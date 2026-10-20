import numpy as np
from PIL import Image

raw = np.fromfile(r"tools/recv_raw.bin", dtype=np.uint8)
a = raw.reshape(72, 128, 3).astype(np.float64)

# 只取有效区(去掉最后1048零字节影响的底部3行)做能量评估
valid = 69   # y=0..68 有效
def energy(img, cut=True):
    g = img.mean(axis=2)
    if cut: g = g[:69]
    return np.abs(np.diff(g,axis=0)).sum() + np.abs(np.diff(g,axis=1)).sum()

def cs(img, k, d):
    return np.roll(img, k, axis=d)

hyps = {
 "identity            ": a,
 "circshift(36,1)+(64,2)": cs(cs(a,36,0),64,1),
 "circshift(-36,1)+(-64,2)": cs(cs(a,-36,0),-64,1),
 "rot90(x,2) 180deg   ": np.rot90(a,2),
 "flipud              ": a[::-1],
 "fliplr              ": a[:,::-1],
 "flipud+fliplr       ": a[::-1,::-1],
 "transpose           ": a.transpose(1,0,2),
 "transpose+rot180    ": np.rot90(a.transpose(1,0,2),2),
}
print("hypothesis                 total-seam-energy  (越小越连续)")
for k,v in hyps.items():
    print(f"  {k:24s} {energy(v):10.0f}")

# 关键: 对角互换是否在 x=64 / y=36 处新增接缝
g = a.mean(axis=2)
print("\nraw 在候选边界处的接缝强度:")
print(f"  列 x=64 接缝 |{g[:,63].mean():.1f}-{g[:,64].mean():.1f}| = {abs(g[:,63].mean()-g[:,64].mean()):.1f}")
print(f"  行 y=36 接缝 |{g[35,:].mean():.1f}-{g[36,:].mean():.1f}| = {abs(g[35,:].mean()-g[36,:].mean()):.1f}")
