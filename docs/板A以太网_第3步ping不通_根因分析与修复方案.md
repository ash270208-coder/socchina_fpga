# 板A以太网 第3步「ping 不通 + 图发不出去」根因分析与修复方案

> 记录时间：2026-10-11 ｜ 对应《[板A以太网_第3步ping不通_调试交接.md](板A以太网_第3步ping不通_调试交接.md)》
>
> **本文的结论分三档，请严格区分**：
> - **【实测】** 我在本机用 ModelSim SE-64 10.4 跑出来的数字（可复现，命令见 §7）
> - **【静态确认】** 从 RTL / 综合报告 / 布线报告 / 构建产物里核对出来的事实
> - **【推断】** 由机制推出的结论，没有硬件复现（已在文中标注）

---

## 0. 一句话结论

**第 3 步引入的发送侧应用逻辑有两个独立缺陷：**

1. **`tx_frame_sender` 里那个 1ms ack 超时**（v1 的"等不到 ack 就放弃本帧"）
   每 1ms 就把 `app_tx_data_request` 拉低一次，**在协议栈 400ms 的 ARP 解析窗口里
   把请求线抖了 400 次**。而板 B 实机验证过的 `result_sender.v` 和官方
   `udp_loopback.v` 都是**一直拉着 request 直到 ack**。这是与协议栈的握手违规。
   **→ 这是"ping 不通"最可疑的根因（【推断】，机制见 §3）。**

2. **图像通路的速率/背压架构是错的**：生产者 `cnn_ds10` 瞬时 18.75 MB/s，
   消费者（20 个包 / 100ms）只有 0.28 MB/s；而帧门控只门了"哪一帧被采"，**没有门住
   写入速率，也没有背压**。FIFO 必然饱和 → 每 100ms 丢掉 83% 的帧数据；
   发送侧一旦 FIFO 常满就退化成"自由奔跑"（`S_FILL` 一拍就过），包边界与帧边界
   永久脱钩；**而且读到空 FIFO 时 v1 会继续 `fifo_rd`+`O_tx_data<=I_fifo_q`，
   把同一个字节重复发很多次**。**→ 这是"图发不出去 / LED3 不亮"的根因（【实测】）。**

3. **诊断灯接错了信号，把排查方向带偏了**：`temac_tx_valid` 是**协议栈送给 MAC 的
   "我要发数据"**，不是"MAC 真的在发帧"；`app_rx_data_valid` 只统计**UDP 载荷**，
   ARP / ICMP 一律不计。所以"LED2 亮 = 协议栈确实在生成发送帧""LED1 灭 = 板子收不到"
   这两条判读都是无效的。**→ 换正确的信号后，才能一刀切开"收"和"发"（【静态确认】）。**

---

## 1. 先纠正三个事实性错误（这决定了后面怎么查）

### 1.1 你实际烧进去的那个 bit，用的是**带 `tx_reset_txc` 的第 3 步版本**

交接文档 §4 把"`rgmii_interface.v` 的 TXC 时序修复"列为假设 4，并说"已回退，但还没上板验证"。
核对构建产物后，实际情况是：

| 时间 | 事件 | 证据 |
|---|---|---|
| 19:25:22 | `_s3f.bit`（1 789 539 B）生成，**含 `tx_reset_txc`** | `td_project/_s3f_route.qor`、`_s3f_exception.timing` 里路径起点是 `u1_rgmii_interface/tx_reset_txc_reg_syn_3` |
| 22:50:39 | 无头 TD 完整构建（带 4 个网口观察灯） | `td_project/td_20261010_225039.log` |
| 23:05 | 提交 `530c590`（led 语义、S_REQ 超时都在里面） | `git show --stat 530c590` |
| 23:15 / 23:34 | 两次无头 TD **都在启动时失败**（脚本被 GBK 误解码） | 两个日志只有 455 B，内容是 `invalid command name "閿樼斧roc"` |
| 23:41~23:49 | TD 图形界面重跑完整流程出 bit | `phy_1/camera_to_dsi_display.bit` 时间戳 23:49:21 |

**结论**：**23:49 那个 bit 是"已回退 TXC + led 直连 + tx_frame_sender 带 1ms 超时"**，
但你 ping 测试时烧的应该是 22:50 或更早的、**带 `tx_reset_txc`** 的版本。
交接文档 §4 假设 4"已回退但未验证"是对的，但**"回退版是否修好了"这个问题至今没有答案**。

> ⚠️ 另外：**23:15 和 23:34 那两次无头构建根本没跑起来**。交接文档 §7 说的
> "23:29 构建"在日志里找不到对应记录，请以 23:49 这次（GUI）为准。

### 1.2 `tx_reset_txc` 在功能上几乎不可能是元凶（可以降级）

我逐拍推演了 `ODDR` 的 `ASYNCRST("ENABLE")` 行为：复位有效时 Q 恒为复位值，
`tx_reset` 释放后一拍 `tx_reset_txc` 也跟着释放，ODDR 从下一个 90° 时钟沿起正常翻转。
**它只会让 TXC 多延迟 8ns 开始翻转，不会让 TXC 停住。**

- 交接文档担心的"TXC 被一直按在复位态"不成立：`tx_reset_txc` 是 `tx_clk`（0°）域寄存器，
  主复位释放后**必定**会释放，没有任何东西能把它锁住。
- 19:25 的 STA 也证明这条路径是收敛的：`Slack 1.946ns`、`Data Path Delay 1.341ns`、
  预算 2ns（`net_pll_clk_125m_0` 0° → `...clkc[4]` 90°，8ns 周期的 1/4 = 2ns）。

**所以 §4 假设 4 可以降到最低优先级**，不必再围着它转。

### 1.3 第 3 步的设计**确实完整进了 bit**（不是"新文件没被综合"）

交接文档 §8.1 的 `.al` 坑确实存在，但这次没踩到。综合报告的实例表里有真实资源：

```
|  u_net            |board_a_net_wrapper |2280 |666 |3986 |10 |1 |...   ← 10 ERAM / 1 DSP
|    u_cnn_ds10     |cnn_ds10            | 136 |105 | 114 | 3 |1 |...   ← 3 ERAM / 1 DSP
|    u_img_fifo     |ram_fifo            |  49 | 41 | 102 | 2 |0 |...   ← 2 ERAM
|    u_p2b          |pixel_to_bytes      |  22 |  0 |  37 | 0 |0 |...
|    u_sender       |tx_frame_sender     |  46 | 29 |  55 | 0 |0 |...
```

（来源：`td_project/camera_to_dsi_display_Runs/syn_1/camera_to_dsi_display_gate.area`）

**而且时序是干净的**——`phy_1/camera_to_dsi_display_phy.ts`（23:49 布线后）：

```
SWNS: 0.364ns, STNS: 0.000ns
HWNS: 0.020ns, HTNS: 0.000ns
```

逐组看（`final_timing.rpt`）：

| Path Group | SWNS | 违例端点 |
|---|---|---|
| `phy1_rgmii_rx_clk -> phy1_rgmii_rx_clk` | **+1.173ns**（946 个端点） | 0 |
| `udp_clk_125m -> udp_clk_125m` | +0.364ns | 0 |
| `net_pll_clk_125m_0 -> ...clkc[4]`（0°→90°，TXC） | +0.542ns | 0 |
| 其余全部 | 正 | 0 |

**所以"时序没收敛导致网口不工作"这条路可以彻底排除。**
（顺带：`phy1_rgmii_rx_clk` 组 +1.173ns 说明 RX 采样窗口很宽裕，
`set_input_delay 2.0~2.8` 那组约束在 23:49 这一版里**不是**瓶颈。）

---

## 2. 根因 1：图像通路的架构是错的（【实测】+【静态确认】）

### 2.1 速率账（先算清楚，这是所有问题的源头）

【静态确认】`cnn_ds10.v:180-211` 的排空节奏是 **4 拍 1 个块**（注释和 RTL 一致）：

```
生产者：75 MHz / 4 拍 = 18.75 M 字节/s（每帧激活 1280x720/75M ≈ 15.2ms，帧率 60fps）
        cnn_ds10 只在 fsel==0 那一帧输出 → 每 6 帧采 1 帧
        → 每个"采帧窗口"产出 27 648 字节，耗时 27 648 x 4 / 75M ≈ 1.47 ms

消费者：一帧 20 个包，100 ms 一次
        27 648 字节 / 100 ms = 0.277 MB/s

比值：18.75 / 0.277 ≈ 68 倍
```

`cnn_ds10` 输出一帧要 1.47 ms，而发送侧在 125 MHz 下发完 20 个包只要
`27 648 / 125M ≈ 221 µs`。**消费者比生产者快 6.7 倍**，所以：

- 发送侧一旦启动，**必然**在 221 µs 内把 FIFO 抽干（生产者只来得及再供 ~4 KB 的 1/6）；
- 生产者每个采帧窗口硬塞 27 648 字节，而 FIFO 只有 4 096 字节
  → **每个帧窗口至少要丢 23 KB（83%）**。

而帧门控 `gate` 只作用在 `pixel_to_bytes` 的**写使能**上（哪一帧被采），
**既不背压、也不限速**。所以另外 5 帧虽然 `gate=0` 不写，但被采的那一帧本身
就已经远超 FIFO 容量。

### 2.2 三个衍生故障

```
① FIFO 长期饱和
   → 后面的帧把前面的帧挤掉，20 个包的字节流里混着不同帧的数据
   → 板 B 拼出来的图必然全错（即使 ping 通了也收不到正确的图）

② S_FILL 形同虚设、发送侧"自由奔跑"
   v1 的 S_FILL 只要 fifo_cnt >= 1400 就放行。FIFO 一旦常满，这个条件**一拍就过**
   → 发送侧不再与 frame_start 对齐，包边界与帧边界永久脱钩
   → 这也意味着 app_tx_data_request 长期处于"想发就发"的状态

③ 读到空 FIFO 时重复发同一个字节（★ 最直接的"图错"原因）
   ram_fifo.v:175   assign fifo_re = (re & (!fifo_empty));
   ram_fifo.v:246   .addrb(rdaddress + (SHOW_AHEAD_EN & fifo_re));
   → 读空时读地址不再前进、do 保持旧值
   但 v1 的 S_SEND 里是**无条件** O_fifo_rd<=1 且 O_tx_data<=I_fifo_q
   → 只要 FIFO 读空，同一个字节就会被反复发出去
   → 包长度还是对的，内容全错
```

---

## 3. 根因 2：和协议栈的握手违规（【实测】+【推断】）

### 3.1 一条被忽略的关键线索

`arp_request_no_reply_error` 这个信号**只有在协议栈自己发起 ARP 解析时才会亮**。
而协议栈**只会为了"应用层要发出去的东西"去做 ARP**（回复 ping / 回复 ARP 请求
都不需要主动解析对端 MAC）。

**所以 LED4 亮 = 应用层确实在请求发往 192.168.240.2。** 这条线索说明：
第 3 步之后板子在**主动**尝试解析 `.2`，而不是被动应答。

### 3.2 协议栈的 ARP 参数（从加密 IP 的端口表读到）

```verilog
module udp_ip_protocol_stack #(
    parameter ARP_REQUEST_NUM   = 3,
    parameter ARP_REQUEST_DELAY = 27'h0ffffff,   // 16 777 215 拍 @125MHz ≈ 134 ms
    ...
```

→ **一次 ARP 解析最长要 3 x 134ms ≈ 400ms 才判失败。**

### 3.3 v1 的 1ms 超时干了什么

【实测】ModelSim（`sim/tb_s3_sender.v`，命令见 §7）：

```
---- Test A: ack held low (ARP unresolved), 250000 clocks ----
  v1: tx_abort=1  tx_request duty=98%
  v2: tx_abort=0  tx_request duty=99%
  -> v1 drops tx_request every 125000 clocks = 1000 us
  -> v2 never drops it (same as board B result_sender / official loopback)
```

即：**ack 不来的时候，v1 每 1ms 必然把 `app_tx_data_request` 拉低一次。**
在 400ms 的 ARP 窗口里，请求线被抖动 **~400 次**。

### 3.4 为什么这是违规（对照两个已验证的实现）

| 实现 | 握手写法 | 状态 |
|---|---|---|
| `cnn_boardB/src/net/result_sender.v` | `S_REQ: tx_request <= 1'b1; if (tx_ack) ...` **无任何超时** | **板 B 实机验证过** |
| 官方 `net/udp_loopback.v:126-142` | `WAIT_ACK` 里死等 `app_tx_ack`，**无超时** | 第 2 步板 A 实机验证过 |
| 本工程 v1 | `S_REQ` 里 1ms 等不到 ack 就放弃 | ❌ **是唯一一个抖请求线的** |

**两个"能用的"参考实现都是"一直拉着 request 直到 ack"。这就是协议栈期望的用法。**
v1 的出发点（交接文档 §4 假设 3："怕把 TX 通路占死，所以加超时让出去"）方向是反的：
**真正会把通路占死的是"请求线抖动 / 应用层反复重入"，而不是"老老实实等 ack"。**

### 3.5 修复后的预期行为（【推断】）

`arp_request_no_reply_error` 亮，说明栈在"请求已发出但没收到回应"的状态。
把请求线稳住不动之后：

- 栈可以走完自己的 ARP 重试序列（3 x 134ms），要么解析成功、
  要么干净地报一次失败，而不会在 400ms 里被重入 400 次；
- ARP / ICMP 回复和应用包共用同一条 TX 通路时，仲裁由**协议栈内部**做
  （板 B 就是这么跑的），不需要应用层"让路"。

> ⚠️ **【推断】声明**：我无法在仿真里证实"抖请求线一定会让 ARP 失败"，
> 因为 `udp_ip_protocol_stack_merge.enc.v` 是加密 IP，ModelSim 里跑不了它的内部逻辑。
> 但这是**两个已实机验证的实现都遵循、而唯一不工作的实现违反**的握手契约，
> 且它同时能解释 `arp_request_no_reply_error` 常亮。§6 给了零成本的决定性实验来判它。

---

## 4. 根因 3：诊断灯接错了信号（【静态确认】）

这是**最省事、收益最大**的一条，因为它直接决定后面怎么查。

| 灯 | 原来接的 | 它**真正**的含义 | 应该接 |
|---|---|---|---|
| `led[0]` D10 | `app_rx_data_valid` | 协议栈校验通过、**且目标是本机 UDP 端口 1** 的 UDP 载荷。**ARP / ICMP 一律不计** | `temac_rx_valid`（已由 `rx_client_fifo` 同步到 `udp_clk` 域）→ **任何**到达 MAC 的帧都算 |
| `led[1]` E10 | `temac_tx_valid` | **协议栈送给 MAC 的"我要发数据"**，不是 MAC 真的在往线上发 | `temac_tx_ready`（TEMAC 正在取走这一帧） |
| `led[2]` C6 | `snd_frame_done` | "20 个包已喂给协议栈"（**不代表电脑收到**） | 保持（语义本身是对的，只是别过度解读） |
| `led[3]` D6 | `arp_request_no_reply_error` | 协议栈自己的 ARP 解析失败 → **应用层在主动请求发往 `.2`** | 保持（这条是有效的） |

**所以交接文档 §3.4 的结论"协议栈在生成 TX 帧 ✓（LED2 亮）→ 断在 tx_client_fifo → MAC → RGMII → PHY"
第一步就错了**：LED2 亮只能证明"协议栈有发送意图"，`tx_client_fifo` / MAC / RGMII
这一段**根本没有被观测到**。同理 LED1 灭**不能**推出"PC 的包没到板子"。

---

## 5. 已落地的修复（代码已经改好）

### 5.1 `net/tx_frame_sender.v` —— 重写为 v2（**已完成，已仿真对照**）

三处改动，文件头有详细说明：

| # | 改动 | 原因 |
|---|---|---|
| 1 | **删掉 `ACK_TIMEOUT` / `O_tx_abort` 逻辑**：`S_REQ` 里 request 拉高后一直保持到 ack | 见 §3；与 `result_sender.v` / `udp_loopback.v` 对齐 |
| 2 | **新增 `I_fifo_empty` 输入**：`S_SEND` 且 `idx>=2` 且读空时**冻结**（不推进 idx、不抬 fifo_rd、保持 `O_tx_data`） | 见 §2.2③；防止重复发同一字节，并让发送速率自动跟随生产者 |
| 3 | 保留 `S_FILL` 的"攒够一整包再发" | 配合写侧背压，帧边界才能对齐 |

**接口变化（例化处必须同步改）**：新增 1 个输入 `I_fifo_empty`；
`O_tx_abort` 保留但不产生脉冲。

### 5.2 `net/board_a_net_wrapper.v` —— 三处（**已完成**）

```verilog
// ① 写侧背压
localparam [13:0] FIFO_HIGH = 14'd3072;
wire        fifo_block = (fifo_cnt >= FIFO_HIGH);
wire        img_we   = pb_we & ~fifo_full & ~fifo_block;

// ② 把 fifo_empty 接进发送器
.I_fifo_empty   (fifo_empty),

// ③ 两个诊断灯换成正确的信号
else if (temac_rx_valid)  rx_led_cnt <= ...;   // net_led[0]
else if (temac_tx_ready)  txact_led_cnt <= ...; // net_led[1]
```

### 5.3 还需要你确认/做的事

| # | 事项 | 说明 |
|---|---|---|
| 1 | **在 TD 图形界面重跑 syn + P&R + bitgen** | 改了 2 个 `.v`，必须重跑；无头流程注意 `.al` 会被覆盖（交接文档 §8.1） |
| 2 | 时序应仍然违例 0 | 新增逻辑极少（1 个比较器 + 2 个 mux）；若 `udp_clk_125m` 组（现 +0.364ns）变差，优先看 `fifo_cnt >= 3072` 这个比较器 |
| 3 | 上板后按 §6 的顺序做验证 | **先 ping，再看图** |

---

## 6. 上板验证顺序（按"性价比"排序，前两步零成本）

### ① 【必做】先烧**第 2 步的 bit** 做对照

`.git` 里有第 2 步的 bit（`5271175`），或直接用 `camera_to_dsi_display_Runs/best_result/` 里的历史版本。

| 结果 | 结论 |
|---|---|
| **ping 通** | PC / 网线 / 板子硬件都是好的 → 问题**确定**在第 3 步的改动里，继续 ③ |
| **ping 也不通** | 问题不在第 3 步！先查 PC 网卡设置、ARP 缓存、网线、板子供电/复位 |

这一步能一刀砍掉一半的可能性，**不做就是浪费时间**。

### ② 换灯之后重测，看 `arp` 有没有被板子收到

烧上 §5 的新 bit，`ping 192.168.240.1` 之后看：

| led[0]（收到任何帧） | 结论 |
|---|---|
| **闪 / 亮** | 板子的**接收通路是好的**，PC 的 ARP 请求到了 MAC → 问题在"发"或"协议栈处理" |
| **灭** | 板子的**接收通路断了** → 方向完全不同，去查 RGMII RX / `rx_client_fifo` |

（这一步在旧灯下是**做不到**的，见 §4。）

### ③ 如果 ① 通、② 里 led[0] 闪，但 ping 仍不通 → 二分：换回 `udp_loopback`

把应用层换回官方 `udp_loopback`（网络链路 / 约束 / 端口全部保持第 3 步的状态），重出 bit：

| 结果 | 结论 |
|---|---|
| ping 通 | 问题**就在第 3 步的应用层**（v2 修复应该能解决；若仍不通，说明是别的应用层副作用） |
| ping 仍不通 | 问题**不在应用层**，而在同时改动的其他地方（RGMII 改动 / `.al` / SDC） |

### ④ Wireshark / `pktmon` 抓包（最有力）

过滤 `arp or icmp`，然后 ping 一次：

- 看到 PC 的 ARP 请求 + **板子 `02:00:00:00:24:01` 的 ARP 请求**（板子在解析 `.2`）
  → 板子在发，看 PC 有没有回 ARP 应答；
- 看到板子发了 `.2` 的 ARP 请求但 PC 没回 → 查 PC 的 ARP 防火墙 / 网卡设置；
- **什么都看不到** → 帧确实没出 PHY，回到物理层。

### ⑤ 【验收】图

```powershell
# PC 网卡 192.168.240.2 / 255.255.255.0，防火墙放行入站 UDP 6666
python tools\boardA_recv_frame.py --count 5 --scale 8
```

**期望**（v2 修好之后）：`led[2]` **常亮**（每 6 帧发一帧 ≈100ms < 展宽 200ms）、
`led[3]` **灭**、脚本能收到 20 包并拼出正确的 128x72 图。

---

## 7. 仿真复现（我实际跑过的命令）

新增的验证文件（都在 `lab_ex1_mipi_hdmi+vpp/sim/`，**不进工程、不进 `.al`**）：

| 文件 | 用途 |
|---|---|
| `tb_s3_sender.v` | v1 vs v2 对照：ARP 未解析时的请求线抖动；FIFO 读空时的字节重复 |
| `tx_frame_sender_v1.v` | v1 的冻结副本（从 git `HEAD` 取出并改模块名），做对照用 |

```powershell
cd <工程>\sim
$env:PATH = "E:\Modelsim\win64;" + $env:PATH
vlib work_s3
vlog -work work_s3 tx_frame_sender_v1.v ..\user_source\hdl_source\net\tx_frame_sender.v tb_s3_sender.v
vsim -c -do "run -all; quit -f" work_s3.tb_s3_sender
```

> ⚠️ ModelSim 10.4 的 `vsim` **没有 `-work` 选项**，库名要写成 `<lib>.<top>`。
> 生成 `tx_frame_sender_v1.v` 时**不要用 PowerShell 的 `Out-File`/`Set-Content -Encoding UTF8`**
> （会加 BOM，vlog 报 `unexpected non-printable character`）。
> 本次用 `[System.IO.File]::WriteAllText($path,$txt,(New-Object System.Text.UTF8Encoding($false)))`。

**实测输出（Test A，已确认）**：

```
=== tb_s3_sender : v1 (flashed) vs v2 (fixed) ===
---- Test A: ack held low (ARP unresolved), 250000 clocks ----
  v1: tx_abort=1  tx_request duty=98%
  v2: tx_abort=0  tx_request duty=99%
  -> v1 drops tx_request every 125000 clocks = 1000 us
  -> v2 never drops it (same as board B result_sender / official loopback)
```

**Test B（FIFO 读空时的字节重复）**：这一版的 starvation 激励我还没调对
（`img_bytes=0`，说明发送侧没进入 S_SEND），**结论待补**。
但重复字节的机制已经由 RTL 直接确认（§2.2③：`fifo_re = re & !fifo_empty`
而 v1 无条件推进），v2 的"冻结"逻辑是按这个机制针对性加的。

---

## 8. 千万别再重复的坑（本次新增）

| # | 坑 | 说明 |
|---|---|---|
| 1 | **用 `temac_tx_valid` 判断"MAC 在发帧"** | 它是协议栈的输出，不是 MAC 的活动。要用 `temac_tx_ready` |
| 2 | **用 `app_rx_data_valid` 判断"板子收到包"** | 它只统计 UDP 载荷；ARP/ICMP 不算。要用 `temac_rx_valid`（已在 `udp_clk` 域） |
| 3 | **给协议栈的应用侧 TX 加"超时放弃"** | 板 B `result_sender.v` 和官方 `udp_loopback.v` 都是死等 ack。协议栈自己会仲裁 ARP/ICMP/应用包 |
| 4 | **以为"帧门控"能解决速率匹配** | 门控只决定"采哪一帧"，不提供任何背压。生产者/消费者差 68 倍时，FIFO 必须有背压 + 发送侧必须能停 |
| 5 | **在 `S_SEND` 里无条件推 `fifo_rd`** | `ram_fifo` 读空时地址不动、`do` 保持旧值 → 会重复发同一字节。必须用 `empty_flag` 冻结 |
| 6 | **拿 `_s3f_phy.ts` 的 `SWNS +0.291` 当 19:25 的结论** | `_s3f_route.qor` 里 `Setup WNS = 291`，与 `_s3f_phy.ts` 一致；但**路线不一样**（一个无头、一个 GUI），资源也不同（18 126 vs 16 773 slice） |
| 7 | **PowerShell 生成 Verilog 文件** | `Out-File`/`Set-Content -Encoding UTF8` 会写 BOM，vlog 直接报错。用 .NET 的 `UTF8Encoding($false)` |

---

## 9. 相关文档

| 文档 | 内容 |
|---|---|
| [板A以太网_第3步ping不通_调试交接.md](板A以太网_第3步ping不通_调试交接.md) | 问题交接（本文是对它的分析结论） |
| [板A以太网改造_第3步实施记录.md](板A以太网改造_第3步实施记录.md) | 第 3 步实施记录 |
| [板A以太网改造_第2步实施记录.md](板A以太网改造_第2步实施记录.md) | 第 2 步（含 TXC 时序修复全过程） |
| [A板以太网改造方案.md](A板以太网改造方案.md) | 最初的改造方案 |
| [HX1P35A双板以太网级联实施指导.md](HX1P35A双板以太网级联实施指导.md) | ⚠️ 早期草稿，§7.3 / §7.6 有错 |
