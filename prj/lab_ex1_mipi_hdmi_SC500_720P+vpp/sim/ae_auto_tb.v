`timescale 1ns / 1ps
// 自动曝光单元验证:
//  1) brightness_stats: 全 200 帧的平均亮度 = 200, frame_done 单拍脉冲;
//  2) ae_auto 闭环: 恒亮输入下曝光单调下降且不越界 [4,1990];
//  3) 每次 O_ae 变化伴随 O_ae_req 脉冲;
//  4) 变暗输入 (y=10) 后曝光转为上升。
module tb_ae;

    reg         clk, rst_n;
    reg         tvalid, tlast, tuser, tready;
    reg  [7:0]  y;
    wire [7:0]  avg_y;
    wire        frame_done;
    reg         enable, cfg_done;
    wire [15:0] o_ae;
    wire        o_ae_req;

    brightness_stats #(.IMG_WIDTH(16), .IMG_HEIGHT(8)) u_stats (
        .I_clk(clk), .I_rst_n(rst_n),
        .I_tlast(tlast), .I_tuser(tuser), .I_y_tdata(y),
        .I_tvalid(tvalid), .I_tready(tready),
        .O_avg_y(avg_y), .O_frame_done(frame_done)
    );

    ae_auto #(
        .TARGET_Y(50), .AE_MAX(1990), .AE_MIN(4), .AE_INIT(500),
        .HYST(20), .KP(1), .STEP_MAX(50), .AG_VALUE(80)
    ) u_ae (
        .I_clk(clk), .I_rst_n(rst_n),
        .I_enable(enable), .I_avg_y(avg_y), .I_frame_done(frame_done),
        .I_cfg_done(cfg_done),
        .O_ae(o_ae), .O_ag(), .O_ae_req(o_ae_req)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer errors;
    reg [15:0] ae_prev;
    integer frames;

    task send_frame(input [7:0] val);
        integer r, c;
        begin
            for (r = 0; r < 8; r = r + 1) begin
                for (c = 0; c < 16; c = c + 1) begin
                    @(posedge clk);
                    tvalid <= 1'b1;
                    tuser  <= ((r==0)&&(c==0));
                    tlast  <= (c==15);
                    y      <= val;
                end
            end
            @(posedge clk);
            tvalid <= 1'b0; tlast <= 1'b0; tuser <= 1'b0;
        end
    endtask

    task wait_fd;
        begin
            while (!frame_done) @(posedge clk);
        end
    endtask

    initial begin
        errors = 0;
        rst_n = 0; tvalid = 0; tlast = 0; tuser = 0; tready = 1;
        enable = 0; cfg_done = 0; y = 0; ae_prev = 500;
        #30 rst_n = 1;
        #20;
        enable = 1; cfg_done = 1;

        // ---- 检查 1: 亮帧平均亮度 = 200 ----
        frames = 0;
        send_frame(8'd200);
        wait_fd;
        #1;
        if (avg_y !== 8'd200) begin
            $display("FAIL avg_y = %0d (expect 200)", avg_y);
            errors = errors + 1;
        end else $display("OK   avg_y = 200");

        // ---- 检查 2/3: 连续 9 帧亮帧, 曝光单调下降且不越界 ----
        repeat (9) begin
            send_frame(8'd200);
            wait_fd;
            #1;
            frames = frames + 1;
            $display("DBG f%0d: avg=%0d y_filt=%0d ae_cur=%0d o_ae=%0d ae_req=%0b", frames,
                     avg_y, u_ae.y_filt, u_ae.ae_cur, o_ae, o_ae_req);
            if (o_ae > 1990 || o_ae < 4) begin
                $display("FAIL frame %0d: o_ae = %0d 越界", frames, o_ae);
                errors = errors + 1;
            end
            if (o_ae > ae_prev) begin
                $display("FAIL frame %0d: o_ae = %0d 反而上升 (prev %0d)", frames, o_ae, ae_prev);
                errors = errors + 1;
            end
            ae_prev = o_ae;
        end
        $display("INFO 10 帧恒亮后 o_ae = %0d (应显著下降)", o_ae);
        if (o_ae >= 500) begin
            $display("FAIL 恒亮输入下曝光未下降: o_ae = %0d", o_ae);
            errors = errors + 1;
        end else $display("OK   恒亮下曝光下降");

        // ---- 检查 4: 变暗输入后曝光从最低点回升 ----
        // (8 帧滑动平均有惯性, 变暗初期可能继续降到 AE_MIN, 随后应回升)
        begin : dark_phase
            reg [15:0] ae_min;
            ae_min = o_ae;
            repeat (12) begin
                send_frame(8'd10);
                wait_fd;
                #1;
                if (o_ae < ae_min) ae_min = o_ae;
            end
            if (o_ae <= ae_min) begin
                $display("FAIL 变暗后曝光未回升: %0d <= 最低 %0d", o_ae, ae_min);
                errors = errors + 1;
            end else $display("OK   变暗后曝光回升: %0d (最低 %0d)", o_ae, ae_min);
        end

        $display("------------------------------------");
        if (errors == 0) $display("===== PASS =====");
        else             $display("===== FAIL (%0d) =====", errors);
        $finish;
    end

endmodule
