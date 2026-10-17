`timescale 1ns / 1ps

module ptz_servo_ctrl #(
    // 请确认云台模块所在时钟域！如果在 pclk 下，通常填 74250000；如果独立 50M，填 50000000
    parameter CLK_HZ     = 25_000_000, 
    
    parameter ANGLE_MAX  = 270,        // 舵机最大角度
    parameter CENTER_CX2 = 128,        // 128空间下，中心点64，乘2为128
    parameter DEADZONE   = 12,         // 死区（形心x2误差），12对应原空间6个像素
    parameter STEP_DEG   = 2           // 每次收到结果，最多转动的度数（建议2~3度防过冲）
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

    reg [26:0] pwm_cnt;
    reg [26:0] pulse_reg;
    reg [8:0]  angle;

    // =========================================================================
    // 1. 计算形心误差 (128x72 空间)
    // =========================================================================
    // 形心乘2公式: cx2 = 2*x1 + w。例如 x1=10, w=20, 则 cx2 = 40
    wire [9:0] cx2 = {target_x, 1'b0} + target_w;
    
    // 计算误差 (用有符号数)
    wire signed [10:0] error = $signed({1'b0, cx2}) - $signed(11'd128);
    wire [10:0] error_abs = error[10] ? (~error + 1'b1) : error;

    // =========================================================================
    // 2. 判定当前是否真的检测到了人脸
    // =========================================================================
    // 根据交接文档：true_found = valid脉冲 && 框宽高>=2
    wire true_face_found = target_valid && (target_w >= 2) && (target_h >= 2);

    // 计算步长：误差越大走得越多，限幅为 STEP_DEG
    wire [3:0] step;
    assign step = (error_abs <= DEADZONE) ? 4'd0 :
                  (error_abs > 48)        ? STEP_DEG : // 误差大于24个像素(原图240)，给最大步长
                  ((error_abs >> 2) > STEP_DEG) ? STEP_DEG :
                  (error_abs >> 2);

    // =========================================================================
    // 3. 舵机控制逻辑
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pwm_cnt   <= 0;
            pulse_reg <= PULSE_MIN + (135 * PULSE_RANGE) / ANGLE_MAX;
            angle     <= 9'd135;
        end
        else begin
            // ---- PWM 发生器 (后台一直运行) ----
            if (pwm_cnt == PWM_PERIOD - 1)
                pwm_cnt <= 0;
            else
                pwm_cnt <= pwm_cnt + 1'b1;

            // ---- 动态更新脉宽 ----
            pulse_reg <= PULSE_MIN + (angle * (PULSE_RANGE / ANGLE_MAX));

            // ---- 目标追踪 (仅在收到有效脉冲时触发) ----
            if (true_face_found) begin
                // 目标偏右：角度减少 (反向)
                if (error > DEADZONE) begin
                    if (angle >= step)
                        angle <= angle - step;
                    else
                        angle <= 9'd0;
                end
                // 目标偏左：角度增加 (反向)
                else if (error < -DEADZONE) begin
                    if (angle + step <= ANGLE_MAX)
                        angle <= angle + step;
                    else
                        angle <= ANGLE_MAX;
                end
            end
            // 如果 target_valid=0，说明没收到包或者丢包，angle 保持原值不动
        end
    end

    assign pwm_out   = (pwm_cnt < pulse_reg) ? 1'b1 : 1'b0;
    assign angle_dbg = angle;

endmodule