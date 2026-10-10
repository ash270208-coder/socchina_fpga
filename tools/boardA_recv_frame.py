#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
boardA_recv_frame.py —— 板 A「发图」验收脚本（电脑当板 B）

收 20 个 UDP 包，拼成 128x72 RGB 图像，存成 PNG。
**只用标准库**（socket / zlib / struct），不需要装 numpy / Pillow。

前置条件
--------
1. PC 网卡 IP 设成 **192.168.240.2**，掩码 255.255.255.0，网关留空。
   板 A 把图像固定发到 192.168.240.2:**6666**（`board_a_net_wrapper.v` 里的
   `DST_IP_ADDRESS` / `DST_UDP_PORT_NUM`），所以 PC 必须是 .2。
   （不想改网卡的话，给网卡加第二个 IP 192.168.240.2 也行。）
2. 板 A 已烧录第 3 步的 bit，网线直连，`ping 192.168.240.1` 通。
3. Windows 防火墙放行入站 UDP 6666（或临时关掉）。

用法
----
    python boardA_recv_frame.py                  # 收 1 帧，存 frame_001.png
    python boardA_recv_frame.py --count 5        # 收 5 帧
    python boardA_recv_frame.py --scale 8        # 存 8 倍放大图，便于肉眼比对
    python boardA_recv_frame.py --port 6666 --bind 192.168.240.2

协议（板 B 已钉死，见 docs/板A以太网改造_实施计划.md §8.3）
----------
UDP 载荷 = [seq_hi, seq_lo] + 图像字节，大端序号 0..19
    包 0~18 : 2 + 1400  = 1402 字节
    包 19   : 2 + 1048  = 1050 字节
    合计 19*1400 + 1048 = 27648 = 128*72*3，字节序 R,G,B 逐像素排列
"""

import argparse
import os
import socket
import struct
import sys
import time
import zlib

W, H = 128, 72
NPKT = 20
PAY_FULL = 1400     # 包 0~18 的图像字节数
PAY_LAST = 1048     # 包 19 的图像字节数
IMG_BYTES = W * H * 3


# ---------------------------------------------------------------------------
# 纯标准库写 PNG（8bit RGB，color type 2）
# ---------------------------------------------------------------------------
def _png_chunk(tag: bytes, data: bytes) -> bytes:
    return (struct.pack('>I', len(data)) + tag + data +
            struct.pack('>I', zlib.crc32(tag + data) & 0xFFFFFFFF))


def write_png(path: str, rgb: bytes, scale: int = 1) -> None:
    w, h = W * scale, H * scale
    rows = []
    for y in range(H):
        base = y * W * 3
        if scale == 1:
            rows.append(b'\x00' + rgb[base:base + W * 3])
        else:
            line = bytearray()
            for x in range(W):
                p = rgb[base + x * 3: base + x * 3 + 3]
                line += p * scale
            line = b'\x00' + bytes(line)
            rows.extend([line] * scale)
    raw = b''.join(rows)
    png = b'\x89PNG\r\n\x1a\n'
    png += _png_chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
    png += _png_chunk(b'IDAT', zlib.compress(raw, 9))
    png += _png_chunk(b'IEND', b'')
    with open(path, 'wb') as f:
        f.write(png)


# ---------------------------------------------------------------------------
def recv_one_frame(sock: socket.socket, verbose: bool = True):
    """收满 20 个包返回拼好的 27648 字节；超时/乱序失败返回 None"""
    frame = [None] * NPKT
    got = 0
    dup = 0
    t0 = time.time()
    while got < NPKT:
        try:
            data, addr = sock.recvfrom(4096)
        except socket.timeout:
            if verbose:
                print('  [超时] 只收到 %d/%d 包就断了' % (got, NPKT))
            return None
        if len(data) < 2:
            continue
        seq = (data[0] << 8) | data[1]
        if not (0 <= seq < NPKT):
            if verbose:
                print('  [忽略] 序号越界 %d' % seq)
            continue
        exp = PAY_LAST if seq == NPKT - 1 else PAY_FULL
        img = data[2:]
        if len(img) != exp:
            if verbose:
                print('  [丢弃] pkt %2d 载荷 %d 字节，期望 %d（协议不符）'
                      % (seq, len(img), exp))
            continue
        if frame[seq] is not None:
            dup += 1
            continue
        frame[seq] = img
        got += 1
        if verbose:
            print('  pkt %2d  from %-15s : %4d 字节   (%2d/%d)'
                  % (seq, addr[0], len(img), got, NPKT))

    dt = time.time() - t0
    if verbose:
        print('  收齐 20 包，用时 %.1f ms（重复包 %d 个）' % (dt * 1000, dup))
    # 按序号拼装
    out = bytearray()
    for i in range(NPKT):
        out += frame[i]
    return bytes(out)


def stats(rgb: bytes) -> str:
    n = W * H
    sr = sg = sb = 0
    for i in range(0, len(rgb), 3):
        sr += rgb[i]
        sg += rgb[i + 1]
        sb += rgb[i + 2]
    return '均值 R=%6.1f G=%6.1f B=%6.1f   （和 HDMI 上的画面比一下色调应一致）' \
           % (sr / n, sg / n, sb / n)


def main() -> int:
    ap = argparse.ArgumentParser(description='板 A 发图验收：收 20 包拼 128x72 PNG')
    ap.add_argument('--bind', default='192.168.240.2',
                    help='本地绑定 IP（板 A 固定发给 .2，默认 192.168.240.2）')
    ap.add_argument('--port', type=int, default=6666, help='本地端口，默认 6666')
    ap.add_argument('--count', type=int, default=1, help='收几帧，默认 1')
    ap.add_argument('--scale', type=int, default=4,
                    help='PNG 放大倍数（默认 4，便于肉眼观察）')
    ap.add_argument('--outdir', default='.', help='输出目录')
    ap.add_argument('--timeout', type=float, default=10.0,
                    help='等第一个包的超时秒数，默认 10')
    a = ap.parse_args()

    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind((a.bind, a.port))
    except OSError as e:
        print('绑定 %s:%d 失败：%s' % (a.bind, a.port, e))
        print('  * 地址被占用？先关掉正在监听 6666 的程序')
        print('  * 本机没有 %s 这个 IP？先把网卡设成它（板 A 固定发到 .2）' % a.bind)
        return 2

    sock.settimeout(a.timeout)
    print('=' * 66)
    print(' 监听 %s:%d ，等板 A 发图（板 A 每 6 帧发 1 帧，约 0.1 秒一帧）'
          % (a.bind, a.port))
    print('=' * 66)

    os.makedirs(a.outdir, exist_ok=True)
    ok = 0
    for k in range(1, a.count + 1):
        print('--- 第 %d/%d 帧 ---' % (k, a.count))
        rgb = recv_one_frame(sock)
        if rgb is None:
            continue
        if len(rgb) != IMG_BYTES:
            print('  拼装长度 %d != %d，异常' % (len(rgb), IMG_BYTES))
            continue
        name = os.path.join(a.outdir, 'frame_%03d.png' % k)
        write_png(name, rgb, a.scale)
        print('  ✓ 已存 %s  (%dx%d, 放大 %d 倍)' % (name, W, H, a.scale))
        print('  ' + stats(rgb))
        ok += 1
        # 清掉积压的旧包，让下一帧从干净状态开始
        sock.settimeout(0.05)
        try:
            while True:
                sock.recvfrom(4096)
        except socket.timeout:
            pass
        sock.settimeout(a.timeout)

    print('=' * 66)
    print(' 完成：成功 %d / %d 帧' % (ok, a.count))
    print('=' * 66)
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
