`timescale 1ns / 1ps
// lp_filter_3x3 单元验证:
//  1) 2 拍固定延迟, 坐标/控制与数据同拍;
//  2) x>=3 && y>=2 区域输出因果 3x3 均值(/8 饱和), 边界透传;
//  3) 有效拍之间有空洞 (模拟 downscaler 每 6 拍 1 个样本), 移位链不被冲乱;
//  4) 带一个孤立尖峰 (4,3)=200, 验证平滑效果。
module tb_lp_filter;

    localparam W = 8, H = 6;

    reg         clk, rst_n;
    reg         tvalid, tuser, tlast;
    reg  [7:0]  grey, px, py;
    wire        o_valid, o_user, o_last;
    wire [7:0]  o_grey, o_x, o_y;

    lp_filter_3x3 #(.IMG_WIDTH(W), .IMG_HEIGHT(H)) dut (
        .I_clk(clk), .I_rst_n(rst_n),
        .I_tvalid(tvalid), .I_tuser(tuser), .I_tlast(tlast),
        .I_grey(grey), .I_x(px), .I_y(py),
        .O_tvalid(o_valid), .O_tuser(o_user), .O_tlast(o_last),
        .O_grey(o_grey), .O_x(o_x), .O_y(o_y)
    );

    // 参考图像 (x,y) -> 值
    reg [7:0] img [0:W-1][0:H-1];
    integer rx, ry;
    initial begin
        for (ry = 0; ry < H; ry = ry + 1)
            for (rx = 0; rx < W; rx = rx + 1)
                img[rx][ry] = 8'd10 + ry * 10 + rx;
        img[4][3] = 8'd200;   // 尖峰
    end

    integer errors, checked;
    initial errors = 0; initial checked = 0;

    // 期望值计算与比对
    integer sumv; reg [7:0] exp;
    always @(posedge clk) begin
        if (o_valid) begin
            checked = checked + 1;
            if (o_x >= 3 && o_y >= 2) begin
                sumv = img[o_x][o_y]     + img[o_x-1][o_y]   + img[o_x-2][o_y]
                     + img[o_x][o_y-1]   + img[o_x-1][o_y-1] + img[o_x-2][o_y-1]
                     + img[o_x][o_y-2]   + img[o_x-1][o_y-2] + img[o_x-2][o_y-2];
                exp = ((sumv >> 3) > 255) ? 8'd255 : (sumv >> 3);
            end else begin
                exp = img[o_x][o_y];
            end
            if (o_grey !== exp) begin
                errors = errors + 1;
                $display("FAIL (%0d,%0d): got %0d, expect %0d", o_x, o_y, o_grey, exp);
            end else begin
                $display("OK   (%0d,%0d): %0d", o_x, o_y, o_grey);
            end
        end
    end

    initial clk = 0;
    always #5 clk = ~clk;

    // 发送: 每 3 个时钟 1 个有效样本 (模拟降采样空洞), x 每样本 +1
    integer cycle_cnt;
    reg [2:0] sub_cnt;
    integer total_samples;

    initial begin
        tvalid = 0; tuser = 0; tlast = 0; grey = 0; px = 0; py = 0;
        rst_n = 0;
        #30 rst_n = 1;
        #20;

        total_samples = 0;
        // 逐行逐列, 每个样本间插 2 个无效拍
        for (ry = 0; ry < H; ry = ry + 1) begin
            for (rx = 1; rx < W; rx = rx + 1) begin  // x 从 1 开始, 与 downscaler 一致
                @(posedge clk);
                tvalid <= 1'b1;
                tuser  <= ((rx == 1) && (ry == 0));
                tlast  <= (rx == W - 1);
                grey   <= img[rx][ry];
                px     <= rx;
                py     <= ry;
                total_samples = total_samples + 1;
                // 空洞
                repeat (2) begin
                    @(posedge clk);
                    tvalid <= 1'b0; tuser <= 1'b0; tlast <= 1'b0;
                end
            end
        end
        @(posedge clk);
        tvalid <= 1'b0; tuser <= 1'b0; tlast <= 1'b0;

        #100;
        $display("------------------------------------");
        $display("total samples sent : %0d", total_samples);
        $display("pixels checked     : %0d", checked);
        $display("errors             : %0d", errors);
        if (errors == 0 && checked == total_samples)
            $display("===== PASS =====");
        else
            $display("===== FAIL =====");
        $finish;
    end

endmodule
