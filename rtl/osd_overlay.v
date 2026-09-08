`timescale 1ns / 1ps
//=============================================================
// osd_overlay.v
// 插入在 vpp_top 输出之后、hdmi_tx 之前的一级 OSD 叠加模块。
//
// 功能：
//   1. 画面左上角叠加"安路"官方 Logo（复用 anlogic_logo_rom 位图 ROM）
//   2. 画面左下角叠加当前图像处理模式文字：MODE: RGB / GRAY / HIST / SOBEL
//
// 设计约束（完全满足用户要求）：
//   - 不改动 vpp_top 及任何既有模块的时序；本模块为新增，仅引入 2 级
//     流水延迟，且 O_tvalid/O_tdata 同时被延迟，互相保持对齐。
//   - 当前处理模式通过"镜像" vpp_top 的按键消抖/模式计数逻辑得到：
//     两者使用同一时钟、同一按键、同一复位，且消抖语义完全一致，
//     因此 osd_mode 与 vpp 内部 display_mode 保持同步，无需改动 vpp。
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
    parameter TXT_H       = 40,     // 模式文字条高度（32x40 字模，约为 logo 的 1/4）
    parameter TXT_PITCH   = 34,     // 字符步进（32 像素字宽 + 2 像素间隔）
    parameter TXT_CHARS   = 11      // 最大字符数（MODE: SOBEL 为 11 个）
)(
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_button,     // 按键0（与 vpp_top 同一按键，用于镜像模式）

    // 来自 vpp_top 的视频流（AXI4-Stream 风格）
    input  wire        I_tuser,      // 帧起始（与首像素对齐）
    input  wire        I_tlast,      // 行结束
    input  wire        I_tvalid,     // 数据有效
    input  wire [23:0] I_tdata,      // 24 位像素

    // 叠加后输出，送往 hdmi_tx
    output reg         O_tuser,
    output reg         O_tlast,
    output reg         O_tvalid,
    output reg  [23:0] O_tdata
);

    localparam TXT_W = TXT_CHARS * TXT_PITCH;        // 文字条宽度
    localparam [23:0] COLOR_TEXT = 24'hFFFFFF;       // 文字白色
    localparam [23:0] COLOR_BAR  = 24'h202030;       // 文字底条深色

    //----------------------------------------------------------------------
    // 1. 按键模式镜像（与 vpp_top 消抖语义完全一致，保持同步）
    //----------------------------------------------------------------------
    reg        btn_d0;
    reg        btn_d1;
    reg [19:0] btn_cnt;
    reg [1:0]  osd_mode;      // 0:RGB 1:GRAY 2:HIST 3:SOBEL

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            btn_d0   <= 1'b1;
            btn_d1   <= 1'b1;
            btn_cnt  <= 20'd0;
            osd_mode <= 2'b00;
        end
        else begin
            btn_d0 <= I_button;
            btn_d1 <= btn_d0;
            // 按键下降沿消抖（低电平按下），与 vpp_top 完全一致
            if (btn_d1 && !btn_d0) begin
                btn_cnt <= 20'd1;
            end
            else if (btn_cnt > 20'd0) begin
                if (btn_cnt == 20'd1_000_000) begin  // 约 10~20ms
                    btn_cnt <= 20'd0;
                    if (!I_button)
                        osd_mode <= osd_mode + 2'd1;
                end
                else begin
                    btn_cnt <= btn_cnt + 20'd1;
                end
            end
        end
    end

    //----------------------------------------------------------------------
    // 2. 像素坐标计数（输入侧）
    //----------------------------------------------------------------------
    reg [11:0] S_x;
    reg [11:0] S_y;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            S_x <= 12'd0;
            S_y <= 12'd0;
        end
        else if (I_tuser) begin        // 帧起始复位坐标
            S_x <= 12'd0;
            S_y <= 12'd0;
        end
        else if (I_tvalid) begin
            if (I_tlast) begin         // 行结束：x 归零，y+1
                S_x <= 12'd0;
                S_y <= S_y + 12'd1;
            end
            else begin
                S_x <= S_x + 12'd1;
            end
        end
    end

    //----------------------------------------------------------------------
    // 3. 一级流水：把数据与坐标延迟一拍对齐
    //    （同一时钟沿采样 I_tdata 与 S_x/S_y 的旧值，保证像素-坐标对应）
    //----------------------------------------------------------------------
    reg        valid_r1;
    reg        last_r1;
    reg        user_r1;
    reg [23:0] data_r1;
    reg [11:0] x_r1;
    reg [11:0] y_r1;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            valid_r1 <= 1'b0;
            last_r1  <= 1'b0;
            user_r1  <= 1'b0;
            data_r1  <= 24'd0;
            x_r1     <= 12'd0;
            y_r1     <= 12'd0;
        end
        else begin
            valid_r1 <= I_tvalid;
            last_r1  <= I_tlast;
            user_r1  <= I_tuser;
            data_r1  <= I_tdata;
            x_r1     <= S_x;          // 采样坐标旧值，即当前像素坐标
            y_r1     <= S_y;
        end
    end

    //----------------------------------------------------------------------
    // 4. 组合 OSD 判定：由 (x_r1, y_r1) 决定是否替换像素
    //----------------------------------------------------------------------
    // Logo ROM 接口
    wire [24:0] logo_pixel;
    reg  [14:0] logo_addr;
    reg  [11:0] logo_lx;
    reg  [11:0] logo_ly;

    // 字符库接口
    wire [31:0] char_row_bits;
    reg  [7:0]  char_sel;
    reg  [5:0]  char_row;
    reg  [8:0]  txt_local_x;   // 文字条内 x(0..TXT_W-1)
    reg  [5:0]  txt_local_y;   // 文字条内 y(0..TXT_H-1)
    reg  [3:0]  txt_glyph;     // 字符序号
    reg  [5:0]  txt_lx;        // 字符内列(0..33)
    reg         text_pixel_on;

    reg        osd_hit;
    reg [23:0] osd_color;

    // 模式 → 字符序列映射
    function [7:0] F_mode_glyph;
        input [1:0] I_mode;
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
                        4'd5: F_mode_glyph = " ";
                        4'd6: F_mode_glyph = "R";
                        4'd7: F_mode_glyph = "G";
                        4'd8: F_mode_glyph = "B";
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
                        4'd5: F_mode_glyph = " ";
                        4'd6: F_mode_glyph = "G";
                        4'd7: F_mode_glyph = "R";
                        4'd8: F_mode_glyph = "A";
                        4'd9: F_mode_glyph = "Y";
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
                        4'd5: F_mode_glyph = " ";
                        4'd6: F_mode_glyph = "H";
                        4'd7: F_mode_glyph = "I";
                        4'd8: F_mode_glyph = "S";
                        4'd9: F_mode_glyph = "T";
                        default: F_mode_glyph = " ";
                    endcase
                end
                default: begin // MODE: SOBEL
                    case (I_g)
                        4'd0: F_mode_glyph = "M";
                        4'd1: F_mode_glyph = "O";
                        4'd2: F_mode_glyph = "D";
                        4'd3: F_mode_glyph = "E";
                        4'd4: F_mode_glyph = ":";
                        4'd5: F_mode_glyph = " ";
                        4'd6: F_mode_glyph = "S";
                        4'd7: F_mode_glyph = "O";
                        4'd8: F_mode_glyph = "B";
                        4'd9: F_mode_glyph = "E";
                        4'd10: F_mode_glyph = "L";
                        default: F_mode_glyph = " ";
                    endcase
                end
            endcase
        end
    endfunction

    always @(*) begin
        // 默认透传
        osd_hit        = 1'b0;
        osd_color      = 24'd0;
        logo_addr      = 15'd0;
        logo_lx        = 12'd0;
        logo_ly        = 12'd0;
        char_sel       = 8'h20;
        char_row       = 6'd0;
        txt_local_x    = 8'd0;
        txt_local_y    = 5'd0;
        txt_glyph      = 4'd0;
        txt_lx         = 5'd0;
        text_pixel_on  = 1'b0;

        if (valid_r1) begin
            // ---- (a) Logo 区域（左上角）----
            if ((x_r1 >= LOGO_X) && (x_r1 < LOGO_X + LOGO_W) &&
                (y_r1 >= LOGO_Y) && (y_r1 < LOGO_Y + LOGO_H)) begin
                logo_lx   = x_r1 - LOGO_X;
                logo_ly   = y_r1 - LOGO_Y;
                logo_addr = logo_ly * LOGO_W + logo_lx;
                if (logo_pixel[24]) begin   // bit24 为 1 表示不透明像素
                    osd_hit   = 1'b1;
                    osd_color = logo_pixel[23:0];
                end
            end

            // ---- (b) 模式文字区域（左下角）----
            if (!osd_hit &&
                (x_r1 >= TXT_X) && (x_r1 < TXT_X + TXT_W) &&
                (y_r1 >= TXT_Y) && (y_r1 < TXT_Y + TXT_H)) begin
                txt_local_x = x_r1 - TXT_X;             // 0..TXT_W-1
                txt_local_y = y_r1 - TXT_Y;             // 0..TXT_H-1
                txt_glyph   = txt_local_x / TXT_PITCH;  // 字符序号
                txt_lx      = txt_local_x % TXT_PITCH;  // 字符内列(0..17)
                if ((txt_glyph < TXT_CHARS) && (txt_lx < 32) && (txt_local_y < 40)) begin
                    char_sel = F_mode_glyph(osd_mode, txt_glyph);
                    char_row = txt_local_y[5:0];
                    text_pixel_on = char_row_bits[31 - txt_lx[5:0]]; // bit31=最左列
                end
                if (text_pixel_on) begin
                    osd_hit   = 1'b1;
                    osd_color = COLOR_TEXT;
                end
                else begin
                    osd_hit   = 1'b1;   // 底条（含字符间隔与下边距）
                    osd_color = COLOR_BAR;
                end
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
            O_tdata  <= 24'd0;
        end
        else begin
            O_tvalid <= valid_r1;
            O_tlast  <= last_r1;
            O_tuser  <= user_r1;
            O_tdata  <= osd_hit ? osd_color : data_r1;
        end
    end

    //----------------------------------------------------------------------
    // 6. 子模块例化
    //----------------------------------------------------------------------
    anlogic_logo_rom u_anlogic_logo_rom(
        .I_addr  ( logo_addr ),
        .O_pixel ( logo_pixel )
    );

    osd_char_lib u_osd_char_lib(
        .I_char    ( char_sel       ),
        .I_row     ( char_row       ),
        .O_row_bits( char_row_bits  )
    );

endmodule
