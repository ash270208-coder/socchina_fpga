`timescale 1ns / 1ps

module cartoon_top #(
    parameter IMG_WIDTH        = 1280,
    parameter IMG_HEIGHT       = 720,
    parameter SOBEL_THRESHOLD  = 150,
    parameter QUANT_BITS       = 4,
    parameter COUNT_THRESHOLD  = 3
)(
    input               I_clk,
    input               I_rst_n,

    input               I_tlast,
    input               I_tuser,
    input      [23:0]   I_tdata,
    input               I_tvalid,
    input               I_tready,

    output reg [23:0]   O_tdata,
    output reg          O_tlast,
    output reg          O_tuser,
    output reg          O_tvalid,
    output              O_tready
);

    // =========================================================================
    // 1. RGB888 转 YCbCr444 (提取 Y 灰度)
    //    流水线延迟：3 拍
    // =========================================================================
    wire        tlast_ycbcr;
    wire        tuser_ycbcr;
    wire        tvalid_ycbcr;
    wire [7:0]  y_tdata;
    wire [7:0]  cb_tdata;
    wire [7:0]  cr_tdata;

    RGB888_YCbCr444 #(
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT)
    ) u_RGB888_YCbCr444 (
        .I_clk          (I_clk),
        .I_rst_n        (I_rst_n),
        .I_tlast        (I_tlast),
        .I_tuser        (I_tuser),
        .I_red_tdata    (I_tdata[23:16]),
        .I_green_tdata  (I_tdata[15:8]),
        .I_blue_tdata   (I_tdata[7:0]),
        .I_tvalid       (I_tvalid),
        .I_tready       (I_tready),
        .O_tlast        (tlast_ycbcr),
        .O_tuser        (tuser_ycbcr),
        .O_y_tdata      (y_tdata),
        .O_cb_tdata     (cb_tdata),
        .O_cr_tdata     (cr_tdata),
        .O_tvalid       (tvalid_ycbcr),
        .O_tready       ()
    );

    // =========================================================================
    // 2. Sobel 边缘检测 (对 Y 灰度做边缘提取，输出二值 mask)
    //    流水线延迟：4 拍
    // =========================================================================
    wire        tlast_sobel;
    wire        tuser_sobel;
    wire        tvalid_sobel;
    wire [7:0]  sobel_mask;

    Sobel_edge #(
        .IMG_WIDTH       (IMG_WIDTH),
        .IMG_HEIGHT      (IMG_HEIGHT),
        .SOBEL_THRESHOLD (SOBEL_THRESHOLD)
    ) u_Sobel_edge (
        .I_clk          (I_clk),
        .I_rst_n        (I_rst_n),
        .I_tlast        (tlast_ycbcr),
        .I_tuser        (tuser_ycbcr),
        .I_grey_tdata   (y_tdata),
        .I_tvalid       (tvalid_ycbcr),
        .O_tlast        (tlast_sobel),
        .O_tuser        (tuser_sobel),
        .O_grey_tdata   (sobel_mask),
        .O_tvalid       (tvalid_sobel)
    );

    // =========================================================================
    // 3. 颜色量化 (Color Quantize)
    //    流水线延迟：2 拍
    // =========================================================================
    wire        tlast_quant;
    wire        tuser_quant;
    wire        tvalid_quant;
    wire [23:0] quant_rgb;

    Color_Quantize #(
        .QUANT_BITS (QUANT_BITS)
    ) u_Color_Quantize (
        .I_clk      (I_clk),
        .I_rst_n    (I_rst_n),
        .I_tlast    (I_tlast),
        .I_tuser    (I_tuser),
        .I_tdata    (I_tdata),
        .I_tvalid   (I_tvalid),
        .O_tlast    (tlast_quant),
        .O_tuser    (tuser_quant),
        .O_tdata    (quant_rgb),
        .O_tvalid   (tvalid_quant)
    );

    // =========================================================================
    // 4. 延时对齐链
    //    边缘路径 = 3 + 4 + 4 + 4 = 15 拍
    //    Color_Quantize = 2 拍
    //    差值 = 15 - 2 = 13 拍
    // =========================================================================
    localparam QUANT_EXTRA_DLY = 13;
    reg [23:0] quant_rgb_d [0:QUANT_EXTRA_DLY-1];

    integer i;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            for (i = 0; i < QUANT_EXTRA_DLY; i = i + 1)
                quant_rgb_d[i] <= 24'd0;
        end
        else if (I_tready) begin
            quant_rgb_d[0] <= quant_rgb;
            for (i = 0; i < QUANT_EXTRA_DLY - 1; i = i + 1)
                quant_rgb_d[i+1] <= quant_rgb_d[i];
        end
    end

    wire [23:0] quant_rgb_aligned = quant_rgb_d[QUANT_EXTRA_DLY-1];

    // =========================================================================
    // 5. 边缘处理：邻域计数去噪 → 膨胀加粗
    // =========================================================================
    wire sobel_edge = sobel_mask[0];

    // ---- 5.1 邻域计数去噪 ----
    wire        tvalid_cnt;
    wire        tlast_cnt;
    wire        tuser_cnt;
    wire        edge_cnt;

    Bit_Neighbor_Count #(
        .IMG_WIDTH       (IMG_WIDTH),
        .IMG_HEIGHT      (IMG_HEIGHT),
        .COUNT_THRESHOLD (COUNT_THRESHOLD)
    ) u_Bit_Neighbor_Count (
        .I_clk          (I_clk),
        .I_rst_n        (I_rst_n),
        .I_tlast        (tlast_sobel),
        .I_tuser        (tuser_sobel),
        .I_per_img_Bit  (sobel_edge),
        .I_tvalid       (tvalid_sobel),
        .O_tlast        (tlast_cnt),
        .O_tuser        (tuser_cnt),
        .O_per_img_Bit  (edge_cnt),
        .O_tvalid       (tvalid_cnt)
    );

    // ---- 5.2 膨胀加粗 ----
    wire        tvalid_dilate;
    wire        tlast_dilate;
    wire        tuser_dilate;
    wire        edge_dilated;

    Bit_Dilation_Detector #(
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT)
    ) u_Bit_Dilation_Detector (
        .I_clk          (I_clk),
        .I_rst_n        (I_rst_n),
        .I_tlast        (tlast_cnt),
        .I_tuser        (tuser_cnt),
        .I_per_img_Bit  (edge_cnt),
        .I_tvalid       (tvalid_cnt),
        .O_tlast        (tlast_dilate),
        .O_tuser        (tuser_dilate),
        .O_per_img_Bit  (edge_dilated),
        .O_tvalid       (tvalid_dilate)
    );

    // =========================================================================
    // 6. 卡通化边缘合成 (Cartoon Blend)
    // =========================================================================
    wire        tlast_blend;
    wire        tuser_blend;
    wire        tvalid_blend;
    wire [23:0] blend_rgb;

    Cartoon_Blend #(
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT)
    ) u_Cartoon_Blend (
        .I_clk          (I_clk),
        .I_rst_n        (I_rst_n),
        .I_tlast        (tlast_dilate),
        .I_tuser        (tuser_dilate),
        .I_color_tdata  (quant_rgb_aligned),
        .I_edge_flag    (edge_dilated),
        .I_tvalid       (tvalid_dilate),
        .O_tlast        (tlast_blend),
        .O_tuser        (tuser_blend),
        .O_tdata        (blend_rgb),
        .O_tvalid       (tvalid_blend)
    );

    // =========================================================================
    // 7. 输出寄存器 (打 1 拍)
    // =========================================================================
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_tdata  <= 24'd0;
            O_tlast  <= 1'b0;
            O_tuser  <= 1'b0;
            O_tvalid <= 1'b0;
        end
        else begin
            O_tdata  <= blend_rgb;
            O_tlast  <= tlast_blend;
            O_tuser  <= tuser_blend;
            O_tvalid <= tvalid_blend;
        end
    end

    assign O_tready = I_tready;

endmodule