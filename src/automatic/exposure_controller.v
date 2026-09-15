`timescale 1ns / 1ps

// =============================================================================
// exposure_controller
// 自动曝光 - 增益控制器模块
//   - 接收 brightness_stats 输出的帧平均亮度 I_avg_y
//   - 每帧计算目标增益 = (TARGET_Y << GAIN_FRAC) / avg_y, 再用受限步长逐帧逼近
//   - gain 采用 12.12 定点格式 (GAIN_FRAC=12), 帧内保持恒定, 避免逐帧闪烁
//   - 帧间步长限制 MAX_STEP 防止单帧增益跳变过大 (避免画面突变/闪烁)
//   - 增益钳位 [GAIN_MIN, GAIN_MAX], 防止过曝/欠曝无限偏移
// 算法：比例收敛 + 步长限制 (成熟 AE 做法, 收敛快且无闪烁)
//   目标增益 target = (TARGET_Y << FRAC) / avg_y
//   每帧步进 = clamp(target - 上帧增益, -MAX_STEP, +MAX_STEP), 再钳位到 [GAIN_MIN,GAIN_MAX]
// =============================================================================
module exposure_controller #(
    parameter TARGET_Y  = 128,   // 目标平均亮度 (0~255)
    parameter GAIN_FRAC = 12,    // 增益小数位 (12.12 格式 → 放大 4096 倍)
    parameter GAIN_MAX  = 65536, // 增益上限 = 16.0 (16 << 12)
    parameter GAIN_MIN  = 1024,  // 增益下限 = 0.25 (0.25 << 12)
    parameter MAX_STEP  = 2048   // 每帧最大步进 = 0.5 (0.5 << 12), 防闪烁
)(
    input               I_clk,
    input               I_rst_n,

    input      [7:0]    I_avg_y,        // 当前帧平均亮度 (0~255)
    input               I_frame_done,   // 帧计算完成脉冲 (1 拍)

    output reg [23:0]   O_gain          // 当前帧应使用的增益 (q12.12)
);

    // 增益累加寄存器: 使用有符号便于误差方向控制
    reg signed [31:0] gain_acc;

    // ---- 目标增益定点计算: target = (TARGET_Y << GAIN_FRAC) / avg_y ----
    // 注意 TARGET_Y 为 8bit, avg_y 为 8bit, 用乘法放大精度后除法
    // (TARGET_Y << 12) / avg_y; 防除零: avg_y==0 时取最大增益
    reg [31:0] target;

    always @(*) begin
        if (I_avg_y == 8'd0)
            target = GAIN_MAX;                 // 全黑, 后续由限幅钳到上限
        else
            target = ({24'd0, TARGET_Y} << GAIN_FRAC) / {24'd0, I_avg_y};
    end

    // ---- 帧间步长限制: 目标增益与当前增益之差, 钳位到 ±MAX_STEP ----
    wire signed [31:0] gain_diff = $signed(target) - gain_acc;
    wire signed [31:0] limited_step = (gain_diff > $signed(MAX_STEP)) ? $signed(MAX_STEP)
                                    : (gain_diff < -$signed(MAX_STEP)) ? -$signed(MAX_STEP)
                                    : gain_diff;

    // ---- 钳位后的下一次增益 ----
    wire signed [31:0] next_gain = gain_acc + limited_step;
    wire signed [31:0] sat_gain  = (next_gain < $signed(GAIN_MIN)) ? $signed(GAIN_MIN)
                                  : (next_gain > $signed(GAIN_MAX)) ? $signed(GAIN_MAX)
                                  : next_gain;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            gain_acc <= $signed(32'd4096);   // 初始增益 1.0 (1 << 12)
            O_gain   <= 24'd4096;
        end else begin
            if (I_frame_done) begin
                gain_acc <= sat_gain;
                O_gain   <= sat_gain[23:0];
            end else begin
                gain_acc <= gain_acc;
                O_gain   <= O_gain;
            end
        end
    end

endmodule
