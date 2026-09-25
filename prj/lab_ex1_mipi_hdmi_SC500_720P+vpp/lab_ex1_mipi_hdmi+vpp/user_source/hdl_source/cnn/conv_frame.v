//=============================================================================
// conv_frame.v —— 参数化卷积引擎核心（conv2/conv3/conv4 通用，16 DSP 双切片）
//-----------------------------------------------------------------------------
// 本模块【不含任何存储器】:
//   输入特征图: 读地址 ram_raddr 输出 / 读数据 ram_rdata 输入（**同步读块 RAM**，
//              数据晚 1 拍到，与权重 doa 同拍对齐）
//   权重 ROM  : rom_addr_e/o 输出 / w_doa_e/o 输入（官方 ROM IP，同步读）
//   偏置      : bmem 行为级（小，综合成分布式 ROM）
//
// RAM 字宽参数 RAM_W（必须 ≥ 每个 tap 需求的通道字节数）:
//   私有 RAM 用法: RAM_W = 8*CIN（每像素 1 字，字节序 = 通道序）
//   共享窄字用法: RAM_W = 64 或 128（每字 WPC=RAM_W/8 个通道，每像素占 CIN/WPC 字）
//   读地址 = 像素索引*(CIN/WPC) + ci/WPC，字节 = ci%WPC
//
// 架构（方案文档 §4.2 的 2×8 切片版）:
//   每拍: 取 1 个输入字节（tap）+ 2 个权重字（2×8 输出通道）→ 16 个 MAC
//   每输出像素: (TAPS+1) x NUM_GRP/2 拍（tap 累加）+ 16 拍（量化串行复用）
//   量化: 16 通道共用 1 套 (acc*Q32 + 半舍入 + clamp)，逐通道 1 拍输出 1 字节
//         → 省掉 16 路并行乘法器（上一版 40 个 DSP 的来源）
//   NUM_GRP 必须为偶数（16 通道 = 2 组 x 8）
//
// 定点公式（与 matlab step4 金标准逐位一致）:
//   acc = Σ(Wq·xq);  y = clamp(round((acc + b_int)·MOUT_Q32/2^32), 0, 255)
//=============================================================================
`timescale 1ns/1ps

module conv_frame #(
    // ---- 层参数 ----
    parameter IMG_W  = 128,
    parameter IMG_H  = 72,
    parameter CIN    = 8,
    parameter COUT   = 16,
    parameter K      = 3,
    parameter STRIDE = 2,
    parameter PAD    = 1,
    parameter TAPS   = 72,          // K*K*CIN
    parameter NUM_GRP = 2,          // ceil(COUT/8)，必须为偶数
    parameter OUT_W  = 64,
    parameter OUT_H  = 36,
    parameter WOUT_BITS = 128,      // 8*COUT
    parameter AW     = 14,          // 输入 RAM 地址位宽
    parameter RAM_W  = 64,          // 输入 RAM 字宽（bit）
    // ---- 偏置文件 ----
    parameter B_MEM = "sim/cnn_data/b_conv2.mem",
    parameter signed [31:0] MOUT_Q32 = 32'sd56261780   // = `MOUT_Q32_CONV2
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    output reg  [WOUT_BITS-1:0] m_data,
    output reg         m_valid,
    output reg         done,
    // ---- 输入特征图 RAM（同步读）----
    output wire [AW-1:0]  ram_raddr,
    input  wire [RAM_W-1:0] ram_rdata,
    // ---- 权重 ROM（同步读）----
    output wire [10:0] rom_addr_e,      // 偶字地址 = t*NUM_GRP + 2p
    output wire [10:0] rom_addr_o,      // 奇字地址 = t*NUM_GRP + 2p + 1
    input  wire [63:0] w_doa_e,
    input  wire [63:0] w_doa_o
);

    localparam WPC    = RAM_W / 8;          // 每字通道数
    localparam PASSES = NUM_GRP / 2;

    // ---- 偏置（行为级；小 ROM，综合成分布式 ROM）----
    reg [31:0] bmem [0:COUT-1];
    integer k;
    initial $readmemh(B_MEM, bmem);

    localparam [1:0] S_IDLE = 2'd0, S_TAP = 2'd1, S_Q = 2'd2;
    reg [1:0]  state;
    reg [9:0]  ro;
    reg [7:0]  co;
    reg [8:0]  t;                       // tap 计数 0..TAPS（多 1 拍冲刷流水）
    reg [2:0]  p;                       // 通道组对
    reg [4:0]  qc;                      // 量化串行通道 0..15
    reg signed [31:0] acc [0:15];
    reg [7:0]  xval_d;                  // (保留未用)
    reg [4:0]  ci_d;                    // 与 ram_rdata 对齐的通道号
    reg        inb_d;                   // 与 ram_rdata 对齐的越界标志
    reg        t_valid;                 // doa/xval_d 有效（t ≥ 1）

    // ---- 权重 ROM 地址（组合直连 ROM 端口；ROM 内部自带地址寄存器）----
    assign rom_addr_e = (t * NUM_GRP) + 2*p;
    assign rom_addr_o = (t * NUM_GRP) + 2*p + 11'd1;

    // ---- tap 分解: t = ky + K*kx + K*K*ci（ky 最快变）----
    wire [1:0] ky = t % K;
    wire [1:0] kx = (t / K) % K;
    wire [4:0] ci = t / (K*K);

    // ---- 滑窗采样（pad 补零）→ 输入 RAM 读地址（同步读: 数据下一拍到）----
    wire signed [10:0] ri  = $signed({1'b0, ro}) * STRIDE - PAD + $signed({1'b0, ky});
    wire signed [10:0] ric = $signed({1'b0, co}) * STRIDE - PAD + $signed({1'b0, kx});
    wire        inb   = (ri >= 0) && (ri < IMG_H) && (ric >= 0) && (ric < IMG_W);
    wire [AW-1:0] pix_idx  = (ri[6:0] * IMG_W) + ric[6:0];
    wire [AW-1:0] base_idx = pix_idx * (CIN/WPC);
    assign ram_raddr = base_idx + (ci / WPC);
    // 下一拍: ram_rdata = 该 tap 所在字，用 ci_d 组合抽字节（与 doa 同拍）
    wire [7:0] xbyte = inb_d ? ram_rdata[8*(ci_d % WPC) +: 8] : 8'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= S_IDLE;
            ro      <= 10'd0;
            co      <= 8'd0;
            t       <= 9'd0;
            p       <= 3'd0;
            qc      <= 5'd0;
            xval_d  <= 8'd0;
            ci_d    <= 5'd0;
            inb_d   <= 1'b0;
            t_valid <= 1'b0;
            m_valid <= 1'b0;
            m_data  <= {WOUT_BITS{1'b0}};
            done    <= 1'b0;
            for (k = 0; k < 16; k = k + 1)
                acc[k] <= 32'sd0;
        end else begin
            done    <= 1'b0;
            m_valid <= 1'b0;
            // 输入字节对齐寄存器（ci_d/inb_d 与 ram_rdata 同拍）
            ci_d   <= ci;
            inb_d  <= inb;

            case (state)
                S_IDLE: begin
                    if (start) begin
                        ro <= 10'd0;
                        co <= 8'd0;
                        t  <= 9'd0;
                        p  <= 3'd0;
                        qc <= 5'd0;
                        t_valid <= 1'b0;
                        for (k = 0; k < 16; k = k + 1)
                            acc[k] <= 32'sd0;
                        state <= S_TAP;
                    end
                end
                S_TAP: begin
                    // doa(拍 c) = 字(t-1)，与 xval_d 对齐（pix_idx 由 (ky,kx) 决定）
                    t_valid <= 1'b1;
                    for (k = 0; k < 8; k = k + 1) begin
                        acc[k]   <= acc[k]
                                  + (t_valid ? ($signed(w_doa_e[8*k +: 8]) * $signed({1'b0, xbyte})) : 32'sd0);
                        acc[8+k] <= acc[8+k]
                                  + (t_valid ? ($signed(w_doa_o[8*k +: 8]) * $signed({1'b0, xbyte})) : 32'sd0);
                    end
                    if (t == TAPS)
                        begin qc <= 5'd0; state <= S_Q; end
                    else
                        t <= t + 1'b1;
                end
                S_Q: begin
                    // 逐通道量化（1 拍 1 通道，16 通道共用 1 套乘法/舍入/钳位）
                    m_data[128*p + 8*qc +: 8] <= quantize(acc[qc] + $signed(bmem[16*p + qc]));
                    if (qc == 5'd15) begin
                        if (p == PASSES-1) begin
                            m_valid <= 1'b1;
                            if ((ro == OUT_H-1) && (co == OUT_W-1)) begin
                                done  <= 1'b1;
                                state <= S_IDLE;
                            end else begin
                                if (co == OUT_W-1) begin
                                    co <= 8'd0;
                                    ro <= ro + 1'b1;
                                end else
                                    co <= co + 1'b1;
                                t <= 9'd0;
                                p <= 3'd0;
                                t_valid <= 1'b0;
                                for (k = 0; k < 16; k = k + 1)
                                    acc[k] <= 32'sd0;
                                state <= S_TAP;
                            end
                        end else begin
                            t <= 9'd0;
                            p <= p + 1'b1;
                            t_valid <= 1'b0;
                            qc <= 5'd0;
                            for (k = 0; k < 16; k = k + 1)
                                acc[k] <= 32'sd0;
                            state <= S_TAP;
                        end
                    end else
                        qc <= qc + 1'b1;
                end
            endcase
        end
    end

    // ---- 定点量化: round(acc*MOUT_Q32/2^32)，半舍入远离零，clamp 0..255 ----
    function [7:0] quantize;
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
            if (p <= 32'sd0)
                quantize = 8'd0;
            else if (p >= 32'sd255)
                quantize = 8'd255;
            else
                quantize = p[7:0];
        end
    endfunction

endmodule
