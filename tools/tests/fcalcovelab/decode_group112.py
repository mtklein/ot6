#!/usr/bin/env python3
"""decode_group112.py -- map 394's random pool, decoded offline (issue #221).

    python3 tools/tests/fcalcovelab/decode_group112.py

Map 394 rolls world/field battle group 112.  Its four words are $80B1,
$80B4, $80B7, $80B9: base formations 177, 180, 183, 185, each `+Rand(0..3)`
because of the $8000 flag (battle_main.asm:8215-8224), so the effective pool
is formations 177..188 -- the vanilla Floating Continent set.  Formation
contents come from battle_monsters.dat (15-byte records: +1 occupied-slot
mask, +2..+7 the low byte of each slot's species, +14 the per-slot bit 8);
stats from monster_prop.dat (32-byte records, the offsets
tools/check_boss_rows.py uses); names from the shipped text tables.

The `special` column is the monster's own name for `atk $EF`
(monster_special_name_en.json, indexed by species) and `specdata` is
monster_prop +31, which battle_main.asm @32ec-@334e unpacks as:

    bit 7   the attack cannot be dodged
    bit 6   the attack deals NO damage (status only)
    bits 0-5  < $20: a status bit; >= $20: `$bc += value - $20`, and
              ApplyDmgMult then multiplies the damage by 1 + $bc/2

so Behemoth's Take Down ($23) is a physical hit at x2 and the Dragon's Tail
($27) one at x4, while Apokryphos's Silencer ($4B), Brainpan's Smirk ($54),
Misfit's Enmity ($40) and Ninja's Inviz ($44) deal no damage at all.

Nothing here reads the emulator; it is a data decode of the shipped tree.
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.dirname(os.path.abspath(__file__)))))
REC = 32
ELEMENTS = ["fire", "ice", "bolt", "poison", "wind", "holy", "earth", "water"]
BASES = [177, 180, 183, 185]
WEIGHT = [31.25, 31.25, 31.25, 6.25]


def elem(mask):
    return "|".join(n for i, n in enumerate(ELEMENTS) if mask & (1 << i)) or "-"


def main():
    d = lambda *p: os.path.join(ROOT, *p)
    prop = open(d("ff6/src/battle/monster_prop.dat"), "rb").read()
    bm = open(d("ff6/src/battle/battle_monsters.dat"), "rb").read()
    names = json.load(open(d("ff6/src/text/monster_name_en.json")))["text"]
    spec = json.load(open(d("ff6/src/text/monster_special_name_en.json")))["text"]

    def slots(f):
        r = bm[f * 15:(f + 1) * 15]
        mask, hi = r[1], r[14]
        return [(s, r[2 + s] | (((hi >> s) & 1) << 8))
                for s in range(6) if (mask >> s) & 1]

    # each base contributes its weight spread over its four +Rand outcomes
    odds = {}
    for base, w in zip(BASES, WEIGHT):
        for k in range(4):
            odds[base + k] = odds.get(base + k, 0.0) + w / 4

    print("map 394, group 112 -- formations 177..188 (base +Rand(0..3))\n")
    print("| roll | formation | bodies |")
    print("|---|---|---|")
    for f in sorted(odds):
        body = ", ".join("%s ($%03X)" % (names[sp].strip(), sp) for _, sp in slots(f))
        print("| %5.2f%% | %d ($%03X) | %s |" % (odds[f], f, f, body))

    seen = sorted({sp for f in odds for _, sp in slots(f)})
    print("\n| species | L | HP | spd | atk | def | mdef | weak | absorb | special | specdata |")
    print("|---|---|---|---|---|---|---|---|---|---|---|")
    for sp in seen:
        r = prop[sp * REC:(sp + 1) * REC]
        sd = r[31]
        if sd & 0x40:
            note = "no damage, status $%02X" % (sd & 0x3F)
        else:
            mult = 1 + max(0, (sd & 0x3F) - 0x20) // 2
            note = "physical x%d" % mult
        print("| %s ($%03X) | %d | %d | %d | %d | %d | %d | %s | %s | %s | $%02X (%s) |"
              % (names[sp].strip(), sp, r[16], r[8] | (r[9] << 8), r[0], r[1],
                 r[5], r[6], elem(r[25]), elem(r[23]), spec[sp].strip(), sd, note))
    return 0


if __name__ == "__main__":
    sys.exit(main())
