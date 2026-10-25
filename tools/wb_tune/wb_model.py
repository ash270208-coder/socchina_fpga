"""wb_model.py -- bit-exact Python model of the real board chain

    sensor(linear) -> awb.v -> gamma_lut.v -> display

Used to answer "画面发灰" quantitatively BEFORE touching RTL.
Every operation here mirrors the Verilog expression it is named after, including
the truncating shifts (>>8) and the saturating clamps.

Chain under test (user_source/hdl_source/):
    awb.v        : G+G/4 boost, dynamic R/B gain (Q8), halo clamp, specular white
    gamma_lut.v  : subtract fixed black level, then gamma 255*(x/255)**(1/2.2)

The black level is the interesting part: awb.v multiplies the sensor pedestal by
(1.25*Kr) / 1.25 / (1.25*Kb) but gamma_lut.v subtracts 21/12/33, which are the
pedestal scaled by 1.75/1.0/2.75.  The residual is small in LSB but gamma 2.2 is
a 5x amplifier down there -- that is the "grey veil".
"""
import os
import re
import numpy as np

# ---------------------------------------------------------------------------
# gamma table: parsed straight out of gamma_lut.v so it can never drift
# ---------------------------------------------------------------------------
_here = os.path.dirname(os.path.abspath(__file__))
GAMMA_V = os.path.join(_here, "..", "..",
                       "lab_ex1_mipi_hdmi_SC500_720P+vpp", "lab_ex1_mipi_hdmi+vpp",
                       "user_source", "hdl_source", "gamma_lut.v")


def load_gamma_table(path=GAMMA_V):
    txt = open(path, encoding="utf-8", errors="replace").read()
    tab = np.zeros(256, dtype=np.int32)
    seen = 0
    for m in re.finditer(r"8'd(\d+)\s*:\s*gamma_map\s*=\s*8'd(\d+)", txt):
        tab[int(m.group(1))] = int(m.group(2))
        seen += 1
    if seen != 256:
        raise RuntimeError(f"gamma table parse: got {seen} entries, expected 256")
    return tab


GAMMA = load_gamma_table()

# sanity: the table must be round(255*(x/255)^(1/2.2))
_x = np.arange(256, dtype=np.float64)
_ref = np.round(255.0 * (_x / 255.0) ** (1 / 2.2)).astype(np.int32)
assert np.array_equal(GAMMA, _ref), "gamma_lut.v table is not gamma 2.2"


# ---------------------------------------------------------------------------
# default RTL constants (keep in sync with the .v files)
# ---------------------------------------------------------------------------
from dataclasses import dataclass, field


@dataclass
class P:
    """Defaults == the *fixed* RTL (awb.v PEDESTAL=12, gamma_lut.v BLK_G=0).

    Use P_OLD to reproduce the pre-fix build.
    """
    # --- awb.v -----------------------------------------------------------
    blk_in: int = 12           # pedestal removed BEFORE the gain (fixed RTL)
    g_boost_num: int = 1       # g_boost = frame_g + frame_g*num/den  == 1.25x
    g_boost_den: int = 4       #   (awb.v: frame_g + {2'b00, frame_g[31:2]})
    corridor_r: tuple = (0x19000, 0x1F000)      # 1.5625 .. 1.9375   (Q16)
    corridor_b: tuple = (0x27000, 0x32000)      # 2.4375 .. 3.125    (Q16)
    halo_zone: int = 196       # awb.v: g_d >= 196 -> R<=G+16, B>=G-24
    halo_r_up: int = 16
    halo_b_dn: int = 24
    specular: int = 248        # awb.v: g_d >= 248 -> pure white
    # --- gamma_lut.v -----------------------------------------------------
    BLK_G: int = 0             # pedestal subtracted AFTER the gain (fixed RTL)
    blk_r_ratio: float = 0.0
    blk_b_ratio: float = 0.0


def P_OLD(**kw):
    """The pre-fix build: pedestal left in, removed after the gain at 12/21/33."""
    d = dict(blk_in=0, BLK_G=12, blk_r_ratio=1.75, blk_b_ratio=2.75)
    d.update(kw)
    return P(**d)


def blk_triple(p):
    g = p.BLK_G
    r = int(g * p.blk_r_ratio)
    b = int(g * p.blk_b_ratio)
    return r, g, b


# ---------------------------------------------------------------------------
# awb.v statistics + gain loop (one "frame" = one pass over the image)
# ---------------------------------------------------------------------------
def awb_gains(img, p, frames=120, verbose=False):
    """img: HxWx3 uint8 = awb input.  Reproduces the whole gain loop.

    awb.v samples only pixel 0 of every 4-pixel group (tdata[16:8]) -> 1/4 of
    the pixels, i.e. columns 0,4,8,... of the raster.

    NOTE the pedestal: awb.v sums the pixels it receives.  If the pedestal is
    removed at the awb input (p.blk_in), the statistics are pedestal-free too --
    and that matters a lot, because on this board the pedestal is 12 LSB out of
    a ~50 LSB mean signal (24%).  Leaving it inside the means compresses
    frame_g/frame_r and frame_g/frame_b, so the gains come out too small and get
    pinned to the corridor edge -> AWB never actually converges.
    """
    src = img.astype(np.int64)
    if p.blk_in:
        src = np.maximum(src - p.blk_in, 0)
    samp = src.reshape(-1, 3)[0::4]
    sum_r, sum_g, sum_b = samp[:, 0].sum(), samp[:, 1].sum(), samp[:, 2].sum()
    frame_r = max(sum_r, 1000)
    frame_g = max(sum_g, 1000)
    frame_b = max(sum_b, 1000)

    g_boost = frame_g + (frame_g * p.g_boost_num) // p.g_boost_den   # frame_g + frame_g/4

    def target(den, corr):
        q = (int(g_boost) << 16) // max(int(den), 1)
        lo, hi = corr
        return lo if q < lo else (hi if q > hi else q)

    t_r = target(frame_r, p.corridor_r)
    t_b = target(frame_b, p.corridor_b)

    cur_r, cur_b = 0x1C000, 0x2C000          # reset values
    for _ in range(frames):                  # one IIR step per vblank
        cur_r = cur_r - (cur_r >> 4) + (t_r >> 4)
        cur_b = cur_b - (cur_b >> 4) + (t_b >> 4)
    g_r = (cur_r >> 8) & 0x3FF
    g_b = (cur_b >> 8) & 0x3FF
    if verbose:
        print(f"    frame means R/G/B = {frame_r/ samp.shape[0]:.1f} / "
              f"{frame_g/samp.shape[0]:.1f} / {frame_b/samp.shape[0]:.1f}")
        print(f"    target q16 R={t_r} ({t_r/65536:.3f}x)  B={t_b} ({t_b/65536:.3f}x)"
              f"   [Q16 增益, 已含 G 的 1.25x 提亮]")
        print(f"    applied Q8 gain R={g_r}/256={g_r/256:.4f}  B={g_b}/256={g_b/256:.4f}")
    return g_r, g_b


# ---------------------------------------------------------------------------
# awb.v pixel path
# ---------------------------------------------------------------------------
def awb_pixels(img, g_r, g_b, p):
    r = img[..., 0].astype(np.int32)
    g = img[..., 1].astype(np.int32)
    b = img[..., 2].astype(np.int32)

    if p.blk_in:
        r = np.maximum(r - p.blk_in, 0)
        g = np.maximum(g - p.blk_in, 0)
        b = np.maximum(b - p.blk_in, 0)

    # G: wire [8:0] p_g_bst = p_g + {2'b00, p_g[7:2]};  saturate on bit 8
    g_bst = g + (g >> 2)
    g_d = np.where(g_bst >= 256, 255, g_bst & 0xFF)

    # R/B: reg [17:0] r_m = p_r * gain_q8;  if |r_m[17:16] -> 255 else r_m[15:8]
    r_m = r * g_r
    b_m = b * g_b
    r_raw = np.where((r_m >> 16) != 0, 255, (r_m >> 8) & 0xFF)
    b_raw = np.where((b_m >> 16) != 0, 255, (b_m >> 8) & 0xFF)

    # halo: R <= G+16 , B >= G-24   (only where g_d >= halo_zone)
    r_lim = np.minimum(g_d + p.halo_r_up, 255)
    b_flr = np.maximum(g_d - p.halo_b_dn, 0)
    zone = g_d >= p.halo_zone
    r_out = np.where(zone, np.minimum(r_raw, r_lim), r_raw)
    b_out = np.where(zone, np.maximum(b_raw, b_flr), b_raw)

    # specular: g_d >= 248 -> 255,255,255
    spec = g_d >= p.specular
    r_out = np.where(spec, 255, r_out)
    b_out = np.where(spec, 255, b_out)
    g_out = np.where(spec, 255, g_d)

    return np.clip(r_out, 0, 255), np.clip(g_out, 0, 255), np.clip(b_out, 0, 255)


# ---------------------------------------------------------------------------
# gamma_lut.v pixel path
# ---------------------------------------------------------------------------
def gamma_pixels(r, g, b, p):
    br, bg, bb = blk_triple(p)
    rl = np.maximum(r - br, 0).astype(np.int32)
    gl = np.maximum(g - bg, 0).astype(np.int32)
    bl = np.maximum(b - bb, 0).astype(np.int32)
    return GAMMA[rl], GAMMA[gl], GAMMA[bl]


def run(img, p, frames=120, verbose=False):
    """full chain: awb (dynamic gains) -> gamma_lut -> uint8 RGB"""
    g_r, g_b = awb_gains(img, p, frames=frames, verbose=verbose)
    r, g, b = awb_pixels(img, g_r, g_b, p)
    return np.stack(gamma_pixels(r, g, b, p), axis=-1).astype(np.uint8)


# ---------------------------------------------------------------------------
# metrics
# ---------------------------------------------------------------------------
def y_of(rgb):
    i = rgb.astype(np.float64)
    return 0.299 * i[..., 0] + 0.587 * i[..., 1] + 0.114 * i[..., 2]


def metrics(rgb, name=""):
    i = rgb.astype(np.float64)
    y = y_of(rgb)
    mx = i.max(axis=2)
    mn = i.min(axis=2)
    # saturation only over pixels that actually carry light -- otherwise a lifted
    # black (0,34,0) scores sat=1.0 and lies about how colourful the picture is
    lit = mx >= 48
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1), 0.0)
    sat_lit = float(sat[lit].mean()) if lit.any() else 0.0
    p5, p50, p95 = np.percentile(y, [5, 50, 95])
    m = dict(name=name,
             ymin=float(y.min()), yp5=float(p5), yp50=float(p50), yp95=float(p95),
             span=float(p95 - p5), std=float(y.std()),
             sat=sat_lit,
             darkest=tuple(float(v) for v in i[y <= np.percentile(y, 2)].mean(axis=0)),
             mean=tuple(float(v) for v in i.reshape(-1, 3).mean(axis=0)))
    return m


def show(m):
    r, g, b = m["mean"]
    print(f"  {m['name']:<22s} Ymin={m['ymin']:5.1f} Yp5={m['yp5']:5.1f} Ymean={m['yp50']:5.1f} "
          f"Yp95={m['yp95']:5.1f} span={m['span']:5.1f} std={m['std']:5.1f} "
          f"sat(lit)={m['sat']:.3f} meanRGB=({r:5.1f},{g:5.1f},{b:5.1f}) "
          f"darkest2%=({m['darkest'][0]:.0f},{m['darkest'][1]:.0f},{m['darkest'][2]:.0f})")
