`timescale 1ns / 1ps

// =============================================================================
// auto_exposure_top
// 自动曝光 - 顶层模块 (独立 AXI-Stream RGB888 通路)
//   - 输入: 视频流 RGB888 (24bit), 输出: 自动曝光补偿后的 RGB888
//   - 统计通路: 提取 Y 亮度 → brightness_stats 帧内累加求平均
//   - 控制通路: exposure_controller 在帧间更新数字增益 (q12.12)
//   - 应用通路: gain_apply 对 RGB 等比乘增益 + clamp
// 说明:
//   - 等比增益只提亮不改色相, 是自动曝光最安全的补偿方式
//   - 目标亮度 128, 增益在帧间消隐期更新, 帧内恒定避免逐帧闪烁
//   - 本模块不依赖外部 ram_2port / ram_accumulate IP, 自包含
//   - 已复用工程 RGB88_YCbCr444 的 Y 公式 (54R+183G+18B)>>8
//   - gain_apply 输出打 1 拍, 故控制信号同步打拍对齐
// =============================================================================
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
    output reg          O_tready         // 透传 (本模块无背压)
);

    // =========================================================================
    // 1. 提取 Y 亮度分量 (复用工程 RGB88_YCbCr444 的公式)
    // =========================================================================
    // Y = (54R + 183G + 18B) >> 8
    wire [24:0] y_sum = (I_tdata[23:16] * 8'd54)
                      + (I_tdata[15:8]  * 8'd183)
                      + (I_tdata[7:0]   * 8'd18);
    wire [7:0]  y_pix = y_sum[15:8];   // 等效 >>8

    // =========================================================================
    // 2. 亮度统计模块 (帧内累加, 帧末求平均)
    // =========================================================================
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
        .O_avg_y       (avg_y),
        .O_frame_done  (frame_done)
    );

    // =========================================================================
    // 3. 增益控制器 (帧间更新增益)
    // =========================================================================
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

    // =========================================================================
    // 4. RGB 等比增益应用 (输出打 1 拍)
    // =========================================================================
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
        end
    end

    assign O_tready = I_tready;

endmodule
