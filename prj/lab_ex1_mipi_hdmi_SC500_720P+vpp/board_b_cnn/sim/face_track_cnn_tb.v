//=============================================================================
// face_track_cnn_tb.v —— face_track_top 全链路集成验证
//-----------------------------------------------------------------------------
// 合成 4 帧 1280x720 流: 每个 10x10 块 = 金标准 x0 对应像素的常数块
// （ds10 块平均输出 = x0 逐位一致 → CNN 检出金标准框 [71 0 30 30]）
// 验证: ① 帧 0~2 OSD 透传（画框前）；② O_face_valid 脉冲 + 形心 (860,150)；
//      ③ 帧 3 画框: 边框像素 = 绿色，框内/框外 = 透传
// 运行（仓库根目录）:
//   vlog -work work_cnn .../cnn/*.v .../face_track_top.v .../osd_box_drawer.v sim/face_track_cnn_tb.v
//   vsim -c work_cnn.face_track_cnn_tb -do "run -all; quit -f"
//=============================================================================
`timescale 1ns/1ps

module face_track_cnn_tb;

    localparam IW=1280, IH=720, NFRAMES=4, NPX=IW*IH;
    localparam GREEN = 24'h00FF00;

    reg clk=0, rst_n=0;
    reg tvalid=0, tuser=0, tlast=0;
    reg [23:0] tdata=0;
    wire ovalid, ouser, olast;
    wire [23:0] odata;
    wire fvalid;
    wire [11:0] fx, fy;

    reg [7:0] img [0:27647];            // x0 金标准（3 平面列主序）
    integer x, y, f, cyc, errs, checks, face_pulses;
    integer got_x, got_y;
    integer px_cnt;

    face_track_top #(.IMG_WIDTH(IW), .IMG_HEIGHT(IH)) dut (
        .I_clk(clk), .I_rst_n(rst_n),
        .I_ycbcr_tvalid(1'b0), .I_ycbcr_tlast(1'b0), .I_ycbcr_tuser(1'b0),
        .I_y_tdata(8'd0), .I_cb_tdata(8'd0), .I_cr_tdata(8'd0),
        .I_disp_tvalid(tvalid), .I_disp_tlast(tlast), .I_disp_tuser(tuser),
        .I_disp_tdata(tdata),
        .O_disp_tvalid(ovalid), .O_disp_tlast(olast), .O_disp_tuser(ouser),
        .O_disp_tdata(odata),
        .O_face_x(fx), .O_face_y(fy), .O_face_valid(fvalid)
    );

    always #5 clk = ~clk;
    initial $readmemh("sim/cnn_data/x0_input.hex", img);

    // ---- 当前像素合成值: 块 (x/10, y/10) = x0 像素 (row=oy, col=ox)
    //      img 为列主序: idx = row + 72*col + 9216*ch ----
    function [23:0] pixval;
        input integer px, py;
        integer ox, oy;
        begin
            ox = px / 10;  oy = py / 10;
            pixval = {img[oy + 72*ox + 0*9216],
                      img[oy + 72*ox + 1*9216],
                      img[oy + 72*ox + 2*9216]};
        end
    endfunction

    initial begin
        rst_n=0; tvalid=0; tuser=0; tlast=0;
        repeat (5) @(posedge clk); rst_n=1; repeat (2) @(posedge clk);
        errs=0; checks=0; face_pulses=0;

        $display("=========================================================");
        $display(" face_track_top 全链路集成验证（4 帧 720p 合成流）");
        $display(" 期望: 帧0~2 透传; O_face=(860,150); 帧3 画绿框 [710,0]-[1010,300]");

        for (f=0; f<NFRAMES; f=f+1) begin
            tuser=1; @(posedge clk); tuser=0;         // 帧起始（提前 1 拍）
            for (y=0; y<IH; y=y+1) begin
                for (x=0; x<IW; x=x+1) begin
                    tdata  = pixval(x, y);
                    tvalid = 1'b1;
                    tlast  = (x == IW-1);
                    @(posedge clk);
                    @(negedge clk);

                    // ---- ① 帧 0: OSD 透传检查（画框前；16 切片引擎在帧 1 检出）----
                    if (f < 1) begin
                        if (ovalid === 1'b1) begin
                            checks = checks + 1;
                            if (odata !== tdata) begin
                                errs = errs + 1;
                                if (errs <= 5)
                                    $display("  FAIL 透传 f%0d(%0d,%0d): out=%h exp=%h", f, x, y, odata, tdata);
                            end
                        end
                    end else if (f >= 2) begin
                        // ---- ③ 帧 2~3: 画框检查（边框绿，框内/外透传）
                        //      16 切片引擎在帧 2 第 ~30 行锁定框 → 帧 2 取第 150 行样本，
                        //      帧 3 任意行皆可（框保持 15 帧）----
                        if (ovalid === 1'b1) begin
                            checks = checks + 1;
                            if ((f == 3 && x == 711 && y == 1)   ||  // 上边（帧3）
                                (x == 712  && y == 300) ||          // 左边（行号 > 锁定行）
                                (x == 1009 && y == 300)) begin      // 右边
                                if (odata !== GREEN) begin
                                    errs = errs + 1;
                                    $display("  FAIL 边框(%0d,%0d): out=%h exp=绿 | box_en=%b box=(%0d,%0d)-(%0d,%0d) cur=(%0d,%0d) hit=%b",
                                             x, y, odata, dut.u_osd_box_drawer.box_enable,
                                             dut.u_osd_box_drawer.box_x1, dut.u_osd_box_drawer.box_y1,
                                             dut.u_osd_box_drawer.box_x2, dut.u_osd_box_drawer.box_y2,
                                             dut.u_osd_box_drawer.cur_x, dut.u_osd_box_drawer.cur_y,
                                             dut.u_osd_box_drawer.hit_border);
                                end
                            end else if ((x == 750 && y == 150) ||   // 框内
                                         (x == 100 && y == 100)) begin // 框外
                                if (odata !== tdata) begin
                                    errs = errs + 1;
                                    $display("  FAIL 非边框(%0d,%0d): out=%h exp=%h", x, y, odata, tdata);
                                end
                            end
                        end
                    end

                    // ---- ② O_face 脉冲与形心 ----
                    if (fvalid === 1'b1) begin
                        face_pulses = face_pulses + 1;
                        got_x = fx; got_y = fy;
                        $display("  O_face_valid: (%0d, %0d) @帧%0d 像素%0d", fx, fy, f, y*IW+x);
                    end
                end
            end
            tvalid=0; tlast=0;
            // ---- 帧间消隐（真实视频有场消隐；ds10 末条纹排空需 ~512 拍）----
            for (cyc=0; cyc<2000; cyc=cyc+1) begin
                @(posedge clk);
                if (fvalid === 1'b1) begin
                    face_pulses = face_pulses + 1;
                    got_x = fx; got_y = fy;
                    $display("  O_face_valid: (%0d, %0d) @帧%0d 消隐期", fx, fy, f);
                end
            end
        end

        $display("---------------------------------------------------------");
        $display(" 透传/画框检查 %0d 项，O_face 脉冲 %0d 次", checks, face_pulses);
        if (errs > 0) $display(" RESULT: FAIL  -- %0d 项不符", errs);
        else if (face_pulses == 0) $display(" RESULT: FAIL  -- 未检出 O_face_valid");
        else if (got_x < 859 || got_x > 861 || got_y < 149 || got_y > 151) begin
            $display(" RESULT: FAIL  -- 形心 (%0d,%0d) ≠ (860,150)±1", got_x, got_y);
        end
        else $display(" RESULT: PASS  -- 全链路（透传/形心/画框）正确");
        $finish;
    end

endmodule
