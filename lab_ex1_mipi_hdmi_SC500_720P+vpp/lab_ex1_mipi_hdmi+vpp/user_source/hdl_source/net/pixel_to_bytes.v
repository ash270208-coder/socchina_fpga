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
        end else begin
            O_we <= 1'b0;
            case (ph)
                2'd0: begin
                    if (take) begin
                        p  <= I_data;
                        ph <= 2'd1;
                    end
                end
                2'd1: begin O_we <= 1'b1; O_byte <= p[23:16]; ph <= 2'd2; end
                2'd2: begin O_we <= 1'b1; O_byte <= p[15: 8]; ph <= 2'd3; end
                default: begin O_we <= 1'b1; O_byte <= p[ 7: 0]; ph <= 2'd0; end
            endcase
        end
    end
endmodule
