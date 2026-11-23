#!/usr/bin/env python3
"""route_fights.py [--keys] LOG... -- the battles a play's logs record, as
JSON on stdout.

Default: one {"form", "how", "species": [...], "chars": [...]} per
`[outcome]` line (the formation, every species killed or escaped, and the
seated members the reward names).  LOG is a qualification log (every leg's
output inline) or leg logs.

--keys: one per `[keys]` line (#566's instrument: tools/tests/lib/ot6.lua
M.keyLine), with what the party held, item by item, so the fight can be
re-read under another class table:
    {"form", "species": [gauged bodies' species with a class row],
     "members": [{"c", "r", "l", "skills": "BSMT...", "tools", "throw"}],
     "bag": [tool, star and skean item ids a Tools or Throw owner could use]}
"""
import json
import re
import sys

OUT = re.compile(r"\[outcome\] battle \$([0-9A-F]+) (.*?) after \d+ ticks: killed (.*?); escaped (.*?); "
                 r".*?\((char .*?)\)(?::|$)")
KEYS = re.compile(r"^\[ot6\] .*\[keys\] form=\$([0-9A-F]+) .* bodies=(\S*) gauged=\d+ nohand=\d+ nokit=\d+ "
                  r"src=(\S*) bag=(\S*)")


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


def keys(paths):
    out = []
    for p in paths:
        for line in open(p, errors="replace"):
            m = KEYS.match(line)
            if not m:
                continue
            species = []
            for b in filter(None, m.group(2).split(",")):
                q = re.match(r"s\d:\$([0-9A-F]+):row\$([0-9A-F]+):sh(\d+)$", b)
                if q and int(q.group(2), 16) and int(q.group(3)):
                    species.append(int(q.group(1), 16))
            members = []
            for s in filter(None, m.group(3).split(",")):
                tok = s.split(":")
                mem = {"c": int(tok[0][1:]), "r": None, "l": None, "skills": "", "tools": False, "throw": False}
                for x in tok[1:]:
                    if x in ("tools", "throw"):
                        mem[x] = True
                    elif x[0] in "rl" and len(x) == 3:
                        mem[x[0]] = int(x[1:], 16)
                    else:
                        mem["skills"] += x
                members.append(mem)
            bag = [int(x, 16) for x in filter(None, m.group(4).strip().split("/"))]
            out.append({"form": int(m.group(1), 16), "species": sorted(set(species)), "members": members, "bag": bag,
                        "leg": p.rsplit("/", 1)[-1][:-4]})
    return out


if __name__ == "__main__":
    if sys.argv[1] == "--keys":
        json.dump(keys(sys.argv[2:]), sys.stdout)
    else:
        json.dump(fights(sys.argv[1:]), sys.stdout)
