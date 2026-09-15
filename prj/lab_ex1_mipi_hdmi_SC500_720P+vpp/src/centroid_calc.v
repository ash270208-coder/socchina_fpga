module centroid_calc #(
    parameter IMG_WIDTH  = 1024,
    parameter IMG_HEIGHT = 600,
    parameter MIN_AREA   = 2000  // 最小有效人脸像素面积，低于该值视作未检测到人脸
)(
    input               I_clk,
    input               I_rst_n,
    
    
    input               I_tvalid,
    input               I_tlast,
    input               I_tuser,
    input               I_skin_mask,
    
    output reg  [11:0]  O_face_x,
    output reg  [11:0]  O_face_y,
    output reg          O_face_valid
);
    reg [11:0] x_cnt, y_cnt;
    reg [31:0] sum_x, sum_y;
    reg [23:0] area_cnt;
    

    // 像素行/列坐标计数器
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            x_cnt <= 12'd0;
            y_cnt <= 12'd0;
        end else if (I_tvalid) begin
            if (I_tuser) begin
                // 遇到帧起始标记，强行同步复位为第 (0,0) 点的下一个点 (1,0)
                x_cnt <= 12'd1;
                y_cnt <= 12'd0;
            end else if (I_tlast) begin
                // 行末换行
                x_cnt <= 12'd0;
                y_cnt <= y_cnt + 1'b1;
            end else begin
                x_cnt <= x_cnt + 1'b1;
            end
        end
    end

    // 肤色区域像素累加
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            sum_x    <= 32'd0;
            sum_y    <= 32'd0;
            area_cnt <= 24'd0;
        end else if (I_tvalid) begin
            if (I_tuser) begin
                // 帧头重置累加器，并记录 (0,0) 第一个像素
                sum_x    <= 32'd0;
                sum_y    <= 32'd0;
                area_cnt <= I_skin_mask ? 24'd1 : 24'd0;
            end else if (I_skin_mask) begin
                sum_x    <= sum_x + x_cnt;
                sum_y    <= sum_y + y_cnt;
                area_cnt <= area_cnt + 1'b1;
            end
        end
    end

    // 帧尾计算形心 (利用消隐期除法)
    wire frame_done = I_tvalid && I_tlast && (y_cnt == IMG_HEIGHT - 1);
    reg  frame_done_d;
    
    reg div_start;
    // 触发除法计算：在 frame_done 时拉高 1 拍 valid
	always @(posedge I_clk or negedge I_rst_n) begin
	    if (!I_rst_n) begin
	        div_start <= 1'b0;
            frame_done_d <= 1'b0;
        end
	    else begin
            frame_done_d <= frame_done;
	        div_start <= frame_done_d && (area_cnt >= MIN_AREA);
        end
	end
    
    wire        div_x_out_valid;
    wire [55:0] div_x_dout; // 位宽以生成后的 IP 端口为准
    
    
    Divider_x u_div_x (
    	.aclk                    (I_clk),
    	.s_axis_dividend_tvalid  (div_start),
    	.s_axis_dividend_tdata   (sum_x),           // 32 位被除数
    	.s_axis_divisor_tvalid   (div_start),
    	.s_axis_divisor_tdata    (area_cnt),         // 24 位除数
    	.m_axis_dout_tvalid      (div_x_out_valid),  // 结果有效信号
    	.m_axis_dout_tdata       (div_x_dout)        // 商与余数输出
    );


    wire        div_y_out_valid;
    wire [55:0] div_y_dout;

	Divider_y u_div_y (
	    .aclk                    (I_clk),
	    .s_axis_dividend_tvalid  (div_start),
	    .s_axis_dividend_tdata   (sum_y),           // 32 位被除数
	    .s_axis_divisor_tvalid   (div_start),
	    .s_axis_divisor_tdata    (area_cnt),         // 24 位除数
	    .m_axis_dout_tvalid      (div_y_out_valid),
	    .m_axis_dout_tdata       (div_y_dout)
	);

    always @(posedge I_clk or negedge I_rst_n) begin
    	if (!I_rst_n) begin
    	    O_face_x     <= IMG_WIDTH / 2;
    	    O_face_y     <= IMG_HEIGHT / 2;
    	    O_face_valid <= 1'b0;
    	end else if (div_x_out_valid) begin
    	    O_face_x     <= div_x_dout[11:0]; // 截取商的低 12 位，既是因为要与O_face_x位宽对齐，同时也是由于商的结果一定是小于1023的，12位足够
    	    O_face_y     <= div_y_dout[11:0];
    	    O_face_valid <= 1'b1;
    	end else if (frame_done && (area_cnt < MIN_AREA)) begin
    	    O_face_valid <= 1'b0;             // 面积不足，无有效目标
    	end
    end
    
endmodule