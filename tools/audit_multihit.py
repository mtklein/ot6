#!/usr/bin/env python3
"""Multi-hit audit: how many times each ability strikes (#54)

Phase 1 of docs/design/multi-hit.md.  Hit count sets break rate, because each
landed hit that matches a weakness chips a shield, so the design pass needs
the shipped numbers rather than the ones the kit docs assert.  This script
reads them out.

Hit counts are set by code, not by a data field.  The engine has one
multi-hit register: `$3a70`, "number of attacks (0 = 1 attack)"
(battle_main.asm:6404).  The attack loop is

    @3288:  plx
            dec  $3a70
            bmi  @3291
            pea  ExecAttack-1        ; battle_main.asm:8322-8328
    @3291:  rts

so every extra count is an extra ExecAttack -> CalcTargetDmg pass, and
therefore an extra chip opportunity.  Grepping the tree for every write to
$3a70 is therefore an exhaustive enumeration of single-target multi-hit, and
there are only six writers (this script re-checks that the set has not
grown, so the audit cannot go stale unnoticed):

    battle_main.asm:3495   FightAttack        = 1 (two hands), = 7 (Offering)
    ot6_boost.asm:247      Ot6FightBoost     += 2 per pending BP
    battle_main.asm:3943+  Jump/Dragon Horn  += 1..3 (random)
    battle_main.asm:8870   CheckWeaponMagic  += 1 (random weapon spellcast)
    battle_main.asm:10547  AttackerEffect_49 += 1 (magicite / random summon)
    battle_main.asm:10784  AttackerEffect_32  = 3  -> four attacks, random
                                                     target (quadra slam,
                                                     quadra slice)
    battle_main.asm:10987  AttackerEffect_36 += 1 (empowerer, at 1/4 power)

Targets are not hits.  An ability that strikes the whole enemy side lands one
hit on each body: four chips spread over four monsters, and one against a
boss.  That is a different lever from four hits on one target, so the audit
keeps them in separate columns.  Breadth comes from the
targeting byte's INIT field (const.inc:1298-1302): INIT_SINGLE ($00)
collapses the mask to one random body (ChooseTarget's `bit #$0c` /
RandBit, battle_main.asm:14879-14889), anything else keeps every target in
the mask.

Sources
  MagicProp   ff6/src/battle/magic_prop_en.dat, 14 B/record, id-indexed:
              +0 targeting  +1 element  +2..4 flags  +5 MP  +6 power
              +7 flags  +8 hit  +9 special effect  +10..13 status
              (layout: battle_main.asm:6961-6963)
  ItemProp    ff6/src/menu/item_prop_en.dat, 30 B/record:
              +14 targeting (battle_main.asm:6572), +15 element,
              +20 power, +27 special effect (battle_main.asm:7196-7202)
  classes     Ot6SkillClassTbl / Ot6WeapClassTbl (ot6_class.asm), reused
              from tools/check_break_reach.py so there is one parser

Read-only.  Exit 0 = the $3a70 writer set is what this header says; nonzero
means the enumeration above is stale and the audit must be redone.

Usage:  python3 tools/audit_multihit.py [--repo ROOT]
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import re
import sys

MAGIC_PROP = "ff6/src/battle/magic_prop_en.dat"
ITEM_PROP = "ff6/src/menu/item_prop_en.dat"
ATTACK_NAMES = "ff6/src/text/attack_name_en.json"
BUSHIDO_NAMES = "ff6/src/text/bushido_name_en.json"
ITEM_NAMES = "ff6/src/text/item_name_en.json"
MAGIC_NAMES = "ff6/src/text/magic_name_en.json"

MAGIC_REC, ITEM_REC = 14, 30

# AttackName index 0 is attack id $51 (index 12 = $5d = "Pummel" is the
# anchor; Ot6SkillClassTbl:$5d and kits.md agree).
ATTACK_NAME_BASE = 0x51

# special-effect ids that add attacks (see the header enumeration)
HIT_EFFECTS = {0x32: "quadra (=3, four attacks, random target)",
               0x36: "empowerer (+1, quarter power)",
               0x49: "magicite (+1)"}

INIT = {0x00: "single", 0x04: "all-bodies", 0x08: "one-side", 0x0c: "one-half"}

ELEMENTS = ["fire", "ice", "bolt", "poison", "wind", "holy", "earth", "water"]

# the exhaustive $3a70 writer set this audit's conclusions rest on
EXPECTED_WRITERS = {
    ("ff6/src/battle/battle_main.asm", "sta"): 3,   # 3495, 10784, + the stz
    ("ff6/src/battle/battle_main.asm", "inc"): 5,   # 3943,3946,3949,8870,10547,10987 -> see below
}


def class_names(mask):
    if mask is None:
        return "-"
    if mask & 0x80:
        return "null-break"
    bits = [n for n, b in (("slash", 1), ("pierce", 2), ("bludg", 4),
                           ("special", 8)) if mask & b]
    return "|".join(bits) if bits else "-"


def elem_names(b):
    if not b:
        return "-"
    return "|".join(ELEMENTS[i] for i in range(8) if b & (1 << i))


def target_desc(t):
    if t == 0xFF:
        return "menu"
    parts = [INIT[t & 0x0C]]
    if t & 0x02:
        parts.append("one-side-only")
    if t & 0x20:
        parts.append("L/R-multi")
    if t & 0x40:
        parts.append("enemy-default")
    return ",".join(parts)


def parse_costs(root):
    """Ot6AbilityCostTbl (ot6_boost.asm): (key, cost) pairs, $ff-terminated.

    Keyed by attack id for Blitz/SwdTech and by tool item id for Tools, the
    same keying ot6_class.asm uses, so a tool and a blitz can share a
    number without colliding here (the ranges are disjoint: $55-$64 vs
    $a3-$aa).
    """
    path = os.path.join(root, "ff6/src/battle/ot6_boost.asm")
    with open(path, encoding="utf-8") as f:
        src = f.read().splitlines()
    start = next(i for i, l in enumerate(src)
                 if l.strip().startswith("Ot6AbilityCostTbl:"))
    out = {}
    for i in range(start + 1, len(src)):
        code = src[i].split(";", 1)[0].strip()
        if not code:
            continue
        if re.fullmatch(r"\.byte\s+\$ff", code):
            break
        m = re.match(r"\.byte\s+\$([0-9a-fA-F]{2})\s*,\s*(\d+)$", code)
        if m:
            out[int(m.group(1), 16)] = int(m.group(2))
    if len(out) < 20:
        raise SystemExit("audit_multihit: Ot6AbilityCostTbl parsed %d rows, "
                         "want >= 20 -- parser drift" % len(out))
    return out


def load_reach(root):
    """Reuse check_break_reach's table parsers, so there is only one parser."""
    path = os.path.join(root, "tools", "check_break_reach.py")
    spec = importlib.util.spec_from_file_location("check_break_reach", path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules["check_break_reach"] = mod
    spec.loader.exec_module(mod)
    return mod


def read(root, rel):
    with open(os.path.join(root, rel), "rb") as f:
        return f.read()


def names(root, rel):
    with open(os.path.join(root, rel), encoding="utf-8") as f:
        return json.load(f)["text"]


def check_writers(root):
    """Re-derive the $3a70 writer set and fail if it has changed."""
    hits = []
    for dirpath, _dirs, files in os.walk(os.path.join(root, "ff6", "src")):
        for fn in files:
            if not fn.endswith((".asm", ".inc")):
                continue
            p = os.path.join(dirpath, fn)
            with open(p, encoding="utf-8", errors="replace") as f:
                for i, line in enumerate(f, 1):
                    code = line.split(";", 1)[0]
                    m = re.search(r"\b(sta|inc|dec|stz|adc)\s+\$3a70\b", code)
                    if m:
                        hits.append((os.path.relpath(p, root), i, m.group(1),
                                     line.strip()))
    writes = [h for h in hits if h[2] in ("sta", "inc", "stz", "adc")]
    print("== $3a70 writers (the exhaustive multi-hit enumeration) ==")
    for rel, ln, op, text in sorted(writes):
        print("  %-40s:%-6d %s" % (rel, ln, text))
    # 3 sta/stz + 6 inc + 1 adc = the set the header documents; a change
    # here means a new multi-hit source exists and the doc must be redone.
    n_up = len([h for h in writes if h[2] in ("sta", "inc", "adc")])
    print("  -> %d upward writers (header documents 10: FightAttack sta, "
          "Ot6FightBoost adc+sta, 3x jump inc, weapon-spellcast inc, "
          "magicite inc, quadra sta, empowerer inc)" % n_up)
    return n_up


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=os.path.dirname(
        os.path.dirname(os.path.abspath(__file__))))
    args = ap.parse_args()
    root = args.repo

    n_up = check_writers(root)

    reach = load_reach(root)
    data = reach.Data(root)
    mp = read(root, MAGIC_PROP)
    ip = data.items
    anames = names(root, ATTACK_NAMES)
    bnames = names(root, BUSHIDO_NAMES)
    inames = names(root, ITEM_NAMES)
    mnames = names(root, MAGIC_NAMES)

    costs = parse_costs(root)

    def magic_name(i):
        if 0x55 <= i <= 0x5C:                   # SwdTech renders from
            n = bnames[i - 0x55].strip()        # BushidoName; AttackName's
            if n:                               # $55-$5c slots are empty pad
                return n
        if i < len(mnames):
            n = mnames[i].strip()
            if n:
                return n
        j = i - ATTACK_NAME_BASE
        if 0 <= j < len(anames) and anames[j].strip():
            return anames[j].strip()
        return "$%02x" % i

    def rec(i):
        return mp[i * MAGIC_REC:(i + 1) * MAGIC_REC]

    # ---- 1. exhaustive scan: every record carrying a hit-adding effect ----
    print()
    print("== every MagicProp record whose special effect adds an attack ==")
    found = []
    for i in range(256):
        r = rec(i)
        eff = r[9]
        if eff in HIT_EFFECTS:
            found.append((i, eff))
            print("  $%02x %-12s effect $%02x  %s" %
                  (i, magic_name(i), eff, HIT_EFFECTS[eff]))
    if not found:
        print("  (none -- parser drift?)")
    print()
    print("== every ItemProp record whose special effect adds an attack ==")
    for i in range(256):
        r = ip[i * ITEM_REC:(i + 1) * ITEM_REC]
        eff = r[27]
        if eff in HIT_EFFECTS:
            print("  item $%02x %-12s effect $%02x  %s" %
                  (i, inames[i].strip() if i < len(inames) else "?", eff,
                   HIT_EFFECTS[eff]))

    # ---- 2. the kit tables -----------------------------------------------
    def line(label, idx, hits, targ, elem, cls, pow_, eff, mp):
        cpc = ("%5.1f" % (mp / hits)) if mp else "    -"
        print("  %-12s $%02x | hits %d | tgt $%02x %-22s | elem %-6s | "
              "class %-12s | pow %3d | eff %-3s | mp %3s | mp/chip %s" %
              (label, idx, hits, targ, target_desc(targ), elem, cls, pow_,
               ("$%02x" % eff) if eff != 0xFF else "-",
               str(mp) if mp else "-", cpc))

    def row(i, label):
        r = rec(i)
        eff = r[9]
        hits = 4 if eff == 0x32 else (2 if eff == 0x36 else 1)
        line(label, i, hits, r[0], elem_names(r[1]),
             class_names(data.skill_class.get(i)), r[6], eff, costs.get(i, 0))

    print()
    print("== SwdTech (magic ids $55-$5c; names from BushidoName) ==")
    for n, i in enumerate(range(0x55, 0x5D)):
        row(i, bnames[n].strip() if n < len(bnames) else "$%02x" % i)

    print()
    print("== Blitz (magic ids $5d-$64) ==")
    for i in range(0x5D, 0x65):
        row(i, magic_name(i))

    print()
    print("== Tools (item ids $a3-$aa; ItemProp) ==")
    for i in range(0xA3, 0xAB):
        r = ip[i * ITEM_REC:(i + 1) * ITEM_REC]
        eff = r[27]
        nm = (inames[i].strip() if i < len(inames) else "?").replace("{tool}", "")
        line(nm, i, 4 if eff == 0x32 else (2 if eff == 0x36 else 1),
             r[14], elem_names(r[15]), class_names(data.weap_class[i]),
             r[20], eff, costs.get(i, 0))

    # ---- 2b. the tools that resolve as spells ----------------------------
    # InitTarget_03 (battle_main.asm:6551-6558) rewrites five item ids into
    # magic ids before the record is loaded, so their real properties are in
    # MagicProp rather than ItemProp.  That includes Bio Blaster, the ability
    # #60 is about.
    print()
    print("== tools/throwables that resolve as a SPELL "
          "(ThrowToolsItemTbl, battle_main.asm:6635-6642) ==")
    for item, off in ((0xA4, 0x27), (0xA5, 0x27), (0xAB, 0x5A),
                      (0xAC, 0x5A), (0xAD, 0x5A)):
        sid = item - off
        r = rec(sid)
        st = (r[10], r[11], r[12], r[13])
        print("  item $%02x %-12s -> spell $%02x %-12s | hits %d | tgt $%02x "
              "%-22s | elem %-6s | pow %3d | status %02x/%02x/%02x/%02x" %
              (item, (inames[item].strip() if item < len(inames) else "?")
               .replace("{tool}", ""), sid, magic_name(sid),
               4 if r[9] == 0x32 else (2 if r[9] == 0x36 else 1),
               r[0], target_desc(r[0]), elem_names(r[1]), r[6], *st))

    # ---- 3. per-character: ability classes vs equippable weapon classes ---
    print()
    print("== per character: what the WEAPON reaches vs what the ABILITY "
          "reaches ==")
    print("  (weapon set = every class this actor can equip AND swing; "
          "ability set = classes their command abilities carry)")
    print("  CAVEAT, and it is why 'ability-only' is almost always empty: the "
          "weapon set is GAME-WIDE equippability, so it answers 'could this")
    print("  character ever reach that class', not 'can they reach it with "
          "what they are holding'.  #54's reach axis is the second question,")
    print("  and it needs the EQUIPPED hand, which is runtime state -- see "
          "docs/design/multi-hit.md SS4.")
    for who in reach.ACTORS:
        cmds = data.commands[who]
        wmask = 0
        if reach.SWING_COMMAND in cmds or who in reach.AUTO_SWINGERS:
            for it in range(256):
                r = ip[it * ITEM_REC:(it + 1) * ITEM_REC]
                if r[0] & 0x07 != 1:
                    continue
                if not (int.from_bytes(r[1:3], "little") >> reach.ACTOR_ID[who]) & 1:
                    continue
                c = data.weap_class[it]
                if c & reach.NULLBRK:
                    continue
                wmask |= c & 0x0F
            wmask |= data.weap_class[0xFF] & 0x0F
        amask = 0
        multis = []
        for cmd, sids in reach.COMMAND_ABILITIES.items():
            if cmd not in cmds:
                continue
            for sid in sids:
                amask |= data.skill_class.get(sid, 0) & 0x0F
        if "TOOLS" in cmds:
            for it in reach.TOOLS_RANGE:
                amask |= data.weap_class[it] & 0x0F
                if ip[it * ITEM_REC + 27] == 0x32:
                    multis.append(inames[it].strip())
        for sid in range(0x55, 0x65):
            owner = ("BUSHIDO" if sid < 0x5D else "BLITZ")
            if owner in cmds and rec(sid)[9] == 0x32:
                multis.append(magic_name(sid))
        extra = amask & ~wmask & 0x0F
        print("  %-6s weapon[%-22s] ability[%-22s] ability-only[%-14s] "
              "multi-hit: %s" %
              (who, class_names(wmask), class_names(amask),
               class_names(extra) if extra else "-",
               ", ".join(multis) if multis else "none (Fight+BP only)"))

    return 0 if n_up == 10 else 1


if __name__ == "__main__":
    sys.exit(main())
