`timescale 1ns / 1ps

module tb_vpp_matlab;

    // 参数修改为 256 x 256
    parameter WIDTH           = 256;
    parameter HEIGHT          = 256;
    parameter TOTAL_PIXELS    = WIDTH * HEIGHT; // 65536
    parameter CLK_PERIOD      = 20;             // 50MHz
    parameter SOBEL_THRESHOLD = 60;

    reg         I_clk;
    reg         I_rst_n;
    reg  [1:0]  I_button;
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
    integer out_pixel_cnt = 0;

    PH1P_PHY_GSR PH1P_PHY_GSR();

    // 实例化顶层 VPP 模块
    vpp_top #(
        .IMG_WIDTH       (WIDTH),
        .IMG_HEIGHT      (HEIGHT),
        .SOBEL_THRESHOLD (SOBEL_THRESHOLD)
    ) u_vpp_top (
        .I_button (I_button),
        .I_clk    (I_clk),
        .I_rst_n  (I_rst_n),
        .I_tlast  (I_tlast),
        .I_tuser  (I_tuser),
        .I_tdata  (I_tdata),
        .I_tvalid (I_tvalid),
        .I_tdest  (I_tdest),
        .I_tready (I_tready),
        .O_tdata  (O_tdata),
        .O_tlast  (O_tlast),
        .O_tuser  (O_tuser),
        .O_tvalid (O_tvalid),
        .O_tready (O_tready)
    );

    // 时钟生成
    initial I_clk = 0;
    always #(CLK_PERIOD/2) I_clk = ~I_clk;

    initial begin
        $readmemh("src_img.txt", img_mem);
        fp_out = $fopen("sim_out.txt", "w");
        if (!fp_out) begin
            $display("ERROR: Cannot open sim_out.txt!");
            $finish;
        end

        I_rst_n   = 0;
        I_button  = 2'b11;
        I_tvalid  = 0;
        I_tuser   = 0;
        I_tlast   = 0;
        I_tdata   = 0;
        I_tdest   = 0;
        I_tready  = 1;

        #(CLK_PERIOD * 10);
        I_rst_n = 1;
        #(CLK_PERIOD * 10);

        // 强制进入 Sobel 模式 (跳过 20ms 消抖)
        force u_vpp_top.display_mode = 2'b11;
        $display("Switch to Mode 3: Sobel Edge Detection...");

        #(CLK_PERIOD * 20);

        $display("Sending 256x256 Frame...");
        send_frame();

        #(CLK_PERIOD * 200); // 等待流水线全部吐完
        $fclose(fp_out);

        $display("=========================================");
        $display("Simulation Finished!");
        $display("Total Pixels Captured: %d (Expected: %d)", out_pixel_cnt, TOTAL_PIXELS);
        $display("=========================================");
        $finish;
    end

    // 发送单帧任务
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

    // 抓取有效数据
    always @(posedge I_clk) begin
        if (O_tvalid) begin
            $fdisplay(fp_out, "%06X", O_tdata);
            out_pixel_cnt = out_pixel_cnt + 1;
        end
    end

endmodule