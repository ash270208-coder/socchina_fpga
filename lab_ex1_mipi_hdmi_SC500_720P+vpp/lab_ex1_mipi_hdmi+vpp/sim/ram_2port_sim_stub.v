`timescale 1ns / 1ps
//=============================================================================
// ram_2port_sim_stub.v - SIMULATION-ONLY behavioural model of the TD IP
//                         "ram_2port" (256 x 20, true dual port, NOREG read)
//-----------------------------------------------------------------------------
//   WHY: tb_board_a_face_cdc.v elaborates the whole board_a_net_wrapper, which
//        pulls in cnn_ds10 -> ram_2port (a TD-generated ERAM IP). ModelSim has
//        no model for that IP, so elaboration stops with
//        "Module 'ram_2port' is not defined".
//
//   HOW : 1) compile this file only into the ModelSim work library;
//         2) never add it to td_project/camera_to_dsi_display.al;
//         3) never put it in user_source/ (TD would then see two ram_2port).
//
//   The timing accuracy is irrelevant here: the CDC testbench only exercises
//   board_a_net_wrapper's RX parser -> pixel-clock synchroniser path and forces
//   the UDP/MAC side, so the CNN accumulators are never used functionally.
//=============================================================================
module ram_2port (
    output wire [19:0] doa,
    input  wire [19:0] dia,
    input  wire [7:0]  addra,
    input  wire        wea,
    input  wire        cea,
    input  wire        clka,
    output wire [19:0] dob,
    input  wire [19:0] dib,
    input  wire [7:0]  addrb,
    input  wire        web,
    input  wire        ceb,
    input  wire        clkb
);

    reg [19:0] mem [0:255];
    reg [19:0] qa;
    reg [19:0] qb;

    assign doa = qa;
    assign dob = qb;

    always @(posedge clka) if (cea && wea) mem[addra] <= dia;
    always @(posedge clkb) if (ceb && web) mem[addrb] <= dib;

    // REGMODE = "NOREG": asynchronous read, matching the IP configuration that
    // cnn_ds10 relies on for its read-modify-write accumulator.
    always @* qa = mem[addra];
    always @* qb = mem[addrb];

endmodule
