import numpy as np
from PIL import Image

h  = np.asarray(Image.open(r"tools/hdmi_128x72.png").convert('RGB')).astype(np.uint8)
m  = np.asarray(Image.open(r"tools/py_recv.png").convert('RGB')).astype(np.uint8)
hg = h.mean(axis=2).astype(np.float64); mg = m.mean(axis=2).astype(np.float64)

def zn(x):
    x = x - x.mean(); s = x.std()
    return x/s if s>0 else x

mask = np.ones_like(hg); mask[:, :36] = 0
mask[:3,:]=0; mask[-3:,:]=0; mask[:,:3]=0; mask[:,-3:]=0
hz = zn(hg)*mask; den_h=(hz**2).sum()

res=[]
for dy in range(-72,73):
    for dx in range(-128,129):
        s = zn(np.roll(np.roll(mg, dy, 0), dx, 1))*mask
        den = np.sqrt((s**2).sum()*den_h)
        res.append(((s*hz).sum()/den if den>0 else 0, dy, dx))
res.sort(reverse=True)
print("=== 本帧 vs HDMI 照片 最佳平移 ===")
for c,dy,dx in res[:5]:
    print(f"   corr={c:.4f}  dy={dy:5d}  dx={dx:5d}")
print(f"不平移 corr = {(zn(mg)*mask*hz).sum()/np.sqrt((((zn(mg)*mask))**2).sum()*den_h):.4f}")

gap = np.full((6,128,3),255,np.uint8)
Image.fromarray(np.vstack([h, gap, m]),'RGB').resize((128*4,(72*2+6)*4), Image.NEAREST).save(r"tools/final_cmp.png")
print("saved tools/final_cmp.png (上=HDMI 下=板A接收, 未做任何平移)")
