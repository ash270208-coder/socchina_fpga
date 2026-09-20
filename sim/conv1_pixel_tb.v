//=============================================================================
// conv1_pixel_tb.v —— conv1 单像素对拍（FPGA 端第一步验收）
//-----------------------------------------------------------------------------
// 做法：
//   1) 读入输入图 x0_input.hex（128×72×3，MATLAB 列主序：idx = r + 72*c + 9216*ch）
//   2) 读入金标准 x1_conv1.hex（128×72×8，同一顺序）
//   3) 对若干像素组建 3×3×3 patch（含 pad=1 补零），逐个输出通道与金标准比对
//
// 运行（在【仓库根目录】下执行，那里有 modelsim.ini 和 work/）：
//   vlib work_cnn
//   vlog -work work_cnn lab_ex1_mipi_hdmi_SC500_720P+vpp/lab_ex1_mipi_hdmi+vpp/user_source/hdl_source/cnn/conv1_pixel.v sim/conv1_pixel_tb.v
//   vsim -c work_cnn.conv1_pixel_tb -do "run -all; quit -f"
//=============================================================================
`timescale 1ns/1ps

module conv1_pixel_tb;

    localparam integer IMG_W = 128;
    localparam integer IMG_H = 72;
    localparam integer IMG_C = 3;
    localparam integer IMG_N = IMG_W*IMG_H*IMG_C;      // 27648
    localparam integer X1_N  = IMG_W*IMG_H*8;          // 73728
    localparam integer TAPS  = 27;                     // CIN*K*K

    reg         clk = 1'b0;
    reg         rst_n = 1'b0;
    reg         start = 1'b0;
    reg  [3:0]  cout_idx = 4'd0;
    reg  [8:0]  patch [0:TAPS-1];
    reg  [TAPS*9-1:0] patch_flat;                      // 243 位（曾误写成 234 位 → 第 26 个 tap 读到 z）
    wire [8:0]  y_out;
    wire        done;

    integer errs   = 0;
    integer checks = 0;

    reg [7:0] img  [0:IMG_N-1];
    reg [7:0] gold [0:X1_N-1];

    // ---- DUT ----
    conv1_pixel #(
        .W_MEM("sim/cnn_data/w_conv1.mem"),
        .B_MEM("sim/cnn_data/b_conv1.mem")
    ) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (start),
        .cout_idx (cout_idx),
        .x_patch  (patch_flat),
        .y_out    (y_out),
        .done     (done)
    );

    always #5 clk = ~clk;                              // 100 MHz 仿真时钟

    // ---- 数据文件读取 ----
    initial begin
        $readmemh("sim/cnn_data/x0_input.hex", img);
        $readmemh("sim/cnn_data/x1_conv1.hex", gold);
    end

    //-------------------------------------------------------------------------
    // 单像素检查任务：组建 patch → 8 个输出通道逐个比对
    //-------------------------------------------------------------------------
    task check_pixel;
        input integer r;
        input integer c;
        integer ky, kx, ci, idx, ch, gi;
        reg [8:0] v;
        begin
            // 组装 patch：i = ky + 3*kx + 9*ci，越界处补 0（pad=1）
            for (ky = 0; ky < 3; ky = ky + 1) begin
                for (kx = 0; kx < 3; kx = kx + 1) begin
                    for (ci = 0; ci < 3; ci = ci + 1) begin
                        idx = ky + 3*kx + 9*ci;
                        if (((r+ky-1) >= 0) && ((r+ky-1) < IMG_H) &&
                            ((c+kx-1) >= 0) && ((c+kx-1) < IMG_W))
                            v = {1'b0, img[(r+ky-1) + IMG_H*(c+kx-1) + IMG_H*IMG_W*ci]};
                        else
                            v = 9'd0;
                        patch[idx] = v;
                    end
                end
            end
            for (idx = 0; idx < TAPS; idx = idx + 1)
                patch_flat[idx*9 +: 9] = patch[idx];

            // 8 个输出通道
            for (ch = 0; ch < 8; ch = ch + 1) begin
                cout_idx = ch[3:0];
                @(posedge clk);
                start = 1'b1;
                @(posedge clk);
                start = 1'b0;
                while (done !== 1'b1) @(posedge clk);
                @(posedge clk);                          // 让 y_out 稳定

                gi = r + IMG_H*c + IMG_H*IMG_W*ch;
                checks = checks + 1;
                if (y_out !== {1'b0, gold[gi]}) begin
                    errs = errs + 1;
                    $display("  FAIL  pixel(%0d,%0d) ch%0d: got %0d, expect %0d",
                             r, c, ch, y_out, gold[gi]);
                end
            end
            $display("  pixel(%0d,%0d): all 8 channels checked", r, c);
        end
    endtask

    //-------------------------------------------------------------------------
    // 主流程
    //-------------------------------------------------------------------------
    initial begin
        rst_n = 1'b0;
        start = 1'b0;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        $display("=========================================================");
        $display(" conv1 single-pixel check   (golden: out/golden/x1_conv1.txt)");
        $display("---------------------------------------------------------");
        $display(" weight ROM self-test (first 4 entries of w_conv1.mem):");
        $display("   w[0..3] = %0d %0d %0d %0d", dut.w_rom[0], dut.w_rom[1], dut.w_rom[2], dut.w_rom[3]);
        $display("   b[0..3] = %0d %0d %0d %0d", dut.b_rom[0], dut.b_rom[1], dut.b_rom[2], dut.b_rom[3]);
        $display("---------------------------------------------------------");

        check_pixel(0, 0);        // 左上角（含 padding）
        check_pixel(0, 5);
        check_pixel(1, 1);
        check_pixel(35, 64);      // 画面中央
        check_pixel(71, 127);     // 右下角（含 padding）

        $display("---------------------------------------------------------");
        if (errs == 0)
            $display(" RESULT: PASS  -- %0d checks all match the golden data", checks);
        else
            $display(" RESULT: FAIL  -- %0d of %0d checks mismatch", errs, checks);
        $display("=========================================================");
        $finish;
    end

endmodule
