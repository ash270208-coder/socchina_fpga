//=============================================================================
// cnn_rom.v —— 权重/偏置 ROM 包装（接口固定，实现可切换）
//-----------------------------------------------------------------------------
// 接口与 TD IP Generator 生成的 ROM 完全一致：clka / addra / doa（同步读，1 拍延迟）
//
// 两种实现，用一个宏切换：
//   默认（不定义宏）        ：行为级 ROM，$readmemh 读 .mem
//                            → ModelSim 仿真直接可用（不需要安路原语库）
//   定义 `CNN_TD_ROM` 后综合 ：实例化官方原语 PH1P_LOGIC_ERAM，用 .dath 初始化
//                            → 与工程里 rom_weak_lut 同一模板，保证映射到 ERAM 块
//
// 用法（同一个 cnn_rom 例化，仿真/综合各自走对应实现）：
//   cnn_rom #(.DW(8), .AW(8), .DEPTH(256),
//             .INIT_FILE("sim/cnn_data/w_conv1.mem"),   // 仿真
//             .DATH_FILE("cnn_w_conv1.dath"))           // 综合
//   u_w_rom (.clka(clk), .addra(addr), .doa(data));
//
// TD 综合时：把 `CNN_TD_ROM` 加到工程的 Verilog Define（或在该文件顶部
// `define CNN_TD_ROM），并把 mem_dath/*.dath 拷到 TD 工程能找到的路径下。
//=============================================================================
module cnn_rom #(
    parameter integer DW        = 8,
    parameter integer AW        = 8,
    parameter integer DEPTH     = 256,
    parameter         INIT_FILE = "sim/cnn_data/w_conv1.mem",
    parameter         DATH_FILE = "cnn_w_conv1.dath"
)(
    input  wire          clka,
    input  wire [AW-1:0] addra,
    output wire [DW-1:0] doa
);

`ifdef CNN_TD_ROM
    //-------------------------------------------------------------------------
    // 官方 ERAM 原语（ROM 模式：wea=0、cea=1、dia=0）
    // 参数模板与 td_project/al_ip/rom_weak_lut/RTL/rom_*.v 完全一致
    //-------------------------------------------------------------------------
    PH1P_LOGIC_ERAM #(
        .DATA_WIDTH_A  (DW),
        .ADDR_WIDTH_A  (AW),
        .DATA_DEPTH_A  (DEPTH),
        .DATA_WIDTH_B  (DW),
        .ADDR_WIDTH_B  (AW),
        .DATA_DEPTH_B  (DEPTH),
        .MODE          ("SP"),
        .REGMODE_A     ("NOREG"),
        .IMPLEMENT     ("20K"),
        .DEBUGGABLE    ("NO"),
        .PACKABLE      ("NO"),
        .INIT_FILE     (DATH_FILE),
        .FILL_ALL      ("NONE")
    ) u_eram (
        .dia   ({DW{1'b0}}),
        .dib   ({DW{1'b0}}),
        .addra (addra),
        .addrb ({AW{1'b0}}),
        .cea   (1'b1),
        .ceb   (1'b0),
        .ocea  (1'b0),
        .oceb  (1'b0),
        .clka  (clka),
        .clkb  (1'b0),
        .wea   (1'b0),
        .web   (1'b0),
        .bea   (1'b0),
        .beb   (1'b0),
        .rsta  (1'b0),
        .rstb  (1'b0),
        .doa   (doa),
        .dob   ()
    );

`else
    //-------------------------------------------------------------------------
    // 行为级 ROM（ModelSim 仿真；TD 也能正常推断）
    //-------------------------------------------------------------------------
    reg [DW-1:0] mem    [0:DEPTH-1];
    reg [DW-1:0] dout_r;

    initial begin
        $readmemh(INIT_FILE, mem);
    end

    always @(posedge clka) begin
        dout_r <= mem[addra];
    end

    assign doa = dout_r;
`endif

endmodule
