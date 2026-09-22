//=============================================================================
// head_dec_tb.v —— 解码对拍：喂金标准 head_real.hex → 全局最高分 1 框
// 基准: matlab/cnn_detector/out/golden/boxes.txt 的 int8 行
//       [70.8983 0.0000 30.3397 29.6821] score 0.7590
// 验收: 整数框与金标准四舍五入值（71, 0, 30, 30）各差 ≤1 px；分数 Q12 ≈ 3109
// 运行（仓库根目录）:
//   vlog -work work_cnn lab_ex1_mipi_hdmi_SC500_720P+vpp/lab_ex1_mipi_hdmi+vpp/user_source/hdl_source/cnn/cnn_head_dec.v sim/head_dec_tb.v
//   vsim -c work_cnn.head_dec_tb -do "run -all; quit -f"
//=============================================================================
`timescale 1ns/1ps

module head_dec_tb;

    localparam NPX = 576, NCH = 15;
    localparam EXP_X1 = 71, EXP_Y1 = 0, EXP_W = 30, EXP_H = 30;   // 金标准 int8 框四舍五入
    localparam EXP_SCORE = 3109;                                    // round(0.7590*4096)

    reg clk=0, rst_n=0;
    reg ivalid=0;
    reg [239:0] idata=0;
    wire ovalid;
    wire [7:0] ox1, oy1, ow, oh;
    wire [15:0] oscore;

    reg [31:0] gold [0:NPX*NCH-1];
    integer p, ch, cyc, fails, got_valid;
    integer dx, dy, dw, dh;

    cnn_head_dec #(
        .LUT_MEM("sim/cnn_data/lut_exp.mem"),
        .SCORE_TH_Q12(12'd615)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .I_valid(ivalid), .I_data(idata),
        .O_valid(ovalid), .O_x1(ox1), .O_y1(oy1), .O_w(ow), .O_h(oh), .O_score_q12(oscore)
    );

    always #5 clk = ~clk;
    initial $readmemh("sim/cnn_data/head_real.hex", gold);

    initial begin
        rst_n=0; ivalid=0;
        repeat (5) @(posedge clk); rst_n=1; repeat (2) @(posedge clk);

        $display("=========================================================");
        $display(" head decode check  (golden boxes.txt int8: 70.8983 0.0000 30.3397 29.6821)");

        // ---- 调试: 金标准中应获胜的候选（框中心 cx=86.05, cy=14.84 → gy=3, gx=21 → px=117, 锚3）----
        $display(" debug px117 ch10..14 (to tx ty tw th): %0d %0d %0d %0d %0d",
                 $signed(gold[3 + 18*21 + NPX*10][15:0]),
                 $signed(gold[3 + 18*21 + NPX*11][15:0]),
                 $signed(gold[3 + 18*21 + NPX*12][15:0]),
                 $signed(gold[3 + 18*21 + NPX*13][15:0]),
                 $signed(gold[3 + 18*21 + NPX*14][15:0]));

        // ---- 喂 576 像素（行主序，每像素 15 通道 Q12 打包 240bit）----
        for (p=0; p<NPX; p=p+1) begin
            idata = 0;
            for (ch=0; ch<NCH; ch=ch+1)
                idata[16*ch +: 16] = gold[(p/32) + 18*(p%32) + NPX*ch][15:0];
            @(posedge clk); ivalid=1;
            @(posedge clk); ivalid=0;
            repeat (10) @(posedge clk);   // 每 12 拍 1 像素（解码 3 锚 x 3 拍流水）
        end

        // ---- 等 O_valid ----
        got_valid = 0;
        for (cyc=0; cyc<2000; cyc=cyc+1) begin
            @(posedge clk);
            if (ovalid === 1'b1) begin
                got_valid = 1;
                $display(" 检出框: [%0d %0d %0d %0d]  score_q12 = %0d", ox1, oy1, ow, oh, oscore);
                $display(" debug dut.best_valid=%b dut.best_score=%0d", dut.best_valid, dut.best_score);
                cyc = 2000;
            end
        end

        fails = 0;
        if (!got_valid) begin
            $display(" RESULT: FAIL  -- 未检出 O_valid");
            fails = 1;
        end else begin
            dx = $signed({1'b0, ox1}) - EXP_X1;
            dy = $signed({1'b0, oy1}) - EXP_Y1;
            dw = $signed({1'b0, ow})  - EXP_W;
            dh = $signed({1'b0, oh})  - EXP_H;
            if (dx < -1 || dx > 1) begin
                $display("  FAIL x1 = %0d（期望 %0d ±1）", ox1, EXP_X1); fails = fails+1; end
            if (dy < -1 || dy > 1) begin
                $display("  FAIL y1 = %0d（期望 %0d ±1）", oy1, EXP_Y1); fails = fails+1; end
            if (dw < -1 || dw > 1) begin
                $display("  FAIL w = %0d（期望 %0d ±1）", ow, EXP_W); fails = fails+1; end
            if (dh < -1 || dh > 1) begin
                $display("  FAIL h = %0d（期望 %0d ±1）", oh, EXP_H); fails = fails+1; end
            if (oscore < EXP_SCORE-10 || oscore > EXP_SCORE+10) begin
                $display("  FAIL score_q12 = %0d（期望 %0d ±10）", oscore, EXP_SCORE); fails = fails+1; end
        end

        if (fails == 0)
            $display(" RESULT: PASS  -- 框与金标准一致（±1 px）");
        else
            $display(" RESULT: FAIL  -- %0d 项不符", fails);
        $finish;
    end

endmodule
