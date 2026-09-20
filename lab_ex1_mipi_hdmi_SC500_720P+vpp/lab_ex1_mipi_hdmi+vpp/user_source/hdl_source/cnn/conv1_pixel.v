//=============================================================================
// conv1_pixel.v —— conv1 单输出像素算术通路（FPGA 端第一步验证用）
//-----------------------------------------------------------------------------
// 目的：用最小电路把整条"算术链"验对，再做整帧。链路上的每个环节都在这里：
//   权重 ROM($readmemh) → 27 次 MAC（累加器初值=偏置）→ 定点乘 mOut(Q16)
//   → 四舍五入右移 16 → clamp 0..255
//
// 权重布局（与 matlab/cnn_detector/out/w_conv1.mem 一致，列主序）：
//   地址 = ky + K*kx + K*K*ci + K*K*CIN*co      (K=3, CIN=3, COUT=8 → 共 216 个)
//   patch 总线同理：x_patch[i*9 +: 9]，i = ky + K*kx + K*K*ci
//
// 定点公式（与 MATLAB 金标准完全一致）：
//   acc    = b_int[co] + Σ( x[i] * w[co*27+i] )
//   y_out  = clamp( (acc * MOUT_Q16 + 32768) >>> 16, 0, 255 )
//   注：+32768 是四舍五入（MATLAB 用 round，硬件算术右移是下取整，差 1 LSB 就对不上）
//
// 用法：
//   conv1_pixel #(.W_MEM("sim/cnn_data/w_conv1.mem"),
//                 .B_MEM("sim/cnn_data/b_conv1.mem")) dut (...);
//   （路径相对 ModelSim 启动目录；从仓库根目录启动即可）
//=============================================================================
module conv1_pixel #(
    parameter integer CIN      = 3,
    parameter integer COUT     = 8,
    parameter integer K        = 3,
    parameter integer MOUT_Q16 = 238,                       // round(0.00362591 × 65536)
    parameter         W_MEM    = "sim/cnn_data/w_conv1.mem",
    parameter         B_MEM    = "sim/cnn_data/b_conv1.mem"
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 start,                      // 拉高一拍启动一次计算
    input  wire [3:0]           cout_idx,                   // 输出通道 0..COUT-1
    input  wire [CIN*K*K*9-1:0] x_patch,                    // 展平 patch，[i*9 +: 9]
    output reg  [8:0]           y_out,                      // 输出激活 0..255
    output reg                  done                        // 完成脉冲（1 拍）
);

    localparam integer TAPS = CIN*K*K;                      // 27

    //-------------------------------------------------------------------------
    // 权重 / 偏置 ROM（.mem 为十六进制文本，$readmemh 直接读）
    //   权重：8 位二进制补码 int8；偏置：32 位二进制补码 int32
    //-------------------------------------------------------------------------
    reg signed [7:0]  w_rom [0:COUT*TAPS-1];
    reg signed [31:0] b_rom [0:COUT-1];
    initial begin
        $readmemh(W_MEM, w_rom);
        $readmemh(B_MEM, b_rom);
    end

    //-------------------------------------------------------------------------
    // 状态机：IDLE → MAC(27 拍) → SCALE(1 拍) → DONE(1 拍)
    //-------------------------------------------------------------------------
    localparam [1:0] S_IDLE = 2'd0, S_MAC = 2'd1, S_SCALE = 2'd2, S_DONE = 2'd3;

    reg [1:0]         state;
    reg [5:0]         i;                                    // 0..26
    reg [3:0]         co_r;
    reg signed [31:0] acc;
    reg signed [63:0] scaled;

    wire [8:0]         xv   = x_patch[i*9 +: 9];             // 当前 tap 激活（0..255）
    wire signed [8:0]  xs   = {1'b0, xv};                    // 放进有符号容器
    wire signed [7:0]  ws   = w_rom[co_r*TAPS + i];          // int8 补码 → 有符号
    wire signed [17:0] prod = xs * ws;                       // 9b × 8b 有符号
    wire signed [63:0] mout = MOUT_Q16;                      // 定点系数（64 位上下文，避免截断）

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
            done <= 1'b0;                                    // 默认拉低，只脉冲一拍
            case (state)
                S_IDLE: begin
                    if (start) begin
                        acc   <= b_rom[cout_idx];            // 累加器初值 = 偏置
                        co_r  <= cout_idx;
                        i     <= 6'd0;
                        state <= S_MAC;
                    end
                end
                S_MAC: begin
                    acc <= acc + prod;                        // 每个时钟累加一次
                    if (i == TAPS-1) begin
                        state <= S_SCALE;
                    end else begin
                        i <= i + 6'd1;
                    end
                end
                S_SCALE: begin
                    scaled <= acc * mout;                     // 定点乘（64 位）
                    state  <= S_DONE;
                end
                S_DONE: begin
                    if ((scaled + 64'sd32768) < 0)
                        y_out <= 9'd0;                        // 负 → 0（等价 ReLU）
                    else if (((scaled + 64'sd32768) >>> 16) > 64'sd255)
                        y_out <= 9'd255;                      // 上限饱和
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
