#!/bin/sh
# frontier_stamp_selftest.sh -- prove the issue #2 freshness gate in isolation,
# no emulator, on a mock tree (OT6_ROOT).  Pins the mint-or-skip DECISION for
# each of the four axes the gate must react to: state missing, ROM bytes,
# generator source, lib/ot6.lua -- and the quiescent "nothing changed" case.
# This is the positive/negative control the mint macro's expensive real mints
# stand on; if the decision logic is wrong, every proof above it is theatre.
set -u
GATE="$(cd "$(dirname "$0")" && pwd)/frontier_stamp.sh"
ok=1
check() { # <label> <expected: MINT|FRESH> <actual-rc>
  want="$2"; got=FRESH; [ "$3" -eq 0 ] && got=MINT
  if [ "$got" = "$want" ]; then echo "  pass $1 -> $got"
  else echo "  FAIL $1: got $got want $want"; ok=0; fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/tools/tests/lib" "$TMP/build/states"
printf 'gen body v1\n'  > "$TMP/tools/tests/gen_fake.lua"
printf 'lib body v1\n'  > "$TMP/tools/tests/lib/ot6.lua"
printf 'rom-bytes\n'    > "$TMP/build/states/.rom-copy"
export OT6_ROOT="$TMP"
S="$TMP/build/states"

# 1. never minted: no .mss -> MINT
sh "$GATE" needsmint fake gen_fake; check "state absent" MINT $?

# mint it: create the .mss NEWER than .rom-copy, then record the stamp.
printf 'savestate\n' > "$S/fake.mss"; touch "$S/fake.mss"
sh "$GATE" write fake gen_fake

# 2. nothing changed -> FRESH (the fast no-op)
sh "$GATE" needsmint fake gen_fake; check "nothing changed" FRESH $?

# 3. ROM bytes changed (.rom-copy re-stamped newer) -> MINT
sleep 1; printf 'rom-bytes-v2\n' > "$S/.rom-copy"
sh "$GATE" needsmint fake gen_fake; check "ROM bytes changed" MINT $?
# re-mint to clear it (mss newest again, stamp already current)
touch "$S/fake.mss"
sh "$GATE" needsmint fake gen_fake; check "ROM re-mint clears" FRESH $?

# 4. generator source changed (mss/rom untouched) -> MINT, and ONLY reacts to
#    a CONTENT change: a mtime-only touch with identical bytes stays FRESH.
touch "$TMP/tools/tests/gen_fake.lua"     # newer mtime, same bytes
sh "$GATE" needsmint fake gen_fake; check "generator mtime-only touch" FRESH $?
printf 'gen body v2\n' > "$TMP/tools/tests/gen_fake.lua"   # real edit
sh "$GATE" needsmint fake gen_fake; check "generator content changed" MINT $?
sh "$GATE" write fake gen_fake            # re-mint records new sig
sh "$GATE" needsmint fake gen_fake; check "generator re-mint clears" FRESH $?

# 5. lib/ot6.lua changed -> MINT (a comment-only touch is content, so it counts;
#    a pure mtime touch does not)
touch "$TMP/tools/tests/lib/ot6.lua"
sh "$GATE" needsmint fake gen_fake; check "lib mtime-only touch" FRESH $?
printf 'lib body v2\n' > "$TMP/tools/tests/lib/ot6.lua"
sh "$GATE" needsmint fake gen_fake; check "lib content changed" MINT $?

# 6. per-generator granularity: with lib HELD CONSTANT, editing one generator
#    trips only its own state, never a sibling minted from a different one.
#    (Editing the SHARED lib trips both -- proven in step 5 -- and is the
#    coarse axis the report's granularity note is about.)
printf 'lib frozen\n'  > "$TMP/tools/tests/lib/ot6.lua"
printf 'fake gen f\n'  > "$TMP/tools/tests/gen_fake.lua"
printf 'other gen g\n' > "$TMP/tools/tests/gen_other.lua"
printf 'savestate2\n'  > "$S/other.mss"; touch "$S/other.mss"; touch "$S/fake.mss"
sh "$GATE" write fake  gen_fake
sh "$GATE" write other gen_other
sh "$GATE" needsmint fake  gen_fake;  check "baseline both fresh (fake)"  FRESH $?
sh "$GATE" needsmint other gen_other; check "baseline both fresh (other)" FRESH $?
printf 'fake gen f2\n' > "$TMP/tools/tests/gen_fake.lua"   # edit ONLY gen_fake
sh "$GATE" needsmint fake  gen_fake;  check "per-gen: edited state trips"  MINT  $?
sh "$GATE" needsmint other gen_other; check "per-gen: sibling stays fresh" FRESH $?

[ "$ok" -eq 1 ] && { echo "frontier_stamp selftest: ok"; exit 0; }
echo "frontier_stamp selftest: FAILED"; exit 1
