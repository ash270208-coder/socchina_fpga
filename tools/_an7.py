import numpy as np
from PIL import Image

raw = np.fromfile(r"tools/recv_raw.bin", dtype=np.uint8)
a = raw.reshape(72,128,3).copy()

# 把最后3行(丢包全零)用上一行补齐，避免黑条干扰判断
for y in (69,70,71):
    if np.all(a[y]==0):
        a[y] = a[68]

def show(x, name):
    Image.fromarray(x,'RGB').resize((128*5,72*5), Image.NEAREST).save(f"tools/{name}.png")
    print("saved", name)

show(a, "v_raw_filled")

# 对角互换: 行roll 36 + 列roll 64  -> 左下内容移到右上
d = np.roll(np.roll(a, 36, axis=0), 64, axis=1)
show(d, "v_diag_filled")

# 并排对比图 (raw 上, diag 下) 加分隔
gap = np.full((6,128,3), 255, np.uint8)
stack = np.vstack([a, gap, d])
Image.fromarray(stack,'RGB').resize((128*5, (72*2+6)*5), Image.NEAREST).save(r"tools/v_compare.png")
print("saved v_compare (上=原图 下=对角互换)")
