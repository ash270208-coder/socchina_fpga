`timescale 1ns / 1ps

// 注意当前输入的像素数据一定是卷积矩阵的右下角数据，所以得到的卷积数据其实是之前的输入数据的结果，并不是当前数据对应的卷积结果


module Sobel_edge #(
    parameter IMG_WIDTH       = 1280,
    parameter IMG_HEIGHT      = 720,
    parameter SOBEL_THRESHOLD = 60
)(
    input               I_clk,
    input               I_rst_n,
    
    input               I_tlast,
    input               I_tuser,
    input      [7:0]    I_grey_tdata,
    input               I_tvalid,
    
    output             O_tlast,
    output             O_tuser,
    output reg [7:0]   O_grey_tdata,
    output             O_tvalid
);

    // =========================================================================
    // 1. 行列坐标计数器
    // =========================================================================
    reg [11:0] col_cnt;
    reg [11:0] row_cnt;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            col_cnt <= 12'd0;
            row_cnt <= 12'd0;
        end
        else if (I_tvalid) begin
            if (I_tuser) begin
                col_cnt <= 12'd1;
                row_cnt <= 12'd0;
            end
            else if (I_tlast || (col_cnt == IMG_WIDTH - 1)) begin
                col_cnt <= 12'd0;
                if (row_cnt == IMG_HEIGHT - 1)
                    row_cnt <= 12'd0;
                else
                    row_cnt <= row_cnt + 1'b1;
            end
            else begin
                col_cnt <= col_cnt + 1'b1;
            end
        end
    end

    // =========================================================================
    // 2. 双行缓存（加入仿真 initial 清零，彻底消除 xxxxxx 不定态）
    // =========================================================================
    (* ram_style = "block" *) reg [7:0] line_buf0 [0:IMG_WIDTH-1];
    (* ram_style = "block" *) reg [7:0] line_buf1 [0:IMG_WIDTH-1];
    
    //仿真用，防止出现x态
    integer init_i;
    initial begin
        for (init_i = 0; init_i < IMG_WIDTH; init_i = init_i + 1) begin
            line_buf0[init_i] = 8'd0;
            line_buf1[init_i] = 8'd0;
        end
    end
    //
    reg [7:0] row0_data; // 第 y-2 行
    reg [7:0] row1_data; // 第 y-1 行
    reg [7:0] row2_data; // 第 y   行 (当前行)

    always @(posedge I_clk) begin
        if (I_tvalid) begin
            // 完美对齐读取：在同一时钟下读出第 col_cnt 列的历史数据
            row0_data <= line_buf0[col_cnt];
            row1_data <= line_buf1[col_cnt];
            row2_data <= I_grey_tdata;

            // 级联无位移写入：老数据逐行下移
            line_buf0[col_cnt] <= line_buf1[col_cnt];
            line_buf1[col_cnt] <= I_grey_tdata;
        end
    end

    // =========================================================================
    // 3. 构建 3x3 滑动窗口矩阵
    // =========================================================================
    reg [7:0] p11, p12, p13;
    reg [7:0] p21, p22, p23;
    reg [7:0] p31, p32, p33;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            p11 <= 8'd0; p12 <= 8'd0; p13 <= 8'd0;
            p21 <= 8'd0; p22 <= 8'd0; p23 <= 8'd0;
            p31 <= 8'd0; p32 <= 8'd0; p33 <= 8'd0;
        end
        else if (I_tvalid) begin
            p11 <= p12; p12 <= p13; p13 <= row0_data;
            p21 <= p22; p22 <= p23; p23 <= row1_data;
            p31 <= p32; p32 <= p33; p33 <= row2_data;
        end
    end

    // =========================================================================
    // 4. 流水线阶段 1: Sobel 卷积正负项求和
    // =========================================================================
    reg [10:0] gx_p, gx_n;
    reg [10:0] gy_p, gy_n;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            gx_p <= 11'd0; gx_n <= 11'd0;
            gy_p <= 11'd0; gy_n <= 11'd0;
        end
        else if (I_tvalid) begin
            gx_p <= p13 + (p23 << 1) + p33;
            gx_n <= p11 + (p21 << 1) + p31;

            gy_p <= p11 + (p12 << 1) + p13;
            gy_n <= p31 + (p32 << 1) + p33;
        end
    end

    // =========================================================================
    // 5. 流水线阶段 2: 绝对值差与曼哈顿距离求和
    // =========================================================================
    reg [11:0] mag;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            mag <= 12'd0;
        end
        else if (I_tvalid) begin
            mag <= ((gx_p >= gx_n) ? (gx_p - gx_n) : (gx_n - gx_p)) +
                   ((gy_p >= gy_n) ? (gy_p - gy_n) : (gy_n - gy_p));
        end
    end

    // =========================================================================
    // 6. 流水线阶段 3: 坐标延迟对齐与消边二值化输出
    // =========================================================================
    reg [11:0] row_cnt_d1, row_cnt_d2, row_cnt_d3, row_cnt_d4;
    reg [11:0] col_cnt_d1, col_cnt_d2, col_cnt_d3, col_cnt_d4;

    always @(posedge I_clk) begin
        if (I_tvalid) begin
            row_cnt_d1 <= row_cnt;
            row_cnt_d2 <= row_cnt_d1;
            row_cnt_d3 <= row_cnt_d2;
            row_cnt_d4 <= row_cnt_d3;

            col_cnt_d1 <= col_cnt;
            col_cnt_d2 <= col_cnt_d1;
            col_cnt_d3 <= col_cnt_d2;
            col_cnt_d4 <= col_cnt_d3;
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_grey_tdata <= 8'd0;
        end
        else if (I_tvalid) begin
            // 只有窗口被真实像素充满时（第 2 行、第 2 列之后）才输出 Sobel 边缘
            if ((row_cnt_d4 >= 12'd2) && (col_cnt_d4 >= 12'd2)) begin
                O_grey_tdata <= (mag >= SOBEL_THRESHOLD) ? 8'hFF : 8'h00;
            end
            else begin
                O_grey_tdata <= 8'h00;
            end
        end
    end

    // =========================================================================
    // 7. 控制信号严格打拍对齐 (数据通路共 5 级流水线延迟，控制信号精确延迟 5 拍)
    // =========================================================================
    reg [4:0] tvalid_shift; // 定义为 5 位
    reg [4:0] tlast_shift;
    reg [4:0] tuser_shift;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            tvalid_shift <= 5'd0;
            tlast_shift  <= 5'd0;
            tuser_shift  <= 5'd0;
        end
        else begin
            // 1. tvalid 必须无条件每拍移位，准确传递有效/气泡状态
            tvalid_shift <= {tvalid_shift[3:0], I_tvalid};

            // tlast/tuser 与 tvalid 一样按时钟移位，必须保留行间空泡。
            // 只在 I_tvalid 时移位会把行尾标志滞留到下一行，导致后级
            // 坐标计数和 OSD 在不同模式下漂移。
            tlast_shift <= {tlast_shift[3:0], I_tlast};
            tuser_shift <= {tuser_shift[3:0], I_tuser};
        end
    end

    // 用 assign 引出第 5 级（索引 4）的输出，保证干净、准确的 5 拍延迟
    assign O_tvalid = tvalid_shift[4];
    assign O_tlast  = tlast_shift[4];
    assign O_tuser  = tuser_shift[4];

endmodule