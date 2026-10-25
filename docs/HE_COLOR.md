# 直方图档"发灰 / 发蓝"的根因与修复（L1 + L3）

> 日期：2026-10-22 ~ 10-23
> 改动文件：`vpp_top.v`
> 新增文件：`RGB888_Y888.v`、`hue_scale.v`、`sim/vpp_top_l1_tb.v`
> 仿真环境：ModelSim 10.4 + `sim/he_ram_stub.v`（TD ERAM 行为级桩件）
>
> ⚠ **2026-10-23 重要更新**：§3.2 里的 `chroma_comp` 方案已被 **L4（§11）取代** ——
> 原因不是算法错，而是**这颗芯片只有 40 个 DSP、原设计已用满**，加 9 个乘法器把设计
> 顶到 49/40，TD 被迫把乘法器硬塞进 9x9 双乘法模式，连带把 Sobel/卡通的 Y 弄坏
> （mode 3/4 满屏雪花）。现在改成 `RGB' = RGB*(Y'/Y)`，DSP 比原设计还少 3 个。

---

## 1. 症状演进

| 阶段 | 屏上表现 |
|---|---|
| 最初（线性域 HE + 后接 gamma） | **发灰**：颜色不突出、像蒙了一层，但红还是红 |
| 加了 L1（HE 挪到显示域） | **发蓝**：整屏偏蓝，像加了一层蓝滤镜 |
| 加 L3（色度补偿） | 颜色与模式 0 一致，只有亮度按 HE 曲线走 |

两个症状是**同一个毛病**的两个方向，见 §2。

---

## 2. 根因

### 2.1 只改 Y ⇒ RGB 三通道同加一个常数（加性）

```
R = Y + 1.402(Cr-128)          把 Y 换成 Y'、Cb/Cr 原样，代入得
G = Y - 0.344(Cb-128) - 0.714(Cr-128)      R' = R + Δ , G' = G + Δ , B' = B + Δ
B = Y + 1.772(Cb-128)
```

- `R-G`、`B-G` **完全不变** → 色相不变（所以"红还是红"；定点链上残差 1~3 LSB，全是取整）。
- 饱和度 `S=(max-min)/max`：分子不变、分母 `max` 跟着 Δ 走 →
  **S 按 1/亮度增益 变化**：

| HE 对这个像素的亮度 | 增益 | 饱和度 | 观感 |
|---|---|---|---|
| 提亮 | > 1 | 下降 | 发白 / 发灰 |
| 压暗 | < 1 | 上升 | 环境色被放大 → 发蓝 / 发黄 |

`tools/he_color/patch_demo.png` 用色块直接演示：只把 Y 加 40，平均 S 从 0.593 → 0.481；
Y 乘 1.6 → 0.413；而"Y 乘 1.6、Cb/Cr 也乘 1.6"能回到 0.573。

> 对比：如果改的是 `V=max(R,G,B)`（乘性），R/G/B 同乘 k，色相和 S 都不变 ——
> 这就是教科书说"只在 HSV 的 V 上做均衡"的原因。

### 2.2 为什么会"发灰"：HE 在线性域，gamma 在其后（放大器）

旧链路：`线性 Y -> HE -> 转回 RGB -> 再套 γ2.2`。线性直方图全挤在低端，HE 摊平后
大部分像素被抬到中高线性值；再套 γ2.2（凹函数，中高段斜率 ~0.6），通道差值又压掉 4 成。
720P 真实图像逐位复现：**平均饱和度 0.177 → 0.100**，深蓝外套 (41,46,65) → (78,83,91)。

### 2.3 为什么会"发蓝"：HE 在显示域，把中调/暗部压暗了

L1 之后链路变成 `gamma -> Y/Cb/Cr -> HE(Y) -> RGB`。这时颜色仍然由 `k = Y'/Y` 决定：
**哪个像素被 HE 压暗，它的颜色就被等比例放大**。现场这个场景（暗房间 + 大片墙 + 灯光峰值）
的直方图被亮部占住，中间调被压下去、暗部更是被压到接近 0 —— 亮度塌下去而色度不动，
饱和度与彩噪一起被放大，屏上就是"蓝屏 + 颗粒"。

量化（Python 定点模型 + 720P 真实照片）：显示域 HE 平均 |ΔY| ≈ 16 级、整体 ×0.94，
饱和度 0.177 → 0.210（×1.19）；被压得更狠的暗部像素 k 会低于 0.5，饱和度就是 ×2 以上。

> ⚠ 一个测量坑（已修）：第一版 `vpp_top_l1_tb` 统计时把**上电第一帧**也算进去了。
> 那一帧 CDF 还是空的 → Y'=0 → 输出是"全黑 + 残留色度"的垃圾，饱和度接近 1，
> 把平均值抬到了 1.68。改成只统计第 2 帧后，四色块合成图（映射接近恒等）上的
> L1-only 比值只有 1.03 —— 也就是说**合成色块图本身就测不出这个毛病**，
> 真正会翻车的场景是"直方图被亮部占住、中间调被压暗"的实拍画面。

### 2.4 结论

**只改 Y 的方案天生保证不了颜色**，必须把色度一起按同样的增益缩放 —— 这就是 L3。

---

## 3. 改动

### 3.1 L1：把 HE 搬到显示域（修"域"）

| # | 位置 | 内容 |
|---|---|---|
| 1 | 新增 **2A 节** | `gamma_lut` 从第 5 节搬到最前（Verilog 先用后声明会生成隐式 1 位线网） |
| 2 | 第 2 节 → **2B 节** | 两个 `RGB888_YCbCr444`：(a) 线性域 → 只喂 Sobel；(b) 显示域 → 喂直方图 |
| 3 | 第 3 节 | `histogram_equ` 输入换成 (b) 的 `y_he_tdata` |
| 4 | 第 5 节 | 删掉 gamma 实例（已搬走） |
| 5 | 第 6 节 | `cb_d/cr_d/he_*_d` 改接 (b) |
| 6 | 6b 节 | 删除 `gamma_lut u_gamma_lut_he`，`chroma_nr` 直接吃转出来的 RGB |

为什么 Sobel 不共用 (b)：Y 只有一份，若把 (a) 的输入改成 gamma，Sobel 也跟着跳到显示域，
边沿梯度放大 2~3 倍、阈值 60 会过曝成大白边。所以给直方图单独加一套（+9 个乘法器）。

### 3.2 L3：色度补偿（修"色"）

新增 `chroma_comp.v`，对每个像素：

```
k  = Y' / Y                        (HE 对这个像素的亮度增益)
Cb' = 128 + k*(Cb-128)
Cr' = 128 + k*(Cr-128)
```

因为 `Y' = k*Y`，代回反变换可严格推出：

```
R' = k*R , G' = k*G , B' = k*B          —— 整幅图乘一个 k
```

也就是说：**色相、饱和度与模式 0 完全一致，只有亮度按 HE 的曲线走**
（文献里的 hue-preserving / color-preserving histogram equalization）。

定点实现（`chroma_comp.v`）：

- `1/Y` 查表 64 项（索引 `Y[7:2]`，Q12），误差 <3%；
- `k_q8 = (Y' * inv) >> 4`，再限幅 `K_MIN_Q8=64(0.25x) ~ K_MAX_Q8=512(2.0x)`；
  限幅下限必须低：HE 把暗部压到接近 0 时 k→0，色度必须跟着压掉，否则又变成"压暗=发蓝"；
- `Y' == Y` 时强制 `k = 1.0x`：保证"映射是恒等的那部分颜色一丝不差"；
- 资源：3 个乘法器（1 个算 k，2 个给 Cb/Cr）+ 64x12 查表，3 拍。

**延迟重新配平**：`3(转换) + 3(HE) + 3(色度补偿) + 3(YCbCr→RGB) + 3(chroma_nr) + 7(he_rgb_d) = 22 拍`
（`he_rgb_d` 由 `[0:9]` 改为 `[0:6]`，`he_tlast_d/he_tuser_d` 由 3 级扩到 6 级）。
`design_top_wrapper.v` 里 vs 的 27 拍补偿**不用动**。

---

## 4. 验证

### 4.1 编译

`vpp_top.v` + `chroma_comp.v` + 全部依赖 → `Errors: 0, Warnings: 0`。

### 4.2 时序对齐（`sim/vpp_top_aln_tb.v`，64×64，左暗 40 / 右亮 200）

```
  beat |  mode0(R)  |  mode2(R)
     30 |         77 |         75
     31 |        217 |        208     <- 台阶仍在同一个 beat
     62 |        217 |        209
```

### 4.3 色调域（`sim/vpp_top_l1_tb.v` 检查 A，16 项 0 错误）

| 输入 RGB | `y_he`（直方图链） | `y_lin`（Sobel） |
|---|---|---|
| (200,60,55) 红 | 144 | 101 |
| (60,140,75) 绿 | 154 | 108 |
| (45,80,150) 蓝 | 128 | 77 |
| (205,165,140) 肤色 | 204 | 174 |
| (10,10,10) 暗（低于黑电平） | 0 | 10 |
| (240,240,240) 白 | 239 | 240 |

`y_he` 精确等于 `Y(γ(R),γ(G),γ(B))`，`y_lin` 仍是 `Y(R,G,B)` —— 两个转换器各就各位。

### 4.4 颜色（同一 TB 检查 B，四色块图，第 2 帧统计）

```
    模式0 (原图+gamma)            : 平均饱和度 0.427
    模式2 (显示域HE+色度补偿+降噪) : 平均饱和度 0.438
    比值 模式2/模式0 = 1.025          (L1 之前 0.55 = 发灰；L3 之后应 ≈1.0)
    与模式0 的逐像素色差 |dR|+|dG|+|dB| 平均 = 10.2 级 (每通道 3.4 级)
    >>> ALL PASS
```

> 这张四色块合成图的 HE 映射接近恒等（k≈0.94），所以它主要用来卡"颜色不能被改"这条红线；
> k 偏离 1 较多的情形由 `chroma_comp_tb`（1500 项，k 从 0.25x 到 2.0x 全覆盖）和
> §4.4 的逐点对照共同覆盖。

四个色块的逐点对照（探针实测）：

| 色块 | 模式 0 | 模式 2 |
|---|---|---|
| 红 (200,60,55) | (217,119, 84) | (205,115, 79) |
| 绿 (60,140,75) | (109,186,112) | (104,183,106) |
| 蓝 (45,80,150) | ( 87,140,179) | ( 79,131,166) |
| 肤色 (205,165,140) | (220,202,172) | (213,198,165) |

每通道差 3~8 级，全部来自 YCC 往返取整 + `k≈0.94` 的整体压暗，**色相与饱和度没变**。

### 4.5 单元测试（`sim/chroma_comp_tb.v`）

1500 项逐值比对 + "k=1 时颜色必须原样"语义检查 → **0 错误**。

---

## 5. 代价与上板检查清单

1. **资源**：+1 套 RGB→YCbCr（9 个 8x8 常数乘法）+ `chroma_comp`（3 个乘法器 + 64x12 查表）。
2. **两条新路径要看时序**：
   - `gamma_lut`（组合）→ (b) 的乘法器输入（以前只喂寄存器）；
   - `chroma_comp` 里算 `k` 的乘法 → 紧跟色度乘法（已拆成 3 拍，级间都是寄存器）。
   HDMI_PIXEL_CLK 域 WNS 只有 +105 ps，综合布线后请检查这两条。
3. **上板必看**：
   - 模式 0/1/3/4 应与改动前完全一样（数据通路没动）；
   - 模式 2 的颜色应与模式 0 一致，只是明暗曲线不同；
   - 上电第一帧模式 2 会是黑的（CDF 还没建好），属正常，第二帧起正常。

## 6. 备用方案（历史记录，现在的 L4 实现已不适用）

> 下面这段是 L1 时期为"gamma 直驱 YCbCr 转换器"准备的备用方案；L4 之后那条转换器
> 已经不存在（改成 `RGB888_Y888` + `hue_scaling`），**不用再做这一步**。留档备查。

把 gamma 打一拍只给 (b) 用：`gamma_*_d <= gamma_*`，控制信号 `he_v_d/he_u_d/he_l_d`
同步打一拍，喂给转换器；然后 `he_rgb_d` 由 7 级减到 6 级（总延迟仍 22 拍）。
`raw_rgb_d` 那条链不动（卡通档还是 `raw_rgb_d[0]`）。

## 7. 调参

| 想要的效果 | 动作 |
|---|---|
| 对比度更强/更弱 | `histogram_equ` 的 `CLIP_DIV`：64（默认）/ 32（更强）/ 128（更温和） |
| 允许更夸张的亮度增益 | `hue_scale` 的 `K_MAX_Q8`（512=2.0x，默认）/ 768=3.0x |
| 暗部还想更"压住"颜色 | `hue_scale` 的 `K_MIN_Q8`（64=0.25x，默认）/ 32=0.125x |
| 局部对比度 | CLAHE（`HE_OPTIMIZATION.md` 第 6 节已排期） |

## 8. 如果上板还是偏蓝

L3 之后模式 2 的颜色**在数学上就等于模式 0**。若还偏蓝，说明颜色是在进 VPP 之前就偏的：

1. 切到**模式 0** 看同一场景 —— 如果模式 0 也偏蓝，问题在 `awb.v`（低照度下没收敛）
   或光源本身，不在直方图档；
2. 如果是"暗部偏蓝/噪点多"，那是 AWB 把 B 通道噪声放大了 2.75 倍（`gamma_lut.v` 注释里
   也提到 R/B 的 pedestal 被 AWB 乘过），需要单独处理黑电平与色度降噪。

## 9. 怎么重跑仿真

```powershell
$hd  = "…\user_source\hdl_source"; $sim = "…\sim"
vlib work
vlog $hd\gamma_lut.v $hd\RGB888_YCbCr444.v $hd\YCbCr444_RGB888.v $hd\histogram_equ.v `
     $hd\Sobel_edge.v $hd\Sobel_edge_detection_top.v $hd\Erosion.v $hd\Dilation.v `
     $hd\chroma_nr.v $hd\chroma_comp.v $hd\Cartoon_Blend.v $hd\Color_Quantize.v `
     $hd\bilateral_rom_ip.v $hd\bilateral_filter_3x3.v $hd\cartoon_top.v `
     $sim\he_ram_stub.v $hd\vpp_top.v `
     $sim\chroma_comp_tb.v $sim\vpp_top_l1_tb.v $sim\vpp_top_aln_tb.v

vsim -c -do "run -all; quit -f" chroma_comp_tb     # 1500 项自检
vsim -c -do "run -all; quit -f" vpp_top_l1_tb      # 色调域 + 颜色
vsim -c -do "run -all; quit -f" vpp_top_aln_tb     # 22 拍对齐
```

> `bilateral_*.hex` 找不到只会让卡通档的 ROM 读出 X，不影响模式 0/2 的检查。
> 注：`sim/vpp_top_tb.v` 是更早的版本（`display_mode` 还是 2 bit），本次改动之前就已失配，不是 L1/L3 引起的。

## 11. L4：为什么最后改成 RGB×k（DSP 预算事件）

### 11.1 现场：Sobel / 卡通满屏雪花，但时序是过的

2026-10-23 上板后模式 3（Sobel）和模式 4（卡通）变成满屏黑白噪点，而模式 0/2 正常。
`vpp_top.v` 里这两档的 RTL 一个字节都没改（`git diff -U0` 里与它们相关的只有注释），
所以先看综合报告。关键几行：

```
final timing :  Setup WNS +191ps  TNS 0  FEPS 0      ← 时序过
                Hold  WNS  +20ps  TNS 0  FEPS 0
gate 阶段    :  #dsp  49  out of  40   122.50%        ← 逻辑上要 49 个 DSP
place 阶段   :  "Need to merge 9 9x9 Dsps."
                #dsp  40  out of  40   100.00%
                SYN-2600 : DSP u_vpp_top/u_RGB888_YCbCr444/mult2 will be merged
                           into .../mult0 by using 9x9 mode          ← 这是 Sobel 的 Y
                SYN-2600 : DSP u_cartoon_top/u_RGB888_YCbCr444/mult2 → mult1
                SYN-2600 : DSP u_cartoon_top/u_bilateral_filter/mult2 → mult0
```

结论：**不是时序问题，是 DSP 超预算**。这颗 PH1P35 只有 **40 个 DSP**，
原设计的模式 2 用 13 个（YCbCr 正变换 9 + 反变换 4），全设计正好 40/40、一次都不用打包。
L1+L3 加了 9 个（第二套转换器净 +6、chroma_comp +3）→ 49 个，TD 只好把 9 对乘法器
塞进"9x9 双乘法"模式；被塞的位置**恰好包含喂给 Sobel 的 Y 和卡通内部的两处乘法器**，
阈值二值化把任何一位错误放大成满屏雪花。

> 经验：这颗芯片**没有任何 DSP 余量**。以后给 VPP 加任何乘法器前，先看
> `report_qor` 的 `#dsp` 是不是 40/40、log 里有没有 `will be merged into ... 9x9`。

### 11.2 改法：RGB' = RGB × (Y'/Y)

不再"改 Y 再用 Cb/Cr 反变换"，直接在 RGB 上乘增益：

```
Y'  = HE(Y)              Y 由 RGB888_Y888.v 算（3 个乘法器）
k   = Y'/Y               hue_scale.v（1 个乘法器）
RGB' = RGB * k           hue_scale.v（3 个乘法器）
```

因为 `Y' = k·Y`，所以 `R'=kR、G'=kG、B'=kB` —— 色相与饱和度**严格不变**，
只有亮度按 HE 曲线走（比 L3 的"改色度"更干净，且不需要 Cb/Cr）。

| 资源 | 原设计 | L1+L3（出问题那版） | **L4（现在）** |
|---|---|---|---|
| 模式 2 这条链的 DSP | 13 | 19 | **10** |
| 全设计 DSP | 40/40 | 49/40（强制打包 9 个） | **≈37/40** |
| 器件 | `RGB888_YCbCr444` ×1 + `YCbCr444_RGB888` ×1 | 再加一套 + `chroma_comp` | `RGB888_Y888` ×2 + `hue_scale` ×1 |

延迟重新配平：`3(Y) + 3(HE) + 3(hue_scale) + 3(chroma_nr) + 10(he_rgb_d) = 22` 拍，
`gam_rgb_d[0:5]` 把 gamma 后的 RGB 对齐到第 6 拍（与 `y_he_d[2]`/`y_equ` 同拍）。

### 11.3 验证（ModelSim）

* 编译 `Errors: 0, Warnings: 0`
* 22 拍对齐：台阶仍在 **beat 31**（mode0 78→217 / mode2 78→211，比之前更接近，因为 k 缩放是精确的）
* 色调域 16 项检查 0 错误
* **颜色**：模式2/模式0 平均饱和度比 **0.998**，逐像素色差 **3.2 级/通道**
* 新模块：`RGB888_Y888.v`（3 拍，与 `RGB888_YCbCr444` 的 Y 定点完全一致）、`hue_scale.v`（3 拍）

> `chroma_comp.v` 现在**没有实例化**了，文件可以留在工程里（不占资源）也可以删掉。

## 12. 结构性重构（2026-10-23 下午）：统一成"特征模块"

目标：让 vpp_top 里的算法模块形态一致 —— **吃 RGB、吐 RGB（或边缘图）、固定拍数、自包含**，
和 `cartoon_top` 对齐，而不是在顶层到处飞裸的 Y 中间信号。

### 12.1 改了什么

| 改动 | 说明 |
|---|---|
| 新增 `hist_eq_color_top.v` | 特征模块，RGB 进 RGB 出，**固定 9 拍** = `RGB888_Y888`(3) + `histogram_equ`(3) + `hue_scale`(3) |
| `Sobel_edge_detection_top` 端口改成 RGB | 内部自带 `u_rgb2y`（3 拍），喂**线性域** RGB → Y 与改造前逐位一致，`SOBEL_THRESHOLD=60` 不用重调；总延迟仍 **16 拍** |
| `cartoon_top` 内部换模块 | `RGB888_YCbCr444`(算 Y+Cb+Cr，9 个乘法器，但 Cb/Cr 从没被用到) → `RGB888_Y888`(3 个)。Y 定点完全一致，卡通仍 **21 拍、逐位不变**，顺带删掉 `cb_tdata/cr_tdata` 两个死端口 |
| vpp_top 删除 4 个裸实例 | `u_RGB888_Y888_lin` / `u_RGB888_Y888_disp` / `u_histogram_equ` / `u_hue_scale`，以及 `y_tdata`/`y_he_tdata`/`gam_rgb_d`/`y_he_d` 等中间信号 |

vpp_top：**541 行 → 414 行，实例 9 → 6**。

### 12.2 现在的结构

```
I_tdata ─┬─► Sobel_edge_detection_top (内含 RGB2Y, 16 拍) ─► +6 拍 ─► 模式3
         └─► cartoon_top             (内含 RGB2Y, 21 拍) ─► 模式4
gamma ─► hist_eq_color_top (内含 RGB2Y+HE+保色缩放, 9 拍) ─► chroma_nr ─► +10 拍 ─► 模式2
gamma ─► raw_rgb_d[22] ─► 模式0 / 灰度 / CNN
```

| 实例 | 类型 | 契约 | 拍数 |
|---|---|---|---|
| `u_gamma_lut` | 算子（组合） | RGB → RGB | 0 |
| `u_hist_eq_color` | **特征** | RGB → RGB | 9 |
| `u_Sobel_edge` | **特征** | RGB → 边缘 | 16 |
| `u_cartoon_top` | **特征** | RGB → RGB | 21 |
| `u_chroma_nr_he` / `u_chroma_nr` | 算子 | RGB → RGB（亮度不变） | 3 |

> 设计原则：**算子模块保持通用**（`histogram_equ` 仍是"任意 8 位 → 映射后 8 位"、`hue_scale` 仍是"RGB×增益"），
> **特征模块负责自包含**（用薄包装把算子拼成"RGB 进 RGB 出"）。两者不要混。

### 12.3 验证（重构后逐位不变）

* 编译 `Errors: 0, Warnings: 0`
* 22 拍对齐：beat 31，数值与重构前完全一致（mode0 78→217 / mode2 78→211）
* 色调域 16 项 0 错误（探针改为 `u_m0.u_hist_eq_color.u_rgb2y` / `u_m0.u_Sobel_edge.u_rgb2y`）
* 颜色：饱和度比 **0.998**，逐像素色差 **3.2 级/通道**

### 12.4 重跑仿真（重构后的文件清单）

```powershell
vlog $hd\gamma_lut.v $hd\RGB888_Y888.v $hd\hue_scale.v $hd\histogram_equ.v `
     $hd\hist_eq_color_top.v $hd\Sobel_edge.v $hd\Sobel_edge_detection_top.v `
     $hd\Erosion.v $hd\Dilation.v $hd\chroma_nr.v $hd\RGB888_YCbCr444.v `
     $hd\Cartoon_Blend.v $hd\Color_Quantize.v $hd\bilateral_rom_ip.v `
     $hd\bilateral_filter_3x3.v $hd\cartoon_top.v `
     $sim\he_ram_stub.v $hd\vpp_top.v $sim\vpp_top_l1_tb.v $sim\vpp_top_aln_tb.v
```

> ⚠ 加进 TD 工程的新文件：`RGB888_Y888.v`、`hue_scale.v`、`hist_eq_color_top.v`。
> 另外 **`Sobel_edge_detection_top.v` 的端口变了**（`I_grey_tdata` → `I_red/green/blue_tdata`），
> `cartoon_top.v` 内部的转换器也换了，两个文件要一起更新。
>
> 现在 `RGB888_YCbCr444.v` 和 `YCbCr444_RGB888.v` **全工程已无例化**（取亮度统一用
> `RGB888_Y888`，直方图档也不再做 YCbCr 反变换）。文件可以留在磁盘当参考，
> 也可以从 TD 工程里移除；`chroma_comp.v` 同样已无例化。



## 10. 回滚

```powershell
git checkout HEAD -- "lab_ex1_mipi_hdmi_SC500_720P+vpp/lab_ex1_mipi_hdmi+vpp/user_source/hdl_source/vpp_top.v"
```

只回滚 L3、保留 L1：把 `vpp_top.v` 里 6a 节的 `chroma_comp` 去掉，
`u_YCbCr444_RGB888` 的 `.I_y/.I_cb/.I_cr/.I_tvalid` 换回 `y_equ_tdata / cb_d[2] / cr_d[2] / he_tvalid_d[2]`，
`.I_tlast/.I_tuser` 换回 `[2]`，`he_rgb_d` 改回 `[0:9]`、`he_tlast_d/he_tuser_d` 改回 `[0:2]`。
