#!/usr/bin/env python3
"""Report fixtures that ship a party member dead, one hit from it, or poisoned.

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

It reads the tracked SRAM checkpoints too, and that half is not an extra.
A checkpoint is the other thing a generator can boot from -- five states
cold-Continue out of one instead of resuming a predecessor's .mss -- so a
casualty in one is inherited just as widely, and it is worse to leave
uncaught: a checkpoint is a binary tracked in git, so no `make savestates`
ever refreshes it, and it goes on handing over the same dead characters
until somebody re-captures it.  Four were sitting there when this half was
added.  The report keeps them separate from the fixtures because the
remedy is different in kind; the closing message says what it is.

WHERE THE LINE IS, AND WHY THERE

Four conditions fail, and they are the game's own, not invented here:

  - **Dead**: current HP 0, or wound in status 1.
  - **Petrified or zombie**: the other two bits in `$C2`, which is the mask
    the game itself applies when it asks whether a character can be healed
    (CheckCanUseItem, `ff6/src/menu/item.asm:2249-2258`) or picked for
    Skills (CheckSkillValid, `ff6/src/menu/field_menu.asm:722-731`).  A
    petrified character is not dead and cannot be revived with a Fenix Down
    either; shipping one is the same failure wearing a different status bit.
  - **Poisoned**: `$04` in status 1.  Poison is not in the game's own
    can-be-healed mask and does not belong there -- the menu serves a
    poisoned character perfectly well -- but it is the one status the act of
    walking converts into a casualty.  DoPoisonDmg drains max HP/32
    from every poisoned character on every step and floors the result at 1
    (`ff6/src/field/player.asm:593-613`), so a character who leaves a fight
    poisoned reaches the end of any walk of length at exactly 1 HP no matter
    what they had when the fight ended.  banon_joined and lete_river are the
    measured case: TERRA at 1 of 136 with status 04 after five crossings of
    a Returner Hideout that cannot draw an encounter at all (its map_prop
    byte `$0525` has bit 7 clear, `ff6/src/field/battle.asm:332-333`).  The
    near-fatal clause below did catch them, but only at the far end of the
    grind; this clause names the bit at the fixture that first carries it,
    which is the fixture whose generator can still do something about it.
  - **Near fatal**: current HP at or below max HP / 8.  That is the game's
    arithmetic, not a number picked to fit: `lda $3c1c,y` (max HP), `lsr3`,
    `cmp $3bf4,y` (current HP), and near-fatal goes into the status-to-set
    when the carry says max/8 >= current (`ff6/src/battle/battle_main.asm:
    11544-11549`).

Poison is curable on the route, so this is a bar the tree can meet rather
than one it can only waive: `M.fieldCare` learned the Antidote alongside
this clause, and shop 8 in South Figaro -- the shop gen_kolts already walks
into -- stocks Antidotes on row 1 (`ff6/src/menu/shop_prop.dat` record 8).

Near fatal rather than dead-only, because a member at 15 of 231 is not a
survivor, it is a casualty the next random encounter has already claimed,
and the room that kills it will be investigated as a hard room.  Near fatal
rather than something stricter, because a check that fires on ordinary wear
gets waived into uselessness, and the data says the gap is wide: across the
98 .mss files in build/states on 2026-08-11 there were 241 party records, and
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
steering.  That is on purpose: at `kefka_entry` the player holds party 1
and parties 2 and 3 are queued behind the same fight, so a casualty in
either is shipping just as much as one on screen.  The report says which
party each finding is in and marks the active one.

WHICH FILES COUNT AS FIXTURES

Only the ones tools/tests/savestate_graph.py still declares.  build/states
outlives the graph -- renaming a state leaves the old .mss sitting there
forever -- and on 2026-08-12 nineteen of the ninety-eight files in it were
leftovers.  One of them, `kefka_doorstep`, was a pre-rename copy of
`kefka_entry` from before gen_narshe_battle got its care stop, and it named
CELES dead at 0/217: a casualty in a route that no longer exists, that no
regeneration can clear and no generator edit can fix.  It was worked as a
live bug.  savestate_party.declared_states carries the rest of that story.

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
# Without this, a classify() that had been broken into always returning None
# would report the same clean green as a tree that is genuinely clean, and
# the fixtures are generated state that no unit test can stand in for.  This
# is the part that fails when the check stops checking.

def selftest(repo: str = ".") -> int:
    def rec(hp, maxhp, st1=0x00, **kw):
        d = {"name": "TERRA", "level": 9, "hp": hp, "maxhp": maxhp,
             "status1": st1, "party": 1, "active": True}
        d.update(kw)
        return d

    cases = [
        # the three findings this check was written for, as measured
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
        # poison, which the HP alone cannot report.  The first case is the
        # one the near-fatal clause never sees: TERRA the moment the fight
        # that poisoned her ends, still at 118 of 136, on a route with a
        # hideout to walk.  The second is the same character at the far end
        # of that walk, which is what banon_joined and lete_river shipped.
        (rec(118, 136, 0x04), "POISONED", "poisoned and nowhere near fatal"),
        (rec(1, 136, 0x04), "POISONED", "banon_joined TERRA, ground to 1"),
        # and dead-with-poison is still reported as dead: a Fenix Down is
        # the only thing the game will accept there (item.asm:2282-2286)
        (rec(0, 136, 0x84), "DEAD", "wound wins over poison"),
        # magitek ($08) is 18 records in the tree and is not a casualty
        (rec(147, 231, 0x08), None, "magitek status alone"),
        # nor is dark ($01) or imp ($20): both are combat handicaps that
        # walking does not make worse, which is the whole basis for poison
        # being in the list and them not being in it
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

    # The orphan filter.  Without these three the filter can quietly become
    # a no-op -- declared_states swallows any exception and returns an empty
    # set, and split_orphans treats an empty set as "audit everything" -- so
    # a graph this stops being able to read would put kefka_doorstep back in
    # the report with no sign that anything changed.
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
    # And this is the clause that fails if the graph file moves, or S()
    # stops carrying a "state" key: an empty set here is indistinguishable
    # from a clean tree everywhere else.
    declared = declared_states(repo)
    if "kefka_entry" not in declared or len(declared) < 50:
        bad.append(f"declared_states({repo!r}) should read "
                   f"tools/tests/savestate_graph.py and find kefka_entry "
                   f"among ~114 states, got {len(declared)}")

    # The checkpoint half.  It reads files that are tracked in git rather
    # than generated, so "no checkpoints found" and "all checkpoints clean"
    # print the same nothing -- these two are what tell them apart.
    payloads = dict(checkpoint_payloads(repo))
    if "n024-entry-save-v1" not in payloads or len(payloads) < 5:
        bad.append(f"checkpoint_payloads({repo!r}) should find "
                   f"n024-entry-save-v1 among the tracked checkpoints, "
                   f"got {sorted(payloads)}")
    else:
        party, err = read_party_sram(payloads["n024-entry-save-v1"])
        # The four records the emulator independently logged out of live
        # WRAM after booting this checkpoint.  If the save layout ever
        # moves, this is what says so instead of the reader quietly
        # locating the wrong table or none at all.
        #
        # Updated 2026-08-12 because the checkpoint itself was re-captured,
        # not because the reader changed.  It used to hand over EDGAR and
        # SABIN dead (0/398 and 0/407, status $80), which is the defect the
        # re-capture cleared: battle 70 stopped killing them once the fight
        # driver began casting CELES's cures instead of drinking, so the
        # segment's two Fenix Downs are no longer spent on arrival.  SABIN
        # at 278/363 is the fight's ordinary wear.  The expectation follows
        # the measurement here; the reader is still what is under test.
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
    # fixtures: no generator writes them, so a casualty in one names a route
    # that no longer exists and cannot be fixed by editing anything.  See
    # savestate_party.declared_states for the case that put this here.
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

    # The checkpoints are the other thing a generator can boot from, and a
    # casualty in one is inherited by everything below it exactly as a
    # casualty in a fixture is.  They are reported apart from the fixtures
    # because the remedy is different: a fixture is repaired by editing its
    # generator and regenerating, while a checkpoint is a tracked binary in
    # git and has to be re-captured through its own chain.
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
