`timescale 1ns / 1ps

module lbp_detector_engine #(
    parameter IMG_WIDTH  = 170,   
    parameter IMG_HEIGHT = 100,   
    parameter WIN_SIZE   = 24    
)(
    input  wire        I_clk,          
    input  wire        I_rst_n,        
    
    // 来自积分图模块的数据流
    input  wire        I_tvalid,       
    input  wire        I_tuser,        
    input  wire [23:0] I_integral,     
    input  wire [7:0]  I_x,            
    input  wire [7:0]  I_y,            
    
    // 检测结果输出
    output reg         O_face_valid,   
    output reg  [7:0]  O_face_x,       
    output reg  [7:0]  O_face_y,       
    output reg  [7:0]  O_face_w,       
    output reg  [7:0]  O_face_h        
);

    
    // 1. 全图积分 BRAM
    
    wire [14:0] ram_wr_addr = (I_y << 7) + (I_y << 5) + (I_y << 3) + (I_y << 1) + I_x;
    
    reg  [14:0] ram_rd_addr;
    wire [17:0] ram_rd_data;

    frame_integral_bram u_integral_bram (
        // 端口 A: 写端口
        .clka   (I_clk),
        .cea    (1'b1),                // 时钟使能常开
        .addra  (ram_wr_addr),         // 15 位写地址: I_y * 170 + I_x
        .dia    (I_integral[17:0]),    // 18 位写入数据
        
        // 端口 B: 读端口
        .ceb    (1'b1),                // 读使能常开
        .addrb  (ram_rd_addr),         // 15 位读地址
        .dob    (ram_rd_data)          // 18 位读出数据直接接流水线
    );

    // 窗口对齐门禁
    wire win_valid = I_tvalid && (I_x >= WIN_SIZE - 1) && (I_y >= WIN_SIZE - 1);

    // =========================================================================
    // 2. ROM 资源
    // =========================================================================
    reg  [7:0]  weak_idx;
    wire [295:0] curr_weak_raw;
    
    wire [7:0]         curr_feat_id = curr_weak_raw[295:288];
    wire signed [15:0] curr_leaf0   = curr_weak_raw[287:272];
    wire signed [15:0] curr_leaf1   = curr_weak_raw[271:256];
    wire [255:0]       curr_bitmask = curr_weak_raw[255:0];

    rom_weak_lut u_rom_lut (
        .clka  (I_clk),
        .addra (weak_idx),         
        .doa   (curr_weak_raw)     
    );

    wire [31:0] curr_rect_raw;
    rom_feature_rects u_rom_rect (
        .clka  (I_clk),
        .addra (curr_feat_id),     
        .doa   (curr_rect_raw)     
    );

    reg  [4:0]  stage_idx;
    wire signed [15:0] curr_stage_thresh;
    rom_stage_thresh u_rom_thresh (
        .clka  (I_clk),
        .addra (stage_idx),        
        .doa   (curr_stage_thresh) 
    );

    // =========================================================================
    // 3. 【无 MUX 纯地址采样逻辑】
    // =========================================================================
    wire [4:0] fx = curr_rect_raw[31:24];
    wire [4:0] fy = curr_rect_raw[23:16];
    wire [4:0] fw = curr_rect_raw[15:8];
    wire [4:0] fh = curr_rect_raw[7:0];

    // 候选窗口左上角基准坐标 (静态锁存)
    reg [7:0] win_top_x, win_top_y;

    wire [7:0] abs_y0 = win_top_y + fy;
    wire [7:0] abs_y1 = win_top_y + fy + fh;
    wire [7:0] abs_y2 = win_top_y + fy + 2*fh;
    wire [7:0] abs_y3 = win_top_y + fy + 3*fh;

    wire [7:0] abs_x0 = win_top_x + fx;
    wire [7:0] abs_x1 = win_top_x + fx + fw;
    wire [7:0] abs_x2 = win_top_x + fx + 2*fw;
    wire [7:0] abs_x3 = win_top_x + fx + 3*fw;

    reg [4:0] fetch_step;
    reg [7:0] cur_sample_x, cur_sample_y;

    always @(*) begin
        case (fetch_step)
            // Row 0
            5'd0:  begin cur_sample_y = abs_y0; cur_sample_x = abs_x0; end
            5'd1:  begin cur_sample_y = abs_y0; cur_sample_x = abs_x1; end
            5'd2:  begin cur_sample_y = abs_y0; cur_sample_x = abs_x2; end
            5'd3:  begin cur_sample_y = abs_y0; cur_sample_x = abs_x3; end
            // Row 1
            5'd4:  begin cur_sample_y = abs_y1; cur_sample_x = abs_x0; end
            5'd5:  begin cur_sample_y = abs_y1; cur_sample_x = abs_x1; end
            5'd6:  begin cur_sample_y = abs_y1; cur_sample_x = abs_x2; end
            5'd7:  begin cur_sample_y = abs_y1; cur_sample_x = abs_x3; end
            // Row 2
            5'd8:  begin cur_sample_y = abs_y2; cur_sample_x = abs_x0; end
            5'd9:  begin cur_sample_y = abs_y2; cur_sample_x = abs_x1; end
            5'd10: begin cur_sample_y = abs_y2; cur_sample_x = abs_x2; end
            5'd11: begin cur_sample_y = abs_y2; cur_sample_x = abs_x3; end
            // Row 3
            5'd12: begin cur_sample_y = abs_y3; cur_sample_x = abs_x0; end
            5'd13: begin cur_sample_y = abs_y3; cur_sample_x = abs_x1; end
            5'd14: begin cur_sample_y = abs_y3; cur_sample_x = abs_x2; end
            5'd15: begin cur_sample_y = abs_y3; cur_sample_x = abs_x3; end
            default: begin cur_sample_y = 8'd0; cur_sample_x = 8'd0; end
        endcase
    end

    // 生成 BRAM 读地址
    always @(*) begin
        ram_rd_addr = (cur_sample_y << 7) + (cur_sample_y << 5) + (cur_sample_y << 3) + (cur_sample_y << 1) + cur_sample_x;
    end

    // 16 拍打拍锁存 16 个顶点数据 (严格匹配 BRAM 1 拍读延迟)
    reg [17:0] p00, p01, p02, p03;
    reg [17:0] p10, p11, p12, p13;
    reg [17:0] p20, p21, p22, p23;
    reg [17:0] p30, p31, p32, p33;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            p00 <= 18'd0; p01 <= 18'd0; p02 <= 18'd0; p03 <= 18'd0;
            p10 <= 18'd0; p11 <= 18'd0; p12 <= 18'd0; p13 <= 18'd0;
            p20 <= 18'd0; p21 <= 18'd0; p22 <= 18'd0; p23 <= 18'd0;
            p30 <= 18'd0; p31 <= 18'd0; p32 <= 18'd0; p33 <= 18'd0;
        end else begin
            case (fetch_step)
                5'd1:  p00 <= ram_rd_data;
                5'd2:  p01 <= ram_rd_data;
                5'd3:  p02 <= ram_rd_data;
                5'd4:  p03 <= ram_rd_data;
                5'd5:  p10 <= ram_rd_data;
                5'd6:  p11 <= ram_rd_data;
                5'd7:  p12 <= ram_rd_data;
                5'd8:  p13 <= ram_rd_data;
                5'd9:  p20 <= ram_rd_data;
                5'd10: p21 <= ram_rd_data;
                5'd11: p22 <= ram_rd_data;
                5'd12: p23 <= ram_rd_data;
                5'd13: p30 <= ram_rd_data;
                5'd14: p31 <= ram_rd_data;
                5'd15: p32 <= ram_rd_data;
                5'd16: p33 <= ram_rd_data;
            endcase
        end
    end

    // 18 位模加减法
    wire [17:0] s0 = p11 - p01 - p10 + p00;
    wire [17:0] s1 = p12 - p02 - p11 + p01;
    wire [17:0] s2 = p13 - p03 - p12 + p02;
    wire [17:0] s3 = p23 - p13 - p22 + p12;
    wire [17:0] s4 = p22 - p12 - p21 + p11; // Center 块
    wire [17:0] s5 = p32 - p22 - p31 + p21;
    wire [17:0] s6 = p31 - p21 - p30 + p20;
    wire [17:0] s7 = p21 - p11 - p20 + p10;
    wire [17:0] s8 = p33 - p23 - p32 + p22;

    wire [7:0] calc_lbp_code = {
        (s7 >= s4), (s6 >= s4), (s5 >= s4), (s8 >= s4),
        (s3 >= s4), (s2 >= s4), (s1 >= s4), (s0 >= s4)
    };

    wire hit_bit = curr_bitmask[calc_lbp_code];
    wire signed [15:0] curr_score = hit_bit ? curr_leaf0 : curr_leaf1;

    // =========================================================================
    // 4. Stage 结束索引函数
    // =========================================================================
    function [7:0] get_stage_end_idx;
        input [4:0] s;
        case(s)
            5'd0:  get_stage_end_idx = 8'd2;   
            5'd1:  get_stage_end_idx = 8'd6;   
            5'd2:  get_stage_end_idx = 8'd12;  
            5'd3:  get_stage_end_idx = 8'd19;  
            5'd4:  get_stage_end_idx = 8'd26;  
            5'd5:  get_stage_end_idx = 8'd34;  
            5'd6:  get_stage_end_idx = 8'd43;  
            5'd7:  get_stage_end_idx = 8'd52;  
            5'd8:  get_stage_end_idx = 8'd61;  
            5'd9:  get_stage_end_idx = 8'd70;  
            5'd10: get_stage_end_idx = 8'd78;  
            5'd11: get_stage_end_idx = 8'd86;  
            5'd12: get_stage_end_idx = 8'd93;  
            5'd13: get_stage_end_idx = 8'd100; 
            5'd14: get_stage_end_idx = 8'd107; 
            5'd15: get_stage_end_idx = 8'd113; 
            5'd16: get_stage_end_idx = 8'd119; 
            5'd17: get_stage_end_idx = 8'd125; 
            5'd18: get_stage_end_idx = 8'd131; 
            5'd19: get_stage_end_idx = 8'd138; 
            default: get_stage_end_idx = 8'd138;
        endcase
    endfunction

    // =========================================================================
    // 5. 级联决策状态机 (加入 S_WAIT_ROM 彻底解决 2 拍级联延迟)
    // =========================================================================
    localparam S_IDLE        = 3'd0;
    localparam S_WAIT_ROM    = 3'd1; //  等待 2 拍让级联 ROM 读出正确的矩形参数
    localparam S_FETCH_PTS   = 3'd2;
    localparam S_EVAL_WEAK   = 3'd3;
    localparam S_CHECK_STAGE = 3'd4;

    reg [2:0] state;
    reg [1:0] rom_wait_cnt;
    reg signed [19:0] stage_score;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            state        <= S_IDLE;
            stage_idx    <= 5'd0;
            weak_idx     <= 8'd0;
            stage_score  <= 20'sd0;
            fetch_step   <= 5'd0;
            rom_wait_cnt <= 2'd0;
            win_top_x    <= 8'd0;
            win_top_y    <= 8'd0;
            O_face_valid <= 1'b0;
            O_face_x     <= 8'd0;
            O_face_y     <= 8'd0;
            O_face_w     <= 8'd24;
            O_face_h     <= 8'd24;
            
        end else begin
            case (state)
                S_IDLE: begin
                    O_face_valid <= 1'b0;
                    if (win_valid) begin
                        win_top_x    <= I_x - 8'd23;
                        win_top_y    <= I_y - 8'd23;
                        stage_idx    <= 5'd0;
                        weak_idx     <= 8'd0;
                        stage_score  <= 20'sd0;
                        rom_wait_cnt <= 2'd0;
                        state        <= S_WAIT_ROM; // 先去等 ROM 出数据
                    end
                end

                //  等待两拍让 u_rom_lut 和 u_rom_rect 级联输出正确的 fx, fy, fw, fh
                S_WAIT_ROM: begin
                    if (rom_wait_cnt == 2'd1) begin
                        rom_wait_cnt <= 2'd0;
                        fetch_step   <= 5'd0;
                        state        <= S_FETCH_PTS;
                    end else begin
                        rom_wait_cnt <= rom_wait_cnt + 1'b1;
                    end
                end

                // 16 步顺序读出当前弱分类器的 16 个特征点
                S_FETCH_PTS: begin
                    if (fetch_step == 5'd16) begin
                        fetch_step <= 5'd0;
                        state      <= S_EVAL_WEAK;
                    end else begin
                        fetch_step <= fetch_step + 1'b1;
                    end
                end

                // 评估当前弱分类器得分并累加
                S_EVAL_WEAK: begin
                    stage_score <= stage_score + curr_score;
                    state       <= S_CHECK_STAGE;
                end

                // 关卡门槛判断与提前剪枝
                S_CHECK_STAGE: begin
                    if (weak_idx == get_stage_end_idx(stage_idx)) begin
                        if (stage_score >= curr_stage_thresh) begin
                            if (stage_idx == 5'd19) begin
                                // 闯过全部 20 关，输出人脸包围盒！
                                O_face_valid <= 1'b1;
                                O_face_x     <= win_top_x;
                                O_face_y     <= win_top_y;
                                O_face_w     <= 8'd24;
                                O_face_h     <= 8'd24;
                                state        <= S_IDLE;
                            end else begin
                                // 晋级下一个 Stage
                                stage_idx    <= stage_idx + 1'b1;
                                weak_idx     <= weak_idx + 1'b1;
                                stage_score  <= 20'sd0;
                                rom_wait_cnt <= 2'd0;
                                state        <= S_WAIT_ROM; // 等新 Stage 的第一个矩形数据就绪
                            end
                        end else begin
                            state <= S_IDLE; // 未及格淘汰
                        end
                    end else begin
                        // 当前 Stage 内部继续下一个弱分类器
                        weak_idx     <= weak_idx + 1'b1;
                        rom_wait_cnt <= 2'd0;
                        state        <= S_WAIT_ROM; // 等下一个弱分类器的矩形数据就绪
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule