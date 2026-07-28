#!/usr/bin/env python3
"""Encounter-and-party break-class reachability check.

The break floor's regression tests prove nonzero table bytes; nothing static
proved that the party who actually walks a route band can FIELD a class some
body in every formation is weak to.  This linter closes that gap for the
declared bands (docs/design/break-band-vector.md SS10.2 item 3):

  * walk SubBattleGroup -> RandBattleGroup -> BattleMonsters for the band's
    named encounter maps (field/battle.asm:392,:408; battle_main.asm:16610),
  * PLUS the forced-battle list: EventBattleGroup entries reached by event
    `battle` commands (field/event.asm EventBattle) and by the magitek train
    ride script's $e0/$e1/$e2 items (world/train_script.asm TrainCmd_e0/e1/e2)
    -- the minecart writes $0011e0 directly and is invisible to any
    event-script scan,
  * take the declared party for each leg and compute the weapon/ability
    classes each member can field (item_prop_en.dat equip mask at +$01,
    16-bit, bit N = actor N -- docs/research/data-formats.md; classes from
    Ot6WeapClassTbl / Ot6SkillClassTbl in ot6_class.asm),
  * and assert every formation has at least one break-class key
    (Ot6ShieldTbl row's class byte, else the generated floor) that some
    member can field.

"Can field" is game-wide equippability plus command ownership (SwdTech=Cyan,
Blitz=Sabin, Tools=Edgar), plus bare fists -- Ot6WeapClassTbl[$ff] is
OT6_BLUDG, so an empty hand is a bludgeoning probe for anyone.  It is NOT
inventory: whether the item is in the bag is a runtime fixture assertion
(break-band-vector.md SS10.3), not a static one.  Weapons carrying
OT6_NULLBRK chip nothing (ot6_class.asm:14-17) and grant no class here.

Bands are declared in BANDS below; add a band by adding an entry, nothing
else changes.  The vector-factory band's map set and forced list are the
survey's SS1.1/SS2 decode; the party is docs/design/bosses-wob.md SS13-16
(LOCKE CELES SABIN EDGAR, three after the tube room takes Celes).

Nothing here writes; it is a read-only linter.  Exit status 0 = clean.
One loud block per formation with no reachable break class.

Usage:  python3 tools/check_break_reach.py [--repo ROOT] [-v]
                [--band NAME] [--party A,B,C] [--drop-class CLS]

--party and --drop-class exist to demonstrate failure (an impoverished
party, or "nobody can field bludgeon") and for what-if probes; the bare
invocation is the gate.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys

# --------------------------------------------------------------------------
# class bits (ff6/src/battle/ot6_class.asm:10-14)

CLASS_BIT = {"slash": 0x01, "pierce": 0x02, "bludg": 0x04, "special": 0x08}
CLASS_TOKEN = {"OT6_SLASH": 0x01, "OT6_PIERCE": 0x02, "OT6_BLUDG": 0x04,
               "OT6_SPECIAL": 0x08, "OT6_NULLBRK": 0x80}
NULLBRK = 0x80


def class_str(mask):
    if mask & 0x0F == 0:
        return "(none)"
    return "|".join(n for n, b in CLASS_BIT.items() if mask & b)


# actor bit = actor index (CharEquipMaskTbl is an identity table --
# ff6/src/menu/equip.asm:2287; docs/research/data-formats.md, PINNED)
ACTORS = ["TERRA", "LOCKE", "CYAN", "SHADOW", "EDGAR", "SABIN", "CELES",
          "STRAGO", "RELM", "SETZER", "MOG", "GAU", "GOGO", "UMARO"]
ACTOR_ID = {n: i for i, n in enumerate(ACTORS)}

# command ownership: who can use an ability id from Ot6SkillClassTbl.
# SwdTech $55-$5c = Cyan, Blitz $5d/$5f/$64 = Sabin (ot6_class.asm:185-195).
# TekMissile $8a is Magitek-armor only -- no walking party owns it.
ABILITY_OWNER = {sid: "CYAN" for sid in range(0x55, 0x5D)}
ABILITY_OWNER.update({0x5D: "SABIN", 0x5F: "SABIN", 0x64: "SABIN"})

# Tools are type-0 items resolved through the Tools command (Edgar's); their
# class bytes live in Ot6WeapClassTbl at the item id (ot6_class.asm:149-158).
# Gogo can mimic/equip Tools too, but no declared band relies on that.
TOOLS_RANGE = range(0xA3, 0xAB)
TOOLS_OWNER = "EDGAR"

# --------------------------------------------------------------------------
# band declarations.  A band is a list of legs; a leg is a party plus the
# random-encounter maps it walks and the forced battles it must fight.
# events: (event battle id, tuple of EventBattleGroup word slots reached,
#          human label).  EventBattle rolls word 0 at 75% / word 1 at 25%
# (field/event.asm @a5a7), TrainCmd_e0/e1 do the same (train_script.asm
# @327a/@32c8), TrainCmd_e2 takes word 0 only (@3316).

BANDS = {
    "vector-factory": {
        "doc": "docs/design/break-band-vector.md SS1-2, SS6",
        "min_formations": 15,   # parser self-check: fewer means drift
        "legs": [
            {
                "name": "facility, four (bosses-wob.md SS13-14)",
                "party": ["LOCKE", "CELES", "SABIN", "EDGAR"],
                "maps": [262, 263, 264, 269, 271, 273],
                "events": [
                    (70, (0, 1), "Ifrit approach (event battle 70)"),
                    (72, (0, 1), "Number 024 (event battle 72)"),
                ],
            },
            {
                "name": "escape, three -- Celes lost in the tube room "
                        "(bosses-wob.md SS15-16)",
                "party": ["LOCKE", "SABIN", "EDGAR"],
                "maps": [240],
                "events": [
                    (41, (0, 1), "minecart $e0 (event battle 41)"),
                    (144, (0, 1), "minecart $e1 (event battle 144)"),
                    (73, (0,), "minecart $e2 (event battle 73, Number 128)"),
                    (71, (0, 1), "Left & Right Cranes (event battle 71)"),
                ],
            },
        ],
    },
    # The Cave to the Sealed Gate (issue #31, v0.7).  Map set verified from
    # data, not the recon: 382/383/384/385 are the only maps in the band
    # with the enable bit set AND an entrance or load_map reaching them
    # (379/380/381/387/388 carry enable bits or groups but nothing targets
    # them -- the map-275 pattern).  The Imperial Base (377/378) has the
    # enable bit CLEAR, so it contributes no encounters.  Battles 121/122/123
    # (the gate scene and the esper attack) decode to dummy-only formations
    # ($17b L1 HP1) and their real contents live in battle-event scripts
    # being probed by a separate agent -- deliberately NOT declared here;
    # add them when the probe lands.  Battle 149 is the map-384 (66,11)
    # trap-switch Ninja ambush (event_main.asm:45177) and is real.
    "sealed-gate": {
        "doc": "docs/design/break-band-sealed-gate.md SS1-2, SS5",
        "min_formations": 13,   # 3 unique per map x4 maps + the Ninja
        "legs": [
            {
                "name": "cave, four (issue #31 dispatcher ruling: Terra "
                        "seated, Setzer benched)",
                "party": ["TERRA", "LOCKE", "EDGAR", "SABIN"],
                "maps": [382, 383, 384, 385],
                "events": [
                    (149, (0, 1),
                     "Ninja trap switch, map 384 (66,11) (event battle 149)"),
                ],
            },
        ],
    },
}

# --------------------------------------------------------------------------
# data files

MAP_PROP = "ff6/src/field/map_prop.dat"            # 33 B/map; +5 bit7 = random battles
SUB_GROUP = "ff6/src/field/sub_battle_group.dat"   # 1 B/map -> group
RAND_GROUP = "ff6/src/field/rand_battle_group.dat" # 4 formation words/group
EVENT_GROUP = "ff6/src/field/event_battle_group.dat"  # 2 formation words/battle
MONSTERS = "ff6/src/battle/battle_monsters.dat"    # 15 B/formation
ITEM_PROP = "ff6/src/menu/item_prop_en.dat"        # 30 B/item
MONSTER_NAMES = "ff6/src/text/monster_name_en.json"
CLASS_ASM = "ff6/src/battle/ot6_class.asm"
HUD_ASM = "ff6/src/battle/ot6_hud.asm"
FLOOR_INC = "ff6/src/battle/ot6_break_floor.inc"

MAP_REC = 33
ITEM_REC = 30
FORM_REC = 15
N_FORMS = 576
N_SPECIES = 384


def _eval_expr(expr, where):
    """Evaluate a tiny asm constant expression like '$a3 - $5a'."""
    s = expr.replace("$", "0x")
    if not re.fullmatch(r"[0-9a-fA-Fx+\-*() ]+", s):
        raise SystemExit("check_break_reach: unparseable expression %r at %s"
                         % (expr, where))
    return eval(s, {"__builtins__": {}})  # noqa: S307 -- vetted charset above


class Data:
    def __init__(self, root):
        self.root = root
        self.map_prop = self._read(MAP_PROP)
        self.sub = self._read(SUB_GROUP)
        self.rand = self._read(RAND_GROUP)
        self.event = self._read(EVENT_GROUP)
        self.monsters = self._read(MONSTERS)
        self.items = self._read(ITEM_PROP)
        with open(os.path.join(root, MONSTER_NAMES), encoding="utf-8") as f:
            self.names = json.load(f)["text"]
        self.weap_class = self._parse_weap_tbl()
        self.skill_class = self._parse_skill_tbl()
        self.shield_tbl = self._parse_shield_tbl()
        self.floor = self._parse_floor()

    def _read(self, rel):
        with open(os.path.join(self.root, rel), "rb") as f:
            return f.read()

    def _text(self, rel):
        with open(os.path.join(self.root, rel), encoding="utf-8") as f:
            return f.read()

    # -- table parsers ---------------------------------------------------
    def _parse_weap_tbl(self):
        """Ot6WeapClassTbl: 256 class bytes, item-id indexed (.byte / .res)."""
        src = self._text(CLASS_ASM).splitlines()
        start = next(i for i, l in enumerate(src)
                     if l.strip().startswith("Ot6WeapClassTbl:"))
        out = []
        for i in range(start + 1, len(src)):
            code = src[i].split(";", 1)[0].strip()
            if not code:
                continue
            m = re.match(r"\.byte\s+(.+)$", code)
            if m:
                v = 0
                for tok in m.group(1).split("|"):
                    tok = tok.strip()
                    v |= CLASS_TOKEN.get(tok) if tok in CLASS_TOKEN else \
                        _eval_expr(tok, "%s:%d" % (CLASS_ASM, i + 1))
                out.append(v)
            elif code.startswith(".res"):
                m = re.match(r"\.res\s+(.+?),\s*(\S+)$", code)
                n = _eval_expr(m.group(1), "%s:%d" % (CLASS_ASM, i + 1))
                fill = _eval_expr(m.group(2), "%s:%d" % (CLASS_ASM, i + 1))
                out.extend([fill] * n)
            else:
                break  # next label / directive: table ended
            if len(out) >= 256:
                break
        if len(out) != 256:
            raise SystemExit("check_break_reach: Ot6WeapClassTbl parsed %d "
                             "bytes, want 256 (%s)" % (len(out), CLASS_ASM))
        return out

    def _parse_skill_tbl(self):
        """Ot6SkillClassTbl: (ability id, class) pairs, $ff-terminated."""
        src = self._text(CLASS_ASM).splitlines()
        start = next(i for i, l in enumerate(src)
                     if l.strip().startswith("Ot6SkillClassTbl:"))
        out = {}
        for i in range(start + 1, len(src)):
            code = src[i].split(";", 1)[0].strip()
            if not code:
                continue
            m = re.match(r"\.byte\s+\$([0-9a-fA-F]{2})\s*,\s*(\S+)$", code)
            if m:
                out[int(m.group(1), 16)] = CLASS_TOKEN[m.group(2).strip()]
                continue
            if re.match(r"\.byte\s+\$ff\s*$", code):
                break
            break
        if len(out) < 10:
            raise SystemExit("check_break_reach: Ot6SkillClassTbl parsed %d "
                             "entries, want >= 10 (%s)" % (len(out), CLASS_ASM))
        return out

    def _parse_shield_tbl(self):
        """Ot6ShieldTbl: .word species / .byte shields, classes ($ffff-term)."""
        src = self._text(HUD_ASM).splitlines()
        start = next(i for i, l in enumerate(src)
                     if l.strip().startswith("Ot6ShieldTbl:"))
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
            m = re.match(r"\s*\.byte\s+(\S+)\s*,\s*(.+?)\s*$", code)
            if m and pending is not None:
                shields = int(m.group(1), 0)
                cls = 0
                for tok in re.split(r"\|", m.group(2)):
                    tok = tok.strip()
                    if tok in ("$00", "0"):
                        continue
                    if tok not in CLASS_TOKEN:
                        raise SystemExit(
                            "check_break_reach: unknown class token %r at %s:%d"
                            % (tok, HUD_ASM, i + 1))
                    cls |= CLASS_TOKEN[tok]
                out[pending] = {"shields": shields, "class": cls, "line": i + 1}
                pending = None
        if len(out) < 70:
            raise SystemExit("check_break_reach: Ot6ShieldTbl parsed %d rows, "
                             "want >= 70 -- parser drift (%s)" % (len(out), HUD_ASM))
        return out

    def _parse_floor(self):
        """ot6_break_floor.inc: one class byte per species, id order."""
        vals = []
        for line in self._text(FLOOR_INC).splitlines():
            code = line.split(";", 1)[0]
            m = re.match(r"\s*\.byte\s+(\S+)\s*$", code)
            if m:
                tok = m.group(1).strip()
                vals.append(CLASS_TOKEN.get(tok, 0))
        if len(vals) != N_SPECIES:
            raise SystemExit("check_break_reach: floor parsed %d species, "
                             "want %d (%s)" % (len(vals), N_SPECIES, FLOOR_INC))
        return vals

    # -- decode ------------------------------------------------------------
    def map_random_enabled(self, m):
        return bool(self.map_prop[m * MAP_REC + 5] & 0x80)

    def map_group(self, m):
        return self.sub[m]

    def group_formations(self, g):
        """Four slot words at 31.25/31.25/31.25/6.25% (field/battle.asm:398-408)."""
        return [int.from_bytes(self.rand[g * 8 + 2 * i: g * 8 + 2 * i + 2],
                               "little") for i in range(4)]

    def event_formation(self, battle, word):
        off = battle * 4 + word * 2
        return int.from_bytes(self.event[off:off + 2], "little")

    def formation_bodies(self, f):
        """[(species, count)] -- byte 1 present mask, +2..7 id low, +14 id high."""
        rec = self.monsters[f * FORM_REC:(f + 1) * FORM_REC]
        seen = {}
        for slot in range(6):
            if rec[1] & (1 << slot):
                sp = rec[2 + slot] | (((rec[14] >> slot) & 1) << 8)
                seen[sp] = seen.get(sp, 0) + 1
        return sorted(seen.items())

    def species_class(self, sp):
        """(class mask, source, gauge-less?) for one body."""
        row = self.shield_tbl.get(sp)
        if row is not None:
            gaugeless = row["class"] == 0 and row["shields"] == 0
            return row["class"] & 0x0F, "Ot6ShieldTbl:%d" % row["line"], gaugeless
        return self.floor[sp] & 0x0F, "floor", False

    # -- party -------------------------------------------------------------
    def actor_classes(self, name):
        """Classes actor NAME can field: equippable weapons + owned abilities
        + bare fists.  NULLBRK weapons chip nothing and grant nothing."""
        a = ACTOR_ID[name]
        mask = 0
        for it in range(256):
            rec = self.items[it * ITEM_REC:(it + 1) * ITEM_REC]
            if rec[0] & 0x07 != 1:          # not a weapon
                continue
            if not (int.from_bytes(rec[1:3], "little") >> a) & 1:
                continue
            cls = self.weap_class[it]
            if cls & NULLBRK:
                continue
            mask |= cls & 0x0F
        for sid, owner in ABILITY_OWNER.items():
            if owner == name and sid in self.skill_class:
                mask |= self.skill_class[sid] & 0x0F
        if name == TOOLS_OWNER:
            for it in TOOLS_RANGE:
                mask |= self.weap_class[it] & 0x0F
        mask |= self.weap_class[0xFF] & 0x0F   # bare fists (empty hand $ff)
        return mask


# --------------------------------------------------------------------------

def check_band(data, band_name, band, party_override, drop_mask, verbose):
    problems = []
    checked = 0

    for leg in band["legs"]:
        party = party_override or leg["party"]
        for who in party:
            if who not in ACTOR_ID:
                raise SystemExit("check_break_reach: unknown actor %r" % who)
        fieldable = 0
        per_actor = {}
        for who in party:
            per_actor[who] = data.actor_classes(who) & ~drop_mask
            fieldable |= per_actor[who]
        if verbose:
            print("  leg %r party=%s fields %s (%s)"
                  % (leg["name"], ",".join(party), class_str(fieldable),
                     " ".join("%s=%s" % (w, class_str(m))
                              for w, m in per_actor.items())))

        jobs = []   # (label, formation)
        for m in leg["maps"]:
            if not data.map_random_enabled(m):
                problems.append(
                    "band %s: map %d is declared as encounter-bearing but its "
                    "random-battle enable bit is CLEAR (%s +%d bit7) -- the "
                    "declaration has drifted from the data"
                    % (band_name, m, MAP_PROP, m * MAP_REC + 5))
                continue
            g = data.map_group(m)
            for f in sorted(set(data.group_formations(g))):
                jobs.append(("map %d group %d" % (m, g), f))
        for battle, words, label in leg["events"]:
            for w in sorted(set(words)):
                jobs.append((label, data.event_formation(battle, w)))

        seen = set()
        for where, f in jobs:
            if f >= N_FORMS:
                problems.append("band %s: %s names formation $%03x, out of "
                                "range (max $%03x)" % (band_name, where, f, N_FORMS - 1))
                continue
            key = (where, f)
            if key in seen:
                continue
            seen.add(key)
            bodies = data.formation_bodies(f)
            if not bodies:
                problems.append("band %s: %s formation $%03x has an empty "
                                "present mask -- decode drift" % (band_name, where, f))
                continue
            checked += 1
            keys = 0
            gaugeless_only = True
            parts = []
            for sp, n in bodies:
                cls, src, gaugeless = data.species_class(sp)
                if not gaugeless:
                    gaugeless_only = False
                    keys |= cls
                parts.append("%s($%03x)x%d=%s[%s]"
                             % (data.names[sp], sp, n,
                                class_str(cls) if not gaugeless else "no gauge", src))
            if verbose:
                print("    %s formation $%03x: %s -> keys %s"
                      % (where, f, " ".join(parts), class_str(keys)))
            if gaugeless_only:
                continue    # nothing in the fight carries a gauge at all
            if keys & fieldable == 0:
                problems.append(
                    "band %s / %s / formation $%03x: NO REACHABLE BREAK CLASS\n"
                    "    bodies: %s\n"
                    "    formation keys %s vs party {%s} fielding %s"
                    % (band_name, where, f, " ".join(parts),
                       class_str(keys), ",".join(party), class_str(fieldable)))

    if checked < band["min_formations"]:
        problems.append(
            "band %s: only %d formations checked, declaration expects >= %d "
            "-- the walk has drifted (map set, group table, or parser)"
            % (band_name, checked, band["min_formations"]))
    return problems, checked


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--repo", default=os.path.dirname(os.path.dirname(
        os.path.abspath(__file__))))
    ap.add_argument("--band", choices=sorted(BANDS), default=None,
                    help="check one band (default: all declared bands)")
    ap.add_argument("--party", default=None,
                    help="comma-separated actor names overriding every leg's "
                         "declared party (what-if / failure demo)")
    ap.add_argument("--drop-class", action="append", default=[],
                    choices=sorted(CLASS_BIT),
                    help="pretend no member can field this class (repeatable)")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()

    party_override = None
    if args.party:
        party_override = [w.strip().upper() for w in args.party.split(",") if w.strip()]
    drop_mask = 0
    for c in args.drop_class:
        drop_mask |= CLASS_BIT[c]

    data = Data(args.repo)
    names = [args.band] if args.band else sorted(BANDS)
    all_problems = []
    total = 0
    print("break-class encounter/party reachability check")
    for bn in names:
        problems, checked = check_band(data, bn, BANDS[bn], party_override,
                                       drop_mask, args.verbose)
        mode = ""
        if party_override:
            mode += " party-override=%s" % ",".join(party_override)
        if drop_mask:
            mode += " dropped=%s" % class_str(drop_mask)
        print("  band %-16s: %d formations checked%s" % (bn, checked, mode))
        all_problems.extend(problems)
        total += checked

    if all_problems:
        print("  %d PROBLEM(S):" % len(all_problems))
        print()
        for p in all_problems:
            print("  " + p.replace("\n", "\n  "))
            print()
        return 1
    print("  OK -- every checked formation has a break-class key the leg's "
          "party can field")
    return 0


if __name__ == "__main__":
    sys.exit(main())
