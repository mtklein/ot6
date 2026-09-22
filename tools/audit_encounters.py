#!/usr/bin/env python3
"""Report whether a field map can roll a random battle, from which
formations, and whether they can be fled.

The chain, with the loads that make each step true:

  * a field map rolls only when byte +5 of its 33-byte map_prop.dat record
    has bit 7 set -- LoadMapProp copies the record to $0520
    (ff6/src/field/map.asm:143-158) and the step handler returns before the
    roll unless $0525 is negative (ff6/src/field/battle.asm:333-347);
  * the pool is sub_battle_group.dat[map], four formation words at
    rand_battle_group.dat[group*8], drawn 31.25/31.25/31.25/6.25%
    (field/battle.asm:398-408);
  * a formation's monsters are battle_monsters.dat (15 B: +1 present mask,
    +2..+7 indices, +14 index high bits);
  * a formation's ARRANGEMENT permissions are battle_prop.dat word [f*4]
    ^ $00F0, which LoadBattleProp parks at $2F48 (battle_main.asm:8216-8220,
    `eor #$00f0 ; toggle battle type flags / sta $2f48`).  ChooseBattleType
    (:7799-7820) masks that byte and rolls one set bit:
        bit 4 ($10)  normal       -- kept by every mask below
        bit 5 ($20)  back attack  -- `and #$d0 ; disable back attacks` (:7809)
        bit 6 ($40)  pincer       -- `and #$b0 ; disable pincer attacks` (:7806)
        bit 7 ($80)  side attack  -- `and #$70 ; disable side attacks` (:7817,
                                     when fewer than 3 allies live, :7811-7816)
    RandBitWithRate (:13794-13814) walks the bits from 7 down with the rates
    at RandBitRateTbl+$10 = $1e,$07,$07,$cf (:13823: side, pincer, back,
    normal, each +1 for the carry) and answers X = 3 side, 2 pincer, 1 back,
    0 normal, which `stx $201f` (:7820) makes the battle type M.battleLayout
    reads.  So with every bit set a roll is side ~12%, pincer ~3%, back ~3%.

What "can they be fled" means here.  The pincer bit is a permission, not an
arrangement: when the roll does arrange the pincer, the fight cannot be fled
at all -- Cmd_2a reads $b1 bit 1 and answers "Can't run away!!"
(battle_main.asm:5729-5731) -- and a mere side attack raises run difficulty
from 2 to 6 per monster (:15584-15594).  So the per-map verdict is one of:
"no encounters", "fleeable" (no formation permits a pincer), or "pincer
possible" (a "flee" drive can stall the cap on a bad roll; budget for a
fight, or pick "tactical").

Why the back and side bits matter to the route (#185, #186): the target
cursor's crossing direction depends on the arrangement (M.battleLayout:
normal crosses LEFT, a back attack RIGHT, a side attack by the party group),
so a map whose pool permits a back or side attack is a map where the
fight driver's cursor geometry is exercised, and one whose pool permits
neither can only ever draw the normal layout.

Usage:  python3 tools/audit_encounters.py [--repo ROOT] [--selftest]
                                          [--summary] [--all] [--route LOG...]
                                          MAP...
Maps are decimal or 0x-hex.  --summary adds the per-arrangement map lists
(which of the named maps can roll a back / side / pincer, and which cannot)
after the per-map reports; --all names every map in map_prop.dat; --route
collects the maps the party actually stood on from the `[tiles] map=N`
trace lines of the given run logs (a regeneration's build/states/*.log),
so the lists are the route's own maps, and implies --summary.  Exit 0; the
tool reports, it does not judge a route.  --selftest exits 1 if the decode
drifts from the pinned values.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys

MAP_PROP = "ff6/src/field/map_prop.dat"            # 33 B/map; +5 bit7 = rolls
SUB_GROUP = "ff6/src/field/sub_battle_group.dat"   # 1 B/map -> group
RAND_GROUP = "ff6/src/field/rand_battle_group.dat" # 4 formation words/group
MONSTERS = "ff6/src/battle/battle_monsters.dat"    # 15 B/formation
BATTLE_PROP = "ff6/src/battle/battle_prop.dat"     # 4 B/formation
MONSTER_NAMES = "ff6/src/text/monster_name_en.json"

MAP_REC = 33
FORM_REC = 15
ODDS = ("31.25%", "31.25%", "31.25%", "6.25%")     # field/battle.asm:398-408

# $2F48 after LoadBattleProp's `eor #$00f0`: one bit per arrangement the
# formation PERMITS (battle_main.asm:7799-7820 ChooseBattleType, quoted in
# the module docstring).  Order is the battle-type index `stx $201f` lands
# (0 normal, 1 back, 2 pincer, 3 side) so the two tables read alike.
ARRANGEMENTS = ((0x10, "normal"), (0x20, "back"), (0x40, "pincer"),
                (0x80, "side"))
ROLLED = ("back", "pincer", "side")     # the three that change the layout
TILES_RE = re.compile(r"\[tiles\] map=(\d+) n=\d+ xy=")   # lib/ot6.lua traceFlush


class Data:
    def __init__(self, root):
        def rd(rel):
            with open(os.path.join(root, rel), "rb") as f:
                return f.read()
        self.map_prop = rd(MAP_PROP)
        self.sub = rd(SUB_GROUP)
        self.rand = rd(RAND_GROUP)
        self.monsters = rd(MONSTERS)
        self.battle_prop = rd(BATTLE_PROP)
        with open(os.path.join(root, MONSTER_NAMES), encoding="utf-8") as f:
            self.names = json.load(f)["text"]

    def rolls(self, m):
        return bool(self.map_prop[m * MAP_REC + 5] & 0x80)

    def group(self, m):
        return self.sub[m]

    def formations(self, g):
        return [int.from_bytes(self.rand[g * 8 + 2 * i: g * 8 + 2 * i + 2],
                               "little") for i in range(4)]

    def resolve(self, word):
        # A RandBattleGroup word's bit 15 ($8000) is a "+Rand(0..3)" flag,
        # stripped and applied at battle_main.asm:8215-8224: the slot draws one
        # of base..base+3 with equal odds.  Without it the raw word (e.g.
        # $80b1) indexes battle_monsters.dat far out of range.  Formations are
        # 9-bit (0..511).  Returns (list-of-formation-ids, is_rand).
        base = word & 0x01FF
        if word & 0x8000:
            return [base + k for k in range(4)], True
        return [base], False

    def bodies(self, f):
        rec = self.monsters[f * FORM_REC:(f + 1) * FORM_REC]
        if len(rec) < FORM_REC:
            return []       # formation index past the table (a stray flag bit)
        seen = {}
        for slot in range(6):
            if rec[1] & (1 << slot):
                sp = rec[2 + slot] | (((rec[14] >> slot) & 1) << 8)
                seen[sp] = seen.get(sp, 0) + 1
        return sorted(seen.items())

    def types(self, f):
        """The $2F48 value LoadBattleProp would park for formation f."""
        w = int.from_bytes(self.battle_prop[f * 4:f * 4 + 2], "little")
        return (w ^ 0x00F0) & 0xF0

    def arrangements(self, f):
        """The set of arrangement names formation f permits."""
        t = self.types(f)
        return {name for bit, name in ARRANGEMENTS if t & bit}

    def pincer(self, f):
        return "pincer" in self.arrangements(f)

    def pool(self, m):
        """Every formation id map m's group can draw (resolved), in slot
        order, with the +Rand spread expanded; [] when the map rolls none."""
        if not self.rolls(m):
            return []
        out = []
        for w in self.formations(self.group(m)):
            out.extend(self.resolve(w)[0])
        return out

    def map_arrangements(self, m):
        """{name: number of the pool's formations permitting it}."""
        counts = {name: 0 for _, name in ARRANGEMENTS}
        for f in self.pool(m):
            for name in self.arrangements(f):
                counts[name] += 1
        return counts

    def map_count(self):
        return len(self.map_prop) // MAP_REC


def arr_label(names):
    """'back+pincer+side' / 'front only' for a permission set."""
    rolled = [name for name in ROLLED if name in names]
    return "+".join(rolled) if rolled else "front only"


def report(data, m):
    if not data.rolls(m):
        print("map %d: NO ENCOUNTERS (map_prop +5 bit 7 clear) -- a step "
              "here still wants a real playBattles mode, because the mode is "
              "what runs if this assumption is ever wrong" % m)
        return
    g = data.group(m)
    any_pincer = False
    print("map %d: rolls random battles, group %d" % (m, g))
    for i, w in enumerate(data.formations(g)):
        forms, is_rand = data.resolve(w)
        for j, f in enumerate(forms):
            arr = data.arrangements(f)
            p = "pincer" in arr
            any_pincer = any_pincer or p
            who = " ".join("%s($%03x)x%d" % (data.names[sp], sp, n)
                           for sp, n in data.bodies(f))
            odds = ODDS[i] + ("+r" if is_rand else "") if j == 0 else "  +rand"
            print("  %8s formation $%03x %-16s %-15s %s"
                  % (odds, f, arr_label(arr),
                     "PINCER POSSIBLE" if p else "fleeable", who))
    counts = data.map_arrangements(m)
    total = len(data.pool(m))
    can = ["%s (%d of %d formations)" % (name, counts[name], total)
           for name in ROLLED if counts[name]]
    cannot = [name for name in ROLLED if not counts[name]]
    if can:
        print("  -> can roll: %s%s" % ("; ".join(can),
              ("  -- cannot roll: " + ", ".join(cannot)) if cannot else ""))
    else:
        print("  -> front only: no formation here permits a back, pincer or "
              "side attack, so the cursor always crosses LEFT to the monsters")
    if any_pincer:
        print("  -> a \"flee\" drive can stall M.FLEE_CAP on a pincer roll "
              "(Cmd_2a, $b1.1): budget a fight or pick \"tactical\"")
    else:
        print("  -> no formation permits a pincer; \"flee\" is safe here")


def summary(data, maps):
    """The per-arrangement map lists over `maps`: which can roll each of
    back / pincer / side, which are front only, which roll nothing."""
    maps = sorted(set(maps))
    # Maps 0-2 are the world maps: their encounters come from the world
    # module's own tables (ff6/src/world/), not map_prop's, so this field
    # decode has nothing to say about them.
    world = [m for m in maps if m < 3]
    maps = [m for m in maps if m >= 3]
    rolling = [m for m in maps if data.rolls(m)]
    quiet = [m for m in maps if not data.rolls(m)]
    counts = {m: data.map_arrangements(m) for m in rolling}

    def ids(ms):
        return " ".join(str(m) for m in ms) if ms else "(none)"

    print("arrangements over %d field map(s), %d rolling random battles%s:"
          % (len(maps), len(rolling),
             ("; world map(s) %s not audited (the world module rolls its "
              "own tables)" % ids(world)) if world else ""))
    for name in ROLLED:
        can = [m for m in rolling if counts[m][name]]
        print("  %-22s %s" % ("%s attack possible:" % name if name != "pincer"
                              else "pincer possible:", ids(can)))
    front = [m for m in rolling if not any(counts[m][n] for n in ROLLED)]
    print("  %-22s %s" % ("front only:", ids(front)))
    for name in ROLLED:
        cannot = [m for m in rolling if not counts[m][name]]
        print("  %-22s %s" % ("cannot roll %s:" % name, ids(cannot)))
    print("  %-22s %s" % ("no encounters:", ids(quiet)))


def route_maps(logs):
    """Map ids the party stood on, from the [tiles] trace lines of run logs
    (the same lines tools/chest_visibility.py collects)."""
    maps = set()
    for path in logs:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                m = TILES_RE.search(line)
                if m:
                    maps.add(int(m.group(1)))
    return sorted(maps)


# ---------------------------------------------------------------- selftest --
# Pinned values, so a drift in any file's layout is a loud failure instead
# of a wrong answer.

def selftest(root):
    data = Data(root)
    ok = True

    def check(what, got, want):
        nonlocal ok
        if got != want:
            ok = False
            print("  SELFTEST FAIL %s: got %r want %r" % (what, got, want))

    check("map 98 rolls", data.rolls(98), True)
    f = data.formations(data.group(98))[0]
    pool = {(data.names[sp], n) for sp, n in data.bodies(f)}
    check("map 98 first formation is the recorded measurement",
          pool, {("Trilium", 1), ("Tusker", 1), ("Cirpius", 2)})
    check("map 98 pool has no pincer",
          any(data.pincer(x) for x in data.formations(data.group(98))), False)

    zozo = [data.pincer(f) for m in (221, 225)
            for f in data.formations(data.group(m))]
    check("zozo pincer count (burndown: 'several')", sum(zozo), 5)

    # The arrangement decode (#186): battle_prop word ^ $00F0 is the $2F48
    # ChooseBattleType masks, bit 5 back / bit 6 pincer / bit 7 side.  Zozo
    # street's SlamDancer solo ($069) permits back and side but not the
    # pincer; the $06c trio permits all three; map 98's whole pool permits
    # every one of back/side and no pincer (the fight the first selftest
    # pins was fleeable, and it still is).
    check("$069 SlamDancer solo: back+side, no pincer",
          data.arrangements(0x069), {"normal", "back", "side"})
    check("$06c Harvester x2 + SlamDancer: all four",
          data.arrangements(0x06c), {"normal", "back", "pincer", "side"})
    check("map 98 pool: back and side in every formation, pincer in none",
          data.map_arrangements(98),
          {"normal": 4, "back": 4, "pincer": 0, "side": 4})
    check("arr_label orders back+pincer+side", arr_label({"side", "back",
          "pincer", "normal"}), "back+pincer+side")
    check("arr_label front only", arr_label({"normal"}), "front only")
    # collecting a route reads the [tiles] lines and nothing else
    import tempfile
    with tempfile.NamedTemporaryFile("w", suffix=".log", delete=False) as t:
        t.write("[ot6] [tiles] map=225 n=2 xy=1:1,2:2\n"
                "[ot6note] 12 [tiles] map=225 n=2 xy=1:1,2:2\n"
                "[ot6] [tiles] map=98 n=1 xy=5:5\n"
                "[ot6] nav: planned 3 steps from (1,1)\n")
        tpath = t.name
    check("route_maps collects the [tiles] maps once each",
          route_maps([tpath]), [98, 225])
    os.unlink(tpath)

    for m in (108, 109, 110):
        check("Returner Hideout map %d encounter-free" % m,
              data.rolls(m), False)

    # The Floating Continent (map 394) is the first map to use the $8000
    # +Rand(0..3) formation flag; without resolve() its raw words index the
    # formation table out of range (the crash this selftest now guards).
    check("FC map 394 rolls", data.rolls(394), True)
    fc_words = data.formations(data.group(394))
    check("FC first slot is a +Rand spread 177..180",
          data.resolve(fc_words[0]), ([177, 178, 179, 180], True))
    fc_pool = sorted({f for w in fc_words for f in data.resolve(w)[0]})
    check("FC pool is forms 177-188", fc_pool, list(range(177, 189)))

    print("audit_encounters selftest: " + ("ok" if ok else "FAILED"))
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--repo", default=os.path.dirname(os.path.dirname(
        os.path.abspath(__file__))))
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--summary", action="store_true",
                    help="after the reports, list the maps per arrangement")
    ap.add_argument("--all", action="store_true",
                    help="every map in map_prop.dat (summary only unless "
                         "maps are also named)")
    ap.add_argument("--route", nargs="+", metavar="LOG",
                    help="run logs whose [tiles] lines name the maps walked")
    ap.add_argument("maps", nargs="*",
                    help="field map ids, decimal or 0x-hex")
    args = ap.parse_args()

    if args.selftest:
        return selftest(args.repo)
    if not (args.maps or args.all or args.route):
        print("audit_encounters: name at least one map (or --all, --route "
              "LOG..., --selftest); see --help for the decode this reports")
        return 2

    data = Data(args.repo)
    named = []
    for s in args.maps:
        m = int(s, 0)
        if not 0 <= m * MAP_REC + 5 < len(data.map_prop):
            print("map %d: out of range" % m)
            continue
        named.append(m)
    for m in named:
        report(data, m)
    pool = list(named)
    if args.route:
        walked = route_maps(args.route)
        print("route: %d map(s) walked per the [tiles] lines of %d log(s)"
              % (len(walked), len(args.route)))
        pool.extend(walked)
    if args.all:
        pool.extend(range(data.map_count()))
    if args.summary or args.route or args.all:
        summary(data, pool)
    return 0


if __name__ == "__main__":
    sys.exit(main())
