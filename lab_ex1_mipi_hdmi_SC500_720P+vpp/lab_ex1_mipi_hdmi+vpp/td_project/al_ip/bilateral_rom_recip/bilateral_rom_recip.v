/************************************************************\
**	Copyright (c) 2012-2025 Anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Build time: Sep 26 2026 17:24:44
**	TD version	:	6.2.168116
************************************************************/
`timescale 1 ns / 1 ps
module bilateral_rom_recip
(
  output  [15:0]                doa,
  input   [10:0]                addra,
  input                         clka
);

  rom_eb5e8a394116
  #(
      .DATA_WIDTH_A(16),
      .ADDR_WIDTH_A(11),
      .DATA_DEPTH_A(2048),
      .INIT_FILE("../bilateral_recip.dath"),
      .FILL_ALL("NONE")
  )rom_eb5e8a394116_Inst
  (
      .doa(doa),
      .addra(addra),
      .clka(clka)
  );
endmodule
