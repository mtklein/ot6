#!/usr/bin/env python3
"""route_data.py -- decode a route's data from the built ROM and the source.

A planning aid for a new stretch of the route: what the game itself says
about each map and world-map stretch, with no emulator.  Every table is
read from build/ot6.sfc at the address the build's own symbol file
(ff6/rom/ff6-en.dbg) gives it, or from the source .dat the build
compresses, so a number here is the number the ROM ships.

Subcommands (maps are decimal; worlds are 0 = WoB, 1 = WoR):

  map M...              title, random-battle flag, encounter pool and rate,
                        entrances, event triggers, chests, NPCs (source)
  world-entrances W     the world map's town entrances
  world-triggers W      the world map's event triggers
  world-path W X0 Y0 X1 Y1
                        on-foot BFS over the world map; the encounter
                        sectors (group, rate, terrain) the path crosses
  field-path M X0 Y0 X1 Y1 [--avoid X,Y ...]
                        BFS over a field map's BG1 (tile properties,
                        z-levels, diagonals, same-map entrances as edges;
                        NPCs and map-init mod_bg_tiles are not modelled)
  pool field M | pool world W X Y | pool group G | pool event G
                        a pool's slots, odds, formations, species
  species ID...         level, HP, stats, elements, XP/GP, OT6 break row,
                        the attacks its AI script names
  shop N...             a shop's type and stock with prices
  item ID...            an item's equip mask, power, element, class,
                        protections and relic effects
  party STATE.mss [--chars N,...]
                        every party member (and any listed character):
                        gear, spells, commands, what the bag lets them
                        equip, and the bag, read from a Mesen savestate

The table offsets and bit layouts are cited at the code that reads them.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import deque

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))


def path(rel):
    return os.path.join(ROOT, rel)


def rd(rel):
    with open(path(rel), "rb") as f:
        return f.read()


def text_list(name):
    with open(path(f"ff6/src/text/{name}.json"), encoding="utf-8") as f:
        return json.load(f)["text"]


def clean(s):
    return re.sub(r"\{[^}]*\}", "", s).strip()


# ---------------------------------------------------------------- symbols --

WANT = {
    "MonsterProp", "BattleMonsters", "BattleProp", "RandBattleGroup",
    "SubBattleGroup", "SubBattleRate", "WorldBattleGroup", "WorldBattleRate",
    "Ot6ShieldTbl", "Ot6ElemAddTbl", "OT6_FLOOR_CLASS", "Ot6WeapClassTbl",
    "Ot6DangerMulW", "Ot6RewardMulW", "WorldTileProp", "MagicProp", "ItemProp",
    "ShopProp", "AIScriptPtrs", "AIScript", "MapProp", "ShortEntrancePtrs",
    "LongEntrancePtrs", "EventTriggerPtrs", "TreasurePropPtrs",
    "TreasureProp", "EventBattleGroup", "ScrollClipTbl", "RNGTbl",
    "SubBattleRateTbl", "WorldBattleRateTbl", "BattleBGRateTbl",
    "BattleBGGroupTbl",
}


def symbols():
    """(name -> ROM file offset for the labels in WANT, event address ->
    source label), from the build's debug file (only defined labels carry
    val=).  OT6 grows the event bank, so a script's built address is not
    the vanilla address its source label spells (_cc58ff is built at
    $CC5907); the reverse map names a trigger by the label in
    event_main.asm."""
    out, events = {}, {}
    pat = re.compile(r'^sym\t.*name="([^"]+)".*val=0x([0-9A-F]+),seg=\d+,type=lab')
    with open(path("ff6/rom/ff6-en.dbg"), encoding="latin-1") as f:
        for line in f:
            if not line.startswith("sym") or "type=lab" not in line:
                continue
            m = pat.match(line)
            if not m:
                continue
            name, val = m.group(1), int(m.group(2), 16)
            if name in WANT:
                out[name] = val & 0x3FFFFF
            elif re.fullmatch(r"_c[a-c][0-9a-f]{4}", name) and 0xCA0000 <= val < 0xCD0000:
                events.setdefault(val, name)
    missing = WANT - set(out)
    if missing:
        raise SystemExit("route_data: symbols not in ff6-en.dbg: " + ", ".join(sorted(missing)))
    return out, events


ELEMS = ("fire", "ice", "bolt", "poison", "wind", "holy", "earth", "water")
CLASSES = ((0x01, "slash"), (0x02, "pierce"), (0x04, "bludg"), (0x08, "special"))
SLOT_ODDS = (80, 80, 80, 16)          # /256: field/battle.asm draw thresholds $50/$a0/$f0
STATUS = (("Dark", "Zombie", "Poison", "Magitek", "Clear", "Imp", "Petrify", "Death"),
          ("Condemned", "Near Fatal", "Image", "Mute", "Berserk", "Muddle", "Sap", "Sleep"),
          ("Dance", "Regen", "Slow", "Haste", "Stop", "Shell", "Safe", "Reflect"),
          ("Rage", "Frozen", "Reraise", "Morph", "Chant", "Hide", "Interceptor", "Float"))


def statuses(word, bytes_=3):
    out = []
    for k in range(bytes_):
        for bit in range(8):
            if word >> (8 * k + bit) & 1:
                out.append(STATUS[k][bit])
    return "|".join(out) or "-"


def special_text(sp):
    """MonsterProp+31 as battle_main.asm @3300-@3345 reads it: bit 6 set =
    no damage (asl/bpl), bit 7 set = can't be dodged, low 6 bits < $20 a
    status index ($11aa + bit), $20-$2f a damage-multiplier step, $30/$31
    drain HP/MP, $32+ remove Reflect."""
    lo = sp & 0x3F
    if lo < 0x20:
        eff = "inflicts " + STATUS[lo >> 3][lo & 7]
    elif lo < 0x30:
        n = lo - 0x20 + 1           # cmp #$20 leaves carry set: adc adds n+1
        eff = f"+{n} damage-multiplier step{'s' if n > 1 else ''} ($bc; x{1 + n / 2:g})"
    elif lo == 0x30:
        eff = "drains HP"
    elif lo == 0x31:
        eff = "drains MP"
    else:
        eff = "removes Reflect"
    return (("no damage, " if sp & 0x40 else "damage, ") + eff +
            (", can't be dodged" if sp & 0x80 else ""))


def elems(b):
    return "|".join(e for i, e in enumerate(ELEMS) if b >> i & 1) or "-"


def classes(b):
    s = "|".join(n for bit, n in CLASSES if b & bit)
    if b & 0x80:
        s += "+nullbrk"
    return s or "-"


class Data:
    def __init__(self):
        self.rom = rd("build/ot6.sfc")
        self.sym, self.event_labels = symbols()
        self.map_titles = text_list("map_title_en")
        self.mon_names = text_list("monster_name_en")
        self.item_names = [clean(s) for s in text_list("item_name_en")]
        self.magic_names = [clean(s) for s in text_list("magic_name_en")]
        self.genju_attack = [clean(s) for s in text_list("genju_attack_name_en")]
        self.attack_names = [clean(s) for s in text_list("attack_name_en")]
        self.genju_names = [clean(s) for s in text_list("genju_name_en")]
        self.special_names = [clean(s) for s in text_list("monster_special_name_en")]
        self.shield = self._shield_rows()
        self.elemadd = self._elemadd_rows()

    # raw access
    def b(self, o):
        return self.rom[o]

    def w(self, o):
        return self.rom[o] | self.rom[o + 1] << 8

    def at(self, name, off=0):
        return self.sym[name] + off

    # names
    def attack_name(self, a):
        if a < 54:
            return self.magic_names[a]
        if a < 81:
            return self.genju_attack[a - 54]
        return self.attack_names[a - 81] if a - 81 < len(self.attack_names) else f"${a:02X}"

    def map_title(self, m):
        return self.map_titles[self.b(self.at("MapProp", m * 33))]

    # ------------------------------------------------------------ OT6 break
    def _shield_rows(self):
        out, a = {}, self.at("Ot6ShieldTbl")
        while True:
            sp = self.w(a)
            if sp == 0xFFFF:
                break
            out.setdefault(sp, (self.b(a + 2), self.b(a + 3)))
            a += 4
        return out

    def _elemadd_rows(self):
        out, a = {}, self.at("Ot6ElemAddTbl")
        while True:
            sp = self.w(a)
            if sp == 0xFFFF:
                break
            out.setdefault(sp, self.b(a + 2))
            a += 4
        return out

    def break_row(self, sid):
        """(source, shields, class byte) as Ot6SeedShields seeds it
        (ot6_break.asm: authored row first, else floor class and
        2 + level/8 capped at 6)."""
        if sid in self.shield:
            sh, cl = self.shield[sid]
            return "authored", sh, cl
        lvl = self.b(self.at("MonsterProp", sid * 32 + 16))
        sh = min(2 + lvl // 8, 6)
        return "floor", sh, self.b(self.at("OT6_FLOOR_CLASS", sid))

    # ------------------------------------------------------------ monsters
    def species(self, sid):
        o = self.at("MonsterProp", sid * 32)
        r = self.rom[o:o + 32]
        src, sh, cl = self.break_row(sid)
        return {
            "id": sid, "name": self.mon_names[sid] or f"${sid:03X}",
            "level": r[16], "hp": r[8] | r[9] << 8, "mp": r[10] | r[11] << 8,
            # LoadMonsterProp (battle_main.asm @2d0c-@2d5d): +0 speed, +1
            # attack, +3 evade, +4 mblock, +5 def, +6 mdef, +7 magpwr
            "speed": r[0], "atk": r[1], "evade": r[3], "mblock": r[4],
            "def": r[5], "mdef": r[6], "magpwr": r[7],
            "xp": r[12] | r[13] << 8, "gp": r[14] | r[15] << 8,
            "absorb": r[23], "null": r[24], "weak": r[25],
            "elemadd": self.elemadd.get(sid, 0),
            "special": r[31], "status_imm": r[20] | r[21] << 8 | r[22] << 16,
            # LoadMonsterProp (battle_main.asm @2de0-@2e10): +27/+28 status
            # 1/2 set at battle start; +29/+30 status 3/4 with +29 bit 0
            # moved to bit 15 (Float) and $84fe masking the rest
            "status_start": r[27] | r[28] << 8 | (r[29] & 0xFE) << 16 |
                            (r[30] | (0x80 if r[29] & 1 else 0)) << 24,
            "sp_status": r[30], "flags19": r[19],
            "break": (src, sh, cl), "ai": self.ai_attacks(sid),
        }

    AI_LEN = {0xF0: 4, 0xF1: 2, 0xF2: 4, 0xF3: 3, 0xF4: 4, 0xF5: 4, 0xF6: 4,
              0xF7: 2, 0xF8: 3, 0xF9: 4, 0xFA: 4, 0xFB: 3, 0xFC: 4, 0xFD: 1,
              0xFE: 1, 0xFF: 1}

    def ai_attacks(self, sid):
        """attack ids the script can use: plain bytes < $F0 and F0's three
        picks, first (main) and second (counter) sections, in order."""
        base = self.at("AIScript")
        off = self.w(self.at("AIScriptPtrs", sid * 2))
        i, sec, seen = 0, 0, [[], []]
        while sec < 2 and i < 4096:
            op = self.b(base + off + i)
            if op < 0xF0:
                seen[sec].append(op)
                i += 1
                continue
            n = self.AI_LEN[op]
            if op == 0xF0:
                seen[sec].extend(self.rom[base + off + i + 1:base + off + i + 4])
            if op == 0xFF:
                sec += 1
            i += n
        return [[a for a in dict.fromkeys(s) if a != 0xFE] for s in seen]

    def magic(self, a):
        o = self.at("MagicProp", a * 14)
        r = self.rom[o:o + 14]
        return {"elem": r[1], "runic": bool(r[3] & 0x08), "mp": r[5], "power": r[6],
                "status": r[10] | r[11] << 8 | r[12] << 16 | r[13] << 24,
                "remove": bool(r[4] & 0x04), "toggle": bool(r[4] & 0x08),
                "heal": bool(r[4] & 0x01)}

    def formation(self, f):
        o = self.at("BattleMonsters", f * 15)
        r = self.rom[o:o + 15]
        out = []
        for s in range(6):
            if r[1] >> s & 1:
                out.append(r[2 + s] | ((r[14] >> s) & 1) << 8)
        return out

    def event_battle(self, g):
        """EventBattleGroup[g]: the first formation 3/4 of the time, the
        second 1/4 (field/event.asm EventBattle, `cmp #$c0`)."""
        a = self.at("EventBattleGroup", g * 4)
        return [self.w(a) & 0x1FF, self.w(a + 2) & 0x1FF]

    def arrangements(self, f):
        v = (self.w(self.at("BattleProp", f * 4)) ^ 0x00F0) & 0xF0
        return [n for bit, n in ((0x20, "back"), (0x40, "pincer"), (0x80, "side")) if v & bit]

    # ------------------------------------------------------------ pools
    def group_words(self, g):
        return [self.w(self.at("RandBattleGroup", g * 8 + 2 * i)) for i in range(4)]

    def field_group(self, m):
        return self.b(self.at("SubBattleGroup", m))

    def field_rate(self, m):
        return (self.b(self.at("SubBattleRate", m >> 2)) >> ((m & 3) * 2)) & 3

    def world_group(self, world, x, y, bg):
        grp = self.b(self.at("BattleBGGroupTbl", bg))
        idx = world * 256 + (y & 0xE0) + ((x >> 3) & 0x1C) + grp
        g = self.b(self.at("WorldBattleGroup", idx))
        r = self.b(self.at("WorldBattleRate", idx >> 2))
        r = (r >> (2 * self.b(self.at("BattleBGRateTbl", bg)))) & 3
        return idx, g, r

    def rate_step(self, table, r):
        """the per-step danger increment for rate code r (no relic), and the
        OT6 knob Ot6DangerMulW (16ths) applied by Ot6DangerStep."""
        inc = self.w(self.at(table, r * 2))
        mul = self.w(self.at("Ot6DangerMulW")) & 0xFF
        return inc, inc * mul // 16

    @staticmethod
    def mean_steps(inc):
        """expected steps to an encounter: each step adds inc to the 16-bit
        danger counter and a battle starts when a random byte is below its
        high byte (field/battle.asm CheckBattleSub / CheckBattleWorld)."""
        if inc == 0:
            return None
        acc, surv, mean = 0, 1.0, 0.0
        for k in range(1, 4096):
            acc = min(acc + inc, 0xFF00)
            p = (acc >> 8) / 256
            mean += k * surv * p
            surv *= 1 - p
            if surv < 1e-9:
                break
        return mean

    # ------------------------------------------------------------ world map
    def world_tilemap(self, world):
        return rd(f"ff6/src/world/world_{world + 1}_tilemap.dat")

    def world_prop(self, world, tile):
        return self.w(self.at("WorldTileProp", world * 512 + tile * 2))

    # ------------------------------------------------------------ maps
    def ptr_table(self, name, m, rec):
        base = self.at(name)
        a, b = self.w(base + m * 2), self.w(base + m * 2 + 2)
        return [base + o for o in range(a, b, rec)]

    def short_entrances(self, m):
        out = []
        for o in self.ptr_table("ShortEntrancePtrs", m, 6):
            r = self.rom[o:o + 6]
            mw = r[2] | r[3] << 8
            out.append({"x": r[0], "y": r[1], "map": mw & 0x1FF, "flags": r[3],
                        "dx": r[4], "dy": r[5]})
        return out

    def long_entrances(self, m):
        out = []
        for o in self.ptr_table("LongEntrancePtrs", m, 7):
            r = self.rom[o:o + 7]
            mw = r[3] | r[4] << 8
            out.append({"x": r[0], "y": r[1], "len": r[2] & 0x7F,
                        "vertical": bool(r[2] & 0x80), "map": mw & 0x1FF,
                        "flags": r[4], "dx": r[5], "dy": r[6]})
        return out

    def triggers(self, m):
        out = []
        for o in self.ptr_table("EventTriggerPtrs", m, 5):
            r = self.rom[o:o + 5]
            addr = 0xCA0000 + (r[2] | r[3] << 8 | r[4] << 16)
            label = self.event_labels.get(addr, f"${addr:06X} (no source label)")
            out.append({"x": r[0], "y": r[1], "event": label})
        return out

    def chests(self, m):
        base = self.at("TreasurePropPtrs")
        a, b = self.w(base + m * 2), self.w(base + m * 2 + 2)
        out = []
        for o in range(a, b, 5):
            r = self.rom[self.at("TreasureProp") + o:self.at("TreasureProp") + o + 5]
            sw = r[2] | r[3] << 8
            # player.asm @4c06-@4ca9: bit 15 gil, bit 14 item, bit 13 monster
            kind = "gil" if sw & 0x8000 else "item" if sw & 0x4000 else \
                "monster" if sw & 0x2000 else "empty"
            what = (f"{r[4] * 100} GP" if kind == "gil" else
                    self.item_names[r[4]] if kind == "item" else
                    f"event battle group {r[4]} (EventCmd_8e): formations "
                    f"{self.event_battle(r[4])}" if kind == "monster" else f"${r[4]:02X}")
            out.append({"x": r[0], "y": r[1], "bit": sw & 0x1FF, "kind": kind,
                        "what": what})
        return out

    def map_prop(self, m):
        o = self.at("MapProp", m * 33)
        r = self.rom[o:o + 33]
        clip = [self.b(self.at("ScrollClipTbl", i)) for i in range(4)]
        packed = int.from_bytes(r[13:17], "little")
        return {"title": self.map_titles[r[0]], "rolls": bool(r[5] & 0x80),
                "tileprop": r[4], "bg1": packed & 0x3FF,
                "xmask": clip[r[23] >> 6], "ymask": clip[(r[23] >> 4) & 3],
                "warp": bool(r[1] & 0x02)}


# ------------------------------------------------------------------ files --

def enum_files(inc_rel, asm_rel, macro):
    """index -> source .dat for an enum-indexed .incbin table."""
    idx = {}
    for line in open(path(inc_rel)):
        m = re.match(r"\s+([A-Z0-9_]+)\s+;= \$([0-9a-f]+)", line)
        if m:
            idx[m.group(1)] = int(m.group(2), 16)
    out = {}
    for line in open(path(asm_rel)):
        m = re.match(rf"\s+{macro}\s+([A-Z0-9_]+),\s*\"([^\"]+)\"", line)
        if m and m.group(1) in idx:
            out[idx[m.group(1)]] = m.group(2)
    return out


# ------------------------------------------------------------- field BFS --

DIRBIT = {"up": 0x08, "right": 0x01, "down": 0x04, "left": 0x02}
DELTA = {"up": (0, -1), "right": (1, 0), "down": (0, 1), "left": (-1, 0),
         "upright": (1, -1), "downright": (1, 1), "downleft": (-1, 1),
         "upleft": (-1, -1)}
PRESS = {"up": "up", "right": "right", "down": "down", "left": "left",
         "upright": "right", "downright": "right", "downleft": "left",
         "upleft": "left"}


class FieldMap:
    """BG1 of a field map with its tile properties: the model
    tools/tests/lib/ot6_field.lua stepAllowed uses (player.asm), offline."""

    def __init__(self, d: Data, m: int):
        p = d.map_prop(m)
        self.m, self.xm, self.ym = m, p["xmask"], p["ymask"]
        tm = enum_files("ff6/include/field/sub_tilemap.inc",
                        "ff6/src/field/sub_tilemap.asm", "inc_sub_tilemap")
        tp = enum_files("ff6/include/field/map_tile_prop.inc",
                        "ff6/src/field/map_tile_prop.asm", "inc_map_tile_prop")
        self.tilemap_file = f"ff6/src/field/sub_tilemap/{tm[p['bg1']]}.dat"
        self.prop_file = f"ff6/src/field/map_tile_prop/{tp[p['tileprop']]}.dat"
        self.tiles = rd(self.tilemap_file)
        props = rd(self.prop_file)
        self.p1, self.p2 = props[:256], props[256:512]
        self.width = self.xm + 1
        self.links = {(e["x"], e["y"]): (e["dx"], e["dy"])
                      for e in d.short_entrances(m) if e["map"] == m}

    def tile(self, x, y):
        i = (y & self.ym) * self.width + (x & self.xm)
        return self.tiles[i] if i < len(self.tiles) else 0

    def _diag(self, x, y, c, press, z):
        if press not in ("left", "right") or (c & 0xC0) == 0:
            return None
        if (c & 0x04) and z == 0x02:
            return None
        bit = 0x80 if c & 0x80 else 0x40
        mv = ("downright" if press == "right" else "upleft") if bit == 0x80 else \
             ("upright" if press == "right" else "downleft")
        dx, dy = DELTA[mv]
        t = self.p1[self.tile(x + dx, y + dy)]
        if t == 0xF7 or (t & bit) == 0:
            return None
        return mv

    def allowed(self, x, y, move, z):
        c = self.p1[self.tile(x, y)]
        press = PRESS[move]
        diag = self._diag(x, y, c, press, z)
        if move != press:
            return move == diag
        if diag:
            return False
        dx, dy = DELTA[move]
        e = self.p2[self.tile(x, y)]
        t = self.p1[self.tile(x + dx, y + dy)]
        if (e & 0x0F & DIRBIT[move]) == 0:
            return False
        if (t & 0x07) == 0x07:
            return False
        if c & 0x04:
            if z & 0x01:
                if t & 0x02:
                    return False
            elif t & 0x01:
                return False
        elif (t & 0x03) == 0x03:
            pass
        elif (c & 0x03) == 0x03:
            if t & 0x04:
                return False
        elif ((c & 0x03) ^ 0x03) & (t & 0x03):
            return False
        return True

    def z_after(self, x, y, z):
        c = self.p1[self.tile(x, y)]
        return z if (c & 0x07) >= 0x03 else c & 0x03

    def bfs(self, sx, sy, tx, ty, avoid=()):
        """shortest step count (x,y) -> (tx,ty), taking same-map entrances
        as free hops and never stepping on a tile in `avoid` (trigger
        tiles to route around); returns (steps, path of (x,y)) or
        (None, [])."""
        sz = self.p1[self.tile(sx, sy)] & 0x03 or 0x01
        start = (sx, sy, sz)
        prev = {start: None}
        q = deque([start])
        while q:
            x, y, z = q.popleft()
            if (x, y) == (tx, ty):
                out, k = [], (x, y, z)
                while k:
                    out.append(k[:2])
                    k = prev[k]
                out.reverse()
                return len(out) - 1, out
            zn = self.z_after(x, y, z)
            for mv in DELTA:
                if not self.allowed(x, y, mv, z):
                    continue
                nx, ny = x + DELTA[mv][0], y + DELTA[mv][1]
                if (nx, ny) in avoid:
                    continue
                if (nx, ny) in self.links and (nx, ny) != (tx, ty):
                    nx, ny = self.links[(nx, ny)]
                k = (nx, ny, zn)
                if k not in prev:
                    prev[k] = (x, y, z)
                    q.append(k)
        return None, []


# ------------------------------------------------------------- reporting --

def fmt_species(d, sid, indent="    "):
    s = d.species(sid)
    src, sh, cl = s["break"]
    weak = s["weak"] | s["elemadd"]
    add = f" (+{elems(s['elemadd'])} OT6 add)" if s["elemadd"] else ""
    lines = [f"{indent}${sid:03X} {s['name']}: L{s['level']} HP {s['hp']} MP {s['mp']} "
             f"XP {s['xp']} GP {s['gp']}; spd {s['speed']} atk {s['atk']} mag {s['magpwr']} "
             f"def {s['def']} mdef {s['mdef']} evade {s['evade']} mblock {s['mblock']}; "
             f"weak {elems(weak)}{add} absorb "
             f"{elems(s['absorb'])} null {elems(s['null'])}; break {src} {sh} * "
             f"{classes(cl)}"]
    for tag, atk in zip(("script", "counter"), s["ai"]):
        if atk:
            parts = []
            for a in atk:
                mg = d.magic(a)
                el = elems(mg["elem"]) if mg["elem"] else ""
                st = ("swaps statuses" if mg["toggle"] else "removes status" if mg["remove"]
                      else statuses(mg["status"], 4)) if mg["status"] else ""
                parts.append(d.attack_name(a) + (f"[{el}]" if el else "") +
                             (f"{{{st}}}" if st else "") +
                             (f"<pow {mg['power']}>" if mg["power"] else "") +
                             ("(runic)" if mg["runic"] else ""))
            lines.append(f"{indent}  {tag}: " + ", ".join(parts))
    sp = s["special"]
    lines.append(f"{indent}  special {d.special_names[sid]!r} (MonsterProp+31 = ${sp:02X}: "
                 f"{special_text(sp)}); immune {statuses(s['status_imm'])}; starts with "
                 f"{statuses(s['status_start'], 4)}")
    return lines


def fmt_pool(d, words, indent="  ", species_seen=None, odds=SLOT_ODDS):
    out = []
    for i, word in enumerate(words):
        base = word & 0x1FF
        forms = [base + k for k in range(4)] if word & 0x8000 else [base]
        tag = " (+rand 0..3: each 1/4)" if word & 0x8000 else ""
        out.append(f"{indent}slot {i}: {odds[i]}/256 word ${word:04X}{tag}")
        for f in forms:
            sps = d.formation(f)
            counts = {}
            for s in sps:
                counts[s] = counts.get(s, 0) + 1
            body = ", ".join(f"{d.mon_names[s] or hex(s)} ${s:03X} x{n}" for s, n in counts.items())
            xp = sum(d.species(s)["xp"] for s in sps)
            arr = d.arrangements(f)
            out.append(f"{indent}  formation {f}: {body}; XP {xp} (x2 as a random, "
                       f"Ot6RewardMulW); may roll {'/'.join(arr) or 'normal only'}")
            if species_seen is not None:
                species_seen.update(sps)
    return out


def cmd_map(d, args):
    npcs = parse_npcs()
    for m in args.maps:
        p = d.map_prop(m)
        print(f"map {m} {p['title']!r}: random battles {'ON' if p['rolls'] else 'off'}"
              f"; warp {'on' if p['warp'] else 'off'}")
        if p["rolls"]:
            g, r = d.field_group(m), d.field_rate(m)
            inc, eff = d.rate_step("SubBattleRateTbl", r)
            ms = d.mean_steps(eff)
            print(f"  pool: SubBattleGroup[{m}] = group {g}; SubBattleRate code {r} "
                  f"(${inc:04X}/step, x Ot6DangerMulW -> ${eff:04X}; mean "
                  f"{ms:.1f} steps to a battle)")
            seen = set()
            for line in fmt_pool(d, d.group_words(g), "   ", seen):
                print(line)
        for e in d.short_entrances(m):
            print(f"  short ({e['x']},{e['y']}) -> map {e['map']} ({e['dx']},{e['dy']}) flags ${e['flags']:02X}")
        for e in d.long_entrances(m):
            print(f"  long ({e['x']},{e['y']}) len {e['len']}{' vertical' if e['vertical'] else ''}"
                  f" -> map {e['map']} ({e['dx']},{e['dy']}) flags ${e['flags']:02X}")
        for t in d.triggers(m):
            print(f"  trigger ({t['x']},{t['y']}) -> {t['event']}")
        for c in d.chests(m):
            print(f"  chest ({c['x']},{c['y']}) bit ${c['bit']:03X} {c['kind']}: {c['what']}")
        for n in npcs.get(m, []):
            print(f"  npc {n}")


def parse_npcs():
    """map -> NPC summaries from ff6/src/event/npc_prop.asm (source order
    is object order: NPC_1 is the first make_npc)."""
    out, cur, idx, rec = {}, None, 0, None
    lines = open(path("ff6/src/event/npc_prop.asm")).read().splitlines()
    for ln, line in enumerate(lines, 1):
        m = re.match(r"NPCProp::_(\d+):", line)
        if m:
            cur, idx = int(m.group(1)), 0
            out[cur] = []
            continue
        m = re.match(r"\s+make_npc \{(\d+), (\d+)\}, \$([0-9a-f]+)", line)
        if m and cur is not None:
            idx += 1
            rec = {"n": idx, "xy": (int(m.group(1)), int(m.group(2))),
                   "switch": m.group(3), "line": ln, "event": None, "gfx": ""}
            continue
        if rec is not None:
            m = re.match(r"\s+set_npc_event (\S+)", line)
            if m:
                rec["event"] = m.group(1)
            m = re.match(r"\s+set_npc_gfx (.+)", line)
            if m:
                rec["gfx"] = m.group(1).strip()
            if line.strip() == "end_npc":
                out[cur].append(f"NPC_{rec['n']} at {rec['xy']} show-switch ${rec['switch']} "
                                f"gfx {rec['gfx']} event {rec['event']} "
                                f"(npc_prop.asm:{rec['line']})")
                rec = None
    return out


def cmd_world_entrances(d, args):
    m = args.world
    for e in d.short_entrances(m):
        print(f"world {m} ({e['x']},{e['y']}) -> map {e['map']} {d.map_title(e['map'])!r} "
              f"({e['dx']},{e['dy']}) flags ${e['flags']:02X}")


def cmd_world_triggers(d, args):
    for t in d.triggers(args.world):
        print(f"world {args.world} trigger ({t['x']},{t['y']}) -> {t['event']}")


def world_bfs(d, world, sx, sy, tx, ty):
    tm = d.world_tilemap(world)
    props = [d.world_prop(world, t) for t in range(256)]

    def passable(x, y):
        return (props[tm[(y & 0xFF) * 256 + (x & 0xFF)]] & 0x10) == 0
    prev = {(sx, sy): None}
    q = deque([(sx, sy)])
    while q:
        x, y = q.popleft()
        if (x, y) == (tx, ty):
            out, k = [], (x, y)
            while k:
                out.append(k)
                k = prev[k]
            return out[::-1], tm, props
        for dx, dy in ((0, -1), (1, 0), (0, 1), (-1, 0)):
            nx, ny = (x + dx) & 0xFF, (y + dy) & 0xFF
            if (nx, ny) not in prev and passable(nx, ny):
                prev[(nx, ny)] = (x, y)
                q.append((nx, ny))
    return None, tm, props


def cmd_world_path(d, args):
    w = args.world
    route, tm, props = world_bfs(d, w, args.x0, args.y0, args.x1, args.y1)
    if route is None:
        print(f"world {w}: no on-foot path ({args.x0},{args.y0}) -> ({args.x1},{args.y1})")
        return
    print(f"world {w}: on-foot BFS ({args.x0},{args.y0}) -> ({args.x1},{args.y1}): "
          f"{len(route) - 1} steps (world_{w + 1}_tilemap.dat, WorldTileProp bit $10)")
    tally, battle_steps = {}, 0
    for (x, y) in route[1:]:
        pr = props[tm[y * 256 + x]]
        if not pr & 0x40:
            key = ("no battles", None, None, None)
        else:
            bg = (pr >> 8) & 7
            idx, g, r = d.world_group(w, x, y, bg)
            key = (f"sector ({x >> 5},{y >> 5}) bg {bg}", idx, g, r)
            battle_steps += 1
        tally[key] = tally.get(key, 0) + 1
    for (label, idx, g, r), n in tally.items():
        if idx is None:
            print(f"  {n} steps: {label}")
            continue
        if r == 3:
            print(f"  {n} steps: {label}: WorldBattleGroup[{idx}] = {g}, rate code 3 (none)")
            continue
        inc, eff = d.rate_step("WorldBattleRateTbl", r)
        print(f"  {n} steps: {label}: WorldBattleGroup[{idx}] = group {g}; rate code {r} "
              f"(${inc:04X}/step x Ot6DangerMulW -> ${eff:04X}; mean {d.mean_steps(eff):.1f} steps)")
    print("  path: " + " ".join(f"{x},{y}" for x, y in route))


def cmd_field_path(d, args):
    fm = FieldMap(d, args.map)
    avoid = {tuple(int(v) for v in a.split(",")) for a in args.avoid}
    steps, route = fm.bfs(args.x0, args.y0, args.x1, args.y1, avoid)
    print(f"map {args.map}: BFS ({args.x0},{args.y0}) -> ({args.x1},{args.y1}) over "
          f"{fm.tilemap_file} + {fm.prop_file} (mask {fm.xm:#x}x{fm.ym:#x}; "
          f"same-map links {sorted(fm.links.items())}"
          + (f"; avoiding {sorted(avoid)}" if avoid else "") + "): "
          + (f"{steps} steps" if steps is not None else "NO PATH (NPCs not modelled)"))
    if route:
        print("  path: " + " ".join(f"{x},{y}" for x, y in route))


def cmd_pool(d, args):
    if args.kind == "field":
        m = args.a
        print(f"map {m}: group {d.field_group(m)}, rate code {d.field_rate(m)}")
        words = d.group_words(d.field_group(m))
    elif args.kind == "group":
        words = d.group_words(args.a)
    elif args.kind == "event":
        f1, f2 = d.event_battle(args.a)
        print(f"event battle group {args.a}: formation {f1} (192/256), {f2} (64/256)")
        words = [f1, f2]
        seen = set()
        for line in fmt_pool(d, words, "  ", seen, odds=(192, 64)):
            print(line)
        for sid in sorted(seen):
            for line in fmt_species(d, sid):
                print(line)
        return
    else:
        tm = d.world_tilemap(args.a)
        pr = d.world_prop(args.a, tm[args.c * 256 + args.b])
        bg = (pr >> 8) & 7
        idx, g, r = d.world_group(args.a, args.b, args.c, bg)
        print(f"world {args.a} ({args.b},{args.c}): tile prop ${pr:04X} battles "
              f"{'on' if pr & 0x40 else 'off'} bg {bg}; WorldBattleGroup[{idx}] = {g}; rate {r}")
        words = d.group_words(g)
    seen = set()
    for line in fmt_pool(d, words, "  ", seen):
        print(line)
    for s in sorted(seen):
        for line in fmt_species(d, s):
            print(line)


def cmd_species(d, args):
    for s in args.ids:
        for line in fmt_species(d, s, ""):
            print(line)


def cmd_shop(d, args):
    for n in args.shops:
        o = d.at("ShopProp", n * 9)
        r = d.rom[o:o + 9]
        kind = ("?", "weapon", "armor", "item", "relic", "vendor")[r[0] & 7] \
            if (r[0] & 7) < 6 else "?"
        adj = (r[0] >> 3) & 7
        print(f"shop {n} (ShopProp+{n * 9}): {kind}, price adjustment code {adj}")
        for it in r[1:]:
            if it == 0xFF:
                continue
            price = d.w(d.at("ItemProp", it * 30 + 28))
            print(f"  ${it:02X} {d.item_names[it]}: {price} GP")


RELIC_BITS = {  # ItemProp +9..+13 -> $11D5..$11D9 (battle_main.asm @0fb9 tsb chain)
    9: ("fight dmg+", "magic dmg+", "HP+25%", "HP+50%", "HP+12.5%", "MP+25%", "MP+50%", "MP+12.5%"),
    10: ("preemptive+", "no back/pincer", "fight->jump", "magic->x-magic", "sketch->control",
         "slot->gp rain", "steal->capture", "jump continuously"),
    11: ("steal rate+", "magic dmg+ (1 earring)", "sketch rate+", "control rate+",
         "100% hit, ignore mblock", "MP cost 50%", "MP cost 1", "vigor+50%"),
    12: ("fight->x-fight", "random counter", "random evade", "2-handed", "2 weapons",
         "heavy items", "protect weak allies", "?"),
    13: ("shell at low HP", "safe at low HP", "wall at low HP", "double XP", "double GP",
         "?", "?", "undead"),
}
WEAPON_BITS = ("?", "swdtech", "?", "?", "?", "no row penalty", "2-hand", "runic")


def cmd_item(d, args):
    kinds = ("tool", "weapon", "armor", "shield", "helmet", "relic", "item", "?")
    names = ("TERRA", "LOCKE", "CYAN", "SHADOW", "EDGAR", "SABIN", "CELES", "STRAGO",
             "RELM", "SETZER", "MOG", "GAU", "GOGO", "UMARO")
    for it in args.ids:
        o = d.at("ItemProp", it * 30)
        r = d.rom[o:o + 30]
        mask = r[1] | r[2] << 8
        who = ",".join(n for i, n in enumerate(names) if mask >> i & 1) or "-"
        t = r[0] & 7
        out = [f"${it:02X} {d.item_names[it]}: {kinds[t]}; equip {who}; price "
               f"{d.w(o + 28)} GP (ItemProp+{it * 30})"]
        if t == 1:
            wp = [WEAPON_BITS[b] for b in range(8) if r[19] >> b & 1 and WEAPON_BITS[b] != "?"]
            out.append(f"  pow {r[20]} hit {r[21]} element {elems(r[15])} class "
                       f"{classes(d.b(d.at('Ot6WeapClassTbl', it)))}; props {','.join(wp) or '-'}"
                       + (f"; spell {d.attack_name(r[18] & 0x3F)} (ItemProp+18 = ${r[18]:02X})"
                          if r[18] else ""))
        elif t in (2, 3, 4, 5):
            out.append(f"  def {r[20]} mdef {r[21]}; halves {elems(r[15])}; "
                       f"absorbs {elems(r[22])} nulls {elems(r[23])} weak {elems(r[24])}")
        prot = r[6] | r[7] << 8
        if prot:
            out.append(f"  protects from {statuses(prot, 2)} (ItemProp+6/+7)")
        if r[8]:
            out.append(f"  grants {statuses(r[8] << 16, 3)} (ItemProp+8)")
        rel = [RELIC_BITS[k][b] for k in RELIC_BITS for b in range(8) if r[k] >> b & 1]
        if rel:
            out.append("  relic effects: " + ", ".join(rel))
        if r[5]:
            fe = [n for b, n in ((0, "charm bangle"), (1, "moogle charm"), (5, "sprint shoes"),
                                 (7, "tintinabar")) if r[5] >> b & 1]
            out.append("  field: " + ", ".join(fe))
        print("\n".join(out))


def cmd_party(d, args):
    import savestate_party as sp
    raw = sp.biggest_stream(args.state)
    cb = sp.find_char_block(raw)
    if cb is None:
        raise SystemExit("party: character table not found")
    base = cb - 0x1600

    def rb(a):
        return raw[base + a]

    def rw(a):
        return raw[base + a] | raw[base + a + 1] << 8
    cmds = text_list("battle_cmd_name_en")
    print(f"{args.state}: map ${rw(0x0082) & 0x1FF:03X} ({rw(0x0082) & 0x1FF}), "
          f"gil {rw(0x1860) | rb(0x1862) << 16}, steps {rw(0x1866) | rb(0x1868) << 16}")
    extra = {int(x) for x in args.chars.split(",")} if args.chars else set()
    for c in range(16):
        pb = rb(0x1850 + c)
        if not pb & 0x07 and c not in extra:
            continue
        rec = 0x1600 + 37 * c
        lvl, hp = rb(rec + 8), rw(rec + 9)
        mhp = sp.calc_max(rw(rec + 11), 9999)
        mp, mmp = rw(rec + 13), sp.calc_max(rw(rec + 15), 999)
        name = sp.NAMES.get(c, f"#{c}")
        gear = [rb(rec + 0x1F + i) for i in range(6)]
        gtxt = ", ".join(d.item_names[g] if g != 0xFF else "-" for g in gear)
        wcls = classes(d.b(d.at("Ot6WeapClassTbl", gear[0])))
        esper = rb(rec + 0x1E)
        cm = [cmds[rb(rec + 0x16 + i)] if rb(rec + 0x16 + i) < len(cmds) else "-"
              for i in range(4)]
        print(f"  {name}: L{lvl} HP {hp}/{mhp} MP {mp}/{mmp} XP {rw(rec + 0x11) | rb(rec + 0x13) << 16}"
              f" party byte ${pb:02X}")
        print(f"    vigor {rb(rec + 0x1A)} speed {rb(rec + 0x1B)} stamina {rb(rec + 0x1C)} "
              f"magpwr {rb(rec + 0x1D)}; commands {', '.join(clean(x) for x in cm)}")
        print(f"    gear: {gtxt}; weapon class {wcls}; esper "
              f"{d.genju_names[esper] if esper < len(d.genju_names) else '-'}")
        if c < 12:
            known = [d.magic_names[s] for s in range(54) if rb(0x1A6E + c * 54 + s) == 0xFF]
            print(f"    spells ({len(known)}): {', '.join(known)}")
        # what this character can put on from the bag: ItemProp +0 type
        # (low 3 bits: 1 weapon 2 armor 3 shield 4 helmet 5 relic), +1 word
        # equippable-character mask, +15 element, +20 battle/defense power,
        # +21 magic defense (armor), +18 spell cast (weapon)
        kinds = {1: "weapon", 2: "armor", 3: "shield", 4: "helmet", 5: "relic"}
        opts = {k: [] for k in kinds.values()}
        for i in range(256):
            it, n = rb(0x1869 + i), rb(0x1969 + i)
            if it == 0xFF or not n:
                continue
            o = d.at("ItemProp", it * 30)
            r = d.rom[o:o + 30]
            t = r[0] & 7
            if t not in kinds or not ((r[1] | r[2] << 8) >> c) & 1:
                continue
            if t == 1:
                cl = classes(d.b(d.at("Ot6WeapClassTbl", it)))
                el = f" {elems(r[15])}" if r[15] else ""
                opts["weapon"].append(f"{d.item_names[it]} (pow {r[20]}, {cl}{el})")
            elif t == 5:
                opts["relic"].append(d.item_names[it])
            else:
                opts[kinds[t]].append(f"{d.item_names[it]} (def {r[20]}/mdef {r[21]})")
        for k, v in opts.items():
            if v:
                print(f"    can equip {k}: " + "; ".join(v))
    bag = []
    for i in range(256):
        it, n = rb(0x1869 + i), rb(0x1969 + i)
        if it != 0xFF and n:
            bag.append(f"{d.item_names[it]} x{n}")
    print(f"  bag ({len(bag)} rows): " + "; ".join(bag))
    espers = [d.genju_names[i] for i in range(27) if rb(0x1A69 + i // 8) >> (i % 8) & 1]
    print(f"  espers held: {', '.join(espers)}")


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("map"); p.add_argument("maps", type=int, nargs="+")
    p = sub.add_parser("world-entrances"); p.add_argument("world", type=int)
    p = sub.add_parser("world-triggers"); p.add_argument("world", type=int)
    p = sub.add_parser("world-path")
    for a in ("world", "x0", "y0", "x1", "y1"):
        p.add_argument(a, type=int)
    p = sub.add_parser("field-path")
    for a in ("map", "x0", "y0", "x1", "y1"):
        p.add_argument(a, type=int)
    p.add_argument("--avoid", nargs="*", default=[], metavar="X,Y",
                   help="tiles the route must not step on (e.g. a trigger)")
    p = sub.add_parser("pool"); p.add_argument("kind", choices=("field", "world", "group", "event"))
    p.add_argument("a", type=int); p.add_argument("b", type=int, nargs="?")
    p.add_argument("c", type=int, nargs="?")
    p = sub.add_parser("species"); p.add_argument("ids", type=lambda s: int(s, 0), nargs="+")
    p = sub.add_parser("shop"); p.add_argument("shops", type=int, nargs="+")
    p = sub.add_parser("party"); p.add_argument("state")
    p.add_argument("--chars", help="also report these character indices (e.g. 5 for SABIN)")
    p = sub.add_parser("item"); p.add_argument("ids", type=lambda s: int(s, 0), nargs="+")
    args = ap.parse_args()
    d = Data()
    {"map": cmd_map, "world-entrances": cmd_world_entrances,
     "world-triggers": cmd_world_triggers, "world-path": cmd_world_path,
     "field-path": cmd_field_path, "pool": cmd_pool, "species": cmd_species,
     "shop": cmd_shop, "party": cmd_party, "item": cmd_item}[args.cmd](d, args)


if __name__ == "__main__":
    main()
