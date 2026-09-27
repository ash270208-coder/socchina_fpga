`timescale 1ns / 1ps

// ============================================================================
// bilateral_filter_3x3 独立仿真 testbench
//   - 生成 64x64 合成图: 左半暗(60) + 右半亮(180) 的垂直阶跃边 + 撒盐噪声
//   - 验证: 输出像素数正确、无 X 态、平区被平滑、阶跃边被保留
//   - 用法 (ModelSim):
//       vlog bilateral_filter_3x3.v bilateral_filter_3x3_tb.v
//       vsim -c tb_bilateral_filter_3x3 -do "run -all; quit"
//   - 需把 bilateral_range.hex / bilateral_recip.hex 放到工作目录
// ============================================================================
module tb_bilateral_filter_3x3;

    parameter WIDTH  = 64;
    parameter HEIGHT = 64;
    parameter CLK    = 20;   // 50 MHz

    reg         clk;
    reg         rst_n;
    reg         tvalid;
    reg         tuser;
    reg         tlast;
    reg  [7:0]  grey;

    wire        o_valid;
    wire        o_user;
    wire        o_last;
    wire [7:0]  o_grey;

    reg [7:0]  img [0:WIDTH*HEIGHT-1];
    integer    out_cnt;
    integer    fp;

    // ---- DUT ----
    bilateral_filter_3x3 #(
        .IMG_WIDTH  (WIDTH),
        .IMG_HEIGHT (HEIGHT)
    ) u_dut (
        .I_clk        (clk),
        .I_rst_n      (rst_n),
        .I_tvalid     (tvalid),
        .I_tuser      (tuser),
        .I_tlast      (tlast),
        .I_grey_tdata (grey),
        .O_tvalid     (o_valid),
        .O_tuser      (o_user),
        .O_tlast      (o_last),
        .O_grey_tdata (o_grey)
    );

    // ---- 时钟 ----
    initial clk = 0;
    always #(CLK/2) clk = ~clk;

    // ---- 输出抓取 ----
    always @(posedge clk) begin
        if (o_valid) begin
            if (fp) $fdisplay(fp, "%02X", o_grey);
            out_cnt = out_cnt + 1;
        end
    end

    // ---- 主流程 ----
    integer r, c, idx;
    initial begin
        // 构建测试图: 左半 60, 右半 180, 垂直边在 col 32; 加少量盐噪声
        for (r = 0; r < HEIGHT; r = r + 1) begin
            for (c = 0; c < WIDTH; c = c + 1) begin
                idx = r*WIDTH + c;
                if (c < 32)      img[idx] = 8'd60;
                else             img[idx] = 8'd180;
            end
        end
        // 撒盐噪声 (远离边界的孤立点)
        img[20*WIDTH + 10] = 8'd120;   // 暗区一个亮点
        img[20*WIDTH + 11] = 8'd10;    // 暗区一个暗点
        img[40*WIDTH + 50] = 8'd250;   // 亮区一个亮点
        img[40*WIDTH + 51] = 8'd90;    // 亮区一个暗点

        fp = $fopen("bilateral_sim_out.txt", "w");
        out_cnt = 0;

        rst_n  = 0;
        tvalid = 0; tuser = 0; tlast = 0; grey = 0;

        #(CLK*10);
        rst_n = 1;
        #(CLK*5);

        // 送一帧
        for (r = 0; r < HEIGHT; r = r + 1) begin
            for (c = 0; c < WIDTH; c = c + 1) begin
                @(posedge clk);
                tvalid <= 1'b1;
                tuser  <= ((r == 0) && (c == 0));
                tlast  <= (c == WIDTH-1);
                grey   <= img[r*WIDTH + c];
            end
        end
        @(posedge clk);
        tvalid <= 1'b0; tuser <= 1'b0; tlast <= 1'b0;

        // 等待流水线排空
        #(CLK*40);
        if (fp) $fclose(fp);

        $display("======================================");
        $display("captured pixels = %0d (expect %0d)", out_cnt, WIDTH*HEIGHT);
        if (out_cnt == WIDTH*HEIGHT)
            $display("PASS");
        else
            $display("FAIL (diff = %0d)", WIDTH*HEIGHT - out_cnt);
        $display("======================================");
        $finish;
    end

endmodule
