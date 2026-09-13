module YCbCr444_RGB888#(
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720
)(
    input               I_clk,
    input               I_rst_n,
    
    input               I_tlast,
    input               I_tuser,
    input      [7:0]    I_y_tdata,
    input      [7:0]    I_cb_tdata,
    input      [7:0]    I_cr_tdata,
    input               I_tvalid,
    input               I_tready,
    
    output reg          O_tlast,
    output reg          O_tuser,
    output reg [7:0]    O_red_tdata,
    output reg [7:0]    O_green_tdata,
    output reg [7:0]    O_blue_tdata,
    output reg          O_tvalid,
    output              O_tready
);

    // =========================================================================
    // 定点转换公式说明 (BT.601, 放大 256 倍):
    // R = Y + 1.402 * (Cr - 128)
    // G = Y - 0.344 * (Cb - 128) - 0.714 * (Cr - 128)
    // B = Y + 1.772 * (Cb - 128)
    //
    // 展开并化简常数偏移 (1.402*256≈359, 0.344*256≈88, 0.714*256≈183, 1.772*256≈454):
    // 256R = 256*Y + 359*Cr - 45952
    // 256G = 256*Y + 135424 - 88*Cb - 183*Cr
    // 256B = 256*Y + 454*Cb - 58112
    // =========================================================================

    // ready 反压信号透传
    assign O_tready = I_tready;

    // -------------------------------------------------------------------------
    // 流水线控制信号打拍寄存器（3 拍延迟对齐）
    // -------------------------------------------------------------------------
    reg [1:0] tvalid_dly;
    reg [1:0] tlast_dly;
    reg [1:0] tuser_dly;

    // -------------------------------------------------------------------------
    // Pipeline Stage 1: 并行乘法与位移运算
    // -------------------------------------------------------------------------
    reg [15:0] mult_y;      // Y * 256 (位移 8 位即可)
    reg [17:0] mult_cr_359; // Cr * 359 (8bit x 9bit = 17bit)
    reg [15:0] mult_cb_88;  // Cb * 88  (8bit x 7bit = 15bit)
    reg [16:0] mult_cr_183; // Cr * 183 (8bit x 8bit = 16bit)
    reg [17:0] mult_cb_454; // Cb * 454 (8bit x 9bit = 17bit)

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            mult_y      <= 16'd0;
            mult_cr_359 <= 18'd0;
            mult_cb_88  <= 16'd0;
            mult_cr_183 <= 17'd0;
            mult_cb_454 <= 18'd0;
        end else if (I_tvalid && I_tready) begin
            mult_y      <= {I_y_tdata, 8'd0};     // 256 * Y
            mult_cr_359 <= I_cr_tdata * 9'd359;   // 359 * Cr
            mult_cb_88  <= I_cb_tdata * 7'd88;    // 88  * Cb
            mult_cr_183 <= I_cr_tdata * 8'd183;   // 183 * Cr
            mult_cb_454 <= I_cb_tdata * 9'd454;   // 454 * Cb
        end
    end

    // -------------------------------------------------------------------------
    // Pipeline Stage 2: 加减法求和 (带符号 19-bit，保留符号位以判断下溢)
    // -------------------------------------------------------------------------
    reg signed [18:0] sum_r;
    reg signed [18:0] sum_g;
    reg signed [18:0] sum_b;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            sum_r <= 19'sd0;
            sum_g <= 19'sd0;
            sum_b <= 19'sd0;
        end else if (tvalid_dly[0]) begin
            // 256R = 256*Y + 359*Cr - 45952
            sum_r <= $signed({1'b0, mult_y}) + $signed({1'b0, mult_cr_359}) - 19'sd45952;
            
            // 256G = 256*Y + 34688 - 88*Cb - 183*Cr
            // (常数应为 (88+183)*128 = 34688, 原 135424 为笔误, 否则 G 通道整体饱和)
            sum_g <= $signed({1'b0, mult_y}) + 19'sd34688 - $signed({1'b0, mult_cb_88}) - $signed({1'b0, mult_cr_183});
            
            // 256B = 256*Y + 454*Cb - 58112
            sum_b <= $signed({1'b0, mult_y}) + $signed({1'b0, mult_cb_454}) - 19'sd58112;
        end
    end

    // -------------------------------------------------------------------------
    // Pipeline Stage 3: 右移 8 位并进行 0~255 饱和截断处理 (Clamping)
    // -------------------------------------------------------------------------
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_red_tdata   <= 8'd0;
            O_green_tdata <= 8'd0;
            O_blue_tdata  <= 8'd0;
        end else if (tvalid_dly[1]) begin
            // Red 饱和截断
            if (sum_r[18])                     // 符号位为1表示负数下溢
                O_red_tdata <= 8'd0;
            else if (sum_r[18:16] != 3'd0)     // > 255 上溢 (高于结果位的溢出位非零)
                O_red_tdata <= 8'd255;
            else
                O_red_tdata <= sum_r[15:8];

            // Green 饱和截断
            if (sum_g[18]) 
                O_green_tdata <= 8'd0;
            else if (sum_g[18:16] != 3'd0) 
                O_green_tdata <= 8'd255;
            else
                O_green_tdata <= sum_g[15:8];

            // Blue 饱和截断
            if (sum_b[18]) 
                O_blue_tdata <= 8'd0;
            else if (sum_b[18:16] != 3'd0) 
                O_blue_tdata <= 8'd255;
            else
                O_blue_tdata <= sum_b[15:8];
        end
    end

    // -------------------------------------------------------------------------
    // 控制信号打拍（3 拍对齐）
    // -------------------------------------------------------------------------
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            tvalid_dly <= 2'b0;
            tlast_dly  <= 2'b0;
            tuser_dly  <= 2'b0;
            O_tvalid   <= 1'b0;
            O_tlast    <= 1'b0;
            O_tuser    <= 1'b0;
        end else begin
            tvalid_dly <= {tvalid_dly[0], (I_tvalid && I_tready)};
            tlast_dly  <= {tlast_dly[0],  I_tlast};
            tuser_dly  <= {tuser_dly[0],  I_tuser};

            O_tvalid   <= tvalid_dly[1];
            O_tlast    <= tlast_dly[1];
            O_tuser    <= tuser_dly[1];
        end
    end

endmodule