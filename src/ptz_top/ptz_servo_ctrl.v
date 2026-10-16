`timescale 1ns / 1ps

module ptz_servo_ctrl #(
    parameter CLK_HZ     = 50_000_000,
    parameter ANGLE_MAX  = 270,
    parameter STEP_DEG   = 1,    // 每 50ms 转 1°，想快就改成 2 或 3
    parameter UPDATE_MS  = 50
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [1:0]  dir,       // 00=停止, 01=左转(角度减小), 10=右转(角度增大)
    output wire        pwm_out,
    output wire [8:0]  angle_dbg
);

    localparam PWM_PERIOD  = CLK_HZ / 50;      // 1_000_000
    localparam PULSE_MIN   = CLK_HZ / 2000;    // 25_000
    localparam PULSE_MAX   = CLK_HZ / 400;     // 125_000
    localparam PULSE_RANGE = PULSE_MAX - PULSE_MIN;
    localparam UPDATE_CNT  = CLK_HZ / 1000 * UPDATE_MS; // 2_500_000

    reg [19:0] pwm_cnt;
    reg [19:0] pulse_reg;
    reg [8:0]  angle;
    reg [21:0] upd_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pwm_cnt   <= 20'd0;
            pulse_reg <= PULSE_MIN + (135 * PULSE_RANGE) / ANGLE_MAX;
            angle     <= 9'd135;
            upd_cnt   <= 22'd0;
        end
        else begin
            // 20ms PWM 周期
            if (pwm_cnt == PWM_PERIOD - 1) pwm_cnt <= 20'd0;
            else                           pwm_cnt <= pwm_cnt + 1'b1;

            // 每 50ms 根据方向更新角度（恒定速度）
            if (upd_cnt == UPDATE_CNT - 1) begin
                upd_cnt <= 22'd0;
                case (dir)
                    2'b01: begin // 左转：角度减小
                        if (angle >= STEP_DEG) angle <= angle - STEP_DEG;
                        else                   angle <= 9'd0;
                    end
                    2'b10: begin // 右转：角度增大
                        if (angle + STEP_DEG <= ANGLE_MAX) angle <= angle + STEP_DEG;
                        else                               angle <= ANGLE_MAX;
                    end
                    default: angle <= angle; // 停止：保持不变
                endcase
            end
            else upd_cnt <= upd_cnt + 1'b1;

            // 根据当前角度算脉宽（用乘法代替除法，避免时序违例）
            pulse_reg <= PULSE_MIN + (angle * 370);
        end
    end

    assign pwm_out   = (pwm_cnt < pulse_reg) ? 1'b1 : 1'b0;
    assign angle_dbg = angle;

endmodule