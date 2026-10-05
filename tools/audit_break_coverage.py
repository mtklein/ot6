#!/usr/bin/env python3
"""audit_break_coverage.py -- which encounters can the party not chip?

Walks every battle-enabled field map's random pool (SubBattleGroup ->
RandBattleGroup -> BattleMonsters) plus the world-map sector pools, joins
each species against the shipped Ot6ShieldTbl (authored rows), the
generated break floor (floor classes), and vanilla's element bits, and
flags:

  UNAUTHORED  species fought on the WoB route that ride the generated
              floor (the Sealed Gate condition -- nobody validated them)
  NO-KEY      formations where no present species is chippable by the
              broad party kit (slash|pierce|bludg classes; fire/ice/bolt
              elements once espers exist)

Pure data, no emulator.  The Sealed Gate shipped exactly this hole; this
audit exists so the next one is found by grep, not by fourteen wipes.

THE RATCHET (owner, 2026-09-01), two tiers:

1. THE FLOOR INVARIANT, game-wide and absolute: zero completely keyless
   formations anywhere (the Cirpius/Rhinox condition can never ship
   again).  This is what the build gate enforces today.  NOTE HONESTLY:
   unclaimed content passes this tier VACUOUSLY -- the floor generator
   hands every species some class and the broad-kit model accepts most
   of them.  Passing tier 1 is NOT "tuned".

2. THE TUNING CLAIM: the areas play has backed, and everything
   battle-enabled outside it is reported UNCLAIMED/UNTUNED so vacuous
   passes can never be mistaken for verified ones.  The planned
   tightening applies the per-era party-hands table (weapon-classes.md's
   coverage rule) strictly within the claim.

   The claim is DERIVED from what the route fought (#287), not a hand
   list: the generator logs in build/states/*.log name each battle's
   formation (the runner's `[seed] ... battle` lines with `g<formation>`,
   the walkers' `[outcome] battle $<formation>`) and, by the `[tiles]`
   line that follows it (flushed as the party leaves a map), the map it
   was fought on.  A field map is claimed when a formation of its own pool
   was fought there.  A world sector byte (world_battle_group.dat, bytes
   0-255 the World of Balance, 256-511 the World of Ruin; field/battle.asm
   CheckBattleWorld indexes it world*256 + (y & $E0) + ((x >> 3) & $1C) +
   the terrain's group) is claimed when a formation of its group was
   fought on that world's map and, once the [tiles] trace records world
   coordinates (#288), the party walked that sector; until then a group
   shared by a played sector and an unplayed one claims both.  The hand list this
   replaced claimed fifteen World of Ruin maps nobody had visited and the
   whole WoB overworld (Triangle Island, the airship-only isles), and
   missed Esper Mountain and the Floating Continent.  With no logs the
   claim is empty, and the audit says so.
"""

import glob, json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def rd(p): return open(os.path.join(ROOT, p), 'rb').read()

rom   = rd('build/ot6.sfc')
props = rd('ff6/src/field/map_prop.dat')
sbg   = rd('ff6/src/field/sub_battle_group.dat')
rbg   = rd('ff6/src/field/rand_battle_group.dat')
wbg   = rd('ff6/src/field/world_battle_group.dat')
bm    = rd('ff6/src/battle/battle_monsters.dat')
mp    = rd('ff6/src/battle/monster_prop.dat')

# monster names from the dat (2-byte header skip heuristics avoided: the
# json carries asset metadata, the dat is fixed 10-byte records)
nm_dat = rd('ff6/src/text/monster_name_en.dat')
def mname(sid):
    rec = nm_dat[sid*10:(sid+1)*10]
    s = ''
    for c in rec:
        if 0x80 <= c <= 0x99: s += chr(65+c-0x80)
        elif 0x9A <= c <= 0xB3: s += chr(97+c-0x9A)
        elif 0xB4 <= c <= 0xBD: s += chr(48+c-0xB4)
        elif c == 0xFF: s += ' '
        else: s += '.'
    return s.strip() or f'${sid:03X}'

# ---- the shipped Ot6ShieldTbl, found in the ROM by its known row bytes --
# locate via the whelk head row ($0134, 4, PIERCE=0x02) preceded by the
# guard row ($0000, 2, 0x02): search for the full early sequence.
import re
def find_shield_tbl():
    # rows are (word species)(byte shields)(byte mask); the table opens with
    # species $0000 shields 2 mask 2 then $0019 shields 3 mask 2
    key = bytes([0x00,0x00,2,0x02, 0x19,0x00,3,0x02])
    i = rom.find(key)
    assert i >= 0, 'Ot6ShieldTbl signature not found'
    tbl = {}
    a = i
    while True:
        sp = rom[a] | (rom[a+1] << 8)
        if sp == 0xFFFF: break
        # first row wins, like Ot6SeedShields; a second row for a species
        # is dead code and the build gate (tools/check_shield_rows.py)
        # refuses it, so this audit refuses it too rather than pick a side
        assert sp not in tbl, f'Ot6ShieldTbl lists species ${sp:04X} twice (rom+${a:06X}); first row wins in the engine'
        tbl[sp] = (rom[a+2], rom[a+3])
        a += 4
    return tbl
AUTHORED = find_shield_tbl()

# ---- the generated floor classes ----------------------------------------
floor = {}
with open(os.path.join(ROOT, 'ff6/src/battle/ot6_break_floor.inc')) as f:
    i = 0
    for line in f:
        line = line.strip()
        if line.startswith('.byte'):
            for tok in line[5:].split(','):
                tok = tok.strip()
                val = {'OT6_SLASH':1,'OT6_PIERCE':2,'OT6_BLUDG':4,'OT6_SPECIAL':8}.get(tok)
                if val is None:
                    try: val = int(tok.replace('$','0x'), 16) if '$' in tok else int(tok)
                    except ValueError: continue
                floor[i] = val; i += 1

# ---- THE TUNING CLAIM, from the route's own battles (#287) --------------
SEED_BATTLE = re.compile(r'^\[ot6\] \[seed\] (?:first )?battle: .*?key be[0-9A-F]{2}-g([0-9A-F]{4})')
OUTCOME = re.compile(r'^\[ot6\] .*\[outcome\] battle \$([0-9A-F]{3}) ')
TILES = re.compile(r'^\[ot6\] \[tiles\] map=(\d+) ')


XY = re.compile(r'xy=(\S+)')


def fought_by_map(paths):
    """{map: {formation}}: each battle a log names, on the map whose
    [tiles] line comes next (the trace flushes a map as the party leaves
    it, and a battle leaves $1F64 on its field map).  Also fills WALKED
    with each world's walked sector bases."""
    out = {}
    for path in paths:
        pending = set()
        with open(path, errors='replace') as f:
            for line in f:
                m = SEED_BATTLE.match(line) or OUTCOME.match(line)
                if m:
                    pending.add(int(m.group(1), 16))
                    continue
                t = TILES.match(line)
                if t and int(t.group(1)) in (0, 1):
                    w = int(t.group(1))
                    for xy in XY.search(line).group(1).split(','):
                        x, _, y = xy.partition(':')
                        if x.isdigit() and y.isdigit() and (int(x), int(y)) != (0, 0):
                            TILESEEN.setdefault(w, set()).add((int(x), int(y)))
                            WALKED.setdefault(w, set()).add(
                                w * 256 + (int(y) & 0xE0) + ((int(x) >> 3) & 0x1C))
                if t and pending:
                    out.setdefault(int(t.group(1)), set()).update(pending)
                    pending = set()
    return out


# {world: {sector base byte}} walked, from [tiles] lines with world
# coordinates; empty for a world whose logs carry none (#288)
WALKED = {}
TILESEEN = {}


LOGS = sorted(glob.glob(os.path.join(ROOT, 'build', 'states', '*.log')))
FOUGHT = fought_by_map(LOGS)
# a world's walked sectors count once its logs record the world trace
# (#288): the blind trace wrote only the field coordinates of map-change
# frames under map=0/1, 56 distinct tiles across the 217 logs of
# 2026-10-05, where one World of Ruin leg alone walks 221
WALKED = {w: secs for w, secs in WALKED.items() if len(TILESEEN[w]) >= 100}


def group_forms(g):
    return {rbg[g*8+i] | (rbg[g*8+i+1] << 8) for i in range(0, 8, 2)}


CLAIMED_FIELD = {m for m in range(len(props)//33)
                 if props[m*33+5] & 0x80
                 and group_forms(sbg[m]) & FOUGHT.get(m, set())}
CLAIMED_WORLD_SECTORS = {sec for sec in range(512)
                         if wbg[sec] != 0xFF
                         and group_forms(wbg[sec]) & FOUGHT.get(sec // 256, set())
                         and (sec // 256 not in WALKED
                              or sec & ~3 in WALKED[sec // 256])}

PARTY_CLASSES = 0x01 | 0x02 | 0x04          # slash+pierce+bludg, broadly held
PARTY_ELEMS   = 0x01 | 0x02 | 0x04          # fire+ice+bolt once espers exist

def species_key(sid):
    """(authored?, chippable-by-broad-kit?)"""
    weak = mp[sid*32+25]
    if sid in AUTHORED:
        sh, mask = AUTHORED[sid]
        return True, (mask & PARTY_CLASSES) != 0 or (weak & PARTY_ELEMS) != 0
    fl = floor.get(sid, 1)
    return False, (fl & PARTY_CLASSES) != 0 or (weak & PARTY_ELEMS) != 0

def formation_species(f):
    rec = bm[f*15:(f+1)*15]
    out = []
    if len(rec) < 15: return out   # a group slot past the formation table
    for s in range(6):
        if rec[1] & (1 << s):
            out.append(rec[2+s] | (((rec[14] >> s) & 1) << 8))
    return out

NOKEY = [0]
def pool_report(tag, forms):
    lines = []
    for f in sorted(set(forms)):
        sps = formation_species(f)
        if not sps: continue
        keys = [species_key(s) for s in sps]
        unauth = [mname(s) for s, (a, _) in zip(sps, keys) if not a]
        if not any(ch for _, ch in keys):
            lines.append(f'  NO-KEY  form {f}: ' + ', '.join(mname(s) for s in sps))
            NOKEY[0] += 1
        elif unauth:
            lines.append(f'  floor   form {f}: unauthored ' + ', '.join(sorted(set(unauth))))
    return lines

print('== field maps (battle-enabled) ==')
unclaimed = []
for m in range(len(props)//33):
    if not (props[m*33+5] & 0x80): continue
    g = sbg[m]
    forms = [rbg[g*8+i] | (rbg[g*8+i+1] << 8) for i in range(0, 8, 2)]
    lines = pool_report(f'map {m}', forms)
    tag = '' if m in CLAIMED_FIELD else '  [UNCLAIMED/UNTUNED]'
    if m not in CLAIMED_FIELD:
        unclaimed.append(m)
    if lines:
        print(f'map {m:3d} (group {g}):{tag}')
        for l in lines: print(l)

print('== world sectors ==')
seen = set()
for sec in range(512):
    claimed = sec in CLAIMED_WORLD_SECTORS
    g = wbg[sec]
    if g == 0xFF or g in seen: continue
    seen.add(g)
    forms = [rbg[g*8+i] | (rbg[g*8+i+1] << 8) for i in range(0, 8, 2)]
    lines = pool_report(f'sector {sec}', forms)
    if lines:
        tag = '' if claimed else '  [UNCLAIMED/UNTUNED]'
        print(f'world group {g:3d} (first sector {sec}):{tag}')
        for l in lines: print(l)

nfought = sum(len(v) for v in FOUGHT.values())
print(f'tuning claim, from {len(LOGS)} generator log(s) in build/states '
      f'({nfought} map+formation pairs fought): {len(CLAIMED_FIELD)} field '
      f'maps {sorted(CLAIMED_FIELD)}; world sector bytes: '
      f'{len([s for s in CLAIMED_WORLD_SECTORS if s < 256])} of the WoB, '
      f'{len([s for s in CLAIMED_WORLD_SECTORS if s >= 256])} of the WoR '
      f'(walked sectors known for world(s) {sorted(WALKED) or "none"}); '
      f'{len(unclaimed)} battle-enabled maps UNCLAIMED')
if not LOGS:
    print('  (no generator logs: nothing is claimed until the route is played)')

if NOKEY[0]:
    print(f'RATCHET: {NOKEY[0]} no-key formation(s) -- the build gate refuses')
    sys.exit(1)
print('tier-1 floor invariant holds: zero completely keyless formations game-wide')
