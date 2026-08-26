#!/usr/bin/env python3
"""Report whether a field map can roll a random battle, from which
formations, and whether they can be fled.

The chain, with the loads that make each step true:

  * a field map rolls only when byte +5 of its 33-byte map_prop.dat record
    has bit 7 set -- LoadMapProp copies the record to $0520
    (ff6/src/field/map.asm:143-158) and the step handler returns before the
    roll unless $0525 is negative (ff6/src/field/battle.asm:333-347);
  * the pool is sub_battle_group.dat[map], four formation words at
    rand_battle_group.dat[group*8], drawn 31.25/31.25/31.25/6.25%
    (field/battle.asm:398-408);
  * a formation's monsters are battle_monsters.dat (15 B: +1 present mask,
    +2..+7 indices, +14 index high bits);
  * a formation permits a pincer when battle_prop.dat word [f*4] ^ $00F0
    has bit 6 set (battle_main.asm:8175-8180 loads it, :7758-7768 masks it).

What "can they be fled" means here.  The pincer bit is a permission, not an
arrangement: when the roll does arrange the pincer, the fight cannot be fled
at all -- Cmd_2a reads $b1 bit 1 and answers "Can't run away!!"
(battle_main.asm:5729-5731) -- and a mere side attack raises run difficulty
from 2 to 6 per monster (:15584-15594).  So the per-map verdict is one of:
"no encounters", "fleeable" (no formation permits a pincer), or "pincer
possible" (a "flee" drive can stall the cap on a bad roll; budget for a
fight, or pick "tactical").

Usage:  python3 tools/audit_encounters.py [--repo ROOT] [--selftest] MAP...
Maps are decimal or 0x-hex.  Exit 0; the tool reports, it does not judge a
route.  --selftest exits 1 if the decode drifts from the pinned values.
"""

from __future__ import annotations

import argparse
import json
import os
import sys

MAP_PROP = "ff6/src/field/map_prop.dat"            # 33 B/map; +5 bit7 = rolls
SUB_GROUP = "ff6/src/field/sub_battle_group.dat"   # 1 B/map -> group
RAND_GROUP = "ff6/src/field/rand_battle_group.dat" # 4 formation words/group
MONSTERS = "ff6/src/battle/battle_monsters.dat"    # 15 B/formation
BATTLE_PROP = "ff6/src/battle/battle_prop.dat"     # 4 B/formation
MONSTER_NAMES = "ff6/src/text/monster_name_en.json"

MAP_REC = 33
FORM_REC = 15
ODDS = ("31.25%", "31.25%", "31.25%", "6.25%")     # field/battle.asm:398-408


class Data:
    def __init__(self, root):
        def rd(rel):
            with open(os.path.join(root, rel), "rb") as f:
                return f.read()
        self.map_prop = rd(MAP_PROP)
        self.sub = rd(SUB_GROUP)
        self.rand = rd(RAND_GROUP)
        self.monsters = rd(MONSTERS)
        self.battle_prop = rd(BATTLE_PROP)
        with open(os.path.join(root, MONSTER_NAMES), encoding="utf-8") as f:
            self.names = json.load(f)["text"]

    def rolls(self, m):
        return bool(self.map_prop[m * MAP_REC + 5] & 0x80)

    def group(self, m):
        return self.sub[m]

    def formations(self, g):
        return [int.from_bytes(self.rand[g * 8 + 2 * i: g * 8 + 2 * i + 2],
                               "little") for i in range(4)]

    def resolve(self, word):
        # A RandBattleGroup word's bit 15 ($8000) is a "+Rand(0..3)" flag,
        # stripped and applied at battle_main.asm:8215-8224: the slot draws one
        # of base..base+3 with equal odds.  Without it the raw word (e.g.
        # $80b1) indexes battle_monsters.dat far out of range.  Formations are
        # 9-bit (0..511).  Returns (list-of-formation-ids, is_rand).
        base = word & 0x01FF
        if word & 0x8000:
            return [base + k for k in range(4)], True
        return [base], False

    def bodies(self, f):
        rec = self.monsters[f * FORM_REC:(f + 1) * FORM_REC]
        if len(rec) < FORM_REC:
            return []       # formation index past the table (a stray flag bit)
        seen = {}
        for slot in range(6):
            if rec[1] & (1 << slot):
                sp = rec[2 + slot] | (((rec[14] >> slot) & 1) << 8)
                seen[sp] = seen.get(sp, 0) + 1
        return sorted(seen.items())

    def pincer(self, f):
        w = int.from_bytes(self.battle_prop[f * 4:f * 4 + 2], "little")
        return bool((w ^ 0x00F0) & 0x40)


def report(data, m):
    if not data.rolls(m):
        print("map %d: NO ENCOUNTERS (map_prop +5 bit 7 clear) -- a step "
              "here still wants a real playBattles mode, because the mode is "
              "what runs if this assumption is ever wrong" % m)
        return
    g = data.group(m)
    any_pincer = False
    print("map %d: rolls random battles, group %d" % (m, g))
    for i, w in enumerate(data.formations(g)):
        forms, is_rand = data.resolve(w)
        for j, f in enumerate(forms):
            p = data.pincer(f)
            any_pincer = any_pincer or p
            who = " ".join("%s($%03x)x%d" % (data.names[sp], sp, n)
                           for sp, n in data.bodies(f))
            odds = ODDS[i] + ("+r" if is_rand else "") if j == 0 else "  +rand"
            print("  %8s formation $%03x %-14s %s"
                  % (odds, f, "PINCER POSSIBLE" if p else "fleeable", who))
    if any_pincer:
        print("  -> a \"flee\" drive can stall M.FLEE_CAP on a pincer roll "
              "(Cmd_2a, $b1.1): budget a fight or pick \"tactical\"")
    else:
        print("  -> no formation permits a pincer; \"flee\" is safe here")


# ---------------------------------------------------------------- selftest --
# Pinned values, so a drift in any file's layout is a loud failure instead
# of a wrong answer.

def selftest(root):
    data = Data(root)
    ok = True

    def check(what, got, want):
        nonlocal ok
        if got != want:
            ok = False
            print("  SELFTEST FAIL %s: got %r want %r" % (what, got, want))

    check("map 98 rolls", data.rolls(98), True)
    f = data.formations(data.group(98))[0]
    pool = {(data.names[sp], n) for sp, n in data.bodies(f)}
    check("map 98 first formation is the recorded measurement",
          pool, {("Trilium", 1), ("Tusker", 1), ("Cirpius", 2)})
    check("map 98 pool has no pincer",
          any(data.pincer(x) for x in data.formations(data.group(98))), False)

    zozo = [data.pincer(f) for m in (221, 225)
            for f in data.formations(data.group(m))]
    check("zozo pincer count (burndown: 'several')", sum(zozo), 5)

    for m in (108, 109, 110):
        check("Returner Hideout map %d encounter-free" % m,
              data.rolls(m), False)

    # The Floating Continent (map 394) is the first map to use the $8000
    # +Rand(0..3) formation flag; without resolve() its raw words index the
    # formation table out of range (the crash this selftest now guards).
    check("FC map 394 rolls", data.rolls(394), True)
    fc_words = data.formations(data.group(394))
    check("FC first slot is a +Rand spread 177..180",
          data.resolve(fc_words[0]), ([177, 178, 179, 180], True))
    fc_pool = sorted({f for w in fc_words for f in data.resolve(w)[0]})
    check("FC pool is forms 177-188", fc_pool, list(range(177, 189)))

    print("audit_encounters selftest: " + ("ok" if ok else "FAILED"))
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--repo", default=os.path.dirname(os.path.dirname(
        os.path.abspath(__file__))))
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("maps", nargs="*",
                    help="field map ids, decimal or 0x-hex")
    args = ap.parse_args()

    if args.selftest:
        return selftest(args.repo)
    if not args.maps:
        print("audit_encounters: name at least one map (or --selftest); "
              "see --help for the decode this reports")
        return 2

    data = Data(args.repo)
    for s in args.maps:
        m = int(s, 0)
        if not 0 <= m * MAP_REC + 5 < len(data.map_prop):
            print("map %d: out of range" % m)
            continue
        report(data, m)
    return 0


if __name__ == "__main__":
    sys.exit(main())
