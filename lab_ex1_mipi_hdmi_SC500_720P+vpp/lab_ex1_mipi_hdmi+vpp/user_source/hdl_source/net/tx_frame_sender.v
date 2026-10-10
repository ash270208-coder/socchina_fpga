`timescale 1ns / 1ps
//=============================================================================
// tx_frame_sender.v —— 把一帧 128x72 RGB 图像按 20 个 UDP 包发给板 B
//
// 包格式（板 B 已钉死，见 docs/板A以太网改造_实施计划.md §8.3）：
//   UDP 载荷 = [seq_hi, seq_lo] + 图像字节
//     包 0~18：2 + 1400 = 1402 字节     （19 × 1400 = 26 600）
//     包 19  ：2 + 1048 = 1050 字节     （+ 1048 = 27 648 = 128×72×3 ✓）
//   图像字节顺序 R,G,B 逐像素排列（由 pixel_to_bytes 保证）
//
// ⚠⚠ 关键：第一个字节必须与 tx_valid **同一拍**就绪
//   `udp_ip_protocol_stack` 的应用侧 TX 是「request → 等 ack → 连续喂数据」，
//   在看到 ack 的那一拍就把 tx_valid 拉高、并从**下一拍**开始采样 app_tx_data。
//   所以如果在 ack 那一拍不装载首字节，第一个字节会取到上一包的残留值，
//   整包错位一格、长度也会差一字节。
//   板上验证过的 cnn_boardB/src/net/result_sender.v:179 就是这么写的：
//       tx_valid <= 1'b1;
//       tx_data  <= 8'hAA;   // 第一字节与 tx_valid 同拍就绪
//   docs/HX1P35A双板以太网级联实施指导.md §7.6 给的 tx_frame_sender **漏了这一步**，
//   照抄会错位，本文件是修正版。
//
// 与 show-ahead 异步 FIFO 的配合（逐拍推演过）：
//   设载荷字节号 m（0 基）：m=0 是 seq_hi，m=1 是 seq_lo，m>=2 是图像字节 img[m-2]。
//   状态机里 idx 表示"下一个要呈现的字节号"，且 idx 与采样拍的对应关系是
//   **采样到字节 m 的那一拍，idx = m+1**。因此：
//     idx==1 那一拍 -> 装载 seq_lo（供下一拍采样字节 1）
//     idx>=2 那一拍 -> 装载 fifo_q（show-ahead 当拍数据即有效）
//   同时 idx>=2 时拉高 fifo_rd，show-ahead 模式下 FIFO 的读地址会预加 1
//   （见 ram_fifo.v:246 `addrb(rdaddress + (SHOW_AHEAD_EN & fifo_re))`），
//   于是下一拍 fifo_q 正好是下一个图像字节。
//   最终 fifo_rd 的拉高次数 = pay-2 = 每包图像字节数，一帧合计 27 648 ✓
//
// 节拍：图像生产者（cnn_ds10）平均 2.25 字节/µs，而发送侧一旦启动约 125 字节/µs，
//   所以实际是**生产者限速**：S_FILL 每包都等 FIFO 攒够 1400/1048 字节才发。
//   一包发完 FIFO 里只剩几十字节，不会溢出（深度 4096 远大于单包 1402）。
//=============================================================================
module tx_frame_sender (
    input  wire        I_clk,          // udp_clk（125MHz）
    input  wire        I_rst,          // 高有效同步复位
    input  wire        I_frame_start,  // udp_clk 域单周期脉冲（被门控帧的起点）
    // ---- show-ahead 异步 FIFO 读侧 ----
    output reg         O_fifo_rd,
    input  wire [7:0]  I_fifo_q,
    input  wire [13:0] I_fifo_cnt,     // rdusedw（ram_fifo 是 [ADDR_WIDTH_R:0] = 14 位）
    // ---- UDP 协议栈应用侧 ----
    input  wire        I_tx_ready,     // udp2app_tx_ready
    input  wire        I_tx_ack,       // udp2app_tx_ack
    output reg         O_tx_request,   // app_tx_request
    output reg         O_tx_valid,     // app_tx_data_valid
    output reg  [7:0]  O_tx_data,      // app_tx_data
    output reg  [15:0] O_tx_length,    // app_tx_data_length（含 2 字节序号的载荷总长）
    // ---- 诊断/状态 ----
    output reg         O_busy,         // 一帧 20 包发送期间为高
    output reg         O_frame_done    // 一帧发完的单周期脉冲
);
    localparam S_IDLE = 3'd0, S_FILL = 3'd1, S_REQ = 3'd2, S_SEND = 3'd3, S_DONE = 3'd4;
    localparam [4:0]  PKT_LAST  = 5'd19;      // 共 20 包：0..19
    localparam [11:0] PAY_FULL  = 12'd1402;   // 2 + 1400
    localparam [11:0] PAY_LAST  = 12'd1050;   // 2 + 1048
    localparam [13:0] NEED_FULL = 14'd1400;   // 发前要求 FIFO 至少攒够的图像字节
    localparam [13:0] NEED_LAST = 14'd1048;
    reg [2:0]  st;
    reg [4:0]  pkt;
    reg [11:0] idx;      // 下一个要呈现的载荷字节号
    reg [11:0] pay;      // 本包载荷总长（含 2 字节序号）

    wire [11:0] pay_this  = (pkt == PKT_LAST) ? PAY_LAST  : PAY_FULL;
    wire [13:0] need_this = (pkt == PKT_LAST) ? NEED_LAST : NEED_FULL;

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
        end else begin
            O_frame_done <= 1'b0;

            case (st)
            //--------------------------------------------------------------
            S_IDLE: begin
                O_fifo_rd <= 1'b0;
                if (I_frame_start) begin
                    pkt    <= 5'd0;
                    O_busy <= 1'b1;
                    st     <= S_FILL;
                end
            end
            //--------------------------------------------------------------
            // 等生产者把本包的图像字节攒够（发送侧远快于生产者，主要时间花在这）
            S_FILL: begin
                O_fifo_rd <= 1'b0;
                pay <= pay_this;
                if (I_fifo_cnt >= need_this) st <= S_REQ;
            end
            //--------------------------------------------------------------
            S_REQ: begin
                if (I_tx_ack) begin
                    O_tx_request <= 1'b0;
                    O_tx_valid   <= 1'b1;
                    O_tx_length  <= {4'd0, pay_this};
                    O_tx_data    <= 8'h00;      // ★ 字节 0（序号高字节）与 tx_valid 同拍就绪
                    idx          <= 12'd1;
                    st           <= S_SEND;
                end else if (!O_tx_request && I_tx_ready) begin
                    O_tx_request <= 1'b1;        // 就绪后拉请求，并保持到 ack
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
