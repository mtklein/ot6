#!/usr/bin/env python3
"""Every test-shaped file under tools/tests declares whether it runs (#78).

Why this exists.  `whelkbal_tek.lua` carried no `-- @suite` marker, so
`make test` never ran it (suite.sh discovers members by that marker,
suite.sh:70).  It sat in the tree failing, silently, and when someone finally
ran it by hand it handed back numbers from two reads that had been wrong for a
while.  An instrument nobody runs rots into confident-looking garbage, which is
this repo's stated worst failure mode.  Nothing caught it because nothing was
looking: a file simply not appearing in the suite is invisible.

The rule.  A `.lua` under tools/tests must either be a suite member
(`-- @suite ...`) or say out loud that it is not (`-- @manual ...`).  A file
that is neither fails this check, so a test that loses its `@suite` marker --
or a new one that never got one -- can no longer hide.  `@manual` is not a
loophole: it is a one-line statement that a human runs this by hand and it is
deliberately outside the gate, which is exactly the decision that was never
made for whelkbal.

What is exempt, and why the exemption is safe.  Three prefixes carry their
status in the name, by long convention:

  * `gen_*`   -- savestate generators, run by the ninja graph
                 (tools/tests/savestate_graph.py), not the suite.  Orphan
                 generators are a different question the graph owns.
  * `probe*`  -- throwaway diagnostics, run by hand while chasing one thing.
  * `shot_*`  -- screenshot producers, run by hand.

These are understood to be off the suite; requiring a marker on ~120 probes
would be noise that trains people to add markers without thinking, which is
how the next whelkbal gets waved through.  The check is aimed at the namespaces
a reader would mistake for pass/fail suite tests (battle_, menu_, bal_,
metrics_, ...), which is where the rot actually hid.

Usage:  python3 tools/check_test_registration.py [--dir tools/tests] [--selftest]
Exit 0 if every non-exempt file declares itself, 1 otherwise.
"""

from __future__ import annotations

import argparse
import glob
import os
import sys

EXEMPT_PREFIXES = ("gen_", "probe", "shot_")
SUITE_MARK = "-- @suite"
MANUAL_MARK = "-- @manual"


def is_exempt(name: str) -> bool:
    """True if the file carries its run-status in its name by convention."""
    return name.startswith(EXEMPT_PREFIXES)


def declares_itself(text: str) -> bool:
    """True if a line begins with the suite or the manual marker."""
    for line in text.splitlines():
        s = line.lstrip()
        if s.startswith(SUITE_MARK) or s.startswith(MANUAL_MARK):
            return True
    return False


def undeclared(directory: str) -> list[str]:
    """Basenames of non-exempt .lua files that declare neither status."""
    bad = []
    for path in sorted(glob.glob(os.path.join(directory, "*.lua"))):
        name = os.path.basename(path)
        if is_exempt(name):
            continue
        with open(path, encoding="utf-8") as f:
            if not declares_itself(f.read()):
                bad.append(name)
    return bad


def selftest() -> int:
    ok = True

    def check(what, got, want):
        nonlocal ok
        if got != want:
            ok = False
            print(f"  SELFTEST FAIL {what}: got {got!r} want {want!r}")

    # The exemption is by name, and it is the load-bearing half: a bug that
    # exempted everything would pass a tree full of undeclared tests.
    check("gen_ is exempt", is_exempt("gen_arvis.lua"), True)
    check("probe_ is exempt", is_exempt("probe_vargas.lua"), True)
    check("probe16 (no underscore) is exempt", is_exempt("probe16.lua"), True)
    check("shot_ is exempt", is_exempt("shot_mines.lua"), True)
    check("a battle_ test is NOT exempt", is_exempt("battle_break.lua"), False)
    check("an instrument is NOT exempt", is_exempt("whelkbal_tek.lua"), False)

    # The marker must be a real comment line, not a mention in prose, so the
    # whelkbal failure mode (a file talking about @suite in its header without
    # carrying the marker) still fails.
    check("bare @suite line declares", declares_itself("-- @suite slow\ncode"),
          True)
    check("@manual line declares", declares_itself("-- @manual instrument\nx"),
          True)
    check("indented marker still declares",
          declares_itself("  -- @suite savestate=x"), True)
    check("prose mention does NOT declare",
          declares_itself("-- run this like a @suite member by hand"), False)
    check("no marker does not declare",
          declares_itself("-- whelkbal_tek.lua -- an instrument\nlocal H"),
          False)

    print("check_test_registration selftest: " + ("ok" if ok else "FAILED"))
    return 0 if ok else 1


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default="tools/tests")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return selftest()

    bad = undeclared(args.dir)
    if bad:
        print(f"test registration: {len(bad)} file(s) under {args.dir} run "
              f"neither in the suite nor by declared hand:")
        for name in bad:
            print(f"  {name}")
        print("\nEach must open with one of:\n"
              "  -- @suite [savestate=<fixture>] [slow]   (a pass/fail member "
              "make test runs)\n"
              "  -- @manual <why it is run by hand>       (a deliberate "
              "instrument, off the gate)\n"
              "A file with neither is invisible: it can fail on main and "
              "nobody notices (#78, whelkbal_tek).")
        return 1
    print("test registration: every non-exempt tools/tests file declares "
          "@suite or @manual")
    return 0


if __name__ == "__main__":
    sys.exit(main())
