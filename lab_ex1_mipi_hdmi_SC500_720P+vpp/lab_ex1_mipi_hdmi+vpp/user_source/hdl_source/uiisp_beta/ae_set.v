/*********************************************************************
* Module Name: ae_set (纯曝光时间调节优化版)，例程里面的ae_set模块其实是在调节AG（增益）
* 针对 24MHz 时钟优化，具备人眼视觉对数平滑步进，固定低噪声增益
*********************************************************************/
module ae_set (
    input wire        I_clk,            // 24MHz 系统时钟
    input wire        I_rst,            // 高电平复位
    input wire [3:0]  I_btn,            // btn[0]: 减曝光, btn[1]: 加曝光
    input wire        I_ae_cfg_done,    // I2C 配置完成标志
    input wire        I_cam_cfg_done,   // 摄像头初始化完成标志
    output wire       O_ae_req,         // 更新请求脉冲
    output wire[15:0] O_ae,             // 曝光时间输出
    output wire[15:0] O_ag              // 模拟增益输出 (固定低噪声)
);

    // =========================================================================
    // 1. 产生 10ms 的平滑调节时钟节拍 (24MHz / 240,000 = 100Hz)
    // =========================================================================
    reg [18:0] rc_ae_tick = 0;
    reg        r_ae_tick  = 0;

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            rc_ae_tick <= 0;
            r_ae_tick  <= 0;
        end else begin
            if (rc_ae_tick >= 239999) begin // 240,000 个周期 = 严格的 10ms
                rc_ae_tick <= 0;
                r_ae_tick  <= 1'b1;
            end else begin
                rc_ae_tick <= rc_ae_tick + 1'b1;
                r_ae_tick  <= 1'b0;
            end
        end
    end

    // =========================================================================
    // 2. 按键打拍消抖与动态步长计算 (匹配人眼对数感光曲线)
    // =========================================================================
    reg [3:0] r_button_0 = 0, r_button_1 = 0;
    reg [15:0] r_ae_set = 2246;          // 初始设为合法最大曝光，保证开机最亮最纯净
    reg [15:0] step;

    // 动态步长：暗处小步微调(防瞬间暴跌)，亮处大步快调(防迟钝)
    always @(*) begin
        if (r_ae_set < 300)
            step = 16'd4;                // 极暗区：每 10ms 变化 4，过渡极其细腻
        else if (r_ae_set < 1000)
            step = 16'd12;               // 中间过渡区：每 10ms 变化 12
        else
            step = 16'd28;               // 亮区：每 10ms 变化 28，快速回升
    end

    localparam AE_MIN = 16'd80;          // 最低安全曝光 (防死黑，保留暗部轮廓)
    localparam AE_MAX = 16'd2246;        // 720P 模式合法最大曝光行数

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            r_button_0 <= 4'd0;
            r_button_1 <= 4'd0;
            r_ae_set   <= AE_MAX;
        end else begin
            r_button_0 <= ~I_btn;        // 假设低电平按下
            r_button_1 <= r_button_0;

            if (r_ae_tick) begin
                if (r_button_1[0]) begin // 减曝光
                    if (r_ae_set > (AE_MIN + step))
                        r_ae_set <= r_ae_set - step;
                    else
                        r_ae_set <= AE_MIN;
                end else if (r_button_1[1]) begin // 加曝光
                    if (r_ae_set < (AE_MAX - step))
                        r_ae_set <= r_ae_set + step;
                    else
                        r_ae_set <= AE_MAX;
                end
            end
        end
    end

    // =========================================================================
    // 3. 握手与输出：增益固定在 80，拒绝额外噪点；只更新 AE
    // =========================================================================
    reg [15:0] r_ae     = 2246;
    reg [15:0] r_ag     = 87;            // 固定模拟增益在 80 (约 4x 放大，底噪极低)
    reg        r_ae_req = 0;

    assign O_ae     = r_ae;
    assign O_ag     = r_ag;
    assign O_ae_req = r_ae_req;

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            r_ae_req <= 1'b0;
            r_ae     <= AE_MAX;
            r_ag     <= 16'd80;
        end else if (r_ae_req) begin
            r_ae_req <= 1'b0;
        end else if ((r_ae != r_ae_set) && I_cam_cfg_done && I_ae_cfg_done) begin
            r_ae     <= r_ae_set;
            r_ae_req <= 1'b1;            // 触发 I2C 下发新的曝光值
        end
    end

endmodule