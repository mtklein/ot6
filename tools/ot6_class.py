#!/usr/bin/env python3
"""ot6_class.py -- the weapon classes, read from the source that defines them.

ff6/src/battle/ot6_class.asm names each break class as one bit of a byte
(`OT6_SWORD := $01` ...), their union (`OT6_CLASSES`), their count
(`OT6_NCLASS`) and the null-break property (`OT6_NULLBRK`).  Every Python
tool that reads a class byte takes the names and bits from here, so a class
added, renamed or renumbered in the source reaches every tool at once, and a
tool cannot hold a private copy that has drifted (v0.51, #566: four tools
carried the four-class literals and two a ROM signature spelled in them).

    import ot6_class
    C = ot6_class.read(root)
    C.bit["sword"], C.token["OT6_SWORD"], C.mask, C.nullbrk
    C.names(0x21) -> "sword|spear"

Also here, because three tools located it three ways: Ot6ShieldTbl, parsed
from the source and found in a ROM by the source's own opening rows.

    python3 tools/ot6_class.py [--repo ROOT] [--selftest]
"""

from __future__ import annotations

import os
import re
import sys

CLASS_ASM = "ff6/src/battle/ot6_class.asm"
HUD_ASM = "ff6/src/battle/ot6_hud.asm"
FLOOR_INC = "ff6/src/battle/ot6_break_floor.inc"
N_SPECIES = 384

_DEF = re.compile(r"^(OT6_[A-Z0-9_]+)\s*:?=\s*([^;]+?)\s*(?:;.*)?$")


class Classes:
    """The class bits of one tree's ot6_class.asm."""

    def __init__(self, consts: dict):
        self.consts = dict(consts)
        for need in ("OT6_CLASSES", "OT6_NULLBRK", "OT6_NCLASS"):
            if need not in consts:
                raise SystemExit("ot6_class: %s defines no %s" % (CLASS_ASM, need))
        self.mask = consts["OT6_CLASSES"]
        self.nullbrk = consts["OT6_NULLBRK"]
        # a class is a one-bit constant inside OT6_CLASSES, in bit order; the
        # kit aliases (OT6_CLS_*) name a class and are not classes themselves
        self.token = {n: v for n, v in sorted(consts.items(), key=lambda kv: kv[1])
                      if v and v & (v - 1) == 0 and v & self.mask
                      and not n.startswith("OT6_CLS_")
                      and n not in ("OT6_CLASSES", "OT6_NULLBRK", "OT6_NCLASS")}
        self.bit = {n[4:].lower(): v for n, v in self.token.items()}
        self.name = {v: n for n, v in self.bit.items()}
        if len(self.token) != consts["OT6_NCLASS"]:
            raise SystemExit("ot6_class: %s names %d class bits (%s) but OT6_NCLASS = %d"
                             % (CLASS_ASM, len(self.token), ", ".join(self.token), consts["OT6_NCLASS"]))
        union = 0
        for v in self.token.values():
            union |= v
        if union != self.mask:
            raise SystemExit("ot6_class: the class bits make $%02x, OT6_CLASSES is $%02x"
                             % (union, self.mask))
        if self.nullbrk & self.mask:
            raise SystemExit("ot6_class: OT6_NULLBRK $%02x overlaps OT6_CLASSES $%02x"
                             % (self.nullbrk, self.mask))

    def names(self, mask: int, none: str = "(none)", sep: str = "|") -> str:
        """'sword|spear' for a class mask, in bit order."""
        return sep.join(n for n, b in self.bit.items() if mask & b) or none

    def value(self, expr: str, where: str = "") -> int:
        """A class byte as the source spells it: tokens and literals or'd."""
        v = 0
        for tok in expr.split("|"):
            tok = tok.strip()
            if tok in self.consts:
                v |= self.consts[tok]
            elif re.fullmatch(r"\$[0-9a-fA-F]+", tok):
                v |= int(tok[1:], 16)
            elif re.fullmatch(r"[0-9]+", tok):
                v |= int(tok)
            else:
                raise SystemExit("ot6_class: unknown class token %r%s"
                                 % (tok, (" at " + where) if where else ""))
        return v


def parse_consts(text: str) -> dict:
    """Every `OT6_NAME := value` / `= value` of ot6_class.asm, values being
    literals or earlier names or'd together."""
    out = {}
    for line in text.splitlines():
        m = _DEF.match(line.strip())
        if not m:
            continue
        v, ok = 0, True
        for tok in m.group(2).split("|"):
            tok = tok.strip()
            if re.fullmatch(r"\$[0-9a-fA-F]+", tok):
                v |= int(tok[1:], 16)
            elif re.fullmatch(r"[0-9]+", tok):
                v |= int(tok)
            elif tok in out:
                v |= out[tok]
            else:
                ok = False
        if ok:
            out[m.group(1)] = v
    return out


def read(root: str) -> Classes:
    with open(os.path.join(root, CLASS_ASM), encoding="utf-8") as f:
        return Classes(parse_consts(f.read()))


# ------------------------------------------------------------ Ot6ShieldTbl --

def shield_rows(text: str, C: Classes, label: str = "Ot6ShieldTbl"):
    """[(species, shields, class byte, line, comment)] of a
    `.word species / .byte shields, classes` table, in source order, up to
    the $ffff terminator.  Duplicates are kept: the caller decides."""
    lines = text.splitlines()
    try:
        start = next(i for i, l in enumerate(lines) if l.strip().startswith(label + ":"))
    except StopIteration:
        raise SystemExit("ot6_class: no %s: in the source" % label)
    rows, pending, pending_line = [], None, None
    for i in range(start + 1, len(lines)):
        code, _, comment = lines[i].partition(";")
        m = re.match(r"\s*\.word\s+\$([0-9a-fA-F]{4})\s*$", code)
        if m:
            v = int(m.group(1), 16)
            if v == 0xFFFF:
                break
            pending, pending_line = v, i + 1
            continue
        m = re.match(r"\s*\.byte\s+([^,]+),\s*(.+?)\s*$", code)
        if m and pending is not None:
            rows.append((pending, int(m.group(1).strip(), 0),
                         C.value(m.group(2), "%s:%d" % (HUD_ASM, i + 1)),
                         pending_line, comment.strip()))
            pending, pending_line = None, None
    return rows


def rom_table_at(rom: bytes, source_rows, what: str = "Ot6ShieldTbl", lead: int = 4):
    """The offset of the table in a ROM, found by the source's own opening
    rows (species word, shields, class byte; `lead` of them), which must
    occur exactly once.  No class value is spelled here, so the search
    follows the source through any re-split of the classes."""
    key = b"".join(bytes([sp & 0xFF, sp >> 8, sh, cl]) for sp, sh, cl in
                   [r[:3] for r in source_rows[:lead]])
    if len(key) < 8:
        raise SystemExit("ot6_class: %s has fewer than two source rows to search by" % what)
    i = rom.find(key)
    if i < 0:
        raise SystemExit("ot6_class: %s not found in the ROM by its source's opening rows (%s): "
                         "the ROM was not built from this source" % (what, key.hex()))
    if rom.find(key, i + 1) >= 0:
        raise SystemExit("ot6_class: %s's opening rows (%s) are not unique in the ROM" % (what, key.hex()))
    return i


def rom_rows(rom: bytes, at: int):
    """[(species, shields, class byte, offset)] of the 4-byte rows at `at`,
    up to the $ffff terminator."""
    rows, a = [], at
    while True:
        sp = rom[a] | (rom[a + 1] << 8)
        if sp == 0xFFFF:
            break
        rows.append((sp, rom[a + 2], rom[a + 3], a))
        a += 4
    return rows


def floor_classes(text: str, C: Classes):
    """ot6_break_floor.inc: one class byte per species, id order."""
    vals = []
    for n, line in enumerate(text.splitlines(), 1):
        code = line.split(";", 1)[0]
        m = re.match(r"\s*\.byte\s+(.+?)\s*$", code)
        if not m:
            continue
        for tok in m.group(1).split(","):
            if tok.strip():
                vals.append(C.value(tok, "%s:%d" % (FLOOR_INC, n)))
    if len(vals) != N_SPECIES:
        raise SystemExit("ot6_class: %s parsed to %d species, not %d: the floor-class parse is broken"
                         % (FLOOR_INC, len(vals), N_SPECIES))
    return vals


# ---------------------------------------------------------------- selftest --

def selftest(root: str) -> int:
    C = read(root)
    assert C.mask == sum(C.token.values()) and len(C.bit) == C.consts["OT6_NCLASS"]
    assert C.names(0) == "(none)" and C.names(C.mask).count("|") == len(C.bit) - 1
    first = next(iter(C.token))
    assert C.value("%s|$00" % first) == C.token[first]
    # a private literal table is exactly what this module exists to refuse:
    # a source with a class the union omits, a count that disagrees, a
    # null-break bit inside the classes
    good = "OT6_A := $01\nOT6_B := $02\nOT6_CLASSES := $03\nOT6_NCLASS = 2\nOT6_NULLBRK := $80\n" \
           "OT6_CLS_X = OT6_B\n"
    c = Classes(parse_consts(good))
    assert c.bit == {"a": 1, "b": 2} and c.consts["OT6_CLS_X"] == 2 and c.names(3) == "a|b"
    for tag, bad in (("count", good.replace("OT6_NCLASS = 2", "OT6_NCLASS = 3")),
                     ("union", good.replace("OT6_CLASSES := $03", "OT6_CLASSES := $07")),
                     ("nullbrk", good.replace("OT6_NULLBRK := $80", "OT6_NULLBRK := $02"))):
        try:
            Classes(parse_consts(bad))
        except SystemExit as e:
            print("ot6_class selftest: mutant refused, %s: %s" % (tag, e))
        else:
            raise AssertionError("mutant %s was accepted" % tag)
    try:
        c.value("OT6_C")
    except SystemExit as e:
        print("ot6_class selftest: mutant refused, token: %s" % e)
    else:
        raise AssertionError("an unknown class token was accepted")
    # the table search: found by the source's rows, refused when absent or
    # when the opening rows occur twice
    src = [(0, 2, 1), (0x19, 3, 1), (0x134, 4, 2), (0x64, 4, 2)]
    blob = b"".join(bytes([sp & 255, sp >> 8, sh, cl]) for sp, sh, cl in src)
    rom = bytes(16) + blob + bytes([0xFF, 0xFF]) + bytes(8)
    at = rom_table_at(rom, src)
    assert at == 16 and [r[:3] for r in rom_rows(rom, at)] == src
    for tag, bad in (("absent", bytes(64)), ("twice", rom + blob)):
        try:
            rom_table_at(bad, src)
        except SystemExit as e:
            print("ot6_class selftest: mutant refused, %s: %s" % (tag, str(e)[:90]))
        else:
            raise AssertionError("mutant %s was accepted" % tag)
    with open(os.path.join(root, HUD_ASM), encoding="utf-8") as f:
        rows = shield_rows(f.read(), C)
    with open(os.path.join(root, FLOOR_INC), encoding="utf-8") as f:
        floor = floor_classes(f.read(), C)
    assert len(rows) >= 300 and all(r[2] & ~C.mask == 0 for r in rows), "an Ot6ShieldTbl class byte leaves OT6_CLASSES"
    assert all(v and v & (v - 1) == 0 and v & C.mask for v in floor), "a floor byte is not one class"
    print("ot6_class selftest OK: %d classes (%s), mask $%02x; %d Ot6ShieldTbl rows, %d floor bytes"
          % (len(C.bit), ", ".join(C.bit), C.mask, len(rows), len(floor)))
    return 0


def main() -> int:
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return selftest(args.repo)
    C = read(args.repo)
    for n, b in C.bit.items():
        print("$%02x %s" % (b, n))
    return 0


if __name__ == "__main__":
    sys.exit(main())
