#!/usr/bin/env python3
"""bench_throughput.py -- how many emulators this machine runs well at once.

    python3 tools/bench_throughput.py                  # K = 1 .. 1.5 x cores
    python3 tools/bench_throughput.py --k 1,2,4,8,12

For each K, starts K copies of one fixed, deterministic test at once through
tools/tests/run.sh and waits for all of them.  Per K it reports the frames
each copy advanced (from its PASS line; every copy must PASS on the same
frame, or the row says so), the wall seconds, frames/s per emulator, the
total frames/s (all copies' frames over the batch's wall time), and the
1-minute load average before and during the batch, with the most Mesen
processes that were not this bench's.  On a shared machine, --quiet-load 2
waits for quiet first and re-runs (up to 3 times) a batch that another
job's emulators joined.  A total that has fallen well below
the best for two K in a row ends the sweep early (--full to go on).

Its runs are ordinary runs, so a live.py watching this machine records each
one in build/throughput.jsonl like any other: the bench seeds the per-machine
curve that live.py's placement reads, at concurrency normal work has not
reached yet.  Run it when the machine is otherwise quiet, and with live.py
watching the machine if the curve is to learn from it.

Each copy runs with OT6_NO_PUBLISH=1 (build/states is left alone) and a
roomy OT6_TIMEOUT with no timeout retry, so an oversubscribed K is measured
rather than killed and silently re-run.  Each run's [ot6] lines, a JSON line
per run and the table go to --out (default build/bench/<host>-<time>/).
"""
import argparse
import math
import os
import re
import signal
import socket
import subprocess
import sys
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
PASS = re.compile(r"^\[ot6\] PASS \(frame (\d+)\)", re.M)


def default_ks(n):
    top = math.ceil(1.5 * n)
    ks = {1, 2, 3, 4, n, top}
    ks |= set(range(6, top + 1, 2))
    return sorted(k for k in ks if 1 <= k <= top)


def load1():
    return os.getloadavg()[0]


def foreign_mesen(ours):
    """Mesen processes on this machine whose parent is not one of our run.sh
    children: another job's emulators."""
    try:
        out = subprocess.run(["ps", "-Ao", "pid=,ppid=,comm="],
                             capture_output=True, text=True, timeout=10).stdout
    except Exception:
        return None
    n = 0
    for line in out.splitlines():
        parts = line.split(None, 2)
        if len(parts) == 3 and os.path.basename(parts[2]) == "Mesen" \
                and int(parts[1]) not in ours:
            n += 1
    return n


def batch(k, test, out, cap):
    env = dict(os.environ, OT6_WORKER=f"bench_k{k}", OT6_NO_PUBLISH="1",
               OT6_TIMEOUT=str(cap), OT6_TIMEOUT_RETRIES="0")
    before = (round(load1(), 2), foreign_mesen(set()))
    procs, t0 = [], time.time()
    for i in range(k):
        log = os.path.join(out, f"k{k:02d}_{i:02d}.log")
        so = open(os.path.join(out, f"k{k:02d}_{i:02d}.out"), "w")
        p = subprocess.Popen(["sh", os.path.join(ROOT, "tools/tests/run.sh"),
                              test, log], cwd=ROOT, env=env, stdout=so,
                             stderr=subprocess.STDOUT, start_new_session=True)
        procs.append([p, log, so, None])
    loads, foreign = [], []
    try:
        while any(pr[3] is None for pr in procs):
            time.sleep(2)
            loads.append(load1())
            foreign.append(foreign_mesen({pr[0].pid for pr in procs}))
            for pr in procs:
                if pr[3] is None and pr[0].poll() is not None:
                    pr[3] = time.time() - t0
                    pr[2].close()
    except BaseException:
        for pr in procs:
            if pr[0].poll() is None:
                os.killpg(pr[0].pid, signal.SIGTERM)
        for pr in procs:   # run.sh traps TERM and tidies up; wait for it
            pr[0].wait()
        raise
    makespan = time.time() - t0
    runs = []
    for p, log, _so, wall in procs:
        try:
            with open(log) as f:
                text = f.read()
            m = PASS.findall(text)
            # the screenshot stream is megabytes a run; keep the [ot6] lines
            with open(log, "w") as f:
                f.writelines(ln + "\n" for ln in text.splitlines()
                             if ln.startswith("[ot6] "))
        except OSError:
            m = []
        frames = int(m[-1]) if m else None
        runs.append({"k": k, "log": log, "code": p.returncode,
                     "frames": frames, "wall": round(wall, 1),
                     "fps": round(frames / wall, 1) if frames else None})
    fr = {r["frames"] for r in runs}
    good = [r for r in runs if r["frames"]]
    row = {
        "k": k, "passed": len(good), "frames": sorted(f for f in fr if f),
        "same": len(fr) == 1 and None not in fr,
        "wall_min": min(r["wall"] for r in runs),
        "wall_max": max(r["wall"] for r in runs),
        "per_emu": round(sum(r["fps"] for r in good) / len(good), 1) if good else 0,
        "total": round(sum(r["frames"] for r in good) / makespan, 1),
        "load_before": before[0], "foreign_before": before[1],
        "load_mean": round(sum(loads) / len(loads), 2) if loads else None,
        "load_max": round(max(loads), 2) if loads else None,
        "foreign_max": max((f for f in foreign if f is not None), default=None),
    }
    return row, runs


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--test", default="tools/tests/battle_rage.lua")
    ap.add_argument("--k", help="comma-separated K values (default: 1..1.5x cores)")
    ap.add_argument("--cap", type=int, default=3600,
                    help="per-run wall-clock cap, seconds (OT6_TIMEOUT)")
    ap.add_argument("--full", action="store_true",
                    help="do not stop once the total has fallen off")
    ap.add_argument("--quiet-load", type=float, metavar="L",
                    help="share-aware: wait for the 1-min load under L before "
                    "the first batch and for no other Mesen before each; a "
                    "batch another job's emulators joined is logged, marked "
                    "shared, and run again once they are gone")
    ap.add_argument("--tolerate", type=int, default=0, metavar="N",
                    help="with --quiet-load, up to N other Mesen count as quiet")
    ap.add_argument("--max-wait", type=int, default=3 * 3600,
                    help="with --quiet-load, give up after this many seconds "
                    "of waiting in all")
    ap.add_argument("--out")
    a = ap.parse_args()
    ncpu = os.cpu_count()
    ks = [int(x) for x in a.k.split(",")] if a.k else default_ks(ncpu)
    host = socket.gethostname().split(".")[0].lower()
    out = a.out or os.path.join(ROOT, "build/bench",
                                f"{host}-{time.strftime('%Y%m%d-%H%M%S')}")
    os.makedirs(out, exist_ok=True)
    print(f"bench_throughput: {host}, {ncpu} logical cores, {a.test}, "
          f"K {ks}, out {out}", flush=True)
    hdr = ("   K pass  frames        wall s     frames/s/emu  total frames/s"
           "  load before  during(mean/max)  other Mesen")
    print(hdr, flush=True)
    best, falling = 0.0, 0
    import json
    with open(os.path.join(out, "runs.jsonl"), "a") as jl, \
            open(os.path.join(out, "table.txt"), "a") as tl:
        tl.write(hdr + "\n")
        waited = [0.0]

        def wait_for(ok, what):
            t = time.time()
            while not ok():
                if waited[0] + time.time() - t > a.max_wait:
                    print(f"gave up waiting for {what} after {a.max_wait}s",
                          flush=True)
                    sys.exit(3)
                time.sleep(15)
            if time.time() - t > 1:
                print(f"  (waited {time.time() - t:.0f}s for {what}; load "
                      f"{load1():.2f})", flush=True)
            waited[0] += time.time() - t

        if a.quiet_load is not None:
            wait_for(lambda: load1() < a.quiet_load
                     and foreign_mesen(set()) <= a.tolerate,
                     f"load < {a.quiet_load} and at most {a.tolerate} other Mesen")
        queue = list(ks)
        redo = {}
        while queue:
            k = queue[0]
            if a.quiet_load is not None:
                wait_for(lambda: foreign_mesen(set()) <= a.tolerate,
                         f"at most {a.tolerate} other Mesen")
            row, runs = batch(k, a.test, out, a.cap)
            shared = (a.quiet_load is not None
                      and (row["foreign_max"] or 0) > a.tolerate)
            if shared and redo.get(k, 0) < 3:
                redo[k] = redo.get(k, 0) + 1
            else:
                queue.pop(0)
            for r in runs:
                jl.write(json.dumps(dict(r, host=host, test=a.test)) + "\n")
            jl.write(json.dumps(dict(row, host=host, test=a.test, row=True)) + "\n")
            jl.flush()
            frames = ",".join(map(str, row["frames"])) + ("" if row["same"] else " (DIFFER)")
            line = (f"{k:4d} {row['passed']:2d}/{k:<2d} {frames:>12s}  "
                    f"{row['wall_min']:6.1f}-{row['wall_max']:<6.1f}  "
                    f"{row['per_emu']:10.1f}  {row['total']:14.1f}  "
                    f"{row['load_before']:10.2f}  {row['load_mean']:>7}/{row['load_max']:<7}"
                    f"  {row['foreign_before']}/{row['foreign_max']}"
                    + ("  shared: run again" if shared and queue and queue[0] == k
                       else "  shared" if shared else ""))
            print(line, flush=True)
            tl.write(line + "\n")
            tl.flush()
            if shared:
                continue
            best = max(best, row["total"])
            falling = falling + 1 if row["total"] < 0.85 * best else 0
            if falling >= 2 and not a.full:
                print("total has fallen below 85% of the best twice running; "
                      "stopping (--full to go on)", flush=True)
                break
    return 0


if __name__ == "__main__":
    sys.exit(main())
