#!/usr/bin/env python3
"""savestate_ninja.py -- emit the savestate graph
(tools/tests/savestate_graph.py) as build/build.ninja.

Replaces the Makefile's generate/generate_checkpoint/stackseed macros, the SAVESTATES
lists, the ~104 hand-written rules, and the grep-generated dependency include
(issue #25).  The old shape kept producing four failure modes; each is listed
below with the mechanism here that prevents it:

 * A content stamp beside a touch: make decides staleness by mtime, so the
   content check (savestate_stamp.sh needsgen) had to `touch` the target to
   stop make re-deciding.  The two mechanisms could disagree, and did
   (2026-07-27: a resumed run printed "rom content changed" then booted an
   old-ROM savestate against the new ROM).  Here the decision and the
   execution are one mechanism: every generated state declares its real
   inputs, and the "is the content the same?" question is answered by
   `restat` latch edges (below), inside ninja's own scheduler.
 * make never reconsiders: a target with no newer prerequisite is skipped
   without its recipe running, so that generated include existed only to add
   generator/lib prerequisites back on.  Ninja edges list every input
   directly, emitted from the same data entry that defines the step, so
   there is no second list to go stale.
 * A silent .PHONY no-op: GNU make does not apply implicit pattern rules to
   .PHONY targets, so `smoke-%: rom` matched nothing and reported success in
   0.036s.  Ninja has no implicit rules: every target is an explicit edge,
   an unknown target is a hard error, and a dirty edge either runs its
   command or fails.
 * The graph in three places: macros, rules and a generated include.  The
   graph is now one data list, which this script translates.

The content-staleness mechanism (`restat`): git checkouts and rebuilds bump
mtimes without changing bytes, and generating a savestate costs minutes to
hours, so mtime alone must never schedule one.  Every source input to a
generated state (the ROM, the generator .lua, the three composed-in lib
halves, checkpoint manifests and payloads) is therefore routed through a latch
edge:

    build build/ninja/src/<path>: latch <path>      (cmp -s || cp; restat=1)

The latch re-runs on any mtime bump (cheap: one cmp), rewrites its output
only when bytes differ, and `restat = 1` tells ninja to re-stat the output
and prune everything downstream when it did not move.  A touched-but-equal
file regenerates nothing; a changed ROM re-runs every transitive dependent,
because a state's staleness is determined by its position in this graph.
Generated states themselves are not latched: a regenerated .mss is new bytes,
and everything booted from it must replay.

What does not participate in staleness (same as the stamp check this
replaces): the harness itself (run.sh, compose.py, decode_b64.py,
pin_test_saves.py, sram_checkpoint.py) and ff6-en.dbg.  A harness edit has never
invalidated a generated state, and widening the input set would regenerate
every state on any tooling change.

savestate_stamp.sh has a narrower job now: each state-generating edge
still `write`s build/states/<state>.stamp after success, because
lib/compose.py re-derives that signature at embed time to catch a fixture
that reached a test without passing any freshness check (a worktree-seeded
state that a local edit has since drifted from).  The stamp is provenance for
that consume-time check, and it no longer schedules anything.

Usage:
    python3 tools/tests/lib/savestate_ninja.py             # (re)write build/build.ninja
    python3 tools/tests/lib/savestate_ninja.py --list      # state names, play order
    python3 tools/tests/lib/savestate_ninja.py --selftest  # validation negatives

The write is compare-and-conditionally-write, so an unchanged graph leaves
build/build.ninja's mtime alone; build.ninja also regenerates itself via a
`generator = 1` edge when this script or the graph data changes, so bare
`ninja -f build/build.ninja` stays correct without the make wrapper.
Emitted paths are relative to the repo root: run ninja from the root (the
make wrappers do), or a state-generating edge's run.sh invocation will not
resolve.
"""

import argparse
import re
import runpy
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent          # tools/tests/lib
ROOT = HERE.parent.parent.parent                # lib -> tests -> tools -> root

SELF = "tools/tests/lib/savestate_ninja.py"
GRAPH = "tools/tests/savestate_graph.py"
OUT = "build/build.ninja"
ROM = "build/ot6.sfc"
LATCH_DIR = "build/ninja/src"
# The three lib halves compose.py inlines into every composed generator, in
# inline order.  ot6_contract.lua is the invariant-contract half: an edit to
# a contract must re-run every step that asserts it (issue #25), which the old
# stamp signature never covered.
LIB_HALVES = (
    "tools/tests/lib/ot6.lua",
    "tools/tests/lib/ot6_field.lua",
    "tools/tests/lib/ot6_contract.lua",
)

NAME_RE = re.compile(r"^[A-Za-z0-9_]+$")
STACK_RE = re.compile(r"^[A-Za-z0-9]+_$")
FIELDS = {"state", "gen", "prev", "checkpoint", "seed", "stack", "after",
          "timeout"}


def checkpoint_inputs(root, key):
    """Manifest first, then sorted payloads, the same order the Makefile's
    checkpoint_inputs hashed, so no checkpointed state's signature changes."""
    adir = f"tools/tests/checkpoints/{key}"
    payloads = sorted(p.name for p in (root / adir).glob("*.sram"))
    return [f"{adir}/manifest.json"] + [f"{adir}/{p}" for p in payloads]


def validate(states, root):
    """Every error is fatal and named; a malformed entry must never emit as
    some other kind of edge, which is the quiet-no-op class this design
    prevents."""
    errors = []
    seen = set()

    def err(entry, msg):
        errors.append(f"{entry.get('state', '<unnamed>')}: {msg}")

    for e in states:
        unknown = set(e) - FIELDS
        if unknown:
            err(e, f"unknown field(s) {sorted(unknown)}")
            continue
        s = e.get("state")
        if not (isinstance(s, str) and NAME_RE.match(s)):
            err(e, f"bad state name {s!r}")
            continue
        if s in seen:
            err(e, "duplicate state")
            continue
        gen, seed = e.get("gen"), e.get("seed")
        prev, checkpoint, after = e.get("prev"), e.get("checkpoint"), e.get("after")
        if bool(gen) == bool(seed):
            err(e, "exactly one of gen= or seed= is required")
        if seed:
            for k in ("prev", "checkpoint", "stack", "after"):
                if e.get(k):
                    err(e, f"seed= excludes {k}=")
            if seed not in seen:
                err(e, f"seed source {seed!r} is not an earlier state")
        if gen and not (root / "tools/tests" / f"{gen}.lua").is_file():
            err(e, f"no such generator tools/tests/{gen}.lua")
        if sum(map(bool, (prev, checkpoint, after))) > 1:
            err(e, "prev=, checkpoint= and after= are mutually exclusive")
        if prev and prev not in seen:
            err(e, f"prev {prev!r} is not an earlier state")
        if after and after not in seen:
            err(e, f"after {after!r} is not an earlier state")
        if checkpoint:
            # Dirs named negative-* are deliberately-wrong fixtures for
            # `make checkpoint-negatives`; no generated state may ever name one.
            if checkpoint.startswith("negative"):
                err(e, f"checkpoint {checkpoint!r} is a negative fixture")
            elif not (root / "tools/tests/checkpoints" / checkpoint /
                      "manifest.json").is_file():
                err(e, f"checkpoint {checkpoint!r} has no manifest.json")
            elif not checkpoint_inputs(root, checkpoint)[1:]:
                err(e, f"checkpoint {checkpoint!r} has no *.sram payload")
        # timeout=: run.sh's wall-clock cap for THIS edge only.  The default
        # is 600 s and it is not enough for every generator: the South Figaro
        # stop pushed gen_kolts past 80000 emulated frames, and the cap is
        # wall clock, so `nice` does not protect it and a loaded machine
        # turns a working generator into a timeout kill (trap 9).  Raising it
        # per edge is better than raising the global default, which would
        # also lengthen the time a genuinely hung run takes to report.
        timeout = e.get("timeout")
        if timeout is not None and not (isinstance(timeout, int)
                                        and 60 <= timeout <= 7200):
            err(e, f"timeout {timeout!r} must be an int between 60 and 7200")
        if timeout is not None and not gen:
            err(e, "timeout= requires gen=")
        stack = e.get("stack")
        if stack and not STACK_RE.match(stack):
            err(e, f"stack prefix {stack!r} must end in '_'")
        if stack and not gen:
            err(e, "stack= requires gen=")
        seen.add(s)
    return errors


def latch(rel):
    return f"{LATCH_DIR}/{rel}"


def emit_state_rules(w):
    """The generate and seed rule definitions, shared by standalone emission
    and the root configure.py's embedded emission (which owns the latch and
    regen rules itself, so they are not here)."""
    w("# One generate: run.sh composes the generator with the lib halves, boots")
    w("# Mesen, and publishes $state.mss + $state.mss.lua atomically into")
    w("# build/states -- OT6_EXPECT_ARTIFACT makes a run that passes without")
    w("# emitting BOTH a hard failure.  The stamp write is provenance for")
    w("# compose.py's consume-time drift check, not scheduling: it records")
    w("# the generator sig, the artifact's hash, and (via $ancestor -- the")
    w("# predecessor's stamp for prev= edges, the checkpoint manifest for")
    w("# checkpoint= edges, '-' for a power-on root) the hash of the stamp this")
    w("# state grew from, so the whole chain verifies transitively (#75).")
    w("# NB: $env and $extras are optional per-edge splices; ninja strips a")
    w("# value's leading whitespace, so the separating spaces live HERE in")
    w("# the template (an empty splice leaves a harmless double space).")
    w("rule generate")
    w("  command = OT6_WORKER=$state OT6_EXPECT_ARTIFACT='$state.mss "
      "$state.mss.lua' $env tools/tests/run.sh tools/tests/$gen.lua && "
      "sh tools/tests/lib/savestate_stamp.sh write $state $gen $ancestor "
      "$extras")
    w("  description = generate $state <- $gen")
    w("")
    w("# A stacked chain's boot is a finished chain's ending: a pure copy of")
    w("# both halves AND the stamp.  No generator, no emulator.  The stamp")
    w("# copy is correct by construction: the seed's bytes ARE the source's")
    w("# bytes, so the source's stamp -- its sig, its artifact hash, its")
    w("# ancestor -- vouches for the copy verbatim, and the copied stamp is")
    w("# what lets a stacked generate edge bind ITS ancestor line to a real file (#75).")
    w("rule seed")
    w("  command = cp build/states/$src.mss build/states/$state.mss && "
      "cp build/states/$src.mss.lua build/states/$state.mss.lua && "
      "cp build/states/$src.stamp build/states/$state.stamp")
    w("  description = stack seed $state <- $src")
    w("")


def emit_state_edges(w, states, root, latch_of):
    """The per-state build statements.  latch_of(path) -> the dependency path
    to use for a latched source; the caller owns emitting the latch edges
    themselves (so a source shared with other parts of a larger graph is
    latched exactly once)."""
    for e in states:
        s = e["state"]
        outs = (f"build/states/{s}.mss.lua build/states/{s}.mss")
        if e.get("seed"):
            src = e["seed"]
            w(f"build {outs} build/states/{s}.stamp: seed "
              f"build/states/{src}.mss.lua build/states/{src}.mss "
              f"build/states/{src}.stamp")
            w(f"  state = {s}")
            w(f"  src = {src}")
            continue
        gen = e["gen"]
        deps = [latch_of(ROM), latch_of(f"tools/tests/{gen}.lua")]
        deps += [latch_of(h) for h in LIB_HALVES]
        # Wall-clock default for generation edges: 1800 s rather than run.sh's
        # 600 s, because bare `ninja` fans every runnable generator out at
        # once and equally-niced emulators stretch each other's wall clock --
        # the longest edge measured 631 s UNCONTENDED (v0.15 ledger), which
        # left the old default one scheduler hiccup from a spurious kill.
        # The cap detects hangs; it never slows a green run.  A per-edge
        # timeout= larger than this still wins below.
        env = [] if e.get("timeout") else ["OT6_TIMEOUT=1800"]
        extras = ""
        explicit = ""
        order = ""
        # The provenance ancestor (issue #75): what savestate_stamp.sh write
        # hashes into the stamp's `ancestor` line.  Exactly one of prev= /
        # checkpoint= can be set (validate() enforces it); a state with neither
        # is a power-on root and records no ancestor.
        ancestor = "-"
        if e.get("prev"):
            p = e["prev"]
            explicit = (f" build/states/{p}.mss.lua build/states/{p}.mss"
                        f" build/states/{p}.stamp")
            ancestor = f"build/states/{p}.stamp"
        if e.get("checkpoint"):
            key = e["checkpoint"]
            ins = checkpoint_inputs(root, key)
            deps += [latch_of(a) for a in ins]
            env.append(f"OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/{key}")
            extras = " ".join(ins)
            ancestor = f"tools/tests/checkpoints/{key}/manifest.json"
        if e.get("stack"):
            env.append(f"OT6_STACK={e['stack']}")
        if e.get("timeout"):
            env.append(f"OT6_TIMEOUT={e['timeout']}")
        if e.get("after"):
            order = f" || build/states/{e['after']}.mss.lua"
        w(f"build {outs} build/states/{s}.stamp: generate{explicit} | "
          f"{' '.join(deps)}{order}")
        w(f"  state = {s}")
        w(f"  gen = {gen}")
        w(f"  ancestor = {ancestor}")
        if env:
            w(f"  env = {' '.join(env)}")
        if extras:
            w(f"  extras = {extras}")
    w("")


def latched_sources(states, root):
    """Every source path the state edges route through a latch, in first-use
    order: the ROM, the lib halves, each generator, each checkpoint input."""
    out = [ROM] + list(LIB_HALVES)
    for e in states:
        if e.get("gen"):
            g = f"tools/tests/{e['gen']}.lua"
            if g not in out:
                out.append(g)
        if e.get("checkpoint"):
            for a in checkpoint_inputs(root, e["checkpoint"]):
                if a not in out:
                    out.append(a)
    return out


def emit(states, root):
    """Standalone build/build.ninja text (the mock-tree selftests use this;
    the real tree's graph is emitted by configure.py, which embeds
    emit_state_rules/emit_state_edges into the whole-project file)."""
    o = []
    w = o.append
    w(f"# AUTOGENERATED by {SELF} from {GRAPH} -- do not edit.")
    w("# The real tree's graph is ./build.ninja (see configure.py); this")
    w("# standalone form exists for the mock-tree selftests.  Invoke from")
    w("# the repo root:")
    w(f"#     ninja -f {OUT} build/states/<state>.mss.lua")
    w("ninja_required_version = 1.3")
    w("builddir = build/ninja")
    w("")
    w("rule regen")
    w(f"  command = python3 {SELF}")
    w("  description = regen $out")
    w("  generator = 1")
    w("  restat = 1")
    w("")
    w("# Content latch: re-runs on any mtime bump, rewrites only on a byte")
    w("# change; restat = 1 prunes everything downstream when it did not.")
    w("rule latch")
    w("  command = mkdir -p $$(dirname $out) && { cmp -s $in $out || cp $in $out; }")
    w("  description = latch $in")
    w("  restat = 1")
    w("")
    emit_state_rules(w)
    w(f"build {OUT}: regen {SELF} {GRAPH}")
    w("")
    for src in latched_sources(states, root):
        w(f"build {latch(src)}: latch {src}")
    w("")
    emit_state_edges(w, states, root, latch)
    sidecars = " ".join(f"build/states/{e['state']}.mss.lua" for e in states)
    w(f"build savestates: phony {sidecars}")
    w("default savestates")
    w("")
    return "\n".join(o)


def load(root):
    ns = runpy.run_path(str(root / GRAPH))
    return ns["STATES"]


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", type=Path, default=ROOT,
                    help="tree to read the graph from and write into "
                         "(the selftest harness points this at a mock tree)")
    ap.add_argument("--list", action="store_true",
                    help="print state names in play order and exit")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args(argv)
    if args.selftest:
        return selftest()

    root = args.root.resolve()
    states = load(root)
    errors = validate(states, root)
    if errors:
        for e in errors:
            print(f"savestate_graph: {e}", file=sys.stderr)
        return 1
    if args.list:
        for e in states:
            print(e["state"])
        return 0
    text = emit(states, root)
    out = root / OUT
    out.parent.mkdir(parents=True, exist_ok=True)
    if out.exists() and out.read_text() == text:
        return 0
    out.write_text(text)
    print(f"wrote {out} ({len(states)} states)")
    return 0


def selftest():
    """Validation negatives: every malformed-entry class is a refusal, never
    a differently-shaped edge.  Pure python; the ninja-semantics proofs are
    in savestate_ninja_selftest.sh."""
    ok = True

    def check(label, cond):
        nonlocal ok
        print(f"  {'pass' if cond else 'FAIL'} {label}")
        ok = ok and cond

    import tempfile
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        (root / "tools/tests/checkpoints/good-v1").mkdir(parents=True)
        (root / "tools/tests/checkpoints/good-v1/manifest.json").write_text("{}")
        (root / "tools/tests/checkpoints/good-v1/a.sram").write_text("x")
        (root / "tools/tests/checkpoints/empty-v1").mkdir(parents=True)
        (root / "tools/tests/checkpoints/empty-v1/manifest.json").write_text("{}")
        (root / "tools/tests/gen_ok.lua").write_text("-- ok")

        def s(**kw):
            e = {"state": None, "gen": None, "prev": None, "checkpoint": None,
                 "seed": None, "stack": None, "after": None}
            e.update(kw)
            return e

        good = [s(state="a", gen="gen_ok"),
                s(state="b", gen="gen_ok", prev="a"),
                s(state="c", gen="gen_ok", checkpoint="good-v1"),
                s(state="d", seed="b"),
                s(state="e", gen="gen_ok", prev="d", stack="t9_")]
        check("well-formed graph validates", validate(good, root) == [])
        bad = [
            ("duplicate state", [s(state="a", gen="gen_ok")] * 2),
            ("gen and seed together",
             [s(state="a", gen="gen_ok", seed="a")]),
            ("neither gen nor seed", [s(state="a")]),
            ("unknown generator", [s(state="a", gen="gen_missing")]),
            ("prev not earlier",
             [s(state="a", gen="gen_ok", prev="zzz")]),
            ("prev+checkpoint together",
             [s(state="a", gen="gen_ok"),
              s(state="b", gen="gen_ok", prev="a", checkpoint="good-v1")]),
            ("negative-* checkpoint refused",
             [s(state="a", gen="gen_ok", checkpoint="negative-x")]),
            ("checkpoint without manifest",
             [s(state="a", gen="gen_ok", checkpoint="nonexistent-v1")]),
            ("checkpoint without payload",
             [s(state="a", gen="gen_ok", checkpoint="empty-v1")]),
            ("stack without trailing underscore",
             [s(state="a", gen="gen_ok", stack="t9")]),
            ("seed of a later state", [s(state="a", seed="b"),
                                       s(state="b", gen="gen_ok")]),
            ("unknown field",
             [dict(s(state="a", gen="gen_ok"), checkpointt="oops")]),
            ("bad state name", [s(state="a/b", gen="gen_ok")]),
        ]
        for label, graph in bad:
            check(label, validate(graph, root) != [])

        # the emitted text contains the pieces the build depends on
        text = emit(good, root)
        check("latch rule is restat", "rule latch" in text and
              text.split("rule latch")[1].split("rule ")[0].count(
                  "restat = 1") == 1)
        check("every generate edge depends on all three lib halves",
              all(f"{LATCH_DIR}/{h}" in line
                  for line in text.splitlines() if ": generate" in line
                  for h in LIB_HALVES))
        check("checkpointed generate edge hashes manifest before payload",
              "extras = tools/tests/checkpoints/good-v1/manifest.json "
              "tools/tests/checkpoints/good-v1/a.sram" in text)
        check("checkpointed generate edge exports OT6_SRAM_CHECKPOINT",
              "OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/good-v1" in text)
        check("stacked generate edge exports OT6_STACK", "OT6_STACK=t9_" in text)
        check("seed consumes both halves of its source AND its stamp (#75)",
              "seed build/states/b.mss.lua build/states/b.mss "
              "build/states/b.stamp" in text)
        check("seed copies the stamp with the state (#75)",
              "cp build/states/$src.stamp build/states/$state.stamp" in text)
        # provenance ancestors (#75): what each edge tells savestate_stamp.sh
        # to hash into its `ancestor` line.
        check("generate rule threads $ancestor to savestate_stamp.sh",
              "savestate_stamp.sh write $state $gen $ancestor" in text)
        check("root generate edge records no ancestor", "ancestor = -" in text)
        check("chained generate edge binds its predecessor's stamp",
              "ancestor = build/states/a.stamp" in text)
        check("chained generate edge consumes its predecessor's stamp",
              any("build/states/a.stamp" in line
                  for line in text.splitlines()
                  if line.startswith("build build/states/b.")))
        check("checkpointed generate edge binds the checkpoint manifest",
              "ancestor = tools/tests/checkpoints/good-v1/manifest.json" in text)
        check("stacked generate edge binds the seed copy's stamp",
              "ancestor = build/states/d.stamp" in text)
    print("savestate_ninja selftest:", "ok" if ok else "FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
