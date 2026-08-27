#!/usr/bin/env python3
"""render_worldmap.py -- the World of Balance overworld, rendered from the
repo's own game data into a PNG for the live viewer's route map.

Read-only over game data.  Sources (all uncompressed in-tree):

  ff6/src/world/world_1_tilemap.dat   256x256 world tiles, one byte each
                                      (index = y*256 + x; world-map-nav.md)
  ff6/src/gfx/world_1_bg.4bpp         WorldGfx1, the blob Decompress lands at
                                      $7E6F50 (world/init.asm:326-344):
                                        +0x0400  tile pixels, 256 tiles x 32
                                                 bytes, 2 px/byte -- the
                                                 stream TfrWorldMapGfx reads
                                                 from $7E7350 (WMADDL=$7350);
                                                 1st px = low nybble
                                        +0x2400  per-tile palette nybbles, the
                                                 $7E9350 table: tile 2k = low
                                                 nybble of byte k, 2k+1 = high
  ff6/src/gfx/world_1_bg.pal          CGRAM colors 0-127  (World1BGPal+0x000,
                                      copied to $7EE000, init.asm:203-213)
  ff6/src/gfx/world_1_sprite.pal      CGRAM colors 128-255 (World1BGPal+0x200
                                      = the next-next incbin, copied to
                                      $7EE100, init.asm:217-227)

Mode 7 color index = (palette nybble << 4) | pixel, exactly TfrWorldMapGfx
(world/tfr_gfx.asm).  Native render is 2048x2048 (8px tiles); each unique
tile is box-filtered once to 4x4 and blitted, so the shipped PNG is
1024x1024.  Pure stdlib (zlib PNG) -- no PIL on this box.
"""
import os
import struct
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TILEMAP = os.path.join(ROOT, "ff6/src/world/world_1_tilemap.dat")
GFX = os.path.join(ROOT, "ff6/src/gfx/world_1_bg.4bpp")
BGPAL = os.path.join(ROOT, "ff6/src/gfx/world_1_bg.pal")
SPRPAL = os.path.join(ROOT, "ff6/src/gfx/world_1_sprite.pal")

PIX_OFF = 0x400    # $7E7350 - $7E6F50
PALTAB_OFF = 0x2400  # $7E9350 - $7E6F50


def load_palette():
    raw = open(BGPAL, "rb").read() + open(SPRPAL, "rb").read()
    pal = []
    for i in range(256):
        c = struct.unpack_from("<H", raw, i * 2)[0]
        r, g, b = c & 31, (c >> 5) & 31, (c >> 10) & 31
        pal.append((r * 255 // 31, g * 255 // 31, b * 255 // 31))
    return pal


def tile_rgb_4x4(gfx, pal, t):
    """One world tile as 16 RGB triples (4x4, box-filtered from 8x8)."""
    pn = gfx[PALTAB_OFF + (t >> 1)]
    pn = (pn & 0x0F) if (t & 1) == 0 else (pn >> 4)
    base = pn << 4
    px = []
    for i in range(32):
        b = gfx[PIX_OFF + t * 32 + i]
        px.append(pal[base | (b & 0x0F)])
        px.append(pal[base | (b >> 4)])
    out = bytearray()
    for y in range(4):
        for x in range(4):
            a = px[(2 * y) * 8 + 2 * x]
            b = px[(2 * y) * 8 + 2 * x + 1]
            c = px[(2 * y + 1) * 8 + 2 * x]
            d = px[(2 * y + 1) * 8 + 2 * x + 1]
            out += bytes(((a[k] + b[k] + c[k] + d[k]) >> 2) for k in range(3))
    return bytes(out)


def write_png(path, w, h, rgb_rows):
    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c))
    raw = b"".join(b"\x00" + r for r in rgb_rows)
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    tmp = path + ".tmp"
    with open(tmp, "wb") as f:
        f.write(png)
    os.replace(tmp, path)


def render(out_path):
    tilemap = open(TILEMAP, "rb").read()
    gfx = open(GFX, "rb").read()
    pal = load_palette()
    tiles = [tile_rgb_4x4(gfx, pal, t) for t in range(256)]
    # blit 4x4 tiles into 1024-wide scanlines
    rows = [bytearray(1024 * 3) for _ in range(1024)]
    for ty in range(256):
        rowbase = tilemap[ty * 256:(ty + 1) * 256]
        for tx in range(256):
            tl = tiles[rowbase[tx]]
            for sy in range(4):
                dst = rows[ty * 4 + sy]
                dst[tx * 12:tx * 12 + 12] = tl[sy * 12:sy * 12 + 12]
    write_png(out_path, 1024, 1024, rows)
    return out_path


def main(out_path=None):
    out = out_path or os.path.join(ROOT, "build/live/wob_map.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    render(out)
    print(f"wrote {out}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else None)
