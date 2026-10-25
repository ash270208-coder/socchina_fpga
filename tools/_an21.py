import numpy as np
from PIL import Image, ImageDraw

a = np.asarray(Image.open(r"tools/py_recv.png").convert('RGB')).astype(np.uint8)
perms = [("RGB",(0,1,2)), ("RBG",(0,2,1)), ("GRB",(1,0,2)),
         ("GBR",(1,2,0)), ("BRG",(2,0,1)), ("BGR",(2,1,0))]
tiles=[]
S=3
for name,(i,j,k) in perms:
    im = a[:,:,[i,j,k]]
    im = np.array(Image.fromarray(im,'RGB').resize((128*S,72*S), Image.NEAREST))
    strip = np.full((30, im.shape[1],3), 0, np.uint8)
    canvas = np.vstack([strip, im])
    d = ImageDraw.Draw(Image.fromarray(canvas,'RGB'))
    d.text((8,8), f"byte order {name}", fill=(255,255,0))
    tiles.append(np.array(Image.fromarray(canvas,'RGB')))

W = tiles[0].shape[1]; H = tiles[0].shape[0]
sep = np.full((H,8,3),200,np.uint8)
r1 = np.hstack([tiles[0],sep,tiles[1],sep,tiles[2]])
r2 = np.hstack([tiles[3],sep,tiles[4],sep,tiles[5]])
hsep = np.full((8, r1.shape[1],3),200,np.uint8)
grid = np.vstack([r1,hsep,r2])
Image.fromarray(grid,'RGB').save(r"tools/perm_test.png")
print("saved tools/perm_test.png", grid.shape)
print("布局: 上排 RGB RBG GRB / 下排 GBR BRG BGR")
