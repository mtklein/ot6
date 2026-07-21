#!/bin/sh
# frontier_stamp.sh -- the freshness gate for a minted frontier savestate.
#
# ISSUE #2: a minted state is a function of (ROM bytes, its generator .lua,
# and lib/ot6.lua -- the shared driver every generator dofile()s).  The
# Makefile's .rom-copy content-clock already re-mints on a ROM byte change,
# but NOTHING watched the other two: a gen_*.lua or lib edit that left the ROM
# alone never refreshed an already-minted fixture, so the savestate silently
# drifted from the script that would mint it today.  This adds the missing
# generator+lib axis, in the same "compare a stamp, re-mint on a difference"
# shape the ROM gate already uses -- but keyed on CONTENT, so a mere mtime bump
# (a `git checkout`, a worktree cp) re-mints nothing.
#
# The gate lives in one small script, not inline in the mint macro, so the
# decision is unit-testable without the emulator (see frontier_gate_selftest
# in the Makefile) and reads identically for `mint` and `smint`.
#
#   frontier_stamp.sh needsmint <state> <generator>  # exit 0 = re-mint, 1 = fresh
#   frontier_stamp.sh write     <state> <generator>  # record the provenance stamp
#   frontier_stamp.sh sig       <generator>          # print the (gen+lib) signature
#
# The signature is `<sha256 of generator ++ lib/ot6.lua> <generator-basename>`.
# The generator name rides along so a consumer (lib/compose.py) can re-derive
# and check the same signature at load time -- the loud, fail-closed half of
# the guard for a fixture that reaches a test WITHOUT passing the mint gate
# first (a worktree-setup seed that a local edit has since drifted).
set -u

# OT6_ROOT lets the selftest point the gate at a mock tree; the default is the
# real tree this script lives in (lib/ -> tests/ -> tools/ -> root).
ROOT="${OT6_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
STATES="$ROOT/build/states"

# sha256(<generator source> ++ <shared driver>) plus the generator's name.
# Order is fixed (generator first) so the digest is reproducible from either
# side.  lib/ot6.lua is THE shared dependency: every gen_*.lua dofile()s it and
# nothing else (verified: no generator dofile()s any other helper), so this
# pair is the whole non-ROM input to a mint.
sig() {
  gen="$1"
  printf '%s %s' \
    "$(cat "$ROOT/tools/tests/$gen.lua" "$ROOT/tools/tests/lib/ot6.lua" \
        | shasum -a 256 | cut -c1-64)" \
    "$gen"
}

cmd="${1:?usage: frontier_stamp.sh needsmint|write|sig ...}"
case "$cmd" in
  sig)
    sig "${2:?sig needs a generator}"
    ;;
  write)
    state="${2:?write needs a state}"; gen="${3:?write needs a generator}"
    sig "$gen" > "$STATES/$state.stamp"
    ;;
  needsmint)
    state="${2:?needsmint needs a state}"; gen="${3:?needsmint needs a generator}"
    mss="$STATES/$state.mss"
    stamp="$STATES/$state.stamp"
    [ -f "$mss" ] || exit 0                          # never minted -> mint
    [ "$STATES/.rom-copy" -nt "$mss" ] && exit 0     # ROM bytes changed -> re-mint
    [ "$(sig "$gen")" = "$(cat "$stamp" 2>/dev/null)" ] || exit 0  # gen/lib changed
    exit 1                                           # fresh: skip
    ;;
  *)
    echo "frontier_stamp.sh: unknown command '$cmd'" >&2
    exit 2
    ;;
esac
