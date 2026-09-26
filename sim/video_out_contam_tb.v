`timescale 1ns/1ps
// ===========================================================================
// video_out 帧首污染 验证 / 对比测试台
//
// 目的：证明"显示帧首那一刻仍在途的 DDR 读数据（地址属于上一帧尾部）会被
//       写进刚清空的新 FIFO，并被当作新帧开头像素输出"。
//
// 方法：
//   * DDR 内容设计成 "word 的第 1 个像素 = 该 word 的 DDR 地址"
//        -> 输出像素值直接告诉我们是哪个地址/哪一帧的数据
//   * 帧基址: rp=0 -> 0 ; rp=1 -> 7000000 (0x6ACFC0)
//        -> 若开头像素值 < 1,382,400  = 上一帧(rp=0)的数据 = 污染
//           若开头像素值 >= 7,000,000 = 新帧(rp=1)的数据 = 干净
//   * 在"读突发进行中"时给一个 vsync 上升沿(帧首)，模拟真实相位
//
// 时序简化：ddr_clk 与 dsi_clk 接同一个 clock（本 bug 与跨时钟域无关）
// ===========================================================================
module video_out_contam_tb;
    parameter LAT = 6;              // DDR 读延迟(拍)

    reg clk = 0;
    always #5 clk = ~clk;           // 100MHz

    reg         rst_n = 0;
    reg         vsync = 0;
    reg         rd_en = 0;
    reg  [1:0]  rp    = 2'd0;
    reg         wr_busy = 0;
    reg         user_ready = 1;
    reg  [127:0] rd_data;
    reg         rd_valid;

    wire        rd_busy;
    wire        rd_en_out;
    wire [24:0] addr_out;
    wire [23:0] pix;

    video_out dut (
        .I_rst_n             (rst_n),
        .I_ddr_clk           (clk),
        .O_video_out_rd_busy (rd_busy),
        .I_video_in_wr_busy  (wr_busy),
        .I_video_out_rp      (rp),
        .O_ddr_user_rd_en    (rd_en_out),
        .O_ddr_user_addr     (addr_out),
        .I_ddr_user_ready    (user_ready),
        .I_ddr_user_rd_valid (rd_valid),
        .I_ddr_user_rd_data  (rd_data),
        .I_dsi_clk           (clk),
        .I_video_vsync       (vsync),
        .I_video_rd_en       (rd_en),
        .O_vdieo_data        (pix)
    );

    // ---- DDR 读模型：请求后 LAT 拍返回一个 word ----
    reg [24:0] pa [0:LAT-1];
    reg        pv [0:LAT-1];
    integer i;
    initial for (i = 0; i < LAT; i = i + 1) begin pa[i] = 25'd0; pv[i] = 1'b0; end

    always @(posedge clk) begin
        pv[0] <= rd_en_out;
        pa[0] <= addr_out;
        for (i = 1; i < LAT; i = i + 1) begin
            pv[i] <= pv[i-1];
            pa[i] <= pa[i-1];
        end
    end

    // word 内容 = 地址重复 5 次(前 120bit) -> 第 1 个像素就是地址本身
    // 注意: 再或上 0x800000 作为"有效标记"，这样"陈旧内存"不会退化成 0
    //       (上一版没加标记，陈旧内存正好是地址 0 -> 被当成"无数据"跳过了)
    wire [24:0] a = pa[LAT-1];
    always @(*) rd_data = {a[23:0] | 24'h800000, a[23:0] | 24'h800000,
                           a[23:0] | 24'h800000, a[23:0] | 24'h800000,
                           a[23:0] | 24'h800000, 8'h00};
    always @(*) rd_valid = pv[LAT-1];

    // ---- 抓取帧首之后的输出像素 ----
    reg [23:0] cap [0:63];
    integer    ncap = 0;
    reg        armed = 0;
    integer    req_cnt = 0;

    always @(posedge clk) begin
        if (rd_en_out) req_cnt <= req_cnt + 1;
    end

    always @(posedge clk) begin
        if (armed && rd_en && rd_valid) begin
            if (ncap < 64) begin
                cap[ncap] <= pix;
                ncap <= ncap + 1;
            end
        end
    end

    integer j;
    initial begin
        // 复位
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);

        // 帧首#1: 从 buffer0 开始读, 让读通路的 FIFO/突发跑起来
        vsync = 0; rp = 2'd0; rd_en = 1;
        repeat (3) @(posedge clk);
        vsync = 1;                 // 上升沿 = S_video_frame_start
        repeat (3) @(posedge clk);
        vsync = 0;

        // 让读突发进行一段时间(此时 FIFO 已有一批 buffer0 数据、且有在途数据)
        repeat (120) @(posedge clk);

        // ---- 关键: 在读突发"进行中"给第二个帧首, 并切到 buffer1 ----
        rp = 2'd1;
        @(posedge clk);
        // 清空抓取窗口
        ncap = 0;
        armed = 1;
        vsync = 1;                 // 帧首! (new base = 7000000)
        repeat (3) @(posedge clk);
        vsync = 0;

        // 抓够 64 个像素
        repeat (4000) @(posedge clk);
        armed = 0;

        $display("");
        $display("=== video_out frame-start contamination test ===");
        $display("   DDR layout: rp0 base=0  rp1 base=7000000(0x6ACFC0); 内容 = 地址|0x800000");
        $display("   -> 0x000000            = 无数据(空)");
        $display("   -> 0x800000..0x951C00  = 旧帧(rp0) 数据 = 污染(对应画面底部)");
        $display("   -> >= 0xEACFC0         = 新帧(rp1) 数据 = 干净");
        $display("   captured pixels after frame start (first 24):");
        for (j = 0; j < 24; j = j + 1)
            if (j < ncap)
                $display("     pix[%0d] = 0x%06X  (addr=%0d)", j, cap[j], cap[j] & 24'h7FFFFF);
        $display("");

        // 判定: 找第一个"有效数据"像素(带 0x800000 标记)
        j = 0;
        while (j < ncap && (cap[j] & 24'h800000) == 24'd0) j = j + 1;
        if (j < ncap) begin
            if ((cap[j] & 24'h7FFFFF) >= 24'd7000000)
                $display("   RESULT: CLEAN  (first valid pixel addr=%0d, new frame)", cap[j] & 24'h7FFFFF);
            else
                $display("   RESULT: CONTAMINATED  (first valid pixel addr=%0d, OLD frame)",
                         cap[j] & 24'h7FFFFF);
        end
        else
            $display("   RESULT: no valid pixel captured");
        $display("");
        $finish;
    end
endmodule
