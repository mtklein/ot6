# Break band — the Cave to the Sealed Gate (survey + proposed rows)

Issue #31, v0.7 scope, the #11 pattern (`break-band-vector.md` is the model).
**PROPOSAL ONLY — nothing here is landed.** The six rows in §8 are not in
`Ot6ShieldTbl`; they land with the band's implementation wave. The one thing
that ships with this survey is the `sealed-gate` entry in
`tools/check_break_reach.py` `BANDS`, which gates the *current* data honestly
(§10).

Everything below was decoded from the vendored data under `ff6/` on
2026-07-28 in a clean worktree at 97f6d6e. Every species byte, map byte,
group word, formation record and arithmetic figure was recomputed from
`sub_battle_group.dat` / `rand_battle_group.dat` / `battle_monsters.dat` /
`monster_prop.dat` / `map_prop.dat` and the entrance `.dat` pair — not read
off `sealed-gate-recon.md` §3.2 (which it nonetheless confirms, with the
corrections in §1.2). `monster_prop.dat +23` is absorb, `+25` is weak
(`docs/HANDOFF.md:107`, canonical). Where a claim is an inference it is
labelled.

---

## 0. Decode chain and weights

Per `break-band-vector.md` §1: `map_prop.dat[map*33]` byte 5 bit 7 =
random-battle enable → `SubBattleGroup[map]` (`field/battle.asm:392`) →
`RandBattleGroup[group*8]`, four formation words drawn at
**31.25 / 31.25 / 31.25 / 6.25 %** (`field/battle.asm:398-408`) →
`BattleMonsters[formation*15]` → `MonsterProp[species*32]`.

Per-step rate: all four encounter maps carry rate code 0 → `$0070`
(`sub_battle_rate.dat`; table `SubBattleRateTbl` verified at
`field/battle.asm:259-262`, read at `:375-376`). **Because every map in the
band has the same rate, equal-map weight and rate weight are the same
number**, and the OT6 danger multiplier (`Ot6DangerMulW`,
`ot6_break.asm:644-671`) cancels out of every share below. This band has
none of the Vector band's two-rate split.

Forced battles decode through `event_battle_group.dat[battle*4]`, word 0 at
75 % / word 1 at 25 % (`field/event.asm` `EventBattle`, per the checker
header).

---

## 1. The band's map set, verified from data

### 1.1 The encounter-bearing maps: exactly four

| map | title | enable | group | rate | pool |
|---|---|---|---|---|---|
| 382 | CAVE TO THE SEALED GATE | **Y** | 92 | `$0070` | Apparite, Coelecite, Lich |
| 383 | BASEMENT 1 | **Y** | 93 | `$0070` | Apparite, Lich, Ing |
| 384 | BASEMENT 3 | **Y** | 94 | `$0070` | Zombone, Ing |
| 385 | BASEMENT 2 | **Y** | 95 | `$0070` | Zombone, Ing, Coelecite |
| 386 | BASEMENT 4 (save room) | n | 92 | — | carries a group, cannot draw it |
| 391 | SEALED GATE | n | 0 | — | the scene room; no encounters |
| 377/378 | IMPERIAL BASE | **n** | 110 | — | **the base has no encounters at all** |

**The Imperial Base contributes nothing to the band.** Maps 377/378/379 have
the enable bit clear. The whole random-encounter surface of v0.7's interior
legs is these four cave maps plus one forced ambush (§2.2).

### 1.2 Recon corrections

- **The dispatch's "base 381" is wrong twice over.** The Imperial Base is
  maps **377/378** (`sealed-gate-recon.md` leg 2, confirmed by the entrance
  scan: world `(165,194)→377`, `(166,194)→377 (30,13)`, `377 (13,18)→378`).
  Map **381** is a Sealed-Gate-*tileset* cutscene map used only by the
  Esper-World flashback (`load_map 381` at `event_main.asm:11909`, in the
  Maduin/Madonna sequence; likewise 389 at `:11755`, 390 at `:11432`). No
  entrance record targets 379/380/381/387/388/389/390 (full scan of
  `trigger/short_entrance.dat` + `trigger/long_entrance.dat`, record layouts
  `include/field/short_entrance.inc:9-18` / `long_entrance.inc:9-18`), and no
  other `load_map` reaches them.
- **Four more maps carry live-looking encounter bytes but are dead**, the
  map-275 pattern from v0.6: **387** (enable Y, group 93) and **388**
  (enable Y, group 94) are unreachable cave duplicates; **380** (enable Y,
  group 110 → ChickenLip ×5, formation `$095`) and **381** (enable Y,
  group **0** — the Narshe overworld pool) are unreachable or
  cutscene-only. Map 381 is the band's copy of the v0.6 maps-265/267/268
  anomaly: if the flashback ever took a danger-checked step there it would
  draw level-5 Narshe trash. Inference, same as v0.6: scene choreography
  never takes a free step, so it never rolls. Not authored for; worth the
  same one runtime check.
- **`sealed-gate-recon.md` §3.2's pools, species stats and rates all
  reproduce exactly** — formations, counts, levels, HP, absorb/weak bytes,
  `$0070` rates. The recon's one substantive error is the reachability
  claim its design question rests on (§7).

### 1.3 The forced battles

| fight | where | formation | contents | in this survey? |
|---|---|---|---|---|
| battle 149 | 384 (66,11) trap switch (`event_main.asm:45177`) | `$20c` (both words) | **Ninja `$003`** ×1 | **yes** — real body, §3 |
| battle 121/122 | map 391 gate scene | `$180`/`$181` | dummy `$17b` L1 HP1 | no — battle-event contents, **being probed by a separate agent**; this survey deliberately decides nothing about them |
| battle 123 | Blackjack deck | `$182` | dummy `$17b` | no — same |

The banquet fights (26/27/30) and the two world bands (southern continent,
Crescent Island) are outside this survey's scope; §12 flags them as the
remaining #11-shaped debt of the milestone.

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

2.6875 bodies per draw. Ing is the band's swarm body — ×3 at 37.5 % on two
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

The vanilla data tells one story three times:

- **Pearl is the master key**: 4 of 5 random species (and the Ninja) are
  pearl-weak, and *nothing absorbs or nulls it*. 90.63 % of draws contain a
  pearl-weak body (§5).
- **Fire and poison are traps**: fire is absorbed by 4 of 5 species
  (84.38 % of draws feed a fire-splash) and poison by 4 of 5 plus the
  Ninja. This band forces Terra into the party (the base gate,
  `sealed-gate-recon.md` headline 3) and then punishes her fire lean
  (`kits.md` §Terra) — the Zozo poison inversion again, and worth keeping.
- **The exception is deliberate-looking**: Coelecite, the one body with no
  pearl weakness, is also the one whose absorb set (fire only) admits ice —
  and it is a *rock*, not a corpse. Vanilla built the "one fight your master
  key doesn't answer" body already.

Shield counts as they stand: levels 20-21 give `2 + level/8` = **4**
(`ot6_break.asm` `@formula`); Ninja at 27 gives 5. Both prior authoring
passes measured 4 as one-too-many on trash and landed on 2
(`balance-metrics.md:944-972`, `ot6_hud.asm:1489-1510`, `break-band-vector.md`
§8.2 — the third band to inherit that finding unmeasured, see §9).

---

## 4. What the generated floor currently says

No band species has an `Ot6ShieldTbl` row today (scanned `ot6_hud.asm`; also
visible in the checker's `[floor]` provenance tags).

| species | current class | how (`ff6/tools/gen_break_floor.py` keyword lists) |
|---|---|---|
| Apparite | SLASH | **DEFAULT** (ghosts/spirits fall through) |
| Ing | SLASH | **DEFAULT** |
| Lich | BLUDGEON | keyword `lich` (skeletal/undead bucket) |
| Zombone | BLUDGEON | keyword `bone` — fired on a substring and *happened* to be right |
| Coelecite | BLUDGEON | keyword `coelecite` (golem/rock bucket) |
| Ninja | SLASH | **DEFAULT** |

3 keyword-inferred, 3 defaulted, 0 authored. Unlike Vector (where `rhino`
fired wrong on Rhinox) the keywords here all landed on defensible answers —
but two of the three are luck (`bone` matching "Zombone", an exact-name
entry for Coelecite), and the two DEFAULT slash rows sit on the two bodies
whose fiction least supports "just swing a sword": a ghost and a ghoul that
comes three at a time.

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

Pierce — Locke's A button and Edgar's entire Tools kit — has literally no
work anywhere in the band.

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
of map 385) — ice-keyed. Fire's 31.25 % is Zombone; in the mixed `$097`
fights (Ing ×2 + Zombone) a fire *splash* heals two bodies while chipping
one, so fire is a single-target key only — the Mag Roader lesson shape.

---

## 6. The party, and what it can actually field

Dispatcher ruling (issue #31): **TERRA, LOCKE, EDGAR, SABIN** — Terra is a
hard gate at the base entrance, Setzer is benched.

### 6.1 Classes

All game-wide equippable, from `item_prop_en.dat` +1 equip masks and
`Ot6WeapClassTbl`/`Ot6SkillClassTbl` (recomputed via the checker's own
parser):

| class | who | cost |
|---|---|---|
| slash | Terra's and Locke's sword lines; Sabin's claws | free |
| pierce | Locke's daggers (A button); Edgar's spears + AutoCrossbow/Drill/Air Anchor | free |
| bludgeon | **Sabin's fists and Pummel/Suplex** (guaranteed — he is in the ruled party); Terra's Flail `$44`/Morning Star `$46`; Locke's Full Moon `$45`/Boomerang family; bare fists are a bludgeon probe for anyone (`Ot6WeapClassTbl[$ff]`) | free |
| special ¤ | Setzer only — benched | not assumable, correctly at 0 % |

Every class is free for this party; no shop trip is load-bearing.

### 6.2 The element ring — including what the recon missed

Espers owned entering v0.7: Ramuh (Zozo, `event_main.asm:25789`;
Siren/Kirin/Stray grant sites exist at `:26463-26487` but whether the
driven chain collects them is anchor state, not asserted here — no key
below depends on them), Ifrit + Shiva (facility), and the six tube stones
Maduin/Phantom/Unicorn/Bismark/Carbunkl/Shoat (`:95777-95782`,
granted-while-worn under M5, `genju_prop.asm:56-66`).

- **Pearl — REACHABLE TODAY: Sabin's AuraBolt.** Blitz #2, learned at
  **level 6** (`BlitzLevelTbl`, `field/event.asm:1239`; Sabin is ~L15-16 at
  the band, `wob-route.md` measured tail), element **pearl** in the spell
  data (`magic_prop_en.dat` record `$5e` +1 = `$20`; layout
  `battle_main.asm:6918-6921`), priced at **5 MP** in `Ot6AbilityCostTbl`
  (`ot6_boost.asm:478`, its own comment: *"AuraBolt L6 holy chip"*). It is
  already load-bearing break data elsewhere: Vargas's `Ot6ElemAddTbl` holy
  add exists *because* "aurabolt already carries it"
  (`ot6_break.asm:121-127`, row at `:338`), proven at runtime by
  `battle_vargas.lua`. `kits.md:93` lists it as Sabin's holy chip. Single
  target, magic damage.
- **Ice** — Shiva's granted Ice (`genju_prop.asm:116`), Maduin's Ice2
  (`:128`), Bismark's Ice (`:131`).
- **Fire** — Terra's natural Fire (L3, `field/event.asm:1249`), Ifrit,
  Maduin, Bismark. Right on Zombone alone; feeds everything else.
- **Water** — **Bismark's summon** (esper 7 → attack `$3d`, the
  esper-index+`$36` mapping verified at `battle_main.asm:14382-14389`;
  `magic_prop_en.dat $3d` +1 = `$80` water, power 58). Once per battle, but
  a real key on Ing. The recon missed this too.
- **Bolt** — Ramuh; dead on the draws, right on the Ninja.
- **Poison** — Edgar's Bio Blaster, Shoat's Bio: **do not bring them out**;
  4 of 5 species absorb.

MP note: AuraBolt at 5 MP against band pools of ~40-60 is ~10 casts per
pool, and MP is universal now (97f6d6e) with Osmose income on Shiva. The
key is not gated on a resource cliff.

---

## 7. The pearl/holy question, resolved

The recon (`sealed-gate-recon.md` §3.2) framed the band as "keyed on
pearl/holy — an element no kit in the band can currently produce" and the
dispatch asked for three options. Laid out with the math:

### (a) Authored class rows carry the band physically

The §8 rows make every formation chippable by a free class for the ruled
party — slash/pierce/bludgeon all cost nothing (§6.1). Under (a) alone the
element axis is flavor and the band works with zero MP. This is necessary
regardless of the pearl answer (formula-4 shields and two DEFAULT rows are
the same quality debt Vector had), but as the *whole* answer it wastes the
best element story vanilla has handed any band yet: a 90.63 % master key
with zero absorb overlap.

### (b) A holy-adjacent key through the tube-esper redesign

The exact grant that closes the hole: **Unicorn (esper 23,
`genju_prop.asm:183-184`) grants base-tier `PEARL`** (`ATTACK::PEARL =
$0e`, `const.inc:611`; 40 MP, power 108 in `magic_prop_en.dat`) — one
`make_genju_prop` slot, e.g. `{PEARL, 0}` alongside a trimmed support list.
Fiction is clean (the holy horn; the stones freed from the tubes light the
road to their own gate) and Alexandr granting Pearl later is the
established Ramuh/ZoneSeek-style overlap. Carbunkl is the weaker candidate
— its identity is Reflect, nothing in its kit or fiction says holy.

But as the *load-bearing* answer, (b) has two costs: 40 MP a cast is most
of a band-level pool (against AuraBolt's 5), and it sequences this band's
reachability behind a redesign being authored in parallel by another agent.
Recommend it to that agent as **flavor coupling, not as the key**: if
Unicorn gains Pearl, wearer-agnostic holy becomes available (Terra or Locke
can wear the stone), which softens the single-point-of-Sabin note in §9.

### (c) The vanilla-data key the recon missed — and it is the answer

**Sabin's AuraBolt is a pearl chip today** (§6.2), and Sabin is in the
party by dispatcher ruling. The claimed hole does not exist for the ruled
party:

| species | elemental keys reachable today |
|---|---|
| Apparite | pearl (AuraBolt), ice (Shiva/Maduin/Bismark) |
| Lich | pearl (AuraBolt) — its only element, and it is covered |
| Ing | pearl (AuraBolt), water (Bismark summon) |
| Zombone | pearl (AuraBolt), fire (Terra's own lean — her one clean target) |
| Coelecite | ice (Shiva/Maduin/Bismark) |
| Ninja | pearl (AuraBolt), bolt (Ramuh) |

**Recommendation: (c) + (a).** Ship the band on vanilla elements plus the
§8 class rows; adopt no element add and no new spell grant as load-bearing.
The encounter math: AuraBolt alone keys 90.63 % of draws at 5 MP; the
remaining 9.37 % (`$09a`, Coelecite ×3) is keyed by ice, which three owned
stones grant; the class rows key 100 % of draws for an MP-empty party. The
band's teaching writes itself: *the monk's holy fist is the master key to
an undead cave, the esper mage's favorite button feeds it* — a designed
spotlight for the character the dispatcher just seated, in the band whose
gate is about espers.

Considered and rejected: adding pearl to Coelecite via `Ot6ElemAddTbl` (it
is a rock, not a corpse; flattening the one non-undead fight onto the
master key deletes the band's only "wrong button" lesson on the pearl
axis); a cure-spell-chips-undead mechanic (vanilla's undead-heal reversal
is a damage-side flag, not an element byte — the chip path keys on the
weak byte, so this needs new battle code for a band that has no hole).

---

## 8. Proposed `Ot6ShieldTbl` rows — NOT LANDED

Format per the existing table: `.word` species, `.byte` shields,
`.byte` class mask.

| species | id | shields | class mask | rationale |
|---|---|---|---|---|
| Apparite | `$06e` | 2 | `OT6_SLASH\|OT6_PIERCE` | A shade has no anatomy: any blade's edge or point disperses it. The cave-mouth body (both entrance maps) teaches "blades still work on the *hollow* dead" before bone and stone retire them. Ice and pearl both back it. |
| Ing | `$048` | 2 | `OT6_PIERCE` | The swarm body — 32.6 % of all bodies, ×3 at 37.5 % on two maps. Pin the walking corpse; Edgar's AutoCrossbow (whole side, chips per hit) is the designed swarm answer — the Pipsqueak precedent (`break-band-vector.md` §8.1). Pearl and water back it. |
| Lich | `$0e5` | 2 | `OT6_BLUDG` | A robed skeleton: bones shatter. The keyword got it right; make it authored. Its element is pearl *only*, so the class row is the whole non-AuraBolt path — and bludgeon is not Sabin-locked (fists are universal, Terra's Flail, Locke's Full Moon). |
| Zombone | `$082` | 2 | `OT6_BLUDG` | **The flagship body**: 1991 HP, the largest trash body in any authored band. A dragon of dry bone — you break it apart. Fire is Terra's one clean elemental target here; pearl backs it; the `bone` keyword was right by substring accident, this makes it right on purpose. |
| Coelecite | `$0b3` | 2 | `OT6_BLUDG` | Stone, not corpse — crack it. Deliberately the band's one pearl-less body: `$09a` (×3, 37.5 % of the timed-floor map) is the fight where the master key does nothing and Shiva's ice or a blunt swing must answer. Keep that. |
| Ninja | `$003` | 3 | `OT6_SLASH\|OT6_PIERCE` | The one real forced fight (battle 149, the 384 trap switch). A duelist answers to blades; 1650 HP and a one-off ambush earn the wider window (the blades-at-3 precedent). Bolt (Ramuh) and pearl back it. |

No `Ot6ElemAddTbl` rows. Absorb discipline (`ot6_break.asm:180-184`): every
proposed class row was checked against +23/+24 — class rows cannot feed,
and no element is being added anywhere, so nothing can put a chip trigger
on an absorber.

### 8.1 Resulting distribution

| class | current draws keyed | proposed | current bodies | proposed |
|---|---|---|---|---|
| slash | 65.63 % | **31.25 %** | 52.91 % | 20.35 % |
| pierce | **0.00 %** | **65.63 %** | 0.00 % | 52.91 % |
| bludgeon | 65.63 % | **65.63 %** | 47.09 % | 47.09 % |
| special ¤ | 0 | 0 | 0 | 0 |

Per-formation, the table to argue with (elements = reachable-today set):

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

Every formation has at least two independent answers; no formation is
single-key-and-element-less (Vector's Rhinox pair has no analogue here).

---

## 9. Reachability, and the honest costs

Under the **current** floor nothing is unbreakable for the ruled party
(slash+bludgeon cover all 12 formations, and everyone fields both — the
checker's bare pass, §10). The failure is the same quality failure as
Vector's: pierce at literal zero, two DEFAULT rows on the least-slashable
fictions, formula-4 shields.

Under the proposal:

- **34.38 % of draws are bludgeon-only on the class axis** (`$09c`, `$024`,
  `$096`, `$09a`). Each keeps a reachable element: pearl on the Liches and
  Zombones, ice on the Coelecites. Bludgeon itself is free for all four
  members (fists), so this is a texture cost, not a coverage cost.
- **18.75 % of draws are pierce-only** (`$098` twice) — Locke's A button,
  Edgar's crossbow, with pearl and water behind them.
- **AuraBolt concentrates on Sabin.** If Sabin is dead or silenced, pearl
  is gone (Terra's natural Pearl is L57 vanilla data / L30 in kits.md's
  unimplemented schedule — either way not at band level). The band still
  stands: every formation keeps a non-pearl answer. If the esper agent
  adopts §7(b)'s Unicorn-grants-Pearl, holy also becomes wearer-agnostic;
  nice-to-have, not load-bearing.
- **Shield count 2 (Ninja 3) is UNMEASURED** — the third band to inherit
  the 4-is-one-too-many finding. Needs its own sweep at a cave doorstep
  fixture (anchor H, map 386, is the natural place), with the mixed
  `$097`/`$09b` fights as the interesting arms.
- Fixture assertions this implies (the §10.3 pattern): at the cave mouth,
  assert Sabin active (AuraBolt is the master key) and Terra active (the
  base gate demands her anyway, `sealed-gate-recon.md` §2.3); assert Shiva
  and Bismark owned (the `$09a` ice key, the Ing water key).

---

## 10. The checker entry, and its honest verdict

`tools/check_break_reach.py` now declares band `"sealed-gate"`: one leg,
party TERRA/LOCKE/EDGAR/SABIN, maps 382/383/384/385, forced battle 149,
`min_formations` 13 (3 unique formations × 4 maps + the Ninja; `$099`,
`$097`, `$098` repeat across maps and are checked per map-group). Battles
121/122/123 are deliberately **not** declared — their offline decode is
dummy-only (`$17b`) and known-suspect (the Shiva precedent), and their real
contents are another agent's probe; the entry's comment says to add them
when that lands.

Verdict against current data, run in this worktree:

- **Bare run: PASSES — honestly.** All 13 formations carry a floor class
  (slash or bludgeon) that the party can field. This is a true statement
  about the class axis and *only* the class axis: the checker models
  weapon/ability classes, not elements, so the pearl question of §7 is
  invisible to it by design. The pass is not "the band is fine"; it is
  "no formation is class-unreachable", which was already true here.
- **Failure demonstration (the tool's own `--drop-class` arm, built for
  exactly this):** `--band sealed-gate --drop-class bludg` fails loudly
  with 4 problems — precisely the four bludgeon-only formations (`$09c`,
  `$024`, `$096`, `$09a`). The entry has teeth; a future data drift that
  strips bludgeon coverage (or an authored-row typo) will be caught.
- The vector-factory band still passes 29 formations, unchanged.

After the §8 rows land the bare run must still pass (every proposed mask is
fieldable by the ruled party); the row-landing commit should re-run it and
say so.

---

## 11. Cross-references

- **Battles 121/122/123** — scripted set pieces, contents in battle-event
  scripts, loseability unknown; owned by the parallel probe agent. This
  survey makes no claim about them beyond: their formation words decode to
  dummy `$17b` and they are excluded from the checker band until probed.
- **The tube-esper redesign** (parallel agent): §7(b) names the one
  coupling — Unicorn granting base-tier `PEARL` — as recommended flavor,
  explicitly not load-bearing for this band's reachability.
- **The banquet fights** (26: Mega Armor, bolt|water; 27 ×3: Commando,
  bolt|water; 30: Sp Forces ×3, poison — all decoded and confirmed real)
  and the **southern-continent / Crescent Island world pools** are the
  milestone's remaining unsurveyed encounter surface, out of this
  survey's scope.

---

## 12. Follow-ups

1. Land the §8 rows with the band's implementation wave; re-run
   `check_break_reach.py` (must still pass) and add the runtime analogue of
   `battle_breakvector.lua` for this band, pinning `$09a` as the
   pearl-less ice fight and asserting pierce outranks its current zero.
2. Shield-count sweep (2 vs formula 4; Ninja 3) at the anchor-H doorstep.
3. Fixture asserts: Sabin+Terra active, Shiva+Bismark owned (§9).
4. One runtime check that the flashback cutscene maps (381, and v0.6's
   265/267/268) never take a danger-checked step.
5. When the 121/122/123 probe lands, extend the `sealed-gate` band's
   `events` list with whatever real formations they carry.
6. The banquet trio and the two world bands need their own #11 pass.
7. `gen_break_floor.py`'s three-way review output (`break-band-vector.md`
   §10.2 item 1) would have surfaced Apparite/Ing/Ninja as DEFAULT rows on
   this route automatically; still worth building.
