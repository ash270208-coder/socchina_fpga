`timescale 1ns / 1ps
// =============================================================================
// ae_auto (抗拍屏震荡版)
//   - avg_y 8 帧滑动平均, 抑制拍屏引起的帧间大幅波动
//   - 死区 HYST = 20, 波动在死区内完全不动
//   - 每帧曝光变化限速 ±50 行, 防止极限环
// =============================================================================
module ae_auto #(
    parameter TARGET_Y = 50,
    parameter AE_MAX   = 1990,
    parameter AE_MIN   = 4,
    parameter AE_INIT  = 500,
    parameter HYST     = 20,
    parameter KP       = 1,
    parameter STEP_MAX = 50,     // 每帧最大变化量
    parameter AG_VALUE = 80
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

    // ---- 使能边沿 ----
    reg enable_d;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) enable_d <= 1'b0;
        else          enable_d <= I_enable;
    end
    wire enable_rise = I_enable & ~enable_d;

    // ---- 8 帧滑动平均 ----
    reg [7:0]  y_p0, y_p1, y_p2, y_p3, y_p4, y_p5, y_p6, y_p7;
    reg [7:0]  y_filt;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            y_p0 <= 8'd50; y_p1 <= 8'd50; y_p2 <= 8'd50; y_p3 <= 8'd50;
            y_p4 <= 8'd50; y_p5 <= 8'd50; y_p6 <= 8'd50; y_p7 <= 8'd50;
            y_filt <= 8'd50;
        end else if (I_frame_done && I_enable) begin
            y_p0 <= I_avg_y;
            y_p1 <= y_p0; y_p2 <= y_p1; y_p3 <= y_p2; y_p4 <= y_p3;
            y_p5 <= y_p4; y_p6 <= y_p5; y_p7 <= y_p6;
            y_filt <= (I_avg_y + y_p0 + y_p1 + y_p2
                     + y_p3 + y_p4 + y_p5 + y_p6) >> 3;   // 8 帧平均
        end
    end

    // ---- 误差 ----
    wire [8:0] err_abs = (y_filt > TARGET_Y) ? (y_filt - TARGET_Y)
                                              : (TARGET_Y - y_filt);
    wire       too_dark  = (y_filt < TARGET_Y - HYST);
    wire       too_bright= (y_filt > TARGET_Y + HYST);

    // ---- 一帧的曝光增量: 用滤波后的 y, 按误差方向算 ----
    // delta 越大步进越大, 但每帧限速 ±STEP_MAX
    reg [15:0] step_now;
    always @(*) begin
        if (too_dark || too_bright) begin
            // 步长 = 误差 * KP, 但不超过 STEP_MAX
            step_now = err_abs * KP;
            if (step_now > STEP_MAX) step_now = STEP_MAX;
        end else
            step_now = 16'd0;   // 死区内不动
    end

    // ---- 新曝光 ----
    wire [15:0] ae_up   = (ae_cur + step_now > AE_MAX) ? AE_MAX : (ae_cur + step_now);
    wire [15:0] ae_down = (ae_cur < step_now + AE_MIN) ? AE_MIN : (ae_cur - step_now);

    reg [15:0] ae_next;
    always @(*) begin
        if      (!too_dark && !too_bright) ae_next = ae_cur;    // 死区内冻结
        else if (too_dark)                 ae_next = ae_up;     // 太暗, 加曝光
        else                               ae_next = ae_down;   // 太亮, 减曝光
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