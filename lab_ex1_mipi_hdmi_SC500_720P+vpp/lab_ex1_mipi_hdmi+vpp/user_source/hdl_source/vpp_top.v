`timescale 1ns / 1ps
//2026.9.13
module vpp_top #(
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720,
    parameter SOBEL_THRESHOLD = 60,      // 模式 3 (Sobel 显示) 阈值
    parameter CART_SOBEL_THRESHOLD = 60  // 模式 4 (卡通) 阈值: 低通已降噪, 阈值回退到 60 保留描边; 可在 40~70 微调
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
    //    卡通:   伽马后延迟  1 拍                     -> raw_rgb_d[0]
    //            (卡通内部固定 15 拍, 1+15 = 16, 与其它档严格同拍)
    //    灰度:   由伽马后的 RGB 现算 (R+2G+B)/4        -> gray_gam (第 16 拍)
    //    直方图: 彩色转换链路见第 6 节 (Y_eq+Cb/Cr -> RGB, 共 16 拍)
    //    Sobel:  sobel_tdata 与 tvalid_sobel 本身对齐
    //
    //    【只用一个伽马】伽马是无记忆的组合逻辑(0 拍), 所以放在最前面做一次,
    //    后面用两条纯寄存器延迟链分别取第 1 拍(卡通)与第 16 拍(原图)即可,
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
    //    -> gamma(0拍) -> chroma_nr(3拍) -> 再补 4 拍 = 16 拍, 与 tvalid_sobel 对齐
    //    (直方图内部已加对比度限制/裁剪, 见 histogram_equ.v 的 CLIP_DIV 参数)
    // =========================================================================
    wire [7:0]  he_r_tdata;
    wire [7:0]  he_g_tdata;
    wire [7:0]  he_b_tdata;

    // 模式 2 专用: gamma(0 拍) + 色度降噪(3 拍)，例化见 6b 节
    wire [7:0]  he_gamma_r, he_gamma_g, he_gamma_b;
    wire [23:0] he_gamma_rgb = {he_gamma_r, he_gamma_g, he_gamma_b};
    wire [23:0] he_nr_rgb;

    reg [7:0]   cb_d [0:2];
    reg [7:0]   cr_d [0:2];
    reg         he_tvalid_d [0:2];
    reg         he_tlast_d  [0:2];
    reg         he_tuser_d  [0:2];
    // he_rgb_d 只补 4 拍: 9(转换) + 3(chroma_nr) + 4 = 16 拍
    reg [23:0]  he_rgb_d [0:3];

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            for (i = 0; i < 3; i = i + 1) begin
                cb_d[i]        <= 8'd0;
                cr_d[i]        <= 8'd0;
                he_tvalid_d[i] <= 1'b0;
                he_tlast_d[i]  <= 1'b0;
                he_tuser_d[i]  <= 1'b0;
            end
            for (i = 0; i < 4; i = i + 1)
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

            // 转换后的 RGB (9 拍) -> 模式2 专用 gamma(0 拍) -> chroma_nr(3 拍)
            // = 12 拍, 再补 4 拍 -> 16 拍, 与 Sobel 路径对齐
            he_rgb_d[0] <= he_nr_rgb;
            for (i = 0; i < 3; i = i + 1)
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
    // 6b. 模式 2 的色调域统一 + 色度降噪 (A+E+G 里的 E、G)
    //     原先模式 2 是"均衡后的 Y + 原始 Cb/Cr"直接转 RGB 输出，两个问题：
    //       ① 别的档都过 gamma_lut（扣黑电平 + γ2.2），只有它不过 -> 色调域不一致；
    //       ② 它的 Cb/Cr 没过色度降噪 -> 彩色噪点直接可见。
    //     现在补上：gamma_lut 纯组合(0 拍)，chroma_nr 内部 3 拍，
    //     所以整条链路仍然落在第 16 拍（见上面 he_rgb_d 的说明）。
    //     (信号声明在 6 节开头)
    // =========================================================================
    gamma_lut u_gamma_lut_he (
        .I_r (he_r_tdata),
        .I_g (he_g_tdata),
        .I_b (he_b_tdata),
        .O_r (he_gamma_r),
        .O_g (he_gamma_g),
        .O_b (he_gamma_b)
    );

    chroma_nr u_chroma_nr_he (
        .I_clk   (I_clk),
        .I_rst_n (I_rst_n),
        .I_rgb   (he_gamma_rgb),
        .O_rgb   (he_nr_rgb)
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
    //   cartoon_top 内部固定 15 拍 (RGB2Y 3 + LP 2 + Sobel 5 + 膨胀 4 = 14 拍
    //   对齐, 再打 1 拍输出), 因此输入必须提前到第 1 拍: 1 + 15 = 16 ✓。
    //   若像原来那样喂第 3 拍的数据, 输出是 3 + 15 = 18 拍, 会横移 2 个像素。
    //     - 数据: raw_rgb_d[0]  (= 伽马校正后再延迟 1 拍)
    //     - 控制: 输入 tvalid/tlast/tuser 打 1 拍
    //     (伽马已在第 5 节统一做过一次, 这里不再重复例化)
    // =========================================================================
    reg cartoon_in_valid;
    reg cartoon_in_last;
    reg cartoon_in_user;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            cartoon_in_valid <= 1'b0;
            cartoon_in_last  <= 1'b0;
            cartoon_in_user  <= 1'b0;
        end
        else begin
            cartoon_in_valid <= I_tvalid;
            cartoon_in_last  <= I_tlast;
            cartoon_in_user  <= I_tuser;
        end
    end

    wire        cartoon_tlast;
    wire        cartoon_tuser;
    wire        cartoon_tvalid;
    wire [23:0] cartoon_tdata;

    cartoon_top #(
        .IMG_WIDTH       (IMG_WIDTH          ),
        .IMG_HEIGHT      (IMG_HEIGHT         ),
        .SOBEL_THRESHOLD (CART_SOBEL_THRESHOLD),
        .QUANT_BITS      (4                  )   // 每通道保留 4 位高比特 -> 16 级色阶
    ) u_cartoon_top (
        .I_clk    (I_clk),
        .I_rst_n  (I_rst_n),
        .I_tlast  (cartoon_in_last ),
        .I_tuser  (cartoon_in_user ),
        .I_tdata  (raw_rgb_d[0]),
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
    //     卡通档走 raw_rgb_d[0] (第 1 拍), 不动它, 否则会破坏 16 拍时序。
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
            3'b010: begin // 模式 2: 直方图均衡化 (已过 gamma + 色度降噪, 16 拍对齐)
                mux_tdata  = he_rgb_d[3];
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




    // =========================================================================
    // 人脸检测已移除（板 A 只做图像处理）：MUX 选中的显示画面直通输出
    //   原 face_track_top（LBP 级联检测 + 画框 + 准星）已从本工程解绑，
    //   相关源文件仍保留在磁盘上作为归档，分类见 docs/BOARD_SPLIT.md。
    //   如需恢复人脸检测：git checkout b21e965 -- user_source/hdl_source/vpp_top.v
    //
    //   ⚠ 时序相位：原 face_track_top 内的 osd_box_drawer 会给显示通路加 1 拍，
    //     删除后整条 DE 链路少 1 拍，因此 design_top_wrapper.v 中给 hdmi_tx 的
    //     vsync 相位补偿已同步由 21 拍改为 20 拍（S_vsync_dly[19]）。
    //     以后若在此处增删寄存器级，必须同步修改那个补偿拍数，否则 vs/de 错位。
    // =========================================================================
    assign O_tdata  = mux_tdata;
    assign O_tlast  = mux_tlast;
    assign O_tuser  = mux_tuser;
    assign O_tvalid = mux_tvalid;

    assign O_tready = 1'b1;
    assign O_display_mode = display_mode;

endmodule
