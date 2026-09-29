#!/usr/bin/env python3
"""Build gate: the spells characters learn and Espers grant are the planned
lists, and none of them is a higher tier (#305).

Two properties, read from the built ROM (build/ot6.sfc) at the addresses the
build's debug file (ff6/rom/ff6-en.dbg) records.

1. No tier.  Owner guideline (docs/guidelines.md, "Stronger spells come from
   boosting, never from a list"): no natural magic and no Esper grants Fire 2,
   Fire 3 or any other tier.  The tiers are whatever the built ROM's
   Ot6FoldTbl says (ff6/src/battle/ot6_boost.asm): rows of [head, +1 boost,
   +2 boosts]; a tier is any id in the second or third column that is not its
   row's head (so Life 2 and Life 3, since the life row reaches Life 3,
   #327).  The ROM's rows must equal the source's.

2. The plan.  The grant tables implement the design docs exactly:
   * NaturalMagic (field/event.asm; TERRA's and CELES's 16 [spell, level]
     pairs, learned at join by UpdateAbilities and on a battle level-up by
     LearnAbilities) equals the spell rows of Terra's and Celes's tables in
     docs/design/kits.md.  "join" is level 1; a row learned by story (the
     divines) or a non-spell skill (Runic) is not natural magic.  The real
     pairs come first, in level order (UpdateAbilities stops at the first
     pair above the current level); the unused pairs are ($ff, $ff), a level
     nothing reaches.
   * GenjuProp (menu/genju_prop.asm; each Esper's five spell ids at row bytes
     +1/+3/+5/+7/+9, granted while equipped) equals the planned list of every
     Esper that has one: docs/design/magicite.md's roster table ("Spells
     (base)"), overridden by the make_genju_prop rows of
     docs/design/magicite-tube-six.md §11 for the tube room's six.  A planned
     entry that names no spell is reported and skipped only when it is in
     INEXPRESSIBLE ("Protect-alike", "(Water lore-alike)"); any other
     unknown name fails, so a typo cannot pass as inexpressible.  An Esper with no planned list
     is only held to property 1.

Nothing else writes the learned-spell table: the new-game init clears it,
and vanilla's teach-spell event routine (GiveMagic) is in no event command
slot.

Usage:  python3 tools/check_spell_grants.py [--repo ROOT] [--rom PATH]
            [--dbg PATH] [--selftest]

--selftest runs the checks on the real ROM's bytes and docs with one mutant
at a time -- a tier put back in each table, a natural level moved by one, an
Esper spell swapped, a kits.md row edited -- and requires each to be
reported, and the untouched inputs to pass.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys

ROM = "build/ot6.sfc"
DBG = "ff6/rom/ff6-en.dbg"
BOOST_ASM = "ff6/src/battle/ot6_boost.asm"
CONST_INC = "ff6/include/const.inc"
GENJU_NAMES = "ff6/src/text/genju_name_en.json"
MAGIC_NAMES = "ff6/src/text/magic_name_en.json"
KITS_MD = "docs/design/kits.md"
MAGICITE_MD = "docs/design/magicite.md"
TUBE_SIX_MD = "docs/design/magicite-tube-six.md"

NATURAL_CHARS = ("TERRA", "CELES")
KITS_SECTION = {"TERRA": "### Terra", "CELES": "### Celes"}
NATURAL_PER_CHAR = 16
NATURAL_NONE = 0xFF
GENJU_ROW = 11
GENJU_SPELL_BYTES = (1, 3, 5, 7, 9)
GENJU_NONE = 0xFF
# kit rows learned at join or by level that are skills, not spells
NOT_SPELLS = {"Runic"}
# planned Esper entries that name no FF6 spell, reported rather than checked;
# any other unknown name in a plan is a typo and fails
INEXPRESSIBLE = {"Protect-alike", "(Water lore-alike)"}

_VAL = re.compile(r"\bval=0x([0-9A-Fa-f]+)")
_NAME = re.compile(r'\bname="([^"]*)"')
_SEG = re.compile(r'^seg\t.*\bname="([^"]*)".*\bsize=0x([0-9A-Fa-f]+)')


class Input:
    """Everything the checks read, so the selftest can mutate a copy."""

    def __init__(self, root, rom_path, dbg_path):
        def read(p, mode="r"):
            with open(p if os.path.isabs(p) else os.path.join(root, p), mode) as f:
                return f.read()
        self.rom = bytearray(read(rom_path, "rb"))
        syms, segs = dbg_symbols(read(dbg_path))
        for s in ("NaturalMagic", "GenjuProp", "Ot6FoldTbl"):
            if s not in syms:
                raise SystemExit("check_spell_grants: %s not in %s" % (s, dbg_path))
        if segs.get("natural_magic") != 2 * NATURAL_PER_CHAR * len(NATURAL_CHARS):
            raise SystemExit("check_spell_grants: natural_magic segment is %s bytes, "
                             "expected %d" % (segs.get("natural_magic"),
                                              2 * NATURAL_PER_CHAR * len(NATURAL_CHARS)))
        gsize = segs.get("genju_prop", 0)
        if gsize == 0 or gsize % GENJU_ROW:
            raise SystemExit("check_spell_grants: genju_prop segment is %s bytes, not "
                             "whole %d-byte rows" % (gsize, GENJU_ROW))
        self.nat = rom_offset(syms["NaturalMagic"])
        self.genju = rom_offset(syms["GenjuProp"])
        self.genju_rows = gsize // GENJU_ROW
        self.fold = rom_offset(syms["Ot6FoldTbl"])
        self.boost_asm = read(BOOST_ASM)
        self.nfold = fold_rows_in_source(self.boost_asm)
        self.enum = spell_names(read(CONST_INC))
        self.espers = json.loads(read(GENJU_NAMES))["text"]
        self.magic = [re.sub(r"^\{[a-z]+\}", "", t)
                      for t in json.loads(read(MAGIC_NAMES))["text"]]
        self.kits = read(KITS_MD)
        self.magicite = read(MAGICITE_MD)
        self.tube_six = read(TUBE_SIX_MD)

    def name(self, sp):
        return self.enum.get(sp, "$%02X" % sp)


def dbg_symbols(text: str):
    """Label addresses and segment sizes from ff6-en.dbg."""
    syms, segs = {}, {}
    for line in text.splitlines():
        m = _SEG.match(line)
        if m:
            segs[m.group(1)] = int(m.group(2), 16)
            continue
        if not line.startswith("sym\t") or "type=lab" not in line:
            continue
        v, n = _VAL.search(line), _NAME.search(line)
        if v and n:
            syms.setdefault(n.group(1), int(v.group(1), 16))
    return syms, segs


def rom_offset(addr: int) -> int:
    return addr & 0x3FFFFF     # HiROM: bank $C0-$FF maps linearly


def fold_rows_in_source(text: str) -> int:
    """How many [head, +1, +2] rows Ot6FoldTbl declares."""
    lines = text.splitlines()
    start = next(i for i, l in enumerate(lines) if l.strip().startswith("Ot6FoldTbl:"))
    n = 0
    for l in lines[start + 1:]:
        code = l.split(";", 1)[0].strip()
        if not code.startswith(".byte"):
            break
        n += 1
    return n


def spell_names(text: str):
    """ATTACK enum ids -> names (const.inc), for readable failures."""
    body = text.split(".enum ATTACK", 1)[1].split(".endenum", 1)[0]
    names = {}
    for l in body.splitlines():
        m = re.match(r"\s*([A-Z0-9_]+)\s*;=\s*\$([0-9a-fA-F]+)", l)
        if m:
            names[int(m.group(2), 16)] = m.group(1)
    return names


def tiers_of(fold: bytes):
    tiers = {}
    for r in range(0, len(fold), 3):
        head = fold[r]
        for t in fold[r + 1:r + 3]:
            if t != head:
                tiers[t] = head
    return tiers


# ----------------------------------------------------------------- the ROM --

def natural_pairs(inp, c):
    base = inp.nat + c * NATURAL_PER_CHAR * 2
    return [(inp.rom[base + 2 * k], inp.rom[base + 2 * k + 1]) for k in range(NATURAL_PER_CHAR)]


def esper_spells(inp, e):
    return [inp.rom[inp.genju + e * GENJU_ROW + off] for off in GENJU_SPELL_BYTES]


# ---------------------------------------------------------------- the docs --

def spell_id(inp, name):
    """A doc's spell name -> its id, or None when it names no spell."""
    want = name.strip().lower()
    for i, n in enumerate(inp.magic):
        if n.strip().lower() == want:
            return i
    return None


def kits_plan(inp, who):
    """[(spell id, level)] from kits.md's table for this character.

    Returns (pairs, notes): notes name the rows that are not natural magic."""
    text = inp.kits
    head = KITS_SECTION[who]
    start = text.find("\n" + head)
    if start < 0:
        raise SystemExit("check_spell_grants: %s has no '%s' section" % (KITS_MD, head))
    end = text.find("\n### ", start + 1)
    section = text[start:end if end > 0 else len(text)]
    # the kit table: the first table in the section, headed "| # | Spell..."
    lines = section.splitlines()
    top = next((i for i, l in enumerate(lines) if re.match(r"\|\s*#\s*\|\s*Spell", l)), None)
    if top is None:
        raise SystemExit("check_spell_grants: %s's %s section has no '| # | Spell' table"
                         % (KITS_MD, head))
    rows = []
    for l in lines[top + 2:]:
        if not l.startswith("|"):
            break
        rows.append(l)
    if not rows:
        raise SystemExit("check_spell_grants: %s's %s table has no rows" % (KITS_MD, head))
    pairs, notes = [], []
    for r in rows:
        cells = [c.strip() for c in r.strip().strip("|").split("|")]
        name_cell, level_cell = cells[1], cells[-1]
        name = re.split(r"\s+✦|\s+\(", name_cell.replace("**", ""))[0].strip()
        m = re.match(r"(join|\d+)", level_cell)
        if not m:
            notes.append("%s row '%s' is learned by story ('%s'): not natural magic"
                         % (who, name, level_cell))
            continue
        level = 1 if m.group(1) == "join" else int(m.group(1))
        sp = spell_id(inp, name)
        if sp is None:
            if name not in NOT_SPELLS:
                raise SystemExit("check_spell_grants: %s row '%s' (%s) names no spell and is "
                                 "not a known skill" % (who, name, level_cell))
            notes.append("%s row '%s' is a skill, not a spell" % (who, name))
            continue
        pairs.append((sp, level))
    return pairs, notes


def esper_plans(inp):
    """{esper index: ([spell ids], [inexpressible names], source)}."""
    idx = {n.lower(): i for i, n in enumerate(inp.espers)}
    plans = {}
    for l in inp.magicite.splitlines():
        cells = [c.strip() for c in l.strip().strip("|").split("|")]
        if len(cells) < 3 or cells[0].lower() not in idx:
            continue
        ids, skipped = [], []
        for n in cells[2].replace("*", "").split(","):
            n = n.strip()
            sp = spell_id(inp, n)
            if sp is not None:
                ids.append(sp)
            elif n in INEXPRESSIBLE:
                skipped.append(n)
            else:
                raise SystemExit("check_spell_grants: %s's %s row plans '%s', which is no "
                                 "spell name and not in INEXPRESSIBLE (a typo?)"
                                 % (MAGICITE_MD, cells[0], n))
        plans[idx[cells[0].lower()]] = (ids, skipped, MAGICITE_MD)
    block = inp.tube_six.split("## 11. The data", 1)
    if len(block) < 2:
        raise SystemExit("check_spell_grants: %s has no '## 11. The data'" % TUBE_SIX_MD)
    e = None
    for l in block[1].split("## 12.", 1)[0].splitlines():
        m = re.match(r";\s*(\d+):", l)
        if m:
            e = int(m.group(1))
            continue
        m = re.match(r"make_genju_prop\s+(.*)", l)
        if m and e is not None:
            ids = []
            for n in re.findall(r"\{([A-Z0-9_]+),", m.group(1)):
                sp = next((i for i, v in inp.enum.items() if v == n), None)
                if sp is None:
                    raise SystemExit("check_spell_grants: %s names unknown spell %s"
                                     % (TUBE_SIX_MD, n))
                ids.append(sp)
            plans[e] = (ids, [], TUBE_SIX_MD + " §11")
            e = None
    return plans


# ----------------------------------------------------------------- checks --

def check_fold(inp):
    lines = inp.boost_asm.splitlines()
    start = next(i for i, l in enumerate(lines) if l.strip().startswith("Ot6FoldTbl:"))
    src = []
    for l in lines[start + 1:start + 1 + inp.nfold]:
        code = l.split(";", 1)[0].strip()[len(".byte"):]
        src += [int(t.strip().lstrip("$"), 16) for t in code.split(",")]
    got = list(inp.rom[inp.fold:inp.fold + 3 * inp.nfold])
    if got != src:
        return ["Ot6FoldTbl in the ROM (%s) is not the source's (%s)"
                % (" ".join("%02X" % b for b in got), " ".join("%02X" % b for b in src))]
    return []


def check_tiers(inp):
    tiers = tiers_of(inp.rom[inp.fold:inp.fold + 3 * inp.nfold])
    out = []
    for c, who in enumerate(NATURAL_CHARS):
        for k, (sp, lv) in enumerate(natural_pairs(inp, c)):
            if sp in tiers:
                out.append("%s natural magic, entry %d (level %d) grants %s ($%02X), a tier "
                           "of %s: boosting %s casts it" % (who, k + 1, lv, inp.name(sp), sp,
                                                            inp.name(tiers[sp]), inp.name(tiers[sp])))
    for e in range(inp.genju_rows):
        for s, sp in enumerate(esper_spells(inp, e)):
            if sp in tiers:
                out.append("%s (Esper %d), spell slot %d grants %s ($%02X), a tier of %s: "
                           "boosting %s casts it" % (inp.espers[e], e, s + 1, inp.name(sp), sp,
                                                     inp.name(tiers[sp]), inp.name(tiers[sp])))
    return out, tiers


def check_natural_plan(inp):
    out, notes = [], []
    for c, who in enumerate(NATURAL_CHARS):
        plan, n = kits_plan(inp, who)
        notes += n
        pairs = natural_pairs(inp, c)
        real = [p for p in pairs if p != (NATURAL_NONE, NATURAL_NONE)]
        if pairs[:len(real)] != real:
            out.append("%s natural magic: an unused ($ff, $ff) pair sits before a real one "
                       "(UpdateAbilities stops at it)" % who)
        levels = [lv for _, lv in real]
        if levels != sorted(levels):
            out.append("%s natural magic is not in level order (%s): UpdateAbilities stops "
                       "at the first pair above the current level" % (who, levels))
        fmt = lambda ps: ", ".join("%s %d" % (inp.name(s), l) for s, l in ps)
        if sorted(real) != sorted(plan):
            out.append("%s natural magic is [%s]; %s plans [%s]"
                       % (who, fmt(real), KITS_MD, fmt(plan)))
    return out, notes


def check_esper_plans(inp):
    out, notes = [], []
    for e, (plan, skipped, src) in sorted(esper_plans(inp).items()):
        got = [sp for sp in esper_spells(inp, e) if sp != GENJU_NONE]
        for s in skipped:
            notes.append("%s's planned '%s' (%s) names no spell: not expressible"
                         % (inp.espers[e], s, src))
        if got != plan:
            out.append("%s (Esper %d) grants [%s]; %s plans [%s]"
                       % (inp.espers[e], e, ", ".join(inp.name(s) for s in got), src,
                          ", ".join(inp.name(s) for s in plan)))
    return out, notes


def run_checks(inp):
    probs = check_fold(inp)
    p, tiers = check_tiers(inp)
    probs += p
    p, n1 = check_natural_plan(inp)
    probs += p
    p, n2 = check_esper_plans(inp)
    probs += p
    return probs, tiers, n1 + n2


# ---------------------------------------------------------------- selftest --

def selftest(root, rom_path, dbg_path):
    """Each mutant must add a problem that names it, on top of whatever the
    real inputs report (so the control holds on a red tree too)."""
    base_inp = Input(root, rom_path, dbg_path)
    base, tiers, _ = run_checks(base_inp)
    tier = min(tiers)
    plans = esper_plans(base_inp)
    planned = min(plans)
    first = base_inp.espers[planned]
    # the deepest tier id (Life 3) on the last planned Esper, so a tier from
    # the fold table's third column is caught as well as the first tier
    deep, lastp = max(tiers), max(plans)
    last = base_inp.espers[lastp]

    def rom_mutant(off, val):
        def f(inp):
            inp.rom[off] = val
        return f

    def kits_mutant(inp):
        # Terra's Drain row moved 50 levels later than the doc says now
        inp.kits, n = re.subn(r"(\| \d+ \| Drain \| )(\d+)",
                              lambda m: m.group(1) + str(int(m.group(2)) + 50), inp.kits, count=1)
        assert n == 1, "kits.md has no Terra Drain row to mutate"

    mutants = [
        ("TERRA's first natural spell -> %s" % base_inp.name(tier),
         rom_mutant(base_inp.nat, tier), "TERRA natural magic, entry 1 "),
        ("TERRA's first natural spell -> %s (plan)" % base_inp.name(tier),
         rom_mutant(base_inp.nat, tier), "TERRA natural magic is ["),
        ("%s's first spell -> %s" % (first, base_inp.name(tier)),
         rom_mutant(base_inp.genju + planned * GENJU_ROW + GENJU_SPELL_BYTES[0], tier),
         "%s (Esper %d), spell slot 1 " % (first, planned)),
        ("%s's first spell -> %s (plan)" % (first, base_inp.name(tier)),
         rom_mutant(base_inp.genju + planned * GENJU_ROW + GENJU_SPELL_BYTES[0], tier),
         "%s (Esper %d) grants [" % (first, planned)),
        ("%s's first spell -> %s" % (last, base_inp.name(deep)),
         rom_mutant(base_inp.genju + lastp * GENJU_ROW + GENJU_SPELL_BYTES[0], deep),
         "%s (Esper %d), spell slot 1 " % (last, lastp)),
        ("CELES's second natural level + 1",
         rom_mutant(base_inp.nat + NATURAL_PER_CHAR * 2 + 3,
                    base_inp.rom[base_inp.nat + NATURAL_PER_CHAR * 2 + 3] + 1),
         "CELES natural magic is ["),
        ("TERRA's first level -> $ff (out of level order)",
         rom_mutant(base_inp.nat + 1, NATURAL_NONE), "TERRA natural magic"),
        ("kits.md: Terra's Drain 50 levels later",
         kits_mutant, "TERRA natural magic is ["),
    ]
    ok = True
    for what, mutate, tag in mutants:
        inp = Input(root, rom_path, dbg_path)
        mutate(inp)
        p, _, _ = run_checks(inp)
        new = [x for x in p if x not in base and x.startswith(tag)]
        if new:
            print("selftest: %s -> red: %s" % (what, new[0]))
        else:
            print("selftest FAIL: %s was not reported" % what)
            ok = False
    # a misspelt spell in a planned Esper row must fail, not pass as
    # inexpressible
    inp = Input(root, rom_path, dbg_path)
    inp.magicite, n = re.subn(r"(\| Stray \|[^|]*\| )Muddle", r"\g<1>Mudle", inp.magicite, count=1)
    try:
        if n != 1:
            raise AssertionError("magicite.md has no Stray row to mutate")
        esper_plans(inp)
        print("selftest FAIL: magicite.md Stray 'Mudle' was not reported")
        ok = False
    except SystemExit as e:
        print("selftest: magicite.md Stray 'Mudle' -> red: %s" % e)
    print("selftest: the untouched inputs report %d problem(s)" % len(base))
    print("selftest %s" % ("ok" if ok else "FAILED"))
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--repo", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    ap.add_argument("--rom", default=ROM)
    ap.add_argument("--dbg", default=DBG)
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    os.chdir(a.repo)
    if a.selftest:
        return selftest(a.repo, a.rom, a.dbg)
    inp = Input(a.repo, a.rom, a.dbg)
    probs, tiers, notes = run_checks(inp)
    for n in notes:
        print("check_spell_grants: note: " + n)
    if probs:
        for p in probs:
            print("check_spell_grants: " + p)
        print("check_spell_grants: FAIL, %d problem(s)" % len(probs))
        return 1
    plans = esper_plans(inp)
    print("check_spell_grants: ok, no grant names one of the %d tiers (%s); TERRA's and "
          "CELES's natural magic is %s's plan; %d Espers grant their planned list (%s)"
          % (len(tiers), ", ".join(inp.name(t) for t in sorted(tiers)), KITS_MD,
             len(plans), ", ".join(inp.espers[e] for e in sorted(plans))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
