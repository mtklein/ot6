#!/bin/sh
# nerapalab_batch.sh -- run a batch of Nerapa strategy-lab experiments.
#
#   tools/tests/nerapalab_batch.sh <policy> <idle> [idle ...]
#
#   policy  a POLICIES key in lab_nerapa_template.lua
#           (control | breakfirst | allin | allin_bank2 | raise1 | noraise |
#            physical | physical_bank2 | physical_allin | physical_raise1)
#   idle    frames to stand still at the doorstep before the talk (shifts
#           $021e; only idle mod 60 matters -- $021e has period 60)
#
# Substitutes each idle into lab_nerapa_template.lua, runs the variants
# under run.sh with bounded parallelism, and prints the [result] line per
# run.  Needs build/states/nerapalab_doorstep.mss (lab_nerapa_bake.lua).
#
# Machine etiquette: JOBS defaults to 3 and is clamped to 3 (the lab
# campaigns' ceiling on concurrent emulator runs per agent).
#
# Results and per-run logs land in build/nerapalab/; the aggregate is
# tools/tests/nerapalab_aggregate.py.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
POLICY="${1:?usage: nerapalab_batch.sh <policy> <idle> [idle ...]}"
shift
[ $# -gt 0 ] || { echo "no idles given"; exit 2; }
JOBS="${JOBS:-3}"
[ "$JOBS" -le 3 ] || JOBS=3
TAG="${TAG:-$POLICY}"
OUT="$ROOT/build/nerapalab"
mkdir -p "$OUT"

run_one() {
  idle=$1
  name="${TAG}_i${idle}"
  lua="$OUT/$name.lua"
  sed -e "s/@POLICY@/$POLICY/" -e "s/@IDLE@/$idle/" \
      "$ROOT/tools/tests/lab_nerapa_template.lua" > "$lua"
  OT6_TIMEOUT=1200 OT6_WORKER="nerapalab-$name" \
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
