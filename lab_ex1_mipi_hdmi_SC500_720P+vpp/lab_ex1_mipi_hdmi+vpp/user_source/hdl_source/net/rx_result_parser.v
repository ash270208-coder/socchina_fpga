`timescale 1ns / 1ps
//=============================================================================
// rx_result_parser.v - pull the face-box result packet out of the app_rx stream
//-----------------------------------------------------------------------------
// Board B (cnn_boardB/src/net/result_sender.v, tx_length = 149):
//   [0]  0xAA            header
//   [1]  0x55            header
//   [2]  valid          0x01 = this frame has a detection
//   [3]  x1             box left   / 128x72 detection space
//   [4]  y1             box top
//   [5]  w              box width
//   [6]  h              box height
//   [7]  score[15:8]
//   [8]  score[7:0]
//   [9]  pixR           NOT a terminator (the old 10-byte format puts 0x0D here)
//   [10..147]           diagnostics
//   [148] 0x0D          terminator
//
// Older formats kept for the PC-side test script and board-B debug builds:
//   10 byte: [0..8] identical, [9] = 0x0D
//   14 byte: [0..9] identical to the 10-byte one, [10..13] extra
//
// FRAMING - why this file does not gate on rx_len any more
// -------------------------------------------------------
// The previous version accepted a packet only when rx_len was exactly 10 or 149
// and counted to that declared length. On board A that meant nothing ever
// committed, so res_valid never pulsed, osd_box_drawer's box_enable stayed 0
// and neither the green box nor the X/Y/W/H readout appeared - even though the
// image path and the coordinate path were fine. The version before that (also
// length based) had failed on the board for the same reason.
//
// So framing now anchors on the AA 55 header and counts bytes from it, inside a
// fixed 149-byte window. rx_len is only a HINT for where the packet ends: if it
// looks plausible it is used to release the window early (so a 10-byte packet
// does not swallow the next 14 headers), otherwise the full window is used.
// A wrong or missing app_rx_data_length can no longer stop every result.
//
// COMMIT - still strictly validated
// -------------------------------------------------------
// A 0x0D terminator is accepted at offset 9 (10-byte), 13 (14-byte debug) or
// 148 (board B), and only together with valid == 1 and score >= MIN_SCORE.
// Exactly one pulse per header; the rest of the packet is skipped so the
// diagnostic bytes can never be mistaken for a new header.
//=============================================================================
module rx_result_parser(
    input  wire        clk,
    input  wire        rst,
    input  wire [7:0]  rx_d,
    input  wire        rx_v,        // byte valid; gaps do not advance the counter
    input  wire [15:0] rx_len,      // UDP payload length, used as a hint only
    output reg         res_valid,   // one-cycle pulse per accepted result
    output reg  [7:0]  x1,
    output reg  [7:0]  y1,
    output reg  [7:0]  w,
    output reg  [7:0]  h,
    output reg  [15:0] score,
    output reg         saw_aa       // diagnostic: latched after any 0xAA byte
);

    localparam [15:0] MIN_SCORE  = 16'd615;
    localparam [7:0]  IDX_LEGACY = 8'd9;    // 10-byte format terminator
    localparam [7:0]  IDX_DEBUG  = 8'd13;   // 14-byte debug build terminator
    localparam [7:0]  IDX_LAST   = 8'd148;  // board-B 149-byte terminator

    reg [7:0]  sr;          // previous byte, only updated on rx_v
    reg        armed;       // AA 55 seen, now counting from the header
    reg [7:0]  idx;         // index of rx_d while armed (0 = AA, 1 = 55)
    reg [7:0]  end_idx;     // index of this packet's last byte
    reg [7:0]  vld_byte;
    reg [7:0]  x1_latched, y1_latched, w_latched, h_latched;
    reg [7:0]  score_hi, score_lo;
    reg        committed;

     // 2026-10-23 FIX: ignore rx_len completely, always use the fixed 149-byte
    // window. Previously end_idx came from rx_len; if board A's
    // app_rx_data_length was ever anything other than 149 (10, 14, a stale
    // value, ...) the parser would hit at_end in the MIDDLE of the packet,
    // re-arm, and then scan the remaining image bytes as if they were a new
    // packet. Any AA 55 inside image data would re-lock it and latch pixel
    // values as x1/y1/w/h -- which shows up as a box with the right position
    // but an absurd size. With a fixed window the sequence is deterministic:
    // AA 55 -> latch bytes 2..8 -> commit at byte 148.
    wire [7:0]  hint_end      = IDX_LAST;

    wire        term_ok   = (rx_d == 8'h0D) && !committed &&
                            (vld_byte == 8'h01) &&
                            ({score_hi, score_lo} >= MIN_SCORE);
    wire        at_commit = (idx == IDX_LEGACY) || (idx == IDX_DEBUG) ||
                            (idx == end_idx);
    wire        at_end    = (idx == end_idx);

    always @(posedge clk) begin
        if (rst) begin
            sr           <= 8'd0;
            armed        <= 1'b0;
            idx          <= 8'd0;
            end_idx      <= IDX_LAST;
            vld_byte     <= 8'd0;
            x1_latched   <= 8'd0;
            y1_latched   <= 8'd0;
            w_latched    <= 8'd0;
            h_latched    <= 8'd0;
            score_hi     <= 8'd0;
            score_lo     <= 8'd0;
            committed    <= 1'b0;
            res_valid    <= 1'b0;
            saw_aa       <= 1'b0;
            x1           <= 8'd0;
            y1           <= 8'd0;
            w            <= 8'd0;
            h            <= 8'd0;
            score        <= 16'd0;
        end else begin
            res_valid <= 1'b0;

            if (rx_v) begin
                sr <= rx_d;
                if (rx_d == 8'hAA)
                    saw_aa <= 1'b1;

                if (!armed) begin
                    if ({sr, rx_d} == 16'hAA55) begin
                        // rx_d is offset 1 (the 0x55); the next byte to arrive is
                        // offset 2, so pre-load idx with 2 rather than 1.
                        armed     <= 1'b1;
                        idx       <= 8'd2;
                        end_idx   <= hint_end;
                        committed <= 1'b0;
                    end
                end else begin
                    case (idx)
                        8'd2: vld_byte  <= rx_d;
                        8'd3: x1_latched <= rx_d;
                        8'd4: y1_latched <= rx_d;
                        8'd5: w_latched  <= rx_d;
                        8'd6: h_latched  <= rx_d;
                        8'd7: score_hi   <= rx_d;
                        8'd8: score_lo   <= rx_d;
                        default: ;
                    endcase

                    if (at_commit && term_ok) begin
                        x1        <= x1_latched;
                        y1        <= y1_latched;
                        w         <= w_latched;
                        h         <= h_latched;
                        score     <= {score_hi, score_lo};
                        res_valid <= 1'b1;
                        committed <= 1'b1;
                    end

                    if (at_end) begin
                        armed <= 1'b0;
                    end else begin
                        idx <= idx + 8'd1;
                    end
                end
            end
        end
    end

endmodule
