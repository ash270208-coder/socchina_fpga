//=============================================================================
// conv3_frame.v —— conv3 层（16→32, s2, 3x3）：引擎 + 官方 ROM IP + 私有同步 RAM
//-----------------------------------------------------------------------------
// 官方 ROM: cnn_rom_w3（64bit x 576，cnn_w_conv3_packed.dath）例化两份（偶/奇字）
// 输入 RAM: 同步读块 RAM 128bit x 2304（每像素 1 字 = 16 输入通道）
//=============================================================================
`timescale 1ns/1ps

module conv3_frame (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        wr_en,
    input  wire [13:0] wr_addr,
    input  wire [127:0] wr_data,
    input  wire        start,
    output wire [255:0] m_data,
    output wire        m_valid,
    output wire        done
);

    wire [10:0] rom_addr_e, rom_addr_o;
    wire [63:0] w_doa_e, w_doa_o;
    wire [13:0] ram_raddr;
    wire [127:0] ram_rdata;

    cnn_rom_w3 u_rom_e (.doa(w_doa_e), .addra(rom_addr_e[9:0]), .clka(clk));
    cnn_rom_w3 u_rom_o (.doa(w_doa_o), .addra(rom_addr_o[9:0]), .clka(clk));

    cnn_ram #(.DW(128), .AW(14), .DEPTH(2304)) u_fb (
        .clk(clk), .we(wr_en), .waddr(wr_addr), .wdata(wr_data),
        .raddr(ram_raddr), .rdata(ram_rdata));

    conv_frame #(
        .IMG_W(64), .IMG_H(36), .CIN(16), .COUT(32),
        .K(3), .STRIDE(2), .PAD(1), .TAPS(144), .NUM_GRP(4),
        .OUT_W(32), .OUT_H(18), .WOUT_BITS(256), .AW(14), .RAM_W(128),
        .B_MEM("sim/cnn_data/b_conv3.mem"),
        .MOUT_Q32(32'sd25934300)
    ) u_eng (
        .clk(clk), .rst_n(rst_n),
        .start(start), .m_data(m_data), .m_valid(m_valid), .done(done),
        .ram_raddr(ram_raddr), .ram_rdata(ram_rdata),
        .rom_addr_e(rom_addr_e), .rom_addr_o(rom_addr_o),
        .w_doa_e(w_doa_e), .w_doa_o(w_doa_o)
    );

endmodule
