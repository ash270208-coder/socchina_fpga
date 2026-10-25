import numpy as np
from PIL import Image

p = r"C:\Users\jingzifu\.dsh\attachments\v1\objects\00\0032fd4ef1e736a4e3235888699514462624b6ee525c92b61ff31409c616ffea"
im = Image.open(p).convert('RGB')
W,H = im.size
a = np.asarray(im).astype(np.float32)
g = a.mean(axis=2)

# 找屏幕: 亮区包围盒 (阈值)
thr = g > 60
cols = thr.mean(axis=0); rows = thr.mean(axis=1)
xs = np.where(cols>0.35)[0]; ys = np.where(rows>0.35)[0]
print("detected screen bbox: x", xs.min(), xs.max(), " y", ys.min(), ys.max())
x0,x1,y0,y1 = xs.min(), xs.max(), ys.min(), ys.max()

# 按16:9修正高度
w = x1-x0
hh = int(round(w*9/16))
cy = (y0+y1)//2
y0b, y1b = max(0,cy-hh//2), min(H, cy+hh//2)
print("corrected 16:9 crop: x",x0,x1," y",y0b,y1b, " ratio", w/(y1b-y0b))

crop = im.crop((x0,y0b,x1,y1b)).resize((128,72), Image.LANCZOS)
crop.save(r"tools/hdmi_128x72.png")
crop.resize((128*4,72*4), Image.NEAREST).save(r"tools/hdmi_128x72_4x.png")
print("saved hdmi_128x72.png")
