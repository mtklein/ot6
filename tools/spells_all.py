#!/usr/bin/env python3
"""spells_all.py -- every tracked checkpoint's learned spells against what the
built ROM can grant (#326; extended for #335 from build/attempts/wt/recut/
spells_all.py, folding in wt/v026-rom/335/spells_sources.py).
Run from a tree root after `ninja build/ot6.sfc`.

For every character record 0..11 in the checkpoint's save (the $1A6E learned
table, 54 bytes a character; savestate_party.find_char_block locates $1600):
  tiers     = learned spells that are a tier in the ROM's Ot6FoldTbl
              (check_spell_grants.tiers_of): no source in this ROM grants one.
  UNSOURCED = learned spells no current grant source produces for that save:
              not TERRA's or CELES's NaturalMagic at or below the saved level,
              and not in the GenjuProp list of an Esper the save holds
              ($1A69..$1A6C bits).  check_spell_grants.py's header: nothing
              else writes the learned table.
For TERRA (0) and CELES (6):
  missing   = natural spells at or below the saved level not learned.
One line per checkpoint; 'BAD' marks any tier or unsourced spell.  Exit 1
when any checkpoint is BAD.

  spells_all.py [ROOT]      read the checkpoints under ROOT (default .): the
                            captures the legs Continue, build/checkpoints/<key>/,
                            for every tracked key (savestate_party
                            checkpoint_payloads, #363)
  spells_all.py --control   the same checkpoints, each with one spell that is
                            no tier and that no source the save has produces
                            set learned for LOCKE in memory: every checkpoint
                            must read BAD (exit 0 if so)
"""
import sys

sys.path.insert(0, "tools")
import check_spell_grants as g  # noqa: E402
import savestate_party as sp  # noqa: E402

inp = g.Input(".", g.ROM, g.DBG)
tiers = g.tiers_of(bytes(inp.rom[inp.fold:inp.fold + 3 * inp.nfold]))
NAMES = ["TERRA", "LOCKE", "CYAN", "SHADOW", "EDGAR", "SABIN", "CELES", "STRAGO",
         "RELM", "SETZER", "MOG", "GAU"]
nat = {0: g.natural_pairs(inp, 0), 6: g.natural_pairs(inp, 1)}
grants = {e: {s for s in g.esper_spells(inp, e) if s != 0xFF}
          for e in range(inp.genju_rows)}
every = set().union(*grants.values()) | {s for c in nat for s, _ in nat[c] if s != 0xFF}
never = sorted(s for s in range(54) if s not in every)

control = "--control" in sys.argv
args = [a for a in sys.argv[1:] if a != "--control"]
root = args[0] if args else "."


def check(name, raw):
    cb = sp.find_char_block(bytes(raw), allow_fallback=False)
    if cb is None:
        return None, "? char table not located"
    bits = raw[cb + 0x469:cb + 0x46D]
    held = [e for e in range(inp.genju_rows) if bits[e // 8] >> (e % 8) & 1]
    from_espers = set().union(*(grants[e] for e in held)) if held else set()
    parts, bad = [], False
    for c in range(12):
        lvl = raw[cb + 37 * c + 8]
        base = cb + 0x46E + 54 * c
        learned = {s for s in range(54) if raw[base + s] == 0xFF}
        t = sorted(inp.name(s) for s in learned if s in tiers)
        ok = set(from_espers)
        if c in nat:
            ok |= {s for s, l in nat[c] if s != 0xFF and l <= lvl}
        extra = sorted(inp.name(s) for s in learned - ok)
        if t:
            bad = True
            parts.append(f"{NAMES[c]} L{lvl} TIERS={t}")
        if extra:
            bad = True
            parts.append(f"{NAMES[c]} L{lvl} UNSOURCED={extra}")
        if c in nat:
            want = {s for s, l in nat[c] if s != 0xFF and l <= lvl}
            miss = sorted(inp.name(s) for s in want - learned)
            parts.append(f"{NAMES[c]} L{lvl} missing={miss}")
    return bad, f"espers={len(held)} " + " | ".join(parts)


nbad = n = 0
picked = {}
for name, path in sp.checkpoint_payloads(root):
    raw = bytearray(open(path, "rb").read())
    if control:
        # a spell that is not a tier and that no source this save has
        # produces (an Esper the party does not hold grants it): LOCKE
        # learns it in memory, the shape of the Antdot the old negatives held
        cb = sp.find_char_block(bytes(raw), allow_fallback=False)
        if cb is not None:
            bits = raw[cb + 0x469:cb + 0x46D]
            held = [e for e in range(inp.genju_rows) if bits[e // 8] >> (e % 8) & 1]
            have = set().union(*(grants[e] for e in held)) if held else set()
            pick = next(x for x in range(54) if x not in tiers and x not in have)
            raw[cb + 0x46E + 54 * 1 + pick] = 0xFF
            picked[name] = inp.name(pick)
    bad, line = check(name, raw)
    n += 1
    nbad += bool(bad)
    print(("BAD " if bad else "ok  ") + name.ljust(28), line)
print(f"tier ids from Ot6FoldTbl: {sorted(inp.name(s) for s in tiers)}")
print(f"spells no current source produces: {[inp.name(s) for s in never]}")
if control:
    print(f"control: one unsourced, non-tier spell set learned for LOCKE in each "
          f"({sorted(set(picked.values()))}); {nbad} of {n} checkpoint(s) read BAD")
    sys.exit(0 if nbad == n else 1)
print(f"{nbad} checkpoint(s) hold a tier or a spell no source in this ROM produces for them")
sys.exit(1 if nbad else 0)
