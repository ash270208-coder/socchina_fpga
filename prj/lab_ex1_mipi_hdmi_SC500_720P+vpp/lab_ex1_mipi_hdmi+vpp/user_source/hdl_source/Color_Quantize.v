`timescale 1ns / 1ps

module Color_Quantize #(
    parameter QUANT_BITS = 4
)(
    input               I_clk,
    input               I_rst_n,

    input               I_tlast,
    input               I_tuser,
    input      [23:0]   I_tdata,
    input               I_tvalid,

    output reg          O_tlast,
    output reg          O_tuser,
    output reg [23:0]   O_tdata,
    output reg          O_tvalid
);

    // =========================================================================
    // 1. 量化参数与位宽定义
    // =========================================================================
    localparam KEEP_BITS = (QUANT_BITS < 1)   ? 1   :
                           (QUANT_BITS > 8)   ? 8   : QUANT_BITS;
    localparam ZERO_BITS = 8 - KEEP_BITS;

    wire [7:0] in_r = I_tdata[23:16];
    wire [7:0] in_g = I_tdata[15:8];
    wire [7:0] in_b = I_tdata[7:0];

    // =========================================================================
    // 2. 流水线阶段 1: 量化运算（保留高位，低位补0）
    // =========================================================================
    reg [7:0] quant_r;
    reg [7:0] quant_g;
    reg [7:0] quant_b;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            quant_r <= 8'd0;
            quant_g <= 8'd0;
            quant_b <= 8'd0;
        end
        else if (I_tvalid) begin
            quant_r <= {in_r[7:8-KEEP_BITS], {ZERO_BITS{1'b0}}};
            quant_g <= {in_g[7:8-KEEP_BITS], {ZERO_BITS{1'b0}}};
            quant_b <= {in_b[7:8-KEEP_BITS], {ZERO_BITS{1'b0}}};
        end
    end

    // =========================================================================
    // 3. 流水线阶段 2: 输出寄存器（打拍对齐）
    // =========================================================================
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_tdata <= 24'd0;
        end
        else if (I_tvalid) begin
            O_tdata <= {quant_r, quant_g, quant_b};
        end
    end

    // =========================================================================
    // 4. 控制信号严格打拍对齐 (共 2 级流水线延迟)
    // =========================================================================
    reg [1:0] tvalid_shift;
    reg [1:0] tlast_shift;
    reg [1:0] tuser_shift;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            tvalid_shift <= 2'd0;
            tlast_shift  <= 2'd0;
            tuser_shift  <= 2'd0;
            O_tvalid     <= 1'b0;
            O_tlast      <= 1'b0;
            O_tuser      <= 1'b0;
        end
        else begin
            tvalid_shift <= {tvalid_shift[0], I_tvalid};
            tlast_shift  <= {tlast_shift[0],  I_tlast};
            tuser_shift  <= {tuser_shift[0],  I_tuser};
            O_tvalid     <= tvalid_shift[1];
            O_tlast      <= tlast_shift[1];
            O_tuser      <= tuser_shift[1];
        end
    end

endmodule