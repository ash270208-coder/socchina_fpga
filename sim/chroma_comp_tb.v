`timescale 1ns/1ps
// ===========================================================================
// chroma_comp_tb.v -- 自检：与参考模型逐值比对 + 语义检查
//   参考模型：k = (Y' * recip(Y>>2)) >>> 4, 限幅 [128,512]
//             Cb' = sat(128 + ((Cb-128)*k) >>> 8)
//   语义检查：Y'==Y 时必须原样输出（k=1），这是"不做均衡时不能改变颜色"的底线
// ===========================================================================
module chroma_comp_tb;

    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    reg  [7:0] y_old, y_new, cb, cr;
    reg        v;
    wire [7:0] o_y, o_cb, o_cr;
    wire       o_v;

    chroma_comp dut (
        .I_clk(clk), .I_rst_n(rst_n),
        .I_y_old(y_old), .I_y_new(y_new), .I_cb(cb), .I_cr(cr), .I_tvalid(v),
        .O_y(o_y), .O_cb(o_cb), .O_cr(o_cr), .O_tvalid(o_v)
    );

    integer err = 0, n = 0, i, j, k, kk;
    integer yl[0:9], yn[0:9], cc[0:4];

    function integer ref_k(input integer yo, input integer yn);
        integer p;
        begin
            if (yo == yn) begin                     // DUT 里有 k=1 直通
                ref_k = 256;
            end
            else begin
                p = yn * dut.recip(yo[7:2]);
                ref_k = p >>> 4;
                if (ref_k > dut.K_MAX_Q8) ref_k = dut.K_MAX_Q8;
                if (ref_k < dut.K_MIN_Q8) ref_k = dut.K_MIN_Q8;
            end
        end
    endfunction

    function integer ref_c(input integer c, input integer K);
        integer q;
        begin
            q = ((c - 128) * K) >>> 8;
            q = q + 128;
            if (q < 0)        ref_c = 0;
            else if (q > 255) ref_c = 255;
            else              ref_c = q;
        end
    endfunction

    task check(input [7:0] got, input integer expect, input [255:0] tag);
        begin
            n = n + 1;
            if (got !== expect[7:0]) begin
                if (err < 10) $display("  MISMATCH %0s: got %0d expect %0d", tag, got, expect);
                err = err + 1;
            end
        end
    endtask

    initial begin
        yl[0]=4;   yl[1]=20;  yl[2]=40;  yl[3]=83;  yl[4]=128;
        yl[5]=150; yl[6]=180; yl[7]=200; yl[8]=230; yl[9]=254;
        cc[0]=0;   cc[1]=40;  cc[2]=128; cc[3]=190; cc[4]=255;

        v = 0; y_old = 128; y_new = 128; cb = 128; cr = 128;
        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        for (i = 0; i < 10; i = i + 1) begin
            for (j = 0; j < 10; j = j + 1) begin
                yn[0]=yl[i];                                                // k=1 的情形
                yn[1]=(yl[i] > 40) ? yl[i]-40 : 4;                          // 压暗
                yn[2]=(yl[i] < 200) ? yl[i]+40 : 254;                       // 提亮
                for (k = 0; k < 5; k = k + 1) begin
                    @(negedge clk);
                    y_old = yl[i]; y_new = yn[j]; cb = cc[k]; cr = 255 - cc[k]; v = 1;
                    repeat (3) @(posedge clk);      // 模块 3 拍，等它吐出来
                    #1;
                    kk = ref_k(yl[i], yn[j]);
                    check(o_cb, ref_c(cc[k],       kk), "cb");
                    check(o_cr, ref_c(255 - cc[k], kk), "cr");
                    check(o_y,  yn[j],                  "y ");
                end
            end
        end

        // 语义检查：k=1 时色度必须原样
        @(negedge clk); y_old = 120; y_new = 120; cb = 60; cr = 200; v = 1;
        repeat (3) @(posedge clk); #1;
        $display("");
        $display("  Y'==Y (k=1) : cb %0d -> %0d , cr %0d -> %0d", 60, o_cb, 200, o_cr);
        if (o_cb !== 8'd60 || o_cr !== 8'd200) begin
            $display("  FAIL: k=1 时颜色被改动了"); err = err + 1;
        end

        $display("");
        $display("=== chroma_comp TB : %0d checks, %0d errors ===", n, err);
        $display("    example Y=100: Y'=50 -> k=%0d (0.5x) ; Y'=150 -> k=%0d (1.5x)",
                 ref_k(100, 50), ref_k(100, 150));
        $display("    %0s", (err == 0) ? "RESULT: PASS" : "RESULT: FAIL");
        $finish;
    end

endmodule
