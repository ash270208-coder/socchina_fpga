# socchina_fpga

基于 Anlogic TD 的 FPGA 图像处理工程：SC500 摄像头 MIPI 输入 -> ISP 处理 -> HDMI 输出（720P + VPP 后处理）。

## 目录结构

- `td_project/` —— TD 工程文件（IP、约束、综合布局布线结果）
- `user_source/hdl_source/` —— RTL 源码（ISP、MIPI DPHY、DDR2 控制器、HDMI/VTC 等）
- `user_source/ip_source/` —— 用户 IP 源文件

## 工具链

- 开发工具：Anlogic TD
- 版本管理：Git + GitHub + VSCode
