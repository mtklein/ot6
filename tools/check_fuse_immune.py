#!/usr/bin/env python3
"""Build gate (#561, wt/v052-tg-wob3): no status can lose a boss's announced move.

The boss contract (docs/design/bosses-wob.md): an announced move always fires unless a break cancels it or the boss
dies.  Three statuses would lose one:
  * Berserk: a Berserked monster runs no AI script (its turns are Fights);
  * Mute: a Muted monster's MP-cost move fizzles (battle_main.asm @3201, $3EE5 bit 3);
  * Imp: an Imp's MP-cost move fizzles too (the same test, $3EE4 bit 5), and an Imp whose move's command cannot be
    used by an Imp has it turned into a Fight (@029a: a command under $1E whose BattleCmdProp lacks the IMP flag,
    $04; a monster's attack takes its command from GetCmdForAI's table -- specials $8B-$ED are Lore, $0C, no IMP
    flag -- and Roulette becomes $1E, FixRoulette, which the test passes).
So every body that announces -- every species with a row in Ot6FuseTbl -- must be immune to Berserk; to Mute when its
announced move costs MP (MagicProp +5); and to Imp when the move costs MP or its command is not an Imp's.  Sleep, Stop
and Muddle only delay the move; Rasp and Osmose draining the MP stay the player's.

Read from the built ROM: each row's species, its announced move (the first attack, `cmd`, or call for backup after
the row's last lit address, as battle_fuse.lua reads it; where the fuse block holds none there, the move of the
earlier block that really takes the move's turn, conditioned on the switch the announce sets -- the Tentacles', Umaro's
and Phunbaba's second visit's fire blocks, wt/v052-tg-wor1; a switch row, the Gold Dragon's, counts as costing MP), and
the species' blocked status bytes (MonsterProp +$14 and +$15, as LoadRageProp loads them: a set bit is immunity;
Imp $20 in +$14, Mute $08 and Berserk $10 in +$15).

    python3 tools/check_fuse_immune.py [--rom R] [--dbg D]   check (prints every row's verdict)
    python3 tools/check_fuse_immune.py --selftest            four mutants red: Chupon open to Mute, Nerapa open to
                                                             Berserk, Number 024 open to Imp (vanilla's bytes), and
                                                             the Tentacle $11B's real fire block (seat 1) casting
                                                             Fire (MP 4: it is open to Mute)
"""
import argparse
import re
import sys

SIZE = [4, 2, 4, 3, 4, 4, 4, 2, 3, 4, 4, 3, 4, 1, 1, 1]       # AICmdSizeTbl
MUTE, BERSERK, IMP = 0x08, 0x10, 0x20
CMD_IMP = 0x04              # BattleCmdProp +0: can be used by an Imp


def syms(dbg):
    t = open(dbg, encoding="latin-1").read()
    out = {}
    for n in ("AIScript", "AIScriptPtrs", "Ot6FuseTbl", "MagicProp", "MonsterProp", "AttackForAITbl", "CmdForAITbl",
              "BattleCmdProp"):
        m = re.search(r'name="%s",[^\n]*val=0x([0-9A-Fa-f]+)' % n, t)
        if not m:
            raise SystemExit("check_fuse_immune: %s not in %s" % (n, dbg))
        out[n] = int(m.group(1), 16) & 0x3FFFFF
    return out


def ai_cmd(rom, s, a):
    """the command a monster's attack a is queued with (GetCmdForAI, then FixRoulette)"""
    cmd = 0x02
    for x in range(10, -1, -1):
        if a >= rom[s["AttackForAITbl"] + x]:
            cmd = rom[s["CmdForAITbl"] + x]
            break
    if a == 0x8C and cmd == 0x0C:
        cmd = 0x1E
    return cmd


def imp_turns(rom, s, cmd):
    """an Imp's use of this command is turned into a Fight (@029a)"""
    return cmd < 0x1E and not rom[s["BattleCmdProp"] + 2 * cmd] & CMD_IMP


def fire_block(rom, s, sp, lo):
    """(wt/v052-tg-wor1) the block that really fires a fuse whose block holds no move after its lit address: the
    announce sets a switch (set_monster_switch / set_battle_switch, $F9 $01 v b, before the `wait`; or the Tentacles'
    claim, if_seize_free seat CLAIM, $FC $00 seat $00: monster switch seat-1) and an EARLIER block of the turn script,
    conditioned on that switch ($FC $14 v b), takes the boss's next turn.  Returns its start, or None."""
    AI = s["AIScript"]
    start = rom[s["AIScriptPtrs"] + 2 * sp] | rom[s["AIScriptPtrs"] + 2 * sp + 1] << 8
    blocks, x, b0 = [], start, start
    while rom[AI + x] != 0xFF:
        b = rom[AI + x]
        x += SIZE[b - 0xF0] if b >= 0xF0 else 1
        if b == 0xFE:
            blocks.append((b0, x))
            b0 = x
    fuse = next(((a, e) for a, e in blocks if a <= lo < e), None)
    if fuse is None:
        return None
    sets, x = set(), fuse[0]
    while x < lo:
        b = rom[AI + x]
        if b == 0xF9 and rom[AI + x + 1] == 0x01:
            sets.add((rom[AI + x + 2], rom[AI + x + 3]))
        if b == 0xFC and rom[AI + x + 1] == 0x00 and rom[AI + x + 2] and rom[AI + x + 3] == 0x00:
            sets.add((0x24, rom[AI + x + 2] - 1))
        x += SIZE[b - 0xF0] if b >= 0xF0 else 1
    for a, e in blocks:
        if a >= fuse[0]:
            break
        y = a
        while rom[AI + y] == 0xFC:
            if rom[AI + y + 1] == 0x14 and (rom[AI + y + 2], rom[AI + y + 3]) in sets:
                return a
            y += 4
    return None


def first_move(rom, s, x):
    """the first move from x to its block's end: (description, mp, command), or (None, None, None)"""
    AI = s["AIScript"]
    while rom[AI + x] not in (0xFE, 0xFF):
        b = rom[AI + x]
        if b < 0xF0 or (b == 0xF0 and rom[AI + x + 1] != 0xFE):
            a = b if b < 0xF0 else rom[AI + x + 1]
            cmd = ai_cmd(rom, s, a)
            return "attack $%02X, command $%02X" % (a, cmd), rom[s["MagicProp"] + 14 * a + 5], cmd
        if b == 0xF4:
            return "command $%02X" % rom[AI + x + 1], 0, rom[AI + x + 1]
        # (an item is a move too: use_item / throw_item, $F6 -- Umaro's Green Cherry, wt/v052-tg-wor1: the
        # Item command, $01, or Throw, $08, which costs no MP and which an Imp keeps where the command's
        # flag says so)
        if b == 0xF6:
            cmd = 0x08 if rom[AI + x + 1] else 0x01
            return "item $%02X, command $%02X" % (rom[AI + x + 2], cmd), 0, cmd
        if b == 0xF5 and rom[AI + x + 2] in (0, 1):
            return "a call or a withdrawal (entry/exit)", 0, None
        x += SIZE[b - 0xF0] if b >= 0xF0 else 1
    return None, None, None


def rows(rom, s):
    """(species, move description, mp, command) for each Ot6FuseTbl row"""
    AI, T = s["AIScript"], s["Ot6FuseTbl"]
    out, r = [], T
    while (rom[r] | rom[r + 1] << 8) != 0xFFFF:
        sp = rom[r] | rom[r + 1] << 8
        lo, ln, fl = rom[r + 2] | rom[r + 3] << 8, rom[r + 4], rom[r + 7]
        move, mp, cmd = None, None, None
        if fl & 0x80:
            move, mp = "a counter's switch (counted as costing MP)", 1
        else:
            move, mp, cmd = first_move(rom, s, lo + ln - 1)
            if move is None:
                # the fire block that takes the move's turn (the Tentacles, Umaro, Phunbaba's second visit)
                fb = fire_block(rom, s, sp, lo)
                if fb is not None:
                    move, mp, cmd = first_move(rom, s, fb)
                    if move is not None:
                        move += " (its fire block at script+$%04X)" % (fb - (rom[s["AIScriptPtrs"] + 2 * sp] |
                                                                            rom[s["AIScriptPtrs"] + 2 * sp + 1] << 8))
        out.append((sp, move, mp, cmd))
        r += 8
    return out


def check(rom, s):
    bad, lines = [], []
    for sp, move, mp, cmd in rows(rom, s):
        imm1 = rom[s["MonsterProp"] + 32 * sp + 0x14]
        imm = rom[s["MonsterProp"] + 32 * sp + 0x15]
        imp_bad = bool(mp) or (cmd is not None and imp_turns(rom, s, cmd))
        need = BERSERK | (MUTE if mp else 0)
        need1 = IMP if imp_bad else 0
        ok = (imm & need) == need and (imm1 & need1) == need1
        opens = [n for n, b in (("Berserk", BERSERK), ("Mute", MUTE)) if need & b and not imm & b]
        if need1 and not imm1 & IMP:
            opens.append("Imp")
        lines.append("  $%03X: %s (MP %s%s), blocked status 1/2 $%02X/$%02X -> %s" % (sp, move, mp,
                     "; an Imp's use of the command is a Fight" if cmd is not None and imp_turns(rom, s, cmd) else "",
                     imm1, imm, "immune as needed" if ok else "OPEN to " + " and ".join(opens)))
        if move is None:
            bad.append("$%03X: no announced move found after the row's lit address" % sp)
        elif not ok:
            bad.append(lines[-1].strip())
    return bad, lines


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rom", default="build/ot6.sfc")
    ap.add_argument("--dbg", default="ff6/rom/ff6-en.dbg")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    rom = bytearray(open(a.rom, "rb").read())
    s = syms(a.dbg)
    if a.selftest:
        fails = []
        for sp, off, val, what in ((0x12F, 0x15, 0x63, "Chupon open to Mute and Berserk"),
                                   (0x118, 0x15, 0xCE, "Nerapa open to Berserk"),
                                   (0x10A, 0x14, 0xCF, "Number 024 open to Imp")):
            m = bytearray(rom)
            m[s["MonsterProp"] + 32 * sp + off] = val
            if not check(m, s)[0]:
                fails.append(what + " reads green")
        # the fire block read, not the announce block's tail: the Tentacle $11B's first row's fire block Seizes
        # with Fire instead (a one-byte attack), which costs MP and the body is open to Mute
        m = bytearray(rom)
        T = s["Ot6FuseTbl"]
        while (m[T] | m[T + 1] << 8) != 0x11B:
            T += 8
        fb = fire_block(m, s, 0x11B, m[T + 2] | m[T + 3] << 8)
        x = fb
        while m[s["AIScript"] + x] >= 0xF0:
            x += SIZE[m[s["AIScript"] + x] - 0xF0]
        m[s["AIScript"] + x] = 0x00
        red = check(m, s)[0]
        print("check_fuse_immune selftest: the fire-block mutant reads: " + ("; ".join(red) or "green"))
        if not red:
            fails.append("the Tentacle $11B's fire block casting Fire reads green")
        if check(rom, s)[0]:
            fails.append("the tree's own ROM is red")
        if fails:
            print("check_fuse_immune selftest: FAIL: " + "; ".join(fails))
            return 1
        print("check_fuse_immune selftest: PASS (Chupon's, Nerapa's and Number 024's vanilla bytes are caught, and a "
              "Fire in the Tentacle $11B's real fire block; the tree's ROM is clean)")
        return 0
    bad, lines = check(rom, s)
    for l in lines:
        print(l)
    for b in bad:
        print("check_fuse_immune: " + b)
    if bad:
        return 1
    print("check_fuse_immune: every one of the %d Ot6FuseTbl rows' bodies is immune to Berserk, to Mute where its "
          "announced move costs MP, and to Imp where it costs MP or an Imp's use of its command is a Fight" % len(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())
