#!/usr/bin/env python3
"""Story generators advance through real input; no selective game-state edits.

Complete snapshot capture, restoration, branching, and memory inspection are
permitted experiment machinery (docs/TESTING.md). This check does not prohibit
library snapshot helpers or require continuous replay from the game's start.

A generator (tools/tests/gen_*.lua) may not write emulated game state -- no
emu.write, no M.writeByte/writeWord, and no M.clearBattle (which writes the
kill-bit through the library) -- unless named in UNIT_FIXTURE_GENERATORS as
a standalone unit fixture: a leaf off the story spine nothing boots from.
Suite tests, probes and measurement instruments are out of scope; those are
governed by check_state_writes.py.

Usage:  python3 tools/check_playthrough_honest.py [--dir tools/tests] [--selftest]
Exit 0 if every playthrough generator is write-free, 1 otherwise.
"""

from __future__ import annotations

import argparse
import glob
import os
import sys

# A write reaches emulated game state through one of these.  M.clearBattle
# writes $3EEC through the library rather than inline.
WRITE_TOKENS = (".writeByte(", ".writeWord(", "emu.write", "clearBattle")

# Generators exempt because they mint a standalone unit fixture off the
# story spine -- a leaf nothing boots from.
UNIT_FIXTURE_GENERATORS = {
    "gen_battle2": "standalone sprite-anchor check: clamps the two guards to "
                   "1 HP to reach the mixed-formation render state fast. Its "
                   "state battle2_entry is a leaf (savestate_graph: no "
                   "children), off the whelk_entry story spine, so nothing on "
                   "the release playthrough boots from it.",
}


def strip_comment(line: str) -> str:
    """The code half of a Lua line: everything before a `--` line comment.

    Block comments (--[[ ]]) are not used in the generators.
    """
    i = line.find("--")
    return line if i < 0 else line[:i]


def writes_in(path: str) -> list[str]:
    """The write tokens that actually appear in this file's code."""
    hits = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            code = strip_comment(line)
            for tok in WRITE_TOKENS:
                if tok in code and tok not in hits:
                    hits.append(tok)
    return hits


def offenders(directory: str):
    """(generator, tokens) for each playthrough generator that writes state."""
    bad = []
    for path in sorted(glob.glob(os.path.join(directory, "gen_*.lua"))):
        name = os.path.basename(path)[:-len(".lua")]
        if name in UNIT_FIXTURE_GENERATORS:
            continue
        hits = writes_in(path)
        if hits:
            bad.append((name, hits))
    return bad


def selftest() -> int:
    ok = True

    def check(what, got, want):
        nonlocal ok
        if got != want:
            ok = False
            print(f"  SELFTEST FAIL {what}: got {got!r} want {want!r}")

    check("a real write is seen", writes_token_in("H.writeWord(0x3C00, 1)"), True)
    check("clearBattle call is seen", writes_token_in("H.clearBattle(9000)"), True)
    check("a commented clearBattle is NOT seen",
          writes_token_in("-- the clearBattle this used to call is gone"), False)
    check("an inline-commented write is NOT seen",
          writes_token_in("foo()  -- H.writeByte(x) explained"), False)
    check("honest input is not a write",
          writes_token_in('H.navTo(25, 52, { playBattles = "flee" })'), False)

    # gen_battle2 must still be a leaf off the spine, or the exemption is
    # wrong.
    try:
        sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                        "tests"))
        import savestate_graph as g
        kids = [s["state"] for s in g.STATES
                if s.get("prev") == "battle2_entry"
                or s.get("checkpoint") == "battle2_entry"]
        if kids:
            ok = False
            print(f"  SELFTEST FAIL gen_battle2 is allowlisted as an off-spine "
                  f"leaf, but battle2_entry now has descendants {kids} -- it is "
                  f"on the playthrough and must not write state")
    except Exception as e:
        ok = False
        print(f"  SELFTEST FAIL could not read the graph to check the "
              f"gen_battle2 exemption: {e}")

    print("check_playthrough_honest selftest: " + ("ok" if ok else "FAILED"))
    return 0 if ok else 1


def writes_token_in(line: str) -> bool:
    """Selftest helper: does one line, comment-stripped, carry a write token."""
    code = strip_comment(line)
    return any(tok in code for tok in WRITE_TOKENS)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default="tools/tests")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return selftest()

    bad = offenders(args.dir)
    if bad:
        print(f"playthrough honesty: {len(bad)} story generator(s) WRITE GAME "
              f"STATE -- the long playthrough must play for real (#75):")
        for name, hits in bad:
            print(f"  {name}: {', '.join(hits)}")
        print("\nA generator that writes state mints a fixture that was never "
              "actually reached, and every state below it inherits that.\n"
              "Drive the state through real input instead (playBattles="
              '"flee"/"tactical", real menus, real items).  If this generator '
              "truly\nmints a standalone unit fixture off the story spine "
              "(a leaf nothing boots from), add it to "
              "UNIT_FIXTURE_GENERATORS with the\nreason -- but check the graph "
              "first.")
        return 1
    print("playthrough honesty: every story generator plays for real "
          f"(no writes; {len(UNIT_FIXTURE_GENERATORS)} declared unit fixture "
          "exempt)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
