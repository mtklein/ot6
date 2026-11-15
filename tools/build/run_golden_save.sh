#!/bin/sh
# run_golden_save.sh check|negative <fixture dir> <ok-file> -- one golden save (#389).
#
# Continues the fixture's battery on today's ROM through
# tools/tests/save_golden.lua (run.sh, OT6_SRAM_CHECKPOINT), keeps the battery
# the run leaves (OT6_CAPTURE_SRM), and has tools/golden_saves.py hold the
# run's log and that battery to the fixture file.  `negative` wants the
# check to refuse the fixture (the corrupted one), and the run itself to
# finish: the refusal must come from the check, not from a broken run.
#
# Logs: build/golden/<version>_<key>.log, the battery beside it (.srm).
set -u
mode="${1:?check|negative}"
fx="${2:?fixture dir}"
ok="${3:?ok path}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
n="golden_$(echo "${fx#tools/tests/golden-saves/}" | tr '/.' '__')"
mkdir -p build/golden "$(dirname "$ok")"
log="build/golden/$n.log"
srm="build/golden/$n.srm"
rm -f "$srm" "$ok"
if ! OT6_WORKER="$n" OT6_SRAM_CHECKPOINT="$fx" OT6_CAPTURE_SRM="$srm" \
     tools/tests/run.sh tools/tests/save_golden.lua "$log" >/dev/null 2>&1
then
  echo "FAIL: golden save $fx: the run failed -- $log"
  grep -E 'FAIL|assertEq|Error' "$log" | tail -5
  exit 1
fi
python3 tools/golden_saves.py "$mode" "$fx" "$log" "$srm" > "$log.check" 2>/dev/null
rc=$?
cat "$log.check"
[ "$rc" -eq 0 ] || exit 1
: > "$ok"
