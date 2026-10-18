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
     INEXPRESSIBLE ("Protect-alike"); any other
     unknown name fails, so a typo cannot pass as inexpressible.  An Esper with no planned list
     is only held to property 1.

3. The stat packages (#418).  Ot6EsperStatTbl (battle/ot6_progression.asm;
   two bytes per Esper, four signed nibbles: vigor, speed, stamina, mag.pwr,
   each [sign:1][magnitude:3]) equals the "Stat vig/spd/stm/mag" cell of that
   Esper's row in docs/design/magicite.md, for every Esper: both roster
   tables carry the column, and an Esper with no row or a cell that does not
   read as four signed numbers fails.

Equipment also teaches: ItemProp +3 (the learn rate) and +4 (the spell) make
a worn piece teach its spell after battles, as an Esper does, so property 1
holds for every item too (#266: vanilla's Flame, Ice and Thunder Shld taught
Fire 2, Ice 2 and Bolt 2, and the World of Ruin route's CYAN and MOG learned
Ice 2 and Bolt 2 wearing them; build/attempts/wt/v029-narshe-route/
spells_all/).

And equipment grants while worn, as an Esper does (#431): Ot6ItemGrantTbl
(battle/ot6_progression.asm; (item, spell) pairs ended by $ff) gives the
wearer its spell, never learned.  Items may grant a family's base -- the head
of an Ot6FoldTbl row, which boost folds up its tiers -- and never a tier or a
spell no row heads; and the table equals docs/design/magicite.md's "Items
that grant" table, in order.  Nothing else writes the learned-spell table: the new-game
init clears it, and vanilla's teach-spell event routine (GiveMagic) is in no
event command slot.

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
ITEM_NAMES = "ff6/src/text/item_name_en.json"
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
INEXPRESSIBLE = {"Protect-alike"}

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
        for s in ("NaturalMagic", "GenjuProp", "Ot6FoldTbl", "Ot6EsperStatTbl",
                  "Ot6ItemGrantTbl"):
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
        self.items = rom_offset(syms["ItemProp"])
        self.genju_rows = gsize // GENJU_ROW
        self.fold = rom_offset(syms["Ot6FoldTbl"])
        self.stat = rom_offset(syms["Ot6EsperStatTbl"])
        self.grant = rom_offset(syms["Ot6ItemGrantTbl"])
        self.item_names = [re.sub(r"^\{[a-z]+\}", "", t)
                           for t in json.loads(read(ITEM_NAMES))["text"]]
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


def esper_stats(inp, e):
    """(vigor, speed, stamina, mag.pwr) from Ot6EsperStatTbl's two bytes:
    byte 0 = [speed:4][vigor:4], byte 1 = [magpwr:4][stamina:4]."""
    b0, b1 = inp.rom[inp.stat + 2 * e], inp.rom[inp.stat + 2 * e + 1]
    nib = lambda n: -(n & 7) if n & 8 else n
    return (nib(b0 & 15), nib(b0 >> 4), nib(b1 & 15), nib(b1 >> 4))


def item_grants(inp):
    """[(item, spell)] from Ot6ItemGrantTbl, up to its $ff end."""
    out = []
    for k in range(ITEMS):
        it = inp.rom[inp.grant + 2 * k]
        if it == 0xFF:
            return out
        out.append((it, inp.rom[inp.grant + 2 * k + 1]))
    raise SystemExit("check_spell_grants: Ot6ItemGrantTbl has no $ff end")


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


GRANT_SECTION = "## Items that grant"


def item_grant_plan(inp):
    """[(item, spell)] from magicite.md's "Items that grant" table: rows whose
    first cell is an item's name, in order."""
    start = inp.magicite.find("\n" + GRANT_SECTION)
    if start < 0:
        raise SystemExit("check_spell_grants: %s has no '%s' section" % (MAGICITE_MD, GRANT_SECTION))
    end = inp.magicite.find("\n## ", start + 1)
    idx = {n.strip().lower(): i for i, n in enumerate(inp.item_names) if n.strip()}
    plan = []
    for l in inp.magicite[start:end if end > 0 else len(inp.magicite)].splitlines():
        cells = [c.strip() for c in l.strip().strip("|").split("|")]
        if len(cells) < 2 or cells[0].lower() not in idx:
            continue
        sp = spell_id(inp, cells[1])
        if sp is None:
            raise SystemExit("check_spell_grants: %s's '%s' row grants '%s', which is no spell name"
                             % (MAGICITE_MD, cells[0], cells[1]))
        plan.append((idx[cells[0].lower()], sp))
    return plan


_STAT_CELL = re.compile(r"([+−-]?\d+) / ([+−-]?\d+) / ([+−-]?\d+) / ([+−-]?\d+)(?:\s|$)")


def stat_plans(inp):
    """{esper index: (vigor, speed, stamina, mag.pwr)} from magicite.md's
    roster tables' fourth cell."""
    idx = {n.lower(): i for i, n in enumerate(inp.espers)}
    plans = {}
    for l in inp.magicite.splitlines():
        cells = [c.strip() for c in l.strip().strip("|").split("|")]
        if len(cells) < 4 or cells[0].lower() not in idx:
            continue
        m = _STAT_CELL.match(cells[3])
        if not m:
            raise SystemExit("check_spell_grants: %s's %s row has stat cell '%s', not "
                             "'vig / spd / stm / mag'" % (MAGICITE_MD, cells[0], cells[3]))
        plans[idx[cells[0].lower()]] = tuple(int(v.replace("−", "-")) for v in m.groups())
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


ITEMS, ITEM_ROW = 256, 30


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
    for it in range(ITEMS):
        rate, sp = inp.rom[inp.items + it * ITEM_ROW + 3], inp.rom[inp.items + it * ITEM_ROW + 4]
        if rate and sp in tiers:
            out.append("item $%02X teaches %s ($%02X, learn rate %d), a tier of %s: boosting %s casts it"
                       % (it, inp.name(sp), sp, rate, inp.name(tiers[sp]), inp.name(tiers[sp])))
    heads = set(inp.rom[inp.fold:inp.fold + 3 * inp.nfold][0::3])
    for it, sp in item_grants(inp):
        if sp in tiers:
            out.append("item $%02X (%s) grants %s ($%02X) while worn, a tier of %s: boosting %s casts it"
                       % (it, inp.item_names[it], inp.name(sp), sp, inp.name(tiers[sp]),
                          inp.name(tiers[sp])))
        elif sp not in heads:
            out.append("item $%02X (%s) grants %s ($%02X) while worn, which heads no Ot6FoldTbl row: "
                       "an item grants a family's base" % (it, inp.item_names[it], inp.name(sp), sp))
    return out, tiers


def check_item_plan(inp):
    got, plan = item_grants(inp), item_grant_plan(inp)
    if got != plan:
        fmt = lambda ps: ", ".join("%s: %s" % (inp.item_names[i], inp.name(s)) for i, s in ps)
        return ["Ot6ItemGrantTbl grants [%s]; %s plans [%s]" % (fmt(got), MAGICITE_MD, fmt(plan))]
    return []


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


def check_stat_plans(inp):
    out = []
    plans = stat_plans(inp)
    fmt = lambda t: " / ".join("%+d" % v if v else "0" for v in t)
    for e in range(inp.genju_rows):
        got = esper_stats(inp, e)
        if e not in plans:
            out.append("%s (Esper %d) stat is %s; %s has no row for it"
                       % (inp.espers[e], e, fmt(got), MAGICITE_MD))
        elif got != plans[e]:
            out.append("%s (Esper %d) stat is %s; %s plans %s"
                       % (inp.espers[e], e, fmt(got), MAGICITE_MD, fmt(plans[e])))
    return out


def run_checks(inp):
    probs = check_fold(inp)
    probs += check_stat_plans(inp)
    probs += check_item_plan(inp)
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

    def grant_doc_mutant(inp):
        inp.magicite, n = re.subn(r"\n\| Flame Shld \|[^\n]*", "", inp.magicite, count=1)
        assert n == 1, "magicite.md has no Flame Shld row to remove"

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
        ("item $61 (Ice Shld) teaches %s again" % base_inp.name(tier),
         lambda inp: (inp.rom.__setitem__(inp.items + 0x61 * ITEM_ROW + 3, 5),
                      inp.rom.__setitem__(inp.items + 0x61 * ITEM_ROW + 4, tier)),
         "item $61 teaches "),
        ("Ice Shld's grant -> %s" % base_inp.name(tier),
         rom_mutant(base_inp.grant + 3, tier), "item $61 (Ice Shld) grants "),
        ("Thunder Shld's grant -> Drain (no family)",
         rom_mutant(base_inp.grant + 5, 0x04), "item $62 (Thunder Shld) grants "),
        ("Ice Shld's grant -> Fire (plan)",
         rom_mutant(base_inp.grant + 3, 0x00), "Ot6ItemGrantTbl grants ["),
        ("magicite.md: the Flame Shld's row removed",
         grant_doc_mutant, "Ot6ItemGrantTbl grants ["),
        ("TERRA's first level -> $ff (out of level order)",
         rom_mutant(base_inp.nat + 1, NATURAL_NONE), "TERRA natural magic"),
        ("kits.md: Terra's Drain 50 levels later",
         kits_mutant, "TERRA natural magic is ["),
    ]
    # the stat packages (#418): a ROM nibble moved by one on the last Esper
    # (a World of Ruin row), each stat in turn, and a doc cell edited on the
    # first (a World of Balance row)
    nesp = base_inp.genju_rows - 1
    for k, stat in enumerate(("vigor", "speed", "stamina", "mag.pwr")):
        off = base_inp.stat + 2 * nesp + k // 2
        sh = 4 * (k % 2)
        n = (base_inp.rom[off] >> sh) & 15
        n2 = (n & 8) | (((n & 7) + 1) & 7) if (n & 7) != 7 else (n & 8) | 6
        mutants.append(("%s's %s nibble $%X -> $%X" % (base_inp.espers[nesp], stat, n, n2),
                        rom_mutant(off, (base_inp.rom[off] & ~(15 << sh) & 0xFF) | (n2 << sh)),
                        "%s (Esper %d) stat is " % (base_inp.espers[nesp], nesp)))

    def stat_doc_mutant(inp):
        inp.magicite, n = re.subn(r"(\| Ramuh \|[^|]*\|[^|]*\| [^|]*/ )(\+?\d+)( \|)",
                                  lambda m: m.group(1) + "+%d" % (int(m.group(2)) + 1)
                                  + m.group(3), inp.magicite, count=1)
        assert n == 1, "magicite.md has no Ramuh stat cell to mutate"
    mutants.append(("magicite.md: Ramuh's mag.pwr + 1", stat_doc_mutant,
                    "%s (Esper 0) stat is " % base_inp.espers[0]))

    def stat_row_gone(inp):
        inp.magicite, n = re.subn(r"\n\| Palidor \|[^\n]*", "", inp.magicite, count=1)
        assert n == 1, "magicite.md has no Palidor row to remove"
    pal = next(i for i, n in enumerate(base_inp.espers) if n.lower() == "palidor")
    mutants.append(("magicite.md: Palidor's row removed", stat_row_gone,
                    "%s (Esper %d) stat is " % (base_inp.espers[pal], pal)))
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
    # a stat cell that is not four signed numbers must fail, not be skipped
    inp = Input(root, rom_path, dbg_path)
    inp.magicite, n = re.subn(r"(\| Kirin \|[^|]*\|[^|]*\| )[^|]*\|", r"\g<1>+1 stamina |",
                              inp.magicite, count=1)
    try:
        if n != 1:
            raise AssertionError("magicite.md has no Kirin row to mutate")
        stat_plans(inp)
        print("selftest FAIL: magicite.md Kirin '+1 stamina' was not reported")
        ok = False
    except SystemExit as e:
        print("selftest: magicite.md Kirin '+1 stamina' -> red: %s" % e)
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
          "CELES's natural magic is %s's plan; %d Espers grant their planned list (%s); "
          "all %d Espers carry %s's stat package; %d items grant their planned family base "
          "while worn (%s)"
          % (len(tiers), ", ".join(inp.name(t) for t in sorted(tiers)), KITS_MD,
             len(plans), ", ".join(inp.espers[e] for e in sorted(plans)),
             inp.genju_rows, MAGICITE_MD, len(item_grants(inp)),
             ", ".join("%s: %s" % (inp.item_names[i], inp.name(s)) for i, s in item_grants(inp))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
