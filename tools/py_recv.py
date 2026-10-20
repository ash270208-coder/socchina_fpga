# py_recv.py —— 用 Python 直接收板A的 UDP 图像帧（绕过 MATLAB udpport 的乱序）
# 自动识别两种分包方案：
#   旧: 20 包 = 19x1400 + 1048   (datagram 1402 / 1050)
#   新: 24 包 = 24x1152          (datagram 1154，等长)
import socket, sys, time
import numpy as np
from PIL import Image

PORT = 6666
WAIT_S = 40.0
TOTAL = 128 * 72 * 3            # 27648

s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
try:
    s.bind(('0.0.0.0', PORT))
except OSError as e:
    print(f"BIND_FAIL: {e}  (MATLAB 可能还占着 {PORT})")
    sys.exit(2)
s.settimeout(2.0)
print(f"listening on udp/{PORT} ...")

NPKT = PAY_FULL = PAY_LAST = None
buf = bytearray(TOTAL)
got = None
t0 = time.time()
seen = 0
sizes = {}
while (time.time() - t0) < WAIT_S:
    if got is not None and all(got):
        break
    try:
        data, addr = s.recvfrom(4096)
    except socket.timeout:
        continue
    seen += 1
    if len(data) < 2:
        continue
    # 首包决定分包方案
    if NPKT is None:
        if len(data) >= 1402:
            NPKT, PAY_FULL, PAY_LAST = 20, 1400, 1048
            print("detected layout: 20 x (19*1400 + 1048)")
        else:
            NPKT, PAY_FULL, PAY_LAST = 24, 1152, 1152
            print("detected layout: 24 x 1152 (equal)")
        got = [False] * NPKT
    seq = data[0] * 256 + data[1]
    if not (0 <= seq < NPKT):
        continue
    sizes[seq] = len(data)
    if not got[seq]:
        got[seq] = True
        n = PAY_LAST if seq == NPKT - 1 else PAY_FULL
        n = min(n, len(data) - 2)
        buf[seq * PAY_FULL: seq * PAY_FULL + n] = data[2:2 + n]
        print(f"  seq {seq:2d}  len={len(data):4d}  {sum(got)}/{NPKT}")

print(f"datagrams seen={seen}  collected={sum(got)}/{NPKT}")
missing = [i for i in range(NPKT) if not got[i]]
if missing:
    print(f"missing seq: {missing}")

img = np.frombuffer(bytes(buf), dtype=np.uint8).reshape(72, 128, 3)
# ★ [修复12] 已进 RTL：pixel_to_bytes 现在按 R,G,B 顺序输出，这里不用再换。
#   若跑的是**未含修复12的旧 bit**，把 CH_SWAP 改成 True（旧 bit 是 B,R,G 序）。
CH_SWAP = False
if CH_SWAP:
    img = img[:, :, [1, 2, 0]]
Image.fromarray(img, 'RGB').save('tools/py_recv.png')
Image.fromarray(img, 'RGB').resize((128 * 4, 72 * 4), Image.NEAREST).save('tools/py_recv_4x.png')
print("saved tools/py_recv.png, tools/py_recv_4x.png")
print("fully-zero rows:", [y for y in range(72) if not img[y].any()])
