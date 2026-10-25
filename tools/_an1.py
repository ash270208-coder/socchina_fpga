import numpy as np
from PIL import Image

raw = np.fromfile(r"tools/recv_raw.bin", dtype=np.uint8)
print("total bytes:", raw.size, " expect:", 128*72*3)

# 按 row-major 拆: img[y][x] = (R,G,B)
a = raw.reshape(72, 128, 3).astype(np.int32)
print("shape:", a.shape)

# 每行的平均亮度, 找横向分界
rowmean = a.mean(axis=(1,2))
print("\nrow mean brightness (per row 0..71):")
for y in range(72):
    print(f"  y={y:2d}  {rowmean[y]:7.1f}")

# 每列平均亮度, 找纵向分界
colmean = a.mean(axis=(0,2))
print("\ncol mean brightness (per col 0..127), 每8列:")
for x in range(0, 128, 8):
    seg = colmean[x:x+8]
    print(f"  x={x:3d}-{x+7:3d}: " + " ".join(f"{v:6.1f}" for v in seg))
