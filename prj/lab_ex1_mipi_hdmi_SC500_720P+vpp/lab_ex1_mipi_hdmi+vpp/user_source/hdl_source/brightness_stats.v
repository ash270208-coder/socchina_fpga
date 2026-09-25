`timescale 1ns / 1ps

// =============================================================================
// brightness_stats
// 自动曝光 - 帧亮度统计模块
//   - 逐像素累加 Y 亮度电平总和 sum_y 与像素总数 pixel_cnt
//   - 帧末触发多周期恢复余数除法器, 求平均亮度
//   - 帧同步基于 I_tlast 自持行计数, I_tuser 强制行计数归零
//   - 除法器每次 1 bit, 共 YSUM_W 拍, 帧消隐期足够, 无时序压力
// =============================================================================
module brightness_stats #(
    parameter IMG_WIDTH   = 1280,
    parameter IMG_HEIGHT  = 720
)(
    input               I_clk,
    input               I_rst_n,

    input               I_tlast,        // 行结束信号 (EOL)
    input               I_tuser,        // 帧开始信号 (SOF)
    input      [7:0]    I_y_tdata,      // 输入 Y 灰度分量 (0~255)
    input               I_tvalid,       // 数据有效
    input               I_tready, 

    output reg [7:0]    O_avg_y,        // 当前帧平均亮度 (0~255)
    output reg          O_frame_done    // 帧计算完成脉冲 (持续 1 拍)
);

    localparam YSUM_W = (IMG_WIDTH * IMG_HEIGHT < (1 << 24)) ? 32 : 40;

    // ---- 行计数与累加器 ----
    reg [15:0]       line_cnt;
    reg [YSUM_W-1:0] sum_y;
    reg [YSUM_W-1:0] pixel_cnt;

    wire [YSUM_W-1:0] sum_next = sum_y + {24'd0, I_y_tdata};
    wire              frame_end = (line_cnt == IMG_HEIGHT - 1) && I_tlast && I_tvalid && I_tready;

    // 帧末那一拍连同最后一个像素一起算进去
    wire [YSUM_W-1:0] final_sum = sum_y + {24'd0, I_y_tdata};
    wire [YSUM_W-1:0] final_cnt = pixel_cnt + 1'b1;

    // =========================================================================
    // 多周期恢复余数除法器
    //   算法: 每拍把 {rem, num_msb} 左移, 与除数比较, 够减则 rem 减去除数, 商位=1
    //   迭代 YSUM_W 次后商在 div_quo 中
    // =========================================================================
    localparam S_IDLE = 1'b0;
    localparam S_DIV  = 1'b1;

    reg              div_state;
    reg [5:0]        div_cnt;
    reg [YSUM_W-1:0] div_rem;
    reg [YSUM_W-1:0] div_quo;
    reg [YSUM_W-1:0] div_num;   // 被除数 (逐拍左移)
    reg [YSUM_W-1:0] div_den;   // 除数

    wire [YSUM_W-1:0] shifted_rem = {div_rem[YSUM_W-2:0], div_num[YSUM_W-1]};
    wire              ge_den      = (shifted_rem >= div_den);
    wire [YSUM_W-1:0] rem_new     = ge_den ? (shifted_rem - div_den) : shifted_rem;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            sum_y        <= {YSUM_W{1'b0}};
            pixel_cnt    <= {YSUM_W{1'b0}};
            line_cnt     <= 16'd0;
            O_avg_y      <= 8'd128;
            O_frame_done <= 1'b0;
            div_state    <= S_IDLE;
            div_cnt      <= 6'd0;
            div_rem      <= {YSUM_W{1'b0}};
            div_quo      <= {YSUM_W{1'b0}};
            div_num      <= {YSUM_W{1'b0}};
            div_den      <= {YSUM_W{1'b0}};
        end else begin
            O_frame_done <= 1'b0;   // 默认清除

            // ---- 行计数: I_tuser 优先复位 ----
            if (I_tuser) begin
                line_cnt <= 16'd0;
            end
            else if (I_tvalid && I_tlast) begin
                if (line_cnt == IMG_HEIGHT - 1)
                    line_cnt <= 16'd0;
                else
                    line_cnt <= line_cnt + 16'd1;
            end

            // ---- 除法迭代 (优先级最高) ----
            if (div_state == S_DIV) begin
                div_rem <= rem_new;
                div_quo <= {div_quo[YSUM_W-2:0], ge_den};
                div_num <= {div_num[YSUM_W-2:0], 1'b0};
                div_cnt <= div_cnt - 1'b1;
                if (div_cnt == 6'd1) begin
                    div_state    <= S_IDLE;
                    O_avg_y      <= {div_quo[6:0], ge_den}; // 最终商的低 8 位
                    O_frame_done <= 1'b1;
                end
            end
            // ---- 帧末: 触发除法 (或除零直出 128) ----
            else if (frame_end) begin
                if (final_cnt == {YSUM_W{1'b0}}) begin
                    O_avg_y      <= 8'd128;
                    O_frame_done <= 1'b1;
                end
                else begin
                    div_num   <= final_sum;
                    div_den   <= final_cnt;
                    div_rem   <= {YSUM_W{1'b0}};
                    div_quo   <= {YSUM_W{1'b0}};
                    div_cnt   <= YSUM_W[5:0];
                    div_state <= S_DIV;
                end
                sum_y     <= {YSUM_W{1'b0}};
                pixel_cnt <= {YSUM_W{1'b0}};
            end
            // ---- 正常累加 ----
            else if (I_tvalid && I_tready) begin
                sum_y     <= sum_next;
                pixel_cnt <= pixel_cnt + 1'b1;
            end
        end
    end

endmodule
