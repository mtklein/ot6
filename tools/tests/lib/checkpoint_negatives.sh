#!/bin/sh
# checkpoint_negatives.sh: the stale-checkpoint regression (#25), run by
# `make checkpoint-negatives`.
#
# Issue #25's acceptance criterion: "A stale checkpoint fails loudly, naming
# what differed -- with a regression proving it FAILS, not merely that it
# passes when correct."  Every fixture bug this project has had is a check
# that can only agree with itself, and a refusal check whose refusal has never
# been observed has the same problem.  So this script drives both refusal
# paths through the real path (tools/tests/run.sh with a real checkpoint
# directory) and asserts on the refusal text itself:
#
#   1. tools/tests/checkpoints/negative-unknown-layout-v1: a byte-identical
#      copy of post-opera-v1 whose manifest declares a persistent_layout
#      no generator step supports.  Must be refused before the emulator boots
#      (run.sh + lib/sram_checkpoint.py), naming both layout strings.
#   2. tools/tests/checkpoints/negative-stale-check-v1: one contract-checked
#      byte perturbed and the manifest re-hashed, so it validates and
#      cold-boots.  The post-opera-v1 entry contract
#      (lib/ot6_contract.lua, asserted by gen_vector_entry) must fail
#      in the emulator, naming the field, the expected value, and the read value.
#
# Exit 0 only when both negatives failed for the declared reasons.
# All run output is captured to build/states/checkpoint_negative_*.log; grep
# those rather than the terminal scrollback.
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
OUT="$ROOT/build/states"
mkdir -p "$OUT"

fail() { echo "checkpoint-negatives: FAIL -- $1"; exit 1; }

# A deliberate failure still makes run.sh retain its workspace for
# inspection; these failures are the expected outcome, so reclaim the
# workspace once its log has been captured and checked.
reclaim_retained() {
  retained=$(sed -n 's/^failed run retained: //p' "$1")
  case "$retained" in
    "$ROOT"/build/test-runs/*) [ -d "$retained" ] && rm -rf "$retained" ;;
  esac
}

# ---- negative 1: the persistent_layout check refuses before boot ----------
LOG="$OUT/checkpoint_negative_layout.log"
echo "checkpoint-negatives: 1/2 unknown persistent_layout (pre-boot refusal)..."
if OT6_NO_PUBLISH=1 OT6_WORKER=neg_layout \
   OT6_SRAM_CHECKPOINT="$ROOT/tools/tests/checkpoints/negative-unknown-layout-v1" \
   sh "$ROOT/tools/tests/run.sh" "$ROOT/tools/tests/gen_vector_entry.lua" \
   > "$LOG" 2>&1
then
  fail "the unknown-layout checkpoint was ACCEPTED (see $LOG)"
fi
grep -q "persistent_layout mismatch" "$LOG" ||
  fail "refusal does not say 'persistent_layout mismatch' ($LOG)"
grep -q "ot6-codex-o9-experimental" "$LOG" ||
  fail "refusal does not name the CHECKPOINT's layout string ($LOG)"
grep -q "ot6-codex-o8-v1" "$LOG" ||
  fail "refusal does not name the GENERATOR's supported layout string ($LOG)"
# Pre-boot means the testrunner never ran: run.sh prints its "testrunner
# exit" line after every emulator invocation, so its absence is the evidence.
if grep -q "testrunner exit" "$LOG"; then
  fail "the emulator RAN; the layout check must refuse before boot ($LOG)"
fi
reclaim_retained "$LOG"
echo "checkpoint-negatives: 1/2 refused pre-boot, naming both layout strings"

# ---- negative 2: the entry contract names the perturbed field -------------
LOG="$OUT/checkpoint_negative_stale.log"
echo "checkpoint-negatives: 2/2 stale codex check (in-emulator contract)..."
if OT6_NO_PUBLISH=1 OT6_WORKER=neg_stale \
   OT6_SRAM_CHECKPOINT="$ROOT/tools/tests/checkpoints/negative-stale-check-v1" \
   sh "$ROOT/tools/tests/run.sh" "$ROOT/tools/tests/gen_vector_entry.lua" \
   > "$LOG" 2>&1
then
  fail "the stale-check checkpoint PASSED gen_vector_entry (see $LOG)"
fi
grep -q "CONTRACT DIFF \[post-opera-v1\]" "$LOG" ||
  fail "no per-field CONTRACT DIFF line in $LOG"
grep -q "element-codex witness" "$LOG" ||
  fail "the diff does not name the perturbed field ($LOG)"
grep -q "expected 0x01, read 0x00" "$LOG" ||
  fail "the diff does not carry expected-vs-read values ($LOG)"
grep -q "contract post-opera-v1 (entry) VIOLATED" "$LOG" ||
  fail "the [ot6] FAIL verdict does not name the violated contract ($LOG)"
reclaim_retained "$LOG"
echo "checkpoint-negatives: 2/2 failed in-emulator, naming the differing field"

echo "checkpoint-negatives: PASS -- both negatives failed loudly, naming what differed"
