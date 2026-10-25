`timescale 1ns/1ps
//=============================================================================
// cnn_ds10.v —— 三通道 10x10 块平均降采样（1280x720 RGB → 128x72 RGB）
//-----------------------------------------------------------------------------
// 【v2：纵向累加器改为 ERAM —— 这一版是为"装得下"重写的】
//
// 为什么重写：v1 用"2 bank x 128 块 x 3 通道 x 15 位 = 11 520 个触发器"的
//   寄存器堆做纵向累加。在 PH1P 里 1 个 slice = 1 个 LUT + 2 个触发器，
//   这 11 520 个触发器本身要占 ~5 760 个 slice；更致命的是 256 深寄存器堆的
//   **写译码 + 读 mux** 又额外吃掉了 ~9 200 个 LUT（实测 u_cnn_ds10 = 9 206 LUT
//   + 11 619 FF），把整芯片顶到 #slice* 26 148 / 21 216 = 123%。
//   实测确认瓶颈是 LUT 不是触发器（#with luts 20 057 vs #reg only 1 114），
//   所以只把触发器搬进 ERAM 是不够的 —— 必须连"寄存器堆选址"一起消掉。
//   （另一条实测教训：v1 的"条纹末 for 循环清 bank"删掉后 LUT 一个没省，
//     因为安逻辑触发器自带同步复位端，清零 mux 是免费的。）
//
// v2 架构（把 10x10 拆成"先横后纵"）：
//   a) 横向段和：块内 10 个像素在寄存器里累加（bx==0 装载，其后相加）
//      -> blk_r/g/b = 该块在这一行的 10 像素和
//   b) 纵向累加：3 个 ram_2port(256x20 真双口 ERAM)，
//      地址 = {bank, ox[6:0]}（bit7 选 bank，低 7 位是块列号）
//      **端口 A** 做读-改-写：dia = doa + blk，每个块末写一次
//      （ram_2port 是 REGMODE="NOREG"，读是组合的，所以同拍就能完成 RMW）
//   c) 初始化：条纹**第 0 行装载**（by==0 时 dia = blk，不累加），
//      等效于"清零后再累加" -> 完全不需要清 bank 的通路，也不需要上电清零
//   d) 排空：条纹末切 bank 后用**端口 B** 读刚完成那个 bank 的 128 个块和，
//      分时共用一个乘法器 ÷100，输出
//      端口 A/B 地址不同（一个 {bank,ox} 一个 {~bank,ox}），天然无冲突
//
// 精度：÷100 用定点 (x*10486 + 2^19) >>> 20，10486/2^20 ≈ 0.01，误差 ≤0.006 LSB
// 输出：O_tvalid 每块 1 拍（4 拍 1 个块，供下游 pixel_to_bytes 3 拍拆字节）
//
// 验证：sim/tb_cnn_ds10.v —— tb 独立地从整帧缓存重算 10x10 块和再逐位比，
//       不是镜像本模块的累加过程。128x72=9216 块全部一致。
//=============================================================================
module cnn_ds10 #(
    parameter IN_W  = 1280,
    parameter IN_H  = 720,
    parameter SCALE = 10,
    parameter OUT_W = 128,
    parameter OUT_H = 72
)(
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_tvalid,
    input  wire        I_tuser,
    input  wire        I_tlast,
    input  wire [23:0] I_tdata,          // RGB888
    output reg         O_tvalid,
    output reg         O_tuser,
    output reg         O_tlast,
    output reg  [23:0] O_tdata,
    output reg  [7:0]  O_x,
    output reg  [7:0]  O_y
);

    // ---- 块内坐标 / 块列号 / 条纹行号 ----
    localparam [3:0] BLK_LAST = SCALE - 1;   // 块内最后一个像素/行的下标 (9)
    reg [3:0]  bx;          // 块内列 0..9
    reg [3:0]  by;          // 块内行 0..9（条纹内行号）
    reg [7:0]  ox;          // 块列号 0..127
    reg [7:0]  oy;          // 条纹行号 0..71
    reg [7:0]  stripe_oy;   // 排空期间锁存的条纹行号
    reg        bank;        // 当前累加 bank

    // =========================================================================
    // 横向段和（寄存器）
    // =========================================================================
    reg  [14:0] hsum_r, hsum_g, hsum_b;
    wire [14:0] blk_r = hsum_r + {7'd0, I_tdata[23:16]};   // 含当前像素的完整块和
    wire [14:0] blk_g = hsum_g + {7'd0, I_tdata[15: 8]};
    wire [14:0] blk_b = hsum_b + {7'd0, I_tdata[ 7: 0]};

    wire        blk_end   = I_tvalid && (bx == BLK_LAST);
    wire        first_row = (by == 4'd0);

    // =========================================================================
    // 纵向累加器：3 个 256x20 真双口 ERAM
    //   端口 A：累加（条纹第 0 行装载，其余行相加）
    //   端口 B：排空（读完整块和）
    // =========================================================================
    reg  [7:0]  dr_ox;
    wire [7:0]  addr_a = {bank,  ox};        // 端口 A 地址
    wire [7:0]  addr_b = {~bank, dr_ox};     // 端口 B 地址

    wire [19:0] doa_r, doa_g, doa_b;
    wire [19:0] dob_r, dob_g, dob_b;

    // 第 0 行装载（等效初始化），其余行累加
    wire [19:0] dia_r = first_row ? {5'd0, blk_r} : (doa_r + {5'd0, blk_r});
    wire [19:0] dia_g = first_row ? {5'd0, blk_g} : (doa_g + {5'd0, blk_g});
    wire [19:0] dia_b = first_row ? {5'd0, blk_b} : (doa_b + {5'd0, blk_b});

    ram_2port u_acc_r (
        .doa(doa_r), .dia(dia_r), .addra(addr_a), .wea(blk_end), .cea(1'b1), .clka(I_clk),
        .dob(dob_r), .dib(20'd0), .addrb(addr_b), .web(1'b0),    .ceb(1'b1), .clkb(I_clk)
    );
    ram_2port u_acc_g (
        .doa(doa_g), .dia(dia_g), .addra(addr_a), .wea(blk_end), .cea(1'b1), .clka(I_clk),
        .dob(dob_g), .dib(20'd0), .addrb(addr_b), .web(1'b0),    .ceb(1'b1), .clkb(I_clk)
    );
    ram_2port u_acc_b (
        .doa(doa_b), .dia(dia_b), .addra(addr_a), .wea(blk_end), .cea(1'b1), .clka(I_clk),
        .dob(dob_b), .dib(20'd0), .addrb(addr_b), .web(1'b0),    .ceb(1'b1), .clkb(I_clk)
    );

    // =========================================================================
    // 排空：分时共用一个乘法器算 R/G/B 的 ÷100
    // =========================================================================
    reg        dr_on;
    reg [1:0]  dr_sub;
    reg [14:0] m_in;
    reg  [7:0] dres_r, dres_g;
    wire [34:0] m_out = (m_in * 20'd10486) + 32'd524288;   // ≈ x/100，误差 ≤0.006 LSB

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            bx <= 4'd0;  by <= 4'd0;
            ox <= 8'd0;  oy <= 8'd0;
            bank <= 1'b0; stripe_oy <= 8'd0;
            hsum_r <= 15'd0; hsum_g <= 15'd0; hsum_b <= 15'd0;
            O_tvalid <= 1'b0; O_tuser <= 1'b0; O_tlast <= 1'b0;
            O_tdata <= 24'd0; O_x <= 8'd0; O_y <= 8'd0;
            dr_on <= 1'b0; dr_ox <= 8'd0; dr_sub <= 2'd0;
            m_in <= 15'd0; dres_r <= 8'd0; dres_g <= 8'd0;
        end else if (I_tuser) begin
            // 帧起始复位；同拍有效像素直接进新帧第 1 块（bx==0 分支负责装载）
            bx <= 4'd0;  by <= 4'd0;
            ox <= 8'd0;  oy <= 8'd0;
            bank <= 1'b0; stripe_oy <= 8'd0;
            dr_on <= 1'b0; dr_ox <= 8'd0; dr_sub <= 2'd0;
            O_tvalid <= 1'b0; O_tuser <= 1'b0; O_tlast <= 1'b0;
            if (I_tvalid) begin
                hsum_r <= {7'd0, I_tdata[23:16]};
                hsum_g <= {7'd0, I_tdata[15: 8]};
                hsum_b <= {7'd0, I_tdata[ 7: 0]};
                bx <= 4'd1;
            end
        end else begin
            O_tvalid <= 1'b0;

            // ---------------- 输入侧：横向段和 + 纵向累加（端口 A）----------------
            //   端口 A 的写由 blk_end 直接驱动（组合），地址在整个块期间稳定，
            //   ram_2port 读是组合的，所以"读-改-写"在同一拍完成，无需状态机。
            if (I_tvalid) begin
                if (bx == 4'd0) begin
                    hsum_r <= {7'd0, I_tdata[23:16]};
                    hsum_g <= {7'd0, I_tdata[15: 8]};
                    hsum_b <= {7'd0, I_tdata[ 7: 0]};
                end else begin
                    hsum_r <= blk_r;
                    hsum_g <= blk_g;
                    hsum_b <= blk_b;
                end

                if (I_tlast && by == BLK_LAST) begin
                    // ---- 条纹完成：切 bank，开始排空刚完成那个 bank ----
                    stripe_oy <= oy;
                    bank      <= ~bank;
                    dr_on     <= 1'b1;
                    dr_ox     <= 8'd0;
                    dr_sub    <= 2'd0;
                    bx <= 4'd0; by <= 4'd0;
                    ox <= 8'd0;
                    oy <= (oy == OUT_H-1) ? 8'd0 : oy + 1'b1;
                end else if (bx == BLK_LAST) begin
                    // ---- 块列回绕 ----
                    bx <= 4'd0;
                    if (I_tlast) begin
                        by <= by + 1'b1;
                        ox <= 8'd0;
                    end else begin
                        ox <= ox + 1'b1;
                    end
                end else begin
                    bx <= bx + 1'b1;
                end
            end

            // ---------------- 排空侧：端口 B 读 + 分时 ÷100 + 输出 ----------------
            //   4 拍 1 个块（与 v1 完全一致，下游 pixel_to_bytes 按 3 拍拆字节）
            if (dr_on) begin
                case (dr_sub)
                2'd0: begin
                    m_in   <= dob_r[14:0];
                    dr_sub <= 2'd1;
                end
                2'd1: begin
                    dres_r <= m_out[27:20];
                    m_in   <= dob_g[14:0];
                    dr_sub <= 2'd2;
                end
                2'd2: begin
                    dres_g <= m_out[27:20];
                    m_in   <= dob_b[14:0];
                    dr_sub <= 2'd3;
                end
                default: begin
                    O_tvalid <= 1'b1;
                    O_tdata  <= {dres_r, dres_g, m_out[27:20]};
                    O_tuser  <= (dr_ox == 8'd0 && stripe_oy == 8'd0);
                    O_tlast  <= (dr_ox == OUT_W-1);
                    O_x      <= dr_ox;
                    O_y      <= stripe_oy;
                    dr_sub   <= 2'd0;
                    if (dr_ox == OUT_W-1)
                        dr_on <= 1'b0;
                    else
                        dr_ox <= dr_ox + 1'b1;
                end
                endcase
            end
        end
    end

endmodule
