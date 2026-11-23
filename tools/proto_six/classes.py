#!/usr/bin/env python3
"""classes.py -- the six weapon classes as data (#566): which class every
weapon family, tool and class-bearing skill carries, who really holds each,
and what each four-class weakness may become.  rewrite_class.py writes
ot6_class.asm and the item icons from it, split.py splits the species' rows
by it, party_share.py and the audits read the holders.  Regrouping the
classes is an edit here and a re-run of those.

The grouping is the owner's of 2026-11-23, after Octopath's six (sword,
spear, dagger, axe, bow, staff): "katana is axe"; Ranged "gathers together
all the ranged physicals, bolts, stars, darts, cards, dice, boomerangs";
"rods and fists could group" (Blunt: "yes i like blunt").
"""
SWORD, DAGGER, BLUNT, RANGED, KATANA, SPEAR = 0x01, 0x02, 0x04, 0x08, 0x10, 0x20
NAME = {SWORD: "Sword", DAGGER: "Dagger", BLUNT: "Blunt", RANGED: "Ranged", KATANA: "Katana", SPEAR: "Spear"}
CONST = {SWORD: "OT6_SWORD", DAGGER: "OT6_DAGGER", BLUNT: "OT6_BLUNT", RANGED: "OT6_RANGED", KATANA: "OT6_KATANA",
         SPEAR: "OT6_SPEAR"}
ORDER = (SWORD, DAGGER, SPEAR, KATANA, BLUNT, RANGED)       # the order a row's mask is written in

# ---- weapon kinds: what the thing is, then the class the kind carries -------
KIND_CLASS = {
    "sword": SWORD, "chainsaw": SWORD,
    "dagger": DAGGER, "ninja blade": DAGGER, "thief hit": DAGGER, "fang": DAGGER,
    "spear": SPEAR, "drill": SPEAR,
    "katana": KATANA, "claw": KATANA, "swdtech": KATANA,
    "rod": BLUNT, "brush": BLUNT, "fist": BLUNT, "knuckle": BLUNT, "flail": BLUNT, "club": BLUNT, "blitz": BLUNT,
    "umaro": BLUNT,
    "crossbow": RANGED, "air anchor": RANGED, "tekmissile": RANGED, "star": RANGED, "skean": RANGED, "dart": RANGED,
    "card": RANGED, "dice": RANGED, "coin": RANGED, "boomerang": RANGED,
}
# where a kind sits badly, said once (the report and the docs quote these)
AWKWARD = {
    "chainsaw": "a saw is no sword; Sword is the nearest edge (not a katana's cut, not a blow), and it is what "
                "'buys Edgar slashing' meant",
    "air anchor": "it fires a harpoon: a spear by shape, Ranged by how it is delivered (as the AutoCrossbow's bolts)",
    "skean": "the three damaging skeans are thrown, so Ranged with the stars, though they resolve as spells and "
             "their elements do most of their chipping",
    "umaro": "Umaro's Throw hurls an ally: literally a thrown thing, kept Blunt as his Charge is (a body's blow)",
    "thief hit": "Trickshot throws a coin but carries Locke's own class whatever he holds, as Mug does: Dagger",
    "brush": "a brush is no bludgeon; it goes with the rods, the other caster's weapon ('rods and fists could "
             "group')",
    "claw": "the four edged claws (Mithril Claw, Poison Claw, Dragon Claw, Tiger Fangs) cut, so Katana; the three "
            "knuckles (MetalKnuckle, Kaiser, Fire Knuckle) strike, so Blunt",
    "boomerang": "Hawk Eye and the returning rings are thrown: Ranged, though vanilla drew them with the flails",
    "dice": "dice and cards are Setzer's thrown things: Ranged (the Fixed Dice stay null-break)",
}

# item id -> kind (Ot6WeapClassTbl's rows; anything absent has no class)
ITEM_KIND = {}
for _i in range(0x00, 0x0a):
    ITEM_KIND[_i] = "dagger"
for _i in range(0x0a, 0x1d):
    ITEM_KIND[_i] = "sword"
for _i in range(0x1d, 0x25):
    ITEM_KIND[_i] = "spear"
for _i in range(0x25, 0x2b):
    ITEM_KIND[_i] = "ninja blade"
for _i in range(0x2b, 0x33):
    ITEM_KIND[_i] = "katana"
for _i in range(0x34, 0x3d):
    ITEM_KIND[_i] = "rod"               # $33 Heal Rod: no class
for _i in range(0x3d, 0x41):
    ITEM_KIND[_i] = "brush"
for _i in range(0x41, 0x44):
    ITEM_KIND[_i] = "star"
ITEM_KIND.update({0x44: "flail", 0x46: "flail", 0x4a: "club",
                  0x45: "boomerang", 0x47: "boomerang", 0x48: "boomerang", 0x49: "boomerang", 0x4b: "boomerang",
                  0x4c: "boomerang",
                  0x4d: "card", 0x50: "card", 0x51: "dice", 0x52: "dice", 0x4e: "dart", 0x4f: "dart",
                  0x53: "knuckle", 0x55: "knuckle", 0x57: "knuckle",
                  0x54: "claw", 0x56: "claw", 0x58: "claw", 0x59: "claw",
                  0xa6: "chainsaw", 0xa8: "drill", 0xa9: "air anchor", 0xaa: "crossbow",
                  0xff: "fist"})
# ability id -> kind (Ot6SkillClassTbl's rows)
SKILL_KIND = {0x55: "swdtech", 0x57: "swdtech", 0x58: "swdtech", 0x5a: "swdtech", 0x5c: "swdtech",
              0x5d: "blitz", 0x5f: "blitz", 0x64: "blitz", 0x8a: "tekmissile",
              0x51: "skean", 0x52: "skean", 0x53: "skean"}
# the kits' hand-loaded classes (Ot6KitClassTbl)
KIT_KIND = {"thief": "thief hit", "coin": "coin", "club": "umaro", "fang": "fang"}


def item_class(i):
    k = ITEM_KIND.get(i)
    return KIND_CLASS[k] if k else 0


def skill_class(a):
    k = SKILL_KIND.get(a)
    return KIND_CLASS[k] if k else 0


# ---- the four classes, and what each weakness may become --------------------
SLASH, PIERCE, BLUDG, SPECIAL = 1, 2, 4, 8
OLD_NAME = {SLASH: "slash", PIERCE: "pierce", BLUDG: "bludgeon", SPECIAL: "special"}
# a four-class weakness becomes one of the classes its own weapons went to
# (slash: swords, katanas, claws; pierce: daggers, ninja blades, spears,
# bolts, stars, darts; bludgeon: fists, rods, flails, boomerangs; special:
# cards, dice, brushes), first-named first
CHILDREN = {SLASH: (SWORD, KATANA), PIERCE: (DAGGER, SPEAR, RANGED), BLUDG: (BLUNT, RANGED),
            SPECIAL: (RANGED, BLUNT)}

# ---- who really holds a class: signature weapon or signature command --------
# (owner, 2026-11-23: "we don't want just one particular character to be
# required to get through fights"; "it's pretty rare anyone will want to be
# wielding a dagger" -- so a holder is who really wields it, not who could)
CHARS = ["TERRA", "LOCKE", "CYAN", "SHADOW", "EDGAR", "SABIN", "CELES", "STRAGO", "RELM", "SETZER", "MOG", "GAU",
         "GOGO", "UMARO", "BANON", "LEO"]
SIGNATURE = {
    "TERRA": {"sword"}, "CELES": {"sword"}, "LEO": {"sword"},
    "LOCKE": {"dagger", "thief hit"},
    "SHADOW": {"ninja blade", "star", "skean"},
    "EDGAR": {"spear", "drill", "crossbow"},
    "MOG": {"spear"},
    "CYAN": {"katana", "swdtech"},
    "SABIN": {"claw", "knuckle", "fist", "blitz"},
    "GAU": {"fang"}, "UMARO": {"club", "umaro"},
    "STRAGO": {"rod"}, "RELM": {"brush"}, "BANON": {"rod"},
    "SETZER": {"card", "dice", "dart", "coin"},
    "GOGO": set(),
}


def signature_mask(name):
    m = 0
    for k in SIGNATURE.get(name, ()):
        m |= KIND_CLASS[k]
    return m


def holders(cls):
    """the characters who really hold a class"""
    return {n for n in SIGNATURE if signature_mask(n) & cls}


if __name__ == "__main__":
    for c in ORDER:
        print("%-7s %s" % (NAME[c], ", ".join(sorted(holders(c)))))
        print("        kinds: %s" % ", ".join(sorted(k for k, v in KIND_CLASS.items() if v == c)))
    for k, why in AWKWARD.items():
        print("sits badly: %s -- %s" % (k, why))
