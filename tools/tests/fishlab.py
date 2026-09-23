#!/usr/bin/env python3
"""fishlab.py -- the Solitary Island fishing lab (#253, docs/design/wor-start.md).

    python3 tools/tests/fishlab.py write [policy ...]
    python3 tools/tests/fishlab.py run [--shifts 0-273:7] [--jobs N] [--dir NAME] policy [...]
    python3 tools/tests/fishlab.py aggregate [--root DIR] [policy-or-dir ...]
    python3 tools/tests/fishlab.py heldout [--root DIR] HELDOUT_DIR SEARCH_DIR [...]

`write` derives gen_wor_start.lua into build/lab/fish/gen_wor_start_<policy>.lua:
the generator verbatim with its POLICY line replaced (every substitution
asserts it matched exactly once).  The pseudo-policy `contboot` is the
shipping policy with the seed shift's boot point moved back to the cold
Continue on the world map (assertEntryContract), to measure what an idle
there moves.

`run` plays each variant once per shift, cold-Continuing the tracked
`wor-island-v1` battery as the ninja graph does, retries OFF
(OT6_RETRIES=1), OT6_SEED_SHIFT idle frames at the boot point (the
generator's: on the fishing beach after the first visit's catches, where
the fish and the bird walk the field RNG the next talk's reroll reads; it
moves about one RNG step per 7 frames, hence the default step of 7).
Every attempt is one sample from the island save; every one is kept,
failures included, under build/lab/fish/<dir>/ (<dir> defaults to the
policy's name).  Nothing is published to build/states.  The same shift is
the same boot for every policy, so the rows pair; the shift also costs
Cid its idle (about one health per 64 frames), the same for every policy.

`aggregate` prints, per run directory: attempts, Cid recovered / lost, the
rate, distinct first draws (a first draw is the spawn roll, the RNG index
and Cid's health after the first feed; the same one can still continue
differently, so a draw with both outcomes is counted as `mixed`), trips and
frames to recovery; then one row per shift across the directories.  It
reads the runs' own logs (shiftNN.log) or the evidence tree's filtered
copies (shiftNN.ot6.log): --root points it at either tree.

`heldout` scores one directory's runs only on the first draws none of the
SEARCH directories ever drew: the held-out test of a policy picked by the
search (docs/TESTING.md "test the discovered strategy separately from its
search").
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

POLICY_LINE = 'local POLICY = "near"\n'
POLICIES = ["near", "fast", "fastslow", "all", "allnear", "wait", "contboot"]
BOOT_OLD = '    H.assertContract("wor-island-v1", "entry")\n'
BOOT_NEW = '    H.assertEntryContract("wor-island-v1")   -- fishlab contboot: the boot point on the world map\n'
LOGNAME = re.compile(r"shift(\d+)(\.ot6)?\.log$")


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


def run_one(policy, shift, dirname):
    d = os.path.join(OUT, dirname)
    os.makedirs(d, exist_ok=True)
    log = os.path.join(d, "shift%02d.log" % shift)
    env = dict(os.environ)
    env.update({
        "OT6_RETRIES": "1", "OT6_SEED_SHIFT": str(shift),
        "OT6_NO_PUBLISH": "1",
        "OT6_SRAM_CHECKPOINT": CHECKPOINT,
        "OT6_TIMEOUT": env.get("OT6_TIMEOUT", "7200"),
        "OT6_ARTIFACT_DIR": os.path.join(d, "shift%02d" % shift),
        "OT6_WORKER": "fishlab-%s-%02d" % (dirname, shift),
    })
    with open(os.path.join(d, "shift%02d.out" % shift), "w") as out:
        rc = subprocess.run(["sh", os.path.join(ROOT, "tools/tests/run.sh"),
                             path_of(policy), log],
                            cwd=ROOT, env=env, stdout=out,
                            stderr=subprocess.STDOUT).returncode
    return dirname, shift, rc, summarize(log)


PASS = re.compile(r"^\[ot6\] PASS \(frame (\d+)\)")
FAILV = re.compile(r"^\[ot6\] FAIL: (.*)")
DRAW = re.compile(r"^\[ot6\] \[cid\] first draw: (roll \d+ rand \$[0-9A-F]+ health \d+)")
RECOVERED = re.compile(r"^\[ot6\] \[cid\] Cid recovered on trip (\d+) at f(\d+), health (\d+)")
LOST = re.compile(r"^\[ot6\] \[retry\] attempt \d+/\d+ FAILED class=(\S+) .*?: (.*)")
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
        if m and not r["draw"]:
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


def load(root, name):
    d = os.path.join(root, name)
    rows = {}
    if not os.path.isdir(d):
        return rows
    for f in sorted(os.listdir(d)):
        m = LOGNAME.match(f)
        if m:
            rows[int(m.group(1))] = summarize(os.path.join(d, f))
    return rows


def by_draw(rs):
    byd = {}
    for r in rs.values():
        if r["draw"] and r["outcome"] in ("recovered", "LOST"):
            byd.setdefault(r["draw"], set()).add(r["outcome"])
    return byd


def draw_line(tag, byd):
    ok = sum(1 for o in byd.values() if o == {"recovered"})
    lost = sum(1 for o in byd.values() if o == {"LOST"})
    mixed = sum(1 for o in byd.values() if len(o) > 1)
    return "%-12s distinct samples=%d recovered=%d lost=%d mixed=%d rate=%.3f" % (
        tag, len(byd), ok, lost, mixed, ok / len(byd) if byd else 0)


def run(policies, shifts, jobs, dirname):
    todo = [(p, s, dirname or p) for p in policies for s in shifts]
    for p in policies:
        if not os.path.exists(path_of(p)):
            sys.exit("no %s -- run `fishlab.py write %s` first" % (path_of(p), p))
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as ex:
        for name, shift, rc, r in ex.map(lambda t: run_one(*t), todo):
            print("%-12s shift %2d: rc=%d %-5s %-9s trips=%-4s draw=[%s] %s" % (
                name, shift, rc, r["verdict"], r["outcome"], r["trips"],
                r["draw"], r["fail"]), flush=True)


def aggregate(root, names):
    rows = {n: load(root, n) for n in names}
    rows = {n: rs for n, rs in rows.items() if rs}
    for n, rs in rows.items():
        k = len(rs)
        ok = [r for r in rs.values() if r["outcome"] == "recovered"]
        lost = [r for r in rs.values() if r["outcome"] == "LOST"]
        other = [r for r in rs.values() if r["outcome"] not in ("recovered", "LOST")]
        seqs = {" ".join(r["sets"][:12]) for r in rs.values()}
        trips = sorted(r["trips"] for r in ok if r["trips"])
        frames = sorted(r["cidframe"] for r in ok if r["cidframe"])
        med = lambda xs: xs[len(xs) // 2] if xs else None
        byd = by_draw(rs)
        print("%-12s attempts=%d recovered=%d lost=%d other=%d rate=%.3f distinct first draws=%d "
              "distinct beach sequences=%d trips median=%s max=%s cid-frames median=%s max=%s" % (
                  n, k, len(ok), len(lost), len(other), len(ok) / k if k else 0,
                  len(byd), len(seqs), med(trips), trips[-1] if trips else None,
                  med(frames), frames[-1] if frames else None))
        print(draw_line(n, byd))
        for r in other:
            print("   other: %s %s" % (r["verdict"], r["fail"]))
    shifts = sorted({s for n in rows for s in rows[n]})
    print("\nshift " + " ".join("%-14s" % n for n in rows))
    for s in shifts:
        cells = []
        for n in rows:
            r = rows[n].get(s)
            cells.append("%-14s" % ("-" if r is None else "%s/%s" % (
                "OK" if r["outcome"] == "recovered" else r["outcome"], r["trips"])))
        print("%5d " % s + " ".join(cells))


def heldout(root, name, search):
    seen = set()
    for s in search:
        seen |= {r["draw"] for r in load(root, s).values() if r["draw"]}
    rs = load(root, name)
    fresh = {s: r for s, r in rs.items() if r["draw"] and r["draw"] not in seen}
    print("%s: %d runs, %d with a first draw the search (%s) never drew, over %d search draws" % (
        name, len(rs), len(fresh), " ".join(search), len(seen)))
    print(draw_line(name + " held-out", by_draw(fresh)))
    for s in sorted(fresh):
        r = fresh[s]
        print("  shift %4d: %-9s trips=%-4s draw=[%s]" % (s, r["outcome"], r["trips"], r["draw"]))
    rest = sorted(s for s, r in rs.items() if s not in fresh)
    if rest:
        print("  (shifts whose first draw the search had seen, or with no draw: %s)" %
              " ".join(str(s) for s in rest))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["write", "run", "aggregate", "heldout"])
    ap.add_argument("names", nargs="*")
    ap.add_argument("--shifts", default="0-273:7")
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--dir", default=None, help="run: the directory under build/lab/fish")
    ap.add_argument("--root", default=OUT, help="aggregate/heldout: the tree of run directories")
    a = ap.parse_intermixed_args()
    if a.cmd == "write":
        write(a.names or POLICIES)
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
        run(a.names or POLICIES, shifts, a.jobs, a.dir)
    elif a.cmd == "aggregate":
        aggregate(a.root, a.names or POLICIES)
    else:
        if len(a.names) < 2:
            sys.exit("heldout HELDOUT_DIR SEARCH_DIR [...]")
        heldout(a.root, a.names[0], a.names[1:])


if __name__ == "__main__":
    main()
