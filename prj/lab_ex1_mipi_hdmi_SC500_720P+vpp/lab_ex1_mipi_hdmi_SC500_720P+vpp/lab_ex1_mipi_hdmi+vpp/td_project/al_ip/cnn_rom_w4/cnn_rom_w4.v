/************************************************************\
**	Copyright (c) 2012-2025 Anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Build time: Sep 21 2026 22:33:02
**	TD version	:	6.2.168116
************************************************************/
`timescale 1 ns / 1 ps
module cnn_rom_w4
(
  output  [63:0]                doa,
  input   [10:0]                addra,
  input                         clka
);

  rom_91c42686cce7
  #(
      .DATA_WIDTH_A(64),
      .ADDR_WIDTH_A(11),
      .DATA_DEPTH_A(1152),
      .INIT_FILE("../cnn_w_conv4_packed.dath"),
      .FILL_ALL("NONE")
  )rom_91c42686cce7_Inst
  (
      .doa(doa),
      .addra(addra),
      .clka(clka)
  );
endmodule
