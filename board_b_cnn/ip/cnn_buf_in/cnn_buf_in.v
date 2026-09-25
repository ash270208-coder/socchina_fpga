/************************************************************\
**	Copyright (c) 2012-2025 Anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Build time: Sep 21 2026 23:20:36
**	TD version	:	6.2.168116
************************************************************/
`timescale 1ns/1ps
module cnn_buf_in
(
  output  [7:0]                 doa,
  input   [7:0]                 dia,
  input   [14:0]                addra,
  input                         wea,
  input                         cea,
  input                         clka,
  output  [7:0]                 dob,
  input   [14:0]                addrb,
  input                         ceb,
  input                         clkb,
  input   [7:0]                 dib,
  input                         web
);

  ram_6ba517cddb42
  #(
      .DATA_WIDTH_A(8),
      .ADDR_WIDTH_A(15),
      .DATA_DEPTH_A(27648),
      .DATA_WIDTH_B(8),
      .ADDR_WIDTH_B(15),
      .DATA_DEPTH_B(27648),
      .REGMODE_A("NOREG"),
      .WRITEMODE_A("NORMAL"),
      .RESETMODE_A("ASYNC"),
      .INIT_FILE("NONE"),
      .REGMODE_B("NOREG"),
      .FILL_ALL("NONE"),
      .WRITEMODE_B("NORMAL"),
      .RESETMODE_B("ASYNC")
  )ram_6ba517cddb42_Inst
  (
      .doa(doa),
      .dia(dia),
      .addra(addra),
      .wea(wea),
      .cea(cea),
      .clka(clka),
      .dob(dob),
      .addrb(addrb),
      .ceb(ceb),
      .clkb(clkb),
      .dib(dib),
      .web(web)
  );
endmodule
