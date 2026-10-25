`timescale 1ns / 1ps
//=============================================================================
// tb_osd_box_drawer.v - self-checking test for osd_box_drawer
//-----------------------------------------------------------------------------
//   Covers: pixel-coordinate tracking, 128x72 -> 1280x720 scaling, the 27-cell
//   X/Y/W/H text, the 3-pixel border, right/bottom clipping, rejection of
//   degenerate detections (board B "no face" report), and the frame hold timer.
//
//   2026-10-25:FIT_MODE 引入后两种裁剪策略都要测
//     dut      / dut_raw  : FIT_MODE=0（旧行为：右下硬裁），原有全部检查保持不变
//     dut_fit             : FIT_MODE=1（新默认：保尺寸、整框平移进屏幕）
//=============================================================================
module tb_osd_box_drawer;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg tvalid = 1'b0;
    reg tuser = 1'b0;
    reg tlast = 1'b0;
    reg [23:0] tdata = 24'h123456;
    reg face_valid = 1'b0;
    reg [7:0] face_x = 8'd0, face_y = 8'd0, face_w = 8'd0, face_h = 8'd0;
    wire o_valid, o_user, o_last;
    wire [23:0] o_data;
    reg [8*27-1:0] expected_text     = "X:0440 Y:0200 W:0400 H:0320"; // 模式0：HDMI 屏幕像素坐标
    reg [8*27-1:0] expected_raw_text = "X:0044 Y:0020 W:0040 H:0032"; // 模式1：板 B 原始格坐标
    integer i;

    always #5 clk = ~clk;

    // 生产配置（旧裁剪策略，FIT_MODE=0）：读数显示 HDMI 屏幕上的真实像素坐标
    // SHOW_RAW_LINE=1 只在这条实例上打开，用来验证第二行读数
    osd_box_drawer #(
        .IN_WIDTH(1280), .IN_HEIGHT(720), .SCALE_FACTOR(10),
        .LINE_THICK(3), .HOLD_FRAMES(15), .MIN_WH(8'd2),
        .FIT_MODE(2'd0), .SHOW_RAW_LINE(1),
        .READOUT_RAW_CELLS(0)
    ) dut (
        .I_clk(clk), .I_rst_n(rst_n),
        .I_tvalid(tvalid), .I_tuser(tuser), .I_tlast(tlast), .I_tdata(tdata),
        .I_face_valid(face_valid), .I_face_x(face_x), .I_face_y(face_y),
        .I_face_w(face_w), .I_face_h(face_h),
        .O_tvalid(o_valid), .O_tuser(o_user), .O_tlast(o_last), .O_tdata(o_data)
    );

    // 调试配置：读数显示板 B 的原始格坐标（同一套激励，只验读数内容）
    osd_box_drawer #(
        .IN_WIDTH(1280), .IN_HEIGHT(720), .SCALE_FACTOR(10),
        .LINE_THICK(3), .HOLD_FRAMES(15), .MIN_WH(8'd2),
        .FIT_MODE(2'd0),
        .READOUT_RAW_CELLS(1)
    ) dut_raw (
        .I_clk(clk), .I_rst_n(rst_n),
        .I_tvalid(tvalid), .I_tuser(tuser), .I_tlast(tlast), .I_tdata(tdata),
        .I_face_valid(face_valid), .I_face_x(face_x), .I_face_y(face_y),
        .I_face_w(face_w), .I_face_h(face_h),
        .O_tvalid(), .O_tuser(), .O_tlast(), .O_tdata()
    );

    // 新默认策略（FIT_MODE=1）：保尺寸、整框平移进屏幕
    osd_box_drawer #(
        .IN_WIDTH(1280), .IN_HEIGHT(720), .SCALE_FACTOR(10),
        .LINE_THICK(3), .HOLD_FRAMES(15), .MIN_WH(8'd2),
        .FIT_MODE(2'd1),
        .READOUT_RAW_CELLS(0)
    ) dut_fit (
        .I_clk(clk), .I_rst_n(rst_n),
        .I_tvalid(tvalid), .I_tuser(tuser), .I_tlast(tlast), .I_tdata(tdata),
        .I_face_valid(face_valid), .I_face_x(face_x), .I_face_y(face_y),
        .I_face_w(face_w), .I_face_h(face_h),
        .O_tvalid(), .O_tuser(), .O_tlast(), .O_tdata()
    );

    // FIT_MODE=1 + 显示侧限幅 20x20 格：验证"围绕中心收缩"不会把脸挤出框外
    osd_box_drawer #(
        .IN_WIDTH(1280), .IN_HEIGHT(720), .SCALE_FACTOR(10),
        .LINE_THICK(3), .HOLD_FRAMES(15), .MIN_WH(8'd2),
        .FIT_MODE(2'd1), .MAX_W_CELLS(8'd20), .MAX_H_CELLS(8'd20),
        .READOUT_RAW_CELLS(0)
    ) dut_cap (
        .I_clk(clk), .I_rst_n(rst_n),
        .I_tvalid(tvalid), .I_tuser(tuser), .I_tlast(tlast), .I_tdata(tdata),
        .I_face_valid(face_valid), .I_face_x(face_x), .I_face_y(face_y),
        .I_face_w(face_w), .I_face_h(face_h),
        .O_tvalid(), .O_tuser(), .O_tlast(), .O_tdata()
    );

    // FIT_MODE=1 + SHRINK_LOG2=1（×0.5，围绕中心）：把框往回收但不让脸偏
    osd_box_drawer #(
        .IN_WIDTH(1280), .IN_HEIGHT(720), .SCALE_FACTOR(10),
        .LINE_THICK(3), .HOLD_FRAMES(15), .MIN_WH(8'd2),
        .FIT_MODE(2'd1), .SHRINK_LOG2(2'd1),
        .READOUT_RAW_CELLS(0)
    ) dut_shr (
        .I_clk(clk), .I_rst_n(rst_n),
        .I_tvalid(tvalid), .I_tuser(tuser), .I_tlast(tlast), .I_tdata(tdata),
        .I_face_valid(face_valid), .I_face_x(face_x), .I_face_y(face_y),
        .I_face_w(face_w), .I_face_h(face_h),
        .O_tvalid(), .O_tuser(), .O_tlast(), .O_tdata()
    );

    task set_face;
        input [7:0] fx, fy, fw, fh;
        begin
            @(negedge clk);
            face_x = fx; face_y = fy; face_w = fw; face_h = fh;
            face_valid = 1'b1;
            @(posedge clk); #1;
            face_valid = 1'b0;
        end
    endtask

    task pulse_frame_start;
        begin
            @(negedge clk); tvalid = 1'b1; tuser = 1'b1; tlast = 1'b1;
            @(posedge clk); #1;
        end
    endtask

    task check_pixel;
        input integer px, py;
        input user_mark, last_mark;
        input [23:0] expected_pixel;
        begin
            @(negedge clk);
            dut.cur_x = px;
            dut.cur_y = py;
            tvalid = 1'b1; tuser = user_mark; tlast = last_mark;
            tdata = 24'h123456;
            @(posedge clk); #1;
            if (o_valid !== 1'b1 || o_user !== user_mark || o_last !== last_mark || o_data !== expected_pixel)
                $fatal(1, "AXI pixel/marker mismatch at x=%0d y=%0d: valid=%b user=%b last=%b data=%h",
                       px, py, o_valid, o_user, o_last, o_data);
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        // ---- pixel coordinate tracking -------------------------------------
        check_pixel(77, 20, 1'b1, 1'b0, 24'h123456);
        if (dut.cur_x !== 11'd1) $fatal(1, "SOF pixel did not advance the next x coordinate to 1");
        check_pixel(1, 0, 1'b0, 1'b1, 24'h123456);
        @(negedge clk); tvalid = 1'b0; tuser = 1'b0; tlast = 1'b0;
        @(posedge clk); #1;
        if (o_valid || o_user || o_last || o_data !== 24'd0)
            $fatal(1, "Invalid input cycle was not propagated as an empty output cycle");

        // ---- scaling + coordinate readout ----------------------------------
        //   box_* = ×10 后的 HDMI 像素框；dut 是模式0（显示屏幕坐标），dut_raw 是模式1（显示原始格）
        set_face(8'd44, 8'd20, 8'd40, 8'd32);
        if (!dut.box_enable || dut.box_x1 !== 11'd440 || dut.box_y1 !== 10'd200 ||
            dut.box_x2 !== 11'd840 || dut.box_y2 !== 10'd520 ||
            dut.display_x !== 12'd440 || dut.display_y !== 12'd200 ||
            dut.display_w !== 12'd400 || dut.display_h !== 12'd320)
            $fatal(1, "128x72 face coordinates were not scaled to 1280x720 / screen readout wrong");
        if (dut_raw.display_x !== 12'd44 || dut_raw.display_y !== 12'd20 ||
            dut_raw.display_w !== 12'd40 || dut_raw.display_h !== 12'd32)
            $fatal(1, "raw-cell readout (debug mode 1) wrong");

        for (i = 0; i < 27; i = i + 1) begin
            dut.cur_x     = 11'd832 + (i * 16);
            dut.cur_y     = 10'd16;
            dut_raw.cur_x = 11'd832 + (i * 16);
            dut_raw.cur_y = 10'd16;
            #1;
            if (dut.text_char !== expected_text[(26-i)*8 +: 8])
                $fatal(1, "screen-coord text char %0d mismatch: got %c expected %c",
                       i, dut.text_char, expected_text[(26-i)*8 +: 8]);
            if (dut_raw.text_char !== expected_raw_text[(26-i)*8 +: 8])
                $fatal(1, "raw-cell text char %0d mismatch: got %c expected %c",
                       i, dut_raw.text_char, expected_raw_text[(26-i)*8 +: 8]);
        end

        // ---- 第 2 行读数 = 板 B 送来的原始格坐标（0~255，SHOW_RAW_LINE=1）----
        for (i = 0; i < 27; i = i + 1) begin
            dut.cur_x = 11'd832 + (i * 16);
            dut.cur_y = 10'd16 + 10'd20;
            #1;
            if (dut.text_char !== expected_raw_text[(26-i)*8 +: 8])
                $fatal(1, "raw-cell text (line 2) char %0d mismatch: got %c expected %c",
                       i, dut.text_char, expected_raw_text[(26-i)*8 +: 8]);
        end

        // ---- border geometry -----------------------------------------------
        check_pixel(439, 210, 1'b0, 1'b0, 24'h123456);
        check_pixel(440, 210, 1'b0, 1'b0, 24'h00FF00);
        check_pixel(442, 210, 1'b0, 1'b0, 24'h00FF00);
        check_pixel(443, 210, 1'b0, 1'b0, 24'h123456);
        check_pixel(839, 210, 1'b0, 1'b0, 24'h00FF00);
        check_pixel(840, 210, 1'b0, 1'b0, 24'h123456);
        check_pixel(500, 199, 1'b0, 1'b0, 24'h123456);
        check_pixel(500, 200, 1'b0, 1'b0, 24'h00FF00);
        check_pixel(500, 519, 1'b0, 1'b0, 24'h00FF00);
        check_pixel(500, 520, 1'b0, 1'b0, 24'h123456);

        // ---- right/bottom clipping -----------------------------------------
        //   模式0 的读数显示"屏幕上实际画出来的框"，所以被裁到 80x70
        set_face(8'd120, 8'd65, 8'd20, 8'd20);
        if (dut.box_x1 !== 11'd1200 || dut.box_y1 !== 10'd650 ||
            dut.box_x2 !== 11'd1280 || dut.box_y2 !== 10'd720 ||
            dut.display_w !== 12'd80 || dut.display_h !== 12'd70)
            $fatal(1, "Right/bottom edge clipping did not match the drawn half-open box");

        // ---- degenerate detections are IGNORED, the good box is kept -------
        //   Board B reports "no face this frame" as w=h=0; those frames must
        //   not replace (or reset the hold of) the latched box.
        set_face(8'd10, 8'd10, 8'd0, 8'd0);
        if (!dut.box_enable || dut.box_x1 !== 11'd1200 || dut.box_y1 !== 10'd650 ||
            dut.hold_cnt !== 8'd15)
            $fatal(1, "Zero-size detection replaced the latched box or reloaded the hold");
        set_face(8'd10, 8'd10, 8'd1, 8'd1);
        if (!dut.box_enable || dut.box_x1 !== 11'd1200)
            $fatal(1, "Sub-MIN_WH detection replaced the latched box");

        // ---- a non-degenerate box outside the screen is ignored too --------
        set_face(8'd128, 8'd72, 8'd20, 8'd20);
        if (!dut.box_enable || dut.box_x1 !== 11'd1200)
            $fatal(1, "Off-screen detection replaced the latched box");

        // ---- frame hold timer ----------------------------------------------
        for (i = 0; i < 14; i = i + 1) begin
            pulse_frame_start;
            if (!dut.box_enable) $fatal(1, "Box cleared before the 15-frame hold elapsed");
        end
        pulse_frame_start;
        if (dut.box_enable) $fatal(1, "Box did not clear after the 15-frame hold");

        // ---- a fresh detection re-arms the overlay --------------------------
        set_face(8'd44, 8'd20, 8'd40, 8'd32);
        if (!dut.box_enable || dut.box_x1 !== 11'd440) $fatal(1, "Box was not re-armed");

        // =====================================================================
        // 2026-10-25  FIT_MODE=1（新默认）：保尺寸 / 保中心，整框平移进屏幕
        // ---------------------------------------------------------------------
        //   同样一份 (120,65,20,20)：框在屏幕上占 (1080,520)-(1280,720)，
        //   **W/H 仍然是 200x200（板 B 报的尺寸），不再是 mode0 的 80x70 被切**。
        //   mode0 读数 W=80/H=70 是"被切掉一半"的指纹，mode1 不会出现。
        // =====================================================================

        // ① 框完全在画面内 -> 两种模式必须完全一致（不引入任何偏移）
        set_face(8'd44, 8'd20, 8'd40, 8'd32);
        if (dut_fit.box_x1 !== 11'd440 || dut_fit.box_y1 !== 10'd200 ||
            dut_fit.box_x2 !== 11'd840 || dut_fit.box_y2 !== 10'd520)
            $fatal(1, "FIT_MODE=1 moved a box that already fit on screen");

        // ② 会越界 -> 保尺寸、平移到屏幕内（尺寸 = 200x200，不是 80x70）
        set_face(8'd120, 8'd65, 8'd20, 8'd20);
        if (dut_fit.box_x1 !== 11'd1080 || dut_fit.box_y1 !== 10'd520 ||
            dut_fit.box_x2 !== 11'd1280 || dut_fit.box_y2 !== 10'd720 ||
            dut_fit.display_w !== 12'd200 || dut_fit.display_h !== 12'd200)
            $fatal(1, "FIT_MODE=1 did not keep the reported size when fitting on screen");

        // ③ 尺寸限幅：40x32 格 -> 收到 20x20 格。
        //    被夹过 w/h 时框锚在报告的 x1/y1 上（假中心不参与），
        //    框 = (440,200)-(640,400)
        //    （SHRINK 那种"没被夹"的情况仍围绕真中心收，见 ⑥）
        set_face(8'd44, 8'd20, 8'd40, 8'd32);
        if (dut_cap.box_x1 !== 11'd440 || dut_cap.box_y1 !== 10'd200 ||
            dut_cap.box_x2 !== 11'd640 || dut_cap.box_y2 !== 10'd400)
            $fatal(1, "MAX_*_CELLS clamp did not apply the clamped size");

        // ④ 越界 + 限幅同时生效：先围绕中心收缩，再平移进屏幕
        //    框 20x20 格 @ (120,65) -> cx=1300(超屏)->夹到 1280，cy=750->夹到 720
        //    x1 = 1280-100 = 1180, y1 = 720-100 = 620
        //    再平移：1180+200 > 1280 -> x1=1080 ；620+200 > 720 -> y1=520
        set_face(8'd120, 8'd65, 8'd20, 8'd20);
        if (dut_cap.box_x1 !== 11'd1080 || dut_cap.box_y1 !== 10'd520 ||
            dut_cap.box_x2 !== 11'd1280 || dut_cap.box_y2 !== 10'd720)
            $fatal(1, "FIT_MODE=1 + clamp combination wrong");

        // ⑤ 板 B 报 h=255（8 位上限）-> 先按 SANITIZE 收回 1.25w，再夹到屏幕内
        //    50x255 格 @ (40,10) -> w=500px, h=2550px -> h 收回 625px
        //    框 = (400,95)-(900,720)
        set_face(8'd40, 8'd10, 8'd50, 8'd255);
        if (dut_fit.box_y1 !== 10'd95 || dut_fit.box_y2 !== 10'd720)
            $fatal(1, "Oversized h was not sanitised/clamped to the screen height");

        // ⑥ SHRINK_LOG2=1（×0.5，围绕中心）：
        //    40x32 格 @ (44,20) -> 400x320 px，中心 (640,360)
        //    收缩后 200x160 -> (540,280)-(740,440)
        set_face(8'd44, 8'd20, 8'd40, 8'd32);
        if (dut_shr.box_x1 !== 11'd540 || dut_shr.box_y1 !== 10'd280 ||
            dut_shr.box_x2 !== 11'd740 || dut_shr.box_y2 !== 10'd440)
            $fatal(1, "SHRINK_LOG2 did not contract the box around its centre");

        // ⑦ SANITIZE（默认开）：h > 1.5w 时按 1.25w 重算
        //    20x120 格 @ (30,10) -> w=200px, h=1200px -> 收回 h=250px
        //    h 被夹过 -> 纵向锚在 y1=100；框 = (300,100)-(500,350)，
        //    完全没有"整幅高"的框
        set_face(8'd30, 8'd10, 8'd20, 8'd120);
        if (dut_fit.box_x1 !== 11'd300 || dut_fit.box_y1 !== 10'd100 ||
            dut_fit.box_x2 !== 11'd500 || dut_fit.box_y2 !== 10'd350)
            $fatal(1, "SANITIZE did not cap h to 1.25*w");

        $display("PASS: osd_box_drawer scaling, digits, clipping, degenerate reject, border, hold timer, FIT_MODE");
        $finish;
    end
endmodule
