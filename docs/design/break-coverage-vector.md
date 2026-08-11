# Break coverage — Vector / Magitek Research Facility (survey + authored rows)

Everything below is decoded from the vendored data under `ff6/`. Where a claim
is an inference rather than something read out of the source, it is labelled.
Party composition is stated in `docs/design/bosses-wob.md`; §6 cites it rather
than re-deriving it.
`tools/tests/battle_breakvector.lua` recomputes the key shares from the shipped
ROM on every `make test`.

---

## 0. How the two tables interact

`Ot6SeedShields` scans the authored table first and only falls through to
the generated floor on a miss:

- `ff6/src/battle/ot6_break.asm:24-38` — linear scan of `Ot6ShieldTbl`
  (4-byte records: `.word` species, `.byte` shields, `.byte` class mask),
  `$ffff`-terminated. A hit stores the authored class mask into
  `OT6_BP_CLASS,y` and the authored shield count.
- `ff6/src/battle/ot6_break.asm:39-51` — `@formula`: species-indexed
  `OT6_FLOOR_CLASS[species]` (the generated floor) plus `2 + level/8` capped
  at 6.

The table itself lives at `ff6/src/battle/ot6_hud.asm:1273`. Authoring an
area means adding `Ot6ShieldTbl` rows; it needs no generator change. The
separate generator work is in §10.

One coupling, documented at `ot6_hud.asm:1380-1392`: an `Ot6ShieldTbl` row also
exempts its species from `Ot6HpScale` (`ot6_break.asm:466-476`). That is inert
today, because every entry of `Ot6HpMulTbl` ships `$10` = 1×
(`ot6_break.asm:568-575`). It is the reason overworld species that need only a
weakness go on `Ot6ElemAddTbl` instead. Class weaknesses can be expressed
nowhere else, so the rows below accept that trade.

---

## 1. The area, decoded from the tables

Decode chain:

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

Map graph and segment order come from `vector-route.md`; the encounter columns
are decoded here.

```
242 Vector ─► 262 ─► 263 ─(chute)─► 264 ─► 269 ─► 271 ─► 273 ─► 274
   ─► 266 (lift) ─► 272 ─► cutscene TRAIN ─► 240 ─► map 6 (Blackjack)
```

Vector town is maps 242 / 253 (title index 49). The facility is the contiguous
block 262-275, identified three ways that agree: the map titles
(`MAGITEK FACTORY` on 262, `MAGITEK RES. FACILITY` on 271), the default song
(`$47` = `SONG::DEVILS_LAB`, `ff6/include/sound/song_script.inc:80`) on every
map 262-275, and the fact that battle groups 80, 81, 104, 105, 106 and 108
are used by no other map in the game. Map 240 is a second copy of Vector used
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

Map 275 is unreachable and is excluded from the area. No short or long
entrance record anywhere in the game targets it, and `load_map 275` appears
nowhere in `ff6/src/`. It carries group 106 and the battle-enable bit but
cannot be visited. The random-encounter map set is seven maps.

The three enable-bit-clear maps carry a group they cannot draw, the same case
as maps 95 and 74 elsewhere in the game.

Set-piece rooms, from `event/npc_prop.asm` (its per-map blocks sit at a fixed
+3 offset from `map_prop`; calibrated against the weapon-shop maps, where
offset 3 lands 9 of 11 blocks on a `WEAPON SHOP`/`ARSENAL` map and every other
offset lands 0):

| map | contents | fight |
|---|---|---|
| 263 | IFRIT, KEFKA, ELEVATOR | Ifrit approach (`_cc7937` → `battle 70`, `event_main.asm:95283`) |
| 264 | IFRIT, SHIVA, MAGICITE | the Ifrit & Shiva fight and the Shiva magicite, in the Flan room |
| 273 | NUMBER_024 | `_cc79ed` → `battle 72` (`:95386`) |
| 274 | BIG_SWITCH, CID, KEFKA, BISMARK, CARBUNCL, MADUIN | six espers (`:95777-95782`); Celes is lost here (`:96148-96158`) |
| 240 | MAGITEK_TRAIN ×4, SAVE_POINT | escape; Setzer reunion → Blackjack → `battle 71` (Cranes) |

One anomaly, reported as data; the mechanism is unverified. Maps 265 `$109`,
267 `$10b` and 268 `$10c` are Devil's-Lab maps with the enable bit set and
`SubBattleGroup = 0`, and group 0 is the Narshe overworld pool (Leafer `$017`,
Dark Wind `$028`, level 5). They read as cutscene rooms, so the player probably
never takes a danger-checked step on them, but that is an inference. If they
do roll, the area draws level-5 trash. This needs one runtime check. No rows
are authored for them here, because Leafer belongs to the deferred v0.5 pool.

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

per draw: Flan 100 % / 2.8750 bodies. A single-species pool, and it is the
room the tag boss is fought in.

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
These two species are 100 % of the draws on the two maps of the deepest third
of the dungeon.

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
`EventBattleGroup` directly, which is why `battle 73` appears nowhere in the
event disassembly).

| fight | formations | contents |
|---|---|---|
| battle 41 ×2 | `$06f` / `$075` | Mag Roader `$006` ×1 · or `$006` + `$0af` |
| battle 144 ×3 | `$196` / `$197` | Mag Roader `$006` ×2 · or `$0af` ×4 |
| battle 73 | `$1ba` | Number 128 `$10b`, Left Blade `$140`, RightBlade `$13f` |

Neither Mag Roader appears in any random battle group anywhere in the game:
`$006` appears only in formations `$06f`/`$075`/`$196` and `$0af` only in
`$075`/`$197`, and no `RandBattleGroup` slot points at any of those. Authoring
rows for them affects this area only.

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

Every boss row in the area is authored and reachable by the party that
fights it (§6.3). The elements on Number 128 are `Ot6ElemAddTbl` rows rather
than vanilla bits: `bosses-wob.md` §15 specifies bolt + water on the body
and bolt on both blades, and vanilla gives all three no weakness at all
(`monster_prop.dat` +25 = `$00`). All three parts absorb ice, which is
neither added bit, so nothing is fed.

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

Vanilla's own data marks the machines. Exactly 6 of 384 species in the game
have a `Program NN` special-attack name (`src/text/monster_special_name_en.json`),
and they are Garm, Commando, ProtoArmor, Pipsqueak, Trapper and Chaser, this
area's six machines. The split is six bodies running programs and four that are
alive (an ooze, an officer, a maw, a beast). §8 is built on that split, and it
gives the player a rule to guess before probing: swords are not the answer on
the machines.

### 3.2 The two minecart bodies

| species | id | L | HP | vanilla weak | absorb | special |
|---|---|---|---|---|---|---|
| Mag Roader | `$006` | 19 | 420 | **fire** | **ice** | Wheel |
| Mag Roader | `$0af` | 18 | 250 | **ice** | — | Rush |

These two carry an elemental puzzle that comes from vanilla data:

- Their elements are opposed and one of them is a trap. `$006` is weak to fire
  and absorbs ice; `$0af` is weak to ice. Formation `$075` puts them in the
  same fight, so an ice splash heals `$006` while chipping `$0af`.
- The facility supplies both keys before the ride. Ifrit's magicite grants
  Fire / Fire 2 / Drain and Shiva's grants Ice / Ice 2 / Rasp / Osmose / Cure
  (`menu/genju_prop.asm:86,:89`), and under M5 an equipped esper grants its
  spells rather than teaching them over time: the learn rates are all zero and
  `Ot6EsperSpellKnown` resolves the ids as known while the esper is worn
  (`genju_prop.asm:58-66`). Ifrit answers `$006` and Shiva answers `$0af`
  as soon as they are equipped, and the chests add Flame Sabre (map 262,
  (3,25)) and Blizzard (map 263, (55,34)) as weapon-borne alternatives.
- The generated floor removes the distinction: both species default to slash,
  and both elemental keys arrive on slashing swords, so one sword answers
  the class axis and the element axis at once.

### 3.3 Shield counts as they stand

Every species above seeds 4 shields under the formula: levels 18 and 19
both give `2 + level/8` = 4 (`ot6_break.asm:52-60`). The formula count is one
chip too many, because the break then lands on an already-dead body. The
authored count for trash bodies is 2 (`ot6_hud.asm:1489-1510` for the Zozo
rows, where a 1200-HP HadesGigas sits at 2 and the break lands penultimate).

---

## 4. What the generated floor says, and how it gets there

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

Raw species count for the area: 7 SLASH, 4 PIERCE, 1 BLUDGEON, of which
6 are defaulted and 6 keyword-inferred. Zero are explicitly authored.

### The global picture

`break_floor_review.txt`'s headline count of 285/75/24 with 265 defaulted is
over all 384 species, including those that carry an authored `Ot6ShieldTbl`
row and therefore never reach `@formula`. `Ot6ShieldTbl` holds 62 rows.
Excluding them:

| | all 384 | floor-live (322) |
|---|---|---|
| SLASH | 285 | **245** |
| PIERCE | 75 | 58 |
| BLUDGEON | 24 | 19 |
| defaulted | 265 | **227** |
| keyword-inferred | 119 | 95 |

245 of the 322 floor-live species (76 %) are slash, and 227 of those 245 (93 %)
got there by default.

---

## 5. Class distribution by encounter frequency

Over the seven encounter-bearing maps. Neither aggregate weights by time spent
on a map, which is not measured; the first weights each map equally, the second
by per-step encounter rate.

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

Off the draw table entirely: five forced Mag Roader fights, both species
defaulted to slash.

### 5.3 The finding

- In the deep facility (group 106, maps 271 and 273) slash keys 100 % of
  encounters, because both species there landed on slash: one by default
  (Gobbler) and one by a keyword that matched the wrong body
  (Rhinox / `rhino`).
- Those two are the only random-pool species in the area with no vanilla
  elemental weakness at all, so the class row is their entire break axis. A
  wrong class row there leaves the room with no working break.
- Rhinox absorbs bolt (`monster_prop.dat` +23 = `$04`), which is the element
  the rest of the area teaches. This is the Mt. Kolts Brawler-absorbs-poison
  case (`ot6_hud.asm:1348-1360`) one area later, on a bigger body.
- The minecart is the same problem in its simplest form (§3.2): a vanilla
  puzzle whose two keys are both slashing swords, on two species that both
  defaulted to slash.
- ¤ is at 0 %, and §6 explains why it should stay there for this area.

---

## 6. The party that walks this area

### 6.1 Composition

`bosses-wob.md` is the authority here.

| stretch | party | source |
|---|---|---|
| Facility exploration, Ifrit & Shiva, Number 024 | four: Locke, Celes + two, player-chosen | `bosses-wob.md` §13, §14 |
| Minecart, Mag Roaders, Number 128 | three: Celes is lost partway through the facility | `bosses-wob.md` §15 |
| Left & Right Cranes | three: the same set; Setzer is flying the getaway | `bosses-wob.md` §16 |

Terra is available but not active until the tail of the beat
(`wob-route.md`), so no fight in this area may assume her. Setzer is flying
the airship through the escape, so no fight may assume him either.

The exact roster is runtime state, and `bosses-wob.md` §15 says it is to be
measured at the fixture rather than read out of the event dump. One mechanism
is what makes an event-dump reading go wrong: `party_chars` does not change
party membership. Event command `$3c`
(`field/event.asm:596-622`) writes only the four character-object pointers at
`$07fb`-`$0801` — the on-map sprite train. Membership is `char_party`, command
`$3f` (`field/event.asm:563-585`), which writes `$1850,y`. In the facility
chain only Celes gets a `char_party … , 0`; a cutscene that walks one sprite
does not reduce the party to one.

The free picks come from Edgar, Sabin, Cyan and Gau; Locke and Celes are fixed
until the tube room.

### 6.2 What each class costs the player to field

Classes from `ot6_class.asm:10-13`; weapon bytes from `Ot6WeapClassTbl`
(`:46`); ability bytes from `Ot6SkillClassTbl` (`:184-196`); equippability from
the 16-bit character mask at `item_prop_en.dat[item*30]+1`
(`menu/equip.asm:1592`).

| class | who brings it | cost |
|---|---|---|
| **slash** | Celes' whole sword line; Cyan's katanas and all eight SwdTechs (`:185-192`); Sabin's claws `$53`-`$59`; Edgar's Chain Saw `$a6`; Locke's swords | free; five of the six candidates bring it, and for two of them it is the default attack |
| **pierce** | Locke's daggers (his joining weapon); Edgar's spears plus AutoCrossbow `$aa`, Drill `$a8`, Air Anchor `$a9`; Celes' daggers | free; it is Locke's default attack |
| **bludgeon** | Sabin: bare fists `$ff` and Pummel / Suplex / Bum Rush (`:193-195`), which count as bludgeon whatever weapon he holds; Gau: bare fists; otherwise Locke's Full Moon `$45` / Boomerang `$47` / Rising Sun / Sniper / Wing Edge, or Celes' Flail `$44` / Morning Star `$46` | free if one of the two open slots is Sabin or Gau; otherwise a weapon slot plus a shop trip |
| **special ¤** | Setzer's Cards `$4d` only | not assumable; Setzer is flying the getaway |

Blunt weapons are sold at Narshe (shop 0: Flail, Full Moon), Kohlingen
(shop 17: Flail, Full Moon), Jidoor (shop 20: Full Moon) and Tzen (shop 29:
Full Moon, Boomerang). Vector's own weapon shop (27) and Albrook's (25) stock
none, which matters only to a party that brought neither Sabin nor Gau and
still wants bludgeon.

Bludgeon is therefore the area's one deliberate class, and it is reachable:
free for the cost of a party pick, or buyable for the cost of a weapon slot.
`weapon-classes.md`'s coverage table already describes this stretch that way —
*"Magitek factory: all — armored spread: bludgeon/pierce featured."*

¤ is not used in this area. Setzer is its only wielder and he is not in the
fights that close the area, so a ¤ row would require a character those fights
exclude. `weapon-classes.md`'s same table earmarks Opera → Vector for "the
first ¤-weak enemies"; on this beat's roster that has to wait.

### 6.3 The element ring

- **Bolt** — Ramuh, owned from Zozo (`magicite.md`'s WoB roster), grants Bolt and
  Rasp on equip (`genju_prop.asm:83`). Seven of the ten random-pool species
  carry vanilla bolt|water or bolt.
- **Fire and ice** — Ifrit and Shiva magicite, awarded inside the facility
  (`genju_prop.asm:86,:89`; granted on equip, §3.2). Fire also comes on the
  Flame Sabre in map 262's first chest.
- **Poison** — Edgar's Bio Blaster, if Edgar is one of the two picks. General
  is the one body weak to it.
- No element reaches Gobbler or Rhinox, and Rhinox absorbs bolt.

The bosses are covered on both axes. Celes' natural Ice
(`field/event.asm:1266`) answers Ifrit; Ifrit absorbs fire, so the Flame Sabre
heals him, which is the intended absorb lesson. The Flame Sabre answers Shiva,
and Locke and Celes hold the pierce and slash their rows ask for. Number 128's
pierce and the blades' slash are both covered by any three-character party
containing Locke plus one of Edgar, Cyan or Sabin.

---

## 7. What the distribution should be

Three facts set the shape.

1. Slash is the default attack for most of the roster and pierce is nearly
   free. Five of the six candidates swing slash, it is the default for Celes
   and Cyan, and the facility's own chests hand out four more swords (Flame
   Sabre, ThunderBlade, Blizzard, Break Blade). Pierce is Locke's default line
   and Edgar's whole Tools menu. Authoring either onto common trash costs the
   player nothing.
2. Bludgeon is the deliberate class and it is reachable (§6.2) through either
   a party pick or a shop trip.
3. Vanilla already labelled six of the ten bodies as machines (§3.1), which
   gives the player a rule to guess before probing.

So bludgeon carries the area, pierce is the second key on the imperial bodies,
slash comes off the machines entirely, and ¤ is not used in this beat.

Slash still has work: three of the area's six set-pieces are already slash
rows, namely Shiva 6·slash, RightBlade and Left Blade 3·slash each, and
Number 024 slash|pierce. Cyan's Quadra Slam (four hits, and multi-hit actions
chip per hit — `weapon-classes.md`, "Weapons as chip carriers") and Celes'
sword both apply there. What they lose is chipping every random encounter with
the default attack.

The measurable target is three conditions, not an even four-way split: every
encounter is chippable by some buildable party (`weapon-classes.md`'s coverage
rule); no encounter is chippable only by a class no party can field; and slash
is no longer the automatic answer on the common bodies.

---

## 8. The area's `Ot6ShieldTbl` rows

Format matches the existing table (`ot6_hud.asm:1273`): `.word` species,
`.byte` shields, `.byte` class mask.

### 8.1 The rows

| species | id | shields | class mask | rationale |
|---|---|---|---|---|
| Garm | `$0cb` | 2 | `OT6_PIERCE\|OT6_BLUDG` | A magitek quadruped (`Program 95`) rather than a hound: the joints take a point and the housing takes a blow. It is the commonest body at the entrance, where the area introduces its rule, so it carries both halves of that rule. |
| Commando | `$0c7` | 2 | `OT6_PIERCE` | Imperial rank keeps the imperial answer: templar `$0002` and officer `$0175` are both pierce (`ot6_hud.asm:1433-1487`). Chosen for consistency with those rows. |
| ProtoArmor | `$165` | 2 | `OT6_BLUDG` | A sealed suit has no seam for a point, so it is dented instead. Dropping pierce gives the armored machine a different answer from the armored man. Vanilla bolt stays as the ranged key. |
| Pipsqueak | `$041` | 2 | `OT6_PIERCE` | The swarm body, up to ×5 and 22 % of all bodies in the area. Pierce makes Edgar's AutoCrossbow (whole enemy side, chips per hit) the intended answer to a five-stack. |
| Flan | `$047` | 2 | `OT6_BLUDG` | Keeps the generator's answer (`gen_break_floor.py:78`): an ooze cannot be cut. Its element is fire, supplied by the Flame Sabre two maps upstream and by Ifrit's magicite. Ifrit & Shiva are fought in this pool, so the player meets it. |
| General | `$066` | 2 | `OT6_PIERCE\|OT6_BLUDG` | An officer in plate. Vanilla poison answers him if Edgar was picked; the class row is what makes him breakable when Edgar was not. |
| Trapper | `$02d` | 2 | `OT6_BLUDG` | A fixed trap mechanism (`Program 18`), so it is smashed rather than stabbed. Comes ×3, and vanilla bolt\|water is a second key. |
| Chaser | `$0a0` | 2 | `OT6_PIERCE\|OT6_BLUDG` | 1202 HP, the widest break window in the area, on the escape map, where no shop trip is possible mid-sequence. Two keys so that whichever three characters leave the tube room, they hold one. |
| Gobbler | `$088` | 2 | `OT6_SLASH\|OT6_PIERCE` | No vanilla weakness at all, so this row is its only key. It is the one soft body in a dungeon of machines, so it can be cut or stuck. It is the area's slash target, placed in the deepest pool so that blades still have work in the rooms where the machine rows have dropped slash. |
| Rhinox | `$075` | 2 | `OT6_BLUDG` | No weakness of any kind, and it absorbs bolt, so the element the rest of the facility teaches would heal it. Armoured bulk with no seam gives bludgeon, and bludgeon alone. It is the one body in the area that requires the player to have brought a blunt instrument, and it is a reason to bring Sabin. |
| Mag Roader | `$006` | 2 | `OT6_BLUDG` | A machine on wheels, so the wheel is smashed. Its vanilla fire weakness (Ifrit's magicite, or the Flame Sabre) stays as the reward for reading the fight, and its ice absorb stays as a trap. |
| Mag Roader | `$0af` | 2 | `OT6_BLUDG` | Same creature, same class. The element is what distinguishes the pair; repeating that distinction on the class axis would remove the element puzzle. Shiva's magicite answers this one; Ifrit's answers `$006`. |

### 8.2 Shield counts

All twelve sit at 2, against a formula value of 4, because the formula's count
lands the break on an already-dead body (`ot6_hud.asm:1489-1510`).

Unmeasured. Validating them needs a Vector entry-point fixture and a
`bal_party.lua` `boost3` run with `BAL_BUFF_SHIELDS` over 1/2/3 against groups
80, 104, 105 and 106 with a four-character party, and against group 108 and
the minecart formations with three. The three-character arm matters on its
own: less damage per round means the same shield count breaks later.

### 8.3 Resulting distribution

Species count over the twelve authored bodies:

| class | generated floor | authored |
|---|---|---|
| slash | 7 | **1** |
| pierce | 4 | **6** |
| bludgeon | 1 | **9** |
| special ¤ | 0 | **0** |

Share of draws in which a class is a key, over the seven random-pool maps:

| class | floor | authored | floor (rate-wt) | authored (rate-wt) |
|---|---|---|---|---|
| slash | 67.86 % | **19.64 %** | 70.47 % | **24.06 %** |
| pierce | 45.54 % | **66.96 %** | 43.59 % | **69.38 %** |
| bludgeon | 14.29 % | **80.36 %** | 10.00 % | **78.75 %** |

Share of bodies weak to a class: slash 59.11 % → **10.86 %**, pierce 26.20 % →
**64.54 %**, bludgeon 14.70 % → **53.67 %**.

Per-formation reading:

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
| 106 | 31.25 % | Rhinox ×2 | **bludgeon only, and no element at all** |
| 106 | 37.50 % | Gobbler ×2, Rhinox | slash, pierce, bludgeon |
| 108 | 62.50 % | Chaser (+ Pipsqueak ×3) | pierce, bludgeon |
| 108 | 37.50 % | Commando ×4, or Pipsqueak ×4 | pierce |
| minecart | 5 fights | Mag Roader `$006` and/or `$0af` | **bludgeon only** (vanilla fire / ice, both granted by the facility's own magicite) |

---

## 9. Reachability, and what the party cannot break

The generated floor leaves nothing in the area unbreakable, so the fallback
works, but its failure is one of quality rather than coverage: without the
rows, slash answers 100 % of encounters in the deepest third of the facility,
and the dungeon supplies four swords.

With the rows, every encounter is chippable by some buildable party. The costs
are:

- 33.04 % of draws are bludgeon-only on the class axis, plus all five
  minecart fights. Every one of them except the Rhinox pair keeps a reachable
  vanilla element: ProtoArmor and Trapper bolt (Ramuh, owned since Zozo), Flan
  fire (Ifrit, or the Flame Sabre chest), the Mag Roaders fire and ice (Ifrit
  and Shiva, awarded upstream of the ride). A party with no blunt weapon still
  has a probe in all of them.
- 8.93 % of draws (formation `$168`, Rhinox ×2, 31.25 % of the draws on the
  two deepest maps) can be chipped by nothing but a blunt instrument. Rhinox
  has no vanilla weakness and absorbs bolt, so no element substitutes. This is
  the area's one hard requirement, and it is deliberate: bringing Sabin, or
  buying a Flail beforehand, changes the outcome here. Sabin's Blitz costs
  nothing to bring and hits it, as do Gau's fists and a Full Moon on Locke.
- General `$066` loses its vanilla poison key if Edgar is not picked, because
  the Bio Blaster is his Tool. Its `PIERCE|BLUDG` row is what covers that party.

No shop change is needed. Vector's shop 27 stocks no blunt weapon, but with
a four-character party that costs nothing: Sabin and Gau bring bludgeon for
free, and Locke and Celes can buy it in four towns before the walk.

---

## 10. What this asks of the generator and the tests

### 10.1 Substring matching cannot express these rows, and does not need to

Not needed: every row above goes in `Ot6ShieldTbl`, which `Ot6SeedShields`
scans before `@formula` (`ot6_break.asm:24-38`). Authored rows take precedence
by construction, so the generator needs no change to accommodate them.

Not able, in general. Name-substring classification cannot express per-species
intent wherever two species share a name, and 15 names in the game cover 42
species. This area supplies two cases:

- Both minecart bodies are named "Mag Roader" (`$006`, `$0af`), and one
  absorbs the element the other is weak to. A name-keyed rule must give them
  the same class. That is what the design wants here, but only by coincidence:
  the tool could not have chosen otherwise.
- Both Cranes are named "Crane" (`$10d`, `$10e`), and they already carry
  authored rows over different vanilla element profiles.

The same holds for the four Ultros records (`$12c`/`$12d`/`$12e`/`$168`, which
carry four different authored rows), the three Tritochs, the three Kefkas and
the four Tentacles. If species-level control is ever wanted from the tool, the
keying has to move from name to species id.

### 10.2 Three generator/tooling changes this survey identifies

1. Three-way review output: explicit / inferred / defaulted. Two categories are
   not enough. `break_floor_review.txt` triages only DEFAULT rows as "the
   taste-review surface" (`gen_break_floor.py:202-203`). Rhinox is not on that
   list, because `rhino` matched, even though it has no weakness at all,
   absorbs the area's key element, and is 68.75 % of the deep pool. Inferred
   rows need review too.
2. Mark authored species as AUTHORED and exclude them from the headline
   counts. 62 of the 384 rows the review counts never reach `@formula`; the
   floor-live numbers are 245/58/19 over 322 species (§4).
3. An encounter-and-party reachability check. No existing test detects the
   floor's failure here: the bytes are nonzero and every species has a class,
   but nothing measures whether that class is the interesting one or whether
   the party can field it. The check that would catch it: walk
   `SubBattleGroup → RandBattleGroup → BattleMonsters` for a named map set
   and the forced-battle lists (`EventBattleGroup`, plus the train script's
   `$e0`/`$e1`/`$e2` items, since the minecart is invisible to any event-script
   scan), take a declared party and their equippable class sets, and assert
   every formation has at least one class key some member can bring. That is
   the concrete form of "tests cover encounter/party reachability, not only
   nonzero table bytes".

### 10.3 Fixture assertions, on the `gen_kolts.lua:594` pattern

Inventory is ids at `$1869 + i` and counts at `$1969 + i` (the helper at
`gen_kolts.lua:588-593`). Equipped weapon is `$161f + char*37`.

**At the Vector entry point**, before the on-foot world walk into town:

- Assert a bludgeon key exists: Sabin or Gau in the active party (their fists
  and Blitz need nothing), **or** `invCount(0x44) + invCount(0x46) ≥ 1`
  (Flail / Morning Star — Celes) **or** `invCount(0x45) + invCount(0x47) +
  invCount(0x48) + invCount(0x4b) + invCount(0x4c) ≥ 1` (the boomerang family —
  Locke). Direct analogue of "BioBlaster still carried (the poison key)". This
  is the assertion the Rhinox row depends on.
- Assert Ramuh is owned and equippable, because three bludgeon-only rows use
  bolt as their fallback probe.
- Assert the active party is four with Locke and Celes among them, so the
  fixture cannot drift off `bosses-wob.md` §13's roster.

**At the Ifrit & Shiva entry point** (map 264, which is also the Flan pool):
assert Flame Sabre `$0d` is carried or equipped. It is Shiva's element key and
Flan's, and it is a chest two maps back.

**At the minecart boarding point** (map 272's save point at (3,55),
`event_trigger.asm:1211`, the last controllable state before the ride): assert
the party is three, and assert Ifrit and Shiva magicite are owned: they
are the five Mag Roader fights' elemental answers and the facility awards both
upstream.

**At the Crane entry point** (map 240, one step from (52,39)/(52,40)/(52,41)):
assert the party is the three that boarded, since `bosses-wob.md` §16's roster
is the thing most likely to drift.

---

## 11. Open items

`tools/tests/battle_breakvector.lua` is the regression test on the rows: it
walks `SubBattleGroup → RandBattleGroup → BattleMonsters` out of the shipped
ROM, asserts every body in the area is authored rather than floored, enumerates the
six free four-parties and asserts every formation is answerable by one, pins
formation `$168` (Rhinox ×2) as both bludgeon-only and element-less, and
recomputes the key shares to assert bludgeon outranks slash.

Each of these is a separate piece of work:

- The shield counts in §8.2 are UNMEASURED: a precedent-following 2
  against a formula 4. They need their own sweep with a Vector entry-point
  fixture and a separate three-character arm (§8.2, §10.3). It is the largest
  unvalidated assumption in the area.
- The §10.3 fixture assertions are not written, because no Vector
  entry-point / minecart-boarding / Crane entry-point fixture has been
  generated yet. The Rhinox row's
  "a bludgeon key is in the party or the bag" assertion belongs there.
- The §10.2 generator/tooling items are untouched: three-way
  explicit/inferred/defaulted review output, marking authored species and
  excluding them from the headline counts, and the generalised
  encounter/party reachability check. `battle_breakvector.lua` implements the
  third of those for this area only; generalising it is the remaining work.
- Whether maps 265 / 267 / 268 actually roll their group-0 encounters (§1.1)
  wants one runtime check.
- The generated floor remains the documented provisional fallback for every
  area except this one. Retro-authoring Narshe → Blackjack is deferred.
- No human playtesting. The distribution is measured; how it plays is not.
