/*****************************************************************
Company : MiLianKe Electronic Technology Co., Ltd.
Module  : awb (防眩光发红 + 轮廓保真修复版)
本次关键升级：
  1. 【根除光圈发红】：加入高光区红通道动态约束 (R <= G + 16)，
     绝不允许红通道在光斑外沿提前顶格在 255，彻底消灭光圈外围发红的现象！
  2. 【抑制强光模糊】：消除提前饱和截断，恢复高光边缘的渐变动态范围，
     灯泡轮廓分明，不再过曝虚化成一大团死光；
  3. 【保留原有优良特性】：Q8 紧凑位宽乘法省 50% 逻辑、TUSER_LEAD(=24)
     零错位架构、消隐期除法器 IP 稳定自适应。
*****************************************************************/
// ============================================================================
// 【资源优化修改 1】除法器 2 个 -> 1 个
// 原设计: 两个 48/32bit 流水线除法器 IP (PIPLE=50) 在 vblank_pulse 同时
//         并行计算 G/R 与 G/B, 合计约 1150 LUT + 1900 加法器 + 5000 寄存器。
// 修改后: 单个除法器在消隐期内分时完成两次除法 (先 G/R 再 G/B),
//         单周期 start 脉冲与操作数切换均由小状态机控制。
//         720p60 垂直消隐期约 49500 拍, 两次除法仅需约 100+ 拍, 时间充裕;
//         目标增益锁存时刻由 vblank_pulse+50 变为 vblank_pulse+102,
//         IIR 平滑仍在下一帧 vblank_pulse 进行, 帧级行为与原设计完全一致。
//         节省约 575 LUT + 950 加法器 + 2500 寄存器 (~5% slice)。
//
// 【资源优化修改 2】除法器由"全流水 IP"换成"顺序实现" divider_seq.v
//   原 divider IP 是 48 级全流水移位减阵列，布线后报告实测
//   u_divider = 827 LUT + 948 ripple + 2496 寄存器。
//   但本模块每帧只用 2 次除法 (vblank 后)，720p60 一帧在 75MHz 下有
//   约 125 万拍，两次除法各 48 拍只占 0.004% —— 全流水完全是浪费。
//   换成单减法器的 48 拍循环后：
//     * 同一上下文实测 divider_seq = 108 LUT + 48 ripple + 231 寄存器
//     * 分别单独综合对比：原 IP 2162 slice vs 顺序版 232 slice
//       -> **净省 1930 slice，0 ERAM**
//     * 算法与位宽完全相同，商/余数逐位一致
//       （等价性验证见 sim/tb_divider_seq.v：4457 组随机+定向激励 0 失败，
//         done 延迟固定 48 拍）
//   ⚠ 随之把状态机里"按固定拍数硬等"的守卫去掉了：
//     原 `if (done_div && (div_cnt >= DIV_LAT-4))` -> 现 `if (done_div)`
//     因为换了实现后拍数会变，靠固定拍数硬等必然出错。
//
//   目的：为《板A以太网改造_实施计划.md》第 3 步（取数+降采样+发 128x72 图）
//   腾出 slice 余量 —— 布线后余量 2796，而 cnn_ds10 单独综合要 3369，缺口 573。
//   参考 docs/板A以太网改造_第2步实施记录.md §5.6
// ============================================================================

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

    // 错位保护延迟参数（原版已验证有效，原样保留）
    localparam TUSER_LEAD = 24;

    /*****************************************************************
      一、全帧色彩累加与场消隐期 (VBLANK) 检测
    *****************************************************************/
    reg [31:0] sum_r, sum_g, sum_b;
    reg [31:0] frame_r, frame_g, frame_b;
    reg [8:0]  vblank_cnt;
    reg        vblank_pulse;

    // 抽样第 0 像素统计全图均值
    wire [7:0] s_r = I_tdata[16+:8];
    wire [7:0] s_g = I_tdata[8+:8];
    wire [7:0] s_b = I_tdata[0+:8];

    // 当 valid 连续 128 周期为低，进入场消隐期 (VBLANK)
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
                vblank_pulse <= (vblank_cnt == 9'd128);
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
            if (I_tuser && I_tvalid) begin
                sum_r <= {24'd0, s_r};
                sum_g <= {24'd0, s_g};
                sum_b <= {24'd0, s_b};
            end else if (I_tvalid) begin
                sum_r <= sum_r + s_r;
                sum_g <= sum_g + s_g;
                sum_b <= sum_b + s_b;
            end

            if (vblank_pulse) begin
                frame_r <= (sum_r > 32'd1000) ? sum_r : 32'd1000;
                frame_g <= (sum_g > 32'd1000) ? sum_g : 32'd1000;
                frame_b <= (sum_b > 32'd1000) ? sum_b : 32'd1000;
            end
        end
    end

    /*****************************************************************
      二、除法器调用 (分子含 1.25x 提亮)
      【资源优化】单个除法器分时计算: 先 G/R (div_st=1) 再 G/B (div_st=2)
      【资源优化 2】全流水 divider IP -> 顺序 divider_seq (见 divider_seq.v)
        原 IP 是 48 级全流水移位减阵列(PIPLE=50), 实测在布线后报告里占
        u_divider = 827 LUT + 948 ripple + 2496 寄存器;
        而这里每帧只用 2 次除法(vblank 后), 720p60 一帧在 75MHz 下有约
        125 万拍, 两次除法各 48 拍只占 0.004%, 全流水纯属浪费。
        换成单减法器的 48 拍循环: 同一上下文实测 divider_seq 只要
        108 LUT + 48 ripple + 231 寄存器, 单独综合对比省 1930 slice。
        算法/位宽完全相同, 商逐位一致 (tb_divider_seq.v 已验 4457 组 0 错)。
        ⚠ 因为换掉了实现, 下面等待完成的判断必须是**纯 done_div**,
          不能再按固定拍数硬等(原来那句 div_cnt >= DIV_LAT-4 已删除)。
    *****************************************************************/
    wire [31:0] frame_g_boost = frame_g + {2'b00, frame_g[31:2]};

    reg [31:0] div_den;      // 除数 (frame_r 或 frame_b)
    reg [1:0]  div_st;       // 状态机: 0=IDLE 1=DIV_R 2=DIV_B
    reg [6:0]  div_cnt;      // 状态内周期计数(仅用于产生 start 脉冲)
    reg        div_start;    // 除法器单周期启动脉冲

    wire [47:0] dout_div;    // 除法商
    wire        done_div;    // 除法完成

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            div_st    <= 2'd0;
            div_cnt   <= 7'd0;
            div_start <= 1'b0;
            div_den   <= 32'd1000;
            target_r  <= 20'h1C000;   // 1.75x
            target_b  <= 20'h2C000;   // 2.75x
        end else begin
            div_start <= 1'b0;        // 默认低, 需要时在分支内置 1 (单周期脉冲)
            case (div_st)
                2'd0: begin           // IDLE: 等待 vblank_pulse
                    div_cnt <= 7'd0;
                    if (vblank_pulse) begin
                        div_den <= frame_r;   // 第 1 次除法: G/R
                        div_st  <= 2'd1;
                    end
                end
                2'd1: begin           // DIV_R: 计算 G/R
                    if (div_cnt == 7'd0)
                        div_start <= 1'b1;    // 操作数已稳定, 发单周期启动脉冲
                    if (done_div) begin
                        // 锁存 G/R 商 -> 安全走廊限幅
                        if (|dout_div[47:20] || dout_div[19:0] > 20'h1F000)
                            target_r <= 20'h1F000;
                        else if (dout_div[19:0] < 20'h19000)
                            target_r <= 20'h19000;
                        else
                            target_r <= dout_div[19:0];
                        div_den <= frame_b;   // 第 2 次除法: G/B
                        div_cnt <= 7'd0;
                        div_st  <= 2'd2;
                    end else
                        div_cnt <= div_cnt + 1'b1;
                end
                2'd2: begin           // DIV_B: 计算 G/B
                    if (div_cnt == 7'd0)
                        div_start <= 1'b1;    // 操作数已稳定, 发单周期启动脉冲
                    if (done_div) begin
                        // 锁存 G/B 商 -> 安全走廊限幅
                        if (|dout_div[47:20] || dout_div[19:0] > 20'h32000)
                            target_b <= 20'h32000;
                        else if (dout_div[19:0] < 20'h27000)
                            target_b <= 20'h27000;
                        else
                            target_b <= dout_div[19:0];
                        div_st <= 2'd0;
                    end else
                        div_cnt <= div_cnt + 1'b1;
                end
                default: div_st <= 2'd0;
            endcase
        end
    end

    // 顺序(非流水)除法器: start 后 48 拍出 done，商/余数当拍有效。
    // 端口与原 divider IP 完全一致，所以这里只是换了模块名。
    // 详见 divider_seq.v 头部；等价性见 sim/tb_divider_seq.v (4457 组 0 错)。
    divider_seq #(
        .PIPLE (50),          // 保留参数名，本模块不使用
        .W_DEN (32),
        .W_NUM (48),
        .W_REM (32)
    ) u_divider (
        .clk        (I_clk               ),
        .rst        (!I_rst_n            ),
        .start      (div_start           ),
        .denominator(div_den             ),
        .numerator  ({frame_g_boost,16'd0}),
        .done       (done_div            ),
        .quotient   (dout_div            ),
        .remainder  (                    )
    );

    /*****************************************************************
      三、安全走廊限幅与平滑滤波
      (目标增益 target_r/target_b 的更新已并入除法器状态机, 此处仅做 IIR 平滑)
    *****************************************************************/
    reg [19:0] target_r;
    reg [19:0] target_b;
    reg [19:0] cur_gain_r;
    reg [19:0] cur_gain_b;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            cur_gain_r <= 20'h1C000; 
            cur_gain_b <= 20'h2C000;
        end else if (vblank_pulse) begin
            cur_gain_r <= cur_gain_r - (cur_gain_r >> 4) + (target_r >> 4);
            cur_gain_b <= cur_gain_b - (cur_gain_b >> 4) + (target_b >> 4);
        end
    end

    /*****************************************************************
      四、【Q8 紧凑乘法】+【高光色相平抑 (消灭红圈与模糊)】
    *****************************************************************/
    wire [9:0] gain_r_q8 = cur_gain_r[17:8]; 
    wire [9:0] gain_b_q8 = cur_gain_b[17:8];

    // 拆分 4 像素
    wire [7:0] p0_r = I_tdata[16+:8], p0_g = I_tdata[8+:8],  p0_b = I_tdata[0+:8];
    wire [7:0] p1_r = I_tdata[40+:8], p1_g = I_tdata[32+:8], p1_b = I_tdata[24+:8];
    wire [7:0] p2_r = I_tdata[64+:8], p2_g = I_tdata[56+:8], p2_b = I_tdata[48+:8];
    wire [7:0] p3_r = I_tdata[88+:8], p3_g = I_tdata[80+:8], p3_b = I_tdata[72+:8];

    // G 通道 1.25x 提亮
    wire [8:0] p0_g_bst = p0_g + {2'b00, p0_g[7:2]};
    wire [8:0] p1_g_bst = p1_g + {2'b00, p1_g[7:2]};
    wire [8:0] p2_g_bst = p2_g + {2'b00, p2_g[7:2]};
    wire [8:0] p3_g_bst = p3_g + {2'b00, p3_g[7:2]};

    // Stage 1: 并行乘法
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

        g0_d <= p0_g_bst[8] ? 8'd255 : p0_g_bst[7:0];
        g1_d <= p1_g_bst[8] ? 8'd255 : p1_g_bst[7:0];
        g2_d <= p2_g_bst[8] ? 8'd255 : p2_g_bst[7:0];
        g3_d <= p3_g_bst[8] ? 8'd255 : p3_g_bst[7:0];

        v_d1 <= I_tvalid;
        u_d1 <= I_tuser && I_tvalid;
        l_d1 <= I_tlast && I_tvalid;
    end

    // Stage 2: 【核心修复！】高光色相平抑与防红圈算法
    // 基础截断
    wire [7:0] p0_r_raw = (|r0_m[17:16]) ? 8'd255 : r0_m[15:8];
    wire [7:0] p0_b_raw = (|b0_m[17:16]) ? 8'd255 : b0_m[15:8];
    wire [7:0] p1_r_raw = (|r1_m[17:16]) ? 8'd255 : r1_m[15:8];
    wire [7:0] p1_b_raw = (|b1_m[17:16]) ? 8'd255 : b1_m[15:8];
    wire [7:0] p2_r_raw = (|r2_m[17:16]) ? 8'd255 : r2_m[15:8];
    wire [7:0] p2_b_raw = (|b2_m[17:16]) ? 8'd255 : b2_m[15:8];
    wire [7:0] p3_r_raw = (|r3_m[17:16]) ? 8'd255 : r3_m[15:8];
    wire [7:0] p3_b_raw = (|b3_m[17:16]) ? 8'd255 : b3_m[15:8];

    // 1. 中心极亮区强行纯白 (>=248)
    wire p0_specular = (g0_d >= 8'd248);
    wire p1_specular = (g1_d >= 8'd248);
    wire p2_specular = (g2_d >= 8'd248);
    wire p3_specular = (g3_d >= 8'd248);

    // 2. 光晕区高光上限计算 (R <= G + 16, 保证红光不抢跑饱和，轮廓分明不发红！)
    wire [8:0] p0_r_cap = g0_d + 9'd16;
    wire [8:0] p1_r_cap = g1_d + 9'd16;
    wire [8:0] p2_r_cap = g2_d + 9'd16;
    wire [8:0] p3_r_cap = g3_d + 9'd16;

    wire [7:0] p0_r_lim = (p0_r_cap > 9'd255) ? 8'd255 : p0_r_cap[7:0];
    wire [7:0] p1_r_lim = (p1_r_cap > 9'd255) ? 8'd255 : p1_r_cap[7:0];
    wire [7:0] p2_r_lim = (p2_r_cap > 9'd255) ? 8'd255 : p2_r_cap[7:0];
    wire [7:0] p3_r_lim = (p3_r_cap > 9'd255) ? 8'd255 : p3_r_cap[7:0];

    // 光晕区蓝光下限计算 (B >= G - 24, 保证蓝光不掉队泛黄)
    wire [7:0] p0_b_flr = (g0_d >= 8'd24) ? (g0_d - 8'd24) : 8'd0;
    wire [7:0] p1_b_flr = (g1_d >= 8'd24) ? (g1_d - 8'd24) : 8'd0;
    wire [7:0] p2_b_flr = (g2_d >= 8'd24) ? (g2_d - 8'd24) : 8'd0;
    wire [7:0] p3_b_flr = (g3_d >= 8'd24) ? (g3_d - 8'd24) : 8'd0;

    // 当 G >= 196 时进入光晕平抑状态
    wire p0_halo_zone = (g0_d >= 8'd196);
    wire p1_halo_zone = (g1_d >= 8'd196);
    wire p2_halo_zone = (g2_d >= 8'd196);
    wire p3_halo_zone = (g3_d >= 8'd196);

    // 综合裁决输出 (纯白区 / 平抑区 / 正常色彩区)
    wire [7:0] p0_r_clp = p0_specular ? 8'd255 : (p0_halo_zone && (p0_r_raw > p0_r_lim) ? p0_r_lim : p0_r_raw);
    wire [7:0] p0_g_clp = p0_specular ? 8'd255 : g0_d;
    wire [7:0] p0_b_clp = p0_specular ? 8'd255 : (p0_halo_zone && (p0_b_raw < p0_b_flr) ? p0_b_flr : p0_b_raw);

    wire [7:0] p1_r_clp = p1_specular ? 8'd255 : (p1_halo_zone && (p1_r_raw > p1_r_lim) ? p1_r_lim : p1_r_raw);
    wire [7:0] p1_g_clp = p1_specular ? 8'd255 : g1_d;
    wire [7:0] p1_b_clp = p1_specular ? 8'd255 : (p1_halo_zone && (p1_b_raw < p1_b_flr) ? p1_b_flr : p1_b_raw);

    wire [7:0] p2_r_clp = p2_specular ? 8'd255 : (p2_halo_zone && (p2_r_raw > p2_r_lim) ? p2_r_lim : p2_r_raw);
    wire [7:0] p2_g_clp = p2_specular ? 8'd255 : g2_d;
    wire [7:0] p2_b_clp = p2_specular ? 8'd255 : (p2_halo_zone && (p2_b_raw < p2_b_flr) ? p2_b_flr : p2_b_raw);

    wire [7:0] p3_r_clp = p3_specular ? 8'd255 : (p3_halo_zone && (p3_r_raw > p3_r_lim) ? p3_r_lim : p3_r_raw);
    wire [7:0] p3_g_clp = p3_specular ? 8'd255 : g3_d;
    wire [7:0] p3_b_clp = p3_specular ? 8'd255 : (p3_halo_zone && (p3_b_raw < p3_b_flr) ? p3_b_flr : p3_b_raw);

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
