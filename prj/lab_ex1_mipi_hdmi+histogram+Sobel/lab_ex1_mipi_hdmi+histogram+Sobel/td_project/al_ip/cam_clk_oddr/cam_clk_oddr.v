/************************************************************\
**	Copyright (c) 2012-2025 Anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Build time: Aug 29 2026 12:48:21
**	TD version	:	6.2.168116
************************************************************/
module cam_clk_oddr
(
  input                         clk_in,
  input                         rst,
  input   [1:0]                 data_out_from_device,
  output  [0:0]                 data_out_to_pins
);

  High_Speed_IO_9485efe6e826
  #(
      .IO_WIDTH(1),
      .DIV_CLOCK_SRC("INTERNAL"),
      .DATA_DIRECTION("OUTPUT"),
      .SERDES_MODE("DDRX1"),
      .CLOCK_FORWARD(0),
      .ODELAY(0),
      .IO_TYPE("HDIO")
  )High_Speed_IO_9485efe6e826_Inst
  (
      .clk_in(clk_in),
      .rst(rst),
      .data_out_from_device(data_out_from_device),
      .data_out_to_pins(data_out_to_pins)
  );
endmodule
