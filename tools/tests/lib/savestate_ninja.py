#!/usr/bin/env python3
"""savestate_ninja.py -- the savestate graph (tools/tests/savestate_graph.py)
as ninja build statements: one graph, played once, from power-on.

Every generated state has one edge: run.sh composes its generator with the
test library, boots the state before it (prev=), and publishes
build/states/<state>.mss + .mss.lua.  A cut (prev= with checkpoint=) boots
instead the battery save the run before it made: that run captures its
battery (OT6_CAPTURE_SRM) into build/checkpoints/<key>/, a seal edge turns
the capture into a checkpoint (the tracked manifest's authored fields, the
payload's size and hash, its provenance), and the cut's run Continues it.
A cutter= script, booted from prev's savestate, makes the save when prev's
own run does not; CAPTURES (capture-only cutters nothing boots) and saves=
(a run that saves a checkpoint nothing boots yet) put every tracked
checkpoint on the graph, and checkpoint_drift.py's gate compares each
tracked checkpoint with the graph's capture of it.

Dependencies are the true inputs of each run, by content:

  * the composed script, through a digest edge: `compose.py --digest`
    composes the script exactly as the run will (the generator, the lib
    files it inlines, the savestate sidecars it embeds, the write-gate
    registry, the symbols it names) and writes the sha256 of its Lua token
    stream, rewriting the file only when that changes (restat = 1).  So an
    edit that leaves a script's composed program alone (a comment, another
    script's waiver, compose.py's own diagnostics) runs that digest edge
    and nothing after it.
  * the ROM's identity (tools/build/rom_version.py: the ROM with its
    version fields masked, so the release commit's VERSION bump moves
    nothing that does not read them), the emulator pin, run.sh and the
    Python it runs (RUN_INPUTS), each through a copy edge that keeps its
    mtime when what it compares did not move;
  * at a cut, the capture's payload and the tracked manifest's authored
    fields (its sealed manifest only orders the run: the seal re-checks the
    payload before anything boots it).

Generate and capture edges are restat: run.sh publishes an artifact only
when its bytes changed, so a run that plays to the same bytes stops there.
Each artifact's stamp (lib/stamps.py) is its own edge, recorded after the
run from the same inputs, so a change to the stamp tool rewrites stamps and
replays nothing.

Usage:
    python3 tools/tests/lib/savestate_ninja.py --selftest   # validation, emission
    python3 tools/tests/lib/savestate_ninja.py --authored MANIFEST OUT

Emitted paths are relative to the repo root: run ninja from the root.
configure.py embeds emit_state_rules/emit_state_edges into build.ninja.
"""

import argparse
import json
import re
import runpy
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent          # tools/tests/lib
ROOT = HERE.parent.parent.parent                # lib -> tests -> tools -> root

GRAPH = "tools/tests/savestate_graph.py"
ROM = "build/ot6.sfc"
# The emulator the fixtures are made with: the fork commit tools/mesen/build.sh
# builds (tools/mesen/README.md).  A machine snapshot is only as good as the
# emulator that played it, so the pin is an input of every run.
EMULATOR = "tools/mesen/EMULATOR"
# What a run executes besides its composed script: the runner and the
# Python it calls before and after the emulator (the settings pins, the
# artifact decode).  compose.py is not here: the digest edge is what a run's
# composition depends on.
RUN_INPUTS = (ROM, EMULATOR, "tools/tests/run.sh",
              "tools/tests/lib/pin_test_saves.py",
              "tools/tests/lib/decode_b64.py")
# ...and what a run that Continues a checkpoint also executes: the
# checkpoint's validate-and-materialize before the emulator boots.
CHECKPOINT_TOOL = "tools/tests/lib/sram_checkpoint.py"
# The test library compose.py can inline.  A digest edge depends on every
# one through a Lua copy (comment and whitespace edits move nothing); the
# digest itself says whether the composed program moved.
LIB_FILES = (
    "tools/tests/lib/ot6.lua",
    "tools/tests/lib/ot6_field.lua",
    "tools/tests/lib/ot6_contract.lua",
)
# What composition reads besides the script, its lib and its sidecars:
# VERSION reaches only a script that names OT6_VERSION (compose.py).
COMPOSE_INPUTS = ("tools/tests/lib/compose.py",
                  "tools/tests/lib/lua_fingerprint.py",
                  "tools/state_write_waivers.txt",
                  "ff6/rom/ff6-en.dbg", "VERSION")
STAMP_TOOL = ("tools/tests/lib/stamps.py", "tools/tests/lib/compose.py",
              "tools/tests/lib/lua_fingerprint.py")
COPY_DIR = "build/ninja/src"
DIGEST_DIR = "build/ninja/digest"
CAPTURE_DIR = "build/checkpoints"
AUTHORED_DIR = "build/ninja/authored"

NAME_RE = re.compile(r"^[A-Za-z0-9_]+$")
FIELDS = {"state", "gen", "prev", "checkpoint", "timeout", "also", "saves",
          "cutter"}
CAPTURE_FIELDS = {"capture", "cutter", "prev", "timeout"}
# run.sh's wall-clock cap for a run with no timeout= of its own.  Bare
# `ninja` runs every ready edge at once and equally-niced emulators stretch
# each other's wall clock, so this is run.sh's 600 s default tripled.
DEFAULT_TIMEOUT = 1800
# A cutter's cap.  The longest, gen_terra_returned_checkpoint, allows itself
# 160000 frames: ~2000 s at a loaded machine's ~80 frames/s.
CUTTER_TIMEOUT = 3600
# The sidecars a composition embeds: compose.py's own rule, every
# "<path>.mss.lua" string literal in the script.
SIDECAR_REF = re.compile(r'"([^"]+\.mss\.lua)"')
# Every file and directory the helpers below read while the manifest is
# written: configure.py lists them in build.ninja's depfile, so an edit
# that changes what they return (a script that embeds another sidecar, a
# checkpoint that gains a payload) re-runs configure.
READS = set()


def checkpoint_inputs(root, key):
    """A tracked checkpoint's files: manifest first, then sorted payloads."""
    adir = f"tools/tests/checkpoints/{key}"
    READS.add(adir)
    payloads = sorted(p.name for p in (root / adir).glob("*.sram"))
    return [f"{adir}/manifest.json"] + [f"{adir}/{p}" for p in payloads]


def payload_name(root, key):
    return Path(checkpoint_inputs(root, key)[1]).name


def tracked_checkpoints(root):
    """Every tracked checkpoint key, the deliberately wrong negative-*
    fixtures aside."""
    READS.add("tools/tests/checkpoints")
    return sorted(p.parent.name for p in
                  (root / "tools/tests/checkpoints").glob("*/manifest.json")
                  if not p.parent.name.startswith("negative"))


def _owners(states):
    """name -> the entry name whose run publishes it (itself, or the state
    an also= sibling rides with)."""
    owner = {}
    for e in states:
        owner[e["state"]] = e["state"]
        for a in (e.get("also") or []):
            owner[a] = e["state"]
    return owner


def producers(states, captures):
    """{checkpoint key: the run that saves it}: ("run", state) when that
    state's own run saves it (prev= of a cut with no cutter, or saves=),
    ("cutter", gen, prev) when a capture-only script booted from prev's
    savestate does (a cut's cutter=, or a CAPTURES entry)."""
    owner = _owners(states)
    out = {}
    for e in states:
        key = e.get("checkpoint")
        if e.get("prev") and key:
            run = (("cutter", e["cutter"], e["prev"]) if e.get("cutter")
                   else ("run", owner[e["prev"]]))
            out.setdefault(key, run)
        if e.get("saves"):
            out.setdefault(e["saves"], ("run", e["state"]))
    for c in captures:
        out.setdefault(c["capture"], ("cutter", c["cutter"], c["prev"]))
    return out


def validate(states, root, captures=()):
    """Every error is fatal and named; a malformed entry must never emit as
    some other kind of edge."""
    errors = []
    seen = set()
    runs = {}        # (generator, boot) -> the entry that plays it
    names = set()
    for e in states:
        if isinstance(e, dict):
            names.add(e.get("state"))
            names.update(e.get("also") or [])

    def err(entry, msg):
        errors.append(f"{entry.get('state') or entry.get('capture') or '<unnamed>'}: {msg}")

    def tracked_key(entry, field, key):
        if key.startswith("negative"):
            err(entry, f"{field} {key!r} is a negative fixture")
        elif not (root / "tools/tests/checkpoints" / key / "manifest.json").is_file():
            err(entry, f"{field} {key!r} has no manifest.json")
        elif len(checkpoint_inputs(root, key)) != 2:
            err(entry, f"{field} {key!r} must hold exactly one *.sram")

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
        gen, prev, checkpoint = e.get("gen"), e.get("prev"), e.get("checkpoint")
        if not gen:
            err(e, "gen= is required")
        elif not (root / "tools/tests" / f"{gen}.lua").is_file():
            err(e, f"no such generator tools/tests/{gen}.lua")
        if prev and prev not in seen:
            err(e, f"prev {prev!r} is not an earlier state")
        # One leg, one run: a script from one boot plays the same game
        # whatever its edge is called, so a second entry is the same leg
        # played twice.  Its other saves are also= siblings.
        boot = (checkpoint, prev) if checkpoint else prev
        if gen and (gen, boot) in runs:
            err(e, f"{gen} from {checkpoint or prev or 'power-on'} is the leg "
                   f"{runs[(gen, boot)]!r} already plays: name this save in "
                   f"its also=")
        runs[(gen, boot)] = s
        # prev= is what the run boots: the one sidecar the generator embeds
        # (compose.py), or, at a cut, none (it boots the capture).
        if gen and (root / "tools/tests" / f"{gen}.lua").is_file():
            refs = fixture_refs(root, f"tools/tests/{gen}.lua", names)
            want = [] if checkpoint or not prev else [prev]
            if refs != want:
                err(e, f"{gen} embeds {refs or 'no sidecar'} but the entry "
                       f"boots {('the capture ' + checkpoint) if checkpoint else (prev or 'power-on')}"
                       + (" (a cut boots its capture and embeds none)" if checkpoint else
                          f" (prev= must be the sidecar it embeds)"))
        # A cut boots the graph's own capture of the save prev's play ends
        # at; a checkpoint with no prev= would boot a save no run here made.
        if checkpoint and not prev:
            err(e, "checkpoint= needs prev= (the state whose play ends at "
                   "the save)")
        for field in ("checkpoint", "saves"):
            if e.get(field):
                tracked_key(e, field, e[field])
        if e.get("saves") and checkpoint and e["saves"] == checkpoint:
            err(e, "saves= names the checkpoint this state boots")
        cutter = e.get("cutter")
        if cutter:
            if not (prev and checkpoint):
                err(e, "cutter= is only for a cut (prev= with checkpoint=)")
            if not (root / "tools/tests" / f"{cutter}.lua").is_file():
                err(e, f"no such cutter tools/tests/{cutter}.lua")
        timeout = e.get("timeout")
        if timeout is not None and not (isinstance(timeout, int)
                                        and 60 <= timeout <= 7200):
            err(e, f"timeout {timeout!r} must be an int between 60 and 7200")
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
    for c in captures:
        unknown = set(c) - CAPTURE_FIELDS
        if unknown:
            err(c, f"unknown field(s) {sorted(unknown)}")
            continue
        key = c.get("capture")
        if not isinstance(key, str):
            err(c, f"bad capture key {key!r}")
            continue
        tracked_key(c, "capture", key)
        if c.get("prev") not in seen:
            err(c, f"prev {c.get('prev')!r} is not a state")
        cutter = c.get("cutter")
        if not (cutter and (root / "tools/tests" / f"{cutter}.lua").is_file()):
            err(c, f"no such cutter tools/tests/{cutter}.lua")
    if errors:
        return errors
    # One run saves one battery, so it stands for one checkpoint; one
    # checkpoint is made by one run.
    owner = _owners(states)
    made, by_key = {}, {}

    def claim(entry, run, key):
        name = run[1] if run[0] == "run" else f"{run[1]} (from {run[2]})"
        if made.setdefault(run, key) != key:
            err(entry, f"{name}'s run already saves checkpoint {made[run]!r}; "
                       f"one run cannot also stand for {key!r}")
        if by_key.setdefault(key, run) != run:
            other = by_key[key]
            oname = other[1] if other[0] == "run" else f"{other[1]} (from {other[2]})"
            err(entry, f"checkpoint {key!r} is already made by {oname}'s run; "
                       f"{name} cannot make it too")
    for e in states:
        if e.get("prev") and e.get("checkpoint"):
            run = (("cutter", e["cutter"], e["prev"]) if e.get("cutter")
                   else ("run", owner[e["prev"]]))
            claim(e, run, e["checkpoint"])
        if e.get("saves"):
            claim(e, ("run", e["state"]), e["saves"])
    for c in captures:
        claim(c, ("cutter", c["cutter"], c["prev"]), c["capture"])
    # Every tracked checkpoint is made by the graph, so the drift gate
    # compares every one.
    made_keys = set(by_key)
    for key in tracked_checkpoints(root):
        if key not in made_keys:
            errors.append(f"{key}: a tracked checkpoint no run on the graph "
                          f"saves; make it a cut (prev= with checkpoint=, "
                          f"cutter= when a separate script saves it), saves= "
                          f"on the state whose run saves it, or a CAPTURES "
                          f"entry")
    return errors


# ------------------------------------------------------------- emission ----
def copy_from(rel):
    return f"{COPY_DIR}/{rel}"


def digest_path(label):
    return f"{DIGEST_DIR}/{label}.digest"


def capture_label(key):
    return "capture_" + key.replace("-", "_")


def capture_paths(root, key):
    """(payload, sealed manifest, capture stamp) of the graph's capture of
    `key`."""
    cdir = f"{CAPTURE_DIR}/{key}"
    return (f"{cdir}/{payload_name(root, key)}", f"{cdir}/manifest.json",
            f"{CAPTURE_DIR}/{key}.stamp")


def boot_env(e):
    """The environment a state's run (and its composition) gets from the
    graph: the checkpoint a cut Continues."""
    if e.get("prev") and e.get("checkpoint"):
        return {"OT6_SRAM_CHECKPOINT": f"{CAPTURE_DIR}/{e['checkpoint']}"}
    return {}


def fixture_refs(root, lua_rel, names):
    """The graph states whose sidecars a script's composition embeds."""
    READS.add(str(lua_rel))
    text = (root / lua_rel).read_text(errors="replace")
    return sorted({Path(r).name[:-len(".mss.lua")]
                   for r in SIDECAR_REF.findall(text)} & set(names))


def emit_state_rules(w):
    """Rule definitions shared by the standalone emission and configure.py
    (which owns the copy rules)."""
    w("# A composed script's digest: compose.py composes it as the run will")
    w("# and writes the sha256 of its Lua token stream, only when it moved.")
    w("rule compose_digest")
    w("  command = $env python3 tools/tests/lib/compose.py --digest $script $out")
    w("  description = digest $script")
    w("  restat = 1")
    w("")
    w("# One generate: run.sh composes the generator with the lib, boots")
    w("# Mesen, and publishes $state.mss + $state.mss.lua into build/states,")
    w("# each only when its bytes changed (restat).  OT6_EXPECT_ARTIFACT makes")
    w("# a run that passes without emitting them all a failure.")
    w("rule generate")
    w("  command = OT6_GRAPH=1 OT6_WORKER=$state OT6_EXPECT_ARTIFACT='$expect' $env "
      "tools/tests/run.sh tools/tests/$gen.lua build/states/$state.log")
    w("  description = generate $state <- $gen")
    w("  restat = 1")
    w("")
    w("# A cutter: a capture-only script booted from a state; it publishes no")
    w("# state, only the battery it saved (OT6_CAPTURE_SRM).")
    w("rule capture")
    w("  command = OT6_GRAPH=1 OT6_WORKER=$worker OT6_NO_PUBLISH=1 $env "
      "tools/tests/run.sh tools/tests/$gen.lua build/states/$worker.log")
    w("  description = capture $key <- $gen")
    w("  restat = 1")
    w("")
    w("# A run's record (lib/stamps.py): what it composed, ran on and booted.")
    w("# stamps.py rewrites a stamp only when its text moved (restat).")
    w("rule stamp")
    w("  command = python3 tools/tests/lib/stamps.py write $out $args")
    w("  description = stamp $out")
    w("  restat = 1")
    w("")
    w("# The checkpoint a capture makes: the tracked manifest's authored")
    w("# fields, the payload's size and sha256, and its provenance from the")
    w("# capture's stamp; seal refuses a battery holding another save.")
    w("rule seal")
    w("  command = python3 tools/tests/lib/sram_checkpoint.py seal-capture "
      "$cdir $authored $stamp")
    w("  description = seal $cdir")
    w("")
    w("rule checkpoint_authored")
    w("  command = python3 tools/tests/lib/savestate_ninja.py --authored $in $out")
    w("  description = checkpoint_authored $in")
    w("  restat = 1")
    w("")


def _env_str(env):
    return " ".join(f"{k}={v}" for k, v in env.items())


def emit_state_edges(w, states, root, copy_from, lua_copy_from=None,
                     captures=()):
    """The per-state build statements.  copy_from(path) / lua_copy_from(path)
    -> the dependency path of a copied source (byte copy / Lua token copy);
    the caller emits those copy edges.  Returns {state: [its .mss outputs]}
    for the caller's audits."""
    lua_copy_from = lua_copy_from or copy_from
    names = set(_owners(states))
    prod = producers(states, captures)
    saves = {run[1]: key for key, run in prod.items() if run[0] == "run"}
    run_deps = [copy_from(p) for p in RUN_INPUTS]
    compose_deps = ([lua_copy_from(p) for p in LIB_FILES]
                    + [copy_from(p) for p in COMPOSE_INPUTS])
    stamp_tool = [copy_from(p) for p in STAMP_TOOL]

    def digest_edge(label, script_rel, env):
        refs = fixture_refs(root, script_rel, names)
        sidecars = [f"build/states/{r}.mss.lua" for r in refs]
        w(f"build {digest_path(label)}: compose_digest {script_rel} | "
          f"{' '.join(compose_deps + sidecars)}")
        w(f"  script = {script_rel}")
        if env:
            w(f"  env = {_env_str(env)}")
        return refs

    def stamp_edge(out, artifact, gen, label, inputs, ancestor, emulator_of):
        args = [f"--generator {gen}", f"--digest {digest_path(label)}",
                f"--artifact {artifact}"]
        args += [f"--input {p}" for p in inputs]
        if ancestor:
            args.append(f"--ancestor {ancestor}")
        if emulator_of:
            args.append(f"--emulator-of {emulator_of}")
        # the stamp hashes the sources; it depends on them as the run does,
        # through their copies
        copied = set(RUN_INPUTS) | {CHECKPOINT_TOOL}
        srcs = [copy_from(p) if p in copied else p for p in inputs]
        w(f"build {out}: stamp {artifact} | {digest_path(label)} "
          f"{' '.join(srcs + stamp_tool)}")
        w(f"  args = {' '.join(args)}")

    emitted_keys = set()

    def seal_edge(key):
        if key in emitted_keys:
            return
        emitted_keys.add(key)
        payload, manifest, cstamp = capture_paths(root, key)
        authored = f"{AUTHORED_DIR}/{key}.json"
        w(f"build {authored}: checkpoint_authored "
          f"tools/tests/checkpoints/{key}/manifest.json")
        w(f"build {manifest}: seal {payload} {authored} {cstamp} | "
          f"{copy_from('tools/tests/lib/sram_checkpoint.py')}")
        w(f"  cdir = {CAPTURE_DIR}/{key}")
        w(f"  authored = {authored}")
        w(f"  stamp = {cstamp}")

    mss = {}
    for e in states:
        s, gen = e["state"], e["gen"]
        outs_names = [s] + list(e.get("also") or [])
        env = boot_env(e)
        timeout = e.get("timeout") or DEFAULT_TIMEOUT
        script = f"tools/tests/{gen}.lua"
        digest_edge(s, script, env)
        deps = [digest_path(s)] + run_deps
        order = []
        ancestor = None
        run_inputs = list(RUN_INPUTS)
        if e.get("prev") and e.get("checkpoint"):
            key = e["checkpoint"]
            payload, manifest, cstamp = capture_paths(root, key)
            authored = f"{AUTHORED_DIR}/{key}.json"
            deps += [copy_from(CHECKPOINT_TOOL), payload, authored]
            run_inputs += [CHECKPOINT_TOOL, payload, authored]
            order.append(manifest)
            ancestor = cstamp
            seal_edge(key)
        elif e.get("prev"):
            ancestor = f"build/states/{e['prev']}.stamp"
        outs = []
        for n in outs_names:
            outs += [f"build/states/{n}.mss.lua", f"build/states/{n}.mss"]
        mss[s] = [f"build/states/{n}.mss" for n in outs_names]
        renv = dict(env)
        renv["OT6_TIMEOUT"] = str(timeout)
        key = saves.get(s)
        if key:
            payload, manifest, cstamp = capture_paths(root, key)
            outs.append(payload)
            renv["OT6_CAPTURE_SRM"] = payload
        w(f"build {' '.join(outs)}: generate | {' '.join(deps)}"
          + (f" || {' '.join(order)}" if order else ""))
        w(f"  state = {s}")
        w(f"  gen = {gen}")
        w(f"  expect = {' '.join(f'{n}.mss {n}.mss.lua' for n in outs_names)}")
        w(f"  env = {_env_str(renv)}")
        for n in outs_names:
            stamp_edge(f"build/states/{n}.stamp", f"build/states/{n}.mss", gen,
                       s, run_inputs, ancestor, f"build/states/{n}.mss.emulator")
        if key:
            payload, manifest, cstamp = capture_paths(root, key)
            stamp_edge(cstamp, payload, gen, s, run_inputs, ancestor, None)
            seal_edge(key)
    # the cutters: each checkpoint's once, however many cuts boot it
    for key, run in sorted(prod.items()):
        if run[0] != "cutter":
            continue
        _, gen, prev = run
        label = capture_label(key)
        payload, manifest, cstamp = capture_paths(root, key)
        timeout = next((c.get("timeout") for c in captures
                        if c["capture"] == key and c.get("timeout")), None) \
            or CUTTER_TIMEOUT
        script = f"tools/tests/{gen}.lua"
        digest_edge(label, script, {})
        w(f"build {payload}: capture | {digest_path(label)} {' '.join(run_deps)}")
        w(f"  worker = {label}")
        w(f"  gen = {gen}")
        w(f"  key = {key}")
        w(f"  env = OT6_TIMEOUT={timeout} OT6_CAPTURE_SRM={payload}")
        stamp_edge(cstamp, payload, gen, label, list(RUN_INPUTS),
                   f"build/states/{prev}.stamp", None)
        seal_edge(key)
    w("")
    return mss


def copy_sources(states, root, captures=()):
    """(byte-copied sources, Lua-copied sources) the state edges route
    through copy edges, in first-use order."""
    byte = list(RUN_INPUTS) + [CHECKPOINT_TOOL] + list(COMPOSE_INPUTS)
    byte += [p for p in STAMP_TOOL if p not in byte]
    return byte, list(LIB_FILES)


def write_authored(manifest, out):
    """A tracked manifest minus what a seal writes (size, sha256,
    provenance): the template the graph's capture is sealed against.
    Written only when it changed, so re-cutting the tracked checkpoint from
    the graph's own capture moves nothing (restat)."""
    m = json.loads(Path(manifest).read_text())
    text = json.dumps({k: v for k, v in m.items()
                       if k not in ("size", "sha256", "provenance")},
                      indent=2) + "\n"
    out = Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    if not (out.exists() and out.read_text() == text):
        out.write_text(text)
    return 0


def load(root):
    return runpy.run_path(str(root / GRAPH))["STATES"]


def load_captures(root):
    return runpy.run_path(str(root / GRAPH)).get("CAPTURES", [])


def emit(states, root, captures=()):
    """Standalone build.ninja text for the mock-tree selftests (the real
    tree's graph is configure.py's)."""
    o = []
    w = o.append
    w("# AUTOGENERATED by tools/tests/lib/savestate_ninja.py -- mock-tree "
      "selftests only.")
    w("ninja_required_version = 1.3")
    w("builddir = build/ninja")
    w("")
    w("rule copy_if_changed")
    w("  command = mkdir -p $$(dirname $out) && { cmp -s $in $out || cp $in $out; }")
    w("  description = copy_if_changed $in")
    w("  restat = 1")
    w("")
    w("rule copy_if_lua_changed")
    w("  command = python3 tools/tests/lib/lua_fingerprint.py "
      "copy-if-changed $in $out")
    w("  description = copy_if_lua_changed $in")
    w("  restat = 1")
    w("")
    w("rule copy_if_rom_identity_changed")
    w("  command = python3 tools/build/rom_version.py "
      "copy-if-identity-changed $in $out")
    w("  description = copy_if_rom_identity_changed $in")
    w("  restat = 1")
    w("")
    emit_state_rules(w)
    byte, lua = copy_sources(states, root, captures)
    for src in byte:
        rule = "copy_if_rom_identity_changed" if src == ROM else "copy_if_changed"
        w(f"build {copy_from(src)}: {rule} {src}")
    for src in lua:
        w(f"build {COPY_DIR}/lua/{src}: copy_if_lua_changed {src}")
    w("")
    emit_state_edges(w, states, root, copy_from,
                     lambda p: f"{COPY_DIR}/lua/{p}", captures)
    return "\n".join(o) + "\n"


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", type=Path, default=ROOT)
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--authored", nargs=2, metavar=("MANIFEST", "OUT"),
                    help="write MANIFEST's authored fields to OUT, only "
                         "when they changed (the seal's template)")
    ap.add_argument("--emit", action="store_true",
                    help="write ROOT/build/build.ninja from ROOT's graph "
                         "(the mock-tree selftests)")
    args = ap.parse_args(argv)
    if args.selftest:
        return selftest()
    if args.authored:
        return write_authored(*args.authored)
    root = args.root.resolve()
    states, captures = load(root), load_captures(root)
    errors = validate(states, root, captures)
    if errors:
        for e in errors:
            print(f"savestate_graph: {e}", file=sys.stderr)
        return 1
    if args.emit:
        out = root / "build" / "build.ninja"
        out.parent.mkdir(parents=True, exist_ok=True)
        text = emit(states, root, captures)
        if not (out.exists() and out.read_text() == text):
            out.write_text(text)
        return 0
    ap.print_usage()
    return 2


def selftest():
    """Validation negatives and the shape of what is emitted.  Pure python;
    ninja's own behaviour on the emitted graph is
    savestate_ninja_selftest.sh's."""
    ok = True

    def check(label, cond):
        nonlocal ok
        print(f"  {'pass' if cond else 'FAIL'} {label}")
        ok = ok and cond

    import tempfile
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        for key in ("k1-v1", "k2-v1", "k3-v1", "k4-v1", "seed-v1",
                    "negative-x-v1"):
            d = root / "tools/tests/checkpoints" / key
            d.mkdir(parents=True)
            (d / "manifest.json").write_text("{}")
            (d / f"{key[:-3]}.sram").write_text("x")
        (root / "tools/tests/checkpoints/two-v1").mkdir(parents=True)
        for g in ("gen_ok", "gen_cut", "gen_seed", "gen_q2"):
            (root / f"tools/tests/{g}.lua").write_text("-- ok")
        for g, fx in (("gen_x", "o"), ("gen_y", "x"), ("gen_two", "o")):
            (root / f"tools/tests/{g}.lua").write_text(
                f'H.loadState("build/states/{fx}.mss.lua")')
        (root / "tools/tests/gen_two.lua").write_text(
            'H.loadState("build/states/o.mss.lua")\n'
            'H.loadState("build/states/x.mss.lua")')
        # o boots power-on and saves k1, which p Continues.  A cutter
        # booted from p saves k2, which q and q2 Continue; r Continues k3,
        # which q's own run saves; r's run saves k4, which nothing boots;
        # a capture-only cutter lifts seed-v1 from o.
        (root / "tools/tests/gen_cut.lua").write_text(
            'H.loadState("build/states/p.mss.lua")')

        def s(**kw):
            return dict(kw)
        full = [s(state="o", gen="gen_ok"),
                s(state="p", gen="gen_ok", prev="o", checkpoint="k1-v1"),
                s(state="q", gen="gen_ok", prev="p", checkpoint="k2-v1",
                  cutter="gen_cut"),
                s(state="q2", gen="gen_q2", prev="p", checkpoint="k2-v1",
                  cutter="gen_cut"),
                s(state="r", gen="gen_ok", prev="q", checkpoint="k3-v1",
                  saves="k4-v1", also=["r2"]),
                s(state="x", gen="gen_x", prev="o")]
        caps = [{"capture": "seed-v1", "cutter": "gen_seed", "prev": "o"}]
        READS.clear()
        validate(full, root, caps)
        check("configure-time reads are recorded for the depfile: each "
              "generator whose sidecars it reads, each checkpoint directory",
              {"tools/tests/gen_x.lua", "tools/tests/checkpoints/k1-v1",
               "tools/tests/checkpoints"} <= READS)
        check("a well-formed graph validates",
              validate(full, root, caps) == [])
        bad = [
            ("duplicate state", full + [s(state="o", gen="gen_ok")], caps),
            ("no gen", full + [s(state="z")], caps),
            ("unknown generator", full + [s(state="z", gen="gen_nope")], caps),
            ("prev not earlier", [s(state="z", gen="gen_ok", prev="o")] + full,
             caps),
            ("after= (an order with no dependency)",
             full + [s(state="z", gen="gen_ok", after="o")], caps),
            ("a checkpoint boot with no prev",
             full + [s(state="z", gen="gen_ok", checkpoint="k1-v1")], caps),
            ("a negative fixture",
             full + [s(state="z", gen="gen_ok", prev="o",
                       saves="negative-x-v1")], caps),
            ("a checkpoint with no manifest",
             full + [s(state="z", gen="gen_ok", prev="o",
                       saves="nope-v1")], caps),
            ("a checkpoint with no payload",
             full + [s(state="z", gen="gen_ok", prev="o", saves="two-v1")],
             caps),
            ("cutter off a cut",
             full + [s(state="z", gen="gen_ok", prev="o", cutter="gen_cut")],
             caps),
            ("a missing cutter",
             full[:2] + [s(state="q", gen="gen_ok", prev="p",
                           checkpoint="k2-v1", cutter="gen_nope")] + full[4:],
             caps),
            ("one checkpoint made by two runs",
             full + [s(state="z", gen="gen_ok", prev="o", saves="k4-v1")],
             caps),
            ("one run standing for two checkpoints",
             full[:4] + [s(state="r", gen="gen_ok", prev="q",
                           checkpoint="k3-v1", saves="k4-v1"),
                         s(state="z", gen="gen_ok", prev="q",
                           checkpoint="k4-v1")] + full[5:], caps),
            ("a tracked checkpoint nothing saves (the gate would miss it)",
             full, []),
            ("a capture from an unknown state",
             full, [{"capture": "seed-v1", "cutter": "gen_seed",
                     "prev": "nope"}]),
            ("unknown field", full + [s(state="z", gen="gen_ok", seed="o")],
             caps),
            ("also duplicating a state",
             full + [s(state="z", gen="gen_ok", also=["o"])], caps),
            ("one leg played twice: a second entry with the same generator "
             "and boot (n024_won / esper_tubes_entry)",
             full + [s(state="z", gen="gen_x", prev="o")], caps),
            ("...the same at a cut",
             full + [s(state="z", gen="gen_q2", prev="p", checkpoint="k2-v1",
                       cutter="gen_cut")], caps),
            ("prev= that is not the sidecar the generator embeds",
             full + [s(state="z", gen="gen_y", prev="o")], caps),
            ("a generator that embeds a sidecar with no prev=",
             full + [s(state="z", gen="gen_y")], caps),
            ("a generator that embeds two sidecars",
             full + [s(state="z", gen="gen_two", prev="o")], caps),
            ("a cut whose generator embeds a sidecar besides its capture",
             full + [s(state="z", gen="gen_x", prev="p", checkpoint="k2-v1",
                       cutter="gen_cut")], caps),
        ]
        for label, graph, cs in bad:
            check(f"NEGATIVE {label}", validate(graph, root, cs) != [])

        text = emit(full, root, caps)
        lines = text.splitlines()

        def edge(out):
            return next((l for l in lines if l.startswith(f"build {out}")), "")

        def body(out):
            i = lines.index(edge(out))
            out_ = []
            for l in lines[i + 1:]:
                if not l.startswith("  "):
                    break
                out_.append(l)
            return "\n".join(out_)
        gen_lines = [l for l in lines if ": generate" in l]
        check("every generate edge depends on its digest, the ROM, the "
              "emulator pin and the runner",
              gen_lines and all(all(copy_from(p) in l for p in RUN_INPUTS)
                                and f"{DIGEST_DIR}/" in l for l in gen_lines))
        check("no generate edge depends on a lib file directly (the digest "
              "says whether its program moved)",
              not any(p in l for l in gen_lines for p in LIB_FILES))
        dig = edge(digest_path("p"))
        check("a digest edge depends on every lib file through a Lua copy",
              all(f"{COPY_DIR}/lua/{p}" in dig for p in LIB_FILES))
        check("...and on compose.py, the waiver registry and the symbols",
              all(copy_from(p) in dig for p in COMPOSE_INPUTS))
        check("a digest edge is restat (an unmoved program prunes the run)",
              "rule compose_digest" in text and
              text.split("rule compose_digest")[1].split("rule ")[0]
              .count("restat = 1") == 1)
        check("generate and capture are restat (same bytes stop there)",
              all(text.split(f"rule {r}\n")[1].split("rule ")[0]
                  .count("restat = 1") == 1 for r in ("generate", "capture")))
        dcut = edge(digest_path("q"))
        check("a cut's digest composes with the capture it boots",
              "OT6_SRAM_CHECKPOINT=build/checkpoints/k2-v1" in body(digest_path("q")))
        check("the cutter's digest embeds the state it boots",
              "build/states/p.mss.lua" in edge(digest_path("capture_k2_v1")))
        gp = edge("build/states/p.mss.lua")
        check("the cut boots the graph's capture: its payload and authored "
              "fields are inputs, its sealed manifest orders it",
              "build/checkpoints/k1-v1/k1.sram" in gp
              and f"{AUTHORED_DIR}/k1-v1.json" in gp
              and "|| build/checkpoints/k1-v1/manifest.json" in gp
              and "tools/tests/checkpoints/k1-v1" not in gp)
        check("only a run that Continues a checkpoint depends on its "
              "materialize (sram_checkpoint.py)",
              copy_from(CHECKPOINT_TOOL) in gp
              and copy_from(CHECKPOINT_TOOL) not in edge("build/states/o.mss.lua"))
        check("the cut's run Continues the capture",
              "OT6_SRAM_CHECKPOINT=build/checkpoints/k1-v1" in
              body("build/states/p.mss.lua"))
        go = edge("build/states/o.mss.lua")
        check("the producer's own run captures its battery",
              "build/checkpoints/k1-v1/k1.sram" in go
              and "OT6_CAPTURE_SRM=build/checkpoints/k1-v1/k1.sram" in
              body("build/states/o.mss.lua"))
        cap = edge("build/checkpoints/k2-v1/k2.sram")
        check("a cutter's capture edge runs once though two cuts boot it",
              ": capture |" in cap
              and sum(1 for l in lines
                      if l.startswith("build build/checkpoints/k2-v1/k2.sram")) == 1)
        check("...and publishes no state",
              "OT6_NO_PUBLISH=1" in text.split("rule capture")[1].split("rule ")[0])
        check("a saves= frontier's own run captures its save",
              "build/checkpoints/k4-v1/k4.sram" in edge("build/states/r.mss.lua"))
        check("a capture-only cutter is on the graph",
              ": capture |" in edge("build/checkpoints/seed-v1/seed.sram"))
        seal = edge("build/checkpoints/k1-v1/manifest.json")
        check("the seal reads the payload, the authored fields and the "
              "capture's stamp",
              ": seal build/checkpoints/k1-v1/k1.sram "
              f"{AUTHORED_DIR}/k1-v1.json build/checkpoints/k1-v1.stamp" in seal)
        check("each checkpoint is sealed once",
              sum(1 for l in lines if l.startswith(
                  "build build/checkpoints/k2-v1/manifest.json")) == 1)
        st = edge("build/states/p.stamp")
        check("a stamp is its own edge after the run, naming what it booted",
              ": stamp build/states/p.mss |" in st
              and "--ancestor build/checkpoints/k1-v1.stamp" in
              body("build/states/p.stamp"))
        check("...so the stamp tool is an input of the stamp, not the run",
              "stamps.py" in st and not any("stamps.py" in l for l in gen_lines))
        check("a plain link's stamp names its prev's stamp",
              "--ancestor build/states/o.stamp" in body("build/states/x.stamp"))
        check("an also= sibling has its own stamp edge",
              ": stamp build/states/r2.mss |" in edge("build/states/r2.stamp"))
        check("no edge in the graph names a chain_ copy or a phony alias",
              "chain_" not in text and ": phony" not in text)
        check("generator timeouts default to 1800 s",
              "OT6_TIMEOUT=1800" in body("build/states/o.mss.lua"))
    print("savestate_ninja selftest:", "ok" if ok else "FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
