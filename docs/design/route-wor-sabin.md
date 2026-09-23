# World of Ruin: the raft landing to Sabin (Tzen)

The route from the first World of Ruin save (Celes alone where the raft
from the Solitary Island lands) to Sabin joining in Tzen, and on to the
first save after he joins. It is planned from the game's own data; the
driving comes next, once the `wor-start-v1` checkpoint exists.

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
   kit (§5.2). Equipping her is the first action, unless the Solitary Island
   segment that cuts `wor-start-v1` has already done it.
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
| equipment | **possibly empty** (finding 1) | `$161F..$1624` for char 6 |
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
| `wor-start-v1` (the other agent) | world (146,212), Celes alone | the first WoR save |
| `wor-albrook-v1` (optional) | world, outside Albrook after shopping, re-equip and any grind | the grind's resume point |
| **`wor-tzen-door-v1`** | world (131,179), one step east of Tzen's door, *not* on the desert | the last save before the committed, timed scene; every house attempt retries from here |
| **`wor-sabin-v1`** | world (130,179) after leaving Tzen with Sabin | the first save after he joins; the end of this route |

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

### 8.2 The Solitary Island (world groups 29, 30; fought before `wor-start-v1`)

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
| a party of one; Death, Petrify or Zombie = loss | everywhere to Tzen | Petrify is "HANDLED (cured in battle) / not measured live"; a solo party gets no turn to cure it | Jewel Ring on; kill the Osprey first; kill order in 207; count every loss by cause |
| Condemned (Doom Sting) | house, 209 | HANDLED (`M.doomCount` / `M.doomRule`) | plan the kill inside the count; solo, nobody can raise |
| Sap (T. Lash, Slip Touch) | plains, house | **UNHANDLED** (no read; Remedy's STATUS2 `$48` does clear it) | at least log it; Remedy |
| Stop (Net) | house, 207 | HANDLED (planned around) | — |
| Monster Escape (a Mesosaur with company) | group 31 (both formations), group 35 | **UNHANDLED** (slot liveness only) | a battle can end with bodies escaped; XP accounting must not assume kills |
| Sneeze (Chitonid, last and hit) | formations 204 (group 34) and 201 (group 33) | **UNHANDLED** ("a character just ran away `$3A38`") | a solo sneeze ends the battle with no reward; the driver must not read it as a win or a wipe |
| face up + A trigger | the child (117,12) | PARTIAL: generator-local in `gen_terra_caves.lua` | promote an "examine" step into the lib, or reuse it |
| event timer through menus and battles | the house | HANDLED (`eventTimerLive` keeps menus out) | log the counter at each battle's start and end; no field care inside |
| committed scene (the bounce) | Tzen after the LoJ | none needed | do not route to the exit before `$028A=1` |
| map-init `mod_bg_tiles` | 305, 324 | the lib reads live RAM, so it is fine | the offline BFS counts here are **verify-on-arrival** |
| equipping from nothing, Genji pair, esper | landing; Sabin at Tzen | `M.equipKit`, `M.equipEsper` exist | assert the result slot by slot |
| world-map tiles to avoid | Tzen's door | `worldNavTo` has no avoid option (`worldBfs` takes only learned `blockedEdges`, `ot6_field.lua:1022`) | waypoint via (136,179), or add an avoid set; keep off the desert south and west of (130,179) |
| no Tonic seller | whole stretch | the care kernel falls back to Potions | size Potions from the logged spend; extend `audit_supplies.py` into the WoR |
| side attacks | — | masked out below three allies | none |

Other unknowns:

- **The Solitary Island segment's hand-off.** Whether `wor-start-v1`'s Celes
  is equipped, and how many Potions and Softs the island spent, sets the
  first Albrook shopping list. Read it on arrival.
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
