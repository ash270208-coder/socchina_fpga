import numpy as np
from PIL import Image

a = np.asarray(Image.open(r"tools/py_recv.png").convert('RGB')).astype(np.int32)
print("shape", a.shape)
print("\n各通道 (PIL 按 R,G,B 解释):")
for i,n in enumerate("RGB"):
    c = a[:,:,i]
    print(f"  {n}: mean={c.mean():6.1f} std={c.std():5.1f} min={c.min():3d} max={c.max():3d}")

print("\n通道相关:")
for i in range(3):
    for j in range(i+1,3):
        print(f"  {'RGB'[i]} vs {'RGB'[j]}: {np.corrcoef(a[:,:,i].ravel(), a[:,:,j].ravel())[0,1]:+.3f}")

# 找最红/最黄/最亮的区域, 看真实颜色
r,g,b = a[:,:,0], a[:,:,1], a[:,:,2]
def show(name, m):
    ys,xs = np.where(m)
    if len(ys)==0: print(f"  {name}: none"); return
    print(f"  {name}: n={len(ys):4d}  平均RGB=({r[m].mean():5.1f},{g[m].mean():5.1f},{b[m].mean():5.1f})")

print("\n颜色区域统计:")
show("最偏红(R-G>30)", (r-g)>30)
show("最偏绿(G-R>30)", (g-r)>30)
show("最偏蓝(B-R>30)", (b-r)>30)
show("暗部(均值<80)", (r+g+b)/3<80)
show("亮部(均值>180)", (r+g+b)/3>180)

# 直接看特征点
for name,(y,x) in {"头/脸":(20,55),"衣服中心":(40,60),"身体下部":(60,55),"左侧":(40,12),"右侧":(40,115)}.items():
    v=a[y,x]; print(f"  点 {name:8s} ({y:2d},{x:3d}) RGB=({v[0]:3d},{v[1]:3d},{v[2]:3d})")
