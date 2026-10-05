#!/usr/bin/env python3
"""rc_summary.py -- medians of build/rc/results.tsv per workload x variant
(numbered reps only; 'prof' and 0/9 smoke runs are left out), with fps and
the time saved against the same workload's base."""
import os, statistics as st
from collections import defaultdict
RC = os.path.dirname(os.path.abspath(__file__))
rows = defaultdict(list)
for l in open(os.path.join(RC, "results.tsv")):
    f = l.rstrip("\n").split("\t")
    w, v, rep, verdict, frame, real, user = f[:7]
    if rep not in ("1", "2", "3"):
        continue
    rows[(w, v)].append((float(real), float(user), int(frame), verdict, f[9], f[10], f[12]))
print(f"{'workload':8s} {'variant':12s} n  verdicts      frames  real(s): runs -> median   fps    vs base   Ginstr  load1s")
for w in ("rwhelk", "rrage", "rzozo", "whelk", "rage", "zozo"):
    base = rows.get((w, "base"))
    bm = st.median(r[0] for r in base) if base else None
    for v in ("base", "skip128", "skipall", "nomixer", "norewind", "all_safe", "nodsp_probe", "skip128_nomixer"):
        rs = rows.get((w, v))
        if not rs:
            continue
        reals = [r[0] for r in rs]
        m = st.median(reals)
        frames = sorted(set(r[2] for r in rs))
        verd = ",".join(sorted(set(r[3] for r in rs)))
        fps = st.median(r[2] / r[0] for r in rs)
        rel = f"{(1 - m / bm) * 100:5.1f}% less" if bm and v != "base" else ""
        print(f"{w:8s} {v:12s} {len(rs)}  {verd:12s} {','.join(map(str, frames)):>8s}  "
              f"{' '.join(f'{x:.2f}' for x in reals):24s} -> {m:7.2f}  {fps:6.0f}  {rel:12s} "
              f"{st.median(float(r[4]) for r in rs):7.0f}  {' '.join(r[6] for r in rs)}")
