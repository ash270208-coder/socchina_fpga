/************************************************************\
**	Copyright (c) 2012-2025 Anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Build time: Sep 10 2026 21:46:42
**	TD version	:	6.2.168116
************************************************************/
`timescale 1ns/1ps
module frame_integral_bram
(
  input   [17:0]                dia,
  input   [14:0]                addra,
  input                         cea,
  input                         clka,
  output  [17:0]                dob,
  input   [14:0]                addrb,
  input                         ceb
);

  ram_5e6f4a9feab8
  #(
      .DATA_WIDTH_A(18),
      .ADDR_WIDTH_A(15),
      .DATA_DEPTH_A(25560),
      .DATA_WIDTH_B(18),
      .ADDR_WIDTH_B(15),
      .DATA_DEPTH_B(25560),
      .REGMODE_A("NOREG"),
      .WRITEMODE_A("NORMAL"),
      .RESETMODE_A("ASYNC"),
      .INIT_FILE("NONE"),
      .REGMODE_B("NOREG"),
      .FILL_ALL("000000000000000000"),
      .WRITEMODE_B("NORMAL"),
      .RESETMODE_B("ASYNC")
  )ram_5e6f4a9feab8_Inst
  (
      .dia(dia),
      .addra(addra),
      .cea(cea),
      .clka(clka),
      .dob(dob),
      .addrb(addrb),
      .ceb(ceb)
  );
endmodule
