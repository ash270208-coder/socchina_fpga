# =====================================================================
#  Step A: 板 A 解绑人脸检测 + 板 A/B 文件分类归档
#  用法: powershell -ExecutionPolicy Bypass -File board_split_stepA.ps1
#  特性: 只改 vpp_top.v / design_top_wrapper.v 的接线; 源文件一律不删除
#        所有删除项都可用 git checkout 恢复
# =====================================================================
$ErrorActionPreference = 'Stop'

$R   = 'D:\TD_project\lab_ex1_mipi_hdmi_SC500_720P+vpp'
$P   = Join-Path $R 'lab_ex1_mipi_hdmi_SC500_720P+vpp\lab_ex1_mipi_hdmi+vpp'
$H   = Join-Path $P 'user_source\hdl_source'
$enc = New-Object System.Text.UTF8Encoding($false)

Write-Host '============================================================='
Write-Host ' Step A-1: vpp_top.v 解绑 face_track_top'
Write-Host '============================================================='

$p1 = Join-Path $H 'vpp_top.v'
$L1 = [System.IO.File]::ReadAllLines($p1)
$o1 = New-Object System.Collections.Generic.List[string]
$inject = @(
'',
'    // =========================================================================',
'    // 人脸检测已移除（板 A 只做图像处理）：MUX 选中的显示画面直通输出',
'    //   原 face_track_top（LBP 级联检测 + 画框 + 准星）已从本工程解绑，',
'    //   相关源文件仍保留在磁盘上作为归档，分类见工程根目录 BOARD_SPLIT.md。',
'    //   如需恢复人脸检测：git checkout b21e965 -- user_source/hdl_source/vpp_top.v',
'    // =========================================================================',
'    assign O_tdata  = mux_tdata;',
'    assign O_tlast  = mux_tlast;',
'    assign O_tuser  = mux_tuser;',
'    assign O_tvalid = mux_tvalid;'
)
$skip = $false
$nParam = 0
foreach ($ln in $L1) {
    if ($ln -match 'parameter\s+MIN_FACE_AREA') {
        $o1[$o1.Count-1] = ($o1[$o1.Count-1] -replace ',\s*$','')
        $nParam++
        continue
    }
    if ($ln -match 'face_track_top\s*#') { $skip = $true }
    if ($skip) {
        if ($ln -match '\.O_face_valid') {
            $skip = $false
            foreach ($x in $inject) { $o1.Add($x) }
        }
        continue
    }
    $o1.Add($ln)
}
if ($skip)      { throw 'vpp_top.v: face_track_top 例化块未找到结束标记 (.O_face_valid)' }
if ($nParam -ne 1) { throw "vpp_top.v: MIN_FACE_AREA 参数行匹配数 = $nParam (期望 1)" }

# 端口声明删除 (O_face_x / O_face_y / O_face_valid)
$o1b = New-Object System.Collections.Generic.List[string]
$nPort = 0
foreach ($ln in $o1) {
    if ($ln -match '^\s*output\s+\[\s*11\s*:\s*0\s*\]\s+O_face_[xy]' -or $ln -match '^\s*output\s+O_face_valid') {
        $nPort++
        continue
    }
    if ($ln -match '^\s*//\s*输出给云台控制模块的信号') { continue }
    $o1b.Add($ln)
}
if ($nPort -gt 3) { throw "vpp_top.v: 端口删除数 = $nPort (期望 3)" }
[System.IO.File]::WriteAllLines($p1, $o1b, $enc)
Write-Host ("  OK: 删除端口 3 个, 参数 1 个, 例化块 1 个 -> 直通 assign")

Write-Host '============================================================='
Write-Host ' Step A-2: design_top_wrapper.v 移除 face 端口连接'
Write-Host '============================================================='

$p2 = Join-Path $H 'design_top_wrapper.v'
$L2 = [System.IO.File]::ReadAllLines($p2)
$o2 = New-Object System.Collections.Generic.List[string]
$nW = 0
foreach ($ln in $L2) {
    if ($ln -match '\.MIN_FACE_AREA') {
        $o2[$o2.Count-1] = ($o2[$o2.Count-1] -replace ',\s*$','')
        $nW++
        continue
    }
    if ($ln -match '\.O_face_(x|y|valid)\s*\(') {
        if ($ln -match '\.O_face_x') { $o2[$o2.Count-1] = ($o2[$o2.Count-1] -replace ',\s*$','') }
        $nW++
        continue
    }
    if ($ln -match '^\s*//' -and $ln -match 'VPP' -and $ln -match '\+\s*[^\x00-\x7F]') {
        $o2.Add(($ln -replace '\s*\+\s*[^\x00-\x7F].*$',''))
        continue
    }
    $o2.Add($ln)
}
if ($nW -ne 4) { throw "design_top_wrapper.v: face 相关行删除数 = $nW (期望 4)" }
[System.IO.File]::WriteAllLines($p2, $o2, $enc)
Write-Host '  OK: 删除 .MIN_FACE_AREA + .O_face_x/y/valid 连接'

Write-Host '============================================================='
Write-Host ' Step A-3: 建立板 B 自包含归档包 board_b_cnn/'
Write-Host '============================================================='

$B = Join-Path $R 'board_b_cnn'
foreach ($d in @('', 'hdl', 'sim', 'ip', 'mem', 'matlab', 'docs')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $B $d) | Out-Null
}

# HDL: CNN 全套
Copy-Item (Join-Path $H 'cnn') (Join-Path $B 'hdl\cnn') -Recurse -Force

# 仿真: CNN testbench + golden 数据
New-Item -ItemType Directory -Force -Path (Join-Path $B 'sim') | Out-Null
Get-ChildItem (Join-Path $R 'sim') -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match 'cnn' -or $_.Name -match '^conv\d' -or $_.Name -match '^head_' } |
    Copy-Item -Destination (Join-Path $B 'sim') -Force
if (Test-Path (Join-Path $R 'sim\cnn_data')) {
    Copy-Item (Join-Path $R 'sim\cnn_data') (Join-Path $B 'sim\cnn_data') -Recurse -Force
}

# IP: CNN ROM/RAM 核 + 通用 RAM 核
Get-ChildItem (Join-Path $P 'td_project\al_ip') -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like 'cnn_*' -or $_.Name -in @('ram_2port','ram_accumulate') } |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $B 'ip') -Recurse -Force }

# 权重/激活 mem
Get-ChildItem (Join-Path $P 'td_project') -File -Filter '*.mem' -ErrorAction SilentlyContinue |
    Copy-Item -Destination (Join-Path $B 'mem') -Force

# MATLAB: 训练脚本 + 权重 + 数据集 + golden
if (Test-Path (Join-Path $R 'matlab\cnn_detector')) {
    Copy-Item (Join-Path $R 'matlab\cnn_detector') (Join-Path $B 'matlab\cnn_detector') -Recurse -Force
}

# 文档
Get-ChildItem $R -File -Filter '*.md' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match 'CNN' } |
    Copy-Item -Destination (Join-Path $B 'docs') -Force
Get-ChildItem $R -File -Filter 'FPGA_CNN*.md' -ErrorAction SilentlyContinue |
    Copy-Item -Destination (Join-Path $B 'docs') -Force

$sz = (Get-ChildItem $B -Recurse -File | Measure-Object -Property Length -Sum).Sum
$fc = (Get-ChildItem $B -Recurse -File).Count
Write-Host ("  OK: board_b_cnn/ = {0} 个文件, {1:N1} MB" -f $fc, ($sz/1MB))

Write-Host '============================================================='
Write-Host ' Step A-4: 生成 BOARD_SPLIT.md (板 A/B 文件分类)'
Write-Host '============================================================='

$split = @'
# 双板分工方案 / Board Split

> 生成时间：Step A 执行时自动生成
> 工程根目录：`lab_ex1_mipi_hdmi_SC500_720P+vpp/lab_ex1_mipi_hdmi+vpp`
> 板 B 归档包：`board_b_cnn/`（本文件同级目录）

---

## 1. 分工总览

| | 板 A（本工程） | 板 B（第二块板，同款 PH1P35MDG324） |
|---|---|---|
| 定位 | 图像处理展示平台（保底作品） | 人脸检测（CNN，锦上添花） |
| 视频源 | 板载 SC500（MIPI CSI-2 2-lane） | 板 A 降采样后经板间链路送的 128×72 RGB |
| 输出 | HDMI 显示器（5 种处理模式） | 检测框（回传板 A 叠加，或本地显示） |
| 人脸检测 | **已全部移除** | 全部在这里 |
| 状态 | Step A 完成 | Step B/C 待做 |

设计原则：**任一块板单独都能交付**。板 A 不依赖板 B，板 B 失败不影响板 A 的作品完整性。

---

## 2. 板 A 保留内容（图像处理主线）

数据流：

```
SC500(MIPI) -> MIPI DPHY RX -> CSI/RAW10 解包 -> ISP(demosaic + AWB)
   -> DDR2 帧缓存 -> vpp_top 图像处理(5 模式) -> osd_overlay 文字 -> hdmi_tx -> 显示器
```

| 功能 | 模块 | 说明 |
|---|---|---|
| MIPI 接收 | `mipi_dphy_rx/*`、`isp/csi_unpacket_2lane.v`、`isp/raw10_unpacket_2lane.v` | 官方 IP，勿动 |
| ISP | `isp/isp_top.v` + `demosaic_4x_2_0/*` + `awb.v` | 去马赛克 + 自动白平衡 |
| 帧缓存 | `ph1p35_ddr/*`、`video_in.v`、`video_out.v`、`mc_to_user_interface.v` | DDR2 跨时钟域 |
| 自动曝光 | `uiisp_beta/ae_set.v`、`ae_auto.v`、`brightness_stats.v` | 按键 0/1 调节 |
| 伽马校正 | `gamma_lut.v` | 全工程只做一次 |
| 模式 0 原图 | — | 伽马域彩色输出 |
| 模式 1 灰度 | RGB2Y 现算 `{gray,gray,gray}` | `(R+2G+B)/4` |
| 模式 2 直方图均衡 | `histogram_equ.v` | 彩色输出 |
| 模式 3 Sobel 边缘 | `Sobel_edge.v`、`Sobel_edge_detection_top.v`、`Bit_Erosion_Detector.v`、`Bit_Dilation_Detector.v` | 阈值 60 |
| 模式 4 卡通化 | `cartoon_top.v`、`Color_Quantize.v`、`Cartoon_Blend.v` | 量化 + 融合 |
| 降噪 | `chroma_nr.v` | 色度降噪 |
| 文字 OSD | `osd_overlay.v`、`osd_char_lib.v`、`anlogic_logo_rom.v`、`delay_osd.v` | 显示当前模式 |
| HDMI 输出 | `hdmi_tx.v`、`hdmi_mixer.v`、`hdmi_phy_warpper.v`、`uivtc/*` | TMDS |

按键映射（`design_top_wrapper.v`）：

- `I_button[0]/[1]` → 自动曝光 减 / 增
- `I_button[2]/[3]` → vpp 显示模式切换（`vpp_btn = {I_button[3], I_button[2]}`）

---

## 3. 板 A 已移除内容（人脸检测）

| 文件 | 角色 | 处理 |
|---|---|---|
| `face_track_top.v` | 检测顶层（降采样→滤波→积分图→LBP→画框） | 保留文件，不再例化 |
| `lbp_detector_engine.v` | LBP 级联检测引擎 | 保留文件，不再例化 |
| `integral_image.v` | 积分图 | 保留文件，不再例化 |
| `lp_filter_3x3.v` | 低分辨率 3x3 均值降噪 | 保留文件，不再例化 |
| `downscaler.v` | ÷6 灰度降采样（1280×720→213×120） | 保留文件，不再例化 |
| `osd_box_drawer.v` | 人脸框绘制 | 保留文件，不再例化 |
| LBP ROM IP：`rom_weak_lut` / `rom_feature_rects` / `rom_stage_thresh` / `frame_integral_bram` | LBP 查表/矩形/阈值 | 保留 IP，不再例化 |
| `hdl_source/cnn/*`（14 个 .v） | CNN 检测链 | 保留文件，不再例化（板 B 资产） |
| CNN IP：`al_ip/cnn_*` | ROM/RAM 核 | 保留 IP，不再例化 |

代码改动（Step A 实际改的两个文件）：

1. `vpp_top.v`
   - 删除端口 `O_face_x[11:0]` / `O_face_y[11:0]` / `O_face_valid`
   - 删除参数 `MIN_FACE_AREA`
   - 删除 `face_track_top` 例化，改为 4 条直通 `assign`（`mux_*` → `O_t*`）
2. `design_top_wrapper.v`
   - 删除 `vpp_top` 例化中的 `MIN_FACE_AREA` 参数覆盖与 `.O_face_x/y/valid` 空连接
   - 更新章节注释

> 注意：`.al` 工程文件的源文件清单**未改动**。未被例化的模块不参与综合（自动剪除），因此不占任何资源；这样可避免手工改 TD 工程 XML 的风险。若需要一份"干净清单"，可在 Step B 时用 TD 图形界面移除后重新综合验证。

---

## 4. 板 B 资产（已归档到 `board_b_cnn/`）

| 包内路径 | 来源 | 内容 |
|---|---|---|
| `hdl/cnn/` | `user_source/hdl_source/cnn/` | `cnn_top.v`、`cnn_ds10.v`、`cnn_ram.v`、`cnn_buf_ip.v`、`cnn_rom_ip.v`、`cnn_params.vh`、`conv_frame.v`、`conv1..4_frame.v`、`head_frame.v`、`conv1_pixel.v`、`cnn_head_dec.v`、`mem_dath/cnn_*.dath` |
| `sim/` | 根目录 `sim/` | CNN testbench（`cnn_top_tb`、`conv*_tb`、`head*_tb`、`cnn_ds10_tb`、`face_track_cnn_tb`）+ `cnn_data/` golden |
| `ip/` | `td_project/al_ip/` | `cnn_rom_w1..w4`、`cnn_rom_wh`、`cnn_rom_exp`、`cnn_buf_a/b/in`、`ram_2port`、`ram_accumulate` |
| `mem/` | `td_project/*.mem` | `w_conv1..4.mem`、`b_conv1..4.mem`、`w_head.mem`、`b_head.mem`、`lut_exp.mem`、`lut_sigmoid.mem` |
| `matlab/cnn_detector/` | `matlab/cnn_detector/` | 训练脚本 `step0..step5*.m`、`detector_net.mat`、`training_data.mat`、`snapshots/v1_80ep/`、`out/golden/`、`export_fpga_consts.m`、`out/cnn_params.vh` |
| `docs/` | 工程根目录 | CNN 训练/实现方案文档 |

网络规模（方案 A）：输入 128×72×3 RGB → conv1 3→8 s1 → conv2 8→16 s2 → conv3 16→32 s2 → conv4 32→32 s1 → head 1×1 32→15 → decode，约 12.9 M MAC/帧，15.5K 参数。

---

## 5. 板 B 待办（Step B / Step C）

### Step B：板 B 单板出框
1. 新建精简顶层：`MIPI → ISP(demosaic) → 降采样/取帧 → cnn_top → 结果输出`，去掉 DDR/HDMI/图形增强等与检测无关的负载（腾出资源预算）
2. 资源收敛（当前单板实测：LUT 52.1K / slice 41.1K（限 21.2K）/ ERAM 115（限 108）/ DSP 51（限 40））：
   - 权重 ROM 改双口读 → ERAM 115 → 107
   - 帧缓存/引擎进一步复用（`cnn_ram` 已做一轮，dram-lut 已降到 1832）
   - 必要时降输入分辨率（128×72 → 96×54）或减通道，用保留的训练脚本重训
3. ModelSim 逐层对齐 MATLAB golden（现有 testbench 与 `sim/cnn_data/` 可直接复用）

### Step C：板间链路
- 板 A 侧：在 vpp 输出后取 128×72 RGB 帧（每帧 27,648 B），10 fps 只需约 276 KB/s ≈ 2.2 Mbps
- 链路选型结论：本工程及 `D:\TD_project` 下所有安路例程中**没有任何以太网参考设计**（`rgmii`/`mdio`/`eth_phy` 零命中），板子是否板载 RJ45+PHY 需查原理图
  - 有 PHY：需自行实现 RGMII + 精简 MAC（自定义 EtherType 裸帧，不做 TCP/IP 栈），约 3~7 天
  - 无 PHY：可外挂 SPI 以太网模块（W5500），FPGA 侧只需 SPI master，约 1~2 天
  - 最省：扩展 IO 直连（并口/SPI），当天可通
- 建议：先用最简并口跑通，CNN 稳定后再决定是否加以太网作为展示亮点

---

## 6. 回退与恢复

```powershell
# 查看历史
git log --oneline

# 恢复板 A 到"带人脸检测"的版本
git checkout 66de940 -- lab_ex1_mipi_hdmi_SC500_720P+vpp/lab_ex1_mipi_hdmi+vpp/user_source/hdl_source/vpp_top.v
git checkout 66de940 -- lab_ex1_mipi_hdmi_SC500_720P+vpp/lab_ex1_mipi_hdmi+vpp/user_source/hdl_source/design_top_wrapper.v

# 恢复 CNN 版本（板 B 参考）
git checkout b21e965 -- lab_ex1_mipi_hdmi_SC500_720P+vpp/lab_ex1_mipi_hdmi+vpp/user_source/hdl_source/
```

关键提交：

| 提交 | 内容 |
|---|---|
| `799b02c` | 加入自动曝光 |
| `2bd17d3` | 加入 CNN 之前的基线 |
| `b21e965` | CNN 全链路归档（板 B 起点） |
| `66de940` | 恢复 LBP + 自动曝光 |

---

## 7. 资产保护

- 训练数据、网络权重、golden 输出**一律未删除**，且已复制到 `board_b_cnn/`
- 建议再往工程外的移动盘/网盘备份一份 `matlab/cnn_detector/` 与 `board_b_cnn/`
'@
[System.IO.File]::WriteAllText((Join-Path $R 'BOARD_SPLIT.md'), $split, $enc)
Write-Host '  OK: BOARD_SPLIT.md'

Write-Host '============================================================='
Write-Host ' Step A-5: 验证 (残留引用检查 + ModelSim 语法检查)'
Write-Host '============================================================='

Write-Host '--- vpp_top.v 中 face 残留 ---'
$r1 = Select-String -Path $p1 -Pattern 'face_track|O_face'
if ($r1) { $r1 | ForEach-Object { "  $($_.LineNumber): $($_.Line)" } } else { Write-Host '  (无, 干净)' }

Write-Host '--- design_top_wrapper.v 中 face 残留 ---'
$r2 = Select-String -Path $p2 -Pattern 'face_track|O_face|MIN_FACE'
if ($r2) { $r2 | ForEach-Object { "  $($_.LineNumber): $($_.Line)" } } else { Write-Host '  (无, 干净)' }

Write-Host '--- vpp_top.v 例化检查 (应仍有 MUX 直通 assign) ---'
Select-String -Path $p1 -Pattern 'assign O_t(data|last|user|valid)\s*=\s*mux_' |
    ForEach-Object { "  $($_.LineNumber): $($_.Line.Trim())" }

Write-Host '--- ModelSim vlog 语法检查 ---'
$vlog = 'E:\Modelsim\win64\vlog.exe'
if (Test-Path $vlog) {
    Push-Location $R
    try {
        & $vlog -quiet -work work_lbp (Join-Path $H 'vpp_top.v') 2>&1 |
            Select-String -Pattern 'Error|error' | Select-Object -First 10 |
            ForEach-Object { "  $_" }
        Write-Host ("  vlog 退出码: $LASTEXITCODE (0=无语法错误)")
    } finally { Pop-Location }
} else { Write-Host '  跳过: 未找到 vlog.exe' }

Write-Host '============================================================='
Write-Host ' Step A 完成'
Write-Host '============================================================='
