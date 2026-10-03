#!/usr/bin/env python3
"""stamps.py -- a generated artifact's record, and whether it is current.

Every generated savestate (build/states/<state>.mss) and every capture of a
checkpoint (build/checkpoints/<key>/<payload>) has a stamp beside it,
written by its own ninja edge after the run that made it, from that run's
inputs (savestate_ninja.py):

    ot6-stamp/v3
    generator <gen>              the script the run played, tools/tests/<gen>.lua
    composed <sha256>            compose.py --digest of it, as the run composed it
    env <K>=<V>                  the environment that composition read (0+)
    input <path> <sha256>        each other input of the run, by its bytes: the
                                 ROM (by its identity, the version fields
                                 masked: tools/build/rom_version.py), the
                                 emulator pin, run.sh and the Python it runs,
                                 and at a cut the capture it Continued
    source <path> <sha256>       the generator and each lib file, by Lua token
                                 stream: a record, so a message can say which
                                 one moved
    artifact <path> <sha256>     what the run made
    ancestor <path>              the stamp of what the run booted (none for a
                                 power-on root)
    emulator <sha256|unknown>    the Mesen executable that ran: a record

A stamp is CURRENT when composing its generator now gives the recorded
digest, every input hashes as recorded, the artifact is the recorded bytes,
and its ancestor is current too.  That is the question ninja's graph
answers by the same inputs, so after a `ninja` that builds a state its
stamp is current, and anything else is what the next `ninja` would
regenerate.  The verdicts:

    FRESH       current
    STALE       an input moved (the ROM, the composed script, the runner,
                the capture it booted), or the state it grew from is not
                current (`STALE via <ancestor>`); ninja regenerates it
    UNBOUND     the artifact is not the bytes the stamp records, or the
                stamp is not one this tool writes; ninja regenerates it
    UNVERIFIED  the tree has no build/ot6.sfc to compare against

Usage:
    stamps.py write OUT --generator G --digest D --artifact A
              [--input P]... [--ancestor S] [--emulator-of F]
    stamps.py --check-states     # every graph fixture and capture; exit 1 if
                                 # any is not current
    stamps.py --status NAME...   # one line per state (or build/checkpoints/<key>)
    stamps.py --selftest
"""

import hashlib
import importlib.util
import os
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent.parent
sys.path.insert(0, str(HERE))
import compose  # noqa: E402
import lua_fingerprint  # noqa: E402
sys.path.insert(0, str(HERE.parent.parent / "build"))
import rom_version  # noqa: E402

FORMAT = "ot6-stamp/v3"
LIB_FILES = ("tools/tests/lib/ot6.lua", "tools/tests/lib/ot6_field.lua",
             "tools/tests/lib/ot6_contract.lua")
ROM = "build/ot6.sfc"
FRESH, STALE, UNBOUND, UNVERIFIED = "fresh", "stale", "unbound", "unverified"


def input_hash(rel, path):
    """What a stamp records for one input: the ROM by its identity (the
    copy ninja compares it by), anything else by its bytes."""
    if rel == ROM:
        return rom_version.identity(Path(path).read_bytes())
    return sha256_file(path)


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


# ------------------------------------------------------------------ write --
def emulator_record(path):
    """The sha in run.sh's `[emulator] <sha256> ...` line beside a .mss, or
    'unknown'."""
    try:
        m = re.match(r"\[emulator\] ([0-9a-f]{64}) ", Path(path).read_text())
        return m.group(1) if m else "unknown"
    except OSError:
        return "unknown"


def stamp_text(root, generator, digest_file, artifact, inputs, ancestor=None,
               emulator_of=None):
    root = Path(root)
    rec = (root / digest_file).read_text().splitlines()
    lines = [FORMAT, f"generator {generator}", f"composed {rec[0]}"]
    lines += [l for l in rec[1:] if l.startswith("env ")]
    for p in inputs:
        lines.append(f"input {p} {input_hash(p, root / p)}")
    for p in [f"tools/tests/{generator}.lua", *LIB_FILES]:
        lines.append(f"source {p} {lua_fingerprint.filehash(root / p)}")
    lines.append(f"artifact {artifact} {sha256_file(root / artifact)}")
    if ancestor:
        lines.append(f"ancestor {ancestor}")
    lines.append(f"emulator {emulator_record(root / emulator_of) if emulator_of else 'unknown'}")
    return "\n".join(lines) + "\n"


def write(root, out, **kw):
    text = stamp_text(root, **kw)
    out = Path(root) / out
    if not (out.exists() and out.read_text() == text):
        tmp = out.with_name(out.name + ".tmp")
        tmp.write_text(text)
        os.replace(tmp, out)
    return 0


# ------------------------------------------------------------------ check --
def stamp_path(name, root):
    """A state name, `<state>.mss.lua`, or a stamp's tree path -> the stamp."""
    if name.endswith(".stamp"):
        return Path(root) / name
    if name.endswith(".mss.lua"):
        name = name[:-len(".mss.lua")]
    return Path(root) / "build" / "states" / f"{name}.stamp"


def label(path, root):
    rel = str(Path(path).relative_to(root))
    m = re.fullmatch(r"build/states/(.+)\.stamp", rel)
    return m.group(1) if m else rel[:-len(".stamp")]


def regen_hint(artifact):
    if artifact.startswith("build/states/") and artifact.endswith(".mss"):
        return f"ninja {artifact}.lua"
    return f"ninja {artifact}"


def parse(text):
    rec = {"env": {}, "input": [], "source": []}
    lines = text.splitlines()
    rec["format"] = lines[0] if lines else ""
    for line in lines[1:]:
        k, _, rest = line.partition(" ")
        if k == "env":
            a, _, b = rest.partition("=")
            rec["env"][a] = b
        elif k in ("input", "source"):
            p, _, h = rest.rpartition(" ")
            rec[k].append((p, h))
        elif k == "artifact":
            p, _, h = rest.rpartition(" ")
            rec["artifact"] = (p, h)
        else:
            rec[k] = rest
    return rec


def stamp_status(name, root=ROOT, memo=None):
    """(verdict, message) for one stamp; (None, None) when there is no stamp
    or its generator is gone.  `memo` shares compositions, file hashes and
    verdicts across calls (a whole-tree check composes each script once)."""
    memo = {} if memo is None else memo
    root = Path(root)
    path = stamp_path(name, root)
    return _status(path, root, memo, set())[:2]


def _status(path, root, memo, active):
    verdicts = memo.setdefault("verdict", {})
    if path in verdicts:
        return verdicts[path]
    if path in active:                      # a cycle passes nothing down
        return (None, None, [])
    active.add(path)
    v = _own(path, root, memo)
    if v[0] == FRESH:
        anc = memo["anc"].get(path)
        if anc:
            a = _status(root / anc, root, memo, active)
            if a[0] in (STALE, UNBOUND):
                chain = [root / anc] + a[2]       # stamp paths, down the line
                last = verdicts[chain[-1]][0]
                v = (STALE, f"{label(path, root)} is STALE via "
                            f"{' <- '.join(label(c, root) for c in chain)} -- "
                            f"its own record verifies, but it grew from a "
                            f"state that is not current ({label(chain[-1], root)} "
                            f"is {last.upper()}); regenerate: "
                            f"{memo['hint'][path]}", chain)
    active.discard(path)
    verdicts[path] = v
    return v


# Across calls in one process (live.py asks every few seconds while a
# build publishes), a file's hash and a script's composition are kept while
# the files they were computed from keep their (mtime, size): a long-lived
# caller recomposes only the scripts whose inputs moved.
_HASHES, _COMPOSED = {}, {}


def _stat(path):
    try:
        st = os.stat(path)
        return (st.st_mtime_ns, st.st_size)
    except OSError:
        return None


def _hash(root, rel, memo):
    hs = memo.setdefault("hash", {})
    if rel not in hs:
        p = root / rel
        key = (str(p), _stat(p))
        if key not in _HASHES:
            _HASHES[key] = input_hash(rel, p) if key[1] else None
        hs[rel] = _HASHES[key]
    return hs[rel]


def _compose_reads(root, gen, env):
    """The files composing `gen` reads, by compose.py's own rules."""
    script = root / "tools" / "tests" / f"{gen}.lua"
    files = [script, *(root / p for p in LIB_FILES),
             HERE / "compose.py", HERE / "lua_fingerprint.py",
             root / "tools" / "state_write_waivers.txt",
             Path(env.get("OT6_DBG") or root / "ff6" / "rom" / "ff6-en.dbg")]
    try:
        refs = re.findall(r'"([^"]+\.mss\.lua)"', script.read_text())
    except OSError:
        refs = []
    files += [root / "build" / "states" / Path(r).name for r in refs]
    return files


def _composed(root, gen, env, memo):
    cs = memo.setdefault("composed", {})
    key = (gen, tuple(sorted(env.items())))
    if key not in cs:
        fp = (str(root), key, tuple((str(f), _stat(f))
                                    for f in _compose_reads(root, gen, env)))
        if fp not in _COMPOSED:
            try:
                text, _ = compose.compose_script(
                    root / "tools" / "tests" / f"{gen}.lua", root, env)
                _COMPOSED[fp] = (compose.composed_digest(text), None)
            except (compose.ComposeError, OSError, ValueError) as e:
                _COMPOSED[fp] = (None, str(e).splitlines()[0])
        cs[key] = _COMPOSED[fp]
    return cs[key]


def _own(path, root, memo):
    memo.setdefault("anc", {})
    memo.setdefault("hint", {})
    me = label(path, root)
    try:
        text = path.read_text()
    except OSError:
        return (None, None, [])
    rec = parse(text)
    art = rec.get("artifact")
    v3 = rec["format"] == FORMAT and art and art[0] and "generator" in rec
    hint = (regen_hint(art[0]) if v3 else
            f"ninja build/states/{me}.mss.lua" if "/" not in me else
            f"ninja {me}")
    memo["hint"][path] = hint
    if not v3:
        return (UNBOUND, f"{me} is UNBOUND -- its stamp is not an {FORMAT} "
                         f"record (written by an older harness), so nothing "
                         f"ties its bytes to its inputs; regenerate: {hint}", [])
    gen = rec["generator"]
    if not (root / "tools" / "tests" / f"{gen}.lua").exists():
        return (None, None, [])
    if rec.get("ancestor"):
        memo["anc"][path] = rec["ancestor"]
    # the ROM first: a ROM change moves every stamp at once, one cause
    for p, h in rec["input"]:
        if p != ROM:
            continue
        now = _hash(root, p, memo)
        if now is None:
            return (UNVERIFIED, f"{me} is UNVERIFIED -- it was generated on "
                                f"ROM identity {h[:12]} but this tree has no {ROM} "
                                f"to compare against; build it (ninja {ROM}) "
                                f"and re-check", [])
        if now != h:
            return (STALE, f"{me} is STALE -- generated on ROM identity "
                           f"{h[:12]}, but {ROM} is {now[:12]}: a machine snapshot "
                           f"of a different ROM; regenerate: {hint}", [])
    for p, h in rec["input"]:
        if p == ROM:
            continue
        now = _hash(root, p, memo)
        if now != h:
            what = "is gone" if now is None else f"moved ({h[:12]} -> {now[:12]})"
            return (STALE, f"{me} is STALE -- its input {p} {what}; "
                           f"regenerate: {hint}", [])
    digest, err = _composed(root, gen, rec["env"], memo)
    if digest is None:
        return (STALE, f"{me} is STALE -- {gen} no longer composes ({err}); "
                       f"regenerate: {hint}", [])
    if digest != rec.get("composed"):
        moved = [p for p, h in rec["source"]
                 if (root / p).exists() and lua_fingerprint.filehash(root / p) != h]
        why = (", ".join(moved) + " moved" if moved else
               "an embedded state, the write gate, a symbol or compose.py's "
               "output moved")
        return (STALE, f"{me} is STALE -- its composed script changed "
                       f"({why}); regenerate: {hint}", [])
    ap = root / art[0]
    if not ap.exists():
        return (UNBOUND, f"{me} is UNBOUND -- its stamp exists but {art[0]} "
                         f"does not; regenerate: {hint}", [])
    now = _hash(root, art[0], memo)
    if now != art[1]:
        return (UNBOUND, f"{me} is UNBOUND -- {art[0]} (sha {now[:12]}) is not "
                         f"the artifact its stamp records (sha {art[1][:12]}): "
                         f"it was replaced without a run; regenerate: {hint}", [])
    return (FRESH, None, [])


# --------------------------------------------------------- whole tree ------
def _graph(root):
    path = Path(root) / "tools" / "tests" / "savestate_graph.py"
    try:
        spec = importlib.util.spec_from_file_location("savestate_graph", path)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return list(mod.STATES), list(getattr(mod, "CAPTURES", []))
    except Exception:
        return [], []


def declared_states(root):
    """Fixture names in this tree's graph, also= siblings included, in play
    order."""
    states, _ = _graph(root)
    out = []
    for e in states:
        out.append(e["state"])
        out += list(e.get("also") or [])
    return out


def declared_stamps(root):
    """Every stamp the graph writes: one per state, one per capture."""
    states, captures = _graph(root)
    out = [f"build/states/{n}.stamp" for n in declared_states(root)]
    keys = {e["checkpoint"] for e in states if e.get("checkpoint")}
    keys |= {e["saves"] for e in states if e.get("saves")}
    keys |= {c["capture"] for c in captures}
    out += [f"build/checkpoints/{k}.stamp" for k in sorted(keys)]
    return out


def check_states(root=ROOT):
    """--check-states: every stamp the graph writes, asked the same
    question.  Exit 0 = all current; 1 = some are not."""
    root = Path(root)
    stamps = [s for s in declared_stamps(root) if (root / s).exists()]
    if not stamps:
        print("no generated fixtures in this tree (build/states is "
              "unseeded); ninja generates them")
        return 0
    memo, bad = {}, []
    for s in stamps:
        v, msg = stamp_status(s, root, memo)
        if v in (STALE, UNBOUND, UNVERIFIED):
            bad.append(msg)
    missing = len(declared_stamps(root)) - len(stamps)
    tail = f"; {missing} not generated yet" if missing else ""
    if not bad:
        print(f"fixtures: {len(stamps)}/{len(stamps)} current (composed "
              f"script, inputs, artifact and ancestor all verify){tail}")
        return 0
    kinds = {}
    for m in bad:
        k = m.split(" is ", 1)[1].split(" ", 1)[0]
        kinds[k] = kinds.get(k, 0) + 1
    print(f"fixtures: {len(bad)} of {len(stamps)} are not current ("
          + ", ".join(f"{n} {k}" for k, n in sorted(kinds.items())) + f"){tail}")
    rom = sum(1 for m in bad if "a machine snapshot of a different ROM" in m)
    if rom:
        print(f"CAUSE: the ROM changed since they were generated ({rom} of "
              f"{len(stamps)}); that is one cause, not {rom} problems.")
    unv = sum(1 for m in bad if " is UNVERIFIED " in m)
    if unv:
        print(f"CAUSE: this tree has no built ROM to compare against ({unv} "
              f"of {len(stamps)} are UNVERIFIED, not known stale).  ninja "
              f"{ROM}, then re-check.")
    via = sum(1 for m in bad if " is STALE via " in m)
    if via:
        print(f"CAUSE: {via} of {len(stamps)} are stale only through what "
              f"they grew from (the `via` chain names the link that moved).")
    for m in bad[:6]:
        print(f"  {m}")
    if len(bad) > 6:
        print(f"  ... and {len(bad) - 6} more, same shape")
    print("\nninja regenerates exactly these (and what depends on them): "
          "nice ninja, or ninja <one of the paths above>")
    return 1


# --------------------------------------------------------------- selftest --
def selftest():
    import tempfile
    ok = True

    def check(label_, got, want):
        nonlocal ok
        good = got == want
        ok = ok and good
        print(f"  {'pass' if good else 'FAIL'} {label_}"
              + ("" if good else f"\n       got  {got!r}\n       want {want!r}"))

    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        (root / "tools/tests/lib").mkdir(parents=True)
        (root / "build/states").mkdir(parents=True)
        (root / "build/checkpoints/k-v1").mkdir(parents=True)
        (root / "build/ninja/digest").mkdir(parents=True)
        lib = root / "tools/tests/lib"
        (lib / "ot6.lua").write_text("local M = {}\nM.v = 1\nreturn M\n")
        (lib / "ot6_field.lua").write_text("local M = ...\n")
        (lib / "ot6_contract.lua").write_text("local M = ...\n")
        (root / "tools/tests/run.sh").write_text("run v1\n")
        (root / "build/ot6.sfc").write_bytes(b"rom v1")
        (root / "tools/tests/gen_a.lua").write_text(
            'local H = dofile("tools/tests/lib/ot6.lua")\nH.run({}, {})\n')
        (root / "tools/tests/gen_b.lua").write_text(
            'local H = dofile("tools/tests/lib/ot6.lua")\n'
            'H.run({}, { H.loadState("build/states/a.mss.lua") })\n')
        (root / "tools/tests/gen_c.lua").write_text(
            'local H = dofile("tools/tests/lib/ot6.lua")\nH.run({}, {})\n')
        inputs = ["build/ot6.sfc", "tools/tests/run.sh"]

        def run(state, gen, ancestor=None, env=None, extra=()):
            env = env or {}
            st = root / "build/states"
            (st / f"{state}.mss").write_bytes(f"{state} bytes".encode())
            (st / f"{state}.mss.lua").write_text('return "%s"\n' % (
                __import__("base64").b64encode(f"{state} bytes".encode()).decode()))
            d = root / f"build/ninja/digest/{state}.digest"
            compose.main_digest(root / f"tools/tests/{gen}.lua", d, root, env)
            write(root, f"build/states/{state}.stamp", generator=gen,
                  digest_file=str(d.relative_to(root)),
                  artifact=f"build/states/{state}.mss",
                  inputs=inputs + list(extra), ancestor=ancestor)

        def st(name):
            return stamp_status(name, root)

        run("a", "gen_a")
        run("b", "gen_b", "build/states/a.stamp")
        check("a fresh record is FRESH", st("a"), (FRESH, None))
        check("...by either name form", st("b.mss.lua"), (FRESH, None))
        text = (root / "build/states/a.stamp").read_text()
        check("the record leads with its format", text.splitlines()[0], FORMAT)
        # the ROM
        (root / "build/ot6.sfc").write_bytes(b"rom v2")
        v, m = st("a")
        check("MUTANT a ROM change is STALE", v, STALE)
        check("...named as a different ROM",
              "a machine snapshot of a different ROM" in (m or ""), True)
        (root / "build/ot6.sfc").unlink()
        check("no built ROM is UNVERIFIED", st("a")[0], UNVERIFIED)
        (root / "build/ot6.sfc").write_bytes(b"rom v1")
        check("restoring the ROM restores FRESH", st("a"), (FRESH, None))
        # the runner, any input by its bytes
        (root / "tools/tests/run.sh").write_text("run v2\n")
        v, m = st("a")
        check("MUTANT a runner change is STALE, naming it",
              (v, "tools/tests/run.sh moved" in (m or "")), (STALE, True))
        (root / "tools/tests/run.sh").write_text("run v1\n")
        # the lib: no exemption -- a code edit is a change like any other
        (lib / "ot6.lua").write_text("local M = {}\nM.v = 2\nreturn M\n")
        v, m = st("a")
        check("MUTANT a lib code edit is STALE (no provenance-drift exemption)",
              v, STALE)
        check("...naming the lib file that moved",
              "tools/tests/lib/ot6.lua moved" in (m or ""), True)
        (lib / "ot6.lua").write_text("-- note\nlocal M = {}\n  M.v = 1\nreturn M\n")
        check("a lib comment/whitespace edit leaves it FRESH", st("a"),
              (FRESH, None))
        (lib / "ot6.lua").write_text("local M = {}\nM.v = 1\nreturn M\n")
        # the generator
        (root / "tools/tests/gen_a.lua").write_text(
            'local H = dofile("tools/tests/lib/ot6.lua")\nH.run({ x = 1 }, {})\n')
        check("MUTANT a generator code edit is STALE", st("a")[0], STALE)
        v, m = st("b")
        check("...and its child is STALE via it",
              (v, "STALE via a" in (m or "")), (STALE, True))
        (root / "tools/tests/gen_a.lua").write_text(
            'local H = dofile("tools/tests/lib/ot6.lua")\nH.run({}, {})\n')
        check("restoring the generator restores the chain", st("b"),
              (FRESH, None))
        # the artifact
        (root / "build/states/a.mss").write_bytes(b"swapped")
        check("MUTANT replaced bytes are UNBOUND", st("a")[0], UNBOUND)
        check("...and the child is STALE via it", st("b")[0], STALE)
        (root / "build/states/a.mss").write_bytes(b"a bytes")
        # an embedded state regenerated to other bytes moves the child's
        # composition even though the child's own sources did not move
        (root / "build/states/a.mss.lua").write_text('return "QUJD"\n')
        v, m = st("b")
        check("MUTANT a regenerated parent sidecar stales the child",
              (v, "its composed script changed" in (m or "")), (STALE, True))
        run("a", "gen_a")
        check("a parent regenerated to the same bytes leaves the child FRESH",
              st("b"), (FRESH, None))
        # a cut: the capture it booted is an input
        pay = root / "build/checkpoints/k-v1/k.sram"
        pay.write_bytes(b"battery v1")
        run("c", "gen_c", "build/checkpoints/k-v1.stamp",
            env={"OT6_SRAM_CHECKPOINT": "build/checkpoints/k-v1"},
            extra=["build/checkpoints/k-v1/k.sram"])
        write(root, "build/checkpoints/k-v1.stamp", generator="gen_a",
              digest_file="build/ninja/digest/a.digest",
              artifact="build/checkpoints/k-v1/k.sram", inputs=inputs,
              ancestor="build/states/a.stamp")
        check("a cut's record is FRESH", st("c"), (FRESH, None))
        check("...and records the environment it composed under",
              "env OT6_SRAM_CHECKPOINT=build/checkpoints/k-v1" in
              (root / "build/states/c.stamp").read_text(), True)
        check("a capture's record is FRESH",
              st("build/checkpoints/k-v1.stamp"), (FRESH, None))
        pay.write_bytes(b"battery v2")
        v, m = st("c")
        check("MUTANT a moved capture stales the cut that Continues it",
              (v, "build/checkpoints/k-v1/k.sram" in (m or "")), (STALE, True))
        # format: an older stamp is not trusted
        (root / "build/states/a.stamp").write_text(
            "deadbeef gen_a\nrom x\ngenerator y\nartifact z\n")
        check("MUTANT a pre-v3 stamp is UNBOUND", st("a")[0], UNBOUND)
        check("a missing stamp has nothing to say", st("zz"), (None, None))
    print("stamps selftest:", "ok" if ok else "FAILED")
    return 0 if ok else 1


def main(argv):
    if argv == ["--selftest"]:
        return selftest()
    if argv == ["--check-states"]:
        return check_states(ROOT)
    if argv and argv[0] == "--status":
        memo, rc = {}, 0
        for n in argv[1:]:
            v, m = stamp_status(n, ROOT, memo)
            print(f"{n}: {v or 'no stamp'}" + (f" -- {m}" if m else ""))
            rc |= v not in (FRESH, None)
        return rc
    if argv and argv[0] == "write":
        import argparse
        ap = argparse.ArgumentParser(prog="stamps.py write")
        ap.add_argument("out")
        ap.add_argument("--generator", required=True)
        ap.add_argument("--digest", required=True)
        ap.add_argument("--artifact", required=True)
        ap.add_argument("--input", action="append", default=[])
        ap.add_argument("--ancestor")
        ap.add_argument("--emulator-of")
        a = ap.parse_args(argv[1:])
        return write(ROOT, a.out, generator=a.generator, digest_file=a.digest,
                     artifact=a.artifact, inputs=a.input, ancestor=a.ancestor,
                     emulator_of=a.emulator_of)
    print(__doc__.split("Usage:")[1].strip(), file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
