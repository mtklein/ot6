#!/bin/sh
# rafterlab_ultros_gen.sh -- play battle 104 (Ultros 2) from a rafter-lab
# arrival snapshot with the GENERATOR's own fighter (gen_opera7_blackjack.lua),
# not a copy of it.
#
#   tools/tests/rafterlab_ultros_gen.sh <tag> <state>
#
# <state> is the basename of a build/states/<state>.mss.lua sidecar -- one of
# the rafterlab_<batch>_arrival_<n>.mss saves rafterlab_batch_gen.sh makes
# with RAFTERLAB_ARRIVALS=1: the party at (14,7) facing Ultros, one A press
# from the battle, with whatever HP the crossing left it.  Makes a scratch
# copy of gen_opera7_blackjack.lua in build/rafterlab/ with
#   * DOOR swapped from ultros2_entry to that snapshot;
#   * every H.saveState name prefixed rafterlab_<tag>_, so nothing is written
#     into the fixture run (build/states/blackjack.mss stays untouched),
# and runs it through run.sh.  The whole generator runs (the Blackjack ride
# after the fight is a minute); the measurement is the "[ultros2]" lines:
# "hit fN slot=S char=C a->b (-d)" per hit taken, "battle done ... party
# [...]" and "attempt N WON battle 104" / the loss lines.
#
# Output: build/rafterlab/ultros_<tag>.log.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TAG="${1:?usage: rafterlab_ultros_gen.sh <tag> <state>}"
STATE="${2:?arrival state basename (build/states/<state>.mss.lua)}"
OUT="$ROOT/build/rafterlab"
mkdir -p "$OUT"
SRC="$ROOT/tools/tests/gen_opera7_blackjack.lua"
LUA="$OUT/ultros_$TAG.lua"
# A lab crossing run ends in its designed FAIL (nothing banks at floor
# 99999), and run.sh publishes nothing from a failed run, so the arrivals sit
# in the retained workspace.  compose.py resolves loadState references
# against build/states only: copy the pair in from the workspace (the .mss
# and its sidecar, unchanged; provenance is the batch log beside it).
if [ ! -f "$ROOT/build/states/$STATE.mss.lua" ]; then
  src=$(ls "$ROOT"/build/test-runs/rafterlab-gen-*/artifacts/"$STATE.mss.lua" 2>/dev/null | head -1)
  [ -n "$src" ] || { echo "no sidecar build/states/$STATE.mss.lua, and no retained lab workspace holds one"; exit 2; }
  cp "${src%.lua}" "$src" "$ROOT/build/states/" || exit 2
  echo "[lab] $TAG: staged $STATE from $(dirname "$src") into build/states/"
fi

DOOR_ANCHOR='local DOOR = "build/states/ultros2_entry.mss.lua"'
n=$(grep -cF "$DOOR_ANCHOR" "$SRC")
[ "$n" -eq 1 ] || { echo "anchor '$DOOR_ANCHOR' matches $n times in $SRC, want 1"; exit 2; }

sed -e "s|^local DOOR = \"build/states/ultros2_entry.mss.lua\"\$|local DOOR = \"build/states/$STATE.mss.lua\"|" \
    -e "s/H\.saveState(\"\([a-z0-9_]*\)\.mss\")/H.saveState(\"rafterlab_${TAG}_\1.mss\")/g" \
    "$SRC" > "$LUA"
grep -qF "local DOOR = \"build/states/$STATE.mss.lua\"" "$LUA" || { echo "DOOR substitution failed"; exit 2; }
grep -q 'saveState("blackjack.mss")' "$LUA" && { echo "saveState rename failed"; exit 2; }

echo "[lab] $TAG: battle 104 from $STATE -> $OUT/ultros_$TAG.log"
OT6_TIMEOUT="${OT6_TIMEOUT:-1200}" OT6_WORKER="rafterlab-ultros-$TAG" \
  "$ROOT/tools/tests/run.sh" "$LUA" "$OUT/ultros_$TAG.log" > /dev/null 2>&1
rc=$?
grep -h '^\[ot6\] \[ultros2\] \(battle up\|hit \|battle done\|attempt [0-9]* WON\|PARTY WIPED\|GAME OVER\|ATTEMPT\)' "$OUT/ultros_$TAG.log"
grep -h '^\[ot6\] \(PASS (frame\|FAIL:\)' "$OUT/ultros_$TAG.log" || echo "[lab] $TAG: no verdict (rc=$rc)"
