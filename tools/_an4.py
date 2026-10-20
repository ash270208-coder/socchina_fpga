import numpy as np
from PIL import Image

raw = np.fromfile(r"tools/recv_raw.bin", dtype=np.uint8)

# 假设A: 行优先 72行x128列 (当前)
A = raw.reshape(72,128,3)
# 假设B: 列优先 -> 128行x72列
B = raw.reshape(128,72,3)          # 直接按128x72拆就是列优先的等价
print("A", A.shape, "B", B.shape)

variants = {
 "A_rowmajor_72x128": A,
 "B_colmajor_128x72": B,
 "B_rot180":          np.rot90(B,2),
 "B_flipud":          B[::-1],
 "B_fliplr":          B[:,::-1],
 "A_rot180":          np.rot90(A,2),
}
for name, im in variants.items():
    Image.fromarray(im,'RGB').resize((im.shape[1]*4, im.shape[0]*4), Image.NEAREST).save(f"tools/hyp_{name}.png")
    print("saved", name, im.shape)
