#!/usr/bin/env python3
"""The six weapon classes' tables in the built ROM, against the design (#566).

    python3 tools/check_six_classes.py [--rom build/ot6.sfc] [--dbg ff6/rom/ff6-en.dbg]
    python3 tools/check_six_classes.py --selftest

The design is written once, below (DESIGN, FAMILIES, SKILLS, KIT, ART), from
the issue and the owner's ruling, not copied from the tables: six classes,
Sword $01, Dagger $02, Fist $04, Arcane $08, Katana $10, Spear $20, and a
null-break property $80.  Read from the ROM through ff6-en.dbg's symbols and
held to it, rule by rule:

  weapon  every item id's byte in Ot6WeapClassTbl (256 of them: a weapon's
          family, the four classed Tools, the empty hand, and $00 for
          everything else)
  icon    the icon each classed hand weapon's name wears (ItemName's first
          byte) is its class's glyph; the Heal Rod wears the classless
          mark and the Tools the tool icon
  type    the word the item menu draws for that icon (ItemTypeName[icon -
          $D8], menu/item.asm LoadItemTypeName) is the class's
  glyph   Ot6ClassGlyphTbl, the HUD's cell for each class bit, is the same
          six cells, all different, and all white (Ot6ElemPalTbl 8..13)
  font    those six cells' art in the ROM's small font differs pairwise, and
          the dagger, katana and spear are the redrawn art (ART)
  skill   Ot6SkillClassTbl holds exactly the design's (ability, class) rows
  kit     Ot6KitClassTbl: a thief's hit, the coins, Umaro's club, a hire
  msg     Ot6ClassMsgTbl names each class's attack message, and that
          message's text in the ROM is "Weak against <the class>"

No emulator.  --selftest runs every rule against the built ROM with one
byte changed (a mutant per rule: each must fail its own rule and no other
rule's mutant may pass unnoticed), and the unchanged ROM, which must pass.
A battle on a body weak to each class is tools/tests/battle_sixchip.lua;
the HUD's cells drawn in a battle are tools/tests/battle_sixhud.lua.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SWORD, DAGGER, FIST, ARCANE, KATANA, SPEAR, NULLBRK = 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x80

# class bit -> (name, the font cell its glyph is, the item menu's type word,
# its attack message, that message's text), in bit order
DESIGN = [
    (SWORD, "sword", 0xD9, "SWORD", 0x45, "Weak against swords"),
    (DAGGER, "dagger", 0xD8, "DAGGER", 0x46, "Weak against daggers"),
    (FIST, "fist", 0xE1, "FIST", 0x47, "Weak against fists"),
    (ARCANE, "arcane", 0xDF, "ARCANE", 0x48, "Weak against arcane"),
    (KATANA, "katana", 0xDB, "KATANA", 0x4A, "Weak against katanas"),
    (SPEAR, "spear", 0xDA, "SPEAR", 0x4B, "Weak against spears"),
]
GLYPH = {bit: cell for bit, _, cell, _, _, _ in DESIGN}
NAME = {bit: name for bit, name, _, _, _, _ in DESIGN}
WORD = {cell: word for _, _, cell, word, _, _ in DESIGN}
NOCLASS_ICON, TOOL_ICON, SCROLL_ICON = 0xE0, 0xE5, 0xE6
WORD[NOCLASS_ICON], WORD[TOOL_ICON] = "-----", "TOOL"


def ids(*parts):
    out = []
    for p in parts:
        out += list(range(p[0], p[1] + 1)) if isinstance(p, tuple) else [p]
    return out


# the families: every item id that carries a class (everything else is $00)
FAMILIES = {
    # daggers; the thrown stars; the Hawk Eye; darts
    DAGGER: ids((0x00, 0x09), (0x41, 0x43), 0x49, 0x4E, 0x4F),
    # swords
    SWORD: ids((0x0A, 0x1C)),
    # spears
    SPEAR: ids((0x1D, 0x24)),
    # ninja blades and katanas
    KATANA: ids((0x25, 0x32)),
    # rods (not the Heal Rod), brushes, the boomerang family, cards, Trump, dice
    ARCANE: ids((0x34, 0x40), 0x45, 0x47, 0x48, 0x4B, 0x4C, 0x4D, 0x50, 0x51),
    # the Flail, Morning Star and Bone Club; claws
    FIST: ids(0x44, 0x46, 0x4A, (0x53, 0x59)),
}
FIXED_DICE, HEAL_ROD, EMPTY_HAND = 0x52, 0x33, 0xFF
TOOLS = {0xA6: SWORD, 0xA8: SPEAR, 0xA9: SPEAR, 0xAA: SPEAR}      # Chain Saw; Drill, Air Anchor, AutoCrossbow
LAST_HAND_WEAPON = 0x59

# ability id -> class (Ot6SkillClassTbl's rows, all of them)
SKILLS = {
    0x55: KATANA, 0x57: KATANA, 0x58: KATANA, 0x5A: KATANA, 0x5C: KATANA,   # SwdTech
    0x5D: FIST, 0x5F: FIST, 0x64: FIST,                                     # Pummel, Suplex, Bum Rush
    0x8A: SPEAR,                                                            # TekMissile
    0x51: DAGGER, 0x52: DAGGER, 0x53: DAGGER,                               # the skeans
}
# Ot6KitClassTbl: a thief's hit, the coins, Umaro's club, what a hire may swing
KIT = [("a thief's hit", DAGGER), ("the coins", ARCANE), ("Umaro's club", FIST),
       ("a hire's swing", SWORD | DAGGER | FIST | ARCANE | KATANA | SPEAR)]

# the redrawn icons (' ' 0 clear, '.' 1 shadow, 'o' 2 grey, '#' 3 white), as
# the owner was shown them: the spear upright, the dagger level with its point
# to the left, the katana vanilla's mirrored (a thin blade up to the right)
ART = {
    SPEAR: ["   #    ",
            "  ###.  ",
            "  ###.  ",
            "   #..  ",
            "   o.   ",
            "   o.   ",
            "   o.   ",
            "   o.   "],
    DAGGER: ["        ",
             "     #. ",
             "     #. ",
             "######oo",
             " oooo#oo",
             " ....#..",
             "     #. ",
             "      . "],
}
# vanilla's katana icon, a thin blade up to the left; the build's is this, mirrored
VANILLA_KATANA = ["#       ",
                  "#o      ",
                  ".#o     ",
                  " .#o    ",
                  "  .#o # ",
                  "   ..#  ",
                  "    #.o ",
                  "    . .#"]
ART[KATANA] = [r[::-1] for r in VANILLA_KATANA]


def load_syms(dbg_path):
    text = open(dbg_path, encoding="utf-8").read()
    out = {}
    for m in re.finditer(r'\bname="([A-Za-z0-9_]+)",[^\n]*\bval=0x([0-9A-Fa-f]+)', text):
        out.setdefault(m.group(1), int(m.group(2), 16) & 0x3FFFFF)
    return out


def char_table():
    t = {}
    for name in ("text_en", "small_symbols_en"):
        d = json.load(open(os.path.join(ROOT, "ff6", "tools", "char_table", name + ".json"), encoding="utf-8"))
        for k, v in d.items():
            t[int(k, 16)] = v[0] if isinstance(v, list) else v
    return t


def decode(b, table):
    out = []
    for c in b:
        if c == 0x00:
            break
        out.append(" " if c in (0xFE, 0xFF) else table.get(c, "{%02X}" % c))
    return "".join(out).rstrip()


def tile(rom, font, cell):
    t = rom[font + cell * 16: font + cell * 16 + 16]
    return ["".join(" .o#"[((t[2 * r] >> (7 - c)) & 1) | (((t[2 * r + 1] >> (7 - c)) & 1) << 1)]
                    for c in range(8)) for r in range(8)]


def want_weapon_byte(item):
    for cls, members in FAMILIES.items():
        if item in members:
            return cls
    if item == FIXED_DICE:
        return ARCANE | NULLBRK
    if item == EMPTY_HAND:
        return FIST
    return TOOLS.get(item, 0x00)


def check(rom, sym, table):
    """-> list of (rule, message) failures."""
    bad = []

    def fail(rule, msg):
        bad.append((rule, msg))

    # weapon: all 256 bytes
    wt = sym["Ot6WeapClassTbl"]
    for item in range(256):
        got, want = rom[wt + item], want_weapon_byte(item)
        if got != want:
            fail("weapon", "item $%02X: Ot6WeapClassTbl has $%02X, the design $%02X" % (item, got, want))

    # icon and type: the name each classed hand weapon wears, and its word
    names, types = sym["ItemName"], sym["ItemTypeName"]

    def icon(item):
        return rom[names + item * 13]

    def word(cell):
        return decode(rom[types + (cell - 0xD8) * 7: types + (cell - 0xD8) * 7 + 7], table)
    for item in range(LAST_HAND_WEAPON + 1):
        cls = want_weapon_byte(item) & 0x7F
        want = GLYPH[cls] if cls else NOCLASS_ICON
        nm = decode(rom[names + item * 13 + 1: names + item * 13 + 13], table)
        if icon(item) != want:
            fail("icon", "item $%02X %s wears icon $%02X, its class's (%s) is $%02X"
                 % (item, nm, icon(item), NAME.get(cls, "none"), want))
        elif word(want) != WORD[want]:
            fail("type", "item $%02X %s: the item menu's word for icon $%02X is %r, the design's %r"
                 % (item, nm, want, word(want), WORD[want]))
    for item in TOOLS:
        if icon(item) != TOOL_ICON:
            fail("icon", "tool $%02X wears icon $%02X, not the tool icon $%02X" % (item, icon(item), TOOL_ICON))

    # glyph: the HUD's cells, their palette rows
    gt, pt = sym["Ot6ClassGlyphTbl"], sym["Ot6ElemPalTbl"]
    cells = [rom[gt + i] for i in range(6)]
    for i, (bit, name, cell, _, _, _) in enumerate(DESIGN):
        if cells[i] != cell:
            fail("glyph", "Ot6ClassGlyphTbl[%d] (%s) is $%02X, the design's cell $%02X" % (i, name, cells[i], cell))
        if rom[pt + 8 + i] != 0:
            fail("glyph", "Ot6ElemPalTbl[%d] (%s) is $%02X, not white ($00)" % (8 + i, name, rom[pt + 8 + i]))
    if len(set(cells)) != 6:
        fail("glyph", "Ot6ClassGlyphTbl's six cells are not six different cells: %s"
             % " ".join("$%02X" % c for c in cells))

    # font: the six cells' art
    font = sym["SmallFontGfx"]
    art = {bit: tile(rom, font, cell) for bit, _, cell, _, _, _ in DESIGN}
    for i, (a, an, _, _, _, _) in enumerate(DESIGN):
        for b, bn, _, _, _, _ in DESIGN[i + 1:]:
            if art[a] == art[b]:
                fail("font", "the %s and %s glyphs are the same picture" % (an, bn))
        if not any(c != " " for r in art[a] for c in r):
            fail("font", "the %s glyph is blank" % an)
    for bit, rows in ART.items():
        if art[bit] != rows:
            fail("font", "the %s glyph (cell $%02X) is not the redrawn art:\n%s"
                 % (NAME[bit], GLYPH[bit], "\n".join("      |%s|  want |%s|" % (g, w) for g, w in zip(art[bit], rows))))

    # skill: exactly the design's rows
    st, got = sym["Ot6SkillClassTbl"], {}
    for i in range(64):
        a = rom[st + i * 2]
        if a == 0xFF:
            break
        if a in got:
            fail("skill", "Ot6SkillClassTbl lists ability $%02X twice" % a)
        got[a] = rom[st + i * 2 + 1]
    else:
        fail("skill", "Ot6SkillClassTbl has no $FF end in 64 rows")
    for a in sorted(set(got) | set(SKILLS)):
        if got.get(a) != SKILLS.get(a):
            fail("skill", "ability $%02X: Ot6SkillClassTbl has %s, the design %s" % (
                a, "$%02X" % got[a] if a in got else "no row", "$%02X" % SKILLS[a] if a in SKILLS else "no row"))

    # kit
    kt = sym["Ot6KitClassTbl"]
    for i, (what, want) in enumerate(KIT):
        if rom[kt + i] != want:
            fail("kit", "Ot6KitClassTbl[%d] (%s) is $%02X, the design $%02X" % (i, what, rom[kt + i], want))

    # msg: the table, and the text of the message it names
    mt, ptrs, base = sym["Ot6ClassMsgTbl"], sym["AttackMsgPtrs"], sym["AttackMsg"] & 0xFF0000
    for i, (bit, name, _, _, msg, text) in enumerate(DESIGN):
        got = rom[mt + i]
        if got != msg:
            fail("msg", "Ot6ClassMsgTbl[%d] (%s) is message $%02X, the design's $%02X" % (i, name, got, msg))
        p = base | rom[ptrs + msg * 2] | (rom[ptrs + msg * 2 + 1] << 8)
        said = decode(rom[p: p + 40], table)
        if said != text:
            fail("msg", "attack message $%02X reads %r, the design's %r" % (msg, said, text))
    return bad


def load(rom_path, dbg_path):
    return bytearray(open(rom_path, "rb").read()), load_syms(dbg_path), char_table()


def selftest(rom_path, dbg_path):
    rom, sym, table = load(rom_path, dbg_path)
    ok = True
    bad = check(rom, sym, table)
    if bad:
        ok = False
        print("  SELFTEST FAIL: the built ROM does not pass (%d): %s" % (len(bad), bad[0][1]))
    font = sym["SmallFontGfx"]
    sword = bytes(rom[font + 0xD9 * 16: font + 0xD9 * 16 + 16])
    # one byte (or one tile) changed per mutant: (what, offset, new bytes, the rule that must go red)
    mutants = [
        ("the Mithril Pike a sword", sym["Ot6WeapClassTbl"] + 0x1D, [SWORD], "weapon"),
        ("the Imperial (a ninja blade) a dagger", sym["Ot6WeapClassTbl"] + 0x25, [DAGGER], "weapon"),
        ("the Heal Rod arcane", sym["Ot6WeapClassTbl"] + HEAL_ROD, [ARCANE], "weapon"),
        ("the Fixed Dice without null-break", sym["Ot6WeapClassTbl"] + FIXED_DICE, [ARCANE], "weapon"),
        ("a helmet with a class", sym["Ot6WeapClassTbl"] + 0x6A, [FIST], "weapon"),
        ("the empty hand classless", sym["Ot6WeapClassTbl"] + EMPTY_HAND, [0x00], "weapon"),
        ("the Ashura's name wearing the sword", sym["ItemName"] + 0x2B * 13, [0xD9], "icon"),
        ("the Dirk's name wearing the spear", sym["ItemName"] + 0x00 * 13, [0xDA], "icon"),
        ("the katana icon's word misspelt", sym["ItemTypeName"] + 3 * 7, [0x80], "type"),
        ("katana drawing the sword's cell", sym["Ot6ClassGlyphTbl"] + 4, [0xD9], "glyph"),
        ("spear in a colour", sym["Ot6ElemPalTbl"] + 13, [0x04], "glyph"),
        ("the katana cell holding the sword's picture", font + 0xDB * 16, list(sword), "font"),
        ("one pixel of the spear", font + 0xDA * 16, [rom[font + 0xDA * 16] ^ 0x01], "font"),
        ("SwdTech Dispatch a sword", sym["Ot6SkillClassTbl"] + 1, [SWORD], "skill"),
        ("a skill row's ability moved", sym["Ot6SkillClassTbl"] + 16, [0x8B], "skill"),
        ("the table ended early", sym["Ot6SkillClassTbl"] + 22, [0xFF], "skill"),
        ("a thief's hit a spear", sym["Ot6KitClassTbl"], [SPEAR], "kit"),
        ("a hire four classes wide", sym["Ot6KitClassTbl"] + 3, [0x0F], "kit"),
        ("katana showing the sword's line", sym["Ot6ClassMsgTbl"] + 4, [0x45], "msg"),
        ("the spears' line one letter off", (sym["AttackMsg"] & 0xFF0000)
         | rom[sym["AttackMsgPtrs"] + 0x4B * 2] | (rom[sym["AttackMsgPtrs"] + 0x4B * 2 + 1] << 8), [0x80], "msg"),
    ]
    for what, off, new, rule in mutants:
        m = bytearray(rom)
        if bytes(m[off: off + len(new)]) == bytes(new):
            ok = False
            print("  SELFTEST FAIL: mutant '%s' changes nothing" % what)
            continue
        m[off: off + len(new)] = bytes(new)
        rules = sorted({r for r, _ in check(m, sym, table)})
        if rule not in rules:
            ok = False
            print("  SELFTEST FAIL: mutant '%s' (ROM $%06X) did not fail rule '%s' (failed: %s)"
                  % (what, off, rule, ", ".join(rules) or "nothing"))
        else:
            print("  mutant %-46s red: %s" % (what, ", ".join(rules)))
    print("check_six_classes selftest: " + ("ok (%d mutants)" % len(mutants) if ok else "FAILED"))
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rom", default=os.path.join(ROOT, "build", "ot6.sfc"))
    ap.add_argument("--dbg", default=os.path.join(ROOT, "ff6", "rom", "ff6-en.dbg"))
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return selftest(args.rom, args.dbg)
    rom, sym, table = load(args.rom, args.dbg)
    bad = check(rom, sym, table)
    if bad:
        print("six classes: %d failure(s) in %s" % (len(bad), args.rom))
        for rule, msg in bad:
            print("  FAIL %-6s %s" % (rule, msg))
        return 1
    n = sum(len(v) for v in FAMILIES.values())
    print("six classes: %s holds the design -- 256 item bytes (%d classed weapons, the Fixed Dice, %d Tools, the "
          "empty hand), each weapon's icon and type word, 6 HUD glyph cells and their art, %d skill rows, %d kit "
          "bytes, 6 messages" % (os.path.relpath(args.rom, ROOT), n, len(TOOLS), len(SKILLS), len(KIT)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
