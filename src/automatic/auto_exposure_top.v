`timescale 1ns / 1ps

module auto_exposure_top #(
    parameter IMG_WIDTH   = 1280,
    parameter IMG_HEIGHT  = 720,
    parameter TARGET_Y    = 128,
    parameter GAIN_FRAC   = 12
)(
    input               I_clk,
    input               I_rst_n,

    input               I_tlast,        // 行结束信号
    input               I_tuser,        // 帧开始信号
    input      [23:0]   I_tdata,        // 输入 RGB888
    input               I_tvalid,       // 数据有效
    input               I_tready,       // 输入 ready 信号

    output reg          O_tlast,
    output reg          O_tuser,
    output reg [23:0]   O_tdata,
    output reg          O_tvalid,
    output reg          O_tready         // 透传 
);
    // 1. 提取 Y 亮度分量
    wire [24:0] y_sum = (I_tdata[23:16] * 8'd54)
                      + (I_tdata[15:8]  * 8'd183)
                      + (I_tdata[7:0]   * 8'd18);
    wire [7:0]  y_pix = y_sum[15:8];   // 等效 >>8

    // 2. 亮度统计模块 (帧内累加, 帧末求平均)
    wire [7:0] avg_y;
    wire       frame_done;

    brightness_stats #(
        .IMG_WIDTH  (IMG_WIDTH),
        .IMG_HEIGHT (IMG_HEIGHT)
    ) u_brightness_stats (
        .I_clk         (I_clk),
        .I_rst_n       (I_rst_n),
        .I_tlast       (I_tlast),
        .I_tuser       (I_tuser),
        .I_y_tdata     (y_pix),
        .I_tvalid      (I_tvalid),
        .I_tready      (I_tready),
        .O_avg_y       (avg_y),
        .O_frame_done  (frame_done)
    );

    // 3. 增益控制器
    wire [23:0] gain;

    exposure_controller #(
        .TARGET_Y  (TARGET_Y),
        .GAIN_FRAC (GAIN_FRAC)
    ) u_exposure_controller (
        .I_clk         (I_clk),
        .I_rst_n       (I_rst_n),
        .I_avg_y       (avg_y),
        .I_frame_done  (frame_done),
        .O_gain        (gain)
    );

    // 4. RGB 等比增益应用 (输出打 1 拍)
    wire       gain_tlast;
    wire       gain_tuser;
    wire [23:0] gain_tdata;
    wire       gain_tvalid;

    gain_apply #(
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .GAIN_FRAC (GAIN_FRAC)
    ) u_gain_apply (
        .I_clk     (I_clk),
        .I_rst_n   (I_rst_n),
        .I_tlast   (I_tlast),
        .I_tuser   (I_tuser),
        .I_tdata   (I_tdata),
        .I_tvalid  (I_tvalid),
        .I_gain    (gain),
        .O_tlast   (gain_tlast),
        .O_tuser   (gain_tuser),
        .O_tdata   (gain_tdata),
        .O_tvalid  (gain_tvalid)
    );

    // =========================================================================
    // 5. 输出
    // =========================================================================
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_tdata  <= 24'd0;
            O_tlast  <= 1'b0;
            O_tuser  <= 1'b0;
            O_tvalid <= 1'b0;
            O_tready <= 1'b0;
        end else begin
            O_tdata  <= gain_tdata;
            O_tlast  <= gain_tlast;
            O_tuser  <= gain_tuser;
            O_tvalid <= gain_tvalid;
            O_tready <= I_tready
        end
    end

endmodule
