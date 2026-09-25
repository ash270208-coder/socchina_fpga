`timescale 1ns / 1ps
//=============================================================
// delay_osd.v
// 处理延迟可视化 OSD 叠加模块
//
// 显示内容（黄色，与"安路"汉字同色）：
//   第一行 = DELAY:[帧数]帧
//   第二行 = DELAY:[延时ms]ms
//
// 风格：延迟文本采用与“安路”相同的 16x16 点阵格式，字符 1:1 输出；
// 每个字符保留 16 像素完整窗口，字符之间只留 1 像素间隔。
//   这样文字更细、更小，且 DELAY、数字、帧和 ms 的字形风格统一。
//=============================================================
module delay_osd #(
    parameter IMG_WIDTH        = 1024,
    parameter IMG_HEIGHT       = 600,
    parameter [3:0] LAG_FRAMES = 4'd2,
    parameter integer LAG_SHIFT = 1,
    parameter [11:0] DIGIT_X   = 12'd8,
    parameter [11:0] DIGIT_Y0  = 12'd196,
    parameter [11:0] DIGIT_Y1  = 12'd216,
    // 字符步进取 17 像素：16 像素字模 + 1 像素间隔，约为原 34 像素
    // 排版步进的一半；左端 DIGIT_X 保持不变。
    parameter [11:0] PITCH_X   = 12'd17,
    parameter integer CLK_FREQ_HZ = 52000000,
    parameter [15:0] DEFAULT_FRAME_MS = 16'd33,
    parameter [23:0] COLOR_DLY = 24'hFFF200
)(
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_cap_clk,
    input  wire        I_cap_rst_n,
    input  wire        I_cap_frame_start,
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
    localparam [3:0]  LAG_DISP   = (LAG_FRAMES > 4'd9) ? 4'd9 : LAG_FRAMES;
    localparam [15:0] MS_DIV_MINUS1 = CLK_FREQ_HZ / 1000 - 1;

    //---------------------------------------------------------
    // 跨时钟域：采集帧首 → 显示域
    //---------------------------------------------------------
    reg cap_start_d, cap_toggle;
    always @(posedge I_cap_clk or negedge I_cap_rst_n) begin
        if (!I_cap_rst_n) begin
            cap_start_d <= 1'b0;
            cap_toggle  <= 1'b0;
        end
        else begin
            cap_start_d <= I_cap_frame_start;
            if (I_cap_frame_start & ~cap_start_d)
                cap_toggle <= ~cap_toggle;
        end
    end
    reg cap_sync1, cap_sync2, cap_sync3;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            cap_sync1 <= 1'b0; cap_sync2 <= 1'b0; cap_sync3 <= 1'b0;
        end
        else begin
            cap_sync1 <= cap_toggle;
            cap_sync2 <= cap_sync1;
            cap_sync3 <= cap_sync2;
        end
    end
    wire cap_event = cap_sync2 ^ cap_sync3;

    //---------------------------------------------------------
    // 1ms 计时器
    //---------------------------------------------------------
    reg [15:0] ms_cnt;
    reg        ms_tick;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            ms_cnt  <= 16'd0;
            ms_tick <= 1'b0;
        end
        else if (ms_cnt == MS_DIV_MINUS1) begin
            ms_cnt  <= 16'd0;
            ms_tick <= 1'b1;
        end
        else begin
            ms_cnt  <= ms_cnt + 16'd1;
            ms_tick <= 1'b0;
        end
    end

    //---------------------------------------------------------
    // 帧周期实测
    //---------------------------------------------------------
    reg [15:0] ms_run, frame_ms;
    reg        frame_ms_vld;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            ms_run       <= 16'd0;
            frame_ms     <= DEFAULT_FRAME_MS;
            frame_ms_vld <= 1'b0;
        end
        else if (cap_event) begin
            if ((ms_run >= 16'd10) && (ms_run <= 16'd100)) begin
                if (!frame_ms_vld) begin
                    frame_ms     <= ms_run;
                    frame_ms_vld <= 1'b1;
                end
                else if ((ms_run > frame_ms + 16'd2) || (ms_run + 16'd2 < frame_ms))
                    frame_ms <= ms_run;
            end
            ms_run <= 16'd0;
        end
        else if (ms_tick)
            ms_run <= (ms_run >= 16'd200) ? 16'd200 : (ms_run + 16'd1);
    end

    wire [15:0] delay_ms_raw = frame_ms << LAG_SHIFT;
    wire [15:0] delay_ms     = (delay_ms_raw > 16'd999) ? 16'd999 : delay_ms_raw;

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
    wire [11:0] delay_bcd = F_bin2bcd3(delay_ms[9:0]);
    wire [3:0] bcd_hund = delay_bcd[11:8];
    wire [3:0] bcd_ten  = delay_bcd[7:4];
    wire [3:0] bcd_ones = delay_bcd[3:0];

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
    //---------------------------------------------------------
    reg        dly_on;
    reg  [7:0] dly_char;
    reg        dly_is_cn;
    reg [11:0] dly_dx;
    reg [11:0] dly_dy;

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
            else if (x_r1 >= DIGIT_X + 6*PITCH_X && x_r1 < DIGIT_X + 6*PITCH_X + DIGIT_W) begin
                dly_on = 1'b1; dly_char = 8'h30 | {4'h0, LAG_DISP};
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
            else if (x_r1 >= DIGIT_X + 6*PITCH_X && x_r1 < DIGIT_X + 6*PITCH_X + DIGIT_W) begin
                dly_on = 1'b1; dly_char = 8'h30 | {4'h0, bcd_hund};
                dly_dx = x_r1 - DIGIT_X - 6*PITCH_X;
            end
            else if (x_r1 >= DIGIT_X + 7*PITCH_X && x_r1 < DIGIT_X + 7*PITCH_X + DIGIT_W) begin
                dly_on = 1'b1; dly_char = 8'h30 | {4'h0, bcd_ten};
                dly_dx = x_r1 - DIGIT_X - 7*PITCH_X;
            end
            else if (x_r1 >= DIGIT_X + 8*PITCH_X && x_r1 < DIGIT_X + 8*PITCH_X + DIGIT_W) begin
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
