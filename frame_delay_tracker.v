`timescale 1ns / 1ps
//=============================================================
// frame_delay_tracker.v
// “采集 → HDMI 显示”真实帧延迟测量（物理 DDR 页标签法）
//
//   1) CSI 帧首（CSI 时钟域）→ toggle → 三级同步 → DDR 时钟域事件；
//   2) DDR 域维护 32 位 ms_counter（按 DDR_CLK_HZ 分频）和 32 位 frame_seq；
//   3) video_in 写帧首时，把“该帧的采集时间戳/帧序号”绑定到实际写入的物理页；
//   4) video_out 显示帧首时，用实际读取的物理页索引取回标签，做 32 位模减法；
//   5) 结果经“请求/应答 toggle”握手送到 HDMI 像素域，供 delay_osd 显示。
//
// 说明：只跟踪 4 个物理页；页被复用时旧标签被覆盖。CSI 帧首与 DDR 写帧首
// 配不上对时，受影响页置无效，不输出伪造延迟（宁可不显示，也不显示错值）。
//=============================================================
module frame_delay_tracker #(
    parameter integer DDR_CLK_HZ = 66666667
)(
    input  wire       I_ddr_clk,
    input  wire       I_ddr_rst_n,
    input  wire       I_csi_clk,
    input  wire       I_csi_rst_n,
    input  wire       I_csi_frame_start,
    input  wire       I_write_frame_start,
    input  wire [1:0] I_write_page,
    input  wire       I_display_frame_start,
    input  wire [1:0] I_display_page,
    input  wire       I_pixel_clk,
    input  wire       I_pixel_rst_n,
    output reg        O_delay_valid,
    output reg  [3:0] O_delay_frames,
    output reg  [9:0] O_delay_ms,
    output reg        O_fps_valid,
    output reg  [9:0] O_fps_tenths
);

    localparam integer MS_DIVISOR = DDR_CLK_HZ / 1000;
    localparam [31:0] FPS_NUMERATOR = DDR_CLK_HZ * 32'd10;

    reg csi_start_d;
    reg csi_toggle;
    reg csi_sync1, csi_sync2, csi_sync3;
    wire capture_event = csi_sync2 ^ csi_sync3;

    reg [31:0] ms_div_cnt;
    reg [31:0] ms_counter;
    wire ms_tick = (ms_div_cnt == MS_DIVISOR - 1);
    wire [31:0] ms_now = ms_counter + (ms_tick ? 32'd1 : 32'd0);
    reg [31:0] frame_seq;
    wire [31:0] frame_seq_now = frame_seq + (capture_event ? 32'd1 : 32'd0);

    reg [31:0] ddr_cycle_counter;
    reg [31:0] last_capture_cycle;
    reg capture_seen;
    wire [31:0] capture_period_cycles = ddr_cycle_counter - last_capture_cycle;

    // A 32-cycle restoring divider keeps variable division out of the pixel path.
    reg fps_div_busy;
    reg [5:0] fps_div_count;
    reg [31:0] fps_dividend_shift;
    reg [31:0] fps_divisor;
    reg [31:0] fps_quotient;
    reg [32:0] fps_remainder;
    reg [9:0] fps_tenths_ddr;
    reg fps_valid_ddr;
    wire [32:0] fps_trial_remainder = {fps_remainder[31:0], fps_dividend_shift[31]};
    wire fps_trial_subtract = fps_trial_remainder >= {1'b0, fps_divisor};
    wire [31:0] fps_quotient_next = {fps_quotient[30:0], fps_trial_subtract};

    reg [31:0] capture_q_ms [0:3];
    reg [31:0] capture_q_seq [0:3];
    reg [1:0] capture_q_wr_ptr;
    reg [1:0] capture_q_rd_ptr;
    reg [2:0] capture_q_count;

    reg [3:0] page_valid;
    reg [31:0] page_capture_ms [0:3];
    reg [31:0] page_frame_seq [0:3];
    integer page_index;

    reg display_result_valid;
    reg [3:0] display_result_frames;
    reg [9:0] display_result_ms;
    reg [31:0] display_frame_age;
    reg [31:0] display_ms_age;
    wire selected_page_valid = page_valid[I_display_page];
    wire [31:0] selected_page_ms = page_capture_ms[I_display_page];
    wire [31:0] selected_page_seq = page_frame_seq[I_display_page];

    always @(posedge I_csi_clk or negedge I_csi_rst_n) begin
        if (!I_csi_rst_n) begin
            csi_start_d <= 1'b0;
            csi_toggle  <= 1'b0;
        end else begin
            csi_start_d <= I_csi_frame_start;
            if (I_csi_frame_start && !csi_start_d)
                csi_toggle <= ~csi_toggle;
        end
    end

    always @(posedge I_ddr_clk or negedge I_ddr_rst_n) begin
        if (!I_ddr_rst_n) begin
            csi_sync1 <= 1'b0;
            csi_sync2 <= 1'b0;
            csi_sync3 <= 1'b0;
        end else begin
            csi_sync1 <= csi_toggle;
            csi_sync2 <= csi_sync1;
            csi_sync3 <= csi_sync2;
        end
    end

    always @(posedge I_ddr_clk or negedge I_ddr_rst_n) begin
        if (!I_ddr_rst_n) begin
            ms_div_cnt <= 32'd0;
            ms_counter <= 32'd0;
            frame_seq  <= 32'd0;
            ddr_cycle_counter <= 32'd0;
            last_capture_cycle <= 32'd0;
            capture_seen <= 1'b0;
        end else begin
            ddr_cycle_counter <= ddr_cycle_counter + 32'd1;
            if (ms_tick) begin
                ms_div_cnt <= 32'd0;
                ms_counter <= ms_counter + 32'd1;
            end else begin
                ms_div_cnt <= ms_div_cnt + 32'd1;
            end
            if (capture_event) begin
                frame_seq <= frame_seq + 32'd1;
                last_capture_cycle <= ddr_cycle_counter;
                capture_seen <= 1'b1;
            end
        end
    end

    always @(posedge I_ddr_clk or negedge I_ddr_rst_n) begin
        if (!I_ddr_rst_n) begin
            fps_div_busy <= 1'b0;
            fps_div_count <= 6'd0;
            fps_dividend_shift <= 32'd0;
            fps_divisor <= 32'd0;
            fps_quotient <= 32'd0;
            fps_remainder <= 33'd0;
            fps_tenths_ddr <= 10'd0;
            fps_valid_ddr <= 1'b0;
        end else begin
            if (capture_event && capture_seen && (capture_period_cycles != 32'd0) && !fps_div_busy) begin
                fps_dividend_shift <= FPS_NUMERATOR + (capture_period_cycles >> 1);
                fps_divisor <= capture_period_cycles;
                fps_quotient <= 32'd0;
                fps_remainder <= 33'd0;
                fps_div_count <= 6'd0;
                fps_div_busy <= 1'b1;
            end

            if (fps_div_busy) begin
                fps_dividend_shift <= {fps_dividend_shift[30:0], 1'b0};
                fps_quotient <= fps_quotient_next;
                if (fps_trial_subtract)
                    fps_remainder <= fps_trial_remainder - {1'b0, fps_divisor};
                else
                    fps_remainder <= fps_trial_remainder;

                if (fps_div_count == 6'd31) begin
                    fps_div_busy <= 1'b0;
                    fps_tenths_ddr <= (fps_quotient_next > 32'd999) ? 10'd999 : fps_quotient_next[9:0];
                    fps_valid_ddr <= 1'b1;
                end else begin
                    fps_div_count <= fps_div_count + 6'd1;
                end
            end
        end
    end

    always @(posedge I_ddr_clk or negedge I_ddr_rst_n) begin
        if (!I_ddr_rst_n) begin
            capture_q_wr_ptr <= 2'd0;
            capture_q_rd_ptr <= 2'd0;
            capture_q_count  <= 3'd0;
            page_valid       <= 4'b0000;
            for (page_index = 0; page_index < 4; page_index = page_index + 1) begin
                capture_q_ms[page_index]  <= 32'd0;
                capture_q_seq[page_index] <= 32'd0;
                page_capture_ms[page_index] <= 32'd0;
                page_frame_seq[page_index] <= 32'd0;
            end
        end else begin
            case ({capture_event, I_write_frame_start})
                2'b10: begin
                    if (capture_q_count < 3'd4) begin
                        capture_q_ms[capture_q_wr_ptr]  <= ms_now;
                        capture_q_seq[capture_q_wr_ptr] <= frame_seq_now;
                        capture_q_wr_ptr <= capture_q_wr_ptr + 2'd1;
                        capture_q_count  <= capture_q_count + 3'd1;
                    end else begin
                        capture_q_ms[capture_q_wr_ptr]  <= ms_now;
                        capture_q_seq[capture_q_wr_ptr] <= frame_seq_now;
                        capture_q_rd_ptr <= capture_q_wr_ptr;
                        capture_q_wr_ptr <= capture_q_wr_ptr + 2'd1;
                        capture_q_count  <= 3'd1;
                    end
                end

                2'b01: begin
                    if (capture_q_count == 3'd1) begin
                        page_valid[I_write_page] <= 1'b1;
                        page_capture_ms[I_write_page] <= capture_q_ms[capture_q_rd_ptr];
                        page_frame_seq[I_write_page] <= capture_q_seq[capture_q_rd_ptr];
                        capture_q_rd_ptr <= capture_q_rd_ptr + 2'd1;
                        capture_q_count  <= 3'd0;
                    end else begin
                        page_valid[I_write_page] <= 1'b0;
                        capture_q_rd_ptr <= capture_q_wr_ptr;
                        capture_q_count  <= 3'd0;
                    end
                end

                2'b11: begin
                    if (capture_q_count == 3'd0) begin
                        page_valid[I_write_page] <= 1'b1;
                        page_capture_ms[I_write_page] <= ms_now;
                        page_frame_seq[I_write_page] <= frame_seq_now;
                    end else if (capture_q_count == 3'd1) begin
                        page_valid[I_write_page] <= 1'b1;
                        page_capture_ms[I_write_page] <= capture_q_ms[capture_q_rd_ptr];
                        page_frame_seq[I_write_page] <= capture_q_seq[capture_q_rd_ptr];
                        capture_q_rd_ptr <= capture_q_rd_ptr + 2'd1;
                        capture_q_ms[capture_q_wr_ptr]  <= ms_now;
                        capture_q_seq[capture_q_wr_ptr] <= frame_seq_now;
                        capture_q_wr_ptr <= capture_q_wr_ptr + 2'd1;
                    end else begin
                        page_valid[I_write_page] <= 1'b0;
                        capture_q_ms[capture_q_wr_ptr]  <= ms_now;
                        capture_q_seq[capture_q_wr_ptr] <= frame_seq_now;
                        capture_q_rd_ptr <= capture_q_wr_ptr;
                        capture_q_wr_ptr <= capture_q_wr_ptr + 2'd1;
                        capture_q_count  <= 3'd1;
                    end
                end

                default: begin
                    capture_q_count <= capture_q_count;
                end
            endcase
        end
    end

    always @(*) begin
        display_result_valid  = 1'b0;
        display_result_frames = 4'd0;
        display_result_ms     = 10'd0;
        display_frame_age     = 32'd0;
        display_ms_age        = 32'd0;

        // 同一页同时读写的瞬间，页内容可能新旧混合，本拍结果判为无效。
        if (selected_page_valid &&
            !(I_write_frame_start && (I_write_page == I_display_page))) begin
            display_result_valid = 1'b1;
            display_frame_age = frame_seq_now - selected_page_seq;
            display_ms_age = ms_now - selected_page_ms;
            display_result_frames = (display_frame_age > 32'd9) ? 4'd9 : display_frame_age[3:0];
            display_result_ms = (display_ms_age > 32'd999) ? 10'd999 : display_ms_age[9:0];
        end
    end

    reg [3:0] source_frames;
    reg [9:0] source_ms;
    reg source_valid;
    reg [9:0] source_fps_tenths;
    reg source_fps_valid;
    reg request_toggle;
    reg ack_toggle;
    reg ack_sync1, ack_sync2;
    reg [3:0] pending_frames;
    reg [9:0] pending_ms;
    reg pending_valid;
    reg [9:0] pending_fps_tenths;
    reg pending_fps_valid;

    always @(posedge I_ddr_clk or negedge I_ddr_rst_n) begin
        if (!I_ddr_rst_n) begin
            source_frames <= 4'd0;
            source_ms <= 10'd0;
            source_valid <= 1'b0;
            source_fps_tenths <= 10'd0;
            source_fps_valid <= 1'b0;
            request_toggle <= 1'b0;
            ack_sync1 <= 1'b0;
            ack_sync2 <= 1'b0;
            pending_frames <= 4'd0;
            pending_ms <= 10'd0;
            pending_valid <= 1'b0;
            pending_fps_tenths <= 10'd0;
            pending_fps_valid <= 1'b0;
        end else begin
            ack_sync1 <= ack_toggle;
            ack_sync2 <= ack_sync1;

            if (I_display_frame_start) begin
                if (request_toggle == ack_sync2) begin
                    source_frames <= display_result_frames;
                    source_ms <= display_result_ms;
                    source_valid <= display_result_valid;
                    source_fps_tenths <= fps_tenths_ddr;
                    source_fps_valid <= fps_valid_ddr;
                    request_toggle <= ~request_toggle;
                    pending_valid <= 1'b0;
                end else begin
                    pending_frames <= display_result_frames;
                    pending_ms <= display_result_ms;
                    pending_valid <= 1'b1;
                    pending_fps_tenths <= fps_tenths_ddr;
                    pending_fps_valid <= fps_valid_ddr;
                end
            end else if ((request_toggle == ack_sync2) && pending_valid) begin
                source_frames <= pending_frames;
                source_ms <= pending_ms;
                source_valid <= pending_valid;
                source_fps_tenths <= pending_fps_tenths;
                source_fps_valid <= pending_fps_valid;
                request_toggle <= ~request_toggle;
                pending_valid <= 1'b0;
            end
        end
    end

    reg request_sync1, request_sync2, request_seen;
    always @(posedge I_pixel_clk or negedge I_pixel_rst_n) begin
        if (!I_pixel_rst_n) begin
            request_sync1 <= 1'b0;
            request_sync2 <= 1'b0;
            request_seen  <= 1'b0;
            ack_toggle    <= 1'b0;
            O_delay_valid <= 1'b0;
            O_delay_frames <= 4'd0;
            O_delay_ms <= 10'd0;
            O_fps_valid <= 1'b0;
            O_fps_tenths <= 10'd0;
        end else begin
            request_sync1 <= request_toggle;
            request_sync2 <= request_sync1;
            if (request_sync2 != request_seen) begin
                request_seen <= request_sync2;
                ack_toggle <= request_sync2;
                O_delay_valid <= source_valid;
                O_delay_frames <= source_frames;
                O_delay_ms <= source_ms;
                O_fps_valid <= source_fps_valid;
                O_fps_tenths <= source_fps_tenths;
            end
        end
    end

endmodule
