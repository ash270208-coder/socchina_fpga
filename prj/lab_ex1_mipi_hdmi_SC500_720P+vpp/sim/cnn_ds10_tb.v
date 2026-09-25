//=============================================================================
// cnn_ds10_tb.v —— ÷10 块平均降采样功能验证（20x20 → 2x2 小帧）
// 模式 A: 常数图 RGB=(10,100,200) → 4 个输出块全部 (10,100,200)
// 模式 B: 斜坡图 v=(x mod 10)+10*(y mod 10) → 每块和 4950，平均 49.5 → 50
// 同时检查 O_x/O_y/tuser/tlast 时序（边喂流边检查 + 帧尾排空采集）
//=============================================================================
`timescale 1ns/1ps

module cnn_ds10_tb;

    localparam IW=20, IH=20, OW=2, OH=2;

    reg clk=0, rst_n=0;
    reg tvalid=0, tuser=0, tlast=0;
    reg [23:0] tdata=0;
    wire ovalid, ouser, olast;
    wire [23:0] odata;
    wire [7:0] ox, oy;

    cnn_ds10 #(.IN_W(IW), .IN_H(IH), .SCALE(10), .OUT_W(OW), .OUT_H(OH)) dut (
        .I_clk(clk), .I_rst_n(rst_n),
        .I_tvalid(tvalid), .I_tuser(tuser), .I_tlast(tlast), .I_tdata(tdata),
        .O_tvalid(ovalid), .O_tuser(ouser), .O_tlast(olast),
        .O_tdata(odata), .O_x(ox), .O_y(oy)
    );

    always #5 clk = ~clk;
    integer x, y, cnt, errs, checks, k;

    // ---- 采集一个输出块并校验（模式 A 与 B 用不同期望值）----
    task check_block;
        input [23:0] exp_val;
        begin
            checks = checks+1;
            if (odata !== exp_val || ox !== cnt%OW || oy !== cnt/OW ||
                (cnt==0 ? ouser!==1'b1 : ouser!==1'b0) ||
                (ox==OW-1 ? olast!==1'b1 : olast!==1'b0)) begin
                errs = errs+1;
                $display("  FAIL 块%0d: data=%h exp=%h ox=%0d oy=%0d user=%b last=%b",
                         cnt, odata, exp_val, ox, oy, ouser, olast);
            end
            cnt = cnt+1;
        end
    endtask

    initial begin
        rst_n=0; tvalid=0; tuser=0; tlast=0;
        repeat (5) @(posedge clk); rst_n=1; repeat (2) @(posedge clk);
        errs = 0; checks = 0;

        $display("=========================================================");
        $display(" cnn_ds10 functional check (20x20 -> 2x2, SCALE=10)");

        // ================= 模式 A: 常数图 =================
        $display("--- 模式 A: 常数 RGB=(10,100,200) ---");
        tuser=1; tdata = 24'h0A64C8; @(posedge clk); tuser=0;
        cnt = 0;
        for (y=0; y<IH; y=y+1) begin
            for (x=0; x<IW; x=x+1) begin
                tvalid=1; tlast = (x == IW-1);
                @(posedge clk);
                @(negedge clk);
                if (ovalid === 1'b1) check_block(24'h0A64C8);
            end
        end
        tvalid=0; tlast=0;
        for (k=0; k<OW*4+4; k=k+1) begin      // 帧尾排空（4 拍/块）
            @(negedge clk);
            if (ovalid === 1'b1) check_block(24'h0A64C8);
        end

        // ================= 模式 B: 斜坡图 =================
        $display("--- 模式 B: 斜坡 v=(x mod 10)+10*(y mod 10)，块和 4950，平均 49.5 -> 50 ---");
        tuser=1; @(posedge clk); tuser=0;
        cnt = 0;
        for (y=0; y<IH; y=y+1) begin
            for (x=0; x<IW; x=x+1) begin
                tdata = {8'd0, 8'd0, (x%10) + 10*(y%10)};
                tvalid=1; tlast = (x == IW-1);
                @(posedge clk);
                @(negedge clk);
                if (ovalid === 1'b1) check_block(24'h000032);
            end
        end
        tvalid=0; tlast=0;
        for (k=0; k<OW*4+4; k=k+1) begin      // 帧尾排空（4 拍/块）
            @(negedge clk);
            if (ovalid === 1'b1) check_block(24'h000032);
        end

        $display("---------------------------------------------------------");
        if (errs == 0 && checks == 2*OW*OH)
            $display(" RESULT: PASS  -- %0d 个输出块全部正确", checks);
        else
            $display(" RESULT: FAIL  -- %0d 项不符（采集 %0d/%0d）", errs, checks, 2*OW*OH);
        $finish;
    end

endmodule
