#!/bin/sh
# frontier_ninja_selftest.sh -- prove the generated ninja graph's SEMANTICS
# end-to-end, in seconds, with no emulator: the REAL generator
# (frontier_ninja.py) and the REAL mint command shape run against a mock tree
# whose run.sh is a stub that journals every invocation.
#
# This is the other half of frontier_stamp_selftest.sh: that file pins the
# provenance SIGNATURE, this one pins the mint-or-skip DECISION the retired
# `needsmint` used to make -- now ninja's own scheduling -- on every axis:
#
#   * a fresh tree mints every leg; an untouched tree re-mints nothing;
#   * an mtime-only touch of ANY source re-mints nothing (restat latches);
#   * a ROM content change re-runs EVERY transitive dependent -- the class
#     behind 2026-07-27's "rom content changed, then booted an old-ROM
#     savestate anyway" failure; there is no stamp to disagree with;
#   * a generator edit re-runs its own leg and everything downstream of it,
#     and NOTHING else;
#   * an edit to any of the three composed-in lib halves -- ot6.lua,
#     ot6_field.lua, and the invariant-contract half ot6_contract.lua
#     (issue #25) -- re-runs every leg;
#   * an anchor manifest/payload edit re-runs the anchored leg only;
#   * a failing mint FAILS the build, blocks its dependents, and is retried
#     on the next run -- no way to record success without executing;
#   * an unknown target is a hard error (the `smoke-%: rom` silent .PHONY
#     no-op class make allowed).
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
for g in a b c e; do printf 'gen %s v1\n' "$g" > "$TMP/tools/tests/gen_$g.lua"; done
printf 'rom v1\n' > "$TMP/build/ot6.sfc"
printf '{}\n'     > "$TMP/tools/tests/anchors/toy-v1/manifest.json"
printf 'sram v1'  > "$TMP/tools/tests/anchors/toy-v1/toy.sram"

# The stub run.sh: journal the invocation (worker + stack/anchor env), honor
# an injected failure, then publish both artifact halves like the real one.
cat > "$TMP/tools/tests/run.sh" <<'EOF'
#!/bin/sh
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
echo "$OT6_WORKER${OT6_STACK:+ stack=$OT6_STACK}${OT6_SRAM_ANCHOR:+ anchor=$OT6_SRAM_ANCHOR}" >> "$ROOT/build/journal"
[ -e "$ROOT/build/fail.$OT6_WORKER" ] && { echo "stub run.sh: injected failure for $OT6_WORKER"; exit 1; }
mkdir -p "$ROOT/build/states"
echo "minted $OT6_WORKER by $$" > "$ROOT/build/states/$OT6_WORKER.mss"
echo 'return "AA=="'            > "$ROOT/build/states/$OT6_WORKER.mss.lua"
exit 0
EOF
chmod +x "$TMP/tools/tests/run.sh"

# The toy graph: a plain power-on mint, a chained mint, an anchored mint, a
# stack seed, and a stacked mint off the seed -- one of every edge kind.
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
]
EOF

# ---- helpers ---------------------------------------------------------------
NIN="$TMP/ninja.log"
run() { # regenerate + build; rc in $rc, mints (sorted) in $ran
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

# 1. fresh tree: every mint runs, the seed lands, env vars arrive intact.
: > "$TMP/build/journal"
run
check "fresh tree mints every leg" "a b c e " "$ran"
check "fresh tree build succeeds" 0 "$rc"
[ -f "$TMP/build/states/d.mss" ] && cmp -s "$TMP/build/states/d.mss" "$TMP/build/states/b.mss" &&
  echo "  pass seed d landed as a copy of b" ||
  { echo "  FAIL seed d missing or not b's bytes"; ok=0; }
grep -q '^c anchor=tools/tests/anchors/toy-v1$' "$TMP/journal.last" &&
  echo "  pass anchored mint received OT6_SRAM_ANCHOR" ||
  { echo "  FAIL anchored mint env missing"; ok=0; }
grep -q '^e stack=t9_$' "$TMP/journal.last" &&
  echo "  pass stacked mint received OT6_STACK" ||
  { echo "  FAIL stacked mint env missing"; ok=0; }
[ -f "$TMP/build/states/c.stamp" ] && grep -q 'toy-v1/manifest.json' "$TMP/build/states/c.stamp" &&
  echo "  pass anchored stamp lists manifest+payload" ||
  { echo "  FAIL anchored stamp extras missing"; ok=0; }

# 2. quiescent: nothing re-runs.
run
check "untouched tree re-mints nothing" "" "$ran"
grep -q "no work to do" "$NIN" && echo "  pass ninja reports no work" ||
  { echo "  FAIL expected 'no work to do'"; ok=0; }

# 3. mtime-only touches (a checkout, a worktree cp): nothing re-runs.
sleep 1
touch "$TMP/build/ot6.sfc" "$TMP/tools/tests/gen_a.lua" \
      "$TMP/tools/tests/lib/ot6.lua" "$TMP/tools/tests/lib/ot6_field.lua" \
      "$TMP/tools/tests/lib/ot6_contract.lua" \
      "$TMP/tools/tests/anchors/toy-v1/toy.sram"
run
check "mtime-only touch re-mints nothing (restat)" "" "$ran"

# 4. ROM content change: EVERY leg re-runs -- chained, anchored, stacked --
#    and the seed refreshes.  The 2026-07-27 failure class: there is no way
#    to note "rom content changed" and still skip a state minted under the
#    old ROM, because the decision and the execution are one graph.
sleep 1
edit build/ot6.sfc "rom v2"
run
check "ROM content change re-mints EVERY leg" "a b c e " "$ran"
cmp -s "$TMP/build/states/d.mss" "$TMP/build/states/b.mss" &&
  echo "  pass seed d refreshed with its re-minted source" ||
  { echo "  FAIL seed d stale after source re-mint"; ok=0; }

# 5. one generator edit: its leg re-mints, the seed off it refreshes, the
#    stacked leg downstream re-mints -- and the unrelated legs do not.
sleep 1
edit tools/tests/gen_b.lua "gen b v2"
run
check "gen_b edit re-runs b and its dependents only" "b e " "$ran"

# 6. each composed-in lib half re-runs every leg; the contract half is the
#    issue-#25 addition the old stamp never hashed.
for half in ot6.lua ot6_field.lua ot6_contract.lua; do
  sleep 1
  edit "tools/tests/lib/$half" "$half EDITED $$"
  run
  check "lib/$half edit re-runs every leg" "a b c e " "$ran"
done

# 7. anchor payload and manifest edits re-run the anchored leg only.
sleep 1
edit tools/tests/anchors/toy-v1/toy.sram "sram v2"
run
check "anchor payload edit re-runs the anchored leg" "c " "$ran"
sleep 1
edit tools/tests/anchors/toy-v1/manifest.json '{"v":2}'
run
check "anchor manifest edit re-runs the anchored leg" "c " "$ran"

# 8. a failing mint fails the BUILD and blocks dependents; the retry runs it
#    again -- failure is never recorded as success.
sleep 1
: > "$TMP/build/fail.b"
edit tools/tests/gen_b.lua "gen b v3"
run
[ "$rc" -ne 0 ] && echo "  pass failing mint fails the build" ||
  { echo "  FAIL build succeeded through a failing mint"; ok=0; }
check "failed leg ran, dependent did not" "b " "$ran"
rm "$TMP/build/fail.b"
run
check "retry re-runs the failed leg and dependents" "b e " "$ran"
check "retry build succeeds" 0 "$rc"

# 9. the silent-no-op class: an unknown target is a hard error, where make's
#    .PHONY pattern rules reported success in 0.036s having run nothing.
(cd "$TMP" && ninja -f build/build.ninja smoke-gen_bogus) > "$NIN" 2>&1
[ $? -ne 0 ] && grep -q "unknown target" "$NIN" &&
  echo "  pass unknown target is a hard error" ||
  { echo "  FAIL unknown target did not error"; ok=0; }

# 10. provenance: the stamp a mint edge writes is byte-identical to the sig
#     compose.py will re-derive (the two sides of the consume-time guard).
want=$(cd "$TMP" && OT6_ROOT="$TMP" sh tools/tests/lib/frontier_stamp.sh sig gen_b)
[ "$(cat "$TMP/build/states/b.stamp")" = "$want" ] &&
  echo "  pass mint edge stamp matches sig" ||
  { echo "  FAIL stamp/sig disagree"; ok=0; }

[ "$ok" -eq 1 ] && { echo "frontier_ninja selftest: ok"; exit 0; }
echo "frontier_ninja selftest: FAILED"; exit 1
