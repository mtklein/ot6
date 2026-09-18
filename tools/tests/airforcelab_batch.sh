#!/bin/sh
# airforcelab_batch.sh -- run a batch of Air Force strategy-lab experiments (#201).
#
#   tools/tests/airforcelab_batch.sh <policy> <idle> [idle ...]
#
#   policy  a POLICIES key in lab_airforce_template.lua
#           (control | bank0 | bank3 | keyboost | pods | bay | body | summon |
#            pods_summon | pods_bank0 | heal70 | terrafire | pods_terrafire)
#   idle    frames to stand still at the doorstep before tapping on (shifts
#           $021e; only idle mod 60 matters -- $021e has period 60)
#   FIXTURE airforcelab_teaser (default; the bake found no later window)
#
# Substitutes each idle into lab_airforce_template.lua, runs the variants
# under run.sh with bounded parallelism, and prints the [result] line per
# run.  Needs build/states/<FIXTURE>.mss (lab_airforce_bake.lua).
#
# Machine etiquette: JOBS defaults to 3 and is clamped to 3 (the lab
# campaigns' ceiling on concurrent emulator runs per agent).
#
# Results and per-run logs land in build/attempts/airforce-lab/<TAG>_i<idle>.log;
# the aggregate is tools/tests/airforcelab_aggregate.py.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
POLICY="${1:?usage: airforcelab_batch.sh <policy> <idle> [idle ...]}"
shift
[ $# -gt 0 ] || { echo "no idles given"; exit 2; }
JOBS="${JOBS:-3}"
[ "$JOBS" -le 3 ] || JOBS=3
TAG="${TAG:-$POLICY}"
FIXTURE="${FIXTURE:-airforcelab_teaser}"
OUT="$ROOT/build/attempts/airforce-lab"
mkdir -p "$OUT"

run_one() {
  idle=$1
  name="${TAG}_i${idle}"
  lua="$OUT/$name.lua"
  sed -e "s/@POLICY@/$POLICY/" -e "s/@IDLE@/$idle/" -e "s/@FIXTURE@/$FIXTURE/" \
      "$ROOT/tools/tests/lab_airforce_template.lua" > "$lua"
  OT6_TIMEOUT=1800 OT6_WORKER="airforcelab-$name" \
    OT6_ARTIFACT_DIR="$OUT/artifacts" \
    "$ROOT/tools/tests/run.sh" "$lua" "$OUT/$name.log" > /dev/null 2>&1
  grep -h '^\[ot6\] \[result\]' "$OUT/$name.log" || echo "[result-missing] $name"
}

n=0
for idle in "$@"; do
  run_one "$idle" &
  n=$(( n + 1 ))
  if [ $(( n % JOBS )) -eq 0 ]; then wait; fi
done
wait
