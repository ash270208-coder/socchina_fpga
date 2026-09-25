`timescale 1ns/1ps
// ===========================================================================
// vpp_top 模式 2 时序对齐验证 (E+G 改动后)
//
//   风险点: 模式 2 链路新加了 gamma(0拍) + chroma_nr(3拍)，并把 he_rgb_d
//   的补偿从 7 拍改成 4 拍。如果哪一段算错一拍，模式 2 的画面会相对其它档
//   横移 1 个像素。
//
//   方法: 同一激励喂两个 vpp_top 实例(一个 force 成模式0, 一个 force 成模式2)，
//         图案 = 每行左半暗(40)右半亮(200) -> 输出台阶必须落在同一个 beat。
//         打印第一行的逐 beat 输出对比。
// ===========================================================================
module vpp_top_aln_tb;
    localparam W = 64;
    localparam H = 64;
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

    // 每行内 beat 计数 + 第一行采样
    integer beat0, beat2;
    reg [23:0] line0 [0:W-1];
    reg [23:0] line2 [0:W-1];
    reg        first0, first2;

    always @(posedge clk) begin
        if (o0_v) begin
            if (o0_u) begin beat0 <= 0; first0 <= 1'b1; end
            else       beat0 <= beat0 + 1;
            if (first0 && beat0 < W) line0[beat0] <= o0_data;
            if (o0_l) first0 <= 1'b0;
        end
        if (o2_v) begin
            if (o2_u) begin beat2 <= 0; first2 <= 1'b1; end
            else       beat2 <= beat2 + 1;
            if (first2 && beat2 < W) line2[beat2] <= o2_data;
            if (o2_l) first2 <= 1'b0;
        end
    end

    integer i;
    task send_frame;
        integer r, c;
        reg [23:0] px;
        begin
            for (r = 0; r < H; r = r + 1)
                for (c = 0; c < W; c = c + 1) begin
                    @(posedge clk);
                    tvalid <= 1'b1;
                    tuser  <= (r == 0) && (c == 0);
                    tlast  <= (c == W-1);
                    // 左半暗(40) 右半亮(200)
                    if (c < W/2) px = {8'd40,  8'd40,  8'd40};
                    else         px = {8'd200, 8'd200, 8'd200};
                    tdata <= px;
                end
            @(posedge clk);
            tvalid <= 1'b0; tuser <= 1'b0; tlast <= 1'b0; tdata <= 24'd0;
        end
    endtask

    initial begin
        beat0 = 0; beat2 = 0; first0 = 0; first2 = 0;
        for (i = 0; i < W; i = i + 1) begin line0[i] = 24'd0; line2[i] = 24'd0; end
        repeat (10) @(posedge clk);
        rst_n = 1;
        repeat (40) @(posedge clk);
        force u_m0.display_mode = 3'd0;   // 原图(伽马)
        force u_m2.display_mode = 3'd2;   // 直方图均衡(已加 gamma+chroma_nr)

        send_frame();      // 帧1: 建直方图
        repeat (900) @(posedge clk);
        send_frame();      // 帧2: 采第一行输出
        repeat (100) @(posedge clk);

        $display("");
        $display("=== vpp_top mode2 alignment test (%0dx%0d, 左暗40/右亮200) ===", W, H);
        $display("  beat |  mode0(R)  |  mode2(R)");
        for (i = 0; i < W; i = i + 1) begin
            if (i <= 2 || (i >= W/2-2 && i <= W/2+2) || i >= W-2)
                $display("%6d | %10d | %10d", i, line0[i][23:16], line2[i][23:16]);
        end
        $display("");
        $display("mode0 display_mode = %0d, mode2 display_mode = %0d", mode0, mode2);
        $display("");
        $finish;
    end
endmodule
