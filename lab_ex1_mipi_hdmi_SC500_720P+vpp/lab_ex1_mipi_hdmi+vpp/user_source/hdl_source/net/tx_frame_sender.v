`timescale 1ns / 1ps
//=============================================================================
// tx_frame_sender.v —— 把一帧 128x72 RGB 图像按 20 个 UDP 包发给板 B
//
// ★ v2（2026-10-11 修正）—— 相对 v1 修了三个把网口和图像通路都搞坏的问题：
//
// 【修正 1】删掉 S_REQ 里的 1ms ack 超时（v1 的 ACK_TIMEOUT / O_tx_abort）
//   为什么要删：
//     `udp_ip_protocol_stack` 的 ARP 参数是
//         ARP_REQUEST_NUM   = 3
//         ARP_REQUEST_DELAY = 27'h0ffffff (=16777215 拍 @125MHz ≈ 134ms)
//     也就是说一次 ARP 解析最长要 ~400ms 才判失败。而 ping/ARP 回复和我们的
//     UDP 包**共用同一条应用侧 TX 通路**。
//     v1 每 1ms 就把 app_tx_data_request 拉低一次（超时"放弃本帧"），
//     等于在每个 ARP 窗口里把请求线来回抖 400 次；实测（见
//     sim/tb_s3_sender.v）v1 在 ack 不来时 tx_request 的占空比是 ~94% 且
//     每 1ms 必然出现一次下拉沿。协议栈的请求/应答握手被这种抖动反复打断，
//     ARP 永远解析不完 -> 报 arp_request_no_reply_error -> 对外一个包都发不出去。
//   v1 的出发点（"怕把 TX 通路占死"）是错的：看板 B 上实机验证过的
//     `cnn_boardB/src/net/result_sender.v` 和官方 `udp_loopback.v`，
//     两者都是**一直拉着 request 直到收到 ack**，不做任何超时放弃。
//     正确的协议栈用法就是这样：它自己在内部仲裁 ARP 回复 / ICMP 回复 / 应用包。
//   所以 v2 与板 B / 官方一致：request 从拉高起一直保持到 ack。
//   （保留 O_tx_abort 端口以便兼容，但永远不产生脉冲；真要留一个保险，
//     应放宽到秒级，绝不是 1ms。本版直接去掉，最稳。）
//
// 【修正 2】发送中途 FIFO 读空时必须**停住**，不能继续往下喂
//   为什么要停：
//     ram_fifo.v:175 `fifo_re = re & !fifo_empty` —— 读空时读地址不再走，
//     `do` 保持旧值。v1 在 S_SEND 里无条件 `O_fifo_rd<=1` 并且无条件
//     `O_tx_data <= I_fifo_q`，所以在"生产者供不上"的窗口里会**把同一个字节
//     重复发很多次**，整包长度还是对的、内容全错。
//     实测（sim/tb_s3_sender.v 的旧版对照）确认了这一点。
//     v2 在"S_SEND 且 idx>=2 且 fifo_empty"时冻结：不推进 idx、不抬 fifo_rd、
//     保持 O_tx_data 不变，一直等到 FIFO 有数据再继续。
//     这样发送速率自动跟着生产者走，既不会重复字节，也不会把正在发的包截断。
//
// 【修正 3】帧同步：只在 frame_start 启动，启动前要求 FIFO 里已有 ≥1 包
//   v1 在 S_FILL 里一旦 fifo_cnt>=1400 就发，而生产者（cnn_ds10 每 4 拍 1 字节
//   = 18.75MB/s）远快于 20 个包按 100ms 一帧的消耗速度，FIFO 长期饱和，
//   于是发送侧变成"自由奔跑"、包边界与帧边界完全脱钩（每帧只发到前 1400 字节，
//   其余 26KB 被溢出丢弃）。v2 保留 S_FILL 的"攒够一整包再发"，
//   配合 write 侧的 backpressure（见 board_a_net_wrapper.v 的 fifo_block），
//   让生产者不能超过 FIFO 容量，帧边界才能对齐。
//
// 包格式（板 B 已钉死）：
//   UDP 载荷 = [seq_hi, seq_lo] + 图像字节
//     包 0~18：2 + 1400 = 1402 字节
//     包 19  ：2 + 1048 = 1050 字节   合计 27 648 = 128×72×3 ✓
//
// 首字节时序（务必保持）：在收到 ack 的那一拍就把字节 0 装到 O_tx_data 并拉高
//   O_tx_valid，与板 B `result_sender.v:179` 的写法一致。
//=============================================================================
module tx_frame_sender (
    input  wire        I_clk,          // udp_clk（125MHz）
    input  wire        I_rst,          // 高有效同步复位
    input  wire        I_frame_start,  // udp_clk 域单周期脉冲（被门控帧的起点）
    // ---- show-ahead 异步 FIFO 读侧 ----
    output reg         O_fifo_rd,
    input  wire [7:0]  I_fifo_q,
    input  wire [15:0] I_fifo_cnt,     // rdusedw（= ADDR_WIDTH_R + 1 位；深 32768 时是 16 位）
    input  wire        I_fifo_empty,   // ★ [修复2] 读空时必须停住，否则重复发同一字节
    // ---- UDP 协议栈应用侧 ----
    input  wire        I_tx_ready,     // udp2app_tx_ready（保留，仅用于诊断）
    input  wire        I_tx_ack,       // udp2app_tx_ack
    output reg         O_tx_request,   // app_tx_request
    output reg         O_tx_valid,     // app_tx_data_valid
    output reg  [7:0]  O_tx_data,      // app_tx_data
    output reg  [15:0] O_tx_length,    // app_tx_data_length（含 2 字节序号的载荷总长）
    // ---- 诊断/状态 ----
    output reg         O_busy,         // 一帧 20 包发送期间为高
    output reg         O_frame_done,   // 一帧发完的单周期脉冲
    output reg         O_tx_abort      // 兼容保留：v2 起永远为 0
);
    // ★ [修复4] 发一帧之前要求 FIFO 里已经攒够的字节数。
    //   由上层按 FIFO 深度传进来：
    //     FIFO 深 32768 -> 传 27648（= 一整帧）→ **按下 TX 接口时整帧已就位**
    //     FIFO 深  4096 -> 传  1400（= 一整包）→ 会中途读空，靠 must_stall 兜
    //   为什么必须"整帧就位"：见文件头 §修正4。
    parameter [15:0] NEED_FRAME = 16'd1400;

    // =========================================================================
    // ★ [修复6] 上电静默期 + ack 超时 + 失败重试 —— 三者缺一不可
    // =========================================================================
    //   实测（2026-10-11，板 A）：
    //     USE_NO_APP=1（发送器从不驱动 app_tx_*）-> ping 4/4 通，ARP 表正常
    //     USE_NO_APP=0（发送器驱动 app_tx_*）    -> ping 0/4 不通，ARP 表全空
    //   => 只要应用层去驱动协议栈的 app-TX 接口，网口就死。
    //
    //   机制（结合三次上板实测）：
    //     开机后发送器很快就要发 -> 需要 ARP 解析 192.168.240.2
    //     但此刻 PC 网卡可能还没就绪（板子与 PC 同时上电），ARP 没人应
    //       -> 协议栈记 arp_request_no_reply_error（LED4 亮，实测吻合）
    //     而应用层按"不超时放弃"的写法死等 app_tx_ack
    //       -> TX 接口被**永久占住** -> 协议栈再也发不出 ARP 应答/ping 回复
    //       -> PC 拿不到板子 MAC -> ping"无法访问目标主机"（实测吻合）
    //       -> **自己锁死自己，永不恢复**
    //   （官方 udp_loopback 能用，是因为它**从不主动发**，只在收到包之后才动
    //     TX 接口，那时对接早已就绪。）
    //
    //   三次踩过的错，别再重复：
    //     v1  用 1ms 超时   -> 太短。协议栈 ARP 窗口 = 3 x 134ms ≈ 400ms，
    //                          1ms 就把请求线抖断，ARP 永远走不完（实测不行）
    //     v2  完全不超时    -> 太长。一次 ARP 失败就永久锁死（实测不行）
    //     正解 = 下面三条：
    //   ① 上电静默期 STARTUP_MS：给 PC 网卡先就绪的时间，让第一次 ARP 就成功
    //   ② ack 超时 ACK_TIMEOUT_MS：> 协议栈 ARP 窗口（400ms），给 2 倍余量
    //   ③ 超时后等 RETRY_GAP_MS 再试，且**必须先松手**，让协议栈喘口气
    // =========================================================================
    parameter [23:0] STARTUP_MS     = 24'd3000;   // 上电后静默 3s
    parameter [23:0] ACK_TIMEOUT_MS = 24'd800;    // 等 ack 上限 800ms
    parameter [23:0] RETRY_GAP_MS   = 24'd300;    // 超时后歇 300ms

    // 125MHz 下每毫秒 125000 拍
    localparam [26:0] CNT_1MS = 27'd125_000;

    reg [23:0] ms_cnt;      // 静默期毫秒计数
    reg [26:0] tick;        // 静默期 1ms 分频
    reg        armed;       // 静默期结束标志
    reg [23:0] ack_wait;    // 等 ack 的毫秒数
    reg [26:0] tick2;       // 等 ack 的 1ms 分频
    reg [23:0] backoff;     // 退避毫秒数
    reg [26:0] tick3;       // 退避的 1ms 分频

    localparam S_IDLE = 3'd0, S_FILL = 3'd1, S_REQ = 3'd2, S_SEND = 3'd3, S_DONE = 3'd4,
               S_BACKOFF = 3'd5;

    // =========================================================================
    // ★ [修复7] 载荷大小参数化 —— 验证"协议栈能不能吃下大包"
    // =========================================================================
    //   已知能用的实现，载荷都很小：
    //     官方 udp_loopback（第 2 步实测通过）  7 字节
    //     板 B result_sender.v（上板验证过）    149 字节
    //   而本模块原来发 1402 / 1050 字节 —— **没有任何验证过的实现发过这么大的包**。
    //   加密 IP 的应用侧缓冲/MTU 上限无从得知；若 1402 超出其内部缓冲，
    //   它就不会给 app_tx_ack -> 发送器永久卡在 S_REQ（LED2 常亮，实测吻合）。
    //   PKT_PAY 即每包的图像字节数（不含 2 字节序号）。约束：
    //     27648 % PKT_PAY == 0，且 PKT_PAY + 2 <= 协议栈能接受的 UDP 载荷上限
    //   测试序列建议：512 -> 256 -> 128（都整除 27648）
    // =========================================================================
    parameter [11:0] PKT_PAY = 12'd512;
    localparam [11:0] PAY_FULL_P = PKT_PAY + 12'd2;               // 2 + PKT_PAY
    localparam [5:0]  NPKT       = 6'd54;                          // 27648/512 = 54
    localparam [5:0]  PKT_LAST_P = NPKT - 6'd1;

    localparam [5:0]  PKT_LAST  = PKT_LAST_P;
    localparam [11:0] PAY_FULL  = PAY_FULL_P;
    localparam [11:0] PAY_LAST  = PAY_FULL_P;   // 整除，末包与普通包同长
    localparam [15:0] NEED_FULL = {4'd0, PKT_PAY};
    localparam [15:0] NEED_LAST = {4'd0, PKT_PAY};

    reg [2:0]  st;
    reg [5:0]  pkt;
    reg [11:0] idx;      // 下一个要呈现的载荷字节号
    reg [11:0] pay;      // 本包载荷总长（含 2 字节序号）
    reg        stalled;  // 诊断：本拍因 FIFO 读空而停住（整帧就位时永不置位）

    wire [11:0] pay_this  = (pkt == PKT_LAST) ? PAY_LAST  : PAY_FULL;
    wire [15:0] need_this = (pkt == PKT_LAST) ? NEED_LAST : NEED_FULL;

    // 图像字节阶段（idx>=2）且 FIFO 空了 -> 必须冻结本拍
    wire image_phase = (st == S_SEND) && (idx >= 12'd2);
    wire must_stall  = image_phase && I_fifo_empty;

    // ---- 静默期计数：每 CNT_1MS 拍算 1ms，数满 STARTUP_MS 后 armed=1 ----
    always @(posedge I_clk) begin
        if (I_rst) begin
            tick   <= 27'd0;
            ms_cnt <= 24'd0;
            armed  <= 1'b0;
        end else if (!armed) begin
            if (tick >= CNT_1MS) begin
                tick <= 27'd0;
                if (ms_cnt >= STARTUP_MS) armed  <= 1'b1;
                else                      ms_cnt <= ms_cnt + 24'd1;
            end else begin
                tick <= tick + 27'd1;
            end
        end
    end

    always @(posedge I_clk) begin
        if (I_rst) begin
            st           <= S_IDLE;
            O_fifo_rd    <= 1'b0;
            O_tx_request <= 1'b0;
            O_tx_valid   <= 1'b0;
            O_tx_data    <= 8'd0;
            O_tx_length  <= 16'd0;
            pkt          <= 5'd0;
            idx          <= 12'd0;
            pay          <= 12'd0;
            O_busy       <= 1'b0;
            O_frame_done <= 1'b0;
            O_tx_abort   <= 1'b0;
            stalled      <= 1'b0;
            ack_wait     <= 24'd0;
            tick2        <= 27'd0;
            backoff      <= 24'd0;
            tick3        <= 27'd0;
        end else begin
            O_frame_done <= 1'b0;
            O_tx_abort   <= 1'b0;      // 只在 S_REQ 超时时产生单周期脉冲
            stalled      <= must_stall;

            case (st)
            //--------------------------------------------------------------
            S_IDLE: begin
                O_fifo_rd <= 1'b0;
                // ★ [修复6] ① 上电静默期：armed 之前一帧都不发，
                //   给 PC 网卡留出就绪时间，让第一次 ARP 就能成功。
                if (I_frame_start && armed) begin
                    pkt    <= 5'd0;
                    O_busy <= 1'b1;
                    st     <= S_FILL;
                end
            end
            //--------------------------------------------------------------
            // ★ [修复4] 攒够 **NEED_FRAME** 字节再开始发。
            //   NEED_FRAME = 27 648（一整帧）时：按下 app-TX 接口的那一刻整帧
            //   已经在 FIFO 里，配合写侧背压（占用不会超过 FIFO_HIGH，而
            //   FIFO_HIGH − 27 648 > 0）保证**发送过程中绝不会读空**。
            //   于是 app_tx_data_valid 只会在"真的有数据要发"时拉高，
            //   撤手也干净 —— 不会再出现 v2 那种"举着 valid 干等 1ms"。
            //   need_this 仍然查一次：若上层把 NEED_FRAME 设得小于单包长度，
            //   也不至于把一个包截断。
            S_FILL: begin
                O_fifo_rd <= 1'b0;
                pay <= pay_this;
                if ((I_fifo_cnt >= need_this) && (I_fifo_cnt >= NEED_FRAME))
                    st <= S_REQ;
            end
            //--------------------------------------------------------------
            // ★ [修复5] 必须**先确认 udp2app_tx_ready** 才能拉 app_tx_request
            //
            //   实测（2026-10-11，LED2 接 app_tx_data_request）：
            //     上板后 app_tx_data_request **一直常亮**、且 LED3(一帧发完)恒灭
            //     => 发送器第 1 次进 S_REQ 就**永久卡死**，等不到 app_tx_ack。
            //
            //   根因：本模块原来**无条件**拉 O_tx_request。而 udp2app_tx_ready
            //   是协议栈"我可以收"的就绪信号，官方 udp_loopback.v:117 是
            //     if ((fifo_cnt > 0) && (~app_rx_data_valid) && udp_tx_ready)
            //   必须**先等 ready 再拉请求**。请求在协议栈内部 FSM 就绪之前到达，
            //   协议栈就不认，ack 永远不来 -> 永久占死 TX 接口 ->
            //   ARP / ICMP 全部发不出去 -> ping 不通、arp_request_no_reply_error 亮。
            //
            //   改法：request 只有在 I_tx_ready 为高时才拉高；没 ready 就继续等
            //   （此时 request 保持低，把 TX 接口让给协议栈自己的 ARP/ICMP）。
            //   拉高之后**保持到 ack**，不做任何超时放弃（与板 B / loopback 一致）。
            //--------------------------------------------------------------
            S_REQ: begin
                if (I_tx_ack) begin
                    O_tx_request <= 1'b0;
                    O_tx_valid   <= 1'b1;
                    O_tx_length  <= {4'd0, pay_this};
                    O_tx_data    <= 8'h00;      // ★ 字节 0（序号高字节）与 tx_valid 同拍就绪
                    idx          <= 12'd1;
                    st           <= S_SEND;
                end else if (!O_tx_request) begin
                    // 还没拉请求：等协议栈说"我可以收"
                    if (I_tx_ready) begin
                        O_tx_request <= 1'b1;
                        ack_wait     <= 24'd0;
                        tick2        <= 27'd0;
                    end
                end else begin
                    // ★ [修复6] ② + ③ 已经拉着请求了：给 ARP 留够时间（800ms），
                    //   但**绝不死等** —— 超时就干净地松手，歇 300ms 再重来。
                    //   协议栈 ARP 窗口 = 3 x 134ms ≈ 400ms，800ms 有 2 倍余量。
                    if (tick2 >= CNT_1MS) begin
                        tick2 <= 27'd0;
                        if (ack_wait >= ACK_TIMEOUT_MS) begin
                            // 超时：松手，进入退避等待
                            O_tx_request <= 1'b0;
                            O_tx_abort   <= 1'b1;   // 单周期脉冲（可上灯）
                            O_busy       <= 1'b0;
                            backoff      <= 24'd0;
                            tick3        <= 27'd0;
                            st           <= S_BACKOFF;
                        end else begin
                            ack_wait <= ack_wait + 24'd1;
                        end
                    end else begin
                        tick2 <= tick2 + 27'd1;
                    end
                end
            end
            //--------------------------------------------------------------
            // ★ [修复6] ③ 失败退避：松手 RETRY_GAP_MS 毫秒，把 TX 接口完整让给
            //   协议栈（让它的 ARP 重试、ARP 应答、ICMP 回复都能走），然后再来。
            //   这一状态是防止"自己锁死自己"的最后一道保险。
            S_BACKOFF: begin
                O_fifo_rd    <= 1'b0;
                O_tx_request <= 1'b0;
                O_tx_valid   <= 1'b0;
                if (tick3 >= CNT_1MS) begin
                    tick3 <= 27'd0;
                    if (backoff >= RETRY_GAP_MS) st <= S_IDLE;
                    else                         backoff <= backoff + 24'd1;
                end else begin
                    tick3 <= tick3 + 27'd1;
                end
            end
            //--------------------------------------------------------------
            S_SEND: begin
                if (idx == pay) begin
                    // 字节 pay-1 已在上一拍呈现，本拍收尾
                    O_tx_valid <= 1'b0;
                    O_fifo_rd  <= 1'b0;
                    st         <= S_DONE;
                end else if (idx == 12'd1) begin
                    O_tx_data <= {3'b000, pkt};  // 字节 1：序号低字节
                    O_fifo_rd <= 1'b0;
                    idx       <= idx + 12'd1;
                end else if (must_stall) begin
                    // ★ 修正 2：FIFO 读空 -> 冻结。不推进 idx、不抬 fifo_rd、
                    //   保持 O_tx_data（它此刻仍是上一个有效字节 = 要发的那个）。
                    O_fifo_rd <= 1'b0;
                end else begin
                    O_tx_data <= I_fifo_q;       // 图像字节（show-ahead 当拍有效）
                    O_fifo_rd <= 1'b1;           // 同拍推进，下一拍就是下一个字节
                    idx       <= idx + 12'd1;
                end
            end
            //--------------------------------------------------------------
            S_DONE: begin
                O_fifo_rd <= 1'b0;
                if (pkt == PKT_LAST) begin
                    O_busy       <= 1'b0;
                    O_frame_done <= 1'b1;
                    st           <= S_IDLE;
                end else begin
                    pkt <= pkt + 5'd1;
                    st  <= S_FILL;
                end
            end
            //--------------------------------------------------------------
            default: st <= S_IDLE;
            endcase
        end
    end
endmodule
