#!/usr/bin/env python3
"""Report fixtures that ship a party member dead, one hit from it, or poisoned.

Reads the .mss files directly with no emulator, and reads the tracked SRAM
checkpoints too (the other thing a generator can boot from).  Carries a
waiver list that may only shrink; an entry matching nothing fails as stale.

A party member fails one of four conditions, the game's own:

  - **Dead**: current HP 0, or wound in status 1.
  - **Petrified or zombie**: the other two bits in `$C2`, the mask the game
    itself applies for CheckCanUseItem (`ff6/src/menu/item.asm:2249-2258`)
    and CheckSkillValid (`ff6/src/menu/field_menu.asm:722-731`).
  - **Poisoned**: `$04` in status 1.  DoPoisonDmg drains max HP/32 from every
    poisoned character on every step and floors the result at 1
    (`ff6/src/field/player.asm:593-613`).
  - **Near fatal**: current HP at or below max HP / 8, matching the game's
    own arithmetic for the near-fatal status
    (`ff6/src/battle/battle_main.asm:11544-11549`).

WHO COUNTS AS IN THE PARTY

`$1850 + c` low three bits nonzero, true of all three parties at once during
the three-scenario split.  The report says which party each finding is in
and marks the active one.

WHICH FILES COUNT AS FIXTURES

Only the ones tools/tests/savestate_graph.py still declares; files it no
longer declares are skipped as orphans.

Usage:  python3 tools/audit_party_hp.py [--dir build/states] [--selftest] [-v]
Exit 0 clean, 1 if any fixture or checkpoint ships a casualty, or if a
waiver has gone stale.
"""

from __future__ import annotations

import argparse
import glob
import os
import sys

# Explicit rather than relying on sys.path[0], which PYTHONSAFEPATH and
# `python3 -P` both switch off.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from savestate_party import (ST1_PETRIFY, ST1_POISON, ST1_WOUND, ST1_ZOMBIE,
                             checkpoint_payloads, declared_states,
                             load_waivers, read_party, read_party_sram,
                             split_orphans, stem_of)

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
    # Ahead of NEAR FATAL, because a poisoned character at 1 HP is both and
    # only one of the two labels says what to do about it.  The HP is in
    # describe() either way.
    if st1 & ST1_POISON:
        return "POISONED"
    if m["maxhp"] and m["hp"] <= near_fatal_floor(m["maxhp"]):
        return "NEAR FATAL"
    return None


def describe(m: dict) -> str:
    where = f"party {m['party']}" + (", the active one" if m["active"] else "")
    return (f"{m['name']} L{m['level']} {m['hp']}/{m['maxhp']} hp "
            f"(<={near_fatal_floor(m['maxhp'])} is near fatal), "
            f"status1 {m['status1']:02X}, {where}")


# ---------------------------------------------------------------- selftest --

def selftest(repo: str = ".") -> int:
    def rec(hp, maxhp, st1=0x00, **kw):
        d = {"name": "TERRA", "level": 9, "hp": hp, "maxhp": maxhp,
             "status1": st1, "party": 1, "active": True}
        d.update(kw)
        return d

    cases = [
        (rec(0, 217, 0x80), "DEAD", "kefka_entry CELES"),
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
        # poison, which the HP alone cannot report
        (rec(118, 136, 0x04), "POISONED", "poisoned and nowhere near fatal"),
        (rec(1, 136, 0x04), "POISONED", "banon_joined TERRA, ground to 1"),
        # and dead-with-poison is still reported as dead: a Fenix Down is
        # the only thing the game will accept there (item.asm:2282-2286)
        (rec(0, 136, 0x84), "DEAD", "wound wins over poison"),
        # magitek ($08) alone is not a casualty
        (rec(147, 231, 0x08), None, "magitek status alone"),
        # nor is dark ($01) or imp ($20)
        (rec(147, 231, 0x01), None, "dark alone"),
        (rec(147, 231, 0x20), None, "imp alone"),
    ]
    bad = []
    for m, want, what in cases:
        got = classify(m)
        if got != want:
            bad.append(f"{what}: expected {want}, got {got}")
    if near_fatal_floor(231) != 28:
        bad.append("near_fatal_floor(231) should be 28")

    live, orph = split_orphans(
        ["build/states/kefka_entry.mss", "build/states/kefka_doorstep.mss"],
        {"kefka_entry"})
    if live != ["build/states/kefka_entry.mss"] or orph != ["kefka_doorstep"]:
        bad.append(f"split_orphans should keep kefka_entry and drop the "
                   f"pre-rename kefka_doorstep, got live={live} orphans={orph}")
    live, orph = split_orphans(["build/states/anything.mss"], set())
    if live != ["build/states/anything.mss"] or orph != []:
        bad.append("an unreadable graph must audit everything and orphan "
                   f"nothing, got live={live} orphans={orph}")
    declared = declared_states(repo)
    if "kefka_entry" not in declared or len(declared) < 50:
        bad.append(f"declared_states({repo!r}) should read "
                   f"tools/tests/savestate_graph.py and find kefka_entry "
                   f"among ~114 states, got {len(declared)}")

    payloads = dict(checkpoint_payloads(repo))
    if "n024-entry-save-v1" not in payloads or len(payloads) < 5:
        bad.append(f"checkpoint_payloads({repo!r}) should find "
                   f"n024-entry-save-v1 among the tracked checkpoints, "
                   f"got {sorted(payloads)}")
    else:
        party, err = read_party_sram(payloads["n024-entry-save-v1"])
        # The four records the emulator independently logged out of live
        # WRAM after booting this checkpoint.
        want = {"LOCKE": (314, 314, 0x00), "EDGAR": (354, 354, 0x00),
                "SABIN": (278, 363, 0x00), "CELES": (151, 349, 0x00)}
        got = {m["name"]: (m["hp"], m["maxhp"], m["status1"])
               for m in (party or [])}
        if err or got != want:
            bad.append(f"read_party_sram(n024-entry-save-v1) should read the "
                       f"four records the emulator logged from it, "
                       f"got {err or got}")

    for line in bad:
        print(f"  SELFTEST FAIL {line}")
    print(f"audit_party_hp selftest: {len(cases) + 5} cases, "
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
        return selftest(args.repo)

    waivers = load_waivers(args.repo, WAIVERS)
    used = set()

    files = sorted(glob.glob(os.path.join(args.dir, "*.mss")))
    if not files:
        print(f"audit_party_hp: no fixtures under {args.dir}")
        return 0

    # Files the graph no longer declares are leftovers from a rename, not
    # fixtures: no generator writes them.
    files, orphans = split_orphans(files, declared_states(args.repo))
    if not files:
        print(f"audit_party_hp: {len(orphans)} fixture(s) under {args.dir} "
              f"and the graph declares NONE of them.  That is the filter "
              f"broken, not a clean tree;\nrefusing to report green over "
              f"nothing.  Check {args.dir} and tools/tests/savestate_graph.py "
              f"agree on names.")
        return 1

    def casualties(name: str, party: list) -> list:
        """The members of one party that must not ship, waivers applied."""
        hurt = []
        for m in party:
            why = classify(m)
            if why is None:
                continue
            key = (name, m["name"])
            if key in waivers:
                used.add(key)
                continue
            hurt.append((m, why))
        return hurt

    scanned, skipped, bad = 0, [], []
    for p in files:
        party, err = read_party(p)
        if err:
            skipped.append((os.path.basename(p), err))
            continue
        scanned += 1
        stem = stem_of(p)
        hurt = casualties(stem, party)
        if hurt:
            bad.append((stem, party, hurt))
        elif args.verbose:
            who = " ".join(f"{m['name']}={m['hp']}/{m['maxhp']}"
                           for m in party)
            print(f"  ok   {stem:34s} {who}")

    # Checkpoints are reported apart from fixtures: the remedy differs (a
    # fixture regenerates; a checkpoint is a tracked binary re-captured
    # through its own chain).
    cp_scanned, cp_skipped, cp_bad = 0, [], []
    for name, payload in checkpoint_payloads(args.repo):
        party, err = read_party_sram(payload)
        if err:
            cp_skipped.append((name, err))
            continue
        cp_scanned += 1
        hurt = casualties(name, party)
        if hurt:
            cp_bad.append((name, party, hurt))
        elif args.verbose:
            who = " ".join(f"{m['name']}={m['hp']}/{m['maxhp']}"
                           for m in party)
            print(f"  ok   {name:34s} {who}  (checkpoint)")

    print(f"party hp audit: {scanned} fixtures read"
          + (f", {len(skipped)} unreadable" if skipped else "")
          + f"; {cp_scanned} checkpoints read"
          + (f", {len(cp_skipped)} unreadable" if cp_skipped else ""))
    for name, err in skipped:
        print(f"  ?    {name}: {err}")
    for name, err in cp_skipped:
        print(f"  ?    checkpoint {name}: {err}")
    if orphans:
        print(f"  ({len(orphans)} file(s) in {args.dir} that the graph no "
              f"longer declares, SKIPPED -- they are pre-rename leftovers "
              f"and\n   nothing regenerates them; delete them: "
              + ", ".join(orphans) + ")")

    def report(entries, what):
        for name, party, hurt in entries:
            for m, why in hurt:
                print(f"  {why:10s} {what}{name}: {describe(m)}")
            for m in party:
                print(f"         {m['name']:7s} "
                      f"{m['hp']:5d}/{m['maxhp']:<5d} hp "
                      f"{m['mp']:4d}/{m['maxmp']:<4d} mp  "
                      f"status {m['status1']:02X}/{m['status4']:02X}  "
                      f"party {m['party']}{'*' if m['active'] else ''}")

    report(bad, "")
    report(cp_bad, "checkpoint ")

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
              f"assertion so it fails loudly instead of shipping the fixture.\n"
              f"A POISONED line wants the same two things and one more: the "
              f"Antidote has to be IN the bag for fieldCare to reach for it,\n"
              f"and poison drains max HP/32 every step "
              f"(ff6/src/field/player.asm:593-613), so a fixture that ships "
              f"the bit\nhands the next generator a character at 1 HP however "
              f"healthy this one's HP column looks.")
    if cp_bad:
        print(f"\n{len(cp_bad)} CHECKPOINT(s) SHIP A CASUALTY, which is the "
              f"same defect one level down and costs more to clear.  A\n"
              f"checkpoint is a tracked battery image in git, so no "
              f"regeneration touches it: every state that cold-Continues out\n"
              f"of one starts from these bytes and inherits the loss, and the "
              f"segment then spends its revives undoing it.  Measured at\n"
              f"n024-entry-save-v1: it hands over EDGAR and SABIN dead, the "
              f"care stop before battle 72 spends both of the segment's two\n"
              f"Fenix Downs raising them, and when CELES dies in the fight "
              f"there is nothing left to raise her with -- no esper grants\n"
              f"Life anywhere in the WoB -- so esper_tubes_entry ships her at "
              f"0/349 and no care stop in that generator can fix it.\n"
              f"The repair is to re-capture the checkpoint through its own "
              f"chain with a care stop in the generator that writes it, and\n"
              f"an H.assertPartyStanding before it saves.  Do not waive one: "
              f"a supply that ran out is a finding, not a story.")
    if bad or cp_bad:
        return 1
    print("  OK -- every party member in every fixture and checkpoint is on "
          "their feet")
    return 0


if __name__ == "__main__":
    sys.exit(main())
