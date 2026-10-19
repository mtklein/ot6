#!/bin/sh
# stall_negative.sh: run.sh's heartbeat stall watch, negative controls.
#
#   sh tools/tests/lib/stall_negative.sh [hang|menu]...    (default: both)
#
# hang: a script spinning in an infinite Lua loop inside a frame callback.
# menu: a script parked in the field menu: frames advance, nothing happens.
# Each must be killed by run.sh as a STALL (not the wall-clock backstop),
# within OT6_HEARTBEAT plus slack, with the last progress frame and the
# seconds since in the report, and retried once (OT6_TIMEOUT_RETRIES=1: the
# retry policy is unchanged), ending in no verdict.  The window is set to
# 30 s here so the check is quick; the default is 120.
# Output: build/states/stall_<case>.log and .out.
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
OUT="$ROOT/build/states"
mkdir -p "$OUT"
WINDOW=30
SLACK=40      # poll (5 s) + heartbeat interval + kill + the emulator's start
fail() { echo "stall-negative: FAIL -- $1"; exit 1; }
[ $# -gt 0 ] || set -- hang menu
for c in "$@"; do
  LOG="$OUT/stall_$c.log"; STD="$OUT/stall_$c.out"
  case $c in
    hang) lua=stall_hang_negative.lua; env_ckpt= ;;
    menu) lua=stall_menu_negative.lua; env_ckpt=tools/tests/checkpoints/wor-owzer-v1 ;;
    *) fail "unknown case $c" ;;
  esac
  echo "stall-negative: $c: must be killed as a stall within ${WINDOW}s + slack..."
  t0=$(date +%s)
  if OT6_NO_PUBLISH=1 OT6_WORKER=stall_$c OT6_HEARTBEAT=$WINDOW OT6_TIMEOUT_RETRIES=1 \
     OT6_SRAM_CHECKPOINT=$env_ckpt \
     sh "$ROOT/tools/tests/run.sh" "$ROOT/tools/tests/lib/$lua" "$LOG" > "$STD" 2>&1
  then fail "$c: the run came back GREEN (see $LOG)"; fi
  took=$(( $(date +%s) - t0 ))
  grep -q 'KILLED BY A STALL after' "$STD" || fail "$c: no retry line naming a stall ($STD)"
  grep -q '^\[ot6\] KILLED BY A STALL: no verdict' "$LOG" || fail "$c: the final report does not name a stall ($LOG)"
  grep -q 'the last milestone (.*) was at frame [0-9]*, [0-9]*s before the kill' "$LOG" ||
    fail "$c: the report lacks the last progress frame and the seconds since ($LOG)"
  grep -q 'KILLED BY THE TIMEOUT' "$LOG" "$STD" && fail "$c: reported as the wall-clock timeout, not a stall"
  [ "$took" -le $(( 2 * (WINDOW + SLACK) )) ] || fail "$c: took ${took}s, over 2 x (${WINDOW}s + ${SLACK}s)"
  grep '^\[ot6\] KILLED BY A STALL' "$STD" "$LOG" | head -3
  retained=$(sed -n 's/^failed run retained: //p' "$STD")
  case "$retained" in "$ROOT"/build/test-runs/*) [ -d "$retained" ] && rm -rf "$retained" ;; esac
  echo "stall-negative: $c: PASS (${took}s for two attempts)"
done
echo "stall-negative: PASS"
