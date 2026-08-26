module vpp_top
#(
    parameter IMG_WIDTH  = 1024,
    parameter IMG_HEIGHT = 600
)
( 
    input          I_clk           ,
	input          I_rst_n         ,
	input          I_tlast         ,
	input          I_tuser         ,
	input  [23:0]  I_tdata         ,
	input          I_tvalid        ,
	input          I_tdest         ,
	input          I_tready        ,
	output [23:0]  O_tdata         ,
	output         O_tlast         ,
	output         O_tuser         ,
	output         O_tvalid        ,
	output         O_tready        
);

wire [7:0] red_tdata;
wire [7:0] green_tdata;
wire [7:0] blue_tdata;

assign red_tdata  =I_tdata[23:16];
assign green_tdata=I_tdata[15:8];
assign blue_tdata =I_tdata[7:0];

wire    tlast_RGBYbr_hisequ;
wire    tuser_RGBYbr_hisequ;
wire    tvalid_RGBYbr_hisequ;
wire [7:0] y_tdata;
wire [7:0] cb_tdata;
wire [7:0] cr_tdata;      

RGB888_YCbCr444 
#(
    .IMG_WIDTH (IMG_WIDTH),
    .IMG_HEIGHT(IMG_HEIGHT)
)u_RGB888_YCbCr444(
    .I_clk          (I_clk),        
	.I_rst_n        (I_rst_n),      
	              
	.I_tlast        (I_tlast),      
	.I_tuser        (I_tuser),      
	.I_red_tdata    (red_tdata),  
	.I_green_tdata  (green_tdata),
	.I_blue_tdata   (blue_tdata), 
	.I_tvalid       (I_tvalid),     
	.I_tready       (I_tready),     
	              
	.O_tlast        (tlast_RGBYbr_hisequ),      
	.O_tuser        (tuser_RGBYbr_hisequ),      
	.O_y_tdata      (y_tdata),
	.O_cb_tdata     (cb_tdata),   
	.O_cr_tdata     (cr_tdata),   
	.O_tvalid       (tvalid_RGBYbr_hisequ),
	.O_tready       ()
);

wire        tlast_hisequ;
wire        tuser_hisequ;
wire        tvalid_hisequ;
wire [7:0]  y_equ_tdata;

histogram_equ #(
    .IMG_WIDTH (IMG_WIDTH),
    .IMG_HEIGHT(IMG_HEIGHT)
)u_histogram_equ(
    .I_clk              (I_clk),       
	.I_rst_n            (I_rst_n),     
	             
	.I_tlast            (tlast_RGBYbr_hisequ),     
	.I_tuser            (tuser_RGBYbr_hisequ),     
	.I_grey_tdata       (y_tdata),
	.I_tvalid           (tvalid_RGBYbr_hisequ),    
	             
	.O_tlast            (tlast_hisequ),     
	.O_tuser            (tuser_hisequ),     
	.O_grey_tdata       (y_equ_tdata),
	.O_tvalid           (tvalid_hisequ)     
);

assign O_tdata  = {y_equ_tdata, y_equ_tdata, y_equ_tdata};
assign O_tlast  = tlast_hisequ;
assign O_tuser  = tuser_hisequ;
assign O_tvalid = tvalid_hisequ;
assign O_tready = 1'b1;   // 暂时不处理反压

endmodule
