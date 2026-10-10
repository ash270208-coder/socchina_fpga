`timescale 1ns / 1ps

module ptz_servo_ctrl #(
    parameter CLK_HZ     = 24_000_000, // 使用 24M 时钟域
    parameter ANGLE_MAX  = 270,        // TBS-K15 270°
    parameter IMG_W      = 1280,
    parameter CENTER_X   = 640,
    parameter DEADZONE   = 60,         // 中心死区，像素
    parameter UPDATE_MS  = 50,         // 角度更新周期 ms
    parameter STEP_MAX   = 8           // 每次最多转 8°
)(
    input  wire        clk,
    input  wire        rst_n,          // 低有效复位
    input  wire        target_valid,   // 1=目标有效
    input  wire [10:0] target_x,       // 0~1279
    output wire        pwm_out,        // 接舵机信号线
    output wire [8:0]  angle_dbg       // 当前角度，调试用
);

    // 50Hz PWM: 20ms 周期
    localparam PWM_PERIOD  = CLK_HZ / 50;        // 24M / 50 = 480000
    localparam PULSE_MIN   = CLK_HZ / 2000;      // 0.5ms = 12000
    localparam PULSE_MAX   = CLK_HZ / 400;       // 2.5ms = 60000
    localparam PULSE_RANGE = PULSE_MAX - PULSE_MIN; // 48000
    localparam UPDATE_CNT  = CLK_HZ / 1000 * UPDATE_MS; // 24M*50ms = 1,200,000

    reg [18:0] pwm_cnt;
    reg [18:0] pulse_reg;
    reg [8:0]  angle;
    reg [20:0] upd_cnt;

    // 目标中心误差：target_x - 640
    wire signed [11:0] error = $signed({1'b0, target_x}) - $signed(12'd640);
    wire [11:0] error_abs = error[11] ? (~error + 1'b1) : error;

    // 比例步长：误差越大，转得越快，限幅 STEP_MAX
    wire [3:0] step;
    assign step = (error_abs <= DEADZONE) ? 4'd0 :
                  (error_abs > 320)        ? STEP_MAX :
                  (((error_abs >> 6) + 1) > STEP_MAX) ? STEP_MAX :
                  ((error_abs >> 6) + 1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pwm_cnt   <= 19'd0;
            pulse_reg <= PULSE_MIN + (135 * PULSE_RANGE) / ANGLE_MAX; // 上电中位 135°
            angle     <= 9'd135;
            upd_cnt   <= 21'd0;
        end
        else begin
            // -----------------------------
            // 20ms PWM 周期计数
            // -----------------------------
            if (pwm_cnt == PWM_PERIOD - 1)
                pwm_cnt <= 19'd0;
            else
                pwm_cnt <= pwm_cnt + 1'b1;

            // -----------------------------
            // 每 50ms 更新一次目标角度
            // -----------------------------
            if (upd_cnt == UPDATE_CNT - 1) begin
                upd_cnt <= 21'd0;

                if (target_valid) begin
                    // 目标偏右：角度增加，顺时针
                    if (error > $signed(DEADZONE)) begin
                        if (angle + step <= ANGLE_MAX)
                            angle <= angle + step;
                        else
                            angle <= ANGLE_MAX;
                    end
                    // 目标偏左：角度减少，逆时针
                    else if (error < -$signed(DEADZONE)) begin
                        if (angle >= step)
                            angle <= angle - step;
                        else
                            angle <= 9'd0;
                    end
                    // 死区内：不动
                end
                // target_valid=0：丢失目标，保持当前角度，不更新
            end
            else begin
                upd_cnt <= upd_cnt + 1'b1;
            end

            // -----------------------------
            // 根据当前角度计算 PWM 脉宽
            // 500~2500 对应 0~270°
            // -----------------------------
            pulse_reg <= PULSE_MIN + (angle * PULSE_RANGE) / ANGLE_MAX;
        end
    end

    assign pwm_out   = (pwm_cnt < pulse_reg) ? 1'b1 : 1'b0;
    assign angle_dbg = angle;

endmodule