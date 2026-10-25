import numpy as np
from PIL import Image

h = np.asarray(Image.open(r"tools/hdmi_128x72.png").convert('L')).astype(np.float64)
m = np.asarray(Image.open(r"tools/py_recv.png").convert('L')).astype(np.float64)

def zn(x):
    x = x - x.mean(); s = x.std()
    return x/s if s>0 else x

# 掩: HDMI 左侧 OSD(36列) + 双方底部丢包行(y>=68) + 四周边框
mask = np.ones_like(h)
mask[:, :36] = 0          # OSD
mask[68:, :] = 0          # 丢包黑行
mask[:3,:]=0; mask[-3:,:]=0; mask[:,:3]=0; mask[:,-3:]=0
hz = zn(h)*mask; den_h=(hz**2).sum()

res=[]
for dy in range(-72,73):
    for dx in range(-128,129):
        sh = zn(np.roll(np.roll(m, dy, 0), dx, 1))*mask
        den = np.sqrt((sh**2).sum()*den_h)
        res.append(((sh*hz).sum()/den if den>0 else 0, dy, dx))
res.sort(reverse=True)
print("=== 掩掉 OSD/丢包行后的最佳平移 ===")
for c,dy,dx in res[:6]:
    print(f"   corr={c:.4f}  dy={dy:5d}  dx={dx:5d}")
c0 = (zn(m)*mask*hz).sum()/np.sqrt(((zn(m)*mask)**2).sum()*den_h)
print(f"不平移 corr = {c0:.4f}")

# 并排图
best = res[0]
al = np.roll(np.roll(m, best[1], axis=0), best[2], axis=1)
hc = np.asarray(Image.open(r"tools/hdmi_128x72.png").convert('RGB')).astype(np.uint8)
mc = np.asarray(Image.open(r"tools/py_recv.png").convert('RGB')).astype(np.uint8)
alc= np.roll(np.roll(mc, best[1], axis=0), best[2], axis=1)
gap = np.full((5,128,3),255,np.uint8)
st = np.vstack([hc, gap, alc])
Image.fromarray(st,'RGB').resize((128*4,(72*2+5)*4), Image.NEAREST).save(r"tools/align_cmp2.png")
print("saved tools/align_cmp2.png (上=HDMI 下=新接收图按峰值平移后)")
