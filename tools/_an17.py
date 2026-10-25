import numpy as np
from PIL import Image

img = np.asarray(Image.open(r"tools/py_recv.png").convert('RGB')).astype(np.float64)
g = img.mean(axis=2)
print("shape", img.shape, " mean %.1f  std %.2f" % (g.mean(), g.std()))

# 接缝能量: 打乱的图接缝极大, 真实模糊场景接缝很小
cs = np.abs(np.diff(g, axis=1)).mean()
rs = np.abs(np.diff(g, axis=0)).mean()
print(f"列接缝均值 {cs:.2f}   行接缝均值 {rs:.2f}")
print("(参考: 之前公仔图约 12; 打乱/噪声会 >40)")

# 行/列亮度
print("\n每行均值(每6行):", " ".join(f"{g[y].mean():5.0f}" for y in range(0,72,6)))
print("每列均值(每16列):", " ".join(f"{g[:,x].mean():5.0f}" for x in range(0,128,16)))

# 8bit 直方图分布
h,_ = np.histogram(g, bins=8, range=(0,256))
print("\n亮度直方图(8档):", (h/h.sum()*100).round(1))

# 存 bin 备查
raw = np.asarray(Image.open(r"tools/py_recv.png").convert('RGB')).tobytes()
open(r"tools/py_recv.bin","wb").write(raw)
print("\nsaved tools/py_recv.bin")
