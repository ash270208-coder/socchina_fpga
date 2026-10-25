`timescale 1ns / 1ps

module Sobel_edge_detection_top #(
    parameter IMG_WIDTH       = 1280,
    parameter IMG_HEIGHT      = 720,
    parameter SOBEL_THRESHOLD = 60
)(
    input               I_clk,
    input               I_rst_n,
    
    
    input               I_tvalid,
    input               I_tlast,
    input               I_tuser,
    // 【形态统一】和 cartoon_top / hist_eq_color_top 一样吃 RGB，内部自己取亮度 Y。
    //   为了不影响模式 3 的观感，外面要喂**线性域**的 RGB（gamma 之前的 I_tdata），
    //   这样算出来的 Y 和改造前完全一致，SOBEL_THRESHOLD=60 不用重调。
    input      [7:0]    I_red_tdata,
    input      [7:0]    I_green_tdata,
    input      [7:0]    I_blue_tdata,
    
    
    output              O_tvalid,
    output              O_tlast,
    output              O_tuser,
    output     [7:0]    O_grey_tdata
);

    // =========================================================================
    // 0. RGB -> Y（3 拍）
    //    控制信号由 RGB888_Y888 一起延迟 3 拍，所以下面 Sobel_edge 直接吃
    //    y_v/y_l/y_u 即可，不需要另外补控制信号。
    //    模块总延迟仍是 3 + 5 + 4 + 4 = 16 拍，和改造前完全一样。
    // =========================================================================
    wire        y_v, y_l, y_u;
    wire [7:0]  y_d;

    RGB888_Y888 #(
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT)
    ) u_rgb2y (
        .I_clk          (I_clk),
        .I_rst_n        (I_rst_n),
        .I_tlast        (I_tlast),
        .I_tuser        (I_tuser),
        .I_red_tdata    (I_red_tdata),
        .I_green_tdata  (I_green_tdata),
        .I_blue_tdata   (I_blue_tdata),
        .I_tvalid       (I_tvalid),
        .I_tready       (1'b1),
        .O_tlast        (y_l),
        .O_tuser        (y_u),
        .O_y_tdata      (y_d),
        .O_tvalid       (y_v),
        .O_tready       ()
    );

    // 1. Sobel 阶段 (5 拍延迟)
    
    wire        sobel_tvalid;
    wire        sobel_tlast;
    wire        sobel_tuser;
    wire [7:0]  sobel_tdata;
    wire        sobel_bit = (sobel_tdata == 8'hFF); // 转换为 1-bit 供腐蚀膨胀使用

    Sobel_edge #(
        .IMG_WIDTH       (IMG_WIDTH),
        .IMG_HEIGHT      (IMG_HEIGHT),
        .SOBEL_THRESHOLD (SOBEL_THRESHOLD)
    ) u_Sobel_edge (
        .I_clk           (I_clk),
        .I_rst_n         (I_rst_n),
        .I_tvalid        (y_v),
        .I_tlast         (y_l),
        .I_tuser         (y_u),
        .I_grey_tdata    (y_d),
        
        .O_tvalid        (sobel_tvalid),
        .O_tlast         (sobel_tlast),
        .O_tuser         (sobel_tuser),
        .O_grey_tdata    (sobel_tdata)
    );

   
    // 2. 腐蚀阶段信号定义 (4 拍延迟)
    
    wire        erosion_tvalid;
    wire        erosion_tlast;
    wire        erosion_tuser;
    wire        erosion_bit;

    Bit_Erosion_Detector #(
        .IMG_WIDTH       (IMG_WIDTH),
        .IMG_HEIGHT      (IMG_HEIGHT)
    ) u_Erosion (
        .I_clk           (I_clk),
        .I_rst_n         (I_rst_n),
        .I_tvalid        (sobel_tvalid),
        .I_tlast         (sobel_tlast),
        .I_tuser         (sobel_tuser),
        .I_per_img_Bit   (sobel_bit),
        
        .O_tvalid        (erosion_tvalid),
        .O_tlast         (erosion_tlast),
        .O_tuser         (erosion_tuser),
        .O_per_img_Bit   (erosion_bit)
    );

    
    // 3. 膨胀阶段 (4 拍延迟，恢复边缘强度)
    
    wire        dilation_tvalid;
    wire        dilation_tlast;
    wire        dilation_tuser;
    wire        dilation_bit;

    Bit_Dilation_Detector #(
        .IMG_WIDTH       (IMG_WIDTH),
        .IMG_HEIGHT      (IMG_HEIGHT)
    ) u_Dilation (
        .I_clk           (I_clk),
        .I_rst_n         (I_rst_n),
        .I_tvalid        (erosion_tvalid),
        .I_tlast         (erosion_tlast),
        .I_tuser         (erosion_tuser),
        .I_per_img_Bit   (erosion_bit),
        
        .O_tvalid        (dilation_tvalid),
        .O_tlast         (dilation_tlast),
        .O_tuser         (dilation_tuser),
        .O_per_img_Bit   (dilation_bit)
    );

   
    // 4. 最终输出格式转换 (1-bit 转 8-bit 显示)
    
    assign O_tvalid     = dilation_tvalid;
    assign O_tlast      = dilation_tlast;
    assign O_tuser      = dilation_tuser;
    assign O_grey_tdata = dilation_bit ? 8'hFF : 8'h00;

endmodule