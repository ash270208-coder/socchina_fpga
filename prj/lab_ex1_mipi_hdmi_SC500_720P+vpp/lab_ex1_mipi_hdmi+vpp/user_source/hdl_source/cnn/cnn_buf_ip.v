//=============================================================================
// cnn_buf_ip.v —�?TD 官方 RAM IP 的仿真替身（同名同端口模块）
//-----------------------------------------------------------------------------
// 用法（与权重 ROM �?cnn_rom_ip.v 同一套路�?
//   A. 官方 IP 路线（本工程采用�? �?TD IP Generator 里生成下�?3 �?RAM IP�?//      **不要把本文件加进 TD 工程**（避免同名冲突）；TD 综合时用官方 IP�?//   B. 行为级路�? 若不�?IP，加本文件即可（同步读块 RAM 行为模型，TD 会推断块 RAM）�?//
// RAM IP 规格（端口命名与工程现有 al_ip/ram_2port 一致）:
//   | IP �?     | 位宽 | 深度  | 地址位宽 | 用�?|
//   | cnn_buf_a  | 64   | 9216  | 14       | bufA: x1(1�?像素) 复用 x3(4�?像素) |
//   | cnn_buf_b  | 128  | 2304  | 12       | bufB: x2(1�?像素) 复用 x4(2�?像素) |
//   | cnn_buf_in | 8    | 27648 | 15       | conv1 输入帧（3 平面�?|
//   TD 生成设置: 双口 RAM(DP_RAM，同 ram_2port) / **REGMODE = NOREG**（无输出寄存器，
//   读延�?1 拍，与引擎流水一致；若�?REG 会多 1 拍导致全错）/ �?init file�?//   例化只用�? 写口 A(cea,clka,wea,addra,dia) + 读口 B(ceb,clkb,addrb,dob)�?//   其余端口(doa,dib,web)已在 RTL 中置�?悬空，与官方 IP 的多余端口兼容�?//=============================================================================
`timescale 1ns/1ps

`ifndef TD_SYN

module cnn_buf_a (          // 64bit x 9216
    output [63:0] doa,
    input  [63:0] dia,
    input  [13:0] addra,
    input         wea,
    input         cea,
    input         clka,
    output reg [63:0] dob,
    input  [63:0] dib,
    input  [13:0] addrb,
    input         web,
    input         ceb,
    input         clkb
);
    reg [63:0] mem [0:9215];
    always @(posedge clka) if (wea && cea) mem[addra] <= dia;
    always @(posedge clkb) if (ceb) dob <= mem[addrb];
endmodule

module cnn_buf_b (          // 128bit x 2304
    output [127:0] doa,
    input  [127:0] dia,
    input  [11:0]  addra,
    input          wea,
    input          cea,
    input          clka,
    output reg [127:0] dob,
    input  [127:0] dib,
    input  [11:0]  addrb,
    input          web,
    input          ceb,
    input          clkb
);
    reg [127:0] mem [0:2303];
    always @(posedge clka) if (wea && cea) mem[addra] <= dia;
    always @(posedge clkb) if (ceb) dob <= mem[addrb];
endmodule

module cnn_buf_in (         // 8bit x 27648
    output [7:0]  doa,
    input  [7:0]  dia,
    input  [14:0] addra,
    input         wea,
    input         cea,
    input         clka,
    output reg [7:0]  dob,
    input  [7:0]  dib,
    input  [14:0] addrb,
    input         web,
    input         ceb,
    input         clkb
);
    reg [7:0] mem [0:27647];
    always @(posedge clka) if (wea && cea) mem[addra] <= dia;
    always @(posedge clkb) if (ceb) dob <= mem[addrb];
endmodule

`endif
