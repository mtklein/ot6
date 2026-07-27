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

# Seed the main tree's minted savestates so boot-chain fixtures don't replay
# the whole game, PLUS the ninja frontier bookkeeping (build/ninja: the
# content latches and .ninja_log).  Ninja treats an edge with no build-log
# entry as never built, so seeded states without the log would honestly --
# and expensively, hours -- replay the whole frontier.  -p preserves mtimes
# so the log's recorded times still describe the copied files; any REAL
# drift (a local edit after seeding) still re-mints through the latch
# edges' content compare, proven in frontier_ninja_selftest.sh.
if [ -d "$MAIN/build/states" ] && [ ! -d "$HERE/build/states" ]; then
  mkdir -p "$HERE/build"
  cp -Rp "$MAIN/build/states" "$HERE/build/states"
  if [ -d "$MAIN/build/ninja" ] && [ ! -d "$HERE/build/ninja" ]; then
    cp -Rp "$MAIN/build/ninja" "$HERE/build/ninja"
  fi
fi

echo "worktree ready: ROM copied, Mesen/flips linked"
