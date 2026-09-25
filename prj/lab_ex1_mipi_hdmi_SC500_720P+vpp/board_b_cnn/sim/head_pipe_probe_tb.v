`timescale 1ns/1ps
// 探针: head_frame 前 6 拍流水（喂 1 个非零像素）
module head_pipe_probe_tb;
    reg clk=0, rst_n=0, wr_en=0, start=0;
    reg [9:0] wr_addr=0;
    reg [255:0] wr_data=0;
    wire [239:0] m_data; wire m_valid, done;
    integer t;

    head_frame #(.W_MEM("sim/cnn_data/w_head_packed.mem"), .B_MEM("sim/cnn_data/b_head.mem"))
    dut (.clk(clk), .rst_n(rst_n), .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data),
         .start(start), .m_data(m_data), .m_valid(m_valid), .done(done));

    always #5 clk = ~clk;

    initial begin
        rst_n=0; wr_en=0; start=0;
        repeat (5) @(posedge clk); rst_n=1; repeat (2) @(posedge clk);
        // 写 1 个像素: ch0=1, ch1=2, ch2=3, ... 便于观察
        wr_data = 256'h1f1e1d1c1b1a191817161514131211100f0e0d0c0b0a09080706050403020100;
        @(posedge clk); wr_en=1; wr_addr=0;
        @(posedge clk); wr_en=0;
        start=1; @(posedge clk); start=0;
        for (t=0; t<7; t=t+1) begin
            @(negedge clk);
            $display("t=%0d st=%0d tc=%0d g=%0d tv=%0d doa0=%h xd=%0d acc0=%0d", t,
                     dut.state, dut.t, dut.g, dut.t_valid, dut.w_doa[7:0], dut.xval_d, dut.acc[0]);
        end
        $finish;
    end
endmodule
