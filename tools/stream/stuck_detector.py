#!/usr/bin/env python3
"""stuck_detector.py -- catch hung test workers that never game-over.

A worker that loops in a menu or presses into a wall forever keeps its
frame counter climbing but its SCREEN stops changing; nothing game-overs,
so the run only dies at the wall-clock timeout, wasting compute, and the
coordinator (who is only woken on game-overs / completion) is blind to it.

This watches every active run workspace under build/test-runs/ and emits
one STUCK line -- caught by a Monitor -- when a worker's live screenshot
stream ([ot6shot]) holds a single frozen image while its frame counter
([ot6pad]) keeps advancing.  Read-only; it never touches the runs.

  STUCK <worker> frozen ~<sec>s: frame <F>, <n> identical shots since f<F0>

Tuning: a run is flagged when the last SHOTS_STUCK screenshots are all
byte-identical AND span at least FRAMES_STUCK frames of advancing counter
-- long enough that a real battle animation, cutscene, or dialog (all of
which move pixels) never trips it, short enough to catch a hang well
before the ~600s wall-clock cap.  Each stuck episode is reported once.
"""
import glob
import hashlib
import os
import re
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SHOT = re.compile(rb"^\[ot6shot\] (\d+) (\S+)")
PAD = re.compile(rb"^\[ot6pad\] (\d+)")

POLL_SEC = 15          # how often to scan
ACTIVE_SEC = 40        # a run.log touched within this is "live"
SHOTS_STUCK = 8        # this many identical trailing shots ...
FRAMES_STUCK = 2000    # ... spanning at least this many frames = frozen
TAIL_BYTES = 200_000   # read only the log's tail


def tail(path, n=TAIL_BYTES):
    with open(path, "rb") as f:
        f.seek(0, 2)
        size = f.tell()
        f.seek(max(0, size - n))
        return f.read()


def scan_one(path):
    """Return (frozen_bool, frame, nshots, first_frozen_frame) for a log."""
    data = tail(path)
    shots, last_pad = [], None
    for line in data.splitlines():
        m = SHOT.match(line)
        if m:
            shots.append((int(m.group(1)),
                          hashlib.md5(m.group(2)).hexdigest()))
            continue
        p = PAD.match(line)
        if p:
            last_pad = int(p.group(1))
    if len(shots) < SHOTS_STUCK or last_pad is None:
        return (False, last_pad, 0, None)
    # walk back over the trailing run of identical-hash shots
    last_hash = shots[-1][1]
    run = [s for s in reversed(shots) if s[1] == last_hash]
    # the run must be an unbroken trailing block
    trailing = 0
    for s in reversed(shots):
        if s[1] == last_hash:
            trailing += 1
        else:
            break
    if trailing < SHOTS_STUCK:
        return (False, last_pad, trailing, None)
    first_frozen_frame = shots[-trailing][0]
    span = last_pad - first_frozen_frame
    return (span >= FRAMES_STUCK, last_pad, trailing, first_frozen_frame)


def main():
    reported = {}   # worker -> first_frozen_frame already reported
    while True:
        now = time.time()
        for log in glob.glob(os.path.join(ROOT, "build/test-runs/*/run.log")):
            try:
                if now - os.path.getmtime(log) > ACTIVE_SEC:
                    continue
                worker = os.path.basename(os.path.dirname(log)).split(".")[0]
                frozen, frame, nshots, f0 = scan_one(log)
                if frozen and reported.get(worker) != f0:
                    reported[worker] = f0
                    sec = int((frame - f0) / 60)  # ~60 fps game time
                    print(f"STUCK {worker} frozen ~{sec}s: frame {frame}, "
                          f"{nshots} identical shots since f{f0}", flush=True)
                elif not frozen and worker in reported:
                    # screen moved again -- clear so a later freeze re-reports
                    del reported[worker]
            except (OSError, ValueError):
                continue
        time.sleep(POLL_SEC)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
