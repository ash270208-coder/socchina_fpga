`timescale 1ns / 1ps

module face_track_top #(
    parameter IMG_WIDTH   = 1024,
    parameter IMG_HEIGHT  = 600,
    parameter MIN_AREA    = 2000,
    parameter CROSS_LEN   = 15,
    parameter CROSS_COLOR = 24'h00_FF_00  // 绿色准星
)(
    input               I_clk,
    input               I_rst_n,

    
    input               I_ycbcr_tvalid,
    input               I_ycbcr_tlast,
    input               I_ycbcr_tuser,
    input      [7:0]    I_y_tdata,
    input      [7:0]    I_cb_tdata,
    input      [7:0]    I_cr_tdata,

    
    input               I_disp_tvalid,
    input               I_disp_tlast,
    input               I_disp_tuser,
    input      [23:0]   I_disp_tdata,

    
    output              O_disp_tvalid,
    output              O_disp_tlast,
    output              O_disp_tuser,
    output     [23:0]   O_disp_tdata,

    
    output     [11:0]   O_face_x,
    output     [11:0]   O_face_y,
    output              O_face_valid
);

    
    wire skin_valid;
    wire skin_last;
    wire skin_user;
    wire skin_mask;

    // 1. 椭圆肤色二值化模块
    skin_binarizer_ellipse u_skin_binarizer (
        .I_clk          (I_clk),
        .I_rst_n        (I_rst_n),
        .I_tvalid       (I_ycbcr_tvalid),
        .I_tlast        (I_ycbcr_tlast),
        .I_tuser        (I_ycbcr_tuser),
        .I_grey_tdata   (I_y_tdata),
        .I_Cb_data      (I_cb_tdata),
        .I_Cr_data      (I_cr_tdata),
        .O_tvalid       (skin_valid),
        .O_tlast        (skin_last),
        .O_tuser        (skin_user),
        .O_skin_mask    (skin_mask)
    );

    // 2. 形心计算模块 (在消隐期通过除法器计算坐标)
    centroid_calc #(
        .IMG_WIDTH      (IMG_WIDTH),
        .IMG_HEIGHT     (IMG_HEIGHT),
        .MIN_AREA       (MIN_AREA)
    ) u_centroid_calc (
        .I_clk          (I_clk),
        .I_rst_n        (I_rst_n),
        .I_tvalid       (skin_valid),
        .I_tlast        (skin_last),
        .I_tuser        (skin_user),
        .I_skin_mask    (skin_mask),
        .O_face_x       (O_face_x),
        .O_face_y       (O_face_y),
        .O_face_valid   (O_face_valid)
    );

    // 3. 十字准星叠加模块 (在显示流上绘制准星)
    osd_crosshair #(
        .IMG_WIDTH      (IMG_WIDTH),
        .IMG_HEIGHT     (IMG_HEIGHT),
        .CROSS_LEN      (CROSS_LEN),
        .CROSS_COLOR    (CROSS_COLOR)
    ) u_osd_crosshair (
        .I_clk          (I_clk),
        .I_rst_n        (I_rst_n),
        .I_tvalid       (I_disp_tvalid),
        .I_tlast        (I_disp_tlast),
        .I_tuser        (I_disp_tuser),
        .I_rgb          (I_disp_tdata),
        .I_target_x     (O_face_x),
        .I_target_y     (O_face_y),
        .I_target_valid (O_face_valid),
        .O_tvalid       (O_disp_tvalid),
        .O_tlast        (O_disp_tlast),
        .O_tuser        (O_disp_tuser),
        .O_rgb          (O_disp_tdata)
    );

endmodule