# World of Ruin: Edgar to the Falcon (Kohlingen, Setzer, Darill's Tomb)

The route from the first save after Edgar joins (`wor-edgar-v1`: CELES,
SABIN and EDGAR on the World of Ruin map outside the surfaced Figaro
Castle, (81,86)) to the Falcon rising out of Darill's Tomb, and on to the
first save beside it. It is planned from the game's own data, like
[route-wor-edgar.md](route-wor-edgar.md), whose shape it follows: findings,
the start state, the legs, the pools, the party, the bosses, the save points
and checkpoint cuts, the break data, the risks, then one "played" section per
leg, empty until it is driven. Milestone v0.24, #263; the side items #321
and #322 are placed in section 2.2.

Line numbers are into `ff6/src/event/event_main.asm` unless a path is given.
Decodes come from `tools/route_data.py` and the small scripts kept with their
output under `build/attempts/wt/wor-falcon-plan/route/` (the scripts run from
a tree root; `decode.sh` regenerates every file; ROM `1ef410a37c44`, main
`5f3b3d0b`). The labels are route-wor-sabin's: **verify-on-arrival** marks an
offline decode that holds unless the data moved (every field step count
here: the offline model has no NPCs, no turtles and no map-init
`mod_bg_tiles`), **UNVERIFIED** marks a claim that needs a live read, and
**estimate** marks a number the driving will replace with a measurement. No
emulator run was made for this plan.

---

## 0. Findings

1. **The story is four gates, each a switch the one before it sets**
   (section 2): the castle's engineer takes Figaro Castle to Kohlingen's
   desert (`$0106=1` -> `$00DC=1`, `_ca6908` `:15665`); SETZER joins in
   Kohlingen's inn when talked to (`$067F`, `_cc3bf8` `:85517`, `char_party
   SETZER, 1` `:85759`); the tomb's door opens only with SETZER in the party
   (`_ca3f83` `:9899`: `if_switch $01A9=0, EventReturn`); and reading the
   grave "DARYL SLEEPS HERE" starts **Dullahan, an event battle whose loss
   is a game over** (`battle 85` `:10537`, `_ca5ea9`). The grave's room then
   opens on the flashback and the Falcon (`_ca435d`, `_ca4502` `:10723`),
   which hands control back in flight over world (25,160) (`:11280`).
2. **The walks are short, and both ends of the castle's ride are desert.**
   Castle to Kohlingen is 29 steps, Kohlingen to the tomb 32 (`walks.txt`);
   each meets about half a battle by the pool odds. No on-foot path off
   either castle tile avoids world group 44, the Sand Horse desert
   (`[off group 44]: no path` both sides), so #321's fight is on the route
   whatever the plan does, now with EDGAR.
3. **The levels come from the tomb, not the walk.** The party is L31
   (`EDGAR: L31 HP 948/1600`, `SABIN: L31 ...`, `CELES: L31 ...`,
   `party_wor_edgar.txt`); Dullahan is **L37, 23,450 HP** (`pools.txt`).
   L33 is 9,715-16,904 XP away per member (`levels.txt`); the tomb's
   fights pay 970-2,960 per battle as randoms, split four ways. The level
   for Dullahan is a lab's to set (section 5), not this plan's.
4. **Every species met is new and rides the generated floor, except the
   desert's two** (Sand Horse, Maliga: authored in the Edgar arc). Twelve
   needed designed rows (section 8, now authored): four on the Kohlingen
   continent, five in the tomb, Dullahan, and the chest pair beside the
   tomb's save point. None of the nine random species appears in a World
   of Balance pool; the chest pair's formation 433 sits in WoB world group
   13's 16/256 slot, which no World of Balance tile deals (section 8.5).
5. **The tomb is the Zombie dungeon.** Four of its five species inflict
   Zombie (Orog's Zombite is its whole turn script; Osteosaur's Fossil and
   ChokeSmoke; PowerDemon's Soul Out; Exoray's DoomPollen; `ai.txt`), four
   absorb poison (EDGAR's Bio Blaster heals them), and all five are weak to
   fire, four to holy. The Mad Oscar's Sour Mouth carries Dark, Poison,
   Imp, Mute, Muddle and Sleep at once.
6. **SETZER joins with nothing equipped and no Esper** (the WoB ending's
   `remove_equip SETZER`; `SETZER: L25 ... gear: -, -, -, -, -, -; ...
   esper -`), and his join runs no `opt_equip`: the player dresses him.
   `norm_lvl SETZER` (`:85762`) lifts him to the trio's average level
   (L31 today; section 4.1).
7. **#319's kit gaps bite here** (section 4.3): SETZER joins with Slot
   alone (Coin Toss, Hired Help, Jackpot not built); EDGAR has 3 of his 8
   Tools, and Figaro's World of Ruin tool shop (84: Flash, Drill,
   Debilitator) refuses any party holding EDGAR or SABIN (`_ca67c0`), which
   is every party this arc can field.
8. **The South Figaro continent holds #322's three items and more**, all
   still closed at the checkpoint (`chests.txt`): the Hero Ring (map 90)
   is in a pocket the cave's *other* door reaches (`map 90 region 2: (41,14)
   door -> 68 (4,5); (52,14) chest Hero Ring`, and map 68's (4,4) is in the
   cave's main region), the Regal Crown (map 66) is off basement 2 of the
   castle the party must walk through to travel, and South Figaro's
   basement passage holds a **Ribbon**, a Hyper Wrist and RunningShoes
   (map 89) behind Duncan's house (86 (48,32) -> 87 -> 89). The Ribbon
   answers the tomb's Zombie and the Mad Oscar's Sour Mouth in one relic.
9. **One save point on the arc**, in the tomb's third basement beside the
   last chests and two rooms before the grave (map 300 (122,14), shown by
   `$0632`, which is set). It is the Dullahan retry point and the first
   field save-point checkpoint of the World of Ruin chain (section 7).

---

## 1. The start state (`wor-edgar-v1`)

The tracked battery (`tools/tests/checkpoints/wor-edgar-v1`), validated and
decoded from its slot 3 (`validate_wor-edgar-v1.txt`, `party_wor_edgar.py`):

```
valid ot6.sram-checkpoint/v1: 32768 bytes sha256=bd3d3dce9ca1... holds=slot 3 world 1 (81,86) [$1F64=$2001] (saved: declared and checked)
  EDGAR: L31 HP 948/1600 MP 270/294 XP 83184 party byte $71
    gear: Break Blade, Mithril Shld, Gold Helmet, Mithril Vest, Jewel Ring, Star Pendant; weapon class slash; esper Ramuh
  SABIN: L31 HP 1384/1609 MP 75/291 XP 86953 party byte $69
    gear: Fire Knuckle, Fire Knuckle, Tiger Mask, Power Sash, Genji Glove, Black Belt; weapon class slash; esper Ifrit
  CELES: L31 HP 1300/1595 MP 303/303 XP 90373 party byte $E1
    gear: Enhancer, ThunderBlade, Crystal Helm, Gold Armor, Genji Glove, Jewel Ring; weapon class slash; esper Maduin
    spells (6): Ice, Scan, Safe, Imp, Cure, Antdot
  SETZER: L25 HP 1045/1045 MP 221/221 XP 44072 party byte $00
    gear: -, -, -, -, -, -; weapon class bludg; esper -
```

The save was made without care: EDGAR at 948/1600 HP and SABIN at 75/291
MP. The first thing the arc does is field care.

| member | level | kit | commands |
|---|---|---|---|
| CELES | L31, xp 90,373 (L32 at 91,384) | MADUIN; Enhancer (slash, runic) + ThunderBlade (slash, bolt) on the Genji Glove, Crystal Helm, Gold Armor, Jewel Ring | Fight, Runic, Magic (Ice, Scan, Safe, Imp, Cure, Antdot; Fire/Ice/Bolt from Maduin; Haste at L32), Item |
| SABIN | L31 | IFRIT; Fire Knuckle x2 (slash, fire) on the Genji Glove, Tiger Mask, Power Sash, Black Belt | Fight, Blitz (Pummel, AuraBolt, Suplex, Fire Dance, Mantra, Air Blade), Magic (Fire, Drain), Item |
| EDGAR | L31 | RAMUH; Break Blade (slash), Mithril Shld, Gold Helmet, Mithril Vest, Jewel Ring, Star Pendant | Fight, Tools (AutoCrossbow, NoiseBlaster, Bio Blaster), Magic (Bolt, Rasp), Item |
| SETZER (not yet in the party) | L25 | nothing | Fight, Slot, Magic, Item |

Bag (64 rows): Potion 53, Fenix Down 29, Remedy 5, Soft 18, Revivify 4,
Green Cherry 5, Tonic 4, Tincture 7, Elixir 5, X-Potion 5, Ether 4, Tent 10,
Sleeping Bag 3, Warp Stone 1, Smoke Bomb 1; relics Czarina Ring, Jewel
Ring, Back Guard, Coin Toss, Star Pendant x3, Peace Ring, Memento Ring;
weapons for the arc: Soul Sabre, Blizzard, RegalCutlass, MithrilBlade x2,
Mithril Pike, MetalKnuckle, **Cards** (SETZER's), the rods; armor Ninja
Gear, Kung Fu Suit, Silk Robe, shields and hats; **254,895 GP**. Espers:
the thirteen of the World of Balance route (Ramuh, Ifrit, Shiva, Siren,
Shoat, Maduin, Bismark, Stray, Kirin, Carbunkl, Phantom, Sraphim, Unicorn),
ten of them spare.

The switches the arc reads (`party_wor_edgar.txt`): `$00C6=1 $00C7=1
$0106=1` (Edgar's scene done, the castle surfaced at South Figaro), `$00DC=0`
(not yet at Kohlingen), `$067E=1 $067F=1` (Kohlingen's World of Ruin people
and SETZER in the inn, set at the World of Ruin's start `:113035`),
`$00CA=0 $00CB=0 $00CC=0 $00CD=0` (no Setzer, tomb shut, no Falcon),
`$02B1-$02B8=0` (the tomb's switches), `$0632=1` (the tomb's save point
shown). Encounter counters `$1FA1-$1FA5`: `94 66 4F 82 4F`. The party bytes
put all three in the back row.

---

## 2. The legs and the story's gates

### 2.1 The whole arc

| # | leg | from -> to | steps | pools | gate |
|---|---|---|---|---|---|
| 1 | the South Figaro continent (side items, #321, #322) | world (81,86) -> South Figaro (113,95); the cave (106,98); back to (81,85) | 51 + 14 + 48 (world) | world 41, 43, **44**; cave 68/90 (138, 140); 87 (WoB pool 65) | none (optional) |
| 2 | the castle to Kohlingen | (81,85) -> 55 -> 59 -> 61, the engineer (6,33) | verify-on-arrival | none (maps 55, 59, 61 do not roll); **62 (137) for the Regal Crown** | `$0106=1` -> "Go to Kohlingen?" -> `$00DC=1 $0106=0` |
| 3 | the walk to Kohlingen | castle exit (53,58) (measured) -> (38,45) | 29 | world **44**, 45, 47 | none |
| 4 | Kohlingen: SETZER | 189 -> inn 191, SETZER at (23,15) | verify-on-arrival | none (towns) | `$067F=1`; joins unless the party is full (`$01A3`) -> `$00CA=1` |
| 5 | the walk to the tomb | (38,45) -> (25,52) | 32 | world 45, 46, 47 | none |
| 6 | the tomb's door | 297 (8,12) -> trigger (8,10) -> stairs (7,8) | 2 + verify-on-arrival | none | SETZER in the party (`$01A9`) -> `$00CB=1`, the stairs drawn (`_caf1a2`) |
| 7 | B1, B2, B3: the switches and the turtles | 298 -> 299 -> 300 | verify-on-arrival | field 149, 150, 151 | `$02B1`, `$02B3`, `$02B5`, `$02B6`, `$02B8` (section 2.6) |
| 8 | the east room and the save point | 300 (122,28) -> (122,14) | 22 | field 151 | none |
| 9 | the grave: Dullahan | 300 (122,7) -> 299 (100,28) -> (100,14) | 23 + 13 | field 151, 150; event group 85 | facing up + A -> `battle 85` (a loss is a game over) -> `$02B2=1` |
| 10 | the flashback and the Falcon | 299 (100,7) -> 301; SETZER (28,6), the trigger (17,16), SETZER again | verify-on-arrival | none | `$01F0-$01F3` -> `_ca4502`: `$00CC=1 $00CD=1 $039B=1`, control in flight at world (25,160) |
| 11 | land and save | world (25,160) | 0 | world 49 (the next arcs') | none |

### 2.2 The South Figaro continent (leg 1; optional; #321, #322)

The arc starts in the desert outside the surfaced castle: `(81,86) prop
$0246 walk group 44` (`tiles.txt`). Everything on the continent is
reachable on foot before the castle leaves, and nothing in the story needs
it. A player would go: the castle's shops refuse this party, and the
continent still holds:

| what | where | evidence |
|---|---|---|
| the desert's fights (#321) | world group 44, 18 steps of the walk to South Figaro and 19 back | `wor-edgar-v1 (81,86) -> South Figaro door (113,95) [#321, #322] [shortest]: 51 steps; steps by group: 41: 5, 43: 27, 44: 18`; `budget: mean 1.13 battles` |
| shops: Amulet 5000 (relic 62), Potions, Remedy (item 63), Enhancer (60) | South Figaro (route-wor-edgar 2.4) | `shop 62 ... $B3 Amulet: 5000 GP` (`shops.txt`) |
| **Ribbon**, X-Potion, Ether (#322) | map 89 region 0, by 74 (48,37) -> 86 (52,29) -> (48,32) -> 87 (56,49) -> (33,51) -> 89 (96,42) | `map 86 region 1 ...: (52,29) trigger _ca8973; (48,32) door -> 87 (56,49)`; `map 89 region 0 (81 tiles): (101,39) chest X-Potion; (97,41) door -> 87 (34,50); (101,43) chest Ribbon; (92,53) chest Ether` (`sfig_graph.txt`); all closed (`chests.txt`) |
| Hyper Wrist, RunningShoes (#322) | map 89 region 1, by 74 (15,18) -> 81 (4,16) -> (27,10) -> 83 (7,5) -> (32,18) -> 89 (106,54) | `map 89 region 1 (71 tiles): (110,49) chest Hyper Wrist; (105,53) door -> 83 (31,17); (120,53) chest RunningShoes` |
| Iron Armor, Earrings | map 87 (32,42), (33,56) | `map 87 region 0 ...`; closed |
| Hero Ring (#322) | map 90 (52,14), by the cave's other door: 68 (4,4) -> 90 (41,13) | `map 90 region 2 (33 tiles): (41,14) door -> 68 (4,5); (52,14) chest Hero Ring`; `map 68 region 0 ...: (4,4) door -> 90 (41,13)` |
| Regal Crown (#322) | map 66 (3,53), by 61 (2,37) -> 62 (12,13) -> (4,6) -> 66 (3,55); **measured: (4,6) is in a pocket of 62 only basement 3 reaches** (section 11) | `map 62 region 0 ...: (4,6) door -> 66 (3,55)`; `map 66 region 0 (15 tiles): (3,53) chest Regal Crown; (3,56) door -> 62 (4,8)` |

All of it is **verify-on-arrival**: the offline model has no NPCs and no
map-init tiles, and the Edgar arc found the Hero Ring "not reachable from
where the crossing leaves the party" only because it came in by 68 (10,2)
-> 90 (55,31), the turtle's side. The passage's map 87 rolls the World of
Balance's pool 65 (Vector Pup, Commander; a claimed WoB map), the castle's
basement 2 the cave's Muddle pool 137 (route-wor-edgar 3.3, 12.4: the Peace
Ring answer). The WoB clock in map 84 (`_ca7913`, `$01D1`) does not gate
either route into map 89.

**#321 fits here, with EDGAR.** The pair that walls CELES and SABIN (route-
wor-edgar 12.1: formation 222 won 6 and lost 2, both losses `class=died
with 3 BP banked` with both horses untouched, the driver heal-locked, #312)
now meets three, and the authored row (`2 · slash|pierce`) gives EDGAR's
AutoCrossbow both horses at once. Leg 1 plays the desert on the way to
South Figaro and back, and a lab measures formation 222's first-attempt rate
over distinct battle keys with the trio (section 9). The arc meets the
desert again at Kohlingen (5 steps) and on every later castle ride.

**#322 fits here too**: the Hero Ring and the passage on leg 1, the Regal
Crown on leg 2's walk to the engineer. If the owner prefers the side items
out of the story chain, leg 1 is the one to drop: legs 2-11 do not need it.

### 2.3 The castle's ride (leg 2)

In from the world tile (81,85) (`_ca5f0b`, `$0106=1`) to map 55 (28,42);
(28,38) -> 59 (12,49); (9,49) -> 61 (10,33); the engineer NPC_6 at (6,33)
(`maps.txt`). His talk (`_ca682f` `:15575`, in the World of Ruin `_ca68dc`
`:15646`) with `$00C6=1`, `$026F=0` and `$0106=1` offers "(Go to
Kohlingen?)" (`_ca68e6` `:15651`); choice 0 runs `_ca6908` (`:15665`): the
castle burrows from (81,85), and control returns in 61 (6,34) with the
world parent at the castle's new tile; `$00DC=1 $02B9=0` (`:15690`). The
castle's world trigger at Kohlingen is (53,58)/(54,58) (`_ca5f18`
`:14233`, gated on `$00DC`). The castle's exit returns the party one tile
below its trigger (measured at (81,86) in the Edgar arc), so (53,59) was
expected; **measured: (53,58)** (section 11). The ride is reversible ("(Go to
Figaro?)", `_ca6986`), so South Figaro's shops stay one ride away.

`_ca694f` (the "odd stratum", the Ancient Castle) runs only once `$00CD=1`,
which the Falcon's scene sets: not on this arc.

### 2.4 Kohlingen (map 189; no random battles, no save point)

The World of Ruin Kohlingen is map 189 (the WoB town is 188); its interiors
are shared and return to 189 while `$00A4=1` (`_cc6999`, `_cc697f`,
`_cc698c`).

| what | where | event |
|---|---|---|
| weapon 65, armor 66, item 67 | 194 NPC_1/2/3 (9,35), (15,35), (19,35), door 189 (11,11)/(14,13) | `_cc69a6` `:92679` (`shop_menu 65/66/67` in the World of Ruin) |
| inn, 200 GP | inn 191 NPC_4 (17,11), door 189 (16,22) | `_cc69ca` `:92700` |
| **SETZER** | inn 191 NPC_6 (23,15), `$067F` | `_cc3bf8` `:85517` |
| chests | 195 (37,53) Green Beret; 197 (42,10) Elixir | bits `$041`, `$045`, both closed |
| an old man who unequips the absent | 189 NPC_9 (9,17), `$06B6` | `_cc3510` `:84460` (hidden when SETZER joins) |

**SETZER** (`_cc3bf8`): "CELES: SETZER! / SETZER: You're alive!?", the talk
("I've lost my wings…"), a short flight cutscene over world (38,48), and
back in 189 (16,25): `char_party SETZER, 1` unless the party is full
(`if_switch $01A3=1` `:85757`; three members here, so he joins), then
`norm_lvl SETZER`, `max_hp`, `max_mp`, `$02F9=1`, `$067F=0 $06B6=0
$00CA=1` (`:85761-85777`). No `opt_equip`.

The exit: 189's long edges lead to the world parent (38,46) / (37,45)
(`maps.txt`); **measured**: the party comes out on the tile it stepped into
the town from, (40,45) after a walk in from the castle's side (section 11).

### 2.5 The tomb's door (map 297)

World (25,52) -> 297 (8,12). The trigger (8,10) (`_ca3f83` `:9899`) runs
once (`$01B5`, `$00CB`) and only with SETZER in the party (`set_case
PARTY_CHARS` / `if_switch $01A9=0, EventReturn`): "CELES: This person… She
was your friend? SETZER: Yeah.", the tomb shakes, `$00CB=1`, and `_caf1a2`
draws the stairs at (7,8) (the long entrance (7,8) -> 298 (13,12)). Without
SETZER the door does nothing.

### 2.6 Darill's Tomb (maps 298-300): the switches and the turtles

Every switch is a step-on trigger read with the facing and A held (the
`$01B0`-`$01B4` control byte, the Figaro turtle's "face and hold A",
`H.faceAndHoldA`). Read from the scripts:

| where | event | needs | does |
|---|---|---|---|
| 299 (28,43) | `_ca41a3` `:10298` | facing up + A, `$02B1=0` | `$02B1=1`, opens (28,38) -> 300 (61,44) |
| 300 (61,33) | `_ca41c3` `:10316` | facing up + A, `$02B3=0` | `$02B3=1`: the water (enables the B2 turtle) |
| 299 (56,14) | `_ca422e` `:10373` | facing **down** + A, `$02B3=1` | rides the turtle down to 300 (69,8), `$02B4=1` |
| 300 (70,8) | `_ca41e0` `:10331` | facing up + A | toggles `$02B5` (and `$0396`): moves the B3 turtle |
| 300 (71,9)/(71,10) | `_ca4278`/`_ca428d` `:10424` | facing **right** + A, `$02B5=1`, `$02B6=0` | rides it right 7, up 3; `$02B6=1` |
| 300 (79,6) | `_ca42c0` `:10473` | facing down + A, `$02B6=1` | rides it back; `$02B6=0` |
| 300 (76,10) | `_ca4216` `:10359` | facing up + A, `$02B8=0` | `$02B8=1`, opens (79,3) -> 300 (122,28) |
| 299 (100,14) | `_ca42f1` `:10508` | facing up + A | "DARYL SLEEPS HERE"; first time: Dullahan |
| 299 (12,39) | `_ca4037` `:10014` | facing up + A | the blank tombstone: carve the four found words (the B2 room (75..79,38..43), `$00C2-$00C5`) in the right order for a hint to the Exp. Egg (`$0112`); optional |

The regions the offline model finds (`tomb_graph.txt`), with what each
switch opens, give this order (**verify-on-arrival**, the order and every
count):

1. B1 (298): in (13,12) -> (13,24), 12 steps, to B2 (37,12).
2. B2's hub (299 region 5) holds the Genji Helmet (43,42), the Crystal
   Mail (9,59), the switch (28,43), the turtle (56,14), the tombstone and
   the stairs (17,61). The switch opens (28,38) -> B3 (61,44), whose small
   room (300 region 1) holds the water switch (61,33). Back up.
3. B2 (17,61) -> B3 (37,58) (300 region 3): the Czarina Gown (43,60; RELM's
   only), the **Exp. Egg** (55,58), and by (43,57) -> (76,19) the corridor
   to the wall switch (76,10), which opens (79,3).
4. Back to B2; the turtle (56,14) down to B3 (69,8) (300 region 2); the
   turtle switch (70,8); the ride from (71,9) to the far landing by (79,6)
   (300 region 4); up through (79,3) -> (122,28), the east room.
5. The east room (300 region 4): the **Man Eater** (124,9), the **monster
   chest** (120,9) (event group 116: Presenter and Whelk Head), the **save
   point** (122,14), and (122,7) -> B2 (100,28), the grave's room (299
   region 2): (100,14) the grave, (100,7) the way on once Dullahan falls.
6. 300 (69,17) -> 299 (77,34) is the carved-letters room (299 region 4),
   the tombstone puzzle's words.

Offline counts where the model reaches: `map 298 (13, 12) -> (13, 24) ...:
12 steps`; `map 299 (37, 12) -> (17, 61) ...: 31 steps`; `map 300 (122,
28) -> (122, 14) ...: 22 steps`; `map 300 (122, 14) -> (122, 7) ...: 23
steps`; `map 299 (100, 28) -> (100, 15) ...: 13 steps`; the switch rooms
and the turtles' landings say `NO PATH` (`walks.txt`).

### 2.7 Dullahan, then the flashback and the Falcon

```
event_main.asm:10508  _ca42f1: if_any $01B0=0 / $01B4=0 -> return   ; facing up, A held
               :10513         dlg $09A0 "DARYL SLEEPS HERE"
               :10516         if_switch $02B2=1, EventReturn
               :10537         battle 85
               :10538         call _ca5ea9          ; if_b_switch $40 (won), else call GameOver
               :10550         switch $02B2=1
               :10551         call _caf1ed          ; draws (100,7) open
```

The grave's room then leads up through (100,7) (`_ca435d` `:10565`):
SETZER leaves the party for the flashback (`char_party SETZER, 0`), map
301; control returns there. Talk to SETZER (NPC_5, (28,6); `_ca43d9`
`:10632`: "Watch your step", `$01F0`, the room redrawn), step on (17,16)
(`_ca44ba` `:10683`: Daryl's "If something should happen to me, the
Falcon's yours!", `$01F2`, `$01F3`), talk to him again (`_ca4502`
`:10723`): `char_party SETZER, 1`, the flight flashback, the Falcon in its
hangar (map 11), the first flight (map 17, "SETZER: But first we need to
find our friends!"), "CELES: Hey! A bird!", and the switches `$00CC=1
$00CD=1 $01B8=1 $01B9=1 ... $039B=1` (`:11257-11276`), `ResetTurtles`, and
`load_map 1, {25, 160}, ... AIRSHIP` (`:11280`): the party is aboard the
Falcon, flying, over `(25,160) prop $0544 walk group 49` (`tiles.txt`). `$039B`
shows Palidor on the Solitary Island's beach (magicite.md): the next arcs'.

### 2.8 Where the World of Ruin opens

Before the Falcon the party walks three landmasses joined by the castle and
the Nikeah ferry: the South Figaro continent, the Tzen continent (Tzen,
Albrook, Nikeah, **Mobliz**), and the Kohlingen continent, whose component
(`components.txt`: 1,704 tiles from (53,59)) also holds the World of Ruin
**Colosseum** (50,17), 52 steps from Kohlingen, and a chocobo stable
(62,39). The Colosseum is v0.35's and Mobliz v0.27's; this arc does not go
in. The Falcon opens the rest: Jidoor, Zozo, Maranda, Narshe, Thamasa, the
Veldt's cave, Doma, the Solitary Island's Palidor, and the castle's
stratum.

---

## 3. The pools

Decoded by `route_data.py pool` (`pools.txt`). Slot odds 80/80/80/16 of
256; XP is vanilla and a random battle pays x2 (`Ot6RewardMulW`). Every rate
on the arc is code 0 (world `$0060`/step, field `$0038`/step after
`Ot6DangerMulW`; a field battle every 44.8 steps on average).

### 3.1 The castle's desert (world group 44; both sides)

| p | formation | contents | XP |
|---|---|---|---|
| 31.25 % | 222 | Sand Horse x2 | 950 |
| 31.25 % | 223 | Sand Horse, Maliga x2 | 1195 |
| 37.5 % | 138 | Maliga x3 | 1080 |

### 3.2 The Kohlingen continent (world groups 45-47)

| group | terrain | p | formation | contents | XP |
|---|---|---|---|---|---|
| 45 | grass | 62.5 % | 236 | Harpiai | 449 |
| | | 37.5 % | 243 | Muus | 189 |
| 46 | forest | 37.5 % | 238 | Harpiai, Deep Eye x2 | 1219 |
| | | 31.25 % | 240 | **Deep Eye x6** (may pincer) | 2310 |
| | | 31.25 % | 242 | Muus x3 | 567 |
| 47 | plain | 62.5 % | 239 | Bogy x2 | 1064 |
| | | 37.5 % | 241 | Deep Eye x2, Muus x2 | 1148 |

(Group 46's slots 0 and 3 are both 238: 80 + 16 of 256.) Groups 45 and 47
are the tables of the World of Ruin's sectors x 0-95, y 0-95 beyond this
continent's tiles (`tiles.txt`: `group 45 tiles by sector (x0,y0): (0,0):
975, ...`), so other land there deals the same bodies (which land:
UNVERIFIED); the rows designed here carry to it.

### 3.3 Darill's Tomb

| group | map | p | formation | contents | XP |
|---|---|---|---|---|---|
| 149 | 298 (B1) | 62.5 % | 246 | Osteosaur | 770 |
| | | 31.25 % | 244 | Orog x2 (may pincer) | 1020 |
| | | 6.25 % | 245 | Orog, PowerDemon x2 | 1480 |
| 150 | 299 (B2) | 31.25 % | 247 | PowerDemon | 485 |
| | | 31.25 % | 249 | Exoray x3 (may pincer) | 1347 |
| | | 37.5 % | 250 | Mad Oscar, Exoray | 1229 |
| 151 | 300 (B3) | 31.25 % | 251 | Mad Oscar | 780 |
| | | 31.25 % | 250 | Mad Oscar, Exoray | 1229 |
| | | 37.5 % | 248 | PowerDemon, Exoray x2 | 1383 |
| event 85 | the grave | — | 455 | **Dullahan** `$11C` | 0 |
| event 116 | the chest (120,9) | — | 433 | **Presenter** `$101`, **Whelk Head** `$135` | 0 |

### 3.4 The encounter budgets

`walks.txt` (the draw byte modelled uniform: a pool-odds budget, not a
prediction for one save; the real draw is save data, `$1FA1-$1FA5`):

| leg | steps | mean battles | P(0) |
|---|---|---|---|
| (81,86) -> South Figaro | 51 | 1.13 (0.20 of them the desert) | 0.161 |
| the cave door -> the castle (81,85) | 48 | 1.07 (0.58 the desert) | 0.186 |
| castle exit -> Kohlingen | 29 | 0.43 | 0.598 |
| Kohlingen -> the tomb | 32 | 0.52 | 0.528 |
| B1, in -> B2 | 12 | 0.04 | 0.958 |
| B2, in -> the stairs to B3 | 31 | 0.32 | 0.693 |
| B3, the east room -> the save point | 22 | 0.16 | 0.841 |
| the save point -> the grave | 23 + 13 | 0.18 + 0.05 | — |

The tomb's whole walk (both switch rooms, the chest room, the turtles) is
not in the offline model; the leg's count is **estimate**: 5-8 battles by
the pool rate over 200-350 steps, plus any grind.

### 3.5 The species

`pools.txt`, `ai.txt` (the scripts whole, with their lines in
`ai_script.asm`), `boss_attacks.txt`. "Today" is the row the ROM ships.

| id | name | L | HP | def/mdef | weak | absorb / null | the script | today |
|---|---|---|---|---|---|---|---|---|
| `$05F` | Sand Horse | 27 | 1025 | 135/155 | ice, water | — | Sand Storm; Clamp (x5); **alone: B/B/Clamp** `:2020` | authored 2 slash\|pierce |
| `$097` | Maliga | 26 | 952 | 110/145 | ice, bolt, water | — | B; B/B/Scissors; **alone: Scissors x2** `:2005` | authored 2 slash\|bludg |
| `$089` | Harpiai | 29 | 1418 | 102/153 | wind | — | B/B; B/B/**Aero (wind 125)**; B/B/Pearl Wind; B/B/Nail `:2103`; starts Float | floor 5 slash |
| `$0DB` | Muus | 28 | 900 | 110/105 | — | null poison, wind, holy, earth, water | B/Gunk (Slow)/Pep Up; **counter to Magic: Pep Up** `:2118`; starts Shell | floor 5 slash |
| `$0A7` | Deep Eye | 28 | 1334 | 100/150 | fire | — | B/B/**Dreamland (Sleep)**; Escape `:2149` | floor 5 slash |
| `$0D3` | Bogy | 29 | 1318 | 102/153 | — | — | B/B; B/B/Oogyboog (x2) `:2138`; starts Safe | floor 5 slash |
| `$005` | Orog | 30 | 1584 | 105/140 | fire, holy | poison | **Zombite (Zombie)** and nothing else, up to three a turn; counter: Bio to Magic, Battle to a hit `:2179` | floor 5 bludg |
| `$010` | Osteosaur | 30 | 1584 | 115/155 | fire, holy | poison | B/**Fossil (Zombie)**; B/B/**ChokeSmoke (Zombie)**; B/B/Fossil `:2197` | floor 5 pierce |
| `$06F` | PowerDemon | 29 | 2058 | 145/140 | fire, holy | poison | B/B/Daze Dance (drain); B/B/**Soul Out (Zombie)** `:2223`; speed 40 | floor 5 slash |
| `$061` | Mad Oscar | 30 | 2900 | 95/145 | fire | poison, water | B; B/B/**Sour Mouth** (Dark, Poison, Imp, Mute, Muddle, Sleep); B/Drool (Sap) `:2210` | floor 5 slash |
| `$091` | Exoray | 29 | 1200 | 105/105 | fire, holy | poison | B/B/**DoomPollen (Zombie)**; alone: B/B/Virite `:2234`; starts Shell | floor 5 slash |
| `$11C` | **Dullahan** | 37 | **23450** | 130/160, evade 10 | fire | **ice** | section 5 `:5431`; starts Haste, Float; speed 55 | floor 6 slash |
| `$101` | Presenter | 19 | 9230 | 160/195 | fire | ice, bolt, water | section 6 `:4329`; starts Float | floor 4 slash |
| `$135` | Whelk Head | 31 | 9845 | 80/150 | fire | ice, bolt, water / null poison | section 6 `:6419` | floor 5 slash |

Notes the driving will need:

- **Zombie** is the tomb's status (finding 5). The field care cures it with
  Revivify (#190); in battle a zombied member attacks the party and a
  Fenix Down cannot land on it (#245). The Amulet (South Figaro, 5000) and
  the passage's Ribbon block it.
- The **Orog** acts only to Zombie a member, and counters a hit with a
  Battle and Magic with Bio; broken, it does neither (bosses-wob "the boss
  contract").
- The **Muus** turns Magic into a Pep Up on its own side and nulls five
  elements: a Fight body.
- The **Deep Eye** sleeps a member and can Escape (no XP for an escaped
  body; `Driver:watchLeavers`, #255). Six of them can pincer.
- The **Bogy** starts with Safe (physical damage down), the **Exoray** and
  the **Muus** with Shell (magic damage down).
- The **Mad Oscar**'s Sour Mouth is six statuses in one: Remedy cures it,
  the Ribbon blocks it.
- **Last-stand bodies** again: the Sand Horse and Maliga (route-wor-edgar
  3.5), the Exoray (Virite when alone), the Muus.

---

## 4. The party and its kit

### 4.1 Levels

The trio is L31; the arc's random bodies are L28-L30, Dullahan L37. From
`levels.txt`:

```
L32: 91384 xp; EDGAR needs 8200; SABIN needs 4431; CELES needs 1011
L33: 100088 xp; EDGAR needs 16904; SABIN needs 13135; CELES needs 9715
L34: 109344 xp; EDGAR needs 26160; SABIN needs 22391; CELES needs 18971
```

and a tomb battle pays 970-2,960 XP as a random (`Orog + PowerDemon x2
(245): vanilla 1480; as a random x2 = 2960; ... of four 740`). CELES
reaches L32 (Haste) in the first fight or two. The tomb's own walk (5-8
battles, estimate) brings the four about one level; anything beyond that
is a grind, and its target is set by the Dullahan lab (section 5), as the
Tentacles' L30 was.

**SETZER's join level** (`norm_lvl`, `field/event.asm` `EventCmd_77`): the
average level of the characters available, if higher than his own.
"Available" is `$1EDE`, the event switches `$02F0-$02FF` (characters 0-13
count); today it holds EDGAR, SABIN and CELES (`0x8070`: characters 4, 5,
6 and 15, which the loop skips). SETZER's own `$02F9=1` comes after
`norm_lvl` (`:85762`, `:85766`), so he joins at the trio's average: L31
at today's levels, **estimate** the trio's average when he is met. The
**Exp. Egg** (B3 (55,58), on the way to the wall switch) doubles one
member's experience.

### 4.2 Kit levers (to be measured)

- **Zombie** (the tomb): Revivify (4 in the bag; Kohlingen's item shop 67
  sells it at 300), the Amulet (Dark, Zombie, Poison; 5000 in South
  Figaro's relic shop 62, none in Kohlingen), the passage's **Ribbon**.
  The relic slots are spoken for (two Genji Gloves, CELES's and EDGAR's
  Jewel Rings, SABIN's Black Belt, EDGAR's Star Pendant), so each Amulet is
  a choice against one of those. Breaking a Zombie-caster before its turn
  (route-wor-edgar 8.2, the Bloompire) is the class answer.
- **Sour Mouth / Muddle / Sleep**: Remedy (5; Kohlingen sells it), the
  Ribbon, the Peace Ring (1 in the bag) for Muddle alone.
- **Fire and holy are everywhere in the tomb**: SABIN's Knuckles, Fire
  Dance and AuraBolt, MADUIN's and IFRIT's Fire, and UNICORN's Pearl
  (holy; `Unicorn: Pearl, Remedy`, `espers.txt`) on whoever carries it.
  EDGAR's **Bio Blaster heals four of the five** tomb species; the runner's
  absorb guard knows absorbs (route-wor-edgar 12.1).
- **Weapons in reach**: the Gold Lance (EDGAR, pierce 139, 12,000 GP,
  Kohlingen 65), the **Man Eater** (pierce 146; EDGAR, CELES or SETZER; the
  east-room chest), Darts (SETZER, pierce 115, 10,000) or Trump (SETZER,
  special 133, 13,000), the Soul Sabre in the bag (slash 125). `items.txt`.
- **Armor**: Kohlingen's 66 (Diamond Shld/Helm/Vest/Armor, Bard's Hat,
  Green Beret); the tomb's Genji Helmet and Crystal Mail (EDGAR, CELES,
  SETZER).
- **Espers**: MADUIN on CELES, IFRIT on SABIN, RAMUH on EDGAR; SETZER takes
  one of the ten spare stones. Read from `GenjuProp` (`espers.txt`):
  Shiva (Ice, Osmose, **Shell**), Bismark (**Haste, Slow**), Unicorn (Pearl,
  Remedy), Kirin (Cure, Regen), Sraphim (Cure, Life), Carbunkl (Rflect,
  Safe), Shoat (Break, Doom), Phantom (Vanish, Demi), Siren (Mute, Sleep),
  Stray (Muddle, Imp). No new Esper on the arc; Palidor is the first World
  of Ruin stone, on the Solitary Island once the Falcon flies.
- **Genji pairs** stay on CELES (Enhancer + ThunderBlade) and SABIN (Fire
  Knuckles). The ThunderBlade is bolt: the chest pair absorbs bolt
  (section 6), Dullahan does not.

### 4.3 Kit gaps (#319, milestone v0.25) where they bite

| character | planned (kits.md) | what this arc has | where it bites |
|---|---|---|---|
| SETZER | Slot ✦; Coin Toss, Hired Help (gil-priced); divine Jackpot | Slot only (vanilla); the Coin Toss *relic* in the bag turns Slot into GP Rain | his first arc: one verb; his ¤ weapons (Cards, Trump, Dice) key six of the arc's twelve species since the re-cut (section 8.7) |
| EDGAR | 8 Tools (AutoCrossbow, NoiseBlaster, Bio Blaster, Flash, Drill, Chain Saw, Debilitator, Overclock) | 3: AutoCrossbow, NoiseBlaster, Bio Blaster | Drill (pierce x2, "answers armored bosses") and Debilitator are in Figaro's World of Ruin shop 84, which refuses a party with EDGAR or SABIN (`_ca67c0`): both are in every party this arc fields; Chain Saw is a Zozo chest (after the Falcon); Overclock is not built. Dullahan is the armored boss Drill was planned for |
| CELES | RunicBlade (divine): Runic that also reflects | Runic | Dullahan is a caster boss: Runic takes his Ice 2, Ice 3, Pearl, N. Cross and his own Cure 2 (section 5) |
| SABIN | through Air Blade (L30) | Air Blade held; Spiraler L42 | — |
| all | #328 (Esper stat packages, growth) | the WoB stones' packages | — |

### 4.4 The supply band and the shops

`shops.txt`; South Figaro's 60, 61 and 63 as route-wor-edgar 4.3 decodes
them. No shop on the arc sells Tonics (4 in the bag): field care runs on
Potions, as on the last two stretches.

| shop | where | stock (GP) |
|---|---|---|
| 62 relic | South Figaro (leg 1, or one castle ride back) | Goggles 500, Star Pendant 500, Fairy Ring 1500, **Amulet 5000**, RunningShoes 7000, Wall Ring 6000, Cure Ring 8000, Czarina Ring 3000 |
| 63 item | South Figaro | Potion 300, Tincture 1500, Eyedrop 50, Echo Screen 120, Fenix Down 500, Revivify 300, Remedy 1000, Tent 1200 |
| 64 item, 84 tools | Figaro Castle | refuse a party with SABIN or EDGAR (`_ca67de`/`_ca67e2`) |
| 65 weapon | Kohlingen | Darts 10000, Dice 5000, Trump 13000, Enhancer 10000, Gold Lance 12000 |
| 66 armor | Kohlingen | Diamond Shld 3500, Bard's Hat 3000, Green Beret 3000, Diamond Helm 8000, Diamond Vest 12000, DiamondArmor 15000 |
| 67 item | Kohlingen | Potion 300, Tincture 1500, Antidote 50, Fenix Down 500, Revivify 300, Remedy 1000, Sleeping Bag 500, Tent 1200 |
| inn | Kohlingen 191 | 200 GP |

The band at L31-L33 (guidelines "Supply band"): Potions at level x 1.5
(47-50) before Dullahan on top of the field care (53 in the bag); Fenix
Downs about the level, capped near 20 (29); Remedy 5 against Sour Mouth
and Muddle, Revivify 4 against the tomb's Zombie: the two the tomb spends,
and Kohlingen is the last shop before it, so the top-up of both is sized
there from what the walk to it spent (**estimate**: about ten of each).
Tents (10) restore the whole party at a save point or on the world map
(supply.md): the tomb's save point is the pre-Dullahan stop. Gil is not
the limit (254,895): SETZER's whole kit, the Gold Lance and four Amulets
come to under 70,000.

---

## 5. Dullahan (the grave, event group 85)

Formation 455, Dullahan alone, met by the four (CELES, SABIN, EDGAR,
SETZER). A loss is a game over (`_ca5ea9`); the retry point is the save
point two rooms back (section 7).

- **L37, HP 23,450** (vanilla's; OT6's HP transform is 1x for every band,
  `Ot6HpMulTbl`), def 130, **mdef 160**, evade 10, **speed 55, starts Haste
  and Float**. Weak **fire**; **absorbs ice**. Immune Zombie, Poison, Imp,
  Petrify, Death, Condemned, Near Fatal, Mute, Berserk, Muddle, Sleep,
  Stop; **not Slow** (Bismark's Slow lands; UNVERIFIED live).
- **The script** (`ai_script.asm:5431`, `ai.txt`):
  - opens with **L? Pearl** (holy, power 120) once (`monster switch 0`);
  - **Cure 2** on itself below 10,240 HP, once per rotation (`monster
    switch 2`, cleared with switch 1 at the rotation's end);
  - every hit it takes adds 1 to `battle var 1` and counters with a Battle
    one time in three; above 8, the next turns run **N. Cross (Frozen) +
    Morn Star / Ice 2 + Morn Star / L? Pearl + Absolute 0 / Ice 2 +
    Absolute 0** (one pick of three a turn), and the counter resets;
  - if every member is Reflected, **Reflect???** (Dark, Mute, Slow), once
    per rotation;
  - otherwise a four-turn rotation of **Ice 3, Ice 2 and Pearl**, one pick
    of three a turn (some picks are nothing).
- **Attacks** (`boss_attacks.txt`): `L? Pearl: target $6E elem holy power
  120 runic no`; `Absolute 0: target $6B elem ice power 110 runic no`;
  `Ice 3: target $61 elem ice power 122 runic yes`; `Ice 2: ... power 62
  runic yes`; `Pearl: target $41 elem holy power 108 runic yes`; `N.
  Cross: ... elem ice power 0 runic yes status Frozen`; `Cure 2: ... runic
  yes`; Special Morn Star (x2 damage, physical).
- **L? Pearl** hits the members whose level the last digit of the party's
  gil divides (`AttackerEffect_1d`, `battle_main.asm:10842`; the check
  `@22ec`: `level / digit`, a miss on any remainder). The gil today ends in
  5 (`gil 254895`): L30 and L35 members are hit, L31-L34 are not. A digit
  of 1 hits everyone. A digit of 0 divides by zero; the SNES divider then
  returns the dividend as the remainder, so it should hit no one
  (**UNVERIFIED**). Gil moves with every battle's GP and with SETZER's
  GP Rain, so the digit at the grave is the draw's.
- **Runic is the fight's handle.** Five of its spells are runic (Ice 2,
  Ice 3, Pearl, N. Cross, its own Cure 2); CELES's Runic takes one, pays MP
  and +1 BP once a round, and a boosted Runic stands for 1-3 of her turns
  (kits.md). L? Pearl and Absolute 0 are not runic.
- **Elements**: fire is CELES's (MADUIN) and SABIN's (Knuckles, Fire Dance,
  IFRIT); ice heals him: the Blizzard, Shiva's Ice and CELES's own Ice stay
  out of hand (the runner's absorb guard refuses a weapon he absorbs).
  **Shell** (Shiva) halves Ice 2/3, Absolute 0 and both Pearls; **Haste**
  (CELES at L32, Bismark) and **Slow** on him (Bismark) are the tempo
  levers against speed 55 and Haste.
- **OT6**: unbroken, he takes about half damage; broken, he loses his
  turns and his counters (the boss contract). The hit counter lives in the
  counter block (`if_hit: attack NOTHING, NOTHING, BATTLE / add_battle_var
  1, 1`), which holds no story command, so a Broken Dullahan skips it whole
  and the hits landed in the break window do not feed the ice combo
  (read from the contract, **UNVERIFIED** live).
- **Lab candidate: yes.** An event battle lost to a game over, a level gap
  of six, a party-wide 110-power ice spell behind a hit counter, and a
  level-lore opener whose targets the gil decides. Measure the
  first-attempt rate over distinct battle keys from the save point, by
  level (the grind's target), with and without Shell and Haste, and with
  SETZER's Esper and weapon as the arms.

---

## 6. The monster chest (300 (120,9), event group 116)

The east room's left chest is a battle (`chest (120,9) bit $0A1 monster:
event battle group 116 (EventCmd_8e): formations [433, 433]`), closed at the
checkpoint. Formation 433 is the World of Ruin's Whelk: the **Presenter**
(the shell, `$101`, 9,230 HP, def/mdef 160/195, starts Float) and the
**Whelk Head** (`$135`, 9,845 HP). Both are weak fire and absorb ice, bolt
and water.

- **The shell answers every hit with Giga Volt** (bolt, power 110, runic:
  CELES's Runic takes it). Its turns: Magnitude8 (earth, 100; a floating
  member is not hit) while the head is hidden, else Battle, Mega Volt,
  Blow Fish.
- **The head** hides after three hits (`if_battle_var_greater 36, 2`) and
  comes back on a 20-count timer; its turns are Battle, Mega Volt, El
  Nino (water, 61, the party) and **PetriBlast** (Petrify: the Jewel Rings
  CELES and EDGAR wear, and the Softs, 18).
- The AutoCrossbow hits both bodies: each crossbow turn draws a Giga Volt.
  The ThunderBlade (bolt) heals both; the absorb guard refuses it.
- It pays no XP. It is optional, beside the save point, and a person
  would open it. **Lab candidate** if it is played: it is the same lesson
  as the Narshe Whelk (hit the head, not the shell) at L19/L31 with
  19,000 HP between them.

---

## 7. Save points and checkpoint cuts

One field save point (map 300 (122,14), `npc NPC_3 at (122, 14)
show-switch $0632 gfx SAVE_POINT`); the rest are world-map saves at the
natural pauses. Arcs after this one boot from these checkpoints and can run
in parallel (docs/TOOLING.md "Cuts and the chain from power-on").

| checkpoint | where | why |
|---|---|---|
| `wor-edgar-v1` (exists) | world (81,86), the Figaro desert | the start |
| **`wor-figaro-sweep-v1`** (optional) | world (81,86) again, after leg 1 | the side items and the desert (#321, #322) cut off the story chain, so the Kohlingen legs need not replay a long optional leg; drop it if leg 1 is dropped |
| **`wor-kohlingen-v1`** | world (40,45), east of Kohlingen's door (sealed; section 11) | the first save with SETZER, dressed, after Kohlingen's shops; the boot for the tomb |
| **`wor-tomb-v1`** | Darill's Tomb B3, the save point (122,14) | the last save before the monster chest and Dullahan: the retry point for both, and the World of Ruin's first save-point checkpoint |
| **`wor-falcon-v1`** | world (25,160), landed beside the Falcon | the end of the arc; the hub the World of Ruin arcs boot from |

Each cut asserts its preconditions in a contract in `lib/ot6_contract.lua`
(the party, the story switches the leg set, no live timer, the kit), as
`wor-edgar-v1` does. `wor-falcon-v1`'s contract carries the airship's cells
(`$1F62/$1F63`, `$1F64` bit 13; mechanics-coverage "Vehicles — airship")
and `$00CC $00CD $039B`.

---

## 8. Break data for the arc (authored)

Owner direction (guidelines "Design break data for the encounters players
meet"): every species the route meets gets an authored row designed from its
body, its vanilla elements and the party that meets it, so the party holds a
key and the area teaches something. The house curve: **1** pests, **2**
trash, **3** tanks, **4** miniboss-grade; bosses by bosses-wob's curve
(no WoB gauge above 11; "12 and above is reserved for the WoR"). Vanilla
element bits stay; no `Ot6ElemAddTbl` rows. Today's floor (4-6 shields)
puts every break here on a corpse, as it did on the Edgar stretch.

`design_keys.py` held the draft and checked it against the hands that meet
each formation (`design_keys.txt`). The owner approved it as written
(2026-10-01), and the twelve rows are one block in `Ot6ShieldTbl`
(`ff6/src/battle/ot6_hud.asm`, "the world of ruin: edgar to the falcon").
`tools/tests/battle_breakwor_falcon.lua` (`@suite`) reads them back from
the built ROM: each row, its vanilla weak byte and the absence of an
`Ot6ElemAddTbl` row; that every species of every formation of world groups
44-47, maps 298-300 and event groups 85 and 116 has an authored row and,
unless it draws no gauge (the Presenter), a key for the party that meets
it (the trio on the Kohlingen continent, the four in the tomb); that each
of the four holds a key on the Bogy (SETZER's Cards) and on Dullahan
(SETZER's Darts), who still absorbs ice; and that the Narshe Whelk's rows
are unchanged. (The suite as re-cut for ¤ is in section 8.7.) Evidence in `build/attempts/wt/falcon-breaks/rows/`
(`commands.txt` one level up): green on the authored ROM on px13 and on
the Air (`px13/`, `air/` `suite_battle_breakwor_falcon.log`: `checked 12
designed rows`, `checked 20 formations, 27 formation-species pairs`, `PASS
(frame 31) attempts=1/1`), red on main's ROM (`px13/suite.red.main-rom.log`:
`got 37 ($25), want 0`), red on a mutant ROM with a line per mutant
(`mutate.py`, eleven mutants; `px13/suite.mutant.log`: `got 23 ($17), want
0`). The ROM's rows equal the approved draft on every hand line of
`design_keys.py` (`px13/design_keys.compare.txt`: `hand lines 130, today
!= designed on 0`). `audit_break_coverage.py` no longer lists the twelve as
unauthored (`px13/audit.before.txt`, `px13/audit.after.txt`); the tuning
claim is unchanged and grows only by play.

### 8.1 Who holds what

| hand | classes | elements |
|---|---|---|
| CELES | slash (Enhancer, ThunderBlade; the Soul Sabre in the bag) | fire, ice, bolt (MADUIN), bolt (the blade) |
| SABIN | slash (claws), bludg (Pummel, Suplex) | fire (Knuckles, Fire Dance, IFRIT), holy (AuraBolt), wind (Air Blade) |
| EDGAR | slash (Break Blade) or pierce (Mithril Pike, Gold Lance, Man Eater); pierce on every body (AutoCrossbow) | bolt (RAMUH), poison (Bio Blaster) |
| SETZER (from Kohlingen) | special ¤ (Cards, Trump, Dice) or pierce (Darts) | his Esper's (Unicorn holy, Shiva ice) |

### 8.2 The Kohlingen continent (world groups 45-47)

| id | body | HP | weak | row |
|---|---|---|---|---|
| `$089` Harpiai | a winged woman, floating | 1418 | wind | **3 · slash, pierce** |
| `$0DB` Muus | a small shelled beast; nulls five elements | 900 | — | **2 · slash, bludg** |
| `$0A7` Deep Eye | a floating eye, in crowds of up to six | 1334 | fire | **2 · pierce, special ¤** |
| `$0D3` Bogy | a ghost behind Safe, no weakness | 1318 | — | **3 · slash, special ¤** |

- **Harpiai**: a flier (pierce, the WoB convention) and a blade for the
  slash-handed pair; vanilla wind is SABIN's Air Blade, the one wind key
  the party has. Its Aero (wind 125) is the plain's hardest hit.
- **Muus**: a Fight body (its nulls and its Pep Up counter turn spells
  away); the blade and the fist, not the point, so the AutoCrossbow does
  not sweep the Muus x3.
- **Deep Eye**: a point in the eye. Two shields so the AutoCrossbow's one
  chip a body cracks six of them in two sweeps: the crossbow's crowd.
  Vanilla fire is CELES's and SABIN's. A magic eye (its Dreamland sleeps
  whoever meets its gaze), so ¤ too (section 8.7).
- **Bogy**: no vanilla weakness, so the row is its only key: the blade for
  the trio (who meet it before Kohlingen) and **¤ for SETZER's cards**: a
  ghost. An owner decision.
- **Teaches:** *the crossbow sweeps the crowd* (Deep Eye x6) and *wind for
  the harpy*.

### 8.3 Darill's Tomb (groups 149-151)

| id | body | HP | weak | row |
|---|---|---|---|---|
| `$005` Orog | a zombie mass | 1584 | fire, holy | **3 · slash, bludg, special ¤** |
| `$010` Osteosaur | a skeleton | 1584 | fire, holy | **3 · bludg, special ¤** |
| `$06F` PowerDemon | a demon, the tomb's tank | 2058 | fire, holy | **3 · slash, pierce, special ¤** |
| `$061` Mad Oscar | a man-eating plant | 2900 | fire | **4 · slash** |
| `$091` Exoray | a spore plant behind Shell | 1200 | fire, holy | **2 · slash, pierce** |

- **Orog**: a body a blade or a blow opens; broken, it neither Zombies nor
  counters. Cursed flesh: ¤ (8.7).
- **Osteosaur**: bones are broken, not cut or stuck: SABIN's fists (the
  floor's pierce was the wrong class). EDGAR's key is the vanilla fire
  someone else holds; the Bio Blaster heals it. Risen bones: ¤ (8.7).
- **PowerDemon**: the tomb's tank, a blade or a point; it appears in all
  three basements. A demon: ¤ (8.7).
- **Mad Oscar**: the plant is cut; four shields (miniboss-grade, 2,900 HP)
  so the break lands before Sour Mouth's second turn.
- **Exoray**: trash at two; the AutoCrossbow sweeps the Exoray x3.
- **Teaches:** *the dead burn*: fire on all five and holy on four, Zombie
  on four, poison absorbed by four. Break the Zombie-caster before it acts;
  keep the Bio Blaster in the bag.

### 8.4 Dullahan (event group 85), in bosses-wob's style

Party: CELES, SABIN, EDGAR, SETZER. Formation 455.

**Shields:** 10 (8-12 the range considered) · **Weak:** fire (vanilla) +
piercing, bludgeoning, special ¤ · **Absorbs:** ice.

- **Keys:** an armored knight: the point through the joints, the blow on
  the plate, and ¤ for the headless spirit inside (the third key, 8.7).
  CELES holds fire (MADUIN), SABIN bludg and fire, EDGAR pierce (and the
  AutoCrossbow's one chip a turn), SETZER pierce with Darts or the Man
  Eater and ¤ with Cards, Trump or Dice (before the re-cut, `design_keys.txt`:
  `SETZER (Cards): today Dullahan:n | designed Dullahan:n`).
- **Telegraph (proposed):** Absolute 0. Vanilla's own fuse is the hit
  counter (nine hits, then the ice combo); the contract's one telegraph
  would make Absolute 0 a charged move a break cancels.
- **Break story:** CELES on Runic through the ice rotation (BP from his
  own spells), the rest chipping on fire, pierce and bludg; spend the break
  on the fuse; Shell on the party for L? Pearl and Absolute 0.
- **Jank ✦:** L? Pearl's gil digit stays as vanilla has it; the hit-counted
  combo stays.

### 8.5 The monster chest (event group 116)

| id | body | HP | row |
|---|---|---|---|
| `$101` Presenter | the shell | 9230 | **0** (no gauge: hitting the shell is the mistake) |
| `$135` Whelk Head | the head | 9845 | **6 · pierce** |

The Narshe Whelk's rows (`$0100` 0 shields, `$0134` 4 · pierce,
`ot6_hud.asm` `Ot6ShieldTbl`) grown for the World of Ruin, the way Ultros
keeps one row and grows its count. Formation 433 is also the 16/256 slot of
**World of Balance world group 13** (`pools.txt`: `slot 3: 16/256 word
$01B1 formation 433: Presenter $101 x1, Whelk Head $135 x1`), beside Red
Fangs and Mind Candies (L14-L15); these rows would change that encounter
too, if it were ever dealt. **It is not**
(`build/attempts/wt/falcon-breaks/wob433/where.txt`): group 13 fills only
terrain slot 3 of nine WoB sectors (`WorldBattleGroup indices (WoB) holding
group 13: [3, 7, 35, 39, 67, 99, 103, 131, 135]`); slot 3 is battle bg 5
(`BattleBGGroupTbl (bg -> terrain slot): [0, 1, 2, 1, 0, 3, 0, 0]`), the
World of Ruin's wasteland, and the WoB map has no battle tile with bg 5
(`world 0: battle-enabled tiles by bg: {0: 53912, 2: 889, 3: 1076, 6:
1238}`; `group 13 battle tiles by sector (x0,y0): {}`). The Veldt cannot
deal it either: a fought formation joins the Veldt's list only through a
monster below index 256 (`battle_main.asm` `@49e9`), and both of 433's are
above it. No World of Balance
party meets formation 433, so the rows change no WoB fight.

### 8.6 The check

`design_keys.txt` lists every formation of world groups 44-47, maps
298-300 and event groups 85 and 116 with the hands that meet it. Under the
draft every formation is keyed for the trio and for the four; SETZER alone
keys only the Bogy with Cards, and the Sand Horse, Harpiai, Deep Eye,
PowerDemon, Exoray, Dullahan and Whelk Head with Darts. Since the re-cut
(8.7) his Cards key the Bogy, the Deep Eye, the Orog, the Osteosaur, the
PowerDemon and Dullahan.

### 8.7 Special as a common key (re-cut, owner 2026-10-01)

Owner direction: "lean a little harder into making special a common
weakness, to encourage using characters that support special weapons"
(guidelines, "Special (¤) is a common key"). Before the re-cut only the
Bogy took ¤ here. Six of the twelve species now do, chosen by body:
spirits, magical things and cursed things take ¤ beside their keys; the
plants, the beasts, the harpy and the chest pair do not. Every row keeps
its shield count and its existing classes, so nothing the trio relied on
moved.

| id | body | row before | row now | why ¤ |
|---|---|---|---|---|
| `$0D3` Bogy | a ghost | 3 · slash, ¤ | unchanged | a spirit (the row it had) |
| `$0A7` Deep Eye | a floating eye whose Dreamland sleeps | 2 · pierce | **2 · pierce, ¤** | a magic eye |
| `$005` Orog | a zombie mass | 3 · slash, bludg | **3 · slash, bludg, ¤** | cursed flesh |
| `$010` Osteosaur | a skeleton | 3 · bludg | **3 · bludg, ¤** | risen bones |
| `$06F` PowerDemon | a demon | 3 · slash, pierce | **3 · slash, pierce, ¤** | a demon |
| `$11C` Dullahan | a headless knight | 10 · pierce, bludg | **10 · pierce, bludg, ¤** | the headless spirit in the armor (its third key) |

Left without ¤: the Harpiai (a harpy, a flier), the Muus (a shelled
beast), the Mad Oscar and the Exoray (plants), the Presenter (no gauge)
and the Whelk Head (a shellfish).

**What it changes.** By formation (`design_keys.py`, the re-cut's copy:
`build/attempts/wt/special-weak/design_keys.py`; `px13/design_keys.recut.txt`
and `px13/design_keys.main-rom.txt` under the same directory): SETZER with
Cards held a key on every body of 1 of the arc's 20 formations and on none
of 19 (`SETZER (Cards): every body 1, some body 0, none 19`, main's ROM);
now on every body of 7, some of 3, none of 10 (`SETZER (Cards): every body
7, some body 3, none 10`). In the tomb his cards key every body of the
Osteosaur, Orog and PowerDemon formations and the PowerDemon of 248, and
none of the plants' (249, 250, 251), so the plants stay pierce, slash and
fire. Darts are unchanged (`SETZER (Darts): every body 8, some body 5, none
7`). The trio and the four are keyed on every formation, as before (`CELES
+ SABIN + EDGAR: every body 10, some body 0, none 0`; `the four: every body
20, some body 0, none 0`), and the ROM's rows equal the re-cut on every
hand line (`px13/design_keys.compare.txt`: `hand lines 130, today !=
designed on 0`).

**A ripple into the Kohlingen leg.** `gen_wor_kohlingen` dresses SETZER
with the weapon whose class keys the most of its ten arc species, then by
power (section 11.1). Read statically from the re-cut ROM with the same rule
(`build/attempts/wt/special-weak/setzer_weapon.py`,
`px13/setzer_weapon.txt`): `$50 Trump: class special, power 133, price
13000; keys 6 of 10 ... score 6133` against `$4E Darts: class pierce, power
115, price 10000; keys 5 of 10 ... score 5115`, and the bag's Cards score
6104. On main's ROM the Darts led (`$50 Trump ... keys 1 of 10 (Bogy);
score 1133`). So a regenerated wor-kohlingen chain should dress SETZER
with the Trump where the purse allows it (a reading of the rule, not a
run; the cut checkpoint `wor-kohlingen-v1` keeps its Darts until it is
re-cut).

**The check.** `battle_breakwor_falcon.lua` carries the re-cut rows in
WANT and checks that SETZER's Cards hold a key on each of the six and on
Dullahan, with the Bogy and Dullahan checks of 8.6 kept. Evidence in
`build/attempts/wt/special-weak/px13/` (`commands.txt` one level up):
green on the re-cut ROM (`suite_battle_breakwor_falcon.log`: `special:
SETZER (Cards) holds a key on 6 of 12 designed species`, `Dullahan: SETZER
(Cards) holds a key`, `PASS (frame 31) attempts=1/1`), red on main's ROM
with the suite copied in (`suite.red.main-rom.log`: `special: SETZER
(Cards) holds a key on 1 of 12 designed species`, `got 11 ($B), want 0`).
`shield_rows`, `break_coverage_ratchet`, `break_reach`, `boss_rows` and the
other break suites pass on the re-cut ROM (`ninja_checks.log`).

---

## 9. Risks and unknowns

| mechanic | where | coverage today | what the driving needs |
|---|---|---|---|
| Dullahan: an event battle whose loss is a game over | the grave | the runner retries a lost segment from its boot | the lab (section 5): level target, Shell/Haste/Slow, SETZER's arms |
| Zombie on several members, in battle | the tomb (four species) | field cure HANDLED (#190); the battle raise refuses a Fenix Down on a zombie (#245); **the battle cure HANDLED (#263, 12.3)** | measured (12.3): members Zombied at a battle's end 12 -> 3 over 102 tomb battles; the Amulets and the Ribbon remain levers |
| Sour Mouth (six statuses) | Mad Oscar, B2/B3 | Muddle HANDLED (route-wor-edgar 12.4); Sleep "planned around / not measured live" | Remedy in battle; the Ribbon |
| L? Pearl and the gil digit | Dullahan | not read by the driver | read `$1860-$1862` at the grave; the digit is a lever a person can move (selling an odd-priced item) |
| Frozen (N. Cross) | Dullahan | planned around / not measured live | — |
| a chest that opens a battle (`EventCmd_8e`) | 300 (120,9) | not in mechanics-coverage | open it after the save; the runner's battle handling |
| the Whelk pattern: a shell that counters, a head that hides | the chest | the Narshe Whelk's driver | the kill order (head only) |
| face-and-hold-A switches and turtle rides, three directions | the tomb | HANDLED (`H.faceAndHoldA`, up at the Figaro turtle) | down (56,14) and right (71,9) are new directions for it |
| the castle's ride (a dialog choice and a scripted move) | leg 2 | the Edgar arc's surfacing is the same scene family | choice 0 at "(Go to Kohlingen?)" |
| **flying and landing the Falcon** | the end | "PARTIAL — contract assertions only" | a land verb (A over land) and a contract; a suite for the new mechanic |
| a scripted cutscene with walking in the middle | 301 (the flashback) | none needed beyond talks and a step-on trigger | talk, step, talk |
| a party member joining undressed | SETZER | `M.equipKit` and the world menu helpers (#255) | dress him from the bag and Kohlingen's shops |
| the desert's Sand Horse pair | group 44, both castle tiles | the driver heal-locks (#312); lost 2 of 8 with two members | a lab: formation 222 with the trio |
| map-init `mod_bg_tiles` and turtles | the tomb, 297's stairs, 66, 89 | the lib reads live RAM | offline counts are verify-on-arrival |
| the draw | everywhere | save data (`$1FA1-$1FA5`) | vary it by using up encounters (varlab), not by seeds |

Out of scope, noted: the World of Ruin Colosseum is on foot from Kohlingen
(v0.35); Mobliz (v0.27) is on the Tzen continent; the castle's stratum
(`$00CD`) and Palidor (`$039B`) open with the Falcon.

---

## 10. The South Figaro continent, played (leg 1, `gen_wor_figaro_sweep`, `wor-figaro-sweep-v1`)

Not yet driven.

## 11. The castle's ride, Kohlingen and SETZER, played (legs 2-4, `gen_wor_kohlingen`, `wor-kohlingen-v1`)

Driven 2026-10-01 for #263 (and #322's Regal Crown). The segment
Continues `wor-edgar-v1` (`H.bootCheckpoint`), takes the Regal Crown off
the castle's basements, rides the castle to Kohlingen, walks into town,
opens its two chests, rests at the inn, takes SETZER, dresses him from the
bag and the town's shops, and saves east of the town's door through
`H.saveAtCheckpoint`: the `wor-kohlingen-v1` checkpoint. Every number
below is quoted from a log under `build/attempts/wt/wor-kohlingen/`
(`capture/` the sealing run, `var2/` the shipped generator's variation set,
`var1/` the same set one commit earlier, before SETZER's row step, `dev/`
the failed runs that found the route). All on ROM `4411dfd2fea7` (main
`720ebdea`, the Falcon arc's authored break rows) except `dev/run1-8`,
which ran on the ROM before them. Nothing was measured by writing game
state.

### 11.1 The run (`capture/capture_wor-kohlingen-v1.log`)

| step | what the log says |
|---|---|
| boot | `contract wor-edgar-v1 (entry): all 26 fields hold`; `[wor] boot f1019: world 1 (81,86), CELES L31 HP 1300/1595 ...; SABIN L31 HP 1384/1609 MP 75/291 ...; EDGAR L31 HP 948/1600 ...` (the care's policy leaves 948/1600: `[care at the boot] nothing to do`) |
| the Regal Crown | `[route] basement 3 -> basement 2's west pocket: on map 62 at (3,12)`, `[chest] chest bit 154 (Regal Crown): OPENED`; `[kit] the Regal Crown on EDGAR: def+mdef 51 over his $76's 37 (gain 14)`, `on SABIN: ... over his $77's 34 (gain 17)`, `goes to SABIN` |
| the engineer | `[choice] dlg $03D4: row 0 of 2`; `[castle] f13098 the castle has sailed for Kohlingen` (`$00DC=1`, `$0106=0` asserted) |
| the walk | `[wor] out of Figaro Castle by Kohlingen f13651: world 1 (53,58)`; `wnav: planned 28 steps from (53,58)`; one battle, `battle $0EF WON after 2231 ticks` (Bogy x2) |
| Kohlingen | the chests: `chest bit 65 (Green Beret): OPENED`, `chest bit 69 (Elixir): OPENED`; the inn (200 GP): `before the night: c4 1215/1600 hp ... c5 1192/1609 hp 75/291 mp` -> `after the night: ... gil=266477` |
| SETZER | `[kohlingen] f25142 SETZER joined, kit FF FF FF FF FF FF FF ... SETZER L31 HP 1597/1597 MP 297/297` (`norm_lvl`: the trio's average, as section 4.1 read it) |
| dressed | `[kit] SETZER's kit: slot 0 $4E, slot 1 $5F, slot 2 $7C, slot 3 $95, slot 4 $B1, slot 5 $B5 (weapon $4E keys 5 of the arc's 10 species, power 115)` (Darts, Diamond Shld, Diamond Helm, DiamondArmor, Star Pendant, Jewel Ring); `[UNICORN -> SETZER] verified`; `[SETZER to the back row] done: c4=back c5=back c6=back c9=back` |
| the counter | `bought: tonic=4 potion=54 fenix=32 remedy=10 soft=18 revivify=10 greencherry=5 gil=220177 (spent 9800 GP)` |
| the save | `[saved] wor-kohlingen-v1: slot 3 holds map 1 ($2001) world tile (40,45)`; `contract wor-kohlingen-v1 (exit): all 31 fields hold`; `[wor] the battles: 3 ($0E8 x1, $0E9 x1, $0EF x1): 3 won, 0 the party left, 0 monster escape(s)`; `PASS (frame 29880) attempts=1/3` |

Sealed and validated (`capture/validate_wor-kohlingen-v1.txt`): `valid
ot6.sram-checkpoint/v1: 32768 bytes sha256=51460c39... holds=slot 3 world 1
(40,45) [$1F64=$2001] (saved: declared and checked)`. The graph's own edge
(`nice ninja build/states/wor_kohlingen.mss`, `capture/ninja_wor_kohlingen.log`)
plays the same run: `PASS (frame 29880) attempts=1/3`. The cold Continue
(`capture/probe_kohlingen_continue.lua`, `capture/continue_kohlingen.log`):
`contract wor-kohlingen-v1 (entry): all 31 fields hold`, `[continue] world
1 at (40,45): CELES L32 HP 1696/1696 ...; SABIN L31 ... 01 57 57 7B 90 D1 D5;
EDGAR L31 ...; SETZER L31 HP 1597/1597 MP 297/297 esper+kit 17 4E 5F 7C 95
B1 B5; gil=220177`. The same probe on `wor-edgar-v1` is the contract's
negative: `contract wor-kohlingen-v1 (entry) VIOLATED -- 10 field(s) differ`
(the tile, `$00DC`, `$0106`, `$00CA`, `$02F9`, `$067F`, the crown's
treasure bit, the party's size and SETZER;
`capture/negative_contract_on_wor-edgar-v1.log`).

**Spend.** SETZER's kit cost 36,500 GP (Darts 10,000, Diamond Shld 3,500,
Diamond Helm 8,000, DiamondArmor 15,000: `gil 266477 -> 256477`, `-> 252977`,
`-> 244977`, `-> 229977`), the counter 9,800, the inn 200; the purse went
254,895 -> 220,177 with the battles' gold. The rule (`dressSetzer` in the
generator): each slot takes the bag's best piece he can wear, and the
counter's best is bought only when it beats the bag's and costs no more
than a tenth of the purse at the counter. The weapon is ranked by how many
of the arc's ten species its class keys, read from the ROM's shield rows,
then by power: on this ROM the Darts (pierce) key 5, the Dice and Trump (¤)
key 1 each, the Bogy (the score is keys x 1000 + power: `$51 scores 1001 against the bag's best 5030`, `$50
scores 1133`, `$4E scores 5115`); on the ROM before the authored rows the
same rule bought the Darts keying 1 (`dev/run5.log`: `keys 1 of the arc's
10 species`). The Green Beret from the chest lost the helmet slot to the
Diamond Helm (45 against 32); it is in the bag.

What the plan did not know:

- **The court's gate (28,38) reads impassable from below** to the walker's
  map model; it is crossed the lib's way (`H.crossDoor`: staged below,
  the direction held). `dev/run1.log`: `no path (28,42)->(28,38)`;
  `dev/probe_castle.log`.
- **The Regal Crown's door 62 (4,6) is in a pocket of basement 2 that only
  basement 3 reaches.** From the arrival (12,13) there is no path once
  map 62's other doors are kept off the plan (`dev/run2.log`: `no path
  (12,13)->(4,7)`); the offline region graph had walked through door tiles.
  The way: 62 (14,8) -> 63 (54,6), the link (56,15) -> (87,7), the stairs
  (81,5) -> (44,14), (47,8) -> 62 (3,12), (4,6) -> 66; back by the pocket's
  (2,13) -> 63 (46,9), the stairs (44,15) -> (81,7), and gen_wor_edgar's
  way to basement 1 ((87,5), (53,5) -> 62 (13,7), (13,12) -> 61). It costs
  basements 2 and 3's fights (groups 137, 138): in the set below, 45 of the
  60 body battles (map 63 26, map 62 19; the world walk 15).
- **The castle comes up with its exit at (53,58)**, the trigger's own row
  (the ride's 28 diagonal steps from (81,85) put the castle at (53,57)).
- **Kohlingen's exit returns the party to the tile it stepped in from**
  ((40,45) from the castle's side, `dev/run8.log`: `standing on ... (40,45)`),
  not the edge's (38,46); the save is made on a fixed tile, (40,45), walked
  to with the town's entrances kept off the plan.
- **The field reads stale map data for a moment after the menu closes**
  (`dev/run6.log`'s grid: nothing reachable from where the party stood);
  the walk out of the store waits for control first.

### 11.2 Under real draw variation (`var2/`)

`varlab.py` (after the Edgar arc's) derives the generator with a block
after the boot that fights K encounters on the South Figaro continent
(gen_wor_edgar's grind loop, only the doors kept off the plan: no path off
the castle tile avoids the desert, so its fights count among the K) and
walks back to (81,86); K is a floor. Retries off (`OT6_RETRIES=1`);
`keys.py` pairs each battle's `[key]` line (the seed `$be` at InitBattle's
store and the battle group) with its `[outcome]`. `var2/summary.txt`,
`var2/keys.txt`:

| variant | the body starts at (`$1FA1-5`) | body battles (key/formation) | lowest member HP (body) | verdict |
|---|---|---|---|---|
| K=0, shift 0 | the checkpoint | `be6C/$0E8`, `be0C/$0E9`, `be80/$0EF` | 584 | `PASS (frame 29880) attempts=1/1` |
| K=0, shift 23 | the checkpoint | `beC0/$0E8`, `be60/$0E9`, `be44/$0EF` | 682 | `PASS (frame 28614)` |
| K=0, shift 41 | the checkpoint | `be18/$0E8`, `be88/$0E9`, `beF0/$0EF` | 818 | `PASS (frame 30373)` |
| K=1 | `8C 5E 5D 5D 5D` | `beB0/$0E7`, `beB8/$0E8`, `be74/$0E5` | 337 | `PASS (frame 36279)` |
| K=2 | `BE 5F 5D 5D 5D` | `beE8/$0E4`, `be88/$0E5`, `be40/$0E8`, `be98/$0EF` | 948 | `PASS (frame 37713)` |
| K=3, shifts 0 / 23 / 41 | `E0 60 5D 5D 5D` | `$0E5` x2, `$0E8`, `$0F1` each (`beB8 beB0 be28 be94` / `beBC beB8 be04 be8C` / `beD4 be60 beB4 beE8`) | 971 / 812 / 647 | `PASS (frame 43376)` / `(42801)` / `(42749)` |
| K=4 | `FE 61 5D 5D 5D` | `be60/$0E5`, `beE4/$0E8`, `be40/$0E5`, `beB8/$0F1` | 1206 | `PASS (frame 44262)` |
| K=5 (6 fought) | `30 63 5D 6E 5D` | `be30/$0E5`, `be2C/$0E8`, `beB0/$0E9` | 1410 | `PASS (frame 44894)` |
| K=6, shifts 0 / 23 / 41 | `36 63 5D 6E 5D` | `$0E5`, `$0E8`, `$0E9` each (`be54 be94 be74` / `be9C be74 be9C` / `be98 beA4 beC8`) | 980 / 968 / 910 | `PASS (frame 48480)` / `(48671)` / `(49032)` |
| K=7 (8 fought) | `52 65 5D 6E 5D` | `be88/$0E9` | 1256 | `PASS (frame 46494)` |
| K=8 | `64 65 5D 6E 5D` | `beE4/$0E7`, `beAC/$0F3` | 798 | `PASS (frame 50246)` |
| K=9, shifts 0 / 23 / 41 (10 fought) | `9E 67 5D 6E 5D` | `$0E9`, `$0EF` each (`be24 beA0` / `beCC be98` / `beE8 be14`) | 1592 / 1141 / 1526 | `PASS (frame 55277)` / `(57701)` / `(55092)` |
| K=10 | `A2 67 5D 6E 5D` | `beE4/$0E9`, `be94/$0EF` | 957 | `PASS (frame 56032)` |
| K=11 (12 fought) | `E8 69 5D 6E 5D` | `beE0/$0E5`, `beF0/$0EC` | 1136 | `PASS (frame 62337)` |
| K=12 | `02 69 5D 7F 5D` | `be8C/$0E5`, `be7C/$0E9`, `be70/$0EF` | 1269 | `PASS (frame 64871)` |

**21 of 21 `PASS attempts=1/1`**, each `contract wor-kohlingen-v1 (exit):
all 31 fields hold` on `[saved] ... world tile (40,45)`; 180 `[outcome]`
lines, 180 `paid as due`, 0 without an end reading. **The body fought 60
battles over 56 distinct battle keys, all won, no death**: formation 229
(Cruller, Humpty x2) 16 battles / 14 keys, 232 (NeckHunter, Cruller, Humpty
x2) 13 / 13, 233 (Dante) 13 / 12, 239 (Bogy x2) 9 / 8, 241 (Deep Eye x2,
Muus x2) 4 / 4, 231 2 / 2, 228, 236 and 243 one each; by place, map 63 25
keys, map 62 17, the world 14. Four keys repeat across runs (`be60-g00E5`
K=3 s41 and K=4; `be88-g00E9` K=0 s41 and K=7; `be98-g00EF` K=2 and K=9 s23;
`beB8-g00E5` K=3 s0 and s23). No Fenix Down was spent (`fenix=29` on every
run's arrival in town, `fenix=32` after the counter). The lowest member HP on the
body's battle lines is 337 (K=1). Frames 28,614-64,871 from the Continue,
the body ~29k of them.

**The desert did not come up in the body**: the walk crosses five desert
tiles at the castle's door and none of the 21 bodies rolled a fight there.
It came up in the prefixes (the castle tile's desert on the way out to the
grass and back): formation 222 (the Sand Horse pair, #312) once (K=5:
`battle $0DE WON after 1663 ticks`), 223 eight times over four keys, 138
once, all won by the trio. So #312 did not block this leg; one draw of 222
with three members is not a measurement of it.

`var1/` is the same set one commit earlier (no row step for SETZER): the
same 21 PASS and the same 60 body battles key for key (`var1/keys.txt`),
since the step comes after the last fight.

### 11.3 Re-cut on the special-weak ROM (`build/attempts/wt/wor-tomb/kohlingen-recut/`)

The special-weak rows (main `942cf222`: Deep Eye, Orog, Osteosaur,
PowerDemon and Dullahan also take ¤) changed this leg's play, so the
checkpoint was re-cut from the generator on ROM `86018dd9ac20`, with two
review follow-ups: the Fenix Down purchase is capped at the band (about
20; `FENIX_CAP`), and the contract pins SABIN's Regal Crown (`$16DA =
$7B`) and SETZER's UNICORN (`$176B = $17`). The capture
(`capture_wor-kohlingen-v1.log`): `[kit] SETZER's weapon: shop 65's $50
scores 6133 against the bag's best 6104` (the Trump over the bag's Cards;
the Darts score 5115), `SETZER's kit: slot 0 $50, ... (weapon $50 keys 6
of the arc's 10 species, power 133)`, `FENIX DOWN to the level, capped at
the band: ... already there (0 wanted)`, `bought: tonic=4 potion=54
fenix=29 remedy=10 soft=18 revivify=10 greencherry=5 gil=218677 (spent
8300 GP)`, `contract wor-kohlingen-v1 (exit): all 33 fields hold`, `PASS
(frame 29814) attempts=1/3`; sealed `sha256=577024055a54...`
(`../capture/validate_wor-kohlingen-v1.txt`). The two new pins each fail
alone on a copy of the battery with that byte changed
(`../review/neg/`): `ram $16DA & $FF (SABIN wears the Regal Crown ...):
expected 0x7B, read 0x76` and `ram $176B & $FF (SETZER holds UNICORN
(esper 23)): expected 0x17, read 0xFF`, each `VIOLATED -- 1 field(s)
differ`.

Under draw variation (`var/`, the leg's own `varlab.py`, retries off):
**11 of 11 `PASS attempts=1/1`** (K = 0, 2, 4, 6, 8, 10, 12 at shift 0;
K = 0 and 6 at shifts 23 and 41), each `contract wor-kohlingen-v1 (exit):
all 33 fields hold`, 33 of 33 `[outcome]` lines `paid as due`, no death
in a body (`var/summary.txt`); the bodies fought **33 battles over 33
distinct battle keys**, all won (`var/keys.txt`: formations 229 x7, 232
x8, 233 x8, 239 x6, 228, 231, 241, 243 one each); the lowest member HP on
a body's battle lines was 584.

## 12. Darill's Tomb to its save point, played (legs 5-8, `gen_wor_tomb`, `wor-tomb-v1`)

Driven 2026-10-01 for #263. The segment Continues `wor-kohlingen-v1`
(`H.bootCheckpoint`), walks to the tomb, opens its door with SETZER, works
the switches and the turtles down through B1-B3, opens the chests on the
way (all but the monster chest), and saves on the save point in B3's east
room through `H.saveAtCheckpoint`: the `wor-tomb-v1` checkpoint. Every
number below is quoted from a log under `build/attempts/wt/wor-tomb/`
(`capture/` the sealing run, the cold Continue and the negative; `var1/`
the variation set; `var0/` the same set with the in-battle Zombie cure
off; `zombie/` the cure's lab and suite; `dev/` and `pilot1/` the runs that
found the route; `plan/` the offline pockets). All on ROM `86018dd9ac20`
(main `942cf222`, the special-weak rows) except `dev/run1-3`, which ran on
`4411dfd2fea7`. Nothing was measured by writing game state.

### 12.1 The run (`capture/capture_wor-tomb-v1.log`)

| step | what the log says |
|---|---|
| boot | `contract wor-kohlingen-v1 (entry): all 33 fields hold`; `[wor] SETZER's Esper byte $17`; the leg asserts its own needs: Revivify and Remedy in the bag |
| the walk | `[key] battle key beE4-g00EF f1199 map 1`, `be78-g00EF`: two Bogy pairs, both won |
| the door | `[tomb] f6091 the door opened map 297 (8,10)` (`$00CB`); `the stairs (7,8) -> B1: on map 298 at (13,12)` |
| B2's switch, the water | `the switch (28,43): $02B1`; `the opened way (28,38) -> B3 (61,44)`; `the water switch (61,33): $02B3` |
| chests | `chest bit 156 (Genji Helmet): OPENED`, `157 (Crystal Mail)`, `158 (Czarina Gown)`, `159 (Exp. Egg)`, `160 (Man Eater)`; `[kit] the Genji Helmet ($81) goes to EDGAR` (gain 37 over SETZER 29, CELES 26, SABIN 23), `the Crystal Mail ($98) goes to EDGAR` (gain 46) |
| the wall switch | `the wall switch (76,10): $02B8` |
| the turtles | `[tomb] f27801 down on the turtle map 300 (69,8)`; `the turtle switch (70,8): $02B5`; `f28382 across on the turtle map 300 (79,5)` |
| the save | `[on the save point] plan: heal ... with $E9` x5; `[saved] wor-tomb-v1: slot 3 holds map 300 ($012C) tile (122,14)`; `contract wor-tomb-v1 (exit): all 30 fields hold`; `[wor] the battles: 7 ($0EF x2, $0FA x1, $0F8 x3, $0F9 x1): 7 won`; `PASS (frame 32905) attempts=1/3` |

Sealed and validated (`capture/validate_wor-tomb-v1.txt`): `valid
ot6.sram-checkpoint/v1: 32768 bytes sha256=468ec180c10c... holds=slot 3
map 300 (122,14) [$1F64=$012C] (saved: declared and checked)`. The cold
Continue (`capture/continue_tomb.log`, `probe_tomb_continue.lua`):
`contract wor-tomb-v1 (entry): all 30 fields hold`, `[continue] map 300 at
(122,14): CELES L32 HP 1696/1696 ...; SABIN L32 ...; EDGAR L31 ... esper+kit
00 11 5C 81 98 B5 B1; SETZER L31 ... esper+kit 17 50 5F 7C 95 B1 B5;
gil=242571; revivify=20 remedy=10 potion=47 fenix=29 tent=10`. The same
probe on `wor-kohlingen-v1` is the contract's negative: `contract
wor-tomb-v1 (entry) VIOLATED -- 8 field(s) differ` (the map and tile,
`$00CB`, `$02B1`, `$02B3`, `$02B8`, `$02B6`;
`capture/negative_contract_on_wor-kohlingen-v1.log`). The graph's own edge
plays the same run (`capture/ninja_wor_tomb_generate.log`: `PASS (frame
32905) attempts=1/3`).

The contract pins the party, the door and the switches the route sets,
`$02B2=0` (Dullahan not fought), the monster chest closed (treasure bit
`$0A1`), no timer, and the codex; a later leg that needs a level or an
item asserts it itself. The two pins for the next leg each fail alone on a
copy of the battery with that one bit set (the slot checksum and sha256
recomputed; `review/make_neg.py`, `review/neg/`): `ram $1E54 & $02 (the
monster chest (120,9) is closed (treasure bit $0A1)): expected 0x00, read
0x02` and `switch $02B2 (Dullahan not yet fought (_ca42f1)): expected 0,
read 1`, each `VIOLATED -- 1 field(s) differ`.

What the plan did not know (every **verify-on-arrival** in 2.6 held
otherwise; the order of 2.6 is the order walked):

- **The field's map reads stale for a while after a menu closes.**
  `dev/run2.log` (the field care's menu, then the save point) failed with
  `navTo: no path (124,10)->(122,15)`: the save point (122,14) is walled
  above and below (`plan/grid_save_point.txt`: `122,13:#`, `122,15:#`,
  `121,14:RL`), and right after the menu closed the BFS reached nothing --
  measured from (124,10), every tile `n` for 39 frames with `ctl=true
  algn=true`, then (122,14) and (121,14) `y` (`review/probe_savepoint.log`).
  `H.stepOntoSavePoint` now waits for the map to reach the tile or a side
  before it chooses (`review/probe_savepoint_now.log`: `waitUntil 'the
  field's map reaches the save point (122,14) or a side' satisfied after 39
  frames`, then `[probe] on (122,14)`, `PASS`); the same probe on the
  lib of `d3eaeb7c` fails as run2 did (`review/probe_savepoint_now_on_
  d3eaeb7c.log`: `approached from (122,15), pressing up`, `FAIL: navTo: no
  path (124,10)->(122,15)`). Its other change, approaching from a
  reachable side when the tile itself reads blocked, has not run: no
  measured case had the tile blocked with a side open. Another
  generator's field save point under the new step: `gen_kolts` (57,8),
  `waitUntil ... satisfied after 0 frames`, `contract kolts-summit-v1
  (exit): all 12 fields hold`, `PASS (frame 91741)`
  (`review/review2/gen_kolts.log`).
- **Each room of maps 299 and 300 is its own pocket**, joined by same-map
  doors (`plan/nolinks.txt`), so the walk is a chain of door crossings
  rather than one path; B2's hub (37,12) holds five of them.
- **B3's turtle switch reads `$02B5=0` on arrival**; one press moves the
  turtle (`_ca41e0`), and the ride from (71,9) facing right lands at
  (79,5), below the opened (79,3).
- **The tomb pays its Revivifies back**: the bag went from 10 at the boot
  to 13-22 at the save across the set below (the drops).

### 12.2 Under real draw variation (`var1/`)

`varlab.py` derives the generator with a block after the boot that fights
K encounters on the Kohlingen continent (four waypoints in groups 45-47,
Kohlingen's doors, the castle's tiles and the tomb's door kept off the
plan) and walks back to (40,45); retries off. `analyze.py` pairs each
`[key]` with its `[outcome]` (`var1/summary.txt`, `var1/analysis.txt`):

| variant | the body starts at (`$1FA1-5`) | battles after the boot | verdict |
|---|---|---|---|
| K=0, shifts 0 / 23 / 41 | the checkpoint | 7 (`$0EF x2, $0FA x1, $0F8 x3, $0F9 x1`) | `PASS (frame 32905)` / `(38256)` / `(34361)` |
| K=1 | `7C 6C 6B 6B 6B` | 6 (`$0EF x1, $0FA x3, $0F8 x2`) | `PASS (frame 29051)` |
| K=2 | `96 6D 6B 6B 6B` | 6 (`$0F6 x1, $0F8 x2, $0FA x2, $0FB x1`) | `PASS (frame 30510)` |
| K=3, shifts 0 / 23 / 41 | `C6 6E 6B 6B 6B` | 7 (`$0F2 x1, $0F8 x1, $0F9 x1, $0FA x1, $0FB x3`) | `PASS (frame 37278)` / `(38198)` / `(37208)` |
| K=4 | `E2 6F 6B 6B 6B` | 6 (`$0EF x1, $0F9 x1, $0FA x1, $0F7 x2, $0FB x1`) | `PASS (frame 34140)` |
| K=5 | `FE 70 6B 6B 6B` | 7 (`$0F0 x1, $0FA x1, $0FB x4, $0F7 x1`) | `PASS (frame 35726)` |
| K=6, shifts 0 / 23 / 41 | `1A 71 6B 7C 6B` | 6 (`$0F1 x1, $0F7 x2, $0FB x3`) | `PASS (frame 38595)` / `(38631)` / `(37319)` |
| K=7 | `42 72 6B 7C 6B` | 6 (`$0EF x1, $0F7 x3, $0FB x1, $0FA x1`) | `PASS (frame 41014)` |
| K=8 | `60 73 6B 7C 6B` | 6 (`$0EE x1, $0F7 x2, $0FB x2, $0F9 x1`) | `PASS (frame 45238)` |
| K=9 | `76 74 6B 7C 6B` | 6 (`$0F6 x1, $0F7 x2, $0FA x1, $0FB x1, $0F8 x1`) | `PASS (frame 44026)` |
| K=10 | `AA 75 6B 7C 6B` | 6 (`$0EC x1, $0F6 x1, $0F9 x1, $0FB x1, $0F8 x1, $0F7 x1`) | `PASS (frame 49305)` |
| K=11 | `BC 76 6B 7C 6B` | 6 (`$0EE x1, $0FA x1, $0F7 x1, $0F8 x1, $0FB x2`) | `PASS (frame 51782)` |
| K=12 | `DE 77 6B 7C 6B` | 6 (`$0F9 x1, $0F7 x2, $0FA x1, $0FB x2`) | `PASS (frame 50854)` |

**19 of 19 `PASS attempts=1/1`**, each `contract wor-tomb-v1 (exit): all
30 fields hold`. **The bodies fought 121 battles over 102 distinct battle
keys, all won** (`body: 121 battles over 102 distinct battle keys
(seed+group+formation); outcomes {'WON': 121}`): in the tomb formation 251
(Mad Oscar) 33 battles / 28 keys, 247 (PowerDemon) 20 / 16, 248
(PowerDemon, Exoray x2) 19 / 16, 250 (Mad Oscar, Exoray) 17 / 14, 249
(Exoray x3) 10 / 9, 246 (Osteosaur) 3 / 3; on the world 239 (Bogy x2) 9 /
7 and five others; by place map 300 48 keys, 299 35, 298 3, the world 16.
Eighteen keys repeat across runs (mostly the shifts at one K). **The Orog
(formations 244, 245) never came up**: B1 is 12 steps (3.4: P(0) 0.958),
and its three battles were all 246. The party reached the save point at
L31-L33 (`[wor] the stretch`); one Fenix Down was spent in a battle over
the 19 runs (12.4); Potions went 54 -> 34-52; three runs pitched a Tent on
the save point; the purse ended 242,571-274,041.

### 12.3 Zombie

Four of the five species Zombie a member, and the field care's Revivify
(#190) already cleared it after a fight; in battle the driver left the
zombie standing to the end (`raiseDecision` refuses a Fenix Down on one,
#245). That never cost a battle, but a zombied member's turns are the
engine's and **a won battle pays it nothing**: the first runs paid `char
6 +0 (due 0)` and `char 9 +0 (due 0)` beside `+1383 (due 1383)` for the
standing pair (`dev/run2.log`). The driver now cures it in battle
(`Driver:cureFor`: the bag's item whose STATUS1 record carries the bit,
Revivify; `[status] ... is under ZOMBIE` says it; `opts.zombieCure =
false` is the lever). The same 19 variants with the lever off and on
(`var0/analysis.txt`, `var1/analysis.txt`):

| | battles in the tomb | ended with a member Zombied | member-battles Zombied at the end | XP unpaid to members down or Zombied |
|---|---|---|---|---|
| cure off (`var0/`, `var0b/`) | 102 | 10 | 12 | 14,505 over 13 member-battles |
| cure on (`var1/`) | 102 | 3 | 3 | 3,537 over 4 member-battles |

Both arms 19 of 19 PASS. With the cure on, 19 Zombie landings were said
(`is under ZOMBIE`) and 16 cleared in battle (`Zombie is CLEARED`); the
three left at a battle's end had a plan the last blow beat
(`var1/k0_s41.log`: `actor=2 cure entity 1's Zombie with $F1` at f+1207,
the last monster dead at f+2700 before the item ran). After review the lever
was made to restore the whole pre-#263 driver (the patient test and the
pending-cure bookkeeping as well as the cure line), and the off arm re-run
as `var0b/`: 19 of 19 PASS, the same 121 battles, `102 tomb battles; 10
ended with a member Zombied, 12 member-battles Zombied at the end; XP
unpaid ... 14505 over 13 member-battles`, every run's `[outcome]` lines
identical to `var0/`'s (`review/var0_vs_var0b.txt`).

`battle_zombiecure` holds it. Its fixture, `tomb_zombie`
(`gen_tomb_zombie`), is the frame a Zombie lands in the grave room (299,
whose pool holds two of the casters) **with a turn to spare**: the landing
is captured and held, the battle plays on, and the capture is emitted only
if another standing member's command window opened while the zombie stood
and the battle was still up 900 frames after it; the suite asserts the
same precondition by name before the property (3 of var1's 19 landings
had a plan the last blow beat, `build/attempts/wt/wor-tomb-review/uncured_landings.txt`). Every battle's
`[key]` and every landing is logged with its key. Twelve fixtures
regenerated under draw variation (`review/zfix/`: SKIP 0 and 1 qualifying
landings passed over, seed shifts 0, 7, 13, 21, 29, 37): 141 grave-room
battles over 57 distinct battle keys, 18 landings over 10 of them, all 18
with a turn to spare; the twelve fixtures stand in 10 distinct battle keys
(two keys hold two fixtures, a different member Zombied in each). **The
suite passes on all twelve** (`zfix/suite2_k*_s*.log`), e.g. `PASSED:
entity 3 (char 9) Zombied at the fixture, the cure planned at f901, the
Zombie cleared at f1565, the list one fewer at f1233, the battle won, its
share paid (673)`; in one (`k0_s21`) the cured member was Zombied again
and the battle ended with it down: `down again at f1994 after the cure:
share 0`. The graph's own edge: `ninja build/results/suite/battle_zombiecure.ok`,
exit 0 (`review/zmut/ninja_zombiecure.log`). The suite also ties the clear
to the Revivify spent: the battle's item list ($2686, the list the Item
menu shows) must read one fewer after the plan and before the battle's
end; it updates at the next menu, not on the use (`k1_s21`: cleared f459,
`$F1 40 -> 39` at f624).

Negative control and mutants, all on the graph's fixture
(`review/zmut/`): the lever off fails at `the driver planned a Revivify on
the Zombied entity 3`; with that assertion dropped, at `entity 3's Zombie
cleared while the battle was up`; with that dropped too, at `the battle's
item list lost a $F1 after the cure was planned (fnil) ...`; and with that
dropped, at `the battle paid the once-Zombied entity 3 its share (got 0,
due 0), or it went down again after the cure (no)`. With the lever on:
the captured log without the driver's ZOMBIE line fails at `the driver
said [status] ... is under ZOMBIE for entity 3`; counting Remedy for
Revivify fails at `the battle's item list lost a $F5 ...`; a SPARE no
battle meets fails at `the precondition: the battle was still up 100000
frames after that window`.

Elsewhere on the route, with the cure on (`review/others/`, retries off,
shifts 0, 23, 41): `gen_vector_crash`, `gen_esper_tubes` and
`gen_wor_nikeah` 9 of 9 `PASS attempts=1/1`. Only `gen_vector_crash`
shift 23 met a Zombie (LOCKE: one landing, then `is under ZOMBIE` at the
opening of three later battles, 4 lines over its 8 battles), with no
Revivify in the bag: `entity 1 is ZOMBIE and nothing in
the bag carries the bit (Green Cherry 4, Remedy 1, Revivify 0) -- no cure
to plan; planning on`, so the cure never fired there (and the field care
could not: `[care after battle (navTo)] nothing to do: ... c1 0/968 hp 207/207
mp status1=02`; he walked on Zombied, a supply gap that predates the cure).

After the change, `ninja` ran the suites the driver
touches (`battle_zombiecure`, `battle_zombieraise`, `battle_healpolicy`,
`battle_statuses`, `battle_healerdown`, `field_zombiecure`,
`battle_magicite`, `field_care_emptybag`, `battle_breakwor_falcon`), each
fixture regenerated on this ROM: exit 0 (`zombie/suite/ninja_suites.log`).

### 12.4 Sour Mouth

The Mad Oscar's Sour Mouth landed on CELES in one battle key
(`beB4-g00FA`, in three runs), five statuses at once (`STATUS1/2
$25/$A8`: Imp, Poison, Blind; Sleep, Muddle, Mute); the driver said each,
its Muddle rule planned the curing hit ahead of the Imp's Green Cherry,
and the field care cleared the rest after the fight (`used $F2 ... status1
25 -> 21`, `used $F5 ... 21 -> 00`). All three battles were won. In one
(`var1/k3_s41.log`) the curing hit killed her: `[death] f+2836 entity 0
char 6 from 989/1696 by entity 3 char 9 cmd $00 atk $FF (an ally's
action)` -- SETZER's Fight with the Trump on a sleeping Imp at 989 HP,
above the unmuddle floor's unmeasured quarter (424) -- and a Fenix Down
raised her. That is #320's class (the floor reads a measured hit, and
SETZER's was not yet measured); a lab candidate. The other landings said
over the set: Sleep 26, Slow 14, Poison 7, Blind 3, Sap 2 (`[status]`
lines).

### 12.5 The break rows, measured (`var1/analysis.txt`)

These are the first battle measurements of section 8's rows. The `[brk]`
lines read each gauge every frame and the ROM's own gates by exec hooks:
`Ot6Gate` (a broken monster's full gauge queues no turn), `Ot6BrokenTurn`
(a turn queued before the break consumed without running), `Ot6MayAct` (a
counter refused), and vanilla's `ExecMonsterAction` as the independent
witness (a broken monster reaching it acts after all). Body battles:

| species (row today) | met | broken by the killing blow | broken alive | windows over 60 frames: turns denied at the gate / queued turns consumed / counters refused / actions run | window length, frames (min / median / max) |
|---|---|---|---|---|---|
| Mad Oscar (4 · slash) | 50 | 19 | 13 | 9: 11 / 1 / 5 / **0** | 169 / 417 / 596 |
| PowerDemon (3 · slash, pierce, ¤) | 39 | 11 | 32 | 23: 40 / 10 / 1 / **0** | 172 / 253 / 848 |
| Exoray (2 · slash, pierce) | 85 | 44 | 27 | 19: 37 / 3 / 4 / **0** | 90 / 265 / 1579 |
| Bogy (3 · slash, ¤) | 18 | 5 | 11 | 2: 2 / 0 / 2 / **0** | 270 / 334 / 334 |
| Muus (2 · slash, bludg) | 15 | 3 | 3 | 2: 9 / 1 / 0 / **0** | 369 / 750 / 750 |
| Deep Eye (2 · pierce, ¤) | 14 | 7 | 0 | — | — |
| Harpiai (3 · slash, pierce) | 3 | 1 | 2 | — | — |
| Osteosaur (3 · bludg, ¤) | 3 | 0 | 0 | — | — |
| Orog (3 · slash, bludg, ¤) | 0 | — | — | — | — |

- **Breaks land on every species met but the Osteosaur** (3 met, killed
  unbroken), and **a broken monster never acted**: no `ACTS WHILE BROKEN`
  line in `var1/`, while over the body battles 100 turns were denied at
  the gate, 16 queued turns were consumed unrun (`a turn queued before the
  break is consumed without running`) and 12 counters were refused. The
  rows skip turns as designed.
- **No break ever recovered**: every window ended in the monster's death,
  the longest 1,579 frames (an Exoray). Half the breaks in the tomb's
  species landed with the killing blow (74 of 146), where the break buys
  nothing; the Mad Oscar's four shields (8.3: "so the break lands before
  Sour Mouth's second turn") broke alive 13 times in 50, and Sour Mouth
  landed in one battle key (12.4).
- The Orog was not met: its row and its broken rule (neither Zombite nor
  the counter) are unmeasured.

### 12.6 What was left

- **The monster chest** (120,9) stays closed for the Dullahan leg (the
  contract pins it). Reaching it: from the save point the chest is up the
  room's west column, (121,14) -> (120,14) -> (120,10), a dead end below
  the chest (`plan/grid_save_point.txt`: `120,10:D`), opened facing up
  from (120,10).
- **The kit**: the Man Eater and the Exp. Egg are in the bag, unequipped;
  the Genji Helmet and the Crystal Mail went on EDGAR by the defense-gain
  rule. Arming for Dullahan (the Man Eater's pierce, the Egg) is that
  leg's.
- **The tombstone puzzle** (299 (12,39), the Exp. Egg hint) was not done.

## 13. Dullahan and the Falcon, played (legs 9-11, `gen_wor_falcon`, `wor-falcon-v1`)

Not yet driven.

## 14. What the owner may want to decide

- **The draft rows** (section 8): decided, approved as written (owner,
  2026-10-01), Dullahan at 10, the Bogy's ¤ and the chest pair included;
  authored (section 8). WoB world group 13's formation 433 is never dealt
  (8.5).
- **SETZER's class on the arc**: decided (owner, 2026-10-01): ¤ is a
  common key. His ¤ weapons key six of the twelve species since the
  re-cut (8.7); Darts (pierce) key seven.
- **#319 before or after this arc**: SETZER joins with Slot alone; EDGAR's
  Drill and Debilitator sit in a shop that refuses this party (vanilla's
  "I can't take money from the King!"). Keep the refusal (vanilla) or let
  this arc's EDGAR buy them.
- **Dullahan's telegraph** (Absolute 0 proposed) and whether the policy may
  set the gil's last digit against L? Pearl (an informed reading, a
  human input).
- **The side items' place**: leg 1 in this arc's chain with its own cut, or
  a side leg off `wor-edgar-v1`.

---

## Appendix — key addresses

| thing | citation |
|---|---|
| the engineer, to Kohlingen | 61 NPC_6 `_ca682f` `:15575`; `_ca68e6` `:15651`; `_ca6908` `:15665` (`$0106=0`, `$00DC=1` `:15690`); back `_ca6986` `:15724` |
| the castle on the world at Kohlingen | trigger (53,58)/(54,58) `_ca5f18` `:14233` (`$00DC`) |
| SETZER | inn 191 NPC_6 `_cc3bf8` `:85517`; `char_party` `:85759`; `norm_lvl` `:85762`; `$067F=1` at the World of Ruin's start `:113035` |
| Kohlingen's shops and inn | `_cc69a6` `:92679` (65/66/67); inn `_cc69ca` `:92700` (200 GP) |
| the tomb's door | 297 (8,10) `_ca3f83` `:9899` (`$01A9`, `$00CB`); stairs `_caf1a2` `:35732` |
| the tomb's switches | `_ca41a3` `:10298`, `_ca41c3` `:10316`, `_ca41e0` `:10331`, `_ca4216` `:10359`, `_ca422e` `:10373`, `_ca4259` `:10400`, `_ca4278` `:10424`, `_ca428d` `:10436`, `_ca42c0` `:10473` |
| the tombstone | `_ca4037` `:10014` (`$00C2-$00C5`, `$0112`) |
| the grave, Dullahan | 299 (100,14) `_ca42f1` `:10508`; `battle 85` `:10537`; `_ca5ea9` `:14173`; (100,7) drawn by `_caf1ed` `:35756` |
| the flashback and the Falcon | `_ca435d` `:10565`; `_ca43d9` `:10632`; `_ca44ba` `:10683`; `_ca4502` `:10723`; switches `:11257-11276`; control at (25,160) `:11280` |
| Figaro's World of Ruin tool shop | `_ca67c0` (refuses EDGAR/SABIN), `shop_menu 84` |
| L? Pearl | `AttackerEffect_1d` `battle_main.asm:10842`; the level check `@22ec` |
| Dullahan's script | `ai_script.asm:5431` |
| norm_lvl | `field/event.asm` `EventCmd_77`, `CalcAverageLevel` |
