import numpy as np
from PIL import Image

h = np.asarray(Image.open(r"tools/hdmi_128x72.png").convert('RGB')).astype(np.uint8)
m = np.asarray(Image.open(r"tools/recv_raw.png").convert('RGB')).astype(np.uint8)

# 按相关峰对齐: result[i,j] = m[i+7, j-40]
al = np.roll(np.roll(m, -7, axis=0), 40, axis=1)

def s4(x): return np.array(Image.fromarray(x,'RGB').resize((128*4,72*4), Image.NEAREST))

Image.fromarray(np.vstack([np.full((6,128,3),255,np.uint8), h, np.full((6,128,3),255,np.uint8), al]),'RGB').resize((128*4,(72*2+12)*4), Image.NEAREST).save(r"tools/align_cmp.png")
print("saved tools/align_cmp.png (上=HDMI, 下=接收图平移对齐后)")

# 逐象限找最佳位移
def best_shift(patch, target, ry, rx):
    best=(-9,0,0)
    tz = patch - patch.mean()
    tn = np.sqrt((tz**2).sum())
    if tn==0: return best
    for dy in range(-ry, ry+1, 2):
        for dx in range(-rx, rx+1, 2):
            w = np.roll(np.roll(target, dy, 0), dx, 1)
            wz = w - w.mean()
            d = np.sqrt((wz**2).sum())
            if d==0: continue
            c = (tz*wz).sum()/(tn*d)
            if c>best[0]: best=(c,dy,dx)
    return best

mg = m.mean(axis=2); hg = h.mean(axis=2)
print("\n各象限(64x36)在 HDMI 中的最佳位移:")
for name,(y0,y1,x0,x1) in {"左上":(0,36,0,64),"右上":(0,36,64,128),"左下":(36,72,0,64),"右下":(36,72,64,128)}.items():
    p = mg[y0:y1, x0:x1]
    c,dy,dx = best_shift(p, hg, 36, 64)
    print(f"   {name}: corr={c:.3f}  dy={dy:4d} dx={dx:4d}  -> HDMI 位置约 ({y0+dy},{x0+dx})")
