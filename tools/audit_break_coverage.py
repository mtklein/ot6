#!/usr/bin/env python3
"""audit_break_coverage.py -- which encounters can the party not chip?

Walks every battle-enabled field map's random pool (SubBattleGroup ->
RandBattleGroup -> BattleMonsters) plus the world-map sector pools, joins
each species against the shipped Ot6ShieldTbl (authored rows), the
generated break floor (floor classes), and vanilla's element bits, and
flags:

  UNAUTHORED  species fought on the WoB route that ride the generated
              floor (the Sealed Gate condition -- nobody validated them)
  NO-KEY      formations where no present species is chippable by any
              hand (tier 1), or by the hands the party that walked there
              held (tier 2)

Pure data, no emulator.  The Sealed Gate shipped exactly this hole; this
audit exists so the next one is found by grep, not by fourteen wipes.

THE RATCHET (owner, 2026-09-01), two tiers:

1. THE FLOOR INVARIANT, game-wide and absolute: zero completely keyless
   formations anywhere (the Cirpius/Rhinox condition can never ship
   again).  This is what the build gate enforces today.  NOTE HONESTLY:
   unclaimed content passes this tier VACUOUSLY -- every authored row
   names some class and this tier accepts any class a recruit can swing.
   Passing tier 1 is NOT "tuned".

2. THE TUNING CLAIM: the areas play has backed, and everything
   battle-enabled outside it is reported UNCLAIMED/UNTUNED so vacuous
   passes can never be mistaken for verified ones.  Within the claim the
   per-stage party-hands table applies (weapon-classes.md's coverage rule):
   see THE PARTY-HANDS MODEL below.

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

THE PARTY-HANDS MODEL (six classes, v0.51, #566).  Through v0.50 one mask
stood for every party everywhere: PARTY_CLASSES = slash|pierce|bludgeon,
"broadly held", with special left out because only Setzer's and Relm's
oddball weapons carried it.  Under six classes no such mask exists: each
class is a few recruits' own weapon family (sword, dagger, fist, arcane,
katana, spear; ot6_class.asm), a species keeps as many weapon weaknesses as
it had, and whether an encounter has a key depends on WHO walks into it.
So the model is split the way the two tiers always were:

  tier 1 (the gate, ROM data only) asks the absolute question: does ANY
    class, or fire/ice/bolt, chip a gauged body of the formation.  Every
    class is in some recruit's hands, so "nobody can chip it" now means
    "no body in it takes any class".  This is the one place the model is
    wider in form than v0.50's: it counts Arcane and Dagger, the classes
    that inherited special's species (and the rods', arcs' and daggers').
    It cannot be narrower without knowing who is there, and tier 2 knows.

  tier 2 (the claim, from the play's logs) asks the question the coverage
    rule asks: did the story party at that point hold a key.  The play
    records, a battle, what the seated members held as it opened (#566's
    `[keys]` line: each member's hand items and class-bearing skills, the
    Tools and thrown edges in the bag).  This audit re-reads that record
    under THIS tree's class tables (Ot6WeapClassTbl, Ot6SkillClassTbl,
    OT6_CLS_THIEF), never the masks the playing ROM printed, and holds
    each stage -- a map and the party that fought on it -- to it twice:
      fought  every battle the play fought there: its bodies' rows against
              the kit the party held as it opened
      pool    every formation the map's pool can deal: against each kit a
              party was seen holding on that map
    A formation no class of the kit chips is STAGE NO-KEY when no gauged
    body is fire/ice/bolt-weak either, and STAGE ELEMENT-ONLY when one is:
    the log records no elements, so whether that party carried the
    element (an esper, Terra's Fire, a rod) is the reader's to check.
    v0.50's model called both "keyed" on fire/ice/bolt alone, everywhere.

  THE HOLDER RULE (owner, 2026-11-23: "we don't want just one particular
  character to be required to get through fights").  Tier 2 also holds
  every stage of the line to it: for every gauged species with a class row
  that a stage can be dealt, the row's classes are REALLY held (signature
  weapon or command, not "could equip": tools/proto_six/classes.py
  SIGNATURE) by at least two characters the player can field there, or by
  one the story forces into the party (tools/proto_six/stages.py STAGES:
  roster and forced, by leg of the line; tools/ot6_class.py holder_rule,
  the rule split.py's HOLDERS step applies to the species the route met).
  A stage's legs are the generator logs' own names; what it can be dealt
  is every formation of the pool of each map and world group a leg fought
  on, and every formation it fought (the event battles), not only the
  bodies the route happened to meet.  Each (stage, species) the rule is
  not met for is a HOLDER line; --strict-holders makes them fail the run.
  The Veldt's legs are no stage (it re-deals formations from everywhere),
  and the magic-only tower swings no weapon.

  "May only tighten" (configure.py, at the gate's edge).  Tier 2 refuses
  what v0.50's model accepted: a formation keyed only by a class the party
  there did not hold (v0.50 counted slash, pierce and bludgeon as held by
  a lone Celes).  Tier 1 accepts in form what v0.50 refused: a formation
  whose only key is a class that came from special.  On the shipped rows
  that set is empty (every formation v0.50 accepted held a slash, pierce,
  bludgeon or fire/ice/bolt key, and the split gave each of those one
  child class), and --selftest holds the gate to the mutants that matter:
  a formation with no class and no fire/ice/bolt weakness is refused, a
  gauged body's row emptied is refused, a party stripped of its kit is
  refused.

Usage:
  python3 tools/audit_break_coverage.py --gate       the build gate (tier 1)
  python3 tools/audit_break_coverage.py              tier 1 and the claim,
        [--logs DIR] [--stages] [--strict]           from build/states/*.log
        [--strict-holders]                           (or DIR/*.log); --stages
                                                     prints each stage's hands;
                                                     --strict fails on a
                                                     STAGE NO-KEY,
                                                     --strict-holders on a
                                                     HOLDER line
  python3 tools/audit_break_coverage.py --selftest
"""

import argparse, glob, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import ot6_class  # noqa: E402


def rd(p): return open(os.path.join(ROOT, p), 'rb').read()
def rt(p): return open(os.path.join(ROOT, p), encoding='utf-8').read()


rom   = rd('build/ot6.sfc')
props = rd('ff6/src/field/map_prop.dat')
sbg   = rd('ff6/src/field/sub_battle_group.dat')
rbg   = rd('ff6/src/field/rand_battle_group.dat')
wbg   = rd('ff6/src/field/world_battle_group.dat')
bm    = rd('ff6/src/battle/battle_monsters.dat')
mp    = rd('ff6/src/battle/monster_prop.dat')

# the weapon classes, the weapons' and skills' classes: the source's own
C = ot6_class.read(ROOT)
WEAPON_CLASS = ot6_class.weapon_classes(rt(ot6_class.CLASS_ASM), C)
SKILL_CLASS = ot6_class.skill_classes(rt(ot6_class.CLASS_ASM), C)

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

# ---- the shipped Ot6ShieldTbl, found in the ROM by its source's rows -----
# rows are (word species)(byte shields)(byte mask).  The table is found by
# the source table's own opening rows (ot6_class.rom_table_at), the way
# check_shield_rows.py finds it: through v0.50 the search key was spelled
# here as bytes of two rows' class masks, and the six-class split moved both.
def find_shield_tbl():
    source = ot6_class.shield_rows(rt(ot6_class.HUD_ASM), C)
    tbl = {}
    for sp, sh, mask, a in ot6_class.rom_rows(rom, ot6_class.rom_table_at(rom, source)):
        # first row wins, like Ot6SeedShields; a second row for a species
        # is dead code and the build gate (tools/check_shield_rows.py)
        # refuses it, so this audit refuses it too rather than pick a side
        assert sp not in tbl, f'Ot6ShieldTbl lists species ${sp:04X} twice (rom+${a:06X}); first row wins in the engine'
        assert mask & ~C.mask == 0, f'Ot6ShieldTbl species ${sp:04X}: class byte ${mask:02X} leaves OT6_CLASSES ${C.mask:02X}'
        tbl[sp] = (sh, mask)
    return tbl
AUTHORED = find_shield_tbl()

# ---- the generated floor classes ----------------------------------------
floor = dict(enumerate(ot6_class.floor_classes(rt(ot6_class.FLOOR_INC), C)))

# ---- THE TUNING CLAIM, from the route's own battles (#287) --------------
SEED_BATTLE = re.compile(r'^\[ot6\] \[seed\] (?:first )?battle: .*?key be[0-9A-F]{2}-g([0-9A-F]{4})')
OUTCOME = re.compile(r'^\[ot6\] .*\[outcome\] battle \$([0-9A-F]{3}) ')
OUTCOME_CHAR = re.compile(r'char (\d+) ')       # the seated members an [outcome] line's reward names
TILES = re.compile(r'^\[ot6\] \[tiles\] map=(\d+) ')
# #566's instrument (tools/tests/lib/ot6.lua M.keyLine): what the seated
# members held as a battle opened, and the bodies that stood
KEYS = re.compile(r'^\[ot6\] .*\[keys\] form=\$([0-9A-F]+) .*? bodies=(\S*) gauged=\d+ nohand=\d+ nokit=\d+'
                  r' src=(\S*) bag=(\S*)\s*$')


XY = re.compile(r'xy=(\S+)')
ACTORS = ['TERRA', 'LOCKE', 'CYAN', 'SHADOW', 'EDGAR', 'SABIN', 'CELES', 'STRAGO', 'RELM', 'SETZER',
          'MOG', 'GAU', 'GOGO', 'UMARO', 'BANON', 'LEO']


def kit_of(src, bag):
    """(members, hands, kit) of a [keys] line's `src=` and `bag=` fields,
    re-read under this tree's class tables.  src is one entry a seated
    member, `c<char>` then `:M` (TERRA's TekMissile, in Magitek armor: no
    hand) or `:r<item>` and `:l<item>` (the hands, $FF empty), `:B` Blitz
    (Pummel), `:S` SwdTech (Dispatch), `:tools` and `:throw` (the bag's
    Tools $A3-$AA; its stars $41-$43 and skeans $AB-$AD), `:T` a thief's
    hit.  GAU's empty hand is his fangs.  A null-break weapon chips nothing
    and holds nothing."""
    def weapon(i):
        b = WEAPON_CLASS[i]
        return 0 if b & C.nullbrk else b & C.mask

    def skill(i):
        return SKILL_CLASS.get(i, 0) & C.mask

    bag_ids = {int(x, 16) for x in bag.split('/') if x}
    members, hands, kit = [], 0, 0
    for ent in src.split(','):
        if not ent:
            continue
        parts = ent.split(':')
        m = re.fullmatch(r'c(\d+)', parts[0])
        assert m, f'[keys] src entry {ent!r}: no member'
        members.append(int(m.group(1)))
        for p in parts[1:]:
            if re.fullmatch(r'[rl][0-9A-F]{2}', p):
                # GAU's empty hand is his fangs (Ot6WeaponClass, OT6_CLS_FANG;
                # ot6.lua M.handClass), not the empty hand's class
                if members[-1] == ACTORS.index('GAU') and p[1:] == 'FF' and 'OT6_CLS_FANG' in C.consts:
                    hands |= C.consts['OT6_CLS_FANG'] & C.mask
                else:
                    hands |= weapon(int(p[1:], 16))
            elif p == 'M':
                kit |= skill(0x8A)
            elif p == 'B':
                kit |= skill(0x5D)
            elif p == 'S':
                kit |= skill(0x55)
            elif p == 'tools':
                for i in bag_ids & set(range(0xA3, 0xAB)):
                    kit |= weapon(i)
            elif p == 'throw':
                for i in bag_ids & set(range(0x41, 0x44)):
                    kit |= weapon(i)
                for i in bag_ids & set(range(0xAB, 0xAE)):
                    kit |= skill(0x51 + i - 0xAB)
            elif p == 'T':
                kit |= C.consts['OT6_CLS_THIEF'] & C.mask
            else:
                raise AssertionError(f'[keys] src entry {ent!r}: unknown part {p!r} (ot6.lua M.keyLine changed?)')
    return tuple(sorted(members)), hands, kit | hands


def fought_by_map(paths):
    """({map: {formation}}, {map: [key record]}, {leg: {map: {formation}}},
    {leg: {member names seen fighting}}): each battle a log names, on the map
    whose [tiles] line comes next (the trace flushes a map as the party
    leaves it, and a battle leaves $1F64 on its field map).  A key record is
    (formation, members, kit, [species standing]); a leg is a log's own name
    (build/states/<leg>.log).  Also fills WALKED with each world's walked
    sector bases."""
    out, keys, legs, seen = {}, {}, {}, {}
    for path in paths:
        leg = os.path.basename(path)[:-4]
        pending, pkeys = set(), []
        with open(path, errors='replace') as f:
            for line in f:
                m = SEED_BATTLE.match(line) or OUTCOME.match(line)
                if m:
                    pending.add(int(m.group(1), 16))
                    for c in OUTCOME_CHAR.findall(line) if '[outcome]' in line else ():
                        if int(c) < len(ACTORS):
                            seen.setdefault(leg, set()).add(ACTORS[int(c)])
                    continue
                k = KEYS.match(line)
                if k:
                    members, _hands, kit = kit_of(k.group(3), k.group(4))
                    sps = [int(b.split(':')[1][1:], 16) for b in k.group(2).split(',') if b]
                    pkeys.append((int(k.group(1), 16), members, kit, sps))
                    seen.setdefault(leg, set()).update(ACTORS[c] for c in members if c < len(ACTORS))
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
                    legs.setdefault(leg, {}).setdefault(int(t.group(1)), set()).update(pending)
                    pending = set()
                if t and pkeys:
                    keys.setdefault(int(t.group(1)), []).extend(pkeys)
                    pkeys = []
    return out, keys, legs, seen


# {world: {sector base byte}} walked, from [tiles] lines with world
# coordinates; empty for a world whose logs carry none (#288)
WALKED = {}
TILESEEN = {}


def expand(word):
    """A RandBattleGroup word's formation ids: bit 15 ($8000) is the
    "+Rand(0..3)" flag (battle_main.asm:8215-8224, audit_encounters.py's
    resolve), so the slot draws one of base..base+3; formations are 9-bit."""
    base = word & 0x01FF
    return [base + k for k in range(4)] if word & 0x8000 else [base]


def group_words(g):
    return [rbg[g*8+i] | (rbg[g*8+i+1] << 8) for i in range(0, 8, 2)]


def group_forms(g):
    return {f for w in group_words(g) for f in expand(w)}


# Tier 1's hands: every class (each is some recruit's weapon family; see THE
# PARTY-HANDS MODEL above for why this, and where it is wider than v0.50's
# slash|pierce|bludgeon), read from ot6_class.asm, not spelled here.
PARTY_CLASSES = C.mask
PARTY_ELEMS   = 0x01 | 0x02 | 0x04          # fire+ice+bolt once espers exist

# The Fanatics' Tower is magic-only (battle switch $38, set by map 363's init
# and cleared by 362's: route-wor-thamasa.md finding 3): no Fight, so no
# class lands there, and the kit is spells -- among them OT6's Break, which
# chips any shield whatever the body's keys (ot6_breakspell.asm).  Every
# shielded body there is keyed by it.
MAGIC_ONLY_MAPS = {359, 360, 361, 363, 364, 365, 366, 367, 368, 369, 370}


class Tree:
    """The break data a verdict reads, so --selftest can mutate a copy."""

    def __init__(self, authored, floor_, weak=None):
        self.authored, self.floor = authored, floor_
        self.weak = weak if weak is not None else (lambda sid: mp[sid*32+25])

    def species_key(self, sid, hands=None, magic_only=False):
        """(authored?, how the kit chips it): 'class', 'element', or None.
        An authored row of 0 shields (no gauge: the body takes full damage
        from the start) has nothing to break, so it is never what makes a
        formation keyless: 'nogauge'."""
        hands = PARTY_CLASSES if hands is None else hands
        weak = self.weak(sid)
        if sid in self.authored:
            sh, mask = self.authored[sid]
            if sh == 0 or magic_only:
                return True, 'nogauge'
            a = True
        else:
            mask, a = self.floor.get(sid, 0), False
        if mask & hands:
            return a, 'class'
        if weak & PARTY_ELEMS:
            return a, 'element'
        return a, None

    def verdict(self, sps, hands=None, magic_only=False):
        """How the best-keyed body of a formation is chipped: 'nogauge',
        'class', 'element', or None (keyless)."""
        got = {self.species_key(s, hands, magic_only)[1] for s in sps}
        for how in ('nogauge', 'class', 'element'):
            if how in got:
                return how
        return None

    def row_text(self, sid):
        if sid in self.authored:
            sh, mask = self.authored[sid]
            return f'{mname(sid)}[{C.names(mask, none="-")}]' if sh else f'{mname(sid)}[no gauge]'
        return f'{mname(sid)}[floor {C.names(self.floor.get(sid, 0), none="-")}]'


TREE = Tree(AUTHORED, floor)


def formation_species(f):
    rec = bm[f*15:(f+1)*15]
    out = []
    if len(rec) < 15: return out   # a group slot past the formation table
    for s in range(6):
        if rec[1] & (1 << s):
            out.append(rec[2+s] | (((rec[14] >> s) & 1) << 8))
    return out


def pool_report(tree, forms, magic_only=False):
    """(lines, number of NO-KEY formations) for one pool, under tier 1."""
    lines, nokey = [], 0
    for f in sorted(set(forms)):
        sps = formation_species(f)
        if not sps: continue
        unauth = [mname(s) for s in sps if not tree.species_key(s, None, magic_only)[0]]
        if tree.verdict(sps, None, magic_only) is None:
            lines.append(f'  NO-KEY  form {f}: ' + ', '.join(mname(s) for s in sps))
            nokey += 1
        elif unauth:
            lines.append(f'  floor   form {f}: unauthored ' + ', '.join(sorted(set(unauth))))
    return lines, nokey


def pools():
    """[(kind, n, group)]: every battle-enabled field map, every world sector."""
    return ([('map', m, sbg[m]) for m in range(len(props)//33) if props[m*33+5] & 0x80]
            + [('sector', sec, wbg[sec]) for sec in range(512) if wbg[sec] != 0xFF])


def tier1(tree, claimed_field=None, claimed_sectors=None, quiet=False):
    """Print tier 1's findings; return (NO-KEY count, unclaimed maps)."""
    say = (lambda *a: None) if quiet else print
    gate = claimed_field is None
    nokey, unclaimed = 0, []
    say('== field maps (battle-enabled) ==')
    for m in range(len(props)//33):
        if not (props[m*33+5] & 0x80): continue
        g = sbg[m]
        lines, n = pool_report(tree, sorted(group_forms(g)), m in MAGIC_ONLY_MAPS)
        nokey += n
        tag = '' if gate or m in claimed_field else '  [UNCLAIMED/UNTUNED]'
        if not gate and m not in claimed_field:
            unclaimed.append(m)
        if lines:
            say(f'map {m:3d} (group {g}):{tag}')
            for l in lines: say(l)
    say('== world sectors ==')
    seen = set()
    for sec in range(512):
        g = wbg[sec]
        if g == 0xFF or g in seen: continue
        seen.add(g)
        lines, n = pool_report(tree, sorted(group_forms(g)))
        nokey += n
        if lines:
            tag = '' if gate or sec in claimed_sectors else '  [UNCLAIMED/UNTUNED]'
            say(f'world group {g:3d} (first sector {sec}):{tag}')
            for l in lines: say(l)
    return nokey, unclaimed


def party_name(members):
    return '+'.join(ACTORS[c] if c < len(ACTORS) else f'c{c}' for c in members)


def stage_findings(tree, keys, claimed_field):
    """Tier 2's party-hands check.  Returns (findings, stages): findings are
    (severity, where, formation, members, kit, species, how) with severity
    'NO-KEY' or 'ELEMENT-ONLY' and how 'fought' or 'pool'; stages is
    {(map, members): [kit of each battle fought there]}."""
    stages, findings, seen = {}, [], set()

    def judge(how, m, f, members, kit, sps):
        v = tree.verdict(sps, kit, m in MAGIC_ONLY_MAPS)
        if v in ('class', 'nogauge'):
            return
        key = (how, m, f, members, kit, tuple(sorted(set(sps))))
        if key in seen:
            return
        seen.add(key)
        findings.append(('ELEMENT-ONLY' if v == 'element' else 'NO-KEY', m, f, members, kit, sps, how))

    for m in sorted(keys):
        for f, members, kit, sps in keys[m]:
            stages.setdefault((m, members), []).append(kit)
            judge('fought', m, f, members, kit, sps)
    # the pool: a field map's own formations, against each kit a party held
    # on it.  The world maps are one map id a world: a party there is not
    # known to have walked a given sector, so the world is held to what it
    # fought only.
    for (m, members), kits in sorted(stages.items()):
        if m in (0, 1) or m not in claimed_field:
            continue
        for kit in sorted(set(kits)):
            for f in sorted(group_forms(sbg[m])):
                sps = formation_species(f)
                if sps:
                    judge('pool', m, f, members, kit, sps)
    return findings, stages


def print_stage(tree, findings, stages, nlogs, show_stages):
    nkeys = sum(len(v) for v in stages.values())
    if not nkeys:
        print(f'party hands (tier 2): none of the {nlogs} log(s) carries a [keys] line (played before '
              f"#566's instrument): the per-stage check has nothing to read until the line is replayed")
        return 0
    if show_stages:
        print('== stages: the party that fought on a map, and the classes it held as its battles opened ==')
        for (m, members), kits in sorted(stages.items()):
            every, some = C.mask, 0
            for k in kits:
                every, some = every & k, some | k
            extra = '' if every == some else f'; in some, also {C.names(some & ~every)}'
            where = f'map {m:3d}' if m > 1 else f'world {m}'
            print(f'  {where} {party_name(members):<28} {len(kits):3d} battle(s): '
                  f'{C.names(every, none="no class")} in all{extra}')
    order = {'NO-KEY': 0, 'ELEMENT-ONLY': 1}
    for sev, m, f, members, kit, sps, how in sorted(findings, key=lambda x: (order[x[0]], x[1], x[2], x[6])):
        where = f'map {m}' if m > 1 else f'world {m}'
        print(f'  STAGE {sev} ({how}) {where} form {f}: {party_name(members)} held '
              f'{C.names(kit, none="no class")}; ' + ', '.join(tree.row_text(s) for s in dict.fromkeys(sps)))
    n = {s: len([x for x in findings if x[0] == s]) for s in order}
    nf = {s: len([x for x in findings if x[0] == s and x[6] == 'fought']) for s in order}
    print(f'party hands (tier 2), from {nkeys} [keys] line(s) over {len(stages)} stage(s) (a map and the party '
          f'that fought on it): {n["NO-KEY"]} STAGE NO-KEY ({nf["NO-KEY"]} fought, the rest pool formations), '
          f'{n["ELEMENT-ONLY"]} STAGE ELEMENT-ONLY ({nf["ELEMENT-ONLY"]} fought): no class of the kit chips a '
          f'gauged body; ELEMENT-ONLY has a fire/ice/bolt-weak one, and the log does not say the party carried it')
    return n['NO-KEY']


def holder_findings(tree, legs, seen, order=None):
    """THE HOLDER RULE, stage by stage.  Returns (findings, checked, stages
    met): findings is {(stage's first leg, species): [why, roster, forced,
    {(where, formation)}]} for every gauged species with a class row that a
    stage can be dealt -- every formation of the pool of each map (and world
    group) a leg of the stage fought on, and every formation it fought --
    whose row the rule is not met for there.  The Veldt's legs deal
    formations from everywhere the party has been and are no stage of their
    own; the magic-only tower swings no weapon."""
    K, S = ot6_class.grouping()
    order = order if order is not None else S.line_order(os.path.join(ROOT, 'build.ninja'))
    stage = S.stage_of(order, seen)
    found, checked, met = {}, set(), []
    for leg in order:
        st = stage.get(leg)
        if leg not in legs or st is None or leg in S.VELDT:
            continue
        first, roster, forced, magitek = st
        if first not in met:
            met.append(first)
        # the stage table against the play: a member the leg's battles seated
        # whom the stage says the player cannot field there (a guest aside)
        extra = sorted(seen.get(leg, set()) - roster)
        if extra:
            STAGE_DRIFT.append(f'  STAGE ROSTER leg {leg} (stage {first}: {", ".join(sorted(roster))}): the play '
                               f'seated {", ".join(extra)} there, whom the stage does not field')
        forms = {}
        for m, fs in sorted(legs[leg].items()):
            if m in MAGIC_ONLY_MAPS:
                continue
            if m in (0, 1):
                for g in sorted({wbg[sec] for sec in range(m * 256, m * 256 + 256)
                                 if wbg[sec] != 0xFF and group_forms(wbg[sec]) & fs}):
                    for f in group_forms(g):
                        forms.setdefault(f, f'world {m} group {g}')
            elif props[m*33+5] & 0x80 and group_forms(sbg[m]) & fs:
                for f in group_forms(sbg[m]):
                    forms.setdefault(f, f'map {m}')
            for f in fs:
                forms.setdefault(f, f'map {m}, fought' if m > 1 else f'world {m}, fought')
        for f, where in sorted(forms.items()):
            for sp in sorted(set(formation_species(f))):
                sh, mask = tree.authored.get(sp, (1, tree.floor.get(sp, 0)))
                if sh == 0 or not mask:
                    continue                # no gauge, or no weapon key to hold
                checked.add((first, sp))
                why = ot6_class.holder_rule(mask, roster, forced, magitek, K)
                if why:
                    found.setdefault((first, sp), [why, roster, forced, set()])[3].add((where, f))
    return found, checked, met


STAGE_DRIFT = []


def print_holders(tree, found, checked, met):
    for l in STAGE_DRIFT:
        print(l)
    for (first, sp), (why, roster, forced, where) in sorted(found.items(), key=lambda kv: (met.index(kv[0][0]), kv[0][1])):
        forced_txt = 'all forced' if forced == roster else ('forced: ' + (', '.join(sorted(forced)) or 'nobody'))
        places = sorted({w for w, _f in where})
        print(f'  HOLDER stage {first} ({", ".join(sorted(roster))}; {forced_txt}) ${sp:03X} {tree.row_text(sp)}: '
              f'{why}; dealt by {"; ".join(places[:4])}{" ..." if len(places) > 4 else ""} '
              f'({len({f for _w, f in where})} formation(s))')
    print(f'holder rule (owner, 2026-11-23: a species\' weapon keys are really held by two the player can field '
          f'there, or by one the story forces): {len(checked)} stage x species pair(s) over {len(met)} stage(s) '
          f'of the line, {len(found)} not met ({len({sp for _s, sp in found})} species, '
          f'{len({s for s, _sp in found})} stage(s))')
    return len(found)


def unresolved():
    """Every formation a walked pool can deal must resolve to bodies: a word
    read raw (a "+Rand" flag left on) indexes past the formation table and its
    fights silently go unaudited (#255; map 394's group 112 is four such words)."""
    out = []
    for kind, n, g in pools():
        for f in group_forms(g):
            if not formation_species(f):
                out.append(f'{kind} {n} group {g}: formation {f:#x} resolves to no bodies')
    return sorted(set(out))


def selftest():
    # the kit re-read: a real line of the baseline replay (Mt. Kolts, the
    # Vargas fight), under this tree's tables
    line = ('[ot6] [battle] [keys] form=$1B3 hands=$03 kit=$07 party=e0:c4:$02/$02,e1:c1:$01/$01,'
            'e2:c0:$01/$01,e3:c5:$01/$05 bodies=s0:$103:row$04:sh5,s1:$14D:row$01:sh2,s2:$14D:row$01:sh2 '
            'gauged=3 nohand=1 nokit=0 src=c4:r1D:tools,c1:r0A,c0:r0A,c5:r53:B bag=A3/A4/AA')
    k = KEYS.match(line)
    assert k and int(k.group(1), 16) == 0x1B3, 'the [keys] line no longer parses'
    members, hands, kit = kit_of(k.group(3), k.group(4))
    assert members == (0, 1, 4, 5), members
    w = lambda i: WEAPON_CLASS[i] & C.mask
    assert hands == w(0x1D) | w(0x0A) | w(0x53), 'hands are the hand items of this tree\'s Ot6WeapClassTbl'
    assert kit == hands | w(0xAA) | w(0xA3) | w(0xA4) | (SKILL_CLASS[0x5D] & C.mask), 'kit adds the bag\'s Tools and Pummel'
    assert kit_of('c0:M', '')[1:] == (0, SKILL_CLASS[0x8A] & C.mask), 'Magitek armor: no hand, the TekMissile'
    assert kit_of('c9:r52', '')[2] == 0, 'Fixed Dice is null-break: it holds nothing'
    assert kit_of('c1:rFF:T', '')[2] == w(0xFF) | C.consts['OT6_CLS_THIEF'], 'an empty hand is a fist; a thief\'s hit'
    assert kit_of('c3:r25:throw', '41/AB')[2] == w(0x25) | w(0x41) | (SKILL_CLASS[0x51] & C.mask)
    try:
        kit_of('c1:r0A:Q', '')
    except AssertionError as e:
        print('audit_break_coverage selftest: mutant refused, an unknown [keys] part:', e)
    else:
        raise AssertionError('an unknown [keys] src part was read as nothing')
    print(f'audit_break_coverage selftest: the Vargas line re-reads as {party_name(members)} holding {C.names(kit)}')

    # tier 1 on the tree, then the mutants it must refuse
    n, _ = tier1(TREE, quiet=True)
    assert n == 0, f'the tree has {n} tier-1 NO-KEY formation(s)'
    # a pool formation whose every body is gauged, classed, and not
    # fire/ice/bolt-weak: class is all that keys it
    cand = None
    for kind, m, g in pools():
        if kind != 'map' or m in MAGIC_ONLY_MAPS:
            continue
        for f in sorted(group_forms(g)):
            sps = formation_species(f)
            if sps and all(s in AUTHORED and AUTHORED[s][0] > 0 and AUTHORED[s][1]
                           and not mp[s*32+25] & PARTY_ELEMS for s in sps):
                cand = (m, f, sps)
                break
        if cand:
            break
    assert cand, 'no class-keyed pool formation to mutate'
    m, f, sps = cand
    assert TREE.verdict(sps) == 'class'

    def refused(tag, tree, want):
        n, _ = tier1(tree, quiet=True)
        assert n >= want, f'{tag}: tier 1 found {n} NO-KEY formation(s), wanted >= {want}'
        print(f'audit_break_coverage selftest: mutant refused, {tag}: {n} NO-KEY formation(s)')
    # 1. its bodies' rows emptied (shields kept): nothing chips it
    refused(f'form {f}\'s class rows emptied',
            Tree({**AUTHORED, **{s: (AUTHORED[s][0], 0) for s in sps}}, floor), 1)
    # 2. its bodies' rows dropped, the floor's class emptied with them
    refused(f'form {f}\'s rows dropped and its floor bytes zeroed',
            Tree({s: v for s, v in AUTHORED.items() if s not in sps}, {**floor, **{s: 0 for s in sps}}), 1)
    # 3. every class row emptied: only fire/ice/bolt and the gaugeless stand
    nall, _ = tier1(Tree({s: (sh, 0) for s, (sh, _m) in AUTHORED.items()}, {s: 0 for s in floor}), quiet=True)
    assert nall >= 50, nall
    print(f'audit_break_coverage selftest: mutant refused, every class row emptied: {nall} NO-KEY formation(s)')
    # 4. a gaugeless body is never the hole: the same formation, 0 shields
    assert tier1(Tree({**AUTHORED, **{s: (0, 0) for s in sps}}, floor), quiet=True)[0] == 0

    # tier 2: the party that fought it, with a kit holding its key, is
    # silent; stripped of the kit it is STAGE NO-KEY, fought and pool
    key = 0
    for s in sps:
        key |= AUTHORED[s][1]
    one = key & -key
    for tag, kit, want in (('holding its key', one, 0), ('stripped of its kit', 0, 2),
                           ('holding every other class', C.mask & ~key, 2)):
        found, _stages = stage_findings(TREE, {m: [(f, (1, 6), kit, sps)]}, {m})
        hits = [x for x in found if x[0] == 'NO-KEY' and x[2] == f]
        assert (len(hits) == want), f'tier 2, a party {tag}: {len(hits)} finding(s) on form {f}, wanted {want}'
        print(f'audit_break_coverage selftest: tier 2, map {m} form {f}, a party {tag} '
              f'({C.names(kit, none="no class")}): {len(hits)} STAGE NO-KEY')
    # an element-weak body is ELEMENT-ONLY, never silently keyed
    eweak = next((s for s, (sh, mask) in sorted(AUTHORED.items())
                  if sh > 0 and mask and mp[s*32+25] & PARTY_ELEMS), None)
    assert eweak is not None
    found, _ = stage_findings(TREE, {m: [(f, (6,), C.mask & ~AUTHORED[eweak][1], [eweak])]}, set())
    assert [x[0] for x in found] == ['ELEMENT-ONLY'], found
    print(f'audit_break_coverage selftest: tier 2, {mname(eweak)} against a kit without its class: ELEMENT-ONLY')
    # the holder rule over a staged leg: a species whose only key one
    # unforced member holds is found; with a second holder fieldable, or
    # that member forced, it is not
    K, S = ot6_class.grouping()
    cls = AUTHORED[sps[0]][1]
    cls &= -cls                                         # one class of form f's first body
    hold = sorted(K.holders(cls))
    rest = sorted(n for n in K.CHARS if K.signature_mask(n) and not K.signature_mask(n) & cls)
    assert hold and rest, (hold, rest)
    one = Tree({s: ((2, cls) if s in sps else (0, 0)) for s in AUTHORED}, {s: 0 for s in floor})
    saved = S.STAGES[:]
    try:
        for tag, roster, forced, want in (
                ('one real holder the story does not force', {hold[0], rest[0]}, set(), 1),
                ('nobody who holds it', {rest[0]}, None, 1),
                ('that holder forced into the party', {hold[0], rest[0]}, {hold[0]}, 0),
                ('a second real holder fieldable', set(hold[:2]) | {rest[0]}, set(), 0 if len(hold) > 1 else 1)):
            S.STAGES[:] = [('selftest_leg', roster, forced, False)]
            found, checked, _met = holder_findings(one, {'selftest_leg': {m: {f}}}, {}, ['selftest_leg'])
            got = len({sp for _st, sp in found})
            assert (got > 0) == (want > 0), f'holder rule, {tag}: {got} species found, wanted {"some" if want else "none"}'
            print(f'audit_break_coverage selftest: holder rule, map {m} form {f} keyed by {C.names(cls)} alone, '
                  f'{tag} ({", ".join(sorted(roster))}): {got} species not met of {len(checked)}')
    finally:
        S.STAGES[:] = saved
    print('audit_break_coverage selftest OK')
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    # --gate: the build gate's verdict alone (#536).  The verdict (tier 1, and
    # every pool formation resolving to bodies) is ROM data only; the claim is a
    # report.  So the gate reads no logs, and its edge (configure.py
    # break_coverage_ratchet) depends on no state: `ninja` of it alone builds
    # the ROM, not the line.  Without --gate the claim is read from whatever
    # generator logs build/states holds.
    ap.add_argument('--gate', action='store_true')
    ap.add_argument('--logs', default=os.path.join(ROOT, 'build', 'states'),
                    help='the directory of generator logs the claim is read from')
    ap.add_argument('--stages', action='store_true', help="print each stage's party and hands")
    ap.add_argument('--strict', action='store_true', help='a STAGE NO-KEY fails the run')
    ap.add_argument('--strict-holders', action='store_true', help='a HOLDER finding fails the run')
    ap.add_argument('--selftest', action='store_true')
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    global WALKED
    # `ninja quick`'s runs (quick_<state>.log, suite_quick_<test>.log) played
    # from tracked checkpoints, not the qualified play (#363): not evidence here
    logs = [] if args.gate else sorted(
        p for p in glob.glob(os.path.join(args.logs, '*.log'))
        if not os.path.basename(p).startswith(('quick_', 'suite_quick_')))
    fought, keys, legs, seen = fought_by_map(logs)
    # a world's walked sectors count once its logs record the world trace
    # (#288): the blind trace wrote only the field coordinates of map-change
    # frames under map=0/1, 56 distinct tiles across the 217 logs of
    # 2026-10-05, where one World of Ruin leg alone walks 221
    WALKED = {w: secs for w, secs in WALKED.items() if len(TILESEEN[w]) >= 100}
    claimed_field = {m for m in range(len(props)//33)
                     if props[m*33+5] & 0x80
                     and group_forms(sbg[m]) & fought.get(m, set())}
    claimed_sectors = {sec for sec in range(512)
                       if wbg[sec] != 0xFF
                       and group_forms(wbg[sec]) & fought.get(sec // 256, set())
                       and (sec // 256 not in WALKED
                            or sec & ~3 in WALKED[sec // 256])}

    nokey, unclaimed = tier1(TREE, None if args.gate else claimed_field, claimed_sectors)
    stage_nokey = holders = 0
    if args.gate:
        print('tuning claim: not read (--gate); run without --gate for it')
    else:
        nfought = sum(len(v) for v in fought.values())
        print(f'tuning claim, from {len(logs)} generator log(s) in {os.path.relpath(args.logs, ROOT)} '
              f'({nfought} map+formation pairs fought): {len(claimed_field)} field '
              f'maps {sorted(claimed_field)}; world sector bytes: '
              f'{len([s for s in claimed_sectors if s < 256])} of the WoB, '
              f'{len([s for s in claimed_sectors if s >= 256])} of the WoR '
              f'(walked sectors known for world(s) {sorted(WALKED) or "none"}); '
              f'{len(unclaimed)} battle-enabled maps UNCLAIMED')
        if not logs:
            print('  (no generator logs: nothing is claimed until the route is played)')
        else:
            findings, stages = stage_findings(TREE, keys, claimed_field)
            stage_nokey = print_stage(TREE, findings, stages, len(logs), args.stages)
            holders = print_holders(TREE, *holder_findings(TREE, legs, seen))

    bad = unresolved()
    if bad:
        for l in bad[:20]: print('UNRESOLVED ' + l)
        print(f'RATCHET: {len(bad)} pool formation(s) resolve to no bodies -- unaudited')
        return 1
    print('every pool formation resolves to bodies (the +Rand flag expanded)')

    if nokey:
        print(f'RATCHET: {nokey} no-key formation(s) -- the build gate refuses')
        return 1
    print('tier-1 floor invariant holds: zero completely keyless formations game-wide')
    if args.strict and stage_nokey:
        print(f'RATCHET (--strict): {stage_nokey} STAGE NO-KEY formation(s) within the claim')
        return 1
    if args.strict_holders and holders:
        print(f'RATCHET (--strict-holders): the holder rule is not met for {holders} stage x species pair(s)')
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
