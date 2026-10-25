# -*- coding: utf-8 -*-
"""
patch_demo.py -- 用色块说明"只改 Y 不改 Cb/Cr"为什么会掉饱和度.
每行: 原色块 / 只把 Y 加 40 / 只把 Y 乘 1.6 / 把 Y 乘 1.6 同时把 Cb,Cr 也乘 1.6
"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFont

OUT = os.path.dirname(os.path.abspath(__file__))
FONT = r"C:\Windows\Fonts\msyh.ttc"


def rgb2ycc(rgb):
    r, g, b = [rgb[..., i].astype(np.int32) for i in range(3)]
    return [np.clip((77 * r + 150 * g + 29 * b) >> 8, 0, 255),
            np.clip((128 * b - 43 * r - 85 * g + 32768) >> 8, 0, 255),
            np.clip((128 * r - 107 * g - 21 * b + 32768) >> 8, 0, 255)]


def ycc2rgb(y, cb, cr):
    y = y.astype(np.int32); cb = cb.astype(np.int32); cr = cr.astype(np.int32)
    R = (256 * y + 359 * cr - 45952) >> 8
    G = (256 * y + 34688 - 88 * cb - 183 * cr) >> 8
    B = (256 * y + 454 * cb - 58112) >> 8
    return np.stack([np.clip(v, 0, 255) for v in (R, G, B)], -1).astype(np.uint8)


def sat(rgb):
    f = rgb.astype(np.float64)
    mx = f.max(-1); mn = f.min(-1)
    return np.where(mx > 0, (mx - mn) / np.maximum(mx, 1), 0)


COLORS = [(210, 45, 40, "红"), (230, 140, 40, "橙"), (235, 205, 60, "黄"), (60, 150, 70, "绿"),
          (50, 90, 190, "蓝"), (40, 55, 110, "深蓝"), (205, 165, 140, "肤色"), (150, 150, 150, "灰")]
PW, PH, LM = 140, 130, 300
img = Image.new("RGB", (LM + PW * len(COLORS), PH * 4), (24, 24, 24))
dr = ImageDraw.Draw(img)
f_big = ImageFont.truetype(FONT, 24)
f_sm = ImageFont.truetype(FONT, 20)

rows = [
    ("原图 (Y, Cb, Cr)", "mean S = %.3f", lambda y, cb, cr: (y, cb, cr)),
    ("只把 Y 加 40", "mean S = %.3f", lambda y, cb, cr: (np.clip(y + 40, 0, 255), cb, cr)),
    ("只把 Y 乘 1.6", "mean S = %.3f", lambda y, cb, cr: (np.clip(np.round(y * 1.6), 0, 255), cb, cr)),
    ("Y 乘 1.6, 且 Cb/Cr 也乘 1.6", "mean S = %.3f",
     lambda y, cb, cr: (np.clip(np.round(y * 1.6), 0, 255),
                        np.clip(np.round(128 + (cb.astype(float) - 128) * 1.6), 0, 255).astype(np.uint8),
                        np.clip(np.round(128 + (cr.astype(float) - 128) * 1.6), 0, 255).astype(np.uint8))),
]

for ri, (title, fmt, fn) in enumerate(rows):
    sats = []
    for ci, (r, g, b, name) in enumerate(COLORS):
        patch = np.full((8, 8, 3), (r, g, b), np.uint8)
        y, cb, cr = rgb2ycc(patch)
        y2, cb2, cr2 = fn(y, cb, cr)
        out = ycc2rgb(y2, cb2, cr2)
        sats.append(float(sat(out).mean()))
        img.paste(Image.fromarray(np.tile(out[:1, :1], (PH - 30, PW, 1))),
                  (LM + ci * PW, ri * PH + 30))
        dr.text((LM + ci * PW + 4, ri * PH + 4), name, font=f_sm, fill=(210, 210, 210))
    dr.text((10, ri * PH + 20), title, font=f_big, fill=(255, 235, 0))
    dr.text((10, ri * PH + 58), fmt % np.mean(sats), font=f_big, fill=(150, 255, 150))
    for ci, s in enumerate(sats):
        dr.text((LM + ci * PW + 4, ri * PH + PH - 26), f"S={s:.2f}", font=f_sm,
                fill=(120, 220, 255))
img.save(os.path.join(OUT, "patch_demo.png"))
print("saved", os.path.join(OUT, "patch_demo.png"))
