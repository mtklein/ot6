#!/usr/bin/env python3
"""dlg_fit.py [ID ...] -- how a field dialog's pages wrap, without an emulator.

The field's dialog window wraps by word (ff6/src/field/text.asm): the pen
starts at x = 4, and before a word is drawn its width (CalcTextWidth: the
letters up to the next space, from FontWidth, ff6/src/gfx/font_gfx.asm) is
added to the pen; if the sum reaches $E0 (224) the word starts a new line.  A
page shows four lines; a fifth makes the window wait for a key mid-page, which
tools/tests/school.lua counts as a page too many.

Prints each page of each dialog id (hex, as $0264 or 0264; default: the Narshe
school's) as its lines with their pixel widths, and exits 1 if any page runs
past four lines.  --text "..." measures a draft instead of an id.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCHOOL = [0x0257, 0x025D, 0x0267, 0x0264, 0x026D, 0x0270, 0x026E, 0x026F, 0x0274, 0x0276]
LIMIT, START, LINES = 0xE0, 4, 4


def widths():
    src = (ROOT / "ff6/src/gfx/font_gfx.asm").read_text()
    blk = src[src.index("FontWidth:"):].split(".else")[0]
    w = [int(x) for line in re.findall(r"\.byte\s+(.*)", blk) for x in line.split(",")]
    table = json.loads((ROOT / "ff6/tools/char_table/dialog_en.json").read_text())
    out = {}
    for code, ch in table.items():
        for c in (ch if isinstance(ch, list) else [ch]):
            out[c] = w[int(code, 16)]
    return out


def tokens(text):
    """a page's text as characters, the char table's multi-letter names ({fire}, `` and '') kept whole"""
    return re.findall(r"\{[^}]*\}|``|''|.", text)


def wrap(page, w):
    """[(line text, pixel width)] for one page"""
    lines, cur, x = [], "", START
    for part in page.split("{n}"):
        words = part.split(" ")
        for i, word in enumerate(words):
            ww = 0
            for t in tokens(word):
                if t not in w:
                    raise SystemExit("dlg_fit: no width for %r" % t)
                ww += w[t]
            if x + ww >= LIMIT and cur:
                lines.append((cur.rstrip(), x))
                cur, x = "", START
            cur, x = cur + word, x + ww
            if i + 1 < len(words):
                cur, x = cur + " ", x + w[" "]
        lines.append((cur.rstrip(), x))
        cur, x = "", START
    return lines


def show(label, text, w):
    bad = 0
    for n, page in enumerate(text.split("{page}"), 1):
        lines = wrap(page, w)
        over = len(lines) > LINES
        bad += over
        print("%s page %d: %d line(s)%s" % (label, n, len(lines), "  ** OVER FOUR **" if over else ""))
        for line, x in lines:
            print("    %3d  %s" % (x, line))
    return bad


def main():
    w = widths()
    args = sys.argv[1:]
    if args and args[0] == "--text":
        return 1 if show("draft", args[1], w) else 0
    texts = json.loads((ROOT / "ff6/src/text/dlg1_en.json").read_text())["text"]
    ids = [int(a.lstrip("$"), 16) for a in args] or SCHOOL
    bad = 0
    for i in ids:
        bad += show("$%04X" % i, texts[i], w)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
