`timescale 1ns / 1ps
//2026.9.13
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
    output         O_face_valid    ,
    // 当前已消抖显示模式 (0=RGB 1=GRAY 2=HIST 3=SOBEL 4=CART),
    // 供下游 OSD 文字层锁定视频 MUX 同步显示
    output [2:0]   O_display_mode  
);

    // =========================================================================
    // 1. 按键消抖与模式切换状态机
    //    模式: 0:原图(伽马校正) 1:灰度 2:直方图均衡 3:Sobel边缘 4:卡通化风格化
    // =========================================================================
    reg [2:0]  display_mode;
    reg [19:0] btn_cnt;
    reg        btn_d0, btn_d1;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            btn_d0       <= 1'b1;
            btn_d1       <= 1'b1;
            btn_cnt      <= 20'd0;
            display_mode <= 3'd0; // 默认输出原图(已做伽马校正)
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
                    if (!I_button[0]) begin
                        // 5 个模式循环: 0->1->2->3->4->0
                        if (display_mode == 3'd4)
                            display_mode <= 3'd0;
                        else
                            display_mode <= display_mode + 1'b1;
                    end
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
    // 5. 伽马校正 (全工程只做这一次) + 各模式数据统一对齐到 16 拍延迟
    //    (RGB2Y 3拍 + Sobel 5拍 + 腐蚀 4拍 + 膨胀 4拍 = 16拍):
    //    原图:   伽马后延迟 16 拍                     -> raw_rgb_d[15]
    //    卡通:   伽马后延迟  7 拍                     -> raw_rgb_d[6]
    //            (卡通内部固定 9 拍, 7+9 = 16, 与其它档严格同拍)
    //    灰度:   由伽马后的 RGB 现算 (R+2G+B)/4        -> gray_gam (第 16 拍)
    //    直方图: 彩色转换链路见第 6 节 (Y_eq+Cb/Cr -> RGB, 共 16 拍)
    //    Sobel:  sobel_tdata 与 tvalid_sobel 本身对齐
    //
    //    【只用一个伽马】伽马是无记忆的组合逻辑(0 拍), 所以放在最前面做一次,
    //    后面用两条纯寄存器延迟链分别取第 7 拍(卡通)与第 16 拍(原图)即可,
    //    不需要第二个伽马实例。
    //    注意: raw_rgb_d 里装的已经是"伽马校正后"的数据, 名字沿用原来的,
    //          不要再把它当线性原图使用。
    // =========================================================================
    wire [7:0] gamma_r, gamma_g, gamma_b;
    gamma_lut u_gamma_lut (
        .I_r (I_tdata[23:16]),
        .I_g (I_tdata[15: 8]),
        .I_b (I_tdata[ 7: 0]),
        .O_r (gamma_r),
        .O_g (gamma_g),
        .O_b (gamma_b)
    );

    reg [23:0] raw_rgb_d [0:15];
    integer i;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            for (i = 0; i < 16; i = i + 1)
                raw_rgb_d[i] <= 24'd0;
        end
        else begin
            // 延迟链随时钟无条件推进, 与 Sobel 控制信号严格同拍
            // 链里装的是伽马校正后的原图数据
            raw_rgb_d[0] <= {gamma_r, gamma_g, gamma_b};
            for (i = 0; i < 15; i = i + 1)
                raw_rgb_d[i+1] <= raw_rgb_d[i];
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
    // 6c. 卡通化图像风格化 (Cartoon Top)
    //
    // 【时序对齐 —— 关键，别乱改】
    //   整条 vpp 流水线的输出必须落在第 16 拍:
    //   design_top_wrapper.v 把 vs 延迟 17 拍来匹配 "vpp 16 拍 + OSD 1 拍",
    //   hdmi_tx 的 de 又是跟着数据走的 —— 所以只要某一档的总延迟不是 16 拍,
    //   这一档相对同步信号就会整体横移若干像素, 表现为"最左边一条窄边条错位"。
    //
    //   cartoon_top 内部固定 9 拍 (RGB2Y 3 + Sobel 5 = 8 拍对齐, 再打 1 拍输出),
    //   因此输入必须提前到第 7 拍: 7 + 9 = 16 ✓。
    //   若像原来那样喂第 16 拍的数据, 输出是 16 + 9 = 25 拍, 会横移 9 个像素。
    //     - 数据: raw_rgb_d[6]  (= 伽马校正后再延迟 7 拍)
    //     - 控制: ycbcr 控制信号(第 3 拍)再延迟 4 拍 = 第 7 拍
    //     (伽马已在第 5 节统一做过一次, 这里不再重复例化)
    // =========================================================================
    reg [3:0] cartoon_v_dly;
    reg [3:0] cartoon_l_dly;
    reg [3:0] cartoon_u_dly;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            cartoon_v_dly <= 4'd0;
            cartoon_l_dly <= 4'd0;
            cartoon_u_dly <= 4'd0;
        end
        else begin
            cartoon_v_dly <= {cartoon_v_dly[2:0], tvalid_ycbcr};
            cartoon_l_dly <= {cartoon_l_dly[2:0], tlast_ycbcr};
            cartoon_u_dly <= {cartoon_u_dly[2:0], tuser_ycbcr};
        end
    end

    wire cartoon_in_valid = cartoon_v_dly[3];   // 第 7 拍
    wire cartoon_in_last  = cartoon_l_dly[3];
    wire cartoon_in_user  = cartoon_u_dly[3];

    wire        cartoon_tlast;
    wire        cartoon_tuser;
    wire        cartoon_tvalid;
    wire [23:0] cartoon_tdata;

    cartoon_top #(
        .IMG_WIDTH       (IMG_WIDTH       ),
        .IMG_HEIGHT      (IMG_HEIGHT      ),
        .SOBEL_THRESHOLD (SOBEL_THRESHOLD ),
        .QUANT_BITS      (4               )   // 每通道保留 4 位高比特 -> 16 级色阶
    ) u_cartoon_top (
        .I_clk    (I_clk),
        .I_rst_n  (I_rst_n),
        .I_tlast  (cartoon_in_last ),
        .I_tuser  (cartoon_in_user ),
        .I_tdata  (raw_rgb_d[6]),
        .I_tvalid (cartoon_in_valid),
        .I_tready (1'b1),
        .O_tdata  (cartoon_tdata),
        .O_tlast  (cartoon_tlast),
        .O_tuser  (cartoon_tuser),
        .O_tvalid (cartoon_tvalid),
        .O_tready ()
    );

    // =========================================================================
    // 6d. 灰度档显示数据: 直接用伽马后的 RGB 加权取灰 (R + 2G + B)/4
    //     伽马是无记忆函数, 直接对伽马后的三通道加权, 就是"显示域的灰";
    //     比原来那条线性 Y 延迟链更亮, 符合 sRGB 显示的观感。
    //     好处: 不用第二个伽马实例, 也不额外增加延迟(用的还是第 16 拍那档)。
    //     原来那条 raw_y_d 延迟链已删除(它只被模式 1 用到)。
    //     注意位宽: 三项相加最大 255+510+255 = 1020, 所以先扩到 10 位再相加。
    // =========================================================================
    wire [9:0] gray_sum = {2'b00, raw_rgb_d[15][23:16]}
                        + {1'b0,  raw_rgb_d[15][15: 8], 1'b0}
                        + {2'b00, raw_rgb_d[15][ 7: 0]};
    wire [7:0] gray_gam = gray_sum[9:2];   // /4

    // =========================================================================
    // 6e. 色度降噪 (只动色度, 亮度保持锐利, 原理见 chroma_nr.v)
    //     模块内部 3 拍, 所以从 raw_rgb_d[12] (第 13 拍) 抽输入: 13 + 3 = 16 拍 ✓
    //     只作用于【原图】和兜底档;
    //     灰度档由亮度算出, 而本模块亮度严格不变 -> 数学上不受影响, 保持原样;
    //     卡通档走 raw_rgb_d[6] (第 7 拍), 不动它, 否则会破坏 16 拍时序。
    // =========================================================================
    wire [23:0] nr_rgb;
    chroma_nr u_chroma_nr (
        .I_clk   (I_clk),
        .I_rst_n (I_rst_n),
        .I_rgb   (raw_rgb_d[12]),
        .O_rgb   (nr_rgb)
    );

    // =========================================================================
    // 7. 多路模式选择输出
    // =========================================================================
    reg [23:0] mux_tdata;
    reg        mux_tlast;
    reg        mux_tuser;
    reg        mux_tvalid;

    always @(*) begin
        case (display_mode)
            3'b000: begin // 模式 0: 彩色原图 (伽马校正后, 16 拍对齐)
                mux_tdata  = nr_rgb;
                mux_tlast  = tlast_sobel;
                mux_tuser  = tuser_sobel;
                mux_tvalid = tvalid_sobel;
            end
            3'b001: begin // 模式 1: 灰度图 (伽马域取灰, 16 拍对齐)
                mux_tdata  = {gray_gam, gray_gam, gray_gam};
                mux_tlast  = tlast_sobel;
                mux_tuser  = tuser_sobel;
                mux_tvalid = tvalid_sobel;
            end
            3'b010: begin // 模式 2: 直方图均衡化 (彩色输出, 16 拍对齐)
                mux_tdata  = he_rgb_d[6];
                mux_tlast  = tlast_sobel;
                mux_tuser  = tuser_sobel;
                mux_tvalid = tvalid_sobel;
            end
            3'b011: begin // 模式 3: Sobel 边缘检测图
                mux_tdata  = {sobel_tdata, sobel_tdata, sobel_tdata};
                mux_tlast  = tlast_sobel;
                mux_tuser  = tuser_sobel;
                mux_tvalid = tvalid_sobel;
            end
            3'b100: begin // 模式 4: 卡通化风格化 (自带控制信号)
                mux_tdata  = cartoon_tdata;
                mux_tlast  = cartoon_tlast;
                mux_tuser  = cartoon_tuser;
                mux_tvalid = cartoon_tvalid;
            end
            default: begin // 兜底: 彩色原图 (伽马校正后)
                mux_tdata  = nr_rgb;
                mux_tlast  = tlast_sobel;
                mux_tuser  = tuser_sobel;
                mux_tvalid = tvalid_sobel;
            end
        endcase
    end



     face_track_top #(
        .IMG_WIDTH      (IMG_WIDTH),
        .IMG_HEIGHT     (IMG_HEIGHT),
        .BOX_COLOR      (24'h00_FF_00)
    ) u_face_track_top (
        .I_clk          (I_clk),
        .I_rst_n        (I_rst_n),

        // =====================================================================
        // 人脸检测输入: 线性 Y (RGB2Y 后 3 拍, 与 tvalid_ycbcr 同拍)
        // 原因: 级联在 OpenCV 原始灰度图上训练; LBP 码对全局增益/亮度缩放
        //       天然不变, 但对 HE 这类强非线性映射不保持 —— HE 会直接改变
        //       LBP 码的统计分布 (且这里用的是上一帧 CDF, 逐帧漂移), 暗部
        //       噪声被拉伸成随机纹理, 造成上板漏检 + 噪点区域误检。
        //       降噪改在低分辨率路径用 lp_filter_3x3 均值滤波解决。
        // 如需回退到直方图均衡输入: 把 I_ycbcr_tvalid/tlast/tuser 换回
        // tvalid_hisequ/tlast_hisequ/tuser_hisequ, I_y_tdata 换回
        // y_equ_tdata, I_cb_tdata/I_cr_tdata 换回 cb_d[2]/cr_d[2] 即可。
        // =====================================================================
        .I_ycbcr_tvalid (tvalid_ycbcr),
        .I_ycbcr_tlast  (tlast_ycbcr),
        .I_ycbcr_tuser  (tuser_ycbcr),
        .I_y_tdata      (y_tdata),
        .I_cb_tdata     (cb_tdata),     // 检测引擎未使用, 保留接线
        .I_cr_tdata     (cr_tdata),

        // 送入 MUX 选中的待显示画面
        .I_disp_tvalid  (mux_tvalid),
        .I_disp_tlast   (mux_tlast),
        .I_disp_tuser   (mux_tuser),
        .I_disp_tdata   (mux_tdata),

        // 叠加准星后的最终视频流
        .O_disp_tvalid  (O_tvalid),
        .O_disp_tlast   (O_tlast),
        .O_disp_tuser   (O_tuser),
        .O_disp_tdata   (O_tdata),

        // 输出形心坐标供顶层舵机云台使用
        .O_face_x       (O_face_x),
        .O_face_y       (O_face_y),
        .O_face_valid   (O_face_valid)
    );

    assign O_tready = 1'b1;
    assign O_display_mode = display_mode;

endmodule