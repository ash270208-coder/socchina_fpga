/************************************************************\
**	Copyright (c) 2012-2025 Anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Build time: Sep 14 2026 20:55:32
**	TD version	:	6.2.168116
************************************************************/
`timescale 1 ns / 1 ps
module rom_feature_rects
(
  output  [31:0]                doa,
  input   [7:0]                 addra,
  input                         clka
);

  rom_0f833efb5013
  #(
      .DATA_WIDTH_A(32),
      .ADDR_WIDTH_A(8),
      .DATA_DEPTH_A(256),
      .INIT_FILE("../feature_rects.dath"),
      .FILL_ALL("NONE")
  )rom_0f833efb5013_Inst
  (
      .doa(doa),
      .addra(addra),
      .clka(clka)
  );
endmodule
