`timescale 1ns / 1ps
//=============================================================================
// tb_cnn_ds10.v —— cnn_ds10 独立参考模型验证
//
// 目的：验证这次为省资源做的两处改动没有改变功能：
//   ① 删掉"条纹末 for 循环清 bank"，改成 by==0 && bx==0 时直接装载累加器
//   ② avg() 从 3 个乘法器改成 1 个乘法器分 3 拍复用
//
// 做法：tb 把整帧 1280x720 像素存下来，在 DUT 每输出一个块时，
//   **独立地从帧缓存里重新算 10x10 块和**，再用同一个定点式 ÷100，逐位比较。
//   （不是镜像 DUT 的累加过程，所以能查出累加/装载的逻辑错误）
//=============================================================================
module tb_cnn_ds10;

    localparam IN_W = 1280, IN_H = 720;
    localparam OUT_W = 128, OUT_H = 72;

    reg         clk = 1'b0;
    reg         rst_n;
    reg         I_tvalid, I_tuser, I_tlast;
    reg  [23:0] I_tdata;

    wire        O_tvalid, O_tuser, O_tlast;
    wire [23:0] O_tdata;
    wire [7:0]  O_x, O_y;

    // 整帧缓存
    reg [23:0] frame [0:IN_W*IN_H-1];

    integer nout, nerr, nuser, nlast;
    integer x, y;

    // ---- DUT ----
    cnn_ds10 #(
        .IN_W(IN_W), .IN_H(IN_H), .SCALE(10), .OUT_W(OUT_W), .OUT_H(OUT_H)
    ) dut (
        .I_clk(clk), .I_rst_n(rst_n),
        .I_tvalid(I_tvalid), .I_tuser(I_tuser), .I_tlast(I_tlast), .I_tdata(I_tdata),
        .O_tvalid(O_tvalid), .O_tuser(O_tuser), .O_tlast(O_tlast), .O_tdata(O_tdata),
        .O_x(O_x), .O_y(O_y)
    );

    always #5 clk = ~clk;

    // ---- 激励：1280x720，行间插 5 拍消隐 ----
    initial begin
        I_tvalid = 1'b0; I_tuser = 1'b0; I_tlast = 1'b0; I_tdata = 24'd0;
        rst_n = 1'b0;
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        for (y = 0; y < IN_H; y = y + 1) begin
            repeat (5) @(posedge clk);              // 行消隐
            for (x = 0; x < IN_W; x = x + 1) begin
                I_tdata  = { (x*7  + y*13 + 11) & 8'hFF,
                             (x*3  + y*5  + 40) & 8'hFF,
                             (x    + y*2  +  7) & 8'hFF };
                frame[y*IN_W + x] = I_tdata;
                I_tvalid = 1'b1;
                I_tuser  = (x == 0 && y == 0);
                I_tlast  = (x == IN_W-1);
                @(posedge clk);
            end
            I_tvalid = 1'b0; I_tuser = 1'b0; I_tlast = 1'b0;
        end
        repeat (4000) @(posedge clk);               // 等最后一轮排空
        $display("==================================================");
        $display(" cnn_ds10 验证结果");
        $display("   输出块数 : %0d  (期望 %0d)", nout, OUT_W*OUT_H);
        $display("   tuser 数 : %0d  (期望 1)", nuser);
        $display("   tlast 数 : %0d  (期望 %0d)", nlast, OUT_H);
        $display("   数据错误 : %0d", nerr);
        if (nout == OUT_W*OUT_H && nerr == 0 && nuser == 1 && nlast == OUT_H)
            $display(" >>> PASS");
        else
            $display(" >>> FAIL");
        $display("==================================================");
        $finish;
    end

    // ---- 独立检查器：从帧缓存重算 10x10 块平均 ----
    integer bx2, by2;
    integer sr, sg, sb, er, eg, eb;
    reg [23:0] p2;
    reg [23:0] exp24;

    always @(posedge clk) begin
        if (rst_n && O_tvalid) begin
            sr = 0; sg = 0; sb = 0;
            for (by2 = 0; by2 < 10; by2 = by2 + 1) begin
                for (bx2 = 0; bx2 < 10; bx2 = bx2 + 1) begin
                    p2 = frame[(O_y*10 + by2)*IN_W + O_x*10 + bx2];
                    sr = sr + p2[23:16];
                    sg = sg + p2[15: 8];
                    sb = sb + p2[ 7: 0];
                end
            end
            er = (sr * 10486 + 524288) >> 20;
            eg = (sg * 10486 + 524288) >> 20;
            eb = (sb * 10486 + 524288) >> 20;
            exp24 = {er[7:0], eg[7:0], eb[7:0]};

            nout = nout + 1;
            if (O_tuser) nuser = nuser + 1;
            if (O_tlast) nlast = nlast + 1;

            if (exp24 !== O_tdata) begin
                nerr = nerr + 1;
                if (nerr <= 12)
                    $display("  [错] oy=%0d ox=%0d 期望 %06x 实得 %06x  (块和 R=%0d G=%0d B=%0d)",
                             O_y, O_x, exp24, O_tdata, sr, sg, sb);
            end
            if (O_x !== ((nout-1) % OUT_W))
                $display("  [错] O_x 序列不对: nout=%0d O_x=%0d", nout, O_x);
            if (O_y !== ((nout-1) / OUT_W))
                $display("  [错] O_y 序列不对: nout=%0d O_y=%0d", nout, O_y);
        end
    end

    initial begin
        nout = 0; nerr = 0; nuser = 0; nlast = 0;
    end

endmodule
