W, H = 96, 64
val = 50  # 偏暗灰度 R=G=B=50 -> Y=(255*50)>>8 = 49, 远低于目标128, 触发增益爬升
pix = '%06X' % ((val << 16) | (val << 8) | val)
data = (pix + '\n') * (W * H)
data = data.rstrip('\n')
with open('src_img.txt', 'w') as f:
    f.write(data)
print('generated', W * H, 'pixels, value=%02X' % val)
