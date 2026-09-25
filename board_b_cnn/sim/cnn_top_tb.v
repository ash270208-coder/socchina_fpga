//=============================================================================
// cnn_top_tb.v —— 整链对拍：x0_input.hex 流 → CNN 前向 → 唯一框
// 基准: matlab boxes.txt 的 int8 框 [70.8983 0 30.3397 29.6821]（128x72 空间）
// 验收: 整数框 (71,0,30,30) 各 ±1 px；分数 Q12 ≈ 3109
// 运行（仓库根目录）:
//   vlog -work work_cnn lab_ex1_mipi_hdmi_SC500_720P+vpp/lab_ex1_mipi_hdmi+vpp/user_source/hdl_source/cnn/conv1_frame.v .../conv_frame.v .../head_frame.v .../cnn_head_dec.v .../cnn_top.v sim/cnn_top_tb.v
//   vsim -c work_cnn.cnn_top_tb -do "run -all; quit -f"
//=============================================================================
`timescale 1ns/1ps

module cnn_top_tb;

    localparam IW=128, IH=72, NPX = IW*IH, NIMG = NPX*3;
    localparam EXP_X1 = 71, EXP_Y1 = 0, EXP_W = 30, EXP_H = 30;
    localparam EXP_SCORE = 3109;

    reg clk=0, rst_n=0;
    reg tvalid=0, tuser=0;
    reg [23:0] tdata=0;
    wire busy;
    wire ovalid;
    wire [7:0] ox1, oy1, ow, oh;
    wire [15:0] oscore;

    reg [7:0] img [0:NIMG-1];
    integer r, c, cyc, got_valid, fails, dx, dy, dw, dh;

    cnn_top #(.IMG_W(IW), .IMG_H(IH)) dut (
        .clk(clk), .rst_n(rst_n),
        .I_tvalid(tvalid), .I_tuser(tuser), .I_tdata(tdata),
        .O_busy(busy),
        .O_valid(ovalid), .O_x1(ox1), .O_y1(oy1), .O_w(ow), .O_h(oh), .O_score(oscore)
    );

    always #5 clk = ~clk;
    initial $readmemh("sim/cnn_data/x0_input.hex", img);

    initial begin
        rst_n=0; tvalid=0; tuser=0;
        repeat (5) @(posedge clk); rst_n=1; repeat (2) @(posedge clk);

        $display("=========================================================");
        $display(" cnn_top whole-chain check  (input x0_input.hex, golden box 70.9 0 30.3 29.7)");

        // ---- 喂 128x72 RGB 流（列主序金标准 → 行主序流，每 4 拍 1 像素）----
        tuser=1; @(posedge clk); tuser=0;
        for (r=0; r<IH; r=r+1) begin
            for (c=0; c<IW; c=c+1) begin
                tdata = {img[0*NPX + c*IH + r],   // R 平面
                         img[1*NPX + c*IH + r],   // G 平面
                         img[2*NPX + c*IH + r]};  // B 平面
                tvalid=1;
                @(posedge clk); tvalid=0;
                repeat (3) @(posedge clk);
            end
        end

        // ---- 等 O_valid（链长约 1.6M 拍，留裕量）----
        got_valid = 0;
        for (cyc=0; cyc<2600000; cyc=cyc+1) begin
            @(posedge clk);
            if (ovalid === 1'b1) begin
                got_valid = 1;
                $display(" 检出框: [%0d %0d %0d %0d]  score_q12 = %0d（耗时 %0d 拍）", ox1, oy1, ow, oh, oscore, cyc);
                cyc = 2600000;
            end
        end

        fails = 0;
        if (!got_valid) begin
            $display(" RESULT: FAIL  -- 超时未检出 O_valid");
            fails = 1;
        end else begin
            dx = $signed({1'b0, ox1}) - EXP_X1;
            dy = $signed({1'b0, oy1}) - EXP_Y1;
            dw = $signed({1'b0, ow})  - EXP_W;
            dh = $signed({1'b0, oh})  - EXP_H;
            if (dx < -1 || dx > 1) begin $display("  FAIL x1=%0d（期望 %0d ±1）", ox1, EXP_X1); fails=fails+1; end
            if (dy < -1 || dy > 1) begin $display("  FAIL y1=%0d（期望 %0d ±1）", oy1, EXP_Y1); fails=fails+1; end
            if (dw < -1 || dw > 1) begin $display("  FAIL w=%0d（期望 %0d ±1）", ow, EXP_W); fails=fails+1; end
            if (dh < -1 || dh > 1) begin $display("  FAIL h=%0d（期望 %0d ±1）", oh, EXP_H); fails=fails+1; end
            if (oscore < EXP_SCORE-10 || oscore > EXP_SCORE+10) begin $display("  FAIL score=%0d（期望 %0d ±10）", oscore, EXP_SCORE); fails=fails+1; end
        end

        if (fails == 0)
            $display(" RESULT: PASS  -- 整链框与金标准一致（±1 px）");
        else
            $display(" RESULT: FAIL  -- %0d 项不符", fails);
        $finish;
    end

endmodule
