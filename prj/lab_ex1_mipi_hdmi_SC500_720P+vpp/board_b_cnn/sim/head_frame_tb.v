//=============================================================================
// head_frame_tb.v —— 检测头整层对拍（32→15, Q12）
// 输入 x4_conv4.hex（32x18x32 列主序）→ 打包 256bit/像素 → 写帧缓存 → 启动
// 输出 32x18x15（Q12 int16）与 head_real.hex（8 hex/行 = int32）逐位比对
// 运行（仓库根目录）:
//   vlog -work work_cnn lab_ex1_mipi_hdmi_SC500_720P+vpp/lab_ex1_mipi_hdmi+vpp/user_source/hdl_source/cnn/head_frame.v sim/head_frame_tb.v
//   vsim -c work_cnn.head_frame_tb -do "run -all; quit -f"
//=============================================================================
`timescale 1ns/1ps

module head_frame_tb;

    localparam IW=32, IH=18, IC=32, IN_PX = IW*IH, WIN = 256;
    localparam OC=15, ON_PX = IW*IH, WOUT = 240;

    reg clk=0, rst_n=0, wr_en=0, start=0;
    reg [13:0]  wr_addr=0;
    reg [127:0] wr_data=0;
    wire [WOUT-1:0] m_data;
    wire m_valid, done;
    wire [13:0]  ram_raddr;
    wire [127:0] ram_rdata;
    wire [10:0]  rom_addr;
    wire [63:0]  w_doa;

    reg [7:0]  xin  [0:IN_PX*IC-1];
    reg [31:0] gold [0:ON_PX*OC-1];
    integer errs=0, checks=0, pixcnt=0, cyc=0;
    integer r, c, ch;
    reg [WIN-1:0] w;

    head_frame #(
        .IMG_W(IW), .IMG_H(IH), .TAPS(32), .NUM_GRP(2), .RAM_W(128),
        .B_MEM("sim/cnn_data/b_head.mem"),
        .MOUT_Q32(32'sd1563445632)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .start(start), .m_data(m_data), .m_valid(m_valid), .done(done),
        .ram_raddr(ram_raddr), .ram_rdata(ram_rdata),
        .rom_addr(rom_addr), .w_doa(w_doa)
    );

    // 权重官方 ROM（仿真替身）
    cnn_rom_wh u_wh (.doa(w_doa), .addra(rom_addr[5:0]), .clka(clk));

    // 输入 RAM（同步读块 RAM），每像素 2 个 128bit 字
    cnn_ram #(.DW(128), .AW(14), .DEPTH(1152)) u_fb (
        .clk(clk), .we(wr_en), .waddr(wr_addr), .wdata(wr_data),
        .raddr(ram_raddr), .rdata(ram_rdata));

    always #5 clk = ~clk;
    initial begin
        $readmemh("sim/cnn_data/x4_conv4.hex", xin);
        $readmemh("sim/cnn_data/head_real.hex", gold);
    end

    initial begin
        rst_n=0; wr_en=0; start=0;
        repeat (5) @(posedge clk); rst_n=1; repeat (2) @(posedge clk);

        $display("=========================================================");
        $display(" head whole-frame check  (golden: head_real.hex)");

        for (r=0; r<IH; r=r+1) begin
            for (c=0; c<IW; c=c+1) begin
                w = 0;
                for (ch=0; ch<IC; ch=ch+1)
                    w[8*ch +: 8] = xin[ch*IN_PX + c*IH + r];
                @(posedge clk);
                wr_en=1; wr_addr = 2*(r*IW + c);     wr_data = w[127:0];   // 通道 0..15
                @(posedge clk);
                wr_en=1; wr_addr = 2*(r*IW + c) + 1; wr_data = w[255:128]; // 通道 16..31
            end
        end
        @(posedge clk); wr_en=0;
        $display(" 输入帧写入完成（%0d 像素 x 2 字 x 128bit）", IN_PX);

        start=1; @(posedge clk); start=0;

        while (pixcnt < ON_PX && cyc < 2000000) begin
            @(negedge clk); cyc = cyc+1;
            if (m_valid === 1'b1) begin
                for (ch=0; ch<OC; ch=ch+1) begin
                    checks = checks+1;
                    if ($signed(m_data[16*ch +: 16]) !== $signed(gold[(pixcnt/IW) + IH*(pixcnt%IW) + ON_PX*ch])) begin
                        errs = errs+1;
                        if (errs <= 8)
                            $display("  FAIL pix%0d(r%0d,c%0d) ch%0d: got %0d expect %0d",
                                     pixcnt, pixcnt/IW, pixcnt%IW, ch,
                                     $signed(m_data[16*ch +: 16]),
                                     $signed(gold[(pixcnt/IW) + IH*(pixcnt%IW) + ON_PX*ch]));
                    end
                end
                pixcnt = pixcnt+1;
            end
        end

        $display(" 输出像素 %0d / %0d，耗时 %0d 拍", pixcnt, ON_PX, cyc);
        if (errs == 0 && pixcnt == ON_PX)
            $display(" RESULT: PASS  -- %0d checks all match the golden data", checks);
        else
            $display(" RESULT: FAIL  -- %0d / %0d checks mismatch", errs, checks);
        $finish;
    end

endmodule
