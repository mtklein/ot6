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

Evidence is under `build/attempts/wt/v039-kefka-tower/` (the statues and the
Gauntlet branch: `build/attempts/wt/v039-kefka-tower-2/`). Line numbers are
into `ff6/src/event/event_main.asm` unless a file is named.

---

## 0. Findings

1. **The tower is three closed lanes until the parties open them for each
   other.** Each party lands in its own corner of map 334 and can reach only
   its own rooms until another party throws a switch for it (section 2).
2. **Almost every species the tower deals is met nowhere else.** No pool or
   event battle outside the tower deals any of its 34 species, with one
   exception: the Colosseum (`ColosseumProp`, ff6/src/menu/colosseum.asm)
   deals 21 of them as opponents (Brontaur, Dark Force, Didalos, Doom
   Drgn, Dueller, Evil Oscar, Fortis, GtBehemoth, Hemophyte, Innoc,
   IronHitman, Land Worm, Madam, Outsider, Retainer, Scullion, Sky Base,
   Steroidite, Vectagoyle, Vectaur, Veteran). Their new rows move those
   Colosseum fights too; the wagers the line makes there are untouched
   (section 3).
3. **The Guardian the tower fights is its own record.** Battle 140 is
   Guardian `$112`; battle 76, the only other group that deals it, is never
   called. `$112` gets a real row; the World of Balance's `$111` (battle 75)
   stays without a gauge.
4. **The line plays the tower to Doom's save point** on the graph, five
   cuts (section 5): the factory, Inferno, Atma, Guardian, Doom; the Gold and
   Skull Dragons on the way. Inferno, Atma, both dragons, Guardian and Doom
   are not coin flips (8 of 8 or 11 of 12 and better across draws, section
   6).
5. **The chamber's columns set the lanes**: the order the weights fall puts
   party 1 east (the Goddess), party 3 west (Doom), party 2 the middle
   (Guardian, the Poltergeist).
6. **The statues want the bench levelled in the tower first.** At the
   bench's own levels (L40-46) from Guardian's save, Doom won 10 of 16 and
   the Poltergeist 2 of 16. Twenty-odd of each lane's own random battles
   (the bench to L46) and a dress against Doom's ice make Doom 9 of 9 (8
   distinct keys), and the leg 7 of 7. The Poltergeist (party 2) and the
   Goddess (party 1) stay short of every draw: about 7 or 8 of 9 at L46-50
   (section 6.1), and party 1's lane randoms wipe it while it trains.
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

Inferno's arms are not machines: Striker and Rough take the blade (slash)
as well as the point or the blow, where the machines never do.

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
the killer (that doc is deleted; `git show
6866fa97:docs/design/route-wor-tower-prep.md` has it).

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
| `gen_wor_kt_doom` | `wor-kt-guardian-v1` | `wor-kt-doom-v1` | party 2 back through the chamber's south door to 337 (8,6): the cell doors open, and it stays there; party 3 down the west column and lane to 355 below Doom, its bench trained to L46 on that floor (`T.trainLap`), dressed against his ice (`H.elementDress`), Doom (battle 98), Save on his save point (355 (64,11)) |
| `gen_wor_kt_poltergeist` | `wor-kt-doom-v1` | `wor-kt-poltergeist-v1` | party 2 from 337 (8,6) north through the chamber's middle, 291 and 287 to 334's north; the Ribbon (29,29) on LOCKE over the Back Gauge; the bench to L50 on that floor; dressed against fire, Wall Rings on STRAGO and MOG, a bludgeon (the Pearl Rod) for STRAGO; the Poltergeist (battle 100); the Ribbon off LOCKE into the bag for party 1; through (30,11) to 412, Save on its save point (82,47) |
| `gen_wor_kt_goddess` | `wor-kt-poltergeist-v1` | `wor-kt-goddess-v1` | party 1 puts on party 2's Ribbon (its second), down the east column to 337's east cell and into 355's east lane, its bench to L46 there; on through 291's east room to 354; dressed against bolts; the Goddess (battle 99); a battle on her floor if her Overcast left a Zombie; Save on her save point (354 (12,31)) with party 1 standing |
| `gen_wor_kt_plates` | `wor-kt-goddess-v1` | `wor-kt-plates-v1` | party 1 north to 411's right plate (115,42), party 3 up the ladder to its left plate (103,43); party 2 Saves on 412's save point: two plate bits set, Kefka's boot (#274) |

The factory hall's two chests (the Gauntlet, the Nutkin Suit) are reached
from 296, the dead end off 339's foot (the same treasure bits): the middle
path leaves them, and the branch `gen_wor_kt_gauntlet` (from
`wor-kt-inferno-v1`, nothing boots it) fetches them: party 3 steps on the
hall's tile 410 (43,23) (`_cc13c6`), which carries it back to the factory's
west column (6,17), then 339's top door, 334's east side, 339's foot
(334 (48,36)) and 296. 8 of 8 across seed shifts (`gt0`, `gtsw`).

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

### 6.1 The statues from Guardian's save (#273, second part)

Labbed from the graph's `wor-kt-guardian-v1` capture (sha256 6e295e91, the
tracked save byte for byte) by `lab_statue.lua` (evidence
`build/attempts/wt/v039-kefka-tower-2/`, `scripts/`): party 2 opens the cell
doors, then one lane's party laps two tiles of its own floor until its
bench reaches the level (`KT_TRAIN`), then K more battles (K = 0, 3, 6: the
encounter history moves past the training's), then the statue; three seed
shifts (0, 2, 6) each. Tallied by `stattally.py` (`tallies.txt`): a loss
before the outcome line is the game's own game over, counted from the
statue's last battle key.

| arm | lever | Doom (party 3) | Poltergeist (party 2) | Goddess (party 1) |
|---|---|---|---|---|
| `b0` | none: the bench at L40-46 | won 10, lost 6 (6 and 4 keys) | won 2, lost 14 (1 and 6 keys) | won 10, lost 2 (8 and 1) |
| `a2 t46` | the bench to L46 on the lane | won 8, lost 1 | won 7, lost 2 | won 6, lost 1, 2 wiped training on 354 |
| `a2 td` | + dressed against the statue's element | **won 9 of 9, 8 keys, 5 deaths** | (with the Wall Rings' bug below) won 4, lost 5 | the dress refused (below), 7 not reached |
| `a3 pw46` | Poltergeist: + four Wall Rings | | won 7, lost 2 | |
| `a3 pwt46` | + Wall Rings, the fire dress, the wards | | won 7, lost 2 | |
| `a3 g46` | Goddess: the lap on 355's east lane | | | won 6, lost 3 |
| `a4 pt50` | the bench to L50 | | won 7, lost 2 | |
| `a4 pwt50` | L50 + Wall Rings, fire dress, wards | | won 8, lost 1 | |
| `a4 g50` | Goddess: L50 on 355's east lane | | | won 4, lost 1, 3 wiped training |

The line's leg (`dsw/`, `legs/gen_wor_kt_doom_s0`): "Doom: won 7, lost 0;
distinct keys 4; deaths 0" across seed shifts 0-12; the graph-style run
"PASS (frame 102213) attempts=1/3", "party 3 below Doom: after 17 battles:
CYAN L57, SHADOW L57, SABIN L46, GOGO L50". The dress: "SHADOW slot 1 $64 ->
$61" (the Ice Shld, which absorbs ice), "GOGO slot 1 $62 -> $60" (the Flame
Shld, which nulls it).

Negatives (`neg/`, `negs.sh`, lab batteries edited from the capture): the
cell doors already open, "assertEq failed: the cell doors still shut
($00D0): this leg opens them: got 1"; party 3 off its plate, "contract
wor-kt-guardian-v1 (entry) VIOLATED -- 1 field(s) differ: party 3 stands at
x: expected 35, read 36"; party 1 off its plate, "... party 1 stands at x:
expected 43, read 42".

What the labs found:

- **Doom** kills with Ice 3, N. Cross and Absolute 0, then (below half)
  physical Battle and Special under Image and Haste (ai_script.asm `_295`).
  The bench at L46 and the ice dress settle it.
- **The Poltergeist** answers every hit with a third of a chance of Fire 3
  and counts hits to Wave Cannon; below half it casts Flare Star and S.
  Cross (fire), Meteo, Aero. Its Stop is the killer: any member Stopped
  draws Blaster, which kills outright (`if_status_set ..., STOP: BLASTER`);
  the Ribbon does not ward Stop. Wall Rings bounce the Stop (a reflectable
  spell) and stop every Blaster, but they bounce the Fire 3 counters back
  onto the statue, which absorbs fire and heals by about 1,000 a bounce:
  the fight then drags (11,904-46,573 ticks at L50) and attrition takes the
  loss. The 334 Ribbon stays in the bag: `ribbonsOnSeated` keeps every relic
  party 2 wears ("no seated member can take the bag's Ribbon"). STRAGO's
  nuke lore (`nukeLore = { 22 }`, GrandTrain) was never planned (`pg0`),
  and his Pearl Wind (`strago = { pearlWind = true }`, `a5 pwpt50`) was
  never cast: `a5` played the very fights of `a4 pwt50` (the same keys and
  ticks, "won 8, lost 1"), so the boss fight's opts did not reach his
  turns. Why (#512): his battle list is his five-slot loadout, which on
  AUTO holds his first five lores in id order and not GrandTrain, and he
  never learned Pearl Wind; slotted, GrandTrain made the fight longer and
  costlier than his bludgeon (wor-coverage.md 13.7).
- **The Goddess** answers a Fight with Love Token and every hit with Bolt 2,
  casts Overcast (Condemned on the party) every eighth, and Bolt 3, Flash
  Rain, Quasar below half. Party 1 (TERRA, RELM, EDGAR, SETZER) holds one
  Ribbon; its lane's randoms are its worst enemy: formation 428 (the Madam
  and her Outsiders) on 354 and formation 400 (three Innocs, Muddle) on
  355's east lane wiped it during training in 2 of 9 and 3 of 9 runs. The
  element dress failed on EDGAR ("equip options: 4 A presses on the target
  were not taken", the Force Armor) in 5 of 9 runs and is not used.

### 6.2 The Poltergeist from Doom's save (#273, third part)

Labbed by the leg itself (`gen_wor_kt_poltergeist` with a prelude of lab
globals, `lab.sh`) from the graph's `wor-kt-doom-v1` capture (sha256
8e91c280, the tracked save byte for byte), the lap's K more battles
(`KT_BURN`) x seed shifts, tallied by `stattally.py` (evidence
`build/attempts/wt/v039-kefka-tower-3/`, `tally_*.txt`). Every arm: the
334 Ribbon on LOCKE, the bench to L50 on 334's north (42-49 battles), the
fire dress, and the driver's Reflect guard (below).

| arm | lever | runs | won | distinct keys won / lost | deaths in the fight |
|---|---|---|---|---|---|
| `w2` (`p1`, `p2/w2b`, `p3/w2c`) | Wall Rings on STRAGO and MOG | 18 | 16 | 13 / 2 | 28 |
| `w3` (`p1`) | + LOCKE | 9 | 8 | 8 / 1 | 16 |
| `w4` (`p3`) | all four (CELES's Ribbon gives way) | 15 | 10 | 7 / 5 | 41 |
| `l53` (`p4`) | `w2`, the bench to L53 (62-66 battles) | 12 | 11 | 11 / 1 | 17 |
| `s6` (`p4`, ROM 15bc78f1) | `w2`, its shields 8 -> 6 | 12 | 11 | 8 / 1 | 15 |
| **`kb`** (`p5`) | `w2` + the Pearl Rod in STRAGO's hands (a second key) | 15 | **15** | **12 / 0** | 15 |

Quoted: "Poltrgeist: 18 runs; won 16, lost 2, not reached 0; distinct keys
won 13, lost 2; deaths in the fight 28" (`tally_w2all.txt`); "Poltrgeist:
15 runs; won 10, lost 5 ... distinct keys won 7, lost 5" (`tally_w4.txt`);
"Poltrgeist: 12 runs; won 11, lost 1 ... distinct keys won 11, lost 1"
(`tally_l53.txt`); "Poltrgeist: 12 runs; won 11, lost 1 ... distinct keys
won 8, lost 1" (`tally_s6.txt`).

- **Cures had been feeding it.** With Wall Rings on, CELES's Cure on a
  ringed member bounced onto the statue ("[heal-watch] cure $2D on entity 2:
  no rise inside the watch", `v039-kefka-tower-2/a4/pwt50_polt_k0_s0`); the
  driver now casts no cure on a member under Reflect and no party cure
  while one is seated ("no party cure: entity 1 wears Reflect and a cure
  that reaches it bounces onto the enemy", 22 times in `p1/w2_*` (its party-cure lines; 32 counting the single-target ones)), and the
  bag serves them.
- **The Stop is still the killer where it lands on an unringed member.**
  `p2/w2b_polt_k0_s1` (key be9C): LOCKE stopped at f+435, Blaster at
  f+2142, stopped again at f+19111, Blaster at f+19623 ("[death] f+19623
  entity 2 char 1 from 465/3727 by slot 0 cmd $0C atk $B1"). The other
  `w2` loss (`p3/w2c_polt_k0_s4`, beA4) is attrition: Wave Cannon, Fire 3
  and Meteo. More Wall Rings lose more (`w4`): every Fire 3 counter then
  bounces back onto the statue, which absorbs fire.
- **The shields do not decide it.** The statue keys the blow and the cards;
  in party 2 only LOCKE's Wing Edge holds one, and LOCKE mostly Mugs
  ("LOCKE Mug at", "KEYED: Fight at 1 BP lands 2 chip(s) on slot 0's 8
  shield(s)" once or twice a fight), so the statue rarely breaks: be9C
  played the same 19,903 ticks with six shields as with eight
  ("monhp=s0:44130/sh6" near the end), and `s6` lost the same key. The
  shield count stays 8 (no ROM change).
- **A second key settles it** (`kb`, the leg's play): STRAGO trades his
  Imp Halberd (pierce) for the bag's Pearl Rod (bludgeon), "[a bludgeon for
  STRAGO (gear)] slot 0 <- $39", and the party keys the statue 12-16 times
  a fight ("KEYED" lines in `p5/kb_polt_k0_s0`, `k3_s4`) where `w2` keyed
  it once or twice: "Poltrgeist: 15 runs; won 15, lost 0, not reached 0;
  distinct keys won 12, lost 0; deaths in the fight 15; ... ticks
  14042-22664" (`tally_kb.txt`). STRAGO's own options (#512) were not
  needed, and GrandTrain in place of his Fight loses (wor-coverage.md 13.7).

- **Pearl Wind** (#388, wor-coverage.md 13.8): STRAGO learns it in the
  wood west of Jidoor's plain, and on this ROM it heals each member as much
  as his max HP and passes the Wall Rings' Reflect. The leg casts it when
  two standing members are under 60% (`pearlWindBelow`): on 11 distinct
  keys paired from the replayed `wor-kt-doom-v1`, 11 won with 5 deaths
  against 9 won with 17 without it (`build/attempts/wt/v041-wor-skills/polt3`,
  `polt2`).

### 6.3 The Goddess from the Poltergeist's save

`gen_wor_kt_goddess` labbed from the leg's own `wor-kt-poltergeist-v1`
capture (sha256 08caf1f9, `legs/gen_wor_kt_poltergeist_s0`: "PASS (frame
256199) attempts=1/3"), party 1 wearing party 2's Ribbon (its second: "Ribbon
$CA from the bag onto EDGAR's slot 4 (over $B7, rank 0)"), the bench to L46,
the bolt dress, K = 0, 3, 6 x shifts 0, 2, 6:

| arm | the lap | the Goddess | distinct keys | deaths in the fight | deaths on the lap |
|---|---|---|---|---|---|
| `g355` (`p2`) | 355's east lane, 19-27 battles | won 9 of 9 | 8 | 18 | 81 |
| `g354` (`p2`) | 354 below her, 20-25 battles | won 9 of 9 | 9 | 8 | 115 |

Quoted: "Goddess: 9 runs; won 9, lost 0, not reached 0; distinct keys won 8,
lost 0; deaths in the fight 18; lap battles 206, deaths before the statue
81" (`tally_g355.txt`); "... won 9, lost 0 ... distinct keys won 9 ...
lap battles 201, deaths before the statue 115" (`tally_g354.txt`). The
element dress now goes on (the care revives first, with Life where the
split's reserve holds the Fenix Downs), and nobody wiped training.

Nine of the eighteen failed at the save's assert, not the fight: her
Overcast turns a member who falls into a Zombie, and the field menu refuses
Revivify on one ("c9 0/3230 hp: zombie: revivify 57 in the bag, floor 0,
refused", `p2/g355_goddess_k0_s0`). The leg now meets one battle on her
floor while a Zombie stands, where the driver's Revivify cures it:
`p3/g355z` 6 of 6 PASS (K 0, 3 and 6 by shifts 0 and
2). The lane is 355's: fewer deaths on the lap. A tuning note: about four
deaths a run on the lap (81 in 206 battles) is heavy Fenix use for random
battles; EDGAR and SETZER come to it at L41-42 beside TERRA L66.

### 6.4 The three legs played, and their negatives

From the graph's `wor-kt-doom-v1` capture, each leg as the graph's edge
plays it (`leg.sh`, px13, `legs/`): "PASS (frame 262683) attempts=1/3"
(`wor-kt-poltergeist-v1`, sha256 9f275805), "PASS (frame 257694)
attempts=1/3" (`wor-kt-goddess-v1`, d549cbaf), "PASS (frame 2315)
attempts=1/3" (`wor-kt-plates-v1`, 3fa7f7f5). The Goddess from this
Poltergeist capture: "Goddess: 9 runs; won 9, lost 0, not reached 0;
distinct keys won 9, lost 0; deaths in the fight 16" (`tally_gf.txt`); one
run (`p6/gf_goddess_k6_s6`) failed the save's assert on EDGAR at 0 HP
without the Wound bit (the battle's Revivify cured his Zombie and left him
there; the Fenix Down and Life refused): the care now heals such a member,
and the rerun passed (`p7/gf2_goddess_k6_s6`, "char 0 cast $2D on char 4:
0 -> 953 hp").

Negatives (`neg/`, `negs.sh`, `negs2.sh`, lab-only batteries edited by
`make_negative.py`), each red at its assert: "STRAGO holds a bludgeon for
the Poltergeist (hand $24)" (the bag's four bludgeons emptied); "the
Poltergeist not yet fought ($0074)"; party 2 off 337 (8,6), "contract
wor-kt-doom-v1 (entry) VIOLATED -- 1 field(s) differ: party 2 stands at x:
expected 8, read 7"; "a Ribbon in the bag for party 1"; "the Goddess not yet
fought ($0073)"; "no plate of 411 held yet ($02C6)". (#513, v0.41, build/attempts/wt/v041-tower-asserts/px13/lab/) The boot asserts and `T.standing` each have a red: "a bludgeon for STRAGO in the bag or his hands" (the four bludgeons emptied), "a Wall Ring for each of the 2 members ... (1)" (the bag's four Wall Rings set to one), and "party 2 before the Poltergeist: who stands: got CELES 0/5539" / "party 1 before the Goddess: who stands: got TERRA 0/5995" (a copy of the generator, lap dropped, one member struck to 0 HP just before the assert). `gen_wor_kt_gauntlet`:
"296's two chests still shut: got true" (the Nutkin Suit's bit set), and
party 1 walking, "contract wor-kt-inferno-v1 (entry) VIOLATED ... the
walking party ($1A6D): expected 3, read 1". `T.trainLap`
(`neg_trainlap.lua`): "a lap tile the floor reaches from 355 (39,19): got
false" (the floor's reach mutated to nothing), "every member at L99 within
1 battles ... got 4", "a random battle within 1 steps of the lap (1 since
the last)". Its step bound is now the map's own (`K.worstSteps`, the hunt's
bound: "a battle within 162 steps" on 334).

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
main's tracked save ("checkpoint drift wor-desert-v1: 366 byte(s) differ
from the fresh capture (build/checkpoints/wor-desert-v1)", `graph2.log`).
The tower's four legs then play on the graph
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

The bench by Guardian's save (`audit_levels.txt`), levels from before
party 1's training by its landing existed (the leg of 7.4 on, EDGAR and
SETZER stand at L40 or more there): EDGAR 34 -> 36, SETZER 33 -> 35, LOCKE
41 -> 42, SABIN 39 -> 40, MOG 39 -> 40, GOGO 45 -> 46.

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
the two Doom Dragons met and run from in 8 of the 40 runs (`final/leg_s14`,
`leg_s17`, `leg_s19`, `leg_s20`, `burn_k2_s0`, `burn_k2_s8`, `burn_k4_s5`,
`burn_k4_s9`, each "[run] two Doom Dragons in 295: running"), twice without
getting away: `leg_s17` and `burn_k4_s9` both read "flee: no release after
1800 frames; fighting this formation out", the cap on a run's wait, and
fought the pair out; in `burn_k4_s9` a member died (SETZER, "status1=$80") and
the run still passed; "Skull Drgn: won 40, lost 0",
"Gold Drgn: won 40, lost 0", "Guardian: won 40, lost 0; distinct keys 27".

The graph's play (`graph/graph6.log`): "PASS (frame 238691) attempts=1/3",
"checkpoint drift wor-kt-guardian-v1: 33 byte(s) differ", re-cut, "none";
the factory, Inferno and Atma keys "none".

### 7.6 Where the lap battles spent Fenix Downs (#521)

Every replay of the line on #388's branch spent 14-15 Fenix Downs in one
tower leg, so the Kohlingen stop bought 50 as a stopgap. By battle, from the
line's logs (`tools/tests` legs' `[key]`, `[death]` and care `fenix=` lines;
`build/attempts/wt/v041-tower-laps/sh/laps.py`), nearly all of it was party
1, in two places:

- **The Sky Base's L.5 Doom (formation 413, 352).** The line at 62a8b621
  spent 7 of the Guardian leg's 9 there, in two battles: "[death] f+1274
  entity 0 char 0 from 5399/5840 by slot 0 cmd $0C atk $94 (ONE ACTION
  from >= 80%)", EDGAR beside him. L.5 Doom kills each member whose level
  is a multiple of five, and the training by party 1's landing stopped at
  L40 ("party 1 after 20 battles by its landing: TERRA L65, RELM L56,
  EDGAR L40, SETZER L43"). Every one of those battles was won.
- **The Scullion's Condemned (formation 399, 355's east lane).** The
  Scullion (27,000 HP, four shields of pierce and bludgeon) opens with
  Condemned, about 20 counts of 128 frames. Party 3 kills it in 2,650-3,240
  ticks and loses nobody (13 meetings, 0 deaths, land4's Doom leg); party
  1, with one key-holder against it, takes 3,650-5,200 and the count runs
  out first: 6 deaths in its 10 meetings at 62a8b621, 11 in 13 at
  3eb65922, a Fenix Down each. The Innocs, the lane's other formation, cost
  party 1 nothing.

Labbed from the line's `wor-kt-atma-v1` capture (62a8b621), the Guardian
leg at shifts 0-15, one attempt a run (`b1/g*`, `gtally.txt`,
`sh/armtally.py`): `gA` the leg as it was, `gF` with the Sky Base killed
first while a member stands at a multiple of five, `gT` with party 1
trained by its landing to L46 (the Goddess leg's bench level) instead of
L40:

| arm | runs PASS | random battles (distinct keys) | deaths | in 413 | in 329 (334) |
|---|---|---|---|---|---|
| `gA` | 16 of 16 | 547 (234) | 131 | 68 in 29 | 26 in 160 |
| `gF` | 16 of 16 | 547 (234) | 127 | 71 in 29 | 25 in 160 |
| `gT` | 16 of 16 | 945 (253) | 80 | 3 in 3 | 53 in 353 |

Quoted: "ARM gA: 16 runs, 16 PASS; random battles 547 (distinct keys 234),
won 545; deaths 131", "ARM gT: 16 runs, 16 PASS; random battles 945
(distinct keys 253), won 945; deaths 80", "gA 352:019D: battles 29 deaths
68", "gF 352:019D: battles 29 deaths 71". Guardian was won in all 48.

- Killing the Sky Base first changed nothing: its L.5 Doom lands before
  the party's first turn ("[focus] the Sky Base first: TERRA stands at L65"
  and the deaths at f+421). Dropped.
- Training to L46 here does the Goddess leg's training too (her lap runs
  until the bench stands at L46, so it now fights nothing), on a floor
  where party 1 loses a member about once in seven battles rather than
  once in two, and it leaves the bench past L40 ("TERRA L67, RELM L59,
  EDGAR L46, SETZER L52" after 45 battles). Per run the leg spent 5.0 Fenix
  Downs against 8.2, and `gA`'s party 1 still had the Goddess lap's six to
  eleven ahead of it.

**The change** (`gen_wor_kt_guardian`): party 1 trains by its landing to
L46, at most 60 battles; the Goddess leg's lap stays as a fallback. The
`gT` arm above is that change alone (it ran at 8615b87b, before any check
of the fives). The fives are checked on arrival at 292, one random battle short of 352's door (a level can still change in that battle),
after the battles from the landing, party 1 laps on 292's floor while a
member who wears no death guard (the Memento Ring, the Safety Bit) stands
at a multiple of five (`T.trainLap`'s `opts.also`). In the first replay
RELM had entered 352 at L60, past a check made at the landing's end. The
Kohlingen stop (`gen_wor_kt_factory`) buys the tower 35 Fenix Downs rather
than 50: `gen_wor_kefka` wants 10 at Kefka, and the tower's random battles
still spend some (formation 329's Meteor, above). A replay stocked with 30
(`land1/`, ee52d864) spent 21 in the tower, six of them in Doom's battle,
and stopped at Kefka's boot: "the bag for Kefka: 9 Fenix Downs (floor 10)".

**At the final code** (b8e9bca3, from the replay's `wor-kt-atma-v1` at
c601661e, shifts 0-15, `b4/gZ_*`, `gZtally.txt`): "ARM gZ: 16 runs, 16
PASS; random battles 944 (distinct keys 256), won 944; deaths 74", of
them "gZ 334:0149: battles 352 deaths 40". The check at the door ran in
every run and fought no battle there: RELM stood at L60 and wears the
Memento Ring ("party 1 past L.5 Doom's multiples of five before 352: after
0 battles: TERRA L68, RELM L60, EDGAR L46, SETZER L53"); formation 413 was
not met in this grid.

**Two fixes the replay showed** (#521 review):

- *Field care left Poison and Imp on.* Party 1's six Remedies (its share
  of the split bag) were spent, and the care would not touch the other
  parties' twelve: "status1=24 ... antidote=0 ... remedy=12", and EDGAR
  walked on Poison to 1 HP and died twice before 352 (2 of the Guardian
  leg's 8 Fenix Downs at c601661e). The Poison and Imp cures now borrow
  past the reserve when the party's own share is gone (the other rows keep
  a caller's reserve), and Imp takes a Green Cherry before a Remedy;
  `field_zombiecure`'s branch E checks it (green, and red on the care
  before it: "E: the visit cures the poison past the reserve: got false",
  `zc/`). At the same boot and draw the care cures him
  (`b4/gZ_s0`: "plan: cure poison (past the reserve) char 4 with $F5
  (3173/3233 hp, 508/516 mp, status1 25)").
- *The Goddess lost key `be80` every time* (`b3/gd_s0`-`s2`): her
  Overcast left three members fallen or Zombied with the Goddess at 925
  HP, and RELM, the last standing, spent five turns curing Zombies with
  Revivify while she stood at 104-482 HP, until a Zombied ally killed
  her: "died holding 5 BP" on each. The Zombie cure now gives way when the
  last monster is inside the actor's own measured hit
  (`Driver:finishInReach`: "actor=1 no Zombie cure on entity 2: the last
  monster is inside this actor's own hit -- the kill first"). From the
  replay's `wor-kt-poltergeist-v1`, shifts 0-11 (`b4/gdF_*`, `gdW_*`):
  with it the Goddess is won on all 5 distinct keys, `be80` 3 of 3; with
  the old rule (`OT6_FINISH_ZOMBIE = false`) `be80` is lost 3 of 3 and
  the other four keys won, as before.

**The line replayed with both**, from power-on at 3e6e8cea (px13,
`land3/`; the library's changes replay the whole line, and only the five
tower saves from Guardian's on moved): the bag's Fenix Downs by leg,
factory 25 -> 32 (bought to 35), Atma 32 -> 30, Guardian 30 -> 25 (the
care cured EDGAR's Poison past the reserve, "plan: cure poison (past the
reserve) char 4 with $F5"; the check on arrival at 292 fought nothing), Doom
25 -> 21, the Poltergeist 21 -> 20, the Goddess 20 -> 20, won on the
leg's first attempt ("PASS (frame 11683) attempts=1/3"), and Kefka "the
bag for Kefka: 20 Fenix Downs (floor 10)", "PASS (frame 165938)
attempts=1/3". The tower spent 15 of 35 (#388's replays spent 21-29);
its random battles still spend some on every leg but the Goddess's
(#521 stays open for them: formation 329's Meteor first).

### 7.7 Formation 329: the Evil Oscar's counter, not the Meteor (#521)

The deaths 7.6 put on the GtBehemoth's Meteor were the Evil Oscar's.
Formations 329 (GtBehemoth, Evil Oscar, Vectaur) and 272 (Brontaur, Evil
Oscar) seat the Oscar in slot 1, and the deaths read "by slot 1 cmd $00
atk $EF", its Special: Demon Kiss (MonsterProp +$1F = $47, no damage,
Death). Its counter (`AIScript::_183`) is `if_self_dead / end_if / if_cmd
MAGIC / attack SPECIAL, NOTHING, NOTHING`: a spell that leaves it standing
draws Death on the caster one time in three. LOCKE cast his boosted Fire
at it, its weakness, and died from full HP at any level ("actor=2 nuke $00
... [death] f+1332 entity 2 char 1 from 3352/3352 by slot 1 cmd $00 atk
$EF", v0.41's replay); party 1's TERRA did the same on the Guardian leg's
lap (7.6's final grid: "29 g0149 char 0 by slot 1 cmd $00 atk $EF", the
Meteor, `$13`, 5). LOCKE wears no Death guard and cannot wear the bag's
Memento Ring.

The counter models price no Special, so #372's veto and #503's re-aim
missed it. `Driver:counterMagicPlan` (lib/ot6.lua): a spell aimed at a body
whose answer to Magic, walked for a hit it survives, is a Death Special
goes to another standing body, or becomes a Fight when none stands (the
Oscar answers a Fight with nothing); a caster with a Death guard casts as
planned. Only the Evil Oscar answers Magic so (a scan of every species'
retaliation; the Retainer's and Sleep's Death Specials answer only a
killing blow), and it is met only here, so no play upstream moves.
`counter_selftest` checks the walk and the Special.

Measured from the v0.41 replay's captures, one attempt a run
(`build/attempts/wt/v042-tower-deaths/b1_tally.txt`; `COUNTER_MAGIC_OFF`
is the old driver):

| leg (boot, shifts) | arm | runs PASS | battles (distinct keys) | deaths | Fenix | in 329 |
|---|---|---|---|---|---|---|
| Poltergeist (`wor-kt-doom-v1`, 0-15) | old | 16 of 16 | 741 (185) | 78 | 78 | 61 in 336 (59 keys) |
| | new | 16 of 16 | 753 (180) | 2 | 2 | 2 in 336 (59 keys) |
| Guardian (`wor-kt-atma-v1`, 0-11) | old | 12 of 12 | 744 (259) | 73 | 73 | 37 in 264 (60 keys) |
| | new | 12 of 12 | 750 (259) | 43 | 43 | 7 in 270 (58 keys) |

Quoted: "ARM pkA: 16 runs, 16 PASS; battles 741 (distinct keys 185), lost
0; deaths 78 (61 one action); fenix left the bag 78", "ARM pkN: 16 runs,
16 PASS; battles 753 (distinct keys 180), lost 0; deaths 2 (1 one action);
fenix left the bag 2", "ARM gkA: 12 runs, 12 PASS; ... deaths 73 (30 one
action); fenix left the bag 73", "ARM gkN: 12 runs, 12 PASS; ... deaths 43
(5 one action); fenix left the bag 43". No battle was lost in either arm.
The Guardian leg's other deaths are party 1's formations 399 ($18F, the
Scullion's Condemned) and 370, and the Innocs in the chamber (`$1AB`).

## 8. Not done
- **Kefka** (#274) boots `wor-kt-plates-v1`: party 2 on 412's save point
  with parties 1 and 3 on 411's plates. The plate bits stay set once stepped
  on (`_cc193f` sets, only the tower's exit `_cc0f7d` clears), so party 2's
  step from 412 (82,45) to 411's middle plate (109,40) starts FinalBattle.
- **Party 1's lap deaths** (6.3): done in 7.6 (#521): party 1 trains by
  its landing to L46 and the Goddess leg's lap is a fallback.
- **Formation 329's deaths** (334): done in 7.7. They were the Evil
  Oscar's Death counter to a spell, not the GtBehemoth's Meteor, which
  took 5 of the 40 in 7.6's final grid.
- **The Retainers' dying Death** (Atma's walk, formation 426): the
  Retainer ($007) answers the hit that kills it with Tradeoff, a Death
  Special, on whoever struck it (CELES twice from 5691/5691 in v0.41's
  replay). The finish rules price no Special; not labbed.
- **An older lever, worse** (`swap1`, kept): SETZER and GOGO swapped
  (party 1 TERRA, RELM, EDGAR, GOGO; party 3 CYAN, SHADOW, SABIN, SETZER),
  the chamber in the other order (party 1 west to Doom, party 2 east to the
  Goddess, party 3 the middle to Guardian and the Poltergeist). Party 3
  without GOGO lost Inferno in 6 of 12 runs ("Inferno: won 6, lost 5" with
  one wipe before an outcome line; wipe contexts "formation 010C"), and the
  Poltergeist wiped it in all 5 runs that reached it ("formation 0129").
- **The machines' hall for party 1.** Formation 413 (Sky Base, four
  IronHitmen) in 352 wiped party 1 in 2 of 8 sweeps of `gen_wor_kt_guardian`
  before the training and the wards (7.3, 7.4); with them it is "met 16,
  won 16, distinct keys 11" in the final grid (7.5), so it is no longer
  open.
