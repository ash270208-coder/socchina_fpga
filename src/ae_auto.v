`timescale 1ns / 1ps
// =============================================================================
// ae_auto
// 自动曝光控制器 (通过摄像头曝光时间实现, 不修改 FPGA 内图像)
//   - I_enable=1: 正常自动闭环
//   - I_enable=0: 冻结内部状态, 不更新 O_ae / O_ae_req
//   - I_enable 上升沿: 从 AE_INIT 重新开始, 并发一次 I2C 请求
//   - 比例控制: ae_target = ae_cur * TARGET_Y / avg_y
//               配合步长限制和死区, 收敛快无闪烁
// =============================================================================
module ae_auto #(
    parameter TARGET_Y = 100,
    parameter AE_MAX   = 1990,
    parameter AE_MIN   = 4,
    parameter AE_INIT  = 1990,
    parameter HYST     = 3,
    parameter AG_VALUE = 16
)(
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_enable,        // ← 新增: 模式切换使能
    input  wire [7:0]  I_avg_y,
    input  wire        I_frame_done,
    input  wire        I_cfg_done,
    output reg  [15:0] O_ae,
    output reg  [15:0] O_ag,
    output reg         O_ae_req
);

    reg [15:0] ae_cur;

    // ---- 使能边沿检测 ----
    reg enable_d;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) enable_d <= 1'b0;
        else          enable_d <= I_enable;
    end
    wire enable_rise = I_enable & ~enable_d;

    // ---- 理想目标曝光 ----
    reg [23:0] ae_target;
    always @(*) begin
        if (I_avg_y == 8'd0)
            ae_target = AE_MAX[23:0];
        else begin
            ae_target = (ae_cur * TARGET_Y) / I_avg_y;
            if (ae_target > AE_MAX[23:0])
                ae_target = AE_MAX[23:0];
        end
    end

    // ---- 每帧最大步进 ----
    reg [15:0] max_step;
    always @(*) begin
        if      (ae_cur < 16'd32)   max_step = 16'd8;
        else if (ae_cur > 16'd2000) max_step = 16'd500;
        else                        max_step = ae_cur >> 2;
    end

    // ---- 步长限速 + 死区 ----
    reg [15:0] ae_next;
    always @(*) begin
        if ((I_avg_y > TARGET_Y) && ((I_avg_y - TARGET_Y) <= HYST))
            ae_next = ae_cur;
        else if ((I_avg_y < TARGET_Y) && ((TARGET_Y - I_avg_y) <= HYST))
            ae_next = ae_cur;
        else if (ae_target > (ae_cur + max_step))
            ae_next = ae_cur + max_step;
        else if ((ae_target < (ae_cur - max_step)) && (ae_cur > max_step))
            ae_next = ae_cur - max_step;
        else
            ae_next = ae_target[15:0];

        if      (ae_next > AE_MAX) ae_next = AE_MAX;
        else if (ae_next < AE_MIN) ae_next = AE_MIN;
    end

    // ---- 输出寄存器 ----
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            ae_cur   <= AE_INIT;
            O_ae     <= AE_INIT;
            O_ag     <= AG_VALUE;
            O_ae_req <= 1'b0;
        end else begin
            O_ae_req <= 1'b0;

            if (enable_rise) begin
                // 切到自动: 从 AE_INIT 重新开始
                ae_cur   <= AE_INIT;
                O_ae     <= AE_INIT;
                O_ae_req <= 1'b1;
            end
            else if (I_enable && I_frame_done && I_cfg_done && (ae_next != ae_cur)) begin
                // 正常自动闭环
                ae_cur   <= ae_next;
                O_ae     <= ae_next;
                O_ae_req <= 1'b1;
            end
            // I_enable=0: 冻结, 什么都不动
        end
    end

endmodule