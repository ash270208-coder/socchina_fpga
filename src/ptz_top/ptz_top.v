`timescale 1ns / 1ps

module ptz_top (
    input  wire        clk,           // 接 cnn_clk
    input  wire        rst_n,         // 接 ~reset

    // 直接连 CNN 的输出
    input  wire        I_face_valid,  // 接 cnn_valid
    input  wire [7:0]  I_face_x,      // 接 cnn_x1
    input  wire [7:0]  I_face_w,      // 接 cnn_w
    input  wire [7:0]  I_face_h,      // 接 cnn_h

    output wire        O_servo_pwm    // 输出给舵机
);

    // 提取真实的“人脸存在”脉冲 (w>=2 且 h>=2 才是真脸)
    wire true_face_found = I_face_valid && (I_face_w >= 8'd2) && (I_face_h >= 8'd2);

    // 例化底层云台控制
    ptz_servo_ctrl #(
        .CLK_HZ     (25_000_000),
        .ANGLE_MAX  (270),
        .CENTER_CX2 (128),
        .DEADZONE   (12),
        .STEP_DEG   (2)
    ) u_ptz_servo_ctrl (
        .clk          (clk),
        .rst_n        (rst_n),
        .target_valid (true_face_found), // 已经过滤了假有效信号
        .target_x     (I_face_x),
        .target_y     (8'd0),            // 悬空不用
        .target_w     (I_face_w),
        .target_h     (I_face_h),
        .pwm_out      (O_servo_pwm),
        .angle_dbg    ()
    );

endmodule