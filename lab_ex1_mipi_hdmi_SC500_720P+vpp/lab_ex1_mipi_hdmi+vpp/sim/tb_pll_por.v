`timescale 1ns / 1ps
//=============================================================================
// tb_pll_por.v —— pll_por 上电复位发生器的自检台
//
// 验证：
//   1. 上电后 pll_rst 立即为高（PLL 被复位），por_arst_n 为低（PHY 复位保持）。
//   2. 保持时间 = POR_CYCLES 个 clk 周期（这里用小参数加速仿真）。
//   3. 释放后 pll_rst 为低、por_arst_n 为高，且释放沿经过两级同步（不是当拍直通）。
//   4. 释放后计数器饱和，不再翻转（不会周期性重置 PLL）。
//   5. ext_arst_n 拉低能立即把两者拉回复位态。
//=============================================================================
module tb_pll_por;

    localparam [31:0] POR = 32'd10;      // 10 拍，便于观察

    reg  clk = 1'b0;
    reg  ext_arst_n = 1'b1;
    wire pll_rst;
    wire por_arst_n;

    integer errors = 0;

    pll_por #( .POR_CYCLES (POR) ) dut (
        .clk        (clk),
        .ext_arst_n (ext_arst_n),
        .pll_rst    (pll_rst),
        .por_arst_n (por_arst_n)
    );

    // 50MHz
    always #10 clk = ~clk;

    task check;
        input        cond;
        input [255:0] name;
        begin
            if (!cond) begin
                $display("FAIL: %0s  (t=%0t clk, pll_rst=%b por_arst_n=%b)",
                         name, $time, pll_rst, por_arst_n);
                errors = errors + 1;
            end else begin
                $display("PASS: %0s", name);
            end
        end
    endtask

    // 统计 cnt 里的时钟沿数，用来到点采样
    integer edges;

    initial begin
        $display("=== tb_pll_por start (POR_CYCLES=%0d) ===", POR);

        // --- 0) 上电瞬间：必须处于复位态 ---
        #1;
        check(pll_rst    === 1'b1, "power-on: pll_rst high (PLL held in reset)");
        check(por_arst_n === 1'b0, "power-on: por_arst_n low (PHY held in reset)");

        // --- 1) 在保持窗口内一直为复位态 ---
        repeat (POR) @(posedge clk);
        #1;
        // 此刻 cnt 刚好数到 POR，por_release=1，但 s1/s2 尚未更新 -> 应仍为复位态
        check(pll_rst    === 1'b1, "still held at end of POR window");
        check(por_arst_n === 1'b0, "por_arst_n still low at end of POR window");

        // --- 2) 下一拍 s1 变高，s2 还低 -> 仍然复位（证明是两级同步，不是直通）---
        @(posedge clk); #1;
        check(pll_rst    === 1'b1, "one cycle after release: still reset (sync stage 1)");

        // --- 3) 再下一拍 s2 变高 -> 释放在第 2 级之后发生 ---
        @(posedge clk); #1;
        check(pll_rst    === 1'b0, "two cycles after release: pll_rst deasserted");
        check(por_arst_n === 1'b1, "two cycles after release: por_arst_n high");

        // --- 4) 计数器饱和：长时间运行后不能再次进入复位 ---
        repeat (200) @(posedge clk);
        check(pll_rst    === 1'b0, "after 200 more cycles: pll_rst stays low (counter saturates)");
        check(por_arst_n === 1'b1, "after 200 more cycles: por_arst_n stays high");

        // --- 5) 异步复位请求：拉低立即回到复位态 ---
        ext_arst_n = 1'b0;
        #1;
        check(pll_rst    === 1'b1, "ext_arst_n low: pll_rst asserts asynchronously");
        check(por_arst_n === 1'b0, "ext_arst_n low: por_arst_n asserts asynchronously");

        // --- 6) 释放 ext_arst_n 后：POR 计数器已饱和，两个周期内即可释放 ---
        ext_arst_n = 1'b1;
        @(posedge clk); #1;   // s1 <= por_release (=1)
        @(posedge clk); #1;   // s2 <= s1
        check(pll_rst    === 1'b0, "after ext_arst_n released: pll_rst deasserts in 2 cycles");
        check(por_arst_n === 1'b1, "after ext_arst_n released: por_arst_n high");

        $display("=== tb_pll_por done: errors=%0d ===", errors);
        if (errors == 0) $display("RESULT: ALL PASS");
        else             $display("RESULT: FAILED");
        $finish;
    end

    initial begin
        #100000;
        $display("RESULT: TIMEOUT");
        $finish;
    end

endmodule
