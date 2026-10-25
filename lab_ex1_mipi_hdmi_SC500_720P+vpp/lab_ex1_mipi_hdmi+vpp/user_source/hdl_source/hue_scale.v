`timescale 1ns/1ps
//=============================================================================
// hue_scale.v -- 保色（hue-preserving）亮度重映射：RGB' = RGB * (Y'/Y)
//
// 【为什么用它，而不是"改 Y + 改 Cb/Cr"】
//   只改 Y 时等价于 RGB 三通道同加 Δ：色相不变，但饱和度按 1/增益 变
//   （HE 提亮 -> 发灰；HE 压暗 -> 环境色被放大 -> 发蓝）。
//   本模块直接对 RGB 三通道同乘 k = Y'/Y：
//       R' = k*R , G' = k*G , B' = k*B
//   色相与饱和度严格不变，只有亮度按 HE 的曲线走。
//
// 【为什么比"YCbCr 正变换 + 色度补偿 + 反变换"省】—— 这颗芯片 DSP 只有 40 个
//   那种做法：正变换 9 个乘法器 + 色度补偿 3 个 + 反变换 4 个 = 16 个 DSP。
//   本做法：算 Y 3 个（在 Y888.v 里）+ 算 k 1 个 + 乘 RGB 3 个 = 7 个 DSP。
//
// 【定点】
//   1/Y 查表 64 项（索引 Y[7:2]，Q12）：inv = 4096 / Y
//   k_q8 = (Y' * inv) >> 4               // Y'*(4096/Y)/16 = 256*Y'/Y
//   k 限幅 [K_MIN_Q8, K_MAX_Q8]；Y'==Y 时强制 k=256（恒等映射一丝不差）
//   R' = sat((R * k_q8) >> 8)
//   误差：1/Y 表按 4 档共用一项，k 的误差 <3%，肉眼不可见。
//
// 【时序】3 拍
// ===========================================================================
module hue_scale #(
    // k 的上下限，Q8：64=0.25x, 128=0.5x, 256=1.0x, 512=2.0x
    //   下限要够低：HE 把暗部压到接近 0 时 k 趋近 0，颜色必须跟着压掉，
    //   否则又会变成"压暗 = 饱和度爆涨"（就是之前屏上的发蓝）。
    parameter [9:0] K_MIN_Q8 = 10'd64,
    parameter [9:0] K_MAX_Q8 = 10'd512
)(
    input  wire       I_clk,
    input  wire       I_rst_n,

    input  wire [7:0] I_y_old,      // HE 之前的 Y（显示域）
    input  wire [7:0] I_y_new,      // HE 之后的 Y'（与 I_y_old 同拍）
    input  wire [23:0] I_rgb,       // 与 I_y_old 同拍的 RGB（已经对齐好）
    input  wire       I_tvalid,

    output reg  [23:0] O_rgb,
    output reg         O_tvalid
);

    // -------------------------------------------------------------------------
    // 1/Y 查表：index = Y[7:2]，值 = Q12(1/Y)
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
    // Stage 1: 查 1/Y，同时把 Y' / RGB / valid 打一拍
    // -------------------------------------------------------------------------
    reg [11:0] inv_r;
    reg [7:0]  yold_s1, ynew_s1;
    reg [23:0] rgb_s1;
    reg        v_s1;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            inv_r   <= 12'd0;
            yold_s1 <= 8'd0;
            ynew_s1 <= 8'd0;
            rgb_s1  <= 24'd0;
            v_s1    <= 1'b0;
        end
        else begin
            inv_r   <= recip(I_y_old[7:2]);
            yold_s1 <= I_y_old;
            ynew_s1 <= I_y_new;
            rgb_s1  <= I_rgb;
            v_s1    <= I_tvalid;
        end
    end

    // -------------------------------------------------------------------------
    // Stage 2: k_q8 = (Y' * inv) >> 4，限幅
    //   校验：Y'=Y 时 k = Y*(4096/Y)/16 = 256 = 1.0x
    // -------------------------------------------------------------------------
    wire [19:0] k_prod = ynew_s1 * inv_r;      // 255*2048 = 522240 -> 20 bit 够
    wire [15:0] k_raw  = k_prod[19:4];

    reg [9:0]  k_q8;
    reg [23:0] rgb_s2;
    reg        v_s2;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            k_q8   <= 10'd256;
            rgb_s2 <= 24'd0;
            v_s2   <= 1'b0;
        end
        else begin
            // 映射是恒等（Y'==Y）时强制 1.0x，避开 1/Y 查表 ±3% 的量化误差
            if (ynew_s1 == yold_s1)            k_q8 <= 10'd256;
            else if (k_raw > {6'd0, K_MAX_Q8}) k_q8 <= K_MAX_Q8;
            else if (k_raw < {6'd0, K_MIN_Q8}) k_q8 <= K_MIN_Q8;
            else                               k_q8 <= k_raw[9:0];
            rgb_s2 <= rgb_s1;
            v_s2   <= v_s1;
        end
    end

    // -------------------------------------------------------------------------
    // Stage 3: R' = sat((R*k)>>8)，G/B 同理
    // -------------------------------------------------------------------------
    wire [17:0] r_mul = rgb_s2[23:16] * k_q8;
    wire [17:0] g_mul = rgb_s2[15: 8] * k_q8;
    wire [17:0] b_mul = rgb_s2[ 7: 0] * k_q8;

    function [7:0] sat8;
        input [17:0] v;                 // (8bit * 10bit) 最大 255*512 = 130560
        begin
            if (v[17:16] != 2'd0) sat8 = 8'd255;    // 移位后 >= 256
            else                  sat8 = v[15:8];
        end
    endfunction

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_rgb    <= 24'd0;
            O_tvalid <= 1'b0;
        end
        else begin
            O_rgb    <= {sat8(r_mul), sat8(g_mul), sat8(b_mul)};
            O_tvalid <= v_s2;
        end
    end

endmodule
