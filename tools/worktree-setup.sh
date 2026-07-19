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
# the whole game. Safe against drift: .rom-copy rides along, and the
# Makefile's content-compare gate remints anything whose ROM bytes differ.
if [ -d "$MAIN/build/states" ] && [ ! -d "$HERE/build/states" ]; then
  mkdir -p "$HERE/build"
  cp -R "$MAIN/build/states" "$HERE/build/states"
fi

echo "worktree ready: ROM copied, Mesen/flips linked"
