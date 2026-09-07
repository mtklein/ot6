#!/bin/sh
# rafterlab_batch_gen.sh -- measure the rafter crossing with the GENERATOR's
# own crossing code, not a copy of it.
#
#   tools/tests/rafterlab_batch_gen.sh <tag> <panic> <h1> <h2> <h3> <h4> <h5> <h6>
#
# Makes a scratch copy of gen_opera6_rafter.lua in build/rafterlab/ with
#   * MIN_CROSS_TIMER raised to 99999, so no rung is accepted and every one
#     of the six arrangements is crossed and recorded.  The copy therefore
#     ends with the ladder's own "crossed within the ladder" assert failing:
#     a FAIL verdict is the expected end of a lab run, and the data is the
#     six "[rafters] attempt N did not bank ... timer T left, F fights"
#     lines before it;
#   * HOLDS replaced by the six holds given (the generator has six rungs,
#     so exactly six are required);
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
# lines (and, since #164, "[rafters] attempt N arrival hp at (14,7): c1 H/M
# c4 H/M c5 H/M, ...").  Fold them with rafterlab_aggregate_gen.py.
#
# Optional environment (both leave the lineage's generator untouched):
#   RAFTERLAB_DRIVER='{ tactical = true, boost = false, cure = false, items = true, healPercent = 33, cadence = 12 }'
#       replaces the generator's one-line RAT_DRIVER table (the rat fights'
#       newFightDriver options), so a candidate fight policy is measured with
#       the same crossing code from the same catwalk snapshot;
#   RAFTERLAB_ARRIVALS=1
#       sets LAB_ARRIVAL_PREFIX so every arrival at (14,7) -- banked or not,
#       facing Ultros -- is saved as build/states/rafterlab_<tag>_arrival_<n>.mss
#       (+ .lua sidecar) for rafterlab_ultros_gen.sh to play battle 104 from.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TAG="${1:?usage: rafterlab_batch_gen.sh <tag> <panic> <h1> ... <h6>}"
PANIC="${2:?panic floor}"
shift 2
[ $# -eq 6 ] || { echo "exactly six holds are required (the generator has six sampling rungs), got $#"; exit 2; }
HOLDS="$1, $2, $3, $4, $5, $6"
DRIVER="${RAFTERLAB_DRIVER:-}"
ARRIVALS="${RAFTERLAB_ARRIVALS:-0}"
OUT="$ROOT/build/rafterlab"
mkdir -p "$OUT"
SRC="$ROOT/tools/tests/gen_opera6_rafter.lua"
LUA="$OUT/gen_$TAG.lua"

DRIVER_ANCHOR='local RAT_DRIVER = { tactical = true, boost = false, cure = false, items = false, cadence = 12 }'
PREFIX_ANCHOR='local LAB_ARRIVAL_PREFIX = nil'
# Every anchor must match exactly once, or the copy measures something else.
for pat in 'local RADIUS, STUCKCAP, PANIC, GATEK = 1, 600, 6000, 4' \
           'local MIN_CROSS_TIMER = 900' \
           'local HOLDS = { 0, 250, 550, 900, 1300, 1750 }' \
           "$DRIVER_ANCHOR" "$PREFIX_ANCHOR"; do
  n=$(grep -cF "$pat" "$SRC")
  [ "$n" -eq 1 ] || { echo "anchor '$pat' matches $n times in $SRC, want 1"; exit 2; }
done
case "$DRIVER" in
  *[/\&\\]*) echo "RAFTERLAB_DRIVER must not contain / & or \\ (it is a sed replacement)"; exit 2 ;;
esac

sed -e "s/^\( *\)local RADIUS, STUCKCAP, PANIC, GATEK = 1, 600, 6000, 4\$/\1local RADIUS, STUCKCAP, PANIC, GATEK = 1, 600, $PANIC, 4/" \
    -e "s/^local MIN_CROSS_TIMER = 900\$/local MIN_CROSS_TIMER = 99999/" \
    -e "s/^local HOLDS = { 0, 250, 550, 900, 1300, 1750 }\$/local HOLDS = { $HOLDS }/" \
    -e "s/H\.saveState(\"\([a-z0-9_]*\)\.mss\")/H.saveState(\"rafterlab_${TAG}_\1.mss\")/g" \
    "$SRC" > "$LUA"
if [ -n "$DRIVER" ]; then
  sed -i.bak -e "s/^local RAT_DRIVER = { tactical = true, boost = false, cure = false, items = false, cadence = 12 }\$/local RAT_DRIVER = $DRIVER/" "$LUA"
  grep -qF "local RAT_DRIVER = $DRIVER" "$LUA" || { echo "RAT_DRIVER substitution failed"; exit 2; }
fi
if [ "$ARRIVALS" = 1 ]; then
  sed -i.bak -e "s/^local LAB_ARRIVAL_PREFIX = nil\$/local LAB_ARRIVAL_PREFIX = \"rafterlab_${TAG}_\"/" "$LUA"
  grep -qF "local LAB_ARRIVAL_PREFIX = \"rafterlab_${TAG}_\"" "$LUA" || { echo "LAB_ARRIVAL_PREFIX substitution failed"; exit 2; }
fi
rm -f "$LUA.bak"
grep -q "PANIC, GATEK = 1, 600, $PANIC, 4" "$LUA" || { echo "PANIC substitution failed"; exit 2; }
grep -q "MIN_CROSS_TIMER = 99999" "$LUA" || { echo "MIN_CROSS_TIMER substitution failed"; exit 2; }
grep -q "HOLDS = { $HOLDS }" "$LUA" || { echo "HOLDS substitution failed"; exit 2; }
grep -q 'saveState("ultros2_entry.mss")' "$LUA" && { echo "saveState rename failed"; exit 2; }

echo "[lab] $TAG: panic=$PANIC holds={ $HOLDS } driver=${DRIVER:-<shipped>} arrivals=$ARRIVALS -> $OUT/gen_$TAG.log"
OT6_LIVE=0 OT6_TIMEOUT="${OT6_TIMEOUT:-2400}" OT6_WORKER="rafterlab-gen-$TAG" \
  "$ROOT/tools/tests/run.sh" "$LUA" "$OUT/gen_$TAG.log" > /dev/null 2>&1
rc=$?
grep -h '^\[ot6\] \[rafters\] \(on the catwalk\|bag on the catwalk\|attempt [0-9]* \(ARRIVED\|did not\|arrival hp\)\)' "$OUT/gen_$TAG.log"
grep -h '^\[ot6\] \(PASS (frame\|FAIL:\)' "$OUT/gen_$TAG.log" || echo "[lab] $TAG: no verdict (rc=$rc)"
echo "[lab] $TAG: a FAIL on the ladder assert is the expected end of a lab run (nothing is banked at floor 99999)"
