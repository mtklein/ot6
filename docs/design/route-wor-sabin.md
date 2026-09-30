# World of Ruin: the raft landing to Sabin (Tzen)

The route from the first World of Ruin save (Celes alone where the raft
from the Solitary Island lands) to Sabin joining in Tzen, and on to the
first save after he joins. It is planned from the game's own data. The
route is driven: section 10 records what `gen_wor_tzen_door` measured
from the landing to Tzen's door (`wor-tzen-door-v1`), and section 11 what
`gen_wor_sabin` measured from there through the house to the first save
with Sabin (`wor-sabin-v1`).

Line numbers are into `ff6/src/event/event_main.asm` unless a path is given.
Decodes come from `tools/route_data.py` (added with this doc: entrances,
triggers, chests, NPCs, encounter pools, species, shops, items, the party in a
savestate, and an offline copy of the field BFS). Its output, and the small
analysis scripts that produced the tables, are kept under
`build/attempts/wt/wor-sabin-route/` (the `analysis/` scripts run from a tree
root). The labels are the ones the Floating Continent route uses:
**verify-on-arrival** marks an offline decode that holds unless the data
moved, **UNVERIFIED** marks a claim that needs a live read, and **estimate**
marks a vanilla-formula number that the driving will replace with a
measurement.

---

## 0. Findings

1. **Celes lands with no equipment.** The Floating Continent exit runs
   `remove_equip` on all thirteen playable characters (`:11979-11991`), and
   the fixture she came from shows every one of her slots empty
   (`gear: -, -, -, -, -, -`, `party_wor_landing.txt`). Her bag holds a full
   kit (§5.2). The Solitary Island segment `gen_wor_island` dresses her
   before its save (`docs/design/wor-start.md`), so `wor-start-v1`'s Celes
   wears `11 0E 76 8F D1 C1` (Break Blade, Blizzard, Gold Helmet, Gold
   Armor, Genji Glove, Czarina Ring).
2. **No story gates stand between the landing and Tzen.** The raft
   drops her on the World of Ruin map at **(146,212)** (`:13014`). Albrook's
   door is 20 steps away, Tzen's is 41 steps beyond that, and the direct
   walk from the landing to Tzen is 49 steps. Albrook is an optional supply
   stop: nothing in it sets a switch that the Tzen events read (§2).
3. **Walking into Tzen commits the party.** The Light of Judgment
   trigger (22,25)/(23,25) cannot be avoided on the way in, and once it has
   run, the only way out of town crosses a trigger at (22,28)/(23,28) that
   bounces the party back ("Come on!! Please help!") until Sabin has
   joined. The last save before the timed scene is therefore the world map
   outside Tzen (§2.4, §7).
4. **The house timer is 6:00 and it does not pause.** Stepping onto (16,9),
   in front of the house where Sabin holds it up, starts `start_timer 0, 21600, _cc592e, {FIELD_VISIBLE, BANQUET,
   MENU_BATTLE_VISIBLE}` (`:90010`). That is timer 0 at `$1188-$118D`,
   counting down from 21,600 frames. Its "pause in menu and battle" bit is
   clear, so the timer runs through menus and battles. Its BANQUET bit makes
   an expiry end a battle on the spot (`battle_main.asm:12217-12221`). On
   expiry `_cc592e` runs the collapse and calls `GameOver` (`:90038`). The
   timer stops (`stop_timer 0`, `:90071`) when the party comes back out of
   the house with the child (§3).
5. **Inside the house** (map 311) the child is 70 steps from the door and
   the exit is 71 steps back, across two floors joined by same-map
   entrances. The rescue is a "face up and hold A" trigger at (117,12). The
   141 steps draw about 2.8 random battles from Scorpion ×3 or
   HermitCrab ×2 + Pm Stalker (§3, §4.3).
6. **Four statuses on this stretch lose the fight outright for a party of
   one.** Death, Petrify and Zombie take a character out of the alive mask
   (`battle_main.asm:12625-12626`), and Condemned ends in death. The
   Osprey's Beak petrifies (route-wide), a lone surviving HermitCrab
   counters with Rock (petrify), the Scorpion opens every fight with Doom
   Sting (Condemned), and the Black Drgn on the desert tiles beside Tzen
   inflicts Zombie. Celes carries three Jewel Rings (petrify protection).
7. **No shop on this stretch sells Tonics.** Albrook (shop 48) and Tzen
   (shop 54) stock Potions, Fenix Downs and Tinctures, and only Albrook
   sells Remedies (§5.4). During the timed scene Tzen's innkeeper heals the
   party for free (`_cc5c8d`, `:90562`).
8. **The shipped break data did not suit this stretch** (the rows §8
   designs are authored since 2026-09-22). Every species on it rode the
   generated floor at 4-5 shields
   (`audit_break_coverage.txt:275-277, 623-656`). Scorpion ×3 and the
   HermitCrabs gave a sword-carrying Celes no key at all (their floor class
   is pierce, which she holds only on 26-30-power daggers). That covered
   **62.5 %** and **37.5 %** of the house's draws.
9. **Espers grant spells while they are worn.** This is OT6's M5 rule
   (`ff6/src/menu/genju_prop.asm:53-63`). Maduin, which is in Celes's
   collection, gives her Fire, Ice and Bolt, so a solo Celes holds all three
   elements. Tzen sells Seraphim for **10 GP** (`_cc5df4`, `:90781`).
10. **Sabin joins with no equipment**, at `max(26, Celes's level)`
    (`norm_lvl` raises and never lowers; `field/event.asm:857-886`). The
    first save after he joins is on the world map outside Tzen, 35 steps
    and a door from where control returns (§2.6, §7).
11. **Driven to Tzen's door** (§10, 2026-09-23): the back row, Maduin, the
    Blizzard + ThunderBlade Genji pair and a Jewel Ring; Albrook before
    and after a grind to L27; seven plains fights won, none lost, no Fenix
    Down, the walk off the sand; saved at (131,179). Two plan items moved
    on measurement: the back row beat the front on the same walk, and the
    Chitonid, not the Osprey, is the body to take first (with the Jewel
    Ring the Beak costs nothing; the Chitonid's Sneeze fires on its own
    killing blow once one other body is left).
12. **Driven through the house to Sabin** (§11, 2026-09-28): the Seraphim
    stone, the Back Guard in the Genji Glove's slot for the house, the
    timed scene played by a driver that reads the clock, the child by
    "face up and hold A", Sabin dressed, saved at (131,179).  Three plan
    items moved on measurement: pincers and back attacks came in 5 of 54
    house fights with the Genji kit (ChooseBattleType's odds are 16 in
    224), and both pincered Scorpion trios killed the lone CELES (177-186
    a hit); the clock, not the
    statuses, is the house's thin margin once the Back Guard is on (the
    fights run longer without the Genji pair); and a Scorpion's Doom is a
    real race with one hand (a fight ended 354 ticks before it).

---

## 1. The start state (`wor-start-v1`)

The raft scene is the `_ca55fe` chain (`:12854`, the NPC at 397 (85,51),
`npc_prop.asm:17578`). It ends:

```
event_main.asm:13014   load_map 1, {146, 212}, UP, {ASYNC, Z_UPPER}
               :13015   set_script_mode WORLD
```

Before that `load_map` it sets the NPC switches `$0374 $037A $0382 $0397 $0276
$02B7` and clears `$036D $0367 $0373 $0379 $0380 $0381` (`:13002-13013`). The
scene only plays once Cid's thread has ended, either fed (`$00B3`) or dead
(`$00B4`), and both ends stop the Cid clock
(`start_timer 0, 64, _ca533f, FIELD_ONLY`, `:12448`): `_ca5713` (`:13022-13023`)
when he is fed, and `_ca5419` (`:12528-12533`) when he is not. So at the landing:

| thing | expected value | how to assert it on arrival |
|---|---|---|
| map / position | world 1, (146,212) | `$1F64` low byte 1; `$E0`/`$E2` |
| party | CELES alone | `$1850+6` party bits; no other member with party bits |
| World of Ruin | `$00A4=1` (`:12423`) | switch read |
| event timers | none live | `$1189/$118F/$1195/$119B` all 0 (the harness's `eventTimerLive`) |
| equipment | `11 0E 76 8F D1 C1` (finding 1; the cold Continue logs `kit 11 0E 76 8F D1 C1`) | `$161F..$1624` for char 6 |
| Tzen switches | `$027D=0 $028A=0 $028B=0 $028C=0`; `$066C=1` (Sabin shown) | `roster_wor_landing.txt` |

The fixture that precedes the checkpoint (`build/states/wor_landing.mss`, at
the Solitary Island bedside) holds the World of Balance party that Celes came
from (`roster_wor_landing.txt`):

```
  TERRA   L27 maxHP 1207 gear FF FF FF FF FF FF party byte $20
  LOCKE   L30 maxHP 1499 gear FF FF FF FF FF FF party byte $00
  SHADOW  L25 maxHP 1050 gear FF FF FF FF FF FF party byte $00
  EDGAR   L28 maxHP 1306 gear FF FF FF FF FF FF party byte $20
  SABIN   L26 maxHP 1139 gear FF FF FF FF FF FF party byte $20
  CELES   L25 maxHP 1043 gear FF FF FF FF FF FF party byte $E1
  STRAGO  L26 maxHP 1116 gear FF FF FF FF FF FF party byte $20
  switch $037D = 1  (Shadow saved)
  timer 0: flags $80 counter 5
  encounter counters $1FA1..$1FA5 = 86 F6 ED FE ED; danger $1F6E = $0310
```

(The `timer 0` there is Cid's clock at the bedside, which the island segment
stops. Celes's 44,072 XP is exactly the L25 total in `LevelUpExp`, because
the WoR opening's `norm_lvl CELES` (`:12427`) raised her to the roster
average.)

From `gen_fc_escape`'s log (`build/states/wor_landing.log`):

```
[ot6] landing: map=397 (99,38) party=1 hp=1043 $00A4=1 $037D=1
[ot6] ok: the party is Celes alone = 1
```

---

## 2. The legs

| # | leg | from → to | steps | encounters | gate |
|---|---|---|---|---|---|
| 1 | landing → Albrook | world (146,212) → (140/141,209) → map 324 (2,17) | 20 | world groups 34 (14 steps) and 31 (5) | none |
| 2 | Albrook (optional) | shops, inn | 8-70 to each door | none (map 324 off) | none |
| 3 | Albrook → Tzen | world (141,209) → (130,179) → map 305 (23,29) | 41 | world groups 31 (29) and 34 (11) | none |
| 3' | landing → Tzen direct | (146,212) → (130,179) | 49 | groups 34 (23) and 31 (25) | none |
| 4 | Tzen, the Light of Judgment | 305 (23,29) → (22,25)/(23,25) | 4 | none | `$027D` 0 → 1 |
| 5 | Tzen prep | the inn (free heal), shops, Seraphim | 5-27 | none | `$027D=1` |
| 6 | Sabin at the house | 305 → (16,9) | 23 from the LoJ tile | none | starts timer 0; `$028C=1` |
| 7 | the house | 305 (16,7) → 311 (123,60) → child (117,12) → exit (123,61) | 70 + 71 | map 311, group 128 | face up + A; `$028B=1` |
| 8 | Sabin joins | exit → 305 (16,9) → cutscene → 305 (15,14) | — | none | `stop_timer 0`; `$028A=1`, `$02F5=1` |
| 9 | out to save | 305 (15,14) → exit row y=31 → world (130,179) | 35 | — | `$028A=1` disarms the bounce |

World steps come from an on-foot BFS over `world_2_tilemap.dat` and
`WorldTileProp` (bit `$10` blocks on foot), recorded in `world_paths.txt`:

```
world 1: on-foot BFS (146,212) -> (141,209): 20 steps (world_2_tilemap.dat, WorldTileProp bit $10)
  14 steps: sector (4,6) bg 5: WorldBattleGroup[467] = group 34; rate code 0 ($00C0/step x Ot6DangerMulW -> $0060; mean 33.6 steps)
  5 steps: sector (4,6) bg 4: WorldBattleGroup[464] = group 31; rate code 0 ($00C0/step x Ot6DangerMulW -> $0060; mean 33.6 steps)
world 1: on-foot BFS (141,209) -> (130,179): 41 steps (world_2_tilemap.dat, WorldTileProp bit $10)
world 1: on-foot BFS (146,212) -> (130,179): 49 steps (world_2_tilemap.dat, WorldTileProp bit $10)
```

Field steps come from `route_data.py field-path`, the offline copy of
`ot6_field.lua` `stepAllowed`, recorded in `field_paths.txt`. That model does
not apply map-init `mod_bg_tiles` and does not model NPCs, so every field
count is **verify-on-arrival**.

### 2.1 Landing → Albrook

The world entrances are `ShortEntrance` records of map 1
(`world_entrances.txt`):

```
world 1 (140,209) -> map 324 'ALBROOK' (2,17) flags $1B
world 1 (141,209) -> map 324 'ALBROOK' (2,17) flags $1B
world 1 (130,179) -> map 305 'TZEN' (23,29) flags $0B
```

Flags bit `$02` (the `$0200` bit of the map word) sets the parent map
(`field/entrance.asm:297-300`), so the town's edge exits (`map 511`) return
the party to the world where it entered. The only WoR world triggers are at
(81,85), (53,58) and (73,231), none of which is on this continent's route
(`world_triggers.txt`). From the landing, the continent's on-foot component
also reaches Mobliz, Nikeah and two chocobo stables. None of them is on this
route.

`world_corridor.txt` shows the terrain. The route crosses only bg 4
(grass: group 31) and bg 5 (plain: group 34) tiles, all at rate code 0:

```
179 dddpppTpgggggp###ppppp######
180 pddddddppgggg####ppppp######
181 pddddddpppggp####ggpppp#####
...
209 gggggggppppp##ppAAp##p####pp
...
212 ffffgpppppp####ppp##ppLpppp#
```

(x runs 124..151; `L` is the landing, `A` Albrook, `T` Tzen, `d` desert.)

### 2.2 Albrook (map 324, optional)

It has the same doors as the WoB copy (323), with WoR `mod_bg_tiles` at
init (`_cc5b01`). It has no random battles
(`maps.txt: map 324 'ALBROOK': random battles off`). Everything the stop
offers:

| what | where | event | BFS from (2,17) |
|---|---|---|---|
| item shop 48 | door (7,13) → 328 | `_cc60ba` `:91222` | 8 |
| weapon shop 49 | door (23,19) → 326 | `_cc60a2` `:91208` | 28 |
| armor shop 50 | door (39,19) → 327 | `_cc60c6` `:91229` | 46 |
| relic shop 51 | door (44,12) → 330, keeper (37,25) | `_cc60ae` `:91215` | 60 |
| inn, 300 GP | door (54,12) → 325 | `_cc614a` → `_cc62a6` `:91503` | 70 |
| chests | Potion (56,13); Tincture (326 (11,49)); Elixir (330 (35,7)) | bits `$062 $064 $067`, all closed at the landing | — |

The townsfolk's WoR lines are colour. `_cc5bf9` points north to Tzen
("He said he was going north, to Tzen"), and nothing sets a switch that Tzen
reads. Map 330's `_cc607a` → `_cc5b79` is a flashback when talked to: it
loads 330 with `$0661` and plays a scene.

### 2.3 Albrook → Tzen, and the desert beside the door

The BFS path ends by approaching the door along row 179 from the east:
`... 136,180 136,179 135,179 134,179 133,179 132,179 131,179 130,179`. Tzen's
door has **desert directly south and south-west of it**: the `d` block at
x 124-130, y 177-182 in `world_corridor.txt`, starting at (130,180) and
(130,181). Sector (4,5)'s part is the seven tiles
`(128,180) (128,181) (129,180) (129,181) (129,182) (130,180) (130,181)`, and
sector (3,5)'s part (`WorldBattleGroup[430]`) is the same group. Those tiles
draw world group 36, which is formation
194 (EarthGuard + Peepers ×2, 62.5 %) or **formation 195, a lone Black Drgn
(37.5 %)**: L26, 4000 HP, BonePowder = Zombie. That is a loss for a party of
one (§4.2). **Approach Tzen along row 179 and never step south of the door.**
`worldNavTo` has no avoid-tiles option (its `blocked` edges are learned
from refused steps, `ot6_field.lua:1113`), so the walk goes by waypoints
(the bend at (136,179), then the door) or the lib grows an avoid set.

### 2.4 Tzen (map 305): arrival, the Light of Judgment, preparation

- **Map init** `_cc56da` (`:89751`, `map_init_event.asm:324`). With
  `$028A=0` it draws the pre-collapse house (`_cc56ef`, `mod_bg_tiles`) and
  puts Sabin (NPC_2 at (15,8), show-switch `$066C`) in his "holding" pose.
- **(22,25)/(23,25) → `_cc583e`** (`:89859`, `event_trigger.asm` map 305)
  plays the Light of Judgment. It is gated only by `if_switch $027D=1,
  EventReturn`, and it ends with `switch $027D=1 $0668=0 $066A=1 $066D=1
  $0667=0` and `player_ctrl_on` (`:89944-89951`). It is **unavoidable**:
  `field-path 305 23 29 21 22 --avoid 22,25 23,25` finds no path
  (`field_paths.txt`).
- **(22,28)/(23,28) → `_cc58d4`** (`:89953`) is the bounce. It returns unless
  `$027D=1` and `$028A=0` (`:89954-89956`); when it fires it plays "Come on!!
  Please help!" and moves the party up one tile. Every path out of town
  crosses those two tiles (`tzen_exit.txt`:
  `from (16, 9): to the south exit row (29, (23, 31)); avoiding (22,28)/(23,28) (None, None)`),
  so after the Light of Judgment the party cannot leave until Sabin joins.
- **Between the Light of Judgment and (16,9) no timer is running**, so this
  window is the prep stop. Menus are fine here. From the LoJ tile, avoiding
  (16,9) (`field_paths.txt`):

| what | approach tile | steps | event |
|---|---|---|---|
| inn → 308; keeper NPC at (14,53) | (28,19) | 9 | `_cc5c8d` `:90562`: while `$027D=1 && $028A=0`, **free** `RestoreParty` ("All I can do now is restore your health…"); else 350 GP |
| item shop 54 → 307 (34,15) | (21,22) | 5 | `_cc5c81` `:90555` |
| weapon shop 52 → 309 (38,43) | (6,23) | 23 | `_cc5ce2` `:90610` |
| armor shop 53 → 310 (58,45) | (8,18) | 20 | `_cc5cee` `:90617` |
| relic shop 55 → 312 (80,16) | (25,8) | 19 | `_cc5cfa` `:90624` |
| **Seraphim** for 10 GP, NPC_1 at (29,3) | (28,3) | 27 | `_cc5ddd` `:90769` → `_cc5df4` `:90781` (dlg `$0622`, a Yes/No choice; `$027C=1`) |

- **(16,9) → `_cc58ff`** (`:89985`) starts the timed scene. With `$028C=0`
  and Celes in the party (`$01A6`) it shows dlg `$08A7` ("CELES: SABIN!") and
  `$08A9` ("…save the child that's in there…"), starts the timer (`:90010`),
  sets `$028C=1` and returns control. From then on (16,9) does nothing until
  `$028B=1`.

### 2.5 The house (map 311)

Door 305 (16,7) → 311 (123,60) (`maps.txt`). The route and the timer are
covered in §3.

### 2.6 Sabin joins

Coming out, the exit trigger (123,61) → `_cc5c59` (`:90541`) loads 305 at
(16,9) (`:90545-90546`), which is the Sabin trigger. With `$028B=1`,
`_cc58ff` jumps to `_cc5980` (`:90069`). That scene does `stop_timer 0`
(`:90071`), plays "SABIN: Wait!" and the collapse, and then:

```
event_main.asm:90262   switch $028A=1
               :90267   switch $0668=1 / $066C=0 / $066A=0
               :90272   call _cac5c1
               :90273   if_switch $01A3=1, _cc5aad      ; a full party: Sabin is not added
               :90275   char_party SABIN, 1
               :90278   norm_lvl SABIN
               :90279   max_hp SABIN / max_mp SABIN / and_status SABIN, NONE
               :90282   switch $02F5=1
               :90283   load_map 305, {15, 14}, DOWN, ...
```

`norm_lvl` (`field/event.asm:857-886`) raises the character to the average
level of the *available* roster (`CalcAverageLevel`, `:892-934`, over
`$1EDE`), and only when that average is higher. At this point the available
roster is Celes alone: the landing fixture has `$1EDE = $8040`, and the loop
stops at 14 characters. So **Sabin joins at `max(26, Celes's level)`**,
with full HP and MP and his blitzes updated to that level (`UpdateAbilities`,
`BlitzLevelTbl` 1,6,10,15,23,30,42,70, `field/event.asm:1239`). The roster
fixture has 5 known (`$1D28 = $1F`). Air Blade comes at 30. He has **no
equipment** (finding 1).

Whether the load onto (16,9) fires the trigger is vanilla behaviour, and the
scene is the one players know. It is **verify-on-arrival** for the harness.

### 2.7 To the next save

Control returns at 305 (15,14). The exit row is 35 steps away
(`field_paths.txt: map 305: BFS (15,14) -> (23,31) ... 35 steps`), through
(22,28)/(23,28), which `$028A=1` has disarmed. Leaving by the long entrance
(13,31) len 18 → `map 511` returns the party to world (130,179). Before
leaving, Tzen's weapon, armor and relic shops can equip Sabin (§6).

---

## 3. The collapsing house

### 3.1 The timer

| property | value | source |
|---|---|---|
| command | `start_timer 0, 21600, _cc592e, {FIELD_VISIBLE, BANQUET, MENU_BATTLE_VISIBLE}` | `:90010` |
| RAM | timer 0: flags `$1188`, counter `$1189-$118A`, event `$118B-$118D` | `ff6/notes/field-ram.txt:684-690`; `EventCmd_a0`, `field/event.asm:3736` |
| start | 21,600 frames = 6:00 | — |
| flags byte | `pfrm----` = `%0111`: p = 0 (**does not pause** in menu or battle), f = 1 (shown on the field), r = 1 (BANQUET: end a battle at 0), m = 1 (shown in menu and battle) | `ff6/include/event_cmd.inc:681-695` |
| field tick | `DecTimers`, one per frame | `field/event.asm:5656` |
| menu/battle tick | `DecTimersMenuBattle`: decrements unless `p`; at 0 with `r` it sets `$1DD1` bit 5 | `field/event.asm:5562-5650` |
| expiry in battle | `CheckBattleEnd` sees `$1DD1 & $20` and ends the battle | `battle_main.asm:12217-12221` |
| expiry | `_cc592e`: `load_map 305 {15,9}`, "I'm losing my grip…", collapse, `call GameOver` | `:90014-90038` |
| stop | `stop_timer 0` when the party exits with the child | `_cc5980`, `:90071` |

**Menus inside the timer:** vanilla allows them and the clock keeps running.
The guideline is no menus inside a live event timer, and the harness already
holds menus out while any counter is nonzero (`ot6_field.lua`
`eventTimerLive`, mechanics-coverage "Timed scenes" HANDLED). Field care
inside the house is therefore impossible by policy, and the heals available
there are Potions in battle (`Item`) and the free inn outside (§2.4).
**Saving** is impossible anyway, because neither 305 nor 311 has a save
point.

### 3.2 The layout

The house is map 311. Its BG1 is `thamasa_int_bg1` with the `town_int` tile
properties (`house_map.txt`). It has two floors joined by same-map
entrances: (102,53) → (125,23) up, and (126,22) → (103,52) down.

```
map 311 reachable from the door (123,60): 412 tiles, x 101..127, y 11..62
 12           C..  .K***  ..C
 13          ..........******.
 ...
 22              .       *   L
 23              .       *  L
 24              .       ***
 25           .......   ...
 26          ........C  ......
 ...
 43  ..C...   ......      C.
 44  .........................
 45  ....*****************....
 ...
 52   L ..  .  .......     *
 53  L  ..  .  .......     *
 ...
 58   C..............   ..**..
 59  .................  ..**..
 60  ....... .........  ..D*.
 61                       X
```

(x starts at 101. `D` is the door in, `X` the exit trigger, `K` the child
trigger, `C` a chest, `L` a link, `*` the shortest route.)

- **Door to child:** 70 steps. **Child to exit:** 71 steps. That is
  **141 steps**, about 2,256 frames at 16 frames a step
  (`docs/playing-headless.md:191`).
- **The child** is NPC_2 at (117,10) (show-switch `$066D`, which the Light of
  Judgment set; `npc_prop.asm:13564`). The rescue is trigger (117,12) →
  `_cc5958` (`:90040`):
  `if_any $01B0=0 / $01B4=0 / $028B=1 → return`. `$01B0` is "facing up" and
  `$01B4` is "A held" (`vector-route.md` §7). The party has to stand on
  (117,12) **facing up with A held**. `navTo` never presses A on the open
  field, so this needs its own step. The pattern is `gen_terra_caves.lua`'s
  "examining" step (`:100-130`), which is generator-local today. On success
  it plays "I'm scared…!", hides the child, and sets `$066D=0` and `$028B=1`.
- **Leaving without the child** is allowed. The exit trigger returns the
  party to 305 (16,9), where `_cc58ff` returns at once because `$028C=1`, and
  the clock keeps running. That is how the free inn heal is reached
  mid-scene: about 26 steps each way between (16,9) and the inn door
  (`field_paths.txt: map 305: BFS (28,19) -> (16,9) ... 26 steps`), plus the
  few steps to the keeper and the heal scene. **estimate:** about 25 s of the 6:00.

### 3.3 The budget

The house rolls group 128 (`map 311 ... random battles ON`) at rate code 0:
`$0070/step × Ot6DangerMulW (8/16) → $0038` (`maps.txt`). The
encounter-count distribution under the danger-counter model is in
`encounter_budget.txt`. The draw byte is modelled as uniform; a real save's
draws are fixed by `$1FA1` (`docs/TESTING.md`).

```
house 311: both ways: 141 steps, mean 2.78 battles; P(0)=0.000 P(1)=0.059 P(2)=0.346 P(3)=0.393 P(4)=0.164 P(5)=0.033 P(6)=0.004
house 311: both ways + ~20 steps of chest detours: 161 steps, mean 3.22 battles; ...
```

**estimate:** walking takes about 2,300 frames. At a guessed 1,500-3,000
frames per solo battle, three battles bring the total to roughly
6,800-11,300 of the 21,600 frames. The margin is comfortable *if no fight is
lost*. The real risk is not the clock but the statuses (§4.3). A timed
segment should log the timer at every battle's start and end, so that the
margin is measured.

### 3.4 Chests

Chests from `TreasureProp` (bit, contents), with their distance off the
shortest route (`house_map.txt`). All bits are closed at the landing:

| chest | contents | off route |
|---|---|---|
| (125,12) | **Magicite** (item) | 1 |
| (123,43) | Heal Rod (Strago/Relm/Gogo only) | 3 |
| (102,49) | **monster box**: event group 150 → formation 211, Pm Stalker ×4 | 3 |
| (104,43) | Tincture | 4 |
| (112,49) | Pearl Rod (Strago/Relm/Gogo) | 4 |
| (103,58) | **Hyper Wrist** (vigor +50 %) | 6 |
| (118,26) | **Drainer** (Celes; power 121, the best sword she can hold here) | 6 |
| (111,12) | monster box, as above | 6 |

A monster box starts an event battle (`EventCmd_8e`, `field/event.asm:1836`)
that the clock runs through. It is not a random battle, so it earns no ×2
reward (`Ot6MarkRandom` marks only the random paths). Skip both boxes under
the timer. The Magicite, Drainer and Hyper Wrist are worth their few steps.

---

## 4. Encounter pools

Decoded by `route_data.py pool` (`pools.txt`). The world pool is
`WorldBattleGroup[world·256 + (y & $E0) + ((x >> 3) & $1C) + BattleBGGroupTbl[bg]]`
(`field/battle.asm:97-160`). Slot odds are 80/80/80/16 of 256
(`field/battle.asm:400-408` for field maps, `:187-195` for the world). XP shown is vanilla, and a random
battle pays ×2 (`Ot6RewardMulW`, `ot6_break.asm:369`). Every rate on the route
is code 0 (`$00C0` world, `$0070` field, both halved by `Ot6DangerMulW`,
`ot6_break.asm:367`).

### 4.1 World groups on and beside the route

| group | where | p | formation | contents | XP |
|---|---|---|---|---|---|
| **31** | grass (bg 4), sectors (4,5)/(4,6) | 62.5 % | 197 | Mesosaur ×2 | 918 |
| | | 37.5 % | 199 | Gilomantis, Mesosaur | 1018 |
| **34** | plain (bg 5), sectors (4,5)/(4,6) | 62.5 % | 202 | Lunaris, Osprey | 557 |
| | | 37.5 % | 204 | Osprey, Chitonid, Gigan Toad | 805 |
| 33 | plain (bg 5), sector column x=3 (west of x=128) | 62.5 % | 203 | Lunaris ×2 | 616 |
| | | 37.5 % | 201 | Chitonid, Gigan Toad ×2 | 791 |
| 35 | forest (bg 1), x=3 column | 62.5 % | 198 | Mesosaur ×4 | 1836 |
| | | 37.5 % | 200 | Gilomantis ×2, Mesosaur | 1577 |
| 36 | desert (bg 2), **beside Tzen's door** | 62.5 % | 194 | EarthGuard, Peepers ×2 | 5 |
| | | 37.5 % | 195 | **Black Drgn** | 780 |

The route BFS crosses only 31 and 34. Groups 33, 35 and 36 are one wrong turn
away. The continent also has an oddity at sector (5,6) bg 5, 38 tiles east of
the landing: `WorldBattleGroup[471] = 0`, which is the WoB Leafer/Dark Wind
pool (L5). It is off route.

Arrangements: formations 197/199/201/203/198 permit back, pincer and side;
202/204/200/195 permit back and side. With fewer than three allies alive
the side attack is masked out (`battle_main.asm:7874-7880`), so a solo Celes
or the Celes+Sabin pair can meet only normal, back (about 3 %) or pincer
(about 3 %) layouts (`tools/audit_encounters.py` docstring). Pincers cannot be
fled. The Back Guard in the bag removes both (`battle_main.asm:7862-7873`).

### 4.2 The Solitary Island (before the start, for the break design)

The island is world 1 around (76,240): 70 walkable tiles, of which 62 are bg
5 (group 29) and 7 are desert (group 30). Group 29 is Peepers ×2 or ×3.
Group 30 is identical to group 36 (EarthGuard + Peepers ×2, or Black Drgn).

### 4.3 The house (map 311, group 128) and its monster box

| p | formation | contents | XP |
|---|---|---|---|
| 62.5 % | 209 | Scorpion ×3 | 597 |
| 37.5 % | 207 | HermitCrab ×2, Pm Stalker | 792 |
| box | 211 (event group 150) | Pm Stalker ×4 | 1032 |

### 4.4 The species

Species data are `MonsterProp` (+0 speed, +1 attack, +5 def, +6 mdef, +8 HP,
+16 level, +23 absorb, +25 weak, +31 special; `battle_main.asm` LoadMonsterProp
`:7601-7710`). The AI is from `ff6/src/battle/ai_script.asm`. Throughout
this doc, "today" means main before the §8 rows were authored (the v0.21
ROM): the row `Ot6SeedShields` seeded then (`ot6_break.asm:54-113`: no
authored row, so the floor class and `2 + level/8`). §8's rows are now
authored (battle_breakwor_sabin verifies them).

| id | body | L | HP | def/mdef | weak | absorb | AI (`ai_script.asm`) | solo-relevant | today |
|---|---|---|---|---|---|---|---|---|---|
| `$072` Peepers | — | 23 | 1 | 5/5 | ice\|water | — | Battle/Pearl Wind/Special `:1691` | — | floor 4 · slash |
| `$0B2` EarthGuard | — | 23 | 1 | 5/5 | water | — | PoisonTail `:1700` | Poison | floor 4 · pierce |
| `$0D5` Black Drgn | dragon | 26 | 4000 | 102/20 | fire\|holy | poison | B/B/Sand Storm, then B/**BonePowder**/Sand Storm `:1709` | **Zombie = loss** | floor 5 · pierce |
| `$021` Mesosaur | saurian | 26 | 1112 | 110/150 | ice | — | alone: B/T.Lash/T.Lash; else **Escape** ×2/3 `:1720`; counter to Fight (1 in 3): T.Lash | Sap | floor 5 · pierce |
| `$031` Gilomantis | mantis | 26 | 1412 | 115/140 | fire | — | B/B/— `:1737`; **counter to Fight (1 in 3): Sickle** (×1.5) | — | floor 5 · pierce |
| `$07C` Chitonid | plated shell | 26 | 1111 | 140/80 | bolt | — | B/B/Carapace `:1750`; when it is the last body and is hit (1 in 3): **Sneeze** | sneezed out = fight over, no reward | floor 5 · pierce |
| `$098` Gigan Toad | toad | 26 | 458 | 100/130 | ice | — | B/B/Croak (×2), Slimer (Slow), Rippler (swap) `:1762` | Slow | floor 5 · slash |
| `$0CA` Lunaris | — | 26 | 582 | 155/145 | **none** | — | B, then B/B/Face Bite `:1777` | Dark | floor 5 · slash |
| `$0E6` Osprey | flier (Float) | 26 | 850 | 105/120 | ice | — | B, B, then B/B/**Beak** `:1788`; counter to Magic (1 in 3): Shimsham (runic) | **Petrify = loss** | floor 5 · slash |
| `$0E1` Scorpion | — | 26 | 290 | **5/215** | none | — | **Doom Sting** and Battle on its first turn, then Battle `:1844` | **Condemned** | floor 5 · pierce |
| `$02C` HermitCrab | shell | 26 | 305 | 150/80 | water | — | B, B, then B/B/Net (Stop) `:1805`; when it is the last body and is hit (1 in 3): **Rock** | **Petrify = loss**; Stop | floor 5 · pierce |
| `$0C0` Pm Stalker | ghost (Float) | 26 | 265 | 140/115 | fire\|holy | poison | B/B/Drain, B/B/Slip Touch `:1868`; counter to Fight (1 in 3): **Drain (runic)** | Sap | floor 5 · slash |

Condemned: `StartCondemn` sets `$3B05 = max(0, 60 - (L + rand(0..L-1))) + 20`
(`battle_main.asm:1590-1602`). For an L26 Scorpion that is 29-54 counts. At
128 frames a count (`M.COUNT_FRAMES`, mechanics-coverage §C "Condemned") it
is about 3,700-6,900 frames, and no item clears it. It lasts for one battle.

None of the twelve appears in any WoB pool or event group, and none has an
`Ot6ShieldTbl` or `Ot6ElemAddTbl` row today (`species_sharing.txt`). The only
other uses are unused formations and the Pm Stalker box (event group 150).

---

## 5. Celes alone

### 5.1 What she has

From `party_wor_landing.txt` (`route_data.py party build/states/wor_landing.mss --chars 5`):

```
  CELES: L25 HP 1043/1043 MP 227/227 XP 44072 party byte $E1
    vigor 34 speed 34 stamina 31 magpwr 36; commands Fight, Runic, Magic, Item
    gear: -, -, -, -, -, -; weapon class bludg; esper -
    spells (6): Ice, Scan, Safe, Imp, Cure, Antdot
    can equip weapon: MithrilKnife (pow 30, pierce); Dirk (pow 26, pierce); MithrilBlade (pow 38, slash); Blizzard (pow 108, slash ice); ThunderBlade (pow 108, slash bolt); RegalCutlass (pow 54, slash); Break Blade (pow 117, slash)
    can equip armor: LeatherArmor (def 28/mdef 19); Mithril Vest (def 45/mdef 30); Gold Armor (def 55/mdef 37); Silk Robe (def 39/mdef 29)
    can equip shield: Mithril Shld (def 27/mdef 18); Heavy Shld (def 22/mdef 14); Buckler (def 16/mdef 10)
    can equip helmet: Bandana (def 16/mdef 10); Leather Hat (def 11/mdef 7); Plumed Hat (def 14/mdef 9); Hair Band (def 12/mdef 8); Gold Helmet (def 22/mdef 15)
    can equip relic: Czarina Ring; Jewel Ring; Peace Ring; Genji Glove; Black Belt; Star Pendant; Back Guard
  espers held: Ramuh, Ifrit, Shiva, Siren, Shoat, Maduin, Bismark, Stray, Kirin, Carbunkl, Phantom, Unicorn
```

Gil is 215,563. The bag has 68 rows, including Potion ×39, Fenix Down ×22,
Tonic ×4, Soft ×18, X-Potion ×3, Elixir ×5, Tent ×10, Tincture ×3,
Remedy ×1 and Genji Glove ×2.

### 5.2 A kit for the stretch

Levers, to be measured by the driving:

- **Weapon(s):** every sword she can hold is slash with the runic property
  (`items.txt`, e.g. `$0E Blizzard ... props swdtech,2-hand,runic`), so Runic
  stays lit with any of them. A **Genji Glove** pair of **Blizzard (ice) +
  ThunderBlade (bolt)** chips slash plus the element on every hit. That
  answers the plain's ice bodies and the Chitonid's bolt, and it doubles the
  hits of a boosted Fight (`guidelines.md` "Relics matter"). Break Blade
  (117) is the heaviest plain blade. The house's Drainer (121) is better.
- **Relics:** a **Jewel Ring** (Petrify, `items.txt: $B5 ... protects from
  Petrify`) against the Osprey's Beak and the crab's Rock. The Tzen NPC
  `_cc5ad1` says the same thing: "They keep petrifying everyone who goes in…
  You using suitable Relics?". The second slot holds the Genji Glove. The
  Back Guard (no back or pincer) and the Czarina Ring (Safe and Shell at low
  HP) are alternatives. The Amulet (Tzen relic 55, 5000 GP) blocks Zombie,
  which matters only if the Black Drgn is fought.
- **Armor:** Gold Armor, Gold Helmet and Mithril Shld are in the bag.
- **Esper:** **Maduin** grants Fire, Ice and Bolt while worn
  (`genju_prop.asm:114`), and its stat line is -3 vigor, +3 stamina, +7 magic
  (`ot6_progression.asm:532`). That gives the solo Celes all three elements:
  Fire for the Gilomantis and Pm Stalker, Bolt for the Chitonid. Each is a
  base tier that boost folds to tier 2 or 3 (Fire 4 → 20 → 51 MP; `MagicProp`
  +5). The alternatives are Unicorn (Pearl = holy, 40 MP), Shiva (Osmose MP
  income) and Seraphim once bought (Life and Cure). The **Runic** income on
  this stretch is thin, because only the Pm Stalker's counter-Drain and the
  Osprey's counter-Shimsham are runic spells (`pools.txt`).

**Estimate** of a solo Celes's shielded (×0.5) damage per hit at L25, from
vanilla's formulas (`damage_estimate.txt`; no variance, crits or boost):

```
$021 Mesosaur HP 1112 def 110 mdef 150: Break Blade 225 (5); Blizzard 426 (3); ThunderBlade 213 (6); Ice 290 (4); Fire via Maduin 162 (7)
$031 Gilomantis HP 1412 def 115 mdef 140: Break Blade 217 (7); Blizzard 205 (7); ThunderBlade 205 (7); Ice 159 (9); Fire via Maduin 355 (4)
$07C Chitonid HP 1111 def 140 mdef 80: Break Blade 178 (7); Blizzard 169 (7); ThunderBlade 338 (4); Ice 241 (5); Fire via Maduin 270 (5)
$0E6 Osprey HP 850 def 105 mdef 120: Break Blade 232 (4); Blizzard 441 (2); ThunderBlade 220 (4); Ice 373 (3); Fire via Maduin 208 (5)
$0E1 Scorpion HP 290 def 5 mdef 215: Break Blade 387 (1); Blizzard 367 (1); ThunderBlade 367 (1); Ice 55 (6); Fire via Maduin 62 (5)
$02C HermitCrab HP 305 def 150 mdef 80: Break Blade 163 (2); Blizzard 154 (2); ThunderBlade 154 (2); Ice 241 (2); Fire via Maduin 270 (2)
$0C0 Pm Stalker HP 265 def 140 mdef 115: Break Blade 178 (2); Blizzard 169 (2); ThunderBlade 169 (2); Ice 193 (2); Fire via Maduin 432 (1)
$0D5 Black Drgn HP 4000 def 102 mdef 20: Break Blade 237 (17); Blizzard 224 (18); ThunderBlade 224 (18); Ice 324 (13); Fire via Maduin 725 (6)
```

What the estimate says about fights she can take alone:

- **The plains (31/34)** are two- or three-body fights at 4-7 unbroken hits
  a body. The element blades or Maduin roughly halve that, and a break (×2)
  shortens it again. The Mesosaur pair spends two thirds of its turns trying
  to **Escape** (`ai_script.asm:1720`), which costs XP rather than HP. The
  Osprey is the kill-first body, because of its Beak.
- **The house:** a Scorpion dies to one blade hit, and its mdef of 215 makes
  magic useless against it. That makes Scorpion ×3 about three Fight turns
  against the Doom count that the first Doom Sting starts (29-54 counts). A **HermitCrab** must not be
  the last body standing unless she wears a Jewel Ring. The **Pm Stalker**
  can answer a Fight with a runic Drain (1 in 3), so Runic first turns that
  counter into a BP.
- **The Black Drgn** (4000 HP, Zombie) is a fight to avoid solo. §2.3 keeps
  the route off its tiles.

### 5.3 Levels and where to grind

Celes has exactly the L25 total. The next levels need 5,392, 5,824 and 6,280
XP (`LevelUpExp` ×8, `battle_main.asm:16223`; L26 49,464, L27 55,288, L28
61,568). A route fight pays ×2: 1,114-2,036 XP from groups 31/34, so three
to five fights a level. The walk itself expects about one fight
(`encounter_budget.txt`: landing → Tzen direct, mean 1.10).

Sensible practice, to be settled by measurement:

1. Play the first plains fights solo and log HP lost per fight and the
   statuses taken.
2. If a fight costs more than about half her HP, or a status reaches her,
   grind on the plain between Albrook and the (136,185) bend. The Albrook inn
   is 300 GP, and there are ten Tents for world-map care (`supply.md` Tent
   row).
3. Aim for Sabin's level (26) or higher. `norm_lvl` then brings him up to
   her.

This is "healthy levels at each key point" (`guidelines.md`), and the house
is a key point: a lost house fight is a game-over reload to the pre-Tzen
save.

### 5.4 The supply band and the shops

Every shop on the stretch (`shops.txt`, `ShopProp` at `C4/7BA0` = the vanilla
blob plus OT6's one splice, `menu/shop.asm:2309-2353`):

| shop | where | stock (GP) |
|---|---|---|
| 48 item | Albrook | Potion 300, Tincture 1500, Fenix Down 500, Revivify 300, **Remedy 1000**, Sleeping Bag 500, Smoke Bomb 300, Warp Stone 700 |
| 49 weapon | Albrook | Flame Sabre, Blizzard, ThunderBlade 7000 |
| 50 armor | Albrook | Gold Shld 2500, Bard's Hat 3000, Green Beret 3000, Gold Helmet 4000, Gold Armor 10000 |
| 51 relic | Albrook | Sprint Shoes 1500, Atlas Armlet 5000, Earrings 5000, Barrier Ring 500, MithrilGlove 700, True Knight 1000, Wall Ring 6000, Jewel Ring 1000 |
| 52 weapon | Tzen | Kaiser 1000, Poison Claw 2500, Flame Sabre / Blizzard / ThunderBlade 7000, Fire Knuckle 10000 |
| 53 armor | Tzen | Gold Shld 2500, Beret 3500, Tiger Mask 2500, Gold Helmet 4000, Power Sash 5000, Gold Armor 10000 |
| 54 item | Tzen | Potion 300, Tincture 1500, Green Cherry 150, Fenix Down 500, Echo Screen 120, Revivify 300, Sleeping Bag 500, Super Ball 10000 |
| 55 relic | Tzen | DragoonBoots 9000, Sneak Ring 3000, Black Belt 5000, Back Guard 7000, Sniper Sight 3000, Peace Ring 3000, Jewel Ring 1000, Amulet 5000 |

**No Tonics anywhere on this stretch**, and no Softs or Antidotes either
(Celes has 18 Softs). By the guideline, field care here uses **Potions**:
250 HP in the field (`ItemProp+20`, `menu/item.asm:2400-2420`), against
Tonics' 50. The harness care kernel already falls back from Tonic to Potion
and keeps 4 of each in reserve (`ot6_field.lua` `CARE_RESERVE`, `:3409`), so
her 4 Tonics stay put. The band at L25-27:

| item | band (guidelines) | at the landing | top-up |
|---|---|---|---|
| field heal | Tonics L×5 → 99 cap; no seller, so **Potions**, sized to the legs' spend | Potion ×39 (+ Tonic ×4) | Albrook or Tzen 300 GP each; about 60 more (18k GP) covers a grind and the house with margin; **estimate**, to be sized from the logged spend |
| Fenix Down | about L (≈ 25-27) | 22 | useless solo (a lone Celes's death is a loss); top up at Tzen before or after Sabin joins |
| Potion (combat) | L×1.5 before a boss gauntlet | shared with field care | no boss on the stretch |
| Remedy | — | 1 | Albrook only (Sap, and Petrify alongside Soft) |

Every town stop tops up, buys the scarcest item last, and puts the combat
items (Potion, Soft, Remedy) at the top of the bag (`M.bagArrange`). The
harness's supply audit is WoB-only today: `tools/audit_supplies.py:15` ends
its band at the WoR landing.

---

## 6. Sabin joins

From the same fixture (`party_wor_landing.txt`):

```
  SABIN: L26 HP 1139/1139 MP 211/227 XP 49464 party byte $20
    vigor 47 speed 37 stamina 39 magpwr 28; commands Fight, Blitz, Magic, Item
    gear: -, -, -, -, -, -; weapon class bludg; esper -
    can equip weapon: MetalKnuckle (pow 55, slash)
    can equip armor: Kung Fu Suit (def 34/mdef 23); Mithril Vest (def 45/mdef 30); Ninja Gear (def 47/mdef 32)
    can equip relic: Jewel Ring; Peace Ring; Genji Glove; Black Belt; Star Pendant; Back Guard
```

His keys are bare fists (bludg, `Ot6WeapClassTbl` `$FF`), claws (slash:
Kaiser, holy; Poison Claw, poison; Fire Knuckle, fire; `items.txt`), and
blitzes with their own classes and elements: Pummel and Suplex bludg
(`ot6_class.asm:191-192`), AuraBolt holy, Fire Dance fire (`MagicProp`
`$5D-$64`). Tzen's shops 52, 53 and 55 dress him (Fire Knuckle 10,000;
Power Sash 5,000), along with the house's Hyper Wrist. A second Genji
Glove is in the bag.

---

## 7. Save points and checkpoint cuts

There are no save-point tiles on the stretch: no `SAVE_POINT` NPCs in
305-312 or 324-330 (`maps.txt`). FF6 saves anywhere on the world map
(`M.saveGame` asserts `$0201` bit 7; `supply.md` "save point or world
map"). A person saves at the natural pauses, and those are the checkpoint
cuts:

| checkpoint | where | why |
|---|---|---|
| `wor-island-v1` (`gen_wor_island`) | world (76,239), the Solitary Island's own tile, Celes alone, Cid not yet fed | the first WoR save |
| `wor-start-v1` (`gen_wor_start`) | world (146,212), Celes alone, Cid recovered | the first save after the island |
| `wor-albrook-v1` (not cut) | world, outside Albrook after shopping, re-equip and any grind | the grind's resume point; `gen_wor_tzen_door` plays the kit, both Albrook stops and the grind in one segment, whose own retries start at the landing |
| **`wor-tzen-door-v1`** (`gen_wor_tzen_door`, cut 2026-09-23) | world (131,179), one step east of Tzen's door, *not* on the desert | the last save before the committed, timed scene; every house attempt retries from here |
| **`wor-sabin-v1`** (`gen_wor_sabin`, cut 2026-09-28) | world (131,179), where Tzen's south exit returns the party (the parent map: the tile it entered from) | the first save after he joins; the end of this route |

Each cut asserts its preconditions: the party, `$027D/$028A/$028B/$028C`,
no live timer, and the equipment.

---

## 8. Break data for the stretch

Owner direction (`guidelines.md` "Design break data for every encounter"):
every species the route meets gets an authored row designed from its body,
its vanilla elements and the party that meets it, so that the party holds
a key and the area teaches something. The rows follow the house curve:
**2** for trash, **3** for tanks and stacks, **4** for miniboss-grade. Vanilla
element bits are left untouched, and no `Ot6ElemAddTbl` rows are proposed.

**Authored (2026-09-22), exactly as designed below, pending the owner's
review of the table.** The twelve rows are one block in `Ot6ShieldTbl`
(`ff6/src/battle/ot6_hud.asm`, "the world of ruin: the solitary island to
tzen's collapsing house"), one row per species, so a row changed on review
is a one-line edit there and one line in the suite's `WANT` table.
`tools/tests/battle_breakwor_sabin.lua` (`@suite`) reads them back from the
built ROM: each species' row, its vanilla weak byte and the absence of an
`Ot6ElemAddTbl` row, and that every formation of the stretch (world groups
29-31, 33-36 and 40, map 311, event group 150) has an authored row for each
species and a key for Celes's sword or Ice. It is red on the ROM without
the rows and on a mutant ROM for each assertion
(`build/attempts/wt/wor-break-rows/`). The "proposed row" columns below
are the authored rows. The tuning claim in `audit_break_coverage.py` is
unchanged: it grows only once the driving has played these areas.

### 8.1 Who holds what

| hand | classes | elements |
|---|---|---|
| Celes alone (to Tzen) | **slash** (every sword; pierce only on the 26-30-power daggers) | **ice** (own Ice; Blizzard), **bolt** (ThunderBlade, in the bag), **fire** and bolt (Maduin, worn); holy with Unicorn's Pearl (40 MP) |
| Celes + Sabin | + **bludg** (fists, Pummel, Suplex), slash (claws) | + **holy** (AuraBolt), **fire** (Fire Dance) |

### 8.2 The Solitary Island (world groups 29, 30; not met on the way to `wor-start-v1`)

The island's field maps (396-400) have no random battles (`map_prop.dat` +5
bit 7 clear), and the island segments (`gen_wor_island`, `gen_wor_start`)
cross its world tiles for one step (onto (76,239) off 396's west edge, then
(76,240) back in) and met no battle there in any run
(`docs/design/wor-start.md`). A player who walks the island's world tiles
can meet these; the table is for the break design, not a fight on the
route.

| id | body | L | HP | vanilla weak | absorbs | proposed row |
|---|---|---|---|---|---|---|
| `$072` Peepers | tiny pest | 23 | 1 | ice\|water | — | 1 · slash |
| `$0B2` EarthGuard | tiny pest | 23 | 1 | water | — | 1 · slash |
| `$0D5` Black Drgn | dragon | 26 | 4000 | fire\|holy | poison | **4 · slash** |

- The 1-HP pests die to any hit, so a row only makes the gauge read right. One
  shield, in Celes's class, follows the Baren Falls piranha "chum wave" precedent
  (`ot6_hud.asm`, `$0154`, 1 shield). Today's floor EarthGuard (pierce) is
  keyless for her.
- The Black Drgn is a miniboss-grade body (4000 HP) on the beach, and again
  on the desert tiles at Tzen's door (groups 30, 36 and 40). Its vanilla
  fire and holy are Sabin's (Fire Dance, AuraBolt) and Maduin's. A
  sword-only Celes has no key on today's floor (pierce). Slash gives her
  one: a blade finds the gaps in the scales.
- **Teaches:** the sand holds a dragon. The beach warns, and the desert by
  Tzen repeats it.

### 8.3 The plains (world groups 31 and 34 on the route; 33, 35, 36 beside it)

| id | body | L | HP | vanilla weak | absorbs | proposed row |
|---|---|---|---|---|---|---|
| `$021` Mesosaur | saurian (×4 in group 35) | 26 | 1112 | **ice** | — | **3 · slash\|pierce** |
| `$031` Gilomantis | mantis | 26 | 1412 | **fire** | — | **3 · slash\|bludg** |
| `$07C` Chitonid | plated shell, starts in Safe | 26 | 1111 | **bolt** | — | **3 · bludg** |
| `$098` Gigan Toad | toad | 26 | 458 | **ice** | — | 2 · slash\|pierce |
| `$0CA` Lunaris | — | 26 | 582 | **none** | — | 2 · slash\|pierce |
| `$0E6` Osprey | flier | 26 | 850 | **ice** | — | 2 · slash\|pierce |

- **Shield counts:** the three 1100-1400-HP bodies are this plain's tanks
  (3). The rest are trash (2). Today's 5 shields (`2 + 26/8`) put the break
  on a corpse, as in the Vector note (`break-coverage-vector.md` §8.2).
- **Mesosaur:** a hide that a blade or a point opens. Vanilla ice is Celes's
  own spell and her Blizzard.
- **Gilomantis:** slash for the limbs and bludg for the carapace (Sabin
  later). Vanilla fire (Maduin, the Flame Sabre in both towns, Fire Dance)
  is the better key, because its Sickle counter answers only Fight.
- **Chitonid:** a plated shell that is caved in, never cut (Sabin's fists
  later). For a solo Celes the key is its **vanilla bolt**: the ThunderBlade
  in her landing bag, a Genji Blizzard + ThunderBlade pair, or Maduin's
  Bolt. A sword-only Celes cannot chip it. That is deliberate, and it is the
  one place on the stretch where the key has to be picked up. It is still in
  her bag at the landing, and both towns sell the blade. If review prefers a
  forgiving row, `3 · slash|bludg` keeps it chippable by any sword.
- **Lunaris** has no weakness, so its class row is its only key. The row
  also covers pierce, for later parties.
- **Osprey:** a flier, which is pierce in the WoB convention
  (`weapon-classes.md` "pierce-weak fliers"), plus slash so a solo blade
  reaches it. Its vanilla ice breaks it fast, and it has to die first
  because of its Beak.
- **Teaches:** *read the element.* Three of the plain's six bodies are
  ice-weak (Celes's own). The mantis wants fire and punishes a blade. The
  plated one wants the bolt blade. The Lunaris answers only to the class.
  Elemental blades and a Genji pair are the lesson, and Maduin is the
  magic version of it.

### 8.4 The collapsing house (map 311, group 128; event group 150)

| id | body | L | HP | vanilla weak | absorbs | proposed row |
|---|---|---|---|---|---|---|
| `$0E1` Scorpion | soft body (def 5 / mdef 215) | 26 | 290 | **none** | — | 2 · slash\|pierce |
| `$02C` HermitCrab | shelled, starts in Safe | 26 | 305 | water | — | 2 · slash\|bludg |
| `$0C0` Pm Stalker | ghost, floats | 26 | 265 | **fire\|holy** | poison | 2 · slash |

- **Today, formation 209 (Scorpion ×3, 62.5 % of the house's draws) has no
  key for a sword-carrying Celes, who is alone in the house.** The floor is
  pierce, which she holds only on a Dirk or MithrilKnife (power 26-30), and
  the Scorpion has no weakness. The HermitCrab (floor pierce, water-weak;
  nobody holds water) is keyless too (`design_keys.txt`):

  ```
  formation 209: Scorpion $0E1, Scorpion $0E1, Scorpion $0E1
    Celes, sword only (Break Blade), Ice: today Scorpion:n | proposed Scorpion:Y
  formation 207: HermitCrab $02C, HermitCrab $02C, Pm Stalker $0C0
    Celes, sword only (Break Blade), Ice: today HermitCrab:n Pm Stalker:Y | proposed HermitCrab:Y Pm Stalker:Y
  ```

  `audit_break_coverage.py` passes these vacuously: tier 1's broad-kit model
  counts pierce as held (`audit_break_coverage.txt:275-277`).
- **Scorpion:** a blade (or a point, for later parties) through a soft body.
  With def 5 and mdef 215 the data already says "the blade, not the spell".
- **HermitCrab:** the blade takes the body outside the shell and a blow
  cracks the shell (bludg for Sabin later).
- **Pm Stalker:** slash in Celes's hand, with vanilla fire and holy for
  Maduin, Sabin and the Flame Sabre.
- **Teaches:** *read the counter.* The Scorpion condemns on its first move,
  so kill it with the blade before the count runs out. The last crab
  standing throws Rock, so fix the kill order or wear the Jewel Ring the
  townsfolk mention. The Pm Stalker can answer a Fight with a runic Drain, so
  raise Runic first. The house is where Runic earns its place.

### 8.5 The check

With the proposed rows every formation on the stretch has a key for the
hand that meets it, except Chitonid for a sword-only Celes, as intended
(`design_keys.txt`, all "proposed" columns):

```
formation 204: Osprey $0E6, Chitonid $07C, Gigan Toad $098
  Celes, sword only (Break Blade), Ice: today Osprey:Y Chitonid:n Gigan Toad:Y | proposed Osprey:Y Chitonid:n Gigan Toad:Y
  Celes, Blizzard + ThunderBlade (Genji) or Maduin: today Osprey:Y Chitonid:Y Gigan Toad:Y | proposed Osprey:Y Chitonid:Y Gigan Toad:Y
```

**Format:** each row is an `Ot6ShieldTbl` record (`ff6/src/battle/ot6_hud.asm:1541`),
`.word` species then `.byte shields, OT6_SLASH|…`, with a comment, as in:

```
        .word   $00e1
        .byte   2, OT6_SLASH|OT6_PIERCE ; scorpion (WoR, Tzen house): def 5 /
                                        ;   mdef 215 -- the blade, not the spell
```

`Ot6SeedShields` takes the first match (`ot6_break.asm:54-113`), and
`tools/check_shield_rows.py` refuses a second row for a species. It passed
before authoring (`check_shield_rows OK: 91 Ot6ShieldTbl rows, one per
species, ROM matches source`), when none of the twelve species had a row,
and passes with them (`check_shield_rows OK: 103 Ot6ShieldTbl rows, one per
species, ROM matches source`, `build/attempts/wt/wor-break-rows/`). **WoB sharing:** none of the twelve appears in any WoB pool or
WoB event group (`species_sharing.txt`), so no existing WoB row is affected.
They can come back later on the Veldt. `GetVeldtBattle`
(`field/battle.asm:269-310`) serves any formation on the `$1DDD` list, and
the end of every battle adds its formation unless the formation opts out
(`$2F4B` bit 1) or a monster id is 256 or higher
(`battle_main.asm:12476-12488`). So the rows also shape Gau's WoR Veldt
draws.
One side effect of a row: it exempts the species from `Ot6HpScale`, which
ships at 1× and is inert (`break-coverage-vector.md` §0). The authoring
commit added `battle_breakwor_sabin.lua`, in the `battle_breakgate.lua`
shape, which reads the rows back from the built ROM. With the rows,
`audit_break_coverage.py` no longer lists any of the twelve as
"unauthored" (the `floor` lines for map 311 and world groups 29-31, 33-36
and 40 are gone; `audit.before.txt` / `audit.after.txt` in
`build/attempts/wt/wor-break-rows/`). The tuning claim
(`CLAIMED_WORLD_SECTORS`, `CLAIMED_FIELD`) is unchanged and grows only once
the driving has played these areas.

---

## 9. Risks and unknowns

Harness mechanics this stretch exercises, checked against
`docs/design/mechanics-coverage.md`:

| mechanic | where | coverage today | what the driving needs |
|---|---|---|---|
| a party of one; Death, Petrify or Zombie = loss | everywhere to Tzen | Petrify measured live (§10.2: without the Jewel Ring the Beak lost the second fight); the kit asserts the protection; the Zombie pool is off the walk (the avoid set) | the house: the Jewel Ring stays on (§11.4) |
| Condemned (Doom Sting) | house, 209 | HANDLED (`M.doomCount` / `M.doomRule`); the lone fighter's race said (`[doom]`, §11.3) | measured: the fights end inside the count, the thinnest by 354 ticks |
| Sap (T. Lash, Slip Touch) | plains, house | HANDLED (planned around: 18-21 HP a tick every 429-608 frames, §10.3) | — |
| Stop (Net) | house, 207 | HANDLED (planned around) | — |
| Monster Escape (a Mesosaur with company) | group 31 (both formations), group 35 | HANDLED (`[escape]`, the `[outcome]` reward check, §10.3) | — |
| Sneeze (Chitonid, last and hit) | formations 204 (group 34) and 201 (group 33) | HANDLED for a party that leaves whole (`[left]`, `PARTY LEFT`, no reward, not a wipe) and avoided (the last-stand kill order, §10.3); a member leaving with others still in is out of the care lines (`M.leftMask`, §11.5) | — |
| face up + A trigger | the child (117,12) | HANDLED: `H.faceAndHoldA` (§11.2) | — |
| event timer through menus and battles | the house | HANDLED: `eventTimerLive` keeps menus out; the driver reads the clock and says it (`[timer]`), with timed levers (§11.1) | — |
| pincer / back attack on a party of one | the house; the plains | HANDLED in the house by the Back Guard (§11.4) | the plains keep the Genji pair: a pincered Gilomantis + Mesosaur was won there (§11.6) |
| committed scene (the bounce) | Tzen after the LoJ | none needed | do not route to the exit before `$028A=1` |
| map-init `mod_bg_tiles` | 305, 324 | the lib reads live RAM, so it is fine | the offline BFS counts here are **verify-on-arrival** |
| equipping from nothing, Genji pair, esper | landing; Sabin at Tzen | `M.equipKit`, `M.equipEsper`, now on the world map's menu too (§10.4) | assert the result slot by slot |
| world-map tiles to avoid | Tzen's door | HANDLED: `worldNavTo` / `worldBfs` / `worldPathGroups` take an avoid set (§10.3) | — |
| no Tonic seller | whole stretch | the care kernel falls back to Potions; Albrook tops them up to level x 1.5 + the measured field spend (§10.1) | extend `audit_supplies.py` into the WoR |
| side attacks | — | masked out below three allies | none |

Other unknowns:

- **The Solitary Island segment's hand-off** (measured, `docs/design/wor-start.md`):
  `wor-start-v1`'s Celes is dressed (above), in the back row, and the
  island spent nothing (no battles): `tonic=4 potion=39 fenix=22
  gil=215563` on the cold Continue.
- **The load-onto-trigger at (16,9)** that starts "SABIN: Wait!" is vanilla
  behaviour. It is **verify-on-arrival**.
- **The encounter draws are save data** (`$1FA1-$1FA5`, `docs/TESTING.md`).
  Retries of the house from `wor-tzen-door-v1` meet the same formations in
  the same order unless encounters are used up first. A generator for the
  house must cope with both 207 and 209, and with 0-6 battles, not with the
  one sequence the checkpoint happens to hold.
- **Chests with monsters** start event battles that also run the clock.
  Leave them for a second visit.

Out of scope, noted for the coordinator: `tools/audit_break_coverage.py`
reads raw `RandBattleGroup` words and indexes `battle_monsters.dat` with
them (`formation_species(f)` on the unmasked word). A `+rand 0..3` word
(bit 15) therefore resolves to no species at all. None of this stretch's
pools uses one, but any pool that does is silently unaudited.
`audit_encounters.py` resolves them correctly (`Data.resolve`).

---

## 10. The landing to Tzen's door, played (`gen_wor_tzen_door`, `wor-tzen-door-v1`)

Driven 2026-09-23 for #250 (the harness half is #255). The segment
cold-Continues `wor-start-v1` (checkpoint=, so it regenerates without the
World of Balance chain), dresses CELES on the world map's menu, stops in
Albrook, fights the plains north of it to L27, stops in Albrook again,
walks to Tzen off the desert and saves on the World of Ruin map at
(131,179), one step east of the door: the `wor-tzen-door-v1` checkpoint,
the boot for the timed house. Every number below is quoted from a log
under `build/attempts/wt/wor-tzen-door/` (`runs/` the graph's own run, the
capture and the cold Continue; `lab/` the probes and A/B labs, with the
scripts that made them; `var-final/` and `var-prefinal/` the runs under
real draw variation; `suites/` the lib suites; `review-final/` the same
on the tree after the review's fixes). Nothing was measured by writing
game state.

Re-cut after the review (`review-final/runs/`): the graph's run
(`nice ninja build/states/wor_tzen_door.mss.lua`) and the capture play the
same run to the frame, `PASS (frame 46853) attempts=1/3`, and the
battery is byte-identical to the first cut (`sha256=5965bc6b...`); only
its provenance moved (the generator's new fingerprint,
`ot6-provenance/v2`). Each fight's ticks are
now counted to the end hook, where its `[outcome]` is said: 61 fewer
than the figures below, which were counted to the driver's idle
(`$0C7 WON after 2690 ticks`, against 2751).

### 10.1 The run (`runs/wor_tzen_door_ninja.log`, `nice ninja build/states/wor_tzen_door.mss.lua`)

| step | what the log says |
|---|---|
| boot | `[wor] boot f1346: world 1 (146,212), CELES L25 xp 44072 HP 1043/1043 MP 227/227 status1 $00, row back, esper+kit FF 11 0E 76 8F D1 C1; tonic=4 potion=39 fenix=22 remedy=1 soft=18 tent=10 gil=215563` |
| kit | `[wor] kit: esper+kit 06 0E 0F 76 8F D1 B5, row back; hands 0E (element ice) + 0F (element bolt); relics protect STATUS1 $40` |
| the pools | `[route] avoid set: 65 tiles in (118..159, 160..223) off the plains pools: group 36 x65 (deals $0B2)`; every leg `the walk can roll groups {34, 31}` |
| Albrook, before | `bought: tonic=4 potion=44 fenix=25 remedy=5 ... (spent 7000 GP)`, `CELES is whole; no night at the inn` |
| the grind | 7 battles, `$0C7 x2, $0CC x3, $0C5 x1, $0CA x1`, all `WON`, `paid as due`; `[wor] grind done f44485 after 29 legs: CELES L27 xp 55924 HP 1211/1211 MP 251/251` |
| Albrook, after | `bought: tonic=4 potion=47 fenix=27 remedy=5 ... (spent 2200 GP)`; no night (the level-up had filled her) |
| Tzen | no battle on the walk; `[tzen] at the door f46538: world 1 (131,179)` |
| the save | `[saved] wor-tzen-door-v1: slot 3 holds map 1 ($3001) world tile (131,179)`, `contract wor-tzen-door-v1 (exit): all 24 fields hold`, `PASS (frame 46853) attempts=1/3` |

Fights met: Gilomantis + Mesosaur twice (2751, 3199 ticks), Osprey +
Chitonid + Gigan Toad three times (9582, 4656, 9304), Mesosaur ×2 once
(2478), Lunaris + Osprey once (3303). No death, no Fenix Down (22 held, 5
bought, 27 at the save), so no boost at a death to classify. CELES chose
Fight 24 times and Cure 9 times; the field care spent one Potion (`used
$E9 on char 6: 679 -> 929 hp`); Sap landed once (`[status] f+749 ... SAP`)
and Slow once (`[status] f+2150 ... SLOW`). Her lowest HP was 175 of 1125,
in the third Osprey + Chitonid + Gigan Toad fight with only the Osprey
left (`battle f+8100 ... partyhp=175`); that fight is the stretch's
longest and hardest, taken Chitonid-first (10.3). The capture run
(`runs/capture_wor_tzen_door.log`, `OT6_CAPTURE_SRM`) is the same run, its
`wor_tzen_door.mss` byte-identical; sealed and validated
(`runs/validate_wor_tzen_door_v1.txt`): `holds=slot 3 world 1 (131,179)
[$1F64=$3001] (saved: declared and checked)`. The cold Continue
(`runs/continue_wor_tzen_door_v1.log`, `probe_wor_tzen_door_continue.lua`):
`contract wor-tzen-door-v1 (entry): all 24 fields hold`, `[continue] world
1 at (131,179): CELES L27 HP 1211/1211 MP 251/251 row back esper+kit 06 0E
0F 76 8F D1 B5; tonic=4 potion=47 fenix=27 remedy=5 gil=222473`, `PASS
(frame 1386)`.

### 10.2 The kit and the row, measured

The same walk from the same landing snapshot, 14 battles, only the lever
changed (the formations come in the same order: they are save data):

| lever | frames for 14 battles | Potions of field care | Osprey + Chitonid + Gigan Toad | log |
|---|---|---|---|---|
| front row, Maduin | 49,791 | 6 (39 -> 33) | 7845, 8174, 6147 ticks | `lab/lab_grind.log` |
| **back row, Maduin** | **41,439** | **3** (39 -> 36) | 3114 (sneezed out), 3605, 2717 | `lab/lab_grind_back.log` |
| back row, Ifrit | 46,295 | 5 (39 -> 34) | 4957, 3846 (sneezed out), 5350 | `lab/lab_grind_ifrit.log` |

A boosted Genji Fight kills a plains body a turn from either row (`took
458 off`, `took 850 off`, the Gigan Toad and the Osprey, `lab_grind.log`),
and the back row halves what she takes (`slot 0's smallest hit ... 132`
front, `... 66` back), so the heal policy spends fewer turns on her: she
stays in the BACK row she arrives in. Maduin stays over Ifrit's +6 vigor:
no faster on this walk, and its +7 magic stands behind her Cure, her
in-battle heal. The blades: Blizzard (ice: the Mesosaur, the Osprey, the
Gigan Toad) and ThunderBlade (bolt: the Chitonid, whose authored row is
bludgeoning only) on the Genji Glove, and the Jewel Ring in the second
relic slot. Without it (`lab/lab_grind_noring.log`, the island's Czarina
Ring kept) the second fight was lost: `[status] f+1864 ... SLOW`, `[status]
f+2193 entity 0 char 6 is under PETRIFY`, `[outcome] battle $0CC LOST after
2447 ticks`: the Osprey's Beak on a party of one, at 630/1043 HP
(`lab/lab_grind_noring2.log`: `[wipe] ... class=lost to a status: 1
member(s) Petrified or Zombied, no deaths`). The generator's kit assertion
goes red without the ring (`lab/gen_wor_tzen_door_noring.log`: `a relic
CELES wears protects her from Petrify (the Osprey's Beak): got 0 ($0), want
64 ($40)`).

### 10.3 The mechanics the plains deal (docs/design/mechanics-coverage.md)

- **A monster escaping** (the Mesosaur with company): `[escape] f+350 slot
  3 (species $021) ESCAPED at 1112 HP ($3A3A=08): no kill`, and the
  battle's `[outcome] ... killed s2:$021; escaped s3:$021 ... reward due 918
  ... (char 6 +918 (due 918)): paid as due` (`lab/lab_grind_back2.log`).
  One escaped in 6 of that lab's 9 Mesosaur fights, each at f+262..366,
  about when her first turn comes. WinBattle pays only for a killed
  body; the generator asserts every battle paid as due. With the rule
  switched off (an escaped body counted a kill) the same snapshot reads
  `due 1836 ... +918 ... XP MISMATCH` (`lab/outcome/`).
- **A member sneezed out** (the Chitonid): its retaliation is
  `if_num_monsters 1 / if_hit / attack SNEEZE, NOTHING, NOTHING`, and
  `AICond_13` counts the monsters alive AFTER the hit, so it fires on its
  own killing blow once one other body is left. Left for last it sneezed
  CELES out of 2 of the 6 back-row fights in the labs (`lab/lab_grind_back.log`,
  `lab/lab_grind_ifrit.log`; 0 of 3 in the front row, `lab/lab_grind.log`) (`[left] f+2818 entity 0
  (char 6) LEFT the battle ... the whole party is gone`, `PARTY LEFT ...
  reward due 0`); taken before only the last plain body it still did, on
  its killing blow, twice in three (`lab/gen4.log`). The driver takes a
  Sneeze-counter body first while a plain body stands (`[last stand]
  slot 1 ($07C) throws $CB (N=1) ... taken first, while 2 other(s) still
  stand`), by default and on both routes: on the World of Balance it is
  the Baskervor beside one partner (formation `$0A2`), where 40 fights a
  side (`review-final/wob/summary.txt`) read 25 members sneezed out in 20
  with the rule off and 2 in 1 with it on, at the same pace (mean 2046
  against 2015 ticks). With one partner the killing blow can still fire
  the counter (gen4 above); the order cuts the repeated sneezes of a
  body left alone. From one snapshot, rule off `party left`, rule on
  `won` (`lab/laststand/`): one run per arm, not sixteen -- all 16 seed
  shifts of each arm end on the same frame (3110 off, 5998 on), the idle
  absorbed before the mid-battle snapshot's fight moved. None of the
  segment's Chitonid fights since has sneezed. The price is time: those
  fights run 4656-9582 ticks against 2717-3605 with the Chitonid last.
- **Petrify**: above; the kit asserts a relic protecting STATUS1 `$40`
  before the plains.
- **Zombie**: the Black Drgn is on the desert south and west of Tzen's
  door (group 36). The avoid set keeps every plan off it; from 816 start
  tiles near the door, `without the avoid set: ... 192 plans step on the
  sand`, `with the avoid set: ... 0` (`lab/lab_avoid.log`).
- **Sap** (the Mesosaur's T. Lash): a tick every 429-608 frames of 18-21
  HP at 1211 max HP (`lab/probe_sap.log`), gone with the battle: planned
  around. **Slow** (the Gigan Toad's Slimer): planned around, the ATB
  constant carries it. **Dark** (the Lunaris's Face Bite): planned around
  in battle, cured in the field with a Remedy (`plan: cure dark char 6 with
  $F5`); no shop from the landing to Tzen sells Eye Drops, so Albrook's
  Remedies are the stock.

### 10.4 The walk, the menus, the town

- **The world map's menu** works for the kit now: the equip helpers used to
  wait for the field's control after the menu, which the world map never
  gives (`lab/lab_kit_mutant_menuback.log`: `timeout after 1200 frames
  driving toward MADUIN -> CELES: back out`).
- **Leaving a town**: the world map reads lit for a frame while the town
  fades out, and its tilemap lands about 86 frames after the map word
  turns (`lab/lab_exit2.log`); a plan read before then walks the town's
  tiles (`lab/gen3.log`: `no world path from (141,208) to (141,203)`).
  The generator waits 30 frames of a lit, controllable world with a
  walkable tile under her.
- **Albrook** (WoR map 324): in at (2,17); the item shop is shop 48
  (`the counter opened shop 48`), out of town by the west edge to world
  (141,208). The first stop comes BEFORE the grind: she lands with one
  Remedy, and the first Lunaris took it (`lab/gen1.log`, the grind-first
  cut: `remedy=0` after battle 1).
- **The approach**: `worldNavTo` did not carry past (131,179) into the
  door with the pad held (`lab/lab_approach_norelease.log`), so no
  release-per-step walker was kept.

- **The lib's suites** that call what this segment changed (the equip
  helpers, the world BFS and navigator, the wipe class, the part roles,
  the driver's per-frame watch and `[outcome]`, the last-stand rule).
  On the final tree (the review fixes: the `[outcome]` said at the
  `UpdateSRAM` end hook, the last-stand comment and its World of Balance
  measurement; main merged through `bdc723f9`), run through `run.sh` on a
  ROM built from the tree (`fdf9bacfafaa`, the ROM every fixture was cut
  on: no suite log says STALE), the 16 below plus the 12 more the review
  ran, 28 in all (`review-final/suites/`, `review-final/suites_verdicts.txt`):
  28 of 28 PASS, every `[outcome]` line `paid as due`, none without an end
  reading, one `[outcome]` for every battle opened (`field_care_emptybag`:
  `PASS (frame 59324)`, `layout=19 out=19 paid=19`, 5 `[last stand]`
  lines; the review counted 5 `[outcome]` lines for its 19 battles), and
  `battle_shadowstays` passes (`PASS (frame 33898)`, 10 of 10 `paid as
  due`). An earlier round of these fixes, with the last-stand rule made
  opt-in (since reversed), is kept as history in `review-fixes/`.
  *History, superseded:* the branch's first commit claimed "15 of 16
  PASS" from `suites/` (06:51-06:56), but those runs were on the lib
  BEFORE the end hook: there `battle_statuses` said 12 of 12 `[outcome]`
  lines as CONTRADICTION and `field_care_emptybag` 5 of 5, and
  `battle_shadowstays` failed (`suites/shadowstays/head.log`, `branch.log`:
  `the 1/16 Shadow-leave roll never passed in 80 won battles`). Its
  first run on the branch found the outcome watch reading the battle's
  RAM after the battle had handed it back (`branch_before_endhook.log`:
  320 false `[left]` lines), which is what the end hook fixed.

### 10.5 Under real draw variation

A seed shift moves only in-battle RNG; which formation comes next is save
data (`$1FA1-$1FA5`), so every replay from `wor-start-v1` meets the same
formations in the same order (docs/TESTING.md). `lab/varlab.py` derives
the generator with one block inserted after the kit that fights K
encounters on the grind's own walk first, so the body proper (the pools,
the Albrook stops, the grind, the walk, the save) starts from another
encounter counter, level, HP and bag -- a person who fought a while before
heading for town -- and plays on from there. Retries off
(`OT6_RETRIES=1`): every attempt is scored as it fell.

On the final tree (`review-final/var/summary.txt` and the logs beside
it; `review-final/lab/varlab.py`, the same derivation):

| variant | the body starts at | battles | Osprey + Chitonid + Gigan Toad | escapes | lowest HP sampled | verdict |
|---|---|---|---|---|---|---|
| K=0, shift 23 | the landing (the runner's seed shift only) | 10 | 3 | 4 | 541 | `PASS (frame 41501) attempts=1/1` |
| K=0, shift 41 | the landing | 10 | 3 | 4 | 539 | `PASS (frame 40751) attempts=1/1` |
| K=1 | L25, 837 HP, Dark, `$1FA1-5 = 23 0A 09 09 09` | 10 | 2 | 2 | 487 | `PASS (frame 51678) attempts=1/1` |
| K=2 | L25, 767 HP, `51 0B ...` | 10 | 2 | 5 | 291 | `PASS (frame 46951) attempts=1/1` |
| K=3 | L25, 698 HP, `78 0C ...` | 10 | 3 | 3 | 329 | `PASS (frame 47398) attempts=1/1` |
| K=3, shift 23 | L25, 749 HP | 10 | 3 | 2 | 468 | `PASS (frame 44789) attempts=1/1` |
| K=3, shift 41 | L25, 768 HP | 10 | 3 | 2 | 535 | `PASS (frame 51239) attempts=1/1` |
| K=4 | L25, 584 HP, `92 0D ...` | 10 | 2 | 4 | 418 | `PASS (frame 41758) attempts=1/1` |
| K=5 | L26, `B6 0E ...` | 10 | 2 | 4 | 418 | `PASS (frame 37385) attempts=1/1` |
| K=6 | L26, `DF 0F ...` | 10 | 3 | 3 | 418 | `PASS (frame 39862) attempts=1/1` |
| K=6, shift 23 | L26, 942 HP | 10 | 3 | 2 | 323 | `PASS (frame 48655) attempts=1/1` |
| K=6, shift 41 | L26, 980 HP | 10 | 3 | 3 | 439 | `PASS (frame 46290) attempts=1/1` |
| K=7 | L26, `FF 10 ...` | 10 | 2 | 4 | 418 | `PASS (frame 41664) attempts=1/1` |
| K=8 | L26, `34 11 09 1A 09` | 10 | 1 | 4 | 418 | `PASS (frame 40088) attempts=1/1` |

14 of 14 PASS; every run says one `[outcome]` for each of its 10 battles
(`battles(layout lines)=10 outcome=10 paid_as_due=10 no_end_reading=0`),
140 in all, every one `paid as due`, and no `[left]` line: across the
15 runs (these and the graph's own) 38 Osprey + Chitonid + Gigan Toad
fights were won with no sneeze, no death, no Fenix Down (`Fenix Downs
held and bought 27, left 27` in all 14) and no battle lost; every run
reached L27 and saved at (131,179). The lowest HP is the driver's
300-tick battle line over every battle of the run, not a per-frame
minimum. The K=0 runs end on the frames they ended on before the review;
the K>0 runs do not, because the K block counts its encounters by
`[outcome]` lines, which are now said at the battle's end hook rather
than at the walk's next idle, so it hands over about 62 frames sooner
(K=1: `[varlab] 1 encounter(s) used up before the body: f5649`, against
`f5711`) and the body plays on from another frame. Two things to watch,
both in that formation after the Chitonid falls: HP samples of 175 (the
graph's run, the Osprey alone) and 291 (K=2, the Osprey and the Gigan
Toad: `partyhp=291 ... monhp=s0:850/sh2,s1:0/sh3,s2:458/sh2`): fights
won, but by the heal policy's margin, the stretch's attrition fight.

Before the review, on the lib that said an `[outcome]` only from the
driver's idle (`var-final/summary.txt`): 14 of 14 `PASS attempts=1/1`,
140 `[outcome]` lines, every one `paid as due`, lowest HP samples 128
(K=3, shift 41) to 541; `var-final-prelib/` (the outcome judged on the
last per-frame reading) and `var-prefinal/` (a release-per-step walker
since dropped) ended at the same frames with the same verdicts.

### 10.6 For the house segment

`wor-tzen-door-v1` boots CELES alone at world (131,179): L27 (xp 55,924),
HP 1211/1211, MP 251/251, BACK row, Maduin, Blizzard + ThunderBlade on
the Genji Glove, Gold Helmet, Gold Armor, Jewel Ring; Potion 47, Fenix
Down 27, Remedy 5, Tonic 4, Tent 10, Soft 18, 222,473 GP. Sabin will join
at max(26, 27) = 27 (§2.6). The house's HermitCrabs throw Rock only as
last-stand counters; with the Jewel Ring on they cost nothing, and the
driver's last-stand kill order covers only the Sneeze by default
(`opts.lastStand = true` extends it to every last-stand body).

---

## 11. Tzen's door to Sabin, played (`gen_wor_sabin`, `wor-sabin-v1`)

Driven 2026-09-28 for #250 (the harness half is #255). The segment
cold-Continues `wor-tzen-door-v1` (checkpoint=), walks into Tzen, rides
the Light of Judgment, buys the Seraphim stone, puts the Back Guard on
CELES, starts the house's clock at (16,9), brings the child out of map
311, rides Sabin's joining, dresses him and saves on the World of Ruin map
at (131,179): the `wor-sabin-v1` checkpoint. Every number below is quoted
from a log under `build/attempts/wt/wor-sabin/` (`runs/` the graph's run,
the capture and the cold Continue; `lab/` the A/B labs, the draw
variation and the controls, with the scripts that made them). Nothing
was measured by writing game state, except the one staged suite named in
11.5.

### 11.1 The run (`runs/capture_wor_sabin.log`, the capture)

The graph's own run (`suites/ninja_all.log`, `runs/wor_sabin_ninja.log`:
`[199/340] generate wor_sabin <- gen_wor_sabin`, `PASS (frame 31550)
attempts=1/3`) and the capture are the same run: `wor_sabin.mss`
byte-identical.

| step | what the log says |
|---|---|
| boot | `[wor] boot f1346: world 1 (131,179), CELES L27 HP 1211/1211 MP 251/251 status1 $00, kit 06 0E 0F 76 8F D1 B5; tonic=4 potion=47 fenix=27 remedy=5 soft=18 gil=222473` |
| the Light of Judgment | `[tzen] f1913 after the Light of Judgment map 305 (23,25)` |
| the prep | `[tzen] f2704 bought the stone` (gil 222473 -> 222463, SERAPHIM held); `supplies at the band (potion 47 >= 47, fenix 27 >= 27): no shop`; `the party is whole; no inn`; `[CELES: the Back Guard for the house] char=6 after=11 5C 76 8F E1 B5` |
| the clock | `[house] f4026 the clock starts map 305 (16,9): ... timer 0 6:00 left (21600 frames; flags $72: runs through menus and battles; its expiry ends a battle)` |
| the house | `in the house ... 5:57 left`; `up by the link ... HP 884/1211 ... 4:45 left`; `at the child's tile (117,12) ... HP 657/1211 ... 3:27 left`; `the child is with her ... 3:25`; `down by the link ... HP 409/1211 ... 2:28`; `back at the door (123,60) ... HP 374/1211 ... 1:08` |
| the exit | `out of the house with the child: timer 0 at 1:08 (4099 frames) of 6:00, 17376 frames spent inside (5:57 at the door in); lowest CELES HP inside 248 (f19120, timer 1:57); house battles: $0D1 4:56, $0CF 3:35, $0D1 2:34, $0D1 1:09` |
| Sabin | `[tzen] f24735 SABIN joined map 305 (15,14): ... SABIN L27 HP 1225/1225 MP 239/239`, nothing equipped |
| the town | the inn, 350 GP (`c6 374/1211` -> full); `FIRE KNUCKLE x2 ... gil 230743 -> 210743`, `TIGER MASK ... -> 208243`, `POWER SASH ... -> 203243`; CELES back to `06 0E 0F 76 8F D1 B5`; SABIN `01 57 57 77 90 D1 D5` (IFRIT, Fire Knuckle x2, Tiger Mask, Power Sash, Genji Glove, Black Belt) |
| the save | `[saved] wor-sabin-v1: slot 3 holds map 1 ($2001) world tile (131,179)`, `contract wor-sabin-v1 (exit): all 25 fields hold`, `PASS (frame 31550) attempts=1/3` |

Sealed and validated (`runs/validate_wor_sabin_v1.txt`): `holds=slot 3
world 1 (131,179) [$1F64=$2001] (saved: declared and checked)`, sha256
`757ee81a...`. The cold Continue (`runs/continue_wor_sabin_v1.log`,
`probe_wor_sabin_continue.lua`): `contract wor-sabin-v1 (entry): all 25
fields hold`, `[continue] world 1 at (131,179): CELES L27 HP 1211/1211
MP 251/251 row back esper+kit 06 0E 0F 76 8F D1 B5; SABIN L27 HP
1225/1225 MP 239/239 row back esper+kit 01 57 57 77 90 D1 D5; tonic=5
potion=47 fenix=27 remedy=5 gil=203243`, `PASS (frame 1386)`.

What the plan (sections 2-7) had right: the Light of Judgment is on the
way in and the bounce holds the party in town; the clock starts at (16,9)
at 21,600 frames with flags `$72`; the links are (102,53) -> (125,23) and
(126,22) -> (103,52); the child is "face up and hold A" on (117,12);
Sabin joins at `max(26, 27)` = 27 with nothing equipped. What it did not
know: Tzen's exit returns the party to (131,179), the tile it stepped
into the door from (the parent map), not onto the door (130,179); and
the house's timer is stopped by `stop_timer 0` early in Sabin's scene
(`:90071`), well before `$028A` is set (`:90262`), so a watch for an
expired clock ends at the house's exit.

### 11.2 The clock, read by the driver

The timer is read off `$1188-$119F` (`M.sceneTimer`: the live timer that
runs through menus and battles -- not FIELD_ONLY -- and is drawn there,
MENU_BATTLE_VISIBLE; a clock a person can see) and said at every step: the generator's own lines, the walkers' heartbeats (`nav f... |
timer 0 4:44 left ...`), and the fight driver's `[timer]` lines as each
battle opens and at its end hook (`[timer] battle $0D1 over at f+2603:
timer 0 5:13 left ...; the battle took 2568 frames of it`). No menu
opens inside the house: the walkers' field care already stays out under
any live counter (`eventTimerLive`). Under such a clock the driver's
top-up fraction drops to 30% (`M.TIMED_HEAL_PERCENT`) and its menu
cadence to a press every 12 frames (`M.TIMED_CADENCE`, against 30):
"no dawdling", a heal only for a member inside the round or the rounds
the kill needs, or under 30%.

The A/B, both levers together, 8 draws a side (K = 0-7 encounters used
up on the plains first, shift 0), with the Genji kit the plains leg
wore (`lab/ab_on/`, `lab/ab_off/` = `H.TIMED_HEAL_PERCENT = 55`,
`H.TIMED_CADENCE = 30`; `lab/abtable.py`, `lab/housestats.py`):

| arm | runs | Scorpion trios won in (ticks) | timer at the house's exit (frames) | heal plans in the house | lost |
|---|---|---|---|---|---|
| timed levers on | 8 | 2075-3227, mean 2493 (23) | 7362-14076 | 1 | 1 (k3: a pincered Scorpion trio) |
| timed levers off | 8 | 2491-6779, mean 3179 (23) | 3920-12796 | 9 | 1 (k0: a pincered Scorpion trio) |

With the Back Guard kit, the shipped one (11.4), the same pair on the same
8 draws (`lab/ab_bg/`, `lab/ab_bg_off/`):

| arm | runs | Scorpion trios won in (ticks) | timer at the house's exit (frames) | Doom margin, min (11.3) | lowest CELES HP on the battle lines | heal plans | lost |
|---|---|---|---|---|---|---|---|
| timed levers on | 8 | 2274-4127, mean 3502 (24) | 4099-11730 | 354 | 248 | 3 | 0 |
| timed levers off | 8 | 3667-4844, mean 4154 (24) | **139**-10930 | 133 | 550 | 12 | 0 |

Off, four of the eight left the house with under 40 seconds on the clock
(`ab_bg_off/k0_s0.log`: `timer 0 at 0:02 (139 frames)`; k5 0:21, k6
0:37, k7 0:22): the same draws that leave it with 1:08-1:29 on. The
price of the levers is HP: fewer top-ups, so she runs lower (248 against
550 at the worst), which the heal policy's one-round and kill-rounds
rules still cover.

The same rules apply wherever a visible clock runs through battles; on the
World of Balance that is the opera's rafter chase (flags `$70`), the
banquet and its sparring window (`event_main.asm:97422`, `:98023`), and
the Floating Continent escape (the 6:00 master clock and Shadow's 5:55,
`$78`). The World of Balance also runs timers a person never sees -- the
Sealed Gate cave's cycling puzzle timers (`start_timer 1, 144, _cb2c57`
and its neighbours, `:44640-44858`, flags `$09`) and Owzer's mansion's
(`:48206-48253`) -- and those do not count: the first cut read any timer
that was not FIELD_ONLY, so the levers switched on for a Sealed Gate cave
battle and every later battle of `gen_gate_cave_save` played differently
from main's lib (the review's `build/attempts/review-wor-sabin/
gate_cave_ab.txt`: battle `$097` 4252 ticks on main's lib against 4404,
`[timer] ... flags $09`). With the visibility bit required, the same
generator from `narshe-mission-v1` on this lib and on origin/main's plays
the same run: six battles, 2733 / 1959 / 4252 / 3978 / 5342 / 3678
ticks, `PASS (frame 41114) attempts=1/3` on both, no `[timer]` line
(`build/attempts/wt/wor-sabin/review-fixes/gate/gate_cave_ab.txt`). `gen_fc_escape`
from `fc-alcove-v1`, 3 shifts a side (`lab/wob_fc_escape/`, `lab/wob_timed.py`):
all six PASS; the timed battles (four escape-map fights and Nerapa)
took 7149-9940 frames of Shadow's clock with the levers on against
9131-10288 off (the sum of each run's `the battle took N frames of it`), and Nerapa ended with 2:20 / 2:49 / 3:07 left on
against 2:34 / 2:15 / 2:26. The rafter chase was regenerated under the
rules by the suite run (`gen_opera6_rafter`, `suites/fixtures/ultros2_entry.log`):
three rat fights, each 2389-2622 frames of the clock, the last ending
with `timer 0 1:48 left`, `PASS (frame 19632) attempts=1/3`; not A/B'd.
With the visible-clock check and the run rule, on the merged ROM
(`review-fixes/suites/ultros2_entry.log`): four rat fights, each `an event
battle: fought, never run from`, each under the levers, the last ending
with `timer 0 1:27 left`, `PASS (frame 21184) attempts=1/3`; the escape
likewise (`review-fixes/escape/gen_fc_escape.log`: the four escape-map
fights and Nerapa under `timer 2 ... flags $78`, the escape map's two
random fights `fits, fought`, `PASS (frame 76601) attempts=1/3`).

### 11.3 Condemned, alone

Every Scorpion opens with Doom Sting (special `$48`, Condemned). Alone,
CELES cannot be raised after the Doom and no item clears it, so the
count is the fight's own clock. The plan (sections 5, 9) is the kill
inside the count, and the driver plays it as it plays any fight (the
Doom's last-turn rule spends every pip when the count beats her next
turn); what is new is the race said out loud once per count:
`[doom] f+T actor=0 fights ALONE and CONDEMNED at C: the Doom in about
C x 128 frames (f+D) ...`. Measured (`lab/housestats.py`: the first
`[doom]` line's projected Doom tick less the tick the battle ended):

| kit | condemned fights | margin, min | margins under 1000 ticks |
|---|---|---|---|
| Genji pair (`ab_on/`) | 16 | 1846 | 0 |
| Back Guard, one hand (`var-final/`) | 48 | 354 (`k1_s0`) | 5 (354, 694, 748, 772, 798) |

No Doom landed in any run. With one hand the race is real: a Scorpion's
two shields take a boosted Fight or two turns, so the fights run longer
(11.4) and a low count roll (29 of 29-54) against a slow fight is the
case to watch.

### 11.4 The layouts, and the kit

`ChooseBattleType` (`battle_main.asm` @2e3a) rolls pincer and back attack
at 8 of 224 each for a party under three (side attacks are masked out).
With the Genji kit they came in 5 of 54 house fights (`ab_on/`,
`ab_off/`: 2 pincers, 3 back attacks). A pincer forces the row to front
and the blows land from behind: the Scorpions hit 177, 186 and 122
(`ab_off/k0_s0.log`: `slot 3's smallest hit this fight so far: 177, on
entity 0 (793 -> 616)`), about three times the 60 they land on her in
the back row, and both pincered Scorpion trios killed her (`[death] f+1592
entity 0 char 6 from 124/1211 by slot 4`, `[wipe] ... class=worn down
(no one-shot, no pips banked)`). A back attack costs time instead (6779
and 4839 ticks, `ab_off/k1_s0.log`, `k3_s0.log`).

So CELES wears the **Back Guard** in the Genji Glove's slot from before
the clock until Sabin has joined (`HOUSE_BACK_GUARD`; leaving the Relic
screen runs the game's Optimum: `after=11 5C 76 8F E1 B5`, the Break
Blade and a shield). The **Jewel Ring** stays: the HermitCrab's Rock
(special `$46`: no damage, Petrify) is gated like the Chitonid's
Sneeze (`if_num_monsters 1`, which fired on the Chitonid's own killing
blow, section 10.3), so no kill order keeps it quiet, and a statue is a
lost fight alone. The kit's
price is the second hand: Scorpion trios are won in 2232-4171 ticks
(mean 3553, 48 fights, `var-final/`) against 2075-3227 (mean 2493) with the
pair, and that is where the Doom margin (11.3) and the clock's margin
(11.6) went.

Per #258 the last-stand order stays at its default (the Sneeze only):
the Jewel Ring answers the Rock, no Petrify landed in any house fight
measured, and nothing measured asks to widen it.

### 11.5 The harness pieces

- **"Face up and hold A"** is `H.faceAndHoldA(dir, pred, maxFrames,
  what)` in `lib/ot6_field.lua`, promoted from `gen_terra_caves.lua`,
  which now calls it. From one `terra_narshe` input the generator before
  and after the change wrote byte-identical `terra_caves.mss`
  (`lab/terra/`: `047a1368...` both, from the seeded `terra_narshe.mss.lua
  sha=f79178a9a7c1`), and the graph's regeneration on this ROM's fresh chain
  (`nice ninja build/states/terra_caves.mss.lua`: `terra_caves generated at
  frame 1526`, `PASS (frame 1526) attempts=1/3`) wrote the same bytes as the
  old generator from that input (`c7f4519d...` both,
  `lab/terra/sha256_fresh_chain.txt`). At the child (`lab/face/`, one
  snapshot on (117,12)): the verb sets `$028B` in 140 frames (`[face] arm
  ok f148 the child's switch $028B=1`); with its A presses stripped (a
  mutant) or from (118,12) it times out (`timeout after 1200 frames
  driving toward face up and hold A (noA)` / `(offtile)`).
- **A member who left** is out of the care lines (`M.leftMask`, $3A39,
  read by makePlan's `hpNow` / `maxOf`, the party's damage window and
  the raise rule's top-up race). Natural play never produced the case
  the rule changes: 43 members sneezed out with others still in on the
  review's WoB lab and 9 more here at a 95% heal fraction, 52 in all
  (`lab/left/`: 5, 3 and 1 in `aware_s0/s7/s14`, the same 9 again in
  the `mutant_*` arm with the mask stubbed off; `leftscan.py`: `0 plan(s)
  on a left member` in both), every one above the
  fraction when it left. `battle_left` (`@suite`, kolts_cave) stages it
  with declared waivers: entity 2 marked in $3A39 and set to 80/241 HP at
  actor 1's window, three windows later `a plan on the member who left:
  nil`, `PASS (frame 2326)`; with `H.leftMask` stubbed to 0 the same
  window reads `[left] actor=1 heal entity 2 (80/241) with $E8 ...
  (covering an ally)` and the suite goes red (`lab/left_suite/`).
- **The hand-back is not a battle.** A walk that ended on one battle's
  `[outcome]` and a new walker built on the next frame read the battle's
  hand-back as a second battle (`lab/ghost/k1_s0_before.log`: `[outcome]
  battle $0C7 WON after 59 ticks (no end reading: the last frame's) ...
  XP MISMATCH`, and the generator's "judged on its own end reading"
  assertion went red). A driver whose watch begins within 90 frames after
  the last end hook now says `[tail]` and seats nothing
  (`lab/ghost/after/k1_s0.log`: `[tail] f+6 the last battle's end hook
  fired 3 frames before this watch began`, and the run passes) The 90-frame bound is measured, since the review: over the whole
  regenerated chain and suite set on the merged ROM (192 run logs,
  `build/attempts/wt/wor-sabin/review-fixes/gaps/summary.txt`), `184
  battles opened after an earlier one's end hook, the nearest 112 frames
  after it; 1 hand-back tails, the farthest 73 frames after it` -- the
  nearest real one the opera's rafter rats in a row (`ultros2_entry.log`),
  the tail `battle_classtarget`'s. The bound sits between them, with
  39 frames on the near side.
- **The lone fighter's race** (11.3) and the **timer** (11.2) are in
  `lib/ot6.lua` (`Driver:watchTimer`, `Driver:healPct`,
  `Driver:cadence`, makePlan's `[doom]` line).

### 11.6 Under real draw variation

`lab/varlab.py` (after `gen_wor_tzen_door`'s) derives the generator with
one block after the boot that fights K encounters on the plains beside
Tzen (the grind waypoints, off every tile outside groups 31/34) and walks
back to (131,179), so the body starts from another step counter,
encounter counter, HP and bag: `$1FA1-$1FA5` moves with every step and
every encounter, world and field alike, so the house deals other
formations and battle counts (K is a floor: the count is checked between
walk legs, and a leg can hold two battles: K=5 used 6, and K=6, 7
and 8 each used 8). Retries off
(`OT6_RETRIES=1`). `lab/var-final/summary.txt`, `housestats.txt`, `vartable.md` (the
shipped generator; `lab/var/` is the same set on the file before its
lowest-HP reading moved from her record to the battle's table, with the
same verdicts and frames):

| variant | the body starts at | house battles (the timer at each end) | the timer at the exit (frames) | lowest CELES HP on the 300-tick battle lines | verdict |
|---|---|---|---|---|---|
| K=0, shift 0 | the checkpoint (`$1FA1-2` as saved) | 4 ($0D1 4:56, $0CF 3:35, $0D1 2:34, $0D1 1:09) | 1:08 (4099) | 248 | `PASS (frame 31550) attempts=1/1` |
| K=0, shift 23 | the checkpoint (`$1FA1-2` as saved) | 4 ($0D1 4:57, $0CF 3:46, $0D1 2:36, $0D1 1:15) | 1:13 (4421) | 322 | `PASS (frame 31245) attempts=1/1` |
| K=0, shift 41 | the checkpoint (`$1FA1-2` as saved) | 4 ($0D1 4:54, $0CF 3:43, $0D1 2:30, $0D1 1:02) | 1:01 (3685) | 309 | `PASS (frame 32046) attempts=1/1` |
| K=1, shift 0 | L27, 991/1211 HP, `$1FA1-2 = 22 18` | 3 ($0CF 4:50, $0D1 3:36, $0D1 2:10) | 2:06 (7562) | 356 | `PASS (frame 31118) attempts=1/1` |
| K=2, shift 0 | L27, 991/1211 HP, `$1FA1-2 = 5C 19` | 2 ($0D1 4:40, $0D1 3:22) | 3:15 (11730) | 657 | `PASS (frame 31806) attempts=1/1` |
| K=3, shift 0 | L27, 910/1211 HP, `$1FA1-2 = 76 1A` | 3 ($0D1 5:09, $0D1 3:55, $0D1 2:44) | 2:38 (9537) | 603 | `PASS (frame 31625) attempts=1/1` |
| K=3, shift 23 | L27, 989/1211 HP, `$1FA1-2 = 76 1A` | 3 ($0D1 4:45, $0D1 3:25, $0D1 2:17) | 2:12 (7938) | 650 | `PASS (frame 36634) attempts=1/1` |
| K=3, shift 41 | L27, 824/1211 HP, `$1FA1-2 = 76 1A` | 3 ($0D1 4:43, $0D1 3:21, $0D1 2:07) | 2:02 (7344) | 673 | `PASS (frame 39330) attempts=1/1` |
| K=4, shift 0 | L27, 813/1211 HP, `$1FA1-2 = B8 1B` | 3 ($0D1 4:56, $0D1 3:47, $0D1 2:31) | 2:21 (8490) | 665 | `PASS (frame 39778) attempts=1/1` |
| K=5, shift 0 | L28, 1301/1301 HP, `$1FA1-2 = EC 1D` | 4 ($0D1 4:59, $0CF 3:50, $0D1 2:38, $0D1 1:23) | 1:15 (4549) | 390 | `PASS (frame 44305) attempts=1/1` |
| K=6, shift 0 | L28, 878/1301 HP, `$1FA1-2 = FC 1F` | 4 ($0D1 4:49, $0D1 3:36, $0D1 2:39, $0D1 1:33) | 1:29 (5373) | 844 | `PASS (frame 50684) attempts=1/1` |
| K=6, shift 23 | L28, 985/1301 HP, `$1FA1-2 = FC 1F` | 4 ($0D1 4:49, $0D1 3:35, $0D1 2:31, $0D1 1:25) | 1:21 (4887) | 788 | `PASS (frame 51500) attempts=1/1` |
| K=6, shift 41 | L28, 1082/1301 HP, `$1FA1-2 = FC 1F` | 4 ($0D1 4:48, $0D1 3:25, $0D1 2:21, $0D1 1:36) | 1:32 (5559) | 533 | `PASS (frame 53194) attempts=1/1` |
| K=7, shift 0 | L28, 862/1301 HP, `$1FA1-2 = 0C 1F` | 4 ($0D1 4:54, $0D1 3:44, $0D1 2:37, $0D1 1:30) | 1:22 (4949) | 441 | `PASS (frame 54781) attempts=1/1` |
| K=8, shift 0 | L28, 900/1301 HP, `$1FA1-2 = 14 1F` | 4 ($0D1 4:55, $0D1 3:45, $0D1 2:38, $0D1 1:31) | 1:21 (4862) | 499 | `PASS (frame 52762) attempts=1/1` |

15 of 15 PASS, 53 house battles (48 Scorpion trios, 5 HermitCrab pairs
with the Pm Stalker), every layout normal (the Back Guard), every
`[outcome]` said at the end hook and paid as due, no Doom, no Petrify, no
Fenix Down. The K walks met the plains as the last leg did, a pincered
Gilomantis + Mesosaur among them (`lab/ghost/after/k1_s0.log`, won). The
clock is the margin to watch: every run with four house battles left the
house with 3685-5559 frames (1:01-1:32), and a Scorpion trio costs 2232-4171
ticks; a fifth battle (the pool model's P(5) = 3.3 %, section 3.3; none in these
15) would fit only when it is quick, a sixth would not. That is the
price of the Back Guard kit (11.4), paid to take the pincer out.

Measured against these 15, and before the run rule (11.8):

- A house fight costs the clock 2197-4151 frames, mean 3526 (53 fights,
  the sum of `the battle took N frames of it`). At the tightest
  four-battle exit, 3685 frames, a fifth fight at the measured costs
  loses 13 times in 53, about one attempt in four; over all nine
  four-battle exits against all 53 costs it loses 15 times in 477. A
  sixth loses in all but 18 of 12,402 pairings of two costs against the
  nine exits: it always loses, for practical purposes.
- The measured battle counts run above the model in section 3.3: over the
  nine distinct draws (shift 0; a seed shift does not move the draw)
  3.44 house battles a draw, four in 5 of 9, against the model's mean
  2.78 and P(5) = 0.033. So that P(5) is not a bound on how often a
  five-battle house comes.
- The runner's retries replay the same formations: the encounter draw is
  save data (`$1FA1-$1FA5`), so a second attempt from the checkpoint meets
  the same house, and a lost five-battle draw would be lost again. A retry
  does not decorrelate the clock.
- The expiry is a lost attempt, said: a lab copy that stands still 16,000
  frames at the house's door (`lab/forced/dawdle/k0_s0.log`, the LOST:
  guard's negative control) ends `FAIL: LOST: the house's timer ran out at
  f25886 on map 311 (124,24) -- child not rescued`.

### 11.8 Running from what the clock cannot cover

The owner's rule (docs/guidelines.md, "Fight, don't flee", 2026-09-28):
inside a timed scene with a visible clock, a person runs from a random
battle when the time left cannot cover another fight. The driver does it
(`Driver:watchTimer`, `Driver:runFrame`): at a random battle's open
(OT6_RANDBTL's copy for the battle, read at f+6) under a visible clock it
says the arithmetic -- `[timer] f+6 battle $0D1 (random) fits, fought:
8336 frames left, this fight costs ~4151 (the caller's measure), 1839
frames of walk ahead: 4151 + 1839 = 5990 <= 8336` -- and when the sum is
more than the time left it holds L+R (backing out of any open menu)
until the party is gone, or fights on if the formation refuses the run
(`$B1` bit 1, `$2F4B` bit 0) or has not let it go in 1200 frames. An event
battle is never run from (`gen_fc_escape`: `battle $1A3 is an event
battle: fought, never run from`), and nothing is decided outside a
visible clock. `gen_wor_sabin` gives the fight's cost as the house's
measured worst, 4151 frames, and the walk ahead as the steps still to
walk to the exit (the current leg's plan from where she stands, the later
legs whole: 44, 26, 27 and 43 steps) at 17 frames a step, plus the
child's scene (150) and the links still to cross (40 each).

The long houses, forced (`lab/forced/`, `varlab.py --dawdle` / `--pace`,
the run rule on and off by `H.TIMED_RUN`; retries off). No natural draw
in the variation set met a fifth house battle, so the clock was taken
away instead, by a declared lab-only expedient: CELES stands still at the
house's door for one fight's worth of clock -- 4151 frames, the measured
worst, a fifth battle -- or two average ones, 7052, a sixth, on four-battle
draws (`dawdle_summary.txt`):

| stood still | rule | K0 s0 | K0 s41 | K6 | K7 |
|---|---|---|---|---|---|
| 4151 (a fifth) | off | `LOST: the house's timer ran out at f26148` | PASS, 476 left | PASS, 1492 | PASS, 1678 |
| 4151 (a fifth) | on | PASS, 1 run, 3276 left | PASS, 476 | PASS, 1492 | PASS, 1678 |
| 7052 (a sixth) | off | LOST (f26148) | LOST (f26238) | LOST (f47635) | LOST (f48571) |
| 7052 (a sixth) | on | PASS, 1 run, 974 left | PASS, 1 run, 1815 | PASS, 1 run, 871 | PASS, 1 run, 330 |

Where every fight fits the rule changes nothing: the runs it leaves alone
end on the same frame in both arms (K6: `PASS (frame 56300)` twice; K7
`57057`; K0 s41 `35254`). A first cut of the lab paced upstairs,
(122,19) <-> (122,24), until 1-4 more battles came (`pace_summary.txt`):
paces 1 and 2 met no extra battle (the danger counter spreads the same
steps' encounters: still four), and paces 3 and 4 did (five to eight
battles met), but the pacing itself walks the clock away after the rule
has run -- off, 0 of 6 passed; on, 3 of 6 (`pace3_run/k6`, `k7`,
`pace4_run/k7`, the last with eight battles met, four of them run, and
210 frames left). In `pace3_run/k0` a fight the rule let through (7707
left, 4151 + 1839 needed) cost 5248 frames, more than any of the 53
measured: CELES opened it at 382 HP and spent two turns on Cure. The
rule prices a fight at the measured worst and cannot see that one coming.

On the natural draws the rule changes nothing: the variation set rerun on
the final tree, with the run rule and the visible-clock check, and on the
merged ROM (`build/attempts/wt/wor-sabin/review-fixes/var/`: the same 15
variants) is 15 of 15 PASS with 53 house battles, 0 run decisions and a
`fits, fought` decision for every house battle (`run_decisions=0` in all
15 summaries); the house exit 3685-11839 frames, every `[outcome]` paid
as due, the Doom margin at least 354 ticks, the clock cost of a house
fight 2960-4151 frames (mean 3623). K0 s0, K0 s23, K0 s41, K1 and K3
s41 end on the frames they ended on before; the others moved with the
merged ROM's plains fights.

The run itself, over the 19 run decisions in `lab/forced/`: 18 ended
`PARTY LEFT` (the whole party gone, no reward, `paid as due`) after
350-858 ticks, 314-822 frames of the clock; none was refused (the
house's formations let a party run, `$B1`/`$2F4B` clear); the 19th was
decided with 26 frames left and the clock ran out under it
(`pace3_run/k0`).

`wor-sabin-v1` boots CELES and SABIN at world (131,179), both L27, full;
CELES in the plains kit again (`06 0E 0F 76 8F D1 B5`), SABIN `01 57 57
77 90 D1 D5`; both in the BACK row (Sabin arrives there; unmeasured for
him: his Fight and Blitz are melee); Potion 47, Fenix Down 27, Remedy 5,
Tonic 5; SERAPHIM held; 203,243 GP.

---

## 12. The Black Drgn on the sand, played (#300)

Played 2026-09-29. Until now §2.3 and §10 kept every walk off the desert
beside Tzen's door (world group 36), so the Black Drgn was designed
(§8.2: `4 · slash`) but never fought. `tools/tests/probe_black_drgn.lua`
cold-Continues a battery that saves at (131,179) and optionally uses up K
plains encounters first. It then walks onto the sand, the way someone who
does not know what is there would, and paces a six-step stretch,
(130,180) <-> (125,179), until formation 195 has been fought once. Every
battle is fought by the walkers' tactical driver on its defaults, with
field care after each one; nothing is written. Every battle's open logs
its RNG key: the seed `$be`, the formation and `$1FA1-$1FA4`, in lib's
`firstBattleKey` shape. `tools/tests/probe_black_drgn.py` runs the
variants with `OT6_RETRIES=1` and tallies them. The logs are under
`build/attempts/wt/black-drgn/`, in `solo-final/`, `solo-sweep/`,
`pair-final/` and `pair-sweep/`, each with a `tally.txt`.

The pool comes from the ROM: `[drgn] the sand: 65 tiles of group 36 ...;
pool slot1:194 slot2:195 slot3:194 slot4:195`. Slot odds are
80/80/80/16, so the dragon is 37.5% of the sand's draws and EarthGuard +
Peepers x2 is 62.5%.

| arm | runs | draws | dragon won / lost | distinct battle keys | ticks when won | Zombie landed |
|---|---|---|---|---|---|---|
| CELES alone, `wor-tzen-door-v1` (L27, Maduin, Blizzard + ThunderBlade on the Genji Glove, Gold Helmet, Gold Armor, Jewel Ring, back row) | 36 | K = 0-11 plains encounters first, shifts 0/23/41 | **34 / 2** | 33 | 2533-3276, median 2719 | 2 (both losses) |
| the same | 60 | K = 0, shifts 0-59 | **60 / 0** | 35 | 1982-3806, median 2742 | 0 |
| CELES + SABIN, `wor-sabin-v1` (both L27; SABIN IFRIT, Fire Knuckle x2 on the Genji Glove, Tiger Mask, Power Sash, Black Belt) | 36 | K = 0-11, shifts 0/23/41 | **36 / 0** | 33 | 1227-4661, median 2048 | 1 (SABIN) |
| the same | 60 | K = 0, shifts 0-59 | **60 / 0** | 60 | 1235-2442, median 2106 | 0 |

Across both arms: **CELES alone won 94 of 96 on the first attempt; the pair
won 96 of 96.** The solo runs drew 66 distinct keys and the pair runs 90.
A seed shift that lands on the same `$021e` phase and the same encounter
counters replays the same fight. The first solo set was rerun on the
final lab, which only adds logging, and every run ended on the same frame
(`solo/` against `solo-final/`, and `pair/` against `pair-final/`). No
dragon fight spent a Fenix Down or a Remedy. Three spent a Potion in
battle. 23 of the 192 fights dropped a Tent (`tent 10->11`).

**How the two losses happened.** Both drew seed `$14`. Both opened below
full HP: `battle open ... key be14-g00C3-eFB1F1717; CELES L28 ... HP
890/1301`, and in `k10_s41`, `HP 1084/1396`. The dragon's first action
was the first-cycle Sand Storm (`trace f+197 e0 hp 449/1301`). The driver
then spent CELES's turn on Cure, `no press: Fight at 1 BP lands 0 chip(s)
against 4 shield(s) ... -- caring`. That gave the dragon time for its
second-cycle action (`attack BATTLE, SPECIAL, SAND_STORM`, and SPECIAL is
BonePowder): `trace f+1068 e0 hp 0/1301 st1 $02`, then `[outcome] battle
$0C3 LOST after 1319 ticks` (`solo-final/k5_s41.log`). The same seed from
1168/1211 HP was won in 2854 ticks (`solo-sweep/k0_s17`). A won solo fight
is three boosted Genji Fights. The first one breaks all four shields,
for example `[outcome] battle $0C3 WON after 2767 ticks ... random
reward due 1560 a member (char 6 +1560 (due 1560)): paid as due`
(`solo-final/k0_s0.log`, lowest HP 1143/1211).

**The Zombie in the pair.** In `pair-final/k6_s0` the fight opened at
1141/1301 and 1157/1225. The Sand Storm hit, CELES spent a turn on a
party Cure, and BonePowder took SABIN (`trace f+1478 e1 hp 0/1225 st1
$02`). CELES won alone in 4661 ticks, and SABIN's share was 0 (`char 5
+0`). The field care then planned a Fenix Down, the game refused it,
and it left him a zombie: `REFUSED by the game: revive char 5 with $F0
(0/1225 hp, 211/239 mp, status1 02)` and `nothing more can be done: c5
0/1225 hp: down`. The bag held `revivify=2`.

**What the sand pays.** The dragon pays 1560 XP to each member and 1004
GP (`gil 222473->223477`; vanilla 780 XP and 502 GP, doubled for a
random battle). The other 62.5%, EarthGuard + Peepers x2, pays `10 a
member` in 700-1428 ticks. It also poisons: the field care spent 46
Antidotes on the 60 sweep EarthGuard fights (`plan: cure poison char 6
with $F2`), and neither Albrook nor Tzen sells Antidotes. Per 1000 ticks
of battle, the solo K runs' plains formations paid 400-813 XP and the
dragon paid 552 (`$0C3` including the two losses). Per sand encounter,
at 0.375 x 1560 + 0.625 x 10, the sand pays about 590 XP against the
plains' 1100-1600 a fight. The sand is worth meeting once and not worth
grinding.

**Recommendation.** The route plays the sand solo, where a person first
reaches it: on the walk to Tzen's door in `gen_wor_tzen_door`, after the
second Albrook stop and before the save. It meets the Black Drgn once
and then carries the avoid set as what the party has learned. The
measured first-attempt rate there is 94 of 96. Both losses are one
seed, entered below full HP, and a loss retries the segment. The cost is
about 1.7 EarthGuard fights (about 1050 ticks each, most of them Poison
and an Antidote), about 2700 ticks for the dragon, and about 0.2 Potions.
The party gains 1560 XP and 1004 GP. Meeting it after Sabin instead also
wins every time. There, though, a Zombie costs SABIN his share, and
today's field care cannot cure a real BonePowder Zombie, whose HP reads
0 (the pair-final line above). That arm would need the care fix first.

**In the route (#317).** `gen_wor_tzen_door` now does this: after the
second Albrook stop and the walk to (131,179) it steps onto the sand and
paces the same beat, (130,180) <-> (125,179), until formation 195 has
been fought, then walks back and saves. EarthGuard, Peepers and the Black
Drgn are allowed on that leg only; every other walk keeps the avoid set.
The leg's budget is the pool's own worst case: `the worst of the 65536
encounter-counter states needs 19 sand encounter(s) to deal the Black
Drgn ($0D5), 73.2% need no more than 3, 99.89% no more than 15`, asserted
at most 20. Under draw variation with retries off
(`build/attempts/wt/recut/`, the review-final varlab):

| boot | runs | K, shifts | PASS | dragon met in sand battle | losses |
|---|---|---|---|---|---|
| `wor-start-v1` before the #326 re-cut (`t317/var/`) | 36 | 0-11 x 0/23/41 | **33** | 2 in every run | 3, all one fight |
| `wor-start-v1` re-cut (`var/wor_tzen_door/`) | 18 | 0-5 x 0/23/41 | **18** | 5 to 8 | none |

The three losses (`k4_s0`, `k5_s41`, `k11_s0`) are the same fight: the
Sand Storm opener, a boosted Fight that breaks all four shields, then
`no press: Fight at 0 BP would hit broken slot 0 but the window's damage
1736 (e0:434x4) is short of its 3026 HP -- caring`, a Cure, a Fight that
takes it to `monhp=s0:66/sh0` (24 with its shields back by the next
sample), and BonePowder: `[death] f+3064 entity 0 char 6 from 1008/1211
by slot 0 cmd $00 atk $EF` in all three. That is the care-policy lab
named above (a Cure turn that gives the dragon its second cycle).
The re-cut `wor-tzen-door-v1` met it in sand battle 5 and won in 2567
ticks; CELES saves at L28.

---

## Appendix — key addresses

| thing | citation |
|---|---|
| FC exit strips all equipment | `:11979-11991` (`remove_equip` ×13); `EventCmd_8d` `field/event.asm:940` |
| WoR opening; Cid clock | `$00A4=1` `:12423`; `start_timer 0, 64, _ca533f, FIELD_ONLY` `:12448`; stops `:12533` / `:13023` |
| raft landing | `_ca55fe` `:12854` → `load_map 1, {146,212}` `:13014` |
| world entrances | `ShortEntrancePtrs` map 1: Albrook (140/141,209) → 324 (2,17); Tzen (130,179) → 305 (23,29) |
| Tzen map init | `_cc56da` `:89751` (`map_init_event.asm:324`) |
| Light of Judgment | trigger 305 (22,25)/(23,25) → `_cc583e` `:89859`; `$027D=1` `:89946` |
| the bounce | 305 (22,28)/(23,28) → `_cc58d4` `:89953` |
| Sabin / timer start | 305 (16,9) → `_cc58ff` `:89985`; `start_timer 0, 21600, _cc592e, …` `:90010` |
| timer expiry | `_cc592e` `:90014` → `call GameOver` `:90038` |
| the child | 311 (117,12) → `_cc5958` `:90040` (face up + A; `$028B=1`); NPC at (117,10) `npc_prop.asm:13564` |
| house exit | 311 (123,61) → `_cc5c59` `:90541` → 305 (16,9) |
| Sabin joins | `_cc5980` `:90069`; `stop_timer 0` `:90071`; `$028A=1` `:90262`; `char_party SABIN,1` `:90275`; `norm_lvl` `:90278`; `$02F5=1` `:90282`; control at 305 (15,14) `:90283` |
| Tzen inn (free heal mid-scene) | 308 keeper → `_cc5c8d` `:90562` |
| Tzen shops | `_cc5c81` 54 `:90555`, `_cc5ce2` 52 `:90610`, `_cc5cee` 53 `:90617`, `_cc5cfa` 55 `:90624` |
| Seraphim, 10 GP | 305 NPC_1 (29,3) → `_cc5ddd` `:90769` → `_cc5df4` `:90781` |
| Albrook shops / inn | `_cc60a2` 49 `:91208`, `_cc60ae` 51 `:91215`, `_cc60ba` 48 `:91222`, `_cc60c6` 50 `:91229`; inn `_cc62a6` 300 GP `:91503` |
| timer semantics | `event_cmd.inc:681-695`; `EventCmd_a0` `field/event.asm:3736`; `DecTimersMenuBattle` `:5562`; `DecTimers` `:5656`; `CheckBattleEnd` `battle_main.asm:12208-12221`; `field-ram.txt:684-690`, `:1009-1017` |
| solo loss statuses | `UpdateDead` `battle_main.asm:12600-12632` (`bit #$c2`, `:12625`) |
| Condemned count | `StartCondemn` `battle_main.asm:1590-1602` |
| side attack masked below 3 allies | `battle_main.asm:7874-7880` |
| world pools | `CheckBattleWorld` `field/battle.asm:97-213`; tables `:219-263` |
| OT6 rate / reward knobs | `Ot6DangerMulW` ½, `Ot6RewardMulW` ×2 `ot6_break.asm:367-370` |
| shields seed / formula | `Ot6SeedShields` `ot6_break.asm:54-113` |
| espers grant while worn | `genju_prop.asm:53-63`; Maduin `:114`; Seraphim `:173`; Unicorn `:183`; stats `ot6_progression.asm:524-547` |
| `norm_lvl` | `EventCmd_77` `field/event.asm:857-886`; `CalcAverageLevel` `:892-934` |
