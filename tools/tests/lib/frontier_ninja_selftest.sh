#!/bin/sh
# frontier_ninja_selftest.sh -- prove the generated ninja graph's SEMANTICS
# end-to-end, in seconds, with no emulator: the REAL generator
# (frontier_ninja.py) and the REAL `mint` command shape run against a mock tree
# whose run.sh is a stub that journals every invocation.
#
# This is the other half of frontier_stamp_selftest.sh: that file pins the
# provenance SIGNATURE, this one pins the generate-or-skip DECISION the retired
# `needsmint` used to make -- now ninja's own scheduling -- on every axis:
#
#   * a fresh tree generates every step; an untouched tree regenerates
#     nothing;
#   * an mtime-only touch of ANY source regenerates nothing (restat latches);
#   * a ROM content change re-runs EVERY transitive dependent -- the class
#     behind 2026-07-27's "rom content changed, then booted an old-ROM
#     savestate anyway" failure; there is no stamp to disagree with;
#   * a generator edit re-runs its own step and everything downstream of it,
#     and NOTHING else;
#   * an edit to any of the three composed-in lib halves -- ot6.lua,
#     ot6_field.lua, and the invariant-contract half ot6_contract.lua
#     (issue #25) -- re-runs every step;
#   * a checkpoint manifest/payload edit re-runs only the step that uses it;
#   * a failing generation FAILS the build, blocks its dependents, and is
#     retried on the next run -- no way to record success without executing;
#   * an unknown target is a hard error (the `smoke-%: rom` silent .PHONY
#     no-op class make allowed);
#   * MULTI-STATE SIBLINGS CONVERGE (issue #30): a script that generates
#     several states gets one edge per state, every invocation emits EVERY
#     sibling artifact, and the publish step must not let one edge touch another
#     edge's outputs -- or an edge that republishes its own sibling INPUT
#     after its own outputs is input-newer-than-output forever and
#     consecutive runs regenerate the family and its downstream trunk with
#     zero content changes.  The stub below emits siblings exactly like a
#     real multi-state generator so the quiescence cases prove this class
#     stays dead.
set -u
command -v ninja >/dev/null 2>&1 || {
  echo "frontier_ninja selftest: ninja not installed -- brew bundle"; exit 1; }

REAL="$(cd "$(dirname "$0")/../../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ok=1

# ---- the mock tree ---------------------------------------------------------
mkdir -p "$TMP/tools/tests/lib" "$TMP/tools/tests/anchors/toy-v1" "$TMP/build"
cp "$REAL/tools/tests/lib/frontier_ninja.py" "$TMP/tools/tests/lib/"
cp "$REAL/tools/tests/lib/frontier_stamp.sh" "$TMP/tools/tests/lib/"
printf 'lib v1\n'      > "$TMP/tools/tests/lib/ot6.lua"
printf 'field v1\n'    > "$TMP/tools/tests/lib/ot6_field.lua"
printf 'contract v1\n' > "$TMP/tools/tests/lib/ot6_contract.lua"
for g in a b c e h; do printf 'gen %s v1\n' "$g" > "$TMP/tools/tests/gen_$g.lua"; done
printf 'gen g v1\nmints: g1 g2\n' > "$TMP/tools/tests/gen_g.lua"
printf 'rom v1\n' > "$TMP/build/ot6.sfc"
printf '{}\n'     > "$TMP/tools/tests/anchors/toy-v1/manifest.json"
printf 'sram v1'  > "$TMP/tools/tests/anchors/toy-v1/toy.sram"

# The stub run.sh: journal the invocation (worker + stack/anchor env), honor
# an injected failure, then behave like the real one where it matters here:
#  * the SCRIPT half -- a multi-state generator emits EVERY sibling artifact
#    on EVERY invocation (gen_edgar plays the whole Figaro chapter and emits
#    all three figaro states no matter which edge invoked it).  A mock gen
#    declares its siblings on a `mints:` line; single-state gens omit it.
#  * the PUBLISH half -- MIRRORS tools/tests/run.sh's publish step (the
#    block tagged issue #30); keep the two in lockstep, because this stub is
#    how the publish policy's scheduling consequences get proven without an
#    emulator.  Workspace files are iterated in the same "$ART"/* glob order
#    the real script uses.
cat > "$TMP/tools/tests/run.sh" <<'EOF'
#!/bin/sh
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="${1:?usage: stub run.sh <script.lua>}"
echo "$OT6_WORKER${OT6_STACK:+ stack=$OT6_STACK}${OT6_SRAM_ANCHOR:+ anchor=$OT6_SRAM_ANCHOR}" >> "$ROOT/build/journal"
[ -e "$ROOT/build/fail.$OT6_WORKER" ] && { echo "stub run.sh: injected failure for $OT6_WORKER"; exit 1; }
mkdir -p "$ROOT/build/states"
ART=$(mktemp -d "$ROOT/build/art.XXXXXXXX") || exit 2
states=$(sed -n 's/^mints: *//p' "$SCRIPT")
[ -n "$states" ] || states="$OT6_WORKER"
for s in $states; do
  echo "minted $s by $$ for $OT6_WORKER" > "$ART/$s.mss"
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

# The toy graph: a plain power-on state, a chained state, a state grown from a
# checkpoint, a stack seed, a stacked state off the seed -- one of every edge
# kind -- plus a MULTI-STATE FAMILY (issue #30): gen_g generates g2 then g1
# from one run, one edge each, and h chains off the family's ending.  The sibling names are
# chosen so the SECOND state sorts BEFORE the first, exactly the real
# figaro family's shape (figaro_cleared sorts before figaro_matron, its own
# input): a publish-everything policy writes edge g1's own outputs first and
# then re-bumps g2 -- g1's INPUT -- so g1 could never be clean again.
cat > "$TMP/tools/tests/frontier_graph.py" <<'EOF'
def S(state, **kw):
    e = {"state": state, "gen": None, "prev": None, "anchor": None,
         "seed": None, "stack": None, "after": None}
    e.update(kw)
    return e
STATES = [
    S("a", gen="gen_a"),
    S("b", gen="gen_b", prev="a"),
    S("c", gen="gen_c", anchor="toy-v1"),
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
  (cd "$TMP" && python3 tools/tests/lib/frontier_ninja.py &&
   ninja -f build/build.ninja frontier) > "$NIN" 2>&1
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
# both multi-state siblings were published by their OWN edges -- restricting
# what one edge publishes must never leave a sibling's artifact missing.
[ -f "$TMP/build/states/g1.mss" ] && [ -f "$TMP/build/states/g2.mss" ] &&
  grep -q "for g1" "$TMP/build/states/g1.mss" &&
  grep -q "for g2" "$TMP/build/states/g2.mss" &&
  echo "  pass each multi-state sibling published by its own edge" ||
  { echo "  FAIL a multi-state sibling is missing or published by a sibling's edge"; ok=0; }
[ -f "$TMP/build/states/d.mss" ] && cmp -s "$TMP/build/states/d.mss" "$TMP/build/states/b.mss" &&
  echo "  pass seed d landed as a copy of b" ||
  { echo "  FAIL seed d missing or not b's bytes"; ok=0; }
grep -q '^c anchor=tools/tests/anchors/toy-v1$' "$TMP/journal.last" &&
  echo "  pass the checkpoint edge received OT6_SRAM_ANCHOR" ||
  { echo "  FAIL checkpoint edge env missing"; ok=0; }
grep -q '^e stack=t9_$' "$TMP/journal.last" &&
  echo "  pass stacked edge received OT6_STACK" ||
  { echo "  FAIL stacked edge env missing"; ok=0; }
[ -f "$TMP/build/states/c.stamp" ] && grep -q 'toy-v1/manifest.json' "$TMP/build/states/c.stamp" &&
  echo "  pass checkpoint stamp lists manifest+payload" ||
  { echo "  FAIL checkpoint stamp extras missing"; ok=0; }

# 2. quiescent: nothing re-runs.  With the multi-state family in the graph
#    this is ALSO the issue-#30 sibling regression: before run.sh published
#    only the invoking edge's own artifacts, edge g1's publish pass re-bumped
#    g2.mss -- its own input -- after its own outputs, and this run generated
#    "g1 " (then "g1 h ", then "g1 h " ...) forever on an untouched tree.
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
      "$TMP/tools/tests/anchors/toy-v1/toy.sram"
run
check "mtime-only touch regenerates nothing (restat)" "" "$ran"

# 4. ROM content change: EVERY step re-runs -- chained, checkpointed, stacked --
#    and the seed refreshes.  The 2026-07-27 failure class: there is no way
#    to note "rom content changed" and still skip a state generated under the
#    old ROM, because the decision and the execution are one graph.
sleep 1
edit build/ot6.sfc "rom v2"
run
check "ROM content change regenerates EVERY step" "a b c e g1 g2 h " "$ran"
cmp -s "$TMP/build/states/d.mss" "$TMP/build/states/b.mss" &&
  echo "  pass seed d refreshed with its regenerated source" ||
  { echo "  FAIL seed d stale after the source regenerated"; ok=0; }

# 5. one generator edit: its step regenerates, the seed off it refreshes, the
#    stacked step downstream regenerates -- and the unrelated steps do not.
sleep 1
edit tools/tests/gen_b.lua "gen b v2"
run
check "gen_b edit re-runs b and its dependents only" "b e " "$ran"

# 5a. NO UNDER-GENERATION (#30's other half): a genuinely stale multi-state
#     family regenerates exactly its own members and their dependents.  The
#     per-edge publish restriction must not have turned "publish less" into
#     "generate less".
sleep 1
printf 'gen g v2\nmints: g1 g2\n' > "$TMP/tools/tests/gen_g.lua"
run
check "gen_g edit re-runs BOTH siblings and their dependent" "g1 g2 h " "$ran"
run
check "and the family is quiescent again afterwards" "" "$ran"

# 6. each composed-in lib half re-runs every step; the contract half is the
#    issue-#25 addition the old stamp never hashed.
for half in ot6.lua ot6_field.lua ot6_contract.lua; do
  sleep 1
  edit "tools/tests/lib/$half" "$half EDITED $$"
  run
  check "lib/$half edit re-runs every step" "a b c e g1 g2 h " "$ran"
done

# 7. checkpoint payload and manifest edits re-run only the step that uses it.
sleep 1
edit tools/tests/anchors/toy-v1/toy.sram "sram v2"
run
check "checkpoint payload edit re-runs only that step" "c " "$ran"
sleep 1
edit tools/tests/anchors/toy-v1/manifest.json '{"v":2}'
run
check "checkpoint manifest edit re-runs only that step" "c " "$ran"

# 8. a failing generation fails the BUILD and blocks dependents; the retry
#    runs it again -- failure is never recorded as success.
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

# 9. the silent-no-op class: an unknown target is a hard error, where make's
#    .PHONY pattern rules reported success in 0.036s having run nothing.
(cd "$TMP" && ninja -f build/build.ninja smoke-gen_bogus) > "$NIN" 2>&1
[ $? -ne 0 ] && grep -q "unknown target" "$NIN" &&
  echo "  pass unknown target is a hard error" ||
  { echo "  FAIL unknown target did not error"; ok=0; }

# 10. provenance: the stamp a `mint` edge writes opens with the exact sig
#     compose.py will re-derive (the two sides of the consume-time guard),
#     and carries the #75 bindings -- its own artifact's hash, and the hash
#     of the stamp it grew from -- so the chain verifies transitively from
#     files on disk alone.
want=$(cd "$TMP" && OT6_ROOT="$TMP" sh tools/tests/lib/frontier_stamp.sh sig gen_b)
[ "$(head -n 1 "$TMP/build/states/b.stamp")" = "$want" ] &&
  echo "  pass mint-edge stamp matches sig" ||
  { echo "  FAIL stamp/sig disagree"; ok=0; }
[ "$(sed -n 2p "$TMP/build/states/b.stamp")" = \
  "artifact $(shasum -a 256 "$TMP/build/states/b.mss" | cut -c1-64)" ] &&
  echo "  pass mint-edge stamp binds its artifact (#75)" ||
  { echo "  FAIL artifact binding wrong or missing"; ok=0; }
[ "$(sed -n 3p "$TMP/build/states/b.stamp")" = \
  "ancestor build/states/a.stamp $(shasum -a 256 "$TMP/build/states/a.stamp" | cut -c1-64)" ] &&
  echo "  pass chained stamp binds its predecessor's stamp (#75)" ||
  { echo "  FAIL ancestor binding wrong or missing"; ok=0; }
[ "$(wc -l < "$TMP/build/states/a.stamp" | tr -d ' ')" = 2 ] &&
  echo "  pass root stamp carries no ancestor line" ||
  { echo "  FAIL root stamp shape wrong"; ok=0; }
grep -q '^ancestor tools/tests/anchors/toy-v1/manifest.json ' \
  "$TMP/build/states/c.stamp" &&
  echo "  pass checkpoint stamp binds the checkpoint manifest (#75)" ||
  { echo "  FAIL checkpoint stamp has no manifest ancestor"; ok=0; }
cmp -s "$TMP/build/states/d.stamp" "$TMP/build/states/b.stamp" &&
  echo "  pass seed d carries a verbatim copy of b's stamp (#75)" ||
  { echo "  FAIL seed stamp missing or not the source's"; ok=0; }

[ "$ok" -eq 1 ] && { echo "frontier_ninja selftest: ok"; exit 0; }
echo "frontier_ninja selftest: FAILED"; exit 1
