`timescale 1ns / 1ps
//=============================================================================
// osd_box_drawer.v - face box + X/Y/W/H coordinate readout on the video stream
//-----------------------------------------------------------------------------
//   Detection coordinates live in the 128x72 downscaled space used by the
//   board-B CNN, so SCALE_FACTOR maps them onto the 1280x720 display stream.
//
//   Two things are overlaid on the incoming AXI-Stream:
//     1) a LINE_THICK-pixel BOX_COLOR rectangle around the detected face;
//     2) a black-backed white "X:nnnn Y:nnnn W:nnnn H:nnnn" readout in the
//        top-right corner (27 cells x 16 pixels) showing the same numbers.
//
//   Box and text share one latched detection: I_face_valid captures the
//   coordinates and reloads the frame hold counter (HOLD_FRAMES), so a few
//   dropped detections do not make the overlay flicker.
//
//   MIN_WH rejects degenerate detections. Board B's cnn_head_dec asserts its
//   output valid every frame and reports "no anchor above threshold" as
//   w=h=0 (or a one-pixel sliver). Those frames must be IGNORED rather than
//   latched - otherwise a single missed detection replaces a good box with an
//   empty one AND reloads the hold counter, so the hold period never applies
//   and the symptom is "the box often disappears".
//
//   The stream is registered once (1 cycle). The HDMI vsync compensation in
//   design_top_wrapper must account for exactly that one extra beat.
//
//-----------------------------------------------------------------------------
// 2026-10-25 "框右下贴底贴右 + 框很大 + 脸不在框正中" 的根因与修法
//-----------------------------------------------------------------------------
//   现象：绿框的左/上边跟着脸走，右/下边永远贴在 1279/719 上，框显得很大，
//         脸偏在框的左上，右上角读数里 H = 720 - Y（或 W = 1280 - X）。
//
//   板 B 的框是**以中心回归**的：cx = x1 + w/2，cy = y1 + h/2，而 w/h 现在很大
//   （v2 重训后锚框 3 = 45.6 x 49.6 格 = 456 x 496 px，占屏高 69%）。于是
//       · 脸顶一低于 224 px，y1 + h 就 >= 72 格  -> 下边必然压到 719
//       · 脸左一超过 824 px，x1 + w 就 >= 128 格 -> 右边必然压到 1279
//   本模块原来的做法是「左上角原样保留、只把右下角夹到屏幕内」，于是这种
//   "越界" 被画成「从脸的左上角一直拉到屏幕角」—— 框看起来巨大、右下贴边。
//   而框本身是以脸为中心的，只裁右下不动左上，可见矩形的心就被推向左上 =>
//   脸看起来偏在框的左上角（不是正中间）。这不是缩放/坐标算错，是本模块的
//   **裁剪策略** 把"框比剩余画面大"放大成了视觉灾难。
//
//   FIT_MODE 选择裁剪策略：
//     0 = 旧行为（右下硬裁，左上不动）—— 仅用于回归对照，会复现上述症状
//     1 = 默认：**尺寸不动，把整框平移进屏幕**（不再有任何一条边贴屏幕边）
//   两种模式都先把 w/h 夹到屏幕尺寸内，避免 8 位 w/h 溢出后算出负坐标。
//   注意：本模块只能保证"框完整可见且不再贴边"；框本身的绝对大小由板 B 的
//   锚框/回归决定，要根治"框太大"必须改板 B（见 docs/BOX_PINNING_ROOTCAUSE.md）。
//=============================================================================
module osd_box_drawer #(
    parameter IN_WIDTH     = 1280,
    parameter IN_HEIGHT    = 720,
    parameter SCALE_FACTOR = 10,
    parameter LINE_THICK   = 3,
    parameter BOX_COLOR    = 24'h00FF00,
    parameter HOLD_FRAMES  = 30,
    parameter [7:0] MIN_WH = 8'd2,
    // 裁剪策略（详见文件头 2026-10-25 说明）：
    //   0 = 旧行为：左上角不动、右下角硬裁到屏幕内
    //       => x1+w / y1+h 越界时右/下边被钉在 1279/719（"框很大、右下贴边"）
    //   1 = 默认/推荐：保持板 B 给的尺寸（或按下面 MAX_*_CELLS 收缩，围绕中心），
    //       再整框平移进屏幕 —— 任何一条边都不会被"切"掉
    parameter [1:0]  FIT_MODE = 2'd1,
    // 显示侧"最大框"限幅（128x72 检测格）。默认 128 / 72 = 不限制。
    //   板 B 的锚框偏大时（v2 重训后 anchor3 = 45.6x49.6 格），把它们调小可以在
    //   **不动板 B** 的前提下把框收紧，例如 MAX_W_CELLS=60 / MAX_H_CELLS=66。
    //   收缩是**围绕框中心**做的，所以不会把脸挤出框外。
    parameter [7:0]  MAX_W_CELLS = 8'd128,
    parameter [7:0]  MAX_H_CELLS = 8'd72,
    // 显示侧"框收缩"倍数（**围绕框中心**收，所以脸不会偏）：
    //   0 = 不收缩(*1.0)   1 = *0.5   2 = *0.75   3 = *0.875
    //   板 B 的锚框偏大导致"框比脸大一圈"时，用这个一格一格往回收，
    //   不需要改板 B 的权重/锚框。收缩后仍然保证整框在屏幕内。
    parameter [1:0]  SHRINK_LOG2 = 2'd0,
    // 显示侧"框形状兜底"：h > 1.5w 时按 1.25w 重算（把"整幅高"的假框收回来）。
    //   0 = 关（直接用板 B 原始 w/h）  1 = 开（默认）
    parameter        SANITIZE = 1,
    // 第 2 行读数（板 B 原始格坐标）：1 = 显示，0 = 不显示（默认 0）。
    //   ⚠ 板 A 的 slice/特殊网（clk/CE）已经很紧：2026-10-25 18:09 那次布局
    //   就报过 PHY-9052/PHY-8077（"Spreading special nets failed" +
    //   "AL_MAP_SEQ with unsupported ppm"），把读数加到两行会让它更紧。
    //   所以第 2 行默认关掉；要看板 B 原始值请用 READOUT_RAW_CELLS = 1
    //   （那是纯组合选择，不增加任何逻辑）。
    parameter        SHOW_RAW_LINE = 0,
    // 右上角 27 格读数显示什么：
    //   0 = **HDMI 屏幕上的真实像素坐标**（框左上角 x1/y1 与宽高 w/h，范围 0~1279 / 0~719）
    //       —— 正常使用就选这个
    //   1 = 板 B 送来的**原始格坐标**（128x72 检测网格，0~255），调试用
    // 注意：模式 0 显示的是"屏幕上实际画出来的框"，因此框超出画面时 w/h 是被裁过的
    //       （这正是你在屏幕上看到的）；网络"想要"多大，看模式 1。
    parameter        READOUT_RAW_CELLS = 0
)(
    input  wire        I_clk,
    input  wire        I_rst_n,

    input  wire        I_tvalid,
    input  wire        I_tuser,
    input  wire        I_tlast,
    input  wire [23:0] I_tdata,

    input  wire        I_face_valid,
    input  wire [7:0]  I_face_x,
    input  wire [7:0]  I_face_y,
    input  wire [7:0]  I_face_w,
    input  wire [7:0]  I_face_h,

    output reg         O_tvalid,
    output reg         O_tuser,
    output reg         O_tlast,
    output reg  [23:0] O_tdata
);

    localparam [12:0] SCREEN_W = IN_WIDTH;
    localparam [12:0] SCREEN_H = IN_HEIGHT;
    localparam [10:0] TEXT_WIDTH = 11'd432; // 27 ASCII cells, each 16 pixels wide
    localparam [10:0] TEXT_LEFT = (IN_WIDTH > 448) ? (IN_WIDTH - 448) : 0;
    localparam [9:0]  TEXT_TOP = 10'd16;

    reg [10:0] cur_x;
    reg [9:0]  cur_y;

    // tuser marks the first pixel of a frame. Use its coordinate immediately,
    // since the counters are synchronously reset on this same edge.
    wire [10:0] pixel_x = I_tuser ? 11'd0 : cur_x;
    wire [9:0]  pixel_y = I_tuser ? 10'd0 : cur_y;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            cur_x <= 11'd0;
            cur_y <= 10'd0;
        end else if (I_tuser) begin
            // The SOF pixel itself uses pixel_x=0 above; advance the stored
            // coordinate so the next valid pixel is x=1 rather than x=0 again.
            cur_x <= I_tvalid ? 11'd1 : 11'd0;
            cur_y <= 10'd0;
        end else if (I_tvalid) begin
            if (I_tlast || (pixel_x == IN_WIDTH - 1)) begin
                cur_x <= 11'd0;
                cur_y <= (pixel_y >= IN_HEIGHT - 1) ? 10'd0 : pixel_y + 1'b1;
            end else begin
                cur_x <= pixel_x + 1'b1;
            end
        end
    end

    reg [10:0] box_x1, box_x2; // [x1,x2), with x2 allowed to equal IN_WIDTH
    reg [9:0]  box_y1, box_y2; // [y1,y2), with y2 allowed to equal IN_HEIGHT
    reg [7:0]  hold_cnt;       // 8 bit so HOLD_FRAMES may exceed 63
    reg        box_enable;

    wire [11:0] scaled_x = {4'b0000, I_face_x} * SCALE_FACTOR;
    wire [11:0] scaled_y = {4'b0000, I_face_y} * SCALE_FACTOR;
    wire [11:0] scaled_w = {4'b0000, I_face_w} * SCALE_FACTOR;
    wire [11:0] scaled_h = {4'b0000, I_face_h} * SCALE_FACTOR;
    wire [12:0] raw_x2 = {1'b0, scaled_x} + {1'b0, scaled_w};
    wire [12:0] raw_y2 = {1'b0, scaled_y} + {1'b0, scaled_h};

    // ---- 尺寸：先按 MAX_*_CELLS 收缩，再夹到屏幕以内 ----
    //   板 B 的 w/h 是 8 位（最大 255 格 = 2550 px）；不夹住的话下面"平移进屏幕"
    //   的 SCREEN_W - box_w 会算出负值（回绕成大数）。
    wire [11:0] max_w_pix = {4'b0000, MAX_W_CELLS} * SCALE_FACTOR;
    wire [11:0] max_h_pix = {4'b0000, MAX_H_CELLS} * SCALE_FACTOR;

    // 围绕中心收缩（可选）：w' = w - (w >> SHRINK_LOG2)
    //   SHRINK_LOG2=0 时不能用 w-(w>>0)=0，必须单独旁路。
    wire [12:0] shr_w = (SHRINK_LOG2 == 2'd0) ? {1'b0, scaled_w}
                       : ({1'b0, scaled_w} - ({1'b0, scaled_w} >> SHRINK_LOG2));
    wire [12:0] shr_h = (SHRINK_LOG2 == 2'd0) ? {1'b0, scaled_h}
                       : ({1'b0, scaled_h} - ({1'b0, scaled_h} >> SHRINK_LOG2));

    // ---- 显示侧"框形状兜底"（SANITIZE）----
    //   2026-10-25 上板实测（照片读数 X:0000 Y:0000 W:1280 H:0720）：
    //   板 B 回包里的 h 恒 >= 72 格（= 整幅高度）、w 时大时正常，也就是
    //   **模型把 tw/th 顶到了输出上限**，报出来的是"整幅画面"而不是人脸。
    //   人脸的 h/w 只可能落在 1.1~1.5，所以当 h > 1.5w 时判 h 不可信，
    //   按 1.25w 重算（与 2026-10-23 文档里提的兜底同一条），
    //   先保证画面里不会出现"整幅高"的绿框。
    //   SANITIZE = 0 可关掉，直接使用板 B 的原始 w/h。
    //   注意：w 先按 MAX_W_CELLS 夹住，再拿它去校验 h 的比例 ——
    //   否则 w 也顶到 255 时 h/w=1 会绕过比例检查，又画成满屏。
    wire [12:0] w_lim     = (shr_w > {1'b0, max_w_pix}) ? {1'b0, max_w_pix} : shr_w;
    wire [12:0] h_cap_lo  = w_lim + (w_lim >> 2);              // 1.25 * w
    wire        h_railed  = (shr_h > (w_lim + (w_lim >> 1)));   // h > 1.5 * w ?
    wire [12:0] shp_h     = (SANITIZE && h_railed) ? h_cap_lo : shr_h;

    wire [12:0] size_w = (w_lim > SCREEN_W) ? SCREEN_W : w_lim;
    wire [12:0] size_h = (shp_h > {1'b0, max_h_pix}) ? {1'b0, max_h_pix} : shp_h;
    wire [12:0] box_w  = (size_w > SCREEN_W) ? SCREEN_W : size_w;
    wire [12:0] box_h  = (size_h > SCREEN_H) ? SCREEN_H : size_h;

    // ---- FIT_MODE=0（旧行为）：左上角原样保留，只把右下角夹到屏幕内 ----
    wire [12:0] clip_x1 = (scaled_x >= SCREEN_W) ? SCREEN_W : {1'b0, scaled_x};
    wire [12:0] clip_y1 = (scaled_y >= SCREEN_H) ? SCREEN_H : {1'b0, scaled_y};
    wire [12:0] clip_x2 = (raw_x2 > SCREEN_W) ? SCREEN_W : raw_x2;
    wire [12:0] clip_y2 = (raw_y2 > SCREEN_H) ? SCREEN_H : raw_y2;

    // ---- FIT_MODE=1（默认）：围绕**框中心**收缩，再整框平移进屏幕 ----
    //   板 B 的框本来就是按中心回归的（cx = x1 + w/2），所以收缩/平移都围绕它
    //   做，脸才会一直落在框的正中间。
    //   ⚠ 中心用哪个 w/h 有讲究：
    //     · 板 B 的 w/h **没被夹**  -> 用原始 scaled_w/h 算中心（= 真中心，
    //       SHRINK 收缩时才真的是"围绕中心收，脸不偏"）
    //     · 板 B 的 w/h **被 8 位上限/MAX 夹过** -> 这个"中心"是假的
    //       （板 B 已把 x1 夹到 0，x1+255/2 会跑到画面另一侧），改用夹后的
    //       box_w/h，让框锚在 x1/y1 上，避免框在画面左右乱跳
    wire [12:0] w_for_centre = (scaled_w > {1'b0, max_w_pix}) ? box_w : {1'b0, scaled_w};
    wire [12:0] h_for_centre = (scaled_h > {1'b0, max_h_pix}) ? box_h : {1'b0, scaled_h};
    wire [12:0] cx_pix = {1'b0, scaled_x} + {1'b0, w_for_centre[12:1]};
    wire [12:0] cy_pix = {1'b0, scaled_y} + {1'b0, h_for_centre[12:1]};
    wire [12:0] cx_lim = (cx_pix > SCREEN_W) ? SCREEN_W : cx_pix;
    wire [12:0] cy_lim = (cy_pix > SCREEN_H) ? SCREEN_H : cy_pix;
    wire [12:0] cen_x1 = (cx_lim > {1'b0, box_w[12:1]}) ? (cx_lim - {1'b0, box_w[12:1]})
                                                        : 13'd0;
    wire [12:0] cen_y1 = (cy_lim > {1'b0, box_h[12:1]}) ? (cy_lim - {1'b0, box_h[12:1]})
                                                        : 13'd0;
    // 平移进屏幕：x1+w 超出就令 x1 = SCREEN_W-w（不再"切"右下角）
    wire [12:0] fit_x1 = (cen_x1 + box_w > SCREEN_W) ? (SCREEN_W - box_w) : cen_x1;
    wire [12:0] fit_y1 = (cen_y1 + box_h > SCREEN_H) ? (SCREEN_H - box_h) : cen_y1;

    wire [12:0] det_x1 = (FIT_MODE == 2'd0) ? clip_x1 : fit_x1;
    wire [12:0] det_y1 = (FIT_MODE == 2'd0) ? clip_y1 : fit_y1;
    wire [12:0] det_x2 = (FIT_MODE == 2'd0) ? clip_x2 : (fit_x1 + box_w);
    wire [12:0] det_y2 = (FIT_MODE == 2'd0) ? clip_y2 : (fit_y1 + box_h);

    // 板 B 报的框左上角整个在画面外（x>=128 格 / y>=72 格）-> 直接丢弃
    wire        box_off_screen = (scaled_x >= SCREEN_W) || (scaled_y >= SCREEN_H);
    wire        clipped_box_nonempty = (det_x2 > det_x1) && (det_y2 > det_y1);

    // A detection is usable only when it is neither degenerate (board B's
    // "no face this frame" report) nor entirely outside the visible screen.
    wire        detection_usable = (I_face_w >= MIN_WH) &&
                                   (I_face_h >= MIN_WH) &&
                                   !box_off_screen &&
                                   clipped_box_nonempty;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            box_x1     <= 11'd0;
            box_y1     <= 10'd0;
            box_x2     <= 11'd0;
            box_y2     <= 10'd0;
            hold_cnt   <= 8'd0;
            box_enable <= 1'b0;
        end else if (I_face_valid) begin
            if (detection_usable) begin
                box_x1     <= det_x1[10:0];
                box_y1     <= det_y1[9:0];
                box_x2     <= det_x2[10:0];
                box_y2     <= det_y2[9:0];
                hold_cnt   <= HOLD_FRAMES[7:0];
                box_enable <= 1'b1;
            end
            // Degenerate / off-screen detection: keep the latched box and let
            // the frame hold counter expire on its own.
        end else if (I_tvalid && I_tuser) begin
            // One decrement per frame. Gated on I_tvalid so a tuser that
            // lingers in a pipeline bubble cannot burn the hold period early.
            if (hold_cnt > 8'd1) begin
                hold_cnt <= hold_cnt - 1'b1;
            end else begin
                hold_cnt   <= 8'd0;
                box_enable <= 1'b0;
            end
        end
    end

    wire in_box_x = (pixel_x >= box_x1) && (pixel_x < box_x2);
    wire in_box_y = (pixel_y >= box_y1) && (pixel_y < box_y2);
    wire [10:0] dist_left = pixel_x - box_x1;
    wire [10:0] dist_right = box_x2 - 1'b1 - pixel_x;
    wire [9:0]  dist_top = pixel_y - box_y1;
    wire [9:0]  dist_bottom = box_y2 - 1'b1 - pixel_y;

    wire hit_border = box_enable && in_box_x && in_box_y &&
        ((dist_top < LINE_THICK) || (dist_bottom < LINE_THICK) ||
         (dist_left < LINE_THICK) || (dist_right < LINE_THICK));

    // ---- 右上角读数：两行 x 27 格 ----
    //   第 1 行 = **屏幕上画出来的框**（像素坐标，0~1279 / 0~719）
    //   第 2 行 = **板 B 送来的原始格坐标**（0~255）
    //   两行一比就知道"框太大"是板 B 给的、还是板 A 夹出来的：
    //     第2行 W/H 本来就很大 -> 板 B 的问题（模型/锚框/图像）
    //     第2行正常、第1行很大 -> 板 A 的问题
    wire [11:0] draw_x = {1'b0, box_x1};
    wire [11:0] draw_y = {2'b00, box_y1};
    wire [11:0] draw_w = {1'b0, box_x2} - {1'b0, box_x1};
    wire [11:0] draw_h = {2'b00, box_y2} - {2'b00, box_y1};

    wire [11:0] raw_x = {4'b0000, I_face_x};
    wire [11:0] raw_y = {4'b0000, I_face_y};
    wire [11:0] raw_w = {4'b0000, I_face_w};
    wire [11:0] raw_h = {4'b0000, I_face_h};

    // 老行为：READOUT_RAW_CELLS=1 时第 1 行也显示原始格坐标（单行调试模式）
    wire [11:0] display_x = READOUT_RAW_CELLS ? raw_x : draw_x;
    wire [11:0] display_y = READOUT_RAW_CELLS ? raw_y : draw_y;
    wire [11:0] display_w = READOUT_RAW_CELLS ? raw_w : draw_w;
    wire [11:0] display_h = READOUT_RAW_CELLS ? raw_h : draw_h;

    localparam [9:0] TEXT_TOP2 = TEXT_TOP + 10'd20;

    wire line1_region = box_enable &&
                        (pixel_x >= TEXT_LEFT) &&
                        (pixel_x < TEXT_LEFT + TEXT_WIDTH) &&
                        (pixel_y >= TEXT_TOP) &&
                        (pixel_y < TEXT_TOP + 10'd16);
    // SHOW_RAW_LINE = 0 时这是常量 0 -> 下面的 mux 全部被综合掉，
    // 逻辑与"只有一行读数"的老版本完全一致（布局结果也不会变）。
    wire line2_region = SHOW_RAW_LINE &&
                        box_enable &&
                        (pixel_x >= TEXT_LEFT) &&
                        (pixel_x < TEXT_LEFT + TEXT_WIDTH) &&
                        (pixel_y >= TEXT_TOP2) &&
                        (pixel_y < TEXT_TOP2 + 10'd16);
    wire text_region = line1_region | line2_region;

    wire [10:0] text_relative_x = pixel_x - TEXT_LEFT;
    wire [4:0]  text_char_index = text_relative_x[8:4];
    wire [3:0]  text_glyph_x    = text_relative_x[3:0];
    wire [3:0]  text_row        = line2_region ? (pixel_y - TEXT_TOP2)
                                              : (pixel_y - TEXT_TOP);

    // ---- 第 ci 个字符（"X:nnnn Y:nnnn W:nnnn H:nnnn" 的 27 格）----
    function [7:0] field_char;
        input [4:0]  ci;
        input [11:0] vx, vy, vw, vh;
        reg   [7:0]  ch;
        reg   [11:0] val;
        reg   [1:0]  place;
        reg          isdec;
        begin
            ch    = 8'h20;
            val   = 12'd0;
            place = 2'd0;
            isdec = 1'b0;
            case (ci)
                5'd0:  ch = "X";
                5'd1:  ch = ":";
                5'd2, 5'd3, 5'd4, 5'd5:  begin isdec = 1'b1; val = vx; place = ci - 5'd2;  end
                5'd6:  ch = " ";
                5'd7:  ch = "Y";
                5'd8:  ch = ":";
                5'd9, 5'd10, 5'd11, 5'd12: begin isdec = 1'b1; val = vy; place = ci - 5'd9;  end
                5'd13: ch = " ";
                5'd14: ch = "W";
                5'd15: ch = ":";
                5'd16, 5'd17, 5'd18, 5'd19: begin isdec = 1'b1; val = vw; place = ci - 5'd16; end
                5'd20: ch = " ";
                5'd21: ch = "H";
                5'd22: ch = ":";
                5'd23, 5'd24, 5'd25, 5'd26: begin isdec = 1'b1; val = vh; place = ci - 5'd23; end
                default: ch = 8'h20;
            endcase
            if (isdec) begin
                case (place)
                    2'd0: ch = ((val / 12'd1000) % 12'd10) + 8'd48;
                    2'd1: ch = ((val / 12'd100)  % 12'd10) + 8'd48;
                    2'd2: ch = ((val / 12'd10)   % 12'd10) + 8'd48;
                    2'd3: ch = ( val % 12'd10)            + 8'd48;
                endcase
            end
            field_char = ch;
        end
    endfunction

    // ⚠ 只用**一套**数字产生逻辑：行别只影响喂进去的 4 个 12 位值。
    //   （先前版本调了两次 field_char，等于两套 /1000、/100、/10 常数除法器，
    //     白白多出几百个 LUT，把本来就在 78% 利用率、控制集很紧的布局顶崩了。）
    wire [11:0] v_x = line2_region ? raw_x : display_x;
    wire [11:0] v_y = line2_region ? raw_y : display_y;
    wire [11:0] v_w = line2_region ? raw_w : display_w;
    wire [11:0] v_h = line2_region ? raw_h : display_h;

    wire [7:0] text_char = field_char(text_char_index, v_x, v_y, v_w, v_h);

    wire [15:0] text_glyph_row;
    osd_char_lib16 u_coordinate_font (
        .I_char     (text_char),
        .I_row      (text_row),
        .O_row_bits (text_glyph_row)
    );
    wire text_pixel_on = text_glyph_row[15 - text_glyph_x];

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_tvalid <= 1'b0;
            O_tuser  <= 1'b0;
            O_tlast  <= 1'b0;
            O_tdata  <= 24'd0;
        end else begin
            O_tvalid <= I_tvalid;
            O_tuser  <= I_tuser;
            O_tlast  <= I_tlast;
            if (I_tvalid) begin
                if (text_region)
                    O_tdata <= text_pixel_on ? 24'hFFFFFF : 24'h000000;
                else if (hit_border)
                    O_tdata <= BOX_COLOR;
                else
                    O_tdata <= I_tdata;
            end else begin
                O_tdata <= 24'd0;
            end
        end
    end

endmodule
