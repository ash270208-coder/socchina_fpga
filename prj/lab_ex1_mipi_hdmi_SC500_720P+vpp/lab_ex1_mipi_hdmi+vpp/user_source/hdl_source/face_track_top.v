`timescale 1ns / 1ps

module face_track_top #(
    parameter IMG_WIDTH   = 1280,
    parameter IMG_HEIGHT  = 720,
    parameter BOX_COLOR   = 24'h00_FF_00  // 亮绿色人脸框 (RGB888)
)(
    input               I_clk,            // 像素时钟
    input               I_rst_n,          // 异步复位

    // 视频输入流 (用于算法检测，Cb/Cr保留端口以兼容系统连线)
    input               I_ycbcr_tvalid,
    input               I_ycbcr_tlast,
    input               I_ycbcr_tuser,
    input      [7:0]    I_y_tdata,        // 亮度/灰度分量
    input      [7:0]    I_cb_tdata,       // (未使用)
    input      [7:0]    I_cr_tdata,       // (未使用)

    // RGB 显示输入流 (用于画框叠加)
    input               I_disp_tvalid,
    input               I_disp_tlast,
    input               I_disp_tuser,
    input      [23:0]   I_disp_tdata,

    // RGB 显示输出流 (送往 hdmi_tx / 显示屏)
    output              O_disp_tvalid,
    output              O_disp_tlast,
    output              O_disp_tuser,
    output     [23:0]   O_disp_tdata,

    // 算法检测出的人脸中心坐标 (供外部 MCU / 舵机云台跟踪使用)
    output     [11:0]   O_face_x,         // 人脸中心 X 坐标 (1280 空间)
    output     [11:0]   O_face_y,         // 人脸中心 Y 坐标 (720 空间)
    output              O_face_valid      // 人脸有效脉冲
);

    // 1. 6x6 灰度单通道降采样模块 (1280x720 -> 213x120)
    wire        low_valid;
    wire        low_user;
    wire        low_last;
    wire [7:0]  low_gray;
    wire [7:0]  low_x;
    wire [7:0]  low_y;

    downscaler #(
        .SCALE_FACTOR   (6),
        .OUT_WIDTH      (213),
        .OUT_HEIGHT     (120)
    ) u_downscaler (
        .I_clk          (I_clk),
        .I_rst_n        (I_rst_n),
        .I_tvalid       (I_ycbcr_tvalid),
        .I_tuser        (I_ycbcr_tuser),
        .I_tlast        (I_ycbcr_tlast),
        .I_grey_tdata   (I_y_tdata),
        .O_tvalid       (low_valid),
        .O_tuser        (low_user),
        .O_tlast        (low_last),
        .O_grey_tdata   (low_gray),
        .O_x            (low_x),
        .O_y            (low_y)
    );

    // 1.5 3x3 均值降噪 (低分辨率路径, 固定 2 拍延迟)
    //     抑制高增益下的传感器噪声, 稳定 LBP 编码 (替代原先在输入侧
    //     用直方图均衡的错误做法 —— HE 的非线性映射会破坏 LBP 码分布)
    wire        flt_valid;
    wire        flt_user;
    wire        flt_last;
    wire [7:0]  flt_gray;
    wire [7:0]  flt_x;
    wire [7:0]  flt_y;

    lp_filter_3x3 #(
        .IMG_WIDTH  (213),
        .IMG_HEIGHT (120)
    ) u_lp_filter (
        .I_clk      (I_clk),
        .I_rst_n    (I_rst_n),
        .I_tvalid   (low_valid),
        .I_tuser    (low_user),
        .I_tlast    (low_last),
        .I_grey     (low_gray),
        .I_x        (low_x),
        .I_y        (low_y),
        .O_tvalid   (flt_valid),
        .O_tuser    (flt_user),
        .O_tlast    (flt_last),
        .O_grey     (flt_gray),
        .O_x        (flt_x),
        .O_y        (flt_y)
    );

    // 2. 2D 积分图发生器
    wire        int_valid;
    wire        int_user;
    wire        int_last;
    wire [23:0] int_val;
    wire [7:0]  int_x;
    wire [7:0]  int_y;

    integral_image #(
        .IMG_WIDTH      (213),
        .IMG_HEIGHT     (120)
    ) u_integral_image (
        .I_clk          (I_clk),
        .I_rst_n        (I_rst_n),
        
        .I_tvalid       (flt_valid),
        .I_tuser        (flt_user),
        .I_tlast        (flt_last),
        .I_grey_tdata   (flt_gray),
        .I_x            (flt_x),
        .I_y            (flt_y),
        
        .O_tvalid       (int_valid),
        .O_tuser        (int_user),
        .O_tlast        (int_last),
        .O_integral     (int_val),
        .O_x            (int_x),
        .O_y            (int_y)
    );

    // 3. 纯 LBP 级联人脸检测引擎
    wire        det_face_valid;
    wire [7:0]  det_face_x;
    wire [7:0]  det_face_y;
    wire [7:0]  det_face_w;
    wire [7:0]  det_face_h;

    lbp_detector_engine #(
        .IMG_WIDTH      (213),
        .IMG_HEIGHT     (120),
        .WIN_SIZE       (24)
    ) u_lbp_engine (
        .I_clk          (I_clk),
        .I_rst_n        (I_rst_n),
        
        .I_tvalid       (int_valid),
        .I_tuser        (int_user),
        .I_integral     (int_val),
        .I_x            (int_x),
        .I_y            (int_y),
        
        .O_face_valid   (det_face_valid),
        .O_face_x       (det_face_x),     // 人脸左上角 X (213 空间)
        .O_face_y       (det_face_y),     // 人脸左上角 Y (120 空间)
        .O_face_w       (det_face_w),
        .O_face_h       (det_face_h)
    );

    // 4. 坐标映射放大回原图尺寸 (中心坐标)
    //    引擎输出整窗矩形 (左上角 + win_w), 中心 = 左上角 + 窗宽/2:
    //    center = x*6 + w*3  (用移位加法: 6x = 4x+2x, 3w = 2w+w)
    wire [11:0] center_x = {1'b0, det_face_x, 2'b00} + {2'b00, det_face_x, 1'b0}
                         + {2'b00, det_face_w, 1'b0} + {4'b0000, det_face_w};
    wire [11:0] center_y = {2'b00, det_face_y, 2'b00} + {3'b000, det_face_y, 1'b0}
                         + {2'b00, det_face_h, 1'b0} + {4'b0000, det_face_h};

    assign O_face_valid = det_face_valid;
    assign O_face_x     = (center_x >= IMG_WIDTH)  ? (IMG_WIDTH - 1)  : center_x;
    assign O_face_y     = (center_y >= IMG_HEIGHT) ? (IMG_HEIGHT - 1) : center_y;

    // 5. 高清 OSD 画框模块
    osd_box_drawer #(
        .IN_WIDTH       (IMG_WIDTH),
        .IN_HEIGHT      (IMG_HEIGHT),
        .SCALE_FACTOR   (6),
        .LINE_THICK     (3),              // 3 像素线宽
        .BOX_COLOR      (BOX_COLOR),      // 矩形颜色
        .HOLD_FRAMES    (15)              // 防丢帧平滑
    ) u_osd_box_drawer (
        .I_clk          (I_clk),
        .I_rst_n        (I_rst_n),
        .I_tvalid       (I_disp_tvalid),
        .I_tlast        (I_disp_tlast),
        .I_tuser        (I_disp_tuser),
        .I_tdata        (I_disp_tdata),
        .I_face_valid   (det_face_valid),
        .I_face_x       (det_face_x),
        .I_face_y       (det_face_y),
        .I_face_w       (det_face_w),
        .I_face_h       (det_face_h),
        .O_tvalid       (O_disp_tvalid),
        .O_tlast        (O_disp_tlast),
        .O_tuser        (O_disp_tuser),
        .O_tdata        (O_disp_tdata)
    );

endmodule