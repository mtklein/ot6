#!/usr/bin/env python3
"""savestate_ninja.py -- emit the savestate graph
(tools/tests/savestate_graph.py) as ninja edges: one graph, played once
from power-on (#363).

Every state is generated once, from what it really boots:

  * a power-on root boots nothing;
  * a plain link boots its prev='s savestate;
  * a cut (prev= with checkpoint=) Continues the battery save the run
    before it made: the producer's run saves through the real Save UI,
    run.sh captures the battery (OT6_CAPTURE_SRM) into
    build/checkpoints/<key>/, and the capture is sealed against the
    tracked manifest's authored fields (its `saved` above all).  A cutter=
    is a capture-only script booted from prev's savestate that makes the
    save instead; saves= marks a run that saves a checkpoint no cut boots
    yet (the frontier).

So the play from power-on to the frontier is one line of runs, each booted
from the one before it, and nothing plays it twice: there is no second
copy of any state.  The tracked checkpoints in tools/tests/checkpoints/ are
not boot inputs of anything in the graph; they are the committed copies of
the captures, which checkpoint_drift.py compares (the release gate,
configure.py) and re-cuts.

Every compatibility input to a generated state (the ROM, the emulator pin
tools/mesen/EMULATOR, the generator .lua, the capture it Continues, and
tools/tests/replay.txt) is routed through a copy_if_changed edge:

    build build/ninja/src/<path>: copy_if_changed <path>   (cmp -s || cp; restat=1)

The copy re-runs on any mtime bump, rewrites its output only when bytes
differ, and `restat = 1` prunes everything downstream when it did not move.
A generator is copied by `copy_if_lua_changed` instead (lua_fingerprint.py
copy-if-changed): the copy takes the new bytes but keeps its mtime when the
Lua token stream did not move, so a comment or whitespace edit regenerates
nothing, the same rule the stamps' generator hash follows (#247).  The ROM
is copied by `copy_if_rom_identity_changed` (tools/build/rom_version.py): the
same shape, keyed on the ROM identity, the ROM with its version fields
masked, so a VERSION bump regenerates nothing, the same rule the stamps'
`rom` line follows.
Generated states themselves are not copied this way: a regenerated .mss is
new bytes, and everything booted from it must replay.

Not a dependency of a generate or capture edge (so a harness edit never
replays the game): the three composed-in lib halves (ot6.lua, ot6_field.lua,
ot6_contract.lua), run.sh, compose.py, decode_b64.py, pin_test_saves.py,
sram_checkpoint.py, ff6-en.dbg.  docs/TESTING.md: a change to logging,
assertions, or controller policy does not by itself make a legitimately
reached snapshot illegitimate; changed ROM code/layout can.  The stamps
record the lib halves a state was played with (provenance), and
compose.py --check-states reports a moved one as provenance drift.  The lib
halves are still copy_if_changed inputs of every suite test, audit and
selftest edge (configure.py), so a lib edit re-runs what asserts, not what
was played.  tools/tests/replay.txt is the lever for replaying anyway: every
generate and capture edge depends on it, so bumping its line replays the
whole game under today's library (a scheduled full replay).

Each state-generating edge `write`s build/states/<state>.stamp after
success (savestate_stamp.sh: ROM identity, the generator's own sig, the
provenance sig over gen+lib halves, artifact and ancestor bindings);
lib/compose.py re-derives those at embed time to catch a fixture that
reached a test without passing any freshness check, and reports a moved lib
half as provenance drift rather than staleness -- the same rule this graph
schedules by.

Usage:
    python3 tools/tests/lib/savestate_ninja.py             # (re)write build/build.ninja
    python3 tools/tests/lib/savestate_ninja.py --list      # state names, play order
    python3 tools/tests/lib/savestate_ninja.py --selftest  # validation negatives
    python3 tools/tests/lib/savestate_ninja.py --coverage [--booted KEY...]
        # every tracked checkpoint is captured by a run on the graph

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
# The emulator the fixtures are made with: the fork commit tools/mesen/build.sh
# builds (tools/mesen/README.md).  An input of every generate and capture
# edge, like the ROM: a machine snapshot is only as good as the emulator
# that played it, so changing the pin regenerates every state (and, through
# the captures, makes checkpoint_drift.py ask for a re-cut).
EMULATOR = "tools/mesen/EMULATOR"
# The scheduled-replay lever (#363): an input of every generate and capture
# edge and of nothing else, so bumping its line replays the whole game under
# today's library without touching the ROM.
REPLAY = "tools/tests/replay.txt"
COPY_IF_CHANGED_DIR = "build/ninja/src"
CAPTURE_DIR = "build/checkpoints"
# The three lib halves compose.py inlines into every composed generator, in
# inline order.  They are provenance (the stamp records their hashes), not
# scheduling inputs of a generate edge: a lib edit re-runs the suite tests,
# audits and selftests that assert on fixtures (configure.py routes them
# through copy_if_changed there), never the play that produced a fixture.
LIB_HALVES = (
    "tools/tests/lib/ot6.lua",
    "tools/tests/lib/ot6_field.lua",
    "tools/tests/lib/ot6_contract.lua",
)

NAME_RE = re.compile(r"^[A-Za-z0-9_]+$")
FIELDS = {"state", "gen", "prev", "checkpoint", "timeout", "also", "saves",
          "cutter"}
# The wall-clock cap of a cutter's capture run.  The longest cutter,
# gen_terra_returned_checkpoint, allows itself 160000 frames: ~2000 s at a
# loaded machine's ~80 frames/s.
CUTTER_TIMEOUT = 3600


def checkpoint_inputs(root, key):
    """The TRACKED checkpoint's files: manifest first, then sorted
    payloads."""
    adir = f"tools/tests/checkpoints/{key}"
    payloads = sorted(p.name for p in (root / adir).glob("*.sram"))
    return [f"{adir}/manifest.json"] + [f"{adir}/{p}" for p in payloads]


def capture_inputs(root, key):
    """The capture's files, as a run that Continues it reads them: the
    sealed manifest, then the payload (named as the tracked one is)."""
    return [f"{CAPTURE_DIR}/{key}/manifest.json"] + \
        [f"{CAPTURE_DIR}/{key}/{Path(p).name}"
         for p in checkpoint_inputs(root, key)[1:]]


def validate(states, root):
    """Every error is fatal and named; a malformed entry must never emit as
    some other kind of edge, which is the quiet-no-op class this design
    prevents."""
    errors = []
    seen = set()

    def err(entry, msg):
        errors.append(f"{entry.get('state', '<unnamed>')}: {msg}")

    for e in states:
        unknown = {k for k, v in e.items() if v is not None} - FIELDS
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
        gen, prev, checkpoint = e.get("gen"), e.get("prev"), e.get("checkpoint")
        if not gen:
            err(e, "gen= is required")
        elif not (root / "tools/tests" / f"{gen}.lua").is_file():
            err(e, f"no such generator tools/tests/{gen}.lua")
        if prev and prev not in seen:
            err(e, f"prev {prev!r} is not an earlier state")
        # A checkpoint is Continued from the save the run before it made,
        # so a boot from a checkpoint needs that run: prev= names it.
        if checkpoint and not prev:
            err(e, f"checkpoint {checkpoint!r} without prev=: no run on the "
                   f"graph makes that save; name the state whose play ends "
                   f"where it begins")
        for field in ("checkpoint", "saves"):
            key = e.get(field)
            if not key:
                continue
            # Dirs named negative-* are deliberately-wrong fixtures; no
            # generated state may ever name one.
            if key.startswith("negative"):
                err(e, f"{field} {key!r} is a negative fixture")
            elif not (root / "tools/tests/checkpoints" / key /
                      "manifest.json").is_file():
                err(e, f"{field} {key!r} has no manifest.json")
            elif not checkpoint_inputs(root, key)[1:]:
                err(e, f"{field} {key!r} has no *.sram payload")
        # cutter=: on a cut, the save is made by this capture-only script
        # booted from prev's savestate, not by prev's own run.
        cutter = e.get("cutter")
        if cutter:
            if not (prev and checkpoint):
                err(e, "cutter= is only for a cut (prev= with checkpoint=)")
            if not (root / "tools/tests" / f"{cutter}.lua").is_file():
                err(e, f"no such cutter tools/tests/{cutter}.lua")
        # timeout=: run.sh's wall-clock cap for THIS edge only (default 1800 s).
        timeout = e.get("timeout")
        if timeout is not None and not (isinstance(timeout, int)
                                        and 60 <= timeout <= 7200):
            err(e, f"timeout {timeout!r} must be an int between 60 and 7200")
        # also=: further artifacts the SAME generator run publishes.  One
        # edge, one play-through, several states.
        also = e.get("also")
        if also is not None:
            if not (isinstance(also, list) and also
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
    # A run saves once, so it can stand for one checkpoint, and the capture
    # holds that checkpoint's one payload; and one checkpoint is made by
    # one run.
    if not errors:
        for e, msg in _producer_conflicts(states):
            err(e, msg)
        for e in states:
            for key in {e.get("checkpoint"), e.get("saves")} - {None}:
                if len(checkpoint_inputs(root, key)) != 2:
                    err(e, f"a captured checkpoint {key!r} must hold exactly "
                           f"one *.sram")
    return errors


def _run_of(e, owner):
    """The run that saves a cut's checkpoint: ("run", entry) when prev's
    own run does, ("cutter", gen, prev) when a cutter= script does."""
    if e.get("cutter"):
        return ("cutter", e["cutter"], e["prev"])
    return ("run", owner[e["prev"]])


def _producer_conflicts(states):
    """(entry, message) for every run asked to stand for two checkpoints
    and every checkpoint asked to come from two runs."""
    owner = _owners(states)
    made, by_key, out = {}, {}, []
    for e in states:
        pairs = []
        if e.get("prev") and e.get("checkpoint"):
            pairs.append((_run_of(e, owner), e["checkpoint"]))
        if e.get("saves"):
            pairs.append((("run", e["state"]), e["saves"]))
        for run, key in pairs:
            name = run[1] if run[0] == "run" else f"{run[1]} (from {run[2]})"
            if made.setdefault(run, key) != key:
                out.append((e, f"{name}'s run already saves checkpoint "
                               f"{made[run]!r}; one run cannot also stand "
                               f"for {key!r}"))
            if by_key.setdefault(key, run) != run:
                other = by_key[key]
                oname = other[1] if other[0] == "run" else \
                    f"{other[1]} (from {other[2]})"
                out.append((e, f"checkpoint {key!r} is already made by "
                               f"{oname}'s run; {name} cannot make it too"))
    return out


def producers(states):
    """{checkpoint key: the run that saves it}, for every cut and saves=:
    ("run", entry) when that entry's own run saves it (its generate edge
    captures it), ("cutter", gen, prev) when a capture-only cutter booted
    from prev's savestate does (its own capture edge)."""
    owner = _owners(states)
    out = {}
    for e in states:
        if e.get("prev") and e.get("checkpoint"):
            out.setdefault(e["checkpoint"], _run_of(e, owner))
        if e.get("saves"):
            out.setdefault(e["saves"], ("run", e["state"]))
    return out


def _owners(states):
    """name -> the entry name whose run publishes it (itself, or the state
    an also= sibling rides with)."""
    owner = {}
    for e in states:
        owner[e["state"]] = e["state"]
        for a in (e.get("also") or []):
            owner[a] = e["state"]
    return owner


def capture_record(key, run):
    """The file that names the run that captured `key` (checkpoint_drift.py's
    freshness check): the producer's own stamp, or, for a cutter (which
    publishes no state), the record its capture edge writes."""
    if run[0] == "cutter":
        return f"{CAPTURE_DIR}/{key}.record"
    return f"build/states/{run[1]}.stamp"


def captures(states, root):
    """{checkpoint key: [the paths its capture is sealed into]} for every
    checkpoint a run on the graph saves (each cut's, each saves='s)."""
    out = {}
    for key, run in producers(states).items():
        out[key] = capture_inputs(root, key)
        if run[0] == "cutter":
            out[key].append(capture_record(key, run))
    return out


def line_end(states):
    """The last state of the play from power-on: the state with the longest
    prev= ancestry (cuts included, since a cut Continues its prev's save),
    the later one on a tie.  `ninja chain` names it."""
    by = {e["state"]: e for e in states}
    owner = _owners(states)
    depth = {}
    for e in states:
        p = e.get("prev")
        depth[e["state"]] = 1 + (depth[owner[p]] if p else 0)
    best = None
    for e in states:
        if best is None or depth[e["state"]] >= depth[best]:
            best = e["state"]
    return best if best in by else None


def line_runs(states):
    """The entries whose runs make up the play from power-on to line_end():
    its prev= ancestry, as the entry names that own each run.  Everything
    else (a branch, a suite) is side work beside it."""
    by = {e["state"]: e for e in states}
    owner = _owners(states)
    end = line_end(states)
    out = set()
    e = by.get(end)
    while e is not None:
        out.add(e["state"])
        p = e.get("prev")
        e = by[owner[p]] if p else None
    return out


def coverage(states, root, booted=(), not_gated=None):
    """Errors, one per tracked checkpoint the release gate would not check
    and per suite boot of a save no run makes: every
    tools/tests/checkpoints/<key>/ (negative-* fixtures aside) must be
    captured by a run on the graph (captures(), which checkpoint_drift.py
    --strict compares), or be named in NOT_GATED with its reason; a
    NOT_GATED one must be booted by nothing; and every key in `booted` (the
    suites' boots) must be captured, since a suite Continues the capture."""
    not_gated = dict(not_gated or {})
    captured = captures(states, root)
    tracked = sorted(p.parent.name for p in
                     (root / "tools/tests/checkpoints").glob("*/manifest.json")
                     if not p.parent.name.startswith("negative"))
    errors = []
    for key in sorted(set(booted)):
        if key not in captured:
            errors.append(f"{key}: a suite Continues it, but no run on the "
                          f"graph saves it; make it a cut with its true "
                          f"prev= (cutter= when a separate script saves it) "
                          f"or saves= on the state whose run saves it")
    for key in tracked:
        if key in captured:
            if key in not_gated:
                errors.append(f"{key}: captured by the graph and also listed "
                              f"in NOT_GATED; drop it from NOT_GATED")
            continue
        if key in not_gated:
            continue
        errors.append(f"{key}: not covered by the drift gate -- no run on "
                      f"the graph saves it; make it a cut with its true "
                      f"prev= (cutter= when a separate script saves it), "
                      f"saves= on the state whose run saves it, or name it "
                      f"in NOT_GATED with the reason")
    for key in sorted(set(not_gated) - set(tracked)):
        errors.append(f"{key}: in NOT_GATED but not a tracked checkpoint")
    return errors


def copy_if_changed_from(rel):
    return f"{COPY_IF_CHANGED_DIR}/{rel}"


def emit_state_rules(w):
    """The rule definitions, shared by standalone emission and the root
    configure.py's embedded emission (which owns the copy_if_changed and
    regen rules itself, so they are not here)."""
    w("# One generate: run.sh composes the generator with the lib halves, boots")
    w("# Mesen, and publishes $state.mss + $state.mss.lua atomically into")
    w("# build/states -- OT6_EXPECT_ARTIFACT makes a run that passes without")
    w("# emitting BOTH a hard failure.  The stamp records the generator sig,")
    w("# the artifact's hash, and (via the ancestor -- prev's stamp, the")
    w("# capture's sealed manifest at a cut, '-' for a power-on root) the hash")
    w("# of what this state grew from, so the whole line verifies")
    w("# transitively (#75).")
    w("# NB: $env is an optional per-edge splice; ninja strips a value's")
    w("# leading whitespace, so the separating spaces live HERE in the")
    w("# template (an empty splice leaves a harmless double space).")
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
    w("# A run that also saves a checkpoint: run.sh captures the battery its")
    w("# Save made (OT6_CAPTURE_SRM), and $seal seals it against the tracked")
    w("# manifest's authored fields into build/checkpoints/$key/, which the")
    w("# next leg Continues.")
    w("rule generate_capture")
    w("  command = OT6_WORKER=$state OT6_EXPECT_ARTIFACT='$expect' $env "
      "tools/tests/run.sh tools/tests/$gen.lua build/states/$state.log "
      "&& $stamps && $seal")
    w("  description = generate $state <- $gen (captures $key)")
    w("")
    w("# A cutter: a capture-only script booted from a state, publishing no")
    w("# state (OT6_NO_PUBLISH); it yields the sealed capture and a record of")
    w("# the run (the ROM, its own sig, the payload, the stamp of what it")
    w("# booted), which checkpoint_drift.py reads where a producer's stamp")
    w("# would be.")
    w("rule capture")
    w("  command = OT6_WORKER=$worker $env tools/tests/run.sh "
      "tools/tests/$gen.lua $log && $seal && "
      "{ echo \"rom $$(sh tools/tests/lib/savestate_stamp.sh romsig)\" && "
      "echo \"generator $$(sh tools/tests/lib/savestate_stamp.sh gensig $gen)\" && "
      "echo \"payload $$(shasum -a 256 $payload | cut -c1-64)\" && "
      "echo \"ancestor build/states/$boot.stamp "
      "$$(shasum -a 256 build/states/$boot.stamp | cut -c1-64)\"; } "
      "> $record")
    w("  description = capture $key <- $gen from $boot")
    w("")
    w("# The template a capture is sealed against: the tracked manifest's")
    w("# authored fields (its `saved` above all), rewritten only when they")
    w("# move, so a re-cut of the tracked checkpoint replays nothing.")
    w("rule checkpoint_authored")
    w("  command = python3 tools/tests/lib/savestate_ninja.py --authored $in $out")
    w("  description = checkpoint_authored $in")
    w("  restat = 1")
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
    w("# The ROM's copy, the same shape: the new bytes always land, but the")
    w("# old mtime is kept when the ROM identity (the ROM with its version")
    w("# fields masked, tools/build/rom_version.py) did not move, so a VERSION")
    w("# bump alone regenerates and re-runs nothing behind it.")
    w("rule copy_if_rom_identity_changed")
    w("  command = python3 tools/build/rom_version.py "
      "copy-if-identity-changed $in $out")
    w("  description = copy_if_rom_identity_changed $in")
    w("  restat = 1")
    w("")


SEALED_FIELDS = ("size", "sha256", "provenance")


def write_authored(manifest, out):
    """A tracked manifest minus what `seal` writes (size, sha256,
    provenance): the template a capture is sealed against.  Written only
    when it changed, so re-cutting the tracked checkpoint from the capture
    does not replay anything (restat)."""
    import json
    m = json.loads(manifest.read_text())
    text = json.dumps({k: v for k, v in m.items() if k not in SEALED_FIELDS},
                      indent=2) + "\n"
    out.parent.mkdir(parents=True, exist_ok=True)
    if not (out.exists() and out.read_text() == text):
        out.write_text(text)
    return 0


def _seal_cmd(key, authored):
    """Seal the capture in build/checkpoints/<key>/ against the tracked
    manifest's authored fields; refuse a battery holding another save; and
    print how far the tracked checkpoint is from it (report only; the
    release gate is configure.py's checkpoint_drift edge)."""
    cdir = f"{CAPTURE_DIR}/{key}"
    return (f"cp {authored} {cdir}/manifest.json && "
            f"python3 tools/tests/lib/sram_checkpoint.py seal {cdir} && "
            f"python3 tools/tests/lib/sram_checkpoint.py validate {cdir} && "
            f"python3 tools/tests/lib/checkpoint_drift.py {key}")


def emit_state_edges(w, states, root, copy_if_changed_from, side_pool=None):
    """The per-state build statements, the cutters' capture edges and the
    authored-manifest templates.  copy_if_changed_from(path) -> the
    dependency path to use for a copied source; the caller owns emitting the
    copy_if_changed edges themselves (so a source shared with other parts
    of a larger graph is copied exactly once)."""
    prods = producers(states)
    # side_pool: a ninja pool for runs off the play from power-on, so the
    # line's next run never waits for a -j slot behind side work (#344)
    line = line_runs(states)
    # the entry whose own run saves each checkpoint, and the cutters (a
    # capture-only script booted from a state) that save the rest
    saves = {run[1]: key for key, run in prods.items() if run[0] == "run"}
    cutters = {key: run for key, run in prods.items() if run[0] == "cutter"}
    common = [copy_if_changed_from(ROM), copy_if_changed_from(EMULATOR),
              copy_if_changed_from(REPLAY)]
    for key in sorted(prods):
        w(f"build build/ninja/authored/{key}.json: checkpoint_authored "
          f"tools/tests/checkpoints/{key}/manifest.json")
    w("")
    for key, run in sorted(cutters.items()):
        _, gen, boot = run
        cdir = f"{CAPTURE_DIR}/{key}"
        ins = capture_inputs(root, key)
        authored = f"build/ninja/authored/{key}.json"
        record = capture_record(key, run)
        worker = key.replace("-", "_")
        deps = common + [copy_if_changed_from(f"tools/tests/{gen}.lua"),
                         authored]
        w(f"build {' '.join(ins)} {ins[1]}.provenance.json {record}: capture "
          f"build/states/{boot}.mss.lua build/states/{boot}.mss "
          f"build/states/{boot}.stamp | {' '.join(deps)}")
        w(f"  worker = {worker}")
        w(f"  gen = {gen}")
        w(f"  key = {key}")
        w(f"  boot = {boot}")
        w(f"  log = build/states/{worker}.log")
        w(f"  record = {record}")
        w(f"  payload = {ins[1]}")
        w(f"  env = OT6_TIMEOUT={CUTTER_TIMEOUT} OT6_NO_PUBLISH=1 "
          f"OT6_CAPTURE_SRM={ins[1]}")
        w(f"  seal = {_seal_cmd(key, authored)}")
        if side_pool and _owners(states)[boot] not in line:
            w(f"  pool = {side_pool}")
    if cutters:
        w("")
    for e in states:
        s, gen = e["state"], e["gen"]
        names = [s] + list(e.get("also") or [])
        outs = " ".join(f"build/states/{n}.mss.lua build/states/{n}.mss"
                        for n in names)
        # Compatibility inputs only: the ROM, the emulator pin, the replay
        # lever and this state's own generator, plus what it boots below.
        # The lib halves are deliberately absent -- see the module header.
        deps = common + [copy_if_changed_from(f"tools/tests/{gen}.lua")]
        # Wall-clock default for generation edges: 1800 s rather than
        # run.sh's 600 s, because bare `ninja` fans every runnable generator
        # out at once and equally-niced emulators stretch each other's wall
        # clock.  A per-edge timeout= wins.
        env = [f"OT6_TIMEOUT={e.get('timeout') or 1800}"]
        explicit, extras = "", ""
        if e.get("prev") and e.get("checkpoint"):
            # A cut Continues the save the run before it captured.
            key = e["checkpoint"]
            ins = capture_inputs(root, key)
            explicit = " " + " ".join(ins)
            env.append(f"OT6_SRAM_CHECKPOINT={CAPTURE_DIR}/{key}")
            extras = " ".join(ins)
            ancestor = ins[0]
        elif e.get("prev"):
            p = e["prev"]
            explicit = (f" build/states/{p}.mss.lua build/states/{p}.mss"
                        f" build/states/{p}.stamp")
            ancestor = f"build/states/{p}.stamp"
        else:
            ancestor = "-"
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
        stamp_outs = " ".join(f"build/states/{n}.stamp" for n in names)
        rule, capture_outs, seal, key = "generate", "", "", saves.get(s)
        if key:
            ins = capture_inputs(root, key)
            rule = "generate_capture"
            env.append(f"OT6_CAPTURE_SRM={ins[1]}")
            capture_outs = f" {ins[0]} {ins[1]} {ins[1]}.provenance.json"
            authored = f"build/ninja/authored/{key}.json"
            deps.append(authored)
            seal = _seal_cmd(key, authored)
        w(f"build {outs} {stamp_outs}{capture_outs}: {rule}{explicit} | "
          f"{' '.join(deps)}")
        w(f"  state = {s}")
        w(f"  gen = {gen}")
        w(f"  expect = {' '.join(f'{n}.mss {n}.mss.lua' for n in names)}")
        w(f"  stamps = {' && '.join(stamp_cmds)}")
        w(f"  env = {' '.join(env)}")
        if seal:
            w(f"  seal = {seal}")
            w(f"  key = {key}")
        if side_pool and s not in line:
            w(f"  pool = {side_pool}")
    w("")


# ------------------------------------------------------- the quick lever --
# `ninja quick` (configure.py): early feedback for a branch that changed the
# ROM, without waiting for the play from power-on to reach a late leg.  Each
# cut leg boots its TRACKED checkpoint instead of the capture, so the legs
# between cuts run at once, as quick_<state> copies (OT6_STACK=quick_), and
# the suites whose fixtures they reach run on those.  A tracked checkpoint
# is a save made by an older build's play, so a quick result is NOT
# qualification, merge or release evidence (docs/TESTING.md); nothing in
# the default graph or the release depends on a quick_ output.
QUICK = "quick_"


def quick_affected(states):
    """The states whose quick_ copy differs from the real one: every state
    with a cut in its prev= ancestry (itself included), also= siblings
    with their run."""
    owner = _owners(states)
    by = {e["state"]: e for e in states}
    out = set()
    for e in states:
        cut = bool(e.get("prev") and e.get("checkpoint"))
        if cut or (e.get("prev") and owner[e["prev"]] in out):
            out.add(e["state"])
            out.update(e.get("also") or [])
    return out & (set(by) | {a for e in states for a in (e.get("also") or [])})


def emit_quick_edges(w, states, root, copy_if_changed_from, side_pool=None):
    """The quick_ copies (see QUICK): a generate edge per affected entry,
    a cut booting the tracked checkpoint, and a plain copy of each
    unaffected state a copy boots.  Returns the affected names."""
    affected = quick_affected(states)
    owner = _owners(states)
    common = [copy_if_changed_from(ROM), copy_if_changed_from(EMULATOR)]
    w("# The quick lever (savestate_ninja.py QUICK): never qualification.")
    w("rule quick_copy")
    w("  command = cp $src.mss build/states/$state.mss && "
      "cp $src.mss.lua build/states/$state.mss.lua && "
      "cp $src.stamp build/states/$state.stamp")
    w("  description = quick copy $state")
    w("")
    copied = set()
    for e in states:
        if e["state"] not in affected:
            continue
        p = e.get("prev")
        if p and not e.get("checkpoint") and owner[p] not in affected \
                and p not in copied:
            copied.add(p)
            src = f"build/states/{p}"
            w(f"build build/states/{QUICK}{p}.mss build/states/{QUICK}{p}.mss.lua "
              f"build/states/{QUICK}{p}.stamp: quick_copy {src}.mss "
              f"{src}.mss.lua {src}.stamp")
            w(f"  state = {QUICK}{p}")
            w(f"  src = {src}")
    for e in states:
        s, gen = e["state"], e["gen"]
        if s not in affected:
            continue
        names = [QUICK + n for n in [s] + list(e.get("also") or [])]
        outs = " ".join(f"build/states/{n}.mss.lua build/states/{n}.mss"
                        for n in names)
        deps = common + [copy_if_changed_from(f"tools/tests/{gen}.lua")]
        env = [f"OT6_STACK={QUICK}", f"OT6_TIMEOUT={e.get('timeout') or 1800}"]
        if e.get("prev") and e.get("checkpoint"):
            key = e["checkpoint"]
            ins = checkpoint_inputs(root, key)
            explicit = " " + " ".join(ins)
            env.append(f"OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/{key}")
            extras, ancestor = " " + " ".join(ins), ins[0]
        else:
            p = QUICK + e["prev"]
            explicit = (f" build/states/{p}.mss.lua build/states/{p}.mss"
                        f" build/states/{p}.stamp")
            extras, ancestor = "", f"build/states/{p}.stamp"
        stamp_cmds, anc = [], ancestor
        for n in names:
            stamp_cmds.append(
                f"sh tools/tests/lib/savestate_stamp.sh write {n} {gen} {anc}{extras}")
            anc = f"build/states/{n}.stamp"
        stamp_outs = " ".join(f"build/states/{n}.stamp" for n in names)
        w(f"build {outs} {stamp_outs}: generate{explicit} | {' '.join(deps)}")
        w(f"  state = {names[0]}")
        w(f"  gen = {gen}")
        w(f"  expect = {' '.join(f'{n}.mss {n}.mss.lua' for n in names)}")
        w(f"  stamps = {' && '.join(stamp_cmds)}")
        w(f"  env = {' '.join(env)}")
        if side_pool:
            w(f"  pool = {side_pool}")
    w("")
    return affected


def copy_rule(src, states):
    """The copy rule for one copy_if_changed source: a generator the graph
    runs is copied by its Lua token stream, the ROM by its identity
    (rom_version.py: the version fields masked), anything else by its
    bytes."""
    if src == ROM:
        return "copy_if_rom_identity_changed"
    gens = {f"tools/tests/{e[k]}.lua" for e in states
            for k in ("gen", "cutter") if e.get(k)}
    return "copy_if_lua_changed" if src in gens else "copy_if_changed"


def copy_if_changed_sources(states, root):
    """Every source path the state edges route through a copy_if_changed
    edge, in first-use order: the ROM, the emulator pin, the replay lever,
    each generator and cutter."""
    out = [ROM, EMULATOR, REPLAY]
    for e in states:
        for k in ("gen", "cutter"):
            g = e.get(k) and f"tools/tests/{e[k]}.lua"
            if g and g not in out:
                out.append(g)
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
    sidecars = " ".join(f"build/states/{e['state']}.mss.lua" for e in states)
    caps = " ".join(p for paths in captures(states, root).values()
                    for p in paths)
    w(f"build savestates: phony {sidecars} {caps}".rstrip())
    end = line_end(states)
    if end:
        w(f"build chain: phony build/states/{end}.mss.lua")
    w("default savestates")
    w("")
    return "\n".join(o)


def load(root):
    ns = runpy.run_path(str(root / GRAPH))
    return ns["STATES"]


def load_not_gated(root):
    """The graph's NOT_GATED: {tracked checkpoint key: why the release gate
    does not check it}."""
    return runpy.run_path(str(root / GRAPH)).get("NOT_GATED", {})


def coverage_report(states, root, booted):
    """--coverage: one line per tracked checkpoint, then the verdict."""
    captured = captures(states, root)
    prods = producers(states)
    not_gated = load_not_gated(root)
    for key in sorted(p.parent.name for p in
                      (root / "tools/tests/checkpoints").glob("*/manifest.json")
                      if not p.parent.name.startswith("negative")):
        if key in captured:
            run = prods[key]
            how = (f"{run[1]}'s run" if run[0] == "run" else
                   f"cutter {run[1]} from {run[2]}")
            print(f"gated      {key}: captured by {how}")
        elif key in not_gated:
            print(f"NOT_GATED  {key}: {not_gated[key]}")
        else:
            print(f"UNCOVERED  {key}")
    errors = coverage(states, root, booted, not_gated)
    for e in errors:
        print(f"checkpoint coverage: {e}", file=sys.stderr)
    print(f"checkpoint coverage: {len(captured)} tracked checkpoint(s) "
          f"captured by the graph and compared by the drift gate, "
          f"{len(not_gated)} NOT_GATED, {len(errors)} error(s)")
    return 1 if errors else 0


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", type=Path, default=ROOT,
                    help="tree to read the graph from and write into "
                         "(the selftest harness points this at a mock tree)")
    ap.add_argument("--list", action="store_true",
                    help="print state names in play order and exit")
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--authored", nargs=2, metavar=("MANIFEST", "OUT"),
                    help="write MANIFEST's authored fields to OUT, only "
                         "when they changed (a capture's seal template)")
    ap.add_argument("--coverage", action="store_true",
                    help="check that every tracked checkpoint is captured by "
                         "a run on the graph (so the drift gate compares it) "
                         "or named in NOT_GATED")
    ap.add_argument("--booted", nargs="*", default=[], metavar="KEY",
                    help="with --coverage: checkpoints suites Continue "
                         "(configure.py's TEST_ENV)")
    args = ap.parse_args(argv)
    if args.selftest:
        return selftest()
    if args.authored:
        return write_authored(Path(args.authored[0]), Path(args.authored[1]))

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
    if args.coverage:
        return coverage_report(states, root, args.booted)
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
    a differently-shaped edge; and the emitted shape.  Pure python; the
    ninja-semantics proofs are in savestate_ninja_selftest.sh."""
    ok = True

    def check(label, cond):
        nonlocal ok
        print(f"  {'pass' if cond else 'FAIL'} {label}")
        ok = ok and cond

    import tempfile

    def s(**kw):
        e = {"state": None, "gen": None, "prev": None, "checkpoint": None}
        e.update(kw)
        return e

    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        for key in ("k1-v1", "k2-v1", "k3-v1", "k4-v1", "spare-v1",
                    "negative-x-v1"):
            d = root / "tools/tests/checkpoints" / key
            d.mkdir(parents=True)
            (d / "manifest.json").write_text("{}")
            (d / f"{key[:-3]}.sram").write_text("x")
        (root / "tools/tests/checkpoints/empty-v1").mkdir(parents=True)
        (root / "tools/tests/checkpoints/empty-v1/manifest.json").write_text("{}")
        for g in ("gen_ok", "gen_cut"):
            (root / f"tools/tests/{g}.lua").write_text("-- ok")

        # o (power-on) saves k1 with also= sibling o2 standing at the save;
        # p Continues k1.  A cutter booted from p saves k2, which q and q2
        # Continue; r Continues k3, which q's own run saves; r's run saves
        # k4, which nothing boots (the frontier).  x branches off o; b is a
        # second power-on root.
        full = [s(state="o", gen="gen_ok", also=["o2"]),
                s(state="b", gen="gen_ok"),
                s(state="p", gen="gen_ok", prev="o2", checkpoint="k1-v1"),
                s(state="x", gen="gen_ok", prev="o"),
                s(state="q", gen="gen_ok", prev="p", checkpoint="k2-v1",
                  cutter="gen_cut"),
                s(state="q2", gen="gen_ok", prev="p", checkpoint="k2-v1",
                  cutter="gen_cut"),
                s(state="r", gen="gen_ok", prev="q", checkpoint="k3-v1",
                  saves="k4-v1", timeout=3600)]
        check("a graph with every kind of edge validates",
              validate(full, root) == [])
        bad = [
            ("duplicate state", [s(state="a", gen="gen_ok")] * 2),
            ("no gen", [s(state="a")]),
            ("unknown generator", [s(state="a", gen="gen_missing")]),
            ("prev not earlier", [s(state="a", gen="gen_ok", prev="zzz")]),
            ("a checkpoint boot with no prev= (no run makes that save)",
             [s(state="a", gen="gen_ok", checkpoint="k1-v1")]),
            ("one run standing for two checkpoints",
             [s(state="a", gen="gen_ok"),
              s(state="b", gen="gen_ok", prev="a", checkpoint="k1-v1"),
              s(state="c", gen="gen_ok", prev="a", checkpoint="k2-v1")]),
            ("negative-* checkpoint refused",
             [s(state="a", gen="gen_ok"),
              s(state="b", gen="gen_ok", prev="a", checkpoint="negative-x-v1")]),
            ("checkpoint without manifest",
             [s(state="a", gen="gen_ok"),
              s(state="b", gen="gen_ok", prev="a", checkpoint="nope-v1")]),
            ("checkpoint without payload",
             [s(state="a", gen="gen_ok"),
              s(state="b", gen="gen_ok", prev="a", checkpoint="empty-v1")]),
            ("unknown field",
             [dict(s(state="a", gen="gen_ok"), checkpointt="oops")]),
            ("the retired seed= field", [s(state="a", gen="gen_ok"),
                                         dict(s(state="d"), seed="a")]),
            ("the retired after= field",
             [s(state="a", gen="gen_ok"),
              dict(s(state="b", gen="gen_ok"), after="a")]),
            ("bad state name", [s(state="a/b", gen="gen_ok")]),
            ("also duplicating a state",
             [s(state="a", gen="gen_ok"),
              s(state="b", gen="gen_ok", also=["a"])]),
            ("also duplicating itself",
             [s(state="a", gen="gen_ok", also=["x", "x"])]),
            ("cutter= off a cut",
             [s(state="a", gen="gen_ok"),
              s(state="p", gen="gen_ok", prev="a", cutter="gen_cut")]),
            ("a missing cutter",
             full[:3] + [s(state="q", gen="gen_ok", prev="p",
                           checkpoint="k2-v1", cutter="gen_nope")]),
            ("saves= naming a negative fixture",
             full[:1] + [s(state="d", gen="gen_ok", prev="o",
                           saves="negative-x-v1")]),
            ("one checkpoint made by two runs",
             full + [s(state="t", gen="gen_ok", prev="o", saves="k4-v1")]),
            ("a run saving one checkpoint and standing for another",
             full[:3] + [s(state="q", gen="gen_ok", prev="p",
                           checkpoint="k2-v1", saves="k3-v1"),
                         s(state="r", gen="gen_ok", prev="q",
                           checkpoint="k4-v1")]),
            ("a timeout out of range",
             [s(state="a", gen="gen_ok", timeout=10)]),
        ]
        for label, graph in bad:
            check(f"refused: {label}", validate(graph, root) != [])

        text = emit(full, root)
        lines = text.splitlines()

        def edge(out):
            return next((l for l in lines if l.startswith(f"build {out}")), "")

        def body(out):
            i = next((i for i, l in enumerate(lines)
                      if l.startswith(f"build {out}")), None)
            if i is None:
                return ""
            got = []
            for l in lines[i + 1:]:
                if not l.startswith("  "):
                    break
                got.append(l)
            return "\n".join(got)
        check("copy_if_changed rule is restat",
              text.split("rule copy_if_changed")[1].split("rule ")[0].count(
                  "restat = 1") == 1)
        gen_lines = [l for l in lines if ": generate" in l]
        cap_lines = [l for l in lines if ": capture" in l]
        check("one generate edge per graph entry, no copies",
              len(gen_lines) == len(full) and "chain_" not in text
              and ": seed" not in text)
        need = [f"{COPY_IF_CHANGED_DIR}/{x}" for x in (ROM, EMULATOR, REPLAY)]
        check("every generate and capture edge depends on the ROM, the "
              "emulator pin and the replay lever",
              all(n in l for l in gen_lines + cap_lines for n in need))
        check("...and on its own generator",
              all(f"{COPY_IF_CHANGED_DIR}/tools/tests/gen_ok.lua" in l
                  for l in gen_lines)
              and f"{COPY_IF_CHANGED_DIR}/tools/tests/gen_cut.lua" in cap_lines[0])
        check("no generate or capture edge depends on a lib half "
              "(docs/TESTING.md)",
              not any(h in text for h in LIB_HALVES))
        check("a power-on root boots nothing and binds no ancestor",
              "write o gen_ok -" in text and "build/states/" not in
              edge("build/states/o.mss.lua").split("| ")[0].split(": generate")[1])
        check("a plain link boots its prev and binds its stamp",
              "build/states/o.mss build/states/o.stamp" in edge("build/states/x.mss.lua")
              and "write x gen_ok build/states/o.stamp" in text)
        check("an also= run publishes every artifact from one edge, its "
              "stamps chained through the run",
              edge("build/states/o.mss.lua").startswith(
                  "build build/states/o.mss.lua build/states/o.mss "
                  "build/states/o2.mss.lua build/states/o2.mss")
              and "write o2 gen_ok build/states/o.stamp" in text)
        check("the producer's run (o, whose also= o2 is the cut's prev) "
              "captures and seals the save",
              "build/checkpoints/k1-v1/manifest.json build/checkpoints/k1-v1/k1.sram"
              in edge("build/states/o.mss.lua")
              and ": generate_capture" in edge("build/states/o.mss.lua")
              and "OT6_CAPTURE_SRM=build/checkpoints/k1-v1/k1.sram" in body("build/states/o.mss.lua")
              and "sram_checkpoint.py seal build/checkpoints/k1-v1" in body("build/states/o.mss.lua"))
        check("the seal's template is the manifest's authored fields, so a "
              "re-cut of the tracked checkpoint replays nothing",
              "build/ninja/authored/k1-v1.json" in edge("build/states/o.mss.lua")
              and "tools/tests/checkpoints/k1-v1/manifest.json"
                  not in edge("build/states/o.mss.lua")
              and "build build/ninja/authored/k1-v1.json: checkpoint_authored "
                  "tools/tests/checkpoints/k1-v1/manifest.json" in text)
        check("the cut Continues the capture, never the tracked checkpoint",
              ": generate build/checkpoints/k1-v1/manifest.json "
              "build/checkpoints/k1-v1/k1.sram |" in edge("build/states/p.mss.lua")
              and "OT6_SRAM_CHECKPOINT=build/checkpoints/k1-v1" in body("build/states/p.mss.lua")
              and "write p gen_ok build/checkpoints/k1-v1/manifest.json "
                  "build/checkpoints/k1-v1/manifest.json build/checkpoints/k1-v1/k1.sram"
                  in text
              and not any("tools/tests/checkpoints/" in l
                          for l in gen_lines + cap_lines))
        cap = edge("build/checkpoints/k2-v1/manifest.json")
        check("the cutter's capture edge boots its prev's savestate",
              ": capture build/states/p.mss.lua build/states/p.mss "
              "build/states/p.stamp" in cap)
        check("...publishes no state and records the run that made it",
              "OT6_NO_PUBLISH=1 OT6_CAPTURE_SRM=build/checkpoints/k2-v1/k2.sram"
              in body("build/checkpoints/k2-v1/manifest.json")
              and "build/checkpoints/k2-v1.record" in cap
              and "romsig" in text and "gensig $gen" in text)
        check("...once, though two cuts Continue its save",
              len(cap_lines) == 1)
        check("a saves= frontier's run captures its save",
              "build/checkpoints/k4-v1/manifest.json" in edge("build/states/r.mss.lua")
              and "OT6_CAPTURE_SRM=build/checkpoints/k4-v1/k4.sram" in text)
        check("a run that saves nothing captures nothing",
              ": generate " in edge("build/states/x.mss.lua")
              and "OT6_CAPTURE_SRM" not in body("build/states/x.mss.lua"))
        check("timeout= is the edge's cap, 1800 s otherwise",
              "OT6_TIMEOUT=3600" in body("build/states/r.mss.lua")
              and "OT6_TIMEOUT=1800" in body("build/states/x.mss.lua"))
        check("`chain` names the end of the play from power-on",
              "build chain: phony build/states/r.mss.lua" in text)
        pooled = []
        emit_state_edges(pooled.append, full, root, copy_if_changed_from,
                         side_pool="side")

        def pool_of(out):
            i = next(i for i, l in enumerate(pooled)
                     if l.startswith(f"build {out}"))
            for l in pooled[i + 1:]:
                if not l.startswith("  "):
                    return None
                if l.startswith("  pool = "):
                    return l.split(" = ")[1]
            return None
        check("the play from power-on is o, p, q, r",
              line_runs(full) == {"o", "p", "q", "r"})
        check("its runs and the cutter on it take any free slot; side work "
              "(a branch, a second power-on root, a cut off the line) is "
              "pooled (#344)",
              [pool_of(f"build/states/{n}.mss.lua") for n in "opqrxb"]
              + [pool_of("build/states/q2.mss.lua"),
                 pool_of("build/checkpoints/k2-v1/manifest.json")]
              == [None, None, None, None, "side", "side", "side", None])
        check("the drift gate's keys are every captured checkpoint",
              sorted(captures(full, root)) ==
              ["k1-v1", "k2-v1", "k3-v1", "k4-v1"])

        gated = {"spare-v1": "booted by nothing", "empty-v1": "a mock"}
        check("every tracked checkpoint covered: no coverage error",
              coverage(full, root, ("k2-v1",), gated) == [])
        errs = coverage(full, root, (), {})
        check("NEGATIVE a tracked checkpoint nothing makes or lists fails "
              "coverage", any(e.startswith("spare-v1:") for e in errs))
        errs = coverage(full, root, ("spare-v1",), gated)
        check("NEGATIVE a suite Continuing a checkpoint no run saves fails "
              "coverage", any(e.startswith("spare-v1:") and "a suite" in e
                              for e in errs))
        errs = coverage(full[:-1] + [s(state="r", gen="gen_ok", prev="q",
                                       checkpoint="k3-v1")], root, (), gated)
        check("NEGATIVE a frontier save with no saves= fails coverage",
              any(e.startswith("k4-v1:") for e in errs))
        check("negative-* fixtures are never asked for", not any(
            "negative" in e for e in coverage(full, root, (), {})))
    print("savestate_ninja selftest:", "ok" if ok else "FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
