`timescale 1ns / 1ps

// =============================================================================
// gain_apply
// 自动曝光 - RGB 等比增益应用模块
//   - 对 RGB 三通道同时乘数字增益 gain (q12.12), 只提亮不改色相
//   - 等比增益保持饱和度与色相不变, 是自动曝光最安全的补偿方式
//   - gain 在帧间由 exposure_controller 更新, 帧内恒定
//   - 乘法后右移 GAIN_FRAC 归一, 再 clamp 到 [0,255] 防止饱和溢出
// 时序：输出打 1 拍对齐, 控制信号 tlast/tuser/tvalid 同步打拍
// =============================================================================
module gain_apply #(
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720,
    parameter GAIN_FRAC  = 12     // 增益小数位 (12.12 格式)
)(
    input               I_clk,
    input               I_rst_n,

    input               I_tlast,
    input               I_tuser,
    input      [23:0]   I_tdata,        // 输入 RGB888
    input               I_tvalid,
    input      [23:0]   I_gain,         // q12.12 定点增益 (由 exposure_controller 提供)

    output reg          O_tlast,
    output reg          O_tuser,
    output reg [23:0]   O_tdata,
    output reg          O_tvalid
);

    // ---- 逐通道乘法: 8bit * 24bit(q12.12) = 32bit, 右移 GAIN_FRAC 恢复整数 ----
    // R = I_tdata[23:16], G = I_tdata[15:8], B = I_tdata[7:0]
    wire [31:0] r_mult = I_tdata[23:16] * I_gain;
    wire [31:0] g_mult = I_tdata[15:8]  * I_gain;
    wire [31:0] b_mult = I_tdata[7:0]   * I_gain;

    // ---- 逐通道乘法: 8bit * 24bit(q12.12) = 32bit ----
    wire [31:0] r_mult = I_tdata[23:16] * I_gain;
    wire [31:0] g_mult = I_tdata[15:8]  * I_gain;
    wire [31:0] b_mult = I_tdata[7:0]   * I_gain;

    // ---- 饱和阈值: 255 << GAIN_FRAC ----
    localparam [31:0] SAT_THRESH = 32'd255 << GAIN_FRAC;

    // ---- 用完整 32bit 结果与阈值比较后再截位 ----
    wire [7:0] r_clamp = (r_mult >= SAT_THRESH) ? 8'd255 : r_mult[GAIN_FRAC + 7 : GAIN_FRAC];
    wire [7:0] g_clamp = (g_mult >= SAT_THRESH) ? 8'd255 : g_mult[GAIN_FRAC + 7 : GAIN_FRAC];
    wire [7:0] b_clamp = (b_mult >= SAT_THRESH) ? 8'd255 : b_mult[GAIN_FRAC + 7 : GAIN_FRAC];

    // ---- 数据打 1 拍, 控制信号同拍对齐 ----
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_tdata  <= 24'd0;
            O_tlast  <= 1'b0;
            O_tuser  <= 1'b0;
            O_tvalid <= 1'b0;
        end else begin
            O_tdata  <= {r_clamp, g_clamp, b_clamp};
            O_tlast  <= I_tlast;
            O_tuser  <= I_tuser;
            O_tvalid <= I_tvalid;
        end
    end

endmodule
