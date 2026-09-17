`timescale 1ns / 1ps
// ============================================================================
// lp_filter_3x3 : 低分辨率灰度路径 3x3 因果均值滤波 (降噪)
//
// 目的: 传感器在高模拟增益(15.75x)+数字增益(1.5x)下暗部噪声很大, 而 LBP
//       编码是 9 个块和的相对比较, 对噪声非常敏感 —— 噪点随机翻转比较结果,
//       既造成人脸漏检, 也让噪点区域随机闯过级联 (误检测)。
//       3x3 均值把噪声标准差降为约 1/3, 使 LBP 码在帧间保持稳定。
//       注意: 均值滤波不破坏 LBP 对全局增益/亮度缩放的天然不变性。
//
// 窗口: 以当前像素 (x,y) 为右下角的因果 3x3 (x-2..x, y-2..y)。
//       除 8 近似除 9 (对接近饱和区域做饱和保护), 不引入乘法器。
//       因果窗口使输出坐标与输入坐标一致, 坐标/控制信号与数据同拍打 2 拍。
// 边界: x<3 或 y<2 的像素原样透传 (列 0 恒不存在, 行缓存首两行不可用)。
// 延迟: 固定 2 拍 (数据/控制/坐标同步, 不影响下游积分图与检测引擎)。
// 资源: 2 行行缓存 (IMG_WIDTH x 8bit) + 少量寄存器, 综合为 DRAM 或 BRAM 皆可。
// ============================================================================
module lp_filter_3x3 #(
    parameter IMG_WIDTH  = 213,
    parameter IMG_HEIGHT = 120
)(
    input  wire        I_clk,
    input  wire        I_rst_n,

    input  wire        I_tvalid,
    input  wire        I_tuser,
    input  wire        I_tlast,
    input  wire [7:0]  I_grey,
    input  wire [7:0]  I_x,
    input  wire [7:0]  I_y,

    output reg         O_tvalid,
    output reg         O_tuser,
    output reg         O_tlast,
    output reg  [7:0]  O_grey,
    output reg  [7:0]  O_x,
    output reg  [7:0]  O_y
);

    // ---- 行缓存: line1 = 上一行, line2 = 上两行 (按列地址 I_x 读写) ----
    // 读优先 (先取旧值再覆盖), 与 BRAM 读优先模式一致。
    reg [7:0] line1 [0:IMG_WIDTH-1];
    reg [7:0] line2 [0:IMG_WIDTH-1];

    // ---- 当前行窗口: w1=(x,y) w2=(x-1,y) w3=(x-2,y) ----
    reg [7:0] w1, w2, w3;
    // ---- 上一行窗口: l1_0=(x,y-1) l1_1=(x-1,y-1) l1_2=(x-2,y-1) ----
    reg [7:0] l1_0, l1_1, l1_2;
    // ---- 上两行窗口: l2_0=(x,y-2) l2_1=(x-1,y-2) l2_2=(x-2,y-2) ----
    reg [7:0] l2_0, l2_1, l2_2;

    // ---- 滤波判定 (x>=3 且 y>=2 时窗口内 9 个点全部有效) ----
    reg       do_filter;

    // ---- 数据/控制/坐标统一打 1 拍, 再经输出寄存器 = 共 2 拍延迟 ----
    reg [7:0] g_d1;
    reg [7:0] x_d1;
    reg [7:0] y_d1;
    reg       v_d1;
    reg       l_d1;
    reg       u_d1;

    // ---- 9 点求和 (组合逻辑) 与除 8 + 饱和 ----
    wire [11:0] sum9 = {4'd0, w1} + {4'd0, w2} + {4'd0, w3}
                     + {4'd0, l1_0} + {4'd0, l1_1} + {4'd0, l1_2}
                     + {4'd0, l2_0} + {4'd0, l2_1} + {4'd0, l2_2};
    wire [8:0]  avg9     = sum9[11:3];                 // /8, 最大 286
    wire [7:0]  avg9_sat = avg9[8] ? 8'hFF : avg9[7:0];

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            w1 <= 8'd0; w2 <= 8'd0; w3 <= 8'd0;
            l1_0 <= 8'd0; l1_1 <= 8'd0; l1_2 <= 8'd0;
            l2_0 <= 8'd0; l2_1 <= 8'd0; l2_2 <= 8'd0;
            do_filter <= 1'b0;
            g_d1 <= 8'd0;
            x_d1 <= 8'd0;
            y_d1 <= 8'd0;
            v_d1 <= 1'b0;
            l_d1 <= 1'b0;
            u_d1 <= 1'b0;
            O_tvalid <= 1'b0;
            O_tuser  <= 1'b0;
            O_tlast  <= 1'b0;
            O_grey   <= 8'd0;
            O_x      <= 8'd0;
            O_y      <= 8'd0;
        end else begin
            // ---- 第 1 拍: 窗口移位 + 行缓存滚动 (仅有效拍移位, 无效拍保持) ----
            if (I_tvalid) begin
                l1_0       <= line1[I_x];      // 读上一行同列 (读优先: 旧值)
                l2_0       <= line2[I_x];      // 读上两行同列
                line2[I_x] <= line1[I_x];      // 行缓存滚动
                line1[I_x] <= I_grey;
                l1_2 <= l1_1; l1_1 <= l1_0;    // 上/上两行 前两列延迟链
                l2_2 <= l2_1; l2_1 <= l2_0;
                w3   <= w2;   w2   <= w1;  w1 <= I_grey;
                do_filter <= (I_x >= 8'd3) && (I_y >= 8'd2);
            end else begin
                do_filter <= 1'b0;
            end

            // ---- 数据/控制/坐标打 1 拍 ----
            g_d1 <= I_grey;
            x_d1 <= I_x;
            y_d1 <= I_y;
            v_d1 <= I_tvalid;
            l_d1 <= I_tlast;
            u_d1 <= I_tuser;

            // ---- 第 2 拍: 输出 (滤波或透传), 与数据同拍对齐 ----
            O_tvalid <= v_d1;
            O_tuser  <= u_d1;
            O_tlast  <= l_d1;
            O_x      <= x_d1;
            O_y      <= y_d1;
            if (v_d1) begin
                O_grey <= do_filter ? avg9_sat : g_d1;
            end else begin
                O_grey <= 8'd0;
            end
        end
    end

endmodule
