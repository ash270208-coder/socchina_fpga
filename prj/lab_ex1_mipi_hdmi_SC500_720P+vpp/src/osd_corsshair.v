`timescale 1ns / 1ps

module osd_crosshair #(
    parameter IMG_WIDTH   = 1024,
    parameter IMG_HEIGHT  = 600,
    parameter CROSS_LEN   = 15,                 // 准星单臂长度 (像素)
    parameter CROSS_COLOR = 24'h00_FF_00        // 准星颜色: 亮绿色 (RGB888)
)(
    input               I_clk,
    input               I_rst_n,
    
    // AXI4-Stream 原始彩色视频流输入
    input               I_tvalid,
    input               I_tlast,
    input               I_tuser,
    input      [23:0]   I_rgb,
    
    // 来自形心计算模块的目标坐标
    input      [11:0]   I_target_x,
    input      [11:0]   I_target_y,
    input               I_target_valid,
    
    // AXI4-Stream 叠加准星后的视频流输出 (打 1 拍严格对齐)
    output reg          O_tvalid,
    output reg          O_tlast,
    output reg          O_tuser,
    output reg [23:0]   O_rgb
);

    // =========================================================================
    // 1. 像素扫描坐标计数器
    // =========================================================================
    reg [11:0] x_cnt;
    reg [11:0] y_cnt;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            x_cnt <= 12'd0;
            y_cnt <= 12'd0;
        end else if (I_tvalid) begin
            if (I_tuser) begin
                x_cnt <= 12'd1;
                y_cnt <= 12'd0;
            end else if (I_tlast) begin
                x_cnt <= 12'd0;
                y_cnt <= y_cnt + 1'b1;
            end else begin
                x_cnt <= x_cnt + 1'b1;
            end
        end
    end

    // 当前输入像素对应的真实坐标
    wire [11:0] cur_x = I_tuser ? 12'd0 : x_cnt;
    wire [11:0] cur_y = y_cnt;

    // =========================================================================
    // 2. 十字准星几何判定 (带边界防溢出保护)
    // =========================================================================
    wire [11:0] x_min = (I_target_x >= CROSS_LEN) ? (I_target_x - CROSS_LEN) : 12'd0;
    wire [11:0] x_max = (I_target_x + CROSS_LEN < IMG_WIDTH) ? (I_target_x + CROSS_LEN) : (IMG_WIDTH - 1);
    wire [11:0] y_min = (I_target_y >= CROSS_LEN) ? (I_target_y - CROSS_LEN) : 12'd0;
    wire [11:0] y_max = (I_target_y + CROSS_LEN < IMG_HEIGHT) ? (I_target_y + CROSS_LEN) : (IMG_HEIGHT - 1);

    // 水平横线判定: y 与目标一致，x 在区间内
    wire is_h_bar = (cur_y == I_target_y) && (cur_x >= x_min) && (cur_x <= x_max);
    // 垂直竖线判定: x 与目标一致，y 在区间内
    wire is_v_bar = (cur_x == I_target_x) && (cur_y >= y_min) && (cur_y <= y_max);

    // 综合判定
    wire is_cross = I_target_valid && (is_h_bar || is_v_bar);

    // =========================================================================
    // 3. 输出流水线打拍 (严格同步控制信号与数据)
    // =========================================================================
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_tvalid <= 1'b0;
            O_tlast  <= 1'b0;
            O_tuser  <= 1'b0;
            O_rgb    <= 24'd0;
        end else begin
            O_tvalid <= I_tvalid;
            O_tlast  <= I_tlast;
            O_tuser  <= I_tuser;

            if (I_tvalid) begin
                if (is_cross)
                    O_rgb <= CROSS_COLOR; // 落在准星位置：绘制绿色
                else
                    O_rgb <= I_rgb;       // 其余像素：透传原图
            end
        end
    end

endmodule