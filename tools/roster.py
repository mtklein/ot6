#!/usr/bin/env python3
"""Every character's level, HP, MP, experience and gear in a save or a state.

    python3 tools/roster.py <battery .sram | state .mss | checkpoint dir>...

savestate_party.py reads the members assigned to a party; the bench (a
recruit no party holds, $1850+c low bits 0) is left out there.  This reads
all fourteen records of the $1600 table, whoever holds them, and names the
gear from the source's item table.  A character is listed when the save's
recruited mask ($1EDE+, bit c) has its bit, or when a party holds it.
Read-only: it never writes a fixture.  (#496: the twelve at the tower's
boot.)
"""
import glob
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import savestate_party as sp  # noqa: E402

ROOT = os.path.dirname(HERE)
ITEMS = [s for s in json.load(open(os.path.join(ROOT, "ff6/src/text/item_name_en.json"),
                                   encoding="utf-8"))["text"]]
ESPERS = [s for s in json.load(open(os.path.join(ROOT, "ff6/src/text/genju_name_en.json"),
                                    encoding="utf-8"))["text"]]
RECRUITED = 0x1EDE   # 16 bits: the characters the party-select menu offers
LEARNED = 0x1A6E     # 54 bytes a character (TERRA .. GAU): each spell's learn percent, $FF learned
CARE = ((0x2D, "Cure"), (0x2E, "Cure2"), (0x2F, "Cure3"), (0x30, "Life"), (0x31, "Life2"), (0x34, "Regen"))


def clean(s):
    import re
    return re.sub(r"\{[^}]*\}", "", s).strip() or "-"


def item(i):
    return "-" if i == 0xFF else clean(ITEMS[i])


def blob(path):
    if os.path.isdir(path):
        path = glob.glob(os.path.join(path, "*.sram"))[0]
    if path.endswith(".mss"):
        raw = sp.biggest_stream(path)
        return raw, sp.find_char_block(raw)
    raw = open(path, "rb").read()
    return raw, sp.find_char_block(raw, allow_fallback=False)


def roster(path):
    raw, cb = blob(path)
    if cb is None:
        return None, "character table not located"
    party = cb + (sp.PARTY - sp.CHAR_BLOCK)
    mask_at = cb + (RECRUITED - sp.CHAR_BLOCK)
    mask = raw[mask_at] | raw[mask_at + 1] << 8
    out = []
    for c in range(14):
        held = raw[party + c] & 0x07
        if not (mask >> c) & 1 and not held:
            continue
        r = cb + sp.REC * c
        w = lambda o: int.from_bytes(raw[r + o:r + o + 2], "little")
        out.append({
            "char": c, "name": sp.NAMES.get(c, "#%d" % c), "level": raw[r + 8],
            "hp": w(9), "maxhp": sp.calc_max(w(11), 9999), "mp": w(13), "maxmp": sp.calc_max(w(15), 999),
            "xp": int.from_bytes(raw[r + 0x11:r + 0x14], "little"), "party": held,
            "esper": "-" if raw[r + 0x1E] == 0xFF else clean(ESPERS[raw[r + 0x1E]]),
            "gear": [item(raw[r + o]) for o in range(0x1F, 0x25)],
            # the healing spells learned for good (an esper's spells while equipped are not counted here)
            "cures": [n for s, n in CARE if c < 12 and raw[cb + (LEARNED - sp.CHAR_BLOCK) + 54 * c + s] == 0xFF],
        })
    return out, None


def main(argv):
    for p in argv:
        rows, err = roster(p)
        print("==", p)
        if err:
            print("  ", err)
            continue
        lv = sorted(m["level"] for m in rows)
        for m in rows:
            print("  %-6s L%-2d %4d/%-4d mp %3d/%-3d xp %7d party %d  esper %-9s %s" % (
                m["name"], m["level"], m["hp"], m["maxhp"], m["mp"], m["maxmp"], m["xp"], m["party"],
                m["esper"], " | ".join(m["gear"])) + ("  learned " + "/".join(m["cures"]) if m["cures"] else ""))
        print("  %d characters: levels %s; mean %.1f, max %d" % (len(rows), " ".join(map(str, lv)),
                                                                 sum(lv) / len(lv), lv[-1]))


if __name__ == "__main__":
    main(sys.argv[1:])
