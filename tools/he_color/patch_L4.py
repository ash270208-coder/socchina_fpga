# -*- coding: utf-8 -*-
"""
patch_L4.py -- 把模式 2 从"YCbCr 域改 Y + 色度补偿 + 反变换"换成
               "RGB 域乘增益 RGB'=RGB*(Y'/Y)"，把 DSP 从 19 个降到 7 个。

背景：这颗芯片 DSP 只有 40 个，原设计已经 40/40 用满。L1+L3 加了 9 个，
      综合报告 #dsp 49/40 (122.5%)，TD 只好把 9 对乘法器硬塞进 9x9 双乘法
      模式（"will be merged into ... by using 9x9 mode"），而被塞的位置
      正好包括喂给 Sobel 的 Y 和卡通内部的两处 —— 模式 3/4 因此崩掉。

改动：
  1) (a)/(b) 两处 RGB888_YCbCr444 -> Y888（只算 Y，9 个乘法器降到 3 个）。
  2) 第 6 节：删掉 YCbCr444_RGB888(4 个乘法器) 与 chroma_comp(3 个)，
     换成 hue_scale(1+3 = 4 个乘法器)：RGB' = RGB*(Y'/Y)。
  3) 延迟重新配平：3(Y) + 3(HE) + 3(hue_scale) + 3(chroma_nr) + 10 = 22 拍。
"""
import sys

P = r"D:\TD_project\lab_ex1_mipi_hdmi_SC500_720P+vpp\lab_ex1_mipi_hdmi_SC500_720P+vpp\lab_ex1_mipi_hdmi+vpp\user_source\hdl_source\vpp_top.v"

raw = open(P, "rb").read()
bom = raw.startswith(b"\xef\xbb\xbf")
if bom:
    raw = raw[3:]
crlf = b"\r\n" in raw
txt = raw.decode("utf-8").replace("\r\n", "\n")
L = txt.split("\n")


def find(pred, start=0, what=""):
    for i in range(start, len(L)):
        if pred(L[i].strip()):
            return i
    raise SystemExit("anchor not found: " + what)


def find_div_before(i):
    j = i - 1
    while j >= 0 and L[j].strip() == "":
        j -= 1
    assert L[j].strip().startswith("// ===="), "no divider above %d" % i
    return j


def replace_block(start_pred, end_pred, new_text, start_from=0, what=""):
    """从满足 start_pred 的行, 到其后第一个满足 end_pred 的行, 整段替换"""
    a = find(start_pred, start_from, what + " start")
    b = find(end_pred, a, what + " end")
    L[a:b + 1] = new_text.split("\n")
    return a


# --------------------------------------------------------------- 1) (a) 线性域
Y_INST = """    Y888 #(
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT)
    ) {NAME} (
        .I_clk          (I_clk),
        .I_rst_n        (I_rst_n),
        .I_tlast        (I_tlast),
        .I_tuser        (I_tuser),
        .I_red_tdata    ({R}),
        .I_green_tdata  ({G}),
        .I_blue_tdata   ({B}),
        .I_tvalid       (I_tvalid),
        .I_tready       (I_tready),
        .O_tlast        ({TL}),
        .O_tuser        ({TU}),
        .O_y_tdata      ({YD}),
        .O_tvalid       ({TV}),
        .O_tready       ()
    );"""

i_a = replace_block(lambda s: s == "RGB888_YCbCr444 #(",
                    lambda s: s == ");",
                    Y_INST.format(NAME="u_Y888_lin",
                                  R="I_tdata[23:16]", G="I_tdata[15:8]", B="I_tdata[7:0]",
                                  TL="tlast_ycbcr", TU="tuser_ycbcr",
                                  YD="y_tdata", TV="tvalid_ycbcr"),
                    0, "conv(a)")

# (b) 显示域：从 (a) 之后继续找
i_b = replace_block(lambda s: s == "RGB888_YCbCr444 #(",
                    lambda s: s == ");",
                    Y_INST.format(NAME="u_Y888_disp",
                                  R="gamma_r", G="gamma_g", B="gamma_b",
                                  TL="tlast_he_ycc", TU="tuser_he_ycc",
                                  YD="y_he_tdata", TV="tvalid_he_ycc"),
                    i_a + 1, "conv(b)")

# 顺手把 (b) 上面那句注释改掉
for k in range(i_b - 1, max(0, i_b - 30), -1):
    if L[k].strip().startswith("// ---- (b)"):
        L[k] = "    // ---- (b) 显示域：只喂直方图均衡（只要 Y，3 个乘法器）----"
        break

# --------------------------------------------------------------- 2) 第 6 节
i6 = find(lambda s: s.startswith("// 6. 直方图均衡彩色输出链路"), 0, "sec6")
a6 = find_div_before(i6)
cn = find(lambda s: s == "chroma_nr u_chroma_nr_he (", i6, "chroma_nr_he")
cne = find(lambda s: s == ");", cn, "chroma_nr_he end")

D = L[a6]
NEW6 = """{D}
    // 6. 直方图均衡彩色输出链路（保色版）
    //    [L1] Y 取自显示域（gamma 之后），HE 在显示域做。
    //    [L4] 不再"改 Y 再用 Cb/Cr 反变换"，改成 RGB × k  (k = Y'/Y)：
    //           R'=kR、G'=kG、B'=kB —— 色相与饱和度严格不变，
    //           只有亮度按 HE 的曲线走（hue-preserving HE）。
    //         省掉反变换的 4 个乘法器 + 色度补偿的 3 个乘法器。
    //         这颗芯片 DSP 只有 40 个、原设计已用满 40/40，省下来才不会再逼
    //         TD 把乘法器硬塞进 9x9 双乘法模式（那会把 Sobel/卡通的 Y 弄坏）。
    //
    //    延迟: Y(3) + HE(3) + hue_scale(3) + chroma_nr(3) + 补 10 拍 = 22 拍
    //    （gamma 是组合 0 拍；gam_rgb_d 把 gamma 后的 RGB 对齐到第 6 拍）
{D}
    wire [23:0] he_rgb;          // hue_scale 之后（RGB' = RGB*k）
    wire [23:0] he_nr_rgb;       // chroma_nr 之后
    wire        he_v_scale;

    reg [7:0]   y_he_d [0:2];        // HE 之前的 Y（显示域）
    reg         he_tvalid_d [0:2];
    reg [23:0]  gam_rgb_d [0:5];     // gamma 后的 RGB，补 6 拍
    // he_rgb_d 补 10 拍: 9(Y+HE+hue_scale) + 3(chroma_nr) + 10 = 22 拍
    reg [23:0]  he_rgb_d [0:9];

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            for (i = 0; i < 3; i = i + 1) begin
                y_he_d[i]      <= 8'd0;
                he_tvalid_d[i] <= 1'b0;
            end
            for (i = 0; i < 6; i = i + 1)
                gam_rgb_d[i] <= 24'd0;
            for (i = 0; i < 10; i = i + 1)
                he_rgb_d[i] <= 24'd0;
        end
        else begin
            // Y(HE前)/tvalid 补 3 拍，与 y_equ（转换 3 + HE 3 = 6 拍）对齐
            y_he_d[0]      <= y_he_tdata;
            he_tvalid_d[0] <= tvalid_he_ycc;
            for (i = 0; i < 2; i = i + 1) begin
                y_he_d[i+1]      <= y_he_d[i];
                he_tvalid_d[i+1] <= he_tvalid_d[i];
            end

            // gamma 后的 RGB 补 6 拍，与 y_he_d[2]/y_equ 同拍
            gam_rgb_d[0] <= {{gamma_r, gamma_g, gamma_b}};
            for (i = 0; i < 5; i = i + 1)
                gam_rgb_d[i+1] <= gam_rgb_d[i];

            // hue_scale(3 拍) -> chroma_nr(3 拍)，再补 10 拍 -> 22 拍
            he_rgb_d[0] <= he_nr_rgb;
            for (i = 0; i < 9; i = i + 1)
                he_rgb_d[i+1] <= he_rgb_d[i];
        end
    end

{D}
    // 6a. 保色亮度重映射：RGB' = RGB * (Y'/Y)，3 拍，4 个乘法器
{D}
    hue_scale u_hue_scale (
        .I_clk    (I_clk),
        .I_rst_n  (I_rst_n),
        .I_y_old  (y_he_d[2]),
        .I_y_new  (y_equ_tdata),
        .I_rgb    (gam_rgb_d[5]),
        .I_tvalid (he_tvalid_d[2]),
        .O_rgb    (he_rgb),
        .O_tvalid (he_v_scale)
    );

{D}
    // 6b. 色度降噪（只动色度不动亮度，内部 3 拍）
{D}
    chroma_nr u_chroma_nr_he (
        .I_clk   (I_clk),
        .I_rst_n (I_rst_n),
        .I_rgb   (he_rgb),
        .O_rgb   (he_nr_rgb)
    );""".format(D=D).split("\n")
L[a6:cne + 1] = NEW6

# --------------------------------------------------------------- 3) mux
im = find(lambda s: s.startswith("mux_tdata  = he_rgb_d[6];"), 0, "mux mode2")
L[im] = L[im].replace("he_rgb_d[6]", "he_rgb_d[9]")
for k in range(im - 1, im - 3, -1):
    if L[k].strip().startswith("3'b010:"):
        L[k] = "            3'b010: begin // 模式 2: 直方图均衡 (显示域 HE + RGB 保色缩放, 22 拍对齐)"

out = "\n".join(L)

# --------------------------------------------------------------- 自检
checks = [
    ("两个 Y888 实例", out.count("Y888 #(") == 2),
    ("没有 _he 的 YCbCr 转换器", "u_RGB888_YCbCr444_he" not in out),
    ("没有 YCbCr->RGB 反变换", "u_YCbCr444_RGB888" not in out),
    ("没有 chroma_comp", "chroma_comp" not in out),
    ("hue_scale 实例存在", "hue_scale u_hue_scale (" in out),
    ("gam_rgb_d 存在", "gam_rgb_d [0:5]" in out),
    ("he_rgb_d 10 级", "he_rgb_d [0:9]" in out),
    ("mux 用 he_rgb_d[9]", "he_rgb_d[9]" in out),
    ("histogram 仍吃显示域 Y", ".I_grey_tdata       (y_he_tdata)," in out),
    ("Sobel 仍吃线性 Y", ".I_grey_tdata   (y_tdata)," in out),
    ("raw_rgb_d 未动", "reg [23:0] raw_rgb_d [0:21];" in out),
]
bad = [n for n, ok in checks if not ok]
for n, ok in checks:
    print(("  OK   " if ok else "  FAIL ") + n)
if bad:
    raise SystemExit("self-check failed: " + ", ".join(bad))

head = "\ufeff" if bom else ""
data = head + (out.replace("\n", "\r\n") if crlf else out)
open(P, "wb").write(data.encode("utf-8"))
print("\npatched: %s\nlines: %d -> %d" % (P, len(txt.split("\n")), len(out.split("\n"))))
