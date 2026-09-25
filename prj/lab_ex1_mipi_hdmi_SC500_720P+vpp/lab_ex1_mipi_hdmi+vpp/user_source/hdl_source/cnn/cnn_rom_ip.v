//=============================================================================
// cnn_rom_ip.v —— TD 官方 ROM IP 的仿真替身（同名同端口模块）
//-----------------------------------------------------------------------------
// 用法（两条路线，见 FPGA_CNN实现方案.md §5/§9）:
//   A. 官方 IP 路线: 在 TD IP Generator 里生成同名 ROM（DATA_WIDTH_A/ADDR_WIDTH_A/
//      DATA_DEPTH_A/INIT_FILE 按下表），本文件被 `ifndef TD_SYN 排除，
//      TD 综合用官方 IP（同步读: addra 当拍、doa 下一拍有效）。
//   B. 行为级路线: 不加 IP，本文件提供仿真/综合两用 ROM；综合时 TD 会把
//      initial+$readmemh 的存储器自动推断为块 ROM。
//   仿真: 本文件 + 各引擎模块一起编译即可（ModelSim 无需 TD IP）。
//   替身为【同步读】(与 TD ROM IP 同拍语义)，引擎按 1 拍读延迟设计。
//
// IP 规格表（与 mem_dath/ 下的 .dath 一一对应）:
//   cnn_rom_w1  64bit x 27     cnn_w_conv1_packed.dath
//   cnn_rom_w2  64bit x 144    cnn_w_conv2_packed.dath
//   cnn_rom_w3  64bit x 576    cnn_w_conv3_packed.dath
//   cnn_rom_w4  64bit x 1152   cnn_w_conv4_packed.dath
//   cnn_rom_wh  64bit x 64     cnn_w_head_packed.dath
//   cnn_rom_exp 16bit x 1024   cnn_lut_exp.dath
//=============================================================================
`timescale 1ns/1ps

`ifndef TD_SYN

module cnn_rom_w1 (
    output reg [63:0] doa,
    input      [4:0]  addra,
    input             clka
);
    reg [63:0] mem [0:26];
    initial $readmemh("sim/cnn_data/w_conv1_packed.mem", mem);
    always @(posedge clka) doa <= mem[addra];
endmodule

module cnn_rom_w2 (
    output reg [63:0] doa,
    input      [7:0]  addra,
    input             clka
);
    reg [63:0] mem [0:143];
    initial $readmemh("sim/cnn_data/w_conv2_packed.mem", mem);
    always @(posedge clka) doa <= mem[addra];
endmodule

module cnn_rom_w3 (
    output reg [63:0] doa,
    input      [9:0]  addra,
    input             clka
);
    reg [63:0] mem [0:575];
    initial $readmemh("sim/cnn_data/w_conv3_packed.mem", mem);
    always @(posedge clka) doa <= mem[addra];
endmodule

module cnn_rom_w4 (
    output reg [63:0] doa,
    input      [10:0] addra,
    input             clka
);
    reg [63:0] mem [0:1151];
    initial $readmemh("sim/cnn_data/w_conv4_packed.mem", mem);
    always @(posedge clka) doa <= mem[addra];
endmodule

module cnn_rom_wh (
    output reg [63:0] doa,
    input      [5:0]  addra,
    input             clka
);
    reg [63:0] mem [0:63];
    initial $readmemh("sim/cnn_data/w_head_packed.mem", mem);
    always @(posedge clka) doa <= mem[addra];
endmodule

module cnn_rom_exp (
    output reg [15:0] doa,
    input      [9:0]  addra,
    input             clka
);
    reg [15:0] mem [0:1023];
    initial $readmemh("sim/cnn_data/lut_exp.mem", mem);
    always @(posedge clka) doa <= mem[addra];
endmodule

`endif
