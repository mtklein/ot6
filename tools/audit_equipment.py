#!/usr/bin/env python3
"""Report party members who are walking the story bare-handed.

The game strips characters and returns their gear to the inventory at story
beats (`remove_equip` / EventCmd_8d), and a generated savestate can carry
that forward uncorrected.  Reads the savestate directly, with no emulator,
via `savestate_party.py` (shared with `audit_party_hp.py`); the record used
is +$1F weapon and +$20..+$23 the rest, where $FF means empty.

Usage:  python3 tools/audit_equipment.py [--dir build/states] [-v]
Exit 0 clean, 1 if anybody in a party is holding nothing.
"""

from __future__ import annotations

import argparse
import glob
import os
import sys

# sys.path[0] is unreliable under PYTHONSAFEPATH / `python3 -P`.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from savestate_party import (EMPTY, NAMES, declared_states, load_waivers,
                             read_party, split_orphans, stem_of)

WAIVERS = "tools/equipment_waivers.txt"
ITEM_PROP = "ff6/src/menu/item_prop_en.dat"

ITEM_REC = 30                # bytes per item_prop_en.dat record
ITEM_TYPE_WEAPON = 0x01      # ItemProp +$00 & $07


def equippable_weapons(repo: str) -> dict[int, int]:
    """How many weapon records each actor may hold, read from the ROM data.

    Mirrors the game's own `GetValidWeapons` reads (`ff6/src/menu/
    equip.asm:1594-1601`): a record is a weapon when `ItemProp +$00 & $07 ==
    $01`, and the equip mask is the 16-bit field at +$01, bit N = actor N.
    An actor who can hold one weapon or none cannot be re-equipped and must
    not be reported as a finding.  Record $FF (the empty-slot sentinel) is
    skipped: it is typed as a weapon with a mask that claims actors 0-7.
    """
    path = os.path.join(repo, ITEM_PROP)
    try:
        data = open(path, "rb").read()
    except OSError:
        return {}
    out = {}
    for actor in range(16):
        out[actor] = sum(
            1 for i in range(0x100)
            if i != EMPTY
            and (data[i * ITEM_REC] & 0x07) == ITEM_TYPE_WEAPON
            and (int.from_bytes(data[i * ITEM_REC + 1:i * ITEM_REC + 3],
                                "little") >> actor) & 1)
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

    # A .mss the graph no longer declares is a rename leftover.
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
              f"before anyone looked.  Give the step an equip stop that names\n"
              f"the items it wants; Optimum picks by attack power and knows "
              f"nothing about elements, weapon class, or who swings.")
        return 1
    print("  OK -- everybody in every party is holding something")
    return 0


if __name__ == "__main__":
    sys.exit(main())
