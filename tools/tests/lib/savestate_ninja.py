#!/usr/bin/env python3
"""savestate_ninja.py -- emit the savestate graph
(tools/tests/savestate_graph.py) as build/build.ninja.

Every compatibility input to a generated state (the ROM, the generator
.lua, checkpoint manifests and payloads) is routed through a copy_if_changed
edge:

    build build/ninja/src/<path>: copy_if_changed <path>   (cmp -s || cp; restat=1)

The copy re-runs on any mtime bump, rewrites its output only when bytes
differ, and `restat = 1` prunes everything downstream when it did not move.
A generator is copied by `copy_if_lua_changed` instead (lua_fingerprint.py
copy-if-changed): the copy takes the new bytes but keeps its mtime when the
Lua token stream did not move, so a comment or whitespace edit regenerates
nothing, the same rule the stamps' generator hash follows (#247).
Generated states themselves are not copied this way: a regenerated .mss is
new bytes, and everything booted from it must replay.

Not a dependency of a generate edge (so a harness edit never invalidates a
generated state): the three composed-in lib halves (ot6.lua, ot6_field.lua,
ot6_contract.lua), run.sh, compose.py, decode_b64.py, pin_test_saves.py,
sram_checkpoint.py, ff6-en.dbg.  docs/TESTING.md: a change to logging,
assertions, or controller policy does not by itself make a legitimately
reached snapshot illegitimate; changed ROM code/layout can.  The lib halves
are still copy_if_changed inputs of every suite test, audit and selftest edge
(configure.py), so a lib edit re-runs what asserts, not what was played.

Each state-generating edge `write`s build/states/<state>.stamp after
success (savestate_stamp.sh: ROM identity, the generator's own sig, the
provenance sig over gen+lib halves, artifact and ancestor bindings);
lib/compose.py re-derives those at embed time to catch a fixture that
reached a test without passing any freshness check, and reports a moved lib
half as provenance drift rather than staleness -- the same rule this graph
schedules by.

A cut (prev= with checkpoint=) boots the tracked checkpoint here; the
chain from power-on (chain_plan, emit_chain_edges) keeps the prev= path as
chain_<state> copies, built by `ninja chain`.

Usage:
    python3 tools/tests/lib/savestate_ninja.py             # (re)write build/build.ninja
    python3 tools/tests/lib/savestate_ninja.py --list      # state names, play order
    python3 tools/tests/lib/savestate_ninja.py --selftest  # validation negatives

The write is compare-and-conditionally-write, so an unchanged graph leaves
build/build.ninja's mtime alone.  Emitted paths are relative to the repo
root: run ninja from the root.
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
COPY_IF_CHANGED_DIR = "build/ninja/src"
# The three lib halves compose.py inlines into every composed generator, in
# inline order.  They are provenance (the stamp records their hashes), not
# scheduling inputs of a generate edge: a lib edit re-runs the suite tests,
# audits and selftests that assert on fixtures (configure.py routes them through copy_if_changed
# there), never the play that produced a fixture.
LIB_HALVES = (
    "tools/tests/lib/ot6.lua",
    "tools/tests/lib/ot6_field.lua",
    "tools/tests/lib/ot6_contract.lua",
)

NAME_RE = re.compile(r"^[A-Za-z0-9_]+$")
STACK_RE = re.compile(r"^[A-Za-z0-9]+_$")
FIELDS = {"state", "gen", "prev", "checkpoint", "seed", "stack", "after",
          "timeout", "also"}


def checkpoint_inputs(root, key):
    """Manifest first, then sorted payloads."""
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
        # prev= and checkpoint= together are a cut: qualification boots the
        # tracked checkpoint, and the power-on chain (chain_plan) boots the
        # save prev's own run made there.  after= orders a power-on root
        # and excludes both.
        if after and (prev or checkpoint):
            err(e, "after= excludes prev= and checkpoint=")
        if prev and checkpoint and e.get("stack"):
            err(e, "a cut (prev= with checkpoint=) cannot also be stack=")
        if prev and prev not in seen:
            err(e, f"prev {prev!r} is not an earlier state")
        if after and after not in seen:
            err(e, f"after {after!r} is not an earlier state")
        if checkpoint:
            # Dirs named negative-* are deliberately-wrong fixtures; no
            # generated state may ever name one.
            if checkpoint.startswith("negative"):
                err(e, f"checkpoint {checkpoint!r} is a negative fixture")
            elif not (root / "tools/tests/checkpoints" / checkpoint /
                      "manifest.json").is_file():
                err(e, f"checkpoint {checkpoint!r} has no manifest.json")
            elif not checkpoint_inputs(root, checkpoint)[1:]:
                err(e, f"checkpoint {checkpoint!r} has no *.sram payload")
        # timeout=: run.sh's wall-clock cap for THIS edge only (default 600 s).
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
        # also=: further artifacts the SAME generator run publishes.  One
        # edge, one play-through, several states -- the replacement for the
        # old one-edge-one-artifact splits that replayed a whole route once
        # per artifact.
        also = e.get("also")
        if also is not None:
            if not gen:
                err(e, "also= requires gen=")
            elif not (isinstance(also, list) and also
                      and all(isinstance(a, str) and NAME_RE.match(a)
                              for a in also)):
                err(e, f"also {also!r} must be a nonempty list of names")
            else:
                for a in also:
                    if a == s or a in seen or also.count(a) > 1:
                        err(e, f"also name {a!r} duplicates a state")
        seen.add(s)
        for a in (e.get("also") or []):
            seen.add(a)
    # A cut's producer run saves once, so it can stand for one checkpoint,
    # and the power-on chain captures that checkpoint's one payload.
    owner = _owners(states)
    made = {}
    for e in states:
        if not (e.get("prev") and e.get("checkpoint")):
            continue
        key = e["checkpoint"]
        if len(checkpoint_inputs(root, key)) != 2:
            err(e, f"a cut's checkpoint {key!r} must hold exactly one *.sram")
        p = owner.get(e["prev"])
        if p is not None and made.setdefault(p, key) != key:
            err(e, f"{p}'s run already saves checkpoint {made[p]!r}; "
                   f"one run cannot also stand for {key!r}")
    return errors


def _owners(states):
    """name -> the entry name whose run publishes it (itself, or the state
    an also= sibling rides with)."""
    owner = {}
    for e in states:
        owner[e["state"]] = e["state"]
        for a in (e.get("also") or []):
            owner[a] = e["state"]
    return owner


def copy_if_changed_from(rel):
    return f"{COPY_IF_CHANGED_DIR}/{rel}"


def emit_state_rules(w):
    """The generate and seed rule definitions, shared by standalone emission
    and the root configure.py's embedded emission (which owns the copy_if_changed
    and regen rules itself, so they are not here)."""
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
    # Per-state logs (build/states/$state.log), not the shared last_run.log:
    # the audits (audit_fenix's boss-vs-random rows, the unknown-menu TODO
    # queue, party-cure firings) read per-segment logs, and one overwritten
    # file keeps only the last edge of a wave.
    w("  command = OT6_WORKER=$state OT6_EXPECT_ARTIFACT='$expect' $env "
      "tools/tests/run.sh tools/tests/$gen.lua build/states/$state.log "
      "&& $stamps")
    w("  description = generate $state <- $gen")
    w("")
    w("# A stacked chain's boot is a finished chain's ending: a pure copy of")
    w("# both halves AND the stamp.  No generator, no emulator.  The stamp")
    w("# copy is correct by construction: the seed's bytes ARE the source's")
    w("# bytes, so the source's stamp -- its sig, its artifact hash, its")
    w("# ancestor -- records the copy verbatim, and the copied stamp is")
    w("# what lets a stacked generate edge bind ITS ancestor line to a real file (#75).")
    w("rule seed")
    w("  command = cp build/states/$src.mss build/states/$state.mss && "
      "cp build/states/$src.mss.lua build/states/$state.mss.lua && "
      "cp build/states/$src.stamp build/states/$state.stamp")
    w("  description = stack seed $state <- $src")
    w("")
    w("# A generator's copy: the new bytes always land, but the old mtime is")
    w("# kept when the Lua token stream (comments and whitespace dropped) did")
    w("# not move, so restat prunes a comment-only edit (#247).")
    w("rule copy_if_lua_changed")
    w("  command = python3 tools/tests/lib/lua_fingerprint.py "
      "copy-if-changed $in $out")
    w("  description = copy_if_lua_changed $in")
    w("  restat = 1")
    w("")


def emit_state_edges(w, states, root, copy_if_changed_from):
    """The per-state build statements.  copy_if_changed_from(path) -> the dependency path
    to use for a copied source; the caller owns emitting the copy_if_changed
    edges themselves (so a source shared with other parts of a larger graph
    is copied exactly once)."""
    for e in states:
        s = e["state"]
        names = [s] + list(e.get("also") or [])
        outs = " ".join(f"build/states/{n}.mss.lua build/states/{n}.mss"
                        for n in names)
        if e.get("seed"):
            src = e["seed"]
            w(f"build {outs} build/states/{s}.stamp: seed "
              f"build/states/{src}.mss.lua build/states/{src}.mss "
              f"build/states/{src}.stamp")
            w(f"  state = {s}")
            w(f"  src = {src}")
            continue
        gen = e["gen"]
        # Compatibility inputs only: the ROM and this state's own generator
        # (plus its checkpoint inputs below).  The lib halves are deliberately
        # absent -- see the module header.
        deps = [copy_if_changed_from(ROM), copy_if_changed_from(f"tools/tests/{gen}.lua")]
        # Wall-clock default for generation edges: 1800 s rather than run.sh's
        # 600 s, because bare `ninja` fans every runnable generator out at
        # once and equally-niced emulators stretch each other's wall clock.
        # A per-edge timeout= larger than this still wins below.
        env = [] if e.get("timeout") else ["OT6_TIMEOUT=1800"]
        extras = ""
        explicit = ""
        order = ""
        # The provenance ancestor: what savestate_stamp.sh write hashes into
        # the stamp's `ancestor` line.  Exactly one of prev= / checkpoint=
        # can be set (validate() enforces it); a state with neither is a
        # power-on root and records no ancestor.
        ancestor = "-"
        if e.get("prev") and not e.get("checkpoint"):
            p = e["prev"]
            explicit = (f" build/states/{p}.mss.lua build/states/{p}.mss"
                        f" build/states/{p}.stamp")
            ancestor = f"build/states/{p}.stamp"
        if e.get("checkpoint"):
            key = e["checkpoint"]
            ins = checkpoint_inputs(root, key)
            deps += [copy_if_changed_from(a) for a in ins]
            env.append(f"OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/{key}")
            extras = " ".join(ins)
            ancestor = f"tools/tests/checkpoints/{key}/manifest.json"
        if e.get("stack"):
            env.append(f"OT6_STACK={e['stack']}")
        if e.get("timeout"):
            env.append(f"OT6_TIMEOUT={e['timeout']}")
        if e.get("after"):
            order = f" || build/states/{e['after']}.mss.lua"
        stamp_outs = " ".join(f"build/states/{n}.stamp" for n in names)
        expect = " ".join(f"{n}.mss {n}.mss.lua" for n in names)
        # one stamp per artifact, ancestry chained through the shared run:
        # the first binds the external ancestor, each later artifact binds
        # its predecessor's stamp from the same play-through
        stamp_cmds, anc = [], ancestor
        for n in names:
            cmd = f"sh tools/tests/lib/savestate_stamp.sh write {n} {gen} {anc}"
            if extras:
                cmd += f" {extras}"
            stamp_cmds.append(cmd)
            anc = f"build/states/{n}.stamp"
        w(f"build {outs} {stamp_outs}: generate{explicit} | "
          f"{' '.join(deps)}{order}")
        w(f"  state = {s}")
        w(f"  gen = {gen}")
        w(f"  expect = {expect}")
        w(f"  stamps = {' && '.join(stamp_cmds)}")
        if env:
            w(f"  env = {' '.join(env)}")
    w("")


# ------------------------------------------------ the chain from power-on --
# A cut (prev= with checkpoint=) lets qualification boot a leg from its
# tracked checkpoint, so the legs regenerate at once.  The chain from
# power-on is kept as its own copy of the states: chain_<state>, each
# generated by the same generator under OT6_STACK=chain_ (compose.py
# prefixes every .mss name the script boots or emits), booted from the
# previous chain_ state.  At a cut, the producer's copy captures the save
# its run made (OT6_CAPTURE_SRM) into build/checkpoints/<key>/, sealed with
# the tracked manifest, and the consumer's copy Continues that save instead
# of the tracked one.  Nothing in qualification depends on the copies;
# `ninja chain` builds them (configure.py).
CHAIN_PREFIX = "chain_"
CAPTURE_DIR = "build/checkpoints"


def chain_plan(states):
    """The chain from power-on, or None when the graph has no cut.

    Returns (entries, seeds, end): the graph entries that get a chain_
    copy, in play order; the states copied (seed rule) into chain_ names
    because the first copied run boots them; and the last state of the
    chain.  The chain is the prev= ancestry of the last state in play
    order whose ancestry, cuts joined, holds a cut and reaches a power-on
    root; the copies start at the first cut's producer (everything before
    it plays the same way in both graphs)."""
    by = {e["state"]: e for e in states}
    owner = _owners(states)
    cuts = [e for e in states if e.get("prev") and e.get("checkpoint")]
    if not cuts:
        return None
    producers = {owner[e["prev"]] for e in cuts}

    def ancestry(name):
        line = []
        e = by[name]
        while True:
            line.append(e["state"])
            if not e.get("prev"):
                break
            e = by[owner[e["prev"]]]
        line.reverse()
        return line, not e.get("checkpoint") and not e.get("seed")

    end, line = None, None
    for e in reversed(states):
        cand, poweron = ancestry(e["state"])
        if poweron and any(by[n].get("checkpoint") for n in cand):
            end, line = e["state"], cand
            break
    if end is None:
        return None
    first = next(i for i, n in enumerate(line) if n in producers)
    entries = [by[n] for n in line[first:]]
    seeds = []
    head = entries[0]
    if head.get("prev"):
        seeds.append(head["prev"])
    return entries, seeds, end


def emit_chain_edges(w, states, root, copy_if_changed_from):
    """The chain_ copies (see chain_plan).  Returns the chain's last
    output path, or None when there is no cut."""
    plan = chain_plan(states)
    if plan is None:
        return None
    entries, seeds, end = plan
    owner = _owners(states)
    # the producer entry whose run saves each cut's checkpoint
    saves = {owner[e["prev"]]: e["checkpoint"]
             for e in states if e.get("prev") and e.get("checkpoint")}
    P = CHAIN_PREFIX
    w("# The chain from power-on (savestate_ninja.py chain_plan): chain_<state>")
    w("# copies, each booted from the previous copy, and at a cut from the save")
    w("# the producer's copy captured.  Not qualification: `ninja chain`.")
    w("rule generate_capture")
    w("  command = OT6_WORKER=$state OT6_EXPECT_ARTIFACT='$expect' $env "
      "tools/tests/run.sh tools/tests/$gen.lua build/states/$state.log "
      "&& $stamps && $seal")
    w("  description = generate $state <- $gen (captures $key)")
    w("")
    for s in seeds:
        w(f"build build/states/{P}{s}.mss.lua build/states/{P}{s}.mss "
          f"build/states/{P}{s}.stamp: seed build/states/{s}.mss.lua "
          f"build/states/{s}.mss build/states/{s}.stamp")
        w(f"  state = {P}{s}")
        w(f"  src = {s}")
    for e in entries:
        gen, s = e["gen"], e["state"]
        names = [P + n for n in [s] + list(e.get("also") or [])]
        outs = " ".join(f"build/states/{n}.mss.lua build/states/{n}.mss"
                        for n in names)
        deps = [copy_if_changed_from(ROM),
                copy_if_changed_from(f"tools/tests/{gen}.lua")]
        env = [f"OT6_STACK={P}",
               f"OT6_TIMEOUT={e.get('timeout') or 1800}"]
        explicit, extras = "", ""
        if e.get("prev") and e.get("checkpoint"):
            key = e["checkpoint"]
            ins = [f"{CAPTURE_DIR}/{key}/{Path(a).name}"
                   for a in checkpoint_inputs(root, key)]
            explicit = " " + " ".join(ins)
            env.append(f"OT6_SRAM_CHECKPOINT={CAPTURE_DIR}/{key}")
            extras = " ".join(ins)
            ancestor = ins[0]
        elif e.get("prev"):
            p = P + e["prev"]
            explicit = (f" build/states/{p}.mss.lua build/states/{p}.mss"
                        f" build/states/{p}.stamp")
            ancestor = f"build/states/{p}.stamp"
        else:
            ancestor = "-"
        stamp_cmds, anc = [], ancestor
        for n in names:
            cmd = f"sh tools/tests/lib/savestate_stamp.sh write {n} {gen} {anc}"
            if extras:
                cmd += f" {extras}"
            stamp_cmds.append(cmd)
            anc = f"build/states/{n}.stamp"
        stamp_outs = " ".join(f"build/states/{n}.stamp" for n in names)
        rule, capture_outs, seal = "generate", "", ""
        key = saves.get(s)
        if key:
            tracked = checkpoint_inputs(root, key)
            payload = Path(tracked[1]).name
            cdir = f"{CAPTURE_DIR}/{key}"
            rule = "generate_capture"
            env.append(f"OT6_CAPTURE_SRM={cdir}/{payload}")
            capture_outs = (f" {cdir}/manifest.json {cdir}/{payload}"
                            f" {cdir}/{payload}.provenance.json")
            deps.append(copy_if_changed_from(tracked[0]))
            # the tracked manifest's authored fields (its `saved` above
            # all) judge the capture; seal refuses a battery holding
            # another save
            seal = (f"cp {tracked[0]} {cdir}/manifest.json && "
                    f"python3 tools/tests/lib/sram_checkpoint.py seal {cdir} && "
                    f"python3 tools/tests/lib/sram_checkpoint.py validate {cdir}")
        w(f"build {outs} {stamp_outs}{capture_outs}: {rule}{explicit} | "
          f"{' '.join(deps)}")
        w(f"  state = {names[0]}")
        w(f"  gen = {gen}")
        w(f"  expect = {' '.join(f'{n}.mss {n}.mss.lua' for n in names)}")
        w(f"  stamps = {' && '.join(stamp_cmds)}")
        w(f"  env = {' '.join(env)}")
        if seal:
            w(f"  seal = {seal}")
            w(f"  key = {key}")
    w("")
    return f"build/states/{P}{end}.mss.lua"


def copy_rule(src, states):
    """The copy rule for one copy_if_changed source: a generator the graph
    runs is copied by its Lua token stream, anything else by its bytes."""
    gens = {f"tools/tests/{e['gen']}.lua" for e in states if e.get("gen")}
    return "copy_if_lua_changed" if src in gens else "copy_if_changed"


def copy_if_changed_sources(states, root):
    """Every source path the state edges route through a copy_if_changed
    edge, in first-use order: the ROM, each generator, each checkpoint input."""
    out = [ROM]
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
    w("# copy_if_changed: re-runs on any mtime bump, rewrites only on a byte")
    w("# change; restat = 1 prunes everything downstream when it did not.")
    w("rule copy_if_changed")
    w("  command = mkdir -p $$(dirname $out) && { cmp -s $in $out || cp $in $out; }")
    w("  description = copy_if_changed $in")
    w("  restat = 1")
    w("")
    emit_state_rules(w)
    w(f"build {OUT}: regen {SELF} {GRAPH}")
    w("")
    for src in copy_if_changed_sources(states, root):
        w(f"build {copy_if_changed_from(src)}: {copy_rule(src, states)} {src}")
    w("")
    emit_state_edges(w, states, root, copy_if_changed_from)
    end = emit_chain_edges(w, states, root, copy_if_changed_from)
    sidecars = " ".join(f"build/states/{e['state']}.mss.lua" for e in states)
    w(f"build savestates: phony {sidecars}")
    if end:
        w(f"build chain: phony {end}")
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
        (root / "tools/tests/checkpoints/two-v1").mkdir(parents=True)
        (root / "tools/tests/checkpoints/two-v1/manifest.json").write_text("{}")
        (root / "tools/tests/checkpoints/two-v1/b.sram").write_text("x")
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
                s(state="e", gen="gen_ok", prev="d", stack="t9_"),
                s(state="f", gen="gen_ok", prev="e", also=["g", "h"]),
                s(state="i", gen="gen_ok", prev="h")]
        check("well-formed graph validates", validate(good, root) == [])
        bad = [
            ("duplicate state", [s(state="a", gen="gen_ok")] * 2),
            ("gen and seed together",
             [s(state="a", gen="gen_ok", seed="a")]),
            ("neither gen nor seed", [s(state="a")]),
            ("unknown generator", [s(state="a", gen="gen_missing")]),
            ("prev not earlier",
             [s(state="a", gen="gen_ok", prev="zzz")]),
            ("after+prev together",
             [s(state="a", gen="gen_ok"),
              s(state="b", gen="gen_ok", prev="a", after="a")]),
            ("a cut that is also stacked",
             [s(state="a", gen="gen_ok"),
              s(state="b", gen="gen_ok", prev="a", checkpoint="good-v1",
                stack="t9_")]),
            ("one run standing for two checkpoints",
             [s(state="a", gen="gen_ok"),
              s(state="b", gen="gen_ok", prev="a", checkpoint="good-v1"),
              s(state="c", gen="gen_ok", prev="a", checkpoint="two-v1")]),
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
            ("also without gen",
             [s(state="a", gen="gen_ok"),
              s(state="b", seed="a", also=["x"])]),
            ("also duplicating a state",
             [s(state="a", gen="gen_ok"),
              s(state="b", gen="gen_ok", also=["a"])]),
            ("also duplicating itself",
             [s(state="a", gen="gen_ok", also=["x", "x"])]),
        ]
        for label, graph in bad:
            check(label, validate(graph, root) != [])

        # the emitted text contains the pieces the build depends on
        text = emit(good, root)
        check("copy_if_changed rule is restat", "rule copy_if_changed" in text and
              text.split("rule copy_if_changed")[1].split("rule ")[0].count(
                  "restat = 1") == 1)
        gen_lines = [l for l in text.splitlines() if ": generate" in l]
        check("every generate edge depends on the ROM and its own generator",
              gen_lines and all(f"{COPY_IF_CHANGED_DIR}/{ROM}" in line
                                and f"{COPY_IF_CHANGED_DIR}/tools/tests/gen_ok.lua" in line
                                for line in gen_lines))
        check("no generate edge depends on a lib half (docs/TESTING.md)",
              not any(f"{COPY_IF_CHANGED_DIR}/{h}" in line
                      for line in gen_lines for h in LIB_HALVES))
        check("no lib half is routed through copy_if_changed by the standalone graph at all",
              not any(h in text for h in LIB_HALVES))
        check("checkpointed generate edge hashes manifest before payload",
              "tools/tests/checkpoints/good-v1/manifest.json "
              "tools/tests/checkpoints/good-v1/a.sram" in text)
        check("checkpointed generate edge exports OT6_SRAM_CHECKPOINT",
              "OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/good-v1" in text)
        check("stacked generate edge exports OT6_STACK", "OT6_STACK=t9_" in text)
        check("seed consumes both halves of its source AND its stamp (#75)",
              "seed build/states/b.mss.lua build/states/b.mss "
              "build/states/b.stamp" in text)
        check("seed copies the stamp with the state (#75)",
              "cp build/states/$src.stamp build/states/$state.stamp" in text)
        # provenance ancestors: what each edge tells savestate_stamp.sh to
        # hash into its `ancestor` line.
        check("generate rule runs the per-edge stamp chain",
              "&& $stamps" in text)
        check("root generate edge records no ancestor",
              "write a gen_ok -" in text)
        check("chained generate edge binds its predecessor's stamp",
              "write b gen_ok build/states/a.stamp" in text)
        check("chained generate edge consumes its predecessor's stamp",
              any("build/states/a.stamp" in line
                  for line in text.splitlines()
                  if line.startswith("build build/states/b.")))
        check("checkpointed generate edge binds the checkpoint manifest",
              "write c gen_ok tools/tests/checkpoints/good-v1/manifest.json"
              in text)
        check("stacked generate edge binds the seed copy's stamp",
              "write e gen_ok build/states/d.stamp" in text)
        check("an also= run publishes every artifact from one edge",
              "build/states/f.mss.lua build/states/f.mss "
              "build/states/g.mss.lua build/states/g.mss "
              "build/states/h.mss.lua build/states/h.mss" in text
              and "expect = f.mss f.mss.lua g.mss g.mss.lua h.mss h.mss.lua"
              in text)
        check("also= artifacts chain their stamps through the shared run",
              "write g gen_ok build/states/f.stamp" in text
              and "write h gen_ok build/states/g.stamp" in text)
        check("a later edge may boot an also= artifact",
              any("build/states/h.mss" in line
                  for line in text.splitlines()
                  if line.startswith("build build/states/i.")))
        check("a graph without a cut has no chain copies",
              "chain_" not in text and "build chain:" not in text)

        # A cut: q boots good-v1 in qualification; its chain copy boots the
        # save p's copy captured.  r rides on q; x is a branch off r.
        cut = [s(state="o", gen="gen_ok"),
               s(state="p", gen="gen_ok", prev="o", also=["p2"]),
               s(state="q", gen="gen_ok", prev="p2", checkpoint="good-v1"),
               s(state="r", gen="gen_ok", prev="q"),
               s(state="x", gen="gen_ok", prev="o"),
               s(state="z", gen="gen_ok", checkpoint="two-v1")]
        check("a cut validates", validate(cut, root) == [])
        text = emit(cut, root)
        lines = text.splitlines()

        def edge(out):
            return next((l for l in lines if l.startswith(f"build {out}")), "")
        check("qualification boots the cut from its tracked checkpoint",
              "build/states/p2.mss" not in edge("build/states/q.mss.lua")
              and "OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/good-v1" in text)
        check("the chain seeds the first producer's boot",
              ": seed build/states/o.mss.lua" in edge("build/states/chain_o.mss.lua"))
        check("the producer's copy captures and seals the checkpoint",
              "build/checkpoints/good-v1/manifest.json" in edge("build/states/chain_p.mss.lua")
              and "OT6_CAPTURE_SRM=build/checkpoints/good-v1/a.sram" in text
              and "sram_checkpoint.py seal build/checkpoints/good-v1" in text)
        check("the consumer's copy Continues the captured save",
              "generate build/checkpoints/good-v1/manifest.json "
              "build/checkpoints/good-v1/a.sram" in edge("build/states/chain_q.mss.lua")
              and "OT6_SRAM_CHECKPOINT=build/checkpoints/good-v1" in text)
        check("a copy after the cut boots the copy before it",
              "build/states/chain_q.mss" in edge("build/states/chain_r.mss.lua"))
        check("branches and checkpoint-only roots get no copy",
              "chain_x" not in text and "chain_z" not in text)
        check("`chain` names the chain's last copy",
              "build chain: phony build/states/chain_r.mss.lua" in text)
        def body(i):
            out = []
            for l in lines[i + 1:]:
                if not l.startswith("  "):
                    break
                out.append(l)
            return "\n".join(out)
        copies = [i for i, l in enumerate(lines)
                  if l.startswith("build build/states/chain_") and ": generate" in l]
        check("every copy runs stacked", len(copies) == 3 and all(
            "OT6_STACK=chain_" in body(i) for i in copies))
    print("savestate_ninja selftest:", "ok" if ok else "FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
