module exposure_controller #(
    parameter TARGET_Y  = 128,
    parameter GAIN_FRAC = 12,
    parameter GAIN_MAX  = 65536,
    parameter GAIN_MIN  = 1024,
    parameter MAX_STEP  = 2048
)(
    input               I_clk,
    input               I_rst_n,

    input      [7:0]    I_avg_y,
    input               I_frame_done,

    output reg [23:0]   O_gain
);

    // ---- 除法器位宽 ----
    // TARGET_Y << GAIN_FRAC 最大 255<<12 ≈ 2^20，商同量级
    // 取 24 位留余量，保证 GAIN_MAX(2^16) 也能装下
    localparam DW = 24;

    // ---- 状态机 ----
    localparam S_IDLE = 2'd0;
    localparam S_DIV  = 2'd1;
    localparam S_CALC = 2'd2;

    reg [1:0]    state;
    reg [5:0]    div_cnt;
    reg [DW-1:0] div_rem;
    reg [DW-1:0] div_quo;
    reg [DW-1:0] div_num;   // 被除数，逐拍左移
    reg [DW-1:0] div_den;   // 除数

    reg [DW-1:0]      target;      // 本次算出的目标增益
    reg signed [31:0] gain_acc;    // 当前增益

    // ---- 恢复余数除法器迭代逻辑 ----
    wire [DW-1:0] shifted_rem = {div_rem[DW-2:0], div_num[DW-1]};
    wire          ge_den      = (shifted_rem >= div_den);
    wire [DW-1:0] rem_new     = ge_den ? (shifted_rem - div_den) : shifted_rem;
    wire [DW-1:0] quo_new     = {div_quo[DW-2:0], ge_den};

    // ---- 步长限制 + 钳位 (组合逻辑，只吃寄存器输出，路径很短) ----
    wire signed [31:0] target_s     = $signed({8'd0, target});
    wire signed [31:0] gain_diff    = target_s - gain_acc;
    wire signed [31:0] limited_step = (gain_diff >  $signed(MAX_STEP)) ?  $signed(MAX_STEP)
                                    : (gain_diff < -$signed(MAX_STEP)) ? -$signed(MAX_STEP)
                                    : gain_diff;
    wire signed [31:0] next_gain    = gain_acc + limited_step;
    wire signed [31:0] sat_gain     = (next_gain < $signed(GAIN_MIN)) ? $signed(GAIN_MIN)
                                    : (next_gain > $signed(GAIN_MAX)) ? $signed(GAIN_MAX)
                                    : next_gain;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            state    <= S_IDLE;
            div_cnt  <= 6'd0;
            div_rem  <= {DW{1'b0}};
            div_quo  <= {DW{1'b0}};
            div_num  <= {DW{1'b0}};
            div_den  <= {DW{1'b0}};
            target   <= (TARGET_Y << GAIN_FRAC);   // 初值 1.0
            gain_acc <= $signed(32'd4096);
            O_gain   <= 24'd4096;
        end else begin
            case (state)
                // ---------- 等待帧结束 ----------
                S_IDLE: begin
                    if (I_frame_done) begin
                        if (I_avg_y == 8'd0) begin
                            // 全黑：目标直接置最大，跳过除法
                            target <= GAIN_MAX[DW-1:0];
                            state  <= S_CALC;
                        end else begin
                            // 启动除法：num = TARGET_Y << GAIN_FRAC, den = avg_y
                            div_num <= (TARGET_Y << GAIN_FRAC);
                            div_den <= I_avg_y;
                            div_rem <= {DW{1'b0}};
                            div_quo <= {DW{1'b0}};
                            div_cnt <= DW[5:0];
                            state   <= S_DIV;
                        end
                    end
                end

                // ---------- 多周期除法 (DW 拍) ----------
                S_DIV: begin
                    div_rem <= rem_new;
                    div_quo <= quo_new;
                    div_num <= {div_num[DW-2:0], 1'b0};
                    div_cnt <= div_cnt - 1'b1;
                    if (div_cnt == 6'd1) begin
                        // 最后一次的商还没打进 div_quo，用 quo_new 取完整结果
                        target <= quo_new;
                        state  <= S_CALC;
                    end
                end

                // ---------- 计算限幅并更新增益 ----------
                S_CALC: begin
                    gain_acc <= sat_gain;
                    O_gain   <= sat_gain[23:0];
                    state    <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule