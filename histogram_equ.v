module histogram_equ#(
    parameter IMG_WIDTH  = 1024,
    parameter IMG_HEIGHT = 600
)
(
    input               I_clk,          //axi4s_video_aclk
    input               I_rst_n,
    
    input               I_tlast,        //行结束信号
    input               I_tuser,        //帧开始信号
    input      [7:0]    I_grey_tdata,
    input               I_tvalid,        //数据有效信号
    
    output 	            O_tlast,
    output 	            O_tuser,
    output 	   [7:0]    O_grey_tdata,
    output 	            O_tvalid
 
     );
     
     localparam TOTAL_PIXELS = IMG_WIDTH * IMG_HEIGHT; // 614400
     localparam MAX_GREY     = 256;
     //除法改为乘法＋移位用
     localparam SHIFT_AMT   = 32;
     localparam MULT_FACTOR = 32'd6990;
     
     wire [19:0] ram_his_rd_data;
     reg         ram_his_wr_en;
     reg         I_tuser_delay;
     
     reg [7:0]   ram_his_addr_b;
     reg         ram_his_rd_b;
     wire [19:0] ram_his_rd_data_b;
     
     reg         ram_his_wr_b;
     
     reg         ram_accu_wr;
     reg [7:0]   ram_accu_wraddr;
     wire [19:0]  ram_accu_wrdata;
     
     wire [19:0]  ram_accu_rddata;
     
     
     //读操作比写操作提前一个周期，所以让ram_his_wr_en延迟一个周期
	always @ (posedge I_clk, negedge I_rst_n) begin
	    if(!I_rst_n)
	        ram_his_wr_en<=1'b0;
	    else
	        ram_his_wr_en<=I_tvalid;
	end
     
     
//利用RAM来进行灰度统计，生成灰度直方图，灰度值作为地址，每统计一个出现像素，对应的灰度值作为地址，其中的数据加1

    ram_2port u_ram_2port(
    
    	//端口A，摄像头输出的灰度值数据作为RAM地址，先读出来，再加1写回
    	.clock_a    (I_clk),
    	.aclr_a     (!I_rst_n),
    	.rden_a     (I_tvalid),
    	.address_a  (I_grey_tdata),
    	.q_a        (ram_his_rd_data),
    	
    	
    	.wren_a     (ram_his_wr_en),
    	.data_a     (ram_his_rd_data+1),
        
        //端口B:一帧结束后读出RAM中的数据进行寄存，下一帧开始前将RAM初始化为0
        .clock_b    (I_clk),
    	.aclr_b     (1'b0),
    	.rden_b     (ram_his_rd_b),
    	.address_b  (ram_his_addr_b),
    	.q_b        (ram_his_rd_data_b),
    	
    	
    	.wren_b     (ram_his_wr_b),
    	.data_b     (32'd0)
        
        );
        
//        wire I_tuser_negedge;
//        wire I_tuser_posedge;
//        
//        always @ (posedge I_clk,negedge I_rst_n) begin
//            if(!I_rst_n)
//               I_tuser_delay<=1'b0;
//            else
//               I_tuser_delay<=I_tuser;
//        end
//        
//        assign I_tuser_negedge=I_tuser_delay & (!I_tuser);
//        assign I_tuser_posedge=(!I_tuser_delay) & I_tuser;
//        
//        //帧开始上升沿表示前一帧直方图统计结束，此时将RAM中数据读出，寄存到新的RAM中
//        always @ (posedge I_clk,negedge I_rst_n) begin
//            if(!I_rst_n)
//                ram_his_rd_b<=1'b0;
//            else begin
//                if(I_tuser_posedge)
//                    ram_his_rd_b<=1'b1;
//                else if(ram_his_addr_b==8'd255)
//                    ram_his_rd_b<=1'b0;
//            end
//        end
//        
//        //帧开始下降沿表示新一帧的开始，此时将RAM初始化为0
//        always @ (posedge I_clk,negedge I_rst_n) begin
//            if(!I_rst_n)
//                ram_his_wr_b<=1'b0;
//            else begin
//                if(I_tuser_negedge)
//                    ram_his_wr_b<=1'b1;
//                else if(ram_his_addr_b==8'd255)
//                    ram_his_wr_b<=1'b0;
//            end
//         end

	reg [19:0] pixel_cnt;
	wire       frame_end = (pixel_cnt == TOTAL_PIXELS); // 614400 拍结束标志
	
	always @(posedge I_clk , negedge I_rst_n) begin
	    if(!I_rst_n)
	        pixel_cnt <= 20'd0;
	    else if(I_tuser && I_tvalid)
	        pixel_cnt <= 20'd1;           // 遇到新帧重新数
	    else if(I_tvalid)
	        pixel_cnt <= pixel_cnt + 20'd1;
	end
	
	
	// 状态定义：IDLE -> 读出数据并累加(256拍) -> 写0清零(256拍) -> 完成
	localparam S_IDLE  = 2'd0;
	localparam S_READ  = 2'd1;
	localparam S_CLEAR = 2'd2;
	
	reg [1:0] state;
	reg [7:0] addr_cnt;
	
	always @(posedge I_clk , negedge I_rst_n) begin
	    if(!I_rst_n) begin
	        state          <= S_IDLE;
	        addr_cnt       <= 8'd0;
	        ram_his_rd_b   <= 1'b0;
	        ram_his_wr_b   <= 1'b0;
	        ram_his_addr_b <= 8'd0;
	    end else begin
	        case(state)
	            S_IDLE: begin
	                addr_cnt     <= 8'd0;
	                ram_his_rd_b <= 1'b0;
	                ram_his_wr_b <= 1'b0;
	                if(frame_end) begin
	                    state        <= S_READ;
	                    ram_his_rd_b <= 1'b1; // 启动读使能
	                end
	            end
	
	            // 阶段一：扫描 0~255 读出统计数据送去累加
	            S_READ: begin
	                ram_his_addr_b <= addr_cnt;
                    ram_his_rd_b   <= 1'b1;          
                    ram_his_wr_b   <= 1'b0;
	                if(addr_cnt == 8'd255) begin
	                    state        <= S_CLEAR;
	                    addr_cnt     <= 8'd0;
	                    
	                end else begin
	                    addr_cnt <= addr_cnt + 8'd1;
	                end
	            end
	
	            // 阶段二：扫描 0~255 写入 0 进行清零
	            S_CLEAR: begin
                    ram_his_rd_b <= 1'b0; // 关掉读
	                ram_his_wr_b <= 1'b1; // 开启写(清零)
	                ram_his_addr_b <= addr_cnt;
	                if(addr_cnt == 8'd255) begin
	                    state        <= S_IDLE;
	                    ram_his_wr_b <= 1'b0; // 清零完成，关闭写
	                end else begin
	                    addr_cnt <= addr_cnt + 8'd1;
	                end
	            end
                
                default:begin
                    state <= S_IDLE;
                end
	        endcase
	    end
	end
    
    
    //计算累计直方图
    
    //从前一个RAM中读出直方图统计信息，延迟一个时钟周期拉高下一个RAM的写使能
    always @(posedge I_clk , negedge I_rst_n) begin
	    if(!I_rst_n)
            ram_accu_wr<=1'b0;
        else
            ram_accu_wr<=ram_his_rd_b;
    end
    
    reg [19:0] his_sum;//累积直方图结果
    
    always @(posedge I_clk , negedge I_rst_n) begin
	    if(!I_rst_n)
            his_sum<=20'd0;
        else begin
            if(ram_his_wr_b)
                his_sum<=20'd0;
            else if(ram_accu_wr)
                his_sum<=his_sum+ram_his_rd_data_b;
        end
    end
    
    assign ram_accu_wrdata=his_sum;
    
    // 将直方图统计信息寄存到另一个RAM
    always @(posedge I_clk , negedge I_rst_n) begin
	    if(!I_rst_n)
            ram_accu_wraddr<=8'd0;
        else
            ram_accu_wraddr<=ram_his_addr_b;
    end
    
    
    //累计直方图RAM
    ram_2port_accumulate u_ram_2port_accumulate(
        .clock      (I_clk),
        .aclr       (!I_rst_n),
        .wren       (ram_accu_wr),
        .wraddress  (ram_accu_wraddr),
        .data       (ram_accu_wrdata),
        .rden       (I_tvalid),
        .rdaddress  (I_grey_tdata),
        .q          (ram_accu_rddata)
    );
    
    //直方图均衡
    reg  [27:0] data_mult;//乘法运算结果
    
    always @ (posedge I_clk,negedge I_rst_n) begin
        if(!I_rst_n)
            data_mult<=28'd0;
        else
            data_mult<=ram_accu_rddata*(MAX_GREY-1);
    end
    
    
    wire [59:0] mult_result;               
    assign mult_result = data_mult * MULT_FACTOR;
    
    reg [7:0] data_div;//除法运算结果
    //1/TOTAL_PIXELS=MULT_FACTOR/2^SHIFT_AMT
    
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            data_div<=8'd0;
        else
            data_div <= (mult_result >> SHIFT_AMT);
    end
    
    
    reg [2:0] I_tlast_r;           
    reg [2:0] I_tuser_r;       
    reg [2:0] I_tvalid_r;
    
    always @ (posedge I_clk,negedge I_rst_n) begin
        if(!I_rst_n) begin
            I_tlast_r<=0;
            I_tuser_r<=0;
            I_tvalid_r<=0;
        end
        else begin
            I_tlast_r<={I_tlast_r[1:0],I_tlast};
            I_tuser_r<={I_tuser_r[1:0],I_tuser};
            I_tvalid_r<={I_tvalid_r[1:0],I_tvalid};
        end
        
    end   
    
    assign O_tlast=I_tlast_r[2];
    assign O_tuser=I_tuser_r[2];
    assign O_tvalid=I_tvalid_r[2];
    
    assign O_grey_tdata=data_div;
    
    
    endmodule  