`timescale 1ns / 1ps

module vpp_top #(
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720,
    parameter SOBEL_THRESHOLD = 60,
    parameter MIN_FACE_AREA = 2000
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
    output         O_tready        ,
    
    //输出给云台控制模块的信号
    output [11:0]  O_face_x        ,
    output [11:0]  O_face_y        ,
    output         O_face_valid     
);

    // =========================================================================
    // 0. 自动曝光 (输入侧全局) — AE 提亮后的 RGB888 作为全部下游分支的统一输入源
    // =========================================================================
    /*
    wire        ae_tlast;
    wire        ae_tuser;
    wire [23:0] ae_tdata;
    wire        ae_tvalid;

    auto_exposure_top #(
        .IMG_WIDTH  (IMG_WIDTH),
        .IMG_HEIGHT (IMG_HEIGHT),
        .TARGET_Y   (128),
        .GAIN_FRAC  (12)
    ) u_auto_exposure_top (
        .I_clk      (I_clk),
        .I_rst_n    (I_rst_n),
        .I_tlast    (I_tlast),
        .I_tuser    (I_tuser),
        .I_tdata    (I_tdata),
        .I_tvalid   (I_tvalid),
        .I_tready   (I_tready),
        .O_tlast    (ae_tlast),
        .O_tuser    (ae_tuser),
        .O_tdata    (ae_tdata),
        .O_tvalid   (ae_tvalid),
        .O_tready   ()
    );
    */
    // =========================================================================
    // 1. 按键消抖与模式切换状态机 (0:原图, 1:灰度, 2:直方图均衡, 3:Sobel边缘)
    // =========================================================================
    reg [3:0]  display_mode;
    reg [19:0] btn_cnt;
    reg        btn_d0, btn_d1;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            btn_d0       <= 1'b1;
            btn_d1       <= 1'b1;
            btn_cnt      <= 20'd0;
            display_mode <= 4'b0000; // 默认输出原图
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

    Sobel_edge_detection_top #(
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
    // 5. 各模式数据统一对齐到 Sobel 路径的 16 拍延迟
    //    (RGB2Y 3拍 + Sobel 5拍 + 腐蚀 4拍 + 膨胀 4拍 = 16拍):
    //    原图:   延迟 16 拍             -> raw_rgb_d[15]
    //    灰度:   y_tdata 已延迟 3 拍, 再补 13 拍 -> raw_y_d[12]
    //    直方图: 彩色转换链路见第 6 节 (Y_eq+Cb/Cr -> RGB, 共 16 拍)
    //    Sobel:  sobel_tdata 与 tvalid_sobel 本身对齐
    // =========================================================================
    reg [23:0] raw_rgb_d [0:15];
    reg [7:0]  raw_y_d   [0:12];
    integer i;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            for (i = 0; i < 16; i = i + 1)
                raw_rgb_d[i] <= 24'd0;
            for (i = 0; i < 13; i = i + 1)
                raw_y_d[i]   <= 8'd0;
        end
        else begin
            // 两条链随时钟无条件推进, 与 Sobel 控制信号严格同拍
            raw_rgb_d[0] <= I_tdata;
            for (i = 0; i < 15; i = i + 1)
                raw_rgb_d[i+1] <= raw_rgb_d[i];

            raw_y_d[0] <= y_tdata;
            for (i = 0; i < 12; i = i + 1)
                raw_y_d[i+1] <= raw_y_d[i];
        end
    end

    // =========================================================================
    // 6. 直方图均衡彩色输出链路 (均衡 Y + 原色度, 恢复彩色):
    //    y_equ(6拍) 与 Cb/Cr(3拍, 补 3 拍 = 6拍) 对齐 -> YCbCr444_RGB888(3拍, =9拍)
    //    -> RGB 再补 7 拍 = 16 拍, 与 tvalid_sobel 对齐
    // =========================================================================
    wire [7:0]  he_r_tdata;
    wire [7:0]  he_g_tdata;
    wire [7:0]  he_b_tdata;

    reg [7:0]   cb_d [0:2];
    reg [7:0]   cr_d [0:2];
    reg         he_tvalid_d [0:2];
    reg         he_tlast_d  [0:2];
    reg         he_tuser_d  [0:2];
    reg [23:0]  he_rgb_d [0:6];

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            for (i = 0; i < 3; i = i + 1) begin
                cb_d[i]        <= 8'd0;
                cr_d[i]        <= 8'd0;
                he_tvalid_d[i] <= 1'b0;
                he_tlast_d[i]  <= 1'b0;
                he_tuser_d[i]  <= 1'b0;
            end
            for (i = 0; i < 7; i = i + 1)
                he_rgb_d[i] <= 24'd0;
        end
        else begin
            // Cb/Cr 及控制信号补 3 拍, 与 y_equ (6 拍) 对齐
            cb_d[0]        <= cb_tdata;
            cr_d[0]        <= cr_tdata;
            he_tvalid_d[0] <= tvalid_ycbcr;
            he_tlast_d[0]  <= tlast_ycbcr;
            he_tuser_d[0]  <= tuser_ycbcr;
            for (i = 0; i < 2; i = i + 1) begin
                cb_d[i+1]        <= cb_d[i];
                cr_d[i+1]        <= cr_d[i];
                he_tvalid_d[i+1] <= he_tvalid_d[i];
                he_tlast_d[i+1]  <= he_tlast_d[i];
                he_tuser_d[i+1]  <= he_tuser_d[i];
            end

            // 转换后的 RGB (9 拍) 再补 7 拍, 与 Sobel 路径的 16 拍对齐
            he_rgb_d[0] <= {he_r_tdata, he_g_tdata, he_b_tdata};
            for (i = 0; i < 6; i = i + 1)
                he_rgb_d[i+1] <= he_rgb_d[i];
        end
    end

    YCbCr444_RGB888 #(
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT)
    ) u_YCbCr444_RGB888 (
        .I_clk         (I_clk),
        .I_rst_n       (I_rst_n),
        .I_tlast       (he_tlast_d[2]),
        .I_tuser       (he_tuser_d[2]),
        .I_y_tdata     (y_equ_tdata),
        .I_cb_tdata    (cb_d[2]),
        .I_cr_tdata    (cr_d[2]),
        .I_tvalid      (he_tvalid_d[2]),
        .I_tready      (1'b1),
        .O_tlast       (),
        .O_tuser       (),
        .O_red_tdata   (he_r_tdata),
        .O_green_tdata (he_g_tdata),
        .O_blue_tdata  (he_b_tdata),
        .O_tvalid      (),
        .O_tready      ()
    );

    // =========================================================================
    // 5. 卡通化图像风格化模块 (Cartoon Top)
    //    输入原图 RGB888，输出卡通化 RGB888 (cycle 8)
    //    display_mode 模式 4 时通过 MUX 输出
    // =========================================================================
    /*
    wire        cartoon_tlast;
    wire        cartoon_tuser;
    wire        cartoon_tvalid;
    wire [23:0] cartoon_tdata;

    cartoon_top #(
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT)
    ) u_cartoon_top (
        .I_clk    (I_clk),
        .I_rst_n  (I_rst_n),
        .I_tlast  (ae_tlast),
        .I_tuser  (ae_tuser),
        .I_tdata  (ae_tdata),
        .I_tvalid (ae_tvalid),
        .I_tready (1'b1),
        .O_tdata  (cartoon_tdata),
        .O_tlast  (cartoon_tlast),
        .O_tuser  (cartoon_tuser),
        .O_tvalid (cartoon_tvalid),
        .O_tready ()
    );
    */
    // =========================================================================
    // 7. 多路模式选择输出
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
      //      4'b0100: begin // 模式 4: 卡通化图像风格化
           //     mux_tdata  = cartoon_tdata;
           //     mux_tlast  = cartoon_tlast;
           //     mux_tuser  = cartoon_tuser;
           //     mux_tvalid = cartoon_tvalid;
           // end
            default: begin // 其余模式默认输出彩色原图
                mux_tdata  = raw_rgb_d[6];
                mux_tlast  = tlast_sobel;
                mux_tuser  = tuser_sobel;
                mux_tvalid = tvalid_sobel;
            end
        endcase
    end

    assign O_tready = 1'b1;

endmodule