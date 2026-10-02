#!/bin/sh
# Make a fresh git worktree of this repo buildable/testable. Run from the
# worktree root. Seeds the gitignored pieces a worktree lacks from the main
# tree: the base ROM (copied; the build hashes it) plus Mesen.app and
# tools/bin (symlinked; run.sh execs one shared, non-portable copy under
# ~/Library/Caches/ot6 and isolates workers with CFFIXED_USER_HOME, so a
# worktree costs no emulator copies and no Gatekeeper scans).
set -eu

MAIN=$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')
HERE=$(pwd)
[ "$MAIN" = "$HERE" ] && { echo "already in the main tree; nothing to do"; exit 0; }

ROM="Final Fantasy III (USA).sfc"
[ -f "$HERE/$ROM" ] || cp "$MAIN/$ROM" "$HERE/$ROM"
# Linux runs the single-file binary in tools/Mesen-linux/ (docs/TOOLING.md).
MESEN=Mesen.app; [ "$(uname -s)" = Darwin ] || MESEN=Mesen-linux
[ -e "$HERE/tools/$MESEN" ] || ln -s "$MAIN/tools/$MESEN" "$HERE/tools/$MESEN"
[ -e "$HERE/tools/bin" ] || ln -s "$MAIN/tools/bin" "$HERE/tools/bin"

# Seed generated savestates and the checkpoint captures the graph's cuts
# Continue so boot-chain fixtures don't replay the whole game, plus
# build/ninja (the content copy-if-changed steps, the composed-script
# digests and .ninja_log; ninja treats an edge with no build-log entry as
# never built, so seeded states without the log would replay the whole
# graph). -p preserves mtimes so the log's recorded times still describe the
# copied files; real drift regenerates through the copy-if-changed and
# digest edges' content compare.
#
# Prefer a sibling worktree on the same commit whose own saved games verify
# (same commit = same generators and library, which is exactly what
# compose.py hashes); fall back to the main checkout.
HERE_BRANCH=$(git branch --show-current 2>/dev/null || echo '?')
HERE_HEAD=$(git rev-parse HEAD 2>/dev/null || echo '?')
SEED=""
if [ ! -d "$HERE/build/states" ]; then
  for cand in $(git worktree list --porcelain | awk '/^worktree /{print $2}'); do
    [ "$cand" = "$HERE" ] && continue
    [ -d "$cand/build/states" ] || continue
    [ "$(git -C "$cand" rev-parse HEAD 2>/dev/null)" = "$HERE_HEAD" ] || continue
    if (cd "$cand" && python3 tools/tests/lib/stamps.py --check-states) >/dev/null 2>&1
    then SEED="$cand"; break; fi
  done
  [ -n "$SEED" ] || SEED="$MAIN"
  if [ -d "$SEED/build/states" ]; then
    mkdir -p "$HERE/build"
    cp -Rp "$SEED/build/states" "$HERE/build/states"
    [ -d "$SEED/build/checkpoints" ] && [ ! -d "$HERE/build/checkpoints" ] && \
      cp -Rp "$SEED/build/checkpoints" "$HERE/build/checkpoints"
    [ -d "$SEED/build/ninja" ] && [ ! -d "$HERE/build/ninja" ] && \
      cp -Rp "$SEED/build/ninja" "$HERE/build/ninja"
  fi
fi

# Evidence a worktree cites goes under build/attempts/<branch>/ (docs/TESTING.md).
# Link build/attempts to the main tree's so that evidence lands there as it is
# written: the cited path resolves in both trees and survives `git worktree
# remove` (which deletes the link, not the main tree's files).
mkdir -p "$MAIN/build/attempts" "$HERE/build"
[ -e "$HERE/build/attempts" ] || ln -s "$MAIN/build/attempts" "$HERE/build/attempts"

SEED_BRANCH=$(git -C "${SEED:-$MAIN}" branch --show-current 2>/dev/null || echo '?')
# ninja needs build.ninja, which configure.py writes and git does not track.
(cd "$HERE" && python3 configure.py >/dev/null)

echo "worktree ready: ROM copied, Mesen/flips linked, build.ninja written"
echo "seeded from ${SEED:-$MAIN} ($SEED_BRANCH) into $HERE_BRANCH"

# State the seed's freshness by the stamps (lib/stamps.py: the question
# ninja answers by the same inputs).  A fresh worktree has no built ROM yet,
# so stamps read as UNVERIFIED (not stale) until `ninja build/ot6.sfc`.
if [ -d "$HERE/build/states" ]; then
  echo
  python3 "$HERE/tools/tests/lib/stamps.py" --check-states || {
    echo
    echo "The seed did not verify AS SEEDED (see above: STALE means ninja"
    echo "regenerates it, UNVERIFIED means build the ROM first). Re-confirm"
    echo "any time with:"
    echo "    python3 tools/tests/lib/stamps.py --check-states"
  }
fi
