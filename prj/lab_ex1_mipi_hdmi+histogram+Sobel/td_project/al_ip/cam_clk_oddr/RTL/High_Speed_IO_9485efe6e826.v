
module High_Speed_IO_9485efe6e826 #(
    parameter IO_TYPE = "HDIO",
    //"HRIO" , "HDIO"
    parameter IO_WIDTH = 1,
    // 1 - 16;
    parameter DIV_CLOCK_SRC = "EXTERNAL", 
    //"INTERNAL" , "EXTERNAL"
    parameter DATA_DIRECTION = "INPUT",
    //"INPUT" , "OUTPUT" , "BIDIRECTIONAL" can use
    parameter SERDES_MODE = "DDRX1",
    //"BYPASS" , "SDR" , "DDRX1" , "DDRX1_PIPE" , "DDRX2" , "DDRX3P5" , "DDRX4" , "DDRX5";"DDRX1_PIPE" mode can only be used when $DATA_DIRECTION is "INPUT"
    parameter IDDR_MODE = "OPPOSITE_EDGE",
    //"SAME_EDGE_PIPE","SAME_EDGE","OPPOSITE_EDGE"
    parameter INPUT_DATA_PIPE = 1,
    //When the parameter DATA_DIRECTION is "BIDIRECTIONAL", this option can be selected. When it is selected, the alignment of input data shall be of "PIPE" type.
    parameter CLOCK_FORWARD = 1,
    // 0 = off;1 = on; When $DATA_DIRECTION is "OUTPUT" or "BIDIRECTIONAL" can use.
    parameter DIFF_N_EN = 1,
    // 0 = off;1 = on;Enable the 'n' of diff clk,When $DATA_DIRECTION is "INPUT" or "BIDIRECTIONAL" can use.
    parameter ODELAY = 1,
    // 0 = off;1 = on;
    parameter IDELAY = 1,
    // 0 = off;1 = on; 
    parameter IDLY_CASCADE_NUM = 1,
    parameter ODLY_CASCADE_NUM = 2    

)(
        clk_in,
        rst,
        clk_div_in,
        clk_div_out,
        clk_out,
        clk_to_pins,
        tristate_ctr,   

        data_in_from_pins_p,
        data_in_from_pins_n,
        data_in_to_device_p,
        data_in_to_device_n,
        data_in_from_pins,
        data_in_to_device,
        data_out_from_device,
        data_out_to_pins,
  
        data_from_and_to_pins_p,
        data_from_and_to_pins_n,
        data_from_and_to_pins,

        in_dly,
        out_dly

);

localparam DEVICE_WIDTH  = (SERDES_MODE == "DDRX1") ? IO_WIDTH*2 : 
                           (SERDES_MODE == "DDRX1_PIPE") ? IO_WIDTH*2 :
                           (SERDES_MODE == "DDRX2") ? IO_WIDTH*4 :
                           (SERDES_MODE == "DDRX3P5") ? IO_WIDTH*7 :
                           (SERDES_MODE == "DDRX4") ? IO_WIDTH*8 :
                           (SERDES_MODE == "DDRX5") ? IO_WIDTH*10 :
                           IO_WIDTH ;    
           
localparam DLY_WIDTH = (IO_TYPE == "HRIO") ? 8 : 5;

localparam INDLY_WIDTH = IO_WIDTH*DLY_WIDTH-1 ;

//-----------------port define-------------
  input wire                        clk_in;
  input wire                        rst;
  input wire                        clk_div_in;
  output wire                       clk_div_out;
  output wire                       clk_out;
  input wire                        tristate_ctr;

  inout         [IO_WIDTH-1:0]      data_from_and_to_pins_p;
  inout         [IO_WIDTH-1:0]      data_from_and_to_pins_n;
  inout         [IO_WIDTH-1:0]      data_from_and_to_pins;

  output        [DEVICE_WIDTH-1:0]  data_in_to_device_p;
  output        [DEVICE_WIDTH-1:0]  data_in_to_device_n;
  input wire    [IO_WIDTH-1:0]      data_in_from_pins_p;
  input wire    [IO_WIDTH-1:0]      data_in_from_pins_n;
  output        [DEVICE_WIDTH-1:0]  data_in_to_device;
  input wire    [IO_WIDTH-1:0]      data_in_from_pins;

  input wire    [DEVICE_WIDTH-1:0]  data_out_from_device;
  output        [IO_WIDTH-1:0]      data_out_to_pins;
  output                            clk_to_pins;                                         

  input wire    [INDLY_WIDTH:0]    in_dly;
  input wire    [INDLY_WIDTH:0]    out_dly;

PH1P35_High_Speed_IO_9485efe6e826 #(
    .IO_TYPE          (IO_TYPE),
    .IO_WIDTH         (IO_WIDTH) ,
    .DIV_CLOCK_SRC    (DIV_CLOCK_SRC) , 
    .DATA_DIRECTION   (DATA_DIRECTION),
    .SERDES_MODE      (SERDES_MODE),
    .INPUT_DATA_PIPE  (INPUT_DATA_PIPE),
    .IDDR_MODE        (IDDR_MODE),
    .CLOCK_FORWARD    (CLOCK_FORWARD),
    .DIFF_N_EN        (DIFF_N_EN),
    .ODELAY           (ODELAY),
    .IDELAY           (IDELAY),
    .IDLY_CASCADE_NUM (IDLY_CASCADE_NUM),
    .ODLY_CASCADE_NUM (ODLY_CASCADE_NUM)
  )PH1P35_High_Speed_IO_inst(
        .clk_in               (clk_in),
        .rst                  (rst),
        .clk_div_in           (clk_div_in),
        .clk_div_out          (clk_div_out),
        .clk_out              (clk_out),
        .clk_to_pins          (clk_to_pins),
        .tristate_ctr         (tristate_ctr),   

        .data_in_from_pins_p  (data_in_from_pins_p),
        .data_in_from_pins_n  (data_in_from_pins_n),
        .data_in_to_device_p  (data_in_to_device_p),
        .data_in_to_device_n  (data_in_to_device_n),
        .data_in_from_pins    (data_in_from_pins),
        .data_in_to_device    (data_in_to_device),
        .data_out_from_device (data_out_from_device),
        .data_out_to_pins     (data_out_to_pins),
  
        .data_from_and_to_pins_p(data_from_and_to_pins_p),
        .data_from_and_to_pins_n(data_from_and_to_pins_n),
        .data_from_and_to_pins(data_from_and_to_pins),

        .in_dly               (in_dly),
        .out_dly              (out_dly)
);

endmodule

module PH1P35_High_Speed_IO_9485efe6e826 #(
    parameter IO_TYPE = "HDIO",
    //"HRIO" , "HDIO"
    parameter IO_WIDTH = 1,
    // 1 - 16;
    parameter DIV_CLOCK_SRC = "EXTERNAL", 
    //"INTERNAL" , "EXTERNAL"
    parameter DATA_DIRECTION = "INPUT",
    //"INPUT" , "OUTPUT" , "BIDIRECTIONAL" can use
    parameter SERDES_MODE = "DDRX1",
    //"BYPASS" , "SDR" , "DDRX1" , "DDRX1_PIPE" , "DDRX2" , "DDRX3P5" , "DDRX4" , "DDRX5";"DDRX1_PIPE" mode can only be used when $DATA_DIRECTION is "INPUT"
    parameter INPUT_DATA_PIPE = 1,
    //When the parameter DATA_DIRECTION is "BIDIRECTIONAL", this option can be selected. When it is selected, the alignment of input data shall be of "PIPE" type.
    parameter IDDR_MODE = "OPPOSITE_EDGE",
    //"SAME_EDGE_PIPE","SAME_EDGE","OPPOSITE_EDGE"
    parameter CLOCK_FORWARD = 1,
    // 0 = off;1 = on; When $DATA_DIRECTION is "OUTPUT" or "BIDIRECTIONAL" can use.
    parameter DIFF_N_EN = 0,
    // 0 = off;1 = on;Enable deserialization negative terminal of diff clk,When $DATA_DIRECTION is "INPUT" or "BIDIRECTIONAL" can use.
    parameter ODELAY = 1,
    // 0 = off;1 = on;
    parameter IDELAY = 1,
    // 0 = off;1 = on; 
    parameter IDLY_CASCADE_NUM = 1,
    parameter ODLY_CASCADE_NUM = 2
  )(
        clk_in,
        rst,
        clk_div_in,
        clk_div_out,
        clk_out,
        clk_to_pins,
        tristate_ctr,   

        data_in_from_pins_p,
        data_in_from_pins_n,
        data_in_to_device_p,
        data_in_to_device_n,
        data_in_from_pins,
        data_in_to_device,
        data_out_from_device,
        data_out_to_pins,
  
        data_from_and_to_pins_p,
        data_from_and_to_pins_n,
        data_from_and_to_pins,

        in_dly,
        out_dly
//        clk_to_pins_dly
);

localparam LCLK_MODE = (SERDES_MODE == "DDRX1") ? "BYPASS" : 
                       (SERDES_MODE == "DDRX1_PIPE") ? "BYPASS" :
                       (SERDES_MODE == "DDRX2") ? "DIV2TO8" : 
                       (SERDES_MODE == "DDRX3P5") ? "DIV2TO8" :
                       (SERDES_MODE == "DDRX4") ? "DIV2TO8" :
                       (SERDES_MODE == "DDRX5") ? "DIV2TO8" :
                       "BYPASS";
localparam LCLK_DIV  = (SERDES_MODE == "DDRX1") ? "1" : 
                       (SERDES_MODE == "DDRX1_PIPE") ? "1" :
                       (SERDES_MODE == "DDRX2") ? "2" : 
                       (SERDES_MODE == "DDRX3P5") ? "3P5" :
                       (SERDES_MODE == "DDRX4") ? "4" :
                       (SERDES_MODE == "DDRX5") ? "5" :
                       "1" ;
localparam DEVICE_WIDTH  = (SERDES_MODE == "DDRX1") ? IO_WIDTH*2 : 
                           (SERDES_MODE == "DDRX1_PIPE") ? IO_WIDTH*2 :
                           (SERDES_MODE == "DDRX2") ? IO_WIDTH*4 :
                           (SERDES_MODE == "DDRX3P5") ? IO_WIDTH*7 :
                           (SERDES_MODE == "DDRX4") ? IO_WIDTH*8 :
                           (SERDES_MODE == "DDRX5") ? IO_WIDTH*10 :
                           IO_WIDTH ;          
localparam DATA_RATE = (SERDES_MODE == "DDRX1") ? 2 : 
                       (SERDES_MODE == "DDRX1_PIPE") ? 2 :
                       (SERDES_MODE == "DDRX2") ? 4 : 
                       (SERDES_MODE == "DDRX3P5") ? 7 :
                       (SERDES_MODE == "DDRX4") ? 8 :
                       (SERDES_MODE == "DDRX5") ? 10 :
                       1 ;             
localparam DLY_WIDTH = (IO_TYPE == "HRIO") ? 8 : 5;
localparam IDLY_CASCADE_EN = ((IDLY_CASCADE_NUM > 1) & (IO_WIDTH == 1)) ? 1 : 0;
localparam ODLY_CASCADE_EN = ((ODLY_CASCADE_NUM > 1) & (IO_WIDTH == 1)) ? 1 : 0;

//-----------------port define-------------
  input wire                        clk_in;
  input wire                        rst;
  input wire                        clk_div_in;
  output wire                       clk_div_out;
  output wire                       clk_out;
  input wire                        tristate_ctr;

  inout         [IO_WIDTH-1:0]      data_from_and_to_pins_p;
  inout         [IO_WIDTH-1:0]      data_from_and_to_pins_n;
  inout         [IO_WIDTH-1:0]      data_from_and_to_pins;

  output        [DEVICE_WIDTH-1:0]  data_in_to_device_p;
  output        [DEVICE_WIDTH-1:0]  data_in_to_device_n;
  input wire    [IO_WIDTH-1:0]      data_in_from_pins_p;
  input wire    [IO_WIDTH-1:0]      data_in_from_pins_n;
  output        [DEVICE_WIDTH-1:0]  data_in_to_device;
  input wire    [IO_WIDTH-1:0]      data_in_from_pins;

  input wire    [DEVICE_WIDTH-1:0]  data_out_from_device;
  output        [IO_WIDTH-1:0]      data_out_to_pins;
  output                            clk_to_pins;                                         

  input wire    [IO_WIDTH*DLY_WIDTH-1:0]    in_dly;
  input wire    [IO_WIDTH*DLY_WIDTH-1:0]    out_dly;
//  input wire    [DLY_WIDTH-1:0]             clk_to_pins_dly;

  //------------variable define-----------------
  //cal output from IOL(data input/output path)
        reg   [DEVICE_WIDTH-1:0]  data_in_to_device_p_reg;
        reg   [DEVICE_WIDTH-1:0]  data_in_to_device_n_reg;
        reg   [DEVICE_WIDTH-1:0]  data_in_to_device_reg;
        reg   [IO_WIDTH-1:0]      data_out_to_pins_predelay_reg;
        wire  [DEVICE_WIDTH-1:0]  data_in_to_device_p;
        wire  [DEVICE_WIDTH-1:0]  data_in_to_device_n;
        wire  [DEVICE_WIDTH-1:0]  data_in_to_device;
        wire  [IO_WIDTH-1:0]      data_out_to_pins_predelay;

  //cal input to IOL(data input path)
        wire [IO_WIDTH-1:0]       data_in_from_pins_delay_p;
        wire [IO_WIDTH-1:0]       data_in_from_pins_delay_n;
        wire [IO_WIDTH-1:0]       data_in_from_pins_delay;

  //for BIDIRECTIONAL to connect IOB
        wire [IO_WIDTH-1:0]       data_out_to_pins_delay;
        wire [IO_WIDTH-1:0]       data_in_from_pins_predelay_p;
        wire [IO_WIDTH-1:0]       data_in_from_pins_predelay_n;
        wire [IO_WIDTH-1:0]       data_in_from_pins_predelay;

  //dly cascade
        wire [IDLY_CASCADE_NUM-2:0]  idly_cas_up;
        wire [IDLY_CASCADE_NUM-2:0]  idly_cas_down;
        wire [IDLY_CASCADE_NUM-2:0]  idly_cas_up_p;
        wire [IDLY_CASCADE_NUM-2:0]  idly_cas_down_p;
        wire [IDLY_CASCADE_NUM-2:0]  idly_cas_up_n;
        wire [IDLY_CASCADE_NUM-2:0]  idly_cas_down_n;
        wire [ODLY_CASCADE_NUM-2:0]  odly_cas_up;
        wire [ODLY_CASCADE_NUM-2:0]  odly_cas_down;

  //clock      
        wire            sclk;
        wire            pclk;
        wire            ce;
        wire            lclk_out;
        wire            clk_to_pins_predelay;
        assign ce = 1'b1;

//-------------gen sclk&pclk------------------
// HDIO
  generate if (IO_TYPE == "HDIO") begin
    assign clk_div_out = 1'b0;
    if (DIV_CLOCK_SRC == "EXTERNAL")
      begin:gen_clk
        PH1P_PHY_LCLK #(
         .CEMD("SYNC"), 
         .CLKSEL("ORG"),
         .DIV("1"), 
         .LCLK("BYPASS") 
         )lclk_for_pclk(
         .ce        (ce),
         .clkin     (clk_in),
         .rst       (rst),
         .clkout    (lclk_out),
         .clkdivout ()
        );
        assign clk_out = lclk_out;
        assign pclk = lclk_out;
      end
    else if (DIV_CLOCK_SRC == "INTERNAL")
      begin:gen_clk
        assign clk_out = 1'b0;
        assign pclk = clk_in;
      end
  end
  endgenerate

// HRIO  
  generate if (IO_TYPE == "HRIO") begin
    if (DIV_CLOCK_SRC == "EXTERNAL")
      begin:gen_pclk_and_sclk
        PH1P_PHY_IOCLK ioclk_for_sclk
        (
         .clkin  (clk_in),
         .clkout (sclk)
        );
        PH1P_PHY_LCLK #(
         .CEMD("SYNC"), 
         .CLKSEL("ORG"),
         .DIV(LCLK_DIV), 
         .LCLK(LCLK_MODE) 
         )lclk_for_pclk(
         .ce        (ce),
         .clkin     (clk_in),
         .rst       (rst),
         .clkout    (lclk_out),
         .clkdivout ()
        );
        assign clk_out = ((SERDES_MODE == "SDR") | (SERDES_MODE == "DDRX1") | (SERDES_MODE == "DDRX1_PIPE")) ? lclk_out : 1'b0;
        assign clk_div_out = ((SERDES_MODE == "SDR") | (SERDES_MODE == "DDRX1") | (SERDES_MODE == "DDRX1_PIPE")) ? 1'b0 : lclk_out;
        assign pclk = lclk_out;
      end
    else if (DIV_CLOCK_SRC == "INTERNAL")
      begin:gen_pclk_and_sclk
        assign clk_out = 1'b0;
        assign clk_div_out = 1'b0;
        assign pclk = ((SERDES_MODE == "SDR") | (SERDES_MODE == "DDRX1") | (SERDES_MODE == "DDRX1_PIPE")) ? clk_in : clk_div_in;
        assign sclk = clk_in;
      end
  end
  endgenerate

//-------------forward clock------------------
// gen fwd_clk with delay(HRIO)
  generate if((IO_TYPE == "HRIO") & (CLOCK_FORWARD == 1) & (DATA_DIRECTION != "INPUT")) begin
    case (1)
    (SERDES_MODE == "SDR") : begin:fwd_clk_sdr
      PH1P_LOGIC_HR_OSERDES #(
          .ODDRMODE("DDRX1")
        )clk_forward(
          .sclk(sclk),
          .pclk(pclk),
          .rst(rst),
          .idata(2'b01),
          .odata(clk_to_pins)
        );
    end
    (SERDES_MODE == "DDRX1") : begin:fwd_clk_ddrx1
      PH1P_LOGIC_HR_OSERDES #(
          .ODDRMODE(SERDES_MODE)
        )clk_forward(
          .sclk(sclk),
          .pclk(pclk),
          .rst(rst),
          .idata(2'b01),
          .odata(clk_to_pins)
        );
    end
    (SERDES_MODE == "DDRX2") : begin:fwd_clk_ddrx2
      PH1P_LOGIC_HR_OSERDES #(
          .ODDRMODE(SERDES_MODE)
        )clk_forward(
          .sclk(sclk),
          .pclk(pclk),
          .rst(rst),
          .idata(4'b0101),
          .odata(clk_to_pins)
        );
    end
    (SERDES_MODE == "DDRX3P5") : begin:fwd_clk_ddrx3p5
      PH1P_LOGIC_HR_OSERDES #(
          .ODDRMODE("DDRX2")
        )clk_forward(
          .sclk(sclk),
          .pclk(pclk),
          .rst(rst),
          .idata(4'b0101),
          .odata(clk_to_pins)
        );
    end
    (SERDES_MODE == "DDRX4") : begin:fwd_clk_ddrx4
      PH1P_LOGIC_HR_OSERDES #(
          .ODDRMODE(SERDES_MODE)
        )clk_forward(
          .sclk(sclk),
          .pclk(pclk),
          .rst(rst),
          .idata(8'b01010101),
          .odata(clk_to_pins)
        );
    end
    (SERDES_MODE == "DDRX5") : begin:fwd_clk_ddrx5
      PH1P_LOGIC_HR_OSERDES #(
          .ODDRMODE(SERDES_MODE)
        )clk_forward(
          .sclk(sclk),
          .pclk(pclk),
          .rst(rst),
          .idata(10'b0101010101),
          .odata(clk_to_pins)
        );
    end
    default : assign clk_to_pins = 1'b0;
    endcase
  end
  endgenerate
// gen fwd_clk with delay(HDIO)
  generate if((IO_TYPE == "HDIO") & (CLOCK_FORWARD == 1) & (DATA_DIRECTION != "INPUT")) begin
    case (1)
    ((SERDES_MODE == "DDRX1") | (SERDES_MODE == "SDR")) : begin:fwd_clk_hdio
        PH1P_LOGIC_HD_ODDR #(
          .ASYNCRST ("ENABLE")
        )clk_forward(
          .clk(pclk),
          .rst(rst),
          .d1(1'b0),
          .d0(1'b1),
          .q(clk_to_pins)
        );
    end
    default : assign clk_to_pins = 1'b0;
    endcase
  end
  endgenerate

//---------------data path---------------------------
  genvar i,j;
//////////////////////////////////////////////////////////
//--------------------------INPUT-----------------------//
////////////////////////////////////////////////////////// 

// HRIO
  genvar input_width;
  generate if((IO_TYPE == "HRIO") & (DATA_DIRECTION == "INPUT")) begin
    case(1)
    ((DIFF_N_EN == 1) & (IDELAY == 1) & (SERDES_MODE == "BYPASS")) : begin:data_diff_input_bypass_dly
      for (input_width = 0 ;input_width < IO_WIDTH ; input_width = input_width + 1) begin : input_control
          PH1P_LOGIC_IBUF_DIFF #(
              .DIFF_TERM ("TRUE")
          )diff_iob(
              .i_p           (data_in_from_pins_p[input_width]),
              .i_n           (data_in_from_pins_n[input_width]),
              .interm_disable(1'b1),
              .o             (),
              .o_p           (data_in_from_pins_predelay_p[input_width]),
              .o_n           (data_in_from_pins_predelay_n[input_width])
          );
          
          assign data_in_to_device_p[input_width] = data_in_from_pins_delay_p[input_width];
          assign data_in_to_device_n[input_width] = data_in_from_pins_delay_n[input_width];
      end
      assign data_in_to_device = 'b0;
      assign data_out_to_pins = 'b0;
    end
    ((DIFF_N_EN == 1) & (IDELAY == 0) & (SERDES_MODE == "BYPASS")) : begin:data_hrio_diff_input_bypass
      for (input_width = 0 ;input_width < IO_WIDTH ; input_width = input_width + 1) begin : input_control
          PH1P_LOGIC_IBUF_DIFF #(
              .DIFF_TERM ("TRUE")
          )diff_iob(
              .i_p           (data_in_from_pins_p[input_width]),
              .i_n           (data_in_from_pins_n[input_width]),
              .interm_disable(1'b1),
              .o             (),
              .o_p           (data_in_to_device_p[input_width]),
              .o_n           (data_in_to_device_n[input_width])
          );
      end
      assign data_in_to_device = 'b0;
      assign data_out_to_pins = 'b0; 
    end
    ((DIFF_N_EN == 0) & (IDELAY == 1) & (SERDES_MODE == "BYPASS")) : begin:data_hrio_sgl_input_bypass_dly
      for (input_width = 0 ;input_width < IO_WIDTH ; input_width = input_width + 1) begin : input_control
          assign data_in_from_pins_predelay[input_width] = data_in_from_pins[input_width];
          
          assign data_in_to_device[input_width] = data_in_from_pins_delay[input_width];
      end
      assign data_in_to_device_p = 'b0;
      assign data_in_to_device_n = 'b0;
      assign data_out_to_pins = 'b0;
    end
    ((DIFF_N_EN == 0) & (IDELAY == 0) & (SERDES_MODE == "BYPASS")) : begin:data_hrio_sgl_input_bypass
      for (input_width = 0 ;input_width < IO_WIDTH ; input_width = input_width + 1) begin : input_control
          assign data_in_to_device[input_width] = data_in_from_pins[input_width];
      end
      assign data_in_to_device_p = 'b0;
      assign data_in_to_device_n = 'b0;
      assign data_out_to_pins = 'b0;
    end
    ((DIFF_N_EN == 1) & (IDELAY == 1) & (SERDES_MODE == "SDR")) : begin:data_hrio_diff_input_sdr_dly
      for (input_width = 0 ;input_width < IO_WIDTH ; input_width = input_width + 1) begin : input_control
          PH1P_LOGIC_IBUF_DIFF #(
              .DIFF_TERM ("TRUE")
          )diff_iob(
              .i_p           (data_in_from_pins_p[input_width]),
              .i_n           (data_in_from_pins_n[input_width]),
              .interm_disable(1'b1),
              .o             (),
              .o_p           (data_in_from_pins_predelay_p[input_width]),
              .o_n           (data_in_from_pins_predelay_n[input_width])
          );
          
          always@(posedge pclk)
          begin
            if(rst) begin
                data_in_to_device_n_reg[input_width] <= 0;
                data_in_to_device_p_reg[input_width] <= 0;
            end
            else begin
                data_in_to_device_n_reg[input_width] <= data_in_from_pins_delay_n[input_width];
                data_in_to_device_p_reg[input_width] <= data_in_from_pins_delay_p[input_width];
            end
          end 

          assign data_in_to_device_n[input_width] = data_in_to_device_n_reg[input_width];
          assign data_in_to_device_p[input_width] = data_in_to_device_p_reg[input_width];
      end
      assign data_in_to_device = 'b0;
      assign data_out_to_pins = 'b0;
    end
    ((DIFF_N_EN == 1) & (IDELAY == 0) & (SERDES_MODE == "SDR")) : begin:data_hrio_diff_input_sdr
      for (input_width = 0 ;input_width < IO_WIDTH ; input_width = input_width + 1) begin : input_control
        PH1P_LOGIC_IBUF_DIFF #(
            .DIFF_TERM ("TRUE")
        )diff_iob(
            .i_p           (data_in_from_pins_p[input_width]),
            .i_n           (data_in_from_pins_n[input_width]),
            .interm_disable(1'b1),
            .o             (),
            .o_p           (data_in_from_pins_delay_p[input_width]),
            .o_n           (data_in_from_pins_delay_n[input_width])
        );
        always@(posedge pclk)  begin:sdr_for_input_data
          if(rst) begin
              data_in_to_device_n_reg[input_width] <= 0;
              data_in_to_device_p_reg[input_width] <= 0;
          end
          else begin
              data_in_to_device_n_reg[input_width] <= data_in_from_pins_delay_n[input_width];
              data_in_to_device_p_reg[input_width] <= data_in_from_pins_delay_p[input_width];
          end
        end 
        assign data_in_to_device_n[input_width] = data_in_to_device_n_reg[input_width];
        assign data_in_to_device_p[input_width] = data_in_to_device_p_reg[input_width];
      end
      assign data_in_to_device = 'b0;
      assign data_out_to_pins = 'b0;
    end
    ((DIFF_N_EN == 0) & (IDELAY == 1) & (SERDES_MODE == "SDR")) : begin:data_hrio_sgl_input_sdr_dly
      for (input_width = 0 ;input_width < IO_WIDTH ; input_width = input_width + 1) begin : input_control
        assign data_in_from_pins_predelay[input_width] = data_in_from_pins[input_width];
        
        always@(posedge pclk)  begin:sdr_for_input_data
          if(rst)
              data_in_to_device_reg[input_width] <= 0;
          else
              data_in_to_device_reg[input_width] <= data_in_from_pins_delay[input_width];
        end
        assign data_in_to_device[input_width] = data_in_to_device_reg[input_width];
      end
      assign data_in_to_device_n = 'b0;
      assign data_in_to_device_p = 'b0;
      assign data_out_to_pins = 'b0;
    end
    ((DIFF_N_EN == 0) & (IDELAY == 0) & (SERDES_MODE == "SDR")) : begin:data_hrio_sgl_input_sdr
      for (input_width = 0 ;input_width < IO_WIDTH ; input_width = input_width + 1) begin : input_control
        always@(posedge pclk)  begin
          if(rst)
              data_in_to_device_reg[input_width] <= 0;
          else
              data_in_to_device_reg[input_width] <= data_in_from_pins[input_width];
        end
        assign data_in_to_device[input_width] = data_in_to_device_reg[input_width];
      end
      assign data_in_to_device_n = 'b0;
      assign data_in_to_device_p = 'b0;
      assign data_out_to_pins = 'b0; 
    end
    ((DIFF_N_EN == 1) & (IDELAY == 1) & (SERDES_MODE != "SDR") & (SERDES_MODE != "BYPASS")) : begin:data_hrio_diff_input_ddr_dly
      for (input_width = 0 ;input_width < IO_WIDTH ; input_width = input_width + 1) begin : input_control
        PH1P_LOGIC_IBUF_DIFF #(
            .DIFF_TERM ("TRUE")
        )diff_iob(
            .i_p           (data_in_from_pins_p[input_width]),
            .i_n           (data_in_from_pins_n[input_width]),
            .interm_disable(1'b1),
            .o             (),
            .o_p           (data_in_from_pins_predelay_p[input_width]),
            .o_n           (data_in_from_pins_predelay_n[input_width])
        );
            
        PH1P_LOGIC_HR_ISERDES #(
            .IDDRMODE   (SERDES_MODE)
        ) ddr_for_input_data_p (
            .sclk       (sclk),
            .pclk       (pclk),
            .rst        (rst),
            .idata      (data_in_from_pins_delay_p[input_width]),
            .odata      (data_in_to_device_p[DATA_RATE * input_width+:DATA_RATE])
        );
        PH1P_LOGIC_HR_ISERDES #(
            .IDDRMODE   (SERDES_MODE)
        ) ddr_for_input_data_n (
            .sclk       (sclk),
            .pclk       (pclk),
            .rst        (rst),
            .idata      (data_in_from_pins_delay_n[input_width]),
            .odata      (data_in_to_device_n[DATA_RATE * input_width+:DATA_RATE])
        );
      end
      assign data_in_to_device = 'b0;
      assign data_out_to_pins = 'b0;
    end
    ((DIFF_N_EN == 1) & (IDELAY == 0) & (SERDES_MODE != "SDR") & (SERDES_MODE != "BYPASS")) : begin:data_hrio_diff_input_ddr
      for (input_width = 0 ;input_width < IO_WIDTH ; input_width = input_width + 1) begin : input_control
        PH1P_LOGIC_IBUF_DIFF #(
            .DIFF_TERM ("TRUE")
        )diff_iob(
            .i_p           (data_in_from_pins_p[input_width]),
            .i_n           (data_in_from_pins_n[input_width]),
            .interm_disable(1'b1),
            .o             (),
            .o_p           (data_in_from_pins_delay_p[input_width]),
            .o_n           (data_in_from_pins_delay_n[input_width])
        );      
        PH1P_LOGIC_HR_ISERDES #(
            .IDDRMODE   (SERDES_MODE)
        ) ddr_for_input_data_p (
            .sclk       (sclk),
            .pclk       (pclk),
            .rst        (rst),
            .idata      (data_in_from_pins_delay_p[input_width]),
            .odata      (data_in_to_device_p[DATA_RATE * input_width+:DATA_RATE])
        );
        PH1P_LOGIC_HR_ISERDES #(
            .IDDRMODE   (SERDES_MODE)
        ) ddr_for_input_data_n (
            .sclk       (sclk),
            .pclk       (pclk),
            .rst        (rst),
            .idata      (data_in_from_pins_delay_n[input_width]),
            .odata      (data_in_to_device_n[DATA_RATE * input_width+:DATA_RATE])
        );
      end
      assign data_in_to_device = 'b0;
      assign data_out_to_pins = 'b0;
    end
    ((DIFF_N_EN == 0) & (IDELAY == 1) & (SERDES_MODE != "SDR") & (SERDES_MODE != "BYPASS")) : begin:data_hrio_sgl_input_ddr_dly
      for (input_width = 0 ;input_width < IO_WIDTH ; input_width = input_width + 1) begin : input_control
        assign data_in_from_pins_predelay[input_width] = data_in_from_pins[input_width];
           
        PH1P_LOGIC_HR_ISERDES #(
            .IDDRMODE   (SERDES_MODE)
        ) ddr_for_input_data (
            .sclk       (sclk),
            .pclk       (pclk),
            .rst        (rst),
            .idata      (data_in_from_pins_delay[input_width]),
            .odata      (data_in_to_device[DATA_RATE * input_width+:DATA_RATE])
        );
      end
      assign data_in_to_device_p = 'b0;
      assign data_in_to_device_n = 'b0;
      assign data_out_to_pins = 'b0;
    end
    ((DIFF_N_EN == 0) & (IDELAY == 0) & (SERDES_MODE != "SDR") & (SERDES_MODE != "BYPASS")) : begin:data_hrio_sgl_input_ddr
      for (input_width = 0 ;input_width < IO_WIDTH ; input_width = input_width + 1) begin : input_control    
        PH1P_LOGIC_HR_ISERDES #(
            .IDDRMODE   (SERDES_MODE)
        ) ddr_for_input_data (
            .sclk       (sclk),
            .pclk       (pclk),
            .rst        (rst),
            .idata      (data_in_from_pins[input_width]),
            .odata      (data_in_to_device[DATA_RATE * input_width+:DATA_RATE])
        );
      end
      assign data_in_to_device_p = 'b0;
      assign data_in_to_device_n = 'b0;
      assign data_out_to_pins = 'b0;
    end
    default : ;
    endcase
  end
  endgenerate

// HRIO INPUT DELAY LOGIC
  generate if((IO_TYPE == "HRIO") & (DATA_DIRECTION == "INPUT") & (IDELAY == 1)) begin
    case(1)
    (DIFF_N_EN == 1) : begin:hrio_input_dly_diff
      for (input_width = 0 ;input_width < IO_WIDTH ; input_width = input_width + 1) begin:input_dly_control
        PH1P_LOGIC_DYNAMIC_HR_IDELAY #(
        .DEVICE("PH1P35"),
        .CAS_MODE("NONE")
        )idelay_for_input_n(
            .i         (data_in_from_pins_predelay_n[input_width]),
            .dly       (in_dly[input_width*8+:8]),
            .o         (data_in_from_pins_delay_n[input_width])
        );
        PH1P_LOGIC_DYNAMIC_HR_IDELAY #(
        .DEVICE("PH1P35"),
        .CAS_MODE("NONE")
        )idelay_for_input_p(
            .i         (data_in_from_pins_predelay_p[input_width]),
            .dly       (in_dly[input_width*8+:8]),
            .o         (data_in_from_pins_delay_p[input_width])
        );
      end
    end
    ((DIFF_N_EN == 0) & (IDLY_CASCADE_EN == 1)) : begin:hrio_input_dly_cascade_sgl
      PH1P_LOGIC_DYNAMIC_HR_IDELAY #(
      .DEVICE("PH1P35"),
      .CAS_MODE("MASTER")
      )master_idelay_for_input(
          .i         (data_in_from_pins_predelay),
          .dly       (8'hff),
          .o         (data_in_from_pins_delay),
          .cas_i     (),
          .cas_o     (idly_cas_down[0]),
          .cas_rtn_i (idly_cas_up[0]),
          .cas_rtn_o ()
      );

      for (i=0;i<IDLY_CASCADE_NUM/2;i=i+1) begin:middle_odly_cascade_control   //num of odly
        PH1P_LOGIC_DYNAMIC_HR_ODELAY #(
        .DEVICE("PH1P35"),
        .CAS_MODE("MIDDLE")
        )middle_odelay_for_input(
            .i         (),
            .dly       (8'hff),
            .o         (),
            .cas_i     (idly_cas_down[2*i]),
            .cas_o     (idly_cas_down[2*i+1]),
            .cas_rtn_i (idly_cas_up[2*i+1]),
            .cas_rtn_o (idly_cas_up[2*i])
        );
      end

      for (j=0;j<IDLY_CASCADE_NUM/2-1;j=j+1) begin:middle_idly_cascade_control //num of idly
        PH1P_LOGIC_DYNAMIC_HR_IDELAY #(
        .DEVICE("PH1P35"),
        .CAS_MODE("MIDDLE")
        )middle_idelay_for_input(
            .i         (),
            .dly       (8'hff),
            .o         (),
            .cas_i     (idly_cas_down[2*j+1]),
            .cas_o     (idly_cas_down[2*j+2]),
            .cas_rtn_i (idly_cas_up[2*j+2]),
            .cas_rtn_o (idly_cas_up[2*j+1])
        );
      end

      PH1P_LOGIC_DYNAMIC_HR_IDELAY #(
      .DEVICE("PH1P35"),
      .CAS_MODE("END")
      )end_idelay_for_input(
          .i         (),
          .dly       (in_dly),
          .o         (),
          .cas_i     (idly_cas_down[IDLY_CASCADE_NUM-2]),
          .cas_o     (),
          .cas_rtn_i (),
          .cas_rtn_o (idly_cas_up[IDLY_CASCADE_NUM-2])
      );
    end
    ((DIFF_N_EN == 0) & (IDLY_CASCADE_EN == 0)) : begin:hrio_input_dly_sgl
      for (input_width = 0 ;input_width < IO_WIDTH ; input_width = input_width + 1) begin:input_dly_control
        PH1P_LOGIC_DYNAMIC_HR_IDELAY #(
        .DEVICE("PH1P35"),
        .CAS_MODE("NONE")
        )idelay_for_input(
            .i         (data_in_from_pins_predelay[input_width]),
            .dly       (in_dly[input_width*8+:8]),
            .o         (data_in_from_pins_delay[input_width])
        );
      end
    end
    default : ;
    endcase
  end
  endgenerate

// HDIO
  generate if((IO_TYPE == "HDIO") & (DATA_DIRECTION == "INPUT")) begin
    case(1)
    ((IDELAY == 1) & (SERDES_MODE == "DDRX1")) : begin:data_hdio_input_ddr_dly
      for (input_width = 0 ;input_width < IO_WIDTH ; input_width = input_width + 1) begin : input_control
        assign data_in_from_pins_predelay[input_width] = data_in_from_pins[input_width];
        /*
        PH1P_LOGIC_DYNAMIC_HD_IDELAY idelay_for_input(
          .i    (data_in_from_pins_predelay[input_width]),
          .dly  (in_dly[input_width*5+:5]),
          .o    (data_in_from_pins_delay[input_width])
        );
        */
        PH1P_LOGIC_HD_IDDR #(
          .ASYNCRST ("ENABLE"),
          .MODE     (IDDR_MODE)
        )iddr_for_input_data(
          .clk  (pclk),
          .rst  (rst),
          .d    (data_in_from_pins_delay[input_width]),
          .q1   (data_in_to_device[2 * input_width + 1]),
          .q0   (data_in_to_device[2 * input_width])
        );
      end
      assign data_in_to_device_p = 'b0;
      assign data_in_to_device_n = 'b0;
      assign data_out_to_pins = 'b0; 
    end
    ((IDELAY == 0) & (SERDES_MODE == "DDRX1")) : begin:data_hdio_input_ddr
      for (input_width = 0 ;input_width < IO_WIDTH ; input_width = input_width + 1) begin : input_control
          PH1P_LOGIC_HD_IDDR #(
            .ASYNCRST ("ENABLE"),
            .MODE     (IDDR_MODE)
          )iddr_for_input_data(
            .clk  (pclk),
            .rst  (rst),
            .d    (data_in_from_pins[input_width]),
            .q1   (data_in_to_device[2 * input_width + 1]),
            .q0   (data_in_to_device[2 * input_width])
          );
      end
      assign data_in_to_device_p = 'b0;
      assign data_in_to_device_n = 'b0;
      assign data_out_to_pins = 'b0;
    end
    ((IDELAY == 1) & (SERDES_MODE == "BYPASS")) : begin:data_hdio_input_bypass_dly
      for (input_width = 0 ;input_width < IO_WIDTH ; input_width = input_width + 1) begin : input_control
        assign data_in_from_pins_predelay[input_width] = data_in_from_pins[input_width];
        /*
        PH1P_LOGIC_DYNAMIC_HD_IDELAY idelay_for_input(
          .i    (data_in_from_pins_predelay[input_width]),
          .dly  (in_dly[input_width*5+:5]),
          .o    (data_in_from_pins_delay[input_width])
        );
        */
        assign data_in_to_device[input_width] = data_in_from_pins_delay[input_width];
      end
      assign data_in_to_device_p = 'b0;
      assign data_in_to_device_n = 'b0;
      assign data_out_to_pins = 'b0;
    end
    ((IDELAY == 0) & (SERDES_MODE == "BYPASS")) : begin:data_hdio_input_bypass
      for (input_width = 0 ;input_width < IO_WIDTH ; input_width = input_width + 1) begin : input_control
        assign data_in_to_device[input_width] = data_in_from_pins[input_width];
      end
      assign data_in_to_device_p = 'b0;
      assign data_in_to_device_n = 'b0;
      assign data_out_to_pins = 'b0;
    end
    ((IDELAY == 1) & (SERDES_MODE == "SDR")) : begin:data_hdio_input_sdr_dly
      for (input_width = 0 ;input_width < IO_WIDTH ; input_width = input_width + 1) begin : input_control
        assign data_in_from_pins_predelay[input_width] = data_in_from_pins[input_width];
        /* 
        PH1P_LOGIC_DYNAMIC_HD_IDELAY idelay_for_input(
          .i    (data_in_from_pins_predelay[input_width]),
          .dly  (in_dly[input_width*5+:5]),
          .o    (data_in_from_pins_delay[input_width])
        );
        */
        always@(posedge pclk or posedge rst)  begin:sdr_for_input_data
          if(rst)
              data_in_to_device_reg[input_width] <= 0;
          else
              data_in_to_device_reg[input_width] <= data_in_from_pins_delay[input_width];
        end
        assign data_in_to_device[input_width] = data_in_to_device_reg[input_width];
      end
      assign data_in_to_device_p = 'b0;
      assign data_in_to_device_n = 'b0;
      assign data_out_to_pins = 'b0;
    end
    ((IDELAY == 0) & (SERDES_MODE == "SDR")) : begin:data_hdio_input_sdr
      for (input_width = 0 ;input_width < IO_WIDTH ; input_width = input_width + 1) begin : input_control
        always@(posedge pclk or posedge rst)  begin
          if(rst)
              data_in_to_device_reg[input_width] <= 0;
          else
              data_in_to_device_reg[input_width] <= data_in_from_pins[input_width];
        end
        assign data_in_to_device[input_width] = data_in_to_device_reg[input_width];
      end
      assign data_in_to_device_n = 'b0;
      assign data_in_to_device_p = 'b0;
      assign data_out_to_pins = 'b0; 
    end
    default : ;
    endcase
  end
  endgenerate

// HDIO INPUT DELAY LOGIC
  generate if((IO_TYPE == "HDIO") & (DATA_DIRECTION == "INPUT") & (IDELAY == 1)) begin
    case(1)
    (IDLY_CASCADE_EN == 1) : begin:hdio_input_dly_cascade_sgl
      PH1P_LOGIC_DYNAMIC_HD_IDELAY #(
      .CAS_MODE("MASTER")
      )master_idelay_for_input(
          .i         (data_in_from_pins_predelay),
          .dly       (5'h1f),
          .o         (data_in_from_pins_delay),
          .cas_i     (),
          .cas_o     (idly_cas_down[0]),
          .cas_rtn_i (idly_cas_up[0]),
          .cas_rtn_o ()
      );

      for (i=0;i<IDLY_CASCADE_NUM/2;i=i+1) begin:middle_odly_cascade_control  //num of odly
        PH1P_LOGIC_DYNAMIC_HD_ODELAY #(
        .CAS_MODE("MIDDLE")
        )middle_odelay_for_input(
            .i         (),
            .dly       (5'h1f),
            .o         (),
            .cas_i     (idly_cas_down[2*i]),
            .cas_o     (idly_cas_down[2*i+1]),
            .cas_rtn_i (idly_cas_up[2*i+1]),
            .cas_rtn_o (idly_cas_up[2*i])
        );
      end

      for (j=0;j<IDLY_CASCADE_NUM/2-1;j=j+1) begin:middle_idly_cascade_control //num of idly
        PH1P_LOGIC_DYNAMIC_HD_IDELAY #(
        .CAS_MODE("MIDDLE")
        )middle_idelay_for_input(
            .i         (),
            .dly       (5'h1f),
            .o         (),
            .cas_i     (idly_cas_down[2*j+1]),
            .cas_o     (idly_cas_down[2*j+2]),
            .cas_rtn_i (idly_cas_up[2*j+2]),
            .cas_rtn_o (idly_cas_up[2*j+1])
        );
      end

      PH1P_LOGIC_DYNAMIC_HD_IDELAY #(
      .CAS_MODE("END")
      )end_idelay_for_input(
          .i         (),
          .dly       (in_dly),
          .o         (),
          .cas_i     (idly_cas_down[IDLY_CASCADE_NUM-2]),
          .cas_o     (),
          .cas_rtn_i (),
          .cas_rtn_o (idly_cas_up[IDLY_CASCADE_NUM-2])
      );
    end
    (IDLY_CASCADE_EN == 0) : begin:hdio_input_dly_sgl
      for (input_width = 0 ;input_width < IO_WIDTH ; input_width = input_width + 1) begin:input_dly_control
        PH1P_LOGIC_DYNAMIC_HD_IDELAY #(
        .CAS_MODE("NONE")
        )idelay_for_input(
            .i         (data_in_from_pins_predelay[input_width]),
            .dly       (in_dly[input_width*5+:5]),
            .o         (data_in_from_pins_delay[input_width])
        );
      end
    end
    default : ;
    endcase
  end
  endgenerate

///////////////////////////////////////////////////////////
//--------------------------OUTPUT-----------------------//
///////////////////////////////////////////////////////////
// HRIO
  genvar output_width;
  generate if((IO_TYPE == "HRIO") & (DATA_DIRECTION == "OUTPUT")) begin
    case(1)
    ((ODELAY == 1) & (SERDES_MODE == "BYPASS")) : begin:data_output_bypass_dly
      for (output_width = 0 ;output_width < IO_WIDTH ; output_width = output_width + 1) begin : output_control
        assign data_out_to_pins_predelay[output_width] = data_out_from_device[output_width];
        
        assign data_out_to_pins[output_width] = data_out_to_pins_delay[output_width];
      end
      assign data_in_to_device_p = 'b0;
      assign data_in_to_device_n = 'b0;
      assign data_in_to_device = 'b0;
    end 
    ((ODELAY == 0) & (SERDES_MODE == "BYPASS")) : begin:data_output_bypass
      for (output_width = 0 ;output_width < IO_WIDTH ; output_width = output_width + 1) begin : output_control
        assign data_out_to_pins[output_width] = data_out_from_device[output_width];
      end
      assign data_in_to_device_p = 'b0;
      assign data_in_to_device_n = 'b0;
      assign data_in_to_device = 'b0;
    end
    ((ODELAY == 1) & (SERDES_MODE == "SDR")) : begin:data_output_sdr_dly
      for (output_width = 0 ;output_width < IO_WIDTH ; output_width = output_width + 1) begin : output_control
        always@(posedge pclk or posedge rst) begin
          if(rst)
              data_out_to_pins_predelay_reg[output_width] <= 0;
          else
              data_out_to_pins_predelay_reg[output_width] <= data_out_from_device[output_width];
        end 
        assign  data_out_to_pins_predelay[output_width] = data_out_to_pins_predelay_reg[output_width];
        
        assign data_out_to_pins[output_width] = data_out_to_pins_delay[output_width];
      end
      assign data_in_to_device_p = 'b0;
      assign data_in_to_device_n = 'b0;
      assign data_in_to_device = 'b0;
    end
    ((ODELAY == 0) & (SERDES_MODE == "SDR")) : begin:data_output_sdr
      for (output_width = 0 ;output_width < IO_WIDTH ; output_width = output_width + 1) begin : output_control
        always@(posedge pclk or posedge rst) begin
          if(rst)
              data_out_to_pins_predelay_reg[output_width] <= 0;
          else
              data_out_to_pins_predelay_reg[output_width] <= data_out_from_device[output_width];
        end 
        assign  data_out_to_pins[output_width] = data_out_to_pins_predelay_reg[output_width];
      end
      assign data_in_to_device_p = 'b0;
      assign data_in_to_device_n = 'b0;
      assign data_in_to_device = 'b0;
    end
    ((ODELAY == 1) & (SERDES_MODE != "SDR") & (SERDES_MODE != "BYPASS")) : begin:data_output_ddr_dly
      for (output_width = 0 ;output_width < IO_WIDTH ; output_width = output_width + 1) begin : output_control
        PH1P_LOGIC_HR_OSERDES #(
            .ODDRMODE   (SERDES_MODE)
        )ddr_for_output_data(
            .sclk       (sclk),
            .pclk       (pclk),
            .rst        (rst),
            .idata      (data_out_from_device[DATA_RATE * output_width+:DATA_RATE]),
            .odata      (data_out_to_pins_predelay[output_width])
        );  
        
        assign data_out_to_pins[output_width] = data_out_to_pins_delay[output_width]; 
      end
      assign data_in_to_device_p = 'b0;
      assign data_in_to_device_n = 'b0;
      assign data_in_to_device = 'b0;
    end
    ((ODELAY == 0) & (SERDES_MODE != "SDR") & (SERDES_MODE != "BYPASS")) : begin:data_output_ddr
      for (output_width = 0 ;output_width < IO_WIDTH ; output_width = output_width + 1) begin : output_control
        PH1P_LOGIC_HR_OSERDES #(
            .ODDRMODE   (SERDES_MODE)
        )ddr_for_output_data(
            .sclk       (sclk),
            .pclk       (pclk),
            .rst        (rst),
            .idata      (data_out_from_device[DATA_RATE * output_width+:DATA_RATE]),
            .odata      (data_out_to_pins[output_width])
        );
      end
      assign data_in_to_device_p = 'b0;
      assign data_in_to_device_n = 'b0;
      assign data_in_to_device = 'b0;
    end
    default : ;
    endcase
  end
  endgenerate

// HRIO OUTPUT DELAY LOGIC
  generate if((IO_TYPE == "HRIO") & (DATA_DIRECTION == "OUTPUT") & (ODELAY == 1)) begin
    case(1)
    (ODLY_CASCADE_EN == 1) : begin:hrio_output_dly_cascade
      PH1P_LOGIC_DYNAMIC_HR_ODELAY #(
        .DEVICE("PH1P35"),
        .CAS_MODE("MASTER")
      )master_odelay_for_output(
          .i         (data_out_to_pins_predelay),
          .dly       (8'hff),
          .o         (data_out_to_pins_delay),
          .cas_i     (),
          .cas_o     (odly_cas_down[0]),
          .cas_rtn_i (odly_cas_up[0]),
          .cas_rtn_o ()
      );

      for (i=0;i<ODLY_CASCADE_NUM/2-1;i=i+1) begin:middle_dly_cascade_control
        PH1P_LOGIC_DYNAMIC_HR_IDELAY #(
        .DEVICE("PH1P35"),
        .CAS_MODE("MIDDLE")
        )middle_idelay_for_output(
            .i         (),
            .dly       (8'hff),
            .o         (),
            .cas_i     (odly_cas_down[2*i]),
            .cas_o     (odly_cas_down[2*i+1]),
            .cas_rtn_i (odly_cas_up[2*i+1]),
            .cas_rtn_o (odly_cas_up[2*i])
        );
        PH1P_LOGIC_DYNAMIC_HR_ODELAY #(
        .DEVICE("PH1P35"),
        .CAS_MODE("MIDDLE")
        )middle_odelay_for_output(
            .i         (),
            .dly       (8'hff),
            .o         (),
            .cas_i     (odly_cas_down[2*i+1]),
            .cas_o     (odly_cas_down[2*i+2]),
            .cas_rtn_i (odly_cas_up[2*i+2]),
            .cas_rtn_o (odly_cas_up[2*i+1])
        );
      end

      PH1P_LOGIC_DYNAMIC_HR_IDELAY #(
      .DEVICE("PH1P35"),
      .CAS_MODE("END")
      )end_idelay_for_output(
          .i         (),
          .dly       (out_dly),
          .o         (),
          .cas_i     (odly_cas_down[ODLY_CASCADE_NUM-2]),
          .cas_o     (),
          .cas_rtn_i (),
          .cas_rtn_o (odly_cas_up[ODLY_CASCADE_NUM-2])
      );
    end
    (ODLY_CASCADE_EN == 0) : begin:hrio_output_dly
      for (output_width = 0 ;output_width < IO_WIDTH ; output_width = output_width + 1) begin:output_dly_control
        PH1P_LOGIC_DYNAMIC_HR_ODELAY #(
        .DEVICE("PH1P35"),
        .CAS_MODE("NONE")
        )odelay_for_output(
            .i         (data_out_to_pins_predelay[output_width]),
            .dly       (out_dly[output_width*8+:8]),
            .o         (data_out_to_pins_delay[output_width])
        );
      end
    end
    default : ;
    endcase
  end
  endgenerate

// HDIO
  generate if((IO_TYPE == "HDIO") & (DATA_DIRECTION == "OUTPUT")) begin
    case(1)
    ((ODELAY == 1) & (SERDES_MODE == "DDRX1")) : begin:data_hdio_output_ddr_dly
      for (output_width = 0 ;output_width < IO_WIDTH ; output_width = output_width + 1) begin : output_control
        PH1P_LOGIC_HD_ODDR #(
          .ASYNCRST ("ENABLE")
        )oddr_for_output_data(
          .clk  (pclk),
          .rst  (rst),
          .q    (data_out_to_pins_predelay[output_width]),
          .d1   (data_out_from_device[2 * output_width + 1]),
          .d0   (data_out_from_device[2 * output_width])
        );
        /*
        PH1P_LOGIC_DYNAMIC_HD_ODELAY odelay_for_output(
          .i    (data_out_to_pins_predelay[output_width]),
          .dly  (out_dly[output_width*5+:5]),
          .o    (data_out_to_pins_delay[output_width])
        );
        */
        assign data_out_to_pins[output_width] = data_out_to_pins_delay[output_width];
      end
      assign data_in_to_device_p = 'b0;
      assign data_in_to_device_n = 'b0;
      assign data_in_to_device = 'b0;
    end
    ((ODELAY == 0) & (SERDES_MODE == "DDRX1")) : begin:data_hdio_output_ddr
      for (output_width = 0 ;output_width < IO_WIDTH ; output_width = output_width + 1) begin : output_control
        PH1P_LOGIC_HD_ODDR #(
          .ASYNCRST ("ENABLE")
        )oddr_for_output_data(
          .clk  (pclk),
          .rst  (rst),
          .q    (data_out_to_pins[output_width]),
          .d1   (data_out_from_device[2 * output_width + 1]),
          .d0   (data_out_from_device[2 * output_width])
        );
      end
      assign data_in_to_device_p = 'b0;
      assign data_in_to_device_n = 'b0;
      assign data_in_to_device = 'b0;
    end
    ((ODELAY == 1) & (SERDES_MODE == "BYPASS")) : begin:data_hdio_output_bypass_dly
      for (output_width = 0 ;output_width < IO_WIDTH ; output_width = output_width + 1) begin : output_control
        assign data_out_to_pins_predelay[output_width] = data_out_from_device[output_width];
        /*
        PH1P_LOGIC_DYNAMIC_HD_ODELAY odelay_for_output(
          .i    (data_out_to_pins_predelay[output_width]),
          .dly  (out_dly[output_width*5+:5]),
          .o    (data_out_to_pins_delay[output_width])
        );
        */
        assign data_out_to_pins[output_width] = data_out_to_pins_delay[output_width];
      end
      assign data_in_to_device_p = 'b0;
      assign data_in_to_device_n = 'b0;
      assign data_in_to_device = 'b0;
    end
    ((ODELAY == 0) & (SERDES_MODE == "BYPASS")) : begin:data_hdio_output_bypass
      for (output_width = 0 ;output_width < IO_WIDTH ; output_width = output_width + 1) begin : output_control
        assign data_out_to_pins[output_width] = data_out_from_device[output_width];
      end
      assign data_in_to_device_p = 'b0;
      assign data_in_to_device_n = 'b0;
      assign data_in_to_device = 'b0;
    end
    ((ODELAY == 1) & (SERDES_MODE == "SDR")) : begin:data_hdio_output_sdr_dly
      for (output_width = 0 ;output_width < IO_WIDTH ; output_width = output_width + 1) begin : output_control
        always@(posedge pclk or posedge rst) begin
          if(rst)
              data_out_to_pins_predelay_reg[output_width] <= 0;
          else
              data_out_to_pins_predelay_reg[output_width] <= data_out_from_device[output_width];
        end 

        assign  data_out_to_pins_predelay[output_width] = data_out_to_pins_predelay_reg[output_width];
        /*
        PH1P_LOGIC_DYNAMIC_HD_ODELAY odelay_for_output(
          .i    (data_out_to_pins_predelay[output_width]),
          .dly  (out_dly[output_width*5+:5]),
          .o    (data_out_to_pins_delay[output_width])
        );
        */
        assign data_out_to_pins[output_width] = data_out_to_pins_delay[output_width];
      end
      assign data_in_to_device_p = 'b0;
      assign data_in_to_device_n = 'b0;
      assign data_in_to_device = 'b0;
    end
    ((ODELAY == 0) & (SERDES_MODE == "SDR")) : begin:data_hdio_output_sdr
      for (output_width = 0 ;output_width < IO_WIDTH ; output_width = output_width + 1) begin : output_control
        always@(posedge pclk or posedge rst) begin
          if(rst)
              data_out_to_pins_predelay_reg[output_width] <= 0;
          else
              data_out_to_pins_predelay_reg[output_width] <= data_out_from_device[output_width];
        end 
        assign  data_out_to_pins[output_width] = data_out_to_pins_predelay_reg[output_width];
      end
      assign data_in_to_device_p = 'b0;
      assign data_in_to_device_n = 'b0;
      assign data_in_to_device = 'b0;
    end
    default : ;
    endcase
  end
  endgenerate

// HDIO OUTPUT DELAY LOGIC
  generate if((IO_TYPE == "HDIO") & (DATA_DIRECTION == "OUTPUT") & (ODELAY == 1)) begin
    case(1)
    (ODLY_CASCADE_EN == 1) : begin:hdio_output_dly_cascade
      PH1P_LOGIC_DYNAMIC_HD_ODELAY #(
        .CAS_MODE("MASTER")
      )master_odelay_for_output(
          .i         (data_out_to_pins_predelay),
          .dly       (5'h1f),
          .o         (data_out_to_pins_delay),
          .cas_i     (),
          .cas_o     (odly_cas_down[0]),
          .cas_rtn_i (odly_cas_up[0]),
          .cas_rtn_o ()
      );

      for (i=0;i<ODLY_CASCADE_NUM/2-1;i=i+1) begin:middle_dly_cascade_control
        PH1P_LOGIC_DYNAMIC_HD_IDELAY #(
        .CAS_MODE("MIDDLE")
        )middle_idelay_for_output(
            .i         (),
            .dly       (5'h1f),
            .o         (),
            .cas_i     (odly_cas_down[2*i]),
            .cas_o     (odly_cas_down[2*i+1]),
            .cas_rtn_i (odly_cas_up[2*i+1]),
            .cas_rtn_o (odly_cas_up[2*i])
        );
        PH1P_LOGIC_DYNAMIC_HD_ODELAY #(
        .CAS_MODE("MIDDLE")
        )middle_odelay_for_output(
            .i         (),
            .dly       (5'h1f),
            .o         (),
            .cas_i     (odly_cas_down[2*i+1]),
            .cas_o     (odly_cas_down[2*i+2]),
            .cas_rtn_i (odly_cas_up[2*i+2]),
            .cas_rtn_o (odly_cas_up[2*i+1])
        );
      end

      PH1P_LOGIC_DYNAMIC_HD_IDELAY #(
      .CAS_MODE("END")
      )end_idelay_for_output(
          .i         (),
          .dly       (out_dly),
          .o         (),
          .cas_i     (odly_cas_down[ODLY_CASCADE_NUM-2]),
          .cas_o     (),
          .cas_rtn_i (),
          .cas_rtn_o (odly_cas_up[ODLY_CASCADE_NUM-2])
      );
    end
    (ODLY_CASCADE_EN == 0) : begin:hdio_output_dly
      for (output_width = 0 ;output_width < IO_WIDTH ; output_width = output_width + 1) begin:output_dly_control
        PH1P_LOGIC_DYNAMIC_HD_ODELAY #(
        .CAS_MODE("NONE")
        )odelay_for_output(
            .i         (data_out_to_pins_predelay[output_width]),
            .dly       (out_dly[output_width*5+:5]),
            .o         (data_out_to_pins_delay[output_width])
        );
      end
    end
    default : ;
    endcase
  end
  endgenerate

////////////////////////////////////////////////////////////////
//--------------------------BIDIRECTIONAL-----------------------//
////////////////////////////////////////////////////////////////
// HRIO
  genvar inout_width;
  generate if((IO_TYPE == "HRIO") & (DATA_DIRECTION == "BIDIRECTIONAL")) begin
    case(1)
    ((SERDES_MODE == "BYPASS") & (DIFF_N_EN == 1)) : begin:data_diff_inout_bypass
      for (inout_width = 0 ;inout_width < IO_WIDTH ; inout_width = inout_width + 1) begin : inout_control
        PH1P_LOGIC_IOBUF_DIFF #(
            .DIFF_TERM("TRUE")
        )diff_iob(
            .i              (data_out_to_pins_delay[inout_width]),
            .interm_disable (1'b1),
            .t              (tristate_ctr),
            .o_p            (data_in_from_pins_predelay_p[inout_width]),
            .o_n            (data_in_from_pins_predelay_n[inout_width]),
            .io_p           (data_from_and_to_pins_p[inout_width]),
            .io_n           (data_from_and_to_pins_n[inout_width])
        );

        if (IDELAY == 1) begin
          PH1P_LOGIC_DYNAMIC_HR_IDELAY #(
          .DEVICE("PH1P35")
          )idelay_for_input_n_control(
              .i         (data_in_from_pins_predelay_n[inout_width]),
              .dly       (in_dly[inout_width*8+:8]),
              .o         (data_in_from_pins_delay_n[inout_width])
          );
          PH1P_LOGIC_DYNAMIC_HR_IDELAY #(
          .DEVICE("PH1P35")
          )idelay_for_input_p_control(
              .i         (data_in_from_pins_predelay_p[inout_width]),
              .dly       (in_dly[inout_width*8+:8]),
              .o         (data_in_from_pins_delay_p[inout_width])
          );
          assign data_in_to_device_n[inout_width] = data_in_from_pins_delay_n[inout_width];
          assign data_in_to_device_p[inout_width] = data_in_from_pins_delay_p[inout_width];
        end
        else begin
          assign data_in_to_device_n[inout_width] = data_in_from_pins_predelay_n[inout_width];
          assign data_in_to_device_p[inout_width] = data_in_from_pins_predelay_p[inout_width];
        end

        if (ODELAY == 1) begin
          assign data_out_to_pins_predelay[inout_width] = data_out_from_device[inout_width];
          PH1P_LOGIC_DYNAMIC_HR_ODELAY #(
          .DEVICE("PH1P35")
          )odelay_for_output_control(
              .i         (data_out_to_pins_predelay[inout_width]),
              .dly       (out_dly[inout_width*8+:8]),
              .o         (data_out_to_pins_delay[inout_width])
          );
        end
        else
          assign data_out_to_pins_delay[inout_width] = data_out_from_device[inout_width];
      end
      assign data_out_to_pins = 'b0;
      assign data_in_to_device = 'b0;
    end
    ((SERDES_MODE == "BYPASS") & (DIFF_N_EN == 0)) : begin:data_sgl_inout_bypass
      for (inout_width = 0 ;inout_width < IO_WIDTH ; inout_width = inout_width + 1) begin:inout_control
        PH1P_LOGIC_IOTRIBUF single_iob(
            .i          (data_out_to_pins_delay[inout_width]),
            .t          (tristate_ctr),
            .o          (data_in_from_pins_predelay[inout_width]),
            .io         (data_from_and_to_pins[inout_width])
        );

        if (IDELAY == 1) begin
          PH1P_LOGIC_DYNAMIC_HR_IDELAY #(
          .DEVICE("PH1P35")
          )idelay_for_input_control(
              .i         (data_in_from_pins_predelay[inout_width]),
              .dly       (in_dly[inout_width*8+:8]),
              .o         (data_in_from_pins_delay[inout_width])
          );
          assign data_in_to_device[inout_width] = data_in_from_pins_delay[inout_width];
        end
        else
          assign data_in_to_device[inout_width] = data_in_from_pins_predelay[inout_width];
        
        if (ODELAY == 1) begin
          assign data_out_to_pins_predelay[inout_width] = data_out_from_device[inout_width]; 
          PH1P_LOGIC_DYNAMIC_HR_ODELAY #(
          .DEVICE("PH1P35")
          )odelay_for_output_control(
              .i         (data_out_to_pins_predelay[inout_width]),
              .dly       (out_dly[inout_width*8+:8]),
              .o         (data_out_to_pins_delay[inout_width])
          );
        end
        else
          assign data_out_to_pins_delay[inout_width] = data_out_from_device[inout_width];
      end
      assign data_out_to_pins = 'b0;
      assign data_in_to_device_p = 'b0;
      assign data_in_to_device_n = 'b0;
    end
    ((SERDES_MODE == "SDR") & (DIFF_N_EN == 1)) : begin:data_diff_inout_sdr
      for (inout_width = 0 ;inout_width < IO_WIDTH ; inout_width = inout_width + 1) begin:inout_control
        PH1P_LOGIC_IOBUF_DIFF #(
            .DIFF_TERM("TRUE")
        )diff_iob(
            .i              (data_out_to_pins_delay[inout_width]),
            .interm_disable (1'b1),
            .t              (tristate_ctr),
            .o_p            (data_in_from_pins_predelay_p[inout_width]),
            .o_n            (data_in_from_pins_predelay_n[inout_width]),
            .io_p           (data_from_and_to_pins_p[inout_width]),
            .io_n           (data_from_and_to_pins_n[inout_width])
        );

        if (IDELAY == 1) begin
          PH1P_LOGIC_DYNAMIC_HR_IDELAY #(
          .DEVICE("PH1P35")
          )idelay_for_input_n_control(
              .i         (data_in_from_pins_predelay_n[inout_width]),
              .dly       (in_dly[inout_width*8+:8]),
              .o         (data_in_from_pins_delay_n[inout_width])
          );
          PH1P_LOGIC_DYNAMIC_HR_IDELAY #(
          .DEVICE("PH1P35")
          )idelay_for_input_p_control(
              .i         (data_in_from_pins_predelay_p[inout_width]),
              .dly       (in_dly[inout_width*8+:8]),
              .o         (data_in_from_pins_delay_p[inout_width])
          );
          always@(posedge pclk)  begin
            if(rst) begin
                data_in_to_device_n_reg[inout_width] <= 0;
                data_in_to_device_p_reg[inout_width] <= 0;
            end
            else begin
                data_in_to_device_n_reg[inout_width] <= data_in_from_pins_delay_n[inout_width];
                data_in_to_device_p_reg[inout_width] <= data_in_from_pins_delay_p[inout_width];
            end
          end
          assign data_in_to_device_n[inout_width] = data_in_to_device_n_reg[inout_width];
          assign data_in_to_device_p[inout_width] = data_in_to_device_p_reg[inout_width];
        end
        else begin
          always@(posedge pclk)  begin
            if(rst) begin
                data_in_to_device_n_reg[inout_width] <= 0;
                data_in_to_device_p_reg[inout_width] <= 0;
            end
            else begin
                data_in_to_device_n_reg[inout_width] <= data_in_from_pins_predelay_n[inout_width];
                data_in_to_device_p_reg[inout_width] <= data_in_from_pins_predelay_p[inout_width];
            end
          end
          assign data_in_to_device_n[inout_width] = data_in_to_device_n_reg[inout_width];
          assign data_in_to_device_p[inout_width] = data_in_to_device_p_reg[inout_width];
        end

        if (ODELAY == 1) begin
          always@(posedge pclk or posedge rst)  begin
            if(rst) begin
                data_out_to_pins_predelay_reg[inout_width] <= 0;
            end
            else begin
                data_out_to_pins_predelay_reg[inout_width] <= data_out_from_device[inout_width];
            end
          end
          assign data_out_to_pins_predelay[inout_width] = data_out_to_pins_predelay_reg[inout_width];
          PH1P_LOGIC_DYNAMIC_HR_ODELAY #(
          .DEVICE("PH1P35")
          )odelay_for_output_control(
              .i         (data_out_to_pins_predelay[inout_width]),
              .dly       (out_dly[inout_width*8+:8]),
              .o         (data_out_to_pins_delay[inout_width])
          );
        end
        else begin
          always@(posedge pclk or posedge rst)  begin
            if(rst) begin
                data_out_to_pins_predelay_reg[inout_width] <= 0;
            end
            else begin
                data_out_to_pins_predelay_reg[inout_width] <= data_out_from_device[inout_width];
            end
          end
          assign data_out_to_pins_delay[inout_width] = data_out_to_pins_predelay_reg[inout_width];
        end
      end
      assign data_out_to_pins = 'b0;
      assign data_in_to_device = 'b0;
    end
    ((SERDES_MODE == "SDR") & (DIFF_N_EN == 0)) : begin:data_sgl_inout_sdr
      for (inout_width = 0 ;inout_width < IO_WIDTH ; inout_width = inout_width + 1) begin:inout_control
        PH1P_LOGIC_IOTRIBUF single_iob(
            .i          (data_out_to_pins_delay[inout_width]),
            .t          (tristate_ctr),
            .o          (data_in_from_pins_predelay[inout_width]),
            .io         (data_from_and_to_pins[inout_width])
        );

        if (IDELAY == 1) begin
          PH1P_LOGIC_DYNAMIC_HR_IDELAY #(
          .DEVICE("PH1P35")
          )idelay_for_input_control(
              .i         (data_in_from_pins_predelay[inout_width]),
              .dly       (in_dly[inout_width*8+:8]),
              .o         (data_in_from_pins_delay[inout_width])
          );
          always@(posedge pclk)  begin
            if(rst) begin
                data_in_to_device_reg[inout_width] <= 0;
            end
            else begin
                data_in_to_device_reg[inout_width] <= data_in_from_pins_delay[inout_width];
            end
          end
          assign data_in_to_device[inout_width] = data_in_to_device_reg[inout_width];
        end
        else begin
          always@(posedge pclk)  begin
            if(rst)
                data_in_to_device_reg[inout_width] <= 0;
            else
                data_in_to_device_reg[inout_width] <= data_in_from_pins_predelay[inout_width];
          end
          assign data_in_to_device[inout_width] = data_in_to_device_reg[inout_width];
        end

        if (ODELAY == 1) begin
          always@(posedge pclk or posedge rst)  begin
            if(rst)
                data_out_to_pins_predelay_reg[inout_width] <= 0;
            else
                data_out_to_pins_predelay_reg[inout_width] <= data_out_from_device[inout_width];
          end
          assign data_out_to_pins_predelay[inout_width] = data_out_to_pins_predelay_reg[inout_width];
          PH1P_LOGIC_DYNAMIC_HR_ODELAY #(
          .DEVICE("PH1P35")
          )odelay_for_output_control(
              .i         (data_out_to_pins_predelay[inout_width]),
              .dly       (out_dly[inout_width*8+:8]),
              .o         (data_out_to_pins_delay[inout_width])
          );
        end
        else begin
          always@(posedge pclk or posedge rst)  begin
            if(rst) 
                data_out_to_pins_predelay_reg[inout_width] <= 0;
            else 
                data_out_to_pins_predelay_reg[inout_width] <= data_out_from_device[inout_width];
          end
          assign data_out_to_pins_delay[inout_width] = data_out_to_pins_predelay_reg[inout_width];
        end
      end
      assign data_out_to_pins = 'b0;
      assign data_in_to_device_p = 'b0;
      assign data_in_to_device_n = 'b0;
    end
    ((SERDES_MODE != "BYPASS") & (SERDES_MODE != "SDR") & (DIFF_N_EN == 1)) : begin:data_diff_inout_ddr
      for (inout_width = 0 ;inout_width < IO_WIDTH ; inout_width = inout_width + 1) begin:inout_control
        PH1P_LOGIC_IOBUF_DIFF #(
            .DIFF_TERM("TRUE")
        )diff_iob(
            .i              (data_out_to_pins_delay[inout_width]),
            .interm_disable (1'b1),
            .t              (tristate_ctr),
            .o_p            (data_in_from_pins_predelay_p[inout_width]),
            .o_n            (data_in_from_pins_predelay_n[inout_width]),
            .io_p           (data_from_and_to_pins_p[inout_width]),
            .io_n           (data_from_and_to_pins_n[inout_width])
        );

        if (IDELAY == 1) begin
          PH1P_LOGIC_DYNAMIC_HR_IDELAY #(
          .DEVICE("PH1P35")
          )idelay_for_input_n_control(
              .i         (data_in_from_pins_predelay_n[inout_width]),
              .dly       (in_dly[inout_width*8+:8]),
              .o         (data_in_from_pins_delay_n[inout_width])
          );
          PH1P_LOGIC_DYNAMIC_HR_IDELAY #(
          .DEVICE("PH1P35")
          )idelay_for_input_p_control(
              .i         (data_in_from_pins_predelay_p[inout_width]),
              .dly       (in_dly[inout_width*8+:8]),
              .o         (data_in_from_pins_delay_p[inout_width])
          );

          if((SERDES_MODE == "DDRX1") & (INPUT_DATA_PIPE == 1)) begin
            PH1P_LOGIC_HR_ISERDES #(
              .IDDRMODE   ("DDRX1_PIPE")
            ) ddr_for_input_data_p (
                .sclk       (sclk),
                .pclk       (pclk),
                .rst        (rst),
                .idata      (data_in_from_pins_delay_p[inout_width]),
                .odata      (data_in_to_device_p[DATA_RATE * inout_width+:DATA_RATE])
            );
            PH1P_LOGIC_HR_ISERDES #(
                .IDDRMODE   ("DDRX1_PIPE")
            ) ddr_for_input_data_n (
                .sclk       (sclk),
                .pclk       (pclk),
                .rst        (rst),
                .idata      (data_in_from_pins_delay_n[inout_width]),
                .odata      (data_in_to_device_n[DATA_RATE * inout_width+:DATA_RATE])
            );
          end
          else begin
            PH1P_LOGIC_HR_ISERDES #(
                .IDDRMODE   (SERDES_MODE)
            ) ddr_for_input_data_p (
                .sclk       (sclk),
                .pclk       (pclk),
                .rst        (rst),
                .idata      (data_in_from_pins_delay_p[inout_width]),
                .odata      (data_in_to_device_p[DATA_RATE * inout_width+:DATA_RATE])
            );
            PH1P_LOGIC_HR_ISERDES #(
                .IDDRMODE   (SERDES_MODE)
            ) ddr_for_input_data_n (
                .sclk       (sclk),
                .pclk       (pclk),
                .rst        (rst),
                .idata      (data_in_from_pins_delay_n[inout_width]),
                .odata      (data_in_to_device_n[DATA_RATE * inout_width+:DATA_RATE])
            );
          end
        end
        else begin
          if((SERDES_MODE == "DDRX1") & (INPUT_DATA_PIPE == 1)) begin
            PH1P_LOGIC_HR_ISERDES #(
              .IDDRMODE   ("DDRX1_PIPE")
            ) ddr_for_input_data_p (
                .sclk       (sclk),
                .pclk       (pclk),
                .rst        (rst),
                .idata      (data_in_from_pins_predelay_p[inout_width]),
                .odata      (data_in_to_device_p[DATA_RATE * inout_width+:DATA_RATE])
            );
            PH1P_LOGIC_HR_ISERDES #(
                .IDDRMODE   ("DDRX1_PIPE")
            ) ddr_for_input_data_n (
                .sclk       (sclk),
                .pclk       (pclk),
                .rst        (rst),
                .idata      (data_in_from_pins_predelay_n[inout_width]),
                .odata      (data_in_to_device_n[DATA_RATE * inout_width+:DATA_RATE])
            );
          end
          else begin
            PH1P_LOGIC_HR_ISERDES #(
                .IDDRMODE   (SERDES_MODE)
            ) ddr_for_input_data_p (
                .sclk       (sclk),
                .pclk       (pclk),
                .rst        (rst),
                .idata      (data_in_from_pins_predelay_p[inout_width]),
                .odata      (data_in_to_device_p[DATA_RATE * inout_width+:DATA_RATE])
            );
            PH1P_LOGIC_HR_ISERDES #(
                .IDDRMODE   (SERDES_MODE)
            ) ddr_for_input_data_n (
                .sclk       (sclk),
                .pclk       (pclk),
                .rst        (rst),
                .idata      (data_in_from_pins_predelay_n[inout_width]),
                .odata      (data_in_to_device_n[DATA_RATE * inout_width+:DATA_RATE])
            );
          end
        end

        if (ODELAY == 1) begin
          PH1P_LOGIC_HR_OSERDES #(
              .ODDRMODE   (SERDES_MODE)
          )ddr_for_output_data(
              .sclk       (sclk),
              .pclk       (pclk),
              .rst        (rst),
              .idata      (data_out_from_device[DATA_RATE * inout_width+:DATA_RATE]),
              .odata      (data_out_to_pins_predelay[inout_width])
          );
          PH1P_LOGIC_DYNAMIC_HR_ODELAY #(
          .DEVICE("PH1P35")
          )odelay_for_output_control(
              .i         (data_out_to_pins_predelay[inout_width]),
              .dly       (out_dly[inout_width*8+:8]),
              .o         (data_out_to_pins_delay[inout_width])
          );
        end
        else begin
          PH1P_LOGIC_HR_OSERDES #(
              .ODDRMODE   (SERDES_MODE)
          )ddr_for_output_data(
              .sclk       (sclk),
              .pclk       (pclk),
              .rst        (rst),
              .idata      (data_out_from_device[DATA_RATE * inout_width+:DATA_RATE]),
              .odata      (data_out_to_pins_delay[inout_width])
          );
        end
      end
      assign data_in_to_device = 'b0;
      assign data_out_to_pins = 'b0;
    end
    ((SERDES_MODE != "BYPASS") & (SERDES_MODE != "SDR") & (DIFF_N_EN == 0)) : begin:data_sgl_inout_ddr
      for (inout_width = 0 ;inout_width < IO_WIDTH ; inout_width = inout_width + 1) begin:inout_control
        PH1P_LOGIC_IOTRIBUF single_iob(
            .i          (data_out_to_pins_delay[inout_width]),
            .t          (tristate_ctr),
            .o          (data_in_from_pins_predelay[inout_width]),
            .io         (data_from_and_to_pins[inout_width])
        );

        if (IDELAY == 1) begin
          PH1P_LOGIC_DYNAMIC_HR_IDELAY #(
          .DEVICE("PH1P35")
          )idelay_for_input_control(
              .i         (data_in_from_pins_predelay[inout_width]),
              .dly       (in_dly[inout_width*8+:8]),
              .o         (data_in_from_pins_delay[inout_width])
          );
          if((SERDES_MODE == "DDRX1") & (INPUT_DATA_PIPE == 1)) begin
            PH1P_LOGIC_HR_ISERDES #(
                .IDDRMODE   ("DDRX1_PIPE")
            ) ddr_for_input_data (
                .sclk       (sclk),
                .pclk       (pclk),
                .rst        (rst),
                .idata      (data_in_from_pins_delay[inout_width]),
                .odata      (data_in_to_device[DATA_RATE * inout_width+:DATA_RATE])
            );
          end
          else begin
            PH1P_LOGIC_HR_ISERDES #(
                .IDDRMODE   (SERDES_MODE)
            ) ddr_for_input_data (
                .sclk       (sclk),
                .pclk       (pclk),
                .rst        (rst),
                .idata      (data_in_from_pins_delay[inout_width]),
                .odata      (data_in_to_device[DATA_RATE * inout_width+:DATA_RATE])
            );
          end
        end
        else begin
          if((SERDES_MODE == "DDRX1") & (INPUT_DATA_PIPE == 1)) begin
            PH1P_LOGIC_HR_ISERDES #(
                .IDDRMODE   ("DDRX1_PIPE")
            ) ddr_for_input_data (
                .sclk       (sclk),
                .pclk       (pclk),
                .rst        (rst),
                .idata      (data_in_from_pins_predelay[inout_width]),
                .odata      (data_in_to_device[DATA_RATE * inout_width+:DATA_RATE])
            );
          end
          else begin
            PH1P_LOGIC_HR_ISERDES #(
                .IDDRMODE   (SERDES_MODE)
            ) ddr_for_input_data (
                .sclk       (sclk),
                .pclk       (pclk),
                .rst        (rst),
                .idata      (data_in_from_pins_predelay[inout_width]),
                .odata      (data_in_to_device[DATA_RATE * inout_width+:DATA_RATE])
            );
          end
        end

        if (ODELAY == 1) begin
          PH1P_LOGIC_HR_OSERDES #(
              .ODDRMODE   (SERDES_MODE)
          )ddr_for_output_data(
              .sclk       (sclk),
              .pclk       (pclk),
              .rst        (rst),
              .idata      (data_out_from_device[DATA_RATE * inout_width+:DATA_RATE]),
              .odata      (data_out_to_pins_predelay[inout_width])
          );
          PH1P_LOGIC_DYNAMIC_HR_ODELAY #(
          .DEVICE("PH1P35")
          )odelay_for_output_control(
              .i         (data_out_to_pins_predelay[inout_width]),
              .dly       (out_dly[inout_width*8+:8]),
              .o         (data_out_to_pins_delay[inout_width])
          );
        end
        else
          PH1P_LOGIC_HR_OSERDES #(
              .ODDRMODE   (SERDES_MODE)
          )ddr_for_output_data(
              .sclk       (sclk),
              .pclk       (pclk),
              .rst        (rst),
              .idata      (data_out_from_device[DATA_RATE * inout_width+:DATA_RATE]),
              .odata      (data_out_to_pins_delay[inout_width])
          );      
      end
      assign data_in_to_device_p = 'b0;
      assign data_in_to_device_n = 'b0;
      assign data_out_to_pins = 'b0;
    end
    default : ;
    endcase
  end
  endgenerate
// HDIO
  generate if((IO_TYPE == "HDIO") & (DATA_DIRECTION == "BIDIRECTIONAL")) begin
    case(1)
    (SERDES_MODE == "DDRX1") : begin:data_hdio_inout_ddr
      for (inout_width = 0 ;inout_width < IO_WIDTH ; inout_width = inout_width + 1) begin:inout_control
        PH1P_LOGIC_IOTRIBUF single_iob(
            .i          (data_out_to_pins_delay[inout_width]),
            .t          (tristate_ctr),
            .o          (data_in_from_pins_predelay[inout_width]),
            .io         (data_from_and_to_pins[inout_width])
        );

        if (IDELAY == 1) begin
          PH1P_LOGIC_DYNAMIC_HD_IDELAY idelay_for_input_control(
              .i         (data_in_from_pins_predelay[inout_width]),
              .dly       (in_dly[inout_width*5+:5]),
              .o         (data_in_from_pins_delay[inout_width])
          );
          PH1P_LOGIC_HD_IDDR #(
            .ASYNCRST ("ENABLE"),
            .MODE     (IDDR_MODE)
          )iddr_for_input_data(
            .clk  (pclk),
            .rst  (rst),
            .d    (data_in_from_pins_delay[inout_width]),
            .q1   (data_in_to_device[2 * inout_width + 1]),
            .q0   (data_in_to_device[2 * inout_width])
          );
        end
        else
          PH1P_LOGIC_HD_IDDR #(
            .ASYNCRST ("ENABLE"),
            .MODE     (IDDR_MODE)
          )iddr_for_input_data(
            .clk  (pclk),
            .rst  (rst),
            .d    (data_in_from_pins_predelay[inout_width]),
            .q1   (data_in_to_device[2 * inout_width + 1]),
            .q0   (data_in_to_device[2 * inout_width])
          );
        
        if (ODELAY == 1) begin
          PH1P_LOGIC_HD_ODDR #(
            .ASYNCRST ("ENABLE")
          )oddr_for_output_data(
            .clk  (pclk),
            .rst  (rst),
            .q    (data_out_to_pins_predelay[inout_width]),
            .d1   (data_out_from_device[2 * inout_width + 1]),
            .d0   (data_out_from_device[2 * inout_width])
          );
          PH1P_LOGIC_DYNAMIC_HD_ODELAY odelay_for_output_control(
              .i         (data_out_to_pins_predelay[inout_width]),
              .dly       (out_dly[inout_width*5+:5]),
              .o         (data_out_to_pins_delay[inout_width])
          );
        end
        else
          PH1P_LOGIC_HD_ODDR #(
            .ASYNCRST ("ENABLE")
          )oddr_for_output_data(
            .clk  (pclk),
            .rst  (rst),
            .q    (data_out_to_pins_delay[inout_width]),
            .d1   (data_out_from_device[2 * inout_width + 1]),
            .d0   (data_out_from_device[2 * inout_width])
          );
      end
      assign data_out_to_pins = 'b0;
      assign data_in_to_device_p = 'b0;
      assign data_in_to_device_n = 'b0;
    end
    (SERDES_MODE == "BYPASS") : begin:data_hdio_inout_bypass
      for (inout_width = 0 ;inout_width < IO_WIDTH ; inout_width = inout_width + 1) begin:inout_control
        PH1P_LOGIC_IOTRIBUF single_iob(
            .i          (data_out_to_pins_delay[inout_width]),
            .t          (tristate_ctr),
            .o          (data_in_from_pins_predelay[inout_width]),
            .io         (data_from_and_to_pins[inout_width])
        );

        if (IDELAY == 1) begin
          PH1P_LOGIC_DYNAMIC_HD_IDELAY idelay_for_input_control(
              .i         (data_in_from_pins_predelay[inout_width]),
              .dly       (in_dly[inout_width*5+:5]),
              .o         (data_in_from_pins_delay[inout_width])
          );
          assign data_in_to_device[inout_width] = data_in_from_pins_delay[inout_width];
        end
        else
          assign data_in_to_device[inout_width] = data_in_from_pins_predelay[inout_width];
        
        if (ODELAY == 1) begin
          assign data_out_to_pins_predelay[inout_width] = data_out_from_device[inout_width];
          PH1P_LOGIC_DYNAMIC_HD_ODELAY odelay_for_output_control(
              .i         (data_out_to_pins_predelay[inout_width]),
              .dly       (out_dly[inout_width*5+:5]),
              .o         (data_out_to_pins_delay[inout_width])
          );
        end
        else
          assign data_out_to_pins_delay[inout_width] = data_out_from_device[inout_width];
      end
      assign data_out_to_pins = 'b0;
      assign data_in_to_device_p = 'b0;
      assign data_in_to_device_n = 'b0;
    end
    (SERDES_MODE == "SDR") : begin:data_hdio_inout_sdr
      for (inout_width = 0 ;inout_width < IO_WIDTH ; inout_width = inout_width + 1) begin:inout_control
        PH1P_LOGIC_IOTRIBUF single_iob(
            .i          (data_out_to_pins_delay[inout_width]),
            .t          (tristate_ctr),
            .o          (data_in_from_pins_predelay[inout_width]),
            .io         (data_from_and_to_pins[inout_width])
        );

        if (IDELAY == 1) begin
          PH1P_LOGIC_DYNAMIC_HD_IDELAY idelay_for_input_control(
              .i         (data_in_from_pins_predelay[inout_width]),
              .dly       (in_dly[inout_width*5+:5]),
              .o         (data_in_from_pins_delay[inout_width])
          );
          always@(posedge pclk or posedge rst)  begin
            if(rst) begin
                data_in_to_device_reg[inout_width] <= 0;
            end
            else begin
                data_in_to_device_reg[inout_width] <= data_in_from_pins_delay[inout_width];
            end
          end
          assign data_in_to_device[inout_width] = data_in_to_device_reg[inout_width];
        end
        else begin
          always@(posedge pclk or posedge rst)  begin
            if(rst)
                data_in_to_device_reg[inout_width] <= 0;
            else
                data_in_to_device_reg[inout_width] <= data_in_from_pins_predelay[inout_width];
          end
          assign data_in_to_device[inout_width] = data_in_to_device_reg[inout_width];
        end

        if (ODELAY == 1) begin
          always@(posedge pclk or posedge rst)  begin
            if(rst)
                data_out_to_pins_predelay_reg[inout_width] <= 0;
            else
                data_out_to_pins_predelay_reg[inout_width] <= data_out_from_device[inout_width];
          end
          assign data_out_to_pins_predelay[inout_width] = data_out_to_pins_predelay_reg[inout_width];

          PH1P_LOGIC_DYNAMIC_HD_ODELAY odelay_for_output_control(
              .i         (data_out_to_pins_predelay[inout_width]),
              .dly       (out_dly[inout_width*5+:5]),
              .o         (data_out_to_pins_delay[inout_width])
          );
        end
        else begin
          always@(posedge pclk or posedge rst)  begin
            if(rst)
                data_out_to_pins_predelay_reg[inout_width] <= 0;
            else
                data_out_to_pins_predelay_reg[inout_width] <= data_out_from_device[inout_width];
          end
          assign data_out_to_pins_delay[inout_width] = data_out_to_pins_predelay_reg[inout_width];
        end
      end
      assign data_out_to_pins = 'b0;
      assign data_in_to_device_p = 'b0;
      assign data_in_to_device_n = 'b0;
    end
    default : ;
    endcase
  end
  endgenerate
 
endmodule

