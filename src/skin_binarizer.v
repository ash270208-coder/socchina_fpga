`timescale 1ns / 1ps

module skin_binarizer_ellipse (
    input               I_clk,
    input               I_rst_n,
    
    // AXI-Stream 视频输入
    input               I_tvalid,
    input               I_tlast,
    input               I_tuser,
    input      [7:0]    I_grey_tdata,   // Y 分量
    input      [7:0]    I_Cb_data,     // Cb 分量
    input      [7:0]    I_Cr_data,     // Cr 分量
    
    // 结果输出
    output reg          O_tvalid,
    output reg          O_tlast,
    output reg          O_tuser,
    output reg          O_skin_mask     // 1: 肤色, 0: 背景
);

    // =========================================================================
    // 定点化常数定义 (Q8 定点数，乘以 256,避免除法）
    // =========================================================================
    localparam signed [15:0] COS_THETA     = -16'sd210;
    localparam signed [15:0] SIN_THETA     =  16'sd147;
    localparam signed [15:0] NEG_SIN_THETA = -16'sd147;
    
    localparam signed [8:0]  CB_CENTER     = 9'sd109;
    localparam signed [8:0]  CR_CENTER     = 9'sd152;
    
    localparam signed [31:0] COEFF_B2      = 32'sd197;
    localparam signed [31:0] COEFF_A2      = 32'sd645;
    localparam signed [31:0] ELLIPSE_TH    = 32'sd8300000;
    
    localparam               LATENCY = 3;  // 数据通路到达比较前的流水线级数

    // ========================================================================
    // 1. 数据运算通路
    // ========================================================================
    // Stage 1: 去中心化
    reg signed [8:0]  d_cb;
    reg signed [8:0]  d_cr;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            d_cb <= 9'sd0;
            d_cr <= 9'sd0;
        end else begin
            d_cb <= $signed({1'b0, I_Cb_data}) - CB_CENTER;
            d_cr <= $signed({1'b0, I_Cr_data}) - CR_CENTER;
        end
    end

    // Stage 2: 旋转变换 (定点矩阵乘法)
    reg signed [17:0] x_rot;
    reg signed [17:0] y_rot;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            x_rot <= 18'sd0;
            y_rot <= 18'sd0;
        end else begin
            x_rot <= (COS_THETA * d_cb) + (SIN_THETA * d_cr);
            y_rot <= (NEG_SIN_THETA * d_cb) + (COS_THETA * d_cr);
        end
    end

    // Stage 3: 平方与加权累加 (计算椭圆距离)
    reg signed [31:0] dist_val;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            dist_val <= 32'sd0;
        end else begin
            // 算术右移 4 位防止位宽溢出
            dist_val <= COEFF_B2 * ((x_rot >>> 4) * (x_rot >>> 4)) +
                        COEFF_A2 * ((y_rot >>> 4) * (y_rot >>> 4));
        end
    end

    // =========================================================================
    // 2. 控制与伴随数据移位寄存器（统一打拍对齐）
    // =========================================================================
    reg [LATENCY-1:0] valid_sr;
    reg [LATENCY-1:0] last_sr;
    reg [LATENCY-1:0] user_sr;
    reg [7:0]         grey_sr [0:LATENCY-1];

    integer i;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            valid_sr <= {LATENCY{1'b0}};
            last_sr  <= {LATENCY{1'b0}};
            user_sr  <= {LATENCY{1'b0}};
            for (i = 0; i < LATENCY; i = i + 1) begin
                grey_sr[i] <= 8'd0;
            end
        end else begin
            // 位拼接实现移位寄存器
            valid_sr <= {valid_sr[LATENCY-2:0], I_tvalid};
            last_sr  <= {last_sr[LATENCY-2:0],  I_tlast};
            user_sr  <= {user_sr[LATENCY-2:0],  I_tuser};
            
            // 多维数组打拍传递 Y 分量
            grey_sr[0] <= I_grey_tdata;
            for (i = 1; i < LATENCY; i = i + 1) begin
                grey_sr[i] <= grey_sr[i-1];
            end
        end
    end

    // 对齐到 Stage 3 计算结果的控制信号与亮度分量
    wire       aligned_valid = valid_sr[LATENCY-1];
    wire       aligned_last  = last_sr[LATENCY-1];
    wire       aligned_user  = user_sr[LATENCY-1];
    wire [7:0] aligned_grey  = grey_sr[LATENCY-1];

    // =========================================================================
    // 3. 输出级：判断与注册输出（总延迟 = LATENCY + 1 拍）
    // =========================================================================
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_tvalid    <= 1'b0;
            O_tlast     <= 1'b0;
            O_tuser     <= 1'b0;
            O_skin_mask <= 1'b0;
        end else begin
            O_tvalid <= aligned_valid;
            O_tlast  <= aligned_last;
            O_tuser  <= aligned_user;

            // 落在椭圆内且亮度 Y 在合适区间 (50 ~ 230)
            if (aligned_valid && (dist_val <= ELLIPSE_TH) && 
                (aligned_grey > 8'd50) && (aligned_grey < 8'd230)) begin
                O_skin_mask <= 1'b1;
            end else begin
                O_skin_mask <= 1'b0;
            end
        end
    end

endmodule