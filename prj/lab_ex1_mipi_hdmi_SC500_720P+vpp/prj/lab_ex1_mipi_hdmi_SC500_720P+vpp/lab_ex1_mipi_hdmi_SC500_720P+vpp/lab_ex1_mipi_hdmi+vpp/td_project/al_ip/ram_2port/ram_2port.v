/************************************************************\
**	Copyright (c) 2012-2025 Anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Build time: Sep 10 2026 20:55:52
**	TD version	:	6.2.168116
************************************************************/
`timescale 1ns/1ps
module ram_2port
(
  output  [19:0]                doa,
  input   [19:0]                dia,
  input   [7:0]                 addra,
  input                         wea,
  input                         cea,
  input                         clka,
  output  [19:0]                dob,
  input   [7:0]                 addrb,
  input                         ceb,
  input                         clkb,
  input   [19:0]                dib,
  input                         web
);

  ram_791ed05040df
  #(
      .DATA_WIDTH_A(20),
      .ADDR_WIDTH_A(8),
      .DATA_DEPTH_A(256),
      .DATA_WIDTH_B(20),
      .ADDR_WIDTH_B(8),
      .DATA_DEPTH_B(256),
      .REGMODE_A("NOREG"),
      .WRITEMODE_A("READBEFOREWRITE"),
      .RESETMODE_A("ASYNC"),
      .INIT_FILE("NONE"),
      .REGMODE_B("NOREG"),
      .FILL_ALL("00000000000000000000"),
      .WRITEMODE_B("READBEFOREWRITE"),
      .RESETMODE_B("ASYNC")
  )ram_791ed05040df_Inst
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
