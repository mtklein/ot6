#!/usr/bin/env python3
"""The esper ladder (#328, docs/design/esper-rework.md plan A): the table
this tool holds, the menu labels it writes, and the build check that the ROM
carries both.

Every esper has five rungs at 10 / 30 / 75 / 200 / 500 Magic Points: +1 to
its first stat, +1 to its second, a small effect, +2 to its first stat, and
its signature.  The bytes and points come from the design doc's 26-row table
(docs/design/esper-rework.md, plan A; Odin and Raiden share a row), parsed by
doc_spec: a status immunity and an HP or MP boost from the cell's words, any
other effect from the ItemProp bytes of the relic it names.  SPEC below
carries what the doc does not: each rung's menu label (its effect bytes are
not read).  An effect is the
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


DOC = os.path.join(ROOT, "docs", "design", "esper-rework.md")
ITEM_PROP = os.path.join(ROOT, "ff6", "src", "menu", "item_prop_en.dat")
ITEM_NAMES = os.path.join(ROOT, "ff6", "src", "text", "item_name_en.json")
STATUS = dict(S1, **{k: v << 8 for k, v in S2.items()})   # status 2 in the high byte
STATUS_WORDS = {"dark": "dark", "zombie": "zombie", "poison": "poison", "imp": "imp", "petrify": "petrify",
                "death": "death", "doom": "doom", "doom's countdown": "doom", "mute": "mute",
                "berserk": "bserk", "muddle": "muddle", "seizure": "seize", "sleep": "sleep"}
HPMP = {("hp", "12.5"): 0x10, ("hp", "25"): 0x04, ("hp", "50"): 0x08,
        ("mp", "12.5"): 0x80, ("mp", "25"): 0x20, ("mp", "50"): 0x40}


class DocError(Exception):
    pass


def relic_bytes():
    """{lowercase item name: the ten effect bytes Ot6LadderTbl carries for it (ItemProp +5..+13, +25)}."""
    import json
    names = json.load(open(ITEM_NAMES))["text"]
    d = open(ITEM_PROP, "rb").read()
    out = {}
    for i, n in enumerate(names):
        r = d[i * 30:i * 30 + 30]
        out[re.sub(r"\{[^}]*\}", "", n).strip().lower()] = tuple(r[5:14]) + (r[25],)
    return out


def parse_effect(cell, relics):
    """A rung-3 or rung-5 cell -> (label hint, ten effect bytes, four stat points); a dagger cell (new code)
    carries no bytes.  The words decide a status immunity and an HP or MP boost; any other part takes the
    bytes of the relic it names in parentheses."""
    cell = cell.strip()
    b = [0] * 10
    pts = [0, 0, 0, 0]
    if cell.startswith("\u2020") or cell.startswith("†"):
        return tuple(b), tuple(pts)
    m = re.match(r"^\+(\d) (vigor|speed|stamina|mag\.pwr)$", cell)
    if m:
        pts[("vigor", "speed", "stamina", "mag.pwr").index(m.group(2))] = int(m.group(1))
        return tuple(b), tuple(pts)
    cell = cell.split(";")[0]                       # a note after the effect
    parts = re.split(r", and |;", cell)
    for part in parts:
        part = part.strip()
        im = re.match(r"^immune to (.+?)(?: \(([^)]*)\))?$", part)
        hm = re.match(r"^max (HP|MP) \+([\d.]+)%", part)
        if im:
            words = re.split(r", | and ", im.group(1))
            for w in words:
                key = STATUS_WORDS.get(w.strip().lower())
                if key is None:
                    raise DocError("unknown status %r in %r" % (w, cell))
                v = STATUS[key]
                if v & 0xFF:
                    b[1] |= v & 0xFF
                else:
                    b[2] |= v >> 8
        elif hm:
            k = (hm.group(1).lower(), hm.group(2))
            if k not in HPMP:
                raise DocError("no boost bit for %r" % part)
            b[4] |= HPMP[k]
        else:
            names = re.findall(r"([A-Z][A-Za-z.' ]+?)(?: \([^)]*\))?(?= and |$| both)", part) \
                if "both allowed" in part else re.findall(r"\(([^)]*)\)", part)
            if not names:
                raise DocError("no relic named in %r" % part)
            for n in names:
                key = n.strip().lower()
                if key not in relics:
                    key = re.sub(r"'s .*$", "", key)      # "Force Shld's bit", "Offering's X-Fight"
                if key not in relics:
                    raise DocError("no item %r (in %r)" % (n, cell))
                for i, v in enumerate(relics[key]):
                    b[i] |= v
    return tuple(b), tuple(pts)


def doc_spec():
    """{esper name: (first stat, second stat, rung 3, rung 5)} from esper-rework.md's plan A table, each rung
    (ten effect bytes, four stat points)."""
    relics = relic_bytes()
    text = open(DOC, encoding="utf-8").read()
    a = text.index("| Esper | while worn (today's) |")
    out = {}
    for line in text[a:].splitlines()[2:]:
        if not line.startswith("|"):
            break
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        name = cells[0].split(" /")[0]
        st = cells[2]
        m = re.match(r"^(\w+) / (\w+)$", st)
        if m:
            s1, s2 = m.group(1), m.group(2)
        elif st.startswith("all four +1"):
            s1 = s2 = "All"
        else:
            raise DocError("%s: stats cell %r" % (name, st))
        out[name] = (s1, s2, parse_effect(cells[3], relics), parse_effect(cells[4], relics))
    if len(out) != SLOTS:
        raise DocError("the table has %d rows, not %d" % (len(out), SLOTS))
    return out


def rungs():
    """[(esper, rung 1..5, label, effect bytes, stat points)] in table order: the bytes and points from
    esper-rework.md's table (doc_spec), the labels from SPEC (presentation the doc does not carry), with SPEC's
    own stats and bytes held to the doc's."""
    doc = doc_spec()
    out = []
    for name, s1, s2, r3, r5 in SPEC:
        if name not in doc:
            raise DocError("%s has no row in %s" % (name, DOC))
        d1, d2, d3, d5 = doc[name]
        if (s1, s2) != (d1, d2):
            raise DocError("%s's stats are %s / %s in SPEC, %s / %s in the doc" % (name, s1, s2, d1, d2))
        r3 = (r3[0],) + d3
        r5 = (r5[0],) + d5
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
        # the doc is the table: a doc edit the ROM does not follow goes red
        global DOC
        import tempfile
        real = DOC
        text = open(real, encoding="utf-8").read()
        for what, old, new, needle in [
            ("the doc's Shiva signature names the Economizer", "spells cost half MP (Gold Hairpin)",
             "spells cost half MP (Economizer)", "Shiva rung 5"),
            ("the doc's Ramuh rung 3 is Mute, not Dark", "| Ramuh | Bolt, Rasp | Stm / Mag | immune to Dark",
             "| Ramuh | Bolt, Rasp | Stm / Mag | immune to Mute", "Ramuh rung 3"),
        ]:
            assert text.count(old) == 1, old
            with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False, encoding="utf-8") as f:
                f.write(text.replace(old, new))
            DOC = f.name
            got = check(rom, dbg_text, c)
            DOC = real
            os.unlink(f.name)
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
