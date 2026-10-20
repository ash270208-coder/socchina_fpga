import numpy as np
from PIL import Image

h = np.asarray(Image.open(r"tools/hdmi_128x72.png").convert('L')).astype(np.float64)
m = np.asarray(Image.open(r"tools/py_recv.png").convert('L')).astype(np.float64)
print("hdmi", h.shape, " py_recv", m.shape)

def zn(x):
    x = x - x.mean(); s = x.std()
    return x/s if s>0 else x

mask = np.ones_like(h); mask[:, :36] = 0; mask[66:, :] = 0
mask[:4,:]=0; mask[-4:,:]=0; mask[:,:4]=0; mask[:,-4:]=0
hz = zn(h)*mask; den_h = (hz**2).sum()

res=[]
for dy in range(-72,73):
    for dx in range(-128,129):
        sh = zn(np.roll(np.roll(m, dy, 0), dx, 1))*mask
        den = np.sqrt((sh**2).sum()*den_h)
        res.append((( sh*hz).sum()/den if den>0 else 0, dy, dx))
res.sort(reverse=True)
print("\n=== 修复10 后的最佳平移 (corr, dy, dx) ===")
for c,dy,dx in res[:8]:
    print(f"   corr={c:.4f}  dy={dy:4d}  dx={dx:4d}")
sh = zn(m)*mask
print(f"\n不平移基线 corr = {(sh*hz).sum()/np.sqrt((sh**2).sum()*den_h):.4f}")
