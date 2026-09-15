`timescale 1ns / 1ps

module cartoon_top #(
    parameter IMG_WIDTH        = 1280,
    parameter IMG_HEIGHT       = 720,
    parameter SOBEL_THRESHOLD  = 60,
    parameter QUANT_BITS       = 4
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
    // 卡通化算法顶层集成模块 (Cartoon Top)
    // =========================================================================
    // 2026 嵌赛 FPGA 选题二：卡通化图像风格化处理
    // 流水线：边缘提取 + 区域填充，色度低位量化方案
    //
    // 数据通路 (按本工程实际拍数标注):
    //   输入 RGB888 ─┬─ RGB888_YCbCr444(3拍) ─ Sobel_edge(5拍) ─ sobel_mask  [cycle 8]
    //                └─ Color_Quantize(2拍) ─ 延时链(+6拍) ─ quant_rgb_aligned [cycle 8]
    //   Cartoon_Blend(0拍，组合逻辑) ─ 输出寄存器(1拍) ─ O_tdata  [cycle 9]
    //
    // 两路数据在 cycle 8 严格对齐后喂入 Cartoon_Blend，防止帧撕裂。
    //
    // 【重要】本工程 user_source/hdl_source/Sobel_edge.v 是 5 级流水线输出，
    //         而 fang 分支卡通目录里那份 Sobel_edge 只有 4 级。所以延时链必须
    //         取 6 拍 (2+6 = 3+5) 才能对齐，即 QUANT_EXTRA_DLY = 6。
    //         若以后换回 4 级 Sobel，把 QUANT_EXTRA_DLY 改回 5 即可。
    // =========================================================================

    // =========================================================================
    // 1. RGB888 转 YCbCr444 (提取 Y 灰度 + Cb/Cr)
    //    流水线延迟：3 拍 (cycle 3 输出)
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
    //    I_grey_tdata 输入 Y，O_grey_tdata 输出二值 mask (8'hFF=边缘, 8'h00=非边缘)
    //    流水线延迟：5 拍 (本工程 Sobel_edge 为 5 级流水, 从 ycbcr 输出算起)
    //    Sobel 路径总延迟 = 3 + 5 = 8 拍 (cycle 8 输出)
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
    // 3. 颜色量化 (Color Quantize，低位量化海报化色块)
    //    直接量化输入 RGB888，每通道保留 QUANT_BITS 高位，低位补零
    //    流水线延迟：2 拍 (cycle 2 输出)
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
    // 4. 延时对齐链 (Delay Alignment)
    //    Sobel 路径总延迟 = RGB2YCbCr(3拍) + Sobel(5拍) = 8 拍
    //    Color_Quantize 路径延迟 = 2 拍
    //    差值 = 8 - 2 = 6 拍 → quant_rgb 需额外延迟 6 拍
    //    对齐后两路数据均在 cycle 8 到达 Cartoon_Blend 输入端
    //    控制信号使用 tlast/tuser/tvalid_sobel (已在 cycle 8)
    // =========================================================================
    localparam QUANT_EXTRA_DLY = 6;
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

    // 对齐后的量化 RGB (cycle 8)
    wire [23:0] quant_rgb_aligned = quant_rgb_d[QUANT_EXTRA_DLY-1];

    // =========================================================================
    // 5. 卡通化边缘合成 (Cartoon Blend)
    //    输入两路已在 cycle 8 对齐的数据：
    //      - quant_rgb_aligned : 量化色块 RGB888
    //      - sobel_mask[0]     : 边缘标志 (1=边缘, 0=非边缘)
    //    纯组合逻辑 (0 拍延迟)，边缘位置输出黑色描边，非边缘透传色块
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
        .I_tlast        (tlast_sobel),
        .I_tuser        (tuser_sobel),
        .I_color_tdata  (quant_rgb_aligned),
        .I_edge_flag    (sobel_mask[0]),
        .I_tvalid       (tvalid_sobel),
        .O_tlast        (tlast_blend),
        .O_tuser        (tuser_blend),
        .O_tdata        (blend_rgb),
        .O_tvalid       (tvalid_blend)
    );

    // =========================================================================
    // 6. 输出寄存器 (额外打 1 拍，改善时序，cycle 9 输出)
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

    // ready 信号透传（无反压逻辑，与 vpp_top 风格一致）
    assign O_tready = I_tready;

endmodule