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
4. **Party 3's walk to the factory works end to end** (section 5): from the
   landing, past the crane tile, into 339 from its top door, the factory,
   the hop, and the save point beside Inferno.

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
| 355 the chamber's three plates | all three parties on them at once: the north door (to Guardian) and the south doors | north set; south toggles each time |
| 337 (8,6) | the cell doors (2,4), (14,4) to the west and east lanes | set (`$00D0`) |
| 411 (103,43), (109,40), (115,42) | each walking party sets its own bit; all three set: `FinalBattle` (:926), Kefka | held |

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
| 1 | TERRA 63, RELM 53, EDGAR 34, SETZER 32 | TERRA's Cure, Life | the north-west, the machines' hall; Guardian and the Poltergeist |
| 2 | CELES 63, STRAGO 51, LOCKE 41, MOG 38 | CELES's Cure | the long way west: Atma, the Gold Dragon; the Goddess |
| 3 | CYAN 53, SHADOW 53, SABIN 39, GOGO 44 | SABIN's (Starlet) | the factory: Inferno, the Skull Dragon; Doom |

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

## 8. Not done

(Filled in at the end of the arc's work.)
