#!/usr/bin/env python3
"""No test may WRITE emulated game state.  This is the check that enforces it.

The rule (owner directive, 2026-08): test and savestate-generating Lua scripts
may inject controller input and READ emulated memory; they may never write it.
A test that pokes HP, warps the party, or plants an item is not testing the
game, it is testing its own poke -- every fixture and every green mark
downstream of a poked state is vouching for a game nobody played.

This linter scans every tools/tests/**/*.lua (lib/ included), strips Lua
comments and string literals first (the corpus talks ABOUT write APIs far
more often than it calls them -- prose must not trip the check), and then
flags the write-side surface:

    emu.write / emu.writeWord / emu.write16 / emu.write32
    emu.setState / emu.addCheat / emu.clearCheats
    emu.rewind / emu.reset / emu.loadSavestate
    .writeByte( / .writeWord(          (any receiver -- the ot6.lua wrappers)
    H.write / M.write                  (helper-module write entry points)

One loud line per finding: file:line: token.  Exit 0 clean, exit 1 dirty.

WAIVERS.  The corpus predates the rule, so every existing violation is
grandfathered into tools/state_write_waivers.txt, a BURN-DOWN list of
(file, token) pairs that must only ever shrink:

  * a hit whose (file, token) pair is not in the list fails the run --
    new writes are impossible to land, anywhere, from day one;
  * a listed pair that no longer matches anything also fails the run --
    the stale line must be deleted, so the list only ever shrinks and a
    cleaned-up file can never quietly regress back onto its old waiver.

Granularity is per (file, token), not per line: line numbers churn with
every unrelated edit, while "this file still calls this write API" is
exactly the fact the burn-down tracks.  The cost is that a waived file can
add MORE calls to a token it already uses -- accepted, because the burn-down
cleans whole files and the waiver dies with the last call.

--regen-waivers rewrites the list from the current corpus.  That is for
the cleanup waves (delete writes, regen, watch the list shrink); running it
to LAUNDER a new write is visible in the diff of a checked-in file.

Wired into `make test` (both the check and --selftest) and into `make
frontier` (so savestate generation cannot run from a poking generator even
when the suite was skipped).  It lives in the Makefile rather than suite.sh
because suite discovery globs *.lua for a `-- @suite` marker and cannot see
a .py file -- same reason check_boss_rows.py sits there.

Nothing here writes game state; it is a read-only linter (only
--regen-waivers touches anything, and only the waiver file).

Usage:  python3 tools/check_state_writes.py [--repo ROOT] [-v]
                [--regen-waivers] [--selftest]
"""

from __future__ import annotations

import argparse
import os
import re
import sys

TESTS_DIR = os.path.join("tools", "tests")
WAIVER_FILE = os.path.join("tools", "state_write_waivers.txt")

# ---------------------------------------------------------------- tokens --
# The write-side surface.  Matching is longest-token-first so a site is
# reported under its most specific name (emu.writeWord, not emu.write), and
# tokens that end in an identifier character take a trailing boundary so
# emu.reset does not claim emu.resetAccessCounters (a counter reset is not a
# state write) and M.write does not claim M.writeByte( -- the .writeByte(
# token owns that site instead.

TOKENS = [
    "emu.write",
    "emu.writeWord",
    "emu.write16",
    "emu.write32",
    "emu.setState",
    "emu.addCheat",
    "emu.clearCheats",
    "emu.rewind",
    "emu.reset",
    "emu.loadSavestate",
    ".writeByte(",
    ".writeWord(",
    "H.write",
    "M.write",
    # The runtime write gate's confined raw-emu handle (lib/compose.py
    # injects it at compose time; no checked-in .lua may name it).  A test
    # that reaches for it is reaching AROUND the gate, and since this token
    # was born forbidden it can never legitimately appear in the burn-down
    # list -- the static side closes the runtime side's one escape hatch.
    "__OT6_EMU_RAW",
]

_IDENT = "A-Za-z0-9_"


def _token_pattern(tok: str) -> str:
    pat = re.escape(tok)
    if re.match("[%s]" % _IDENT, tok):
        pat = "(?<![%s])" % _IDENT + pat
    if re.search("[%s]$" % _IDENT, tok):
        pat += "(?![%s])" % _IDENT
    return pat


TOKEN_RE = re.compile("|".join(
    _token_pattern(t) for t in sorted(TOKENS, key=len, reverse=True)))


def canon_token(matched: str) -> str:
    """Map a regex match back to its TOKENS entry (they are equal today;
    this is the seam that keeps waiver keys stable if a pattern grows)."""
    return matched


# ---------------------------------------------------------------- lexer ---
# Blank out Lua comments and string literals, preserving every newline so
# line numbers survive.  Handles:  -- line comments, --[[ ]] / --[=[ ]=]
# long comments, '...' and "..." with backslash escapes, [[ ]] / [=[ ]=]
# long strings.  An unterminated quote is closed at the newline (Lua itself
# errors there) and an unterminated long bracket runs to EOF.

_LONG_OPEN = re.compile(r"\[(=*)\[")


def strip_lua(text: str) -> str:
    out = list(text)
    n = len(text)

    def blank(a: int, b: int) -> None:
        for k in range(a, min(b, n)):
            if out[k] != "\n":
                out[k] = " "

    i = 0
    while i < n:
        c = text[i]
        if c == "-" and text.startswith("--", i):
            m = _LONG_OPEN.match(text, i + 2)
            if m:                                   # --[[ long comment ]]
                close = "]" + m.group(1) + "]"
                j = text.find(close, m.end())
                j = n if j < 0 else j + len(close)
            else:                                   # -- line comment
                j = text.find("\n", i)
                j = n if j < 0 else j
            blank(i, j)
            i = j
        elif c in "\"'":                            # quoted string
            j = i + 1
            while j < n:
                if text[j] == "\\":
                    j += 2
                elif text[j] == c or text[j] == "\n":
                    j += 1
                    break
                else:
                    j += 1
            blank(i, j)
            i = j
        elif c == "[":
            m = _LONG_OPEN.match(text, i)
            if m:                                   # [[ long string ]]
                close = "]" + m.group(1) + "]"
                j = text.find(close, m.end())
                j = n if j < 0 else j + len(close)
                blank(i, j)
                i = j
            else:
                i += 1
        else:
            i += 1
    return "".join(out)


# ---------------------------------------------------------------- scan ----

def scan_text(rel: str, text: str):
    """[(rel, line, token)] for one file's contents."""
    stripped = strip_lua(text)
    hits = []
    for m in TOKEN_RE.finditer(stripped):
        line = stripped.count("\n", 0, m.start()) + 1
        hits.append((rel, line, canon_token(m.group(0))))
    return hits


def scan_tree(root: str):
    """Every hit in root/tools/tests/**/*.lua, path-then-line order."""
    base = os.path.join(root, TESTS_DIR)
    if not os.path.isdir(base):
        raise SystemExit("check_state_writes: no such directory %r" % base)
    hits = []
    nfiles = 0
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames.sort()
        for name in sorted(filenames):
            if not name.endswith(".lua"):
                continue
            nfiles += 1
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, root).replace(os.sep, "/")
            with open(path, encoding="utf-8", errors="replace") as f:
                hits.extend(scan_text(rel, f.read()))
    return hits, nfiles


# ---------------------------------------------------------------- waivers -

WAIVER_HEADER = """\
# state_write_waivers.txt -- BURN-DOWN list for tools/check_state_writes.py.
#
# Each line waives one (file, token) pair: that file's pre-rule uses of that
# state-write API, grandfathered when the no-write rule landed.  This list
# must only ever SHRINK:
#
#   * adding a line to cover new code is the exact cheat the checker exists
#     to prevent -- new writes fail `make test`, full stop;
#   * a line whose pair no longer matches anything FAILS the check as stale
#     and must be deleted (that is the only-shrinks rule -- a cleaned file
#     cannot quietly regress onto its old waiver).
#
# After a cleanup wave:  python3 tools/check_state_writes.py --regen-waivers
# regenerates this file from the corpus; the diff must be pure deletion.
#
# format: <path relative to repo root> <TAB> <token>
"""


def load_waivers(path: str):
    """{(file, token)} from the waiver file; missing file = empty set."""
    waivers = set()
    if not os.path.exists(path):
        return waivers
    with open(path, encoding="utf-8") as f:
        for lineno, line in enumerate(f, 1):
            line = line.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) != 2 or not parts[0] or not parts[1]:
                raise SystemExit(
                    "check_state_writes: %s:%d: malformed waiver line %r "
                    "(want <path>\\t<token>)" % (path, lineno, line))
            waivers.add((parts[0], parts[1]))
    return waivers


def write_waivers(path: str, hits) -> int:
    pairs = sorted({(rel, tok) for rel, _line, tok in hits})
    with open(path, "w", encoding="utf-8") as f:
        f.write(WAIVER_HEADER)
        for rel, tok in pairs:
            f.write("%s\t%s\n" % (rel, tok))
    return len(pairs)


def compare(hits, waivers):
    """(unwaived hits, stale waiver pairs)."""
    fired = {(rel, tok) for rel, _line, tok in hits}
    unwaived = [h for h in hits if (h[0], h[2]) not in waivers]
    stale = sorted(waivers - fired)
    return unwaived, stale


# ---------------------------------------------------------------- check ---

def run_check(root: str, waiver_path: str, verbose: bool) -> int:
    hits, nfiles = scan_tree(root)
    waivers = load_waivers(waiver_path)
    unwaived, stale = compare(hits, waivers)

    print("state-write check (%s/**/*.lua)" % TESTS_DIR)
    print("  scanned %d files: %d state-write sites, %d waived (file,token) "
          "pairs" % (nfiles, len(hits), len(waivers)))

    if verbose:
        for rel, line, tok in hits:
            mark = " " if (rel, tok) in waivers else "!"
            print("  %s %s:%d: %s" % (mark, rel, line, tok))

    if unwaived:
        print("  %d NEW STATE WRITE(S) -- tests may read memory and inject "
              "input, never write game state:" % len(unwaived))
        for rel, line, tok in unwaived:
            print("  %s:%d: %s" % (rel, line, tok))
        print("  Fix the script to observe instead of poke.  Do NOT add a "
              "waiver: %s is a burn-down list and only shrinks."
              % WAIVER_FILE.replace(os.sep, "/"))
    for rel, tok in stale:
        print("  STALE WAIVER: %s\t%s -- no hits left; delete the line "
              "(or --regen-waivers after a cleanup wave)" % (rel, tok))

    if unwaived or stale:
        return 1
    print("  OK -- no state writes outside the burn-down list, no stale "
          "waivers")
    return 0


# ---------------------------------------------------------------- selftest -

def selftest() -> int:
    import tempfile

    failures = []

    def expect(cond, what):
        if not cond:
            failures.append(what)

    # -- stripping: prose about write APIs must not trip -------------------
    quiet = """
-- this line comment mentions emu.write and M.write and .writeByte( freely
--[[ a long comment:
     emu.setState(blob) would be a violation if it were code ]]
--[=[ leveled long comment: emu.addCheat("cheat") ]=]
local prose = "call emu.write(0x7e, 1) to poke"
local prose2 = 'and .writeWord( too, plus H.write'
local esc = "escaped quote \\" then emu.rewind mentioned"
local long = [[ multi
line string with emu.loadSavestate(x) inside ]]
local leveled = [==[ emu.write32(0, 0) ]==]
local tricky = "string with -- inside" .. tostring(4)
local counters = emu.resetAccessCounters()
local reads = emu.read(0x7e0000, emu.memType.snesMemory)
"""
    expect(scan_text("q.lua", quiet) == [],
           "stripped corpus should yield zero hits, got %r"
           % scan_text("q.lua", quiet))

    # -- detection, line numbers, longest-token canonicalisation -----------
    noisy = """local M = {}
--[[ two
lines of comment ]] emu.write(0x10, 1, t)
emu.writeWord(0x12, 2, t)
M.writeByte(0x14, 3)
M.write(0x16)
emu.reset()
local s = "benign" ; H.write(0x18)
local sneak = __OT6_EMU_RAW.write(0x1a, 4)
"""
    got = scan_text("n.lua", noisy)
    want = [
        ("n.lua", 3, "emu.write"),
        ("n.lua", 4, "emu.writeWord"),
        ("n.lua", 5, ".writeByte("),
        ("n.lua", 6, "M.write"),
        ("n.lua", 7, "emu.reset"),
        ("n.lua", 8, "H.write"),
        ("n.lua", 9, "__OT6_EMU_RAW"),
    ]
    expect(got == want, "detection drift: want %r got %r" % (want, got))

    # -- waiver logic on a synthetic tree ----------------------------------
    with tempfile.TemporaryDirectory() as tmp:
        tdir = os.path.join(tmp, TESTS_DIR)
        os.makedirs(os.path.join(tdir, "lib"))
        with open(os.path.join(tdir, "clean.lua"), "w") as f:
            f.write("-- emu.write in prose only\nlocal x = emu.read(1)\n")
        with open(os.path.join(tdir, "lib", "dirty.lua"), "w") as f:
            f.write("emu.write(0x10, 1)\nemu.write(0x20, 2)\n")
        wpath = os.path.join(tmp, WAIVER_FILE)

        hits, nfiles = scan_tree(tmp)
        expect(nfiles == 2, "synthetic tree: want 2 files, got %d" % nfiles)
        expect(len(hits) == 2 and
               all(h[0] == "tools/tests/lib/dirty.lua" for h in hits),
               "synthetic tree hits drifted: %r" % hits)

        # no waiver file: everything is a new write
        unwaived, stale = compare(hits, load_waivers(wpath))
        expect(len(unwaived) == 2 and not stale,
               "unwaivered hits must fail: %r %r" % (unwaived, stale))

        # regen: both hits collapse to one (file, token) pair, then pass
        npairs = write_waivers(wpath, hits)
        expect(npairs == 1, "regen: want 1 pair, got %d" % npairs)
        unwaived, stale = compare(hits, load_waivers(wpath))
        expect(not unwaived and not stale,
               "regenerated waivers must pass: %r %r" % (unwaived, stale))

        # a NEW token in a waived file still fails (granularity is per pair)
        with open(os.path.join(tdir, "lib", "dirty.lua"), "a") as f:
            f.write("emu.setState(blob)\n")
        hits, _ = scan_tree(tmp)
        unwaived, stale = compare(hits, load_waivers(wpath))
        expect([h[2] for h in unwaived] == ["emu.setState"] and not stale,
               "new token in waived file must fail: %r %r" % (unwaived, stale))

        # cleanup wave: the writes go away, the waiver line goes stale
        with open(os.path.join(tdir, "lib", "dirty.lua"), "w") as f:
            f.write("local v = emu.read(0x10)\n")
        hits, _ = scan_tree(tmp)
        unwaived, stale = compare(hits, load_waivers(wpath))
        expect(not unwaived and
               stale == [("tools/tests/lib/dirty.lua", "emu.write")],
               "stale waiver must be reported: %r %r" % (unwaived, stale))

        # regen after the wave: the list shrinks to nothing and passes
        npairs = write_waivers(wpath, hits)
        expect(npairs == 0, "post-wave regen: want 0 pairs, got %d" % npairs)
        unwaived, stale = compare(hits, load_waivers(wpath))
        expect(not unwaived and not stale,
               "empty corpus + empty list must pass: %r %r"
               % (unwaived, stale))

    if failures:
        print("check_state_writes --selftest: %d FAILURE(S)" % len(failures))
        for f in failures:
            print("  " + f)
        return 1
    print("check_state_writes --selftest: OK")
    return 0


# ---------------------------------------------------------------- main ----

def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--repo", default=os.path.dirname(os.path.dirname(
        os.path.abspath(__file__))))
    ap.add_argument("--regen-waivers", action="store_true",
                    help="rewrite the burn-down list from the current corpus "
                         "(for cleanup waves; the diff must be pure deletion)")
    ap.add_argument("--selftest", action="store_true",
                    help="verify stripping, detection, and waiver burn-down "
                         "logic on synthetic input")
    ap.add_argument("-v", "--verbose", action="store_true",
                    help="print every hit, waived ones included")
    args = ap.parse_args()

    if args.selftest:
        return selftest()

    waiver_path = os.path.join(args.repo, WAIVER_FILE)
    if args.regen_waivers:
        hits, nfiles = scan_tree(args.repo)
        npairs = write_waivers(waiver_path, hits)
        print("state-write waivers regenerated: %d (file,token) pairs "
              "covering %d sites in %d scanned files -> %s"
              % (npairs, len(hits), nfiles, WAIVER_FILE.replace(os.sep, "/")))
        return 0

    return run_check(args.repo, waiver_path, args.verbose)


if __name__ == "__main__":
    sys.exit(main())
