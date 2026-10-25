`timescale 1ns/1ps
//=============================================================================
// chroma_gain.v -- 色度(饱和度)增益：只放大 Cb/Cr 相对 128 的偏离量
//
// 为什么需要它:
//   vpp_top 的直方图档只把 Y 换成 Y'，Cb/Cr 原样送回。因为
//       R = Y + 1.402(Cr-128), G = Y - ... , B = Y + 1.772(Cb-128)
//   Y 变大时三个通道同时被"加"了同一个数, R-G / B-G 一点没变 -> 色相不变,
//   但 S=(max-min)/max 的分子不变、分母变大 -> 饱和度掉。视觉上就是
//   "红还是红, 但发灰发白"。本模块把色差按 K 倍放大, 把饱和度补回来。
//
// 数学:
//   Cb' = 128 + ((Cb-128) * K) >> 8      (K = GAIN_Q8, Q8 定点, 256 = 1.0x)
//   Cr' = 同上, 最后饱和到 0~255
//   若 K 取该像素的 Y'/Y, 则等价于 R/G/B 三通道同乘 Y'/Y —— 色相与饱和度
//   都严格保持不变(那是"精确版"); 本模块用固定 K, 是"够用的便宜版"。
//
// 时序: 1 拍。插入后请把 vpp_top 里 cb_d/cr_d 的 3 级延时改成 2 级,
//       这样模式 2 仍然落在第 22 拍, 不需要动 OSD/vs 的任何补偿。
//
// 常用 K:  256=1.0x(直通)  320=1.25x  358=1.40x  384=1.50x  435=1.70x
//=============================================================================
module chroma_gain #(
    parameter [8:0] GAIN_Q8 = 9'd358        // 1.40x
)(
    input  wire       I_clk,
    input  wire       I_rst_n,

    input  wire [7:0] I_cb,
    input  wire [7:0] I_cr,
    input  wire       I_tvalid,

    output reg  [7:0] O_cb,
    output reg  [7:0] O_cr,
    output reg        O_tvalid
);

    // ---- 1. 去掉 128 偏置, 变成有符号色差 (-128 .. +127) ----
    wire signed [9:0] cb_off = {2'b00, I_cb} - 10'sd128;
    wire signed [9:0] cr_off = {2'b00, I_cr} - 10'sd128;

    // ---- 2. 乘法 + 算术右移 8 位 (取反补码的 [17:8] 就是 floor(v/256)) ----
    wire signed [18:0] cb_mul = cb_off * $signed({1'b0, GAIN_Q8});
    wire signed [18:0] cr_mul = cr_off * $signed({1'b0, GAIN_Q8});

    wire signed [9:0]  cb_new = cb_mul[17:8] + 10'sd128;   // -51 .. +305
    wire signed [9:0]  cr_new = cr_mul[17:8] + 10'sd128;

    // ---- 3. 饱和到 0~255 ----
    function [7:0] sat8;
        input signed [9:0] v;
        begin
            if      (v[9]) sat8 = 8'd0;        // 负数
            else if (v[8]) sat8 = 8'd255;      // >= 256
            else           sat8 = v[7:0];
        end
    endfunction

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_cb     <= 8'd128;
            O_cr     <= 8'd128;
            O_tvalid <= 1'b0;
        end
        else begin
            O_cb     <= sat8(cb_new);
            O_cr     <= sat8(cr_new);
            O_tvalid <= I_tvalid;
        end
    end

endmodule
