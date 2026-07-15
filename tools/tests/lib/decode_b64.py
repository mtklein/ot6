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

    for tag, parts in chunks.items():
        if "/" in tag or "\\" in tag or ".." in tag:
            print(f"skipping suspicious tag: {tag!r}")
            continue
        b64 = "".join(parts)
        data = base64.b64decode(b64)
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
    return 0


if __name__ == "__main__":
    sys.exit(main())
