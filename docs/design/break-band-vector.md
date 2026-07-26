# Break band — Vector / Magitek Research Facility (survey + proposed rows)

Issue #11, v0.6 scope. **Survey and proposal only** — no source was touched.
`ot6_break_floor.inc`, `gen_break_floor.py` and `Ot6ShieldTbl` are all
unchanged by this document.

Everything below was decoded from the vendored data under `ff6/` on
2026-07-26. Line references are to that tree. Where a claim is an inference
rather than something read out of the source, it is labelled.

---

## 0. What this replaces, and how the two tables interact

`Ot6SeedShields` scans the authored table **first** and only falls through to
the generated floor on a miss:

- `ff6/src/battle/ot6_break.asm:24-38` — linear scan of `Ot6ShieldTbl`
  (4-byte records: `.word` species, `.byte` shields, `.byte` class mask),
  `$ffff`-terminated. A hit stores the authored class mask into
  `OT6_BP_CLASS,y` and the authored shield count.
- `ff6/src/battle/ot6_break.asm:39-51` — `@formula`: species-indexed
  `OT6_FLOOR_CLASS[species]` (the generated floor) plus `2 + level/8` capped
  at 6.

The table itself lives at `ff6/src/battle/ot6_hud.asm:1273`. So **authoring a
band means adding `Ot6ShieldTbl` rows; it needs no generator change at all.**
The generator work issue #11 asks for is separate, and §9 covers it.

One coupling worth restating (it is documented at `ot6_hud.asm:1380-1392`): an
`Ot6ShieldTbl` row also exempts its species from `Ot6HpScale`
(`ot6_break.asm:466-476`). That is inert today — every band of `Ot6HpMulTbl`
ships `$10` = 1× (`ot6_break.asm:568-575`) — but it is why the Mt. Kolts pass
put overworld species on `Ot6ElemAddTbl` instead. Class weaknesses have
nowhere else to live, so the rows below take that trade knowingly.

---

## 1. The band, decoded from the tables

Decode chain, per Measurement #8's method (`balance-metrics.md:820-829`):

`map_prop.dat[map*33]` → byte 0 = map-title index (`field/text.asm:113`,
`$0520`), byte 5 bit 7 = random-battle enable (`field/battle.asm:332`,
`$0525`), byte 28 = default song (`field/reset.asm:475`, `$053c`);
`SubBattleGroup[map]` (`field/battle.asm:392`) → `RandBattleGroup[group*8]`
(`field/battle.asm:408`, four formation words drawn at
**31.25 / 31.25 / 31.25 / 6.25 %** — `field/battle.asm:398-406`) →
`BattleMonsters[formation*15]` (`battle_main.asm:16503`, cf/6200; byte 1 =
present mask, bytes 2-7 = id low, byte 14 = id high bits) →
`MonsterProp[species*32]` (level +16, HP +8, absorb +23, null +24, weak +25).

Per-step encounter rate is `SubBattleRate` (2 bits/map, `field/battle.asm:361`)
into `SubBattleRateTbl` = `$0070, $0040, $0160, $0200`
(`field/battle.asm:259-262`), then halved by OT6's `Ot6DangerMulW`
(`ot6_break.asm:585`).

### 1.1 Map identification

Vector town is **maps 242 / 253** (title index 49). The Magitek Research
Facility is the contiguous block **262-275**, identified three ways that all
agree: the map titles (`MAGITEK FACTORY` on 262, `MAGITEK RES. FACILITY` on
271), the default song (`$47` = `SONG::DEVILS_LAB`,
`ff6/include/sound/song_script.inc:80`) on every map 262-275, and the fact
that **battle groups 80, 81, 104, 105, 106 and 108 are used by no other map in
the game**.

Map 240 is the **Vector rooftops** — Vector's own tileset, song `$1a`
(`SAVE_THEM`), CRANE_1/2/3 NPC sprites (`event/npc_prop.asm`, map-240 block),
and a long entrance into map 262. It is where the Crane escape happens.

Boss placement, from the NPC event tables (`event/npc_prop.asm`, whose
per-map blocks map onto `map_prop` at a fixed +3 offset — calibrated against
the shop maps, e.g. Narshe 21→24, S. Figaro 74→77, Albrook 323→326):

| fight | map | event |
|---|---|---|
| Ifrit & Shiva | 262, 263 | `_cc7937` → `battle 70` (`event_main.asm:95283`) |
| Shiva magicite | 263 | `_cc79dd` (`event_main.asm:95372`) |
| Number 024 | 272 | `_cc79ed` → `battle 72` (`event_main.asm:95386`) |
| Cranes | (event) | `battle 71, AIRSHIP_CENTER` (`event_main.asm:47070`) |

`EventBattleGroup` index 73 → formation `$1ba` (Number 128 + both blades) is
**not referenced by any `battle` command in `event/`** — the trigger for that
fight was not located. Flagged, not guessed.

### 1.2 The encounter-bearing maps

| map | title | enable | group | rate | pool |
|---|---|---|---|---|---|
| 240 `$0f0` | (Vector rooftops) | **Y** | 108 | `$0070` | Chaser, Commando, Pipsqueak |
| 262 `$106` | MAGITEK FACTORY | **Y** | 80 | `$0040` | Garm, Commando, ProtoArmor, Pipsqueak |
| 263 `$107` | — | **Y** | 81 | `$0040` | ProtoArmor, Garm, Commando, Pipsqueak |
| 264 `$108` | — | **Y** | 104 | `$0040` | Flan |
| 269 `$10d` | — | **Y** | 105 | `$0070` | General, Pipsqueak, Trapper |
| 271 `$10f` | MAGITEK RES. FACILITY | **Y** | 106 | `$0070` | Gobbler, Rhinox |
| 273 `$111` | — | **Y** | 106 | `$0070` | Gobbler, Rhinox |
| 275 `$113` | BASEMENT 3 | **Y** | 106 | `$0070` | Gobbler, Rhinox |
| 270 `$10e` | — | n | 105 | — | carries a group, cannot draw it |
| 272 `$110` | — | n | 104 | — | Number 024's room; same |
| 274 `$112` | — | n | 106 | — | same |

The three enable-bit-clear maps are the same shape as Measurement #8's map
95/74 finding (`balance-metrics.md:831-840`).

**One anomaly, reported as data, mechanism unverified.** Maps 265 `$109`,
267 `$10b` and 268 `$10c` are Devil's-Lab maps with the enable bit **set** and
`SubBattleGroup = 0` — battle group 0 is the Narshe overworld pool
(Leafer `$017` ×1 / Leafer ×2 + Dark Wind `$028`, level 5). Their NPC sprite
sets (Cid + elevator on 265; ESPER_TERRA + MAGICITE + EXPLOSION on 267) say
these are cutscene rooms, so the player probably never takes a danger-checked
step on them — but that is an inference, not something read. **If they do roll,
the band draws level-5 trash.** Worth one runtime check on a v0.6 fixture; it
is not authored for below, because Leafer belongs to the deferred v0.5 pool.

---

## 2. The pools, formation by formation

Slot weights are 31.25 / 31.25 / 31.25 / 6.25 %; several groups repeat a
formation across slots 2 and 3, which is why some appearance shares are
37.5 % rather than 31.25 %.

### Group 80 — map 262 (factory entrance, Ifrit & Shiva's floor)

| p | formation | contents |
|---|---|---|
| 31.25 % | `$074` | Garm ×2, Commando ×1 |
| 31.25 % | `$194` | ProtoArmor ×1, Pipsqueak ×2 |
| 31.25 % | `$073` | Garm ×2, Commando ×2 |
| 6.25 % | `$073` | Garm ×2, Commando ×2 |

per draw: Garm 68.75 % / 1.3750 bodies · Commando 68.75 % / 1.0625 ·
Pipsqueak 31.25 % / 0.6250 · ProtoArmor 31.25 % / 0.3125

### Group 81 — map 263 (Shiva magicite floor)

| p | formation | contents |
|---|---|---|
| 31.25 % | `$193` | ProtoArmor ×2 |
| 31.25 % | `$074` | Garm ×2, Commando ×1 |
| 31.25 % | `$195` | Pipsqueak ×5 |
| 6.25 % | `$195` | Pipsqueak ×5 |

per draw: Pipsqueak 37.50 % / 1.8750 · ProtoArmor 31.25 % / 0.6250 ·
Garm 31.25 % / 0.6250 · Commando 31.25 % / 0.3125

### Group 104 — map 264

| p | formation | contents |
|---|---|---|
| 31.25 % | `$165` | Flan ×4 |
| 31.25 % | `$165` | Flan ×4 |
| 31.25 % | `$164` | Flan ×1 |
| 6.25 % | `$164` | Flan ×1 |

per draw: Flan **100 %** / 2.8750 bodies. A single-species pool.

### Group 105 — map 269 (save point)

| p | formation | contents |
|---|---|---|
| 31.25 % | `$077` | General ×2 |
| 31.25 % | `$078` | General ×1, Pipsqueak ×2 |
| 31.25 % | `$076` | Trapper ×3 |
| 6.25 % | `$076` | Trapper ×3 |

per draw: General 62.50 % / 0.9375 · Trapper 37.50 % / 1.1250 ·
Pipsqueak 31.25 % / 0.6250

### Group 106 — maps 271, 273, 275 (the deep facility: minecart room, esper tubes)

| p | formation | contents |
|---|---|---|
| 31.25 % | `$07c` | Gobbler ×1 |
| 31.25 % | `$168` | Rhinox ×2 |
| 31.25 % | `$169` | Gobbler ×2, Rhinox ×1 |
| 6.25 % | `$169` | Gobbler ×2, Rhinox ×1 |

per draw: Gobbler 68.75 % / 1.0625 · Rhinox 68.75 % / 1.0000.
**Two species, three maps, 100 % of the draws in the deepest third of the
dungeon.**

### Group 108 — map 240 (Vector rooftops / the Crane escape)

| p | formation | contents |
|---|---|---|
| 31.25 % | `$07a` | Chaser ×1 |
| 31.25 % | `$1a0` | Commando ×4 |
| 31.25 % | `$07b` | Chaser ×1, Pipsqueak ×3 |
| 6.25 % | `$079` | Pipsqueak ×4 |

per draw: Chaser 62.50 % / 0.6250 · Commando 31.25 % / 1.2500 ·
Pipsqueak 37.50 % / 1.1875

### The bosses

| species | id | L | HP | vanilla weak / null / absorb | authored row |
|---|---|---|---|---|---|
| Ifrit | `$109` | 21 | 3300 | ice / all but ice / **fire** | 6 · pierce (`ot6_hud.asm:1542`) |
| Shiva | `$108` | 21 | 3000 | fire / all but fire / **ice** | 6 · slash (`:1544`) |
| Number 024 | `$10a` | 24 | 4777 | **none** | 7 · slash\|pierce (`:1546`) |
| Number 128 | `$10b` | 23 | 3276 | none / — / ice | 7 · pierce (`:1549`) |
| RightBlade | `$13f` | 21 | 400 | none / — / ice | 3 · slash (`:1551`) |
| Left Blade | `$140` | 22 | 700 | none / — / ice | 3 · slash (`:1553`) |
| Crane | `$10d` | 23 | 1800 | water / — / bolt | 6 · pierce (`:1555`) |
| Crane | `$10e` | 24 | 2300 | bolt\|water / — / fire | 6 · pierce (`:1557`) |
| Guardian | `$111`/`$112` | 71/67 | 50000/60000 | — | 0 · `$00`, deliberately gauge-less |

**Every boss in the band is already explicitly authored.** Nothing below
changes them except one optional refinement (§8.3).

---

## 3. The ten trash species

| species | id | L | HP | vanilla weak | null | absorb | special-attack name |
|---|---|---|---|---|---|---|---|
| Garm | `$0cb` | 19 | 615 | bolt\|water | — | — | Program 95 |
| Commando | `$0c7` | 18 | 580 | bolt\|water | — | — | Program 65 |
| ProtoArmor | `$165` | 19 | 670 | bolt | — | — | Program 35 |
| Pipsqueak | `$041` | 18 | 250 | bolt\|water | — | — | Program 55 |
| Flan | `$047` | 19 | 255 | **fire** | poison\|wind\|pearl\|earth\|water | — | Slip Gunk |
| General | `$066` | 19 | 650 | **poison** | — | — | Bio Attack |
| Trapper | `$02d` | 19 | 555 | bolt\|water | — | — | Program 18 |
| Gobbler | `$088` | 19 | 470 | **none** | — | — | Silence |
| Rhinox | `$075` | 19 | 800 | **none** | — | **bolt** | BaneStrike |
| Chaser | `$0a0` | 19 | 1202 | bolt\|water | — | — | Program 17 |

**A body-reading gift from vanilla.** Exactly **6 of 384** species in the game
have a `Program NN` special-attack name (`src/text/monster_special_name_en.json`),
and they are exactly Garm, Commando, ProtoArmor, Pipsqueak, Trapper and
Chaser — this band's six machines. Vanilla's own data separates the band's
pool into *six things running programs* and *four things that are alive*
(an ooze, an officer, a maw, a beast). That split is the spine of §8.

Every one of these seeds **4 shields** today: level 18 and 19 both give
`2 + level/8` = 4 (`ot6_break.asm:52-60`). Both prior authoring passes found
the formula count is one chip too many and landed on 2
(`balance-metrics.md:944-972` for Mt. Kolts, `ot6_hud.asm:1489-1510` for Zozo,
where a 1200-HP HadesGigas went 4 → 2 and the break moved off the corpse).

---

## 4. What the generated floor currently says, and how it got there

| species | current class | how |
|---|---|---|
| Garm `$0cb` | SLASH | **DEFAULT** (no keyword matched) |
| Pipsqueak `$041` | SLASH | **DEFAULT** |
| Trapper `$02d` | SLASH | **DEFAULT** |
| Gobbler `$088` | SLASH | **DEFAULT** |
| Rhinox `$075` | SLASH | inferred, keyword `rhino` (`gen_break_floor.py:88`) |
| Commando `$0c7` | PIERCE | inferred, keyword `commando` (`:58`) |
| ProtoArmor `$165` | PIERCE | inferred, keyword `armor` (`:56`) |
| General `$066` | PIERCE | inferred, keyword `general` (`:59`) |
| Chaser `$0a0` | PIERCE | inferred, keyword `chaser` (`:57`) |
| Flan `$047` | BLUDGEON | inferred, keyword `flan` (`:78`) |

Raw species count for the band: **5 SLASH, 4 PIERCE, 1 BLUDGEON**, of which
**4 are defaulted** and 6 keyword-inferred. Zero are explicitly authored.

### The corrected global picture

Issue #11 quotes `break_floor_review.txt`'s headline of 285/75/24 with 265
defaulted. That count includes species that already carry an authored
`Ot6ShieldTbl` row and therefore never reach `@formula`. `Ot6ShieldTbl`
currently holds **62 rows**. Excluding them:

| | all 384 | floor-live (322) |
|---|---|---|
| SLASH | 285 | **245** |
| PIERCE | 75 | 58 |
| BLUDGEON | 24 | 19 |
| defaulted | 265 | **227** |
| keyword-inferred | 119 | 95 |

The shape of the problem is unchanged — 245 of the 322 floor-live species
(76 %) are slash, and 227 of those 245 (93 %) got there by default — but the
review dump's headline numbers overstate what the floor actually decides. Making that distinction is issue #11's first
acceptance criterion.

---

## 5. Class distribution BY ENCOUNTER FREQUENCY — the number that matters

Two aggregates over the eight encounter-bearing maps. Neither weights by
*time spent* on a map, which nobody has measured; the first weights each map
equally, the second weights each map by its per-step encounter rate.

### 5.1 Share of draws in which a class is a key (≥ 1 body weak to it)

| class | equal-map weight | rate weight |
|---|---|---|
| slash | **71.88 %** | **74.87 %** |
| pierce | 39.84 % | 37.10 % |
| bludgeon | 12.50 % | 8.51 % |
| special ¤ | 0.00 % | 0.00 % |

### 5.2 Share of monster bodies weak to a class

| class | share of bodies |
|---|---|
| slash | 63.01 % |
| pierce | 23.70 % |
| bludgeon | 13.29 % |
| special ¤ | 0.00 % |

Per-species contribution (equal-map weight), sorted by bodies per draw:

| species | bodies/draw | % of all bodies | appearance share | class |
|---|---|---|---|---|
| Pipsqueak | 0.5391 | 19.94 % | 12.43 % | SLASH (default) |
| Gobbler | 0.3984 | 14.74 % | 18.64 % | SLASH (default) |
| Rhinox | 0.3750 | 13.87 % | 18.64 % | SLASH (`rhino`) |
| Flan | 0.3594 | 13.29 % | 9.04 % | BLUDGEON |
| Commando | 0.3281 | 12.14 % | 11.86 % | PIERCE |
| Garm | 0.2500 | 9.25 % | 9.04 % | SLASH (default) |
| Trapper | 0.1406 | 5.20 % | 3.39 % | SLASH (default) |
| ProtoArmor | 0.1172 | 4.34 % | 5.65 % | PIERCE |
| General | 0.1172 | 4.34 % | 5.65 % | PIERCE |
| Chaser | 0.0781 | 2.89 % | 5.65 % | PIERCE |

### 5.3 The finding

The band-level number is worse than the global one, and it is worst exactly
where it hurts most:

- **In the deepest third of the facility (group 106, three maps), slash is the
  answer to 100 % of encounters**, because both species there landed on slash
  — one by outright default (Gobbler) and one by a keyword that fired on a
  body it read wrong (Rhinox / `rhino`).
- Those same two species are **the only two in the band with no vanilla
  elemental weakness of any kind**, so the class row is not one option among
  several: it is their *entire* break axis. Getting it wrong there costs the
  whole mechanic in that room.
- **Rhinox absorbs bolt** (`monster_prop.dat` +23 = `$04`) — the exact element
  the rest of the band teaches (§6). This is Mt. Kolts' Brawler-absorbs-poison
  situation (`ot6_hud.asm:1348-1360`) one band later and on a bigger body.
- ¤ is at 0 % across a band that `weapon-classes.md:74` explicitly earmarks as
  the class's debut ("Opera → Vector … the first ¤-weak enemies").

---

## 6. The party that walks this band, and what it can actually swing

### 6.1 Roster

At the v0.5 tail (`zozo_done`) the active roster is **Locke, Celes, Edgar,
Sabin, Cyan, Gau**, with Terra retrieved but catatonic and out of the party
(`wob-route.md:30-38`); **Setzer joins with the Blackjack** at the end of Beat
A (`wob-route.md:52`). Terra returns only in v0.7 (`wob-route.md:52`, C row).
So the band is **four chosen from seven: Locke, Celes, Edgar, Sabin, Cyan,
Gau, Setzer**, with `wob-route.md:192-193` recording Locke + Celes as
effectively fixed for the Ifrit/Shiva/024 stretch and "the factory four" as a
fixed set through Number 128 and the Cranes.

### 6.2 Physical classes each member can bring

Classes from `ot6_class.asm:10-13`; per-weapon bytes from `Ot6WeapClassTbl`
(`:46`); ability bytes from `Ot6SkillClassTbl` (`:184`); equippability from the
16-bit character mask at `item_prop_en.dat[item*30]+1` (read by
`menu/equip.asm:1592`).

| member | slash | pierce | bludgeon | special ¤ |
|---|---|---|---|---|
| Locke | swords (MithrilBlade … Falchion) | **daggers — default weapon** | Full Moon `$45`, Boomerang `$47`, Rising Sun, Sniper, Wing Edge | — |
| Celes | **swords — the whole line** | daggers | **Flail `$44`, Morning Star `$46`** | — |
| Edgar | swords; **Chain Saw `$a6`** | **spears; AutoCrossbow `$aa`, Drill `$a8`, Air Anchor `$a9`** | — | — |
| Cyan | **katanas + all 8 SwdTechs** (`ot6_class.asm:200-207`) | Imp Halberd only | — | — |
| Sabin | claws (`$53`-`$59`) | Imp Halberd only | **bare fists `$ff`; Pummel/Suplex/Bum Rush** (`:208-210`) | — |
| Gau | — | Imp Halberd only | **bare fists `$ff`** | — |
| Setzer | — | Darts `$4e`, Doom Darts | — | **Cards `$4d` — his joining weapon** (`char_prop.asm:253`) |

Two things fall straight out of that table.

**Slash is the A button of this band.** Five of the seven can swing it, it is
the default for Celes and Cyan, and the facility's own chests hand out three
more slashing swords before the deep floors: **Flame Sabre** (map 262, (3,25)),
**ThunderBlade** (map 262, (25,44)), **Blizzard** (map 263, (55,34)), and
**Break Blade** later at map 271 (`trigger/treasure_prop.dat`). Authoring a
slash weakness on common trash here is the definition of a freebie.

**Bludgeon is the one class you have to decide to bring.** It is free only if
Sabin or Gau is in the party (Blitz and bare fists cost nothing); for Locke or
Celes it costs a weapon slot and a shop trip. And the shops matter:

| town | shop | blunt / ¤ stock |
|---|---|---|
| Narshe (map 24) | 0 | **Flail, Full Moon** |
| Kohlingen (map 194) | 17 | **Flail, Full Moon** |
| Jidoor (map 204) | 20 | **Full Moon** |
| Tzen (map 309) | 29 | **Full Moon, Boomerang** |
| Albrook (map 326) | 25 | *none* |
| **Vector (map 246)** | 27 | *none* — Forged, Poison Claw, Epee, Blossom |

Vector's own weapon shop, and Albrook's (the last port before it), sell
**no blunt weapon and no ¤ weapon**. That is a genuine constraint on any
bludgeon-heavy authoring, and §10 turns it into a fixture assertion.

**Pigeonhole check.** Only Edgar and Cyan can bring neither bludgeon nor ¤.
Any party of 4 drawn from 7 therefore contains at least two members from
{Locke, Celes, Sabin, Gau, Setzer} — so **every legal party can field a
bludgeon or ¤ carrier**, and it is free whenever Sabin, Gau or Setzer is
aboard. The only gear-dependent case is a {Locke, Celes, Edgar, Cyan}-shaped
party that never bought a blunt weapon.

### 6.3 The element ring, for contrast

- **Bolt is the band's key element.** Ramuh is owned from Zozo
  (`wob-route.md:30-33`) and seven of the ten trash species carry vanilla
  bolt|water or bolt.
- **Ice is nearly dead.** Celes' natural list is Ice 1 / Cure 4 / Antdot 8 /
  Imp 13 / Scan 18 / Safe 22 / Ice 2 26 (`field/event.asm:1266-1281`) — and
  nothing in the band is ice-weak while Number 128 and both blades **absorb**
  it.
- **Fire is thin until the facility hands it over.** With Terra out, fire is
  the Flame Sabre in the first chest of map 262, or a Fire Skean. That chest
  sits upstream of the Flan room (map 264) — pleasing pedagogy, and it means
  Flan's fire weakness is reachable, but only just.
- **Poison is Edgar's Bio Blaster**, and General is the one body weak to it.
- **Nothing reaches Gobbler or Rhinox**, and Rhinox *absorbs* the band's key
  element.

---

## 7. What the distribution should be, and why

Not equal counts. The target is that a player in this band faces a real
question, and that the question has an answer their party can supply.

Three facts set the shape:

1. **Slash is free and pierce is nearly free.** Celes and Cyan swing slash by
   default; Locke swings pierce by default and Edgar can. With Locke + Celes
   effectively fixed, any row containing slash or pierce is chipped by the A
   button of a member who is already there.
2. **Bludgeon is the deliberate class**, free with Sabin/Gau and a real
   trade-off otherwise. It is also what `weapon-classes.md:75` already promises
   this stretch: *"Magitek factory: all — armored spread: bludgeon/pierce
   featured."*
3. **Vanilla already labelled six of the ten bodies as machines** (§3). A rule
   the player can guess before probing writes itself: **the machines do not
   care about your sword.**

So the proposed shape is: **bludgeon carries the band, pierce is the second
key on the imperial line, slash is retired from the machines and kept as a
boss key plus exactly one soft trash body, and ¤ debuts on one body — always
paired, never a Setzer lock.**

Slash does not disappear: **three of the band's six set-piece fights are
already slash rows** — Shiva 6·slash, RightBlade and Left Blade 3·slash each,
and Number 024 slash|pierce. Cyan and Celes have real work in this band; what
they lose is the guarantee that holding A chips every random encounter.

---

## 8. Proposed `Ot6ShieldTbl` rows

### 8.1 The ten trash rows

Format matches the existing table (`ot6_hud.asm:1273`): `.word` species,
`.byte` shields, `.byte` class mask.

| species | id | shields | class mask | one-line rationale |
|---|---|---|---|---|
| Garm | `$0cb` | 2 | `OT6_PIERCE\|OT6_BLUDG` | A magitek quadruped (`Program 95`), not a hound: pierce the joints or cave the housing. Dual because it is the commonest body at the entrance, where the band teaches its rule. |
| Commando | `$0c7` | 2 | `OT6_PIERCE` | Imperial rank keeps the imperial answer — every soldier-line row in the table is pierce or pierce+slash (`ot6_hud.asm:1433-1495`). Consistency, not novelty. |
| ProtoArmor | `$165` | 2 | `OT6_BLUDG` | A sealed suit has no seam to put a point in; you dent it. Retires pierce so the armored *machine* and the armored *man* stop having the same answer. Vanilla bolt stays as the ranged key. |
| Pipsqueak | `$041` | 2 | `OT6_PIERCE` | The swarm body (up to ×5). Pierce so Edgar's AutoCrossbow — whole enemy side, and multi-hit actions chip per hit (`weapon-classes.md:124`) — is the designed answer to a five-stack. |
| Flan | `$047` | 2 | `OT6_BLUDG` | Keep the generator's read (`gen_break_floor.py:78`, oozes): you cannot cut it. Load-bearing, because fire is its only element and Terra is gone. Pummel/Bum Rush hit the whole ×4 pack. |
| General | `$066` | 2 | `OT6_PIERCE\|OT6_BLUDG` | An officer in plate. Poison already answers him (Bio Blaster), so this row is a second key rather than the only one. |
| Trapper | `$02d` | 2 | `OT6_BLUDG` | A fixed trap mechanism (`Program 18`) — you smash a device, you do not stab it. Comes ×3, and the blunt group Blitzes hit all three. |
| Chaser | `$0a0` | 2 | `OT6_PIERCE\|OT6_BLUDG` | 1202 HP, the widest break window in the band, on the escape map where no shop trip is possible mid-sequence. Dual so a fixed escape party always holds a key. |
| Gobbler | `$088` | 2 | `OT6_SLASH\|OT6_PIERCE` | No vanilla weakness at all — this row is its *only* key. A soft maw: cut it or stick it. Deliberately the band's slash target, placed in the deepest pool so the blade has work in the room where the machines stopped caring about it. |
| Rhinox | `$075` | 2 | `OT6_BLUDG\|OT6_SPECIAL` | **The flagship.** No weakness of any kind *and* it absorbs bolt, so the answer the rest of the facility teaches would heal it. Armoured bulk with no seam → bludgeon; ¤ is the second key and the designed debut of Setzer's class (`weapon-classes.md:74`). Two keys so it is never a single-character lock. |

### 8.2 Shield counts

All ten are proposed at **2**, against a formula value of **4**. This is the
single biggest mechanical change in the pass and it follows a finding both
prior passes reached independently: the formula's count lands the break on a
corpse (`balance-metrics.md:944-972`; `ot6_hud.asm:1489-1510`, where Zozo's
1200-HP HadesGigas went 4 → 2 and its window opened for the first time).

**It is a proposal, not a measurement.** Nothing in this band has been swept.
Landing it should mint a Vector doorstep fixture and run `bal_party.lua`
`boost3` with `BAL_BUFF_SHIELDS` over 1/2/3 against groups 80, 105 and 106,
exactly as Measurements #8 and #9 did, before the counts are committed.

### 8.3 One optional boss refinement — split the Cranes

Both Cranes are 6·pierce (`ot6_hud.asm:1555,1557`). They are the band's climax
and, per `wob-route.md`, its "effective-12 dual gauge" — two simultaneous
bodies asking for the same single key. Proposed:

- `$10d` Crane — 6 · `OT6_PIERCE` (keeps vanilla water)
- `$10e` Crane — 6 · `OT6_BLUDG` (keeps vanilla bolt|water)

so the pair asks for two different keys at once, which is the only thing a
dual gauge is actually for. Both remain reachable by any legal party (§6.2)
and each keeps a distinct vanilla element. Marked optional because it touches
authored boss data, which is `bosses-wob.md`'s territory, not the floor's.

### 8.4 Resulting distribution

Raw species count for the band, before → after:

| class | current | proposed |
|---|---|---|
| slash | 5 | **1** |
| pierce | 4 | **6** |
| bludgeon | 1 | **6** |
| special ¤ | 0 | **1** |

(14 class bits across 10 species — four bodies carry two keys.)

Share of draws in which a class is a key:

| class | current (equal-map) | proposed (equal-map) | current (rate-wt) | proposed (rate-wt) |
|---|---|---|---|---|
| slash | 71.88 % | **25.78 %** | 74.87 % | **30.72 %** |
| pierce | 39.84 % | **67.19 %** | 37.10 % | **69.28 %** |
| bludgeon | 12.50 % | **78.91 %** | 8.51 % | **77.26 %** |
| special ¤ | 0.00 % | **25.78 %** | 0.00 % | **30.72 %** |

Share of bodies weak to a class (bodies count once per key they carry):

| class | current | proposed |
|---|---|---|
| slash | 63.01 % | **14.74 %** |
| pierce | 23.70 % | **63.29 %** |
| bludgeon | 13.29 % | **53.18 %** |
| special ¤ | 0.00 % | **13.87 %** |

Per-formation reading of the proposal (this is the table to argue with):

| group | p | contents | keys |
|---|---|---|---|
| 80 | 31.25 % | Garm ×2, Commando | pierce, bludgeon |
| 80 | 31.25 % | ProtoArmor, Pipsqueak ×2 | pierce, bludgeon |
| 80 | 37.50 % | Garm ×2, Commando ×2 | pierce, bludgeon |
| 81 | 31.25 % | ProtoArmor ×2 | **bludgeon only** (vanilla bolt) |
| 81 | 31.25 % | Garm ×2, Commando | pierce, bludgeon |
| 81 | 37.50 % | Pipsqueak ×5 | pierce |
| 104 | 100 % | Flan ×4 or ×1 | **bludgeon only** (vanilla fire) |
| 105 | 62.50 % | General ×2, or General + Pipsqueak ×2 | pierce, bludgeon |
| 105 | 37.50 % | Trapper ×3 | **bludgeon only** (vanilla bolt) |
| 106 | 31.25 % | Gobbler | slash, pierce |
| 106 | 31.25 % | Rhinox ×2 | **bludgeon or ¤ only — no element at all** |
| 106 | 37.50 % | Gobbler ×2, Rhinox | slash, pierce, bludgeon, ¤ |
| 108 | 62.50 % | Chaser (+ Pipsqueak ×3) | pierce, bludgeon |
| 108 | 37.50 % | Commando ×4, or Pipsqueak ×4 | pierce |

---

## 9. What the party genuinely cannot break

Under the **current** floor: nothing. The safety net works — every species has
a class, so no encounter in the band is unbreakable. The failure is quality,
not coverage.

Under the **proposal**, exactly one formation:

> **Formation `$168` — Rhinox ×2 — 31.25 % of draws on maps 271 / 273 / 275**

is unbreakable by a party that brought neither Sabin, Gau nor Setzer *and*
never bought a Flail / Full Moon / Boomerang / Morning Star. Rhinox has no
vanilla weakness and absorbs bolt, so no element substitutes, and neither
Vector's nor Albrook's weapon shop stocks a blunt weapon (§6.2).

That is a deliberate, bounded cost, and the precedent for accepting it is
Mt. Kolts, where the whole stretch's second key was a Figaro-shop purchase and
the fixture asserts the item is still carried
(`tools/tests/gen_kolts.lua:594`). If playtest says it bites, the two cheap
fixes are (a) add a Flail or Full Moon line to Vector's shop 27 — a shop-data
change, outside issue #11 — or (b) widen the Rhinox row to
`OT6_PIERCE|OT6_BLUDG|OT6_SPECIAL`, at the cost of making Locke's dagger the
answer to the band's flagship body.

Three other formations are single-key on class (ProtoArmor ×2, Flan, Trapper
×3), but each keeps a reachable vanilla element (bolt, fire, bolt), so a
bludgeon-less party still has a probe.

---

## 10. What this asks of the generator and the tests

### 10.1 Can substring matching express these rows? Not needed, and not able.

**Not needed:** every row above goes in `Ot6ShieldTbl`, which
`Ot6SeedShields` scans *before* `@formula` (`ot6_break.asm:24-38`). Authored
rows win by construction and the generator needs no change to accommodate them.

**Not able, in general:** name-substring classification cannot express
per-species intent wherever two species share a name, and **15 names in the
game cover 42 species** — including, in this very band, **both Cranes
(`$10d` and `$10e` are both named "Crane")**. Any keyword rule assigns them
one class; §8.3's split is unexpressible by the generator by construction.
The same is true of the four Ultros records (`$12c`/`$12d`/`$12e`/`$168`,
which carry four different authored rows), the three Tritochs, the three
Kefkas, the four Mag Roaders and the four Tentacles. If species-level control
is ever wanted from the tool, the keying has to move from name to species id.

### 10.2 Three concrete generator/tooling changes this survey argues for

1. **Three-way review output — explicit / inferred / defaulted.** Issue #11's
   first acceptance criterion, and this band shows why it matters *and* why
   two categories are not enough. `break_floor_review.txt` triages only
   DEFAULT rows as "the taste-review surface" (`gen_break_floor.py:202-203`).
   Rhinox — the most consequential species in the band, no weakness at all,
   absorbs the band's key element, 68.75 % of the deepest pool — is **not on
   that list**, because `rhino` matched. Inferred rows need review too.
2. **Mark authored species as AUTHORED and exclude them from the headline
   counts.** 62 of the 384 rows the review counts never reach `@formula`. The
   corrected floor-live numbers are 245/58/19 over 322 species (§4), and after
   this pass another 10 leave the floor. Issue #11 asks for fallback use to be
   "visible in generated review output"; the cheapest honest version is for the
   generator to read `Ot6ShieldTbl` and print both totals.
3. **An encounter-reachability check, not a nonzero-bytes check.** Four of the
   band's most common bodies defaulted to slash purely because their names hit
   no keyword. A test that walks `SubBattleGroup → RandBattleGroup →
   BattleMonsters` for a named map set and asserts that every formation has at
   least one class key reachable by the band's roster is the thing that would
   have caught this, and it is the acceptance criterion "tests cover
   encounter/party reachability, not only nonzero table bytes".

### 10.3 Fixture work before landing

- Mint a Vector/factory doorstep and sweep shields 1/2/3 with `bal_party.lua`
  `boost3` + `BAL_BUFF_SHIELDS` on groups 80, 105 and 106 (§8.2).
- Assert the blunt-weapon or Sabin/Gau/Setzer condition at the doorstep, in
  the shape of `gen_kolts.lua:594`.
- Check whether maps 265 / 267 / 268 actually roll their group-0 (level-5)
  encounters (§1.2).

### 10.4 One unrelated defect found in passing

`tools/tests/gen_vector_arrival.lua` boots the post-Opera anchor at world
(137, 203), steps RIGHT, and asserts it landed on **map 323**, commenting
"step RIGHT into Vector". Map 323's title index is 53 = **ALBROOK**
(`map_prop.dat[323*33]`), and the world short-entrance table confirms world
(138, 203) and (139, 203) both lead to map 323 at field (2, 17) — the exact
coordinates the fixture asserts. Vector town is maps 242 / 253 and **no world
entrance leads into it at all** (checked both the short and long entrance
tables for map 0); it is entered by event. So the anchor named
`vector_arrival` parks the party in Albrook. That matters for v0.6 beyond
naming: Albrook's weapon shop stocks no blunt and no ¤ weapon (§6.2), so a
band fixture chained off it starts one town short of any bludgeon key.

---

## 11. Status

Proposal. Nothing here is measured, and no file was modified. The rows in §8
are authoring intent with a rationale per species; the shield counts in §8.2
are a precedent-following guess that needs its own sweep; the generated floor
remains the documented provisional safety net for every band except this one
until these rows land.
