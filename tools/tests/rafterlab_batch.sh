#!/bin/sh
# rafterlab_batch.sh -- run a batch of rafter-crossing experiments.
#
#   tools/tests/rafterlab_batch.sh <strategy> <hold> [hold ...]
#
# Substitutes each hold into probe_rafterlab_template.lua, runs the
# variants under run.sh with bounded parallelism, and prints the [result]
# line per run.  Knobs ride in as environment variables (defaults match
# the template): RUNTRY, RADIUS, STUCKCAP, PANIC, JOBS, TAG.
#
# Results and per-run logs land in build/rafterlab/.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
STRATEGY="${1:?usage: rafterlab_batch.sh <strategy> <hold> [hold ...]}"
shift
[ $# -gt 0 ] || { echo "no holds given"; exit 2; }
FIXTURE="${FIXTURE:-rafterlab_catwalk}"
RUNTRY="${RUNTRY:-0}"
RADIUS="${RADIUS:-2}"
STUCKCAP="${STUCKCAP:-600}"
PANIC="${PANIC:-6000}"
JOBS="${JOBS:-8}"
TAG="${TAG:-$STRATEGY}"
OUT="$ROOT/build/rafterlab"
mkdir -p "$OUT"

run_one() {
  hold=$1
  name="${TAG}_h${hold}"
  lua="$OUT/$name.lua"
  sed -e "s/@STRATEGY@/$STRATEGY/" -e "s/@HOLD@/$hold/" \
      -e "s/@FIXTURE@/$FIXTURE/" \
      -e "s/@RUNTRY@/$RUNTRY/" -e "s/@RADIUS@/$RADIUS/" \
      -e "s/@STUCKCAP@/$STUCKCAP/" -e "s/@PANIC@/$PANIC/" \
      "$ROOT/tools/tests/probe_rafterlab_template.lua" > "$lua"
  OT6_LIVE=0 OT6_TIMEOUT=900 OT6_WORKER="rafterlab-$name" \
    "$ROOT/tools/tests/run.sh" "$lua" "$OUT/$name.log" > /dev/null 2>&1
  grep -h '^\[ot6\] \[result\]' "$OUT/$name.log" || echo "[result-missing] $name"
}

pids=""
n=0
for hold in "$@"; do
  run_one "$hold" &
  pids="$pids $!"
  n=$(( n + 1 ))
  if [ $(( n % JOBS )) -eq 0 ]; then wait; fi
done
wait
