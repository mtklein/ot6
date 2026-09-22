#!/usr/bin/env python3
"""Report a fixture that lost its last revive crossing a boundary, and warn
where the bag is under the Potion band or the Tonic band.

Flags a fixture with zero Fenix Downs whose predecessor (named by the graph's
`prev=` or `checkpoint=` edge) carried some; a root fixture is not audited.
Revival in the WoB is a Fenix Down only. Inventory is located off the
character-table anchor ($1869 ids / $1969 counts, offset past $1600).

The Potion band (docs/design/level-curve.md, "The supply curve"): Potions
are the in-combat heal, carried at ~level x1.5 (minimum 10) from the first
town on the route that sells them -- the Phantom Train's ghost merchant, so
the band is measured from `train_done` on (a fixture whose `prev` chain
reaches it, or one rooted at a checkpoint, all of which lie downstream).
It is a World of Balance band: it ends at the WoR landing (the graph row
that generates `wor_landing`, its `also=` siblings included, and anything
downstream of it), where the party, the shops and the level curve are all
different.  A fixture under the band is a WARNING (listed, exit code
unaffected); the fix is a `POTION to N` line at the shop stop before it.

The Tonic band (the same section, #210): Tonics are the field-care heal,
carried at ~level x5 (cap 99) from the first town that sells them --
Figaro Castle's shop 4, bought in `gen_edgar`'s run (the `figaro_intro`
row and its `also=` siblings) -- to the same WoR landing.  Under it is a
WARNING too; the fix is a `TONIC to N` line at a shop that sells them, or,
where the route reaches none, the Potion target sized for the field care.

The Tincture band (docs/design/supply.md, #231): Tinctures are the
field-care MP restore, carried at ~level / 4 rounded up (one caster's
pool per stretch) from the first counter whose purse can carry them --
Narshe's shop 3, bought in `gen_zozo1_submerge`'s run (the
`figaro_submerged` row) -- to the same WoR landing.  Figaro Castle sells
them earlier and its purse cannot (supply.md, squeeze 1), so the band
starts at Narshe.  Under it is a WARNING; the fix is a `TINCTURE to N`
line at a counter that sells them (Narshe 3, Jidoor 22, Albrook 24,
Thamasa 35).

Usage:  python3 tools/audit_supplies.py [--repo .] [--selftest] [-v]
Exit 0 clean, 1 if a fixture dropped to no revives across a boundary, or if a
waiver has gone stale.
"""

from __future__ import annotations

import argparse
import functools
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from savestate_party import (biggest_stream, checkpoint_payloads,
                             declared_states, find_char_block, party_at)

WAIVERS = "tools/supply_waivers.txt"

FENIX_DOWN = 0xF0                      # the WoB's only revival, item id $F0
POTION = 0xE9                          # the in-combat heal, item id $E9
TONIC = 0xE8                           # the field-care heal, item id $E8
TINCTURE = 0xEB                        # the field-care MP restore, item id $EB
INV_IDS = 0x1869 - 0x1600             # inventory ids, offset past the char table
INV_QTY = 0x1969 - 0x1600             # inventory counts, one byte each

# The first fixture past a shop that sells Potions on the routed run:
# the Phantom Train's ghost merchant (shop 85).  Figaro's shop 4 and South
# Figaro's shop 8 stock none (shop_prop.dat), so the band applies from here.
FIRST_POTION_SHOP = "train_done"
POTION_BAND_MIN = 10
# The graph row whose run first buys Tonics (Figaro Castle's shop 4); the
# row's `also=` artifacts carry the row name, so all three are in band.
FIRST_TONIC_SHOP_ROW = "figaro_intro"
TONIC_BAND_CAP = 99
# The graph row whose run first buys Tinctures (Narshe's shop 3, after the
# Battle for Narshe).
FIRST_TINCTURE_SHOP_ROW = "figaro_submerged"
# The band is a WoB band: the graph row that generates this state (with its
# `also=` artifacts, escape_start today) and everything downstream of it is
# the World of Ruin, out of band.
WOR_LANDING = "wor_landing"


def count_in(raw: bytes, cb: int, item: int) -> int:
    """How many of `item` the bag holds, given the blob and the $1600 anchor.

    The inventory is 256 (id, count) slots at a fixed offset past the
    character table.
    """
    total = 0
    for i in range(256):
        if raw[cb + INV_IDS + i] == item:
            total += raw[cb + INV_QTY + i]
    return total


def revives_in(raw: bytes, cb: int) -> int:
    """Fenix Downs in the bag."""
    return count_in(raw, cb, FENIX_DOWN)


def potion_band(level: int) -> int:
    """Potions the bag should carry at this party level: ~level x1.5,
    rounded up, never under POTION_BAND_MIN."""
    return max(POTION_BAND_MIN, -(-3 * level // 2))


def tonic_band(level: int) -> int:
    """Tonics the bag should carry at this party level: ~level x5, capped
    at 99 (a bag slot's count)."""
    return min(TONIC_BAND_CAP, 5 * level)


def tincture_band(level: int) -> int:
    """Tinctures the bag should carry at this party level: ~level / 4,
    rounded up -- 50 MP each against pools that grow ~9 MP a level, so one
    caster's whole pool per stretch (docs/design/supply.md)."""
    return -(-level // 4)


def party_level(raw: bytes, cb: int):
    """The active party's highest level, or None if none is flagged active."""
    levels = [m["level"] for m in party_at(raw, cb) if m.get("active")]
    return max(levels) if levels else None


# Cached: a fixture with multiple children would otherwise be decoded once
# per child.
@functools.lru_cache(maxsize=None)
def bag_of_mss(path: str):
    """({"fenix", "potion", "level"}, None) for a generated fixture, or
    (None, reason)."""
    raw = biggest_stream(path)
    if raw is None:
        return None, "no zlib stream"
    cb = find_char_block(raw)
    if cb is None:
        return None, "character table not located"
    return {"fenix": revives_in(raw, cb), "potion": count_in(raw, cb, POTION),
            "tonic": count_in(raw, cb, TONIC),
            "tincture": count_in(raw, cb, TINCTURE),
            "level": party_level(raw, cb)}, None


def revives_of_mss(path: str):
    """(count, None) for a generated fixture, or (None, reason)."""
    bag, err = bag_of_mss(path)
    return (None, err) if err else (bag["fenix"], None)


@functools.lru_cache(maxsize=None)
def revives_of_sram(path: str):
    """(count, None) for a tracked SRAM checkpoint, or (None, reason)."""
    with open(path, "rb") as f:
        raw = f.read()
    # allow_fallback=False: a checkpoint must match the table signature or
    # report nothing.
    cb = find_char_block(raw, allow_fallback=False)
    if cb is None:
        return None, "character table not located"
    return revives_in(raw, cb), None


def load_graph(repo: str):
    """The declared states with their predecessor edges.

    Returns (states, checkpoints): states is name -> {"prev", "checkpoint"},
    checkpoints is name -> payload path.  A row's `also=` artifacts come
    from the same boot as its primary state, so they carry the row's edge
    too (rapids_done is as far past the train as rapids_start is).
    """
    import importlib.util
    path = os.path.join(repo, "tools", "tests", "savestate_graph.py")
    spec = importlib.util.spec_from_file_location("savestate_graph", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    states = {}
    for s in mod.STATES:
        edge = {"prev": s.get("prev"), "checkpoint": s.get("checkpoint"),
                "row": s["state"]}
        states[s["state"]] = edge
        for a in s.get("also") or ():
            states[a] = dict(edge)
    checkpoints = dict(checkpoint_payloads(repo))
    return states, checkpoints


def past_first_potion_shop(name: str, states: dict) -> bool:
    """Whether the band applies: the fixture's `prev` chain reaches
    FIRST_POTION_SHOP, or ends at a checkpoint (every tracked checkpoint is
    cut downstream of the train).  A root with neither is before the shop."""
    seen = set()
    while name and name not in seen:
        if name == FIRST_POTION_SHOP:
            return True
        seen.add(name)
        edge = states.get(name)
        if edge is None:
            return False
        if edge["checkpoint"] and not edge["prev"]:
            return True
        name = edge["prev"]
    return False


def past_row(name: str, states: dict, row: str) -> bool:
    """Whether the fixture's `prev` chain reaches a fixture of `row`'s run,
    or ends at a checkpoint (every tracked checkpoint is cut downstream of
    both Figaro Castle and Narshe's post-Kefka counter)."""
    seen = set()
    while name and name not in seen:
        seen.add(name)
        edge = states.get(name)
        if edge is None:
            return False
        if edge.get("row") == row:
            return True
        if edge["checkpoint"] and not edge["prev"]:
            return True
        name = edge["prev"]
    return False


def past_first_tonic_shop(name: str, states: dict) -> bool:
    """Whether the Tonic band applies: from Figaro Castle's shop on."""
    return past_row(name, states, FIRST_TONIC_SHOP_ROW)


def in_tonic_band(name: str, states: dict) -> bool:
    """The Tonic band applies from Figaro Castle's shop to the WoR landing."""
    return past_first_tonic_shop(name, states) and not in_world_of_ruin(name, states)


def in_tincture_band(name: str, states: dict) -> bool:
    """The Tincture band applies from Narshe's shop 3 (after the Battle for
    Narshe) to the WoR landing."""
    return (past_row(name, states, FIRST_TINCTURE_SHOP_ROW)
            and not in_world_of_ruin(name, states))


def in_world_of_ruin(name: str, states: dict) -> bool:
    """Whether the fixture lies at or past the WoR landing: it is generated
    by WOR_LANDING's graph row (its `also=` siblings included) or its `prev`
    chain passes through that row.  The WoB band does not apply there."""
    seen = set()
    while name and name not in seen:
        seen.add(name)
        edge = states.get(name)
        if edge is None:
            return False
        if edge.get("row") == WOR_LANDING:
            return True
        name = edge["prev"]
    return False


def in_potion_band(name: str, states: dict) -> bool:
    """The band applies from the first Potion shop to the WoR landing."""
    return past_first_potion_shop(name, states) and not in_world_of_ruin(name, states)


def load_waivers(repo: str, path: str) -> set:
    """Fixture names whose zero-revive cliff is sanctioned.  Shrink-only:
    a name matching nothing fails as stale, so a fixture that stops dropping
    cannot keep its waiver."""
    out = set()
    full = os.path.join(repo, path)
    if not os.path.exists(full):
        return out
    with open(full, encoding="utf-8") as f:
        for line in f:
            line = line.split("#", 1)[0].strip()
            if line:
                out.add(line)
    return out


# --------------------------------------------------------------- selftest --

def is_cliff(here: int, pred: int) -> bool:
    """A revive spent and not replaced: none here, some in the predecessor."""
    return here == 0 and pred > 0


def selftest(repo: str = ".") -> int:
    ok = True

    def check(what, got, want):
        nonlocal ok
        if got != want:
            ok = False
            print(f"  SELFTEST FAIL {what}: got {got!r} want {want!r}")

    # the defect and its boundaries
    check("2 -> 0 is a cliff", is_cliff(0, 2), True)
    check("1 -> 0 is a cliff", is_cliff(0, 1), True)
    check("0 -> 0 is not (early game never had one)", is_cliff(0, 0), False)
    check("2 -> 1 is not (a revive spent but one still in the bag)",
          is_cliff(1, 2), False)
    check("0 -> 2 is not (a refill)", is_cliff(2, 0), False)
    check("3 -> 3 is not", is_cliff(3, 3), False)

    # the Potion band: ~level x1.5 rounded up, floor 10
    check("band at L4 is the floor", potion_band(4), 10)
    check("band at L14 (the train merchant)", potion_band(14), 21)
    check("band at L15 (Mobliz) rounds up", potion_band(15), 23)
    check("band at L27 (the FC entry)", potion_band(27), 41)
    # the Tonic band: ~level x5, capped at 99
    check("tonic band at L8 (Figaro Castle)", tonic_band(8), 40)
    check("tonic band at L19 (Zozo)", tonic_band(19), 95)
    check("tonic band at L20 caps", tonic_band(20), 99)
    # the Tincture band: ~level / 4, rounded up
    check("tincture band at L14 (Narshe's counter)", tincture_band(14), 4)
    check("tincture band at L16 is exact", tincture_band(16), 4)
    check("tincture band at L17 rounds up", tincture_band(17), 5)
    check("tincture band at L28 (the FC prep)", tincture_band(28), 7)
    # the short test itself, on a synthetic bag: under the band is short,
    # at it is not (the negative control), over it is not
    check("3 Tinctures at L14 is under the band",
          3 < tincture_band(14), True)
    check("4 Tinctures at L14 is not (negative control)",
          4 < tincture_band(14), False)
    check("9 Tinctures at L28 is not", 9 < tincture_band(28), False)

    # Checked against mrf-save-room-v1, which carries two Fenix Downs.
    cps = dict(checkpoint_payloads(repo))
    if "mrf-save-room-v1" not in cps:
        ok = False
        print("  SELFTEST FAIL mrf-save-room-v1 not among tracked checkpoints")
    else:
        # 20 pins the #198 re-cut (832740ee, from the regenerated
        # ifrit_entry); re-cut B (2026-09-01) carried 13 and the fled
        # run's payload 2.  The pin is the checkpoint reader's
        # regression canary, so it tracks whatever the sealed payload
        # truly holds.
        n, err = revives_of_sram(cps["mrf-save-room-v1"])
        if err or n != 20:
            ok = False
            print(f"  SELFTEST FAIL revives_of_sram(mrf-save-room-v1) "
                  f"should read 20 Fenix Downs, got {err or n}")

    # Sanity-check: the graph loads with edges.
    states, _ = load_graph(repo)
    if len(states) < 50 or states.get("arvis_wake", {}).get("prev") != "whelk_entry":
        ok = False
        print(f"  SELFTEST FAIL load_graph should read the edges "
              f"(arvis_wake prev=whelk_entry), got {len(states)} states")
    else:
        check("the band does not apply before the train (forest_done)",
              past_first_potion_shop("forest_done", states), False)
        check("nor in the Locke scenario (celes_freed)",
              past_first_potion_shop("celes_freed", states), False)
        check("it applies at the train merchant's exit (train_done)",
              past_first_potion_shop("train_done", states), True)
        check("and downstream through the Terra scenario (terra_narshe)",
              past_first_potion_shop("terra_narshe", states), True)
        check("and at a checkpoint-rooted fixture (narshe_mission)",
              past_first_potion_shop("narshe_mission", states), True)
        # a WoB band: it ends at the WoR landing's row
        check("the WoB band still covers the FC alcove (fc_alcove)",
              in_potion_band("fc_alcove", states), True)
        check("but not the WoR landing (wor_landing)",
              in_potion_band("wor_landing", states), False)
        # the Tonic band starts at Figaro Castle's shop, gen_edgar's row
        check("no Tonic band before Figaro Castle (figaro_entry)",
              in_tonic_band("figaro_entry", states), False)
        check("the Tonic band covers gen_edgar's own artifacts (figaro_cleared)",
              in_tonic_band("figaro_cleared", states), True)
        check("and the Locke scenario downstream (celes_freed)",
              in_tonic_band("celes_freed", states), True)
        check("and a checkpoint-rooted fixture (narshe_mission)",
              in_tonic_band("narshe_mission", states), True)
        check("but not the WoR landing (wor_landing)",
              in_tonic_band("wor_landing", states), False)
        check("nor its row-mate, the escape's first frame (escape_start)",
              in_potion_band("escape_start", states), False)
        check("a fixture before the train is not in the WoR either (forest_done)",
              in_world_of_ruin("forest_done", states), False)
        # the Tincture band starts at Narshe's shop 3, gen_zozo1_submerge's
        # row, not at Figaro Castle's counter (the purse there cannot carry
        # one) -- so the whole Battle for Narshe is out of it
        check("no Tincture band at Figaro Castle (figaro_cleared)",
              in_tincture_band("figaro_cleared", states), False)
        check("nor at the descent's foot (narshe_battle, negative control)",
              in_tincture_band("narshe_battle", states), False)
        check("nor at kefka_won, the fixture the Narshe stop boots from",
              in_tincture_band("kefka_won", states), False)
        check("the Tincture band starts with gen_zozo1_submerge's own artifact "
              "(figaro_submerged)",
              in_tincture_band("figaro_submerged", states), True)
        check("and covers the Zozo grind downstream (zozo_arrival)",
              in_tincture_band("zozo_arrival", states), True)
        check("and a checkpoint-rooted fixture (vector_entry)",
              in_tincture_band("vector_entry", states), True)
        check("and the FC alcove (fc_alcove)",
              in_tincture_band("fc_alcove", states), True)
        check("but not the WoR landing (wor_landing)",
              in_tincture_band("wor_landing", states), False)

    print("audit_supplies selftest: " + ("ok" if ok else "FAILED"))
    return 0 if ok else 1


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=".")
    ap.add_argument("--dir", default="build/states")
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return selftest(args.repo)

    declared = declared_states(args.repo)
    if not declared:
        print("audit_supplies: the graph declares no states; nothing to audit")
        return 0

    states, checkpoints = load_graph(args.repo)
    waivers = load_waivers(args.repo, WAIVERS)
    used = set()

    def revives_of_state(name: str):
        return revives_of_mss(os.path.join(args.dir, name + ".mss"))

    def predecessor_revives(edge: dict):
        """(count, label, reason).  Where the fixture came from carried how
        many revives, and what to call it in the report."""
        if edge["prev"]:
            n, err = revives_of_state(edge["prev"])
            return n, f"prev {edge['prev']}", err
        if edge["checkpoint"]:
            cp = edge["checkpoint"]
            if cp not in checkpoints:
                return None, f"checkpoint {cp}", "checkpoint payload missing"
            n, err = revives_of_sram(checkpoints[cp])
            return n, f"checkpoint {cp}", err
        return None, "root", "no predecessor"

    scanned, skipped, cliffs, short, tshort, mpshort = 0, [], [], [], [], []
    for name in sorted(declared):
        path = os.path.join(args.dir, name + ".mss")
        if not os.path.exists(path):
            continue                     # unseeded tree: nothing to read
        bag, err = bag_of_mss(path)
        if err:
            skipped.append((name, err))
            continue
        here = bag["fenix"]
        scanned += 1
        if in_potion_band(name, states) and bag["level"] is not None:
            band = potion_band(bag["level"])
            if bag["potion"] < band:
                short.append((name, bag["potion"], band, bag["level"]))
        if in_tonic_band(name, states) and bag["level"] is not None:
            tband = tonic_band(bag["level"])
            if bag["tonic"] < tband:
                tshort.append((name, bag["tonic"], tband, bag["level"]))
        if in_tincture_band(name, states) and bag["level"] is not None:
            mband = tincture_band(bag["level"])
            if bag["tincture"] < mband:
                mpshort.append((name, bag["tincture"], mband, bag["level"]))
        edge = states.get(name, {"prev": None, "checkpoint": None})
        pred, label, perr = predecessor_revives(edge)
        if perr:
            if perr != "no predecessor":
                skipped.append((name, f"{label}: {perr}"))
            if args.verbose:
                print(f"  ok   {name:30s} fenix={here} ({label})")
            continue
        if is_cliff(here, pred):
            if name in waivers:
                used.add(name)
                if args.verbose:
                    print(f"  waived {name:28s} 0 <- {pred} ({label})")
            else:
                cliffs.append((name, pred, label))
        elif args.verbose:
            print(f"  ok   {name:30s} fenix={here} <- {pred} ({label})")

    if not os.path.exists(os.path.join(args.dir)) or scanned == 0:
        print(f"audit_supplies: no readable fixtures under {args.dir} "
              f"(unseeded tree); skipped")
        return 0

    print(f"supply audit: {scanned} fixtures read"
          + (f", {len(skipped)} unreadable" if skipped else ""))
    for name, err in skipped:
        print(f"  ?    {name}: {err}")

    for name, pred, label in cliffs:
        print(f"  REVIVE CLIFF  {name}: 0 Fenix Downs, but {label} carried "
              f"{pred}. A revive was spent and never replaced.")

    if short:
        print(f"  WARNING: {len(short)} fixture(s) under the Potion band "
              f"(~level x1.5, min {POTION_BAND_MIN}; the in-combat heal, "
              f"docs/design/level-curve.md) -- top up with a POTION to N "
              f"line at the shop stop before each"
              + ("" if args.verbose else "; -v lists them") + ":")
        if args.verbose:
            for name, have, band, level in short:
                print(f"    POTION SHORT  {name:26s} potion={have:3d} "
                      f"< band {band} (L{level})")
        else:
            print("    " + " ".join(n for n, _, _, _ in short))

    if tshort:
        print(f"  WARNING: {len(tshort)} fixture(s) under the Tonic band "
              f"(~level x5, cap {TONIC_BAND_CAP}; the field-care heal, "
              f"docs/design/level-curve.md) -- top up with a TONIC to N "
              f"line at a shop that sells them, or size the Potion target "
              f"for the field care where none is reachable"
              + ("" if args.verbose else "; -v lists them") + ":")
        if args.verbose:
            for name, have, band, level in tshort:
                print(f"    TONIC SHORT   {name:26s} tonic={have:3d} "
                      f"< band {band} (L{level})")
        else:
            print("    " + " ".join(n for n, _, _, _ in tshort))

    if mpshort:
        print(f"  WARNING: {len(mpshort)} fixture(s) under the Tincture band "
              f"(~level / 4; the field-care MP restore, docs/design/supply.md) "
              f"-- top up with a TINCTURE to N line at a counter that sells "
              f"them (Narshe 3, Jidoor 22, Albrook 24, Thamasa 35)"
              + ("" if args.verbose else "; -v lists them") + ":")
        if args.verbose:
            for name, have, band, level in mpshort:
                print(f"    TINCTURE SHORT {name:25s} tincture={have:2d} "
                      f"< band {band} (L{level})")
        else:
            print("    " + " ".join(n for n, _, _, _ in mpshort))

    stale = sorted(waivers - used)
    if stale:
        print(f"\n{len(stale)} waiver(s) match nothing any more -- delete "
              f"them; the burn-down only shrinks:")
        for name in stale:
            print(f"  {name}")
        return 1

    if cliffs:
        print(f"\n{len(cliffs)} fixture(s) DROPPED TO NO REVIVES across a "
              f"boundary. In the World of Balance a Fenix Down is the only "
              f"answer to a\ndeath -- no shop sells Life and no owned esper "
              f"grants it -- so a segment that enters with none is one unlucky "
              f"round from\nunrecoverable. Refill it in the generator that "
              f"crosses the boundary (buy Fenix Downs where a shop is "
              f"reachable, or\nre-capture the checkpoint through a chain that "
              f"keeps them), and add an exit assertion so the drop fails loudly."
              f"\nWaive one only if the segment ahead genuinely cannot lose a "
              f"member -- a supply that ran out is a finding, not a story.")
        return 1

    print("  OK -- no fixture drops to zero revives across a boundary")
    return 0


if __name__ == "__main__":
    sys.exit(main())
