`timescale 1ns / 1ps

module tb_auto_exposure;

    // =========================================================================
    // 自动曝光 (Auto Exposure) — TestBench
    // DUT: auto_exposure_top (AXI-Stream RGB888 输入，自动曝光补偿 RGB888 输出)
    // 分辨率: 96 x 64, 时钟: 50MHz (CLK_PERIOD=20ns)
    // 功能验证: 发送多帧同一偏暗图像, 观察增益逐帧收敛, 输出平均亮度逼近目标 128
    // =========================================================================

    parameter WIDTH           = 96;
    parameter HEIGHT          = 64;
    parameter TOTAL_PIXELS    = WIDTH * HEIGHT; // 6144
    parameter CLK_PERIOD      = 20;             // 50MHz
    parameter TARGET_Y        = 128;            // 目标亮度，与 DUT 一致
    parameter MAX_FRAMES      = 12;             // 发送最大帧数，观察收敛

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
    // 每帧输出亮度统计（用于验证收敛）
    //   - tlast 是行结束(EOL), 收到 HEIGHT 行才算一帧结束
    // =========================================================================
    integer frame_idx       = 0;    // 当前接收到的帧序号
    integer frame_pixel_cnt = 0;    // 当前帧已接收像素数
    reg [15:0] frame_line   = 0;    // 当前帧已接收行数
    reg [31:0] frame_sum    = 0;    // 当前帧 Y 亮度累加（用 RGB 最大通道近似）
    reg [31:0] frame_sum_tmp;

    // =========================================================================
    // DUT 例化
    // =========================================================================
    auto_exposure_top #(
        .IMG_WIDTH  (WIDTH),
        .IMG_HEIGHT (HEIGHT),
        .TARGET_Y   (TARGET_Y)
    ) u_auto_exposure (
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
    // 时钟生成: 50MHz
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

        // 发送 MAX_FRAMES 帧同一偏暗图像, 观察收敛
        $display("Sending %0dx%0d Frame x %0d (target luminance %0d)...",
                 WIDTH, HEIGHT, MAX_FRAMES, TARGET_Y);
        repeat (MAX_FRAMES) begin
            send_frame();
            #10;
            $display("  [int] avg_y=%0d frame_done=%b gain=0x%06X",
                     u_auto_exposure.u_brightness_stats.O_avg_y,
                     u_auto_exposure.u_brightness_stats.O_frame_done,
                     u_auto_exposure.u_exposure_controller.O_gain);
        end

        // 等待流水线全部输出完毕
        #(CLK_PERIOD * 200);
        $fclose(fp_out);

        // =====================================================================
        // 仿真统计报告: 打印每帧输出平均亮度, 验证是否收敛到目标
        // =====================================================================
        $display("=========================================");
        $display("Auto Exposure Simulation Finished!");
        $display("Expected Total Pixels: %0d", MAX_FRAMES * TOTAL_PIXELS);
        $display("=========================================");

        $finish;
    end

    // =========================================================================
    // send_frame 任务: 在时钟上升沿逐像素发送一帧图像
    //   - tuser 在首像素置 1, 标记帧起始 (SOF)
    //   - tlast 在每行最后一个像素置 1, 标记行结束 (EOL)
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
            // 帧发送完毕, 拉低有效信号
            @(posedge I_clk);
            I_tvalid <= 1'b0;
            I_tlast  <= 1'b0;
            I_tuser  <= 1'b0;
            I_tdata  <= 24'd0;
        end
    endtask

    // =========================================================================
    // 输出像素抓取: 采样 O_tvalid, 写入文件, 统计每帧平均亮度
    //   - tlast 是行结束(EOL), 收到 HEIGHT 行(即 frame_line==HEIGHT 时切帧)
    // =========================================================================
    always @(posedge I_clk) begin
        if (O_tvalid) begin
            $fdisplay(fp_out, "%06X", O_tdata);
            out_pixel_cnt = out_pixel_cnt + 1;

            // 用 RGB 最大通道近似亮度参与统计
            frame_sum = frame_sum + (O_tdata[23:16] > O_tdata[15:8] ?
                                    (O_tdata[23:16] > O_tdata[7:0] ? O_tdata[23:16] : O_tdata[7:0]) :
                                    (O_tdata[15:8] > O_tdata[7:0] ? O_tdata[15:8] : O_tdata[7:0]));
            frame_pixel_cnt = frame_pixel_cnt + 1;
        end

        // 行计数: tlast 表示行结束, 收到 HEIGHT 行算一帧
        if (O_tvalid && O_tlast) begin
            frame_line = frame_line + 1;
            if (frame_line == HEIGHT) begin
                frame_sum_tmp = frame_sum;
                $display("Frame %0d: avg max-channel = %0d (pixels=%0d), sum=%0d",
                         frame_idx, frame_sum_tmp / (frame_pixel_cnt > 0 ? frame_pixel_cnt : 1),
                         frame_pixel_cnt, frame_sum_tmp);
                frame_idx       = frame_idx + 1;
                frame_pixel_cnt = 0;
                frame_line      = 0;
                frame_sum       = 0;
            end
        end
    end

endmodule
