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
| `user_source/hdl_source/cnn/conv1_pixel.v` | **conv1 单输出像素算术通路**（第 ①② 步产物） |
| `user_source/hdl_source/cnn/cnn_rom.v` | **权重/偏置 ROM 包装**（仿真=行为级；综合=官方 ERAM 原语，宏切换） |
| `user_source/hdl_source/cnn/mem_dath/*.dath` | TD 官方 ROM IP 的初始化文件（由 `.mem` 直接改名而来） |
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
vlog -work work_cnn lab_ex1_mipi_hdmi_SC500_720P+vpp/lab_ex1_mipi_hdmi+vpp/user_source/hdl_source/cnn/cnn_rom.v \
                        lab_ex1_mipi_hdmi_SC500_720P+vpp/lab_ex1_mipi_hdmi+vpp/user_source/hdl_source/cnn/conv1_pixel.v \
                        sim/conv1_pixel_tb.v
vsim -c work_cnn.conv1_pixel_tb -do "run -all; quit -f"
```

**已验证的实际输出**（2026-09-20，换用 `cnn_rom` 同步读之后重跑）：

```
=========================================================
 conv1 single-pixel check   (golden: out/golden/x1_conv1.txt)
---------------------------------------------------------
 bias ROM self-test: b[0] = 2779 -> y = 10 (expect 10)
---------------------------------------------------------
  pixel(0,0): all 8 channels checked
  pixel(0,5): all 8 channels checked
  pixel(1,1): all 8 channels checked
  pixel(35,64): all 8 channels checked
  pixel(71,127): all 8 channels checked
---------------------------------------------------------
 RESULT: PASS  -- 41 checks all match the golden data
=========================================================
```

- `PASS`：第 ①② 步完成，进入第 ③ 步（整帧滑窗）；
- `FAIL`：`$display` 已打印"实际 vs 期望"，按下面的坑逐项排查。

## 五、权重 ROM 用哪种实现？（仿真 vs 综合）

权重不写在代码里，而是放在 ROM 里。**同一个 `cnn_rom` 包装，两种实现，用宏切换**：

| 场景 | 实现 | 怎么选 | 好处 |
|---|---|---|---|
| **ModelSim 仿真** | 行为级 `reg + $readmemh(.mem)` | 默认（不定义宏） | 不需要安路原语库——工程里就踩过"**安路 IP 原语仿真失败**"的坑 |
| **TD 综合上板** | 官方原语 `PH1P_LOGIC_ERAM` + `.dath` | 定义 `` `define CNN_TD_ROM `` | 与工程里 `rom_weak_lut` 同一模板，保证映射到 ERAM 块、时序可控 |

`cnn_rom.v` 里综合分支的参数/端口与 `td_project/al_ip/rom_weak_lut/RTL/rom_*.v` 完全一致
（`MODE="SP"`、`REGMODE_A="NOREG"`、`IMPLEMENT="20K"`、`INIT_FILE(.dath)`、`FILL_ALL("NONE")`）。

**上板时怎么切**：
1. 把 `cnn/mem_dath/*.dath` 拷到 TD 工程工作目录（`td_project/` 下）；
2. 在 TD 的 Verilog 编译选项里加宏 `CNN_TD_ROM`（或在 `cnn_rom.v` 顶部写 `` `define CNN_TD_ROM ``）；
3. `DATH_FILE` 参数默认是 `"cnn_w_conv1.dath"` 这种相对名——若 TD 报找不到文件，把参数改成实际相对路径。

**如果你更想用 IP Generator 图形界面**（等价做法，工程里 `rom_weak_lut` 就是这么来的）：
Tools → IP Generator → Memory → ERAM：
- 模式选 **ROM**、单口（SP）、位宽/深度按下表填、初始化文件选对应的 `.dath`；
- 生成后把产生的 `rom_xxx.v` 放到 `cnn/` 下，并把 `conv1_pixel.v` 里的 `cnn_rom u_w_rom(...)` 换成该 wrapper 的实例（接口一样：`clka/addra/doa`）。

各 ROM 的配置（地址宽度按"位宽×深度"再核对一次即可）：

| ROM | 位宽 | 深度 | 对应 .dath |
|---|---|---|---|
| conv1 权重 | 8 | 256（实际用 216） | `cnn_w_conv1.dath` |
| conv1 偏置 | 32 | 8 | `cnn_b_conv1.dath` |
| conv2 权重/偏置 | 8 / 32 | 2048(1152) / 16 | `cnn_w_conv2.dath` / `cnn_b_conv2.dath` |
| conv3 权重/偏置 | 8 / 32 | 8192(4608) / 32 | `cnn_w_conv3.dath` / `cnn_b_conv3.dath` |
| conv4 权重/偏置 | 8 / 32 | 16384(9216) / 32 | `cnn_w_conv4.dath` / `cnn_b_conv4.dath` |
| head 权重/偏置 | 8 / 32 | 512(480) / 16 | `cnn_w_head.dath` / `cnn_b_head.dath` |
| exp 查表 | 16 | 1024 | `cnn_lut_exp.dath` |

> 深度都取 2 的幂方便寻址；实际权重数写在括号里，多余位置 `FILL_ALL("NONE")` 不关心。

## 六、六个必须知道的点

1. **权重地址公式**（列主序）：`addr = ky + K*kx + K*K*ci + K*K*CIN*co`
   ——写错一位，整层全错；
2. **patch 顺序与权重同构**：`x_patch[i*9 +: 9]`，`i = ky + 3*kx + 9*ci`，这样 MAC 循环就是简单的 `w[co*27+i]`；
3. **符号扩展**：`.mem` 是 8 位二进制补码，读出后必须按有符号参与运算（本模块用 `reg signed [7:0]` + `wire signed [8:0] xs = {1'b0, xv}`），否则负权重变成 +128 级大正数；
4. **舍入**：MATLAB 用 `round`，硬件算术右移是下取整 → 必须 `+32768` 再 `>>>16`，否则差 1 LSB 就对不上；
5. **累加器位宽**：`|acc| ≤ 127×255×27 + |b_int|`，本模块用 32 位（后续层最多 28 位也够，DSP 48 位余量充足）；
6. **位宽必须逐位对齐**（实际踩过的坑）：TB 里 `patch_flat` 曾写成 `[26*9-1:0]`（234 位），
   而 27 个 tap × 9 位 = **243 位** → 第 26 个 tap 读到高阻 `z`，乘法结果变 `x`，40 项全 FAIL。
   现象是"输出全 x"，定位方法：打印内部信号（`xv/ws/prod/acc`）看哪个先变 x。

## 七、下一步（第 ③ 步：整帧滑窗）

1. 加 **行缓存**（3 通道 × 3 行，或按通道串行复用）+ 3×3 滑窗寄存器阵（与你们 Sobel 行缓存同构）；
2. 在帧首拉高 `start`，逐像素输出 128×72×8，与 `x1_conv1.hex` **整帧逐位比对**；
3. 通过后参数化 Cin/Cout/K/stride/pad，依次打通 conv2/conv3/conv4（stride=2 的输出坐标生成是唯一新知识点）；
4. 再做 head_conv(1×1) + 解码（exp 查表 + 锚框 + 最高分单框），与 `sim/cnn_data/head_real.hex` 对拍。

4. 再做 head_conv(1×1) + 解码（exp 查表 + 锚框 + 最高分单框），与 `sim/cnn_data/head_real.hex` 对拍。

> TD 工程的 `.al` 文件暂不登记本模块——第 ③/④ 步要综合上板时，在 TD 里 **Add Source** 加入
> `cnn_rom.v`、`conv1_pixel.v`（以及后续模块），并**记得加宏 `CNN_TD_ROM`**，让 ROM 走官方 ERAM 原语。

## 八、待办：全部仿真 + 上板验证通过后，切换为"纯 IP"（卸掉包装）

**当前决定（2026-09-20）**：`cnn_rom` 包装**保留到最后**——仿真走行为级 `$readmemh`，综合走官方
`PH1P_LOGIC_ERAM` + `.dath`。等 FPGA 端全部做完、仿真全通过、**且上板验证过 IP 路径**之后，再删掉行为级分支。

**为什么不能现在就删**（实测证据）：
1. 安路原语仿真模型 `E:\Anlogic\TD_6.2.1_Engineer_6.2.168.116\sim_release\ph1p\ph1p_logic_eram.v`
   （657 行）**不含任何 `$readmemh` / `$fopen`** → 仿真时**不加载 `INIT_FILE`**，ROM 读出来是 x/0，无法金标准对拍；
2. 它还实例化 `PH1P_PHY_GSR` 等原语，直接仿真会报
   `Failed to find 'PH1P_PHY_GSR' in hierarchical name` → 需要补齐一串厂商模型（就是工程里记过的"安路 IP 原语仿真失败"）。

**届时切换步骤（约 10 分钟）**：
1. 前置条件：conv1~4 + head + 解码**全部仿真通过**，且已**上板验证** IP 路径正常；
2. `cnn_rom.v`：删掉 `` `ifdef CNN_TD_ROM / `else / `endif ``，只保留 `PH1P_LOGIC_ERAM` 分支；
3. 各模块：删掉 `W_MEM` / `B_MEM` / `INIT_FILE` 参数，只留 `DATH_FILE`；工程里移除 `CNN_TD_ROM` 宏定义；
4. `sim/cnn_data/*.hex`（仿真对拍用）可删，只保留 `mem_dath/*.dath`；
5. 重新综合、上板，用同一张测试图确认检测框与仿真一致（此时"仿真=综合"同一份 RTL，
   但**再也不能在 ModelSim 里验证权重内容**，所以务必在上板后做一次完整功能确认）。

> 备注：切换前的所有验证记录（仿真 PASS）应保留在案，作为切换后回归对比的基准。

