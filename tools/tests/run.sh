#!/bin/sh
# run.sh <script.lua> [logfile] -- run a Lua test under Mesen 2's headless testrunner.
#
#   tools/tests/run.sh tools/tests/battle_smoke.lua
#
# * Composes the script with lib/ot6.lua into one flat file first
#   (build/states/_composed.lua).  Runtime dofile()/loadfile() inside Mesen's
#   sandboxed Lua crashes the emulator intermittently, so shared code and
#   savestate payloads are inlined at compose time instead.
# * Runs build/ot6.sfc (rebuild with `make rom` if you changed sources).
# * All emulator/script output goes to the logfile
#   (default: build/states/last_run.log).
# * [b64:<tag>] payloads emitted by the script (savestates, screenshots) are
#   decoded into build/states/ and build/states/shots/ afterwards.
# * Exit code: 0 = pass, 1 = assertion/Lua error, 2 = frame budget exceeded.
#   The [ot6] PASS/FAIL verdict in the log wins over the raw process code
#   (Mesen occasionally dies with 255 and unflushed stdout).
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MESEN="$ROOT/tools/Mesen.app/Contents/MacOS/Mesen"
ROM="$ROOT/build/ot6.sfc"
SCRIPT="${1:?usage: run.sh <script.lua> [logfile]}"
LOG="${2:-$ROOT/build/states/last_run.log}"
COMPOSED="$ROOT/build/states/_composed.lua"

mkdir -p "$ROOT/build/states/shots"

python3 "$ROOT/tools/tests/lib/compose.py" "$SCRIPT" "$COMPOSED" || exit 2

# Isolated portable Mesen for tests: the testrunner flushes battery saves
# on exit and twice zeroed the user's in-game save (ot6.srm) when sharing
# the real profile. A $HOME override is ignored on macOS, so tests run a
# portable copy (settings.json beside the binary = portable mode). We
# ALSO force an explicit SaveDataFolder override to a dedicated testing
# dir, so the user's save stays untouchable even if their settings later
# grow an override that would otherwise be inherited (the manual-play
# save and the repeatable-testing saves never share a directory).
MESEN_TEST="$ROOT/build/mesen-test.app"
TEST_SAVES="$ROOT/build/mesen-test-saves"
mkdir -p "$TEST_SAVES"
if [ ! -x "$MESEN_TEST/Contents/MacOS/Mesen" ]; then
  echo "creating portable test emulator (one-time copy)..."
  cp -R "$ROOT/tools/Mesen.app" "$MESEN_TEST"
fi
# (re)write the portable settings every run so the override can't drift
python3 "$ROOT/tools/tests/lib/pin_test_saves.py" \
  "$HOME/Library/Application Support/Mesen2/settings.json" \
  "$MESEN_TEST/Contents/MacOS/settings.json" \
  "$TEST_SAVES"
# --timeout=600: Mesen's testrunner has a hard DEFAULT 100-second wall-clock
# cap (exit -1/255 + truncated stdout on expiry) that reaped long runs; keep
# a cap as the only defense against a genuinely hung emulator, just a roomy one.
# --enableStdout mirrors the (otherwise invisible) script log window to
# stdout, surfacing silent Lua watchdog kills.
"$MESEN_TEST/Contents/MacOS/Mesen" --testrunner --timeout=600 --enableStdout "$ROM" "$COMPOSED" > "$LOG" 2>&1
code=$?

python3 "$ROOT/tools/tests/lib/decode_b64.py" "$LOG" "$ROOT/build/states"
grep '^\[ot6\]' "$LOG"

if grep -q '^\[ot6\] PASS' "$LOG"; then
  verdict=0
elif grep -q '^\[ot6\] FAIL' "$LOG"; then
  verdict=1
else
  verdict=$code
fi
echo "testrunner exit: $code (verdict: $verdict)"
exit "$verdict"
