# Break band — Vector / Magitek Research Facility (survey + proposed rows)

Issue #11, v0.6 scope. **Survey and proposal only** — no source was touched.
`ot6_break_floor.inc`, `gen_break_floor.py` and `Ot6ShieldTbl` are all
unchanged by this document.

Everything below was decoded from the vendored data under `ff6/` on
2026-07-26. Line references are to that tree. Where a claim is an inference
rather than something read out of the source, it is labelled.

> **Revision 2, 2026-07-26.** Rev 1 (landed in `cb559af`) reasoned about a free
> choice of four characters from a roster of seven. That premise was false.
> `vector-route-recon.md` §6e and `wob-route.md` establish that Beat B has **no
> four-character party**: it is **Locke + Celes**, then **Locke alone**, then
> **Locke + Setzer**. Rev 2 rewrites §6 onward against the real parties and
> corrects three data errors of my own that the recon surfaced. The survey data
> in §1–§5 is re-derived, not merely re-labelled — the map set shrank by one and
> the species list grew by two.
>
> **The conclusion moves against rev 1, not for it.** With two characters and
> then one, bludgeon is purchase-gated everywhere with no shop in the band, ¤
> has no wielder outside a single fight, and rev 1's flagship row would have
> made 11.7 % of band draws unbreakable. Three rows are pulled, three widened,
> two species added, and a boss fight is flagged as unfittable as authored (§9).
> Where the honest answer is "this needs a shop change, not a cleverer row",
> §10 says so.

**Corrections to rev 1's own data, found while revising:**

1. **The NPC-block → map offset was wrong by 2.** Rev 1 calibrated
   `event/npc_prop.asm` blocks onto `map_prop` at +3 from `sep[6+m]` but then
   used `sep[m+4]`. Re-calibrated properly (9 of 11 weapon-shop NPC blocks land
   on a `WEAPON SHOP`/`ARSENAL` map at offset 3, 0 of 11 at every other offset).
   Consequence: **Ifrit & Shiva are on maps 263 and 264, not 262/263; Number 024
   is on map 273, not 272; the esper tube room is 274.** All three now agree
   with `vector-route-recon.md` §2/§4, which derived them independently.
2. **Map 275 is unreachable and is dropped from the band.** No short or long
   entrance record anywhere targets it, and `load_map 275` appears nowhere in
   `ff6/src/`. It carries group 106 and the battle-enable bit but cannot be
   visited. The random-encounter map set is **7 maps, not 8**, and every §5
   number is recomputed accordingly.
3. **Two species were missing entirely.** The minecart is `cutscene TRAIN`, not
   an event map, and it carries **five forced battles plus Number 128** issued
   by ASM writing `$0011E0` directly (`world/train_script.asm:829-917`) — which
   is why rev 1's grep for `battle 73` found nothing. Those five fights are
   **Mag Roader `$006` and `$0af`**, both defaulted to slash, both fought by
   **Locke alone**. They are §3.2 and they change the picture.

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
The generator work issue #11 asks for is separate, and §11 covers it.

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

### 1.1 The route, and which maps carry encounters

Map graph and leg order are `vector-route-recon.md` §2/§4/§5; the encounter
columns are decoded here.

```
242 Vector ─► 262 ─► 263 ─(chute)─► 264 ─► 269 ─► 271 ─► 273 ─► 274
   ─► 266 (lift) ─► 272 ─► cutscene TRAIN ─► 240 ─► map 6 (Blackjack)
```

| map | title | enable | group | rate | pool | party |
|---|---|---|---|---|---|---|
| 262 `$106` | MAGITEK FACTORY | **Y** | 80 | `$0040` | Garm, Commando, ProtoArmor, Pipsqueak | Locke + Celes |
| 263 `$107` | — | **Y** | 81 | `$0040` | ProtoArmor, Garm, Commando, Pipsqueak | Locke + Celes |
| 264 `$108` | — | **Y** | 104 | `$0040` | Flan | Locke + Celes |
| 269 `$10d` | — | **Y** | 105 | `$0070` | General, Pipsqueak, Trapper | Locke + Celes |
| 271 `$10f` | MAGITEK RES. FACILITY | **Y** | 106 | `$0070` | Gobbler, Rhinox | Locke + Celes |
| 273 `$111` | — | **Y** | 106 | `$0070` | Gobbler, Rhinox | Locke + Celes |
| 240 `$0f0` | (escape Vector) | **Y** | 108 | `$0070` | Chaser, Commando, Pipsqueak | **Locke alone** |
| 270 `$10e` | — | n | 105 | — | save-point room; carries a group, cannot draw it | — |
| 272 `$110` | — | n | 104 | — | minecart boarding + save point; same | — |
| 274 `$112` | — | n | 106 | — | esper tube room; same | — |
| 275 `$113` | BASEMENT 3 | Y | 106 | — | **unreachable — no entrance record, no `load_map`** | — |

Set-piece rooms, from the corrected NPC-block mapping (offset 3):

| map | contents | fight |
|---|---|---|
| 263 | IFRIT, KEFKA, ELEVATOR | Ifrit approach (`_cc7937` → `battle 70`, `event_main.asm:95283`) |
| 264 | IFRIT, SHIVA, MAGICITE | **the Ifrit & Shiva fight and the Shiva magicite — in the Flan room** |
| 273 | NUMBER_024 | `_cc79ed` → `battle 72` (`:95386`) |
| 274 | BIG_SWITCH, CID, KEFKA, BISMARK, CARBUNCL, MADUIN | six espers (`:95777-95782`); `party_chars LOCKE, CELES` (`:95796`); **Celes removed** (`:96148-96158`) |
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

### Group 104 — map 264 (the Ifrit & Shiva room)

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

### Group 106 — maps 271 and 273 (the deep facility; Number 024's floor)

| p | formation | contents |
|---|---|---|
| 31.25 % | `$07c` | Gobbler ×1 |
| 31.25 % | `$168` | Rhinox ×2 |
| 37.50 % | `$169` | Gobbler ×2, Rhinox ×1 |

per draw: Gobbler 68.75 % / 1.0625 · Rhinox 68.75 % / 1.0000.
Two species, two maps, **100 % of the draws in the deepest third of the
dungeon** — all of it fought by Locke + Celes.

### Group 108 — map 240 (the escape, **Locke alone**)

| p | formation | contents |
|---|---|---|
| 31.25 % | `$07a` | Chaser ×1 |
| 31.25 % | `$1a0` | Commando ×4 |
| 31.25 % | `$07b` | Chaser ×1, Pipsqueak ×3 |
| 6.25 % | `$079` | Pipsqueak ×4 |

per draw: Chaser 62.50 % / 0.6250 · Commando 31.25 % / 1.2500 ·
Pipsqueak 37.50 % / 1.1875

### The minecart — six forced fights, no draws, Locke alone

`cutscene TRAIN` (`event_main.asm:96580`) runs a 52-item script in
`world/train_script.asm`; items 3 and 14 issue `battle 41`, items 9, 24 and 31
issue `battle 144`, and item 36 issues `battle 73`
(`train_script.asm:829/864/899`, each writing `$0011E0` from
`EventBattleGroup` directly).

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

| species | id | L | HP | vanilla weak / null / absorb | authored row | party |
|---|---|---|---|---|---|---|
| Ifrit | `$109` | 21 | 3300 | ice / all but ice / **fire** | 6 · pierce (`ot6_hud.asm:1542`) | Locke + Celes |
| Shiva | `$108` | 21 | 3000 | fire / all but fire / **ice** | 6 · slash (`:1544`) | Locke + Celes |
| Number 024 | `$10a` | 24 | 4777 | **none** | 7 · slash\|pierce (`:1546`) | Locke + Celes |
| Number 128 | `$10b` | 23 | 3276 | none / — / ice | 7 · pierce (`:1549`) | **Locke alone** |
| RightBlade | `$13f` | 21 | 400 | none / — / ice | 3 · slash (`:1551`) | **Locke alone** |
| Left Blade | `$140` | 22 | 700 | none / — / ice | 3 · slash (`:1553`) | **Locke alone** |
| Crane | `$10d` | 23 | 1800 | water / — / bolt | 6 · pierce (`:1555`) | Locke + Setzer |
| Crane | `$10e` | 24 | 2300 | bolt\|water / — / fire | 6 · pierce (`:1557`) | Locke + Setzer |
| Guardian | `$111`/`$112` | 71/67 | 50000/60000 | — | 0 · `$00`, gauge-less | — |

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

**A body-reading gift from vanilla, and it survives rev 2 intact.** Exactly
**6 of 384** species in the game have a `Program NN` special-attack name
(`src/text/monster_special_name_en.json`), and they are exactly Garm, Commando,
ProtoArmor, Pipsqueak, Trapper and Chaser — this band's six machines. Vanilla's
own data splits the pool into *six things running programs* and *four things
that are alive* (an ooze, an officer, a maw, a beast). That is still the spine
of §8; what rev 2 changes is how far the rule can be pushed before it outruns
the party.

### 3.2 The two minecart bodies (new in rev 2)

| species | id | L | HP | vanilla weak | absorb | special | floor |
|---|---|---|---|---|---|---|---|
| Mag Roader | `$006` | 19 | 420 | **fire** | **ice** | Wheel | SLASH (**DEFAULT**) |
| Mag Roader | `$0af` | 18 | 250 | **ice** | — | Rush | SLASH (**DEFAULT**) |

These two are the sharpest thing in the band and rev 1 missed them entirely.

- They are **the same name on two species** — `Mag Roader` covers `$006`,
  `$0af`, `$0e7` and `$0f3`. See §11.1.
- **Their elements are opposed and one of them is a trap:** `$006` is weak to
  fire and **absorbs ice**; `$0af` is weak to ice. Formation `$075` puts them in
  the same fight.
- **Both elemental keys are slashing swords found in this dungeon** — Flame
  Sabre (map 262, chest at (3,25)) and Blizzard (map 263, (55,34)). So the
  vanilla-supplied decision is already excellent, and the current floor
  flattens it: both default to slash, so "hold a sword" answers the class axis
  and the element axis at once.
- **Locke fights all five of these alone, with one weapon, and no menu.** The
  last equip opportunity is the save point on map 272 at (3,55)
  (`event_trigger.asm:1211`); the ride is a cutscene from there to Number 128.
  *(That the field menu is unavailable during `cutscene TRAIN` is an inference
  from it being a cutscene — not traced. The save point on 272 being the last
  certain equip point is not.)*

### 3.3 Shield counts as they stand

Every trash species above seeds **4 shields**: levels 18 and 19 both give
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

Over the **seven** encounter-bearing maps (275 dropped, §1.1). Neither
aggregate weights by *time spent* on a map, which nobody has measured; the
first weights each map equally, the second by per-step encounter rate.

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
species defaulted to slash**, fought solo.

### 5.3 The finding

- **In the deep facility (group 106, maps 271 and 273) slash answers 100 % of
  encounters**, because both species there landed on slash — one by outright
  default (Gobbler) and one by a keyword that fired on the wrong body
  (Rhinox / `rhino`).
- Those two are **the only random-pool species in the band with no vanilla
  elemental weakness at all**, so the class row is not one option among
  several: it is their entire break axis.
- **Rhinox absorbs bolt** (`monster_prop.dat` +23 = `$04`) — the element the
  rest of the band teaches. This is Mt. Kolts' Brawler-absorbs-poison case
  (`ot6_hud.asm:1348-1360`) one band later, on a bigger body.
- **The minecart's five forced fights are the purest form of the problem**: a
  genuinely good vanilla elemental puzzle (fire vs ice, with an absorb trap)
  whose keys are both slashing swords, sitting on two species that both
  defaulted to slash. Holding one sword currently answers both axes at once.
- ¤ is at 0 %. §6.3 explains why that is nearly unfixable here and §8.4 gives it
  the one home it can legitimately have.

---

## 6. The parties that walk this band

### 6.1 There is no four-character party

| stretch | party | covers | evidence |
|---|---|---|---|
| **A** | **Locke + Celes** | maps 262, 263, 264, 269, 271, 273; Ifrit & Shiva; Number 024 | roster at the beat head; the lock is explicit at `event_main.asm:95796` `party_chars LOCKE, CELES` |
| **B** | **Locke — solo** | the minecart (5 Mag Roader fights), **Number 128 + both blades**, and map 240 | `event_main.asm:96148-96158`: `char_party CELES, 0` / `party_chars LOCKE` / `switch $02F6=0` / `remove_equip CELES`; again at `:96739` |
| **C** | **Locke + Setzer** | the Crane fight only | `event_main.asm:96980-96982` `norm_lvl SETZER` / `char_party SETZER, 1` |

Terra is available but **not active** at the v0.6 stop line
(`vector-route-recon.md` §6d), so no fight in this band may assume her.

`party_chars` is event command `$3c`; `EventCmd_3c` (`field/event.asm:596`)
writes the party object pointers directly with `$ff` for an empty slot, so
`party_chars LOCKE` genuinely reduces the walking party to one.

Two mechanical details that carry weight below:

- **`remove_equip` returns the gear to inventory.** `EventCmd_8d`
  (`field/event.asm`) walks all six equipment slots at `$161f + char*37`,
  clears each, and puts the item back into `$1869`/`$1969`. When Celes leaves,
  her whole kit lands in Locke's inventory — but only items *he* can equip help
  him, and Flail/Morning Star are not among them (§6.2).
- **Locke has one weapon slot.** Character data is 37 bytes from `$1600`;
  weapon = `$161f + char*37` (Locke `$1644`, Celes `$16fd`, Setzer `$176c`).
  Without a Genji Glove he swings one class at a time. On the minecart that
  single choice is locked in for **six consecutive fights** (§3.2).
- **Stretch C has no random encounters at all.** The Crane fight auto-plays
  from the map-240 trigger onto map 6 with no navigation
  (`vector-route-recon.md` §5), so Setzer is present for exactly one fight.

### 6.2 What each stretch can field

Classes from `ot6_class.asm:10-13`; weapon bytes from `Ot6WeapClassTbl`
(`:46`); ability bytes from `Ot6SkillClassTbl` (`:184`); equippability from the
16-bit character mask at `item_prop_en.dat[item*30]+1` (`menu/equip.asm:1592`).

| member | slash | pierce | bludgeon | special ¤ |
|---|---|---|---|---|
| Locke | swords (MithrilBlade, Flame Sabre, Blizzard, ThunderBlade, Break Blade, Falchion …) | **daggers — his default line** | Full Moon `$45`, Boomerang `$47`, Rising Sun `$48`, Sniper `$4b`, Wing Edge `$4c` | **none** |
| Celes | **the whole sword line** | daggers (Dirk, MithrilKnife, Man Eater, Graedus) | Flail `$44`, Morning Star `$46` | **none** |
| Setzer | none | Darts `$4e`, Doom Darts | none | **Cards `$4d` — his joining weapon** (`char_prop.asm:253`) |

Locke's `STEAL` and Celes' `RUNIC` carry no class byte (absent from
`Ot6SkillClassTbl`), so neither chips. Neither character has Tools, Blitz,
Bushido or Throw. **Every class this band can field comes from an equipped
weapon.**

| stretch | slash | pierce | bludgeon | special ¤ |
|---|---|---|---|---|
| **A** — Locke + Celes | ✅ free, both | ✅ free, both | ⚠️ **purchase only** | ❌ **impossible** |
| **B** — Locke solo | ✅ but one slot | ✅ but one slot | ⚠️ purchase only, and it costs him his only weapon and its element | ❌ **impossible** |
| **C** — Locke + Setzer | ✅ Locke | ✅ both | ⚠️ purchase only | ✅ Setzer's Cards |

### 6.3 The two facts that break rev 1's design

**¤ does not exist in this band outside the Crane fight.** Sabin, Gau, Edgar
and Relm are all absent; Setzer arrives at `:96982`, immediately before
`battle 71`, on a map with no random encounters. Rev 1's Rhinox row
(`OT6_BLUDG|OT6_SPECIAL`) would have shown a `?` slot on the HUD that **no
party in this band can ever fill**, on a body with no elemental weakness, in
68.75 % of the draws on the two deepest maps. Pulled (§8.1).

**Bludgeon is purchase-gated everywhere and no shop in the band sells one.**
Rev 1's free-bludgeon answer was Sabin's Blitz and Gau's fists; neither
character is present. What is left:

| town | shop | blunt / ¤ stock |
|---|---|---|
| Narshe (map 24) | 0 | **Flail** (Celes), **Full Moon** (Locke) |
| Kohlingen (map 194) | 17 | **Flail**, **Full Moon** |
| Jidoor (map 204) | 20 | **Full Moon** |
| Tzen (map 309) | 29 | **Full Moon**, **Boomerang** |
| Albrook (map 326) | 25 | *none* |
| **Vector (map 246)** | 27 | *none* — Forged, Poison Claw, Epee, Blossom |

Vector's own weapon shop sells no blunt and no ¤ weapon, and Vector is reached
by an **on-foot world walk**, not by airship (`vector-route-recon.md` §1a;
map 323 is Albrook, filed as **issue #17**), so there is no casual hop back to
Narshe once the walk has started. A player who did not shop in Narshe,
Kohlingen, Jidoor or Tzen *before* that walk has no bludgeon for the entire
band, and no way to get one. **Therefore no bludgeon-only row may sit on a body
that has no reachable element.**

### 6.4 The element ring, also thinner than rev 1 said

- **Bolt is the band's main element** — Ramuh is owned from Zozo
  (`wob-route.md:30-33`) and seven of the ten random-pool species carry vanilla
  bolt|water or bolt. But it is *learned* magic, not guaranteed gear; a fixture
  should check it (§11.3).
- **Poison is gone.** Rev 1 leaned on Edgar's Bio Blaster for General
  (`$066`, poison-weak). **Edgar is not in this band.** General's vanilla
  weakness is unreachable, so its class row is the only key it has.
- **Ice is Celes' only offensive spell** (natural list Ice 1 / Cure 4 /
  Antdot 8 / Imp 13 / Scan 18 / Safe 22 / Ice 2 26, `field/event.asm:1266-1281`)
  — and in the random pools nothing is ice-weak, while Number 128 and both
  blades **absorb** it. It matters in exactly two places: **Ifrit** (ice-weak)
  and **Mag Roader `$0af`**.
- **Fire is a chest.** With Terra out, fire is the **Flame Sabre in map 262's
  first chest at (3,25)** — a slashing sword either character can equip,
  upstream of everything that needs it. The facility also gives ThunderBlade
  (262, (25,44)), **Blizzard** (263, (55,34)) and Break Blade (271, (8,37)).
- **Nothing reaches Gobbler or Rhinox**, and Rhinox *absorbs* bolt.

The bosses come out fine on elements, which is worth stating: Celes' Ice
answers Ifrit (who absorbs fire — so the Flame Sabre *heals* him, the intended
absorb lesson), the Flame Sabre answers Shiva, and Locke and Celes between them
hold the pierce and slash the two authored rows ask for. **Ifrit, Shiva and
Number 024 need no change.**

---

## 7. What the distribution should be, given two characters and then one

The goal is unchanged — a real question with an answer the party can supply —
but the constraints are much tighter than rev 1 assumed:

1. **Slash and pierce are both "the A button."** Locke's default line is
   daggers, Celes' is swords; between them the pair covers half the class ring
   for free, and the facility's chests add four more swords.
2. **Bludgeon is the only deliberate class, and it is purchase-gated with no
   shop in the band and no way back.** It can be *the interesting answer* only
   where something else is also reachable.
3. **¤ has exactly one legitimate home**: the Crane fight, where the script
   guarantees a ¤ wielder.
4. **Stretch B is solo with one weapon slot**, and on the minecart that slot is
   frozen across six fights. Its pools must be chippable from whichever of
   Locke's two lines he happens to be holding.

Which yields the conclusion rev 1 talked itself out of:

> **On this band there is no weapon class that is simultaneously reachable and
> not a default swing.** The two characters present cover slash and pierce with
> their normal weapons; bludgeon has a wielder only after a shop trip in a
> different town, before a one-way walk; ¤ has no wielder at all until the last
> fight. This is exactly the structural finding `weapon-classes.md:96-102`
> recorded for Figaro → Kolts — "every class row here is a freebie or a Repo
> Man" — recurring one band later for the same reason: a two-character party
> cannot make a four-class ring interesting.

So the pass is scoped to what class rows can honestly do here:

- **Move the weight off slash and onto bludgeon and pierce** on the stretch-A
  pools, following the `Program NN` machine split, so the band reads "the
  machines don't care about your sword" and a player who bought a blunt weapon
  is rewarded across most of the dungeon.
- **Never let bludgeon be the only key on a body with no reachable element.**
- **On the solo stretch, guarantee every fight from either of Locke's lines** —
  and say plainly that those rows are coverage, not design.
- **Give ¤ its debut on Crane `$10e`**, the one fight with a guaranteed wielder.
- **Do not flatten the minecart's vanilla fire/ice puzzle** — put the class row
  where it complements the element rather than duplicating it.

The measurable target is not an even four-way split. It is: *every fight
chippable by the party that actually fights it, no fight chippable only by an
unreachable class, and slash no longer the automatic answer on the common
bodies.*

---

## 8. Proposed `Ot6ShieldTbl` rows (rev 2)

Format matches the existing table (`ot6_hud.asm:1273`): `.word` species,
`.byte` shields, `.byte` class mask. Changes from rev 1 are called out.

### 8.1 Stretch A — the Locke + Celes pools

| species | id | shields | class mask | rationale |
|---|---|---|---|---|
| Garm | `$0cb` | 2 | `OT6_PIERCE\|OT6_BLUDG` | A magitek quadruped (`Program 95`): pierce the joints or cave the housing. Keeps vanilla bolt, so bludgeon can be the *better* answer without being the only one. |
| Commando | `$0c7` | 2 | `OT6_SLASH\|OT6_PIERCE` | **Widened from `PIERCE`.** The only body that appears in both stretch A and the solo escape, so it must be reachable from either of Locke's lines. It is also exactly the existing soldier-line palette — `$0001` soldier, `$0065` trooper and `$003f` rider are all `SLASH\|PIERCE` (`ot6_hud.asm:1433-1487`) — so the widening is consistency, not concession. |
| ProtoArmor | `$165` | 2 | `OT6_BLUDG` | A sealed suit has no seam for a point; you dent it. Bludgeon-only is permitted **because it keeps vanilla bolt**, which Ramuh reaches. |
| Pipsqueak | `$041` | 2 | `OT6_PIERCE` | The swarm body (up to ×5), 22 % of all bodies in the band. Pierce, with vanilla bolt\|water as the floor for a sword loadout. |
| Flan | `$047` | 2 | `OT6_BLUDG` | Keep the generator's read (`gen_break_floor.py:78`): you cannot cut an ooze. Its only element is fire — the Flame Sabre chest two maps upstream. Group 104 is 100 % Flan **and it is the Ifrit & Shiva room**, so this is the most gated pool in the band; see §11.3 for the assertion it needs. |
| General | `$066` | 2 | `OT6_PIERCE\|OT6_BLUDG` | An officer in plate. **Its vanilla poison is unreachable — Edgar is not in this band** — so unlike rev 1 this row is its only key, and pierce is what makes it reachable. |
| Trapper | `$02d` | 2 | `OT6_BLUDG` | A fixed trap mechanism (`Program 18`) — you smash a device. Bludgeon-only is permitted because it keeps vanilla bolt\|water. |
| Gobbler | `$088` | 2 | `OT6_SLASH\|OT6_PIERCE` | No vanilla weakness at all, so this row is its only key. A soft maw: cut it or stick it. Two default-swing classes because it is 68.75 % of the deep pool and its partner (below) is the harder one. |
| Rhinox | `$075` | 2 | `OT6_PIERCE\|OT6_BLUDG` | **Changed from `BLUDG\|SPECIAL`.** No weakness of any kind *and* it absorbs bolt, so no element substitutes; ¤ has no wielder here; and it is the only body in a group-106 draw 31.25 % of the time. Rev 1's row made that draw unbreakable by any party the band can field. Bludgeon stays as the body-read answer (armoured bulk, no seam); pierce is what makes it reachable at all. **Honest cost: pierce is Locke's default line, so the band's flagship body is a freebie for a dagger Locke.** §10 argues this is the right trade and names the one change that would undo it. |

### 8.2 Stretch B — the solo pools

These rows are **coverage, not design**, and the document says so rather than
dressing them up. On a solo stretch there is no party composition to reward,
only a weapon choice made before an unannounced split, with no shop and — on
the minecart — no menu.

| species | id | shields | class mask | rationale |
|---|---|---|---|---|
| Chaser | `$0a0` | 2 | `OT6_SLASH\|OT6_PIERCE\|OT6_BLUDG` | **Widened from `PIERCE\|BLUDG`.** 1202 HP, the largest trash body in the band, and it is 62.5 % of the escape draws fought by one character. Without slash, a sword-carrying Locke has no class chip in 62.5 % of map 240. Narrow to `PIERCE\|BLUDG` only if playtest confirms Locke reliably carries Bolt. |
| Mag Roader | `$006` | 2 | `OT6_SLASH\|OT6_PIERCE` | **New.** The ice-*absorber*: the Blizzard sword that answers its partner actively heals this one, so its class row must not depend on a loadout guess. Both of Locke's lines reach it; the vanilla fire weakness (Flame Sabre) stays the reward for reading the fight. |
| Mag Roader | `$0af` | 2 | `OT6_PIERCE` | **New.** Weak to ice, and ice comes on the **Blizzard** sword from map 263's chest — so a sword Locke has the element axis and a dagger Locke has the class axis, and every loadout has exactly one key. This is the one place in the band where a single-class row is defensible on a solo stretch, because the alternative axis is a chest inside the same dungeon. |

Checked: with these rows a **dagger** Locke has a class chip in 100 % of map-240
draws and all five minecart fights; a **sword** Locke has one in 93.75 % of
map-240 draws (the 6.25 % gap is the Pipsqueak ×4 formation, which is
bolt|water-weak) and in every minecart fight except `$197` (Mag Roader `$0af`
×4), where the Blizzard sword supplies the element instead.

### 8.3 Shield counts

All twelve are proposed at **2** against a formula value of 4, following the
finding both prior passes reached independently: the formula's count lands the
break on a corpse (`balance-metrics.md:944-972`; `ot6_hud.asm:1489-1510`).

**Unmeasured, and rev 2 raises the stakes.** A solo Locke's damage output is
roughly half a two-character party's, so the same shield count produces a much
later break in stretch B. The sweep must run **stretch B as its own arm** —
`bal_party.lua` `boost3` with `BAL_BUFF_SHIELDS` over 1/2/3 against group 108
and the minecart formations with Locke alone, as well as groups 80/104/105/106
with the pair. It is entirely plausible that the right answer is 2 for stretch A
and **1** for the solo pools.

### 8.4 The ¤ debut — Crane `$10e`

Rev 1 put ¤ on Rhinox (pulled: no wielder) and proposed splitting the Cranes
pierce / bludgeon (pulled: bludgeon is purchase-gated and the Cranes are
unskippable). Proposed instead:

- `$10d` Crane — **6 · `OT6_PIERCE`** (unchanged; keeps vanilla water)
- `$10e` Crane — **6 · `OT6_PIERCE|OT6_SPECIAL`** (keeps vanilla bolt|water)

`char_party SETZER, 1` fires at `:96982`, immediately before `battle 71`, so a
¤ wielder is **script-guaranteed** in this fight and only this fight — the one
place in the band where the class can be authored without a composition trap.
The pierce bit keeps the row reachable if the player swapped Setzer's Cards for
Darts. The pair then asks two different characters for two different keys,
which is what rev 1 wanted and could not safely have.

---

## 9. Number 128 — a solo boss fight the authored rows do not fit

**Locke, alone, with one weapon he last chose on map 272**, faces Number 128
`$10b` (7 shields, `OT6_PIERCE`, 3276 HP) plus RightBlade `$13f` (3 shields,
`OT6_SLASH`, 400 HP) and Left Blade `$140` (3 shields, `OT6_SLASH`, 700 HP).
**None of the three has any vanilla elemental weakness and all three absorb
ice** (`monster_prop.dat` +23/+25), and there is no `Ot6ElemAddTbl` row for any
of them.

The whole fight is therefore decided by one item:

| Locke's loadout | body `$10b` | blades `$13f`/`$140` |
|---|---|---|
| a dagger (pierce) | ✅ chips | ❌ no chip at all |
| a sword (slash) | ❌ no chip at all | ✅ chips both |
| a boomerang (bludgeon) | ❌ | ❌ |

**As authored, no single loadout can break the whole fight**, and there is no
element, no second character, no shop and no menu to fix it. `wob-route.md`
records the blades as "part-breaks as the cancel", so a dagger Locke has no
access to the cancel mechanic at all and a sword Locke can never break the body
he is fighting.

**Proposed fix — widen all three so one loadout reaches everything:**

- `$10b` Number 128 — **7 · `OT6_SLASH|OT6_PIERCE`** (was `OT6_PIERCE`)
- `$13f` RightBlade — **3 · `OT6_SLASH|OT6_PIERCE`** (was `OT6_SLASH`)
- `$140` Left Blade — **3 · `OT6_SLASH|OT6_PIERCE`** (was `OT6_SLASH`)

This is Number 024's own row (`7 · slash|pierce`, `ot6_hud.asm:1546`), authored
on exactly this reasoning — "the classes are the handhold." On a solo fight a
class row can only reward or punish a weapon choice made before an unannounced
party split; punishing it is a trap, so the rows should be wide and the
difficulty should live in the shield counts and the script.

If the intent is instead that Number 128 *is* a loadout exam, it needs a
telegraphed re-equip opportunity after Celes leaves and before the ride, plus a
statement to that effect in `bosses-wob.md`. That is a design decision above
this document; it is flagged rather than assumed.

---

## 10. What the party genuinely cannot break

Under the **current** floor: nothing. The safety net works.

Under **rev 1's rows**, measured against the real parties: **11.72 % of all
band draws had no key of any kind** — every Rhinox ×2 draw (formation `$168`,
31.25 % of group 106), because the row was `bludgeon|¤` and this band can field
neither for free. That is the row rev 2 pulls, and it is the single concrete
harm the false party model would have caused.

Under **rev 2**: **no fight in the band lacks a key for the party that fights
it.** What remains is friction, stated plainly:

- **28.12 % of stretch-A draws have no default-swing class key** — the
  bludgeon-only bodies ProtoArmor ×2, Flan, and Trapper ×3. Every one keeps a
  reachable vanilla element (bolt, fire, bolt), which is exactly why they are
  allowed to be bludgeon-only. If playtest finds players arriving without Bolt
  learned, ProtoArmor and Trapper should gain pierce.
- **Group 104 (map 264) is the most gated pool in the band**: 100 % Flan,
  class = bludgeon (purchase-gated), element = fire (one chest, two maps
  upstream) — and it is the floor the Ifrit & Shiva fight happens on, so the
  player will be standing in it for a while.
- **A sword-carrying solo Locke has no class chip in 6.25 % of map-240 draws**
  (Pipsqueak ×4, which is bolt|water-weak) and none against Mag Roader `$0af`
  ×4 (which the Blizzard chest answers on the element axis).
- **Number 128 as authored today is unfittable by any single loadout** (§9).
  This is the one hard failure in the band and it is a boss, not trash.

### The change this band actually wants

The cleanest fix for most of the above is **not** a wider row — it is one line
of shop data. **Add Full Moon `$45` and Flail `$44` to Vector's weapon shop
(shop 27, map 246).** It is the last shop before a one-way walk into the
facility, it puts a bludgeon key in reach of *both* stretch-A characters at the
beat head, it makes the `Program NN` machine rule teachable in the town whose
factory teaches it, and it costs nothing in balance because both weapons are
weak. With it:

- ProtoArmor, Trapper and Flan become a genuine choice instead of a reward for
  having shopped two towns ago;
- **Rhinox can go back to `OT6_BLUDG` alone** — the design row rev 1 wanted, on
  the one body in the band that deserves it;
- and the band gets the "bludgeon is the deliberate class" identity that
  `weapon-classes.md:75` already promises it ("Magitek factory: armored spread:
  bludgeon/pierce featured").

**Recommendation: make the shop change, then narrow Rhinox to `OT6_BLUDG`.**
Absent it, ship Rhinox as `OT6_PIERCE|OT6_BLUDG` and accept that the band's
flagship body is a freebie for a dagger Locke. The shop change is outside issue
#11's scope, so it is argued for here rather than assumed.

### Resulting distribution

Species count over the twelve authored bodies:

| class | current floor | rev 1 (10 bodies) | **rev 2 (12 bodies)** |
|---|---|---|---|
| slash | 7 | 1 | **4** |
| pierce | 4 | 6 | **9** |
| bludgeon | 1 | 6 | **7** |
| special ¤ | 0 | 1 | **0** (moved to Crane `$10e`) |

(20 class bits over 12 species; eight bodies carry two or more keys. The
breadth is the price of a two-then-one-character party — rev 1's 14 bits over
10 species assumed four wielders to spread them across.)

Share of draws in which a class is a key, over the seven random-pool maps:

| class | current | **rev 2** | current (rate-wt) | **rev 2 (rate-wt)** |
|---|---|---|---|---|
| slash | 67.86 % | **47.32 %** | 70.47 % | **50.47 %** |
| pierce | 45.54 % | **75.89 %** | 43.59 % | **80.31 %** |
| bludgeon | 14.29 % | **80.36 %** | 10.00 % | **78.75 %** |

Share of bodies weak to a class: slash 59.11 % → **27.48 %**, pierce 26.20 % →
**74.76 %**, bludgeon 14.70 % → **53.67 %**.

Split by stretch, which is the number that matters:

| | slash | pierce | bludgeon |
|---|---|---|---|
| stretch A (6 maps, Locke + Celes) | 39.58 % | 71.88 % | **83.33 %** |
| stretch B (map 240, Locke alone) | 93.75 % | 100 % | 62.50 % |

That asymmetry is the design: **bludgeon carries the dungeon, and the solo
escape is guaranteed from either of Locke's default lines.** Slash falls from
"the answer to two draws in three" to "the answer to two draws in five", and
it is no longer the answer on any of the four bodies that defaulted into it.

---

## 11. What this asks of the generator and the tests

### 11.1 Can substring matching express these rows? Not needed, and not able.

**Not needed:** every row above goes in `Ot6ShieldTbl`, which
`Ot6SeedShields` scans *before* `@formula` (`ot6_break.asm:24-38`). Authored
rows win by construction; the generator needs no change to accommodate them.

**Not able, in general**, and this band supplies two independent proofs.
Name-substring classification cannot express per-species intent wherever two
species share a name, and **15 names in the game cover 42 species**:

- **Both Cranes are named "Crane"** (`$10d`, `$10e`). §8.4's asymmetric rows are
  unexpressible by any keyword rule.
- **Both minecart bodies are named "Mag Roader"** (`$006`, `$0af`) — and they
  are *opposed*: one absorbs the element the other is weak to. A name-keyed
  classifier must give them the same class, which is precisely the thing that
  flattens the band's best vanilla puzzle (§3.2).

The same holds for the four Ultros records (`$12c`/`$12d`/`$12e`/`$168`, which
already carry four different authored rows), the three Tritochs, the three
Kefkas and the four Tentacles. If species-level control is ever wanted from the
tool, the keying has to move from name to species id.

### 11.2 Three generator/tooling changes this survey argues for

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
3. **An encounter-*and-party* reachability check, run per stretch.** Rev 1's
   error was not a data error — every number in §1–§5 was recomputed in rev 2
   and only the map count and species list moved. It was a **party model**
   error, and no tooling in the repo could have caught it. The check that
   would: walk `SubBattleGroup → RandBattleGroup → BattleMonsters` for a named
   map set *and* the forced-battle lists (`EventBattleGroup`, plus the train
   script's `$e0`/`$e1`/`$e2` items), take a declared party roster and their
   equippable class sets, and assert every formation has at least one class key
   some present member can equip. Per stretch, not per band. That is the
   concrete form of "tests cover encounter/party reachability, not only nonzero
   table bytes", and rev 2 exists because it does not yet exist.

### 11.3 Fixture assertions, concrete, on the `gen_kolts.lua:594` pattern

Inventory is ids at `$1869 + i` and counts at `$1969 + i` (the helper at
`gen_kolts.lua:588-593`). Equipped weapon is `$161f + char*37`: **Locke
`$1644`, Celes `$16fd`, Setzer `$176c`**.

**At the Vector doorstep** (before the world walk, while shops are still
reachable):

- Assert a bludgeon key is carried, and fail with the reason if not:
  `invCount(0x44) + invCount(0x46) ≥ 1` (Flail / Morning Star — Celes) **or**
  `invCount(0x45) + invCount(0x47) + invCount(0x48) + invCount(0x4b) +
  invCount(0x4c) ≥ 1` (Full Moon / Boomerang / Rising Sun / Sniper / Wing Edge
  — Locke). Direct analogue of "BioBlaster still carried (the poison key)".
- Assert the active party is exactly Locke + Celes, so the fixture cannot drift
  back into a four-party assumption.
- Assert Bolt is learned by at least one of them — three bludgeon-only rows use
  it as their floor.

**At the Ifrit & Shiva doorstep** (map 264, which is also the Flan pool):
assert **Flame Sabre `$0d`** is carried or equipped. It is Shiva's element key
*and* Flan's only element key, and it is a chest two maps back — this is the
single most load-bearing pickup in the band.

**At the minecart boarding point** (map 272 save point, the last equip
opportunity): assert the party is Locke alone, and assert his equipped weapon
at `$1644` resolves through `Ot6WeapClassTbl` to a class present in **all
three** Number 128 rows. Under §9's widened rows any slash or pierce weapon
passes; **under the rows as they ship today, no weapon passes** — which is the
point of the test.

**At the stretch-B head** (immediately after `event_main.asm:96158`): assert
both a slash and a pierce weapon are in inventory. `remove_equip CELES` has
just supplied them, and a regression that changed that would silently strand
half of Locke's loadouts on map 240.

**At the Crane doorstep** (map 240, one step from (52,39)/(52,40)/(52,41)):
assert Setzer is in the party and his weapon at `$176c` is Cards `$4d`,
Trump `$50`, Dice `$51` or Darts `$4e` — i.e. the ¤ row on `$10e` has a wielder.

---

## 12. Status

Proposal, revision 2. Nothing here is measured and no file was modified.

- §1–§5 were **re-derived**, not relabelled: the map set is 7 not 8 (275 is
  unreachable), the boss rooms moved (263/264/273/274), and two forced-battle
  species were added.
- §6 onward was rewritten against the real parties: Locke + Celes, then Locke
  alone, then Locke + Setzer.
- **Pulled from rev 1:** ¤ on Rhinox; the pierce/bludgeon Crane split; the
  `PIERCE`-only Commando row; the `PIERCE|BLUDG` Chaser row; and rev 1's claim
  that "every legal party can field a bludgeon or ¤ carrier for free", which
  was an artefact of the false roster.
- **Added in rev 2:** the two Mag Roader rows (§8.2), the Number 128
  solo-fight finding (§9), the ¤ debut on Crane `$10e` (§8.4), and the Vector
  shop recommendation (§10).
- Shield counts (§8.3) remain a precedent-following guess and need their own
  sweep, now with a separate solo arm.
- The generated floor remains the documented provisional safety net for every
  band except this one until these rows land.
