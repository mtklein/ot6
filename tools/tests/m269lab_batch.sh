#!/bin/sh
# m269lab_batch.sh -- run a batch of map-269 random lab attempts (issue #171).
#
#   tools/tests/m269lab_batch.sh <policy> <seed> [seed ...]
#
#   policy  control | cared | allback | breakfirst | boostfight
#           (see lab_map269_random.lua)
#   seed    phases of $021e (period 60) to hold before walking; only
#           seed mod 60 is distinct as a battle seed, quantized to 4
#   MODE    fight (default: one random) | walk (the whole map-269 leg)
#
# Substitutes each seed into lab_map269_random.lua, runs the variants under
# run.sh with bounded parallelism (JOBS, default 3, clamped to 3), and
# prints the [result] / [walkresult] line per run.  The fixture is
# build/states/m269lab_pre.mss (baked by tools/tests/probe_m269lab_bake.lua).
#
# Results and per-run logs land in build/m269lab/<TAG>_s<seed>.log (TAG
# defaults to the policy, or <policy>_walk in walk mode).
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
POLICY="${1:?usage: m269lab_batch.sh <policy> <seed> [seed ...]}"
shift 1
[ $# -gt 0 ] || { echo "no seeds given"; exit 2; }
MODE="${MODE:-fight}"
JOBS="${JOBS:-3}"
if [ "$MODE" = "walk" ]; then DEFTAG="${POLICY}_walk"; else DEFTAG="$POLICY"; fi
TAG="${TAG:-$DEFTAG}"          # output name prefix (a re-pass keeps pass 1's logs)
[ "$JOBS" -le 3 ] || JOBS=3
OUT="$ROOT/build/m269lab"
mkdir -p "$OUT"

run_one() {
  seed=$1
  name="${TAG}_s${seed}"
  lua="$OUT/$name.lua"
  sed -e "s/@POLICY@/$POLICY/" -e "s/@SEED@/$seed/" -e "s/@MODE@/$MODE/" \
      "$ROOT/tools/tests/lab_map269_random.lua" > "$lua"
  OT6_LIVE=0 OT6_TIMEOUT=1800 OT6_WORKER="m269lab-$name" \
    OT6_ARTIFACT_DIR="$OUT/artifacts" \
    "$ROOT/tools/tests/run.sh" "$lua" "$OUT/$name.log" > /dev/null 2>&1
  grep -h '^\[ot6\] \[\(result\|walkresult\)\]' "$OUT/$name.log" || echo "[result-missing] $name"
}

pids=""
n=0
for seed in "$@"; do
  run_one "$seed" &
  pids="$pids $!"
  n=$(( n + 1 ))
  if [ $(( n % JOBS )) -eq 0 ]; then wait; fi
done
wait
