# World of Ruin: Gogo and the odd corners (Triangle Island, Ebot's Rock, Doom Gaze, the Opera House)

Milestone v0.34, #270: from the save beside the Falcon by Duncan's house
(`wor-gau-v1`, where the v0.33 route ends) into the Zone Eater on Triangle
Island, through its belly to GOGO, to Thamasa and Ebot's Rock (STRAGO's
Hidon), up after Doom Gaze in the sky, and down at the Opera House for the
Dirt Dragon; a save beside the Falcon there (`wor-opera-v1`) is the next
arc's boot.  Duncan's Bum Rush is left out (the issue).

Line numbers are into `ff6/src/event/event_main.asm` unless a file is named.
Evidence is under `build/attempts/wt/v034-wor-gogo/lab/` (the run logs, and
the scripts beside them: the explore and probe bodies `x1`-`x22`; the leg
builder `mkgen.py` and its parts (`belly.lua`, `careful.lua`, `crush.lua`,
`navj.lua`, `belly2.lua`, `warp.lua`, `gogomenu.lua`, `ebot.lua`,
`doom.lua`, `extra.lua`); the variant builder `mkvar.py` (the sweeps); the
mutant builders `mkmut.py` and `rowmuts.sh`; the launchers `lab.sh`,
`go.sh`, `sweep.sh`, `dg.sh`, `mutants.sh` and `qual.sh`; and the readers
`tally.py`, `met.py`, `tri.py`, `jumps.py`, `ev.py` and `findform.py`).

---

## 0. Findings

1. **The Zone Eater is a door, not a fight.**  Triangle Island (world
   group 32, the sector x224-255, y32-63) deals it alone, formation $14F.
   Its script Engulfs; when every member is engulfed `$3EBC` bit 7 is set
   and `VehicleEvent_05` drops the party into its belly, map 276 (10,12).
   It was the island's first battle in every run (sweep `sb2`: the first
   `[key]` line of all 12 runs is `g014F`).  The walks' driver spares it
   (formation `$171` on the spare list) and idles until it Engulfs.
2. **The belly's bridge (276) is a timing walk.**  Three conductors (NPCs
   $10-$12) random-walk rows 30 (x32-40, 45-48) and 32 (x31-34); a touch
   (`_cb8251`) drops the party to (37,17), where the plate (46,17) sets
   `$01F0` and opens the way round to (52,13) and (59,32).  The jumps want
   facing and A.  The walk (`careful.lua`) samples where the conductors
   can be a few steps ahead (Monte Carlo over their measured ranges, lab
   `x5`: `x5_cond.txt`) and steps when the risk is under 0.08, or 0.9 when
   standing off a rest tile.
3. **The crushing room (280) is timer 0.**  It runs 256 frames (`$1189`) and
   the drop ~264; only the tiles where `$01B5` or `$01BF` hold (and the
   corridors at x25-27 and x53-55 from y49 down) are safe.  The way on is
   (26,54) -> 277 (5,28); 277 (4,35) -> 280's west half (15,48); jumps to
   (5,43) -> 278, where GOGO stands at (8,5) (`_cb81c6`, the name menu).
4. **GOGO comes at L42** into the cabin when the party is four.  His
   commands at join are Mimic and three blanks (12 FF FF FF); his status
   menu offers FF 00 02 01 05 07 08 09 0A 0B 0C 0D 0F 13 10 (`$7E9D8A`,
   count at `$7E9D89`).  The leg gives him Lore, Tools and Item (12 0C 09 01
   in `wor-gogo-v1`).  The Warp Stone (two in the bag) takes the party out
   of the belly to the landing (237,52).
5. **Ebot's Rock opens from Thamasa.**  Its mouth (249,223) is a mountain
   tile until `$019A` (`world_2_mod.dat`), set by the scene at Thamasa's
   (22-23,39) with STRAGO and RELM in the party.  Its holes warp at random,
   the rooms of 404 are random (`$01F1-$01F8`), and the coral chests are
   invisible NPCs $10-$14 (flags `$01FA-$01FE`, cleared every map load).
   The hungry chest at (23,19) wants more than 21 coral (var 7, `$1FD0`) and
   sets `$01F9` when fed; the line at (23,7) sets `$01FC` and Hidon (NPC at
   (23,5), battle 94, formation 464) follows.  After Hidon the scene ends at
   Strago's house (349) and the Falcon is parked at (250,231).
6. **Doom Gaze is met in the air.**  Its cells (`$0B00`/`$0B02`,
   `$0B04`/`$0B06`, four-tile units) are rolled at each lift-off; flying
   over one with A held starts the battle.  Its HP carries over in `$1DD3`
   and the beaten flag is `$1DD2` bit 0.  L.5 Doom fells every member whose
   level is a multiple of 5 (TERRA and CELES at L50); RELM's brush (special)
   keys it.
7. **The Opera House's Dirt Dragon** is under the stage: 237 (48,30) -> 231;
   231 (28,24) -> 232 (114,36); the stage master (118,29), spoken to facing
   right, sets `$01F0`; the switch (118,27), facing up with A, drops the
   party into battle 134 (formation 368).  The house's exit (60,51) leads
   down to the world at (31,182).
8. **GOGO's Mimic** copies the party's last action (`SaveForMimic`: `$3F20`
   command, `$3F21` attack, `$3F22`/`$3F23` targets; `mimicreplace` with X
   the acting seat).  Its confirm opens a target select latched on GOGO's
   own seat, which the driver now confirms as it stands (section 5).
9. **Covert's Disappear** (Vanish) made the walks' Fights whiff: one wipe in
   the first belly sweep (`sb_k3_s7`, formation `$15E`: "18 keys 17 won ...
   1.17 deaths/fight").  The driver now re-aims a Fight off a Vanished or
   Imaged body, or casts when every body has faded (`Driver:dodgePlan`; the
   second sweep `sb2`: "$15E ... 14 keys 14 won ... 0.00 deaths").

## 1. The legs

| leg | boots | saves | what |
|---|---|---|---|
| `gen_wor_belly` | `wor-gau-v1` | `wor-belly-v1` | the cabin (TERRA, CELES, RELM, STRAGO), Triangle Island until the Engulf, the bridge, the plate, the save point in the belly (279 (24,4)) |
| `gen_wor_gogo` | `wor-belly-v1` | `wor-gogo-v1` | the crushing room, 277, the west half, GOGO (name menu, his kit), the Warp Stone out, the Falcon to Thamasa, the scene that opens Ebot's Rock, the save by the Falcon (250,229) |
| `gen_wor_ebot` | `wor-gogo-v1` | `wor-ebot-v1` | Ebot's Rock: the holes, the coral, the hungry chest, Hidon, the scene at Strago's house, the save on the Falcon's tile (250,231) |
| `gen_wor_opera` | `wor-ebot-v1` | `wor-opera-v1` | the cabin (CELES, RELM, GOGO, STRAGO), the Opera House, the Dirt Dragon, the Doom Gaze hunt, the save by the Falcon there (30,182); also `wor_opera_switch` (the catwalk's switch: `battle_mimicdriver`'s and `battle_wardline`'s fixture) |

## 2. The order

Duncan's house -> Triangle Island (down on (237,52); the Zone Eater) -> the
belly: the bridge, the plate, the save point -> the crushing room -> 277 ->
the west half -> GOGO -> the Warp Stone -> Thamasa (STRAGO and RELM seated:
the scene at (22-23,39)) -> Ebot's Rock -> Hidon -> the Falcon's cabin -> the
Opera House -> the Dirt Dragon -> Doom Gaze in the air -> the save beside the
Falcon by the Opera House.

The belly is walked by TERRA, CELES, RELM and STRAGO: the highest four, and
STRAGO and RELM are wanted at Thamasa next.  Ebot's Rock is STRAGO's: STRAGO,
RELM, GOGO and TERRA.  At the Falcon after Hidon the cabin seats CELES for
TERRA, and those four (CELES, RELM, GOGO, STRAGO) fight the Dirt Dragon and
then Doom Gaze.  The hunt with TERRA met Doom Gaze 8, 14 and 13 times (lab
`dg`, `dg_terra_*`), with CELES 3, 4 and 5 (`dg_celes_*`: "after meeting 3
... beaten true"), because the gear care that seats CELES hands RELM the
brush, Doom Gaze's key.  For the dragon the two seats are alike (18 of 20
trials each with the lores: section 4), so one cabin stop serves both.

## 3. Species and break rows

Vanilla stats from `route_data.py species`; elements stay vanilla.  Rows in
`ff6/src/battle/ot6_hud.asm`.

**The belly** (field group 170; the four hold pierce (TERRA's dagger),
slash (CELES), bludgeon (the two rods), fire, holy and ice, and no bolt or
poison, so the bodies weak only to those take a class, and each row keys
two of the four):

| species | L / HP | vanilla elements | shields | classes | why |
|---|---|---|---|---|---|
| Karkass `$0DC` | 43 / 3,850 | weak fire, holy; absorbs poison | 3 | slash, bludgeon | a carcass: break the bones |
| Wart Puck `$07D` | 44 / 3,559 | weak fire | 3 | pierce, bludgeon | a warty imp |
| Ogor `$068` | 44 / 4,211 | weak bolt, poison | 3 | slash, pierce | an ogre's hide |
| Tap Dancer `$0F0` | 43 / 4,452 | weak poison | 2 | slash, bludgeon | a dancer |
| Covert `$067` | 44 / 4,530 | weak holy; absorbs poison | 3 | pierce, bludgeon | a ninja (evade 50): pinned or crushed |
| Woolly `$0FA` | 43 / 3,609 | weak fire; absorbs ice, bolt, poison, wind, earth, water | 3 | slash | shear the wool |
| Zone Eater `$171` | 61 / 7,700 | weak holy; absorbs ice | 0 | none | the fight is to be eaten (finding 1): no gauge |

**Ebot's Rock** (field groups 193 and 194, Hidon's event 94).  STRAGO,
RELM, GOGO and TERRA hold bludgeon (the rods), pierce, fire and holy.  It is
STRAGO's quest, so every body takes his rod beside a key of its own:

| species | L / HP | vanilla elements | shields | classes | why |
|---|---|---|---|---|---|
| Warlock `$069` | 38 / 1,300 | weak bolt, poison | 2 | bludgeon, special | a robed caster (mdef 225) |
| Slatter `$074` | 37 / 2,600 | weak holy | 2 | pierce, bludgeon | a shelled crawler |
| Cluck `$09A` | 38 / 2,366 | weak ice; absorbs poison | 2 | slash, bludgeon | a bird |
| Eland `$0A5` | 37 / 2,470 | weak bolt | 2 | pierce, bludgeon | an antelope |
| Hipocampus `$0B5` | 37 / 2,444 | weak fire, holy; absorbs poison | 2 | pierce, bludgeon | a sea horse |
| Displayer `$070` | 38 / 3,826 | weak fire, holy; absorbs poison | 3 | bludgeon, special | an eye |
| Opinicus `$0C8` | 38 / 3,210 | weak fire, holy; absorbs poison | 3 | slash, bludgeon | a griffin |
| Hidon `$123` | 43 / 25,000 | weak fire, holy, earth; absorbs poison | 6 | pierce, bludgeon | STRAGO's old foe |
| Hidonite `$126` | 43 / 3,500 | weak earth; absorbs poison | 2 | slash, bludgeon | a claw |
| Hidonite `$160` | 43 / 3,500 | absorbs fire, ice, bolt, poison, wind, holy, water | 2 | slash, bludgeon | drinks every element: a weapon only |
| Hidonite `$161` | 43 / 3,500 | weak fire, holy; absorbs poison | 2 | pierce, bludgeon | a claw |
| Hidonite `$162` | 43 / 3,500 | weak to every element | 2 | bludgeon | a claw |

**The Opera House and the sky:**

| species | L / HP | vanilla elements | shields | classes | why |
|---|---|---|---|---|---|
| Dirt Drgn `$14C` | 53 / 28,500 | weak wind, water | 6 | pierce, bludgeon | an earth dragon: the floor's pierce and a crushing blow; STRAGO's Aqua Rake is the elemental answer |
| Doom Gaze `$11D` | (the Phoenix Cave arc's row, unchanged) | | 8 | pierce, special | RELM's brush |

`battle_breakwor_gogo` checks the 21 rows in the built ROM, every formation
of the pools (world group 32, field groups 170, 171, 193 and 194, events 94,
134 and 93: "checked 20 formations, 36 formation-species-hands triples")
against the hands that meet them, and the lessons: no gauge on the Zone
Eater; at least two of the belly's four key each body; STRAGO alone keys
all 12 of Ebot's Rock's bodies ("STRAGO alone keys 12 of Ebot's Rock's 12
bodies"); the Dirt Dragon keeps wind and water.  Red on the ROM without
this arc's rows (`bwbase`, at c34651d5: "WoR Gogo arc break row mismatches:
got 71") and on two ROM mutants (`rowmuts.sh`, at c34651d5): Warlock without
bludgeon (`bwmut1`: "$069 Warlock: STRAGO alone holds no key"), the Zone
Eater with a gauge (`bwmut2`: "$171 the Zone Eater draws a gauge").

## 4. The bosses

- **The Zone Eater**: Engulfed on the island's first battle in all 12 runs
  of `sb2` (finding 1).  No lab: the fight is no fight.
- **Hidon** (event 94, with its Hidonites): sweep `se2`, 12 of 12 runs
  PASS, `fight_report_se2.txt`: "$1D0 Hidon+Hidonite ... 11 keys 11 won ...
  89% 38% 2 0.45" (low HP median 89%, worst 38%, at most two down, 0.45
  deaths a fight).  Not a coin flip; no lab.
- **Doom Gaze**: an attrition fight across meetings (its HP carries).  Lab
  `dg` (six runs from `wor-ebot-v1`, three seed shifts per arm): with TERRA
  seated it took 8, 14 and 13 meetings and left 14, 3 and 7 of 27-28 Fenix
  Downs; with CELES seated (and RELM on the brush) 3, 4 and 5 meetings, 26,
  25 and 22 left of 28 (the `[doom] ... after meeting N: hp 0 ... beaten
  true` lines; the bag's first and last `fenix=` in each log).
  The leg seats CELES.
- **The Dirt Dragon** (battle 134; a game over when lost).  Its script casts
  earth on the whole field (Quake, Magnitude8, Slide), strikes with Honed
  Tusk, and answers Float with 50 Gs, which removes Float and nothing else
  (MagicProp $C3, `magic.py C3`).  The labs fight it from
  `wor_opera_switch`, twenty trials an arm (thirty in `dx*`), idle frames
  apart; `dtally.py` pairs each trial with its battle key:

  | lab | seated | the fight | won | keys won every time |
  |---|---|---|---|---|
  | `dd2_plain` | TERRA | the walks' driver | 15 of 20 | |
  | `dd2_lore` | TERRA | Aqua Rake and Aero first (`nukeLore`) | 16 of 20 | |
  | `dd2_back` | TERRA | the lores, STRAGO, RELM and GOGO in the back row | 18 of 20 | |
  | `fl1_lore` | TERRA | the lores, the back row | 18 of 20 | |
  | `fl1` | TERRA | and the Float line | 5 of 12 (stopped) | |
  | `dc_lore` | CELES | the lores, the back row | 18 of 20 | 11 of 13 |
  | `dc_float` | CELES | and the Float line | 17 of 20 | 10 of 13 |
  | `dw_ward` | CELES | the lores and Shell, Safe (`buffVs`) | 18 of 20 | 11 of 13 |
  | `du_ultima` | CELES | the lores and RELM's Ultima | 18 of 20 | 11 of 13 |
  | `du_ultimaward` | CELES | Ultima and Shell | 19 of 20 | 12 of 13 |
  | `du_ultimafloat` | CELES | Ultima and Float | 13 of 20 | 8 of 13 |
  | `dx2_ward` | CELES | Ultima and Shell | 25 of 30 | 14 of 17 |
  | `dx2_dis` | CELES | and STRAGO's Dischord | 22 of 30 | 11 of 17 |

  (The labs before `dx2` built one driver for all their trials, so its
  per-battle memory carried from trial to trial; `dx2` builds one a trial.)
  Float loses every way it was tried: 50 Gs takes it off within 400-1300
  frames of each cast (lab `x26`, the floating mask), and the casts cost
  STRAGO his lores.  Two things the sweeps found mattered more than any
  line: the battle heals sat at bag rows 106-107 (`so3_k3_s7`: "item steer:
  row 0 -> 106", RELM's turn held in the Item list for 1,100 frames of
  Quakes), and CELES, STRAGO and RELM wore Wall Rings from the tower, so the
  party's Cure and Shell turned away from them.  The leg seats CELES (the
  cabin before the Opera House), puts the heals on top of the bag
  (`bagArrange`), trades the Wall Rings for the Earrings, the Czarina Ring
  and the Barrier Ring for this fight (back on for Doom Gaze), and fights
  with the lores, RELM's Ultima, Shell on the party and Dischord.  The opera
  sweeps, K 0-5 at shifts 0 and 7, the Dirt Dragon's line in
  `fight_report_*`:

  | sweep (commit) | the fight | runs | Dirt Drgn keys won | deaths a fight |
  |---|---|---|---|---|
  | `so` (8a75e830) | TERRA seated, the lores, the back row | 10 of 12 | 9 of 11 | 1.18 |
  | `so2` (690e4c04) | CELES, Ultima, Shell | 11 of 12 | 11 of 12 | 1.67 |
  | `so3` (801b332b) | and Dischord | 11 of 12 | 11 of 12 | 1.67 |
  | `so4` (4b618091) | and the heals on top | 11 of 12 | 10 of 11 | 2.09 |
  | `so5` (946c08b1) | and the Wall Rings off | 12 of 12 | 10 of 10 | 1.00 |
  | `so6` (06573b92, shifts 3 and 11) | the same | 12 of 12 | 11 of 11 | 1.55 |

  Over `so5` and `so6` the dragon drew 20 distinct keys and lost none; its
  worst moment in `so6` left the party at 2% of its HP (`low_worst`), so it
  stays a fight.

  **v0.36 (#460).**  Dischord retested from main's `wor_opera_switch`
  (the leg's fixture at cfae9e47), thirty trials an arm twice, idle frames
  apart, a fresh driver a trial (`build/attempts/wt/v036-route/lab/dd_*`,
  `dtally.py`): without it 27 of 30 and 28 of 30 (`dd_ward`, `dd_ward2`),
  with it 24 of 30 and 25 of 30 (`dd_dis`, `dd_dis2`); the key be70 was
  won in all 7 of its trials without Dischord and lost in all 7 with it
  ("be70:WWWW", "be70:xxxx"); beA0 was lost in all four arms.  The leg
  drops Dischord.  The tower no longer leaves Wall Rings on
  (route-wor-thamasa.md 12.2), so the Earrings, the Czarina Ring and the
  Barrier Ring take each member's second relic for the dragon and that
  relic goes back for Doom Gaze.  Sweep `so7` (ef239262, from the chain's
  own `wor-ebot-v1` at that commit, K 0-5 at shifts 0 and 7): 12 of 12
  PASS, the Dirt Dragon 11 keys won of 11, 1.73 deaths a fight, three down
  at most, the party's worst moment 6%; Doom Gaze 26 meetings, 0.50 deaths
  a meeting, every hunt won (`fight_report_so7.txt`).

## 5. GOGO's kit and the Mimic line

GOGO has no Fight row, so the driver's fallbacks had nothing to press for
him; `Driver:mimicLine` (`lib/ot6.lua`) gives him one.  At his window, when
the party's last action (`$3F20`/`$3F21`) is one the line copies
(`M.MIMIC_COPY`: Fight, Magic, SwdTech, Throw, Tools, Blitz, Lore,
X-Magic), struck a monster still standing, and (a spell or a lore) neither
heals nor carries an element a standing target absorbs or nulls, he
Mimics at the bank's planned boost for the turn (Mimic itself is free); its
confirm, a target select latched on his seat, is pressed as it stands.
Otherwise his Lore and Tools rows decide, and then the bag.  `MIMIC_OFF` turns the line
off.  His kit row in `kits.md` ("Gogo -- Mime") has the rest.

`battle_mimicdriver` plays the Dirt Dragon from `wor_opera_switch` (up to
thirteen fights, idle frames apart, until a boosted copy is measured) and
reads the engine: each copy's plan read a command the line copies (the
engine's copy is the party's last action when his turn runs, logged beside
it: lab `x29` saw a plan's copy land on an Item), free (his MP at
`Ot6ActionEnd` equals his MP at `mimicreplace`), its pending pips its
plan's, at least one copy, no more copies than confirmed Mimics, at least
one boosted; then a control from the same snapshot and the idle frames of
the first fight that copied, with `MIMIC_OFF`: GOGO has a command window
(his command menu open on his seat) and makes no copy.  The budget is
measured: lab `x29` (`mkx29.py`, sixteen fights, no early stop) saw a
boosted copy in 5 of 16 fights, so thirteen miss one with odds
(11/16)^13 < 1%.  Passing at 0e49d158 (`md6`): "3 fight(s) with the line:
2 Mimic plan(s), 2 confirmed, 2 copy(ies) for GOGO's seat in 12 command
window(s) of his", "the control fight: 0 copy(ies) for GOGO's seat in 8
command window(s) of his"; again at 06573b92 on the leg's new fixture
(`md7`: "1 fight(s) with the line: 2 Mimic plan(s), 2 confirmed, 1
copy(ies) ... in 8 command window(s)", "the control fight: 0 copy(ies) ...
in 7 command window(s)").  Four mutants (`mkmut.py`, `mutants.sh`), each
red on its assertion: no Mimic plan (`mutA`, 0e49d158: "1. at least one
copy for GOGO's seat: got false"), the copy charged 5 MP in the ROM
(`mutB`, c34651d5: "2. copy 1 is free ... got 343, want 348"), no boost
pressed (`mutC`, 0e49d158: "3. copy 1's pending pips are its plan's: got
0, want 1"), the line ignoring `MIMIC_OFF` (`mutD`, 0e49d158: "control:
with the line off GOGO never Mimics: got 2").

`battle_vanish` gained a part for `Driver:dodgePlan` (finding 9): a Fight
at a Vanished body re-aims, one at a body that can be hit is left alone,
`DODGE_OFF` (the control) leaves the plan as made, and with every body
faded each actor's Fight becomes its cast where it has a Magic row and a
line, else stays a Fight, and some actor casts.  Passing at ff7cda4d
(`r2_battle_vanish`: "actor 2's Fight becomes magic (Magic row true, a line
magic)"); the mutant that never casts (`mkmut2.py V`, `muts2.sh`) is red:
"3. every body faded: actor 2's Fight becomes its cast where it has one,
else stays a Fight: got fight, want magic".

The ward line came with the Dirt Dragon (section 4): `Driver:buffPlan`
(`opts.buffVs`, `BUFF_OFF` the control): Shell, Safe or Haste on each living
member without it, the frailest first, a member at a time, none on a
reflecting member.  `battle_wardline` checks it on the dragon from
`wor_opera_switch`: a ward plan, its target under Shell within 2400 frames,
then the control with no plan and that member never shelled.  Passing at
06573b92 (then `battle_floatline`, `r4_battle_floatline`: "entity 2 under
Shell 1039 frames after the plan", "the control: 0 ward plan(s); entity 2
under Shell: false"); its mutants `WA` (the ward cast on the next member:
"2. its target under Shell within 2400 frames of the plan: got false") and
`WB` (the line ignoring `BUFF_OFF`: "control: with BUFF_OFF no ward plan:
got 1") were red.  WARDLINE_V036

A Float line (`Driver:floatPlan`, `opts.floatVs`) was built beside it and
no leg used it: the dragon's 50 Gs removes Float and nothing else
(MagicProp $C3, `magic.py`), and in lab `x26` the party's Float lasted
400-1300 frames a cast.  It was pruned in v0.36 (#460), with its half of
the suite (then `battle_floatline`).

## 6. Supplies

No counter on the way but Thamasa's.  The bag at `wor-gogo-v1`'s save: 99
Potions, 30 Fenix Downs, 40 Tinctures, 5 Tents (`gg1`: "[wor] ... on the save
tile world (250,229) ... potion=99 tincture=40 fenix=30 ..."); at
`wor-ebot-v1`'s, 97 Potions and 30 Fenix Downs (`ge4`: "on the save tile
world (250,231) ... potion=97 tincture=40 fenix=30"); at
`wor-opera-v1`'s, after the Dirt Dragon and the Doom Gaze hunt: 41
Potions, 19 Fenix Downs, 40 Tinctures, 1 Tent and 633,026 gil (`so5_k0_s0`:
"on the save tile world (30,182) ... potion=41 tincture=40 fenix=19 ...
tent=1 gil=633026"; the play's `wor-ebot-v1` carried 20 Fenix Downs).  The
two fights are where they go; the next arc starts with gil to restock.  GOGO's kit at join holds no weapon
(FF): he has no Fight row to use one.

## 7. Played

Evidence under `build/attempts/wt/v034-wor-gogo/lab/`.  Each sweep run is
one attempt (retries off) from a committed tree (`commit.txt`; `diff.sha256`
of the empty diff), the leg's variant with K battles used up first
(`mkvar.py`: the belly's landing, the passage 277, Ebot's Rock's entry, and
for the Opera House, which deals no randoms, the plain by the Falcon at
Thamasa), K 0-5 at seed shifts 0 and 7.  `tally_<p>.txt` lists each run and
the distinct `[key]` lines by group; `fight_report_<p>.txt` is
`tools/fight_report.py` over the runs.

| leg | sweep (commit) | runs | distinct keys | fights (fight_report) |
|---|---|---|---|---|
| belly | `sb2` (4639ae4b) | 12 of 12 PASS | g014F 2, g015D 13, g015E 14, g0161 7 | Karkass 13 won of 13, 0.00 deaths a fight; Covert+Tap Dancer 14 of 14, 0.00; Ogor+Wart Puck 7 of 7, 0.29 |
| gogo | `sg` (76b9cc54) | 12 of 12 PASS | g014E 2, g015D 3, g015E 4, g0161 2 | all won, 0.00 deaths |
| ebot | `se2` (3ada72cd) | 12 of 12 PASS | g0123 19, g0124 11, g0125 40, g0128 4, g0129 4, g012A 8, g01D0 11 | all won; Hidon+Hidonite 11 of 11, 0.45 deaths a fight, two down at most |
| opera | `so5` (946c08b1) | 12 of 12 PASS | g014D 5, g014E 4, g0170 10, g01CF 29 | Dirt Drgn 10 of 10 won, 1.00 deaths a fight, two down at most; Doom Gaze 29 meetings, 0.24 deaths a meeting |
| opera | `so6` (06573b92, shifts 3, 11) | 12 of 12 PASS | g014D 6, g014E 4, g0170 11, g01CF 26 | Dirt Drgn 11 of 11 won, 1.55 deaths a fight, three down at most; Doom Gaze 26 meetings, 0.46 deaths a meeting |

The opera sweeps before `so5` are in section 4.

Before them: `sb` (the first belly sweep, before `dodgePlan`) 11 of 12, the
wipe to Covert's Vanish (finding 9); `se` (before the Mimic target select
was handled) 5 of 6 passed, one held on GOGO's target select.

The labs the legs were sealed from: `gb2` ("contract wor-belly-v1 (exit):
all 15 fields hold", "PASS (frame 12286)"), `gg1` ("PASS (frame 17999)"),
`ge4` ("PASS (frame 58061) attempts=1/3"), `go3` ("contract wor-opera-v1
(exit): all 20 fields hold", "PASS (frame 36208) attempts=1/3").  The four
tracked checkpoints were sealed from those captures, not yet re-cut from
the graph's play (`checkpoint_drift.py --recut`, at the release).

## 8. Open

1. **The belly's chests** (the Genji Armor, the Hero Ring and the rest) are
   not opened; the walks keep to the way on.
2. **GOGO is L42** against TERRA and CELES's L50.
3. **The cabin regroup** talks to members who wander; `talkToObj`'s fixed
   approach timed out on them, and the legs now chase (`chaseTalk`).  Other
   arcs' regroups still use `talkToObj`.
4. **The checkpoints** were sealed from lab captures (section 7); the
   release's re-cut makes them the graph's play.
5. **The Dirt Dragon** is the arc's hard fight (section 4): 1.00 and 1.55
   deaths a fight in `so5` and `so6`, 20 keys won of 20; 1.73 in `so7`
   (v0.36, without Dischord and without the tower's Wall Rings), 11 of 11.
6. **Doom Gaze** fells one in four meetings (0.24 deaths a meeting over 29
   in `so5`); the hunt wins every run, at the bag's cost (section 6).
7. **The labs before `dx2`** shared one driver across their trials
   (section 4); their numbers are comparisons on that footing.
