`timescale 1ns/1ps
//=============================================================================
// hist_eq_color_top.v -- 彩色直方图均衡（特征级模块）
//
// 【形态】和 cartoon_top / Sobel_edge_detection_top 一样：
//        吃 RGB、吐 RGB、固定拍数、自包含 —— 接上就能独立仿真/复用，
//        不依赖外部任何 Y 信号或对齐链。
//
//   契约： I_rgb(24b) + 控制  ->  O_rgb(24b) + 控制，固定 9 拍
//
//   内部 = 三段，各自都是"通用算子"，在这里被组合成一个特征：
//     1) RGB888_Y888  (3 拍)  RGB -> Y                     （显示域亮度）
//     2) histogram_equ(3 拍)  Y   -> Y'                    （直方图均衡，通用 8-bit 音调映射器）
//     3) hue_scale    (3 拍)  RGB * (Y'/Y) -> RGB          （保色：色相/饱和度严格不变）
//
// 【为什么不是把这三段塞进 histogram_equ】
//   histogram_equ 的价值就在于"纯 8 位音调映射器"（任意 8-bit 信号都能喂，
//   可单独仿真、已有 histogram_equ_clip_tb）。把颜色策略焊进去会让它失去通用性，
//   也让"算法"和"保色策略"两件事耦合。这里用组合而不是修改：
//   算子保持通用，特征用薄包装拼出来。
//
// 【对齐】Y 和 RGB 要在第 6 拍同时到达 hue_scale：
//   Y_d      -> y_old_d[0..2]  (补到第 6 拍)
//   I_rgb    -> rgb_d[0..5]    (补到第 6 拍)
//   然后 hue_scale 3 拍 -> 第 9 拍输出。
//=============================================================================
module hist_eq_color_top #(
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720
)(
    input  wire        I_clk,
    input  wire        I_rst_n,

    input  wire        I_tlast,
    input  wire        I_tuser,
    input  wire [23:0] I_rgb,
    input  wire        I_tvalid,

    output wire        O_tlast,
    output wire        O_tuser,
    output wire        O_tvalid,
    output wire [23:0] O_rgb
);

    // -------------------------------------------------------------------------
    // 1. RGB -> Y（3 拍）
    // -------------------------------------------------------------------------
    wire       y_v, y_l, y_u;
    wire [7:0] y_d;

    RGB888_Y888 #(
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT)
    ) u_rgb2y (
        .I_clk          (I_clk),
        .I_rst_n        (I_rst_n),
        .I_tlast        (I_tlast),
        .I_tuser        (I_tuser),
        .I_red_tdata    (I_rgb[23:16]),
        .I_green_tdata  (I_rgb[15: 8]),
        .I_blue_tdata   (I_rgb[ 7: 0]),
        .I_tvalid       (I_tvalid),
        .I_tready       (1'b1),
        .O_tlast        (y_l),
        .O_tuser        (y_u),
        .O_y_tdata      (y_d),
        .O_tvalid       (y_v),
        .O_tready       ()
    );

    // -------------------------------------------------------------------------
    // 2. 直方图均衡（3 拍）：Y -> Y'
    //    用上一帧的 CDF 映射当前帧；上电第一帧 CDF 为空（输出全 0），第二帧起正常。
    // -------------------------------------------------------------------------
    wire       he_v, he_l, he_u;
    wire [7:0] y_new;

    histogram_equ #(
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT)
    ) u_histogram_equ (
        .I_clk        (I_clk),
        .I_rst_n      (I_rst_n),
        .I_tlast      (y_l),
        .I_tuser      (y_u),
        .I_grey_tdata (y_d),
        .I_tvalid     (y_v),
        .O_tlast      (he_l),
        .O_tuser      (he_u),
        .O_grey_tdata (y_new),
        .O_tvalid     (he_v)
    );

    // -------------------------------------------------------------------------
    // 3. 对齐：Y(HE 之前) 与 RGB 各补到第 6 拍（与 y_new/hess 同拍）
    // -------------------------------------------------------------------------
    reg [7:0]  y_old_d [0:2];
    reg [23:0] rgb_d   [0:5];
    integer k;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            for (k = 0; k < 3; k = k + 1) y_old_d[k] <= 8'd0;
            for (k = 0; k < 6; k = k + 1) rgb_d[k]   <= 24'd0;
        end
        else begin
            y_old_d[0] <= y_d;
            for (k = 0; k < 2; k = k + 1)
                y_old_d[k+1] <= y_old_d[k];

            rgb_d[0] <= I_rgb;
            for (k = 0; k < 5; k = k + 1)
                rgb_d[k+1] <= rgb_d[k];
        end
    end

    // -------------------------------------------------------------------------
    // 4. 保色缩放（3 拍）：RGB' = RGB * (Y'/Y)
    // -------------------------------------------------------------------------
    wire sc_v;

    hue_scale u_hue_scale (
        .I_clk    (I_clk),
        .I_rst_n  (I_rst_n),
        .I_y_old  (y_old_d[2]),      // HE 之前的 Y
        .I_y_new  (y_new),           // HE 之后的 Y'
        .I_rgb    (rgb_d[5]),        // 与上面两个同拍
        .I_tvalid (he_v),
        .O_rgb    (O_rgb),
        .O_tvalid (sc_v)
    );

    // -------------------------------------------------------------------------
    // 5. tlast/tuser 再补 3 拍（he_l/he_u 在第 6 拍，输出在第 9 拍）
    // -------------------------------------------------------------------------
    reg [2:0] l_d, u_d;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            l_d <= 3'd0;
            u_d <= 3'd0;
        end
        else begin
            l_d <= {l_d[1:0], he_l};
            u_d <= {u_d[1:0], he_u};
        end
    end

    assign O_tvalid = sc_v;
    assign O_tlast  = l_d[2];
    assign O_tuser  = u_d[2];

endmodule
