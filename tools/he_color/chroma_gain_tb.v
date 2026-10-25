`timescale 1ns/1ps
//=============================================================================
// chroma_gain_tb.v -- 自检 testbench
//   期望值: out = clip(128 + ((c-128)*K) >> 8)   (算术右移)
//   覆盖: Cb/Cr 各扫 0..255, 以及 K=1.0x / 1.4x / 1.5x 三档
//=============================================================================
module chroma_gain_tb;

    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;

    reg  [7:0] i_cb, i_cr;
    reg        i_v;
    wire [7:0] o_cb_140, o_cr_140;
    wire [7:0] o_cb_100, o_cr_100;
    wire [7:0] o_cb_150, o_cr_150;

    chroma_gain #(.GAIN_Q8(9'd358)) dut_140 (
        .I_clk(clk), .I_rst_n(rst_n), .I_cb(i_cb), .I_cr(i_cr), .I_tvalid(i_v),
        .O_cb(o_cb_140), .O_cr(o_cr_140), .O_tvalid());

    chroma_gain #(.GAIN_Q8(9'd256)) dut_100 (
        .I_clk(clk), .I_rst_n(rst_n), .I_cb(i_cb), .I_cr(i_cr), .I_tvalid(i_v),
        .O_cb(o_cb_100), .O_cr(o_cr_100), .O_tvalid());

    chroma_gain #(.GAIN_Q8(9'd384)) dut_150 (
        .I_clk(clk), .I_rst_n(rst_n), .I_cb(i_cb), .I_cr(i_cr), .I_tvalid(i_v),
        .O_cb(o_cb_150), .O_cr(o_cr_150), .O_tvalid());

    integer err = 0, n = 0, i, k;
    integer kk [0:2];

    task automatic check(input [7:0] got, input integer expect, input [255:0] tag);
        begin
            n = n + 1;
            if (got !== expect[7:0]) begin
                if (err < 12)
                    $display("  MISMATCH %0s: got %0d expect %0d", tag, got, expect);
                err = err + 1;
            end
        end
    endtask

    // 参考模型: 算术右移 + 饱和
    function integer ref_out(input integer c, input integer K);
        integer d;
        begin
            d = c - 128;
            d = (d * K) >>> 8;          // 算术右移 = floor
            d = d + 128;
            if (d < 0)        ref_out = 0;
            else if (d > 255) ref_out = 255;
            else              ref_out = d;
        end
    endfunction

    initial begin
        kk[0] = 358; kk[1] = 256; kk[2] = 384;
        i_cb = 128; i_cr = 128; i_v = 0;
        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // 逐值扫描 (Cb = Cr = 同一个值)
        for (i = 0; i < 256; i = i + 1) begin
            @(negedge clk);
            i_cb = i[7:0]; i_cr = 255 - i[7:0]; i_v = 1;
            @(posedge clk);
            #1;
            check(o_cb_140, ref_out(i,           358), "cb@1.40");
            check(o_cr_140, ref_out(255 - i,     358), "cr@1.40");
            check(o_cb_100, ref_out(i,           256), "cb@1.00");
            check(o_cr_100, ref_out(255 - i,     256), "cr@1.00");
            check(o_cb_150, ref_out(i,           384), "cb@1.50");
            check(o_cr_150, ref_out(255 - i,     384), "cr@1.50");
        end

        $display("");
        $display("=== chroma_gain TB : %0d checks, %0d errors ===", n, err);
        $display("    example  Cb=40  : 1.00x -> %0d , 1.40x -> %0d , 1.50x -> %0d",
                 ref_out(40, 256), ref_out(40, 358), ref_out(40, 384));
        $display("    example  Cb=190 : 1.00x -> %0d , 1.40x -> %0d , 1.50x -> %0d",
                 ref_out(190, 256), ref_out(190, 358), ref_out(190, 384));
        if (err == 0) $display("    RESULT: PASS");
        else          $display("    RESULT: FAIL");
        $finish;
    end

endmodule
