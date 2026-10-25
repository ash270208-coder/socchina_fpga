`timescale 1ns / 1ps
//=============================================================================
// divider_seq.v —— 与 TD `divider` IP **功能等价**的顺序（非流水）除法器
//
// 为什么写这个：
//   原 `divider` IP（user_source/ip_source/divider/divider_gate.v）是
//   **48 级全流水**的移位-减法阵列（parameter PIPLE=50，网表里是
//   SubSft[0].i … SubSft[47].i 共 48 级，ITERA_PIPLINE=48'b111…1）。
//   全流水意味着每拍都能吃进一个新的除法、每拍吐出一个商 ——
//   所以它摆着 48 个并行的 48bit 减法器，实测占
//   **827 LUT + 948 ripple + 2496 寄存器**（布线后 phy_1/*.area 的 u_divider 行）。
//
//   但在 awb.v 里它**每帧只用 2 次**（场消隐后算 G/R 与 G/B），而 720p60 一帧
//   在 75MHz 下有约 125 万拍 —— 两次除法各花 48 拍只占 0.004%。
//   而且 awb 的外层状态机本来就是 `done` 握手（不是靠固定 50 拍硬等）。
//
//   所以把 48 级流水"折回"单减法器的 48 拍循环即可：
//   **算法完全一样，商的每一位都相同**，不是近似；省下的是 47 个减法器和整条流水线。
//
// 算法（restoring / 恢复余数法，就是手算长除法）：
//   rem = 0
//   逐位从 MSB 到 LSB（共 W_NUM 次）：
//       rem = (rem << 1) | 被除数当前位
//       若 rem >= 除数：rem -= 除数，商的这一位 = 1
//       否则：                          商的这一位 = 0
//   结束时 rem 就是余数。
//
// 与原 IP 的接口/语义保持一致（这样 awb.v 的例化行不用改）：
//   * 端口名与位宽完全相同：clk / denominator[31:0] / numerator[47:0] /
//     rst(高有效异步复位) / start(单周期启动脉冲) / done / quotient[47:0] / remainder[31:0]
//   * 参数名保留（PIPLE 本模块不使用；S_DEN/S_NUM 仅支持 UNSIGNED）
//   * rst 与 IP 一致是**高有效、异步**：原 IP 网表是 AL_DFF_X 的 .ar(rst)；
//     awb.v 传的是 .rst(!I_rst_n)
//
// 行为差异（唯一一处，且对本设计有利）：
//   * 原 IP：start 之后约 PIPLE(50) 拍出 done，吞吐 1/拍
//   * 本模块：start 之后 **W_NUM+1(49) 拍**出 done，吞吐 1/(W_NUM+1)
//   * `done` 两者都是**单周期脉冲**，且当拍 quotient/remainder 就有效
//   ⚠ 因此 awb.v 里 `if (done_div && (div_cnt >= DIV_LAT-4))` 那句
//     "按固定拍数硬等"的守卫必须去掉，改成**纯 `if (done_div)`**，
//     否则换实现后拍数一变就会错。
//
// 资源估算（W_NUM=48 / W_DEN=32）：一个 49bit 减法器 + 49bit 2:1 mux +
//   48bit 商移位寄存器 + 48bit 被除数移位寄存器 + 32bit 除数锁存 + 小 FSM
//   ≈ 150~250 LUT / 40~80 ripple / ~200 寄存器
//   （对比原 IP：827 LUT / 948 ripple / 2496 寄存器）
//
// 参考：docs/板A以太网改造_第2步实施记录.md §5.6
//=============================================================================
module divider_seq #(
    parameter PIPLE = 50,            // 仅为兼容原例化参数；本模块不使用
    parameter S_DEN = "UNSIGNED",
    parameter S_NUM = "UNSIGNED",
    parameter W_DEN = 32,
    parameter W_NUM = 48,
    parameter W_REM = 32
)(
    input  wire             clk,
    input  wire [W_DEN-1:0] denominator,
    input  wire [W_NUM-1:0] numerator,
    input  wire             rst,
    input  wire             start,
    output reg              done,
    output reg  [W_NUM-1:0] quotient,
    output reg  [W_REM-1:0] remainder
);

    // 余数寄存器比分子宽 1 位：每步移位后最大到 2*den-1 < 2^(W_DEN+1)
    localparam RW = W_NUM + 1;
    // 迭代计数：W_NUM=48 需要 6 位（支持到 W_NUM ≤ 64）
    localparam CW = 6;
    localparam [CW-1:0] CNT_INIT = W_NUM - 1;

    reg  [RW-1:0]    rem;
    reg  [W_NUM-1:0] quo;
    reg  [W_NUM-1:0] num_r;
    reg  [W_DEN-1:0] den_r;
    reg  [CW-1:0]    cnt;
    reg              busy;

    // 移位进来的那一位 = 被除数当前的最高位；同时把 num_r 左移备下一轮用
    wire [RW-1:0] rem_sh  = {rem[RW-2:0], num_r[W_NUM-1]};
    wire [RW-1:0] den_ext = {{(RW-W_DEN){1'b0}}, den_r};
    wire          ge      = (rem_sh >= den_ext);
    wire [RW-1:0] rem_nxt = ge ? (rem_sh - den_ext) : rem_sh;
    // 商从 LSB 侧移入：第 1 轮算出的 MSB 会一路被推到最高位
    wire [W_NUM-1:0] quo_sh = {quo[W_NUM-2:0], ge};

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rem       <= {RW{1'b0}};
            quo       <= {W_NUM{1'b0}};
            num_r     <= {W_NUM{1'b0}};
            den_r     <= {W_DEN{1'b0}};
            cnt       <= {CW{1'b0}};
            busy      <= 1'b0;
            done      <= 1'b0;
            quotient  <= {W_NUM{1'b0}};
            remainder <= {W_REM{1'b0}};
        end else begin
            done <= 1'b0;                       // done 是单周期脉冲

            if (!busy) begin
                if (start) begin                // 单周期 start 脉冲 -> 启动
                    num_r <= numerator;
                    den_r <= denominator;
                    rem   <= {RW{1'b0}};
                    quo   <= {W_NUM{1'b0}};
                    cnt   <= CNT_INIT;
                    busy  <= 1'b1;
                end
            end else begin
                rem   <= rem_nxt;
                num_r <= {num_r[W_NUM-2:0], 1'b0};
                quo   <= quo_sh;                // 移位式写商，避免变址译码

                if (cnt == {CW{1'b0}}) begin     // 最后一位
                    busy      <= 1'b0;
                    done      <= 1'b1;
                    quotient  <= quo_sh;         // 含刚算出的 bit0
                    remainder <= rem_nxt[W_REM-1:0];
                end else begin
                    cnt <= cnt - 1'b1;
                end
            end
        end
    end

endmodule
