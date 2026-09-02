# socchina_fpga
**2026年嵌赛 FPGA 赛道**  

注意事项：
- 最终设计必须固化在开发板上，上电即可运行，无需再使用PC下载
- 注意代码不能完全一样，不要照抄，包括MIPI视频流，所以先学习，后更改


## 团队分工

| 成员   | 任务 | 待定 |
|--------|------|------|
| 景子玞 | 云台跟踪    | —    |
| 林伟钦 | OSD    | —    |
| 方俊尧 | 图像风格化    | —    |

## 学习资料

| 名称       | 类型     | 链接 |
|------------|----------|------|
| 大磊 FPGA  | 图像算法 | [B站视频](https://www.bilibili.com/video/BV1wA411i78E) |
| 小梅哥 FPGA| 硬件基础 | [B站视频](https://www.bilibili.com/video/BV1va411c7Dz) |
| 官方板卡资料 | 详细例程 | [百度网盘](https://pan.baidu.com/s/12hjB7BiAxT3CIVqzh4Amnw) |

---

## 景子玞 · 工作日志

### 2026.8.23
- 获取官方资料，安装 TD 开发平台 + ModelSim
- 完成从代码 → 仿真 → 添加约束的完整流程
- 参考：官方 PDF《安路软件使用全流程》 + [B站视频](https://www.bilibili.com/video/BV14MFCe4EHe)

### 2026.8.24
阅读官方例程，梳理数据通路：
SC500CS 物理信号  
→ mipi_dphy_rx          (D-PHY 物理层)  
→ csi_unpacket_2lane    (CSI-2 解包)  
→ raw10_unpacket_2lane  (Bayer RAW10)  
→ uial2axis             (AXI4-Stream)  
→ image_correction      (BLC / DPC)  
→ isp_top               (去马赛克 + 色彩校正) ← 主要修改点  
→ video_in + ddr_wrapper (帧缓存)  
→ video_out  
→ hdmi_mixer            ← 主要修改点 （osd） 
→ hdmi_tx               (HDMI 输出)    

**初步方案**：
- `isp_top`：完成 AE / AWB / 直方图均衡
- `hdmi_mixer` 与 `hdmi_tx` 之间：多算法切换 + 状态显示 + 目标跟踪/检测 + 风格化（即添加一个vpp模块）  

### 2026.8.25
**架构确认**：
1. DDR 写入前：去马赛克 + 白平衡 + 自动曝光（基础处理）
2. DDR 写出后：灰度 / 边缘检测等算法，通过 MUX 切换

开始编写直方图均衡模块：

| 模块              | 功能                    | 文件                |
|-------------------|-------------------------|---------------------|
| RGB888_YCbCr444   | RGB → YCbCr（取 Y）     | RGB888_YCbCr444.v   |
| histogram_equ     | 直方图均衡              | histogram.v         |

### 2026.8.26
完成 `vpp_top` 直方图部分并仿真验证。

| 模块              | 功能                       | 文件                  |
|-------------------|----------------------------|-----------------------|
| vpp_top           | 算法顶层                   | vpp_top.v             |
| vpp_top_tb        | 测试平台                   | vpp_top_tb.v          |
| RGB_generation    | 图片转 RGB888              | RGB_generation.mlx    |
| histogram_proof   | 仿真结果可视化             | histogram_proof.mlx   |

**主要问题与解决**：
- 双口 RAM 读写冲突 → 调整 A/B 口职责 + 时序打拍
- 安路 IP 原语仿真失败 → 改为行为级描述后通过
- 仍需上板最终验证

![仿真结果](https://github.com/user-attachments/assets/33a27119-f792-4e6a-9e96-bac858184d7e)

### 2026.8.27
- 修复 RGB888_YCbCr444 输出延迟导致首像素丢失的问题
- 与 MATLAB 结果对比，误差基本消除
- 将 `vpp_top` 整合进官方例程 `lab_ex_2026_1`，综合通过，待上板

![修正后对比](https://github.com/user-attachments/assets/ea7b317e-5287-49d5-8d3d-ba82ac3f4fd2)

下一步：学习腐蚀 / 膨胀 / 边缘检测

### 2026.8.28
- 基于官方代码修改接口，将 Sobel 边缘检测接入 `vpp_top`
- AI 生成 testbench 与 MATLAB 验证代码
- 原理了解基本完成，时序细节仍需进一步梳理，这一部分代码纯ai改编官方例程

![Sobel 仿真](https://github.com/user-attachments/assets/430ca9cf-c7f9-4d56-bec3-c67e0a8264c3)

### 2026.8.29
将边缘检测接入完整显示链路后出现时钟相关警告：

**PHY-5060**  
- `scl_clk` 同时作为时钟和数据/控制信号使用  
- `O_cam_24m` 既驱动 102 个时钟引脚，又作为普通输出

**PHY-5079**  
- 时钟网络未走全局时钟树（由 PHY-5060 引起）

**根因分析**：  
纯直方图版本中按键信号未使用，综合工具将 `u_ae_set` 相关逻辑优化掉；加入 Sobel + 按键消抖后，按键逻辑被激活，导致时钟混用问题暴露。

**修改措施**：
1. 使用安路 High-Speed IO IP（`cam_clk_oddr`）规范输出 24M 摄像头时钟，替代直接顶层模块中 `assign O_cam_24m=S_24m_clk; `
2. 将 `uii2c` 模块中 `always @(posedge scl_clk)` 改为以 `I_clk` 为主时钟 + Clock Enable 方式
3. 修复消隐期同步信号死锁 Bug
4. 完善 `vpp` 模块

![警告截图](https://github.com/user-attachments/assets/bdcf5200-297d-473e-b901-14e9cb2e21d0)  


### 2026.8.30  
完成腐蚀与膨胀模块，并成功例化  

vpp_top-->Sobel_edge_detection_top-->Sobel_edge+腐蚀膨胀  

<img width="1902" height="461" alt="sobel_edge" src="https://github.com/user-attachments/assets/2ef1a370-b7c1-42c2-b981-085412a9e725" />  
<img width="1872" height="434" alt="Sobel_edge_black" src="https://github.com/user-attachments/assets/d1cc9c55-6872-4c56-bfba-415f6d87fb3c" />  

前图为加入腐蚀膨胀前（设置为白色边沿），后图为腐蚀膨胀后（设置的为黑色边沿），前途噪点较多，但是线条更清晰，原因是图片较小，边沿检测的线条本来就较细，腐蚀容易使得线条消失


### 2026.8.31 
**云台跟踪初步方案**
- YCbCr 肤色/特定颜色分割 + 实时形心（Centroid）坐标提取（色彩空间阈值分割 + 连通域形心算法）——此算法是根据颜色来识别人类，准确率低，后续升级
- PID控制，将中心偏差送入PID控制器，输出两路PWM波控制云台
- 优化 加入死区控制（Deadzone），即人已经基本在正中央（比如偏差在 ±20像素以内）时，云台保持不动，防止舵机高频抖动


关于人脸识别的方案——肤色分割-->平面椭圆肤色模型-->Haar-like级联加速器，先入手平面椭圆肤色模型

** 平面椭圆肤色模型代码模块如下  

| 模块              | 功能                          | 文件                |
|-------------------|-------------------------------|---------------------|
|face_track_top     |顶层模块，接收各算法处理的数据  |face_track_top.v     |
|skin_binarizer     |利用平面椭圆肤色模型将图像二值化|skin_binarizer.v     |
|centroid_calc      |计算人脸区域质心                |centroid_calc.v      |
|osd_cross_hair     |在质心处添加十字准星            |osd_crosshair.v      |

