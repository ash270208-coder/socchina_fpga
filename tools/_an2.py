import numpy as np
from PIL import Image

raw = np.fromfile(r"tools/recv_raw.bin", dtype=np.uint8)
a = raw.reshape(72, 128, 3).astype(np.float64)
g = a.mean(axis=2)   # 灰度 72x128

# --- 列接缝能量: |col[x] - col[x-1]| 平均 ---
cs = np.abs(np.diff(g, axis=1)).mean(axis=0)
print("column seam energy (x = boundary between x-1 and x), top 15:")
idx = np.argsort(cs)[::-1][:15]
for i in sorted(idx):
    print(f"   x={i+1:3d}  seam={cs[i]:6.2f}   left={g[:,i].mean():6.1f} right={g[:,i+1].mean():6.1f}")

rs = np.abs(np.diff(g, axis=0)).mean(axis=1)
print("\nrow seam energy (y = boundary between y-1 and y), top 10:")
idx = np.argsort(rs)[::-1][:10]
for i in sorted(idx):
    print(f"   y={i+1:3d}  seam={rs[i]:6.2f}   up={g[i,:].mean():6.1f} down={g[i+1,:].mean():6.1f}")

# --- 全黑/全零区域 ---
zero_rows = [y for y in range(72) if np.all(raw.reshape(72,128,3)[y]==0)]
print("\nfully-zero rows:", zero_rows)
print("zero bytes total:", int((raw==0).sum()))

# --- 放大 4 倍存图 ---
im = Image.fromarray(raw.reshape(72,128,3), 'RGB').resize((128*4, 72*4), Image.NEAREST)
im.save(r"tools/recv_raw_4x.png")
print("\nsaved tools/recv_raw_4x.png")
