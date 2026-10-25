`timescale 1ns/1ps
// 一次性探针：打印四色块图上 mode0 / mode2 的实际输出，以及 mode2 内部
//   y_he_d[2] (HE 前的 Y) / y_equ (HE 后的 Y') / k_q8 / cb_d[2] / cb_comp
module vpp_top_probe_tb;
    localparam W = 64, H = 64, CLK = 10;

    reg clk = 0; always #(CLK/2) clk = ~clk;
    reg rst_n = 0;
    reg [1:0] button = 2'b11;
    reg tvalid = 0, tuser = 0, tlast = 0, tdest = 0, tready = 1;
    reg [23:0] tdata = 0;

    wire [23:0] o0, o2;
    wire o0v,o0u,o0l,o2v,o2u,o2l;
    wire [2:0] m0, m2;

    vpp_top #(.IMG_WIDTH(W), .IMG_HEIGHT(H), .SOBEL_THRESHOLD(60)) u0 (
        .I_button(button), .I_clk(clk), .I_rst_n(rst_n),
        .I_tlast(tlast), .I_tuser(tuser), .I_tdata(tdata), .I_tvalid(tvalid),
        .I_tdest(tdest), .I_tready(tready),
        .O_tdata(o0), .O_tlast(o0l), .O_tuser(o0u), .O_tvalid(o0v),
        .O_tready(), .O_display_mode(m0));

    vpp_top #(.IMG_WIDTH(W), .IMG_HEIGHT(H), .SOBEL_THRESHOLD(60)) u2 (
        .I_button(button), .I_clk(clk), .I_rst_n(rst_n),
        .I_tlast(tlast), .I_tuser(tuser), .I_tdata(tdata), .I_tvalid(tvalid),
        .I_tdest(tdest), .I_tready(tready),
        .O_tdata(o2), .O_tlast(o2l), .O_tuser(o2u), .O_tvalid(o2v),
        .O_tready(), .O_display_mode(m2));

    // 内部探针（每来一个 mode2 输出像素，把它这一拍内部的值一起打出来）
    reg [7:0] p_cb1, p_cr1, p_cb2, p_cr2, p_ko;
    always @(posedge clk) begin
        p_ko  <= u2.u_chroma_comp.k_q8[7:0];
        p_cb1 <= u2.he_cb_comp;
        p_cr1 <= u2.he_cr_comp;
        p_cb2 <= u2.cb_d[2];
        p_cr2 <= u2.cr_d[2];
    end

    integer cnt = 0, frame = 0;
    always @(posedge clk) begin
        if (o2v) begin
            if (o2u) begin cnt <= 0; frame <= frame + 1; end
            else     cnt <= cnt + 1;
            if (frame >= 1 && ((cnt % 64) == 5 || (cnt % 64) == 37) &&
                ((cnt / 64) == 5 || (cnt / 64) == 37) && cnt < 4096)
                $display("  out#%4d r=%2d c=%2d | mode0=%02X%02X%02X  mode2=%02X%02X%02X",
                         cnt, cnt/64, cnt%64, o0[23:16], o0[15:8], o0[7:0],
                         o2[23:16], o2[15:8], o2[7:0]);
        end
    end

    // 同一拍把 chroma_comp 的输入/输出打出来
    integer k = 0;
    always @(posedge clk) begin
        if (u2.he_v_comp && frame >= 1 && u2.y_he_d[2] > 60 && u2.y_equ_tdata > 0 && k < 14) begin
            k <= k + 1;
            $display("    [comp] y_old=%3d y_new=%3d k_q8=%3d cb=%3d->%3d  cr=%3d->%3d",
                     u2.y_he_d[2], u2.y_equ_tdata, u2.u_chroma_comp.k_q8,
                     u2.cb_d[2], u2.he_cb_comp, u2.cr_d[2], u2.he_cr_comp);
        end
    end

    task send_quad; integer r,c; begin
        for (r=0;r<H;r=r+1) for (c=0;c<W;c=c+1) begin
            @(posedge clk); tvalid<=1; tuser<=(r==0)&&(c==0); tlast<=(c==W-1);
            if (r < H/2) tdata <= (c < W/2) ? {8'd200,8'd60,8'd55} : {8'd60,8'd140,8'd75};
            else         tdata <= (c < W/2) ? {8'd45,8'd80,8'd150} : {8'd205,8'd165,8'd140};
        end
        @(posedge clk); tvalid<=0; tuser<=0; tlast<=0;
    end endtask

    initial begin
        repeat (10) @(posedge clk); rst_n = 1; repeat (40) @(posedge clk);
        force u0.display_mode = 3'd0;
        force u2.display_mode = 3'd2;
        send_quad(); repeat (900) @(posedge clk);
        send_quad(); repeat (300) @(posedge clk);
        $display("  (quad: 左上红 200,60,55 | 右上绿 60,140,75 | 左下蓝 45,80,150 | 右下肤色 205,165,140)");
        $finish;
    end
endmodule
