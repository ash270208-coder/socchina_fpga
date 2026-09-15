module RGB888_YCbCr444#(
    parameter IMG_WIDTH  = 1024,
    parameter IMG_HEIGHT = 600
)(
    input               I_clk,
    input               I_rst_n,
    
    input               I_tlast,
    input               I_tuser,
    input      [7:0]    I_red_tdata,
    input      [7:0]    I_green_tdata,
    input      [7:0]    I_blue_tdata,
    input               I_tvalid,
    input               I_tready,
    
    output reg          O_tlast,
    output reg          O_tuser,
    output reg [7:0]    O_y_tdata,
    output reg [7:0]    O_cb_tdata,
    output reg [7:0]    O_cr_tdata,
    output reg          O_tvalid,
    output              O_tready
);


//Y = 0.2126R + 0.7152G + 0.0722B 
//Cb = -0.1146R - 0.3854G + 0.5B + 128 
//Cr = 0.5R - 0.4542G - 0.0458B + 128
//避免浮点运算，采用

//Y &= (54R + 183G + 18B) >> 8 
//Cb &= (-29R -99G +128B +32768)>>8 
//Cr &= (128R -116G -12B +32768)>>8

 // ready 反压信号透传
    assign O_tready = I_tready;

    // -------------------------------------------------------------------------
    // 流水线控制信号打拍寄存器（3 拍延迟对齐）,因为计算结果并输出需要总共三拍
    // -------------------------------------------------------------------------
    reg [1:0] tvalid_dly;
    reg [1:0] tlast_dly;
    reg [1:0] tuser_dly;

    // -------------------------------------------------------------------------
    // Pipeline Stage 1: 并行乘法运算 (8bit x 8bit = 16bit)
    // -------------------------------------------------------------------------
    // Y 分量乘积
    reg [15:0] mult_y_r;
    reg [15:0] mult_y_g;
    reg [15:0] mult_y_b;
    
    // Cb 分量乘积
    reg [15:0] mult_cb_r;
    reg [15:0] mult_cb_g;
    reg [15:0] mult_cb_b;
    
    // Cr 分量乘积
    reg [15:0] mult_cr_r;
    reg [15:0] mult_cr_g;
    reg [15:0] mult_cr_b;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            mult_y_r  <= 16'd0; mult_y_g  <= 16'd0; mult_y_b  <= 16'd0;
            mult_cb_r <= 16'd0; mult_cb_g <= 16'd0; mult_cb_b <= 16'd0;
            mult_cr_r <= 16'd0; mult_cr_g <= 16'd0; mult_cr_b <= 16'd0;
        end else if (I_tvalid && I_tready) begin
            // Y 乘积 (77, 150, 29)
            mult_y_r  <= I_red_tdata   * 8'd77;
            mult_y_g  <= I_green_tdata * 8'd150;
            mult_y_b  <= I_blue_tdata  * 8'd29;
            
            // Cb 乘积 (43, 85, 128)
            mult_cb_r <= I_red_tdata   * 8'd43;
            mult_cb_g <= I_green_tdata * 8'd85;
            mult_cb_b <= I_blue_tdata  * 8'd128;
            
            // Cr 乘积 (128, 107, 21)
            mult_cr_r <= I_red_tdata   * 8'd128;
            mult_cr_g <= I_green_tdata * 8'd107;
            mult_cr_b <= I_blue_tdata  * 8'd21;
        end
    end

    // -------------------------------------------------------------------------
    // Pipeline Stage 2: 累加与偏置求和 (18-bit 宽，防止溢出)
    // -------------------------------------------------------------------------
    reg [17:0] sum_y;
    reg [17:0] sum_cb;
    reg [17:0] sum_cr;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            sum_y  <= 18'd0;
            sum_cb <= 18'd0;
            sum_cr <= 18'd0;
        end else if (tvalid_dly[0]) begin
            // Y  = R*77 + G*150 + B*29
            sum_y  <= mult_y_r + mult_y_g + mult_y_b;
            
            // Cb = B*128 - R*43 - G*85 + 32768 (32768 = 128 << 8)
            // 先加正数再减负数，保证在无符号数范围内运算不会产生负下溢
            sum_cb <= mult_cb_b + 18'd32768 - mult_cb_r - mult_cb_g;
            
            // Cr = R*128 - G*107 - B*21 + 32768
            sum_cr <= mult_cr_r + 18'd32768 - mult_cr_g - mult_cr_b;
        end
    end

    // -------------------------------------------------------------------------
    // Pipeline Stage 3: 右移 8 位 (取 [15:8]) 输出最终 8-bit Y, Cb, Cr
    // -------------------------------------------------------------------------
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_y_tdata  <= 8'd0;
            O_cb_tdata <= 8'd0;
            O_cr_tdata <= 8'd0;
        end else if (tvalid_dly[1]) begin
            O_y_tdata  <= sum_y[15:8];
            O_cb_tdata <= sum_cb[15:8];
            O_cr_tdata <= sum_cr[15:8];
        end
    end

    // 控制信号打 2 拍，加上输出寄存器正好 3 拍对齐：

	always @(posedge I_clk or negedge I_rst_n) begin
	    if (!I_rst_n) begin
	        tvalid_dly <= 2'b0;
	        tlast_dly  <= 2'b0;
	        tuser_dly  <= 2'b0;
	        O_tvalid   <= 1'b0;
	        O_tlast    <= 1'b0;
	        O_tuser    <= 1'b0;
	    end else begin
	        tvalid_dly <= {tvalid_dly[0], (I_tvalid && I_tready)};
	        tlast_dly  <= {tlast_dly[0],  I_tlast};
	        tuser_dly  <= {tuser_dly[0],  I_tuser};
	
	        O_tvalid   <= tvalid_dly[1];
	        O_tlast    <= tlast_dly[1];
	        O_tuser    <= tuser_dly[1];
	    end
	end
endmodule   


