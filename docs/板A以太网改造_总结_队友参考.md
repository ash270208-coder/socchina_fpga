# 板A以太网 改造总结（队友参考版）

> 记录时间：2026-10-11 ｜ 状态：**单板 ping + 图像发送已打通**
> 面向对象：接手板 A 以太网改造的队友，**不需要重新踩我们踩过的坑**。

---

## 0. 一句话结论

**板 A 以太网改造已经跑通了**：ping 4/4 通、UDP 图像正常发出。

过程中最关键的发现是：**安路的加密 UDP/IP 协议栈有一个致命限制——不能"主动发"**。
具体说：应用层一旦往一个**还没解析出 MAC 的地址**（ARP 缓存为空）主动请求发送，
协议栈就会在 ARP 解析这一步**内部死锁**，导致整个网口 TX 彻底瘫痪（连 ARP 请求、
ping 回复都发不出去）。

所以最终架构的核心原则只有一条：

> **板子绝不主动发，必须"先收到帧、学到对端 MAC 之后"才发。**

---

## 1. 根因（务必先理解这个）

### 现象

- 第 2 步（UDP 回环）ping 通、回环正常。
- 第 3 步（图像发送）之后，ping 不通、ARP 表拿不到板子 MAC。

### 定位过程（用 Wireshark 一锤定音）

抓包显示：**图像发送器一旦工作，板子从头到尾一个帧都不发**——连它自己的 ARP
请求「who has .2」都发不出去，也回不了 PC 的「who has .1」。

### 机制（死锁）

```
应用层主动请求发送（app_tx_request）
   → 协议栈要发往 .2，但 ARP 缓存为空 → 需要先 ARP
   → 而 ARP 请求要用同一条 TX 通路发 → 但 TX 通路被"待发送的应用请求"占着
   → 应用等 app_tx_ack，协议栈等 ARP 应答，ARP 请求发不出去
   → 死锁，永久卡死
```

### 为什么"被动发"没事

- UDP 回环：收到包之后才发，对端 MAC 已经从收到的包里学到了 → 不需要 ARP。
- 板 B result_sender：收到图之后才回，同理。
- 图像发送器：**开机就主动发**，ARP 缓存空 → 触发死锁。

**结论：这个协议栈只能"应答"，不能"主动发起"。**

---

## 2. 版本演进（从第 2 步到最终版）

| 版本 | 应用层 | ping | 结论 |
|---|---|---|---|
| 第 2 步 | `udp_loopback`（被动回环） | ✅ 4/4 | 基线，已验证 |
| 第 3 步 v1 | `tx_frame_sender`（手写 TX，1ms 超时） | ❌ | 手写 app-TX 是错误方向 |
| 第 3 步 v2 | 同上，去超时 + 读空冻结 | ❌ | app_tx_request 常亮，卡死 |
| 整帧就位 | FIFO 加深到 32768，攒够整帧再发 | ❌ | 不是数据够不够的问题 |
| 等 tx_ready | 请求前等 `udp2app_tx_ready` | ❌ | 不是握手时序问题 |
| 静默+超时+退避 | 3s 静默 + 800ms 超时 + 300ms 退避 | ❌ | 不是 ARP 时序问题 |
| 包长减半 | 1402 → 512 | ❌ | 不是包大小问题 |
| **loopback-reuse** | `image_feeder` + `udp_loopback` | ❌ | 方向对了，但仍主动发 → 死锁 |
| **被动化（最终）** | feeder 加 `rx_seen` 门 + 修极性 | ✅ **4/4** | **成功** |

### 三个"分水岭"实验（用开关做的单变量二分）

| 实验 | 说明 | 结果 |
|---|---|---|
| `USE_NO_APP=1` | 发送器例化但**从不驱动 app_tx** | ping 4/4 → 证明"驱动 app_tx 即死" |
| `USE_LOOPBACK=1` | 应用层换回回环，其余全同第 3 步 | ping 4/4 → 证明图像通路/RGMII/时序全无罪 |
| Wireshark 抓包 | 看线上有没有板子的帧 | 一个都没有 → 证明是协议栈内部死锁 |

---

## 3. 最终工作架构

```
视频取数 vpp_top(raw_rgb_d[21] + tvalid/tuser/tlast)
   → cnn_ds10      10×10 块平均降采样 1280×720 → 128×72
   → pixel_to_bytes  24bit 像素拆 R/G/B 三字节
   → img_fifo      异步 FIFO（写 pclk 75MHz / 读 udp_clk 125MHz，深 32768）
   → image_feeder  读 FIFO，拆成 20 个 UDP 包，喂给 udp_loopback 的"收口"
   → udp_loopback  官方回环模块当 TX 引擎（验证过的 app-TX 握手）
   → udp_ip_protocol_stack → TEMAC → RGMII → PHY → 网线
```

### 关键点：为什么用 `image_feeder` + `udp_loopback`

- **官方 `udp_transmit_test.v` 的"主动发送"就是这么做的**：把数据发生器喂进
  `udp_loopback` 的 `app_rx_*` 口，loopback 那套验证过的握手把数据发出去。
- **官方从未手写过 app-TX 状态机**。我们之前手写的 `tx_frame_sender` 是唯一一个
  这么干的，结果把协议栈卡死了。
- `image_feeder` 就是那个"数据发生器"，只是数据来自真实图像而非固定图案。

### 关键点：`rx_seen` 被动化门

```verilog
// 收到过任何帧（temac_rx_valid 低有效，0=有帧）才允许 feeder 喂数据
if (~temac_rx_valid) rx_seen <= 1'b1;
// 再延迟 100ms 确保 ARP 学完
// feeder 只在这之后才动手
```

原理：你 ping 板子时，PC 的 ARP 请求（源 IP 就是 .2）会让板子**被动学到 PC 的
MAC**；之后板子发图就不需要主动 ARP 了，死锁解除。

---

## 4. 最终文件改动清单

| 文件 | 改动 | 性质 |
|---|---|---|
| `net/board_a_net_wrapper.v` | ① img_fifo 深 4096→32768 + 背压阈值 31744<br>② 加 `rx_seen` 被动化门 + 100ms 延迟<br>③ `image_feeder` + `udp_loopback` 取代 `tx_frame_sender`<br>④ LED 换成诊断信号、修极性<br>⑤ 保留 `USE_LOOPBACK` / `USE_NO_APP` 两个调试开关 | 核心修改 |
| `net/image_feeder.v` | **新增**：读 img_fifo，拆 20 包（1400/1048），喂 loopback | 新增 |
| `net/tx_frame_sender.v` | 手写 app-TX 发送器，**已不再例化**（留着但不用） | 废弃 |
| `net/pixel_to_bytes.v` | 24bit 拆 R/G/B（第 3 步已加，未再改） | 不变 |
| `net/rgmii_interface.v` | TXC 复位时序修复**已回退**（那是个红鲱鱼，跟 ping 无关） | 回退 |
| `design_top_wrapper.v` | 视频取数 4 根线 + `led = net_led` 直连 | 核心修改 |
| `td_project/camera_to_dsi_display.al` | 登记 `image_feeder.v`（CompileOrder 108） | 需 GUI 确认 |

---

## 5. 当前参数 / 开关（接手时先确认）

| 项 | 值 |
|---|---|
| `USE_LOOPBACK` | `1'b0`（正常设计；`1'b1` = 纯回环诊断） |
| `USE_NO_APP` | `1'b0`（正常发图；`1'b1` = 发送器完全不动，诊断用） |
| 包格式 | 20 包/帧：前 19 包 1402 字节，末包 1050 字节（2 序号 + 1400/1048 图像） |
| img_fifo | 深 32768（`ADDR_WIDTH=15`），背压 `FIFO_HIGH=31744` |
| `rx_seen` 门 | 收到帧后延迟 100ms 才允许 feeder 喂 |
| 身份 | IP `192.168.240.1` / 端口 1 / MAC `02:00:00:00:24:01` / 发往 `.2:6666` |

---

## 6. 测试验证（照着做）

```cmd
:: PC 网卡 192.168.240.2 / 255.255.255.0，网关空
:: 先 ping（这步同时也是在给板子喂 PC 的 MAC）
netsh interface ipv4 delete neighbors "以太网" 192.168.240.1
ping 192.168.240.1
arp -a
```

- **ping 4/4 通** + `arp -a` 里出现 `02-00-00-00-24-01` = 网口 OK
- Wireshark 过滤 `udp.port == 6666`：应看到周期性 20 个包/帧（19×1402 + 1×1050）

### 收图（需装 Python）

```powershell
cd D:\TD_project\lab_ex1_mipi_hdmi_SC500_720P+vpp
python tools\boardA_recv_frame.py --count 5 --scale 8
```

---

## 7. 千万别踩的坑（血泪总结）

1. **别手写 app-TX**。官方只验证过 `udp_loopback` 那套握手。要主动发，就照官方
   `udp_transmit_test.v`：把数据喂进 `udp_loopback.app_rx_*`。
2. **协议栈不能主动发**（空 ARP 缓存会死锁）。板子必须"先收到帧再发"。
3. **`temac_rx_valid` 是低有效的**（= `rx_client_fifo` 的 `rd_src_rdy_n`，0=有帧）。
   判断"收到帧"要用 `~temac_rx_valid`，写反了门控会在空闲时误开、照样死锁。
4. **改 Verilog 别用 PowerShell 的 `Set-Content` / `Out-File`**（会加 BOM、毁中文注释），
   用能保证 UTF-8 无 BOM 的工具。
5. **`.al` 会手改被 TD 覆盖**，新源文件必须在 TD 图形界面登记（`image_feeder.v` 已在里）。
6. **`udp_loopback` 例化要传 `.DEVICE(DEVICE)`**（默认 "PH1"，不传就展开成黑盒原语）。

---

## 8. 遗留问题（未解决，队友接手）

### 双板离开电脑怎么冷启动（这是唯一没解决的）

因为"协议栈不能主动发"，纯双板冷启动时两边都等对方先开口 → 死结。

方案（需验证）：**广播引导**——板 B 周期性发广播 UDP "hello"（广播 MAC 是
`ff:ff:ff:ff:ff:ff`，不需要 ARP，不会死锁），板 A 收到后学到板 B 的 MAC，再单播
发图。有两个待验证点：
1. 协议栈往 `255.255.255.255` 发，是不是真的不走 ARP？
2. 板 A 收到广播 UDP 后，会不会从源 MAC 学到板 B 的 MAC？

下策：每次上电由 PC ping 两块板一次（演示够用，不算纯双板）。

### 图像内容未做逐像素比对

UDP 在流、包结构对了，但"拼出来的图是否和 HDMI 一致"还没跑 `boardA_recv_frame.py`
验证（本机没装 Python）。

---

## 9. 相关文档

| 文档 | 内容 |
|---|---|
| `docs/板A以太网_第3步调试复盘与后续计划.md` | 完整的调试复盘 + 方法教训 + 今晚计划 |
| `docs/板A以太网_第3步ping不通_根因分析与修复方案.md` | 根因分析（早期版，部分结论已被本总结修正） |
| `docs/板A以太网改造_第2步实施记录.md` | 第 2 步（基线） |
| `docs/板A以太网改造_第3步实施记录.md` | 第 3 步（原始改动） |
