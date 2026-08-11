#!/bin/sh
# Make a fresh git worktree of this repo buildable/testable. Run from the
# worktree root. The gitignored pieces a worktree lacks are seeded from the
# main tree: the base ROM (copied — make verify hashes it) plus Mesen.app
# and tools/bin (symlinked — the source bundle really is read-only now:
# run.sh execs ONE shared, non-portable copy under ~/Library/Caches/ot6 and
# isolates workers with CFFIXED_USER_HOME instead of per-worker bundles, so
# a worktree costs no emulator copies and no Gatekeeper scans at all). That
# shared copy is machine-wide, so it is already warm by the time a second
# worktree exists. Generated build products (.lz compression, ca65 depfiles)
# need no seeding: ff6/Makefile schedules them from tracked sources, so
# plain `make` builds them.
set -eu

MAIN=$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')
HERE=$(pwd)
[ "$MAIN" = "$HERE" ] && { echo "already in the main tree; nothing to do"; exit 0; }

ROM="Final Fantasy III (USA).sfc"
[ -f "$HERE/$ROM" ] || cp "$MAIN/$ROM" "$HERE/$ROM"
[ -e "$HERE/tools/Mesen.app" ] || ln -s "$MAIN/tools/Mesen.app" "$HERE/tools/Mesen.app"
[ -e "$HERE/tools/bin" ] || ln -s "$MAIN/tools/bin" "$HERE/tools/bin"

# Seed the main tree's generated savestates so boot-chain fixtures don't
# replay the whole game, PLUS the ninja bookkeeping for `make frontier`
# (build/ninja: the content latches and .ninja_log).  Ninja treats an edge
# with no build-log entry as never built, so seeded states without the log
# would genuinely -- and expensively, hours -- replay the whole chain.  -p
# preserves mtimes so the log's recorded times still describe the copied
# files; any REAL drift (a local edit after seeding) still regenerates
# through the latch edges' content compare, proven in
# frontier_ninja_selftest.sh.
MAIN_BRANCH=$(git -C "$MAIN" branch --show-current 2>/dev/null || echo '?')
HERE_BRANCH=$(git branch --show-current 2>/dev/null || echo '?')
if [ -d "$MAIN/build/states" ] && [ ! -d "$HERE/build/states" ]; then
  mkdir -p "$HERE/build"
  cp -Rp "$MAIN/build/states" "$HERE/build/states"
  if [ -d "$MAIN/build/ninja" ] && [ ! -d "$HERE/build/ninja" ]; then
    cp -Rp "$MAIN/build/ninja" "$HERE/build/ninja"
  fi
fi

echo "worktree ready: ROM copied, Mesen/flips linked"
echo "seeded from $MAIN ($MAIN_BRANCH) into $HERE_BRANCH"

# ------------------------------------------------------- is the seed FRESH?
# This block used to be a branch-name guess: "$MAIN_BRANCH != $HERE_BRANCH,
# so SOME tests MAY be red, confirm by regenerating."  Both halves were wrong
# in the way that costs time.
#
#   * Wrong direction.  Equal branch names proved nothing.  Measured
#     2026-07-30: `git diff main release/v0.9` was EMPTY, so the heuristic
#     stayed silent -- and every one of the 105 seeded fixtures was stale
#     anyway, because the main checkout's own last `make frontier` (its
#     stamps: 2026-07-28 09:15) predates commit b085cac (2026-07-28 19:47),
#     which edited tools/tests/lib/ot6.lua.  The staleness never came from
#     the branch; it came from the seed source not having regenerated since a
#     shared input moved.  A worktree cut from a tree in that state inherits
#     it whatever branch either side is on.
#   * "MAY be red" is not actionable.  An agent told that some unnamed tests
#     might be stale, with no cheap way to check which, does the expensive
#     thing: re-runs tests against unmodified `main` to see if they are red
#     there too.  Four agents did precisely that, independently, for the same
#     ~10 tests, on 2026-07-29.
#
# So: ask, do not guess -- and ask with the SAME code the runtime check uses,
# so this script and compose.py cannot disagree about what "fresh" means.
# ~2s for 105 fixtures, once, at setup.
if [ -d "$HERE/build/states" ]; then
  echo
  python3 "$HERE/tools/tests/lib/compose.py" --check-states || {
    echo
    echo "The seed is stale AS SEEDED -- before you have touched anything."
    echo "That is a fact about this tree now, not a warning about later, and"
    echo "you can re-confirm it any time with:"
    echo "    python3 tools/tests/lib/compose.py --check-states"
  }
fi
