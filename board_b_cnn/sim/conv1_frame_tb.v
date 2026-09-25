//=============================================================================
// conv1_frame_tb.v —— conv1 整层对拍（第 ③ 步验收）
//-----------------------------------------------------------------------------
// 流程：
//   1) 把 x0_input.hex（列主序 r+72c+9216ch）重排写入 DUT 帧缓存（行主序平面布局）
//   2) 启动，收集 128×72 个输出像素（每像素 8 通道），与 x1_conv1.hex 逐位比对
// 运行（仓库根目录）：
//   vlib work_cnn
//   vlog -work work_cnn <cnn_rom.v> <conv1_frame.v> sim/conv1_frame_tb.v
//   vsim -c work_cnn.conv1_frame_tb -do "run -all; quit -f"
//=============================================================================
`timescale 1ns/1ps

module conv1_frame_tb;

    localparam IMG_W = 128;
    localparam IMG_H = 72;
    localparam IMG_C = 3;
    localparam IMG_N = IMG_W*IMG_H*IMG_C;      // 27648
    localparam OUT_N = IMG_W*IMG_H*8;          // 73728
    localparam PIXN  = IMG_W*IMG_H;            // 9216
    localparam AW    = 15;

    reg          clk = 0;
    reg          rst_n = 0;
    reg          wr_en = 0;
    reg  [AW-1:0] wr_addr = 0;
    reg  [7:0]   wr_data = 0;
    reg          start = 0;

    wire [71:0]  m_data;
    wire         m_valid;
    wire         done;

    reg  [7:0] img  [0:IMG_N-1];
    reg  [7:0] gold [0:OUT_N-1];

    integer errs = 0, checks = 0, pixcnt = 0, cyc = 0;
    integer idx, rr, cc, ch, k, ga;
    reg [8:0] got;

    conv1_frame #(
        .W_MEM("sim/cnn_data/w_conv1_packed.mem"),
        .B_MEM("sim/cnn_data/b_conv1_packed.mem")
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data),
        .start(start), .m_data(m_data), .m_valid(m_valid), .done(done)
    );

    always #5 clk = ~clk;                       // 100 MHz 仿真时钟

    initial begin
        $readmemh("sim/cnn_data/x0_input.hex", img);
        $readmemh("sim/cnn_data/x1_conv1.hex", gold);
    end

    initial begin
        rst_n = 0;  wr_en = 0;  start = 0;
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        $display("=========================================================");
        $display(" conv1 whole-frame check  (golden: sim/cnn_data/x1_conv1.hex)");
        $display("---------------------------------------------------------");

        // ---- 1) 写帧缓存：列主序 hex → 行主序平面布局 ----
        for (idx = 0; idx < IMG_N; idx = idx + 1) begin
            rr = idx % IMG_H;
            cc = (idx / IMG_H) % IMG_W;
            ch = idx / (IMG_H*IMG_W);
            @(posedge clk);
            wr_en   = 1'b1;
            wr_addr = ch*(IMG_W*IMG_H) + rr*IMG_W + cc;
            wr_data = img[idx];
        end
        @(posedge clk);
        wr_en = 1'b0;
        $display(" 帧缓存写入完成（%0d 字节）", IMG_N);

        // ---- 2) 启动 ----
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;

        // ---- 3) 收集输出并逐位比对（在 negedge 采样，避免漏掉最后一个像素）----
        while (pixcnt < PIXN && cyc < 900000) begin
            @(negedge clk);
            cyc = cyc + 1;
            if (m_valid === 1'b1) begin
                rr = pixcnt / IMG_W;
                cc = pixcnt % IMG_W;
                for (k = 0; k < 8; k = k + 1) begin
                    got = m_data[k*9 +: 9];
                    ga  = rr + IMG_H*cc + IMG_H*IMG_W*k;    // 金标准索引（列主序）
                    checks = checks + 1;
                    if (got !== {1'b0, gold[ga]}) begin
                        errs = errs + 1;
                        if (errs <= 8)
                            $display("  FAIL pix%0d(r%0d,c%0d) ch%0d: got %0d expect %0d",
                                     pixcnt, rr, cc, k, got, gold[ga]);
                    end
                end
                pixcnt = pixcnt + 1;
            end
        end

        $display("---------------------------------------------------------");
        $display(" 输出像素 %0d / %0d，耗时 %0d 拍", pixcnt, PIXN, cyc);
        if (errs == 0 && pixcnt == PIXN)
            $display(" RESULT: PASS  -- %0d 项全部与金标准一致", checks);
        else
            $display(" RESULT: FAIL  -- %0d / %0d 项不一致", errs, checks);
        $display("=========================================================");
        $finish;
    end

endmodule
