/************************************************************\
**	Copyright (c) 2012-2025 Anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Build time: Sep 10 2026 21:23:17
**	TD version	:	6.2.168116
************************************************************/
`timescale 1 ns / 1 ps
module rom_weak_lut
(
  output  [295:0]               doa,
  input   [7:0]                 addra,
  input                         clka
);

  rom_7b7c1dc52abc
  #(
      .DATA_WIDTH_A(296),
      .ADDR_WIDTH_A(8),
      .DATA_DEPTH_A(256),
      .INIT_FILE("../weak_lut.dath"),
      .FILL_ALL("NONE")
  )rom_7b7c1dc52abc_Inst
  (
      .doa(doa),
      .addra(addra),
      .clka(clka)
  );
endmodule
