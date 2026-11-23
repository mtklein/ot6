#!/usr/bin/env python3
"""rewrite_class.py -- write ff6/src/battle/ot6_class.asm's two tables, the
weapons' name icons and the item menu's type words from classes.py (#566).

Run from the repo root.  Idempotent: it rebuilds the tables from the
four-class ot6_class.asm at BASE (origin/main, or $OT6_SPLIT_BASE), keeping
that file's row comments.
"""
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import classes as C  # noqa: E402

BASE = os.environ.get("OT6_SPLIT_BASE", "origin/main")
ICON = {C.DAGGER: "{dagger}", C.SWORD: "{sword}", C.SPEAR: "{spear}", C.KATANA: "{katana}", C.BLUNT: "{staff}",
        C.RANGED: "{star}"}
# the item menu's type word, by icon cell $d8..$e1
TYPE_WORDS = ["DAGGER", "SWORD", "SPEAR", "KATANA", "BLUNT", "BRUSH", "RANGED", "SPECIAL", "-----", "CLAW"]

CONSTS = """\
; six weapon classes (#566), after Octopath's six: the four of v0.50 and
; before (slash $01, pierce $02, bludgeon $04, special $08) regrouped by the
; weapon in hand.  tools/proto_six/classes.py is the grouping as data, and
; this file's two tables are written from it.
OT6_SWORD   := $01              ; swords; the chain saw
OT6_DAGGER  := $02              ; daggers and ninja blades; a thief's hit
OT6_BLUNT   := $04              ; fists and knuckles, rods and brushes, flails
                                ;   and clubs; the blitzes' blows; umaro's arms
OT6_RANGED  := $08              ; what is thrown or shot: stars, skeans, darts,
                                ;   cards, dice, coins, boomerangs, the
                                ;   autocrossbow, the air anchor, tekmissile
OT6_KATANA  := $10              ; katanas and the edged claws; swdtech
OT6_SPEAR   := $20              ; spears; the drill
OT6_CLASSES := $3f              ; every class bit
OT6_NCLASS  = 6
OT6_NULLBRK := $80              ; property, not a class: high damage that
                                ;   chips nothing (the physical mirror of
                                ;   non-elemental magic). class bits stay set
                                ;   for future consumers (equip permits, hud).

; the classes the kits load by hand (no weapon, no table row)
OT6_CLS_THIEF = %s      ; Trickshot and Dismantle (Mug swings the weapon in hand)
OT6_CLS_COIN  = %s      ; Coin Toss and a character's GP Rain
OT6_CLS_CLUB  = %s      ; Umaro's Charge and Throw
OT6_CLS_FANG  = %s      ; Gau's own body: his bare hand, and his raging Fight

"""

KIT_TBL = """\
; ------------------------------------------------------------------------------

; [ the kits' hand-loaded classes, as data ]

; the harness reads these (tools/tests/lib/ot6.lua M.kitClass) so its key
; model follows the ROM: +0 a thief's hit, +1 the coins, +2 Umaro's club,
; +3 the classes a hire may swing (Ot6HireClass: the first the target is
; weak to, in bit order), +4 Gau's fangs
Ot6KitClassTbl:
        .byte   OT6_CLS_THIEF, OT6_CLS_COIN, OT6_CLS_CLUB, OT6_CLASSES, OT6_CLS_FANG

"""


def main():
    old = subprocess.run(["git", "show", BASE + ":ff6/src/battle/ot6_class.asm"], cwd=ROOT, check=True,
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
            c = C.item_class(item)
            # the four-class table decides WHETHER an item has a class and its null-break
            if m.group(2) == "$00":
                assert c == 0, "item $%02x has no class at BASE but a kind here" % item
                new = "$00"
            else:
                assert c, "no kind for item $%02x (%s)" % (item, m.group(2))
                new = C.CONST[c] + ("|OT6_NULLBRK" if "OT6_NULLBRK" in m.group(2) else "")
            classes[item] = c
            note = (m.group(3) or "").lstrip()
            kind = C.ITEM_KIND.get(item)
            line = "%s%-16s%s" % (m.group(1), new, note + ((" [%s]" % kind) if kind and note else ""))
            item += 1
        elif mode == "skill":
            s = re.match(r"(\s+\.byte\s+)\$([0-9a-f]{2}), (OT6_\w+)(\s*;.*)?$", line)
            if s:
                a = int(s.group(2), 16)
                line = "%s$%s, %-11s%s" % (s.group(1), s.group(2), C.CONST[C.skill_class(a)],
                                           (s.group(4) or "").lstrip() + " [%s]" % C.SKILL_KIND[a])
        out.append(line.rstrip())
    assert item == 0x100, hex(item)
    text = "\n".join(out) + "\n"
    head = text.index("OT6_SLASH   :=")
    tail = text.index('.segment "ot6_code"')
    kit = tuple(C.CONST[C.KIND_CLASS[C.KIT_KIND[k]]] for k in ("thief", "coin", "club", "fang"))
    text = text[:head] + CONSTS % kit + text[tail:] + "\n" + KIT_TBL
    (ROOT / "ff6/src/battle/ot6_class.asm").write_text(text)

    # the item names wear their class's icon; the type column names it
    p = ROOT / "ff6/src/text/item_name_en.json"
    d = json.loads(p.read_text())
    for i, c in classes.items():
        if i > 0x59:
            continue
        name = re.sub(r"^\{\w+\}", "", d["text"][i])
        d["text"][i] = (ICON[c] if c else "{card}") + name
    p.write_text(json.dumps(d, indent=2, ensure_ascii=False))
    p = ROOT / "ff6/src/text/item_type_name_en.json"
    d = json.loads(p.read_text())
    d["text"][0:10] = TYPE_WORDS
    p.write_text(json.dumps(d, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
