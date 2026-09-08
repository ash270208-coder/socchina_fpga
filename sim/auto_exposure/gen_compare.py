#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""自动曝光对比图生成脚本
读取 src_img.txt (输入偏暗图, 单帧) 与 sim_out.txt (12帧输出)
生成:
  - in_original.png   : 输入原图 (96x64)
  - frame_NN.png      : 每帧输出图像 (可选, 展示逐帧变亮)
  - comparison.png    : 放大后的并排对比图 (原图 + 各帧输出)
"""
from PIL import Image, ImageDraw

W, H = 96, 64
PIX = W * H
SCALE = 8          # 放大倍数, 便于肉眼观察
MAX_FRAMES = 12    # 与仿真帧数对应


def read_pixels(path, n):
    """读取 hex 每行一个 24-bit RGB 像素, 返回 (n, [ (r,g,b)... ])"""
    with open(path) as f:
        lines = [ln.strip() for ln in f if ln.strip()]
    pixels = []
    for ln in lines:
        v = int(ln, 16)
        r = (v >> 16) & 0xFF
        g = (v >> 8) & 0xFF
        b = v & 0xFF
        pixels.append((r, g, b))
    assert len(pixels) >= n, f"{path}: {len(pixels)} < {n}"
    return pixels


def to_image(pixels):
    im = Image.new("RGB", (W, H))
    im.putdata(pixels[:PIX])
    return im


def main():
    src = read_pixels("src_img.txt", PIX)
    out = read_pixels("sim_out.txt", PIX * MAX_FRAMES)

    # 输入原图
    in_im = to_image(src)
    in_im.save("in_original.png")
    print(f"in_original.png 尺寸={in_im.size}")

    # 各帧输出
    frames = []
    for f in range(MAX_FRAMES):
        f_im = to_image(out[f * PIX:(f + 1) * PIX])
        f_im.save(f"frame_{f:02d}.png")
        frames.append(f_im)
        print(f"frame_{f:02d}.png 尺寸={f_im.size}")

    # ===== 对比图: 上方原图 + 下方各帧输出, 并排放大 =====
    labels = ["INPUT (dark)"] + [f"AE Frame {f}" for f in range(MAX_FRAMES)]
    imgs = [in_im] + frames

    big_w = W * SCALE
    big_h = H * SCALE
    label_h = 22

    # 一行放多少张图 (连标签)
    per_row = 6
    n = len(imgs)
    rows = (n + per_row - 1) // per_row
    cols = min(n, per_row)

    canvas_w = cols * big_w + (cols - 1) * 8 + 16
    canvas_h = rows * (big_h + label_h) + (rows - 1) * 10 + 16

    cmp_im = Image.new("RGB", (canvas_w, canvas_h), (40, 40, 40))
    d = ImageDraw.Draw(cmp_im)

    for i, (im, lab) in enumerate(zip(imgs, labels)):
        row = i // per_row
        col = i % per_row
        x0 = 8 + col * (big_w + 8)
        y0 = 8 + row * (big_h + label_h + 10)
        big = im.resize((big_w, big_h), Image.NEAREST)
        cmp_im.paste(big, (x0, y0))
        d.text((x0 + 4, y0 + big_h + 4), lab, fill=(255, 255, 255))

    cmp_im.save("comparison.png")
    print(f"comparison.png 尺寸={cmp_im.size}")


if __name__ == "__main__":
    main()
