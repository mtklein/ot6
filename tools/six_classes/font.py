#!/usr/bin/env python3
"""font.py -- the six classes' text and font edits (#566).

  * attack_msg_en.json: the "Weak against ..." lines, one per class
    (Ot6ClassMsgTbl in ot6_break.asm: $45-$48, $4a, $4b).
  * small_font_en.2bpp: the four blade icons each on its own axis, so the
    HUD's weakness icons (8x8, white, side by side) read apart at a glance:
        sword  $d9   vanilla's: a broad blade up and to the left      \\
        katana $db   vanilla's, mirrored: a thin blade up to the right /
        spear  $da   redrawn: upright, a leaf head on a thin shaft     |
        dagger $d8   redrawn: level, the point to the left             -
        blunt  $dc   redrawn: a mallet, a broad head on a short shaft   T
        ranged $de   vanilla's thrown star                              *
    These cells are also the icons the weapons' names wear.

Run from the repo root.  Idempotent: the glyphs are rebuilt from the font at
BASE (origin/main, or $OT6_SPLIT_BASE).
"""
import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = os.environ.get("OT6_SPLIT_BASE", "origin/main")
MSG = {0x45: "Weak against swords", 0x46: "Weak against daggers", 0x47: "Weak against blunt attacks",
       0x48: "Weak against ranged attacks", 0x4a: "Weak against katanas", 0x4b: "Weak against spears"}
KATANA = 0xDB
# ' ' 0 clear, '.' 1 shadow, 'o' 2 grey, '#' 3 white (the text palette's stroke)
ART = {
    0xDA: ["   #    ",          # spear: upright
           "  ###.  ",
           "  ###.  ",
           "   #..  ",
           "   o.   ",
           "   o.   ",
           "   o.   ",
           "   o.   "],
    0xDC: [" #####  ",          # blunt: a mallet
           " #####. ",
           " #####. ",
           "  .o... ",
           "   o.   ",
           "   o.   ",
           "   o.   ",
           "   o.   "],
    0xD8: ["        ",          # dagger: level, point left
           "     #. ",
           "     #. ",
           "######oo",
           " oooo#oo",
           " ....#..",
           "     #. ",
           "      . "],
}


def encode(rows):
    out = bytearray()
    for r in rows:
        assert len(r) == 8, r
        v = [" .o#".index(c) for c in r]
        out.append(sum((x & 1) << (7 - i) for i, x in enumerate(v)))
        out.append(sum((x >> 1) << (7 - i) for i, x in enumerate(v)))
    return bytes(out)


def main():
    p = ROOT / "ff6/src/text/attack_msg_en.json"
    d = json.loads(p.read_text())
    for i, s in MSG.items():
        d["text"][i] = s
    p.write_text(json.dumps(d, indent=2, ensure_ascii=False))

    f = ROOT / "ff6/src/gfx/small_font_en.2bpp"
    old = subprocess.run(["git", "show", BASE + ":ff6/src/gfx/small_font_en.2bpp"], cwd=ROOT, check=True,
                         capture_output=True).stdout
    b = bytearray(old)
    for k in range(16):
        b[KATANA * 16 + k] = int("{:08b}".format(old[KATANA * 16 + k])[::-1], 2)
    for cell, rows in ART.items():
        b[cell * 16:cell * 16 + 16] = encode(rows)
    f.write_bytes(bytes(b))


if __name__ == "__main__":
    main()
