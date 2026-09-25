//=============================================================================
// conv1_pixel.v —— conv1 单像素定点卷积（27 tap x 1 输出通道）
//-----------------------------------------------------------------------------
// 接口由 sim/conv1_pixel_tb.v 定义；对拍基准: sim/cnn_data/x1_conv1.hex
// （= matlab/cnn_detector/out/golden/x1_conv1.txt，uint8，列主序）
//
// 算法（与 matlab step4 金标准同一公式）:
//   acc     = Σ_tap (Wq[tap,cout] * xq[tap]) + b_int[cout]
//   real    = round(acc * MOUT_Q32 / 2^32)      // MOUT_Q32 = round(mOut*2^32)
//   y_out   = clamp(real, 0, 255)，9bit 输出（bit8 恒 0）
//   Q32 常数出处: cnn_params.vh（由 matlab export_fpga_consts.m 自动生成）
//
// 权重/偏置: 行为级 ROM（$readmemh，仿真路径）。
// TD 综合路径将换官方 ROM IP（mem_dath/cnn_w_conv1.dath + cnn_b_conv1.dath）。
//=============================================================================
`timescale 1ns/1ps

module conv1_pixel #(
    parameter W_MEM           = "sim/cnn_data/w_conv1.mem",   // 216 行 int8（列主序 [ky kx cin cout]）
    parameter B_MEM           = "sim/cnn_data/b_conv1.mem",   // 8 行 int32
    parameter signed [31:0] MOUT_Q32 = 32'sd15573148           // = `MOUT_Q32_CONV1（勿手改，见 cnn_params.vh）
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,          // 1 拍启动脉冲
    input  wire [3:0]  cout_idx,       // 输出通道 0..7
    input  wire [242:0] x_patch,       // 27 tap x 9bit（tap = ky + 3*kx + 9*ci，ky 最快变）
    output reg  [8:0]  y_out,          // 9bit: {1'b0, 量化激活 0..255}
    output reg         done
);

    // ---- 行为级权重/偏置 ROM ----
    reg [7:0]  wmem [0:215];
    reg [31:0] bmem [0:7];
    initial begin
        $readmemh(W_MEM, wmem);
        $readmemh(B_MEM, bmem);
    end

    localparam [1:0] S_IDLE = 2'd0, S_ACC = 2'd1, S_OUT = 2'd2;
    reg [1:0]  state;
    reg [4:0]  tap;                    // 0..26
    reg signed [31:0] acc;

    // 权重地址 = cout*27 + tap（列主序: 同一 tap 的 8 个 cout 相距 27）
    wire [7:0]          waddr = (cout_idx * 5'd27) + tap;
    wire signed [7:0]   wq    = $signed(wmem[waddr]);
    wire signed [8:0]   xq    = $signed(x_patch[tap*9 +: 9]);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            tap   <= 5'd0;
            acc   <= 32'sd0;
            y_out <= 9'd0;
            done  <= 1'b0;
        end else begin
            done <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (start) begin
                        tap   <= 5'd0;
                        acc   <= 32'sd0;
                        state <= S_ACC;
                    end
                end
                S_ACC: begin
                    // 27 拍累加；最后一拍同时加偏置
                    if (tap == 5'd26)
                        acc <= acc + (wq * xq) + $signed(bmem[cout_idx]);
                    else
                        acc <= acc + (wq * xq);
                    if (tap == 5'd26)
                        state <= S_OUT;
                    else
                        tap <= tap + 1'b1;
                end
                S_OUT: begin
                    y_out <= quantize(acc);
                    done  <= 1'b1;
                    state <= S_IDLE;
                end
            endcase
        end
    end

    // ---- 定点量化: real = round(acc*MOUT_Q32/2^32)，半舍入远离零，clamp 0..255 ----
    // 负数: round(x) = -round(|x|)（对齐 MATLAB round；随后 ReLU clamp 到 0）
    function [8:0] quantize;
        input signed [31:0] a;
        reg signed [63:0] p, m;
        begin
            p = a * MOUT_Q32;
            if (p[63]) begin
                m = -p;
                m = (m + 64'sd2147483648) >>> 32;
                p = -m;
            end else begin
                p = (p + 64'sd2147483648) >>> 32;
            end
            if (p <= 32'sd0)
                quantize = 9'd0;
            else if (p >= 32'sd255)
                quantize = 9'd255;
            else
                quantize = {1'b0, p[7:0]};
        end
    endfunction

endmodule
