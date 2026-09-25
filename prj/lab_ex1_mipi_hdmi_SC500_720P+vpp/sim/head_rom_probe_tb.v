`timescale 1ns/1ps
// 探针: 验证同步 ROM 替身时序 + head_frame 流水
module head_rom_probe_tb;
    reg clk=0, rst_n=0;
    integer t;

    // A) ROM 替身时序: 地址 0,1,2 → doa 应为 mem[0],mem[1],mem[2]（各晚 1 拍）
    reg [5:0] rom_addr = 0;
    wire [63:0] rom_doa;
    cnn_rom_wh u_rom (.doa(rom_doa), .addra(rom_addr), .clka(clk));

    always #5 clk = ~clk;

    initial begin
        rst_n=0;
        repeat (5) @(posedge clk); rst_n=1; repeat (2) @(posedge clk);
        $display("=== ROM 替身时序（w_head_packed 前 3 字）===");
        rom_addr = 6'd0; @(posedge clk); @(negedge clk);
        $display("addr0 后 1 拍 doa=%h (exp 0cf9cc0f0e090b61)", rom_doa);
        rom_addr = 6'd1; @(posedge clk); @(negedge clk);
        $display("addr1 后 1 拍 doa=%h (exp 00e519071bdef0f5)", rom_doa);
        rom_addr = 6'd2; @(posedge clk); @(negedge clk);
        $display("addr2 后 1 拍 doa=%h", rom_doa);
        $finish;
    end
endmodule
