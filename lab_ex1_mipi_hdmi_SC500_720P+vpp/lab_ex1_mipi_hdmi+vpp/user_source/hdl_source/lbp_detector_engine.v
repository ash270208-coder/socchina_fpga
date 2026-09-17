`timescale 1ns / 1ps

// ============================================================================
// LBP 级联人脸检测引擎 (多尺度滑窗版)
//
// 相对原版的修复 (仅本文件, 未改其它模块):
//  [FIX-1] LUT 位序修正:
//          weak_lut.dath 中 256-bit 查找表按 lut[0]..lut[7] 高位在前存放,
//          而 OpenCV 规范为 lut[c>>5] 的第 (c&31) 位。
//          因此索引必须为 {~code[7:5], code[4:0]}, 否则永远查错表, 无法检出。
//  [FIX-2] 级联 stage 边界表与 weak_lut.dath 实际内容对齐
//          (dath 中第 91 号弱分类器为第 14 级的附加弱分类器)。
//  [FIX-3] 多尺度金字塔扫描:
//          原引擎只扫 24x24 固定窗, 测试图人脸约 50~70 低分辨率像素,
//          必须按 OpenCV detectMultiScale 的方式多尺度检测。
//          采用定点坐标缩放 (scale = s16/16), 直接从全分辨率积分图取块和,
//          无需额外存储。
//  扫描范围与耗时: SCALE_MIN_S16=36 .. SCALE_MAX_S16=76, 步进 10/16,
//          共 5 级 (窗 54/69/84/99/114 低分px = 720p 中 324~684px),
//          覆盖镜头前约 0.25~0.55 m (人脸占画面 1/4~1/2)。
//          SCAN_STEP=3, 每帧约 3100 窗 ≈ 7 ms @74.25MHz, 一帧周期内完成。
//          注意: 大窗特征块和需配合积分输入右移 1 位 (见 integral_image.v),
//          使块和 < 2^18 (38^2 * 127 ≈ 18.3 万), 18-bit 积分 RAM 不失真。
//  [FIX-4] 输出整窗矩形: O_face_x/y = 检测窗左上角, O_face_w/h = win_w,
//          画框覆盖完整检测窗 (原固定 24x24 框只盖住人脸的一小部分)。
//  [FIX-5] 积分 RAM X 态消除: frame_integral_bram 的 FILL_ALL 置为全 0
//          (第 0 列/第 0 行降采样后本就为 0), 波形不再有 X 态。
//  [FIX-6] 检测结果卫生 (消除噪点误检乱框):
//          每帧收集所有全 20 级通过的窗口, 扫描结束时只输出总分最高的
//          1 个候选 (等效 OpenCV minNeighbors/NMS 的轻量替代)。噪点区域的
//          误报通常是"压线过关", 总分远低于真实人脸, 会被最高分机制压掉。
//  [FIX-7] 乒乓切换保护: frame_end 仅在引擎空闲 (S_IDLE) 时才交换读写
//          bank; 扫描未完成时丢弃当前帧并告警, 避免扫描后半段读到新一帧
//          数据造成混帧。
//  [FIX-8] 时域确认: 候选与上一帧确认位置邻近 (±12 低分px = 72px@720p) 才
//          输出脉冲; 首帧/位置跳变仅静默锁存, 连续 15 帧无候选才撤销确认
//          位置 (与 OSD 保持帧数一致) —— 消除"噪点单帧误报"与绿框闪跳,
//          同时保证级联偶发通过时框也能持续刷新。
// ============================================================================

module lbp_detector_engine #(
    parameter IMG_WIDTH  = 213,   
    parameter IMG_HEIGHT = 120,   
    parameter WIN_SIZE   = 24,
    parameter SCAN_STEP  = 3,     // 滑窗步长 (3 低分px = 18px@720p)
    // 多尺度金字塔: 定点 scale = s16/16 (16 = 1.0 倍, 76 = 4.75 倍)
    // 5 级: 窗 54/69/84/99/114 低分px = 720p 中 324~684px,
    //       覆盖镜头前约 0.25~0.55m (人脸占画面 1/4~1/2)
    parameter SCALE_MIN_S16 = 36, // 最小尺度 (窗 54)
    parameter SCALE_MAX_S16 = 76, // 最大尺度 (窗 114)
    parameter SCALE_STEP_S16= 10  // 尺度步进
)(
    input  wire        I_clk,          
    input  wire        I_rst_n,        
    
    // 来自积分图计算模块的数据流 (写通道)
    input  wire        I_tvalid,       
    input  wire        I_tuser,        // 帧起始标志 (SOF)
    input  wire [23:0] I_integral,     
    input  wire [7:0]  I_x,            
    input  wire [7:0]  I_y,            
    
    // 检测状态与结果输出
    output reg         O_busy,         // 引擎正忙（正在遍历检测）
    output reg         O_frame_drop,   // 掉帧报警（检测耗时超过一帧时触发）
    output reg         O_face_valid,   // 检测到人脸脉冲（高电平有效 1 拍）
    output reg  [7:0]  O_face_x,       
    output reg  [7:0]  O_face_y,       
    output reg  [7:0]  O_face_w,       
    output reg  [7:0]  O_face_h        
);

    // =========================================================================
    // 1. 物理双 BRAM 乒乓仲裁 (2 个独立的 25560 BRAM)
    // =========================================================================
    reg wr_bank; // 当前写入的目标 Bank: 0 或 1
    reg rd_bank; // 当前读取的目标 Bank: 0 或 1
    reg frame_pending;

    // 帧末尾信号：写入第 119 行最后一个点 (212, 119)
    wire frame_end = I_tvalid && (I_x == IMG_WIDTH - 1) && (I_y == IMG_HEIGHT - 1);

    // 地址 = y * IMG_WIDTH + x = y*213 + x。213 = 128+64+16+4+1, 用移位加法实现,
    // 避免综合出乘法器。注意 Verilog 移位结果不自动扩展位宽, 必须先把 y 扩展为
    // 15 位再移位, 否则 y>=2 时高位移出丢失。最大地址 119*213+212 = 25559,
    // 不超 15 位地址空间 32768。
    // 移位系数必须与 IMG_WIDTH 及 frame_integral_bram 深度 (25560) 严格一致。
    wire [14:0] I_y_wide    = {7'd0, I_y};
    wire [14:0] ram_wr_addr = (I_y_wide << 7) + (I_y_wide << 6) + (I_y_wide << 4) + (I_y_wide << 2) + I_y + I_x;
    reg  [14:0] ram_rd_addr;

    // 根据 wr_bank 决定写使能给哪一个 BRAM
    wire cea_0 = I_tvalid & (~wr_bank); // wr_bank 为 0 时写 BRAM 0
    wire cea_1 = I_tvalid & ( wr_bank); // wr_bank 为 1 时写 BRAM 1

    wire [17:0] ram_rd_data_0;
    wire [17:0] ram_rd_data_1;

    // ---------------------- 乒乓 Bank 0 (深度 25560) ----------------------
    frame_integral_bram u_integral_bram_0 (
        .clka   (I_clk),
        .cea    (cea_0),               
        .addra  (ram_wr_addr),         // 15 位写地址
        .dia    (I_integral[17:0]),    
        
        .ceb    (1'b1),                
        .addrb  (ram_rd_addr),         // 15 位读地址
        .dob    (ram_rd_data_0)        
    );

    // ---------------------- 乒乓 Bank 1 (深度 25560) ----------------------
    frame_integral_bram u_integral_bram_1 (
        .clka   (I_clk),
        .cea    (cea_1),               
        .addra  (ram_wr_addr),         // 15 位写地址
        .dia    (I_integral[17:0]),    
        
        .ceb    (1'b1),                
        .addrb  (ram_rd_addr),         // 15 位读地址
        .dob    (ram_rd_data_1)        
    );

    // 读数据多路选择器 (MUX)：检测引擎需要读哪个 Bank，就选通哪个
    wire [17:0] ram_rd_data = (rd_bank == 1'b1) ? ram_rd_data_1 : ram_rd_data_0;

    // =========================================================================
    // 2. ROM 资源定义
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
    // 3. 自主滑窗采样生成器 (多尺度定点坐标)
    // =========================================================================
    reg [7:0] scan_x, scan_y; 
    reg [6:0] scale_s16;         // 当前尺度 (定点 4.4: 值/16 = 实际倍数)

    // 当前尺度窗口宽/高 (低分辨率像素) 与扫描边界
    wire [10:0] win_w_pre = WIN_SIZE * scale_s16;      // 24*76=1824 -> 11 bit
    wire [7:0]  win_w     = win_w_pre >> 4;
    wire [7:0]  max_scan_x = IMG_WIDTH  - win_w;
    wire [7:0]  max_scan_y = IMG_HEIGHT - win_w;

    wire [4:0] fx = curr_rect_raw[31:24];
    wire [4:0] fy = curr_rect_raw[23:16];
    wire [4:0] fw = curr_rect_raw[15:8];
    wire [4:0] fh = curr_rect_raw[7:0];

    // 定点缩放: 特征矩形顶点坐标 = (scan + f*scale)/16 (与 OpenCV 一致)
    wire [13:0] sx_sc = scan_x * scale_s16;   // 8 bit * 7 bit, 最大 99*76=7524 -> 14 bit
    wire [13:0] sy_sc = scan_y * scale_s16;
    wire [11:0] fx_sc = fx * scale_s16;       // 5 bit * 7 bit, 最大 31*76=2356 -> 12 bit
    wire [11:0] fy_sc = fy * scale_s16;
    wire [11:0] fw_sc = fw * scale_s16;
    wire [11:0] fh_sc = fh * scale_s16;

    wire [10:0] dw = fw_sc >> 4;      // 缩放后块宽 (<=38)
    wire [10:0] dh = fh_sc >> 4;      // 缩放后块高 (<=38)

    wire [7:0] abs_x0 = (sx_sc + fx_sc) >> 4;
    wire [7:0] abs_x1 = abs_x0 + dw[7:0];
    wire [7:0] abs_x2 = abs_x0 + {dw[6:0], 1'b0};                    // +2*dw
    wire [7:0] abs_x3 = abs_x0 + {dw[6:0], 1'b0} + dw[7:0];          // +3*dw

    wire [7:0] abs_y0 = (sy_sc + fy_sc) >> 4;
    wire [7:0] abs_y1 = abs_y0 + dh[7:0];
    wire [7:0] abs_y2 = abs_y0 + {dh[6:0], 1'b0};                    // +2*dh
    wire [7:0] abs_y3 = abs_y0 + {dh[6:0], 1'b0} + dh[7:0];          // +3*dh

    // [时序修复] 在 S_WAIT_ROM 末尾把 abs 坐标寄存一拍:
    // 拆开 "ROM -> 乘法 -> 加法" 长组合链与后续 "取点选择 -> 截断 -> 地址加法" 链。
    // 原设计按 50MHz 时钟开发, 直接跑在 75MHz 像素时钟下该路径违例约 1.9ns。
    reg [7:0] r_abs_x0, r_abs_x1, r_abs_x2, r_abs_x3;
    reg [7:0] r_abs_y0, r_abs_y1, r_abs_y2, r_abs_y3;

    reg [4:0] fetch_step;
    reg [7:0] cur_sample_x, cur_sample_y;

    always @(*) begin
        case (fetch_step)
            5'd0:  begin cur_sample_y = r_abs_y0; cur_sample_x = r_abs_x0; end
            5'd1:  begin cur_sample_y = r_abs_y0; cur_sample_x = r_abs_x1; end
            5'd2:  begin cur_sample_y = r_abs_y0; cur_sample_x = r_abs_x2; end
            5'd3:  begin cur_sample_y = r_abs_y0; cur_sample_x = r_abs_x3; end
            5'd4:  begin cur_sample_y = r_abs_y1; cur_sample_x = r_abs_x0; end
            5'd5:  begin cur_sample_y = r_abs_y1; cur_sample_x = r_abs_x1; end
            5'd6:  begin cur_sample_y = r_abs_y1; cur_sample_x = r_abs_x2; end
            5'd7:  begin cur_sample_y = r_abs_y1; cur_sample_x = r_abs_x3; end
            5'd8:  begin cur_sample_y = r_abs_y2; cur_sample_x = r_abs_x0; end
            5'd9:  begin cur_sample_y = r_abs_y2; cur_sample_x = r_abs_x1; end
            5'd10: begin cur_sample_y = r_abs_y2; cur_sample_x = r_abs_x2; end
            5'd11: begin cur_sample_y = r_abs_y2; cur_sample_x = r_abs_x3; end
            5'd12: begin cur_sample_y = r_abs_y3; cur_sample_x = r_abs_x0; end
            5'd13: begin cur_sample_y = r_abs_y3; cur_sample_x = r_abs_x1; end
            5'd14: begin cur_sample_y = r_abs_y3; cur_sample_x = r_abs_x2; end
            5'd15: begin cur_sample_y = r_abs_y3; cur_sample_x = r_abs_x3; end
            default: begin cur_sample_y = 8'd0; cur_sample_x = 8'd0; end
        endcase
    end

    wire [7:0] safe_x = (cur_sample_x >= IMG_WIDTH)  ? (IMG_WIDTH  - 1) : cur_sample_x;
    wire [7:0] safe_y = (cur_sample_y >= IMG_HEIGHT) ? (IMG_HEIGHT - 1) : cur_sample_y;

    // 【正确统一的读地址计算】：物理双 RAM 内部地址都是 0~25559，无多驱动冲突
    // 同样用 15 位扩展后的移位加法实现 (safe_y*213 + safe_x)
    wire [14:0] safe_y_wide = {7'd0, safe_y};
    always @(*) begin
        ram_rd_addr = (safe_y_wide << 7) + (safe_y_wide << 6) + (safe_y_wide << 4) + (safe_y_wide << 2) + safe_y + safe_x;
    end

    // 16 拍打拍锁存
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

    // 9 个 Block 的矩形和 (18-bit 模运算, block 和 < 2^18 时精确)
    wire [17:0] s0 = p11 - p01 - p10 + p00; // TL
    wire [17:0] s1 = p12 - p02 - p11 + p01; // TC
    wire [17:0] s2 = p13 - p03 - p12 + p02; // TR
    wire [17:0] s3 = p23 - p13 - p22 + p12; // MR
    wire [17:0] s4 = p22 - p12 - p21 + p11; // Center
    wire [17:0] s5 = p32 - p22 - p31 + p21; // BC
    wire [17:0] s6 = p31 - p21 - p30 + p20; // BL
    wire [17:0] s7 = p21 - p11 - p20 + p10; // ML
    wire [17:0] s8 = p33 - p23 - p32 + p22; // BR

    // OpenCV 规范的 8 位 LBP 编码 (bit7:TL bit6:TC bit5:TR bit4:MR
    //                             bit3:BR bit2:BC bit1:BL bit0:ML)
    wire [7:0] calc_lbp_code = {
        (s0 >= s4), // Bit 7 (128) - 左上
        (s1 >= s4), // Bit 6 (64)  - 正上
        (s2 >= s4), // Bit 5 (32)  - 右上
        (s3 >= s4), // Bit 4 (16)  - 正右
        (s8 >= s4), // Bit 3 (8)   - 右下
        (s5 >= s4), // Bit 2 (4)   - 正下
        (s6 >= s4), // Bit 1 (2)   - 左下
        (s7 >= s4)  // Bit 0 (1)   - 正左
    };

    // [FIX-1] LUT 位序修正:
    // weak_lut.dath 中 lut[0] 存放在 bit[255:224] ... lut[7] 在 bit[31:0],
    // 而 OpenCV 查表为 lut[code>>5] 的第 (code&31) 位 =>
    // 索引 = {~(code>>5), code[4:0]}  (高 3 位取反即 7-(code>>5))
    wire [7:0] lut_index = {~calc_lbp_code[7:5], calc_lbp_code[4:0]};
    wire hit_bit = curr_bitmask[lut_index];
    wire signed [15:0] curr_score = hit_bit ? curr_leaf0 : curr_leaf1;

    // [FIX-2] Stage 截止索引 (与 weak_lut.dath 内容对齐)
    function [7:0] get_stage_end_idx;
        input [4:0] s;
        case(s)
            5'd0:  get_stage_end_idx = 8'd2;   
            5'd1:  get_stage_end_idx = 8'd6;   
            5'd2:  get_stage_end_idx = 8'd10;  
            5'd3:  get_stage_end_idx = 8'd15;  
            5'd4:  get_stage_end_idx = 8'd20;  
            5'd5:  get_stage_end_idx = 8'd25;  
            5'd6:  get_stage_end_idx = 8'd30;  
            5'd7:  get_stage_end_idx = 8'd36;  
            5'd8:  get_stage_end_idx = 8'd43;  
            5'd9:  get_stage_end_idx = 8'd50;  
            5'd10: get_stage_end_idx = 8'd57;  
            5'd11: get_stage_end_idx = 8'd64;  
            5'd12: get_stage_end_idx = 8'd72;  
            5'd13: get_stage_end_idx = 8'd81;  
            5'd14: get_stage_end_idx = 8'd91;  
            5'd15: get_stage_end_idx = 8'd100; 
            5'd16: get_stage_end_idx = 8'd109; 
            5'd17: get_stage_end_idx = 8'd118; 
            5'd18: get_stage_end_idx = 8'd128; 
            5'd19: get_stage_end_idx = 8'd138; 
            default: get_stage_end_idx = 8'd138;
        endcase
    endfunction

    // =========================================================================
    // 4. 检测控制状态机与乒乓切换
    // =========================================================================
    localparam S_IDLE        = 3'd0;
    localparam S_INIT_WIN    = 3'd1;
    localparam S_WAIT_ROM    = 3'd2;
    localparam S_FETCH_PTS   = 3'd3;
    localparam S_EVAL_WEAK   = 3'd4;
    localparam S_CHECK_STAGE = 3'd5;
    localparam S_NEXT_WIN    = 3'd6;

    reg [2:0] state;
    reg [1:0] rom_wait_cnt;
    reg signed [19:0] stage_score;

    // [FIX-6] 每帧最优候选 (全 20 级通过且总分最高), 扫描结束时一次性输出
    reg          best_valid;
    reg signed [19:0] best_score;
    reg  [7:0]   best_x, best_y, best_w;

    // [FIX-8] 时域确认: 候选与上一帧确认位置邻近 (±12 低分px = 72px@720p)
    //         才输出脉冲; 首帧/位置跳变仅静默锁存, 连续 15 帧无候选才撤销
    //         确认位置 (与 OSD 保持帧数一致) —— 消除"噪点单帧误报"与绿框
    //         闪跳, 同时保证级联偶发通过时框也能持续刷新。
    reg        prev_valid;
    reg  [7:0] prev_x, prev_y;
    reg  [3:0] miss_cnt;
    wire [7:0] diff_x = (best_x >= prev_x) ? (best_x - prev_x) : (prev_x - best_x);
    wire [7:0] diff_y = (best_y >= prev_y) ? (best_y - prev_y) : (prev_y - best_y);
    wire       candidate_stable = prev_valid && (diff_x <= 8'd12) && (diff_y <= 8'd12);

    // 乒乓缓存握手核心逻辑
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            wr_bank       <= 1'b0;
            rd_bank       <= 1'b0;
            frame_pending <= 1'b0;
            O_frame_drop  <= 1'b0;
        end else begin
            // [FIX-7] 写入完成且引擎空闲时才交换 bank;
            //         引擎仍在扫描时保持两 bank 不动, 丢弃当前帧并告警
            if (frame_end && (state == S_IDLE)) begin
                O_frame_drop  <= 1'b0;
                rd_bank       <= wr_bank;  // 让读端口锁定刚刚写满的这块 Bank
                wr_bank       <= ~wr_bank; // 写端口去写另外一块 Bank
                frame_pending <= 1'b1;     // 发出检测申请
            end else if (frame_end) begin
                O_frame_drop <= 1'b1;      // 上一轮扫描未完成, 本帧丢弃
            end else begin
                O_frame_drop <= 1'b0;
                if (state == S_IDLE && frame_pending) begin
                    frame_pending <= 1'b0; // 引擎接单，撤销申请
                end
            end
        end
    end

    // 主检测流水状态机
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            state        <= S_IDLE;
            scan_x       <= 8'd0;
            scan_y       <= 8'd0;
            scale_s16    <= SCALE_MIN_S16;
            stage_idx    <= 5'd0;
            weak_idx     <= 8'd0;
            stage_score  <= 20'sd0;
            fetch_step   <= 5'd0;
            rom_wait_cnt <= 2'd0;
            r_abs_x0     <= 8'd0; r_abs_x1 <= 8'd0; r_abs_x2 <= 8'd0; r_abs_x3 <= 8'd0;
            r_abs_y0     <= 8'd0; r_abs_y1 <= 8'd0; r_abs_y2 <= 8'd0; r_abs_y3 <= 8'd0;
            O_busy       <= 1'b0;
            O_face_valid <= 1'b0;
            O_face_x     <= 8'd0;
            O_face_y     <= 8'd0;
            O_face_w     <= 8'd24;
            O_face_h     <= 8'd24;
            best_valid   <= 1'b0;
            best_score   <= 20'sh80000;   // 最负, 保证首个候选必被采纳
            best_x       <= 8'd0;
            best_y       <= 8'd0;
            best_w       <= 8'd0;
            prev_valid   <= 1'b0;
            prev_x       <= 8'd0;
            prev_y       <= 8'd0;
            miss_cnt     <= 4'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    O_face_valid <= 1'b0;
                    if (frame_pending) begin
                        O_busy    <= 1'b1;
                        scan_x    <= 8'd0;
                        scan_y    <= 8'd0;
                        scale_s16 <= SCALE_MIN_S16;   // [FIX-3] 金字塔从最小尺度开始
                        best_valid  <= 1'b0;          // [FIX-6] 新一轮扫描, 清空候选
                        best_score  <= 20'sh80000;
                        state     <= S_INIT_WIN;
                    end else begin
                        O_busy <= 1'b0;
                    end
                end

                S_INIT_WIN: begin
                    O_face_valid <= 1'b0;
                    stage_idx    <= 5'd0;
                    weak_idx     <= 8'd0;
                    stage_score  <= 20'sd0;
                    rom_wait_cnt <= 2'd0;
                    state        <= S_WAIT_ROM;
                end

                S_WAIT_ROM: begin
                    if (rom_wait_cnt == 2'd1) begin
                        rom_wait_cnt <= 2'd0;
                        fetch_step   <= 5'd0;
                        // [时序修复] 此刻 ROM 数据已稳定, 寄存 abs 坐标缩短组合路径
                        r_abs_x0     <= abs_x0;
                        r_abs_x1     <= abs_x1;
                        r_abs_x2     <= abs_x2;
                        r_abs_x3     <= abs_x3;
                        r_abs_y0     <= abs_y0;
                        r_abs_y1     <= abs_y1;
                        r_abs_y2     <= abs_y2;
                        r_abs_y3     <= abs_y3;
                        state        <= S_FETCH_PTS;
                    end else begin
                        rom_wait_cnt <= rom_wait_cnt + 1'b1;
                    end
                end

                S_FETCH_PTS: begin
                    if (fetch_step == 5'd16) begin
                        fetch_step <= 5'd0;
                        state      <= S_EVAL_WEAK;
                    end else begin
                        fetch_step <= fetch_step + 1'b1;
                    end
                end

                S_EVAL_WEAK: begin
                    stage_score <= stage_score + curr_score;
                    state       <= S_CHECK_STAGE;
                end

                S_CHECK_STAGE: begin
                    if (weak_idx == get_stage_end_idx(stage_idx)) begin
                        if (stage_score >= curr_stage_thresh) begin
                            if (stage_idx == 5'd19) begin
                                // [FIX-6] 20 关全通: 记录候选, 本帧结束后
                                // 只输出总分最高者, 不在此处立即出框
                                if (stage_score > best_score) begin
                                    best_score <= stage_score;
                                    best_valid <= 1'b1;
                                    best_x     <= scan_x;   // [FIX-4] 整窗矩形
                                    best_y     <= scan_y;
                                    best_w     <= win_w;
                                end
                                state <= S_NEXT_WIN;
                            end else begin
                                stage_idx    <= stage_idx + 1'b1;
                                weak_idx     <= weak_idx + 1'b1;
                                stage_score  <= 20'sd0;
                                rom_wait_cnt <= 2'd0;
                                state        <= S_WAIT_ROM;
                            end
                        end else begin
                            state <= S_NEXT_WIN; // 未及格剪枝
                        end
                    end else begin
                        weak_idx     <= weak_idx + 1'b1;
                        rom_wait_cnt <= 2'd0;
                        state        <= S_WAIT_ROM;
                    end
                end

                S_NEXT_WIN: begin
                    O_face_valid <= 1'b0;
                    if (scan_x + SCAN_STEP <= max_scan_x) begin
                        scan_x <= scan_x + SCAN_STEP;
                        state  <= S_INIT_WIN;
                    end else begin
                        scan_x <= 8'd0; // 换行
                        if (scan_y + SCAN_STEP <= max_scan_y) begin
                            scan_y <= scan_y + SCAN_STEP;
                            state  <= S_INIT_WIN;
                        end else begin
                            // [FIX-3] 本尺度扫描完成: 进入下一尺度或结束
                            scan_y <= 8'd0;
                            if (scale_s16 + SCALE_STEP_S16 <= SCALE_MAX_S16) begin
                                scale_s16 <= scale_s16 + SCALE_STEP_S16;
                                state     <= S_INIT_WIN;
                            end else begin
                                // [FIX-6][FIX-8] 全部尺度扫描完成:
                                // 时域确认后输出本帧最优候选 (1 拍脉冲)
                                if (best_valid) begin
                                    miss_cnt <= 4'd0;
                                    if (candidate_stable) begin
                                        O_face_valid <= 1'b1;
                                        O_face_x     <= best_x;
                                        O_face_y     <= best_y;
                                        O_face_w     <= best_w;
                                        O_face_h     <= best_w;
                                        prev_x       <= best_x;
                                        prev_y       <= best_y;
                                        prev_valid   <= 1'b1;
                                    end else begin
                                        // 首帧或位置跳变: 静默锁存, 不出框
                                        // (下一帧位置邻近时才开始连续出框)
                                        prev_x     <= best_x;
                                        prev_y     <= best_y;
                                        prev_valid <= 1'b1;
                                    end
                                end else begin
                                    // 连续 15 帧无候选才撤销确认位置 (与 OSD 保持帧数一致)
                                    if (miss_cnt == 4'd15) begin
                                        prev_valid <= 1'b0;
                                    end else begin
                                        miss_cnt <= miss_cnt + 1'b1;
                                    end
                                end
                                state <= S_IDLE;
                            end
                        end
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
