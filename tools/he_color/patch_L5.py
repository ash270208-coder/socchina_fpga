# -*- coding: utf-8 -*-
"""
patch_L5.py -- 把 vpp_top 里的三个"裸"实例收进两个特征模块，形成与 cartoon_top 一致的结构。

  删: u_RGB888_Y888_lin / u_RGB888_Y888_disp / u_histogram_equ / u_hue_scale
      以及 y_tdata / y_he_tdata / y_equ_tdata / gam_rgb_d / y_he_d 等中间信号
  增: u_hist_eq_color (hist_eq_color_top, 9 拍, RGB 进 RGB 出)
      u_Sobel_edge 改成吃 RGB(线性), 内部自带 RGB2Y, 仍 16 拍

延迟账（逐位不变）:
  直方图档: 9(hist_eq_color_top) + 3(chroma_nr) + 10 = 22
  Sobel档 : 16(Sobel_top 内含 RGB2Y) + 6 = 22
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


# ============================================================ 区域 A: 2A gamma
a = find_div_before(find(lambda s: s.startswith("// 2A. 伽马校正"), 0, "2A"))
b = find(lambda s: s == ");", find(lambda s: s.startswith(") u_RGB888_Y888_disp ("), 0, "disp"), "disp end")

A_TXT = """    // =========================================================================
    // 2. 伽马校正（全工程只做这一次；纯组合逻辑，0 拍延迟）
    //    传感器/ISP 出来的是线性光，显示器按 sRGB(γ≈2.2) 解读输入，
    //    这里补上 out = round(255*(in/255)^(1/2.2))，并扣掉黑电平。
    //
    //    为什么放在最前面（而不是每档各做一次）：
    //      gamma 无记忆、0 拍，做一次之后所有档都从"显示域 RGB"出发，
    //      后面用纯寄存器延迟链取不同拍数即可，不需要第二个 gamma 实例。
    //      【L1】直方图档也因此能在显示域做均衡（详见 docs/HE_COLOR.md）。
    // =========================================================================
    wire [7:0] gamma_r, gamma_g, gamma_b;
    gamma_lut u_gamma_lut (
        .I_r    (I_tdata[23:16]),
        .I_g    (I_tdata[15: 8]),
        .I_b    (I_tdata[ 7: 0]),
        .O_r    (gamma_r),
        .O_g    (gamma_g),
        .O_b    (gamma_b)
    );"""
L[a:b + 1] = A_TXT.split("\n")

# ============================================================ 区域 B: 直方图档
a = find_div_before(find(lambda s: s.startswith("// 3. 直方图均衡化模块"), 0, "sec3"))
b = find(lambda s: s == ");", find(lambda s: s.startswith(") u_histogram_equ ("), 0, "he"), "he end")

B_TXT = """    // =========================================================================
    // 3. 彩色直方图均衡（特征模块，固定 9 拍）
    //    形态与 cartoon_top / Sobel_edge_detection_top 对齐：吃 RGB、吐 RGB、
    //    固定拍数、自包含，可以单独仿真/复用。
    //      内部 = RGB888_Y888(3) + histogram_equ(3) + hue_scale(3)
    //    颜色(色相+饱和度)严格不变，只有亮度按 HE 曲线走。
    //    详见 hist_eq_color_top.v 与 docs/HE_COLOR.md。
    // =========================================================================
    wire [23:0] he_rgb;          // 直方图均衡输出(仍是 24bit RGB)

    hist_eq_color_top #(
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT)
    ) u_hist_eq_color (
        .I_clk    (I_clk),
        .I_rst_n  (I_rst_n),
        .I_tlast  (I_tlast),
        .I_tuser  (I_tuser),
        .I_rgb    ({gamma_r, gamma_g, gamma_b}),
        .I_tvalid (I_tvalid),
        // 控制信号不需要:hue_scale 之后 vpp 统一用 sobel_*_d6 那套(同为 22 拍)
        .O_tlast  (),
        .O_tuser  (),
        .O_tvalid (),
        .O_rgb    (he_rgb)
    );"""
L[a:b + 1] = B_TXT.split("\n")

# ============================================================ 区域 D: Sobel 端口
i = find(lambda s: s.startswith(".I_grey_tdata   (y_tdata),"), 0, "sobel grey")
assert L[i - 2].strip().startswith(".I_tlast")
assert L[i + 1].strip().startswith(".I_tvalid")
L[i - 2:i + 2] = """        .I_tlast        (I_tlast),
        .I_tuser        (I_tuser),
        .I_red_tdata    (I_tdata[23:16]),
        .I_green_tdata  (I_tdata[15: 8]),
        .I_blue_tdata   (I_tdata[ 7: 0]),
        .I_tvalid       (I_tvalid),""".split("\n")

# ============================================================ 区域 C: 第 6 节
a = find_div_before(find(lambda s: s.startswith("// 6. 直方图均衡彩色输出链路"), 0, "sec6"))
b = find(lambda s: s == ");", find(lambda s: s.startswith("chroma_nr u_chroma_nr_he ("), 0, "cn"), "cn end")

C_TXT = """    // =========================================================================
    // 6. 直方图档：色度降噪 + 补拍对齐
    //    hist_eq_color_top(9) + chroma_nr(3) = 12 拍，再补 10 拍 = 22 拍。
    //    Y/HE/保色缩放都已经收进第 3 节那个特征模块里了，这里只剩"降噪 + 对齐"。
    // =========================================================================
    wire [23:0] he_nr_rgb;
    reg [23:0]  he_rgb_d [0:9];

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            for (i = 0; i < 10; i = i + 1)
                he_rgb_d[i] <= 24'd0;
        end
        else begin
            he_rgb_d[0] <= he_nr_rgb;
            for (i = 0; i < 9; i = i + 1)
                he_rgb_d[i+1] <= he_rgb_d[i];
        end
    end

    chroma_nr u_chroma_nr_he (
        .I_clk   (I_clk),
        .I_rst_n (I_rst_n),
        .I_rgb   (he_rgb),
        .O_rgb   (he_nr_rgb)
    );"""
L[a:b + 1] = C_TXT.split("\n")

out = "\n".join(L)

# ---- 小段注释更新
out = out.replace("//    直方图: 显示域 Y 链路见第 6 节 (Y_eq + Cb/Cr -> RGB, 共 22 拍)",
                  "//    直方图: hist_eq_color_top(9) + chroma_nr(3) + 补 10 拍 = 22 拍")
out = out.replace("// 4. Sobel 边缘检测模块 (接 Y 灰度分量)",
                  "// 4. Sobel 边缘检测（特征模块：吃 RGB、内部取 Y，固定 16 拍）")
out = out.replace("// 6c. 卡通化图像风格化 (Cartoon Top)",
                  "// 6c. 卡通化图像风格化（特征模块：吃 RGB、内部取 Y，固定 21 拍）")

# ---- 自检
checks = [
    ("只剩 1 个 hist_eq_color_top", out.count("hist_eq_color_top #(") == 1),
    ("没有裸的 Y 提取", "RGB888_Y888 #(" not in out),
    ("没有裸的 histogram_equ", "histogram_equ #(" not in out),
    ("没有裸的 hue_scale", "hue_scale u_hue_scale" not in out),
    ("Sobel 吃 RGB", ".I_red_tdata    (I_tdata[23:16])," in out),
    ("he_rgb_d 10 级仍在", "he_rgb_d [0:9]" in out),
    ("mux 用 he_rgb_d[9]", "he_rgb_d[9]" in out),
    ("raw_rgb_d 未动", "reg [23:0] raw_rgb_d [0:21];" in out),
    ("4 档控制仍取 sobel_*_d6", out.count("sobel_v_d6") >= 4),
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
