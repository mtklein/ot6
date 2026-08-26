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
[ -e "$HERE/tools/Mesen.app" ] || ln -s "$MAIN/tools/Mesen.app" "$HERE/tools/Mesen.app"
[ -e "$HERE/tools/bin" ] || ln -s "$MAIN/tools/bin" "$HERE/tools/bin"

# Seed generated savestates so boot-chain fixtures don't replay the whole
# game, plus build/ninja (the content latches and .ninja_log; ninja treats
# an edge with no build-log entry as never built, so seeded states without
# the log would replay the whole chain). -p preserves mtimes so the log's
# recorded times still describe the copied files; real drift regenerates
# through the latch edges' content compare.
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

# State the seed's freshness with the same code the runtime check uses.
if [ -d "$HERE/build/states" ]; then
  echo
  python3 "$HERE/tools/tests/lib/compose.py" --check-states || {
    echo
    echo "The seed is stale AS SEEDED. Re-confirm any time with:"
    echo "    python3 tools/tests/lib/compose.py --check-states"
  }
fi
