`timescale 1ns / 1ps
// 仅用于 ModelSim elaboration 检查（不入工程、不入 .al）
module elab_top (
    input  wire        clk_50m,
    input  wire        por_arst_n,
    input  wire        I_pclk,
    input  wire        I_pclk_rst_n,
    input  wire        I_raw_tvalid,
    input  wire        I_raw_tuser,
    input  wire        I_raw_tlast,
    input  wire [23:0] I_raw_tdata,
    input  wire        phy1_rgmii_rx_clk,
    input  wire        phy1_rgmii_rx_ctl,
    input  wire [3:0]  phy1_rgmii_rx_data,
    output wire        phy1_rgmii_tx_clk,
    output wire        phy1_rgmii_tx_ctl,
    output wire [3:0]  phy1_rgmii_tx_data,
    output wire        phy_reset,
    output wire [3:0]  net_led
);
    board_a_net_wrapper u_net (
        .clk_50m            (clk_50m),
        .por_arst_n         (por_arst_n),
        .I_pclk             (I_pclk),
        .I_pclk_rst_n       (I_pclk_rst_n),
        .I_raw_tvalid       (I_raw_tvalid),
        .I_raw_tuser        (I_raw_tuser),
        .I_raw_tlast        (I_raw_tlast),
        .I_raw_tdata        (I_raw_tdata),
        .phy1_rgmii_rx_clk  (phy1_rgmii_rx_clk),
        .phy1_rgmii_rx_ctl  (phy1_rgmii_rx_ctl),
        .phy1_rgmii_rx_data (phy1_rgmii_rx_data),
        .phy1_rgmii_tx_clk  (phy1_rgmii_tx_clk),
        .phy1_rgmii_tx_ctl  (phy1_rgmii_tx_ctl),
        .phy1_rgmii_tx_data (phy1_rgmii_tx_data),
        .phy_reset          (phy_reset),
        .net_led            (net_led)
    );
endmodule
