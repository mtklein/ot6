#!/bin/sh
# run.sh <script.lua> [watchdog_seconds] [output_file]
# Runs a Lua script under the Mesen 2 headless testrunner against build/ot6.sfc.
# - Captures all output to $OUT (default /tmp/mesen_run.out)
# - Decodes any [b64:<tag>] screenshot/blob chunks in the output:
#     * tags ending in .mss are written under build/states/
#     * everything else is written as build/states/shots/<tag>.png
# - Exits with the emu.stop() exit code (143 if the watchdog had to kill it).
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MESEN="$ROOT/tools/Mesen.app/Contents/MacOS/Mesen"
ROM="$ROOT/build/ot6.sfc"
SCRIPT="$1"
SECS="${2:-300}"
OUT="${3:-/tmp/mesen_run.out}"

mkdir -p "$ROOT/build/states/shots"

"$MESEN" --testrunner "$ROM" "$SCRIPT" > "$OUT" 2>&1 &
pid=$!
(
  sleep "$SECS"
  kill "$pid" 2>/dev/null
) &
watchdog=$!
wait "$pid"
code=$?
kill "$watchdog" 2>/dev/null

# Decode any base64 payloads: lines look like "[b64:tag] AAAA..."
tags=$(grep -o '^\[b64:[^]]*\]' "$OUT" 2>/dev/null | sort -u | sed 's/^\[b64:\(.*\)\]$/\1/')
for tag in $tags; do
  case "$tag" in
    *.mss) dest="$ROOT/build/states/$tag" ;;
    *)     dest="$ROOT/build/states/shots/$tag.png" ;;
  esac
  grep "^\[b64:$tag\] " "$OUT" | sed "s/^\[b64:$tag\] //" | tr -d '\n' | base64 -d > "$dest" 2>/dev/null \
    && echo "decoded: $dest ($(wc -c < "$dest" | tr -d ' ') bytes)"
done

echo "runner-exit: $code"
exit "$code"
