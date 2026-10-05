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
10. **Played (section 13):** the chest and Dullahan are won at L31-L33 in
   every measured draw with the route's policy (80 of 80 each, 49 and 52
   battle keys); the gil's digit is the lever that matters at Dullahan (30
   of 32 left at 1); SETZER lands four of Dullahan's breaks in five; the
   rising leaves the Falcon over (68,187), and `H.flyTo` flies it to
   (25,160), where `wor-falcon-v1` is cut.

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
**Measured** (section 10.3): 124 of 124 over 60 distinct keys with the trio;
the deaths it still costs from a hurt start are the driver's heal-lock.

**#322 fits here too**: the Hero Ring and the passage on leg 1, the Regal
Crown on leg 2's walk to the engineer. If the owner prefers the side items
out of the story chain, leg 1 is the one to drop: legs 2-11 do not need it.
**Played** off `wor-edgar-v1` (section 10): every chest above but the
Regal Crown (leg 2's), plus South Figaro's (2,43) Elixir; the rich man's
house is a warp maze from its door, not one region. First a side branch,
then put on the chain with its relics worn (owner, 2026-10-01; 10.4).

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
**Measured** (section 13): the load is followed by the rising's own
`move_vehicle` script (`:11287-11298`), which flies the Falcon on to
(68,187) before the pilot has the controls; leg 11 flies it back to
(25,160) and lands there.

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
  Figaro's relic shop 62, none in Kohlingen), the passage's **Ribbon** (on
  CELES since 10.4).
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
| SETZER | Slot ✦; Coin Toss, Hired Help (gil-priced); divine Jackpot | built since #319 (kits.md "Setzer"): his table behind Slot, Jackpot learned at Kohlingen's rejoin | his first arc; the route's driver plays the table (`Driver:setzerLine`, #353; section 13.10) |
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
| **`wor-figaro-sweep-v1`** (sealed; on the chain since 2026-10-01, sections 10, 10.4) | world (81,86) again, after leg 1 | the side items and the desert (#321, #322), the relics worn; the boot for the Kohlingen leg |
| **`wor-kohlingen-v1`** | world (40,45), east of Kohlingen's door (sealed; section 11; re-cut from `wor-figaro-sweep-v1`, 11.4) | the first save with SETZER, dressed, after Kohlingen's shops; the boot for the tomb |
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

(Since #347 the earlier arcs and the WoB take ¤ on their own spirits too:
the Pm Stalker, the NeckHunter and Dante in the WoR, the Sealed Gate's
spirit and the Floating Continent's Apokryphos, Misfit and Brainpan in the
WoB; their route docs say why.)

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
| Dullahan: an event battle whose loss is a game over | the grave | **measured (13.6)**: 80 of 80 over 52 keys at L31-L33 with the digit settled; 30 of 32 with it at 1 | the runner retries a lost segment from its boot |
| Zombie on several members, in battle | the tomb (four species) | field cure HANDLED (#190); the battle raise refuses a Fenix Down on a zombie (#245); **the battle cure HANDLED (#263, 12.3)** | measured (12.3): members Zombied at a battle's end 12 -> 3 over 102 tomb battles; with CELES in the Ribbon (12.7) 3 over 57: Zombie lands on the other three; the Amulet goes on by the relic rule when one drops |
| Sour Mouth (six statuses) | Mad Oscar, B2/B3 | Muddle HANDLED (route-wor-edgar 12.4); Sleep "planned around / not measured live" | Remedy in battle; the Ribbon (worn by CELES since 10.4; she said no status in 12.7's ten runs) |
| L? Pearl and the gil digit | Dullahan | **HANDLED (13.3)**: `gen_wor_falcon` reads it after the chest and at the grave and moves it with a Mad Oscar's purse (no shop in the tomb) | — |
| Frozen (N. Cross) | Dullahan | planned around / not measured live | — |
| a chest that opens a battle (`EventCmd_8e`) | 300 (120,9) | **HANDLED (13.5)**: faced and pressed like a chest, the fight played by the driver | — |
| the Whelk pattern: a shell that counters, a head that hides | the chest | **measured (13.5)**: the head first; 80 of 80 over 49 keys; Giga Volt one counter in three | — |
| face-and-hold-A switches and turtle rides, three directions | the tomb | HANDLED (`H.faceAndHoldA`, up at the Figaro turtle) | down (56,14) and right (71,9) are new directions for it |
| the castle's ride (a dialog choice and a scripted move) | leg 2 | the Edgar arc's surfacing is the same scene family | choice 0 at "(Go to Kohlingen?)" |
| **flying and landing the Falcon** | the end | **HANDLED (13.8)**: `H.flyTo` (steer, A, coast, B over a landable tile), `field_flyto`, `wor-falcon-v1`'s contract | — |
| a scripted cutscene with walking in the middle | 301 (the flashback) | **HANDLED (13.1)**: talk, step, talk (`H.talkToObj` on NPC_5, the trigger (17,16)) | — |
| a party member joining undressed | SETZER | `M.equipKit` and the world menu helpers (#255) | dress him from the bag and Kohlingen's shops |
| the desert's Sand Horse pair | group 44, both castle tiles | the driver heal-locks (#312); lost 2 of 8 with two members; **won 124 of 124 over 60 keys with the trio** (section 10.3) | the heal policy's fix (#312), measured there as a lever |
| map-init `mod_bg_tiles` and turtles | the tomb, 297's stairs, 66, 89 | the lib reads live RAM | offline counts are verify-on-arrival |
| the draw | everywhere | save data (`$1FA1-$1FA5`) | vary it by using up encounters (varlab), not by seeds |

Out of scope, noted: the World of Ruin Colosseum is on foot from Kohlingen
(v0.35); Mobliz (v0.27) is on the Tzen continent; the castle's stratum
(`$00CD`) and Palidor (`$039B`) open with the Falcon.

---

## 10. The South Figaro continent, played (leg 1, `gen_wor_figaro_sweep`, `wor-figaro-sweep-v1`)

Driven 2026-10-01 for #321 and #322, as a side branch off the chain: the
segment Continues `wor-edgar-v1`, walks the desert and the plain to South
Figaro, takes the basement passage's chests by both of its ways in, takes
the Hero Ring through the Figaro cave's other door, walks back through the
desert and saves on the castle's tile again through `H.saveAtCheckpoint`:
the `wor-figaro-sweep-v1` checkpoint. As first driven nothing booted it
(`wor_kohlingen` booted `wor-edgar-v1`), the relics went to the bag and
the kit was unchanged; since the re-cut of 10.4 the leg is on the chain
(`wor_kohlingen` boots its checkpoint) and each relic goes on as it is
found. The Regal Crown is left for the Kohlingen leg. Sections 10.1-10.3
are the first driving; every number in them is quoted
from a log under `build/attempts/wt/wor-figaro-sweep/` (`capture/` the
sealing run, the graph edge, the Continue and its negative; `var1/` the
variation set; `pace1*`, `lab222_*` the formation-222 lab; `dev/` the
first runs; `lab/` the scripts), all on ROM `86018dd9ac20` (main
`b2e68aa0`), run on px13. Nothing was measured by writing game state.

### 10.1 The run (`capture/capture_wor-figaro-sweep-v1.log`)

| step | what the log says |
|---|---|
| boot | `contract wor-edgar-v1 (entry): all 26 fields hold`; `[care at the boot] nothing to do: c4 948/1600 hp 270/294 mp  c5 1384/1609 hp 75/291 mp  c6 1300/1595 hp 303/303 mp` |
| the walk to town | one battle, `battle $0DC WON after 2231 ticks` (key `beE4-g00DC`); the desert did not come up |
| South Figaro | `chest bit 230 (Elixir): OPENED` at (2,43) (the bit the World of Balance's Soft there shares; never opened before) |
| Duncan's way | `South Figaro -> Duncan's house 74(48,37)->86(52,29): DONE`, `Duncan's stairs 86(48,32)->87(56,49): DONE`; the passage (map 87, the World of Balance's pool 65): `chest bit 32 (Iron Armor): OPENED`, `chest bit 33 (Earrings): OPENED`, four battles; `the passage -> its cellar 87(33,51)->89(96,42): DONE`; `chest bit 253 (X-Potion): OPENED`, `chest bit 254 (Ribbon): OPENED`, `chest bit 255 (Ether): OPENED`; back the same way |
| the rich man's way | `74(15,18)->81(4,16)`, the warps `81(3,5)->81(5,54)` and `81(13,51)->81(39,17)`, `the rich man's stairs 81(27,10)->83(7,5)`, `83(8,12)->83(18,5)`, `the rich man's cellar 83(32,18)->89(106,54): DONE`; `chest bit 252 (Hyper Wrist): OPENED`, `chest bit 256 (RunningShoes): OPENED`; back by `83(17,4)->83(7,11)`, `83(8,4)->81(28,9)`, `81(39,18)->81(13,53)`, `81(6,55)->81(4,6)`, `81(4,17)->74(15,20)` |
| the cave's other door | the links (14,33) and (61,57), `the cave: the other door (4,4) -> 90 (41,13): on map 90 at (41,13)`, `chest bit 19 (Hero Ring): OPENED`, `map 90 -> the cave (68 (4,5))`, back by the links (17,20) and (55,57); two battles (`$0E8`, `$0E9`) |
| the walk back | `battle $0DC WON after 2738 ticks` |
| the save | `[saved] wor-figaro-sweep-v1: slot 3 holds map 1 ($2001) world tile (81,86)`; `contract wor-figaro-sweep-v1 (exit): all 29 fields hold`; `[wor] the battles: 10 ($0DC x2, $07D x1, $176 x2, $175 x2, $086 x1, $0E8 x1, $0E9 x1): 10 won, 0 the party left, 2 monster escape(s)`; `PASS (frame 40859) attempts=1/3` |

Sealed and validated (`capture/validate_wor-figaro-sweep-v1.txt`): `valid
ot6.sram-checkpoint/v1: 32768 bytes sha256=0f0537cf3a8f... holds=slot 3
world 1 (81,86) [$1F64=$2001] (saved: declared and checked)`. The graph's
own edge (`nice -n 10 ninja build/states/wor_figaro_sweep.mss`,
`capture/ninja_wor_figaro_sweep.log`) plays the same run: `PASS (frame
40859) attempts=1/3`. The cold Continue (`lab/probe_sweep_continue.lua`,
`capture/continue_figaro_sweep.log`): `contract wor-figaro-sweep-v1
(entry): all 29 fields hold`; `[continue] chests: Hero Ring OPEN, Iron
Armor OPEN, Earrings OPEN, Hyper Wrist OPEN, X-Potion OPEN, Ribbon OPEN,
Ether OPEN, RunningShoes OPEN, Elixir OPEN, Regal Crown closed; bag: Ribbon
1, Hero Ring 1, Hyper Wrist 1, RunningShoes 1`. The same probe on
`wor-edgar-v1` is the contract's negative: `contract wor-figaro-sweep-v1
(entry) VIOLATED -- 4 field(s) differ` (the four chest bits the contract
pins; `capture/negative_contract_on_wor-edgar-v1.log`).

What the plan did not know:

- **The rich man's house is a warp maze from both doors.** Straight from
  the door the stairs do not reach: `FAIL: navTo: no path (4,16)->(27,11)`
  (`dev/dev1.log`); the World of Balance's way through it (gen_celes) does.
  The offline region graph had walked through same-map warps as links.
- **South Figaro's (2,43) chest opens in the World of Ruin** (an Elixir on
  the bit the World of Balance's unreachable Soft shares).
- The Hero Ring's door (4,4) is in the cave's third piece, with the
  turtle's door (10,2), as planned.

### 10.2 Under real draw variation (`var1/`)

`lab/varlab.py` (gen_wor_kohlingen's, re-anchored) fights K encounters on
the continent's grass, forest and plain before the body (the desert's
fights count among them), walks back to (81,86), and plays the body;
retries off. `var1/summary.txt`; the per-key list is regenerated by `lab/keys.py` (build/attempts/wt/wor-figaro-sweep-review/var1_keys_rerun.txt):

| variant | verdict |
|---|---|
| K=0, shifts 0 / 23 / 41 | `PASS (frame 40859)` / `(42450)` / `(41839)` |
| K=1, 2 | `PASS (frame 43076)`, `(55020)` |
| K=3, shifts 0 / 23 / 41 | `PASS (frame 54497)` / `(54927)` / `(52444)` |
| K=4, 5 | `PASS (frame 58837)`, `(58167)` |
| K=6, shifts 0 / 23 / 41 | `PASS (frame 62397)` / `(66208)` / `(63760)` |
| K=7, 8 | `PASS (frame 71699)`, `(63427)` |

**15 of 15 `PASS attempts=1/1`**, each `contract wor-figaro-sweep-v1
(exit): all 29 fields hold`. `body: 152 battles, 132 distinct battle keys
(seed+group+formation); outcomes {'WON': 152}`, no death in any body
(`deaths(body) 0` on every run; the lowest member HP on a body battle line
217, K=2). The desert in the bodies: formation 223 (Sand Horse, Maliga x2)
12 battles over 11 keys, 138 (Maliga x3) 4, 222 (the Sand Horse pair) 1
(`k2_s0 | body | be80-g00DE | 0DE | Sand Horse x2 | WON`); in the prefixes
222 once more and 223 twice, all won.

### 10.3 The Sand Horse pair with the trio (#321, #312): a lab

The variation set meets formation 222 rarely (the walks cross 18 and 19
desert steps), so it is measured as a lab. `lab/lab_pace.lua` Continues
`wor-edgar-v1`, runs the boot's care, and paces two desert tiles
((81,92), (75,87); every non-desert tile kept off the plan), fighting
everything with the walkers' tactical driver and the field care after
each, and snapshots the world map after each battle's care
(`pace1.log`): 24 battles, all won, formation 222 at battles 1, 3, 6 and
24 (`[pace] after battle 1 ($0DE won)`, `3 ($0DE won)`, `6 ($0DE won)`,
`24 ($0DE won)`). Which formation comes next is save data, so each
snapshot before a 222 (`pace_00`, `pace_02`, `pace_05`, `pace_23`) meets
222 again whatever the wait; `lab/lab_222.lua` idles LAB_WAIT frames (the
battle's seed is the frame counter) and walks the same pace to that one
battle, retries off (`lab/labrun.py`, `lab/turns.py`). The entry states
(`[lab222] start` lines):

| snapshot | the party at the walk's start |
|---|---|
| `pace_00` (the boot, after its care) | CELES L31 1300/1595, SABIN L31 1384/1609 MP 75/291, EDGAR L31 948/1600 |
| `pace_02` | CELES L32 1696/1696, SABIN 1541/1609, EDGAR 1600/1600 |
| `pace_05` | all three at full HP |
| `pace_23` | L33: CELES 1262/1798, SABIN 1498/1812, EDGAR 1803/1803 |

**Formation 222 with the trio** (`lab222_base/summary.txt`, `turns.txt`):

| snapshot | waits | runs won | distinct keys | care turns / attack turns | runs with a death | deaths (holding BP) | Fenix Downs |
|---|---|---|---|---|---|---|---|
| `pace_00` | 1-64 | 64/64 | 60 | 106 / 196 | 5 | 13 (7) | 8 |
| `pace_02` | 1-20 | 20/20 | 20 | 1 / 74 | 0 | 0 | 0 |
| `pace_05` | 1-20 | 20/20 | 20 | 0 / 70 | 0 | 0 | 0 |
| `pace_23` | 1-20 | 20/20 | 20 | 29 / 62 | 0 | 0 | 0 |
| all | | **124/124** | **60** | 136 / 402 | 5 | 13 (7) | 8 |

Counts are over runs; waits 61-64 repeat waits 1-4's battle keys, so by
distinct key `pace_00` is 4 runs with a death, 9 deaths, 6 Fenix Downs.
Holding BP counts the dying member's own `bp=` only (the first count read
`party_bp=` too; build/attempts/wt/wor-figaro-sweep-review/lab222_deaths_recount.txt).

`formation $0DE: 124 runs, 60 distinct battle keys: 60 keys won, 0 keys
lost, 0 keys mixed; runs won 124/124`. With EDGAR it is not a wall and not
a coin flip. It is still not a confident fight from the hurt boot: five
`pace_00` draws lost members, eight Fenix Downs went into a random battle,
and seven of the thirteen deaths held BP.

**The cause is the driver's heal policy, not the rows.** The deaths are
#312's heal-lock: the pair's Sand Storm and Clamp take up to 932 a round
off the member being covered (the driver's measured round cost on its
"covering an ally" lines: 396-932), a Potion gives 250, and the heal
policy's "covering an ally" clause spends the turn on a Potion even when
the ally stays inside one round of death after it: 32 of the base set's
51 such Potions did (hp + 250 not above the round's cost; `lab222_base/covering.txt`). From
`lab222_base/pace_00_w5.log`:

    [worldNavTo] actor=1 heal entity 2 (523/1600) with $E9 -- restores 250, a round costs 905 (covering an ally)
    [worldNavTo] actor=2 heal entity 2 (336/1600) with $E9 -- restores 250, a round costs 425 (covering an ally)
    [worldNavTo] actor=1 SPEND (care): 290/1609 is inside one round of death (930) holding 3 BP, and no heal saves it (item $E9 +250 = 540) -- Fight at 3 BP ...
    [worldNavTo] [death] f+3217 entity 1 char 5 from 290/1609 by slot 0 cmd $02 atk $69 bp=3 party_bp=1,3,2,1 -- died holding 3 BP

(523 + 250 = 773 under a 905 round, 336 + 250 = 586 above a 425 one:
the first heal only delays.) That run took
11 care turns to 4 attack turns and 7398 ticks; `pace_00_w18` 15 care
turns to 2, three deaths and three Fenix Downs. With full HP (`pace_02`,
`pace_05`) no one is ever inside one round of death and the fight ends in
1600-1900 ticks with almost no care.

**The proposed fix, measured as a lab lever** (`lab/lever_lift.lua`,
not shipped): "covering an ally" heals only when the heal lifts the ally
out of one round's reach (hp + restore > the round's cost); otherwise the
actor acts, and the spend rule (which counts only the heals the care lines
would take) then spends a doomed member's pips. On the same snapshot and
waits 1-42, so the same 42 battle keys (`pair_base_lift_pace00.txt`):

| arm | won | mean ticks | care / attack turns | runs with a death | deaths (holding BP) | Fenix Downs |
|---|---|---|---|---|---|---|
| base | 42/42 | 2575 | 72 / 131 | 4 | 9 (6) | 6 |
| lift | 42/42 | 2102 | 33 / 134 | **0** | **0** | **0** |

e.g. `pace_00_w18: be74-g00DE | base WON 9209t care 15 atk 2 deaths 3(3
BP) fenix 3 | lever WON 3137t care 2 atk 4 deaths 0(0 BP) fenix 0`.

**Verdict for #321:** the Sand Horse pair is not a wall with the trio
(124 of 124 over 60 distinct keys; the walks' own desert fights 20 of 20,
build/attempts/wt/wor-figaro-sweep-review/var1_keys_rerun.txt). The losses #321 recorded with CELES and SABIN alone
(both `class=died with 3 BP banked`, the horses untouched) and the trio's
deaths here have one cause: a driver policy problem (#312), the
"covering an ally" heal that does not lift the ally clear. The Sand Horse
row (`2 · slash|pierce`) and its vanilla script need no change; the fix
belongs in `M.healDecision` (#312, v0.26) and is measured above. Not
measured: CELES and SABIN alone against 222 (the leg never fields the
pair), and the lever's effect on other fights.

### 10.4 The relics worn, and the side trip on the chain (re-cut 2026-10-01)

Owner, 2026-10-01: "you gotta use a ribbon when you have one" (guidelines
"Ribbons are worth going out of your way for"). The leg now dresses the
party the moment a find is in the bag (after the Ribbon's cellar, after
the rich man's cellar, after the Hero Ring), and `wor_kohlingen` boots its
checkpoint, so the relics ride the chain to the tomb and Dullahan. Every
number below is quoted from `build/attempts/wt/ribbon-chain/` (`capture/`
the sealing runs, the cold Continues and their negatives, for all three
re-cut checkpoints; `var_kohlingen/`, `var_tomb/` the variation sets;
`var_tomb_a/` the first tomb set, before a fix; `dev/` the first runs;
`lab/` the scripts), on ROM `86018dd9ac20` (main `5abf9e2e`), run on px13.
Nothing was measured by writing game state.

**The rule** is one lib helper, `H.relicPlan` / `H.dressRelics`
(`lib/ot6_field.lua`; #351), read from the ROM's item records (ItemProp
+6/+7 status protection, +8 bit 3 Haste, +9 the Atlas/Earring bits, +11
bit 7 the Hyper Wrist, +12 the Black Belt's counter and the two-weapon
bits) and the threats the caller states (`H.ARC_THREATS["wor-falcon"]`, one
entry the arc's three generators share: the tomb's Zombie, Sour Mouth's
Imp, Poison, Dark, Sleep, Muddle and Mute, the Sap seen there, the
chest's PetriBlast). A worn Genji Glove stays where it is; a spare one in
the bag goes on the main boost-Fighter not wearing one (the highest vigor),
and the Relic menu's own re-equip arms the second hand. The widest guard
goes next, to the party's caster (the member with the most spells
learned, counted only for the twelve characters with a spell-table row),
or, when she cannot wear it or has no free slot, to the next member by
spells learned who can; then Haste, +25% damage, vigor, counter and magic
outrank plain guards, each to the member it helps most (Haste the
slowest, damage and vigor the two-weapon Fighters first, then by vigor);
a guard fills a slot nothing better took, by the threatened statuses it
adds. Then it dresses through the Relic menu.

**Who wears what, and why** (`capture/capture_wor-figaro-sweep-v1.log`):

| member | relics | the log's reason |
|---|---|---|
| CELES | Genji Glove, **Ribbon** | `Ribbon $CA goes to CELES's slot 5 (over Jewel Ring $B5): the widest guard (9 of the threatened statuses) to the party's caster (7 spells learned; SABIN 0, EDGAR 0)` |
| SABIN | Genji Glove, Hero Ring | `Hero Ring $C9 goes to SABIN's slot 5 (over Hyper Wrist $D2): rank 4, to the member whose Fight it scales most (two weapons, vigor 47)` |
| EDGAR | RunningShoes, Hyper Wrist | `RunningShoes $BA goes to EDGAR's slot 4 ...: Haste, rank 5, to the slowest member with a free slot (speed 30)`; `Hyper Wrist $D2 goes to EDGAR's slot 5 (over Black Belt $D5): rank 3, ... (one weapon, vigor 39)` |
| SETZER (at Kohlingen) | Black Belt, Star Pendant | `Black Belt $D5 goes to SETZER's slot 4 (over (empty) $FF): rank 2 ...`; `Star Pendant $B1 goes to SETZER's slot 5 ...: a guard (1 of the threatened statuses)` (`capture/capture_wor-kohlingen-v1.log`) |

**Why CELES wears the Ribbon.** She is the party's caster and its Runic
(Dullahan's handle, section 5): Mute and Imp take her Magic and Runic
while the others keep Fight, Blitz, Tools and Slot, and Sleep, Muddle and
Zombie cost every member alike. On her it replaces a Jewel Ring whose one
threatened status (Petrify) it also covers, so she loses nothing. The
statuses the tomb said in section 12's set (`status_tomb.py` over
`wor-tomb/var1/`, body battles, 19 runs) agree: CELES 15 lines (`BLIND 3,
IMP 3, POISON 4, SLEEP 3, ZOMBIE 2`: every Sour Mouth landing), SABIN 8,
EDGAR 8, SETZER 10 (two of them Slow, which no relic here blocks). The
case for EDGAR or SETZER (the Ribbon covers both of their guards, freeing
a slot) does not hold under the rule, since the acting relics displace
those guards either way; what moves is whether CELES or EDGAR carries the
third acting relic. It was measured as a lab arm (12.7).

**What the plan did not know:** the Relic menu re-equips by Optimum on the
way out whenever the relics changed and a Genji Glove, Gauntlet or Merit
Award sits in the old or new pair, one that stays put included
(`CheckReequipRelics`, `menu/equip.asm`). The first run lost CELES's
ThunderBlade to the Blizzard, which Dullahan absorbs
(`dev/sweep1_optimum_finding.txt`: `before=13 0F 7E 8F D1 B5`,
`after=13 0E 7E 8F D1 CA`; that run was killed and its log lost, so the
file quotes the lines as read during it; the finding is live in the
capture log, `capture/capture_wor-figaro-sweep-v1.log`: `[relics after
the Ribbon] CELES: the Relic menu's re-equip moved slot 1 $0F -> $0E;
putting it back`). `H.dressRelics` notes the gear before each
Relic session and re-equips it after: `[relics after the Ribbon] CELES:
the Relic menu's re-equip moved slot 1 $0F -> $0E; putting it back`, then
`CELES's gear slot 1 holds $0F as before the relics`.

**The re-cut.** `capture/capture_wor-figaro-sweep-v1.log`: `contract
wor-edgar-v1 (entry): all 26 fields hold`; `[sweep] the Ribbon ($CA) is
worn by CELES`, `the Hero Ring ($C9) is worn by SABIN`, `the Hyper Wrist
($D2) is worn by EDGAR`, `the RunningShoes ($BA) is worn by EDGAR`;
`[saved] wor-figaro-sweep-v1: slot 3 holds map 1 ($2001) world tile
(81,86)`; `contract wor-figaro-sweep-v1 (exit): all 30 fields hold`; `[wor]
the battles: 10 ($0DC x2, $07D x1, $176 x2, $175 x2, $086 x1, $0E8 x1, $0E9
x1): 10 won`; `PASS (frame 42972) attempts=1/3`. Sealed
(`capture/validate_wor-figaro-sweep-v1.txt`): `valid
ot6.sram-checkpoint/v1: 32768 bytes sha256=2d716d50536d... holds=slot 3
world 1 (81,86)`. The cold Continue (`capture/continue_figaro_sweep.log`):
`contract wor-figaro-sweep-v1 (entry): all 30 fields hold`, `CELES ...
esper+kit 06 13 0F 7E 8F D1 CA; SABIN ... 01 57 57 77 90 D1 C9; EDGAR ...
00 11 5C 76 89 BA D2`. The contract's new pin fails alone on the battery
it replaced (`capture/negative_contract_on_old_wor-figaro-sweep-v1.log`):
`contract wor-figaro-sweep-v1 (entry) VIOLATED -- 1 field(s) differ: ram
$1702 & $FF (CELES wears the Ribbon ...): expected 0xCA, read 0xB5`. The
first sealing run (`capture-first/`) dressed EDGAR with two Star Pendants
for a moment (a tie between equal guards went by item number); the
re-cut's rule keeps the worn guard on a tie and gives a guard only to a
member it adds a threatened status to.

**The leg under draw variation** (`var_sweep/`, `lab/varlab_sweep.py`, the
first driving's varlab with the shipped generator: K encounters used up
on the continent's grass, forest and plain before the body, retries off;
`summary.txt`, `keys.txt`):

| K | 0 | 1 | 2 | 3 | 4 | 5 (6 fought) | 6 | 7 (8 fought) | 8 | 10 |
|---|---|---|---|---|---|---|---|---|---|---|
| PASS frame | 42972 | 45812 | 57120 | 55355 | 69437 | 59535 | 65808 | 74621 | 66478 | 76346 |
| lowest member HP (body) | 948 | 992 | 217 | 794 | 524 | 1010 | 259 | 842 | 1110 | 920 |

**10 of 10 `PASS attempts=1/1`**, each `contract wor-figaro-sweep-v1
(exit): all 30 fields hold`; every `[outcome]` line `paid as due` (150 of
150), no death in a body. `body: 102 battles, 90 distinct battle keys
(seed+group+formation); outcomes {'WON': 102}`: by place map 87 (the
passage) 34 keys, the world 27, map 68 (the cave) 25, map 90 5. The desert
in the bodies: the Sand Horse pair (222) once (`k2_s0 | body | be80-g00DE
| 0DE | Sand Horse x2 | WON`, 4176 ticks), formation 223 six times. In
every run the three Relic-menu stops ended in the same kit (`[relics after
the Hero Ring] CELES wears Genji Glove $D1, Ribbon $CA`, `SABIN wears Genji
Glove $D1, Hero Ring $C9`, `EDGAR wears RunningShoes $BA, Hyper Wrist
$D2`) with one Optimum put-back (`putting it back`, 1 a run).

**After the review's generality fixes** (a spare two-weapon relic
planned, spells counted only where a spell-table row exists, the widest
guard passed to the next member who can wear it, the threats in one
place), the three captures were re-run from the same tracked boots
(`recheck/`): `PASS (frame 42972)`, `(26324)`, `(26573)`, each
`attempts=1/3` with `all 30` / `all 34` / `all 31 fields hold`, and the
payloads are the same batteries byte for byte (`recheck/validate_*.txt`:
`sha256=2d716d50536d...`, `b0c2de780704...`, `cd0d052614f6...`); only the
provenance signatures were re-sealed. The cold Continues hold (`all 30`,
`all 34`, `all 31 fields hold`). A plan-only probe on the battery from
before the re-cut (`recheck/probe_relic_plan.log`, `lab/probe_relic_plan.lua`;
the Ribbon still in the bag) exercises the fallback: `[probe] the Ribbon
goes to: the trio CELES; without CELES SABIN; CELES listed last CELES`
(`Ribbon $CA goes to SABIN's slot 5 (over Black Belt $D5): the widest
guard ... to SABIN, the first by spells learned (SABIN 0, EDGAR 0) who can
wear it with a free slot`). No battery on this arc holds a spare Genji
Glove, Gauntlet or Merit Award, or GOGO or UMARO, so those two paths have
not run.

## 11. The castle's ride, Kohlingen and SETZER, played (legs 2-4, `gen_wor_kohlingen`, `wor-kohlingen-v1`)

Driven 2026-10-01 for #263 (and #322's Regal Crown). The segment
Continued `wor-edgar-v1` (`H.bootCheckpoint`; since 11.4 it Continues
`wor-figaro-sweep-v1`), takes the Regal Crown off
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

### 11.4 Re-cut from the side trip (`build/attempts/wt/ribbon-chain/`)

The leg now Continues `wor-figaro-sweep-v1` (10.4): the same tile (81,86),
the castle not yet sailed, the trio wearing the side trip's relics and the
bag holding its finds. Nothing in the leg's route or assertions needed to
change; SETZER's relics now come from the same relic rule over all four
(`H.dressRelics`), which leaves the trio's as they were. The capture
(`capture/capture_wor-kohlingen-v1.log`): `contract wor-figaro-sweep-v1
(entry): all 30 fields hold`; `[care at the boot] nothing to do`; `[kit]
the Regal Crown goes to SABIN`; `[castle] f10159 the castle has sailed for
Kohlingen`; `[kit] SETZER's weapon: shop 65's $50 scores 6133 against the
bag's best 6104` (the Trump, as in 11.3); `[shop] Kohlingen item counter:
bought: tonic=4 potion=54 fenix=29 remedy=10 soft=18 revivify=10
greencherry=5 gil=231655 (spent 9200 GP)`; `[relics with SETZER] SETZER
wears Black Belt $D5, Star Pendant $B1`; `[saved] wor-kohlingen-v1: slot 3
holds map 1 ($2001) world tile (40,45)`; `contract wor-kohlingen-v1 (exit):
all 34 fields hold`; `[wor] the battles: 3 ($0E7 x1, $0E9 x1, $0EF x1): 3
won`; `PASS (frame 26324) attempts=1/3`. Sealed
(`capture/validate_wor-kohlingen-v1.txt`): `sha256=b0c2de780704...
holds=slot 3 world 1 (40,45)`. The cold Continue
(`capture/continue_kohlingen.log`): `contract wor-kohlingen-v1 (entry): all
34 fields hold`, `SETZER L31 ... esper+kit 17 50 5F 7C 95 D5 B1;
gil=231655`. The contract's new pin (CELES's Ribbon) fails alone on the
battery it replaced (`capture/negative_contract_on_old_wor-kohlingen-v1.log`:
`VIOLATED -- 1 field(s) differ: ram $1702 & $FF ... expected 0xCA, read
0xB5`).

Under draw variation (`var_kohlingen/`, `lab/varlab_kohlingen.py`: K
encounters used up on the South Figaro continent before the body, retries
off; `summary.txt`, `keys.txt`):

| K | body battles (key/formation) | lowest member HP (body) | verdict |
|---|---|---|---|
| 0 | `be1C/$0E7`, `beC0/$0E9`, `be1C/$0EF` | 1519 | `PASS (frame 26324) attempts=1/1` |
| 1 | `beA0/$0E7`, `beA0/$08A`, `be84/$0EF` | 1550 | `PASS (frame 28478)` |
| 2 | `be7C/$0E9`, `beB0/$0E9`, `be0C/$0EF` | 1273 | `PASS (frame 31092)` |
| 3 | `be48/$0E7`, `beC0/$0E9`, `beB8/$0F1` | 1285 | `PASS (frame 36059)` |
| 4 (5 fought) | `beF0/$0E5`, `be0C/$0F1` | 1097 | `PASS (frame 39974)` |
| 5 | `be74/$0E8`, `beB4/$0E7` | 1102 | `PASS (frame 42664)` |
| 6 (7 fought) | `be0C/$0E8`, `beC0/$0E4`, `be50/$0DE`, `beE0/$0EF` | 938 | `PASS (frame 52406)` |
| 8 | `beF0/$0E4`, `beC8/$0E8`, `beC8/$0EF` | 803 | `PASS (frame 56204)` |
| 10 (11 fought) | `beF0/$0E8`, `beAC/$0E5` | 1050 | `PASS (frame 58716)` |
| 12 | `be28/$0E5`, `be58/$0EF` | 1515 | `PASS (frame 62227)` |

**10 of 10 `PASS attempts=1/1`**, each `contract wor-kohlingen-v1 (exit):
all 34 fields hold` with SETZER in `D5 B1`; every `[outcome]` line `paid
as due` (81 of 81), no death in a body. `body: 27 battles, 26 distinct
battle keys (seed+group+formation); outcomes {'WON': 27}` (one key,
`beC0-g00E9/$0E9`, in K=0 and K=3). The Sand Horse pair (222) came up once
in a body (K=6: `be50-g00DE | 0DE | Sand Horse x2 | WON`) and once in a
prefix (K=10), both won by the trio in its new relics.

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
  The cause, found later (`build/attempts/wt/walker-after-menu/`): every
  flag `H.hasControl` read came back clear while the field was still
  reloading the map after the menu, and the object map the walker reads
  held the menu's scratch bytes until LoadMap rebuilt it. `H.hasControl`
  now also requires the map loaded (`H.mapLoaded`). The menu helpers close
  on the control flags alone (`H.fieldControl`), so a menu can follow a
  menu through the reload as a player holding X does, and the step runner's
  reload gate (`H.menuStep`) holds any other step until the map is loaded;
  this step's approach side, like every cached pick, is chosen only with
  `H.hasControl`, and its own 39-frame wait is gone.
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

### 12.7 Re-cut with the Ribbon on (`build/attempts/wt/ribbon-chain/`)

The leg Continues the re-cut `wor-kohlingen-v1` (11.4): CELES in the
Ribbon, SABIN the Hero Ring, EDGAR the RunningShoes and the Hyper Wrist,
SETZER the Black Belt and a Star Pendant. On the save point, before the
save, the relic rule re-plans with what the chests and the drops brought
(`H.dressRelics`): the Exp. Egg is not ranked (it helps no fight), and an
Amulet, when one drops, goes on SETZER over the Star Pendant (`Amulet $B3
goes to SETZER's slot 5 (over Star Pendant $B1): a guard (3 of the
threatened statuses)`, `var_tomb/k1_s0.log`). The capture
(`capture/capture_wor-tomb-v1.log`): `contract wor-kohlingen-v1 (entry):
all 34 fields hold`; `[kit] the Genji Helmet ($81) goes to EDGAR`, `the
Crystal Mail ($98) goes to EDGAR`; `[saved] wor-tomb-v1: slot 3 holds map
300 ($012C) tile (122,14)`; `contract wor-tomb-v1 (exit): all 31 fields
hold`; `[wor] the battles: 6 ($0F6 x1, $0F9 x2, $0F7 x1, $0FA x1, $0FB x1):
6 won`; `PASS (frame 26573) attempts=1/3`. Sealed
(`capture/validate_wor-tomb-v1.txt`): `sha256=cd0d052614f6... holds=slot 3
map 300 (122,14)`. The cold Continue (`capture/continue_tomb.log`):
`contract wor-tomb-v1 (entry): all 31 fields hold`, `CELES L32 ... esper+kit
06 13 0F 7E 8F D1 CA; ... EDGAR L32 ... 00 11 5C 81 98 BA D2; SETZER L31 ...
17 50 5F 7C 95 D5 B1; gil=247857; revivify=17 remedy=10 potion=53 fenix=29
tent=10`; the new pin fails alone on the battery it replaced
(`capture/negative_contract_on_old_wor-tomb-v1.log`: `VIOLATED -- 1
field(s) differ: ram $1702 & $FF ... expected 0xCA, read 0xB5`).

**A failed first set** (`var_tomb_a/`): the first re-cut also re-planned
the relics at B2's hub after the chests. Where an Amulet had dropped the
Relic menu opened there, and afterwards the walker found no path from
(29,26) to (37,23) for the 900 frames of its retries: `FAIL: navTo: no path
(29,26)->(37,23) [0 edges blocklisted, 20 retries]` in K=1 and K=6 (8 of 10
PASS), and a third time in the lab arm's first set before it was
re-derived (`var_tomb_armE_a/k1_s0.log`, the same line). Every run whose
Relic menu opened at the hub failed there and no other did
(`build/attempts/wt/ribbon-chain-review/hub_menus.txt`); the field care at
the same tile never opened a menu in any set (`[before the turtles]
nothing to do`, 39 runs), so the defect predates the relic rule and is
filed apart. The re-plan then ran only on the save point, whose step-on waited
out the field's stale map after a menu. The capture never opened that
menu, so its re-capture is the same battery byte for byte (payload
`cd0d052614f6...` both times; `capture-tomb-first/`); only the provenance
signature changed. Diagnosed later (`build/attempts/wt/walker-after-menu/`):
the hub's map recovers on time; the walker's choice does not. The Relic
menu's close wait ended while the field was still reloading the map, the
next step's door crossing picked its staging tile from a BFS on the
unloaded map, found none of (37,22)'s neighbours reachable, and fell back
to (37,23), a tile no walk reaches. Now the step after a menu helper waits
in the step runner's reload gate until the map is loaded, and the
crossing's staging tile is picked only on a frame `H.hasControl` reads
true; the crossing stages at (37,21), and the re-plan runs at the hub
again (and once more on the save point).

**Under draw variation** (`var_tomb/`, `lab/varlab_tomb.py`: K encounters
used up on the Kohlingen continent before the body, retries off;
`summary.txt`, `analysis.txt`, `status.txt`):

| K | verdict | K | verdict |
|---|---|---|---|
| 0 | `PASS (frame 26573) attempts=1/1` | 5 | `PASS (frame 46755)` |
| 1 | `PASS (frame 30405)` | 6 | `PASS (frame 49949)` |
| 2 | `PASS (frame 34604)` | 8 | `PASS (frame 55071)` |
| 3 | `PASS (frame 32800)` | 10 | `PASS (frame 65616)` |
| 4 | `PASS (frame 42370)` | 12 | `PASS (frame 63711)` |

**10 of 10**, each `contract wor-tomb-v1 (exit): all 31 fields hold`.
`body: 62 battles over 56 distinct battle keys (seed+group+formation);
outcomes {'WON': 62}`, 57 of them in the tomb (formation 250 22 battles,
249 16, 248 7, 247 5, 251 4).

**What the Ribbon changed, against 12.2-12.4.** Section 12's set
(`wor-tomb/var1/`, the cure on, 19 runs) against this one, and a lab arm
with the Ribbon on EDGAR instead (`var_tomb_armE/`: the same generators
with the relic rule's `opts.guardTo = 4` lever and the CELES pin dropped,
`lab/arm_edgar.py`, its own sweep and Kohlingen captures under `armE/`;
EDGAR wore `Ribbon $CA, RunningShoes $BA`, CELES `Genji Glove $D1, Hyper
Wrist $D2`; the same ten K, 10 of 10 PASS). Status lines are counted as
said in body battles (`lab/status_tomb.py`); "deaths" are the `[death]`
lines other than the Zombie touch's (`atk $EF`, the landing reads as a
death):

| set | tomb battles | ended with a member Zombied | member-battles Zombied at the end | XP unpaid to members down or Zombied | statuses said on the Ribbon's wearer | Zombie said | other deaths | Fenix Downs |
|---|---|---|---|---|---|---|---|---|
| 12.2, no Ribbon (19 runs) | 102 | 3 | 3 | 3,537 over 4 | (CELES) 15 | 19 | 3 | 1 |
| Ribbon on CELES (10 runs) | 57 | 3 | 3 | 2,476 over 3 | **0** | 22 | 4 | 1 |
| Ribbon on EDGAR (10 runs) | 57 | 2 | 2 | 1,796 over 2 | **0** (CELES 6) | 15 | 3 | 0 |

- **The Ribbon empties its wearer's status list**: CELES said nothing in
  ten runs (15 lines over 19 before, every Sour Mouth landing among them);
  in the arm EDGAR said nothing and CELES 6 (`POISON 4, ZOMBIE 2`). Sour
  Mouth now lands on whoever else it picks (`SETZER ... is an IMP` in K=1
  and K=10).
- **Zombie landings per tomb battle roughly doubled while the
  end-of-battle outcomes held.** Zombie was said 22 times over 57 tomb
  battles here against 19 over 102 before (0.39 against 0.19 a battle;
  the arm 15 over 57), all of it on the other three (`SABIN 5, EDGAR 8,
  SETZER 9` lines); the in-battle cure (12.3) cleared most (`Zombie
  cleared in battle 19`, `status.txt`), and the
  battles that ended with a member Zombied held at three of 57 against
  three of 102 (2.9% before, 5.3% here, 3.5% in the arm: three, three and
  two battles, inside each other's noise). The arms share 21 of their ~58 distinct body keys
  (`arms_keys.txt`), so ten runs each cannot tell them apart; the choice
  of wearer stands on the reason in 10.4, not on these numbers.
- **The deaths are the party's own** in both arms. Ribbon on CELES: a
  Zombied SETZER's Fight killed CELES from 1417 (`var_tomb/k10_s0.log`:
  `[death] f+2379 entity 0 char 6 from 1417/1798 by entity 3 char 9 ... (an
  ally's action)`, the one Fenix Down); CELES's boosted party Cure 2,
  planned before EDGAR was Zombied, killed him when it landed (`k8_s0.log`:
  `party cure: 2 hurt (worst 71%), boost 1 folds $2D -> $2E ... all
  allies`, then `[death] f+1864 entity 2 char 4 from 750/1701 by entity 0
  char 6 cmd $02 atk $2E`); and twice a one-action kill from 80% or more on
  SETZER (`cmd $0C atk $E5`, K=5 and K=12). In the arm a Cure 2 or Cure 3
  landed on a Zombied SABIN twice (`k2`, `k6`: CELES's) and a Zombied
  CELES's own turn cast one on herself (`k3`: `(its own action)`). A
  party cure landing on a member Zombied after it was planned is a driver
  class for a lab (out of this re-cut's scope).

The graph's own edges on the merged tree (`ninja/ninja_edges.log`, `nice
ninja -j4 build/states/wor_figaro_sweep.mss build/states/wor_kohlingen.mss
build/states/wor_tomb.mss build/results/suite/battle_zombiecure.ok`) play
the same runs (`PASS (frame 42972)`, `(26324)`, `(26573)`, each
`attempts=1/3` with its exit contract holding), regenerate
`battle_zombiecure`'s fixture on the new `wor_tomb` (`tomb_zombie
generated: battle be54-g00F9, entity 3 (char 9) Zombied at f6620`), and the
suite passes on it (`[23/23] suite battle_zombiecure`, no FAILED).

## 13. Dullahan and the Falcon, played (legs 9-11, `gen_wor_falcon`, `wor-falcon-v1`)

Driven 2026-10-01 for #263. The segment Continues `wor-tomb-v1` (the
re-cut with the Ribbon on CELES, payload `cd0d0526...`), arms for the two
fights ahead, opens the monster chest, moves the gil's last digit off the
party's levels, saves, beats Dullahan, plays the flashback, flies the
Falcon to (25,160), lands it and saves: the `wor-falcon-v1` checkpoint.
Every number below is quoted from a log under
`build/attempts/wt/wor-falcon/final/` (`capture2/` the sealing run,
`continue/` the cold Continue, `neg/` the contract's negatives, `suite/`
the graph's own edge, `field_flyto` and its mutants, `var1/` and `var0/`
the variation sets, `chest/`, `dull/`, `dullctl/` and `dullczar/` the
labs, `interrupted/` three lab runs stopped when the base moved; their
scripts one level up). The development runs, on the pre-Ribbon
`wor-tomb-v1` (`468ec180...`), are kept in `dev/`. All on ROM
`86018dd9ac20`, px13. Nothing was measured by writing game state.

### 13.1 The run (`capture2/capture_wor-falcon-v1.log`)

| step | what the log says |
|---|---|
| boot | `contract wor-tomb-v1 (entry): all 31 fields hold`; `kit CELES 06 13 0F 7E 8F D1 CA` (the ThunderBlade in her left hand, the Ribbon) |
| the kit | `[kit] CELES hand 1: holds $0F (keys 0 of the fights' species, power 108, ABSORBED by one of them); the best for the fights ahead is $16 (keys 0, power 125)`; `[kit] EDGAR hand 0: holds $11 (keys 0 ...); the best ... is $06 (keys 2, power 146)` (the Man Eater: pierce keys the Whelk Head and Dullahan); SETZER keeps the Trump (`keys 1`), SABIN his Fire Knuckles (`keys 2`) |
| the chest | `[key] battle key beC4-g01B1`; `[outcome] battle $1B1 WON after 5913 ticks: killed s0:$101` |
| the purse | `[pearl] after the chest: gil 248857, last digit 7: L? Pearl would hit no one` (no walk needed on this draw) |
| the save | `[saved] the save after the chest: slot 3 holds map 300 ($012C) tile (122,14)` |
| the grave | one battle on the walk (`$0F8 WON after 3625 ticks`); `[pearl] pressing the grave: gil 251107, last digit 7: L? Pearl would hit no one` |
| Dullahan | `[key] battle key be14-g01C7`; `[monact] ... cmd $0C atk $98 L? Pearl`; `[outcome] battle $1C7 WON after 6906 ticks` |
| the flashback | `[falcon] f22536 in the flashback map 301 (28,6)`; `[falcon] f23416 Daryl's promise seen map 301 (17,16)` |
| the rising | `[falcon] f32617 in flight over world 1 (68,187): vehicle 1` |
| the flight | `[fly] f32619 (68.06,187.56) tile (68,187) -> (25,160): 50.4 tiles, bearing 148, heading 316 (err 102, turn 0)`; `[fly] f32739 (45.12,172.38) ... speed 2048 (coasts 2.8)`; `[fly] the Falcon to (25,160): on foot at (25,160), the airship parked at (25,160)` |
| the save | `[saved] wor-falcon-v1: slot 3 holds map 1 ($0401) world tile (25,160)`; `contract wor-falcon-v1 (exit): all 30 fields hold`; `[wor] the battles: 3 ($1B1 x1, $0F8 x1, $1C7 x1): 3 won`; `PASS (frame 33362) attempts=1/3` |

Sealed and validated (`capture2/validate_wor-falcon-v1.txt`): `valid
ot6.sram-checkpoint/v1: 32768 bytes sha256=eeee5c8ccd1d... holds=slot 3
world 1 (25,160) [$1F64=$0401] (saved: declared and checked)`. The cold
Continue (`continue/continue_falcon.log`): `contract wor-falcon-v1 (entry):
all 30 fields hold`, `[continue] world 1 at (25,160), ... the airship parked
at (25,160): CELES L32 ... SETZER L31 ...; gil=251107; potion=52 fenix=29`.
The graph's own edge plays the same run (`suite/ninja_field_flyto.log`:
`[3/5] generate wor_falcon <- gen_wor_falcon`, `PASS (frame 33362)
attempts=1/3`). The contract's negatives (`neg/`): the same probe on
`wor-tomb-v1` reads `contract wor-falcon-v1 (entry) VIOLATED -- 10
field(s) differ`; and copies of the battery with one cell changed (the
slot checksum recomputed; `make_neg.py`) each fail alone: `switch $02B2
(Dullahan is beaten ...): expected 1, read 0`, `switch $00CC (the Falcon
has risen ...): expected 1, read 0`, `ram $1F62 & $FF (the Falcon parked at
x 25 ...): expected 0x19, read 0x1A`, each `VIOLATED -- 1 field(s) differ`.
The flashback's `$01F0-$01F3` are the scene's own temporaries (measured 0
again at the landing; the first contract pinned `$01F3` and failed on it,
`dev/gl1/k0_s0.log`). The ROM clears switches `$01F0-$01FF` on every new
map (`ff6/src/field/init.asm:470-471`, `stz $1ebe / stz $1ebf`).

What the plan did not know:

- **The rising flies the Falcon itself.** After `load_map 1, {25, 160}`
  the event's `move_vehicle` script (`event_main.asm:11287-11298`) carries
  it to (68,187) before the pilot has it; the plan's "control in flight
  over (25,160)" was the load, not the control. Leg 11 flies back to
  (25,160), the tile the next arcs were planned from (2.7).
- **The tomb moves the digit only through the Mad Oscar.** Of the
  formations the east room and the grave room deal (groups 151 and 150:
  247-251) only the Mad Oscar's pay a purse that does not end in 0 (`$061
  Mad Oscar ... GP 2292`, x2 as a random: +4 to the digit); the Exoray and
  PowerDemon formations' end in 0 (`dev/dev/run1.log`: six grave-room
  battles, each `$0F9` or `$0F7`, the digit `1` throughout), the chest
  pays 1000, and GP Rain costs level x 30 (`AttackerEffect_51`). There is
  no shop.
- **A Genji Glove's Relic menu re-equips**, so a relic lever has to put the
  hands back (the relic rule's own lesson, ribbon-chain); `lab_grave.lua`'s
  `LAB_RELIC` does.

### 13.2 Arming, and the route's policy

`armForFights` reads the ROM: for each weapon hand, the weapon from the
hand and the bag that scores best on the two fights' species, power scaled
up by the share of their gauged species it keys (its class in the shield
row, or its element among their vanilla weaknesses), never one whose
element any of them absorbs; EDGAR, SETZER and SABIN first, CELES last.
The first draft scored keys first and power second and handed the bag's
30-power MithrilKnife to SETZER and CELES (`dev/dev/run1.log`: `the best
for the fights ahead is $01 (keys 2, power 30)`); the power-scaled score is
what shipped. No relic moves: `wor-tomb-v1` was dressed by the relic rule
for the arc's threats on that save point, and the chest and Dullahan add
none it does not cover.

The fights' options: the chest `{ focus = { { species = WHELK_HEAD } } }`
(the head first; the shell has no gauge and answers hits), Dullahan
`{ runic = true }` (CELES raises Runic: Ice 2, Ice 3, Pearl, N. Cross and
his own Cure 2 are runic), everything else the driver's defaults (break,
the keyed line, boost banked and spent, Potions and CELES's Cure for care).
Two levers were measured on the pre-Ribbon base and not shipped:
- the chest with CELES on Runic too (Giga Volt is runic): 48 of 48 won
  either way over 31 keys, with 1 death (focus alone, `dev/c0/`) against 7
  (with Runic, `dev/c1/`): `runs: {'WON': 48}; deaths 1` / `deaths 7 (bp at
  death: Counter({1: 4, 3: 2, 5: 1}))`;
- Dullahan with SETZER the only healer and no Cure (`{ runic = true, cure
  = false, healer = 9 }`, `dev/p1c/`) on 16 draws with the digit at 1: `runs:
  {'LOST': 2, 'WON': 14}; deaths 13`, against the shipped options' 16 of 16
  on the same snapshots (`dev/p0c/`).

### 13.3 L? Pearl and the purse

L? Pearl opens every Dullahan fight (`L? Pearl casts 80 in 80 runs`,
`dull/`). With the digit at 1 it hits all four: `[monact] f493 slot 0 cmd
$0C atk $98 L? Pearl partyhp 1798,1710,1701,1597`, then `partyhp=1219,1075,
1263,1156` (`dullctl/var0_k1_s0_w1.log`); with it at 5, nobody
(`dull/var1_k1_s0_w1.log`: `partyhp=1798,1710,1701,1597` after it). It
comes back in the hit-counter combo (L? Pearl + Absolute 0), at whatever HP
the party has then: of the control arm's 29 deaths, 3 are to it
(`dullctl/var0_k1_s0_w9.log`: three members at once, `[death] f+13359 ...
atk $98`).

The policy (`settleDigit`): read the digit after the chest and again at
the grave; while L? Pearl would hit someone (or the digit is 0, whose
divide-by-zero is unmeasured), walk the room for a battle's purse, at most
8 battles. On the policy arm (`var1/`) the digit after the chest was 1 on 4
of 10 draws and 9 or 7 on the rest; the walk cost 1-3 battles each (K=1 took 3: two purses ending in 0, then a Mad Oscar), and on
one draw (K=7) the walk to the grave moved a safe 9 to 3 (`at the grave:
gil 277673, last digit 3: L? Pearl would hit CELES L33, SABIN L33`) and one
grave-room battle moved it on. Every press of the grave on the policy arm
read `L? Pearl would hit no one`.

### 13.4 Under real draw variation (`var1/`, `var0/`)

`genlab.py` derives the generator with a block after the boot that fights
K encounters in the east room's own pool and steps back onto the save
point (`varlab.py`'s shape); retries off. `var1/summary.txt` (the policy)
and `var0/summary.txt` (`DIGIT_POLICY = false`, the control):

| arm | runs | verdicts | chest | digit at the press | Dullahan | KOs / Zombie landings / Fenix Downs | Potions spent |
|---|---|---|---|---|---|---|---|
| policy, K=0-7 at shift 0, K=0 at 23 and 41 | 10 | `10 PASS` | 10 won, 10 keys | 7, 7, 7, 5, 5, 5, 5, 9, 9, 7 | 10 won, 10 keys, 5821-10149 ticks | 4 / 2 / 3 | 1-17 a run |
| control, K=0-5 | 6 | `6 PASS` | 6 won | 7, 1, 1, 1, 1, 9 | 6 won, 6443-11766 ticks | 3 / 1 / 2 | 1-28 a run (28 and 25 at digit 1) |

Every run landed at (25,160) and held the exit contract. The KOs and
Zombie landings are the tomb's random battles (the Exoray's Zombie, 12.3)
but one: a KO in Dullahan's fight on the policy arm (`var1/k3_s0.log`:
`[death] f+4224 entity 1 char 5 from 300/1710 by slot 0 cmd $00 atk $EE
bp=1`), raised and won.

### 13.5 The monster chest, a lab (`chest/`, `lab_chestsnap.lua`)

From the frame below the chest in each of the ten `var1/` runs
(`wor_chest.mss`: armed, on (120,10)), eight waits each before the press
(the event battle's draw is the frame counter at its start), retries off,
the generator's own options. `chest/analysis.txt`:

| | runs | distinct battle keys | won | deaths (boost at death) | Fenix Downs | Potions | ticks (min / median / max) |
|---|---|---|---|---|---|---|---|
| the chest | 80 | 49 | **80** (`groups won in every run: 49 of 49`) | 5 (bp 1, 1, 1, 0, 0) | 4 | 77 | 1549 / 4093 / 9509 |

Not a coin flip and not attrition at this level: every key won. The fight
ends on the first boss_death, the shell's or the head's, **40 and 40**
(`killed s0:$101` / `killed s1:$135`). The head was never broken: its six
pierce shields took 82 chips, all EDGAR's (the AutoCrossbow), and the fight
ended first in every run. The shell's counter is Giga Volt one hit in three,
as its script says (`attack NOTHING, NOTHING, GIGA_VOLT`), not on every
hit: **73 Giga Volts over 213 counters weighed** on the shell
(`Ot6MayAct`, `[retal]` lines). The head hid 46 times (`cmd $24 atk $08`),
and Magnitude8 came 34 times. The four keys with deaths: `beB4` (1, no
Fenix), `beB0` (2), `beF0` (1), `be28` (1). It is worth opening at this
level; it pays no XP and holds nothing but the fight.

### 13.6 Dullahan, a lab (`dull/`, `dullctl/`, `dullczar/`, `lab_grave.lua`)

From the frame on the grave in each `var1/` run (`wor_grave.mss`), eight
waits each before the press, retries off, the generator's own options; a
loss is a game over (`FAIL: GAME OVER fired`), counted, not retried.

| arm | runs | distinct keys | won | deaths (boost at death) | Fenix Downs | Potions | ticks (min / median / max) |
|---|---|---|---|---|---|---|---|
| **the route** (digit settled, `dull/`) | 80 | 52 | **80** (`groups won in every run: 52 of 52`) | 4 (all bp 1) | 4 | 98 | 5485 / 6588 / 13168 |
| control: the digit at 1, all four hit (`var0/` K=1-4, `dullctl/`) | 32 | 27 | **30** (`groups with a loss: 2`: `beD0`, `beC4`) | 29 (bp 0 x17, 1 x8, 2 x4) | 10 | 233 | 5958 / 8821 / 16500 (wins) |
| lever: the Czarina Ring (Safe, Shell) for CELES's Ribbon (`var1/` K=0-3, `dullczar/`) | 32 | 20 | 32 | 0 | 0 | 21 | 5428 / 6184 / 10771 |

On the same four entry states the route's own arm spent 37 Potions and 2
Fenix Downs with 2 deaths over its 32 runs (both in var1_k0_s0_w9); the Czarina arm, 21, 0 and 0
(the relic's menu moves the press's frame, so the keys differ). Both
losses in the control are wipes late in long fights, the party worn down
with little boost banked (`dullctl/var0_k1_s0_w9.log`: `[death] f+13359
entity 0 char 6 from 224/1798 by slot 0 cmd $0C atk $98 bp=0`, three
members to the combo's L? Pearl); the policy's settled digit removes both
L? Pearls' damage. **Measured rate with the route's policy: 80 of 80, 52 of
52 keys.** The hit-counter combo barely fires (Absolute 0: 0 in `dull/`, 2
in `dullctl/`): the break and the kill come first.

Two notes for the driver, not shipped: the heal model prices Dullahan's
round at two of his worst single actions (`inside one round of death
(2172)`, two 1086-HP Pearls under Haste), above every member's maximum, so
every member is always "in danger" and many turns go to +250 Potions
(`dev/grave0/w37.log`); and an auto-Shell relic is not ranked by the relic
rule (`H.relicClass` returns nil for the Czarina Ring), so the lever above
cannot be the rule's choice today.

### 13.7 SETZER on arrival (owner, 2026-10-01: "every recruit should feel amazing")

`credit.lua` credits each frame's fall in a monster's HP, shields, broken
ticks and life to the party member whose action is running (ExecCmd);
`analyze.py` sums it. SETZER fights with the Trump (¤) throughout; Slot is
not in the driver's plan here.

| fight | SETZER's damage (share of all; per-run median) | chips | breaks | fight-ending blows | the others |
|---|---|---|---|---|---|
| Dullahan (`dull/`, 80 runs, 1,876,390 damage) | 399,666 (**21%**; median 21%) | 349 of 886 | **68 of 84** | 7 of 80 | SABIN 61% and 46 blows, EDGAR 17% and 26, CELES 1% (Runic) |
| the chest (`chest/`, 80 runs) | 195,523 (19%; median 10%) | 0 | 0 (no break landed by anyone) | 21 of 80 | SABIN 42% and 30, CELES 21% and 26, EDGAR 17% and 3 |

In Dullahan he is the breaker: four breaks in five are his (`breaks landed
by: {'SETZER': 68, 'SABIN': 11, 'EDGAR': 5}`), the ¤ key of 8.7 at work,
and the break is where SABIN's Blitzes land their damage. He lands one
kill in eleven. In the chest neither part keys ¤ (the shell has no gauge,
the head is pierce), and he is a fifth of the damage. Not a passenger; his
share is the break, not the damage.

### 13.8 Flying and landing (`H.flyTo`, `field_flyto`)

`H.flyTo(tx, ty)` (lib/ot6_field.lua) flies the airship with the pilot's
buttons, measured from the Falcon's first control (`dev/dev/probe_flight.log`):
heading `$73` (the math angle is `$73 - 270`; Left turns it up), position
`$34/$38` in 1/16 tiles, A for speed `$26` (to `$0800`, about a third of a
tile a frame), a coast of about three tiles, B to land on a tile whose
property bit 1 is clear. It steers to the bearing, letting go early enough
for the turn's momentum, holds A while the target is ahead and farther than
the coast, nudges with A when stopped short, and lands over the target;
it refuses a target the airship cannot land on. `field_flyto` (suite,
fixture `wor_flight`, the pilot's first control) flies to the route's
(25,160) (a turn of 102 degrees left) and to (128,171) (31 degrees right),
asserting the party on foot on each target and the airship parked there
(`suite/suite_field_flyto.log`: `[flyto] PASSED (25,160): on foot there at
f341`, `[flyto] PASSED (128,171): on foot there at f665`, `PASS (frame 665)
attempts=1/1`). Its mutants fail where they should (`suite/`): with the
flight taken out, `assertEq failed: (25,160): on foot ($11FA): got 1, want
0`; with an unlandable target, `(100,170) is a tile the airship can land on
(its property word $0753, bit 1 clear): got false, want true`.

### 13.9 What was left

- **The Exp. Egg** (from the tomb) is still in the bag; the relic rule does
  not rank it and no member wears it.
- **SETZER's Slot** was not played in these fights (the driver's `opts.slot`
  was off); the Coin Toss relic stays in the bag.  Since #319/#353 the
  driver plays his table (13.10).
- **The tombstone puzzle** (299 (12,39)) was not done.
- The Dullahan care-model and the auto-Shell relic notes above (13.6).

### 13.10 SETZER's kit played (#319, #353)

Since #319 SETZER's Slot row opens his table (Slot, Coin Toss, Hired Help,
Jackpot; kits.md "Setzer") and the driver plays it (`Driver:setzerLine`).
Measured on ROM `c4986f696e4a` (px13), every number from a log under
`build/attempts/wt/kit-setzer/`: six variation runs of the generator (K = 0-5
encounters used up first, `labs/var1.txt`: `k0_s0: PASS (frame 30542)` ...
`k5_s0: PASS (frame 42239)`, every run won the chest and Dullahan), and from
their snapshots the chest and grave labs at four waits each, retries off,
with the policy (`labs/chest`, `labs/dull`) and with `setzer = false`, the
driver as it was (`labs/chestctl`, `labs/dullctl`). `labs/go.sh` is the
batch; `labs/*_analysis.txt` the tables.

| fight | arm | runs / keys | won | ticks (min / median / max) | SETZER's damage | his chips / breaks / fight-ending blows | his rows used |
|---|---|---|---|---|---|---|---|
| Dullahan | policy | 24 / 20 | 24 | 5426 / 6828 / 11227 | 163,311 (**29%**; median 30%) | 103 / **16 of 24** / **9 of 24** | Jackpot 14 |
| Dullahan | control | 24 / 20 | 24 | 5670 / 6831 / 11227 | 112,198 (20%; median 25%) | 106 / 17 of 24 / 2 of 24 | — |
| the chest | policy | 24 / 21 | 24 | 1673 / 4415 / 7593 | 66,472 (**23%**; median 13%) | 2 / 0 / **8 of 24** | Hired Help 8, Jackpot 2 |
| the chest | control | 24 / 21 | 24 | 1673 / 4473 / 9477 | 56,005 (19%; median 11%) | 0 / 0 / 6 of 24 | — |

From `labs/dull_analysis.txt`: `SETZER actions 104 damage 163311 (29% of
all; per run min 8% median 30% max 54%) chips 103 breaks 16 kills 9`, and
`dullctl_analysis.txt`: `SETZER actions 104 damage 112198 (20% of all ...)
chips 106 breaks 17 kills 2`.  The rows from the credit lines' commands
(`$15A` Hired Help, `$15B` Jackpot): Dullahan `{'00': 74, '01': 16, '15B':
14}` against the control's `{'00': 89, '01': 15}`; the chest `{'00': 24,
'01': 9, '15A': 8, '15B': 2}` against `{'00': 38, '01': 15}`.

What it says.  In Dullahan SETZER stays the breaker (his Trump keys ¤ and
his Fight lands the breaks either way) and Jackpot becomes his finisher:
of its 14 throws, 9 came with Dullahan Broken and under 10,000 HP, where a
1-BP floor of three reached the cap (`SETZER Jackpot on slot 0 (4592 HP, 0
shield(s), Broken) at 1 BP (lowest face 3), 99 MP of 297`), 3 with him
Broken at 14,432-14,570 HP (also 1 BP), and 2 before the break, at 2 BP
with one or two shields left (`SETZER Jackpot on slot 0 (17663 HP, 1
shield(s)) at 2 BP (lowest face 5)`), counted off the `[advanceStory]`
lines in `labs/dull/`; the fight-ending blows move from SABIN to him; the fights are no shorter (the
same median) and no fight was lost in either arm. In the chest, where ¤
keys nothing, Hired Help is his way in: the sellsword strikes the Whelk
Head with piercing (`SETZER Hired Help on slot 1: 1550 gil of 247857; his
Fight keys nothing there`), and the policy arm spent 28 Potions to the
control's 40 and no Fenix Down to its 2. Slot and Coin Toss were not chosen
on this arc: the tomb's random fights end before his bank reaches 3, and
Coin Toss waits for two revealed ¤ bodies.

The table above measured the first Jackpot and Hired Help (a floor the
boost raised to certain sixes; one hire whose fee the boost doubled), on ROM
`c4986f696e4a`.  Both were redesigned the same day (kits.md "Setzer"); 13.11
measures the redesign.

### 13.11 Dullahan with the rolls and the hires (owner, 2026-10-02)

Jackpot now rolls once more a boost point (each roll a face 1-6, its own hit)
and Hired Help hires once more a point (each hire its own fee, hit and
chip).  The policy arm again, briefly, on ROM `0a95b57fd7bd`: the grave
frame the regenerated generator leaves (`final2/wor_falcon.log`), eight
waits, `labs-r2/dull2.txt`: 8 of 8 won over 3 battle keys (`groups won in
every run: 3 of 3`), no death, `potions spent 12 over 8 runs`.  From
`labs-r2/dull2_analysis.txt`: `SETZER actions 31 damage 95840 (51% of all;
per run min 27% median 72% max 79%) chips 23 breaks 3 kills 4`.  The
policy throws Jackpot at the opening, with one point and Dullahan whole
(`SETZER Jackpot on slot 0 (23450 HP, 10 shield(s)) at 1 BP: 2 roll(s) of
expected 5162 each, 99 MP of 198`: this frame's SETZER spent one Jackpot in
the chest, hence 198 MP), and hires against the shields before the ¤ cell
is revealed (`SETZER Hired Help on slot 0 at 2 BP: 3 hire(s) at 1550 gil
...`).  Three keys is few: the share is a direction, not a rate.

### 13.12 The driver's table on the generators that seat SETZER

The coordinator's review asked what the driver's table does on the
generators that seat SETZER, where nothing had measured it: the World of
Balance grind (`gen_narshe_mission`, from `terra-returned-v1`, LOCKE EDGAR
SABIN SETZER) and this arc's tomb and Falcon legs.  Each generator twice
(in-battle seeds 0 and 23, retries off) with the policy and with
`SETZER_POLICY_OFF` (the control), ROM `0a95b57fd7bd`;
`build/attempts/wt/kit-setzer/gm/gm_summary.txt`:

| generator | arm | battles won | deaths | Fenix Downs (bag) | gil | rows chosen |
|---|---|---|---|---|---|---|
| narshe_mission | control s0 / s23 | 18 / 18 | 0 / 0 | 20 -> 23 | 122,167 -> 113,497 / 113,797 | — |
| narshe_mission | policy s0 / s23 | 17 / 18 | **2** / 0 | 20 -> 23 | 122,167 -> **84,253 / 78,797** | Hired Help 28 / 28 |
| wor_tomb | control | 6 / 6 | 0 / 0 | 29 -> 29 | 231,655 -> 247,857 | — |
| wor_tomb | policy | 6 / 6 | **1 / 2** | 29 -> 29 | 231,655 -> 244,757 / 241,657 | Hired Help 2 / 3 |
| wor_falcon | control | 3 / 3 | 0 / 0 | 29 -> 29 | 247,857 -> 251,107 | — |
| wor_falcon | policy | 3 / 3 | 0 / 0 | 29 -> 29 | 247,857 -> 248,007 | Jackpot 2 / 2, Hired Help 2 / 1 |

(`nm_pol_s0: ... battles 17 won 17 | deaths 2 (bp {'0': 2}) | ... gil 122167
-> 84253 | SETZER plans {'Hired Help': 28}`; `tomb_pol_s23: ... deaths 2 (bp
{'1': 2}) ... gil 231655 -> 241657 | SETZER plans {'Hired Help': 3}`.)  Hired
Help in random battles bought nothing the free Fight did not: some 30,000
gil a WoB run and deaths the control did not take.  So the gil rows now
wait for an event battle (kits.md), and the policy arms again
(`gm/gm2_summary.txt`): the grind and the tomb play exactly as the control
(`nm_pol_s0: PASS (frame 106028) ... deaths 0 ... gil 122167 -> 113497 |
SETZER plans {}`, `tomb_pol_s0: ... gil 231655 -> 247857 | SETZER plans {}`),
and the Falcon leg keeps its Jackpots and hires (`fal_pol_s0: ... deaths 1
(bp {'1': 1}) ... gil 247857 -> 251107 | SETZER plans {'Jackpot': 2, 'Hired
Help': 1}`, `fal_pol_s23: ... deaths 0 ... gil 247857 -> 246457`).  Two
seeds an arm is a direction, not a rate.

### 13.13 Dullahan on the final kit, by distinct battle key (round 3)

ROM `049ee079d85e` (Coin Toss buys tosses, a pass with no body pays
nothing, Jackpot's rejection draw), the grave frame `wor_grave`, the
policy arm (`{ runic = true }`) and the control (`{ runic = true, setzer =
false }`) over the same entries; `build/attempts/wt/kit-setzer/labs-r3/`.
A fight is fixed by its battle key (the in-battle seed shift only moves the
entry frame, so shifts 0 / 7 / 13 met keys the waits already met), so the
16 runs an arm are 8 distinct keys, and `dull_perkey.txt` sets the arms
side by side a key:

| key | policy ticks | SETZER (policy) | control ticks | SETZER (control) |
|---|---|---|---|---|
| be0C | 4,015 | 86%, Hired Help 1, Jackpot 1, the kill | 6,893 | 26% |
| be1C | 6,186 | 68%, Hired Help 2, Jackpot 1 | 9,615 | 8% |
| be3C | 6,454 | 54%, Hired Help 2, Jackpot 1 | 6,814 | 26% |
| be5C | 9,542 | 18%, Jackpot 1 | 6,024 | 25% |
| be7C | 9,179 | 56%, Hired Help 1, Jackpot 1, the kill | 6,704 | 12% |
| be9C | 7,483 | 70%, Hired Help 1, Jackpot 1, the kill | 6,119 | 30% |
| beBC | 5,705 | 73%, Hired Help 2, Jackpot 1 | 8,728 | 8% |
| beDC | 5,340 | 73%, Hired Help 2, Jackpot 1 | 6,416 | 17% |

(`be0C-g01C7 | policy 4015t SETZER actions 2 ($15A:1 $15B:1), damage 20218
(86%), chips 1, breaks 0, kills 1`; `| control 6893t SETZER actions 4
($00:4), damage 6109 (26%), chips 4, breaks 1, kills 0`.)  Both arms win
every fight (`groups won in every run: 8 of 8`) with no death and no Fenix
Down.  With his table SETZER deals a median 69% a key against 21% without
it, and the fight is shorter at 5 keys of 8 (53,904 ticks over the 8
against 57,313).  The cost is Potions: `potions spent 55 over 16 runs`
against `potions spent 20 over 16 runs` (run-weighted; by key, 19 against
12), most of it at be5C and be7C, the two keys where the policy fight ran
longer.  His Fight's own breaks go (6 against 10 in the run-weighted
credit): the Jackpot is null-break and the hires chip what his Fight does
not key.

**What the Falcon leg spends in gil** with the gil rows kept to event
battles: `gen_wor_falcon` from `wor-tomb-v1`, policy and control at four
in-battle seeds, every fall of the purse logged (`labs-r3/gm3_summary.txt`,
`gilwatch.lua`; the falls to 0 and back are the generator's save and
reload, not spending).  Seeds 0 and 13 spend nothing (`fal_pol_s0: ...
gil 247857 -> 251107`, the control's own end; seed 0's one planned hire,
in the chest, never ran: the battle ended, `killed s0:$101`, before
SETZER's turn came); seeds 7 and 23 spend 4,650 gil, three hires at 1,550 in Dullahan
(`[gilwatch] f12550 gil 251107 -> 249557 (-1550)`, `[gilwatch] f13963 gil
249557 -> 246457 (-3100)`; `fal_pol_s7: ... gil 247857 -> 246457`), under
2% of a purse of 247,857.  No random battle spends gil in any of the eight.

### 13.14 The care policy pass (wt/care-policy, #312 #348 #351)

The two 13.6 notes are the driver's now.  The round price charges one
enemy's second action in a window at its typical action -- the mean of its
damaging actions on the party, once it has taken three; a counter-attack, a
buff and a status landing (a Zombie touch reading as the whole HP bar) stay
out of it -- rather than its worst again; a heal on an endangered ally is
taken only when it lifts them clear of the round; and the relic rule ranks
a Shell/Safe ward for a fight whose damage is magic
(`H.FIGHT_THREATS.dullahan`).  The Exp. Egg goes to whoever is behind on
levels only into a free slot or over a guard or spare ward that guards
nothing the fight threatens -- never over an acting relic -- and not at
all when arming for a boss: Dullahan's threats carry `boss = true`.  The
leg arms for Dullahan before the grave (`[relics for Dullahan] CELES: slot
4 Genji Glove $D1, slot 5 Czarina Ring $C1 (1 change)`, `SETZER: slot 4
Black Belt $D5, slot 5 Star Pendant $B1 (0 changes)`) and goes back to the
arc's relics after him (the Ribbon to CELES).  The first cut put the Egg
on SETZER for Dullahan (over the Star Pendant) and over an acting relic in
all 13 tomb runs (SETZER's Black Belt in 11, EDGAR's RunningShoes in 2);
this one puts it on in none of the 13.

Measured from the generator's own grave snapshots, by distinct fight
(snapshot + key), every fight won in every arm
(`build/attempts/wt/care-policy/dull/`, `tally_r2_*.txt`): over K = 0..3 x 8
waits, main's driver and kit spent 37 Potions with 2 deaths in one fight;
this branch's driver on main's kit 11 Potions, 1 death; main's driver on
this branch's kit 39, 2 deaths in one fight; this branch's driver and kit
18, 1 death.  Over K = 0 x 64 waits (15 fights a kit): 23 Potions and 2
deaths (main), 5 and 1 (this driver, main's kit), 22 and 0 (main's driver,
this kit), 10 and 0 (this driver and kit).  The gain is in Potions; the
deaths are one or two a sweep either way.  The two kits' snapshots draw
disjoint keys, so the relics' own effect is not separated from the draw.

### 13.15 The bag in battle (wt/care-items, #370)

The care lines offered only the Potion (else the Tonic).  After 13.14 the
chain's Dullahan left SABIN at 905/1812 under an 846 round with seven
X-Potions in the bag (`$E9 restores 250 and a round costs 846 ... acting
instead`) and he died from 591.  (The bag line called the Ether `$EC`
"elixir"; the party holds 5 Ethers and 7 Elixirs `$EE` there.)  Now:

- every battle-usable HP item is weighed by the lift rule and the cheapest
  in gil that the rule takes is spent (`H.itemChoice`).  Prices are the
  ROM's: a sold item's price word (ShopProp lists what shops sell), an
  unsold one's effect at the shops' least gil per HP and MP (the Tonic's
  1, the Tincture's 30) times a scarcity term, 1 + legs to the next source
  / the count held (`H.scarcity`; the next source is the generator's
  `opts.nextSource`, else a 10-leg horizon), so the last few count for
  more.  An unsold item with no HP or MP to price it by is priceless, not
  free;
- an item no shop sells (X-Potion, Elixir, Megalixir) is spent only on a
  member inside the round, never on a top-up; `opts.reserve` still keeps
  the last n of anything.  A sold item dearer than the death it guards
  against (`H.deathGil`) is no top-up either.  A Megalixir is a party turn
  when two or more members are inside their rounds and it lifts each (no
  bag on the route holds one, so that menu path is unmeasured in play);
- the status cures take the same gil order (`H.cureItems`);
- a confirmed heal holds the others off its target until the HP rises or
  a hit lands first (`H.healInFlight`);
- the round's one care turn is kept after the confirm (`H.careRefund`):
  from 11a8f6e3 the confirm's own `dropPlan("confirm_attempt")` refunded
  it, so the rule bound only while a plan was being steered.  It holds for
  top-ups and reopens for a lift (`H.liftReopens`): a member inside their
  round with a heal in hand that lifts them clear, the way an owed top-up
  reopens it for a raise.  The Gate's shift 5 had wiped with LOCKE at
  144/820 under a 286 round and an X-Potion in the bag, the turn gone to a
  top-up;
- a queued heal holds the others off its target only when it lifts them
  clear of the round, or they stand outside it (`H.inFlightHolds`): a
  Potion queued on SETZER at 25/902 under 413 held an Elixir off;
- the SPEND line names why no heal saves: the round's care turn gone to
  another, the heal policy, or an empty bag.

A queued cure-hit is part of its target's round (`H.roundWithQueuedHits`,
#320's floor gap): the floor is read when the hit is planned, and the hit
waits in the queue -- the Gate's shift 5 lost SABIN to LOCKE's hit planned
at 275/902 (floor 114) and run at 27, after the Muddle had cleared on its
own.  With the hit priced in, the care lines planned an Elixir on him at
182; on that draw it was queued behind the same monsters and he still fell.

Measured on a wide sample, by distinct fight (snapshot + battle key, the
first run of each), Zombie touches apart: Dullahan arm B from the grave
cut for K = 0..10 by main's generator, 18 waits each (198 runs, 154
distinct fights an arm), and the Gate from 28 boot shifts (0..54 step 2).
Four arms: main 5883ecb9, cae71db9, cae71db9 with the old care refund,
and the head (892e274f: the lift reopen, the in-flight cap, the queued
cure-hit).  Intervals are 95% (normal on the per-fight counts; Wilson for
proportions); the paired column is the head against each arm on the same
fights, with McNemar's exact p on the discordant ones
(`build/attempts/wt/care-items/wide/stats_*.txt`):

| | main | cae71db9 | refund | head |
|---|---|---|---|---|
| Dullahan B: deaths (a fight) | 16 (0.104, 0.056-0.152) | 7 (0.045, 0.012-0.078) | 14 (0.091, 0.045-0.136) | 11 (0.071, 0.031-0.112) |
| ... Fenix Downs | 9 | 7 | 8 | 9 |
| ... head minus arm, discordant worse/better, p | 4/9, 0.27 | 4/0, 0.125 | 0/3, 0.25 | -- |
| ... Potions, X-Potions | 101, 0 | 38, 51 | 62, 78 | 55, 88 |
| Gate: runs passed (Wilson) | 27/28 (0.82-0.99) | 27/28 | 28/28 (0.88-1.00) | 28/28 |
| ... deaths (fights 104-108) | 9 | 9 | 5 | 5 |

Every arm that weighs the bag beats main at Dullahan B in the point
estimate; cae71db9 does so outside the noise (13 fights better, 4 worse,
p = 0.049).  No arm beats the head outside the noise: cae71db9 has 4
fewer Dullahan deaths (4 discordant fights, all the head's, p = 0.125),
the head 4 fewer Gate deaths.  No X-Potion is planned outside the round in
any arm (the head: 125 inside, 0 outside at Dullahan B; 7 and 0 at the
Gate), and no cure-hit killed anyone in these 904 runs.

battle_brokendeath's ladder was four rungs ten phases apart, a budget read
off a map of counting phases measured with one driver; under the head's
driver with the refund the old suite failed shift 0 (`rungs ...:
1:0w/0sk 2:0w/0sk 3:0w/0sk 4:1w/0s`) and needed its last rung at shift 20.
It now visits rung 1 and one target in each of the period's fifteen runs
of four (every phase the fight can draw), stopping at the first counting
rung, and logs the map it saw: 7 of 7 shifts pass under the head, the
refund arm and main's driver alike, in at most 3 rungs (r5/bd_*).

The last round (670a9f21) closed three gaps the re-review found:

- the Muddle rule's floor is the hitter's floor plus the target's round
  (`H.muddleFloors`): the hit waits in the queue behind the round, so it
  is held unless hp - round stays above the floor.  The Gate's shift 5
  had queued LOCKE's hit on SABIN at 275/902 over a floor of 114, under a
  413 round, and it ran at 27;
- `H.inFlightHolds` holds the others off only for a queued heal whose
  restore is known and lifts the target clear of the round; a party cure
  or a first cast not yet measured holds nobody;
- `H.raiseDecision` judges "survives alone" against the round the lift
  rule prices as well as the smallest hit, and with nothing measured the
  raise stands but owes its top-up.  The chain's sabin_done had raised
  SABIN to 45/363 on "survives the smallest hit, 34" under a 91 round and
  on "no enemy hit measured yet", both "judged to survive alone", and he
  died from 45 and from 10.

On the wide sample the round changed nothing: Dullahan B 154 fights, 11
deaths, 9 Fenix Downs, and the Gate 28/28 with 5 deaths, the same fights
as 892e274f's code with no discordant fight either place
(`wide/stats_final_*.txt`).  Against main at Dullahan B the head had 4
fights worse and 9 better (p = 0.27): no difference shown either way.

The chain's sabin_done had moved from main's 1 death and no Fenix Down to
3 and 3 (892e274f, `chain11/main_vs_head.txt`).  It is the draw.  Main's
and the head's chains enter the leg on the same gau_joined (the same
bytes: it is cut from the falls-done checkpoint, `trench/entry_sha.txt`),
and the chain plays boot shift 0.  Both arms played the whole leg from
that entry under boot shifts 0..62 step 2 (30 distinct first battles,
over 100 distinct battle keys an arm, `trench/stats.txt`):

| | main | head |
|---|---|---|
| runs passed | 32/32 | 32/32 |
| deaths (Aspik's Giga Volt) | 30 (14) | 30 (14) |
| Fenix Downs landed | 26 | 26 |
| runs with a death | 17 | 17 |
| head minus main, by first battle: more deaths / fewer / as many | | 6 / 6 / 18 |

Shift 0 is one of the head's six worse draws (main 1 death, head 3).
Under 670a9f21 the leg plays the same as under 892e274f at shift 0
(`PASS (frame 32726)`, 3 deaths): the raises there now owe their top-up,
and SABIN still falls at 45 with the Potion queued.  About half the
leg's deaths in both arms are Giga Volt one-shots on SABIN from 200 HP or
more, each after his auto-targeted Pummel (Blitz $5D) into an Aspik
formation (the retaliation the dive's kill order is written around); no
in-battle care reaches those.

The chain at 670a9f21 failed battle_healerdown: the Magitek riders have no
Fight row, so under the finisher window (monsters at 80 HP <= 200) the
care block stayed shut and they passed 35 and 36 turns with the healer
dead; care opened only with entity 1 at 13/68, when a raise to 7 under a
16 round no longer survives it.  The window now holds only an actor with
a Fight row, and the raise comes on the riders' first turn: 0/16 boot
shifts passed before, 16/16 after (`healerdown/`).  The chain regenerated
from nothing with it passes with no failed edge, and no leg moved from
670a9f21's chain; against main it is 6 deaths and 1 Fenix Down to 8 and
4, all of it sabin_done's shift-0 draw above (`chain15/main_vs_head.txt`).

### 13.16 The Exp. Egg worn (wt/v026-field, #351)

13.14's Egg never went on: on the v0.25 chain the tomb's Egg sat in the bag
to the Falcon (`[relics after Dullahan] SETZER: slot 4 Black Belt $D5, slot
5 Star Pendant $B1`; field_relicplan "0 Egg check(s)").  The rule now
follows the owner's ranking on #351: the Egg goes to whoever is furthest
behind on levels, into a free slot or over the lowest-ranked relic there
that no threat needs (a spare ward, a guard adding no threatened status,
then an acting relic by rank); two-weapon relics, wards the fight calls
for and guards adding a threatened status are never displaced, and boss
arming still keeps it off.  Played on the branch from the tracked
checkpoints: `[relics on the save point] SETZER: slot 4 Exp. Egg $E4, slot
5 Star Pendant $B1`, Dullahan armed without it (`SETZER: slot 4 Black Belt
$D5 ...`) and `[relics after Dullahan] SETZER wears Exp. Egg $E4, Star
Pendant $B1`, both legs passing on their first attempt
(`build/attempts/wt/v026-field/351/`).

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
- **Dullahan's telegraph** (Absolute 0 proposed): open. The hit-counter
  combo that holds Absolute 0 fired twice in 144 lab fights (13.6);
  the break and the kill come first. The gil's last digit against L? Pearl:
  decided fair play (the TLM, 2026-10-01); with no shop in the tomb the
  route moves it with a Mad Oscar's purse (13.3). Left unmoved, the fight
  was lost 2 times in 32 at digit 1 (13.6).
- **An auto-Shell relic for a caster boss** (13.6): the Czarina Ring on
  CELES in place of the Ribbon spent 21 Potions and no Fenix Down over 32
  Dullahan fights, against the route's 37 and 2 on the same entry states;
  both won every fight. The relic rule does not rank Safe/Shell relics, so
  the route does not wear it; ranking them for a fight whose damage is
  spells is a rule change for the owner.
- **SETZER on arrival** (13.7): in Dullahan he lands four breaks in five
  and a fifth of the damage; in the chest, where ¤ keys nothing, a fifth of
  the damage and no breaks. His Slot is not played (#319's verbs); whether
  the driver should spin it at bosses is open.
- **The side items' place**: decided (owner, 2026-10-01: "you gotta use a
  ribbon when you have one"): the side leg is on the chain and its relics
  are worn (10.4, 11.4, 12.7). Before that, the Ribbon, Hero Ring, Hyper
  Wrist and RunningShoes were in that branch's bag only: the tomb's legs,
  booted from `wor-kohlingen-v1` off `wor-edgar-v1`,
  did not carry them. Leg 1 is critical path again; the cost in chain
  length and re-cuts is ours (guidelines).
- **Who wears the Ribbon**: CELES by the relic rule (the party's caster,
  10.4). The audit's case for EDGAR or SETZER (it frees a guard slot) and
  the lab arm (12.7) do not separate the two at ten runs each; the
  lever (`opts.guardTo`) is there if the owner prefers another wearer.

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
