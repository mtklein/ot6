#!/usr/bin/env python3
"""Aggregate whelkbal_run.lua [metrics] blocks into a per-policy summary.

Usage: whelkbal_agg.py <log> [<log> ...]      (one policy per log)

Same line grammar as bal_aggregate.py: `[ot6] [metrics] b=<k> <key>=<value>`.
Turn counts come from the exec-verified cast counters (casts_*), not the
queue-dequeue player_actions (which double-counts through two queues in
this fight -- measured: player_actions == 2 x casts exactly).
"""
import re
import sys
from collections import defaultdict


def parse(path):
    battles = defaultdict(dict)
    for line in open(path):
        m = re.match(r"\[ot6\] \[metrics\] b=(\d+) (\w+)=(.*)", line.strip())
        if not m:
            continue
        k, key, val = int(m.group(1)), m.group(2), m.group(3)
        if key == "mon_detail":
            battles[k].setdefault("mon_detail", []).append(val)
        else:
            battles[k][key] = val
    return battles


def fnum(b, key):
    try:
        return float(b.get(key, 0) or 0)
    except ValueError:
        return 0.0


def main():
    rows = []
    for path in sys.argv[1:]:
        battles = parse(path)
        if not battles:
            print(f"{path}: no metrics lines", file=sys.stderr)
            continue
        policy = next(iter(battles.values())).get("policy", path)
        valid = [b for b in battles.values() if "void" not in b]
        voids = [b for b in battles.values() if "void" in b]
        n = len(valid)
        wins = [b for b in valid if b.get("result") == "won"]
        losses = [b for b in valid
                  if b.get("result") in ("wiped", "gameover_terra")]
        row = {
            "policy": policy,
            "n": n,
            "voids": len(voids),
            "won": len(wins),
            "lost": len(losses),
            "budget": sum(1 for b in valid if b.get("result") == "budget"),
            "win_frames": (sum(fnum(b, "frames") for b in wins) / len(wins))
                          if wins else 0,
            "casts/fight": sum(fnum(b, "casts_beam") + fnum(b, "casts_tek")
                               + fnum(b, "casts_heal") for b in valid) / n,
            "teks": sum(int(fnum(b, "casts_tek")) for b in valid),
            "heals": sum(int(fnum(b, "casts_heal")) for b in valid),
            "mvolts": sum(int(fnum(b, "casts_megavolt")) for b in valid),
            "chips": sum(int(fnum(b, "shield_chips")) for b in valid),
            "breaks": sum(int(fnum(b, "breaks")) for b in valid),
            "deaths": sum(int(fnum(b, "deaths")) for b in valid),
            "dmg_out": sum(fnum(b, "player_dmg") for b in valid) / n,
            "dmg_in": sum(fnum(b, "enemy_dmg") for b in valid) / n,
            "hidden%": 100 * sum(fnum(b, "head_hidden_frames") for b in valid)
                       / max(1, sum(fnum(b, "frames") for b in valid)),
        }
        rows.append(row)
        print(f"## {policy} ({path})")
        for k in sorted(battles):
            b = battles[k]
            if "void" in b:
                print(f"  b={k} VOID {b['void']}")
                continue
            print(
                f"  b={k} {b.get('result'):<15} frames={b.get('frames'):>5}"
                f" casts(beam/tek/heal)={b.get('casts_beam')}/{b.get('casts_tek')}"
                f"/{b.get('casts_heal')} mvolt={b.get('casts_megavolt')}"
                f" chips={b.get('shield_chips')} breaks={b.get('breaks')}"
                f" dealt={b.get('player_dmg'):>4} taken={b.get('enemy_dmg'):>3}"
                f" deaths={b.get('deaths')} hidden={b.get('head_hidden_frames'):>5}"
                f" hp_end={b.get('party_hp_end')}"
            )
        print()

    hdr = ["policy", "n", "voids", "won", "lost", "budget", "win_frames",
           "casts/fight", "teks", "heals", "mvolts", "chips", "breaks",
           "deaths", "dmg_out", "dmg_in", "hidden%"]
    widths = {h: max(len(h), *(len(f"{r[h]:.1f}" if isinstance(r[h], float)
                                   else str(r[h])) for r in rows)) for h in hdr}
    print(" | ".join(h.ljust(widths[h]) for h in hdr))
    print("-+-".join("-" * widths[h] for h in hdr))
    for r in rows:
        cells = [f"{r[h]:.1f}" if isinstance(r[h], float) else str(r[h])
                 for h in hdr]
        print(" | ".join(c.ljust(widths[h]) for c, h in zip(cells, hdr)))


if __name__ == "__main__":
    main()
