`timescale 1ns / 1ps

module tb_frame_delay_tracker;
    reg ddr_clk = 1'b0;
    reg csi_clk = 1'b0;
    reg pixel_clk = 1'b0;
    reg ddr_rst_n = 1'b0;
    reg csi_rst_n = 1'b0;
    reg pixel_rst_n = 1'b0;
    reg csi_frame_start = 1'b0;
    reg write_frame_start = 1'b0;
    reg [1:0] write_page = 2'd0;
    reg display_frame_start = 1'b0;
    reg [1:0] display_page = 2'd0;

    wire delay_valid;
    wire [3:0] delay_frames;
    wire [9:0] delay_ms;
    wire osd_tuser, osd_tlast, osd_tvalid;
    wire [23:0] osd_tdata;
    reg in_tuser = 1'b0;
    reg in_tlast = 1'b0;
    reg in_tvalid = 1'b0;
    reg [23:0] in_tdata = 24'h123456;

    reg [31:0] test_frame_seq = 32'd0;
    reg [31:0] last_capture_ms = 32'd0;
    reg [31:0] last_capture_seq = 32'd0;
    reg page_expected_valid [0:3];
    reg [31:0] page_expected_ms [0:3];
    reg [31:0] page_expected_seq [0:3];
    reg [31:0] now_ms;
    reg [31:0] frame_delta;
    reg [31:0] ms_delta;
    reg [3:0] expected_frames;
    reg [9:0] expected_ms;
    integer i;

    always #5 ddr_clk = ~ddr_clk;
    always #7 csi_clk = ~csi_clk;
    always #3.333 pixel_clk = ~pixel_clk;

    frame_delay_tracker #(
        .DDR_CLK_HZ(20000)
    ) dut (
        .I_ddr_clk(ddr_clk), .I_ddr_rst_n(ddr_rst_n),
        .I_csi_clk(csi_clk), .I_csi_rst_n(csi_rst_n),
        .I_csi_frame_start(csi_frame_start),
        .I_write_frame_start(write_frame_start), .I_write_page(write_page),
        .I_display_frame_start(display_frame_start), .I_display_page(display_page),
        .I_pixel_clk(pixel_clk), .I_pixel_rst_n(pixel_rst_n),
        .O_delay_valid(delay_valid), .O_delay_frames(delay_frames), .O_delay_ms(delay_ms)
    );

    delay_osd #(
        .IMG_WIDTH(1280), .IMG_HEIGHT(720)
    ) u_delay_osd (
        .I_clk(pixel_clk), .I_rst_n(pixel_rst_n),
        .I_delay_valid(delay_valid), .I_delay_frames(delay_frames), .I_delay_ms(delay_ms),
        .I_tuser(in_tuser), .I_tlast(in_tlast), .I_tvalid(in_tvalid), .I_tdata(in_tdata),
        .O_tuser(osd_tuser), .O_tlast(osd_tlast), .O_tvalid(osd_tvalid), .O_tdata(osd_tdata)
    );

    task pulse_capture;
        begin
            @(negedge csi_clk);
            csi_frame_start = 1'b1;
            @(negedge csi_clk);
            csi_frame_start = 1'b0;
            @(negedge ddr_clk);
            while (dut.capture_event !== 1'b1)
                @(negedge ddr_clk);
            last_capture_ms = dut.ms_counter + dut.ms_tick;
            last_capture_seq = test_frame_seq + 32'd1;
            @(posedge ddr_clk);
            #0.1;
            test_frame_seq = last_capture_seq;
            repeat (2) @(posedge ddr_clk);
        end
    endtask

    task write_page_event;
        input [1:0] page;
        input valid_tag;
        begin
            @(negedge ddr_clk);
            write_page = page;
            write_frame_start = 1'b1;
            @(posedge ddr_clk);
            #0.1;
            write_frame_start = 1'b0;
            if (valid_tag) begin
                page_expected_valid[page] = 1'b1;
                page_expected_ms[page] = last_capture_ms;
                page_expected_seq[page] = last_capture_seq;
            end else begin
                page_expected_valid[page] = 1'b0;
            end
            repeat (2) @(posedge ddr_clk);
        end
    endtask

    task capture_and_write;
        input [1:0] page;
        begin
            pulse_capture;
            write_page_event(page, 1'b1);
            if (dut.page_valid[page] !== 1'b1 ||
                dut.page_capture_ms[page] !== last_capture_ms ||
                dut.page_frame_seq[page] !== last_capture_seq)
                $fatal(1, "write page %0d did not receive its CSI timestamp/sequence", page);
        end
    endtask

    task advance_ms;
        input integer count;
        reg [31:0] start_ms;
        begin
            start_ms = dut.ms_counter;
            while ((dut.ms_counter - start_ms) < count)
                @(posedge ddr_clk);
            #0.1;
        end
    endtask

    task check_display;
        input [1:0] page;
        input expected_valid;
        begin
            now_ms = dut.ms_counter + dut.ms_tick;
            if (expected_valid) begin
                frame_delta = test_frame_seq - page_expected_seq[page];
                ms_delta = now_ms - page_expected_ms[page];
                expected_frames = (frame_delta > 9) ? 4'd9 : frame_delta[3:0];
                expected_ms = (ms_delta > 999) ? 10'd999 : ms_delta[9:0];
            end else begin
                expected_frames = 4'd0;
                expected_ms = 10'd0;
            end
            @(negedge ddr_clk);
            display_page = page;
            display_frame_start = 1'b1;
            @(posedge ddr_clk);
            #0.1;
            display_frame_start = 1'b0;
            repeat (8) @(posedge pixel_clk);
            #0.1;
            if (delay_valid !== expected_valid || delay_frames !== expected_frames || delay_ms !== expected_ms)
                $fatal(1, "page %0d display mismatch: valid=%b frames=%0d ms=%0d expected=%b/%0d/%0d",
                       page, delay_valid, delay_frames, delay_ms,
                       expected_valid, expected_frames, expected_ms);
        end
    endtask

    task check_osd_digit;
        input integer x;
        input integer y;
        input [7:0] expected_char;
        begin
            @(negedge pixel_clk);
            u_delay_osd.x_r1 = x;
            u_delay_osd.y_r1 = y;
            #0.1;
            if (!u_delay_osd.dly_on || u_delay_osd.dly_char !== expected_char)
                $fatal(1, "OSD digit mismatch at (%0d,%0d): on=%b char=%h expected=%h",
                       x, y, u_delay_osd.dly_on, u_delay_osd.dly_char, expected_char);
        end
    endtask

    task check_osd_blank;
        input integer x;
        input integer y;
        begin
            @(negedge pixel_clk);
            u_delay_osd.x_r1 = x;
            u_delay_osd.y_r1 = y;
            #0.1;
            if (u_delay_osd.dly_on)
                $fatal(1, "OSD displayed a delay number before the selected page was valid");
        end
    endtask

    integer j;
    initial begin
        for (i = 0; i < 4; i = i + 1) begin
            page_expected_valid[i] = 1'b0;
            page_expected_ms[i] = 32'd0;
            page_expected_seq[i] = 32'd0;
        end

        repeat (4) @(negedge ddr_clk);
        ddr_rst_n = 1'b1;
        csi_rst_n = 1'b1;
        pixel_rst_n = 1'b1;
        repeat (4) @(posedge ddr_clk);

        check_display(2'd0, 1'b0);
        check_osd_blank(110, 196);
        check_osd_blank(110, 216);

        capture_and_write(2'd0);
        advance_ms(4);
        capture_and_write(2'd1);
        advance_ms(3);
        capture_and_write(2'd2);
        advance_ms(2);
        capture_and_write(2'd3);
        check_display(2'd2, 1'b1);
        check_display(2'd0, 1'b1);

        // Reusing one physical DDR page replaces only that page's label.
        advance_ms(5);
        capture_and_write(2'd1);
        check_display(2'd1, 1'b1);
        advance_ms(20);
        check_display(2'd1, 1'b1);

        // A display read colliding with a write to the same page is ambiguous.
        @(negedge ddr_clk);
        write_page = 2'd1;
        display_page = 2'd1;
        write_frame_start = 1'b1;
        display_frame_start = 1'b1;
        @(posedge ddr_clk);
        #0.1;
        write_frame_start = 1'b0;
        display_frame_start = 1'b0;
        page_expected_valid[1] = 1'b0;
        repeat (8) @(posedge pixel_clk);
        #0.1;
        if (delay_valid !== 1'b0)
            $fatal(1, "same-page simultaneous DDR read/write was reported as valid");

        // A write with no matching CSI event invalidates just the selected page.
        write_page_event(2'd3, 1'b0);
        check_display(2'd3, 1'b0);

        // More CSI starts than ISP/DDR write starts are discarded as a mismatch.
        pulse_capture;
        pulse_capture;
        write_page_event(2'd2, 1'b0);
        check_display(2'd2, 1'b0);
        capture_and_write(2'd2);
        check_display(2'd2, 1'b1);

        // Exercise a CSI start coincident with write and display events.
        @(negedge csi_clk);
        csi_frame_start = 1'b1;
        @(negedge csi_clk);
        csi_frame_start = 1'b0;
        @(negedge ddr_clk);
        while (dut.capture_event !== 1'b1)
            @(negedge ddr_clk);
        last_capture_ms = dut.ms_counter + dut.ms_tick;
        last_capture_seq = test_frame_seq + 32'd1;
        write_page = 2'd3;
        display_page = 2'd2;
        write_frame_start = 1'b1;
        display_frame_start = 1'b1;
        @(posedge ddr_clk);
        #0.1;
        write_frame_start = 1'b0;
        display_frame_start = 1'b0;
        test_frame_seq = last_capture_seq;
        page_expected_valid[3] = 1'b1;
        page_expected_ms[3] = last_capture_ms;
        page_expected_seq[3] = last_capture_seq;
        repeat (8) @(posedge pixel_clk);
        #0.1;
        frame_delta = test_frame_seq - page_expected_seq[2];
        now_ms = dut.ms_counter + dut.ms_tick;
        ms_delta = now_ms - page_expected_ms[2];
        expected_frames = (frame_delta > 9) ? 4'd9 : frame_delta[3:0];
        expected_ms = (ms_delta > 999) ? 10'd999 : ms_delta[9:0];
        if (delay_valid !== 1'b1 || delay_frames !== expected_frames || delay_ms !== expected_ms)
            $fatal(1, "simultaneous capture/write/display used the wrong display-page metadata");

        // Sequence and millisecond differences must remain correct across wrap.
        @(negedge ddr_clk);
        dut.ms_counter = 32'hffff_fffc;
        dut.ms_div_cnt = 32'd0;
        dut.frame_seq = 32'hffff_fffe;
        test_frame_seq = 32'hffff_fffe;
        capture_and_write(2'd0);
        advance_ms(5);
        capture_and_write(2'd1);
        check_display(2'd0, 1'b1);

        // Both display fields saturate at their documented OSD widths.
        @(negedge ddr_clk);
        test_frame_seq = page_expected_seq[0] + 32'd12;
        dut.frame_seq = test_frame_seq;
        dut.ms_counter = page_expected_ms[0] + 32'd1200;
        dut.ms_div_cnt = 32'd0;
        check_display(2'd0, 1'b1);

        check_osd_digit(110, 196, 8'h39);
        check_osd_digit(110, 216, 8'h39);

        $display("PASS: physical-page frame age, millisecond age, pairing faults, wrap, saturation, and OSD CDC");
        $finish;
    end
endmodule
