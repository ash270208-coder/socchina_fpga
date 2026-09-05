


//   1. 接收来自降采样模块的 8-bit 灰度流 (170x100)
//   2. 纯流水线实时计算 2D 积分图 (24-bit 宽)
//   3. 伴随传递 1-bit 肤色掩码和坐标，保持全流水线绝对同拍

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
    input  wire        I_skin_mask,    
    input  wire [7:0]  I_x,            
    input  wire [7:0]  I_y,            
    
   
    output reg         O_tvalid,       
    output reg         O_tuser,        
    output reg         O_tlast,        
    output reg  [23:0] O_integral,     
    output reg         O_skin_mask,    
    output reg  [7:0]  O_x,            
    output reg  [7:0]  O_y             
);

    
    // 1. 内部累加器与上一行积分值存储器 (RAM)
    
   
    reg [15:0] row_sum; // 行累加和: 存当前行从第 0 列到当前列的灰度总和 
    
    
    reg [23:0] prev_row_integral [0:IMG_WIDTH-1];// 存储“上一行整行积分值”的片上 RAM 

    // 计算当前点的水平累加和
    wire [15:0] current_row_sum = (I_x == 8'd0) ? {8'd0, I_grey_tdata} : (row_sum + I_grey_tdata);

    // 计算当前点的二维总积分: II(x,y) = II(x, y-1) + current_row_sum
    wire [23:0] current_integral = (I_y == 8'd0) ? {8'd0, current_row_sum} : 
                                                   (prev_row_integral[I_x] + current_row_sum);

    
    // 2. 流水线核心计算与寄存器更新
    
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            row_sum      <= 16'd0;
            O_tvalid     <= 1'b0;
            O_tuser      <= 1'b0;
            O_tlast      <= 1'b0;
            O_integral   <= 24'd0;
            O_skin_mask  <= 1'b0;
            O_x          <= 8'd0;
            O_y          <= 8'd0;
        end else if (I_tuser) begin
            // 遇到新一帧开头，清零行累加和
            row_sum  <= 16'd0;
            O_tvalid <= 1'b0;
        end else if (I_tvalid) begin
            // 1. 更新当前行的水平累加器
            if (I_tlast || I_x == IMG_WIDTH - 1) begin
                row_sum <= 16'd0; // 遇到行尾，下一行重新从 0 开始累加
            end else begin
                row_sum <= current_row_sum;
            end

            // 2. 更新 RAM：把算好的当前点积分值写入 RAM，供“下一行”的同一列使用
            prev_row_integral[I_x] <= current_integral;

            // 3. 伴随打拍输出给后级 (延迟 1 拍输出，保持时序干净)
            O_tvalid    <= 1'b1;
            O_tuser     <= I_tuser;
            O_tlast     <= I_tlast;
            O_integral  <= current_integral;
            O_skin_mask <= I_skin_mask; // 肤色信号原样同步传递
            O_x         <= I_x;
            O_y         <= I_y;
        end else begin
            O_tvalid <= 1'b0;
        end
    end

endmodule
