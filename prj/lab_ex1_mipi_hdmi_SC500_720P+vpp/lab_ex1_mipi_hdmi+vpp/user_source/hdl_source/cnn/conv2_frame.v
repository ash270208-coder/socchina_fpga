//=============================================================================
// conv2_frame.v —— conv2 层（8→16, s2, 3x3）：引擎 + 官方 ROM IP + 私有同步 RAM
//-----------------------------------------------------------------------------
// 官方 ROM: cnn_rom_w2（64bit x 144，cnn_w_conv2_packed.dath）例化两份（偶/奇字）
// 输入 RAM: 同步读块 RAM 64bit x 9216（每像素 1 字 = 8 输入通道）
// 注意: 组合读数组会被综合成分布式 RAM(LUTRAM)，必须用 cnn_ram（同步读）
//=============================================================================
`timescale 1ns/1ps

module conv2_frame (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        wr_en,
    input  wire [13:0] wr_addr,
    input  wire [63:0] wr_data,
    input  wire        start,
    output wire [127:0] m_data,
    output wire        m_valid,
    output wire        done
);

    wire [10:0] rom_addr_e, rom_addr_o;
    wire [63:0] w_doa_e, w_doa_o;
    wire [13:0] ram_raddr;
    wire [63:0] ram_rdata;

    cnn_rom_w2 u_rom_e (.doa(w_doa_e), .addra(rom_addr_e[7:0]), .clka(clk));
    cnn_rom_w2 u_rom_o (.doa(w_doa_o), .addra(rom_addr_o[7:0]), .clka(clk));

    cnn_ram #(.DW(64), .AW(14), .DEPTH(9216)) u_fb (
        .clk(clk), .we(wr_en), .waddr(wr_addr), .wdata(wr_data),
        .raddr(ram_raddr), .rdata(ram_rdata));

    conv_frame #(
        .IMG_W(128), .IMG_H(72), .CIN(8), .COUT(16),
        .K(3), .STRIDE(2), .PAD(1), .TAPS(72), .NUM_GRP(2),
        .OUT_W(64), .OUT_H(36), .WOUT_BITS(128), .AW(14), .RAM_W(64),
        .B_MEM("sim/cnn_data/b_conv2.mem"),
        .MOUT_Q32(32'sd56261780)
    ) u_eng (
        .clk(clk), .rst_n(rst_n),
        .start(start), .m_data(m_data), .m_valid(m_valid), .done(done),
        .ram_raddr(ram_raddr), .ram_rdata(ram_rdata),
        .rom_addr_e(rom_addr_e), .rom_addr_o(rom_addr_o),
        .w_doa_e(w_doa_e), .w_doa_o(w_doa_o)
    );

endmodule
