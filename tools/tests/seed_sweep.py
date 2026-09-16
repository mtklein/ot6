#!/usr/bin/env python3
"""seed_sweep.py -- regenerate one state K times on K different boot seeds.

    python3 tools/tests/seed_sweep.py dadaluma_entry --seeds 8 [--jobs 2]

Runs are bit-reproducible, so a segment that passes on its one seed has
proved one seed.  A route change upstream (buying more Potions, a grind)
moves every later encounter, NPC walk and back-attack roll, and only then
does the segment show whether it was robust or lucky (#179, #185).  This
runner asks that question BEFORE a route change exposes it: it composes the
state's generator exactly as the ninja graph would (its fixture or
checkpoint, its timeout) and runs it K times, each with a different
OT6_SEED_SHIFT -- idle frames the segment runner (lib/ot6.lua) inserts at
the boot point, which is what a player who paused a beat longer before
walking on would have done -- with the lib's own retries turned OFF
(OT6_RETRIES=1) so every seed reports its first-try outcome.

Nothing is published: every run's artifacts and log go to the sweep's own
directory (default build/sweeps/<state>-<stamp>/), never build/states, and
every failed run's workspace is retained under build/test-runs.  The table
printed at the end (and written as summary.tsv) has one row per seed:
shift, verdict, frames, failure class, message.  A sweep with 8 PASSes says
the segment held on 8 seeds; a sweep with one FAIL says which seed and what
class -- that failure is the finding, and its log and screenshots are kept.

Seeds: K shifts spread across the 60-frame battle seed period ($021e; see
newSeedLadder in lib/ot6.lua), so every attempt seeds its first battle from
a distinct phase.  --step overrides the spacing.
"""
import argparse
import concurrent.futures
import datetime
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "tests"))

VERDICT_PASS = re.compile(r"^\[ot6\] PASS \(frame (\d+)\)(?: attempts=(\d+)/(\d+))?")
VERDICT_FAIL = re.compile(r"^\[ot6\] FAIL: (.*)")
ATTEMPT = re.compile(r"^\[ot6\] \[retry\] attempt (\d+)/(\d+) FAILED class=(\S+) "
                     r"frame=(\d+) totalframes=(\d+) shift=(-?\d+) phase=(\d+)"
                     r"(?: screenshot=(\S+))?: (.*)")


def load_graph():
    ns = {}
    exec((ROOT / "tools/tests/savestate_graph.py").read_text(), ns)
    return {e["state"]: e for e in ns["STATES"]}, ns["STATES"]


def entry_for(state):
    by_name, states = load_graph()
    if state in by_name:
        return by_name[state]
    for e in states:                       # an `also=` sibling
        if state in (e.get("also") or []):
            return e
    sys.exit(f"seed_sweep: {state!r} is not a state in tools/tests/savestate_graph.py")


def parse_log(path):
    verdict, frames, cls, msg, attempts = "NONE", None, "", "", ""
    fail_msg = None
    if not path.exists():
        return dict(verdict="NONE", frames="", cls="norun", msg="no log",
                    attempts="")
    for line in path.read_text(errors="replace").splitlines():
        m = ATTEMPT.match(line)
        if m:
            cls, frames, msg = m.group(3), int(m.group(4)), m.group(9)
            attempts = f"{m.group(1)}/{m.group(2)}"
            continue
        m = VERDICT_PASS.match(line)
        if m:
            verdict, frames = "PASS", int(m.group(1))
            if m.group(2):
                attempts = f"{m.group(2)}/{m.group(3)}"
            cls, msg = "", ""
            continue
        m = VERDICT_FAIL.match(line)
        if m:
            verdict = "FAIL"
            fail_msg = m.group(1)
    if verdict == "FAIL" and not cls:
        cls, msg = "other", fail_msg or ""
    if verdict == "NONE":
        cls, msg = "noverdict", "no PASS/FAIL line (killed by the wall clock, or a load error)"
    return dict(verdict=verdict, frames="" if frames is None else frames,
                cls=cls, msg=msg, attempts=attempts)


def run_one(k, shift, gen, env_extra, outdir, timeout, state):
    log = outdir / f"{state}.seed{k:02d}.log"
    art = outdir / f"seed{k:02d}"
    art.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    env.update(env_extra)
    env.update({
        "OT6_SEED_SHIFT": str(shift),
        "OT6_RETRIES": "1",
        "OT6_NO_PUBLISH": "1",
        "OT6_ARTIFACT_DIR": str(art),
        "OT6_KEEP_RUNS": "1",
        "OT6_WORKER": f"sweep_{state}_{k:02d}",
        "OT6_TIMEOUT": str(timeout),
        "OT6_LIVE": env.get("OT6_LIVE", "0"),
    })
    with open(outdir / f"{state}.seed{k:02d}.out", "w") as out:
        rc = subprocess.run(["sh", str(ROOT / "tools/tests/run.sh"),
                             f"tools/tests/{gen}.lua", str(log)],
                            cwd=ROOT, env=env, stdout=out, stderr=subprocess.STDOUT).returncode
    r = parse_log(log)
    r.update(seed=k, shift=shift, rc=rc, log=str(log.relative_to(ROOT)))
    return r


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("state")
    ap.add_argument("--seeds", type=int, default=8, help="how many seeds (K)")
    ap.add_argument("--step", type=int, default=None,
                    help="idle frames between seeds (default 60 // K)")
    ap.add_argument("--jobs", type=int, default=1, help="runs in parallel")
    ap.add_argument("--out", default=None, help="sweep directory")
    ap.add_argument("--timeout", type=int, default=None,
                    help="run.sh wall-clock cap per run (default: the graph's)")
    a = ap.parse_args()

    e = entry_for(a.state)
    gen = e["gen"]
    step = a.step if a.step is not None else max(1, 60 // max(a.seeds, 1))
    timeout = a.timeout or e.get("timeout") or 1800
    env_extra = {}
    if e.get("checkpoint"):
        env_extra["OT6_SRAM_CHECKPOINT"] = f"tools/tests/checkpoints/{e['checkpoint']}"
    if e.get("stack"):
        env_extra["OT6_STACK"] = e["stack"]
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    outdir = Path(a.out) if a.out else ROOT / "build" / "sweeps" / f"{a.state}-{stamp}"
    outdir.mkdir(parents=True, exist_ok=True)
    print(f"seed sweep: {a.state} <- {gen}.lua, {a.seeds} seeds, shift step "
          f"{step} frames, retries OFF, cap {timeout}s, jobs {a.jobs}")
    print(f"  output: {outdir.relative_to(ROOT)}/ (nothing published to build/states)")
    if e.get("prev"):
        print(f"  boots build/states/{e['prev']}.mss.lua as the graph does")
    if e.get("checkpoint"):
        print(f"  cold-boots checkpoint {e['checkpoint']} as the graph does")

    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, a.jobs)) as ex:
        futs = [ex.submit(run_one, k, k * step, gen, env_extra, outdir, timeout, a.state)
                for k in range(a.seeds)]
        for f in concurrent.futures.as_completed(futs):
            r = f.result()
            results.append(r)
            print(f"  seed {r['seed']:2d} shift {r['shift']:3d}: {r['verdict']:4s} "
                  f"frames={r['frames']} {r['cls']} {r['msg'][:100]}", flush=True)
    results.sort(key=lambda r: r["seed"])

    hdr = ("seed", "shift", "verdict", "frames", "class", "message", "log")
    rows = [(r["seed"], r["shift"], r["verdict"], r["frames"], r["cls"],
             r["msg"], r["log"]) for r in results]
    with open(outdir / "summary.tsv", "w") as f:
        f.write("\t".join(hdr) + "\n")
        for row in rows:
            f.write("\t".join(str(c) for c in row) + "\n")
    print()
    print(f"{'seed':>4} {'shift':>5} {'verdict':7} {'frames':>7}  class        message")
    for row in rows:
        seed, shift, verdict, frames, cls, msg, _ = row
        print(f"{seed:>4} {shift:>5} {verdict:7} {str(frames):>7}  {cls:12} {msg[:140]}")
    npass = sum(1 for r in results if r["verdict"] == "PASS")
    print(f"\n{npass}/{len(results)} seeds passed; table in {outdir.relative_to(ROOT)}/summary.tsv")
    return 0 if npass == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
