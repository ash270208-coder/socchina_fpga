`timescale 1ns / 1ps

module Cartoon_Blend #(
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720
)(
    input               I_clk,
    input               I_rst_n,

    input               I_tlast,
    input               I_tuser,
    input      [23:0]   I_color_tdata,
    input               I_edge_flag,
    input               I_tvalid,

    output              O_tlast,
    output              O_tuser,
    output     [23:0]   O_tdata,
    output              O_tvalid
);

    // 控制信号直接透传
    assign O_tvalid = I_tvalid;
    assign O_tlast  = I_tlast;
    assign O_tuser  = I_tuser;

    // 像素合成：边缘=1 输出黑色描边，否则透传彩色像素
    assign O_tdata = (I_edge_flag) ? 24'h000000 : I_color_tdata;

endmodule
