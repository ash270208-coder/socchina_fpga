/************************************************************\
**	Copyright (c) 2012-2025 Anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Build time: Sep 21 2026 22:33:47
**	TD version	:	6.2.168116
************************************************************/
`timescale 1 ns / 1 ps
module cnn_rom_wh
(
  output  [63:0]                doa,
  input   [5:0]                 addra,
  input                         clka
);

  rom_3e141b8a518d
  #(
      .DATA_WIDTH_A(64),
      .ADDR_WIDTH_A(6),
      .DATA_DEPTH_A(64),
      .INIT_FILE("../cnn_w_head_packed.dath"),
      .FILL_ALL("NONE")
  )rom_3e141b8a518d_Inst
  (
      .doa(doa),
      .addra(addra),
      .clka(clka)
  );
endmodule
