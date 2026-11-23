#!/usr/bin/env python3
"""font.py -- the six-class prototype's text and font edits.

  * attack_msg_en.json: the "Weak against ..." lines, one per class
    (Ot6ClassMsgTbl in ot6_break.asm: $45-$48, $4a, $4b).
  * small_font_en.2bpp: the katana glyph ($db) mirrored left to right, so the
    HUD's katana icon points up and to the right where the sword ($d9), the
    dagger ($d8) and the spear ($da) point up and to the left.

Run from the repo root.  Idempotent: the glyph is rebuilt from v0.50's font.
"""
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MSG = {0x45: "Weak against swords", 0x46: "Weak against daggers", 0x47: "Weak against fists",
       0x48: "Weak against arcane", 0x4a: "Weak against katanas", 0x4b: "Weak against spears"}
KATANA = 0xDB


def main():
    p = ROOT / "ff6/src/text/attack_msg_en.json"
    d = json.loads(p.read_text())
    for i, s in MSG.items():
        d["text"][i] = s
    p.write_text(json.dumps(d, indent=2, ensure_ascii=False))

    f = ROOT / "ff6/src/gfx/small_font_en.2bpp"
    old = subprocess.run(["git", "show", "v0.50:ff6/src/gfx/small_font_en.2bpp"], cwd=ROOT, check=True,
                         capture_output=True).stdout
    b = bytearray(old)
    for k in range(16):
        b[KATANA * 16 + k] = int("{:08b}".format(old[KATANA * 16 + k])[::-1], 2)
    f.write_bytes(bytes(b))


if __name__ == "__main__":
    main()
