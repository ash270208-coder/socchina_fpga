/*****************************************************************
Company : MiLianKe Electronic Technology Co., Ltd.
Module  : awb (高画质全功能整合版 - 零错位 + 提亮 + 防高光发绿 + Q8瘦身)
本次新增整合：
  1. 【高光去伪色漂白】：台灯调很亮时，若绿光接近饱和(>=248)，强制三通道拉满至 255，
     彻底消灭强光下白纸泛绿的物理瓶颈；
  2. 【人眼视觉感知提亮】：G 通道采用零开销移位加法 (G + G/4) 提亮 25%，R/B 同步
     等比放大，彻底解决画面比人眼暗的问题，通透感立现；
  3. 【Q8 紧凑乘法瘦身】：乘法器位宽由 20x8 砍至 10x8(18位输出)，乘法资源立减 50%；
  4. 【原有时序分毫不动】：完整保留 TUSER_LEAD(=24) 拍延迟线，绝不错位、绝无边条！
*****************************************************************/

module awb #(   
    parameter IMG_HEIGHT = 1080,
    parameter IMG_WIDTH  = 1920
) 
(
    input                   I_clk,
    input                   I_rst_n,

    input                   I_tlast,
    input                   I_tuser,
    input  [95:0]           I_tdata,
    input                   I_tvalid, 
    output                  I_tready,

    output                  O_tlast,
    output                  O_tuser,
    output [95:0]           O_tdata,
    output                  O_tvalid,
    input                   O_tready
);

    // =========================================================================
    // 0. 错位保护延迟参数（原版已验证有效，原样保留）
    // =========================================================================
    localparam TUSER_LEAD = 24;

    /*****************************************************************
      一、全帧色彩累加与场消隐期 (VBLANK) 单脉冲检测
    *****************************************************************/
    reg [31:0] sum_r, sum_g, sum_b;
    reg [31:0] frame_r, frame_g, frame_b;
    reg [8:0]  vblank_cnt;
    reg        vblank_pulse;

    // 抽样第 0 像素统计全图均值
    wire [7:0] s_r = I_tdata[16+:8];
    wire [7:0] s_g = I_tdata[8+:8];
    wire [7:0] s_b = I_tdata[0+:8];

    // 当 valid 连续 128 周期为低，确认进入两帧之间的场消隐期 (VBLANK)
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            vblank_cnt   <= 9'd0;
            vblank_pulse <= 1'b0;
        end else begin
            if (I_tvalid) begin
                vblank_cnt   <= 9'd0;
                vblank_pulse <= 1'b0;
            end else if (vblank_cnt < 9'd255) begin
                vblank_cnt   <= vblank_cnt + 1'b1;
                vblank_pulse <= (vblank_cnt == 9'd128); // 场消隐期产生 1 拍启动单脉冲
            end else begin
                vblank_pulse <= 1'b0;
            end
        end
    end

    // 全帧色彩统计累加器
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            sum_r   <= 32'd0; sum_g   <= 32'd0; sum_b   <= 32'd0;
            frame_r <= 32'd1000; frame_g <= 32'd1000; frame_b <= 32'd1000;
        end else begin
            if (I_tuser && I_tvalid) begin // 帧头到来，清零重新累加
                sum_r <= {24'd0, s_r};
                sum_g <= {24'd0, s_g};
                sum_b <= {24'd0, s_b};
            end else if (I_tvalid) begin
                sum_r <= sum_r + s_r;
                sum_g <= sum_g + s_g;
                sum_b <= sum_b + s_b;
            end

            // 场消隐期瞬间锁存整帧真实统计量
            if (vblank_pulse) begin
                frame_r <= (sum_r > 32'd1000) ? sum_r : 32'd1000;
                frame_g <= (sum_g > 32'd1000) ? sum_g : 32'd1000;
                frame_b <= (sum_b > 32'd1000) ? sum_b : 32'd1000;
            end
        end
    end

    /*****************************************************************
      二、调用原配除法器 IP (分子注入 1.25x 提亮，色准亮度两全其美)
    *****************************************************************/
    // 分子整体放大 1.25 倍 (G + G/4)，使除法器算出来的 R/B 增益同步提亮 25%
    wire [31:0] frame_g_boost = frame_g + {2'b00, frame_g[31:2]};

    wire [47:0] dout_R;
    wire [47:0] dout_B;
    wire        done_R;

    // R 通道除法器 IP
    divider div_gen_G_R_r1 (
        .clk        (I_clk),
        .rst        (!I_rst_n),
        .start      (vblank_pulse),
        .denominator(frame_r),
        .numerator  ({frame_g_boost, 16'd0}), // 分子放大 1.25x
        .quotient   (dout_R),
        .done       (done_R)
    );

    // B 通道除法器 IP
    divider divide_G_B_r1 (
        .clk        (I_clk),
        .rst        (!I_rst_n),
        .start      (vblank_pulse),
        .denominator(frame_b),
        .numerator  ({frame_g_boost, 16'd0}), // 分子放大 1.25x
        .quotient   (dout_B),
        .done       ()
    );

    /*****************************************************************
      三、安全走廊限幅与平滑滤波 (匹配 1.25x 提亮后的黄金区间)
    *****************************************************************/
    reg [19:0] target_r;
    reg [19:0] target_b;
    reg [19:0] cur_gain_r;
    reg [19:0] cur_gain_b;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            // 提亮后的开机基准 (原 1.40x*1.25 = 1.75x, 原 2.20x*1.25 = 2.75x)
            target_r   <= 20'h1C000; // 1.75x
            target_b   <= 20'h2C000; // 2.75x
            cur_gain_r <= 20'h1C000; 
            cur_gain_b <= 20'h2C000;
        end else begin
            if (done_R) begin
                // R 提亮走廊：严格锁在 1.56x (20'h19000) ~ 1.94x (20'h1F000)
                if (|dout_R[47:20] || dout_R[19:0] > 20'h1F000)
                    target_r <= 20'h1F000;
                else if (dout_R[19:0] < 20'h19000)
                    target_r <= 20'h19000;
                else
                    target_r <= dout_R[19:0];

                // B 提亮走廊：严格锁在 2.44x (20'h27000) ~ 3.12x (20'h32000)
                if (|dout_B[47:20] || dout_B[19:0] > 20'h32000)
                    target_b <= 20'h32000;
                else if (dout_B[19:0] < 20'h27000)
                    target_b <= 20'h27000;
                else
                    target_b <= dout_B[19:0];
            end

            // 帧间 1/16 阻尼平滑滤波 (自适应平稳过渡，防闪烁)
            if (vblank_pulse) begin
                cur_gain_r <= cur_gain_r - (cur_gain_r >> 4) + (target_r >> 4);
                cur_gain_b <= cur_gain_b - (cur_gain_b >> 4) + (target_b >> 4);
            end
        end
    end

    /*****************************************************************
      四、【Q8 紧凑乘法】+【G 通道 1.25x 提亮】+【高光强行漂白】
    *****************************************************************/
    // Q8 增益提取 (10 位宽，减半乘法器消耗)
    wire [9:0] gain_r_q8 = cur_gain_r[17:8]; 
    wire [9:0] gain_b_q8 = cur_gain_b[17:8];

    // 拆分输入的 4 个并行像素
    wire [7:0] p0_r = I_tdata[16+:8], p0_g = I_tdata[8+:8],  p0_b = I_tdata[0+:8];
    wire [7:0] p1_r = I_tdata[40+:8], p1_g = I_tdata[32+:8], p1_b = I_tdata[24+:8];
    wire [7:0] p2_r = I_tdata[64+:8], p2_g = I_tdata[56+:8], p2_b = I_tdata[48+:8];
    wire [7:0] p3_r = I_tdata[88+:8], p3_g = I_tdata[80+:8], p3_b = I_tdata[72+:8];

    // G 通道 1.25x 无乘法器移位提亮 (G + G/4)
    wire [8:0] p0_g_bst = p0_g + {2'b00, p0_g[7:2]};
    wire [8:0] p1_g_bst = p1_g + {2'b00, p1_g[7:2]};
    wire [8:0] p2_g_bst = p2_g + {2'b00, p2_g[7:2]};
    wire [8:0] p3_g_bst = p3_g + {2'b00, p3_g[7:2]};

    // Stage 1: 并行紧凑乘法流水线 (8x10 位乘法)
    reg [17:0] r0_m, b0_m, r1_m, b1_m, r2_m, b2_m, r3_m, b3_m;
    reg [7:0]  g0_d, g1_d, g2_d, g3_d;
    reg        v_d1, u_d1, l_d1;

    always @(posedge I_clk) begin
        r0_m <= p0_r * gain_r_q8; 
        b0_m <= p0_b * gain_b_q8;
        r1_m <= p1_r * gain_r_q8;
        b1_m <= p1_b * gain_b_q8;
        r2_m <= p2_r * gain_r_q8;
        b2_m <= p2_b * gain_b_q8;
        r3_m <= p3_r * gain_r_q8;
        b3_m <= p3_b * gain_b_q8;

        // G 通道截断限幅后打拍
        g0_d <= p0_g_bst[8] ? 8'd255 : p0_g_bst[7:0];
        g1_d <= p1_g_bst[8] ? 8'd255 : p1_g_bst[7:0];
        g2_d <= p2_g_bst[8] ? 8'd255 : p2_g_bst[7:0];
        g3_d <= p3_g_bst[8] ? 8'd255 : p3_g_bst[7:0];

        v_d1 <= I_tvalid;
        u_d1 <= I_tuser && I_tvalid;
        l_d1 <= I_tlast && I_tvalid;
    end

    // Stage 2: 【关键！】截断限幅 + 高光强行漂白 (消除台灯强光下的泛绿)
    // 检测绿通道是否接近饱和 (>=248)，若是则认定为强光高光，强制漂白为纯白 255
    wire p0_hl = (g0_d >= 8'd248);
    wire p1_hl = (g1_d >= 8'd248);
    wire p2_hl = (g2_d >= 8'd248);
    wire p3_hl = (g3_d >= 8'd248);

    wire [7:0] p0_r_clp = p0_hl ? 8'd255 : ((|r0_m[17:16]) ? 8'd255 : r0_m[15:8]);
    wire [7:0] p0_g_clp = p0_hl ? 8'd255 : g0_d;
    wire [7:0] p0_b_clp = p0_hl ? 8'd255 : ((|b0_m[17:16]) ? 8'd255 : b0_m[15:8]);

    wire [7:0] p1_r_clp = p1_hl ? 8'd255 : ((|r1_m[17:16]) ? 8'd255 : r1_m[15:8]);
    wire [7:0] p1_g_clp = p1_hl ? 8'd255 : g1_d;
    wire [7:0] p1_b_clp = p1_hl ? 8'd255 : ((|b1_m[17:16]) ? 8'd255 : b1_m[15:8]);

    wire [7:0] p2_r_clp = p2_hl ? 8'd255 : ((|r2_m[17:16]) ? 8'd255 : r2_m[15:8]);
    wire [7:0] p2_g_clp = p2_hl ? 8'd255 : g2_d;
    wire [7:0] p2_b_clp = p2_hl ? 8'd255 : ((|b2_m[17:16]) ? 8'd255 : b2_m[15:8]);

    wire [7:0] p3_r_clp = p3_hl ? 8'd255 : ((|r3_m[17:16]) ? 8'd255 : r3_m[15:8]);
    wire [7:0] p3_g_clp = p3_hl ? 8'd255 : g3_d;
    wire [7:0] p3_b_clp = p3_hl ? 8'd255 : ((|b3_m[17:16]) ? 8'd255 : b3_m[15:8]);

    reg [95:0] out_data_r;
    reg        v_d2;

    always @(posedge I_clk) begin
        out_data_r <= {p3_r_clp, p3_g_clp, p3_b_clp,
                       p2_r_clp, p2_g_clp, p2_b_clp,
                       p1_r_clp, p1_g_clp, p1_b_clp,
                       p0_r_clp, p0_g_clp, p0_b_clp};
        v_d2 <= v_d1;
    end

    // =========================================================================
    // 五、延迟线与无错位输出同步 (严格保持 TUSER_LEAD = 24 拍架构，严禁改动)
    // =========================================================================
    reg u_d2, l_d2;
    always @(posedge I_clk) begin
        u_d2 <= u_d1;
        l_d2 <= l_d1;
    end

    // 数据与 valid 延迟 TUSER_LEAD 拍
    (* ram_style = "distributed" *) reg [95:0] dl_data [0:TUSER_LEAD-1];
    reg        dl_v    [0:TUSER_LEAD-1];
    integer    j;

    always @(posedge I_clk) begin
        dl_data[0] <= out_data_r;
        dl_v[0]    <= v_d2;
        for (j = 1; j < TUSER_LEAD; j = j + 1) begin
            dl_data[j] <= dl_data[j-1];
            dl_v[j]    <= dl_v[j-1];
        end
    end

    // 最终输出：完全继承已验证通过的零错位输出端口逻辑
    assign O_tdata  = dl_data[TUSER_LEAD-1];
    assign O_tvalid = dl_v[TUSER_LEAD-1];
    assign O_tuser  = u_d2;   // 领先数据 TUSER_LEAD 拍
    assign O_tlast  = l_d2;
    assign I_tready = O_tready;

endmodule