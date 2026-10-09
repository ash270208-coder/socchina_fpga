# 板 A 以太网改造方案

> 目标：把「MIPI 摄像头采集 + HDMI 显示主工程」部署在**板 A** 上，让板 A 通过**千兆 RGMII + UDP** 与**板 B** 交互：
> 板 A 送出降采样后的 128×72 RGB 图像帧，板 B 跑 CNN 推理后把**人脸框**回传，板 A 把框画到 HDMI 上。
>
> 板 B 侧已完工（工程：`D:\TD_project\cnn_boardB`），本方案只覆盖板 A。
>
> ⚠️ **本文是方案文档，不含任何已落地的代码改动。** 所有 RTL / 约束 / 工程文件均未被修改。
>
> 事实来源：`cnn_boardB` 的引脚约束、RGMII RTL、板 B 顶层与联调报告；板 A 的
> `phy_1/camera_to_dsi_display_phy.area` 布线报告、`pin.adc`、`camera_to_dsi_display.sdc`。
> 凡属**推断/估算**的数字，正文均单独标注。

---

## 目录

- [0. 结论速览](#0-结论速览)
- [1. 现状盘点](#1-现状盘点)
- [2. 核心障碍：R10 / R11 引脚冲突](#2-核心障碍r10--r11-引脚冲突)
- [3. RGMII 引脚表（照抄板 B）](#3-rgmii-引脚表照抄板-b)
- [4. 复位方案（必做项）](#4-复位方案必做项)
- [5. 合并后的 pin.adc](#5-合并后的-pinadc)
- [6. 需要搬入板 A 的网络资源清单](#6-需要搬入板-a-的网络资源清单)
- [7. 时钟与 PLL 规划](#7-时钟与-pll-规划)
- [8. 数据通路设计](#8-数据通路设计)
- [9. 显示链改动与 vsync 拍数](#9-显示链改动与-vsync-拍数)
- [10. 资源预算](#10-资源预算)
- [11. 板间协议（已由板 B 钉死）](#11-板间协议已由板-b-钉死)
- [12. 实施顺序与验收](#12-实施顺序与验收)
- [13. 风险清单](#13-风险清单)
- [14. 未决事项](#14-未决事项)

---

## 0. 结论速览

| 项 | 结论 |
|---|---|
| **R10 / R11 冲突** | **存在且必须解决**。板 A 现把它们分配给 `I_rst_n` / `O_screen_pwm`，而板上铜线接的是 PHY 的 TX_EN / TXD0 |
| 能否解决 | **能，且解法确定**：删 2 行约束 + 加 13 行约束（照抄板 B 已验证值） |
| 是否要动 PCB | **不用**。板上铜线一根都不动，只改 FPGA 内部如何"认领"这些球 |
| 复位怎么处理 | **必须重做**（现有复位键本来就是摆设）。推荐"内部上电复位 + 双键长按" |
| 需要牺牲按键功能吗 | **不需要**。4 个按键功能全部保留 |
| 会碰视频/显示链路吗 | 不碰 PLL；但显示域要加画框一级，**必须同步改 vsync 拍数** |
| 主要风险 | 逻辑余量薄（slice 已 80.4%）、HDMI 像素域只有 7.1% 时序余量 |

**一句话**：引脚冲突是这件事里最确定、最容易解决的一环；真正的难点是**资源收敛**和 **75 MHz 域的时序余量**。

---

## 1. 现状盘点

### 1.1 板 A 侧（`lab_ex1_mipi_hdmi_SC500_720P+vpp`）

| 项 | 状态 |
|---|---|
| 器件 | PH1P35MDG324（BGA324，TD 6.2） |
| 工程 | `td_project/camera_to_dsi_display.al` |
| 数据流 | SC500(MIPI) → DPHY RX → CSI/RAW10 解包 → ISP(demosaic+AWB) → DDR2 帧缓存 → vpp_top(5 模式) → osd_overlay → delay_osd → hdmi_tx |
| 以太网 RTL | **完全没有**（全仓库 `rgmii`/`mdio`/`eth_phy` 零命中） |
| 板级硬件 | 板载 **YT8511C 千兆 PHY** + **HR911130A** RJ45（内置变压器，支持 Auto-MDIX） |
| 板 A vs 板 B | **同一块板**（HX1P35A）；板卡技术人员已确认 A/B 版电气连接与 FPGA 球位相同，仅螺丝孔不同 |

### 1.2 板 B 侧（`D:\TD_project\cnn_boardB`，已完成）

| 项 | 状态 |
|---|---|
| 顶层 | `src/net/board_b_top.v` —— **纯网口 + CNN 顶层，不含摄像头/HDMI/DDR** |
| 网口链路 | UDP/IP/ARP/ICMP 栈 + TEMAC MAC + RGMII + YT8511C，**已 ping 通、UDP 收发已验证** |
| CNN | `cnn_top` 推理 ~47 ms/帧（CNN 时钟 25 MHz），结果 10/14 字节回包 |
| 关键 RTL | `rgmii_interface.v`、`temac_block.v`、`udp_ip_protocol_stack_merge.enc.v`、`pll_gen_1.v`、`tx_clk_en_gen.v`、`clk_gen_rst_gen.v`、`ram_fifo.v`、`tx/rx_client_fifo.v` |
| 约束 | `src/net/constraints/ph1_demo.adc`、`ph1_demo.sdc`（**已在板 B 上验证**） |
| 参考文档 | `HX1P35A双板以太网级联实施指导.md`（含板 A 侧改造思路与 `video_to_axis.v` 源码） |

### 1.3 板 A 最新布线实测资源（2026-09-26，`phy_1/camera_to_dsi_display_phy.area`）

| 资源 | 用量 | 上限 | 占比 |
|---|---|---|---|
| slice | 17 056 | 21 216 | **80.39 %** |
| LUT6 | 15 668 | 21 216 | 73.85 % |
| 寄存器 | 12 644 | 42 432 | 29.80 % |
| ERAM20K | 47 | 108 | 43.52 % |
| DSP | **38** | 40 | **95.00 %** |
| pad | 60 | 160 | 37.50 % |
| gclk / sclk | 9 / 18 | 32 / 48 | 28 % / 37.5 % |
| PLL | 3 | 6 | 50 % |

**时序（最新布线）**：HDMI 像素域 SWNS **+0.952 ns**（周期 13.333 ns，即余量 **7.1 %**），hold +0.020 ns，违例端点 0。
> 参考 `docs/TIMING_OSD_ANALYSIS.md` §8.1。该文明确警告：再往像素时钟域塞逻辑就可能压垮它。

---

## 2. 核心障碍：R10 / R11 引脚冲突

### 2.1 冲突事实

| FPGA 球 | 板上铜线（网络名） | 连到 | 板 A 约束文件里写的 | 板 B 约束文件里写的 |
|---|---|---|---|---|
| **R10** | `ETHPHY_TX_EN` | YT8511C 的 TX_EN | ❌ `I_rst_n`（输入） | ✅ `phy1_rgmii_tx_ctl` |
| **R11** | `ETHPHY_TXD0` | YT8511C 的 TXD0 | ❌ `O_screen_pwm`（输出，恒 1） | ✅ `phy1_rgmii_tx_data[0]` |

**出处**：`cnn_boardB/src/net/constraints/ph1_demo.adc:26-27`；
板 B 的 `README_STAGE1.md:22`；`HX1P35A双板以太网级联实施指导.md:925-936`（该文已专门列出此冲突的处理步骤）。

### 2.2 冲突的本质

- 板 A 的 `pin.adc` 继承自**不带网口的官方 MIPI→HDMI 例程**。那份例程没有 PHY，于是把"当时空着"的 R10/R11 派给了复位与背光 PWM —— 逻辑自洽，TD 也能综合过（TD 只检查"同一球是否被分配两次"，**不检查与板上真实连线是否一致**）。
- 但 HX1P35A 的 R10/R11 铜线**物理上通到 PHY**。约束与硬件不符，问题只在上板时暴露。

### 2.3 两颗球的"错法"不同（严重程度不同）

| | R10（`I_rst_n`） | R11（`O_screen_pwm`） |
|---|---|---|
| 顶层端口方向 | **input** | **output** |
| FPGA 是否驱动它 | ❌ 不驱动（输入口无驱动器，仅内部弱上拉） | ✅ 驱动，且是**常量 `1'b1`** |
| 对 PHY 的实际影响 | PHY 输入脚看到"悬空偏高"，多数情况**无害** | FPGA 主动把 3.3 V 顶到 PHY 的 TXD0，并同时与自己打开的 `PULLDOWN` 较劲 |
| 主要后果 | **复位功能失效**（该球上没有按键） | **电气错误驱动** + 网口行为异常 |
| 优先级 | 低（系统还能跑） | **高** |

### 2.4 板 A 的复位链现状（关键背景）

```verilog
// design_top_wrapper.v:5      顶层端口
input wire I_rst_n,                 // 低有效，接到 R10

// design_top_wrapper.v:446-448  PLL 例化 —— 唯一的复位入口
PLL u_PLL(
    .refclk ( I_sys_clk ),          // 50 MHz（PLL.v:10 明确 FIN=50MHz）
    .reset  ( ~I_rst_n  ),
    .lock   ( S_pll_lock )
);

// design_top_wrapper.v:232-233  全系统复位 = PLL 锁定信号
assign S_rst_n      = S_pll_lock;
assign S_hdmi_rst_n = S_pll_lock;
```

**链路**：`I_rst_n → PLL.reset → lock → S_rst_n → 全系统`

**这份"复位"实际是怎么工作的**：

1. 上电配置完成后，R10 按约束变成**输入 + 内部上拉**，内部上拉把球缓缓拉高 → `I_rst_n = 1` → `PLL.reset = 0`（释放）；
2. PLL 硬核本身带用户复位功能（`PLL.v:80` 的 `.PLL_USR_RST("ENABLE")`，传入原语 `PH1P_PHY_PLL_V2` 的 `pllreset`），保证从上电确定状态起步；
3. PLL 收敛 → `lock = 1` → `S_rst_n = 1` → 全系统解除复位。

**结论**：
- ✅ 系统能上电启动；
- ❌ **复位按键从未生效** —— R10 这颗球上根本没有按键，没有任何东西能把它拉低；
- ❌ PLL 一旦失锁（`lock=0` → 全系统复位），**没有任何手段能让它重新锁定**，只能断电。

> 这也解释了 `README.md` 2026.9.13 记录的"上板之后按键无法发挥作用"——其中一部分很可能就是这件事。

**因此**：删掉 `I_rst_n = R10` **不会破坏任何现有功能**（那个功能本来就没工作）；但**必须同步补上一个真正可靠的复位源**（见 §4）。

---

## 3. RGMII 引脚表（照抄板 B）

来源：`cnn_boardB/src/net/constraints/ph1_demo.adc`（已在板 B 验证）。
BANK22 VCCIO = 3.3 V，**所有 RGMII 信号用 `LVCMOS33`**。

| 信号（顶层端口名） | FPGA 球 | 方向 | 板 A 现状 |
|---|---|---|---|
| `phy1_rgmii_rx_clk` | V3 | PHY→FPGA | 未分配 ✅ |
| `phy1_rgmii_rx_ctl` | N8 | PHY→FPGA | 未分配 ✅ |
| `phy1_rgmii_rx_data[0]` | N9 | PHY→FPGA | 未分配 ✅ |
| `phy1_rgmii_rx_data[1]` | T7 | PHY→FPGA | 未分配 ✅ |
| `phy1_rgmii_rx_data[2]` | T8 | PHY→FPGA | 未分配 ✅ |
| `phy1_rgmii_rx_data[3]` | T9 | PHY→FPGA | 未分配 ✅ |
| `phy1_rgmii_tx_clk` | U9 | FPGA→PHY | 未分配 ✅ |
| **`phy1_rgmii_tx_ctl`** | **R10** | FPGA→PHY | ❌ **被 `I_rst_n` 占用** |
| **`phy1_rgmii_tx_data[0]`** | **R11** | FPGA→PHY | ❌ **被 `O_screen_pwm` 占用** |
| `phy1_rgmii_tx_data[1]` | P11 | FPGA→PHY | 未分配 ✅ |
| `phy1_rgmii_tx_data[2]` | T10 | FPGA→PHY | 未分配 ✅ |
| `phy1_rgmii_tx_data[3]` | R12 | FPGA→PHY | 未分配 ✅ |
| `phy_reset` | V8 | FPGA→PHY | 未分配 ✅ |

> 注意 TX 组是 `U9/R10/R11/P11/T10/R12`（TX_CLK/TX_EN/TXD0~3），**不是按顺序排的**——TXD0=R11 夹在 TX_EN 与 TXD1 之间，所以 R10、R11 两颗都必须让出来，无法只挪一颗。
>
> 另有两条来自板 B 文档的重要说明：
> - 手册第 8 页的网口引脚表**漏列 RX_CLK**；板源网络图标出 `ETHPHY_RX_CLK = V3`。
> - 手册第 15 页明确 `V2` 是 J2 扩展口 `GPIOA_0`，**不能**当作网口 RX_CLK。

### 3.1 电气配置要点（易错）

| 项 | 说明 |
|---|---|
| IOSTANDARD | 全部 `LVCMOS33`（BANK22 供 3.3 V） |
| TX 组 | `DRIVESTRENGTH = 16`、`SLEWRATE = FAST` |
| RX 组 | `PULLTYPE = NONE` |
| **R11 必须去掉 `PULLTYPE = PULLDOWN`** | 那是 PWM 输出的旧配置；RGMII 数据脚按板 B 写法**不加上下拉**，多一个下拉会吃摆幅、破坏眼图 |
| MDIO | **不需要**。YT8511C 靠 strap 自举（PHY 地址 strap = `{LED_ACT=1, RXD1=0, RXD0=0}` = `0b100` = 4），本方案不做 MDIO 配置 |

### 3.2 时钟如何对齐（板 B 已实现，照搬）

- **发送侧**：PLL 产出两路 125 MHz —— 0°（`temac_clk`）走数据/控制经 ODDR 双沿输出；90°相移（`temac_clk90`）经 ODDR 产生 TXC。时钟边沿相对数据错开 2 ns，PHY 在时钟边沿采到的数据正好在眼图中央。**不需要 `OUTDEL`。**
- **接收侧**：YT8511C 内部默认使能 RXC 延迟（千兆 1.8 ns，strap `LED_10_100` 默认上拉），FPGA 不使用 IDELAY；`phy1_rgmii_rx_clk` 先经 `rgmii_interface.v` 内的 `BUFGMUX` 进入一条明确的 PH1P 全局时钟，再同时驱动 IDDR 与 TEMAC RX 逻辑，避免 RXC 在局部/全局路由间分叉造成 hold 偏斜。

---

## 4. 复位方案（必做项）

### 4.1 为什么必须重做

`I_rst_n` 是 PLL 唯一的复位来源，删掉它的约束后必须补上。而**现在这个来源本身也不可靠**（悬空球 + 弱上拉，且运行中完全无法复位）。

### 4.2 推荐方案：内部上电复位 + 双键长按

**优点**：不占用任何按键球；不动 `pin.adc` 的按键部分；上电复位可靠；运行中可手动复位。

#### 4.2.1 上电复位 + 同步释放（可直接用的 RTL 骨架）

```verilog
//=============================================================================
// PLL 上电复位：上电后从确定状态释放，避免依赖悬空引脚的弱上拉。
// 时钟源：I_sys_clk（50 MHz，一直存在，不依赖 PLL 自身输出）。
// 时序：异步复位 + 同步释放，两个不同时钟域的触发器，避免亚稳态。
//=============================================================================
module pll_por #(
    parameter POR_CYCLES = 32'd500_000      // 50MHz × 10ms
)(
    input  wire clk,        // I_sys_clk, 无复位
    input  wire ext_arst_n, // 额外复位请求（双键长按），低有效；不用则接 1'b1
    output wire pll_rst     // 接 PLL u_PLL 的 .reset（高有效）
);

    reg [31:0] cnt = 32'd0;
    always @(posedge clk)
        if (cnt != POR_CYCLES) cnt <= cnt + 32'd1;

    wire por_release = (cnt == POR_CYCLES);

    // 两域同步释放；ext_arst_n=0 时立即拉回复位
    reg s1, s2;
    always @(posedge clk or negedge ext_arst_n)
        if (!ext_arst_n) {s2, s1} <= 2'b00;
        else             {s2, s1} <= {s1, por_release & 1'b1};

    assign pll_rst = ~s2;
endmodule
```

**接线**（替换原 `PLL u_PLL` 的 `.reset` 连接）：

```verilog
wire S_por_rst;                    // 上电复位
wire S_soft_arst_n;                // 可选：双键长按产生的复位请求

pll_por u_pll_por (
    .clk       ( I_sys_clk    ),
    .ext_arst_n( S_soft_arst_n ),
    .pll_rst   ( S_por_rst    )
);

PLL u_PLL(
    .refclk ( I_sys_clk ),
    .reset  ( S_por_rst ),         // ← 由内部复位逻辑驱动，取代 pin 上的 I_rst_n
    .lock   ( S_pll_lock )
);
```

> 注意 `pll_por` 必须跑在 **`I_sys_clk`** 上，**不能**跑在 PLL 自己的输出时钟上（自举依赖）。

#### 4.2.2 双键长按（可选，运行中复位）

```verilog
// 在 pll_clk_24m（23.81MHz，PLL 失锁时需注意：该时钟由 PLL 产生）
// 若要求"PLL 失锁后也能触发"，改用 I_sys_clk（50MHz）域。
// 你工程已有 key_remove_shakes 去抖模块可直接复用。
localparam [25:0] BOTH_LOW_MAX = 26'd12_000_000;  // 50MHz × ~0.24s
reg [25:0] both_cnt = 26'd0;
wire both_low = ~I_button[0] & ~I_button[1];      // D5 + A9 同时按下（低有效）

always @(posedge I_sys_clk)
    if (!both_low)             both_cnt <= 26'd0;
    else if (both_cnt != BOTH_LOW_MAX) both_cnt <= both_cnt + 26'd1;

assign S_soft_arst_n = (both_cnt == BOTH_LOW_MAX) ? 1'b0 : 1'b1;
```

### 4.3 备选方案：把一个按键球给复位

若坚持要物理复位键，从现有 4 个按键球里让一个出来（代价：失去该键当前功能）。

> ⚠️ **不推荐**的做法：直接用 `I_button[3]`（C7）当复位。会丢掉 C7 的功能；且若用户**按住该键上电**，PLL 永远锁不住（黑屏），是很难查的坑。

### 4.4 按键映射（推荐方案下的最终分配）

| 球 | 用途 | 变化 |
|---|---|---|
| D5 | 曝光 − | 不变 |
| A9 | 曝光 + | 不变 |
| B9 | 显示模式切换（5 档） | 不变 |
| C7 | 自动 / 手动曝光切换 | 不变 |
| D5 + A9 同按 ~0.24 s | **软复位**（可选） | 新增 |
| — | **上电复位**（内部产生） | 新增 |

**四个按键的功能一个都不丢。**

---

## 5. 合并后的 pin.adc

### 5.1 改动方式：**合并，不是覆盖**

> 🚨 **绝对不要用板 B 的 `ph1_demo.adc` 整份覆盖板 A 的 `pin.adc`。**
> 板 B 的约束文件**不含** TMDS 四路输出，也**不含** `I_button[2]/[3]`（B9/C7）。
> 整份覆盖会立刻丢掉 HDMI 输出和两个按键的引脚定义。

正确做法：保留板 A 原有内容，**删 2 行、加 13 行**。

### 5.2 完整合并结果（`user_source/constraints_source/pin.adc`）

```tcl
#===== 系统时钟（板载 50MHz 晶振 C4）=====
set_pin_assignment  { I_sys_clk }       { LOCATION = C4; IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }

#===== 复位 =====
# 原第 3 行 { I_rst_n } = R10 已删除（R10 让给 RGMII TX_EN）；
# 复位改为内部上电复位 + 双键长按，不再占用任何引脚。
# 若坚持要物理复位键，在此补一行指向空闲球（须先与实物原理图核对）。

#===== 摄像头 I2C / 时钟 / 复位（不变）=====
set_pin_assignment  { O_cam_scl }       { LOCATION = K3; IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 8; PULLTYPE = PULLUP; }
set_pin_assignment  { IO_cam_sda }      { LOCATION = J3; IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 8; PULLTYPE = PULLUP; }
set_pin_assignment  { O_cam_24m }       { LOCATION = L3; IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 8; PULLTYPE = PULLUP; }
set_pin_assignment  { O_cam_rst }       { LOCATION = L2; IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 8; PULLTYPE = PULLUP; }

#===== 按键（4 个，全部保留）=====
set_pin_assignment  { I_button[0] }     { LOCATION = D5; IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 8; PULLTYPE = PULLUP; }
set_pin_assignment  { I_button[1] }     { LOCATION = A9; IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 8; PULLTYPE = PULLUP; }
set_pin_assignment  { I_button[2] }     { LOCATION = B9; IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 8; PULLTYPE = PULLUP; }
set_pin_assignment  { I_button[3] }     { LOCATION = C7; IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 8; PULLTYPE = PULLUP; }

#===== HDMI TMDS（不变）=====
set_pin_assignment  { O_tmds_ch0_p }    { LOCATION = G16; IOSTANDARD = TMDS33; PULLTYPE = NONE; }
set_pin_assignment  { O_tmds_ch1_p }    { LOCATION = F17; IOSTANDARD = TMDS33; PULLTYPE = NONE; }
set_pin_assignment  { O_tmds_ch2_p }    { LOCATION = H14; IOSTANDARD = TMDS33; PULLTYPE = NONE; }
set_pin_assignment  { O_tmds_clk_p }    { LOCATION = C17; IOSTANDARD = TMDS33; PULLTYPE = NONE; }

#===== 原第 16 行 { O_screen_pwm } = R11 已删除（R11 让给 RGMII TXD0）=====
# 外部 HDMI 显示器不需要 FPGA 提供背光 PWM；如需保留，迁到 D10/E10/C6/D6 之一。

#===== RGMII 接收（PHY -> FPGA）—— 新增，照抄板 B =====
set_pin_assignment  { phy1_rgmii_rx_clk }     { LOCATION = V3;  IOSTANDARD = LVCMOS33; PULLTYPE = NONE; }
set_pin_assignment  { phy1_rgmii_rx_ctl }     { LOCATION = N8;  IOSTANDARD = LVCMOS33; PULLTYPE = NONE; }
set_pin_assignment  { phy1_rgmii_rx_data[0] } { LOCATION = N9;  IOSTANDARD = LVCMOS33; PULLTYPE = NONE; }
set_pin_assignment  { phy1_rgmii_rx_data[1] } { LOCATION = T7;  IOSTANDARD = LVCMOS33; PULLTYPE = NONE; }
set_pin_assignment  { phy1_rgmii_rx_data[2] } { LOCATION = T8;  IOSTANDARD = LVCMOS33; PULLTYPE = NONE; }
set_pin_assignment  { phy1_rgmii_rx_data[3] } { LOCATION = T9;  IOSTANDARD = LVCMOS33; PULLTYPE = NONE; }

#===== RGMII 发送（FPGA -> PHY）—— 新增，R10/R11 在此 =====
set_pin_assignment  { phy1_rgmii_tx_clk }     { LOCATION = U9;  IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 16; SLEWRATE = FAST; }
set_pin_assignment  { phy1_rgmii_tx_ctl }     { LOCATION = R10; IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 16; SLEWRATE = FAST; }
set_pin_assignment  { phy1_rgmii_tx_data[0] } { LOCATION = R11; IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 16; SLEWRATE = FAST; }
set_pin_assignment  { phy1_rgmii_tx_data[1] } { LOCATION = P11; IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 16; SLEWRATE = FAST; }
set_pin_assignment  { phy1_rgmii_tx_data[2] } { LOCATION = T10; IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 16; SLEWRATE = FAST; }
set_pin_assignment  { phy1_rgmii_tx_data[3] } { LOCATION = R12; IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 16; SLEWRATE = FAST; }

#===== PHY 硬件复位（新增）=====
set_pin_assignment  { phy_reset }             { LOCATION = V8;  IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 16; SLEWRATE = FAST; }
```

### 5.3 顶层端口增删

| 动作 | 端口 | 说明 |
|---|---|---|
| **删** | `input wire I_rst_n` | 或保留名字但不再约束到 R10，改为内部信号 |
| **删** | `output wire O_screen_pwm` | 同时删掉 `assign O_screen_pwm = 1'b1;`（`design_top_wrapper.v:228`） |
| **增** | `input  wire phy1_rgmii_rx_clk` | |
| **增** | `input  wire phy1_rgmii_rx_ctl` | |
| **增** | `input  [3:0] phy1_rgmii_rx_data` | |
| **增** | `output wire phy1_rgmii_tx_clk` | |
| **增** | `output wire phy1_rgmii_tx_ctl` | **→ R10** |
| **增** | `output [3:0] phy1_rgmii_tx_data` | **bit0 → R11** |
| **增** | `output wire phy_reset` | |

---

## 6. 需要搬入板 A 的网络资源清单

从 `D:\TD_project\cnn_boardB` 复制到板 A 工程的 `user_source/hdl_source/net/`：

| 类别 | 文件 | 说明 |
|---|---|---|
| RGMII 物理层 | `rgmii_interface.v`、`ODDR.v`、`IDDR.v`、`BUFGMUX.v` | **必需** |
| 时钟 | `pll_gen_1.v`、`ph1p_phy_pll_wrapper_25a56e5ce2f9.v`、`clk_gen_rst_gen.v`、`div_clk_gen.v`、`temac_clk_gen.v`、`tx_clk_en_gen.v` | `tx_clk_en_gen` 负责 TX_CLK 的时钟使能门控，**必须一起搬** |
| MAC | `temac_block.v` + IP `TEMAC_CORE.ipc` | TEMAC 是 TD IP 生成器产物 |
| 协议栈 | `udp_ip_protocol_stack_merge.enc.v` | **加密交付的 IP，不能改，只能例化** |
| FIFO | `tx_client_fifo.v`、`rx_client_fifo.v`、`ram_fifo.v`、`RAMB16_S9_S9.v` | 跨时钟域缓冲 |
| 降采样 | `cnn_ds10.v`（板 B `src/cnn_ds10.v`） | **现成的 ÷10 三通道 10×10 块平均**，8/8 tb 已过；只需取帧功能 |
| 应用层 | `tx_frame_sender`（20 包发送）、`rx_result_parser`（解析 10 字节回包） | 参考 `docs/BOARD_SPLIT.md` §5 与实施指导 §7 |

**工程侧**：把上述 `.v` 加入 `camera_to_dsi_display.al` 的编译列表；复制 `TEMAC_CORE` IP 目录到工程 IP 目录并在 TD 中确认路径。

> 板 B 侧**不需要任何改动**。

---

## 7. 时钟与 PLL 规划

### 7.1 原则：新增独立 PLL，不碰视频 PLL

板 B 的 `pll_gen_1.v`：**50 MHz 输入 → 125 / 125 / 12.5 / 25 / 125(90°) MHz**，与视频 PLL 完全独立。

| PLL | 用途 | 现状 |
|---|---|---|
| `u_PLL`（`PLL.v`） | 100 M / 23.81 M / 75 M / 375 M —— 视频与 HDMI | 不动 |
| DDR PHY 内部 PLL0/1 | DDR2 | 不动 |
| **新增 `pll_gen_1`** | **125 M ×2 + 12.5 M + 25 M（网络）** | 新增 |

PLL 用量 3 → 4（上限 6）✅

### 7.2 时钟域划分

| 时钟域 | 频率 | 内容 |
|---|---|---|
| `I_sys_clk` | 50 MHz | 复位发生器（`pll_por`）、双键长按 |
| `HDMI_PIXEL_CLK` | 75 MHz | vpp / OSD / 画框 / hdmi_tx |
| `MIPI_RX_BYTE_CLK` | 60 MHz | MIPI / ISP |
| `ddr usr_clk` | 66.7 MHz | DDR 读写 |
| `pll_clk_24m` | 23.81 MHz | 摄像头配置 / 自动曝光 / 按键去抖 |
| **`phy1_rgmii_rx_clk`** | **125 MHz（千兆）** | RGMII 接收、TEMAC RX |
| **`udp_clk`** | **125 MHz** | TEMAC TX、UDP 栈、组包、帧发送 |

### 7.3 SDC 增补（`camera_to_dsi_display.sdc`）

**板 A 现有内容不动**（`sys_clk_50m` = 20 ns 周期是正确的，对应 50 MHz 晶振）。**新增**：

```tcl
# --- 新增：PHY 接收时钟 ---
create_clock -name {phy1_rgmii_rx_clk} -period 8 -waveform {0 4} [get_ports {phy1_rgmii_rx_clk}]

# --- 新增：网络 PLL 派生时钟（层级名以实际为准）---
create_generated_clock -name {pll_inst_125M_0} -source [get_ports {I_sys_clk}] -master_clock {sys_clk_50m} -multiply_by 2.500 [get_pins {u_net_pll/.../u_PH1P_PHY_PLL.clkc[0]}]
# （其余派生时钟照抄 cnn_boardB/src/net/constraints/ph1_demo.sdc:17-28）

# --- 新增：RGMII RX 外部延迟窗口（暂定值，见风险 §13）---
set rgmii_rx_ports [get_ports {phy1_rgmii_rx_ctl {phy1_rgmii_rx_data[*]}}]
set_input_delay -clock [get_clocks {phy1_rgmii_rx_clk}] -max 2.800 $rgmii_rx_ports
set_input_delay -clock [get_clocks {phy1_rgmii_rx_clk}] -min 2.000 $rgmii_rx_ports
set_input_delay -clock [get_clocks {phy1_rgmii_rx_clk}] -clock_fall -max -add_delay 2.800 $rgmii_rx_ports
set_input_delay -clock [get_clocks {phy1_rgmii_rx_clk}] -clock_fall -min -add_delay 2.000 $rgmii_rx_ports

# --- 新增：跨时钟域按异步处理 ---
set_clock_groups -exclusive -group [get_clocks {phy1_rgmii_rx_clk}]
set_clock_groups -exclusive -group [get_clocks {udp_clk_125m}]
```

> 板 B 的 SDC 里有三条重要经验（`ph1_demo.sdc:1-10, 30-34, 41-45`）：
> 1. 官方 33 例程日志里的 TX generated-clock / `set_output_delay` 命令**因旧层级名不匹配而失败**（`USR-8134/8171/8159`），**不要照抄**；TXC 由 `rgmii_interface.v` 的 ODDR + PLL C4(90°) 产生，错误的 TX 外部约束反而制造假违例。
> 2. 三速 BUFGMUX 候选时钟在 TD 6.2 下要用**"每个候选单独声明 exclusive group"**的写法，不要合成一个 asynchronous group（否则留下跨域假路径）。
> 3. RGMII RX 输入延迟 2.0–2.8 ns 是**暂定调试值**，必须结合 YT8511C 实际 strap/寄存器配置与数据手册再定；**不能凭 STA 收敛就认定 RX 采样正确**。

---

## 8. 数据通路设计

### 8.1 抽取点：**必须在画框之前、OSD 之前的显示域 RGB**

沿用板 B 的结论（`docs/FPGA_CNN实现方案.md` §4.4）：

- CNN 的 RGB 输入从 **`vpp` 的 mux 输出（`I_disp_tdata`，画框之前）** 抽取；
- 它是**伽马后的显示域 RGB**，与训练数据（sRGB 照片）分布一致；
- 位于 `osd_box_drawer` 之前 → **CNN 永远不会看到自己画的绿框**，杜绝"框锁死绿框"的正反馈。

> ⚠️ **这是最容易踩且最难查的坑**：板 A 在 2026.9.14 加了 γ=2.2 伽马校正。
> **绝不能送线性域数据给板 B** —— 那会让板 B 的网络精度大幅下降。

### 8.2 数据通路

```
hdmi_mixer / vpp mux 输出（75MHz 域，伽马后 RGB888）
        │  ★ 像素域只做"装箱"，不做运算
        ▼
  video_to_axis（pclk 域：de/vs → tvalid/tuser/tlast）
        │
        ▼
  cnn_ds10（÷10 三通道 10×10 块平均 → 128×72×3）
        │
        ▼
  帧门控（每 6 帧发 1 帧 ≈ 10 fps）
        │
        ▼
  img_afifo（TD 异步 FIFO，8bit × 4096 ≈ 2 块 ERAM，Show-Ahead 模式）
        │  ← 唯一一次跨时钟域
        ▼
  tx_frame_sender（udp_clk 域：拆 20 个 UDP 包发送）
        │
        ▼
  udp_ip_protocol_stack → TEMAC → rgmii_interface → YT8511C → 网线 → 板 B
```

**反向**：

```
网线 → 板 B 的 10 字节结果包
        ▼
  udp_ip_protocol_stack（RX）→ rx_result_parser（解析 AA 55 … 0D）
        ▼
  框坐标落到寄存器（udp_clk 域）
        ▼
  2~3 级同步器 → 像素域
        ▼
  ★ 场消隐期整帧锁存（防撕裂/闪烁）
        ▼
  osd_box_drawer（SCALE_FACTOR = 10，128×72 → 1280×720）
        ▼
  delay_osd → hdmi_tx → 显示器
```

### 8.3 关键纪律

| 纪律 | 原因 |
|---|---|
| **像素域（75 MHz）只做装箱/计数，不做块平均** | 该域只剩 +0.952 ns 余量（7.1 %） |
| 跨域**只穿一次**异步 FIFO | 减少 CDC 风险与约束复杂度 |
| `cnn_ds10` 的排空节奏放宽到 4 拍/块 | 板 B 坑 14：每拍 1 块连续排空会与下游 3 拍/块的握手不匹配而丢块 |
| 帧间需保留消隐 | 板 B 坑 15：背靠背无消隐会让下一帧 tuser 打断末条纹排空，每帧丢最后一行块 |

---

## 9. 显示链改动与 vsync 拍数

### 9.1 要加回画框

`osd_box_drawer.v` 现在**只在 `.al` 的源文件列表里登记**（第 391 行），**已不参与综合**。本次需要重新例化。

### 9.2 ⚠️ vsync 拍数必须同步修改

`BOARD_SPLIT.md:78-82` 的血泪教训：

> 显示通路的延迟链原本是 16 拍算法 + **1 拍画框 OSD** + 2 拍 Logo OSD + 2 拍延迟 OSD = **21 拍**。
> 人脸检测解绑后那 1 拍消失，DE 链路变成 20 拍；若不同步修改，`hdmi_tx` 拿到的 vs/de 相位会错 1 拍（**画面横向偏移 1 像素**）。

**板 A 当前状态**（`OSD_TIMING_OPTIMIZATION.md` / `TIMING_OSD_ANALYSIS.md` §8）：

```
现存：22 拍算法（卡通 1+21）+ 2 拍 Logo/模式 OSD + 2 拍延迟 OSD = 26 拍 vsync 对齐
本次加画框（osd_box_drawer 是寄存输出，+1 拍）：
      22 + 1（画框）+ 2 + 2 = 27 拍
```

**动作**：`design_top_wrapper.v` 中 `S_vsync_dly` 由 26 拍改为 **27 拍**（`reg [26:0] S_vsync_dly` + `S_vsync_dly[26]`）。

> 并请在代码里保留/更新那句警示注释：**今后在 `vpp → osd_overlay → delay_osd` 这条 DE 链路上增删寄存器级，必须同步改这个拍数。**

### 9.3 画框坐标的异步处理

框从以太网异步到达，必须：

1. **2~3 级同步器**过到像素时钟域（可用 `signal_delay.v` 或标准两级同步）；
2. **场消隐期整帧锁存**：像素域只读一组稳定寄存器，切换发生在 vsync 期间 → **无撕裂、无闪烁**。

---

## 10. 资源预算

### 10.1 板 A 余量

| 资源 | 已用 | 上限 | 余量 |
|---|---|---|---|
| slice | 17 056 | 21 216 | **4 160** |
| LUT6 | 15 668 | 21 216 | 5 548 |
| 寄存器 | 12 644 | 42 432 | 29 788 |
| ERAM20K | 47 | 108 | **61** |
| DSP | 38 | 40 | **2** |
| pad | 60 | 160 | 100 |
| PLL | 3 | 6 | 3 |
| gclk / sclk | 9 / 18 | 32 / 48 | 23 / 30 |

### 10.2 网络部分需求（板 B 实测 / 估算）

| 项 | 数值 | 性质 |
|---|---|---|
| ERAM | **33 块** | **实测**（板 B 阶段一门级综合 `README_STAGE1.md:31`） |
| PLL | 1 | 实测 |
| GCLK | 3 | 实测 |
| IO | 20（板 B 顶层） | 实测；板 A 并入后约 15 个新增 |
| DSP | **0** | 网络链路不需要 DSP |
| slice / CLB | **~1 500 ~ 2 500** | **估算**（需板 A 自行综合确认） |
| `img_afifo` | ~2 块 ERAM | 8 bit × 4096 |

### 10.3 合并后预估

| 资源 | 预估 | 上限 | 判断 |
|---|---|---|---|
| ERAM | 47 + 33 + 2 ≈ **82** | 108 | ✅ 够（约 76 %） |
| DSP | 38 + 0 = **38** | 40 | ✅ 够 |
| PLL | 3 + 1 = **4** | 6 | ✅ 够 |
| slice | 17 056 + 1 500~2 500 ≈ **18 600 ~ 19 600** | 21 216 | ⚠️ **88 % ~ 92 %，很紧** |

> **结论**：ERAM / DSP / PLL 都够，**瓶颈是逻辑（slice）和时序**。
> 若综合后 slice 超限，可回收的方向（按性价比）：
> 1. `anlogic_logo_rom` 的 1 984 个 LUT 组合表 → 改 ERAM ROM（`TIMING_OSD_ANALYSIS.md` §5 方案 B），约 32 块 ERAM；
> 2. `awb` 的除法器（754 LUT + 8 DSP）→ 改移位减 / LUT 除法；
> 3. `cnn_ds10` 的 128 选 1 排空 MUX（板 B 记录 logic 9 623）→ 分块排空或改线缓冲结构。

---

## 11. 板间协议（已由板 B 钉死）

### 11.1 网络参数

| 项 | 板 A | 板 B |
|---|---|---|
| IP | `192.168.240.1`（`32'hC0A8F001`） | `192.168.240.2`（`32'hC0A8F002`） |
| UDP 端口 | 1 | 2 |
| MAC | 本地管理单播（如 `02:00:00:00:24:01`） | `02:00:00:00:24:02` |
| 对端 IP / 端口 | `.2` / 2 | `.1` / 1 |

> 板 B 当前 `board_b_top.v` 使用的本地 MAC 为 `48'h020000002402`。
> ⚠️ 不要使用 `01:...` 开头的组播地址作为单播源地址（板 B 文档已指出该错误）。

### 11.2 下行图像包（板 A → 板 B）

一帧 27 648 字节拆 **20 个 UDP 包**：

| seq | UDP payload 长度 | 内容 |
|---|---|---|
| 0 – 18 | 1 402 字节 | 字节[0:2] = seq（大端 u16，高字节固定 `0x00`）；字节[2:1402] = 1 400 个图像字节 |
| 19 | 1 050 字节 | 字节[0:2] = seq；字节[2:1050] = 1 048 个图像字节 |

- **校验**：`19 × 1400 + 1048 = 27 648` ✓
- **图像字节排列**：按行扫描，每像素 3 字节顺序 **R、G、B**（对应 `cnn_top` 的 `I_tdata = {R,G,B}`）
- 板 B 按 seq 写到帧缓存地址 `seq × 1400 + 包内偏移`；20 包全到才启动一帧 → **天然容忍乱序**；丢包则本帧不启动，等下一帧

### 11.3 上行结果包（板 B → 板 A）

固定 **10 字节**（板 B 调试版为 14 字节，**前 10 字节向后兼容**）：

| 偏移 | 内容 |
|---|---|
| 0 | 帧头 `0xAA` |
| 1 | 帧头 `0x55` |
| 2 | valid（有结果固定 `0x01`） |
| 3 | x1（小图坐标，0–127） |
| 4 | y1（0–71） |
| 5 | w（框宽） |
| 6 | h（框高） |
| 7 | score[15:8] |
| 8 | score[7:0] |
| 9 | 帧尾 `0x0D` |

> 板 B 实测回包示例：`AA 55 01 47 00 1E 1E 0C 25 … 0D`
> → x1=71, y1=0, w=30, h=30, score=3109(0x0C25)

### 11.4 节奏

- 板 A **每 6 帧发 1 帧**（≈10 fps）
- 板 B `cnn_top` 推理约 **47 ms/帧**（CNN 时钟 25 MHz）；发得比它快也没关系 —— **板 A 有 15 帧框保持机制，不会闪没**
- 带宽：27 648 B/帧 × 10 fps ≈ 276 KB/s ≈ **2.2 Mbps**，相对千兆链路毫无压力

---

## 12. 实施顺序与验收

> 原则：**每一步都能单独验收，绝不跨步。**

| 步 | 内容 | 验收标准 |
|---|---|---|
| **0** | 备份板 A 工程；确认 TD 器件为 `PH1P35MDG324` | 备份可打开；原工程未被破坏 |
| **1** | **先只改引脚 + 复位**：删 `I_rst_n`/`O_screen_pwm` 约束、加 RGMII 完整约束、加 `pll_por` | ① TD 无重复分配报错；② 综合通过；③ **上板后视频链路（5 模式、OSD）与改动前逐像素一致**；④ 按键四个功能正常 |
| **2** | 搬入网络 RTL + `TEMAC_CORE` IP + 新增独立 PLL；只做 **UDP 回环**（不含图像） | 电脑网卡设 `192.168.240.10`，`ping 192.168.240.1` 通；NetAssist 发什么收什么 |
| **3** | 加 `video_to_axis` + `cnn_ds10` + 帧门控 + `img_afifo` + `tx_frame_sender`（**电脑当板 B**） | 电脑收到 20 包、拼出 128×72 图，与显示器上的画面降采样后**目视一致** |
| **4** | 加 `rx_result_parser` + 画框 + vsync 改 27 拍（**电脑发假框**） | 电脑发 10 字节假框 → HDMI 上绿框出现在正确位置；**画面不横向偏移** |
| **5** | 双板网线直连联调 | 真人出镜，HDMI 绿框实时套脸 |

### 12.1 每步的回归检查（不能省）

- [ ] 视频 5 种显示模式均正常，无横向偏移
- [ ] OSD（Logo / 模式文字 / DELAY）位置与内容正确
- [ ] 4 个按键功能完整（曝光−/曝光+/模式切换/自动手动切换）
- [ ] 摄像头 I²C 配置正常（画面不黑、不偏绿）
- [ ] 占用 `pin.adc` 的球无重复分配

---

## 13. 风险清单

| # | 风险 | 影响 | 应对 |
|---|---|---|---|
| 1 | **用板 B 的 `ph1_demo.adc` 整份覆盖** | 立刻丢掉 TMDS 与 `I_button[2]/[3]` | **必须合并**，只删 2 行加 13 行（§5） |
| 2 | **R11 忘记去掉 `PULLTYPE = PULLDOWN`** | 破坏 RGMII 眼图 | 按 §3.1 检查 |
| 3 | **75 MHz 像素域余量只有 7.1 %** | 加逻辑后时序崩 | 像素域只做装箱；必要时先做 OSD 流水加固 |
| 4 | **vsync 拍数没跟着改** | 画面横向偏移 1 像素 | §9.2；两处加警示注释 |
| 5 | **送线性域数据给板 B** | 板 B 检不出人脸（且极难查） | §8.1：必须取伽马后的显示域 RGB |
| 6 | RGMII RX 输入延迟是**暂定值** | 可能时通时不通 | 结合 YT8511C 实际 strap/配置与数据手册再定；不能凭 STA 收敛当正确 |
| 7 | 忘记搬 `tx_clk_en_gen.v` | PLL 未锁定时 TX_CLK 输出毛刺，PHY 收到垃圾帧 | §6：必搬 |
| 8 | slice 预估 88 %~92 % | 可能布局失败（板 B 曾报 `PHY-9009`） | 见 §10.3 的回收方向 |
| 9 | 跨域假违例 | 综合报 WNS 负值 | 照板 B 的 SDC 写法（exclusive group / false path） |
| 10 | 板 B 的组包对"分片"敏感 | 板 A 用 MATLAB 发送会被拆包导致误判 | **板 A 是硬件发送整包，无此问题**；但用 PC 做阶段性验收时要用整包发送器（板 B 复盘报告 `板B调试复盘.md`） |

---

## 14. 未决事项

| # | 事项 | 需要谁定 |
|---|---|---|
| 1 | 复位最终选型：**① 内部上电复位（推荐）/ ①+② 双键长按 / ③ 占用一个按键球** | 需拍板（§4） |
| 2 | 板 A 是否需要 `O_screen_pwm` 保留（外部 HDMI 显示器不需要） | 已可删；若要保留则迁到 D10/E10/C6/D6 之一 |
| 3 | `cnn_ds10` 取帧位置：`vpp` mux 输出 vs `hdmi_mixer` 输出 | 建议按 §8.1 取 vpp mux 输出（画框之前、伽马后） |
| 4 | 网络部分实际 slice 占用 | 需板 A 综合一次后回填（替换 §10.2 的估算值） |
| 5 | 板 B 当前 bit 是否已包含真实框输出（非调试值） | 需与板 B 负责人确认（见 `板B联调诊断报告_20261006.md`） |

---

## 附录 A：相关文件与出处

| 内容 | 路径 |
|---|---|
| 板 B 引脚约束（已验证） | `D:\TD_project\cnn_boardB\src\net\constraints\ph1_demo.adc` |
| 板 B 时序约束（已验证） | `D:\TD_project\cnn_boardB\src\net\constraints\ph1_demo.sdc` |
| 板 B RGMII 实现 | `D:\TD_project\cnn_boardB\src\net\rgmii_interface.v` |
| 板 B 顶层 | `D:\TD_project\cnn_boardB\src\net\board_b_top.v` |
| 板 B 阶段一移植记录 | `D:\TD_project\cnn_boardB\src\net\README_STAGE1.md` |
| 双板实施指导（含板 A 改造 §7） | `D:\TD_project\cnn_boardB\HX1P35A双板以太网级联实施指导.md` |
| 板 B 联网调试复盘（方法论） | `D:\TD_project\cnn_boardB\doc\板B调试复盘.md` |
| 板 A 引脚约束 | `.../user_source/constraints_source/pin.adc` |
| 板 A 时序约束 | `.../td_project/camera_to_dsi_display.sdc` |
| 板 A PLL 配置 | `.../user_source/ip_source/PLL/PLL.v` |
| 板 A 布线资源报告 | `.../td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display_phy.area` |
| OSD 时序分析与加固 | [`docs/TIMING_OSD_ANALYSIS.md`](TIMING_OSD_ANALYSIS.md) |
| 板 A/B 分工与回退 | [`docs/BOARD_SPLIT.md`](BOARD_SPLIT.md) |
| CNN 部署施工图 | [`docs/FPGA_CNN实现方案.md`](FPGA_CNN实现方案.md) |
| ROM / 查表数据说明 | [`rom_data/README.md`](../rom_data/README.md) |

## 附录 B：本文档中"实测"与"估算"的区分

| 数据 | 性质 |
|---|---|
| 板 A 全部资源数字、SWNS/STNS | **实测**（`phy_1/*.area`、`*.qor`、`*.timing`） |
| 板 B 阶段一：33 ERAM / 1 PLL / 3 GCLK / 20 IO / WNS +1.783 ns | **实测**（门级综合） |
| 板 B：CNN 推理 ~47 ms、slice 65.4 %、ERAM 97 %、DSP 40/40 | **实测**（`板B联调诊断报告_20261006.md`） |
| RGMII 引脚映射与电气配置 | **实测**（板 B 已在实物上验证） |
| 板 A 网络部分 slice 占用 **1 500~2 500** | **估算** —— 待板 A 综合后回填 |
| RGMII RX 输入延迟 2.0~2.8 ns | **暂定调试值** —— 需结合 PHY 配置复核 |
