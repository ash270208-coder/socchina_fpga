`timescale 1ns/1ps
//=============================================================================
// PH1P_LOGIC_ERAM_sim.v —— **仅用于 ModelSim 仿真** 的 PH1P_LOGIC_ERAM 行为模型
//
// 安逻辑的 PH1P_LOGIC_ERAM 是 TD 的厂商原语，ModelSim 里没有，会报
//   "Module 'PH1P_LOGIC_ERAM' is not defined"。
// 这个文件只加进**仿真**的编译列表，不进设计、不进 .al。
//
// 只实现本设计用到的行为（够验证用）：
//   * MODE="DP"，两个端口都能读写
//   * REGMODE_A/B = "NOREG" -> 读是**组合**的（doa 跟着 addra 走）
//     这正好对应 cnn_ds10 v2 里"读-改-写同拍完成"的用法
//   * WRITEMODE = "READBEFOREWRITE" -> 写的那一拍读出的还是旧值
//     （组合读天然就是这个行为）
//   * bea/beb 忽略（生成的 IP 把它们固定接 0）
//
// ⚠ 存储内容**故意不初始化**（保持 X）：cnn_ds10 v2 靠"条纹第 0 行装载"
//   而不是靠清 bank 来初始化，所以任何"先读后写"的地址都会变成 X 并被
//   testbench 抓到。这是刻意的强校验，不要改成初始化为 0。
//=============================================================================
module PH1P_LOGIC_ERAM #(
    parameter DATA_WIDTH_A = 20,
    parameter DATA_WIDTH_B = 20,
    parameter ADDR_WIDTH_A = 8,
    parameter ADDR_WIDTH_B = 8,
    parameter DATA_DEPTH_A = 256,
    parameter DATA_DEPTH_B = 256,
    parameter MODE           = "DP",
    parameter REGMODE_A      = "NOREG",
    parameter REGMODE_B      = "NOREG",
    parameter WRITEMODE_A    = "READBEFOREWRITE",
    parameter WRITEMODE_B    = "READBEFOREWRITE",
    parameter IMPLEMENT      = "20K",
    parameter ECC_ENCODE     = "DISABLE",
    parameter ECC_DECODE     = "DISABLE",
    parameter CLKMODE        = "ASYNC",
    parameter SSROVERCE      = "DISABLE",
    parameter OREGSET_A      = "SET",
    parameter OREGSET_B      = "SET",
    parameter RESETMODE_A    = "ASYNC",
    parameter RESETMODE_B    = "ASYNC",
    parameter ASYNC_RESET_RELEASE_A = "ASYNC",
    parameter ASYNC_RESET_RELEASE_B = "SYNC",
    parameter INIT_FILE      = "NONE",
    parameter FILL_ALL       = "NONE"
)(
    input  [DATA_WIDTH_A-1:0] dia,
    input  [DATA_WIDTH_B-1:0] dib,
    input  [ADDR_WIDTH_A-1:0] addra,
    input  [ADDR_WIDTH_B-1:0] addrb,
    input                     cea,
    input                     ceb,
    input                     ocea,
    input                     oceb,
    input                     clka,
    input                     clkb,
    input                     wea,
    input                     web,
    input                     bea,
    input                     beb,
    input                     rsta,
    input                     rstb,
    input  [DATA_WIDTH_A-1:0] ecc_sbiterrinj,
    input  [DATA_WIDTH_A-1:0] ecc_dbiterrinj,
    output [DATA_WIDTH_A-1:0] doa,
    output [DATA_WIDTH_B-1:0] dob,
    output                    ecc_sbiterr,
    output                    ecc_dbiterr
);

    reg [DATA_WIDTH_A-1:0] mem [0:DATA_DEPTH_A-1];   // 故意不初始化，保持 X

    // NOREG：组合读
    assign doa = mem[addra];
    assign dob = mem[addrb];

    assign ecc_sbiterr = 1'b0;
    assign ecc_dbiterr = 1'b0;

    // 端口 A 写（READBEFOREWRITE 由组合读天然保证）
    always @(posedge clka) begin
        if (cea && wea)
            mem[addra] <= dia;
    end

    // 端口 B 写
    always @(posedge clkb) begin
        if (ceb && web)
            mem[addrb] <= dib;
    end

endmodule
