`timescale 1ns / 1ps
// 诊断 TB：定位 cartoon_top 链路中 tlast 在哪一级丢失
// 不干扰工程，仅用于本回合分析。用 iverilog 复现 Vivado 波形现象。

module tb_diag;

    // 与 prj/cartoon/cartoon_top_tb.v 完全一致
    parameter WIDTH           = 96;
    parameter HEIGHT          = 64;
    parameter TOTAL_PIXELS    = WIDTH * HEIGHT;
    parameter CLK_PERIOD      = 20;
    parameter SOBEL_THRESHOLD = 60;
    parameter QUANT_BITS      = 4;

    reg         I_clk;
    reg         I_rst_n;
    reg         I_tlast;
    reg         I_tuser;
    reg  [23:0] I_tdata;
    reg         I_tvalid;
    reg         I_tready;

    wire [23:0] O_tdata;
    wire        O_tlast;
    wire        O_tuser;
    wire        O_tvalid;
    wire        O_tready;

    reg [23:0] img_mem [0:TOTAL_PIXELS-1];

    cartoon_top #(
        .IMG_WIDTH       (WIDTH),
        .IMG_HEIGHT      (HEIGHT),
        .SOBEL_THRESHOLD (SOBEL_THRESHOLD),
        .QUANT_BITS      (QUANT_BITS)
    ) u_cartoon_top (
        .I_clk    (I_clk),
        .I_rst_n  (I_rst_n),
        .I_tlast  (I_tlast),
        .I_tuser  (I_tuser),
        .I_tdata  (I_tdata),
        .I_tvalid (I_tvalid),
        .I_tready (I_tready),
        .O_tdata  (O_tdata),
        .O_tlast  (O_tlast),
        .O_tuser  (O_tuser),
        .O_tvalid (O_tvalid),
        .O_tready (O_tready)
    );

    // 内部各节点探测
    wire tlast_ycbcr = u_cartoon_top.tlast_ycbcr;
    wire tlast_sobel = u_cartoon_top.tlast_sobel;
    wire tlast_blend = u_cartoon_top.tlast_blend;
    wire [3:0] tlast_shift = u_cartoon_top.u_Sobel_edge.tlast_shift;
    wire [1:0] tlast_dly    = u_cartoon_top.u_RGB888_YCbCr444.tlast_dly;

    initial I_clk = 0;
    always #(CLK_PERIOD/2) I_clk = ~I_clk;

    integer tlast_pulse_I      = 0;
    integer tlast_pulse_ycbcr  = 0;
    integer tlast_pulse_sobel  = 0;
    integer tlast_pulse_blend  = 0;
    integer tlast_pulse_O      = 0;

    // 统计各级 tlast 脉冲数
    always @(posedge I_clk) begin
        if (I_tlast)      tlast_pulse_I     <= tlast_pulse_I + 1;
        if (tlast_ycbcr)  tlast_pulse_ycbcr <= tlast_pulse_ycbcr + 1;
        if (tlast_sobel)  tlast_pulse_sobel <= tlast_pulse_sobel + 1;
        if (tlast_blend)  tlast_pulse_blend <= tlast_pulse_blend + 1;
        if (O_tlast)      tlast_pulse_O     <= tlast_pulse_O + 1;
    end

    // 打印前 12 个 tlast-相关时刻（含行号）
    integer cnt;
    always @(posedge I_clk) begin
        if (I_tlast || tlast_ycbcr || tlast_sobel || tlast_blend || O_tlast) begin
            if (cnt < 20) begin
                $display("t=%0t  I_%b  ycbcr=%b  sobel=%b  blend=%b  O=%b | shift=%b dly=%b O_valid=%b",
                    $time, I_tlast, tlast_ycbcr, tlast_sobel, tlast_blend, O_tlast,
                    tlast_shift, tlast_dly, O_tvalid);
                cnt = cnt + 1;
            end
        end
    end

    task send_frame;
        integer r, c, idx;
        begin
            idx = 0;
            for (r = 0; r < HEIGHT; r = r + 1) begin
                for (c = 0; c < WIDTH; c = c + 1) begin
                    @(posedge I_clk);
                    I_tvalid <= 1'b1;
                    I_tuser  <= (r == 0 && c == 0) ? 1'b1 : 1'b0;
                    I_tlast  <= (c == WIDTH - 1)  ? 1'b1 : 1'b0;
                    I_tdata  <= img_mem[idx];
                    idx = idx + 1;
                end
            end
            @(posedge I_clk);
            I_tvalid <= 1'b0;
            I_tlast  <= 1'b0;
            I_tuser  <= 1'b0;
            I_tdata  <= 24'd0;
        end
    endtask

    integer idx0;
    initial begin
        $readmemh("src_img.txt", img_mem);
        I_rst_n  = 0;
        I_tvalid = 0;
        I_tuser  = 0;
        I_tlast  = 0;
        I_tdata  = 0;
        I_tready = 1;
        #(CLK_PERIOD * 10);
        I_rst_n = 1;
        #(CLK_PERIOD * 10);
        $display("=== sending frame ===");
        send_frame();
        #(CLK_PERIOD * 200);
        $display("===================");
        $display("tlast pulses: I=%0d ycbcr=%0d sobel=%0d blend=%0d O=%0d",
                 tlast_pulse_I, tlast_pulse_ycbcr, tlast_pulse_sobel, tlast_pulse_blend, tlast_pulse_O);
        $display("===================");
        $finish;
    end

endmodule
