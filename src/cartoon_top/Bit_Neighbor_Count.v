`timescale 1ns / 1ps

module Bit_Neighbor_Count #(
    parameter IMG_WIDTH       = 1024,
    parameter IMG_HEIGHT      = 600,
    parameter COUNT_THRESHOLD = 3
)(
    input               I_clk,
    input               I_rst_n,

    input               I_tlast,
    input               I_tuser,
    input               I_per_img_Bit,
    input               I_tvalid,

    output              O_tlast,
    output              O_tuser,
    output              O_per_img_Bit,
    output              O_tvalid
);

    reg [11:0] col_cnt;
    reg [11:0] row_cnt;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            col_cnt <= 12'd0;
            row_cnt <= 12'd0;
        end
        else if (I_tvalid) begin
            if (I_tuser) begin
                col_cnt <= 12'd0;
                row_cnt <= 12'd0;
            end
            else if (I_tlast || (col_cnt == IMG_WIDTH - 1)) begin
                col_cnt <= 12'd0;
                if (row_cnt == IMG_HEIGHT - 1)
                    row_cnt <= 12'd0;
                else
                    row_cnt <= row_cnt + 1'b1;
            end
            else begin
                col_cnt <= col_cnt + 1'b1;
            end
        end
    end

    (* ram_style = "block" *) reg line_buf0 [0:IMG_WIDTH-1];
    (* ram_style = "block" *) reg line_buf1 [0:IMG_WIDTH-1];

    integer init_i;
    initial begin
        for (init_i = 0; init_i < IMG_WIDTH; init_i = init_i + 1) begin
            line_buf0[init_i] = 1'd0;
            line_buf1[init_i] = 1'd0;
        end
    end

    reg row0_data;
    reg row1_data;
    reg row2_data;

    always @(posedge I_clk) begin
        if (I_tvalid) begin
            row0_data <= line_buf0[col_cnt];
            row1_data <= line_buf1[col_cnt];
            row2_data <= I_per_img_Bit;

            line_buf0[col_cnt] <= line_buf1[col_cnt];
            line_buf1[col_cnt] <= I_per_img_Bit;
        end
    end

    reg p11, p12, p13;
    reg p21, p22, p23;
    reg p31, p32, p33;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            p11 <= 1'd0; p12 <= 1'd0; p13 <= 1'd0;
            p21 <= 1'd0; p22 <= 1'd0; p23 <= 1'd0;
            p31 <= 1'd0; p32 <= 1'd0; p33 <= 1'd0;
        end
        else if (I_tvalid) begin
            p11 <= p12; p12 <= p13; p13 <= row0_data;
            p21 <= p22; p22 <= p23; p23 <= row1_data;
            p31 <= p32; p32 <= p33; p33 <= row2_data;
        end
    end

    reg [1:0] row0_cnt;
    reg [1:0] row1_cnt;
    reg [1:0] row2_cnt;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            row0_cnt <= 2'd0;
            row1_cnt <= 2'd0;
            row2_cnt <= 2'd0;
        end
        else if (I_tvalid) begin
            row0_cnt <= p11 + p12 + p13;
            row1_cnt <= p21 + p22 + p23;
            row2_cnt <= p31 + p32 + p33;
        end
    end

    reg edge_out_r;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n)
            edge_out_r <= 1'b0;
        else if (I_tvalid)
            edge_out_r <= ((row0_cnt + row1_cnt + row2_cnt) >= COUNT_THRESHOLD) ? 1'b1 : 1'b0;
    end

    assign O_per_img_Bit = edge_out_r;

    reg [3:0] tvalid_shift;
    reg [3:0] tlast_shift;
    reg [3:0] tuser_shift;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            tvalid_shift <= 4'd0;
            tlast_shift  <= 4'd0;
            tuser_shift  <= 4'd0;
        end
        else begin
            tvalid_shift <= {tvalid_shift[2:0], I_tvalid};
            tlast_shift  <= {tlast_shift[2:0],  I_tlast};
            tuser_shift  <= {tuser_shift[2:0],  I_tuser};
        end
    end

    assign O_tvalid = tvalid_shift[3];
    assign O_tlast  = tlast_shift[3];
    assign O_tuser  = tuser_shift[3];

endmodule