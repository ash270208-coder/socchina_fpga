`timescale 1ns / 1ps
//=============================================================================
// pll_por.v —— PLL 上电复位发生器
//
// 背景（为什么要这个模块）：
//   原工程把顶层 I_rst_n 约束到 R10，再用 `PLL.reset = ~I_rst_n` 复位 PLL，
//   而 R10 在 HX1P35A 板上实际连到 YT8511C 的 ETHPHY_TX_EN，**该球上没有按键**。
//   于是"复位"完全依赖该球的内部弱上拉：上电后球被缓缓拉高 -> PLL 释放 -> 锁定
//   -> 全系统解除复位。系统能启动，但复位功能实际上从未生效，且 PLL 一旦失锁
//   就再没有任何手段让它重新锁定，只能断电。
//
//   板 A 以太网改造必须把 R10 让给 phy1_rgmii_tx_ctl，所以这条复位链必须重建。
//   本模块用一直存在的 I_sys_clk（50MHz 板载晶振，不依赖 PLL 自身输出）产生一个
//   确定的上电复位窗口，彻底摆脱"悬空引脚 + 弱上拉"这种不确定的上电行为。
//
// 时序结构：异步复位 / 同步释放
//   ext_arst_n 拉低时立刻把 s1/s2 清零（异步），释放时经两级触发器同步，
//   避免释放沿落在 PLL 参考时钟的亚稳态窗口里。
//   ⚠ 本模块必须跑在 I_sys_clk 上，不能跑在 PLL 自己的输出时钟上（自举依赖）。
//
// 注意：ext_arst_n 预留作"运行中软复位请求"输入，当前设计**不使用**，在顶层
//   直接接 1'b1。若要启用，务必把它做成**一次性脉冲**而不是电平——如果用按键
//   电平直接驱动，用户按住按键上电会让 PLL 永远锁不住（黑屏），这是很难查的坑。
//=============================================================================
module pll_por #(
    // 复位保持时间 = POR_CYCLES / 50MHz。500_000 -> 10ms，
    // 与 YT8511C 要求的 RESET_N 低电平 ≥10ms 一致，给 PHY 自举留足时间。
    parameter [31:0] POR_CYCLES = 32'd500_000
)(
    input  wire clk,          // I_sys_clk, 50MHz, 无复位
    input  wire ext_arst_n,   // 额外复位请求, 低有效; 不用时接 1'b1
    output wire pll_rst,      // 接 PLL u_PLL 的 .reset (高有效)
    output wire por_arst_n    // 低有效上电复位, 可直接作 PHY 的 RESET_N
);

    reg [31:0] cnt = 32'd0;

    always @(posedge clk)
        if (cnt != POR_CYCLES)
            cnt <= cnt + 32'd1;

    wire por_release = (cnt == POR_CYCLES);

    // ⚠ 必须给初值：cnt/s1/s2 若不定初值，上电后第一个时钟沿之前是 X，
    //   pll_rst 就会输出 X 而不是确定的"复位有效"。FPGA 上电确实会把寄存器
    //   初始化为 0，但依赖这一点会让仿真与综合行为不一致；显式写出来，
    //   PH1P 支持寄存器初值（TD 会把它们体现为配置后的确定状态）。
    reg s1 = 1'b0;
    reg s2 = 1'b0;

    always @(posedge clk or negedge ext_arst_n)
        if (!ext_arst_n) {s2, s1} <= 2'b00;
        else             {s2, s1} <= {s1, por_release};

    assign pll_rst    = ~s2;
    // PHY 的 RESET_N 与 PLL 复位同源：同一个 10ms 计数器，天然满足 ≥10ms 的
    // 低电平要求，而且不依赖 PLL 输出时钟（PLL 失锁时依然正确）。
    assign por_arst_n = s2;

endmodule
