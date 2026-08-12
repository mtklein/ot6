#!/usr/bin/env python3
"""Report party members who are walking the story bare-handed.

Why this exists.  The game strips characters and returns their gear to the
inventory at story beats (`remove_equip` / EventCmd_8d, 58 sites in 15
clusters across event_main.asm), and the chain of generated savestates has
never once put it back on.  battle_brokendeath found this at the Vector
infiltration in 2026-07 and drove Equip -> Optimum by hand to fix its own
fixture.  Nobody checked whether it was a general problem; it is one.

On 2026-08-09 the first end-to-end run of the input-driven chain stalled at
`sfigaro_town`, where solo LOCKE lost the gate soldier three times running.
It read like a balance wall, a level-13 machine with 495 hp against a
level-8 thief, but the cause was different: LOCKE's whole equipment block
read `FF FF FF FF FF` and his own Dirk was sitting in the bag.  He was
punching it.  Armed, his swing went 8 -> 21.

A wrong fixture reads like a balance finding, and this script is here to
catch that case.  To keep it cheap, it reads the savestates directly, with
no emulator: 110 fixtures in about a second, against a `make savestates`
measured in hours.

Reading the fixture is `savestate_party.py`, shared with the sibling check
`audit_party_hp.py`; this file is only the equipment question.  What it
needs from a record is +$1F weapon and +$20..+$23 the rest, where $FF means
empty.

Usage:  python3 tools/audit_equipment.py [--dir build/states] [-v]
Exit 0 clean, 1 if anybody in a party is holding nothing.
"""

from __future__ import annotations

import argparse
import glob
import os
import sys

# Explicit rather than relying on sys.path[0], which PYTHONSAFEPATH and
# `python3 -P` both switch off; `make test` invokes this as a plain script
# but a one-line insert costs nothing and cannot surprise anyone later.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from savestate_party import (EMPTY, NAMES, declared_states, load_waivers,
                             read_party, split_orphans, stem_of)

WAIVERS = "tools/equipment_waivers.txt"
ITEM_PROP = "ff6/src/menu/item_prop_en.dat"

WEAPON_IDS = range(0x00, 0x60)


def equippable_weapons(repo: str) -> dict[int, int]:
    """How many weapon records each actor may hold, read from the ROM data.

    UMARO is bare-handed in ten fixtures, and that is correct, because the
    game will not let him hold anything.  That is derived here rather than
    hardcoded: the equip mask is `item_prop_en.dat` offset +$01, 16-bit,
    bit N = actor N (HANDOFF, "canonical facts you should not re-derive";
    byte +$00 always looks like a mask and always claims Terra, which is
    the mistake that entry exists to prevent).  An actor who can hold one
    weapon or none cannot be re-equipped and must not be reported as a
    finding, or the real findings get buried.
    """
    path = os.path.join(repo, ITEM_PROP)
    try:
        data = open(path, "rb").read()
    except OSError:
        return {}
    out = {}
    for actor in range(16):
        out[actor] = sum(
            1 for i in WEAPON_IDS
            if (int.from_bytes(data[i * 30 + 1:i * 30 + 3], "little")
                >> actor) & 1)
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default="build/states")
    ap.add_argument("--repo", default=".")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()

    waivers = load_waivers(args.repo, WAIVERS)
    used = set()
    canhold = equippable_weapons(args.repo)
    cannot = sorted(c for c, n in canhold.items()
                    if n <= 1 and c in NAMES)

    files = sorted(glob.glob(os.path.join(args.dir, "*.mss")))
    if not files:
        print(f"audit_equipment: no fixtures under {args.dir}")
        return 0

    # Same reason as the party-hp audit: a .mss the graph no longer declares
    # is a rename leftover, and a finding in one cannot be fixed by editing
    # any generator.  savestate_party.declared_states has the case.
    files, orphans = split_orphans(files, declared_states(args.repo))
    if not files:
        print(f"audit_equipment: {len(orphans)} fixture(s) under {args.dir} "
              f"and the graph declares NONE of them.  That is the filter "
              f"broken, not a clean tree;\nrefusing to report green over "
              f"nothing.  Check {args.dir} and tools/tests/savestate_graph.py "
              f"agree on names.")
        return 1

    scanned, skipped, bad = 0, [], []
    for p in files:
        party, err = read_party(p)
        if err:
            skipped.append((os.path.basename(p), err))
            continue
        scanned += 1
        stem = stem_of(p)
        naked = []
        for m in party:
            if m["weapon"] != EMPTY or canhold.get(m["char"], 99) <= 1:
                continue
            key = (stem, m["name"])
            if key in waivers:
                used.add(key)
                continue
            naked.append(m)
        if naked:
            bad.append((os.path.basename(p), party, naked))
        elif args.verbose:
            who = " ".join(f"{m['name']}={m['weapon']:02X}" for m in party)
            print(f"  ok   {os.path.basename(p):34s} {who}")

    print(f"equipment audit: {scanned} fixtures read"
          + (f", {len(skipped)} unreadable" if skipped else ""))
    if cannot:
        print("  (bare is EXPECTED and not reported for "
              + ", ".join(f"{NAMES[c]} ({canhold[c]} weapon record"
                          + ("s" if canhold[c] != 1 else "") + ")"
                          for c in cannot)
              + " -- the equip mask says so)")
    for name, err in skipped:
        print(f"  ?    {name}: {err}")
    if orphans:
        print(f"  ({len(orphans)} file(s) in {args.dir} that the graph no "
              f"longer declares, SKIPPED -- they are pre-rename leftovers "
              f"and\n   nothing regenerates them; delete them: "
              + ", ".join(orphans) + ")")

    for name, party, naked in bad:
        who = ", ".join(f"{m['name']} (L{m['level']}, {m['hp']}/{m['maxhp']})"
                        for m in naked)
        print(f"  BARE {name}: {who}")
        for m in party:
            gear = " ".join(f"{g:02X}" for g in m["gear"])
            print(f"         {m['name']:7s} gear {gear}")

    stale = sorted(set(waivers) - used)
    if stale:
        print(f"\n{len(stale)} waiver(s) match nothing any more -- delete "
              f"them; the burn-down only shrinks:")
        for fix, who in stale:
            print(f"  {fix}: {who}")
        return 1

    if bad:
        print(f"\n{len(bad)} fixture(s) hand a party member NOTHING TO FIGHT "
              f"WITH.  A bare-handed character reads exactly like a balance\n"
              f"wall -- solo LOCKE punched a 495-hp HeavyArmor for 8 a swing "
              f"before anyone looked.  Give the step an H.equipOptimum stop.")
        return 1
    print("  OK -- everybody in every party is holding something")
    return 0


if __name__ == "__main__":
    sys.exit(main())
