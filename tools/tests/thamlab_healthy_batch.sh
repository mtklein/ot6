#!/bin/sh
# thamlab_healthy_batch.sh -- healthy-level agent's batch wrapper.
# Same shape as thamlab_batch.sh, but substitutes into the healthy-level
# probes (which boot the thamlab_*_healthy fixtures baked by
# probe_thamlab_grind.lua):
#   lab=flame  -> probe_thamlab_healthy_flame.lua  (@STRATEGY@ nuke|control,
#                 @HOLD@ = seed frames, @BANK@)
#   lab=ambush -> probe_thamlab_healthy_ambush.lua (@STRATEGY@ ambush-fix|
#                 ambush-fix-noboost|ambush-fix-fight, @SEED@ = seed frames)
#
#   tools/tests/thamlab_healthy_batch.sh <lab> <strategy> <seed> [seed ...]
#
# Env knobs: BANK (flame only, default 2), JOBS (clamped to 3), TAG.
# Results and per-run logs land in build/thamlab/.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LAB="${1:?usage: thamlab_healthy_batch.sh <lab> <strategy> <seed> [seed ...]}"
STRATEGY="${2:?usage: thamlab_healthy_batch.sh <lab> <strategy> <seed> [seed ...]}"
shift 2
[ $# -gt 0 ] || { echo "no seeds given"; exit 2; }
BANK="${BANK:-2}"
JOBS="${JOBS:-3}"
[ "$JOBS" -le 3 ] || JOBS=3
TAG="${TAG:-healthy_${LAB}_${STRATEGY}}"
OUT="$ROOT/build/thamlab"
mkdir -p "$OUT"

case "$LAB" in
  flame)  SRC="$ROOT/tools/tests/probe_thamlab_healthy_flame.lua" ;;
  ambush) SRC="$ROOT/tools/tests/probe_thamlab_healthy_ambush.lua" ;;
  *) echo "unknown lab $LAB"; exit 2 ;;
esac

run_one() {
  seed=$1
  name="${TAG}_s${seed}"
  lua="$OUT/$name.lua"
  sed -e "s/@STRATEGY@/$STRATEGY/" -e "s/@SEED@/$seed/" \
      -e "s/@HOLD@/$seed/" -e "s/@BANK@/$BANK/" \
      "$SRC" > "$lua"
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
