
module integral_line_buffer_25 (
    input  wire        I_clk,
    input  wire        I_rst_n,
    
    
    input  wire        I_tvalid,       
    input  wire        I_tuser,        
    input  wire [23:0] I_integral,     
    input  wire        I_skin_mask,    
    input  wire [7:0]  I_x,            
    input  wire [7:0]  I_y,            
    
    // 输出给 LBP 级联决策状态机
    output reg         O_win_valid,    // 窗口数据填满有效 (X>=23 且 Y>=23)
    output reg  [7:0]  O_win_x,        // 当前窗口右下角 X 坐标
    output reg  [7:0]  O_win_y,        // 当前窗口右下角 Y 坐标
    output reg  [9:0]  O_skin_count    
);

    
    wire [24:0] pack_data_in = {I_skin_mask, I_integral};

    // 声明 25 根纵向并行数据线
    wire [24:0] line [0:24];
    
    // 第 0 行就是当前实时进来的这一行
    assign line[0] = pack_data_in;

    
    // line[0] 进水管1 -> 吐出 line[1]
    // line[1] 进水管2 -> 吐出 line[2] ... 直到 line[24]
    genvar i;
    generate
        for (i = 0; i < 24; i = i + 1) begin : pipe_cascade
            line_fifo #(
                .DATA_WIDTH (25),
                .LINE_LEN   (170)
            ) u_line_fifo (
                .I_clk   (I_clk),
                .I_rst_n (I_rst_n),
                .wr_en (I_tvalid),
                .din   (line[i]),     // 输入上一级
                .dout  (line[i+1])    // 输出给下一级
            );
        end
    endgenerate

    
    // 3. 构建 25x25 移位二维阵列 (横向推移)
    
    // 二维寄存器: win_int[行][列]
    reg [23:0] win_int  [0:24][0:24]; // 25x25 积分图矩阵
    reg        win_skin [0:23][0:23]; // 24x24 肤色点阵

    integer r, c;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            // 复位清零
            for (r = 0; r < 25; r = r + 1)
                for (c = 0; c < 25; c = c + 1)
                    win_int[r][c] <= 24'd0;
            for (r = 0; r < 24; r = r + 1)
                for (c = 0; c < 24; c = c + 1)
                    win_skin[r][c] <= 1'b0;
        end else if (I_tvalid) begin
            // 每来一个点，25 行数据全部向右挪动一格 (第 0 列吃进最新线的数据)
            for (r = 0; r < 25; r = r + 1) begin
                for (c = 0; c < 24; c = c + 1) begin
                    win_int[r][c] <= win_int[r][c+1]; // 其余列向左推
                end
                win_int[r][24] <= line[24 - r][23:0]; // 与屏幕顺序相同，屏幕左上像素位于屏幕左上角
            end
            
            // 肤色点阵同理向右推
            for (r = 0; r < 24; r = r + 1) begin
                for (c = 0; c < 23; c = c + 1) begin
                    win_skin[r][c] <= win_skin[r][c+1];
                end
                win_skin[r][23] <= line[23 - r][24]; // 与屏幕顺序相同，屏幕左上像素位于屏幕左上角
            end
        end
    end

    // -------------------------------------------------------------
    // 4. 统计 24x24 空间里有多少个皮肤点
    // -------------------------------------------------------------
    reg [9:0] skin_sum;
    integer sr, sc;
    always @(*) begin
        skin_sum = 10'd0;
        for (sr = 0; sr < 24; sr = sr + 1) begin
            for (sc = 0; sc < 24; sc = sc + 1) begin
                skin_sum = skin_sum + win_skin[sr][sc];
            end
        end
    end

    
    // 5. 窗口有效标志输出 (防画面边缘越界)
    
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_win_valid  <= 1'b0;
            O_win_x      <= 8'd0;
            O_win_y      <= 8'd0;
            O_skin_count <= 10'd0;
        end else if (I_tuser) begin
            O_win_valid  <= 1'b0;
        end else if (I_tvalid) begin
            // 只有当坐标跑过 23 行 23 列之后，24x24 方块才完全填满,
            //即使填满也会出现新进入的一列比剩下的列要快，比如在扫到最右边时剩下的列起始在十行，
            //新进入的列从第十一行开始的，所以需要再次跑过23行23列才能使得窗口数据行对齐
            if ((I_x >= 8'd23) && (I_y >= 8'd23)) begin
                O_win_valid  <= 1'b1;
                O_win_x      <= I_x;
                O_win_y      <= I_y;
                O_skin_count <= skin_sum;
            end else begin
                O_win_valid  <= 1'b0;
            end
        end else begin
            O_win_valid <= 1'b0;
        end
    end

endmodule
