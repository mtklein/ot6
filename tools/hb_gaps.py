#!/usr/bin/env python3
"""hb_gaps.py -- measure the gaps run.sh's stall watch sees.

    hb_gaps.py <worker-label> <out.tsv> [poll-seconds]

Follows build/test-runs/<worker-label>.*/run.log (OT6_WORKER names the label)
of one run, polling every second (default), and writes one line per change of
the heartbeat's progress counter:

    <wall s since the first heartbeat>  <frame>  <progress n>  <what>  <gap s since the previous change>

and, when the log ends (the run left), a summary: the longest gap, the
frame it ended at and what ended it, the number of changes, the run's wall
time.  A stall watch window must exceed the longest gap on the slowest
legs under full load (docs/TOOLING.md "The run's heartbeat").
"""
import glob, os, re, sys, time

label, out = sys.argv[1], sys.argv[2]
poll = float(sys.argv[3]) if len(sys.argv) > 3 else 1.0
HB = re.compile(rb"^\[ot6hb\] (\d+) - (\d+) (\d+) (\S+)", re.M)
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build", "test-runs")

log = None
while log is None:
    c = sorted(glob.glob(os.path.join(root, label + ".*", "run.log")), key=os.path.getmtime)
    log = c[-1] if c else None
    time.sleep(poll)
t0 = last_t = None
last_n = None
gaps = []
hbs = 0
rows = []
dead = 0
while True:
    try:
        with open(log, "rb") as f:
            f.seek(0, 2)
            size = f.tell()
            f.seek(max(0, size - 4194304))
            data = f.read()
    except OSError:
        break          # the workspace is gone: the run ended clean
    m = list(HB.finditer(data))
    now = time.time()
    if m:
        frame, n, pf, what = int(m[-1][1]), int(m[-1][2]), int(m[-1][3]), m[-1][4].decode()
        if t0 is None:
            t0 = last_t = now
        if n != last_n:
            gap = now - last_t
            if last_n is not None:
                gaps.append((gap, frame, n, what))
            rows.append("%.0f\t%d\t%d\t%s\t%.0f" % (now - t0, frame, n, what, gap))
            last_n, last_t = n, now
    if os.path.exists(os.path.join(os.path.dirname(log), "composed.lua")) is False:
        break
    time.sleep(poll)
    if b"testrunner exit" in data or b"[ot6] PASS" in data or b"[ot6] FAIL" in data:
        dead += 1
        if dead > 3:
            break
now = time.time()
with open(out, "w") as f:
    f.write("# wall_s\tframe\tprogress_n\twhat\tgap_s\n")
    f.write("\n".join(rows) + "\n")
    if gaps:
        g = max(gaps)
        f.write("# changes %d; longest gap %.0fs ending at frame %d (progress %d, %s); run %.0fs\n"
                % (len(gaps), g[0], g[1], g[2], g[3], now - (t0 or now)))
        top = sorted(gaps, reverse=True)[:5]
        for g in top:
            f.write("# gap %.0fs ending at frame %d (progress %d, %s)\n" % g)
    else:
        f.write("# no progress changes seen\n")
