`timescale 1ns / 1ps
// =============================================================================
// tb_ae_full.v
//   完整复刻 design_top_wrapper.v 的自动曝光闭环, 含真实跨时钟域 (75MHz 像素 ->
//   23.81MHz 24M 域), 用来观察闭环最终稳定在哪里。
// =============================================================================
module tb_ae_full;

    localparam real PIX_NS = 13.468;   // 74.25MHz
    localparam real SYS_NS = 42.0;     // 23.81MHz (pll_clk_24m)

    reg clk_pix = 1'b0;
    reg clk_24m = 1'b0;
    reg rst_n   = 1'b0;

    always #(PIX_NS/2.0) clk_pix = ~clk_pix;
    always #(SYS_NS/2.0) clk_24m = ~clk_24m;

    // ---------------- 画面源 = DDR 回读 (可在帧边界改变) ----------------
    reg  [23:0] disp_pix = 24'h808080;

    wire        vtc_vs, vtc_hs, vtc_de, vtc_user, vtc_last;
    wire        hdmi_de;
    wire [23:0] hdmi_data;

    uivtc #(
        .H_ActiveSize ( 1280 ), .H_FrameSize ( 1650 ),
        .H_SyncStart  ( 1390 ), .H_SyncEnd   ( 1430 ),
        .V_ActiveSize ( 720  ), .V_FrameSize ( 750  ),
        .V_SyncStart  ( 725  ), .V_SyncEnd   ( 730  )
    ) u_hdmi_vtc (
        .I_vtc_rstn    ( rst_n   ),
        .I_vtc_clk     ( clk_pix ),
        .O_vtc_vs      ( vtc_vs   ),
        .O_vtc_hs      ( vtc_hs   ),
        .O_vtc_de_valid( vtc_de   ),
        .O_vtc_user    ( vtc_user ),
        .O_vtc_last    ( vtc_last )
    );

    hdmi_mixer #(
        .H_OFFSET(0), .V_OFFSET(0), .IMG_WIDTH(1280), .IMG_HEIGHT(720), .DEBUG_MODE(0)
    ) u_hdmi_mixer (
        .I_clk(clk_pix), .I_rst_n(rst_n),
        .I_video_vsync(vtc_vs), .I_video_hsync(vtc_hs), .I_video_de(vtc_de),
        .I_video_user(vtc_user), .I_video_last(vtc_last),
        .I_debug_status(4'd0), .O_video_rd_en(), .I_video_rd_data(disp_pix),
        .O_hdmi_vsync(), .O_hdmi_hsync(), .O_hdmi_de(hdmi_de), .O_hdmi_data(hdmi_data)
    );

    // user/last 延迟 3 拍
    reg u1,u2,u3,l1,l2,l3;
    always @(posedge clk_pix or negedge rst_n) begin
        if (!rst_n) begin u1<=0;u2<=0;u3<=0;l1<=0;l2<=0;l3<=0; end
        else begin u1<=vtc_user;u2<=u1;u3<=u2; l1<=vtc_last;l2<=l1;l3<=l2; end
    end

    wire [17:0] y_sum = hdmi_data[23:16]*8'd54 + hdmi_data[15:8]*8'd183 + hdmi_data[7:0]*8'd18;
    wire [7:0]  y_pix = y_sum[15:8];

    wire [7:0] avg_y_pix;
    wire       frame_done_pix;

    brightness_stats #(.IMG_WIDTH(1280), .IMG_HEIGHT(720)) u_bs (
        .I_clk(clk_pix), .I_rst_n(rst_n),
        .I_tlast(l3), .I_tuser(u3), .I_y_tdata(y_pix),
        .I_tvalid(hdmi_de), .I_tready(1'b1),
        .O_avg_y(avg_y_pix), .O_frame_done(frame_done_pix)
    );

    // ---------------- CDC: avg_y 两级同步 ----------------
    reg [7:0] S_avg_y_s1, S_avg_y_s2_r;
    always @(posedge clk_24m or negedge rst_n) begin
        if (!rst_n) begin S_avg_y_s1 <= 8'd0; S_avg_y_s2_r <= 8'd0; end
        else begin S_avg_y_s1 <= avg_y_pix; S_avg_y_s2_r <= S_avg_y_s1; end
    end
    wire [7:0] avg_y_s2 = S_avg_y_s2_r;

    // ---------------- CDC: frame_done 展宽 + 同步 + 边沿 ----------------
    reg [7:0] S_fd_ext;
    always @(posedge clk_pix or negedge rst_n) begin
        if (!rst_n)               S_fd_ext <= 8'd0;
        else if (frame_done_pix)  S_fd_ext <= 8'hFF;
        else if (S_fd_ext != 0)   S_fd_ext <= S_fd_ext - 1'b1;
    end
    wire S_fd_wide = |S_fd_ext;

    reg S_fd_s1, S_fd_s2, S_fd_s3;
    always @(posedge clk_24m or negedge rst_n) begin
        if (!rst_n) begin S_fd_s1<=0; S_fd_s2<=0; S_fd_s3<=0; end
        else begin S_fd_s1<=S_fd_wide; S_fd_s2<=S_fd_s1; S_fd_s3<=S_fd_s2; end
    end
    wire frame_done_24m = S_fd_s2 & ~S_fd_s3;

    // ---------------- AE ----------------
    wire [15:0] ae_out, ag_out;
    wire        ae_req;

    ae_auto #(
        .TARGET_Y(90), .AE_MAX(1990), .AE_MIN(4), .AE_INIT(500), .HYST(20),
        .KP(1), .STEP_MAX(30), .AG_VALUE(80), .UPDATE_HOLD(3)
    ) u_ae_auto (
        .I_clk(clk_24m), .I_rst_n(rst_n), .I_enable(1'b1),
        .I_avg_y(avg_y_s2), .I_frame_done(frame_done_24m), .I_cfg_done(1'b1),
        .O_ae(ae_out), .O_ag(ag_out), .O_ae_req(ae_req)
    );

    // ---------------- 被控对象: 曝光 -> 亮度, 4 帧延迟 ----------------
    //   Y = K/ae, K 选成 ae=1000 -> Y=90 (所以理想工作点是 ~1000)
    //   为了模拟"增益固定偏大、暗处仍偏亮"的真实传感器, 用两条曲线:
    //     ae < 200 : Y = 90 (传感器底噪/固定增益撑住, 不再是线性)
    //     ae >=200 : Y = 90000/ae
    reg [15:0] ae_d1, ae_d2, ae_d3, ae_d4;
    always @(posedge clk_24m or negedge rst_n) begin
        if (!rst_n) begin ae_d1<=500; ae_d2<=500; ae_d3<=500; ae_d4<=500; end
        else begin ae_d1<=ae_out; ae_d2<=ae_d1; ae_d3<=ae_d2; ae_d4<=ae_d3; end
    end

    integer plant_y;
    reg [15:0] ae_applied = 16'd500;

    always @(posedge frame_done_pix) begin
        ae_applied = ae_d4;
        if (ae_applied < 16'd200) plant_y = 90;      // 饱和平台
        else                      plant_y = 90000 / ae_applied;
        if (plant_y > 255) plant_y = 255;
        if (plant_y < 0)   plant_y = 0;
        disp_pix <= {plant_y[7:0], plant_y[7:0], plant_y[7:0]};
        $display("[%0t] frame@%0d  ae_applied=%0d  -> plant Y=%0d   (measured avg_y(24M)=%0d)",
                 $time, frame_cnt, ae_applied, plant_y, avg_y_s2);
    end

    integer frame_cnt = 0;
    always @(posedge clk_pix) if (rst_n && frame_done_pix) frame_cnt <= frame_cnt + 1;
    integer ae_updates = 0;
    always @(posedge clk_24m) if (rst_n && ae_req) ae_updates <= ae_updates + 1;

    integer k;
    initial begin
        #200 rst_n = 1'b1;
        $display("=== tb_ae_full start ===");
        // 跑 120 帧, 看闭环收敛(或跑飞)
        repeat (120) @(posedge frame_done_pix);
        $display("=== 结束: 帧数=%0d, ae=%0d, 最后 avg_y=%0d ===", frame_cnt, ae_out, avg_y_s2);
        $finish;
    end

endmodule
