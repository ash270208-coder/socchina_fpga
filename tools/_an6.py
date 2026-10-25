import numpy as np
from PIL import Image

raw = np.fromfile(r"tools/recv_raw.bin", dtype=np.uint8)
a = raw.reshape(72,128,3)

# 1) 左下角(C: y36-72, x0-64) 放大
C = a[36:72, 0:64]
Image.fromarray(C,'RGB').resize((64*8,36*8), Image.NEAREST).save(r"tools/zoom_C_bl.png")

# 2) 右上角(B: y0-36, x64-128) 放大
B = a[0:36, 64:128]
Image.fromarray(B,'RGB').resize((64*8,36*8), Image.NEAREST).save(r"tools/zoom_B_tr.png")

# 3) 对角互换 (roll 36行 + 64列) —— 头应从左下移到右上
d = np.roll(np.roll(a, 36, axis=0), 64, axis=1)
Image.fromarray(d,'RGB').resize((128*5,72*5), Image.NEAREST).save(r"tools/fix_diag.png")

# 4) 180度
Image.fromarray(np.rot90(a,2),'RGB').resize((128*5,72*5), Image.NEAREST).save(r"tools/fix_rot180.png")

print("saved zoom_C_bl, zoom_B_tr, fix_diag, fix_rot180")
