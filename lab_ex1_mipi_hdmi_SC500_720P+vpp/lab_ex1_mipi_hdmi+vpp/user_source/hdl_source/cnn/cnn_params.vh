// 由 export_fpga_consts.m 自动生成 —— Verilog 定点常数，勿手改
// 用法: real = (acc * `MOUT_Q32_xxx + 32'sd2147483648) >>> 32   (acc>=0)
//       real = (acc * `MOUT_Q32_xxx - 32'sd2147483648) >>> 32   (acc<0)
`ifndef CNN_PARAMS_VH
`define CNN_PARAMS_VH

`define MOUT_Q32_CONV1 32'd15573148
`define MOUT_Q32_CONV2 32'd56261780
`define MOUT_Q32_CONV3 32'd25934300
`define MOUT_Q32_CONV4 32'd17997652
`define MOUT_Q32_HEAD_CONV 32'd381701
`define MOUT_Q32_HEAD_Q12 32'd1563445632

// 锚框 Q12（值 = 原始值 x 4096）
`define ANCHOR1_W_Q12 18'd52328
`define ANCHOR1_H_Q12 18'd34738
`define ANCHOR2_W_Q12 18'd67885
`define ANCHOR2_H_Q12 18'd65880
`define ANCHOR3_W_Q12 18'd151969
`define ANCHOR3_H_Q12 18'd122424

`endif
