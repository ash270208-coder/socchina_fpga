# matlab/cnn_detector —— 方案 A（int8 小检测器）PC 端脚本骨架

这是 `../../docs/CNN可行性评估.md` 方案 A 的 MATLAB 训练/量化/金标准脚本链：**全程 MATLAB，不依赖 Python**。

> ⚠️ 本骨架由 AI 编写、在你机器上逐步调试过（环境自检、数据解析、训练启动均已通过）。
> 按顺序逐脚本运行（step0→step1→step2→step3→step4）。

## 文件清单

| 文件 | 作用 | 何时跑 |
|---|---|---|
| `step0_check_env.m` | 检查版本与工具箱（脚本） | 第一步 |
| `parse_widerface.m` | WIDER FACE 标注解析（函数，自动质量过滤） | 用 WIDER 时 |
| `step1_prepare_data.m` | 组装训练数据表 → `training_data.mat` | 第二步 |
| `step1b_autolabel.m` | 半自动标框（自动标 + 手动补标合并 → boxes.csv） | 数据准备时（推荐） |
| `step2_train_detector.m` | 训练（全标准层 + 回归目标）→ `detector_net.mat` | 第三步 |
| `fold_bn.m` | BN 折叠进卷积（函数） | step3 调用 |
| `conv2d_float.m` / `conv2d_int.m` | 多通道卷积算子（float / 定点精确） | step3/step4 调用 |
| `step3_quantize_export.m` | int8 量化 + 激活校准 + 导出 `.mem`/LUT/参数头 | 第四步 |
| `decode_boxes.m` | 检测头解码 + 最高分单框（函数） | step4 调用 |
| `step4_golden_forward.m` | 定点金标准前向，与浮点网络对比 | 第五步 |

## 运行顺序

```
step0_check_env        （确认 R2021b+ 与工具箱）
step1_prepare_data     （mode：'A' 自采 / 'B' WIDER / 'AB' 混合）
step2_train_detector   （全标准层训练；先 maxEpochs=5 试跑，再改 30 正式训）
step3_quantize_export  （输出 out/w_*.mem、b_*.mem、lut_*.mem、params_summary.txt）
step4_golden_forward   （test.jpg 或 data/test/ 第一张；首框 IoU > 0.5 = 链路正确）
```

**为什么不用 `yolov2Layers`/`trainYOLOv2ObjectDetector`**：R2024b 的检测头（TransformLayer）反向传播在你机器上崩溃（GPU/CPU 均复现、真实错误被 MATLAB 吞掉）。改为全标准层训练：conv/BN/relu + 预编码回归目标 + `regressionLayer`，路径 100% 可控，且网络与 FPGA 计划完全一致（没有 R2024b 偷偷加的两层 3×3×32 卷积，省 10M MACs）。

## 数据准备（`data/` 目录）—— 把资料按下面规则放进来即可

> 原 `data/README.txt` 已并入本节，不再单独保留一份 README。

**【images/】训练图片**（支持 `.jpg` `.jpeg` `.png` `.bmp`）

- 有人脸的图：同时在 `boxes.csv` 里标注
- 没人脸的背景图（负样本）：直接放进来即可，不用标注（step1 自动当负样本）
- 建议数量：正常脸 100~200 张；涂颜料脸 50~100 张（**核心需求**）；负样本 50~100 张

**【test/】测试图**（不参与训练）

- `step4_golden_forward` 自动取这里第一张做定点前向验证；若 `matlab/cnn_detector/test.jpg` 存在则优先用它

**【boxes.csv】标注文件**

- 每行：`文件名,x,y,w,h`（左上角坐标，像素）；一张图多个框就写多行；第一行表头保留即可（脚本自动跳过）
- 文件名只写 basename（如 `img001.jpg`），不要带路径

```
img001.jpg,120,80,60,70
img001.jpg,300,200,80,95
img002.jpg,150,90,55,62
```

**【标框工具】不用手算坐标**

1. 半自动（推荐）：跑 `step1b_autolabel` —— 内置人脸检测器自动标框写 `boxes.csv`；涂颜料的脸会漏检，脚本末尾会列出漏检名单，只对它们用 `imageLabeler` 手动补框
2. 全手动：MATLAB 命令行输入 `imageLabeler` → 打开图片目录 → 鼠标画矩形框（坐标软件自动记录）→ Export Labels 导出（格式不匹配没关系，贴给 AI 转成 `boxes.csv`）

**【WIDER FACE（可选，用于多样性）】**

- 下载 `wider_face_train_bbx_gt.txt` + `WIDER_train/images`，把路径填进 `step1_prepare_data`
- 选图不用手动挑：`parse_widerface.m` 自动过滤（脸太小/太大、严重模糊、夸张姿态、重度遮挡）
- 推荐最终用 `mode='AB'`：WIDER 提供多样性，自拍提供彩绘脸/负样本/演示环境域匹配

## 与 Verilog 的接口契约（`out/params_summary.txt` 是权威）

**网络**（输入 128×72×3 RGB，uint8 0..255，scale=1；FPGA 端可直接接 vpp 的 RGB888 通路，
或喂灰度并复制三通道——推荐前者）：

```
conv1: 3×3 s1 pad1  3→8   + BN + ReLU    → 128×72×8
conv2: 3×3 s2 pad1  8→16  + BN + ReLU    →  64×36×16
conv3: 3×3 s2 pad1 16→32  + BN + ReLU    →  32×18×32
conv4: 3×3 s1 pad1 32→32  + BN + ReLU    →  32×18×32
head : 1×1       32→15（3 锚 × [to tx ty tw th]）→ 32×18×15
```

**定点公式**（Verilog 必须照抄，金标准按同一公式所以逐位一致）：

```
acc     = Σ(Wq·xq) + b_int          （Wq=int8, xq=uint8, b_int=int32，累加器按层宽规划）
xq_next = clamp(round(acc · mOut), 0, 255)      // conv1..4，mOut = sW·sIn/sOut
head    = acc · (sW·sIn)            // 检测头输出还原到实域，送 LUT 解码
```

**解码**（`decode_boxes.m` 与 Verilog 同一契约，每锚通道顺序 [to tx ty tw th]）：

```
score = clamp(p1, 0, 1)                          // 回归训练目标即 0/1，原始输出即分数（不套 sigmoid）
tx = clamp(p2, 0, 1),  ty = clamp(p3, 0, 1)     // 直接回归的格内偏移
w = anchorW · exp(p4), h = anchorH · exp(p5)
cx = (gx + tx) · (128/32), cy = (gy + ty) · (72/18)
框 = [cx-w/2, cy-h/2, w, h]
```

- exp 用 `lut_exp.mem`（1024 项 ×16bit Q11，输入 x∈[-4,4)，`idx = round((x+4)*128)`）；
- `lut_sigmoid.mem` 仍导出但当前契约不用（分数直接取原始值截断），保留备用；
- 后处理：score ≥ 0.15（回归对象分偏低，阈值可按实测调）→ 每帧只留最高分 1 框 → 板级叠加 9.16 的时域确认（现成）。

**`.mem` 格式**（`$readmemh` 直接可吃）：

- `w_convN.mem` / `w_head.mem`：int8 二进制补码 hex，每行一个值，顺序 = **列主序 [ky kx cin cout]**（即 MATLAB `weights(:)`，ky 最快变）；
- `b_convN.mem` / `b_head.mem`：int32 二进制补码 hex，顺序 [cout]；
- 各层 stride/pad/sW/sIn/sOut/mOut 见 `params_summary.txt`。

## 已知限制与后续

- `step3` 用手动对称 int8 权重 + 激活校准（比 `dlquantizer` 更透明可控）；金标准的 `round` 规则要与 Verilog 一致（建议硬件也四舍五入）。
- 正负样本不平衡用加权损失 + ignore 区域解决：`yoloLossLayer.m`（默认 λobj=5 / λnoobj=0.5 / λcoord=5）；锚框由 step2 按数据 k-means 自动估计；映射到"框画错位置"的改进见 step2 头注释。分数用原始值截断（不套 sigmoid）。
- 训练时 MATLAB 会打印 loss 曲线；3000 张图、30 epochs 在 CPU 上约数十分钟~数小时。
- 下一步（阶段 2~4）：写 Verilog 卷积引擎时，用 `step4` 对同一张测试图保存的逐层输出做 ModelSim 金标准对照——把 `x`（每层量化后激活）dump 成 `.txt` 即可。
