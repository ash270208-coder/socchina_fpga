`timescale 1ns / 1ns
//发生了重大改动
module uii2c#
(
parameter integer WMEN_LEN = 8'd0,//写长度，以字节为单位
parameter integer RMEN_LEN = 8'd0,//读长度，以字节为单位
parameter integer CLK_DIV  = 16'd499// I2C时钟分频系数
)
(
input  wire I_clk,//系统时钟输入
input  wire I_rstn,//系统复位，低电平有效
output reg  O_iic_scl = 1'b0,//I2C时钟SCL
inout  wire IO_iic_sda,//I2C 数据总线
input  wire [WMEN_LEN*8-1'b1:0]I_wr_data,//写数据寄存器
input  wire [7:0]I_wr_cnt,//写数据计数器
output reg  [RMEN_LEN*8-1'b1:0]O_rd_data = 0,//读数据寄存器
input  wire [7:0]I_rd_cnt,//读数据计数器
input  wire I_iic_req,//I_iic_req == 1 使能I2C传输
input  wire I_iic_mode,//I_iic_mode = 1 读模式   I_iic_mode = 0 读当前寄存器或者页读
output reg  O_iic_busy = 1'b0,//I2C控制器忙
output reg  O_iic_bus_error = 1'b0, //I2C总线无ACK应答错误
output reg  IO_iic_sda_dg
);

localparam IDLE    = 4'd0;
localparam START   = 4'd1;
localparam W_WAIT  = 4'd2;
localparam W_ACK   = 4'd3;
localparam R_WAIT  = 4'd4;
localparam R_ACK   = 4'd5;
localparam STOP1   = 4'd6;
localparam STOP2   = 4'd7;   

localparam SCL_DIV = CLK_DIV/2;
localparam OFFSET  = SCL_DIV - SCL_DIV/4;

reg [2:0] IIC_S = 4'd0; 
reg [15:0] clkdiv = 16'd0;   
reg scl_r 	   = 1'b1;       
reg sda_o 	   = 1'b0;       
reg scl_clk    = 1'b0;       
reg scl_posedge = 1'b0; // scl 上升沿单周期使能脉冲
reg scl_negedge = 1'b0; // scl 下降沿单周期使能脉冲

reg [7:0] sda_r = 8'd0;      
reg [7:0] sda_i_r = 8'd0;    
reg [7:0] wcnt = 8'd0;       
reg [7:0] rcnt = 8'd0;       
reg [2:0] bcnt = 3'd0;       
reg  rd_req = 1'b0;          
wire sda_i;                  
wire scl_offset;             

assign sda_i = IO_iic_sda;  
assign IO_iic_sda = (sda_o == 1'b0) ?  1'b0 : 1'bz;

// 1. 统一在 I_clk 下产生 scl 时钟及边沿脉冲
always @(posedge I_clk or negedge I_rstn) begin
    if (!I_rstn) begin
        clkdiv      <= 16'd0;
        scl_clk     <= 1'b0;
        scl_posedge <= 1'b0;
        scl_negedge <= 1'b0;
    end else begin
        if (clkdiv < SCL_DIV) begin
            clkdiv      <= clkdiv + 1'b1;
            scl_posedge <= 1'b0;
            scl_negedge <= 1'b0;
        end else begin
            clkdiv      <= 16'd0;
            scl_clk     <= ~scl_clk;
            scl_posedge <= ~scl_clk; // 0变1时产生1拍使能
            scl_negedge <= scl_clk;  // 1变0时产生1拍使能
        end
    end
end

assign scl_offset = (clkdiv == OFFSET);

always @(posedge I_clk or negedge I_rstn) begin
    if (!I_rstn)
        O_iic_scl <= 1'b1;
    else
        O_iic_scl <= scl_offset ? scl_r : O_iic_scl;
end

always @(posedge I_clk) IO_iic_sda_dg <= sda_i;  

always @(*) begin
    if(IIC_S == IDLE || IIC_S == STOP1 || IIC_S == STOP2)
        scl_r = 1'b1;
    else 
        scl_r = scl_clk;
end

always @(*) begin
    if(IIC_S == START || IIC_S == STOP1 || (IIC_S == R_ACK && (rcnt != I_rd_cnt)))
        sda_o = 1'b0;
    else if(IIC_S == W_WAIT)
        sda_o = sda_r[7]; 
    else  
        sda_o = 1'b1; 
end

// 2. 发送移位寄存器（改在 I_clk 下通过 scl_posedge 触发）
always @(posedge I_clk or negedge I_rstn) begin
    if (!I_rstn) begin
        sda_r <= 8'd0;
    end else if (scl_posedge) begin
        if (IIC_S == W_ACK || IIC_S == START) begin
            sda_r <= I_wr_data[(wcnt*8) +: 8];
            if (rd_req) sda_r <= {I_wr_data[7:1], 1'b1};
        end else if (IIC_S == W_WAIT) begin
            sda_r <= {sda_r[6:0], 1'b1};
        end
    end
end

// 3. 接收移位寄存器（改在 I_clk 下通过 scl_negedge 触发）
always @(posedge I_clk or negedge I_rstn) begin
    if (!I_rstn) begin
        sda_i_r   <= 8'd0;
        O_rd_data <= 'd0;
    end else if (scl_negedge) begin
        if (IIC_S == R_WAIT)
            sda_i_r <= {sda_i_r[6:0], sda_i};
        else if (IIC_S == R_ACK)
            O_rd_data[((rcnt-1'b1)*8) +: 8] <= sda_i_r[7:0];
        else if (IIC_S == IDLE)
            sda_i_r <= 8'd0;
    end
end

// 4. 忙状态标志（改在 I_clk 下触发）
always @(posedge I_clk or negedge I_rstn) begin
    if (!I_rstn) begin
        O_iic_busy <= 1'b0; 
    end else begin
        if (I_iic_req == 1'b1 || rd_req == 1'b1 || O_iic_bus_error)
            O_iic_busy <= 1'b1; 
        else if (scl_posedge && (IIC_S == IDLE))
            O_iic_busy <= 1'b0;
    end 		
end

// 5. 总线错误标志（改在 I_clk 下触发）
always @(posedge I_clk or negedge I_rstn) begin
    if (!I_rstn) begin
        O_iic_bus_error <= 1'b0;  	
    end else begin
        if (scl_negedge && (IIC_S == W_ACK) && (sda_i == 1'b1))
            O_iic_bus_error <= 1'b1; 
        else if (I_iic_req == 1'b0)
            O_iic_bus_error <= 1'b0;
    end 		
end

// 6. I2C 主状态机（改在 I_clk 下通过 scl_posedge 触发）
always @(posedge I_clk or negedge I_rstn) begin
    if (!I_rstn) begin
        wcnt   <= 8'd0;
        rcnt   <= 8'd0;
        rd_req <= 1'b0;   
        IIC_S  <= IDLE;
        bcnt   <= 3'd0;
    end else if (scl_posedge) begin
        case(IIC_S)
            IDLE: begin
                if (I_iic_req == 1'b1 || rd_req == 1'b1)
                    IIC_S <= START;
                else begin
                    wcnt <= 8'd0;
                    rcnt <= 8'd0;
                end
            end
            START: begin
                bcnt  <= 3'd7;        
                IIC_S <= W_WAIT;
            end           
            W_WAIT: begin
                if (bcnt > 3'd0)
                    bcnt <= bcnt - 1'b1;
                else begin
                    wcnt  <= wcnt + 1'b1;
                    IIC_S <= W_ACK;
                end
            end 
            W_ACK: begin 
                if (wcnt < I_wr_cnt) begin
                    bcnt  <= 3'd7;
                    IIC_S <= W_WAIT;
                end else if (I_rd_cnt > 3'd0) begin
                    if (rd_req == 1'b0 && I_iic_mode == 1'b1) begin
                        rd_req <= 1'b1;
                        IIC_S  <= IDLE;
                    end else begin
                        IIC_S <= R_WAIT;
                        bcnt  <= 3'd7;
                    end
                end else begin
                    IIC_S <= STOP1; 
                end
            end  
            R_WAIT: begin
                rd_req <= 1'b0;
                bcnt   <= bcnt - 1'b1;
                if (bcnt == 3'd0) begin
                    rcnt  <= (rcnt < I_rd_cnt) ? (rcnt + 1'b1) : rcnt;
                    IIC_S <= R_ACK;
                end
            end
            R_ACK: begin
                bcnt  <= 3'd7;
                IIC_S <= (rcnt < I_rd_cnt) ? R_WAIT : STOP1;
            end  
            STOP1: begin
                rd_req <= 1'b0;              
                IIC_S  <= STOP2;
            end
            STOP2: begin
                IIC_S <= IDLE;          
            end
            default: begin
                IIC_S <= IDLE;
            end
        endcase
    end
end

endmodule