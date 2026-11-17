"""Build gate (#553): no monster's shield line starts in screen column 0 or 1.

The battle HUD draws each monster's shield line on bg3 under the monster
(`Ot6BgHudLine`, ot6_hud.asm).  Its anchor (the count cell) sits at

    column = ((monster x + width * 4) & $ff) >> 3, minus one

where `monster x` is w7e80c3 and `width * 4` half the monster's drawn width
(cur_poi_set's w7e800f, btlgfx_main.asm).  The lead cell (the shield emblem)
is at anchor - 1 and Shadow's mark (#546) at anchor - 2, so a line anchored
in column 0 or 1 has no mark cell (the flush's edge rule: the cell would wrap
into the row above) and a slowed or stopped monster there would show no
dagger or knife.

This reads every formation from the built ROM and places each monster the
way the battle does at the open:

  - x = (BattleMonsters+8,slot & $f0) >> 1           (mon_data_get)
  - width = the stencil's last drawn column + 1, capped by the formation's
    vram-map box (InitStencil: rows are OR'd until the first empty one);
    the Ghost Train ($106) is $10 (LoadMonsterStencil)
  - per battle type the formation allows (BattleProp+0's high nibble, xor
    $f0: bit 4 normal, 5 back, 6 pincer, 7 side; ChooseBattleType):
    normal keeps x; back is -x - width*8; pincer mirrors a monster whose
    right edge is at $68 or more to -(x - $40 + width*8); side adds $30
    (CalcMonsterPos_00..03)
  - battle $23f (the Colosseum) re-centres its one monster
    (InitMonsterPos).

It fails, naming the formation, the slot and the monster, if any formation
the game can deal (check_shield_rows.py's reachable_formations: the pools,
the event and engine battles, chests, ai changes, the colosseum, CondBattle
and the final tiers) would anchor a line in column 0 or 1, or before column
0 (the x wraps).  A formation nothing deals is listed, not failed: today one,
battle $186 (390), the battle-event runner $17B in column 1, unused
(break-coverage-wob.md section 18).

The model is checked against the live HUD too: LIVE below holds what a lab
read from battle RAM (w7e80c3, w7e812f) on the v0.48 line's states
(build/attempts/wt/v048-shadow-fu/hudcols/), and the selftest fails if the
model places any of them elsewhere.  Positions a
battle script moves a monster to later are not formation data; the HUD
holds its anchor while a script runs and re-reads it after.

    python3 tools/check_hud_columns.py [--rom R] [--dbg D] [--list]
    python3 tools/check_hud_columns.py --selftest     mutants, each red
"""
import argparse
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from check_shield_rows import read_sources, reachable_formations  # noqa: E402

TYPES = ("normal", "back", "pincer", "side")
MIN_COLUMN = 2          # the mark cell is anchor - 2

# (battle, slot): (x, width) as the live battle RAM held them in a normal
# attack (lab_hudcols, build/attempts/wt/v048-shadow-fu/hudcols/lab_hudcols.log)
LIVE = {
    (0x002, 2): (32, 4), (0x002, 3): (64, 4), (0x02D, 3): (40, 4), (0x02D, 4): (80, 4),
    (0x1B9, 0): (48, 9), (0x164, 0): (56, 4), (0x057, 0): (40, 12), (0x023, 0): (80, 8),
    (0x023, 1): (24, 8), (0x070, 2): (64, 4), (0x070, 3): (88, 4), (0x070, 4): (40, 4),
    (0x054, 0): (72, 8), (0x054, 1): (72, 8), (0x054, 2): (24, 4), (0x054, 3): (24, 4),
}


def symbols(dbg, names):
    out = {}
    pat = re.compile(r'^sym\t.*name="([A-Za-z0-9_]+)".*val=0x([0-9A-F]+),seg=\d+,type=lab')
    with open(dbg, encoding="latin-1") as f:
        for line in f:
            m = pat.match(line)
            if m and m.group(1) in names and m.group(1) not in out:
                out[m.group(1)] = int(m.group(2), 16)
    missing = sorted(set(names) - set(out))
    if missing:
        raise SystemExit("check_hud_columns: %s not in %s" % (", ".join(missing), dbg))
    return out


def off(addr):
    return addr & 0x3FFFFF


def word(rom, at):
    return rom[at] | rom[at + 1] << 8


class Rom:
    def __init__(self, rom, sym):
        self.rom = rom
        self.formations = off(sym["BattleMonsters"])
        self.props = off(sym["BattleProp"])
        self.gfx = off(sym["MonsterGfxProp"])
        self.stencil = off(sym["MonsterStencil"])
        self.vrammaps = off(sym["MonsterVRAMMapPtrs"])

    def width(self, monster, vmap, slot):
        r = self.rom
        if monster == 0x106:
            return 0x10
        g = self.gfx + monster * 5
        large = r[g + 2] & 0x80
        mapno = r[g + 4]
        bank = self.stencil & 0xFF0000
        box = (self.vrammaps & 0xFF0000) | word(r, self.vrammaps + vmap * 2)
        cap = r[box + slot * 4 + 2]
        if large:
            at = bank | (word(r, self.stencil + 2) + mapno * 32)
            rows = [r[at + 2 * i] << 8 | r[at + 2 * i + 1] for i in range(16)]
        else:
            at = bank | (word(r, self.stencil) + mapno * 8)
            rows = [r[at + i] << 8 for i in range(8)]
        bits = 0
        for row in rows:
            if row == 0:
                break
            bits |= row
        last = 0
        for c in range(16):
            if bits & (0x8000 >> c):
                last = c
        return min(last + 1, cap)

    def lines(self, battle):
        """[(type, slot, monster, x, width, column)] for every placement"""
        r = self.rom
        f = self.formations + battle * 15
        vmap = r[f] >> 4
        present = r[f + 1] & 0x3F
        high = r[f + 14]
        types = (r[self.props + battle * 4] ^ 0xF0) >> 4
        out = []
        for t in range(4):
            if not types & (1 << t):
                continue
            for s in range(6):
                if not present & (1 << s):
                    continue
                monster = r[f + 2 + s] | ((high >> s) & 1) << 8
                w = self.width(monster, vmap, s)
                x = (r[f + 8 + s] & 0xF0) >> 1
                if battle == 0x23F:
                    x = ((0x80 - w * 8) >> 1) + 0x18
                elif t == 1:
                    x = (-x - w * 8) & 0xFF
                elif t == 2 and x + w * 8 >= 0x68:
                    x = (-(x - 0x40 + w * 8)) & 0xFF
                elif t == 3:
                    x = (x + 0x30) & 0xFF
                centre = (x + w * 4) & 0xFF
                out.append((TYPES[t], s, monster, x, w, (centre >> 3) - 1))
        return out


def model_problems(rom):
    bad = []
    for (b, s), (x, w) in sorted(LIVE.items()):
        got = [(lx, lw) for t, ls, m, lx, lw, col in rom.lines(b) if t == "normal" and ls == s]
        if got != [(x, w)]:
            bad.append("battle $%03X slot %d: the live HUD had x %d width %d, the model %s"
                       % (b, s, x, w, got or "no such line"))
    return bad


def problems(rom, battles):
    bad = []
    for b in battles:
        for t, s, m, x, w, col in rom.lines(b):
            if col < MIN_COLUMN:
                bad.append("battle $%03X %s slot %d monster $%03X: x %d width %d, "
                           "shield line anchored in column %d (the mark cell needs %d)"
                           % (b, t, s, m, x, w, col, MIN_COLUMN))
    return bad


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rom", default="build/ot6.sfc")
    ap.add_argument("--dbg", default="ff6/rom/ff6-en.dbg")
    ap.add_argument("--root", default=".")
    ap.add_argument("--list", action="store_true", help="print every placement's column")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    data = bytearray(open(a.rom, "rb").read())
    sym = symbols(a.dbg, ["BattleMonsters", "BattleProp", "MonsterGfxProp",
                          "MonsterStencil", "MonsterVRAMMapPtrs"])
    rom = Rom(data, sym)
    count = len(read_sources(a.root)["bm"]) // 15
    reach = sorted(f for f in reachable_formations(read_sources(a.root)) if f < count)
    if a.list:
        hist = {}
        for b in range(count):
            for t, s, m, x, w, col in rom.lines(b):
                print("battle $%03X %-6s slot %d monster $%03X x %3d width %2d column %d%s"
                      % (b, t, s, m, x, w, col, "" if b in reach else "  (no call deals it)"))
                if b in reach:
                    hist[col] = hist.get(col, 0) + 1
        print("reachable columns:", " ".join("%d:%d" % kv for kv in sorted(hist.items())))
    fails = 0
    if a.selftest:
        # 1. the leftmost reachable normal placement, moved to x nibble 0
        col, b, s = min((col, b, s) for b in reach
                        for t, s, m, x, w, col in rom.lines(b) if t == "normal" and b != 0x23F)
        mut = bytearray(data)
        at = rom.formations + b * 15 + 8 + s
        mut[at] &= 0x0F
        got = problems(Rom(mut, sym), reach)
        print("selftest x 0 (battle $%03X slot %d, column %d): %s (%s)"
              % (b, s, col, "red, as it must be" if got else "GREEN: the check is blind",
                 got[0] if got else "nothing flagged"))
        fails += not got
        # 2. the same move on a formation nothing deals: listed, not failed
        un = min(f for f in range(count) if f not in reach and rom.lines(f))
        mut = bytearray(data)
        for s2 in range(6):
            mut[rom.formations + un * 15 + 8 + s2] &= 0x0F
        got = problems(Rom(mut, sym), reach)
        print("selftest unreached battle $%03X at x 0: %s"
              % (un, "green, as it must be" if not got else "RED: " + got[0]))
        fails += bool(got)
        # 3. the model against the live HUD: every width one column short
        #    must disagree with what the lab read
        keep = Rom.width
        Rom.width = lambda self, *args: max(1, keep(self, *args) - 1)
        got = model_problems(rom)
        Rom.width = keep
        print("selftest width off by one: %s (%d live line(s) disagree)"
              % ("red, as it must be" if got else "GREEN: the live table is blind", len(got)))
        fails += not got
    bad = model_problems(rom) + problems(rom, reach)
    for p in bad:
        print("check_hud_columns:", p)
    if bad or fails:
        sys.exit(1)
    n = sum(len(rom.lines(b)) for b in reach)
    lowest = min((col, b) for b in reach for *_, col in rom.lines(b))
    unreached = problems(rom, [f for f in range(count) if f not in reach])
    print("check_hud_columns: %d placements over %d reachable formations, leftmost anchor "
          "column %d (battle $%03X; the mark needs %d); the live table agrees (%d lines); "
          "%d line(s) in an unreached formation left of it%s"
          % (n, len(reach), lowest[0], lowest[1], MIN_COLUMN, len(LIVE), len(unreached),
             (": " + "; ".join(unreached)) if unreached else ""))


if __name__ == "__main__":
    main()
