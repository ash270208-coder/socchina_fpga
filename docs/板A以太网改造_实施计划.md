# 板 A 以太网改造 · 实施计划（交给下一个 AI 直接执行）

> **本文目的**：把 2026-10-09 那次失败尝试的教训固化下来，让下一个 AI 少走弯路、且**不重复踩同样的坑**。
>
> **约定**：凡标 **[你复制]** 的，由人手工复制/操作；标 **[AI 写]** 的，由 AI 用文件工具写。
>
> **当前状态**：工程已恢复为「改造前原点」。第 1 步的成果**完好保存在 git 提交 `b2da00a` 里**，第 2 步尚未开始。

---

## 0. 目录结构（三层，名字都像，最容易搞错）

```
D:\TD_project\lab_ex1_mipi_hdmi_SC500_720P+vpp              ← ① git 仓库根（唯一 .git 在这）
├── docs\
├── LBP\  matlab\  rom_data\  src\  ...
└── lab_ex1_mipi_hdmi_SC500_720P+vpp                        ← ② 纯套壳目录
    └── lab_ex1_mipi_hdmi+vpp                               ← ③ 板 A 工程本体
        ├── user_source\constraints_source\pin.adc
        ├── user_source\hdl_source\design_top_wrapper.v  pll_por.v  net\
        ├── td_project\camera_to_dsi_display.al  .sdc
        └── sim\
```

- **git 操作在 ① 执行**（`cd D:\TD_project\lab_ex1_mipi_hdmi_SC500_720P+vpp`）
- **TD 工程在 ③**（`td_project\camera_to_dsi_display.al`）
- 全文用 `$P` 代表 ③ 在工作区内的相对路径：
  `lab_ex1_mipi_hdmi_SC500_720P+vpp\lab_ex1_mipi_hdmi+vpp`

---

## 1. 铁律：**绝对不要手改 TD 的工程文件**

### 1.1 不要碰这两个文件

| 文件 | 谁维护 |
|---|---|
| `$P\td_project\camera_to_dsi_display.al` | **TD 工程管理器** |
| `$P\td_project\camera_to_dsi_display_Runs\<run>\camera_to_dsi_display.prj` | **TD 每个 run 保存一份自己的副本** |

**要增删源文件，一律在 TD 图形界面里做**（右键工程 → Add Files / Remove）。手写 XML 那次我连错 6 轮，最后把 `.prj` 写成 1048 行、段落重复的损坏文件。

### 1.2 为什么（这次踩的坑，按顺序）

| # | 现象 | 真因 |
|---|---|---|
| 1 | `XML tag <xmlcomment> is invalid` | 我往 `.al` 里加了 XML 注释。TD 能读裸 `&`、也能读带 `::` 的元素名，**唯独咽不下注释** |
| 2 | 白折腾一轮 | 我以为裸 `&`（`UsedInP&R`）是错的，把 106 处转义成 `&amp;`。**TD 重写文件时又全改回裸 `&`** —— 它自己就这么存，`&` 从来不是问题 |
| 3 | `IP ...TEMAC_CORE.ipc generated file does not exist` | 我把 `.ipc` 登记进 `<IP_FILE>`。**正确做法是把已生成的 `TEMAC_CORE_gate.v` 当普通 Verilog 源文件登记进 `<Verilog>` 段**（板 B / 阶段一都这么干，它们的 `.al` 里没有 `.ipc`） |
| 4 | 同样的错，删了 `.al` 里的条目还在报 | **TD 每个 run 目录存了一份 `.prj`**，改主 `.al` 不会同步过去。必须清 run 的 `.prj`（或直接删 run 目录让 TD 重建） |
| 5 | `.prj` 被我改成 1048 行、段落重复 | 我用正则替换 `<Verilog>…</Verilog>` 时，插入的是**整个 `.al`**（自带 `<HardWare>`/`<SourceFiles>`/`<Runs>` 全套），于是段落重复 |

### 1.3 结论

- 源文件登记 → **TD 图形界面**
- 实在要动工程文件 → **删掉整个 run 目录让 TD 重建**，不要手编 XML
- 改完 `.al` 后如果 TD 已开着 → **完全退出 TD 再重开**，别只 reload run

---

## 2. 其它必须知道的坑

| # | 坑 | 正确做法 |
|---|---|---|
| 1 | `DEVICE` 参数写成 `"PH1"` | **必须 `"PH1P"`**。见 `net/ODDR.v`：`"PH1P"` 走 `PH1P_LOGIC_HD_ODDR`（HDIO 原语），`"PH1"` 走 `PH1_LOGIC_ODDR`。RGMII 在 HDIO 上，**用错引脚不工作**。`docs/HX1P35A双板以太网级联实施指导.md` §7.9 写的是 `"PH1"`，**别照抄** |
| 2 | PHY 复位脉冲太短 | YT8511C 要求 `RESET_N` **低电平 ≥10ms**。实施指导文档 §5.6/§7.9 的 8 位计数器（256 拍 ≈ 2.5µs）**是错的**。正确：`clk_25_out`(25MHz) 域数 **250_000** 拍 |
| 3 | 把网络逻辑接在 `vpp_top` 的 mux 输出上 | vpp 有 5 档显示模式，mux 输出会随按键变（灰度/直方图/Sobel/卡通）。CNN 取数必须取 **`vpp_top` 内 `raw_rgb_d[21]`**（伽马后原图，不随模式变） |
| 4 | vsync 拍数 | 现为 **26 拍**（vpp 22 + osd_overlay 2 + delay_osd 2）。若在显示链路插入画框（+1 拍）→ 改 **27**。⚠ `vpp_top.v:474` 的注释「已改为 20 拍 / `S_vsync_dly[19]`」**是过期的**，实际是 `reg [25:0]` / `[25]` |
| 5 | 隐式线网 | 被例化模块的输出线必须**先声明再使用**。板 B 踩过：`net_led` 没声明就被隐式当 1 位线，高位悬空 |
| 6 | 器件原语报 `black box` | 只有**手写 `.prj` 的独立测量工程**会这样（缺库注册）。正式工程用 TD 生成 run 不受影响 |

---

## 3. 已实测的权威数字（不要重新推算，直接用）

### 3.1 资源（布线后实测）

| 项 | 改造前 | 第 1 步后 | 余量 |
|---|---|---|---|
| slice | 17 056（80.39%） | **17 037（80.30%）** | **4 179 可用** |
| ERAM | 47 | 47 | 61 可用 |
| DSP | 38 | 38 | **2 可用** |
| PLL / IO | 3 / 60 | 3 / 75 | 3 / 85 |

### 3.2 时序（第 1 步后，布线实测）

| 时钟域 | 周期 | setup 余量 | hold |
|---|---|---|---|
| HDMI_PIXEL_CLK | 13.333 ns | +1.231 ns | +0.020 ns |
| **HDMI_SERIAL_CLK** | 2.666 ns | **+0.565 ns ← 全局瓶颈** | +0.054 |
| MIPI_RX_BYTE_CLK | 16.668 ns | +7.469 ns | +0.020 |
| usr_clk (DDR) | 15.000 ns | +1.735 ns | +0.020 |

**违例端点 0（setup/hold 都是）**。全局瓶颈是 **HDMI_SERIAL_CLK（375 MHz TMDS 串行器）**，不是像素域。

> ⚠ 旧的 `docs/TIMING_OSD_ANALYSIS.md` / `docs/OSD_TIMING_OPTIMIZATION.md` 和 `docs/A板以太网改造方案.md` §1.3 引用的「像素域 +0.952 ns / 7.1%」是 **2026-09-26 的过期数据**，实际是 +1.753 ns（13.1%）。

### 3.3 `cnn_ds10` 单独综合实测（本次会话新测，很重要）

`user_source/hdl_source/cnn/cnn_ds10.v` —— 1280×720 → 128×72 十倍块平均降采样。

| 项 | 实测 |
|---|---|
| slice | **3 369**（占全芯片 15.88%） |
| DSP | **1**（不是 3！TD 把 15×20 常数乘装进 1 个 DSP 并分时复用） |
| ERAM | **0**（11 520 个累加器寄存器走触发器，不占 ERAM） |
| 寄存器 | 3 937 |
| 75 MHz 下 setup 余量 | **+4 843 ps**（很宽裕） |

**资源结论**：`4 179 − 3 369 = 810` slice 留给网络部分。板 B 网络部分门级综合记录是 33 ERAM / 1 PLL / 3 GCLK / 20 IO。**第 3 步很可能超 slice**，回退方案见 §7。

### 3.4 板 B 已满（说明分工不是选择而是必需）

板 B 布线后：ERAM **107/108（99%）**、DSP **40/40**、slice 15 495（73%）。所以**降采样必须在板 A，CNN 必须在板 B**。

---

## 4. 第 1 步（**从 git 一键恢复，零抄写风险**）

第 1 步 = 释放 R10/R11 给 RGMII + 重建复位链。**已上板验证通过**（画面正常、5 种显示模式可切、OSD 正确、无横向偏移、4 个按键完整）。

### 4.1 恢复（[你复制] 一条命令）

```powershell
cd D:\TD_project\lab_ex1_mipi_hdmi_SC500_720P+vpp
$P='lab_ex1_mipi_hdmi_SC500_720P+vpp/lab_ex1_mipi_hdmi+vpp'
git checkout b2da00a -- "$P/user_source/hdl_source/design_top_wrapper.v" "$P/user_source/constraints_source/pin.adc" "$P/user_source/hdl_source/pll_por.v" "$P/sim/tb_pll_por.v" "$P/td_project/camera_to_dsi_display.al"
git status --short
```

> 用一条长命令（别用反引号续行，粘贴时容易断）。

恢复了 5 个文件（288 行改动）：

| 文件 | 内容 |
|---|---|
| `pin.adc` | 删 `I_rst_n=R10`、`O_screen_pwm=R11`；加 13 条 RGMII/phy_reset + 4 条 LED 约束（共 19 条） |
| `design_top_wrapper.v` | 删 2 个端口、加 RGMII/phy_reset/led；`PLL.reset` 改由 `pll_por` 驱动；`phy_reset` 复用同一 10ms 输出 |
| `pll_por.v` | 新增，60 行，50 MHz 域 10 ms 上电复位 |
| `sim/tb_pll_por.v` | 新增，13 条断言 ModelSim 全 PASS |
| `.al` | 登记 `pll_por.v` |

### 4.2 验证（[你操作]）

1. **完全退出 TD**（若开着）→ 打开 `$P\td_project\camera_to_dsi_display.al`
2. 跑 **Synthesis** → 再跑 **Place & Route + Bitgen**
3. 对照 report（数值可小幅浮动，**结论必须一致**）：

| 项 | 期望 |
|---|---|
| Setup WNS / Hold WNS | 约 +1.2 ns / +20 ps，**违例 0** |
| slice | 约 17 037（80.3%） |
| ERAM / DSP | 47 / 38 |
| IO | **75** |

引脚逐条核对（**最关键**）：

```
I_rst_n / O_screen_pwm   必须已消失
phy1_rgmii_tx_ctl        R10        phy1_rgmii_tx_data[0]  R11
phy_reset                V8         phy1_rgmii_rx_clk      V3
rx_ctl/rx_data[0..3]     N8/N9/T7/T8/T9
tx_clk/tx_data[1..3]     U9/P11/T10/R12
led[0..3]                D10/E10/C6/D6
I_button[0..3]           D5/A9/B9/C7   ← 四个按键必须都在
```

4. 上板验收：画面正常无横向偏移、5 种模式可切、OSD 正确、4 个按键功能完整。
   LED：`led[1]`(E10) 亮 = PLL 锁定，`led[0]`(D10) 亮 = PHY 复位已释放。

### 4.3 第 1 步的状态

**已完成、已验证、已存档在 `b2da00a`。** 不需要重做设计，只需恢复 + 重跑一次综合确认。

---

## 5. 第 2 步：接入网络链路（UDP 回环，先打通网口）

目标：**`ping 192.168.240.1` 通**，NetAssist 发什么收什么。不碰视频链路。

### 5.1 [你复制] 网络 RTL 文件

**源用官方 APUG013 移植副本，不要用 `cnn_boardB`**（板 A 不该依赖板 B 的目录）：

```powershell
$SRC='D:\stage1_hx1p35a_udp\src'
$IP ='D:\stage1_hx1p35a_udp\par_ph1demo\al_ip'
$DST='D:\TD_project\lab_ex1_mipi_hdmi_SC500_720P+vpp\lab_ex1_mipi_hdmi_SC500_720P+vpp\lab_ex1_mipi_hdmi+vpp\user_source\hdl_source\net'

New-Item -ItemType Directory -Force "$DST\ip" | Out-Null

Copy-Item "$SRC\rgmii_interface.v"                   $DST -Force
Copy-Item "$SRC\temac_block.v"                       $DST -Force
Copy-Item "$SRC\pll_gen_1.v"                         $DST -Force
Copy-Item "$SRC\ph1p_phy_pll_wrapper_25a56e5ce2f9.v" $DST -Force
Copy-Item "$SRC\clk_gen_rst_gen.v"                   $DST -Force
Copy-Item "$SRC\div_clk_gen.v"                       $DST -Force
Copy-Item "$SRC\temac_clk_gen.v"                     $DST -Force
Copy-Item "$SRC\tx_clk_en_gen.v"                     $DST -Force
Copy-Item "$SRC\ODDR.v"                              $DST -Force
Copy-Item "$SRC\IDDR.v"                              $DST -Force
Copy-Item "$SRC\BUFGMUX.v"                           $DST -Force
Copy-Item "$SRC\RAMB16_S9_S9.v"                      $DST -Force
Copy-Item "$SRC\ram_fifo.v"                          $DST -Force
Copy-Item "$SRC\tx_client_fifo.v"                    $DST -Force
Copy-Item "$SRC\rx_client_fifo.v"                    $DST -Force
Copy-Item "$SRC\udp_ip_protocol_stack_merge.enc.v"   $DST -Force
Copy-Item "$IP\TEMAC_CORE_gate.v"                    "$DST\ip" -Force

Get-ChildItem $DST -Recurse -File | Select-Object Name,Length | Format-Table -AutoSize
```

**注意**：
- **不要复制 `TEMAC_CORE.ipc`**（TD 会自动发现并要求"生成文件"，而我们用的是已生成好的 `_gate.v` 网表）
- `pll_gen.v` / `pll_gen_2.v` / `udp_data_tpg.v` 是别的器件或测试用，**不要复制**
- 总大小约 700 KB，`TEMAC_CORE_gate.v` 一个就 455 KB，**别用 AI 转抄**（抄错一个字符极难排查）

预期 `net\` 下 17 个文件 + `ip\TEMAC_CORE_gate.v`。

### 5.2 [AI 写] `$P\user_source\hdl_source\net\board_a_net_wrapper.v`

> ⚠️ **本节下面的代码块已经被实施过一遍，并发现了 3 处问题。动手前请先看
> [板A以太网改造_第2步实施记录.md](板A以太网改造_第2步实施记录.md) §2。**
>
> 1. **回环那 4 行组合逻辑是错的**（本节末尾
>    `assign app_tx_data_request = app_rx_data_valid && udp_tx_ready;` 那段）：
>    `udp_ip_protocol_stack` 的 TX 侧是 `request → 等 ack → 再连续喂数据` 的握手，
>    而 `app_rx_data_valid` 是逐字节流有效，必须**先把整包收进 FIFO、等 RX 结束**才能发。
>    实际实施改用安路官方 `net/udp_loopback.v`（+ `ram_fifo`）。
> 2. **`assign led = { net_led, S_por_arst_n, S_pll_lock };` 是 5 位进 4 位口**，
>    实际改成 `{ net_led[2], net_led[1], S_pll_lock, net_led[0] }`。
> 3. 工程里**已经有** `ph1p_phy_pll_wrapper_25a56e5ce2f9`（视频 PLL 的 IP 带进来的），
>    不要再从 stage1 复制一份，否则 TD 报
>    `HDL-7201 CRITICAL-WARNING: overwrite current module`。
>
> 另：`net\` 下最终是 17 个文件（16 个从 stage1 复制 + 新写的 wrapper），
> 不包含上面第 3 条那个 wrapper。

**这是板 A 专属模块，必须新写。** 例化端口逐行对照板 B 已验证的 `cnn_boardB/src/net/board_b_top.v:344-486`，但要改三处（见下）。

```verilog
`timescale 1ns / 1ps
//=============================================================================
// board_a_net_wrapper.v —— 板 A 以太网链路包装（第 2 步：纯网络 + UDP 回环）
//
// 例化端口对照 cnn_boardB/src/net/board_b_top.v:344-486（板 B 实机验证过），
// 三处板 A 专属改动：
//   ① DEVICE 用 "PH1P"（不是 "PH1"）——见 ODDR.v：PH1P 走 HDIO 原语
//   ② 网络复位改用 pll_por 输出，不占按键
//   ③ MAC/IP/端口按板 A 身份
//=============================================================================
module board_a_net_wrapper (
    input  wire        clk_50m,           // C4 板载 50MHz 晶振
    input  wire        por_arst_n,        // 来自 pll_por：低有效 10ms 上电复位

    // ---- RGMII（YT8511C，BANK22 3.3V）----
    input  wire        phy1_rgmii_rx_clk,
    input  wire        phy1_rgmii_rx_ctl,
    input  wire [3:0]  phy1_rgmii_rx_data,
    output wire        phy1_rgmii_tx_clk,
    output wire        phy1_rgmii_tx_ctl,
    output wire [3:0]  phy1_rgmii_tx_data,
    output wire        phy_reset,

    output wire [2:0]  net_led
);

    wire net_rst_n = por_arst_n;
    wire net_arst  = ~net_rst_n;

    wire reset;
    wire reset_reg;
    reg  [7:0] soft_reset_cnt = 8'hFF;

    assign reset = net_arst || reset_reg || (soft_reset_cnt != 8'd0);

    // ③ 板 A 身份：192.168.240.1 / 端口 1；对端板 B 192.168.240.2 / 端口 2
    //    MAC 用本地管理单播（第 1 字节 bit0=0 且 bit1=1），不能用 01:... 组播
    parameter DEVICE             = "PH1P";
    parameter LOCAL_UDP_PORT_NUM = 16'h0001;
    parameter LOCAL_IP_ADDRESS   = 32'hC0A8F001;      // 192.168.240.1
    parameter LOCAL_MAC_ADDRESS  = 48'h020000002401;  // 02:00:00:00:24:01
    parameter DST_UDP_PORT_NUM   = 16'h0002;
    parameter DST_IP_ADDRESS     = 32'hC0A8F002;      // 192.168.240.2

    wire [7:0]  app_rx_data;
    wire        app_rx_data_valid;
    wire [15:0] app_rx_data_length;
    wire        udp_tx_ready;
    wire        app_tx_ack;
    wire        app_tx_data_request;
    wire        app_tx_data_valid;
    wire [7:0]  app_tx_data;
    wire [15:0] udp_data_length;

    wire [1:0]  TRI_speed = 2'b10;                    // 千兆
    wire [19:0] mac_cfg_vector;
    wire [47:0] unicast_address;
    wire        temac_tx_ready, temac_tx_valid, temac_tx_sof, temac_tx_eof;
    wire [7:0]  temac_tx_data;
    wire        temac_rx_ready, temac_rx_valid, temac_rx_sof, temac_rx_eof;
    wire [7:0]  temac_rx_data;
    wire        rx_correct_frame, rx_error_frame;
    wire        rx_clk_int, rx_clk_en_int, tx_clk_int, tx_clk_en_int;
    wire        rx_valid, tx_valid, tx_rdy, tx_collision, tx_retransmit;
    wire [7:0]  rx_data, tx_data;

    wire        temac_clk, udp_clk, temac_clk90;
    wire        clk_125_out, clk_12_5_out, clk_1_25_out, clk_25_out;

    assign unicast_address = { LOCAL_MAC_ADDRESS[7:0],   LOCAL_MAC_ADDRESS[15:8],
                               LOCAL_MAC_ADDRESS[23:16], LOCAL_MAC_ADDRESS[31:24],
                               LOCAL_MAC_ADDRESS[39:32], LOCAL_MAC_ADDRESS[47:40] };
    assign mac_cfg_vector  = {1'b0, 2'b00, TRI_speed, 8'b00100010, 7'b0100010};

    // ---- PHY 硬件复位：YT8511C 要求 RESET_N 低电平 ≥10ms ----
    // clk_25_out = 25MHz -> 250_000 拍 = 10ms
    // ⚠ 不要照抄实施指导文档 §5.6/§7.9 的 8 位计数器（256 拍 ≈ 2.5µs），太短
    reg [19:0] phy_reset_cnt = 20'd0;

    always @(posedge clk_25_out or negedge net_rst_n) begin
        if (!net_rst_n)
            phy_reset_cnt <= 20'd0;
        else if (phy_reset_cnt < 20'd250000)
            phy_reset_cnt <= phy_reset_cnt + 20'd1;
    end
    assign phy_reset = (phy_reset_cnt >= 20'd250000);

    always @(posedge udp_clk or negedge net_rst_n) begin
        if (!net_rst_n)                   soft_reset_cnt <= 8'hFF;
        else if (soft_reset_cnt != 8'd0)  soft_reset_cnt <= soft_reset_cnt - 8'd1;
    end

    // ---- 独立网络 PLL：50MHz -> 125/125/12.5/25/125@90° MHz ----
    // 与视频 PLL（u_PLL）完全独立，视频链路不受影响
    clk_gen_rst_gen #(.DEVICE(DEVICE)) u_clk_gen (
        .reset        ( net_arst    ),
        .clk_in       ( clk_50m     ),
        .rst_out      ( reset_reg   ),
        .clk_125_out0 ( temac_clk   ),
        .clk_125_out1 ( clk_125_out ),
        .clk_125_out2 ( temac_clk90 ),
        .clk_12_5_out ( clk_12_5_out),
        .clk_1_25_out ( clk_1_25_out),
        .clk_25_out   ( clk_25_out  )
    );

    // ---- UDP/IP 协议栈（加密 IP，不可修改，只能例化）----
    udp_ip_protocol_stack #(
        .DEVICE             (DEVICE),
        .LOCAL_UDP_PORT_NUM (LOCAL_UDP_PORT_NUM),
        .LOCAL_IP_ADDRESS   (LOCAL_IP_ADDRESS),
        .LOCAL_MAC_ADDRESS  (LOCAL_MAC_ADDRESS)
    ) u_stack (
        .udp_rx_clk         (udp_clk),
        .udp_tx_clk         (udp_clk),
        .reset              (reset),
        .udp2app_tx_ready   (udp_tx_ready),
        .udp2app_tx_ack     (app_tx_ack),
        .app_tx_request     (app_tx_data_request),
        .app_tx_data_valid  (app_tx_data_valid),
        .app_tx_data        (app_tx_data),
        .app_tx_data_length (udp_data_length),
        .app_tx_dst_port    (DST_UDP_PORT_NUM),
        .ip_tx_dst_address  (DST_IP_ADDRESS),
        .input_local_udp_port_num       (1'b0),
        .input_local_udp_port_num_valid (1'b0),
        .input_local_ip_address         (1'b0),
        .input_local_ip_address_valid   (1'b0),
        .app_rx_data_valid  (app_rx_data_valid),
        .app_rx_data        (app_rx_data),
        .app_rx_data_length (app_rx_data_length),
        .app_rx_port_num    (),
        .temac_rx_ready     (temac_rx_ready),
        .temac_rx_valid     (~temac_rx_valid),
        .temac_rx_data      (temac_rx_data),
        .temac_rx_sof       (temac_rx_sof),
        .temac_rx_eof       (temac_rx_eof),
        .temac_tx_ready     (temac_tx_ready),
        .temac_tx_valid     (temac_tx_valid),
        .temac_tx_data      (temac_tx_data),
        .temac_tx_sof       (temac_tx_sof),
        .temac_tx_eof       (temac_tx_eof),
        .ip_rx_error        (),
        .arp_request_no_reply_error ()
    );

    // ---- TEMAC + RGMII ----
    temac_block #(.DEVICE(DEVICE)) u_trimac (
        .reset              (reset),
        .gtx_clk            (temac_clk),
        .gtx_clk_90         (temac_clk90),
        .rx_clk             (rx_clk_int),
        .rx_clk_en          (rx_clk_en_int),
        .rx_data            (rx_data),
        .rx_data_valid      (rx_valid),
        .rx_correct_frame   (rx_correct_frame),
        .rx_error_frame     (rx_error_frame),
        .rx_status_vector   (),
        .rx_status_vld      (),
        .tx_clk             (tx_clk_int),
        .tx_clk_en          (tx_clk_en_int),
        .tx_data            (tx_data),
        .tx_data_en         (tx_valid),
        .tx_rdy             (tx_rdy),
        .tx_stop            (1'b0),
        .tx_collision       (tx_collision),
        .tx_retransmit      (tx_retransmit),
        .tx_ifg_val         (8'h00),
        .tx_status_vector   (),
        .tx_status_vld      (),
        .pause_req          (1'b0),
        .pause_val          (16'h0),
        .pause_source_addr  (48'h5AF1F2F3F4F5),
        .unicast_address    (unicast_address),
        .mac_cfg_vector     (mac_cfg_vector),
        .rgmii_txd          (phy1_rgmii_tx_data),
        .rgmii_tx_ctl       (phy1_rgmii_tx_ctl),
        .rgmii_txc          (phy1_rgmii_tx_clk),
        .rgmii_rxd          (phy1_rgmii_rx_data),
        .rgmii_rx_ctl       (phy1_rgmii_rx_ctl),
        .rgmii_rxc          (phy1_rgmii_rx_clk),
        .inband_link_status (),
        .inband_clock_speed (),
        .inband_duplex_status ()
    );

    // ---- 三速时钟选择 ----
    udp_clk_gen #(.DEVICE(DEVICE)) u_clkgen (
        .reset       ( net_arst     ),
        .tri_speed   ( TRI_speed    ),
        .clk_125_in  ( clk_125_out  ),
        .clk_12_5_in ( clk_12_5_out ),
        .clk_1_25_in ( clk_1_25_out ),
        .udp_clk_out ( udp_clk      )
    );

    // ---- TX/RX 跨时钟 FIFO ----
    tx_client_fifo #(.DEVICE(DEVICE), .ADDR_WIDTH(11)) u_tx_fifo (
        .rd_clk       (tx_clk_int),
        .rd_sreset    (reset),
        .rd_enable    (tx_clk_en_int),
        .tx_data      (tx_data),
        .tx_data_valid(tx_valid),
        .tx_ack       (tx_rdy),
        .tx_collision (tx_collision),
        .tx_retransmit(tx_retransmit),
        .overflow     (),
        .wr_clk       (udp_clk),
        .wr_sreset    (reset),
        .wr_data      (temac_tx_data),
        .wr_sof_n     (temac_tx_sof),
        .wr_eof_n     (temac_tx_eof),
        .wr_src_rdy_n (temac_tx_valid),
        .wr_dst_rdy_n (temac_tx_ready),
        .wr_fifo_status ()
    );

    rx_client_fifo #(.DEVICE(DEVICE), .ADDR_WIDTH(11)) u_rx_fifo (
        .wr_clk       (rx_clk_int),
        .wr_enable    (rx_clk_en_int),
        .wr_sreset    (reset),
        .rx_data      (rx_data),
        .rx_data_valid(rx_valid),
        .rx_good_frame(rx_correct_frame),
        .rx_bad_frame (rx_error_frame),
        .overflow     (),
        .rd_clk       (udp_clk),
        .rd_sreset    (reset),
        .rd_data_out  (temac_rx_data),
        .rd_sof_n     (temac_rx_sof),
        .rd_eof_n     (temac_rx_eof),
        .rd_src_rdy_n (temac_rx_valid),
        .rd_dst_rdy_n (temac_rx_ready),
        .rx_fifo_status ()
    );

    // =========================================================================
    // 应用层：最小 UDP 回环（收到什么发回什么）—— 第 2 步验收用
    // 第 3 步会换成发图像帧，第 4 步加收人脸框解析
    // =========================================================================
    assign app_tx_data_request = app_rx_data_valid && udp_tx_ready;
    assign app_tx_data_valid   = app_rx_data_valid;
    assign app_tx_data         = app_rx_data;
    assign udp_data_length     = app_rx_data_length;

    // ---- 诊断 LED（高电平点亮）----
    reg [23:0] hb_cnt;
    always @(posedge udp_clk or negedge net_rst_n)
        if (!net_rst_n) hb_cnt <= 24'd0;
        else            hb_cnt <= hb_cnt + 24'd1;

    assign net_led[0] = phy_reset;         // PHY 复位释放 = 链路就绪
    assign net_led[1] = app_rx_data_valid; // 收到 UDP 载荷
    assign net_led[2] = hb_cnt[23];        // 心跳（约 0.75s 翻转）

endmodule
```

### 5.3 [AI 改] `$P\user_source\hdl_source\design_top_wrapper.v`

把第 1 步末尾那三行**占位常量驱动**删掉：

```verilog
// 删掉这三行（第1步的占位）
assign phy1_rgmii_tx_clk  = 1'b0;
assign phy1_rgmii_tx_ctl  = 1'b0;
assign phy1_rgmii_tx_data = 4'b0000;
```

替换为（注意 **`net_led` 必须先声明再用**，否则被隐式声明成 1 位线）：

```verilog
    // =========================================================================
    // [以太网改造 第2步] 网络链路例化
    //   独立 PLL + RGMII + TEMAC + UDP/IP 栈 + 跨时钟 FIFO，应用层暂为最小 UDP 回环。
    //   视频链路完全不经过本模块，第 1 步的画面时序不受影响。
    // =========================================================================
    wire [2:0] net_led;

    assign led = { net_led, S_por_arst_n, S_pll_lock };

    board_a_net_wrapper u_net (
        .clk_50m            ( I_sys_clk           ),
        .por_arst_n         ( S_por_arst_n        ),
        .phy1_rgmii_rx_clk  ( phy1_rgmii_rx_clk   ),
        .phy1_rgmii_rx_ctl  ( phy1_rgmii_rx_ctl   ),
        .phy1_rgmii_rx_data ( phy1_rgmii_rx_data  ),
        .phy1_rgmii_tx_clk  ( phy1_rgmii_tx_clk   ),
        .phy1_rgmii_tx_ctl  ( phy1_rgmii_tx_ctl   ),
        .phy1_rgmii_tx_data ( phy1_rgmii_tx_data  ),
        .phy_reset          ( phy_reset           ),
        .net_led            ( net_led             )
    );
```

同时把第 1 步那行 `assign led = { 2'b00, S_por_arst_n, S_pll_lock };` 换成上面的 `{ net_led, ... }`。

### 5.4 [AI 改] `$P\td_project\camera_to_dsi_display.sdc`

在文件**末尾**追加（这是普通 SDC，不是 XML，安全）：

```tcl
# =============================================================================
# [以太网改造 第2步] 网络链路时序约束
#   网络 PLL 在 u_net/u_clk_gen/u_pll_0，参考时钟就是上面已有的 I_sys_clk(50MHz)
#   层级依据：clk_gen_rst_gen.v 里 u_pll_0 -> pll_gen_1.v 里 pll_inst
#             -> ph1p_phy_pll_wrapper 里 u_PH1P_PHY_PLL
# =============================================================================

# --- PHY 送来的 RGMII 接收时钟（千兆 125MHz）---
create_clock -name {phy1_rgmii_rx_clk} -period 8.000 -waveform {0.000 4.000} [get_ports {phy1_rgmii_rx_clk}]

# --- 网络 PLL 派生时钟：50MHz -> 125/125/12.5/25/125(90°) MHz ---
create_generated_clock -name {net_pll_125m_0} -source [get_ports {I_sys_clk}] -master_clock {sys_clk_50m} -multiply_by 2.500 [get_pins {u_net/u_clk_gen/u_pll_0/pll_inst/u_PH1P_PHY_PLL.clkc[0]}]
create_generated_clock -name {net_pll_125m_1} -source [get_ports {I_sys_clk}] -master_clock {sys_clk_50m} -multiply_by 2.500 [get_pins {u_net/u_clk_gen/u_pll_0/pll_inst/u_PH1P_PHY_PLL.clkc[1]}]
create_generated_clock -name {net_pll_12p5m}  -source [get_ports {I_sys_clk}] -master_clock {sys_clk_50m} -divide_by 4.000  [get_pins {u_net/u_clk_gen/u_pll_0/pll_inst/u_PH1P_PHY_PLL.clkc[2]}]
create_generated_clock -name {net_pll_25m}    -source [get_ports {I_sys_clk}] -master_clock {sys_clk_50m} -divide_by 2.000  [get_pins {u_net/u_clk_gen/u_pll_0/pll_inst/u_PH1P_PHY_PLL.clkc[3]}]

# --- udp_clk 是三速 BUFGMUX 的候选时钟（与板 B ph1_demo.sdc:42-45 同一写法）---
create_generated_clock -name {udp_clk_125m}  -add -source [get_pins {u_net/u_clk_gen/u_pll_0/pll_inst/u_PH1P_PHY_PLL.clkc[1]}] -master_clock {net_pll_125m_1} -divide_by 1.000  [get_nets {udp_clk}]
create_generated_clock -name {udp_clk_12p5m} -add -source [get_pins {u_net/u_clk_gen/u_pll_0/pll_inst/u_PH1P_PHY_PLL.clkc[2]}] -master_clock {net_pll_12p5m}  -divide_by 1.000  [get_nets {udp_clk}]
create_generated_clock -name {udp_clk_1p25m} -add -source [get_pins {u_net/u_clk_gen/u_pll_0/pll_inst/u_PH1P_PHY_PLL.clkc[2]}] -master_clock {net_pll_12p5m}  -divide_by 10.000 [get_nets {udp_clk}]

# --- RGMII RX 外部延迟窗口（板 B 当前调试值 2.0~2.8ns，属暂定值，需结合 YT8511C
#     实际 strap/寄存器配置与数据手册复核；"STA 收敛"不等于"RX 采样正确"）---
set rgmii_rx_ports [get_ports {phy1_rgmii_rx_ctl {phy1_rgmii_rx_data[*]}}]
set_input_delay -clock [get_clocks {phy1_rgmii_rx_clk}] -max 2.800 $rgmii_rx_ports
set_input_delay -clock [get_clocks {phy1_rgmii_rx_clk}] -min 2.000 $rgmii_rx_ports
set_input_delay -clock [get_clocks {phy1_rgmii_rx_clk}] -clock_fall -max -add_delay 2.800 $rgmii_rx_ports
set_input_delay -clock [get_clocks {phy1_rgmii_rx_clk}] -clock_fall -min -add_delay 2.000 $rgmii_rx_ports

# --- 网络时钟与视频/DDR 域按异步处理 ---
# TXC 不加 set_output_delay：TXC 由 rgmii_interface.v 的 ODDR + PLL C4(90°) 产生，
# 官方 33 例程那两条 TX 约束因旧层级名不匹配而失败，加上反而制造假违例
set_clock_groups -exclusive -group [get_clocks {udp_clk_125m}]
set_clock_groups -exclusive -group [get_clocks {udp_clk_12p5m}]
set_clock_groups -exclusive -group [get_clocks {udp_clk_1p25m}]
set_clock_groups -exclusive -group [get_clocks {phy1_rgmii_rx_clk}]

set_clock_groups -asynchronous \
    -group [get_clocks {udp_clk_125m phy1_rgmii_rx_clk net_pll_125m_0 net_pll_125m_1 net_pll_12p5m net_pll_25m}] \
    -group [get_clocks {mipi_rx_ck_pad MIPI_RX_BYTE_CLK}] \
    -group [get_clocks {sys_clk_50m pll_clk_100m pll_clk_24m HDMI_PIXEL_CLK HDMI_SERIAL_CLK}] \
    -group [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/ddr_clk u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk}]
```

### 5.5 [你操作] **在 TD 图形界面里登记源文件**（不要手改 `.al`）

1. **完全退出 TD** → 打开 `$P\td_project\camera_to_dsi_display.al`
2. 右键工程 → **Add Files**（添加源文件），加这 **17 个 Verilog**：

```
net\board_a_net_wrapper.v
net\rgmii_interface.v          net\temac_block.v
net\pll_gen_1.v                net\ph1p_phy_pll_wrapper_25a56e5ce2f9.v
net\clk_gen_rst_gen.v          net\div_clk_gen.v
net\temac_clk_gen.v            net\tx_clk_en_gen.v
net\ODDR.v                     net\IDDR.v               net\BUFGMUX.v
net\RAMB16_S9_S9.v             net\ram_fifo.v
net\tx_client_fifo.v           net\rx_client_fifo.v
net\udp_ip_protocol_stack_merge.enc.v
net\ip\TEMAC_CORE_gate.v
```

> ⚠ **只加 `_gate.v`，绝对不要加 `TEMAC_CORE.ipc`。**
> `TEMAC_CORE_gate.v` 是 `module TEMAC_CORE` 的已生成网表，当普通 Verilog 源文件登记即可。
> `.ipc` 只是 IP 配置描述，加进 `<IP_FILE>` 会让 TD 去找"生成文件"并报错
> （板 B 和阶段一工程的 `.al` 里都**没有** `.ipc`）。

3. 确认工程树里能看到这些文件，且 `design_top_wrapper` 仍是顶层

### 5.6 [你操作] 综合 → 验收

1. 跑 **Synthesis**，**把 `#slice / #eram / #dsp / #pll / #gclk` 记下来**（这是第 3 步的关键输入）
2. 跑 **Place & Route + Bitgen**
3. **先别上板**，先看报告：
   - `#slice` 应 ≈ 17 037 + 2 000~2 500 ≈ **19 000~19 500**（89~92%）
   - `#eram` 应 ≈ 47 + 33 ≈ **80**
   - 违例应为 0
   - **如果 slice > 93% 或 ERAM > 95%，先停下**（见 §7 回退方案）
4. 上板：网线接 PC，PC 网卡设 `192.168.240.10/24`
   ```
   ping 192.168.240.1
   ```
   LED：`led[1]`(E10) 亮 = PHY 链路就绪，收到包时 `led[0]`(D10) 闪

**第 2 步完成标准**：ping 通 + NetAssist 发什么收什么（UDP 回环）。

---

## 6. 后续步骤预告（第 3~5 步，本次未实施）

| 步 | 内容 | 关键要点 |
|---|---|---|
| 3 | 取数 + 降采样 + 帧门控 + 跨时钟 FIFO + 发 20 个 UDP 包 | **取数点必须是 `vpp_top` 内 `raw_rgb_d[21]`**（见 §2 坑 3）。`vpp_top.v` 目前没把这一级引出来，需要加一个输出端口。帧门控每 6 帧发 1 帧 |
| 4 | 解析板 B 回传的人脸框 + 画到 HDMI | 用已有的 `osd_box_drawer.v`（`SCALE_FACTOR=10`，输入是左上角 x1/y1 + w/h）。**插入后显示链路 +1 拍 → `S_vsync_dly` 由 26 改 27**（`reg [26:0]`，取 `[26]`） |
| 5 | 双板直连联调 | 板 B 已完工（`D:\TD_project\cnn_boardB`），板 A 发图 → 板 B 推理 → 回框 → 画框 |

**板 B 接口（已钉死）**：它接收 128×72×3 RGB（20 个 UDP 包），回传 10 字节人脸框。

---

## 7. 风险与回退（第 3 步很可能需要）

### 7.1 核心风险：第 3 步 slice 可能不够

```
第 1 步后余量            4 179
cnn_ds10 实测消耗        3 369      ← 占余量 80%
剩给网络部分                 810
网络部分实际需要        ~2 100

预计超出约 2 000 slice → TD 在 place 阶段失败（PHY-9009）
```

### 7.2 回退方案（按性价比排序，**全部有实测依据**）

| 方案 | 现状占用 | 改法 | 可回收 |
|---|---|---|---|
| **① `u_anlogic_logo_rom` 改 ERAM** | **1 859 LUT，0 ERAM** | 组合查表 → ERAM ROM | **~1 859 slice**，代价 ~32 ERAM（余 61 个，够） |
| ② `cnn_ds10` 累加器改 ERAM | 占其 3 369 的大头 | 累加器从触发器改 ERAM 存储 | ~1 500~2 200 slice |
| ③ `u_awb/u_divider` 改移位减 | 767 LUT + 948 ripple，**占 8 DSP** | 移位减法器替代除法器 IP | ~700 slice + 释放 8 DSP |

**①号最优**：它现在一行 ERAM 都没用（`0 ERAM`），把 1 859 个 LUT 的真值表搬进 ERAM 直接换回 1 859 slice。按此算 `22 506 − 1 859 = 20 647 < 21 216` ✅ 能装下（余量仅 2.6%）。

### 7.3 另一个风险：HDMI_SERIAL_CLK 只剩 21% 余量

全局时序瓶颈是 `HDMI_SERIAL_CLK`（375 MHz，+0.565 ns / 2.666 ns）。加 5 000+ slice 会抬高布局拥塞，可能间接压这个域。**方案①除了省 slice，还减少 1 859 个需布局的 LUT，对这条路径是双重利好。**

### 7.4 已知的历史缺陷（与本次改造无关，**不要顺手改**）

`vpp_top` 模式 4（卡通）的 `tvalid/tuser/tlast` 是 23 拍而 `tdata` 是 22 拍，根因在 `bilateral_filter_3x3.v:237` 把 `O_tvalid` 多打了一拍。效果是卡通档画面比自身 DE 提前 1 像素。**与 CNN 取数点无关，别动。**

---

## 8. [你复制] 环境与工程信息

### 8.1 关键路径

| 项 | 路径 |
|---|---|
| 工作区根（git 在此外） | `D:\TD_project\lab_ex1_mipi_hdmi_SC500_720P+vpp` |
| **板 A 工程本体** | `...\lab_ex1_mipi_hdmi_SC500_720P+vpp\lab_ex1_mipi_hdmi+vpp` |
| TD 安装 | `E:\Anlogic\TD_6.2.1_Engineer_6.2.168.116` |
| **网络 RTL 源（用这个）** | `D:\stage1_hx1p35a_udp\src` + `...\par_ph1demo\al_ip` |
| 板 B 工程（参考，勿依赖） | `D:\TD_project\cnn_boardB` |
| 官方例程（33 以太网 UDP） | `D:\HX1P35A_Contest_202606\2_Example\33_ethernet_udp_led` |
| 板级资料包 | `D:\HX1P35A_Contest_202606\` |

### 8.2 设计规格

| 项 | 值 |
|---|---|
| 器件 | PH1P35MDG324（BGA324，TD 6.2，speed -3） |
| 顶层 | `design_top_wrapper` |
| 数据流 | SC500(MIPI) → DPHY RX → CSI/RAW10 解包 → ISP(demosaic+AWB) → DDR2 → hdmi_mixer → vpp_top(5模式) → osd_overlay → delay_osd → hdmi_tx |
| 伽马在哪 | **只在 `vpp_top` 里**。ISP/DDR/mixer 全是线性 RGB |
| 以太网硬件 | 板载 YT8511C 千兆 PHY + HR911130A RJ45（支持 Auto-MDIX，直连网线即可） |
| 板 A / 板 B | **同一块板**（HX1P35A，技术人员确认 A/B 版电气与球位相同，仅螺丝孔不同） |

### 8.3 板间协议（板 B 已钉死）

| 项 | 板 A | 板 B |
|---|---|---|
| IP | `192.168.240.1` | `192.168.240.2` |
| MAC | `02:00:00:00:24:01` | `02:00:00:00:24:02` |
| UDP 端口 | `1` | `2` |
| 发送 | 20 个 UDP 包 = 128×72×3 RGB | 10 字节人脸框（x1,y1,w,h,score） |

### 8.4 参考文档

| 文档 | 用途 | 注意 |
|---|---|---|
| `docs/A板以太网改造方案.md` | 引脚表、资源账 | ⚠ §1.3 时序数字过期；§8.1 取数点建议有坑；§10.2 网络 slice 是估算 |
| `docs/HX1P35A双板以太网级联实施指导.md` | 背景知识 | ⚠ §7.9 的 `DEVICE="PH1"` 和 PHY 复位代码**都是错的**；文档开头已自述"不是可直接下载的工程" |
| `docs/BOARD_SPLIT.md` | 双板分工、文件分类 | 可用 |
| `docs/TIMING_OSD_ANALYSIS.md` | OSD 时序根因 | ⚠ 数字是 2026-09-26 的，已被后续布线取代 |
| `docs/项目总结.md` | CNN 侧总结 | 只讲 CNN，以太网部分已过期 |

---

## 9. 给下一个 AI 的操作纪律（请严格遵守）

1. **不要手改 `.al` / `.prj`**。要登记源文件 → 让用户在 TD 图形界面 Add Files。要清缓存 → 删 run 目录让 TD 重建。
2. **大文件一律让用户复制**。不要用读+写工具转抄 KB 级以上的代码（`TEMAC_CORE_gate.v` 455 KB、加密栈 222 KB，抄错一个字符极难排查）。
3. **写 `.bat` 一律用 CRLF 行尾**（工具写出来是 LF，cmd 会闪退）。**推荐写 `.ps1`**（PowerShell 不在乎行尾），或让用户直接在 PowerShell 里粘命令。
4. **让用户跑命令时，先确认提示符是 `PS`**（PowerShell）。粘到 cmd 里会全线报错。
5. **路径含中文**（`lab_ex1_mipi_hdmi_SC500_720P+vpp`）。`.ps1` 文件避免内嵌中文路径（PowerShell 5.1 按 ANSI 读无 BOM 的 UTF-8 会乱码）；**优先用相对路径 + 让用户 cd 到工作区根**。
6. **遇到"别人能用我不能用"，第一步就去对照能用工程的同类文件**（`.al`、`.prj`、SDC），不要凭文档推断。
7. **改 `.al` 只允许"添加一个源文件条目"这一种手改**（第 1 步的 `pll_por.v` 就是这么加的，成功了）。其余一律走图形界面。
8. **每完成一步就提交 git**（沙箱不允许 AI 写 `.git`，需请用户授权或让用户自己跑 `git add -A; git commit`）。第 2 步的代码这次就是因为没提交、工程被删而丢失，只能重写。
