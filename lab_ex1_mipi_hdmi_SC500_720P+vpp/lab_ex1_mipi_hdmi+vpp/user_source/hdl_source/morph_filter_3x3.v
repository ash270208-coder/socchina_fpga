`timescale 1ns / 1ps
// ============================================================================
// 3x3 灰度形态学窗口滤波模块 (单级)
//   MIN_MODE=1: 腐蚀 (3x3 最小值)    MIN_MODE=0: 膨胀 (3x3 最大值)
// 两级级联 (先腐蚀后膨胀) 构成灰度开运算, 用于直方图均衡显示链路的
// 亮噪点(椒盐)抑制。
// Cb/Cr 色度从本模块旁路通过, 每级同样延迟 1 行 + 2 拍 (级联 = 2 行 + 4 拍),
// 与滤波后的 Y 严格对齐, 无需额外的延迟模块。
//
// 关键设计:
//  - 3 个 1 行缓存 (Y 2 个 + 色度 1 个, ram_style="block" 推断为 eRAM),
//    读地址 = 写地址 + 1, 无同址读写冲突;
//  - 首行/次行与首列/次列做边缘复制, 输出保持 1280x720 全有效流,
//    两级级联时不会出现 valid 空洞/地址漂移;
//  - 延迟固定 = 1 行 + 2 拍; O_tvalid/tlast/user 与 O_grey 严格对齐;
//  - 行缓存不复位清零 (保证 BRAM 推断), 内容由 valid 门控, 不会泄漏脏数据。
// ============================================================================
module morph_filter_3x3 #(
    parameter IMG_WIDTH = 1280,
    parameter MIN_MODE  = 1      // 1=腐蚀(最小), 0=膨胀(最大)
)(
    input              I_clk,
    input              I_rst_n,
    input              I_tvalid,
    input              I_tlast,
    input              I_tuser,
    input  [7:0]       I_grey,
    input  [7:0]       I_cb,
    input  [7:0]       I_cr,
    output             O_tvalid,
    output             O_tlast,
    output             O_tuser,
    output reg [7:0]   O_grey,
    output [7:0]       O_cb,
    output [7:0]       O_cr
);

    // -------------------------------------------------------------------------
    // 1. 写地址与行计数 (tuser 与首个有效像素同拍)
    // -------------------------------------------------------------------------
    reg [10:0] waddr;
    reg [10:0] row_cnt;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            waddr   <= 11'd0;
            row_cnt <= 11'd0;
        end else if (I_tvalid) begin
            if (I_tuser) begin
                waddr   <= 11'd1;
                row_cnt <= 11'd0;
            end else begin
                waddr <= (waddr == IMG_WIDTH - 1) ? 11'd0 : waddr + 11'd1;
                if (I_tlast)
                    row_cnt <= row_cnt + 11'd1;
            end
        end
    end

    // tuser 与首个有效像素同拍: 该拍写入地址强制为 0
    wire [10:0] eff_waddr = (I_tvalid && I_tuser) ? 11'd0 : waddr;
    wire [10:0] raddr     = eff_waddr + 11'd1;

    // -------------------------------------------------------------------------
    // 2. 两级 1 行缓存 (级联 = 1 行 / 2 行延迟)
    // -------------------------------------------------------------------------
    (* ram_style = "block" *) reg [7:0] lb1_mem [0:IMG_WIDTH-1];
    (* ram_style = "block" *) reg [7:0] lb2_mem [0:IMG_WIDTH-1];
    reg [7:0] lb1_rd;   // 当前列, 上一行
    reg [7:0] lb2_rd;   // 当前列, 上两行

    always @(posedge I_clk) begin
        if (I_tvalid) begin
            lb1_mem[eff_waddr] <= I_grey;
            lb2_mem[eff_waddr] <= lb1_rd;
            lb1_rd <= lb1_mem[raddr];
            lb2_rd <= lb2_mem[raddr];
        end
    end

    // -------------------------------------------------------------------------
    // 2b. Cb/Cr 色度旁路延迟 (1 行 + 2 拍, 与滤波后 Y 对齐; 级联两级 = 2 行 + 4 拍)
    // -------------------------------------------------------------------------
    (* ram_style = "block" *) reg [15:0] cb_mem [0:IMG_WIDTH-1];
    reg [15:0] cb_lb, cb_d1, cb_d2;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            cb_lb <= 16'd0;
            cb_d1 <= 16'd0;
            cb_d2 <= 16'd0;
        end else begin
            if (I_tvalid) begin
                cb_mem[eff_waddr] <= {I_cb, I_cr};
                cb_lb <= cb_mem[raddr];
            end
            cb_d1 <= cb_lb;
            cb_d2 <= cb_d1;
        end
    end

    assign O_cb = cb_d2[15:8];
    assign O_cr = cb_d2[7:0];

    // -------------------------------------------------------------------------
    // 3. 9 点窗口抽头
    //    t0..t2: 行 y,  列 x / x-1 / x-2
    //    r0..r2: 行 y-1
    //    s0..s2: 行 y-2
    // -------------------------------------------------------------------------
    reg [7:0] t1, t2, r1, r2, s1, s2;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            t1 <= 8'd0; t2 <= 8'd0;
            r1 <= 8'd0; r2 <= 8'd0;
            s1 <= 8'd0; s2 <= 8'd0;
        end else begin
            t1 <= I_grey;   // (x-1, y)
            t2 <= t1;       // (x-2, y)
            r1 <= lb1_rd;   // (x-1, y-1)
            r2 <= r1;       // (x-2, y-1)
            s1 <= lb2_rd;   // (x-1, y-2)
            s2 <= s1;       // (x-2, y-2)
        end
    end

    // -------------------------------------------------------------------------
    // 4. 边缘复制 (首行/次行 + 首列/次列)
    // -------------------------------------------------------------------------
    wire row0 = (row_cnt == 11'd0);
    wire row1 = (row_cnt == 11'd1);
    wire col0 = (waddr == 11'd0) || (I_tvalid && I_tuser);
    wire col1 = (waddr == 11'd1) || (I_tvalid && I_tuser);

    // 行复制: 行 y-1 (y=0 时用行 0); 行 y-2 (y=0 用行 0, y=1 用行 y-1)
    wire [7:0] m_r0 = row0 ? I_grey : lb1_rd;
    wire [7:0] m_r1 = row0 ? t1     : r1;
    wire [7:0] m_r2 = row0 ? t2     : r2;
    wire [7:0] m_s0 = row0 ? I_grey : (row1 ? lb1_rd : lb2_rd);
    wire [7:0] m_s1 = row0 ? t1     : (row1 ? r1     : s1);
    wire [7:0] m_s2 = row0 ? t2     : (row1 ? r2     : s2);

    // 列复制
    wire [7:0] c0 = I_grey;
    wire [7:0] c1 = col0 ? c0 : t1;
    wire [7:0] c2 = col0 ? c0 : (col1 ? t1 : t2);
    wire [7:0] d0 = m_r0;
    wire [7:0] d1 = col0 ? d0 : m_r1;
    wire [7:0] d2 = col0 ? d0 : (col1 ? m_r1 : m_r2);
    wire [7:0] e0 = m_s0;
    wire [7:0] e1 = col0 ? e0 : m_s1;
    wire [7:0] e2 = col0 ? e0 : (col1 ? m_s1 : m_s2);

    // -------------------------------------------------------------------------
    // 5. 9 取最值 (两级比较树) + 输出寄存 (总延迟 = 1 行 + 2 拍)
    // -------------------------------------------------------------------------
    function [7:0] wsel;
        input [7:0] a, b;
        begin
            wsel = MIN_MODE ? ((a < b) ? a : b) : ((a > b) ? a : b);
        end
    endfunction

    wire [7:0] p0 = wsel(c0, c1);
    wire [7:0] p1 = wsel(c2, d0);
    wire [7:0] p2 = wsel(d1, d2);
    wire [7:0] p3 = wsel(e0, e1);
    wire [7:0] q0 = wsel(p0, p1);
    wire [7:0] q1 = wsel(p2, p3);
    wire [7:0] w0 = wsel(q0, q1);
    wire [7:0] w1 = wsel(w0, e2);

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n)
            O_grey <= 8'd0;
        else
            O_grey <= w1;
    end

    // -------------------------------------------------------------------------
    // 6. 控制信号延迟 1 行 + 2 拍 (与 O_grey 对齐)
    // -------------------------------------------------------------------------
    (* ram_style = "block" *) reg [2:0] ctrl_mem [0:IMG_WIDTH-1]; // {valid,last,user}
    reg [2:0] ctrl_lb, ctrl_d1, ctrl_d2;
    reg       v_row0, v_row0_d1, v_row0_d2;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            ctrl_lb   <= 3'd0;
            ctrl_d1   <= 3'd0;
            ctrl_d2   <= 3'd0;
            v_row0    <= 1'b0;
            v_row0_d1 <= 1'b0;
            v_row0_d2 <= 1'b0;
        end else begin
            if (I_tvalid) begin
                ctrl_mem[eff_waddr] <= {I_tvalid, I_tlast, I_tuser};
                ctrl_lb <= ctrl_mem[raddr];
            end
            ctrl_d1 <= ctrl_lb;
            ctrl_d2 <= ctrl_d1;
            // 输出第 0 行由边缘复制产生, 该行有效需强制置 1
            v_row0    <= I_tvalid && (row_cnt == 11'd0);
            v_row0_d1 <= v_row0;
            v_row0_d2 <= v_row0_d1;
        end
    end

    assign O_tvalid = ctrl_d2[2] | v_row0_d2;
    assign O_tlast  = ctrl_d2[1];
    assign O_tuser  = ctrl_d2[0];

endmodule
