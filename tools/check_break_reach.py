#!/usr/bin/env python3
"""Encounter-and-party break-class reachability check.

For each declared area (AREAS below): walks SubBattleGroup -> RandBattleGroup
-> BattleMonsters for the area's encounter maps, plus its forced
EventBattleGroup entries, and asserts every formation has a reachable chip on
at least one axis -- a break-class key (Ot6ShieldTbl's class byte, else the
generated floor) some party member can field, or an element some body is
weak to (monster_prop.dat +25 OR'd with Ot6ElemAddTbl) some member can
deliver.

"Can field" reads equippability and command ownership from item_prop_en.dat
and ff6/src/field/char_prop.asm; SwdTech/Blitz/Tools classes go to whoever
owns those commands.  "Can deliver" mirrors it for elements: weapon elements
(item_prop +$0F), tool attack elements (Tools ownership), and kit-ability
elements (SwdTech/Blitz ownership).  Spell elements are runtime state and are
not credited.  Weapons carrying OT6_NULLBRK grant no class or element.

Nothing here writes.  It is a read-only linter.  Exit status 0 = clean.
It prints one block per formation with no reachable break class.

Usage:  python3 tools/check_break_reach.py [--repo ROOT] [-v]
                [--area NAME] [--party A,B,C] [--drop-class CLS]

--party and --drop-class exist to demonstrate failure and for what-if probes.
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


# element bits, vanilla's own order.
ELEM_BIT = {"fire": 0x01, "ice": 0x02, "bolt": 0x04, "poison": 0x08,
            "wind": 0x10, "holy": 0x20, "earth": 0x40, "water": 0x80}


def elem_str(mask):
    if mask & 0xFF == 0:
        return "(none)"
    return "|".join(n for n, b in ELEM_BIT.items() if mask & b)


# actor bit = actor index (CharEquipMaskTbl is an identity table --
# ff6/src/menu/equip.asm:2287; docs/research/data-formats.md, PINNED)
ACTORS = ["TERRA", "LOCKE", "CYAN", "SHADOW", "EDGAR", "SABIN", "CELES",
          "STRAGO", "RELM", "SETZER", "MOG", "GAU", "GOGO", "UMARO"]
ACTOR_ID = {n: i for i, n in enumerate(ACTORS)}

# command ownership: which battle command resolves each classed ability id in
# Ot6SkillClassTbl (ot6_class.asm:185-195).  Who owns that command is read
# from char_prop.asm, not written down here.
# TekMissile $8a is Magitek-armor only.  No walking party owns it, so it
# appears in no row below and is credited to nobody.
COMMAND_ABILITIES = {
    "BUSHIDO": tuple(range(0x55, 0x5D)),        # swdtech
    "BLITZ": tuple(range(0x5D, 0x65)),          # blitz
}
# The full id ranges: a lookup in skill_class filters the class side (an
# unclassed ability grants no class), and the element side reads magic_prop
# for every id the command resolves (AuraBolt $5e carries holy and no class
# row at all).

# Tools are type-0 items resolved through the Tools command; their class bytes
# live in Ot6WeapClassTbl at the item id (ot6_class.asm:149-158).
TOOLS_RANGE = range(0xA3, 0xAB)

# the command that swings an equipped weapon (and an empty hand).  JUMP is
# Fight under Dragoon Boots (RelicCmdTbl1/2, battle_main.asm:14095-14102) and
# needs no row of its own: the relic only rewrites a slot that already held
# Fight.
SWING_COMMAND = "FIGHT"

# actors who swing without owning the command.  UMARO never opens a battle
# menu (CheckPlayerAction returns early on CHAR::UMARO,
# battle_main.asm:1465-1467) and attacks through his own character AI every
# turn, so his weapon and his fists are fieldable.
AUTO_SWINGERS = {"UMARO"}

# actors who can only repeat another member's action.  GOGO can equip weapons
# but owns only MIMIC, so every class he fields is one somebody else fielded
# first, and he is credited with nothing of his own.  No declared area seats
# him.
MIMIC_ONLY = {"GOGO"}

# --------------------------------------------------------------------------
# area declarations.  An area is a list of steps; a step is a party plus the
# random-encounter maps it walks and the forced battles it must fight.
# events: (event battle id, tuple of EventBattleGroup word slots reached,
#          human label).  EventBattle rolls word 0 at 75% / word 1 at 25%
# (field/event.asm @a5a7), TrainCmd_e0/e1 do the same (train_script.asm
# @327a/@32c8), TrainCmd_e2 takes word 0 only (@3316).

AREAS = {
    "vector-factory": {
        "doc": "docs/design/break-coverage-vector.md SS1-2, SS6",
        "min_formations": 15,   # parser self-check: fewer means drift
        "steps": [
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
    # Maps 382-385 are the only Sealed Gate maps with the random-battle
    # enable bit set and reachable; battle 149 is the map-384 (66,11)
    # trap-switch Ninja ambush.
    "sealed-gate": {
        "doc": "docs/design/break-coverage-sealed-gate.md SS1-2, SS5",
        "min_formations": 13,   # 3 unique per map x4 maps + the Ninja
        "steps": [
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
    # Maps 221 and 225 are Zozo's encounter-bearing climb maps (groups 77
    # and 78).  HadesGigas, Gabbldegak, Harvester and SlamDancer carry
    # authored no-class shield rows and are opened by poison weakness
    # through Edgar's Bio Blaster.
    "zozo": {
        "doc": "ot6_hud.asm's Zozo block + HANDOFF 'Zozo is broken by an "
               "element, not by a class'",
        "min_formations": 8,    # groups 77+78, four formations each
        "steps": [
            {
                "name": "the climb, four (LOCKE CELES EDGAR SABIN)",
                "party": ["LOCKE", "CELES", "EDGAR", "SABIN"],
                "maps": [221, 225],
                "events": [],
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
CHAR_PROP = "ff6/src/field/char_prop.asm"          # 22 B/actor; +2..+5 cmds

MAGIC_PROP = "ff6/src/battle/magic_prop_en.dat"   # 14 B/attack; +1 element

MAP_REC = 33
ITEM_REC = 30
FORM_REC = 15
MAGIC_REC = 14
N_FORMS = 576
N_SPECIES = 384

OFF_WEAP_ELEM = 0x0F      # item_prop weapon element (data-formats.md)
OFF_ATK_ELEM = 0x01       # magic_prop attack element (data-formats.md)
TOOL_ATK_DELTA = 0x27     # tool item id - $27 = its attack id; anchored to
                          # ot6_break.asm's "item $a4 -> attack $7d" at load


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
        self.magic = self._read(MAGIC_PROP)
        with open(os.path.join(root, MONSTER_NAMES), encoding="utf-8") as f:
            self.names = json.load(f)["text"]
        self.weap_class = self._parse_weap_tbl()
        self.skill_class = self._parse_skill_tbl()
        self.shield_tbl = self._parse_shield_tbl()
        self.floor = self._parse_floor()
        self.commands = self._parse_commands()
        # The element side reads monster_prop and Ot6ElemAddTbl through
        # check_boss_rows' Data, the checker that already owns those parses
        # (effective_weak is the same merge Ot6SeedShields performs).
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import check_boss_rows
        self.boss = check_boss_rows.Data(root)
        self._check_element_anchors()

    def _check_element_anchors(self):
        """Verify the offsets the element axis rides against known records
        before computing a verdict from them."""
        checks = [
            (self.attack_elem(0xA4 - TOOL_ATK_DELTA), 0x08,
             "Bio Blaster attack element (magic_prop $7d +$01)"),
            (self.attack_elem(0x5E), 0x20,
             "AuraBolt attack element (magic_prop $5e +$01)"),
            (self.weapon_elem(0x0F), 0x04,
             "ThunderBlade weapon element (item_prop $0f +$0f)"),
        ]
        for got, want, what in checks:
            if got != want:
                raise SystemExit("check_break_reach: element anchor drifted: "
                                 "%s reads $%02x, expected $%02x"
                                 % (what, got, want))

    def weapon_elem(self, it):
        return self.items[it * ITEM_REC + OFF_WEAP_ELEM]

    def attack_elem(self, atk):
        return self.magic[atk * MAGIC_REC + OFF_ATK_ELEM]

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

    def _parse_commands(self):
        """char_prop.asm -> {ACTOR: frozenset of battle command names}.

        Records are emitted in actor order, one `; N: name` header and one
        optional `set_char_prop_cmds` per record.  An actor with no
        set_char_prop_cmds line (UMARO) owns no commands.  That is real data
        rather than a parse miss, so it is recorded as the empty set.
        """
        out = {}
        who = None
        for i, line in enumerate(self._text(CHAR_PROP).splitlines()):
            code = line.split(";", 1)[0].strip()
            m = re.match(r";\s*(\d+):\s*(\S+)", line.strip())
            if m:
                idx, name = int(m.group(1)), m.group(2).upper()
                if idx < len(ACTORS):
                    if ACTORS[idx] != name:
                        raise SystemExit(
                            "check_break_reach: %s:%d actor %d is %r, the "
                            "checker's ACTORS says %r -- table drift"
                            % (CHAR_PROP, i + 1, idx, name, ACTORS[idx]))
                    who = name
                    out.setdefault(who, frozenset())
                else:
                    who = None       # ghosts, esper terra and the rest
                continue
            m = re.match(r"set_char_prop_cmds\s+(.*)$", code)
            if m and who is not None:
                cmds = {c.strip().upper() for c in m.group(1).split(",")
                        if c.strip() and c.strip().upper() != "NONE"}
                out[who] = frozenset(cmds)
        missing = [n for n in ACTORS if n not in out]
        if missing:
            raise SystemExit("check_break_reach: %s named no record for %s "
                             "-- parser drift" % (CHAR_PROP, ",".join(missing)))
        return out

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
        """Classes actor NAME can field: equippable weapons + bare fists if he
        owns a command that swings them, plus the classes of the abilities his
        commands resolve.  NULLBRK weapons chip nothing and grant nothing."""
        a = ACTOR_ID[name]
        cmds = self.commands[name]
        mask = 0
        if name in MIMIC_ONLY:
            return 0
        if SWING_COMMAND in cmds or name in AUTO_SWINGERS:
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
            mask |= self.weap_class[0xFF] & 0x0F   # bare fists (empty hand $ff)
        for cmd, sids in COMMAND_ABILITIES.items():
            if cmd not in cmds:
                continue
            for sid in sids:
                if sid in self.skill_class:
                    mask |= self.skill_class[sid] & 0x0F
        if "TOOLS" in cmds:
            for it in TOOLS_RANGE:
                mask |= self.weap_class[it] & 0x0F
        return mask

    def actor_elems(self, name):
        """Elements actor NAME can deliver, the mirror of actor_classes:
        weapon elements under the same equip-mask-plus-swing rule, tool
        attack elements for Tools owners, kit-ability elements for
        SwdTech/Blitz owners.  Spell elements are runtime state and are
        deliberately absent (module docstring).  NULLBRK weapons chip
        nothing on either axis and grant nothing."""
        a = ACTOR_ID[name]
        cmds = self.commands[name]
        mask = 0
        if name in MIMIC_ONLY:
            return 0
        if SWING_COMMAND in cmds or name in AUTO_SWINGERS:
            for it in range(256):
                rec = self.items[it * ITEM_REC:(it + 1) * ITEM_REC]
                if rec[0] & 0x07 != 1:          # not a weapon
                    continue
                if not (int.from_bytes(rec[1:3], "little") >> a) & 1:
                    continue
                if self.weap_class[it] & NULLBRK:
                    continue
                mask |= self.weapon_elem(it)
        for cmd, sids in COMMAND_ABILITIES.items():
            if cmd not in cmds:
                continue
            for sid in sids:
                mask |= self.attack_elem(sid)
        if "TOOLS" in cmds:
            for it in TOOLS_RANGE:
                if self.weap_class[it] & NULLBRK:
                    continue
                mask |= self.attack_elem(it - TOOL_ATK_DELTA)
        return mask

    def species_break_elems(self, sp):
        """Elements a chip lands on for one body: the effective weak byte
        (monster_prop +25 merged with Ot6ElemAddTbl, check_boss_rows'
        effective_weak -- the same merge Ot6SeedShields performs), minus
        anything the body absorbs or nulls.  The authoring rule already
        forbids weak-and-absorbed rows; the mask is defense against drift."""
        return (self.boss.effective_weak(sp)
                & ~self.boss.vanilla_absorb(sp)
                & ~self.boss.vanilla_null(sp))


# --------------------------------------------------------------------------

def check_area(data, area_name, area, party_override, drop_mask,
               drop_elem_mask, verbose):
    problems = []
    checked = 0

    for step in area["steps"]:
        party = party_override or step["party"]
        for who in party:
            if who not in ACTOR_ID:
                raise SystemExit("check_break_reach: unknown actor %r" % who)
        fieldable = 0
        deliverable = 0
        per_actor = {}
        for who in party:
            per_actor[who] = data.actor_classes(who) & ~drop_mask
            fieldable |= per_actor[who]
            deliverable |= data.actor_elems(who) & ~drop_elem_mask
        if verbose:
            print("  step %r party=%s fields %s, delivers %s (%s)"
                  % (step["name"], ",".join(party), class_str(fieldable),
                     elem_str(deliverable),
                     " ".join("%s=%s" % (w, class_str(m))
                              for w, m in per_actor.items())))

        jobs = []   # (label, formation)
        for m in step["maps"]:
            if not data.map_random_enabled(m):
                problems.append(
                    "area %s: map %d is declared as encounter-bearing but its "
                    "random-battle enable bit is CLEAR (%s +%d bit7) -- the "
                    "declaration has drifted from the data"
                    % (area_name, m, MAP_PROP, m * MAP_REC + 5))
                continue
            g = data.map_group(m)
            for f in sorted(set(data.group_formations(g))):
                jobs.append(("map %d group %d" % (m, g), f))
        for battle, words, label in step["events"]:
            for w in sorted(set(words)):
                jobs.append((label, data.event_formation(battle, w)))

        seen = set()
        for where, f in jobs:
            if f >= N_FORMS:
                problems.append("area %s: %s names formation $%03x, out of "
                                "range (max $%03x)" % (area_name, where, f, N_FORMS - 1))
                continue
            key = (where, f)
            if key in seen:
                continue
            seen.add(key)
            bodies = data.formation_bodies(f)
            if not bodies:
                problems.append("area %s: %s formation $%03x has an empty "
                                "present mask -- decode drift" % (area_name, where, f))
                continue
            checked += 1
            keys = 0
            ekeys = 0
            gaugeless_only = True
            parts = []
            for sp, n in bodies:
                cls, src, gaugeless = data.species_class(sp)
                elems = data.species_break_elems(sp)
                if not gaugeless:
                    gaugeless_only = False
                    keys |= cls
                    ekeys |= elems
                parts.append("%s($%03x)x%d=%s/%s[%s]"
                             % (data.names[sp], sp, n,
                                class_str(cls) if not gaugeless else "no gauge",
                                elem_str(elems), src))
            if verbose:
                print("    %s formation $%03x: %s -> keys %s elems %s"
                      % (where, f, " ".join(parts), class_str(keys),
                         elem_str(ekeys)))
            if gaugeless_only:
                continue    # nothing in the fight carries a gauge at all
            if keys & fieldable == 0 and ekeys & deliverable == 0:
                problems.append(
                    "area %s / %s / formation $%03x: NO REACHABLE CHIP ON "
                    "EITHER AXIS\n"
                    "    bodies: %s\n"
                    "    formation class keys %s vs party {%s} fielding %s;\n"
                    "    weak elements %s vs party delivering %s"
                    % (area_name, where, f, " ".join(parts),
                       class_str(keys), ",".join(party), class_str(fieldable),
                       elem_str(ekeys), elem_str(deliverable)))

    if checked < area["min_formations"]:
        problems.append(
            "area %s: only %d formations checked, declaration expects >= %d "
            "-- the walk has drifted (map set, group table, or parser)"
            % (area_name, checked, area["min_formations"]))
    return problems, checked


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--repo", default=os.path.dirname(os.path.dirname(
        os.path.abspath(__file__))))
    ap.add_argument("--area", choices=sorted(AREAS), default=None,
                    help="check one area (default: all declared areas)")
    ap.add_argument("--party", default=None,
                    help="comma-separated actor names overriding every step's "
                         "declared party (what-if / failure demo)")
    ap.add_argument("--drop-class", action="append", default=[],
                    choices=sorted(CLASS_BIT),
                    help="pretend no member can field this class (repeatable)")
    ap.add_argument("--drop-elem", action="append", default=[],
                    choices=sorted(ELEM_BIT),
                    help="pretend no member can deliver this element "
                         "(repeatable; failure demo for element-keyed areas)")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()

    party_override = None
    if args.party:
        party_override = [w.strip().upper() for w in args.party.split(",") if w.strip()]
    drop_mask = 0
    for c in args.drop_class:
        drop_mask |= CLASS_BIT[c]
    drop_elem_mask = 0
    for e in args.drop_elem:
        drop_elem_mask |= ELEM_BIT[e]

    data = Data(args.repo)
    names = [args.area] if args.area else sorted(AREAS)
    all_problems = []
    total = 0
    print("break-class encounter/party reachability check")
    for bn in names:
        problems, checked = check_area(data, bn, AREAS[bn], party_override,
                                       drop_mask, drop_elem_mask, args.verbose)
        mode = ""
        if party_override:
            mode += " party-override=%s" % ",".join(party_override)
        if drop_mask:
            mode += " dropped=%s" % class_str(drop_mask)
        if drop_elem_mask:
            mode += " dropped-elems=%s" % elem_str(drop_elem_mask)
        print("  area %-16s: %d formations checked%s" % (bn, checked, mode))
        all_problems.extend(problems)
        total += checked

    if all_problems:
        print("  %d PROBLEM(S):" % len(all_problems))
        print()
        for p in all_problems:
            print("  " + p.replace("\n", "\n  "))
            print()
        return 1
    print("  OK -- every checked formation has a chip the step's party can "
          "reach, by class key or by weak element")
    return 0


if __name__ == "__main__":
    sys.exit(main())
