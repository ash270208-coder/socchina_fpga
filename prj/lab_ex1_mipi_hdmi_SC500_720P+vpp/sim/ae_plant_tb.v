`timescale 1ns / 1ps
// 自动曝光闭环极限环验证 (带被控对象模型):
//   模型: avg_y(k) = S * ae(k-3) / 1990 * 255,  S = 场景亮度 0..1
//         (曝光变化经 传感器->ISP->DDR->统计 约 3 帧延迟后反映到 avg_y)
//   场景 1: S 从 0.5 突跳到 1.0 (台灯快速调亮) -> 曝光应收敛, avg 稳定, 无忽明忽暗
//   场景 2: S 从 1.0 突降到 0.3 (关灯)        -> 同上
//   判据: 收敛期后 (每段后 40 帧) avg_y 波动范围 <= 20 LSB (死区外不持续振荡),
//         且平均亮度最终落在目标 50 附近 (±30)。
module tb_ae_plant;

    reg         clk, rst_n;
    reg         enable, cfg_done;
    reg         frame_done;
    reg  [7:0]  avg_y;
    wire [15:0] o_ae;
    wire        o_ae_req;

    ae_auto #(
        .TARGET_Y(50), .AE_MAX(1990), .AE_MIN(4), .AE_INIT(500),
        .HYST(20), .KP(1), .STEP_MAX(30), .AG_VALUE(80),
        .UPDATE_HOLD(3)
    ) dut (
        .I_clk(clk), .I_rst_n(rst_n), .I_enable(enable),
        .I_avg_y(avg_y), .I_frame_done(frame_done), .I_cfg_done(cfg_done),
        .O_ae(o_ae), .O_ag(), .O_ae_req(o_ae_req)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // ---- 被控对象 ----
    real        S_scene;
    reg  [15:0] ae_d1, ae_d2, ae_d3;
    integer     errors;

    task tick_frame;
        begin
            @(posedge clk);
            frame_done = 1'b1;
            ae_d3 = ae_d2; ae_d2 = ae_d1; ae_d1 = o_ae;
            avg_y = $rtoi(S_scene * ae_d3 * 255.0 / 1990.0);
            @(posedge clk);
            frame_done = 1'b0;
        end
    endtask

    // 采集一段窗口内 avg 的波动范围与均值
    task settle_check(input integer frames, input real lo, input real hi,
                      output integer span, output real mean_out);
        integer k;
        real acc, mn, mx;
        begin
            acc = 0.0; mn = 1e9; mx = -1e9;
            for (k = 0; k < frames; k = k + 1) begin
                tick_frame();
                acc = acc + avg_y;
                if (avg_y < mn) mn = avg_y;
                if (avg_y > mx) mx = avg_y;
            end
            span = $rtoi(mx - mn);
            mean_out = acc / frames;
            $display("INFO %0d 帧窗口: avg 波动范围 %0d LSB, 均值 %0.1f, ae=%0d",
                     frames, span, mean_out, o_ae);
            if ((mean_out < lo) || (mean_out > hi)) begin
                $display("FAIL 均值 %0.1f 超出 [%0.1f, %0.1f]", mean_out, lo, hi);
                errors = errors + 1;
            end
            if (span > 20) begin
                $display("FAIL 波动范围 %0d LSB > 20 (持续振荡/忽明忽暗)", span);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors = 0;
        rst_n = 0; enable = 0; cfg_done = 0; avg_y = 0; frame_done = 0;
        S_scene = 0.5;
        ae_d1 = 500; ae_d2 = 500; ae_d3 = 500;
        #30 rst_n = 1;
        #20;
        enable = 1; cfg_done = 1;

        // ---- 场景 1 预热 + 收敛 ----
        repeat (60) tick_frame();           // S=0.5, 预热至收敛
        $display("---- 台灯调亮: S 0.5 -> 1.0 ----");
        S_scene = 1.0;
        repeat (20) tick_frame();           // 过渡期 (允许震荡调整)
        begin : c1
            integer span; real mean_out;
            settle_check(40, 20.0, 80.0, span, mean_out);
        end

        // ---- 场景 2: 关灯 ----
        $display("---- 关灯: S 1.0 -> 0.3 ----");
        S_scene = 0.3;
        repeat (20) tick_frame();
        begin : c2
            integer span; real mean_out;
            settle_check(40, 20.0, 80.0, span, mean_out);
        end

        // ---- 场景 3: 再次快速调亮 (往复) ----
        $display("---- 再次调亮: S 0.3 -> 0.9 ----");
        S_scene = 0.9;
        repeat (20) tick_frame();
        begin : c3
            integer span; real mean_out;
            settle_check(40, 20.0, 80.0, span, mean_out);
        end

        $display("------------------------------------");
        if (errors == 0) $display("===== PASS =====");
        else             $display("===== FAIL (%0d) =====", errors);
        $finish;
    end

endmodule
