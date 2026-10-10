`timescale 1ns / 1ps
//******************************************************************** 
// -------------------------------------------------------------------
// >>>>>>>>>>>>>>>>>>>>>>>Copyright Notice<<<<<<<<<<<<<<<<<<<<<<<<<<<< 
// ------------------------------------------------------------------- 
//             /\ --------------- 
//            /  \ ------------- 
//           / /\ \ -----------
//          / /  \ \ ---------
//         / /    \ \ ------- 
//        / /      \ \ ----- 
//       / /_ _ _   \ \ --- 
//      /_ _ _ _ _\  \_\ -
//********************************************************************
// Author: suluyang 
// Email:luyang.su@anlogic.com 
// Date:2020/10/16 
// Description: 
// 1.0:Date:2020/10/16 通用ODDR模块建立，支持PH1器件和EG4器件
// web：www.anlogic.com 
//-------------------------------------------------------------------- 
//*******************************************************************/
module ODDR (
        q,
        clk,
        d1,
        d0,
        rst
);
output           q;
input            clk;
input            d1;
input            d0;
input            rst;
parameter ASYNCRST      = "ENABLE";     //ENABLE, DISABLE
parameter DEVICE 		= "PH1P";//"PH1P" "PH1" "EG4" "PH1A400"

generate 
if(DEVICE == "EG4")
begin
	EG_LOGIC_ODDR#(
		.ASYNCRST(ASYNCRST)
	) 
	u_oddr
	(
		.q	(q	),
		.clk(clk),
		.d1	(d1	),
		.d0	(d0	),
		.rst(rst)
	);	
end
else if(DEVICE == "PH1P")
begin
	// HX1P35A 的 RGMII 引脚位于 HDIO；HDIO 必须使用对应的 HD DDR 原语。
	PH1P_LOGIC_HD_ODDR#(
		.ASYNCRST(ASYNCRST)
	) 
	u_oddr
	(
		.q	(q	),
		.clk(clk),
		.d1	(d1	),
		.d0	(d0	),
		.rst(rst)
	);		
end
else if(DEVICE == "PH1" || DEVICE == "PH1A400" )
begin
	PH1_LOGIC_ODDR#(
		.ASYNCRST(ASYNCRST)
	) 
	u_oddr
	(
		.q	(q	),
		.clk(clk),
		.d1	(d1	),
		.d0	(d0	),
		.rst(rst)
	);		
end
endgenerate

endmodule
