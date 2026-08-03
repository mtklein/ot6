#!/bin/sh
# frontier_stamp.sh -- the ONE definition of a minted fixture's provenance
# signature.
#
# HISTORY: this script used to also DECIDE mint-or-skip (`needsmint`), and the
# Makefile's mint macro would `touch` the target afterwards to stop make
# re-deciding by mtime -- a content gate beside an mtime scheduler, two
# mechanisms that could disagree (and on 2026-07-27 did: a resumed run
# printed "rom content changed", then booted an old-ROM savestate against the
# new ROM).  Scheduling now belongs entirely to the generated ninja graph
# (tools/tests/lib/frontier_ninja.py): every input is a declared dependency
# and content-staleness is ninja's own restat mechanism, so `needsmint` is
# gone with the macros that called it.
#
# What remains is the signature itself, because it is compared on two sides
# and both must agree byte-for-byte:
#   * the mint edge `write`s build/states/<state>.stamp after a successful
#     mint (see the mint rule in build/build.ninja);
#   * lib/compose.py re-derives it at embed time (via `sig`, shelled to this
#     script so there is exactly one implementation) and refuses -- loudly,
#     through the [ot6] channel -- a fixture that reached a test WITHOUT
#     passing any mint gate: a worktree-setup seed that a local generator or
#     lib edit has since drifted.  That consume-time guard is why the stamp
#     still exists at all.
#
#   frontier_stamp.sh write <state> <generator> <ancestor|-> [extra ...]
#   frontier_stamp.sh sig   <generator> [extra ...]
#
# The signature hashes the generator and ALL THREE lib halves compose.py
# inlines into every composed script -- lib/ot6.lua, lib/ot6_field.lua and
# lib/ot6_contract.lua, in inline order -- plus any declared extra inputs
# (battery anchors hash manifest then payloads).  The contract half joined
# the digest with the ninja graph (issue #25): an invariant-contract edit
# re-mints every leg, and the consume-time check has to agree that a
# pre-edit fixture is stale.  Content-keyed throughout: a mere mtime bump
# (a `git checkout`, a worktree cp) changes no signature.
#
# PROVENANCE BINDINGS (issue #75 step 5).  The signature above answers "were
# these SOURCES the ones that minted?"  It never bound the ARTIFACT: a
# hand-crafted .mss dropped beside a matching stamp read as fresh, and a
# fixture chained off a poked predecessor carried no trace of that ancestry.
# So `write` now records three things, one per line:
#
#     <sha256(GATE_CONTRACT ++ gen ++ ot6.lua ++ ot6_field.lua ++
#             ot6_contract.lua ++ extras...)> <gen> [extras...]
#     artifact <sha256(build/states/<state>.mss)>
#     ancestor <path> <sha256(<path> file bytes)>        (non-root mints only)
#
# The artifact line binds stamp -> minted bytes, so replacing the .mss
# without a mint is detected.  The ancestor line binds stamp -> the
# predecessor's stamp file (prev= edges) or the anchor's manifest.json
# (anchor= edges), so the WHOLE chain is verifiable transitively on disk:
# each stamp vouches for its artifact and names the exact stamp it grew
# from, all the way down to a power-on root.  compose.py's stamp_check
# verifies every line; `compose.py --check-states` asks it of the whole
# tree and is a hard `make test` gate.
set -u

# THE GATE-CONTRACT VERSION -- a fixed input to every signature.  Bumping it
# deliberately stales every stamp in existence, forcing a full re-mint under
# the new rules; that is the point, not a side effect.  v1 is the provenance
# format above (issue #75 step 5).  The runtime write-gate (issue #75 step 4)
# bumps this to v2 when it lands, so no fixture minted without the gate can
# survive into the gated era.  Keep it a single obvious constant: both sides
# of the comparison (the mint edge and compose.py) shell into THIS file, so
# there is exactly one definition to bump.
GATE_CONTRACT='ot6-provenance/v1'

# OT6_ROOT lets selftests and compose.py point the sig at another tree; the
# default is the real tree this script lives in (lib/ -> tests/ -> tools/ ->
# root).
ROOT="${OT6_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
STATES="$ROOT/build/states"

# sha256(<generator source> ++ <battle core> ++ <nav half> ++ <contract
# half>) plus the generator's name and the extras' paths.  Order is FIXED --
# the same order compose.py inlines them -- so the digest is reproducible
# from either side.
sig() {
  gen="$1"
  shift
  files="$ROOT/tools/tests/$gen.lua
$ROOT/tools/tests/lib/ot6.lua
$ROOT/tools/tests/lib/ot6_field.lua
$ROOT/tools/tests/lib/ot6_contract.lua"
  # Every fixed input must exist BEFORE hashing: the digest pipeline's `cat`
  # cannot fail it (a pipeline swallows the status), so a typo'd generator
  # would otherwise hash the remaining files and call that a signature.
  printf '%s\n' "$files" | while IFS= read -r f; do
    [ -f "$f" ] ||
      { echo "frontier_stamp: missing input '$f'" >&2; exit 2; }
  done || exit 2
  extras=""
  for extra in "$@"; do
    case "$extra" in /*|*..*) echo "frontier_stamp: unsafe extra '$extra'" >&2; exit 2 ;; esac
    [ -f "$ROOT/$extra" ] ||
      { echo "frontier_stamp: missing extra '$ROOT/$extra'" >&2; exit 2; }
    files="$files
$ROOT/$extra"
    extras="$extras $extra"
  done
  # The gate-contract version leads the byte stream, so bumping the constant
  # above moves every signature at once (see its comment).
  digest=$(
    { printf '%s\n' "$GATE_CONTRACT"
      printf '%s\n' "$files" | while IFS= read -r file; do cat "$file"; done
    } | shasum -a 256 | cut -c1-64
  )
  printf '%s %s%s' "$digest" "$gen" "$extras"
}

# sha256 of one file, bare.  Used for the artifact and ancestor bindings.
filehash() {
  shasum -a 256 "$1" | cut -c1-64
}

cmd="${1:?usage: frontier_stamp.sh write|sig ...}"
case "$cmd" in
  sig)
    gen="${2:?sig needs a generator}"; shift 2
    sig "$gen" "$@"
    ;;
  write)
    state="${2:?write needs a state}"; gen="${3:?write needs a generator}"
    ancestor="${4:?write needs an ancestor (a .stamp/manifest.json path relative to the tree root, or - for a power-on root)}"
    shift 4
    # Bind the artifact FIRST: a stamp that cannot name the exact bytes it
    # vouches for must never exist at all.  The .mss was published by the
    # same mint command a moment ago, so a miss here is a real wiring bug.
    mss="$STATES/$state.mss"
    [ -f "$mss" ] ||
      { echo "frontier_stamp: no minted artifact '$mss' to bind" >&2; exit 2; }
    artifact=$(filehash "$mss")
    anc_hash=""
    if [ "$ancestor" != "-" ]; then
      case "$ancestor" in /*|*..*)
        echo "frontier_stamp: unsafe ancestor '$ancestor'" >&2; exit 2 ;;
      esac
      [ -f "$ROOT/$ancestor" ] ||
        { echo "frontier_stamp: missing ancestor '$ROOT/$ancestor'" >&2; exit 2; }
      anc_hash=$(filehash "$ROOT/$ancestor")
    fi
    # Everything is computed; only now may the old stamp be replaced.
    sigline=$(sig "$gen" "$@") || exit 2
    {
      printf '%s\n' "$sigline"
      printf 'artifact %s\n' "$artifact"
      [ "$ancestor" = "-" ] ||
        printf 'ancestor %s %s\n' "$ancestor" "$anc_hash"
    } > "$STATES/$state.stamp"
    ;;
  *)
    echo "frontier_stamp.sh: unknown command '$cmd'" >&2
    exit 2
    ;;
esac
