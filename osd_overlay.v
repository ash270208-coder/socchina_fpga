`timescale 1ns / 1ps
//=============================================================
// osd_overlay.v
// 插入在 vpp_top 输出之后、hdmi_tx 之前的一级 OSD 叠加模块。
//
// 功能：
//   1. 画面左上角叠加"安路"官方 Logo（复用 anlogic_logo_rom 位图 ROM）
//   2. Logo 正下方叠加"安路"汉字标识：16x16 点阵放大 1.5 倍为 24x24，
//      字模与渲染方式参考 lab_hd_3_osd 参考工程 hdmi_mixer.v
//   3. 画面左下角叠加当前图像处理模式文字：MODE: RGB / GRAY / HIST / SOBEL
//   4. 贴屏幕左侧叠加曝光模式提示："自动曝光" / "手动曝光"
//      （16x16 点阵放大 1.5 倍为 24x24，与"安路"同色同为 FFF200）
//      - 上电（屏幕亮起）默认自动曝光，先显示 3 s；
//      - 之后每次按键 4 在 自动/手动 之间切换时，按新状态再显示 3 s；
//      - 3 s 用"帧数"计时（AE_SHOW_FRAMES 帧 ≈ 3 s @60 fps），不占 24 位计数器，
//        且只在真正有视频帧时才递减，屏幕一帧都没有时不会提前到期。
//
// 设计约束：
//   - 不改动 vpp_top 及任何既有模块的时序；本模块为新增，仅引入 2 级
//     流水延迟，且 O_tvalid/O_tdata 同时被延迟，互相保持对齐。
//   - 当前处理模式通过"镜像" vpp_top 的按键消抖/模式计数逻辑得到：
//     两者使用同一时钟、同一按键、同一复位，且消抖语义完全一致，
//     osd_mode 与 vpp 内部 display_mode 保持同步，无需改动 vpp。
//
// 端口沿用 vpp 输出的 AXI4-Stream 风格（tuser/tlast/tvalid/tdata）。
//=============================================================
module osd_overlay #(
    parameter IMG_WIDTH   = 1024,   // 图像宽
    parameter IMG_HEIGHT  = 600,    // 图像高
    parameter LOGO_X      = 8,      // Logo 框左上角 X
    parameter LOGO_Y      = 8,      // Logo 框左上角 Y
    parameter LOGO_W      = 160,    // Logo 框宽（与 logo ROM 寻址一致）
    parameter LOGO_H      = 160,    // Logo 框高
    parameter TXT_X       = 16,     // 模式文字条左上角 X
    parameter TXT_Y       = 552,    // 模式文字条左上角 Y
    parameter TXT_H       = 30,     // 模式文字条高度（32x40 字模缩小 0.75 后为 24x30）
    parameter TXT_PITCH   = 34,     // 字符步进（32 像素字宽 + 2 像素间隔）
    parameter TXT_CHARS   = 11,     // 最大字符数（MODE: SOBEL 为 11 个）
    parameter CN_X        = 64,     // "安路"文字区左上角 X（Logo 下方水平居中）
    parameter CN_Y        = 172,    // "安路"文字区左上角 Y（Logo 底边 168 + 4 间距）
    parameter CN_W        = 48,     // "安路"文字区宽（2 字 × 24px）
    parameter CN_H        = 24,     // "安路"文字区高（16x16 字模放大 1.5 倍）

    // ---- 曝光模式提示（"自动曝光" / "手动曝光"）----
    //   位置：贴屏幕左侧。X 与 Logo/DELAY 左端一致（8），排在 FPS 与分辨率行之后。
    parameter AE_X           = 8,    // 提示框左上角 X
    parameter AE_Y           = 288,  // 提示框左上角 Y
    parameter AE_PITCH       = 26,   // 字符步进（24 px 字宽 + 2 px 间隔，与"安路"同尺寸）
    parameter AE_H           = 24,   // 提示框高（16x16 字模放大 1.5 倍）
    parameter AE_SHOW_FRAMES = 180   // 提示保持帧数（180 帧 ≈ 3.0 s @60 fps）
)(
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire [2:0]  I_mode,       // vpp_top 已消抖的当前显示模式
    input  wire        I_ae_manual,  // 曝光模式 0=自动(默认) 1=手动；必须已同步到 I_clk 域
    input  wire        I_ae_ready,   // 摄像头/AE 首次配置完成（粘滞置 1）；见 1b 节说明

    // 来自 vpp_top 的视频流（AXI4-Stream 风格）
    input  wire        I_tuser,      // 帧起始（与首像素对齐）
    input  wire        I_tlast,      // 行结束
    input  wire        I_tvalid,     // 数据有效
    input  wire [23:0] I_tdata,      // 24 位像素

    // 叠加后输出，送往 hdmi_tx
    output reg         O_tuser,
    output reg         O_tlast,
    output reg         O_tvalid,
    output wire [23:0] O_tdata
);

    // 文字条宽度：紧凑排版后最宽 SOBEL = 第10字符(g9)起始238 + 字宽24 = 262
    // Keep the text path synthesizable at the 75 MHz pixel clock.  The
    // original 262-pixel bar is retained for the 1280-wide production image.
    localparam TXT_W = 262;
    localparam [23:0] COLOR_TEXT = 24'hFFFFFF;       // 文字白色
    localparam [23:0] COLOR_BAR  = 24'h202030;       // 文字底条深色
    localparam CN_OFFSET  = 2;                       // 字形在 24px 框内垂直下沉量（参考工程 CN_Y_OFFSET）
    localparam [23:0] COLOR_CN = 24'hFFF200;         // "安路"文字颜色（参考工程动态 OSD 文字色）
    // 保持帧数计数器取 10 位：AE_SHOW_FRAMES 最大可到 1023 帧（≈17 s @60 fps），
    // 不会像 8 位那样在 255 处静默截断。
    localparam [9:0]  AE_CNT_INIT = AE_SHOW_FRAMES;        // 复位值（尚未经历帧起始）
    localparam [9:0]  AE_CNT_RELOAD = AE_SHOW_FRAMES - 1;  // 切换当帧就已经在显示了，故少 1
    // 曝光提示框宽度：4 个字符 × 24 px + 3 个 2 px 间隔 = 102 px
    localparam [6:0]  AE_REG_W = AE_PITCH * 4 - (AE_PITCH - 24);

    // Keep one mode state for the whole video path.  The VPP mux exports its
    // debounced mode; latch it only at a frame start so a caption cannot
    // change half way through a frame.
    reg [2:0] osd_mode;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n)
            osd_mode <= 3'd0;
        else if (I_tvalid && I_tuser)
            osd_mode <= (I_mode <= 3'd4) ? I_mode : 3'd0;
    end

    //----------------------------------------------------------------------
    // 1b. 曝光模式提示的"显示 3 秒"计时器（帧计数，HDMI 像素域）
    //      · 复位后立刻可见（屏幕亮起即显示，默认自动曝光）；
    //      · ae_manual_f 在帧起始锁存，模式一旦变化就重新计时，
    //        这样提示内容与本次按键后的状态一致，且不会在一帧中间改写；
    //      · ae_cnt 只在真正来帧时递减，所以"上电后摄像头还没出图"不会
    //        白耗掉这 3 秒；
    //      · I_ae_ready 上升沿（摄像头/AE 首次配置完成 = 画面真的出来了）也
    //        重新计时一次：显示器从无信号到锁上 TMDS 通常要 0.5~2 s，
    //        这样保证"画面出现时"还能看满 3 s，而不是只剩尾巴。
    //      · 可见帧数正好 AE_SHOW_FRAMES 帧：计数从 AE_SHOW_FRAMES 递减到 0 的
    //        那一帧仍可见，下一帧才清 ae_show。
    //        切换/就绪当帧本身已经算 1 帧（它已经在显示新内容了），所以重装值是
    //        AE_SHOW_FRAMES-1，而复位值用 AE_SHOW_FRAMES（复位后还没经历帧起始）。
    //----------------------------------------------------------------------
    reg        ae_manual_f;   // 当前帧的曝光模式：0=自动 1=手动
    reg        ae_ready_f;    // 上一帧看到的"配置完成"标志（用于取上升沿）
    reg        ae_show;       // 1 = 正在显示提示
    reg [9:0]  ae_cnt;        // 剩余显示帧数

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            ae_manual_f <= 1'b0;          // 上电默认自动曝光
            ae_ready_f  <= 1'b0;
            ae_show     <= 1'b1;
            ae_cnt      <= AE_CNT_INIT;
        end
        else if (I_tvalid && I_tuser) begin
            ae_manual_f <= I_ae_manual;
            ae_ready_f  <= I_ae_ready;
            if ((I_ae_manual != ae_manual_f) || (I_ae_ready && !ae_ready_f)) begin
                // 模式变化 / 画面首次就绪 -> 按当前状态重新显示 AE_SHOW_FRAMES 帧
                ae_show <= 1'b1;
                ae_cnt  <= AE_CNT_RELOAD;
            end
            else if (ae_show) begin
                if (ae_cnt == 10'd0)
                    ae_show <= 1'b0;
                else
                    ae_cnt <= ae_cnt - 10'd1;
            end
        end
    end

    //----------------------------------------------------------------------
    // 1c. 汉字点阵共用的两个纯组合函数（放在使用它们的预译码之前）
    //----------------------------------------------------------------------
    // 16x16 汉字点阵放大到 24x24 的列/行查表：
    // 由 (cn_local*16)/24 化简得 floor(2*cn_local/3)，输入仅 0..23，
    // 直接 case 查表，替代组合除法 cn_scale_x/24。
    // "安路"与曝光提示共用这张表（同为 16x16 → 24x24）。
    function [3:0] F_cn_scale;
        input [4:0] n;
        begin
            case (n)
                5'd 0: F_cn_scale = 4'd0;
                5'd 1: F_cn_scale = 4'd0;
                5'd 2: F_cn_scale = 4'd1;
                5'd 3: F_cn_scale = 4'd2;
                5'd 4: F_cn_scale = 4'd2;
                5'd 5: F_cn_scale = 4'd3;
                5'd 6: F_cn_scale = 4'd4;
                5'd 7: F_cn_scale = 4'd4;
                5'd 8: F_cn_scale = 4'd5;
                5'd 9: F_cn_scale = 4'd6;
                5'd10: F_cn_scale = 4'd6;
                5'd11: F_cn_scale = 4'd7;
                5'd12: F_cn_scale = 4'd8;
                5'd13: F_cn_scale = 4'd8;
                5'd14: F_cn_scale = 4'd9;
                5'd15: F_cn_scale = 4'd10;
                5'd16: F_cn_scale = 4'd10;
                5'd17: F_cn_scale = 4'd11;
                5'd18: F_cn_scale = 4'd12;
                5'd19: F_cn_scale = 4'd12;
                5'd20: F_cn_scale = 4'd13;
                5'd21: F_cn_scale = 4'd14;
                5'd22: F_cn_scale = 4'd14;
                5'd23: F_cn_scale = 4'd15;
                default: F_cn_scale = 4'd0;
            endcase
        end
    endfunction

    // 曝光模式提示的字形编号：0=自 1=动 2=曝 3=光 4=手
    //   自动曝光 = 自 动 曝 光；手动曝光 = 手 动 曝 光（只有首字不同）
    function [2:0] F_ae_glyph;
        input       I_manual;
        input [1:0] I_char;
        begin
            case (I_char)
                2'd0:    F_ae_glyph = I_manual ? 3'd4 : 3'd0;
                2'd1:    F_ae_glyph = 3'd1;
                2'd2:    F_ae_glyph = 3'd2;
                default: F_ae_glyph = 3'd3;
            endcase
        end
    endfunction

    //----------------------------------------------------------------------
    // 2. 像素坐标计数（输入侧）
    //----------------------------------------------------------------------
    reg [11:0] S_x;
    reg [11:0] S_y;

    // Pre-decode coordinate-dependent OSD inputs before the existing r1
    // register. This keeps the external two-cycle latency unchanged while
    // shortening the ROM-to-output combinational path.
    wire [11:0] x_in_aligned = (I_tvalid && I_tuser) ? 12'd0 : S_x;
    wire [11:0] y_in_aligned = (I_tvalid && I_tuser) ? 12'd0 : S_y;
    wire [2:0] mode_in_aligned = (I_tvalid && I_tuser) ?
                                 ((I_mode <= 3'd4) ? I_mode : 3'd0) : osd_mode;
    wire logo_region_in = I_tvalid &&
        (x_in_aligned >= LOGO_X) && (x_in_aligned < LOGO_X + LOGO_W) &&
        (y_in_aligned >= LOGO_Y) && (y_in_aligned < LOGO_Y + LOGO_H);
    wire [11:0] logo_lx_in = x_in_aligned - LOGO_X;
    wire [11:0] logo_ly_in = y_in_aligned - LOGO_Y;
    wire [14:0] logo_addr_in = ({3'd0, logo_ly_in} << 7) +
                               ({3'd0, logo_ly_in} << 5) +
                               {3'd0, logo_lx_in};

    wire text_region_in = I_tvalid &&
        (x_in_aligned >= TXT_X) && (x_in_aligned < TXT_X + TXT_W) &&
        (y_in_aligned >= TXT_Y) && (y_in_aligned < TXT_Y + TXT_H);
    wire [8:0] txt_local_x_in = x_in_aligned - TXT_X;
    wire [5:0] txt_local_y_in = y_in_aligned - TXT_Y;

    wire cn_region_in = I_tvalid &&
        (x_in_aligned >= CN_X) && (x_in_aligned < CN_X + CN_W) &&
        (y_in_aligned >= CN_Y) && (y_in_aligned < CN_Y + CN_H);
    wire cn_char_in = x_in_aligned >= CN_X + 24;
    wire [4:0] cn_local_x_in = cn_char_in ?
                               x_in_aligned - CN_X - 12'd24 : x_in_aligned - CN_X;
    wire [4:0] cn_local_y_in = y_in_aligned - CN_Y;

    // ---- 曝光模式提示（贴屏幕左侧，24 px 字模）----
    // 字符序号、字内列、放大 1.5 倍后的字模行列都在第一级寄存器之前算好，
    // 第二级只承担"字形 ROM 查表 + 取位"，与"安路"汉字层的结构一致。
    localparam [6:0] AE_P1 = AE_PITCH;         // 第 2 字起始列
    localparam [6:0] AE_P2 = AE_PITCH * 2;     // 第 3 字起始列
    localparam [6:0] AE_P3 = AE_PITCH * 3;     // 第 4 字起始列

    wire ae_region_in = I_tvalid && ae_show &&
        (x_in_aligned >= AE_X) && (x_in_aligned < AE_X + AE_REG_W) &&
        (y_in_aligned >= AE_Y) && (y_in_aligned < AE_Y + AE_H);
    wire [6:0] ae_local_x_in = x_in_aligned - AE_X;      // 0..101
    wire [4:0] ae_local_y_in = y_in_aligned - AE_Y;      // 0..23
    wire [1:0] ae_char_in = (ae_local_x_in < AE_P1) ? 2'd0 :
                            (ae_local_x_in < AE_P2) ? 2'd1 :
                            (ae_local_x_in < AE_P3) ? 2'd2 : 2'd3;
    wire [6:0] ae_cell_base_in = (ae_char_in == 2'd1) ? AE_P1 :
                                 (ae_char_in == 2'd2) ? AE_P2 :
                                 (ae_char_in == 2'd3) ? AE_P3 : 7'd0;
    wire [5:0] ae_cell_x_in = ae_local_x_in - ae_cell_base_in;   // 字内列 0..25
    wire ae_lx_ok_in = (ae_cell_x_in < 6'd24);           // 24/25 是字间 2 px 间隔
    wire [3:0] ae_col_in = F_cn_scale(ae_cell_x_in[4:0]);
    wire [3:0] ae_row_in = F_cn_scale(ae_local_y_in);
    wire [2:0] ae_glyph_in = F_ae_glyph(ae_manual_f, ae_char_in);

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            S_x <= 12'd0;
            S_y <= 12'd0;
        end
        // 坐标只由有效像素计数产生。上游各算法的 tuser/tlast 可能因
        // 流水线空泡而保持若干拍，直接使用它们会让 OSD 在不同模式跳变。
        // 每行固定 IMG_WIDTH 个有效像素，计满后换行并在整帧处回到 0。
        else if (I_tvalid) begin
            if (I_tuser) begin
                S_x <= 12'd1;
                S_y <= 12'd0;
            end
            else if (S_x == IMG_WIDTH - 1) begin
                S_x <= 12'd0;
                if (S_y == IMG_HEIGHT - 1)
                    S_y <= 12'd0;
                else
                    S_y <= S_y + 12'd1;
            end
            else begin
                S_x <= S_x + 12'd1;
            end
        end
    end

    //----------------------------------------------------------------------
    // 3. 一级流水：锁存像素数据及各图层的预译码结果。
    //    区域比较、局部坐标和 Logo 地址在该寄存器前计算，使第二级
    //    只承担字模/Logo 查表和最终命中判定；总输出延迟仍为两拍。
    //----------------------------------------------------------------------
    reg        valid_r1;
    reg        last_r1;
    reg        user_r1;
    reg [23:0] data_r1;
    reg        logo_region_r1;
    reg [14:0] logo_addr_r1;
    reg        text_region_r1;
    reg [8:0]  txt_local_x_r1;
    reg [5:0]  txt_local_y_r1;
    reg [2:0]  mode_r1;
    reg        cn_region_r1;
    reg [4:0]  cn_local_x_r1;
    reg [4:0]  cn_local_y_r1;
    reg        cn_char_r1;
    reg        ae_region_r1;      // 曝光提示层
    reg        ae_lx_ok_r1;
    reg [2:0]  ae_glyph_r1;
    reg [3:0]  ae_col_r1;
    reg [3:0]  ae_row_r1;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            valid_r1 <= 1'b0;
            last_r1  <= 1'b0;
            user_r1  <= 1'b0;
            data_r1  <= 24'd0;
            logo_region_r1 <= 1'b0;
            logo_addr_r1   <= 15'd0;
            text_region_r1 <= 1'b0;
            txt_local_x_r1 <= 9'd0;
            txt_local_y_r1 <= 6'd0;
            mode_r1        <= 3'd0;
            cn_region_r1   <= 1'b0;
            cn_local_x_r1  <= 5'd0;
            cn_local_y_r1  <= 5'd0;
            cn_char_r1     <= 1'b0;
            ae_region_r1   <= 1'b0;
            ae_lx_ok_r1    <= 1'b0;
            ae_glyph_r1    <= 3'd0;
            ae_col_r1      <= 4'd0;
            ae_row_r1      <= 4'd0;
        end
        else begin
            valid_r1 <= I_tvalid;
            last_r1  <= I_tlast;
            user_r1  <= I_tuser;
            data_r1  <= I_tdata;
            logo_region_r1 <= logo_region_in;
            logo_addr_r1   <= logo_addr_in;
            text_region_r1 <= text_region_in;
            txt_local_x_r1 <= txt_local_x_in;
            txt_local_y_r1 <= txt_local_y_in;
            mode_r1        <= mode_in_aligned;
            cn_region_r1   <= cn_region_in;
            cn_local_x_r1  <= cn_local_x_in;
            cn_local_y_r1  <= cn_local_y_in;
            cn_char_r1     <= cn_char_in;
            ae_region_r1   <= ae_region_in;
            ae_lx_ok_r1    <= ae_lx_ok_in;
            ae_glyph_r1    <= ae_glyph_in;
            ae_col_r1      <= ae_col_in;
            ae_row_r1      <= ae_row_in;
        end
    end

    //----------------------------------------------------------------------
    // 4. 第二级组合查表：由第一级锁存的图层坐标读取字模/Logo
    //----------------------------------------------------------------------
    // Logo ROM 接口
    wire [24:0] logo_pixel;

    // 字符库接口
    wire [31:0] char_row_bits;
    reg  [7:0]  char_sel;
    reg  [5:0]  char_row;
    reg  [8:0]  txt_local_x;
    reg  [5:0]  txt_local_y;
    reg  [3:0]  txt_glyph;     // 字符序号
    reg  [5:0]  txt_lx;        // 字符内列(0..23)
    reg  [5:0]  src_col;       // 字模源列（显示列经 4/3 缩放映射）
    reg  [5:0]  src_row;       // 字模源行（显示行经 4/3 缩放映射）
    wire        text_pixel_on;

    // "安路"汉字区（Logo 正下方）内部信号
    reg  [4:0]  cn_local_x;    // 文字区内 x(0..CN_W-1)
    reg  [4:0]  cn_local_y;    // 文字区内 y(0..CN_H-1)
    reg         cn_char;       // 0:安 1:路
    reg  [3:0]  cn_col;        // 字形内列(0..15)
    reg  [3:0]  cn_row;        // 字形内行(0..15)
    reg  [15:0] cn_row_bits;   // 该行 16 位点阵
    reg         cn_on;         // 笔画点亮

    wire text_region_now = valid_r1 &&
                           text_region_r1;
    wire cn_region_now = valid_r1 &&
                         cn_region_r1;
    wire logo_opaque_now = valid_r1 && logo_region_r1 && logo_pixel[24];

    // 曝光模式提示层（贴屏幕左侧）：字模行 + 取位
    wire ae_region_now = valid_r1 && ae_region_r1 && ae_lx_ok_r1;
    wire [15:0] ae_row_bits = ae_region_now ? F_ae16_row(ae_glyph_r1, ae_row_r1)
                                            : 16'h0000;
    wire ae_on = ae_row_bits[15 - ae_col_r1];

    reg [23:0] data_r2;
    reg [23:0] logo_color_r2;
    reg        logo_hit_r2;
    reg        text_hit_r2;
    reg        text_pixel_r2;
    reg        cn_hit_r2;

    // 模式 → 字符序列映射
    function [7:0] F_mode_glyph;
        input [2:0] I_mode;
        input [3:0] I_g;
        begin
            case (I_mode)
                2'd0: begin // MODE: RGB
                    case (I_g)
                        4'd0: F_mode_glyph = "M";
                        4'd1: F_mode_glyph = "O";
                        4'd2: F_mode_glyph = "D";
                        4'd3: F_mode_glyph = "E";
                        4'd4: F_mode_glyph = ":";
                        4'd5: F_mode_glyph = "R";
                        4'd6: F_mode_glyph = "G";
                        4'd7: F_mode_glyph = "B";
                        default: F_mode_glyph = " ";
                    endcase
                end
                2'd1: begin // MODE: GRAY
                    case (I_g)
                        4'd0: F_mode_glyph = "M";
                        4'd1: F_mode_glyph = "O";
                        4'd2: F_mode_glyph = "D";
                        4'd3: F_mode_glyph = "E";
                        4'd4: F_mode_glyph = ":";
                        4'd5: F_mode_glyph = "G";
                        4'd6: F_mode_glyph = "R";
                        4'd7: F_mode_glyph = "A";
                        4'd8: F_mode_glyph = "Y";
                        default: F_mode_glyph = " ";
                    endcase
                end
                2'd2: begin // MODE: HIST
                    case (I_g)
                        4'd0: F_mode_glyph = "M";
                        4'd1: F_mode_glyph = "O";
                        4'd2: F_mode_glyph = "D";
                        4'd3: F_mode_glyph = "E";
                        4'd4: F_mode_glyph = ":";
                        4'd5: F_mode_glyph = "H";
                        4'd6: F_mode_glyph = "I";
                        4'd7: F_mode_glyph = "S";
                        4'd8: F_mode_glyph = "T";
                        default: F_mode_glyph = " ";
                    endcase
                end
                3'd3: begin // MODE: SOBEL
                    case (I_g)
                        4'd0: F_mode_glyph = "M";
                        4'd1: F_mode_glyph = "O";
                        4'd2: F_mode_glyph = "D";
                        4'd3: F_mode_glyph = "E";
                        4'd4: F_mode_glyph = ":";
                        4'd5: F_mode_glyph = "S";
                        4'd6: F_mode_glyph = "O";
                        4'd7: F_mode_glyph = "B";
                        4'd8: F_mode_glyph = "E";
                        4'd9: F_mode_glyph = "L";
                        default: F_mode_glyph = " ";
                    endcase
                end
                3'd4: begin // MODE: CART
                    case (I_g)
                        4'd0: F_mode_glyph = "M";
                        4'd1: F_mode_glyph = "O";
                        4'd2: F_mode_glyph = "D";
                        4'd3: F_mode_glyph = "E";
                        4'd4: F_mode_glyph = ":";
                        4'd5: F_mode_glyph = "C";
                        4'd6: F_mode_glyph = "A";
                        4'd7: F_mode_glyph = "R";
                        4'd8: F_mode_glyph = "T";
                        default: F_mode_glyph = " ";
                    endcase
                end
                default: begin // 非法状态回退到 MODE: RGB
                    case (I_g)
                        4'd0: F_mode_glyph = "M";
                        4'd1: F_mode_glyph = "O";
                        4'd2: F_mode_glyph = "D";
                        4'd3: F_mode_glyph = "E";
                        4'd4: F_mode_glyph = ":";
                        4'd5: F_mode_glyph = "R";
                        4'd6: F_mode_glyph = "G";
                        4'd7: F_mode_glyph = "B";
                        default: F_mode_glyph = " ";
                    endcase
                end
            endcase
        end
    endfunction

    // 16x16 汉字点阵："安"(I_char=0)、"路"(I_char=1)
    // 数据取自参考工程 lab_hd_3_osd 的 hdmi_mixer.v F_cn16_row，
    // bit15 对应最左列，行 11..15 为空。
    function [15:0] F_cn16_row;
        input         I_char;
        input [3:0]   I_row;
        begin
            if (!I_char) begin
                case (I_row)
                    4'd 0: F_cn16_row = 16'h0200;
                    4'd 1: F_cn16_row = 16'h7ff0;
                    4'd 2: F_cn16_row = 16'h4410;
                    4'd 3: F_cn16_row = 16'h0400;
                    4'd 4: F_cn16_row = 16'h7ff0;
                    4'd 5: F_cn16_row = 16'h0840;
                    4'd 6: F_cn16_row = 16'h1040;
                    4'd 7: F_cn16_row = 16'h1c80;
                    4'd 8: F_cn16_row = 16'h0300;
                    4'd 9: F_cn16_row = 16'h0cc0;
                    4'd10: F_cn16_row = 16'h7020;
                    default: F_cn16_row = 16'h0000;
                endcase
            end
            else begin
                case (I_row)
                    4'd 0: F_cn16_row = 16'h79e0;
                    4'd 1: F_cn16_row = 16'h4a20;
                    4'd 2: F_cn16_row = 16'h4d40;
                    4'd 3: F_cn16_row = 16'h7880;
                    4'd 4: F_cn16_row = 16'h1140;
                    4'd 5: F_cn16_row = 16'h1630;
                    4'd 6: F_cn16_row = 16'h5be0;
                    4'd 7: F_cn16_row = 16'h5220;
                    4'd 8: F_cn16_row = 16'h5220;
                    4'd 9: F_cn16_row = 16'h5be0;
                    4'd10: F_cn16_row = 16'h6220;
                    default: F_cn16_row = 16'h0000;
                endcase
            end
        end
    endfunction

    // 曝光模式提示的 16x16 字模："自"(0) "动"(1) "曝"(2) "光"(3) "手"(4)。
    // 字模由 SimSun 16 px 渲染后逐行核对（笔画完整、底边对齐第 15 行），
    // 与"安路"同一点阵风格（1 px 笔画）。bit15 对应最左列。
    function [15:0] F_ae16_row;
        input [2:0] I_glyph;
        input [3:0] I_row;
        begin
            case (I_glyph)
                3'd0: case (I_row)      // 自
                    4'd 0: F_ae16_row = 16'h0000;
                    4'd 1: F_ae16_row = 16'h0100;
                    4'd 2: F_ae16_row = 16'h0200;
                    4'd 3: F_ae16_row = 16'h0400;
                    4'd 4: F_ae16_row = 16'h1FF0;
                    4'd 5: F_ae16_row = 16'h1010;
                    4'd 6: F_ae16_row = 16'h1010;
                    4'd 7: F_ae16_row = 16'h1010;
                    4'd 8: F_ae16_row = 16'h1FF0;
                    4'd 9: F_ae16_row = 16'h1010;
                    4'd10: F_ae16_row = 16'h1010;
                    4'd11: F_ae16_row = 16'h1FF0;
                    4'd12: F_ae16_row = 16'h1010;
                    4'd13: F_ae16_row = 16'h1010;
                    4'd14: F_ae16_row = 16'h1010;
                    4'd15: F_ae16_row = 16'h1FF0;
                    default: F_ae16_row = 16'h0000;
                endcase
                3'd1: case (I_row)      // 动
                    4'd 0: F_ae16_row = 16'h0040;
                    4'd 1: F_ae16_row = 16'h0040;
                    4'd 2: F_ae16_row = 16'h7C40;
                    4'd 3: F_ae16_row = 16'h0040;
                    4'd 4: F_ae16_row = 16'h01FC;
                    4'd 5: F_ae16_row = 16'h0044;
                    4'd 6: F_ae16_row = 16'hFE44;
                    4'd 7: F_ae16_row = 16'h2044;
                    4'd 8: F_ae16_row = 16'h2044;
                    4'd 9: F_ae16_row = 16'h2084;
                    4'd10: F_ae16_row = 16'h4884;
                    4'd11: F_ae16_row = 16'h4484;
                    4'd12: F_ae16_row = 16'hFD04;
                    4'd13: F_ae16_row = 16'h4504;
                    4'd14: F_ae16_row = 16'h0228;
                    4'd15: F_ae16_row = 16'h0410;
                    default: F_ae16_row = 16'h0000;
                endcase
                3'd2: case (I_row)      // 曝
                    4'd 0: F_ae16_row = 16'h03F8;
                    4'd 1: F_ae16_row = 16'h0208;
                    4'd 2: F_ae16_row = 16'hF3F8;
                    4'd 3: F_ae16_row = 16'h9208;
                    4'd 4: F_ae16_row = 16'h93F8;
                    4'd 5: F_ae16_row = 16'h9110;
                    4'd 6: F_ae16_row = 16'h97FC;
                    4'd 7: F_ae16_row = 16'hF110;
                    4'd 8: F_ae16_row = 16'h9FFE;
                    4'd 9: F_ae16_row = 16'h9110;
                    4'd10: F_ae16_row = 16'h9248;
                    4'd11: F_ae16_row = 16'h9554;
                    4'd12: F_ae16_row = 16'hF0E0;
                    4'd13: F_ae16_row = 16'h9150;
                    4'd14: F_ae16_row = 16'h0248;
                    4'd15: F_ae16_row = 16'h00C0;
                    default: F_ae16_row = 16'h0000;
                endcase
                3'd3: case (I_row)      // 光
                    4'd 0: F_ae16_row = 16'h0100;
                    4'd 1: F_ae16_row = 16'h2108;
                    4'd 2: F_ae16_row = 16'h1108;
                    4'd 3: F_ae16_row = 16'h0910;
                    4'd 4: F_ae16_row = 16'h0920;
                    4'd 5: F_ae16_row = 16'h0100;
                    4'd 6: F_ae16_row = 16'hFFFE;
                    4'd 7: F_ae16_row = 16'h0440;
                    4'd 8: F_ae16_row = 16'h0440;
                    4'd 9: F_ae16_row = 16'h0440;
                    4'd10: F_ae16_row = 16'h0440;
                    4'd11: F_ae16_row = 16'h0842;
                    4'd12: F_ae16_row = 16'h0842;
                    4'd13: F_ae16_row = 16'h1042;
                    4'd14: F_ae16_row = 16'h203E;
                    4'd15: F_ae16_row = 16'hC000;
                    default: F_ae16_row = 16'h0000;
                endcase
                default: case (I_row)   // 手
                    4'd 0: F_ae16_row = 16'h0010;
                    4'd 1: F_ae16_row = 16'h00F8;
                    4'd 2: F_ae16_row = 16'h3F00;
                    4'd 3: F_ae16_row = 16'h0100;
                    4'd 4: F_ae16_row = 16'h0100;
                    4'd 5: F_ae16_row = 16'h3FF8;
                    4'd 6: F_ae16_row = 16'h0100;
                    4'd 7: F_ae16_row = 16'h0100;
                    4'd 8: F_ae16_row = 16'h0100;
                    4'd 9: F_ae16_row = 16'hFFFE;
                    4'd10: F_ae16_row = 16'h0100;
                    4'd11: F_ae16_row = 16'h0100;
                    4'd12: F_ae16_row = 16'h0100;
                    4'd13: F_ae16_row = 16'h0100;
                    4'd14: F_ae16_row = 16'h0500;
                    4'd15: F_ae16_row = 16'h0200;
                    default: F_ae16_row = 16'h0000;
                endcase
            endcase
        end
    endfunction

    // 32x40 字模缩小 0.75 倍到 24x30 的坐标映射：源坐标 = floor(显示坐标 * 4/3)。
    // 显示列 0..23 → 源列 0..30；显示行 0..29 → 源行 0..38。查表替代乘法+除法。
    function [5:0] F_dn43;
        input [5:0] n;
        begin
            case (n)
                6'd 0: F_dn43 = 6'd0;
                6'd 1: F_dn43 = 6'd1;
                6'd 2: F_dn43 = 6'd2;
                6'd 3: F_dn43 = 6'd4;
                6'd 4: F_dn43 = 6'd5;
                6'd 5: F_dn43 = 6'd6;
                6'd 6: F_dn43 = 6'd8;
                6'd 7: F_dn43 = 6'd9;
                6'd 8: F_dn43 = 6'd10;
                6'd 9: F_dn43 = 6'd12;
                6'd10: F_dn43 = 6'd13;
                6'd11: F_dn43 = 6'd14;
                6'd12: F_dn43 = 6'd16;
                6'd13: F_dn43 = 6'd17;
                6'd14: F_dn43 = 6'd18;
                6'd15: F_dn43 = 6'd20;
                6'd16: F_dn43 = 6'd21;
                6'd17: F_dn43 = 6'd22;
                6'd18: F_dn43 = 6'd24;
                6'd19: F_dn43 = 6'd25;
                6'd20: F_dn43 = 6'd26;
                6'd21: F_dn43 = 6'd28;
                6'd22: F_dn43 = 6'd29;
                6'd23: F_dn43 = 6'd30;
                6'd24: F_dn43 = 6'd32;
                6'd25: F_dn43 = 6'd33;
                6'd26: F_dn43 = 6'd34;
                6'd27: F_dn43 = 6'd36;
                6'd28: F_dn43 = 6'd37;
                6'd29: F_dn43 = 6'd38;
                default: F_dn43 = 6'd38;
            endcase
        end
    endfunction

    // 紧凑排版下每个字符在文字条内的起始 x 偏移。
    // 字符宽 24、步进 26；第5个字符(模式名首字母)紧跟冒号后 6px 处，替代原来一个完整 pitch 的空格。
    // 0/26/52/78/104 = M O D E :；134 = 模式名首字母；其后每 26 一个。
    function [8:0] F_txt_start;
        input [3:0] g;
        begin
            case (g)
                4'd0: F_txt_start = 9'd0;
                4'd1: F_txt_start = 9'd26;
                4'd2: F_txt_start = 9'd52;
                4'd3: F_txt_start = 9'd78;
                4'd4: F_txt_start = 9'd104;
                4'd5: F_txt_start = 9'd134;
                4'd6: F_txt_start = 9'd160;
                4'd7: F_txt_start = 9'd186;
                4'd8: F_txt_start = 9'd212;
                4'd9: F_txt_start = 9'd238;
                default: F_txt_start = 9'd264;
            endcase
        end
    endfunction

    // Keep the font-ROM inputs in a separate combinational cone from its
    // output. This avoids a false feedback loop through char_row_bits in RTL
    // simulation and lets the font lookup run in parallel with layer priority.
    always @(*) begin
        char_sel      = 8'h20;
        char_row      = 6'd0;
        txt_local_x   = 9'd0;
        txt_local_y   = 6'd0;
        txt_glyph     = 4'd0;
        txt_lx        = 6'd0;
        src_col       = 6'd0;
        src_row       = 6'd0;

        if (text_region_r1) begin
            txt_local_x = txt_local_x_r1;
            txt_local_y = txt_local_y_r1;
            txt_glyph = (txt_local_x < 9'd26)  ? 4'd0 :
                        (txt_local_x < 9'd52)  ? 4'd1 :
                        (txt_local_x < 9'd78)  ? 4'd2 :
                        (txt_local_x < 9'd104) ? 4'd3 :
                        (txt_local_x < 9'd134) ? 4'd4 :
                        (txt_local_x < 9'd160) ? 4'd5 :
                        (txt_local_x < 9'd186) ? 4'd6 :
                        (txt_local_x < 9'd212) ? 4'd7 :
                        (txt_local_x < 9'd238) ? 4'd8 :
                        (txt_local_x < 9'd262) ? 4'd9 : 4'd10;
            txt_lx = txt_local_x - F_txt_start(txt_glyph);
            if ((txt_glyph < 4'd10) && (txt_lx < 6'd24) && (txt_local_y < 6'd30)) begin
                char_sel = F_mode_glyph(mode_r1, txt_glyph);
                src_row = F_dn43(txt_local_y);
                src_col = F_dn43(txt_lx);
                char_row = src_row;
            end
        end
    end

    assign text_pixel_on = char_row_bits[31 - src_col];

    always @(*) begin
        cn_local_x  = 5'd0;
        cn_local_y  = 5'd0;
        cn_char     = 1'b0;
        cn_col      = 4'd0;
        cn_row      = 4'd0;
        cn_row_bits = 16'd0;
        cn_on       = 1'b0;

        if (cn_region_now) begin
            cn_local_y = cn_local_y_r1;
            cn_local_x = cn_local_x_r1;
            cn_char    = cn_char_r1;
            if (cn_local_y >= CN_OFFSET)
                cn_local_y = cn_local_y - CN_OFFSET;
            else
                cn_local_y = 5'd31;
            if ((cn_local_x < 5'd24) && (cn_local_y < 5'd24)) begin
                cn_col      = F_cn_scale(cn_local_x);
                cn_row      = F_cn_scale(cn_local_y);
                cn_row_bits = F_cn16_row(cn_char, cn_row);
                cn_on       = cn_row_bits[15 - cn_col];
            end
        end
    end

    //----------------------------------------------------------------------
    // 5. 输出级：OSD 命中则输出叠加色，否则透传视频；与 valid 对齐
    //----------------------------------------------------------------------
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_tvalid <= 1'b0;
            O_tlast  <= 1'b0;
            O_tuser  <= 1'b0;
            data_r2       <= 24'd0;
            logo_color_r2 <= 24'd0;
            logo_hit_r2   <= 1'b0;
            text_hit_r2   <= 1'b0;
            text_pixel_r2 <= 1'b0;
            cn_hit_r2     <= 1'b0;
        end
        else begin
            O_tvalid <= valid_r1;
            O_tlast  <= last_r1;
            O_tuser  <= user_r1;
            data_r2       <= data_r1;
            logo_color_r2 <= logo_pixel[23:0];
            logo_hit_r2   <= logo_opaque_now;
            text_hit_r2   <= text_region_now && !logo_opaque_now;
            text_pixel_r2 <= text_pixel_on;
            // 汉字层（"安路" + 曝光模式提示，同为 FFF200 24px 汉字）：
            // 两个字形查表是并行的独立组合锥，合并后再打一拍，
            // 所以 O_tdata 的最终多路选择仍是 4 选 1、选择信号全部来自寄存器，
            // 与加入曝光提示之前完全一致（不给 75 MHz 像素时钟加组合深度）。
            cn_hit_r2     <= (cn_region_now && cn_on &&
                              !logo_opaque_now && !text_region_now) ||
                             (ae_region_now && ae_on &&
                              !logo_opaque_now && !text_region_now);
        end
    end

    // The OSD color mux is deliberately after the stage-2 registers. The
    // expensive Logo ROM and font decoding therefore terminate at registers,
    // while the original two-cycle video latency remains unchanged.
    // 图层优先级：不透明 Logo > 模式文字/底条 > 汉字笔画（"安路" / 曝光提示）> 原视频
    assign O_tdata = logo_hit_r2 ? logo_color_r2 :
                     text_hit_r2 ? (text_pixel_r2 ? COLOR_TEXT : COLOR_BAR) :
                     cn_hit_r2   ? COLOR_CN : data_r2;

    //----------------------------------------------------------------------
    // 6. 子模块例化
    //----------------------------------------------------------------------
    anlogic_logo_rom u_anlogic_logo_rom(
        .I_addr  ( logo_addr_r1 ),
        .O_pixel ( logo_pixel )
    );

    osd_char_lib u_osd_char_lib(
        .I_char    ( char_sel       ),
        .I_row     ( char_row       ),
        .O_row_bits( char_row_bits  )
    );

endmodule
