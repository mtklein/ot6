#!/usr/bin/env python3
"""rafterlab_arrivals.py -- the arrival-HP table for the rafter crossing
(#164): fold the generator's own "[rafters]" lines from
build/rafterlab/gen_<tag>.log runs (rafterlab_batch_gen.sh) with the Ultros 2
lines from build/rafterlab/ultros_<tag>_a<n>.log (rafterlab_ultros_gen.sh
played from that attempt's saved arrival), one row per crossing.

Per row: log tag (the policy x batch), attempt, hold, timer left at (14,7),
fights and each one's clock cost, Potions drunk in the rat fights, each
member's HP at (14,7) -- which is the HP entering battle 104, nothing can
heal between -- the lowest fraction, and for the Ultros run: every hit he
landed (slot, damage), whether the fight was won, and the party after it.
Then per tag: n, how many arrivals had a member under max/3, under max/4,
under max/8 (the shipped gate), fights mean, fight-length spread, Potions,
Ultros wins, and how many arrivals had a member below Ultros's largest
measured hit on that member.

Usage: python3 tools/tests/rafterlab_arrivals.py [gen log ...]
       (default: build/rafterlab/gen_*.log; Ultros logs are found by tag)
"""
import glob
import os
import re
import sys
from collections import defaultdict
from statistics import mean, median

logs = sys.argv[1:] or sorted(glob.glob("build/rafterlab/gen_*.log"))
start = re.compile(r"\[rafters\] crossing attempt (\d+): hold (-?\d+),")
arrival = re.compile(r"\[rafters\] attempt (\d+) arrival hp at \((\d+),(\d+)\): (.*), "
                     r"timer (\d+) left, (\d+) fights")
end = re.compile(r"\[rafters\] attempt (\d+) (ARRIVED|did not bank) at \((\d+),(\d+)\), "
                 r"timer (\d+) left, (\d+) fights")
member = re.compile(r"c(\d+) (\d+)/(\d+)")
fired = re.compile(r"cross: fight (\d+) fired at \((\d+),(\d+)\) timer=(\d+)")
done = re.compile(r"cross: fight (\d+) done, timer=(\d+)")
potion = re.compile(r"\[rafters\] actor=(\d+) heal entity (\d+) \((\d+)/(\d+)\) with \$E9")
entry = re.compile(r"\[rafters\] battle f\+1 .* partyhp=([\d,]+)")
bag = re.compile(r"\[rafters\] bag on the catwalk: Potions=(\d+) Tonics=(\d+) Fenix=(\d+)")
catwalk = re.compile(r"\[rafters\] on the catwalk at \((\d+),(\d+)\), timer (\d+)")

u_hit = re.compile(r"\[ultros2\] hit f(\d+) slot=(\d+) char=(\d+) (\d+)->(\d+) \(-(\d+)\)")
u_done = re.compile(r"\[ultros2\] battle done at f(\d+) \((\d+) frames\) -- party \[(.*)\]")
u_won = re.compile(r"\[ultros2\] attempt (\d+) WON battle 104")
u_lost = re.compile(r"\[ultros2\] (PARTY WIPED|GAME OVER)")
u_verdict = re.compile(r"^\[ot6\] (PASS \(frame|FAIL:)")


def ultros_for(tag, n):
    path = f"build/rafterlab/ultros_{tag}_a{n}.log"
    if not os.path.exists(path):
        return None
    u = dict(path=path, hits=[], done=None, won=False, lost=False, verdict="none",
             attempts=0)
    for line in open(path, errors="replace"):
        if not line.startswith("[ot6] "):
            continue
        m = u_hit.search(line)
        if m:
            u["hits"].append((int(m.group(2)), int(m.group(3)), int(m.group(6))))
        m = u_done.search(line)
        if m and u["done"] is None:
            u["done"] = (int(m.group(2)), m.group(3))
        if u_won.search(line):
            u["won"] = True
        if u_lost.search(line):
            u["lost"] = True
        if "[ultros2] ATTEMPT" in line:
            u["attempts"] += 1
        m = u_verdict.search(line)
        if m:
            u["verdict"] = "PASS" if m.group(1).startswith("PASS") else "FAIL"
    return u


rows = []
for log in logs:
    tag = re.sub(r"^gen_|\.log$", "", os.path.basename(log))
    cur = None
    fights = {}
    per = {}
    cw, bagline = None, None
    for line in open(log, errors="replace"):
        if not line.startswith("[ot6] "):
            continue
        m = catwalk.search(line)
        if m:
            cw = int(m.group(3))
        m = bag.search(line)
        if m:
            bagline = tuple(int(g) for g in m.groups())
        m = start.search(line)
        if m:
            cur = int(m.group(1))
            per[cur] = dict(tag=tag, attempt=cur, hold=int(m.group(2)), fights=[],
                            potions=0, entries=[], arrived=False, hp=None,
                            timer=None, nfights=0, catwalk=cw, bag=bagline)
            fights = {}
            continue
        if cur is None:
            continue
        r = per[cur]
        m = fired.search(line)
        if m:
            fights[int(m.group(1))] = int(m.group(4))
        m = done.search(line)
        if m:
            k = int(m.group(1))
            if k in fights:
                r["fights"].append(fights[k] - int(m.group(2)))
        if potion.search(line):
            r["potions"] += 1
        m = entry.search(line)
        if m:
            r["entries"].append(m.group(1))
        m = arrival.search(line)
        if m:
            r["arrived"] = True
            r["hp"] = [(int(c), int(h), int(mx)) for c, h, mx in member.findall(m.group(4))]
            r["timer"] = int(m.group(5))
            r["nfights"] = int(m.group(6))
        m = end.search(line)
        if m:
            if r["timer"] is None:
                r["timer"] = int(m.group(5))
                r["nfights"] = int(m.group(6))
            r["ultros"] = ultros_for(tag, cur)
            rows.append(r)
            cur = None

if not rows:
    print("no [rafters] attempt lines found in", logs)
    sys.exit(1)

print(f"{'tag':14} {'att':>3} {'hold':>5} {'timer':>6} {'fights':>6} {'fight frames':>22} "
      f"{'pot':>3} {'arrival hp (c1 c4 c5)':>28} {'min%':>5}  ultros")
for r in rows:
    if r["arrived"]:
        hp = " ".join(f"{h}/{mx}" for _, h, mx in r["hp"])
        frac = min(h / mx for _, h, mx in r["hp"])
        fracs = f"{100 * frac:5.1f}"
    else:
        hp, fracs = "(did not arrive)", "-"
    u = r.get("ultros")
    if u is None:
        us = "-"
    else:
        hits = ",".join(f"s{s}-{d}" for s, _, d in u["hits"]) or "no hits"
        us = (f"{'WON' if u['won'] else 'LOST' if u['lost'] else '?'} "
              f"{u['verdict']} hits={hits}"
              + (f" after=[{u['done'][1]}] {u['done'][0]}f" if u["done"] else ""))
    print(f"{r['tag']:14} {r['attempt']:>3} {r['hold']:>5} {r['timer']:>6} {r['nfights']:>6} "
          f"{','.join(str(f) for f in r['fights']):>22} {r['potions']:>3} {hp:>28} {fracs:>5}  {us}")

print()
print("catwalk timers seen:", sorted({r['catwalk'] for r in rows}, key=str),
      " bag (Potions, Tonics, Fenix):", sorted({r['bag'] for r in rows}, key=str))

by = defaultdict(list)
for r in rows:
    by[r["tag"].rsplit("_", 1)[0]].append(r)
print()
print(f"{'policy':10} {'n':>3} {'arrive':>6} {'<1/3':>5} {'<1/4':>5} {'<=1/8':>5} {'fights':>6} "
      f"{'fight min/med/max':>18} {'pot':>4} {'timer med':>9} {'u2 n':>4} {'won':>4} {'<maxhit':>7}")
for pol, rs in sorted(by.items()):
    arr = [r for r in rs if r["arrived"]]
    fl = [f for r in rs for f in r["fights"]]
    us = [r["ultros"] for r in arr if r.get("ultros")]
    # Ultros's largest measured hit per character, over every Ultros run of
    # every policy (his damage does not depend on the crossing policy)
    maxhit = defaultdict(int)
    for rr in rows:
        u = rr.get("ultros")
        if u:
            for s, c, d in u["hits"]:
                maxhit[c] = max(maxhit[c], d)
    under_hit = sum(1 for r in arr if any(h <= maxhit.get(c, 0) for c, h, _ in r["hp"]))

    def n_under(div):
        return sum(1 for r in arr if any(h * div < mx for _, h, mx in r["hp"]))
    def n_under_eq(div):
        return sum(1 for r in arr if any(h <= mx // div for _, h, mx in r["hp"]))
    print(f"{pol:10} {len(rs):>3} {len(arr)/len(rs):>6.0%} {n_under(3):>5} {n_under(4):>5} "
          f"{n_under_eq(8):>5} {mean(r['nfights'] for r in rs):>6.2f} "
          f"{(str(min(fl)) + '/' + str(int(median(fl))) + '/' + str(max(fl))) if fl else '-':>18} "
          f"{sum(r['potions'] for r in rs):>4} "
          f"{int(median(r['timer'] for r in arr)) if arr else '-':>9} {len(us):>4} "
          f"{sum(1 for u in us if u['won']):>4} {under_hit:>7}")
if any(r.get("ultros") for r in rows):
    mh = defaultdict(int)
    for r in rows:
        u = r.get("ultros")
        if u:
            for s, c, d in u["hits"]:
                mh[c] = max(mh[c], d)
    print("Ultros 2's largest measured hit per character:",
          ", ".join(f"c{c}={d}" for c, d in sorted(mh.items())))
