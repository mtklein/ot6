#!/usr/bin/env python3
"""rewrite_class.py -- the six-class prototype's source rewrite of
ff6/src/battle/ot6_class.asm's two tables (from v0.50's four classes), and of
the item-name icons and type words that show a weapon's class.

Run from the repo root.  Idempotent: it reads v0.50's ot6_class.asm from git.
"""
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


# item id -> new class, by the v0.50 table's own blocks
def weapon_class(i, old):
    if old == "$00":
        return "$00"
    null = "|OT6_NULLBRK" if "OT6_NULLBRK" in old else ""
    if 0x00 <= i <= 0x09:
        c = "OT6_DAGGER"
    elif 0x0a <= i <= 0x1c:
        c = "OT6_SWORD"
    elif 0x1d <= i <= 0x24:
        c = "OT6_SPEAR"
    elif 0x25 <= i <= 0x32:
        c = "OT6_KATANA"       # ninja blades, katanas
    elif 0x34 <= i <= 0x40:
        c = "OT6_ARCANE"       # rods, brushes
    elif 0x41 <= i <= 0x43:
        c = "OT6_DAGGER"       # thrown stars
    elif i in (0x44, 0x46, 0x4a):
        c = "OT6_FIST"         # flail, morning star, bone club
    elif i in (0x45, 0x47, 0x48, 0x4b, 0x4c):
        c = "OT6_ARCANE"       # the returning arcs
    elif i == 0x49:
        c = "OT6_DAGGER"       # hawk eye: a thrown blade
    elif i in (0x4d, 0x50, 0x51, 0x52):
        c = "OT6_ARCANE"       # cards, trump, dice
    elif i in (0x4e, 0x4f):
        c = "OT6_DAGGER"       # darts
    elif 0x53 <= i <= 0x59:
        c = "OT6_FIST"         # claws, knuckles, fangs
    elif i == 0xa6:
        c = "OT6_SWORD"        # chain saw
    elif i in (0xa8, 0xa9, 0xaa):
        c = "OT6_SPEAR"        # drill, air anchor, autocrossbow
    elif i == 0xff:
        c = "OT6_FIST"         # the empty hand
    else:
        raise SystemExit("no six-class rule for item $%02x (%s)" % (i, old))
    return c + null


SKILL = {0x55: "OT6_KATANA", 0x57: "OT6_KATANA", 0x58: "OT6_KATANA", 0x5a: "OT6_KATANA", 0x5c: "OT6_KATANA",
         0x5d: "OT6_FIST", 0x5f: "OT6_FIST", 0x64: "OT6_FIST", 0x8a: "OT6_SPEAR",
         0x51: "OT6_DAGGER", 0x52: "OT6_DAGGER", 0x53: "OT6_DAGGER"}

ICON = {"OT6_DAGGER": "{dagger}", "OT6_SWORD": "{sword}", "OT6_SPEAR": "{spear}", "OT6_KATANA": "{katana}",
        "OT6_FIST": "{claw}", "OT6_ARCANE": "{special}"}

CONSTS = """\
; six-class prototype (wt/proto-six-classes, #566): v0.50's four classes each
; split in two.  bits $01..$08 keep their v0.50 parent (slash, pierce,
; bludgeon, special), so a v0.50 save's revealed class bits read as the
; first child of what they were.
OT6_SWORD   := $01              ; swords, the chain saw (was slash)
OT6_DAGGER  := $02              ; daggers, thrown stars and edges, darts,
                                ;   a thief's hit (was pierce)
OT6_FIST    := $04              ; fists, claws, fangs, clubs, flails (was
                                ;   bludgeon; the claws were slash)
OT6_ARCANE  := $08              ; rods, brushes, cards, dice, coins, the
                                ;   returning arcs (was special; the rods
                                ;   and arcs were bludgeon)
OT6_KATANA  := $10              ; katanas, ninja blades, swdtech (was
                                ;   slash; the ninja blades were pierce)
OT6_SPEAR   := $20              ; spears, bolts, the drill, the air anchor,
                                ;   tekmissile (was pierce)
OT6_CLASSES := $3f              ; every class bit
OT6_NCLASS  = 6
OT6_NULLBRK := $80              ; property, not a class: high damage that
                                ;   chips nothing (the physical mirror of
                                ;   non-elemental magic). class bits stay set
                                ;   for future consumers (equip permits, hud).

; the classes the kits load by hand (no weapon, no table row)
OT6_CLS_THIEF = OT6_DAGGER      ; Mug, Trickshot and the rest of Locke's hits
OT6_CLS_COIN  = OT6_ARCANE      ; Coin Toss and a character's GP Rain
OT6_CLS_CLUB  = OT6_FIST        ; Umaro's Charge and Throw

"""

KIT_TBL = """\
; ------------------------------------------------------------------------------

; [ the kits' hand-loaded classes, as data ]

; the harness reads these (tools/tests/lib/ot6.lua M.kitClass) so its key
; model follows the ROM: +0 a thief's hit, +1 the coins, +2 Umaro's club,
; +3 the classes a hire may swing (Ot6HireClass: the first the target is
; weak to, in bit order)
Ot6KitClassTbl:
        .byte   OT6_CLS_THIEF, OT6_CLS_COIN, OT6_CLS_CLUB, OT6_CLASSES

"""


def main():
    old = subprocess.run(["git", "show", "origin/main:ff6/src/battle/ot6_class.asm"], cwd=ROOT, check=True,
                         capture_output=True, text=True).stdout.splitlines()
    out, item, mode, classes = [], 0, None, {}
    for line in old:
        if line.startswith("Ot6WeapClassTbl:"):
            mode = "weap"
        elif line.startswith("Ot6SkillClassTbl:"):
            mode = "skill"
        m = re.match(r"(\s+\.byte\s+)(\S+)(\s*;.*)?$", line)
        r = re.match(r"\s+\.res\s+\$([0-9a-f]+) - \$([0-9a-f]+)", line)
        if mode == "weap" and r:
            item = int(r.group(1), 16)
        elif mode == "weap" and m:
            new = weapon_class(item, m.group(2))
            classes[item] = new
            line = "%s%-16s%s" % (m.group(1), new, (m.group(3) or "").lstrip())
            item += 1
        elif mode == "skill":
            s = re.match(r"(\s+\.byte\s+)\$([0-9a-f]{2}), (OT6_\w+)(\s*;.*)?$", line)
            if s:
                line = "%s$%s, %-11s%s" % (s.group(1), s.group(2), SKILL[int(s.group(2), 16)],
                                           (s.group(4) or "").lstrip())
        out.append(line.rstrip())
    assert item == 0x100, hex(item)
    text = "\n".join(out) + "\n"
    head = text.index("OT6_SLASH   :=")
    tail = text.index('.segment "ot6_code"')
    text = text[:head] + CONSTS + text[tail:] + "\n" + KIT_TBL
    (ROOT / "ff6/src/battle/ot6_class.asm").write_text(text)

    # the item names wear their class's icon; the type column names it
    p = ROOT / "ff6/src/text/item_name_en.json"
    d = json.loads(p.read_text())
    for i, c in classes.items():
        if i > 0x59:
            continue
        name = re.sub(r"^\{\w+\}", "", d["text"][i])
        d["text"][i] = (ICON[c.split("|")[0]] if c != "$00" else "{card}") + name
    p.write_text(json.dumps(d, indent=2, ensure_ascii=False))
    p = ROOT / "ff6/src/text/item_type_name_en.json"
    d = json.loads(p.read_text())
    d["text"][0:10] = ["DAGGER", "SWORD", "SPEAR", "KATANA", "STAFF", "BRUSH", "STARS", "ARCANE", "-----", "FIST"]
    p.write_text(json.dumps(d, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
