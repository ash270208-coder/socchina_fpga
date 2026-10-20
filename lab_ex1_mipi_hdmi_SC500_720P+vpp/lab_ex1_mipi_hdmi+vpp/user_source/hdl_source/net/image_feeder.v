`timescale 1ns / 1ps
//=============================================================================
// image_feeder.v —— 把图像帧拆成 N 个小 UDP 包，喂给 udp_loopback 的"接收口"
//
// 【为什么这样做】
//   实测（板 A，2026-10-11）证明：手写 app-TX 状态机（tx_frame_sender）会
//   把加密协议栈卡死（ping 0/4、ARP 表空）；而官方 udp_loopback 的握手是
//   唯一验证过能用的 app-TX 驱动方式。
//   安路官方的"主动发送"（udp_transmit_test.v 的 TPG 模式）就是：
//      数据发生器 → 灌进 udp_loopback.app_rx_*  → loopback 原样发出去
//   本模块就是那个"数据发生器"，只是数据来自 img_fifo（真实图像），
//   而不是固定图案。udp_loopback 的握手一个字都不用自己写。
//
// 喂给 loopback 的每个"收包突发"= 一个 UDP 包：
//   [seq_hi, seq_lo] + PKT_PAY 个图像字节，长度 = PKT_PAY + 2
//   seq 大端：seq_hi=0，seq_lo=包号（0..NPKT-1）
//   约束：27648 % PKT_PAY == 0，NPKT = 27648 / PKT_PAY
//
// 与 loopback 的时序配合（loopback 只在 ~app_rx_data_valid 时才开始发）：
//   每个包之间 deassert valid 一段 gap（32 拍），让 loopback 有空档开始
//   上一包的发送；loopback 内部 64KB FIFO 足够缓存整帧，不会丢。
//=============================================================================
module image_feeder (
    input  wire        clk,            // udp_clk（125MHz）
    input  wire        rst,            // 高有效同步复位
    input  wire        frame_start,    // ★[修复10] 采集帧起点（udp_clk 域单拍脉冲）

    // ---- 读 img_fifo（show-ahead）----
    output reg         fifo_rd,
    input  wire [7:0]  fifo_q,
    input  wire [15:0] fifo_cnt,
    input  wire        fifo_empty,

    // ---- 喂给 udp_loopback 的 app_rx 口 ----
    output reg  [7:0]  loop_rx_data,
    output reg         loop_rx_valid,
    output reg  [15:0] loop_rx_length,

    // ---- 诊断 ----
    output reg         frame_done      // 一帧最后一个包喂完的单周期脉冲
);

    // ★[修复11] 改成**等长包**：27648 = 24 x 1152，没有"短末包"。
    //   实测（2026-10-13，Python 裸 socket 直收）：原 20 包方案下 seq0~18
    //   顺序完美，但 **seq19（唯一的 1050 短包）404 帧一次都没到**。
    //   末包长度与其它包不同，唯一可疑路径是 udp_loopback 的长度锁存
    //   （udp_loopback.v:96-99 只在 app_rx_data_valid 期间锁存长度）。
    //   等长化后所有包走同一条路径，从结构上排除这个变量。
    parameter [11:0] PKT_PAY_FULL = 12'd1152;  // 每包图像字节（等长）
    parameter [11:0] PKT_PAY_LAST = 12'd1152;  // 等长：不再有短末包
    parameter [4:0]  NPKT         = 5'd24;     // 共 24 包
    parameter [15:0] NEED_FRAME   = 16'd27648; // 24*1152 = 27648

    localparam [4:0]  PKT_LAST = NPKT - 5'd1;  // 23

    localparam [2:0] S_IDLE = 3'd0, S_HEAD = 3'd1, S_BODY = 3'd2, S_GAP = 3'd3;

    reg [2:0]  st;
    reg [4:0]  pkt;      // 当前包号 0..23
    reg [11:0] cnt;      // 包内字节号
    reg [7:0]  gap;      // 包间间隔计数

    // 每包的图像字节数与 UDP 载荷长（含 2 字节序号）：等长 1152/1154
    wire [11:0] pay_this = (pkt == PKT_LAST) ? PKT_PAY_LAST : PKT_PAY_FULL;
    wire [15:0] len_this = {4'd0, pay_this} + 16'd2;

    always @(posedge clk) begin
        if (rst) begin
            st            <= S_IDLE;
            pkt           <= 8'd0;
            cnt           <= 12'd0;
            gap           <= 8'd0;
            fifo_rd       <= 1'b0;
            loop_rx_data  <= 8'd0;
            loop_rx_valid <= 1'b0;
            loop_rx_length<= 16'd0;
            frame_done    <= 1'b0;
        end else if (frame_start) begin
            // ★[修复10] 采集帧起点：丢弃上一帧的残包，回到等待态，
            //   与 wrapper 的 FIFO 清空配合，保证下一帧**从帧头开始发**。
            //   此时 FIFO 刚被清空、写侧尚未开始，feeder 必然处于 S_IDLE，
            //   不会打断任何正在发送的完整帧。
            st            <= S_IDLE;
            pkt           <= 5'd0;
            cnt           <= 12'd0;
            gap           <= 8'd0;
            fifo_rd       <= 1'b0;
            loop_rx_valid <= 1'b0;
            frame_done    <= 1'b0;
        end else begin
            frame_done <= 1'b0;

            case (st)
            //------------------------------------------------------------
            // 等 FIFO 攒够一整帧
            S_IDLE: begin
                fifo_rd       <= 1'b0;
                loop_rx_valid <= 1'b0;
                if (fifo_cnt >= NEED_FRAME) begin
                    pkt <= 5'd0;
                    cnt <= 12'd0;
                    st  <= S_HEAD;
                end
            end
            //------------------------------------------------------------
            // 2 拍序号：seq_hi=0x00、seq_lo=包号（大端 u16）
            S_HEAD: begin
                fifo_rd       <= 1'b0;
                loop_rx_valid <= 1'b1;
                loop_rx_length<= len_this;          // 1402 / 1050
                loop_rx_data  <= (cnt == 12'd0) ? 8'h00 : {3'd0, pkt};
                if (cnt == 12'd1) begin
                    cnt <= 12'd0;
                    st  <= S_BODY;
                end else begin
                    cnt <= cnt + 12'd1;
                end
            end
            //------------------------------------------------------------
            // pay_this 个图像字节（前 19 包 1400、末包 1048；show-ahead）
            S_BODY: begin
                loop_rx_valid <= 1'b1;
                loop_rx_data  <= fifo_q;
                fifo_rd       <= 1'b1;
                if (cnt == pay_this - 12'd1) begin
                    cnt <= 12'd0;
                    gap <= 8'd0;
                    st  <= S_GAP;
                end else begin
                    cnt <= cnt + 12'd1;
                end
            end
            //------------------------------------------------------------
            // 包间间隔：拉低 valid，让 loopback 有空档把上一包发出去
            // ★ 256 拍（官方 tpg 用 130 拍）：保证 loopback 的 ACK 在下一包
            //   喂进来之前就完成，这样 ff2 锁存的长度才是"当前包"的长度，
            //   而不是"下一包"的长度（否则末包 1050 会污染前一包 1402）。
            S_GAP: begin
                loop_rx_valid <= 1'b0;
                fifo_rd       <= 1'b0;
                if (gap >= 8'd255) begin
                    if (pkt == PKT_LAST) begin
                        frame_done <= 1'b1;
                        pkt <= 5'd0;
                        st  <= S_IDLE;
                    end else begin
                        pkt <= pkt + 5'd1;
                        cnt <= 12'd0;
                        st  <= S_HEAD;
                    end
                end else begin
                    gap <= gap + 8'd1;
                end
            end
            default: st <= S_IDLE;
            endcase
        end
    end

endmodule
