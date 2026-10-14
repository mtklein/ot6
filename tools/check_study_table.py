#!/usr/bin/env python3
"""Build gate (#432): Ot6StudyTbl, the species -> lores table Strago's full
boost studies, is exactly what the monsters' AI scripts can cast.

A species belongs in the table when its AI script (the main section or the
counter section, AIScriptPtrs -> AIScript) names a lore, attack ids $8B..$A2
(lore id = attack - $8B), as a plain attack byte or one of an F0 random
pick's three.  Its row is the 3-byte mask of those lores in $1D29's bit
order (lore id n is bit n&7 of byte n>>3).  The table in the built ROM must
list every such species once, ascending, with exactly that mask, and no
other species; it ends with $FFFF.

    python3 tools/check_study_table.py [--rom R] [--dbg D]   check
    python3 tools/check_study_table.py --emit                print the table
    python3 tools/check_study_table.py --selftest            one mutant per rule
"""
import argparse
import re
import sys

NSPECIES = 384
LORE0, NLORES = 0x8B, 24
# AI script opcode lengths (battle_main.asm's AI command table; route_data.py's)
AI_LEN = {0xF0: 4, 0xF1: 2, 0xF2: 4, 0xF3: 3, 0xF4: 4, 0xF5: 4, 0xF6: 4,
          0xF7: 2, 0xF8: 3, 0xF9: 4, 0xFA: 4, 0xFB: 3, 0xFC: 4, 0xFD: 1,
          0xFE: 1, 0xFF: 1}


def symbols(dbg):
    out = {}
    pat = re.compile(r'^sym\t.*name="([^"]+)".*val=0x([0-9A-F]+),seg=\d+,type=lab')
    with open(dbg, encoding="latin-1") as f:
        for line in f:
            m = pat.match(line)
            if m:
                out.setdefault(m.group(1), int(m.group(2), 16) & 0x3FFFFF)
    for s in ("AIScript", "AIScriptPtrs"):
        if s not in out:
            raise SystemExit("check_study_table: %s not in %s" % (s, dbg))
    return out


def lore_mask(rom, sym, sid):
    """the lores species `sid`'s script can cast, as a 24-bit mask"""
    base = sym["AIScript"]
    p = sym["AIScriptPtrs"] + sid * 2
    i = rom[p] | rom[p + 1] << 8
    sec, n, mask = 0, 0, 0
    while sec < 2 and n < 4096:
        op = rom[base + i]
        if op < 0xF0:
            ids = [op]
            step = 1
        else:
            step = AI_LEN[op]
            ids = list(rom[base + i + 1:base + i + 4]) if op == 0xF0 else []
            if op == 0xFF:
                sec += 1
        for a in ids:
            if LORE0 <= a < LORE0 + NLORES:
                mask |= 1 << (a - LORE0)
        i += step
        n += 1
    return mask


def expected(rom, sym):
    return [(s, m) for s in range(NSPECIES) for m in [lore_mask(rom, sym, s)] if m]


def table(rom, sym):
    if "Ot6StudyTbl" not in sym:
        raise SystemExit("check_study_table: Ot6StudyTbl not in the debug file")
    a, rows = sym["Ot6StudyTbl"], []
    while True:
        sid = rom[a] | rom[a + 1] << 8
        if sid == 0xFFFF:
            return rows
        rows.append((sid, rom[a + 2] | rom[a + 3] << 8 | rom[a + 4] << 16))
        a += 5
        if len(rows) > NSPECIES:
            raise SystemExit("check_study_table: Ot6StudyTbl has no $FFFF end")


def check(rom, sym):
    want, got = expected(rom, sym), table(rom, sym)
    errs = []
    if [s for s, _ in got] != sorted(set(s for s, _ in got)):
        errs.append("Ot6StudyTbl is not ascending without repeats")
    w, g = dict(want), dict(got)
    for s in sorted(set(w) | set(g)):
        if w.get(s, 0) != g.get(s, 0):
            errs.append("species $%03X: the script casts lores $%06X, the table says $%06X"
                        % (s, w.get(s, 0), g.get(s, 0)))
    return errs, len(want)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--rom", default="build/ot6.sfc")
    ap.add_argument("--dbg", default="ff6/rom/ff6-en.dbg")
    ap.add_argument("--emit", action="store_true")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    rom = bytearray(open(a.rom, "rb").read())
    sym = symbols(a.dbg)
    if a.emit:
        for s, m in expected(rom, sym):
            print("        .word   $%04x\n        .byte   $%02x, $%02x, $%02x"
                  % (s, m & 0xFF, m >> 8 & 0xFF, m >> 16))
        print("        .word   $ffff")
        return 0
    if a.selftest:
        errs, _ = check(rom, sym)
        if errs:
            raise SystemExit("check_study_table: selftest needs a passing ROM: " + errs[0])
        t = sym["Ot6StudyTbl"]
        for what, edit in (("a mask bit dropped", lambda r: r.__setitem__(t + 2, r[t + 2] ^ 0x01 if r[t + 2] & 1 else r[t + 2] | 0x01)),
                           ("a row's species moved", lambda r: r.__setitem__(t, r[t] ^ 0x01)),
                           ("the last row cut", lambda r: None)):
            m = bytearray(rom)
            if what == "the last row cut":
                rows = table(rom, sym)
                end = t + 5 * (len(rows) - 1)
                m[end], m[end + 1] = 0xFF, 0xFF
            else:
                edit(m)
            errs, _ = check(m, sym)
            if not errs:
                raise SystemExit("check_study_table: selftest mutant passed: " + what)
        print("check_study_table: selftest ok, 3 mutants fail")
        return 0
    errs, n = check(rom, sym)
    if errs:
        for e in errs:
            print("check_study_table: " + e)
        return 1
    print("check_study_table: ok, Ot6StudyTbl holds the %d species whose scripts cast lores, "
          "each with exactly those lores" % n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
