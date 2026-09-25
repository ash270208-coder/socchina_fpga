`timescale 1ns/1ps
// 临时调试：观察 conv1_frame 前 80 拍的内部状态
module conv1_frame_dbg_tb;
    localparam IMG_W=128, IMG_H=72, IMG_N=IMG_W*IMG_H*3, AW=15;
    reg clk=0, rst_n=0, wr_en=0, start=0;
    reg [AW-1:0] wr_addr=0; reg [7:0] wr_data=0;
    wire [71:0] m_data; wire m_valid, done;
    reg [7:0] img [0:IMG_N-1];
    integer idx, rr, cc, ch, t;

    conv1_frame #(.W_MEM("sim/cnn_data/w_conv1_packed.mem"),
                  .B_MEM("sim/cnn_data/b_conv1.mem")) dut (
        .clk(clk), .rst_n(rst_n), .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data),
        .start(start), .m_data(m_data), .m_valid(m_valid), .done(done));

    always #5 clk = ~clk;
    initial $readmemh("sim/cnn_data/x0_input.hex", img);

    initial begin
        rst_n=0; wr_en=0; start=0;
        repeat(5) @(posedge clk); rst_n=1; repeat(2) @(posedge clk);
        for (idx=0; idx<IMG_N; idx=idx+1) begin
            rr = idx % IMG_H; cc = (idx/IMG_H) % IMG_W; ch = idx/(IMG_H*IMG_W);
            @(posedge clk);
            wr_en=1; wr_addr = ch*(IMG_W*IMG_H) + rr*IMG_W + cc; wr_data = img[idx];
        end
        @(posedge clk); wr_en=0;
        start=1; @(posedge clk); start=0;
        for (t=0; t<80; t=t+1) begin
            @(negedge clk);
            $display("t=%0d st=%0d bk=%0d i=%0d bw=%0d acc0=%0d fd=%0d ww=%h inbq=%b y0=%0d",
                     t, dut.state, dut.bk, dut.i, dut.b_word, dut.acc[0],
                     dut.frame_dout, dut.w_word, dut.inb_q, dut.yq[0]);
        end
        $finish;
    end
endmodule
