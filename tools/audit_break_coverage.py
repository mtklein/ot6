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
"""
import json, os, sys

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
    for s in range(6):
        if rec[1] & (1 << s):
            out.append(rec[2+s] | (((rec[14] >> s) & 1) << 8))
    return out

def pool_report(tag, forms):
    lines = []
    for f in sorted(set(forms)):
        sps = formation_species(f)
        if not sps: continue
        keys = [species_key(s) for s in sps]
        unauth = [mname(s) for s, (a, _) in zip(sps, keys) if not a]
        if not any(ch for _, ch in keys):
            lines.append(f'  NO-KEY  form {f}: ' + ', '.join(mname(s) for s in sps))
        elif unauth:
            lines.append(f'  floor   form {f}: unauthored ' + ', '.join(sorted(set(unauth))))
    return lines

print('== field maps (battle-enabled) ==')
for m in range(len(props)//33):
    if not (props[m*33+5] & 0x80): continue
    g = sbg[m]
    forms = [rbg[g*8+i] | (rbg[g*8+i+1] << 8) for i in range(0, 8, 2)]
    lines = pool_report(f'map {m}', forms)
    if lines:
        print(f'map {m:3d} (group {g}):')
        for l in lines: print(l)

print('== world sectors (WoB) ==')
seen = set()
for sec in range(256):
    g = wbg[sec]
    if g == 0xFF or g in seen: continue
    seen.add(g)
    forms = [rbg[g*8+i] | (rbg[g*8+i+1] << 8) for i in range(0, 8, 2)]
    lines = pool_report(f'sector {sec}', forms)
    if lines:
        print(f'world group {g:3d} (first sector {sec}):')
        for l in lines: print(l)
