//=============================================================================
// conv1_pixel.v —— conv1 单输出像素算术通路（FPGA 端第①②步验证用）
//-----------------------------------------------------------------------------
// 链路：权重 ROM(cnn_rom 同步读) → 27 次 MAC（累加器初值=偏置）
//       → 定点乘 mOut(Q16) → 四舍五入右移 16 → clamp 0..255
//
// 权重布局（与 matlab/cnn_detector/out/w_conv1.mem 一致，列主序）：
//   addr = ky + K*kx + K*K*ci + K*K*CIN*co      (K=3, CIN=3, COUT=8 → 216 项)
//   patch 总线同理：x_patch[i*9 +: 9]，i = ky + K*kx + K*K*ci
//
// 时序（同步 ROM 有 1 拍读延迟）：
//   IDLE(1) → MAC(i=0..TAPS，共 TAPS+1 拍) → SCALE(1) → DONE(1) ≈ 31 拍/点
//     第 i 拍 ROM 地址给出 tap i；本拍拿到的 doa 属于 tap i-1（j = i-1）
//     i=0 那一拍 doa 无效，正好用来装载偏置 b_dout（偏置地址在 IDLE 已给出）
//
// 定点公式（与 MATLAB 金标准一致）：
//   acc   = b_int[co] + Σ( x[i] * w[co*27+i] )
//   y_out = clamp( (acc * MOUT_Q16 + 32768) >>> 16, 0, 255 )
//=============================================================================
module conv1_pixel #(
    parameter integer CIN      = 3,
    parameter integer COUT     = 8,
    parameter integer K        = 3,
    parameter integer MOUT_Q16 = 238,                       // round(0.00362591 × 65536)
    parameter integer W_AW     = 8,                         // 216 项 → 地址 8 位
    parameter integer W_DEPTH  = 256,
    parameter integer B_AW     = 3,                         // 8 项 → 地址 3 位
    parameter integer B_DEPTH  = 8,
    parameter         W_MEM    = "sim/cnn_data/w_conv1.mem",
    parameter         B_MEM    = "sim/cnn_data/b_conv1.mem",
    parameter         W_DATH   = "cnn_w_conv1.dath",
    parameter         B_DATH   = "cnn_b_conv1.dath"
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 start,                      // 拉高一拍启动
    input  wire [3:0]           cout_idx,                   // 输出通道 0..COUT-1
    input  wire [CIN*K*K*9-1:0] x_patch,                    // 展平 patch，[i*9 +: 9]
    output reg  [8:0]           y_out,                      // 输出激活 0..255
    output reg                  done                        // 完成脉冲（1 拍）
);

    localparam integer TAPS = CIN*K*K;                      // 27

    //-------------------------------------------------------------------------
    // ROM：权重 216×8bit，偏置 8×32bit
    //   cnn_rom 内部两种实现：仿真=行为级 $readmemh；TD 综合=官方 ERAM 原语（.dath）
    //-------------------------------------------------------------------------
    reg  [5:0]         i;                                   // ROM 地址指针（tap 序号）
    reg  [3:0]         co_r;
    wire [5:0]         j = (i == 6'd0) ? 6'd0 : (i - 6'd1); // 本拍 doa 对应的 tap
    wire [W_AW-1:0]    w_addr = co_r * TAPS + i;
    wire signed [7:0]  w_dout;
    wire signed [31:0] b_dout;

    cnn_rom #(
        .DW(8), .AW(W_AW), .DEPTH(W_DEPTH),
        .INIT_FILE(W_MEM), .DATH_FILE(W_DATH)
    ) u_w_rom (
        .clka(clk), .addra(w_addr), .doa(w_dout)
    );

    cnn_rom #(
        .DW(32), .AW(B_AW), .DEPTH(B_DEPTH),
        .INIT_FILE(B_MEM), .DATH_FILE(B_DATH)
    ) u_b_rom (
        .clka(clk), .addra(cout_idx[B_AW-1:0]), .doa(b_dout)
    );

    wire [8:0]         xv   = x_patch[j*9 +: 9];            // 当前 tap 激活 0..255
    wire signed [8:0]  xs   = {1'b0, xv};                   // 放进有符号容器
    wire signed [17:0] prod = xs * w_dout;                  // 9b × 8b 有符号
    wire signed [63:0] mout = MOUT_Q16;

    //-------------------------------------------------------------------------
    // 状态机
    //-------------------------------------------------------------------------
    localparam [1:0] S_IDLE = 2'd0, S_MAC = 2'd1, S_SCALE = 2'd2, S_DONE = 2'd3;

    reg [1:0]         state;
    reg signed [31:0] acc;
    reg signed [63:0] scaled;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state  <= S_IDLE;
            i      <= 6'd0;
            co_r   <= 4'd0;
            acc    <= 32'sd0;
            scaled <= 64'sd0;
            y_out  <= 9'd0;
            done   <= 1'b0;
        end else begin
            done <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (start) begin
                        i     <= 6'd0;                  // 地址指针从 tap 0 开始
                        co_r  <= cout_idx;              // 偏置 ROM 地址在 IDLE 已给出
                        acc   <= 32'sd0;
                        state <= S_MAC;
                    end
                end
                S_MAC: begin
                    if (i == 6'd0)
                        acc <= b_dout;                  // 第一拍：装载偏置
                    else
                        acc <= acc + prod;              // 之后每拍累加一个乘积
                    if (i == TAPS)                      // i=TAPS 时 doa 属于最后一个 tap
                        state <= S_SCALE;
                    else
                        i <= i + 6'd1;
                end
                S_SCALE: begin
                    scaled <= acc * mout;               // 定点乘（64 位）
                    state  <= S_DONE;
                end
                S_DONE: begin
                    if ((scaled + 64'sd32768) < 0)
                        y_out <= 9'd0;                  // 负 → 0（等价 ReLU）
                    else if (((scaled + 64'sd32768) >>> 16) > 64'sd255)
                        y_out <= 9'd255;                // 上限饱和
                    else
                        y_out <= (scaled + 64'sd32768) >>> 16;
                    done  <= 1'b1;
                    state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
