# World of Ruin: Tzen to Edgar (Nikeah, South Figaro, Figaro Castle)

The route from the first save after Sabin joins (`wor-sabin-v1`: CELES and
SABIN on the World of Ruin map outside Tzen, (131,179)) to Edgar joining in
Figaro Castle's engine room, and on to the first save after he joins. It is
planned from the game's own data, like
[route-wor-sabin.md](route-wor-sabin.md), whose shape it follows: findings,
the start state, the legs, the pools, the party, the break data, the save
points and checkpoint cuts, the risks, then one "played" section per leg as
it is driven.

Line numbers are into `ff6/src/event/event_main.asm` unless a path is given.
Decodes come from `tools/route_data.py` and the small analysis scripts kept
with their output under `build/attempts/wt/wor-edgar/route/` (the scripts
run from a tree root; `decode.sh` regenerates every file; ROM
`615ed3641d4f`, main `5b043705`). The labels are route-wor-sabin's:
**verify-on-arrival** marks an offline decode that holds unless the data
moved (every field step count here: the offline model has no NPCs and no
map-init `mod_bg_tiles`), **UNVERIFIED** marks a claim that needs a live
read, and **estimate** marks a number the driving will replace with a
measurement.

---

## 0. Findings

1. **The story runs through four places, in order, and each gate is a
   switch the previous one sets** (section 2):
   Nikeah's cafe (four thieves, `$00A7-$00AA` -> `$0376`), Gerad in
   Nikeah's street (three talks, `$01F0-$01F3` -> `$0378`), the ship
   (`$0378` -> `$00AC`, and it lands the party in South Figaro), Gerad in
   South Figaro's inn (`$037E` -> `$037F`, `$0398`), the Figaro cave's
   turtle (`$037F` -> `$0383`), Gerad in the castle's basement (`$0383`),
   and Edgar in the engine room: `char_party EDGAR` (`:15935`) and then
   **the Tentacles, an event battle whose loss is a game over**
   (`battle 84, TENTACLES` `:15937`, `_ca5ea9`: `call GameOver` unless
   won). The castle's engineer then takes it to the surface (`_ca69fd`).
2. **The walk from Tzen to Nikeah is 206 steps and crosses the Black
   Drgn's desert.** World group 40 deals only formation 195, a lone Black
   Drgn, from all four slots, and **no on-foot path to Nikeah avoids it**
   (`walks.txt`: `[off group 40]: no path`). The shortest walk puts 8
   steps on it, which the danger-counter model gives 0.24 of its 5.65
   expected battles: about one walk in five meets the Black Drgn. This
   is #300's fight (the desert beside Tzen, never played) on the natural
   route, and the party that meets it is CELES + SABIN.
3. **Every species on the stretch is new, World of Ruin only, and rides
   the generated floor** at 5-6 shields (`design_keys.txt`), except the
   Black Drgn (authored 4 slash, route-wor-sabin 8.2). Seventeen species
   and the four Tentacles need designed rows (section 8); none appears in
   any other pool or event group, so no World of Balance row moves.
4. **Zombie and Muddle are the stretch's statuses.** North of Tzen the
   Bloompire's Special is Energy Sap (Zombie) and the Black Drgn's is
   BonePowder (Zombie); the Lizard Imps. In the Figaro cave every body
   muddles: Humpty (Hug), Cruller
   (BrainStorm), NeckHunter (Mad Sickle), Dante (L.3 Muddle as a counter
   to Magic -- and both members are **L27, a multiple of three**), Drop
   (Mad Signal).
5. **The Tentacles seize.** Each Tentacle's Entwine Slows, a Slowed member
   is Seized (`TargetEffect_2e`, `battle_main.asm` @3cce: the member's menu
   is shut off and the Tentacle drains HP each turn), and it is Discarded
   30 counts later or when that Tentacle dies (`TargetEffect_44`). The
   harness has no Seize handling today (section 9).
6. **No shop on the stretch sells Tonics.** Nikeah (58) and South Figaro
   (63) sell Potions; field care stays on Potions, as on the Sabin
   stretch. Figaro Castle's shops refuse a party with SABIN or EDGAR in it
   ("I can't take money from the King!", `_ca67de`/`_ca67e2`).
7. **Edgar joins with nothing equipped, and the game dresses him from the
   bag** (`opt_equip EDGAR` `:15936`) at `max(28, the party's average)`
   (`norm_lvl EDGAR` `:15930`), full HP and MP, straight into the
   Tentacles as the third member.
8. **The checkpoints are world-map saves.** No map on the stretch has a
   save point (`maps.txt`; South Figaro's two, maps 84 and 88, are in the
   World of Balance's escape passage). A person saves on the world map at
   the natural pauses: before Nikeah, outside South Figaro, and outside
   the surfaced castle (section 7).

---

## 1. The start state (`wor-sabin-v1`)

From route-wor-sabin 11 and its cold Continue
(`build/attempts/wt/wor-sabin/runs/continue_wor_sabin_v1.log`):

```
contract wor-sabin-v1 (entry): all 25 fields hold
[continue] world 1 at (131,179): CELES L27 HP 1211/1211 MP 251/251 row back esper+kit 06 0E 0F 76 8F D1 B5;
  SABIN L27 HP 1225/1225 MP 239/239 row back esper+kit 01 57 57 77 90 D1 D5;
  tonic=5 potion=47 fenix=27 remedy=5 gil=203243
```

The whole bag and the roster, from the graph run's own state after the save
(`party_wor_sabin.txt`, `route_data.py party
build/attempts/wt/wor-sabin/review-fixes/var/art_k0_s0/wor_sabin.mss`,
the K=0 shift-0 run whose battery is the checkpoint's):

| member | level | kit | commands |
|---|---|---|---|
| CELES | L27, xp 61,090 | MADUIN; Blizzard + ThunderBlade (Genji Glove), Gold Helmet, Gold Armor, Jewel Ring | Fight, Runic, Magic (Ice, Ice 2, Scan, Safe, Imp, Cure, Antdot; Fire/Ice/Bolt from Maduin), Item |
| SABIN | L27, xp 55,288 | IFRIT; Fire Knuckle x2 (Genji Glove), Tiger Mask, Power Sash, Black Belt | Fight, Blitz (Pummel, AuraBolt, Suplex, Fire Dance, Mantra: `BlitzLevelTbl` 1/6/10/15/23; Air Blade at 30), Magic, Item |
| EDGAR (not in the party) | L28, xp 61,764 | nothing | Fight, Tools, Magic, Item |

Bag highlights: Potion 47, Fenix Down 27, Remedy 5, Tonic 5, Soft 18,
Green Cherry 5, Antidote 4, Revivify 2, Elixir 5, X-Potion 3, Tent 10,
Echo Screen 1; relics Jewel Ring x2, Star Pendant x4, Peace Ring,
Czarina Ring, Back Guard, Memento Ring; Edgar's Tools AutoCrossbow,
NoiseBlaster, Bio Blaster; weapons Break Blade, Mithril Pike, RegalCutlass,
MithrilBlade x2, MithrilKnife x10; 203,243 GP. Espers: the twelve of the
World of Balance plus SERAPHIM.

The switches the stretch reads, as the raft's landing left them
(`:13002-13013`): `$0374=1` (the thieves in Nikeah's cafe), `$037A=1`
(the thieves in South Figaro), `$0381=0 $0382=1` (the castle basement's
fallen guards), `$0397=1`, `$02B7=1`.

---

## 2. The legs and the story's gates

### 2.1 The whole stretch

| # | leg | from -> to | steps | pools | gate |
|---|---|---|---|---|---|
| 1 | Tzen -> Nikeah | world (131,179) -> (148,76) -> Nikeah (146/147,76) | 206 | world 31, 34, 37, 38, 39, **40** | none |
| 2 | Nikeah: the thieves | map 169 -> cafe 172: four thieves | verify-on-arrival | none (towns) | `$00A7-$00AA` -> `$0376=1` |
| 3 | Nikeah: Gerad | 169, NPC_11 at (20,46), three talks | — | none | `$01F0..$01F3` -> `$0378=1` |
| 4 | the ship | 169 (13,63) -> 187 (17,2) -> trigger (17,4) | 2 | none | `$0378` -> `$00AC=1`; lands at 91 (14,12), parent world (113,95) |
| 5 | South Figaro | 91 -> 74 (19,54) -> inn 76, Gerad at (88,11) | 22 + 57 | none | `$037E` -> `$037F=1 $0398=1` |
| 6 | out to the cave | world (113,95) -> (106,98) | 14 | world 41, 43 | none |
| 7 | the Figaro cave | map 68 -> 90 (the turtle) -> 92 -> 53 | 70 + 12 + 28 + 54 | field 138, 140, 137, 137 | `$037F` -> `$0383=1` (the turtle, `_ca76e1`) |
| 8 | the castle's basements | 53 -> 61 (Gerad) -> 62 -> 64 (engine room) | verify-on-arrival | field 137, 139 (63: 138) | `$0383` (`_ca6a2c`) |
| 9 | Edgar and the Tentacles | 64, NPC_11 at (29,16) | 3 | event group 84 | `char_party EDGAR`; `battle 84` (a loss is GameOver) |
| 10 | the surface | 64 -> 62 -> 61, the engineer (5,35) | verify-on-arrival | field 137, 139 | `$00C6=1` -> `_ca69fd`: world (81,84), `$00C7=1 $0106=1` |
| 11 | out to save | the castle -> world (81,85) | verify-on-arrival | world 44 | `$0106=1` arms the castle's world trigger (`_ca5f0b`) |

### 2.2 Tzen -> Nikeah (world)

On foot, `walks.txt` (`route_data.py world-path 1 131 179 146 76`, and the
same BFS with group 40 avoided):

```
wor-sabin-v1 (131,179) -> Nikeah door (146,76) [shortest]: 206 steps; steps by group: 31: 24, 34: 20, 37: 18, 38: 74, 39: 58, 40: 8, None: 4
  budget: mean 5.65 battles; P(1)=0.000 P(2)=0.001 P(3)=0.028 P(4)=0.150 P(5)=0.297 P(6)=0.288 P(7)=0.161 P(8)=0.058 P(9)=0.014 P(10)=0.003
    battles expected by group: 31: 0.43, 34: 0.52, 37: 0.54, 38: 2.21, 39: 1.73, 40: 0.24
    group-40 tiles on the path: [(163, 106), (163, 105), (163, 104), (163, 103), (163, 102), (163, 101), (157, 96), (156, 87)]
wor-sabin-v1 (131,179) -> Nikeah door (146,76) [off group 40]: no path
```

The walk leaves the plains (31/34, route-wor-sabin 4.1) at the bend east of
Tzen, crosses the grass and plains north-east (37, 38) and the plains north
(39), and three strips of desert (40): six steps down x=163 and single
steps at (157,96) and (156,87). The BFS approaches the door from the east,
`... 148,77 148,76 147,76`; (148,76) is walkable grass (group 37) one step
from the door, the tile the leg saves on (section 7).

The continent's component (`components.txt`: 3,664 tiles from (131,179))
also holds Mobliz (237,135), two chocobo stables ((229,156), (112,165)) and
Albrook. **Mobliz** is v0.26's (Terra, Phunbaba); this route does not go
in. The stables are optional: a ridden chocobo draws no battles. The 38
tiles of world group 0 (WoB Leafer/Dark Wind, sector (5,6)) are off every
route here, as on the Sabin stretch.

### 2.3 Nikeah (map 169; no random battles)

Map 169 is the World of Balance's Nikeah with `$00A4` branches
(`maps.txt`). Everything the stop offers:

| what | where | event |
|---|---|---|
| weapon shop 56 | NPC_2 (17,42) | `_ca8f23` `:21595` |
| armor shop 57 | NPC_4 (26,47) | `_ca8f3e` |
| item shop 58 | NPC_1 (24,39) | `_ca8f4a` |
| relic shop 59 | NPC_3 (23,52) | `_ca8f2f` |
| inn, 150 GP | door (19,31) -> 171, keeper (46,48) | `_ca8ee5` `:21563` (the dialog says 150; `take_gil 150`) |
| chest | inn 171 (57,37): Elixir | bit `$03E` |
| chocobo stable | door (23,20) -> 173 | `_ca8fb4` |

**The thieves** (`:22022-22072`): the cafe (door (16,54) -> 172 (26,37))
holds four BANDIT NPCs shown by `$0374`. Each talk sets one switch
(`_ca9189` `$00A7`, `_ca9193` `$00A8`, `_ca919d` `$00A9`, `_ca91a7`
`$00AA`) and calls `_ca91b1`, which returns until all four are set; then
"All right, let's go!", and `$0374=0 $0375=1 $0376=1 $0377=1`: the thieves
leave the cafe, Gerad appears in the street (NPC_11 at (20,46), `$0376`),
and four thieves stand on the ship (`$0377`).

**Gerad** (`_ca91da` `:22073`): the first talk ("you're EDGAR, aren't
you?!") sets `$01F0` and walks him away (`$01F1`); the second (`_ca9204`)
walks him further (`$01F2`, then `$01F3`); the third (`_ca921a` `:22112`)
plays "Only EDGAR would say, 'my lady'", hides him, and sets `$0376=0
$0378=1`. The NPC moves between talks, so each talk is a new approach.
`$01F0`-`$01F3` are the map's scratch switches (cleared on map load
elsewhere in the script, UNVERIFIED): a talk sequence interrupted by
leaving the map may restart.

**The ship** (map 187, the long exit (13,63) -> 187 (17,2)): the ferryman
NPC_1 (`_ca8cbb` `:21392`) says "This ship belongs to the Crimson Robbers"
until `$00AC`. The trigger (17,4), two steps in, runs `_ca9282`
(`:22183`) once `$0378=1` and `$00AC=0`: Gerad and "you know how to get into
Figaro Castle", the ship's world ride (`_ca92ca` `:22240`: `load_map 1,
{142,76}` then west and south), and `load_map 91, {14,12}` with
`set_parent_map 1, {113, 95}, UP`: the party lands in South Figaro's dock
house with the world tile outside South Figaro as its parent. It sets
`$00AC=1`, `$037E=1`. From then on the ferryman sails either way on a
Yes/No (`_ca8ce4` -> `_ca92ca`; from South Figaro's dock `_ca77d7`
`:18192` -> `_ca931c`), so the two continents stay joined.

### 2.4 South Figaro (map 74; no random battles)

The dock house 91's exit triggers (7..9,1) load the World of Ruin's South
Figaro, map 74 (19,54) (`_ca7f85` `:19361`). Map 74 is the town without
the Empire (the WoB town is map 75); its doors lead to the shared
interiors (76 inn, 77 arsenal, 78 cafe, 81 the rich man's house, 85 item
shop, 86 the other houses).

| what | where | event |
|---|---|---|
| weapon shop 60, armor 61 | arsenal 77 (103,9), (114,10) | `_ca7860`, `_ca786c` |
| relic shop 62 | inn 76 NPC_3 (51,9) | `_ca7878` |
| item shop 63 | 85 NPC_3 (106,52) | `_ca7884` |
| inn, 80 GP | 76 NPC_4 (81,17) | `_ca7894` `:18320` |
| chocobo stable | 74 (8,32) -> 80 | — |
| chests | 74: Fenix Down, X-Potion, Tent x2, Remedy, Revivify, Elixir, Fenix Down; 86: Tonic, Elixir | bits `$014-$019`, `$0E6`, `$0E7`, `$01E`, `$01F` (the `$01x` bits are shared with the World of Balance town, so some are already open) |

**Gerad** is upstairs in the inn (76 NPC_6 at (88,11), `$037E`), 57 steps
from the door by the same-map stairs (`town_paths.txt`). One talk
(`_ca808d` `:19496`): "Are you people STILL here?", "Boss, everything's
ready", and `$037E=0 $037A=0 $037F=1 $0398=1`: the thieves leave town
for the cave, and Siegfried appears at its mouth (`$0398`).

**The rich man's house and its basement** (81 -> 83 -> 84/87/89) are the
World of Balance's escape passage. The offline model reaches map 83 and
its door to 89 (`route_data.py field-path 83 7 5 32 18`: 32 steps) but not
across 84 or 89 (`NO PATH`: the WoB clock and switch mechanism). Map 87
(Commander, Vector Pup: WoB pool 65) and 89's chests (Hyper Wrist,
Ribbon, RunningShoes, X-Potion, Ether) are **UNVERIFIED** as reachable in
the World of Ruin. Leg 2 walks in and says what is open.

### 2.5 The Figaro cave (maps 68, 90, 92, 53)

The world entrance (106,98) -> map 68 (16,42), 14 steps from South
Figaro's door across groups 41 and 43. Map 68 is the WoR copy of the
cave to South Figaro (69/70 are the WoB ones, `maps.txt`):

- **68** (group 138): Siegfried at (14,36) (`$0398`, `_ca7775`: "I'll go
  in first and clear out all the monsters", `$0398=0 $0399=1`). The way on
  is (10,2) -> 90 (55,31), 70 steps; chests X-Potion (3,18), Ether
  (33,23).
- **90** (group 140): the arrival tile (55,31) is the turtle scene's
  trigger (`_ca76e1` `:18005`, gated on `$037F`): the thieves feed the
  turtle, "Presto! GERAD: Good job! I used to have a turtle!", and
  `$0123=1 $037F=0 $0383=1`. The crossing is the turtle itself: (47,29)
  **facing up with A held** moves the party up four tiles (`_ca76b3`
  `:17973`: `$01F0`, `$01B4`, `$01B0`), (47,25) facing down back
  (`_ca76ca`). That is the Sabin stretch's "face up and hold A"
  (`H.faceAndHoldA`). Chest (52,14): Hero Ring.
- **92** (group 137): (68,12) -> (47,11), 28 steps, to 53.
- **53** (group 137): Siegfried's trigger (32,44) (`_ca7782`, `$0399`:
  "On the hum, let's go!!!!", he runs off), and (21,56) -> the castle's
  basement 61 (35,37), 54 steps in all.

### 2.6 The castle's basements and the engine room (maps 61-66)

- **61** (no battles): (35,40) `_ca6a2c` `:15813` with `$0383`: "GERAD:
  You all right? You were almost a goner", `$026E=1 $0383=0`. The engineer
  NPC_6 at (6,33) (`_ca682f`) and his trigger (5,35) (`_ca69cd`
  `:15752`) run the surfacing once `$00C6=1`. (35,35) goes back to the cave
  (`_ca5f25`). The fallen guards say "I...it was awful" (`$0382`).
- **62** (group 137): basement 2; (8,6) -> the engine room 64 (29,20);
  (4,6) -> 66 (Regal Crown); (2,13)/(14,8)/(8,18) -> 63.
- **63** (group 138): basement 3, a side loop with Ether, X-Potion,
  Gravity Rod and Crystal Helm.
- **64** (group 139): the engine room. Ten Tentacle NPCs (`$03F0`), Edgar
  as "Gerad" at (29,16) (`$03F1`, event `_ca6a48` `:15832`), thieves
  (`$03F2`). `$03F0`-`$03F2` are set by the NPC switch defaults
  (`init_npc_switch.dat`; no event sets them) and cleared at the scene's
  end (`:16115-16117`).
- **65** (no battles): (29,5) of 64 -> 65 (68,16), the Soul Sabre chest,
  behind the tile the scene redraws (`mod_bg_tiles BG1, {29, 5}` in
  `_ca6a48`).

The offline model finds no path across 61 or 62 (`walks.txt`: the
basements' doors and bridges are drawn by map init), so every step count
here is **verify-on-arrival**.

### 2.7 Edgar and the Tentacles (`_ca6a48`)

```
event_main.asm:15930   norm_lvl EDGAR
               :15931   max_hp EDGAR / max_mp EDGAR / and_status EDGAR, NONE
               :15934   switch $02F4=1
               :15935   char_party EDGAR, 1
               :15936   opt_equip EDGAR
               :15937   battle 84, TENTACLES
               :15938   call _ca5ea9          ; if_b_switch $40 (won), else call GameOver
```

The party in the battle is CELES, SABIN and EDGAR. Nothing restores
CELES's or SABIN's HP or MP before it. `opt_equip` is the game's Optimum
from the bag: the bag at `wor-sabin-v1` gives him the Break Blade (117,
slash; the Mithril Pike is 70), a Mithril Shld, a Plumed Hat and the
Mithril Vest (**estimate**: the bag at the engine room decides). After the
win: the scene with the thieves ("Must have been eaten by that thing"),
EDGAR explains, and `$0381=1 $00C6=1 $0382=0 $0397=0`.

### 2.8 The surface

Back in 61, the engineer's trigger (5,35) with `$00C6=1` runs `_ca69fd`
(`:15783`): "Nonsense! It's been fixed! Next stop, the surface!", the
castle rises at world (81,84), and control returns in 61 (6,34) with the
parent world tile (81,85), `$0106=1 $00C7=1 $02B7=0`. From then on the
engineer offers "Go to Kohlingen?" (`_ca68e6`), which is v0.24's. The
castle's world trigger (81,85)/(82,85) (`_ca5f0b`) loads the castle (55)
while `$0106=1`.

---

## 3. The pools

Decoded by `route_data.py pool` (`pools.txt`). Slot odds 80/80/80/16 of
256; XP is vanilla and a random battle pays x2 (`Ot6RewardMulW`). Every
rate on the stretch is code 0 (world `$00C0`, field `$0070`, halved by
`Ot6DangerMulW`).

### 3.1 The Tzen continent north of Tzen

| group | terrain | p | formation | contents | XP |
|---|---|---|---|---|---|
| 37 | grass | 31.25 % | 216 | Bloompire x2 | 1020 |
| | | 31.25 % | 213 | Buffalax | 562 |
| | | 37.5 % | 215 | Bloompire x2, Lizard | 1317 |
| 38 | plain | 62.5 % | 214 | Buffalax, Delta Bug x2 | 1138 |
| | | 37.5 % | 217 | Delta Bug x4 | 1152 |
| 39 | plain (north) | 31.25 % | 219 | Buffalax, Lizard | 859 |
| | | 31.25 % | 218 | Bloompire x2, Delta Bug | 1308 |
| | | 37.5 % | 217 | Delta Bug x4 | 1152 |
| 40 | desert | 100 % | 195 | **Black Drgn** | 780 |

### 3.2 The South Figaro continent

| group | terrain | p | formation | contents | XP |
|---|---|---|---|---|---|
| 41 | grass by the town and cave | 100 % | 134 | Nohrabbit x3 | 0 |
| 42 | forest by the town | 62.5 % | 224 | Latimeria | 612 |
| | | 37.5 % | 225 | Latimeria, Nohrabbit x3 | 612 |
| 43 | plain | 100 % | 220 | Maliga x2, Nohrabbit x2 | 720 |
| 44 | desert (the castle's) | 31.25 % | 222 | Sand Horse x2 | 950 |
| | | 31.25 % | 223 | Sand Horse, Maliga x2 | 1195 |
| | | 37.5 % | 138 | Maliga x3 | 1080 |

### 3.3 The cave and the basements

| group | maps | p | formation | contents | XP |
|---|---|---|---|---|---|
| 137 | 92, 53, 62 | 31.25 % | 228 | Humpty x3 | 1263 |
| | | 31.25 % | 229 | Cruller, Humpty x2 | 1261 |
| | | 37.5 % | 231 | NeckHunter x2 | 1176 |
| 138 | 68, 63 | 62.5 % | 232 | NeckHunter, Cruller, Humpty x2 | 1849 |
| | | 37.5 % | 233 | Dante | 1150 |
| 139 | 64 | 31.25 % | 234 | Drop x3 | 1194 |
| | | 31.25 % | 233 | Dante | 1150 |
| | | 37.5 % | 230 | Humpty x4 | 1684 |
| 140 | 90 | 31.25 % | 231 | NeckHunter x2 | 1176 |
| | | 31.25 % | 233 | Dante | 1150 |
| | | 37.5 % | 230 | Humpty x4 | 1684 |
| event 84 | 64 | — | 454 | Tentacle `$13E`, `$13D`, `$13C`, `$11B` | 0 |

### 3.4 The encounter budgets

`walks.txt` (the draw byte modelled uniform: a pool-odds budget, not a
prediction for one save; the real draw is save data, `$1FA1-$1FA5`):

| leg | steps | mean battles | P(0) |
|---|---|---|---|
| Tzen -> Nikeah | 206 | 5.65 (0.24 of them the Black Drgn) | 0.000 |
| South Figaro -> the cave | 14 | 0.11 | 0.896 |
| cave 68, in -> 90 | 70 | 1.19 | 0.131 |
| cave 90, the turtle's banks | 12 + 1 | 0.04 | 0.958 |
| cave 92 | 28 | 0.26 | 0.744 |
| cave 53 | 21 + 33 | 0.15 + 0.36 | — |
| South Figaro -> the castle's tile (81,85) | 52 | 1.19 | 0.138 |

### 3.5 The species

`species.txt`, `ai.txt` (the scripts whole, with their lines in
`ai_script.asm`). "Today" is the row the ROM ships (the generated floor).

| id | name | L | HP | def/mdef | weak | absorb | the script | today |
|---|---|---|---|---|---|---|---|---|
| `$035` | Bloompire | 26 | **12** | **254/254** | fire | water | B; B/B/**Energy Sap (Zombie)**; Bio/Bio/B `:1910` | floor 5 slash |
| `$058` | Buffalax | 26 | 2252 | 100/150 | fire, water | — | B x4 then Riot (x1.5); **counter to Magic: Sun Bath** `:1923`; starts Poisoned | floor 5 slash |
| `$03C` | Lizard | 26 | 1280 | 102/153 | ice | poison | B/B/**Imp Glare**; B; B `:1897` | floor 5 slash |
| `$030` | Delta Bug | 26 | 612 | **220/5** | fire | — | B; B/B/Rush (x1.5); B/B/Mega Volt `:1884` | floor 5 pierce |
| `$0D5` | Black Drgn | 26 | 4000 | 102/20 | fire, holy | poison | B/B/Sand Storm; B/**BonePowder (Zombie)**/Sand Storm `:1710`; starts in Sap | **authored 4 slash** |
| `$0C3` | Nohrabbit | 26 | 75 | 100/100 | water | — | B/B/Carrot; B; **counter to Fight: Cure/Cure 2/Remedy on a random party member** `:1980`; Haste | floor 5 slash |
| `$0B9` | Latimeria | 27 | 1700 | 125/140 | bolt | — | Magnitude8 (earth, 100); Wind-up/Magnitude8 x2 `:1994` | floor 5 slash |
| `$097` | Maliga | 26 | 952 | 110/145 | ice, bolt, water | — | B; B/B/Scissors; **last one standing: Scissors x2 a turn** `:2005` | floor 5 slash |
| `$05F` | Sand Horse | 27 | 1025 | 135/155 | ice, water | — | Sand Storm; Clamp/Sand Storm; **last one standing: B/B/Clamp (x5)** `:2020` | floor 5 slash |
| `$049` | Humpty | 27 | 800 | 145/135 | fire, holy | poison | B/B; B/B/**Hug (Muddle)**; B `:2034` | floor 5 slash |
| `$04B` | Cruller | 28 | 1334 | 110/70, **evade 100** | fire, holy | poison | Fire 2 (runic)/B; B/B/Slimer (Slow); B/B/**BrainStorm (Muddle)** `:2047`; starts Dark + Poison | floor 5 slash |
| `$0A9` | NeckHunter | 28 | 1334 | 102/153 | poison | — | **Mad Sickle (Muddle)**/B; B; B; B `:2088`; Haste | floor 5 slash |
| `$0D7` | Dante | 28 | 1945 | 105/150 | poison | — | B/B/QuartzPike (x3); B; **counter to Magic: L.3 Muddle** `:2060`; speed 40 | floor 5 slash |
| `$08B` | Drop | 27 | 1000 | 100/150 | bolt, water | — | **Mad Signal (Muddle)** x2; **counter to Fight: Battle** `:2075`; starts in Sap | floor 5 slash |
| `$11B` | Tentacle | 31 | 7000 | 102/153 | ice, water | **fire** | Seize a Slowed member; Poison/Entwine (Slow)/Bio; Discard at 30 counts; counter: Battle `ai_script.asm:5384` | floor 5 slash |
| `$13C` | Tentacle | 32 | 6000 | 102/153 | fire | **ice**, water | the same shape `:6575` | floor 6 slash |
| `$13D` | Tentacle | 33 | 5000 | 102/153 | — | **bolt**, water | the same; counter: Special `:6622` | floor 6 slash |
| `$13E` | Tentacle | 34 | 4000 | 102/153 | — | earth, water | the same; counter: Special `:6669` | floor 6 slash |

Notes the driving will need:

- The **Bloompire**'s 254/254 leaves any hit a point or two (the physical
  formula keeps `(255 - def)/256` of the damage, plus one), against 12 HP.
  Fire (the Fire Knuckles, Fire Dance, Maduin's Fire) doubles that. Its
  turn is the danger: one in three of its second line is Energy Sap.
- **Magic draws counters** on the Buffalax (Sun Bath) and the Dante (L.3
  Muddle, which lands on levels divisible by three: L27 now, L30 later).
  Counters are off while a body is Broken (bosses-wob "the boss contract").
- The **Nohrabbit heals the party** when struck by Fight; it pays 0 XP.
- The **Cruller**'s evade 100 turns physical swings into misses; its fire
  and holy weakness and its runic Fire 2 are the handles.
- **Last-stand bodies**: the Maliga (Scissors twice) and the Sand Horse
  (Clamp at x5) change their scripts when alone (`if_num_monsters 1`).
  Neither is a Sneeze or a petrify; the driver's last-stand kill order
  (`M.lastStand`) covers only the Sneeze by default.

---

## 4. The party and its kit

### 4.1 Levels

The stretch's bodies are L26-L28 on the way and L31-L34 at the Tentacles.
CELES and SABIN start at L27 (CELES 61,090 XP of L28's 61,568; SABIN
55,288, exactly L27's). A route fight here pays 1,100-3,700 XP (x2) split
between two, so the walk to Nikeah's expected 5-6 fights bring both to
about L28-29 (**estimate**). Air Blade comes at SABIN's L30. EDGAR joins at
`max(28, the average)` into the Tentacles.

"Healthy levels at each key point" (guidelines): the key point is the
Tentacles, which retry from the cave's checkpoint on a loss (a game over).
The level for them is set by a lab (section 9), not guessed; a grind on
the South Figaro continent (groups 41-44, beside the cave's door) is the
natural place.

### 4.2 Kit levers (to be measured)

- **Zombie** (the Bloompire north of Tzen, the Black Drgn): a zombie
  member is out of control and a Fenix Down cannot land on it; Revivify
  cures it (2 in the bag; Tzen 54, Albrook 48 and Nikeah 58 sell it at
  300). The **Amulet** protects Dark, Zombie and Poison (Tzen 55, Nikeah
  59, South Figaro 62; 5,000 GP). CELES's Jewel Ring answered the plains'
  Petrify (the Osprey on groups 31/34, which the walk still crosses for 44
  steps); with two members a statue is no longer a lost fight, and Softs
  (18) cure it.
- **Muddle** (the cave): a physical hit or a Remedy clears it; the driver
  handles it (mechanics-coverage "Confuse/Muddle"). No relic in the bag
  blocks it.
- **Imp** (the Lizard): Green Cherry (5), Remedy.
- **The Genji pairs** stay on (CELES Blizzard + ThunderBlade: ice for the
  Lizard, the Maliga, the Sand Horse; bolt for the Latimeria, the Maliga,
  the Drop. SABIN's Fire Knuckles: fire for the Bloompire, the Buffalax,
  the Delta Bug, the Black Drgn, the Humpty, the Cruller).
- **Espers**: MADUIN on CELES (Fire/Ice/Bolt), IFRIT on SABIN. SERAPHIM
  (Life, Cure) is held.

### 4.3 The supply band and the shops

`shops.txt`. No Tonic seller on the stretch; field care runs on Potions
(the care kernel's fallback), as on the Sabin stretch.

| shop | where | stock (GP) |
|---|---|---|
| 54 item | Tzen | Potion 300, Tincture 1500, Green Cherry 150, Fenix Down 500, Echo Screen 120, Revivify 300, Sleeping Bag 500, Super Ball 10000 |
| 55 relic | Tzen | DragoonBoots 9000, Sneak Ring 3000, Black Belt 5000, Back Guard 7000, Sniper Sight 3000, Peace Ring 3000, Jewel Ring 1000, **Amulet 5000** |
| 56 weapon | Nikeah | Rune Edge 7500, Flame Sabre / Blizzard / ThunderBlade 7000, Enhancer 10000 |
| 57 armor | Nikeah | Diamond Shld 3500, Bard's Hat 3000, Green Beret 3000, Diamond Helm 8000, Gaia Gear 6000, Power Sash 5000, Diamond Vest 12000 |
| 58 item | Nikeah | Potion 300, Tincture 1500, Soft 200, Fenix Down 500, Revivify 300, Remedy 1000, Sleeping Bag 500, Tent 1200 |
| 59 relic | Nikeah | White Cape 5000, Cure Ring 8000, Zephyr Cape 7000, Gale Hairpin 8000, Hyper Wrist 8000, Beads 4000, Amulet 5000, Czarina Ring 3000 |
| 60 weapon | South Figaro | Trident 1700, Stout Spear 10000, Enhancer 10000, Gold Lance 12000 |
| 61 armor | South Figaro | Diamond Shld 3500, Bard's Hat 3000, Green Beret 3000, Diamond Helm 8000, Gaia Gear 6000, Diamond Vest 12000, DiamondArmor 15000 |
| 62 relic | South Figaro | Goggles 500, Star Pendant 500, Fairy Ring 1500, Amulet 5000, RunningShoes 7000, Wall Ring 6000, Cure Ring 8000, Czarina Ring 3000 |
| 63 item | South Figaro | Potion 300, Tincture 1500, Eyedrop 50, Echo Screen 120, Fenix Down 500, Revivify 300, Remedy 1000, Tent 1200 |
| 64, 84 | Figaro Castle | refuse a party with SABIN or EDGAR |

The band at L27-30 (guidelines "Supply band"): Potions at level x 1.5 plus
the measured field spend (the Sabin stretch carried 6 of field care: 47 at
L27), Fenix Downs at about the level (27), Remedies 5; Revivify for the
Zombie, Green Cherries for the Imp. Nikeah is the first stop after the long
walk, South Figaro the last before the cave. Before the Tentacles (a boss):
Potions at level x 1.5 for combat on top of the field care.

---

## 5. The Black Drgn, met by two

Formation 195 is the whole of group 40. CELES + SABIN at L27 against it:

- **HP 4000**, def 102, **mdef 20**: magic lands nearly whole. Weak fire
  and holy: SABIN's Fire Dance and AuraBolt, the Fire Knuckles, MADUIN's
  Fire. Absorbs poison.
- **4 shields, slash** (authored, route-wor-sabin 8.2): both members'
  weapons are slash, so every Fight chips.
- **BonePowder** (Zombie) on its second line, one turn in three of it:
  a zombie member attacks the party and cannot be raised by a Fenix Down.
  With two members the fight survives one zombie; it is lost only when
  both are gone or zombied.
- XP 780 (x2): 780 each.

This is the fight #300 asks to be played. The route walks the natural path
and fights it when it comes; because only about one walk in five meets it,
its first-attempt rate is measured by a lab from the snapshots at its
opening (section 9), not from the leg's variation set alone.

---

## 6. EDGAR and the Tentacles

The fight's shape (`ai.txt`): four bodies, 22,000 HP together, each with
the same loop -- Poison, Entwine (Slow), Bio, Battle -- and, first, **Seize
any Slowed party member** (`if_status_set CHAR_SLOT_n, SLOW`). A seized
member cannot act and is drained each turn (`Cmd_2d`, `battle_main.asm`
@51b2: a drain attack); after 30 counts the Tentacle Discards it, or the
Tentacle's death frees it. Each counters a hit (Battle on `$11B`/`$13C`,
Special on `$13D`/`$13E`). Their absorbs punish the wrong element: fire
heals `$11B`, ice heals `$13C`, bolt heals `$13D`.

The hands at the fight: CELES (slash; ice and bolt blades; Maduin's
Fire/Ice/Bolt), SABIN (slash claws with fire; Pummel/Suplex bludgeon;
AuraBolt holy; Fire Dance), EDGAR (the Optimum's Break Blade, slash; the
AutoCrossbow, pierce, on every body; the Bio Blaster, poison, which none
absorbs; the NoiseBlaster). Nothing in the bag cures Slow (no Haste
spell or relic is held), so the answer to the Seize is to kill or break
the body before it Seizes, or the one that holds a member.

---

## 7. Save points and checkpoint cuts

No field map on the stretch has a save point (section 0). FF6 saves
anywhere on the world map. The cuts are the natural pauses:

| checkpoint | where | why |
|---|---|---|
| `wor-sabin-v1` (exists) | world (131,179) outside Tzen | the start |
| **`wor-nikeah-v1`** | world (148,76), one step east of Nikeah's door | after the long walk, before the town and the ship; leg 1's end |
| **`wor-south-figaro-v1`** | world (113,95) region, outside South Figaro (where its exit returns the party: the ship set the parent tile to (113,95)) | after Nikeah, the ship and South Figaro; the last save before the cave, and the retry point for the Tentacles |
| **`wor-edgar-v1`** | world outside the surfaced castle (its exit returns to the parent tile (81,85)) | the first save with EDGAR; the end of this arc |

Each cut asserts its preconditions (the party, the story switches the
stretch set, no live timer, the kit) in a contract in
`lib/ot6_contract.lua`, as `wor-sabin-v1` does.

---

## 8. Break data for the stretch

Owner direction (guidelines "Design break data for every encounter"): every
species the route meets gets an authored row designed from its body, its
vanilla elements and the party that meets it, so the party holds a key and
the area teaches something. The house curve: **1** for pests, **2** for
trash, **3** for tanks, **4** for miniboss-grade; bosses by bosses-wob's
curve. Vanilla element bits stay; no `Ot6ElemAddTbl` rows. Today's floor
(5-6 shields) puts every break here on a corpse.

### 8.1 Who holds what

| hand | classes | elements |
|---|---|---|
| CELES + SABIN (Tzen to the engine room) | slash (swords, claws), bludg (Pummel, Suplex, bare fists) | ice, bolt (the blades), fire (the Knuckles, Fire Dance, Maduin), holy (AuraBolt) |
| + EDGAR (the Tentacles, and the walk out) | + pierce (the AutoCrossbow, Mithril Pike), slash (Break Blade) | + poison (Bio Blaster) |

### 8.2 North of Tzen (world groups 37-39)

| id | body | HP | weak | row |
|---|---|---|---|---|
| `$035` Bloompire | an armored bloom (def/mdef 254) | 12 | fire | **1 · slash** |
| `$058` Buffalax | a bull | 2252 | fire, water | **3 · bludg** |
| `$03C` Lizard | scaled | 1280 | ice | **3 · slash, pierce** |
| `$030` Delta Bug | a shelled insect (def 220 / mdef 5) | 612 | fire | **2 · bludg, pierce** |

- **Bloompire**: 12 HP behind the best armor in the game so far. One
  shield, in both members' class: the first blade breaks it, and a
  broken body loses its turn -- the Energy Sap that would zombify a
  member. Fire finishes it.
- **Buffalax**: the plain's tank, cracked by SABIN's fists; its vanilla
  fire is both members' (Knuckles, Maduin). Its counter answers only
  Magic, so the fists are the quiet key.
- **Lizard**: a hide a blade or a point opens; vanilla ice is CELES's.
- **Delta Bug**: def 220 against mdef 5 -- the spell, not the blade (the
  Scorpion's lesson reversed). The class row is SABIN's fists and a later
  party's points; its vanilla fire is anyone's spell.
- **Teaches:** *break it before it acts.* The Bloompire's one shield is
  the whole lesson: a zombie on the team is the price of a slow opener.

### 8.3 The South Figaro continent (world groups 41-44)

| id | body | HP | weak | row |
|---|---|---|---|---|
| `$0C3` Nohrabbit | a rabbit that heals whoever hits it | 75 | water | **1 · slash** |
| `$0B9` Latimeria | a fish | 1700 | bolt | **3 · slash, pierce** |
| `$097` Maliga | a sand crab | 952 | ice, bolt, water | **2 · slash, bludg** |
| `$05F` Sand Horse | an antlion | 1025 | ice, water | **2 · slash, pierce** |

- **Nohrabbit**: a pest (0 XP) that answers a Fight with a Cure on the
  party. One shield so the gauge reads right.
- **Latimeria**: the forest's tank, filleted by a blade; vanilla bolt is
  CELES's ThunderBlade.
- **Maliga**: the HermitCrab's row (a blade under the shell, a blow on it);
  three vanilla weaknesses, two of them CELES's blades.
- **Sand Horse**: its jaws are the danger (Clamp, x5, and every turn once
  alone); two shields let the break land before it closes them.
- **Teaches:** *read the last one standing.* The Maliga and the Sand Horse
  change scripts when alone; break the last one rather than race it.

### 8.4 The Figaro cave and the castle's basements (groups 137-140)

| id | body | HP | weak | row |
|---|---|---|---|---|
| `$049` Humpty | an egg | 800 | fire, holy | **2 · bludg** |
| `$04B` Cruller | a ring of dough (evade 100) | 1334 | fire, holy | **3 · bludg** |
| `$0A9` NeckHunter | a reaper | 1334 | poison | **3 · slash, pierce** |
| `$0D7` Dante | the cave's miniboss-grade body | 1945 | poison | **4 · slash, bludg** |
| `$08B` Drop | a drop of water | 1000 | bolt, water | **2 · bludg, pierce** |

- **Humpty / Cruller**: shells and dough are cracked, not cut: SABIN's
  fists. Their vanilla fire and holy are SABIN's AuraBolt and Fire Dance
  and CELES's Fire; the Cruller's evade makes those the real keys, and its
  Fire 2 is runic.
- **NeckHunter**: a blade or a point; its vanilla poison is EDGAR's Bio
  Blaster on the way out.
- **Dante**: four shields, both hands' classes. Broken, it cannot counter
  (bosses-wob "the boss contract"), so the break silences L.3 Muddle.
- **Drop**: a blade passes through water; a fist or a point splashes it.
  Vanilla bolt is CELES's ThunderBlade.
- **Teaches:** *the cave muddles; hit the right thing.* Four of its five
  bodies Muddle, and two counter the wrong command.

### 8.5 The Tentacles (event group 84), in bosses-wob's style

Party: CELES, SABIN and EDGAR (who joins on the spot). Formation 454.

**Shields:** 5 each (four bodies) · **Weak (class):**

| id | L | HP | vanilla weak / absorb | shields · class |
|---|---|---|---|---|
| `$11B` | 31 | 7000 | ice, water / **fire** | **5 · slash, pierce** |
| `$13C` | 32 | 6000 | fire / **ice**, water | **5 · slash, bludg** |
| `$13D` | 33 | 5000 | — / **bolt**, water | **5 · bludg, pierce** |
| `$13E` | 34 | 4000 | — / earth, water | **5 · slash, pierce** |

- **Keys:** every body is keyed for the party; each member holds a key on
  three of the four, and none alone holds all four: `$13D`, which absorbs
  CELES's bolt and has no weakness, answers only SABIN's fists and EDGAR's
  crossbow. `design_keys.txt`: `CELES + SABIN + EDGAR: designed
  Tentacle:Y Tentacle:Y Tentacle:Y Tentacle:Y`.
- **Telegraph:** Entwine is the wind-up: a Slowed member is Seized on
  that Tentacle's next turn. Break the Tentacle whose Entwine landed and
  it loses the turn it would Seize on.
- **Break story:** chip with the classes (elements are a trap here: each
  absorbs one of the party's three); spend the break on the body holding
  or about to hold a member; the AutoCrossbow chips all four at once.
- **Jank ✦:** the Seize and Discard stay as vanilla has them; the fight
  pays no XP (vanilla 0).

### 8.6 The check

`design_keys.txt` lists every formation of groups 37-44, maps 68, 90, 92,
53, 62-64 and event group 84 with the hands that meet it: every species
is keyed for CELES + SABIN (and for the Tentacles' three) under the
designed rows.

---

## 9. Risks and unknowns

| mechanic | where | coverage today | what the driving needs |
|---|---|---|---|
| Zombie on one of two members | groups 37/39 (Bloompire), 40 (Black Drgn) | the driver refuses a Fenix Down on a zombie (#245); the field care cures it with a Revivify (#190) | measure: whether a zombied member costs the fight; the Amulet as a lever |
| Imp | groups 37/39 (Lizard) | HANDLED (cured in battle) | — |
| Muddle | the cave | HANDLED | L.3 Muddle on L27/L30 members |
| the Black Drgn | group 40, unavoidable on the walk | never fought (#300) | a lab: first-attempt rate over draws that meet it |
| Seize / Discard | the Tentacles | **none**: a seized member's menu never opens, which the driver reads as a stall | read `$3359,y` (the member's seizer) / `$3403`; treat a seized member as out of the turn order and out of the heal plan; kill or break its seizer |
| an event battle whose loss is a game over | the Tentacles | the runner retries a lost segment from its boot | the lab decides the level and the kit |
| three talks to a moving NPC | Gerad in Nikeah | `H.talkToObj` | each talk re-approaches |
| "face up and hold A" | the turtle (47,29) | HANDLED (`H.faceAndHoldA`) | — |
| a ship ride | Nikeah -> South Figaro | none needed (event) | wait for control on map 91 |
| map-init `mod_bg_tiles` | Nikeah, the basements | the lib reads live RAM | offline counts are verify-on-arrival |
| the castle's shops | map 59 | refuse SABIN/EDGAR | shop in South Figaro before the cave |
| the draw | everywhere | save data (`$1FA1-$1FA5`) | vary it by using up encounters (varlab), not by seeds |

Out of scope, noted: Mobliz (v0.26), Duncan (north of Narshe, v0.32:
"He's meditating just north of Narshe", `$0936`), and Kohlingen (v0.24)
are the next arcs. South Figaro's basement passage is UNVERIFIED as
open (2.4).

---

## Appendix — key addresses

| thing | citation |
|---|---|
| the raft landing's switches | `:13002-13013` (`$0374 $037A $0381 $0382 $0397 $02B7`) |
| Nikeah's thieves | `_ca9189`..`_ca91a7` `:22022-22046`; `_ca91b1` `:22047` |
| Gerad in Nikeah | `_ca91da` `:22073`, `_ca9204`, `_ca921a` `:22112` (`$0378=1`) |
| the ship | trigger 187 (17,4) -> `_ca9282` `:22183`; `_ca92ca` `:22240` (load 91, parent (113,95)); back `_ca931c` `:22293` |
| the ferrymen | Nikeah `_ca8cbb` `:21392`; South Figaro `_ca77d7` `:18192` |
| South Figaro (WoR) | dock 91 -> `_ca7f85` `:19361` -> map 74 |
| Gerad in South Figaro | 76 NPC_6 -> `_ca808d` `:19496` (`$037F=1 $0398=1`) |
| Siegfried | 68 NPC_1 `_ca7775` `:18110`; 53 trigger (32,44) `_ca7782` `:18120` |
| the turtle | 90 (55,31) `_ca76e1` `:18005` (`$0383=1`); crossing `_ca76b3` `:17973`, `_ca76ca` `:17989` |
| Gerad in the basement | 61 (35,40) `_ca6a2c` `:15813` |
| Edgar and the Tentacles | 64 NPC_11 `_ca6a48` `:15832`; `norm_lvl` `:15930`; `char_party` `:15935`; `opt_equip` `:15936`; `battle 84` `:15937`; `_ca5ea9` `:14173` |
| the surface | 61 (5,35) `_ca69cd` `:15752` -> `_ca69fd` `:15783` |
| the castle on the world | trigger (81,85)/(82,85) `_ca5f0b` `:14227` (`$0106`) |
| Seize / Discard | `TargetEffect_2e` `battle_main.asm` @3cce; `TargetEffect_44` @3cfd; drain `Cmd_2d` @51b2 |
| inns | Nikeah `_ca8ee5` `:21563` (150 GP); South Figaro `_ca7894` `:18320` (80 GP) |
