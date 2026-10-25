`timescale 1ns / 1ps
// =============================================================================
// tb_ae_path.v
//   验证 design_top_wrapper.v 里 "uivtc -> hdmi_mixer -> brightness_stats -> ae_auto"
//   这条自动曝光反馈链在真实时序下是否能正常出 frame_done / avg_y，以及闭环行为。
//   用法: vsim -c -do "run -all; quit -f" work.tb_ae_path
// =============================================================================
module tb_ae_path;

    localparam real PIX_CLK_NS = 13.468;    // 74.25MHz (1650x750@60)

    reg         clk = 1'b0;
    reg         rst_n = 1'b0;

    always #(PIX_CLK_NS/2.0) clk = ~clk;

    // ---------------- VTC ----------------
    wire        vtc_vs, vtc_hs, vtc_de, vtc_user, vtc_last;

    uivtc #(
        .H_ActiveSize ( 1280 ),
        .H_FrameSize  ( 1650 ),
        .H_SyncStart  ( 1390 ),
        .H_SyncEnd    ( 1430 ),
        .V_ActiveSize ( 720  ),
        .V_FrameSize  ( 750  ),
        .V_SyncStart  ( 725  ),
        .V_SyncEnd    ( 730  )
    ) u_hdmi_vtc (
        .I_vtc_rstn    ( rst_n   ),
        .I_vtc_clk     ( clk     ),
        .O_vtc_vs      ( vtc_vs   ),
        .O_vtc_hs      ( vtc_hs   ),
        .O_vtc_de_valid( vtc_de   ),
        .O_vtc_user    ( vtc_user ),
        .O_vtc_last    ( vtc_last )
    );

    // ---------------- 混合器(画面来源 = DDR 回读) ----------------
    reg  [23:0] disp_pix = 24'h808080;      // 可以由 TB 改, 模拟闭环

    wire        hdmi_de;
    wire [23:0] hdmi_data;

    hdmi_mixer #(
        .H_OFFSET   ( 0    ),
        .V_OFFSET   ( 0    ),
        .IMG_WIDTH  ( 1280 ),
        .IMG_HEIGHT ( 720  ),
        .DEBUG_MODE ( 0    )
    ) u_hdmi_mixer (
        .I_clk           ( clk        ),
        .I_rst_n         ( rst_n      ),
        .I_video_vsync   ( vtc_vs     ),
        .I_video_hsync   ( vtc_hs     ),
        .I_video_de      ( vtc_de     ),
        .I_video_user    ( vtc_user   ),
        .I_video_last    ( vtc_last   ),
        .I_debug_status  ( 4'd0       ),
        .O_video_rd_en   (            ),
        .I_video_rd_data ( disp_pix   ),
        .O_hdmi_vsync    (            ),
        .O_hdmi_hsync    (            ),
        .O_hdmi_de       ( hdmi_de    ),
        .O_hdmi_data     ( hdmi_data  )
    );

    // ---------------- user/last 延迟 3 拍 (与 design_top_wrapper 一致) ----------------
    reg user_d1, user_d2, user_d3;
    reg last_d1, last_d2, last_d3;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            user_d1 <= 1'b0; user_d2 <= 1'b0; user_d3 <= 1'b0;
            last_d1 <= 1'b0; last_d2 <= 1'b0; last_d3 <= 1'b0;
        end else begin
            user_d1 <= vtc_user; user_d2 <= user_d1; user_d3 <= user_d2;
            last_d1 <= vtc_last; last_d2 <= last_d1; last_d3 <= last_d2;
        end
    end

    // ---------------- Y 提取 (与 design_top_wrapper 一致) ----------------
    wire [17:0] y_sum = hdmi_data[23:16] * 8'd54
                      + hdmi_data[15:8]  * 8'd183
                      + hdmi_data[7:0]   * 8'd18;
    wire [7:0]  y_pix = y_sum[15:8];

    // ---------------- 亮度统计 ----------------
    wire [7:0] avg_y;
    wire       frame_done;
    integer    fd_cnt = 0;
    integer    frame_cnt = 0;

    brightness_stats #(
        .IMG_WIDTH  (1280),
        .IMG_HEIGHT (720)
    ) u_brightness_stats (
        .I_clk         ( clk        ),
        .I_rst_n       ( rst_n      ),
        .I_tlast       ( last_d3    ),
        .I_tuser       ( user_d3    ),
        .I_y_tdata     ( y_pix      ),
        .I_tvalid      ( hdmi_de    ),
        .I_tready      ( 1'b1       ),
        .O_avg_y       ( avg_y      ),
        .O_frame_done  ( frame_done )
    );

    // 统计每帧的 user 个数
    always @(posedge clk) if (rst_n && user_d3) frame_cnt <= frame_cnt + 1;
    always @(posedge clk) if (rst_n && frame_done) fd_cnt <= fd_cnt + 1;

    // 检查每次 frame_done 时的 avg_y
    always @(posedge clk) if (rst_n && frame_done)
        $display("[%0t] frame_done #%0d  avg_y=%0d  (disp_pix=%06h, 期望 ~%0d)",
                 $time, fd_cnt+1, avg_y, disp_pix, (disp_pix[23:16]*54 + disp_pix[15:8]*183 + disp_pix[7:0]*18) >> 8);

    // ---------------- 闭环: ae_auto -> 模拟传感器 ----------------
    wire [15:0] ae_out, ag_out;
    wire        ae_req;

    ae_auto #(
        .TARGET_Y (90),
        .AE_MAX   (1990),
        .AE_MIN   (4),
        .AE_INIT  (500),
        .HYST     (20),
        .KP       (1),
        .STEP_MAX (30),
        .AG_VALUE (80),
        .UPDATE_HOLD (3)
    ) u_ae_auto (
        .I_clk        ( clk        ),
        .I_rst_n      ( rst_n      ),
        .I_enable     ( 1'b1       ),
        .I_avg_y      ( avg_y      ),
        .I_frame_done ( frame_done ),
        .I_cfg_done   ( 1'b1       ),
        .O_ae         ( ae_out     ),
        .O_ag         ( ag_out     ),
        .O_ae_req     ( ae_req     )
    );

    // 被控对象: 曝光 -> 亮度   (线性: Y = 50000 / ae, 并夹到 0..255, 3 帧延迟)
    //   ae=500 -> Y=100;  ae=1990 -> Y=25;  ae=4 -> Y=255(饱和)
    reg [15:0] ae_p0, ae_p1, ae_p2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin ae_p0 <= 16'd500; ae_p1 <= 16'd500; ae_p2 <= 16'd500; end
        else begin ae_p0 <= ae_out; ae_p1 <= ae_p0; ae_p2 <= ae_p1; end
    end

    integer plant_y;
    always @(posedge frame_done) begin
        // 每个统计帧更新一次画面亮度
        plant_y = (ae_p2 == 0) ? 255 : (50000 / ae_p2);
        if (plant_y > 255) plant_y = 255;
        disp_pix <= {plant_y[7:0], plant_y[7:0], plant_y[7:0]};
        $display("    [plant] ae=%0d -> Y=%0d", ae_p2, plant_y);
    end

    // ---------------- 主流程 ----------------
    integer k;
    initial begin
        #200;
        rst_n = 1'b1;
        $display("=== tb_ae_path start ===");

        // 跑 8 帧
        for (k = 0; k < 8; k = k + 1) begin
            @(posedge user_d3);
            $display("[%0t] frame %0d : user_d3 pulse; line-phase  avg_y=%0d frame_done_cnt=%0d",
                     $time, k, avg_y, fd_cnt);
        end
        repeat (20) @(posedge clk);
        $display("=== 结果: user 脉冲=%0d, frame_done=%0d, 最后 avg_y=%0d, ae=%0d ===",
                 frame_cnt, fd_cnt, avg_y, ae_out);
        if (fd_cnt == 0) $display("*** FAIL: frame_done 从来没出现 -> 自动曝光永远不会更新 ***");
        else             $display("*** frame_done 正常输出 ***");
        $finish;
    end

endmodule
