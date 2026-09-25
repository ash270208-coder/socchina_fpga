/************************************************************\
**	Copyright (c) 2012-2025 Anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Build time: Sep 21 2026 23:19:54
**	TD version	:	6.2.168116
************************************************************/
`timescale 1ns/1ps
module cnn_buf_b
(
  output  [127:0]               doa,
  input   [127:0]               dia,
  input   [11:0]                addra,
  input                         wea,
  input                         cea,
  input                         clka,
  output  [127:0]               dob,
  input   [11:0]                addrb,
  input                         ceb,
  input                         clkb,
  input   [127:0]               dib,
  input                         web
);

  ram_6b6bdae5f172
  #(
      .DATA_WIDTH_A(128),
      .ADDR_WIDTH_A(12),
      .DATA_DEPTH_A(2304),
      .DATA_WIDTH_B(128),
      .ADDR_WIDTH_B(12),
      .DATA_DEPTH_B(2304),
      .REGMODE_A("NOREG"),
      .WRITEMODE_A("NORMAL"),
      .RESETMODE_A("ASYNC"),
      .INIT_FILE("NONE"),
      .REGMODE_B("NOREG"),
      .FILL_ALL("NONE"),
      .WRITEMODE_B("NORMAL"),
      .RESETMODE_B("ASYNC")
  )ram_6b6bdae5f172_Inst
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
