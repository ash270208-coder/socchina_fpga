//=============================================================================
// conv1_frame.v —— conv1 整层引擎（128x72x3 → 128x72x8）
//-----------------------------------------------------------------------------
// 输入 RAM: 同步读块 RAM 8bit x 27648（3 平面布局 addr = ch*9216 + row*128 + col）
//           【必须同步读】组合读会被综合成分布式 RAM(LUTRAM)，烧查找表
// 权重 ROM: 官方 IP（cnn_rom_w1，同步读 doa 晚 1 拍）
// 量化    : 8 通道共用 1 套 (acc*Q32 + 半舍入 + clamp)，逐通道 1 拍（8 拍）
// 偏置    : 在 i==27 拍并入 acc（只加一次）
// 输出    : 每像素 1 拍 m_valid，m_data = 8 通道 x 9bit（bit8 恒 0，LSB 通道在前）
//=============================================================================
`timescale 1ns/1ps

module conv1_frame #(
    parameter W_MEM = "sim/cnn_data/w_conv1_packed.mem",   // 兼容旧测试台传递（权重已由官方 ROM IP 提供，此参数不再使用）
    parameter B_MEM = "sim/cnn_data/b_conv1_packed.mem",
    parameter signed [31:0] MOUT_Q32 = 32'sd15573148    // = `MOUT_Q32_CONV1
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        wr_en,
    input  wire [14:0] wr_addr,
    input  wire [7:0]  wr_data,
    input  wire        start,
    output reg  [71:0] m_data,
    output reg         m_valid,
    output reg         done
);

    // ---- 私有输入 RAM（官方 IP cnn_buf_in: 8bit x 27648，双口，REGMODE=NOREG）----
    reg  [14:0] ram_raddr;
    wire [7:0]  ram_rdata;
    cnn_buf_in u_fb (
        .clka(clk), .cea(1'b1), .wea(wr_en), .addra(wr_addr), .dia(wr_data),
        .clkb(clk), .ceb(1'b1), .addrb(ram_raddr), .dob(ram_rdata),
        .doa(), .dib(8'd0), .web(1'b0));

    // ---- 偏置（1 行 64 hex = 8 x int32 打包）----
    reg [255:0] b_packed [0:0];
    initial $readmemh(B_MEM, b_packed);

    // ---- 权重官方 ROM（cnn_rom_w1，同步读）----
    // addra 直接接组合表达式（ROM 内部自带地址寄存器，勿再加寄存否则 2 拍延迟）
    wire [63:0] w_doa;

    localparam [1:0] S_IDLE = 2'd0, S_TAP = 2'd1, S_Q = 2'd2;
    reg [1:0]  state;
    reg [7:0]  row, col;
    reg [5:0]  i;                       // tap 计数 0..27（多 1 拍冲刷流水）
    reg [3:0]  qc;                      // 量化串行通道 0..7
    reg signed [31:0] acc [0:7];
    integer k;
    reg        t_valid;
    reg        inb_d;                   // 越界标志（与 ram_rdata 同拍）

    // ---- 调试观测信号（conv1_frame_dbg_tb 引用）----
    reg [63:0] w_word;
    reg [7:0]  bk;
    reg signed [31:0] b_word;
    reg [8:0]  yq [0:7];

    cnn_rom_w1 u_rom (.doa(w_doa), .addra((i < 6'd27) ? i[4:0] : 5'd0), .clka(clk));

    // ---- tap 分解: i = ky + 3*kx + 9*ci ----
    wire [2:0] ky = i % 3'd3;
    wire [2:0] kx = (i / 3'd3) % 3'd3;
    wire [1:0] ci = i / 4'd9;          // 注意: 9 需要 4 bit，3'd9 会溢出成 1！

    // ---- 3x3 滑窗采样（pad=1 补零）→ 同步 RAM 读地址 ----
    wire signed [8:0] rr = $signed({1'b0, row}) - 9'sd1 + $signed({1'b0, ky});
    wire signed [8:0] cc = $signed({1'b0, col}) - 9'sd1 + $signed({1'b0, kx});
    wire        inb = (rr >= 9'sd0) && (rr < 9'sd72) && (cc >= 9'sd0) && (cc < 9'sd128);
    always @(*) begin
        ram_raddr = (ci * 15'd9216) + ({1'b0, rr[7:0]} * 8'd128) + {1'b0, cc[7:0]};
    end
    wire [8:0] inb_q = inb_d ? {1'b0, ram_rdata} : 9'd0;   // 与 doa 同拍（组合抽取）

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= S_IDLE;
            row     <= 8'd0;
            col     <= 8'd0;
            i       <= 6'd0;
            qc      <= 4'd0;
            t_valid <= 1'b0;
            inb_d   <= 1'b0;
            m_valid <= 1'b0;
            m_data  <= 72'd0;
            done    <= 1'b0;
            w_word  <= 64'd0;
            bk      <= 8'd0;
            b_word  <= 32'sd0;
            for (k = 0; k < 8; k = k + 1) begin
                acc[k] <= 32'sd0;
                yq[k]  <= 9'd0;
            end
        end else begin
            done    <= 1'b0;
            m_valid <= 1'b0;
            w_word  <= w_doa;
            bk      <= row;
            b_word  <= $signed(b_packed[0][31:0]);
            // 输入字节对齐寄存器（inb_d 与 ram_rdata 同拍）
            inb_d <= inb;

            case (state)
                S_IDLE: begin
                    if (start) begin
                        row <= 8'd0;
                        col <= 8'd0;
                        i   <= 6'd0;
                        qc  <= 4'd0;
                        t_valid <= 1'b0;
                        for (k = 0; k < 8; k = k + 1)
                            acc[k] <= 32'sd0;
                        state <= S_TAP;
                    end
                end
                S_TAP: begin
                    // i=0..26 发地址，i=1..27 收 MAC，i=27 收末字 + 偏置
                    t_valid <= 1'b1;
                    for (k = 0; k < 8; k = k + 1)
                        acc[k] <= acc[k]
                                + (t_valid ? ($signed(w_doa[8*k +: 8]) * $signed(inb_q)) : 32'sd0)
                                + ((i == 6'd27) ? $signed(b_packed[0][32*k +: 32]) : 32'sd0);
                    if (i == 6'd27)
                        begin qc <= 4'd0; state <= S_Q; end
                    else
                        i <= i + 1'b1;
                end
                S_Q: begin
                    // 逐通道量化（1 拍 1 通道，8 通道共用 1 套乘法/舍入/钳位）
                    yq[qc] <= quantize(acc[qc]);
                    m_data[9*qc +: 9] <= quantize(acc[qc]);
                    if (qc == 4'd7) begin
                        m_valid <= 1'b1;
                        if ((row == 8'd71) && (col == 8'd127)) begin
                            done  <= 1'b1;
                            state <= S_IDLE;
                        end else begin
                            if (col == 8'd127) begin
                                col <= 8'd0;
                                row <= row + 1'b1;
                            end else
                                col <= col + 1'b1;
                            i <= 6'd0;
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

    // ---- 定点量化: real = round(acc*MOUT_Q32/2^32)，半舍入远离零，clamp 0..255 ----
    function [8:0] quantize;
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
                quantize = 9'd0;
            else if (p >= 32'sd255)
                quantize = 9'd255;
            else
                quantize = {1'b0, p[7:0]};
        end
    endfunction

endmodule
