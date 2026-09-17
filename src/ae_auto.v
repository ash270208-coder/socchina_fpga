`timescale 1ns / 1ps
// =============================================================================
// ae_auto (抗拍屏闪烁版)
//   - 对 avg_y 做 4 帧滑动平均, 抑制屏幕刷新引起的帧间波动
//   - 死区增大到 8, 收敛后完全冻结曝光
//   - 步长减半, 避免过冲振荡
// =============================================================================
module ae_auto #(
    parameter TARGET_Y = 100,
    parameter AE_MAX   = 1990,
    parameter AE_MIN   = 4,
    parameter AE_INIT  = 1990,
    parameter HYST     = 8,          // ← 3 改 8
    parameter AG_VALUE = 16
)(
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_enable,
    input  wire [7:0]  I_avg_y,
    input  wire        I_frame_done,
    input  wire        I_cfg_done,
    output reg  [15:0] O_ae,
    output reg  [15:0] O_ag,
    output reg         O_ae_req
);

    reg [15:0] ae_cur;

    // ---- 对 avg_y 做 4 帧滑动平均 ----
    reg [7:0]  avg_y_p0, avg_y_p1, avg_y_p2, avg_y_p3;
    reg [7:0]  avg_y_filt;
    reg [9:0]  avg_y_sum4;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            avg_y_p0   <= 8'd100;
            avg_y_p1   <= 8'd100;
            avg_y_p2   <= 8'd100;
            avg_y_p3   <= 8'd100;
            avg_y_filt <= 8'd100;
            avg_y_sum4 <= 10'd400;
        end else if (I_frame_done && I_enable) begin
            avg_y_p0 <= I_avg_y;
            avg_y_p1 <= avg_y_p0;
            avg_y_p2 <= avg_y_p1;
            avg_y_p3 <= avg_y_p2;
            avg_y_sum4 <= I_avg_y + avg_y_p0 + avg_y_p1 + avg_y_p2;
            avg_y_filt <= (I_avg_y + avg_y_p0 + avg_y_p1 + avg_y_p2) >> 2;
        end
    end

    // ---- 使能边沿检测 ----
    reg enable_d;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) enable_d <= 1'b0;
        else          enable_d <= I_enable;
    end
    wire enable_rise = I_enable & ~enable_d;

    // ---- 理想目标曝光 (用滤波后的 avg_y) ----
    reg [23:0] ae_target;
    always @(*) begin
        if (avg_y_filt == 8'd0)
            ae_target = AE_MAX[23:0];
        else begin
            ae_target = (ae_cur * TARGET_Y) / avg_y_filt;
            if (ae_target > AE_MAX[23:0])
                ae_target = AE_MAX[23:0];
        end
    end

    // ---- 每帧最大步进: 收敛后步伐更小 ----
    reg [15:0] max_step;
    always @(*) begin
        if      (ae_cur < 16'd32)   max_step = 16'd4;      // 极短曝光, 微调
        else if (ae_cur > 16'd2000) max_step = 16'd200;    // 长曝光, 快收敛
        else                        max_step = ae_cur >> 4; // ← >>2 改 >>4
    end

    // ---- 步长限速 + 死区 ----
    reg [15:0] ae_next;
    reg [8:0]  diff_abs;
    always @(*) begin
        diff_abs = (avg_y_filt > TARGET_Y) ? (avg_y_filt - TARGET_Y)
                                            : (TARGET_Y - avg_y_filt);

        if (diff_abs <= HYST)
            ae_next = ae_cur;                     // 死区: 冻结曝光
        else if (ae_target > (ae_cur + max_step))
            ae_next = ae_cur + max_step;
        else if ((ae_target < (ae_cur - max_step)) && (ae_cur > max_step))
            ae_next = ae_cur - max_step;
        else
            ae_next = ae_target[15:0];

        if      (ae_next > AE_MAX) ae_next = AE_MAX;
        else if (ae_next < AE_MIN) ae_next = AE_MIN;
    end

    // ---- 输出 ----
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            ae_cur   <= AE_INIT;
            O_ae     <= AE_INIT;
            O_ag     <= AG_VALUE;
            O_ae_req <= 1'b0;
        end else begin
            O_ae_req <= 1'b0;
            if (enable_rise) begin
                ae_cur   <= AE_INIT;
                O_ae     <= AE_INIT;
                O_ae_req <= 1'b1;
            end
            else if (I_enable && I_frame_done && I_cfg_done && (ae_next != ae_cur)) begin
                ae_cur   <= ae_next;
                O_ae     <= ae_next;
                O_ae_req <= 1'b1;
            end
        end
    end

endmodule