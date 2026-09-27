/************************************************************\
**	Copyright (c) 2012-2025 Anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Build time: Sep 26 2026 17:13:38
**	TD version	:	6.2.168116
************************************************************/
`timescale 1 ns / 1 ps
module bilateral_rom_range
(
  output  [7:0]                 doa,
  input   [7:0]                 addra,
  input                         clka
);

  rom_0eb03742bff9
  #(
      .DATA_WIDTH_A(8),
      .ADDR_WIDTH_A(8),
      .DATA_DEPTH_A(256),
      .INIT_FILE("../bilateral_range.dath"),
      .FILL_ALL("NONE")
  )rom_0eb03742bff9_Inst
  (
      .doa(doa),
      .addra(addra),
      .clka(clka)
  );
endmodule
