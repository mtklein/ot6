#!/usr/bin/env python3
"""route_fights.py LOG... -- the battles a play's logs record, as JSON on
stdout: one {"form", "how", "species": [...], "chars": [...]} per `[outcome]`
line (the formation, every species killed or escaped, and the seated members
the reward names).  LOG is a qualification log (every leg's output inline)
or leg logs.
"""
import json
import re
import sys

OUT = re.compile(r"\[outcome\] battle \$([0-9A-F]+) (.*?) after \d+ ticks: killed (.*?); escaped (.*?); "
                 r".*?\((char .*?)\)(?::|$)")


def fights(paths):
    out = []
    for p in paths:
        for line in open(p, errors="replace"):
            m = OUT.search(line)
            if not m:
                continue
            sp = sorted({int(x, 16) for x in re.findall(r"s\d:\$([0-9A-F]+)", m.group(3) + " " + m.group(4))})
            ch = sorted({int(x) for x in re.findall(r"char (\d+) ", m.group(5))})
            out.append({"form": int(m.group(1), 16), "how": m.group(2), "species": sp, "chars": ch})
    return out


if __name__ == "__main__":
    json.dump(fights(sys.argv[1:]), sys.stdout)
