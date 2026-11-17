#!/usr/bin/env python3
"""The field Treasure Hunter and Painter pages' help lines (#549): one table,
the generated include, and the build check that the ROM carries it.

Each page (skills.asm DrawThiefMenu, menu/ot6_painter_page.asm) shows the
help line of the row under the cursor in the help window at the top of the
screen, as the vanilla Skills pages and the esper rank page do: a learned
row says what the move does, a row not learned yet says how it is learned.
The lines are drawn in the menu's variable-width font, as the esper page's
are (tools/esper_ladder.py DESC), so the same width rule holds: the first
line fits DESC_WIDTH pixels.  A second line ({n}) sits under the page's
title box, which covers the help window's second line from its left edge
(x = 8 * the box's first column): the shared seven-tile box at column 22 on
the Painter page, Locke's own fifteen-tile box at column 14 on his, so each
page has its own second-line width.

  python3 tools/kit_pages.py --write      write ff6/src/battle/ot6_kitpage_desc.inc
  python3 tools/kit_pages.py              check build/ot6.sfc against the table
  python3 tools/kit_pages.py --selftest   the check on the real ROM plus mutants

The check requires sixteen lines a page (eight rows learned, eight locked),
none empty, none over two lines, each line within its width; a locked line
for a row learned by level names the level Ot6PaintRowTbl holds; and the
ROM's strings, through its pointer tables, to be the table's, row for row.
"""
from __future__ import annotations

import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import esper_ladder as el  # noqa: E402  the font, the codec, the dbg reader

DESC_WIDTH = el.DESC_WIDTH          # 223: the widest vanilla help line
# the second line runs from the help window's text start (x = 16) to the
# title box's left frame: x = 176 on the Painter page (the shared box), 112 on
# Locke's (his own wide box); a 161-pixel line touched the Painter box's frame
# (build/attempts/wt/v049-painter/help2/shots/painterpage_wor_help_row4.png)
LINE2_WIDTH = {"thief": 94, "paint": 150}

# Rows in each page's order (Ot6ThiefRowTbl, Ot6PaintRowTbl): (learned, locked).
THIEF = [
    ("Steal", "Steals an item; boost: likelier", "Known from the start"),
    ("Filch", "Takes a shield; Locke gains 1 BP", "Known from the start"),
    ("Bestow", "Gives an ally 1 BP, or all pending", "Known from the start"),
    ("Mug", "A Fight that steals on each hit", "Learned escaping South Figaro"),
    ("Trickshot", "A thrown coin; ignores defense", "Learned on the Lete River"),
    ("Dismantle", "Corrodes defense, then stabs", "Learned at the Sealed Gate"),
    ("Appraise", "Reads weaknesses; boost: all", "Learned in Thamasa"),
    ("Master's Mark", "With 3 BP: robs and reads{n}every enemy",
     "Learned on Floating Continent"),
]
PAINT = [
    ("Sketch", "Draws an enemy's attack{n}Can glitch: save first", "Known from the start"),
    ("Portrait", "Ally's next boost: 1 free point{n}A boost buys nothing", "Learned when Relm joins"),
    ("Tint", "Ally's weapon gets an element{n}4 turns; boost: +1 ally", "Learned at level 18"),
    ("Varnish", "The next enemy hit on an ally{n}misses; boost: +1 ally", "Learned at level 24"),
    ("Still Life", "A break lasts twice as long{n}Boost: +1 foe a point", "Learned at Owzer's mansion"),
    ("Underpainting", "Next weakness hit: 2 shields{n}Boost: +1 foe a point", "Learned at level 36"),
    ("Gesture", "An ally's turn comes up now{n}Boost: +1 ally a point", "Learned at level 42"),
    ("Masterpiece", "With 3 BP: each other ally{n}gets a free point", "Learned when Strago returns"),
]
PAGES = {"thief": ("Ot6ThiefPageDescPtrs", "Ot6ThiefPageDescStr", THIEF),
         "paint": ("Ot6PaintPageDescPtrs", "Ot6PaintPageDescStr", PAINT)}
OUT = os.path.join(ROOT, "ff6", "src", "battle", "ot6_kitpage_desc.inc")


def paint_levels():
    """Ot6PaintRowTbl's records (ot6_paint.asm): row -> the level that teaches it, or None."""
    src = open(os.path.join(ROOT, "ff6", "src", "battle", "ot6_paint.asm")).read()
    blk = src[src.index("Ot6PaintRowTbl:"):src.index("Ot6PaintCostTbl:")]
    out = []
    for m in re.finditer(r"\.byte\s+OT6_PAINT_\w+,\s*\$\w+,\s*(.+)", blk):
        args = [a.strip() for a in m.group(1).split(";")[0].split(",")]
        out.append(int(args[0]) if len(args) == 2 and args[1] == "0" and args[0] != "0" else None)
    return out


def lines(page, pages=None):
    """The page's sixteen strings: rows 0-7 learned, then rows 0-7 locked."""
    rows = (pages or PAGES)[page][2]
    return [r[1] for r in rows] + [r[2] for r in rows]


def problems(dc, pages=None):
    pages = pages or PAGES
    widths = el.font_widths()
    out = []
    for page, (_, _, rows) in pages.items():
        if len(rows) != 8:
            out.append("%s: %d rows, not 8" % (page, len(rows)))
        for i, row in enumerate(rows):
            for kind, text in (("learned", row[1]), ("locked", row[2])):
                what = "%s row %d (%s) %s" % (page, i, row[0], kind)
                if not text.strip():
                    out.append("%s: no line" % what)
                    continue
                parts = text.split("{n}")
                if len(parts) > 2:
                    out.append("%s: more than two lines" % what)
                for k, part in enumerate(parts):
                    w = el.desc_width(dc, widths, part)
                    lim = DESC_WIDTH if k == 0 else LINE2_WIDTH[page]
                    if w > lim:
                        out.append("%s: line %d is %d pixels wide, over %d: %r" % (what, k + 1, w, lim, part))
                for b in el.desc_bytes(dc, text)[:-1]:
                    if 0x1c <= b <= 0x1f:
                        out.append("%s: byte $%02x is a LoadBigText control code" % (what, b))
    if "paint" in pages:
        for i, lv in enumerate(paint_levels()):
            if lv is not None and i < len(pages["paint"][2]):
                text = pages["paint"][2][i][2]
                if "level %d" % lv not in text:
                    out.append("paint row %d (%s) locked: Ot6PaintRowTbl teaches it at level %d, the line says %r"
                               % (i, pages["paint"][2][i][0], lv, text))
    return out


def write():
    dc = el.desc_codec()
    bad = problems(dc)
    if bad:
        raise SystemExit("\n".join(bad))
    out = ["; generated by tools/kit_pages.py --write from its THIEF and PAINT tables",
           "; (the field Treasure Hunter and Painter pages' help lines, #549); do not edit.",
           "; Sixteen lines a page: rows 0-7 learned, then rows 0-7 not learned yet."]
    for page, (ptrs, strs, _) in PAGES.items():
        texts = lines(page)
        out += ["", ptrs + ":"]
        off = 0
        for t in texts:
            out.append("        .word   $%04x   ; %s" % (off, t))
            off += len(el.desc_bytes(dc, t))
        out.append(strs + ":")
        for t in texts:
            out.append("        .byte   " + ",".join("$%02x" % x for x in el.desc_bytes(dc, t)) + "   ; " + t)
    open(OUT, "w").write("\n".join(out) + "\n")
    print("wrote", OUT)


def check_rom(rom, dbg_text, dc, pages=None):
    out = problems(dc, pages)
    for page, (ptrs, strs, _) in (pages or PAGES).items():
        tp = el.rom_off(el.sym(dbg_text, ptrs))
        ts = el.rom_off(el.sym(dbg_text, strs))
        for i, t in enumerate(lines(page, pages)):
            off = rom[tp + 2 * i] | (rom[tp + 2 * i + 1] << 8)
            end = rom.index(b"\0", ts + off)
            if list(rom[ts + off:end + 1]) != el.desc_bytes(dc, t):
                out.append("%s line %d: the ROM's help line is not %r" % (page, i, t))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--rom", default=os.path.join(ROOT, "build", "ot6.sfc"))
    ap.add_argument("--dbg", default=os.path.join(ROOT, "ff6", "rom", "ff6-en.dbg"))
    a = ap.parse_args()
    if a.write:
        write()
        return 0
    rom = open(a.rom, "rb").read()
    dbg_text = open(a.dbg).read()
    dc = el.desc_codec()
    bad = check_rom(rom, dbg_text, dc)
    if bad:
        print("\n".join(bad))
        print("kit_pages: FAIL")
        return 1
    if a.selftest:
        miss = 0
        ts = el.rom_off(el.sym(dbg_text, "Ot6PaintPageDescStr"))
        tp = el.rom_off(el.sym(dbg_text, "Ot6ThiefPageDescPtrs"))
        rom_mutants = [
            ("a Painter line's first letter changes", ts, rom[ts] ^ 0x01, "paint line 0"),
            ("Mug's learned line points at its locked line", tp + 2 * 3, rom[tp + 2 * 11], "thief line 3"),
        ]
        for what, off, val, needle in rom_mutants:
            m = bytearray(rom)
            m[off] = val
            got = check_rom(bytes(m), dbg_text, dc)
            ok = any(needle in p for p in got)
            print("mutant %-52s %s" % (what, "red" if ok else "MISSED"))
            miss += not ok

        def edited(page, i, col, text):
            p = {k: (v[0], v[1], [list(r) for r in v[2]]) for k, v in PAGES.items()}
            p[page][2][i][col] = text
            return p
        table_mutants = [
            ("Gesture's line is missing", edited("paint", 6, 1, ""), "paint row 6 (Gesture) learned: no line"),
            ("Tint's locked line names the wrong level", edited("paint", 2, 2, "Learned at level 20"),
             "teaches it at level 18"),
            ("Steal's line runs past the window", edited("thief", 0, 1, THIEF[0][1] + " and rarer"),
             "thief row 0 (Steal) learned: line 1 is"),
            ("a Painter second line runs under the title box", edited("paint", 2, 1,
             "Ally's weapon gets an element{n}for four of the ally's turns"), "line 2 is"),
            ("a line of three", edited("thief", 7, 1, "a{n}b{n}c"), "more than two lines"),
        ]
        for what, p, needle in table_mutants:
            got = problems(dc, p)
            ok = any(needle in x for x in got)
            print("mutant %-52s %s" % (what, "red" if ok else "MISSED"))
            miss += not ok
        if miss:
            print("kit_pages selftest: FAIL")
            return 1
        print("kit_pages selftest: OK")
        return 0
    print("kit_pages: OK -- 32 help lines, each in the ROM and within the window")
    return 0


if __name__ == "__main__":
    sys.exit(main())
