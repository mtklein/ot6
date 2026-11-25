"""Build gate (#561, wt/v052-tg-wob3): every monster dialogue line reads back from the built ROM as the json writes it.

The English monster dialogue (MonsterDlg) and its pointer table (MonsterDlgPtrs) moved out of monster_text
into their own segment, monster_dlg, in the bank-$cf fill ai_script left (ff6-en.cfg, text_main.asm).  The
one reader is btlgfx's GfxCmd_10 (the AI's `dlg`): it takes the bank byte from ^MonsterDlg and the line's
address from the table, `lda f:MonsterDlgPtrs,x` with x = 2 * id.  This reads the built ROM the same way: for
each of the 256 ids, the table's word in the bank MonsterDlg names must hold the json's line, encoded by the
build's own codec (ff6/tools/romtools), through its end byte; the table must point inside the segment, and the
segment must not run past monster_text (cf/c050).

    python3 tools/check_monster_dlg.py [--rom R] [--dbg D]   check
    python3 tools/check_monster_dlg.py --selftest            three mutants, each red: a pointer off by one, a
        line's byte changed, the table read from vanilla's old address (cf/dfe0)
"""
import argparse
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "ff6", "tools"))
from romtools.text_codec import TextCodec  # noqa: E402

JSON = os.path.join(ROOT, "ff6", "src", "text", "monster_dlg_en.json")
MONSTER_TEXT = 0xC050        # monster_text's pinned offset in bank $cf: the dialogue must end below it


def sym(dbg, name):
    pat = re.compile(r'^sym\t.*name="%s".*val=0x([0-9A-F]+),' % re.escape(name))
    with open(dbg, encoding="latin-1") as f:
        for line in f:
            m = pat.match(line)
            if m:
                return int(m.group(1), 16)
    raise SystemExit("check_monster_dlg: %s not in %s" % (name, dbg))


_LINES = []


def lines():
    """the json's lines, each encoded alone by the build's codec (end byte included)"""
    if _LINES:
        return _LINES
    asset = json.load(open(JSON, encoding="utf8"))
    here = os.getcwd()
    os.chdir(os.path.join(ROOT, "ff6"))          # (the codec's char tables are paths from ff6/)
    try:
        codec = TextCodec(asset)     # (the codec alone: encode_text would also rewrite the .inc)
        for t in asset["text"]:
            _LINES.append((t, bytes(codec.encode(t))))
    finally:
        os.chdir(here)
    return _LINES


def check(rom, ptrs, dlg):
    """the problems (empty when every line reads back), reading the table at SNES `ptrs`, the text in `dlg`'s bank"""
    bad = []
    bank = (dlg >> 16) & 0x3F
    pt = (ptrs & 0x3FFFFF) if ptrs >= 0xC00000 else ptrs
    want = lines()
    if len(want) != 256:
        bad.append("the json holds %d lines, want 256" % len(want))
    for i, (t, b) in enumerate(want):
        lo = rom[pt + 2 * i] | (rom[pt + 2 * i + 1] << 8)
        if lo < (dlg & 0xFFFF) or lo + len(b) > MONSTER_TEXT:
            bad.append("line $%02X: the table points at $%04X, outside the dialogue block ($%04X-$%04X)"
                       % (i, lo, dlg & 0xFFFF, MONSTER_TEXT))
            continue
        at = bank * 0x10000 + lo
        got = bytes(rom[at:at + len(b)])
        if got != b:
            bad.append("line $%02X %r: the ROM at $%02X%04X reads %s, the json encodes %s"
                       % (i, t, 0xC0 | bank, lo, got.hex(), b.hex()))
    return bad


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rom", default="build/ot6.sfc")
    ap.add_argument("--dbg", default="ff6/rom/ff6-en.dbg")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    rom = bytearray(open(a.rom, "rb").read())
    ptrs, dlg = sym(a.dbg, "MonsterDlgPtrs"), sym(a.dbg, "MonsterDlg")
    if a.selftest:
        fails = []
        pt = ptrs & 0x3FFFFF
        m1 = bytearray(rom)
        m1[pt + 2 * 0x94] = (m1[pt + 2 * 0x94] + 1) & 0xFF      # "It inhales!" one byte late
        if not check(m1, ptrs, dlg):
            fails.append("a pointer off by one reads green")
        m2 = bytearray(rom)
        lo = rom[pt + 2 * 0x9C] | (rom[pt + 2 * 0x9C + 1] << 8)
        m2[((dlg >> 16) & 0x3F) * 0x10000 + lo] ^= 0x01         # "Deck groans!"'s first letter
        if not check(m2, ptrs, dlg):
            fails.append("a changed byte reads green")
        if not check(rom, 0xCFDFE0, dlg):                        # vanilla's table address (before the move)
            fails.append("the table read at vanilla's cf/dfe0 reads green")
        if check(rom, ptrs, dlg):
            fails.append("the tree's own ROM is red")
        if fails:
            print("check_monster_dlg selftest: FAIL: " + "; ".join(fails))
            return 1
        print("check_monster_dlg selftest: PASS (a pointer off by one, a changed byte and vanilla's table address "
              "are caught; the tree's ROM reads clean)")
        return 0
    bad = check(rom, ptrs, dlg)
    for p in bad:
        print("check_monster_dlg: " + p)
    if bad:
        return 1
    print("check_monster_dlg: all 256 monster dialogue lines read back from the ROM through MonsterDlgPtrs "
          "($%06X) in MonsterDlg's bank ($%06X, ending below $CF%04X) as the json encodes them"
          % (ptrs, dlg, MONSTER_TEXT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
