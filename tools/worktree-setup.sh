#!/bin/sh
# Make a fresh git worktree of this repo buildable/testable. Run from the
# worktree root. The gitignored pieces a worktree lacks are seeded from the
# main tree: the base ROM (copied, because make verify hashes it) plus
# Mesen.app and tools/bin (symlinked, because the source bundle is read-only
# now: run.sh execs one shared, non-portable copy under ~/Library/Caches/ot6
# and isolates workers with CFFIXED_USER_HOME instead of per-worker bundles,
# so a worktree costs no emulator copies and no Gatekeeper scans). That
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
# replay the whole game, plus the ninja bookkeeping for `make savestates`
# (build/ninja: the content latches and .ninja_log).  Ninja treats an edge
# with no build-log entry as never built, so seeded states without the log
# would replay the whole chain, which takes hours.  -p
# preserves mtimes so the log's recorded times still describe the copied
# files; real drift (a local edit after seeding) still regenerates
# through the latch edges' content compare, proven in
# savestate_ninja_selftest.sh.
HERE_BRANCH=$(git branch --show-current 2>/dev/null || echo '?')

# Seed from whichever tree actually has usable saved games, not from the main
# checkout by reflex.
#
# The main checkout regenerates rarely -- it is the one somebody plays from --
# so seeding from it hands a new worktree months-old saved games far more often
# than not. On 2026-08-13 that cost two agents real time in one day: one
# diagnosed a boss fight against a party from a route that no longer existed,
# and another had to hand-copy files out of a sibling worktree before it could
# reproduce anything. Meanwhile a worktree on the same commit, with saved games
# that verify, was usually sitting right there.
#
# So: prefer a sibling on the same commit as us whose own saved games verify.
# Same commit means the same generators and the same library, so what verifies
# there verifies here -- that is exactly what compose.py hashes. Anything else
# falls back to the main checkout, which is no worse than before.
HERE_HEAD=$(git rev-parse HEAD 2>/dev/null || echo '?')
SEED=""
if [ ! -d "$HERE/build/states" ]; then
  for cand in $(git worktree list --porcelain | awk '/^worktree /{print $2}'); do
    [ "$cand" = "$HERE" ] && continue
    [ -d "$cand/build/states" ] || continue
    [ "$(git -C "$cand" rev-parse HEAD 2>/dev/null)" = "$HERE_HEAD" ] || continue
    if (cd "$cand" && python3 tools/tests/lib/compose.py --check-states) >/dev/null 2>&1
    then SEED="$cand"; break; fi
  done
  [ -n "$SEED" ] || SEED="$MAIN"
  if [ -d "$SEED/build/states" ]; then
    mkdir -p "$HERE/build"
    cp -Rp "$SEED/build/states" "$HERE/build/states"
    [ -d "$SEED/build/ninja" ] && [ ! -d "$HERE/build/ninja" ] && \
      cp -Rp "$SEED/build/ninja" "$HERE/build/ninja"
  fi
fi

SEED_BRANCH=$(git -C "${SEED:-$MAIN}" branch --show-current 2>/dev/null || echo '?')
echo "worktree ready: ROM copied, Mesen/flips linked"
echo "seeded from ${SEED:-$MAIN} ($SEED_BRANCH) into $HERE_BRANCH"

# ------------------------------------------------------- is the seed fresh?
# This block used to be a branch-name guess: "$MAIN_BRANCH != $HERE_BRANCH,
# so SOME tests MAY be red, confirm by regenerating."  Both halves were wrong
# in ways that cost time.
#
#   * Wrong direction.  Equal branch names proved nothing.  Measured
#     2026-07-30: `git diff main release/v0.9` was empty, so the heuristic
#     stayed silent, and every one of the 105 seeded fixtures was stale
#     anyway, because the main checkout's own last `make savestates` (its
#     stamps: 2026-07-28 09:15) predates commit b085cac (2026-07-28 19:47),
#     which edited tools/tests/lib/ot6.lua.  The staleness came from the seed
#     source not having regenerated since a shared input moved, rather than
#     from the branch.  A worktree cut from a tree in that state inherits
#     it whatever branch either side is on.
#   * "MAY be red" is not actionable.  An agent told that some unnamed tests
#     might be stale, with no cheap way to check which, does the expensive
#     thing: re-runs tests against unmodified `main` to see if they are red
#     there too.  Four agents did that, independently, for the same
#     ~10 tests, on 2026-07-29.
#
# So ask rather than guess, and ask with the same code the runtime check uses,
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
