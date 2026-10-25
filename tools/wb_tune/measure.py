"""measure.py -- 拿一张板上回传的帧，量出"发灰"到底有多少，并给出参数建议

用法:
    python measure.py <图>            # png/jpg/bmp, 或者 UDP 回传的 .bin (128x72x3)
    python measure.py ../../tools/py_recv.bin
    python measure.py shot.png --linear-naive

这张图是 **显示域**(过完 γ2.2) 的数据, 所以:
    反推线性值  lin = 255 * (Y/255)^2.2
真黑(传感器盖住/对着全黑物体)本该是 lin = 0。屏幕上量到的暗部
    Y_d  ->  lin_d = 255*(Y_d/255)^2.2
就是"AWB 输出域里没被扣干净的那点黑电平"。设当前总增益 K(含 1.25 提亮),
则还差多少黑电平:

    delta = lin_d / K          (8bit 域, 直接就是 awb.v 里 PEDESTAL 该加的量)

典型值: K = 1.25*Kb ≈ 2.2(R) / 1.25(G) / 2.2~2.8(B)。
"""
import os
import sys
import numpy as np
from PIL import Image

GAMMA_INV = (np.arange(256, dtype=np.float64) / 255.0) ** 2.2 * 255.0


def y_of(i):
    return 0.299 * i[..., 0] + 0.587 * i[..., 1] + 0.114 * i[..., 2]


def load(path):
    if path.lower().endswith(".bin"):
        b = np.fromfile(path, dtype=np.uint8)
        n = b.size // 3
        h = 72
        w = n // h
        return b[:n * 3].reshape(h, w, 3)
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.uint8)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    path = sys.argv[1]
    img = load(path)
    i = img.astype(np.float64)
    y = y_of(i)
    print(f"\n文件: {path}   {img.shape[1]}x{img.shape[0]}")

    print("\n--- 1. 三通道统计 (显示域 0..255) ---")
    for k, n in enumerate("RGB"):
        c = i[..., k]
        print(f"  {n}: mean={c.mean():6.2f}  min={c.min():5.1f}  p1={np.percentile(c,1):5.1f} "
              f"p50={np.percentile(c,50):5.1f}  p99={np.percentile(c,99):5.1f}  max={c.max():5.1f}")
    r, g, b = [i[..., k].mean() for k in range(3)]
    print(f"  通道均值比  R/G = {r/g:.3f}   B/G = {b/g:.3f}   "
          f"(1.00 附近 = 白平衡到位; 明显 <1 = 该通道压暗, 画面偏绿)")

    print("\n--- 2. 黑点 / 对比度 (发灰就靠这三行) ---")
    p1, p50, p99 = np.percentile(y, [1, 50, 99])
    print(f"  Y: min={y.min():5.1f}  p1={p1:5.1f}  p50={p50:5.1f}  p99={p99:5.1f}")
    print(f"  暗部占比 p1/255        = {p1/255:.3f}     (要接近 0, >0.05 就是蒙了雾)")
    print(f"  对比度 span = p99-p1   = {p99-p1:5.1f}   (越大越通透)")
    print(f"  标准差 std(Y)          = {y.std():5.1f}")

    ymin = int(np.clip(round(y.min()), 0, 255))
    lin_d = GAMMA_INV[ymin]
    print(f"\n  最暗像素 Y={ymin}  ->  反推线性 = {lin_d:.1f} (8bit)")
    if lin_d > 0.5:
        for K, ch in ((1.25, "G"), (2.2, "R"), (2.8, "B")):
            print(f"    若这条链的 {ch} 总增益 K={K:.2f} x 1(未含1.25已算): "
                  f"残留黑电平 ≈ {lin_d/K:.1f} LSB")
        print("    -> 这部分残留正是 gamma 抬出来的灰雾; 把 awb.v 的 PEDESTAL 往这个方向调")
    else:
        print("    -> 黑点已经贴到 0, 黑电平扣干净了 ✔")

    mx = i.max(axis=2)
    mn = i.min(axis=2)
    lit = mx >= 48
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1), 0.0)
    print(f"\n--- 3. 饱和度 ---")
    print(f"  sat(有光像素) = {sat[lit].mean():.3f}   饱和度过低(<0.20)通常是"
          f"白平衡没收敛 或 高光被压平")
    print(f"  过曝像素(max>=250) 占比 = {100*(mx>=250).mean():.1f}%   "
          f"(太大说明 B/R 增益偏大, 高光先饱和了)")

    print("\n--- 4. 判据速查 ---")
    print("  暗部发灰发白 + R/G、B/G 都 < 0.95  -> 黑电平没扣干净(调 PEDESTAL), 不是白平衡")
    print("  整屏偏色但黑是黑                    -> 才是白平衡: 看 R/G、B/G 哪个方向错, 动 CORR_R/B 走廊")
    print("  亮的地方一片白、没有颜色            -> 高光平抑过度: HALO_ZONE 调大, HALO_R_UP 调大")
    return 0


if __name__ == "__main__":
    sys.exit(main())
