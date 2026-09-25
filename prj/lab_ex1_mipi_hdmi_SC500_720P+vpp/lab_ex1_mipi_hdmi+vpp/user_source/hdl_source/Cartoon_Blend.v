`timescale 1ns / 1ps

module Cartoon_Blend #(
    parameter IMG_WIDTH  = 1024,
    parameter IMG_HEIGHT = 600
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

    // =========================================================================
    // 卡通化边缘合成模块 (Cartoon Edge Blend)
    // =========================================================================
    // 功能：将 Sobel 边缘二值 mask 叠加到色块化 RGB888 像素上，
    //       边缘位置输出黑色描边 (24'h000000)，非边缘位置透传彩色像素。
    //
    // 接口约定：
    //   I_color_tdata : 上游 Color_Quantize 输出的量化 RGB888 像素
    //   I_edge_flag   : 上游 Sobel_edge 输出的边缘二值标志 (1=边缘, 0=非边缘)
    //   两路输入已在同一拍对齐（由上层 top 延时链保证），本模块不做任何延时。
    //
    // 实现方式：纯组合逻辑合成，无内部流水打拍，控制信号直接透传。
    // =========================================================================

    // -------------------------------------------------------------------------
    // 控制信号直接透传（组合逻辑，零延迟）
    // -------------------------------------------------------------------------
    assign O_tvalid = I_tvalid;
    assign O_tlast  = I_tlast;
    assign O_tuser  = I_tuser;

    // -------------------------------------------------------------------------
    // 像素合成：边缘=1 输出黑色描边，否则透传彩色像素
    // -------------------------------------------------------------------------
    assign O_tdata = (I_edge_flag) ? 24'h000000 : I_color_tdata;

endmodule