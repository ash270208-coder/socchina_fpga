`timescale 1ns / 1ps

module ptz_top (
    input  wire        clk,           // 接入大工程的 pclk (像素时钟)
    input  wire        rst_n,         // 复位

    // -------------------------------------------------------------
    // 接入大工程的以太网解析输出 (去掉 y，保留计算中心点必须的 x, w, h)
    // -------------------------------------------------------------
    input  wire        I_face_valid,  // 对应 O_face_valid
    input  wire [7:0]  I_face_x,      // 对应 O_face_x (左上角 x1)
    input  wire [7:0]  I_face_w,      // 对应 O_face_w (框宽)
    input  wire [7:0]  I_face_h,      // 对应 O_face_h (框高，仅用于判断是否有人脸)

    output wire        O_servo_pwm    // 输出给舵机
);

    // 1. 提取真实的“人脸存在”脉冲 (w>=2 且 h>=2 才是真脸)
    wire true_face_found = I_face_valid && (I_face_w >= 8'd2) && (I_face_h >= 8'd2);

    // 2. 跨时钟域同步 (打两拍防亚稳态)
    reg        sync_valid_s1, sync_valid_s2;
    reg [7:0]  sync_x_s1, sync_x_s2;
    reg [7:0]  sync_w_s1, sync_w_s2;
    reg [7:0]  sync_h_s1, sync_h_s2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_valid_s1 <= 1'b0; sync_valid_s2 <= 1'b0;
            sync_x_s1 <= 8'd0; sync_x_s2 <= 8'd0;
            sync_w_s1 <= 8'd0; sync_w_s2 <= 8'd0;
            sync_h_s1 <= 8'd0; sync_h_s2 <= 8'd0;
        end
        else begin
            sync_valid_s1 <= true_face_found; 
            sync_valid_s2 <= sync_valid_s1;
            sync_x_s1 <= I_face_x; sync_x_s2 <= sync_x_s1;
            sync_w_s1 <= I_face_w; sync_w_s2 <= sync_w_s1;
            sync_h_s1 <= I_face_h; sync_h_s2 <= sync_h_s1;
        end
    end

    // 3. 例化底层云台控制模块
    ptz_servo_ctrl #(
        .CLK_HZ     (74_250_000),  // ⚠️ 记得确认时钟，24M改24_000_000，50M改50_000_000
        .ANGLE_MAX  (270),
        .CENTER_CX2 (128),
        .DEADZONE   (12),
        .STEP_DEG   (2)
    ) u_ptz_servo_ctrl (
        .clk          (clk),
        .rst_n        (rst_n),
        .target_valid (sync_valid_s2),
        .target_x     (sync_x_s2),
        .target_y     (),           // 一维云台用不到 y，悬空
        .target_w     (sync_w_s2),
        .target_h     (sync_h_s2),
        .pwm_out      (O_servo_pwm),
        .angle_dbg    ()
    );

endmodule