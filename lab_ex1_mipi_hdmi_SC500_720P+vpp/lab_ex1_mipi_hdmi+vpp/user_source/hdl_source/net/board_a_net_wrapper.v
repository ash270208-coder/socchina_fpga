`timescale 1ns / 1ps
//=============================================================================
// board_a_net_wrapper.v —— 板 A 以太网链路包装（第 2 步：纯网络 + UDP 回环）
//
// 目的：在「MIPI 摄像头 + HDMI 显示」主工程里接进千兆网口，先只做
//       ping 通 + UDP 原样回送，验证 RGMII / PHY / TEMAC / UDP-IP 栈全部正常。
//       本步**完全不碰视频链路**：wrapper 不读任何视频信号，也不驱动任何视频信号。
//
// 例化端口逐行对照已在实机验证过的 cnn_boardB/src/net/board_b_top.v:344-486，
// 三处板 A 专属改动：
//   ① DEVICE 用 "PH1P"（不是 "PH1" / "EG4"）
//      —— 见 net/ODDR.v / net/IDDR.v：只有 "PH1P" 分支才走
//         PH1P_LOGIC_HD_ODDR / PH1P_LOGIC_HD_IDDR（HDIO 原语）。
//         RGMII 引脚在 HDIO 上，用错分支引脚直接不工作。
//         docs/HX1P35A双板以太网级联实施指导.md §7.9 写的是 "PH1"，**不要照抄**。
//   ② 复位不占按键：由顶层 pll_por 的 10ms 上电复位驱动（net_arst = ~por_arst_n），
//      板 B 用的 key1 在这里没有对应物，也不需要。
//   ③ MAC / IP / UDP 端口按板 A 身份（.1 / 端口 1）。
//
// 应用层（第 2 步）用的是安路 APUG013 官方 udp_loopback + ram_fifo，**不是**
// docs/板A以太网改造_实施计划.md §5.2 里那段 4 行组合逻辑回环。原因：
//   udp_ip_protocol_stack 的应用侧 TX 是 request -> 等 ack -> 再连续喂数据 的握手，
//   而 app_rx_data_valid 是**逐字节**的流有效。把 app_tx_data_valid 直接组合接到
//   app_rx_data_valid，等于不等 ack 就往 TX 口灌数据，官方 udp_loopback 里那句
//   `(~app_rx_data_valid)` 的等待条件正说明必须先把整包收进 FIFO 再发。
//   取“别人能用、我不能用就先去对照能用的工程”这条纪律，这里用官方模块。
//   代价：ram_fifo 深度 2^16 x 8bit ≈ 26 块 ERAM；第 3 步换成图像通路后这块 FIFO
//         会整个删掉，ERAM 会还回来。
//
// 参考：
//   docs/A板以太网改造方案.md §5~§7
//   docs/板A以太网改造_实施计划.md §5（并已修正其上两处：DEVICE 必须 PH1P；回环用官方模块）
//   cnn_boardB/src/net/board_b_top.v（实机验证过的例化基准）
//=============================================================================
module board_a_net_wrapper (
    input  wire        clk_50m,           // C4 板载 50MHz 晶振（I_sys_clk）
    input  wire        por_arst_n,        // 来自 pll_por：低有效 10ms 上电复位

    // ---- RGMII（YT8511C，BANK22 3.3V）----
    input  wire        phy1_rgmii_rx_clk,
    input  wire        phy1_rgmii_rx_ctl,
    input  wire [3:0]  phy1_rgmii_rx_data,
    output wire        phy1_rgmii_tx_clk,
    output wire        phy1_rgmii_tx_ctl,
    output wire [3:0]  phy1_rgmii_tx_data,
    output wire        phy_reset,

    // ---- 诊断 LED（高电平点亮），顶层再映射到 led[3:0] ----
    //   net_led[0] = PHY 复位已释放（≈ 链路可自协商）
    //   net_led[1] = 收到 UDP 载荷（展宽，便于肉眼观察）
    //   net_led[2] = 心跳
    output wire [2:0]  net_led
);

    // ① 器件分支：必须是 "PH1P"
    parameter DEVICE             = "PH1P";
    // ③ 板 A 身份：192.168.240.1 / 端口 1；对端板 B 192.168.240.2 / 端口 2
    //    MAC 用本地管理单播（首字节 bit0=0 且 bit1=1），不能用 01:... 组播当单播源
    parameter LOCAL_UDP_PORT_NUM = 16'h0001;
    parameter LOCAL_IP_ADDRESS   = 32'hC0A8F001;      // 192.168.240.1
    parameter LOCAL_MAC_ADDRESS  = 48'h020000002401;  // 02:00:00:00:24:01
    parameter DST_UDP_PORT_NUM   = 16'h0002;
    parameter DST_IP_ADDRESS     = 32'hC0A8F002;      // 192.168.240.2

    // ---------------------------------------------------------------------
    // 复位：全部由 pll_por 的 10ms 上电复位驱动，不依赖任何引脚
    // ---------------------------------------------------------------------
    wire net_rst_n = por_arst_n;
    wire net_arst  = ~net_rst_n;

    wire reset;          // 送给网络逻辑的高有效复位
    wire reset_reg;      // clk_gen_rst_gen 的 PLL 失锁复位（rst_out = !lock）
    reg  [7:0] soft_reset_cnt = 8'hFF;

    assign reset = net_arst || reset_reg || (soft_reset_cnt != 8'd0);

    // ---------------------------------------------------------------------
    // 协议栈应用侧信号
    // ---------------------------------------------------------------------
    wire [7:0]  app_rx_data;
    wire        app_rx_data_valid;
    wire [15:0] app_rx_data_length;
    wire        udp_tx_ready;
    wire        app_tx_ack;
    wire        app_tx_data_request;
    wire        app_tx_data_valid;
    wire [7:0]  app_tx_data;
    wire [15:0] udp_data_length;

    // ---------------------------------------------------------------------
    // TEMAC / RGMII 侧信号
    // ---------------------------------------------------------------------
    wire [1:0]  TRI_speed = 2'b10;                    // 千兆
    wire [19:0] mac_cfg_vector;
    wire [47:0] unicast_address;
    wire        temac_tx_ready, temac_tx_valid, temac_tx_sof, temac_tx_eof;
    wire [7:0]  temac_tx_data;
    wire        temac_rx_ready, temac_rx_valid, temac_rx_sof, temac_rx_eof;
    wire [7:0]  temac_rx_data;
    wire        rx_correct_frame, rx_error_frame;
    wire        rx_clk_int, rx_clk_en_int, tx_clk_int, tx_clk_en_int;
    wire        rx_valid, tx_valid, tx_rdy, tx_collision, tx_retransmit;
    wire [7:0]  rx_data, tx_data;

    wire        temac_clk, udp_clk, temac_clk90;
    wire        clk_125_out, clk_12_5_out, clk_1_25_out, clk_25_out;

    assign unicast_address = { LOCAL_MAC_ADDRESS[7:0],   LOCAL_MAC_ADDRESS[15:8],
                               LOCAL_MAC_ADDRESS[23:16], LOCAL_MAC_ADDRESS[31:24],
                               LOCAL_MAC_ADDRESS[39:32], LOCAL_MAC_ADDRESS[47:40] };
    assign mac_cfg_vector  = {1'b0, 2'b00, TRI_speed, 8'b00100010, 7'b0100010};

    // ---------------------------------------------------------------------
    // PHY 硬件复位：YT8511C 要求 RESET_N 低电平 ≥10ms
    //   clk_25_out = 25MHz -> 250_000 拍 = 10ms
    //   ⚠ 不要照抄实施指导文档 §5.6/§7.9 的 8 位计数器（256 拍 ≈ 2.5µs），太短。
    //   注意 phy_reset_cnt 只在 por_arst_n 释放后才开始数，且计数期间 phy_reset
    //   仍为低 —— 所以 PHY 实际被拉了 (10ms POR) + (10ms 计数) = 20ms，满足要求。
    // ---------------------------------------------------------------------
    reg [19:0] phy_reset_cnt = 20'd0;

    always @(posedge clk_25_out or negedge net_rst_n) begin
        if (!net_rst_n)
            phy_reset_cnt <= 20'd0;
        else if (phy_reset_cnt < 20'd250000)
            phy_reset_cnt <= phy_reset_cnt + 20'd1;
    end
    assign phy_reset = (phy_reset_cnt >= 20'd250000);

    always @(posedge udp_clk or negedge net_rst_n) begin
        if (!net_rst_n)                   soft_reset_cnt <= 8'hFF;
        else if (soft_reset_cnt != 8'd0)  soft_reset_cnt <= soft_reset_cnt - 8'd1;
    end

    // ---------------------------------------------------------------------
    // 独立网络 PLL：50MHz -> 125/125/12.5/25/125@90° MHz
    //   与视频 PLL（顶层 u_PLL）完全独立，视频链路时序不受影响。
    //   reset 接 net_arst：上电期间网络 PLL 被复位保持，PLL 起来之前
    //   clk_25_out 不翻转 -> phy_reset 恒低 -> PHY 保持复位。上电顺序正确。
    // ---------------------------------------------------------------------
    clk_gen_rst_gen #(.DEVICE(DEVICE)) u_clk_gen (
        .reset        ( net_arst    ),
        .clk_in       ( clk_50m     ),
        .rst_out      ( reset_reg   ),
        .clk_125_out0 ( temac_clk   ),
        .clk_125_out1 ( clk_125_out ),
        .clk_125_out2 ( temac_clk90 ),
        .clk_12_5_out ( clk_12_5_out),
        .clk_1_25_out ( clk_1_25_out),
        .clk_25_out   ( clk_25_out  )
    );

    // ---------------------------------------------------------------------
    // 应用层：安路官方 UDP 原样回环（收什么发什么）
    //   第 3 步会换成 取数 -> 降采样 -> 帧门控 -> 跨时钟 FIFO -> 发 20 个 UDP 包
    //   第 4 步再加 收人脸框解析
    // ---------------------------------------------------------------------
    udp_loopback #(
        .DEVICE (DEVICE)
    ) u_loopback (
        .app_rx_clk         (udp_clk),
        .app_tx_clk         (udp_clk),
        .reset              (reset),
        .app_rx_data        (app_rx_data),
        .app_rx_data_valid  (app_rx_data_valid),
        .app_rx_data_length (app_rx_data_length),
        .udp_tx_ready       (udp_tx_ready),
        .app_tx_ack         (app_tx_ack),
        .app_tx_data        (app_tx_data),
        .app_tx_data_request(app_tx_data_request),
        .app_tx_data_valid  (app_tx_data_valid),
        .udp_data_length    (udp_data_length)
    );

    // ---------------------------------------------------------------------
    // UDP/IP 协议栈（安路加密 IP，不可修改，只能例化）
    // ---------------------------------------------------------------------
    udp_ip_protocol_stack #(
        .DEVICE             (DEVICE),
        .LOCAL_UDP_PORT_NUM (LOCAL_UDP_PORT_NUM),
        .LOCAL_IP_ADDRESS   (LOCAL_IP_ADDRESS),
        .LOCAL_MAC_ADDRESS  (LOCAL_MAC_ADDRESS)
    ) u_stack (
        .udp_rx_clk         (udp_clk),
        .udp_tx_clk         (udp_clk),
        .reset              (reset),
        .udp2app_tx_ready   (udp_tx_ready),
        .udp2app_tx_ack     (app_tx_ack),
        .app_tx_request     (app_tx_data_request),
        .app_tx_data_valid  (app_tx_data_valid),
        .app_tx_data        (app_tx_data),
        .app_tx_data_length (udp_data_length),
        .app_tx_dst_port    (DST_UDP_PORT_NUM),
        .ip_tx_dst_address  (DST_IP_ADDRESS),
        .input_local_udp_port_num       (1'b0),
        .input_local_udp_port_num_valid (1'b0),
        .input_local_ip_address         (1'b0),
        .input_local_ip_address_valid   (1'b0),
        .app_rx_data_valid  (app_rx_data_valid),
        .app_rx_data        (app_rx_data),
        .app_rx_data_length (app_rx_data_length),
        .app_rx_port_num    (),
        .temac_rx_ready     (temac_rx_ready),
        .temac_rx_valid     (~temac_rx_valid),
        .temac_rx_data      (temac_rx_data),
        .temac_rx_sof       (temac_rx_sof),
        .temac_rx_eof       (temac_rx_eof),
        .temac_tx_ready     (temac_tx_ready),
        .temac_tx_valid     (temac_tx_valid),
        .temac_tx_data      (temac_tx_data),
        .temac_tx_sof       (temac_tx_sof),
        .temac_tx_eof       (temac_tx_eof),
        .ip_rx_error        (),
        .arp_request_no_reply_error ()
    );

    // ---------------------------------------------------------------------
    // TEMAC（MAC 层）+ RGMII
    // ---------------------------------------------------------------------
    temac_block #(.DEVICE(DEVICE)) u_trimac (
        .reset              (reset),
        .gtx_clk            (temac_clk),
        .gtx_clk_90         (temac_clk90),
        .rx_clk             (rx_clk_int),
        .rx_clk_en          (rx_clk_en_int),
        .rx_data            (rx_data),
        .rx_data_valid      (rx_valid),
        .rx_correct_frame   (rx_correct_frame),
        .rx_error_frame     (rx_error_frame),
        .rx_status_vector   (),
        .rx_status_vld      (),
        .tx_clk             (tx_clk_int),
        .tx_clk_en          (tx_clk_en_int),
        .tx_data            (tx_data),
        .tx_data_en         (tx_valid),
        .tx_rdy             (tx_rdy),
        .tx_stop            (1'b0),
        .tx_collision       (tx_collision),
        .tx_retransmit      (tx_retransmit),
        .tx_ifg_val         (8'h00),
        .tx_status_vector   (),
        .tx_status_vld      (),
        .pause_req          (1'b0),
        .pause_val          (16'h0),
        .pause_source_addr  (48'h5AF1F2F3F4F5),
        .unicast_address    (unicast_address),
        .mac_cfg_vector     (mac_cfg_vector),
        .rgmii_txd          (phy1_rgmii_tx_data),
        .rgmii_tx_ctl       (phy1_rgmii_tx_ctl),
        .rgmii_txc          (phy1_rgmii_tx_clk),
        .rgmii_rxd          (phy1_rgmii_rx_data),
        .rgmii_rx_ctl       (phy1_rgmii_rx_ctl),
        .rgmii_rxc          (phy1_rgmii_rx_clk),
        .inband_link_status (),
        .inband_clock_speed (),
        .inband_duplex_status ()
    );

    // ---------------------------------------------------------------------
    // 三速时钟选择（当前 TRI_speed 固定千兆；保留三速是为了与参考设计一致）
    // ---------------------------------------------------------------------
    udp_clk_gen #(.DEVICE(DEVICE)) u_clkgen (
        .reset       ( net_arst     ),
        .tri_speed   ( TRI_speed    ),
        .clk_125_in  ( clk_125_out  ),
        .clk_12_5_in ( clk_12_5_out ),
        .clk_1_25_in ( clk_1_25_out ),
        .udp_clk_out ( udp_clk      )
    );

    // ---------------------------------------------------------------------
    // TX / RX 跨时钟 FIFO（TEMAC 的 TX/RX 时钟 <-> udp_clk）
    // ---------------------------------------------------------------------
    tx_client_fifo #(.DEVICE(DEVICE), .ADDR_WIDTH(11)) u_tx_fifo (
        .rd_clk        (tx_clk_int),
        .rd_sreset     (reset),
        .rd_enable     (tx_clk_en_int),
        .tx_data       (tx_data),
        .tx_data_valid (tx_valid),
        .tx_ack        (tx_rdy),
        .tx_collision  (tx_collision),
        .tx_retransmit (tx_retransmit),
        .overflow      (),
        .wr_clk        (udp_clk),
        .wr_sreset     (reset),
        .wr_data       (temac_tx_data),
        .wr_sof_n      (temac_tx_sof),
        .wr_eof_n      (temac_tx_eof),
        .wr_src_rdy_n  (temac_tx_valid),
        .wr_dst_rdy_n  (temac_tx_ready),
        .wr_fifo_status()
    );

    rx_client_fifo #(.DEVICE(DEVICE), .ADDR_WIDTH(11)) u_rx_fifo (
        .wr_clk        (rx_clk_int),
        .wr_enable     (rx_clk_en_int),
        .wr_sreset     (reset),
        .rx_data       (rx_data),
        .rx_data_valid (rx_valid),
        .rx_good_frame (rx_correct_frame),
        .rx_bad_frame  (rx_error_frame),
        .overflow      (),
        .rd_clk        (udp_clk),
        .rd_sreset     (reset),
        .rd_data_out   (temac_rx_data),
        .rd_sof_n      (temac_rx_sof),
        .rd_eof_n      (temac_rx_eof),
        .rd_src_rdy_n  (temac_rx_valid),
        .rd_dst_rdy_n  (temac_rx_ready),
        .rx_fifo_status()
    );

    // ---------------------------------------------------------------------
    // 诊断 LED（高电平点亮）
    //   app_rx_data_valid 是逐字节脉冲，直接点灯看不见 -> 展宽成 ~0.2s
    // ---------------------------------------------------------------------
    reg [24:0] rx_led_cnt;
    always @(posedge udp_clk or negedge net_rst_n) begin
        if (!net_rst_n)                                  rx_led_cnt <= 25'd0;
        else if (app_rx_data_valid)                      rx_led_cnt <= 25'd25_000_000;
        else if (rx_led_cnt != 25'd0)                    rx_led_cnt <= rx_led_cnt - 25'd1;
    end

    reg [26:0] hb_cnt;
    always @(posedge udp_clk or negedge net_rst_n) begin
        if (!net_rst_n) hb_cnt <= 27'd0;
        else            hb_cnt <= hb_cnt + 27'd1;
    end

    assign net_led[0] = phy_reset;               // PHY 复位已释放 = 链路就绪
    assign net_led[1] = (rx_led_cnt != 25'd0);   // 收到 UDP 载荷（展宽 ~0.2s）
    assign net_led[2] = hb_cnt[26];              // 心跳 ~0.54s 翻转

endmodule
