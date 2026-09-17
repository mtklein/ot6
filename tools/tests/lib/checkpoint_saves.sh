#!/bin/sh
# checkpoint_saves.sh -- validate every tracked SRAM checkpoint, and say
# which save each battery holds.
#
# `sram_checkpoint.py validate` decodes the save slot out of the payload
# bytes (the slot's own copy of $1F64 and $1FC0/$1FC1 or $1F60/$1F61) and,
# for a manifest that declares a `saved` block, refuses a battery holding a
# different one.  Two checkpoints shipped holding the Kolts summit save
# because their generators' save steps were skipped and nothing looked
# (#218); this is the look, run by ninja over the whole set.
#
# Exit 0 only when every checkpoint validates.  The per-checkpoint lines
# are the record of what each one holds, declared or not.
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT" || exit 2

fail=0
n=0
for dir in tools/tests/checkpoints/*/; do
  [ -f "$dir/manifest.json" ] || continue
  n=$((n + 1))
  key=$(basename "$dir")
  # stderr (the legacy-v0 provenance warning) flows through to the log;
  # stdout is the one-line verdict.
  line=$(python3 tools/tests/lib/sram_checkpoint.py validate "$dir") || {
    echo "checkpoint-saves: FAIL $key (see the refusal above)"
    fail=1
    continue
  }
  echo "checkpoint-saves: $key: ${line#valid ot6.sram-checkpoint/v1: }"
done

[ "$n" -gt 0 ] || { echo "checkpoint-saves: FAIL -- no checkpoints found"; exit 1; }
[ "$fail" -eq 0 ] || exit 1
echo "checkpoint-saves: PASS -- $n checkpoints validate; each line names the save its battery holds"
