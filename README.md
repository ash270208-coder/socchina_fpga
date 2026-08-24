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
2026.8.23  
获取官方资料，安装官方开发平台TD，下载Modelsim  
从代码到仿真再到添加约束，通过TD和Modelsim完整实现全流程  
参考资料为：  
官方pdf——安路软件使用全流程  
视频——https://www.bilibili.com/video/BV14MFCe4EHe?t=1.8


2026.8.24  
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


