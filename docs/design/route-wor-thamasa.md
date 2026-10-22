# World of Ruin: Jidoor and Thamasa (Relm, Chadarnook, Strago, the Fanatics' Tower)

The plan for milestone v0.30, #267: from the save beside the Falcon outside
Narshe (`wor-narshe-v1`, where the v0.29 route ends) to RELM and STRAGO
joined, Chadarnook, the Holy Dragon (`White Drgn`) and MagiMaster beaten,
Starlet owned, and a save beside the Falcon. It folds in #365 (the
Mantodea's formation on the Jidoor continent), #388 (where this arc
learns lores, SwdTechs and Blitzes) and #420 (the tower stays
magic-only). Sections 0-10 are the plan as written before play.

Line numbers are into `ff6/src/event/event_main.asm` unless a file is named.
Evidence is under `build/attempts/wt/v030-plan-kits/`, read from
`build/ot6.sfc` built at db6c8daf (`rom_commit.txt`) by `tools/route_data.py`
and the scripts beside the logs, and from the tracked `wor-narshe-v1` SRAM at
db6c8daf (`wor-narshe-v1_db6c8daf.sram`, slot 3). Estimates are marked.

---

## 0. Findings

1. **Both recruits join into an empty seat.** RELM joins after Chadarnook
   (`_cb4dc6`, :48855: `give_genju STARLET` :48869, `char_party RELM, 1`
   :48894 only when `$01A3` is clear after `_cac5c1`'s `set_case`), and
   STRAGO at the tower's foot (`_cc5275`, :89137; `char_party STRAGO, 1`
   :89446, same test). With four seated, each is made available but waits
   on the Falcon. Both are `norm_lvl` (:48897, :89449): raised to the mean
   level of the available characters (`CalcAverageLevel`,
   `field/event.asm:892`), which `wor-narshe-v1` puts at (41+40+34+40+42+33
   +43+39)/8 = 39 (`wor-narshe-v1_roster.txt`). Both arrive at about L39
   (**estimate**), two to six under the tower's target (section 5).
2. **STRAGO needs RELM in the party, nothing else.** The four triggers round
   the cultists on map 362 (`_cc522e` :89106, `_cc5248` :89117, `_cc5262`
   :89128, `_cc5275` :89137) test only `$00BA` (not yet joined) and `$01A8`
   (RELM seated, `set_case PARTY_CHARS`); `$022F` is never set, so every
   trigger falls into the join. Thamasa is not on the critical path.
3. **The Fanatics' Tower pays no XP** (every tower formation `XP 0`,
   `maps_tower.txt`, `maps_tower2.txt`) and is magic-only: map 363's init
   (`_cc5173`, :88973) sets battle switch `$38`, map 362's clears it
   (:88985), and `InitCmdList` (`battle_main.asm:14112-14139`) turns Fight
   into Magic and drops every row but Magic, Item and Mimic (#420: kept).
   Lore, Sketch, SwdTech, Blitz and every divine on those rows are off
   inside; Analyze is the Scan spell on the Magic row (#381) and stays.
   Levels for MagiMaster come from outside.
4. **Three of the tower's species start with Reflect** (L.20 Magic `$130`,
   L.70 `$143`, L.90 `$164`, `species.txt`), and every party damage spell
   but Drain, Demi, Quartr, X-Zone, Quake and Merton is reflectable
   (MagicProp +3 bit 1, `reflect.txt`). Fire, Ice, Bolt, Poison, Pearl and
   OT6's Break bounce off them.
5. **MagiMaster's weakness moves.** His counter to every hit is WallChange
   (`AIScript::_358`, `ai_script.asm:3551`), which sets `$3BE0` (weak) to
   one random element, `$3BCD` (null) to the other seven and `$3BCC`
   (absorb) to one random element (`TargetEffect_26`,
   `battle_main.asm:9650`). OT6's chip reads `$3BE0` live (`Ot6Chip`,
   `ot6_break.asm:589`), so his elemental key is whichever element the last
   counter drew, and every other element does nothing. OT6's Break chips him
   regardless of element (`ot6_breakspell.asm`).
6. **The Gem Box is the X-Magic relic** (`items.txt`: `magic->x-magic`).
   Taking it (366 (7,8), `_cc5440` :89462) arms MagiMaster, who triggers on
   the way out (`_cc544b` :89467, battle 145 :89675), so a player equips it
   in room 366 before stepping onto (8,8): two casts a turn for the boss.
7. **#365's Mantodea is on this arc's doorstep.** Jidoor's gate (34,156)
   sits on world group 49, whose slots 1 and 3 (96/256) are formation 323
   (`$143`: Mantodea, Sprinter, Spek Tor x2, L50-54), the wipe in
   route-wor-terra.md section 8. Two tiles west is group 48 (Crawler x3;
   Geckorex x2 and Reach Frog), which has no Mantodea (`worldgroups.txt`,
   `pools_groups.txt`). Section 5.1 plans against it.
8. **The auction is random.** Golem (20,000) and ZoneSeek (10,000) are two
   arms of a chain of `if_rand` (:49241, `_cb5197` :49524, `_cb5312`
   :49792), one item a visit (`$016D`/`$016C` mark each sold). A player
   re-enters until they come up; the route counts its visits.
9. **No species here has an authored row** but the plains' (groups 37, 48,
   49, already authored on earlier arcs). Owzer's house, the tower, Thamasa's
   plain (groups 55, 56) and the three bosses ride the floor (`break floor
   6 * slash` and the like, `species.txt`).

## 1. The start state (`wor-narshe-v1`)

From the tracked SRAM (`wor-narshe-v1_dump.txt`, `wor-narshe-v1_roster.txt`):

- Party: `TERRA L41 HP 2645/2645`, `CELES L42 HP 2762/2762`, `MOG L43 HP
  2871/2871`, `UMARO L39 HP 2444/2444`. Aboard: `CYAN L40`, `SABIN L40`,
  `EDGAR L34`, `SETZER L33`. Not yet available: `STRAGO L25`, `RELM L22`,
  `LOCKE L29`, `GAU L33`.
- Stones worn: TERRA Fenrir, CELES Tritoch, MOG Terrato, CYAN Ifrit, EDGAR
  Ramuh, SETZER Unicorn; owned: Ramuh, Ifrit, Shiva, Siren, Terrato, Shoat,
  Maduin, Bismark, Stray, Palidor, Tritoch, Kirin, Carbunkl, Phantom,
  Sraphim, Unicorn, Fenrir.
- Natural magic: TERRA `Fire, Drain, Break, Pearl, Merton, Cure, Life`;
  CELES `Ice, Scan, Safe, Haste, Imp, Cure`.
- Known: SwdTech `$1CF7 = $BF` (all but Quadra Slice), Blitz `$1D28 = $3F`
  (through Air Blade), lores `$1D29 = $900088: Aqua Rake, Revenge, Stone,
  Exploder`.
- Bag: `Potion x88, Fenix Down x29, ... Remedy x11, ... Revivify x31, ...
  Elixir x8, ... Tincture x10, ... Tent x3, ... X-Potion x3, ... Ether x6,
  ... Echo Screen x2, ... X-Ether x1`; `gil 830121`.
- Saved on world 1 (115,38), beside the Falcon outside Narshe.

## 2. The order

1. **Jidoor, before Owzer's.** Land beside the gate (34,156) (`world 1
   (34,156) -> map 198`, `world_entrances1.txt`); the item counter (shop 78)
   for the arc's spend (section 7). The auction (map 200): one visit, and
   re-entry while Golem or ZoneSeek has not come up, bounded (finding 8).
2. **The cabin.** Seat three, TERRA, CELES and CYAN, and leave the fourth
   seat for RELM; MOG and UMARO wait aboard (section 5.4).
3. **Owzer's house** (map 198 (16,12) -> 209 (118,28)). The hall: the
   Tincture (209 (125,11), already opened, `tools/chests_opened.txt` 66);
   the two paintings that fight when read, A facing up (209 (99,30)
   `_cb47ae` :47963, battle 146: Dahling x2; (111,18) `_cb47f4` :47994,
   battle 147: Nightshade x3); the diary (116,17), `_cb4893` :48094, open
   only after (114,11) `_cb4776` :47940 sets `$024A`. Down the door 209
   (99,29) to the basement, 207 (127,51).
4. **The basement (207).** The lamp at (95,60) (`_cb4962` :48196) starts a
   160-frame rotation of three doors (88,50), (90,50), (92,50) (`_cb4987`,
   `_cb49ab`, `_cb49cf`, :48210-48254; blockers NPC_3-5, switches
   `$0494`-`$0496`). (88,50) is a door (to (90,61)); (90,50) and (92,50)
   drop the party into a 2-tile cell at (113,54) (`_cb4b86` :48500); which
   phase lets the party through is for the emulator to settle. The painting at (85,50) (`_cb4bb5` :48527) carries the party to
   (71,49); the four chest-monsters (NPC_7-10 at (73,50), (75,49), (77,50),
   (79,49); `_cb4a4e` :48316 and the three after; battle 151 each:
   SoulDancer, Wild Cat x4) give 293 GP, a Tonic, a Tincture and a Soft;
   Still Life (76,52), A facing up (`_cb4c47` :48603, battle 148), opens
   (75,47); (76,51) (`_cb4c94` :48635) lands at (85,46), the pocket with the
   save point (87,41) and the door (88,35) to map 208
   (`components.txt`). Chests: Moogle Suit (92,58), Relic Ring (90,47), and
   the old woman (107,51)/(107,56) (`_cb49f3` :48255, battle 151).
5. **The save point** (207 (87,41)): `wor-owzer-v1` (section 8), the retry
   point for Chadarnook.
6. **Chadarnook.** Map 208: (75,20) (`_cb4ce1` :48680) is Owzer's line;
   Owzer at (75,14), A facing up (`_cb4cfa` :48701), plays the scene and
   battle 86 (:48727), a game over when lost (`_ca5ea9`). `$0253` is set at
   :48853.
7. **Starlet and RELM.** (80,14), A facing up (`_cb4dc6` :48855): Starlet
   (:48869), then RELM into the empty seat; the map reloads to Jidoor
   (198 (16,14), :48904). RELM's gear goes on (section 6.2).
8. **The Fanatics' Tower's foot.** The cabin is not needed: the Falcon flies
   to the tower, world (160,126) -> map 362 (8,13). Stepping onto any of
   (8,12), (7,13), (9,13), (8,14) with RELM seated plays the scene and
   STRAGO joins into the fourth seat (finding 2); map 362 reloads at (8,13)
   (:89459).
9. **Out to level** (section 5.1): back to the Falcon and to the Jidoor
   continent's group 48 (west of the gate), the four that will climb
   (TERRA, CELES, RELM, STRAGO) fighting toward the target the lab sets,
   STRAGO learning what the plain casts (section 6.4).
10. **Thamasa** (world (251,230) -> map 344): its four counters (shops
    72-75, section 7) for the tower's gear and supplies, and the inn (346).
11. **The tower.** A world-map save beside it, `wor-tower-v1` (Tent; the
    tower has no save point). The climb: 362 (8,1) -> 363 -> 359 -> 360 ->
    361 -> 364, each floor's (10,10) to its side room and back:
    - 365 (off 363): Safety Bit (7,6); (8,6), A facing up (`_cc55a6`
      :89699) sets `$02DC`, which opens 363 (10,12)-(10,14) (`_cc5173`
      :88975) to room 370, the Air Anchor (7,6).
    - 367 (off 359): Genji Shld (7,6).
    - 368 (off 360): the Holy Dragon (NPC_1 (5,9), touch-to-fight:
      `_cc55a3` :89696 `collision_on`; `_cc558b` :89682, battle 139, then
      the Pearl Lance :89692) and the Stunner (7,6).
    - 369 (off 361): Force Armor (7,6).
    - 364 (7,6) -> 366: the Gem Box (7,7), whose tile event (7,8)
      (`_cc5440`) sets `$02DA` and shows the cultists (`$0699`). The Gem
      Box goes on here (finding 6).
    - Back onto 364 (8,8): MagiMaster (`_cc544b`, battle 145), then the map
      reloads at (8,8) (:89679) and the party walks down.
12. **The save.** Out of the tower to the Falcon, the cabin regroup (section
    5.4) and the save beside the Falcon: `wor-thamasa-v1`.

Not on the way: the Hidon and Gungho at Thamasa and Ebot's Rock (v0.34,
Gogo); Duncan's Bum Rush (v0.33). Thamasa's chests (343) were opened in
the World of Balance (`tools/chests_opened.txt` 246-250).

## 3. Maps, switches and battles

| map | what | switches and events | battles |
|---|---|---|---|
| 198 Jidoor (WoR) | town; shops 76-79; door (16,12) to Owzer's | init `_cb43e4` (:47451, sets `$025F`, the WoR gate every Owzer event tests) | none |
| 200 the auction | Golem, ZoneSeek, by chance | `if_rand` chain :49241, :49524, :49792; `$016C`, `$016D` | none |
| 209 Owzer's hall | the paintings, the diary, the lamp switch (118,14) | `_cb47ae`, `_cb47f4` (`$0252`, `$0156`); `_cb4776` (`$024A`); `_cb4930` (`$0243`, `$0251`) | event 146, 147; random off |
| 207 the basement | rotating doors, the painting warps, chest-monsters, save point (87,41) | `_cb4962` (`$01B5`, `$01FC`-`$01FE`); `_cb4b86`, `_cb4bb5` (`$024C`), `_cb4bea`, `_cb4c94`; `_cb4c47` (`$0254`); chests `$0258`-`$025C` | group 157; event 148, 151 |
| 208 the goddess | Owzer, Chadarnook, Starlet, RELM | `_cb4ce1`; `_cb4cfa` (`$0253`); `_cb4dc6` (`$0240`, `$02F8`, `$00D9`) | event 86 |
| 362 the tower's foot | cultists, STRAGO | `_cc522e`-`_cc5275` (`$00BA`, `$02F7`, `$0679`); init clears battle switch `$38` | random off |
| 363, 359, 360, 361 the climb | the outer stair, a side room off each | 363 init `_cc5173` (battle switch `$38`; `$02DC` opens 370) | groups 152, 153, 154, 155 |
| 364 the top | the cultists' ghosts (`$0699`), MagiMaster | `_cc544b` (`$02DA`, `$02DB`) | group 155; event 145 |
| 365-370 side rooms | Safety Bit, Gem Box, Genji Shld, Stunner + the Holy Dragon, Force Armor, Air Anchor | `_cc55a6` (`$02DC`); `_cc5440` (`$02DA`); `_cc558b` (`$0694`) | group 156 (365-369), 159 (370); event 139 |
| 344 Thamasa (WoR) | shops 72-75, inn | -- | random off |

Event groups (`pool event`): 86 is formation 456 (Chadarnook `$11E`, with
`$148` shown by its script), 139 is 481 (White Drgn `$024`), 145 is 354
(MagiMaster `$166`), 146 is 288 (Dahling x2), 147 is 289 (Nightshade x3),
148 is 290 (Still Life), 151 is 287 (SoulDancer, Wild Cat x4). Map 207's
random group 157: Vindr x2 (286), SoulDancer x2 + Crusher x2 (284), Vindr
x2 + Wild Cat + Crusher x2 (285) (`maps_jidoor.txt`).

## 4. Species and proposed break rows

Vanilla stats (`species.txt`). Shields follow ot6_hud.asm's tiers. The party
holds slash (TERRA, CELES, CYAN), fire (TERRA, CYAN's Ifrit), holy (TERRA's
Pearl) and bolt/ice (CELES's Tritoch) going into Owzer's; RELM adds ¤ (the
brush) and STRAGO bludgeon (the rod). Inside the tower only spells chip:
an element on a weakness, or OT6's Break (one shield, one more a boost
point; `ot6_breakspell.asm`), so the tower's rows are designed around
elements and around which spells reach each body (finding 4). **Counts and
keys are a proposal**; the route's play sets them.

### 4.1 Owzer's house

| species | where | L / HP | vanilla elements; notes | shields | classes | why |
|---|---|---|---|---|---|---|
| Vindr `$0CC` | 207 | 36 / 885 | weak fire; Float, evade 90; Beak (Petrify) | 1 | slash, pierce | a bird that dodges blades: fire is the key that lands |
| SoulDancer `$0AD` | 207, event 151 | 22 / 2,539 | weak poison; Red Dance (drain) | 2 | slash, special | a dancing spirit (guidelines.md: ¤ for spirits) |
| Crusher `$092` | 207 | 36 / 2,095 | weak fire; Blow (x5); counter Lifeshaver | 3 | pierce, bludg | the house's tank; break it before Blow |
| Wild Cat `$077` | 207, event 151 | 36 / 1,115 | weak fire, water; Fire Ball | 1 | slash, pierce | in fours |
| Dahling `$009` | event 146 | 37 / 3,580 | weak poison; Mute, Ice 2, Bolt 2 (Runic-able); counter Cure 2 | 2 | slash, special | a painting; CELES's Runic eats its list |
| Nightshade `$033` | event 147 | 37 / 2,200 | weak fire; absorbs water; Charm | 2 | slash | a painted flower |
| Still Life `$050` | event 148 | 37 / 4,889 | weak fire; Lullaby; counter Condemned | 4 | slash, special | the basement's miniboss painting |
| Chadarnook (painting) `$11E` | event 86 | 37 / 56,000 | weak fire; absorbs holy, water; counter Phantasm | 0 | -- | the goddess: hitting her is the fight's mistake, so she carries no shields to chip |
| Chadarnook (demon) `$148` | event 86 | 41 / 30,000 | weak fire, holy; absorbs bolt; Bolt 2/3 (Runic-able), Flash Rain | 6 | slash, pierce | the boss: the three blades (or MOG's spear), with fire and Pearl |

### 4.2 The Fanatics' Tower

| species | floors | L / HP | vanilla elements; notes | shields | key inside the tower | why |
|---|---|---|---|---|---|---|
| L.10 Magic `$132` | 363, 359, 360 | 48 / 1,000 | weak fire, holy; Float | 1 | fire, holy | the first lesson: a weakness and a cast |
| L.20 Magic `$130` | 363, 359 | 51 / 2,000 | none; absorbs poison; **Reflect** | 2 | **+earth** (element add): Quake | Reflect bounces the party's tier spells; Quake ignores it and it is not floating |
| L.30 Magic `$125` | 363, 359, 360 | 54 / 3,000 | weak poison; absorbs holy | 2 | poison (Tritoch), Break | |
| L.40 Magic `$12B` | 363, 359, 360 | 55 / 4,000 | weak bolt; Float; Break (Petrify) | 2 | bolt, Break | |
| L.50 Magic `$133` | 359, 360, 365-369 | 57 / 5,000 | weak fire, holy; Doom | 2 | fire, holy, Break | |
| L.60 Magic `$139` | 359-361, 364 | 58 / 6,000 | weak fire; absorbs ice; Float; Quake, W Wind, Pearl | 3 | fire, Break | |
| L.70 Magic `$143` | 360 | 56 / 7,000 | weak ice, water; absorbs fire; **Reflect**; Fire 3/Ice 3/Bolt 3 | 3 | **+earth**: Quake | as L.20; ice bounces |
| L.80 Magic `$163` | 361, 364 | 53 / 8,000 | weak poison; heals, Life 3 | 3 | poison, Break | |
| L.90 Magic `$164` | 361, 364-369 | 55 / 9,000 | none; absorbs wind; nulls holy, earth, water; **Reflect**; Meteor, Merton, Flare | 0 | -- (full damage: Drain, Demi, X-Zone fails on its Death immunity) | nothing the party casts reaches a weakness through Reflect and its nulls, so it carries no shields and takes full damage rather than half |
| Magic Urn `$055` | every floor | 31 / 100 | absorbs all eight; heals the party, then Escapes | 0 | -- | a gift, not a fight |
| White Drgn `$024` | event 139 | 71 / 18,500 | none; absorbs holy; Pearl x2 a turn; counter Dispel to Magic | 6 | Break (no Reflect) | the Holy Dragon: OT6's Break is its only key, and its counter strips the party's buffs |
| MagiMaster `$166` | event 145 | 68 / 50,000 | WallChange: one random weakness, the rest null (finding 5) | 8 | the wall's element; Break | read the wall, or break through it |

The tower species' classes do not matter inside (no Fight). Outside the
tower they appear only in random groups 84 and 85 and event groups 58, 96,
102, 108 and 110 (`sharing.txt`), none of them on this arc; each takes
`special`, the ¤ of a magical body, for those. The element adds are `Ot6ElemAddTbl` rows (`ot6_break.asm:206`),
the tool earlier arcs used (Whelk Head + fire, Vargas + holy).

### 4.3 The plains and Thamasa

| species | where | L / HP | vanilla elements | row today | proposal |
|---|---|---|---|---|---|
| Crawler `$05B`, Sprinter `$087`, Spek Tor `$0B0`, Geckorex `$099`, Reach Frog `$03B` | groups 48-52 | 50-54 | (`species.txt`) | authored (3/3/1/3/2) | as built |
| Mantodea `$0D2` | groups 49-52 | 54 / 4,500 | weak fire; atk 180 | authored 3, slash, bludg | **+special**: RELM's brush becomes a key on the arc's one killer, the day she joins |
| Bloompire `$035`, Buffalax `$058`, Lizard `$03C` | group 37 (the tower's plain) | 26 | | authored | as built |
| Harpy `$02B` | group 55 (Thamasa's plain) | 42 / 3,615 | none; Aero (a lore) | floor | 2, pierce, special |
| GloomShell `$08A` | group 56 (Thamasa's gate) | 41 / 2,905 | weak ice; Net (Stop) | floor | 3, pierce, bludg (a shell: STRAGO's rod) |
| Prussian `$0D4` | groups 55, 56 | 41 / 3,300 | none; Bear Hug (x3) | floor | 3, slash, bludg |

## 5. The bosses and the levels

The party arrives at L41-43 (section 1); level-curve.md projected 41, with a
target of 45 for MagiMaster. RELM and STRAGO arrive at about L39 (finding 1).
XP (`event.asm:1336`, `LevelUpExp` x8): L41 to L45 is 60,584 and L39 to L45
86,816. A random on group 48 pays 5,111 x2 = 10,222 (formations 319 and
326, 160/96 of 256, `pools_groups.txt`), about 2,555 a member of four; group
49 pays 3,168 a member (level-curve.md). So L41 to L45 is about 24 fights on
group 48 and about 19 on group 49, and RELM and STRAGO need about 34 and 27
(**estimates**; XP is split among the living).

### 5.1 The Mantodea (#365) and the grind

The Mantodea's Battle (atk 180, L54) is what killed the L33-36 party: 52 of
58 deaths, 17 from 80% HP or more in one hit (route-wor-terra.md section 8).
By vanilla's monster formula, level² x (4 x attack + vigor) / 256 then
x (255 - def)/256, one hit is about 3,600-5,400 at def 100-150, about half
that from the back row and two thirds of that under Safe (**estimate**),
against 2,400-2,900 HP here. So:

- **Grind on group 48, not 49.** It is the same continent two tiles west of
  Jidoor's gate (`worldgroups.txt`: `group 48 ... Jidoor gate (34,156) 2
  tiles at (32, 156)`), pays 80% of group 49's XP and has no Mantodea.
  Walking in and out of the gate still crosses group 49, so every draw there
  can deal formation 323, and the rows and the kill order have to take it.
- **The kill order puts the Mantodea first, and breaks it.** Its row is 3,
  slash and bludgeon (with RELM's ¤, section 4.3); TERRA and CELES's blades,
  UMARO's or STRAGO's bludgeon. Fire is its weakness. The back row and Safe
  (CELES's natural Safe, Carbunkl, Golem) for the casters.
- **Measure before the grind.** The lab Continues `wor-owzer-v1` and walks
  group 49 (as `lab_ruinwaste.lua` did), counting formation 323 by battle key
  and the Mantodea's hits at the party's def; and it captures MagiMaster at
  the party's arrival level (section 5.3). The two set the target. A
  45-level grind of thirty fights is the plan only if MagiMaster says so.

**Measured (v0.31, #365).** The route as played walks one group-49 tile:
the Falcon's landing at (36,156), one step from Jidoor's door, which
`route_data.py world-path 1 34 156 36 156` reads as "1 steps: no
battles" onto (35,156) and "1 steps: ... group 49" onto (36,156). That
step comes once a Jidoor exit (wor_cyan, wor_storm, wor_narshe and
wor_relm in v0.30's play); its chance is the danger counter's high byte
over 256 (`CheckBattleWorld`: +$60 a world step, cleared only by a
battle). The grind is group 48's lap (16..22,135). In v0.30's
qualification (`build/attempts/wt/v030-release-qualification/
final-8efd9290/ninja.log`) no battle came from group 49: formation 319
(Crawler x3) was fought 24 times (24 battle keys), all won, all on
wor_relm's lap, and formation 323 never. The arc's labs add 170 Crawler
fights, none lost (`build/attempts/wt/v030-route/lab/relm/*`,
`lab/var/*`). v0.31's fresh play (`build/attempts/wt/v031-robust/final/
ninja2.log.gz`, wor_relm) fought formation 319 32 times and 326 (Geckorex
x2, Reach Frog) 22 times, every one a distinct key and won, and met 323
never. The Mantodea is left to that one step, where a loss is a retried
attempt.

### 5.2 Chadarnook (event 86; `AIScript::_286`, `ai_script.asm:5505`; `_328`, :6873)

The goddess (`$11E`) opens: "The girl in the picture is mine!", then Charm,
Lullaby, Battle, Doom Kiss (Condemned), and her counter to any hit is
Phantasm. On a battle variable she hides and the demon (`$148`) shows. The
demon casts Bolt 3 and Bolt 2 (Runic-able), Flash Rain (ice/water) below
15,360 HP, counters every hit with Bolt 2, and after five hits, or a
40-tick timer, the goddess returns. Killing the demon ends the fight
(`boss_death`).

- **Kit.** Hit the demon only: fire (TERRA, CYAN's Ifrit) and Pearl
  (TERRA's natural L30) on its fire and holy weaknesses, blades for its
  slash key; CELES on Runic for Bolt 2/3. The demon absorbs bolt, so
  CELES's Tritoch does nothing to it. The windows are short (five hits),
  so boosted spells, not several small hits.
- **Expectation (estimate).** L37/L41 against L40-42: under the party, as
  Tritoch and Umaro were (route-wor-narshe.md 11.4). A lab if the
  goddess's Condemned or Charm costs more than Fenix Downs 0-2 a fight.
- **Lab question.** Whether a Broken demon's counter still counts its five
  hits (its `if_hit` block), which decides how long a break window is.

### 5.3 MagiMaster (event 145; `AIScript::_358`, `ai_script.asm:3551`)

A loop of Fire 2/Ice 2/Bolt 2, then pairs of Fire 3/Ice 3/Bolt 3, then
Doom, Mute and Bio; while every monster has Reflect, tier 3 only. Every hit
draws WallChange (finding 5). On death, Ultima (power 150) on the party.

- **Reading the wall.** STRAGO's Analyze (Scan, #381) or CELES's natural
  Scan marks the current wall on the HUD (vanilla's text names it too); the
  HUD also shows
  a weakness once a cast chips it; the driver may read `$3BE0` (TESTING.md:
  reading is full power). The cast that matches it chips and does double;
  every other element does nothing.
- **Kit.** Magic only, and the Gem Box on the main caster (X-Magic, two
  casts a turn). Damage: boosted tier spells on the wall (TERRA's Fire,
  CELES's Ice, Maduin's fire, ice and bolt, Tritoch's ice, bolt and
  poison, Terrato's Quake for earth), so a Maduin wearer matches any
  fire/ice/bolt wall; a wind, holy or water wall has only Pearl (holy) to
  answer it, and Break. Shields: OT6's Break
  (TERRA's natural, Shoat's), boosted to take four. Defence: the Force
  Armor (369; halves fire, ice, bolt) on TERRA or CELES, the Safety Bit
  (365) against Doom, Remedies for Mute (Echo Screens: 2), Shell (Shiva,
  ZoneSeek) on all four.
- **Ultima.** Vanilla's monster spell at L68, mag 25: 150 x 4 + 68 x 25 x
  150 / 32 = 8,568 before magic defence, halved across four targets, about
  3,260 at mdef 60 and about 2,170 under Shell (**estimate**; whether
  Ultima splits is the lab's first measurement). That is about the party's
  HP at L45, so: **Shell on all four, then Life 3 pre-cast** (Life at two
  or three points, magicite.md "Life 3 is Life's third tier": TERRA's
  natural Life, Sraphim's) when his HP says the next hits can kill him
  (the driver reads his HP), with Fenix Downs as the backstop.
- **Reflect.** Wall Ring or Rflect (Carbunkl) on the party would bounce his
  single-target spells onto him, where seven elements in eight are null;
  but it bounces the party's own Cure too. A lab branch, not the plan.
- **Expectation.** The arc's contest: the target level comes from it.

### 5.4 The Holy Dragon (event 139; `AIScript::_36`, `ai_script.asm:3253`)

Pearl twice a turn (holy, power 108), then once, then a wait; any Magic
draws Dispel on every character. Absorbs holy, no weakness.

- **Kit.** Fight it on its own, before MagiMaster's floor (it strips Shell
  and Life 3). Break (it has no Reflect) for its six shields, then the tier
  spells on the broken body. No Pearl (it absorbs holy) and no Pearl Rod
  hits. Fenix Downs over Life 3 here.
- **Expectation (estimate).** Pearl at mag 9, L71: 108 x 4 + 71 x 9 x
  108 / 32 = 2,589 before mdef, single target, twice a turn. Measure.

### 5.5 The party

**Into Owzer's:** TERRA, CELES, CYAN, and RELM when she joins; MOG, UMARO,
SABIN, EDGAR, SETZER aboard. CYAN (L40) earns XP toward Quadra Slice (L44)
and carries Ifrit's fire. **Into the tower:** TERRA, CELES, RELM, STRAGO:
the four with Magic and the most magic power (Umaro has no Magic; the
tower's Fight row becomes Magic). **Out of the tower:** as the next arc
needs; RELM and STRAGO stay seated for the plains' lores.

## 6. Espers, arrivals and abilities

### 6.1 Espers

| Esper | where | how | spells (`espers.txt`) |
|---|---|---|---|
| Starlet | map 208 (80,14) | after Chadarnook (:48869) | Cure, Regen, Remedy |
| Golem | the auction | 20,000 GP, by chance (finding 8) | Safe |
| ZoneSeek | the auction | 10,000 GP, by chance | Shell, Haste |

**Tower loadouts** (proposal): TERRA Maduin (Fire, Ice, Bolt over her own
Fire, Drain, Break, Pearl, Life); CELES Tritoch (Ice, Bolt, Poison over her
Ice, Scan, Safe); RELM Shiva (Ice, Osmose, Shell) or ZoneSeek (Shell,
Haste); STRAGO Sraphim (Cure, Life) or Shoat (Break, Doom). Life is then
on two casters (TERRA, Sraphim's wearer), Break on two (TERRA, Shoat's),
Shell on one. level-curve.md and magicite.md listed Carbunkl among the
Shell stones; it grants Rflect and Safe (`espers.txt`), corrected there.

### 6.2 RELM on arrival

- **Her key:** the brush is the party's only ¤ (CYAN's katana, TERRA's and
  CELES's swords are slash). The proposed rows make ¤ a key on the
  Mantodea (the plain's killer) and the Harpy (Thamasa's plain).
- **Gear:** the Moogle Suit from map 207 (92,58) (STRAGO or RELM; nulls
  poison); Thamasa's DaVinci Brsh (7,000), Mystery Veil (5,500) or Circlet,
  Light Robe (11,000; mdef 43, `items.txt`).
- **In the tower:** Magic with a stone, her magic power the party's best.

### 6.3 STRAGO on arrival

- **His key:** the rod (bludgeon): GloomShell and Prussian (proposed) and
  the Mantodea and Crawlers on the plains.
- **His kit:** the lores (below), Aqua Rake as the free row and Analyze
  (Scan, always his; #381, kits.md "Strago"). Lore is off in the tower;
  his Magic row, Scan with it, is not: he reads MagiMaster's wall.
- **Gear:** Pearl Rod (Thamasa, 12,000; holy, casts Pearl), Light Robe,
  the Moogle Suit.

### 6.4 What this arc teaches (#388)

- **STRAGO's lores** are learned by seeing them cast with him in the party.
  On this arc, after he joins (`lores.txt`): Dischord (Crawler, groups 48,
  49), Rippler (Reach Frog, groups 48, 50, 51), Pearl Wind (Sprinter, groups
  49, 51, 52; on 49 only in formation 323), Aero (Harpy, group 55, at
  Thamasa's door). Condemned is Still Life's counter (event 148) and Owzer's
  house comes before he joins, so it is not on this arc. The tower's species
  cast no lores. The grind on group 48 teaches Dischord and Rippler as a
  matter of course.
- **What the driver uses:** Aqua Rake (water, every enemy: the Spek Tor and
  Wild Cats' weakness) through `opts.nukeLore` as built; Pearl Wind as the
  party heal in place of a care action once learned; Dischord on a single
  tank (it halves level). Rippler, Stone, Exploder and Revenge are not worth
  a turn here.
- **CYAN's SwdTechs:** all but Quadra Slice (L44) are known (`$1CF7 =
  $BF`); CYAN at L40 learns it on this arc only if he fights it (the Owzer
  party, section 5.5). Cleave is known.
- **SABIN's Blitzes:** through Air Blade (`$1D28 = $3F`); Spiraler at L42
  needs two levels he will not get aboard; Bum Rush is Duncan's (v0.33). Not
  on this arc unless the route seats him.

## 7. Shops, supplies and items

- **The counters.** Jidoor (shop 78: Potion, Tincture, Fenix Down,
  Revivify, Remedy, Warp Stone, Sleeping Bag, Tent) at the start; Thamasa
  (shop 74: the same with Smoke Bomb for Warp Stone) before the climb; its
  weapons (72: DaVinci Brsh, Pearl Rod, Gravity Rod, Trump, Gold Lance),
  armor (73: Mystery Veil, Circlet, Dark Hood, Light Robe, Diamond Vest) and
  relics (75: Wall Ring, Cure Ring and the rings) (`shops.txt`). Narshe sells
  nothing without LOCKE (route-wor-narshe.md finding 2). Inns: Jidoor (206),
  Thamasa (346).
- **The band** at L45 (level-curve.md): Potion ~68, Tincture ~11, Revivify
  3, Fenix Down 20. Held: 88, 10, 31, 29. The tower is MP: every random is
  fought with spells and pays nothing back, so Tinctures to about 20 and the
  6 Ethers, 1 X-Ether and 8 Elixirs kept for MagiMaster (**estimate**;
  the climb's spend is the first measurement). Remedies (11) for Mute.
- **Chests on the way:** Moogle Suit, Relic Ring (207); four chest-monsters'
  293 GP, Tonic, Tincture, Soft; the tower's Safety Bit, Gem Box, Genji Shld,
  Stunner, Force Armor, Air Anchor (EDGAR's tool); the Pearl Lance (MOG's,
  holy) after the Holy Dragon. None of these bits is in
  `tools/chests_opened.txt` (the hall's Tincture, 66, is).

## 8. Checkpoints

- `wor-owzer-v1`: map 207's save point (87,41), RELM not joined, `$0253`
  clear. The retry point for Chadarnook.
- `wor-tower-v1`: the world map beside the tower, STRAGO and RELM seated,
  the plains done, `$02DB` clear. The retry point for the climb, the Holy
  Dragon and MagiMaster (the tower has no save point; `maps_tower*.txt`).
- `wor-thamasa-v1`: beside the Falcon after the tower; `$02F7`, `$02F8`,
  `$0240`, `$02DB` set; Starlet owned.

## 9. Harness risks

- **The rotating doors** (207 (88,50)-(92,50)) are NPC blockers on a
  160-frame timer started by the lamp (95,60); the wrong two drop the party
  into the (113,54) cell. The walk has to read the blocker switches
  (`$0494`-`$0496`) and step through on the right phase.
- **A-facing-up events.** The paintings (209 (99,30), (111,18); 207 (76,52)),
  Owzer (208 (75,14)), the stone (208 (80,14)) and 365's switch (8,6)
  answer A pressed facing up (`if_any $01B0=0 / $01B4=0`); stepping on them
  does nothing.
- **Painting warps** (207 (85,50), (86,38), (76,51), (90,50), (92,50)) move
  the party without a door; the static model shows them as 2-27 tile pockets
  (`components.txt`). The walk detects the tile jump, as v0.29's mines did.
- **Chest-monsters are NPCs**: four on the (71,49) path, each a battle.
- **The auction's chance** (finding 8): bounded re-entries, each counted.
- **Magic-only command lists.** The battle menu has one Magic row (Fight
  becomes Magic, Magic is dropped; `battle_main.asm:14125-14139`): menu
  indices shift, and any verb the driver opens by row (Lore, Sketch) is
  absent.
- **Reflect bounces** (finding 4): the driver's veto (`H.castVeto`,
  `spellReflectable`) has to keep tier spells off L.20, L.70 and L.90 and
  pick Quake, Drain or Demi there; Quake misses Float (L.10, L.40, L.60) and
  heals nothing of the party's.
- **The Holy Dragon on contact**: a touch-to-fight NPC (368 (5,9)); a walk
  to the Stunner (7,6) can brush it.
- **The Gem Box arms MagiMaster** on the next step onto 364 (8,8): the relic
  goes on in room 366, before that step.
- **Pre-casting Life 3** needs a boost of two and the driver's own read of
  MagiMaster's HP; a Life 3 spent on a member at full HP is a turn, and the
  Holy Dragon's Dispel removes it.
- **Naming menus:** none (RELM and STRAGO are named in the World of
  Balance).

## 10. Decisions (coordinator, 2026-10-13)

1. **The tower's randoms are fought** (guidelines.md, "fight rather than
   flee"), 0 XP or not. If the lab shows the climb's MP spend makes
   MagiMaster a coin flip, the answer is supplies (Ethers, Tinctures, Tents)
   and the saves outside, not fleeing.
2. **STRAGO's full boost** is Study (#432, built on this branch): his Scan
   at 3 BP learns every lore the monsters present could cast (kits.md
   "Strago"). On this arc it pays on the plains (Dischord, Rippler, Pearl
   Wind, Aero); no tower species casts a lore.

## 11. Played (v0.30)

The route plays the arc in three legs. Evidence is under
`build/attempts/wt/v030-route/` (`lab/` holds the dev and variant runs,
`grind/` the world tables, `rows/` and `study/`, `scanally/` the suites').

### 11.1 The legs

- `gen_wor_owzer` (`wor-narshe-v1` -> `wor-owzer-v1`): the cabin seats CYAN,
  TERRA and CELES; the Falcon to Jidoor; the item counter; the auction, up
  to 16 visits; Owzer's hall: the switch at the stair's foot, the two
  paintings; the basement: the lamp, the turning door, the painting warp,
  Still Life; the save point.
- `gen_wor_relm` (`wor-owzer-v1` -> `wor-tower-v1`): Owzer and Chadarnook;
  Starlet and RELM; Jidoor's item counter again; STRAGO at the tower's foot
  (he waits aboard: the party is full); the cabin seats TERRA, CELES, RELM
  and STRAGO; the grind; Thamasa's item and relic counters; the save beside
  the Falcon at the tower (160,127).
- `gen_wor_tower` (`wor-tower-v1` -> `wor-thamasa-v1`): the stones and Wall
  Rings, the climb with each floor's side room, the Holy Dragon, the Gem
  Box, MagiMaster, the walk down and the save beside the Falcon.

### 11.2 What the walk learned

- **Owzer's hall is dark until its switch.** The landing (114,11) answers
  "Stay...away..." and turns the party back while `$0243` is clear
  (`lab/owzer/a1`: `control lost at (114,11)`, then `planned 20 steps from
  (118,14)` until no-progress); A facing up at (118,14) (`_cb4930`) lights
  it.
- **The turning door.** Of the three, (88,50) leads on (to (90,61)) while
  `$01FC` is set; the walk waits below it and presses up then
  (`lab/owzer/b2`: `$01FC-$01FE 100 ... through the turning door`).
- **The old woman at (107,56)** stands on the only way west (row 56), so
  her fight (event 151) is part of the walk.
- **The Moogle Suit and the Relic Ring** are not reached from the save
  point's pocket; the route leaves them.
- **The auction's World of Ruin chain** (`_cb55b0`) is the Hero Ring, then
  an item, then Golem, then ZoneSeek, each behind a coin flip: Golem one
  visit in eight, ZoneSeek one in sixteen before Golem is owned. The run
  (and its K=3 variant) met ZoneSeek on visit 12 and no Golem in 16
  (`lab/owzer/cap1`, `lab/var/owzer_k3`).
- **The plan's grind spot is unreachable on foot**: no landing reaches world
  rows 160-162 south of the gate (`lab/relm/s1`: `no path (34,158)->
  (31,161)`). Row 135 north-west of Jidoor, x 16-22, is group 48 throughout
  and takes a landing (17,135) (`grind/grindspot.txt`, `grind/wg_lap.txt`).
- **Thamasa's (22,39) and (23,39)** start STRAGO and RELM's scene at their
  house (`_cb75bf`); the walks keep off them.
- **Landings** that take the airship: the tower (160,127), Thamasa (250,229)
  (`grind/land_tower.txt`).

### 11.3 Chadarnook, the grind and STRAGO's kit

- **Chadarnook** fell in every run, slowly: 38,786 ticks with three deaths
  (`lab/relm/cap1`, one by Doom Kiss from full HP), 32,031 ticks and three
  deaths with three encounters used up first (`lab/var/relm_k3`). The
  goddess is drawn on most of the clock; the driver aims at the demon
  (`focus`) and waits her out. Short of "what makes a fight good": it is
  attrition, decided by Fenix Downs rather than by a choice.
- **The grind** north-west of Jidoor: to L43 for the lowest of the four in
  26 fights (`lab/relm/r1`), to L46 in about 55 (`lab/relm/r3`). Potions and
  Remedies ran out by the 33rd fight (`lab/var/relm_k3`: `potion=2 ...
  remedy=0`); with 15 Tents from Jidoor the care pitches one when the heals
  would cost more, and the run arrives whole (`lab/relm/cap2`: about 15
  Tents, "potion=98" at the save).
- **STRAGO's kit (#388).** Study (Scan at 3 BP) fired on the plain when a
  Reach Frog could teach Rippler (`lab/relm/r1`: `study: Scan at 3 BP on
  slot 2 ($03B), lores $080000 he lacks`); Dischord was learned by being
  cast on (Crawlers); Aqua Rake is the plain's nuke (55 casts in 26 fights).
  Pearl Wind is not on this route (the Sprinter casts it on group 49 only
  beside the Mantodea), so the driver's Pearl Wind line went unexercised,
  and so did Dischord on the Mantodea (group 48 holds none).

### 11.4 The Fanatics' Tower

Every fight inside is spells (no Fight row), so the driver gained a
magic-only line (`Driver:magicOnlyLine`) and the climb its own kit:

- **Every seat casts.** RELM on ZoneSeek and STRAGO on Sraphim had no
  attack and passed every turn while three L.30 Magic killed the party
  (`lab/tower/c1`: `plan=switch`, `battle $0AD LOST`). TERRA Maduin, CELES
  Tritoch, RELM Shiva (Ice, Osmose, Shell); STRAGO Palidor (Float).
- **Wall Rings** (Thamasa's relic counter) through the third floor: the
  monsters' tier spells rebound, and a reflectable spell cast on a member in
  Reflect rebounds onto the L.20 and L.70 Magic past their Reflect; a
  reflecting body otherwise refuses every reflectable cast at the confirm
  (`lab/tower/c3`: a Break re-planned for 90,000 frames).
- **Float** kept on the four from the menu (the L.60 Magic's Quake took
  3,400 of 3,600 from each, twice: `lab/tower/c8`).
- **MP**: Tinctures to 99 at Thamasa (the climb from the second floor spent
  32 and reached the top dry: `lab/tower/c10`); the after-battle care keeps
  the casters above 60% and, inside, casts cures when Potions (250 HP) cannot
  keep up.
- **The Holy Dragon** fell every time it was met: 17,518 to 45,491 ticks,
  broken twice a fight by TERRA's Break (`lab/tower/c10`, `c11`, `c15`,
  `cap2` x3: `$024 broken (0 of 6 shields)`).
- **The fourth floor's L.90 Magic** is where the climb ends at L46 (TERRA
  and CELES L49): with the rings off above the third floor (cures again) and
  Shell going up, the L.90 and L.80 Magic won all three attempts of a full
  run, the L.90's Merton taking about 2,300 from each member
  (`lab/tower/cap2`: `attempt 3/3 FAILED class=wipe`, `formation 0164
  0163`). MagiMaster has not been reached.
- **More levels did not change it.** Ground to L50 (TERRA L52, CELES L53;
  95 fights, `lab/relm/cap3`), the four lost the fourth floor's first fight,
  the L.90 and L.60 Magic, without denting the L.90 (`lab/tower/c18`:
  `monhp=s0:9000/sh0` until the wipe): the party spent its turns on the
  L.60 and on Shell and heals while the L.90's Meteor, Merton and Flare
  fell. So leg B grinds to L46 and the tower leg stays off the graph; its
  generator is kept at `build/attempts/wt/v030-route/wip/gen_wor_tower.lua`.

### 11.5 Open

- **The tower's fourth floor and top** (groups 155, 156: the L.90 Magic
  with an L.80 or L.60). What the driver lacks there, read from the runs: a
  kill order that puts the L.90 first through the rebound (the direct line
  prefers the L.60's weakness), and a party heal that is not a turn per
  member. Then MagiMaster (Shell, Life 3 at his end: `opts.shellVs`,
  `opts.reraiseVs`, built and not yet met).
- **Golem** came up in none of the 16 visits of any run (ZoneSeek on the
  12th each time: the auction's draw does not follow the encounter history).
- **The basement can wipe the Owzer party.** With six encounters used up at
  the save point before Chadarnook, SoulDancer x2 and Crusher x2 won
  (`lab/var/relm_k6`: `battle $11C LOST`); the base run and K=3 did not meet
  it.
- **No Warp out of the tower (owner, 2026-10-19).** Every tower map (362-371)
  has map_prop byte 1 bit 1 ($0521 & $02, the field menu's warp enable) clear
  in vanilla, so neither Warp nor a Warp Stone works there; a Smoke Bomb only
  ends one battle. We keep it: the walk down is the tower's design. If
  MagiMaster's fight drains the party, shorten the fight (#442), don't open
  the exit.

## 12. Played (v0.31)

The tower leg is on the graph: `wor_tower` (`gen_wor_tower`) Continues
`wor-tower-v1` and saves `wor-thamasa-v1`. Evidence is under
`build/attempts/wt/v031-tower/lab/` and `build/attempts/wt/v031-tower-2/lab/`.

- **The basement draw.** `gen_wor_relm` kills the SoulDancers first in
  Owzer's basement. From `wor-owzer-v1` with 0 to 8 encounters used up
  (K7 not run), every variant won the leg, K6 among them (`relm_k6`:
  `PASS (frame 338319) attempts=1/1`).
- **The fourth floor.** The L.90 Magic is killed first (`opts.magicFirst`),
  above the third floor the rings come off and Shell goes up, and the
  stones change (TERRA Palidor, RELM Phantom, STRAGO Maduin). It still wipes
  some draws: the captured chain lost its first attempt to the L.90 and
  L.80 Magic and won the second (`cap3b`: `attempt 1/3 FAILED class=wipe`,
  `formation 0164 0163`; `PASS (frame 466591) attempts=2/3`).
- **MagiMaster.** Shell on all four, Life 3 (Life at 2 BP) on the living
  once he is low, the attack held until they have it (at most 3,600
  frames), TERRA's Fire at 3 BP as Ultima, no Drain (it heals him). From
  one state before his fight and four seed shifts: the hold that waited on
  the fallen lost all four to the time limit (`mm13_*`); the bounded hold
  won three (`mm14_*`: `MagiMaster: battle $162 won after 112839 ticks`
  for s0). The fourth, s9, ended with STRAGO alone: the wall nulled every
  element he holds, so he cast Scan until the time limit while MagiMaster
  healed (`partyhp=0,0,0,3219`). A Fenix Down in place of that Scan was
  tried and did worse (`mm15_*`: two of four; s0 spent 38 Fenix Downs into
  re-kills), so it was reverted.
- **Absorb guard.** The formation-0 test is gone: a retry now clears the
  battle reader's last-battle frame, which was what made field frames read
  as battles.

- **Qualification.** A bare `ninja` on px13 played both legs: `wor_relm`
  `PASS (frame 341376) attempts=1/3`; `wor_tower` lost its first attempt to
  the 200,000-frame limit at MagiMaster and won the second (`MagiMaster:
  battle $162 won after 143885 ticks`, `PASS (frame 508873) attempts=2/3`;
  `build/attempts/wt/v031-tower-2/ninja/`).

### 12.1 One attempt

The qualification's tower leg needed its second attempt, so the leg was
made to pass at one attempt across draws (`lab/` under
`build/attempts/wt/v031-tower-2/`). What each failure was, and the answer:

- **MagiMaster's stalls.** STRAGO on Sraphim holds no attack spell; left
  alone he Scanned to the time limit (`mm16_*_s9`: `no candidate in the
  list`). The last member standing with no attack now raises a fallen
  member, the one holding an attack first; a raise whenever nothing hurt,
  the others standing, did worse (`mm15_*`, reverted). Drain heals him and
  was back on his list (`sw2_k4_s13`: RELM's Drain `took 0` 64 times); it is
  off again. RELM on Ifrit, walled and without Scan, passed four turns
  into the recovery cap (`sw3_*`); a seat with no line now casts the
  cheapest attack his wall nulls but does not absorb, for the counter that
  turns the wall.
- **A lone survivor anywhere.** The last member standing whose last three
  actions took nothing raises a fallen member (`sw3_k0_s9`: RELM's Drain
  for 0 on the first floor to the time limit).
- **The fourth floor and the top.** The four died holding points to the
  L.90 Magic (`cap3b`): a `magicFirst` body now takes the whole bank, and
  TERRA keeps hers for Ultima while a 5,000-HP body stands. The side
  rooms' gear goes on after each (`H.gearDress`, magic defence counted three
  times, defence once: every fight in the tower is spells):
  STRAGO had worn a Mithril Shld (MDef 18) with the Genji Shld (MDef 50) in
  the bag when Merton took 3,366 from each member on the walk down
  (`mm18_*_s4`).
- **The walk down dry.** A long MagiMaster fight spent the 99 Tinctures and
  TERRA passed at 0 MP (`f4e_*_s2`). Twenty Tinctures are kept out of the
  care before MagiMaster and of his fight for the walk down (supplies, not
  running: the decision of 2026-10-13; a run-when-dry rule was tried and
  removed).
- **A second MagiMaster battle.** His dying Ultima took all four to 0 and
  Life 3 raised them after his death; a new walker read that as a battle
  (`sw2_k3_s0`: `its formation was fought once: got 2`). A watch that
  opens with every seat at 0 HP and no monster standing is a tail.
- **His end.** Two Ultimas can take him from 45% to 5% inside 600
  frames; Life 3 now starts at 60% of his HP and the hold at 40%, the hold
  lasts while a member can still cast Life 3, and a held seat never falls
  through to an attack (`re1`-`re3_k3_s0`: his dying Ultima wiped the four).
- **A greyed Magic row.** With no Fight row and no Magic line a seat uses a
  Tonic or Potion rather than a pass that parks the menu (`dbg1_k0_s25`).
- **His fight is long.** Won fights ran 46,501 to 195,414 ticks (`sw4_*`).
  sw4_k5_s3 was not slow but stalled: he reached 4,081 HP, every cast was
  nulled for about 7,500 frames, and he healed to 21,230 by the old
  200,000. The fight has 400,000 frames, and fails loudly when his HP sets
  no new low in 120,000 ticks (`opts.progressVs`; the longest such stretch
  in 72 won fights was 84,900).
  Three of the eight elements are no member's, and a cast that lands after
  his wall turned is absorbed. This is a fight won by attrition, a lab
  candidate: more elements (an earth, wind or water caster) or a way to
  time casts to the wall would shorten it.

The sweep at 86d84182: the tower leg from the tracked `wor-tower-v1`, 0 to
5 world battles used up beside the tower first, six seed shifts, one
attempt each (`sw5_*`, `sw6_*`): 36 of 36 passed. Counted by distinct
battle key ($be and group): MagiMaster in 26 keys of 36 meetings, the L.90
and L.80 Magic in 35 of 42, the L.90 and L.60 Magic in 20 of 24. His fight
ran 39,982 to 203,654 ticks. Before these changes the same sweep shape
passed 13 of 18 (`sw2_*`) and 16 of 18 (`sw4_*`).

After the review fixes, the same sweep at 3f3e7ea1 (`sw13_*`, `sw14_*`):
36 of 36 at one attempt; MagiMaster in 26 keys of 36 meetings, the L.90
and L.80 Magic in 31 of 42, the L.90 and L.60 Magic in 18 of 24; his fight
ran 53,495 to 198,092 ticks. The draws of sw4_k5_s3 and sw2_k3_s0 passed
(`re5_*`), and with the dead-open tail rule switched off (`mut6_k5_s3`)
the k5 s3 draw failed `MagiMaster: its formation was fought once: got 2`.

### 12.2 The bag and the rings out of the tower (v0.36, #457, #460)

Evidence under `build/attempts/wt/v036-route/lab/`.

- **The bag.** The care healed from the bag first, and a Potion gives 250
  of a member's 3,500 HP, so the first floor's randoms drank 87 Potions
  and the party left the tower with 2 (main's play at cfae9e47, and lab
  `tw0_k0_s0`, the old generator from the tracked `wor-tower-v1`:
  "beside the Falcon after the tower ... tonic=0 potion=2 ... tincture=1
  ... tent=0"). Inside there is no Tent or inn, so MP is bought back with
  Tinctures (1,500 GP for 50 MP), and a Cure costs 5 MP (150 GP of
  Tinctures) for about 700 HP (`tw1_k1_s7`: "cast $2D on char 7: 402 ->
  1087 hp, caster 256 -> 251 mp"). The tower's care now casts first
  (`H.careCastFirst`, the field care's `opts.castFirst`) and reaches for
  the bag when no cure can be cast. The last care's spend-MP-to-zero
  stopgap is gone. Over the sweep `tw1` (K 0-5 at shifts 0, 7 and 13: 18
  of 18 PASS at one attempt) the save held 66 to 95 Potions and 4 Tonics,
  every member at full HP. Tinctures still run down to 1-26 (the climb's
  attacks are its MP), and in 3 of 18 runs a member reached the save under
  a fifth of his MP (`tw1_k1_s7`: TERRA 9/559; the next leg's first stop is
  Thamasa's inn). A walk down that healed from the bag again (`tw2`) left
  4 Potions in three runs and saved no MP, so it was dropped.
- **The rings.** The Wall Rings came off before the Holy Dragon and went
  back on after him, but the fourth floor's second "on" recorded the
  rings themselves as the relic to restore, so every later "off" restored
  nothing: MagiMaster has always been fought in them (`v031-tower-2/lab/
  sw13_k0_s5`: "dressed for MagiMaster: kit TERRA 02 06 64 7F 94 CA BB"),
  and CELES, STRAGO, RELM and TERRA left the tower wearing them. The
  record now skips a ring already worn; MagiMaster's fight is left as
  measured, in the rings; and out of the tower, beside the Falcon, the
  rings come off and each member's relic from before the climb goes back
  on (every run of `tw1`: slot 5 TERRA $C3, CELES $B1, STRAGO $B5, RELM
  $B1).
- **The sweep.** `tw1` at e4491312: 18 of 18 PASS at one attempt; the Holy
  Dragon in 16 distinct keys over 19 meetings (with `tw0`), MagiMaster in
  14 over 19, every one won (`tally_tw.txt`).
