# 纯 FPGA 部署 CNN · 学习与准备路线（MATLAB 优先版）

> 目标：从"对 FPGA 部署 CNN 了解很少"到把**方案 A（int8 整帧锚框检测器，主推）或方案 B′（全图滑窗二值级联，备选）**跑上 PH1P35MDG324，约 3~4 周。
> 配套文档：`CNN可行性评估.md`（为什么要这么做、资源账、A/B′ 细节）。
> 四条原则：
> 1. **先 PC 后硬件**——每一层硬件逻辑都有 MATLAB 端"金标准"对照，仿真不靠猜。
> 2. **每一步都有可验证的交付物**——看不到输出就不算学会。
> 3. **复用现有技能**——你们的 Sobel 行缓存、BRAM 乒乓、ModelSim+MATLAB 对照仿真流程，就是 CNN 加速器 70% 的地基。
> 4. **PC 端全程 MATLAB**——不引入 Python（如需，Python 只是可选的平行项，不是必要条件）。

---

## 〇、先建立心智模型：FPGA"部署 CNN"到底在做什么

**分工**：PC（MATLAB）负责训练（浮点、梯度、损失），FPGA 只跑**前向推理**（定点/二值、无梯度）。所谓"部署"就是三件事：

```
① 训练好的网络 → 量化/二值化 → 导出成一张张权重表（FPGA 眼里的 ROM 初始化文件）
② 写一个数据流硬件：特征图缓冲 + 滑窗乘累加 + 激活 + 控制器 FSM
③ 硬件输出与 PC 端 MATLAB 定点金标准逐位对齐（这就是仿真的意义）
```

**数据流五要素**（任何 CNN 加速器论文/工程都是这五样）：

| 要素 | 是什么 | 你们已有的对应经验 |
|---|---|---|
| 行缓存（line buffer） | 3×3 滑窗的数据来源 | Sobel 的行缓存，一模一样 |
| 权重 ROM | 卷积核参数表 | weak_lut ROM（LBP 查表） |
| MAC 阵列 | 乘累加 | 直方图累加、积分图 |
| 激活函数 | ReLU / sign / maxpool | 阈值比较、腐蚀膨胀的 min/max |
| 控制器 FSM | 逐层调度、乒乓切换 | lbp_detector_engine 的扫描状态机 |

**术语地图**（读资料时对照）：

- CNN 基础：卷积/池化/批归一化（BN）/全连接；**BN 在部署前必须"折叠"进权重**（变成乘一个数加一个数）。
- 量化：QAT（量化感知训练）/ PTQ（训练后量化）；int8 / int4 / 二值（±1）。FPGA 上 int8 走 DSP，二值走 LUT。
- 加速器：数据流（权重固定/输出固定/行缓存流式）、乒乓缓冲、roofline（算力墙 vs 带宽墙）。
- 检测后端：锚框、NMS、时域确认——方案 A 需要锚框解码；方案 B′ 用分类器打分，不需要锚框。

---

## 一、阶段 0（2~3 天）：看懂一个与你们同量级的最小工程

**目标**：把"数据流五要素"落到一个真实代码上。

1. 通读 [cnn_chip](https://github.com/123-code/cnn_chip)：Tang Nano 20K（高云小 FPGA，规模和 PH1P35 同量级）上的 **Verilog INT8 CNN 加速器**，流式 MAC 阵列 + 全片上 MNIST 推理。**这是全网最适合你们起点的最小完整工程。**
2. 对照读入门文章：[如何用 FPGA 加速卷积神经网络（CNN）](https://cloud.tencent.cn/developer/article/1059706)、[FPGA 加速器学习路线图（CSDN）](https://blog.csdn.net/weixin_30907935/article/details/97218270)。
3. 泛读 [FINN 的 README 与架构图](https://github.com/Xilinx/finn)（不用装，只看图）：理解"流式 + 乒乓 + 权重 ROM"长什么样。

**交付物**：一页纸画出"你们所选方案（A 或 B′）的数据通路"——从降采样灰度图 → 行缓存 → 卷积/二值卷积 → 激活 → 解码/打分 → 判决 → 画框，标出每块在哪个模块里实现。**画不出来 = 没看懂，回炉。**

---

## 二、阶段 1（3~5 天）：PC 端 MATLAB 训练闭环（最大技能缺口，务必先过）

**目标**：训练 → 量化 → 导出权重表的完整脚本链。这是"FPGA 部署"里和硬件无关、但决定成败的一半。

**环境检查**：MATLAB **R2021b 或更新**；确认 license 含：Deep Learning Toolbox、Computer Vision Toolbox、Fixed-Point Designer、Image Processing Toolbox。

| 子任务 | 内容 | MATLAB 对应 |
|---|---|---|
| 1.1 | 数据准备：WIDER FACE 标注解析（`textscan`）+ 自采实拍（**含彩绘脸**）切正负样本 | `imageDatastore` |
| 1.2（练手） | 训练 24×24 灰度分类器，跑通全流程 | `trainNetwork` |
| 1.3（关键） | **手写 MATLAB 前向推理**（双层循环 conv/pool/FC），与 `trainNetwork` 输出逐位对齐 | 纯 MATLAB 脚本 |
| 1.4 | 按所选路线训练：**A** → `trainNetwork` + 标准卷积网络 + 预编码回归目标 + `regressionLayer`（骨架已就位：`matlab/cnn_detector/step2`；R2024b 的 YOLOv2 检测头反向有崩溃 bug，故不用 trainYOLOv2）；**B′** → 自定义训练循环 + sign 层 + STE（`defineBackward`）训 16×16/32×32 二值分类器 | 见各函数文档 |
| 1.5 | 量化：**A** → `dlquantizer`（yolov2 支持 int8；版本不支持则手动 `fi`）；**B′** → 二值化即 sign 取阈值 | `dlquantizer` / `fi` |
| 1.6 | 导出：遍历各层 `Weights` → 写 `.mem`（`$readmemh` 格式） | `fopen/fprintf` |

**交付物**：`export_weights.m` + **金标准脚本**（`fi` 定点前向，与你们 .mlx 对照流程同源）。**没有它不准进入阶段 2。**
> ✅ 脚本骨架已就位：`matlab/cnn_detector/`（step0 环境自检 → step1 数据 → step2 训练 → step3 量化导出 → step4 金标准，均为脚本可直接 Run），
> 方案 A 采用**手动 int8 对称量化 + 激活校准**（比 dlquantizer 更透明可控，dlquantizer 可作交叉验证）；
> 运行说明与 Verilog 接口契约见该目录 README.md。

**卡点提示**：`dlquantizer` 对 yolov2 的支持以你的 MATLAB 版本为准；不支持就手动 `fi` 量化——15.5K 参数的网络手动量化完全可控，反而更透明。

---

## 三、阶段 2（3~5 天）：Verilog 最小卷积引擎（你们已有 70% 基础）

**目标**：把 Sobel 升级成"带参数的卷积"。

一个 3×3 卷积 = Sobel 数据通路 + 权重从"常数"变"从 ROM 读" + 多通道累加。按这个顺序递进，每步用 ModelSim + 阶段 1 的 MATLAB 金标准对照（沿用你们 `histogram_proof.mlx` 那套流程）：

| 子任务 | 内容 | 新知识点 |
|---|---|---|
| 2.1 | 单输入通道 3×3 卷积，权重从 ROM 读 | 权重广播、定点乘法 |
| 2.2 | 多输入通道累加（Cin>1） | 通道累加器、按通道调权重地址 |
| 2.3 | 多输出通道分时复用（Cout>1） | 一个 MAC 阵算所有输出通道、权重 ROM 换页 |
| 2.4 | ReLU / sign、2×2 maxpool、FC 层 | 激活流水级、池化行缓存、FC=宽累加 |
| 2.5 | 拼成一个 32×32 灰度分类器，ModelSim 跑通 | 层间乒乓、控制器 FSM |

**交付物**：32×32 分类器在 ModelSim 里对一张真实测试图输出分数，**与 MATLAB 金标准逐位一致**。

**卡点提示**：定点位宽规划（权重 Q 点、累加器宽度）是唯一真正的难点；先算"最大累加值 < 2^N"再定位宽（和你们积分图 18-bit 的算法一模一样）。

---

## 四、阶段 3（2~3 天）：按路线二选一

### 走方案 A：跳过二值专项，做检测头定点化

1. 锚框解码定点化：score 的 sigmoid、x/y/w/h 解码在定点下怎么写（查表或分段近似）。
2. 效率核算：把阶段 2 的引擎按 15 DSP 阵列重组，核对 11.6M MAC/帧的时序预算。
3. 泛读 [FINN 架构图](https://github.com/Xilinx/finn)，理解流式 + 乒乓。

### 走方案 B′：二值网络专项（本方案的核心）

1. 读四篇经典（按顺序，只读架构图和核心公式即可）：
   - [Binarized Neural Networks（BNN，Courbariaux 2016）](https://arxiv.org/abs/1602.02830)——二值训练的祖师爷；
   - [XNOR-Net（ECCV 2016）](https://arxiv.org/abs/1603.05279)——乘法变 XNOR 的数学；
   - [FINN（FPGA'17）](https://arxiv.org/abs/1612.07119)——二值网络在 FPGA 上怎么做成流式；
   - [LUTNet（FCCM 2019）](https://arxiv.org/abs/1904.00938)——**LUT6 当 6 输入 popcount** 的技巧（你们方案 B′ 的算力来源）。
2. 写 LUT popcount 引擎：LUT6 输出 6 个二值乘积的 popcount（0~6 的 3 位结果），加法树汇总，256 个 LUT6 阵列。

**交付物**：对应引擎仿真通过 + 精度报告（测试集 >90% 及格线）。

---

## 五、阶段 4（3~5 天）：集成上板

**方案 A**：新增 ÷10 块平均降采样器（128×72）→ 检测器整帧前向 → 候选框 → 复用 9.16 的最高分 1 框 + 时域确认 → `osd_box_drawer` 画框 → `centroid_calc` → PID；撤 LBP 链，TD 综合资源复核。

**方案 B′**：滑窗提取器（3~4 尺度，行缓存实现）→ 级 1 二值网粗筛 → 级 2 二值网打分 → 同一套后端；LBP 保留可做对比演示。

**交付物**：上板视频——绿框稳定套脸（含彩绘脸），CNN 真实参与判决。

---

## 六、并行线（贯穿全程）：数据与精度验证——安全闸

**不要等阶段 4 才录数据。** 第 1 周就：
1. 用相机实拍采集几百张含人脸/无人脸的帧（各种距离、光照），**并专门拍一组涂颜料/贴纸的脸**；
2. 切出正负样本训练（A：标框；B′：切窗），看精度曲线；
3. **精度过不了及格线，就还在 PC 端改网络/数据，一行 Verilog 都不写。** 这是整个路线里最重要的止损机制。涂颜料脸是数据覆盖问题，PC 端就能发现缺口。

---

## 七、资料清单

**书**
- 《基于FPGA的深度学习加速器的设计与实现》（[浙江图书馆馆藏信息](https://opac.zjlib.cn/opac/book/4574209)）
- 《基于MATLAB与FPGA的图像处理教程》（[百度百科](https://baike.baidu.com/item/%E5%9F%BA%E4%BA%8EMATLAB%E4%B8%8EFPGA%E7%9A%84%E5%9B%BE%E5%83%8F%E5%A4%84%E7%90%86%E6%95%99%E7%A8%8B)）——与你们 MATLAB+FPGA 工作流同源

**MATLAB 官方文档（阶段 1 的主教材）**
- [yolov2Layers 函数参考](https://www.mathworks.com/help/vision/ref/yolov2layers.html) / [trainYOLOv2ObjectDetector](https://www.mathworks.com/help/vision/ref/trainyolov2objectdetector.html) / [YOLO v2 目标检测示例](https://www.mathworks.com/help/vision/ug/object-detection-using-yolo-v2-deep-learning.html)
- [dlquantizer 量化工作流](https://www.mathworks.com/help/deeplearning/ref/dlquantizer.html)
- [自定义训练循环示例](https://www.mathworks.com/help/deeplearning/ug/train-network-using-custom-training-loop.html)（B′ 二值训练的基础）
- [自定义层反向函数 defineBackward](https://www.mathworks.com/help/deeplearning/ug/specify-custom-layer-backward-function.html)（B′ 的 STE）
- [fi 定点对象](https://www.mathworks.com/help/fixedpoint/ref/fi.html)（金标准）

**开源工程（Verilog，可跑可改）**
- [cnn_chip（Tang Nano 20K，INT8 流式 MAC，MNIST，最小完整工程）](https://github.com/123-code/cnn_chip)
- [ZYBO 上可配置卷积核的 LeNet-5 Verilog 工程（CSDN）](https://blog.csdn.net/uu89012/article/details/161878562)
- [FINN（Xilinx，二值网络数据流参考架构）](https://github.com/Xilinx/finn)

**论文**
- [BNN（arXiv:1602.02830）](https://arxiv.org/abs/1602.02830) / [XNOR-Net（arXiv:1603.05279）](https://arxiv.org/abs/1603.05279) / [FINN FPGA'17（arXiv:1612.07119）](https://arxiv.org/abs/1612.07119) / [LUTNet（arXiv:1904.00938）](https://arxiv.org/abs/1904.00938)
- [QAT：Integer-Arithmetic-Only Inference（Jacob, CVPR 2018）](https://arxiv.org/abs/1712.05877)——量化训练必读

**视频**
- [B 站：FPGA 项目——用于数字识别的 CNN 加速器课程](https://www.snm0516.aisee.tv/video/BV1mJQMBAECW/)

---

## 八、卡点与退路

| 卡点 | 退路 |
|---|---|
| A 的检测器精度上不去 | ① 数据加增广/彩绘脸样本；② 锚框数/尺度重调；③ 转 B′（分类器比回归好训） |
| B′ 的二值分类器精度上不去 | ① 数据；② 换 2-bit/int4 权重（LUT 查表乘法，资源仍低）；③ 级 1 放宽、级 2 加强 |
| `dlquantizer` 不支持你的 MATLAB 版本/网络 | 手动 `fi` 量化（15~26K 参数量级完全可控，且更透明） |
| 卷积引擎调不出来 | 保持阶段 2 的"子任务递进 + 逐位对照"纪律；把每层独立仿真，绝不一次仿真整个网络 |
| 时间不够 | 保底：修正版 LBP（待上板验证）+ HOG/SVM 后备；CNN 部分能单独演示也算交付 |
| TD 综合/仿真问题 | 沿用既有经验：安路 IP 仿真失败就改行为级描述；权重 ROM 用 `$readmemh` 行为级 RAM |

---

## 九、检查点清单（每过一项打勾）

- [ ] 能画出所选方案（A 或 B′）数据通路图（阶段 0 交付）
- [ ] MATLAB 手写前向与 `trainNetwork` 输出逐位一致（阶段 1）
- [ ] `export_weights.m` 能导出 `.mem` 权重文件（阶段 1）
- [ ] 32×32 分类器 ModelSim 输出与 MATLAB 金标准一致（阶段 2）
- [ ] 检测器/二值分类器在自采测试集（含彩绘脸）上达标（阶段 3）
- [ ] LUT popcount 引擎（B′）或 DSP 阵列引擎（A）仿真通过（阶段 3）
- [ ] TD 综合资源报告在预算内（阶段 4）
- [ ] 上板：稳定出框、彩绘脸可检出、误报可控（阶段 4）
