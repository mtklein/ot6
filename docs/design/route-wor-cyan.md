# World of Ruin: Cyan (Maranda's letters, Zozo, Mt. Zozo, the Storm Dragon)

The route from the save beside the Falcon outside Mobliz (`wor-terra-v1`:
TERRA, CELES, SABIN and EDGAR on foot at world (238,135)) to CYAN joining
on Mt. Zozo, the Storm Dragon, and the save beside the Falcon outside
Jidoor (`wor-cyan-v1`), with a save point checkpoint between them
(`wor-mtzozo-v1`, the dragon's retry point). Milestone v0.28, #265; #419
(the Potion target past L43) rides along. `tools/tests/gen_wor_cyan.lua`
plays the first leg, `tools/tests/gen_wor_storm.lua` the second.

Line numbers are into `ff6/src/event/event_main.asm`. Evidence is under
`build/attempts/wt/v028-cyan-route/`; every number below is quoted from a
log there. Nothing was measured by writing game state.

---

## 0. Findings

1. **The letters open the mountain.** Mt. Zozo's only door is on Zozo's
   street (221 (49,31) -> 179 (25,29)), behind an invisible rusted door
   (221 NPC_8 at (49,35), `_ca95b4`: "Rusted shut." until `$01DB`). The
   Rust-Rid is 1000 GP from the merchant at (43,29) (`_ca9513`), who sells
   it only once Lola's reply has flown (`$0298`, set by the carrier pigeon
   in Maranda, `_cc3f12`). So the route reads Lola's letters first, as the
   story intends: Lola (196 NPC_2, `_cc3d73`), the letter and "attach this
   reply to a carrier pigeon?" Yes (`_cc3e06`, `_cc3dbc`), the pigeon (284
   NPC_18).
2. **Zozo's way to the door is the café's stair.** From the street, the
   door (44,48) into 225, its stair out at (21,15) onto the balcony 221
   (49,39), the outside stair up to the landing (53,36), and west to
   (49,36) below the rusted door (`zozo/ex1.log`, the door graph walked;
   `zozo/st1.log`, the stair pressed). Zozo's clock (`_ca96bd`, 6:10:50) is
   not on the way: it opens the Chain Saw's room and a dead-end balcony
   (`zozo/clk1.log`, `zozo/h_m.log`), and the route leaves it (section 9).
3. **Mt. Zozo is two faces and a cliff.** The west face (from Zozo) holds
   four chests (Red Cap, Ice Shld, Thunder Shld, Aegis Shld) and map 177's
   Gold Hairpin; map 176 is the passage to the east face, which holds the
   save point (40,15), the Storm Dragon's ledge (48,11) and the way on
   through 178 to the cliff 180 (`mtzozo/h_mz2.log`, `h_mz3.log`).
4. **CYAN joins a full party aboard.** The cliff's trigger (180 (44,55),
   `_cc3fa7`) plays the scene in his cave and joins him at the average
   level of the available characters (`norm_lvl`, L33 here) with nothing
   equipped; `char_party` only runs when the party has room (`_cac5c1`'s
   `$01A3`, four), so with four he waits on the Falcon. The route walks
   down, takes him into the party in the cabin (EDGAR waits aboard with
   SETZER), dresses him from the bag and gives him Palidor, the stone no
   one wore.
5. **The Storm Dragon is a fight a player takes.** It sits on the east
   face beside the save point, on the way to and from CYAN, and
   level-curve.md keeps the eight dragons at their milestones. At the
   level the walk brings (CYAN 33, the others 35-36) it won 11 of 14 lab
   fights with 34 party deaths; after a grind on the east face to the
   lowest member L38 it won 12 of 12 with 8 (section 5). The route grinds,
   then fights it from the save point.
6. **Every species met has a designed row** (section 6): the plains' six
   round Zozo, Jidoor and Maranda (world groups 48-50, met a step from the
   Falcon), Mt. Zozo's five, and the Storm Dragon. Zozo's own pools were
   authored for the World of Balance and are unchanged.
7. **#419.** `H.careStockPotions` now stops the reserve at the Potion
   band's cap (79) and the target at the stack's 99 instead of raising;
   below L49 nothing it returned moves (`care_stock_selftest.lua`). Jidoor's
   counter on this route asks for 111 and buys to 99.

---

## 1. The start state (`wor-terra-v1`)

`contract wor-terra-v1 (entry): all 30 fields hold`; `TERRA(p1) L33 HP
1794/1794 ... EDGAR(p1) L33 ... SABIN(p1) L33 ... CELES(p1) L34`;
`tonic=4 potion=70 ... tincture=13 fenix=30 ... revivify=25 tent=4
gil=263596` (`dev/full1.log`). CYAN's record: `ch2 $1850=00 L24 ... kit FF
FF FF FF FF FF FF` (`zozo/p1.log`).

## 2. The legs

### 2.1 `gen_wor_cyan` (`wor-terra-v1` -> `wor-mtzozo-v1`)

1. **Maranda.** Board, land on (68,184), walk in (284 (11,29)). The
   entrance walk is the town's upper level: east along it to (14,27), up
   to the inn's landing (13,23), down the stair to the street (9,25), and
   north to Lola's door (26,11) (`maranda/press_mar2.log`,
   `maranda/h_mar5.log`). Lola, the letters, the pigeon (section 0.1).
2. **Zozo.** Land on (45,130), walk in (221 (61,44)). The merchant
   (wandering near (43,29)): the Rust-Rid. The café (44,48) -> 225, its
   stair (21,15) -> the balcony (49,39), the outside stair to (53,36), and
   (49,36): A on the rusted door (`$0356` cleared). Up the column to the
   door (49,31): Mt. Zozo.
3. **Mt. Zozo, first climb.** The west face's chests, 177's Gold Hairpin,
   the passage 176, the east face, 178, the cliff 180. CYAN joins
   (`$00D2`); the key's glint in his cave (181 NPC_4, `$0297`) and his
   chest (180 NPC_10, `_cc42c9`, `$01D9`).
4. **Down.** The same way back to Zozo's street and its east edge (63,44),
   onto the Falcon.
5. **The cabin.** X to the deck, the cabin (map 12). Every member of its
   main room is in the party, so the route takes the stairs (23,44) to the
   upper rooms and asks SETZER (NPC_10, (36,33)); "Change party members?"
   Yes; the party menu: CYAN, TERRA, CELES, SABIN (`H.partySelect`, the
   menu opens with everyone in the pool). CYAN from the bag (section 4),
   relics (`H.dressRelics`), Palidor on him.
6. **Jidoor.** Land on (36,156); the item counter (shop 78): Potions to
   `H.careStockPotions` (section 4).
7. **Maranda again.** The armor counter (shop 81, 284 (6,12) -> 290, a
   door in a wall: hold Up from (6,13)), then Lola with CYAN (`_cc3e45`:
   `$029C`) and the letters he exchanges (`_cc3eef`: `$029D`).
8. **Mt. Zozo again, to its save point.** Zozo, the open door, the west
   face, the passage, the east face; the grind (section 5.2); the save
   point (40,15): `wor-mtzozo-v1`.

### 2.2 `gen_wor_storm` (`wor-mtzozo-v1` -> `wor-cyan-v1`)

1. **Armed for the dragon** at the save point: each weapon hand takes the
   bag's best by power, doubled for a bolt edge and nothing for a wind one
   (it absorbs wind, is weak to bolt): CYAN's Tempest -> Ashura, TERRA's
   Break Blade -> the ThunderBlade (`[kit] TERRA hand 0: holds $11 (117
   against the dragon); the best is $0F (216)`). Relics for its threats
   (magic damage, no status a relic guards); care to full.
2. **The dragon.** The ledge's trigger (48,11) (`_cc4362`: `$0299`, the
   rock opens, NPC_1 shown); touching it is event battle 133
   (`_cc43cd`), a game over when lost (`_ca5ea9`). The fight driver: CELES
   on Runic (Wind Slash and Aero are spells), CYAN on his SwdTech.
3. **Down and out**, back to each hand's best and the arc's relics.
4. **Jidoor's counter again** (the next arc's stock), and Save beside the
   Falcon at (36,156): `wor-cyan-v1`.

## 3. Mechanics the harness learned

- **The planner's search cap.** `H.bfsPath` gives up after 4096 search
  nodes (`if qi > 4096 then return nil end`), and on a 64x64 map with two
  z-levels a target forty tiles off is past it: "navTo: no path" with a
  path there (`maranda/h_mar5.log`: the same walk passes through five
  near waypoints). The generators walk long stretches by waypoints
  (`via`). The library is unchanged (section 9).
- **Doors in walls.** Maranda's armor shop door (6,12) is a wall tile
  ($F7) whose tile below (6,13) takes an Up press (`maranda/f_mh.log`'s
  hex dump: `13 ... 23:8F` under `12 ... F7:FF`); `enterUp` stands below
  and holds Up until the map changes.
- **Stairs the planner's z-model misreads.** Zozo's outside stair (the
  "/" tiles (50,40)-(53,37)) is pressed, not planned (`climbStair`,
  `descendStair`); the same was true of gen_zozo4_dadaluma's corridor.
- **NPC objects are not NPC_n = $0F + n everywhere.** Zozo's street starts
  its NPCs at object $17 (`zozo/objs.log`); `npcAt` finds the live object
  nearest the posted tile.
- **The airship's party menu** opens with every member in the pool, so a
  swap is four seatings (`[the Falcon's cabin] CYAN: pool cell $01 -> seat
  $10`).
- **The cabin's show-switches** come from the deck's map init (`_cae90b`):
  `$02F0 + n` shows `$0388 + n`, CYAN's and SHADOW's swapped (`$02F2` ->
  `$038B`).

## 4. The party, its kit and its supplies

- **CYAN** joins at L33 naked; the bag dresses him: the Tempest (101,
  wind), the Aegis Shld from the west face, the Red Cap, Iron Armor until
  Maranda's Crystal Mail; Peace Ring and Star Pendant by the relic rule;
  Palidor (`[kit] CYAN slot 0: wears $FF (-1), the bag's best $2E (101)`,
  `dev/full1.log`).
- **Maranda's armor counter** (shop 81), for the four, each slot's best on
  the shelf over what is worn and the bag's best, keeping 100,000 GP:
  three Crystal Mails (CYAN, TERRA, CELES), Dark Gear (SABIN), two Oath
  Veils (TERRA, CELES) and a Crystal Shld (TERRA), 89,000 GP
  (`[shop] armor: char 2 slot 3 $87 (67) -> $98 (121), 17000 GP` ...).
  SABIN takes the bag's Dragon Claw (188) over a Fire Knuckle.
- **Supplies.** No counter on Maranda, Zozo or Mt. Zozo; Jidoor's (shop 78)
  stocks the climb, the grind, the dragon and the walk down: Potions to
  `H.careStockPotions(L35, spend 33)`, which wants 111 (reserve 59 + field
  care 19 + 33) and buys to 99 (#419). Measured spends: the first climb
  1 (70 -> 69), Maranda to the save point 5, the grind 7 (83 -> 76,
  `grind/gr_mz.out`), the dragon 0-19 (section 5). Fenix Downs 30, over
  the band; Tinctures 13 (band 10 at L40); Revivify 25. After the dragon
  Jidoor stocks the next arc (spend 10).

## 5. The Storm Dragon

Event group 133, formation 367: Storm Drgn `$14B`, L74, 42,000 HP, weak
bolt, absorbs wind, immune to Death and most statuses, starts with Float.
Script: Battle, Aero, Wing Saber (Special), Cyclonic, Wind Slash, Rage;
counter Battle. Optional in vanilla; here it sits beside the east face's
save point, on the way to CYAN and back, so a player passing it fights it.

### 5.1 At the walk's level (`storm/arrival/`)

Booted from the save point state of the first full run (`dev/full1.log`:
`CYAN(p1) L33 ... TERRA(p1) L35 ... SABIN(p1) L35 ... CELES(p1) L36`),
seven seed shifts, two arms on the same seven battle keys:

| arm | fights (keys) | won | lost | party deaths |
|---|---|---|---|---|
| Fight (CELES on Runic) | 7 (7) | 5 | 2 | 17 |
| and CYAN on SwdTech | 7 (7) | 6 | 1 | 17 |

(`analysis_fight.txt`, `analysis_bushido.txt`.) The deaths are Wind
Slash (all four, `[death] ... by slot 0 cmd $02 atk $65`), Rage and
Battle; one of the three losses had no break (`st2_s24`), the others one
and two. A coin flip with attrition
on top: a lab, and level-curve.md's healthy level for it is 38-40.

### 5.2 The grind

Two grinds from the same party (`grind/`): Zozo's plain beside the Falcon
(world groups 48/49) took 20 battles and 108,789 frames to CYAN L38 (one
death, CYAN to a Mantodea); Mt. Zozo's east face (field group 160) took 41
battles and 104,073 frames, no death (`[grind] f104071 done map 179
(52,15): TERRA(p1) L39 ... CYAN(p1) L38 ... SABIN(p1) L39 ... CELES(p1)
L40`). The route grinds on the east face, between the passage's door and
the save point, until its lowest member reaches L38: the same time, no
deaths, beside the save point a player would use.

### 5.3 At L38-40 (`storm/l38/`)

| arm | fights (keys) | won | lost | party deaths |
|---|---|---|---|---|
| Fight (CELES on Runic) | 7 (7) | 7 | 0 | 4 |
| and CYAN on SwdTech | 5 (5) | 5 | 0 | 4 |

The fights last 5,918-15,358 ticks; Potions 0-19 and Fenix Downs 0-2 a
fight. The route's driver takes the SwdTech arm: CYAN's own verb, Quadra
Slam and Stunner (`[advanceStory] actor=0 SwdTech row 2: tech $5A at 3 BP`).

### 5.4 What makes a fight good (guidelines.md)

- *Real but surmountable:* at L38-40, 30 of 30 won (sections 5.3, 8.2),
  with party deaths in 13 of them.
- *Drama:* Wind Slash hits all four at once and kills from as much as
  1,032 HP (`l38/st5_s0.out`: `SABIN from 1032/2442 by Wind Slash`); one
  draw in eighteen took four Fenix Downs (`stormB/stB_s44`), the
  guidelines' signal for a lab if it recurs.
- *Choices over levels:* the choices that count are reading its elements
  (the ThunderBlade, the Tempest off) and Runic against its spells; but the
  measured difference between losing 3 of 14 and winning 30 of 30 is three
  levels of grind, so levels settle more of it than choices do. Worth the
  v0.31 second look.
- *Luck:* at the arrival level a loss in about one fight in five; at the
  route's level none, so luck moves only the cost (0-24 Potions).

## 6. Break rows (authored)

| record | shields | classes | vanilla | why |
|---|---|---|---|---|
| Crawler `$05B` | 3 | pierce, bludg | weak ice | a shelled crawler: the blow cracks it, the point finds the joints |
| Geckorex `$099` | 3 | slash, pierce | weak ice | lizard hide |
| Reach Frog `$03B` | 2 | bludg | weak ice | soft, crushed |
| Mantodea `$0D2` | 3 | slash, bludg | weak fire | cut or crush the scythes; three, so it breaks before its Battle lands (route-wor-terra.md 8) |
| Sprinter `$087` | 3 | pierce, slash | weak bolt | a running bird |
| Spek Tor `$0B0` | 1 | slash, pierce, bludg | weak water | 250 HP |
| Luridan `$08E` | 2 | slash, pierce | weak fire, wind | horned, in herds of three and six: CYAN's Stunner cuts them all; his Tempest finds the wind |
| Borras `$0F2` | 4 | bludg, slash | weak poison | the brute: break it before the Uppercut |
| Punisher `$0DD` | 3 | slash, pierce | weak poison | |
| Scrapper `$0C5` | 2 | slash, bludg | absorbs poison | beside the Punishers, the Bio Blaster heals it |
| Ursus `$014` | 2 | bludg, slash | weak fire | two, so it breaks before it runs |
| Storm Drgn `$14B` | 14 | slash, pierce | weak bolt, absorbs wind | blades cut the hide, CYAN's Quadra Slam four a turn; the bolt finds it; the Tempest heals it |

`tools/tests/battle_breakwor_cyan.lua` (`@suite`) reads the rows back from
the ROM, the vanilla weak and absorb bytes, the formations of world groups
48-50, Mt. Zozo's field groups 160-162 and event group 133, and the keys
for the two parties that meet them (`suite/suite1.log`: `checked 12
designed rows`, `checked 13 formations, 35 formation-species-hands
triples`, `$14B: CYAN's katana (slash) is a key`, `PASS`).

The first draft of the dragon's row was the floor's `6 * pierce`, which no
member of either party holds; it broke only through the ThunderBlade's
bolt (`storm/floor/`: 3 of 4 won, 14 deaths, on the pre-row ROM).

## 7. The checkpoints

- `wor-mtzozo-v1`: Mt. Zozo's save point, map 179 (40,15), slot 3; CYAN,
  TERRA, CELES, SABIN; the letters, the Rust-Rid, the door, CYAN and Lola
  done; the Storm Dragon not fought (`$029A` clear); CYAN wears Palidor;
  the Falcon parked at (45,130).
- `wor-cyan-v1`: world 1 (36,156), on foot beside the Falcon outside
  Jidoor, slot 3; the dragon beaten (`$029A`).

## 8. Played

### 8.1 The bootstrap runs

`dev/full2.log`: `gen_wor_cyan` from the tracked `wor-terra-v1`, `PASS
(frame 200228) attempts=1/3`, 66 battles and no death, the grind `done
after 41 battles`, `contract wor-mtzozo-v1 (exit): all 33 fields hold`.
`dev/storm3.log`: `gen_wor_storm` from that capture, the dragon `WON after
9810 ticks`, `contract wor-cyan-v1 (exit): all 25 fields hold`, `PASS
(frame 40814) attempts=1/3`. The tracked checkpoints are these captures;
the chain's own replace them by `checkpoint_drift.py --recut`.

### 8.2 Under draw variation (`cyanB/`, `stormB/`)

Each leg eighteen times from its tracked boot: twelve seed shifts (0-44 by
4) and, to move the encounter draw, K = 2, 5 and 9 random battles used up
before the leg's body (the cyan leg on Mobliz's plain, world group 38; the
storm leg on Mt. Zozo's east face, group 160), each at shifts 0 and 12
(`build/lab/cyan/make_kvariant.py`, retained beside the logs).

- **The cyan leg**: 18 of 18 reach the save point; 17 pass, and the
  18th (`varB_k5_s0`) failed on the lab's own back-to-back savestates
  after the save point (`render on demand: fixture(s) wor_cyan.mss saved
  with the PPU's palette address unknown`), the lab's edit, not the
  route's; rerun with a wait in its place it passes (`varC_k5_s0.log`:
  `PASS (frame 205334)`). 1,190 battles over 321 distinct battle keys and
  no party death (`analysis_leg.txt`: `TOTAL battles 1190 (321 distinct
  keys), deaths 0`). The grind takes 34-46 battles; the save point holds
  TERRA 38-39, CYAN 38, SABIN 39, CELES 39-40 and 87-98 Potions.
- **The storm leg**: 18 of 18 pass; the dragon over 12 distinct battle
  keys, won 18, lost 0, broken in all 18, 15 party deaths
  (`analysis_storm.txt`); Potions 0-24 and Fenix Downs 0-4 a fight, the
  worst one draw (`stB_s44`: four deaths, `potions 24 fenix 4`).
  `wor-cyan-v1` holds 95-97 Potions.
- **Who breaks the dragon** (the party action before each break,
  `who_breaks.txt`): SABIN's Fight 11, TERRA's (the ThunderBlade) 6,
  CYAN's Quadra Slam 5, his Fight 2 and Empowerer 1, CELES 1. CYAN lands
  a quarter of them in the fight he joins for.

The first variation set (`varA/`, the generator before b429308e) stalled in
9 of 12 seeds on Zozo's outside stair, a battle under the pressed walk
(`where.txt`); the stair now fights it. The first storm run stopped one
tile short of the ledge (`dev/storm1.log`), fixed the same commit.

### 8.3 On the kits ROM (`chain_a57087a5/`, `cyanC/`, `stormC/`)

After wt/v028-kits and wt/v028-edgar-lab merged (a57087a5: CYAN learns
Cleave at the Phantom Train farewell, his window is his two best other
techs and Cleave on 3 BP, Retort and Empowerer classless; plans capped at
3 BP), `ninja chain` played the line from power-on on px13
(`chain_a57087a5/`: `wor_terra` `PASS (frame 48418) attempts=1/3`,
`wor_cyan` `PASS (frame 212900) attempts=1/3`, `wor_storm` `PASS (frame
39420) attempts=1/3`), and both checkpoints are re-cut from its captures.
The variation sets again, the cyan leg booted from that chain's
`wor-terra-v1` capture (its CYAN knows Cleave), the storm leg from the
re-cut `wor-mtzozo-v1`:

- **The cyan leg**: 18 of 18 pass; `TOTAL battles 1190 (327 distinct
  keys), deaths 0` (`cyanC/analysis_leg.txt`).
- **The storm leg**: 18 of 18 pass; `runs 18, distinct battle keys 15,
  won 18, lost 0, party deaths 5, broken in 18`; Potions 0-13 and Fenix
  Downs 0-2 a fight (`stormC/analysis_storm.txt`).
- **CYAN's turns**: the driver spends his bank as it comes, so his
  SwdTech is mostly Empowerer at 1 BP (36 of 49 picks), Stunner 8, Cleave
  5; with Empowerer classless he lands 1 of 27 breaks (`who_breaks.txt`:
  `TERRA Fight 14, SABIN Fight 9, CELES Fight 3, CYAN SwdTech $5A 1`). A
  player would bank three for Cleave against a boss; the driver's per-actor
  banking is the lever (section 9).

### 8.4 Retry sites

None in the runs above (`attempts=1/1` and `1/3` throughout, the chain's
included). The Storm
Dragon is the leg's game-over risk; at the route's levels it was not lost
in 30 fights (sections 5.3, 8.2).

## 9. What was left

- **Zozo's clock and the Chain Saw.** Off the way; a later arc (EDGAR's
  tools) can take it: the trigger (225 (98,59)) answers A held facing up,
  and 6:10:50 opens the room (`zozo/clk1.log`).
- **The planner's 4096-node cap** (section 3) is the library's; raising it
  could change which side an approach picks in the chain's other
  generators, so the waypoints stay generator-local.
- **EDGAR waits aboard.** His Ramuh stays on him; the next arc's kit pass
  can move it.
- **CYAN's bank against a boss.** `opts.bushido` takes the deepest row the
  bank pays this turn, so on the kits ROM he spends 1 BP on Empowerer most
  turns instead of saving three for Cleave (8.3); a per-actor bank target
  in the fight driver would let him save for it.  The rows were tuned on
  the measured fights and need no change for it.
