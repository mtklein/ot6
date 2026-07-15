#!/usr/bin/env python3
"""Pixel-exact golden comparison: compare_golden.py <shot.png> <golden.png>
Exit 0 = identical, 1 = differs (prints count), 2 = missing golden."""
import sys, zlib, struct, os

def read_png(p):
    d = open(p, 'rb').read()
    pos, w, h, idat = 8, 0, 0, b''
    while pos < len(d):
        ln = struct.unpack('>I', d[pos:pos+4])[0]
        typ = d[pos+4:pos+8]
        if typ == b'IHDR':
            w, h = struct.unpack('>II', d[pos+8:pos+16])
        elif typ == b'IDAT':
            idat += d[pos+8:pos+8+ln]
        pos += 12 + ln
    raw = zlib.decompress(idat)
    bpp = (len(raw)//h - 1)//w
    rows, prev, i = [], bytearray(w*bpp), 0
    for y in range(h):
        f = raw[i]; i += 1
        line = bytearray(raw[i:i+w*bpp]); i += w*bpp
        if f == 1:
            for x in range(bpp, len(line)): line[x] = (line[x]+line[x-bpp]) & 0xff
        elif f == 2:
            for x in range(len(line)): line[x] = (line[x]+prev[x]) & 0xff
        elif f == 3:
            for x in range(len(line)):
                a = line[x-bpp] if x >= bpp else 0
                line[x] = (line[x]+((a+prev[x])>>1)) & 0xff
        elif f == 4:
            def paeth(a, b, c):
                p = a+b-c
                pa, pb, pc = abs(p-a), abs(p-b), abs(p-c)
                return a if pa <= pb and pa <= pc else (b if pb <= pc else c)
            for x in range(len(line)):
                a = line[x-bpp] if x >= bpp else 0
                c = prev[x-bpp] if x >= bpp else 0
                line[x] = (line[x]+paeth(a, prev[x], c)) & 0xff
        rows.append(bytes(line)); prev = line
    return w, h, bpp, rows

shot, golden = sys.argv[1], sys.argv[2]
tolerance = int(sys.argv[3]) if len(sys.argv) > 3 else 0
if not os.path.exists(golden):
    print(f"NO GOLDEN: {golden} (capture with 'make goldens')")
    sys.exit(2)
w1, h1, b1, r1 = read_png(shot)
w2, h2, b2, r2 = read_png(golden)
if (w1, h1) != (w2, h2):
    print(f"size mismatch: {w1}x{h1} vs {w2}x{h2}")
    sys.exit(1)
diff = sum(1 for y in range(h1) for x in range(w1)
           if r1[y][x*b1:x*b1+3] != r2[y][x*b2:x*b2+3])
if diff > tolerance:
    print(f"DIFFERS: {diff} pixels (tolerance {tolerance}) vs {os.path.basename(golden)}")
    sys.exit(1)
print(f"match: {os.path.basename(golden)} ({diff} px within tolerance)")
