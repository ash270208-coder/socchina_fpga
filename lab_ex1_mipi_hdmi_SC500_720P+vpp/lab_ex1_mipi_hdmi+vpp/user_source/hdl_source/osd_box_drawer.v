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
//=============================================================================
module osd_box_drawer #(
    parameter IN_WIDTH     = 1280,
    parameter IN_HEIGHT    = 720,
    parameter SCALE_FACTOR = 10,
    parameter LINE_THICK   = 3,
    parameter BOX_COLOR    = 24'h00FF00,
    parameter HOLD_FRAMES  = 15,
    parameter [7:0] MIN_WH = 8'd2,
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

    wire [12:0] clipped_x1 = (scaled_x >= SCREEN_W) ? SCREEN_W : {1'b0, scaled_x};
    wire [12:0] clipped_y1 = (scaled_y >= SCREEN_H) ? SCREEN_H : {1'b0, scaled_y};
    wire [12:0] clipped_x2 = (raw_x2 > SCREEN_W) ? SCREEN_W : raw_x2;
    wire [12:0] clipped_y2 = (raw_y2 > SCREEN_H) ? SCREEN_H : raw_y2;
    wire        clipped_box_nonempty = (clipped_x2 > clipped_x1) &&
                                       (clipped_y2 > clipped_y1);

    // A detection is usable only when it is neither degenerate (board B's
    // "no face this frame" report) nor entirely outside the visible screen.
    wire        detection_usable = (I_face_w >= MIN_WH) &&
                                   (I_face_h >= MIN_WH) &&
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
                box_x1     <= clipped_x1[10:0];
                box_y1     <= clipped_y1[9:0];
                box_x2     <= clipped_x2[10:0];
                box_y2     <= clipped_y2[9:0];
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

    // ---- 右上角 27 格读数的内容（见 READOUT_RAW_CELLS 参数说明）----
    //   模式 0：显示 box_x1/box_y1（框左上角，HDMI 像素坐标）和框宽高
    //   模式 1：显示网络原始格坐标
    wire [11:0] display_x = READOUT_RAW_CELLS ? {4'b0000, I_face_x} : {1'b0, box_x1};
    wire [11:0] display_y = READOUT_RAW_CELLS ? {4'b0000, I_face_y} : {2'b00, box_y1};
    wire [11:0] display_w = READOUT_RAW_CELLS ? {4'b0000, I_face_w}
                                              : ({1'b0, box_x2} - {1'b0, box_x1});
    wire [11:0] display_h = READOUT_RAW_CELLS ? {4'b0000, I_face_h}
                                              : ({2'b00, box_y2} - {2'b00, box_y1});

    wire text_region = box_enable &&
                       (pixel_x >= TEXT_LEFT) &&
                       (pixel_x < TEXT_LEFT + TEXT_WIDTH) &&
                       (pixel_y >= TEXT_TOP) &&
                       (pixel_y < TEXT_TOP + 10'd16);
    wire [10:0] text_relative_x = pixel_x - TEXT_LEFT;
    wire [4:0]  text_char_index = text_relative_x[8:4];
    wire [3:0]  text_row = pixel_y - TEXT_TOP;
    wire [3:0]  text_glyph_x = text_relative_x[3:0];

    reg [7:0] text_char;
    reg [11:0] decimal_value;
    reg [1:0] decimal_place;
    reg decimal_character;

    always @* begin
        text_char = 8'h20;
        decimal_value = 12'd0;
        decimal_place = 2'd0;
        decimal_character = 1'b0;
        case (text_char_index)
            5'd0: text_char = "X";
            5'd1: text_char = ":";
            5'd2, 5'd3, 5'd4, 5'd5: begin
                decimal_character = 1'b1;
                decimal_value = display_x;
                decimal_place = text_char_index - 5'd2;
            end
            5'd6: text_char = " ";
            5'd7: text_char = "Y";
            5'd8: text_char = ":";
            5'd9, 5'd10, 5'd11, 5'd12: begin
                decimal_character = 1'b1;
                decimal_value = display_y;
                decimal_place = text_char_index - 5'd9;
            end
            5'd13: text_char = " ";
            5'd14: text_char = "W";
            5'd15: text_char = ":";
            5'd16, 5'd17, 5'd18, 5'd19: begin
                decimal_character = 1'b1;
                decimal_value = display_w;
                decimal_place = text_char_index - 5'd16;
            end
            5'd20: text_char = " ";
            5'd21: text_char = "H";
            5'd22: text_char = ":";
            5'd23, 5'd24, 5'd25, 5'd26: begin
                decimal_character = 1'b1;
                decimal_value = display_h;
                decimal_place = text_char_index - 5'd23;
            end
            default: text_char = 8'h20;
        endcase

        if (decimal_character) begin
            case (decimal_place)
                2'd0: text_char = ((decimal_value / 12'd1000) % 12'd10) + 8'd48;
                2'd1: text_char = ((decimal_value / 12'd100)  % 12'd10) + 8'd48;
                2'd2: text_char = ((decimal_value / 12'd10)   % 12'd10) + 8'd48;
                2'd3: text_char = ( decimal_value % 12'd10) + 8'd48;
            endcase
        end
    end

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
