# -*- coding: utf-8 -*-
"""
patch_L1.py -- 对 vpp_top.v 实施 L1: 把直方图均衡从"线性域"搬到"显示域(gamma 之后)".

做法: 按行锚点定位(不受行尾空白/缩进影响), 文档里所有中文注释保留, 只在必要处替换.

变更清单:
  1) 新增 2A 节: gamma_lut 从第 5 节搬到最前面(必须先声明再引用).
  2) 第 2 节拆成两个 RGB->YCbCr:
       (a) 线性域 -> 只给 Sobel (模式 3 行为完全不变)
       (b) 显示域 -> 给直方图均衡
  3) histogram_equ 的输入换成 (b) 的输出.
  4) 第 5 节删掉 gamma_lut 实例(已搬走), 只留 raw_rgb_d 延迟链.
  5) 第 6 节: Cb/Cr/控制信号改用 (b) 的; 删除 6b 节的 he 专用 gamma_lut;
     chroma_nr 直接吃转换后的 RGB.
  延迟: gamma 是组合 0 拍, 所有寄存器级不变 -> 模式 2 仍严格落在第 22 拍.

[状态] 已应用到 vpp_top.v（2026-10-22），随后又手工加了 L3（chroma_comp 色度补偿，
       见 docs/HE_COLOR.md 与 hdl_source/chroma_comp.v）。**当前 vpp_top.v = L1 + L3**；
       本脚本只负责 L1，重跑会得到 L1-only 版本（能编译能跑，但没有色度补偿，颜色会偏）。
       脚本是一次性的：目标文件里 "// 2. RGB 转 YCbCr" 这些锚点已被替换掉，
       重复运行会在第一个锚点就报错退出，不会破坏文件（重跑前先 git checkout 原文件）。
"""
import os

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
    assert L[j].strip().startswith("// ===="), "no divider above line %d" % i
    return j


i2 = find(lambda s: s == "// 2. RGB 转 YCbCr (提取 Y 灰度)", 0, "sec2 title")
D = L[find_div_before(i2)]          # 直接沿用文件里分隔线的样式
assert D.startswith("    // ====")

# ---------------------------------------------------------------- 1 + 2) 2A / 2B
a = find_div_before(i2)
b = i2 + 1
assert L[b].strip().startswith("// ====")

new2 = """{D}
    // 2A. 伽马校正（全工程只做这一次；纯组合逻辑，0 拍延迟）
    //     【L1 变更】从第 5 节搬到这里 —— 提前到 RGB->YCbCr 之前。
    //
    //   为什么必须提前 —— 直方图档"颜色发灰/发白"的根因：
    //     改之前直方图那条链是： 线性 Y -> HE -> 转回 RGB -> 再套 γ2.2
    //     线性光的直方图全挤在低端，HE 把它摊平后大部分像素被抬到中高线性值；
    //     然后才套 γ2.2（凹函数，中高段斜率只剩 ~0.6），三通道之间的差值又被
    //     压掉约 4 成，而亮度继续往上抬 —— 表现就是"红还是红、但整体发白、发灰"。
    //     实测（720P 真实图像走完整条定点链路）：
    //         平均饱和度 0.177 -> 0.100；深蓝外套 (41,46,65) -> (78,83,91)，
    //         该区域饱和度 0.37 -> 0.14。
    //     把同一个 HE 改成在显示域做：平均饱和度 0.100 -> 0.210，外套还是深蓝。
    //
    //   改之后：gamma 先做，直方图档的 Y/Cb/Cr 全部落在显示域（和人眼一致），
    //           HE 直接对显示域 Y 均衡，再转回 RGB 就结束，后面不再套第二次 gamma。
    //           -> 6b 节原来那个 gamma_lut 实例（u_gamma_lut_he）已删除。
    //
    //   注意：gamma_lut 必须先声明再被引用（Verilog 里"先用后声明"会生成隐式
    //         1 位线网，综合出来是 1 bit 的坑），所以它从第 5 节搬到了这里。
    //   时序：纯组合 0 拍，不占任何延迟级，22 拍对齐完全不变。
{D}
    wire [7:0] gamma_r, gamma_g, gamma_b;
    gamma_lut u_gamma_lut (
        .I_r (I_tdata[23:16]),
        .I_g (I_tdata[15: 8]),
        .I_b (I_tdata[ 7: 0]),
        .O_r (gamma_r),
        .O_g (gamma_g),
        .O_b (gamma_b)
    );

{D}
    // 2B. RGB 转 YCbCr（两个实例，各管一段）
    //   (a) 线性域：吃原始 I_tdata   -> 只给 Sobel 用（模式 3 的观感/阈值完全不变）
    //   (b) 显示域：吃 2A 的 gamma    -> 给直方图均衡用（模式 2）
    //
    //   为什么是两个：Y 只有一份，而 Sobel 和 直方图 都要吃 Y。若把 (a) 的输入
    //   直接改成 gamma，Sobel 也会跟着跳到显示域，边沿梯度整体放大 2~3 倍，
    //   阈值 60 会一下过曝成大白边 —— 那是模式 3 的行为倒退，所以给直方图单独
    //   加一套。代价：9 个 8x8 乘法器，两条链并行(不串接)，不加延迟、不动关键路径。
    //   ⚠ 以后若不在乎模式 3，可以把 (a) 删掉、让 Sobel 直接吃 (b) 的 Y 省一套
    //     乘法器，但要重调 SOBEL_THRESHOLD（经验值 60 -> 110 左右）。
{D}
    // ---- (a) 线性域：只喂 Sobel ----""".format(D=D).split("\n")
L[a:b + 1] = new2

# ---------------------------------------------------------------- 3) 第二个转换器
ia = find(lambda s: s == ") u_RGB888_YCbCr444 (", 0, "instance (a)")
iend = find(lambda s: s == ");", ia, "instance (a) end")
new_b = """
    // ---- (b) 显示域：喂直方图均衡（等价于"在显示器域做 HE"）----
    wire        tlast_he_ycc;
    wire        tuser_he_ycc;
    wire        tvalid_he_ycc;
    wire [7:0]  y_he_tdata;
    wire [7:0]  cb_he_tdata;
    wire [7:0]  cr_he_tdata;

    RGB888_YCbCr444 #(
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT)
    ) u_RGB888_YCbCr444_he (
        .I_clk          (I_clk),
        .I_rst_n        (I_rst_n),
        .I_tlast        (I_tlast),
        .I_tuser        (I_tuser),
        .I_red_tdata    (gamma_r),
        .I_green_tdata  (gamma_g),
        .I_blue_tdata   (gamma_b),
        .I_tvalid       (I_tvalid),
        .I_tready       (I_tready),
        .O_tlast        (tlast_he_ycc),
        .O_tuser        (tuser_he_ycc),
        .O_y_tdata      (y_he_tdata),
        .O_cb_tdata     (cb_he_tdata),
        .O_cr_tdata     (cr_he_tdata),
        .O_tvalid       (tvalid_he_ycc),
        .O_tready       ()
    );""".split("\n")
L[iend + 1:iend + 1] = new_b

# ---------------------------------------------------------------- 3) histogram_equ 输入
ih = find(lambda s: s == ") u_histogram_equ (", 0, "histogram_equ inst")
ihe = find(lambda s: s == ");", ih, "histogram_equ end")
for k in range(ih, ihe):
    L[k] = (L[k].replace("tlast_ycbcr", "tlast_he_ycc")
                 .replace("tuser_ycbcr", "tuser_he_ycc")
                 .replace("tvalid_ycbcr", "tvalid_he_ycc")
                 .replace("(y_tdata)", "(y_he_tdata)"))

# ---------------------------------------------------------------- 4) 第 5 节删 gamma
i5 = find(lambda s: s.startswith("// 5. 伽马校正"), 0, "sec5 title")
a5 = find_div_before(i5)
i5e = find(lambda s: s == "reg [23:0] raw_rgb_d [0:21];", i5, "raw_rgb_d")
new5 = """{D}
    // 5. 各模式数据统一对齐到 22 拍延迟（伽马已在 2A 节统一做过一次）
    //    (卡通用了 8 拍双边滤波, 整条对齐由 16 拍放宽到 22 拍):
    //    原图:   伽马后延迟 22 拍                     -> raw_rgb_d[21]
    //    卡通:   伽马后延迟  1 拍                     -> raw_rgb_d[0]
    //            (卡通内部固定 21 拍, 1+21 = 22, 与其它档严格同拍)
    //    灰度:   由伽马后的 RGB 现算 (R+2G+B)/4        -> gray_gam (第 22 拍)
    //    直方图: 显示域 Y 链路见第 6 节 (Y_eq + Cb/Cr -> RGB, 共 22 拍)
    //    Sobel:  sobel_tdata 与 tvalid_sobel 补 6 拍 -> 第 22 拍
    //
    //    【只有一个伽马实例】它在 2A 节, 纯组合(0 拍), 从最前面做一次; 后面用两条
    //    纯寄存器延迟链分别取第 1 拍(卡通)与第 22 拍(原图)即可, 不需要第二个实例。
    //    (L1 之后连直方图档也用它, 所以 6b 节那个 he 专用 gamma 已删除)
    //    注意: raw_rgb_d 里装的已经是"伽马校正后"的数据, 名字沿用原来的,
    //          不要再把它当线性原图使用。
{D}
    reg [23:0] raw_rgb_d [0:21];""".format(D=D).split("\n")
L[a5:i5e + 1] = new5

# ---------------------------------------------------------------- 5) 第 6 节标题
i6 = find(lambda s: s.startswith("// 6. 直方图均衡彩色输出链路"), 0, "sec6 title")
a6 = find_div_before(i6)
j = i6 + 1
while not L[j].strip().startswith("// ===="):
    j += 1
new6 = """{D}
    // 6. 直方图均衡彩色输出链路 (均衡 Y + 显示域色度, 恢复彩色):
    //    [L1] 输入已换成 2B(b) 的显示域 Y/Cb/Cr, 所以这条链上不再需要 gamma。
    //    y_equ(含转换共 6 拍) 与 Cb/Cr(转换 3 + 补 3 = 6 拍) 对齐
    //      -> YCbCr444_RGB888(3 拍, =9 拍) -> chroma_nr(3 拍, =12 拍)
    //      -> 再补 10 拍 = 22 拍, 与 Sobel(补 6 拍后) 严格同拍
    //    (直方图内部已加对比度限制/裁剪, 见 histogram_equ.v 的 CLIP_DIV 参数)
{D}""".format(D=D).split("\n")
L[a6:j + 1] = new6

# ---------------------------------------------------------------- 5) he_gamma 声明
ig = find(lambda s: s.startswith("// 模式 2 专用: gamma(0 拍) + 色度降噪(3 拍)"), 0, "he_gamma decl")
assert L[ig + 1].strip().startswith("wire [7:0]  he_gamma_r")
assert L[ig + 2].strip().startswith("wire [23:0] he_gamma_rgb")
L[ig:ig + 3] = """    // 模式 2 专用: 色度降噪(3 拍)，例化见 6b 节
    //   (L1 之后这里不再需要 gamma: 本档的 Y/Cb/Cr 本来就是显示域)
    wire [23:0] he_rgb    = {he_r_tdata, he_g_tdata, he_b_tdata};""".split("\n")

# ---------------------------------------------------------------- 5) 赋值换信号
ic = find(lambda s: s.startswith("cb_d[0]        <= cb_tdata;"), 0, "cb_d assign")
assert L[ic + 1].strip().startswith("cr_d[0]")
assert L[ic + 2].strip().startswith("he_tvalid_d[0]")
assert L[ic + 4].strip().startswith("he_tuser_d[0]")
L[ic] = L[ic].replace("cb_tdata", "cb_he_tdata")
L[ic + 1] = L[ic + 1].replace("cr_tdata", "cr_he_tdata")
for k in range(ic + 2, ic + 5):
    L[k] = (L[k].replace("tvalid_ycbcr", "tvalid_he_ycc")
                 .replace("tlast_ycbcr", "tlast_he_ycc")
                 .replace("tuser_ycbcr", "tuser_he_ycc"))

# ---------------------------------------------------------------- 5) he_rgb_d 注释
ic2 = find(lambda s: s.startswith("// 转换后的 RGB (9 拍) -> 模式2 专用 gamma(0 拍)"), 0, "he_rgb_d note")
assert L[ic2 + 1].strip().startswith("// = 12 拍")
L[ic2:ic2 + 2] = """            // 转换后的 RGB (9 拍) -> chroma_nr(3 拍) = 12 拍,
            // 再补 10 拍 -> 22 拍, 与 Sobel 路径对齐""".split("\n")

# ---------------------------------------------------------------- 6) 6b 节
i6b = find(lambda s: s.startswith("// 6b. 模式 2 的色调域统一"), 0, "sec6b")
a6b = find_div_before(i6b)
cn = find(lambda s: s == "chroma_nr u_chroma_nr_he (", i6b, "chroma_nr_he")
cne = find(lambda s: s == ");", cn, "chroma_nr_he end")
new6b = """{D}
    // 6b. 模式 2 的色度降噪 (A+E+G 里的 G)
    //       ① 色调域：L1 之后 gamma 已在 2A 节统一做过（直方图链本身就是显示域），
    //          这一档不再重复套 gamma —— 这正是"颜色发灰"的根因修复；
    //       ② 色度降噪：chroma_nr 内部 3 拍，只动色度不动亮度。
    //     整条链路仍然落在第 22 拍（见上面 he_rgb_d 的说明）。
    //     信号 he_rgb 在第 6 节开头声明。
{D}
    chroma_nr u_chroma_nr_he (
        .I_clk   (I_clk),
        .I_rst_n (I_rst_n),
        .I_rgb   (he_rgb),
        .O_rgb   (he_nr_rgb)
    );""".format(D=D).split("\n")
L[a6b:cne + 1] = new6b

# ---------------------------------------------------------------- 7) mux 注释
im = find(lambda s: s.startswith("3'b010: begin // 模式 2:"), 0, "mux mode2")
L[im] = L[im].replace("(已过 gamma + 色度降噪, 22 拍对齐)",
                      "(显示域 HE + 色度降噪, 22 拍对齐)")

out = "\n".join(L)

# ---------------------------------------------------------------- 自检
checks = [
    ("gamma_lut 实例只剩 1 个", out.count("gamma_lut u_gamma_lut") == 1),
    ("u_gamma_lut_he 实例已删除", "gamma_lut u_gamma_lut_he (" not in out),
    ("he_gamma 已删除", "he_gamma" not in out),
    ("第二个转换器已插入", "u_RGB888_YCbCr444_he (" in out),
    ("he_rgb 声明存在", "wire [23:0] he_rgb    = {he_r_tdata" in out),
    ("histogram 吃显示域 Y", ".I_grey_tdata       (y_he_tdata)," in out),
    ("Sobel 仍吃线性 Y", ".I_grey_tdata   (y_tdata)," in out),
    ("cb_d 用 cb_he_tdata", "cb_d[0]        <= cb_he_tdata;" in out),
    ("cr_d 用 cr_he_tdata", "cr_d[0]        <= cr_he_tdata;" in out),
    ("he_tvalid_d 用 tvalid_he_ycc", "he_tvalid_d[0] <= tvalid_he_ycc;" in out),
    ("chroma_nr_he 吃 he_rgb", ".I_rgb   (he_rgb)," in out),
    ("raw_rgb_d 22 级未动", "reg [23:0] raw_rgb_d [0:21];" in out),
    ("22 拍注释仍在", "再补 10 拍 = 22 拍" in out and "再补 10 拍 -> 22 拍" in out),
    ("mux 注释已更新", "(显示域 HE + 色度降噪, 22 拍对齐)" in out),
    ("模式 3/4 未被牵连", "u_Sobel_edge (" in out and "u_cartoon_top (" in out),
]
bad = [n for n, ok in checks if not ok]
for n, ok in checks:
    print(("  OK   " if ok else "  FAIL ") + n)
if bad:
    raise SystemExit("self-check failed: " + ", ".join(bad))

head = "\ufeff" if bom else ""
data = head + (out.replace("\n", "\r\n") if crlf else out)
open(P, "wb").write(data.encode("utf-8"))
print("\npatched: %s" % P)
print("lines: %d -> %d" % (len(txt.split("\n")), len(out.split("\n"))))
