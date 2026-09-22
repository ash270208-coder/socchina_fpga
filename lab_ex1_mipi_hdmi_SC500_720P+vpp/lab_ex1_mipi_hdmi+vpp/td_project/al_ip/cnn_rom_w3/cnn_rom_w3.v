/************************************************************\
**	Copyright (c) 2012-2025 Anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Build time: Sep 21 2026 22:32:14
**	TD version	:	6.2.168116
************************************************************/
`timescale 1 ns / 1 ps
module cnn_rom_w3
(
  output  [63:0]                doa,
  input   [9:0]                 addra,
  input                         clka
);

  rom_0a2b16d92680
  #(
      .DATA_WIDTH_A(64),
      .ADDR_WIDTH_A(10),
      .DATA_DEPTH_A(576),
      .INIT_FILE("../cnn_w_conv3_packed.dath"),
      .FILL_ALL("NONE")
  )rom_0a2b16d92680_Inst
  (
      .doa(doa),
      .addra(addra),
      .clka(clka)
  );
endmodule
