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

    // ---- [第3步] 视频取数口（pclk 域）----
    //   来自 vpp_top 新加的 O_raw_*：raw_rgb_d[21]（伽马后原图，不随显示模式变）
    //   + 与之严格同拍的 tvalid/tuser/tlast
    //   I_pclk_rst_n 必须传**视频域的复位**（S_hdmi_rst_n），不要传网络域的 reset
    input  wire        I_pclk,            // S_hdmi_pixel_clk（75MHz）
    input  wire        I_pclk_rst_n,      // S_hdmi_rst_n（低有效）
    input  wire        I_raw_tvalid,
    input  wire        I_raw_tuser,
    input  wire        I_raw_tlast,
    input  wire [23:0] I_raw_tdata,

    // ---- RGMII（YT8511C，BANK22 3.3V）----
    input  wire        phy1_rgmii_rx_clk,
    input  wire        phy1_rgmii_rx_ctl,
    input  wire [3:0]  phy1_rgmii_rx_data,
    output wire        phy1_rgmii_tx_clk,
    output wire        phy1_rgmii_tx_ctl,
    output wire [3:0]  phy1_rgmii_tx_data,
    output wire        phy_reset,

    // ---- 诊断 LED（高电平点亮），顶层直连 led[3:0] ----
    //   net_led[0] D10 = 收到**任何**帧（temac_rx_valid；ARP/ICMP/UDP 都算）
    //   net_led[1] E10 = 协议栈在把帧推给 TEMAC（temac_tx_ready）
    //   net_led[2] C6  = 一整帧 128x72 图像已发完（展宽 ~0.2s，正常应常亮）
    //   net_led[3] D6  = ⚠ ARP 请求没收到回应（展宽）—— 发不出去时亮
    output wire [3:0]  net_led,

    // ---- ★ [P0-5] 板 B 回结果 → 人脸框坐标（pclk 域，供 osd_box_drawer 画框）----
    //   坐标由 udp_clk 域的 rx_result_parser 从 app_rx_* 里解析出来；
    //   res_valid 脉冲同步到 pclk 后产生 O_face_valid，坐标在两次结果之间长期稳定，
    //   画框模块在 O_face_valid 当拍才锁存坐标，所以 pclk 侧直接采样即可。
    output wire        O_face_valid,      // pclk 域单拍脉冲：收到一份新框
    output wire [7:0]  O_face_x,          // 框左上角 X（128x72 检测空间，0~127）
    output wire [7:0]  O_face_y,          // 框左上角 Y（0~71）
    output wire [7:0]  O_face_w,          // 框宽
    output wire [7:0]  O_face_h           // 框高
);

    // ① 器件分支：必须是 "PH1P"
    parameter DEVICE             = "PH1P";
    // ③ 板 A 身份：192.168.240.1 / 端口 1；对端板 B 192.168.240.2 / 端口 2
    //    MAC 用本地管理单播（首字节 bit0=0 且 bit1=1），不能用 01:... 组播当单播源
    parameter LOCAL_UDP_PORT_NUM = 16'h0001;
    parameter LOCAL_IP_ADDRESS   = 32'hC0A8F001;      // 192.168.240.1
    parameter LOCAL_MAC_ADDRESS  = 48'h020000002401;  // 02:00:00:00:24:01
    parameter DST_UDP_PORT_NUM   = 16'h1A0A;          // 6666（第2步用的 2 是低位端口，PC 侧被占过，改成普通端口）
    parameter DST_IP_ADDRESS     = 32'hC0A8F002;      // 192.168.240.2（板 B 的 IP；电脑当板 B 时把 PC 网卡设成 .2）

    // （彩条测试开关 TEST_PATTERN 已于 2026-10-17 撤销：它与"AE 反向调节"问题相关，
    //   原因是 TEST_PATTERN=1 会让 vpp 的 raw 取数链变成死逻辑被综合器剪掉，
    //   整份设计的布局布线随之改变，AE 闭环跑飞。R/G 字节序的修复保留在
    //   pixel_to_bytes.v 里。）


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

    // =====================================================================
    // [第3步] 应用层：取数 -> 降采样 -> 帧门控 -> 跨时钟 FIFO -> 发 20 个 UDP 包
    //   第 2 步的 udp_loopback 已撤掉（它那块 65536x8 的 ram_fifo 实测占 28 块 ERAM，
    //   换成这里 4096 深的图像 FIFO 后省下约 26 块）
    //   第 4 步再在这一层加 收人脸框解析 + 画框
    //
    //   数据通路（除最后写进异步 FIFO 外，全在 pclk 域）：
    //     I_raw_*  (vpp_top raw_rgb_d[21], 1280x720, 22 拍对齐)
    //       -> u_cnn_ds10      10x10 块平均 -> 128x72
    //       -> u_p2b           24bit 拆成 R/G/B 三字节
    //       -> u_img_fifo      写 pclk / 读 udp_clk
    //     udp_clk 域：
    //       -> u_sender        打 20 个 UDP 包（2 字节序号 + 图像字节）
    //
    //   ⚠ 帧门控必须门在**写侧**（pixel_to_bytes 的 I_gate）。
    //     cnn_ds10 靠"10 行条纹双 bank 乒乓"工作，输入被抽掉会让块边界错乱；
    //     门在写侧时 cnn_ds10 一直连续跑，块网格永远与帧对齐。
    // =====================================================================

    // ---- 复位：把网络侧 reset 也同步进 pclk，与视频复位合并 ----
    //   目的：保证"帧门控计数器"和发送侧同时开始 —— 第一个被采集的帧一定是
    //   FIFO 全空时开始的，从而包边界与帧边界永不发生永久错位。
    //   （异步置位/同步释放，避免 pclk 侧的 recovery 问题）
    reg prs1, prs2;
    always @(posedge I_pclk or posedge reset) begin
        if (reset) begin prs1 <= 1'b1; prs2 <= 1'b1; end
        else       begin prs1 <= 1'b0; prs2 <= prs1; end
    end
    wire pclk_arst_n = I_pclk_rst_n & ~prs2;

    // ---- 帧门控：每 6 帧采集 1 帧 ----
    reg [2:0] fdiv;
    reg       gate;
    always @(posedge I_pclk or negedge pclk_arst_n) begin
        if (!pclk_arst_n) begin
            fdiv <= 3'd0;
            gate <= 1'b0;
        end else if (I_raw_tuser) begin
            gate <= (fdiv == 3'd0);                              // 复位后第 1 帧就采
            fdiv <= (fdiv == 3'd5) ? 3'd0 : (fdiv + 3'd1);
        end
    end

    // ---- frame_start 跨时钟：pclk 侧翻转握手 → udp_clk 侧边沿检测 ----
    //   不用单周期脉冲直传：翻转握手对 75M/125M 任意相位都稳
    reg fs_tgl;
    always @(posedge I_pclk or negedge pclk_arst_n) begin
        if (!pclk_arst_n)                 fs_tgl <= 1'b0;
        else if (I_raw_tuser && gate)     fs_tgl <= ~fs_tgl;
    end

    reg fs_s1, fs_s2, fs_s3;
    always @(posedge udp_clk or negedge net_rst_n) begin
        if (!net_rst_n) begin fs_s1 <= 1'b0; fs_s2 <= 1'b0; fs_s3 <= 1'b0; end
        else begin fs_s1 <= fs_tgl; fs_s2 <= fs_s1; fs_s3 <= fs_s2; end
    end
    wire frame_start_pulse = fs_s2 ^ fs_s3;

    // ---- 10x10 块平均降采样：1280x720 -> 128x72 ----
    wire        ds_valid, ds_user, ds_last;
    wire [23:0] ds_data;
    wire [7:0]  ds_x, ds_y;

    cnn_ds10 #(
        .IN_W  (1280), .IN_H  (720),
        .SCALE (10),
        .OUT_W (128),  .OUT_H (72)
    ) u_cnn_ds10 (
        .I_clk    (I_pclk),
        .I_rst_n  (pclk_arst_n),
        .I_tvalid (I_raw_tvalid),
        .I_tuser  (I_raw_tuser),
        .I_tlast  (I_raw_tlast),
        .I_tdata  (I_raw_tdata),
        .O_tvalid (ds_valid),
        .O_tuser  (ds_user),
        .O_tlast  (ds_last),
        .O_tdata  (ds_data),
        .O_x      (ds_x),
        .O_y      (ds_y)
    );

    // =====================================================================
    // ★ [P0-5·对比度拉伸] 2026-10-17 —— 只作用于**以太网支路**
    // ---------------------------------------------------------------------
    //   实测（把板 A 抓到的真人图喂回板 B）：
    //     · 原始图：亮度 96、对比度(std) 26  →  B 分数 0（完全检不出）
    //     · 软件把对比度拉到 2.0~2.5 倍并提亮： B 分数 1609 / 1664（远超门限 615）✓
    //   训练数据（WIDER FACE）是明亮高对比的户外照（std≈82），而室内暗光经
    //   10x10 块平均后只剩 std≈26 —— 对比度不足是"真人认不出"的主因。
    //   这里对送 CNN 的每个通道做逐像素映射 y' = clamp(((y-96)*5)>>1 + 126)：
    //     · cnn_ds10 仍然直连 I_raw_tdata → 视频源没被剪，不会像彩条测试那样
    //       改变整份设计的布局布线（那次把 AE 搞挂了）；
    //     · 只改 pixel_to_bytes 的输入 → 不影响 HDMI / 显示 / AE 回路。
    //   关闭方法：CS_OFF=1（或把 CS_LIFT 设 0 且把增益改成 1）。
    // =====================================================================
    // =====================================================================
    // ★ 2026-10-18 回退说明（按用户要求）
    //   本文件已回退到 2026-10-17 18:00 之前的状态，移除了两处 10-17 深夜起的改动：
    //     ① 固定对比度拉伸  y' = clamp((y-96)*2.5 + 126)
    //        —— 暗光场景有效（分数 0→1631），但亮场景（输入均值>148）会裁剪过曝 ✗
    //     ② R 通道 2 网格像素对齐（RG_ALIGN，G/B 各延迟 2 像素）
    //        —— 软件验证分数 1631→2443，但现场复核不稳定
    //   保留（均为 10-15/10-16 的真修复，与本次回退无关）：
    //     · img_fifo 清空时机（[修复10] 帧相位对齐）
    //     · 结果解析器 u_rx_result_parser 及其 CDC / led[3] 诊断
    //   如需重新启用①②，方案与实测数据见 doc\交接_项目当前状态与回退方案_20261018.md
    // =====================================================================

    // ---- 像素拆字节（R,G,B 三拍）----
    wire [7:0] pb_byte;
    wire       pb_we;
    pixel_to_bytes u_p2b (
        .I_clk   (I_pclk),
        .I_rst_n (pclk_arst_n),
        .I_valid (ds_valid),
        .I_data  (ds_data),
        .I_gate  (gate),
        .O_byte  (pb_byte),
        .O_we    (pb_we)
    );

    // ---- 图像异步 FIFO：写 pclk / 读 udp_clk，4096 x 8，show-ahead ----
    //   复用已验证的 ram_fifo（PH1P 分支走 PH1P_LOGIC_ERAM），
    //   免得再走一次 TD IP Generator 图形界面步骤。约 2 块 ERAM。
    //   深度 4096 >> 单包 1402；生产者平均 2.25 字节/us，消费者 125 字节/us，
    //   实际是生产者限速，FIFO 占用长期低于 ~1800，不会溢出。
    //   ⚠ rdusedw 的位宽是 [ADDR_WIDTH_R:0] = 14 位（含进位），别声明成 13 位
    wire [7:0]  fifo_q;
    wire [15:0] fifo_cnt;
    wire        fifo_full, fifo_empty;
    // ---- [修复4] FIFO 加深到 32768（要能装下一整帧 27 648 字节）----
    //   为什么：发送器必须在"按下协议栈 app-TX 接口"之前就持有整帧，否则中途
    //   要向生产者等数据 -> app_tx_data_valid 长时间举着不放，把协议栈唯一的
    //   TX 通路占死（**实测：ping 0/4 不通，换成 udp_loopback 就 4/4 通**）。
    //   资源：8bit x 32768 = 262 144 bit / ~18.7 Kbit每块 ≈ 14 块 ERAM。
    //   背压阈值 FIFO_HIGH = 31 744（= 32768 - 1024）：
    //     FIFO_HIGH - 27 648 = 4 096 > 0 => 发送期间写侧被挡、占用只减不增
    //     => **绝不读空** => must_stall 永不触发 => tx_valid 撤手干净。
    // =========================================================================
    // 【诊断开关】USE_NO_APP —— 图像通路照跑，但 FIFO 一个字节都不写
    // =========================================================================
    //   0 = 正常：图像写进 img_fifo，发送器会发帧
    //   1 = 诊断：img_we 钉死为 0，fifo_cnt 恒为 0
    //             -> 发送器永远卡在 S_FILL，**永不驱动 app_tx_***
    //             -> 图像通路（cnn_ds10 / pixel_to_bytes / img_fifo）照样例化、照样跑时钟
    //
    //   用来判定：ping 不通到底是
    //     (a) 应用层占用协议栈 app-TX 接口，还是
    //     (b) img_fifo 这条 pclk<->udp_clk 跨时钟路径本身有问题
    //   USE_NO_APP=1 能 ping 通 -> 是 (b)，去查 CDC/SDC，别再改发送器
    //   USE_NO_APP=1 仍不通     -> 是"例化图像通路"这件事本身，继续往下切
    // -------------------------------------------------------------------------
    parameter USE_NO_APP = 1'b0;        // ★ 诊断实验时改成 1'b1

    localparam [15:0] FIFO_HIGH = 16'd31744;
    wire        fifo_block = (fifo_cnt >= FIFO_HIGH);
    wire        img_we   = pb_we & ~fifo_full & ~fifo_block & ~USE_NO_APP;
    wire        fifo_rd;                          // 由 image_feeder 驱动（g_image_sender 分支）

    // =====================================================================
    // ★ [修复10·帧相位对齐] 非采集帧期间清空 img_fifo —— 根治“整帧平移”
    // ---------------------------------------------------------------------
    //   现象（实测 2026-10-13）：板 B / PC 收到的图相对 HDMI 有**固定的整帧
    //   平移**（行 +7、列 −40，即 2808 字节）。把接收图整体平移回去后与 HDMI
    //   完全重合（归一化互相关 −0.09 → +0.76），角色位置姿态逐点吻合。
    //
    //   根因：img_fifo 是**纯流式** FIFO，它的写指针相位和“帧边界”没有任何
    //   绑定关系。上电复位相对视频帧是异步的，第一次开始写时正好落在帧中间，
    //   于是整个 FIFO 的读写相位永久偏了 2808 字节；又因为每帧“写 27648、
    //   读 27648”严格相等，这个偏差恒定不变 —— 表现为**固定的整帧平移**，
    //   而不是随机错乱。（本文件早就生成了 frame_start_pulse，却一直悬空没用。）
    //
    //   修法：门控是“6 帧采 1 帧”，所以每个采集帧之间有 **5 整帧完全没有写入**。
    //   在这段空闲期把 FIFO 清空，每个采集帧就必然从地址 0 开始写，读侧也必然
    //   从帧头开始 -> 相位恒为 0，与板 B 怎么收都无关。
    //
    //   ⚠ 安全性：cnn_ds10 最后一条纹的排空只有 512 拍，而帧间消隐约 49500 拍
    //     （720P 约 30 行），所以“上一采集帧的尾数据”在下一个帧起点之前早就写
    //     完了 —— ~gate 期间清空不会截断任何有效数据。
    //   ⚠ 只碰图像通路，不碰 ping/ARP/协议栈，不影响被动化修复。
    // =====================================================================
    reg fifo_flush_r;
    always @(posedge I_pclk or negedge pclk_arst_n) begin
        if (!pclk_arst_n) fifo_flush_r <= 1'b1;   // 复位期间保持清空
        // ★★ 正式修法（2026-10-15，双板实测定位）：不再"一进 ~gate 就清"，而是推迟到
        //   空闲期的**最后一帧**（fdiv==5）才清。
        //   原写法（fifo_flush_r <= ~gate）在采集帧刚结束、垂直消隐那一瞬就把 img_fifo
        //   复位；而 image_feeder 必须等 fifo_cnt >= NEED_FRAME(27648，整整一帧) 才开喂
        //   → 整帧刚攒满就被擦掉 → feeder 永远等不到 → 板 A 一个字节都发不出去
        //   （现象：A 的 led[1]/led[2] 恒灭，双板联调时 B 收不到任何图）。
        //   推迟之后：feeder 有采集帧之后约 4 个帧周期（≈66ms @60fps）从容读完整帧
        //   （实际只需约 0.22ms），而 FIFO 仍在下一个采集帧之前被清干净
        //   → "每个采集帧都从地址 0 开始写"的相位对齐（修复10 的本意）不丢。
        //   注意判据用 pclk 域的 fdiv，不跨时钟域（比拿 fifo_cnt==0 判断稳）。
        else              fifo_flush_r <= ~gate && (fdiv == 3'd5);
    end
    wire fifo_flush = fifo_flush_r;

    // 2026-10-18 修复【根因#2】：清空那一拍禁止写入。
    //   gate 拉高后 fifo_flush_r 还会多保持 1 拍，而 p2b 已经开始发第一个字节 ->
    //   第一个字节"写进去又被清掉"，整个字节流永久偏 1 字节（表现为通道序被左旋一位）。
    wire img_we_g = img_we & ~fifo_flush;

    ram_fifo #(
        .DEVICE        ("PH1P"),
        .DATA_WIDTH_W  (8),
        .ADDR_WIDTH_W  (15),
        .DATA_WIDTH_R  (8),
        .ADDR_WIDTH_R  (15),
        .SHOW_AHEAD_EN (1)
    ) u_img_fifo (
        .rst        (reset | fifo_flush),   // ★ [修复10] 非采集帧期间清空 -> 帧相位恒为 0
        .di         (pb_byte),
        .clkw       (I_pclk),
        .we         (img_we_g),
        .clkr       (udp_clk),
        .re         (fifo_rd),
        .do         (fifo_q),
        .empty_flag (fifo_empty),
        .full_flag  (fifo_full),
        .wrusedw    (),
        .rdusedw    (fifo_cnt)
    );
    // =========================================================================
    // ★ [修复9·最终修法] 被动化：收到过帧、且延迟足够后，才允许 feeder 喂数据
    // =========================================================================
    //   实测（Wireshark 抓包，2026-10-11 晚）：板子主动发图时，TX 从开机起
    //   **完全死锁，一个帧都不发**（连它自己的 ARP 请求「who has .2」都发不出，
    //   也回不了 PC 的「who has .1」）。
    //   根因：加密协议栈在「app-TX 请求 + ARP 缓存为空」时内部死锁——
    //   应用等 app_tx_ack，协议栈等 ARP 应答，而 ARP 请求因 TX 被占发不出去。
    //   死锁一旦触发就永久卡死，之后连 ping 的 ARP 应答、ICMP 回复全发不出。
    //
    //   而所有验证过能用的实现（回环、板B result_sender）都是**被动发**：
    //   收到包之后才发，对端 MAC 早就学到了，从不触发主动 ARP。
    //
    //   修法：feeder 在「收到过至少一个帧」之前，一字节都不喂给 loopback。
    //   你 ping 板子时，PC 的 ARP 请求（源 IP 就是 .2）会让板子被动学到 .2 的
    //   MAC；再延迟 100ms 确保 ARP 学完，之后 feeder 动手就不用主动 ARP。
    // =========================================================================
    reg        rx_seen;         // 收到过任何帧（temac_rx_valid 已在 udp_clk 域）
    reg [24:0] rx_delay_cnt;    // 100ms @125MHz = 12_500_000 拍（25 位够）
    localparam [24:0] RX_DELAY_MS = 25'd12_500_000;

    always @(posedge udp_clk or negedge net_rst_n) begin
        if (!net_rst_n) begin
            rx_seen      <= 1'b0;
            rx_delay_cnt <= 25'd0;
        end else begin
            // ⚠⚠ temac_rx_valid = rx_client_fifo 的 rd_src_rdy_n，是**低有效**！
            //   0 = 有帧，1 = 空闲。所以"收到帧"要判断 ~temac_rx_valid。
            //   （之前写反了：if(temac_rx_valid) 在空闲时就把 rx_seen 置 1，
            //    导致上电即开喂，死锁照旧。）
            if (~temac_rx_valid) rx_seen <= 1'b1;
            if (rx_seen && (rx_delay_cnt < RX_DELAY_MS))
                rx_delay_cnt <= rx_delay_cnt + 25'd1;
        end
    end
    wire feed_enable = rx_seen && (rx_delay_cnt >= RX_DELAY_MS);

    // USE_NO_APP=1 或 还没收到过帧（被动化）时，占用强制为 0 -> feeder 绝不出手
    wire [15:0] fifo_cnt_g = (USE_NO_APP || !feed_enable) ? 16'd0 : fifo_cnt;

    // =========================================================================
    // 【二分对照开关】USE_LOOPBACK
    // =========================================================================
    //   0 = 第 3 步设计：图像发送器 tx_frame_sender 驱动协议栈的 app TX 接口
    //   1 = 对照实验   ：官方 udp_loopback 驱动协议栈的 app TX 接口
    //
    //   实测结论（2026-10-11）：
    //     第 2 步 bit（udp_loopback）                          ping 4/4 通
    //     第 3 步 v2 bit（tx_frame_sender）                    ping 0/4 不通
    //     对照 bit（本文件 USE_LOOPBACK=1，其余全同第 3 步）   ping 4/4 通 ★
    //   => 元凶是**应用层占用协议栈 app-TX 接口的方式**，与 RGMII / 引脚 /
    //      约束 / cnn_ds10 / 视频取数线全都无关。
    //
    //   ⚠ 用 generate 切换而不是 mux：保证被选中的模块**独占驱动** app_tx_*，
    //     不留任何多余组合逻辑。
    //   ⚠ 未选中的分支里**绝不能 assign** 这些线：arp_no_reply 是协议栈的
    //     output 口，再 assign 一次 TD 就报
    //     "net 'arp_no_reply' is constantly driven from multiple places"。
    // ---------------------------------------------------------------------
    parameter USE_LOOPBACK = 1'b0;      // ★ 对照实验 = 1'b1；第 3 步设计 = 1'b0

    wire snd_frame_done;
    wire snd_tx_abort;
    wire arp_no_reply;

    generate
    if (USE_LOOPBACK) begin : g_loopback

        // ---- 官方 udp_loopback（内部自带 udp_packet_fifo，与第 2 步同源）----
        //   ⚠⚠ `.DEVICE(DEVICE)` 必须传！ udp_loopback.v 自己的 DEVICE 默认值是
        //   "PH1"，而它内部例化 ram_fifo 时用的是它自己的形参（udp_loopback.v:66）。
        //   不覆盖就会展开成 PH1_LOGIC_ERAM —— 那是**别的器件**的原语，在 PH1P35
        //   上是黑盒，TD 直接报：
        //     ERROR: PH1_LOGIC_ERAM(...) is a black box in .../net/ram_fifo.v(267)
        udp_loopback #(
            .DEVICE (DEVICE)
        ) u_loopback (
            .app_rx_clk          (udp_clk),
            .app_tx_clk          (udp_clk),
            .reset               (reset),
            .app_rx_data         (app_rx_data),
            .app_rx_data_valid   (app_rx_data_valid),
            .app_rx_data_length  (app_rx_data_length),
            .udp_tx_ready        (udp_tx_ready),
            .app_tx_ack          (app_tx_ack),
            .app_tx_data         (app_tx_data),
            .app_tx_data_request (app_tx_data_request),
            .app_tx_data_valid   (app_tx_data_valid),
            .udp_data_length     (udp_data_length)
        );
        // 本分支不驱动 snd_frame_done / snd_tx_abort（悬空 -> 常量 0），
        // arp_no_reply 由协议栈驱动。LED 只看 arp_no_reply，无功能影响。

    end else begin : g_image_sender

        // =====================================================================
        // ★ [修复8·最终方案] 图像发送改用「官方 loopback-reuse」结构
        // =====================================================================
        //   实测证明手写 app-TX 状态机（tx_frame_sender）会把加密协议栈卡死
        //   （ping 0/4、ARP 表空），而官方 udp_loopback 的握手是唯一验证过
        //   能用的 app-TX 驱动方式。安路官方的"主动发送"（udp_transmit_test.v
        //   的 TPG 模式）就是：数据发生器 → 灌进 udp_loopback.app_rx_* →
        //   loopback 原样发出去。
        //   这里完全照抄这个结构：
        //     image_feeder 读 img_fifo，拆成 N 个小包，喂给 udp_loopback 的
        //     收口；udp_loopback 的握手一个字都不自己写。
        //   板 A 因此可以继续**主动发图**（loopback 只在 feeder 喂数据时才动
        //   app-TX），板 B 也不需要改。
        // =====================================================================
        wire [7:0]  feed_rx_data;
        wire        feed_rx_valid;
        wire [15:0] feed_rx_length;

        image_feeder u_feeder (
            .clk            (udp_clk),
            .rst            (reset),
            .frame_start    (frame_start_pulse), // ★ [修复10] 采集帧起点，用于复位发帧状态机
            .fifo_rd        (fifo_rd),
            .fifo_q         (fifo_q),
            .fifo_cnt       (fifo_cnt_g),    // USE_NO_APP=1 时恒 0 -> 永不喂
            .fifo_empty     (fifo_empty),
            .loop_rx_data   (feed_rx_data),
            .loop_rx_valid  (feed_rx_valid),
            .loop_rx_length (feed_rx_length),
            .frame_done     (snd_frame_done)
        );

        udp_loopback #(
            .DEVICE (DEVICE)
        ) u_loopback_img (
            .app_rx_clk          (udp_clk),
            .app_tx_clk          (udp_clk),
            .reset               (reset),
            .app_rx_data         (feed_rx_data),
            .app_rx_data_valid   (feed_rx_valid),
            .app_rx_data_length  (feed_rx_length),
            .udp_tx_ready        (udp_tx_ready),
            .app_tx_ack          (app_tx_ack),
            .app_tx_data         (app_tx_data),
            .app_tx_data_request (app_tx_data_request),
            .app_tx_data_valid   (app_tx_data_valid),
            .udp_data_length     (udp_data_length)
        );

        // 本分支没有 tx_frame_sender 了，snd_tx_abort 悬空（常量 0）
        // arp_no_reply 由协议栈驱动，不在此赋值。
    end
    endgenerate


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
        .arp_request_no_reply_error (arp_no_reply)
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

    // =====================================================================
    // ★ [P0-5] 收板 B 的结果包 → 解析出人脸框 → 跨到 pclk 给画框模块
    // =====================================================================
    //   协议栈把"目标是本机 UDP 端口 1"的载荷送到 app_rx_*（逐字节 valid）。
    //   结果包前 9 字节 = AA 55 valid x1 y1 w h score[15:8] score[7:0]，之后分三种：
    //     · 旧 10 字节包：offset 9 = 0D（帧尾）
    //     · 板 B 14 字节调试版：offset 9 或 13 = 0D（帧尾）
    //     · 板 B 现行 149 字节包：offset 9 = pixR，offset 148 = 0D（帧尾）
    //   rx_result_parser 以 AA 55 帧头为锚点、按字节计数分帧（rx_len 只当"包尾在哪"
    //   的提示），只有"帧尾 = 0D + valid = 1 + score >= 615"三条同时满足才提交坐标并
    //   出脉冲；一个帧头只提交一次，提交后跳过本包剩余字节，诊断字节里的 AA 55 不会
    //   被误当帧头。
    //   ⚠ 之前那版用 rx_len 白名单（只认 10 / 149）在这块板上一个结果都没提交过，
    //     表现为"绿框和坐标全都不显示"——app_rx_data_length 在首字节时刻不可靠。
    //   ⚠ 被拒绝的包不改动已锁存坐标 → 画框模块的"保持"才有意义（漏检时留旧框）。
    wire        res_valid_udp;
    wire [7:0]  fx1, fy1, fw, fh;
    wire [15:0] fscore;                    // 当前只画框，分数暂时不上（留作日后显示）
    wire        saw_aa;                    // 诊断：收到过 0xAA

    rx_result_parser u_rxp (
        .clk       (udp_clk),
        .rst       (reset),
        .rx_d      (app_rx_data),
        .rx_v      (app_rx_data_valid),
        .rx_len    (app_rx_data_length),
        .res_valid (res_valid_udp),
        .x1        (fx1),
        .y1        (fy1),
        .w         (fw),
        .h         (fh),
        .score     (fscore),
        .saw_aa    (saw_aa)
    );

    // ⚠ res_valid_udp 只有 1 个 udp_clk 拍（8ns），而 pclk 是 75MHz（13.3ns）——
    //   把 8ns 脉冲直接拿去采样会**漏掉**（相位不利时整拍落空，画框时有时无甚至全无）。
    //   所以先在 udp 域把它展宽到 16 拍（128ns），再同步到 pclk 做边沿检测。
    reg [4:0] rv_stretch;
    always @(posedge udp_clk or posedge reset) begin
        if (reset)                   rv_stretch <= 5'd0;
        else if (res_valid_udp)      rv_stretch <= 5'd16;
        else if (rv_stretch != 5'd0) rv_stretch <= rv_stretch - 5'd1;
    end
    wire res_valid_wide = (rv_stretch != 5'd0);

    // 展宽后的电平同步到 pclk（两级）+ 上升沿检测。坐标变化频率 ≤10Hz、
    // 两次结果之间长期不变，pclk 侧直接采样（画框模块只在 valid 当拍锁存坐标）。
    reg rv1, rv2, rv3;
    always @(posedge I_pclk or negedge I_pclk_rst_n) begin
        if (!I_pclk_rst_n) begin rv1 <= 1'b0; rv2 <= 1'b0; rv3 <= 1'b0; end
        else               begin rv1 <= res_valid_wide; rv2 <= rv1; rv3 <= rv2; end
    end
    assign O_face_valid = rv2 & ~rv3;      // pclk 域单拍脉冲
    assign O_face_x     = fx1;
    assign O_face_y     = fy1;
    assign O_face_w     = fw;
    assign O_face_h     = fh;

    // ---------------------------------------------------------------------
    // 诊断 LED（高电平点亮）—— 顶层再映射成 led[3:0]
    //
    //   顶层映射：led = { net_led[2], net_led[1], S_pll_lock, net_led[0] }
    //     led[0] D10 = net_led[0]  PHY 复位已释放（链路可自协商）
    //     led[1] E10 = S_pll_lock  视频 PLL 已锁定
    //     led[2] C6  = net_led[1]  一整帧 128x72 已发完（展宽 ~0.2s）
    //     led[3] D6  = net_led[2]  ⚠ ARP 请求没收到回应（展宽）—— 发不出去时亮
    //
    //   判读：
    //     正常工作            -> led[2] 常亮（每 6 帧发一帧 ≈99ms < 展宽 200ms，所以常亮）
    //                             led[3] 灭
    //     发不出去（ARP 不通）-> led[2] 灭、led[3] 亮
    //     led[3] 亮 = 板 A 解析不到 192.168.240.2 的 MAC
    //                 -> 对面那台 .2 的设备不在、网线不通、或 PC 网卡没设成 .2
    //     （snd_tx_abort 也是"发送失败"的指示，但 4 个灯不够分，
    //       暂时不上灯；若 led[2] 灭而 led[3] 也不亮，再把它换上来。）
    // ---------------------------------------------------------------------
    reg [24:0] tx_led_cnt;
    always @(posedge udp_clk or negedge net_rst_n) begin
        if (!net_rst_n)                                  tx_led_cnt <= 25'd0;
        else if (snd_frame_done)                         tx_led_cnt <= 25'd25_000_000;
        else if (tx_led_cnt != 25'd0)                    tx_led_cnt <= tx_led_cnt - 25'd1;
    end

    // ARP 无回应：可能是脉冲也可能是电平，两种都用"置满、慢慢减"来展宽
    reg [24:0] arp_led_cnt;
    always @(posedge udp_clk or negedge net_rst_n) begin
        if (!net_rst_n)                                  arp_led_cnt <= 25'd0;
        else if (arp_no_reply)                           arp_led_cnt <= 25'd25_000_000;
        else if (arp_led_cnt != 25'd0)                   arp_led_cnt <= arp_led_cnt - 25'd1;
    end

    // ---- [修复3] 这四个灯改成"能真正切开链路"的信号 ----
    //   原来 net_led[0]=phy_reset、net_led[1]=收到UDP载荷、net_led[2]=ARP失败，
    //   只有 3 位（顶层 led[1] 给的是视频 PLL 锁）。问题：
    //     * phy_reset 只能说明"PHY 复位释放了"，不含任何收发信息；
    //     * "收到 UDP 载荷"用的是 app_rx_data_valid —— 它是**协议栈校验通过、
    //       且目标是本机 UDP 端口 1** 的载荷，ARP/ICMP 一律不计。
    //       所以它灭**不能**推出"PC 的包没到板子"（这条判读曾经把排查带偏）。
    //   实测（2026-10-11）：v2 上 LED1(收到帧) 与 LED4(ARP失败) 常亮，
    //   说明接收侧有帧在 FIFO 里喂不进协议栈 —— 正是 app-TX 接口被占死的表现。
    // ---------------------------------------------------------------------
    // 收到**任何**帧：用 temac_rx_valid（rx_client_fifo 已把它同步到 udp_clk 域，
    //   = ~rd_src_rdy_n，任何到达 MAC 的帧（ARP/ICMP/UDP）都会拉动它）
    reg [24:0] rx_led_cnt;
    always @(posedge udp_clk or negedge net_rst_n) begin
        if (!net_rst_n)                                  rx_led_cnt <= 25'd0;
        else if (~temac_rx_valid)                        rx_led_cnt <= 25'd25_000_000; // 0=有帧
        else if (rx_led_cnt != 25'd0)                    rx_led_cnt <= rx_led_cnt - 25'd1;
    end

    // 应用层有没有在向协议栈申请发送（app_tx_request）
    //   ★ 这是当前最需要看的信号：
    //     常亮 = 应用层一直占着协议栈的 TX 接口（疑似正是 ping 不通的原因）
    //     灭   = 应用层没占用，方向要换
    //   （原来这里接 temac_tx_ready，信息量不如这个）
    reg [24:0] txact_led_cnt;
    always @(posedge udp_clk or negedge net_rst_n) begin
        if (!net_rst_n)                                  txact_led_cnt <= 25'd0;
        else if (app_tx_data_request)                    txact_led_cnt <= 25'd25_000_000;
        else if (txact_led_cnt != 25'd0)                 txact_led_cnt <= txact_led_cnt - 25'd1;
    end

    assign net_led[0] = (rx_led_cnt    != 25'd0);   // 收到**任何**帧（ARP/ICMP/UDP 都算）
    assign net_led[1] = (txact_led_cnt != 25'd0);   // ★ 应用层在申请发送（app_tx_request）
    assign net_led[2] = (tx_led_cnt    != 25'd0);   // 一整帧 128x72 已发完（展宽 ~0.2s）
    // ---- ★★ 临时四态诊断（2026-10-15 v2，查"没绿框"）----
    //   常亮        = 解析成功过（res_valid 出现过）→ 绿框应当稳定出现
    //   快闪(~12Hz) = 收到过 0xAA，但没能凑齐 AA 55 帧头
    //   慢闪(~4Hz)  = app_rx 有载荷，却连一个 0xAA 都没见着（送来的不是板 B 的载荷）
    //   灭          = app_rx 压根没动静
    //   恢复：把下面这段换回   assign net_led[3] = (arp_led_cnt != 25'd0);
    reg        res_seen, aa_seen;
    reg [24:0] rxact_cnt;
    reg [23:0] blink_cnt;
    reg        blink;
    always @(posedge udp_clk or posedge reset) begin
        if (reset) begin
            res_seen  <= 1'b0;
            aa_seen   <= 1'b0;
            rxact_cnt <= 25'd0;
            blink_cnt <= 24'd0;
            blink     <= 1'b0;
        end else begin
            if (res_valid_udp)           res_seen  <= 1'b1;
            if (saw_aa)                  aa_seen   <= 1'b1;
            if (app_rx_data_valid)       rxact_cnt <= 25'd25_000_000;   // 0.2s 展宽
            else if (rxact_cnt != 25'd0) rxact_cnt <= rxact_cnt - 25'd1;
            // 见过 0xAA → 快闪；没见过 → 慢闪（一眼能分开）
            if (blink_cnt == 24'd0) begin
                blink_cnt <= aa_seen ? 24'd5_000_000 : 24'd16_000_000;
                blink     <= ~blink;
            end else begin
                blink_cnt <= blink_cnt - 24'd1;
            end
        end
    end
    assign net_led[3] = res_seen ? 1'b1 : ((rxact_cnt != 25'd0) ? blink : 1'b0);

endmodule
