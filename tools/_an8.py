import numpy as np
from PIL import Image, ImageDraw

raw = np.fromfile(r"tools/recv_raw.bin", dtype=np.uint8)
a = raw.reshape(72,128,3).astype(np.uint8).copy()
for y in (69,70,71):
    if np.all(a[y]==0): a[y]=a[68]

# 疑似"头": 白圆+两个黑点, 大约 x20-70 y25-65
Image.fromarray(a[25:66, 20:72],'RGB').resize((52*10,41*10), Image.NEAREST).save(r"tools/zoom_head.png")

# 四块
TL=a[0:36,0:64]; TR=a[0:36,64:128]; BL=a[36:72,0:64]; BR=a[36:72,64:128]
# 候选: 把左下的内容放到右上 (TR位置)
cands = [
 ("1", [TL,BL,TR,BR]),
 ("2", [TL,BL,BR,TR]),
 ("3", [TR,BL,TL,BR]),
 ("4", [TR,BL,BR,TL]),
 ("5", [BR,BL,TL,TR]),
 ("6", [BR,BL,TR,TL]),
]
S=2
tiles=[]
for name, q in cands:
    top    = np.hstack([q[0], np.full((36,4,3),255,np.uint8), q[1]])
    bot    = np.hstack([q[2], np.full((36,4,3),255,np.uint8), q[3]])
    mid    = np.full((4, top.shape[1],3),255,np.uint8)
    im     = np.vstack([top, mid, bot])
    im     = np.array(Image.fromarray(im).resize((im.shape[1]*S, im.shape[0]*S), Image.NEAREST))
    d = ImageDraw.Draw(Image.fromarray(im))
    tiles.append(im)

# 3列x2行
per_row=3
rows=[]
for r in range(2):
    row = tiles[r*per_row:(r+1)*per_row]
    row = [np.pad(t, ((0,0),(0,0),(0,1)), constant_values=255) for t in row]
    rows.append(np.hstack(row))
grid = np.vstack(rows)
Image.fromarray(grid,'RGB').save(r"tools/cands.png")
print("saved tools/cands.png", grid.shape, " 顺序: 左上=1 中上=2 右上=3 / 左下=4 中下=5 右下=6")
