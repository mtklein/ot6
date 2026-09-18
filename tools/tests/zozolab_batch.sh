#!/bin/sh
# zozolab_batch.sh -- run a batch of Zozo street lab attempts (issue #155).
#
#   tools/tests/zozolab_batch.sh <policy> <seed> [seed ...]
#
#   policy  control | allback | allfront | breakfirst | runic
#           (see lab_zozo_street.lua)
#   seed    phases of $021e (period 60) to hold before walking; only
#           seed mod 60 is distinct as a battle seed, but the hold also
#           moves the map's NPC walkers, so the formation that rolls
#           varies with it too
#
# Substitutes each seed into lab_zozo_street.lua, runs the variants under
# run.sh with bounded parallelism (JOBS, default 3, clamped to 3), and
# prints the [result] line per run.  The fixture is build/states/zozolab_pre.mss
# (baked by build/zozolab/gen_bake.lua).
#
# Results and per-run logs land in build/zozolab/<TAG>_s<seed>.log (TAG
# defaults to the policy).
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
POLICY="${1:?usage: zozolab_batch.sh <policy> <seed> [seed ...]}"
shift 1
[ $# -gt 0 ] || { echo "no seeds given"; exit 2; }
JOBS="${JOBS:-3}"
TAG="${TAG:-$POLICY}"          # output name prefix (a re-pass keeps pass 1's logs)
[ "$JOBS" -le 3 ] || JOBS=3
OUT="$ROOT/build/zozolab"
mkdir -p "$OUT"

run_one() {
  seed=$1
  name="${TAG}_s${seed}"
  lua="$OUT/$name.lua"
  sed -e "s/@POLICY@/$POLICY/" -e "s/@SEED@/$seed/" \
      "$ROOT/tools/tests/lab_zozo_street.lua" > "$lua"
  OT6_TIMEOUT=900 OT6_WORKER="zozolab-$name" \
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
