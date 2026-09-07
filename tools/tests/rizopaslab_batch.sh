#!/bin/sh
# rizopaslab_batch.sh -- run a batch of Rizopas strategy-lab experiments (#162).
#
#   tools/tests/rizopaslab_batch.sh <policy> <idle> [idle ...]
#
#   policy  a POLICIES key in lab_rizopas_template.lua
#           (control | care | bank2 | allin | bankboss | pummel)
#   idle    frames to stand still on the jump row before the last step
#           (shifts $021e; only idle mod 60 matters -- $021e has period 60)
#
# Substitutes each idle into lab_rizopas_template.lua, runs the variants
# under run.sh with bounded parallelism, and prints the [result] line per
# run.  Needs build/states/falls_prejump.mss (lab_rizopas_bake.lua).
#
# Machine etiquette: JOBS defaults to 3 and is clamped to 3 (the lab
# campaigns' ceiling on concurrent emulator runs per agent).
#
# Results and per-run logs land in build/rizopaslab/; the aggregate is
# tools/tests/rizopaslab_aggregate.py.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
POLICY="${1:?usage: rizopaslab_batch.sh <policy> <idle> [idle ...]}"
shift
[ $# -gt 0 ] || { echo "no idles given"; exit 2; }
JOBS="${JOBS:-3}"
[ "$JOBS" -le 3 ] || JOBS=3
TAG="${TAG:-$POLICY}"
OUT="$ROOT/build/rizopaslab"
mkdir -p "$OUT"

run_one() {
  idle=$1
  name="${TAG}_i${idle}"
  lua="$OUT/$name.lua"
  sed -e "s/@POLICY@/$POLICY/" -e "s/@IDLE@/$idle/" \
      "$ROOT/tools/tests/lab_rizopas_template.lua" > "$lua"
  OT6_LIVE=0 OT6_TIMEOUT=1200 OT6_WORKER="rizopaslab-$name" \
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
