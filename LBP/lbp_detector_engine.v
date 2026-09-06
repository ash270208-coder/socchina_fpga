`timescale 1ns / 1ps

module lbp_detector_engine #(
    parameter IMG_WIDTH  = 170,   
    parameter IMG_HEIGHT = 100,   
    parameter WIN_SIZE   = 24    
)(
    input  wire        I_clk,          
    input  wire        I_rst_n,        
    
    // 来自积分图模块的低分辨率流
    input  wire        I_tvalid,       
    input  wire        I_tuser,        
    input  wire [23:0] I_integral,     // 24-bit 积分图
    input  wire [7:0]  I_x,            // 当前点 X
    input  wire [7:0]  I_y,            // 当前点 Y
    
    // 输出给画框模块 (OSD)
    output reg         O_face_valid,   // 人脸检测命中有效脉冲
    output reg  [7:0]  O_face_x,       // 人脸左上角 X
    output reg  [7:0]  O_face_y,       // 人脸左上角 Y
    output reg  [7:0]  O_face_w,       // 宽度 (固定 24)
    output reg  [7:0]  O_face_h        // 高度 (固定 24)
);

    // 1. 24 阶行缓存流水线 (纯积分图数据，位宽为 24)
    wire [23:0] line [0:24];
    assign line[0] = I_integral;

    genvar i;
    generate
        for (i = 0; i < 24; i = i + 1) begin : pipe_cascade
            line_fifo #(
                .DATA_WIDTH (24),
                .LINE_LEN   (IMG_WIDTH)
            ) u_line_fifo (
                .I_clk   (I_clk),
                .I_rst_n (I_rst_n),
                .wr_en   (I_tvalid),
                .din     (line[i]),
                .dout    (line[i+1])
            );
        end
    endgenerate

    // 2. 25x25 积分点阵缓存
    reg [23:0] win_int [0:24][0:24];

    integer r, c;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            for (r = 0; r < 25; r = r + 1)
                for (c = 0; c < 25; c = c + 1)
                    win_int[r][c] <= 24'd0;
        end else if (I_tvalid) begin
            for (r = 0; r < 25; r = r + 1) begin
                for (c = 0; c < 24; c = c + 1) begin
                    win_int[r][c] <= win_int[r][c+1];
                end
                win_int[r][24] <= line[24 - r];
            end
        end
    end

    // 窗口对齐门禁：确保至少有 24x24 完整数据才允许进入评估
    wire win_valid = I_tvalid && (I_x >= WIN_SIZE - 1) && (I_y >= WIN_SIZE - 1);

    // 3. ROM 资源
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

    // 4. 行列两级 MUX 与 3x3 块积分求和
    wire [4:0] fx = curr_rect_raw[31:24];
    wire [4:0] fy = curr_rect_raw[23:16];
    wire [4:0] fw = curr_rect_raw[15:8];
    wire [4:0] fh = curr_rect_raw[7:0];

    wire [23:0] r0 [0:24];
    wire [23:0] r1 [0:24];
    wire [23:0] r2 [0:24];
    wire [23:0] r3 [0:24];

    genvar mc;
    generate
        for (mc = 0; mc <= WIN_SIZE; mc = mc + 1) begin : gen_row_mux
            assign r0[mc] = win_int[fy][mc];
            assign r1[mc] = win_int[fy + fh][mc];
            assign r2[mc] = win_int[fy + 2*fh][mc];
            assign r3[mc] = win_int[fy + 3*fh][mc];
        end
    endgenerate

    wire [23:0] p00 = r0[fx];         wire [23:0] p01 = r0[fx + fw];
    wire [23:0] p02 = r0[fx + 2*fw];   wire [23:0] p03 = r0[fx + 3*fw];

    wire [23:0] p10 = r1[fx];         wire [23:0] p11 = r1[fx + fw];
    wire [23:0] p12 = r1[fx + 2*fw];   wire [23:0] p13 = r1[fx + 3*fw];

    wire [23:0] p20 = r2[fx];         wire [23:0] p21 = r2[fx + fw];
    wire [23:0] p22 = r2[fx + 2*fw];   wire [23:0] p23 = r2[fx + 3*fw];

    wire [23:0] p30 = r3[fx];         wire [23:0] p31 = r3[fx + fw];
    wire [23:0] p32 = r3[fx + 2*fw];   wire [23:0] p33 = r3[fx + 3*fw];

    wire signed [24:0] s0 = p11 - p01 - p10 + p00;
    wire signed [24:0] s1 = p12 - p02 - p11 + p01;
    wire signed [24:0] s2 = p13 - p03 - p12 + p02;
    wire signed [24:0] s3 = p23 - p13 - p22 + p12;
    wire signed [24:0] s4 = p22 - p12 - p21 + p11; // Center 块
    wire signed [24:0] s5 = p32 - p22 - p31 + p21;
    wire signed [24:0] s6 = p31 - p21 - p30 + p20;
    wire signed [24:0] s7 = p21 - p11 - p20 + p10;
    wire signed [24:0] s8 = p33 - p23 - p32 + p22;

    wire [7:0] calc_lbp_code = {
        (s7 >= s4), (s6 >= s4), (s5 >= s4), (s8 >= s4),
        (s3 >= s4), (s2 >= s4), (s1 >= s4), (s0 >= s4)
    };

    wire hit_bit = curr_bitmask[calc_lbp_code];
    wire signed [15:0] curr_score = hit_bit ? curr_leaf0 : curr_leaf1;

    // 5. Stage 结束索引查表
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

    // 6. 级联决策状态机 (已去除肤色检查，增加坐标锁存)
    localparam S_IDLE        = 2'd0;
    localparam S_FETCH_FEAT  = 2'd1;
    localparam S_EVAL_WEAK   = 2'd2;
    localparam S_CHECK_STAGE = 2'd3;

    reg [1:0] state;
    reg signed [19:0] stage_score;
    reg [7:0] cur_win_x; // 锁存窗口坐标，防止多周期迭代中输入坐标漂移
    reg [7:0] cur_win_y;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            state        <= S_IDLE;
            stage_idx    <= 5'd0;
            weak_idx     <= 8'd0;
            stage_score  <= 20'sd0;
            cur_win_x    <= 8'd0;
            cur_win_y    <= 8'd0;
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
                        cur_win_x   <= I_x;
                        cur_win_y   <= I_y;
                        stage_idx   <= 5'd0;
                        weak_idx    <= 8'd0;
                        stage_score <= 20'sd0;
                        state       <= S_FETCH_FEAT;
                    end
                end

                S_FETCH_FEAT: begin
                    // 等待 BRAM 读出特征参数与矩形
                    state <= S_EVAL_WEAK;
                end

                S_EVAL_WEAK: begin
                    // 累加当前弱分类器得分
                    stage_score <= stage_score + curr_score;
                    state       <= S_CHECK_STAGE;
                end

                S_CHECK_STAGE: begin
                    if (weak_idx == get_stage_end_idx(stage_idx)) begin
                        // 关卡结束，判定阈值
                        if (stage_score >= curr_stage_thresh) begin
                            if (stage_idx == 5'd19) begin
                                // 20 关全部通过，基于锁存的右下角坐标计算左上角
                                O_face_valid <= 1'b1;
                                O_face_x     <= cur_win_x - 8'd23;
                                O_face_y     <= cur_win_y - 8'd23;
                                O_face_w     <= 8'd24;
                                O_face_h     <= 8'd24;
                                state        <= S_IDLE;
                            end else begin
                                // 晋级下一关
                                stage_idx   <= stage_idx + 1'b1;
                                weak_idx    <= weak_idx + 1'b1;
                                stage_score <= 20'sd0;
                                state       <= S_FETCH_FEAT;
                            end
                        end else begin
                            // 不及格早停 (Early-Exit)
                            state <= S_IDLE;
                        end
                    end else begin
                        weak_idx <= weak_idx + 1'b1;
                        state    <= S_FETCH_FEAT;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule