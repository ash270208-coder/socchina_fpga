`timescale 1ns/1ps

module histogram_equ#(
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720
)
(
    input               I_clk,          // axi4s_video_aclk
    input               I_rst_n,
    
    input               I_tlast,        // 行结束信号
    input               I_tuser,        // 帧开始信号
    input      [7:0]    I_grey_tdata,   // 输入灰度数据
    input               I_tvalid,       // 数据有效信号
    
    output              O_tlast,
    output              O_tuser,
    output     [7:0]    O_grey_tdata,   // 均衡化后的灰度数据
    output              O_tvalid
);
     
    localparam TOTAL_PIXELS = IMG_WIDTH * IMG_HEIGHT;
    localparam MAX_GREY     = 256;
    localparam SHIFT_AMT    = 32;
    localparam MULT_FACTOR  = (64'd1 << SHIFT_AMT) / TOTAL_PIXELS;

    // =========================================================================
    // 1. 像素统计流水线与 RAW 冲突前推 (Port A: 写, Port B: 读)
    // =========================================================================
    reg [7:0]   grey_d1, grey_d2;
    reg         valid_d1, valid_d2;
    reg [19:0]  his_wr_data_r;
    wire [19:0] ram_his_rd_data;
    wire [19:0] his_wr_data;
    
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            grey_d1  <= 8'd0;
            grey_d2  <= 8'd0;
            valid_d1 <= 1'b0;
            valid_d2 <= 1'b0;
        end else begin
            grey_d1  <= I_grey_tdata;
            grey_d2  <= grey_d1;
            valid_d1 <= I_tvalid;
            valid_d2 <= valid_d1;
        end
    end

    // RAW 旁路前推：连续相同灰度时直接累加上一拍结果
    wire raw_hazard = (grey_d1 == grey_d2) && valid_d1 && valid_d2;
    assign his_wr_data = raw_hazard ? (his_wr_data_r + 20'd1) : (ram_his_rd_data + 20'd1);

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            his_wr_data_r <= 20'd0;
        else if(valid_d1)
            his_wr_data_r <= his_wr_data;
    end

    // =========================================================================
    // 2. 帧结束检测 (基于 AXI-Stream 行列计数器)
    // =========================================================================
    reg [11:0] line_cnt;
    
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            line_cnt <= 12'd0;
        else if(I_tuser && I_tvalid)
            line_cnt <= 12'd1;
        else if(I_tvalid && I_tlast)
            line_cnt <= line_cnt + 12'd1;
    end

    wire frame_end = (line_cnt == IMG_HEIGHT) && I_tlast && I_tvalid;

    // =========================================================================
    // 3. 状态机 (包含复位自清零 S_INIT_CLEAR)
    // =========================================================================
    localparam S_INIT_CLEAR = 3'd0; // 复位后先把 RAM 刷成纯 0
    localparam S_IDLE       = 3'd1; // 等待图像数据并统计
    localparam S_READ       = 3'd2; // 消隐期读直方图做累加
    localparam S_WAIT       = 3'd3; // 缓冲 1 拍
    localparam S_CLEAR      = 3'd4; // 帧间清零
    localparam S_DONE       = 3'd5; // 等待下一帧

    reg [2:0] state;
    reg [7:0] addr_cnt;

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            state    <= S_INIT_CLEAR; // 复位后必须先清零！
            addr_cnt <= 8'd0;
        end else begin
            case(state)
                S_INIT_CLEAR: begin
                    if(addr_cnt == 8'd255) begin
                        state    <= S_IDLE;
                        addr_cnt <= 8'd0;
                    end else begin
                        addr_cnt <= addr_cnt + 8'd1;
                    end
                end

                S_IDLE: begin
                    addr_cnt <= 8'd0;
                    if(frame_end)
                        state <= S_READ;
                end

                S_READ: begin
                    if(addr_cnt == 8'd255) begin
                        state    <= S_WAIT;
                        addr_cnt <= 8'd0;
                    end else begin
                        addr_cnt <= addr_cnt + 8'd1;
                    end
                end

                S_WAIT: begin
                    state    <= S_CLEAR;
                    addr_cnt <= 8'd0;
                end

                S_CLEAR: begin
                    if(addr_cnt == 8'd255) begin
                        state    <= S_DONE;
                        addr_cnt <= 8'd0;
                    end else begin
                        addr_cnt <= addr_cnt + 8'd1;
                    end
                end

                S_DONE: begin
                    if(I_tuser && I_tvalid)
                        state <= S_IDLE;
                end
                
                default: state <= S_INIT_CLEAR;
            endcase
        end
    end

    // =========================================================================
    // 4. 直方图统计 RAM 多路复用与例化 (ram_2port)
    // =========================================================================
    wire is_clearing = (state == S_INIT_CLEAR) || (state == S_CLEAR);

    wire [7:0]  ram_his_addra = is_clearing ? addr_cnt : grey_d1;
    wire [19:0] ram_his_dia   = is_clearing ? 20'd0 : his_wr_data;
    wire        ram_his_wea   = is_clearing ? 1'b1 : valid_d1;
    wire        ram_his_cea   = is_clearing ? 1'b1 : valid_d1;

    wire [7:0]  ram_his_addrb = (state == S_READ) ? addr_cnt : I_grey_tdata;
    wire        ram_his_ceb   = (state == S_READ) ? 1'b1 : I_tvalid;

    ram_2port u_ram_his (
        .clka   (I_clk),
        .cea    (ram_his_cea),
        .wea    (ram_his_wea),
        .addra  (ram_his_addra),
        .dia    (ram_his_dia),
        .doa    (),

        .clkb   (I_clk),
        .ceb    (ram_his_ceb),
        .web    (1'b0),
        .addrb  (ram_his_addrb),
        .dib    (20'd0),
        .dob    (ram_his_rd_data)
    );

    // =========================================================================
    // 5. 累计直方图 (CDF) 计算与例化 (ram_accumulate)
    // =========================================================================
    reg        ram_accu_wr;
    reg [7:0]  ram_accu_wraddr;
    reg [19:0] his_sum;

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            ram_accu_wr     <= 1'b0;
            ram_accu_wraddr <= 8'd0;
        end else begin
            ram_accu_wr     <= (state == S_READ);
            ram_accu_wraddr <= ram_his_addrb;
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            his_sum <= 20'd0;
        else if(state == S_IDLE || state == S_INIT_CLEAR)
            his_sum <= 20'd0;
        else if(ram_accu_wr)
            his_sum <= his_sum + ram_his_rd_data;
    end

    wire [19:0] ram_accu_wrdata = his_sum + ram_his_rd_data;
    wire [19:0] ram_accu_rddata;

    ram_accumulate u_ram_accumulate (
        .clka   (I_clk),
        .cea    (ram_accu_wr),
        .addra  (ram_accu_wraddr),
        .dia    (ram_accu_wrdata),

        .clkb   (I_clk),
        .ceb    (I_tvalid),
        .addrb  (I_grey_tdata),
        .dob    (ram_accu_rddata)
    );

    // =========================================================================
    // 6. 映射归一化计算流水线 (严格防截断)
    // =========================================================================
    reg [27:0] data_mult;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            data_mult <= 28'd0;
        else
            data_mult <= ram_accu_rddata * (MAX_GREY - 1);
    end

    // 显式 64 位防截断
    wire [63:0] mult_result = ({36'd0, data_mult}) * ({32'd0, MULT_FACTOR});
    wire [63:0] mult_round  = mult_result + (64'd1 << (SHIFT_AMT - 1)); 
    reg  [7:0]  data_div;
    
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            data_div <= 8'd0;
        else
            data_div <= mult_round[SHIFT_AMT + 7 : SHIFT_AMT];
    end

    // 控制信号打 3 拍对齐
    reg [2:0] I_tlast_r;
    reg [2:0] I_tuser_r;
    reg [2:0] I_tvalid_r;

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            I_tlast_r  <= 3'd0;
            I_tuser_r  <= 3'd0;
            I_tvalid_r <= 3'd0;
        end else begin
            I_tlast_r  <= {I_tlast_r[1:0],  I_tlast};
            I_tuser_r  <= {I_tuser_r[1:0],  I_tuser};
            I_tvalid_r <= {I_tvalid_r[1:0], I_tvalid};
        end
    end

    assign O_tlast      = I_tlast_r[2];
    assign O_tuser      = I_tuser_r[2];
    assign O_tvalid     = I_tvalid_r[2];
    assign O_grey_tdata = data_div;

endmodule