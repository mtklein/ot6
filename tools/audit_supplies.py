#!/usr/bin/env python3
"""Report a fixture that lost its last revive crossing a boundary.

Flags a fixture with zero Fenix Downs whose predecessor (named by the graph's
`prev=` or `checkpoint=` edge) carried some; a root fixture is not audited.
Revival in the WoB is a Fenix Down only. Inventory is located off the
character-table anchor ($1869 ids / $1969 counts, offset past $1600).

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
                             declared_states, find_char_block)

WAIVERS = "tools/supply_waivers.txt"

FENIX_DOWN = 0xF0                      # the WoB's only revival, item id $F0
INV_IDS = 0x1869 - 0x1600             # inventory ids, offset past the char table
INV_QTY = 0x1969 - 0x1600             # inventory counts, one byte each


def revives_in(raw: bytes, cb: int) -> int:
    """Fenix Downs in the bag, given the blob and the $1600 anchor.

    The inventory is 256 (id, count) slots at a fixed offset past the
    character table.
    """
    total = 0
    for i in range(256):
        if raw[cb + INV_IDS + i] == FENIX_DOWN:
            total += raw[cb + INV_QTY + i]
    return total


# Cached: a fixture with multiple children would otherwise be decoded once
# per child.
@functools.lru_cache(maxsize=None)
def revives_of_mss(path: str):
    """(count, None) for a generated fixture, or (None, reason)."""
    raw = biggest_stream(path)
    if raw is None:
        return None, "no zlib stream"
    cb = find_char_block(raw)
    if cb is None:
        return None, "character table not located"
    return revives_in(raw, cb), None


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
    checkpoints is name -> payload path.
    """
    import importlib.util
    path = os.path.join(repo, "tools", "tests", "savestate_graph.py")
    spec = importlib.util.spec_from_file_location("savestate_graph", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    states = {s["state"]: {"prev": s.get("prev"), "checkpoint": s.get("checkpoint")}
              for s in mod.STATES}
    checkpoints = dict(checkpoint_payloads(repo))
    return states, checkpoints


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

    # Checked against mrf-save-room-v1, which carries two Fenix Downs.
    cps = dict(checkpoint_payloads(repo))
    if "mrf-save-room-v1" not in cps:
        ok = False
        print("  SELFTEST FAIL mrf-save-room-v1 not among tracked checkpoints")
    else:
        # 13 pins the FIGHTING lineage's re-cut B (2026-09-01); the fled
        # lineage's payload carried 2.  The pin is the checkpoint reader's
        # regression canary, so it tracks whatever the sealed payload
        # truly holds.
        n, err = revives_of_sram(cps["mrf-save-room-v1"])
        if err or n != 13:
            ok = False
            print(f"  SELFTEST FAIL revives_of_sram(mrf-save-room-v1) "
                  f"should read 13 Fenix Downs, got {err or n}")

    # Sanity-check: the graph loads with edges.
    states, _ = load_graph(repo)
    if len(states) < 50 or states.get("arvis_wake", {}).get("prev") != "whelk_entry":
        ok = False
        print(f"  SELFTEST FAIL load_graph should read the edges "
              f"(arvis_wake prev=whelk_entry), got {len(states)} states")

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

    scanned, skipped, cliffs = 0, [], []
    for name in sorted(declared):
        path = os.path.join(args.dir, name + ".mss")
        if not os.path.exists(path):
            continue                     # unseeded tree: nothing to read
        here, err = revives_of_state(name)
        if err:
            skipped.append((name, err))
            continue
        scanned += 1
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
