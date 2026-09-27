//=============================================================================
// bilateral_rom_ip.v —— TD 官方 ROM IP 的仿真替身（同名同端口模块）
//-----------------------------------------------------------------------------
// 用法（两条路线，与 cnn_rom_ip.v 一致）:
//   A. 官方 IP 路线: 在 TD IP Generator 里生成同名 ROM（按下表参数），本文件被
//      `ifndef TD_SYN 排除，TD 综合用官方 IP（同步读: addra 当拍、doa 下一拍有效）。
//   B. 行为级路线: 不加 IP，本文件提供仿真/综合两用 ROM；综合时 TD 会把
//      initial+$readmemh 的存储器自动推断为块 ROM。
//   仿真: 本文件 + bilateral_filter_3x3.v 一起编译即可（ModelSim 无需 TD IP）。
//   替身为【同步读】(与 TD ROM IP 同拍语义)，引擎按 1 拍读延迟设计。
//
// IP 规格表:
//   bilateral_rom_range  8bit x 256   bilateral_range.hex (距离核, sigma_r=35)
//   bilateral_rom_recip 16bit x 2048  bilateral_recip.hex  (倒数, Q0.16)
//-----------------------------------------------------------------------------
`timescale 1ns / 1ps

`ifndef TD_SYN

module bilateral_rom_range (
    output reg [7:0]  doa,
    input      [7:0]  addra,
    input             clka
);
    reg [7:0] mem [0:255];
    initial $readmemh("bilateral_range.hex", mem);
    always @(posedge clka) doa <= mem[addra];
endmodule

module bilateral_rom_recip (
    output reg [15:0] doa,
    input      [10:0] addra,
    input             clka
);
    reg [15:0] mem [0:2047];
    initial $readmemh("bilateral_recip.hex", mem);
    always @(posedge clka) doa <= mem[addra];
endmodule

`endif
