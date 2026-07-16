#!/bin/sh
# make_srm_sidecar.sh -- snapshot the live in-game battery save and turn
# its front 8 KB (the save slots; the upper banks are the OT6 codex) into
# an embeddable base64 sidecar the headless harness can inject at boot.
#
#   tools/tests/make_srm_sidecar.sh
#
# Headless Mesen always boots SRAM zeroed (battery loading is GUI-only),
# so gen_whelk / probe_slots / probe_srmboot inject this instead. In-game
# saves are pure vanilla-layout data with no code dependency, so a sidecar
# made once keeps loading across ROM rebuilds -- regenerate only when you
# save further in the GUI and want the harness to start from there.
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRM="$HOME/Library/Application Support/Mesen2/Saves/ot6.srm"
OUT="$ROOT/build/states/playthrough_srm.mss.lua"

[ -f "$SRM" ] || { echo "no battery save at $SRM"; exit 1; }
mkdir -p "$ROOT/build/states"
python3 - "$SRM" "$OUT" <<'PY'
import base64, sys
front = open(sys.argv[1], 'rb').read()[:8192]        # save slots only
open(sys.argv[2], 'w').write('return "' + base64.b64encode(front).decode() + '"')
nz = sum(1 for b in front if b)
print(f"sidecar -> {sys.argv[2]}  ({nz} nonzero bytes of 8192)")
PY