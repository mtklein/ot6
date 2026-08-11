# Break coverage — the Cave to the Sealed Gate (survey + proposed rows)

v0.7 scope; `break-coverage-vector.md` is the model.
**PROPOSAL ONLY: nothing here is landed.** The six rows in §8 are not in
`Ot6ShieldTbl`; they land with the area's implementation wave. The only thing
that ships with this survey is the `sealed-gate` entry in
`tools/check_break_reach.py`'s `AREAS` table, which checks the current data
as it stands (§10).

Everything below is decoded from the vendored data under `ff6/`. Every species
byte, map byte, group word, formation record and arithmetic figure is
recomputed from `sub_battle_group.dat` / `rand_battle_group.dat` /
`battle_monsters.dat` / `monster_prop.dat` / `map_prop.dat` and the entrance
`.dat` pair. `monster_prop.dat +23` is absorb, `+25` is weak
(`docs/HANDOFF.md`, canonical). Where a claim is an inference it is labelled.

---

## 0. Decode chain and weights

Per `break-coverage-vector.md` §1: `map_prop.dat[map*33]` byte 5 bit 7 =
random-battle enable → `SubBattleGroup[map]` (`field/battle.asm:392`) →
`RandBattleGroup[group*8]`, four formation words drawn at
**31.25 / 31.25 / 31.25 / 6.25 %** (`field/battle.asm:398-408`) →
`BattleMonsters[formation*15]` → `MonsterProp[species*32]`.

Per-step rate: all four encounter maps carry rate code 0 → `$0070`
(`sub_battle_rate.dat`; table `SubBattleRateTbl` verified at
`field/battle.asm:259-262`, read at `:375-376`). Because every map in the
area has the same rate, equal-map weight and rate weight are the same
number, and the OT6 danger multiplier (`Ot6DangerMulW`,
`ot6_break.asm:644-671`) cancels out of every share below. This area has no
two-rate split of the kind the Vector area has.

Forced battles decode through `event_battle_group.dat[battle*4]`, word 0 at
75 % / word 1 at 25 % (`field/event.asm` `EventBattle`, per the checker
header).

---

## 1. The area's map set, verified from data

### 1.1 The encounter-bearing maps: exactly four

| map | title | enable | group | rate | pool |
|---|---|---|---|---|---|
| 382 | CAVE TO THE SEALED GATE | **Y** | 92 | `$0070` | Apparite, Coelecite, Lich |
| 383 | BASEMENT 1 | **Y** | 93 | `$0070` | Apparite, Lich, Ing |
| 384 | BASEMENT 3 | **Y** | 94 | `$0070` | Zombone, Ing |
| 385 | BASEMENT 2 | **Y** | 95 | `$0070` | Zombone, Ing, Coelecite |
| 386 | BASEMENT 4 (save room) | n | 92 | — | carries a group, cannot draw it |
| 391 | SEALED GATE | n | 0 | — | the scene room; no encounters |
| 377/378 | IMPERIAL BASE | **n** | 110 | — | the base has no encounters |

The Imperial Base contributes no encounters to the area. Maps 377/378/379 have
the enable bit clear. The random-encounter surface of v0.7's interior
segments is these four cave maps plus one forced ambush (§2.2).

### 1.2 The unreachable and cutscene-only maps

- The Imperial Base is maps 377/378, not 381 (entrance scan: world
  `(165,194)→377`, `(166,194)→377 (30,13)`, `377 (13,18)→378`).
  Map 381 is a cutscene map on the Sealed Gate tileset, used only by the
  Esper-World flashback (`load_map 381` at `event_main.asm:11909`, in the
  Maduin/Madonna sequence; likewise 389 at `:11755`, 390 at `:11432`). No
  entrance record targets 379/380/381/387/388/389/390 (full scan of
  `trigger/short_entrance.dat` + `trigger/long_entrance.dat`, record layouts
  `include/field/short_entrance.inc:9-18` / `long_entrance.inc:9-18`), and no
  other `load_map` reaches them.
- Four more maps carry live-looking encounter bytes but are unreachable, the
  map-275 pattern from v0.6: 387 (enable Y, group 93) and 388
  (enable Y, group 94) are unreachable cave duplicates; 380 (enable Y,
  group 110 → ChickenLip ×5, formation `$095`) and 381 (enable Y,
  group 0, the Narshe overworld pool) are unreachable or
  cutscene-only. Map 381 repeats the v0.6 maps-265/267/268
  anomaly: if the flashback ever took a danger-checked step there it would
  draw level-5 Narshe trash. As in v0.6 this is an inference: cutscene
  movement never takes a free step, so it never rolls. No rows are authored
  for it; it needs the same one runtime check.

### 1.3 The forced battles

| fight | where | formation | contents | in this survey? |
|---|---|---|---|---|
| battle 149 | 384 (66,11) trap switch (`event_main.asm:45177`) | `$20c` (both words) | Ninja `$003` ×1 | yes; real body, §3 |
| battle 121/122 | map 391 gate scene | `$180`/`$181` | dummy `$17b` L1 HP1 | no; battle-event contents, unprobed, and this survey deliberately decides nothing about them |
| battle 123 | Blackjack deck | `$182` | dummy `$17b` | no; same |

The banquet fights (26/27/30) and the two world areas (southern continent,
Crescent Island) are outside this survey's scope; §12 flags them as the
milestone's remaining unsurveyed encounter surface.

---

## 2. The pools, formation by formation

Group 92 — map 382 (cave mouth):

| p | formation | contents |
|---|---|---|
| 31.25 % | `$099` | Apparite ×2 |
| 31.25 % | `$09b` | Apparite, Coelecite, Lich |
| 37.50 % | `$09c` | Lich ×3 |

Group 93 — map 383 (Basement 1):

| p | formation | contents |
|---|---|---|
| 31.25 % | `$099` | Apparite ×2 |
| 31.25 % | `$049` | Apparite ×2, Lich ×2 |
| 37.50 % | `$098` | Ing ×3 |

Group 94 — map 384 (Basement 3, the big bridge map):

| p | formation | contents |
|---|---|---|
| 31.25 % | `$024` | Zombone ×2 |
| 31.25 % | `$097` | Ing ×2, Zombone |
| 37.50 % | `$098` | Ing ×3 |

Group 95 — map 385 (Basement 2, the timed floor):

| p | formation | contents |
|---|---|---|
| 31.25 % | `$096` | Zombone ×1 |
| 31.25 % | `$097` | Ing ×2, Zombone |
| 37.50 % | `$09a` | Coelecite ×3 |

Per-species, equal-map weight (= rate weight, §0):

| species | bodies/draw | % of all bodies | appearance share |
|---|---|---|---|
| Ing | 0.8750 | **32.56 %** | 34.38 % |
| Apparite | 0.5469 | 20.35 % | 31.25 % |
| Lich | 0.5156 | 19.19 % | 25.00 % |
| Zombone | 0.3906 | 14.53 % | 31.25 % |
| Coelecite | 0.3594 | 13.37 % | 17.19 % |

2.6875 bodies per draw. Ing is the area's swarm body: ×3 at 37.5 % on two
of the four maps.

---

## 3. The species

| species | id | L | HP | absorb | null | weak |
|---|---|---|---|---|---|---|
| Apparite | `$06e` | 20 | 781 | fire\|poison | — | **ice\|pearl** |
| Lich | `$0e5` | 20 | 590 | fire\|poison | — | **pearl only** |
| Ing | `$048` | 21 | 1100 | fire\|poison | — | **pearl\|water** |
| Zombone | `$082` | 21 | 1991 | poison | — | **fire\|pearl** |
| Coelecite | `$0b3` | 20 | 480 | fire | — | **ice** |
| Ninja (forced) | `$003` | 27 | 1650 | poison | — | **bolt\|pearl** |

Three patterns in the vanilla data:

- Pearl is the master key: 4 of 5 random species and the Ninja are
  pearl-weak, and nothing in the area absorbs or nulls it. 90.63 % of draws
  contain a pearl-weak body (§5).
- Fire and poison feed absorbers: fire is absorbed by 4 of 5 species
  (84.38 % of draws feed a fire splash) and poison by 4 of 5 plus the
  Ninja. This area requires Terra in the party (the base entrance demands her)
  and her fire lean (`kits.md`'s Terra entry) is wrong here. It repeats the
  Zozo poison inversion, and it is worth keeping.
- The exception looks deliberate: Coelecite is the one body with no
  pearl weakness, and it is also the one whose absorb set (fire only) admits
  ice. It is a rock rather than a corpse. Vanilla already supplies the one
  fight the master key does not answer.

Shield counts as they stand: levels 20-21 give `2 + level/8` = **4**
(`ot6_break.asm` `@formula`); Ninja at 27 gives 5. Both prior authoring
passes measured 4 as one-too-many on trash and landed on 2
(`ot6_hud.asm:1489-1510`, `break-coverage-vector.md` §8.2 — the third area to
inherit that finding unmeasured, see §9).

---

## 4. What the generated floor currently says

No species in the area has an `Ot6ShieldTbl` row today (scanned `ot6_hud.asm`; also
visible in the checker's `[floor]` provenance tags).

| species | current class | how (`ff6/tools/gen_break_floor.py` keyword lists) |
|---|---|---|
| Apparite | SLASH | **DEFAULT** (ghosts/spirits fall through) |
| Ing | SLASH | **DEFAULT** |
| Lich | BLUDGEON | keyword `lich` (skeletal/undead bucket) |
| Zombone | BLUDGEON | keyword `bone`, matched as a substring and happened to be right |
| Coelecite | BLUDGEON | keyword `coelecite` (golem/rock bucket) |
| Ninja | SLASH | **DEFAULT** |

3 keyword-inferred, 3 defaulted, 0 authored. Unlike Vector, where `rhino`
matched wrongly on Rhinox, the keywords here all produced defensible answers,
but two of the three did so by luck (`bone` matching "Zombone", an exact-name
entry for Coelecite). The two DEFAULT slash rows sit on the two bodies
whose fiction least supports a sword: a ghost, and a ghoul that comes three at
a time.

---

## 5. Key shares by encounter frequency

Equal-map weight = rate weight throughout (§0).

### 5.1 Class axis, current floor

| class | share of draws keyed | share of bodies |
|---|---|---|
| slash | 65.63 % | 52.91 % |
| bludgeon | 65.63 % | 47.09 % |
| pierce | **0.00 %** | 0.00 % |
| special ¤ | 0.00 % | 0.00 % |

Pierce, which is Locke's default attack and Edgar's entire Tools kit, keys
nothing anywhere in the area.

### 5.2 Element axis, vanilla data

| element | key in % of draws | feeds an absorber in % of draws |
|---|---|---|
| **pearl** | **90.63 %** | 0.00 % |
| ice | 40.63 % | 0.00 % |
| water | 34.38 % | 0.00 % |
| fire | 31.25 % | **84.38 %** |
| bolt | 0.00 % (Ninja only, off-draw) | 0.00 % |
| poison | 0.00 % | 90.63 % |

The only formation with no pearl-weak body is `$09a` (Coelecite ×3, 37.5 %
of map 385), which is keyed by ice. Fire's 31.25 % is Zombone; in the mixed
`$097` fights (Ing ×2 + Zombone) a fire splash heals two bodies while chipping
one, so fire is a single-target key only, the same shape as the Mag Roader
fights.

---

## 6. The party, and what it can field

Owner ruling: TERRA, LOCKE, EDGAR, SABIN. Terra is a hard requirement at the
base entrance; Setzer is benched.

### 6.1 Classes

All game-wide equippable, from `item_prop_en.dat` +1 equip masks and
`Ot6WeapClassTbl`/`Ot6SkillClassTbl` (recomputed via the checker's own
parser):

| class | who | cost |
|---|---|---|
| slash | Terra's and Locke's sword lines; Sabin's claws | free |
| pierce | Locke's daggers (his default attack); Edgar's spears + AutoCrossbow/Drill/Air Anchor | free |
| bludgeon | Sabin's fists and Pummel/Suplex (guaranteed, since he is in the ruled party); Terra's Flail `$44`/Morning Star `$46`; Locke's Full Moon `$45`/Boomerang family; bare fists are a bludgeon probe for anyone (`Ot6WeapClassTbl[$ff]`) | free |
| special ¤ | Setzer only, and he is benched | not assumable; 0 % is correct |

Every class is free for this party; no shop trip is required.

### 6.2 The element ring

Espers owned entering v0.7: Ramuh (Zozo, `event_main.asm:25789`;
Siren/Kirin/Stray grant sites exist at `:26463-26487` but whether the
driven chain collects them is checkpoint state, not asserted here — no key
below depends on them), Ifrit + Shiva (facility), and the six tube stones
Maduin/Phantom/Unicorn/Bismark/Carbunkl/Shoat (`:95777-95782`,
granted-while-worn under M5, `genju_prop.asm:56-66`).

- Pearl is reachable today, through Sabin's AuraBolt. Blitz #2, learned at
  level 6 (`BlitzLevelTbl`, `field/event.asm:1239`; Sabin is ~L15-16 by
  this point, `wob-route.md` measured tail), element pearl in the spell
  data (`magic_prop_en.dat` record `$5e` +1 = `$20`; layout
  `battle_main.asm:6918-6921`), priced at 5 MP in `Ot6AbilityCostTbl`
  (`ot6_boost.asm:478`, its own comment: *"AuraBolt L6 holy chip"*). It is
  already used as break data elsewhere: Vargas's `Ot6ElemAddTbl` holy
  add exists because "aurabolt already carries it"
  (`ot6_break.asm:121-127`, row at `:338`), proven at runtime by
  `battle_vargas.lua`. `kits.md`'s Sabin entry lists it as his holy chip.
  Single target, magic damage.
- **Ice** — Shiva's granted Ice (`genju_prop.asm:116`), Maduin's Ice2
  (`:128`), Bismark's Ice (`:131`).
- **Fire** — Terra's natural Fire (L3, `field/event.asm:1249`), Ifrit,
  Maduin, Bismark. It is a key on Zombone only, and feeds every other species.
- **Water** — **Bismark's summon** (esper 7 → attack `$3d`, the
  esper-index+`$36` mapping verified at `battle_main.asm:14382-14389`;
  `magic_prop_en.dat $3d` +1 = `$80` water, power 58). Once per battle, but
  a real key on Ing.
- **Bolt** — Ramuh. It keys nothing in the random draws and keys the Ninja.
- **Poison** — Edgar's Bio Blaster, Shoat's Bio. Do not use them here: 4 of 5
  species absorb poison.

MP note: AuraBolt at 5 MP against pools of ~40-60 at this stage is ~10 casts
per pool, and MP is universal with Osmose income on Shiva. The key does not
depend on running out of MP.

---

## 7. The pearl/holy question, resolved

The area appears to be keyed on pearl/holy, an element no kit here can
produce. Three options, with the math for each:

### (a) Authored class rows carry the area physically

The §8 rows make every formation chippable by a free class for the ruled
party — slash/pierce/bludgeon all cost nothing (§6.1). Under (a) alone the
element axis is flavor and the area works with zero MP. The rows are needed
regardless of the pearl answer, since formula-4 shields and two DEFAULT rows
are the same quality problem Vector had, but as the whole answer this option
discards the element structure vanilla supplies here: a 90.63 % master key
with no absorb overlap.

### (b) A holy-adjacent key through the tube espers

The grant that would close the gap: Unicorn (esper 23) grants base-tier
`PEARL` (`ATTACK::PEARL = $0e`, `const.inc:611`; 40 MP, power 108 in
`magic_prop_en.dat`), one `make_genju_prop` slot alongside a trimmed
support list, which is how his row is authored (`magicite-tube-six.md` §9).
The fiction fits (the holy horn, and the stones freed from the tubes lead to
their own gate), and Alexandr granting Pearl later is the same kind of overlap
as Ramuh/ZoneSeek. Carbunkl is the weaker candidate: its identity is Reflect,
and nothing in its kit or fiction is holy.

As the primary answer it fails on price: 40 MP a cast is most of a pool
at this level, against AuraBolt's 5. It is flavour coupling rather than the
key. It does give wearer-agnostic holy, since Terra or Locke can wear the
stone, which reduces the dependence on Sabin noted in §9.

### (c) The vanilla-data key, which is the answer

Sabin's AuraBolt is a pearl chip today (§6.2), and Sabin is in the ruled
party, so there is no gap:

| species | elemental keys reachable today |
|---|---|
| Apparite | pearl (AuraBolt), ice (Shiva/Maduin/Bismark) |
| Lich | pearl (AuraBolt), its only element, and it is covered |
| Ing | pearl (AuraBolt), water (Bismark summon) |
| Zombone | pearl (AuraBolt), fire (Terra's fire lean, her one correct target here) |
| Coelecite | ice (Shiva/Maduin/Bismark) |
| Ninja | pearl (AuraBolt), bolt (Ramuh) |

Recommendation: (c) + (a). Ship the area on vanilla elements plus the
§8 class rows, with no element add and no new spell grant required.
The encounter math: AuraBolt alone keys 90.63 % of draws at 5 MP; the
remaining 9.37 % (`$09a`, Coelecite ×3) is keyed by ice, which three owned
stones grant; the class rows key 100 % of draws for a party with no MP. What
the area teaches: Sabin's holy fist is the master key to an undead cave, and
Terra's fire feeds the absorbers. That puts the spotlight on a character the
ruled party seats, in the area whose gate is about espers.

Considered and rejected: adding pearl to Coelecite via `Ot6ElemAddTbl` (it
is a rock rather than a corpse, and giving the one non-undead fight the
master key removes the area's only fight where pearl is the wrong choice);
a cure-spell-chips-undead mechanic (vanilla's undead-heal reversal is a
damage-side flag, not an element byte, and the chip path keys on the weak
byte, so this needs new battle code for an area that has no gap).

---

## 8. Proposed `Ot6ShieldTbl` rows, not landed

Format per the existing table: `.word` species, `.byte` shields,
`.byte` class mask.

| species | id | shields | class mask | rationale |
|---|---|---|---|---|
| Apparite | `$06e` | 2 | `OT6_SLASH\|OT6_PIERCE` | A shade has no anatomy, so a blade's edge or point both disperse it. It is the cave-mouth body on both entrance maps, so it shows that blades still work on the hollow dead before the bone and stone bodies drop them. Ice and pearl are both second keys. |
| Ing | `$048` | 2 | `OT6_PIERCE` | The swarm body: 32.6 % of all bodies, ×3 at 37.5 % on two maps. A walking corpse is pinned, and pierce makes Edgar's AutoCrossbow (whole side, chips per hit) the intended swarm answer, following the Pipsqueak row (`break-coverage-vector.md` §8.1). Pearl and water are second keys. |
| Lich | `$0e5` | 2 | `OT6_BLUDG` | A robed skeleton, so bones shatter. The keyword produced the right answer; this makes it authored. Its element is pearl only, so the class row is the whole non-AuraBolt path, and bludgeon does not depend on Sabin (fists are universal, plus Terra's Flail and Locke's Full Moon). |
| Zombone | `$082` | 2 | `OT6_BLUDG` | 1991 HP, the largest trash body in any authored area. A dragon of dry bone, so it is broken apart. Fire is Terra's one correct elemental target here and pearl is a second key. The `bone` keyword was right by substring accident; this row makes it deliberate. |
| Coelecite | `$0b3` | 2 | `OT6_BLUDG` | Stone rather than corpse, so it is cracked. Deliberately the area's one body with no pearl weakness: `$09a` (×3, 37.5 % of the timed-floor map) is the fight where the master key does nothing and Shiva's ice or a blunt swing must answer. Keep that. |
| Ninja | `$003` | 3 | `OT6_SLASH\|OT6_PIERCE` | The one real forced fight (battle 149, the 384 trap switch). A duelist is answered by blades. 1650 HP and a one-off ambush justify the wider window, following the blades-at-3 rows. Bolt (Ramuh) and pearl are second keys. |

No `Ot6ElemAddTbl` rows. Absorb discipline (`ot6_break.asm:180-184`): every
proposed class row was checked against +23/+24. Class rows cannot feed an
absorber, and no element is being added anywhere, so no chip trigger can land
on an absorber.

### 8.1 Resulting distribution

| class | current draws keyed | proposed | current bodies | proposed |
|---|---|---|---|---|
| slash | 65.63 % | **31.25 %** | 52.91 % | 20.35 % |
| pierce | **0.00 %** | **65.63 %** | 0.00 % | 52.91 % |
| bludgeon | 65.63 % | **65.63 %** | 47.09 % | 47.09 % |
| special ¤ | 0 | 0 | 0 | 0 |

Per-formation (elements = reachable-today set):

| map | p | contents | class keys | element keys |
|---|---|---|---|---|
| 382 | 31.25 % | Apparite ×2 | slash, pierce | ice, pearl |
| 382 | 31.25 % | Apparite, Coelecite, Lich | slash, pierce, bludgeon | ice, pearl |
| 382 | 37.50 % | Lich ×3 | **bludgeon only** | **pearl only** |
| 383 | 31.25 % | Apparite ×2 | slash, pierce | ice, pearl |
| 383 | 31.25 % | Apparite ×2, Lich ×2 | slash, pierce, bludgeon | ice, pearl |
| 383 | 37.50 % | Ing ×3 | **pierce only** | pearl, water |
| 384 | 31.25 % | Zombone ×2 | **bludgeon only** | fire, pearl |
| 384 | 31.25 % | Ing ×2, Zombone | pierce, bludgeon | pearl, water, fire (1-target) |
| 384 | 37.50 % | Ing ×3 | **pierce only** | pearl, water |
| 385 | 31.25 % | Zombone | **bludgeon only** | fire, pearl |
| 385 | 31.25 % | Ing ×2, Zombone | pierce, bludgeon | pearl, water, fire (1-target) |
| 385 | 37.50 % | Coelecite ×3 | **bludgeon only** | **ice only** |
| forced | — | Ninja | slash, pierce | bolt, pearl |

Every formation has at least two independent answers, and no formation is both
single-key and element-less; there is no equivalent of Vector's Rhinox pair
here.

---

## 9. Reachability, and the real costs

Under the current floor nothing is unbreakable for the ruled party: slash and
bludgeon cover all 12 formations and every member fields both, which is the
checker's bare pass (§10). The failure is the same quality failure as
Vector's: pierce at zero, two DEFAULT rows on the least sword-like bodies, and
formula-4 shields.

Under the proposal:

- 34.38 % of draws are bludgeon-only on the class axis (`$09c`, `$024`,
  `$096`, `$09a`). Each keeps a reachable element: pearl on the Liches and
  Zombones, ice on the Coelecites. Bludgeon itself is free for all four
  members (fists), so this is a variety cost, not a coverage cost.
- 18.75 % of draws are pierce-only (`$098` twice), answered by Locke's
  daggers and Edgar's crossbow, with pearl and water behind them.
- AuraBolt is concentrated on Sabin. If Sabin is dead or silenced, pearl
  is unavailable (Terra's natural Pearl is L57 in vanilla data, L30 in
  kits.md's unimplemented schedule; either way not at this point in the game).
  The area still works: every formation keeps a non-pearl answer. Unicorn's
  granted Pearl (§7(b)) makes holy wearer-agnostic at 40 MP a cast; it is
  optional, not required.
- Shield count 2 (Ninja 3) is UNMEASURED: the third area to inherit
  the finding that 4 is one chip too many. It needs its own sweep at a cave
  entry-point fixture (checkpoint H, map 386, is the natural place), with the
  mixed `$097`/`$09b` fights as the arms to test.
- Fixture assertions this implies (the §10.3 pattern): at the cave mouth,
  assert Sabin active (AuraBolt is the master key) and Terra active (the
  base entrance demands her anyway); assert Shiva
  and Bismark owned (the `$09a` ice key, the Ing water key).

---

## 10. The checker entry, and its verdict

`tools/check_break_reach.py` declares `"sealed-gate"` in its `AREAS`
table: one segment,
party TERRA/LOCKE/EDGAR/SABIN, maps 382/383/384/385, forced battle 149,
`min_formations` 13 (3 unique formations × 4 maps + the Ninja; `$099`,
`$097`, `$098` repeat across maps and are checked per map-group). Battles
121/122/123 are deliberately not declared: their offline decode is
dummy-only (`$17b`) and known to be suspect (the Shiva case), and their real
contents are unprobed. The entry's comment says to add them when that lands.

Verdict against current data:

- Bare run: passes, and the pass is narrow. All 13 formations carry a floor
  class (slash or bludgeon) that the party can field. That is a statement
  about the class axis only: the checker models weapon/ability classes, not
  elements, so the pearl question of §7 is outside its scope by design. The
  pass means no formation is class-unreachable, which is already true here;
  it does not mean the area is finished.
- Failure demonstration, using the tool's `--drop-class` option, which exists
  for this: `--area sealed-gate --drop-class bludg` fails with 4 problems,
  which are the four bludgeon-only formations (`$09c`, `$024`, `$096`,
  `$09a`). A future data drift that strips bludgeon coverage, or an
  authored-row typo, will be caught.

After the §8 rows land the bare run must still pass (every proposed mask is
fieldable by the ruled party); the row-landing commit should re-run it and
say so.

---

## 11. Cross-references

- **Battles 121/122/123** — scripted set pieces, contents in battle-event
  scripts, loseability unknown. This survey makes no claim about them beyond:
  their formation words decode to dummy `$17b` and they are excluded from the
  checker's entry until probed.
- **The tube espers**: §7(b) names one coupling, Unicorn granting base-tier
  `PEARL`, as flavour that is explicitly not required for this area's
  reachability.
- **The banquet fights** (26: Mega Armor, bolt|water; 27 ×3: Commando,
  bolt|water; 30: Sp Forces ×3, poison — all decoded and confirmed real)
  and the **southern-continent / Crescent Island world pools** are the
  milestone's remaining unsurveyed encounter surface, out of this
  survey's scope.

---

## 12. Follow-ups

1. Land the §8 rows with the area's implementation wave; re-run
   `check_break_reach.py` (must still pass) and add the runtime analogue of
   `battle_breakvector.lua` for this area, pinning `$09a` as the
   pearl-less ice fight and asserting pierce outranks its current zero.
2. Shield-count sweep (2 vs formula 4; Ninja 3) at the checkpoint-H entry point.
3. Fixture asserts: Sabin+Terra active, Shiva+Bismark owned (§9).
4. One runtime check that the flashback cutscene maps (381, and v0.6's
   265/267/268) never take a danger-checked step.
5. When the 121/122/123 probe lands, extend the `sealed-gate` entry's
   `events` list with whatever real formations they carry.
6. The banquet trio and the two world areas need their own coverage pass.
7. `gen_break_floor.py`'s three-way review output (`break-coverage-vector.md`
   §10.2 item 1) would have surfaced Apparite/Ing/Ninja as DEFAULT rows on
   this route automatically; still worth building.
