#!/usr/bin/env python3
"""rizopaslab_aggregate.py -- fold build/rizopaslab/*.log [result] lines into
one table for the Rizopas strategy lab (#162): per policy, over the
declared seed spread, wins, Fenix Downs per win, Potions per win, deaths,
mean battle frames on a win (battle-up to teardown), mean boss-phase frames
(Rizopas surfacing to its death), and the raw per-seed line.

Usage: python3 tools/tests/rizopaslab_aggregate.py [logdir] [--md] [--raw]
"""
import re
import sys
from collections import defaultdict
from pathlib import Path
from statistics import mean

args = [a for a in sys.argv[1:] if not a.startswith("--")]
md = "--md" in sys.argv
raw = "--raw" in sys.argv
logdir = Path(args[0] if args else "build/rizopaslab")
pat = re.compile(r"\[result\] (.*)")

# Items are counted from the engine's own record -- the [act] line ExecCmd
# writes for a party Item command (cmd=$01, atk = the item id) -- not from
# the battle-inventory delta the [result] line carries: an emptied row
# vanishes from the battle inventory, so the bag sample freezes at the
# last nonzero count (control_i55: two Potion actions, "potion=1").
ITEM_ACT = re.compile(r"\[act\] t=\d+ start e[0-3] cmd=\$01 atk=\$([0-9A-F]{2})")
ITEM = {"E8": "tonic", "E9": "potion", "F0": "fenix"}

rows = defaultdict(dict)
for log in sorted(logdir.glob("*.log")):
    used = {"tonic": 0, "potion": 0, "fenix": 0}
    kv = None
    for line in log.read_text(errors="replace").splitlines():
        a = ITEM_ACT.search(line)
        if a and a.group(1) in ITEM:
            used[ITEM[a.group(1)]] += 1
            continue
        m = pat.search(line)
        if m:
            kv = dict(p.split("=", 1) for p in m.group(1).split() if "=" in p)
    if kv is None:
        continue
    kv["_log"] = log.name
    for k, v in used.items():
        kv[k] = str(v)
    rows[kv.get("policy", "?")][(int(kv.get("idle", -1)), int(kv.get("prompt", 0)))] = kv   # last wins


def fmean(xs):
    return f"{mean(xs):.0f}" if xs else "-"


if "--matrix" in sys.argv:
    # seed x policy: outcome, boss-phase frames (surface -> dead) on a
    # win, items and deaths -- the Nerapa section's per-seed table
    pols = sorted(rows)
    seeds = []
    for pol in pols:
        for k in rows[pol].values():
            if k["seed"] not in seeds:
                seeds.append(k["seed"])
    seeds.sort(key=lambda s: int(s[1:], 16))
    print("| seed | " + " | ".join(pols) + " |")
    print("|---|" + "---|" * len(pols))
    for s in seeds:
        cells = []
        for pol in pols:
            ks = [k for k in rows[pol].values() if k["seed"] == s]
            if not ks:
                cells.append("—")
                continue
            k = ks[0]
            d = 0 if k["deaths"] == "none" else len(k["deaths"].split(";"))
            items = "".join(f" {n}{lab}" for n, lab in ((int(k["fenix"]), "Fx"), (int(k["potion"]), "Po"), (int(k["tonic"]), "To")) if n)
            if k["outcome"] == "won":
                cells.append(f"{k['t_boss']}{items}{' ' + str(d) + 'd' if d else ''}")
            else:
                cells.append(f"**L** {k['outcome'][5:]}{items} {d}d")
        print(f"| `{s}` | " + " | ".join(cells) + " |")
    sys.exit(0)


if md:
    print("| policy | distinct seeds | won | lost | Fenix/win | Potion/win | deaths (all) | mean t (won) | mean boss phase (won) |")
    print("|---|---|---|---|---|---|---|---|---|")
else:
    print(f"{'policy':10} {'n':>2} {'won':>3} {'lost':>4} {'fx/win':>6} {'po/win':>6} {'deaths':>6} {'t(won)':>7} {'boss(won)':>9}")
for pol, byidle in sorted(rows.items()):
    # Two idles can draw the same seed: a repeated seed is a replicate of
    # the same fight, not a new sample.  Statistics are over DISTINCT
    # seeds; replicates are listed and marked.
    ks, seen, reps = [], set(), []
    for i in sorted(byidle):
        k = byidle[i]
        if k["seed"] in seen:
            reps.append(k)
        else:
            seen.add(k["seed"])
            ks.append(k)
    won = [k for k in ks if k["outcome"] == "won"]
    lost = [k for k in ks if k["outcome"] != "won"]
    fx = mean(int(k["fenix"]) for k in won) if won else float("nan")
    po = mean(int(k["potion"]) for k in won) if won else float("nan")
    deaths = sum(0 if k["deaths"] == "none" else len(k["deaths"].split(";")) for k in ks)
    tw = [int(k["t"]) for k in won]
    bw = [int(k["t_boss"]) for k in won if k["t_boss"] != "none"]
    if md:
        print(f"| {pol} | {len(ks)} | {len(won)} | {len(lost)} | {fx:.1f} | {po:.1f} | {deaths} | {fmean(tw)} | {fmean(bw)} |")
    else:
        print(f"{pol:10} {len(ks):>2} {len(won):>3} {len(lost):>4} {fx:>6.1f} {po:>6.1f} {deaths:>6} {fmean(tw):>7} {fmean(bw):>9}")
        if raw:
            for k in ks + reps:
                rep = " (replicate seed)" if k in reps else ""
                print(f"    idle={k['idle']:>2} prompt={k.get('prompt', '0'):>2} seed={k['seed']} be_up={k['be_up']} {k['outcome']:<13} t={k['t']:>5} "
                      f"boss={k['t_boss']:>5} fenix={k['fenix']} potion={k['potion']} tonic={k['tonic']} "
                      f"deaths={k['deaths']} raises={k['raises']} bp@surface={k['bp_at_surface']} "
                      f"shore={k['shore']} party={k.get('party', '?')}{rep}")
