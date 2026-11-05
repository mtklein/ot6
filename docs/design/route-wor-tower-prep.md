# World of Ruin: the bench before Kefka's Tower

Issue #496. The tower takes three parties, and through the World of Ruin
eight characters sat on the bench and gained nothing. This doc measures what
each of the tower's parties needs, then designs the training stretch the
line plays before it: `gen_wor_bench`, after `gen_wor_desert`, saving
`wor-bench-v1`, the tower's new boot. The owner's shape for it (2026-10-28):
"about 6-8 characters who were strong and could carry the rest in their
respective parties. no need for everyone to be at the same level."

Evidence is under `build/attempts/wt/v039-bench-training/` (section 7 lists
it; every number below is quoted from a log or a tally there).

---

## 0. Findings

1. **At the tower's old boot six characters are strong and eight are far
   behind.** `wor-desert-v1`: TERRA 64, CELES 63, RELM 55, CYAN, SHADOW and
   STRAGO 53; then GOGO 44, LOCKE 41, SABIN 40, MOG 38, UMARO 37, EDGAR 34,
   GAU 33, SETZER 32 (mean 45.7, max 64).
2. **The tower's first map is the real test, and its pool is hard.** Map 334
   (pool group 208) deals Vectaur x4 (271), Brontaur with Evil Oscar (272)
   and, 96 rolls in 256, GtBehemoth with Evil Oscar and a Vectaur (329), whose
   Meteor hits the whole party: it killed members standing at up to 1,068 HP,
   195 deaths over the two rounds below. Every formation refuses the run. All
   but four of the battles lost in this doc were 329.
3. **A strong physical member with a healer carries two of the bench at any
   level; two mages do not carry even with all their levels.** On the old
   boot, TERRA (64) and SHADOW (53) with SABIN (40) and EDGAR (34) won 60 of
   60 battles; CELES (63) alone with LOCKE (41), MOG (38) and UMARO (37) won
   60 of 60. RELM (55) and STRAGO (53), who know no cure and whose Fights land
   little, lost with the two weakest beside them in 4 of 6 runs and with
   GOGO (44) and LOCKE (41) beside them in 6 of 6.
4. **The bench is a liability under about L40 and competent from there.**
   The four weakest (L32-37) with no one carrying them lost 4 of 6 runs; the
   bench's best four (L38-44) with no one carrying them lost 1 of 6.
5. **The carried die a lot even when the party wins.** In the winning arms a
   member fell about once in three battles (A: 21 deaths in 60 battles; C: 18
   in 60), almost all of them in 329. The guidelines read a Fenix Down in a
   random as under-levelling; at the old boot the bench is.
6. **The training stretch.** `gen_wor_bench` rotates the bench through the
   plain by Maranda two at a time beside SHADOW and CYAN, until the six to be
   carried stand at L40 and SABIN and GOGO, the two who join the six strong,
   at L48. The line's play: 63 battles, 4 deaths, about 66 minutes of game
   time (237,320 frames). The fourteen go from mean 45.7 to 49.6; the max
   stays TERRA's 64; SHADOW and CYAN, the carriers, rise from 53 to 61.
7. **After it the designed parties win the tower's first map.** From the new
   boot, TERRA and SHADOW with EDGAR and GAU, CELES and CYAN with SETZER and
   UMARO, and RELM, STRAGO, SABIN and GOGO won 140 of 140, 140 of 140 and 130
   of 131 battles over 14 runs each (one run of the third party wiped). Deaths
   fell from about one in three battles to 32 in 140 (GAU 21 of them), 1 in
   140 and 21 in 131. The four at L40 with no carrier still lose half their
   runs: they are trained to be carried, not to stand alone.

## 1. The fourteen at the tower's boot

`tools/roster.py` reads every character's record in a save (the party
reader, `savestate_party.py`, reads only the members a party holds). The
boot is the graph's own capture of main's play (16304ff5; px13, from
v038-harness-fixes's build at 0d96f044, the play at 9a624949):
`wor-desert.sram` sha256 2abd8b07, byte for byte main's tracked
`wor-desert-v1` (`roster_wor_desert.txt`):

| character | L | HP | esper | weapon | relics | cures it knows |
|---|---|---|---|---|---|---|
| TERRA | 64 | 5687 | Maduin | Falchion | Ribbon, Economizer | Cure, Life (natural) |
| CELES | 63 | 5539 | Tritoch | Scimitar, Falchion | Genji Glove, Wall Ring | Cure (natural) |
| RELM | 55 | 5475 | Ragnarok | Magus Rod | -, Wall Ring | none |
| CYAN | 53 | 4126 | Alexandr | Strato x2 | Genji Glove, Ribbon | none |
| SHADOW | 53 | 4124 | - | Striker | Ribbon, Hyper Wrist | none |
| STRAGO | 53 | 4108 | Palidor | Pearl Rod | -, Hero Ring | none |
| GOGO | 44 | 2984 | - | Man Eater | -, Safety Bit | none |
| LOCKE | 41 | 2653 | Shiva | Wing Edge | -, Back Guard | none |
| SABIN | 40 | 2552 | Starlet | Dragon Claw, Fire Knuckle | Genji Glove, Hero Ring | Cure (Starlet) |
| MOG | 38 | 2315 | Terrato | Partisan | Amulet, Hyper Wrist | none |
| UMARO | 37 | 2229 | - | Bone Club | Gauntlet, Atlas Armlet | none |
| EDGAR | 34 | 1905 | Ramuh | Man Eater | RunningShoes x2 | none |
| GAU | 33 | 1799 | - | - | -, Peace Ring | none |
| SETZER | 32 | 1698 | Unicorn | Trump | Hero Ring, Exp. Egg | (Unicorn's) |

"Cures it knows" is the lab's own read (`H.knowsSpell`: learned, or granted by
the equipped esper while it is worn, DESIGN.md "Magicite as sub-jobs"). Only
three of the fourteen hold a cure at the boot.

## 2. The tower's first map, from the old boot

`tools/tests/lab_tower_split.lua` (an instrument, `@manual`) Continues a save
beside the Falcon, flies to the tower (world (137,198): the one World of Ruin
tile whose property word has bit `$8000`, `LandAirship`'s `VehicleEvent_04`
-> `EnterKefkasTower`), seats the three groups `party_menu 3` offers, lands
on map 334 with all three parties there (party 1 at (9,16), 2 at (43,21), 3
at (56,22)), and walks one party on a two-tile lap for ten battles, the
walker playing them and the field care between. Encounters are used up first
(K = 0, 3, 6) by a second party fighting them on the same map (the map's
formations refuse the run), so the draw moves and the measured party starts
as the split seated it; seed shifts 0 and 7. Tallied by
`tools/tower_tally.py` by distinct battle key.

The bosses (Guardian, Inferno, the three statues, the Gold and Skull Dragons)
were not reached: they stand past the tower's multi-party switches, which are
#273's route. Their data is in section 6.

Two rounds, the same 48 runs each (8 arms x 3 K x 2 shifts). Round 1 cared
as the walker does by default (to 65%, the bag shared by member count);
round 2 as the line's forest and desert do (to full, casting first) with
three quarters of the bag given to the measured party. Battles won / lost,
runs that ended in a wipe, deaths, Fenix Downs spent (`tally_round1.txt`,
`tally_round2.txt`):

| arm | party (L) | round 1 | round 2 |
|---|---|---|---|
| A | TERRA 64, SHADOW 53, SABIN 40, EDGAR 34 | 60/0, 0 wipes, 14 deaths, 14 Fenix | 60/0, 0 wipes, 21 deaths, 21 Fenix |
| C | CELES 63, LOCKE 41, MOG 38, UMARO 37 | 60/0, 0 wipes, 32 deaths, 31 Fenix | 60/0, 0 wipes, 18 deaths, 17 Fenix |
| G | TERRA 64, CELES 63, GAU 33, SETZER 32 | 57/1, 1 wipe, 38 deaths | 58/1, 1 wipe, 19 deaths |
| E | GOGO 44, LOCKE 41, SABIN 40, MOG 38 | 58/1, 1 wipe, 28 deaths | 59/1, 1 wipe, 20 deaths |
| D | CYAN 53, EDGAR 34, GAU 33, SETZER 32 | 39/6, 6 wipes | 52/3, 3 wipes |
| F | SETZER 32, GAU 33, EDGAR 34, UMARO 37 | 31/5, 5 wipes | 34/4, 4 wipes |
| B | RELM 55, STRAGO 53, GAU 33, SETZER 32 | 20/6, 6 wipes | 40/4, 4 wipes |
| H | RELM 55, STRAGO 53, GOGO 44, LOCKE 41 | 14/6, 6 wipes | 16/6, 6 wipes |

What the rounds say:

- **Formation 329 decides it.** Of every lost battle in both rounds, all but
  four (272 three times, 271 once) were 329, and it holds most deaths (round
  2, A: "form 329: won 42; deaths 20"; B: "form 329: lost 4, won 25; deaths
  65"). The GtBehemoth's Meteor (`cmd $02 atk $13`) hits all four: "[death]
  f+3262 entity 2 char 11 from 987/1901 by slot 0 cmd $02 atk $13" and SETZER
  from 560/2005 in the same Meteor (`lab/B_b0_s0`); the highest HP it killed
  from was 1,068 (`lab2/B_k6_s7`). A member at L32-34 (1,698-1,905 HP) stands
  one Meteor from full and not two; at L40 (about 2,540) two leave little.
- **The carrier is a physical member with a cure.** A, C and G, with TERRA or
  CELES, lost one run of 18 in each round (G's, with the two weakest). B and
  H, the two mages, lost 22 of 24 runs over the two rounds. H's party knew no
  cure ("[lab] party 1's cures: none"); in round 1 it entered 329 at a third
  of its HP once the care's Potions ran out, and STRAGO's Fight landed
  nothing on the Evil Oscar ("actor=1's fight took 0 off the monsters",
  `lab/H_k0_s0`).
  The mages are a kit question for the tower (#273): Lores, Sketch, a cure
  esper on one of them.
- **Care to full helps the weak arms, not the strong.** B went from 6 wipes to
  4, D from 6 to 3; A and C won everything either way.
- **Levels under about L40 are the liability.** F (L32-37) lost 4-5 of 6
  runs on its own; E (L38-44) lost 1. The deaths in the winning arms are the
  carried members': GAU 14-25 times an arm, LOCKE 12-22.

## 3. The design

The tower seats twelve. Six are strong already; the shape is "6-8 strong
characters ... carry the rest". Section 2 sets what the rest need:

- **each party a physical carrier with a cure**: TERRA and CELES know Cure,
  SABIN holds it through Starlet. So the three parties are built round
  TERRA, CELES and a third party that has SABIN;
- **the third party's strong pair are RELM and STRAGO**, who carry no one
  (B, H). It needs two more strong members: SABIN (the cure, Blitz) and GOGO
  (Mimic), the bench's two highest. With them it is the eight strong of the
  owner's 6-8;
- **the carried at L40**: the level where four of the bench stop losing
  their own runs (E against F), and where a member stands a Meteor with
  room for the next turn's hit (HP 2,533-2,554 at L40 against 1,698-1,905
  at L32-34; section 2);
- **the max where it is**: TERRA and CELES do not train. The carriers are
  SHADOW and CYAN, the two strong physical members at L53.

The parties this points the tower at (#273's to settle): TERRA, SHADOW and
two of the carried; CELES, CYAN and two of the carried; RELM, STRAGO, SABIN
and GOGO. Two of LOCKE, MOG, EDGAR, UMARO, GAU and SETZER sit out.

**Where.** The plain by Maranda (world group 49), at the Falcon's tile the
desert's save stands on: the World of Ruin's grind (level-curve.md, 3,168 a
member of four a random), and the plain `gen_wor_dino` already grinds
before the forest, so nothing new is met. The forest's two Tyranosaurs
(Meteor twice a round) would kill a member at L32 before the carriers act.

**How.** Each rotation seats the two trainees who need the most experience
beside SHADOW and CYAN (the cabin: `regroup`, which moves the Ribbons to the
seated), flies the Falcon back to its tile, and paces the plain until one of
the two reaches its goal; Kohlingen's counter when the bag falls under half
its band, and its gear stop dresses the trainees then (EDGAR came out with a
Pearl Lance and a Red Jacket). At the end the line's four go back in the
cabin and the leg saves on the Falcon's tile.

**Coverage hunts that fit.** None: group 49's formations are all won on the
line already (#483), and the hunts left on branch legs (#485, #488) are on
other maps.

## 4. The line's play of `gen_wor_bench`

The graph's own play on px13, booted from the `wor-desert-v1` capture
(`graph/wor_bench_graph.log`):

```
[ot6] [bench] f1002 boot; SETZER L32/40, GAU L33/40, EDGAR L34/40, UMARO L37/40, MOG L38/40, LOCKE L41/40, SABIN L40/48, GOGO L44/48, SHADOW L53, CELES L63, CYAN L53, TERRA L64
[ot6] [bench] f50850 rotation 1: 14 battles (won 13F x9, won 143 x4, won 146 x1); SETZER L40/40, ... SABIN L42/48
[ot6] [bench] f133939 rotation 2: 22 battles (won 13F x9, won 143 x13); ... GAU L40/40, ... SABIN L47/48
[ot6] [bench] f234554 the bench's training: 63 battles (won 13F x33, won 143 x29, won 146 x1); SETZER L40/40, GAU L40/40, EDGAR L40/40, UMARO L40/40, MOG L40/40, LOCKE L41/40, SABIN L48/48, GOGO L48/48, SHADOW L61, CELES L63, CYAN L61, TERRA L64
[ot6] PASS (frame 237320) attempts=1/3
```

Seven rotations, 63 battles, 4 deaths (CYAN and GAU in rotation 2, GOGO and
MOG in rotation 5), one trip to Kohlingen. SETZER's Exp. Egg doubles his
share, so he reached L40 in the first rotation. `checkpoint_drift.py` after
`--recut wor-bench-v1`: "none -- the tracked save is the one the graph's play
makes today". The fourteen at the new boot (`roster_wor_bench.txt`):

| | TERRA | CELES | CYAN | SHADOW | RELM | STRAGO | SABIN | GOGO | LOCKE | EDGAR | SETZER | MOG | GAU | UMARO | mean |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `wor-desert-v1` (main) | 64 | 63 | 53 | 53 | 55 | 53 | 40 | 44 | 41 | 34 | 32 | 38 | 33 | 37 | 45.7 |
| `wor-bench-v1` | 64 | 63 | 61 | 61 | 55 | 53 | 48 | 48 | 41 | 40 | 40 | 40 | 40 | 40 | 49.6 |

**Across draws.** The leg from the same capture at seed shifts 7 and 20 and
with 2 or 5 encounters fought first on the plain (`scripts/mk_benchk.py`):
6 of 6 PASS, 62-63 battles, 1-4 deaths, 116 distinct battle keys over the
six (`bsweep3/tally.txt`):

```
b_k0_s7 rc=0: PASS (frame 230975) ... 62 battles (won 13F x33, won 143 x28, won 146 x1); SETZER L40/40, GAU L40/40, EDGAR L40/40, UMARO L40/40, MOG L40/40, LOCKE L41/40, SABIN L48/48, GOGO L48/48, SHADOW L61, CELES L63, CYAN L61, TERRA L64
b_k5_s0 rc=0 (used up 5 first): PASS (frame 266062) ... 63 battles ...; SHADOW L62, CELES L64, CYAN L62, TERRA L65
```

Two versions failed on the way, and are kept. The first ended a rotation as
soon as either of its pair stood at its goal, and counted the rider seated
beside the last trainee: four runs of six spent their last rotations on 0
battles and failed "every trainee at its goal within 12 rotations" with one
trainee a level short (`bsweep/b_k2_s0`: "rotation 7: 0 battles" through
"rotation 12: 0 battles", MOG L39/40). The second waited for both of the pair:
6 of 6 PASS, but SETZER, whose Exp. Egg doubles his share, ran on to L50 beside
SABIN, 79-84 battles (`bsweep2/tally.txt`). The leg now ends a rotation when
one of its pair who sat under its goal reaches it. The graph's play of that
version (`graph/wor_bench_graph2.log`, 1e7bc2cc) is the first's to the frame
("PASS (frame 237320)", drift "none" against the save already re-cut): the
rider never mattered at shift 0.

**What it depends on (#480).** Hard, asserted at the start: every trainee and
both carriers recruited (the party menu's mask, `$1EDE`), and gil for
Kohlingen's counter (60,000). The experience table read off the ROM is checked
against each trainee's own level before it sets a goal. Soft, fixed in the
leg: who is seated (the cabin), the bag (Kohlingen), HP (the care to full,
casting first), the trainees' gear (Kohlingen's gear stop). The negatives,
lab batteries made from the graph's capture with one byte or the gil edited
(`scripts/make_negative.py`), both red at their asserts:

```
neg/neg_bench_norecruit: [deps] recruited mask $B7FF; missing: GAU
  FAIL: ... assertEq failed: every trainee and carrier recruited ($1EDE: the arcs up to gen_wor_colosseum): got 1 ($1), want 0 ($0)
neg/neg_bench_poor: FAIL: ... assertEq failed: gil for Kohlingen's top-ups: 1000 GP, the floor 60000 (the line's purse): got false, want true
```

The positive control is the line's play: "[deps] recruited mask $BFFF;
missing: none".

## 5. The tower's first map, from the new boot

The lab again, booting the graph's `wor-bench-v1` capture (703fcc7b), care to
full as round 2, the designed parties (T1-T3) and two references: T4, four of
the trained bench at L40 with no carrier (F before the training), and T5, the
two mages with LOCKE (41) and MOG (40). Two batches: K 0, 3, 6 at shifts 0
and 7 (`tally_round3_v1boot.txt`, round 3) and K 0, 6, 12, 18 at the same
shifts (`tally_lab5_benchboot_full.txt`). The save's encounter seed changed
with the training, and from it the map deals mostly 272 (Brontaur and Evil
Oscar) where the old boot dealt mostly 329, so the old boot was swept again at
K 12 and 18 for 272 (`tally_lab4_oldboot_k12k18_full.txt`):

| arm | party (L) | runs | battles won / lost | deaths | deaths a battle |
|---|---|---|---|---|---|
| T1 | TERRA 64, SHADOW 61, EDGAR 40, GAU 40 | 14, 0 wiped | 140 / 0 | 32 (GAU 21) | 0.23 |
| T2 | CELES 63, CYAN 61, SETZER 40, UMARO 40 | 14, 0 wiped | 140 / 0 | 1 | 0.01 |
| T3 | RELM 55, STRAGO 53, SABIN 48, GOGO 48 | 14, 1 wiped | 130 / 1 | 21 | 0.16 |
| T4 | SETZER, GAU, EDGAR, UMARO, all 40 | 14, 8 wiped | 93 / 8 | 82 | 0.81 |
| T5 | RELM 55, STRAGO 53, LOCKE 41, MOG 40 | 6, 5 wiped | 31 / 5 | 86 | 2.4 |
| *old boot, K 12-18:* A | TERRA 64, SHADOW 53, SABIN 40, EDGAR 34 | 4, 0 wiped | 40 / 0 | 5 | 0.13 |
| C | CELES 63, LOCKE 41, MOG 38, UMARO 37 | 4, 1 wiped | 31 / 1 | 15 | 0.47 |
| E | GOGO 44, LOCKE 41, SABIN 40, MOG 38 | 4, 2 wiped | 26 / 2 | 19 | 0.68 |
| F | SETZER 32, GAU 33, EDGAR 34, UMARO 37 | 4, 4 wiped | 11 / 4 | 25 | 1.7 |
| G | TERRA 64, CELES 63, GAU 33, SETZER 32 | 4, 0 wiped | 40 / 0 | 13 | 0.33 |

Quoted from the tallies: "T2: 8 runs, 0 FAIL; battles {'won': 80}; distinct
keys 64; deaths none" (K 0-18); "T1: 6 runs, 0 FAIL; battles {'won': 60};
distinct keys 50; deaths {'TERRA': 5, 'EDGAR': 1, 'GAU': 11}" (round 3);
"T3: 6 runs, 1 FAIL; battles {'won': 50, 'lost': 1}" (round 3, the loss in
272); "T4: 8 runs, 4 FAIL; battles {'won': 57, 'lost': 4}" (K 0-18).

- **The three designed parties hold.** T2 lost no one in 140 battles; T3,
  with SABIN's cure and the two new strong members, lost one run of 14 where
  the mages with two of the bench (B, H, T5) lost most of theirs.
- **GAU is the casualty.** He has no weapon to wear, and 21 of T1's 32 deaths
  are his. #273 has two of the six carried to leave out; GAU is the first
  candidate.
- **The bench is trained to be carried, not to stand alone**: T4 lost 8 of
  14 runs. A fourth strong party is not what the owner's shape asks for.
- **The old boot fares better on 272 than on 329**: A lost 5 members in 40
  battles at K 12-18 against 21 in 60 at K 0-6. Rows compare within a boot;
  across boots, the formation mix moves with the save's seed.

## 6. The bosses' data

Not reached by the lab (section 2). From the built ROM (`route_data.py
species`, `tower_bosses.txt`); every one but Guardian still stands on the
generated six-shield floor row, which #273 designs:

| species | L | HP | weak / absorbs | what bites |
|---|---|---|---|---|
| Guardian `$111` | 71 | 50,000 | - | atk 250, evade 50; counters every hit with Battle |
| Guardian `$112` | 67 | 60,000 | weak bolt, water | WaveCannon (110), Flare (60), Meteo (60), Flare Star, Atomic Ray; Entwine (Slow), Stone (Muddle) |
| Inferno `$10C` | 67 | 30,800 | weak bolt; absorbs fire | Bolt 3, Giga Volt (110), Meteor, Atomic Ray; Delta Hit (Petrify); counters with Sobat (x3) |
| Doom `$127` | 73 | 63,000 | weak holy; absorbs ice, poison | Ice 3, Absolute 0 (110), N. Cross (Frozen); Demon Rage (x4, cannot be dodged) |
| Goddess `$128` | 68 | 44,000 | absorbs bolt, holy | Overcast (Condemned), Bolt 3, Quasar, Flash Rain; Lullaby (Sleep), Charm; starts with Haste and Shell |
| Poltrgeist `$129` | 67 | 58,000 | weak poison; absorbs fire, wind | S. Cross (120), Shrapnel (120), Aero (125), WaveCannon, Blaster (Death), Stop; counters with Fire 3; starts with Image, Haste, Safe, Float |
| Gold Drgn `$150` | 62 | 32,400 | weak water; absorbs bolt | Bolt 3, Giga Volt (110); counters with Bolt, Bolt 2 |
| Skull Drgn `$151` | 62 | 32,800 | weak fire, holy; absorbs poison | Condemned, Disaster (Muddle, Imp, Mute ...), Specter (Muddle), Elf Fire |

The carried members' HP matters most against the all-target spells here
(Meteo, Flare Star, Quasar, Flash Rain, Giga Volt): a member at L40 has
about 2,550.

## 7. Not done, and for the owner

- **The bosses** were not fought; they are #273's, past the tower's
  switches. Their parties' levels are this doc's estimate only.
- **The tower's own pool past map 334** (maps 287-355, groups 208-227) was
  not walked. Map 334 is the first map every party crosses.
- **The mages' kit** (RELM and STRAGO carrying no one, section 2) is a kit
  question for #273, not a level one.
- **For the owner, a pacing question.** The training is about 66 minutes of
  game time on the plain. The tower's own randoms pay the carried better
  than any plain (2,800-4,150 a member a battle: EDGAR went from L34 to L38
  in ten of them, `lab/A_k0_s0`), so a player could also take the carried in
  at their old levels and let the tower train them, at the price of a Fenix
  Down about every three battles. The line trains first; whether that is the
  feel wanted is the owner's call.

## 8. Evidence

`build/attempts/wt/v039-bench-training/`:

- `boot/wor-desert-v1/` the graph's capture the labs booted; `roster_*.txt`;
- `lab/` round 1 (and `lab_flee/`, the first try at using up encounters by
  running, which the map refuses: "this formation cannot be run from
  ($B1=02 $2F4B=00)", kept and not counted); `lab2/` round 2; `lab4/` the
  old boot at K 12 and 18; `lab3/` and `lab5/` the tower from the new boot;
  each run's `run.log.gz`, `lab.txt`, `script.lua`, `env.txt`, `commit.txt`,
  `rom.txt`, `boot.txt` (the sha256 of the battery it Continued);
- `tally_round1.txt`, `tally_round2.txt`, `tally_round3_v1boot.txt`,
  `tally_lab4_oldboot_k12k18_full.txt`, `tally_lab5_benchboot_full.txt`
  (`tools/tower_tally.py --by-arm`);
- `bench/bench_s0/` the first play of `gen_wor_bench` as a lab; `graph/` the
  graph's own plays (`wor_bench_graph.log`, `wor_bench_graph2.log`);
  `bsweep/`, `bsweep2/`, `bsweep3/` the three versions' sweeps (the last is
  the leg's; `bsweep3/tally.txt`, `scripts/benchtally.py`); `neg/` the
  negatives;
- `tower_bosses.txt`; `scripts/` (the runners, the arm makers, the K variants,
  `make_negative.py`).
