`timescale 1ns / 1ps
//=============================================================================
// tb_rx_result_parser.v - self-checking test for rx_result_parser
//-----------------------------------------------------------------------------
//   Covers the three result formats the sender can use, header-anchored framing
//   (including a deliberately wrong / missing rx_len, which is what broke the
//   length-whitelisted version on board A), embedded AA 55 inside the board-B
//   diagnostics, and rejection of valid=0 / score<615 / missing terminator.
//=============================================================================
module tb_rx_result_parser;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg [7:0] rx_d = 8'd0;
    reg rx_v = 1'b0;
    reg [15:0] rx_len = 16'd0;
    wire res_valid;
    wire [7:0] x1, y1, w, h;
    wire [15:0] score;
    wire saw_aa;
    integer accepted = 0;
    integer pulses_in_packet;

    always #5 clk = ~clk;
    always @(negedge clk) if (!rst && res_valid) accepted <= accepted + 1;

    rx_result_parser dut (
        .clk(clk), .rst(rst), .rx_d(rx_d), .rx_v(rx_v), .rx_len(rx_len),
        .res_valid(res_valid), .x1(x1), .y1(y1), .w(w), .h(h),
        .score(score), .saw_aa(saw_aa)
    );

    task send_byte;
        input [7:0] value;
        input add_gap;
        begin
            @(negedge clk);
            rx_d = value;
            rx_v = 1'b1;
            @(posedge clk); #1;
            if (add_gap) begin
                @(negedge clk); rx_v = 1'b0;
                @(posedge clk); #1;
            end
        end
    endtask

    task start_packet;
        input [15:0] length;
        input [7:0] first_byte;
        input add_gap;
        begin
            @(negedge clk);
            rx_len = length;
            rx_d = first_byte;
            rx_v = 1'b1;
            @(posedge clk); #1;
            if (add_gap) begin
                @(negedge clk); rx_v = 1'b0;
                @(posedge clk); #1;
            end
        end
    endtask

    // 10-byte legacy format: terminator at offset 9.
    task send_legacy10;
        input valid_bit;
        input [7:0] fx, fy, fw, fh;
        input [15:0] confidence;
        input [7:0] ending;
        input [15:0] declared_len;   // may deliberately be wrong
        input add_gaps;
        begin
            start_packet(declared_len, 8'hAA, add_gaps);
            send_byte(8'h55, add_gaps);
            send_byte(valid_bit ? 8'h01 : 8'h00, add_gaps);
            send_byte(fx, add_gaps);
            send_byte(fy, add_gaps);
            send_byte(fw, add_gaps);
            send_byte(fh, add_gaps);
            send_byte(confidence[15:8], add_gaps);
            send_byte(confidence[7:0], add_gaps);
            send_byte(ending, 1'b0);
        end
    endtask

    // 14-byte board-B debug build: [9] = 0x0D (or 0x0D at the end).
    task send_debug14;
        input [7:0] fx, fy, fw, fh;
        input [15:0] confidence;
        input [7:0] byte9;           // 0x0D -> terminator at offset 9
        input [7:0] byte13;          // 0x0D -> terminator at offset 13
        input [15:0] declared_len;
        begin
            start_packet(declared_len, 8'hAA, 1'b0);
            send_byte(8'h55, 1'b0);
            send_byte(8'h01, 1'b0);
            send_byte(fx, 1'b0); send_byte(fy, 1'b0);
            send_byte(fw, 1'b0); send_byte(fh, 1'b0);
            send_byte(confidence[15:8], 1'b0);
            send_byte(confidence[7:0], 1'b0);
            send_byte(byte9, 1'b0);
            send_byte(8'h11, 1'b0); send_byte(8'h22, 1'b0); send_byte(8'h33, 1'b0);
            send_byte(byte13, 1'b0);
        end
    endtask

    // 149-byte board-B packet.
    task send_board_b;
        input valid_bit;
        input [7:0] fx, fy, fw, fh;
        input [15:0] confidence;
        input [7:0] pix_r;
        input [7:0] ending;
        input [15:0] declared_len;   // may deliberately be wrong
        input add_gaps;
        input embed_sync;
        input expect_before_end;     // 1 when pix_r == 0x0D commits at offset 9
        input [7:0] expect_x, expect_y, expect_w, expect_h;
        integer i;
        reg [7:0] value;
        begin
            start_packet(declared_len, 8'hAA, add_gaps);
            pulses_in_packet = 0;
            for (i = 1; i < 149; i = i + 1) begin
                case (i)
                    1: value = 8'h55;
                    2: value = valid_bit ? 8'h01 : 8'h00;
                    3: value = fx;
                    4: value = fy;
                    5: value = fw;
                    6: value = fh;
                    7: value = confidence[15:8];
                    8: value = confidence[7:0];
                    9: value = pix_r;
                    148: value = ending;
                    default: begin
                        if (embed_sync && i == 40)
                            value = 8'hAA;
                        else if (embed_sync && i == 41)
                            value = 8'h55;
                        else
                            value = i[7:0] ^ 8'h5A;
                    end
                endcase
                send_byte(value, add_gaps && (i != 9) && (i != 148));
                if (res_valid)
                    pulses_in_packet = pulses_in_packet + 1;
                if (!expect_before_end && (i < 148) && res_valid)
                    $fatal(1, "149-byte packet committed before offset 148 (at %0d)", i);
            end
            if (expect_before_end && (pulses_in_packet != 1))
                $fatal(1, "pixR==0D should produce exactly one pulse at offset 9, got %0d",
                       pulses_in_packet);
        end
    endtask

    task wait_settle;
        begin
            @(negedge clk); rx_v = 1'b0;
            @(posedge clk); #1;
        end
    endtask

    task check_held;
        input [7:0] fx, fy, fw, fh;
        input [15:0] confidence;
        input integer expected_pulses;
        begin
            if (res_valid || x1 !== fx || y1 !== fy || w !== fw || h !== fh ||
                score !== confidence || accepted != expected_pulses)
                $fatal(1, "Rejected packet changed the latched result or pulse count");
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst = 1'b0;

        // ---- noise must not produce a result -------------------------------
        start_packet(16'd14, 8'hA5, 1'b0);
        send_byte(8'h55, 1'b0); send_byte(8'hAA, 1'b0); send_byte(8'h54, 1'b0);
        repeat (10) send_byte(8'h33, 1'b0);
        wait_settle;
        check_held(8'd0, 8'd0, 8'd0, 8'd0, 16'd0, 0);

        // ---- 10-byte legacy, gaps, score exactly at MIN_SCORE --------------
        send_legacy10(1'b1, 8'd44, 8'd20, 8'd40, 8'd32, 16'd615, 8'h0D, 16'd10, 1'b1);
        wait_settle;
        if (accepted != 1 || x1 != 44 || y1 != 20 || w != 40 || h != 32 || score != 615)
            $fatal(1, "10-byte legacy frame at threshold was not accepted once");

        // ---- board B 149-byte, pixR != 0D, embedded AA55 --------------------
        send_board_b(1'b1, 8'd17, 8'd18, 8'd19, 8'd20, 16'd900, 8'h23, 8'h0D,
                     16'd149, 1'b1, 1'b1, 1'b0, 8'd17, 8'd18, 8'd19, 8'd20);
        wait_settle;
        if (pulses_in_packet != 1 || accepted != 2 || x1 != 17 || y1 != 18 ||
            w != 19 || h != 20 || score != 900)
            $fatal(1, "board-B 149-byte packet did not commit once at offset 148");

        // ---- THE REGRESSION: rx_len that does not match the real payload ---
        //   The length-whitelisted version dropped all of these, so no result
        //   ever reached the OSD box.
        send_board_b(1'b1, 8'd21, 8'd22, 8'd23, 8'd24, 16'd700, 8'h24, 8'h0D,
                     16'd157, 1'b0, 1'b1, 1'b0, 8'd21, 8'd22, 8'd23, 8'd24);
        wait_settle;
        if (accepted != 3 || x1 != 21 || y1 != 22 || w != 23 || h != 24)
            $fatal(1, "rx_len=157 (header inclusive) broke the 149-byte parse");

        send_board_b(1'b1, 8'd25, 8'd26, 8'd27, 8'd28, 16'd800, 8'h25, 8'h0D,
                     16'd0, 1'b0, 1'b1, 1'b0, 8'd25, 8'd26, 8'd27, 8'd28);
        wait_settle;
        if (accepted != 4 || x1 != 25)
            $fatal(1, "rx_len=0 broke the 149-byte parse");

        // ---- 14-byte debug build: terminator at offset 9 and at 13 ---------
        send_debug14(8'd5, 8'd6, 8'd7, 8'd8, 16'd900, 8'h0D, 8'h44, 16'd14);
        wait_settle;
        if (accepted != 5 || x1 != 5 || w != 7)
            $fatal(1, "14-byte debug frame with 0D at offset 9 was rejected");
        send_debug14(8'd9, 8'd10, 8'd11, 8'd12, 16'd950, 8'h11, 8'h0D, 16'd14);
        wait_settle;
        if (accepted != 6 || x1 != 9 || h != 12)
            $fatal(1, "14-byte debug frame with 0D at offset 13 was rejected");

        // ---- rejections keep the previous result --------------------------
        send_legacy10(1'b0, 8'd1, 8'd2, 8'd3, 8'd4, 16'd900, 8'h0D, 16'd10, 1'b0);
        wait_settle;
        check_held(8'd9, 8'd10, 8'd11, 8'd12, 16'd950, 6);

        send_legacy10(1'b1, 8'd5, 8'd6, 8'd7, 8'd8, 16'd614, 8'h0D, 16'd10, 1'b0);
        wait_settle;
        check_held(8'd9, 8'd10, 8'd11, 8'd12, 16'd950, 6);

        send_legacy10(1'b1, 8'd9, 8'd10, 8'd11, 8'd12, 16'd700, 8'h00, 16'd10, 1'b0);
        wait_settle;
        check_held(8'd9, 8'd10, 8'd11, 8'd12, 16'd950, 6);

        send_board_b(1'b0, 8'd1, 8'd2, 8'd3, 8'd4, 16'd900, 8'h26, 8'h0D,
                     16'd149, 1'b0, 1'b1, 1'b0, 8'd1, 8'd2, 8'd3, 8'd4);
        wait_settle;
        check_held(8'd9, 8'd10, 8'd11, 8'd12, 16'd950, 6);

        send_board_b(1'b1, 8'd5, 8'd6, 8'd7, 8'd8, 16'd614, 8'h27, 8'h0D,
                     16'd149, 1'b0, 1'b1, 1'b0, 8'd5, 8'd6, 8'd7, 8'd8);
        wait_settle;
        check_held(8'd9, 8'd10, 8'd11, 8'd12, 16'd950, 6);

        send_board_b(1'b1, 8'd9, 8'd10, 8'd11, 8'd12, 16'd700, 8'h28, 8'h00,
                     16'd149, 1'b0, 1'b1, 1'b0, 8'd9, 8'd10, 8'd11, 8'd12);
        wait_settle;
        check_held(8'd9, 8'd10, 8'd11, 8'd12, 16'd950, 6);

        // ---- pixR happens to equal 0x0D: one pulse, at offset 9 ------------
        send_board_b(1'b1, 8'd31, 8'd32, 8'd33, 8'd34, 16'd1000, 8'h0D, 8'h0D,
                     16'd149, 1'b0, 1'b1, 1'b1, 8'd31, 8'd32, 8'd33, 8'd34);
        wait_settle;
        if (accepted != 7 || x1 != 31 || y1 != 32 || w != 33 || h != 34 || score != 1000)
            $fatal(1, "pixR==0D did not commit exactly once");

        // ---- back-to-back datagrams ---------------------------------------
        send_legacy10(1'b1, 8'd41, 8'd42, 8'd43, 8'd44, 16'd700, 8'h0D, 16'd10, 1'b0);
        send_board_b(1'b1, 8'd51, 8'd52, 8'd53, 8'd54, 16'd1000, 8'h42, 8'h0D,
                     16'd149, 1'b0, 1'b1, 1'b0, 8'd51, 8'd52, 8'd53, 8'd54);
        wait_settle;
        if (accepted != 9 || x1 != 51 || y1 != 52 || w != 53 || h != 54)
            $fatal(1, "back-to-back datagrams were not independently parsed");

        $display("PASS: 10/14/149-byte formats, rx_len-independence, embedded AA55, rejections, single pulse");
        $finish;
    end
endmodule
