
//   1. 接收低分辨率人脸坐标并等比放大 6 倍到 1280x720
//   2. 采用帧保持机制防止边框闪烁
//   3. 在高清视频流上实时绘制 3 像素粗的亮绿色人脸矩形边框

module osd_box_drawer #(
    parameter IN_WIDTH     = 1280,             
    parameter IN_HEIGHT    = 720,              
    parameter SCALE_FACTOR = 6,                // 放大倍率
    parameter LINE_THICK   = 3,                // 边框线宽 
    parameter BOX_COLOR    = 24'h00FF00,       // 边框颜色 (亮绿色 RGB888)
    parameter HOLD_FRAMES  = 15                // 人脸离开后框保留的帧数 (防丢帧闪烁)
)(
    input  wire        I_clk,                  // S_hdmi_pixel_clk
    input  wire        I_rst_n,                // 异步复位
    
    // 输入来自 ISP/Mixer 的原始 1280x720 高清视频流
    input  wire        I_tvalid,
    input  wire        I_tuser,                // 帧起始
    input  wire        I_tlast,                // 行结束
    input  wire [23:0] I_tdata,                // 原始高清像素数据
    
    // 输入来自 lbp_detector_engine 的人脸检测结果
    input  wire        I_face_valid,           // 人脸脉冲
    input  wire [7:0]  I_face_x,               // 人脸左上角 X (0~212)
    input  wire [7:0]  I_face_y,               // 人脸左上角 Y (0~119)
    input  wire [7:0]  I_face_w,               // 人脸宽度 (24)
    input  wire [7:0]  I_face_h,               // 人脸高度 (24)
    
    // 输出画框后的高清 AXI-Stream 流 (送往 hdmi_tx)
    output reg         O_tvalid,
    output reg         O_tuser,
    output reg         O_tlast,
    output reg  [23:0] O_tdata
);

    
    // 1. 高清画面当前扫描像素坐标跟踪 (0~1279, 0~719)
    
    reg [10:0] cur_x;
    reg [9:0]  cur_y;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            cur_x <= 11'd0;
            cur_y <= 10'd0;
        end else if (I_tuser) begin
            cur_x <= 11'd0;
            cur_y <= 10'd0;
        end else if (I_tvalid) begin
            if (I_tlast || (cur_x == IN_WIDTH - 1)) begin
                cur_x <= 11'd0;
                cur_y <= (cur_y == IN_HEIGHT - 1) ? 10'd0 : cur_y + 1'b1;
            end else begin
                cur_x <= cur_x + 1'b1;
            end
        end
    end

    
    // 2. 坐标放大与帧保持锁存 (防闪烁)
    
    reg [10:0] box_x1, box_x2;
    reg [9:0]  box_y1, box_y2;
    reg [5:0]  hold_cnt;
    reg        box_enable;

    // 移位相加实现乘以 6: (val << 2) + (val << 1)
    wire [10:0] scaled_x = {3'b000, I_face_x, 2'b00} + {4'b0000, I_face_x, 1'b0};
    wire [9:0]  scaled_y = {2'b00,  I_face_y, 2'b00} + {3'b000,  I_face_y, 1'b0};
    wire [10:0] scaled_w = 11'd144; // 24 * 6 = 144
    wire [9:0]  scaled_h = 10'd144;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            box_x1     <= 11'd0;
            box_y1     <= 10'd0;
            box_x2     <= 11'd0;
            box_y2     <= 10'd0;
            hold_cnt   <= 6'd0;
            box_enable <= 1'b0;
        end else begin
            // 抓取到新人脸，更新坐标并重置保持计时器
            if (I_face_valid) begin
                box_x1     <= scaled_x;
                box_y1     <= scaled_y;
                box_x2     <= (scaled_x + scaled_w >= IN_WIDTH) ? (IN_WIDTH - 1) : (scaled_x + scaled_w);
                box_y2     <= (scaled_y + scaled_h >= IN_HEIGHT) ? (IN_HEIGHT - 1) : (scaled_y + scaled_h);
                hold_cnt   <= HOLD_FRAMES;
                box_enable <= 1'b1;
            end else if (I_tuser) begin
                // 每过一帧，保持倒计时减 1
                if (hold_cnt > 0) begin
                    hold_cnt <= hold_cnt - 1'b1;
                end else begin
                    box_enable <= 1'b0; // 超时无脸，关闭画框
                end
            end
        end
    end

    
    // 3. 边框命中判断 (带线宽检测)
    
    // 判断当前扫描点 (cur_x, cur_y) 是否落在矩形框的 4 条边上
    wire in_box_x_range = (cur_x >= box_x1) && (cur_x <= box_x2);
    wire in_box_y_range = (cur_y >= box_y1) && (cur_y <= box_y2);

    // 上边与下边 (水平线)
    wire on_top_border    = (cur_y >= box_y1) && (cur_y < box_y1 + LINE_THICK) && in_box_x_range;
    wire on_bottom_border = (cur_y > box_y2 - LINE_THICK) && (cur_y <= box_y2) && in_box_x_range;

    // 左边与右边 (垂直线)
    wire on_left_border   = (cur_x >= box_x1) && (cur_x < box_x1 + LINE_THICK) && in_box_y_range;
    wire on_right_border  = (cur_x > box_x2 - LINE_THICK) && (cur_x <= box_x2) && in_box_y_range;

    // 命中边框标志
    wire hit_border = box_enable && (on_top_border || on_bottom_border || on_left_border || on_right_border);

    // =========================================================================
    // 4. 流水线打拍输出 (严格保持 AXI-Stream 时序对齐)
    // =========================================================================
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_tvalid <= 1'b0;
            O_tuser  <= 1'b0;
            O_tlast  <= 1'b0;
            O_tdata  <= 24'd0;
        end else begin
            O_tvalid <= I_tvalid;
            O_tuser  <= I_tuser;
            O_tlast  <= I_tlast;

            // 命中边框替换为绿色，未命中保留原始高清视频
            if (I_tvalid) begin
                O_tdata <= hit_border ? BOX_COLOR : I_tdata;
            end else begin
                O_tdata <= 24'd0;
            end
        end
    end

endmodule