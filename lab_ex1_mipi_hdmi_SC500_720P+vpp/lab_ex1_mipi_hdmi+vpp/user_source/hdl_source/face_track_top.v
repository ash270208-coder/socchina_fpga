`timescale 1ns / 1ps

//=============================================================================
// face_track_top.v —— 人脸跟踪顶层（CNN 版，替换 LBP 级联链）
//-----------------------------------------------------------------------------
// 数据通路: 显示 RGB 流(1280x720, 画框之前) → cnn_ds10(÷10 块平均 128x72)
//          → cnn_top(五层 CNN + 解码, 输出全局最高分 1 框, 128x72 空间)
//          → osd_box_drawer(SCALE=10 画绿框) + 形心输出(×10, 供云台 PID)
// 接口与原 LBP 版完全一致，vpp_top 无需改动。
// 注意: 输入取自画框之前的 I_disp 流 → CNN 永远不会看到自己画的框（无正反馈）。
//=============================================================================
module face_track_top #(
    parameter IMG_WIDTH   = 1280,
    parameter IMG_HEIGHT  = 720,
    parameter BOX_COLOR   = 24'h00_FF_00   // 亮绿色人脸框 (RGB888)
)(
    input               I_clk,            // 像素时钟 74.25MHz
    input               I_rst_n,          // 异步复位

    // 视频输入流（旧 LBP 用的 YCbCr 通道；CNN 不用，保留端口以兼容系统连线）
    input               I_ycbcr_tvalid,
    input               I_ycbcr_tlast,
    input               I_ycbcr_tuser,
    input      [7:0]    I_y_tdata,
    input      [7:0]    I_cb_tdata,
    input      [7:0]    I_cr_tdata,

    // RGB 显示输入流（CNN 检测输入 + 画框叠加源；位于画框之前）
    input               I_disp_tvalid,
    input               I_disp_tlast,
    input               I_disp_tuser,
    input      [23:0]   I_disp_tdata,

    // RGB 显示输出流 (送往 hdmi_tx / 显示屏)
    output              O_disp_tvalid,
    output              O_disp_tlast,
    output              O_disp_tuser,
    output     [23:0]   O_disp_tdata,

    // 人脸中心坐标 (1280x720 空间, 供云台 PID 跟踪)
    output     [11:0]   O_face_x,
    output     [11:0]   O_face_y,
    output              O_face_valid
);

    // =====================================================================
    // 1. ÷10 降采样（1280x720 RGB → 128x72 RGB 块平均）
    // =====================================================================
    wire        ds_valid;
    wire        ds_user;
    wire        ds_last;
    wire [23:0] ds_data;

    cnn_ds10 #(
        .IN_W   (IMG_WIDTH),
        .IN_H   (IMG_HEIGHT),
        .SCALE  (10),
        .OUT_W  (128),
        .OUT_H  (72)
    ) u_cnn_ds10 (
        .I_clk      (I_clk),
        .I_rst_n    (I_rst_n),
        .I_tvalid   (I_disp_tvalid),
        .I_tuser    (I_disp_tuser),
        .I_tlast    (I_disp_tlast),
        .I_tdata    (I_disp_tdata),
        .O_tvalid   (ds_valid),
        .O_tuser    (ds_user),
        .O_tlast    (ds_last),
        .O_tdata    (ds_data),
        .O_x        (),
        .O_y        ()
    );

    // =====================================================================
    // 2. CNN 检测器整链（128x72x3 → 全局最高分 1 框）
    // =====================================================================
    wire        cnn_valid;
    wire [7:0]  cnn_x1, cnn_y1, cnn_w, cnn_h;
    wire [15:0] cnn_score;

    cnn_top #(
        .IMG_W (128),
        .IMG_H (72)
    ) u_cnn_top (
        .clk      (I_clk),
        .rst_n    (I_rst_n),
        .I_tvalid (ds_valid),
        .I_tuser  (ds_user),
        .I_tdata  (ds_data),
        .O_busy   (),
        .O_valid  (cnn_valid),
        .O_x1     (cnn_x1),
        .O_y1     (cnn_y1),
        .O_w      (cnn_w),
        .O_h      (cnn_h),
        .O_score  (cnn_score)
    );

    // =====================================================================
    // 3. 形心换算到 1280x720 空间: center = (x1 + w/2) x 10 = x1*10 + w*5
    // =====================================================================
    wire [11:0] center_x = {1'b0, cnn_x1, 3'b0} + {2'b0, cnn_x1, 1'b0}
                         + {1'b0, cnn_w, 2'b0}  + {3'b0, cnn_w};
    wire [11:0] center_y = {1'b0, cnn_y1, 3'b0} + {2'b0, cnn_y1, 1'b0}
                         + {1'b0, cnn_h, 2'b0}  + {3'b0, cnn_h};

    assign O_face_valid = cnn_valid;
    assign O_face_x     = (center_x >= IMG_WIDTH)  ? (IMG_WIDTH  - 1) : center_x;
    assign O_face_y     = (center_y >= IMG_HEIGHT) ? (IMG_HEIGHT - 1) : center_y;

    // =====================================================================
    // 4. 高清 OSD 画框（低分辨率框坐标 ×10 放大，帧保持防闪烁）
    // =====================================================================
    osd_box_drawer #(
        .IN_WIDTH       (IMG_WIDTH),
        .IN_HEIGHT      (IMG_HEIGHT),
        .SCALE_FACTOR   (10),             // CNN 框在 128x72 空间 → ×10
        .LINE_THICK     (3),
        .BOX_COLOR      (BOX_COLOR),
        .HOLD_FRAMES    (15)
    ) u_osd_box_drawer (
        .I_clk          (I_clk),
        .I_rst_n        (I_rst_n),
        .I_tvalid       (I_disp_tvalid),
        .I_tlast        (I_disp_tlast),
        .I_tuser        (I_disp_tuser),
        .I_tdata        (I_disp_tdata),
        .I_face_valid   (cnn_valid),
        .I_face_x       (cnn_x1),
        .I_face_y       (cnn_y1),
        .I_face_w       (cnn_w),
        .I_face_h       (cnn_h),
        .O_tvalid       (O_disp_tvalid),
        .O_tlast        (O_disp_tlast),
        .O_tuser        (O_disp_tuser),
        .O_tdata        (O_disp_tdata)
    );

endmodule
