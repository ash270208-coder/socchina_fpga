# FPGA_CNN实现方案（PH1P35MDG324 · 方案 A int8 检测器）

> 本文是 Verilog 施工总图：**现状盘点 → 契约速查 → 架构 → 官方 IP 清单 → 资源账 → 施工顺序 → 待确认事项**。
> 权威数字出处：`matlab/cnn_detector/FPGA部署契约.md`、`out/params_summary.txt`、`step3/step4` 脚本（以脚本为准，个别与旧契约文档冲突处以本文"§3 定点细节修正"为准）。
> 本文只覆盖 FPGA 端；训练/量化已完工（v1_80ep，浮点↔定点 IoU 0.971）。

---

## 1. 现状盘点（已核对到文件级）

### 1.1 PC 端（MATLAB）——全部完工 ✅

| 产物 | 位置 | 状态 |
|---|---|---|
| int8 权重 `.mem`（5 层） | `matlab/cnn_detector/out/w_conv1..4.mem, w_head.mem` | ✅ 已导出 |
| int32 折叠偏置 `.mem` | `out/b_conv1..4.mem, b_head.mem` | ✅ |
| exp 查表 | `out/lut_exp.mem`（1024×Q11） | ✅ |
| 逐层金标准 | `out/golden/x0_input, x1_conv1, x2_conv2, x3_conv3, x4_conv4, head_real, boxes.txt` | ✅ 已导出（.txt 带尺寸表头） |
| 仿真对照数据 | `sim/cnn_data/*.hex`（无表头，`$readmemh` 直接吃）+ conv1 打包权重 | ✅ 前一会话已备好 |
| TD 官方 ROM 初始化文件 | `user_source/hdl_source/cnn/mem_dath/*.dath` | ✅ 格式与 .mem 一致（每行一个 hex 值） |
| 训练快照/复现记录 | `snapshots/v1_80ep/`、`训练记录.md` | ✅ |

### 1.2 FPGA 端——测试台已就位，RTL 待写 ⏳

| 素材 | 位置 | 说明 |
|---|---|---|
| `conv1_pixel_tb.v` | `sim/` | 单像素对拍：**定义了 `conv1_pixel.v` 的接口**（W_MEM/B_MEM 参数、start/cout_idx/x_patch/y_out/done） |
| `conv1_frame_tb.v` | `sim/` | 整层对拍：**定义了 `conv1_frame.v` 的接口**（帧缓存写口 + start + 8 通道 ×9bit 输出） |
| `conv1_frame_dbg_tb.v` | `sim/` | 临时调试台（观察内部信号名：state/bk/i/acc/frame_dout/w_word/inb_q/yq） |
| ModelSim | `E:\Modelsim\win64`（vsim/vlog/vlib 在 PATH） | ✅ 可用 |
| TD 工程 | `td_project/camera_to_dsi_display.al`（PH1P35MDG324，TD 6.2） | ✅ `.mem` 已拷入工程根目录 |
| LBP 链（将被替换） | `face_track_top.v` 内：downscaler(÷6) + lp_filter + integral_image + lbp_detector_engine | 接口保留，内部整体换 CNN |

**结论：缺的只有 RTL 本身。** 且接口已经被三个 tb 钉死，照着写即可。

---

## 2. 网络契约速查（Verilog 照此实现）

输入 **128×72×3 RGB，uint8 0..255**；输出 18×32 网格 × 3 锚 × [to tx ty tw th]。

| 层 | K/stride/pad | Cin→Cout | 输出 | 整数乘累加公式 |
|---|---|---|---|---|
| conv1 | 3/1/1 | 3→8 | 128×72×8 | `acc = Σ(Wq·xq) + b_int` |
| conv2 | 3/2/1 | 8→16 | 64×36×16 | `xq_next = clamp(round(acc·mOut), 0, 255)` |
| conv3 | 3/2/1 | 16→32 | 32×18×32 | （BN 已折叠进 W/b，硬件无 BN） |
| conv4 | 3/1/1 | 32→32 | 32×18×32 | |
| head | 1/1/0 | 32→15 | 32×18×15 | `head_q12 = round(acc·mOut·4096)` |

- 锚框（全精度，params_summary.txt）：`[12.77542 8.48097] / [16.57357 16.08400] / [37.10174 29.88861]`
- 解码：`score = clamp(to,0,1)`（不套 sigmoid）；`tx/ty = clamp(·,0,1)`；`w = anchorW·exp(tw)`；
  `cx = (gx+tx)·4`；后处理 `score ≥ 0.15` → 全局最高分 1 框。
- 权重 `.mem` 顺序：**列主序 [ky kx cin cout]**；偏置 `[cout]`。

## 3. 定点细节修正（⚠️ 比旧契约文档更重要，必须照抄）

### 3.1 mOut 用 Q32 常数，不要用 Q16（旧契约文档的 Q16 会错）

旧 `FPGA部署契约.md` 建议 `xq_next = (acc × mOut_q16) >>> 16`（conv1=238…）。**这是错的**：
金标准 `step4` 用双精度 `round(acc·mOut)`，而 `238/65536 = 0.0036316 ≠ mOut = 0.00362591`，
相对误差 1.6‰，conv1 的 acc 最大 ~9×10⁵ → 激活误差达 **±5 LSB**，ModelSim 对拍会大面积 FAIL。

`step3_quantize_export.m` 的第 6b 节（比契约文档新）才是正解：

```verilog
// 由 step3 导出的 cnn_params.vh（尚未生成，见 §7 待确认事项-1）
// real = (acc * `MOUT_Q32_CONV1 + 32'sd2147483648) >>> 32     // 正数时 +2^31
// real = (acc * `MOUT_Q32_CONV1 - 32'sd2147483648) >>> 32     // 负数时 −2^31（对齐 MATLAB round 半舍入远离零）
```

- 硬件实现：`sign = acc[最高位]`，`v = acc × Q32 ± 2^31`，`>>> 32`。Q32 常数全部 < 2^31，28~32 bit 有符号乘
  （8×8 MAC 之外的**量化乘法**用 LUT 常数乘法实现即可，量级每像素每通道一次，不进 DSP 预算）。
- 半界概率 ~2⁻³²，正负分支只在"恰好 0.5"处与 MATLAB 有差，概率可忽略；其余逐位一致。

### 3.2 检测头 Q12

```verilog
head_q12 = (acc × (`MOUT_Q32_HEAD_CONV << 12) ± 2^31) >>> 32   // = round(acc·mOut·4096)
```
`MOUT_Q32_HEAD_CONV ≈ 381,704`（= round(mOut_head·2³²)，×4096 后 1.56e9 < 2³¹ 不溢出）。
金标准 `head_real.txt/hex` 就是 Q12 整数（hex 版为 16-bit 补码），逐位对拍。

### 3.3 exp LUT（tw/th 解码）

```
h = head_q12（Q12 实域值）
idx = clamp(((h + 16384 + 16) >>> 5), 0, 1023)      // = round((h/4096 + 4)·128)，h∈[-4,4) 内
exp = rom_lut_exp[idx]                              // Q11，值 = exp_real×2048
```
LUT 内容 = `lut_exp.mem` 第 idx+1 行（MATLAB 1-based）。

### 3.4 锚框与解码定点（推荐 Q12 锚，比契约文档 Q4 更贴金标准）

```
tx_q12, ty_q12      : clamp 到 [0, 4096]
to_q12              : 分数阈值 0.15 → Q12 阈值 = 614
w_q23 = anchorW_q12 × exp_q11 ;   w_q12 = w_q23 >>> 11     // anchorW_q12 = round(anchorW×4096)
cx_q12 = gx×16384 + (tx_q12 << 2) ;  cy_q12 = gy×16384 + (ty_q12 << 2)
x1_q12 = cx_q12 - (w_q12 >>> 1) ;   y1_q12 = cy_q12 - (h_q12 >>> 1)
最终整数框（128×72 空间）: x1 = (x1_q12 + 2048) >>> 12，clamp [0,128]/[0,72]
```
> 契约文档的 Q4 锚（204/136、265/257、594/478）也可用，但会让框与 golden `boxes.txt`
> 差 ~0.5 px；Q12 锚（52328/34738、67885/65880、151968/122424）与浮点锚误差 <1e-4。
> 全网格共 **1728 候选**：扫描记最高分（≥614）唯一框。

---

## 4. 总体架构

```
        ┌────────────────────────── face_track_top（接口不变）───────────────────────────┐
I_disp ─┤  RGB888 显示流（画框前抽取！后文 §4.4）                                        │
 I_y    ─┤  Y 流（CNN 不用，留兼容）                                                     │
        │                                                                                │
        │  ┌─────────────┐   ┌────────────┐   ┌──────────────────┐   ┌──────────────┐  │
RGB888→ │  │ cnn_ds10    │──▶│ cnn_frame_ │──▶│ cnn_conv_engine  │──▶│ cnn_head_dec │  │
(÷10 块 │  │ 3通道 10×10 │   │ buf (ERAM) │   │ 通用 5 层卷积引擎 │   │ 锚解码+expLUT │  │
 平均)  │  │ 128×72×3    │   │ 11 块 单缓冲│   │ 2×8 切片 MAC 阵列│   │ +最高分1框   │  │
        │  └─────────────┘   └────────────┘   └──────────────────┘   └──────────────┘  │
        │                                        bufA(29块)x1→x3→head   bufB(15块)x2→x4  │
        │                                                          │                    │
        │  框(128×72 空间) ─▶ 坐标 ×10 换算 ─▶ osd_box_drawer(SCALE_FACTOR=10) ─▶ O_disp│
        │                                   └─▶ O_face_x/y/valid（云台 PID）              │
        └─────────────────────────────────────────────────────────────────────────────────┘
```

### 4.1 模块清单（新增/修改）

| 模块 | 类型 | 功能 | 验收 |
|---|---|---|---|
| `cnn_ds10.v` | 新 | ÷10 三通道 10×10 块平均（抗混叠），输出 128×72×3 行主序 + tuser/tlast | 单模块 tb |
| `cnn_frame_buf.v` | 新（RAM IP 包装） | 输入帧缓存 9216×24bit（RGB888），单缓冲，双口（写=流，读=引擎） | 随 conv1_frame tb |
| `cnn_conv_engine.v` | 新（核心） | 参数化 Cin/Cout/K/stride/pad + Q32 量化 + clamp；内部含 conv1_pixel/conv1_frame 的实例化关系 | 逐层对拍（§6） |
| `cnn_rom.v` | 新（ROM IP 包装） | 权重/偏置/expLUT 三合一封装：`ifdef TD_SYN → TD ROM IP 实例；else → $readmemh 行为模型` | 随各 tb |
| `cnn_head_dec.v` | 新 | §3.3/3.4 解码 + 1728 候选最高分单框（Q12 全整数） | 对拍 boxes.txt |
| `cnn_top.v` | 新 | 上述整合：帧调度 FSM（§4.3） | 整链 tb |
| `face_track_top.v` | 改 | 内部 LBP 链整体换成 cnn_top；接口/端口不变 | vpp_top 回归 |
| `osd_box_drawer.v` | 改参数 | SCALE_FACTOR 6→10（参数化已支持，只改例化） | 上板 |
| `downscaler.v` | 保留 | LBP 用；cnn_ds10 是新模块 | — |

### 4.2 卷积引擎内部结构（核心决策）

**帧缓存式、输出通道并行的 2×8 切片阵列（16 DSP）**：

- 特征图按"**一个像素的全通道打包成宽字**"存 ERAM：x1=64bit/字（8ch×8b）、x2=128bit/字（16ch×8b）、
  x3/x4=256bit/字（32ch×8b）。**一周期读一个字 = 拿到该位置的全部输入通道**。
- 每周期：2 个权重 ROM 各读 1 个 64bit 打包字（每字 = 8 个输出通道的 int8），
  与寄存器里锁存的输入字做 16 个 MAC（2 切片 × 8 DSP）。
- 层间循环：
  - conv1：27 拍/像素（3ch×3×3，每拍 1 输入通道 ×8 输出通道并行；8 DSP 忙 8 闲，可选 2 像素并行提速一半）
  - conv2：72 拍/像素（9 位置 × 8 入通道，2 切片各 8 出通道并行）
  - conv3/conv4：288/576 拍/像素（32 出通道 = 2 遍 × 2 切片；输入字锁存复用，每位置 1 次 ERAM 读）
  - head：30 拍/像素（1×1，15 通道 1 遍）
- 每拍 16 MAC → **100% MAC 利用率（conv1 除外）**；读取带宽：1 输入字读 + 2 权重字读 + 1 输出字写/像素，
  ERAM/ROM 端口完全够。
- 累加器 32bit 有符号（DSP 48bit 级联余量充足）；量化乘法（acc×Q32）用 LUT 常数乘法，每像素每通道一次，
  与下一像素的 tap 循环重叠，不进关键路径。

### 4.3 帧调度时间线（74.25 MHz，单缓冲输入帧）

```
t=0         帧 N 有效区：cnn_ds10 流式写 bufIN（27,648 拍 ≈ 0.37 ms）
t=16.7ms    帧 N 结束 → 引擎启动（conv1 读 bufIN 须等帧 N+1 的 ds10 写完成，
            实际以帧 N+1 的 SOF 为同步点启动即可，天然满足）
             conv1 249K 拍(3.3ms) → conv2 166K → conv3 166K → conv4 332K → head 17K
t≈29.2ms   全部算完（启动后 ~12.5 ms），框送 OSD，帧 N+1 期间画框
            下一帧同理 —— 检测结果滞后 1 帧，osd_box_drawer 的 HOLD_FRAMES=15 抹平，肉眼无感
```

- 计算合计 ≈ **930K 拍 ≈ 12.5 ms**（16 DSP 版）；×1.2 工程余量 ≈ 15 ms < 16.7 ms → **60fps 可行**。
- 15 DSP（8+7 非对称）或 8 DSP 版 ≈ 1.9M 拍 ≈ 26 ms → 38fps；兜底手段：引擎提频（PLL 有 148.5MHz 可用）、
  或检测跑 30fps（OSD 保持掩丑）。**首版按 16 DSP 设计，DSP 数不够再降档**（见 §7-2）。

### 4.4 输入源与画框自反馈（重要坑）

- CNN 的 RGB 输入从 **`I_disp_tdata`（即 vpp 的 mux 输出、画框之前）** 抽取：它是伽马后的显示域 RGB，
  与训练数据（sRGB 照片）分布一致；且**位于 osd_box_drawer 之前** → CNN 永远不会看到自己画的绿框，
  杜绝"框锁死绿框"的正反馈。
- 现有 `I_ycbcr_*` 端口保留但 CNN 不使用（Y 只有单通道，网络要 RGB）。

---

## 5. 官方 IP 使用清单（用户核心诉求）

| 用途 | 官方 IP | 规格 | 初始化/来源 | 备注 |
|---|---|---|---|---|
| 5 层权重 ROM ×5 | TD IP Generator **ROM** | 64bit×27 / 64×144 / 64×576 / 64×1152 / 64×64 字 | `cnn_w_*_packed.dath`（8 通道/字打包，需按 step3 6b 格式重新生成，见 §7-1） | 与 `rom_weak_lut` 同款流程（al_ip/ 下生成 .xml，工程注册） |
| 偏置 ROM ×5 | TD **ROM** | 64bit×4/8/16/16/8 字（2×int32 打包） | `cnn_b_*.dath` | 亦可用 LUT 分布式（量小） |
| exp LUT ROM ×1 | TD **ROM** | 16bit×1024 | `cnn_lut_exp.dath`（已备 ✅） | |
| 输入帧缓存 bufIN | TD **RAM**（ram_2port 型） | 9216×24bit，双口 | — | 11 块 ERAM，单缓冲 |
| 特征图 bufA | TD **RAM** | 9216×64bit（x1）→ 复用 576×256（x3）→ 576×240（head） | — | 29 块 ERAM，三种几何分时复用 |
| 特征图 bufB | TD **RAM** | 2304×128bit（x2）→ 复用 576×256（x4） | — | 15 块 ERAM |
| MAC（16 个） | **不例化 IP**，写 `*` 由 TD 综合映射 DSP 单元（项目现有风格） | 8bit 有符号 ×8bit 无符号，48bit 累加 | — | 若想锁级数可换 TD MULT IP |
| 量化乘法 | LUT 常数乘法（CSD） | 32×25 | — | 不进 DSP 预算 |
| FIFO | **仅当**需要跨时钟/流缓冲时才用（现有 w40_d512_fifo 等范例） | — | 首版不需要 |

**仿真与综合双轨**：`cnn_rom.v` 内 `ifdef TD_SYN` 选 TD ROM IP 实例，否则 `$readmemh`
行为模型（路径由 W_MEM/B_MEM 参数传入）——沿用团队"安路 IP 仿真失败就改行为级"的既有经验，
同时保留官方 IP 在综合路径上（用户要求）。

**ERAM 总账**：bufA 29 + bufB 15 + bufIN 11 + 权重 ROM 7 + exp LUT 1 + 偏置 ~1 ≈ **64 ≤ 74** ✅
（比旧契约 67 还宽裕，因为输入帧改单缓冲；若想双缓冲 RGB888 也放得下：+11 = 75，差 1 块，
把偏置挪 LUT 即可）。

---

## 6. 分层施工顺序（每步都有 ModelSim 验收，绝不跨步）

| 步 | 内容 | 验收（现有素材） | 状态 |
|---|---|---|---|
| 0 | MATLAB 导出 Q32 常数 + 打包权重（`matlab/cnn_detector/export_fpga_consts.m`，只读 net_params.mat） | `cnn_params.vh` + `w_*_packed.mem/.dath` 生成 | ✅ 已完工（Q32 常数见 §8） |
| 1 | `conv1_pixel.v`（27 tap × 1 输出通道，Q32 量化） | **conv1_pixel_tb PASS**（5 像素 ×8 通道 + bias 自检） | ✅ **PASS**（41/41 逐位一致） |
| 2 | `conv1_frame.v`（帧缓存 + 3×3 滑窗 + 8 通道并行 + m_valid/m_data 接口） | **conv1_frame_tb PASS**（9216 像素 ×8 通道逐位） | ✅ **PASS**（73,728/73,728 逐位一致） |
| 3 | 参数化引擎 `conv_frame.v`：stride/pad/Cin/Cout 泛化 + 打包宽字读 → conv2、conv3、conv4 | conv2/3/4_frame_tb 逐层对拍 | ✅ **PASS**（36,864 / 18,432 / 18,432 逐位一致，一次通过） |
| 4 | `head_frame.v`（1×1, 32→15, Q12 输出）+ `cnn_head_dec.v`（exp LUT + Q12 锚框 + 1728 选 1） | head_real.hex 逐位 + 最终框 vs `boxes.txt`（±1 px） | ✅ **PASS**（8,640/8,640 逐位一致；框 [71 0 30 30] vs 金标准 [70.90 0 30.34 29.68] ✓） |
| 5 | `cnn_ds10.v`（÷10 三通道块平均）+ `cnn_top.v`（五层帧调度 + 16 DSP 双切片引擎 + 解码整合） | 整链 tb：x0 流输入 → 框 vs `boxes.txt` | ✅ **PASS**（整链框 [71 0 30 30]、score 3109、**964K 拍 ≈ 13 ms → 60fps 可行**；ds10 功能 tb 8/8） |
| 6 | `face_track_top.v` 换芯（删 LBP 链，接 ds10+cnn_top）+ osd 参数化缩放修复 + 整链集成验证 | **face_track_cnn_tb PASS**：4 帧 720p 合成流 → 透传 ✓ / 形心 (860,150) ✓ / 帧3 绿框 [710,0]-[1010,300] ✓ | ✅ **RTL+仿真已完工**；TD 综合+上板 = §9 执行清单（GUI 操作） |

> 纪律（沿用 `CNN学习与准备路线.md`）：每层独立仿真、逐位对照，**任何一步 FAIL 先修再走**；
> 金标准是唯一的裁判（x0→x1→x2→x3→x4→head→boxes 全部已有）。

---

## 7. 待确认事项（开工前需要拍板）

1. ~~【需要你操作】重跑 MATLAB~~ ✅ **已自动完成**：新增 `matlab/cnn_detector/export_fpga_consts.m`（只读
   `out/net_params.mat`，不依赖训练图片），已用 `matlab -batch` 跑通，Q32 常数/打包权重已全部导出并部署到
   `hdl_source/cnn/` 与 `sim/cnn_data/`。以后换权重重训后重跑这一个脚本即可。
2. **DSP 阵列宽度**：16 DSP（2×8 切片）→ 12.5 ms/帧（60fps 稳）；8 DSP → 26 ms（38fps，可提频救）。
   旧文档说 LBP 撤后只有 15 个 DSP 可用——**TD 综合资源报告里实际可用 DSP 数需复核**；
   若真卡 15，首版走 8 宽 + 引擎提频，或用"conv1 双像素并行"把 conv1 用满 16 个槽位。
3. **引擎时钟**：默认 74.25 MHz 像素钟（省跨时钟域）；不够时再用 PLL 提频 148.5 MHz。
4. **输入帧缓冲**：默认单缓冲 + 1 帧滞后（省 11 块 ERAM）；要零滞后则双缓冲（+11 块，仍在预算内）。
5. **训练精度**：训练集 IoU 中位 0.37、彩绘脸未覆盖——上板前建议补彩绘脸数据重训一版
   （`训练记录.md` 已给出配方）；FPGA 侧不受影响，权重文件替换即可。

---

## 8. 施工日志（已核实的关键常数与踩坑记录）

### 8.1 全精度 Q32 常数（`cnn_params.vh`，勿手改）

```verilog
`define MOUT_Q32_CONV1     32'd15573148   // mOut = 3.6259060726e-3
`define MOUT_Q32_CONV2     32'd56261780   // mOut = 1.3099466451e-2
`define MOUT_Q32_CONV3     32'd25934300   // mOut = 6.0382997617e-3
`define MOUT_Q32_CONV4     32'd17997652   // mOut = 4.1904048994e-3
`define MOUT_Q32_HEAD_CONV 32'd381701     // mOut = 8.8871594926e-5
`define MOUT_Q32_HEAD_Q12  32'd1563445632 // = HEAD_CONV x 4096（检测头 Q12 输出）
`define ANCHOR1_W_Q12 18'd52328   `define ANCHOR1_H_Q12 18'd34738
`define ANCHOR2_W_Q12 18'd67885   `define ANCHOR2_H_Q12 18'd65880
`define ANCHOR3_W_Q12 18'd151969  `define ANCHOR3_H_Q12 18'd122424
```

> 与 6 位有效数字估算值对比：conv1 的 Q32 差 892（估算 15,574,040 vs 真值 15,573,148）——
> 足以让逐位对拍失败，**全精度值不可手抄**。

### 8.2 已通过的仿真（ModelSim SE-64 10.4，仓库根目录执行）

```bat
vlib work_cnn
vlog -work work_cnn lab_ex1_mipi_hdmi_SC500_720P+vpp/lab_ex1_mipi_hdmi+vpp/user_source/hdl_source/cnn/conv1_pixel.v sim/conv1_pixel_tb.v
vsim -c work_cnn.conv1_pixel_tb -do "run -all; quit -f"     :: PASS 41/41
vlog -work work_cnn lab_ex1_mipi_hdmi_SC500_720P+vpp/lab_ex1_mipi_hdmi+vpp/user_source/hdl_source/cnn/conv1_frame.v sim/conv1_frame_tb.v
vsim -c work_cnn.conv1_frame_tb -do "run -all; quit -f"     :: PASS 73728/73728
vlog -work work_cnn lab_ex1_mipi_hdmi_SC500_720P+vpp/lab_ex1_mipi_hdmi+vpp/user_source/hdl_source/cnn/conv_frame.v sim/conv2_frame_tb.v sim/conv3_frame_tb.v sim/conv4_frame_tb.v
vsim -c work_cnn.conv2_frame_tb -do "run -all; quit -f"     :: PASS 36864/36864
vsim -c work_cnn.conv3_frame_tb -do "run -all; quit -f"     :: PASS 18432/18432
vsim -c work_cnn.conv4_frame_tb -do "run -all; quit -f"     :: PASS 18432/18432
vlog -work work_cnn lab_ex1_mipi_hdmi_SC500_720P+vpp/lab_ex1_mipi_hdmi+vpp/user_source/hdl_source/cnn/head_frame.v sim/head_frame_tb.v
vsim -c work_cnn.head_frame_tb -do "run -all; quit -f"      :: PASS 8640/8640（Q12 逐位）
vlog -work work_cnn lab_ex1_mipi_hdmi_SC500_720P+vpp/lab_ex1_mipi_hdmi+vpp/user_source/hdl_source/cnn/cnn_head_dec.v sim/head_dec_tb.v
vsim -c work_cnn.head_dec_tb -do "run -all; quit -f"        :: PASS 框 [71 0 30 30]（金标准 int8 框 ±1 px，score Q12=3109）
vlog -work work_cnn lab_ex1_mipi_hdmi_SC500_720P+vpp/lab_ex1_mipi_hdmi+vpp/user_source/hdl_source/cnn/cnn_ds10.v sim/cnn_ds10_tb.v
vsim -c work_cnn.cnn_ds10_tb -do "run -all; quit -f"        :: PASS 8/8 块（常数/斜坡两模式 + x/y/user/last 时序）
vlog -work work_cnn lab_ex1_mipi_hdmi_SC500_720P+vpp/lab_ex1_mipi_hdmi+vpp/user_source/hdl_source/cnn/conv1_frame.v .../conv_frame.v .../head_frame.v .../cnn_head_dec.v .../cnn_top.v sim/cnn_top_tb.v
vsim -c work_cnn.cnn_top_tb -do "run -all; quit -f"         :: PASS 整链框 [71 0 30 30] score 3109，1,632,399 拍
```

> 引擎已升级为 **2×8 切片（16 DSP，每拍 16 MAC）**，conv_frame 一次通过（算法不变，并行化提速）：
> conv2 ≈166K / conv3 ≈83K / conv4 ≈166K 拍，整链 1.63M → **964K 拍 ≈ 13 ms @74.25MHz**。
> conv1 仍为 8 通道（Cout=8，249K 拍），可选"双像素并行"再减半。

### 8.3 已踩坑（写后续层时注意）

| # | 坑 | 根因 | 修法 |
|---|---|---|---|
| 1 | `3'd9` 溢出 | 9 需要 4 bit，`3'd9` 被截断成 1 → `ci = i/1 = i`，读地址错乱、越界读 X | 除常量 9 用 `4'd9`；**凡写除/模常量的位宽都要 ≥ 常量的最小位宽** |
| 2 | 偏置 packed 文件读 X | `$readmemh` 一行 64 hex 不能读进 32-bit 数组（超宽报 "too many digits"），且单 reg 不是合法目标（"Argument 2 must be a memory"） | 读进 1 元素 256-bit memory：`reg [255:0] b_packed [0:0];`，再按 `b_packed[0][32*k +: 32]` 切片 |
| 3 | 量化乘法精度 | 旧契约 Q16（238/65536）相对误差 1.6‰，激活差 ±5 LSB，对拍必挂 | 用 Q32 常数 + 半舍入远离零（`prod±2^31` 后 `>>>32`），误差 ~acc×1.2e-10，全网络预期翻转 <1 次 |
| 4 | MATLAB 打包写出 | `fprintf('%s', char矩阵)` 按列迭代 + `dec2hex(uint64)` 精度风险 → 内容全错 | 逐字 `typecast(v,'uint8')` 取字节 → `sprintf('%02X', b(end:-1:1))`；与旧文件逐字节核对 |
| 5 | MATLAB 沙箱启动崩溃 | 受限令牌下 `matlab -batch` 报 Fatal Startup Error(File system inconsistency)，重定向 prefs/TMP 无效 | 该命令用完整访问权限跑（danger 模式，一次一授权） |
| 6 | 负值量化差 −1（head 层暴露） | `(p − 2³¹) >>> 32` 对负数算的是 floor(x−0.5)，整体偏移 −1；conv 层被 ReLU clamp 掩盖，head 输出负数才暴露 | 负数先取绝对值做半入再取负：`round(x) = −round(\|x\|)`，全部 4 个量化器统一修正 |
| 7 | `14'd16384` 溢出 | 16384 = 2¹⁴ 在 14 位里截断为 0 → `co×16384 = 0`，cx 只剩 tx 项（与坑 1 同类，**常量的位宽必须 > 其最高位**） | 用 `15'd16384`；cx/cy 同时扩到 21 位防 co=31 极限溢出 |
| 8 | 乘法被 LHS 位宽截断 | `wire [23:0] w_q12 = (aw × exp_w) >>> 11;` 的乘积按 LHS 24bit 上下文求值 → 254M mod 2²⁴ 后再移位 | 先赋给 34bit 中间量再移位：`wire [33:0] w_q23 = aw*exp_w; w_q12 = w_q23 >>> 11` |
| 9 | tb 无符号边界比较误报 | `oy1 < 0−1` 中 −1 被当无符号 255 → y1=0 误判 FAIL | 用有符号差值判断：`$signed({1'b0,oy1}) − EXP` |
| 10 | 单累加器做 2D 块平均（ds10 大坑） | 块 (1,0) 的像素在块 (0,0) 完成前就到齐了，单流式累加器必然串块 | 每条纹 OUT_W 个块累加器 + 双 bank 乒乓，条纹末切 bank 排空 128 块（与下一条纹累加并行） |
| 11 | bx 回绕 vs 行尾混淆 | bx==9 每行出现 OUT_W 次；曾误让 by++ 在每次回绕发生、后又误加 tlast 限制漏掉行内回绕 | 回绕恒做 bx=0；**仅 tlast 时 by++**；条纹完成条件 = tlast && by==SCALE−1 |
| 12 | ÷100 常数写错 | 13107/2^17 = 0.1 是 ÷10 的常数，不是 ÷100 | ÷100 用 10486/2^20（÷10 才是 1311/2^17） |
| 13 | tb 错过帧尾排空输出 | 输出排空持续到最后一像素之后，喂流循环结束即停止检查 → 漏收 | tb 在喂流循环后再跑 OUT_W+2 拍采集尾部 |
| 14 | ds10 排空节奏与下游适配器握手 | ds10 每拍 1 块连续排空，cnn_top 采集适配器每块要 3 拍 → 丢块 | ds10 排空节奏放宽到 4 拍/块（720p 时序余量充足） |
| 15 | 整链 tb 帧背靠背无消隐 | 下一帧 tuser 打断 ds10 末条纹排空 → 每帧丢最后一行块 | tb 帧间加 2000 拍消隐（真实视频有场消隐，RTL 无需改） |
| 16 | 合成流数据映射 | 金标准 x0 是列主序，tb 按行主序 `oy*128+ox` 索引 → 乱序输入垃圾框 | 列主序索引 `oy + 72*ox + 9216*ch` |
| 17 | osd 缩放硬编码 ×6 | `osd_box_drawer.v` 的 scaled_* 是 LBP 时代写死的移位 ×6，SCALE_FACTOR 参数未生效 | 改为 `I_face_* * SCALE_FACTOR` 参数化（对旧 LBP ×6 用法向后兼容） |
| 18 | 同步 ROM 地址多寄存一拍 | 引擎地址寄存器 + ROM 内部地址寄存器 = 2 拍延迟，而引擎按 1 拍设计 → 错位 | **addra 直接接组合表达式**（ROM 自带地址寄存器）；先声明信号再例化 ROM（否则隐式 1-bit net） |
| 19 | 偏置双加 | 重构时在冲刷拍加了偏置，而量化处原就有偏置 → 输出 ≈2×偏置 | 偏置只在量化处加一次（各模块自查单一加偏位置） |
| 20 | ROM 例化位置早于信号声明 | Verilog 先声明后用；端口引用未声明信号 → 隐式 net + 重复声明错误 | ROM 例化放声明之后；端口 part-select 需先建 wire |
| 21 | `generate if (ROM_ID==n)` 选模块名 | 用参数条件例化"按层选 ROM 模块"——语法合法且 ModelSim 通过，但**综合器可能在 generate 剪枝前就要求被引用模块存在**，只生成部分 IP 就报模块找不到；可读性也差 | **引擎与 ROM 解耦**：`conv_frame` 只输出 ROM 地址、输入权重数据；每层一个薄包装 `conv2/3/4_frame` **显式例化本层 ROM IP**（无任何条件例化） |

---

## 9. TD 综合与上板执行清单（剩余 GUI 操作，约 30~60 分钟）

### 9.1 工程准备（RTL 侧已全部就绪）
- `face_track_top.v` 已换芯（LBP 链删除，旧版备份在仓库根 `LBP/`、`src/`）；
- `osd_box_drawer.v` 已参数化缩放（SCALE_FACTOR=10）；
- CNN 模块在 `user_source/hdl_source/cnn/`（9 个）：`conv_frame`（引擎核心，不含 ROM）+ 每层薄包装
  `conv2_frame/conv3_frame/conv4_frame`（各自显式例化本层官方 ROM IP）+ `conv1_frame / head_frame /
  cnn_head_dec / cnn_ds10 / cnn_top`；`conv1_pixel.v` 是单像素验证模块，综合不用；
- **仿真数据已拷入 TD 工程相对路径** `td_project/sim/cnn_data/*.mem`（RTL 默认参数路径可直接被 TD 找到）。

### 9.2 TD 工程操作
1. 打开 `td_project/camera_to_dsi_display.al`；
2. **加入源文件**（Project → Add Source）：`hdl_source/cnn/` 下 **10 个模块**（cnn_ram、conv1_frame、conv_frame、
   conv2_frame、conv3_frame、conv4_frame、head_frame、cnn_head_dec、cnn_ds10、cnn_top）。
   **不要加 `cnn_rom_ip.v`、`cnn_buf_ip.v`**（都是仿真替身，加进去会与官方 IP 同名冲突）；
3. **旧 LBP 文件处理**：`downscaler.v / lp_filter_3x3.v / integral_image.v / lbp_detector_engine.v`
   与 `al_ip/rom_weak_lut` 等 LBP ROM 已不被引用，可从编译列表移除（不删也行，综合器自动裁剪）；
4. **官方 ROM IP（用户要求）**：用 TD IP Generator 生成 6 个 ROM（初始化文件全部备好，CRLF）：
   | IP 名 | 位宽×深度 | 初始化文件（mem_dath/） | 例化位置 |
   |---|---|---|---|
   | cnn_rom_w1 | 64×27 | `cnn_w_conv1_packed.dath` | conv1_frame ×1 |
   | cnn_rom_w2 | 64×144 | `cnn_w_conv2_packed.dath` | conv2_frame ×2（偶/奇字） |
   | cnn_rom_w3 | 64×576 | `cnn_w_conv3_packed.dath` | conv3_frame ×2 |
   | cnn_rom_w4 | 64×1152 | `cnn_w_conv4_packed.dath` | conv4_frame ×2 |
   | cnn_rom_wh | 64×64 | `cnn_w_head_packed.dath` | head_frame ×1 |
   | cnn_rom_exp | 16×1024 | `cnn_lut_exp.dath` | cnn_head_dec ×1 |
   **配置要点**：单口 ROM、EMB20K、**Output Register = None**（保持 1 拍读延迟，与 RTL 流水一致；
   选 Register 会多 1 拍导致全错）；**IP 名称必须与上表完全一致**（RTL 按此名例化）。
   每个 IP 的例化在对应包装模块里**显式可见**（无 generate / 条件例化）。
   RTL 接法：**已内置于各引擎** —— `hdl_source/cnn/cnn_rom_ip.v` 的 6 个同名同端口替身
   （`` `ifndef TD_SYN `` 包裹）已被 `conv1_frame / conv_frame / head_frame / cnn_head_dec`
   直接例化（同步读语义与 TD ROM IP 完全一致：addra 组合直连、doa 晚 1 拍）。
   在 TD 里用 IP Generator 生成同名 ROM 后**无需改任何 RTL**，直接综合即可；
   不加 IP 时替身走 `$readmemh`（TD 自动推断块 ROM），两条路线都合法；
5. **官方 RAM IP（同样已 IP 化）**：生成 3 个双口 RAM（端口命名与工程现有 `al_ip/ram_2port` 一致）：
   | IP 名 | 位宽×深度 | 用途 | 例化位置 |
   |---|---|---|---|
   | `cnn_buf_a` | 64×9216 | bufA：x1（1 字/像素）复用 x3（4 字/像素） | cnn_top ×1 |
   | `cnn_buf_b` | 128×2304 | bufB：x2（1 字/像素）复用 x4（2 字/像素） | cnn_top ×1 |
   | `cnn_buf_in` | 8×27648 | conv1 输入帧（3 平面） | conv1_frame ×1 |
   **配置要点**：双口 RAM（DP_RAM，同 `ram_2port`）、**REGMODE = NOREG**（无输出寄存器 → 读延迟 1 拍，
   与引擎流水一致；选 REG 会多 1 拍导致全错）、**无 init file**。RTL 只连 写口A(cea/clka/wea/addra/dia)
   + 读口B(ceb/clkb/addrb/dob)，其余端口(doa/dib/web)已按 IP 端口表置位，可直接绑定。
   替身在 `hdl_source/cnn/cnn_buf_ip.v`（`` `ifndef TD_SYN `` 包裹，仿真用）；
6. 综合 → 看资源报告（重点 `#dram lut` 应为 0/仅 DDR 的 296、`#eram`、`#dsp`、`#lut`，见 §9.5）；
7. 生成 bitstream 上板。

> **想尽快拿到资源数字的捷径**：若暂时不想逐个生成 6 个 IP，可以反过来做——**不加任何 ROM IP，
> 直接把 `cnn_rom_ip.v` 加进工程**（行为级 ROM，TD 自动推断块 ROM）。ROM 内容相同，ERAM/DSP/LUT
> 占用与用官方 IP 基本一致，可以先用它跑一遍综合/布局拿资源报告；数字确认没问题后再换成官方 IP 出码。
>
> **需要回传的东西**（做超限判断用）：
> ① 资源汇总（ERAM/EMB 块数 used/available、DSP、LUT、REG）；
> ② 若失败：报错行 + 日志（`td_project/td_*.log` 或 `camera_to_dsi_display_Runs/` 下的报告）；
> ③ 若通过：时序报告里 setup/hold 违例路径（74.25MHz 预期应能过）。

### 9.5 资源风险与修复记录（R2：综合报错后的修复）
**首次综合结果（2026-09-21）**：失败于布局阶段 `PHY-9009: mslice number = 38864, exceeds the limit 8112`。
真实资源：原有设计 9,086 LUT + 2,043 ripple；CNN 新增 53,889 LUT + 22,488 ripple + **38,400 dram-lut(LUTRAM)**；
ERAM 55/108（**不紧张**）、DSP 40/40（满）、REG 66%。⇒ 瓶颈是**逻辑**，不是 ERAM。

| # | 问题 | 修法 | 状态 |
|---|---|---|---|
| 1 | **帧缓存被推断成分布式 RAM（LUTRAM）**：写同步 + **组合读** → 烧掉 36,864 个查找表并触发 PHY-9009 | 新增 `cnn_ram.v`（**同步读块 RAM**），引擎改"读地址输出/读数据输入"端口；共享 **bufA(64b×9216)=x1→x3**、**bufB(128b×2304)=x2→x4**，conv1 输入 RAM 11 块 | ✅ 已改，10 tb 全绿 |
| 2 | **量化级 16 路并行** `acc×Q32` + 64 位符号舍入 + 钳位（全设计 80 份）→ 74K LUT + 40 DSP | 量化改**逐通道串行复用 1 套**（16 拍/组对），代价整链 964K→1.12M 拍（≈15.1ms，仍 60fps）；顺带把 conv_frame 拆出 3 个薄包装（显式例化 ROM，无 generate） | ✅ 已改，10 tb 全绿 |
| 3 | `cnn_ds10` 的 128 选 1 排空 MUX（logic 9,623） | 方案A：分 8 块×16 路排空（省 ~1~5K LUT）；方案B：改"横向流式 + 10 行线缓冲 + 逐块竖加"结构（省 ~5~6K LUT + 11.5K FF，改动大） | ⏳ 待新一轮综合数字决定是否需要 |

**修复后预期 ERAM**：bufA 29 + bufB 15 + conv1 输入 11 + ROM 21 + 原设计 29 ≈ **105 / 108**（紧，若超可合并小 ROM 或把 exp LUT 挪分布式 ROM）。
> 结论仍以 TD 综合报告为准：请重新综合一次，把新的资源汇总发回。

### 9.3 上板验收
1. 上电显示 720p 视频，模式 0（原图）；
2. 人脸 0.3~1.5 m 正对摄像头 → 绿框套脸（检测滞后 2 帧，HOLD_FRAMES=15 抹平）；
3. 云台形心 `O_face_x/y` 输出（1280×720 空间）接 PID 跟随；
4. 误检偏多 → `cnn_head_dec` 的 `SCORE_TH_Q12` 从 615 上调（0.15→0.3 即 1229）；
5. 彩绘脸未覆盖 → `matlab/cnn_detector` 补数据重训（`训练记录.md` 配方）→ 重跑 `export_fpga_consts.m`
   → 重新生成 bitstream（权重文件替换即可，RTL 不动）。

### 9.4 性能状态与升级路线
- ✅ **16 DSP（2×8 切片）已落地**：整链 964K 拍 ≈ 13 ms @74.25MHz → **检测 60fps 可行**（上板实测为准）；
- 可选再加码：conv1 双像素并行（Cout=8 只用 8 DSP，可 2 像素并行填满 16 → 整链 ~840K 拍）；
  或引擎提频 148.5 MHz（PLL 现成）。

---

## 附录 A：MATLAB 定点常数导出脚本（`matlab/cnn_detector/export_fpga_consts.m`）

> 已跑通（`matlab -batch` 无头运行）。**注意**：本机沙箱环境下 MATLAB 启动会报
> "Fatal Startup Error: File system inconsistency"，需以完整访问权限运行（Danger 模式），
> 脚本本身只读 `out/net_params.mat`，不依赖训练图片。换权重后重跑该脚本 + 重跑 §8 的 ModelSim 命令即可。

## 附录 B：各层 ROM/RAM 规格表

| 层 | 权重打包 ROM（8ch/字 ×64bit） | 偏置（int32×Cout） | 输入特征图（打包宽字） | 输出特征图 |
|---|---|---|---|---|
| conv1 | 27 字（3×3×3 tap） | 8 | 9216×24bit（RGB888） | 9216×64bit |
| conv2 | 144 字（9×8 tap ×2 组） | 16 | 9216×64bit | 2304×128bit |
| conv3 | 576 字（9×16 tap ×4 组） | 32 | 2304×128bit | 576×256bit |
| conv4 | 1152 字（9×32 tap ×4 组） | 32 | 576×256bit | 576×256bit |
| head | 64 字（1×32 tap ×2 组） | 15 | 576×256bit | 576×240bit（Q12×15） |
| expLUT | 1024×16bit | — | — | — |

> 打包字与 MATLAB 列主序 [ky kx cin cout] 的关系：字地址 = tap×组数 + 组号，字内 bit[8c+7:8c] = 第 g×8+c 输出通道。
