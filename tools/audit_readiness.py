#!/usr/bin/env python3
"""What the party could be wearing and is not, read straight out of a saved game.

Reports rather than fails: an empty slot is often correct (the bag has
nothing that fits, or the character is a guest).

    python3 tools/audit_readiness.py                     every declared state
    python3 tools/audit_readiness.py build/states/x.mss  one of them

Three things it knows that are easy to get wrong by hand:

  * The left hand only takes a weapon when the character wears a Genji Glove,
    a Gauntlet or a Merit Award; otherwise it takes a shield.  Two weapons is
    worth chasing here because a shield chips by weapon class, so two hands
    can carry two break classes.
  * Which items a character may equip is a per-character mask in
    item_prop_en.dat, not a guess from the item's name.
  * The back row halves incoming physical damage and costs nothing at all to
    a character whose damage comes from Tools, Magic, Blitz, SwdTech, Throw
    or Steal, because only a weapon swing pays for it.  The row is printed so
    a front-row caster is visible.

It shares savestate_party.py with the equipment and party-health checks, so
all three agree about where the character table is.
"""

from __future__ import annotations

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import savestate_party as SP  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHAR_BLOCK, CHAR_REC, ITEM_REC = 0x1600, 37, 30

SLOTS = ["R hand", "L hand", "helmet", "armor", "relic1", "relic2"]
# slot index -> the item types the game will accept there
SLOT_TYPE = {0: {1}, 1: {1, 3}, 2: {4}, 3: {2}, 4: {5}, 5: {5}}
TWO_WEAPON_RELICS = {0x43, 0x44, 0x46}   # Genji Glove, Gauntlet, Merit Award

_ITEM_NAMES = json.load(open(
    os.path.join(REPO, "ff6/src/text/item_name_en.json"), encoding="utf-8"))["text"]
_ITEM_PROP = open(os.path.join(REPO, "ff6/src/menu/item_prop_en.dat"), "rb").read()


def item_name(i):
    return "(empty)" if i == 0xFF else _ITEM_NAMES[i].strip()


def item_rec(i):
    return _ITEM_PROP[i * ITEM_REC:(i + 1) * ITEM_REC]


def item_type(i):
    return item_rec(i)[0] & 0x07


def equippable_by(i, actor):
    """The per-character equip mask, item_prop +$01, 16-bit, bit N = actor N."""
    return bool((int.from_bytes(item_rec(i)[1:3], "little") >> actor) & 1)


def report(path):
    raw = SP.biggest_stream(path)
    cb = SP.find_char_block(raw)
    at = lambda a: raw[cb + a - CHAR_BLOCK]

    bag = {}
    for i in range(256):
        item, qty = at(0x1869 + i), at(0x1969 + i)
        if item != 0xFF and qty:
            bag[item] = bag.get(item, 0) + qty

    print("== %s" % os.path.basename(path))
    print("   bag: %s" % ", ".join(
        "%s x%d" % (item_name(i), q) for i, q in sorted(bag.items())) or "(empty)")

    gaps = 0
    for slot_in_party in range(16):
        party = at(0x1850 + slot_in_party)
        if not party & 0x07:
            continue
        rec = CHAR_BLOCK + CHAR_REC * slot_in_party
        actor = at(rec) & 0x0F
        who = SP.NAMES.get(actor, "#%d" % actor)

        worn, dsum, msum = [], 0, 0
        for k in range(6):
            item = at(rec + 0x1F + k)
            if item == 0xFF:
                continue
            if k == 0:
                worn.append("%s(pow%d)" % (item_name(item), item_rec(item)[20]))
                continue
            dsum += item_rec(item)[20]
            msum += item_rec(item)[21]
            worn.append("%s(d%d/m%d)" % (
                item_name(item), item_rec(item)[20], item_rec(item)[21]))
        print("   %-6s row=%-5s def=%-3d mdef=%-3d  %s" % (
            who, "BACK" if party & 0x20 else "front", dsum, msum,
            " ".join(worn) or "NOTHING AT ALL"))

        for k in range(6):
            if at(rec + 0x1F + k) != 0xFF:
                continue
            fits = [i for i in bag
                    if item_type(i) in SLOT_TYPE[k] and equippable_by(i, actor)]
            if k == 1:
                relics = {at(rec + 0x23), at(rec + 0x24)}
                if not (relics & TWO_WEAPON_RELICS):
                    fits = [i for i in fits if item_type(i) == 3]
            if fits:
                gaps += 1
                print("     %-7s empty, and the bag holds: %s" % (
                    SLOTS[k], ", ".join("%s (def%d mdef%d)" % (
                        item_name(i), item_rec(i)[20], item_rec(i)[21])
                        for i in fits)))
    return gaps


def main():
    args = sys.argv[1:]
    if args:
        paths = args
    else:
        states = SP.declared_states(REPO)
        paths = [os.path.join(REPO, "build/states", "%s.mss" % s)
                 for s in sorted(states)]
        paths = [p for p in paths if os.path.exists(p)]
    if not paths:
        print("readiness: no saved games to read")
        return 0

    total = 0
    for p in paths:
        total += report(p)
        print()
    print("readiness: %d saved game(s) read, %d empty slot(s) the bag could fill"
          % (len(paths), total))
    print("An empty slot is not automatically wrong -- a guest character, or a")
    print("slot the story is about to take away, is fine.  This is a place to")
    print("look when a fight seems too hard, not a bar to clear.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
