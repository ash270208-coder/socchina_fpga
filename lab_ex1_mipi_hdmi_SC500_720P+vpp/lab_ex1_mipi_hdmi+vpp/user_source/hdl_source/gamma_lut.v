`timescale 1ns / 1ps
//=============================================================================
// gamma_lut.v -- display gamma encoding (gamma = 2.2) + fixed black level
//
// WHY THIS MODULE EXISTS:
//   The sensor/ISP chain hands out LINEAR light values, and they are sent
//   straight to HDMI. But a monitor interprets its input as sRGB (gamma ~2.2).
//   Feeding linear data to a gamma display makes mid-tones and shadows look
//   2..5x darker than they should (a dark face ends up almost black).
//   This module applies the missing  out = round(255*(in/255)^(1/2.2))  step.
//
//   Pure combinational (0 clock latency), so it does NOT disturb the 16-cycle
//   delay alignment of the other display modes in vpp_top.v.
//
// BLACK LEVEL (fixed constant now):
//   The sensor has a dark pedestal. Measured on this board: about 12 in the
//   8-bit domain (= 48 LSB at 10 bit). It must be removed, otherwise gamma
//   turns that pedestal into grey fog and black never gets black.
//   R/B carry the AWB-multiplied pedestal (~1.75x / ~2.75x of G), so their
//   subtraction is scaled accordingly -- subtracting the same number from all
//   three channels would tint the shadows.
//   The button-selectable presets have been REMOVED; this is a fixed constant.
//
// TO CHANGE THE CURVE: edit the gamma_map table below.
// The values are round(255*(x/255)^(1/2.2)) for x = 0..255.
// TO CHANGE THE BLACK LEVEL: edit BLK_G in section 1 below.
//=============================================================================
// 【中文说明】
//   为什么要加这个模块:
//     传感器/ISP 出来的是"线性光"数据, 而 HDMI 显示器是按 sRGB(约 2.2 次方)
//     解读输入的。线性数据直送显示器时, 中间调和暗部会被额外压暗 2~5 倍,
//     人脸这种本来就暗的东西几乎变成全黑 —— 这就是之前画面很暗、只能靠
//     猛加增益硬撑的原因(而增益又会把灯顶成一片白斑)。
//   本模块补上缺失的那一步: out = round(255*(in/255)^(1/2.2))。
//
//   关键点:
//     1) 三个通道共用同一条曲线, 所以色调比例不变, 不会像直方图均衡那样
//        在暗部把颜色丢掉变成黑白;
//     2) 纯组合逻辑, 0 拍延迟, 不会打乱 vpp_top 里各模式对齐的 16 拍延时。
//
//   黑电平 (BLK_G, 已固定为常数):
//     实测本机最佳值 = 12 (8bit 域), 也就是 10bit 域的 48 LSB。
//     必须扣掉, 否则伽马会把这点"底"抬成灰雾, 画面黑不下去。
//     注意: R/B 的黑电平按名义 AWB 增益(约 1.75x / 2.75x)缩放；
//           AWB 实际是逐帧自适应的，因此这里仍是保守的固定黑电平近似值。
//     因为 AWB 把这个底也一起乘过了; 三个通道扣同一个数, 暗部会偏色。
//     原来的按键档位已经删除, 现在是一个常数, 第 4 颗按键已腾空。
//     以后更干净的做法: 把这个扣除挪到源头(raw10_unpacket_2lane, 在 AWB
//     之前扣掉), 那时把这里 BLK_G 改成 0 即可。
//
//   要改曲线形状: 只改下面 gamma_map 那张表即可。
//=============================================================================
module gamma_lut (
    input  wire [7:0] I_r,        // linear R (8 bit, after AWB)
    input  wire [7:0] I_g,        // linear G
    input  wire [7:0] I_b,        // linear B
    output wire [7:0] O_r,        // gamma encoded R
    output wire [7:0] O_g,        // gamma encoded G
    output wire [7:0] O_b         // gamma encoded B
);

    //-------------------------------------------------------------------------
    // 1. black level: FIXED constant (G channel domain) -- measured on board
    //    (was a button-selectable preset, the button is now free again)
    //-------------------------------------------------------------------------
    localparam [7:0] BLK_G = 8'd12;   // = 48 LSB in the 10-bit domain
    wire [7:0] blk_g = BLK_G;
    wire [7:0] blk_r = blk_g + (blk_g >> 1) + (blk_g >> 2);          // ~ x1.75
    wire [7:0] blk_b = blk_g + blk_g + (blk_g >> 1) + (blk_g >> 2); // ~ x2.75

    //-------------------------------------------------------------------------
    // 2. subtract black level (saturating, never negative)
    //-------------------------------------------------------------------------
    wire [7:0] r_lin = (I_r > blk_r) ? (I_r - blk_r) : 8'd0;
    wire [7:0] g_lin = (I_g > blk_g) ? (I_g - blk_g) : 8'd0;
    wire [7:0] b_lin = (I_b > blk_b) ? (I_b - blk_b) : 8'd0;

    //-------------------------------------------------------------------------
    // 3. gamma curve: out = round(255*(in/255)^(1/2.2))
    //    all three channels share ONE curve, so hue ratios are preserved
    //    (this is why it does not lose colour in the dark like the
    //     histogram equaliser does when it only remaps Y)
    //-------------------------------------------------------------------------
    function [7:0] gamma_map;
        input [7:0] x;
        case (x)
            8'd0:gamma_map=8'd0; 8'd1:gamma_map=8'd21; 8'd2:gamma_map=8'd28; 8'd3:gamma_map=8'd34; 8'd4:gamma_map=8'd39; 8'd5:gamma_map=8'd43; 8'd6:gamma_map=8'd46; 8'd7:gamma_map=8'd50;
            8'd8:gamma_map=8'd53; 8'd9:gamma_map=8'd56; 8'd10:gamma_map=8'd59; 8'd11:gamma_map=8'd61; 8'd12:gamma_map=8'd64; 8'd13:gamma_map=8'd66; 8'd14:gamma_map=8'd68; 8'd15:gamma_map=8'd70;
            8'd16:gamma_map=8'd72; 8'd17:gamma_map=8'd74; 8'd18:gamma_map=8'd76; 8'd19:gamma_map=8'd78; 8'd20:gamma_map=8'd80; 8'd21:gamma_map=8'd82; 8'd22:gamma_map=8'd84; 8'd23:gamma_map=8'd85;
            8'd24:gamma_map=8'd87; 8'd25:gamma_map=8'd89; 8'd26:gamma_map=8'd90; 8'd27:gamma_map=8'd92; 8'd28:gamma_map=8'd93; 8'd29:gamma_map=8'd95; 8'd30:gamma_map=8'd96; 8'd31:gamma_map=8'd98;
            8'd32:gamma_map=8'd99; 8'd33:gamma_map=8'd101; 8'd34:gamma_map=8'd102; 8'd35:gamma_map=8'd103; 8'd36:gamma_map=8'd105; 8'd37:gamma_map=8'd106; 8'd38:gamma_map=8'd107; 8'd39:gamma_map=8'd109;
            8'd40:gamma_map=8'd110; 8'd41:gamma_map=8'd111; 8'd42:gamma_map=8'd112; 8'd43:gamma_map=8'd114; 8'd44:gamma_map=8'd115; 8'd45:gamma_map=8'd116; 8'd46:gamma_map=8'd117; 8'd47:gamma_map=8'd118;
            8'd48:gamma_map=8'd119; 8'd49:gamma_map=8'd120; 8'd50:gamma_map=8'd122; 8'd51:gamma_map=8'd123; 8'd52:gamma_map=8'd124; 8'd53:gamma_map=8'd125; 8'd54:gamma_map=8'd126; 8'd55:gamma_map=8'd127;
            8'd56:gamma_map=8'd128; 8'd57:gamma_map=8'd129; 8'd58:gamma_map=8'd130; 8'd59:gamma_map=8'd131; 8'd60:gamma_map=8'd132; 8'd61:gamma_map=8'd133; 8'd62:gamma_map=8'd134; 8'd63:gamma_map=8'd135;
            8'd64:gamma_map=8'd136; 8'd65:gamma_map=8'd137; 8'd66:gamma_map=8'd138; 8'd67:gamma_map=8'd139; 8'd68:gamma_map=8'd140; 8'd69:gamma_map=8'd141; 8'd70:gamma_map=8'd142; 8'd71:gamma_map=8'd143;
            8'd72:gamma_map=8'd144; 8'd73:gamma_map=8'd144; 8'd74:gamma_map=8'd145; 8'd75:gamma_map=8'd146; 8'd76:gamma_map=8'd147; 8'd77:gamma_map=8'd148; 8'd78:gamma_map=8'd149; 8'd79:gamma_map=8'd150;
            8'd80:gamma_map=8'd151; 8'd81:gamma_map=8'd151; 8'd82:gamma_map=8'd152; 8'd83:gamma_map=8'd153; 8'd84:gamma_map=8'd154; 8'd85:gamma_map=8'd155; 8'd86:gamma_map=8'd156; 8'd87:gamma_map=8'd156;
            8'd88:gamma_map=8'd157; 8'd89:gamma_map=8'd158; 8'd90:gamma_map=8'd159; 8'd91:gamma_map=8'd160; 8'd92:gamma_map=8'd160; 8'd93:gamma_map=8'd161; 8'd94:gamma_map=8'd162; 8'd95:gamma_map=8'd163;
            8'd96:gamma_map=8'd164; 8'd97:gamma_map=8'd164; 8'd98:gamma_map=8'd165; 8'd99:gamma_map=8'd166; 8'd100:gamma_map=8'd167; 8'd101:gamma_map=8'd167; 8'd102:gamma_map=8'd168; 8'd103:gamma_map=8'd169;
            8'd104:gamma_map=8'd170; 8'd105:gamma_map=8'd170; 8'd106:gamma_map=8'd171; 8'd107:gamma_map=8'd172; 8'd108:gamma_map=8'd173; 8'd109:gamma_map=8'd173; 8'd110:gamma_map=8'd174; 8'd111:gamma_map=8'd175;
            8'd112:gamma_map=8'd175; 8'd113:gamma_map=8'd176; 8'd114:gamma_map=8'd177; 8'd115:gamma_map=8'd178; 8'd116:gamma_map=8'd178; 8'd117:gamma_map=8'd179; 8'd118:gamma_map=8'd180; 8'd119:gamma_map=8'd180;
            8'd120:gamma_map=8'd181; 8'd121:gamma_map=8'd182; 8'd122:gamma_map=8'd182; 8'd123:gamma_map=8'd183; 8'd124:gamma_map=8'd184; 8'd125:gamma_map=8'd184; 8'd126:gamma_map=8'd185; 8'd127:gamma_map=8'd186;
            8'd128:gamma_map=8'd186; 8'd129:gamma_map=8'd187; 8'd130:gamma_map=8'd188; 8'd131:gamma_map=8'd188; 8'd132:gamma_map=8'd189; 8'd133:gamma_map=8'd190; 8'd134:gamma_map=8'd190; 8'd135:gamma_map=8'd191;
            8'd136:gamma_map=8'd192; 8'd137:gamma_map=8'd192; 8'd138:gamma_map=8'd193; 8'd139:gamma_map=8'd194; 8'd140:gamma_map=8'd194; 8'd141:gamma_map=8'd195; 8'd142:gamma_map=8'd195; 8'd143:gamma_map=8'd196;
            8'd144:gamma_map=8'd197; 8'd145:gamma_map=8'd197; 8'd146:gamma_map=8'd198; 8'd147:gamma_map=8'd199; 8'd148:gamma_map=8'd199; 8'd149:gamma_map=8'd200; 8'd150:gamma_map=8'd200; 8'd151:gamma_map=8'd201;
            8'd152:gamma_map=8'd202; 8'd153:gamma_map=8'd202; 8'd154:gamma_map=8'd203; 8'd155:gamma_map=8'd203; 8'd156:gamma_map=8'd204; 8'd157:gamma_map=8'd205; 8'd158:gamma_map=8'd205; 8'd159:gamma_map=8'd206;
            8'd160:gamma_map=8'd206; 8'd161:gamma_map=8'd207; 8'd162:gamma_map=8'd207; 8'd163:gamma_map=8'd208; 8'd164:gamma_map=8'd209; 8'd165:gamma_map=8'd209; 8'd166:gamma_map=8'd210; 8'd167:gamma_map=8'd210;
            8'd168:gamma_map=8'd211; 8'd169:gamma_map=8'd212; 8'd170:gamma_map=8'd212; 8'd171:gamma_map=8'd213; 8'd172:gamma_map=8'd213; 8'd173:gamma_map=8'd214; 8'd174:gamma_map=8'd214; 8'd175:gamma_map=8'd215;
            8'd176:gamma_map=8'd215; 8'd177:gamma_map=8'd216; 8'd178:gamma_map=8'd217; 8'd179:gamma_map=8'd217; 8'd180:gamma_map=8'd218; 8'd181:gamma_map=8'd218; 8'd182:gamma_map=8'd219; 8'd183:gamma_map=8'd219;
            8'd184:gamma_map=8'd220; 8'd185:gamma_map=8'd220; 8'd186:gamma_map=8'd221; 8'd187:gamma_map=8'd221; 8'd188:gamma_map=8'd222; 8'd189:gamma_map=8'd223; 8'd190:gamma_map=8'd223; 8'd191:gamma_map=8'd224;
            8'd192:gamma_map=8'd224; 8'd193:gamma_map=8'd225; 8'd194:gamma_map=8'd225; 8'd195:gamma_map=8'd226; 8'd196:gamma_map=8'd226; 8'd197:gamma_map=8'd227; 8'd198:gamma_map=8'd227; 8'd199:gamma_map=8'd228;
            8'd200:gamma_map=8'd228; 8'd201:gamma_map=8'd229; 8'd202:gamma_map=8'd229; 8'd203:gamma_map=8'd230; 8'd204:gamma_map=8'd230; 8'd205:gamma_map=8'd231; 8'd206:gamma_map=8'd231; 8'd207:gamma_map=8'd232;
            8'd208:gamma_map=8'd232; 8'd209:gamma_map=8'd233; 8'd210:gamma_map=8'd233; 8'd211:gamma_map=8'd234; 8'd212:gamma_map=8'd234; 8'd213:gamma_map=8'd235; 8'd214:gamma_map=8'd235; 8'd215:gamma_map=8'd236;
            8'd216:gamma_map=8'd236; 8'd217:gamma_map=8'd237; 8'd218:gamma_map=8'd237; 8'd219:gamma_map=8'd238; 8'd220:gamma_map=8'd238; 8'd221:gamma_map=8'd239; 8'd222:gamma_map=8'd239; 8'd223:gamma_map=8'd240;
            8'd224:gamma_map=8'd240; 8'd225:gamma_map=8'd241; 8'd226:gamma_map=8'd241; 8'd227:gamma_map=8'd242; 8'd228:gamma_map=8'd242; 8'd229:gamma_map=8'd243; 8'd230:gamma_map=8'd243; 8'd231:gamma_map=8'd244;
            8'd232:gamma_map=8'd244; 8'd233:gamma_map=8'd245; 8'd234:gamma_map=8'd245; 8'd235:gamma_map=8'd246; 8'd236:gamma_map=8'd246; 8'd237:gamma_map=8'd247; 8'd238:gamma_map=8'd247; 8'd239:gamma_map=8'd248;
            8'd240:gamma_map=8'd248; 8'd241:gamma_map=8'd249; 8'd242:gamma_map=8'd249; 8'd243:gamma_map=8'd249; 8'd244:gamma_map=8'd250; 8'd245:gamma_map=8'd250; 8'd246:gamma_map=8'd251; 8'd247:gamma_map=8'd251;
            8'd248:gamma_map=8'd252; 8'd249:gamma_map=8'd252; 8'd250:gamma_map=8'd253; 8'd251:gamma_map=8'd253; 8'd252:gamma_map=8'd254; 8'd253:gamma_map=8'd254; 8'd254:gamma_map=8'd255; 8'd255:gamma_map=8'd255;
            default: gamma_map = 8'd0;
        endcase
    endfunction

    assign O_r = gamma_map(r_lin);
    assign O_g = gamma_map(g_lin);
    assign O_b = gamma_map(b_lin);

endmodule
