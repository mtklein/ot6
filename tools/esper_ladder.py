#!/usr/bin/env python3
"""The esper ladder (#328, docs/design/esper-rework.md plan A): the table
this tool holds, the menu labels it writes, and the build check that the ROM
carries both.

Every esper has five rungs at 10 / 30 / 75 / 200 / 500 Magic Points: +1 to
its first stat, +1 to its second, a small effect, +2 to its first stat, and
its signature.  SPEC below is the design doc's 26-row table (Odin and Raiden
share a row), one entry per counter slot in GenjuProp order.  An effect is the
ten bytes Ot6LadderTbl carries for it (ItemProp +5..+13 and +25, the bits a
relic would set), or no bytes for the five signatures that are new code
(Conductor, Facet, Rebirth, and Fenrir's Stop and Slow immunity; the doc's
Grace for Sraphim would do nothing, since no code clears a fallen
character's boost bank, so Sraphim's signature is the Cure Ring's Regen).

  python3 tools/esper_ladder.py --labels     write ff6/src/battle/ot6_esper_labels.inc
  python3 tools/esper_ladder.py              check build/ot6.sfc against SPEC
  python3 tools/esper_ladder.py --selftest   the check on the real ROM plus mutants

The check reads Ot6LadderTbl (26 x 5 x 14 bytes: the ten effect bytes, then
vigor, speed, stamina, mag.pwr points) and Ot6RungLabelTbl (26 x 5 x 12
encoded tiles) at the addresses ff6/rom/ff6-en.dbg records, and requires both
to equal what SPEC says, rung for rung.
"""
from __future__ import annotations

import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REC = 14
LABEL = 12
SLOTS = 26
COSTS = (10, 30, 75, 200, 500)

# ItemProp +5..+13, +25 in Ot6LadderTbl's order
FIELDS = ("fld", "p1", "p2", "s3", "r9", "r10", "r11", "r12", "r13", "s2")


def eff(label, **bits):
    b = [0] * 10
    for k, v in bits.items():
        b[FIELDS.index(k)] = v
    return (label, tuple(b), (0, 0, 0, 0))


def plus(label, vig=0, spd=0, stm=0, mag=0):
    return (label, (0,) * 10, (vig, spd, stm, mag))


S1 = dict(dark=0x01, zombie=0x02, poison=0x04, imp=0x20, petrify=0x40, death=0x80)
S2 = dict(doom=0x01, mute=0x08, bserk=0x10, muddle=0x20, seize=0x40, sleep=0x80)
STAT = ("Vig", "Spd", "Stm", "Mag")
STAT_NAME = {"Vig": "Vigor", "Spd": "Speed", "Stm": "Stamina", "Mag": "Mag.Pwr"}

# name, first stat, second stat, rung 3, rung 5.  Stats "All" is Crusader:
# all four +1 at rungs 1, 2 and 4.
SPEC = [
    ("Ramuh", "Stm", "Mag", eff("No Dark", p1=S1["dark"]), eff("Conductor")),
    ("Ifrit", "Vig", "Stm", eff("Green Beret", r9=0x10), eff("Atlas Armlet", r9=0x01)),
    ("Shiva", "Mag", "Spd", eff("No Seizure", p2=S2["seize"]), eff("Gold Hairpin", r11=0x20)),
    ("Siren", "Spd", "Mag", eff("No Sleep", p2=S2["sleep"]),
     eff("Peace Ring", p2=S2["bserk"] | S2["muddle"])),
    ("Terrato", "Mag", "Stm", eff("Black Belt", r12=0x02), eff("Muscle Belt", r9=0x08)),
    ("Shoat", "Spd", "Stm", eff("No Petrify", p1=S1["petrify"]),
     eff("No Death", p1=S1["death"], p2=S2["doom"])),
    ("Maduin", "Mag", "Stm", eff("Bard's Hat", r9=0x80), eff("Earring", r9=0x02)),
    ("Bismark", "Vig", "Stm", eff("MithrilGlove", r13=0x02), eff("Red Cap", r9=0x04)),
    ("Stray", "Mag", "Spd", eff("No Imp", p1=S1["imp"]), eff("Sneak Ring", r11=0x01)),
    ("Palidor", "Spd", "Vig", eff("Sprint Shoes", fld=0x20), eff("Cherub Down", s3=0x01)),
    ("Tritoch", "Mag", "Spd", plus("Speed   +1", spd=1),
     eff("Jewel+Orb", p1=S1["dark"] | S1["petrify"], r9=0x40)),
    ("Odin", "Vig", "Spd", eff("Sniper Sight", r11=0x10), eff("RunningShoes", s3=0x08)),
    ("Bahamut", "Mag", "Vig", eff("Red Cap", r9=0x04), eff("Hero Ring", r9=0x03)),
    ("Alexandr", "Stm", "Vig", eff("No Death", p1=S1["death"]), eff("Guard Ring", s3=0x40)),
    ("Crusader", "All", "All", eff("Red Cap", r9=0x04), eff("Gaunt+Genji", r12=0x18)),
    ("Ragnarok", "Vig", "Mag", eff("Minerva", r9=0x20), eff("Offering", r12=0x01)),
    ("Kirin", "Mag", "Stm", eff("No Poison", p1=S1["poison"]), eff("Cure Ring", s3=0x02)),
    ("ZoneSeek", "Mag", "Stm", eff("No Mute", p2=S2["mute"]), eff("Auto Shell", s3=0x20)),
    ("Carbunkl", "Stm", "Mag", eff("Barrier Ring", r13=0x01), eff("Facet")),
    ("Phantom", "Spd", "Mag", eff("Back Guard", r10=0x02), eff("Mirage Vest", s2=0x04)),
    ("Sraphim", "Stm", "Mag", eff("No Doom", p2=S2["doom"]), eff("Cure Ring", s3=0x02)),
    ("Golem", "Stm", "Vig", eff("No Muddle", p2=S2["muddle"]), eff("True Knight", r12=0x40)),
    ("Unicorn", "Stm", "Mag", eff("No Zombie", p1=S1["zombie"]),
     eff("Amulet", p1=S1["dark"] | S1["zombie"] | S1["poison"])),
    ("Fenrir", "Spd", "Mag", eff("Gale Hairpin", r10=0x01), eff("No Stop/Slow")),
    ("Starlet", "Mag", "Spd", eff("No Berserk", p2=S2["bserk"]), eff("Minerva", r9=0x20)),
    ("Phoenix", "Stm", "Spd", eff("No Doom/Zomb", p1=S1["zombie"], p2=S2["doom"]), eff("Rebirth")),
]
assert len(SPEC) == SLOTS


def stat_rung(which, n):
    if which == "All":
        return ("All stats +%d" % n, (0,) * 10, (n, n, n, n))
    pts = [0, 0, 0, 0]
    pts[STAT.index(which)] = n
    return ("%-8s+%d" % (STAT_NAME[which], n), (0,) * 10, tuple(pts))


def rungs():
    """[(esper, rung 1..5, label, effect bytes, stat points)] in table order."""
    out = []
    for name, s1, s2, r3, r5 in SPEC:
        row = [stat_rung(s1, 1), stat_rung(s2, 1), r3,
               stat_rung(s1, 1 if s1 == "All" else 2), r5]
        for i, (label, b, pts) in enumerate(row):
            assert len(label) <= LABEL, label
            out.append((name, i + 1, label, b, pts))
    return out


def codec():
    sys.path.insert(0, os.path.join(ROOT, "ff6", "tools"))
    cwd = os.getcwd()
    os.chdir(os.path.join(ROOT, "ff6"))
    try:
        import romtools as rt
        return rt.TextCodec({"char_tables": ["null_terminated_en", "text_en", "small_symbols_en"]})
    finally:
        os.chdir(cwd)


def encode(c, label):
    b = list(c.encode(label.ljust(LABEL)))
    if b and b[-1] == 0:
        b = b[:-1]
    assert len(b) == LABEL, (label, b)
    return b


def write_labels():
    c = codec()
    lines = ["; generated by tools/esper_ladder.py --labels from its SPEC (the esper",
             "; ladder, #328); do not edit.  26 espers x 5 rungs x 12 menu tiles.",
             "Ot6RungLabelTbl:"]
    for name, k, label, _, _ in rungs():
        lines.append("        .byte   " + ",".join("$%02x" % x for x in encode(c, label))
                     + "   ; %s %d: %s" % (name, k, label))
    lines.append("        calc_size Ot6RungLabelTbl")
    lines.append(".assert sizeof_Ot6RungLabelTbl = %d, error, \"Ot6RungLabelTbl size\"" % (SLOTS * 5 * LABEL))
    path = os.path.join(ROOT, "ff6", "src", "battle", "ot6_esper_labels.inc")
    open(path, "w").write("\n".join(lines) + "\n")
    print("wrote", path)


def sym(dbg_text, name):
    for line in dbg_text.splitlines():
        if 'name="%s"' % name in line and "type=lab" in line:
            m = re.search(r"\bval=0x([0-9A-Fa-f]+)", line)
            if m:
                return int(m.group(1), 16)
    raise SystemExit("esper_ladder: %s not in the debug file" % name)


def rom_off(addr):
    return addr & 0x3FFFFF


def check(rom, dbg_text, c):
    problems = []
    t = rom_off(sym(dbg_text, "Ot6LadderTbl"))
    lt = rom_off(sym(dbg_text, "Ot6RungLabelTbl"))
    for i, (name, k, label, b, pts) in enumerate(rungs()):
        rec = rom[t + i * REC: t + (i + 1) * REC]
        want = bytes(b) + bytes(pts)
        if rec != want:
            problems.append("%s rung %d (%s): Ot6LadderTbl holds %s, the table says %s"
                            % (name, k, label, rec.hex(" "), want.hex(" ")))
        lab = rom[lt + i * LABEL: lt + (i + 1) * LABEL]
        if list(lab) != encode(c, label):
            problems.append("%s rung %d: the menu label is not %r" % (name, k, label))
    return problems


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--labels", action="store_true")
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--rom", default=os.path.join(ROOT, "build", "ot6.sfc"))
    ap.add_argument("--dbg", default=os.path.join(ROOT, "ff6", "rom", "ff6-en.dbg"))
    a = ap.parse_args()
    if a.labels:
        write_labels()
        return 0
    rom = open(a.rom, "rb").read()
    dbg_text = open(a.dbg).read()
    c = codec()
    problems = check(rom, dbg_text, c)
    if a.selftest:
        if problems:
            print("\n".join(problems))
            print("esper_ladder selftest: FAIL (the real ROM is not clean)")
            return 1
        t = rom_off(sym(dbg_text, "Ot6LadderTbl"))
        lt = rom_off(sym(dbg_text, "Ot6RungLabelTbl"))
        names = [r[0] for r in rungs()]
        mutants = [
            ("Shiva's signature loses the Gold Hairpin bit", t + (2 * 5 + 4) * REC + 6, 0x00, "Shiva rung 5"),
            ("Ifrit's rung 4 gives +1 vigor, not +2", t + (1 * 5 + 3) * REC + 10, 0x01, "Ifrit rung 4"),
            ("Phoenix's rung 3 label changes", lt + (25 * 5 + 2) * LABEL, 0x80, "Phoenix rung 3"),
        ]
        bad = 0
        for what, off, val, needle in mutants:
            m = bytearray(rom)
            m[off] = val
            got = check(bytes(m), dbg_text, c)
            ok = any(needle in p for p in got)
            print("mutant %-48s %s" % (what, "red" if ok else "MISSED"))
            bad += not ok
        print("esper_ladder selftest: %s" % ("OK" if not bad else "FAIL"))
        return 1 if bad else 0
    if problems:
        print("\n".join(problems))
        print("esper_ladder: %d problem(s)" % len(problems))
        return 1
    print("esper_ladder: the ROM's 26 ladders (130 rungs) and their menu labels match the table")
    return 0


if __name__ == "__main__":
    sys.exit(main())
