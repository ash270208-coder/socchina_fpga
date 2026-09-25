//=============================================================================
// cnn_ram.v —— 同步读块 RAM（1 写口 + 1 读口，读延迟 1 拍）
//-----------------------------------------------------------------------------
// 为什么必须同步读: 组合读数组会被综合器推断成【分布式 RAM(LUTRAM)】，把查找表
// 当存储器用（上一版综合在此烧掉 36,864 个 LUT 并导致布局报错 PHY-9009）。
// 同步读（地址寄存、数据下一拍）才会映射到块 RAM(ERAM)。
// 引擎侧已按"地址/数据各流水 1 拍"设计，与权重 ROM 的 doa 同拍对齐。
//
// 用法:
//   cnn_ram #(.DW(64), .AW(14), .DEPTH(9216)) u_ram (
//       .clk(clk), .we(we), .waddr(waddr), .wdata(wdata),
//       .raddr(raddr), .rdata(rdata));
//=============================================================================
`timescale 1ns/1ps

module cnn_ram #(
    parameter DW    = 64,          // 字宽（bit）
    parameter AW    = 14,          // 地址位宽
    parameter DEPTH = 9216         // 深度（字数）
)(
    input  wire            clk,
    input  wire            we,
    input  wire [AW-1:0]   waddr,
    input  wire [DW-1:0]   wdata,
    input  wire [AW-1:0]   raddr,
    output reg  [DW-1:0]   rdata
);

    reg [DW-1:0] mem [0:DEPTH-1];

    always @(posedge clk) begin
        if (we)
            mem[waddr] <= wdata;
        rdata <= mem[raddr];
    end

endmodule
