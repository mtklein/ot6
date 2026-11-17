#!/usr/bin/env python3
"""#552: Leo's grave scene against the build (docs/design/leo-reveal.md).

  * the dialogue: OT6_LEO_DLG (the event module's index, from ff6-en.dbg)
    names the scene's 17 entries in ff6/src/text/dlg1_en.json, in order --
    Gogo's line, Leo's, his two speeches and the thirteen reactions -- each
    checked by its opening text, so dialogue appended or removed elsewhere
    cannot shift them unnoticed;
  * every line fits the dialogue box (WIDTH pixels, measured from the
    built ROM's FontWidth): a name token is measured as the widest name a
    player can give (six of the font's widest letter), except `{gogo}` after
    the scene's first line, which is LEO by then;
  * the switch: every OT6_LEO_SWITCH the build assembled (code_ext.inc's
    and the event module's) is one value, and OT6_LEO_FLAG / OT6_LEO_BIT
    are its byte and bit.

Usage: python3 tools/check_leo_reveal.py [--selftest]
"""
import json
import re
import sys

ROM = "build/ot6.sfc"
DBG = "ff6/rom/ff6-en.dbg"
DLG = "ff6/src/text/dlg1_en.json"
CHARS = "ff6/tools/char_table/dialog_en.json"
WIDTH = 218          # the widest line measured to fit the box (a 230-px line wraps)
NAME_LEN = 6
# the scene's entries in order, by the text each opens with
OPENINGS = [
    "{gogo}: You know,", "{gogo}: I've been watching you.", "{gogo}: Kefka's blade", "{gogo}: The world I swore",
    "{celes}:", "{terra}:", "{locke}:", "{edgar}:", "{sabin}:", "{cyan}:", "{shadow}:", "{strago}:", "{relm}:",
    "{setzer}:", "{mog}:", "{gau}:", "{umaro}:",
]


def syms(dbg_text, name):
    return [int(m.group(1), 16) for m in
            re.finditer(r'\bname="%s",[^\n]*\bval=0x([0-9A-Fa-f]+)' % re.escape(name), dbg_text)]


def widths(rom, dbg_text):
    fw = syms(dbg_text, "FontWidth")[0] & 0x3FFFFF
    table = rom[fw:fw + 128]
    chars = {}
    for k, v in json.load(open(CHARS)).items():
        for ch in (v if isinstance(v, list) else [v]):
            if len(ch) == 1 and int(k, 16) < 128:
                chars.setdefault(ch, int(k, 16))
    return table, chars


def line_width(line, table, chars, gogo):
    widest = max(table[c] for ch, c in chars.items() if ch.isalnum())
    total = 0
    for tok in re.split(r"(\{[a-z]+(?::\d+)?\})", line):
        if not tok:
            continue
        m = re.match(r"^\{([a-z]+)", tok)
        if m:
            if m.group(1) == "gogo" and gogo is not None:
                total += sum(table[chars[c]] for c in gogo)
            elif m.group(1) in ("key", "wait", "page", "n"):
                pass
            else:
                total += NAME_LEN * widest
            continue
        for ch in tok.replace("_", "…"):
            if ch not in chars:
                raise SystemExit("check_leo_reveal: %r has no dialogue code" % ch)
            total += table[chars[ch]]
    return total


def check(rom, dbg_text, texts):
    problems = []
    idx = syms(dbg_text, "OT6_LEO_DLG")
    if len(set(idx)) != 1:
        return ["OT6_LEO_DLG: %s in %s, want exactly one value" % (idx, DBG)]
    base = idx[0]
    table, chars = widths(rom, dbg_text)
    for k, want in enumerate(OPENINGS):
        i = base + k
        if i >= len(texts):
            problems.append("entry $%04X (OT6_LEO_DLG+%d) is past the dialogue's end" % (i, k))
            continue
        if not texts[i].startswith(want):
            problems.append("entry $%04X (OT6_LEO_DLG+%d) opens %r, want %r" % (i, k, texts[i][:30], want))
        for line in texts[i].split("{n}"):
            wpx = line_width(line, table, chars, None if k == 0 else "LEO")
            if wpx > WIDTH:
                problems.append("entry $%04X line %r is %d px with the widest names, past %d" % (i, line, wpx, WIDTH))
    sw = set(syms(dbg_text, "OT6_LEO_SWITCH"))
    if len(sw) != 1:
        problems.append("OT6_LEO_SWITCH has values %s (code_ext.inc's and the event module's must agree)"
                        % sorted("$%04X" % v for v in sw))
    else:
        s = sw.pop()
        flag, bit = syms(dbg_text, "OT6_LEO_FLAG"), syms(dbg_text, "OT6_LEO_BIT")
        if not flag or (flag[0] & 0xFFFF) != 0x1E80 + (s >> 3):
            problems.append("OT6_LEO_FLAG %s is not switch $%04X's byte" % (flag, s))
        if not bit or bit[0] != 1 << (s & 7):
            problems.append("OT6_LEO_BIT %s is not switch $%04X's bit" % (bit, s))
    return problems


def selftest():
    rom = open(ROM, "rb").read()
    dbg_text = open(DBG, encoding="utf-8").read()
    texts = json.load(open(DLG))["text"]
    assert check(rom, dbg_text, texts) == [], check(rom, dbg_text, texts)
    shifted = texts[:0x0C0C] + ["x"] + texts[0x0C0C:]
    assert any("opens" in p for p in check(rom, dbg_text, shifted))
    wide = list(texts)
    base = syms(dbg_text, "OT6_LEO_DLG")[0]
    wide[base] = "{gogo}: You know, this grave is{n}empty."
    assert any("px with the widest names" in p for p in check(rom, dbg_text, wide))
    two = dbg_text + 'sym\tname="OT6_LEO_SWITCH",val=0xE1,type=equ\n'
    assert any("must agree" in p for p in check(rom, dbg_text and two, texts))
    print("check_leo_reveal selftest OK")


def main():
    if "--selftest" in sys.argv:
        selftest()
        return 0
    rom = open(ROM, "rb").read()
    dbg_text = open(DBG, encoding="utf-8").read()
    texts = json.load(open(DLG))["text"]
    problems = check(rom, dbg_text, texts)
    for p in problems:
        print("check_leo_reveal: " + p)
    if problems:
        return 1
    print("check_leo_reveal OK: the scene's 17 entries from $%04X open as they should and fit %d px with the "
          "widest names; OT6_LEO_SWITCH agrees" % (syms(dbg_text, "OT6_LEO_DLG")[0], WIDTH))
    return 0


if __name__ == "__main__":
    sys.exit(main())
