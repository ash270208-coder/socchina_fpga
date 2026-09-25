`timescale 1ns/1ps
// 探针：验证 conv1_frame 的帧缓存写通路与读通路
module conv1_frame_probe_tb;
    reg clk=0, rst_n=0, wr_en=0, start=0;
    reg [14:0] wr_addr=0; reg [7:0] wr_data=0;
    wire [71:0] m_data; wire m_valid, done;
    integer idx, rr, cc, ch, t;
    reg [7:0] img [0:27647];

    conv1_frame #(.W_MEM("sim/cnn_data/w_conv1_packed.mem"),
                  .B_MEM("sim/cnn_data/b_conv1_packed.mem")) dut (
        .clk(clk), .rst_n(rst_n), .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data),
        .start(start), .m_data(m_data), .m_valid(m_valid), .done(done));

    always #5 clk = ~clk;
    initial $readmemh("sim/cnn_data/x0_input.hex", img);

    initial begin
        repeat(5) @(posedge clk); rst_n=1; repeat(2) @(posedge clk);

        // ---- A) 定向写 3 个地址 ----
        @(posedge clk); wr_en=1; wr_addr=15'd1;   wr_data=8'hAA;
        @(posedge clk);            wr_addr=15'd128; wr_data=8'hBB;
        @(posedge clk);            wr_addr=15'd129; wr_data=8'hCC;
        @(posedge clk); wr_en=0;
        @(posedge clk);
        $display("A) fb[1]=%h (exp aa)  fb[128]=%h (exp bb)  fb[129]=%h (exp cc)",
                 dut.fb[1], dut.fb[128], dut.fb[129]);

        // ---- B) 按 frame_tb 同样方式写整帧 ----
        for (idx=0; idx<27648; idx=idx+1) begin
            rr = idx % 72; cc = (idx/72) % 128; ch = idx/(72*128);
            @(posedge clk);
            wr_en=1; wr_addr = ch*9216 + rr*128 + cc; wr_data = img[idx];
        end
        @(posedge clk); wr_en=0;
        @(posedge clk);
        $display("B) fb[0]=%h (exp %h)  fb[1]=%h (exp %h)  fb[128]=%h (exp %h)  fb[18560]=%h (exp %h)",
                 dut.fb[0], img[0], dut.fb[1], img[72], dut.fb[128], img[1], dut.fb[18560], img[9216+72]);
        $display("   fb[129]=%h (exp %h)  fb[9216]=%h (exp %h)",
                 dut.fb[129], img[73], dut.fb[9216], img[9216]);

        // ---- C) 启动引擎，看前 12 拍的地址链 ----
        start=1; @(posedge clk); start=0;
        for (t=0; t<12; t=t+1) begin
            @(negedge clk);
            $display("C) t=%0d i=%0d ky=%0d kx=%0d ci=%0d rr=%0d cc=%0d inb=%b faddr=%0d fb=%h fd=%h",
                     t, dut.i, dut.ky, dut.kx, dut.ci, dut.rr, dut.cc, dut.inb,
                     dut.faddr, dut.fb[dut.faddr], dut.frame_dout);
        end
        $finish;
    end
endmodule
