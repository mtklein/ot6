#!/usr/bin/env python3
"""banked_deaths.py -- #194 evidence from run logs: every [death] holding BP.

    python3 tools/tests/zozogrindlab/banked_deaths.py LOG [LOG ...] [--min-bp 1]

For each death of entity E holding >= min-bp pips, prints (raw lines):
  * the battle's status lines (partyhp / roundcost) from the last one before
    E's HP first sat at or under its measured round cost, to the death;
  * every line naming actor=E in that battle (plans, KEYED, SPEND / no spend,
    MUDDLED defers) -- the spend rule (#175) is asked only inside E's own
    command window, so "no actor=E line after the HP fell inside the round"
    means the rule was never asked;
  * the verdict the rule's own arithmetic gives at each status line:
    hp <= roundcost[E] with bp >= 1.
"""
import re
import sys

STATUS = re.compile(r"battle f\+(\d+) menu=(..) state=(..) actor=(\d) .*partyhp=([\d,]+) roundcost=([\d,]+)")
DEATH = re.compile(r"\[death\] f\+(\d+) entity (\d) char (\d+) from (\d+)/(\d+) by (.*?) bp=(\d+) party_bp=(\S+)")
START = re.compile(r"battle f\+1 menu=")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    min_bp = 1
    if "--min-bp" in sys.argv:
        min_bp = int(sys.argv[sys.argv.index("--min-bp") + 1])
        args = [a for a in args if a != str(min_bp)]
    for path in args:
        lines = [l.rstrip("\n") for l in open(path, errors="replace")]
        ot6 = [(i + 1, l) for i, l in enumerate(lines) if l.startswith("[ot6] ") and " wnav " not in l]
        start = 0
        for k, (n, l) in enumerate(ot6):
            if START.search(l):
                start = k
            m = DEATH.search(l)
            if not m or int(m.group(7)) < min_bp:
                continue
            e = int(m.group(2))
            print("=" * 8, path, "line", n)
            print(n, l[6:])
            battle = ot6[start:k + 1]
            inside_at = None
            for n2, l2 in battle:
                s = STATUS.search(l2)
                if s:
                    hp = [int(v) for v in s.group(5).split(",")]
                    rc = [int(v) for v in s.group(6).split(",")]
                    if 0 < hp[e] <= rc[e] and inside_at is None:
                        inside_at = int(s.group(1))
            for n2, l2 in battle:
                s = STATUS.search(l2)
                named = re.search(r"actor=%d\b" % e, l2) and not s
                if s:
                    hp = [int(v) for v in s.group(5).split(",")]
                    rc = [int(v) for v in s.group(6).split(",")]
                    inside = 0 < hp[e] <= rc[e]
                    if inside_at is not None and int(s.group(1)) >= inside_at - 300:
                        print("  %d %s   [E%d hp=%d roundcost=%d inside=%s]" % (
                            n2, l2[6:220], e, hp[e], rc[e], inside))
                elif named or "SPEND" in l2 or "no spend" in l2:
                    print("  %d %s" % (n2, l2[6:260]))
            print("  first status line with E inside one round: %s" % (
                "f+%d" % inside_at if inside_at is not None else "never (roundcost[E] never reached hp)"))


if __name__ == "__main__":
    main()
