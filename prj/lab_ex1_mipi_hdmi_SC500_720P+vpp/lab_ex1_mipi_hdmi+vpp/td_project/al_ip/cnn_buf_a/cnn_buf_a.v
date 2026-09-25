/************************************************************\
**	Copyright (c) 2012-2025 Anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Build time: Sep 21 2026 23:18:41
**	TD version	:	6.2.168116
************************************************************/
`timescale 1ns/1ps
module cnn_buf_a
(
  output  [63:0]                doa,
  input   [63:0]                dia,
  input   [13:0]                addra,
  input                         wea,
  input                         cea,
  input                         clka,
  output  [63:0]                dob,
  input   [13:0]                addrb,
  input                         ceb,
  input                         clkb,
  input   [63:0]                dib,
  input                         web
);

  ram_7c369343886e
  #(
      .DATA_WIDTH_A(64),
      .ADDR_WIDTH_A(14),
      .DATA_DEPTH_A(9216),
      .DATA_WIDTH_B(64),
      .ADDR_WIDTH_B(14),
      .DATA_DEPTH_B(9216),
      .REGMODE_A("NOREG"),
      .WRITEMODE_A("NORMAL"),
      .RESETMODE_A("ASYNC"),
      .INIT_FILE("NONE"),
      .REGMODE_B("NOREG"),
      .FILL_ALL("NONE"),
      .WRITEMODE_B("NORMAL"),
      .RESETMODE_B("ASYNC")
  )ram_7c369343886e_Inst
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
