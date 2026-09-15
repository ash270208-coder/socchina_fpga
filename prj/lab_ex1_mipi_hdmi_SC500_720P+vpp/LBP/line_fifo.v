
// 模块名称: line_fifo.v
// 功能: 单行延迟器 (水管)
// 作用: 灌入当前行像素，流出上一行同一位置的像素

module line_fifo #(
    parameter DATA_WIDTH = 25,   // 24位积分图 + 1位肤色 = 25位
    parameter LINE_LEN   = 170   // 一行有 170 个像素点
)(
    input  wire                  I_clk,
    input  wire                  I_rst_n,
    input  wire                  wr_en, // 数据有效时才工作 (I_tvalid)
    input  wire [DATA_WIDTH-1:0] din,   // 进水: 当前行的像素数据
    output reg  [DATA_WIDTH-1:0] dout   // 出水: 上一行同一列的像素数据
);

    // 内部申请一个深度为 170 的片上存储空间 (Block RAM)
    reg [DATA_WIDTH-1:0] ram [0:LINE_LEN-1];
    reg [7:0] addr; // 0 ~ 169 的读写指针

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            addr <= 8'd0;
            dout <= {DATA_WIDTH{1'b0}};
        end else if (wr_en) begin
            // 1. 先把存储器里存着的“上一行同一列数据”读出来
            dout <= ram[addr];
            
            // 2. 把刚刚进来的“新一行数据”写进去占位
            ram[addr] <= din;
            
            // 3. 指针前移，走到 169 自动归零
            if (addr == LINE_LEN - 1)
                addr <= 8'd0;
            else
                addr <= addr + 1'b1;
        end
    end

endmodule
