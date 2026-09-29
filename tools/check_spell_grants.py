#!/usr/bin/env python3
"""Build gate: nothing grants a higher spell tier (#305).

Owner guideline (docs/guidelines.md, "Stronger spells come from boosting,
never from a list"): no character's natural magic and no Esper grants Fire 2,
Fire 3 or any other tier; boosting the family's base spell is how a player
reaches them.

The tiers are whatever the built ROM's Ot6FoldTbl says they are
(ff6/src/battle/ot6_boost.asm): rows of [head, +1 boost, +2 boosts], and a
tier is any id in the second or third column that is not its row's head.
The row count is taken from the source table; the bytes from the ROM, and
the two must agree.

The grant sources, read from the built ROM (build/ot6.sfc) at the addresses
the build's debug file (ff6/rom/ff6-en.dbg) records:

  * NaturalMagic (field/event.asm): TERRA's and CELES's level tables,
    16 [spell, level] pairs each, learned at join (UpdateAbilities) and on
    level-up in battle (LearnAbilities);
  * GenjuProp (menu/genju_prop.asm): each Esper's five spell ids at row
    bytes +1/+3/+5/+7/+9, granted while it is equipped (Ot6EsperSpellKnown,
    Ot6FieldSpellKnown).

Nothing else writes the learned-spell table: the new-game init clears it,
and vanilla's teach-spell event routine (GiveMagic) is in no event command
slot.  Any grant source that names a tier fails the check.

Usage:  python3 tools/check_spell_grants.py [--repo ROOT] [--rom PATH]
            [--dbg PATH] [--selftest]

--selftest runs the check on the real ROM's bytes with one tier put back in
each table (TERRA's first natural slot and the first Esper's first spell),
and requires both to be reported, then requires the untouched bytes to pass.
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

NATURAL_CHARS = ("TERRA", "CELES")
NATURAL_PER_CHAR = 16
GENJU_ROW = 11
GENJU_SPELL_BYTES = (1, 3, 5, 7, 9)

_VAL = re.compile(r"\bval=0x([0-9A-Fa-f]+)")
_NAME = re.compile(r'\bname="([^"]*)"')
_SEG = re.compile(r'^seg\t.*\bname="([^"]*)".*\bsize=0x([0-9A-Fa-f]+)')


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
        if not code:
            break
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


def grants(rom: bytes, nat: int, genju: int, genju_rows: int, espers=()):
    """[(source, spell id)] for every grant slot."""
    out = []
    for c, who in enumerate(NATURAL_CHARS):
        for k in range(NATURAL_PER_CHAR):
            a = nat + (c * NATURAL_PER_CHAR + k) * 2
            out.append(("%s natural magic, entry %d (level %d)" % (who, k + 1, rom[a + 1]),
                        rom[a]))
    for e in range(genju_rows):
        for s, off in enumerate(GENJU_SPELL_BYTES):
            who = espers[e] if e < len(espers) else "Esper %d" % e
            out.append(("%s (Esper %d), spell slot %d" % (who, e, s + 1),
                        rom[genju + e * GENJU_ROW + off]))
    return out


def problems_for(rom: bytes, layout, names, espers=()):
    nat, genju, genju_rows, fold, nfold = layout
    tiers = tiers_of(rom[fold:fold + 3 * nfold])
    out = []
    for where, sp in grants(rom, nat, genju, genju_rows, espers):
        if sp in tiers:
            out.append("%s grants %s ($%02X), a tier of %s: boosting %s reaches it; "
                       "grant the head or another spell"
                       % (where, names.get(sp, "?"), sp, names.get(tiers[sp], "?"),
                          names.get(tiers[sp], "?")))
    return out, tiers


def load(root: str, rom_path: str, dbg_path: str):
    def read(p, mode="r"):
        with open(os.path.join(root, p) if not os.path.isabs(p) else p, mode) as f:
            return f.read()
    rom = read(rom_path, "rb")
    syms, segs = dbg_symbols(read(dbg_path))
    for s in ("NaturalMagic", "GenjuProp", "Ot6FoldTbl"):
        if s not in syms:
            raise SystemExit("check_spell_grants: %s not in %s" % (s, dbg_path))
    if segs.get("natural_magic") != 2 * NATURAL_PER_CHAR * len(NATURAL_CHARS):
        raise SystemExit("check_spell_grants: natural_magic segment is %s bytes, expected %d "
                         "(16 [spell, level] pairs for TERRA and CELES)"
                         % (segs.get("natural_magic"), 2 * NATURAL_PER_CHAR * len(NATURAL_CHARS)))
    gsize = segs.get("genju_prop", 0)
    if gsize == 0 or gsize % GENJU_ROW:
        raise SystemExit("check_spell_grants: genju_prop segment is %s bytes, not whole "
                         "%d-byte rows" % (gsize, GENJU_ROW))
    nfold = fold_rows_in_source(read(BOOST_ASM))
    layout = (rom_offset(syms["NaturalMagic"]), rom_offset(syms["GenjuProp"]),
              gsize // GENJU_ROW, rom_offset(syms["Ot6FoldTbl"]), nfold)
    names = spell_names(read(CONST_INC))
    names["espers"] = json.loads(read(GENJU_NAMES))["text"]
    return bytearray(rom), layout, names


def check_fold_matches_source(root, rom, layout):
    """The ROM's fold rows are the source's (the tier set comes from the ROM)."""
    text = open(os.path.join(root, BOOST_ASM)).read()
    lines = text.splitlines()
    start = next(i for i, l in enumerate(lines) if l.strip().startswith("Ot6FoldTbl:"))
    src = []
    for l in lines[start + 1:start + 1 + layout[4]]:
        code = l.split(";", 1)[0].strip()[len(".byte"):]
        src += [int(t.strip().lstrip("$"), 16) for t in code.split(",")]
    fold = layout[3]
    got = list(rom[fold:fold + 3 * layout[4]])
    if got != src:
        return ["Ot6FoldTbl in the ROM (%s) is not the source's (%s)"
                % (" ".join("%02X" % b for b in got), " ".join("%02X" % b for b in src))]
    return []


def run(root, rom_path, dbg_path):
    rom, layout, names = load(root, rom_path, dbg_path)
    probs = check_fold_matches_source(root, rom, layout)
    p, tiers = problems_for(rom, layout, names, names["espers"])
    probs += p
    return probs, tiers, layout, names, rom


def selftest(root, rom_path, dbg_path):
    """One tier put back in each table must go red, on top of whatever the
    real ROM already reports (so the control holds on a red tree too)."""
    rom, layout, names = load(root, rom_path, dbg_path)
    espers = names["espers"]
    nat, genju, _, fold, nfold = layout
    tiers = tiers_of(rom[fold:fold + 3 * nfold])
    if not tiers:
        print("selftest FAIL: the fold table names no tiers")
        return 1
    tier = min(tiers)
    base, _ = problems_for(rom, layout, names, espers)
    ok = True
    for what, off, tag in (("TERRA's first natural slot", nat, "TERRA natural magic, entry 1 "),
                           ("%s's first spell" % espers[0], genju + GENJU_SPELL_BYTES[0],
                            "%s (Esper 0), spell slot 1 " % espers[0])):
        bad = bytearray(rom)
        bad[off] = tier
        p, _ = problems_for(bad, layout, names, espers)
        new = [x for x in p if x not in base and x.startswith(tag)]
        if not new:
            print("selftest FAIL: %s set to %s ($%02X) was not reported"
                  % (what, names.get(tier, "?"), tier))
            ok = False
        else:
            print("selftest: %s set to %s -> red: %s" % (what, names.get(tier, "?"), new[0]))
    p, _ = problems_for(rom, layout, names, espers)
    print("selftest: the untouched ROM reports %d grant(s) naming a tier" % len(p))
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
    probs, tiers, layout, names, _ = run(a.repo, a.rom, a.dbg)
    n_grants = NATURAL_PER_CHAR * len(NATURAL_CHARS) + layout[2] * len(GENJU_SPELL_BYTES)
    tier_list = ", ".join("%s" % names.get(t, "$%02X" % t) for t in sorted(tiers))
    if probs:
        for p in probs:
            print("check_spell_grants: " + p)
        print("check_spell_grants: FAIL, %d grant(s) name a tier (tiers: %s)"
              % (len(probs), tier_list))
        return 1
    print("check_spell_grants: ok, %d grant slots (%d natural, %d Esper rows x 5) "
          "name none of the %d tiers (%s)"
          % (n_grants, NATURAL_PER_CHAR * len(NATURAL_CHARS), layout[2], len(tiers), tier_list))
    return 0


if __name__ == "__main__":
    sys.exit(main())
