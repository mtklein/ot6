#!/usr/bin/env python3
"""rafterlab_aggregate_gen.py -- fold the generator's own "[rafters]" lines
from build/rafterlab/gen_*.log (rafterlab_batch_gen.sh runs) and any other
gen_opera6_rafter log given on the command line into one margin table.

Per attempt: log, attempt, hold, PANIC floor (from the scratch copy's
substituted constant, or 6000 for an unsubstituted generator log), timer
left at (14,7), fights, whether it arrived standing, the rats' positions.
Then per PANIC floor: n, arrival rate, margin min/median/mean/max, fights
mean, and how many attempts cleared 6000 / 3000 / 900.

Usage: python3 tools/tests/rafterlab_aggregate_gen.py [log ...]
       (default: build/rafterlab/gen_*.log)
"""
import glob
import re
import sys
from collections import defaultdict
from statistics import mean, median

logs = sys.argv[1:] or sorted(glob.glob("build/rafterlab/gen_*.log"))
start = re.compile(r"\[rafters\] crossing attempt (\d+): hold (-?\d+),")
end = re.compile(r"\[rafters\] attempt (\d+) (ARRIVED|did not bank) at \((\d+),(\d+)\), "
                 r"timer (\d+) left, (\d+) fights, rats: (.*)")
under = re.compile(r"\[rafters\] attempt (\d+) reached Ultros with (\d+) frames left")
hurt = re.compile(r"\[rafters\] attempt (\d+) reached Ultros on the clock but banked a hurt")
catwalk = re.compile(r"\[rafters\] on the catwalk at \((\d+),(\d+)\), timer (\d+)")

rows = []
for log in logs:
    panic = 6000
    hold = {}
    reached = {}
    hurtset = set()
    cw = None
    for line in open(log, errors="replace"):
        if not line.startswith("[ot6] "):
            continue
        m = catwalk.search(line)
        if m:
            cw = (int(m.group(1)), int(m.group(2)), int(m.group(3)))
        m = start.search(line)
        if m:
            hold[int(m.group(1))] = int(m.group(2))
        m = under.search(line)
        if m:
            reached[int(m.group(1))] = int(m.group(2))
        m = hurt.search(line)
        if m:
            hurtset.add(int(m.group(1)))
        m = end.search(line)
        if m:
            n = int(m.group(1))
            timer = int(m.group(5))
            # "reached Ultros with T frames left" is logged for an on-clock
            # arrival the rung refused; a run that never reached has no such
            # line and its end line reads "did not bank" with the clock where
            # it died (or 0).
            arrived = m.group(2) == "ARRIVED" or n in reached or n in hurtset
            rows.append(dict(log=log, attempt=n, hold=hold.get(n), panic=None,
                             x=int(m.group(3)), y=int(m.group(4)), timer=timer,
                             fights=int(m.group(6)), rats=m.group(7).strip(),
                             arrived=arrived, standing=arrived and n not in hurtset,
                             catwalk=cw))
    # the PANIC floor the scratch copy was run with
    m = re.search(r"gen[_-]p(\d+)_", log)
    if m:
        panic = int(m.group(1))
    for r in rows:
        if r["log"] == log:
            r["panic"] = panic

if not rows:
    print("no [rafters] attempt lines found in", logs)
    sys.exit(1)

print(f"{'log':28} {'att':>3} {'hold':>5} {'panic':>5} {'timer':>6} {'fights':>6} "
      f"{'arrived':>7} {'standing':>8}  rats at the end")
for r in rows:
    print(f"{r['log'].split('/')[-1]:28} {r['attempt']:>3} {str(r['hold']):>5} "
          f"{r['panic']:>5} {r['timer']:>6} {r['fights']:>6} "
          f"{'yes' if r['arrived'] else 'NO':>7} {'yes' if r['standing'] else 'NO':>8}  {r['rats']}")

cws = {r["catwalk"] for r in rows}
print()
print("catwalk snapshots seen (x,y,timer):", sorted(cws, key=str))

by = defaultdict(list)
for r in rows:
    by[r["panic"]].append(r)
print()
print(f"{'panic':>5} {'n':>3} {'arrive':>6} {'min':>5} {'median':>6} {'mean':>6} {'max':>5} "
      f"{'fights':>6} {'>=6000':>6} {'>=3000':>6} {'>=900':>5}")
for panic, rs in sorted(by.items()):
    margins = [r["timer"] if r["arrived"] else 0 for r in rs]
    ok = [r for r in rs if r["arrived"]]
    print(f"{panic:>5} {len(rs):>3} {len(ok)/len(rs):>6.0%} {min(margins):>5} "
          f"{median(margins):>6.0f} {mean(margins):>6.0f} {max(margins):>5} "
          f"{mean(r['fights'] for r in rs):>6.2f} "
          f"{sum(m >= 6000 for m in margins):>6} {sum(m >= 3000 for m in margins):>6} "
          f"{sum(m >= 900 for m in margins):>5}")
