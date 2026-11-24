#!/usr/bin/env python3
"""The field Treasure Hunter, Painter and Rune Knight pages' help lines (#549,
#563): one table, the generated includes, and the build check that the ROM
carries them.

Each page (skills.asm DrawThiefMenu, menu/ot6_painter_page.asm,
menu/ot6_runeknt_page.asm) shows the
help line of the row under the cursor in the help window at the top of the
screen, as the vanilla Skills pages and the esper rank page do: a learned
row says what the move does, a row not learned yet says how it is learned.
The lines are drawn in the menu's variable-width font, as the esper page's
are (tools/esper_ladder.py DESC), so the same width rule holds: the first
line fits DESC_WIDTH pixels.  A second line ({n}) sits under the page's
title box, which covers the help window's second line from its left edge
(x = 8 * the box's first column): the shared seven-tile box at column 22 on
the Painter page and Celes's, Locke's own fifteen-tile box at column 14 on
his, so each page has its own second-line width.

  python3 tools/kit_pages.py --write      write ff6/src/battle/ot6_kitpage_desc.inc
                                          and ot6_runepage_desc.inc
  python3 tools/kit_pages.py              check build/ot6.sfc against the table
  python3 tools/kit_pages.py --selftest   the check on the real ROM plus mutants

The check requires sixteen lines on Locke's page and on Relm's (eight rows
learned, eight locked), none empty, none over two lines, each line within
its width; a locked line for a row learned by level names the level
Ot6PaintRowTbl holds; and the ROM's strings, through its pointer tables, to
be the table's, row for row.

Celes's page lists rows that come and go with what she can cast, so its
lines are indexed by the row's id less $d0 (ot6_rune.asm: Runic, the eight
blade rows in element bit order, Break Blade), and one more follows for
Break Blade not learned yet: eleven.  Her rows are checked against
ot6_rune.asm: the names in Ot6RuneName's order, a blade line naming its own
element, and a boost promised on exactly the OT6_RUNE_LINES elements that
have a spell line to climb.
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
LINE2_WIDTH = {"thief": 94, "paint": 150, "rune": 150}

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
    ("Portrait", "Ally's next boost: 1 free point{n}Refuses a boost", "Learned when Relm joins"),
    ("Tint", "Ally's weapon gets an element{n}4 turns; +1 ally/point", "Learned at level 18"),
    ("Varnish", "The next enemy hit on an ally{n}misses; +1 ally a point", "Learned at level 24"),
    ("Still Life", "A break lasts twice as long{n}Boost: +1 foe a point", "Learned at Owzer's mansion"),
    ("Underpainting", "Next weakness hit: 2 shields{n}Boost: +1 foe a point", "Learned at level 36"),
    ("Gesture", "An ally's turn comes up now{n}Boost: +1 ally a point", "Learned at level 42"),
    ("Masterpiece", "With 3 BP: each other ally{n}gets a free point", "Learned when Strago returns"),
]
# Celes's rows by id from $d0 (ot6_rune.asm): (name, the row's line, locked).
# Only Break Blade is ever shown locked: a blade row is listed when she can
# cast its element and not otherwise, and Runic comes with the command.
RUNE_BOOST, RUNE_NO_BOOST = "Boost it like %s", "Takes no boost"
RUNE = [
    ("Runic", "Absorbs a spell: MP, 1 BP and its{n}element on the blade", None),
    ("Fire", "Hits strike a weakness to fire{n}" + RUNE_BOOST % "Fire", None),
    ("Ice", "Hits strike a weakness to ice{n}" + RUNE_BOOST % "Ice", None),
    ("Bolt", "Hits strike a weakness to bolt{n}" + RUNE_BOOST % "Bolt", None),
    ("Poison", "Hits strike a weakness to poison{n}" + RUNE_BOOST % "Poison", None),
    ("Wind", "Hits strike a weakness to wind{n}" + RUNE_NO_BOOST, None),
    ("Pearl", "Hits strike a weakness to pearl{n}" + RUNE_NO_BOOST, None),
    ("Earth", "Hits strike a weakness to earth{n}" + RUNE_NO_BOOST, None),
    ("Water", "Hits strike a weakness to water{n}" + RUNE_NO_BOOST, None),
    ("Break", "With 3 BP: for 3 turns, hits take{n}a shield, weak or not",
     "Learned on Floating Continent"),
]
PAGES = {"thief": ("Ot6ThiefPageDescPtrs", "Ot6ThiefPageDescStr", THIEF),
         "paint": ("Ot6PaintPageDescPtrs", "Ot6PaintPageDescStr", PAINT),
         "rune": ("Ot6RunePageDescPtrs", "Ot6RunePageDescStr", RUNE)}
ROWS = {"thief": 8, "paint": 8, "rune": 10}
BATTLE = os.path.join(ROOT, "ff6", "src", "battle")
# Celes's lines go in an include of their own, read after ot6_rune.asm, so the
# first file's bytes and every bank-F0 symbol after it stay where they were.
OUTS = [(os.path.join(BATTLE, "ot6_kitpage_desc.inc"), ["thief", "paint"],
         ["; generated by tools/kit_pages.py --write from its THIEF and PAINT tables",
          "; (the field Treasure Hunter and Painter pages' help lines, #549); do not edit.",
          "; Sixteen lines a page: rows 0-7 learned, then rows 0-7 not learned yet."]),
        (os.path.join(BATTLE, "ot6_runepage_desc.inc"), ["rune"],
         ["; generated by tools/kit_pages.py --write from its RUNE table (the field",
          "; Rune Knight page's help lines, #563); do not edit.  Eleven lines: the",
          "; rows' ids $d0-$d9 in order, then Break Blade not learned yet."])]


def paint_levels():
    """Ot6PaintRowTbl's records (ot6_paint.asm): row -> the level that teaches it, or None."""
    src = open(os.path.join(ROOT, "ff6", "src", "battle", "ot6_paint.asm")).read()
    blk = src[src.index("Ot6PaintRowTbl:"):src.index("Ot6PaintCostTbl:")]
    out = []
    for m in re.finditer(r"\.byte\s+OT6_PAINT_\w+,\s*\$\w+,\s*(.+)", blk):
        args = [a.strip() for a in m.group(1).split(";")[0].split(",")]
        out.append(int(args[0]) if len(args) == 2 and args[1] == "0" and args[0] != "0" else None)
    return out


def rune_rows():
    """ot6_rune.asm: Ot6RuneName's names for ids $d0-$d9, and OT6_RUNE_LINES."""
    src = open(os.path.join(BATTLE, "ot6_rune.asm")).read()
    blk = src[src.index("Ot6RuneName:"):src.index("OT6_RUNE_BANLEN")]
    names = [m.group(1).replace("(sword)", "")
             for m in re.finditer(r"^\s+\.byte\s+[^;\n]*;\s*(\S[^\n]*?)\s*$", blk, re.M)]
    return names[0xd0 - 0xc8:], int(re.search(r"^OT6_RUNE_LINES\s*=\s*(\d+)", src, re.M).group(1))


def lines(page, pages=None):
    """The page's strings: each row's own line, then the locked lines there are
    (Locke's page and Relm's: rows 0-7 learned, then rows 0-7 locked)."""
    rows = (pages or PAGES)[page][2]
    return [r[1] for r in rows] + [r[2] for r in rows if r[2] is not None]


def problems(dc, pages=None):
    pages = pages or PAGES
    widths = el.font_widths()
    out = []
    for page, (_, _, rows) in pages.items():
        if len(rows) != ROWS[page]:
            out.append("%s: %d rows, not %d" % (page, len(rows), ROWS[page]))
        for i, row in enumerate(rows):
            for kind, text in (("learned", row[1]), ("locked", row[2])):
                what = "%s row %d (%s) %s" % (page, i, row[0], kind)
                if text is None and page == "rune":
                    continue            # a row that is never shown locked (checked below)
                if text is None or not text.strip():
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
    if "rune" in pages:
        rows = pages["rune"][2]
        names, nlines = rune_rows()
        for i, row in enumerate(rows):
            if i < len(names) and row[0] != names[i]:
                out.append("rune row %d: Ot6RuneName's row $%02x is %r, the table says %r"
                           % (i, 0xd0 + i, names[i], row[0]))
            if (row[2] is not None) != (i == len(rows) - 1):
                out.append("rune row %d (%s): only Break Blade, the last row, has a locked line" % (i, row[0]))
            if 1 <= i <= 8 and row[1]:
                if "to %s{n}" % row[0].lower() not in row[1]:
                    out.append("rune row %d (%s): the blade line does not name its element: %r" % (i, row[0], row[1]))
                want = RUNE_BOOST % row[0] if i <= nlines else RUNE_NO_BOOST
                if not row[1].endswith("{n}" + want):
                    out.append("rune row %d (%s): OT6_RUNE_LINES is %d, so its line ends %r, not %r"
                               % (i, row[0], nlines, want, row[1].split("{n}")[-1]))
    return out


def write():
    dc = el.desc_codec()
    bad = problems(dc)
    if bad:
        raise SystemExit("\n".join(bad))
    for path, pages, header in OUTS:
        out = list(header)
        for page in pages:
            ptrs, strs, _ = PAGES[page]
            texts = lines(page)
            out += ["", ptrs + ":"]
            off = 0
            for t in texts:
                out.append("        .word   $%04x   ; %s" % (off, t))
                off += len(el.desc_bytes(dc, t))
            out.append(strs + ":")
            for t in texts:
                out.append("        .byte   " + ",".join("$%02x" % x for x in el.desc_bytes(dc, t)) + "   ; " + t)
        open(path, "w").write("\n".join(out) + "\n")
        print("wrote", path)


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
        rp = el.rom_off(el.sym(dbg_text, "Ot6RunePageDescPtrs"))
        rom_mutants = [
            ("a Painter line's first letter changes", ts, rom[ts] ^ 0x01, "paint line 0"),
            ("Mug's learned line points at its locked line", tp + 2 * 3, rom[tp + 2 * 11], "thief line 3"),
            ("Break Blade's line points at its locked line", rp + 2 * 9, rom[rp + 2 * 10], "rune line 9"),
            ("the Ice Blade's line points at the Fire Blade's", rp + 2 * 2, rom[rp + 2 * 1], "rune line 2"),
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
            ("the Earth Blade's line promises a boost", edited("rune", 7, 1,
             "Hits strike a weakness to earth{n}" + RUNE_BOOST % "Earth"), "rune row 7 (Earth): OT6_RUNE_LINES is"),
            ("the Ice Blade's line names fire", edited("rune", 2, 1, RUNE[1][1]),
             "rune row 2 (Ice): the blade line does not name its element"),
            ("the Rune Knight's rows leave Ot6RuneName's order",
             {**PAGES, "rune": PAGES["rune"][:2] + ([RUNE[0], RUNE[2], RUNE[1]] + RUNE[3:],)},
             "Ot6RuneName's row $d1 is 'Fire'"),
            ("Runic's second line runs under the title box", edited("rune", 0, 1,
             "Absorbs a spell: MP, 1 BP and its{n}element stays on the blade"),
             "rune row 0 (Runic) learned: line 2 is"),
            ("Break Blade has no locked line", edited("rune", 9, 2, None),
             "only Break Blade, the last row, has a locked line"),
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
    print("kit_pages: OK -- %d help lines, each in the ROM and within the window"
          % sum(len(lines(p)) for p in PAGES))
    return 0


if __name__ == "__main__":
    sys.exit(main())
