//=============================================================================
// cnn_top.v —— CNN 检测器整链整合（128x72x3 输入 → 全局最高分 1 框）
//-----------------------------------------------------------------------------
// 数据通路: 输入流适配(24bit RGB → conv1 私有输入 RAM 3 平面字节写)
//          → conv1(3→8) → conv2(8→16,s2) → conv3(16→32,s2) → conv4(32→32)
//          → head(1×1,32→15,Q12) → cnn_head_dec(exp LUT + 锚框 + 1728 选 1)
//
// 共享特征图缓冲（**同步读块 RAM**，省 ERAM 且避免 LUTRAM 推断）:
//   bufA: 64bit x 9216  —— x1（1 字/像素，9216 字）→ 复用为 x3（4 字/像素，2304 字）
//   bufB: 128bit x 2304 —— x2（1 字/像素，2304 字）→ 复用为 x4（2 字/像素，1152 字）
//   复用安全性: 各层按 FSM 串行执行；x1 被 conv2 读完才写 x3，x2 被 conv3 读完才写 x4
// 权重: 官方 ROM IP（每层偶/奇字各一份）
// 读口多路: conv2/conv4 共用 bufA 读口，conv3/head 共用 bufB 读口（按调度状态切换）
//=============================================================================
`timescale 1ns/1ps

module cnn_top #(
    parameter IMG_W = 128,
    parameter IMG_H = 72
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        I_tvalid,
    input  wire        I_tuser,
    input  wire [23:0] I_tdata,
    output wire        O_busy,
    output reg         O_valid,
    output reg  [7:0]  O_x1, O_y1, O_w, O_h,
    output reg  [15:0] O_score
);

    // =====================================================================
    // 1. 调度 FSM
    // =====================================================================
    localparam [2:0] S_IDLE=3'd0, S_C1=3'd1, S_C2=3'd2, S_C3=3'd3,
                     S_C4=3'd4, S_HEAD=3'd5, S_DEC=3'd6, S_OUT=3'd7;
    reg [2:0] sched_st;
    assign O_busy = (sched_st != S_IDLE);

    reg  c1_start, c2_start, c3_start, c4_start, h_start;
    wire c1_valid, c1_done, c2_valid, c2_done, c3_valid, c3_done;
    wire c4_valid, c4_done, h_valid, h_done;

    // 解码输出
    wire        d_valid;
    wire [7:0]  d_x1, d_y1, d_w, d_h;
    wire [15:0] d_score;

    // =====================================================================
    // 2. 输入采集适配: 每像素 3 拍写 conv1 私有输入 RAM（3 平面布局）
    // =====================================================================
    reg  [1:0]  cap_st;
    reg  [13:0] cap_cnt;
    reg  [23:0] pix_l;
    reg         frame_ready;
    reg         c1_wr_en;
    reg  [14:0] c1_wr_addr;
    reg  [7:0]  c1_wr_data;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cap_st <= 2'd0; cap_cnt <= 14'd0; frame_ready <= 1'b0;
            c1_wr_en <= 1'b0; c1_wr_addr <= 15'd0; c1_wr_data <= 8'd0; pix_l <= 24'd0;
        end else begin
            c1_wr_en    <= 1'b0;
            frame_ready <= 1'b0;
            case (cap_st)
                2'd0: if (I_tuser && !O_busy) begin
                          cap_cnt <= 14'd0;
                          if (I_tvalid) begin
                              pix_l      <= I_tdata;
                              c1_wr_en   <= 1'b1;
                              c1_wr_addr <= 15'd0;
                              c1_wr_data <= I_tdata[23:16];
                              cap_st     <= 2'd2;
                          end else
                              cap_st <= 2'd1;
                      end
                2'd1: if (I_tvalid) begin
                          pix_l      <= I_tdata;
                          c1_wr_en   <= 1'b1;
                          c1_wr_addr <= {1'b0, cap_cnt};
                          c1_wr_data <= I_tdata[23:16];
                          cap_st     <= 2'd2;
                      end
                2'd2: begin
                          c1_wr_en   <= 1'b1;
                          c1_wr_addr <= {1'b0, cap_cnt} + 15'd9216;
                          c1_wr_data <= pix_l[15:8];
                          cap_st     <= 2'd3;
                      end
                2'd3: begin
                          c1_wr_en   <= 1'b1;
                          c1_wr_addr <= {1'b0, cap_cnt} + 15'd18432;
                          c1_wr_data <= pix_l[7:0];
                          if (cap_cnt == 14'd9215) begin
                              cap_st      <= 2'd0;
                              frame_ready <= 1'b1;
                          end else begin
                              cap_cnt <= cap_cnt + 1'b1;
                              cap_st  <= 2'd1;
                          end
                      end
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sched_st <= S_IDLE;
            c1_start <= 1'b0; c2_start <= 1'b0; c3_start <= 1'b0;
            c4_start <= 1'b0; h_start  <= 1'b0;
            O_valid  <= 1'b0;
            O_x1 <= 8'd0; O_y1 <= 8'd0; O_w <= 8'd0; O_h <= 8'd0; O_score <= 16'd0;
        end else begin
            c1_start <= 1'b0; c2_start <= 1'b0; c3_start <= 1'b0;
            c4_start <= 1'b0; h_start  <= 1'b0; O_valid  <= 1'b0;
            case (sched_st)
                S_IDLE: if (frame_ready) begin c1_start <= 1'b1; sched_st <= S_C1; end
                S_C1:   if (c1_done) begin c2_start <= 1'b1; sched_st <= S_C2; end
                S_C2:   if (c2_done) begin c3_start <= 1'b1; sched_st <= S_C3; end
                S_C3:   if (c3_done) begin c4_start <= 1'b1; sched_st <= S_C4; end
                S_C4:   if (c4_done) begin h_start  <= 1'b1; sched_st <= S_HEAD; end
                S_HEAD: if (h_done)  sched_st <= S_DEC;
                S_DEC:  if (d_valid) begin
                            O_valid  <= 1'b1;
                            O_x1 <= d_x1; O_y1 <= d_y1; O_w <= d_w; O_h <= d_h;
                            O_score <= d_score;
                            sched_st <= S_OUT;
                        end
                S_OUT:  sched_st <= S_IDLE;
                default: sched_st <= S_IDLE;
            endcase
        end
    end

    // =====================================================================
    // 3. 共享特征图缓冲（同步读块 RAM）
    // =====================================================================
    reg  [13:0]  bufA_waddr;
    reg  [63:0]  bufA_wdata;
    reg          bufA_we;
    reg  [11:0]  bufB_waddr;
    reg  [127:0] bufB_wdata;
    reg          bufB_we;

    wire [13:0]  bufA_raddr;
    wire [63:0]  bufA_rdata;
    wire [11:0]  bufB_raddr;
    wire [127:0] bufB_rdata;

    // 官方 RAM IP（TD IP Generator: cnn_buf_a 64x9216 / cnn_buf_b 128x2304，双口，REGMODE=NOREG）
    cnn_buf_a u_bufA (
        .clka(clk), .cea(1'b1), .wea(bufA_we), .addra(bufA_waddr), .dia(bufA_wdata),
        .clkb(clk), .ceb(1'b1), .addrb(bufA_raddr), .dob(bufA_rdata),
        .doa(), .dib(64'd0), .web(1'b0));

    cnn_buf_b u_bufB (
        .clka(clk), .cea(1'b1), .wea(bufB_we), .addra(bufB_waddr), .dia(bufB_wdata),
        .clkb(clk), .ceb(1'b1), .addrb(bufB_raddr), .dob(bufB_rdata),
        .doa(), .dib(128'd0), .web(1'b0));

    // =====================================================================
    // 4. 各层输出与写缓冲展开
    // =====================================================================
    wire [71:0]  c1_out;
    wire [127:0] c2_out;
    wire [255:0] c3_out;
    wire [255:0] c4_out;
    wire [239:0] h_out;

    // conv1 输出 72bit(9bit/通道) → 64bit(8bit/通道)
    wire [63:0] c1_pack = { c1_out[70:63], c1_out[61:54], c1_out[52:45], c1_out[43:36],
                            c1_out[34:27], c1_out[25:18], c1_out[16:9],  c1_out[7:0] };

    reg [13:0] c1_px, c2_px, c3_px, c4_px;
    always @(posedge clk or negedge rst_n)
        if (!rst_n || c1_done) c1_px <= 14'd0; else if (c1_valid) c1_px <= c1_px + 1'b1;
    always @(posedge clk or negedge rst_n)
        if (!rst_n || c2_done) c2_px <= 14'd0; else if (c2_valid) c2_px <= c2_px + 1'b1;
    always @(posedge clk or negedge rst_n)
        if (!rst_n || c3_done) c3_px <= 14'd0; else if (c3_valid) c3_px <= c3_px + 1'b1;
    always @(posedge clk or negedge rst_n)
        if (!rst_n || c4_done) c4_px <= 14'd0; else if (c4_valid) c4_px <= c4_px + 1'b1;

    // conv3 输出 256bit → bufA 4 x 64bit（c3_valid 拍 + 后续 3 拍，共 4 写）
    reg [1:0]   c3w;
    reg         c3w_busy;
    reg [255:0] c3w_word;
    reg [13:0]  c3w_px;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            c3w <= 2'd0; c3w_busy <= 1'b0; c3w_word <= 256'd0; c3w_px <= 14'd0;
        end else if (c3_valid) begin
            c3w_word <= c3_out;
            c3w_px   <= c3_px;
            c3w      <= 2'd1;
            c3w_busy <= 1'b1;
        end else if (c3w_busy) begin
            if (c3w == 2'd3) c3w_busy <= 1'b0;
            else             c3w <= c3w + 1'b1;
        end
    end

    // conv4 输出 256bit → bufB 2 x 128bit（c4_valid 拍 + 后续 1 拍）
    reg         c4w;
    reg         c4w_busy;
    reg [255:0] c4w_word;
    reg [13:0]  c4w_px;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            c4w <= 1'b0; c4w_busy <= 1'b0; c4w_word <= 256'd0; c4w_px <= 14'd0;
        end else if (c4_valid) begin
            c4w_word <= c4_out;
            c4w_px   <= c4_px;
            c4w      <= 1'b1;
            c4w_busy <= 1'b1;
        end else if (c4w_busy) begin
            if (c4w == 1'b1) c4w_busy <= 1'b0;
            else             c4w <= c4w + 1'b1;
        end
    end

    // 写口多路（bufA: conv1 写 x1 / conv3 展开写 x3；bufB: conv2 写 x2 / conv4 展开写 x4）
    // 注意: valid 拍直接用该层输出数据（避免用尚未锁存的 c3w_word/c4w_word）
    always @(*) begin
        if (c3_valid) begin
            bufA_we    = 1'b1;
            bufA_waddr = (c3_px * 4);
            bufA_wdata = c3_out[63:0];
        end else if (c3w_busy) begin
            bufA_we    = 1'b1;
            bufA_waddr = (c3w_px * 4) + c3w;
            bufA_wdata = c3w_word[64*c3w +: 64];
        end else begin
            bufA_we    = c1_valid;
            bufA_waddr = c1_px;
            bufA_wdata = c1_pack;
        end
        if (c4_valid) begin
            bufB_we    = 1'b1;
            bufB_waddr = c4_px[11:0] * 2;
            bufB_wdata = c4_out[127:0];
        end else if (c4w_busy) begin
            bufB_we    = 1'b1;
            bufB_waddr = (c4w_px[11:0] * 2) + c4w;
            bufB_wdata = c4w_word[128*c4w +: 128];
        end else begin
            bufB_we    = c2_valid;
            bufB_waddr = c2_px[11:0];
            bufB_wdata = c2_out;
        end
    end

    // =====================================================================
    // 5. 网络实例化
    // =====================================================================
    // ---- conv1（私有输入 RAM 在模块内）----
    conv1_frame #(
        .B_MEM("sim/cnn_data/b_conv1_packed.mem"),
        .MOUT_Q32(32'sd15573148)
    ) u_conv1 (
        .clk(clk), .rst_n(rst_n),
        .wr_en(c1_wr_en), .wr_addr(c1_wr_addr), .wr_data(c1_wr_data),
        .start(c1_start), .m_data(c1_out), .m_valid(c1_valid), .done(c1_done)
    );

    // ---- conv2（读 bufA，RAM_W=64）----
    wire [10:0] r2e, r2o;
    wire [63:0] d2e, d2o;
    wire [13:0] r2_raddr;
    cnn_rom_w2 u_w2e (.doa(d2e), .addra(r2e[7:0]), .clka(clk));
    cnn_rom_w2 u_w2o (.doa(d2o), .addra(r2o[7:0]), .clka(clk));
    conv_frame #(
        .IMG_W(128), .IMG_H(72), .CIN(8), .COUT(16),
        .K(3), .STRIDE(2), .PAD(1), .TAPS(72), .NUM_GRP(2),
        .OUT_W(64), .OUT_H(36), .WOUT_BITS(128), .AW(14), .RAM_W(64),
        .B_MEM("sim/cnn_data/b_conv2.mem"),
        .MOUT_Q32(32'sd56261780)
    ) u_conv2 (
        .clk(clk), .rst_n(rst_n), .start(c2_start),
        .m_data(c2_out), .m_valid(c2_valid), .done(c2_done),
        .ram_raddr(r2_raddr), .ram_rdata(bufA_rdata),
        .rom_addr_e(r2e), .rom_addr_o(r2o), .w_doa_e(d2e), .w_doa_o(d2o)
    );

    // ---- conv3（读 bufB，RAM_W=128）----
    wire [10:0] r3e, r3o;
    wire [63:0] d3e, d3o;
    wire [11:0] r3_raddr;
    cnn_rom_w3 u_w3e (.doa(d3e), .addra(r3e[9:0]), .clka(clk));
    cnn_rom_w3 u_w3o (.doa(d3o), .addra(r3o[9:0]), .clka(clk));
    conv_frame #(
        .IMG_W(64), .IMG_H(36), .CIN(16), .COUT(32),
        .K(3), .STRIDE(2), .PAD(1), .TAPS(144), .NUM_GRP(4),
        .OUT_W(32), .OUT_H(18), .WOUT_BITS(256), .AW(12), .RAM_W(128),
        .B_MEM("sim/cnn_data/b_conv3.mem"),
        .MOUT_Q32(32'sd25934300)
    ) u_conv3 (
        .clk(clk), .rst_n(rst_n), .start(c3_start),
        .m_data(c3_out), .m_valid(c3_valid), .done(c3_done),
        .ram_raddr(r3_raddr), .ram_rdata(bufB_rdata),
        .rom_addr_e(r3e), .rom_addr_o(r3o), .w_doa_e(d3e), .w_doa_o(d3o)
    );

    // ---- conv4（读 bufA 里的 x3，RAM_W=64）----
    wire [10:0] r4e, r4o;
    wire [63:0] d4e, d4o;
    wire [13:0] r4_raddr;
    cnn_rom_w4 u_w4e (.doa(d4e), .addra(r4e), .clka(clk));
    cnn_rom_w4 u_w4o (.doa(d4o), .addra(r4o), .clka(clk));
    conv_frame #(
        .IMG_W(32), .IMG_H(18), .CIN(32), .COUT(32),
        .K(3), .STRIDE(1), .PAD(1), .TAPS(288), .NUM_GRP(4),
        .OUT_W(32), .OUT_H(18), .WOUT_BITS(256), .AW(14), .RAM_W(64),
        .B_MEM("sim/cnn_data/b_conv4.mem"),
        .MOUT_Q32(32'sd17997652)
    ) u_conv4 (
        .clk(clk), .rst_n(rst_n), .start(c4_start),
        .m_data(c4_out), .m_valid(c4_valid), .done(c4_done),
        .ram_raddr(r4_raddr), .ram_rdata(bufA_rdata),
        .rom_addr_e(r4e), .rom_addr_o(r4o), .w_doa_e(d4e), .w_doa_o(d4o)
    );

    // ---- head（读 bufB 里的 x4，RAM_W=128）----
    wire [10:0] rh;
    wire [63:0] dh;
    wire [11:0] rh_raddr;
    cnn_rom_wh u_wh (.doa(dh), .addra(rh[5:0]), .clka(clk));
    head_frame #(
        .IMG_W(32), .IMG_H(18), .TAPS(32), .NUM_GRP(2), .RAM_W(128), .AW(12),
        .B_MEM("sim/cnn_data/b_head.mem"),
        .MOUT_Q32(32'sd1563445632)
    ) u_head (
        .clk(clk), .rst_n(rst_n), .start(h_start),
        .m_data(h_out), .m_valid(h_valid), .done(h_done),
        .ram_raddr(rh_raddr), .ram_rdata(bufB_rdata),
        .rom_addr(rh), .w_doa(dh)
    );

    // ---- 解码（exp LUT 官方 ROM）----
    cnn_head_dec #(
        .SCORE_TH_Q12(12'd615)
    ) u_dec (
        .clk(clk), .rst_n(rst_n),
        .I_valid(h_valid), .I_data(h_out),
        .O_valid(d_valid), .O_x1(d_x1), .O_y1(d_y1), .O_w(d_w), .O_h(d_h),
        .O_score_q12(d_score)
    );

    // ---- 读口多路: bufA(conv2/conv4) / bufB(conv3/head) ----
    assign bufA_raddr = (sched_st == S_C4) ? r4_raddr : r2_raddr;
    assign bufB_raddr = (sched_st == S_HEAD) ? rh_raddr : r3_raddr;

endmodule
