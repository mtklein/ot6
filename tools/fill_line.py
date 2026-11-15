#!/usr/bin/env python3
"""fill_line.py -- replay the line from power-on under a power-on RAM fill.

The line is deterministic, and the harness powers on with every RAM zeroed.
Replayed with WRAM, the battery and the PPU/APU RAMs filled with something
else first (OT6_POWERON_FILL, lib/poweron_fill.lua), every observable result
must come out the same; any difference means the game read memory it never
wrote.  tools/fill_diff.py compares the two.

A fill run's states are not the line's, so they live in a tree of their own:
a clone (not a worktree, so tools/worktree-setup.sh never seeds from it) at
this tree's commit, with build/FILL_TREE naming the mode.  compose.py honours
OT6_POWERON_FILL only there, and there it refuses any run that does not
declare the same mode.  Nothing in a fill tree is qualification evidence.

    tools/fill_line.py setup DIR --mode ones|alt|rand:<seed>|zero
    tools/fill_line.py run DIR [--until STATE] [TARGET...]
    tools/fill_line.py sync DIR          # move DIR to this tree's commit
    tools/fill_line.py --selftest        # the fence, without an emulator

A mode may name the RAMs it fills after an @ (ones@wram,sram,spc; the
default is wram,sram).  `lab` marks a tree for experiments: each run there
declares its own mode.  `zero` is the reference: a fresh replay with no fill, fenced the same way
(the proof that the fill machinery leaves a plain run's bytes alone).  `run`
replays the line up to --until (default: the whole line, `chain`) in DIR
with OT6_POWERON_FILL set, logs to DIR/build/fill-run.log and writes
DIR/build/FILL_DONE (`rc=N`) when ninja exits.  Run it detached:

    setsid nohup systemd-inhibit --what=idle --who=ot6 --why=fills \\
        python3 tools/fill_line.py run DIR > DIR.out 2>&1 < /dev/null &
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ROM = "Final Fantasy III (USA).sfc"
MARKER = "build/FILL_TREE"
sys.path.insert(0, str(ROOT / "tools/tests/lib"))
import compose  # noqa: E402  (the fence and the mode's grammar live there)


def valid_mode(mode):
    if mode in ("zero", "lab"):
        return True
    try:
        compose._fill_lines(mode, "lab", {})
        return True
    except ValueError:
        return False


def sh(cmd, **kw):
    print("+", " ".join(str(c) for c in cmd), flush=True)
    subprocess.run(cmd, check=True, **kw)


def setup(args):
    d = Path(args.dir).resolve()
    if not valid_mode(args.mode):
        sys.exit(f"--mode {args.mode!r}: expected ones, alt, rand:<seed>, "
                 f"zero or lab (compose.py's OT6_POWERON_FILL grammar)")
    if d.exists():
        sys.exit(f"{d} exists; a fill tree starts empty (remove it first)")
    sha = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, check=True,
                         capture_output=True, text=True).stdout.strip()
    sh(["git", "clone", "--quiet", "--shared", "--no-checkout", str(ROOT), str(d)])
    sh(["git", "-C", str(d), "checkout", "--quiet", "--detach", sha])
    shutil.copy2(ROOT / ROM, d / ROM)
    mesen = "Mesen.app" if sys.platform == "darwin" else "Mesen-linux"
    for rel in (f"tools/{mesen}", "tools/bin"):
        src = (ROOT / rel).resolve()
        if src.exists():
            os.symlink(src, d / rel)
    (d / "build").mkdir()
    (d / MARKER).write_text(args.mode + "\n")
    sh([sys.executable, "configure.py"], cwd=d, stdout=subprocess.DEVNULL)
    print(f"fill tree {d}: mode {args.mode}, commit {sha[:12]}, no seeded "
          f"states (the line replays from power-on)")


def sync(args):
    """Move a fill tree to this tree's commit (its states then go stale
    and replay, as anywhere)."""
    d = Path(args.dir).resolve()
    if not (d / MARKER).exists():
        sys.exit(f"{d} is not a fill tree (no {MARKER})")
    sha = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, check=True,
                         capture_output=True, text=True).stdout.strip()
    sh(["git", "-C", str(d), "fetch", "--quiet", str(ROOT), sha])
    sh(["git", "-C", str(d), "checkout", "--quiet", "--detach", sha])
    # A fill run's states record nothing about the fill (its pattern, its
    # waivers), so a moved fill tree replays from power-on: its states go.
    for sub in ("states", "checkpoints", "ninja"):
        shutil.rmtree(d / "build" / sub, ignore_errors=True)
    sh([sys.executable, "configure.py"], cwd=d, stdout=subprocess.DEVNULL)


def run(args):
    d = Path(args.dir).resolve()
    mode = (d / MARKER).read_text().strip()
    targets = list(args.targets)
    if args.until:
        targets.append(f"build/states/{args.until}.mss.lua")
    if not targets:
        targets = ["chain"]
    env = dict(os.environ, OT6_POWERON_FILL=mode)
    log = d / "build" / "fill-run.log"
    done = d / "build" / "FILL_DONE"
    done.unlink(missing_ok=True)
    t0 = time.time()
    with open(log, "a") as f:
        f.write(f"[fill_line] {time.strftime('%Y-%m-%d %H:%M:%S')} mode={mode} "
                f"targets={' '.join(targets)}\n")
        f.flush()
        rc = subprocess.run(["nice", "ninja", "-k", "0", *targets], cwd=d,
                            env=env, stdout=f, stderr=subprocess.STDOUT).returncode
        f.write(f"[fill_line] rc={rc} wall={time.time() - t0:.0f}s\n")
    done.write_text(f"rc={rc} wall={time.time() - t0:.0f}s\n")
    print(done.read_text(), end="")
    return rc


def selftest(_args=None):
    """The fence and the grammar, with no emulator: compose.py's prologue
    in a plain tree, a fill tree and a lab tree."""
    import tempfile
    fails = []

    def check(what, ok):
        print(("  pass  " if ok else "  FAIL  ") + what)
        if not ok:
            fails.append(what)

    def prologue(tree, env):
        try:
            return compose.poweron_fill_prologue(tree, env)
        except ValueError as why:
            return why

    with tempfile.TemporaryDirectory() as t:
        plain, fill, lab = (Path(t, n) for n in ("plain", "fill", "lab"))
        for d, mark in ((plain, None), (fill, "rand:9"), (lab, "lab")):
            (d / "build").mkdir(parents=True)
            if mark:
                (d / MARKER).write_text(mark + "\n")
        check("a plain run in a plain tree composes nothing extra", prologue(plain, {}) == [])
        check("a fill declared in a plain tree is refused",
              isinstance(prologue(plain, {"OT6_POWERON_FILL": "ones"}), ValueError))
        check("the read-before-write instrument is refused in a plain tree",
              isinstance(prologue(plain, {"OT6_RBW": "1"}), ValueError))
        check("a fill tree refuses a run that declares no fill",
              isinstance(prologue(fill, {}), ValueError))
        check("a fill tree refuses another mode",
              isinstance(prologue(fill, {"OT6_POWERON_FILL": "ones"}), ValueError))
        got = prologue(fill, {"OT6_POWERON_FILL": "rand:9"})
        check("a fill tree's own mode fills, the fill code first after its globals",
              isinstance(got, list) and got[0] == 'OT6_FILL_MODE = "rand"\n'
              and "OT6_FILL_SEED = 9\n" in got and "emu.write" in got[-1])
        check("the waivers' offsets are left zero in a whole-region fill",
              isinstance(got, list) and "except = true" in got[2] and "0x1F6E" in got[2])
        got = prologue(fill, {"OT6_POWERON_FILL": "rand:9",
                              "OT6_SRAM_CHECKPOINT": "build/checkpoints/x"})
        check("a run handed a battery does not fill the battery",
              isinstance(got, list) and "sram" not in got[2])
        got = prologue(lab, {"OT6_POWERON_FILL": "alt@wram:1D54+1FD3-1FF2"})
        check("a lab tree takes any mode, and a bisection's ranges",
              isinstance(got, list) and "{0x1D54, 0x1D54}, {0x1FD3, 0x1FF2}" in got[2])
        got = prologue(lab, {"OT6_RBW": "1"})
        check("a lab run of the instrument alone fills nothing",
              isinstance(got, list) and len(got) == 2 and "OT6_RBW_SRAM = true" in got[0])
        check("a malformed mode is refused",
              isinstance(prologue(lab, {"OT6_POWERON_FILL": "ones@bogus"}), ValueError))
        zero = Path(t, "zero")
        (zero / "build").mkdir(parents=True)
        (zero / MARKER).write_text("zero\n")
        check("the zero reference composes exactly as a plain run",
              prologue(zero, {"OT6_POWERON_FILL": "zero"}) == [])
    check("valid_mode agrees with compose", valid_mode("rand:3@wram,spc") and not valid_mode("twos"))
    print("fill_line selftest: " + ("OK" if not fails else f"{len(fails)} FAILURE(S)"))
    return 1 if fails else 0


def main():
    if sys.argv[1:] == ["--selftest"]:
        return selftest()
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("setup")
    s.add_argument("dir")
    s.add_argument("--mode", required=True)
    y = sub.add_parser("sync")
    y.add_argument("dir")
    r = sub.add_parser("run")
    r.add_argument("dir")
    r.add_argument("--until")
    r.add_argument("targets", nargs="*")
    args = ap.parse_args()
    return {"setup": setup, "sync": sync, "run": run}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main() or 0)
