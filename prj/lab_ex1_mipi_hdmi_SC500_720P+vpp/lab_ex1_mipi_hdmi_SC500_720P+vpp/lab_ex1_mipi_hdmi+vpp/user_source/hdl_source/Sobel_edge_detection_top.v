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
    input      [7:0]    I_grey_tdata,
    
    
    output              O_tvalid,
    output              O_tlast,
    output              O_tuser,
    output     [7:0]    O_grey_tdata
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
        .I_tvalid        (I_tvalid),
        .I_tlast         (I_tlast),
        .I_tuser         (I_tuser),
        .I_grey_tdata    (I_grey_tdata),
        
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