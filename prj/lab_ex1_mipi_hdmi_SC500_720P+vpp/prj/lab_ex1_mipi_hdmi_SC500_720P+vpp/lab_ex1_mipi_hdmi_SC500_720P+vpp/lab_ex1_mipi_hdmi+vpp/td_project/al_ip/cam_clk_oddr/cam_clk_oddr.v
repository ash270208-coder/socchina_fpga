/************************************************************\
**	Copyright (c) 2012-2025 Anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Build time: Sep 10 2026 23:27:37
**	TD version	:	6.2.168116
************************************************************/
module cam_clk_oddr
(
  input                         clk_in,
  input                         rst,
  input   [1:0]                 data_out_from_device,
  output  [0:0]                 data_out_to_pins
);

  High_Speed_IO_60d305d38ddd
  #(
      .IO_WIDTH(1),
      .DIV_CLOCK_SRC("INTERNAL"),
      .DATA_DIRECTION("OUTPUT"),
      .SERDES_MODE("DDRX1"),
      .CLOCK_FORWARD(0),
      .ODELAY(0),
      .IO_TYPE("HDIO")
  )High_Speed_IO_60d305d38ddd_Inst
  (
      .clk_in(clk_in),
      .rst(rst),
      .data_out_from_device(data_out_from_device),
      .data_out_to_pins(data_out_to_pins)
  );
endmodule
