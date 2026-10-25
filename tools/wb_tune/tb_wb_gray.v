//=============================================================================
// tb_wb_gray.v -- self-checking testbench for the "发灰" fix
//
// DUT : user_source/hdl_source/awb.v      (real RTL, parameter PEDESTAL=12)
//       user_source/hdl_source/gamma_lut.v (real RTL, BLK_G=0)
//
// It plays one small frame over and over (8 pixels + 200 idle cycles), which is
// exactly the "frame + vblank" pattern awb.v needs: the 128-cycle idle counter
// fires vblank_pulse once per frame, the divider runs G/R then G/B, and the
// 1/16 IIR settles.  After the gain loop has converged the last frame is dumped
// to dut_out.hex, which compare.py diffs against the Python twin.
//
// Checks performed in-block:
//   1. a sensor-black pixel (12,12,12) must leave the chain as (0,0,0)
//   2. every one of the 8 pixels must match the expected table
//=============================================================================
`timescale 1ns / 1ps

module tb_wb_gray;

    localparam NPIX   = 32;     // words per frame (must match vectors/stim.hex)
    localparam IDLE   = 200;    // idle cycles between frames (>128, <255)
    localparam NFRAME = 120;    // frames to run (IIR needs ~20 to settle)

    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;

    reg  [95:0] tdata = 0;
    reg         tvalid = 0;
    reg         tuser = 0;
    reg         tlast = 0;

    wire [95:0] awb_data;
    wire        awb_valid, awb_user, awb_last;
    wire        awb_tready;        // awb's I_tready is an OUTPUT (drives upstream)

    wire [7:0] g_r, g_g, g_b;      // gamma output of pixel 0 of each word

    reg [23:0] stim     [0:NPIX-1];
    reg [23:0] expected [0:NPIX-1];
    reg [23:0] captured [0:NPIX-1];
    integer i, f, fd, errs;

    //-------------------------------------------------------------------------
    // DUT chain: awb -> gamma_lut (the whole user-visible fix)
    //-------------------------------------------------------------------------
    awb #(
        .IMG_HEIGHT (720),
        .IMG_WIDTH  (1280),
        .PEDESTAL   (8'd12)          // <-- the knob under test
    ) u_awb (
        .I_clk   (clk),
        .I_rst_n (rst_n),
        .I_tlast (tlast),
        .I_tuser (tuser),
        .I_tdata (tdata),
        .I_tvalid(tvalid),
        .I_tready(awb_tready),
        .O_tlast (awb_last),
        .O_tuser (awb_user),
        .O_tdata (awb_data),
        .O_tvalid(awb_valid),
        .O_tready(1'b1)
    );

    gamma_lut #(
        .BLK_G (8'd0)                // <-- black level already removed upstream
    ) u_gamma (
        .I_r (awb_data[16+:8]),
        .I_g (awb_data[ 8+:8]),
        .I_b (awb_data[ 0+:8]),
        .O_r (g_r),
        .O_g (g_g),
        .O_b (g_b)
    );

    //-------------------------------------------------------------------------
    // stimulus
    //-------------------------------------------------------------------------
    initial begin
        $readmemh("vectors/stim.hex", stim);
        $readmemh("vectors/expected.hex", expected);
        errs = 0;
    end

    // one "frame" = NPIX valid words (each word = 4 pixels, we only vary pixel 0)
    task play_frame;
        integer k;
        begin
            for (k = 0; k < NPIX; k = k + 1) begin
                @(negedge clk);
                tdata  = {72'd0, stim[k]};      // pixels 1..3 = 0, pixel 0 = stim[k]
                tvalid = 1'b1;
                tuser  = (k == 0);
                tlast  = (k == NPIX-1);
            end
            @(negedge clk);
            tvalid = 1'b0; tuser = 1'b0; tlast = 1'b0; tdata = 96'd0;
            // idle long enough for vblank_pulse (fires at counter == 128)
            repeat (IDLE) @(negedge clk);
        end
    endtask

    // capture the *last* frame's gamma outputs
    always @(posedge clk) begin
        if (rst_n && f == NFRAME-1 && awb_valid) begin
            // awb output words are replayed in order; pixel 0 of word k
            captured[i % NPIX] <= {g_r, g_g, g_b};
            i <= i + 1;
        end
    end

    initial begin
        i = 0; f = 0;
        rst_n = 0;
        repeat (20) @(negedge clk);
        rst_n = 1;
        repeat (10) @(negedge clk);

        for (f = 0; f < NFRAME; f = f + 1) begin
            play_frame;
        end
        repeat (100) @(negedge clk);

        // ---- report / self-check -------------------------------------
        fd = $fopen("dut_out.hex", "w");
        for (i = 0; i < NPIX; i = i + 1) $fdisplay(fd, "%06x", captured[i]);
        $fclose(fd);

        $display("");
        $display("  idx   input      expected   dut        verdict");
        for (i = 0; i < NPIX; i = i + 1) begin
            if (captured[i] === expected[i]) begin
                $display("   %0d   %06x    %06x     %06x     OK", i, stim[i], expected[i], captured[i]);
            end else begin
                $display("   %0d   %06x    %06x     %06x     *** MISMATCH ***", i, stim[i], expected[i], captured[i]);
                errs = errs + 1;
            end
        end

        // hard requirement of the fix
        if (captured[0] !== 24'h000000) begin
            $display("  FAIL: sensor black (12,12,12) came out %06x, expected 000000", captured[0]);
            errs = errs + 1;
        end else begin
            $display("  OK  : sensor black (12,12,12) -> (0,0,0)   [the grey veil is gone]");
        end

        if (errs == 0) $display("\n*** TB PASS ***\n");
        else           $display("\n*** TB FAIL: %0d mismatches ***\n", errs);
        $finish;
    end

    initial begin
        #20_000_000;
        $display("*** TB TIMEOUT ***");
        $finish;
    end

endmodule
