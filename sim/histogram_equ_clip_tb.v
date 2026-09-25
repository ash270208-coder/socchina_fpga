`timescale 1ns/1ps
// ===========================================================================
// histogram_equ 对比度限制(clip) + 重分配 功能验证
//
//   DUT_OFF : CLIP_DIV=1  -> CLIP = 4096 = 帧像素数 -> 永不裁剪(= 原始行为)
//   DUT_ON  : CLIP_DIV=64 -> CLIP = 64            -> 裁剪 + 重分配
//
//   帧1 = 白墙 + 墙角 场景(制造 h[i] 尖峰, 复现"白墙满屏噪点")
//   帧2 = 0..255 斜坡探针 -> 直接量出映射曲线 out[x]
//
//   关注: ① 白墙亮度附近的局部增益(噪点放大倍数)  ② 白点是否还在 255
//         ③ 暗部是否被抬起来(空 bin 重分配的效果)
// ===========================================================================
module histogram_equ_clip_tb;
    localparam W   = 64;
    localparam H   = 64;
    localparam CLK = 10;

    reg clk = 0;
    always #(CLK/2) clk = ~clk;

    reg        rst_n  = 0;
    reg        tvalid = 0, tuser = 0, tlast = 0;
    reg  [7:0] grey   = 0;

    wire [7:0] out_off, out_on;
    wire       v_off,   v_on;

    histogram_equ #(.IMG_WIDTH(W), .IMG_HEIGHT(H), .CLIP_DIV(1)) dut_off (
        .I_clk(clk), .I_rst_n(rst_n), .I_tlast(tlast), .I_tuser(tuser),
        .I_grey_tdata(grey), .I_tvalid(tvalid),
        .O_tlast(), .O_tuser(), .O_tvalid(v_off), .O_grey_tdata(out_off)
    );

    histogram_equ #(.IMG_WIDTH(W), .IMG_HEIGHT(H), .CLIP_DIV(64)) dut_on (
        .I_clk(clk), .I_rst_n(rst_n), .I_tlast(tlast), .I_tuser(tuser),
        .I_grey_tdata(grey), .I_tvalid(tvalid),
        .O_tlast(), .O_tuser(), .O_tvalid(v_on), .O_grey_tdata(out_on)
    );

    // 输入延迟 3 拍(= 模块内部延迟), 用于把输出与输入配对
    reg [7:0] gd1 = 0, gd2 = 0, gd3 = 0;
    always @(posedge clk) begin
        gd1 <= grey; gd2 <= gd1; gd3 <= gd2;
    end

    reg [7:0] map_off [0:255];
    reg [7:0] map_on  [0:255];
    reg       probe = 0;

    integer i, r, c, v;
    integer g_off, g_on;

    always @(posedge clk) begin
        if (probe) begin
            if (v_off) map_off[gd3] <= out_off;
            if (v_on)  map_on [gd3] <= out_on;
        end
    end

    task blank;
        input integer n;
        integer k;
        begin
            tvalid <= 0; tuser <= 0; tlast <= 0; grey <= 0;
            for (k = 0; k < n; k = k + 1) @(posedge clk);
        end
    endtask

    // 白墙: 52 行 @199..201 ; 暗墙角: 10 行 @59..61 ; 少量杂项: 2 行
    task send_scene;
        begin
            for (r = 0; r < H; r = r + 1)
                for (c = 0; c < W; c = c + 1) begin
                    @(posedge clk);
                    tvalid <= 1'b1;
                    tuser  <= (r == 0) && (c == 0);
                    tlast  <= (c == W-1);
                    if (r < 52)      v = 200 + ((r*7  + c*13) % 3) - 1;
                    else if (r < 62) v =  60 + ((r*5  + c*11) % 3) - 1;
                    else             v = (c*4) % 256;
                    grey <= v[7:0];
                end
            @(posedge clk);
            tvalid <= 0; tuser <= 0; tlast <= 0; grey <= 0;
        end
    endtask

    // 探针: 0..255 每个值出现 16 次
    task send_ramp;
        begin
            probe = 1;
            for (r = 0; r < H; r = r + 1)
                for (c = 0; c < W; c = c + 1) begin
                    @(posedge clk);
                    tvalid <= 1'b1;
                    tuser  <= (r == 0) && (c == 0);
                    tlast  <= (c == W-1);
                    grey   <= ((r*W + c) % 256);
                end
            @(posedge clk);
            tvalid <= 0; tuser <= 0; tlast <= 0; grey <= 0;
            for (i = 0; i < 8; i = i + 1) @(posedge clk);
            probe = 0;
        end
    endtask

    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            map_off[i] = 8'd0;
            map_on [i] = 8'd0;
        end

        repeat (10) @(posedge clk);
        rst_n = 1;
        // 复位后 DUT 要先跑完 S_INIT_CLEAR(256 拍刷直方图 RAM)才能开始统计,
        // 等够 300 拍再送第一帧, 否则帧头几百个像素会被"清零状态"吃掉。
        repeat (300) @(posedge clk);

        send_scene();     // 帧1: 建立直方图
        blank(120);       // 让 FSM 进到 S_READ 中段(此时直方图还没被 S_CLEAR 清掉)

        $display("");
        $display("--- DEBUG (frame1 S_READ 期间的内视) ---");
        $display("  state_off=%0d  state_on=%0d   (2=S_READ)", dut_off.state, dut_on.state);
        $display("  excess_on=%0d  clip_add(on)=%0d  clip_rem(on)=%0d",
                 dut_on.excess, dut_on.clip_add, dut_on.clip_rem);
        $display("  hist_off[59..61]  = %0d %0d %0d",
                 dut_off.u_ram_his.mem[59],  dut_off.u_ram_his.mem[60],  dut_off.u_ram_his.mem[61]);
        $display("  hist_off[199..201]= %0d %0d %0d",
                 dut_off.u_ram_his.mem[199], dut_off.u_ram_his.mem[200], dut_off.u_ram_his.mem[201]);
        $display("  hist_on [199..201]= %0d %0d %0d",
                 dut_on.u_ram_his.mem[199],  dut_on.u_ram_his.mem[200],  dut_on.u_ram_his.mem[201]);

        blank(800);       // 消隐: 扫完 CDF + 清直方图
        send_ramp();      // 帧2: 量映射
        blank(50);

        $display("");
        $display("=== histogram_equ CLIP test : frame %0dx%0d ===", W, H);
        $display("    DUT_OFF: CLIP_DIV=1  (CLIP=4096 -> never clips)");
        $display("    DUT_ON : CLIP_DIV=64 (CLIP=64   -> clip + redistribute)");
        $display("");
        $display("   x  | no-clip | clip+redist");
        $display("------+---------+------------");
        for (i = 0; i < 256; i = i + 1) begin
            if (i < 6 || (i >= 58 && i <= 62) || (i >= 198 && i <= 202) || (i >= 253))
                $display("%5d | %7d | %11d", i, map_off[i], map_on[i]);
        end

        g_off = map_off[201] - map_off[199];
        g_on  = map_on [201] - map_on [199];

        $display("");
        $display("--- KEY METRICS ---");
        $display("wall noise gain (out[201]-out[199] over 2 input LSB):");
        $display("    no-clip = %0d  =>  %0d x per input LSB", g_off, g_off/2);
        $display("    clip    = %0d  =>  %0d x per input LSB", g_on,  g_on/2);
        $display("white point out[255] : no-clip=%0d   clip=%0d   (want 255)",
                 map_off[255], map_on[255]);
        $display("dark end out[0..3]   : no-clip=%0d,%0d,%0d,%0d   clip=%0d,%0d,%0d,%0d",
                 map_off[0],map_off[1],map_off[2],map_off[3],
                 map_on[0],map_on[1],map_on[2],map_on[3]);
        $display("");
        $finish;
    end
endmodule
