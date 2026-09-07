#!/bin/sh
# rafterlab_batch_gen.sh -- measure the rafter crossing with the GENERATOR's
# own crossing code, not a copy of it.
#
#   tools/tests/rafterlab_batch_gen.sh <tag> <panic> <h1> <h2> <h3> <h4> <h5> <h6>
#
# Makes a scratch copy of gen_opera6_rafter.lua in build/rafterlab/ with
#   * TARGET_CROSS_TIMER raised to 99999, so no sampling rung is accepted and
#     every one of the six arrangements is crossed and recorded (the replay
#     rung then re-runs the best of them, which is a free re-test of the
#     "a reload replays the crossing bit-for-bit" claim);
#   * HOLDS replaced by the six holds given (the generator has six sampling
#     rungs, so exactly six are required);
#   * the dodge policy's PANIC floor replaced by <panic>;
#   * every H.saveState name prefixed rafterlab_<tag>_, so parallel runs
#     write nothing into the fixture lineage (build/states/ultros2_entry.mss
#     and the two mid-route checkpoints stay untouched),
# and runs it through run.sh.  The approach from opera_dance_done is replayed
# each run (about a minute), which is what makes every run start from the
# same catwalk snapshot: the "[rafters] on the catwalk" line must match
# across runs, or they are not comparable.
#
# Output: build/rafterlab/gen_<tag>.log; the per-attempt lines are the
# generator's own "[rafters] attempt N ... at (x,y), timer T left, F fights"
# lines.  Fold them with rafterlab_aggregate_gen.py.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TAG="${1:?usage: rafterlab_batch_gen.sh <tag> <panic> <h1> ... <h6>}"
PANIC="${2:?panic floor}"
shift 2
[ $# -eq 6 ] || { echo "exactly six holds are required (the generator has six sampling rungs), got $#"; exit 2; }
HOLDS="$1, $2, $3, $4, $5, $6"
OUT="$ROOT/build/rafterlab"
mkdir -p "$OUT"
SRC="$ROOT/tools/tests/gen_opera6_rafter.lua"
LUA="$OUT/gen_$TAG.lua"

# Every anchor must match exactly once, or the copy measures something else.
for pat in 'local RADIUS, STUCKCAP, PANIC, GATEK = 1, 600, 6000, 4' \
           'local TARGET_CROSS_TIMER = 6000' \
           'local HOLDS = { 0, 250, 550, 900, 1300, 1750 }'; do
  n=$(grep -cF "$pat" "$SRC")
  [ "$n" -eq 1 ] || { echo "anchor '$pat' matches $n times in $SRC, want 1"; exit 2; }
done

sed -e "s/^\( *\)local RADIUS, STUCKCAP, PANIC, GATEK = 1, 600, 6000, 4\$/\1local RADIUS, STUCKCAP, PANIC, GATEK = 1, 600, $PANIC, 4/" \
    -e "s/^local TARGET_CROSS_TIMER = 6000\$/local TARGET_CROSS_TIMER = 99999/" \
    -e "s/^local HOLDS = { 0, 250, 550, 900, 1300, 1750 }\$/local HOLDS = { $HOLDS }/" \
    -e "s/H\.saveState(\"\([a-z0-9_]*\)\.mss\")/H.saveState(\"rafterlab_${TAG}_\1.mss\")/g" \
    "$SRC" > "$LUA"
grep -q "PANIC, GATEK = 1, 600, $PANIC, 4" "$LUA" || { echo "PANIC substitution failed"; exit 2; }
grep -q "TARGET_CROSS_TIMER = 99999" "$LUA" || { echo "TARGET substitution failed"; exit 2; }
grep -q "HOLDS = { $HOLDS }" "$LUA" || { echo "HOLDS substitution failed"; exit 2; }
grep -q 'saveState("ultros2_entry.mss")' "$LUA" && { echo "saveState rename failed"; exit 2; }

echo "[lab] $TAG: panic=$PANIC holds={ $HOLDS } -> $OUT/gen_$TAG.log"
OT6_LIVE=0 OT6_TIMEOUT="${OT6_TIMEOUT:-2400}" OT6_WORKER="rafterlab-gen-$TAG" \
  "$ROOT/tools/tests/run.sh" "$LUA" "$OUT/gen_$TAG.log" > /dev/null 2>&1
rc=$?
grep -h '^\[ot6\] \[rafters\] \(on the catwalk\|attempt [0-9]* \(ARRIVED\|did not\)\|no rung\)' "$OUT/gen_$TAG.log"
grep -h '^\[ot6\] \(PASS (frame\|FAIL:\)' "$OUT/gen_$TAG.log" || echo "[lab] $TAG: no verdict (rc=$rc)"
