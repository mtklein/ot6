#!/bin/sh
# sfigarolab_batch.sh -- run a batch of South Figaro gate-soldier lab
# attempts (issue #193).
#
#   tools/tests/sfigarolab_batch.sh <policy> <seed> [seed ...]
#
#   policy  control | boostfight | breakfirst | heal75 | heal75b0 | tonics |
#           front | run | stealrun   (see lab_sfigaro_gate.lua)
#   seed    phases of $021e (period 60) to hold before walking to the
#           soldier; the hold-to-battle latency is quantized to 4 frames,
#           so 0..56 step 4 is the whole cycle
#
# Substitutes each seed into lab_sfigaro_gate.lua, runs the variants under
# run.sh with bounded parallelism (JOBS, default 3, clamped to 3), and
# prints the [result] line per run.  The fixture is the graph's own
# build/states/locke_scenario.mss (gen_sfigaro's boot state).
#
# Results and per-run logs land in build/attempts/locke-solo-lab/<TAG>_s<seed>.log
# (TAG defaults to the policy).  Every attempt is kept.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
POLICY="${1:?usage: sfigarolab_batch.sh <policy> <seed> [seed ...]}"
shift 1
[ $# -gt 0 ] || { echo "no seeds given"; exit 2; }
JOBS="${JOBS:-3}"
TAG="${TAG:-$POLICY}"
[ "$JOBS" -le 3 ] || JOBS=3
OUT="${OUT:-$ROOT/build/attempts/locke-solo-lab}"
mkdir -p "$OUT"

run_one() {
  seed=$1
  name="${TAG}_s${seed}"
  lua="$OUT/$name.lua"
  sed -e "s/@POLICY@/$POLICY/" -e "s/@SEED@/$seed/" \
      "$ROOT/tools/tests/lab_sfigaro_gate.lua" > "$lua"
  OT6_TIMEOUT="${OT6_TIMEOUT:-900}" OT6_WORKER="gatelab-$name" \
    OT6_ARTIFACT_DIR="$OUT/artifacts" \
    "$ROOT/tools/tests/run.sh" "$lua" "$OUT/$name.log" > /dev/null 2>&1
  grep -h '^\[ot6\] \[result\]' "$OUT/$name.log" || echo "[result-missing] $name"
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
