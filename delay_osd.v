`timescale 1ns / 1ps
//=============================================================
// delay_osd.v
// 处理延迟可视化 OSD 叠加模块
//
// 显示内容（黄色，与"安路"汉字同色）：
//   第一行 = DELAY:[帧数]帧
//   第二行 = DELAY:[延时ms]ms
//   第三行 = xx.x fps
//   第四行 = [宽度]*[高度] px
//
// 风格：延迟文本采用与“安路”相同的 16x16 点阵格式，字符 1:1 输出；
// 每个字符保留 16 像素完整窗口，字符之间只留 1 像素间隔。
//   这样文字更细、更小，且 DELAY、数字、帧和 ms 的字形风格统一。
//=============================================================
module delay_osd #(
    parameter IMG_WIDTH        = 1024,
    parameter IMG_HEIGHT       = 600,
    parameter [11:0] DIGIT_X   = 12'd8,
    parameter [11:0] DIGIT_Y0  = 12'd196,
    parameter [11:0] DIGIT_Y1  = 12'd216,
    parameter [11:0] FPS_Y     = 12'd240,
    parameter [11:0] RESOLUTION_Y = 12'd264,
    // 字符步进取 17 像素：16 像素字模 + 1 像素间隔，约为原 34 像素
    // 排版步进的一半；左端 DIGIT_X 保持不变。
    parameter [11:0] PITCH_X   = 12'd17,
    parameter [23:0] COLOR_DLY = 24'hFFF200
)(
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_delay_valid,
    input  wire [3:0]  I_delay_frames,
    input  wire [9:0]  I_delay_ms,
    input  wire        I_fps_valid,
    input  wire [9:0]  I_fps_tenths,
    input  wire        I_tuser,
    input  wire        I_tlast,
    input  wire        I_tvalid,
    input  wire [23:0] I_tdata,
    output reg         O_tuser,
    output reg         O_tlast,
    output reg         O_tvalid,
    output reg  [23:0] O_tdata
);

    // 延迟文字与“安路”共用 16x16 点阵格式，直接 1:1 显示。
    // ASCII 与汉字“帧”统一使用完整 16x16 字符窗口，避免汉字被裁小。
    localparam [11:0] DIGIT_W  = 12'd16;
    localparam [11:0] DIGIT_H  = 12'd16;
    localparam [11:0] FRAME_W  = 12'd16;
    wire [3:0] delay_frames_disp = (I_delay_frames > 4'd9) ? 4'd9 : I_delay_frames;

    //---------------------------------------------------------
    // double-dabble: 10bit → 3 BCD
    //---------------------------------------------------------
    function [11:0] F_bin2bcd3;
        input [9:0] I_val;
        integer i;
        reg [21:0] sh;
        begin
            sh = {12'd0, I_val};
            for (i = 0; i < 10; i = i + 1) begin
                if (sh[13:10] >= 4'd5) sh[13:10] = sh[13:10] + 4'd3;
                if (sh[17:14] >= 4'd5) sh[17:14] = sh[17:14] + 4'd3;
                if (sh[21:18] >= 4'd5) sh[21:18] = sh[21:18] + 4'd3;
                sh = sh << 1;
            end
            F_bin2bcd3 = sh[21:10];
        end
    endfunction
    wire [11:0] delay_bcd = F_bin2bcd3(I_delay_ms);
    wire [3:0] bcd_hund = delay_bcd[11:8];
    wire [3:0] bcd_ten  = delay_bcd[7:4];
    wire [3:0] bcd_ones = delay_bcd[3:0];
    wire [11:0] fps_bcd = F_bin2bcd3(I_fps_tenths);
    wire [3:0] fps_hund = fps_bcd[11:8];
    wire [3:0] fps_tens = fps_bcd[7:4];
    wire [3:0] fps_ones = fps_bcd[3:0];

    localparam [3:0] IMG_W_1000 = (IMG_WIDTH / 1000) % 10;
    localparam [3:0] IMG_W_100  = (IMG_WIDTH / 100) % 10;
    localparam [3:0] IMG_W_10   = (IMG_WIDTH / 10) % 10;
    localparam [3:0] IMG_W_1    = IMG_WIDTH % 10;
    localparam [3:0] IMG_H_100  = (IMG_HEIGHT / 100) % 10;
    localparam [3:0] IMG_H_10   = (IMG_HEIGHT / 10) % 10;
    localparam [3:0] IMG_H_1    = IMG_HEIGHT % 10;

    function [7:0] F_fps_char;
        input integer I_index;
        begin
            case (I_index)
                0: F_fps_char = I_fps_valid ? (8'h30 | {4'h0, fps_hund}) : 8'h20;
                1: F_fps_char = I_fps_valid ? (8'h30 | {4'h0, fps_tens}) : 8'h20;
                2: F_fps_char = I_fps_valid ? 8'h2E : 8'h20;
                3: F_fps_char = I_fps_valid ? (8'h30 | {4'h0, fps_ones}) : 8'h20;
                5: F_fps_char = 8'h66;
                6: F_fps_char = 8'h70;
                7: F_fps_char = 8'h73;
                default: F_fps_char = 8'h20;
            endcase
        end
    endfunction

    function [7:0] F_resolution_char;
        input integer I_index;
        begin
            case (I_index)
                0: F_resolution_char = 8'h30 | {4'h0, IMG_W_1000};
                1: F_resolution_char = 8'h30 | {4'h0, IMG_W_100};
                2: F_resolution_char = 8'h30 | {4'h0, IMG_W_10};
                3: F_resolution_char = 8'h30 | {4'h0, IMG_W_1};
                4: F_resolution_char = 8'h2A;
                5: F_resolution_char = 8'h30 | {4'h0, IMG_H_100};
                6: F_resolution_char = 8'h30 | {4'h0, IMG_H_10};
                7: F_resolution_char = 8'h30 | {4'h0, IMG_H_1};
                9: F_resolution_char = 8'h70;
                10: F_resolution_char = 8'h78;
                default: F_resolution_char = 8'h20;
            endcase
        end
    endfunction

    //---------------------------------------------------------
    // 坐标计数 + 2 级流水
    //---------------------------------------------------------
    reg [11:0] S_x, S_y;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            S_x <= 12'd0; S_y <= 12'd0;
        end
        // 不依赖上游可能滞留的 tuser/tlast，按固定有效像素数计数，
        // 这样 OSD 坐标在所有 VPP 模式下都保持一致。
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
    reg valid_r1, last_r1, user_r1;
    reg [23:0] data_r1;
    reg [11:0] x_r1, y_r1;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            valid_r1 <= 1'b0; last_r1 <= 1'b0; user_r1 <= 1'b0;
            data_r1 <= 24'd0; x_r1 <= 12'd0; y_r1 <= 12'd0;
        end
        else begin
            valid_r1 <= I_tvalid; last_r1 <= I_tlast; user_r1 <= I_tuser;
            data_r1  <= I_tdata;
            x_r1     <= (I_tvalid && I_tuser) ? 12'd0 : S_x;
            y_r1     <= (I_tvalid && I_tuser) ? 12'd0 : S_y;
        end
    end

    //---------------------------------------------------------
    // 组合命中判定
    // 第一行: D E L A Y : [帧数] [帧]   (8字符)
    // 第二行: D E L A Y : [百][十][个] m s (11字符)
    // 第三行: xx.x fps (8字符)
    // 第四行: [宽度]*[高度] px (11字符)
    //---------------------------------------------------------
    reg        dly_on;
    reg  [7:0] dly_char;
    reg        dly_is_cn;
    reg [11:0] dly_dx;
    reg [11:0] dly_dy;
    integer fps_char_index;
    integer resolution_char_index;

    always @(*) begin
        dly_on    = 1'b0;
        dly_char  = 8'h00;
        dly_is_cn = 1'b0;
        dly_dx    = 12'd0;
        dly_dy    = 12'd0;

        // ---- 第一行 ----
        if ((y_r1 >= DIGIT_Y0) && (y_r1 < DIGIT_Y0 + DIGIT_H)) begin
            dly_dy = y_r1 - DIGIT_Y0;
            if      (x_r1 >= DIGIT_X + 0*PITCH_X && x_r1 < DIGIT_X + 0*PITCH_X + DIGIT_W) begin
                dly_on = 1'b1; dly_char = 8'h44; dly_dx = x_r1 - DIGIT_X;
            end
            else if (x_r1 >= DIGIT_X + 1*PITCH_X && x_r1 < DIGIT_X + 1*PITCH_X + DIGIT_W) begin
                dly_on = 1'b1; dly_char = 8'h45; dly_dx = x_r1 - DIGIT_X - 1*PITCH_X;
            end
            else if (x_r1 >= DIGIT_X + 2*PITCH_X && x_r1 < DIGIT_X + 2*PITCH_X + DIGIT_W) begin
                dly_on = 1'b1; dly_char = 8'h4C; dly_dx = x_r1 - DIGIT_X - 2*PITCH_X;
            end
            else if (x_r1 >= DIGIT_X + 3*PITCH_X && x_r1 < DIGIT_X + 3*PITCH_X + DIGIT_W) begin
                dly_on = 1'b1; dly_char = 8'h41; dly_dx = x_r1 - DIGIT_X - 3*PITCH_X;
            end
            else if (x_r1 >= DIGIT_X + 4*PITCH_X && x_r1 < DIGIT_X + 4*PITCH_X + DIGIT_W) begin
                dly_on = 1'b1; dly_char = 8'h59; dly_dx = x_r1 - DIGIT_X - 4*PITCH_X;
            end
            else if (x_r1 >= DIGIT_X + 5*PITCH_X && x_r1 < DIGIT_X + 5*PITCH_X + DIGIT_W) begin
                dly_on = 1'b1; dly_char = 8'h3A; dly_dx = x_r1 - DIGIT_X - 5*PITCH_X;
            end
            else if (I_delay_valid && x_r1 >= DIGIT_X + 6*PITCH_X && x_r1 < DIGIT_X + 6*PITCH_X + DIGIT_W) begin
                dly_on = 1'b1; dly_char = 8'h30 | {4'h0, delay_frames_disp};
                dly_dx = x_r1 - DIGIT_X - 6*PITCH_X;
            end
            // 汉字“帧”，宽 16，与 ASCII 字符同高
            else if (x_r1 >= DIGIT_X + 7*PITCH_X && x_r1 < DIGIT_X + 7*PITCH_X + FRAME_W) begin
                dly_on    = 1'b1;
                dly_is_cn = 1'b1;
                dly_dx    = x_r1 - DIGIT_X - 7*PITCH_X;
            end
        end
        // ---- 第二行 ----
        else if ((y_r1 >= DIGIT_Y1) && (y_r1 < DIGIT_Y1 + DIGIT_H)) begin
            dly_dy = y_r1 - DIGIT_Y1;
            if      (x_r1 >= DIGIT_X + 0*PITCH_X && x_r1 < DIGIT_X + 0*PITCH_X + DIGIT_W) begin
                dly_on = 1'b1; dly_char = 8'h44; dly_dx = x_r1 - DIGIT_X;
            end
            else if (x_r1 >= DIGIT_X + 1*PITCH_X && x_r1 < DIGIT_X + 1*PITCH_X + DIGIT_W) begin
                dly_on = 1'b1; dly_char = 8'h45; dly_dx = x_r1 - DIGIT_X - 1*PITCH_X;
            end
            else if (x_r1 >= DIGIT_X + 2*PITCH_X && x_r1 < DIGIT_X + 2*PITCH_X + DIGIT_W) begin
                dly_on = 1'b1; dly_char = 8'h4C; dly_dx = x_r1 - DIGIT_X - 2*PITCH_X;
            end
            else if (x_r1 >= DIGIT_X + 3*PITCH_X && x_r1 < DIGIT_X + 3*PITCH_X + DIGIT_W) begin
                dly_on = 1'b1; dly_char = 8'h41; dly_dx = x_r1 - DIGIT_X - 3*PITCH_X;
            end
            else if (x_r1 >= DIGIT_X + 4*PITCH_X && x_r1 < DIGIT_X + 4*PITCH_X + DIGIT_W) begin
                dly_on = 1'b1; dly_char = 8'h59; dly_dx = x_r1 - DIGIT_X - 4*PITCH_X;
            end
            else if (x_r1 >= DIGIT_X + 5*PITCH_X && x_r1 < DIGIT_X + 5*PITCH_X + DIGIT_W) begin
                dly_on = 1'b1; dly_char = 8'h3A; dly_dx = x_r1 - DIGIT_X - 5*PITCH_X;
            end
            else if (I_delay_valid && x_r1 >= DIGIT_X + 6*PITCH_X && x_r1 < DIGIT_X + 6*PITCH_X + DIGIT_W) begin
                dly_on = 1'b1; dly_char = 8'h30 | {4'h0, bcd_hund};
                dly_dx = x_r1 - DIGIT_X - 6*PITCH_X;
            end
            else if (I_delay_valid && x_r1 >= DIGIT_X + 7*PITCH_X && x_r1 < DIGIT_X + 7*PITCH_X + DIGIT_W) begin
                dly_on = 1'b1; dly_char = 8'h30 | {4'h0, bcd_ten};
                dly_dx = x_r1 - DIGIT_X - 7*PITCH_X;
            end
            else if (I_delay_valid && x_r1 >= DIGIT_X + 8*PITCH_X && x_r1 < DIGIT_X + 8*PITCH_X + DIGIT_W) begin
                dly_on = 1'b1; dly_char = 8'h30 | {4'h0, bcd_ones};
                dly_dx = x_r1 - DIGIT_X - 8*PITCH_X;
            end
            else if (x_r1 >= DIGIT_X + 9*PITCH_X && x_r1 < DIGIT_X + 9*PITCH_X + DIGIT_W) begin
                dly_on = 1'b1; dly_char = 8'h6D; dly_dx = x_r1 - DIGIT_X - 9*PITCH_X;  // 'm'
            end
            else if (x_r1 >= DIGIT_X + 10*PITCH_X && x_r1 < DIGIT_X + 10*PITCH_X + DIGIT_W) begin
                dly_on = 1'b1; dly_char = 8'h73; dly_dx = x_r1 - DIGIT_X - 10*PITCH_X; // 's'
            end
        end
        // ---- 第三行：实时 FPS ----
        else if ((y_r1 >= FPS_Y) && (y_r1 < FPS_Y + DIGIT_H)) begin
            dly_dy = y_r1 - FPS_Y;
            for (fps_char_index = 0; fps_char_index < 8; fps_char_index = fps_char_index + 1) begin
                if ((x_r1 >= DIGIT_X + fps_char_index*PITCH_X) &&
                    (x_r1 < DIGIT_X + fps_char_index*PITCH_X + DIGIT_W)) begin
                    dly_on = 1'b1;
                    dly_char = F_fps_char(fps_char_index);
                    dly_dx = x_r1 - DIGIT_X - fps_char_index*PITCH_X;
                end
            end
        end
        // ---- 第四行：当前视频分辨率 ----
        else if ((y_r1 >= RESOLUTION_Y) && (y_r1 < RESOLUTION_Y + DIGIT_H)) begin
            dly_dy = y_r1 - RESOLUTION_Y;
            for (resolution_char_index = 0; resolution_char_index < 11; resolution_char_index = resolution_char_index + 1) begin
                if ((x_r1 >= DIGIT_X + resolution_char_index*PITCH_X) &&
                    (x_r1 < DIGIT_X + resolution_char_index*PITCH_X + DIGIT_W)) begin
                    dly_on = 1'b1;
                    dly_char = F_resolution_char(resolution_char_index);
                    dly_dx = x_r1 - DIGIT_X - resolution_char_index*PITCH_X;
                end
            end
        end
    end

    //---------------------------------------------------------
    // 统一 16x16 字库查询（ASCII、数字、m/s 以及保留码 8'hFE=“帧”）。
    //---------------------------------------------------------
    wire [7:0]  dly_lib_char = dly_is_cn ? 8'hFE : dly_char;
    wire [15:0] dly_char_bits;
    osd_char_lib16 u_osd_char_lib16 (
        .I_char     ( dly_lib_char  ),
        .I_row      ( dly_dy[3:0]   ),
        .O_row_bits ( dly_char_bits )
    );

    //---------------------------------------------------------
    // 笔画命中汇总
    //---------------------------------------------------------
    wire dly_hit = dly_on & dly_char_bits[15 - dly_dx[3:0]];

    //---------------------------------------------------------
    // 输出级
    //---------------------------------------------------------
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
            O_tdata  <= dly_hit ? COLOR_DLY : data_r1;
        end
    end

endmodule
