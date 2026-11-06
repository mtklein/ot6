# World of Ruin: Kefka's Tower

Issue #273. The tower takes three parties. This doc decodes the tower from
the ROM, designs its break rows, seats the three parties, and routes the
tower a leg at a time from the line's frontier, `wor-desert-v1`. Kefka
himself is #274's.

The owner's direction (2026-11-05): "i usually bring my bench and mains to
kefkas tower in mixed parties and let the bench level up naturally". So
there is no training leg before the tower (#496's `gen_wor_bench` was
reverted at cb302e15); each party is a carrier beside the bench, and the
bench levels in the tower.

Evidence is under `build/attempts/wt/v039-kefka-tower/`. Line numbers are
into `ff6/src/event/event_main.asm` unless a file is named.

---

## 0. Findings

1. **The tower is three closed lanes until the parties open them for each
   other.** Each party lands in its own corner of map 334 and can reach only
   its own rooms until another party throws a switch for it (section 2).
2. **Every species the tower deals is met nowhere else.** No pool or event
   battle outside the tower deals any of its 34 species, so its rows move
   no earlier fight (section 3).
3. **The Guardian the tower fights is its own record.** Battle 140 is
   Guardian `$112`; battle 76, the only other group that deals it, is never
   called. `$112` gets a real row; the World of Balance's `$111` (battle 75)
   stays without a gauge.
4. **The line plays the tower to Guardian's save point** on the graph, four
   cuts (section 5): the factory, Inferno, Atma, Guardian; the Gold and
   Skull Dragons on the way. Inferno, Atma, both dragons and Guardian are
   not coin flips (8 of 8 or 11 of 12 and better across draws, section 6).
5. **The chamber's columns set the lanes**: the order the weights fall puts
   party 1 east (the Goddess), party 3 west (Doom), party 2 the middle
   (Guardian, the Poltergeist).
6. **The three statues are coin flips** for the parties that reach them
   (the Poltergeist 6 of 11, Doom 3 of 6, the Goddess 1 of 3): the next
   labs, before they join the line.
7. **A Ribbon in every party.** The line arrives with three, two of them in
   party 3; party 2, with none, wiped to the Evil Oscars' Sour Mouth.

## 1. Into the tower

The Falcon lands on world (137,198) (`VehicleEvent_04` ->
`EnterKefkasTower`, :451): "Right. We're going in!", `party_menu 3` (:605),
and the three parties set down on map 334: party 1 at (9,16), party 2 at
(43,21), party 3 at (56,22). It sets `$01CE` (party switching), `$02BE`
(inside the tower) and `$0029` (the speech made). The tower's exit
(`_cc0f7d`) clears them.

**The crane.** Six tiles of map 334 ride the crane back to the Falcon's
deck on A ((56,22), (41,18), (14,17), and (57,44), (35,21), (8,37) facing
up: `_cc0fc3`, `_cc0fd4`, `_cc0fe5`, `_ca03ba`, `_ca03c9`, `_ca03d8`). They
fire on A only, so the walks cross them (334 (57,44) is the only way down
the east side) and no chest or talk is made from one.

**Ladders.** A ladder is two columns: one carries a party the way it was
entered (down 2, 3 or 5; up 2, 3, 5 or 6), the column beside it pushes a
party entering the wrong way back a tile (`_cc1008`.. `_cc1046`). The legs
carry them as links (`H.navLinks`) and avoid the push-back tiles.

## 2. The map graph and the three lanes

The tower's 23 maps (`route_data.py map`, `tower_maps.txt` in the
evidence). Each landing is a closed region until a switch opens it:

- **Party 1** (north-west): 334's north-west, 303, 304 (the Fixed Dice),
  334's west, 292's left room. It goes on only when party 2 presses 292
  (87,12) (`_cc1447`, opens the passage to 352) and party 3 opens 334's
  door (30,50) from the sparkle at (34,53) or (33,54) (`_cc1480`). Then: 352
  (the machines' hall), 295 (the Doom Dragons), 334's south, 337's centre
  corridor.
- **Party 2** (north): 338 (Minerva, a Tack Star), 331 (Atma, optional; a
  save point behind it), the hole into 329, 409, 334's south-west (the
  Force Shld, the Force Armor), 292's right room (the switch, a Ribbon),
  294, 335 (the Gold Dragon), 354's west half, 337's west plate room.
- **Party 3** (east): 334's east (the Red Cap), 339, the factory 410 (the
  Hero Ring, the Aegis Shld; Inferno; a save point), 293, 334's south (the
  sparkle; the Rainbow Brsh, a Megalixir), 354's east half (the Skull
  Dragon), 337's east plate room.

**The puzzle** (`_cc14af`.. `_cc1698`):

| where | what it does | held or set |
|---|---|---|
| 292 (87,12) | the passage from 292's left room to 352, for party 1; refused while `$02C8` is set, so party 2 presses it before its plate | set (`$0062`) |
| 334 (34,53) left + A, (33,54) up + A | the door (30,50), 334's south to its middle, for party 1 | set (`$007F`) |
| 337 (4,12), (12,12) | set `$02C8` (party 2's bit) and `$02CC` (party 3's) whoever stands there; both set opens the locked door (8,11) for good | held, then set (`$0080`) |
| 337 the weights (4,7), (12,7), A | knock the walls through so the plate rooms reach the corridor; refused while the plate under them is held | set |
| 355 (35,9), (43,9) | each shuts the gate between its column and the middle (`_cc1598`, `_cc15b2`): the chamber is three columns joined only along row 9, so a party that steps on one is shut in that column | set (`$0065`, `$0066`) |
| 355 the chamber's three plates (35,6), (39,9), (43,6) | one in each column; all three parties on them at once: the north door (to Guardian) and the south doors | north set; south toggles each time |
| 337 (8,6) | the cell doors (2,4), (14,4) to the west and east lanes | set (`$00D0`) |
| 411 (103,43), (109,40), (115,42) | each walking party sets its own bit; all three set: `FinalBattle` (:926), Kefka | held |

**The chamber's order.** Each column holds one party, and the weights set
who goes where: the first party into the chamber takes a column and drops
its weight, which frees the party in the plate room below it; that one
comes up and takes the other column and its weight; the last takes the
middle. The route: party 1 east (the east weight frees party 3), party 3
west (the west weight frees party 2), party 2 the middle (probe `c3`; `c2`
was party 1 shut in the west column, "neither the exit (43,18) nor a side
of it is reachable from (35,9)"). The west cell's door to the west lane
(2,4) and the east's (14,4) open from 337 (8,6) (`$00D0`), which only the
middle party reaches, through the chamber's south door.

**From the chamber**, three lanes, each behind a statue, each ending on one
of 411's three plates:

- the north door: **Guardian** (291 (12,14), battle 140; a save point
  after), 287, 334's north (the Ribbon (29,29)), the **Poltergeist** (334
  (30,16), battle 100), 412 (a save point), down to 411's middle plate;
- the west: 355's west column, 291's west room, **Doom** (355 (64,12),
  battle 98; a save point after), 411's left plate;
- the east: 355's east column, 291's east room, the **Goddess** (354
  (12,32), battle 99; a save point after), 411's right plate.

Every boss battle in the tower ends in a game over when lost (`_ca5ea9`).
Atma (battle 112, 331), the Gold Dragon (135, 335) and the Skull Dragon
(136, 354) are touched NPCs off the lanes' floors; a party can walk round
each.

Save points: 410 (37,17) and 412 (82,47) from the start; 331 (76,51) after
Atma, 291 (12,12) after Guardian, 354 (12,31) after the Goddess, 355
(64,11) after Doom. A save keeps all three parties (split-party.md 1).

## 3. Species and break rows

34 rows, all new (the generated floor stood for each: six shields; the
tower's Guardian stood shieldless). Vanilla elements stay. The tower is two
places, and the rows say so: the empire's **factory** (292, 352, 409, 410,
329, 355), whose machines are weak to bolt and water vanilla, and its
**ruins**, the beasts, the dead and the court.

The lessons:

- **The machines turn the blades.** Every machine takes the point and the
  blow (pierce, bludgeon), never slash. The carriers' blades want Bolt
  there; the bench's spears, knives and clubs carry (EDGAR, MOG, LOCKE,
  GOGO, UMARO), which is where the bench shines.
- **The statues are magic made stone.** Each takes the brush and the cards
  (special) and one other hand; between them every hand: Doom slash, the
  Goddess pierce, the Poltergeist bludgeon. Which party takes which lane is
  a choice the keys make (section 4).

| species | L / HP | vanilla | shields | classes |
|---|---|---|---|---|
| Brontaur `$084` | 50 / 10,050 | weak ice | 3 | pierce, bludgeon |
| Evil Oscar `$0B7` | 56 / 7,000 | weak fire; absorbs the rest | 3 | slash, special |
| Vectaur `$080` | 59 / 2,800 | weak ice, water | 2 | slash, pierce |
| GtBehemoth `$0E0` | 58 / 11,000 | none; Meteor | 3 | pierce, bludgeon |
| Dark Force `$00D` | 55 / 8,940 | weak holy | 3 | bludgeon, special |
| Outsider `$0BD` | 18 / 8,050 | weak holy; absorbs poison | 3 | slash, pierce |
| Madam `$06A` | 53 / 8,150 | weak poison | 3 | slash, special |
| Retainer `$007` | 59 / 7,050 | weak poison | 3 | slash, bludgeon |
| Hemophyte `$0C1` | 56 / 6,800 | none | 2 | slash, special |
| Veteran `$0FB` | 51 / 10,000 | none | 3 | slash, pierce |
| Didalos `$0F9` | 59 / 12,280 | weak fire, holy; absorbs poison | 3 | bludgeon, special |
| Steroidite `$016` | 54 / 25,000 | weak holy | 4 | pierce, bludgeon |
| Mover `$056` | 51 / 120 | absorbs poison | 1 | slash, bludgeon |
| Doom Drgn `$025` | 54 / 18,008 | none | 4 | pierce, special |
| Vectagoyle `$0E4` | 57 / 7,500 | none | 3 | bludgeon, special |
| Land Worm `$09B` | 59 / 12,000 | weak ice; absorbs earth | 3 | slash, pierce |
| IronHitman `$0FD`, Junk `$0ED`, Sky Base `$0FC` | 52-53 / 2,000-6,000 | weak bolt, water | 2 | pierce, bludgeon |
| Dueller `$0D9`, Innoc `$0F6` | 52-53 / 6,600-7,200 | weak bolt, water | 3 | pierce, bludgeon |
| Fortis `$0EA`, Prometheus `$105`, Scullion `$0A1` | 54-57 / 9,800-27,000 | weak bolt, water | 4 | pierce, bludgeon |
| Inferno `$10C` (battle 114) | 67 / 30,800 | weak bolt; absorbs fire | 6 | pierce, bludgeon |
| Striker `$142` (Inferno's arm) | 67 / 11,000 | weak fire; absorbs ice | 3 | slash, pierce |
| Rough `$141` (Inferno's arm) | 69 / 8,000 | weak ice; absorbs bolt | 3 | slash, bludgeon |
| Guardian `$112` (battle 140) | 67 / 60,000 | weak bolt, water | 10 | pierce, bludgeon |
| Doom `$127` (battle 98) | 73 / 63,000 | weak holy; absorbs ice, poison | 10 | slash, special |
| Goddess `$128` (battle 99) | 68 / 44,000 | none; absorbs bolt, holy | 8 | pierce, special |
| Poltrgeist `$129` (battle 100) | 67 / 58,000 | weak poison; absorbs fire, wind | 8 | bludgeon, special |
| Atma `$17D` (battle 112) | 67 / 55,000 | none; absorbs five | 10 | slash, pierce |
| Gold Drgn `$150` (battle 135) | 62 / 32,400 | weak water; absorbs bolt | 6 | slash, pierce |
| Skull Drgn `$151` (battle 136) | 62 / 32,800 | weak fire, holy; absorbs poison | 6 | bludgeon, special |

The GtBehemoth's three is the Tyranosaur's count (route-wor-side-trips.md
finding 3): a break that comes before its second Meteor. Atma keeps the
AtmaWeapon's pair (the World of Balance's `$117`, slash and pierce): the
rematch.

`battle_breakwor_tower` checks the rows in the built ROM, their vanilla
weak and absorb bytes, that every species of pool groups 208-227 and the
eight event battles has a row and a key for each party whose lane meets it
(section 4's seating), and the lessons. Red on main's rows
(`rows/main.log`: "got 539 ($21B)", "$007 Retainer has no Ot6ShieldTbl row
(want 3, class $05)") and on a lane mutant, party 3 with only a blade
(`rows/mutlane.log`: "formation 484 (event battle 114): species $10C (class
$06, weak $04) has no key for party 3 without its point"); PASS on the rows
(`rows/rows.log`).

## 4. The seating

Fourteen characters at `wor-desert-v1` (`tools/roster.py`): TERRA and
CELES 63, CYAN, SHADOW and RELM 53, STRAGO 51, then the bench: GOGO 44,
LOCKE 41, SABIN 39, MOG 38, UMARO 37, EDGAR 34, GAU and SETZER 32.

#496 measured the tower's first map (334, formations 271, 272 and 329): a
physical carrier with a cure (TERRA, CELES) carries any two of the bench;
RELM and STRAGO, who know no cure, carry nobody; formation 329's Meteor is
the killer (git show 6866fa97:docs/design/route-wor-tower-prep.md).

The seating (plan M), two strong and two of the bench in every party, a
cure in every party:

| party | members (L) | cure | lane |
|---|---|---|---|
| 1 | TERRA 63, RELM 53, EDGAR 34, SETZER 32 | TERRA's Cure, Life | the north-west, the machines' hall; the east column, the Goddess |
| 2 | CELES 63, STRAGO 51, LOCKE 41, MOG 38 | CELES's Cure | the long way west: Atma, the Gold Dragon; the middle, Guardian and the Poltergeist |
| 3 | CYAN 53, SHADOW 53, SABIN 39, GOGO 44 | SABIN's (Starlet) | the factory: Inferno, the Skull Dragon; the west column, Doom |

GAU (no weapon; #496's casualty) and UMARO sit out. Party 3's keys are
slash and pierce only, so it takes Doom (slash) or the Goddess (pierce), not
the Poltergeist; party 1 holds every hand.

**Measured on 334** (`tools/tests/lab_tower_split.lua`, each group seated
as party 1, 10 battles after K encounters used up by another group):
section 7.

## 5. The legs and cuts

| leg | boots | saves | what |
|---|---|---|---|
| `gen_wor_kt_factory` | `wor-desert-v1` | `wor-kt-factory-v1` | the Falcon to the tower, the three groups, each party dressed, party 3 down the east side, into 339 by its top door (334 (52,47)), the factory (410), the hop at (8,14) into its hall, Save on the factory's save point (37,17) beside Inferno |
| `gen_wor_kt_inferno` | `wor-kt-factory-v1` | `wor-kt-inferno-v1` | Inferno (battle 114), Save again on the factory's save point |
| `gen_wor_kt_atma` | `wor-kt-inferno-v1` | `wor-kt-atma-v1` | party 2 north through 338 to 331, Atma (battle 112), Save on the save point behind him |
| `gen_wor_kt_guardian` | `wor-kt-atma-v1` | `wor-kt-guardian-v1` | party 3: the sparkle, the Skull Dragon, the east plate; party 2: the hole, 409, the 292 switch and Ribbon, the Gold Dragon, the west plate (the locked door opens); party 1's lane to the chamber; the weights and the chamber's plates; party 2 to Guardian (battle 140), Save on his save point (291 (12,12)) |

The factory hall's two chests (the Gauntlet, the Nutkin Suit) are reached
from 296, the dead end off 339's foot (the same treasure bits): the middle
path leaves them.

## 6. The bosses

Until the graph captures `wor-kt-factory-v1` on this ROM (a replay from
power-on, section 8), each boss is labbed from the graph's `wor-desert-v1`
capture with the factory leg's own play in front of it
(`mkinferno.py`, `mkatma.py`, `mkgold.py` in the evidence: the leg up to its
save, then the boss instead), at twelve seed shifts (0, 1, 4, 5, ... 20, 21).
A shift moves the in-battle RNG of every battle on the way, so the boss is
met at different frames; distinct keys are counted (`$be` at the open with
the formation). Fought by the default driver (boost-Fight, the break
keyed), each party's hands made absorb-safe first (`H.absorbSafeArms`: SABIN's
Fire Knuckle healed Inferno, lab `inf2`: "char 5's L-hand item $57 (fire) is
ABSORBED by slot 0 species $010C").

**Inferno** (battle 114: Inferno, Striker, Rough; party 3, CYAN, SHADOW,
SABIN, GOGO). Not attrition, not a coin flip:

| lab | the kit | won | distinct keys | deaths | ticks |
|---|---|---|---|---|---|
| `inf3` | two Ribbons in party 3 | 12 of 12 | 9 | 2 | 6,896-13,702 |
| `inf5` | the spread: SHADOW's Ribbon to party 2 | 11 of 12 | 9 | 7 | 8,189-13,046 |

`inf5`'s loss (`inf_s8`, key be5C) was a Petrify wipe: Delta Hit stoned
SABIN ("entity 2 char 5 is under PETRIFY"), then CYAN and GOGO fell, and
the game ends with SHADOW (no Ribbon now) standing stoned or alone. A loss
in twelve is a line in the retry inventory; the Ribbon is worth more in
party 2 (below). The break lands ("actor=0 KEYED: Fight at 0 BP lands 2
chip(s) on slot 1's 1 shield(s)").

**Atma** (battle 112, optional; party 2, CELES, STRAGO, LOCKE, MOG): 12 of
12 won, 0 deaths, 8 distinct keys, 6,331-8,224 ticks (`atma3`); before the
spread `atma1` won it in all 11 runs that reached it. A save point stands
behind him, so the line fights him: a player meets him on party 2's way.

**The Gold Dragon** (battle 135, map 335; party 2 after Atma, the hole, 409,
334's south-west, the 292 switch and its Ribbon): 12 of 12 won, 0 deaths,
8 distinct keys, 3,680-3,880 ticks (`gold1`). Short: party 2 holds both its
keys (CELES's blade, MOG's spear) and STRAGO's Aqua Rake its water
weakness. A tuning note: it may be too easy for an eighth dragon.

**The Skull Dragon** (battle 136, map 354; party 3 after Inferno, 293, the
sparkle that opens party 1's door, the Rainbow Brsh and the Megalixir): 11
of 11 won where it was reached, 2 deaths, 8 distinct keys, 5,474-8,738 ticks
(`skull1`; the twelfth run is `inf5`'s Inferno loss, key be5C, replayed:
the labs share the leg's play up to the boss).

**Guardian** (battle 140; party 2 from the chamber's middle): 11 of 11
won where reached, 0 deaths, 8 distinct keys, 6,400-7,185 ticks (`guard1`,
the whole first half of the tower played in front of it from
`wor-desert-v1`, probe `c3`).

**The statues are the tower's hard fights** (`stat1`, the same play on to
each lane's statue; `bosstally.py`, `stat1_tally.txt`):

| boss | party | met | won | lost | distinct keys | deaths | ticks |
|---|---|---|---|---|---|---|---|
| Poltergeist (battle 100) | 2 (CELES, STRAGO, LOCKE, MOG) | 11 | 6 | 5 | 9 | 23 in the six won | 23,339-32,977 won |
| Doom (battle 98) | 3 (CYAN, SHADOW, SABIN, GOGO) | 6 | 3 | 3 | 4 | 15 in the five with an outcome line | 11,261-17,485 won |
| Goddess (battle 99) | 1 (TERRA, RELM, EDGAR, SETZER) | 3 | 1 | 2 | 3 | 5 in the two with an outcome line | 10,634 won |

A run ends at its first loss, so each statue is met only where the ones
before it were won. The tally counts outcome lines ("Poltrgeist: won 6,
lost 1; distinct keys 6; deaths 23; ticks 19920-32977"; "Doom: won 3, lost
2"; "Goddess: won 1, lost 1"); the other losses are wipes the game ended
before an outcome line, read from each run's wipe context ("the last battle
up (f204180) was formation 0129 ... a6:0/5691 bp1 a7:727/3975 bp0 a1:0/2766
bp2 a10:0/2533"; Doom's "formation 0127", the Goddess's "formation 0128").
The Poltergeist is attrition (three or four deaths in every win,
23,000-33,000 ticks) and a coin flip; Doom is a coin flip (N. Cross freezes
two members, "entity 2 char 5 is under FROZEN"; SHADOW "died holding 5
BP"); the Goddess won once in three. These are labs before the statues join the line (section 8).

**Why the Ribbon moves.** With the three Ribbons as the line wore them
(TERRA's, CYAN's, SHADOW's), party 2 had none, and on its first map three
Evil Oscars' Sour Mouth (Dark, Poison, Imp, Mute, Muddle, Sleep) wiped it
(`atma1/atma_s16`: "formation 00B7 00B7 00B7 ... a6:0/5539 bp2 a7:449/3844
bp1 a1:0/2653 bp1 a10:0/2315"). The split now hands one over: "[ribbons]
party 3 wears 2, party 2 none: SHADOW hands slot 4's Ribbon over", "Ribbon
$CA from the bag onto STRAGO's slot 4", "Ribbons by party: 1, 1, 1"
(`probe/f10`). Party 2 picks up a second Ribbon in 292.

## 7. Measured

### 7.1 The seating on 334

`lab_tower_split.lua` from `wor-desert-v1` (sha256 4b173cb7, main's
capture, byte for byte the tracked save), each group seated as party 1 and
walked on its lap by the north-west landing for 10 battles, after K = 0, 6
or 12 encounters used up by the next group, at seed shifts 0 and 7; tallied
by `tools/tower_tally.py --by-arm` (`seat3_tally.txt`). Three plans: M
(section 4), N (TERRA and CELES each carry three of the bench, the four
other strong together: CYAN, SHADOW, RELM, STRAGO, no cure), O (M with the
two mages swapped).

On the designed rows (`seat3/`, ROM 50cc0ef3), every group won all 60 of
its battles:

| group | members | battles | deaths | Fenix | Potions |
|---|---|---|---|---|---|
| M1 | TERRA, RELM, EDGAR, SETZER | 60/60 | 5 (EDGAR 2, TERRA 2, SETZER 1) | 5 | 19 |
| M2 | CELES, STRAGO, LOCKE, MOG | 60/60 | 6 (LOCKE 5, MOG 1) | 6 | 4 |
| M3 | CYAN, SHADOW, SABIN, GOGO | 60/60 | 1 (SABIN) | 1 | 4 |
| N1 | TERRA, GOGO, SABIN, SETZER | 60/60 | 3 | 3 | 6 |
| N2 | CELES, LOCKE, MOG, UMARO | 60/60 | 7 | 7 | 2 |
| N3 | CYAN, SHADOW, RELM, STRAGO | 60/60 | 2 | 2 | **350** |
| O1 | TERRA, STRAGO, EDGAR, SETZER | 60/60 | 5 | 5 | 15 |
| O2 | CELES, RELM, LOCKE, MOG | 60/60 | 7 | 7 | 7 |

Quoted: "M1: 6 runs, 0 FAIL; battles {'won': 60}; distinct keys 51; deaths
{'EDGAR': 2, 'TERRA': 2, 'SETZER': 1}"; "M2: 6 runs, 0 FAIL; battles
{'won': 60}; distinct keys 49; deaths {'LOCKE': 5, 'MOG': 1}"; "M3: 6 runs,
0 FAIL; battles {'won': 60}; distinct keys 49; deaths {'SABIN': 1}"; "N3:
... spent potion 350 fenix 2".

- **Plan M holds**: 180 of 180 battles, 12 deaths. N3, the four strong with
  no cure, wins too but drinks the bag (350 Potions over its six runs: the
  care with no cure to cast), which the one bag of three parties cannot
  pay. So every party keeps a cure.
- **The rows decide the first map.** The same plans on the generated floor
  (six shields on everything; `seat2/`, ROM f442a80f, main's; the batch
  stopped at 17 of 36 runs when the rows landed): M1 50 of 50 with 24
  deaths (TERRA 9), M2 lost 2 of 6 runs ("M2: 6 runs, 2 FAIL; battles
  {'won': 42, 'lost': 2}"; a wipe in 272: "formation 272 lost after 19899
  ticks; CELES L63 0/5539, STRAGO L52 0/3975, LOCKE L41 0/2653, MOG L39
  0/2423"). With three shields the GtBehemoth breaks before its Meteors
  pile up.
- `seat1/` was the first try, measuring each group in its own party's seat:
  party 3's lap from (56,22) runs onto the ladder's push-back tile (56,24)
  and every party-3 arm timed out ("navTo: timeout after 20000 walk
  frames"); kept, not counted.

### 7.2 The factory leg

`gen_wor_kt_factory` as a lab from the same capture (`probe/f2`.. `f8`):
f2-f7 found the walk (339's top door is reached from below the crane tile
(57,44); 339's foot leads only to 296), f8 and `cap/c1` passed it: "PASS
(frame 32802) attempts=1/1"; "party 3: 4 battle(s), 4 won, 0 lost; XP
CYAN +16032, SHADOW +16032, SABIN +6300, GOGO +16032; spent $F0 x2". SABIN
(L39, 2,552 HP) fell twice to the Dueller's one action from full ("[death]
f+2227 entity 2 char 5 from 2552/2552 by slot 0 cmd $0C atk $94 (ONE
ACTION from >= 80%)").

### 7.3 The graph's own play, sweeps and negatives

**The line on this ROM** (px13, `graph/line.log`, `graph/graph2.log`): the
rows move the line's play from power-on (a ROM change reshuffles every
draw): the graph's `wor-desert-v1` is 5bc1ce44, "366 byte(s) differ" from
main's tracked save ("SABIN level: fresh 38, tracked 39", "CELES level:
fresh 62, tracked 63"). The tower's four legs then play on the graph
(`graph2.log`): "generate wor_kt_inferno ... PASS (frame 12893)
attempts=1/3", "generate wor_kt_atma ... PASS (frame 23000) attempts=1/3",
"generate wor_kt_guardian ... PASS (frame 99903) attempts=1/3" (the factory
"PASS (frame 36814) attempts=1/3", `chain.log`), and "checkpoint drift
wor-kt-factory-v1: none", "... wor-kt-inferno-v1: none", "...
wor-kt-atma-v1: none", "... wor-kt-guardian-v1: none". The first plays
found two defects, fixed in the library: a random battle opened on the
step Atma's talk took, so the leg went on without him (`T.touchBoss` talks
again while the boss stands); and Inferno's trigger, kept off the walks
while he stood, kept party 3 on the factory's save point after him.

The bench by Guardian's save (`audit_levels.txt`): EDGAR 34 -> 36, SETZER
33 -> 35, LOCKE 41 -> 42, SABIN 39 -> 40, MOG 39 -> 40, GOGO 45 -> 46.

**Sweeps from the graph's captures** (`sweep/`, each leg from the capture
before it, seed shifts 0, 1, 4, 5, 8, 9, 12, 13, one attempt each;
`sweep_tally.txt`): `gen_wor_kt_factory` 8 of 8, `gen_wor_kt_inferno` 8 of 8
("Inferno: won 8, lost 0; distinct keys 8; deaths 7"), `gen_wor_kt_atma` 8
of 8, `gen_wor_kt_guardian` 6 of 8 ("Skull Drgn: won 8 ... Gold Drgn: won 8
... Guardian: won 6, lost 0; distinct keys 6"). Both losses were party 1 in
the machines' hall (352), formation 413, Sky Base with four IronHitmen
("formation 00FC FFFF 00FD 00FD 00FD 00FD; seats ... a0:0/5535 bp0 a8:0/5475
bp1 a4:0/2008 bp1 a9:1611/1902"): the line retries a wipe from the leg's
boot, but two in eight is a lab (section 8).

**Negatives** (#480; `negs.log`, lab batteries from the graph's captures,
`make_negative.py`): SABIN unrecruited, "[deps] recruited mask $BFDF;
missing: SABIN" and "assertEq failed: every member the tower's seating names
is recruited"; 1,000 GP, "gil for a top-up at Kohlingen: 1000 GP, the floor
60000"; Inferno marked beaten in the factory's save, "contract
wor-kt-factory-v1 (entry) VIOLATED ... switch $00BD (Inferno not yet fought
(_cc1872)): expected 0, read 1". The positive is the graph's play:
"[deps] recruited mask $BFFF; missing: none".

### 7.4 Party 1's lane (the hall labs)

The sweep's two losses (7.3) were party 1 in 352, so `gen_wor_kt_guardian`
was labbed from the graph's `wor-kt-atma-v1` capture with K = 0, 2, 4
encounters used up by party 1 by its landing first (`mkburn.py`) x 8 seed
shifts (`hall*/`, `halltally.py`, `bosstally.py`):

| lab | the leg | runs PASS | formation 428 won | the losses |
|---|---|---|---|---|
| `hall` base | as 7.3 | 13 of 24 | - | 428 (Outsiders and a Madam, 304) 7, 413 (Sky Base, IronHitmen, 352) 2, 425, 329 |
| `hall` new | the Sky Base killed first | 12 of 24 | - | the same: "formation 413 met 9, won 6" against base's "met 9, won 7" |
| `hall2` | party 1 trained by its landing to L40 | 14 of 24 | 7 of 17 | 428 10; 413 "met 7, won 7" |
| `hall3` | + the Madam killed first | 12 of 24 | 5 of 17 | every hit on her draws her Meteor: "partyhp=4627,4664,1508,1432 roundcost=1213,1156,1146,1108" |
| `hall4` | Pearl on the Outsiders (weak to holy) | 12 of 24 | 6 of 17 | 428 11 |
| `hall4` l45 | Pearl, trained to L45 | 15 of 24 | 8 of 14 | 428 6, the Doom Dragons 2 |
| `hall5` | Ultima, Pearl, Fire on 428; Ultima on the Doom Dragons; L40 | 22 of 24 | 17 of 17 | three Innocs muddled party 2 in the chamber (its second Ribbon still in the bag); the Doom Dragons |
| `hall6` | + the 292 Ribbon put on | 28 of 32 | 22 of 22 | ribbonsOnSeated would not move a relic for it ("no seated member can take the bag's Ribbon"): the Innocs 2; the Doom Dragons 2 |
| `hall7` | + the 292 Ribbon over CELES's Wall Ring (the leg at 8bc55a1a) | 25 of 32 | 23 of 23 | the Doom Dragons (formation 226, 295) 5; formation 413 2 (one key twice) |

`hall7`: the leg itself at shifts 0-15, "leg: 16 runs, 13 PASS"; with K =
2, 4, "burn: 16 runs, 12 PASS"; the bosses "Skull Drgn: won 32, lost 0",
"Gold Drgn: won 32, lost 0", "Guardian: won 25, lost 0". The training:
"party 1 after 23 battles by its landing: TERRA L65, RELM L57, EDGAR L41,
SETZER L40". The opt `focusFirst` (a kill order held while a species
stands) went into the driver for the Sky Base and the Madam and out again:
it helped neither.

The graph's play of this leg (`graph/graph3.log`): "generate wor_kt_guardian
... PASS (frame 239051) attempts=1/3", "checkpoint drift wor-kt-guardian-v1:
75 byte(s) differ", re-cut, then "none"; the other three tower keys
"none".

### 7.5 The wards, one at a time, and the run

The same grid (K = 0, 2, 4 x 8 shifts, from the graph's `wor-kt-atma-v1`),
each arm adding one lever to the one before (`gear_*`, `mkarm.py`,
`mkflee.py`; `gear_<arm>_413.txt`, `_226.txt`):

| arm | the lever | runs PASS | 413 | 226 (two Doom Dragons) |
|---|---|---|---|---|
| `rows` | EDGAR and SETZER to the back row: already there ("[party 1: EDGAR and SETZER to the back row] already set") | 19 of 24 | won 16 of 17 | won 0 of 4 |
| `shell` | a Barrier Ring (auto Shell) on EDGAR and SETZER: S. Cross and Flare Star are magic (MagicProp +2 bit $01 clear) | 20 of 24 | won 16 of 17 | won 0 of 3 |
| `death` | + the bag's Memento Ring (a Death guard) on RELM | 22 of 24 | "met 17, won 17" | won 2 of 4 |
| `run` | + party 1 runs from the two Doom Dragons (the single one is fought) | 24 of 24 | "met 17, won 17" | run from at 4 distinct keys: "battle $0E2 PARTY LEFT after 30 ticks" |

The two Doom Dragons beat party 1 whatever it wore, as the Brachosaur beat
the forest's party (route-wor-side-trips.md finding 4), and a player runs
from them. `navTo` takes `fleeSpecies` now, as `worldNavTo` did.

**The leg at 7f4e9f9d** (the wards, the run, and the care before the wards:
`final_a/leg_s14` had EDGAR fall in the training's last battle, "EDGAR L40
0/2543", and the Relic menu refused him: "equip options: 4 A presses on the
target were not taken"), from the graph's capture (`final/`,
`final_tally_*.txt`, `final_bosses.txt`): the leg itself at shifts 0-23,
"leg: 24 runs, 24 PASS"; with K = 2, 4 x 8 shifts, "burn: 16 runs, 16
PASS"; formation 413 "met 16, won 16, distinct keys 11" and "met 13, won
13, distinct keys 13"; formation 428 "met 16, won 16" and "met 13, won 13";
the two Doom Dragons met once and run from; "Skull Drgn: won 40, lost 0",
"Gold Drgn: won 40, lost 0", "Guardian: won 40, lost 0; distinct keys 27".

The graph's play (`graph/graph6.log`): "PASS (frame 238691) attempts=1/3",
"checkpoint drift wor-kt-guardian-v1: 33 byte(s) differ", re-cut, "none";
the factory, Inferno and Atma keys "none".

## 8. Not done

- **The statues.** Routed and walked (probe `st1`, `stat1`): party 2 from
  Guardian back to the chamber, through its south door to 337 (8,6) (the
  cell doors), north again, 287, the Ribbon (334 (29,29)), the Poltergeist,
  412; party 3 the west lane (the west cell's door, 355's west column, 291's
  west room) to Doom; party 1 the east lane to the Goddess. Each is a coin
  flip for its party (section 6). Levers to measure next: the lane each
  party takes (it follows the order the weights fall; with SETZER and GOGO
  swapped between parties 1 and 3, party 3 would hold the brush and cards
  and party 1 could take the west column, so TERRA's party would meet Doom),
  the bench's levels by then (the tower's randoms pay 2,800-5,800 a member),
  the statues' shield counts (10, 8, 8), and the driver's choices against
  them (Doom's N. Cross; the Poltergeist absorbs fire and wind).
  One lever was tried and is worse (`swap1`, kept): SETZER and GOGO swapped
  (party 1 TERRA, RELM, EDGAR, GOGO; party 3 CYAN, SHADOW, SABIN, SETZER),
  the chamber in the other order (party 1 west to Doom, party 2 east to the
  Goddess, party 3 the middle to Guardian and the Poltergeist). Party 3
  without GOGO lost Inferno in 6 of 12 runs ("Inferno: won 6, lost 5" with
  one wipe before an outcome line; wipe contexts "formation 010C"), and the
  Poltergeist wiped it in all 5 runs that reached it ("formation 0129").
- **The convergence.** 411's three end plates (`_cc193f`): two parties on
  their plates, the third's step runs `FinalBattle`, which is #274's. The
  last cut of this arc would be the third party on 412's save point with
  the other two on their plates.
- **The machines' hall for party 1.** Formation 413 (Sky Base, four
  IronHitmen) in 352 wiped party 1 in 2 of 8 sweeps of `gen_wor_kt_guardian`
  (7.3).
- **The Gauntlet and the Nutkin Suit** (296, off 339's foot) are left on the
  middle path; a branch leg could fetch them.
