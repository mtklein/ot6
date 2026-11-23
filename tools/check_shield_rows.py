#!/usr/bin/env python3
"""Build gate: every species appears at most once in the break tables.

Ot6SeedShields (ff6/src/battle/ot6_break.asm) scans Ot6ShieldTbl from the
top and takes the FIRST row whose species matches; Ot6ElemAdd scans
Ot6ElemAddTbl the same way.  A second row for the same species is dead
code that reads as authored -- issue #157: five keyed rows added in
c0fb032 sat under older shields-only rows for the same species and never
seeded, while the design audit (which kept the LAST row) reported the
keys as shipped.

Three checks, any failure exits 1:

  1. the Ot6ShieldTbl source (ff6/src/battle/ot6_hud.asm) lists each
     species once;
  2. the Ot6ElemAddTbl source (ff6/src/battle/ot6_break.asm) lists each
     species once;
  3. the Ot6ShieldTbl the ROM ships (build/ot6.sfc, located the way
     tools/audit_break_coverage.py locates it) is row-for-row the parsed
     source: same species order, shields and class bytes, no duplicates.

Usage:  python3 tools/check_shield_rows.py [--repo ROOT] [--rom PATH] [--selftest]
"""

from __future__ import annotations

import argparse
import glob
import os
import re
import sys

HUD_ASM = "ff6/src/battle/ot6_hud.asm"
BREAK_ASM = "ff6/src/battle/ot6_break.asm"
ROM = "build/ot6.sfc"

CLASS_BIT = {"OT6_SWORD": 0x01, "OT6_DAGGER": 0x02, "OT6_BLUNT": 0x04,
             "OT6_RANGED": 0x08, "OT6_KATANA": 0x10, "OT6_SPEAR": 0x20}


def _num(tok: str) -> int:
    tok = tok.strip()
    if tok.startswith("$"):
        return int(tok[1:], 16)
    return int(tok, 0)


def parse_rows(text: str, label: str, byte2_is_mask: bool):
    """Rows of a `.word species / .byte a, b` table, in source order.

    Returns [(species, a, b, line_no)] up to the $ffff terminator.
    """
    lines = text.splitlines()
    start = next(i for i, l in enumerate(lines) if l.strip().startswith(label + ":"))
    rows, pending, pending_line = [], None, None
    for i in range(start + 1, len(lines)):
        code = lines[i].split(";", 1)[0]
        m = re.match(r"\s*\.word\s+\$([0-9a-fA-F]{4})\s*$", code)
        if m:
            v = int(m.group(1), 16)
            if v == 0xFFFF:
                break
            pending, pending_line = v, i + 1
            continue
        m = re.match(r"\s*\.byte\s+([^,]+),\s*(.+?)\s*$", code)
        if m and pending is not None:
            a = _num(m.group(1))
            b = 0
            for tok in m.group(2).split("|"):
                tok = tok.strip()
                if byte2_is_mask and tok in CLASS_BIT:
                    b |= CLASS_BIT[tok]
                else:
                    b |= _num(tok)
            rows.append((pending, a, b, pending_line))
            pending, pending_line = None, None
    return rows


def duplicates(rows):
    seen, dups = {}, []
    for sp, a, b, line in rows:
        if sp in seen:
            dups.append((sp, seen[sp], line))
        else:
            seen[sp] = line
    return dups


def rom_shield_rows(rom: bytes):
    """The shipped Ot6ShieldTbl, found by its opening rows the way
    audit_break_coverage.py finds it (guard $0000/2/PIERCE, lobo $0019/3/PIERCE)."""
    key = bytes([0x00, 0x00, 2, 0x02, 0x19, 0x00, 3, 0x02])
    i = rom.find(key)
    if i < 0:
        raise SystemExit("check_shield_rows: Ot6ShieldTbl signature not found in the ROM")
    if rom.find(key, i + 1) >= 0:
        raise SystemExit("check_shield_rows: Ot6ShieldTbl signature is not unique in the ROM")
    rows, a = [], i
    while True:
        sp = rom[a] | (rom[a + 1] << 8)
        if sp == 0xFFFF:
            break
        rows.append((sp, rom[a + 2], rom[a + 3], a))
        a += 4
    return rows


# ------------------------------------------------- the reachable formations --
# Every way the game picks a formation (battle_main.asm LoadBattle reads $11e0),
# each read from the tree's own data:
#   - a battle-enabled field map's pool and each World sector's pool
#     (SubBattleGroup / WorldBattleGroup -> RandBattleGroup), the +Rand flag
#     expanded, as tools/audit_break_coverage.py walks them;
#   - an event battle group (EventBattleGroup, both formations: field/event.asm
#     EventBattle takes the first 3/4 of the time, the second 1/4) when an
#     event or vehicle script calls it (`battle N`, event_cmd.inc's $4c/$4d/$cf),
#     a monster-in-a-box chest holds it (treasure_prop.dat, kind $20, the group
#     in the content byte; player.asm), or engine code names it (the magitek
#     train's ride, world/train_script.asm `lda #$00NN ; event battle`; the
#     World of Ruin airship's Doom Gaze, world/ctrl.asm `ldx #$0174`);
#   - a formation an ai script changes to (`change_battle N`);
#   - the colosseum's two (field/event.asm `ldx #$023f` / `#$023e`), and the
#     opponent the colosseum puts in them: ColosseumProp's monster for each
#     wager (menu/colosseum.asm `make_colosseum_prop`, a blank row the default
#     CHUPON_COLOSSEUM), held as a species, not a formation;
#   - CondBattle's substitute for a reachable formation (battle_main.asm);
#   - the final battle's next tier (battle_main.asm FinalBattleIDTbl: each
#     word's formation, once reached, leads to the next word's).
# The Veldt only re-deals formations already met (battle_main.asm $1ddd).
DATS = {k: "ff6/src/" + v for k, v in {
    "props": "field/map_prop.dat", "sbg": "field/sub_battle_group.dat",
    "rbg": "field/rand_battle_group.dat", "wbg": "field/world_battle_group.dat",
    "ebg": "field/event_battle_group.dat", "chests": "field/trigger/treasure_prop.dat",
    "cond": "battle/cond_battle.dat", "bm": "battle/battle_monsters.dat"}.items()}
EVENT_GLOB = "ff6/src/event/*.asm"
AI_ASM = "ff6/src/battle/ai_script.asm"
TRAIN_ASM = "ff6/src/world/train_script.asm"
WORLD_CTRL_ASM = "ff6/src/world/ctrl.asm"
FIELD_EVENT_ASM = "ff6/src/field/event.asm"
COLOSSEUM_ASM = "ff6/src/menu/colosseum.asm"
CONST_INC = "ff6/include/const.inc"
BATTLE_MAIN_ASM = "ff6/src/battle/battle_main.asm"
UNREACHED_LABEL = "Ot6ShieldTblUnreached"


def formation_species(bm: bytes, f: int) -> list[int]:
    rec = bm[f * 15:(f + 1) * 15]
    if len(rec) < 15:
        return []
    return [rec[2 + s] | (((rec[14] >> s) & 1) << 8) for s in range(6) if rec[1] & (1 << s)]


def expand(word: int) -> list[int]:
    base = word & 0x01FF
    return [base + k for k in range(4)] if word & 0x8000 else [base]


def read_sources(root: str) -> dict:
    """The raw inputs reachable_formations reads, so the selftest can mutate them."""
    src = {k: open(os.path.join(root, p), "rb").read() for k, p in DATS.items()}

    def text(rel):
        with open(os.path.join(root, rel), encoding="utf-8") as f:
            return f.read()
    called = {}
    for p in sorted(glob.glob(os.path.join(root, EVENT_GLOB))):
        for n, line in enumerate(open(p, encoding="utf-8"), 1):
            m = re.match(r"\s*battle\s+(\d+)\b", line.split(";", 1)[0])
            if m:
                called.setdefault(int(m.group(1)), "%s:%d" % (os.path.relpath(p, root), n))
    src["called"] = called
    src["ai"] = {int(m.group(1)) for m in re.finditer(r"^\s*change_battle\s+(\d+)", text(AI_ASM), re.M)}
    engine = {}
    for m in re.finditer(r"lda\s+#\$([0-9a-fA-F]{4})\s*;\s*event battle", text(TRAIN_ASM)):
        engine[int(m.group(1), 16)] = TRAIN_ASM
    for m in re.finditer(r"ldx\s+#\$([0-9a-fA-F]{4})\s*\n\s*lda\s+f:EventBattleGroup,x", text(WORLD_CTRL_ASM)):
        engine[int(m.group(1), 16) // 4] = WORLD_CTRL_ASM
    src["engine"] = engine
    src["colosseum"] = {int(m.group(1), 16) for m in
                        re.finditer(r"ldx\s+#\$([0-9a-fA-F]{4})\s*;[^\n]*colosseum battle", text(FIELD_EVENT_ASM))}
    src["colosseum_prop"] = colosseum_opponents(text(COLOSSEUM_ASM), monster_ids(text(CONST_INC)))
    src["final"] = final_battle_ids(text(BATTLE_MAIN_ASM))
    return src


def monster_ids(text: str) -> dict:
    """const.inc's MONSTER enum: name -> species id (its `;= $NNNN` comments)."""
    m = re.search(r"^\.enum MONSTER\n(.*?)^\.endenum", text, re.M | re.S)
    assert m, "no .enum MONSTER in " + CONST_INC
    return {n: int(v, 16) for n, v in re.findall(r"^\s*(\w+)\s*;=\s*\$([0-9a-fA-F]+)", m.group(1), re.M)}


def colosseum_opponents(text: str, ids: dict) -> dict:
    """{species: [wager row, ...]}: ColosseumProp's monster for each wager, in
    the order of the table (a blank make_colosseum_prop is CHUPON_COLOSSEUM, the
    macro's default)."""
    start = text.index("\nColosseumProp:")
    out = {}
    row = 0
    for line in text[start + 1:].splitlines()[1:]:
        code = line.split(";", 1)[0].strip()
        if not code:
            continue
        if not code.startswith("make_colosseum_prop"):
            break
        args = code[len("make_colosseum_prop"):].strip()
        name = args.split(",")[0].strip() if args else "CHUPON_COLOSSEUM"
        assert name in ids, "ColosseumProp row %d: monster %s is not in the MONSTER enum" % (row, name)
        out.setdefault(ids[name], []).append(row)
        row += 1
    assert row == 256, "ColosseumProp has %d rows, not one per item (256)" % row
    return out


def final_battle_ids(text: str) -> list[int]:
    """FinalBattleIDTbl's words: each formation, once reached, leads to the next."""
    m = re.search(r"^FinalBattleIDTbl:\s*\n(?:@\w+:)?\s*\.word\s+([^\n;]+)", text, re.M)
    assert m, "no FinalBattleIDTbl in " + BATTLE_MAIN_ASM
    return [int(w.strip().lstrip("$"), 16) for w in m.group(1).split(",")]


def reachable_formations(src: dict) -> dict:
    """{formation: [how the game reaches it, ...]}"""
    props, sbg, rbg, wbg, ebg = src["props"], src["sbg"], src["rbg"], src["wbg"], src["ebg"]
    out = {}

    def add(f, why):
        out.setdefault(f, []).append(why)

    def group(g):
        return [f for i in range(0, 8, 2) for f in expand(rbg[g * 8 + i] | (rbg[g * 8 + i + 1] << 8))]

    def event_group(g, why):
        for w in (ebg[g * 4] | (ebg[g * 4 + 1] << 8), ebg[g * 4 + 2] | (ebg[g * 4 + 3] << 8)):
            for f in expand(w):
                add(f, why)
    for m in range(len(props) // 33):
        if props[m * 33 + 5] & 0x80:
            for f in group(sbg[m]):
                add(f, "map %d's pool" % m)
    for sec in range(len(wbg)):
        if wbg[sec] != 0xFF:
            for f in group(wbg[sec]):
                add(f, "world sector %d's pool" % sec)
    for g, where in src["called"].items():
        event_group(g, "battle %d (%s)" % (g, where))
    for g, where in src["engine"].items():
        event_group(g, "event battle %d (%s)" % (g, where))
    chests = src["chests"]
    for i in range(0, len(chests) - 4, 5):
        if chests[i + 3] & 0x20:
            event_group(chests[i + 4], "event battle %d (a monster-in-a-box)" % chests[i + 4])
    for f in src["ai"]:
        add(f, "an ai script's change_battle")
    for f in src["colosseum"]:
        add(f, "the colosseum")
    cond = src["cond"]
    for i in range(0, len(cond) - 3, 4):
        a, b = cond[i] | (cond[i + 1] << 8), cond[i + 2] | (cond[i + 3] << 8)
        if a and a in out:
            add(b, "CondBattle's substitute for formation %d" % a)
    final = src["final"]
    for a, b in zip(final, final[1:]):
        if a in out:
            add(b, "the final battle's tier after formation %d (FinalBattleIDTbl)" % a)
    return out


def unreached_species(text: str) -> set[int]:
    """Species of the rows under the Ot6ShieldTblUnreached label (the marker block)."""
    lines = text.splitlines()
    try:
        start = next(i for i, l in enumerate(lines) if l.strip().startswith(UNREACHED_LABEL + ":"))
    except StopIteration:
        return set()
    out = set()
    for l in lines[start + 1:]:
        m = re.match(r"\s*\.word\s+\$([0-9a-fA-F]{4})\s*$", l.split(";", 1)[0])
        if m:
            v = int(m.group(1), 16)
            if v == 0xFFFF:
                break
            out.add(v)
    return out


def coverage_problems(src: dict, rows, unreached: set[int]):
    """(problems, summary): every species a reachable formation holds has a
    row; every marker row is a 0-shield row for a species none holds."""
    reach = reachable_formations(src)
    bm = src["bm"]
    held = {}      # species -> [how the game deals it, ...]
    for f in sorted(reach):
        for sp in sorted(set(formation_species(bm, f))):
            held.setdefault(sp, []).append("formation %d holds it (%s)" % (f, reach[f][0]))
    if 0x23F in reach:
        for sp, wagers in sorted(src.get("colosseum_prop", {}).items()):
            held.setdefault(sp, []).append("the colosseum deals it for %d wager(s), item %d first"
                                           % (len(wagers), wagers[0]))
    authored = {sp: (sh, mask) for sp, sh, mask, _ in rows}
    problems = []
    for sp in sorted(held):
        if sp not in authored:
            problems.append("species $%03X has no Ot6ShieldTbl row, but %s%s: "
                            "it rides the generated floor; author its row"
                            % (sp, held[sp][0], "" if len(held[sp]) == 1
                               else " and %d other way(s)" % (len(held[sp]) - 1)))
    for sp in sorted(unreached):
        if sp in held:
            problems.append("species $%03X sits under %s, but %s: a reachable body "
                            "needs a designed row" % (sp, UNREACHED_LABEL, held[sp][0]))
        sh, mask = authored.get(sp, (0, 0))
        if sh != 0 or mask != 0:
            problems.append("species $%03X sits under %s with %d shields and class $%02X: a marker row is 0, $00"
                            % (sp, UNREACHED_LABEL, sh, mask))
    summary = ("%d reachable formations hold %d species, %d without an authored row; %d marker rows under %s"
               % (len(reach), len(held), len([s for s in held if s not in authored]), len(unreached),
                  UNREACHED_LABEL))
    return problems, summary


def check(root: str, rom_path: str | None) -> list[str]:
    problems = []

    def text(rel):
        with open(os.path.join(root, rel), encoding="utf-8") as f:
            return f.read()

    shield = parse_rows(text(HUD_ASM), "Ot6ShieldTbl", True)
    cov, summary = coverage_problems(read_sources(root), shield, unreached_species(text(HUD_ASM)))
    problems += cov
    print("check_shield_rows: " + summary)
    elem = parse_rows(text(BREAK_ASM), "Ot6ElemAddTbl", False)
    for sp, first, again in duplicates(shield):
        problems.append("Ot6ShieldTbl lists species $%04X twice: %s:%d and :%d "
                        "(the seeder takes the first; the second is dead)"
                        % (sp, HUD_ASM, first, again))
    for sp, first, again in duplicates(elem):
        problems.append("Ot6ElemAddTbl lists species $%04X twice: %s:%d and :%d "
                        "(the scan takes the first; the second is dead)"
                        % (sp, BREAK_ASM, first, again))

    rom_path = rom_path or os.path.join(root, ROM)
    if not os.path.exists(rom_path):
        problems.append("no ROM at %s to compare the shipped table against" % rom_path)
        return problems
    with open(rom_path, "rb") as f:
        rom = f.read()
    shipped = rom_shield_rows(rom)
    for sp, first, again in duplicates(shipped):
        problems.append("the ROM's Ot6ShieldTbl lists species $%04X twice (rom+$%06X and rom+$%06X)"
                        % (sp, first, again))
    if len(shipped) != len(shield):
        problems.append("the ROM's Ot6ShieldTbl has %d rows, the source %d"
                        % (len(shipped), len(shield)))
    for n, (src, ship) in enumerate(zip(shield, shipped)):
        if src[:3] != ship[:3]:
            problems.append("first differing row %d: source %s:%d $%04X/%d/$%02X, ROM rom+$%06X $%04X/%d/$%02X"
                            % (n, HUD_ASM, src[3], src[0], src[1], src[2],
                               ship[3], ship[0], ship[1], ship[2]))
            break
    return problems


def selftest(root: str) -> int:
    good = "Tbl:\n .word $0001\n .byte 2, OT6_PIERCE\n .word $0002\n .byte 3, $00\n .word $ffff\n"
    bad = "Tbl:\n .word $0001\n .byte 2, $00 ; old\n .word $0002\n .byte 3, $00\n .word $0001\n .byte 2, OT6_PIERCE|OT6_SLASH\n .word $ffff\n"
    rows = parse_rows(good, "Tbl", True)
    assert rows == [(1, 2, 2, 2), (2, 3, 0, 4)], rows
    assert duplicates(rows) == []
    rows = parse_rows(bad, "Tbl", True)
    assert rows[2] == (1, 2, 3, 6), rows
    assert duplicates(rows) == [(1, 2, 6)], duplicates(rows)
    rom = bytes([0xEE] * 16 + [0, 0, 2, 2, 0x19, 0, 3, 2, 0x34, 0x01, 4, 2, 0x34, 0x01, 4, 0, 0xFF, 0xFF])
    got = rom_shield_rows(rom)
    assert [r[:3] for r in got] == [(0, 2, 2), (0x19, 3, 2), (0x134, 4, 2), (0x134, 4, 0)], got
    assert len(duplicates(got)) == 1
    print("check_shield_rows selftest: duplicate rows OK")
    return coverage_selftest(root)


def coverage_selftest(root: str) -> int:
    """The coverage gate against the tree's own data, then one mutant per
    property, each of which must be refused with the line that names it."""
    with open(os.path.join(root, HUD_ASM), encoding="utf-8") as f:
        hud = f.read()
    rows = parse_rows(hud, "Ot6ShieldTbl", True)
    unreached = unreached_species(hud)
    src = read_sources(root)
    reach = reachable_formations(src)
    # the parsers found each kind of source (a parse that went blind would
    # pass every species as unreached)
    assert 0x29 in src["engine"] and 0x90 in src["engine"] and 93 in src["engine"], src["engine"]
    assert src["colosseum"] == {0x23E, 0x23F}, src["colosseum"]
    assert src["colosseum_prop"].get(0x40) and src["colosseum_prop"].get(0x7D) == [4], \
        "the ColosseumProp parse: CHUPON_COLOSSEUM's default rows, WART_PUCK for the ThiefKnife"
    assert src["final"][:2] == [0x1D7, 0x200] and len(src["final"]) == 4, src["final"]
    assert {424, 512, 513, 514} <= src["ai"], src["ai"]
    assert 109 in src["called"] and 22 in src["called"], "the event parse lost battles 22/109"
    assert any("monster-in-a-box" in w for w in reach.get(476, [])), "the chest parse lost formation 476"
    assert any("pool" in w for w in reach.get(75, [])), "the pool walk lost map 149's formation 75"
    assert len(unreached) >= 1, "no rows under " + UNREACHED_LABEL
    problems, summary = coverage_problems(src, rows, unreached)
    assert problems == [], problems
    print("check_shield_rows selftest: the tree passes (" + summary + ")")

    def refused(tag, mrows, munreached, msrc, want):
        got, _ = coverage_problems(msrc, mrows, munreached)
        assert any(want in p for p in got), "%s: mutant not refused (wanted %r, got %r)" % (tag, want, got)
        print("check_shield_rows selftest: mutant refused, %s: %s" % (tag, next(p for p in got if want in p)))
    # 1. a reachable body loses its row: the train's Siegfried, battle 109
    refused("row dropped", [r for r in rows if r[0] != 0x131], unreached, src, "species $131 has no Ot6ShieldTbl row")
    # 2. a reachable body filed as a marker: the raft's Pterodon
    refused("marker on a reachable body", rows, unreached | {0x022}, src, "species $022 sits under")
    # 3. a marker row given shields
    refused("marker with shields", [(sp, 2 if sp == 0x10F else sh, m, l) for sp, sh, m, l in rows],
            unreached, src, "species $10F sits under Ot6ShieldTblUnreached with 2 shields")
    refused("marker with a class", [(sp, sh, 0x02 if sp == 0x10F else m, l) for sp, sh, m, l in rows],
            unreached, src, "species $10F sits under Ot6ShieldTblUnreached with 0 shields and class $02")
    # a marker made reachable: a formation holding the marker body $10F, dealt
    # by a monster-in-a-box chest, an ai script's change_battle, or the final
    # battle's chain; and a marker body the colosseum deals for a wager
    bm = src["bm"]
    holder = next((f for f in range(len(bm) // 15) if 0x10F in formation_species(bm, f)), None)
    assert holder is not None and holder not in reach, "a formation holds $10F and none is reached"
    chests = bytearray(src["chests"])
    boxed = {chests[i + 4] for i in range(0, len(chests) - 4, 5) if chests[i + 3] & 0x20}
    g = next(g for g in range(len(src["ebg"]) // 4)
             if g not in src["called"] and g not in src["engine"] and g not in boxed)
    ebg = bytearray(src["ebg"])
    ebg[g * 4:g * 4 + 4] = bytes([holder & 0xFF, holder >> 8, holder & 0xFF, holder >> 8])
    i = next(i for i in range(0, len(chests) - 4, 5) if chests[i + 3] & 0x20)
    chests[i + 4] = g
    refused("marker in a chest", rows, unreached, dict(src, ebg=bytes(ebg), chests=bytes(chests)),
            "species $10F sits under Ot6ShieldTblUnreached, but formation %d holds it (event battle %d "
            "(a monster-in-a-box))" % (holder, g))
    refused("marker by change_battle", rows, unreached, dict(src, ai=src["ai"] | {holder}),
            "species $10F sits under Ot6ShieldTblUnreached, but formation %d holds it (an ai script's "
            "change_battle)" % holder)
    refused("marker past the final battle", rows, unreached, dict(src, final=src["final"] + [holder]),
            "species $10F sits under Ot6ShieldTblUnreached, but formation %d holds it (the final battle's tier"
            % holder)
    # the colosseum's ids are a byte, so its mutant files a low species as a
    # marker and deals it nowhere but the colosseum: every formation dropped
    colo = dict(src, colosseum_prop={0x7D: [4]}, called={}, engine={}, ai=set(),
                chests=bytes(len(src["chests"])), props=bytes(len(src["props"])),
                wbg=bytes([0xFF]) * len(src["wbg"]), final=[])
    refused("marker in the colosseum", [(0x7D, 0, 0, 0)], {0x7D}, colo,
            "species $07D sits under Ot6ShieldTblUnreached, but the colosseum deals it for 1 wager(s), item 4")
    # 4. a reachability mutant: battle 109's call gone, Siegfried's row gone,
    # and the gate must then stay green (the body is unreached, not missed)
    msrc = dict(src)
    msrc["called"] = {g: w for g, w in src["called"].items() if g != 109}
    got, _ = coverage_problems(msrc, [r for r in rows if r[0] != 0x131], unreached)
    assert got == [], got
    print("check_shield_rows selftest: with battle 109's call removed, $131 needs no row (reachability read)")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    ap.add_argument("--rom", default=None)
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return selftest(args.repo)
    problems = check(args.repo, args.rom)
    for p in problems:
        print("check_shield_rows: " + p)
    if problems:
        return 1
    with open(os.path.join(args.repo, HUD_ASM), encoding="utf-8") as f:
        n = len(parse_rows(f.read(), "Ot6ShieldTbl", True))
    print("check_shield_rows OK: %d Ot6ShieldTbl rows, one per species, ROM matches source" % n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
