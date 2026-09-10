`timescale 1ns / 1ps
//=============================================================
// osd_char_lib.v
// 自研 32x40 等宽粗体 ASCII 点阵字符库（由 Consolas Bold 生成），
// 用于 OSD 模式文字显示。字符集：M O D E : R G B A Y H I S T L 空格
// 输出 O_row_bits[31:0]，bit31 对应字符最左列，bit0 对应最右列。
// 每个字符占 40 行（行 0..39），行 0/39 为上下留白。
//=============================================================
module osd_char_lib (
    input  wire [7:0]  I_char,      // ASCII 码
    input  wire [5:0] I_row,       // 点阵行号 0..39
    output reg  [31:0] O_row_bits   // 该行 32 位点阵
);

    function [31:0] F_char_row;
        input [7:0]  I_char;
        input [5:0]  I_row;
        begin
            case (I_char)
                //---------------- 'M' (0x4D) ----------------
                8'h4D: begin
                    case (I_row)
                        6'd 0: F_char_row = 32'h00000000;
                        6'd 2: F_char_row = 32'h1FE00FF8;
                        6'd 3: F_char_row = 32'h1FF00FF8;
                        6'd 4: F_char_row = 32'h1FF00FF8;
                        6'd 5: F_char_row = 32'h1FF01FF8;
                        6'd 6: F_char_row = 32'h1FF81FF8;
                        6'd 7: F_char_row = 32'h1FF81FF8;
                        6'd 8: F_char_row = 32'h1FF81FF8;
                        6'd 9: F_char_row = 32'h1FF83FF8;
                        6'd10: F_char_row = 32'h1FFC3FF8;
                        6'd11: F_char_row = 32'h1F7C3EF8;
                        6'd12: F_char_row = 32'h1F7C7CF8;
                        6'd13: F_char_row = 32'h1F7E7CF8;
                        6'd14: F_char_row = 32'h1F3E7CF8;
                        6'd15: F_char_row = 32'h1F3E78F8;
                        6'd16: F_char_row = 32'h1F3EF8F8;
                        6'd17: F_char_row = 32'h3F3FF8F8;
                        6'd18: F_char_row = 32'h3F1FF0F8;
                        6'd19: F_char_row = 32'h3F1FF0FC;
                        6'd20: F_char_row = 32'h3F1FF0FC;
                        6'd21: F_char_row = 32'h3F0FF0FC;
                        6'd22: F_char_row = 32'h3F0FE0FC;
                        6'd23: F_char_row = 32'h3F0FE0FC;
                        6'd24: F_char_row = 32'h3F0FE0FC;
                        6'd25: F_char_row = 32'h3F07C0FC;
                        6'd26: F_char_row = 32'h3F07C0FC;
                        6'd27: F_char_row = 32'h3F0000FC;
                        6'd28: F_char_row = 32'h3F0000FC;
                        6'd29: F_char_row = 32'h3F0000FC;
                        6'd30: F_char_row = 32'h3F0000FC;
                        6'd31: F_char_row = 32'h3E0000FC;
                        6'd32: F_char_row = 32'h3E0000FC;
                        6'd33: F_char_row = 32'h3E0000FC;
                        6'd34: F_char_row = 32'h3E0000FC;
                        6'd35: F_char_row = 32'h3E0000FC;
                        6'd36: F_char_row = 32'h3E0000FC;
                        6'd37: F_char_row = 32'h7E0000FC;
                        6'd39: F_char_row = 32'h00000000;
                        default: F_char_row = 8'd0;
                    endcase
                end
                //---------------- 'O' (0x4F) ----------------
                8'h4F: begin
                    case (I_row)
                        6'd 0: F_char_row = 32'h00000000;
                        6'd 1: F_char_row = 32'h000FF800;
                        6'd 2: F_char_row = 32'h003FFE00;
                        6'd 3: F_char_row = 32'h00FFFF80;
                        6'd 4: F_char_row = 32'h01FFFFC0;
                        6'd 5: F_char_row = 32'h03FFFFE0;
                        6'd 6: F_char_row = 32'h07FFFFF0;
                        6'd 7: F_char_row = 32'h0FFC3FF0;
                        6'd 8: F_char_row = 32'h0FF00FF8;
                        6'd 9: F_char_row = 32'h1FE007F8;
                        6'd10: F_char_row = 32'h1FC003F8;
                        6'd11: F_char_row = 32'h3FC003FC;
                        6'd12: F_char_row = 32'h3F8001FC;
                        6'd13: F_char_row = 32'h3F8001FC;
                        6'd14: F_char_row = 32'h3F8001FC;
                        6'd15: F_char_row = 32'h3F8001FC;
                        6'd16: F_char_row = 32'h7F8001FE;
                        6'd17: F_char_row = 32'h7F8001FE;
                        6'd18: F_char_row = 32'h7F8001FE;
                        6'd19: F_char_row = 32'h7F8001FE;
                        6'd20: F_char_row = 32'h7F8001FE;
                        6'd21: F_char_row = 32'h7F8001FE;
                        6'd22: F_char_row = 32'h7F8001FE;
                        6'd23: F_char_row = 32'h7F8001FE;
                        6'd24: F_char_row = 32'h7F8001FC;
                        6'd25: F_char_row = 32'h3F8001FC;
                        6'd26: F_char_row = 32'h3F8001FC;
                        6'd27: F_char_row = 32'h3F8001FC;
                        6'd28: F_char_row = 32'h3FC003FC;
                        6'd29: F_char_row = 32'h3FC003F8;
                        6'd30: F_char_row = 32'h1FE007F8;
                        6'd31: F_char_row = 32'h1FF00FF0;
                        6'd32: F_char_row = 32'h0FFC3FF0;
                        6'd33: F_char_row = 32'h0FFFFFE0;
                        6'd34: F_char_row = 32'h07FFFFC0;
                        6'd35: F_char_row = 32'h03FFFF80;
                        6'd36: F_char_row = 32'h01FFFF00;
                        6'd37: F_char_row = 32'h007FFC00;
                        6'd38: F_char_row = 32'h001FF000;
                        6'd39: F_char_row = 32'h00000000;
                        default: F_char_row = 8'd0;
                    endcase
                end
                //---------------- 'D' (0x44) ----------------
                8'h44: begin
                    case (I_row)
                        6'd 0: F_char_row = 32'h00000000;
                        6'd 2: F_char_row = 32'h1FFFF000;
                        6'd 3: F_char_row = 32'h1FFFFE00;
                        6'd 4: F_char_row = 32'h1FFFFF00;
                        6'd 5: F_char_row = 32'h1FFFFFC0;
                        6'd 6: F_char_row = 32'h1FFFFFE0;
                        6'd 7: F_char_row = 32'h1FC0FFE0;
                        6'd 8: F_char_row = 32'h1F803FF0;
                        6'd 9: F_char_row = 32'h1F800FF0;
                        6'd10: F_char_row = 32'h1F8007F8;
                        6'd11: F_char_row = 32'h1F8007F8;
                        6'd12: F_char_row = 32'h1F8003F8;
                        6'd13: F_char_row = 32'h1F8003FC;
                        6'd14: F_char_row = 32'h1F8003FC;
                        6'd15: F_char_row = 32'h1F8001FC;
                        6'd16: F_char_row = 32'h1F8001FC;
                        6'd17: F_char_row = 32'h1F8001FC;
                        6'd18: F_char_row = 32'h1F8001FC;
                        6'd19: F_char_row = 32'h1F8001FC;
                        6'd20: F_char_row = 32'h1F8001FC;
                        6'd21: F_char_row = 32'h1F8001FC;
                        6'd22: F_char_row = 32'h1F8001FC;
                        6'd23: F_char_row = 32'h1F8001FC;
                        6'd24: F_char_row = 32'h1F8003FC;
                        6'd25: F_char_row = 32'h1F8003FC;
                        6'd26: F_char_row = 32'h1F8003F8;
                        6'd27: F_char_row = 32'h1F8007F8;
                        6'd28: F_char_row = 32'h1F8007F8;
                        6'd29: F_char_row = 32'h1F800FF0;
                        6'd30: F_char_row = 32'h1F801FF0;
                        6'd31: F_char_row = 32'h1F803FE0;
                        6'd32: F_char_row = 32'h1FC3FFC0;
                        6'd33: F_char_row = 32'h1FFFFFC0;
                        6'd34: F_char_row = 32'h1FFFFF00;
                        6'd35: F_char_row = 32'h1FFFFE00;
                        6'd36: F_char_row = 32'h1FFFF800;
                        6'd37: F_char_row = 32'h1FFFC000;
                        6'd39: F_char_row = 32'h00000000;
                        default: F_char_row = 8'd0;
                    endcase
                end
                //---------------- 'E' (0x45) ----------------
                8'h45: begin
                    case (I_row)
                        6'd 0: F_char_row = 32'h00000000;
                        6'd 2: F_char_row = 32'h07FFFFE0;
                        6'd 3: F_char_row = 32'h07FFFFE0;
                        6'd 4: F_char_row = 32'h07FFFFE0;
                        6'd 5: F_char_row = 32'h07FFFFE0;
                        6'd 6: F_char_row = 32'h07FFFFE0;
                        6'd 7: F_char_row = 32'h07F80000;
                        6'd 8: F_char_row = 32'h07F00000;
                        6'd 9: F_char_row = 32'h07F00000;
                        6'd10: F_char_row = 32'h07F00000;
                        6'd11: F_char_row = 32'h07F00000;
                        6'd12: F_char_row = 32'h07F00000;
                        6'd13: F_char_row = 32'h07F00000;
                        6'd14: F_char_row = 32'h07F00000;
                        6'd15: F_char_row = 32'h07F00000;
                        6'd16: F_char_row = 32'h07FFFF40;
                        6'd17: F_char_row = 32'h07FFFFE0;
                        6'd18: F_char_row = 32'h07FFFFE0;
                        6'd19: F_char_row = 32'h07FFFFE0;
                        6'd20: F_char_row = 32'h07FFFFE0;
                        6'd21: F_char_row = 32'h07FFFFE0;
                        6'd22: F_char_row = 32'h07F00000;
                        6'd23: F_char_row = 32'h07F00000;
                        6'd24: F_char_row = 32'h07F00000;
                        6'd25: F_char_row = 32'h07F00000;
                        6'd26: F_char_row = 32'h07F00000;
                        6'd27: F_char_row = 32'h07F00000;
                        6'd28: F_char_row = 32'h07F00000;
                        6'd29: F_char_row = 32'h07F00000;
                        6'd30: F_char_row = 32'h07F00000;
                        6'd31: F_char_row = 32'h07F00000;
                        6'd32: F_char_row = 32'h07FFFFE0;
                        6'd33: F_char_row = 32'h07FFFFE0;
                        6'd34: F_char_row = 32'h07FFFFE0;
                        6'd35: F_char_row = 32'h07FFFFE0;
                        6'd36: F_char_row = 32'h07FFFFE0;
                        6'd37: F_char_row = 32'h07FFFFE0;
                        6'd39: F_char_row = 32'h00000000;
                        default: F_char_row = 8'd0;
                    endcase
                end
                //---------------- 'R' (0x52) ----------------
                8'h52: begin
                    case (I_row)
                        6'd 0: F_char_row = 32'h00000000;
                        6'd 2: F_char_row = 32'h0FFFF800;
                        6'd 3: F_char_row = 32'h0FFFFF00;
                        6'd 4: F_char_row = 32'h0FFFFF80;
                        6'd 5: F_char_row = 32'h0FFFFFC0;
                        6'd 6: F_char_row = 32'h0FFFFFE0;
                        6'd 7: F_char_row = 32'h0FE0FFE0;
                        6'd 8: F_char_row = 32'h0FE01FE0;
                        6'd 9: F_char_row = 32'h0FE00FF0;
                        6'd10: F_char_row = 32'h0FE00FF0;
                        6'd11: F_char_row = 32'h0FE007F0;
                        6'd12: F_char_row = 32'h0FE007F0;
                        6'd13: F_char_row = 32'h0FE00FF0;
                        6'd14: F_char_row = 32'h0FE00FE0;
                        6'd15: F_char_row = 32'h0FE01FE0;
                        6'd16: F_char_row = 32'h0FE03FE0;
                        6'd17: F_char_row = 32'h0FE1FFC0;
                        6'd18: F_char_row = 32'h0FFFFF80;
                        6'd19: F_char_row = 32'h0FFFFE00;
                        6'd20: F_char_row = 32'h0FFFF800;
                        6'd21: F_char_row = 32'h0FFFF800;
                        6'd22: F_char_row = 32'h0FFFFC00;
                        6'd23: F_char_row = 32'h0FE3FE00;
                        6'd24: F_char_row = 32'h0FE0FF00;
                        6'd25: F_char_row = 32'h0FE07F00;
                        6'd26: F_char_row = 32'h0FE07F80;
                        6'd27: F_char_row = 32'h0FE03F80;
                        6'd28: F_char_row = 32'h0FE03FC0;
                        6'd29: F_char_row = 32'h0FE03FC0;
                        6'd30: F_char_row = 32'h0FE01FE0;
                        6'd31: F_char_row = 32'h0FE01FE0;
                        6'd32: F_char_row = 32'h0FE00FF0;
                        6'd33: F_char_row = 32'h0FE00FF0;
                        6'd34: F_char_row = 32'h0FE007F8;
                        6'd35: F_char_row = 32'h0FE007F8;
                        6'd36: F_char_row = 32'h0FE007FC;
                        6'd37: F_char_row = 32'h0FE003FC;
                        6'd39: F_char_row = 32'h00000000;
                        default: F_char_row = 8'd0;
                    endcase
                end
                //---------------- 'G' (0x47) ----------------
                8'h47: begin
                    case (I_row)
                        6'd 0: F_char_row = 32'h00000000;
                        6'd 1: F_char_row = 32'h0003FF80;
                        6'd 2: F_char_row = 32'h001FFFF0;
                        6'd 3: F_char_row = 32'h007FFFF8;
                        6'd 4: F_char_row = 32'h00FFFFF8;
                        6'd 5: F_char_row = 32'h01FFFFF8;
                        6'd 6: F_char_row = 32'h03FFFFF8;
                        6'd 7: F_char_row = 32'h07FF83F8;
                        6'd 8: F_char_row = 32'h0FFC0018;
                        6'd 9: F_char_row = 32'h0FF80000;
                        6'd10: F_char_row = 32'h1FF00000;
                        6'd11: F_char_row = 32'h1FE00000;
                        6'd12: F_char_row = 32'h1FC00000;
                        6'd13: F_char_row = 32'h3FC00000;
                        6'd14: F_char_row = 32'h3FC00000;
                        6'd15: F_char_row = 32'h3F800000;
                        6'd16: F_char_row = 32'h3F800000;
                        6'd17: F_char_row = 32'h3F80FFF8;
                        6'd18: F_char_row = 32'h3F80FFF8;
                        6'd19: F_char_row = 32'h3F80FFF8;
                        6'd20: F_char_row = 32'h3F80FFF8;
                        6'd21: F_char_row = 32'h3F80FFF8;
                        6'd22: F_char_row = 32'h3F80FFF8;
                        6'd23: F_char_row = 32'h3F8003F8;
                        6'd24: F_char_row = 32'h3F8003F8;
                        6'd25: F_char_row = 32'h3F8003F8;
                        6'd26: F_char_row = 32'h3FC003F8;
                        6'd27: F_char_row = 32'h3FC003F8;
                        6'd28: F_char_row = 32'h1FE003F8;
                        6'd29: F_char_row = 32'h1FE003F8;
                        6'd30: F_char_row = 32'h1FF003F8;
                        6'd31: F_char_row = 32'h0FF803F8;
                        6'd32: F_char_row = 32'h07FF07F8;
                        6'd33: F_char_row = 32'h07FFFFF8;
                        6'd34: F_char_row = 32'h03FFFFF8;
                        6'd35: F_char_row = 32'h01FFFFF8;
                        6'd36: F_char_row = 32'h00FFFFF8;
                        6'd37: F_char_row = 32'h003FFFE0;
                        6'd38: F_char_row = 32'h0007FF00;
                        6'd39: F_char_row = 32'h00000000;
                        default: F_char_row = 8'd0;
                    endcase
                end
                //---------------- 'B' (0x42) ----------------
                8'h42: begin
                    case (I_row)
                        6'd 0: F_char_row = 32'h00000000;
                        6'd 2: F_char_row = 32'h0FFFFC00;
                        6'd 3: F_char_row = 32'h0FFFFF80;
                        6'd 4: F_char_row = 32'h0FFFFFC0;
                        6'd 5: F_char_row = 32'h0FFFFFE0;
                        6'd 6: F_char_row = 32'h0FFFFFE0;
                        6'd 7: F_char_row = 32'h0FE03FF0;
                        6'd 8: F_char_row = 32'h0FE00FF0;
                        6'd 9: F_char_row = 32'h0FE00FF0;
                        6'd10: F_char_row = 32'h0FE007F0;
                        6'd11: F_char_row = 32'h0FE007F0;
                        6'd12: F_char_row = 32'h0FE007F0;
                        6'd13: F_char_row = 32'h0FE007F0;
                        6'd14: F_char_row = 32'h0FE00FE0;
                        6'd15: F_char_row = 32'h0FE01FE0;
                        6'd16: F_char_row = 32'h0FE07FC0;
                        6'd17: F_char_row = 32'h0FFFFF80;
                        6'd18: F_char_row = 32'h0FFFFF00;
                        6'd19: F_char_row = 32'h0FFFFF80;
                        6'd20: F_char_row = 32'h0FFFFFE0;
                        6'd21: F_char_row = 32'h0FFFFFF0;
                        6'd22: F_char_row = 32'h0FE01FF0;
                        6'd23: F_char_row = 32'h0FE007F8;
                        6'd24: F_char_row = 32'h0FE007F8;
                        6'd25: F_char_row = 32'h0FE003F8;
                        6'd26: F_char_row = 32'h0FE003FC;
                        6'd27: F_char_row = 32'h0FE003FC;
                        6'd28: F_char_row = 32'h0FE003F8;
                        6'd29: F_char_row = 32'h0FE003F8;
                        6'd30: F_char_row = 32'h0FE007F8;
                        6'd31: F_char_row = 32'h0FE00FF8;
                        6'd32: F_char_row = 32'h0FE0FFF0;
                        6'd33: F_char_row = 32'h0FFFFFF0;
                        6'd34: F_char_row = 32'h0FFFFFE0;
                        6'd35: F_char_row = 32'h0FFFFFC0;
                        6'd36: F_char_row = 32'h0FFFFF00;
                        6'd37: F_char_row = 32'h0FFFF800;
                        6'd39: F_char_row = 32'h00000000;
                        default: F_char_row = 8'd0;
                    endcase
                end
                //---------------- 'A' (0x41) ----------------
                8'h41: begin
                    case (I_row)
                        6'd 0: F_char_row = 32'h00000000;
                        6'd 2: F_char_row = 32'h001FF800;
                        6'd 3: F_char_row = 32'h001FF800;
                        6'd 4: F_char_row = 32'h003FFC00;
                        6'd 5: F_char_row = 32'h003FFC00;
                        6'd 6: F_char_row = 32'h003FFC00;
                        6'd 7: F_char_row = 32'h007FFE00;
                        6'd 8: F_char_row = 32'h007FFE00;
                        6'd 9: F_char_row = 32'h007EFE00;
                        6'd10: F_char_row = 32'h00FEFE00;
                        6'd11: F_char_row = 32'h00FE7F00;
                        6'd12: F_char_row = 32'h00FC7F00;
                        6'd13: F_char_row = 32'h00FC7F00;
                        6'd14: F_char_row = 32'h01FC7F80;
                        6'd15: F_char_row = 32'h01FC3F80;
                        6'd16: F_char_row = 32'h01F83F80;
                        6'd17: F_char_row = 32'h03F83F80;
                        6'd18: F_char_row = 32'h03F81FC0;
                        6'd19: F_char_row = 32'h03F01FC0;
                        6'd20: F_char_row = 32'h03F01FC0;
                        6'd21: F_char_row = 32'h07F01FE0;
                        6'd22: F_char_row = 32'h07F00FE0;
                        6'd23: F_char_row = 32'h07E00FE0;
                        6'd24: F_char_row = 32'h0FE00FF0;
                        6'd25: F_char_row = 32'h0FFFFFF0;
                        6'd26: F_char_row = 32'h0FFFFFF0;
                        6'd27: F_char_row = 32'h1FFFFFF0;
                        6'd28: F_char_row = 32'h1FFFFFF8;
                        6'd29: F_char_row = 32'h1FFFFFF8;
                        6'd30: F_char_row = 32'h1FFFFFF8;
                        6'd31: F_char_row = 32'h3F8003FC;
                        6'd32: F_char_row = 32'h3F8003FC;
                        6'd33: F_char_row = 32'h3F8001FC;
                        6'd34: F_char_row = 32'h7F0001FC;
                        6'd35: F_char_row = 32'h7F0001FE;
                        6'd36: F_char_row = 32'h7F0000FE;
                        6'd37: F_char_row = 32'hFE0000FE;
                        6'd39: F_char_row = 32'h00000000;
                        default: F_char_row = 8'd0;
                    endcase
                end
                //---------------- 'Y' (0x59) ----------------
                8'h59: begin
                    case (I_row)
                        6'd 0: F_char_row = 32'h00000000;
                        6'd 2: F_char_row = 32'h7F8000FE;
                        6'd 3: F_char_row = 32'h7F8001FC;
                        6'd 4: F_char_row = 32'h3FC001FC;
                        6'd 5: F_char_row = 32'h3FC003F8;
                        6'd 6: F_char_row = 32'h1FC003F8;
                        6'd 7: F_char_row = 32'h1FE007F0;
                        6'd 8: F_char_row = 32'h0FE007F0;
                        6'd 9: F_char_row = 32'h0FF00FE0;
                        6'd10: F_char_row = 32'h07F00FE0;
                        6'd11: F_char_row = 32'h07F81FC0;
                        6'd12: F_char_row = 32'h03F81FC0;
                        6'd13: F_char_row = 32'h03FC3F80;
                        6'd14: F_char_row = 32'h01FC3F80;
                        6'd15: F_char_row = 32'h01FE7F00;
                        6'd16: F_char_row = 32'h00FE7F00;
                        6'd17: F_char_row = 32'h00FEFE00;
                        6'd18: F_char_row = 32'h007FFE00;
                        6'd19: F_char_row = 32'h007FFC00;
                        6'd20: F_char_row = 32'h003FFC00;
                        6'd21: F_char_row = 32'h003FF800;
                        6'd22: F_char_row = 32'h001FF800;
                        6'd23: F_char_row = 32'h001FF000;
                        6'd24: F_char_row = 32'h000FF000;
                        6'd25: F_char_row = 32'h000FE000;
                        6'd26: F_char_row = 32'h000FE000;
                        6'd27: F_char_row = 32'h000FE000;
                        6'd28: F_char_row = 32'h000FE000;
                        6'd29: F_char_row = 32'h000FE000;
                        6'd30: F_char_row = 32'h000FE000;
                        6'd31: F_char_row = 32'h000FE000;
                        6'd32: F_char_row = 32'h000FE000;
                        6'd33: F_char_row = 32'h000FE000;
                        6'd34: F_char_row = 32'h000FE000;
                        6'd35: F_char_row = 32'h000FE000;
                        6'd36: F_char_row = 32'h000FE000;
                        6'd37: F_char_row = 32'h000FE000;
                        6'd39: F_char_row = 32'h00000000;
                        default: F_char_row = 8'd0;
                    endcase
                end
                //---------------- 'H' (0x48) ----------------
                8'h48: begin
                    case (I_row)
                        6'd 0: F_char_row = 32'h00000000;
                        6'd 2: F_char_row = 32'h1FC003F8;
                        6'd 3: F_char_row = 32'h1FC003F8;
                        6'd 4: F_char_row = 32'h1FC003F8;
                        6'd 5: F_char_row = 32'h1FC003F8;
                        6'd 6: F_char_row = 32'h1FC003F8;
                        6'd 7: F_char_row = 32'h1FC003F8;
                        6'd 8: F_char_row = 32'h1FC003F8;
                        6'd 9: F_char_row = 32'h1FC003F8;
                        6'd10: F_char_row = 32'h1FC003F8;
                        6'd11: F_char_row = 32'h1FC003F8;
                        6'd12: F_char_row = 32'h1FC003F8;
                        6'd13: F_char_row = 32'h1FC003F8;
                        6'd14: F_char_row = 32'h1FC003F8;
                        6'd15: F_char_row = 32'h1FC003F8;
                        6'd16: F_char_row = 32'h1FFFFFF8;
                        6'd17: F_char_row = 32'h1FFFFFF8;
                        6'd18: F_char_row = 32'h1FFFFFF8;
                        6'd19: F_char_row = 32'h1FFFFFF8;
                        6'd20: F_char_row = 32'h1FFFFFF8;
                        6'd21: F_char_row = 32'h1FFFFFF8;
                        6'd22: F_char_row = 32'h1FC003F8;
                        6'd23: F_char_row = 32'h1FC003F8;
                        6'd24: F_char_row = 32'h1FC003F8;
                        6'd25: F_char_row = 32'h1FC003F8;
                        6'd26: F_char_row = 32'h1FC003F8;
                        6'd27: F_char_row = 32'h1FC003F8;
                        6'd28: F_char_row = 32'h1FC003F8;
                        6'd29: F_char_row = 32'h1FC003F8;
                        6'd30: F_char_row = 32'h1FC003F8;
                        6'd31: F_char_row = 32'h1FC003F8;
                        6'd32: F_char_row = 32'h1FC003F8;
                        6'd33: F_char_row = 32'h1FC003F8;
                        6'd34: F_char_row = 32'h1FC003F8;
                        6'd35: F_char_row = 32'h1FC003F8;
                        6'd36: F_char_row = 32'h1FC003F8;
                        6'd37: F_char_row = 32'h1FC003F8;
                        6'd39: F_char_row = 32'h00000000;
                        default: F_char_row = 8'd0;
                    endcase
                end
                //---------------- 'I' (0x49) ----------------
                8'h49: begin
                    case (I_row)
                        6'd 0: F_char_row = 32'h00000000;
                        6'd 2: F_char_row = 32'h0FFFFFF0;
                        6'd 3: F_char_row = 32'h0FFFFFF0;
                        6'd 4: F_char_row = 32'h0FFFFFF0;
                        6'd 5: F_char_row = 32'h0FFFFFF0;
                        6'd 6: F_char_row = 32'h0FFFFFF0;
                        6'd 7: F_char_row = 32'h000FF000;
                        6'd 8: F_char_row = 32'h000FE000;
                        6'd 9: F_char_row = 32'h000FE000;
                        6'd10: F_char_row = 32'h000FE000;
                        6'd11: F_char_row = 32'h000FE000;
                        6'd12: F_char_row = 32'h000FE000;
                        6'd13: F_char_row = 32'h000FE000;
                        6'd14: F_char_row = 32'h000FE000;
                        6'd15: F_char_row = 32'h000FE000;
                        6'd16: F_char_row = 32'h000FE000;
                        6'd17: F_char_row = 32'h000FE000;
                        6'd18: F_char_row = 32'h000FE000;
                        6'd19: F_char_row = 32'h000FE000;
                        6'd20: F_char_row = 32'h000FE000;
                        6'd21: F_char_row = 32'h000FE000;
                        6'd22: F_char_row = 32'h000FE000;
                        6'd23: F_char_row = 32'h000FE000;
                        6'd24: F_char_row = 32'h000FE000;
                        6'd25: F_char_row = 32'h000FE000;
                        6'd26: F_char_row = 32'h000FE000;
                        6'd27: F_char_row = 32'h000FE000;
                        6'd28: F_char_row = 32'h000FE000;
                        6'd29: F_char_row = 32'h000FE000;
                        6'd30: F_char_row = 32'h000FE000;
                        6'd31: F_char_row = 32'h000FE000;
                        6'd32: F_char_row = 32'h000FF000;
                        6'd33: F_char_row = 32'h0FFFFFF0;
                        6'd34: F_char_row = 32'h0FFFFFF0;
                        6'd35: F_char_row = 32'h0FFFFFF0;
                        6'd36: F_char_row = 32'h0FFFFFF0;
                        6'd37: F_char_row = 32'h0FFFFFF0;
                        6'd39: F_char_row = 32'h00000000;
                        default: F_char_row = 8'd0;
                    endcase
                end
                //---------------- 'S' (0x53) ----------------
                8'h53: begin
                    case (I_row)
                        6'd 0: F_char_row = 32'h00000000;
                        6'd 1: F_char_row = 32'h000FFE00;
                        6'd 2: F_char_row = 32'h007FFFC0;
                        6'd 3: F_char_row = 32'h01FFFFC0;
                        6'd 4: F_char_row = 32'h03FFFFC0;
                        6'd 5: F_char_row = 32'h07FFFFC0;
                        6'd 6: F_char_row = 32'h07FFFFC0;
                        6'd 7: F_char_row = 32'h0FF801C0;
                        6'd 8: F_char_row = 32'h0FF00000;
                        6'd 9: F_char_row = 32'h0FE00000;
                        6'd10: F_char_row = 32'h1FE00000;
                        6'd11: F_char_row = 32'h1FE00000;
                        6'd12: F_char_row = 32'h1FE00000;
                        6'd13: F_char_row = 32'h1FF00000;
                        6'd14: F_char_row = 32'h0FFC0000;
                        6'd15: F_char_row = 32'h0FFF0000;
                        6'd16: F_char_row = 32'h07FFE000;
                        6'd17: F_char_row = 32'h07FFF800;
                        6'd18: F_char_row = 32'h03FFFE00;
                        6'd19: F_char_row = 32'h01FFFF80;
                        6'd20: F_char_row = 32'h007FFFC0;
                        6'd21: F_char_row = 32'h001FFFE0;
                        6'd22: F_char_row = 32'h0007FFF0;
                        6'd23: F_char_row = 32'h0000FFF0;
                        6'd24: F_char_row = 32'h00003FF0;
                        6'd25: F_char_row = 32'h00000FF8;
                        6'd26: F_char_row = 32'h000007F8;
                        6'd27: F_char_row = 32'h000007F8;
                        6'd28: F_char_row = 32'h000007F8;
                        6'd29: F_char_row = 32'h000007F8;
                        6'd30: F_char_row = 32'h000007F0;
                        6'd31: F_char_row = 32'h18000FF0;
                        6'd32: F_char_row = 32'h1FC03FF0;
                        6'd33: F_char_row = 32'h1FFFFFE0;
                        6'd34: F_char_row = 32'h1FFFFFC0;
                        6'd35: F_char_row = 32'h1FFFFF80;
                        6'd36: F_char_row = 32'h1FFFFF00;
                        6'd37: F_char_row = 32'h1FFFFC00;
                        6'd38: F_char_row = 32'h01FFE000;
                        6'd39: F_char_row = 32'h00000000;
                        default: F_char_row = 8'd0;
                    endcase
                end
                //---------------- 'T' (0x54) ----------------
                8'h54: begin
                    case (I_row)
                        6'd 0: F_char_row = 32'h00000000;
                        6'd 2: F_char_row = 32'h3FFFFFFC;
                        6'd 3: F_char_row = 32'h3FFFFFFC;
                        6'd 4: F_char_row = 32'h3FFFFFFC;
                        6'd 5: F_char_row = 32'h3FFFFFFC;
                        6'd 6: F_char_row = 32'h3FFFFFFC;
                        6'd 7: F_char_row = 32'h000FF000;
                        6'd 8: F_char_row = 32'h000FE000;
                        6'd 9: F_char_row = 32'h000FE000;
                        6'd10: F_char_row = 32'h000FE000;
                        6'd11: F_char_row = 32'h000FE000;
                        6'd12: F_char_row = 32'h000FE000;
                        6'd13: F_char_row = 32'h000FE000;
                        6'd14: F_char_row = 32'h000FE000;
                        6'd15: F_char_row = 32'h000FE000;
                        6'd16: F_char_row = 32'h000FE000;
                        6'd17: F_char_row = 32'h000FE000;
                        6'd18: F_char_row = 32'h000FE000;
                        6'd19: F_char_row = 32'h000FE000;
                        6'd20: F_char_row = 32'h000FE000;
                        6'd21: F_char_row = 32'h000FE000;
                        6'd22: F_char_row = 32'h000FE000;
                        6'd23: F_char_row = 32'h000FE000;
                        6'd24: F_char_row = 32'h000FE000;
                        6'd25: F_char_row = 32'h000FE000;
                        6'd26: F_char_row = 32'h000FE000;
                        6'd27: F_char_row = 32'h000FE000;
                        6'd28: F_char_row = 32'h000FE000;
                        6'd29: F_char_row = 32'h000FE000;
                        6'd30: F_char_row = 32'h000FE000;
                        6'd31: F_char_row = 32'h000FE000;
                        6'd32: F_char_row = 32'h000FE000;
                        6'd33: F_char_row = 32'h000FE000;
                        6'd34: F_char_row = 32'h000FE000;
                        6'd35: F_char_row = 32'h000FE000;
                        6'd36: F_char_row = 32'h000FE000;
                        6'd37: F_char_row = 32'h000FF000;
                        6'd39: F_char_row = 32'h00000000;
                        default: F_char_row = 8'd0;
                    endcase
                end
                //---------------- 'L' (0x4C) ----------------
                8'h4C: begin
                    case (I_row)
                        6'd 0: F_char_row = 32'h00000000;
                        6'd 2: F_char_row = 32'h03F80000;
                        6'd 3: F_char_row = 32'h03F80000;
                        6'd 4: F_char_row = 32'h03F80000;
                        6'd 5: F_char_row = 32'h03F80000;
                        6'd 6: F_char_row = 32'h03F80000;
                        6'd 7: F_char_row = 32'h03F80000;
                        6'd 8: F_char_row = 32'h03F80000;
                        6'd 9: F_char_row = 32'h03F80000;
                        6'd10: F_char_row = 32'h03F80000;
                        6'd11: F_char_row = 32'h03F80000;
                        6'd12: F_char_row = 32'h03F80000;
                        6'd13: F_char_row = 32'h03F80000;
                        6'd14: F_char_row = 32'h03F80000;
                        6'd15: F_char_row = 32'h03F80000;
                        6'd16: F_char_row = 32'h03F80000;
                        6'd17: F_char_row = 32'h03F80000;
                        6'd18: F_char_row = 32'h03F80000;
                        6'd19: F_char_row = 32'h03F80000;
                        6'd20: F_char_row = 32'h03F80000;
                        6'd21: F_char_row = 32'h03F80000;
                        6'd22: F_char_row = 32'h03F80000;
                        6'd23: F_char_row = 32'h03F80000;
                        6'd24: F_char_row = 32'h03F80000;
                        6'd25: F_char_row = 32'h03F80000;
                        6'd26: F_char_row = 32'h03F80000;
                        6'd27: F_char_row = 32'h03F80000;
                        6'd28: F_char_row = 32'h03F80000;
                        6'd29: F_char_row = 32'h03F80000;
                        6'd30: F_char_row = 32'h03F80000;
                        6'd31: F_char_row = 32'h03F80000;
                        6'd32: F_char_row = 32'h03FFFFF0;
                        6'd33: F_char_row = 32'h03FFFFF0;
                        6'd34: F_char_row = 32'h03FFFFF0;
                        6'd35: F_char_row = 32'h03FFFFF0;
                        6'd36: F_char_row = 32'h03FFFFF0;
                        6'd37: F_char_row = 32'h03FFFFF0;
                        6'd39: F_char_row = 32'h00000000;
                        default: F_char_row = 8'd0;
                    endcase
                end
                //---------------- ':' (0x3A) ----------------
                8'h3A: begin
                    case (I_row)
                        6'd 0: F_char_row = 32'h00000000;
                        6'd10: F_char_row = 32'h0007E000;
                        6'd11: F_char_row = 32'h000FF000;
                        6'd12: F_char_row = 32'h001FF800;
                        6'd13: F_char_row = 32'h001FF800;
                        6'd14: F_char_row = 32'h001FF800;
                        6'd15: F_char_row = 32'h001FF800;
                        6'd16: F_char_row = 32'h001FF800;
                        6'd17: F_char_row = 32'h000FF000;
                        6'd18: F_char_row = 32'h0007E000;
                        6'd19: F_char_row = 32'h00018000;
                        6'd29: F_char_row = 32'h0003C000;
                        6'd30: F_char_row = 32'h000FF000;
                        6'd31: F_char_row = 32'h000FF000;
                        6'd32: F_char_row = 32'h001FF800;
                        6'd33: F_char_row = 32'h001FF800;
                        6'd34: F_char_row = 32'h001FF800;
                        6'd35: F_char_row = 32'h001FF800;
                        6'd36: F_char_row = 32'h000FF000;
                        6'd37: F_char_row = 32'h000FF000;
                        6'd38: F_char_row = 32'h0003C000;
                        6'd39: F_char_row = 32'h00000000;
                        default: F_char_row = 8'd0;
                    endcase
                end
                default: F_char_row = 8'd0;
            endcase
        end
    endfunction

    always @(*) begin
        O_row_bits = F_char_row(I_char, I_row);
    end

endmodule
