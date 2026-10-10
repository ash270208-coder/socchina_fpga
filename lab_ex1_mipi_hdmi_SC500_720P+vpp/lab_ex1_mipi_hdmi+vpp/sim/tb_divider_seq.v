`timescale 1ns / 1ps
//=============================================================================
// tb_divider_seq.v —— divider_seq 的等价性验证
//
// 验证目标：`divider_seq` 产出的 quotient / remainder 与
//           "48bit 无符号整数除法" **逐位完全相同**（不是近似）。
// 参考模型：Verilog 行为级 `/` 与 `%`（48bit / 32bit 无符号）。
//
// 覆盖：
//   1. 定向 corner：n=0 / d=1 / n=d / n<d / 全 1 边界 / d=max
//   2. AWB 真实场景：numerator = {frame_g_boost, 16'd0}，denominator = frame_r
//   3. 全范围随机 4000 组
//   4. 握手鲁棒性：除法进行中改输入、进行中重复 start
//
// 跑法（ModelSim）：
//   vlib work && vmap work work
//   vlog divider_seq.v tb_divider_seq.v
//   vsim -c -do "run -all; quit -f" tb_divider_seq
//=============================================================================
module tb_divider_seq;

    reg          clk = 1'b0;
    always #5 clk = ~clk;                 // 100 MHz

    reg          rst   = 1'b0;
    reg          start = 1'b0;
    reg  [31:0]  den   = 32'd1;
    reg  [47:0]  num   = 48'd0;
    wire         done;
    wire [47:0]  q;
    wire [31:0]  r;

    divider_seq #(
        .PIPLE (50),
        .S_DEN ("UNSIGNED"),
        .S_NUM ("UNSIGNED"),
        .W_DEN (32),
        .W_NUM (48),
        .W_REM (32)
    ) dut (
        .clk         (clk),
        .denominator (den),
        .numerator   (num),
        .rst         (rst),
        .start       (start),
        .done        (done),
        .quotient    (q),
        .remainder   (r)
    );

    // ---- 全部声明放模块级，避免"unnamed block 内声明"问题 ----
    integer    errors  = 0;
    integer    tests   = 0;
    integer    lat_min = 9999;
    integer    lat_max = 0;
    integer    i;
    integer    k;

    reg [31:0] rnd;
    reg [47:0] n_tmp;
    reg [31:0] d_tmp;
    reg [31:0] g_tmp;
    reg [47:0] saved_q;
    reg [47:0] exp_q;
    reg [31:0] exp_r;

    //-------------------------------------------------------------------------
    // 单次比对：输入在 start 之前置好（模拟 awb 的用法）
    //-------------------------------------------------------------------------
    task chk(input [47:0] n, input [31:0] d, input [127:0] tag);
        integer cyc;
        begin
            exp_q = n / d;
            exp_r = n % d;

            @(negedge clk);
            num = n; den = d; start = 1'b1;
            @(negedge clk);
            start = 1'b0;

            cyc = 0;
            while (done !== 1'b1 && cyc < 300) begin
                @(negedge clk);
                cyc = cyc + 1;
            end

            if (done !== 1'b1) begin
                $display("[FAIL] TIMEOUT  %0s : n=%0d d=%0d", tag, n, d);
                errors = errors + 1;
            end else begin
                tests = tests + 1;
                if (cyc < lat_min) lat_min = cyc;
                if (cyc > lat_max) lat_max = cyc;
                if (q !== exp_q || r !== exp_r) begin
                    $display("[FAIL] %0s : n=%0d d=%0d | dut q=%0d r=%0d | exp q=%0d r=%0d",
                             tag, n, d, q, r, exp_q, exp_r);
                    errors = errors + 1;
                end
            end
            @(negedge clk);
        end
    endtask

    //-------------------------------------------------------------------------
    initial begin
        $display("========================================================");
        $display(" tb_divider_seq : divider_seq vs 行为级 48/32 无符号除法");
        $display("========================================================");

        // ---- 复位 ----
        rst = 1'b1; start = 1'b0; num = 48'd0; den = 32'd1;
        repeat (4) @(negedge clk);
        rst = 1'b0;
        repeat (2) @(negedge clk);

        if (done !== 1'b0) begin
            $display("[FAIL] 复位后 done 不是 0");
            errors = errors + 1;
        end

        //=========================================================
        $display("--- 1) 定向 corner ---");
        //=========================================================
        chk(48'd0,             32'd1,        "n=0/d=1");
        chk(48'd0,             32'hFFFFFFFF, "n=0/d=max");
        chk(48'd1,             32'd1,        "1/1");
        chk(48'd1,             32'hFFFFFFFF, "1/d=max");
        chk(48'hFFFFFFFFFFFF,  32'd1,        "n=max/d=1");
        chk(48'hFFFFFFFFFFFF,  32'd2,        "n=max/d=2");
        chk(48'hFFFFFFFFFFFF,  32'hFFFFFFFF, "max/max");
        chk(48'hFFFFFFFFFFFF,  32'hFFFFFFFE, "max/(max-1)");
        chk(48'd1000,          32'd1001,     "n<d");
        chk(48'd1000,          32'd1000,     "n=d");
        chk(48'd7,             32'd3,        "7/3");
        chk(48'd200,           32'd13,       "200/13");
        chk(48'h0000FFFFFFFFFFFF, 32'd3,     "low48=1/3");
        chk(48'h0000000100000000, 32'hFFFFFFFF, "(1<<32)/max");
        chk(48'h0000000100000000, 32'd1,      "(1<<32)/1");
        for (i = 0; i < 16; i = i + 1) begin
            n_tmp = 48'h0000000000010000 << i;
            chk(n_tmp, 32'd3, "shift/3");
        end

        //=========================================================
        $display("--- 2) AWB 真实场景: numerator={g+g/4,16'd0}, denominator=r ---");
        //=========================================================
        // 720p 全白时 frame 累加和 = 1280*720*255 = 234,950,400
        for (i = 0; i < 400; i = i + 1) begin
            rnd   = $random;
            g_tmp = 32'd1000 + (rnd % 32'd234_000_000);
            rnd   = $random;
            d_tmp = 32'd1000 + (rnd % 32'd234_000_000);
            // 与 awb.v:107 的 frame_g + {2'b00, frame_g[31:2]} 等价
            n_tmp = { (g_tmp + (g_tmp >> 2)), 16'd0 };
            chk(n_tmp, d_tmp, "awb-real");
        end
        chk({ (32'd234950400 + (32'd234950400 >> 2)), 16'd0 }, 32'd234950400, "white/white");
        chk({ (32'd117475200 + (32'd117475200 >> 2)), 16'd0 }, 32'd234950400, "half/white");
        chk({ (32'd234950400 + (32'd234950400 >> 2)), 16'd0 }, 32'd1000,      "white/dark");
        chk({ (32'd1000      + (32'd1000      >> 2)), 16'd0 }, 32'd1000,      "dark/dark");

        //=========================================================
        $display("--- 3) 全范围随机 4000 组 ---");
        //=========================================================
        for (i = 0; i < 4000; i = i + 1) begin
            rnd = $random; n_tmp[47:32] = rnd[15:0];
            rnd = $random; n_tmp[31:0]  = rnd;
            rnd = $random; d_tmp        = rnd;
            if (d_tmp == 32'd0) d_tmp = 32'd1;      // 除零无定义，跳过
            chk(n_tmp, d_tmp, "random");
        end

        //=========================================================
        $display("--- 4) 握手鲁棒性 ---");
        //=========================================================
        // 4a) 除法进行中途改输入，结果必须是"启动那一刻"的输入
        n_tmp = 48'd123456789012;
        d_tmp = 32'd12345;
        saved_q = n_tmp / d_tmp;
        @(negedge clk);
        num = n_tmp; den = d_tmp; start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        for (k = 0; k < 5; k = k + 1) @(negedge clk);
        num = 48'h000000000000;              // 中途把输入打乱
        den = 32'hFFFFFFFF;
        for (k = 0; k < 200; k = k + 1) begin
            @(negedge clk);
            if (done === 1'b1) k = 1000;
        end
        tests = tests + 1;
        exp_q = 48'd123456789012 / 32'd12345;
        exp_r = 48'd123456789012 % 32'd12345;
        if (q !== exp_q || r !== exp_r) begin
            $display("[FAIL] 4a 中途改输入影响了结果: dut q=%0d r=%0d exp q=%0d r=%0d",
                     q, r, exp_q, exp_r);
            errors = errors + 1;
        end

        // 4b) 除法进行中重复发 start，不能打断/污染本次结果
        n_tmp = 48'd777777777;
        d_tmp = 32'd4321;
        @(negedge clk);
        num = n_tmp; den = d_tmp; start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        for (k = 0; k < 3; k = k + 1) @(negedge clk);
        start = 1'b1;                        // 进行中再发一次
        @(negedge clk);
        start = 1'b0;
        for (k = 0; k < 200; k = k + 1) begin
            @(negedge clk);
            if (done === 1'b1) k = 1000;
        end
        tests = tests + 1;
        exp_q = 48'd777777777 / 32'd4321;
        exp_r = 48'd777777777 % 32'd4321;
        if (q !== exp_q || r !== exp_r) begin
            $display("[FAIL] 4b 重复 start 影响了结果: dut q=%0d r=%0d exp q=%0d r=%0d",
                     q, r, exp_q, exp_r);
            errors = errors + 1;
        end

        // 4c) 连续背靠背除法（每次都重新 start）
        for (k = 0; k < 20; k = k + 1) begin
            n_tmp = 48'd1000000 + k * 48'd31337;
            d_tmp = 32'd999 + k;
            chk(n_tmp, d_tmp, "back-to-back");
        end

        //=========================================================
        $display("========================================================");
        $display(" 测试组数(tests)   = %0d", tests);
        $display(" 失败数(errors)    = %0d", errors);
        $display(" done 延迟(拍)    = min %0d / max %0d", lat_min, lat_max);
        if (errors == 0)
            $display(" 结果：*** PASS *** 全部逐位一致");
        else
            $display(" 结果：*** FAIL *** 有 %0d 组不一致", errors);
        $display("========================================================");
        $finish;
    end

    // 全局看门狗
    initial begin
        #20000000;
        $display("[FAIL] 全局超时，仿真被强制结束");
        $finish;
    end

endmodule
