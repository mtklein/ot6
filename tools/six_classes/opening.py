#!/usr/bin/env python3
"""opening.py -- the opening's evidence without an emulator (#566,
docs/design/opening.md): for each area from the Narshe mines to Zozo, the
species the game deals there (decoded from the data: SubBattleGroup and the
World sectors -> RandBattleGroup -> BattleMonsters, EventBattleGroup, the
monster-in-a-box chests, as tools/check_shield_rows.py reads them), the party
the story forces with what a NEW PLAYER's hands hold (the weapons the
characters join with, ff6/src/field/char_prop.asm, and the first shops'
obvious buys), and the share of the area's gauged species that party keys

    in hand     a weapon in a member's hand carries one of the row's classes
    by kit      ... or a class-bearing skill or tool does (Pummel, the
                AutoCrossbow, Trickshot, TekMissile, SwdTech, a thrown star)
    by element  a spell, tool, Blitz or beam the party has reaches an element
                the body is weak to and does not absorb or null
    any         one of the three

under the four classes (origin/main's rows and weapon table) and under the six
(the working tree's).  Then the same for the automated route's own hands, from
the baseline play's [keys] lines, where it fought in the area.

    python3 tools/six_classes/opening.py            # the report
    python3 tools/six_classes/opening.py --md       # the areas' tables, as opening.md carries them
    python3 tools/six_classes/opening.py --write    # both, under build/attempts/wt/v051-six-classes/opening/
"""
import collections
import importlib.util
import itertools
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
KEYS = ROOT / "build/attempts/wt/v051-six-classes/line/route-keys-base.json"
OUT = ROOT / "build/attempts/wt/v051-six-classes/opening"
S, P, B, X = C.SLASH, C.PIERCE, C.BLUDG, C.SPECIAL
OLD = {"OT6_SLASH": S, "OT6_PIERCE": P, "OT6_BLUDG": B, "OT6_SPECIAL": X}
OLD_NAME = {S: "slash", P: "pierce", B: "bludg", X: "special"}
ELEMENTS = ["fire", "ice", "bolt", "poison", "wind", "holy", "earth", "water"]
EL = {n: 1 << i for i, n in enumerate(ELEMENTS)}
# what each class-bearing skill or tool was under the four classes
OLD_KIT = {"tekmissile": P, "crossbow": P, "drill": P, "blitz": B, "swdtech": S, "thief hit": P, "star": P}


def _load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def base_file(path):
    return subprocess.run(["git", "show", BASE + ":" + path], cwd=ROOT, check=True, capture_output=True,
                          text=True).stdout


def old_item_classes():
    """origin/main's Ot6WeapClassTbl: item id -> four-class bits (null-break weapons none)."""
    lines = base_file("ff6/src/battle/ot6_class.asm").split("\n")
    start = next(i for i, l in enumerate(lines) if l.startswith("Ot6WeapClassTbl:"))
    out = []
    for l in lines[start + 1:]:
        code = l.split(";", 1)[0].strip()
        if not code:
            continue
        m = re.match(r"\.byte\s+(.+)$", code)
        if m:
            v = 0
            for tok in m.group(1).split("|"):
                tok = tok.strip()
                v |= OLD.get(tok, 0x80 if tok == "OT6_NULLBRK" else (int(tok[1:], 16) if tok.startswith("$") else 0))
            out.append(0 if v & 0x80 else v & 15)
            continue
        m = re.match(r"\.res\s+(.+?),\s*\S+$", code)
        if m:
            out += [0] * eval(m.group(1).replace("$", "0x"), {"__builtins__": {}})
            continue
        break
    # 256 rows; the Mithril Blade slashed, the MetalKnuckle (a claw then) slashed, the empty hand bludgeoned
    assert len(out) == 256 and out[0x0A] == S and out[0x53] == S and out[0x45] == B and out[0xFF] == B, len(out)
    return out


# ---- the parties: what a new player's hands hold --------------------------------
DIRK, MKNIFE, MBLADE, PIKE, IMPERIAL, ASHURA, PUNISHER = 0x00, 0x01, 0x0A, 0x1D, 0x25, 0x2B, 0x3B
BRUSH, FLAIL, FULLMOON, MSTAR, BOOMERANG, KNUCKLE, CLAW, BARE = 0x3D, 0x44, 0x45, 0x46, 0x47, 0x53, 0x54, 0xFF


def mem(name, hands=(), kit=(), elem=(), says=""):
    return dict(name=name, hands=tuple(hands), kit=tuple(kit), elem=tuple(elem), says=says)


TERRA_ARMOR = mem("TERRA", kit=["tekmissile"], elem=["fire", "ice", "bolt", "poison"],
                  says="in armor: Fire, Bolt and Ice Beam, Bio Blast, TekMissile")
VICKS = mem("VICKS", elem=["fire", "ice", "bolt"], says="in armor: the three beams")
WEDGE = mem("WEDGE", elem=["fire", "ice", "bolt"], says="in armor: the three beams")
TERRA_KNIFE = mem("TERRA", [MKNIFE], elem=["fire"], says="Mithril Knife (she wakes with it); Fire, Cure")
TERRA = mem("TERRA", [MBLADE], elem=["fire"], says="a sword from South Figaro's shop; Fire, Cure")
LOCKE0 = mem("LOCKE", [DIRK], says="Dirk; Steal, Filch, Bestow")
LOCKE = mem("LOCKE", [DIRK], kit=["thief hit"], says="a dagger; Steal, Filch, Bestow, Trickshot (from the Lete on)")
EDGAR0 = mem("EDGAR", [MBLADE], kit=["crossbow"], says="Mithril Blade and the AutoCrossbow (he joins with both)")
EDGAR = mem("EDGAR", [MBLADE], kit=["crossbow"], elem=["poison"],
            says="Mithril Blade; AutoCrossbow; the Bio Blaster from Figaro's tool merchant")
EDGAR_PIKE = mem("EDGAR", [PIKE], kit=["crossbow"], elem=["poison"],
                 says="the Mithril Pike Narshe's shop sells before the defense; AutoCrossbow; Bio Blaster")
EDGAR_DRILL = mem("EDGAR", [PIKE], kit=["crossbow", "drill"], elem=["poison"],
                  says="Mithril Pike; AutoCrossbow, the Drill (Figaro, after the dive); Bio Blaster")
SABIN = mem("SABIN", [KNUCKLE], kit=["blitz"], elem=["holy"], says="MetalKnuckle; Pummel, AuraBolt (level 6)")
SABIN_CLAW = mem("SABIN", [CLAW], kit=["blitz"], elem=["holy"],
                 says="a Mithril Claw (Mobliz's or Narshe's shop); Pummel, Suplex, AuraBolt")
SABIN15 = mem("SABIN", [CLAW], kit=["blitz"], elem=["holy", "fire"],
              says="a Mithril Claw; Pummel, Suplex, AuraBolt, Fire Dance (level 15)")
BANON = mem("BANON", [PUNISHER], says="Punisher (a rod); Health")
CELES = mem("CELES", [MBLADE], elem=["ice"], says="a spare Mithril Blade (she joins unarmed); Ice, Cure, Runic")
CELES_BARE = mem("CELES", [BARE], elem=["ice"], says="bare hands, as she joins; Ice, Runic")
CYAN = mem("CYAN", [ASHURA], kit=["swdtech"], says="Ashura; SwdTech")
SHADOW = mem("SHADOW", [IMPERIAL], says="Imperial (a ninja blade); Throw, with nothing to throw")
SHADOW_STARS = mem("SHADOW", [IMPERIAL], kit=["star"], says="Imperial; Throw, with the Shurikens the house's "
                   "merchant sells")
GAU = mem("GAU", ["fang"], says="his fangs; Rage")
MOOGLES = {
    "LOCKE's squad": [LOCKE0, mem("KUPEK", [PIKE], says="Mithril Pike"), mem("KUPOP", [MSTAR], says="Morning Star"),
                      mem("KUMAMA", [CLAW], says="Mithril Claw")],
    "MOG's squad": [mem("MOG", [PIKE], says="Mithril Pike"), mem("KUKU", [FLAIL], says="Flail"),
                    mem("KUTAN", [MBLADE], says="Mithril Blade"), mem("KUPAN", [FULLMOON], says="Full Moon")],
    "KUSHU's squad": [mem("KUSHU", [BRUSH], says="Chocobo Brush"), mem("KURIN", [PIKE], says="Mithril Pike"),
                      mem("KURU", [MBLADE], says="Mithril Blade"), mem("KAMOG", [BOOMERANG], says="Boomerang")],
}
SEVEN = [TERRA, LOCKE, EDGAR_PIKE, SABIN_CLAW, CYAN, GAU, CELES]
SIX = [LOCKE, EDGAR_DRILL, SABIN15, CYAN, GAU, CELES]

# ---- the areas, in the order a new game meets them ---------------------------------
# pools: maps (field maps' random pools), world (WorldBattleGroup group ids), battles
# (event battle ids), chests (monster-in-a-box event battle ids), extra (species a
# formation's script brings in), skip (formations of those pools the area does not deal)
AREAS = [
    dict(key="1", name="The mines in Magitek armor",
         legs=["battle_entry", "battle2_entry", "whelk_entry", "arvis_wake"],
         pools=dict(battles=[1, 0, 2, 3, 4, 64, 77]),
         parties=[("TERRA, VICKS, WEDGE in armor", [TERRA_ARMOR, VICKS, WEDGE])],
         teaches="The beams end every fight in a hit; the shield and '?' cells are seen, not yet needed. The "
                 "Whelk's head is the first break: three Fire Beams and a TekMissile."),
    dict(key="2", name="TERRA alone, the mine shaft out of Narshe", legs=["moogle_entry"],
         pools=dict(maps=[50]),
         parties=[("TERRA alone", [TERRA_KNIFE])],
         teaches="One member, one weapon class: her knife keys every body. Fire keys two of the three; on the "
                 "Repo Man it shows nothing, so the '?' is the knife's."),
    dict(key="3", name="The moogle defense", legs=["moogle_cleared"],
         pools=dict(battles=[5, 6]),
         parties=list(MOOGLES.items()),
         teaches="Five of the six weapon icons are on the field at once (no Katana: KUMAMA's claw is a dagger) and nobody has a spell: the Lobo takes points "
                 "(the pikes, LOCKE's dirk), the Vomammoth swords and blows, and each squad holds a key to both. "
                 "The Marshal is the first boss broken by weapons alone."),
    dict(key="4", name="TERRA and LOCKE: the plains and the Figaro desert (and the school's practice chest)",
         legs=["worldmap_narshe", "figaro_entry"],
         pools=dict(world=[0, 2, 1], chests=[0]),
         parties=[("TERRA and LOCKE", [TERRA_KNIFE, LOCKE0])],
         teaches="Two members, still one weapon class. The daggers key every body; Fire keys the plains' two and "
                 "neither of the desert's, where the knives carry it. LOCKE's Steal is his other turn."),
    dict(key="5", name="Figaro Castle: the M-TekArmors", legs=["figaro_intro"],
         pools=dict(battles=[65]),
         parties=[("TERRA, LOCKE, EDGAR", [TERRA_KNIFE, LOCKE0, EDGAR0])],
         teaches="EDGAR's first fight: his sword does nothing to the armor and his AutoCrossbow chips both at "
                 "once. The knives chip too; the Bio Blaster, if bought on the way out, is a second key."),
    dict(key="6", name="The cave to South Figaro (and the desert at its mouth)", legs=["south_figaro"],
         pools=dict(maps=[72, 73], world=[1]),
         parties=[("TERRA, LOCKE, EDGAR", [TERRA_KNIFE, LOCKE0, EDGAR])],
         teaches="The first place the cell picks the target: the eye takes the knives, the worm EDGAR's blade, the "
                 "hornets anyone's point or the sweep. Fire burns all three."),
    dict(key="7", name="The plains round South Figaro", legs=["south_figaro"],
         pools=dict(world=[3, 4, 5]),
         parties=[("the three, before the shop", [TERRA_KNIFE, LOCKE0, EDGAR]),
                  ("the three, TERRA with a sword", [TERRA, LOCKE0, EDGAR])],
         teaches="No body here is weak to fire: the Bio Blaster is the element (all three), the Rhodox is "
                 "everybody's, the GreaseMonk the dagger's, the Rhinotaur the crossbow's."),
    dict(key="8", name="Mt. Kolts and Vargas", legs=["south_figaro", "kolts_pool", "kolts_cave", "vargas_entry"],
         pools=dict(maps=[96, 97, 98, 99, 100, 101, 102], battles=[66]),
         parties=[("TERRA, LOCKE, EDGAR", [TERRA, LOCKE0, EDGAR]),
                  ("with SABIN, from the summit down", [TERRA, LOCKE0, EDGAR, SABIN])],
         teaches="TERRA's new Mithril Blade and her Fire carry the mountain (a RegalCutlass keys nothing here); the Tusker has no weapon weakness at all "
                 "(Fire or the Bio Blaster); the fliers fall to the dagger or the sweep. Vargas cannot be broken "
                 "until SABIN arrives: Pummel, his MetalKnuckle and AuraBolt."),
    dict(key="8b", name="The Returners' side of Mt. Kolts, SABIN's first walk", legs=["returner_hideout"],
         pools=dict(maps=[100, 101], world=[5]),
         parties=[("TERRA, LOCKE, EDGAR, SABIN", [TERRA, LOCKE0, EDGAR, SABIN])],
         teaches="SABIN's Blunt matters the day he joins: the Vaporite, the GreaseMonk and the Rhinotaur take "
                 "his fists."),
    dict(key="9", name="The Lete River and Ultros", legs=["scenario_hub"],
         pools=dict(battles=[7, 8, 103]),
         parties=[("TERRA, EDGAR, SABIN, BANON", [TERRA, EDGAR, SABIN, BANON])],
         teaches="Each hand keys two of the raft's three: TERRA's blade, EDGAR's bolts, the fists and BANON's rod. "
                 "Ultros takes the swords, the AutoCrossbow and Fire; SABIN and BANON hit and heal."),
    dict(key="10a", name="TERRA's scenario: the raft, Narshe's mines and the back way",
         legs=["rapids_start", "terra_narshe", "terra_caves", "terra_clifftop"],
         pools=dict(battles=[7, 8, 38], world=[0, 2], maps=[41, 48, 50]),
         parties=[("TERRA, EDGAR, BANON", [TERRA, EDGAR, BANON])],
         teaches="Three hands, three classes. The checkpoint's trap is the lesson in elements: all three bodies "
                 "burn and all three drink the Bio Blaster's poison."),
    dict(key="10b", name="LOCKE's scenario, alone in South Figaro", legs=["sfigaro_town"],
         pools=dict(battles=[10, 9, 11]),
         parties=[("LOCKE alone", [LOCKE])],
         teaches="One member, one class, and every body takes it. Steal is the scenario's verb."),
    dict(key="10b2", name="LOCKE and CELES: the basement, the cave, TunnelArmor", legs=["sfigaro_escape"],
         pools=dict(maps=[87, 69, 70], battles=[67], world=[1, 0, 2]),
         parties=[("LOCKE and CELES (a blade for her)", [LOCKE, CELES]),
                  ("LOCKE and CELES (unarmed, as she joins)", [LOCKE, CELES_BARE])],
         teaches="The two hands split the cave: the soldiers and the hounds take both, the shell LOCKE's point "
                 "(or her bare hands), the soft body and the bear her blade. TunnelArmor: his dagger and "
                 "Trickshot, her Ice, and Runic for the quake."),
    dict(key="10c", name="SABIN's scenario: east of the Lete", legs=["sabin_world"],
         pools=dict(world=[6, 7, 8]),
         parties=[("SABIN alone", [SABIN]), ("SABIN and a hired SHADOW", [SABIN, SHADOW_STARS]),
                  ("with CYAN, on the way to the forest", [SABIN, CYAN])],
         teaches="One member, one class: fists key three of the four bodies. The Beakor is out of his reach, a "
                 "flier for a thrown star or, later, CYAN's katana."),
    dict(key="10c2", name="The Imperial camp and Doma",
         legs=["cyan_defence", "wob_camp_telstar", "kefka_done", "doma_defended"],
         pools=dict(battles=[12, 42, 44, 43, 46, 13, 14], chests=[32]),
         parties=[("SABIN alone", [SABIN]), ("SABIN and a hired SHADOW", [SABIN, SHADOW_STARS]),
                  ("CYAN alone (his duel: the Soldiers, the Leader)", [CYAN]),
                  ("SABIN and CYAN", [SABIN, CYAN])],
         teaches="Everything in the camp takes a blow, so SABIN alone always holds the key; SHADOW's blade keys "
                 "the Templars and the dogs, CYAN's katana the infantry. No body here needs the hire."),
    dict(key="10c3", name="The Phantom Forest and the Phantom Train",
         legs=["forest_done", "wob_forest_hunt", "train_done", "wob_train_hunt", "wob_train_specter"],
         pools=dict(maps=[130, 132, 133, 134, 135, 141, 142, 145, 149, 151, 152], battles=[47, 109, 68],
                    chests=[34]),
         parties=[("SABIN and CYAN", [SABIN, CYAN]), ("with SHADOW", [SABIN, CYAN, SHADOW_STARS])],
         teaches="CYAN's katana keys every body but the train itself; AuraBolt's holy keys all but the Bomb. The "
                 "GhostTrain takes only blows (and fire, bolt, holy): CYAN waits for the break his Cleave needs."),
    dict(key="10c4", name="Baren Falls and the Serpent Trench", legs=["falls_done", "sabin_done"],
         pools=dict(battles=[18, 19, 20, 21], extra=[0x155]),
         parties=[("SABIN and CYAN (the falls)", [SABIN, CYAN]),
                  ("SABIN, CYAN, GAU (the trench), SABIN with Mobliz's claw", [SABIN_CLAW, CYAN, GAU])],
         teaches="The falls take both hands. The trench is three aquatics, three keys: CYAN's katana, SABIN's "
                 "Blitzes, GAU's fangs (and SABIN's claw, a dagger)."),
    dict(key="11", name="The Narshe defense and Kefka", legs=["narshe_battle", "kefka_won"],
         pools=dict(battles=[22, 23, 24, 57]),
         parties=[("all seven", SEVEN),
                  ("a squad as the scenarios ended: TERRA, EDGAR", [TERRA, EDGAR_PIKE]),
                  ("a squad as the scenarios ended: LOCKE, CELES", [LOCKE, CELES]),
                  ("a squad as the scenarios ended: SABIN, CYAN, GAU", [SABIN_CLAW, CYAN, GAU]),
                  ("the automated route's party 1: TERRA, EDGAR, CELES", [TERRA, EDGAR_PIKE, CELES]),
                  ("the automated route's party 2: LOCKE, GAU", [LOCKE, GAU]),
                  ("the automated route's party 3: CYAN, SABIN (bare fists)",
                   [CYAN, mem("SABIN", [BARE], kit=["blitz"], elem=["holy"])])],
         teaches="The player forms three squads from seven without seeing the enemy, so one row serves the "
                 "raiders: swords, daggers, claws and fangs, the katana and a cutlass. The Rider takes the dagger and the katana, "
                 "Kefka the sword and the dagger, and both Fire and poison: his four cells are full, and the "
                 "katana has none."),
    dict(key="12", name="Kohlingen, the plains and Zozo, with Dadaluma",
         legs=["figaro_submerged", "wob_kohlingen", "zozo_arrival", "zozo_clock_solved", "dadaluma_entry"],
         pools=dict(world=[9, 10, 11, 12, 13], maps=[221, 225], battles=[69], extra=[0x6C], skip=[433]),
         parties=[("all six", SIX)], picks=(SIX, 4),
         teaches="The first free party. EDGAR's tools reach almost everything (the sweep, the new Drill, the Bio "
                 "Blaster); each other member keys about a third by hand, so the pick is a real choice. Dadaluma "
                 "takes the dagger, a blow or poison, and every pick of four holds one."),
]


class Data:
    def __init__(self):
        self.csr = csr = _load(ROOT / "tools/check_shield_rows.py", "csr")
        self.src = csr.read_sources(str(ROOT))
        self.names = json.loads((ROOT / "ff6/src/text/monster_name_en.json").read_text())["text"]
        self.mp = (ROOT / "ff6/src/battle/monster_prop.dat").read_bytes()
        six = csr.parse_rows((ROOT / csr.HUD_ASM).read_text(), "Ot6ShieldTbl", True)
        self.six = {sp: (sh, m) for sp, sh, m, _ in six}
        keep = dict(csr.CLASS_BIT)
        csr.CLASS_BIT = dict(OLD)
        four = csr.parse_rows(base_file(csr.HUD_ASM), "Ot6ShieldTbl", True)
        csr.CLASS_BIT = keep
        self.four = {sp: (sh, m & 15) for sp, sh, m, _ in four}
        self.add = {sp: a for sp, a, _, _ in csr.parse_rows((ROOT / csr.BREAK_ASM).read_text(), "Ot6ElemAddTbl",
                                                            False)}
        self.old_item = old_item_classes()

    def name(self, sp):
        return self.names[sp] if sp < len(self.names) and self.names[sp] else "$%03x" % sp

    def prop(self, sp):
        r = self.mp[sp * 32:sp * 32 + 32]
        return dict(level=r[16], hp=r[8] | (r[9] << 8), weak=r[25] | self.add.get(sp, 0), absorb=r[23], null=r[24],
                    added=self.add.get(sp, 0))

    def group(self, g):
        rbg = self.src["rbg"]
        return [f for i in range(0, 8, 2) for f in self.csr.expand(rbg[g * 8 + i] | (rbg[g * 8 + i + 1] << 8))]

    def event(self, g):
        ebg = self.src["ebg"]
        return [f for w in (ebg[g * 4] | (ebg[g * 4 + 1] << 8), ebg[g * 4 + 2] | (ebg[g * 4 + 3] << 8))
                for f in self.csr.expand(w)]

    def formations(self, pools):
        """[(formation, where)] the area deals, in pool order, each once."""
        out, seen = [], set()

        def add(f, where):
            if f not in seen and f not in pools.get("skip", ()):
                seen.add(f)
                out.append((f, where))
        for m in pools.get("maps", ()):
            assert self.src["props"][m * 33 + 5] & 0x80, "map %d deals no random battles" % m
            for f in self.group(self.src["sbg"][m]):
                add(f, "map %d" % m)
        for g in pools.get("world", ()):
            assert g in self.src["wbg"][:256], "no World of Balance sector deals group %d" % g
            for f in self.group(g):
                add(f, "world group %d" % g)
        for b in pools.get("battles", ()):
            assert b in self.src["called"], "no event calls battle %d" % b
            for f in self.event(b):
                add(f, "battle %d" % b)
        for b in pools.get("chests", ()):
            for f in self.event(b):
                add(f, "chest, battle %d" % b)
        return out

    def species(self, f):
        return self.csr.formation_species(self.src["bm"], f)


def el_names(m):
    return ", ".join(n for n in ELEMENTS if m & EL[n]) or "-"


def six_names(m):
    return ", ".join(C.NAME[b] for b in C.ORDER if m & b) or "-"


def four_names(m):
    return ", ".join(n for b, n in OLD_NAME.items() if m & b) or "-"


def party_masks(d, party):
    """(hand4, kit4, hand6, kit6, elements) of a party of mem() records"""
    h4 = k4 = h6 = k6 = e = 0
    for m in party:
        for it in m["hands"]:
            if it == "fang":
                h4, h6 = h4 | B, h6 | C.KIND_CLASS["fang"]
            else:
                h4, h6 = h4 | d.old_item[it], h6 | C.item_class(it)
        for k in m["kit"]:
            k4, k6 = k4 | OLD_KIT[k], k6 | C.KIND_CLASS[k]
        for n in m["elem"]:
            e |= EL[n]
    return h4, k4 | h4, h6, k6 | h6, e


def keyed(d, sp, masks):
    """how a party keys a species: (four: hand, kit, element), (six: ...)"""
    h4, k4, h6, k6, e = masks
    p = d.prop(sp)
    el = bool(p["weak"] & e & ~(p["absorb"] | p["null"]))
    f, s = d.four.get(sp, (0, 0))[1], d.six.get(sp, (0, 0))[1]
    return (bool(f & h4), bool(f & k4), el), (bool(s & h6), bool(s & k6), el)


def share(d, gauged, masks):
    """[(label, four count, six count)] over the gauged species, and n"""
    rows = []
    for i, label in enumerate(("in hand", "by kit", "by element")):
        rows.append((label, sum(keyed(d, sp, masks)[0][i] for sp in gauged),
                     sum(keyed(d, sp, masks)[1][i] for sp in gauged)))
    rows.append(("any", sum(any(keyed(d, sp, masks)[0]) for sp in gauged),
                 sum(any(keyed(d, sp, masks)[1]) for sp in gauged)))
    return rows, len(gauged)


def formation_share(d, forms, masks, gauged):
    """(formations, those where every gauged body has a key under six, those where none has; the same under four)"""
    full6 = none6 = full4 = none4 = n = 0
    for f, _ in forms:
        sps = [sp for sp in set(d.species(f)) if sp in gauged]
        if not sps:
            continue
        n += 1
        k = [keyed(d, sp, masks) for sp in sps]
        full4 += all(any(a) for a, _ in k)
        none4 += not any(any(a) for a, _ in k)
        full6 += all(any(b) for _, b in k)
        none6 += not any(any(b) for _, b in k)
    return n, full6, none6, full4, none4


def route_fights(d, legs):
    """the automated route's fights in these legs: [(species, hand4, kit4, hand6, kit6)] and the hands it held"""
    if not KEYS.exists():
        return [], collections.Counter()
    skill6 = {"B": C.KIND_CLASS["blitz"], "S": C.KIND_CLASS["swdtech"], "M": C.KIND_CLASS["tekmissile"],
              "T": C.KIND_CLASS["thief hit"]}
    skill4 = {"B": B, "S": S, "M": P, "T": P}
    out, held = [], collections.Counter()
    for f in json.loads(KEYS.read_text()):
        if f["leg"] not in legs:
            continue
        tools = [i for i in f["bag"] if 0xA3 <= i <= 0xAA]
        stars = [i for i in set(f["bag"]) if 0x41 <= i <= 0x43]
        h4 = k4 = h6 = k6 = 0
        for m in f["members"]:
            who = C.CHARS[m["c"]] if m["c"] < len(C.CHARS) else "c%d" % m["c"]
            got = []
            for hand in (m.get("r"), m.get("l")):
                if hand is None:
                    continue
                if m["c"] == 11 and hand == 0xFF:
                    h4, h6 = h4 | B, h6 | C.KIND_CLASS["fang"]
                    got.append("fangs")
                else:
                    h4, h6 = h4 | d.old_item[hand], h6 | C.item_class(hand)
                    got.append("$%02X" % hand)
            for s in m["skills"]:
                k4, k6 = k4 | skill4[s], k6 | skill6[s]
                got.append({"B": "Blitz", "S": "SwdTech", "M": "TekMissile", "T": "Trickshot"}[s])
            if m["tools"]:
                for i in tools:
                    k4, k6 = k4 | d.old_item[i], k6 | C.item_class(i)
                got.append("Tools")
            if m["throw"]:
                for i in stars:
                    k4, k6 = k4 | d.old_item[i], k6 | C.item_class(i)
                got.append("Throw" + ("" if stars else " (no stars)"))
            held["%s %s" % (who, "+".join(got) or "(nothing)")] += 1
        for sp in f["species"]:
            out.append((sp, h4, k4 | h4, h6, k6 | h6))
    return out, held


def area_species(d, area):
    forms = d.formations(area["pools"])
    order = []
    for f, _ in forms:
        for sp in d.species(f):
            if sp not in order:
                order.append(sp)
    for sp in area["pools"].get("extra", ()):
        if sp not in order:
            order.append(sp)
    gauged = [sp for sp in order if d.six.get(sp, (0, 0))[0] > 0]
    return forms, order, gauged


def item_names():
    return json.loads((ROOT / "ff6/src/text/item_name_en.json").read_text())["text"]


def report(d):
    out = []
    w = out.append
    w("the opening under four classes (%s) and six (the working tree): tools/six_classes/opening.py" % BASE)
    w("a share is of the area's gauged species (a shield row with shields); 'any' is hand, kit or element")
    inames = item_names()
    totals = collections.Counter()
    for a in AREAS:
        forms, order, gauged = area_species(d, a)
        w("")
        w("== %s. %s" % (a["key"], a["name"]))
        w("   formations: " + "; ".join("%d [%s] (%s)" % (
            f, ", ".join(d.name(sp) for sp in d.species(f)) or "no monster", where) for f, where in forms))
        for sp in order:
            p = d.prop(sp)
            sh, s6 = d.six.get(sp, (0, 0))
            f4 = d.four.get(sp, (0, 0))[1]
            w("   $%03x %-11s L%-2d HP%-5d shields %d  four: %-15s six: %-22s weak: %s%s%s" % (
                sp, d.name(sp), p["level"], p["hp"], sh, four_names(f4), six_names(s6), el_names(p["weak"]),
                " (added: %s)" % el_names(p["added"]) if p["added"] else "",
                "; absorbs %s" % el_names(p["absorb"] | p["null"]) if p["absorb"] | p["null"] else ""))
        for label, party in a["parties"]:
            masks = party_masks(d, party)
            rows, n = share(d, gauged, masks)
            fn, full6, none6, full4, none4 = formation_share(d, forms, masks, set(gauged))
            w("   party: %s" % label)
            w("      holds, six: in hand %s; by kit %s; elements %s   (four: in hand %s; by kit %s)" % (
                six_names(masks[2]), six_names(masks[3]), el_names(masks[4]), four_names(masks[0]),
                four_names(masks[1])))
            if bin(masks[3]).count("1") == 1:
                w("      ONE WEAPON CLASS (%s): %d of %d gauged species take it; %d take an element it has" % (
                    six_names(masks[3]), rows[1][2], n, rows[2][2]))
            w("      species keyed, of %d:  %s" % (n, ";  ".join("%s four %d, six %d" % r for r in rows)))
            w("      formations, of %d: every body keyed four %d, six %d; no body keyed four %d, six %d" % (
                fn, full4, full6, none4, none6))
            if len(party) > 1:
                for m in party:
                    mm = party_masks(d, [m])
                    r1, _ = share(d, gauged, mm)
                    if label == a["parties"][0][0]:
                        totals[("member", 4)] += r1[3][1]
                        totals[("member", 6)] += r1[3][2]
                        totals[("memberhand", 4)] += r1[1][1]
                        totals[("memberhand", 6)] += r1[1][2]
                        totals["member n"] += n
                    none = [d.name(sp) for sp in gauged if not any(keyed(d, sp, mm)[1])]
                    w("      %-7s six: in hand %d, by kit %d, by element %d, any %d of %d (four: any %d)%s" % (
                        m["name"], r1[0][2], r1[1][2], r1[2][2], r1[3][2], n, r1[3][1],
                        ("; no key: " + ", ".join(none)) if none else ""))
            lost = [d.name(sp) for sp in gauged if any(keyed(d, sp, masks)[0]) and not any(keyed(d, sp, masks)[1])]
            unk = [d.name(sp) for sp in gauged if not any(keyed(d, sp, masks)[1])]
            if unk:
                w("      no key under six: %s%s" % (", ".join(unk), (" (keyed under four: %s)" % ", ".join(lost))
                                                    if lost else ""))
            if label == a["parties"][0][0]:
                for i, r in enumerate(rows):
                    totals[(r[0], 4)] += r[1]
                    totals[(r[0], 6)] += r[2]
                totals["n"] += n
        if "picks" in a:
            pool, k = a["picks"]
            res = []
            for pick in itertools.combinations(pool, k):
                masks = party_masks(d, pick)
                rows, n = share(d, gauged, masks)
                res.append((rows[3][2], rows[0][2], rows[3][1], "+".join(m["name"] for m in pick),
                            [d.name(sp) for sp in gauged if not any(keyed(d, sp, masks)[1])]))
            res.sort()
            w("   every pick of %d from %d (%d picks): keyed any, six: least %d, most %d of %d; four: least %d" % (
                k, len(pool), len(res), res[0][0], res[-1][0], len(gauged), min(r[2] for r in res)))
            for anyk, hand, any4, who, unk in res:
                w("      %-28s six: any %d, in hand %d (four: any %d)%s" % (who, anyk, hand, any4,
                                                                            ("; no key: " + ", ".join(unk)) if unk
                                                                            else ""))
        fights, held = route_fights(d, a["legs"])
        if fights:
            nh4 = sum(1 for sp, h4, k4, h6, k6 in fights if d.four.get(sp, (0, 0))[1] & h4)
            nk4 = sum(1 for sp, h4, k4, h6, k6 in fights if d.four.get(sp, (0, 0))[1] & k4)
            nh6 = sum(1 for sp, h4, k4, h6, k6 in fights if d.six.get(sp, (0, 0))[1] & h6)
            nk6 = sum(1 for sp, h4, k4, h6, k6 in fights if d.six.get(sp, (0, 0))[1] & k6)
            w("   the automated route in legs %s: %d species x fights; keyed in hand four %d, six %d; by kit four "
              "%d, six %d" % (", ".join(a["legs"]), len(fights), nh4, nh6, nk4, nk6))

            def nice(s):
                return re.sub(r"\$([0-9A-F]{2})", lambda m: inames[int(m.group(1), 16)].split("}")[-1], s)
            w("      its hands: " + "; ".join("%s (%d)" % (nice(k), v) for k, v in sorted(held.items())))
    w("")
    w("== the whole opening, each area's first party: species keyed of %d (an area's species counted once an area)"
      % totals["n"])
    for label in ("in hand", "by kit", "by element", "any"):
        w("   %-10s four %3d (%.0f%%)   six %3d (%.0f%%)" % (
            label, totals[(label, 4)], 100.0 * totals[(label, 4)] / totals["n"], totals[(label, 6)],
            100.0 * totals[(label, 6)] / totals["n"]))
    w("   a single member of those parties (of two or more), species x members %d: any key four %d (%.0f%%), six %d "
      "(%.0f%%); by weapon or skill four %d (%.0f%%), six %d (%.0f%%)" % (
          totals["member n"], totals[("member", 4)], 100.0 * totals[("member", 4)] / totals["member n"],
          totals[("member", 6)], 100.0 * totals[("member", 6)] / totals["member n"],
          totals[("memberhand", 4)], 100.0 * totals[("memberhand", 4)] / totals["member n"],
          totals[("memberhand", 6)], 100.0 * totals[("memberhand", 6)] / totals["member n"]))
    return "\n".join(out) + "\n"


def markdown(d):
    """the areas' tables for docs/design/opening.md"""
    out = []
    w = out.append
    for a in AREAS:
        forms, order, gauged = area_species(d, a)
        w("### %s. %s" % (a["key"], a["name"]))
        w("")
        seen = []
        for label, party in a["parties"]:
            masks = party_masks(d, party)
            who = "; ".join("%s (%s)" % (m["name"], m["says"]) if m["says"] else m["name"] for m in party
                            if (m["name"], m["says"]) not in seen)
            rows, n = share(d, gauged, masks)
            line = "**%s.** " % (label[0].upper() + label[1:])
            if who:
                line += who + ". "
            line += "Holds: %s in hand" % six_names(masks[2])
            if masks[3] != masks[2]:
                line += ", %s by kit" % six_names(masks[3] & ~masks[2])
            line += "; elements: %s. " % el_names(masks[4])
            line += "Keys %d of %d species (%d in hand, %d by kit, %d by element); under four classes %d (%d in hand)." % (
                rows[3][2], n, rows[0][2], rows[1][2], rows[2][2], rows[3][1], rows[0][1])
            if 1 < len(party) <= 7:
                each = []
                for m in party:
                    r1, _ = share(d, gauged, party_masks(d, [m]))
                    each.append("%s %d" % (m["name"], r1[3][2]))
                line += " Each member's own keys: %s." % ", ".join(each)
            w(line)
            w("")
            seen += [(m["name"], m["says"]) for m in party]
        w("| species | L | HP | shields | weapon weaknesses | elements | on main (four classes) |")
        w("|---|---|---|---|---|---|---|")
        for sp in order:
            p = d.prop(sp)
            sh, s6 = d.six.get(sp, (0, 0))
            f4 = d.four.get(sp, (0, 0))[1]
            el = el_names(p["weak"] & ~p["added"]) if p["weak"] & ~p["added"] else ""
            if p["added"]:
                el = (el + ", " if el else "") + "+" + el_names(p["added"]).replace(", ", ", +")
            if p["absorb"] | p["null"]:
                el = (el or "-") + "; absorbs " + el_names(p["absorb"] | p["null"])
            if sh == 0:
                w("| `$%03X` %s | %d | %d | no gauge | | | |" % (sp, d.name(sp), p["level"], p["hp"]))
            else:
                w("| `$%03X` %s | %d | %d | %d | %s | %s | %s |" % (
                    sp, d.name(sp), p["level"], p["hp"], sh, six_names(s6), el or "-", four_names(f4)))
        w("")
        w("Formations: " + "; ".join("%s (%s)" % (" + ".join(
            "%s%s" % (d.name(sp), " x%d" % c if c > 1 else "") for sp, c in collections.Counter(
                d.species(f)).items()) or "no monster", where) for f, where in forms) + ".")
        w("")
        w("Teaches: " + a["teaches"])
        w("")
    return "\n".join(out)


def main():
    d = Data()
    if "--md" in sys.argv:
        sys.stdout.write(markdown(d))
    elif "--write" in sys.argv:
        OUT.mkdir(parents=True, exist_ok=True)
        (OUT / "shares.txt").write_text(report(d))
        (OUT / "tables.md").write_text(markdown(d))
        print("wrote %s and tables.md" % (OUT / "shares.txt").relative_to(ROOT))
    else:
        sys.stdout.write(report(d))


if __name__ == "__main__":
    main()
