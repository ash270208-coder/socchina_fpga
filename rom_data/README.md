# ROM / 查表数据文件汇总（rom_data）

> 这些是"需要预置进 ROM / 查表结构"的数据文件。原来分散在 6 个地方
> （`matlab/cnn_detector/out/`、`sim/cnn_data/`、`td_project/`、`td_project/al_ip/*/`、
> `user_source/hdl_source/cnn/mem_dath/`、`LBP/`），这里集中一份**副本**方便查看。
>
> ⚠️ **副本不参与综合 / 仿真**。TD 的 ROM IP 引用的是原始路径，
> **要改表内容必须改原文件**（或用 MATLAB 重新导出），改这里的副本没有效果。

---

## 1. CNN 权重 / 偏置 / 激活表 —— `cnn/mem/`（板 B）

文本 hex 格式，**每行一个值**；来源：`matlab/cnn_detector/out/`（由 `export_fpga_consts.m` 生成）。

| 文件 | 字节 | 行数 | 内容 | 使用者 |
|---|---|---|---|---|
| `w_conv1.mem` | 648 | 216 | conv1 权重 8×3×3×3（int8，每行 2 位 hex） | `conv1_frame` + IP `cnn_rom_w1` |
| `b_conv1.mem` | 72 | 8 | conv1 偏置（int32，每行 8 位 hex） | `conv1_frame` |
| `w_conv2.mem` | 3 456 | 1 152 | conv2 权重 16×8×3×3 | `cnn_rom_w2` |
| `b_conv2.mem` | 144 | 16 | conv2 偏置 | `conv2_frame` |
| `w_conv3.mem` | 13 824 | 4 608 | conv3 权重 32×16×3×3 | `cnn_rom_w3` |
| `b_conv3.mem` | 288 | 32 | conv3 偏置 | `conv3_frame` |
| `w_conv4.mem` | 27 648 | 9 216 | conv4 权重 32×32×3×3 | `cnn_rom_w4` |
| `b_conv4.mem` | 288 | 32 | conv4 偏置 | `conv4_frame` |
| `w_head.mem` | 1 440 | 480 | head 权重 15×32×1×1 | `cnn_rom_wh` |
| `b_head.mem` | 135 | 15 | head 偏置 | `head_frame` |
| `lut_exp.mem` | 5 120 | 1 024 | exp() 近似表（16 bit/项），框解码用 | IP `cnn_rom_exp` |
| `lut_sigmoid.mem` | 3 072 | 1 024 | sigmoid 表（8 bit/项） | **当前 RTL 未映射**（al_ip 里只有 `cnn_rom_exp`），训练/评估留档 |

**打包变体**（每行 16 位 hex = 一个 64 bit ROM 字，按 ROM 位宽打包）：

| 文件 | 字节 | 行数 |
|---|---|---|
| `w_conv1_packed.mem` | 459 | 27 |
| `w_conv2_packed.mem` | 2 448 | 144 |
| `w_conv3_packed.mem` | 9 792 | 576 |
| `w_conv4_packed.mem` | 19 584 | 1 152 |
| `w_head_packed.mem` | 1 088 | 64 |

## 2. TD ROM IP 实际加载的初始化文件 —— `cnn/dath/`（板 B）

来源：`td_project/al_ip/cnn_rom_*/`。**这才是综合时真正被烧进 ROM 的文件**（`.mem` 是给人看的文本，`.dath` 是 IP 用的打包格式）。

| 文件 | 字节 | 对应 IP |
|---|---|---|
| `cnn_w_conv1_packed.dath` | 486 | `cnn_rom_w1` |
| `cnn_w_conv2_packed.dath` | 2 592 | `cnn_rom_w2` |
| `cnn_w_conv3_packed.dath` | 10 368 | `cnn_rom_w3` |
| `cnn_w_conv4_packed.dath` | 20 736 | `cnn_rom_w4` |
| `cnn_w_head_packed.dath` | 1 152 | `cnn_rom_wh` |
| `cnn_lut_exp.dath` | 6 144 | `cnn_rom_exp` |

## 3. LBP 级联表 —— `lbp/`（板 A 原人脸检测，现已解绑，仅留档）

| 文件 | 字节 | 行数 | 内容 | 使用者 |
|---|---|---|---|---|
| `weak_lut.hex` | 12 093 | 139 | LBP 弱分类器查表（每行 1 索引 + 10 个 16 bit 值） | IP `rom_weak_lut` |
| `feature_rects.hex` | 1 360 | 136 | 矩形特征描述（每行 4×8 bit） | IP `rom_feature_rects` |
| `stage_threshold.hex` | 120 | 20 | 每级级联阈值 | IP `rom_stage_thresh` |
| `weak_lut.dath` / `feature_rects.dath` / `stage_threshold.dath` | 19 200 / 2 304 / 160 | — | 上述三表的 IP 打包版 | 同上（来源 `td_project/`） |

`.hex` 文本源在工程根目录 `LBP/`。

## 4. 仿真黄金数据 —— `golden/`（**不是 ROM**，供 ModelSim 逐层比对）

来源：`sim/cnn_data/`。每行一个值。

| 文件 | 字节 | 行数 | 张量含义 |
|---|---|---|---|
| `x0_input.hex` | 110 592 | 27 648 | 网络输入 128×72×3 |
| `x1_conv1.hex` | 294 912 | 73 728 | conv1 输出 8×72×128 |
| `x2_conv2.hex` | 147 456 | 36 864 | conv2 输出 16×36×64 |
| `x3_conv3.hex` | 73 728 | 18 432 | conv3 输出 32×18×32 |
| `x4_conv4.hex` | 73 728 | 18 432 | conv4 输出 32×18×32 |
| `head_real.hex` | 86 400 | — | head 层浮点参考 |

## 5. 已排除：官方模板残留的 DSI 数据文件（**无人使用**）

`user_source/hdl_source/dsi_tx_packet/` 里只有两个文件：`config_data.mif`（3 338 B，
`DEPTH=1024 / WIDTH=8`）及其生成物 `config_data.mif.dat`（10 240 B）。**已逐项核查确认没有任何
模块使用它**，因此不放进本汇总：

| 核查项 | 结果 |
|---|---|
| 目录里有 `.v` 模块吗 | ❌ 没有，只有 `.mif` 和数据文件 |
| 本工程 `.al` 收录了吗 | ❌ 没有（93 个源文件里 `mif` / `config_data` / `.dat` 命中 0 条） |
| 全 depot 里有任何工程例化它吗 | ❌ 没有 |
| 本工程综合资源占用 | `#mipi_tx 0 out of 2 (0.00%)` —— 未使用 MIPI/DSI 发送通道 |
| 本工程输出接口 | HDMI/TMDS（`pin.adc` 只有 4 路 TMDS + 屏背光 PWM，无 DSI 引脚） |
| 其他官方例程 | `lab_ex1` / `lab_ex2` / `lab_ex3` 都带这个目录，**连官方自己的 `.al` 也没收录** |

结论：这是**安路官方例程模板**为"MIPI-DSI 屏"版本预留的数据文件，与本工程（HDMI 输出）无关，
属死文件。

**已处理（"哪里来的回哪里去"）**：整个 `dsi_tx_packet/` 目录已从本工程删除。
删除前先与官方模板原件做过逐字节比对，两个文件 MD5 完全一致
（`config_data.mif` = 33A275BC…，`config_data.mif.dat` = E95CE63B…），
原件在 `D:\TD_project\anlogic_example\lab_ex1_mipi_hdmi\...\user_source\hdl_source\dsi_tx_packet\`
完好无损。如需恢复：`git checkout <删除前提交> -- <工程路径>/user_source/hdl_source/dsi_tx_packet`。

## 6. RTL 内嵌的查表（不是独立文件，改内容要改 `.v`）

| RTL 文件 | 表内容 | 规模 | 说明 |
|---|---|---|---|
| `gamma_lut.v` | 显示 gamma=2.2 曲线 + 固定黑电平 | 256 项 | 板 A 图像处理链 |
| `osd_char_lib.v` | 8×8 字库放大到 32×40 窗口 | 16 个字模 | 板 A 文字 OSD |
| `anlogic_logo_rom.v` | 安路 logo 点阵，**6 387 条组合 `case` 条目**（298 KB 源码） | 160×160，25 bit/像素 | 板 A OSD —— **当前时序瓶颈的元凶**，见 `../docs/BOARD_SPLIT.md` 与 `../docs/TIMING_OSD_ANALYSIS.md` |
| `osd_overlay.v` 内 `F_cn16_row` | "安路" 16×16 汉字点阵 | 2 字 × 16 行 | 板 A OSD |

## 7. 重新生成方法

- **CNN 全部表**：MATLAB 运行 `matlab/cnn_detector/export_fpga_consts.m`
  （读 `out/net_params.mat` → 写 `out/*.mem`、`out/cnn_params.vh` Q32 常量）
- **LBP 表**：`LBP/` 下的训练/导出脚本
- **TD ROM IP 的 `.dath`**：改完 `.mem` 后在 TD 的 IP 界面重新加载初始化文件并重新生成 IP
