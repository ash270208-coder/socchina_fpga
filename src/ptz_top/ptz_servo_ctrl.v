`timescale 1ns / 1ps

module ptz_servo_ctrl #(
    parameter CLK_HZ        = 25_000_000, 
    parameter ANGLE_MAX     = 270,        // 舵机最大角度
    parameter CENTER_CX2    = 128,        // 128空间下，中心点64，乘2为128
    parameter DEADZONE      = 12,         // 死区（形心x2误差），12对应原空间6个像素
    parameter STEP_DEG      = 2,          // 追踪时，每次收到结果最多转动的度数
    
    // ---- 回中相关参数 ----
    parameter LOST_TIMEOUT_MS = 1000,     // 丢失目标超时时间（毫秒），超过此时间无目标则回中
    parameter MID_STEP_DEG    = 2,        // 回中时每次转动的度数
    parameter MID_UPDATE_MS   = 20        // 回中时的转动周期（毫秒），20ms转2度，平滑回中
)(
    input  wire        clk,
    input  wire        rst_n,          // 低有效复位
    
    // 接收来自以太网解析模块的原始信号
    input  wire        target_valid,   // 单拍有效脉冲
    input  wire [7:0]  target_x,       // x1 (0~128)
    input  wire [7:0]  target_y,       // y1 (0~72)
    input  wire [7:0]  target_w,       // w  (0~128)
    input  wire [7:0]  target_h,       // h  (0~72)
    
    output wire        pwm_out,        // PWM 信号输出
    output wire [8:0]  angle_dbg       // 当前角度
);

    // 50Hz PWM: 20ms 周期
    localparam PWM_PERIOD  = CLK_HZ / 50;        
    localparam PULSE_MIN   = CLK_HZ / 2000;      // 0.5ms
    localparam PULSE_MAX   = CLK_HZ / 400;       // 2.5ms
    localparam PULSE_RANGE = PULSE_MAX - PULSE_MIN; // 脉宽范围

    // 超时与回中计数器参数
    localparam TIMEOUT_CNT = CLK_HZ / 1000 * LOST_TIMEOUT_MS;
    localparam MID_UPD_CNT = CLK_HZ / 1000 * MID_UPDATE_MS;
    localparam CENTER_ANG  = 9'd135;             // 中位角度

    reg [31:0] pwm_cnt;
    reg [31:0] pulse_reg;
    reg [8:0]  angle;
    
    reg [31:0] lost_cnt;   // 丢失目标计时器
    reg [21:0] mid_cnt;    // 回中步进周期计数器
    wire       mid_tick;   // 回中步进脉冲

    // =========================================================================
    // 1. 计算形心误差 (128x72 空间)
    // =========================================================================
    wire [9:0] cx2 = {target_x, 1'b0} + target_w;
    wire signed [10:0] error = $signed({1'b0, cx2}) - $signed(11'd128);
    wire [10:0] error_abs = error[10] ? (~error + 1'b1) : error;

    // 判定当前是否真的检测到了人脸
    wire true_face_found = target_valid && (target_w >= 2) && (target_h >= 2);

    // 计算追踪步长
    wire [3:0] step;
    assign step = (error_abs <= DEADZONE) ? 4'd0 :
                  (error_abs > 48)        ? STEP_DEG : 
                  ((error_abs >> 2) > STEP_DEG) ? STEP_DEG :
                  (error_abs >> 2);

    // =========================================================================
    // 2. 超时与回中节拍逻辑
    // =========================================================================
    // 丢失目标超时逻辑：只要收到有效人脸，计数器清零；否则一直累加
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lost_cnt <= 32'd0;
        end else if (true_face_found) begin
            lost_cnt <= 32'd0;
        end else if (lost_cnt < TIMEOUT_CNT) begin
            lost_cnt <= lost_cnt + 1'b1;
        end
    end
    
    wire target_lost = (lost_cnt >= TIMEOUT_CNT);

    // 回中节拍发生器（类似 PWM，但周期是 20ms）
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mid_cnt <= 22'd0;
        end else if (mid_cnt == MID_UPD_CNT - 1) begin
            mid_cnt <= 22'd0;
        end else begin
            mid_cnt <= mid_cnt + 1'b1;
        end
    end
    assign mid_tick = (mid_cnt == MID_UPD_CNT - 1);

    // =========================================================================
    // 3. 舵机控制逻辑（包含 PWM 与 追踪/回中 状态机）
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pwm_cnt   <= 0;
            pulse_reg <= PULSE_MIN + (CENTER_ANG * PULSE_RANGE) / ANGLE_MAX;
            angle     <= CENTER_ANG;
        end
        else begin
            // ---- PWM 发生器 (后台一直运行) ----
            if (pwm_cnt == PWM_PERIOD - 1)
                pwm_cnt <= 0;
            else
                pwm_cnt <= pwm_cnt + 1'b1;

            // ---- 动态更新脉宽 ----
            pulse_reg <= PULSE_MIN + (angle * (PULSE_RANGE / ANGLE_MAX));

            // ---- 目标追踪 (优先级最高) ----
            if (true_face_found) begin
                // 目标偏右：角度减少 (反向)
                if (error > DEADZONE) begin
                    if (angle >= step) angle <= angle - step;
                    else               angle <= 9'd0;
                end
                // 目标偏左：角度增加 (反向)
                else if (error < -DEADZONE) begin
                    if (angle + step <= ANGLE_MAX) angle <= angle + step;
                    else                           angle <= ANGLE_MAX;
                end
            end
            // ---- 丢失目标超时 -> 平滑回中 ----
            else if (target_lost && mid_tick) begin
                if (angle > CENTER_ANG) begin
                    if (angle >= CENTER_ANG + MID_STEP_DEG) angle <= angle - MID_STEP_DEG;
                    else                                    angle <= CENTER_ANG;
                end
                else if (angle < CENTER_ANG) begin
                    if (angle + MID_STEP_DEG <= CENTER_ANG) angle <= angle + MID_STEP_DEG;
                    else                                    angle <= CENTER_ANG;
                end
                // 如果 angle == CENTER_ANG，保持不动
            end
        end
    end

    assign pwm_out   = (pwm_cnt < pulse_reg) ? 1'b1 : 1'b0;
    assign angle_dbg = angle;

endmodule