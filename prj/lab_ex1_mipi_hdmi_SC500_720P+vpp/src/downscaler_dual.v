`timescale 1ns / 1ps

module downscaler #(
    parameter SCALE_FACTOR = 6,        // 降采样倍率
    parameter OUT_WIDTH    = 170,      // 输出低分辨率宽
    parameter OUT_HEIGHT   = 100       // 输出低分辨率高
)(
    input  wire        I_clk,          
    input  wire        I_rst_n,        
    
    // 输入原始高清灰度流
    input  wire        I_tvalid,
    input  wire        I_tuser,        
    input  wire        I_tlast,        
    input  wire [7:0]  I_grey_tdata,   
    
    // 降采样后的数据流
    output reg         O_tvalid,       
    output reg         O_tuser,        
    output reg         O_tlast,        
    output reg  [7:0]  O_grey_tdata,   
    output reg  [7:0]  O_x,            // 低分辨率 X 坐标 (0 ~ 169)
    output reg  [7:0]  O_y             // 低分辨率 Y 坐标 (0 ~ 99)
);

    // 1. 步进抽样计数器
    reg [2:0] sub_x;    // 0 ~ 5 计数
    reg [2:0] sub_y;    // 0 ~ 5 计数
    reg [7:0] low_x;    // 0 ~ 169
    reg [7:0] low_y;    // 0 ~ 99

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            sub_x <= 3'd0;
            sub_y <= 3'd0;
            low_x <= 8'd0;
            low_y <= 8'd0;
        end else if (I_tuser) begin
            sub_x <= 3'd0;
            sub_y <= 3'd0;
            low_x <= 8'd0;
            low_y <= 8'd0;
        end else if (I_tvalid) begin
            if (I_tlast) begin
                sub_x <= 3'd0;
                low_x <= 8'd0;
                if (sub_y == SCALE_FACTOR - 1) begin
                    sub_y <= 3'd0;
                    low_y <= (low_y == OUT_HEIGHT - 1) ? 8'd0 : low_y + 1'b1;
                end else begin
                    sub_y <= sub_y + 1'b1;
                end
            end else begin
                if (sub_x == SCALE_FACTOR - 1) begin
                    sub_x <= 3'd0;
                    low_x <= low_x + 1'b1;
                end else begin
                    sub_x <= sub_x + 1'b1;
                end
            end
        end
    end

    // 2. 抽样输出与信号对齐
    wire sample_pulse = I_tvalid && (sub_x == 3'd0) && (sub_y == 3'd0) && (low_x < OUT_WIDTH) && (low_y < OUT_HEIGHT);

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_tvalid     <= 1'b0;
            O_tuser      <= 1'b0;
            O_tlast      <= 1'b0;
            O_grey_tdata <= 8'd0;
            O_x          <= 8'd0;
            O_y          <= 8'd0;
        end else if (I_tuser) begin
            O_tvalid     <= 1'b0;
            O_tuser      <= 1'b0;
            O_tlast      <= 1'b0;
        end else if (sample_pulse) begin
            O_tvalid     <= 1'b1;
            O_tuser      <= (low_x == 8'd0 && low_y == 8'd0) ? 1'b1 : 1'b0;
            O_tlast      <= (low_x == OUT_WIDTH - 1) ? 1'b1 : 1'b0;
            O_grey_tdata <= I_grey_tdata;
            O_x          <= low_x;
            O_y          <= low_y;
        end else begin
            O_tvalid     <= 1'b0;
            O_tuser      <= 1'b0;
            O_tlast      <= 1'b0;
        end
    end

endmodule