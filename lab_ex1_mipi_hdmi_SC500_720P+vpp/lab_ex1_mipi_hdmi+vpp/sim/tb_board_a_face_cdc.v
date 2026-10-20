`timescale 1ns / 1ps

module tb_board_a_face_cdc;
    reg udp_clk = 1'b0;
    reg pclk = 1'b0;
    reg pclk_rst_n = 1'b0;
    reg reset_force = 1'b1;
    reg [7:0] rx_byte = 8'd0;
    reg rx_valid = 1'b0;
    reg [15:0] rx_length = 16'd0;
    wire face_valid;
    wire [7:0] face_x, face_y, face_w, face_h;
    integer pulse_count = 0;
    reg [7:0] captured_x, captured_y, captured_w, captured_h;
    integer timeout_cycles;

    always #4 udp_clk = ~udp_clk;
    always #6.667 pclk = ~pclk;

    board_a_net_wrapper dut (
        .I_pclk(pclk), .I_pclk_rst_n(pclk_rst_n),
        .O_face_valid(face_valid), .O_face_x(face_x), .O_face_y(face_y),
        .O_face_w(face_w), .O_face_h(face_h)
    );

    // Isolate the actual parser and CDC logic from unrelated PHY/MAC blocks.
    initial begin
        force dut.udp_clk = udp_clk;
        force dut.reset = reset_force;
        force dut.app_rx_data = rx_byte;
        force dut.app_rx_data_valid = rx_valid;
        force dut.app_rx_data_length = rx_length;
    end

    always @(posedge pclk) begin
        if (!pclk_rst_n) begin
            pulse_count <= 0;
            captured_x <= 0; captured_y <= 0; captured_w <= 0; captured_h <= 0;
        end else if (face_valid) begin
            pulse_count <= pulse_count + 1;
            captured_x <= face_x; captured_y <= face_y;
            captured_w <= face_w; captured_h <= face_h;
        end
    end

    task send_byte;
        input [7:0] value;
        input integer gap_cycles;
        begin
            @(negedge udp_clk);
            rx_byte = value; rx_valid = 1'b1;
            @(posedge udp_clk); #1;
            rx_valid = 1'b0;
            repeat (gap_cycles) @(posedge udp_clk);
        end
    endtask

    task send_result;
        input [7:0] fx, fy, fw, fh;
        input [15:0] confidence;
        input integer gap_cycles;
        integer i;
        begin
            rx_length = 16'd149;
            send_byte(8'hAA, gap_cycles); send_byte(8'h55, gap_cycles);
            send_byte(8'h01, gap_cycles); send_byte(fx, gap_cycles);
            send_byte(fy, gap_cycles); send_byte(fw, gap_cycles);
            send_byte(fh, gap_cycles); send_byte(confidence[15:8], gap_cycles);
            send_byte(confidence[7:0], gap_cycles); send_byte(8'h0D, gap_cycles); // pixR=0D
            for (i = 10; i < 148; i = i + 1) begin
                if (i == 40)
                    send_byte(8'hAA, gap_cycles);
                else if (i == 41)
                    send_byte(8'h55, gap_cycles);
                else
                    send_byte(i[7:0] ^ 8'h5A, gap_cycles);
            end
            send_byte(8'h0D, 0);
        end
    endtask

    task wait_for_one_pulse;
        input integer previous_count;
        input [7:0] expected_x, expected_y, expected_w, expected_h;
        begin
            timeout_cycles = 0;
            while (pulse_count == previous_count && timeout_cycles < 40) begin
                @(posedge pclk); #0.1;
                timeout_cycles = timeout_cycles + 1;
            end
            if (pulse_count != previous_count + 1 || captured_x !== expected_x ||
                captured_y !== expected_y || captured_w !== expected_w || captured_h !== expected_h)
                $fatal(1, "CDC pulse or coordinate bundle was lost/mixed");
            repeat (6) @(posedge pclk); #0.1;
            if (pulse_count != previous_count + 1)
                $fatal(1, "One UDP result generated more than one pixel-clock pulse");
        end
    endtask

    integer previous_count;
    initial begin
        repeat (4) @(posedge udp_clk);
        pclk_rst_n = 1'b1;
        repeat (2) @(posedge udp_clk);
        reset_force = 1'b0;
        repeat (4) @(posedge udp_clk);

        #2.3;
        previous_count = pulse_count;
        send_result(8'd44, 8'd20, 8'd40, 8'd32, 16'd615, 0);
        wait_for_one_pulse(previous_count, 8'd44, 8'd20, 8'd40, 8'd32);

        #3.7;
        previous_count = pulse_count;
        send_result(8'd17, 8'd18, 8'd19, 8'd20, 16'd900, 1);
        wait_for_one_pulse(previous_count, 8'd17, 8'd18, 8'd19, 8'd20);

        previous_count = pulse_count;
        rx_length = 16'd10;
        send_byte(8'hAA, 0); send_byte(8'h55, 0); send_byte(8'h01, 0);
        send_byte(8'd1, 0); send_byte(8'd2, 0); send_byte(8'd3, 0);
        send_byte(8'd4, 0); send_byte(8'h00, 0); send_byte(8'h10, 0); send_byte(8'h0D, 0);
        repeat (40) @(posedge pclk); #0.1;
        if (pulse_count != previous_count || face_x !== 8'd17 || face_y !== 8'd18 ||
            face_w !== 8'd19 || face_h !== 8'd20)
            $fatal(1, "Rejected low-score frame changed synchronized face coordinates");

        $display("PASS: board_a_net_wrapper parser-to-pixel CDC phase, bundle stability, and single-pulse behavior");
        $finish;
    end
endmodule
