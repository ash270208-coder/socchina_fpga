/************************************************************\
**	Copyright (c) 2012-2025 Anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Build time: Sep 21 2026 22:31:10
**	TD version	:	6.2.168116
************************************************************/
`timescale 1 ns / 1 ps
module cnn_rom_w2
(
  output  [63:0]                doa,
  input   [7:0]                 addra,
  input                         clka
);

  rom_6e782a15cc7e
  #(
      .DATA_WIDTH_A(64),
      .ADDR_WIDTH_A(8),
      .DATA_DEPTH_A(144),
      .INIT_FILE("../cnn_w_conv2_packed.dath"),
      .FILL_ALL("NONE")
  )rom_6e782a15cc7e_Inst
  (
      .doa(doa),
      .addra(addra),
      .clka(clka)
  );
endmodule
