#!/usr/bin/env python3
"""audit_retries.py -- every segment run that needed more than one attempt.

    python3 tools/audit_retries.py                 # build/states/*.log
    python3 tools/audit_retries.py build/sweeps/x  # a directory, or files
    python3 tools/audit_retries.py --all           # every run the runner saw

The segment runner in tools/tests/lib/ot6.lua retries a seed-dependent
failure (a wipe, a no-path, a step timeout, a watchdog trip) from the boot
snapshot and counts it: the verdict line carries `attempts=n/N`, and each
failed attempt leaves one `[retry] attempt n/N FAILED class=... ` line
with the raw message and, where one was taken, the screenshot's path.  A
retried pass is a pass -- but a retry must never hide a bug, so this audit
lists every log with attempts > 1 (or a FAIL that spent attempts), with
each failed attempt's class, message and screenshot, so that each CLASS
becomes an issue.  The rate is the signal: a segment that needs two
attempts every regeneration is not robust, it is lucky twice.

Exit status: 0 always; the listing is the finding.
"""
import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

RUNNER = re.compile(r"^\[ot6\] \[retry\] segment runner: (\S+), up to (\d+) attempt")
ATTEMPT = re.compile(r"^\[ot6\] \[retry\] attempt (\d+)/(\d+) FAILED class=(\S+) "
                     r"frame=(\d+) totalframes=(\d+) shift=(-?\d+) phase=(\d+)"
                     r"(?: screenshot=(\S+))?: (.*)")
WIPECTX = re.compile(r"^\[ot6\] \[retry\] attempt (\d+)/(\d+) wipe context: (.*)")
PASS = re.compile(r"^\[ot6\] PASS \(frame (\d+)\)(?: attempts=(\d+)/(\d+))?")
FAIL = re.compile(r"^\[ot6\] FAIL: (.*)")


def scan(path):
    r = {"log": path, "script": None, "max": None, "attempts": [],
         "verdict": None, "frames": None, "attempts_used": None, "ctx": {}}
    try:
        text = path.read_text(errors="replace")
    except OSError:
        return None
    for line in text.splitlines():
        m = RUNNER.match(line)
        if m:
            r["script"], r["max"] = m.group(1), int(m.group(2))
            continue
        m = ATTEMPT.match(line)
        if m:
            r["attempts"].append({
                "n": int(m.group(1)), "of": int(m.group(2)), "cls": m.group(3),
                "frame": int(m.group(4)), "shift": int(m.group(6)),
                "phase": int(m.group(7)), "shot": m.group(8), "msg": m.group(9)})
            continue
        m = WIPECTX.match(line)
        if m:
            r["ctx"][int(m.group(1))] = m.group(3)
            continue
        m = PASS.match(line)
        if m:
            r["verdict"], r["frames"] = "PASS", int(m.group(1))
            if m.group(2):
                r["attempts_used"] = int(m.group(2))
            continue
        m = FAIL.match(line)
        if m and r["verdict"] is None:
            r["verdict"] = "FAIL"
    if r["script"] is None:
        return None                       # not a segment-runner log
    if r["attempts_used"] is None:
        r["attempts_used"] = len(r["attempts"]) + (1 if r["verdict"] == "PASS" else 0)
        if r["verdict"] == "FAIL":
            r["attempts_used"] = max(1, len(r["attempts"]))
    return r


def collect(args):
    paths = []
    if not args:
        paths = sorted((ROOT / "build/states").glob("*.log"))
    for a in args:
        p = Path(a)
        if p.is_dir():
            paths += sorted(p.rglob("*.log"))
        else:
            paths.append(p)
    return paths


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("paths", nargs="*")
    ap.add_argument("--all", action="store_true",
                    help="list every segment-runner log, retried or not")
    a = ap.parse_args()
    runs = [r for r in (scan(p) for p in collect(a.paths)) if r]
    retried = [r for r in runs if r["attempts"]]
    classes = {}
    print(f"{len(runs)} segment-runner log(s) scanned, {len(retried)} with a failed attempt")
    for r in runs if a.all else retried:
        rel = r["log"]
        try:
            rel = rel.relative_to(ROOT)
        except ValueError:
            pass
        print(f"\n{rel}: {r['script']} {r['verdict'] or 'NO VERDICT'} "
              f"attempts={r['attempts_used']}/{r['max']}"
              + (f" frame={r['frames']}" if r["frames"] else ""))
        for at in r["attempts"]:
            classes.setdefault(at["cls"], []).append((r["script"], at["msg"]))
            print(f"  attempt {at['n']}/{at['of']} {at['cls']:12} f{at['frame']} "
                  f"shift={at['shift']} phase={at['phase']}: {at['msg'][:200]}")
            if at["shot"]:
                print(f"      screenshot: {at['shot']}")
            if at["n"] in r["ctx"]:
                print(f"      {r['ctx'][at['n']][:220]}")
    if classes:
        print("\nby class (each is an issue candidate):")
        for cls, items in sorted(classes.items(), key=lambda kv: -len(kv[1])):
            scripts = sorted({s for s, _ in items})
            print(f"  {cls:12} x{len(items):<3} {', '.join(scripts)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
