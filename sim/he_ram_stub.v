`timescale 1ns/1ps
// ===========================================================================
// TD RAM IP 的行为级桩件（仅供 ModelSim 功能仿真）
//   TD 生成的 ram_2port / ram_accumulate 内部实例化安路原语
//   PH1P_LOGIC_ERAM，ModelSim 无法 elaborate，仿真时用本文件替代。
//
//   行为对齐真实 IP：
//     REGMODE = NOREG          -> 读延迟 1 拍（同步读）
//     WRITEMODE = READBEFOREWRITE -> 同一拍读同一地址时读到旧值
//     FILL_ALL = 0             -> 上电全 0
// ===========================================================================

// ---- 直方图统计用：A 口写, B 口读 ----
module ram_2port (
    input  wire        clka,
    input  wire        cea,
    input  wire        wea,
    input  wire [7:0]  addra,
    input  wire [19:0] dia,
    output wire [19:0] doa,
    input  wire        clkb,
    input  wire        ceb,
    input  wire        web,
    input  wire [7:0]  addrb,
    input  wire [19:0] dib,
    output wire [19:0] dob
);
    reg [19:0] mem [0:255];
    reg [19:0] doa_r, dob_r;
    integer k;
    initial begin
        for (k = 0; k < 256; k = k + 1) mem[k] = 20'd0;
        doa_r = 20'd0; dob_r = 20'd0;
    end
    always @(posedge clka) if (cea && wea) mem[addra] <= dia;
    always @(posedge clka) if (cea)        doa_r <= mem[addra];
    always @(posedge clkb) if (ceb)        dob_r <= mem[addrb];
    assign doa = doa_r;
    assign dob = dob_r;
endmodule

// ---- CDF 累加用：A 口写(无写使能), B 口读 ----
module ram_accumulate (
    input  wire [19:0] dia,
    input  wire [7:0]  addra,
    input  wire        cea,
    input  wire        clka,
    output wire [19:0] dob,
    input  wire [7:0]  addrb,
    input  wire        ceb,
    input  wire        clkb
);
    reg [19:0] mem [0:255];
    reg [19:0] dob_r;
    integer k;
    initial begin
        for (k = 0; k < 256; k = k + 1) mem[k] = 20'd0;
        dob_r = 20'd0;
    end
    always @(posedge clka) if (cea) mem[addra] <= dia;
    always @(posedge clkb) if (ceb) dob_r <= mem[addrb];
    assign dob = dob_r;
endmodule
