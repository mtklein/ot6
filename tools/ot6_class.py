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


# ------------------------------------------------- the weapon and skill tables --

def _expr(expr: str, where: str) -> int:
    """A tiny asm constant expression like '$a3 - $5a'."""
    t = expr.replace("$", "0x")
    if not re.fullmatch(r"[0-9a-fA-Fx+\-*() ]+", t):
        raise SystemExit("ot6_class: unparseable expression %r at %s" % (expr, where))
    return eval(t, {"__builtins__": {}})  # noqa: S307 -- vetted charset above


def weapon_classes(text: str, C: Classes):
    """Ot6WeapClassTbl: 256 class bytes, item-id indexed (.byte / .res)."""
    src = text.splitlines()
    start = next(i for i, l in enumerate(src) if l.strip().startswith("Ot6WeapClassTbl:"))
    out = []
    for i in range(start + 1, len(src)):
        code = src[i].split(";", 1)[0].strip()
        where = "%s:%d" % (CLASS_ASM, i + 1)
        if not code:
            continue
        m = re.match(r"\.byte\s+(.+)$", code)
        if m:
            v = C.value(m.group(1), where)
            if v & ~(C.mask | C.nullbrk):
                raise SystemExit("ot6_class: Ot6WeapClassTbl byte $%02x at %s leaves "
                                 "OT6_CLASSES|OT6_NULLBRK" % (v, where))
            out.append(v)
        elif code.startswith(".res"):
            m = re.match(r"\.res\s+(.+?),\s*(\S+)$", code)
            out.extend([_expr(m.group(2), where)] * _expr(m.group(1), where))
        else:
            break  # next label / directive: table ended
        if len(out) >= 256:
            break
    if len(out) != 256:
        raise SystemExit("ot6_class: Ot6WeapClassTbl parsed %d bytes, want 256 (%s)"
                         % (len(out), CLASS_ASM))
    return out


def skill_classes(text: str, C: Classes):
    """Ot6SkillClassTbl: {ability id: class byte}, $ff-terminated pairs."""
    src = text.splitlines()
    start = next(i for i, l in enumerate(src) if l.strip().startswith("Ot6SkillClassTbl:"))
    out = {}
    for i in range(start + 1, len(src)):
        code = src[i].split(";", 1)[0].strip()
        if not code:
            continue
        m = re.match(r"\.byte\s+\$([0-9a-fA-F]{2})\s*,\s*(\S+)$", code)
        if not m:
            break
        out[int(m.group(1), 16)] = C.value(m.group(2), "%s:%d" % (CLASS_ASM, i + 1))
    if len(out) < 9:
        raise SystemExit("ot6_class: Ot6SkillClassTbl parsed %d entries, want >= 9 (%s)"
                         % (len(out), CLASS_ASM))
    return out


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


# ------------------------------------------------- the grouping and the holders --
# tools/six_classes/classes.py is the grouping as data (which class every weapon
# family, tool and skill carries; SIGNATURE: who really holds each) and
# tools/six_classes/stages.py the story's stages (who the player can field,
# whom the story forces).  ot6_class.asm is edited by hand (the generator that
# first wrote it from classes.py is retired; git has it); selftest() holds the two to agree, so a
# tool may read the bits from the source and the holders from the grouping.

PROTO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "six_classes")


def grouping():
    """(classes, stages): the two modules of tools/six_classes."""
    if PROTO not in sys.path:
        sys.path.insert(0, PROTO)
    import classes
    import stages
    return classes, stages


def really_held(name, magitek=False, K=None):
    """The classes a character really holds (signature weapon or command, not
    "could equip"); in Magitek armor, TERRA's TekMissile and nobody else's."""
    K = K or grouping()[0]
    if magitek:
        return K.KIND_CLASS["tekmissile"] if name == "TERRA" else 0
    return K.signature_mask(name)


def holder_rule(mask, roster, forced, magitek=False, K=None):
    """The owner's holder rule (2026-11-23: "we don't want just one particular
    character to be required to get through fights") for one species' weapon
    keys at one stage: None when met, else why not.  Met when at least two
    characters the player can field there really hold one of the row's
    classes, or one whom the story forces into the party does.  forced None:
    the story fixes the whole roster.  The same rule as split.py's
    holder_check."""
    K = K or grouping()[0]
    forced = set(roster) if forced is None else set(forced)
    if magitek and not any(really_held(n, True, K) for n in roster):
        return None                     # in armor with no TekMissile: no weapon key to hold
    real = sorted(n for n in roster if really_held(n, magitek, K) & mask)
    if not real:
        return "nobody fieldable there really holds it"
    if len(real) == 1 and real[0] not in forced:
        return "only %s really holds it, and the story does not force them in" % real[0]
    return None


def stage_table(S=None):
    """{first leg: (roster, forced, magitek)} of stages.STAGES; the open World
    of Ruin stage (roster None) is left out: its roster is the play's."""
    S = S or grouping()[1]
    return {first: (set(roster), set(roster) if forced is None else set(forced), magitek)
            for first, roster, forced, magitek in S.STAGES if roster is not None}


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
    # the floor follows the rows (gen_break_floor.py's rule 1): a species
    # whose row names a class has one of that row's classes as its floor byte
    stray = ["$%03X" % r[0] for r in rows if r[0] < N_SPECIES and r[2] and not floor[r[0]] & r[2]]
    assert not stray, ("the floor byte of %s is not a class of its Ot6ShieldTbl row: run "
                       "python3 ff6/tools/gen_break_floor.py" % ", ".join(stray))
    # the grouping (tools/six_classes/classes.py) restates the source's tables:
    # held to them, name by name and item by item
    K, S = grouping()
    assert {K.CONST[b]: b for b in K.CONST} == C.token, "classes.py CONST is not ot6_class.asm's class bits"
    with open(os.path.join(root, CLASS_ASM), encoding="utf-8") as f:
        asm = f.read()
    weapon, skill = weapon_classes(asm, C), skill_classes(asm, C)
    bad = [i for i in range(256) if K.item_class(i) != weapon[i] & C.mask]
    assert not bad, "classes.py ITEM_KIND disagrees with Ot6WeapClassTbl at item(s) " + ", ".join("$%02x" % i for i in bad)
    bad = [a for a in set(skill) | set(K.SKILL_KIND) if K.skill_class(a) != skill.get(a, 0) & C.mask]
    assert not bad, "classes.py SKILL_KIND disagrees with Ot6SkillClassTbl at " + ", ".join("$%02x" % a for a in bad)
    for kit, const in (("thief", "OT6_CLS_THIEF"), ("coin", "OT6_CLS_COIN"), ("club", "OT6_CLS_CLUB"),
                       ("fang", "OT6_CLS_FANG")):
        assert K.KIND_CLASS[K.KIT_KIND[kit]] == C.consts[const], "classes.py KIT_KIND %s is not %s" % (kit, const)
    for name in K.SIGNATURE:
        assert name in K.CHARS, name
    stage = stage_table(S)
    assert len(stage) >= 30 and all(f <= r for r, f, _m in stage.values()), "a stage forces someone it cannot field"
    # the holder rule: two real holders, or one the story forces
    two = next(b for b in C.token.values() if len(K.holders(b)) >= 2)
    a, b = sorted(K.holders(two))[:2]
    other = next(n for n in K.CHARS if n != "TERRA" and K.signature_mask(n) and not K.signature_mask(n) & two)
    assert holder_rule(two, {a, b, other}, set(), False, K) is None
    assert holder_rule(two, {a, other}, {a}, False, K) is None
    assert holder_rule(two, {a, other}, None, False, K) is None
    for tag, why in (("one holder the story does not force", holder_rule(two, {a, other}, set(), False, K)),
                     ("one holder, another forced", holder_rule(two, {a, other}, {other}, False, K)),
                     ("no holder", holder_rule(two, {other}, None, False, K)),
                     ("armor: TERRA's TekMissile is not that key",
                      holder_rule(C.mask & ~K.KIND_CLASS["tekmissile"], {"TERRA", a}, None, True, K))):
        assert why, "holder rule: %s was accepted" % tag
        print("ot6_class selftest: holder rule refuses %s: %s" % (tag, why))
    assert holder_rule(two, {a, other}, set(), True, K) is None, "armor without TERRA holds no key to ask for"
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
