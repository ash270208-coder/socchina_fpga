/************************************************************\
**	Copyright (c) 2012-2025 Anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Build time: Sep 21 2026 22:30:16
**	TD version	:	6.2.168116
************************************************************/
`timescale 1 ns / 1 ps
module cnn_rom_w1
(
  output  [63:0]                doa,
  input   [4:0]                 addra,
  input                         clka
);

  rom_27f1d317274d
  #(
      .DATA_WIDTH_A(64),
      .ADDR_WIDTH_A(5),
      .DATA_DEPTH_A(27),
      .INIT_FILE("../cnn_w_conv1_packed.dath"),
      .FILL_ALL("NONE")
  )rom_27f1d317274d_Inst
  (
      .doa(doa),
      .addra(addra),
      .clka(clka)
  );
endmodule
