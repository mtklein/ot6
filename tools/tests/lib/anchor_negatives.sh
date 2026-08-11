#!/bin/sh
# anchor_negatives.sh -- the stale-checkpoint regression (#25), run by
# `make anchor-negatives`.
#
# Issue #25's acceptance criterion: "A stale anchor fails loudly, naming
# what differed -- with a regression proving it FAILS, not merely that it
# passes when correct."  Every fixture bug this project has had is a check
# that can only agree with itself; a refusal check whose refusal has never
# been observed is the same shape.  So this script drives BOTH refusal
# paths through the REAL path -- tools/tests/run.sh with a real checkpoint
# directory -- and asserts on the refusal text itself:
#
#   1. tools/tests/anchors/negative-unknown-layout-v1: a byte-identical
#      copy of post-opera-v1 whose manifest declares a persistent_layout
#      no generator step supports.  Must be refused BEFORE the emulator boots
#      (run.sh + lib/sram_anchor.py), naming BOTH layout strings.
#   2. tools/tests/anchors/negative-stale-witness-v1: one contract-checked
#      byte perturbed and the manifest re-hashed, so it validates and
#      cold-boots.  The post-opera-v1 ENTRY contract
#      (lib/ot6_contract.lua, asserted by gen_vector_doorstep) must fail
#      IN the emulator, naming the exact field, expected, and read values.
#
# Exit 0 only when both negatives failed for exactly the declared reasons.
# All run output is captured to build/states/anchor_negative_*.log; grep
# those, never the terminal scrollback.
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
OUT="$ROOT/build/states"
mkdir -p "$OUT"

fail() { echo "anchor-negatives: FAIL -- $1"; exit 1; }

# A deliberate failure still makes run.sh retain its forensic workspace;
# these failures are the expected outcome, so reclaim the workspace once
# its log has been captured and judged.
reap_retained() {
  retained=$(sed -n 's/^failed run retained: //p' "$1")
  case "$retained" in
    "$ROOT"/build/test-runs/*) [ -d "$retained" ] && rm -rf "$retained" ;;
  esac
}

# ---- negative 1: the persistent_layout check refuses BEFORE boot ----------
LOG="$OUT/anchor_negative_layout.log"
echo "anchor-negatives: 1/2 unknown persistent_layout (pre-boot refusal)..."
if OT6_NO_PUBLISH=1 OT6_WORKER=neg_layout \
   OT6_SRAM_ANCHOR="$ROOT/tools/tests/anchors/negative-unknown-layout-v1" \
   sh "$ROOT/tools/tests/run.sh" "$ROOT/tools/tests/gen_vector_doorstep.lua" \
   > "$LOG" 2>&1
then
  fail "the unknown-layout anchor was ACCEPTED (see $LOG)"
fi
grep -q "persistent_layout mismatch" "$LOG" ||
  fail "refusal does not say 'persistent_layout mismatch' ($LOG)"
grep -q "ot6-codex-o9-experimental" "$LOG" ||
  fail "refusal does not name the ANCHOR's layout string ($LOG)"
grep -q "ot6-codex-o8-v1" "$LOG" ||
  fail "refusal does not name the GENERATOR's supported layout string ($LOG)"
# Pre-boot means the testrunner never ran: run.sh prints its "testrunner
# exit" line after every emulator invocation, so its absence is the proof.
if grep -q "testrunner exit" "$LOG"; then
  fail "the emulator RAN; the layout check must refuse before boot ($LOG)"
fi
reap_retained "$LOG"
echo "anchor-negatives: 1/2 refused pre-boot, naming both layout strings"

# ---- negative 2: the entry contract names the perturbed field -------------
LOG="$OUT/anchor_negative_stale.log"
echo "anchor-negatives: 2/2 stale codex check (in-emulator contract)..."
if OT6_NO_PUBLISH=1 OT6_WORKER=neg_stale \
   OT6_SRAM_ANCHOR="$ROOT/tools/tests/anchors/negative-stale-witness-v1" \
   sh "$ROOT/tools/tests/run.sh" "$ROOT/tools/tests/gen_vector_doorstep.lua" \
   > "$LOG" 2>&1
then
  fail "the stale-witness anchor PASSED gen_vector_doorstep (see $LOG)"
fi
grep -q "CONTRACT DIFF \[post-opera-v1\]" "$LOG" ||
  fail "no per-field CONTRACT DIFF line in $LOG"
grep -q "element-codex witness" "$LOG" ||
  fail "the diff does not name the perturbed field ($LOG)"
grep -q "expected 0x01, read 0x00" "$LOG" ||
  fail "the diff does not carry expected-vs-read values ($LOG)"
grep -q "contract post-opera-v1 (entry) VIOLATED" "$LOG" ||
  fail "the [ot6] FAIL verdict does not name the violated contract ($LOG)"
reap_retained "$LOG"
echo "anchor-negatives: 2/2 failed in-emulator, naming the differing field"

echo "anchor-negatives: PASS -- both negatives failed loudly, naming what differed"
