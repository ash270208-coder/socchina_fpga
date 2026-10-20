import numpy as np
from PIL import Image

p = r"C:\Users\jingzifu\.dsh\attachments\v1\objects\00\0032fd4ef1e736a4e3235888699514462624b6ee525c92b61ff31409c616ffea"
im = Image.open(p).convert('RGB')
a = np.asarray(im).astype(np.float32); g = a.mean(axis=2)
H,W = g.shape
print("photo", W, "x", H)

# 屏幕边缘: 沿列/行找"暗->亮"的台阶
colprof = g[H//4:3*H//4, :].mean(axis=0)
rowprof = g[:, W//4:3*W//4].mean(axis=1)
print("\n左边 60 列亮度:", " ".join(f"{v:.0f}" for v in colprof[:60:4]))
print("右边 60 列亮度:", " ".join(f"{v:.0f}" for v in colprof[-60::4]))
print("\n上边 60 行亮度:", " ".join(f"{v:.0f}" for v in rowprof[:60:4]))
print("下边 60 行亮度:", " ".join(f"{v:.0f}" for v in rowprof[-60::4]))

# 取一个更可靠的裁剪: 亮度>80 的连通主体
thr = g>80
cs = thr.sum(axis=0); rs = thr.sum(axis=1)
cx = np.where(cs > 0.6*H)[0]; ry = np.where(rs > 0.6*W)[0]
print("\n高置信屏幕区: x", cx.min(), cx.max(), " y", ry.min(), ry.max())
