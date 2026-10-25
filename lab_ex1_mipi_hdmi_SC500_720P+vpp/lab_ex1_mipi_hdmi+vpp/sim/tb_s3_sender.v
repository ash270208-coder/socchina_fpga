`timescale 1ns / 1ps
//=============================================================================
// tb_s3_sender.v -- tx_frame_sender v1 (flashed at 19:25) vs v2 (fixed)
//
// Both DUTs run on the same udp_clk and see identical stimuli.
// The FIFO contents are driven manually (no producer FSM), so the two
// measurements below are unambiguous:
//
//  Test A  ack held low = ARP unresolved.
//          frame_start pulses.  Count tx_abort pulses and tx_request duty.
//          v1 (1ms timeout)  -> drops tx_request once per millisecond
//          v2 (holds request) -> never drops it
//
//  Test B  ack answers normally; the FIFO is deliberately starved:
//          it is topped up 1 byte every 4 udp_clk (which is still SLOWER than
//          the sender, forcing a mid-packet underrun), and the last byte we
//          wrote is remembered.  Any byte the sender emits that was NOT the
//          most recent written byte is a duplicate -> counted as bad.
//          v1 keeps advancing on an empty FIFO  -> many duplicated bytes
//          v2 freezes on an empty FIFO          -> 0 bad bytes
//=============================================================================
module tb_s3_sender;

    reg clk    = 1'b0;
    reg arst_n = 1'b0;
    always #4 clk = ~clk;
    wire reset = ~arst_n;

    //---------------------------------------------------------------- FIFO 1
    reg  [7:0]  mem1 [0:4095];
    reg  [12:0] wp1 = 13'd0, rp1 = 13'd0;
    reg  [7:0]  lastw1 = 8'h00;
    wire [7:0]  q1 = mem1[rp1[11:0]];
    wire [13:0] c1 = {1'b0,wp1} - {1'b0,rp1};
    //---------------------------------------------------------------- FIFO 2
    reg  [7:0]  mem2 [0:4095];
    reg  [12:0] wp2 = 13'd0, rp2 = 13'd0;
    reg  [7:0]  lastw2 = 8'h00;
    wire [7:0]  q2 = mem2[rp2[11:0]];
    wire [13:0] c2 = {1'b0,wp2} - {1'b0,rp2};
    wire        e2 = (wp2 == rp2);

    wire rd1, rd2;
    reg  fstart = 1'b0;
    reg  ack    = 1'b0;

    wire r1, v1, d1, a1, r2, v2, d2, a2;
    wire [7:0]  x1, x2;
    wire [15:0] l1, l2;

    tx_frame_sender_v1 u_v1 (
        .I_clk(clk), .I_rst(reset), .I_frame_start(fstart),
        .O_fifo_rd(rd1), .I_fifo_q(q1), .I_fifo_cnt(c1),
        .I_tx_ready(1'b1), .I_tx_ack(ack),
        .O_tx_request(r1), .O_tx_valid(v1), .O_tx_data(x1),
        .O_tx_length(l1), .O_busy(), .O_frame_done(d1), .O_tx_abort(a1)
    );
    tx_frame_sender u_v2 (
        .I_clk(clk), .I_rst(reset), .I_frame_start(fstart),
        .O_fifo_rd(rd2), .I_fifo_q(q2), .I_fifo_cnt(c2), .I_fifo_empty(e2),
        .I_tx_ready(1'b1), .I_tx_ack(ack),
        .O_tx_request(r2), .O_tx_valid(v2), .O_tx_data(x2),
        .O_tx_length(l2), .O_busy(), .O_frame_done(d2), .O_tx_abort(a2)
    );

    always @(posedge clk) if (rd1 && !(wp1 == rp1)) rp1 <= rp1 + 13'd1;
    always @(posedge clk) if (rd2 && !(wp2 == rp2)) rp2 <= rp2 + 13'd1;

    //--- counters -----------------------------------------------------------
    integer ab1=0, ab2=0, rq1=0, rq2=0, tc=0;
    integer bad1=0, bad2=0, img1=0, img2=0;
    integer sq1=0, sq2=0;

    always @(posedge clk) begin
        if (a1) ab1 = ab1 + 1;
        if (a2) ab2 = ab2 + 1;
        if (r1) rq1 = rq1 + 1;
        if (r2) rq2 = rq2 + 1;
        tc = tc + 1;

        // Test B checking: image bytes (seq>=2) must equal the most recent write
        if (v1) begin
            if (sq1 >= 2) begin
                if (x1 !== lastw1) bad1 = bad1 + 1;
                img1 = img1 + 1;
            end
            if (sq1 == l1 - 1) sq1 = 0; else sq1 = sq1 + 1;
        end
        if (v2) begin
            if (sq2 >= 2) begin
                if (x2 !== lastw2) bad2 = bad2 + 1;
                img2 = img2 + 1;
            end
            if (sq2 == l2 - 1) sq2 = 0; else sq2 = sq2 + 1;
        end
    end

    //--- stimuli ------------------------------------------------------------
    integer i, k;
    integer fs_period = 2500;     // frame_start period in clocks
    integer starve    = 0;        // 1 = starve the FIFOs (Test B)

    // frame_start generator
    integer fc = 0;
    always @(posedge clk) begin
        if (fc >= fs_period) fc <= 0; else fc <= fc + 1;
        fstart <= (fc == fs_period - 1) ? 1'b1 : 1'b0;
    end

    // starvation feeder: 1 byte every 4 clocks into both FIFOs
    integer sc = 0;
    always @(posedge clk) begin
        if (starve) begin
            if (sc >= 3) begin
                sc <= 0;
                if (c1 < 14'd4090) begin
                    mem1[wp1[11:0]] <= wp1[7:0];
                    lastw1 <= wp1[7:0];
                    wp1 <= wp1 + 13'd1;
                end
                if (c2 < 14'd4090) begin
                    mem2[wp2[11:0]] <= wp2[7:0];
                    lastw2 <= wp2[7:0];
                    wp2 <= wp2 + 13'd1;
                end
            end else sc <= sc + 1;
        end
    end

    initial begin
        $display("=== tb_s3_sender : v1 (flashed) vs v2 (fixed) ===");
        arst_n = 1'b0; ack = 1'b0; starve = 0;
        repeat (40) @(posedge clk);
        arst_n = 1'b1;

        // pre-fill both FIFOs past one packet
        for (i = 0; i < 1600; i = i + 1) begin
            mem1[i] = i[7:0]; lastw1 = i[7:0]; wp1 = wp1 + 13'd1;
            mem2[i] = i[7:0]; lastw2 = i[7:0]; wp2 = wp2 + 13'd1;
        end

        //================ Test A : ARP unresolved =================
        ab1=0; ab2=0; rq1=0; rq2=0; tc=0;
        $display("");
        $display("---- Test A: ack held low (ARP unresolved), 250000 clocks ----");
        repeat (250000) @(posedge clk);
        $display("  v1: tx_abort=%0d  tx_request duty=%0d%%", ab1, (rq1*100)/tc);
        $display("  v2: tx_abort=%0d  tx_request duty=%0d%%", ab2, (rq2*100)/tc);
        if (ab1 > 0)
            $display("  -> v1 drops tx_request every %0d clocks = %0d us",
                     tc/ab1, ((tc/ab1)*8)/1000);
        if (ab2 == 0)
            $display("  -> v2 never drops it (same as board B result_sender / official loopback)");

        //================ Test B : FIFO starvation =================
        arst_n = 1'b0;
        repeat (20) @(posedge clk);
        wp1=13'd0; rp1=13'd0; wp2=13'd0; rp2=13'd0;
        sq1=0; sq2=0; bad1=0; bad2=0; img1=0; img2=0;
        lastw1=8'h00; lastw2=8'h00;
        ack = 0; starve = 1;
        arst_n = 1'b1;

        $display("");
        $display("---- Test B: ack OK, FIFO starved (1 byte / 4 clocks) ----");
        repeat (300000) @(posedge clk);
        $display("  v1: img_bytes=%0d  duplicated/orphan bytes=%0d", img1, bad1);
        $display("  v2: img_bytes=%0d  duplicated/orphan bytes=%0d", img2, bad2);
        $display("  v1 FIFO_left=%0d  v2 FIFO_left=%0d", c1, c2);
        $display("");
        if (bad1 > 0 && bad2 == 0)
            $display("  RESULT: v1 duplicates bytes on underrun, v2 does not. FIX CONFIRMED.");
        $display("=== done ===");
        $finish;
    end

    initial begin
        #200_000_000;
        $display("!! TIMEOUT");
        $finish;
    end

endmodule
