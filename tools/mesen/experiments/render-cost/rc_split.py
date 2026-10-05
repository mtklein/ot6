#!/usr/bin/env python3
"""rc_split.py -- seconds per category for rwhelk base and skip128: each
profile's category shares (rc_categorize.py) times that variant's unprofiled
median wall time (rc_summary.py), and the difference."""
import subprocess, re, os
RC = os.path.dirname(os.path.abspath(__file__))
def shares(p):
    out = subprocess.run(["python3", f"{RC}/rc_categorize.py", p], capture_output=True, text=True).stdout
    d = {}
    for l in out.splitlines()[1:]:
        m = re.match(r"\s+([\d.]+)%  (.*)$", l)
        if m: d[m.group(2)] = float(m.group(1))
        if "other, top" in l: break
    return d
MED = {"base": 78.36, "skip128": 57.03}   # rc_summary.py, rwhelk, medians of 3
a = shares(f"{RC}/runs/rwhelk/base/rprof.sample.txt")
b = shares(f"{RC}/runs/rwhelk/skip128/rprof.sample.txt")
print(f"{'category':58s} {'base s':>7s} {'skip128 s':>9s} {'saved s':>8s}")
for k in a:
    x, y = a[k] * MED["base"] / 100, b.get(k, 0) * MED["skip128"] / 100
    print(f"{k:58s} {x:7.1f} {y:9.1f} {x - y:8.1f}")
print(f"{'total (median wall)':58s} {MED['base']:7.1f} {MED['skip128']:9.1f} {MED['base'] - MED['skip128']:8.1f}")
