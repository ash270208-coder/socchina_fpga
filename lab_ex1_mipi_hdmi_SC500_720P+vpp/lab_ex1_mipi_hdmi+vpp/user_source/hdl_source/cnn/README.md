# cnn/ —— FPGA 端 CNN 人脸检测（Verilog）

本目录是 FPGA 端的实现。

> **当前进度：第 ①② 步已完成并通过仿真验证** —— `conv1_pixel` 单像素算术通路
> 在 ModelSim 中与金标准 **40/40 项逐位一致（PASS）**。
> 下一步：第 ③ 步「整帧行缓存 + 滑窗」。

> 全部公式与常数来自 `matlab/cnn_detector/FPGA部署契约.md`；
> 权重与金标准数据由 `matlab/cnn_detector/step3/step4` 生成。

---

## 一、文件分布

| 路径 | 内容 |
|---|---|
| `user_source/hdl_source/cnn/conv1_pixel.v` | **conv1 单输出像素算术通路**（本目录，第 ① 步产物） |
| `user_source/hdl_source/cnn/README.md` | 本文件 |
| `sim/conv1_pixel_tb.v` | 测试平台（对拍脚本） |
| `sim/cnn_data/*.mem` | 权重/偏置/LUT（从 `matlab/cnn_detector/out/` 拷贝） |
| `sim/cnn_data/*.hex` | **逐层金标准**（`$readmemh` 可读；由 `out/golden/*.txt` 转十六进制得到） |

金标准数据规模（MATLAB 列主序 `X(:)`，索引 = `r + H*c + H*W*ch`）：

| 文件 | 尺寸 | 值 |
|---|---|---|
| `x0_input.hex` | 72×128×3 = 27648 | 输入 RGB 0..255 |
| `x1_conv1.hex` | 72×128×8 = 73728 | conv1 输出 |
| `x2_conv2.hex` | 36×64×16 = 36864 | conv2 输出 |
| `x3_conv3.hex` | 18×32×32 = 18432 | conv3 输出 |
| `x4_conv4.hex` | 18×32×32 = 18432 | conv4 输出 |
| `head_real.hex` | 18×32×15 = 8640 | 检测头输出（Q12 定点，int32） |

## 二、第一步在验什么

把整条算术链用一个最小电路走通，逐项排除最容易错的地方：

```
权重 ROM($readmemh)  →  27 次 MAC（累加器初值 = 偏置）
                     →  acc × mOut(Q16)  →  四舍五入右移 16  →  clamp 0..255
```

只要 `conv1_pixel` 的输出与 `x1_conv1.hex` 逐位一致，就说明：
权重文件布局、ROM 读取、符号扩展、累加器位宽、定点系数、舍入方式、饱和逻辑——**全都是对的**。
后面 3 层和检测头只是同样的东西参数化复用。

## 三、怎么跑（在【仓库根目录】执行，那里有 `modelsim.ini` 和 `work/`）

```tcl
vlib work_cnn
vlog -work work_cnn lab_ex1_mipi_hdmi_SC500_720P+vpp/lab_ex1_mipi_hdmi+vpp/user_source/hdl_source/cnn/conv1_pixel.v sim/conv1_pixel_tb.v
vsim -c work_cnn.conv1_pixel_tb -do "run -all; quit -f"
```

**已验证的实际输出**（2026-09-20）：

```
=========================================================
 conv1 single-pixel check   (golden: out/golden/x1_conv1.txt)
---------------------------------------------------------
 weight ROM self-test (first 4 entries of w_conv1.mem):
   w[0..3] = 29 -27 -47 -20
   b[0..3] = 2779 -1193 9563 7690
---------------------------------------------------------
  pixel(0,0): all 8 channels checked
  pixel(0,5): all 8 channels checked
  pixel(1,1): all 8 channels checked
  pixel(35,64): all 8 channels checked
  pixel(71,127): all 8 channels checked
---------------------------------------------------------
 RESULT: PASS  -- 40 checks all match the golden data
=========================================================
```

- `PASS`：第 ①② 步完成，进入第 ③ 步（整帧滑窗）；
- `FAIL`：`$display` 已打印"实际 vs 期望"，按下面的坑逐项排查。

## 四、六个必须知道的点

1. **权重地址公式**（列主序）：`addr = ky + K*kx + K*K*ci + K*K*CIN*co`
   ——写错一位，整层全错；
2. **patch 顺序与权重同构**：`x_patch[i*9 +: 9]`，`i = ky + 3*kx + 9*ci`，这样 MAC 循环就是简单的 `w[co*27+i]`；
3. **符号扩展**：`.mem` 是 8 位二进制补码，读出后必须按有符号参与运算（本模块用 `reg signed [7:0]` + `wire signed [8:0] xs = {1'b0, xv}`），否则负权重变成 +128 级大正数；
4. **舍入**：MATLAB 用 `round`，硬件算术右移是下取整 → 必须 `+32768` 再 `>>>16`，否则差 1 LSB 就对不上；
5. **累加器位宽**：`|acc| ≤ 127×255×27 + |b_int|`，本模块用 32 位（后续层最多 28 位也够，DSP 48 位余量充足）；
6. **位宽必须逐位对齐**（实际踩过的坑）：TB 里 `patch_flat` 曾写成 `[26*9-1:0]`（234 位），
   而 27 个 tap × 9 位 = **243 位** → 第 26 个 tap 读到高阻 `z`，乘法结果变 `x`，40 项全 FAIL。
   现象是"输出全 x"，定位方法：打印内部信号（`xv/ws/prod/acc`）看哪个先变 x。

## 五、下一步（第 ③ 步：整帧滑窗）

1. 加 **行缓存**（3 通道 × 3 行，或按通道串行复用）+ 3×3 滑窗寄存器阵（与你们 Sobel 行缓存同构）；
2. 在帧首拉高 `start`，逐像素输出 128×72×8，与 `x1_conv1.hex` **整帧逐位比对**；
3. 通过后参数化 Cin/Cout/K/stride/pad，依次打通 conv2/conv3/conv4（stride=2 的输出坐标生成是唯一新知识点）；
4. 再做 head_conv(1×1) + 解码（exp 查表 + 锚框 + 最高分单框），与 `sim/cnn_data/head_real.hex` 对拍。

> TD 工程的 `.al` 文件暂不登记本模块——第 ③/④ 步要综合上板时，在 TD 里 **Add Source** 加入
> `conv1_pixel.v`（以及后续模块），并确认 `sim/cnn_data/*.mem` 能被综合工具的 `$readmemh` 找到
> （综合时把 `.mem` 拷到工程工作目录，或改模块的 `W_MEM/B_MEM` 参数）。
