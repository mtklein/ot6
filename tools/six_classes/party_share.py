#!/usr/bin/env python3
"""party_share.py -- by analysis (no emulator): the share of the species the
game deals (and gauges) that a party can weapon-key, under the four classes
(origin/main) and under the six (#566), and the per-character table of what
each can hold.

A party keys a species when it holds one of the species' weapon-weakness
classes.  What a member holds is read two ways:
  signature  the weapon family and class-bearing commands the member is built
             around (classes.py SIGNATURE): who really wields a class
  widest     every class of every weapon the ROM lets the member equip
             (vanilla's equip masks, which OT6 keeps), whenever it is found,
             plus the same commands: the ceiling for a player who re-arms
The parties are stages.py's rosters (the characters the player can field at
each story stage; a roster larger than four is every four of it: the worst,
the mean and the best four).

    python3 tools/six_classes/party_share.py
"""
import itertools
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import classes as C  # noqa: E402
import split  # noqa: E402
import stages  # noqa: E402

S, P, B, X = 1, 2, 4, 8
N4 = {S: "slash", P: "pierce", B: "bludgeon", X: "special"}
# the same signature kinds under the four classes (origin/main's tables)
KIND4 = {"sword": S, "chainsaw": S, "katana": S, "claw": S, "swdtech": S, "dagger": P, "ninja blade": P,
         "thief hit": P, "spear": P, "drill": P, "crossbow": P, "air anchor": P, "tekmissile": P, "star": P,
         "skean": P, "dart": P, "rod": B, "fist": B, "fang": B, "knuckle": S, "flail": B, "club": B, "blitz": B,
         "umaro": B, "boomerang": B, "brush": X, "card": X, "dice": X, "coin": X}
SKILLS = {"LOCKE": {"thief hit"}, "EDGAR": {"drill", "crossbow", "chainsaw", "air anchor"},
          "SABIN": {"blitz"}, "CYAN": {"swdtech"}, "SHADOW": {"star", "skean"}, "SETZER": {"coin"},
          "UMARO": {"umaro"}, "GAU": {"fang"}}


def four_weapons():
    text = subprocess.run(["git", "show", split.BASE + ":ff6/src/battle/ot6_class.asm"], cwd=ROOT, check=True,
                          capture_output=True, text=True).stdout
    bits = {"OT6_SLASH": S, "OT6_PIERCE": P, "OT6_BLUDG": B, "OT6_SPECIAL": X}
    out, item, on = {}, 0, False
    for line in text.splitlines():
        if line.startswith("Ot6WeapClassTbl:"):
            on = True
            continue
        if on and line and not line[0].isspace() and not line.startswith(";"):
            break
        if not on:
            continue
        r = re.match(r"\s+\.res\s+\$([0-9a-f]+) - \$([0-9a-f]+)", line)
        m = re.match(r"\s+\.byte\s+(\S+)", line)
        if r:
            item = int(r.group(1), 16)
        elif m:
            if "OT6_NULLBRK" not in m.group(1):
                out[item] = sum(bits.get(t, 0) for t in m.group(1).split("|"))
            item += 1
    return out


def kits():
    """name -> (sig4, sig6, wide4, wide6)"""
    rom = (ROOT / "Final Fantasy III (USA).sfc").read_bytes()
    if len(rom) % 0x8000:
        rom = rom[0x200:]
    w4 = four_weapons()
    out = {}
    for k, name in enumerate(C.CHARS):
        sig = C.SIGNATURE.get(name, set())
        s4 = sum({KIND4[x] for x in sig})
        s6 = C.signature_mask(name)
        m4 = m6 = 0
        if k < 14:
            for i in range(0x5a):
                rec = rom[0x185000 + i * 30: 0x185000 + i * 30 + 30]
                if (rec[1] | (rec[2] << 8)) >> k & 1 and not rec[2] & 0x40:     # (not an Imp item)
                    m4 |= w4.get(i, 0)
                    m6 |= C.item_class(i)
        for x in SKILLS.get(name, ()):
            m4 |= KIND4[x]
            m6 |= C.KIND_CLASS[x]
        out[name] = (s4, s6, m4 | s4, m6 | s6)
    return out


def share(masks, m):
    return 100.0 * sum(1 for v in masks.values() if v & m) / len(masks)


def names(m, table, order=None):
    return "+".join(table[b] for b in (order or table) if m & b) or "-"


def main():
    r = split.compute()
    g = r["gauged"]
    m4 = {sp: r["rows"][sp][1] for sp in g}
    m6 = {sp: r["new"][sp] for sp in g}
    k = kits()
    print("the share of the %d species the game deals and gauges that a party can weapon-key" % len(g))
    print("(tools/six_classes/party_share.py; four = origin/main, six = this tree's rows)")
    print()
    print("held classes, how many of the species they key:")
    six = tuple(C.ORDER)
    for n in range(1, 7):
        v4 = [share(m4, sum(c)) for c in itertools.combinations((S, P, B, X), n)] if n <= 4 else []
        v6 = [share(m6, sum(c)) for c in itertools.combinations(six, n)]
        print("  any %d: four %s   six %.1f-%.1f%% (mean %.1f%%)" % (
            n, ("%.1f-%.1f%% (mean %.1f%%)" % (min(v4), max(v4), sum(v4) / len(v4))) if v4 else "-",
            min(v6), max(v6), sum(v6) / len(v6)))
    print()
    print("each character: signature kit | widest kit (every class of every weapon the ROM lets them equip, and "
          "their commands)")
    for name in C.CHARS:
        s4, s6, w4, w6 = k[name]
        print("  %-7s %-34s four %-24s %5.1f%% | six %-22s %5.1f%% || widest four %-30s %5.1f%% | six %-40s %5.1f%%" % (
            name, ", ".join(sorted(C.SIGNATURE.get(name, ()))) or "(mimic)", names(s4, N4), share(m4, s4),
            names(s6, C.NAME, C.ORDER), share(m6, s6), names(w4, N4), share(m4, w4), names(w6, C.NAME, C.ORDER),
            share(m6, w6)))
    print()
    print("%-18s %-62s %-26s %-26s %s" % ("stage (first leg)", "roster", "four: signature keys",
                                        "six: signature keys", "widest four / six"))
    seen = {}
    for leg, st in stages.stage_of(stages.line_order(str(ROOT / "build.ninja")), r and {}).items():
        first, roster, forced, magitek = st
        if first in seen or not roster:
            continue
        seen[first] = 1
        if magitek:
            parties = [tuple(n for n in roster if n == "TERRA")]
            kit = {"TERRA": (P, C.KIND_CLASS["tekmissile"], P, C.KIND_CLASS["tekmissile"])}
        else:
            parties = [tuple(sorted(roster))] if len(roster) <= 4 else list(itertools.combinations(sorted(roster), 4))
            kit = k
        rows = []
        for p in parties:
            a = [0, 0, 0, 0]
            for n in p:
                for i in range(4):
                    a[i] |= kit.get(n, (0, 0, 0, 0))[i]
            rows.append((share(m4, a[0]), share(m6, a[1]), share(m4, a[2]), share(m6, a[3])))
        f = lambda i: ("%.0f%%" % rows[0][i]) if len(rows) == 1 else "%.0f-%.0f%% (mean %.0f%%)" % (
            min(x[i] for x in rows), max(x[i] for x in rows), sum(x[i] for x in rows) / len(rows))
        print("%-18s %-62s %-26s %-26s %s / %s" % (first + (" [magitek]" if magitek else ""),
                                                 " ".join(sorted(roster)), f(0), f(1), f(2), f(3)))


if __name__ == "__main__":
    sys.exit(main())
