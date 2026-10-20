import numpy as np
from PIL import Image, ImageDraw

raw = np.fromfile(r"tools/recv_raw.bin", dtype=np.uint8)
a = raw.reshape(72,128,3)
S = 6
im = Image.fromarray(a,'RGB').resize((128*S,72*S), Image.NEAREST)
d = ImageDraw.Draw(im)
# 象限边界
for x in (64,):  d.line([(x*S,0),(x*S,72*S)], fill=(255,0,0), width=2)
for y in (36,):  d.line([(0,y*S),(128*S,y*S)], fill=(255,0,0), width=2)
# 每16列淡线
for x in range(0,128,16): d.line([(x*S,0),(x*S,72*S)], fill=(0,255,0), width=1)
for y in range(0,72,8):   d.line([(0,y*S),(128*S,y*S)], fill=(0,255,0), width=1)
# 标注
for lbl,(px,py) in {"A":(10,10),"B":(76,10),"C":(10,44),"D":(76,44)}.items():
    d.text((px*S+4, py*S+4), lbl, fill=(255,255,0))
# 暗带标注
d.line([(64*S,0),(64*S,72*S)], fill=(255,255,255), width=1)
d.line([(87*S,0),(87*S,72*S)], fill=(255,255,255), width=1)
im.save(r"tools/diag_grid.png")
print("saved tools/diag_grid.png", im.size)

# 四象限分别存出来
for lbl,(x0,x1,y0,y1) in {"A":(0,64,0,36),"B":(64,128,0,36),"C":(0,64,36,72),"D":(64,128,36,72)}.items():
    q = a[y0:y1, x0:x1]
    Image.fromarray(q,'RGB').resize(((x1-x0)*6,(y1-y0)*6), Image.NEAREST).save(f"tools/quad_{lbl}.png")
print("saved 4 quadrants")
