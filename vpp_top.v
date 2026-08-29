`timescale 1ns / 1ps

module vpp_top #(
    parameter IMG_WIDTH  = 1024,
    parameter IMG_HEIGHT = 600,
    parameter SOBEL_THRESHOLD =60
    
)( 
    input  [1:0]   I_button        ,  // 按键输入，用于切换显示模式
    
    input          I_clk           ,
    input          I_rst_n         ,
    input          I_tlast         ,
    input          I_tuser         ,
    input  [23:0]  I_tdata         ,
    input          I_tvalid        ,
    input          I_tdest         ,
    input          I_tready        ,
    output [23:0]  O_tdata         ,
    output         O_tlast         ,
    output         O_tuser         ,
    output         O_tvalid        ,
    output         O_tready        
);

    // =========================================================================
    // 1. 按键消抖与模式切换状态机 (0:原图, 1:灰度, 2:直方图均衡, 3:Sobel边缘)
    // =========================================================================
    reg [1:0]  display_mode;
    reg [19:0] btn_cnt;
    reg        btn_d0, btn_d1;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            btn_d0       <= 1'b1;
            btn_d1       <= 1'b1;
            btn_cnt      <= 20'd0;
            display_mode <= 2'b00; // 默认输出原图
        end
        else begin
            btn_d0 <= I_button[0];
            btn_d1 <= btn_d0;
            
            // 按键下降沿消抖 (假设低电平按下)
            if (btn_d1 && !btn_d0) begin
                btn_cnt <= 20'd1;
            end
            else if (btn_cnt > 20'd0) begin
                if (btn_cnt == 20'd1_000_000) begin // 约 10~20ms 消抖
                    btn_cnt <= 20'd0;
                    if (!I_button[0])
                        display_mode <= display_mode + 1'b1;
                end
                else begin
                    btn_cnt <= btn_cnt + 1'b1;
                end
            end
        end
    end

    // =========================================================================
    // 2. RGB 转 YCbCr (提取 Y 灰度)
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
    // 3. 直方图均衡化模块
    // =========================================================================
    wire        tlast_hisequ;
    wire        tuser_hisequ;
    wire        tvalid_hisequ;
    wire [7:0]  y_equ_tdata;

    histogram_equ #(
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT)
    ) u_histogram_equ (
        .I_clk              (I_clk),       
        .I_rst_n            (I_rst_n),     
        .I_tlast            (tlast_ycbcr),     
        .I_tuser            (tuser_ycbcr),     
        .I_grey_tdata       (y_tdata),
        .I_tvalid           (tvalid_ycbcr),    
        .O_tlast            (tlast_hisequ),     
        .O_tuser            (tuser_hisequ),     
        .O_grey_tdata       (y_equ_tdata),
        .O_tvalid           (tvalid_hisequ)     
    );

    // =========================================================================
    // 4. Sobel 边缘检测模块 (接 Y 灰度分量)
    // =========================================================================
    wire        tlast_sobel;
    wire        tuser_sobel;
    wire        tvalid_sobel;
    wire [7:0]  sobel_tdata;

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
        .O_grey_tdata   (sobel_tdata),
        .O_tvalid       (tvalid_sobel)
    );

    // =========================================================================
    // 5. 对原图与灰度图做延时对齐 (与 Sobel 对齐约 4 拍，防止切换撕裂)
    // =========================================================================
    reg [23:0] raw_rgb_d [0:7];
    reg [7:0]  raw_y_d   [0:7];
    integer i;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            for (i = 0; i < 8; i = i + 1) begin
                raw_rgb_d[i] <= 24'd0;
                raw_y_d[i]   <= 8'd0;
            end
        end
        else begin
            // 原图随时钟无条件推进（RGB2Y 3拍 + Sobel 4拍 = 总共对齐 7 拍）
            raw_rgb_d[0] <= I_tdata;
            for (i = 0; i < 7; i = i + 1)
                raw_rgb_d[i+1] <= raw_rgb_d[i];

            // 灰度图随时钟无条件推进（对齐 Sobel 的 4 拍延时）
            raw_y_d[0] <= y_tdata;
            for (i = 0; i < 7; i = i + 1)
                raw_y_d[i+1] <= raw_y_d[i];
        end
    end

    // =========================================================================
    // 6. 多路模式选择输出
    // =========================================================================
    reg [23:0] mux_tdata;
    reg        mux_tlast;
    reg        mux_tuser;
    reg        mux_tvalid;

    always @(*) begin
        case (display_mode)
            2'b00: begin // 模式 0: 彩色原图 (对齐时钟)
                mux_tdata  = raw_rgb_d[6];
                mux_tlast  = tlast_sobel;
                mux_tuser  = tuser_sobel;
                mux_tvalid = tvalid_sobel;
            end
            2'b01: begin // 模式 1: Y 灰度图
                mux_tdata  = {raw_y_d[3], raw_y_d[3], raw_y_d[3]};
                mux_tlast  = tlast_sobel;
                mux_tuser  = tuser_sobel;
                mux_tvalid = tvalid_sobel;
            end
            2'b10: begin // 模式 2: 直方图均衡化
                mux_tdata  = {y_equ_tdata, y_equ_tdata, y_equ_tdata};
                mux_tlast  = tlast_hisequ;
                mux_tuser  = tuser_hisequ;
                mux_tvalid = tvalid_hisequ;
            end
            2'b11: begin // 模式 3: Sobel 边缘检测图
                mux_tdata  = {sobel_tdata, sobel_tdata, sobel_tdata};
                mux_tlast  = tlast_sobel;
                mux_tuser  = tuser_sobel;
                mux_tvalid = tvalid_sobel;
            end
        endcase
    end

    assign O_tdata  = mux_tdata;
    assign O_tlast  = mux_tlast;
    assign O_tuser  = mux_tuser;
    assign O_tvalid = mux_tvalid;
    assign O_tready = 1'b1;

endmodule