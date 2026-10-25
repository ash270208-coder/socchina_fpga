`timescale 1ns/1ps
// ===========================================================================
// RGB888_Y888.v -- RGB888 -> Y888（只取亮度），3 拍流水
//
// 命名：沿用 RGB888_YCbCr444.v 的约定 —— "从 RGB888 转成 Y888"，
//       一眼能看出这是一个色彩格式转换模块，而不是某种格式的名字。
//
// 为什么要单独一个模块：
//   直方图均衡和 Sobel 都只需要 Y，但 RGB888_YCbCr444 一次算 Y+Cb+Cr
//   要 9 个乘法器。这颗芯片总共只有 40 个 DSP，原设计已经用满 40/40，
//   再加乘法器就会逼工具把两对乘法器硬塞进一个 9x9 DSP（TD 的
//   "will be merged into ... by using 9x9 mode"），而 Sobel/卡通恰好
//   对落到它们头上的打包很敏感。只算 Y 只要 3 个乘法器。
//
// 定点与 RGB888_YCbCr444 的 Y 完全一致（保证 Sobel 行为不变）：
//   Y = (77*R + 150*G + 29*B) >> 8        (77+150+29 = 256)
//
// 时序：3 拍，端口/控制信号语义与 RGB888_YCbCr444 相同，可直接替换。
// ===========================================================================
module RGB888_Y888 #(
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720
)(
    input  wire       I_clk,
    input  wire       I_rst_n,

    input  wire       I_tlast,
    input  wire       I_tuser,
    input  wire [7:0] I_red_tdata,
    input  wire [7:0] I_green_tdata,
    input  wire [7:0] I_blue_tdata,
    input  wire       I_tvalid,
    input  wire       I_tready,

    output reg        O_tlast,
    output reg        O_tuser,
    output reg  [7:0] O_y_tdata,
    output reg        O_tvalid,
    output            O_tready
);

    assign O_tready = I_tready;

    reg [1:0] tvalid_dly;
    reg [1:0] tlast_dly;
    reg [1:0] tuser_dly;

    // ---- Stage 1: 三个常数乘法 ----
    reg [15:0] mult_y_r, mult_y_g, mult_y_b;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            mult_y_r <= 16'd0; mult_y_g <= 16'd0; mult_y_b <= 16'd0;
        end
        else if (I_tvalid && I_tready) begin
            mult_y_r <= I_red_tdata   * 8'd77;
            mult_y_g <= I_green_tdata * 8'd150;
            mult_y_b <= I_blue_tdata  * 8'd29;
        end
    end

    // ---- Stage 2: 求和 ----
    reg [17:0] sum_y;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n)
            sum_y <= 18'd0;
        else if (tvalid_dly[0])
            sum_y <= mult_y_r + mult_y_g + mult_y_b;
    end

    // ---- Stage 3: 右移 8 位输出 ----
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n)
            O_y_tdata <= 8'd0;
        else if (tvalid_dly[1])
            O_y_tdata <= sum_y[15:8];
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            tvalid_dly <= 2'b0;
            tlast_dly  <= 2'b0;
            tuser_dly  <= 2'b0;
            O_tvalid   <= 1'b0;
            O_tlast    <= 1'b0;
            O_tuser    <= 1'b0;
        end
        else begin
            tvalid_dly <= {tvalid_dly[0], (I_tvalid && I_tready)};
            tlast_dly  <= {tlast_dly[0],  I_tlast};
            tuser_dly  <= {tuser_dly[0],  I_tuser};

            O_tvalid   <= tvalid_dly[1];
            O_tlast    <= tlast_dly[1];
            O_tuser    <= tuser_dly[1];
        end
    end

endmodule
