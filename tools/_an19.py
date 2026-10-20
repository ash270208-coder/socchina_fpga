import numpy as np
from PIL import Image

raw = np.fromfile(r"tools/recv_raw.bin", dtype=np.uint8)
print("recv_raw.bin size:", raw.size)
a = raw.reshape(72,128,3).astype(np.int32)      # 直接按 (R,G,B) 顺序看

print("\n各通道均值 (按字节顺序 0/1/2):")
for i in range(3):
    print(f"  byte[{i}]: mean={a[:,:,i].mean():6.1f}  std={a[:,:,i].std():5.1f}  min={a[:,:,i].min():3d} max={a[:,:,i].max():3d}")

# 通道间相关: 判断是不是 R/G/B 顺序排错了
print("\n通道间相关系数:")
for i in range(3):
    for j in range(i+1,3):
        c = np.corrcoef(a[:,:,i].ravel(), a[:,:,j].ravel())[0,1]
        print(f"  ch{i} vs ch{j}: {c:+.3f}")

# 取几个特征点看数值 (公仔身体中心/背景)
pts = {"公仔身体(约)": (40, 55), "公仔头(约)": (25, 55), "左侧背景": (40, 10), "右侧背景": (40, 115)}
print("\n特征点原始字节 (byte0,byte1,byte2):")
for name,(y,x) in pts.items():
    v = a[y,x]
    print(f"  {name:12s} y={y:2d} x={x:3d} -> ({v[0]:3d},{v[1]:3d},{v[2]:3d})")
