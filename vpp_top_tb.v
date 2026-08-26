`timescale 1ns / 1ps

module tb_vpp_matlab;

    // 参数必须与 MATLAB 中的 64x64 一致
    parameter WIDTH  = 64;
    parameter HEIGHT = 64;
    parameter TOTAL_PIXELS = WIDTH * HEIGHT;
    parameter CLK_PERIOD = 20;

    reg         I_clk;
    reg         I_rst_n;
    reg         I_tlast;
    reg         I_tuser;
    reg  [23:0] I_tdata;
    reg         I_tvalid;
    reg         I_tdest;
    reg         I_tready;

    wire [23:0] O_tdata;
    wire        O_tlast;
    wire        O_tuser;
    wire        O_tvalid;
    wire        O_tready;

    reg [23:0] img_mem [0:TOTAL_PIXELS-1];
    integer fp_out;
    integer frame_cnt = 0;

    PH1P_PHY_GSR PH1P_PHY_GSR();
    // 实例化顶层模块
    vpp_top 
    #(
        .IMG_WIDTH (WIDTH),
        .IMG_HEIGHT(HEIGHT)
    )u_vpp_top (
        .I_clk   (I_clk),
        .I_rst_n (I_rst_n),
        .I_tlast (I_tlast),
        .I_tuser (I_tuser),
        .I_tdata (I_tdata),
        .I_tvalid(I_tvalid),
        .I_tdest (I_tdest),
        .I_tready(I_tready),
        .O_tdata (O_tdata),
        .O_tlast (O_tlast),
        .O_tuser (O_tuser),
        .O_tvalid(O_tvalid),
        .O_tready(O_tready)
    );

    // 时钟生成 50MHz
    initial I_clk = 0;
    always #(CLK_PERIOD/2) I_clk = ~I_clk;

    initial begin
        // 读取 MATLAB 生成的输入图片
        $readmemh("src_img.txt", img_mem);
        fp_out = $fopen("sim_out.txt", "w");

        I_rst_n  = 0;
        I_tvalid = 0;
        I_tuser  = 0;
        I_tlast  = 0;
        I_tdata  = 0;
        I_tdest  = 0;
        I_tready = 1;

        #(CLK_PERIOD * 10);
        I_rst_n = 1;
        #(CLK_PERIOD * 10);

        // 发送第 1 帧（直方图统计）
        $display("Sending Frame 1 (Histogram Statistics)...");
        send_frame();

        #(CLK_PERIOD * 1000); // 帧间空白

        // 发送第 2 帧（此时均衡化结果正式输出）
        $display("Sending Frame 2 (Capture Equalized Result)...");
        frame_cnt = 1;
        send_frame();

        #(CLK_PERIOD * 100);
        $fclose(fp_out);
        $display("Simulation Finished! Results written to sim_out.txt");
        $finish;
    end

    // 发送一帧的任务
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
        end
    endtask

    // 抓取第 2 帧输出写入文本
    always @(posedge I_clk) begin
        if (O_tvalid && frame_cnt == 1) begin
            $fdisplay(fp_out, "%06X", O_tdata);
        end
    end

endmodule