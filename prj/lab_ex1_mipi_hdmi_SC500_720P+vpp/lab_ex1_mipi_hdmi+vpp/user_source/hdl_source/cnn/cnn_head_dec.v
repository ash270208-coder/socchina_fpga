//=============================================================================
// cnn_head_dec.v —— 检测头解码：exp LUT + Q12 锚框 + 全局最高分 1 框
//-----------------------------------------------------------------------------
// 输入: head_frame 的流式输出（576 像素 x 15 通道 Q12，每像素 1 拍 I_valid，
//       行主序 32x18），通道序: 每锚 [to tx ty tw th]，锚 1/2/3 = 通道 0/5/10 起
// 输出: 帧末 O_valid 1 拍 + 唯一框（128x72 输入空间整数）+ 分数（Q12）
//
// 解码公式（与 matlab decode_boxes.m 同一契约）:
//   score = clamp(to, 0, 1)           → Q12: clamp(to_q12, 0, 4096)，阈值 0.15
//   tx/ty = clamp(·, 0, 1)            → clamp(·, 0, 4096)
//   w = anchorW * exp(tw)             → w_q12 = (anchorW_Q12 * lut_exp(idx)) >>> 11
//   idx = round((tw + 4) * 128)       → ((tw_q12 + 16400) >>> 5)，clamp [0,1023]
//   cx = (gx + tx) * 4                → cx_q12 = gx*16384 + (tx_q12 << 2)
//   框 = [cx - w/2, cy - h/2, w, h]   → 整数化: (+2048)>>>12 后 clamp x∈[0,128] y∈[0,72]
//   阈值 0.15 → Q12 = 615（0.15*4096 = 614.4，向上取整对齐 MATLAB 的 >= 0.15）
//=============================================================================
`timescale 1ns/1ps

module cnn_head_dec #(
    parameter LUT_MEM       = "sim/cnn_data/lut_exp.mem",
    parameter [11:0] SCORE_TH_Q12 = 12'd615
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        I_valid,          // 每像素 1 拍
    input  wire [239:0] I_data,          // 15 通道 x 16bit Q12（ch c 在 bit[16c+15:16c]）
    output reg         O_valid,          // 帧末 1 拍，输出有效
    output reg  [7:0]  O_x1,             // 128x72 空间整数框 [x1 y1 w h]
    output reg  [7:0]  O_y1,
    output reg  [7:0]  O_w,
    output reg  [7:0]  O_h,
    output reg  [15:0] O_score_q12       // 该框分数（Q12）
);

    // ---- exp 查表官方 ROM（cnn_rom_exp，同步读: doa 晚 1 拍）----
    wire [15:0] exp_doa;

    // ---- 锚框（Q12，出自 cnn_params.vh，勿手改）----
    localparam [17:0] AW1 = 18'd52328,  AH1 = 18'd34738;
    localparam [17:0] AW2 = 18'd67885,  AH2 = 18'd65880;
    localparam [17:0] AW3 = 18'd151969, AH3 = 18'd122424;

    localparam [2:0] S_WAIT = 3'd0, S_A1 = 3'd1, S_A2 = 3'd2, S_A3 = 3'd3, S_DONE = 3'd4;
    reg [2:0]  state;
    reg [239:0] pix;                    // 锁存的当前像素 15 通道
    reg [9:0]  px;                      // 像素计数 0..575
    reg [1:0]  a;                       // 锚 0..2
    reg [4:0]  ro, co;                  // 当前像素格坐标（ro = px/32, co = px%32）
    reg        stage;                   // 0=查 tw, 1=查 th
    reg        best_valid;
    reg [11:0] best_score;
    reg [7:0]  best_x1, best_y1, best_w, best_h;
    reg [15:0] expw_r;                  // tw 查表结果流水

    // ---- 锚 a 的 5 通道（Q12 int16）----
    wire signed [15:0] to_s = $signed(pix[16*(5*a)   +: 16]);
    wire signed [15:0] tx_s = $signed(pix[16*(5*a+1) +: 16]);
    wire signed [15:0] ty_s = $signed(pix[16*(5*a+2) +: 16]);
    wire signed [15:0] tw_s = $signed(pix[16*(5*a+3) +: 16]);
    wire signed [15:0] th_s = $signed(pix[16*(5*a+4) +: 16]);

    // ---- clamp 到 [0, 4096] ----
    wire [11:0] score = (to_s < 16'sd0) ? 12'd0 : (to_s > 16'sd4096) ? 12'd4096 : to_s[11:0];
    wire [11:0] tx12  = (tx_s < 16'sd0) ? 12'd0 : (tx_s > 16'sd4096) ? 12'd4096 : tx_s[11:0];
    wire [11:0] ty12  = (ty_s < 16'sd0) ? 12'd0 : (ty_s > 16'sd4096) ? 12'd4096 : ty_s[11:0];

    // ---- exp LUT: idx = round((x + 4)*128) = ((x_q12 + 16384 + 16) >>> 5) ----
    wire signed [17:0] twoff = tw_s + 18'sd16400;
    wire signed [17:0] thoff = th_s + 18'sd16400;
    wire signed [11:0] iws = twoff >>> 5;
    wire signed [11:0] ihs = thoff >>> 5;
    wire [9:0]  idx_w = (iws < 12'sd0) ? 10'd0 : (iws > 12'sd1023) ? 10'd1023 : iws[9:0];
    wire [9:0]  idx_h = (ihs < 12'sd0) ? 10'd0 : (ihs > 12'sd1023) ? 10'd1023 : ihs[9:0];

    // 地址 = stage 选择器: S_A1 查 tw、S_A2 查 th（ROM 内部自带地址寄存器）
    wire [9:0] lut_addr = stage ? idx_h : idx_w;
    cnn_rom_exp u_lut (.doa(exp_doa), .addra(lut_addr), .clka(clk));

    // ---- 锚框宽高: w_q12 = anchorW_Q12 * exp(Q11) >>> 11 ----
    wire [17:0] aw = (a == 2'd0) ? AW1 : (a == 2'd1) ? AW2 : AW3;
    wire [17:0] ah = (a == 2'd0) ? AH1 : (a == 2'd1) ? AH2 : AH3;
    // 注意: 乘法必须先扩到 34bit 再移位（否则被 LHS 24bit 上下文截断）
    wire [33:0] w_q23 = aw * expw_r;        // expw_r = lut(tw)，1 拍流水
    wire [33:0] h_q23 = ah * exp_doa;       // exp_doa = lut(th)，本拍就绪
    wire [23:0] w_q12 = w_q23 >>> 11;
    wire [23:0] h_q12 = h_q23 >>> 11;

    // ---- 中心与框角: cx_q12 = gx*16384 + (tx_q12 << 2) ----
    // 注意: 16384 = 2^14 必须用 15'd 表示（14'd16384 溢出为 0！）
    wire [20:0] cx_q12 = (co * 15'd16384) + (tx12 << 2);
    wire [20:0] cy_q12 = (ro * 15'd16384) + (ty12 << 2);
    wire signed [25:0] x1_q12 = $signed({1'b0, cx_q12}) - $signed({1'b0, w_q12[23:1]});
    wire signed [25:0] y1_q12 = $signed({1'b0, cy_q12}) - $signed({1'b0, h_q12[23:1]});

    // ---- 整数化: round（+2048 再 >>12），框角 clamp，宽高防溢出 ----
    wire signed [12:0] x1r = (x1_q12 + 26'sd2048) >>> 12;
    wire signed [12:0] y1r = (y1_q12 + 26'sd2048) >>> 12;
    wire [7:0] x1i = (x1r < 13'sd0) ? 8'd0 : (x1r > 13'sd128) ? 8'd128 : x1r[7:0];
    wire [7:0] y1i = (y1r < 13'sd0) ? 8'd0 : (y1r > 13'sd72)  ? 8'd72  : y1r[7:0];
    wire [12:0] wiq = (w_q12 + 24'sd2048) >>> 12;
    wire [12:0] hiq = (h_q12 + 24'sd2048) >>> 12;
    wire [7:0] wi = (wiq > 13'sd255) ? 8'd255 : wiq[7:0];
    wire [7:0] hi = (hiq > 13'sd255) ? 8'd255 : hiq[7:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_WAIT;
            pix        <= 240'd0;
            px         <= 10'd0;
            a          <= 2'd0;
            ro         <= 5'd0;
            co         <= 5'd0;
            stage      <= 1'b0;
            expw_r     <= 16'd0;
            best_valid <= 1'b0;
            best_score <= 12'd0;
            best_x1    <= 8'd0;
            best_y1    <= 8'd0;
            best_w     <= 8'd0;
            best_h     <= 8'd0;
            O_valid    <= 1'b0;
            O_x1       <= 8'd0;
            O_y1       <= 8'd0;
            O_w        <= 8'd0;
            O_h        <= 8'd0;
            O_score_q12 <= 16'd0;
        end else begin
            O_valid <= 1'b0;
            case (state)
                S_WAIT: begin
                    if (I_valid) begin
                        pix <= I_data;
                        ro  <= px[9:5];          // px / 32
                        co  <= px[4:0];          // px % 32
                        a   <= 2'd0;
                        stage <= 1'b0;           // 先查 tw
                        state <= S_A1;
                    end
                end
                S_A1: begin                    // 本拍 doa=lut(tw)，下拍可见；切查 th
                    stage  <= 1'b1;
                    state  <= S_A2;
                end
                S_A2: begin                    // 锁 lut(tw)，doa 已就绪；下拍 lut(th)
                    expw_r <= exp_doa;
                    stage  <= 1'b0;
                    state  <= S_A3;
                end
                S_A3: begin                    // exp_doa = lut(th)，与 expw_r 一起出框
                    if ((score >= SCORE_TH_Q12) && (!best_valid || (score > best_score))) begin
                        best_valid <= 1'b1;
                        best_score <= score;
                        best_x1    <= x1i;
                        best_y1    <= y1i;
                        best_w     <= wi;
                        best_h     <= hi;
                    end
                    if (a == 2'd2) begin
                        if (px == 10'd575)
                            state <= S_DONE;
                        else begin
                            px    <= px + 1'b1;
                            state <= S_WAIT;
                        end
                    end else begin
                        a     <= a + 1'b1;
                        state <= S_A1;
                    end
                end
                S_DONE: begin
                    O_valid    <= 1'b1;
                    O_x1       <= best_x1;
                    O_y1       <= best_y1;
                    O_w        <= best_w;
                    O_h        <= best_h;
                    O_score_q12 <= {4'd0, best_score};
                    best_valid <= 1'b0;
                    best_score <= 12'd0;
                    px         <= 10'd0;
                    state      <= S_WAIT;
                end
            endcase
        end
    end

endmodule
