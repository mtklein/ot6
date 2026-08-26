#!/usr/bin/env python3
"""State writes in tools/tests are declared, not silent: a registry of
sanctioned write-side API uses.

Scans every tools/tests/**/*.lua for the write-side token surface below,
after stripping Lua comments and string literals so prose does not trip it.
Every hit must be declared in tools/state_write_waivers.txt as a (file,
token) pair; an undeclared hit or a stale waiver entry fails the run.
--regen-waivers rewrites the list from the current corpus.

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
# reported under its most specific name; a trailing boundary keeps e.g.
# emu.reset from matching emu.resetAccessCounters.

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
    # The runtime write gate's confined raw-emu handle, injected by
    # lib/compose.py; no checked-in .lua may name it.
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
    """Map a regex match back to its TOKENS entry."""
    return matched


# ---------------------------------------------------------------- lexer ---
# Blanks out Lua comments and string literals, preserving newlines so line
# numbers survive: -- line/long comments, '...'/"..." strings, [[ ]] long
# strings.

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
# state_write_waivers.txt -- the registry of sanctioned state-writes for
# tools/check_state_writes.py.
#
# Each line names one (file, token) pair that writes emulated state.  Every one
# is a sanctioned expedient: a focused unit-style test, a measurement
# instrument, or the write primitives themselves -- the kind the owner ruled
# fine, because instrumenting a mechanism a person cannot produce on cue is not
# a claim about play.  The honesty that matters -- the long playthroughs (the
# savestate generators) playing for real -- is a separate and ABSOLUTE check,
# check_playthrough_honest.py, which refuses a generator that writes at all.
#
#   * a write whose (file, token) is not listed FAILS the run, so a new poke is
#     a reviewed line rather than a silent one;
#   * a listed pair that no longer matches anything FAILS as stale and must be
#     deleted, so the registry stays honest about the corpus.
#
# This is a registry, not a burn-down: it may grow when a new unit-style test
# earns an expedient, and it carries no obligation to reach zero.
#
# After removing writes:  python3 tools/check_state_writes.py --regen-waivers
# rewrites this file from the corpus (it preserves the third field).
#
# format: <path relative to repo root> <TAB> <token> [<TAB> quarantine: why]
#
# The optional `quarantine: <why>` third field records why the expedient is
# warranted -- typically an input the game can only produce rarely or never on
# cue: deliberate VRAM corruption for the font-restore path, the 1-in-65536
# zero-checksum save, a legacy save layout no version writes.  It is
# documentation, not a gate; a line without one is no less sanctioned.
"""


def load_waivers(path: str):
    """{(file, token): reason-or-None} from the waiver file.  A third field
    beginning `quarantine:` records the reason; missing file = empty."""
    waivers = {}
    if not os.path.exists(path):
        return waivers
    with open(path, encoding="utf-8") as f:
        for lineno, line in enumerate(f, 1):
            line = line.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) not in (2, 3) or not parts[0] or not parts[1]:
                raise SystemExit(
                    "check_state_writes: %s:%d: malformed waiver line %r "
                    "(want <path>\\t<token>[\\tquarantine: why])"
                    % (path, lineno, line))
            reason = None
            if len(parts) == 3:
                if not parts[2].startswith("quarantine:"):
                    raise SystemExit(
                        "check_state_writes: %s:%d: third field must begin "
                        "'quarantine:', got %r" % (path, lineno, parts[2]))
                reason = parts[2]
            waivers[(parts[0], parts[1])] = reason
    return waivers


def write_waivers(path: str, hits, existing=None) -> int:
    """Rewrite the list from the corpus, preserving quarantine reasons."""
    existing = existing or {}
    pairs = sorted({(rel, tok) for rel, _line, tok in hits})
    with open(path, "w", encoding="utf-8") as f:
        f.write(WAIVER_HEADER)
        for rel, tok in pairs:
            reason = existing.get((rel, tok))
            f.write("%s\t%s%s\n" % (rel, tok, "\t" + reason if reason else ""))
    return len(pairs)


def compare(hits, waivers):
    """(unwaived hits, stale waiver pairs)."""
    fired = {(rel, tok) for rel, _line, tok in hits}
    unwaived = [h for h in hits if (h[0], h[2]) not in waivers]
    stale = sorted(set(waivers) - fired)
    return unwaived, stale


# ---------------------------------------------------------------- check ---

def run_check(root: str, waiver_path: str, verbose: bool) -> int:
    hits, nfiles = scan_tree(root)
    waivers = load_waivers(waiver_path)
    unwaived, stale = compare(hits, waivers)

    with_reason = sum(1 for v in waivers.values() if v is not None)

    print("state-write check (%s/**/*.lua)" % TESTS_DIR)
    print("  scanned %d files: %d state-write sites, %d sanctioned "
          "(file,token) pairs" % (nfiles, len(hits), len(waivers)))
    print("  %d sanctioned unit-test/instrument writes (%d with a recorded "
          "reason)" % (len(waivers), with_reason))
    print("  the long playthroughs are honest separately: no story generator "
          "writes state (check_playthrough_honest.py, #75)")

    if verbose:
        for rel, line, tok in hits:
            mark = " " if (rel, tok) in waivers else "!"
            print("  %s %s:%d: %s" % (mark, rel, line, tok))

    if unwaived:
        print("  %d UNDECLARED STATE WRITE(S).  A test may read memory and "
              "inject input; a write is an expedient that must be declared:"
              % len(unwaived))
        for rel, line, tok in unwaived:
            print("  %s:%d: %s" % (rel, line, tok))
        print("  If this is a focused unit-style test or instrument, add the "
              "(file, token) to %s with a reason -- that is the sanctioned "
              "kind.  If it is a savestate generator, it is refused outright: "
              "the long playthroughs play for real (check_playthrough_honest.py)."
              % WAIVER_FILE.replace(os.sep, "/"))
    for rel, tok in stale:
        print("  STALE ENTRY: %s\t%s -- no hits left; delete the line "
              "(or --regen-waivers after a cleanup)" % (rel, tok))

    if unwaived or stale:
        return 1
    print("  OK -- every state write is a declared unit-test expedient, no "
          "stale entries")
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
        npairs = write_waivers(wpath, hits, load_waivers(wpath))
        expect(npairs == 1, "regen: want 1 pair, got %d" % npairs)
        unwaived, stale = compare(hits, load_waivers(wpath))
        expect(not unwaived and not stale,
               "regenerated waivers must pass: %r %r" % (unwaived, stale))

        # a new token in a waived file still fails (granularity is per pair)
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
        npairs = write_waivers(wpath, hits, load_waivers(wpath))
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
        # Passing the existing list lets a recorded quarantine reason
        # survive the rewrite.
        npairs = write_waivers(waiver_path, hits, load_waivers(waiver_path))
        print("state-write waivers regenerated: %d (file,token) pairs "
              "covering %d sites in %d scanned files -> %s"
              % (npairs, len(hits), nfiles, WAIVER_FILE.replace(os.sep, "/")))
        return 0

    return run_check(args.repo, waiver_path, args.verbose)


if __name__ == "__main__":
    sys.exit(main())
