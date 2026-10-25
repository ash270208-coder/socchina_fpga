"""demo.py -- before/after picture for "画面发灰"

No board needed.  A reference sRGB photo is turned back into what the SC500
actually hands to awb.v (linear light + sensor colour response + black pedestal
+ the exposure the AE loop settles on), then pushed through the *bit-exact*
RTL model.  The reference we compare against is the same scene after an
IDEAL awb (pedestal removed first, correct gains) + the same gamma.

    ref = sRGB(255*(1.25*lin/255)^(1/2.2))          <- what should be on screen
    cur = awb.v + gamma_lut.v as they are today     <- what is on screen

Run:  python demo.py
Out:  before_after.png, metrics printed
"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFont

from wb_model import (P, P_OLD, GAMMA, awb_gains, awb_pixels, gamma_pixels, run,
                      metrics, show, y_of)

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SRC = os.path.join(ROOT, "matlab", "cnn_detector", "data", "images",
                   "1789700565486.jpg")
OUT = os.path.join(HERE, "out")


def _font(size):
    """PIL 的默认位图字体不支持中文(会画成方块), 必须用 TrueType。"""
    for p in (r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\msyhbd.ttc",
              r"C:\Windows\Fonts\simhei.ttf", r"C:\Windows\Fonts\simsun.ttc",
              r"C:\Windows\Fonts\arial.ttf", r"C:\Windows\Fonts\segoeui.ttf"):
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size)
            except Exception:
                continue
    return ImageFont.load_default()

PEDESTAL = 12          # measured on this board, 8-bit domain (gamma_lut.v BLK_G)
TARGET_Y = 50          # ae_auto.v TARGET_Y (linear, 8-bit domain)
KR_NOM, KB_NOM = 1.75, 2.75   # awb.v nominal operating point (corridor middle)


def load_scene(w=1280, h=720):
    im = Image.open(SRC).convert("RGB")
    # centre-crop to 16:9 then resize
    W, H = im.size
    ar = w / h
    if W / H > ar:
        nw = int(H * ar)
        im = im.crop(((W - nw) // 2, 0, (W + nw) // 2, H))
    else:
        nh = int(W / ar)
        im = im.crop((0, (H - nh) // 2, W, (H + nh) // 2))
    return np.asarray(im.resize((w, h), Image.LANCZOS), dtype=np.float64)


def main():
    os.makedirs(OUT, exist_ok=True)
    srgb = load_scene()

    # --- 1. back to scene-referred linear light -------------------------
    lin = 255.0 * (srgb / 255.0) ** 2.2
    # exposure: AE drives the *mean* to TARGET_Y (linear, 8-bit)
    lin *= TARGET_Y / lin[..., 1].mean()
    lin = np.clip(lin, 0, 255)

    # --- 2. what the sensor+demosaic delivers to awb.v ------------------
    # AWB is supposed to land on KR/KB and a 1.25x G boost, so back out the
    # raw values that make that true, then add the pedectal on top.
    raw = np.empty_like(lin)
    raw[..., 0] = 1.25 * lin[..., 0] / KR_NOM
    raw[..., 1] = 1.25 * lin[..., 1] / 1.25
    raw[..., 2] = 1.25 * lin[..., 2] / KB_NOM
    raw = np.clip(np.round(raw) + PEDESTAL, 0, 255).astype(np.uint8)

    # --- 3. ideal reference --------------------------------------------
    refl = np.clip(1.25 * lin, 0, 255)
    ref = np.stack([GAMMA[refl[..., i].round().astype(np.int32)] for i in range(3)],
                   axis=-1).astype(np.uint8)

    # --- 4. the parameter sets ------------------------------------------
    cases = []

    p_old = P_OLD()                     # what is compiled on the board today
    cases.append(("② 现在板上 (发灰的就这张)", p_old,
                  "黑电平留在 awb 输入, gamma 里扣 12/21/33"))

    p_fix = P()                         # the fix: PEDESTAL=12, BLK_G=0
    cases.append(("③ 修复后", p_fix,
                  "awb 入口扣 12, gamma 不再扣"))

    p_fix2 = P(halo_zone=232, halo_r_up=40, halo_b_dn=48, specular=252)
    cases.append(("④ 修复+高光放开", p_fix2,
                  "halo 196->232, R<=G+40, B>=G-48"))

    p_fix3 = P(halo_zone=232, halo_r_up=40, halo_b_dn=48, specular=252,
               corridor_r=(0x14000, 0x24000), corridor_b=(0x1C000, 0x38000))
    cases.append(("⑤ 再加走廊放宽", p_fix3,
                  "R 1.25~2.25x, B 1.75~3.5x"))

    print(f"\n场景: {os.path.basename(SRC)}  {srgb.shape[1]}x{srgb.shape[0]}"
          f"   pedestal={PEDESTAL}  TARGET_Y={TARGET_Y}")
    print("=" * 110)
    rm = raw.reshape(-1, 3).mean(axis=0)
    print(f"awb.v 输入均值 (含黑电平)  R/G/B = {rm[0]:.1f} / {rm[1]:.1f} / {rm[2]:.1f}")
    print(f"awb.v 输入均值 (扣黑电平)  R/G/B = {rm[0]-PEDESTAL:.1f} / {rm[1]-PEDESTAL:.1f} / "
          f"{rm[2]-PEDESTAL:.1f}   <- 黑电平占 G 信号的 "
          f"{100*PEDESTAL/rm[1]:.0f}%, 占 B 的 {100*PEDESTAL/rm[2]:.0f}%")
    print(f"灰世界想要的增益: Kr=1.25*G/R={1.25*(rm[1]-PEDESTAL)/(rm[0]-PEDESTAL):.3f} "
          f"Kb=1.25*G/B={1.25*(rm[1]-PEDESTAL)/(rm[2]-PEDESTAL):.3f}   (走廊 R 1.5625~1.9375 / B 2.4375~3.125)")
    print("=" * 110)
    mref = metrics(ref, "0_理想参考 (sRGB)")
    show(mref)

    imgs = [("① 理想参考 (正确显示)", ref)]
    rows = [mref]
    for name, p, note in cases:
        print(f"\n-- {name}: {note}")
        gr, gb = awb_gains(raw, p, verbose=True)
        r, g, b = awb_pixels(raw, gr, gb, p)
        out = np.stack(gamma_pixels(r, g, b, p), axis=-1).astype(np.uint8)
        m = metrics(out, name)
        show(m)
        print(f"    vs 参考: 平均色差 ΔRGB = "
              f"{np.abs(out.astype(float)-ref.astype(float)).mean():5.2f} LSB"
              f"   黑点比参考高 {m['yp5']-mref['yp5']:+.1f}")
        imgs.append((name, out))
        rows.append(m)

    # --- 5. comparison sheet: reference / old / fixed -------------------
    FONT = _font(15)
    FONT_S = _font(12)

    def lab(im, text, sub=""):
        bar = 20
        sub_h = 15 if sub else 0
        c = Image.new("RGB", (im.width, im.height + bar + sub_h), (18, 18, 18))
        c.paste(im, (0, bar))
        d = ImageDraw.Draw(c)
        d.rectangle([0, 0, im.width, bar - 1], fill=(0, 0, 0))
        d.text((5, 2), text, fill=(255, 230, 0), font=FONT)
        if sub:
            d.text((5, bar + im.height + 1), sub, fill=(150, 150, 150), font=FONT_S)
        return c

    NCOL = 3                      # only the 3 decisive panels go on the sheet
    cols = []
    for name, im in imgs[:NCOL]:
        pi = Image.fromarray(im)
        half = pi.resize((pi.width // 2, pi.height // 2), Image.LANCZOS)
        cols.append(lab(half, name))
    W = sum(c.width for c in cols)
    Hh = max(c.height for c in cols)
    CAP = 26
    sheet = Image.new("RGB", (W, Hh + CAP), (18, 18, 18))
    x = 0
    for c in cols:
        sheet.paste(c, (x, 0))
        x += c.width
    d = ImageDraw.Draw(sheet)
    d.rectangle([0, Hh, W, Hh + CAP], fill=(0, 0, 0))
    d.text((8, Hh + 4),
           "从左到右: ① 理想参考  →  ② 现在板上(发灰+泛绿)  →  ③ 修复后",
           fill=(255, 230, 0), font=_font(15))
    p1 = os.path.join(OUT, "before_after.png")
    sheet.save(p1)
    print(f"\n[saved] {p1}   (从左到右: 理想参考 | 现在板上 | 修复后)")

    # --- 6. shadow zoom (where the veil lives) -------------------------
    y = y_of(ref)
    yy, xx = np.unravel_index(np.argmin(
        np.abs(y - np.percentile(y, 3))), y.shape)
    y0 = int(np.clip(yy - 90, 0, ref.shape[0] - 180))
    x0 = int(np.clip(xx - 160, 0, ref.shape[1] - 320))
    box = (slice(y0, y0 + 180), slice(x0, x0 + 320))
    zs = []
    for name, im in imgs[:NCOL]:
        crop = Image.fromarray(im[box])
        zs.append(lab(crop.resize((crop.width * 2, crop.height * 2), Image.NEAREST),
                      name))
    W = sum(c.width for c in zs)
    sheet2 = Image.new("RGB", (W, zs[0].height), (18, 18, 18))
    x = 0
    for c in zs:
        sheet2.paste(c, (x, 0))
        x += c.width
    p2 = os.path.join(OUT, "shadow_zoom.png")
    sheet2.save(p2)
    print(f"[saved] {p2}   (暗部放大 2x, 起点 {x0},{y0})")

    # --- 7. grey ramp, SAME gains on both, only the black level moved --
    #     isolates the "black never gets black / shadows go green" effect
    g_r, g_b = 448, 704                      # 1.75x / 2.75x
    ramp4 = np.zeros((256, 4, 3), dtype=np.uint8)
    ramp4[:, 0, :] = np.arange(256, dtype=np.uint8)[:, None]
    outs = {}
    for tag, p in (("old", P_OLD()), ("new", P())):
        r, g, b = awb_pixels(ramp4, g_r, g_b, p)
        outs[tag] = np.stack(gamma_pixels(r, g, b, p), axis=-1)[:256, 0, :]
    ramp_img = Image.new("RGB", (256, 110), (18, 18, 18))
    for k, (tag, o) in enumerate(outs.items()):
        for x in range(256):
            px = tuple(int(v) for v in o[x])
            for yy in range(40):
                ramp_img.putpixel((x, k * 55 + 15 + yy), px)
    p3 = os.path.join(OUT, "grey_ramp.png")
    ramp_img.save(p3)
    print(f"[saved] {p3}  (上=旧RTL 下=修复后, 左黑右白, 同为 1.75x/2.75x)")

    Image.fromarray(raw).save(os.path.join(OUT, "awb_input_simulated.png"))
    print(f"[saved] {os.path.join(OUT, 'awb_input_simulated.png')}")


if __name__ == "__main__":
    main()
