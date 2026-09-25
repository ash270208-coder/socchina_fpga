//=============================================================================
// conv3_frame_tb.v —— conv3 整层对拍（16→32, s2）
// 输入 x2_conv2.hex（64x36x16 列主序）→ 打包 128bit/像素 → 写帧缓存 → 启动
// 输出 32x18x32 与 x3_conv3.hex 逐位比对
//=============================================================================
`timescale 1ns/1ps

module conv3_frame_tb;

    localparam IW=64, IH=36, IC=16,  IN_PX = IW*IH,   WIN = 128;
    localparam OW=32, OH=18, OC=32,  ON_PX = OW*OH,   WOUT = 256;

    reg clk=0, rst_n=0, wr_en=0, start=0;
    reg [13:0] wr_addr=0;
    reg [WIN-1:0] wr_data=0;
    wire [WOUT-1:0] m_data;
    wire m_valid, done;

    reg [7:0] xin  [0:IN_PX*IC-1];
    reg [7:0] gold [0:ON_PX*OC-1];
    integer errs=0, checks=0, pixcnt=0, cyc=0;
    integer r, c, ch;
    reg [WIN-1:0] w;

    conv3_frame dut (
        .clk(clk), .rst_n(rst_n), .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data),
        .start(start), .m_data(m_data), .m_valid(m_valid), .done(done)
    );

    always #5 clk = ~clk;
    initial begin
        $readmemh("sim/cnn_data/x2_conv2.hex", xin);
        $readmemh("sim/cnn_data/x3_conv3.hex", gold);
    end

    initial begin
        rst_n=0; wr_en=0; start=0;
        repeat (5) @(posedge clk); rst_n=1; repeat (2) @(posedge clk);

        $display("=========================================================");
        $display(" conv3 whole-frame check  (golden: x3_conv3.hex)");

        for (r=0; r<IH; r=r+1) begin
            for (c=0; c<IW; c=c+1) begin
                w = 0;
                for (ch=0; ch<IC; ch=ch+1)
                    w[8*ch +: 8] = xin[ch*IN_PX + c*IH + r];
                @(posedge clk);
                wr_en=1; wr_addr = r*IW + c; wr_data = w;
            end
        end
        @(posedge clk); wr_en=0;
        $display(" 输入帧写入完成（%0d 像素 x %0d bit）", IN_PX, WIN);

        start=1; @(posedge clk); start=0;

        while (pixcnt < ON_PX && cyc < 2000000) begin
            @(negedge clk); cyc = cyc+1;
            if (m_valid === 1'b1) begin
                for (ch=0; ch<OC; ch=ch+1) begin
                    checks = checks+1;
                    if (m_data[8*ch +: 8] !== gold[(pixcnt/OW) + OH*(pixcnt%OW) + ON_PX*ch]) begin
                        errs = errs+1;
                        if (errs <= 8)
                            $display("  FAIL pix%0d(r%0d,c%0d) ch%0d: got %0d expect %0d",
                                     pixcnt, pixcnt/OW, pixcnt%OW, ch,
                                     m_data[8*ch +: 8],
                                     gold[(pixcnt/OW) + OH*(pixcnt%OW) + ON_PX*ch]);
                    end
                end
                pixcnt = pixcnt+1;
            end
        end

        $display(" 输出像素 %0d / %0d，耗时 %0d 拍", pixcnt, ON_PX, cyc);
        if (errs == 0 && pixcnt == ON_PX)
            $display(" RESULT: PASS  -- %0d checks all match the golden data", checks);
        else
            $display(" RESULT: FAIL  -- %0d / %0d checks mismatch", errs, checks);
        $finish;
    end

endmodule
