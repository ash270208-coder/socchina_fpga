`timescale 1ns/1ps
// ===========================================================================
// vpp_top_l1_tb.v  --  L1 改动(直方图档搬到显示域)的回归测试
//
//  检查 A【色调域】: u_m0.y_he_tdata(直方图链吃到的 Y) 必须等于
//                    Y(γ(R),γ(G),γ(B)) —— 也就是 gamma 之后才算出来的 Y;
//                    同时 u_m0.y_tdata(Sobel 吃的那份) 必须还是 Y(R,G,B)(线性域)。
//                    两个数不一样, 才说明 2B 的两个转换器各就各位。
//
//  检查 B【颜色没发灰】: 同一张"四色块"图分别 force 成模式 0 和模式 2,
//                    比较输出帧的平均饱和度 S=(max-min)/max。
//                    L1 之前: 模式2 在线性域做 HE, S 会明显低于模式 0;
//                    L1 之后: 模式2 在显示域做 HE, S 应 >= 模式 0(不再发灰)。
//
//  跑法: vlog ... ; vsim -c -do "run -all; quit -f" vpp_top_l1_tb
// ===========================================================================
module vpp_top_l1_tb;

    localparam W   = 64;
    localparam H   = 64;
    localparam CLK = 10;

    reg clk = 0;
    always #(CLK/2) clk = ~clk;

    reg         rst_n  = 0;
    reg  [1:0]  button = 2'b11;
    reg         tvalid = 0, tuser = 0, tlast = 0, tdest = 0, tready = 1;
    reg  [23:0] tdata  = 24'd0;

    wire [23:0] o0_data, o2_data;
    wire        o0_v, o0_u, o0_l, o2_v, o2_u, o2_l;
    wire [2:0]  mode0, mode2;

    vpp_top #(.IMG_WIDTH(W), .IMG_HEIGHT(H), .SOBEL_THRESHOLD(60)) u_m0 (
        .I_button(button), .I_clk(clk), .I_rst_n(rst_n),
        .I_tlast(tlast), .I_tuser(tuser), .I_tdata(tdata), .I_tvalid(tvalid),
        .I_tdest(tdest), .I_tready(tready),
        .O_tdata(o0_data), .O_tlast(o0_l), .O_tuser(o0_u), .O_tvalid(o0_v),
        .O_tready(), .O_display_mode(mode0)
    );

    vpp_top #(.IMG_WIDTH(W), .IMG_HEIGHT(H), .SOBEL_THRESHOLD(60)) u_m2 (
        .I_button(button), .I_clk(clk), .I_rst_n(rst_n),
        .I_tlast(tlast), .I_tuser(tuser), .I_tdata(tdata), .I_tvalid(tvalid),
        .I_tdest(tdest), .I_tready(tready),
        .O_tdata(o2_data), .O_tlast(o2_l), .O_tuser(o2_u), .O_tvalid(o2_v),
        .O_tready(), .O_display_mode(mode2)
    );

    // ------------------------------------------------------------------ 工具
    function [7:0] gmap(input [7:0] x);          // 直接借 DUT 里的 gamma 表
        gmap = u_m0.u_gamma_lut.gamma_map(x);
    endfunction

    function integer ylin(input [23:0] p);       // 线性域 Y (RGB->YCbCr 的算法)
        ylin = (77 * p[23:16] + 150 * p[15:8] + 29 * p[7:0]) >> 8;
    endfunction

    // 黑电平：2026.10.24 起已从 gamma_lut.v 挪到 awb.v 的输入侧
    //   （awb.v PEDESTAL=12，gamma_lut.v BLK_G 默认 0）。本 TB 直接往
    //   vpp_top 灌 RGB（相当于 AWB 之后的数据），所以这里**不能再扣**。
    //   若以后把 awb.v PEDESTAL 设回 0 且 gamma_lut BLK_G 设回 12，
    //   把下面三个 localparam 改回 21/12/33 即可。
    localparam [7:0] BLK_R = 8'd0;
    localparam [7:0] BLK_G = 8'd0;
    localparam [7:0] BLK_B = 8'd0;

    function integer ydisp(input [23:0] p);      // 显示域 Y = Y(γ(R),γ(G),γ(B))
        integer rr, gg, bb;
        begin
            rr = (p[23:16] > BLK_R) ? (p[23:16] - BLK_R) : 0;   // 与 gamma_lut 的
            gg = (p[15: 8] > BLK_G) ? (p[15: 8] - BLK_G) : 0;   // 黑电平一致
            bb = (p[ 7: 0] > BLK_B) ? (p[ 7: 0] - BLK_B) : 0;
            ydisp = (77 * gmap(rr[7:0]) + 150 * gmap(gg[7:0]) + 29 * gmap(bb[7:0])) >> 8;
        end
    endfunction

    function real satv(input [23:0] p);
        integer r, g, b, mx, mn;
        begin
            r = p[23:16]; g = p[15:8]; b = p[7:0];
            mx = (r > g) ? r : g; if (b > mx) mx = b;
            mn = (r < g) ? r : g; if (b < mn) mn = b;
            if (mx == 0) satv = 0.0;
            else         satv = (mx - mn) * 1.0 / mx;
        end
    endfunction

    // ------------------------------------------------------------------ 检查 A
    integer errA = 0, nA = 0;
    task chk_color(input [23:0] p, input [127:0] tag);
        integer yhe, ylin_exp, y_meas, ys_meas;
        begin
            // 先把流水线灌满, 再让它停住(端口值会保持最后一个有效像素)
            repeat (6) begin @(posedge clk); tvalid <= 1; tuser <= 0; tlast <= 0; tdata <= p; end
            @(posedge clk); tvalid <= 0;
            repeat (10) @(posedge clk);

            yhe      = ydisp(p);
            ylin_exp = ylin(p);
            y_meas   = u_m0.u_hist_eq_color.u_rgb2y.O_y_tdata;  // 直方图链(显示域)
            ys_meas  = u_m0.u_Sobel_edge.u_rgb2y.O_y_tdata;     // Sobel(线性域)

            nA = nA + 2;
            if (y_meas !== yhe) begin
                if (errA < 8) $display("    MISMATCH %0s: y_he=%0d expect %0d", tag, y_meas, yhe);
                errA = errA + 1;
            end
            if (ys_meas !== ylin_exp) begin
                if (errA < 8) $display("    MISMATCH %0s: y_lin=%0d expect %0d", tag, ys_meas, ylin_exp);
                errA = errA + 1;
            end
            $display("    %0s RGB=(%0d,%0d,%0d)  y_he(显示域)=%0d  y_lin(Sobel)=%0d",
                     tag, p[23:16], p[15:8], p[7:0], y_meas, ys_meas);
        end
    endtask

    // ------------------------------------------------------------------ 检查 B
    real    sum0 = 0.0, sum2 = 0.0, sumd = 0.0;
    integer cnt0 = 0,   cnt2 = 0,   cntd = 0;
    integer frm0 = 0,   frm2 = 0;      // 帧计数：第 1 帧 CDF 还空着（HE 输出全 0），必须跳过

    function real diff3(input [23:0] a, input [23:0] b);
        integer dr, dg, db;
        begin
            dr = (a[23:16] > b[23:16]) ? (a[23:16]-b[23:16]) : (b[23:16]-a[23:16]);
            dg = (a[15: 8] > b[15: 8]) ? (a[15: 8]-b[15: 8]) : (b[15: 8]-a[15: 8]);
            db = (a[ 7: 0] > b[ 7: 0]) ? (a[ 7: 0]-b[ 7: 0]) : (b[ 7: 0]-a[ 7: 0]);
            diff3 = dr + dg + db;
        end
    endfunction

    always @(posedge clk) begin
        if (o0_v) begin
            if (o0_u) frm0 <= frm0 + 1;
            // frm0==1 时正是第 1 帧（CDF 还空着），要等第 2 帧 frm0==2 才统计
            if (frm0 >= 2) begin sum0 = sum0 + satv(o0_data); cnt0 = cnt0 + 1; end
        end
        if (o2_v) begin
            if (o2_u) frm2 <= frm2 + 1;
            if (frm2 >= 2) begin
                sum2 = sum2 + satv(o2_data); cnt2 = cnt2 + 1;
                sumd = sumd + diff3(o0_data, o2_data); cntd = cntd + 1;
            end
        end
    end

    task send_quad;
        integer r, c;
        begin
            for (r = 0; r < H; r = r + 1)
                for (c = 0; c < W; c = c + 1) begin
                    @(posedge clk);
                    tvalid <= 1'b1;
                    tuser  <= (r == 0) && (c == 0);
                    tlast  <= (c == W-1);
                    if (r < H/2) tdata <= (c < W/2) ? {8'd200, 8'd60, 8'd55}    // 红
                                                   : {8'd60, 8'd140, 8'd75};    // 绿
                    else         tdata <= (c < W/2) ? {8'd45, 8'd80, 8'd150}    // 蓝
                                                   : {8'd205, 8'd165, 8'd140};  // 肤色
                end
            @(posedge clk);
            tvalid <= 1'b0; tuser <= 1'b0; tlast <= 1'b0; tdata <= 24'd0;
        end
    endtask

    real sat0, sat2;
    initial begin
        repeat (10) @(posedge clk);
        rst_n = 1;
        repeat (40) @(posedge clk);
        force u_m0.display_mode = 3'd0;
        force u_m2.display_mode = 3'd2;

        // ---------------- 检查 A：8 个代表色 ----------------
        $display("");
        $display("=== 检查A: 直方图链是否已切到显示域 (y_he 应为 gamma 后的 Y) ===");
        chk_color(24'hC83C37, "red   ");   // 200,60,55
        chk_color(24'h3C8C4B, "green ");   // 60,140,75
        chk_color(24'h2D5096, "blue  ");   // 45,80,150
        chk_color(24'hCDA58C, "skin  ");   // 205,165,140
        chk_color(24'h289028, "pureG ");   // 40,144,40
        chk_color(24'h0A0A0A, "dark  ");   // 10,10,10 (低于黑电平)
        chk_color(24'hF0F0F0, "white ");   // 240,240,240
        chk_color(24'h64785A, "olive ");   // 100,120,90

        // ---------------- 检查 B：四色块, 模式0 vs 模式2 ----------------
        $display("");
        $display("=== 检查B: 模式0 与 模式2 的平均饱和度 (同一张四色块图) ===");
        send_quad();                    // 帧1: 建直方图
        repeat (900) @(posedge clk);
        send_quad();                    // 帧2: 统计输出
        repeat (300) @(posedge clk);

        sat0 = (cnt0 > 0) ? sum0 / cnt0 : 0.0;
        sat2 = (cnt2 > 0) ? sum2 / cnt2 : 0.0;

        $display("    模式0 (原图+gamma)            : 平均饱和度 %.3f  (%0d 像素)", sat0, cnt0);
        $display("    模式2 (显示域HE+色度补偿+降噪): 平均饱和度 %.3f  (%0d 像素)", sat2, cnt2);
        $display("    比值 模式2/模式0 = %.3f", sat2 / sat0);
        $display("      (只做 L1 时约 1.7 = 发蓝；L1 之前约 0.55 = 发灰；现在应 ≈1.0)");
        $display("    与模式0 的逐像素色差 |dR|+|dG|+|dB| 平均 = %.1f 级 (每通道 %.1f 级)",
                 sumd / cntd, sumd / cntd / 3.0);

        $display("");
        $display("=== 结果 ===");
        $display("    检查A 色调域 : %0d 项, %0d 错误  %0s", nA, errA, (errA == 0) ? "PASS" : "FAIL");
        $display("    检查B 颜色   : 饱和度比 %.2f  %0s",
                 sat2 / sat0,
                 ((sat2 >= 0.92 * sat0) && (sat2 <= 1.15 * sat0)) ? "PASS" : "FAIL");
        $display("");
        if (errA == 0 && sat2 >= 0.92 * sat0 && sat2 <= 1.15 * sat0)
            $display("    >>> ALL PASS");
        else
            $display("    >>> FAIL");
        $finish;
    end

endmodule
