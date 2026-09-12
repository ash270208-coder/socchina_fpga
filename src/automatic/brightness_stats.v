`timescale 1ns / 1ps

// =============================================================================
// brightness_stats
// 自动曝光 - 帧亮度统计模块
//   - 逐像素累加 Y 亮度电平总和 sum_y 与像素总数 pixel_cnt
//   - 帧末（tlast && tvalid 且 line_cnt 到达 IMG_HEIGHT-1）输出平均亮度
//   - 帧同步完全基于 I_tlast 自持行计数，不依赖 I_tuser
//   - 目标亮度 128 的误差在 exposure_controller 中计算，本模块只负责统计
// 接口：与工程现有 AXI-Stream + RGB888 模块一致（I_y 为 8bit 灰度分量）
// 说明：平均亮度除法仅每帧执行一次（frame_end 那拍），占用资源可忽略
// =============================================================================
module brightness_stats #(
    parameter IMG_WIDTH   = 1024,
    parameter IMG_HEIGHT  = 600
)(
    input               I_clk,
    input               I_rst_n,

    input               I_tlast,        // 行结束信号 (EOL)
    input               I_tuser,        // 帧开始信号 (SOF) - 保留端口，不参与帧同步
    input      [7:0]    I_y_tdata,      // 输入 Y 灰度分量 (0~255)
    input               I_tvalid,       // 数据有效

    output reg [7:0]    O_avg_y,        // 当前帧平均亮度 (0~255)
    output reg          O_frame_done    // 帧计算完成脉冲 (持续 1 拍)
);

    // 平均亮度累加器位宽需覆盖 sum 最大可能值: 255 * IMG_WIDTH * IMG_HEIGHT
    localparam YSUM_W = (IMG_WIDTH * IMG_HEIGHT < (1 << 24)) ? 32 : 40;

    // 行计数: 0 ~ IMG_HEIGHT-1 自持循环，仅依赖 I_tlast + I_tvalid
    reg [15:0] line_cnt;
    reg [YSUM_W-1:0] sum_y;        // 本帧 Y 总和
    reg [YSUM_W-1:0] pixel_cnt;    // 本帧像素计数 (无符号)

    wire [YSUM_W-1:0] sum_next = sum_y + {24'd0, I_y_tdata};
    wire              frame_end = (line_cnt == IMG_HEIGHT - 1) && I_tlast && I_tvalid;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            sum_y        <= {YSUM_W{1'b0}};
            pixel_cnt    <= {YSUM_W{1'b0}};
            line_cnt     <= 16'd0;
            O_avg_y      <= 8'd128;     // 缺省平均亮度
            O_frame_done <= 1'b0;
        end else begin
            O_frame_done <= 1'b0;       // 默认清除脉冲

            // ---- 自持行计数: 0 ~ IMG_HEIGHT-1 循环 ----
            if (I_tvalid && I_tlast) begin
                if (line_cnt == IMG_HEIGHT - 1)
                    line_cnt <= 16'd0;
                else
                    line_cnt <= line_cnt + 16'd1;
            end

            // ---- 帧结束: 计算平均亮度（含最后一个像素），复位累加器 ----
            if (frame_end) begin
                O_avg_y      <= (pixel_cnt == {YSUM_W{1'b0}} && sum_y == {YSUM_W{1'b0}})
                                ? 8'd128
                                : (sum_y + {24'd0, I_y_tdata}) / (pixel_cnt + 1'b1);
                O_frame_done <= 1'b1;
                sum_y        <= {YSUM_W{1'b0}};
                pixel_cnt    <= {YSUM_W{1'b0}};
            end
            // ---- 正常累加: 非帧结束的有效数据拍 ----
            else if (I_tvalid) begin
                sum_y     <= sum_next;
                pixel_cnt <= pixel_cnt + 1'b1;
            end
        end
    end

endmodule
