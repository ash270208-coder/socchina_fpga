
`timescale 1 ns / 1 ps

module rom_0a2b16d92680 (
	
	doa, 
	addra, 
	
	clka 
	
);

	parameter DATA_WIDTH_A = 8;
	parameter ADDR_WIDTH_A = 4;
	parameter DATA_DEPTH_A = 16;
	parameter DATA_WIDTH_B = DATA_WIDTH_A;
	parameter ADDR_WIDTH_B = ADDR_WIDTH_A;
	parameter DATA_DEPTH_B = DATA_DEPTH_A;
	parameter INIT_FILE    ="NONE";
	parameter FILL_ALL     ="NONE";

	output [DATA_WIDTH_A-1:0] doa;
	input  [ADDR_WIDTH_A-1:0] addra;
	input  clka;
	
	PH1P_LOGIC_ERAM #( 
	
		.DATA_WIDTH_A(DATA_WIDTH_A),
		.ADDR_WIDTH_A(ADDR_WIDTH_A),
		.DATA_DEPTH_A(DATA_DEPTH_A),
		.DATA_WIDTH_B(DATA_WIDTH_B),
		.ADDR_WIDTH_B(ADDR_WIDTH_B),
		.DATA_DEPTH_B(DATA_DEPTH_B),
		
		.MODE("SP"),
		 
		.REGMODE_A("NOREG"),
		
		.IMPLEMENT("20K"),
		
		.DEBUGGABLE("NO"),
		
		.PACKABLE("NO"),
		
		.INIT_FILE(INIT_FILE),
		.FILL_ALL(FILL_ALL)
	) username_inst (
		
		.dia({DATA_WIDTH_A{1'b0}}),
		.dib({DATA_WIDTH_B{1'b0}}),
		.addra(addra),
		.addrb({ADDR_WIDTH_B{1'b0}}),
		.cea(1'b1),
		.ceb(1'b0),
		
		.ocea(1'b0),
		
		.oceb(1'b0),
		.clka(clka),
		.clkb(1'b0),
		.wea(1'b0),
		.web(1'b0),
		.bea(1'b0),
		.beb(1'b0),
		
		.rsta(1'b0),
		
		.rstb(1'b0),
		.doa(doa),
		.dob()
		
	);

endmodule
