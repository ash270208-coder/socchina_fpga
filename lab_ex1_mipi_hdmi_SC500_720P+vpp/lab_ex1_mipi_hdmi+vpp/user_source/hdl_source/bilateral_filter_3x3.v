`timescale 1ns / 1ps
// ============================================================================
// bilateral_filter_3x3 : 3x3 双边滤波 (Y 灰度, 保边缘降噪)
//
// 接口与 Sobel_edge / lp_filter_3x3_stream 一致 (AXI-Stream, 内部自计数坐标),
// 可直接插在 RGB888_YCbCr444 与 Sobel_edge 之间, 替代原来的 3x3 中心加权低通。
//
// 算法:  I'(p) = (1/W) * Σ_q  w_s(||p-q||) * w_r(|I_p - I_q|) * I_q
//   空间核 w_s : 二项式 [1 2 1; 2 4 2; 1 2 1] (中心 4 / 边 2 / 角 1)
//   距离核 w_r : 高斯 exp(-d^2 / (2*sigma_r^2)), sigma_r = 35
//   归一化   : 分子 Σ(y*w) 与分母 Σw 分别累加, 再乘 1/W 的倒数表 (Q0.16)
//
// 查表用 ROM IP (bilateral_rom_ip.v, 见该文件规格表):
//   - 距离表 bilateral_rom_range : 8bit x 256, 9 路并行读 (3x3 每个像素一路)
//   - 倒数表 bilateral_rom_recip : 16bit x 2048, 1 路
//   同步读 (doa 下一拍有效), 引擎按 1 拍读延迟设计。
//   空间核用移位实现 (中心>>0, 边>>1, 角>>2), 省掉 9 次空间×距离乘法。
//
// 总延迟固定 8 拍, 数据/控制严格同拍。
// 资源: 行缓存 2 行 (IMG_WIDTH x 8bit) + 9x256x8 距离 ROM + 2048x16 倒数 ROM。
// ============================================================================
module bilateral_filter_3x3 #(
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720
)(
    input  wire        I_clk,
    input  wire        I_rst_n,

    input  wire        I_tvalid,
    input  wire        I_tuser,
    input  wire        I_tlast,
    input  wire [7:0]  I_grey_tdata,

    output reg         O_tvalid,
    output reg         O_tuser,
    output reg         O_tlast,
    output reg  [7:0]  O_grey_tdata
);

    // =========================================================================
    // 1. 行列坐标计数器 (col_cnt/row_cnt 与当前像素严格对齐, 0 起)
    // =========================================================================
    reg [11:0] col_cnt;
    reg [11:0] row_cnt;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            col_cnt <= 12'd0;
            row_cnt <= 12'd0;
        end else if (I_tvalid) begin
            if (I_tuser) begin
                col_cnt <= 12'd1;
                row_cnt <= 12'd0;
            end else if (I_tlast || (col_cnt == IMG_WIDTH - 1)) begin
                col_cnt <= 12'd0;
                if (row_cnt == IMG_HEIGHT - 1)
                    row_cnt <= 12'd0;
                else
                    row_cnt <= row_cnt + 1'b1;
            end else begin
                col_cnt <= col_cnt + 1'b1;
            end
        end
    end

    // =========================================================================
    // 2. 双行缓存 (读优先, 与 Sobel_edge 同构)
    // =========================================================================
    (* ram_style = "block" *) reg [7:0] line_buf0 [0:IMG_WIDTH-1];
    (* ram_style = "block" *) reg [7:0] line_buf1 [0:IMG_WIDTH-1];

    integer init_i;
    initial begin
        for (init_i = 0; init_i < IMG_WIDTH; init_i = init_i + 1) begin
            line_buf0[init_i] = 8'd0;
            line_buf1[init_i] = 8'd0;
        end
    end

    reg [7:0] row0_data; // 第 y-2 行
    reg [7:0] row1_data; // 第 y-1 行
    reg [7:0] row2_data; // 第 y   行 (当前行)

    always @(posedge I_clk) begin
        if (I_tvalid) begin
            row0_data <= line_buf0[col_cnt];
            row1_data <= line_buf1[col_cnt];
            row2_data <= I_grey_tdata;

            line_buf0[col_cnt] <= line_buf1[col_cnt];
            line_buf1[col_cnt] <= I_grey_tdata;
        end
    end

    // =========================================================================
    // 3. 3x3 滑动窗口 (中心 = p22)
    //    p11 p12 p13   (第 y-2 行, col-2..col)
    //    p21 p22 p23   (第 y-1 行)
    //    p31 p32 p33   (第 y   行)
    // =========================================================================
    reg [7:0] p11, p12, p13;
    reg [7:0] p21, p22, p23;
    reg [7:0] p31, p32, p33;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            p11 <= 8'd0; p12 <= 8'd0; p13 <= 8'd0;
            p21 <= 8'd0; p22 <= 8'd0; p23 <= 8'd0;
            p31 <= 8'd0; p32 <= 8'd0; p33 <= 8'd0;
        end else if (I_tvalid) begin
            p11 <= p12; p12 <= p13; p13 <= row0_data;
            p21 <= p22; p22 <= p23; p23 <= row1_data;
            p31 <= p32; p32 <= p33; p33 <= row2_data;
        end
    end

    // =========================================================================
    // 4. 中心像素与各邻域像素的绝对亮度差 (组合逻辑)
    // =========================================================================
    wire [7:0] center_y = p22;
    wire [7:0] d00 = (p11 > center_y) ? (p11 - center_y) : (center_y - p11);
    wire [7:0] d01 = (p12 > center_y) ? (p12 - center_y) : (center_y - p12);
    wire [7:0] d02 = (p13 > center_y) ? (p13 - center_y) : (center_y - p13);
    wire [7:0] d10 = (p21 > center_y) ? (p21 - center_y) : (center_y - p21);
    wire [7:0] d11 = 8'd0;                                    // 中心自身, 差恒 0
    wire [7:0] d12 = (p23 > center_y) ? (p23 - center_y) : (center_y - p23);
    wire [7:0] d20 = (p31 > center_y) ? (p31 - center_y) : (center_y - p31);
    wire [7:0] d21 = (p32 > center_y) ? (p32 - center_y) : (center_y - p32);
    wire [7:0] d22 = (p33 > center_y) ? (p33 - center_y) : (center_y - p33);

    // =========================================================================
    // 5. 距离权重查表 (ROM IP, 同步读, 9 路并行)
    //    rXX 为原始高斯距离权重 (doa 下一拍有效)
    // =========================================================================
    wire [7:0] r00, r01, r02, r10, r11, r12, r20, r21, r22;

    bilateral_rom_range u_r00 (.doa(r00), .addra(d00), .clka(I_clk));
    bilateral_rom_range u_r01 (.doa(r01), .addra(d01), .clka(I_clk));
    bilateral_rom_range u_r02 (.doa(r02), .addra(d02), .clka(I_clk));
    bilateral_rom_range u_r10 (.doa(r10), .addra(d10), .clka(I_clk));
    bilateral_rom_range u_r11 (.doa(r11), .addra(d11), .clka(I_clk));
    bilateral_rom_range u_r12 (.doa(r12), .addra(d12), .clka(I_clk));
    bilateral_rom_range u_r20 (.doa(r20), .addra(d20), .clka(I_clk));
    bilateral_rom_range u_r21 (.doa(r21), .addra(d21), .clka(I_clk));
    bilateral_rom_range u_r22 (.doa(r22), .addra(d22), .clka(I_clk));

    // 联合权重 = 空间权重 x 距离权重, 统一除 4 (归一化时抵消):
    //   角(空间1)>>2, 边(空间2)>>1, 中心(空间4)>>0
    wire [7:0] w00 = r00 >> 2;
    wire [7:0] w01 = r01 >> 1;
    wire [7:0] w02 = r02 >> 2;
    wire [7:0] w10 = r10 >> 1;
    wire [7:0] w11 = r11;                                     // = 255
    wire [7:0] w12 = r12 >> 1;
    wire [7:0] w20 = r20 >> 2;
    wire [7:0] w21 = r21 >> 1;
    wire [7:0] w22 = r22 >> 2;

    // =========================================================================
    // 6. 流水线: 像素打拍 -> 乘积/权重打拍 -> 分子/分母求和 -> 倒数 -> 归一化乘
    //    (总 8 拍)
    // =========================================================================
    // 6a. 像素打拍 (第 3 拍), 与 ROM 输出 rXX 同拍对齐
    reg [7:0] p00_r, p01_r, p02_r, p10_r, p11_r, p12_r, p20_r, p21_r, p22_r;

    always @(posedge I_clk) begin
        p00_r <= p11; p01_r <= p12; p02_r <= p13;
        p10_r <= p21; p11_r <= p22; p12_r <= p23;
        p20_r <= p31; p21_r <= p32; p22_r <= p33;
    end

    // 6b. 乘积 + 权重打拍 (第 4 拍)
    reg [15:0] prod00, prod01, prod02, prod10, prod11, prod12, prod20, prod21, prod22;
    reg [7:0]  w00_r, w01_r, w02_r, w10_r, w11_r, w12_r, w20_r, w21_r, w22_r;

    always @(posedge I_clk) begin
        prod00 <= p00_r * w00;
        prod01 <= p01_r * w01;
        prod02 <= p02_r * w02;
        prod10 <= p10_r * w10;
        prod11 <= p11_r * w11;
        prod12 <= p12_r * w12;
        prod20 <= p20_r * w20;
        prod21 <= p21_r * w21;
        prod22 <= p22_r * w22;

        w00_r <= w00; w01_r <= w01; w02_r <= w02;
        w10_r <= w10; w11_r <= w11; w12_r <= w12;
        w20_r <= w20; w21_r <= w21; w22_r <= w22;
    end

    // 6c. 分子 (Σ y*w) 与分母 (Σ w) (第 5 拍)
    reg [23:0] num;
    reg [11:0] den;

    always @(posedge I_clk) begin
        num <= {8'd0, prod00} + {8'd0, prod01} + {8'd0, prod02}
             + {8'd0, prod10} + {8'd0, prod11} + {8'd0, prod12}
             + {8'd0, prod20} + {8'd0, prod21} + {8'd0, prod22};

        den <= {4'd0, w00_r} + {4'd0, w01_r} + {4'd0, w02_r}
             + {4'd0, w10_r} + {4'd0, w11_r} + {4'd0, w12_r}
             + {4'd0, w20_r} + {4'd0, w21_r} + {4'd0, w22_r};
    end

    // 6d. 倒数查表 (1/W, Q0.16) (第 6 拍)
    wire [15:0] inv_w;
    bilateral_rom_recip u_recip (.doa(inv_w), .addra(den[10:0]), .clka(I_clk));

    // 6e. 归一化乘法 (第 7 拍)
    reg [39:0] product;
    always @(posedge I_clk) product <= num * inv_w;

    // 6f. 舍入 + 饱和 + 输出 (第 8 拍)
    wire [39:0] product_rounded = product + 40'h0000008000;   // +0.5 (Q0.16)
    wire [7:0]  y_filtered = (|product_rounded[39:24]) ? 8'hFF : product_rounded[23:16];

    // 控制信号 8 拍对齐
    reg [7:0] vld_shift;
    reg [7:0] last_shift;
    reg [7:0] user_shift;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            vld_shift  <= 8'd0;
            last_shift <= 8'd0;
            user_shift <= 8'd0;
            O_tvalid   <= 1'b0;
            O_tlast    <= 1'b0;
            O_tuser    <= 1'b0;
            O_grey_tdata <= 8'd0;
        end else begin
            vld_shift  <= {vld_shift[6:0],  I_tvalid};
            last_shift <= {last_shift[6:0], I_tlast};
            user_shift <= {user_shift[6:0], I_tuser};

            O_tvalid <= vld_shift[7];
            O_tlast  <= last_shift[7];
            O_tuser  <= user_shift[7];
            if (vld_shift[7])
                O_grey_tdata <= y_filtered;
            else
                O_grey_tdata <= 8'd0;
        end
    end

endmodule
