`timescale 1ns / 1ps
// =============================================================================
// tb_steep.v -- 用真实 ae_auto RTL + "陡峭"被控对象(传感器模拟增益被钉死在
//              15.75x 时的近似) 观察闭环会不会被推到 AE_MIN 并卡在那里。
//   plant: 曝光 4 拍(帧)延迟, Y = 0.9 * ae (饱和到 255), 编码器无增益可调。
// =============================================================================
module tb_steep;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #(21.0) clk = ~clk;          // 23.81MHz

    reg [7:0] measured = 8'd128;
    reg       fd = 1'b0;

    wire [15:0] ae_out, ag_out;
    wire        ae_req;

    ae_auto #(
        .TARGET_Y(90), .AE_MAX(1990), .AE_MIN(4), .AE_INIT(500), .HYST(20),
        .KP(1), .STEP_MAX(30), .AG_VALUE(80), .UPDATE_HOLD(3)
    ) dut (
        .I_clk(clk), .I_rst_n(rst_n), .I_enable(1'b1),
        .I_avg_y(measured), .I_frame_done(fd), .I_cfg_done(1'b1),
        .O_ae(ae_out), .O_ag(ag_out), .O_ae_req(ae_req)
    );

    // 4 帧滑动平均 (与 RTL 内一致)
    reg [7:0] y0, y1, y2, yf;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin y0 <= 8'd50; y1 <= 8'd50; y2 <= 8'd50; yf <= 8'd50; end
        else if (fd) begin
            y0 <= measured; y1 <= y0; y2 <= y1;
            yf <= ({2'd0, measured} + {2'd0, y0} + {2'd0, y1} + {2'd0, y2}) >> 2;
        end
    end

    // 被控对象: 曝光 4 帧延迟 + Y = 0.9*ae
    reg [15:0] d1, d2, d3, d4;
    integer py;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin d1 <= 16'd500; d2 <= 16'd500; d3 <= 16'd500; d4 <= 16'd500; end
        else begin d1 <= ae_out; d2 <= d1; d3 <= d2; d4 <= d3; end
    end
    always @(posedge clk) begin
        py = (d4 * 9) / 10;
        if (py > 255) py = 255;
        measured <= py[7:0];
    end

    integer n = 0;
    initial begin
        #100 rst_n = 1'b1;
        forever begin
            @(posedge clk);
            #1 fd = 1'b1;
            @(posedge clk);
            fd = 1'b0;
            repeat (3) @(posedge clk);     // 4 帧一次决策
            n = n + 1;
            if (n <= 60)
                $display("tick %0d  ae=%0d  applied=%0d  measured=%0d  y_filt=%0d",
                         n, ae_out, d4, measured, yf);
            if (n > 400) begin
                $display("FINAL ae=%0d measured=%0d y_filt=%0d", ae_out, measured, yf);
                $finish;
            end
        end
    end

endmodule
