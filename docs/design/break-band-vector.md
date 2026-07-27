# Break band — Vector / Magitek Research Facility (survey + proposed rows)

Issue #11, v0.6 scope. **Survey and proposal only** — no source was touched.
`ot6_break_floor.inc`, `gen_break_floor.py` and `Ot6ShieldTbl` are all
unchanged by this document.

Everything below was decoded from the vendored data under `ff6/` on
2026-07-26. Line references are to that tree. Where a claim is an inference
rather than something read out of the source, it is labelled. Party
composition is `docs/design/bosses-wob.md`'s to state, not this document's;
§6 cites it rather than re-deriving it.

---

## 0. How the two tables interact

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
The generator work issue #11 asks for is separate, and §10 covers it.

One coupling worth restating (documented at `ot6_hud.asm:1380-1392`): an
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

### 1.1 The route and the encounter-bearing maps

Map graph and leg order are `vector-route-recon.md` §2/§4/§5; the encounter
columns are decoded here.

```
242 Vector ─► 262 ─► 263 ─(chute)─► 264 ─► 269 ─► 271 ─► 273 ─► 274
   ─► 266 (lift) ─► 272 ─► cutscene TRAIN ─► 240 ─► map 6 (Blackjack)
```

Vector town is maps 242 / 253 (title index 49). The facility is the contiguous
block 262-275, identified three ways that agree: the map titles
(`MAGITEK FACTORY` on 262, `MAGITEK RES. FACILITY` on 271), the default song
(`$47` = `SONG::DEVILS_LAB`, `ff6/include/sound/song_script.inc:80`) on every
map 262-275, and the fact that **battle groups 80, 81, 104, 105, 106 and 108
are used by no other map in the game**. Map 240 is a second copy of Vector used
for the escape.

| map | title | enable | group | rate | pool |
|---|---|---|---|---|---|
| 262 `$106` | MAGITEK FACTORY | **Y** | 80 | `$0040` | Garm, Commando, ProtoArmor, Pipsqueak |
| 263 `$107` | — | **Y** | 81 | `$0040` | ProtoArmor, Garm, Commando, Pipsqueak |
| 264 `$108` | — | **Y** | 104 | `$0040` | Flan |
| 269 `$10d` | — | **Y** | 105 | `$0070` | General, Pipsqueak, Trapper |
| 271 `$10f` | MAGITEK RES. FACILITY | **Y** | 106 | `$0070` | Gobbler, Rhinox |
| 273 `$111` | — | **Y** | 106 | `$0070` | Gobbler, Rhinox |
| 240 `$0f0` | (escape Vector) | **Y** | 108 | `$0070` | Chaser, Commando, Pipsqueak |
| 270 `$10e` | — | n | 105 | — | save-point room; carries a group, cannot draw it |
| 272 `$110` | — | n | 104 | — | minecart boarding + save point; same |
| 274 `$112` | — | n | 106 | — | esper tube room; same |
| 275 `$113` | BASEMENT 3 | Y | 106 | — | **unreachable** |

**Map 275 is unreachable and is excluded from the band.** No short or long
entrance record anywhere in the game targets it, and `load_map 275` appears
nowhere in `ff6/src/`. It carries group 106 and the battle-enable bit but
cannot be visited. The random-encounter map set is **seven maps**.

The three enable-bit-clear maps are the same shape as Measurement #8's map
95/74 finding (`balance-metrics.md:831-840`).

Set-piece rooms, from `event/npc_prop.asm` (its per-map blocks sit at a fixed
+3 offset from `map_prop`; calibrated against the weapon-shop maps, where
offset 3 lands 9 of 11 blocks on a `WEAPON SHOP`/`ARSENAL` map and every other
offset lands 0):

| map | contents | fight |
|---|---|---|
| 263 | IFRIT, KEFKA, ELEVATOR | Ifrit approach (`_cc7937` → `battle 70`, `event_main.asm:95283`) |
| 264 | IFRIT, SHIVA, MAGICITE | **the Ifrit & Shiva fight and the Shiva magicite — in the Flan room** |
| 273 | NUMBER_024 | `_cc79ed` → `battle 72` (`:95386`) |
| 274 | BIG_SWITCH, CID, KEFKA, BISMARK, CARBUNCL, MADUIN | six espers (`:95777-95782`); Celes is lost here (`:96148-96158`) |
| 240 | MAGITEK_TRAIN ×4, SAVE_POINT | escape; Setzer reunion → Blackjack → `battle 71` (Cranes) |

**One anomaly, reported as data, mechanism unverified.** Maps 265 `$109`,
267 `$10b` and 268 `$10c` are Devil's-Lab maps with the enable bit **set** and
`SubBattleGroup = 0` — group 0 is the Narshe overworld pool (Leafer `$017`,
Dark Wind `$028`, level 5). They read as cutscene rooms, so the player probably
never takes a danger-checked step on them, but that is an inference. **If they
do roll, the band draws level-5 trash.** Worth one runtime check; not authored
for here, because Leafer belongs to the deferred v0.5 pool.

---

## 2. The pools, formation by formation

Slot weights are 31.25 / 31.25 / 31.25 / 6.25 %; several groups repeat a
formation across slots 2 and 3, which is why some appearance shares are
37.5 % rather than 31.25 %.

### Group 80 — map 262 (factory entrance)

| p | formation | contents |
|---|---|---|
| 31.25 % | `$074` | Garm ×2, Commando ×1 |
| 31.25 % | `$194` | ProtoArmor ×1, Pipsqueak ×2 |
| 37.50 % | `$073` | Garm ×2, Commando ×2 |

per draw: Garm 68.75 % / 1.3750 bodies · Commando 68.75 % / 1.0625 ·
Pipsqueak 31.25 % / 0.6250 · ProtoArmor 31.25 % / 0.3125

### Group 81 — map 263

| p | formation | contents |
|---|---|---|
| 31.25 % | `$193` | ProtoArmor ×2 |
| 31.25 % | `$074` | Garm ×2, Commando ×1 |
| 37.50 % | `$195` | Pipsqueak ×5 |

per draw: Pipsqueak 37.50 % / 1.8750 · ProtoArmor 31.25 % / 0.6250 ·
Garm 31.25 % / 0.6250 · Commando 31.25 % / 0.3125

### Group 104 — map 264, the Ifrit & Shiva room

| p | formation | contents |
|---|---|---|
| 62.50 % | `$165` | Flan ×4 |
| 37.50 % | `$164` | Flan ×1 |

per draw: Flan **100 %** / 2.8750 bodies. A single-species pool, and it is the
floor the tag boss is fought on.

### Group 105 — map 269

| p | formation | contents |
|---|---|---|
| 31.25 % | `$077` | General ×2 |
| 31.25 % | `$078` | General ×1, Pipsqueak ×2 |
| 37.50 % | `$076` | Trapper ×3 |

per draw: General 62.50 % / 0.9375 · Trapper 37.50 % / 1.1250 ·
Pipsqueak 31.25 % / 0.6250

### Group 106 — maps 271 and 273, the deep facility (Number 024's floor)

| p | formation | contents |
|---|---|---|
| 31.25 % | `$07c` | Gobbler ×1 |
| 31.25 % | `$168` | Rhinox ×2 |
| 37.50 % | `$169` | Gobbler ×2, Rhinox ×1 |

per draw: Gobbler 68.75 % / 1.0625 · Rhinox 68.75 % / 1.0000.
Two species, two maps, **100 % of the draws in the deepest third of the
dungeon.**

### Group 108 — map 240, the escape

| p | formation | contents |
|---|---|---|
| 31.25 % | `$07a` | Chaser ×1 |
| 31.25 % | `$1a0` | Commando ×4 |
| 31.25 % | `$07b` | Chaser ×1, Pipsqueak ×3 |
| 6.25 % | `$079` | Pipsqueak ×4 |

per draw: Chaser 62.50 % / 0.6250 · Commando 31.25 % / 1.2500 ·
Pipsqueak 37.50 % / 1.1875

### The minecart — six forced fights, no draws

`cutscene TRAIN` (`event_main.asm:96580`) runs a 52-item script in
`world/train_script.asm`; items 3 and 14 issue `battle 41`, items 9, 24 and 31
issue `battle 144`, and item 36 issues `battle 73`
(`train_script.asm:829/864/899`, each writing `$0011E0` from
`EventBattleGroup` directly — which is why `battle 73` appears nowhere in the
event disassembly).

| fight | formations | contents |
|---|---|---|
| battle 41 ×2 | `$06f` / `$075` | Mag Roader `$006` ×1 · or `$006` + `$0af` |
| battle 144 ×3 | `$196` / `$197` | Mag Roader `$006` ×2 · or `$0af` ×4 |
| battle 73 | `$1ba` | Number 128 `$10b`, Left Blade `$140`, RightBlade `$13f` |

**Neither Mag Roader appears in any random battle group anywhere in the game** —
`$006` lives only in formations `$06f`/`$075`/`$196` and `$0af` only in
`$075`/`$197`, none of which any `RandBattleGroup` slot points at. Authoring
rows for them touches this band and nothing else.

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
| Guardian | `$111`/`$112` | 71/67 | 50000/60000 | — | 0 · `$00`, gauge-less |

**Every boss row in the band is already authored and reachable by the party
that fights it** (§6.3); this pass changes none of them. The one outstanding
boss item is elemental, not class: `bosses-wob.md` §15 specifies **bolt + water
on Number 128's body and bolt on both blades**, and vanilla gives all three no
weakness at all (`monster_prop.dat` +25 = `$00`). Those are `Ot6ElemAddTbl`
rows and they are not written yet — the same M6 data-entry gap `wob-route.md`
records for AtmaWeapon.

---

## 3. The species

### 3.1 The ten random-encounter bodies

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
Chaser — this band's six machines. Vanilla's own data splits the pool into
*six things running programs* and *four things that are alive* (an ooze, an
officer, a maw, a beast). That split is the spine of §8, and it is the rule the
player can guess before probing: **the machines do not care about your sword.**

### 3.2 The two minecart bodies

| species | id | L | HP | vanilla weak | absorb | special |
|---|---|---|---|---|---|---|
| Mag Roader | `$006` | 19 | 420 | **fire** | **ice** | Wheel |
| Mag Roader | `$0af` | 18 | 250 | **ice** | — | Rush |

These two carry the best elemental puzzle in the band, and it is vanilla's own:

- **Their elements are opposed and one is a trap.** `$006` is weak to fire and
  **absorbs ice**; `$0af` is weak to ice. Formation `$075` puts them in the
  same fight, so the wrong splash heals half the screen.
- **The facility hands you both keys on the way in.** Ifrit's magicite grants
  Fire / Fire 2 / Drain and Shiva's grants Ice / Ice 2 / Rasp / Osmose / Cure
  (`menu/genju_prop.asm:86,:89`), and under M5 an equipped esper *grants* its
  spells rather than teaching them over time — the learn rates are all zero and
  `Ot6EsperSpellKnown` resolves the ids as known while the esper is worn
  (`genju_prop.asm:58-66`). So Ifrit answers `$006` and Shiva answers `$0af`
  the moment they are equipped, and the chests add Flame Sabre (map 262,
  (3,25)) and Blizzard (map 263, (55,34)) for anyone who would rather swing it.
- **The current floor flattens all of it**: both species default to slash, and
  both elemental keys arrive on slashing swords, so "hold a sword" answers the
  class axis and the element axis at once.

### 3.3 Shield counts as they stand

Every species above seeds **4 shields**: levels 18 and 19 both give
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
| Mag Roader `$006` | SLASH | **DEFAULT** |
| Mag Roader `$0af` | SLASH | **DEFAULT** |
| Rhinox `$075` | SLASH | inferred, keyword `rhino` (`gen_break_floor.py:88`) |
| Commando `$0c7` | PIERCE | inferred, keyword `commando` (`:58`) |
| ProtoArmor `$165` | PIERCE | inferred, keyword `armor` (`:56`) |
| General `$066` | PIERCE | inferred, keyword `general` (`:59`) |
| Chaser `$0a0` | PIERCE | inferred, keyword `chaser` (`:57`) |
| Flan `$047` | BLUDGEON | inferred, keyword `flan` (`:78`) |

Raw species count for the band: **7 SLASH, 4 PIERCE, 1 BLUDGEON**, of which
**6 are defaulted** and 6 keyword-inferred. Zero are explicitly authored.

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

245 of the 322 floor-live species (76 %) are slash, and 227 of those 245 (93 %)
got there by default. Making the explicit / inferred / defaulted distinction
visible is issue #11's first acceptance criterion.

---

## 5. Class distribution BY ENCOUNTER FREQUENCY

Over the seven encounter-bearing maps. Neither aggregate weights by *time
spent* on a map, which nobody has measured; the first weights each map equally,
the second by per-step encounter rate.

### 5.1 Share of draws in which a class is a key (≥ 1 body weak to it)

| class | equal-map weight | rate weight |
|---|---|---|
| slash | **67.86 %** | **70.47 %** |
| pierce | 45.54 % | 43.59 % |
| bludgeon | 14.29 % | 10.00 % |
| special ¤ | 0.00 % | 0.00 % |

### 5.2 Share of monster bodies weak to a class

| class | share of bodies |
|---|---|
| slash | 59.11 % |
| pierce | 26.20 % |
| bludgeon | 14.70 % |
| special ¤ | 0.00 % |

Per-species contribution (equal-map weight), sorted by bodies per draw:

| species | bodies/draw | % of all bodies | appearance share | class |
|---|---|---|---|---|
| Pipsqueak | 0.6161 | 22.04 % | 14.19 % | SLASH (default) |
| Flan | 0.4107 | 14.70 % | 10.32 % | BLUDGEON |
| Commando | 0.3750 | 13.42 % | 13.55 % | PIERCE |
| Gobbler | 0.3036 | 10.86 % | 14.19 % | SLASH (default) |
| Garm | 0.2857 | 10.22 % | 10.32 % | SLASH (default) |
| Rhinox | 0.2857 | 10.22 % | 14.19 % | SLASH (`rhino`) |
| Trapper | 0.1607 | 5.75 % | 3.87 % | SLASH (default) |
| ProtoArmor | 0.1339 | 4.79 % | 6.45 % | PIERCE |
| General | 0.1339 | 4.79 % | 6.45 % | PIERCE |
| Chaser | 0.0893 | 3.19 % | 6.45 % | PIERCE |

Plus, off the draw table entirely: **five forced Mag Roader fights, both
species defaulted to slash.**

### 5.3 The finding

- **In the deep facility (group 106, maps 271 and 273) slash answers 100 % of
  encounters**, because both species there landed on slash — one by outright
  default (Gobbler) and one by a keyword that fired on the wrong body
  (Rhinox / `rhino`).
- Those two are **the only random-pool species in the band with no vanilla
  elemental weakness at all**, so the class row is not one option among
  several: it is their entire break axis. Getting it wrong there costs the
  whole mechanic in that room.
- **Rhinox absorbs bolt** (`monster_prop.dat` +23 = `$04`) — the element the
  rest of the band teaches. This is Mt. Kolts' Brawler-absorbs-poison case
  (`ot6_hud.asm:1348-1360`) one band later, on a bigger body.
- **The minecart is the purest form of the problem** (§3.2): a genuinely good
  vanilla puzzle whose two keys are both slashing swords, sitting on two
  species that both defaulted to slash.
- ¤ is at 0 %, and §6 explains why it should stay there for this band.

---

## 6. The party that walks this band

### 6.1 Composition

`bosses-wob.md` is the authority here.

| stretch | party | source |
|---|---|---|
| Facility exploration, Ifrit & Shiva, Number 024 | **four** — Locke, Celes + two, player-chosen | `bosses-wob.md` §13, §14 |
| Minecart, Mag Roaders, Number 128 | **three** — Celes is lost partway through the facility | `bosses-wob.md` §15 |
| Left & Right Cranes | **three** — the same set; Setzer is flying the getaway | `bosses-wob.md` §16 |

Terra is available but **not active** until the tail of the beat
(`wob-route.md`), so no fight in this band may assume her, and Setzer is flying
the airship through the escape, so no fight may assume him either.

The exact roster is runtime state, and `bosses-wob.md` §15 says plainly it is
to be measured at the fixture rather than read out of the event dump. The one
mechanism worth recording, because it is what makes an event-dump reading go
wrong: **`party_chars` does not change party membership.** Event command `$3c`
(`field/event.asm:596-622`) writes only the four character-object pointers at
`$07fb`-`$0801` — the on-map sprite train. Membership is `char_party`, command
`$3f` (`field/event.asm:563-585`), which writes `$1850,y`. In the facility
chain only Celes gets a `char_party … , 0`; a cutscene that walks one sprite is
not a party of one.

So the free picks come from **Edgar, Sabin, Cyan and Gau**, and the fixed core
is Locke + Celes until the tube room.

### 6.2 What each class costs the player to field

Classes from `ot6_class.asm:10-13`; weapon bytes from `Ot6WeapClassTbl`
(`:46`); ability bytes from `Ot6SkillClassTbl` (`:184-196`); equippability from
the 16-bit character mask at `item_prop_en.dat[item*30]+1`
(`menu/equip.asm:1592`).

| class | who brings it | cost |
|---|---|---|
| **slash** | Celes' whole sword line; Cyan's katanas **and all eight SwdTechs** (`:185-192`); Sabin's claws `$53`-`$59`; Edgar's Chain Saw `$a6`; Locke's swords | **free** — five of the six candidates, and the A button for two of them |
| **pierce** | Locke's daggers (his joining weapon); Edgar's spears plus AutoCrossbow `$aa`, Drill `$a8`, Air Anchor `$a9`; Celes' daggers | **free** — the A button for Locke |
| **bludgeon** | **Sabin: bare fists `$ff` and Pummel / Suplex / Bum Rush** (`:193-195`), which bludgeon whatever is on his hands; **Gau: bare fists**; else Locke's Full Moon `$45` / Boomerang `$47` / Rising Sun / Sniper / Wing Edge, or Celes' Flail `$44` / Morning Star `$46` | **free if one of the two open slots is Sabin or Gau**; otherwise a weapon slot plus a shop trip |
| **special ¤** | Setzer's Cards `$4d` only | **not assumable** — Setzer flies the getaway |

Blunt weapons are sold at Narshe (shop 0: Flail, Full Moon), Kohlingen
(shop 17: Flail, Full Moon), Jidoor (shop 20: Full Moon) and Tzen (shop 29:
Full Moon, Boomerang). Vector's own weapon shop (27) and Albrook's (25) stock
none — but that only matters to a party that brought neither Sabin nor Gau and
wants bludgeon anyway.

**Bludgeon is therefore the band's one deliberate class, and it is properly
reachable**: free for the cost of a party pick, or buyable for the cost of a
weapon slot. That is exactly the shape `weapon-classes.md:75` already promises
this stretch — *"Magitek factory: all — armored spread: bludgeon/pierce
featured."*

**¤ has no place in this band.** Setzer is its only wielder and he is not in
the fights that close it, so a ¤ row would be a composition lock on the one
character the climax excludes. `weapon-classes.md:74` earmarks Opera → Vector
for "the first ¤-weak enemies"; on this beat's roster that has to wait.

### 6.3 The element ring

- **Bolt** — Ramuh, owned from Zozo (`wob-route.md:30-33`), grants Bolt and
  Rasp on equip (`genju_prop.asm:83`). Seven of the ten random-pool species
  carry vanilla bolt|water or bolt.
- **Fire and ice** — Ifrit and Shiva magicite, awarded inside the facility
  (`genju_prop.asm:86,:89`; granted on equip, §3.2). Fire also comes on the
  Flame Sabre in map 262's first chest.
- **Poison** — Edgar's Bio Blaster, if Edgar is one of the two picks. General
  is the one body weak to it.
- **Nothing reaches Gobbler or Rhinox**, and Rhinox *absorbs* bolt.

The bosses come out clean on both axes, which is worth stating: Celes' natural
Ice (`field/event.asm:1266`) answers Ifrit — who absorbs fire, so the Flame
Sabre *heals* him, the intended absorb lesson — the Flame Sabre answers Shiva,
and Locke and Celes hold the pierce and slash their rows ask for. Number 128's
pierce and the blades' slash are both covered by any three-character party
containing Locke plus one of Edgar, Cyan or Sabin.

---

## 7. What the distribution should be

Three facts set the shape.

1. **Slash is the A button and pierce is nearly free.** Five of the six
   candidates swing slash, it is the default for Celes and Cyan, and the
   facility's own chests hand out four more swords (Flame Sabre, ThunderBlade,
   Blizzard, Break Blade). Pierce is Locke's default line and Edgar's whole
   Tools menu. Authoring either onto common trash is a freebie.
2. **Bludgeon is the deliberate class and it is genuinely reachable** (§6.2) —
   a party pick or a shop trip, never nothing.
3. **Vanilla already labelled six of the ten bodies as machines** (§3.1), so
   the rule the player guesses before probing writes itself.

So: **bludgeon carries the band, pierce is the second key on the imperial line,
slash comes off the machines entirely, and ¤ sits this beat out.**

Slash does not disappear — **three of the band's six set-pieces are already
slash rows**: Shiva 6·slash, RightBlade and Left Blade 3·slash each, and
Number 024 slash|pierce. Cyan's Quadra Slam (four hits, and multi-hit actions
chip per hit — `weapon-classes.md:124`) and Celes' sword have real work in this
band. What they lose is the guarantee that holding A chips every random
encounter.

The measurable target is not an even four-way split. It is: *every encounter
chippable by some buildable party* (`wob-route.md:187`), *no encounter
chippable only by a class no party can field*, and *slash no longer the
automatic answer on the common bodies*.

---

## 8. Proposed `Ot6ShieldTbl` rows

Format matches the existing table (`ot6_hud.asm:1273`): `.word` species,
`.byte` shields, `.byte` class mask.

### 8.1 The rows

| species | id | shields | class mask | rationale |
|---|---|---|---|---|
| Garm | `$0cb` | 2 | `OT6_PIERCE\|OT6_BLUDG` | A magitek quadruped (`Program 95`), not a hound: pierce the joints or cave the housing. The commonest body at the entrance, where the band teaches its rule, so it teaches both halves of it. |
| Commando | `$0c7` | 2 | `OT6_PIERCE` | Imperial rank keeps the imperial answer — templar `$0002` and officer `$0175` are both pierce (`ot6_hud.asm:1433-1487`). Consistency, not novelty. |
| ProtoArmor | `$165` | 2 | `OT6_BLUDG` | A sealed suit has no seam to put a point in; you dent it. Retires pierce so the armored *machine* and the armored *man* stop having the same answer. Vanilla bolt stays as the ranged key. |
| Pipsqueak | `$041` | 2 | `OT6_PIERCE` | The swarm body, up to ×5 and 22 % of all bodies in the band. Pierce so Edgar's AutoCrossbow — whole enemy side, chipping per hit — is the designed answer to a five-stack. |
| Flan | `$047` | 2 | `OT6_BLUDG` | Keep the generator's read (`gen_break_floor.py:78`): you cannot cut an ooze. Its element is fire, which the Flame Sabre two maps upstream and Ifrit's magicite both supply — and this pool is the floor Ifrit & Shiva are fought on, so the player will be standing in it. |
| General | `$066` | 2 | `OT6_PIERCE\|OT6_BLUDG` | An officer in plate. Vanilla poison already answers him **if** Edgar was picked; the class row is what makes him breakable when he wasn't. |
| Trapper | `$02d` | 2 | `OT6_BLUDG` | A fixed trap mechanism (`Program 18`) — you smash a device, you do not stab it. Comes ×3, and vanilla bolt\|water backs it up. |
| Chaser | `$0a0` | 2 | `OT6_PIERCE\|OT6_BLUDG` | 1202 HP, the widest break window in the band, on the escape map where no shop trip is possible mid-sequence. Two keys so whatever three walked out of the tube room, they hold one. |
| Gobbler | `$088` | 2 | `OT6_SLASH\|OT6_PIERCE` | No vanilla weakness at all, so this row is its only key. The one soft body in a dungeon of machines: cut it or stick it. Deliberately the band's slash target, placed in the deepest pool so the blade has work in the room where the machines have stopped caring about it. |
| Rhinox | `$075` | 2 | `OT6_BLUDG` | **The flagship.** No weakness of any kind *and* it absorbs bolt, so the answer the rest of the facility teaches would heal it. Armoured bulk with no seam → bludgeon, and bludgeon alone: this is the one body in the band that asks the player to have brought a blunt instrument, and it is the reason to bring Sabin. |
| Mag Roader | `$006` | 2 | `OT6_BLUDG` | A thing on wheels: you smash the wheel. Its vanilla fire weakness (Ifrit's magicite, or the Flame Sabre) stays the reward for reading the fight, and the ice trap stays a trap. |
| Mag Roader | `$0af` | 2 | `OT6_BLUDG` | Same creature, same class — the *element* is what distinguishes the pair, and flattening that onto the class axis would waste the best puzzle in the band. Shiva's magicite answers this one; Ifrit's answers its sibling. |

### 8.2 Shield counts

All twelve are proposed at **2**, against a formula value of 4, following the
finding both prior passes reached independently: the formula's count lands the
break on a corpse (`balance-metrics.md:944-972`; `ot6_hud.asm:1489-1510`).

**Unmeasured.** Landing this should mint a Vector doorstep fixture and run
`bal_party.lua` `boost3` with `BAL_BUFF_SHIELDS` over 1/2/3 against groups 80,
104, 105 and 106 with a four-character party, and against group 108 and the
minecart formations with three — exactly as Measurements #8 and #9 did. The
three-character arm matters on its own: less damage per round means the same
shield count breaks later.

### 8.3 Resulting distribution

Species count over the twelve authored bodies:

| class | current floor | proposed |
|---|---|---|
| slash | 7 | **1** |
| pierce | 4 | **6** |
| bludgeon | 1 | **9** |
| special ¤ | 0 | **0** |

Share of draws in which a class is a key, over the seven random-pool maps:

| class | current | proposed | current (rate-wt) | proposed (rate-wt) |
|---|---|---|---|---|
| slash | 67.86 % | **19.64 %** | 70.47 % | **24.06 %** |
| pierce | 45.54 % | **66.96 %** | 43.59 % | **69.38 %** |
| bludgeon | 14.29 % | **80.36 %** | 10.00 % | **78.75 %** |

Share of bodies weak to a class: slash 59.11 % → **10.86 %**, pierce 26.20 % →
**64.54 %**, bludgeon 14.70 % → **53.67 %**.

Per-formation reading — the table to argue with:

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
| 105 | 37.50 % | Trapper ×3 | **bludgeon only** (vanilla bolt\|water) |
| 106 | 31.25 % | Gobbler | slash, pierce |
| 106 | 31.25 % | Rhinox ×2 | **bludgeon only — and no element at all** |
| 106 | 37.50 % | Gobbler ×2, Rhinox | slash, pierce, bludgeon |
| 108 | 62.50 % | Chaser (+ Pipsqueak ×3) | pierce, bludgeon |
| 108 | 37.50 % | Commando ×4, or Pipsqueak ×4 | pierce |
| minecart | 5 fights | Mag Roader `$006` and/or `$0af` | **bludgeon only** (vanilla fire / ice, both granted by the facility's own magicite) |

---

## 9. Reachability, and what the party cannot break

Under the **current** floor, nothing in the band is unbreakable — the generated
safety net works. The failure is quality, not coverage: in the deepest third of
the facility the answer to 100 % of encounters is "hold A with a sword", and
the dungeon hands you four swords.

Under the proposal, **every encounter is chippable by some buildable party**,
and the honest costs are:

- **33.04 % of draws are bludgeon-only on the class axis**, plus all five
  minecart fights. Every one of them except the Rhinox pair keeps a reachable
  vanilla element — ProtoArmor and Trapper bolt (Ramuh, owned since Zozo), Flan
  fire (Ifrit, or the Flame Sabre chest), the Mag Roaders fire and ice (Ifrit
  and Shiva, awarded upstream of the ride). A party with no blunt weapon still
  has a probe in all of them.
- **8.93 % of draws — formation `$168`, Rhinox ×2, 31.25 % of the draws on the
  two deepest maps — can be chipped by nothing but a blunt instrument.** Rhinox
  has no vanilla weakness and absorbs bolt, so no element substitutes. This is
  the band's one hard demand, and it is deliberate: it is what makes bringing
  Sabin, or buying a Flail before you go, a decision with a consequence. Sabin's
  Blitz costs nothing to bring and hits it; so do Gau's fists; so does a Full
  Moon on Locke.
- **General `$066` loses its vanilla poison key if Edgar is not picked** — the
  Bio Blaster is his Tool. Its `PIERCE|BLUDG` row is what covers that party.

**No shop change is needed.** Vector's shop 27 stocks no blunt weapon, but with
a four-character party that costs nothing: Sabin and Gau bring bludgeon for
free, and Locke and Celes can buy it in four towns before the walk.

---

## 10. What this asks of the generator and the tests

### 10.1 Can substring matching express these rows? Not needed, and not able.

**Not needed:** every row above goes in `Ot6ShieldTbl`, which `Ot6SeedShields`
scans *before* `@formula` (`ot6_break.asm:24-38`). Authored rows win by
construction; the generator needs no change to accommodate them.

**Not able, in general**, and this band supplies two proofs. Name-substring
classification cannot express per-species intent wherever two species share a
name, and **15 names in the game cover 42 species**:

- **Both minecart bodies are named "Mag Roader"** (`$006`, `$0af`), and they are
  *opposed*: one absorbs the element the other is weak to. A name-keyed rule
  must give them the same class. Here that happens to be what the design wants
  — but it is a coincidence, not a capability, and the tool could not have
  chosen otherwise.
- **Both Cranes are named "Crane"** (`$10d`, `$10e`), and they already carry
  authored rows over different vanilla element profiles.

The same holds for the four Ultros records (`$12c`/`$12d`/`$12e`/`$168`, which
carry four different authored rows), the three Tritochs, the three Kefkas and
the four Tentacles. If species-level control is ever wanted from the tool, the
keying has to move from name to species id.

### 10.2 Three generator/tooling changes this survey argues for

1. **Three-way review output — explicit / inferred / defaulted.** Issue #11's
   first acceptance criterion, and this band shows why two categories are not
   enough. `break_floor_review.txt` triages only DEFAULT rows as "the
   taste-review surface" (`gen_break_floor.py:202-203`). Rhinox — no weakness at
   all, absorbs the band's key element, 68.75 % of the deep pool — is **not on
   that list**, because `rhino` matched. Inferred rows need review too.
2. **Mark authored species as AUTHORED and exclude them from the headline
   counts.** 62 of the 384 rows the review counts never reach `@formula`; the
   corrected floor-live numbers are 245/58/19 over 322 species (§4), and after
   this pass another 12 leave the floor.
3. **An encounter-and-party reachability check.** The floor's failure here was
   invisible to every existing test: the bytes are nonzero, every species has a
   class, and nothing measures whether that class is the *interesting* one or
   whether the party can field it. The check that would catch it: walk
   `SubBattleGroup → RandBattleGroup → BattleMonsters` for a named map set
   **and** the forced-battle lists (`EventBattleGroup`, plus the train script's
   `$e0`/`$e1`/`$e2` items — the minecart is invisible to any event-script
   scan), take a declared party and their equippable class sets, and assert
   every formation has at least one class key some member can bring. That is
   the concrete form of "tests cover encounter/party reachability, not only
   nonzero table bytes".

### 10.3 Fixture assertions, on the `gen_kolts.lua:594` pattern

Inventory is ids at `$1869 + i` and counts at `$1969 + i` (the helper at
`gen_kolts.lua:588-593`). Equipped weapon is `$161f + char*37`.

**At the Vector doorstep**, before the on-foot world walk into town:

- Assert a bludgeon key exists: Sabin or Gau in the active party (their fists
  and Blitz need nothing), **or** `invCount(0x44) + invCount(0x46) ≥ 1`
  (Flail / Morning Star — Celes) **or** `invCount(0x45) + invCount(0x47) +
  invCount(0x48) + invCount(0x4b) + invCount(0x4c) ≥ 1` (the boomerang family —
  Locke). Direct analogue of "BioBlaster still carried (the poison key)". This
  is the assertion the Rhinox row depends on.
- Assert Ramuh is owned and equippable — three bludgeon-only rows use bolt as
  their fallback probe.
- Assert the active party is four with Locke and Celes among them, so the
  fixture cannot drift off `bosses-wob.md` §13's roster.

**At the Ifrit & Shiva doorstep** (map 264, which is also the Flan pool):
assert Flame Sabre `$0d` is carried or equipped. It is Shiva's element key and
Flan's, and it is a chest two maps back.

**At the minecart boarding point** (map 272's save point at (3,55),
`event_trigger.asm:1211`, the last controllable state before the ride): assert
the party is three, and assert **Ifrit and Shiva magicite are owned** — they
are the five Mag Roader fights' elemental answers and the facility awards both
upstream.

**At the Crane doorstep** (map 240, one step from (52,39)/(52,40)/(52,41)):
assert the party is the three that boarded, since `bosses-wob.md` §16's roster
is the thing most likely to drift.

---

## 11. Status

Proposal. Nothing here is measured and no file was modified.

- The shield counts in §8.2 are a precedent-following guess and need their own
  sweep, with a separate three-character arm.
- `bosses-wob.md` §15's element adds for Number 128 and its blades (bolt|water
  / bolt) are not in `Ot6ElemAddTbl` and remain outstanding M6 data entry.
- Whether maps 265 / 267 / 268 actually roll their group-0 encounters (§1.1)
  wants one runtime check.
- The generated floor remains the documented provisional safety net for every
  band except this one until these rows land.
