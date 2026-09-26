`timescale 1ns / 1ps
// ============================================================================
// lp_filter_3x3_stream : 卡通化边缘路径 3x3 中心加权低通 (降噪 + 保边缘)
//
// 接口与 Sobel_edge 一致 (AXI-Stream 风格, 内部自计数, 无需外部 x/y 坐标),
// 因此可直接插在 RGB888_YCbCr444 与 Sobel_edge 之间。
//
// 目的: 传感器在高模拟增益(15.75x)+数字增益(1.5x)下暗部噪声很大, 直接进
//       Sobel 会被当成边缘, 再经 3x3 膨胀后放大成黑噪点。低通把噪声标准差
//       压到约 1/3, 显著减少假边缘 (这是卡通"噪点太多"的主要来源)。
//
// 为什么用中心加权而非均匀均值: 均匀 3x3 均值会把真实边缘的梯度一起磨平,
//       导致卡通描边变少/变淡。改用二项式核 [1 2 1; 2 4 2; 1 2 1]/16
//       (中心权重 4/16) 后, 去噪能力几乎不变(σ -> 0.375σ), 但边缘保留明显
//       更好 —— 中心像素占 25%, 不会被 8 个邻域平均淹没。
//
// 窗口: 以当前像素 (x,y) 为右下角的因果 3x3 (x-2..x, y-2..y), 中心为
//       (x-1,y-1)=l1_1。÷16 即右移 4, 最大 4080/16=255, 无需饱和。
// 边界: x<2 或 y<2 的像素原样透传 (行缓存前两行/前两列不可用)。
// 延迟: 固定 2 拍 (窗口构建 1 拍 + 输出寄存器 1 拍, 数据/控制同步)。
// 资源: 2 行行缓存 (IMG_WIDTH x 8bit) + 少量寄存器, 综合为 BRAM/DRAM 皆可。
// ============================================================================
module lp_filter_3x3_stream #(
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

    // ---- 行列坐标计数器 (col_cnt/row_cnt 与当前像素严格对齐, 0 起) ----
    // 不变式: 任意时钟周期 col_cnt/row_cnt 恒等于当前输入像素的坐标。
    //   复位后为 0; tuser(SOF) 当前像素是 col 0, 下一像素为 col 1 -> 置 1;
    //   tlast/行末 当前是行尾, 下一像素回到 col 0 并 row+1; 其余 col+1。
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

    // ---- 行缓存: line1 = 上一行, line2 = 上两行 (按列 col_cnt 读写, 读优先) ----
    (* ram_style = "block" *) reg [7:0] line1 [0:IMG_WIDTH-1];
    (* ram_style = "block" *) reg [7:0] line2 [0:IMG_WIDTH-1];

    // 仿真用, 防止出现 x 态
    integer init_i;
    initial begin
        for (init_i = 0; init_i < IMG_WIDTH; init_i = init_i + 1) begin
            line1[init_i] = 8'd0;
            line2[init_i] = 8'd0;
        end
    end

    // ---- 当前行窗口: w1=(x,y) w2=(x-1,y) w3=(x-2,y) ----
    reg [7:0] w1, w2, w3;
    // ---- 上一行窗口: l1_0=(x,y-1) l1_1=(x-1,y-1) l1_2=(x-2,y-1) ----
    reg [7:0] l1_0, l1_1, l1_2;
    // ---- 上两行窗口: l2_0=(x,y-2) l2_1=(x-1,y-2) l2_2=(x-2,y-2) ----
    reg [7:0] l2_0, l2_1, l2_2;

    // ---- 滤波判定 (x>=2 且 y>=2 时窗口内 9 个点全部有效) ----
    reg       do_filter;

    // ---- 数据/控制统一打 1 拍 ----
    reg [7:0] g_d1;
    reg       v_d1;
    reg       l_d1;
    reg       u_d1;

    // ---- 中心加权 3x3 求和 (组合逻辑) 与 ÷16 ----
    //   权重布局 (因果窗口, 中心 = l1_1):
    //     l2_2(1) l2_1(2) l2_0(1)
    //     l1_2(2) l1_1(4) l1_0(2)
    //     w3(1)   w2(2)   w1(1)
    //   权重和 = 16, ÷16 即右移 4; 最大 255*16=4080, /16=255, 无需饱和。
    wire [11:0] sum_w = {4'd0, w1}           // w1*1
                      + {3'd0, w2, 1'b0}     // w2*2
                      + {4'd0, w3}           // w3*1
                      + {3'd0, l1_0, 1'b0}   // l1_0*2
                      + {2'd0, l1_1, 2'b00}  // l1_1*4
                      + {3'd0, l1_2, 1'b0}   // l1_2*2
                      + {4'd0, l2_0}         // l2_0*1
                      + {3'd0, l2_1, 1'b0}   // l2_1*2
                      + {4'd0, l2_2};        // l2_2*1
    wire [7:0]  avg16 = sum_w[11:4];        // /16, 最大 255

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            w1 <= 8'd0; w2 <= 8'd0; w3 <= 8'd0;
            l1_0 <= 8'd0; l1_1 <= 8'd0; l1_2 <= 8'd0;
            l2_0 <= 8'd0; l2_1 <= 8'd0; l2_2 <= 8'd0;
            do_filter <= 1'b0;
            g_d1 <= 8'd0;
            v_d1 <= 1'b0;
            l_d1 <= 1'b0;
            u_d1 <= 1'b0;
            O_tvalid <= 1'b0;
            O_tuser  <= 1'b0;
            O_tlast  <= 1'b0;
            O_grey_tdata <= 8'd0;
        end else begin
            // ---- 第 1 拍: 窗口移位 + 行缓存滚动 (仅有效拍移位) ----
            if (I_tvalid) begin
                l1_0 <= line1[col_cnt];           // 读上一行同列 (读优先: 旧值)
                l2_0 <= line2[col_cnt];           // 读上两行同列
                line2[col_cnt] <= line1[col_cnt]; // 行缓存滚动
                line1[col_cnt] <= I_grey_tdata;
                l1_2 <= l1_1; l1_1 <= l1_0;       // 上/上两行 前两列延迟链
                l2_2 <= l2_1; l2_1 <= l2_0;
                w3   <= w2;   w2   <= w1;  w1 <= I_grey_tdata;
                do_filter <= (col_cnt >= 12'd2) && (row_cnt >= 12'd2);
            end else begin
                do_filter <= 1'b0;
            end

            // ---- 数据/控制打 1 拍 ----
            g_d1 <= I_grey_tdata;
            v_d1 <= I_tvalid;
            l_d1 <= I_tlast;
            u_d1 <= I_tuser;

            // ---- 第 2 拍: 输出 (滤波或透传), 与数据同拍对齐 ----
            O_tvalid <= v_d1;
            O_tuser  <= u_d1;
            O_tlast  <= l_d1;
            if (v_d1) begin
                O_grey_tdata <= do_filter ? avg16 : g_d1;
            end else begin
                O_grey_tdata <= 8'd0;
            end
        end
    end

endmodule
