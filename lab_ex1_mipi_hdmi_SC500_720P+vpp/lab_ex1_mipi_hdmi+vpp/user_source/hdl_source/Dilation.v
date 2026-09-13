module Bit_Dilation_Detector#(
    parameter IMG_WIDTH       = 1280,
    parameter IMG_HEIGHT      = 720
)(
    input               I_clk,
    input               I_rst_n,
    
    input               I_tlast,
    input               I_tuser,
    input               I_per_img_Bit,
    input               I_tvalid,
    
    output  	        O_tlast,
    output  	        O_tuser,
    output  	        O_per_img_Bit,
    output  	        O_tvalid
);


    // =========================================================================
    // 1. 行列坐标计数器
    // =========================================================================
    reg [11:0] col_cnt;
    reg [11:0] row_cnt;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            col_cnt <= 12'd0;
            row_cnt <= 12'd0;
        end
        else if (I_tvalid) begin
            if (I_tuser) begin
                col_cnt <= 12'd1;
                row_cnt <= 12'd0;
            end
            else if (I_tlast || (col_cnt == IMG_WIDTH - 1)) begin
                col_cnt <= 12'd0;
                if (row_cnt == IMG_HEIGHT - 1)
                    row_cnt <= 12'd0;
                else
                    row_cnt <= row_cnt + 1'b1;
            end
            else begin
                col_cnt <= col_cnt + 1'b1;
            end
        end
    end
    
    // =========================================================================
    // 2. 双行缓存（加入仿真 initial 清零，彻底消除 xxxxxx 不定态）
    // =========================================================================
    (* ram_style = "block" *) reg  line_buf0 [0:IMG_WIDTH-1];
    (* ram_style = "block" *) reg  line_buf1 [0:IMG_WIDTH-1];

    //仿真用，防止出现x态
    integer init_i;
    initial begin
        for (init_i = 0; init_i < IMG_WIDTH; init_i = init_i + 1) begin
            line_buf0[init_i] = 1'd0;
            line_buf1[init_i] = 1'd0;
        end
    end
    
    reg  row0_data; // 第 y-2 行
    reg  row1_data; // 第 y-1 行
    reg  row2_data; // 第 y   行 (当前行)

    always @(posedge I_clk) begin
        if (I_tvalid) begin
            // 完美对齐读取：在同一时钟下读出第 col_cnt 列的历史数据
            row0_data <= line_buf0[col_cnt];
            row1_data <= line_buf1[col_cnt];
            row2_data <= I_per_img_Bit;

            // 级联无位移写入：老数据逐行下移
            line_buf0[col_cnt] <= line_buf1[col_cnt];
            line_buf1[col_cnt] <= I_per_img_Bit;
        end
    end
    
    
    // =========================================================================
    // 3. 构建 3x3 滑动窗口矩阵
    // =========================================================================
    reg  p11, p12, p13;
    reg  p21, p22, p23;
    reg  p31, p32, p33;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            p11 <= 1'd0; p12 <= 1'd0; p13 <= 1'd0;
            p21 <= 1'd0; p22 <= 1'd0; p23 <= 1'd0;
            p31 <= 1'd0; p32 <= 1'd0; p33 <= 1'd0;
        end
        else if (I_tvalid) begin
            p11 <= p12; p12 <= p13; p13 <= row0_data;
            p21 <= p22; p22 <= p23; p23 <= row1_data;
            p31 <= p32; p32 <= p33; p33 <= row2_data;
        end
    end
    
    //PIXEL
    //P11   P12     P13
    //P21   P22     P23
    //P31   P32     P33
    //采用3x3矩阵进行卷积
    //Dilation Step 1
    reg O_img_Bit1,O_img_Bit2,O_img_Bit3;
    
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_img_Bit1<=1'b0;
            O_img_Bit2<=1'b0;
            O_img_Bit3<=1'b0;
        end
        else begin
            if(I_tvalid) begin
                O_img_Bit1<=p11|p12|p13;
                O_img_Bit2<=p21|p22|p23;
                O_img_Bit3<=p31|p32|p33;
            end
        end
    end
    
    ////Dilation Step 2
    reg O_img_Bit4;
    
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            O_img_Bit4<=0;
        else if(I_tvalid)
            O_img_Bit4<=O_img_Bit1|O_img_Bit2|O_img_Bit3;
    end
    
    assign O_per_img_Bit=O_img_Bit4;
    
    
    
    // 控制信号 4 拍对齐逻辑 (精准 4 拍延迟)
    
    reg [3:0] tvalid_shift;
    reg [3:0] tlast_shift;
    reg [3:0] tuser_shift;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            tvalid_shift <= 4'd0;
            tlast_shift  <= 4'd0;
            tuser_shift  <= 4'd0;
        end
        else begin
            
            tvalid_shift <= {tvalid_shift[2:0], I_tvalid};

            
            if (I_tvalid) begin
                tlast_shift <= {tlast_shift[2:0], I_tlast};
                tuser_shift <= {tuser_shift[2:0], I_tuser};
            end
        end
    end

    
    assign O_tvalid = tvalid_shift[3];
    assign O_tlast  = tlast_shift[3];
    assign O_tuser  = tuser_shift[3];
    
endmodule

