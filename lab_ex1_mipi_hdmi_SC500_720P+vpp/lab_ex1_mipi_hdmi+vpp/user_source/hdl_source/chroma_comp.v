`timescale 1ns/1ps
//=============================================================================
// chroma_comp.v -- 色度补偿（"只改 Y 会偏色"的正解，L3）
//
// 【为什么需要它】
//   只把 Y 换成 Y'、Cb/Cr 原样送回时，等价于在 RGB 上"三通道同加一个 Δ"：
//       R' = R + Δ , G' = G + Δ , B' = B + Δ      (Δ = Y'-Y)
//   色相不变（所以"红还是红"），但饱和度 S=(max-min)/max 的分子不动、分母跟着
//   Δ 走 —— 也就是 S 会按 1/增益 变化：
//       HE 把画面提亮(增益>1) -> 饱和度掉 -> 画面发灰
//       HE 把画面压暗(增益<1) -> 饱和度涨 -> 现场的环境色被放大 -> 发蓝/发黄
//   两者是同一个毛病，本模块把它一次治好。
//
// 【做法】
//   把色度按该像素的亮度增益 k = Y'/Y 一起缩放：
//       Cb' = 128 + k*(Cb-128)
//       Cr' = 128 + k*(Cr-128)
//   代回反变换可以证明（因为 Y' = k*Y）：
//       R' = k*R , G' = k*G , B' = k*B
//   也就是"整幅图乘一个 k" —— 色相、饱和度都严格不变，只有亮度按 HE 的曲线走。
//   这就是文献里的 hue-preserving / color-preserving histogram equalization。
//
// 【定点实现】
//   k 不直接做除法：用 1/Y 的 64 项查表（索引 Y[7:2]，Q12），
//       inv = 4096 / Y_bin
//       k_q8 = (Y' * inv) >> 4        // 因为 Y'*(4096/Y)/16 = 256*Y'/Y
//       k 再限幅到 [K_MIN_Q8, K_MAX_Q8]（防止 Y 接近 0 时爆掉）
//   整个模块 3 拍，3 个乘法器（1 个算 k，2 个给 Cb/Cr），1 张 64x12 表。
//
// 【时序】3 拍。插入后要把 vpp_top 里 he_rgb_d 的补拍由 10 级减到 7 级，
//        模式 2 仍然落在第 22 拍。
//=============================================================================
module chroma_comp #(
    // k 的上下限，Q8 定点：64=0.25x, 128=0.5x, 256=1.0x, 512=2.0x
    //   下限要足够低：HE 把暗部压到接近 0 时，k 会趋近 0，色度也必须跟着压掉，
    //   否则"压暗 = 饱和度爆涨"（就是之前在屏上看到的发蓝）。
    //   上限 2.0x 是为了防止 Y 很小时 1/Y 表爆掉把色度轰上天。
    parameter [9:0] K_MIN_Q8 = 10'd64,
    parameter [9:0] K_MAX_Q8 = 10'd512
)(
    input  wire       I_clk,
    input  wire       I_rst_n,

    input  wire [7:0] I_y_old,      // HE 之前的 Y（显示域），与 Cb/Cr 同拍
    input  wire [7:0] I_y_new,      // HE 之后输出的 Y'
    input  wire [7:0] I_cb,         // 原始色度
    input  wire [7:0] I_cr,
    input  wire       I_tvalid,

    output reg  [7:0] O_y,          // = I_y_new，延时 3 拍，与 O_cb/O_cr 同拍
    output reg  [7:0] O_cb,         // 补偿后的色度
    output reg  [7:0] O_cr,
    output reg        O_tvalid
);

    // -------------------------------------------------------------------------
    // 1/Y 查表：index = Y[7:2]（每 4 个亮度共用一项，误差 <3%），值 = Q12(1/Y)
    //   表中心取每档的中点 4i+2，i=0 时 1/2=2048
    // -------------------------------------------------------------------------
    function [11:0] recip;
        input [5:0] idx;
        case (idx)
            6'd0 : recip = 12'd2048; 6'd1 : recip = 12'd683 ; 6'd2 : recip = 12'd410 ; 6'd3 : recip = 12'd293 ;
            6'd4 : recip = 12'd228 ; 6'd5 : recip = 12'd186 ; 6'd6 : recip = 12'd158 ; 6'd7 : recip = 12'd137 ;
            6'd8 : recip = 12'd120 ; 6'd9 : recip = 12'd108 ; 6'd10: recip = 12'd98  ; 6'd11: recip = 12'd89  ;
            6'd12: recip = 12'd82  ; 6'd13: recip = 12'd76  ; 6'd14: recip = 12'd71  ; 6'd15: recip = 12'd66  ;
            6'd16: recip = 12'd62  ; 6'd17: recip = 12'd59  ; 6'd18: recip = 12'd55  ; 6'd19: recip = 12'd53  ;
            6'd20: recip = 12'd50  ; 6'd21: recip = 12'd48  ; 6'd22: recip = 12'd46  ; 6'd23: recip = 12'd44  ;
            6'd24: recip = 12'd42  ; 6'd25: recip = 12'd40  ; 6'd26: recip = 12'd39  ; 6'd27: recip = 12'd37  ;
            6'd28: recip = 12'd36  ; 6'd29: recip = 12'd35  ; 6'd30: recip = 12'd34  ; 6'd31: recip = 12'd33  ;
            6'd32: recip = 12'd32  ; 6'd33: recip = 12'd31  ; 6'd34: recip = 12'd30  ; 6'd35: recip = 12'd29  ;
            6'd36: recip = 12'd28  ; 6'd37: recip = 12'd27  ; 6'd38: recip = 12'd27  ; 6'd39: recip = 12'd26  ;
            6'd40: recip = 12'd25  ; 6'd41: recip = 12'd25  ; 6'd42: recip = 12'd24  ; 6'd43: recip = 12'd24  ;
            6'd44: recip = 12'd23  ; 6'd45: recip = 12'd23  ; 6'd46: recip = 12'd22  ; 6'd47: recip = 12'd22  ;
            6'd48: recip = 12'd21  ; 6'd49: recip = 12'd21  ; 6'd50: recip = 12'd20  ; 6'd51: recip = 12'd20  ;
            6'd52: recip = 12'd20  ; 6'd53: recip = 12'd19  ; 6'd54: recip = 12'd19  ; 6'd55: recip = 12'd18  ;
            6'd56: recip = 12'd18  ; 6'd57: recip = 12'd18  ; 6'd58: recip = 12'd18  ; 6'd59: recip = 12'd17  ;
            6'd60: recip = 12'd17  ; 6'd61: recip = 12'd17  ; 6'd62: recip = 12'd16  ; 6'd63: recip = 12'd16  ;
            default: recip = 12'd16;
        endcase
    endfunction

    // -------------------------------------------------------------------------
    // Stage 1: 查 1/Y，同时把 Y'/Cb/Cr/valid 打一拍
    // -------------------------------------------------------------------------
    reg [11:0] inv_r;
    reg [7:0]  yold_s1, ynew_s1, cb_s1, cr_s1;
    reg        v_s1;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            inv_r   <= 12'd0;
            yold_s1 <= 8'd0;
            ynew_s1 <= 8'd0;
            cb_s1   <= 8'd128;
            cr_s1   <= 8'd128;
            v_s1    <= 1'b0;
        end
        else begin
            inv_r   <= recip(I_y_old[7:2]);
            yold_s1 <= I_y_old;
            ynew_s1 <= I_y_new;
            cb_s1   <= I_cb;
            cr_s1   <= I_cr;
            v_s1    <= I_tvalid;
        end
    end

    // -------------------------------------------------------------------------
    // Stage 2: k_q8 = (Y' * inv) >> 4，再限幅
    //   Y'*inv 最大 255*2048 = 522240，20 位够；>>4 之后是 Q8 的 k
    //   校验：Y'=Y 时 k = Y*(4096/Y)/16 = 256 = 1.0x ✓
    // -------------------------------------------------------------------------
    wire [19:0] k_prod = ynew_s1 * inv_r;
    wire [15:0] k_raw  = k_prod[19:4];

    reg [9:0]  k_q8;
    reg [7:0]  ynew_s2, cb_s2, cr_s2;
    reg        v_s2;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            k_q8    <= 10'd256;
            ynew_s2 <= 8'd0;
            cb_s2   <= 8'd128;
            cr_s2   <= 8'd128;
            v_s2    <= 1'b0;
        end
        else begin
            // Y'==Y（这一档的映射是恒等）时强制 k=1.0x：保证"没做均衡的那部分
            // 颜色一丝不差"，也避开 1/Y 查表 ±3% 量化误差造成的固定偏色
            if (ynew_s1 == yold_s1)                k_q8 <= 10'd256;
            else if (k_raw > {6'd0, K_MAX_Q8})     k_q8 <= K_MAX_Q8;
            else if (k_raw < {6'd0, K_MIN_Q8})     k_q8 <= K_MIN_Q8;
            else                                   k_q8 <= k_raw[9:0];
            ynew_s2 <= ynew_s1;
            cb_s2   <= cb_s1;
            cr_s2   <= cr_s1;
            v_s2    <= v_s1;
        end
    end

    // -------------------------------------------------------------------------
    // Stage 3: Cb' = 128 + ((Cb-128)*k)>>8，Cr 同理，最后饱和到 0~255
    // -------------------------------------------------------------------------
    wire signed [9:0]  cb_off = {2'b00, cb_s2} - 10'sd128;      // -128 .. +127
    wire signed [9:0]  cr_off = {2'b00, cr_s2} - 10'sd128;
    wire signed [19:0] cb_mul = cb_off * $signed({1'b0, k_q8});
    wire signed [19:0] cr_mul = cr_off * $signed({1'b0, k_q8});
    wire signed [9:0]  cb_new = cb_mul[17:8] + 10'sd128;        // -128 .. +383
    wire signed [9:0]  cr_new = cr_mul[17:8] + 10'sd128;

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
            O_y      <= 8'd0;
            O_cb     <= 8'd128;
            O_cr     <= 8'd128;
            O_tvalid <= 1'b0;
        end
        else begin
            O_y      <= ynew_s2;
            O_cb     <= sat8(cb_new);
            O_cr     <= sat8(cr_new);
            O_tvalid <= v_s2;
        end
    end

endmodule
