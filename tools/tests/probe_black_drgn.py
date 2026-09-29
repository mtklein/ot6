#!/usr/bin/env python3
"""probe_black_drgn.py -- run tools/tests/probe_black_drgn.lua over distinct draws (#300).

A seed shift moves in-battle RNG only (and the battle seed, $be, through the
frame the battle opens on); which formation comes next is save data
($1FA1-$1FA5), so each variant uses up K encounters on the plains first
(docs/TESTING.md "Tests that survive any draw").  Each variant is a copy of
the lab with its LAB line rewritten, run by tools/tests/run.sh with retries
off (OT6_RETRIES=1): every attempt is scored as it fell, and a lost one is
kept.

  python3 tools/tests/probe_black_drgn.py run --cp wor-tzen-door-v1 --ks 0 1 2 --shifts 0 23 --jobs 6 --dir DIR
  python3 tools/tests/probe_black_drgn.py summary --dir DIR
  python3 tools/tests/probe_black_drgn.py tally --dir DIR

(run from the worktree root).
"""
import argparse
import concurrent.futures as cf
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path.cwd()
LAB = ROOT / "tools/tests/probe_black_drgn.lua"
LINE = re.compile(r'^local LAB = \{.*\}  -- LAB .*$', re.M)


def derive(cp, k, cap, out):
    src = LAB.read_text()
    assert len(LINE.findall(src)) == 1, "the LAB line moved"
    body = LINE.sub(f'local LAB = {{ cp = "{cp}", k = {k}, cap = {cap} }}  -- LAB (derived)', src, count=1)
    out.write_text(body)
    return out


def run_one(cp, k, shift, cap, d):
    tag = f"k{k}_s{shift}"
    lua = derive(cp, k, cap, d / f"lab_black_drgn_{tag}.lua")
    log = d / f"{tag}.log"
    env = dict(os.environ, OT6_SRAM_CHECKPOINT=f"tools/tests/checkpoints/{cp}",
               OT6_RETRIES="1", OT6_SEED_SHIFT=str(shift), OT6_TIMEOUT="3600",
               OT6_ARTIFACT_DIR=str(d / f"art_{tag}"), OT6_WORKER=f"drgn_{d.name}_{tag}")
    subprocess.run(["tools/tests/run.sh", str(lua), str(log)], cwd=ROOT, env=env,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return summarize(tag, log)


def summarize(tag, log):
    text = log.read_text(errors="replace") if log.exists() else ""
    lines = [l[6:] for l in text.splitlines() if l.startswith("[ot6] ")]
    verdict = next((l for l in reversed(lines) if re.match(r"(PASS \(frame|FAIL: )", l)), "(no verdict)")
    pick = lambda pat: [l for l in lines if pat in l]
    out = [f"{tag}: {verdict}"]
    for pat in ("[drgn] boot", "encounter(s) used up before the sand", "[drgn] the sand:",
                "[drgn] VERDICT", "[drgn] after the dragon"):
        for l in pick(pat):
            out.append("  " + l)
    opens = [l for l in pick("[drgn] battle open") if "the SAND" in l]
    out.append(f"  sand battles opened: {len(opens)}; formations "
               + " ".join(re.search(r"formation (\$\w+)", l).group(1) for l in opens))
    dr = [l for l in opens if "formation $0C3" in l]
    for l in dr:
        out.append("  dragon open: " + l)
    # the dragon's own window: from its open to the next [drgn] line after the VERDICT
    try:
        i0 = next(i for i, l in enumerate(lines) if "[drgn] battle open" in l and "formation $0C3" in l)
    except StopIteration:
        i0 = None
    if i0 is not None:
        i1 = next((i for i in range(i0 + 1, len(lines)) if "[drgn] VERDICT" in lines[i]), len(lines) - 1)
        win = lines[i0:i1 + 1]
        st = [l for l in win if "] [status] " in l]
        de = [l for l in win if "] [death] " in l]
        wipe = [l for l in win if "[wipe]" in l]
        items = [l for l in win if re.search(r"plan=(item|heal|raise|cure)", l)]
        out.append(f"  in the dragon's fight: {len(st)} [status] line(s), {len(de)} [death], {len(wipe)} [wipe], "
                   f"{len(items)} item/heal plan line(s)")
        for l in st + de + wipe:
            out.append("    " + l)
    return "\n".join(out)


VER = re.compile(r"\[drgn\] VERDICT the Black Drgn: (\w+) after (\d+) ticks \(sand battle (\d+), key ([^)]*)\); "
                 r"lowest HP ([^;]*); deaths ([^;]*); (?:statuses landed \(STATUS2<<8\|STATUS1\) ([^;]*); )?XP due (\d+)")
OPEN = re.compile(r"\[drgn\] battle open f\d+ on the SAND: formation \$0C3 .*?; CELES L(\d+) xp \d+ HP (\d+)/(\d+)")
EGOUT = re.compile(r"\[outcome\] battle \$0C2 \w+ after (\d+) ticks")


def tally(d):
    """One line per run and the set's totals, from each run's own log."""
    import statistics as st
    rows = []
    for log in sorted(d.glob("k*_s*.log"), key=lambda p: [int(x) for x in re.findall(r"\d+", p.stem)]):
        lines = [l[6:] for l in log.read_text(errors="replace").splitlines() if l.startswith("[ot6] ")]
        v = next((m for m in map(VER.search, lines) if m), None)
        o = next((m for m in map(OPEN.search, lines) if m), None)
        verdict = next((l for l in reversed(lines) if re.match(r"(PASS \(frame|FAIL: )", l)), "(no verdict)")
        eg = [int(m.group(1)) for m in map(EGOUT.search, lines) if m]
        zomb = sum(1 for l in lines if "] [status] " in l and "ZOMBIE" in l)
        rows.append(dict(tag=log.stem, v=v, o=o, verdict=verdict, eg=eg, zomb=zomb))
    won = [r for r in rows if r["v"] and r["v"].group(1).lower() == "won"]
    lost = [r for r in rows if r["v"] and r["v"].group(1).lower() == "lost"]
    keys = {r["v"].group(4) for r in rows if r["v"]}
    t = [int(r["v"].group(2)) for r in won]
    out = [f"== {d.name}: {len(rows)} runs; the dragon WON {len(won)}, LOST {len(lost)}, not met "
           f"{len(rows) - len(won) - len(lost)}; {len(keys)} distinct battle keys"]
    if t:
        out.append(f"   won in {min(t)}-{max(t)} ticks, median {int(st.median(t))}, mean {int(st.mean(t))}")
    eg = [x for r in rows for x in r["eg"]]
    if eg:
        out.append(f"   EarthGuard + Peepers fights: {len(eg)}, {min(eg)}-{max(eg)} ticks, mean {int(st.mean(eg))}")
    for r in rows:
        v, o = r["v"], r["o"]
        if v is None:
            out.append(f"   {r['tag']}: {r['verdict']}")
            continue
        out.append(f"   {r['tag']}: {v.group(1).upper()} {v.group(2)} ticks, sand battle {v.group(3)}, key {v.group(4)}; "
                   f"opened L{o.group(1)} {o.group(2)}/{o.group(3)}; lowest {v.group(5)}; deaths {v.group(6)}; "
                   f"landed {v.group(7) or '(not logged)'}; XP {v.group(8)}; [status] ZOMBIE lines {r['zomb']} | {r['verdict']}")
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("run")
    r.add_argument("--cp", required=True)
    r.add_argument("--ks", type=int, nargs="+", required=True)
    r.add_argument("--shifts", type=int, nargs="+", default=[0])
    r.add_argument("--cap", type=int, default=15)
    r.add_argument("--jobs", type=int, default=3)
    r.add_argument("--dir", required=True)
    s = sub.add_parser("summary")
    s.add_argument("--dir", required=True)
    t = sub.add_parser("tally")
    t.add_argument("--dir", required=True)
    a = ap.parse_args()
    d = Path(a.dir)
    d.mkdir(parents=True, exist_ok=True)
    if a.cmd == "run":
        jobs = [(k, sh) for k in a.ks for sh in a.shifts]
        with cf.ThreadPoolExecutor(max_workers=a.jobs) as ex:
            for out in ex.map(lambda j: run_one(a.cp, j[0], j[1], a.cap, d), jobs):
                print(out, flush=True)
    elif a.cmd == "tally":
        print(tally(d))
    else:
        for log in sorted(d.glob("k*_s*.log")):
            print(summarize(log.stem, log))
    return 0


if __name__ == "__main__":
    sys.exit(main())
