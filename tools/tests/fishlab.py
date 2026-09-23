#!/usr/bin/env python3
"""fishlab.py -- the Solitary Island fishing lab (#253, docs/design/wor-start.md).

    python3 tools/tests/fishlab.py write [policy ...]
    python3 tools/tests/fishlab.py run [--shifts 0-273:7] [--jobs N] policy [...]
    python3 tools/tests/fishlab.py aggregate [policy ...]

`write` derives gen_wor_start.lua into build/lab/fish/gen_wor_start_<policy>.lua:
the generator verbatim with its POLICY line replaced (every substitution
asserts it matched exactly once).  The pseudo-policy `contboot` is the
shipping policy with the seed shift's boot point moved back to the cold
Continue on the world map (assertEntryContract), to measure whether an
idle there moves the fish draw at all.

`run` plays each variant once per shift, cold-Continuing the tracked
`wor-island-v1` battery as the ninja graph does, retries OFF
(OT6_RETRIES=1), OT6_SEED_SHIFT idle frames at the boot point (the
generator's: on the fishing beach after the first visit's catches, where
the fish and the bird walk the field RNG the next talk's reroll reads; it
moves about one RNG step per 7 frames, hence the default step of 7).
Every attempt is one sample from the island save; every one is kept,
failures included, under build/lab/fish/<policy>/.  Nothing is published
to build/states.  The same shift is the same boot for every policy, so the
rows pair; the shift also costs Cid its idle (about one health per 64
frames, at most ~4 at shift 273), the same for every policy.

`aggregate` prints, per policy: attempts, Cid recovered / lost, the rate,
distinct first draws, trips and frames to recovery; then one row per shift
across the policies (paired: the same shift is the same boot).
"""
import argparse
import concurrent.futures
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GEN = os.path.join(ROOT, "tools", "tests", "gen_wor_start.lua")
OUT = os.path.join(ROOT, "build", "lab", "fish")
CHECKPOINT = "tools/tests/checkpoints/wor-island-v1"

POLICY_LINE = 'local POLICY = "all"\n'
POLICIES = ["near", "fast", "fastslow", "all", "allnear", "wait", "contboot"]
BOOT_OLD = '    H.assertContract("wor-island-v1", "entry")\n'
BOOT_NEW = '    H.assertEntryContract("wor-island-v1")   -- fishlab contboot: the boot point on the world map\n'


def derive(policy, src):
    assert src.count(POLICY_LINE) == 1, "the POLICY line"
    if policy == "contboot":
        assert src.count(BOOT_OLD) == 1, "the entry contract line"
        return src.replace(BOOT_OLD, BOOT_NEW)
    return src.replace(POLICY_LINE, 'local POLICY = "%s"   -- fishlab\n' % policy)


def path_of(policy):
    return os.path.join(OUT, "gen_wor_start_%s.lua" % policy)


def write(policies):
    src = open(GEN, encoding="utf-8").read()
    os.makedirs(OUT, exist_ok=True)
    for p in policies:
        open(path_of(p), "w", encoding="utf-8").write(derive(p, src))
        print("wrote", os.path.relpath(path_of(p), ROOT))


def run_one(policy, shift):
    d = os.path.join(OUT, policy)
    os.makedirs(d, exist_ok=True)
    log = os.path.join(d, "shift%02d.log" % shift)
    env = dict(os.environ)
    env.update({
        "OT6_RETRIES": "1", "OT6_SEED_SHIFT": str(shift),
        "OT6_NO_PUBLISH": "1",
        "OT6_SRAM_CHECKPOINT": CHECKPOINT,
        "OT6_TIMEOUT": env.get("OT6_TIMEOUT", "3600"),
        "OT6_ARTIFACT_DIR": os.path.join(d, "shift%02d" % shift),
        "OT6_WORKER": "fishlab-%s-%02d" % (policy, shift),
    })
    with open(os.path.join(d, "shift%02d.out" % shift), "w") as out:
        rc = subprocess.run(["sh", os.path.join(ROOT, "tools/tests/run.sh"),
                             path_of(policy), log],
                            cwd=ROOT, env=env, stdout=out,
                            stderr=subprocess.STDOUT).returncode
    return policy, shift, rc, summarize(log)


PASS = re.compile(r"^\[ot6\] PASS \(frame (\d+)\)")
FAILV = re.compile(r"^\[ot6\] FAIL: (.*)")
DRAW = re.compile(r"^\[ot6\] \[cid\] first draw: (.*)")
RECOVERED = re.compile(r"^\[ot6\] \[cid\] Cid recovered on trip (\d+) at f(\d+), health (\d+)")
LOST = re.compile(r"^\[ot6\] \[retry\] attempt \d+/\d+ FAILED class=(\S+) .*?: (.*)")
TRIPDONE = re.compile(r"^\[ot6\] \[cid\] trip (\d+) done: (\d+) frames, caught \{(.*)\}, health (\d+) -> (\d+)")
BEACH = re.compile(r"^\[ot6\] \[cid\] trip (\d+): the beach at f\d+, health \d+, fish (.*)$")
BOOT = re.compile(r"^\[ot6\] \[retry\] boot point: (.*)")


def summarize(log):
    r = dict(verdict="NONE", frame=None, draw="", outcome="?", trips=None,
             cidframe=None, fail="", cls="", boot="", sets=[])
    try:
        lines = open(log, errors="replace").read().splitlines()
    except OSError:
        return r
    for line in lines:
        m = PASS.match(line)
        if m:
            r["verdict"], r["frame"] = "PASS", int(m.group(1))
        m = FAILV.match(line)
        if m:
            r["verdict"], r["fail"] = "FAIL", m.group(1)[:160]
        m = DRAW.match(line)
        if m:
            r["draw"] = m.group(1)
        m = RECOVERED.match(line)
        if m:
            r["outcome"], r["trips"], r["cidframe"] = "recovered", int(m.group(1)), int(m.group(2))
        m = LOST.match(line)
        if m:
            r["cls"] = m.group(1)
            if m.group(1) == "lost":
                r["outcome"] = "LOST"
                t = re.search(r"on trip (\d+)", m.group(2))
                r["trips"] = int(t.group(1)) if t else None
        m = BEACH.match(line)
        if m:
            r["sets"].append("".join("F" if "sp2" in f else "s" if "sp1" in f else "r"
                                      for f in m.group(2).split() if ":" in f) or "-")
        m = BOOT.match(line)
        if m:
            r["boot"] = m.group(1)[:90]
    return r


def run(policies, shifts, jobs):
    todo = [(p, s) for p in policies for s in shifts]
    for p in policies:
        if not os.path.exists(path_of(p)):
            sys.exit("no %s -- run `fishlab.py write %s` first" % (path_of(p), p))
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as ex:
        for policy, shift, rc, r in ex.map(lambda t: run_one(*t), todo):
            print("%-9s shift %2d: rc=%d %-5s %-9s trips=%-4s draw=[%s] %s" % (
                policy, shift, rc, r["verdict"], r["outcome"], r["trips"],
                r["draw"], r["fail"]), flush=True)


def aggregate(policies):
    rows = {}
    for p in policies:
        d = os.path.join(OUT, p)
        if not os.path.isdir(d):
            continue
        for name in sorted(os.listdir(d)):
            m = re.match(r"shift(\d+)\.log$", name)
            if m:
                rows.setdefault(p, {})[int(m.group(1))] = summarize(os.path.join(d, name))
    for p in policies:
        if p not in rows:
            continue
        rs = rows[p]
        n = len(rs)
        ok = [r for r in rs.values() if r["outcome"] == "recovered"]
        lost = [r for r in rs.values() if r["outcome"] == "LOST"]
        other = [r for r in rs.values() if r["outcome"] not in ("recovered", "LOST")]
        draws = {r["draw"] for r in rs.values() if r["draw"]}
        seqs = {" ".join(r["sets"][:12]) for r in rs.values()}
        trips = sorted(r["trips"] for r in ok if r["trips"])
        frames = sorted(r["cidframe"] for r in ok if r["cidframe"])
        med = lambda xs: xs[len(xs) // 2] if xs else None
        print("%-9s attempts=%d recovered=%d lost=%d other=%d rate=%.3f distinct first draws=%d "
              "distinct beach sequences=%d trips median=%s max=%s cid-frames median=%s max=%s" % (
                  p, n, len(ok), len(lost), len(other), len(ok) / n if n else 0,
                  len(draws), len(seqs), med(trips), trips[-1] if trips else None,
                  med(frames), frames[-1] if frames else None))
        # distinct samples: two shifts that drew the same first draw (the
        # same spawn roll, RNG index and health after the first feed) play
        # the same continuation, so they are one sample, not two
        byd = {}
        for r in rs.values():
            if r["draw"] and r["outcome"] in ("recovered", "LOST"):
                byd.setdefault(r["draw"], set()).add(r["outcome"])
        dok = sum(1 for o in byd.values() if o == {"recovered"})
        dlost = sum(1 for o in byd.values() if o == {"LOST"})
        dmixed = sum(1 for o in byd.values() if len(o) > 1)
        print("%-9s distinct samples=%d recovered=%d lost=%d mixed=%d rate=%.3f" % (
            p, len(byd), dok, dlost, dmixed, dok / len(byd) if byd else 0))
        for r in other:
            print("   other: %s %s" % (r["verdict"], r["fail"]))
    shifts = sorted({s for p in rows for s in rows[p]})
    print("\nshift " + " ".join("%-14s" % p for p in policies if p in rows))
    for s in shifts:
        cells = []
        for p in policies:
            if p not in rows:
                continue
            r = rows[p].get(s)
            cells.append("%-14s" % ("-" if r is None else "%s/%s" % (
                "OK" if r["outcome"] == "recovered" else r["outcome"], r["trips"])))
        print("%5d " % s + " ".join(cells))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["write", "run", "aggregate"])
    ap.add_argument("policies", nargs="*")
    ap.add_argument("--shifts", default="0-273:7")
    ap.add_argument("--jobs", type=int, default=4)
    a = ap.parse_args()
    policies = a.policies or POLICIES
    if a.cmd == "write":
        write(policies)
    elif a.cmd == "run":
        shifts = []
        for part in a.shifts.split(","):
            step = 1
            if ":" in part:
                part, step = part.split(":")
                step = int(step)
            if "-" in part:
                lo, hi = part.split("-")
                shifts += list(range(int(lo), int(hi) + 1, step))
            else:
                shifts.append(int(part))
        run(policies, shifts, a.jobs)
    else:
        aggregate(policies)


if __name__ == "__main__":
    main()
