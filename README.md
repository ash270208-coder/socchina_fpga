socchina_fpga
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
4. 从累积直方图RAM中读出数据然后进行均衡处理（注意时序，复位后首次运行时，第一帧图像生成累积直方图并存入ram时，读取出的ram是复位后的值，一般为0，只有在第二帧图像进入  时，读取的ram才是第一帧图像的累积直方图，并均衡化，所以会延迟一帧）
5. 打拍同步，然后输出

##### 2026.8.26  
###### 遇到的问题和自己的解释： 
读取前一帧累积直方图的同时又在写入当前累积直方图，怎么避免读取之前就被写入覆盖呢？  
————对于这个问题我有一个解释，就是我在读取直方图时，由于I_valid一定是有效的，所以在I_grey_tdata来之后，下一拍就能先读出上一帧的数据，但是ram_accu_wr<=ram_his_rd_b，写入新的累积直方图的使能信号是慢于b端口的读使能信号，而且b端口的读使能信号是在消隐期间开启，并且还要在a端口写完之后，所以这个ram的读是快于写的。  
    所以单 RAM 安全的前提是：下一帧的第一个有效像素到来之前，必须已经把 256 个累计直方图全部写完。  

###### 主要工作  
1. 完成了vpp_top的代码关于histogram的部分
2. 进行了代码的测试，验证了直方图均衡算法的有效性

   <img width="1920" height="1022" alt="Snipaste_2026-08-26_20-01-17" src="https://github.com/user-attachments/assets/33a27119-f792-4e6a-9e96-bac858184d7e" /># 

|模块|功能|文件名称|
|:---|:---:|:---|
|vpp_top|顶层模块，最终连接多种算法|vpp_top.v|
|vpp_top_tb|测试模块，ai生成|vpp_top_tb.v|
|RGB_generation|将一张图片转为RGB888数据|RGB_generation.mlx|
|histogram_proof|将仿真后生成的处理后的灰度图显示出来|histogram_proof.mlx|

期间遇到的问题： 
1. 代码进行了相当大的修改：
   1. 修改的双口RAM的功能：A口改为只负责读，B口改为只负责写
   2. ram_accu_wrdata = his_sum 改为ram_accu_wrdata = his_sum + ram_his_rd_data;还无法理解
   3. 各种打拍寄存，时序还不清楚
2. 仿真时注意，如果代码是调用的ram的ip核，仿真时无法成功，原因可能是MOSELSIM不知道安路的ip核原语如何使用，将ram的IP核改为用行为语言描述，仿真成功。所以代码还需真正上版验证


（明天主要看看histogram_equ的代码再搞懂一些）

#####2026.8.27  
昨天的仿真结果误差较大，见上图，原因如下：  
1. RGB888_YCbCr444的输出延迟一拍，导致第一个像素被忽略，已修正
2. matlab的直方图均衡算法与verilog的略有不同，导致出现误差
   修正后误差几乎为0
   
<img width="1854" height="761" alt="image" src="https://github.com/user-attachments/assets/ea7b317e-5287-49d5-8d3d-ba82ac3f4fd2" />  

将vpp_top整合进了官方例程lab_ex_2026_1综合完成，代码无误，需要上板验证  

接下来学习腐蚀+膨胀+边沿检测





 
   


