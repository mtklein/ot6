#!/bin/sh
# ifritlab_batch.sh -- run a batch of Ifrit & Shiva (battle 70) lab experiments.
#
#   tools/tests/ifritlab_batch.sh <strategy> <seed> [seed ...]
#
#   strategy  gen      the gen's own play today (all-slash ThunderBlade kit +
#                      lib newFightDriver {tactical,boost,bank=3,items}) -- the
#                      baseline control (slash chips only Shiva, never Ifrit)
#             classfix class-correct loadout (pierce for Ifrit's 6 pierce
#                      shields, slash for Shiva's 6 slash) + lib driver + a
#                      designated healer + nuke={Ice}
#             bespoke  the design-doc per-turn play: CELES casts boosted Ice
#                      ONLY while IFRIT holds the stage (Shiva absorbs ice),
#                      everyone else Fights class-correct (unboosted while the
#                      staged sibling still has shields -- chip is per-hit, so
#                      fast turns break sooner -- then boosted bursts once
#                      broken); one item healer; any actor revives with Fenix
#             taps     blind A-taps, the floor
#   seed      frames to stand still before engaging (shifts $021e; only
#             seed mod 60 matters -- $021e has period 60).  The [result] line
#             carries the engage phase and the $be the battle actually drew,
#             so seed collisions are visible rather than assumed.
#
# Substitutes each seed into probe_ifritlab_template.lua, runs the variants
# under run.sh with bounded parallelism, and prints the [result] line per run.
# Knobs ride in as environment variables (defaults match the template):
# HEALPCT, BANK, HEALER, JOBS, TAG, FIXTURE.
#
# Machine etiquette: JOBS defaults to 2 and is clamped to 2 (this campaign's
# ceiling on concurrent emulator runs per agent while a release census runs).
#
# Results and per-run logs land in build/ifritlab/.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
STRATEGY="${1:?usage: ifritlab_batch.sh <strategy> <seed> [seed ...]}"
shift
[ $# -gt 0 ] || { echo "no seeds given"; exit 2; }
FIXTURE="${FIXTURE:-ifritlab_entry}"
HEALPCT="${HEALPCT:-60}"
BANK="${BANK:-3}"
HEALER="${HEALER:-1}"
JOBS="${JOBS:-2}"
[ "$JOBS" -le 2 ] || JOBS=2
TAG="${TAG:-$STRATEGY}"
OUT="$ROOT/build/ifritlab"
mkdir -p "$OUT"

run_one() {
  seed=$1
  name="${TAG}_s${seed}"
  lua="$OUT/$name.lua"
  sed -e "s/@STRATEGY@/$STRATEGY/" -e "s/@SEED@/$seed/" \
      -e "s/@FIXTURE@/$FIXTURE/" -e "s/@HEALPCT@/$HEALPCT/" \
      -e "s/@BANK@/$BANK/" -e "s/@HEALER@/$HEALER/" \
      "$ROOT/tools/tests/probe_ifritlab_template.lua" > "$lua"
  OT6_LIVE=0 OT6_TIMEOUT=1200 OT6_WORKER="ifritlab-$name" \
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
