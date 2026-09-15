`timescale 1ns / 1ps

module tb_cartoon_top;

    // =========================================================================
    // 2026 嵌赛 FPGA 选题二：卡通化图像风格化处理 — TestBench
    // DUT: cartoon_top (AXI-Stream 视频流输入，卡通化 RGB888 输出)
    // 分辨率: 96 x 64, 时钟: 50MHz (CLK_PERIOD=20ns)
    // =========================================================================

    parameter WIDTH           = 96;
    parameter HEIGHT          = 64;
    parameter TOTAL_PIXELS    = WIDTH * HEIGHT; // 6144
    parameter CLK_PERIOD      = 20;             // 50MHz
    parameter SOBEL_THRESHOLD = 60;
    parameter QUANT_BITS      = 4;

    // =========================================================================
    // 信号声明
    // =========================================================================
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
    integer fp_out;
    integer out_pixel_cnt = 0;

    // =========================================================================
    // 注: 本工程卡通链 RTL 不实例化安路 PH1P_PHY_GSR 原语，
    //     故无需空例化，避免 iverilog 报 Unknown module type。
    // =========================================================================

    // =========================================================================
    // DUT 例化
    // =========================================================================
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

    // =========================================================================
    // 时钟生成: 50MHz (CLK_PERIOD=20ns, 半周期翻转)
    // =========================================================================
    initial I_clk = 0;
    always #(CLK_PERIOD/2) I_clk = ~I_clk;

    // =========================================================================
    // 主仿真流程
    // =========================================================================
    initial begin
        // 加载源图像数据 (hex 格式，每行一个 24-bit RGB888 像素)
        $readmemh("src_img.txt", img_mem);

        // 打开输出文件
        fp_out = $fopen("sim_out.txt", "w");
        if (!fp_out) begin
            $display("ERROR: Cannot open sim_out.txt!");
            $finish;
        end

        // 初始化所有输入信号
        I_rst_n  = 0;
        I_tvalid = 0;
        I_tuser  = 0;
        I_tlast  = 0;
        I_tdata  = 0;
        I_tready = 1;

        // 复位 10 个周期
        #(CLK_PERIOD * 10);
        I_rst_n = 1;
        #(CLK_PERIOD * 10);

        // 发送一帧 96x64 图像
        $display("Sending %0dx%0d Frame...", WIDTH, HEIGHT);
        send_frame();

        // 等待流水线全部输出完毕
        #(CLK_PERIOD * 200);
        $fclose(fp_out);

        // 仿真统计报告
        $display("=========================================");
        $display("Simulation Finished!");
        $display("Total Pixels Captured: %d (Expected: %d)", out_pixel_cnt, TOTAL_PIXELS);
        $display("=========================================");

        if (out_pixel_cnt == TOTAL_PIXELS)
            $display("PASS");
        else
            $display("FAIL errors=%d", TOTAL_PIXELS - out_pixel_cnt);

        $finish;
    end

    // =========================================================================
    // send_frame 任务: 在时钟上升沿逐像素发送一帧图像
    //   - tuser 在首像素 (row=0, col=0) 置 1，标记帧起始 (SOF)
    //   - tlast 在每行最后一个像素 (col=WIDTH-1) 置 1，标记行结束 (EOL)
    // =========================================================================
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
            // 帧发送完毕，拉低有效信号
            @(posedge I_clk);
            I_tvalid <= 1'b0;
            I_tlast  <= 1'b0;
            I_tuser  <= 1'b0;
            I_tdata  <= 24'd0;
        end
    endtask

    // =========================================================================
    // 输出像素抓取: 在时钟上升沿采样 O_tvalid，写入文件并计数
    // =========================================================================
    always @(posedge I_clk) begin
        if (O_tvalid) begin
            $fdisplay(fp_out, "%06X", O_tdata);
            out_pixel_cnt = out_pixel_cnt + 1;
        end
    end

endmodule
