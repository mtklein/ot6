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
relic would set), or no bytes for the rungs that are new code (the
signatures Conductor, Facet, Rebirth, Fenrir's Stop and Slow immunity,
Sraphim's full revives and Bahamut's Limit Break, and Sraphim's rung 3, healing +25%: Ot6SeraphHeal).

  python3 tools/esper_ladder.py --labels     write ff6/src/battle/ot6_esper_labels.inc and ot6_esper_desc.inc
  python3 tools/esper_ladder.py              check build/ot6.sfc against SPEC
  python3 tools/esper_ladder.py --selftest   the check on the real ROM plus mutants

The check reads Ot6LadderTbl (26 x 5 x 14 bytes: the ten effect bytes, then
vigor, speed, stamina, mag.pwr points) and Ot6RungLabelTbl (26 x 5 x 12
encoded tiles) at the addresses ff6/rom/ff6-en.dbg records, and requires both
to equal what SPEC says, rung for rung.  It also reads the esper page's help lines (Ot6RungDescIdx,
Ot6RungDescPtrs, Ot6RungDescStr, Ot6RungHaveStr: one description per rung, from DESC) and requires every label
to have a description of one line that fits the help window, every label to name one effect, and the ROM's
line for each rung to be its label's.
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
     eff("NoDeath/Doom", p1=S1["death"], p2=S2["doom"])),
    ("Maduin", "Mag", "Stm", eff("Bard's Hat", r9=0x80), eff("Earrings", r9=0x02)),
    ("Bismark", "Vig", "Stm", eff("MithrilGlove", r13=0x02), eff("Red Cap", r9=0x04)),
    ("Stray", "Mag", "Spd", eff("No Imp", p1=S1["imp"]), eff("Sneak Ring", r11=0x01)),
    ("Palidor", "Spd", "Vig", eff("Sprint Shoes", fld=0x20), eff("Cherub Down", s3=0x01)),
    ("Tritoch", "Mag", "Spd", plus("Speed   +1", spd=1),
     eff("Jewel+Orb", p1=S1["dark"] | S1["petrify"], r9=0x40)),
    ("Odin", "Vig", "Spd", eff("Sniper Sight", r11=0x10), eff("RunningShoes", s3=0x08)),
    ("Bahamut", "Mag", "Vig", eff("Red Cap", r9=0x04), eff("Limit Break")),
    ("Alexandr", "Stm", "Vig", eff("No Death", p1=S1["death"]), eff("Guard Ring", s3=0x40)),
    ("Crusader", "All", "All", eff("Red Cap", r9=0x04), eff("Gaunt+Genji", r12=0x18)),
    ("Ragnarok", "Vig", "Mag", eff("Minerva", r9=0x20), eff("Hero Ring", r9=0x03)),
    ("Kirin", "Mag", "Stm", eff("No Poison", p1=S1["poison"]), eff("Cure Ring", s3=0x02)),
    ("ZoneSeek", "Mag", "Stm", eff("No Mute", p2=S2["mute"]), eff("Auto Shell", s3=0x20)),
    ("Carbunkl", "Stm", "Mag", eff("Barrier Ring", r13=0x01), eff("Facet")),
    ("Phantom", "Spd", "Mag", eff("Back Guard", r10=0x02), eff("Mirage Vest", s2=0x04)),
    ("Sraphim", "Stm", "Mag", eff("Heal +25%"), eff("Full Revive")),
    ("Golem", "Stm", "Vig", eff("No Muddle", p2=S2["muddle"]), eff("True Knight", r12=0x40)),
    ("Unicorn", "Stm", "Mag", eff("No Zombie", p1=S1["zombie"]),
     eff("Amulet", p1=S1["dark"] | S1["zombie"] | S1["poison"])),
    ("Fenrir", "Spd", "Mag", eff("Gale Hairpin", r10=0x01), eff("No Stop/Slow")),
    ("Starlet", "Mag", "Spd", eff("No Berserk", p2=S2["bserk"]), eff("Minerva", r9=0x20)),
    ("Phoenix", "Stm", "Spd", eff("No Doom/Zomb", p1=S1["zombie"], p2=S2["doom"]), eff("Rebirth")),
]
assert len(SPEC) == SLOTS


# What the esper page's help line says for the highlighted rung (DrawEsperDetailMenu's cursor on the rung
# column, Ot6RungDescText): one line each, every label one effect.  Player words, FF3-US names; the line is
# drawn in the menu's variable-width font and must fit DESC_WIDTH pixels (the help window's 28 tiles: the
# widest vanilla description line, "Enemy becomes self-destructive", is 223).
DESC = {
    "Vigor   +1": "Raises Vigor by 1",
    "Vigor   +2": "Raises Vigor by 2",
    "Speed   +1": "Raises Speed by 1",
    "Speed   +2": "Raises Speed by 2",
    "Stamina +1": "Raises Stamina by 1",
    "Stamina +2": "Raises Stamina by 2",
    "Mag.Pwr +1": "Raises Mag.Pwr by 1",
    "Mag.Pwr +2": "Raises Mag.Pwr by 2",
    "All stats +1": "Raises all four stats by 1",
    "No Dark": "Protects against Dark",
    "No Seizure": "Protects against Seizure",
    "No Sleep": "Protects against Sleep",
    "No Petrify": "Protects against Petrify",
    "No Imp": "Protects against Imp",
    "No Poison": "Protects against Poison",
    "No Mute": "Protects against Mute",
    "No Muddle": "Protects against Muddle",
    "No Zombie": "Protects against Zombie",
    "No Berserk": "Protects against Berserk",
    "No Death": "Protects against instant death",
    "NoDeath/Doom": "Blocks instant death, Condemned",
    "No Doom/Zomb": "Blocks Condemned and Zombie",
    "No Stop/Slow": "Blocks Stop and Slow",
    "Peace Ring": "Blocks Berserk and Muddle",
    "Amulet": "Blocks Dark, Zombie and Poison",
    "Jewel+Orb": "No Dark or Petrify; max MP +1/2",
    "Green Beret": "Raises max HP by 1/8",
    "Red Cap": "Raises max HP by 1/4",
    "Muscle Belt": "Raises max HP by 1/2",
    "Bard's Hat": "Raises max MP by 1/8",
    "Minerva": "Raises max MP by 1/4",
    "Atlas Armlet": "Raises Fight damage by 1/4",
    "Earrings": "Raises magic damage by 1/4",
    "Hero Ring": "Fight and magic damage +1/4",
    "Gold Hairpin": "Halves the MP spells cost",
    "Black Belt": "Sometimes counters an attack",
    "MithrilGlove": "Casts Safe when HP is low",
    "Barrier Ring": "Casts Shell when HP is low",
    "Sneak Ring": "Raises the success rate of Steal",
    "Sprint Shoes": "Walks faster outside battle",
    "Sniper Sight": "Fight always hits",
    "Back Guard": "No back or pincer attacks",
    "Gale Hairpin": "Raises preemptive attack rate",
    "Cherub Down": "Float in every battle",
    "RunningShoes": "Haste in every battle",
    "Guard Ring": "Safe in every battle",
    "Auto Shell": "Shell in every battle",
    "Cure Ring": "Regen in every battle",
    "Mirage Vest": "Starts every battle with Image",
    "True Knight": "Covers weak allies while healthy",
    "Gaunt+Genji": "Gauntlet and Genji Glove effects",
    "Conductor": "Bolt cuts 2 shields on weak foes",
    "Facet": "2 Boost Points at battle start",
    "Heal +25%": "Healing done is 25% stronger",
    "Full Revive": "Revives allies at full HP",
    "Rebirth": "Starts every battle with Life 3",
    "Limit Break": "Damage dealt can pass 9999",
}
# the help line's second line, under an unreached rung whose effect this character already holds from
# another rung (Ot6RungDescText's cover test over the ladder's effect bytes).  The esper page's title window
# ("Espers", top right) covers the help window's second line from about x = 176, so this line fits HAVE_WIDTH
# (a first try, "Already held from another rank", ran under it: build/attempts/wt/v045-teach/shots/raw/
# esperdetail_staged_held_rung3.png).
HAVE = "Already held"
HAVE_WIDTH = 150
DESC_WIDTH = 223
DESC_TABLES = ["big_symbols_en", "null_terminated_en", "text_en"]


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


def desc_codec():
    sys.path.insert(0, os.path.join(ROOT, "ff6", "tools"))
    cwd = os.getcwd()
    os.chdir(os.path.join(ROOT, "ff6"))
    try:
        import romtools as rt
        return rt.TextCodec({"char_tables": DESC_TABLES})
    finally:
        os.chdir(cwd)


def font_widths():
    """FontWidth (ff6/src/gfx/font_gfx.asm, the English half): the menu's big text indexes it by letter code
    - $60 (big_text.asm: sbc #$80, adc #$20)."""
    src = open(os.path.join(ROOT, "ff6", "src", "gfx", "font_gfx.asm")).read()
    blk = src[src.index("FontWidth:"):].split(".else")[0]
    return [int(x) for line in re.findall(r"\.byte\s+(.*)", blk) for x in line.split(",")]


def desc_bytes(dc, text):
    b = list(dc.encode(text))
    if not b or b[-1] != 0:
        b.append(0)
    return b


def desc_width(dc, widths, text):
    return sum(widths[x - 0x60] for x in desc_bytes(dc, text) if x >= 0x80)


def desc_problems(dc, desc=None):
    """What is wrong with DESC, before any ROM is read: a label in the ladder with no description, a label that
    names two different effects (one description cannot serve both), a description over two lines or wider than
    the help window."""
    desc = DESC if desc is None else desc
    widths = font_widths()
    problems = []
    seen = {}
    for name, k, label, b, pts in rungs():
        if label not in desc or not desc[label].strip():
            problems.append("%s rung %d: the label %r has no description" % (name, k, label))
        if label in seen and seen[label] != (b, pts):
            problems.append("%s rung %d: the label %r names two effects (%s and %s)"
                            % (name, k, label, seen[label], (b, pts)))
        seen.setdefault(label, (b, pts))
    relics = relic_bytes()
    for name, k, label, b, pts in rungs():
        key = label.lower()
        if key in relics and relics[key] != b:
            problems.append("%s rung %d: the label %r names a relic whose effect bytes are %s, not the rung's %s"
                            % (name, k, label, relics[key], b))
    for label, text in sorted(desc.items()) + [("(have)", HAVE)]:
        if "{n}" in text:
            problems.append("description %r is more than one line" % label)
        w = desc_width(dc, widths, text)
        limit = HAVE_WIDTH if label == "(have)" else DESC_WIDTH
        if w > limit:
            problems.append("description %r is %d pixels wide, over %d: %r" % (label, w, limit, text))
    return problems


def desc_table(dc):
    """(the distinct descriptions in first-use order, [description index per rung])"""
    order, idx = [], []
    for name, k, label, b, pts in rungs():
        t = DESC[label]
        if t not in order:
            order.append(t)
        idx.append(order.index(t))
    return order, idx


def write_desc():
    dc = desc_codec()
    bad = desc_problems(dc)
    if bad:
        raise SystemExit("\n".join(bad))
    order, idx = desc_table(dc)
    lines = ["; generated by tools/esper_ladder.py --labels from its DESC (the esper page's",
             "; help line for the highlighted rung); do not edit.",
             "",
             "; one description index per rung, 26 espers x 5 rungs (Ot6RungLabelTbl's order)",
             "Ot6RungDescIdx:"]
    rows = rungs()
    for i in range(0, len(idx), 5):
        lines.append("        .byte   " + ",".join("$%02x" % x for x in idx[i:i + 5]) + "   ; " + rows[i][0])
    lines.append("        calc_size Ot6RungDescIdx")
    lines.append(".assert sizeof_Ot6RungDescIdx = %d, error, \"Ot6RungDescIdx size\"" % (SLOTS * 5))
    lines.append("")
    lines.append("; each description's offset in Ot6RungDescStr")
    lines.append("Ot6RungDescPtrs:")
    off = 0
    for t in order:
        lines.append("        .word   $%04x   ; %s" % (off, t))
        off += len(desc_bytes(dc, t))
    lines.append("")
    lines.append("; the descriptions, null-terminated, in the menu's description charset")
    lines.append("Ot6RungDescStr:")
    for t in order:
        lines.append("        .byte   " + ",".join("$%02x" % x for x in desc_bytes(dc, t)) + "   ; " + t)
    lines.append("")
    lines.append("; the second line under a rung whose effect the character already holds")
    lines.append("Ot6RungHaveStr:")
    lines.append("        .byte   " + ",".join("$%02x" % x for x in desc_bytes(dc, HAVE)) + "   ; " + HAVE)
    path = os.path.join(ROOT, "ff6", "src", "battle", "ot6_esper_desc.inc")
    open(path, "w").write("\n".join(lines) + "\n")
    print("wrote", path)


def check_desc(rom, dbg_text, dc, desc=None):
    """The ROM's help lines against DESC, rung for rung, and DESC's own rules (desc_problems)."""
    desc = DESC if desc is None else desc
    problems = desc_problems(dc, desc)
    ti = rom_off(sym(dbg_text, "Ot6RungDescIdx"))
    tp = rom_off(sym(dbg_text, "Ot6RungDescPtrs"))
    ts = rom_off(sym(dbg_text, "Ot6RungDescStr"))
    th = rom_off(sym(dbg_text, "Ot6RungHaveStr"))

    def cstr(at):
        e = rom.index(b"\0", at)
        return list(rom[at:e + 1])
    for i, (name, k, label, b, pts) in enumerate(rungs()):
        if label not in desc:
            continue
        j = rom[ti + i]
        off = rom[tp + 2 * j] | (rom[tp + 2 * j + 1] << 8)
        if cstr(ts + off) != desc_bytes(dc, desc[label]):
            problems.append("%s rung %d (%s): the help line is not %r" % (name, k, label, desc[label]))
    if cstr(th) != desc_bytes(dc, HAVE):
        problems.append("the 'already has' line is not %r" % HAVE)
    return problems


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
        write_desc()
        return 0
    rom = open(a.rom, "rb").read()
    dbg_text = open(a.dbg).read()
    c = codec()
    dc = desc_codec()
    problems = check(rom, dbg_text, c) + check_desc(rom, dbg_text, dc)
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
            # #550: Bahamut's signature is new code (no bytes); the Hero Ring's moved to Ragnarok's
            ("Bahamut's signature keeps the Hero Ring's bits", t + (12 * 5 + 4) * REC + 4, 0x03, "Bahamut rung 5"),
            ("Ragnarok's signature loses the Hero Ring's bits", t + (15 * 5 + 4) * REC + 4, 0x00, "Ragnarok rung 5"),
        ]
        ti = rom_off(sym(dbg_text, "Ot6RungDescIdx"))
        ts = rom_off(sym(dbg_text, "Ot6RungDescStr"))
        conductor = names.index("Ramuh") + 4      # Ramuh rung 5
        facet_idx = rom[ti + names.index("Carbunkl") + 4]
        mutants += [
            ("Ramuh's signature shows Facet's help line", ti + conductor, facet_idx, "Ramuh rung 5 (Conductor)"),
            ("the first help line's first letter changes", ts, rom[ts] ^ 0x01, "help line is not"),
        ]
        bad = 0
        for what, off, val, needle in mutants:
            m = bytearray(rom)
            m[off] = val
            got = check(bytes(m), dbg_text, c) + check_desc(bytes(m), dbg_text, dc)
            ok = any(needle in p for p in got)
            print("mutant %-48s %s" % (what, "red" if ok else "MISSED"))
            bad += not ok
        # DESC's own rules: a label left without a description, one too wide for the help window
        for what, edit, needle in [
            ("Rebirth's description is missing", lambda d: d.pop("Rebirth"), "'Rebirth' has no description"),
            ("Facet's description runs past the window", lambda d: d.__setitem__("Facet", DESC["Facet"] + " for good"),
             "'Facet' is"),
        ]:
            d = dict(DESC)
            edit(d)
            got = check_desc(rom, dbg_text, dc, d)
            ok = any(needle in p for p in got)
            print("mutant %-48s %s" % (what, "red" if ok else "MISSED"))
            bad += not ok
        global SPEC
        # a label naming a relic carries that relic's bytes: Shoat's signature labelled "Safety Bit" (which
        # blocks Death, Petrify and Zombie, not Condemned)
        real_spec = SPEC
        i = [r[0] for r in SPEC].index("Shoat")
        SPEC = list(SPEC)
        SPEC[i] = SPEC[i][:4] + (("Safety Bit",) + SPEC[i][4][1:],)
        d = dict(DESC)
        d["Safety Bit"] = DESC["NoDeath/Doom"]
        got = desc_problems(dc, d)
        SPEC = real_spec
        ok = any("'Safety Bit' names a relic" in p for p in got)
        print("mutant %-48s %s" % ("Shoat's signature labelled Safety Bit", "red" if ok else "MISSED"))
        bad += not ok
        # one label, one effect: Shoat's signature (Death and Condemned) labelled like Alexandr's rung 3 (Death)
        real_spec = SPEC
        i = [r[0] for r in SPEC].index("Shoat")
        SPEC = list(SPEC)
        SPEC[i] = SPEC[i][:4] + (("No Death",) + SPEC[i][4][1:],)
        got = desc_problems(dc)
        SPEC = real_spec
        ok = any("'No Death' names two effects" in p for p in got)
        print("mutant %-48s %s" % ("Shoat's signature labelled No Death", "red" if ok else "MISSED"))
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
    print("esper_ladder: the ROM's 26 ladders (130 rungs), their menu labels and help lines match the table")
    return 0


if __name__ == "__main__":
    sys.exit(main())
