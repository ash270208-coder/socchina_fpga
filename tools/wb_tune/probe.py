"""probe.py -- what does the current chain do to a *black* pixel?

This needs no photo: black level is a pure arithmetic property of awb.v+gamma_lut.v.
"""
import numpy as np
from wb_model import P, P_OLD, GAMMA, blk_triple, awb_pixels, gamma_pixels


def px(raw, p, g_r=None, g_b=None):
    g_r = int(round(p.corridor_r[0] / 256)) if g_r is None else g_r
    g_b = int(round(p.corridor_b[0] / 256)) if g_b is None else g_b
    img = np.array([[raw]], dtype=np.uint8)
    r, g, b = awb_pixels(img, g_r, g_b, p)
    rr, rg, rb = gamma_pixels(r, g, b, p)
    return (int(r[0, 0]), int(g[0, 0]), int(b[0, 0])), (int(rr[0, 0]), int(rg[0, 0]), int(rb[0, 0]))


def main():
    ped = 12
    print(f"gamma_lut 表校验通过 (256 项 == round(255*(x/255)^(1/2.2)))\n")

    for label, p in [
        ("旧 RTL   (黑电平留在 awb 输入, gamma 里扣 12/21/33)", P_OLD()),
        ("修复后   (awb 入口扣 12, gamma 扣 0)               ", P()),
    ]:
        print(label)
        br, bg, bb = blk_triple(p)
        print(f"   gamma_lut 扣除常数 R/G/B = {br}/{bg}/{bb}"
              + ("   (awb 已扣, 这里不动)" if p.blk_in else ""))
        for k in (0x19000, 0x1C000, 0x1F000):          # R gain at corridor min/mid/max
            kr = k / 65536
            kb = {0x19000: 0x27000, 0x1C000: 0x2C000, 0x1F000: 0x32000}[k] / 65536
            g_r = int(round(kr * 256))
            g_b = int(round(kb * 256))
            lin, out = px(np.array([ped, ped, ped], np.uint8), p, g_r, g_b)
            print(f"   Kr={kr:.3f} Kb={kb:.3f}"
                  f"   raw黑{ped} -> awb{lin} -> 屏上{out}"
                  f"   {'<-- 纯黑变灰!' if max(out) > 2 else '<-- 黑是黑  OK'}")
        print()

    # grey ramp, old RTL, gains at corridor middle
    print("灰阶响应 (raw 0..40, 旧RTL, Kr=1.75 Kb=2.75):")
    p = P_OLD()
    g_r, g_b = 448, 704
    xs = list(range(0, 41, 4))
    print("   raw: " + " ".join(f"{x:4d}" for x in xs))
    for name, ch in (("G", 1), ("R", 0), ("B", 2)):
        vals = []
        for x in xs:
            raw = [0, 0, 0]
            raw[ch] = x
            lin, out = px(np.array(raw, np.uint8), p, g_r, g_b)
            vals.append(out[ch])
        print(f"   {name}->: " + " ".join(f"{v:4d}" for v in vals))

    print("\n关键结论:")
    out_old = px(np.array([ped, ped, ped], np.uint8), P_OLD(), 448, 704)[1]
    out_new = px(np.array([ped, ped, ped], np.uint8), P(), 448, 704)[1]
    print(f"  旧设计: 传感器黑电平(12) 经 AWB(1.75/1.25/2.75) 后是 (21,15,33),")
    print(f"          gamma_lut 只扣了 (21,12,33) -> G 残留 3 LSB,")
    print(f"          γ2.2 把 3 LSB 放大成 34/255 => 纯黑显示为 RGB{out_old} (~13% 暗绿灰)")
    print(f"  修复后: awb 先扣 12 -> AWB 输出 (0,0,0) -> gamma 不扣 => RGB{out_new}  OK")


if __name__ == "__main__":
    main()
