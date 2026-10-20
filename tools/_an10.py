import numpy as np
from PIL import Image
import glob, os

# 找到附件里的 HDMI 照片
cands = glob.glob(r"C:\Users\jingzifu\.dsh\attachments\v1\objects\00\0032fd4ef1e736a4e3235888699514462624b6ee525c92b61ff31409c616ffea*")
print("found:", cands[:3])
p = cands[0]
im = Image.open(p).convert('RGB')
print("photo size:", im.size)
