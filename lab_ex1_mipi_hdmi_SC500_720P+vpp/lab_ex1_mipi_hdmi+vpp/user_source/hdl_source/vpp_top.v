`timescale 1ns / 1ps
//2026.9.13
module vpp_top #(
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720,
    parameter SOBEL_THRESHOLD = 60,      // 模式 3 (Sobel 显示) 阈值
    parameter CART_SOBEL_THRESHOLD = 75  // 模式 4 (卡通) 阈值: 90 时描边偏淡、70 时黑点偏多, 折中 80; 可在 70~100 微调
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
    output [2:0]   O_display_mode  ,

    // =========================================================================
    // [以太网改造 第3步] 给 CNN 通路单独引出的取数口
    //   O_raw_tdata = raw_rgb_d[21]：伽马校正后的**原图**（22 拍对齐那一级），
    //                 **不随按键的 5 档显示模式变** —— 这是 CNN 取数的唯一正确位置。
    //                 绝不能取 mux 输出（会随模式在灰度/直方图/Sobel/卡通之间变）。
    //   O_raw_tvalid/user/last = mux_*，与 raw_rgb_d[21] 严格同拍。
    //   这 4 个口只是把内部已有寄存器引出来，不新增任何逻辑、不改动显示链路。
    // =========================================================================
    output [23:0]  O_raw_tdata     ,
    output         O_raw_tvalid    ,
    output         O_raw_tuser     ,
    output         O_raw_tlast
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
    // 2. 伽马校正（全工程只做这一次；纯组合逻辑，0 拍延迟）
    //    传感器/ISP 出来的是线性光，显示器按 sRGB(γ≈2.2) 解读输入，
    //    这里补上 out = round(255*(in/255)^(1/2.2))，并扣掉黑电平。
    //
    //    为什么放在最前面（而不是每档各做一次）：
    //      gamma 无记忆、0 拍，做一次之后所有档都从"显示域 RGB"出发，
    //      后面用纯寄存器延迟链取不同拍数即可，不需要第二个 gamma 实例。
    //      【L1】直方图档也因此能在显示域做均衡（详见 docs/HE_COLOR.md）。
    // =========================================================================
    wire [7:0] gamma_r, gamma_g, gamma_b;
    gamma_lut u_gamma_lut (
        .I_r    (I_tdata[23:16]),
        .I_g    (I_tdata[15: 8]),
        .I_b    (I_tdata[ 7: 0]),
        .O_r    (gamma_r),
        .O_g    (gamma_g),
        .O_b    (gamma_b)
    );

    // =========================================================================
    // 3. 彩色直方图均衡（特征模块，固定 9 拍）
    //    形态与 cartoon_top / Sobel_edge_detection_top 对齐：吃 RGB、吐 RGB、
    //    固定拍数、自包含，可以单独仿真/复用。
    //      内部 = RGB888_Y888(3) + histogram_equ(3) + hue_scale(3)
    //    颜色(色相+饱和度)严格不变，只有亮度按 HE 曲线走。
    //    详见 hist_eq_color_top.v 与 docs/HE_COLOR.md。
    // =========================================================================
    wire [23:0] he_rgb;          // 直方图均衡输出(仍是 24bit RGB)

    hist_eq_color_top #(
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT)
    ) u_hist_eq_color (
        .I_clk    (I_clk),
        .I_rst_n  (I_rst_n),
        .I_tlast  (I_tlast),
        .I_tuser  (I_tuser),
        .I_rgb    ({gamma_r, gamma_g, gamma_b}),
        .I_tvalid (I_tvalid),
        // 控制信号不需要:hue_scale 之后 vpp 统一用 sobel_*_d6 那套(同为 22 拍)
        .O_tlast  (),
        .O_tuser  (),
        .O_tvalid (),
        .O_rgb    (he_rgb)
    );

    // =========================================================================
    // 4. Sobel 边缘检测（特征模块：吃 RGB、内部取 Y，固定 16 拍）
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
        .I_tlast        (I_tlast),
        .I_tuser        (I_tuser),
        .I_red_tdata    (I_tdata[23:16]),
        .I_green_tdata  (I_tdata[15: 8]),
        .I_blue_tdata   (I_tdata[ 7: 0]),
        .I_tvalid       (I_tvalid),
        .O_tlast        (tlast_sobel),
        .O_tuser        (tuser_sobel),
        .O_grey_tdata   (sobel_tdata),
        .O_tvalid       (tvalid_sobel)
    );

    // =========================================================================
    // 5. 各模式数据统一对齐到 22 拍延迟（伽马已在 第 2 节统一做过一次）
    //    (卡通用了 8 拍双边滤波, 整条对齐由 16 拍放宽到 22 拍):
    //    原图:   伽马后延迟 22 拍                     -> raw_rgb_d[21]
    //    卡通:   伽马后延迟  1 拍                     -> raw_rgb_d[0]
    //            (卡通内部固定 21 拍, 1+21 = 22, 与其它档严格同拍)
    //    灰度:   由伽马后的 RGB 现算 (R+2G+B)/4        -> gray_gam (第 22 拍)
    //    直方图: hist_eq_color_top(9) + chroma_nr(3) + 补 10 拍 = 22 拍
    //    Sobel:  sobel_tdata 与 tvalid_sobel 补 6 拍 -> 第 22 拍
    //
    //    【只有一个伽马实例】它在 第 2 节, 纯组合(0 拍), 从最前面做一次; 后面用两条
    //    纯寄存器延迟链分别取第 1 拍(卡通)与第 22 拍(原图)即可, 不需要第二个实例。
    //    (L1 之后连直方图档也用它, 所以 6b 节那个 he 专用 gamma 已删除)
    //    注意: raw_rgb_d 里装的已经是"伽马校正后"的数据, 名字沿用原来的,
    //          不要再把它当线性原图使用。
    // =========================================================================
    reg [23:0] raw_rgb_d [0:21];
    integer i;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            for (i = 0; i < 22; i = i + 1)
                raw_rgb_d[i] <= 24'd0;
        end
        else begin
            // 延迟链随时钟无条件推进, 与 Sobel 控制信号严格同拍
            // 链里装的是伽马校正后的原图数据
            raw_rgb_d[0] <= {gamma_r, gamma_g, gamma_b};
            for (i = 0; i < 21; i = i + 1)
                raw_rgb_d[i+1] <= raw_rgb_d[i];
        end
    end

    // =========================================================================
    // 6. 直方图档：色度降噪 + 补拍对齐
    //    hist_eq_color_top(9) + chroma_nr(3) = 12 拍，再补 10 拍 = 22 拍。
    //    Y/HE/保色缩放都已经收进第 3 节那个特征模块里了，这里只剩"降噪 + 对齐"。
    // =========================================================================
    wire [23:0] he_nr_rgb;
    reg [23:0]  he_rgb_d [0:9];

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            for (i = 0; i < 10; i = i + 1)
                he_rgb_d[i] <= 24'd0;
        end
        else begin
            he_rgb_d[0] <= he_nr_rgb;
            for (i = 0; i < 9; i = i + 1)
                he_rgb_d[i+1] <= he_rgb_d[i];
        end
    end

    chroma_nr u_chroma_nr_he (
        .I_clk   (I_clk),
        .I_rst_n (I_rst_n),
        .I_rgb   (he_rgb),
        .O_rgb   (he_nr_rgb)
    );

    // =========================================================================
    // 6c. 卡通化图像风格化（特征模块：吃 RGB、内部取 Y，固定 21 拍）
    //
    // 【时序对齐 —— 关键，别乱改】
    //   整条 vpp 流水线的输出必须落在第 22 拍:
    //   design_top_wrapper.v 把 vs 延迟 26 拍来匹配 "vpp 22 拍 + Logo OSD 2 拍
    //   + 延迟 OSD 2 拍", hdmi_tx 的 de 又是跟着数据走的 —— 只要某一档总延迟
    //   不是 22 拍, 这一档相对同步信号就会整体横移, 表现为"最左边窄边条错位"。
    //
    //   cartoon_top 内部固定 21 拍 (RGB2Y 3 + 双边 8 + Sobel 5 + 膨胀 4 = 20 拍
    //   对齐, 再打 1 拍输出), 因此输入必须提前到第 1 拍: 1 + 21 = 22 ✓。
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
        .QUANT_BITS      (5                  )   // 每通道保留 5 位高比特 -> 32 级色阶 (过渡更细腻、色带更少)
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
    //     好处: 不用第二个伽马实例, 也不额外增加延迟(用的还是第 22 拍那档)。
    //     原来那条 raw_y_d 延迟链已删除(它只被模式 1 用到)。
    //     注意位宽: 三项相加最大 255+510+255 = 1020, 所以先扩到 10 位再相加。
    // =========================================================================
    wire [9:0] gray_sum = {2'b00, raw_rgb_d[21][23:16]}
                        + {1'b0,  raw_rgb_d[21][15: 8], 1'b0}
                        + {2'b00, raw_rgb_d[21][ 7: 0]};
    wire [7:0] gray_gam = gray_sum[9:2];   // /4

    // =========================================================================
    // 6e. 色度降噪 (只动色度, 亮度保持锐利, 原理见 chroma_nr.v)
    //     模块内部 3 拍, 所以从 raw_rgb_d[18] (第 19 拍) 抽输入: 19 + 3 = 22 拍 ✓
    //     只作用于【原图】和兜底档;
    //     灰度档由亮度算出, 而本模块亮度严格不变 -> 数学上不受影响, 保持原样;
    //     卡通档走 raw_rgb_d[0] (第 1 拍), 不动它, 否则会破坏 22 拍时序。
    // =========================================================================
    wire [23:0] nr_rgb;
    chroma_nr u_chroma_nr (
        .I_clk   (I_clk),
        .I_rst_n (I_rst_n),
        .I_rgb   (raw_rgb_d[18]),
        .O_rgb   (nr_rgb)
    );

    // =========================================================================
    // 6f. Sobel 路径统一补 6 拍 (16 → 22, 与卡通/其它档严格同拍)
    //     Sobel_edge_detection_top 内部 = RGB2Y 3 + Sobel 5 + 腐蚀 4 + 膨胀 4 = 16 拍
    // =========================================================================
    reg [7:0] sobel_tdata_d [0:5];
    reg [5:0] sobel_v_d, sobel_l_d, sobel_u_d;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            for (i = 0; i < 6; i = i + 1) sobel_tdata_d[i] <= 8'd0;
            sobel_v_d <= 6'd0;
            sobel_l_d <= 6'd0;
            sobel_u_d <= 6'd0;
        end
        else begin
            sobel_tdata_d[0] <= sobel_tdata;
            for (i = 0; i < 5; i = i + 1)
                sobel_tdata_d[i+1] <= sobel_tdata_d[i];
            sobel_v_d <= {sobel_v_d[4:0], tvalid_sobel};
            sobel_l_d <= {sobel_l_d[4:0], tlast_sobel};
            sobel_u_d <= {sobel_u_d[4:0], tuser_sobel};
        end
    end

    wire [7:0] sobel_tdata_d6 = sobel_tdata_d[5];
    wire       sobel_v_d6     = sobel_v_d[5];
    wire       sobel_l_d6     = sobel_l_d[5];
    wire       sobel_u_d6     = sobel_u_d[5];

    // =========================================================================
    // 7. 多路模式选择输出
    // =========================================================================
    reg [23:0] mux_tdata;
    reg        mux_tlast;
    reg        mux_tuser;
    reg        mux_tvalid;

    always @(*) begin
        case (display_mode)
            3'b000: begin // 模式 0: 彩色原图 (伽马校正后, 22 拍对齐)
                mux_tdata  = nr_rgb;
                mux_tlast  = sobel_l_d6;
                mux_tuser  = sobel_u_d6;
                mux_tvalid = sobel_v_d6;
            end
            3'b001: begin // 模式 1: 灰度图 (伽马域取灰, 22 拍对齐)
                mux_tdata  = {gray_gam, gray_gam, gray_gam};
                mux_tlast  = sobel_l_d6;
                mux_tuser  = sobel_u_d6;
                mux_tvalid = sobel_v_d6;
            end
            3'b010: begin // 模式 2: 直方图均衡 (显示域 HE + RGB 保色缩放, 22 拍对齐)
                mux_tdata  = he_rgb_d[9];
                mux_tlast  = sobel_l_d6;
                mux_tuser  = sobel_u_d6;
                mux_tvalid = sobel_v_d6;
            end
            3'b011: begin // 模式 3: Sobel 边缘检测图
                mux_tdata  = {sobel_tdata_d6, sobel_tdata_d6, sobel_tdata_d6};
                mux_tlast  = sobel_l_d6;
                mux_tuser  = sobel_u_d6;
                mux_tvalid = sobel_v_d6;
            end
            3'b100: begin // 模式 4: 卡通化风格化 (自带控制信号)
                mux_tdata  = cartoon_tdata;
                mux_tlast  = cartoon_tlast;
                mux_tuser  = cartoon_tuser;
                mux_tvalid = cartoon_tvalid;
            end
            default: begin // 兜底: 彩色原图 (伽马校正后)
                mux_tdata  = nr_rgb;
                mux_tlast  = sobel_l_d6;
                mux_tuser  = sobel_u_d6;
                mux_tvalid = sobel_v_d6;
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

    // =========================================================================
    // [以太网改造 第3步] CNN 取数口
    //   data 取 raw_rgb_d[21]（伽马后原图，22 拍对齐那一级，不随显示模式变）
    //   控制信号取 mux_*（与 raw_rgb_d[21] 严格同拍）
    //   只是把已有寄存器引出来，不新增逻辑
    // =========================================================================
    assign O_raw_tdata  = raw_rgb_d[21];
    assign O_raw_tvalid = mux_tvalid;
    assign O_raw_tuser  = mux_tuser;
    assign O_raw_tlast  = mux_tlast;

endmodule
