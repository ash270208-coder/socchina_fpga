import numpy as np
from PIL import Image, ImageDraw

raw = np.fromfile(r"tools/recv_raw.bin", dtype=np.uint8)
a = raw.reshape(72,128,3).copy()
for y in (69,70,71):
    if np.all(a[y]==0): a[y]=a[68]

TL=a[0:36,0:64].copy(); TR=a[0:36,64:128].copy()
BL=a[36:72,0:64].copy(); BR=a[36:72,64:128].copy()

# 头在 BL. 候选: 把 BL 放到 右上
cands = [("1",TL,BL,TR,BR), ("2",TL,BL,BR,TR), ("3",TR,BL,TL,BR),
         ("4",TR,BL,BR,TL), ("5",BR,BL,TL,TR), ("6",BR,BL,TR,TL)]

S=2; LW=4; GAPC=6
def tile(name,q0,q1,q2,q3):
    top = np.hstack([q0, np.full((36,LW,3),255,np.uint8), q1])
    bot = np.hstack([q2, np.full((36,LW,3),255,np.uint8), q3])
    im  = np.vstack([top, np.full((LW,top.shape[1],3),255,np.uint8), bot])
    im  = np.array(Image.fromarray(im.astype(np.uint8),'RGB').resize((im.shape[1]*S, im.shape[0]*S), Image.NEAREST))
    strip = np.full((26, im.shape[1],3), 0, np.uint8)
    canvas = np.vstack([strip, im])
    d = ImageDraw.Draw(Image.fromarray(canvas,'RGB'))
    d.text((6,6), f"#{name}", fill=(255,255,0))
    return np.array(Image.fromarray(canvas,'RGB'))

ts=[tile(*c) for c in cands]
h = ts[0].shape[0]; w = ts[0].shape[1]
vsep = np.full((h,GAPC,3),128,np.uint8)
r1 = np.hstack([ts[0],vsep,ts[1],vsep,ts[2]])
r2 = np.hstack([ts[3],vsep,ts[4],vsep,ts[5]])
hsep = np.full((GAPC, r1.shape[1],3),128,np.uint8)
grid = np.vstack([r1,hsep,r2])
Image.fromarray(grid,'RGB').save(r"tools/cands2.png")
print("saved tools/cands2.png", grid.shape)
print("布局: #1 #2 #3 (上排)   #4 #5 #6 (下排)  白线=块边界")
