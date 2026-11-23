#!/usr/bin/env python3
"""glyph_sheet.py OUT.png [cell ...] -- small-font cells drawn large, to judge
how the HUD's class icons read apart.  Default cells: the six class glyphs in
Ot6ClassGlyphTbl's order (sword $d9, dagger $d8, fist $e1, arcane $df,
katana $db, spear $da), at 1x, 2x (a 240p screen on a modern display) and 8x.
stdlib only.
"""
import struct
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SHADE = {0: (16, 16, 48), 1: (60, 60, 70), 2: (170, 170, 180), 3: (255, 255, 255)}


def tile(font, i):
    t = font[i * 16:i * 16 + 16]
    return [[((t[2 * r] >> (7 - c)) & 1) | (((t[2 * r + 1] >> (7 - c)) & 1) << 1) for c in range(8)] for r in range(8)]


def main():
    out = sys.argv[1]
    cells = [int(a, 16) for a in sys.argv[2:]] or [0xd9, 0xd8, 0xe1, 0xdf, 0xdb, 0xda]
    font = (ROOT / "ff6/src/gfx/small_font_en.2bpp").read_bytes()
    tiles = [tile(font, c) for c in cells]
    w = len(cells) * 80 + 16
    h = 16 + 8 + 16 + 16 + 16 + 64 + 16
    img = [[SHADE[0]] * w for _ in range(h)]

    def blit(t, x0, y0, s):
        for r in range(8):
            for c in range(8):
                for dy in range(s):
                    for dx in range(s):
                        img[y0 + r * s + dy][x0 + c * s + dx] = SHADE[t[r][c]]
    for k, t in enumerate(tiles):
        blit(t, 16 + k * 10, 16, 1)              # 1x, side by side as on the HUD
        blit(t, 16 + k * 20, 40, 2)              # 2x
        blit(t, 16 + k * 80, 72, 8)              # 8x
    raw = b"".join(b"\x00" + b"".join(bytes(p) for p in row) for row in img)

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) \
        + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")
    Path(out).write_bytes(png)


if __name__ == "__main__":
    main()
