`timescale 1ns / 1ps

module ptz_top (
    input  wire       I_clk_50m,
    input  wire       I_rst_n,
    input  wire       I_button_0,  // A键（对应板载KEY1）
    input  wire       I_button_1,  // B键（对应板载KEY2）
    output wire       O_servo_pwm,
    output wire [3:0] O_led
);

    localparam DEB_MAX = 20'd999_999; // 20ms @ 50MHz

    // 按键消抖
    reg [19:0] cnt_a; reg st_a, pv_a;
    reg [19:0] cnt_b; reg st_b, pv_b;

    // 状态定义
    localparam S_STOP  = 2'b00;
    localparam S_LEFT  = 2'b01;
    localparam S_RIGHT = 2'b10;
    reg [1:0] state;

    always @(posedge I_clk_50m or negedge I_rst_n) begin
        if (!I_rst_n) begin
            cnt_a <= 20'd0; st_a <= 1'b1; pv_a <= 1'b1;
            cnt_b <= 20'd0; st_b <= 1'b1; pv_b <= 1'b1;
            state <= S_STOP;
        end
        else begin
            // ---- 按键0（A键）消抖 ----
            if (I_button_0 == st_a) cnt_a <= 20'd0;
            else if (cnt_a == DEB_MAX) begin cnt_a <= 20'd0; st_a <= I_button_0; end
            else cnt_a <= cnt_a + 1'b1;
            pv_a <= st_a;

            // ---- 按键1（B键）消抖 ----
            if (I_button_1 == st_b) cnt_b <= 20'd0;
            else if (cnt_b == DEB_MAX) begin cnt_b <= 20'd0; st_b <= I_button_1; end
            else cnt_b <= cnt_b + 1'b1;
            pv_b <= st_b;

            // ---- 按键0（A键）处理 ----
            if (pv_a && !st_a) begin
                case (state)
                    S_STOP : state <= S_LEFT;
                    S_LEFT : state <= S_STOP;
                    S_RIGHT: state <= S_LEFT;
                    default: state <= S_LEFT;
                endcase
            end
            // ---- 按键1（B键）处理 ----
            else if (pv_b && !st_b) begin
                case (state)
                    S_STOP : state <= S_RIGHT;
                    S_RIGHT: state <= S_STOP;
                    S_LEFT : state <= S_RIGHT;
                    default: state <= S_RIGHT;
                endcase
            end
        end
    end

    // 状态转方向信号
    wire [1:0] dir;
    assign dir = (state == S_LEFT)  ? 2'b01 :
                 (state == S_RIGHT) ? 2'b10 : 2'b00;

    // 云台控制例化
    wire [8:0] angle_dbg;

    ptz_servo_ctrl #(
        .CLK_HZ    (50_000_000),
        .ANGLE_MAX (270),
        .STEP_DEG  (1),          // 每 50ms 转 1°，想快改成 2 或 3
        .UPDATE_MS (50)
    ) u_ptz_servo_ctrl (
        .clk       (I_clk_50m),
        .rst_n     (I_rst_n),
        .dir       (dir),
        .pwm_out   (O_servo_pwm),
        .angle_dbg (angle_dbg)
    );

    assign O_led = angle_dbg[3:0];

endmodule