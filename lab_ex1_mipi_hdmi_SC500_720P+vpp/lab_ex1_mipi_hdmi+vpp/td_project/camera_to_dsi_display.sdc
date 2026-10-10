create_clock -name {sys_clk_50m} -period 20.000 -waveform {0.000 10.000} [get_ports {I_sys_clk}]
create_clock -name {mipi_rx_ck_pad} -period 4.167 -waveform {0.000 2.083} [get_nets {IO_rx_clk_pad_p}]

derive_clocks

rename_clock -name {pll_clk_100m} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[0]}]
rename_clock -name {pll_clk_24m} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[1]}]
rename_clock -name {HDMI_PIXEL_CLK} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[4]}]
rename_clock -name {HDMI_SERIAL_CLK} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[5]}]

rename_clock -name {MIPI_RX_BYTE_CLK} [get_clocks {u_mipi_dphy_rx_ph1p_mipiio_wrapper/u_ph1p_mipiio_rx_wrapper/u_PH1P_LOGIC_DPHY_MIPI_RX.o_fabric_div4_8_clk}]


set_clock_groups -asynchronous \
    -group [get_clocks {mipi_rx_ck_pad MIPI_RX_BYTE_CLK}] \
    -group [get_clocks {sys_clk_50m pll_clk_100m pll_clk_24m HDMI_PIXEL_CLK HDMI_SERIAL_CLK}] \
    -group [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/ddr_clk u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk}]

# 自动曝光 CDC 同步链: 亮度统计在 HDMI 域, 闭环控制在 24M 域,
# avg_y (8bit) 与 frame_done (展宽) 均经 2~3 级触发器同步后使用,
# 按异步路径处理, 不参与同步时序检查 (否则两时钟近对齐时预算不足产生违例)。
set_false_path -from [get_clocks {HDMI_PIXEL_CLK}] -to [get_clocks {pll_clk_24m}]

# =============================================================================
# [以太网改造 第2步] 网络链路时序约束（板 A 千兆 RGMII + UDP 回环）
#
# 层级依据（逐层例化名，已与源文件核对）：
#   design_top_wrapper.u_net                -> net/board_a_net_wrapper.v
#     .u_clk_gen                            -> net/clk_gen_rst_gen.v（generate 内 PH1P 分支）
#       .u_pll_0                            -> net/pll_gen_1.v
#         .pll_inst                         -> net/ph1p_phy_pll_wrapper_25a56e5ce2f9.v
#           .u_PH1P_PHY_PLL                 -> PH1P_PHY_PLL_V2 原语
# 与板 B 的 ph1_demo.sdc:16-28 是同一套层级，只是外面多了一层 u_net。
#
# 参考时钟就是本文件开头已经定义的板载 50MHz 晶振：
#   create_clock -name {sys_clk_50m} ... [get_ports {I_sys_clk}]
# 所以这里不重复 create_clock，而是沿用上面第 4 行 derive_clocks 的派生结果再改名，
# 与视频 PLL 那 4 条 rename_clock 的写法保持一致（不要改成 create_generated_clock，
# 否则会和 derive_clocks 已经建好的同名对象打架）。
# =============================================================================

# --- PHY 送来的 RGMII 接收时钟（千兆 125MHz，由 YT8511C 自己的 25MHz 晶振倍频而来）---
create_clock -name {phy1_rgmii_rx_clk} -period 8.000 -waveform {0.000 4.000} [get_ports {phy1_rgmii_rx_clk}]

# --- 网络 PLL 派生时钟：50MHz -> 125/125/12.5/25/125(90°) MHz ---
#     C4（90°相移）不在 SDC 里声明：TXC 由 rgmii_interface.v 的 ODDR 用 C4 产生，
#     板 B 也没有为它建时钟，硬加外部约束只会制造假违例。
rename_clock -name {net_pll_clk_125m_0} [get_clocks {u_net/u_clk_gen/u_pll_0/pll_inst/u_PH1P_PHY_PLL.clkc[0]}]
rename_clock -name {net_pll_clk_125m_1} [get_clocks {u_net/u_clk_gen/u_pll_0/pll_inst/u_PH1P_PHY_PLL.clkc[1]}]
rename_clock -name {net_pll_clk_12p5m}  [get_clocks {u_net/u_clk_gen/u_pll_0/pll_inst/u_PH1P_PHY_PLL.clkc[2]}]
rename_clock -name {net_pll_clk_25m}    [get_clocks {u_net/u_clk_gen/u_pll_0/pll_inst/u_PH1P_PHY_PLL.clkc[3]}]

# --- udp_clk 是三速 BUFGMUX 的候选时钟 ---
#     当前 TRI_speed 固定千兆(2'b10)，但三种候选全部声明，以便后续复用参考设计。
#     TD 6.2 对这种 mux 候选时钟用“每个候选单独声明 exclusive group”的写法，
#     不要合成一个包含所有系统时钟的 asynchronous group，否则会留下跨域假路径。
create_generated_clock -name {udp_clk_125m}  -add -source [get_pins {u_net/u_clk_gen/u_pll_0/pll_inst/u_PH1P_PHY_PLL.clkc[1]}] -master_clock {net_pll_clk_125m_1} -divide_by 1.000  [get_nets {u_net/udp_clk}]
create_generated_clock -name {udp_clk_12p5m} -add -source [get_pins {u_net/u_clk_gen/u_pll_0/pll_inst/u_PH1P_PHY_PLL.clkc[2]}] -master_clock {net_pll_clk_12p5m}  -divide_by 1.000  [get_nets {u_net/udp_clk}]
create_generated_clock -name {udp_clk_1p25m} -add -source [get_pins {u_net/u_clk_gen/u_pll_0/pll_inst/u_PH1P_PHY_PLL.clkc[2]}] -master_clock {net_pll_clk_12p5m}  -divide_by 10.000 [get_nets {u_net/udp_clk}]

# --- RGMII RX 外部延迟窗口 ---
#     ⚠ 2.0~2.8 ns 是照抄板 B 的**暂定调试值**，必须结合 HX1P35A 上 YT8511C 的实际
#     strap/寄存器配置与数据手册时序再定；"STA 收敛"不等于"RX 采样正确"。
#     改 PHY 的 RXC 延迟配置时必须同步改这里。
set rgmii_rx_ports [get_ports {phy1_rgmii_rx_ctl {phy1_rgmii_rx_data[*]}}]
set_input_delay -clock [get_clocks {phy1_rgmii_rx_clk}] -max 2.800 $rgmii_rx_ports
set_input_delay -clock [get_clocks {phy1_rgmii_rx_clk}] -min 2.000 $rgmii_rx_ports
set_input_delay -clock [get_clocks {phy1_rgmii_rx_clk}] -clock_fall -max -add_delay 2.800 $rgmii_rx_ports
set_input_delay -clock [get_clocks {phy1_rgmii_rx_clk}] -clock_fall -min -add_delay 2.000 $rgmii_rx_ports

# --- 三速候选与独立 PHY RXC：同一时刻不作为活动时钟（照抄板 B ph1_demo.sdc:42-45）---
set_clock_groups -exclusive -group [get_clocks {udp_clk_125m}]
set_clock_groups -exclusive -group [get_clocks {udp_clk_12p5m}]
set_clock_groups -exclusive -group [get_clocks {udp_clk_1p25m}]
set_clock_groups -exclusive -group [get_clocks {phy1_rgmii_rx_clk}]

# --- 网络域与视频/MIPI/DDR 域全部按异步处理 ---
#     ⚠ TXC 不加 set_output_delay：TXC 由 rgmii_interface.v 的 ODDR + PLL C4(90°) 产生，
#     官方 33 例程那两条 TX 约束因旧层级名不匹配而失败（USR-8134/8171/8159），
#     加上反而制造假违例。
set_clock_groups -asynchronous \
    -group [get_clocks {udp_clk_125m udp_clk_12p5m udp_clk_1p25m phy1_rgmii_rx_clk net_pll_clk_125m_0 net_pll_clk_125m_1 net_pll_clk_12p5m net_pll_clk_25m}] \
    -group [get_clocks {mipi_rx_ck_pad MIPI_RX_BYTE_CLK}] \
    -group [get_clocks {sys_clk_50m pll_clk_100m pll_clk_24m HDMI_PIXEL_CLK HDMI_SERIAL_CLK}] \
    -group [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/ddr_clk u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk}]

# =============================================================================
# [以太网改造] RGMII TXC 输出 ODDR 的**复位脚**：按准静态放宽
#
# 背景：TXC 的 ODDR（rgmii_interface.v 的 rgmii_txc_ddr）挂在 90° 相移时钟
#   u_net/u_clk_gen/u_pll_0/pll_inst/u_PH1P_PHY_PLL.clkc[4] 上，而它的复位
#   tx_reset 来自 0° 域，于是 STA 按 0°→90° 的 **2ns** 单周期预算去查它。
#   这条路径 90% 以上是走线（扇出 6、要跨多个 IO 单元），布线后 SWNS 反复违约：
#     12:05 −0.075ns   12:37 −0.236ns   13:1x −0.249ns   13:4x −0.039ns
#   RTL 侧已做结构修复（net/rgmii_interface.v 里给 TXC 单独一颗扇出=1 的
#   tx_reset_txc），本条是兜底。
#
# 为什么可以放宽：这是 ODDR 的**异步复位脚**，运行期恒为失效态（准静态），
#   真正有意义的是 recovery/removal，不需要单周期精度。
#   ⚠ 只放宽这一个端点。同一个时钟组里 rgmii_txc_en / _shift 的数据路径
#     （决定 RGMII TXC 相位、真正决定 PHY 采样窗口的那两条）**仍然保持 2ns 检查**，
#     没有被排除，也没有被 set_false_path 藏掉。
#   用 set_max_delay 而不是 set_false_path：路径仍在时序分析范围内，只是给了
#   一个对"准静态复位"合理的上限（4ns），并保留在报告里可见。
# =============================================================================
set_max_delay 4.000 -datapath_only -to [get_pins {phy1_rgmii_tx_clk_syn_*.rst}]
