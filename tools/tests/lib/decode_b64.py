#!/usr/bin/env python3
"""Decode [b64:<tag>] payload lines from a Mesen testrunner log into files.

Mesen 2's sandboxed Lua has no io/os libraries, so our harness
(tools/tests/lib/ot6.lua) emits binary artifacts -- savestates and
screenshots -- to stdout as base64 chunks tagged like:

    [b64:first_battle.mss] AAAA....
    [b64:some_shot.png] AAAA....

This script collects the chunks and writes:
    *.mss  -> <outdir>/<tag>              (raw Mesen savestate)
              <outdir>/<tag>.lua          (sidecar so Lua can load it back,
                                           since Lua can dofile() but not read
                                           arbitrary files)
    *      -> <outdir>/shots/<tag>        (screenshots etc.)

Usage: decode_b64.py <logfile> <outdir>
"""
import base64
import re
import sys
from collections import defaultdict
from pathlib import Path


def main() -> int:
    log, outdir = sys.argv[1], Path(sys.argv[2])
    (outdir / "shots").mkdir(parents=True, exist_ok=True)

    chunks = defaultdict(list)
    pat = re.compile(r"^\[b64:([^\]]+)\] (\S+)\s*$")
    with open(log, "r", errors="replace") as f:
        for line in f:
            m = pat.match(line)
            if m:
                chunks[m.group(1)].append(m.group(2))

    # One tag can carry several emissions: a retry-ladder generator calling
    # H.screenshot() once per attempt lands several complete base64 payloads,
    # each with its own '=' padding, in the log under one tag.  '=' is legal
    # in base64 only as terminal padding, so a chunk line ending in '=' is an
    # emission boundary.  (An emission whose byte length is a multiple of 3
    # has no padding, so its boundary cannot be detected; those decode as one
    # concatenated blob.)  Each tag is fault-isolated: a tag that fails to
    # decode is reported and skipped.
    failures = 0
    for tag, parts in chunks.items():
        if "/" in tag or "\\" in tag or ".." in tag:
            print(f"skipping suspicious tag: {tag!r}")
            continue
        emissions, cur = [], []
        for part in parts:
            cur.append(part)
            if part.endswith("="):
                emissions.append("".join(cur))
                cur = []
        if cur:
            emissions.append("".join(cur))
        if len(emissions) > 1:
            print(f"tag {tag!r}: {len(emissions)} emissions; keeping the last")
        b64 = emissions[-1]
        try:
            data = base64.b64decode(b64)
        except Exception as e:  # noqa: BLE001 -- isolate per tag, report all
            print(f"FAILED to decode tag {tag!r}: {e}")
            failures += 1
            continue
        if tag.endswith(".mss"):
            dest = outdir / tag
            dest.write_bytes(data)
            sidecar = outdir / (tag + ".lua")
            sidecar.write_text('return "' + b64 + '"\n')
            print(f"{dest} ({len(data)} bytes) + sidecar {sidecar.name}")
        else:
            dest = outdir / "shots" / tag
            dest.write_bytes(data)
            print(f"{dest} ({len(data)} bytes)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
