#!/bin/sh
# run_golden_save.sh check|negative|redrun <fixture dir> <ok-file> [want] -- one golden save (#389).
#
# Continues the fixture's battery on today's ROM through
# tools/tests/save_golden.lua (run.sh, OT6_SRAM_CHECKPOINT), keeps the battery
# the run leaves (OT6_CAPTURE_SRM), and has tools/golden_saves.py hold the
# run's log and that battery to the fixture file.  `negative` wants the
# check to refuse the fixture (the corrupted one), and the run itself to
# finish: the refusal must come from the check, not from a broken run, and
# name `want` (default "esper").  OT6_ROM boots a mutant ROM (run.sh), and
# OT6_GOLDEN_TAG keeps its log apart.  `redrun` wants the run itself red,
# its first FAIL line naming `want` (a mutant ROM's run).
#
# Logs: build/golden/<version>_<key>.log, the battery beside it (.srm).
set -u
mode="${1:?check|negative}"
fx="${2:?fixture dir}"
ok="${3:?ok path}"
want="${4:-esper}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
n="golden_${OT6_GOLDEN_TAG:-}$(echo "${fx#tools/tests/golden-saves/}" | tr '/.' '__')"
mkdir -p build/golden "$(dirname "$ok")"
log="build/golden/$n.log"
srm="build/golden/$n.srm"
rm -f "$srm" "$ok"
if [ "$mode" = redrun ]; then
  # the run itself must go red, its FAIL line naming `want`
  if OT6_WORKER="$n" OT6_SRAM_CHECKPOINT="$fx" \
     tools/tests/run.sh tools/tests/save_golden.lua "$log" >/dev/null 2>&1; then
    echo "FAIL: golden save $fx passed on ${OT6_ROM:-build/ot6.sfc}; it must go red -- $log"
    exit 1
  fi
  line=$(grep -m1 '^\[ot6\] FAIL' "$log")
  case "$line" in
    *"$want"*) echo "golden negative: red as it must be: $line"; : > "$ok"; exit 0 ;;
  esac
  echo "FAIL: golden save $fx went red, but not for '$want': $line -- $log"
  exit 1
fi
if ! OT6_WORKER="$n" OT6_SRAM_CHECKPOINT="$fx" OT6_CAPTURE_SRM="$srm" \
     tools/tests/run.sh tools/tests/save_golden.lua "$log" >/dev/null 2>&1
then
  echo "FAIL: golden save $fx: the run failed -- $log"
  grep -E 'FAIL|assertEq|Error' "$log" | tail -5
  exit 1
fi
if [ "$mode" = negative ]; then
  python3 tools/golden_saves.py negative "$fx" "$log" "$srm" "$want" > "$log.check" 2>/dev/null
else
  python3 tools/golden_saves.py check "$fx" "$log" "$srm" > "$log.check" 2>/dev/null
fi
rc=$?
cat "$log.check"
[ "$rc" -eq 0 ] || exit 1
: > "$ok"
