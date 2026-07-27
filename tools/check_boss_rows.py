#!/usr/bin/env python3
"""Cross-check docs/design/bosses-wob.md against the shipped break data.

The doc authors, per boss (and per boss part / per add), three numbers:

  * a shield count      -> Ot6ShieldTbl (ff6/src/battle/ot6_hud.asm), else the
                           level formula 2 + level/8 capped at 6
  * an element weakness -> monster_prop.dat +25 (weak) OR'd with any
                           Ot6ElemAddTbl row (ff6/src/battle/ot6_break.asm)
  * a weapon-class      -> Ot6ShieldTbl's class byte, else the generated
    weakness              break floor (ot6_break_floor.inc)

...and occasionally an *absorb* claim, which is monster_prop.dat +23.

This script parses every such claim out of the prose and the markdown tables
and prints one loud line per disagreement, naming the doc line, the claim, the
data, and the file/offset that proves it.

Nothing here writes; it is a read-only linter.  Exit status 0 = clean.

Wired into `make test` (Makefile's test target, alongside the compose.py and
sram_anchor.py selftests) as of the issue #23 pass that emptied WAIVERS.

Usage:  python3 tools/check_boss_rows.py [--repo ROOT] [-v]
"""

from __future__ import annotations

import argparse
import os
import re
import sys

# --------------------------------------------------------------------------
# masks

ELEMENTS = ["fire", "ice", "bolt", "poison", "wind", "holy", "earth", "water"]
ELEMENT_BIT = {name: 1 << i for i, name in enumerate(ELEMENTS)}
# doc / disassembly synonyms
ELEMENT_BIT.update(
    {
        "lightning": 0x04,
        "thunder": 0x04,
        "pearl": 0x20,
        "lit": 0x04,
    }
)

CLASSES = ["slash", "pierce", "bludg", "special"]
CLASS_BIT = {"slash": 0x01, "pierce": 0x02, "bludg": 0x04, "special": 0x08}
CLASS_BIT.update(
    {
        "slashing": 0x01,
        "piercing": 0x02,
        "bludgeon": 0x04,
        "bludgeoning": 0x04,
        "OT6_SLASH": 0x01,
        "OT6_PIERCE": 0x02,
        "OT6_BLUDG": 0x04,
        "OT6_SPECIAL": 0x08,
    }
)
ALL_CLASSES = 0x0F


def elem_str(mask: int) -> str:
    if mask == 0:
        return "(none)"
    return "|".join(n for n in ELEMENTS if mask & ELEMENT_BIT[n])


def class_str(mask: int) -> str:
    if mask == 0:
        return "(none)"
    return "|".join(n for n in CLASSES if mask & CLASS_BIT[n])


# --------------------------------------------------------------------------
# data side

MONSTER_PROP = "ff6/src/battle/monster_prop.dat"
MONSTER_PROP_ADDR = 0xCF0000  # HiROM address of the table
HUD_ASM = "ff6/src/battle/ot6_hud.asm"
BREAK_ASM = "ff6/src/battle/ot6_break.asm"
FLOOR_INC = "ff6/src/battle/ot6_break_floor.inc"
MONSTER_NAMES = "ff6/src/text/monster_name_en.json"
DOC = "docs/design/bosses-wob.md"

REC = 32          # monster_prop record size
OFF_LEVEL = 0x10
OFF_ABSORB = 23
OFF_NULL = 24
OFF_WEAK = 25


class Data:
    def __init__(self, root: str):
        self.root = root
        self.prop = self._read(MONSTER_PROP)
        assert len(self.prop) == REC * 384, len(self.prop)
        self.names = self._monster_names()
        self.shield_tbl = self._parse_shield_tbl()
        self.elem_add = self._parse_elem_add()
        self.floor = self._parse_floor()

    # -- io ------------------------------------------------------------
    def _read(self, rel: str) -> bytes:
        with open(os.path.join(self.root, rel), "rb") as f:
            return f.read()

    def _text(self, rel: str) -> str:
        with open(os.path.join(self.root, rel), "r", encoding="utf-8") as f:
            return f.read()

    def _monster_names(self):
        import json

        with open(os.path.join(self.root, MONSTER_NAMES), encoding="utf-8") as f:
            return json.load(f)["text"]

    # -- vanilla record ------------------------------------------------
    def vanilla_weak(self, sp):
        return self.prop[sp * REC + OFF_WEAK]

    def vanilla_null(self, sp):
        return self.prop[sp * REC + OFF_NULL]

    def vanilla_absorb(self, sp):
        return self.prop[sp * REC + OFF_ABSORB]

    def level(self, sp):
        return self.prop[sp * REC + OFF_LEVEL]

    def prop_cite(self, sp, off):
        """file+offset proof string for a monster_prop byte."""
        fileoff = sp * REC + off
        return "%s +$%04x (rom $%06x)" % (MONSTER_PROP, fileoff,
                                          MONSTER_PROP_ADDR + fileoff)

    # -- effective (what the game actually seeds) ----------------------
    def effective_weak(self, sp):
        return self.vanilla_weak(sp) | self.elem_add.get(sp, (0, None))[0]

    def effective_class(self, sp):
        row = self.shield_tbl.get(sp)
        if row is not None:
            return row["class"], "Ot6ShieldTbl"
        return self.floor[sp], "break floor"

    def effective_shields(self, sp):
        row = self.shield_tbl.get(sp)
        if row is not None:
            return row["shields"], "Ot6ShieldTbl"
        return min(6, 2 + self.level(sp) // 8), "level formula"

    # -- table parsers -------------------------------------------------
    def _parse_shield_tbl(self):
        """Ot6ShieldTbl: .word species / .byte shields, classes"""
        src = self._text(HUD_ASM).splitlines()
        start = next(i for i, l in enumerate(src) if l.strip().startswith("Ot6ShieldTbl:"))
        out = {}
        pending = None
        for i in range(start + 1, len(src)):
            line = src[i]
            code = line.split(";", 1)[0]
            m = re.match(r"\s*\.word\s+\$([0-9a-fA-F]{4})\s*$", code)
            if m:
                v = int(m.group(1), 16)
                if v == 0xFFFF:
                    break
                pending = v
                continue
            m = re.match(r"\s*\.byte\s+(\S+)\s*,\s*(.+?)\s*$", code)
            if m and pending is not None:
                shields = int(m.group(1), 0)
                cls = 0
                for tok in re.split(r"\|", m.group(2)):
                    tok = tok.strip()
                    if tok in ("$00", "0"):
                        continue
                    if tok not in CLASS_BIT:
                        raise SystemExit(
                            "check_boss_rows: unknown class token %r at %s:%d"
                            % (tok, HUD_ASM, i + 1)
                        )
                    cls |= CLASS_BIT[tok]
                out[pending] = {
                    "shields": shields,
                    "class": cls,
                    "line": i + 1,
                    "comment": (line.split(";", 1)[1].strip() if ";" in line else ""),
                }
                pending = None
        return out

    def _parse_elem_add(self):
        """Ot6ElemAddTbl: .word species / .byte elements, pad"""
        src = self._text(BREAK_ASM).splitlines()
        start = next(i for i, l in enumerate(src) if l.strip().startswith("Ot6ElemAddTbl:"))
        out = {}
        pending = None
        for i in range(start + 1, len(src)):
            code = src[i].split(";", 1)[0]
            m = re.match(r"\s*\.word\s+\$([0-9a-fA-F]{4})\s*$", code)
            if m:
                v = int(m.group(1), 16)
                if v == 0xFFFF:
                    break
                pending = v
                continue
            m = re.match(r"\s*\.byte\s+\$([0-9a-fA-F]{2})\s*,", code)
            if m and pending is not None:
                out[pending] = (int(m.group(1), 16), i + 1)
                pending = None
        return out

    def _parse_floor(self):
        """ot6_break_floor.inc: one .byte per species, in id order."""
        src = self._text(FLOOR_INC)
        vals = []
        for line in src.splitlines():
            code = line.split(";", 1)[0]
            m = re.match(r"\s*\.byte\s+(.+?)\s*$", code)
            if not m:
                continue
            for tok in m.group(1).split(","):
                tok = tok.strip()
                if not tok:
                    continue
                v = 0
                for part in tok.split("|"):
                    part = part.strip()
                    if part in ("$00", "0"):
                        continue
                    v |= CLASS_BIT.get(part, 0)
                vals.append(v)
        return vals


# --------------------------------------------------------------------------
# doc side: species resolution
#
# Rows that carry an id inline (`$003A`, `($10D)`) resolve themselves.  The
# rest are resolved from this table, keyed by (section key, row label).  A row
# that resolves to nothing is a LOUD failure, never a silent skip -- that is
# the whole point of the exercise.

RESOLVE = {
    # boss section -> {row label (lowercased, trimmed) -> species id}
    "1": {"head": 0x134, "shell": 0x100, "whelk": 0x134},
    "2": {"marshal": 0x064, "lobos": 0x019, "*": 0x064},
    "3": {"vargas": 0x103, "ipoohs": 0x14D, "*": 0x103},
    "4": {"ultros ①": 0x12C, "*": 0x12C},
    "5": {"tunnelarmor": 0x104, "*": 0x104},
    "6-7": {"telstar": 0x044, "dobermans": 0x01A},
    "8": {"ghosttrain": 0x106, "*": 0x106},
    "9": {"rizopas": 0x155, "piranhas": 0x154, "*": 0x155},
    "10": {"kefka": 0x14A, "*": 0x14A},
    "11": {"dadaluma": 0x107, "iron fists": 0x06C, "*": 0x107},
    "12": {"ultros ②": 0x12D, "*": 0x12D},
    "13": {"ifrit": 0x109, "shiva": 0x108, "ifrit & shiva": None},
    "14": {"number 024": 0x10A, "*": 0x10A},
    "15": {"body": 0x10B, "left/right blades": (0x13F, 0x140), "number 128": 0x10B},
    "16": {},  # ids inline in the row labels
    "17": {"ultros ③": 0x12E, "*": 0x12E},
    "18": {"flameeater": 0x116, "balloons": 0x0DE, "*": 0x116},
    "19": {"ultros ④": 0x168, "chupon": 0x12F},
    "20": {"airforce": 0x113, "laser gun": 0x145, "missilebay": 0x147,
           "speck": 0x146, "pods": (0x145, 0x147)},
    "21": {"atmaweapon": 0x117, "*": 0x117},
    "22": {"nerapa": 0x118, "*": 0x118},
    # the at-a-glance curve table (### numbers double as its "#" column)
}

# The at-a-glance curve table's "#" column -> the boss body/bodies its
# "Shields" cell counts, in the order the cell lists them ("6 + 6").
# () = deliberately no monster entity at all (see the doc's §6-7 decode).
CURVE_MAIN = {
    "1": (0x134,), "2": (0x064,), "3": (0x103,), "4": (0x12C,), "5": (0x104,),
    "6": (), "7": (0x044,), "8": (0x106,), "9": (0x155,), "10": (0x14A,),
    "11": (0x107,), "12": (0x12D,), "13": (0x109, 0x108), "14": (0x10A,),
    "15": (0x10B,), "16": (0x10D, 0x10E), "17": (0x12E,), "18": (0x116,),
    "19": (0x168, 0x12F), "20": (0x113,), "21": (0x117,), "22": (0x118,),
}

# The curve table's per-row add-on names, e.g. "4 (Lobos 2)".
CURVE_ADDS = {
    "lobos": 0x019, "ipoohs": 0x14D, "dobermans": 0x01A, "piranhas": 0x154,
    "iron fists": 0x06C, "balloons": 0x0DE, "blades": (0x13F, 0x140),
    "pods": (0x145, 0x147), "speck": 0x146,
}

# "the row" = Ultros's authored row, stated in full at Ultros ①.  Rows that
# say "the row" are claiming exactly that, so resolve them to it rather than
# silently skipping.
ULTROS_ROW_ELEMS = ELEMENT_BIT["fire"] | ELEMENT_BIT["bolt"]
ULTROS_ROW_CLASSES = CLASS_BIT["slash"] | CLASS_BIT["pierce"]


# --------------------------------------------------------------------------
# Acknowledged open decisions: (species, "ELEMENT"|"CLASS"|"SHIELDS") ->
# reason.  A waived mismatch is still PRINTED, loudly and in full, in its own
# section -- it just does not fail the run, so this can join `make test`
# without being permanently red.  Every entry names the doc block that
# argues it; delete the entry when the decision lands either way.
#
# Nothing is waived by default in bulk: waiving is per species AND per axis,
# so an unrelated drift on the same boss still fails.

WAIVERS = {
    # EMPTY, and that is the point.  The four entries that lived here --
    # Number 128's body and both blades, and AtmaWeapon's whole element row --
    # were all authored into Ot6ElemAddTbl by the v0.6 boss-element pass
    # (issue #23), along with FlameEater's water and Ultros ④'s bolt.  Every
    # OPEN DECISION block in bosses-wob.md is now a RESOLVED block.
    #
    # With no waivers left this script is a plain gate, and it is registered in
    # `make test` (the Makefile's test target, next to the compose/sram_anchor
    # selftests) so doc-vs-data drift fails the suite from here.  Suite.sh's own
    # discovery globs *.lua for a `-- @suite` marker and cannot see a .py file,
    # which is why registration is a Makefile line rather than a marker.
}


# --------------------------------------------------------------------------
# doc side: claim extraction

class Claim:
    __slots__ = ("line", "where", "label", "species", "shields", "elems",
                 "classes", "absorbs", "elem_add", "note")

    def __init__(self, line, where, label, species):
        self.line = line
        self.where = where
        self.label = label
        self.species = species
        self.shields = None
        self.elems = None      # None = not claimed
        self.classes = None
        self.absorbs = None
        self.elem_add = None   # doc claims THIS element comes from ElemAddTbl
        self.note = ""

    def __repr__(self):
        return "<Claim %s:%d %s sp=%s>" % (self.where, self.line, self.label,
                                           self.species)


ELEM_TOKEN = re.compile(
    r"\b(fire|ice|bolt|lightning|thunder|poison|wind|holy|pearl|earth|water)\b", re.I)
CLASS_TOKEN = re.compile(
    r"\b(slashing|slash|piercing|pierce|bludgeoning|bludgeon|bludg|special)\b", re.I)


def parse_masks(text):
    """Split a 'a, b + c, d' weakness phrase into (element mask, class mask).

    Returns (elems, classes, ok).  ok=False when the phrase carries no
    recognisable token at all -- the caller decides whether that is prose
    (fine) or a broken regex (loud)."""
    elems = 0
    classes = 0
    for m in ELEM_TOKEN.finditer(text):
        elems |= ELEMENT_BIT[m.group(1).lower()]
    for m in CLASS_TOKEN.finditer(text):
        classes |= CLASS_BIT[m.group(1).lower()]
    return elems, classes, bool(elems or classes)


CELL_SPLIT = re.compile(r"(?<!\\)\|")


def split_cells(line):
    """Split a markdown table row, honouring \\| escapes inside cells."""
    body = line.strip()
    body = CELL_SPLIT.sub("\x00", body).strip("\x00")
    return [c.replace("\\|", "|").strip() for c in body.split("\x00")]


def norm(s):
    s = s.strip()
    s = re.sub(r"\*\*|\*|`", "", s)
    s = re.sub(r"\s+", " ", s)
    return s.strip().lower()


ID_IN_TEXT = re.compile(r"\$([0-9a-fA-F]{2,4})\b")


def id_from_label(label):
    m = ID_IN_TEXT.search(label)
    if m:
        return int(m.group(1), 16)
    return None


def strip_id(label):
    return norm(ID_IN_TEXT.sub("", label).replace("(", " ").replace(")", " "))


def extract_claims(doc_text):
    """Walk the doc and pull every element/class/shield claim out of it."""
    lines = doc_text.splitlines()
    claims = []
    section = None            # current "### N." key
    shapes = {"curve": 0, "prose": 0, "parts": 0, "species": 0, "decode": 0}

    # --- shape A: the at-a-glance curve table (shields only) ---------
    for i, line in enumerate(lines):
        if not line.startswith("| ") or "|" not in line[2:]:
            continue
        cells = split_cells(line)
        if len(cells) == 4 and re.fullmatch(r"\d+", cells[0]):
            num, boss, _where, shields = cells
            if num not in CURVE_MAIN:
                raise SystemExit(
                    "check_boss_rows: curve row #%s (%s:%d) is not in CURVE_MAIN"
                    % (num, DOC, i + 1))
            bodies = CURVE_MAIN[num]
            counts = [int(x) for x in re.findall(r"(?<![\d/])(\d+)(?![\d/])",
                                                 shields.split("(")[0])]
            if bodies and len(counts) != len(bodies):
                raise SystemExit(
                    "check_boss_rows: curve row #%s (%s:%d) lists %d shield "
                    "counts for %d bodies -- CURVE_MAIN has drifted"
                    % (num, DOC, i + 1, len(counts), len(bodies)))
            for sp, n in zip(bodies, counts):
                c = Claim(i + 1, "curve", boss, sp)
                c.shields = n
                claims.append(c)
                shapes["curve"] += 1
            # parenthetical adds: "(Lobos 2)", "(pods 3/3, Speck 1)"
            par = re.search(r"\((.*)\)", shields)
            if par:
                for chunk in par.group(1).split(","):
                    mm = re.match(r"\s*([A-Za-z' ]+?)\s+(\d+)", chunk)
                    if not mm:
                        continue
                    who = norm(mm.group(1))
                    sp = CURVE_ADDS.get(who)
                    if sp is None:
                        continue
                    for one in (sp if isinstance(sp, tuple) else (sp,)):
                        c = Claim(i + 1, "curve", mm.group(1).strip(), one)
                        c.shields = int(mm.group(2))
                        claims.append(c)
                        shapes["curve"] += 1

    # --- walk sections for shapes B/C/D/E ----------------------------
    i = 0
    while i < len(lines):
        line = lines[i]
        m = re.match(r"^###\s+([0-9–\-]+)\.\s*(.*)$", line)
        if m:
            section = m.group(1).replace("–", "-")
        elif line.startswith("###") or line.startswith("## "):
            if not re.match(r"^###\s+[0-9]", line):
                # non-numbered heading: keep the last numbered section only for
                # tables that immediately follow it (species tables carry ids)
                pass

        # shape B: prose "**Shields:** N ... **Weak:** ..."
        if "**Shields:**" in line:
            para = line
            j = i + 1
            while j < len(lines) and lines[j].strip() and not lines[j].startswith("- "):
                para += " " + lines[j]
                j += 1
            claims.extend(_prose_claims(para, i + 1, section, shapes))

        # shape B': "**Telstar:** 4 shields · bolt + bludgeoning (Dobermans 2 · piercing)."
        m2 = re.match(r"^\*\*([A-Za-z][A-Za-z0-9 ]*):\*\*\s+(\d+)\s+shields?\s*·\s*(.*)$", line)
        if m2 and section:
            para = m2.group(3)
            j = i + 1
            while j < len(lines) and lines[j].strip() and not lines[j].startswith("- "):
                para += " " + lines[j]
                j += 1
            sec = RESOLVE.get(section, {})
            sp = sec.get(norm(m2.group(1)))
            if sp is not None:
                head, _, tail = para.partition("(")
                e, c, ok = parse_masks(head)
                cl = Claim(i + 1, "prose", m2.group(1), sp)
                cl.shields = int(m2.group(2))
                if ok:
                    cl.elems, cl.classes = e, c
                claims.append(cl)
                shapes["prose"] += 1
                mm = re.match(r"\s*([A-Za-z' ]+?)\s+(\d+)\s*·\s*([^)]*)", tail)
                if mm:
                    sp2 = sec.get(norm(mm.group(1)))
                    if sp2 is not None:
                        e2, c2, ok2 = parse_masks(mm.group(3))
                        cl2 = Claim(i + 1, "prose", mm.group(1).strip(), sp2)
                        cl2.shields = int(mm.group(2))
                        if ok2:
                            cl2.elems = e2 if e2 else None
                            cl2.classes = c2 if c2 else None
                        claims.append(cl2)
                        shapes["prose"] += 1

        # shapes C/D: markdown tables
        if line.startswith("| ") and i + 1 < len(lines) and set(lines[i + 1].strip()) <= set("|-: "):
            hdr = [norm(c) for c in split_cells(line)]
            j = i + 2
            while j < len(lines) and lines[j].startswith("|"):
                cells = split_cells(lines[j])
                _table_row(hdr, cells, j + 1, section, claims, shapes)
                j += 1
            i = j
            continue

        # shape E: inline decode notes "`$104` weak = **bolt|water**"
        for m3 in re.finditer(
                r"`\$([0-9a-fA-F]{2,4})`\s+weak\s*=\s*\*{0,2}([a-z|]+)\*{0,2}", line):
            sp = int(m3.group(1), 16)
            e, _c, ok = parse_masks(m3.group(2))
            if ok:
                cl = Claim(i + 1, "decode", "$%03x" % sp, sp)
                cl.elems = e
                cl.note = "decode note"
                claims.append(cl)
                shapes["decode"] += 1
        for m4 in re.finditer(
                r"`\$([0-9a-fA-F]{2,4})`\s+(?:weak\s*=\s*[a-z|]+(?:,)?\s*)?absorbs?\s+([a-z]+)", line):
            sp = int(m4.group(1), 16)
            a, _c, ok = parse_masks(m4.group(2))
            if ok:
                cl = Claim(i + 1, "decode", "$%03x" % sp, sp)
                cl.absorbs = a
                cl.note = "decode note (absorb)"
                claims.append(cl)
                shapes["decode"] += 1

        i += 1

    return claims, shapes


def _prose_claims(para, lineno, section, shapes):
    out = []
    sec = RESOLVE.get(section or "", {})
    main = sec.get("*")
    m = re.search(r"\*\*Shields:\*\*\s*(\d+)", para)
    if m is None or main is None:
        return out
    cl = Claim(lineno, "prose", section or "?", main)
    cl.shields = int(m.group(1))

    w = re.search(r"\*\*Weak:\*\*\s*(.*)", para)
    if w:
        phrase = w.group(1)
        # cut at the first sentence/aside boundary
        phrase = re.split(r"(?:\.\s|\s—\s|\s·\s|\()", phrase, maxsplit=1)[0]
        if "the row" in phrase:
            cl.elems = ULTROS_ROW_ELEMS
            cl.classes = ULTROS_ROW_CLASSES
            cl.note = '"the row" (Ultros)'
        elif "rotating" in phrase.lower():
            cf = re.search(r"Classes fixed:\s*([^.]+)", para)
            if cf:
                _e, c, _ok = parse_masks(cf.group(1))
                cl.classes = c
            cl.note = "element row rotates (WallChange) — element check skipped"
        else:
            e, c, ok = parse_masks(phrase)
            if not ok:
                cl.note = "UNPARSED weak phrase: %r" % phrase[:60]
            else:
                cl.elems, cl.classes = e, c
    out.append(cl)
    shapes["prose"] += 1

    # absorb aside: "· **absorbs poison.**"
    a = re.search(r"\*\*absorbs? ([a-z]+)", para)
    if a:
        cl.absorbs = ELEMENT_BIT.get(a.group(1).lower(), 0)

    # trailing add clause: "Lobos: 2 · fire + piercing."
    for mm in re.finditer(r"([A-Z][A-Za-z' ]*?):\s*(\d+)\s*·\s*([^.]+)", para):
        who = norm(mm.group(1))
        sp = sec.get(who)
        if sp is None:
            continue
        for one in (sp if isinstance(sp, tuple) else (sp,)):
            c2 = Claim(lineno, "prose", mm.group(1).strip(), one)
            c2.shields = int(mm.group(2))
            e, c, ok = parse_masks(mm.group(3))
            if ok:
                c2.elems = e if e else None
                c2.classes = c if c else None
            out.append(c2)
            shapes["prose"] += 1

    # inline add count: "**Shields:** 7 (Balloons 1 each)"
    par = re.search(r"\*\*Shields:\*\*\s*\d+\s*\(([^)]*)\)", para)
    if par:
        mm = re.match(r"\s*([A-Za-z' ]+?)\s+(\d+)", par.group(1))
        if mm:
            sp = sec.get(norm(mm.group(1)))
            if sp is not None:
                for one in (sp if isinstance(sp, tuple) else (sp,)):
                    c2 = Claim(lineno, "prose", mm.group(1).strip(), one)
                    c2.shields = int(mm.group(2))
                    out.append(c2)
                    shapes["prose"] += 1
    return out


def _table_row(hdr, cells, lineno, section, claims, shapes):
    if len(cells) != len(hdr):
        return
    row = dict(zip(hdr, cells))

    # shape D: "| species | id | shields · class | ... |"
    if "id" in row and "species" in row:
        sp = id_from_label(row["id"])
        if sp is None:
            return
        cl = Claim(lineno, "species-table", row["species"], sp)
        sc = row.get("shields · class") or row.get("shields · class ") or ""
        m = re.match(r"\s*(\d+)\s*·\s*(.*)", sc)
        if m:
            cl.shields = int(m.group(1))
            body = m.group(2)
            # "(+bolt)" is an element-ADD claim, not the full weak row --
            # split it off before reading the class tokens.
            plus = re.search(r"\(\+\s*([a-z|, ]+)\)", body)
            if plus:
                body = body.replace(plus.group(0), " ")
                pe, _pc, pok = parse_masks(plus.group(1))
                if pok:
                    cl.elem_add = pe
                    cl.note = "claims element ADD %s" % elem_str(pe)
            _e, c, _ok = parse_masks(body.replace("\\|", "|"))
            cl.classes = c or None
        claims.append(cl)
        shapes["species"] += 1
        return

    # shape C: "| part | shields | weak |"
    if "part" in row and "shields" in row and "weak" in row:
        label = row["part"]
        sec = RESOLVE.get(section or "", {})
        sp = id_from_label(label)
        if sp is None:
            key = strip_id(label)
            sp = sec.get(key)
            if sp is None:
                for k, v in sec.items():
                    if k != "*" and k and k in key:
                        sp = v
                        break
        if sp is None:
            c = Claim(lineno, "part-table", label, None)
            c.note = "UNRESOLVED part label"
            claims.append(c)
            shapes["parts"] += 1
            return
        for one in (sp if isinstance(sp, tuple) else (sp,)):
            cl = Claim(lineno, "part-table", label, one)
            ms = re.match(r"\s*(\d+)", row["shields"])
            if ms:
                cl.shields = int(ms.group(1))
            elif "no gauge" in row["shields"] or row["shields"].startswith("—"):
                cl.shields = 0
            weak = row["weak"]
            if weak in ("—", "-", ""):
                cl.note = "no gauge"
            elif "any physical class" in weak:
                cl.classes = ALL_CLASSES
                cl.note = "any physical class"
                e, _c, ok = parse_masks(weak)
                cl.elems = e if ok and e else None
            elif "the row" in weak and not ELEM_TOKEN.search(weak):
                # bare "the row" with no elements spelled out
                cl.elems = ULTROS_ROW_ELEMS
                cl.classes = ULTROS_ROW_CLASSES
                cl.note = '"the row" (Ultros)'
            else:
                e, c, ok = parse_masks(weak)
                if not ok:
                    cl.note = "UNPARSED weak cell: %r" % weak
                else:
                    # a cell that names only classes is not claiming "no
                    # element" -- it is silent about the element row.
                    cl.elems = e if e else None
                    cl.classes = c if c else None
            claims.append(cl)
            shapes["parts"] += 1


# --------------------------------------------------------------------------
# comparison

def check(root, verbose=False):
    data = Data(root)
    doc_path = os.path.join(root, DOC)
    with open(doc_path, encoding="utf-8") as f:
        doc = f.read()
    claims, shapes = extract_claims(doc)

    problems = []
    notes = []
    waived = []
    seen_waivers = set()

    def report(species, kind, text):
        """Route one finding to problems or to the waived list."""
        key = (species, kind)
        if key in WAIVERS:
            seen_waivers.add(key)
            waived.append("%s\n    WAIVED: %s" % (text, WAIVERS[key]))
        else:
            problems.append(text)

    # ---- self-check: the parser must actually have matched things ----
    MINIMUM = {"curve": 20, "prose": 14, "parts": 12, "species": 12, "decode": 3}
    for shape, need in MINIMUM.items():
        if shapes.get(shape, 0) < need:
            problems.append(
                "PARSER SELF-CHECK FAILED: shape %r matched %d rows, expected >= %d. "
                "The regex has drifted from the document -- fix the parser before "
                "trusting a clean run." % (shape, shapes.get(shape, 0), need))
    if not claims:
        problems.append("PARSER SELF-CHECK FAILED: zero claims parsed.")

    for c in claims:
        if c.species is None:
            problems.append(
                "%s:%d  [%s] %s -- %s (add it to RESOLVE in this script)"
                % (DOC, c.line, c.where, c.label, c.note))
            continue
        name = data.names[c.species]
        tag = "%s:%d  %s ($%03x %s)" % (DOC, c.line, c.label, c.species, name)

        if c.note.startswith("UNPARSED"):
            problems.append("%s\n    %s" % (tag, c.note))

        # a row that names classes but no element, for a species that HAS
        # one: not a contradiction, but a hole worth naming.
        if (c.elems is None and c.classes is not None
                and c.where in ("part-table", "prose")
                and data.effective_weak(c.species)):
            notes.append(
                "%s\n    row states no element weakness; data has %s"
                % (tag, elem_str(data.effective_weak(c.species))))

        # -- element weakness ------------------------------------------
        if c.elems is not None:
            van = data.vanilla_weak(c.species)
            add, addline = data.elem_add.get(c.species, (0, None))
            eff = van | add
            if c.where == "decode":
                # a decode note quotes monster_prop.dat directly: compare it
                # to the VANILLA byte, not the seeded (vanilla|add) row.
                eff, add, addline = van, 0, None
            if c.elems != eff:
                missing = c.elems & ~eff
                extra = eff & ~c.elems
                bits = []
                if missing:
                    bits.append("doc claims %s that the data does not have"
                                % elem_str(missing))
                if extra:
                    bits.append("data has %s that the doc does not list"
                                % elem_str(extra))
                proof = "%s = $%02x (%s)" % (data.prop_cite(c.species, OFF_WEAK),
                                             van, elem_str(van))
                if add:
                    proof += "; +Ot6ElemAddTbl $%02x (%s:%d)" % (add, BREAK_ASM, addline)
                else:
                    proof += "; no Ot6ElemAddTbl row"
                report(c.species, "ELEMENT",
                       "%s\n    ELEMENT: doc says %s, data says %s\n    %s\n    %s"
                       % (tag, elem_str(c.elems), elem_str(eff), "; ".join(bits), proof))

        # -- claimed element ADD ---------------------------------------
        if c.elem_add is not None:
            add, addline = data.elem_add.get(c.species, (0, None))
            if c.elem_add & ~add:
                report(c.species, "ELEMENT",
                    "%s\n    ELEMENT ADD: doc claims +%s, Ot6ElemAddTbl gives %s\n"
                    "    %s%s"
                    % (tag, elem_str(c.elem_add), elem_str(add), BREAK_ASM,
                       (":%d" % addline) if addline else " (no row for this species)"))

        # -- weapon class ----------------------------------------------
        if c.classes is not None:
            eff, src = data.effective_class(c.species)
            if c.classes != eff:
                row = data.shield_tbl.get(c.species)
                proof = ("%s:%d" % (HUD_ASM, row["line"])) if row else (
                    "%s (generated; no Ot6ShieldTbl row)" % FLOOR_INC)
                report(c.species, "CLASS",
                    "%s\n    CLASS: doc says %s, data says %s (%s)\n    %s"
                    % (tag, class_str(c.classes), class_str(eff), src, proof))

        # -- shields ----------------------------------------------------
        if c.shields is not None:
            eff, src = data.effective_shields(c.species)
            if c.shields != eff:
                row = data.shield_tbl.get(c.species)
                proof = ("%s:%d" % (HUD_ASM, row["line"])) if row else (
                    "no Ot6ShieldTbl row; level %d -> 2 + %d/8"
                    % (data.level(c.species), data.level(c.species)))
                report(c.species, "SHIELDS",
                    "%s\n    SHIELDS: doc says %d, data says %d (%s)\n    %s"
                    % (tag, c.shields, eff, src, proof))

        # -- absorb -----------------------------------------------------
        if c.absorbs is not None:
            eff = data.vanilla_absorb(c.species)
            if c.absorbs & ~eff:
                report(c.species, "ABSORB",
                    "%s\n    ABSORB: doc says %s, data says %s\n    %s = $%02x"
                    % (tag, elem_str(c.absorbs), elem_str(eff),
                       data.prop_cite(c.species, OFF_ABSORB), eff))

        # -- an element weakness the party would HEAL --------------------
        if c.elems:
            heal = c.elems & data.vanilla_absorb(c.species)
            if heal:
                report(c.species, "TRAP",
                    "%s\n    TRAP: doc lists %s as a weakness but the species "
                    "ABSORBS it\n    %s = $%02x"
                    % (tag, elem_str(heal), data.prop_cite(c.species, OFF_ABSORB),
                       data.vanilla_absorb(c.species)))

    if verbose:
        print("parsed %d claims: %s" % (len(claims), shapes))
        for c in sorted(claims, key=lambda c: c.line):
            print("  %4d %-14s %-22s sp=%s sh=%s el=%s cl=%s %s"
                  % (c.line, c.where, c.label,
                     ("$%03x" % c.species) if c.species is not None else "?",
                     c.shields,
                     elem_str(c.elems) if c.elems is not None else "-",
                     class_str(c.classes) if c.classes is not None else "-",
                     c.note))

    # a waiver nobody trips any more is stale: say so rather than rot.
    for key in sorted(WAIVERS):
        if key not in seen_waivers:
            problems.append(
                "STALE WAIVER: WAIVERS[($%03x, %r)] never fired -- the mismatch "
                "it covers is gone (or the parser stopped seeing the row). "
                "Delete it.\n    %s" % (key[0], key[1], WAIVERS[key]))

    return problems, notes, waived, claims, shapes


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--repo", default=os.path.dirname(os.path.dirname(
        os.path.abspath(__file__))))
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()

    problems, notes, waived, claims, shapes = check(args.repo, args.verbose)
    print("bosses-wob.md consistency check")
    print("  parsed %d claims %s" % (len(claims), shapes))
    if problems:
        print("  %d PROBLEM(S):" % len(problems))
        print()
        for p in problems:
            print("  " + p.replace("\n", "\n  "))
            print()
    else:
        print("  OK -- every parsed row agrees with monster_prop.dat + "
              "Ot6ShieldTbl + Ot6ElemAddTbl")
    if waived:
        print("  %d WAIVED (acknowledged open decisions, not failures):" % len(waived))
        print()
        for w in waived:
            print("  " + w.replace("\n", "\n  "))
            print()
    if notes:
        print("  %d NOTE(S) -- rows silent where the data has something to say:"
              % len(notes))
        print()
        for n in notes:
            print("  " + n.replace("\n", "\n  "))
            print()
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
