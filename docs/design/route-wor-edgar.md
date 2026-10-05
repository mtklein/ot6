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
   (Mad Signal). Measured, the pair at L30 won the cave's commonest
   formation (232) 52 times in 53; the loss was Muddle (section 12.3).
   Labbed (12.4): the damage a Muddled party takes is mostly its own, and
   the bag's Peace Ring on SABIN (the NeckHunter drops more) takes the
   fights that cost a member from 9 in 164 to 2.
5. **The Tentacles seize.** Each Tentacle's Entwine Slows, a Slowed member
   is Seized (`TargetEffect_2e`, `battle_main.asm` @3cce: the member's menu
   is shut off and the Tentacle drains HP each turn), and it is Discarded
   30 counts later or when that Tentacle dies (`TargetEffect_44`). A
   seized member simply gets no window; measured (section 12), the Seize
   keeps the fight long. With SABIN's Air Blade the variation set won it
   13 times in 13; the lab's draws show no measured difference between
   Air Blade (11 of 12) and Pummel (10 of 12). Air Blade and the stop's
   kit are informed choices (the party has not met the Tentacles; section
   12.2).
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
The level for them is set by a lab (section 12), not guessed: L30, SABIN's
Air Blade, reached by a grind on the South Figaro continent (groups
41-43, beside the cave's door; not the desert, 44), which also plays those
pools.

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
| **`wor-nikeah-v1`** (`gen_wor_nikeah`, cut) | world (148,76), one step east of Nikeah's door | after the long walk, before the town and the ship; leg 1's end (section 10) |
| **`wor-south-figaro-v1`** (`gen_wor_south_figaro`, cut) | world (113,96), where South Figaro's exit returns the party (one step south of the parent tile (113,95) the ship set; measured) | after Nikeah, the ship and South Figaro; the last save before the cave, and the retry point for the Tentacles (section 11) |
| **`wor-edgar-v1`** (`gen_wor_edgar`, cut) | world (81,86), where the surfaced castle's exit returns the party (measured) | the first save with EDGAR; the end of this arc (section 12) |

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

**Authored** as designed below, one block in `Ot6ShieldTbl`
(`ff6/src/battle/ot6_hud.asm`, "the world of ruin: tzen to edgar"), pending
the owner's review of the table. `tools/tests/battle_breakwor_edgar.lua`
(`@suite`) reads them back from the built ROM: each row, its vanilla weak
byte and the absence of an `Ot6ElemAddTbl` row; that every species of every
formation of world groups 37-44, maps 68, 90, 92, 53, 62-64 and event group
84 has an authored row and a key for the party that meets it; and that each
member holds a class key on at least three of the four Tentacles. Evidence
in `build/attempts/wt/wor-edgar/rows/`: green on the authored ROM
(`suite.green.log`: `checked 17 designed rows`, `checked 23 formations, 36
formation-species pairs`, `PASS (frame 31) attempts=1/1`), red on main's ROM
(`suite.red.main-rom.log`: `got 52 ($34), want 0`), red on a mutant ROM
with one line per mutant (`suite.mutant.log`, `mutate.py`: shields, class
mask, a keyless Drop, a Tentacle CELES cannot key, a missing row, an
element add, a vanilla weak byte: `got 12 ($C), want 0`).
`check_shield_rows OK: 120 Ot6ShieldTbl rows, one per species, ROM matches
source`; `audit_break_coverage.py` no longer lists any of the seventeen as
unauthored (`audit.before.txt`, `audit.after.txt`); the tuning claim is
unchanged and grows only by play.

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
| `$0A9` NeckHunter | a reaper | 1334 | poison | **3 · slash, pierce, special ¤** (8.7) |
| `$0D7` Dante | the cave's miniboss-grade body | 1945 | poison | **4 · slash, bludg, special ¤** (8.7) |
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

- **Keys:** every body is keyed by class for the party, and each member
  holds a class key on at least three of the four: SABIN (slash, bludg)
  and EDGAR (slash, pierce) on all four, CELES (slash) on three. `$13D`,
  which absorbs CELES's bolt and has no weakness, answers only SABIN's
  fists and EDGAR's crossbow. `design_keys.txt`: `CELES + SABIN + EDGAR: designed
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

### 8.7 Special as a common key (#347, owner 2026-10-01)

Guidelines, "Special (¤) is a common key." Nobody on this stretch holds ¤
(Setzer joins at Kohlingen), so the rows serve a later party: Gau's Veldt
and a return with Setzer or Relm. Two of the seventeen take it: the
**NeckHunter** (a reaper: death's own shape) and **Dante** (a demon that
answers magic with magic), each beside its existing keys, shields
unchanged. The Cruller (dough, evade 100) and the Drop (water) were
candidates and stay as they are: their fire, holy and bolt already key
them, and giving ¤ to four of the cave's five bodies would make it the
answer to the cave. `battle_breakwor_edgar` carries the rows in `WANT` and
logs `special: 2 of 17 designed species take ¤ in this ROM` (0 on
a2d49b67); every formation stays keyed for the party that meets it
(build/attempts/wt/v026-rom/347/px13/).

---

## 9. Risks and unknowns

| mechanic | where | coverage today | what the driving needs |
|---|---|---|---|
| Zombie on one of two members | groups 37/39 (Bloompire), 40 (Black Drgn) | the driver refuses a Fenix Down on a zombie (#245); the field care cures it with a Revivify (#190) | measure: whether a zombied member costs the fight; the Amulet as a lever |
| Imp | groups 37/39 (Lizard) | HANDLED (cured in battle) | — |
| Muddle | the cave | HANDLED; the pair lost formation 232 once in 53 to Muddle landing again and again (section 12.3) | L.3 Muddle on L27/L30 members; a Muddle guard |
| the Black Drgn | group 40, unavoidable on the walk | never fought (#300) | a lab: first-attempt rate over draws that meet it |
| Seize / Discard | the Tentacles | planned around (measured, section 12): a seized member gets no window and the driver plans for the others; taking the holder first measured no gain | — |
| an event battle whose loss is a game over | the Tentacles | the runner retries a lost segment from its boot | the lab (section 12): L30 by a grind, Air Blade (no measured difference from Pummel) |
| a weapon the Tentacles absorb | the Tentacles | the runner's absorb guard fails the fight | the stop before them: no element in any hand; the Enhancer bought in South Figaro keeps EDGAR's Optimum off the Blizzard and ThunderBlade |
| three talks to a moving NPC | Gerad in Nikeah | `H.talkToObj` (the cafe's wandering thieves: `H.chaseTalk`) | each talk re-approaches |
| a talk that opens a battle | Gerad at the engines | `H.talkToObj`'s approach plays battles by mashing A | walk up with the tactical walker, then face him and press A |
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

## 10. Tzen to Nikeah's door, played (`gen_wor_nikeah`, `wor-nikeah-v1`)

Driven 2026-09-29 for #262. The segment cold-Continues `wor-sabin-v1`
(checkpoint=), asserts that every pool the walk can roll deals only species
with designed rows, walks the shortest on-foot path to (148,76) fighting
everything (the Black Drgn's desert included), cares for the party after
every battle, and saves there: the `wor-nikeah-v1` checkpoint. Every number
below is quoted from a log under `build/attempts/wt/wor-edgar/leg1/`
(`var4/` the shipped generator's variation set, `var1/`-`var3/` the sets
before its two fixes, `zfix/`, `k12fix/`, `k12s41fix/` the fixes' own
runs). Nothing was measured by writing game state.

### 10.1 The run (`build/attempts/wt/wor-edgar/recut/capture_wor-nikeah-v1.log`, the capture)

| step | what the log says |
|---|---|
| boot | `[wor] boot f1346: world 1 (131,179), CELES L27 xp 61090 HP 1211/1211 MP 251/251 status1 $00; SABIN L27 xp 55288 HP 1225/1225 ...; tonic=5 potion=47 fenix=27 remedy=5 soft=18 revivify=2 greencherry=5 gil=203243` |
| the pools | `[route] Tzen -> Nikeah: the walk can roll groups {31, 34, 36, 37, 38, 40, 39}` (36 by the zone-and-terrain pairing; its Peepers and EarthGuard have rows) |
| the walk | 6 battles: Osprey + Chitonid + Gigan Toad, Lunaris + Osprey, Delta Bug x4 three times, the Black Drgn (`battle $0C3 WON after 1560 ticks: killed s0:$0D5 ... paid as due`) |
| the save | `[saved] wor-nikeah-v1: slot 3 holds map 1 ($2001) world tile (148,76)`, `contract wor-nikeah-v1 (exit): all 25 fields hold`, `[wor] the stretch: 6 battles ...: 6 won ...; Fenix Downs 27 -> 27; CELES L28 xp 66688 HP 997/1301 ...; SABIN L27 xp 60886 HP 988/1225 ...; tonic=4 potion=43 fenix=27`, `PASS (frame 24350) attempts=1/3` |

Sealed and validated (`recut/validate_wor-nikeah-v1.txt`): `holds=slot 3
world 1 (148,76) [$1F64=$2001] (saved: declared and checked)`, sha256
`26e88fd1...`. The graph's own run (`nice ninja
build/states/wor_nikeah.mss.lua`, `recut/wor_nikeah_ninja.log`) and the
capture are the same run: `wor_nikeah.mss` byte-identical, `d354e578...`
both (`recut/graph_vs_capture.sha256`). The next segment's cold Continue of it asserts its entry
contract (`gen_wor_south_figaro`: `contract wor-nikeah-v1 (entry)`).

### 10.2 Under real draw variation

`leg1/varlab.py` (after route-wor-sabin's) derives the generator with a
block after the boot that fights K encounters on the plains beside Tzen
(groups 31/34) and walks back to (131,179), so the body starts from
another encounter counter, level, HP and bag; K is a floor (a leg can hold
two battles). Retries off (`OT6_RETRIES=1`). `leg1/var4/summary.txt`,
`vartable.md` (`vartable.py`), the shipped generator:

| variant | the body starts at | body battles | Black Drgn | deaths / zombie cures | Fenix Downs | lowest member HP | verdict |
|---|---|---|---|---|---|---|---|
| K=0, shifts 0 / 23 / 41 | the checkpoint | 6 | 1 | 0 / 0 | 27 -> 27 | 738 / 554 / 535 | `PASS (frame 24350)` / `(24303)` / `(25694)` |
| K=1 | C L28 1301/1301, S L27 1085/1225, `$1FA1-2 = 62 27` | 6 | 0 | 0 / 0 | 27 -> 27 | 699 | `PASS (frame 26118)` |
| K=2 | `7A 28` | 7 | 0 | 0 / 0 | 27 -> 27 | 627 | `PASS (frame 35023)` |
| K=3, shifts 0 / 23 / 41 | `9A 29` | 7 | 0 | 0 / 0 | 27 -> 27 | 606 / 316 / 608 | `PASS (frame 38726)` / `(34662)` / `(37990)` |
| K=4 | `A8 29` | 7 | 0 | 0 / 0 | 27 -> 27 | 462 | `PASS (frame 37710)` |
| K=5 | `DA 2A` | 7 | 0 | 1 / 1 | 27 -> 27 | 788 | `PASS (frame 37279)` |
| K=6, shifts 0 / 23 / 41 | `FA 2C` | 6 | 0 | 0 / 0 | 27 -> 27 | 763 / 533 / 561 | `PASS (frame 38870)` / `(36946)` / `(39023)` |
| K=7 | `10 2D` | 5 | 0 | 1 / 1 | 27 -> 27 | 877 | `PASS (frame 34727)` |
| K=8 | `2C 2D` | 6 | 0 | 0 / 0 | 27 -> 27 | 770 | `PASS (frame 38806)` |
| K=9, shifts 0 / 23 / 41 | `4C 2F` | 4 | 1 | 0 / 0, 0 / 0, 1 / 1 | 27 -> 27 | 848 / 885 / 607 | `PASS (frame 37046)` / `(37094)` / `(40167)` |
| K=10 | `58 2F` | 5 | 0 | 0 / 0 | 27 -> 27 | 845 | `PASS (frame 42502)` |
| K=11 | `7A 30` | 5 | 1 | 0 / 0 | 27 -> 27 | 900 | `PASS (frame 43870)` |
| K=12, shifts 0 / 23 / 41 | `AC 32` | 6 | 1 | 1 / 1 each | 27 -> 27 | 641 / 716 / 852 | `PASS (frame 51887)` / `(52567)` / `(53597)` |
| K=13-20 | `C2 32` ... `BA 3A` | 5-7 | 1 (K=16), 2 (K=18) | 0 / 0 | 27 -> 27 | 737-1011 | `PASS` all eight |

31 of 31 `PASS attempts=1/1`: 472 `[outcome]` lines, 472 `paid as due`, 0
without an end reading; 183 battles in the bodies, every one won. The
Black Drgn came 13 times (12 of the 31 runs; K=18 met it twice) and fell
every time, in 1239-3438 ticks, with no death in its own fights. The six deaths are
all zombifications counted by the death watch (`atk $EF` Energy Sap five
times, the Bloompire's; one attributed to a poison tick, K=9 shift 41),
each cured after the battle with a Revivify; no Fenix Down was spent in
any run. The lowest member HP on the 300-tick battle lines is 316 (K=3
shift 23).

Two defects found here and fixed before this set (their runs kept):

- **A member the battle leaves zombied reads 0 HP with no Wound bit**, and
  the field care took it for dead: it planned a Fenix Down, the game
  refused it (`REFUSED by the game: revive char 6 with $F0 (0/1396 hp ...
  status1 02)`), and the party walked on with a zombie (`var1/k5_s0.log`,
  K=7 the same for SABIN: 2 of 9 runs red). The care's dead test is now
  0 HP and not zombie (`lib/ot6_field.lua`: the revive pick takes a member
  at 0 HP without the zombie bit `$02`; `pickStatusCure` skips a member with
  the Wound bit, or at 0 HP without the zombie bit; the commit message's
  "the Wound bit" says it short):
  the same draw reads `used $F1 on char 6: 0 -> 174 hp, ... status1 02 ->
  00` (`zfix/k5_s0.log`).
- **The step onto (148,76) can roll an encounter that opens after the
  walker has arrived**, during the save's menu press (`var2/k12_s0.log`:
  the save timed out on the Bloompire pair's reward screen). The segment
  now stands 90 frames and walks to the tile again, fighting what came,
  and runs the field care there (a battle on the goal tile ended the walker
  before its after-battle care: `var3/k12_s41.log`, CELES zombied at the
  save's assertion). `k12fix/`, `k12s41fix/`: both PASS.

## 11. Nikeah, the ship and South Figaro, played (`gen_wor_south_figaro`, `wor-south-figaro-v1`)

The segment cold-Continues `wor-nikeah-v1`, and plays the story's gates in
order, asserting each switch as it passes (section 2.3-2.4). No map on it
rolls a random battle. Logs under `build/attempts/wt/wor-edgar/leg2/`.

| step | what the log says (`recut/capture_wor-south-figaro-v1.log`) |
|---|---|
| Nikeah's item seller (shop 58) | `[shop] Nikeah item seller: bought: tonic=4 potion=48 fenix=28 ... (spent 2000 GP)` |
| the cafe's four thieves | chased where they wander between the tables (`H.chaseTalk`; the static approach timed out on the first: `timeout after 1020 frames driving toward the thief NPC_4`); `$00A7`-`$00AA` and `$0376` asserted |
| Gerad, three talks | `[nikeah] f10342 Gerad gave up his act`: `$01F0`-`$01F3`, then `$0378` |
| the inn (150 GP) | `[Nikeah inn] before the night: c5 988/1225 hp ... c6 997/1301 hp` -> `after the night: c5 1225/1225 ... gil=211431` |
| the ship | `[ship] f13589 aboard map 187 (17,2)` -> `[sfigaro] f16633 off the ship map 91 (14,12)`; `$00AC=1`, `$037E=1` |
| Gerad upstairs in the inn | `[sfigaro] f19225 the thieves leave for the cave map 76 (88,12)`: `$037F=1`, `$0398=1` |
| South Figaro's item shop (63) | at the band already: `(spent 0 GP)` |
| the arsenal (shop 60) | the Enhancer, 10,000 GP; `[sfigaro] ... CELES wears the Enhancer, kit 06 13 0F 76 8F D1 B5` |
| the save | out by the west edge to world (113,96) (measured: one step south of the parent tile (113,95) the ship set); `[saved] wor-south-figaro-v1: slot 3 holds map 1 ($3001) world tile (113,96)`, `PASS (frame 26029) attempts=1/3` |

The ride clears `$0378` again (`:22290`), so the checkpoint's contract
carries `$00AC` rather than it. The Enhancer is CELES's upgrade (135 and
no element against the Blizzard's 108 ice, the ThunderBlade kept in the
other hand), and it keeps the bag's best sword for EDGAR's Optimum
non-elemental (section 12). Sealed and validated
(`recut/validate_wor-south-figaro-v1.txt`): sha256 `d0e923e7...`,
`holds=slot 3 world 1 (113,96)`; the graph's run and the capture wrote
the same `wor_south_figaro.mss` (`192b6363...` both); the cold Continue
(`probe_wor_south_figaro_continue.lua`, `leg2/continue_sf.log`):
`contract wor-south-figaro-v1 (entry): all 29 fields hold`, `[continue]
world 1 at (113,96): CELES L28 HP 1301/1301 ... esper+kit 06 13 0F 76 8F D1
B5; SABIN L27 HP 1225/1225 ... 01 57 57 77 90 D1 D5; tonic=4 potion=48
fenix=28 remedy=5 gil=201431`, `PASS (frame 1386)`.

Under variation (`leg2/var_sf/`, the leg-1 derivation with K encounters
used up on the grass and plains beside Nikeah, groups 37-39): see
`leg2/var_sf/summary.txt`; the segment has no battles of its own, so what
varies is the party it inherits (HP, levels, the bag) and with it the inn
and shop decisions. K = 0-6: 7 of 7 `PASS`, each `[saved]
wor-south-figaro-v1: slot 3 holds map 1 ($3001) world tile (113,96)`.

## 12. South Figaro to Edgar, played (`gen_wor_edgar`, `wor-edgar-v1`)

The segment cold-Continues `wor-south-figaro-v1`, grinds the South Figaro
continent's grass, forest and plain to L30, walks the Figaro cave behind
the thieves and up through the castle's basements, fights the Tentacles
with EDGAR, sends the castle up and saves outside it: the `wor-edgar-v1`
checkpoint. Logs under `build/attempts/wt/wor-edgar/leg3/` (`var_ed4/` the
shipped generator's variation set; `var_ed_v1/`, `var_ed2/`, `var_ed3/`
the sets before its fixes; the Tentacles' labs beside them). Nothing was
measured by writing game state.

### 12.1 The run (`leg3/capture_edgar_final.log`, the capture)

| step | what the log says |
|---|---|
| boot | `[wor] boot f1346: world 1 (113,96), CELES L28 HP 1301/1301 ...; SABIN L27 HP 1225/1225 ...; kit CELES 06 13 0F 76 8F D1 B5, SABIN 01 57 57 77 90 D1 D5` |
| the grind | `[wor] grind done f106952 after 37 legs: CELES L30 ...; SABIN L30 ...; potion=51` |
| the cave | the turtle (`$0383`), the crossing, 92, 53, Gerad's scene in basement 1 (`$026E`); chests: X-Potion and Ether in map 68's second piece, the chest room's Ether, X-Potion, Gravity Rod and Crystal Helm |
| the stop | `ready for Edgar: kit CELES 06 13 0B 76 8F D1 B5, SABIN 01 53 5C 77 90 D1 D5` (the Enhancer and the RegalCutlass; the MetalKnuckle and a Mithril Shld), the care to full |
| the Tentacles | `battle $1C6 WON after 16199 ticks: killed s0:$13E s1:$13D s2:$13C s3:$11B`; `EDGAR's kit from the game's Optimum: FF 11 5C 7E 89 FF FF` (Break Blade, Mithril Shld, Crystal Helm, Mithril Vest) |
| after | the kits back, EDGAR's Jewel Ring, Star Pendant and RAMUH, the Soul Sabre, the way back by basement 3's east stairs, the engineer: `the castle has surfaced` (`$00C7`, `$0106`) |
| the save | `[saved] wor-edgar-v1: slot 3 holds map 1 ($2001) world tile (81,86)`; `[wor] the battles: 41 (...): 41 won, 0 the party left, 0 monster escape(s)`; `PASS (frame 173383) attempts=1/3` |

Sealed and validated (`leg3/validate_wor-edgar-v1.txt`): sha256
`5666aa8a...`, `holds=slot 3 world 1 (81,86)`.

What the plan (sections 2.5-2.8) had right: the gates and their switches,
the turtle's "face up and hold A", Edgar's join and `opt_equip`, the
surfacing at (81,84) with the parent tile (81,85). What it did not know:

- **The cave's map 68 is three pieces joined by same-map links**: in by
  (16,42), the link (14,33) -> (55,56), the link (61,57) -> (17,21), and
  (10,2) on to map 90, whose arrival tile (55,31) is the turtle scene.
- **Basement 1 is two rooms joined through the castle's lower hall**: from
  Gerad's scene, the stairs (27,31) -> 59 (14,48), (9,49) -> 61 (10,33),
  and (2,37) -> 62. **Basement 2's engine-room door is on a floor reached
  only through basement 3**: (14,8) -> 63 (54,6), its link (56,15) -> the
  chest room (87,7), the stairs (84,3) -> 62 (8,17), and the door (8,6) ->
  64 (29,20). The way back is 64 (29,21) -> 62 (8,8), (8,18) -> 63 (84,5),
  the east stairs (87,5) -> (56,14), (53,5) -> 62 (13,7), (13,12) -> 61
  (3,36); the west pair (81,5)/(47,8) leads into a pocket of basement 2
  whose only exit is back (`no path (3,12)->(13,12)` off its (2,13) door).
- **The castle's exit returns the party to (81,86)**, one step below the
  parent tile.
- **The runner's absorb guard refuses the Tentacles with the stretch's
  kit**: `char 5's R-hand item $57 (fire) is ABSORBED by slot 3 species
  $011B`, `char 6's R-hand item $0E (ice) ... $013C`, `... $0F (bolt) ...
  $013D` (`leg3/tent1.log`); hence the stop's kit, and the Enhancer bought
  in South Figaro so that EDGAR's Optimum takes the Break Blade, not a
  Blizzard or ThunderBlade. The kit is informed: the absorbs are the ROM's
  data, and the party has not met the Tentacles (#324 is the in-battle
  hand swap a first-time player would make on seeing a heal).
- **`H.talkToObj`'s approach fights by mashing A** (its navTo plays
  battles with `playBattles = true`). Talking to Gerad through it fought
  the Tentacles by mashing -- no driver line, every member dead with 5 BP
  banked (`leg3/ed9.log`) -- and a cave battle on the way to Siegfried went
  unsaid, which the `[outcome]` count caught (`an [outcome] said for every
  battle fought ... got 28 ($1C), want 29 ($1D)`, `leg3/var_ed3/k3_s0.log`).
  The segment talks from the tile below with the tactical walker.
- **The desert's Sand Horse pair (world group 44, formation 222) is a
  coin flip as the driver plays it, not a level wall.** Across the
  variation sets the pair won it 6 times and lost it twice (`$0DE WON`:
  4 in `var_ed_v1/`, 1 in `var_ed2/`, 1 in `var_ed4/`; the pool's other
  formations, 223 and 138, won 2 and 6). Both losses end `class=died with
  3 BP banked` with both horses untouched (`monhp=s0:1025/sh2,s1:1025/sh2`),
  the pair having spent its turns on heals and items: at L28 two heals
  and an item before the one Fight (`leg3/var_ed_v1/k2_s0.log`), at L30
  three Fenix Downs raising SABIN to 188 HP into Sand Storm (`atk $69`)
  hits of 400 and more, the revive rule judging by `the living enemy's
  smallest hit 162` (`leg3/var_ed2/k2_s0.log`). The grind stays off the
  desert until that is measured (section 13).

### 12.2 The Tentacles

From one snapshot at the engine room's stop, the in-battle draw varied by
when the party talks to Gerad (the battle seeds its RNG from the frame
counter, InitBattle `lda $021e`; a seed shift alone repeated whole runs
frame for frame), 12 draws an arm, retries off (`leg3/tentlab.py`,
`lab_tent.lua`):

| arm | party | won | lost | ticks of the wins |
|---|---|---|---|---|
| L29/28/28, SABIN's Pummel (`tent_l29/`) | CELES 1396, SABIN 1315, EDGAR 1306 HP | 10 | 2 | 7595-21342 |
| the same, the talk by `H.talkToObj` (`tent_off/`) | the same | 10 | 2 | 8086-32366; a won fight lost 7 members to death along the way |
| the same, the holder of a seized member taken first (`tent_on/`, `seize_focus_lever.diff`) | the same | 9 | 3 | no gain; not shipped |
| L31/30/30 after the grind, Pummel (`tent_l30/`) | CELES 1595, SABIN 1509, EDGAR 1500 | 10 | 2 | 8594-22035 |
| **L31/30/30, Air Blade** (`tent_l30_airblade/`) | the same | **11** | **1** | 8507-21227 |

What loses it: the members spend much of the fight Seized. Each
Tentacle's Entwine Slows, a Slowed member is Seized on that Tentacle's
next turn and drained (`cmd $2D`, the commonest cause of death) until it
is Discarded or the Tentacle dies, and the drain heals the Tentacle; a
lost L30 fight issued 20 plans in 14,583 ticks for three members
(`tent_l30/s9.log`). Levels shortened the wins but not the losses. Air
Blade (wind, every Tentacle at once, none absorbs wind) lost one draw in
twelve against Pummel's two, but on the same twelve draws Pummel lost s5
and s9, which Air Blade won, and Air Blade lost s8, which Pummel won
(`tent_l30.out`, `tent_l30_airblade.out`): one loss against two is no
measured difference. The shipped segment grinds to L30 and sets his blitz
to Air Blade for this fight (informed: "none absorbs wind" is read from
the ROM, not seen); with it the variation set below won the Tentacles in
all 13 runs that reached them.

### 12.3 Under real draw variation

The leg-1 derivation, K encounters used up on the continent's grass and
plain before the body (the grind then starts from another counter, level
and bag), retries off. `leg3/var_ed4/summary.txt`:

| variant | the body starts at | grind legs | body battles | the Tentacles (ticks) | deaths there | deaths in all | Fenix Downs | lowest member HP | verdict |
|---|---|---|---|---|---|---|---|---|---|
| K=0, shift 23 | the checkpoint | 37 | 41 | WON 8681 | 0 | 0 | 28 -> 28 | 109 | `PASS (frame 167063) attempts=1/1` |
| K=0, shift 41 | the checkpoint | 37 | 41 | WON 8681 | 0 | 0 | 28 -> 28 | 682 | `PASS (frame 162098) attempts=1/1` |
| K=1, shift 0 | C L28 1216/1301, S L27 1063/1225, `46 42` | 36 | 41 | WON 9286 | 0 | 0 | 28 -> 28 | 350 | `PASS (frame 164075) attempts=1/1` |
| K=2, shift 0 | C L28 1088/1301, S L28 1315/1315, `76 43` | 36 | 41 | WON 16885 | 0 | 0 | 28 -> 28 | 409 | `PASS (frame 171547) attempts=1/1` |
| K=3, shift 0 | C L28 1204/1301, S L28 1261/1315, `94 44` | 27 | 32 | WON 10658 | 0 | 1 | 28 -> 27 | 138 | `PASS (frame 152725) attempts=1/1` |
| K=3, shift 23 | C L28 1301/1301, S L28 1315/1315, `94 44` | 27 | 32 | WON 10026 | 0 | 1 | 28 -> 27 | 201 | `PASS (frame 151205) attempts=1/1` |
| K=3, shift 41 | C L28 1301/1301, S L28 1242/1315, `94 44` | 27 | 24 | - | 0 | 2 | - | 125 | `FAIL: GAME OVER fired (GameOver read x0,` |
| K=4, shift 0 | C L28 1301/1301, S L28 1155/1315, `D0 45` | 31 | 36 | WON 18809 | 0 | 0 | 28 -> 28 | 193 | `PASS (frame 160042) attempts=1/1` |
| K=5, shift 0 | C L29 1261/1396, S L28 1315/1315, `06 47` | 24 | 30 | WON 11240 | 0 | 1 | 28 -> 27 | 63 | `PASS (frame 144779) attempts=1/1` |
| K=6, shift 0 | C L29 1396/1396, S L28 1209/1315, `1A 48` | 31 | 35 | WON 12608 | 0 | 0 | 28 -> 28 | 629 | `PASS (frame 162391) attempts=1/1` |
| K=7, shift 0 | C L29 1322/1396, S L28 1315/1315, `30 49` | 28 | 34 | WON 10514 | 0 | 0 | 28 -> 28 | 145 | `PASS (frame 164367) attempts=1/1` |
| K=8, shift 0 | C L29 1396/1396, S L28 1111/1315, `46 49` | 29 | 34 | WON 9786 | 0 | 0 | 28 -> 28 | 582 | `PASS (frame 162137) attempts=1/1` |
| K=9, shift 0 | C L29 1396/1396, S L28 1315/1315, `96 4B` | 23 | 29 | WON 10966 | 0 | 1 | 28 -> 27 | 270 | `PASS (frame 157631) attempts=1/1` |
| K=10, shift 0 | C L29 1396/1396, S L28 1139/1315, `BC 4C` | 23 | 29 | WON 9788 | 0 | 0 | 28 -> 28 | 424 | `PASS (frame 153758) attempts=1/1` |

Thirteen of the fourteen runs pass; the 545 `[outcome]` lines are all
`paid as due`, and each passing run's `[wor] the battles` line reads
all won (for example `41 ($086 x12, $0DC x21, $0E8 x5, $0E7 x1, $1C6 x1,
$0E5 x1): 41 won, 0 the party left, 0 monster escape(s)`). **The Tentacles
were won in all 13 runs that reached them**, 8681-18809 ticks, no
member dead in that fight. (K=0 at shifts 23 and 41 both won it in 8681
ticks: the event battle's draw is the frame counter, not the seed, so
those two may be one Tentacles draw.)

**The one loss is the cave, not the Tentacles.** K=3 at shift 41: the
first step into map 68, formation 232 (NeckHunter, Cruller, Humpty x2),
the pair at L30 with CELES 1356/1495 and SABIN 1509/1509. SABIN is
Muddled from the first window and CELES later; each Fight on the ally
clears it and it lands again (`entity 1 (182/1509) is MUDDLED (STATUS2
$22)`), CELES dies with no monster action attributed, and SABIN, reviving
her with a Fenix Down, dies to slot 1's spell: `[death] f+3913 entity 1
char 5 from 125/1509 by slot 1 cmd $02 atk $05`, `[wipe] ... class=worn
down (no one-shot, no pips banked)`, `[outcome] battle $0E8 LOST after
4187 ticks: killed s2:$049 s3:$049` (`var_ed4/k3_s41.log`). Across the set
formation 232 was fought 53 times, about four a run on maps 68 and 63:
**52 won, 1 lost**. So the leg's first-attempt rate under this set is 13
of 14, and the loss is the Muddle the cave's bodies all carry (finding 4).
Section 12.4 labs it.

### 12.4 The cave's Muddle, labbed (#320)

The question: how often does each cave and basement formation kill a
member or the party at the first attempt, why, and what moves it. The
review of the merged ROM (`build/attempts/review-wor-edgar/merged/
merged_k3_s0.log`) had lost the walk back to formation 234, Drop x3, with
every death `by nobody (no monster action attributed)` and `class=died
with 5 BP banked`, the Drops untouched at `1000/sh2`.

**The lab** (`build/attempts/wt/figaro-muddle/lab/`: `lab_muddle.lua`,
`labrun.py`, `arms.py`). Snapshots cut inside the generator's own runs
(`varlab.py --snap`, the leg's own variation: K = 0-10 encounters used up
before the body) at the cave's mouth (map 68, the pair: `c68`) and in the
engine room after the Tentacles (map 64, the trio, EDGAR dressed:
`e64t`). From each, the party walks between two tiles and fights what
comes with the tactical driver and its field care, as the generator walks:
6 battles at the cave's mouth, 8 in the engine room, retries off. The
draw moves by idle frames before the first step (the battle's seed is the
frame phase, InitBattle `lda $021e`): waits 1, 21 and 41, 33 runs an arm,
156 distinct battle keys in 164 of formation 232's fights. The formations
come in each snapshot's own order, and only one snapshot met the Drops
(K=3's engine room, as its first battle), so the Drops are 15 waits
there, 28 to 84 by 4 (the first 25 frames of waiting fold into one phase).
Every battle's key, every Muddle landing and every death is in the logs.

**Why the party dies.** Every body here Muddles (Hug, BrainStorm, Mad
Sickle; the Drop's script is Mad Signal on two turns in three and a
counter), and the damage a Muddled party takes is mostly its own:

- a Muddled member's turns are the engine's (RandCharAction), and its
  Fight, Blitz, Tools or spell lands on the party -- 8 of the baseline's
  13 deaths at the cave's mouth were a member's own action;
- a command entered before the Muddle landed goes out re-aimed: SABIN's
  Pummel, committed at f+300, killed him from over 1000 HP after Hug
  landed at f+490 (`attr/attr_self2`: `[death] f+886 entity 1 char 5
  from 31/1509 by entity 1 char 5 cmd $0A atk $5D (its own action; it was
  Muddled at f+490)`);
- the Muddle rule's cure-hit (#170) is a real hit, and a Genji pair of
  Fire Knuckles is a big one: SABIN's measured 178, 268 and 186, and 947
  and 898 where it landed after a monster's hit had already cleared the
  Muddle (`attr/attr_unmuddle`: `[unmuddle] actor 1 (char 5)'s hit on
  entity 0 took 947 (1134 -> 187)`); at 75 HP it killed her (`by entity 1
  char 5 cmd $00 atk $FF (the Muddle rule's unmuddle hit)`).

**The death watch** now names the party's hand (`Driver:allyAct`): a
member's HP falling with no monster action attributed, while a member's
command executes or settles, is that member's action, said with whether
the actor was Muddled as it began. The same fight twice, the attribution
on and switched off (`H.ALLY_ATTRIBUTION = false`), frame for frame
(`attr/attr_drop_on`, `attr/attr_drop_off`, the Drops):

    [death] f+762 entity 0 char 6 from 1260/1696 by entity 1 char 5 cmd $0A atk $5D (a MUDDLED member's action) bp=1 party_bp=1,1,1,1
    [death] f+762 entity 0 char 6 from 1260/1696 by nobody (no monster action attributed) bp=1 party_bp=1,1,1,1

and a monster's kill is still the monster's (`by slot 1 cmd $00 atk $EE`
in both, `attr/attr_on`, `attr/attr_off`). The `[wipe]` line tags such
deaths `:by_muddled_e1`.

**The arms** (`arms.py`; formation 232 at the cave's mouth unless said):

| arm | fights | won | lost | with a death | deaths (by the party) | Fenix landed |
|---|---|---|---|---|---|---|
| baseline (`base_c68`) | 164 | 163 | 1 | 9 | 13 (8) | 9 |
| the Peace Ring on SABIN (`peace_c68`) | 164 | 162 | 2 | 2 | 6 (2) | 2 |
| ...and the Muddle rule's floor (`peace_guard_c68`) | 164 | 162 | 2 | 2 | 4 (2) | 0 |
| ...and no cure-hit at all (`peace_nocure_c68`) | 167 | 166 | 1 | 2 | 3 (3) | 1 |
| the landers' kill order (`lander_c68`; 4 runs cut short by a lab crash) | 149 | 149 | 0 | 7 | 9 (3) | 9 |
| the bank spent while Muddle threatens (`spend_c68`) | 165 | 163 | 2 | 15 | 23 (13) | 18 |
| trio, engine room: baseline / the ring (`base_e64t`, `peace_e64t`) | 264 / 264 | all | 0 | 0 | 0 | 0 |

The ring works as a guard: SABIN was Muddled 43 times in the baseline
and never with it on (`Muddle landings by entity ... e0=54 e1=43` against
`e0=86`). It takes the deaths from 9 fights in 164 to 2, and the Fenix
Downs spent from 9 to 2. It does not measurably move the losses: 1, 2, 2
and 1 in about 165, the ring's two the same hard pincer draw at two
snapshots (seed `be4C`, CELES Muddled at f+330, then the cure-hit's 947).
The floor and no cure-hit at all read the same as the ring alone at this
size. The landers' kill order changed nothing a person would notice. The
bank spent on the keyed line while Muddle threatens was worse on every
count: a pip spent goes out with the action Muddle re-aims.

The Drops, the trio in the engine room (15 draws an arm, 15 distinct
battle keys):

| arm | won | lost | with a death | deaths (by the party) | Fenix landed | Muddle landings |
|---|---|---|---|---|---|---|
| main's rule, no ring (`drop_main`) | 10 | 5 | 7 | 21 (20) | 3 | 93 |
| the ring on SABIN only (`drop_peace1`) | 15 | 0 | 0 | 0 | 0 | 9 |
| every ring the bag holds, SABIN and EDGAR here (`drop_final`) | 15 | 0 | 0 | 0 | 0 | 1 |

Without a ring the trio loses a third of these fights, 20 of its 21
deaths by its own members; with one ring, on SABIN, it won all 15.

**What changed.** gen_wor_edgar puts the bag's Peace Rings on once a
Muddle has been seen this run, the way a person reaches for one after the
first: from then on each arrival in the cave and the basements puts them
on whoever lacks one, SABIN, EDGAR, CELES in that order (the checkpoint's
bag holds one; NeckHunters drop more, 1 to 5 in the bag by the engine
room across the draws). The usual relics go back for the Tentacles, none
of which Muddles (informed: read from their scripts, not met), and again
out of the castle, so wor-edgar-v1 saves in them. A relic change on a Genji Glove wearer re-runs the game's Optimum
(menu `CheckReequipRelics`), so relics change before a stop's kit step,
and the hands go back where no kit step follows; the first cut lost the
Tentacles to the absorb guard when CELES's Optimum took the Break Blade
and EDGAR's took the Blizzard (`final_v1/k3_s0.log`). The Muddle rule
keeps its cure-hit, but not on an ally at or under the hitter's largest
measured cure-hit (a quarter of max HP until measured), on by default
(`opts.unmuddleGuard = false` is the old rule).

**The leg under the same variation** (K = 0-10 at shift 0, then K = 0
and 3 at shifts 23 and 41; retries off; the cave's and the basements'
formations counted from each run's `[outcome]` and `[death]` lines):

| set | runs passed | formation 232: fought, won, with a death | other cave formations | Tentacles |
|---|---|---|---|---|
| main's gen (`base/`, K 0-10) | 11 of 11 | 42, 42, 2 (`k4`: CELES from 1116, `k5`: CELES from 372 holding 3 BP, both `by nobody` under main's death watch) | 31, all won, no death | 11 of 11 |
| rings from the start (`final/`, K 0-10) | 11 of 11 | 42, 42, 1 (`k0`: CELES from 71 by slot 1, holding 4 BP) | 31, all won, no death (the Drops once) | 11 of 11 |
| rings from the start (`final/`, K 0 and 3 at shifts 23, 41) | 3 of 4 | 19, 19, 0 | 5, all won, no death (the Drops once) | 3 of 4 (`k3_s23`: `battle $1C6 LOST after 26675 ticks: killed none`) |
| **this gen** (`final2/`, K 0-10; main merged, ROM `1ef410a3`) | **11 of 11** | **41, 41, 0** | 30, all won, no death (the Drops once) | 11 of 11 |
| **this gen** (`final2/`, K 0 and 3 at shifts 23, 41) | **4 of 4** | **20, 20, 0** | 6, all won, no death (the Drops twice) | 4 of 4 |

`final/` put SABIN's ring on before the cave, which is foreknowledge, and
fought the Tentacles with SABIN and CELES in Peace Rings for the Black
Belt and the Jewel Ring; its one loss was the Tentacles. `final2/` is the
shipped gen: the rings only after a Muddle is seen (SABIN's went on in
map 68 in 2 runs, across the water in 10, in basement 2 in 1, and never
in 2, k4 and k9, where no Muddle landed before the way out; back on after
the Tentacles in the 13), the usual relics for the Tentacles and the save. Its fifteen runs
passed with no death in any cave or basement fight and no Fenix Down
spent there (`final2/cavestats.txt`: `$0E8: 61 battles, 61 won, 0 lost,
0 with a death`).

The one death in `final/` (K = 0, the first capture's own draw) is the cure-hit
again: SABIN's Fight, queued on a Muddled CELES, landed after a monster's
hit had already cleared her Muddle and took 906 of her 977 (`[unmuddle]
actor 1 (char 5)'s hit on entity 0 took 906 (977 -> 71); char 5's
largest this run: 906`), and a monster finished her (`[death] f+3171
entity 0 char 6 from 71/1595 by slot 1 cmd $00 atk $EE bp=4`). The floor
was his largest measured hit so far, 277 (`took 277 (1595 -> 1318)`),
which underestimated this one; and the floor is read when the hit is
planned, not when it lands.
`final_v1/` is the first cut of the rings, kept: its K = 3 lost the
Tentacles to the absorb guard (above) and its K = 5 lost formation 232
in a pincer, CELES Muddled at f+327 and SABIN's cure-hit then taking
898 off her after a monster's hit had already cleared it (`[unmuddle]
actor 1 (char 5)'s hit on entity 0 took 898 (1132 -> 234)`); the same
K passes in `final/`, whose frames part from it inside the cave (map 53 at f113218 against f112513).

### 12.5 After the re-cut (#326, #317): the Back Guard, no cure-hit, a top-up below Gerad

The re-cut chain (`wor-south-figaro-v1` at L29/28, CELES without Ice 2)
passed the leg's variation set 7 of 12 (`build/attempts/wt/recut/var/
var_edgar/`: formation 232 lost in 3, the Tentacles in 2), where the old
chain had passed 15 of 15. Evidence under `build/attempts/wt/edgar-regress/`
(`README.txt`), all on ROM `1ef410a3`, retries off.

**The party is not what changed.** Both chains grind to L30/L30 and meet
the cave with the same maximum HP and MP, stats, kit, espers and blitzes
(`analysis/fixture_party.txt`: vigor, speed, stamina and magic
34/34/31/36 and 47/37/39/28 on both fixtures): `[wor] grind done f50293
after 17 legs: CELES L30 HP 1281/1495 MP 290/290 ...; SABIN L30 HP
1509/1509 MP 278/278 ...; potion=59 fenix=29 ... gil=225443` against the
old chain's `after 37 legs: CELES L30 HP 1495/1495 MP 290/290 ...;
potion=56 fenix=28 ... gil=249815`. CELES's missing Ice 2 is never cast
here: neither chain plans Magic in a cave fight (Fight, a Cure, an item or
a deferred Muddled window; `analysis/cave_plans_*.txt`). The shorter grind
leaves CELES at L31 rather than L32 at the Tentacles. On the same
instrument the two chains' cave is the same: from the cave mouth, 33 runs
of 6 battles, formation 232 won 161 of 162 (6 with a death) on the re-cut
chain and 163 of 164 (9) on the old (`arms/new_base_c68`,
`arms/old_base_c68`; the old chain's run reproduces #320's `base_c68`
line for line). The old K = 0-10 set on this ROM passes 11 of 11 again
(`oldchain_snap/`), the re-cut one 9 of 11, plus 4 of 4 at shifts 23/41
(`before_snap/`). What moved is the draw: the frame phase each battle
seeds from (InitBattle takes `$021e`, the game clock's frames, 0-59) and
the encounter counter, and three things that draw finds:

- **Back attacks and pincers.** They turn the pair's back row to the
  front, and a Muddled ally's Genji pair and the monsters' blows land in
  full. In the lab 4 of 96 back attacks and pincers of formation 232 were
  lost against 2 of 555 normal fights, and the old chain's one lab loss
  is a back attack (`analysis/battle_type_lab_new.txt`, `arms/old_base_c68`).
  In the re-cut chain's generator runs (the recut, `before_snap/`,
  `after1/`) its 11 back attacks cost a member in 5 and were lost twice
  (one draw, K = 3 at shift 23, met twice), its 139 normal fights lost 3
  (`analysis/battle_type_*.txt`; `before_snap/k9_s0` has no `[outcome]`
  line). The bag holds a Back Guard ($E1, the relic
  #250 put on CELES for Tzen's house, where it goes on before the house's
  clock, so no pincer happens there): on CELES in place of her Jewel Ring,
  330 lab fights, all normal, none lost, 6 with a death
  (`arms/new_bg_nocure_c68`, `arms/new_bg_ringnow_nocure_c68`).
- **The cure-hit with the Peace Ring on.** With SABIN's ring on, Muddle
  lands on CELES and SABIN's cure-hit is a Genji pair: `[unmuddle] actor 1
  (char 5)'s hit on entity 0 took 947 (1038 -> 91)`, and a monster
  finished her (`arms/new_ringnow_c68/er_k1_s0_c68_w41.log`). The ring on
  as soon as Muddle is seen lost 4 of 159 with the cure-hit and 0 of 165
  without it (7 fights with a death against 2); bare, 1 of 162 and 1 of
  165. SABIN's measured cure-hits are mostly 175-277 but 739-988 in 10
  of 80 (`analysis/cure_hits.txt`), against the rule's unmeasured floor
  of a quarter of the ally's max HP (373-398). A monster's hit clears Muddle the same way.
- **A random battle between the stop and Gerad.** The three steps up from
  the engine room's door met one after the stop's care in 8 of the 23
  re-cut runs that got there and none of the old chain's 26
  (`analysis/tent_entry.txt`; `before_snap/k7_s0.log` opened the Tentacles
  at `partyhp=1129,1263,1600`). From the engine room's snapshots the
  Tentacles were won 24 of 24 without such a battle and 15 of 18 with one
  (`tent/new_base/`); topped up on the tile below Gerad, 42 of 42
  (`tent/new_topup/`).

**What changed.** gen_wor_edgar wears the Back Guard on CELES from the
cave's door to the stop before Edgar and again after the Tentacles (her
Jewel Ring back for the Tentacles and the save; the Peace Rings go to
SABIN and EDGAR). That is informed: it goes on at the door whatever the
run has met, on the lab numbers above. The lineage has been pincered on
the way here (the re-cut captures: 1 pincer in `wor-tzen-door-v1.log`, 2
in `wor-nikeah-v1.log`, `build/attempts/wt/recut/capture/`), but those
are draws, and the generator does not read them. It also leaves a Muddled ally to the monsters in the cave and
the basements (`unmuddle = false`, CAVE_FIGHT), and cares to full again on
the tile below Gerad. The leg under the same variation (K = 0-10 at shift
0, K = 0 and 3 at shifts 23 and 41; `after2/`): **13 of 15**; formation 232
fought 57 times, all won, none with a death, every battle a normal layout
(`analysis/cavestats_after2.txt`); the two losses are the Tentacles, from
full HP with no battle before them (`k8_s0`: `battle $1C6 LOST after 18804
ticks`, `k10_s0`: `LOST after 17612 ticks`). The same set with only the
top-up and no cure-hit (`after1/`) passed 12 of 15: the Tentacles twice
and formation 232 once, in the back attack every re-cut run with this
draw meets (`k3_s23`: `[layout] battle type $01 (back attack)`, the same
frames as the re-cut's). `wor-edgar-v1` is re-cut through the generator
(`capture/capture_edgar.log`: `PASS (frame 101654) attempts=1/3`, sealed
`bd3d3dce...`, `holds=slot 3 world 1 (81,86)`; the Continue probe passes).

**The Tentacles are lost now and then, more from some states than
others.** The fight's in-battle draw seeds from `$021e` (one of 60), but
60 waits from one engine-room snapshot did not reach 60 distinct draws:
counted by battle key (`$be` with the group and the encounter counters,
the runner's `[seed] first battle` line), the two re-cut states at
L31/31/31 won 59 of 60 runs over 39 distinct keys, 38 all won and one
key won once and lost once (`tent/sweep60_k0`), and 54 of 60 over 40
keys, 4 of them lost every time (`tent/sweep60_k2`); across the re-cut
chain's generator runs 45 of 52 (runs, not keys: a generator log keys
only a run's first battle). The grind to L32 (48-52 legs against 17)
meets the Tentacles at L33-34 and won 59 of 60 from each of its K = 0
and K = 2 states: 49 keys with 1 lost, and 44 keys with 1 won once and
lost once (`tent/sweep60_L32_k0`, `tent/sweep60_L32_k2`). So 2 of 93
keys lost at L32 against 5 of 79 at L31 (118 of 120 runs against 113 of
120): suggestive of a gain from levels, from two states each, not a
measured null. The old chain's L32/31/31 states lost 4 of 33, 33
distinct keys (`tent/old_base`); the cave at L32 lost 2 of 176 against 2
of 150 at L30 from the same two draws (`arms/L32_base_c68`,
`arms/L30_k02_c68`). The grind stays at L30. (Key counts:
`build/attempts/wt/edgar-honest/tent_keys.txt`.)

## 13. What is left, and what the owner may want to decide

- **The Tentacles** (12.2, 12.5): lost from full HP at a rate that
  depends on the state: 1 of 39 and 4 of 40 distinct draws in two L31
  states' sweeps (1 and 6 of 60 runs), 7 of 52 re-cut generator runs;
  most deaths the Seize's drain (`cmd $2D`). A lab on the Seize (who acts
  while a member is held, and whether Air Blade's turns are the right
  ones) is the next step. A grind to L32 lost 2 of 93 distinct draws
  against 5 of 79 at L31, from two states each: suggestive, not settled.

- **The cave's Muddle** (12.4): with the Peace Rings the pair still
  loses 1 or 2 formation-232 fights in about 165 in the lab, each with
  CELES Muddled; the fights that cost a member went
  from 9 in 164 to 2, and the Drops from a third lost to none. The cure-
  hit itself is the next lever: SABIN's Genji pair lands 900 on CELES, and
  lands even when a monster has cleared the Muddle first; switching it
  off read the same at this size (1 loss against 2). SABIN's blitz
  (Air Blade, Fire Dance) in these fights was not measured.
- **The South Figaro desert** (world group 44) is off the grind: its Sand
  Horse pair was won 6 times and lost 2 (12.1), both losses with the
  horses untouched while the pair healed and revived into Sand Storm. That
  is a driver finding (the revive rule's smallest-hit judgement; turns
  spent on care against a pair that must be killed) and a lab candidate
  (first-attempt rate over distinct draws, the driver as is and changed),
  not a level wall. The stretch after this one leaves the castle into
  that desert with EDGAR.
- **South Figaro's rich man's basement passage** (maps 83, 84, 87, 89) is
  not walked: the offline model finds no way across 84 or 89, and no live
  visit was made (2.4).
- The **Hero Ring** in map 90 (52,14) is not reachable from where the
  crossing leaves the party (`no neighbour reachable from (47,25)`); the
  **Regal Crown** in map 66 (by basement 2's (4,6)) is not visited.
- The supply band after the leg: Potions 32-49 at the save across the
  set (34 in the capture), under the combat band at L31 (47) in most
  runs; the castle's shops refuse this party, so the next arc's first
  stop is South Figaro's.

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

### 12.6 The Tentacles, labbed again on the v0.25 chain (#333)

The mechanics, decoded (`build/attempts/wt/v026-route/tentacles/mechanics.md`):
all four bodies Seize, and only a Slowed member (each one's Special,
labelled "Seize", is Slow); a held member cannot act and cannot be healed,
and is released only by its holder's death or, after ~1000-1900 frames, a
Discard.  The informed kill order is $13E, $13D, $13C, $11B (fastest,
most-Slowing, lowest HP first).  Played from two engine-room snapshots
of `gen_wor_edgar`'s own run (shifts 0 and 23; CELES L32, SABIN L31) with
the stop's care below Gerad, waits 1-60 each, retries off
(`tentacles/lab/keys.txt`, by distinct battle key):

| arm | snapshot s0 | snapshot s23 |
|---|---|---|
| shipped (Air Blade, the driver's own targets) | 51 keys, 1 lost | 54 keys, 1 lost |
| the kill order above (`focus`), Air Blade | 51 keys, 0 lost | 54 keys, 2 lost |
| the kill order, SABIN's default Pummel | 51 keys, 4 lost | 54 keys, 5 lost |

On this chain the Tentacles are won from full about 103 draws in 105 as
shipped, not the ~1 in 10 lost the old chain measured; the kill order is
no measured improvement (2 of 105 either way) and dropping Air Blade for
Pummel is worse (9 of 105).  So the generator keeps its plan.  What the
losses show (mechanics.md, section 4) is driver-side: heals aimed at held
members, Fenix raises to 200 HP with no follow-up, a body one hit from
death left standing -- filed for the driver's owner.
