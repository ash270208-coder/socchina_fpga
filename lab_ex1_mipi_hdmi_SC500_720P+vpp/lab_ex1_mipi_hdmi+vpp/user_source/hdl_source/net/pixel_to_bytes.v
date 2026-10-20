`timescale 1ns / 1ps
//=============================================================================
// pixel_to_bytes.v —— 24bit 像素拆成 R/G/B 三字节写入跨时钟 FIFO
//
// 上游 cnn_ds10 的输出节奏是 **每 4 拍 1 个像素**（见 cnn_ds10.v 的 drain_sub），
// 所以拆 3 拍写字节有充足余量，不需要任何反压。
//   拍0: 捕获像素  拍1: 写 R  拍2: 写 G  拍3: 写 B  → 回到拍0
//
// I_gate 是帧门控：只有被选中的帧才写进 FIFO。
//   ⚠ 门控必须放在**这里**（写侧），不能放在 cnn_ds10 的输入端——
//     cnn_ds10 靠 10 行条纹的双 bank 乒乓工作，输入被抽掉会让块边界错乱。
//     放在写侧时 cnn_ds10 一直连续跑，块网格始终与帧对齐。
//
// 输出字节顺序 = R, G, B（与板 B 约定的图像格式一致）
//
// ★[修复12] 通道序实测修正（2026-10-13）
//   实测：原来按 p[23:16]→p[15:8]→p[7:0] 输出时，接收端必须按 (B,R,G) 解释
//   才能得到正确颜色（把 6 种通道排列都渲染出来比对，只有 GBR 是对的）。
//   即 cnn_ds10 送进来的 24 位里：
//       发出 (G,B,R) -> 线上读出 (R,G,B)。p[23:16]=R、p[15:8]=G、p[7:0]=B（见 cnn_ds10.v:200）
//   上层 vpp_top 的命名（{gamma_r,gamma_g,gamma_b}）与显示通路一致，
//   显示端另有兼容，但**以太网支路必须按真实通道序发出去**，否则板 B 收到偏色。
//   因此这里改成按 R,G,B 顺序写：
//       拍1 写 p[15:8] (R) -> 拍2 写 p[7:0] (G) -> 拍3 写 p[23:16] (B)
//   ⚠ 本模块只服务以太网支路（显示走 vpp_top O_tdata -> osd -> hdmi_tx），
//     改这里**不影响 HDMI 颜色**。
//=============================================================================
module pixel_to_bytes (
    input  wire        I_clk,        // pclk（视频像素时钟，75MHz）
    input  wire        I_rst_n,
    input  wire        I_valid,      // cnn_ds10 的 O_tvalid
    input  wire [23:0] I_data,       // cnn_ds10 的 O_tdata（RGB888）
    input  wire        I_gate,       // 帧门控（高=采集本帧）
    output reg  [7:0]  O_byte,
    output reg         O_we
);
    reg [1:0]  ph;
    reg [23:0] p;

    wire take = I_valid & I_gate;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            ph <= 2'd0; O_we <= 1'b0; O_byte <= 8'd0; p <= 24'd0;
        end else if (!I_gate) begin
            // 2026-10-18 修复【根因】：门控关闭期间强制相位归零。
            //   gate 的下降沿与"3 字节/像素"的相位是异步的，若在像素中途关闸，
            //   ph 会停在 1 或 2 并一直保持；下次开门就从 G 或 B 开始发 ->
            //   表现为"每次上电通道顺序随机"（这就是之前所有矛盾的根源）。
            ph   <= 2'd0;
            O_we <= 1'b0;
        end else begin
            O_we <= 1'b0;
            case (ph)
                2'd0: begin
                    if (take) begin
                        p  <= I_data;
                        ph <= 2'd1;
                    end
                end
                // 2026-10-18 18:58 定论（读 RTL 得出，不是猜的）：
                //   cnn_ds10.v 第 200 行  O_tdata <= {dres_r, dres_g, m_out[27:20]};
                //   => p[23:16]=R、p[15: 8]=G、p[ 7: 0]=B。注意 p[7:0] 不是 R 而是 B！
                //   读取端还有恒定 2 字节偏移（17:32 / 18:52 两次横带实测都精确符合）。
                //   故线上要读出 (R,G,B)，必须发出 (G,B,R) = 下面三行的顺序。
                2'd1: begin O_we <= 1'b1; O_byte <= p[15: 8]; ph <= 2'd2; end  // G
                2'd2: begin O_we <= 1'b1; O_byte <= p[ 7: 0]; ph <= 2'd3; end  // B
                default: begin O_we <= 1'b1; O_byte <= p[23:16]; ph <= 2'd0; end // R
            endcase
        end
    end
endmodule
