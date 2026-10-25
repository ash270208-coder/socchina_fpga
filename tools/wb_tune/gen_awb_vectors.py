"""gen_awb_vectors.py -- stimulus + expected output for tb_wb_gray.v

The DUT is the *real* user_source/hdl_source/awb.v + gamma_lut.v, so this script
runs the bit-exact Python twin over the identical pixel stream and writes:

    vectors/stim.hex     32 x 24bit words (one 96-bit awb.v word each)
    vectors/expected.hex 32 x 24bit gamma_lut outputs

awb.v only accumulates pixel 0 of every 96-bit word (tdata[16:8]), so the frame
mean is driven by those 32 samples.  The 8-pixel pattern is repeated 4x so the
`frame_* > 1000` guard in awb.v does not trip and the gains land strictly inside
the safety corridor -- that is the case we actually care about.
"""
import os
import numpy as np

from wb_model import P, awb_gains, awb_pixels, gamma_pixels, blk_triple

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "vectors")
os.makedirs(OUT, exist_ok=True)

PAT = np.array([
    [12,  12,  12],    # 0 sensor black          -> must leave as 0,0,0
    [46,  60,  32],    # 1 mid grey
    [30,  40,  20],    # 2 shadow
    [100, 170, 80],    # 3 bright (g_d lands in the halo zone)
    [70,  90,  50],    # 4 mid grey 2
    [80,  40,  24],    # 5 warm colour
    [20,  44,  26],    # 6 cool colour
    [60,  80,  40],    # 7 mid grey 3
], dtype=np.uint8)

NREP = 4
PIX = np.tile(PAT, (NREP, 1))          # 32 words = 32 sampled pixels


def main():
    # awb.v sees 4 pixels per 96-bit word; words 1..3 of each group are 0 in the
    # TB, and the statistics only ever look at pixel 0, so build (32,4,3) with
    # the real pixel in slot 0.
    words = np.zeros((len(PIX), 4, 3), dtype=np.uint8)
    words[:, 0, :] = PIX

    p = P()                             # == the fixed RTL (PEDESTAL=12, BLK_G=0)
    print("gamma_lut black level (now 0, awb.v did it):", blk_triple(p))
    gr, gb = awb_gains(words, p, verbose=True)
    r, g, b = awb_pixels(words, gr, gb, p)
    out = np.stack(gamma_pixels(r, g, b, p), axis=-1)[:, 0, :]   # pixel 0 of each word

    with open(os.path.join(OUT, "stim.hex"), "w") as f:
        for px in PIX:
            f.write(f"{px[0]:02x}{px[1]:02x}{px[2]:02x}\n")
    with open(os.path.join(OUT, "expected.hex"), "w") as f:
        for px in out:
            f.write(f"{int(px[0]):02x}{int(px[1]):02x}{int(px[2]):02x}\n")

    np.save(os.path.join(OUT, "gains.npy"), np.array([gr, gb]))
    print(f"gain_q8 R={gr} ({gr/256:.4f})  B={gb} ({gb/256:.4f})")
    print("\n  word  input       gamma (expected)")
    for i in range(len(PIX)):
        print(f"   {i:2d}   {tuple(int(v) for v in PIX[i])}   "
              f"{tuple(int(v) for v in out[i])}")


if __name__ == "__main__":
    main()
