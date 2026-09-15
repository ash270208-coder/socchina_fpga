/************************************************************\
**	Copyright (c) 2012-2025 Anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Build time: Sep 14 2026 20:55:47
**	TD version	:	6.2.168116
************************************************************/
`timescale 1 ns / 1 ps
module rom_stage_thresh
(
  output  [15:0]                doa,
  input   [4:0]                 addra,
  input                         clka
);

  rom_02e417c010d2
  #(
      .DATA_WIDTH_A(16),
      .ADDR_WIDTH_A(5),
      .DATA_DEPTH_A(32),
      .INIT_FILE("../stage_threshold.dath"),
      .FILL_ALL("NONE")
  )rom_02e417c010d2_Inst
  (
      .doa(doa),
      .addra(addra),
      .clka(clka)
  );
endmodule
