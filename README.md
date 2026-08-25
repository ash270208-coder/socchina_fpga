# socchina_fpga
2026年嵌赛fpga赛道
## 团队分工
|成员|任务|待定|
|:---|:---:|:---|
|景子玞|1111 |111 |
|林伟钦|     |    | 
|方俊尧|     |     |


## 学习资料
|名称|类型|链接|
|:---:|:---:|:---:|
|大磊fpga|图像算法|https://www.bilibili.com/video/BV1wA411i78E?spm_id_from=333.1387.collection.video_card.click|
|小梅哥fpga|硬件基础|https://www.bilibili.com/video/BV1va411c7Dz?t=1.1| 
|官方板卡资料|详细例程|https://pan.baidu.com/s/12hjB7BiAxT3CIVqzh4Amnw|

### 景子玞的工作日志
#### 2026.8.23  
获取官方资料，安装官方开发平台TD，下载Modelsim  
从代码到仿真再到添加约束，通过TD和Modelsim完整实现全流程  
参考资料为：  
官方pdf——安路软件使用全流程  
视频——https://www.bilibili.com/video/BV14MFCe4EHe?t=1.8


#### 2026.8.24  
##### 阅读官方例程，尝试找到思路
例程1代码结构层次
[SC500CS 物理信号]
      │ IO_rx_data_pad_p/n (MIPI 差分线)    
      ▼  
1. 【mipi_dphy_rx_ph1p_mipiio_wrapper】: 物理层 D-PHY，输出 16 位 HS 数据 (S_hs_rx_data)  
      ▼  
2. 【csi_unpacket_2lane】: CSI-2 协议解包，提取有效数据包 (S_csi_data[31:0])  
      ▼  
3. 【raw10_unpacket_2lane】: 解包为 Bayer RAW10 数据 (S_raw10_data[39:0]，4像素并行)  
      ▼  
4. 【uial2axis】: 转换为标准 AXI4-Stream 视频流 (S_axis_tdata / S_axis_tuser / S_axis_tlast)  
      ▼  
5. 【image_correction】: 图像校正（如黑电平校正 BLC、去坏点 DPC，输出 S_raw_tdata）  
      ▼  
6. 【isp_top】: 核心 ISP（Bayer 转 RGB 邻域插值、色彩校正、打包为 128 位宽 S_ISP_O_tdata）  
      ▼  
7. 【video_in】+【ddr_wrapper】: 写入片内 DDR 帧缓存（三缓存/乒乓机制）  
      ▼  
8. 【video_out】: 从 DDR 读出视频，转换为 HDMI 时钟域的 24 位 RGB 数据 (S_video_rd_data[23:0])  
      ▼  
9. 【hdmi_mixer】: 混叠器（视频窗口对齐、当前例程的 OSD/调试信息注入点）    
      ▼    
10.【hdmi_tx】: 编码并串行化输出 TMDS 差分信号驱动屏幕 (O_tmds_ch*_p)
   
   
其中isp_top和hdmi_mixer是修改的主要目标    
  
isp_top中适合完成AE(自动曝光)，AWB(自动白平衡)，直方图均衡化

     
在u_hdmi_mixer 与 u_hdmi_tx 之间实现
     
1. 多算法平滑切换与状态显示  
   将 24 位 RGB 像素并行输入多个流水线算法分支（原图分支、灰度+Sobel 边缘分支、二值化+形态学分支、色彩分割分支；  
   设计按键状态机（FSM）控制一个多路选择器（MUX），按键按下时平滑切换选择输出哪一路流；  
   状态显示：在 OSD 模块内根据当前状态机的值，在屏幕右上角显示 MODE: SOBEL 或 MODE: TRACKING  

2. 目标跟踪与信息标注 / 目标检测与文字叠加  
3.  图像风格化 / 卡通化

#### 2026.8.25  
##### 思路的再次确认  
写入ddr之前的isp中进行去马赛克和白平衡+自动曝光（这三个算法是图像的基本处理），后续无论用什么算法都需要先经过这几个算法的处理  
之后写入ddr，此时保留的是原图  
从ddr中写出之后，再进行灰度处理，边沿检测等算法，利用多路选择器实现算法的切换

##### 尝试书写直方图均衡算法  
|模块|功能|文件名称|
|:---|:---:|:---|
|RGB888_YCbCr444|将RGB转为YCbCr，获取灰度数据便于后面获取灰度直方图|RGB888_YCbCr444.v|  
|histogram_equ|实现直方图均衡|histogram.v|  

直方图均衡算法的思路：  
1. 获取每个像素的亮度值Y  
2. 统计各灰度值（从0到255）的像素个数，利用双口RAM，以灰度值作为地址，每读到一个灰度值，相应地址的数据加1（具体操作是先读出对应地址的数据再加1，然后存回）  
3. 在一帧数据结束后，在消隐区间，即帧与帧之间，完成读取双口RAM中的数据并累加，形成累计直方图的数据，写入新的ram，写入完成之后，在开始对双口RAM清0，即每个地址写入0
4. 从累积直方图RAM中读出数据然后进行均衡处理
5. 打拍同步，然后输出





 
   


