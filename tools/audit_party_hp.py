#!/usr/bin/env python3
"""Report fixtures that ship a party member dead or one hit from it.

Why this exists.  `returner_hideout` shipped with half the party dead: TERRA
at 0/136 and LOCKE at 0/168, five Fenix Downs unused in the bag, and no
healing stop anywhere in the route that made it.  Two steps later a story
event cut the party down to TERRA alone, so a room with no encounters in it
produced a party wipe, and the wipe was investigated as a bug in the room.
It cost a day.  Nothing in the tree would have caught it: of about
sixty-eight generators that fight battles, three assert that their party is
alive when they finish.

This is the check that catches the whole class, and it is the sibling of
tools/audit_equipment.py in every respect -- it reads the .mss files
directly with no emulator (the whole tree in about a second, against a
`make savestates` measured in hours), it runs unconditionally in `make
test`, and it carries a waiver list that may only shrink, where an entry
matching nothing fails as stale.

WHERE THE LINE IS, AND WHY THERE

Three conditions fail, and they are the game's own, not invented here:

  - **Dead**: current HP 0, or wound in status 1.
  - **Petrified or zombie**: the other two bits in `$C2`, which is the mask
    the game itself applies when it asks whether a character can be healed
    (CheckCanUseItem, `ff6/src/menu/item.asm:2249-2258`) or picked for
    Skills (CheckSkillValid, `ff6/src/menu/field_menu.asm:722-731`).  A
    petrified character is not dead and cannot be revived with a Fenix Down
    either; shipping one is the same failure wearing a different status bit.
  - **Near fatal**: current HP at or below max HP / 8.  That is the game's
    arithmetic, not a number picked to fit: `lda $3c1c,y` (max HP), `lsr3`,
    `cmp $3bf4,y` (current HP), and near-fatal goes into the status-to-set
    when the carry says max/8 >= current (`ff6/src/battle/battle_main.asm:
    11544-11549`).

Near fatal rather than dead-only, because a member at 15 of 231 is not a
survivor, it is a casualty the next random encounter has already claimed,
and the room that kills it will be investigated as a hard room.  Near fatal
rather than something stricter, because a check that fires on ordinary wear
gets waived into uselessness, and the data says the gap is wide: across the
98 fixtures in the tree on 2026-08-11 there were 241 party records, and
sorted by fraction of max HP they run 0%, 6.5%, then nothing at all until
36.6%, 36.6%, 38.5%, 48.4% and up.  Max/8 is 12.5%, which sits in the empty
middle of that gap with room on both sides.  A half-HP bar would have named
six fixtures, four of them for wear that no player would stop to heal.

Half HP *is* the right bar in one place and it is already there: gen_kolts
and gen_returner assert it as the entry contract for a specific fight they
know the cost of.  That is a different question from this one.  This check
is "did the chain ship a casualty", asked of every fixture including ones
with no fight anywhere near them; a per-fight readiness bar belongs in the
generator that knows which fight is next.

MP is deliberately not checked here for the same reason.  gen_kolts asserts
TERRA reaches VARGAS with two thirds of her MP because it knows VARGAS needs
her Cures; there is no tree-wide MP number that means anything.

WHO COUNTS AS IN THE PARTY

`$1850 + c` low three bits nonzero, which during the three-scenario split is
true of all three parties at once and not only the one the player is
steering.  That is on purpose: at `kefka_doorstep` the player holds party 1
and parties 2 and 3 are queued behind the same fight, so a casualty in
either is shipping just as much as one on screen.  The report says which
party each finding is in and marks the active one.

Usage:  python3 tools/audit_party_hp.py [--dir build/states] [--selftest] [-v]
Exit 0 clean, 1 if any fixture ships a casualty or carries a stale waiver.
"""

from __future__ import annotations

import argparse
import glob
import os
import sys

# Explicit rather than relying on sys.path[0], which PYTHONSAFEPATH and
# `python3 -P` both switch off.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from savestate_party import (ST1_PETRIFY, ST1_WOUND, ST1_ZOMBIE, load_waivers,
                             read_party, stem_of)

WAIVERS = "tools/party_hp_waivers.txt"


def near_fatal_floor(maxhp: int) -> int:
    """The highest current HP the game still calls near fatal.

    `battle_main.asm:11544-11549` shifts max HP right three times and
    compares; the branch sets near-fatal when max/8 >= current, so the floor
    is inclusive and integer-truncated exactly as the shifts leave it.
    """
    return maxhp >> 3


def classify(m: dict) -> str | None:
    """Why this member must not ship, or None if they are fine.

    Order matters only for the report: a wounded character is also at zero
    HP and also below max/8, and naming them "DEAD" is more use than naming
    them near fatal.
    """
    st1 = m["status1"]
    if m["hp"] == 0 or st1 & ST1_WOUND:
        return "DEAD"
    if st1 & ST1_PETRIFY:
        return "PETRIFIED"
    if st1 & ST1_ZOMBIE:
        return "ZOMBIE"
    if m["maxhp"] and m["hp"] <= near_fatal_floor(m["maxhp"]):
        return "NEAR FATAL"
    return None


def describe(m: dict) -> str:
    where = f"party {m['party']}" + (", the active one" if m["active"] else "")
    return (f"{m['name']} L{m['level']} {m['hp']}/{m['maxhp']} hp "
            f"(<={near_fatal_floor(m['maxhp'])} is near fatal), "
            f"status1 {m['status1']:02X}, {where}")


# ---------------------------------------------------------------- selftest --
# Without this, a classify() that had been broken into always returning None
# would report the same clean green as a tree that is genuinely clean, and
# the fixtures are generated state that no unit test can stand in for.  This
# is the part that fails when the check stops checking.

def selftest() -> int:
    def rec(hp, maxhp, st1=0x00, **kw):
        d = {"name": "TERRA", "level": 9, "hp": hp, "maxhp": maxhp,
             "status1": st1, "party": 1, "active": True}
        d.update(kw)
        return d

    cases = [
        # the three findings this check was written for, as measured
        (rec(0, 217, 0x80), "DEAD", "kefka_doorstep CELES"),
        (rec(0, 136), "DEAD", "returner_hideout TERRA, HP zero"),
        (rec(15, 231), "NEAR FATAL", "camp_escaped SABIN, 6.5%"),
        # the boundary, both sides of it: 231 >> 3 == 28, inclusive
        (rec(28, 231), "NEAR FATAL", "exactly max/8 is near fatal"),
        (rec(29, 231), None, "one hp above max/8 is not"),
        # ordinary wear the tree really contains, which must stay quiet
        (rec(91, 249), None, "zozo_arrival LOCKE at 36.6%"),
        (rec(47, 122), None, "figaro_cleared LOCKE at 38.5%"),
        (rec(123, 254), None, "s2_camp_escaped CYAN at 48.4%"),
        (rec(186, 186), None, "untouched"),
        # the other two bits of the game's own $C2 mask
        (rec(200, 217, 0x40), "PETRIFIED", "petrify"),
        (rec(200, 217, 0x02), "ZOMBIE", "zombie"),
        # magitek ($08) is 18 records in the tree and is not a casualty
        (rec(147, 231, 0x08), None, "magitek status alone"),
    ]
    bad = []
    for m, want, what in cases:
        got = classify(m)
        if got != want:
            bad.append(f"{what}: expected {want}, got {got}")
    if near_fatal_floor(231) != 28:
        bad.append("near_fatal_floor(231) should be 28")
    for line in bad:
        print(f"  SELFTEST FAIL {line}")
    print(f"audit_party_hp selftest: {len(cases)} cases, "
          f"{len(bad)} failed")
    return 1 if bad else 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default="build/states")
    ap.add_argument("--repo", default=".")
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()

    if args.selftest:
        return selftest()

    waivers = load_waivers(args.repo, WAIVERS)
    used = set()

    files = sorted(glob.glob(os.path.join(args.dir, "*.mss")))
    if not files:
        print(f"audit_party_hp: no fixtures under {args.dir}")
        return 0

    scanned, skipped, bad = 0, [], []
    for p in files:
        party, err = read_party(p)
        if err:
            skipped.append((os.path.basename(p), err))
            continue
        scanned += 1
        stem = stem_of(p)
        hurt = []
        for m in party:
            why = classify(m)
            if why is None:
                continue
            key = (stem, m["name"])
            if key in waivers:
                used.add(key)
                continue
            hurt.append((m, why))
        if hurt:
            bad.append((stem, party, hurt))
        elif args.verbose:
            who = " ".join(f"{m['name']}={m['hp']}/{m['maxhp']}"
                           for m in party)
            print(f"  ok   {stem:34s} {who}")

    print(f"party hp audit: {scanned} fixtures read"
          + (f", {len(skipped)} unreadable" if skipped else ""))
    for name, err in skipped:
        print(f"  ?    {name}: {err}")

    for stem, party, hurt in bad:
        for m, why in hurt:
            print(f"  {why:10s} {stem}: {describe(m)}")
        for m in party:
            print(f"         {m['name']:7s} {m['hp']:5d}/{m['maxhp']:<5d} hp "
                  f"{m['mp']:4d}/{m['maxmp']:<4d} mp  "
                  f"status {m['status1']:02X}/{m['status4']:02X}  "
                  f"party {m['party']}{'*' if m['active'] else ''}")

    stale = sorted(set(waivers) - used)
    if stale:
        print(f"\n{len(stale)} waiver(s) match nothing any more -- delete "
              f"them; the burn-down only shrinks:")
        for fix, who in stale:
            print(f"  {fix}: {who}")
        return 1

    if bad:
        print(f"\n{len(bad)} fixture(s) SHIP A CASUALTY.  A fixture with a "
              f"dead character in it is not a savestate of the story getting\n"
              f"somewhere; it is a savestate of the route losing on the way, "
              f"and every step that boots from it inherits the loss.  This\n"
              f"is how returner_hideout produced a party wipe in a room with "
              f"no encounters: a story event cut the party down to the one\n"
              f"member who was already dead.  Give the step where the damage "
              f"happens an H.fieldCare stop, and give the generator an exit\n"
              f"assertion so it fails loudly instead of shipping the fixture.")
        return 1
    print("  OK -- every party member in every fixture is on their feet")
    return 0


if __name__ == "__main__":
    sys.exit(main())
