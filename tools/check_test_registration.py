#!/usr/bin/env python3
"""Every test-shaped file under tools/tests declares whether it runs.

A `.lua` under tools/tests must either be a suite member (`-- @suite ...`)
or say out loud that it is not (`-- @manual ...`).  One prefix is exempt,
carrying its status in the name: `gen_*` (savestate generators, run by the
ninja graph).  `probe*` and `shot_*` were exempt too until #310: the policy
(docs/TESTING.md, "Scripts that stay in the tree") is the same for them, so
a probe is an instrument (`@manual`, which check_instruments.py starts) or
it goes, its findings in the commit that deletes it.

Usage:  python3 tools/check_test_registration.py [--dir tools/tests] [--selftest]
Exit 0 if every non-exempt file declares itself, 1 otherwise.
"""

from __future__ import annotations

import argparse
import glob
import os
import sys

EXEMPT_PREFIXES = ("gen_",)
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

    check("gen_ is exempt", is_exempt("gen_arvis.lua"), True)
    check("probe_ is NOT exempt (#310)", is_exempt("probe_vargas.lua"), False)
    check("shot_ is NOT exempt (#310)", is_exempt("shot_mines.lua"), False)
    check("a battle_ test is NOT exempt", is_exempt("battle_break.lua"), False)
    check("an instrument is NOT exempt", is_exempt("metrics_battle.lua"), False)

    # The marker must be a real comment line, not a mention in prose.
    check("bare @suite line declares", declares_itself("-- @suite slow\ncode"),
          True)
    check("@manual line declares", declares_itself("-- @manual instrument\nx"),
          True)
    check("indented marker still declares",
          declares_itself("  -- @suite savestate=x"), True)
    check("prose mention does NOT declare",
          declares_itself("-- run this like a @suite member by hand"), False)
    check("no marker does not declare",
          declares_itself("-- metrics_battle.lua -- an instrument\nlocal H"),
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
              "the suite runs)\n"
              "  -- @manual <why it is run by hand>       (an instrument: "
              "build/checks/instruments.ok composes and starts it)\n"
              "A file with neither is invisible: it can fail on main and "
              "nobody notices (#78: whelkbal_tek, deleted in 7f79dd93).")
        return 1
    print("test registration: every non-exempt tools/tests file declares "
          "@suite or @manual")
    return 0


if __name__ == "__main__":
    sys.exit(main())
