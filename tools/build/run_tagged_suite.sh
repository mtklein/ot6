#!/bin/sh
# run_tagged_suite.sh <test> <tag> <ok-file> [red <want>] -- one run of a
# suite under its own tag, for a suite configure.py runs more than once
# (battle_newgameloadouts: on two batteries, and on a mutant ROM).
#
# The environment (OT6_RAM_POWERON, OT6_SRAM_CHECKPOINT, OT6_ROM, OT6_DBG)
# arrives from the edge's `env =` splice.  The log is build/results/tagged/
# <tag>.log.  `red <want>` wants the run red, its first FAIL line naming
# <want> (a negative).
set -u
t="${1:?test}"
tag="${2:?tag}"
ok="${3:?ok path}"
mode="${4:-}"
want="${5:-}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
mkdir -p build/results/tagged "$(dirname "$ok")"
log="build/results/tagged/$tag.log"
rm -f "$ok"
# the ROM this run boots, by hash, so a log names the bytes it tested
romsig="rom sha256 $(shasum -a 256 "${OT6_ROM:-build/ot6.sfc}" | cut -d' ' -f1) ${OT6_ROM:-build/ot6.sfc}"
OT6_WORKER="$tag" tools/tests/run.sh "tools/tests/$t.lua" "$log" >/dev/null 2>&1
rc=$?
echo "$romsig" >> "$log"
echo "$tag: $romsig"
if [ "$mode" = red ]; then
  [ "$rc" -ne 0 ] || { echo "FAIL: $t ($tag) passed; it must go red -- $log"; exit 1; }
  line=$(grep -m1 '^\[ot6\] FAIL' "$log")
  case "$line" in
    *"$want"*) echo "$tag: red as it must be: $line"; : > "$ok"; exit 0 ;;
  esac
  echo "FAIL: $t ($tag) went red, but not for '$want': $line -- $log"
  exit 1
fi
if [ "$rc" -ne 0 ]; then
  echo "FAIL: $t ($tag) (rc=$rc) -- $log"
  grep -E 'FAIL|assertEq|Error' "$log" | tail -5
  exit "$rc"
fi
: > "$ok"
