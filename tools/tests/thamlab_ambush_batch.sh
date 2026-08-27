#!/bin/sh
# thamlab_ambush_batch.sh -- ambush-strategy agent's batch wrapper.
#
#   tools/tests/thamlab_ambush_batch.sh <strategy> <seed> [seed ...]
#
#   strategy  ambush-fix | ambush-fix-noboost | ambush-fix-fight
#             (see probe_thamlab_ambush_fix.lua)
#   seed      frames to stand still before engaging (only seed mod 60
#             matters -- $021e has period 60)
#
# Substitutes into probe_thamlab_ambush_fix.lua, runs under run.sh with
# bounded parallelism (JOBS <= 3, the campaign's per-agent ceiling), and
# prints the [result] line per run.  Results/logs land in build/thamlab/.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
STRATEGY="${1:?usage: thamlab_ambush_batch.sh <strategy> <seed> [seed ...]}"
shift 1
[ $# -gt 0 ] || { echo "no seeds given"; exit 2; }
JOBS="${JOBS:-3}"
[ "$JOBS" -le 3 ] || JOBS=3
TAG="${TAG:-$(echo "$STRATEGY" | tr '-' '_')}"
OUT="$ROOT/build/thamlab"
mkdir -p "$OUT"

run_one() {
  seed=$1
  name="${TAG}_s${seed}"
  lua="$OUT/$name.lua"
  sed -e "s/@STRATEGY@/$STRATEGY/" -e "s/@SEED@/$seed/" \
      "$ROOT/tools/tests/probe_thamlab_ambush_fix.lua" > "$lua"
  OT6_LIVE=0 OT6_TIMEOUT=900 OT6_WORKER="thamlab-$name" \
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
