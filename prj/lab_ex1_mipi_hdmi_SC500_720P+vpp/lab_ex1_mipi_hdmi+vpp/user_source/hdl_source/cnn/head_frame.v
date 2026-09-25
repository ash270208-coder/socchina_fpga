//=============================================================================
// head_frame.v —— 检测头卷积（1x1, 32→15, s1 p0）+ Q12 定点输出
//-----------------------------------------------------------------------------
// 【不含存储器】输入特征图 x4 经 ram_raddr/ram_rdata 外接（同步读块 RAM）:
//   共享用法: bufB = 128bit x 2304，x4 每像素占 2 字（32 通道 / 每字 16 通道）
//   读地址 = 像素索引*(CIN/WPC) + ci/WPC，字节 = ci%WPC
// 权重 ROM: 官方 IP（cnn_rom_wh，同步读）
// 量化    : 8 通道共用 1 套 Q12 量化，逐通道 1 拍（每遍 8 拍）
// 输出    : 32x18x15，Q12 int16（可负！不做 0..255 clamp）
//           m_data[16c+15:16c] = 通道 c 的 Q12 值，m_valid 每像素 1 拍
//=============================================================================
`timescale 1ns/1ps

module head_frame #(
    parameter IMG_W = 32, IMG_H = 18,
    parameter TAPS = 32,                // 1x1x32
    parameter NUM_GRP = 2,              // ceil(15/8)
    parameter RAM_W = 128,              // 输入 RAM 字宽（bit）
    parameter AW = 14,
    parameter B_MEM = "sim/cnn_data/b_head.mem",
    parameter signed [31:0] MOUT_Q32 = 32'sd1563445632   // = `MOUT_Q32_HEAD_Q12
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    output reg  [239:0] m_data,             // 15 ch x 16bit Q12
    output reg         m_valid,
    output reg         done,
    // ---- 输入特征图 RAM（同步读）----
    output wire [AW-1:0]  ram_raddr,
    input  wire [RAM_W-1:0] ram_rdata,
    // ---- 权重 ROM（同步读，外接官方 IP）----
    output wire [10:0] rom_addr,
    input  wire [63:0] w_doa
);

    localparam WPC = RAM_W / 8;             // 每字通道数

    // ---- 偏置 ----
    reg [31:0] bmem [0:14];
    integer k;
    initial $readmemh(B_MEM, bmem);

    // ---- 权重 ROM 地址（外接官方 IP；t<TAPS 时有效）由下方声明后赋值 ----

    localparam [1:0] S_IDLE = 2'd0, S_TAP = 2'd1, S_Q = 2'd2;
    reg [1:0] state;
    reg [4:0] ro, co;                       // 输出像素（18x32）
    reg [5:0] t;                            // tap 计数 0..TAPS（多 1 拍冲刷流水）
    reg       g;                            // 通道组 0/1
    reg [3:0] qc;                           // 量化串行通道 0..7
    reg signed [31:0] acc [0:7];
    reg [4:0] ci_d;                         // 与 ram_rdata 对齐的通道号
    reg       t_valid;

    // 1x1 卷积: 像素索引 = ro*IMG_W + co（无 padding，恒在界内）
    wire [AW-1:0] pix_idx  = (ro * IMG_W) + co;
    wire [AW-1:0] base_idx = pix_idx * (32/WPC);
    assign ram_raddr = base_idx + (t / WPC);
    assign rom_addr  = (t < TAPS) ? (t*NUM_GRP + g) : 11'd0;
    wire [7:0] xbyte = ram_rdata[8*(ci_d % WPC) +: 8];   // 与 doa 同拍（组合抽取）

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= S_IDLE;
            ro      <= 5'd0;
            co      <= 5'd0;
            t       <= 6'd0;
            g       <= 1'b0;
            qc      <= 4'd0;
            ci_d    <= 5'd0;
            t_valid <= 1'b0;
            m_valid <= 1'b0;
            m_data  <= 240'd0;
            done    <= 1'b0;
            for (k = 0; k < 8; k = k + 1)
                acc[k] <= 32'sd0;
        end else begin
            done    <= 1'b0;
            m_valid <= 1'b0;
            ci_d    <= t[4:0];
            case (state)
                S_IDLE: begin
                    if (start) begin
                        ro <= 5'd0;
                        co <= 5'd0;
                        t  <= 6'd0;
                        g  <= 1'b0;
                        qc <= 4'd0;
                        t_valid <= 1'b0;
                        for (k = 0; k < 8; k = k + 1)
                            acc[k] <= 32'sd0;
                        state <= S_TAP;
                    end
                end
                S_TAP: begin
                    // t=0..TAPS-1 发地址，t=1..TAPS 收 MAC（偏置在 S_Q 加一次）
                    t_valid <= 1'b1;
                    for (k = 0; k < 8; k = k + 1)
                        acc[k] <= acc[k]
                                + (t_valid ? ($signed(w_doa[8*k +: 8]) * $signed({1'b0, xbyte})) : 32'sd0);
                    if (t == TAPS)
                        begin qc <= 4'd0; state <= S_Q; end
                    else
                        t <= t + 1'b1;
                end
                S_Q: begin
                    // 逐通道 Q12 量化（1 拍 1 通道）；第 2 组第 8 通道为填充，输出 0
                    if (g == 1'b0)
                        m_data[16*qc +: 16] <= quantize(acc[qc] + $signed(bmem[qc]));
                    else if (qc < 4'd7)
                        m_data[128 + 16*qc +: 16] <= quantize(acc[qc] + $signed(bmem[8 + qc]));
                    else
                        m_data[128 + 16*qc +: 16] <= 16'sd0;
                    if (qc == 4'd7) begin
                        if (g == 1'b1) begin
                            m_valid <= 1'b1;
                            if ((ro == IMG_H-1) && (co == IMG_W-1)) begin
                                done  <= 1'b1;
                                state <= S_IDLE;
                            end else begin
                                if (co == IMG_W-1) begin
                                    co <= 5'd0;
                                    ro <= ro + 1'b1;
                                end else
                                    co <= co + 1'b1;
                                t <= 6'd0;
                                g <= 1'b0;
                                qc <= 4'd0;
                                t_valid <= 1'b0;
                                for (k = 0; k < 8; k = k + 1)
                                    acc[k] <= 32'sd0;
                                state <= S_TAP;
                            end
                        end else begin
                            t <= 6'd0;
                            g <= 1'b1;
                            qc <= 4'd0;
                            t_valid <= 1'b0;
                            for (k = 0; k < 8; k = k + 1)
                                acc[k] <= 32'sd0;
                            state <= S_TAP;
                        end
                    end else
                        qc <= qc + 1'b1;
                end
            endcase
        end
    end

    // ---- 定点量化到 Q12: round(acc*MOUT_Q32/2^32)，半舍入远离零，输出 int16 ----
    function [15:0] quantize;
        input signed [31:0] a;
        reg signed [63:0] p, m;
        begin
            p = a * MOUT_Q32;
            if (p[63]) begin
                m = -p;
                m = (m + 64'sd2147483648) >>> 32;
                p = -m;
            end else begin
                p = (p + 64'sd2147483648) >>> 32;
            end
            quantize = p[15:0];
        end
    endfunction

endmodule
