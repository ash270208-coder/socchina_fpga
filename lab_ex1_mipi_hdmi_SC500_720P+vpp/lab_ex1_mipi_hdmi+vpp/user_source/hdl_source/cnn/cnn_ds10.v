//=============================================================================
// cnn_ds10.v —— 三通道 10x10 块平均降采样（1280x720 RGB → 128x72 RGB）
//-----------------------------------------------------------------------------
// 架构: 每条纹(10 行) OUT_W 个块累加器（每块一个 acc），双 bank 乒乓。
//   - 像素流逐拍累加进当前 bank 的块累加器（块列 = x/10）
//   - 条纹末（第 10 行行尾）: 切 bank → 在接下来 OUT_W 拍内排空旧 bank
//     （每拍输出 1 个块平均），同时新条纹的像素继续累加进新 bank（互不干扰）
//   - ÷100 用定点常数 10486/2^20（对常数块输入逐位精确，误差 ≤0.006 LSB）
// 输入: 视频流（tvalid/tuser 帧起始/tlast 行结束 + RGB888），宽高须为 10 的整倍数。
// 输出: O_tvalid 每块 1 拍（条纹末连续排空），O_x/O_y/tuser/tlast 对齐。
//=============================================================================
`timescale 1ns/1ps

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

    // ---- 双 bank 块累加器: [bank][块列] x 3 通道，每块和 ≤ 25500 < 2^15 ----
    reg [14:0] acc_r [0:1][0:OUT_W-1];
    reg [14:0] acc_g [0:1][0:OUT_W-1];
    reg [14:0] acc_b [0:1][0:OUT_W-1];
    integer i;

    reg [3:0]  bx, by;                   // 块内坐标
    reg [7:0]  ox;                       // 当前块列 0..OUT_W-1
    reg [7:0]  oy;                       // 当前条纹行 0..OUT_H-1
    reg [7:0]  stripe_oy;                // 排空期间锁存的条纹行号
    reg        bank;                     // 当前累加 bank
    reg        drain;                    // 排空状态
    reg [7:0]  drain_i;                  // 排空块号
    reg [1:0]  drain_sub;                // 排空节奏: 每 4 拍输出 1 块（下游每块需 ≥3 拍）

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            bx <= 4'd0;  by <= 4'd0;
            ox <= 8'd0;  oy <= 8'd0;
            bank <= 1'b0; drain <= 1'b0; drain_i <= 8'd0; drain_sub <= 2'd0; stripe_oy <= 8'd0;
            for (i = 0; i < OUT_W; i = i + 1) begin
                acc_r[0][i] <= 15'd0; acc_g[0][i] <= 15'd0; acc_b[0][i] <= 15'd0;
                acc_r[1][i] <= 15'd0; acc_g[1][i] <= 15'd0; acc_b[1][i] <= 15'd0;
            end
            O_tvalid <= 1'b0; O_tuser <= 1'b0; O_tlast <= 1'b0;
            O_tdata <= 24'd0; O_x <= 8'd0; O_y <= 8'd0;
        end else if (I_tuser) begin
            // 帧起始复位；同拍有效像素直接进新帧第 1 块
            bx <= 4'd0;  by <= 4'd0;
            ox <= 8'd0;  oy <= 8'd0;
            bank <= 1'b0; drain <= 1'b0; drain_i <= 8'd0; drain_sub <= 2'd0; stripe_oy <= 8'd0;
            for (i = 0; i < OUT_W; i = i + 1) begin
                acc_r[0][i] <= 15'd0; acc_g[0][i] <= 15'd0; acc_b[0][i] <= 15'd0;
                acc_r[1][i] <= 15'd0; acc_g[1][i] <= 15'd0; acc_b[1][i] <= 15'd0;
            end
            O_tvalid <= 1'b0;
            if (I_tvalid) begin
                acc_r[0][0] <= I_tdata[23:16];
                acc_g[0][0] <= I_tdata[15:8];
                acc_b[0][0] <= I_tdata[7:0];
                bx <= 4'd1;
            end
        end else begin
            O_tvalid <= 1'b0;
            // ---- 排空旧 bank（与输入累加并行；4 拍/块，供下游 3 拍适配器消化）----
            if (drain) begin
                if (drain_sub == 2'd3) begin
                    O_tvalid <= 1'b1;
                    O_tdata  <= {avg(acc_r[~bank][drain_i]),
                                 avg(acc_g[~bank][drain_i]),
                                 avg(acc_b[~bank][drain_i])};
                    O_tuser  <= (drain_i == 8'd0 && stripe_oy == 8'd0);
                    O_tlast  <= (drain_i == OUT_W-1);
                    O_x      <= drain_i;
                    O_y      <= stripe_oy;
                    drain_sub <= 2'd0;
                    if (drain_i == OUT_W-1)
                        drain <= 1'b0;
                    else
                        drain_i <= drain_i + 1'b1;
                end else begin
                    drain_sub <= drain_sub + 1'b1;
                end
            end
            // ---- 输入累加 ----
            if (I_tvalid) begin
                acc_r[bank][ox] <= acc_r[bank][ox] + I_tdata[23:16];
                acc_g[bank][ox] <= acc_g[bank][ox] + I_tdata[15:8];
                acc_b[bank][ox] <= acc_b[bank][ox] + I_tdata[7:0];
                if (I_tlast && by == SCALE-1) begin
                    // ---- 条纹完成: 切 bank、清新 bank、开始排空旧 bank ----
                    stripe_oy <= oy;
                    bank      <= ~bank;
                    drain     <= 1'b1;
                    drain_i   <= 8'd0;
                    for (i = 0; i < OUT_W; i = i + 1) begin
                        acc_r[~bank][i] <= 15'd0;
                        acc_g[~bank][i] <= 15'd0;
                        acc_b[~bank][i] <= 15'd0;
                    end
                    bx <= 4'd0; by <= 4'd0;
                    ox <= 8'd0;
                    oy <= (oy == OUT_H-1) ? 8'd0 : oy + 1'b1;
                end else if (bx == SCALE-1) begin
                    // ---- 块列回绕 ----
                    bx <= 4'd0;
                    if (I_tlast) begin
                        by <= by + 1'b1;
                        ox <= 8'd0;
                    end else
                        ox <= ox + 1'b1;
                end else begin
                    bx <= bx + 1'b1;
                end
            end
        end
    end

    // ---- /100 定点: (x * 10486 + 2^19) >>> 20（10486/2^20 ≈ 0.01，误差 ≤0.006 LSB）----
    function [7:0] avg;
        input [14:0] a;
        reg [34:0] t;
        begin
            t   = (a * 20'd10486) + 32'd524288;
            avg = t[34:20];
        end
    endfunction

endmodule
