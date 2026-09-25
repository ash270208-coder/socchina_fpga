/************************************************************\
**	Copyright (c) 2012-2025 Anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Build time: Sep 21 2026 22:34:44
**	TD version	:	6.2.168116
************************************************************/
`timescale 1 ns / 1 ps
module cnn_rom_exp
(
  output  [15:0]                doa,
  input   [9:0]                 addra,
  input                         clka
);

  rom_3f699db8ffa6
  #(
      .DATA_WIDTH_A(16),
      .ADDR_WIDTH_A(10),
      .DATA_DEPTH_A(1024),
      .INIT_FILE("../cnn_lut_exp.dath"),
      .FILL_ALL("NONE")
  )rom_3f699db8ffa6_Inst
  (
      .doa(doa),
      .addra(addra),
      .clka(clka)
  );
endmodule
