/************************************************************\
**	Copyright (c) 2012-2025 Anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Build time: Aug 27 2026 16:21:00
**	TD version	:	6.2.168116
************************************************************/
`timescale 1ns/1ps
module ram_accumulate
(
  input   [19:0]                dia,
  input   [7:0]                 addra,
  input                         cea,
  input                         clka,
  output  [19:0]                dob,
  input   [7:0]                 addrb,
  input                         ceb,
  input                         clkb
);

  ram_abaf7d9fc0bb
  #(
      .DATA_WIDTH_A(20),
      .ADDR_WIDTH_A(8),
      .DATA_DEPTH_A(256),
      .DATA_WIDTH_B(20),
      .ADDR_WIDTH_B(8),
      .DATA_DEPTH_B(256),
      .REGMODE_A("NOREG"),
      .WRITEMODE_A("NORMAL"),
      .RESETMODE_A("ASYNC"),
      .INIT_FILE("NONE"),
      .REGMODE_B("NOREG"),
      .FILL_ALL("00000000000000000000"),
      .WRITEMODE_B("NORMAL"),
      .RESETMODE_B("ASYNC")
  )ram_abaf7d9fc0bb_Inst
  (
      .dia(dia),
      .addra(addra),
      .cea(cea),
      .clka(clka),
      .dob(dob),
      .addrb(addrb),
      .ceb(ceb),
      .clkb(clkb)
  );
endmodule
