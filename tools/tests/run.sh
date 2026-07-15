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
# portable copy (settings.json beside the binary = portable mode).
MESEN_TEST="$ROOT/build/mesen-test.app"
if [ ! -x "$MESEN_TEST/Contents/MacOS/Mesen" ]; then
  echo "creating portable test emulator (one-time copy)..."
  cp -R "$ROOT/tools/Mesen.app" "$MESEN_TEST"
  cp "$HOME/Library/Application Support/Mesen2/settings.json" \
     "$MESEN_TEST/Contents/MacOS/settings.json"
fi
"$MESEN_TEST/Contents/MacOS/Mesen" --testrunner "$ROM" "$COMPOSED" > "$LOG" 2>&1
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
