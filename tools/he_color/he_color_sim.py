# -*- coding: utf-8 -*-
"""
he_color_sim.py -- 为什么"只对 Y 做直方图均衡、Cb/Cr 不动、再转回 RGB"会让颜色发灰?

实验 1: 把"Y 换成 Y' , Cb/Cr 原样"这一单步单独拎出来看(RTL 定点完全照抄),
        测每个物体的 RGB 与饱和度变化.
实验 2: 比较"先 HE 后 gamma" vs "在 gamma 域里 HE", 看亮度/饱和度差多少.

用法: python he_color_sim.py scene | photo
输出: he_compare_<case>.png / he_zoom_<case>.png / he_metrics_<case>.csv
"""
import sys, os, csv
import numpy as np
from PIL import Image, ImageDraw, ImageFont

OUT = os.path.dirname(os.path.abspath(__file__))
W, H = 1280, 720
CLIP_DIV = 64
FONT = r"C:\Windows\Fonts\msyh.ttc"

# ------------------------------------------------------------- RTL 定点算子
def rgb2ycc(rgb):
    r = rgb[..., 0].astype(np.int32); g = rgb[..., 1].astype(np.int32); b = rgb[..., 2].astype(np.int32)
    return [np.clip((77 * r + 150 * g + 29 * b) >> 8, 0, 255),
            np.clip((128 * b - 43 * r - 85 * g + 32768) >> 8, 0, 255),
            np.clip((128 * r - 107 * g - 21 * b + 32768) >> 8, 0, 255)]


def ycc2rgb(y, cb, cr):
    y = y.astype(np.int32); cb = cb.astype(np.int32); cr = cr.astype(np.int32)
    R = (256 * y + 359 * cr - 45952) >> 8
    G = (256 * y + 34688 - 88 * cb - 183 * cr) >> 8
    B = (256 * y + 454 * cb - 58112) >> 8
    return np.stack([np.clip(v, 0, 255) for v in (R, G, B)], -1).astype(np.uint8)


def he_lut(y, clip_div=CLIP_DIV):
    """histogram_equ.v: clip 限幅 + excess/256 平摊 + round(CDF*255/N)"""
    n = y.size
    h = np.bincount(y.ravel(), minlength=256).astype(np.int64)
    lim = n // clip_div
    excess = int(np.maximum(h - lim, 0).sum())
    h = np.minimum(h, lim) + (excess >> 8) + (np.arange(256) < (excess & 0xFF))
    cdf = np.cumsum(h)
    mult = (1 << 32) // n
    return ((cdf * 255 * mult + (1 << 31)) >> 32).clip(0, 255).astype(np.uint8), cdf


GAMMA = np.array([int(round(255 * (x / 255.0) ** (1 / 2.2))) for x in range(256)], np.int32)


def apply_gamma(rgb):
    return np.stack([GAMMA[rgb[..., i].astype(np.int32)] for i in range(3)], -1).astype(np.uint8)


def gain_chroma(y_old, y_new, cb, cr):
    """k = Y'/Y → 等价于 RGB 三通道同乘 k: 色相、饱和度严格不变"""
    k = np.where(y_old > 0, y_new.astype(np.float64) / np.maximum(y_old, 1), 1.0).clip(0, 4.0)
    f = lambda c: np.clip(np.round(128 + (c.astype(np.float64) - 128) * k), 0, 255).astype(np.uint8)
    return f(cb), f(cr)


def sat_fixed(cb, cr, k):
    f = lambda c: np.clip(np.round(128 + (c.astype(np.float64) - 128) * k), 0, 255).astype(np.uint8)
    return f(cb), f(cr)


def sat_of(rgb):
    f = rgb.astype(np.float64)
    mx = f.max(-1); mn = f.min(-1)
    return np.where(mx > 0, (mx - mn) / np.maximum(mx, 1), 0)


# ------------------------------------------------------------- 测试图
def make_scene():
    rng = np.random.default_rng(7)
    yy, xx = np.mgrid[0:H, 0:W]
    im = np.zeros((H, W, 3), np.float64)
    im[:] = (170 + 40 * (1 - yy / H))[..., None]
    im += rng.normal(0, 3.0, im.shape)
    im[500:] = (100 + 20 * (1 - (yy[500:] - 500) / (H - 500)))[..., None].repeat(3, -1)[..., :3]
    im[:220, :250] = (32, 34, 38)                                    # 暗角
    cy, cx, R = 470, 330, 115
    d = np.sqrt((yy - cy) ** 2 + (xx - cx) ** 2); m = d < R
    sh = 0.78 + 0.22 * np.clip(1 - d / R, 0, 1)
    for i, c in enumerate((200, 60, 55)): im[..., i][m] = c * sh[m]   # 红球
    m = (yy >= 360) & (yy < 660) & (xx >= 700) & (xx < 950)
    for i, c in enumerate((45, 80, 150)): im[..., i][m] = c          # 蓝箱子
    m = (yy >= 400) & (yy < 545) & (xx >= 970) & (xx < 1120)
    for i, c in enumerate((60, 140, 75)): im[..., i][m] = c          # 绿箱子
    m = (yy >= 120) & (yy < 270) & (xx >= 560) & (xx < 670)
    for i, c in enumerate((205, 165, 140)): im[..., i][m] = c        # 肤色
    return np.clip(im, 0, 255).round().astype(np.uint8)


def make_photo():
    src = r"D:\TD_project\lab_ex1_mipi_hdmi_SC500_720P+vpp\matlab\cnn_detector\data\images\1789700565486.jpg"
    im = Image.open(src).convert("RGB")
    w0, h0 = im.size; ch = int(w0 * 9 / 16); top = max(0, (h0 - ch) // 2)
    return np.asarray(im.crop((0, top, w0, top + ch)).resize((W, H), Image.LANCZOS))


def stats(rgb):
    f = rgb.astype(np.float64)
    y, cb, cr = rgb2ycc(rgb)
    return dict(sat=float(sat_of(rgb).mean()),
                chroma=float(np.sqrt((cb.astype(float) - 128) ** 2 + (cr.astype(float) - 128) ** 2).mean()),
                clip=float(((f >= 255).any(-1) | (f <= 0).any(-1)).mean()),
                lum=float((0.2126 * f[..., 0] + 0.7152 * f[..., 1] + 0.0722 * f[..., 2]).mean()))


def report(title, res, regions):
    print(f"\n=== {title} ===")
    print(f"{'variant':34s}{'sat':>7s}{'chroma':>8s}{'clip%':>7s}{'luma':>7s}")
    for name, rgb in res:
        s = stats(rgb)
        print(f"{name:34s}{s['sat']:7.3f}{s['chroma']:8.1f}{100*s['clip']:6.1f}%{s['lum']:7.1f}")
    print(f"\n{'per-object mean RGB':34s}")
    for name, rgb in res:
        parts = []
        for k, v in regions.items():
            m = rgb[v].reshape(-1, 3).mean(0).round().astype(int)
            parts.append(f"{k}=({m[0]:3d},{m[1]:3d},{m[2]:3d}) S={sat_of(rgb)[v].mean():.2f}")
        print(f"{name:34s}" + "  ".join(parts))
    return res


def montage(res, case, box):
    def label(im, text, fs=26):
        im = im.copy(); d = ImageDraw.Draw(im)
        try: f = ImageFont.truetype(FONT, fs)
        except Exception: f = ImageFont.load_default()
        d.rectangle([0, 0, im.width, fs + 12], fill=(0, 0, 0))
        d.text((8, 4), text, font=f, fill=(255, 235, 0)); return im
    n = len(res); cols = 2
    rows_ = (n + 1) // 2
    tw, th = W // cols, H // cols
    sheet = Image.new("RGB", (tw * cols, th * rows_), (18, 18, 18))
    for i, (name, rgb) in enumerate(res):
        t = label(Image.fromarray(rgb).resize((tw, th), Image.LANCZOS),
                  f"{i}. {name}   sat={stats(rgb)['sat']:.3f}")
        sheet.paste(t, ((i % cols) * tw, (i // cols) * th))
    sheet.save(os.path.join(OUT, f"he_compare_{case}.png"))
    zw, zh = box[2] - box[0], box[3] - box[1]
    z = Image.new("RGB", (zw * 2, zh * ((n + 1) // 2)), (18, 18, 18))
    for i, (name, rgb) in enumerate(res):
        c = Image.fromarray(rgb).crop(box)
        z.paste(label(c, f"{i}. {name[:18]}", 18), ((i % 2) * zw, (i // 2) * zh))
    z.save(os.path.join(OUT, f"he_zoom_{case}.png"))


# =============================================================== 实验 1
case = sys.argv[1] if len(sys.argv) > 1 else "scene"
D = make_scene() if case == "scene" else make_photo()
regions = {"red": (slice(400, 540), slice(260, 400)),
           "blue": (slice(400, 600), slice(720, 930)),
           "green": (slice(420, 520), slice(990, 1100)),
           "skin": (slice(150, 250), slice(580, 650)),
           "dark": (slice(40, 200), slice(40, 220)),
           "wall": (slice(280, 340), slice(420, 620))} if case == "scene" else \
          {"jacket": (slice(500, 700), slice(700, 1000)),
           "face": (slice(200, 330), slice(700, 850)),
           "snow": (slice(620, 700), slice(60, 400))}

y, cb, cr = rgb2ycc(D)
lut, cdf = he_lut(y)
ye = lut[y]

res1 = [("0 roundtrip only (no HE)", ycc2rgb(y, cb, cr)),
        ("1 current: HE(Y), Cb/Cr kept", ycc2rgb(ye, cb, cr)),
        ("2 HE + chroma x (Y'/Y)", ycc2rgb(ye, *gain_chroma(y, ye, cb, cr))),
        ("3 HE + fixed sat x1.4", ycc2rgb(ye, *sat_fixed(cb, cr, 1.4))),
        ("4 HE blended 0.5 + chroma", None)]
yb = (0.5 * ye.astype(np.float64) + 0.5 * y.astype(np.float64)).round().clip(0, 255).astype(np.uint8)
res1[4] = ("4 HE blended 0.5 + chroma", ycc2rgb(yb, *gain_chroma(y, yb, cb, cr)))
res1 = report(f"EXPERIMENT 1 [{case}]  only Y is changed, Cb/Cr untouched", res1, regions)
montage(res1, case, (200, 110, 560, 420) if case == "scene" else (620, 60, 1020, 400))

# =============================================================== 实验 2
print("\n=== 实验2 生成用的映射曲线摘要 ===")
print("  HE 映射斜率(Y->Y') :  min=%d  max=%d" % (int(np.diff(lut.astype(int)).min()), int(np.diff(lut.astype(int)).max())))
print("  落在 255 的 bin 数  :  %d / 256" % int((lut == 255).sum()))
print("  Y 在 [200,255] 的像素占比 : %.1f%%" % (100 * (y >= 200).mean()))

# 线性域 vs 显示域做 HE
Lin = 255.0 * (D / 255.0) ** 2.2
yl, cbl, crl = rgb2ycc(Lin.round().clip(0, 255).astype(np.uint8))
lutl, _ = he_lut(yl)
yel = lutl[yl]
res2 = [("0 base (gamma only)", D),
        ("1 HE in linear then gamma", apply_gamma(ycc2rgb(yel, cbl, crl))),
        ("2 HE in display domain", ycc2rgb(*[ye, cb, cr])),
        ("3 disp-HE + chroma x(Y'/Y)", ycc2rgb(ye, *gain_chroma(y, ye, cb, cr)))]
res2 = report(f"EXPERIMENT 2 [{case}]  which domain to equalise in?", res2, regions)
montage(res2, case + "_dom", (200, 110, 560, 420) if case == "scene" else (620, 60, 1020, 400))

# csv
with open(os.path.join(OUT, f"he_metrics_{case}.csv"), "w", newline="", encoding="utf-8-sig") as fp:
    w = csv.writer(fp); w.writerow(["exp", "variant", "mean_sat", "mean_chroma", "clipped", "mean_luma"])
    for tag, rr in (("E1", res1), ("E2", res2)):
        for name, rgb in rr:
            s = stats(rgb)
            w.writerow([tag, name, f"{s['sat']:.4f}", f"{s['chroma']:.2f}", f"{s['clip']:.4f}", f"{s['lum']:.2f}"])
print("\nsaved ->", OUT)
