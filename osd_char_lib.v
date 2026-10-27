`timescale 1ns/1ps
// Compact 8x8 font enlarged to a uniform 32x40 glyph window.
module osd_char_lib(input wire [7:0] I_char,input wire [5:0] I_row,output reg [31:0] O_row_bits);
 reg [7:0] bits; integer k;
 always @(*) begin
   bits=8'h00;
   case(I_char)
    "M": case(I_row[5:2]-1) 0:bits=8'b11000011;1:bits=8'b11100111;2:bits=8'b11111111;3:bits=8'b11011011;4:bits=8'b11000011;5:bits=8'b11000011; default:; endcase
    "O": case(I_row[5:2]-1) 0:bits=8'b00111100;1:bits=8'b01100110;2:bits=8'b11000011;3:bits=8'b11000011;4:bits=8'b11000011;5:bits=8'b01100110;6:bits=8'b00111100; default:; endcase
    "D": case(I_row[5:2]-1) 0:bits=8'b11111100;1:bits=8'b11000110;2:bits=8'b11000011;3:bits=8'b11000011;4:bits=8'b11000011;5:bits=8'b11000110;6:bits=8'b11111100; default:; endcase
    "E": case(I_row[5:2]-1) 0:bits=8'b11111111;1:bits=8'b11000000;2:bits=8'b11000000;3:bits=8'b11111110;4:bits=8'b11000000;5:bits=8'b11000000;6:bits=8'b11111111; default:; endcase
    "R": case(I_row[5:2]-1) 0:bits=8'b11111110;1:bits=8'b11000011;2:bits=8'b11000011;3:bits=8'b11111110;4:bits=8'b11011000;5:bits=8'b11001100;6:bits=8'b11000110; default:; endcase
    "G": case(I_row[5:2]-1) 0:bits=8'b00111110;1:bits=8'b11000000;2:bits=8'b11000000;3:bits=8'b11001111;4:bits=8'b11000011;5:bits=8'b11000011;6:bits=8'b00111110; default:; endcase
    "B": case(I_row[5:2]-1) 0:bits=8'b11111110;1:bits=8'b11000011;2:bits=8'b11000110;3:bits=8'b11111100;4:bits=8'b11000110;5:bits=8'b11000011;6:bits=8'b11111110; default:; endcase
    "A": case(I_row[5:2]-1) 0:bits=8'b00111100;1:bits=8'b01100110;2:bits=8'b11000011;3:bits=8'b11111111;4:bits=8'b11000011;5:bits=8'b11000011;6:bits=8'b11000011; default:; endcase
    "Y": case(I_row[5:2]-1) 0:bits=8'b11000011;1:bits=8'b11000011;2:bits=8'b01100110;3:bits=8'b00111100;4:bits=8'b00011000;5:bits=8'b00011000;6:bits=8'b00011000; default:; endcase
    "H": case(I_row[5:2]-1) 0:bits=8'b11000011;1:bits=8'b11000011;2:bits=8'b11000011;3:bits=8'b11111111;4:bits=8'b11000011;5:bits=8'b11000011;6:bits=8'b11000011; default:; endcase
    "I": case(I_row[5:2]-1) 0:bits=8'b11111111;1:bits=8'b00011000;2:bits=8'b00011000;3:bits=8'b00011000;4:bits=8'b00011000;5:bits=8'b00011000;6:bits=8'b11111111; default:; endcase
    "S": case(I_row[5:2]-1) 0:bits=8'b00111111;1:bits=8'b11000000;2:bits=8'b11000000;3:bits=8'b00111110;4:bits=8'b00000011;5:bits=8'b00000011;6:bits=8'b11111110; default:; endcase
    "T": case(I_row[5:2]-1) 0:bits=8'b11111111;1:bits=8'b00011000;2:bits=8'b00011000;3:bits=8'b00011000;4:bits=8'b00011000;5:bits=8'b00011000;6:bits=8'b00011000; default:; endcase
    "L": case(I_row[5:2]-1) 0:bits=8'b11000000;1:bits=8'b11000000;2:bits=8'b11000000;3:bits=8'b11000000;4:bits=8'b11000000;5:bits=8'b11000000;6:bits=8'b11111111; default:; endcase
    "C": case(I_row[5:2]-1) 0:bits=8'b00111110;1:bits=8'b01100011;2:bits=8'b11000000;3:bits=8'b11000000;4:bits=8'b11000000;5:bits=8'b01100011;6:bits=8'b00111110; default:; endcase
    ":": if ((I_row[5:2]==2)||(I_row[5:2]==5)) bits=8'b00011000;
    " ": bits=8'h00;
    default: bits=8'h00;
   endcase
   O_row_bits=32'h0;
   if ((I_row>=6'd4)&&(I_row<6'd32)) for(k=0;k<8;k=k+1) if(bits[7-k]) O_row_bits[31-k*4 -: 4]=4'hf;
 end
endmodule
module osd_char_lib16 (
    input  wire [7:0]  I_char,
    input  wire [3:0]  I_row,
    output reg  [15:0] O_row_bits
);

    localparam [7:0] CHAR_FRAME = 8'hFE;

    function [7:0] F_ascii8_row;
        input [7:0] I_char;
        input [2:0] I_row;
        begin
            F_ascii8_row = 8'h00;
            case (I_char)
                8'h44: case (I_row) // D
                    3'd0: F_ascii8_row=8'b11111000; 3'd1: F_ascii8_row=8'b11001100;
                    3'd2: F_ascii8_row=8'b11000110; 3'd3: F_ascii8_row=8'b11000110;
                    3'd4: F_ascii8_row=8'b11000110; 3'd5: F_ascii8_row=8'b11001100;
                    3'd6: F_ascii8_row=8'b11111000; default: F_ascii8_row=8'h00;
                endcase
                8'h45: case (I_row) // E
                    3'd0: F_ascii8_row=8'b11111110; 3'd1: F_ascii8_row=8'b11000000;
                    3'd2: F_ascii8_row=8'b11000000; 3'd3: F_ascii8_row=8'b11111100;
                    3'd4: F_ascii8_row=8'b11000000; 3'd5: F_ascii8_row=8'b11000000;
                    3'd6: F_ascii8_row=8'b11111110; default: F_ascii8_row=8'h00;
                endcase
                8'h4C: case (I_row) // L
                    3'd0: F_ascii8_row=8'b11000000; 3'd1: F_ascii8_row=8'b11000000;
                    3'd2: F_ascii8_row=8'b11000000; 3'd3: F_ascii8_row=8'b11000000;
                    3'd4: F_ascii8_row=8'b11000000; 3'd5: F_ascii8_row=8'b11000000;
                    3'd6: F_ascii8_row=8'b11111110; default: F_ascii8_row=8'h00;
                endcase
                8'h41: case (I_row) // A
                    3'd0: F_ascii8_row=8'b00111000; 3'd1: F_ascii8_row=8'b01101100;
                    3'd2: F_ascii8_row=8'b11000110; 3'd3: F_ascii8_row=8'b11000110;
                    3'd4: F_ascii8_row=8'b11111110; 3'd5: F_ascii8_row=8'b11000110;
                    3'd6: F_ascii8_row=8'b11000110; default: F_ascii8_row=8'h00;
                endcase
                8'h59: case (I_row) // Y
                    3'd0: F_ascii8_row=8'b11000110; 3'd1: F_ascii8_row=8'b11000110;
                    3'd2: F_ascii8_row=8'b01101100; 3'd3: F_ascii8_row=8'b00111000;
                    3'd4: F_ascii8_row=8'b00111000; 3'd5: F_ascii8_row=8'b00111000;
                    3'd6: F_ascii8_row=8'b00111000; default: F_ascii8_row=8'h00;
                endcase
                8'h58: case (I_row) // X
                    3'd0: F_ascii8_row=8'b11000110; 3'd1: F_ascii8_row=8'b01101100;
                    3'd2: F_ascii8_row=8'b00111000; 3'd3: F_ascii8_row=8'b00111000;
                    3'd4: F_ascii8_row=8'b00111000; 3'd5: F_ascii8_row=8'b01101100;
                    3'd6: F_ascii8_row=8'b11000110; default: F_ascii8_row=8'h00;
                endcase
                8'h57: case (I_row) // W
                    3'd0: F_ascii8_row=8'b11000110; 3'd1: F_ascii8_row=8'b11000110;
                    3'd2: F_ascii8_row=8'b11000110; 3'd3: F_ascii8_row=8'b11010110;
                    3'd4: F_ascii8_row=8'b11010110; 3'd5: F_ascii8_row=8'b11111110;
                    3'd6: F_ascii8_row=8'b01101100; default: F_ascii8_row=8'h00;
                endcase
                8'h48: case (I_row) // H
                    3'd0: F_ascii8_row=8'b11000110; 3'd1: F_ascii8_row=8'b11000110;
                    3'd2: F_ascii8_row=8'b11000110; 3'd3: F_ascii8_row=8'b11111110;
                    3'd4: F_ascii8_row=8'b11000110; 3'd5: F_ascii8_row=8'b11000110;
                    3'd6: F_ascii8_row=8'b11000110; default: F_ascii8_row=8'h00;
                endcase
                8'h3A: case (I_row) // :
                    3'd1: F_ascii8_row=8'b00110000; 3'd2: F_ascii8_row=8'b00110000;
                    3'd5: F_ascii8_row=8'b00110000; 3'd6: F_ascii8_row=8'b00110000;
                    default: F_ascii8_row=8'h00;
                endcase
                8'h30: case (I_row) // 0
                    3'd0: F_ascii8_row=8'b00111000; 3'd1: F_ascii8_row=8'b01101100;
                    3'd2: F_ascii8_row=8'b11000110; 3'd3: F_ascii8_row=8'b11000110;
                    3'd4: F_ascii8_row=8'b11000110; 3'd5: F_ascii8_row=8'b01101100;
                    3'd6: F_ascii8_row=8'b00111000; default: F_ascii8_row=8'h00;
                endcase
                8'h31: case (I_row) // 1
                    3'd0: F_ascii8_row=8'b00011000; 3'd1: F_ascii8_row=8'b00111000;
                    3'd2: F_ascii8_row=8'b00011000; 3'd3: F_ascii8_row=8'b00011000;
                    3'd4: F_ascii8_row=8'b00011000; 3'd5: F_ascii8_row=8'b00011000;
                    3'd6: F_ascii8_row=8'b01111110; default: F_ascii8_row=8'h00;
                endcase
                8'h32: case (I_row) // 2
                    3'd0: F_ascii8_row=8'b01111100; 3'd1: F_ascii8_row=8'b11000110;
                    3'd2: F_ascii8_row=8'b00000110; 3'd3: F_ascii8_row=8'b00001100;
                    3'd4: F_ascii8_row=8'b00110000; 3'd5: F_ascii8_row=8'b01100000;
                    3'd6: F_ascii8_row=8'b11111110; default: F_ascii8_row=8'h00;
                endcase
                8'h33: case (I_row) // 3
                    3'd0: F_ascii8_row=8'b01111100; 3'd1: F_ascii8_row=8'b11000110;
                    3'd2: F_ascii8_row=8'b00000110; 3'd3: F_ascii8_row=8'b00111100;
                    3'd4: F_ascii8_row=8'b00000110; 3'd5: F_ascii8_row=8'b11000110;
                    3'd6: F_ascii8_row=8'b01111100; default: F_ascii8_row=8'h00;
                endcase
                8'h34: case (I_row) // 4
                    3'd0: F_ascii8_row=8'b00001100; 3'd1: F_ascii8_row=8'b00011100;
                    3'd2: F_ascii8_row=8'b00111100; 3'd3: F_ascii8_row=8'b01101100;
                    3'd4: F_ascii8_row=8'b11001100; 3'd5: F_ascii8_row=8'b11111110;
                    3'd6: F_ascii8_row=8'b00001100; default: F_ascii8_row=8'h00;
                endcase
                8'h35: case (I_row) // 5
                    3'd0: F_ascii8_row=8'b11111110; 3'd1: F_ascii8_row=8'b11000000;
                    3'd2: F_ascii8_row=8'b11000000; 3'd3: F_ascii8_row=8'b11111100;
                    3'd4: F_ascii8_row=8'b00000110; 3'd5: F_ascii8_row=8'b11000110;
                    3'd6: F_ascii8_row=8'b01111100; default: F_ascii8_row=8'h00;
                endcase
                8'h36: case (I_row) // 6
                    3'd0: F_ascii8_row=8'b00111100; 3'd1: F_ascii8_row=8'b01100000;
                    3'd2: F_ascii8_row=8'b11000000; 3'd3: F_ascii8_row=8'b11111100;
                    3'd4: F_ascii8_row=8'b11000110; 3'd5: F_ascii8_row=8'b11000110;
                    3'd6: F_ascii8_row=8'b01111100; default: F_ascii8_row=8'h00;
                endcase
                8'h37: case (I_row) // 7
                    3'd0: F_ascii8_row=8'b11111110; 3'd1: F_ascii8_row=8'b00000110;
                    3'd2: F_ascii8_row=8'b00001100; 3'd3: F_ascii8_row=8'b00011000;
                    3'd4: F_ascii8_row=8'b00110000; 3'd5: F_ascii8_row=8'b00110000;
                    3'd6: F_ascii8_row=8'b00110000; default: F_ascii8_row=8'h00;
                endcase
                8'h38: case (I_row) // 8
                    3'd0: F_ascii8_row=8'b01111100; 3'd1: F_ascii8_row=8'b11000110;
                    3'd2: F_ascii8_row=8'b11000110; 3'd3: F_ascii8_row=8'b01111100;
                    3'd4: F_ascii8_row=8'b11000110; 3'd5: F_ascii8_row=8'b11000110;
                    3'd6: F_ascii8_row=8'b01111100; default: F_ascii8_row=8'h00;
                endcase
                8'h39: case (I_row) // 9
                    3'd0: F_ascii8_row=8'b01111100; 3'd1: F_ascii8_row=8'b11000110;
                    3'd2: F_ascii8_row=8'b11000110; 3'd3: F_ascii8_row=8'b01111110;
                    3'd4: F_ascii8_row=8'b00000110; 3'd5: F_ascii8_row=8'b00001100;
                    3'd6: F_ascii8_row=8'b01110000; default: F_ascii8_row=8'h00;
                endcase
                8'h6D: case (I_row) // m
                    3'd2: F_ascii8_row=8'b11101100; 3'd3: F_ascii8_row=8'b11111110;
                    3'd4: F_ascii8_row=8'b11011010; 3'd5: F_ascii8_row=8'b11011010;
                    3'd6: F_ascii8_row=8'b11011010; default: F_ascii8_row=8'h00;
                endcase
                8'h73: case (I_row) // s
                    3'd1: F_ascii8_row=8'b00111100; 3'd2: F_ascii8_row=8'b01100110;
                    3'd3: F_ascii8_row=8'b01100000; 3'd4: F_ascii8_row=8'b00111100;
                    3'd5: F_ascii8_row=8'b00000110; 3'd6: F_ascii8_row=8'b01100110;
                    3'd7: F_ascii8_row=8'b00111100; default: F_ascii8_row=8'h00;
                endcase
                8'h66: case (I_row) // f
                    3'd0: F_ascii8_row=8'b00011100; 3'd1: F_ascii8_row=8'b00110000;
                    3'd2: F_ascii8_row=8'b01111100; 3'd3: F_ascii8_row=8'b00110000;
                    3'd4: F_ascii8_row=8'b00110000; 3'd5: F_ascii8_row=8'b00110000;
                    3'd6: F_ascii8_row=8'b00110000; 3'd7: F_ascii8_row=8'b00110000;
                endcase
                8'h70: case (I_row) // p
                    3'd0: F_ascii8_row=8'b00000000; 3'd1: F_ascii8_row=8'b11111100;
                    3'd2: F_ascii8_row=8'b11000110; 3'd3: F_ascii8_row=8'b11000110;
                    3'd4: F_ascii8_row=8'b11111100; 3'd5: F_ascii8_row=8'b11000000;
                    3'd6: F_ascii8_row=8'b11000000; 3'd7: F_ascii8_row=8'b11000000;
                endcase
                8'h78: case (I_row) // x
                    3'd0: F_ascii8_row=8'b00000000; 3'd1: F_ascii8_row=8'b11000110;
                    3'd2: F_ascii8_row=8'b01101100; 3'd3: F_ascii8_row=8'b00111000;
                    3'd4: F_ascii8_row=8'b00111000; 3'd5: F_ascii8_row=8'b01101100;
                    3'd6: F_ascii8_row=8'b11000110; 3'd7: F_ascii8_row=8'b00000000;
                endcase
                8'h2A: case (I_row) // *
                    3'd0: F_ascii8_row=8'b00000000; 3'd1: F_ascii8_row=8'b01100110;
                    3'd2: F_ascii8_row=8'b00111100; 3'd3: F_ascii8_row=8'b11111111;
                    3'd4: F_ascii8_row=8'b00111100; 3'd5: F_ascii8_row=8'b01100110;
                    default: F_ascii8_row=8'h00;
                endcase
                8'h2E: case (I_row) // .
                    3'd5: F_ascii8_row=8'b00110000; 3'd6: F_ascii8_row=8'b00110000;
                    default: F_ascii8_row=8'h00;
                endcase
                default: F_ascii8_row = 8'h00;
            endcase
        end
    endfunction

    function [15:0] F_frame_cn16_row;
        input [3:0] I_row;
        begin
            case (I_row)
                // 闁炽儲绮岄幎姘跺灳濠垫挾绀勭€?+ 閻犳劗鍎戠槐姘扁偓鐟版湰閺?16x16 闁绘劕缍婂Ο鈧柨娑樼暟it15 閻庣數鎳撶花鏌ュ嫉閳ь剙顔忛敃鈧崹顏堝Υ?                // 濞达綀娉曢弫銈夊礉閻樼數鐓愰柡鍐Ь閳ユ牜鐥崹顔炬憻鐟滈偊婢佺槐婵堢箔閺冨倹鏆伴悗纭呮鐎硅櫕绋?16x16 ASCII 閻庢稒顨嗚啯闁烩晝顭堢紞瀣晬?                // 閻熸洖妫涘ú?16 閻炴稑鐭夌槐婵嬫焼閸喖甯抽柛妤佹磻缂嶅懐鈧稒顨夌换鍐焊韫囧鍋撴担鍝勭箒缂佹姊婚弫楣冨箣閺嶎剦娼堕悹鍥跺灥椤撶粯绋夋潪鎷岀闁活喕闄嶉埀?                4'd 0: F_frame_cn16_row = 16'h1830;
                4'd 1: F_frame_cn16_row = 16'h183F;
                4'd 2: F_frame_cn16_row = 16'h1830;
                4'd 3: F_frame_cn16_row = 16'h7E30;
                4'd 4: F_frame_cn16_row = 16'h5FFE;
                4'd 5: F_frame_cn16_row = 16'h5F86;
                4'd 6: F_frame_cn16_row = 16'h5FB6;
                4'd 7: F_frame_cn16_row = 16'h5FB6;
                4'd 8: F_frame_cn16_row = 16'h5FB6;
                4'd 9: F_frame_cn16_row = 16'h5FB6;
                4'd10: F_frame_cn16_row = 16'h5FB6;
                4'd11: F_frame_cn16_row = 16'h5DBE;
                4'd12: F_frame_cn16_row = 16'h183C;
                4'd13: F_frame_cn16_row = 16'h186E;
                4'd14: F_frame_cn16_row = 16'h18C6;
                4'd15: F_frame_cn16_row = 16'h1982;
                default: F_frame_cn16_row = 16'h0000;
            endcase
        end
    endfunction

    reg [7:0]  base_row;
    integer k;
    always @(*) begin
        base_row = 8'h00;
        if (I_char == CHAR_FRAME) begin
            O_row_bits = F_frame_cn16_row(I_row);
        end
        else begin
            base_row = F_ascii8_row(I_char, I_row[3:1]);
            O_row_bits = 16'h0000;
            for (k = 0; k < 8; k = k + 1) begin
                if (base_row[7-k]) begin
                    O_row_bits[15-(k*2)] = 1'b1;
                    O_row_bits[14-(k*2)] = 1'b1;
                end
            end
        end
    end

endmodule


