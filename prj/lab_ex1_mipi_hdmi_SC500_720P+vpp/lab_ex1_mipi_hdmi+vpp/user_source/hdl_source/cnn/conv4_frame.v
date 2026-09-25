//=============================================================================
// conv4_frame.v —— conv4 层（32→32, s1, 3x3）：引擎 + 官方 ROM IP + 私有同步 RAM
//-----------------------------------------------------------------------------
// 官方 ROM: cnn_rom_w4（64bit x 1152，cnn_w_conv4_packed.dath）例化两份（偶/奇字）
// 输入 RAM: 同步读块 RAM 256bit x 576（每像素 1 字 = 32 输入通道）
//=============================================================================
`timescale 1ns/1ps

module conv4_frame (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        wr_en,
    input  wire [13:0] wr_addr,
    input  wire [255:0] wr_data,
    input  wire        start,
    output wire [255:0] m_data,
    output wire        m_valid,
    output wire        done
);

    wire [10:0] rom_addr_e, rom_addr_o;
    wire [63:0] w_doa_e, w_doa_o;
    wire [13:0] ram_raddr;
    wire [255:0] ram_rdata;

    cnn_rom_w4 u_rom_e (.doa(w_doa_e), .addra(rom_addr_e), .clka(clk));
    cnn_rom_w4 u_rom_o (.doa(w_doa_o), .addra(rom_addr_o), .clka(clk));

    cnn_ram #(.DW(256), .AW(14), .DEPTH(576)) u_fb (
        .clk(clk), .we(wr_en), .waddr(wr_addr), .wdata(wr_data),
        .raddr(ram_raddr), .rdata(ram_rdata));

    conv_frame #(
        .IMG_W(32), .IMG_H(18), .CIN(32), .COUT(32),
        .K(3), .STRIDE(1), .PAD(1), .TAPS(288), .NUM_GRP(4),
        .OUT_W(32), .OUT_H(18), .WOUT_BITS(256), .AW(14), .RAM_W(256),
        .B_MEM("sim/cnn_data/b_conv4.mem"),
        .MOUT_Q32(32'sd17997652)
    ) u_eng (
        .clk(clk), .rst_n(rst_n),
        .start(start), .m_data(m_data), .m_valid(m_valid), .done(done),
        .ram_raddr(ram_raddr), .ram_rdata(ram_rdata),
        .rom_addr_e(rom_addr_e), .rom_addr_o(rom_addr_o),
        .w_doa_e(w_doa_e), .w_doa_o(w_doa_o)
    );

endmodule
