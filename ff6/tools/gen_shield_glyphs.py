#!/usr/bin/env python3
# ------------------------------------------------------------------------------
# gen_shield_glyphs.py -- the HUD's per-monster shield tiles
#
# Writes ff6/src/battle/ot6_shield_glyphs.inc: Ot6ShieldGlyphs, 100 2bpp 8x8
# tiles.  Tile n-1 (n = 1..99) is the shield count n; tile 99 (n = 100) is
# the broken shield.  The HUD uploads the tile a monster needs into that
# monster slot's own font cell (ot6_hud.asm, #292), so every count draws true.
#
# The shield gauge is two cells under the monster (#397): a fixed shield
# emblem (Ot6BgGlyphData in ot6_hud.asm) and, right of it, this count tile.
# Both draw in battle text palette 0 (1 = black, 2 = grey, 3 = white), plain
# white like the party's HP numerals.  No weakness icon is drawn in a hue
# there: the gauge used to be gold on navy (palette 2), the yellow the
# lightning and holy icons are drawn in, so a revealed bolt beside the count
# read as a smear of the count (owner, 2026-11-14).
#
# Counts 1-9: the battle font's own numeral (SmallFontGfx $b4-$bd, the bold
# 2-pixel strokes the party's HP is drawn in, with its own black shadow).
# Counts 10-99: two 3x7 numerals, white with a black shadow right and below,
# the only way two digits fit eight pixels.
#
# The broken tile takes the emblem's place while a monster is broken (the
# count cell is then empty): the #397 emblem cracked down the middle, its
# right half dropped a row, in text palette 7 (grey outline and body, red
# rim).

# Colors: plane 0 = bit 0, plane 1 = bit 1; each row is stored plane 0 then
# plane 1.
#
#   python3 ff6/tools/gen_shield_glyphs.py          # rewrite the .inc
#   python3 ff6/tools/gen_shield_glyphs.py --check  # exit 1 if it is stale
#
# stdlib only.
# ------------------------------------------------------------------------------

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "src", "battle", "ot6_shield_glyphs.inc")
FONT = os.path.join(HERE, "..", "src", "gfx", "small_font_en.2bpp")
FONT_ZERO = 0xb4                # SmallFontGfx's '0'; '1'..'9' follow

# 3x7 numerals for the two-digit counts
NARROW = {
    0: ["XXX", "X.X", "X.X", "X.X", "X.X", "X.X", "XXX"],
    1: [".X.", "XX.", ".X.", ".X.", ".X.", ".X.", "XXX"],
    2: ["XXX", "..X", "..X", "XXX", "X..", "X..", "XXX"],
    3: ["XXX", "..X", "..X", ".XX", "..X", "..X", "XXX"],
    4: ["X.X", "X.X", "X.X", "XXX", "..X", "..X", "..X"],
    5: ["XXX", "X..", "X..", "XXX", "..X", "..X", "XXX"],
    6: ["XXX", "X..", "X..", "XXX", "X.X", "X.X", "XXX"],
    7: ["XXX", "..X", "..X", ".X.", ".X.", ".X.", ".X."],
    8: ["XXX", "X.X", "X.X", "XXX", "X.X", "X.X", "XXX"],
    9: ["XXX", "X.X", "X.X", "XXX", "..X", "..X", "XXX"],
}

# the shield gauge's emblem (cell $71, ot6_hud.asm's Ot6BgGlyphData takes it
# from the OT6_EMBLEM_TILE this file defines): a plain white shield with a
# black outline in palette 0
EMBLEM = [
    "13333331",
    "13333331",
    "13333331",
    "13333331",
    "01333310",
    "00133100",
    "00011000",
    "00000000",
]

# the #397 emblem (grey body, rim, outline), which the broken tile cracks;
# drawn in palette 7 it is the grey shield with a red rim
BROKEN_BASE = [
    "13333331",
    "13222231",
    "13222231",
    "13222231",
    "01322310",
    "00132100",
    "00011000",
    "00000000",
]


def broken_rows():
    """The #397 emblem cracked: a zigzag gap down the middle and the right
    half dropped a row.  Drawn in palette 7 (grey outline and body, red
    rim)."""
    out = [["0"] * 8 for _ in range(8)]
    for r in range(8):
        for c in range(4):
            out[r][c] = BROKEN_BASE[r][c]
        for c in range(4, 8):
            if r + 1 < 8:
                out[r + 1][c] = BROKEN_BASE[r][c]
    for r in range(8):
        out[r][3 if r % 2 else 4] = "0"
    return ["".join(r) for r in out]


def font_digit(d):
    data = open(FONT, "rb").read()
    t = data[(FONT_ZERO + d) * 16:(FONT_ZERO + d) * 16 + 16]
    rows = []
    for r in range(8):
        p0, p1 = t[2 * r], t[2 * r + 1]
        rows.append("".join(str(((p0 >> (7 - c)) & 1) | (((p1 >> (7 - c)) & 1) << 1))
                            for c in range(8)))
    return rows


def count_rows(n):
    if n < 10:
        # the font numeral as it is: white stroke, black shadow
        return font_digit(n)
    g = [["0"] * 8 for _ in range(8)]
    for d, col in ((n // 10, 0), (n % 10, 4)):
        for r, pat in enumerate(NARROW[d]):
            for c, ch in enumerate(pat):
                if ch == "X":
                    g[r][col + c] = "3"
    # the shadow, as the font draws it: right of and below each stroke pixel
    for r in range(8):
        for c in range(8):
            if g[r][c] == "3":
                for dr, dc in ((0, 1), (1, 0), (1, 1)):
                    rr, cc = r + dr, c + dc
                    if rr < 8 and cc < 8 and g[rr][cc] == "0":
                        g[rr][cc] = "1"
    return ["".join(r) for r in g]


def encode(rows):
    out = []
    for row in rows:
        p0 = p1 = 0
        for c, ch in enumerate(row):
            v = 0 if ch == "." else int(ch)
            p0 |= (v & 1) << (7 - c)
            p1 |= ((v >> 1) & 1) << (7 - c)
        out += [p0, p1]
    return bytes(out)


def tile(n):
    if n == 100:
        return encode(broken_rows())
    return encode(count_rows(n))


def render():
    for n in range(1, 101):
        assert len(tile(n)) == 16
    lines = [
        "; generated by ff6/tools/gen_shield_glyphs.py; do not edit by hand.",
        "; Ot6ShieldGlyphs: tile n-1 is the HUD count tile for n = 1..99, and",
        "; tile 99 (n = 100) is the broken shield (2bpp, 16 bytes a tile).",
        "; OT6_EMBLEM_TILE: the gauge's emblem, for Ot6BgGlyphData.",
        "",
        ".define OT6_EMBLEM_TILE " + ",".join("$%02x" % x for x in encode(EMBLEM)),
        "",
        "Ot6ShieldGlyphs:",
    ]
    for n in range(1, 101):
        b = tile(n)
        lines.append("; %s" % ("broken" if n == 100 else n))
        for k in (0, 8):
            lines.append("        .byte   " + ",".join("$%02x" % x for x in b[k:k + 8]))
    return "\n".join(lines) + "\n"


def main():
    text = render()
    if "--check" in sys.argv[1:]:
        cur = open(OUT).read() if os.path.exists(OUT) else ""
        if cur != text:
            print("ot6_shield_glyphs.inc is stale: python3 ff6/tools/gen_shield_glyphs.py")
            return 1
        print("ot6_shield_glyphs.inc is current")
        return 0
    with open(OUT, "w") as f:
        f.write(text)
    print("wrote %s (100 tiles)" % os.path.relpath(OUT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
