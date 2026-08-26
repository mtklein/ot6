#!/bin/sh
# savestate_ninja_selftest.sh: checks the generated ninja graph's build
# semantics end-to-end against a mock tree, with no emulator.
set -u
command -v ninja >/dev/null 2>&1 || {
  echo "savestate_ninja selftest: ninja not installed -- brew bundle"; exit 1; }

REAL="$(cd "$(dirname "$0")/../../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ok=1

# ---- the mock tree ---------------------------------------------------------
mkdir -p "$TMP/tools/tests/lib" "$TMP/tools/tests/checkpoints/toy-v1" "$TMP/build"
cp "$REAL/tools/tests/lib/savestate_ninja.py" "$TMP/tools/tests/lib/"
cp "$REAL/tools/tests/lib/savestate_stamp.sh" "$TMP/tools/tests/lib/"
printf 'lib v1\n'      > "$TMP/tools/tests/lib/ot6.lua"
printf 'field v1\n'    > "$TMP/tools/tests/lib/ot6_field.lua"
printf 'contract v1\n' > "$TMP/tools/tests/lib/ot6_contract.lua"
for g in a b c e h; do printf 'gen %s v1\n' "$g" > "$TMP/tools/tests/gen_$g.lua"; done
printf 'gen g v1\ngenerates: g1 g2\n' > "$TMP/tools/tests/gen_g.lua"
printf 'rom v1\n' > "$TMP/build/ot6.sfc"
printf '{}\n'     > "$TMP/tools/tests/checkpoints/toy-v1/manifest.json"
printf 'sram v1'  > "$TMP/tools/tests/checkpoints/toy-v1/toy.sram"

# Stub run.sh: journals the invocation, honors an injected failure, and
# mirrors tools/tests/run.sh's publish step. A mock gen declares siblings
# on a `generates:` line; single-state gens omit it.
cat > "$TMP/tools/tests/run.sh" <<'EOF'
#!/bin/sh
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="${1:?usage: stub run.sh <script.lua>}"
echo "$OT6_WORKER${OT6_STACK:+ stack=$OT6_STACK}${OT6_SRAM_CHECKPOINT:+ checkpoint=$OT6_SRAM_CHECKPOINT}" >> "$ROOT/build/journal"
[ -e "$ROOT/build/fail.$OT6_WORKER" ] && { echo "stub run.sh: injected failure for $OT6_WORKER"; exit 1; }
mkdir -p "$ROOT/build/states"
ART=$(mktemp -d "$ROOT/build/art.XXXXXXXX") || exit 2
states=$(sed -n 's/^generates: *//p' "$SCRIPT")
[ -n "$states" ] || states="$OT6_WORKER"
for s in $states; do
  echo "generated $s by $$ for $OT6_WORKER" > "$ART/$s.mss"
  echo 'return "AA=="'                   > "$ART/$s.mss.lua"
done
if [ -n "${OT6_EXPECT_ARTIFACT:-}" ]; then
  for src in $OT6_EXPECT_ARTIFACT; do
    cp "$ART/$src" "$ROOT/build/states/$src"
  done
else
  for src in "$ART"/*; do
    [ -f "$src" ] || continue
    cp "$src" "$ROOT/build/states/$(basename "$src")"
  done
fi
rm -rf "$ART"
exit 0
EOF
chmod +x "$TMP/tools/tests/run.sh"

# The toy graph: one edge of every kind, plus a multi-state family (gen_g
# generates g2 then g1 from one run; h chains off it), with sibling names
# chosen so the second state sorts before the first.
cat > "$TMP/tools/tests/savestate_graph.py" <<'EOF'
def S(state, **kw):
    e = {"state": state, "gen": None, "prev": None, "checkpoint": None,
         "seed": None, "stack": None, "after": None}
    e.update(kw)
    return e
STATES = [
    S("a", gen="gen_a"),
    S("b", gen="gen_b", prev="a"),
    S("c", gen="gen_c", checkpoint="toy-v1"),
    S("d", seed="b"),
    S("e", gen="gen_e", prev="d", stack="t9_"),
    S("g2", gen="gen_g"),
    S("g1", gen="gen_g", prev="g2"),
    S("h", gen="gen_h", prev="g1"),
]
EOF

# ---- helpers ---------------------------------------------------------------
NIN="$TMP/ninja.log"
run() { # regenerate + build; rc in $rc, states generated (sorted) in $ran
  (cd "$TMP" && python3 tools/tests/lib/savestate_ninja.py &&
   ninja -f build/build.ninja savestates) > "$NIN" 2>&1
  rc=$?
  cp "$TMP/build/journal" "$TMP/journal.last" 2>/dev/null || : > "$TMP/journal.last"
  ran=$(sort "$TMP/build/journal" 2>/dev/null | sed 's/ .*//' | tr '\n' ' ')
  : > "$TMP/build/journal"
}
check() { # <label> <want> <got>
  if [ "$3" = "$2" ]; then echo "  pass $1"
  else echo "  FAIL $1: want '$2' got '$3'"; ok=0; fi
}
edit() { printf '%s\n' "$2" > "$TMP/$1"; }

# 1. fresh tree: every generator runs, the seed lands, env vars arrive intact.
: > "$TMP/build/journal"
run
check "fresh tree generates every step" "a b c e g1 g2 h " "$ran"
check "fresh tree build succeeds" 0 "$rc"
# both multi-state siblings were published by their own edges; restricting
# what one edge publishes must not leave a sibling's artifact missing.
[ -f "$TMP/build/states/g1.mss" ] && [ -f "$TMP/build/states/g2.mss" ] &&
  grep -q "for g1" "$TMP/build/states/g1.mss" &&
  grep -q "for g2" "$TMP/build/states/g2.mss" &&
  echo "  pass each multi-state sibling published by its own edge" ||
  { echo "  FAIL a multi-state sibling is missing or published by a sibling's edge"; ok=0; }
[ -f "$TMP/build/states/d.mss" ] && cmp -s "$TMP/build/states/d.mss" "$TMP/build/states/b.mss" &&
  echo "  pass seed d landed as a copy of b" ||
  { echo "  FAIL seed d missing or not b's bytes"; ok=0; }
grep -q '^c checkpoint=tools/tests/checkpoints/toy-v1$' "$TMP/journal.last" &&
  echo "  pass the checkpoint edge received OT6_SRAM_CHECKPOINT" ||
  { echo "  FAIL checkpoint edge env missing"; ok=0; }
grep -q '^e stack=t9_$' "$TMP/journal.last" &&
  echo "  pass stacked edge received OT6_STACK" ||
  { echo "  FAIL stacked edge env missing"; ok=0; }
[ -f "$TMP/build/states/c.stamp" ] && grep -q 'toy-v1/manifest.json' "$TMP/build/states/c.stamp" &&
  echo "  pass checkpoint stamp lists manifest+payload" ||
  { echo "  FAIL checkpoint stamp extras missing"; ok=0; }

# 2. quiescent: nothing re-runs.
run
check "untouched tree regenerates nothing (#30: g1 must not regenerate)" "" "$ran"
grep -q "no work to do" "$NIN" && echo "  pass ninja reports no work" ||
  { echo "  FAIL expected 'no work to do'"; ok=0; }
run
check "third run is still quiescent (#30 cascade class)" "" "$ran"

# 3. mtime-only touches (a checkout, a worktree cp): nothing re-runs.
sleep 1
touch "$TMP/build/ot6.sfc" "$TMP/tools/tests/gen_a.lua" \
      "$TMP/tools/tests/lib/ot6.lua" "$TMP/tools/tests/lib/ot6_field.lua" \
      "$TMP/tools/tests/lib/ot6_contract.lua" \
      "$TMP/tools/tests/checkpoints/toy-v1/toy.sram"
run
check "mtime-only touch regenerates nothing (restat)" "" "$ran"

# 4. ROM content change: every step re-runs (chained, checkpointed, stacked)
#    and the seed refreshes.
sleep 1
edit build/ot6.sfc "rom v2"
run
check "ROM content change regenerates EVERY step" "a b c e g1 g2 h " "$ran"
cmp -s "$TMP/build/states/d.mss" "$TMP/build/states/b.mss" &&
  echo "  pass seed d refreshed with its regenerated source" ||
  { echo "  FAIL seed d stale after the source regenerated"; ok=0; }

# 5. one generator edit: its step regenerates, the seed off it refreshes, the
#    stacked step downstream regenerates, and the unrelated steps do not.
sleep 1
edit tools/tests/gen_b.lua "gen b v2"
run
check "gen_b edit re-runs b and its dependents only" "b e " "$ran"

# 5a. A stale multi-state family regenerates its own members and their
#     dependents; the per-edge publish restriction must not reduce what
#     gets generated.
sleep 1
printf 'gen g v2\ngenerates: g1 g2\n' > "$TMP/tools/tests/gen_g.lua"
run
check "gen_g edit re-runs BOTH siblings and their dependent" "g1 g2 h " "$ran"
run
check "and the family is quiescent again afterwards" "" "$ran"

# 6. each composed-in lib half re-runs every step.
for half in ot6.lua ot6_field.lua ot6_contract.lua; do
  sleep 1
  edit "tools/tests/lib/$half" "$half EDITED $$"
  run
  check "lib/$half edit re-runs every step" "a b c e g1 g2 h " "$ran"
done

# 7. checkpoint payload and manifest edits re-run only the step that uses it.
sleep 1
edit tools/tests/checkpoints/toy-v1/toy.sram "sram v2"
run
check "checkpoint payload edit re-runs only that step" "c " "$ran"
sleep 1
edit tools/tests/checkpoints/toy-v1/manifest.json '{"v":2}'
run
check "checkpoint manifest edit re-runs only that step" "c " "$ran"

# 8. a failing generation fails the build and blocks dependents; the retry
#    runs it again, so failure is never recorded as success.
sleep 1
: > "$TMP/build/fail.b"
edit tools/tests/gen_b.lua "gen b v3"
run
[ "$rc" -ne 0 ] && echo "  pass failing generation fails the build" ||
  { echo "  FAIL build succeeded through a failing generation"; ok=0; }
check "failed step ran, dependent did not" "b " "$ran"
rm "$TMP/build/fail.b"
run
check "retry re-runs the failed step and dependents" "b e " "$ran"
check "retry build succeeds" 0 "$rc"

# 9. an unknown target is a hard error.
(cd "$TMP" && ninja -f build/build.ninja smoke-gen_bogus) > "$NIN" 2>&1
[ $? -ne 0 ] && grep -q "unknown target" "$NIN" &&
  echo "  pass unknown target is a hard error" ||
  { echo "  FAIL unknown target did not error"; ok=0; }

# 10. provenance: the stamp a `generate` edge writes carries its own
#     artifact's hash and the hash of the stamp it was generated from, so
#     the chain verifies from files on disk alone.
want=$(cd "$TMP" && OT6_ROOT="$TMP" sh tools/tests/lib/savestate_stamp.sh sig gen_b)
[ "$(head -n 1 "$TMP/build/states/b.stamp")" = "$want" ] &&
  echo "  pass generate-edge stamp matches sig" ||
  { echo "  FAIL stamp/sig disagree"; ok=0; }
[ "$(sed -n 2p "$TMP/build/states/b.stamp")" = \
  "artifact $(shasum -a 256 "$TMP/build/states/b.mss" | cut -c1-64)" ] &&
  echo "  pass generate-edge stamp binds its artifact (#75)" ||
  { echo "  FAIL artifact binding wrong or missing"; ok=0; }
[ "$(sed -n 3p "$TMP/build/states/b.stamp")" = \
  "ancestor build/states/a.stamp $(shasum -a 256 "$TMP/build/states/a.stamp" | cut -c1-64)" ] &&
  echo "  pass chained stamp binds its predecessor's stamp (#75)" ||
  { echo "  FAIL ancestor binding wrong or missing"; ok=0; }
[ "$(wc -l < "$TMP/build/states/a.stamp" | tr -d ' ')" = 2 ] &&
  echo "  pass root stamp carries no ancestor line" ||
  { echo "  FAIL root stamp shape wrong"; ok=0; }
grep -q '^ancestor tools/tests/checkpoints/toy-v1/manifest.json ' \
  "$TMP/build/states/c.stamp" &&
  echo "  pass checkpoint stamp binds the checkpoint manifest (#75)" ||
  { echo "  FAIL checkpoint stamp has no manifest ancestor"; ok=0; }
cmp -s "$TMP/build/states/d.stamp" "$TMP/build/states/b.stamp" &&
  echo "  pass seed d carries a verbatim copy of b's stamp (#75)" ||
  { echo "  FAIL seed stamp missing or not the source's"; ok=0; }

[ "$ok" -eq 1 ] && { echo "savestate_ninja selftest: ok"; exit 0; }
echo "savestate_ninja selftest: FAILED"; exit 1
