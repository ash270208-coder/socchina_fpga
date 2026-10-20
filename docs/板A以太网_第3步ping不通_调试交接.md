# 板A以太网 第3步「ping 不通」调试交接

> **用途**：新开对话继续排查这个问题时，先读这一份。所有信息都是**实测过的**，
> 没验证过的都明确标了「未验证」。
> 记录时间：2026-10-10 23:4x

---

## 0. 一句话问题

**第 2 步（UDP 回环）上板验证通过；做完第 3 步（图像发送通路）后，板 A 的网口
ping 不通、ARP 表里拿不到板子的 MAC，板子**什么都不往外发**。
第 3 步的**功能目标（发 128×72 图像）也没成功**。**

**注意区分两个现象**（它们可能是同一个根因，也可能不是）：
1. **网口整体不响应**（ping/ARP 都不通）← 这是当前最严重、最优先要解决的
2. 图像发不出去（LED3 不亮）

---

## 1. 工程与环境

| 项 | 值 |
|---|---|
| 工作区根（git 在此外） | `D:\TD_project\lab_ex1_mipi_hdmi_SC500_720P+vpp` |
| **板 A 工程本体** | `...\lab_ex1_mipi_hdmi_SC500_720P+vpp\lab_ex1_mipi_hdmi+vpp` |
| 器件 / 顶层 | PH1P35MDG324（BGA324，speed -3）/ `design_top_wrapper` |
| TD 版本 | TD 6.2.168116，装在 `E:\Anlogic\TD_6.2.1_Engineer_6.2.168.116` |
| ModelSim | SE-64 10.4，`E:\Modelsim\win64` |
| 板子 | HX1P35A（板 A / 板 B 是同一块板，仅螺丝孔不同） |
| 网口硬件 | 板载 YT8511C 千兆 PHY + HR911130A RJ45（支持 Auto-MDIX，直连网线即可） |

### git 状态（重要）

```
530c590  对板A进一步修改以太网的模块     ← 第 3 步已提交
9dbb03c  对板A进一步修改以太网的模块     ← 第 3 步已提交（重复提交）
5271175  板A接入千兆网口+UDP回环(上板验证通过)；awb除法器去流水；TXC复位时序修复   ← 第 2 步
```

**当前工作区有 3 个未提交的改动**（都是这次调试期加的，尚未上板）：

| 文件 | 改动 | 时间 |
|---|---|---|
| `net/rgmii_interface.v` | **回退**了第 2 步那次时序修复（见 §5） | 23:34 |
| `net/board_a_net_wrapper.v` | 4 个诊断 LED 换成网口分段观察 | 23:15 |
| `design_top_wrapper.v` | LED 映射改成 `led = net_led` | 23:14 |

---

## 2. 已经确认能工作的部分（不要在排查时推翻它们）

| 项 | 状态 | 证据 |
|---|---|---|
| **第 2 步整条以太网链路** | ✅ **上板验证通过** | ping `192.168.240.1` 通；PC 用 NetAssist 发 `hello123` 到板 A:1，**原样回送**，收到 `68 65 6C 6C 6F 31 32 33` |
| 发送硬件链路 MAC→RGMII→PHY→网线 | ✅ 由上面那条间接证明（回环时板子在发） | — |
| 网络时钟 / 复位 | ✅ | 心跳灯（`udp_clk` 域）在闪 → `udp_clk` 在跑 → 网络 PLL 锁定 → `reset_reg=0`；`soft_reset_cnt` 用同一个 `udp_clk` 计数，必定减到 0 → `reset` 已释放 |
| 视频链路 / 显示 | ✅ | 第 3 步**没有改动显示链路**，只给 `vpp_top` 加了 4 个输出口引线；上板 HDMI 正常 |
| 第 3 步综合 / 布线 / 时序 | ✅ | SWNS +0.254ns、HWNS +0.020ns、**违例 0**；`#slice` 18 126/21 216（85.4%）、`#eram` 57、`#dsp` 39 |
| `cnn_ds10`（ERAM 版）功能 | ✅ | ModelSim 独立参考模型：9216 块 **0 错 PASS**（`sim/tb_cnn_ds10.v`） |
| PC 侧网络配置 | ✅ | `ipconfig`：以太网 = `192.168.240.2` / `255.255.255.0` / 网关空；WLAN = `10.19.62.197`（不同网段，不抢路由）；RJ45 链路灯亮 |

---

## 3. 现象：完整的实测数据

### 3.1 ping（用第 3 步的 bit）

```
C:\>ping 192.168.240.1
正在 Ping 192.168.240.1 具有 32 字节的数据:
来自 192.168.240.2 的回复: 无法访问目标主机。      ← 这条是 PC 自己发的
请求超时。
请求超时。
请求超时。
    数据包: 已发送 = 4，已接收 = 0，丢失 = 4 (100% 丢失)
```

**读法**：`来自 192.168.240.2 的回复: 无法访问目标主机` 是 **PC 自己的协议栈**生成的
ICMP 不可达 —— 意思是 **PC 发 ARP 问"谁是 192.168.240.1"，没人回答，所以连包都发不出去**。

### 3.2 arp -a（ping 之后立刻看）

`192.168.240.2` 那个接口下**只有广播/组播的静态条目，没有 `192.168.240.1`**。
（Windows 不记录失败的 ARP 条目，所以"没有 `.1`" = **PC 从来没解析到板子的 MAC**。）

### 3.3 LED（**这是最有价值的一组数据**）

**LED 编号对应**（⚠ 有歧义，务必对齐）：
原理图丝印 `LED0~LED3` = `D10 / E10 / C6 / D6`；
**用户口语说的 `LED1~LED4` = `D10 / E10 / C6 / D6`**（即 LED1=D10、LED4=D6）。

**当前 bit（23:29 构建，带 4 个网口观察灯）的映射与读数：**

| 板载 | 引脚 | 语义 | 实测 | 判读 |
|---|---|---|---|---|
| LED1 | D10 | 收到 PC 发来的 UDP（`app_rx_data_valid`） | **灭** | ✓ 没发 UDP，正常 |
| **LED2** | **E10** | **MAC 在往外发帧（`temac_tx_valid`）** | **亮** | **协议栈确实在生成发送帧！** |
| LED3 | C6 | 一整帧 128×72 已发完 | **灭** | 图像发不出去 |
| **LED4** | **D6** | **ARP 请求没收到回应（`arp_request_no_reply_error`）** | **亮** | **ARP 一直失败** |

**更早一版（22:46 构建，映射不同：LED1=`phy_reset` / LED2=`S_pll_lock` /
LED3=`frame_done` / LED4=心跳）的读数**：LED1 亮、LED2 亮、LED3 灭、LED4 闪
→ 即 PHY 复位已释放、视频 PLL 已锁、**一帧图像都没发成**、网络域活着。

### 3.4 由此确定的结论

```
协议栈在生成 TX 帧 ✓（LED2 亮，大概率是反复重发 ARP 请求）
        ↓
   [ tx_client_fifo ] → [ MAC ] → RGMII → PHY → 网线 → PC
        ↑
   断在这一段的某个地方（PC 侧什么都收不到）
```

---

## 4. 排查过程与已排除/未排除的假设

| # | 假设 | 状态 | 依据 |
|---|---|---|---|
| 1 | 复位一直没释放（`reset` 卡住） | ❌ **已排除** | 心跳灯（`udp_clk` 域）在闪 → `udp_clk` 在跑 → PLL 锁定 → `reset_reg=0`；`soft_reset_cnt` 由同一时钟计数，必定到 0 |
| 2 | 发送硬件链路坏了（MAC→PHY） | ❌ **基本排除** | 第 2 步的回环成功，证明当时整条发送链路是通的 |
| 3 | **应用侧 `app_tx_request` 被无限期拉高，占死协议栈的 TX 通路**（协议栈只有一条 TX 通路，还要负责回 ARP、回 ping） | ⚠️ **已修，但没解决问题** | 已在 `tx_frame_sender.v` 加 1ms 超时（超时后放弃本帧、回 `S_IDLE`）+ 接出 `O_tx_abort`。23:29 的 bit **已含此修复，ping 仍不通** |
| 4 | **`rgmii_interface.v` 的时序修复（`tx_reset_txc`）破坏了 TXC 时钟** —— 它是**整条 TX 通路上唯一被动过的地方**；TXC 没了，PHY 就收不到发送时钟，MAC 发什么都不会上线上 | ⚠️ **已回退，但还没上板验证** | 见 §5。综合/布局验证已通过（无错误） |
| 5 | 端口从 2 改成 6666 导致 | ⚠️ 未验证 | 理论上不影响 ping（ping 走 ICMP，与 UDP 端口无关），但未做对照实验 |

---

## 5. 第 2 步遗留的时序修复：已回退（关键！）

### 背景

第 2 步布线后 RGMII 的**TXC ODDR 复位脚**出现 setup 违例，反复重跑无效：

```
12:05 −0.075ns   12:37 −0.236ns   13:1x −0.249ns   13:4x −0.039ns
```

原因：`rgmii_txc_ddr` 挂在 **90° 相移**的 `tx_clk_90` 上，而 `tx_reset` 来自 0° 域
（`temac_block.v:176` 的 `reset_reg2[1]`），STA 按 **2ns** 预算查这条路径，而它
90% 以上是走线。

### 当时的修法（**现已回退**）

试过三次，前两次失败（**别重复**）：
1. 用一个 `tx_reset_io` 驱动全部 6 个 ODDR 复位脚 → 失败：扇出 6、要跨 6 个不同
   IO 单元，一颗寄存器没法同时贴近 6 个位置，走线仍 1.369ns
2. 同时写 `tx_reset_io` 和 `tx_reset_txc` 两颗同逻辑寄存器 → 失败：
   **综合器把两颗合并成一颗**（同域同输入），扇出又回到 6
3. 只给 TXC 那一颗单独打一拍（`tx_reset_txc`）+ `//synthesis keep` → **时序过了**
   （SWNS +0.589），SDC 另加 `set_max_delay 4ns` 兜底

### ⚠️ 为什么回退

第 3 步上板后网口完全发不出去，而 **`rgmii_interface.v` 是整条 TX 通路上唯一
被动过的地方**。第 3 次修法给 ODDR 的复位脚引入了**一个时钟依赖**
（`tx_reset_txc` 由 `tx_clk` 采样才释放），如果它没有正确释放，
**TXC ODDR 会被一直按在复位态 → PHY 收不到发送时钟 → MAC 发什么都不会上线上**，
症状与实测完全吻合。**这只是假设，未证实。**

### 回退后的现状

```verilog
// rgmii_interface.v —— 三个 TX ODDR 全部恢复原版写法
.rst (tx_reset)      // TXC  (原版：直接由 tx_reset 组合驱动，无时钟依赖)
.rst (tx_reset)      // TXD
.rst (tx_reset)      // CTL
// tx_reset_txc 寄存器已删除，只剩注释
```

**时序改由 SDC 单独保证**（`td_project/camera_to_dsi_display.sdc:106`）：

```tcl
set_max_delay 4.000 -datapath_only -to [get_pins {phy1_rgmii_tx_clk_syn_*.rst}]
```

- 这是**准静态复位脚**（运行期恒为失效态），放宽到 4ns 合理
- 同组的 `rgmii_txc_en` 数据路径**仍按 2ns 查**，没有被放宽
- 余量推算：原来在 2ns 预算下只差 0.04~0.25ns，现在给到 4ns → 余量 >2ns
- TD 的时序例外报告确认这条约束**已应用**（匹配 1 条路径）

回退后已跑过 `elaborate → optimize_rtl → optimize_gate → legalize → place`，
**全部 OK、无错误**，但**没有出 bit、没有上板**。

---

## 6. 第 3 步改了什么（文件清单）

| 文件 | 改动 |
|---|---|
| `user_source/hdl_source/vpp_top.v` | **加 4 个输出口** `O_raw_tdata/tvalid/tuser/tlast`，分别接 `raw_rgb_d[21]` 和 `mux_tvalid/tuser/tlast`。只引线，不动现有逻辑 |
| `user_source/hdl_source/design_top_wrapper.v` | 新增 4 根线 `S_cnn_raw_*`；`u_vpp_top` 接出新口；`u_net` 接上 `I_pclk`/`I_pclk_rst_n` + 这 4 根线 |
| `user_source/hdl_source/net/board_a_net_wrapper.v` | ① 加视频取数端口；② **撤掉 `udp_loopback`**；③ 加「帧门控 + cnn_ds10 + pixel_to_bytes + ram_fifo + tx_frame_sender」；④ 目标端口 `2`→**`6666`**；⑤ LED 语义多次调整 |
| `user_source/hdl_source/net/pixel_to_bytes.v` | **新增**：24bit 像素拆 R/G/B 三字节 |
| `user_source/hdl_source/net/tx_frame_sender.v` | **新增**：字节流打 20 个 UDP 包（含 1ms 超时保护） |
| `user_source/hdl_source/cnn/cnn_ds10.v` | **重写 v2**：累加器从 11 520 个触发器改成 3 块 ERAM |
| `user_source/hdl_source/net/rgmii_interface.v` | 先改后**回退**（见 §5） |
| `td_project/camera_to_dsi_display.sdc` | 网络时钟约束 + 上面那条 `set_max_delay` |
| `td_project/camera_to_dsi_display.al` | 登记 3 个新源文件（**但见 §8 的坑**） |
| `sim/tb_cnn_ds10.v`、`sim/PH1P_LOGIC_ERAM_sim.v` | 仿真用（后者**仅仿真**，不要加进工程） |
| `tools/boardA_recv_frame.py` | PC 端收 20 包拼 128×72 存 PNG（纯标准库） |

### 板间协议（板 B 已钉死）

| 项 | 值 |
|---|---|
| 板 A IP / MAC / 本地端口 | `192.168.240.1` / `02:00:00:00:24:01` / `1` |
| **目的 IP / 端口** | `192.168.240.2` / **`6666`** |
| 包结构 | `[seq_hi, seq_lo]` + 图像字节，大端序号 0..19 |
| 包长 | 包 0~18：2+1400=1402；包 19：2+1048=1050；合计 27 648=128×72×3 |
| 字节序 | 逐像素 R,G,B |
| 帧率 | 每 6 帧发 1 帧（≈99ms 一次） |

---

## 7. 下一步该做什么（按性价比排序）

### ① 零成本、立刻可做 —— **看 RJ45 网口上的第二个灯（activity 灯）**

网口上通常两个灯：**链路灯（常亮）+ 活动灯（有数据时闪）**。

> **在板子运行时，活动灯闪不闪？**
> - **闪** → PHY 确实在往线上发信号 → 帧出去了，问题在帧内容或对端
> - **一直不闪** → **实锤"帧没出 PHY"** → 范围压缩到 MAC/RGMII 段

**这是唯一不花任何代价就能知道"PHY 有没有在发"的办法，务必先做。**

### ② 烧录回退版（§5），对比这几个量

改动只有 `rgmii_interface.v`，其他没动。烧完对比：

| 观察项 | 回退前的值 | 回退后 |
|---|---|---|
| `ping 192.168.240.1` | 不通（4/4 丢失） | ？ |
| LED4（D6，ARP 无回应） | 亮 | ？**有效的话应该灭** |
| LED3（C6，一帧发完） | 灭 | ？**有效的话应该常亮** |
| RJ45 活动灯 | ？ | ？ |

### ③ 用静态 ARP 绕开 ARP，一步分清"收"和"发"

板子回不了 ARP 是死结，在 PC 侧把板子的 MAC 写死（**必须管理员权限的 cmd**）：

```cmd
:: 管理员 cmd（Win+X → 终端(管理员)；或开始菜单右键 cmd → 以管理员身份运行）
netsh interface ipv4 add neighbors "以太网" 192.168.240.1 02-00-00-00-24-01
arp -a
ping 192.168.240.1
```

**先用 `arp -a` 确认那一行是"静态"**，否则测试无意义。

| 结果 | 结论 |
|---|---|
| **ping 通了** | 板子的**接收 + 回复发送都是好的** → 问题只出在"板子自己发出的 ARP 请求到不了 PC" |
| **还是不通** | 板子的接收或回复发送断了 → 发送链路中段问题 |

### ④ NetAssist 往 `192.168.240.1:1` 发包 → 看 LED1（D10）闪不闪

LED1 = "板子收到 UDP"。**做了 ③ 的静态 ARP 之后**这一步才能做（否则 PC 发不出去）。

- 闪 = **接收通路没问题**
- 不闪 = 接收也断了（方向完全不同）

### ⑤ Wireshark 抓包（最有力）

抓「以太网」那块网卡，过滤 `arp`，然后 ping 一次：
- 看到 PC 的 ARP 请求、**没有任何回复** → 板子确实一声不响
- 看到板子（`02:00:00:00:24:01`）发了**任何**帧 → 板子在发东西，问题在帧内容

（Windows 10/11 自带 `pktmon` 也能抓，但 Wireshark 直观得多。）

### ⑥ 如果上面都指向"帧出不去"，考虑的对照实验

- **把第 3 步的应用层换回 `udp_loopback`**，其他（网络链路、约束、端口）保持第 3 步的状态：
  - 如果换回后 ping 通了 → 问题在**第 3 步新增的应用层逻辑**（`cnn_ds10`/`pixel_to_bytes`/`tx_frame_sender`/帧门控/FIFO）
  - 如果换回后 ping 仍不通 → 问题**不在第 3 步的应用层**，而在同时改动的其他地方（端口、`.al`、约束）
- 这是**最干净的二分**，建议在 ①②③④⑤ 都没定论时做

---

## 8. 千万别重复的坑（都踩过了）

### 8.1 `.al` 绝对不能手改 —— TD 会在无头流程结束时覆盖它

实测：手工往 `td_project/camera_to_dsi_display.al` 加源文件条目，跑一次无头流程后
**条目被 TD 按它自己的文件表重写掉了**，第二次跑就全是
`HDL-7144 unknown module` / `HDL-8007 is a black box`。

- **验证用**：每次跑前把条目补回去
- **正式构建**：**必须由人在 TD 图形界面里登记**这 3 个文件：
  `net/pixel_to_bytes.v`、`net/tx_frame_sender.v`、`cnn/cnn_ds10.v`
- 截至本记录，`.al` 里这 3 个条目**是在的**

### 8.2 指导文档 §7.6 的 `tx_frame_sender` 是错的

`udp_ip_protocol_stack` 的应用侧 TX 是「request → 等 ack → 连续喂数据」，
**第一个字节必须与 `tx_valid` 同一拍就绪**，否则第一个字节取到上一包的残留、
整包错位一格。指导文档那段只拉 `tx_valid` 没装首字节 → **照抄必错**。

正确参考：`D:\TD_project\cnn_boardB\src\net\result_sender.v:179`（板上验证过的）：
```verilog
if (tx_ack) begin
    tx_valid <= 1'b1;
    tx_data  <= 8'hAA;   // 第一字节与 tx_valid 同拍就绪
```
本工程的 `tx_frame_sender.v` 按这个写法重写，并逐拍推演了与 show-ahead FIFO 的配合。

### 8.3 指导文档 §7.3 的 `video_to_axis.v` 根本不需要

`vpp_top` 本身就是 `tvalid/tuser/tlast` 流（ISP/DDR 那条链路全是），
`mux_tvalid/tuser/tlast` 与 `raw_rgb_d[21]` 严格同拍。
**给 `vpp_top` 加 4 个输出口即可，少一个模块。**

### 8.4 别把 `rx_clk` 域的信号引进 `udp_clk` 的观察逻辑

SDC 里 `phy1_rgmii_rx_clk` 和 `udp_clk_*` 在**同一个** `set_clock_groups` 组里，
**同组内的路径仍然会被分析**。所以观察灯只用本来就在 `udp_clk` 域的信号
（`app_rx_data_valid`、`temac_tx_valid`、`arp_request_no_reply_error` 等），
不要用 `rx_correct_frame` / `tx_clk_en` 这类跨域信号。

### 8.5 手工复制寄存器会被综合器合并

同一个时钟、同一个输入的两颗寄存器，综合器会合并成一颗（见 §5 的第 2 次失败）。
想强制分开要用 `//synthesis keep`，但**即使分开也未必有用**（见 §5 第 1 次失败）。

### 8.6 其它小坑

- TD 无头调用：`td_commands_prompt.exe <script.tcl>`，**Tcl 参数必须用正斜杠**
  （反斜杠会被 Tcl 当转义，报 `couldn't read file "C:Users..."`）
- 无头流程跑 run 目录时，`syn_1/`、`phy_1/` 里的 **`.prj` 可能是过期的**（不含新文件）。
  可以绕过：直接 `open_project {camera_to_dsi_display.al} -single_run` 走 `.al` 的文件表
- TD 在 `elaborate` 之后、`optimize` 之前查时钟（`report_clock_summary` 等）会 **coredump**，
  不要在那一阶段查时钟
- **电源**：`td_commands_prompt.exe` 里 PowerShell 变量名大小写不敏感，
  `foreach ($f ...)` 会覆盖 `$F` —— 用不同的名字
- ModelSim 10.4 的 `vsim` **没有 `-work` 选项**，要用 `vsim -c <库>.<顶层>`
- 仿 `PH1P_LOGIC_ERAM` 需要 `sim/PH1P_LOGIC_ERAM_sim.v`（厂商原语，ModelSim 里没有）

### 8.7 隔离综合的数字不可信（资源估算）

`cnn_ds10` 隔离综合说 3 369 slice，实际在真设计里是 **8 626**（把全芯片顶到 123%）。
**只有布线后 `phy_1/*.area` 的数字算数。**

---

## 9. 第 3 步「功能目标」本身的进度（顺便记录）

图像发送通路的**设计与验证都做完了**，只差上板：

| 项 | 状态 |
|---|---|
| `cnn_ds10` v2（ERAM 累加器） | ✅ 仿真 9216 块 0 错；`u_cnn_ds10 = 136 LUT + 114 FF + 3 ERAM + 1 DSP`（原 v1 是 9 206 LUT + 11 619 FF） |
| 综合 / 布线 / 时序 | ✅ 违例 0；`#slice` 85.4%（加了整条图像通路只比第 2 步多 61 个 slice） |
| 帧门控 / 跨时钟 FIFO / 20 包发送 | ✅ 代码完成、综合通过 |
| **上板发图** | ❌ **未成功**（LED3 不亮；与网口不通这个问题交织在一起） |
| PC 端收图脚本 | ⚠️ 已写（`tools/boardA_recv_frame.py`，纯标准库），**从未运行过**（本机没装 Python） |

**验收标准**（网口修好后做）：
```powershell
# PC 网卡设成 192.168.240.2，防火墙放行入站 UDP 6666
cd D:\TD_project\lab_ex1_mipi_hdmi_SC500_720P+vpp
python tools\boardA_recv_frame.py --count 5 --scale 8
# 期望：每帧打印 20 行 pkt 0..19，存出 128x72 彩色小图，内容与 HDMI 画面一致
```

---

## 10. 相关文档

| 文档 | 内容 |
|---|---|
| `docs/板A以太网改造_实施计划.md` | 总计划、铁律、风险与回退 |
| `docs/板A以太网改造_第2步实施记录.md` | 第 2 步（含 TXC 时序修复全过程） |
| `docs/板A以太网改造_第3步实施记录.md` | 第 3 步（含 `cnn_ds10` 重写、坑、验收步骤） |
| `docs/A板以太网改造方案.md` | 最初的改造方案 |
| `docs/HX1P35A双板以太网级联实施指导.md` | ⚠️ 早期草稿，**§7.3 / §7.6 有错**（见 §8.2/8.3） |
