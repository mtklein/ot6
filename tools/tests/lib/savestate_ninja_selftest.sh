#!/bin/sh
# savestate_ninja_selftest.sh: checks the generated ninja graph's build
# semantics end-to-end against a mock tree, with no emulator: the game is
# played once from power-on (#363), each cut Continuing the capture the run
# before it made, and only what a change really reaches re-runs.
set -u
command -v ninja >/dev/null 2>&1 || {
  echo "savestate_ninja selftest: ninja not installed -- brew bundle"; exit 1; }

REAL="$(cd "$(dirname "$0")/../../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ok=1

# ---- the mock tree ---------------------------------------------------------
mkdir -p "$TMP/tools/tests/lib" "$TMP/tools/tests/checkpoints/toy-v1" \
         "$TMP/tools/tests/checkpoints/cut-v1" "$TMP/build" "$TMP/tools/mesen" \
         "$TMP/tools/build"
cp "$REAL/tools/tests/lib/savestate_ninja.py" "$TMP/tools/tests/lib/"
cp "$REAL/tools/build/rom_version.py" "$TMP/tools/build/"
cp "$REAL/tools/tests/lib/savestate_stamp.sh" "$TMP/tools/tests/lib/"
cp "$REAL/tools/tests/lib/lua_fingerprint.py" "$TMP/tools/tests/lib/"
printf 'lib v1\n'      > "$TMP/tools/tests/lib/ot6.lua"
printf 'field v1\n'    > "$TMP/tools/tests/lib/ot6_field.lua"
printf 'contract v1\n' > "$TMP/tools/tests/lib/ot6_contract.lua"
for g in a b c h k cut; do printf 'gen %s v1\n' "$g" > "$TMP/tools/tests/gen_$g.lua"; done
printf 'gen g v1\n' > "$TMP/tools/tests/gen_g.lua"
printf 'rom v1\n' > "$TMP/build/ot6.sfc"
printf 'emulator v1\n' > "$TMP/tools/mesen/EMULATOR"
printf 'replay v1\n' > "$TMP/tools/tests/replay.txt"
for k in toy cut; do
  printf '{"payload": "%s.sram", "saved": "%s"}\n' "$k" "$k" \
    > "$TMP/tools/tests/checkpoints/$k-v1/manifest.json"
  printf 'tracked %s v1' "$k" > "$TMP/tools/tests/checkpoints/$k-v1/$k.sram"
done
# The seal's two tools, stubbed: the real ones need a real 32 KiB battery.
# The stub seal records that it ran over the manifest the edge copied in.
printf '%s\n' 'import sys' \
  'if sys.argv[1] == "seal": open(sys.argv[2] + "/manifest.json", "a").write("sealed\n")' \
  > "$TMP/tools/tests/lib/sram_checkpoint.py"
printf 'import sys\n' > "$TMP/tools/tests/lib/checkpoint_drift.py"

# Stub run.sh: journals the invocation, honors an injected failure, mirrors
# tools/tests/run.sh's publish step, and writes a capture when asked
# (OT6_CAPTURE_SRM), its bytes a function of what the run booted, so a
# capture moves exactly when its run's play would.
cat > "$TMP/tools/tests/run.sh" <<'EOF'
#!/bin/sh
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="${1:?usage: stub run.sh <script.lua>}"
echo "$OT6_WORKER${OT6_SRAM_CHECKPOINT:+ checkpoint=$OT6_SRAM_CHECKPOINT}" >> "$ROOT/build/journal"
[ -e "$ROOT/build/fail.$OT6_WORKER" ] && { echo "stub run.sh: injected failure for $OT6_WORKER"; exit 1; }
mkdir -p "$ROOT/build/states"
seen="$(cat "$ROOT/build/ot6.sfc" "$SCRIPT" | cksum)"
if [ -n "${OT6_CAPTURE_SRM:-}" ]; then
  mkdir -p "$(dirname "$OT6_CAPTURE_SRM")"
  echo "capture by $OT6_WORKER from $seen" > "$OT6_CAPTURE_SRM"
  echo '{}' > "$OT6_CAPTURE_SRM.provenance.json"
fi
[ -n "${OT6_NO_PUBLISH:-}" ] && exit 0
for src in $OT6_EXPECT_ARTIFACT; do
  case "$src" in
    *.mss) echo "generated $src by $OT6_WORKER from $seen" > "$ROOT/build/states/$src" ;;
    *) echo 'return "AA=="' > "$ROOT/build/states/$src" ;;
  esac
done
exit 0
EOF
chmod +x "$TMP/tools/tests/run.sh"

# The toy graph: a power-on root a; b, whose run saves toy-v1; the cut c,
# Continuing it; g, one run publishing g and g1; h off g1; and the cut k,
# whose save a cutter makes from h.
cat > "$TMP/tools/tests/savestate_graph.py" <<'EOF'
def S(state, **kw):
    e = {"state": state, "gen": None, "prev": None, "checkpoint": None}
    e.update(kw)
    return e
STATES = [
    S("a", gen="gen_a"),
    S("b", gen="gen_b", prev="a"),
    S("c", gen="gen_c", prev="b", checkpoint="toy-v1"),
    S("g", gen="gen_g", also=["g1"]),
    S("h", gen="gen_h", prev="g1"),
    S("k", gen="gen_k", prev="h", checkpoint="cut-v1", cutter="gen_cut"),
]
EOF

# ---- helpers ---------------------------------------------------------------
NIN="$TMP/ninja.log"
run() { # regenerate + build; rc in $rc, runs (sorted) in $ran
  (cd "$TMP" && python3 tools/tests/lib/savestate_ninja.py &&
   ninja -f build/build.ninja savestates) > "$NIN" 2>&1
  rc=$?
  cp "$TMP/build/journal" "$TMP/journal.last" 2>/dev/null || : > "$TMP/journal.last"
  ran=$(sed 's/ .*//' "$TMP/build/journal" 2>/dev/null | sort | tr '\n' ' ')
  : > "$TMP/build/journal"
}
check() { # <label> <want> <got>
  if [ "$3" = "$2" ]; then echo "  pass $1"
  else echo "  FAIL $1: want '$2' got '$3'"; ok=0; fi
}
edit() { printf '%s\n' "$2" > "$TMP/$1"; }
ALL="a b c cut_v1 g h k "

# 1. fresh tree: every run runs once, the cuts Continue the captures.
: > "$TMP/build/journal"
run
check "fresh tree plays every run exactly once" "$ALL" "$ran"
check "fresh tree build succeeds" 0 "$rc"
grep -q '^c checkpoint=build/checkpoints/toy-v1$' "$TMP/journal.last" &&
  echo "  pass the cut Continues the capture b's run made" ||
  { echo "  FAIL the cut did not Continue build/checkpoints/toy-v1"; ok=0; }
grep -q '^k checkpoint=build/checkpoints/cut-v1$' "$TMP/journal.last" &&
  echo "  pass the cutter cut Continues the cutter's capture" ||
  { echo "  FAIL the cutter cut did not Continue build/checkpoints/cut-v1"; ok=0; }
grep -q 'capture by b ' "$TMP/build/checkpoints/toy-v1/toy.sram" &&
  grep -q '^sealed$' "$TMP/build/checkpoints/toy-v1/manifest.json" &&
  grep -q '"saved": "toy"' "$TMP/build/checkpoints/toy-v1/manifest.json" &&
  echo "  pass b's run captured toy-v1, sealed against the tracked manifest's authored fields" ||
  { echo "  FAIL toy-v1's capture or seal"; ok=0; }
grep -q 'capture by cut_v1 ' "$TMP/build/checkpoints/cut-v1/cut.sram" &&
  [ ! -e "$TMP/build/states/cut_v1.mss" ] &&
  echo "  pass the cutter captured cut-v1 and published no state" ||
  { echo "  FAIL the cutter's capture"; ok=0; }
grep -q '^journal\|tracked' "$TMP/journal.last" &&
  { echo "  FAIL a run booted a tracked checkpoint"; ok=0; } ||
  echo "  pass no run boots a tracked checkpoint"
grep -q "for g1\|generated g1.mss by g " "$TMP/build/states/g1.mss" &&
  echo "  pass one run published both of g's artifacts" ||
  { echo "  FAIL g1 missing"; ok=0; }

# 2. quiescent: nothing re-runs.
run
check "untouched tree plays nothing" "" "$ran"
grep -q "no work to do" "$NIN" && echo "  pass ninja reports no work" ||
  { echo "  FAIL expected 'no work to do'"; ok=0; }

# 3. mtime-only touches (a checkout, a worktree cp): nothing re-runs.
sleep 1
touch "$TMP/build/ot6.sfc" "$TMP/tools/mesen/EMULATOR" "$TMP/tools/tests/gen_a.lua" \
      "$TMP/tools/tests/replay.txt" \
      "$TMP/tools/tests/lib/ot6.lua" "$TMP/tools/tests/lib/ot6_field.lua" \
      "$TMP/tools/tests/lib/ot6_contract.lua" \
      "$TMP/tools/tests/checkpoints/toy-v1/toy.sram" \
      "$TMP/tools/tests/checkpoints/toy-v1/manifest.json"
run
check "mtime-only touch plays nothing (restat)" "" "$ran"

# 3a. Generator prose and re-indent changes copy the new bytes but play
# nothing; a code change below still replays its descendants.
sleep 1
before=$(cat "$TMP/build/states/a.stamp")
printf '  gen  a   v1 -- comment only\n\n' > "$TMP/tools/tests/gen_a.lua"
run
check "generator comment/whitespace plays nothing" "" "$ran"
check "generator comment leaves captured stamp untouched" "$before" "$(cat "$TMP/build/states/a.stamp")"
cmp -s "$TMP/tools/tests/gen_a.lua" "$TMP/build/ninja/src/tools/tests/gen_a.lua" &&
  echo "  pass generator copy retains new raw bytes" ||
  { echo "  FAIL generator copy lost raw bytes"; ok=0; }

# 4. ROM content change: every run, once.
sleep 1
edit build/ot6.sfc "rom v2"
run
check "ROM content change plays EVERY run once" "$ALL" "$ran"

# 4a. Emulator pin change (tools/mesen/EMULATOR): every run, once.
sleep 1
edit tools/mesen/EMULATOR "emulator v2"
run
check "emulator pin change plays EVERY run once" "$ALL" "$ran"

# 4b. The scheduled-replay lever: every run, once.
sleep 1
edit tools/tests/replay.txt "replay v2"
run
check "a tools/tests/replay.txt bump plays EVERY run once" "$ALL" "$ran"

# 4c. The ROM is copied by its identity (tools/build/rom_version.py: the
#     version fields and the header checksum masked).  A version-only
#     change -- the release commit's VERSION bump -- plays nothing; one
#     flipped byte anywhere else plays everything.
romfill() { # <version-field byte> <code byte at $1234>: a 64 KB mock ROM
  python3 -c "import sys; b = bytearray(b'\xa5' * 0x10000); b[0xFFA5] = int(sys.argv[1]); b[0xFFC5] = int(sys.argv[1]); b[0xFFDC] = int(sys.argv[1]); b[0x1234] = int(sys.argv[2]); open(sys.argv[3], 'wb').write(b)" "$1" "$2" "$TMP/build/ot6.sfc"
}
sleep 1
romfill 1 1
run
check "a ROM content change (to the 64 KB mock) plays EVERY run" "$ALL" "$ran"
sleep 1
romfill 2 1
run
check "a version-field-only ROM change plays NOTHING" "" "$ran"
sleep 1
romfill 2 2
run
check "one byte flipped outside the version fields plays EVERY run" "$ALL" "$ran"

# 5. a generator edit plays its run and every run its output reaches,
#    through a capture too, and nothing else.
sleep 1
edit tools/tests/gen_b.lua "gen b v2"
run
check "gen_b edit plays b and the cut that Continues b's save" "b c " "$ran"
sleep 1
edit tools/tests/gen_a.lua "gen a v2"
run
check "gen_a edit plays the line from a" "a b c " "$ran"
sleep 1
edit tools/tests/gen_h.lua "gen h v2"
run
check "gen_h edit plays h, its cutter and the cut after it" "cut_v1 h k " "$ran"
sleep 1
edit tools/tests/gen_cut.lua "gen cut v2"
run
check "a cutter edit plays the cutter and the cut after it" "cut_v1 k " "$ran"
sleep 1
printf 'gen g v2\n' > "$TMP/tools/tests/gen_g.lua"
run
check "gen_g edit plays g's one run and what it reaches" "cut_v1 g h k " "$ran"

# 6. a composed-in lib half is provenance, not a scheduling input: editing
#    one plays nothing (docs/TESTING.md), and the stamps keep recording
#    what they were made from.
for half in ot6.lua ot6_field.lua ot6_contract.lua; do
  sleep 1
  before=$(cat "$TMP/build/states/c.stamp")
  edit "tools/tests/lib/$half" "$half EDITED $$"
  run
  check "lib/$half edit plays NOTHING" "" "$ran"
  check "lib/$half edit leaves the stamp's recorded provenance alone" \
    "$before" "$(cat "$TMP/build/states/c.stamp")"
done

# 7. the tracked checkpoint is the capture's committed copy, booted by
#    nothing: a re-cut (new payload, sealed fields) plays nothing; an edit
#    to its authored fields re-seals, which replays the producer's run.
sleep 1
cp "$TMP/build/checkpoints/toy-v1/toy.sram" "$TMP/tools/tests/checkpoints/toy-v1/toy.sram"
printf '{"payload": "toy.sram", "saved": "toy", "sha256": "x", "size": 9}\n' \
  > "$TMP/tools/tests/checkpoints/toy-v1/manifest.json"
run
check "a re-cut of the tracked checkpoint plays NOTHING" "" "$ran"
sleep 1
printf '{"payload": "toy.sram", "saved": "toy2", "sha256": "x", "size": 9}\n' \
  > "$TMP/tools/tests/checkpoints/toy-v1/manifest.json"
run
check "an authored-field edit re-seals: the producer's run and the cut" "b c " "$ran"

# 8. a failing run fails the build and blocks what it reaches; the retry
#    runs it again, so failure is never recorded as success.
sleep 1
: > "$TMP/build/fail.b"
edit tools/tests/gen_b.lua "gen b v3"
run
[ "$rc" -ne 0 ] && echo "  pass failing generation fails the build" ||
  { echo "  FAIL build succeeded through a failing generation"; ok=0; }
check "failed run ran, the cut after it did not" "b " "$ran"
rm "$TMP/build/fail.b"
run
check "retry re-runs the failed run and the cut" "b c " "$ran"
check "retry build succeeds" 0 "$rc"

# 9. an unknown target is a hard error.
(cd "$TMP" && ninja -f build/build.ninja smoke-gen_bogus) > "$NIN" 2>&1
[ $? -ne 0 ] && grep -q "unknown target" "$NIN" &&
  echo "  pass unknown target is a hard error" ||
  { echo "  FAIL unknown target did not error"; ok=0; }

# 10. provenance: the stamp a `generate` edge writes carries its own
#     artifact's hash and the hash of what it grew from -- prev's stamp, or
#     at a cut the capture's sealed manifest -- so the line verifies from
#     files on disk alone; the cutter's record names its ROM, its own sig,
#     the payload and the stamp of the state it booted.
want=$(cd "$TMP" && OT6_ROOT="$TMP" sh tools/tests/lib/savestate_stamp.sh sig gen_b)
[ "$(head -n 1 "$TMP/build/states/b.stamp")" = "$want" ] &&
  echo "  pass generate-edge stamp matches sig" ||
  { echo "  FAIL stamp/sig disagree"; ok=0; }
[ "$(sed -n 2p "$TMP/build/states/b.stamp")" = \
  "rom $(python3 "$REAL/tools/build/rom_version.py" identity "$TMP/build/ot6.sfc")" ] &&
  echo "  pass generate-edge stamp records the ROM it booted" ||
  { echo "  FAIL rom line wrong or missing"; ok=0; }
[ "$(sed -n 8p "$TMP/build/states/b.stamp")" = \
  "ancestor build/states/a.stamp $(shasum -a 256 "$TMP/build/states/a.stamp" | cut -c1-64)" ] &&
  echo "  pass chained stamp binds its predecessor's stamp (#75)" ||
  { echo "  FAIL ancestor binding wrong or missing"; ok=0; }
grep -q "^ancestor build/checkpoints/toy-v1/manifest.json $(shasum -a 256 "$TMP/build/checkpoints/toy-v1/manifest.json" | cut -c1-64)\$" \
  "$TMP/build/states/c.stamp" &&
  echo "  pass a cut's stamp binds the capture's sealed manifest" ||
  { echo "  FAIL the cut's stamp does not bind its capture"; ok=0; }
rec="$TMP/build/checkpoints/cut-v1.record"
grep -q "^rom $(python3 "$REAL/tools/build/rom_version.py" identity "$TMP/build/ot6.sfc")\$" "$rec" &&
  grep -q "^generator $(cd "$TMP" && OT6_ROOT="$TMP" sh tools/tests/lib/savestate_stamp.sh gensig gen_cut)\$" "$rec" &&
  grep -q "^payload $(shasum -a 256 "$TMP/build/checkpoints/cut-v1/cut.sram" | cut -c1-64)\$" "$rec" &&
  grep -q "^ancestor build/states/h.stamp $(shasum -a 256 "$TMP/build/states/h.stamp" | cut -c1-64)\$" "$rec" &&
  echo "  pass the cutter's record names its ROM, its sig, the payload and its boot" ||
  { echo "  FAIL the cutter's record"; cat "$rec"; ok=0; }

# 11. Real copy rules with a journalled mock suite: exercise the same
# library/suite copies configure.py emits, without claiming game play.
cat > "$TMP/suite_graph.py" <<'PYGRAPH'
from pathlib import Path
import sys
sys.path.insert(0, "tools/tests/lib")
import savestate_ninja as sn
lines=[]
sn.emit_state_rules(lines.append)
lines += ["rule copy_if_changed", "  command = cp $in $out", "  restat = 1",
          "rule suite", "  command = echo suite >> build/suite_journal && touch $out"]
sources = list(sn.LIB_HALVES) + ["tools/tests/battle_toy.lua"]
for src in sources:
    dst = sn.copy_if_changed_from(src)
    lines.append(f"build {dst}: {sn.copy_rule(src, [])} {src}")
lines.append("build build/toy.ok: suite " + " ".join(sn.copy_if_changed_from(s) for s in sources))
Path("build/suite.ninja").write_text("\n".join(lines) + "\n")
PYGRAPH
printf 'return true\n' > "$TMP/tools/tests/battle_toy.lua"
(cd "$TMP" && python3 suite_graph.py && ninja -f build/suite.ninja) > "$NIN" 2>&1
check "mock suite starts" 0 "$?"
for source in tools/tests/gen_a.lua tools/tests/lib/ot6.lua \
              tools/tests/lib/ot6_field.lua tools/tests/lib/ot6_contract.lua \
              tools/tests/battle_toy.lua; do
  sleep 1
  saved=$(cat "$TMP/$source")
  printf '  %s -- prose edit\n\n' "$saved" > "$TMP/$source"
  : > "$TMP/build/suite_journal"
  run
  check "comment edit plays nothing: $source" "" "$ran"
  (cd "$TMP" && ninja -f build/suite.ninja) > "$NIN" 2>&1
  check "comment edit runs no suite: $source" "" "$(cat "$TMP/build/suite_journal")"
  cmp -s "$TMP/$source" "$TMP/build/ninja/src/$source" &&
    echo "  pass new raw bytes copied: $source" ||
    { echo "  FAIL raw copy: $source"; ok=0; }
  case "$source" in */gen_a.lua) continue ;; esac
  sleep 1
  printf '%s\nreturn false\n' "$saved" > "$TMP/$source"
  (cd "$TMP" && ninja -f build/suite.ninja) > "$NIN" 2>&1
  case "$source" in
    */gen_a.lua) : ;; # generator code replay was exercised above
    *) check "code edit re-runs suite: $source" suite "$(cat "$TMP/build/suite_journal")" ;;
  esac
done

[ "$ok" -eq 1 ] && { echo "savestate_ninja selftest: ok"; exit 0; }
echo "savestate_ninja selftest: FAILED"; exit 1
