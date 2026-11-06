#!/usr/bin/env python3
"""Draw the Open NavG launcher icon from code (no image editor, no deps).

Usage: python3 scripts/make_icon.py [size] > resources/drawables/launcher_icon.png
Writes a PNG: dark circle with a white navigation arrow and a green dot.
"""
import math
import struct
import sys
import zlib

SIZE = int(sys.argv[1]) if len(sys.argv) > 1 else 70
SS = 4  # supersampling for smooth edges


def inside_polygon(x, y, pts):
    hit = False
    j = len(pts) - 1
    for i in range(len(pts)):
        xi, yi = pts[i]
        xj, yj = pts[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            hit = not hit
        j = i
    return hit


def color_at(x, y):
    c = SIZE / 2
    r = SIZE / 2 - 0.5
    dx, dy = x - c, y - c
    if dx * dx + dy * dy > r * r:
        return None
    # arrow, rotated 35 degrees to look like "turn right"
    a = math.radians(35)
    s = SIZE * 0.34
    shape = [(0, -1), (0.62, 0.62), (0, 0.28), (-0.62, 0.62)]
    pts = [(c + (px * math.cos(a) - py * math.sin(a)) * s,
            c + (px * math.sin(a) + py * math.cos(a)) * s) for px, py in shape]
    if inside_polygon(x, y, pts):
        return (255, 255, 255)
    gx, gy = c - SIZE * 0.22, c + SIZE * 0.24
    if (x - gx) ** 2 + (y - gy) ** 2 < (SIZE * 0.07) ** 2:
        return (0, 200, 90)
    return (24, 32, 44)


def pixel(x, y):
    acc = [0, 0, 0, 0]
    for sy in range(SS):
        for sx in range(SS):
            col = color_at(x + (sx + 0.5) / SS, y + (sy + 0.5) / SS)
            if col:
                acc[0] += col[0]; acc[1] += col[1]; acc[2] += col[2]; acc[3] += 255
    n = SS * SS
    alpha = acc[3] // n
    if alpha == 0:
        return (0, 0, 0, 0)
    k = acc[3] / 255
    return (int(acc[0] / k), int(acc[1] / k), int(acc[2] / k), alpha)


def png(w, h, rows):
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    raw = b"".join(b"\x00" + bytes(v for p in row for v in p) for row in rows)
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9))
            + chunk(b"IEND", b""))


rows = [[pixel(x, y) for x in range(SIZE)] for y in range(SIZE)]
sys.stdout.buffer.write(png(SIZE, SIZE, rows))
