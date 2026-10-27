# World of Ruin coverage audit

Milestone "WoR side trips", #385. What a player can reach in the World of
Ruin that the route never plays, read from the ROM's data and from the
route's own play logs. It is the World of Ruin counterpart of the World of
Balance audit (`build/attempts/wob-coverage/`, issues #279-#286, #350) and
uses the same method: build the universe from the ROM, mark what the logs
show was played, group the rest into issue-sized units.

The route state audited is `wor-colosseum-v1` (CELES L52, TERRA L53, CYAN
and SHADOW L41), the end of the v0.37 line, built from `36907d28`.
Kefka's Tower is the next arc and is listed apart (section 7). Evidence is
under `build/attempts/wt/v038-wor-coverage/`; section 10 quotes the raw
lines behind each number. Line numbers are into
`ff6/src/event/event_main.asm` unless a file is named.

## 0. Findings

1. **The route plays 147 of the 190 map ids listed in
   section 4** (outside Kefka's Tower) and stands on at most 622
   of the world map's 11,467 battle tiles. The unvisited maps are
   shops, inns, houses and screens of towns the route enters; none rolls
   a battle. Every dungeon except Kefka's Tower is entered.
2. **The world map's encounter groups are mostly unfought.** Of the
   54 formations the 30 world groups can deal (the Veldt aside),
   20 were fought. Ten groups were never fought in any formation
   (0, 29, 33, 35, 46, 50, 54, 55, 56, 111), ten were fought in part, ten in full.
3. **The dinosaur forest is group 54**: Tyranosaur (L57, 8,800 XP), two
   Tyranosaurs (17,600 XP) and, one roll in sixteen, Brachosaur (L77,
   14,396 XP, 46,050 HP, casts Ultima). 52 forest tiles, x193-202 y47-53,
   one step from a tile the Falcon lands on, (195,46). Never fought, never
   stood on.
4. **The Cactrot desert is group 111**: Hoover (L49, 7,524 XP, 10,000 GP)
   and Cactrot (HP 3, 0 XP, 10,000 GP). 33 desert tiles, x61-71 y187-193,
   one step from a landing tile, (70,186), and seven from Maranda's door,
   beside which `wor-colosseum-v1` saves. Never fought, never stood on.
5. **The airship-only isles hold no content of their own.** 98 components
   of land have battle tiles and no door; they roll groups 31, 33, 34, 38,
   43, 47, 49, 53, 55 and 56 (and the Veldt's), every one of which also has
   tiles beside a town. The exception is Triangle Island (group 32, the Zone
   Eater), which the route plays. The isles are reachable and empty.
6. **Seven chests hold a monster.** Two are opened (Darill's Tomb, the
   Veldt cave). Five are not: two in the Tzen house (four Pm Stalkers
   each), Umaro's cave (three Pugs, L99, 42,003 HP), the Ancient Castle
   (Master Pug L73, 22,000 HP) and its basement (KatanaSoul L61, 37,620
   HP).
7. **53 chests with a prize are unopened outside Kefka's Tower**
   (16 more inside it), against 62 the WoR legs open. Ten more
   records are empty in the ROM (prize `$00`).
8. **Eight WoR prizes are gone before the WoR starts.** A bit shared
   between a WoB map and its WoR copy is spent by the WoB route's opening;
   South Figaro's six (X-Potion, Tent, Remedy, Revivify, Tent, Fenix Down)
   and the Moogle cave's two (Pod Bracelet, Elixir) are the WoR copy's
   prizes (section 5.2). Issue #350 item 8 names the Narshe pair.
9. **Every optional dragon and boss before Kefka's Tower is fought**
   (Storm, Ice, White, Red, Dirt, Blue; Doom Gaze; Umaro; Hidon). Gold and
   Skull Dragon are in Kefka's Tower.

## 1. Totals

| | count |
|---|---|
| map ids listed, outside Kefka's Tower | 190 |
| of them visited by a WoR leg | 147 |
| field maps that roll a battle | 58 (all visited) |
| formations those maps can deal | 118, fought 69 |
| world battle tiles (non-Veldt) | 11,467, stood on 622 |
| world groups (non-Veldt) | 30: fully fought 10, in part 10, none 10 |
| formations in world pools | 54, fought 20 |
| chest bits with a prize, opened by WoR legs | 62 |
| chest bits with a prize, opened in the WoB | 30 |
| chest bits with a prize, unopened (not Kefka's Tower) | 53, five of them monster boxes |
| chest bits with a prize, unopened in Kefka's Tower | 16 |

## 2. What counts as played

- **A formation is fought** when a WoR play log has `[outcome] battle $XXX`
  for it. An event battle prints a stale `$11E0` (SrBehemoth printed
  `$1A8`, formation 452 is the one dealt), so an event battle also counts
  when the species killed or escaped are exactly the formation's. The Zone
  Eater's formation `$14F` is a door: its script Engulfs and writes no
  outcome (`route-wor-gogo.md` finding 1; `wor_belly.log`, section 10).
- **A map is visited** when a WoR log has a `[tiles]` line for it; a world
  tile is stood on when one lists it. The trace also records field
  coordinates while the map id is still 1 (section 9), so "stood on" is a
  ceiling; a zone at zero is certain.
- **A chest is opened** when its bit is set in
  `tools/tests/checkpoints/wor-colosseum-v1/wor-colosseum.sram` ($1E40);
  it is "opened in the WoB" when it is also set in
  `build/states/fc_alcove.mss`.
- **The universe** is the ROM's: the 256x256 world tilemap's walkable
  components (`WorldTileProp` bit `$10` clear) with the encounter group of
  each battle tile (`WorldBattleGroup`), the field maps' pools
  (`SubBattleGroup`, `RandBattleGroup`), `TreasureProp`, and every
  `battle`/`treasure_battle` in the event script that a WoR map's triggers,
  NPCs or init event reach, vetted by hand (the graph over-approximates).
  Reachable means the Falcon can land on the component (`WorldTileProp` byte
  1 bit `$02` clear) or it holds a door.

## 3. The world map

### 3.1 Every group

Columns: the group, a name where `level-curve.md` or the route docs give
one, the bounding box of its battle tiles, battle tiles, tiles in
components with no door (airship isles), tiles the route stood on, and the
pool with each formation's draw odds and whether it was fought.

| group | name | bbox | tiles | isle tiles | stood | formations |
|---|---|---|---|---|---|---|
| 0 |  | x160-163 y193-207 | 38 | 0 | 0 | 6 Leafer 62.5% **not fought**; 7 Leafer+Leafer+Dark Wind 37.5% **not fought** |
| 29 | Solitary Island | x71-81 y231-242 | 62 | 0 | 6 | 192 Peepers+Peepers 62.5% **not fought**; 193 Peepers+Peepers+Peepers 37.5% **not fought** |
| 30 | Solitary Island (east strip) | x77-79 y238-241 | 7 | 0 | 0 | 194 EarthGuard+Peepers+Peepers 62.5% FOUGHT; 195 Black Drgn 37.5% FOUGHT |
| 31 |  | x110-156 y148-214 | 584 | 2 | 62 | 197 Mesosaur+Mesosaur 62.5% FOUGHT; 199 Gilomantis+Mesosaur 37.5% FOUGHT |
| 32 | Triangle Island (the Zone Eater) | x229-246 y41-59 | 180 | 180 | 6 | 335 Zone Eater 100% FOUGHT |
| 33 |  | x97-127 y147-223 | 495 | 60 | 1 | 203 Lunaris+Lunaris 62.5% **not fought**; 201 Chitonid+Gigan Toad+Gigan Toad 37.5% **not fought** |
| 34 |  | x128-159 y162-229 | 740 | 98 | 52 | 202 Lunaris+Osprey 62.5% FOUGHT; 204 Osprey+Chitonid+Gigan Toad 37.5% FOUGHT |
| 35 |  | x111-127 y164-213 | 29 | 0 | 0 | 198 Mesosaur+Mesosaur+Mesosaur+Mesosaur 62.5% **not fought**; 200 Gilomantis+Gilomantis+Mesosaur 37.5% **not fought** |
| 36 | Tzen's desert (the Black Drgn's pool) | x111-130 y166-219 | 94 | 0 | 8 | 194 EarthGuard+Peepers+Peepers 62.5% FOUGHT; 195 Black Drgn 37.5% FOUGHT |
| 37 |  | x137-236 y71-186 | 504 | 0 | 23 | 216 Bloompire+Bloompire 31.25% **not fought**; 213 Buffalax 31.25% FOUGHT; 215 Bloompire+Bloompire+Lizard 37.5% **not fought** |
| 38 | Mobliz's plain | x144-241 y128-191 | 876 | 77 | 77 | 214 Buffalax+Delta Bug+Delta Bug 62.5% FOUGHT; 217 Delta Bug+Delta Bug+Delta Bug+Delta Bug 37.5% FOUGHT |
| 39 |  | x129-168 y66-127 | 418 | 0 | 58 | 219 Buffalax+Lizard 31.25% FOUGHT; 218 Bloompire+Bloompire+Delta Bug 31.25% **not fought**; 217 Delta Bug+Delta Bug+Delta Bug+Delta Bug 37.5% FOUGHT |
| 40 |  | x149-167 y85-166 | 126 | 0 | 8 | 195 Black Drgn 100% FOUGHT |
| 41 |  | x98-118 y91-107 | 95 | 0 | 42 | 134 Nohrabbit+Nohrabbit+Nohrabbit 100% FOUGHT |
| 42 |  | x106-117 y94-104 | 38 | 0 | 6 | 224 Latimeria 62.5% FOUGHT; 225 Latimeria+Nohrabbit+Nohrabbit+Nohrabbit 37.5% **not fought** |
| 43 |  | x65-120 y65-120 | 669 | 41 | 79 | 220 Maliga+Maliga+Nohrabbit+Nohrabbit 100% FOUGHT |
| 44 |  | x50-102 y49-100 | 788 | 0 | 53 | 222 Sand Horse+Sand Horse 31.25% FOUGHT; 223 Sand Horse+Maliga+Maliga 31.25% **not fought**; 138 Maliga+Maliga+Maliga 37.5% **not fought** |
| 45 |  | x27-72 y11-77 | 592 | 0 | 25 | 236 Harpiai 62.5% FOUGHT; 243 Muus 37.5% **not fought** |
| 46 |  | x31-65 y36-65 | 99 | 0 | 6 | 238 Harpiai+Deep Eye+Deep Eye 37.5% **not fought**; 240 Deep Eye+Deep Eye+Deep Eye+Deep Eye+Deep Eye+Deep Eye 31.25% **not fought**; 242 Muus+Muus+Muus 31.25% **not fought** |
| 47 |  | x18-78 y6-94 | 1133 | 207 | 45 | 239 Bogy+Bogy 62.5% **not fought**; 241 Deep Eye+Muus+Muus+Deep Eye 37.5% FOUGHT |
| 48 |  | x16-73 y115-191 | 472 | 0 | 19 | 319 Crawler+Crawler+Crawler 62.5% FOUGHT; 326 Geckorex+Geckorex+Reach Frog 37.5% FOUGHT |
| 49 | Zozo / Jidoor / Maranda plain | x8-75 y113-197 | 914 | 30 | 13 | 319 Crawler+Crawler+Crawler 62.5% FOUGHT; 323 Mantodea+Sprinter+Spek Tor+Spek Tor 37.5% **not fought** |
| 50 |  | x27-67 y147-187 | 61 | 0 | 1 | 324 Reach Frog+Reach Frog+Reach Frog+Reach Frog 62.5% **not fought**; 325 Mantodea+Mantodea 37.5% **not fought** |
| 51 | Narshe's plain | x98-154 y13-42 | 361 | 0 | 9 | 326 Geckorex+Geckorex+Reach Frog 31.25% FOUGHT; 324 Reach Frog+Reach Frog+Reach Frog+Reach Frog 31.25% **not fought**; 325 Mantodea+Mantodea 31.25% **not fought**; 323 Mantodea+Sprinter+Spek Tor+Spek Tor 6.25% **not fought** |
| 52 | Doma's plain | x167-220 y33-83 | 398 | 0 | 5 | 328 Sprinter+Sprinter+Spek Tor+Spek Tor 62.5% FOUGHT; 327 TumbleWeed+TumbleWeed+TumbleWeed+TumbleWeed 31.25% **not fought**; 323 Mantodea+Sprinter+Spek Tor+Spek Tor 6.25% **not fought** |
| 53 |  | x96-221 y9-238 | 1368 | 250 | 9 | 103 Crawler 31.25% **not fought**; 319 Crawler+Crawler+Crawler 31.25% FOUGHT; 114 Crawler+Crawler+Crawler+Crawler 37.5% **not fought** |
| 54 | the dinosaur forest | x193-202 y47-53 | 52 | 0 | 0 | 321 Tyranosaur 62.5% **not fought**; 320 Tyranosaur+Tyranosaur 31.25% **not fought**; 322 Brachosaur 6.25% **not fought** |
| 55 | Thamasa's plain | x228-252 y221-236 | 95 | 13 | 2 | 331 Harpy 62.5% **not fought**; 332 Harpy+Prussian 37.5% **not fought** |
| 56 | Thamasa's plain (shore) | x225-253 y220-238 | 146 | 14 | 7 | 334 GloomShell+GloomShell+GloomShell 62.5% **not fought**; 333 Prussian+GloomShell 37.5% **not fought** |
| 111 | the Cactrot desert | x61-71 y187-193 | 33 | 0 | 0 | 237 Hoover 62.5% **not fought**; 221 Cactrot 37.5% **not fought** |

Group 255 is the Veldt (1,024 tiles, 3 stood on); its formations come from
Gau's rage table, not a pool, and are not enumerated here.

### 3.2 The named zones

**The dinosaur forest (group 54).** The pool is slot 0 and slot 2
Tyranosaur (62.5%), slot 1 two Tyranosaurs (31.25%), slot 3 Brachosaur
(6.25%). Tyranosaur is L57, 12,770 HP, weak to ice, immune to most
statuses, and casts Meteor; Brachosaur is L77, 46,050 HP, with Disaster,
Meteor, Sneeze and Ultima. Both rows are the generated floor (6 shields,
pierce). A random pays XP x2 split four ways: 4,400 per member for one
Tyranosaur, 8,800 for two, 7,198 for Brachosaur, against 3,168-4,178 for
the grind groups `level-curve.md` names (49-52). The tiles are forest
(`WorldTileProp` `$0166`): the Falcon cannot land on them, so a player
lands on the plain of component 12, at (195,46) one step off the forest
(`near.txt`), or walks from the door of Gau's father's house at (178,45):
21 steps, the last four in group 54 (`trips.txt`). `level-curve.md` (line 269) calls these formations
"WoR-gated" and leaves them there; nothing places a fight there.

**The Cactrot desert (group 111).** Desert tiles (`$0246`, not landable) on
component 63 beside Maranda's plain. Hoover is slots 0 and 2 (62.5%),
Cactrot slots 1 and 3 (37.5%). Hoover: L49, 12,018 HP, 7,524 XP (3,762 per
member), 10,000 GP, weak to ice and water, counters with Sand Storm.
Cactrot: HP 3, MP 60,000, defence and magic defence 255, evade 250, 0 XP,
10,000 GP, casts Blow Fish; it is the vanilla gil target. The nearest
landing is (70,186), one step off the desert (`near.txt`); from Maranda's
door at (69,184), beside the save `wor-colosseum-v1` makes at (69,183), it
is seven steps south. Both rows are the floor.

**Thamasa's plain (groups 55 and 56).** L41-42 monsters (Harpy, Prussian,
GloomShell), 5,035 XP a random in `level-curve.md`'s table, which names it
a grind with Ebot's door. 95 and 146 battle tiles around Thamasa (bounding
boxes in the table); the route stood on 2 and 7 of them and rolled no
fight there. All four formations have authored rows. Since #484
`gen_wor_thamasa_plain`, a branch from `wor-gogo-v1`, fights all four
(route-wor-gogo.md section 9).

**The plains the design sends players to grind (groups 48-53).**
`level-curve.md` names 49, 51 and 52 "the World of Ruin's grind". Of the nine
formations in groups 48-53 the route fought three (Crawler x3 319, Geckorex
326, Sprinter 328) and left six: Mantodea+Sprinter+Spek Tor x2 (323, 9,617
XP), Reach Frog x4 (324), Mantodea x2 (325, 9,224 XP), TumbleWeed x4 (327,
10,216 XP, 31% of group 52), Crawler (103) and Crawler x4 (114). Group 50
(61 forest tiles beside Maranda and the Opera House, x27-67 y147-187:
Reach Frog x4, Mantodea x2) has no formation fought. A player grinding
there meets all of them. Since #483 `gen_wor_colosseum` fights all six
before its save (route-wor-colosseum.md section 9).

**The early continents (groups 0, 29, 33, 35, 37, 39, 42, 44, 45, 46, 47).**
L23-29 monsters worth 94-2,310 XP a random (the 19 formations are in
`units.txt`, unit E). The early legs (`wor_start` to `wor_figaro_sweep`) walk
their neighbours; none of these 19 was drawn. Group 0
(38 tiles at x160-163 y193-207, Leafer L5) pays 12-38 per member.

### 3.3 The airship-only isles

98 walkable components with battle tiles have no door (`isles.txt`). 97 of
them roll groups 31, 33, 34, 38, 43, 47, 49, 53, 55, 56 or the Veldt (255),
all of which also have tiles on a component with a door; none adds a
formation to the universe. The exception is Triangle
Island (component 20, 180 tiles, group 32): the Zone Eater is its only
formation, and `gen_wor_belly` plays it. Two other tile kinds sit on the
isles: Kefka's Tower's landing (137,196-198, `WorldTileProp` bit `$8000`)
and the Phoenix Cave's (117-118,156-157, bit `$4000`); both are played or
scheduled. So the airship-only isles are not a content unit: there is
nothing on them that the mainland pools do not already have.

## 4. Towns, dungeons and rooms

### 4.1 Areas

Maps visited, formations fought of those the area's pools can deal (the
unfought ones are listed), and chest bits opened by WoR legs / already
opened in the WoB / unopened with a prize.

| area | maps visited | formations fought | unfought | chests: WoR / WoB / unopened |
|---|---|---|---|---|
| Solitary Island (Cid) | 4/6 | 0/0 | - | 0 / 0 / 0 |
| Albrook | 4/6 | 0/0 | - | 0 / 0 / 3 (+2 empty) |
| Tzen | 6/8 | 2/2 | - | 0 / 0 / 8 |
| Mobliz | 6/12 | 0/0 | - | 3 / 0 / 0 |
| Sabin's cabin | 1/2 | 0/0 | - | 0 / 0 / 0 |
| Darill's Tomb | 5/5 | 5/8 | 244, 245, 251 | 6 / 0 / 0 |
| Nikeah | 4/5 | 0/0 | - | 0 / 0 / 1 |
| Figaro Castle | 12/15 | 5/7 | 230, 234 | 9 / 2 / 2 |
| South Figaro | 10/16 | 2/3 | 374 | 8 / 15 / 0 (+1 empty) |
| Kohlingen | 5/5 | 0/0 | - | 2 / 0 / 0 |
| Maranda | 4/5 | 0/0 | - | 0 / 0 / 2 |
| Dragon's Neck Colosseum | 1/1 | 0/0 | - | 0 / 0 / 0 |
| Gau's father's house | 2/3 | 0/0 | - | 0 / 0 / 0 |
| Cave in the Veldt | 1/1 | 2/3 | 270 | 3 / 0 / 0 |
| Opera House | 3/3 | 0/0 | - | 0 / 0 / 0 |
| Jidoor / Owzer's mansion | 10/11 | 1/3 | 284, 286 | 0 / 1 / 2 |
| Zozo (town) | 2/3 | 4/8 | 106, 107, 108, 110 | 0 / 2 / 7 |
| Mt. Zozo | 7/7 | 5/9 | 6, 7, 261, 264 | 5 / 0 / 0 (+1 empty) |
| Narshe (WoR town) | 6/13 | 0/0 | - | 6 / 1 / 2 (+1 empty) |
| Narshe mines / Moogle cave / Tritoch cliff | 8/8 | 9/10 | 277 | 2 / 2 / 0 |
| Umaro's cave | 3/3 | 2/8 | 253, 255, 257, 258, 259, 260 | 2 / 0 / 1 |
| Thamasa (WoR) | 8/12 | 0/0 | - | 1 / 7 / 0 |
| Doma Castle | 3/5 | 3/4 | 318 | 0 / 0 / 6 |
| Cyan's dream | 5/5 | 5/11 | 311, 312, 313, 315, 316, 318 | 2 / 0 / 2 |
| Ebot's Rock | 2/2 | 4/8 | 294, 295, 297, 298 | 0 / 0 / 0 |
| Fanatics' Tower | 12/12 | 10/14 | 171, 472, 478, 486 | 6 / 0 / 0 |
| Phoenix Cave | 3/5 | 7/8 | 340 | 4 / 0 / 0 (+5 empty) |
| Ancient Castle | 5/5 | 6/9 | 301, 304, 308 | 3 / 0 / 8 |
| Gogo's cave (Zone Eater) | 5/6 | 1/8 | 346, 347, 348, 349, 350, 351, 352 | 0 / 0 / 9 |

The totals row of section 1 sums these. Pools reached from more than one
map are counted once per area.

### 4.2 Maps the route never enters

The trace samples tile-aligned steps, so a screen crossed in a few frames
can be missing from it (Narshe's screens 19-23 lie between the entrance
and the shops the route did visit). None of these maps rolls a battle.

- **Solitary Island (Cid)**: 399, 403
- **Albrook**: 325 Inn, 330
- **Tzen**: 306 Tzen, 312 Relics
- **Mobliz**: 157 Mobliz, 160 Inn, 161 Arsenal, 162 Relics, 164 Item Shop, 184 Mobliz
- **Sabin's cabin**: 128
- **Nikeah**: 173 Chocobo Stable
- **Figaro Castle**: 57, 58, 60
- **South Figaro**: 47 South Figaro, 75 South Figaro, 78 Cafe, 80 Chocobo Stable, 84, 88
- **Maranda**: 288 Inn
- **Gau's father's house**: 115
- **Jidoor / Owzer's mansion**: 205 Chocobo Stable
- **Zozo (town)**: 226
- **Narshe (WoR town)**: 19 Narshe, 20 Narshe, 21, 22, 23, 25 Armor Shop, 39
- **Thamasa (WoR)**: 341 Thamasa, 342 Thamasa, 348 Elder'S House, 351
- **Doma Castle**: 121 Doma Castle, 124
- **Phoenix Cave**: 314, 316
- **Gogo's cave (Zone Eater)**: 212

### 4.3 Draw gaps in pools of dungeons the route plays

These are the #286 kind: the route walks the map and the draw never
dealt the formation. A player who pauses in the dungeon meets them.

| area | map | pool | unfought formations |
|---|---|---|---|
| Darill's Tomb | 298 | g149 | 244 Orog+Orog; 245 Orog+PowerDemon+PowerDemon |
| Darill's Tomb | 300 | g151 | 251 Mad Oscar |
| Figaro Castle | 64 | g139 | 230 Humpty+Humpty+Humpty+Humpty; 234 Drop+Drop+Drop |
| Figaro Castle | 90 | g140 | 230 Humpty+Humpty+Humpty+Humpty |
| South Figaro | 87 | g65 | 374 Vector Pup+Vector Pup |
| Cave in the Veldt | 353 | g132 | 270 Rhyos |
| Jidoor / Owzer's mansion | 207 | g157 | 284 SoulDancer+SoulDancer+Crusher+Crusher; 286 Vindr+Vindr |
| Zozo (town) | 221 | g78 | 110 HadesGigas+Harvester |
| Zozo (town) | 225 | g77 | 106 SlamDancer+Gabbldegak+Gabbldegak+Gabbldegak; 107 Harvester; 108 SlamDancer+Harvester+Harvester |
| Mt. Zozo | 177 | g162 | 261 Luridan+Luridan+Luridan; 264 Borras+Ursus+Scrapper |
| Mt. Zozo | 178 | g162 | 261 Luridan+Luridan+Luridan; 264 Borras+Ursus+Scrapper |
| Mt. Zozo | 214 | g0 | 6 Leafer; 7 Leafer+Leafer+Dark Wind |
| Narshe mines / Moogle cave / Tritoch cliff | 34 | g191 | 277 Wizard+Wizard+Psychot+Psychot+Psychot |
| Narshe mines / Moogle cave / Tritoch cliff | 35 | g191 | 277 Wizard+Wizard+Psychot+Psychot+Psychot |
| Narshe mines / Moogle cave / Tritoch cliff | 37 | g191 | 277 Wizard+Wizard+Psychot+Psychot+Psychot |
| Narshe mines / Moogle cave / Tritoch cliff | 38 | g191 | 277 Wizard+Wizard+Psychot+Psychot+Psychot |
| Umaro's cave | 281 | g166 | 253 Pug; 255 Kiwok+Ceritops |
| Umaro's cave | 282 | g167 | 257 Ceritops+Ceritops+Ceritops; 258 Anemone+Anemone+Tomb Thumb; 259 Anemone+Anemone+Anemone+Anemone; 260 Ceritops+Tomb Thumb+Tomb Thumb |
| Umaro's cave | 283 | g168 | 257 Ceritops+Ceritops+Ceritops; 258 Anemone+Anemone+Tomb Thumb; 259 Anemone+Anemone+Anemone+Anemone; 260 Ceritops+Tomb Thumb+Tomb Thumb |
| Doma Castle | 126 | g181 | 318 Suriander+Pan Dora+Parasite+Parasite |
| Cyan's dream | 144 | g181 | 318 Suriander+Pan Dora+Parasite+Parasite |
| Cyan's dream | 317 | g183 | 312 Barb-e+Critic; 315 Critic+Pan Dora+Pan Dora+Pan Dora; 316 Allosaurus |
| Cyan's dream | 319 | g182 | 311 PlutoArmor+PlutoArmor; 313 PlutoArmor+Sky Cap |
| Cyan's dream | 320 | g182 | 311 PlutoArmor+PlutoArmor; 313 PlutoArmor+Sky Cap |
| Cyan's dream | 321 | g181 | 318 Suriander+Pan Dora+Parasite+Parasite |
| Ebot's Rock | 404 | g193 | 294 Hipocampus+Hipocampus+Hipocampus |
| Ebot's Rock | 405 | g194 | 295 Hipocampus+Cluck+Cluck+Cluck; 297 Slatter+Slatter; 298 Warlock+Cluck+Cluck+Eland+Eland |
| Fanatics' Tower | 359 | g153 | 478 L.40 Magic+L.50 Magic+L.60 Magic |
| Fanatics' Tower | 361 | g155 | 472 L.90 Magic+L.60 Magic |
| Fanatics' Tower | 363 | g152 | 171 L.10 Magic+L.20 Magic |
| Fanatics' Tower | 364 | g155 | 472 L.90 Magic+L.60 Magic |
| Fanatics' Tower | 365 | g156 | 486 L.90 Magic |
| Fanatics' Tower | 366 | g156 | 486 L.90 Magic |
| Fanatics' Tower | 367 | g156 | 486 L.90 Magic |
| Fanatics' Tower | 368 | g156 | 486 L.90 Magic |
| Fanatics' Tower | 369 | g156 | 486 L.90 Magic |
| Phoenix Cave | 313 | g175 | 340 Sea Flower+Sea Flower+Sea Flower+Sea Flower+Sea Flower |
| Ancient Castle | 406 | g144 | 304 Boxed Set; 308 Boxed Set+Boxed Set+Boxed Set+Boxed Set |
| Ancient Castle | 407 | g145 | 301 Goblin+Goblin |
| Gogo's cave (Zone Eater) | 276 | g170 | 349 Karkass+Karkass; 350 Tap Dancer+Covert+Covert; 352 Woolly+Woolly+Karkass+Karkass |
| Gogo's cave (Zone Eater) | 277 | g170 | 349 Karkass+Karkass; 350 Tap Dancer+Covert+Covert; 352 Woolly+Woolly+Karkass+Karkass |
| Gogo's cave (Zone Eater) | 278 | g171 | 346 Ogor+Ogor; 347 Covert+Ogor; 348 Wart Puck+Wart Puck; 351 Tap Dancer+Woolly |

## 5. Chests

### 5.1 Unopened chests with a prize

| area | n | chests |
|---|---|---|
| Narshe (WoR town) | 2 | Sprint Shoes (map 20 (55,8), bit 1); Elixir (map 30 (105,14), bit 10) |
| Figaro Castle | 2 | Soft (map 59 (11,12), bit 16); Fenix Down (map 59 (120,11), bit 17) |
| Doma Castle | 6 | Elixir (map 123 (52,47), bit 51); Remedy (map 123 (55,5), bit 52); Fenix Down (map 123 (28,49), bit 53); Beads (map 123 (31,50), bit 54); X-Potion (map 123 (33,34), bit 96); Ether (map 123 (56,47), bit 179) |
| Nikeah | 1 | Elixir (map 171 (57,37), bit 62) |
| Zozo (town) | 7 | RunningShoes (map 226 (72,26), bit 70); X-Potion (map 226 (92,27), bit 71); Tonic (map 225 (83,53), bit 72); Chain Saw (map 225 (111,52), bit 73); Tincture (map 225 (66,50), bit 74); Thief Glove (map 225 (11,59), bit 75); Fire Knuckle (map 225 (35,11), bit 76) |
| Albrook | 3 | Potion (map 324 (56,13), bit 98); Tincture (map 326 (11,49), bit 100); Elixir (map 330 (35,7), bit 103) |
| Tzen | 8 | Heal Rod (map 311 (123,43), bit 142); Tincture (map 311 (104,43), bit 143); MONSTER BOX Pm Stalker+Pm Stalker+Pm Stalker+Pm Stalker (map 311 (102,49), bit 144); Pearl Rod (map 311 (112,49), bit 145); Hyper Wrist (map 311 (103,58), bit 146); Magicite (map 311 (125,12), bit 147); MONSTER BOX Pm Stalker+Pm Stalker+Pm Stalker+Pm Stalker (map 311 (111,12), bit 148); Drainer (map 311 (118,26), bit 149) |
| Umaro's cave | 1 | MONSTER BOX Pugs+Pugs+Pugs (map 282 (13,34), bit 170) |
| Cyan's dream | 2 | X-Potion (map 321 (24,9), bit 186); Ice Shld (map 321 (16,8), bit 187) |
| Gogo's cave (Zone Eater) | 9 | Ether (map 276 (35,16), bit 194); FakeMustache (map 276 (25,31), bit 208); Red Jacket (map 276 (40,13), bit 209); Thunder Shld (map 280 (1,45), bit 228); Zephyr Cape (map 280 (46,47), bit 232); Hero Ring (map 280 (41,43), bit 233); Tack Star (map 280 (27,44), bit 234); Magical Brsh (map 276 (42,32), bit 236); Genji Armor (map 276 (43,32), bit 237) |
| Ancient Castle | 8 | Ether (map 401 (55,21), bit 196); Wing Edge (map 401 (45,21), bit 197); MONSTER BOX Master Pug (map 401 (58,43), bit 198); Doom Darts (map 401 (49,46), bit 199); Magicite (map 401 (18,28), bit 200); X-Potion (map 401 (8,20), bit 201); MONSTER BOX KatanaSoul (map 406 (10,17), bit 205); Punisher (map 406 (59,6), bit 206) |
| Jidoor / Owzer's mansion | 2 | Moogle Suit (map 207 (92,58), bit 213); Relic Ring (map 207 (90,47), bit 258) |
| Maranda | 2 | Remedy (map 284 (28,20), bit 244); Revivify (map 284 (2,26), bit 245) |

Kefka's Tower holds 16 more, among them two Ribbons (map 292 (89,12),
map 334 (29,29)), Minerva (map 338 (5,39)) and a Megalixir.

Monster boxes (`treasure_battle`, `EventBattleGroup`): opened, Darill's Tomb
bit 161 (Presenter+Whelk Head) and the Veldt cave bit 192 (Allo Ver);
unopened, the five above. Pugs x3 (formation 235, L99) and Master Pug
(483) and KatanaSoul (465) pay no XP. The Tzen boxes are weak (formation 211, L26) but
sit inside the collapsing house's clock (`route-wor-sabin.md` section 3.4
leaves them for a second visit).

### 5.2 Prizes the WoB route takes from the WoR

Treasure bits are one array for both worlds. Where a WoB map and its WoR
copy share a bit and hold different prizes, the WoB opening spends the
bit (`shared_bits.txt`):

| bit | WoB copy | WoR copy | WoB route |
|---|---|---|---|
| 11 | map 50 Fenix Down | map 38 Pod Bracelet | opens it |
| 12 | map 50 Sleeping Bag | map 38 Elixir | opens it |
| 21 | map 75 Tonic | map 74 X-Potion | opens it |
| 22 | map 75 Antidote | map 74 Tent | opens it |
| 23 | map 75 Eyedrop | map 74 Remedy | opens it |
| 24 | map 75 Tonic | map 74 Revivify | opens it |
| 25 | map 75 Green Cherry | map 74 Tent | opens it |
| 231 | map 75 Warp Stone | map 74 Fenix Down | opens it |

Bits 13, 18, 19, 97 and 230 also have two prizes, and the route opens each
in the world that holds the better one (Ribbon at map 44, the Figaro cave
and the South Figaro elixir are WoR-opened). #350 item 8 asks the WoB route
to keep bits 11 and 12 closed; South Figaro's six are the same defect.

## 6. Bosses and events

| area | event | boss | formation | role | status |
|---|---|---|---|---|---|
| Darill's Tomb | `event_main.asm:10537` `_ca42f1` | Dullahan | 455 | story (the Falcon) | FOUGHT |
| Figaro Castle | `event_main.asm:15937` `_ca6a48` | Tentacle+Tentacle+Tentacle+Tentacle | 454 | story | FOUGHT |
| Opera House | `event_main.asm:28209` `_cab6d6` | Dirt Drgn | 368 | dragon, optional | FOUGHT |
| Jidoor / Owzer's mansion | `event_main.asm:47983` `_cb47ce` | Dahling+Dahling | 288 | story | FOUGHT |
| Jidoor / Owzer's mansion | `event_main.asm:48012` `_cb481a` | Nightshade+Nightshade+Nightshade | 289 | story | FOUGHT |
| Jidoor / Owzer's mansion | `event_main.asm:48290` `_cb49f3` | SoulDancer+Wild Cat+Wild Cat+Wild Cat+Wild Cat | 287 | story | FOUGHT |
| Jidoor / Owzer's mansion | `event_main.asm:48331` `_cb4a4e` | SoulDancer+Wild Cat+Wild Cat+Wild Cat+Wild Cat | 287 | story | FOUGHT |
| Jidoor / Owzer's mansion | `event_main.asm:48367` `_cb4a8e` | SoulDancer+Wild Cat+Wild Cat+Wild Cat+Wild Cat | 287 | story | FOUGHT |
| Jidoor / Owzer's mansion | `event_main.asm:48403` `_cb4acd` | SoulDancer+Wild Cat+Wild Cat+Wild Cat+Wild Cat | 287 | story | FOUGHT |
| Jidoor / Owzer's mansion | `event_main.asm:48439` `_cb4b0c` | SoulDancer+Wild Cat+Wild Cat+Wild Cat+Wild Cat | 287 | story | FOUGHT |
| Jidoor / Owzer's mansion | `event_main.asm:48615` `_cb4c47` | Still Life | 290 | story | FOUGHT |
| Jidoor / Owzer's mansion | `event_main.asm:48727` `_cb4cfa` | Chadarnook | 456 | story boss | FOUGHT |
| Ebot's Rock | `event_main.asm:54567` `_cb71d2` | Hidon+Hidonite+Hidonite+Hidonite+Hidonite | 464 | story | FOUGHT |
| Cave in the Veldt | `event_main.asm:55996` `_cb7a18` | SrBehemoth | 452 | story | FOUGHT |
| Cyan's dream | `event_main.asm:58739` `_cb8bd1` | Curley+Larry+Moe | 460 | story | FOUGHT |
| Cyan's dream | `event_main.asm:60300` `_cb97d6` | Wrexsoul+SoulSaver+SoulSaver | 462 | story | FOUGHT |
| Kefka's Tower | `event_main.asm:80038` `_cc16d6` | Doom | 468 | Kefka's Tower statue | **not fought** |
| Kefka's Tower | `event_main.asm:80074` `_cc1716` | Goddess | 469 | Kefka's Tower statue | **not fought** |
| Kefka's Tower | `event_main.asm:80105` `_cc174f` | Poltrgeist | 470 | Kefka's Tower statue | **not fought** |
| Kefka's Tower | `event_main.asm:80251` `_cc1827` | Guardian | 446 | Kefka's Tower | **not fought** |
| Kefka's Tower | `event_main.asm:80306` `_cc1872` | Inferno+Striker+Rough | 484 | Kefka's Tower | **not fought** |
| Kefka's Tower | `event_main.asm:80316` `_cc18b4` | Atma | 482 | Kefka's Tower | **not fought** |
| Kefka's Tower | `event_main.asm:80356` `_cc18d9` | Gold Drgn | 369 | dragon, Kefka's Tower | **not fought** |
| Kefka's Tower | `event_main.asm:80384` `_cc1906` | Skull Drgn | 370 | dragon, Kefka's Tower | **not fought** |
| Phoenix Cave | `event_main.asm:81455` `_cc2048` | Red Dragon | 372 | dragon, optional | FOUGHT |
| Ancient Castle | `event_main.asm:81465` `_cc205b` | Blue Drgn | 371 | dragon, optional | FOUGHT |
| Narshe mines / Moogle cave / Tritoch cliff | `event_main.asm:84730` `_cc36df` | Ice Dragon | 366 | dragon, optional | FOUGHT |
| Narshe mines / Moogle cave / Tritoch cliff | `event_main.asm:84785` `_cc3719` | Tritoch | 487 | story | FOUGHT |
| Mt. Zozo | `event_main.asm:86872` `_cc43cd` | Storm Drgn | 367 | dragon, optional | FOUGHT |
| Mobliz | `event_main.asm:87704` `_cc4990` | Phunbaba | 420 | story | FOUGHT |
| Mobliz | `event_main.asm:87750` `_cc4990` | Phunbaba | 421 | story | FOUGHT |
| Mobliz | `event_main.asm:88114` `_cc4c1b` | Phunbaba | 422 | story | FOUGHT |
| Mobliz | `event_main.asm:88201` `_cc4c1b` | Phunbaba | 423 | story | FOUGHT |
| Fanatics' Tower | `event_main.asm:89675` `_cc544b` | MagiMaster | 354 | story | FOUGHT |
| Fanatics' Tower | `event_main.asm:89683` `_cc558b` | White Drgn | 481 | dragon, optional | FOUGHT |
| Umaro's cave | `event_main.asm:110705` `_ccd709` | Umaro | 444 | optional (Umaro) | FOUGHT |

Doom Gaze (formation 463, `EventBattleGroup` 93) is a sky event fought in
`gen_wor_opera`: `[doom] [outcome] battle $1CF`. Zone Eater: section 2.
Not in the table because it is a world tile, not a script: the Veldt.

## 7. Past the route's end

Kefka's Tower is the v0.38 arc (`level-curve.md`'s table). Its 34 map
ids (17, 254-261, 287-296, 303-304, 329, 333-339, 352, 354-357, 409-411)
roll 32 formations never fought, hold 16 unopened chests, and deal
the eight scripted fights in section 6 (Guardian, three statues, Inferno,
Atma, Gold and Skull Dragon). Not a side trip: audited here only so nobody counts it twice.

## 8. Proposed units

Sized as the WoB milestone's were: S is a branch with one to three
formations and no new authored rows, M a branch with a lab or several
formations, L new design (rows, a boss lab). "Branch" names the leg whose
boot checkpoint the branch Continues and the leg it rejoins.

| # | unit | branches off | adds | size | a player would |
|---|---|---|---|---|---|
| 1 | The dinosaur forest, group 54 | the Falcon at `wor-gau-v1` (TERRA and CELES L50) or a later save, flown to (195,46); first reachable at `wor-falcon-v1` | forms 321, 320, 322 (Tyranosaur; Tyranosaur x2; Brachosaur L77 Ultima), rows to author | L | yes: the grind `level-curve.md` itself calls huge |
| 2 | The Cactrot desert, group 111 | the save `wor-colosseum-v1` (69,183), seven steps off | forms 237 Hoover L49, 221 Cactrot; rows to author | S | yes, for gil and XP |
| 3 | The grind plains' missing formations, groups 48-53 | any WoR leg that passes a plain; the Falcon's tile at `wor-ancient-v1` | forms 323, 324, 325, 327, 103, 114 (all authored rows) | M | yes: it is the design's grind |
| 4 | Thamasa's plain, groups 55-56 | `gen_wor_ebot` boot `wor-gogo-v1` | forms 331-334 (authored) | S | maybe: Ebot's door is the way |
| 5 | Chests of the dungeons the route walks | the arc's own leg | 39 prizes: Ancient Castle 6, Doma and the dream 8, Zozo 7, Owzer 2, Tzen house 6, Albrook/Nikeah/Figaro/Maranda/Narshe 10 | S to M each, see below | yes |
| 6 | The Zone Eater's belly | `gen_wor_belly` boot `wor-gau-v1` | forms 346-352 (7, authored, L43-44, 1,399-2,784 per member), 9 chests (Genji Armor, Zephyr Cape, Hero Ring, Thunder Shld, Magical Brsh, Tack Star...) | M | yes |
| 7 | Draw gaps in played dungeons | each dungeon's leg | 42 formations (section 4.3; Umaro's cave 6 of its 8, the Fanatics' Tower's four pay no XP) | M | meets them if it pauses |
| 8 | Monster boxes | the arc's leg | five boxes: Pm Stalker x4 (two, Tzen), Pugs x3 L99 (Umaro's cave), Master Pug L73 (Ancient Castle), KatanaSoul L61 (its basement); floor rows on the last two | L | only a strong party; a balance signal |
| 9 | WoB: stop spending WoR bits | WoB chain (the #350 item 8 pass) | 8 prizes (section 5.2) | S, regenerates the WoB chain | yes |
| 10 | The early-continent draw gaps | `wor-start-v1` to `wor-figaro-sweep-v1` | 19 formations of L5-29, 2-1,155 per member | S | seldom |

Unit 5 splits by arc: the Ancient Castle (`gen_wor_ancient`, 8 chests,
items Wing Edge, Doom Darts, Magicite, Ether, X-Potion, Punisher, two
boxes), Doma and the dream (`gen_wor_doma`/`gen_wor_dream`: Elixir,
Remedy, Fenix Down, Beads, X-Potion, Ether, then X-Potion and Ice Shld),
Zozo's two floors (`gen_wor_cyan`: RunningShoes, Chain Saw, Thief Glove,
Fire Knuckle...), Owzer's house (`gen_wor_owzer`: Moogle Suit, Relic Ring),
the Tzen house (`gen_wor_sabin`, timed), and 10 chests in Albrook, Nikeah,
Figaro, Maranda and Narshe (Sprint Shoes, Elixirs, Remedy, Revivify). The
boxes of the Tzen house and the Ancient Castle belong to unit 8.

## 9. Limits and what the instruments do

- The logs are the 35 files in `generator_logs.txt`: the WoR legs from
  `wor_island` to `wor_colosseum` (dated 2026-10-23, and the
  `wor_colosseum` qualification log of 2026-10-27) plus `tomb_zombie`.
  Four legs (`wor_island`, `wor_start`, `wor_south_figaro`, `wor_gogo`)
  have no outcome line (`log_inventory.txt`).
- The logs of `wor_island` to `wor_ancient` predate the re-cut of
  `wor-colosseum-v1` at `bdcc1e61` (2026-10-26). A re-cut reshuffles draws,
  so the fought set of a pool is a sample of what the route can deal. The
  zones at zero (groups 54 and 111) and the formations absent from all 352
  logs (`fought_proof.txt`, `all 0`) are the findings; a formation fought
  once in 35 logs may not be fought in the next run.
- `[tiles] map=1` lines include field coordinates recorded while the map
  id was still 1 (`xy=0:28`, `0:6`, `128:2` at the head of several legs),
  so tile counts are ceilings; the zones reported as zero are certain.
- `[outcome] battle $XXX` prints `$11E0`, stale for an event battle
  (SrBehemoth: `$1A8` for formation 452).
- `audit_chests.py` warns that `wor-colosseum-v1` has no capture in this
  tree; this audit reads the tracked SRAM instead. `chests_opened.txt`
  records 123 bits, the SRAM 120; the three missing are bits 37-39 (the
  WoB Kolts branch).
- `route_data.py`'s pool decode masks `0x3FF` and honours bit 15; no WoR
  group sets bit 15 (only group 112, the Floating Continent, does).
- Not audited: the Veldt's rage table, the Colosseum's wager ladder
  (`route-wor-colosseum.md`), shops and their stock, and which event
  scenes a WoR map reaches beyond the vetted list in section 6.

## 10. Evidence

Directory `build/attempts/wt/v038-wor-coverage/`. Scripts: `map_graph.py`,
`maptable.py`, `visited.py`, `veldt_bits.py`, `world1.py`, `evbat.py`,
`wor_gap.py`, `groups.py`, `isles.py`, `trip.py`, `near.py`, `units.py`, `chest_report.py`,
`shared_bits.py`, `proof.py`, `summary.py`. Outputs: `wor_gap.txt`
(areas, groups, formations, species), `groups.txt`, `isles.txt`,
`chests.txt`, `shared_bits.txt`, `units.txt`, `evbat.txt`,
`fought_proof.txt`, `log_inventory.txt`, `trips.txt`, `landable.txt`, `near.txt`,
`audit_chests.txt`, `summary.txt`.

### 10.1 The logs read (`log_inventory.txt`)

Outcome lines are `^\[ot6\].*\[outcome\] battle`; world tile lines are `^\[ot6\] \[tiles\] map=1 `; `grep -c` of each.

```
kefka_won.log outcomes=1 tilesWorld=0 mtime=2026-10-23
tomb_zombie.log outcomes=8 tilesWorld=0 mtime=2026-10-23
wor_ancient.log outcomes=10 tilesWorld=10 mtime=2026-10-23
wor_belly.log outcomes=1 tilesWorld=3 mtime=2026-10-23
wor_cyan.log outcomes=44 tilesWorld=8 mtime=2026-10-23
wor_doma.log outcomes=2 tilesWorld=5 mtime=2026-10-23
wor_dream.log outcomes=9 tilesWorld=4 mtime=2026-10-23
wor_ebot.log outcomes=11 tilesWorld=7 mtime=2026-10-23
wor_edgar.log outcomes=25 tilesWorld=7 mtime=2026-10-23
wor_falcon.log outcomes=4 tilesWorld=7 mtime=2026-10-23
wor_figaro_sweep.log outcomes=11 tilesWorld=7 mtime=2026-10-23
wor_gau.log outcomes=2 tilesWorld=9 mtime=2026-10-23
wor_gogo.log outcomes=0 tilesWorld=7 mtime=2026-10-23
wor_island.log outcomes=0 tilesWorld=5 mtime=2026-10-23
wor_kohlingen.log outcomes=2 tilesWorld=8 mtime=2026-10-23
wor_landing.log outcomes=9 tilesWorld=1 mtime=2026-10-23
wor_locke.log outcomes=5 tilesWorld=8 mtime=2026-10-23
wor_narshe.log outcomes=14 tilesWorld=4 mtime=2026-10-23
wor_nikeah.log outcomes=6 tilesWorld=5 mtime=2026-10-23
wor_opera.log outcomes=5 tilesWorld=13 mtime=2026-10-23
wor_owzer.log outcomes=6 tilesWorld=3 mtime=2026-10-23
wor_phoenix.log outcomes=10 tilesWorld=3 mtime=2026-10-23
wor_ragnarok.log outcomes=6 tilesWorld=6 mtime=2026-10-23
wor_relm.log outcomes=55 tilesWorld=23 mtime=2026-10-23
wor_sabin.log outcomes=3 tilesWorld=5 mtime=2026-10-23
wor_south_figaro.log outcomes=0 tilesWorld=6 mtime=2026-10-23
wor_start.log outcomes=0 tilesWorld=6 mtime=2026-10-23
wor_storm.log outcomes=8 tilesWorld=7 mtime=2026-10-23
wor_terra.log outcomes=4 tilesWorld=7 mtime=2026-10-23
wor_tomb.log outcomes=6 tilesWorld=4 mtime=2026-10-23
wor_tower.log outcomes=20 tilesWorld=5 mtime=2026-10-23
wor_tritoch.log outcomes=12 tilesWorld=6 mtime=2026-10-23
wor_tzen_door.log outcomes=13 tilesWorld=6 mtime=2026-10-23
wor_veldt.log outcomes=9 tilesWorld=6 mtime=2026-10-23
wor_colosseum.log outcomes=9 tilesWorld=8 mtime=2026-10-27
```

### 10.2 The tile trace (`visited.json`)

The head of `wor_tzen_door.log`, showing the field coordinates under map=1:

```
[ot6] [tiles] map=1 n=1 xy=0:28
[ot6] [tiles] map=1 n=55 xy=0:0,0:108,0:120,0:128,0:18,0:2,0:212,0:28,0:6,0:98,121:0,128:120,128:2,140:204,140:205,140:206,140:207,141:204,141:207,141:208,141:209,142:204,143:204,144:204,145:204,145:205,145:206,145:207,1
```

219 `[tiles] map=1` lines across the 35 logs: `grep -h "^\[ot6\] \[tiles\] map=1 " $(cat generator_logs.txt) | wc -l` = 219. `visited.json` holds 829 distinct world tiles; 622 of them are battle tiles (`summary.txt`).

### 10.3 Unfought formations named in the units (`fought_proof.txt`)

Outcome lines in the 35 WoR logs | in all 352 generator logs plus the colosseum qualification log:

```
form 103 ($067) Crawler: wor 0 | all 0
form 114 ($072) Crawler+Crawler+Crawler+Crawler: wor 0 | all 0
form 211 ($0D3) Pm Stalker+Pm Stalker+Pm Stalker+Pm Stalker: wor 0 | all 0
form 221 ($0DD) Cactrot: wor 0 | all 0
form 235 ($0EB) Pugs+Pugs+Pugs: wor 0 | all 0
form 237 ($0ED) Hoover: wor 0 | all 0
form 253 ($0FD) Pug: wor 0 | all 0
form 255 ($0FF) Kiwok+Ceritops: wor 0 | all 0
form 257 ($101) Ceritops+Ceritops+Ceritops: wor 0 | all 0
form 258 ($102) Anemone+Anemone+Tomb Thumb: wor 0 | all 0
form 259 ($103) Anemone+Anemone+Anemone+Anemone: wor 0 | all 0
form 260 ($104) Ceritops+Tomb Thumb+Tomb Thumb: wor 0 | all 0
form 320 ($140) Tyranosaur+Tyranosaur: wor 0 | all 0
form 321 ($141) Tyranosaur: wor 0 | all 0
form 322 ($142) Brachosaur: wor 0 | all 0
form 323 ($143) Mantodea+Sprinter+Spek Tor+Spek Tor: wor 0 | all 0
form 324 ($144) Reach Frog+Reach Frog+Reach Frog+Reach Frog: wor 0 | all 0
form 325 ($145) Mantodea+Mantodea: wor 0 | all 0
form 327 ($147) TumbleWeed+TumbleWeed+TumbleWeed+TumbleWeed: wor 0 | all 0
form 331 ($14B) Harpy: wor 0 | all 0
form 332 ($14C) Harpy+Prussian: wor 0 | all 0
form 333 ($14D) Prussian+GloomShell: wor 0 | all 0
form 334 ($14E) GloomShell+GloomShell+GloomShell: wor 0 | all 0
form 346 ($15A) Ogor+Ogor: wor 0 | all 0
form 347 ($15B) Covert+Ogor: wor 0 | all 0
form 348 ($15C) Wart Puck+Wart Puck: wor 0 | all 0
form 349 ($15D) Karkass+Karkass: wor 0 | all 0
form 350 ($15E) Tap Dancer+Covert+Covert: wor 0 | all 0
form 351 ($15F) Tap Dancer+Woolly: wor 0 | all 0
form 352 ($160) Woolly+Woolly+Karkass+Karkass: wor 0 | all 0
form 465 ($1D1) KatanaSoul: wor 0 | all 0
form 483 ($1E3) Master Pug: wor 0 | all 0
```

The formations of unit 8 are monster boxes, which print no outcome line unless opened; 235, 483, 465 and 211 are absent from every log:

```
form 211 ($0D3) Pm Stalker+Pm Stalker+Pm Stalker+Pm Stalker: wor 0 | all 0
form 235 ($0EB) Pugs+Pugs+Pugs: wor 0 | all 0
form 465 ($1D1) KatanaSoul: wor 0 | all 0
form 483 ($1E3) Master Pug: wor 0 | all 0
```

### 10.4 Fought formations quoted for the named examples

First outcome line of formations the audit calls fought and the units build on (`fought_proof.txt`):

```
form 195: wor_tzen_door.log: [ot6] [worldNavTo] [outcome] battle $0C3 WON after 2776 ticks: killed s0:$0D5; escaped none; 0 of 1 seated fled (Run, Warp); random reward due 1560 a member (char 6 +1560 (due 1560)): paid as due
form 202: wor_nikeah.log: [ot6] [worldNavTo] [outcome] battle $0CA WON after 1143 ticks: killed s1:$0CA s2:$0E6; escaped none; 0 of 2 seated fled (Run, Warp); random reward due 557 a member (char 6 +557 (due 557), char 5 +557 (due 557)): paid as due
form 204: wor_tzen_door.log: [ot6] [worldNavTo] [outcome] battle $0CC WON after 3482 ticks: killed s0:$0E6 s1:$07C s2:$098; escaped none; 0 of 1 seated fled (Run, Warp); random reward due 1610 a member (char 6 +1610 (due 1610)): paid as due
form 236: wor_ragnarok.log: [ot6] [worldNavTo] [outcome] battle $0EC WON after 1121 ticks: killed s0:$089; escaped none; 0 of 4 seated fled (Run, Warp); random reward due 224 a member (char 1 +224 (due 224), char 0 +224 (due 224), char 6 +224 (due 224), char
form 241: wor_ancient.log: [ot6] [worldNavTo] [outcome] battle $0F1 WON after 2505 ticks: killed s2:$0A7 s3:$0DB s4:$0DB s5:$0A7; escaped none; 0 of 4 seated fled (Run, Warp); random reward due 574 a member (char 6 +574 (due 574), char 8 +574 (due 574), cha
form 319: wor_relm.log: [ot6] [worldNavTo] [outcome] battle $13F WON after 4660 ticks: killed s2:$05B s3:$05B s4:$05B; escaped none; 0 of 4 seated fled (Run, Warp); random reward due 2184 a member (char 0 +2184 (due 2184), char 6 +2184 (due 2184), char 8
form 326: wor_relm.log: [ot6] [worldNavTo] [outcome] battle $146 WON after 6422 ticks: killed s0:$099 s1:$099 s2:$03B; escaped none; 0 of 4 seated fled (Run, Warp); random reward due 3175 a member (char 0 +3175 (due 3175), char 6 +3175 (due 3175), char 8
form 328: wor_gau.log: [ot6] [worldNavTo] [outcome] battle $148 WON after 3435 ticks: killed s0:$087 s1:$087 s2:$0B0 s3:$0B0; escaped none; 0 of 4 seated fled (Run, Warp); random reward due 3649 a member (char 5 +3649 (due 3649), char 11 +3649 (due 3649
form 353: wor_belly.log: [ot6] [navTo] [outcome] battle $161 WON after 2735 ticks: killed s0:$07D s2:$068; escaped none; 1 of 4 seated fled (Run, Warp); random reward due 2118 a member (char 0 +0 (due 0), char 6 +2118 (due 2118), char 8 +2118 (due 2118), 
form 454: wor_edgar.log: [ot6] [advanceStory] [outcome] battle $1C6 WON after 11831 ticks: killed s0:$13E s1:$13D s2:$13C s3:$11B; escaped none; 0 of 3 seated fled (Run, Warp); event reward due 0 a member (char 6 +0 (due 0), char 5 +0 (due 0), char 4 +0 (
form 455: wor_falcon.log: [ot6] [advanceStory] [outcome] battle $1C7 WON after 6883 ticks: killed s0:$11C; escaped none; 0 of 4 seated fled (Run, Warp); event reward due 0 a member (char 6 +0 (due 0), char 5 +0 (due 0), char 4 +0 (due 0), char 9 +0 (due 0)
form 463: wor_opera.log: [ot6] [doom] [outcome] battle $1CF WON after 3656 ticks: killed none; escaped s0:$11D; 0 of 4 seated fled (Run, Warp); event reward due 0 a member (char 6 +0 (due 0), char 8 +0 (due 0), char 12 +0 (due 0), char 7 +0 (due 0)): paid
form 464: wor_ebot.log: [ot6] [advanceStory] [outcome] battle $1D0 WON after 7014 ticks: killed s0:$123 s2:$126; escaped none; 0 of 4 seated fled (Run, Warp); event reward due 0 a member (char 7 +0 (due 0), char 8 +0 (due 0), char 12 +0 (due 0), char 0 +
```

Doom Gaze, `wor_opera.log`:

```
[ot6note] 32385 [doom] [outcome] battle $1CF WON after 3656 ticks: killed none; escaped s0:$11D; 0 of 4 seated fled (Run, Warp); event reward due 0 a member (char 6 +0 (due 0), char 8 +0 (due 0), char 12 +0 (du
[ot6] [doom] [outcome] battle $1CF WON after 3656 ticks: killed none; escaped s0:$11D; 0 of 4 seated fled (Run, Warp); event reward due 0 a member (char 6 +0 (due 0), char 8 +0 (due 0), char 12 +0 (due 0), char
```

SrBehemoth, `wor_gau.log` (formation 452 prints `$1A8`; `killed s0:$119` is its species):

```
[ot6note] 9331 [advanceStory] [outcome] battle $1A8 WON after 7177 ticks: killed s0:$119; escaped none; 0 of 4 seated fled (Run, Warp); event reward due 0 a member (char 0 +0 (due 0), char 6 +0 (due 0), char 8 
[ot6] [advanceStory] [outcome] battle $1A8 WON after 7177 ticks: killed s0:$119; escaped none; 0 of 4 seated fled (Run, Warp); event reward due 0 a member (char 0 +0 (due 0), char 6 +0 (due 0), char 8 +0 (due 0
```

The Zone Eater, `wor_belly.log`:

```
[ot6] ok: the island until the Zone Eater engulfs the party: done within 12 battles = true
```

The party the colosseum leg saves, `wor_colosseum.log`:

```
[ot6note] 55093 wor_colosseum generated: SHADOW L41, CELES L52, CYAN L41 and TERRA L53 beside the Falcon by Maranda, world (69,183), saved in slot 3
[ot6] wor_colosseum generated: SHADOW L41, CELES L52, CYAN L41 and TERRA L53 beside the Falcon by Maranda, world (69,183), saved in slot 3
```

The legs with no battle, `wor_south_figaro.log`:

```
[ot6note] 26573 [wor] the stretch: no battles (Nikeah, the ship and South Figaro roll none); CELES L29 HP 1396/1396 MP 277/277 status1 $00; 
```

### 10.5 The ROM (`trips.txt`, `landable.txt`, `isles.txt`)


```
world 1: on-foot BFS (178,46) -> (195,50): 21 steps (world_2_tilemap.dat, WorldTileProp bit $10)
  8 steps: sector (5,1) bg 4: WorldBattleGroup[308] = group 52; rate code 0 ($00C0/step x Ot6DangerMulW -> $0060; mean 33.6 steps)
  5 steps: sector (5,1) bg 5: WorldBattleGroup[311] = group 53; rate code 0 ($00C0/step x Ot6DangerMulW -> $0060; mean 33.6 steps)
  4 steps: sector (6,1) bg 4: WorldBattleGroup[312] = group 52; rate code 0 ($00C0/step x Ot6DangerMulW -> $0060; mean 33.6 steps)
  4 steps: sector (6,1) bg 1: WorldBattleGroup[313] = group 54; rate code 0 ($00C0/step x Ot6DangerMulW -> $0060; mean 33.6 steps)
  path: 178,46 179,46 180,46 181,46 182,46 183,46 184,46 185,46 186,46 187,46 188,46 189,46 190,46 191,46 192,46 193,46 194,46 195,46 195,47 195,48 195,49 195,50
world 1: on-foot BFS (69,185) -> (66,189): 7 steps (world_2_tilemap.dat, WorldTileProp bit $10)
  2 steps: sector (2,5) bg 5: WorldBattleGroup[427] = group 49; rate code 0 ($00C0/step x Ot6DangerMulW -> $0060; mean 33.6 steps)
  5 steps: sector (2,5) bg 2: WorldBattleGroup[426] = group 111; rate code 0 ($00C0/step x Ot6DangerMulW -> $0060; mean 33.6 steps)
  path: 69,185 69,186 69,187 69,188 69,189 68,189 67,189 66,189
```

The pools and species, `route_data.py pool group 54` and `pool group 111`:

```
  slot 0: 80/256 word $0141
    formation 321: Tyranosaur $027 x1; XP 8800 (x2 as a random, Ot6RewardMulW); may roll back/side
  slot 1: 80/256 word $0140
    formation 320: Tyranosaur $027 x2; XP 17600 (x2 as a random, Ot6RewardMulW); may roll pincer
  slot 2: 80/256 word $0141
    formation 321: Tyranosaur $027 x1; XP 8800 (x2 as a random, Ot6RewardMulW); may roll back/side
  slot 3: 16/256 word $0142
    formation 322: Brachosaur $026 x1; XP 14396 (x2 as a random, Ot6RewardMulW); may roll back/side
    $026 Brachosaur: L77 HP 46050 MP 51420 XP 14396 GP 0; spd 95 atk 55 mag 25 def 190 mdef 145 evade 70 mblock 50; weak ice absorb - null -; break floor 6 * pierce
    $027 Tyranosaur: L57 HP 12770 MP 420 XP 8800 GP 0; spd 55 atk 33 mag 16 def 125 mdef 160 evade 0 mblock 0; weak ice absorb - null -; break floor 6 * pierce
  slot 0: 80/256 word $00ED
    formation 237: Hoover $03E x1; XP 7524 (x2 as a random, Ot6RewardMulW); may roll back/side
  slot 1: 80/256 word $00DD
    formation 221: Cactrot $04C x1; XP 0 (x2 as a random, Ot6RewardMulW); may roll normal only
  slot 2: 80/256 word $00ED
    formation 237: Hoover $03E x1; XP 7524 (x2 as a random, Ot6RewardMulW); may roll back/side
  slot 3: 16/256 word $00DD
    formation 221: Cactrot $04C x1; XP 0 (x2 as a random, Ot6RewardMulW); may roll normal only
    $03E Hoover: L49 HP 12018 MP 10500 XP 7524 GP 10000; spd 54 atk 54 mag 22 def 130 mdef 60 evade 30 mblock 0; weak ice|water absorb - null -; break floor 6 * slash
    $04C Cactrot: L27 HP 3 MP 60000 XP 0 GP 10000; spd 39 atk 1 mag 50 def 255 mdef 255 evade 250 mblock 250; weak ice|water absorb - null -; break floor 5 * slash
```

Tiles of the zones (prop word, landable count):

```
group 54: 52 battle tiles, 0 of them Falcon-landable (props bit $02 clear); sample landable []; prop words ['0x166']
group 111: 33 battle tiles, 0 of them Falcon-landable (props bit $02 clear); sample landable []; prop words ['0x246']
group 50: 61 battle tiles, 0 of them Falcon-landable (props bit $02 clear); sample landable []; prop words ['0x166']
group 46: 99 battle tiles, 0 of them Falcon-landable (props bit $02 clear); sample landable []; prop words ['0x166']
group 35: 29 battle tiles, 0 of them Falcon-landable (props bit $02 clear); sample landable []; prop words ['0x166']
group 55: 95 battle tiles, 60 of them Falcon-landable (props bit $02 clear); sample landable [(248, 221), (251, 221), (252, 222), (251, 223)]; prop words ['0x166', '0x444', '0x446']
group 56: 146 battle tiles, 141 of them Falcon-landable (props bit $02 clear); sample landable [(249, 220), (250, 220), (247, 222), (247, 223)]; prop words ['0x544', '0x546']
```

Nearest Falcon landing (`near.txt`):

```
group 54: nearest Falcon landing tile (195, 46) is 1 steps from the zone (zone 52 tiles)
group 111: nearest Falcon landing tile (70, 186) is 1 steps from the zone (zone 33 tiles)
group 50: nearest Falcon landing tile (29, 146) is 1 steps from the zone (zone 61 tiles)
group 46: nearest Falcon landing tile (61, 35) is 1 steps from the zone (zone 99 tiles)
group 35: nearest Falcon landing tile (111, 163) is 1 steps from the zone (zone 29 tiles)
group 55: nearest Falcon landing tile (248, 221) is 0 steps from the zone (zone 95 tiles)
group 56: nearest Falcon landing tile (249, 220) is 0 steps from the zone (zone 146 tiles)
```

Isles:

```
Kefka's Tower landing tiles (prop $8000, landable): 3 e.g. [(137, 196), (137, 197), (137, 198)]
Phoenix Cave landing tiles (prop $4000, landable): 4 e.g. [(117, 156), (118, 156), (117, 157), (118, 157)]
```

```
  98 doorless components
```

### 10.6 Chests (`chests.txt`, `shared_bits.txt`, `summary.txt`)


```
# WoR-area chest records 187; UNOPENED 87, opened in WoB 37, opened(WoR) 63
# SRAM bits set 120, fc_alcove bits 58, chests_opened.txt 123; in record not SRAM: [37, 38, 39]; in SRAM not record: []
```

```
# bit: records (map (x,y) prize) | opened by the end of the WoB (fc_alcove) | opened at wor-colosseum-v1
bit  11: map 38 (65,28) Pod Bracelet; map 50 (65,28) Fenix Down | WoB OPEN | end OPEN
bit  12: map 38 (52,33) Elixir; map 50 (52,33) Sleeping Bag | WoB OPEN | end OPEN
bit  13: map 44 (98,53) Ribbon; map 52 (98,53) Rune Edge | WoB closed | end OPEN
bit  18: map 68 (3,18) X-Potion; map 69 (3,18) X-Potion; map 72 (3,18) Fenix Down | WoB closed | end OPEN
bit  19: map 70 (52,14) Thunder Rod; map 73 (52,14) Tincture; map 90 (52,14) Hero Ring | WoB closed | end OPEN
bit  21: map 74 (32,16) X-Potion; map 75 (32,16) Tonic | WoB OPEN | end OPEN
bit  22: map 74 (15,45) Tent; map 75 (15,45) Antidote | WoB OPEN | end OPEN
bit  23: map 74 (15,47) Remedy; map 75 (15,47) Eyedrop | WoB OPEN | end OPEN
bit  24: map 74 (6,31) Revivify; map 75 (6,31) Tonic | WoB OPEN | end OPEN
bit  25: map 74 (14,28) Tent; map 75 (14,28) Green Cherry | WoB OPEN | end OPEN
bit  97: map 68 (33,23) Ether; map 69 (33,23) Tincture; map 72 (33,23) Tincture | WoB closed | end OPEN
bit 230: map 74 (2,43) Elixir; map 75 (2,43) Soft | WoB closed | end OPEN
bit 231: map 74 (11,23) Fenix Down; map 75 (11,23) Warp Stone | WoB OPEN | end OPEN
# 13 bits with differing prizes that a WoR-reachable map holds
```

```
world battle tiles (non-Veldt) 11467; route stood on 622 of them; Veldt tiles 1024 stood 3
world-pool formations 54: fought 20, never 34
world groups with no formation ever fought: ['0', '29', '33', '35', '46', '50', '54', '55', '56', '111']
world groups with some but not all fought: ['37', '39', '42', '44', '45', '47', '49', '51', '52', '53']
world groups fully fought: ['30', '31', '32', '34', '36', '38', '40', '41', '43', '48']
field maps that roll (outside Kefka's Tower) 58 (58 visited by a WoR leg); their formations 118, fought 69
WoR map ids listed (outside Kefka's Tower) 190; visited by a WoR leg 147
distinct unopened non-empty chest bits outside Kefka's Tower: 53; monster boxes among them 5
Kefka's Tower distinct unopened non-empty bits 16
empty ($00) chest records (distinct bits) 10
distinct bits opened by WoR legs 62; already opened in the WoB 30
```

### 10.7 Commands

From the worktree root, in order: `ninja build/ot6.sfc`; in the evidence directory `map_graph.py` (DEPTH=0,1,2 into `graph_d*.json`), `visited.py`, `maptable.py`, `veldt_bits.py`, `world1.py`, `evbat.py`, `wor_gap.py`, `groups.py`, `isles.py`, `trip.py`, `units.py`, `chest_report.py`, `shared_bits.py`, `proof.py`, `summary.py`; `python3 tools/audit_chests.py` (`audit_chests.txt`); `python3 tools/route_data.py world-path 1 178 46 195 50`, `world-path 1 69 185 66 189`, `species`, `pool group`. No emulator was started: every number is read from the ROM, the tracked SRAM, a seeded savestate or an existing play log.

