#!/bin/sh
# callback_negative.sh: the callback-error negative control (#438).
#
# Mesen swallows an error raised inside a memory callback, so an assert
# there never failed a run.  lib/ot6.lua's callback shim now records the
# first such error and the runner fails the next frame with its message and
# traceback.  A suite cannot expect a red run, so this drives
# tools/tests/lib/callback_negative.lua (an assertEq inside an exec
# callback) through the real path (tools/tests/run.sh) and asserts on the
# red verdict itself:
#
#   * run.sh exits non-zero;
#   * the log says the error was raised inside a memory callback;
#   * the log carries the original assertEq message.
#
# Exit 0 only when the run failed for the declared reason.  Output:
# build/states/callback_negative.log (run.sh's published log) and
# build/states/callback_negative.out (its stdout).  Reverting the shim
# turns this red (the run comes back GREEN).
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
OUT="$ROOT/build/states"
mkdir -p "$OUT"
LOG="$OUT/callback_negative.log"
STDOUT="$OUT/callback_negative.out"

fail() { echo "callback-negative: FAIL -- $1"; exit 1; }

# the deliberate failure makes run.sh retain its workspace; reclaim it
reclaim_retained() {
  retained=$(sed -n 's/^failed run retained: //p' "$1")
  case "$retained" in
    "$ROOT"/build/test-runs/*) [ -d "$retained" ] && rm -rf "$retained" ;;
  esac
}

echo "callback-negative: an assertEq inside a memory callback must fail the run..."
if OT6_NO_PUBLISH=1 OT6_WORKER=callback_neg \
   sh "$ROOT/tools/tests/run.sh" "$ROOT/tools/tests/lib/callback_negative.lua" "$LOG" \
   > "$STDOUT" 2>&1
then
  fail "the run came back GREEN: an assertEq inside a memory callback passed (see $LOG)"
fi
grep -q 'an error was raised inside a memory callback' "$LOG" ||
  fail "the log does not say the error was raised inside a memory callback ($LOG)"
grep -q 'assertEq failed: an injected miss inside a memory callback: got 1 (\$1), want 2 (\$2)' "$LOG" ||
  fail "the failure is not the injected assertEq ($LOG)"
grep -q '^testrunner exit: 1 (verdict: 1)' "$STDOUT" ||
  fail "run.sh did not exit 1 ($STDOUT)"
reclaim_retained "$STDOUT"
echo "callback-negative: PASS -- the callback's assertEq failed the run with its own message"
