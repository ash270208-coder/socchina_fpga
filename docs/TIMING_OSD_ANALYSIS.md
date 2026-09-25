# OSD 时序违例根因分析

> 板 A（图像处理版）复综合日期：2026-09-25，TD 6.2.1 / PH1P35MDG324 speed 3
> 报告位置：`td_project/camera_to_dsi_display_Runs/syn_1/camera_to_dsi_display_gate.{timing,ts,qor,area}`

---

## 1. 现象

| 时钟域 | 频率 | SWNS | 结论 |
|---|---|---|---|
| **HDMI_PIXEL_CLK** | 75.002 MHz (13.333 ns) | **−4.080 ns** | ❌ 24 个违例端点（全部在此域） |
| MIPI_RX_BYTE_CLK | 59.995 MHz (16.668 ns) | +7.649 ns | ✅ |
| ddr usr_clk | 66.667 MHz (15 ns) | +4.918 ns | ✅ |
| sys_clk_50m | 50 MHz | +16.605 ns | ✅ |
| pll_clk_24m | 23.81 MHz | +28.587 ns | ✅ |
| HDMI_SERIAL_CLK | 375 MHz | +0.860 ns | ✅ |

STNS = −84.170 ns；此域最大逻辑级数 18。

## 2. 证据：最差路径逐级展开

```
Begin Point : u_osd_overlay/x_r1_reg[3].clk      (HDMI_PIXEL_CLK)
End Point   : u_osd_overlay/O_tdata_reg[16].d    (HDMI_PIXEL_CLK)
Budget      : 13.333 ns
Data Path   : 17.349 ns  =  cell 5.367 ns (30%)  +  net 11.982 ns (70%)
Logic Level : 18         ( LUT6×8, LUT2×4, LUT5×2, LUT4×2, LUT3×2 )
Max Fanout  : 619
```

关键几级（完整逐级见 `camera_to_dsi_display_gate.timing` 第 102 行起）：

| 级 | 单元 | 位置/说明 | 该级累计 |
|---|---|---|---|
| — | SEQ | `x_r1_reg[3]` 出发 | 0.076 |
| 1 | LUT6 | 扇出 **88** 的 `x_r1[3]` 网络（1.017 ns） | 1.408 |
| 3 | LUT5 | `osd_overlay.v(430)` 区域判定 mux | 3.032 |
| 5 | LUT2 | 扇出 **619** 的网络（1.281 ns） | 5.699 |
| 7 | LUT4 | 进入 `u_anlogic_logo_rom/I_addr[6]`（`anlogic_logo_rom.v(2)`） | 7.475 |
| 8–14 | LUT6×4,LUT5,LUT3 | logo ROM 组合解码 / 文字与汉字判定 | 13.0 |
| 15 | LUT2 | 扇出 25（0.835 ns） | 14.101 |
| 17 | LUT6 | `O_tdata_b[16]` 末级 | 16.139 |
| 18 | LUT4 | 送 `O_tdata_reg[16].d` | 17.308 |

## 3. 根因

### (1) OSD 判定被整个塞进一个时钟周期
`osd_overlay.v` 的 `always @(*)`（第 406–512 行）在一个周期内完成：

```
(x_r1,y_r1) → 区域比较(logo/文字/汉字 三级优先)
            → 文字区：10 级边界比较链求 txt_glyph（第 450–459 行）
            → 减起始偏移求 txt_lx → F_dn43() 行列 4/3 映射
            → F_mode_glyph() + osd_char_lib 字库查表（32 bit 行向量）
            → char_row_bits[31 - src_col]  ← 32:1 变址位选
            → 汉字区：F_cn_scale() + F_cn16_row 点阵查表 + 16:1 位选
            → osd_hit / osd_color → O_tdata 输出 mux
```

面积证据：`u_osd_overlay` = **2 380 个 cell，只有 24 个寄存器**（`camera_to_dsi_display_gate.area`）—— 几乎是纯组合云，没有流水。

模块里注释写的"一级流水"（`x_r1/y_r1`，第 107–137 行）**只把坐标与像素数据对齐**，并没有把判定逻辑切开，所以它不提供任何时序余量。

### (2) `anlogic_logo_rom.v` 是一张 6 387 条目的稀疏组合查找表
- 源码 **298 KB**，`case(I_addr)` 里 6 387 条 `15'dNNNN: O_pixel = 25'h...`
- 地址稀疏（15 bit 空间里只有 6 千多个有效点）、像素值大量重复
- TD 无法把它推断成 ERAM（全设计 ERAM 仅 34 块，其中没有这块的位置），只能在 LUT 里搭解码树 → 直接落在关键路径上（第 7 级起）
- 地址 `logo_addr` 也是纯组合算出来的（`(logo_ly<<7)+(logo_ly<<5)+logo_lx`），没有寄存

### (3) 互连占 70%：组合云把时钟域铺得太散
`x_r1` 扇出 88、路径中段出现扇出 619 的网络；单元延迟只占 30%。这类"大而散"的组合逻辑对布线极其敏感，是典型的**单周期大组合块**特征，靠 P&R 很难完全救回来。

## 4. 与 Step A（移除人脸检测）的关系 —— 无关，且不是回归

- 24 个违例端点**全部在 `u_osd_overlay` 内部**，Step A 只改了 `vpp_top.v` / `design_top_wrapper.v` 的例化与端口，没动 OSD 一个字符
- 被移除的 LBP 链虽然在同一个像素时钟域，但删除只会**减轻**该域负载，不可能凭空造出这条路径
- 尝试用历史报告对比时发现：工程里唯一一份布线后报告
  `td_project/design_top_wrapper_route.timingsummary`（2025-12-26，SWNS +0.034 ns）
  里 **`osd_overlay` / `anlogic_logo_rom` / `osd_char_lib` / `face_track` / `lbp_detector` 命中次数全为 0**
  → 它是更早、更简单的设计的报告，**不能作为"OSD 以前能过时序"的证据**

**结论：OSD 这条路径（含 logo ROM）从未经过布线验证，是后加 OSD 时引入的隐患，属于存量问题。**

## 5. 修复方案（按性价比排序）

### 方案 A（推荐）：把 OSD 判定切成两级流水
- **第一级**（`x_r1/y_r1` 之后）：区域命中判断、`logo_lx/ly`、`txt_glyph`、`txt_lx`、`src_col/src_row`、`cn_col/cn_row` 等索引计算 → 打一拍
- **第二级**：字库 / 汉字点阵 / logo 查表 + 位选 + 颜色 mux → 输出寄存
- 同时把 `valid/last/user/data` 再延迟一拍（模块已有对齐延迟机制，改动约 30 行）
- 预期：18 级 → 约 9 + 9 级，路径基本减半，中间扇出被寄存器隔断
- **行为完全等价**，只是延迟 +1 拍（OSD 叠加位置不变）

### 方案 B（建议与 A 一起做）：logo 表改用官方 ROM IP
- `anlogic_logo_rom` 的 6 387 条组合 `case` → TD ROM IP + `.dath` 初始化（同步读天然 1 拍，与方案 A 相容）
- 顺带省掉 OSD 里最大的一块 LUT
- 代价：160×160×25 bit ≈ 640 Kbit ≈ **32 块 ERAM20K**（板 A 34 → 约 66 / 108，可接受）
- 更省的备选：logo 改 128×128，或改成 8 bit 索引色 + 调色板

### 方案 C（辅助优化）
- `txt_glyph` 的 10 级边界比较链 → 一张 9 bit→4 bit 的小 LUT
- `char_row_bits[31 - src_col]` 的 32:1 变址位选 → 分段 mux / 先按行寄存

## 6. 最终结果与结论（2026-09-25 布线完成）

| 阶段 | SWNS | 违例端点 |
|---|---|---|
| 综合（rtl / gate） | −4 080 ps | 24 |
| 全局布局 + 物理优化 | −246 ps | 18 |
| 详细布局迭代 | +246 → +1 110 ps | 0 |
| **布线 + hold 修复（最终）** | **+105 ps** | **0** ✅ |
| Hold（最终） | +20 ps | 0 ✅ |

最终资源（`phy_1/route.qor`、`phy_1/camera_to_dsi_display_phy.area`）：

| 资源 | 用量 | 上限 | 占比 |
|---|---|---|---|
| slice | 15 956 | 21 216 | **75.21%** |
| LUT6 | 14 510 | 21 216 | 68.39% |
| 寄存器 | 12 136 | 42 432 | 28.60% |
| ERAM20K | 34 | 108 | 31.48% |
| DSP | 28 | 40 | 70.00% |
| gclk / sclk | 9 / 20 | 32 / 48 | 28% / 42% |

码流：`phy_1/camera_to_dsi_display.bit`（1 789 539 B）+ `..._compress.bit`（1 330 097 B）。
⚠️ `_Runs/best_result/` 里那份 bit 是 2026-09-22 的旧码流，**不要下错**。

**结论：布线已经把这条路径收住了（WNS +105 ps、0 违例），因此"暂不改 OSD"是可行的。**

但要清楚 +105 ps 只占 13.333 ns 周期的 **0.8%**，属于"能过但很薄"。板 A 后续还要继续加图像
处理功能，只要再往像素时钟域塞逻辑，就可能再次压垮它。**建议在给板 A 加新功能之前，先按方案 A
做一次流水加固**（改动约 30 行、行为逐像素等价，一次性把余量做厚）；这样后面加功能才有空间。

## 7. 复现与验证方法

```powershell
# 综合（在 syn_1 目录下）
E:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe `
  E:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/arch/../doc/scripts/DefaultFlow.tcl

# 看结果：Setup WNS
#   camera_to_dsi_display_gate.qor      -> QoR metrics / Setup WNS
#   camera_to_dsi_display_gate.timing   -> 逐级路径
#   camera_to_dsi_display_gate.ts       -> 汇总
```

功能回归：流水改造后 OSD 文字 / logo / "安路" 汉字应与改造前**逐像素一致**（延迟不变的是画面内容，只是晚 1 拍），可用上板对比或仿真抓帧比对。
