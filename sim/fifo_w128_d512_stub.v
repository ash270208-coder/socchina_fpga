`timescale 1ns/1ps
// ===========================================================================
// w128_d512_fifo 行为级桩件（仅供 ModelSim 功能仿真）
//   真实 IP 是安路 soft_fifo，内部实例化原语，ModelSim 无法 elaborate。
//   简化：两个时钟在测试台里接同一个 clock，因此用简单计数器实现即可
//        （本例要验证的是"帧首污染"，与跨时钟域无关）。
// ===========================================================================
module w128_d512_fifo (
    input  wire         rst,
    input  wire         clkw,
    input  wire         we,
    input  wire [127:0] di,
    output wire [8:0]   wrusedw,
    output wire         afull,
    output wire         full_flag,

    input  wire         clkr,
    input  wire         re,
    output wire [127:0] dout,
    output wire [8:0]   rdusedw,
    output wire         valid,
    output wire         empty_flag,
    output wire         aempty
);
    reg [127:0] mem [0:511];
    reg [9:0]   wptr, rptr;
    reg [127:0] dout_r;

    wire [9:0] used = wptr - rptr;

    integer k;
    initial begin
        for (k = 0; k < 512; k = k + 1) mem[k] = 128'd0;
        wptr = 0; rptr = 0; dout_r = 128'd0;
    end

    always @(posedge clkw) begin
        if (rst) wptr <= 10'd0;
        else if (we && used < 10'd512) begin
            mem[wptr[8:0]] <= di;
            wptr <= wptr + 10'd1;
        end
    end

    always @(posedge clkr) begin
        if (rst) begin
            rptr   <= 10'd0;
            dout_r <= 128'd0;
        end
        else if (re && used > 10'd0) begin
            dout_r <= mem[rptr[8:0]];      // 1 拍读延迟
            rptr   <= rptr + 10'd1;
        end
    end

    assign dout       = dout_r;
    assign wrusedw    = used[8:0];
    assign rdusedw    = used[8:0];
    assign full_flag  = (used >= 10'd510);
    assign afull      = (used >= 10'd500);
    assign empty_flag = (used == 10'd0);
    assign aempty     = (used <= 10'd2);
    assign valid      = (used != 10'd0);
endmodule
