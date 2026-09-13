`timescale 1ns / 1ps

module integral_image #(
    parameter IMG_WIDTH  = 170,        
    parameter IMG_HEIGHT = 100         
)(
    input  wire        I_clk,          
    input  wire        I_rst_n,        
    
    input  wire        I_tvalid,       
    input  wire        I_tuser,        
    input  wire        I_tlast,        
    input  wire [7:0]  I_grey_tdata,   
    input  wire [7:0]  I_x,            
    input  wire [7:0]  I_y,            
    
    output reg         O_tvalid,       
    output reg         O_tuser,        
    output reg         O_tlast,        
    output reg  [23:0] O_integral,     
    output reg  [7:0]  O_x,            
    output reg  [7:0]  O_y             
);

    // 1. 行累加和与上一行整行积分值 RAM
    reg  [15:0] row_sum; 
    reg  [23:0] prev_row_integral [0:IMG_WIDTH-1];

    // 水平方向累加
    wire [15:0] current_row_sum = (I_x == 8'd0) ? {8'd0, I_grey_tdata} : (row_sum + I_grey_tdata);

    // 二维积分核心公式: II(x,y) = II(x, y-1) + sum(I(0..x, y))
    wire [23:0] current_integral = (I_y == 8'd0) ? {8'd0, current_row_sum} : 
                                                   (prev_row_integral[I_x] + current_row_sum);

    // 2. 流水线计算
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            row_sum      <= 16'd0;
            O_tvalid     <= 1'b0;
            O_tuser      <= 1'b0;
            O_tlast      <= 1'b0;
            O_integral   <= 24'd0;
            O_x          <= 8'd0;
            O_y          <= 8'd0;
        end else if (I_tuser) begin
            row_sum  <= 16'd0;
            O_tvalid <= 1'b0;
        end else if (I_tvalid) begin
            if (I_tlast || I_x == IMG_WIDTH - 1) begin
                row_sum <= 16'd0;
            end else begin
                row_sum <= current_row_sum;
            end

            prev_row_integral[I_x] <= current_integral;

            O_tvalid    <= 1'b1;
            O_tuser     <= I_tuser;
            O_tlast     <= I_tlast;
            O_integral  <= current_integral;
            O_x         <= I_x;
            O_y         <= I_y;
        end else begin
            O_tvalid <= 1'b0;
        end
    end

endmodule