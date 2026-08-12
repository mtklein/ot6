# What LOCKE brings to his scenario, and where it comes from

Solo LOCKE fights the South Figaro gate soldier (battle 11). This file
records where his loadout comes from, what the route spends, and what the
ground before the three-way split is worth if it is played instead of fled.
Issue #100.

Until 2026-08-12 he arrived at level 8 with a Dirk and lost that fight on all
three attempts. He now arrives at level 10 with a MithrilBlade and a Heavy
Shld and wins it on the first, because the route stops in South Figaro the
way a player would: §8 is the grind outside the west gate, §6 is what it
pays for, §7 is the fight before and after.

Every number below is read from the generated fixtures with
`tools/savestate_party.py`'s reader (no emulator) or decoded from the
vendored data files, and each is attributed where it is stated.

---

## 1. The bag at the split holds exactly one weapon

At `locke_scenario` the shared inventory is:

| item | id | count | type | LOCKE can hold |
|---|---|---|---|---|
| Tonic | `$E8` | 5 | consumable | — |
| Gauntlet | `$D0` | 1 | relic | yes |
| Sleeping Bag | `$F6` | 2 | consumable | — |
| Bio Blaster | `$A4` | 1 | Tool | no (EDGAR) |
| NoiseBlaster | `$A3` | 1 | Tool | no (EDGAR) |
| AutoCrossbow | `$AA` | 1 | Tool | no (EDGAR) |
| Fenix Down | `$F0` | 4 | consumable | — |
| **Dirk** | **`$00`** | **1** | **weapon, power 26** | **yes** |
| Leather Hat | `$69` | 1 | helmet | yes |
| LeatherArmor | `$84` | 1 | armor | yes |

Item type is `item_prop_en.dat` byte `+$00` low nibble and the equip mask is
the 16-bit field at `+$01` (`docs/research/data-formats.md`); battle power is
`+$14` (`ItemProp+20`, `ff6/src/battle/battle_main.asm:2559`). Exactly one
entry is a weapon.

The Dirk, the Leather Hat and the LeatherArmor are LOCKE's own gear. The
story strips him when he leaves the party at the Returner Hideout
(`remove_equip` / `EventCmd_8d`) and returns the pieces to the bag: they are
absent from the bag at `returner_hideout` and present at `banon_joined`,
which is the same step his character record goes to all-`$FF`.

So `H.equipOptimum`'s report during `gen_sfigaro` — item `$00`, power 26, the
only weapon available — is complete and correct. There is nothing better in
the bag to find.

**The equipment audit's "LOCKE is bare" fixtures are stale, not wrong.**
`tools/audit_equipment.py` reports `gear FF FF FF FF FF` for him in every
`sfigaro_*` fixture, and that is what those files hold: `sfigaro_town.mss` is
dated 2026-07-22 in every worktree on this machine and in the owner's
checkout, and `gen_sfigaro` did not gain its `H.equipOptimum` stop until
`969894e` on 2026-08-09. A fixture generated before the code existed cannot
carry its effect. Regenerating the chain on 2026-08-12 shows the drive
working: `[locke kit] someone is bare-handed (c1=FF) -- opening Equip`, six
menu steps, `[locke kit] done: c1=00`. Nothing needs fixing in the audit or
in `gen_sfigaro`; the fixtures need regenerating, and they cannot be until
the fight in §7 is winnable.

## 2. The better weapons are equipped on characters in other scenarios

At the split the party's weapons are:

| character | weapon | power | in LOCKE's party |
|---|---|---|---|
| TERRA | MithrilKnife `$01` | 30 | no (raft scenario) |
| EDGAR | MithrilBlade `$0A` | 38 | no (raft scenario) |
| SABIN | MetalKnuckle `$53` | 55 | no (world scenario), and SABIN-only |
| LOCKE | none | — | yes |

`MetalKnuckle`'s equip mask is `$8020`, SABIN alone, so it was never a
candidate. The other two are held by characters the split sends elsewhere.

**No equip step put them there.** `equipOptimum` and `equipWeapon` appear in
none of `gen_kolts`, `gen_kolts_pool`, `gen_kolts_cave`, `gen_vargas`,
`gen_returner`, `gen_banon`, `gen_lete`, `gen_scenario` or
`gen_scenario_locke`. Those weapons are the gear the game equips at join
time, and nothing between Figaro Castle and the split moves it. The bag is
shared across the three scenarios, and what is in it is what nobody was
wearing.

## 3. No gil is missing

The purse rises monotonically from power-on to the split apart from
purchases. Measured across the chain regenerated 2026-08-11:

| fixture | gil | what changed |
|---|---|---|
| `figaro_cleared` | 3974 | |
| `south_figaro` | 3974 | **the cave crossing earns nothing** |
| `kolts_entry` | 474 | the South Figaro item shop, −3500 |
| `vargas_entry` | 3366 | Mt. Kolts, +2892 |
| `returner_hideout` | 4058 | +692 |
| `scenario_hub` | 6622 | the Lete River and ULTROS, +2564 |
| `locke_scenario` | 6622 | |

The 13,258 figure that this was compared against is from the fixture chain of
2026-07-22, which predates two changes: the South Figaro shopping stop
(`bc0a894`, 2026-08-09) and the conversion of the Figaro→Vargas route to
fleeing its encounters (`6997c7d`). The gap is a purchase plus gil the older
chain earned, not a leak. The purchase is 5 Fenix Downs at 500 and 20 Tonics
at 50 (`gen_kolts.lua`'s `shopTrip`).

## 4. LOCKE cannot gain a level after the split

Experience is `$1600 + 37*c + $11`, three bytes. Required experience is
`8 * sum(LevelUpExp[2..L])` (`CalcLevelExpTotal`,
`ff6/src/menu/status.asm:580-605`, whose tail shifts the sum left three
times); `LevelUpExp` is at `ff6/src/field/event.asm:1329`. That gives 1552 to
reach level 8, 2184 for level 9, 2976 for level 10.

| fixture | LOCKE | TERRA | EDGAR |
|---|---|---|---|
| `figaro_cleared` | L6, 814 | L5, 477 | L7, 1056 |
| `south_figaro` | L6, 814 | L5, 477 | L7, 1056 |
| `vargas_entry` | L8, 1575 | L7, 1238 | L8, 1817 |
| `returner_hideout` | L8, 1757 | L7, 1420 | L8, 1999 |
| `banon_joined` | L8, 1757 (out of party) | L7, 1420 | L8, 1999 |
| `scenario_hub` | **L8, 1757** | L9, 2234 | L9, 2813 |

Two things follow.

- **LOCKE is benched for the whole Lete River sequence.** He leaves the party
  at the Returner Hideout, so TERRA, EDGAR and SABIN each gain 814 experience
  on the river and ULTROS and he gains none. He arrives at his own scenario
  as the lowest-level member of the cast, **427 experience short of level 9**.
- **Nothing in his scenario can make that up.** Random battles need
  `map_prop.dat` byte `+5` bit 7 (`ff6/src/field/battle.asm:332`,
  `lda $0525 / bpl Done`). That byte is `$00` for every map LOCKE reaches
  before the gate soldier: 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85 and
  86. His level at battle 11 is fixed at `banon_joined` and cannot be
  changed after it.

So any level LOCKE is to have for that fight has to be earned before the
Returner Hideout, with the full party, and experience is divided by the
number of living allies (`ldx $3a76 ; number of allies alive` then `Div`,
`ff6/src/battle/battle_main.asm:15797-15803`). Gil is not divided.

**That window is open, and the route now uses it.** LOCKE is in the party
from Mt Kolts through the hideout, and the earliest encounter-bearing ground
in it is the world map outside South Figaro's west gate, where the town's
four shops and its inn are also standing. §8 has the corridor and what it
earns.

LOCKE's measured maximum HP by level, from the fixture tree:

| level | 6 | 8 | 9 | 10 | 11 | 13 | 14 | 15 |
|---|---|---|---|---|---|---|---|---|
| max HP | 122 | 168 | 194 | 221 | 249 | 314 | 353 | 397 |

## 5. The South Figaro cave is fought for nothing today

Experience and gil at `figaro_cleared`, `south_figaro` and `kolts_entry` are
identical for every character. The cave crossing (`gen_kolts`, maps 71 → 73 →
72 → world) passes `playBattles = "flee"` on every leg, and a fled fight pays
nothing. It is the only stretch of encounter-bearing ground between Figaro
Castle and the Returner Hideout that the route does not play.

What it is worth. The map's encounter group is `SubBattleGroup[map]`, the
four formations are `RandBattleGroup[8*group]`, and the draw is 31.25% /
31.25% / 31.25% / 6.25% (`ff6/src/field/battle.asm:392-408`). Formation
records are 15 bytes (`battle_main.asm:8243-8250`, `index*16 - index`), byte
`+1` the present mask and `+2..+7` the monster ids; per-monster experience
and gil are `MonsterProp+12` and `+14` (`battle_main.asm:7613-7615`).

**OT6 doubles both for random encounters**: `Ot6RewardScale_ext` multiplies
the experience and gil sums by `Ot6RewardMulW / 16`, and `Ot6RewardMulW` is
`$0020` (`ff6/src/battle/ot6_break.asm:695-696`, `:766-800`). The figures
below include that.

| map | group | formations | xp/fight | gil/fight |
|---|---|---|---|---|
| 73 (cave body) | 60 | Hornet/Bleary/Crawly, L6–7 | 462 | 688 |
| 72 (exit hall) | 59 | Hornet/Bleary/Crawly, L6–7 | 330 | 524 |
| 70 (far end) | 122 | Trilobiter/Primordite/Gold Bear, L11–13 | 486 | 610 |

Maps 72 and 73 are the ones the route crosses and their monsters are at or
below the party's level, which is not true of map 70. The model is
cross-checked against measured data two ways: it reproduces `gen_kolts`'s own
recorded "Cirpius at 93.75% of draws" for group 61, and Mt. Kolts's measured
`+2892` gil and `+761` LOCKE experience match four to five fights at the
group-61/62 rates.

At roughly 396 experience and 606 gil a fight on maps 72/73, with the
experience split three ways, three or four fights would give LOCKE the 427 he
needs for level 9 and about 1800–2400 gil.

**Measured, and it does not work out that way.** The crossing was switched to
`playBattles = "tactical"` on 2026-08-12 and `south_figaro` regenerated. The
whole cave drew **one fight**: gil 3974 → 4230, `+256`, and not a single
level — TERRA, LOCKE and EDGAR entered at 5/6/7 and left at 5/6/7. The route
through maps 73 and 72 is short, and the per-step danger counter barely
accumulates over it.

So the rates above are right per fight and the conclusion drawn from them was
wrong, because nobody had asked how many fights the crossing draws. Fighting
what the cave happens to offer pays about a sixth of one Star Pendant. Getting
1500 out of it means a deliberate pacing step that walks the cave until it has
drawn six fights, which is a different and larger piece of work than changing
a battle policy, and it has to justify its generation time.

That trial also cost the route its next contract: with one extra fight in the
stream, every later formation draw and battle seed shifts, and the same run
went on to lose LOCKE on the approach to VARGAS, spending all five Fenix Downs
and failing `char 1 reached VARGAS alive`. One sample cannot separate "the
change did this" from "the RNG moved", and the change was reverted rather than
kept on a coin toss. The lesson worth keeping is that this route's downstream
contracts are tight enough that inserting battles upstream is not free.

## 6. What the money buys, and what the route buys with it

South Figaro's four shops and its inn are all open at this point in the story
(`docs/research/south-figaro-shop-route.md` §0, §5, §7). Stock and row
indices, decoded from `shop_prop.dat`:

| shop | type | map | doorstep on 75 | talk spot | wanted item | row | price |
|---|---|---|---|---|---|---|---|
| 5 | Weapon | 77 | (29,19) | (103,11) | MithrilBlade `$0A`, power 38 | 2 | 450 |
| 6 | Armor | 77 | (35,19) | (114,12) | Heavy Shld `$5B`, def 22 / mdef 14 | 1 | 400 |
| 7 | Relics | 76 | (15,39) | (51,11) | Star Pendant `$B1` | 2 | 500 |
| 8 | Item | 85 | (44,32) | (106,54) | Fenix Down `$F0` | 5 | 500 |
| 8 | Item | 85 | | | Tonic `$E8` | 0 | 50 |
| inn | — | 76 | (15,39) | (81,19) | full HP + MP, every status cleared | — | 80 |

- **Star Pendant** is `item_prop_en.dat` `+$06 = $04`. `CalcEquipEffect`
  loads `ItemProp+6` into `$11D2`, the status 1 and 2 protection word
  (`ff6/src/battle/battle_main.asm:2513-2517`), and `STATUS1::POISON` is
  `BIT_2` (`ff6/include/const.inc:1491`). So it is poison immunity. Its
  equip mask is `$3FFF`, every actor. Three cover the Mt. Kolts party.
  Reaching the relic merchant needs the `$0358` demonstrator NPC talked to
  first: he stands on the only tile the shopkeeper can be counter-talked
  from (`south-figaro-shop-route.md` §7).
- **MithrilBlade** is the best weapon in shop 5 that LOCKE can hold.
  RegalCutlass is stronger at power 54 but its mask is `$8051` — TERRA,
  EDGAR and CELES only.
- **Heavy Shld** matters because LOCKE is the only member of this party with
  an empty left hand: measured at `south_figaro`, TERRA and EDGAR both carry
  Bucklers already and LOCKE's shield slot reads `$FF`.
- **The inn restores everything.** `_ca789f` → `_cacd3c` → `_cacf67` ends in
  `_cacfbd` (`event_main.asm:31862-31875`), which is `and_status
  {MAGITEK, INTERCEPTOR}` + `max_hp` + `max_mp` on all four slots: full HP,
  full MP, and every other persistent status bit cleared, KO and poison
  included.

### The 80 GP is paid on purpose: there is no free bed on this road

Every player-invocable rest in the script goes through `_cacd3c` or
`_cacd31`, which are the same routine with and without the sleep jingle, and
both end in `_cacf67` → `_cacfbd`. **So every rest in the game restores
exactly the same thing**, and a free one would be strictly better if one were
reachable. Fifteen call sites: twelve are preceded by `take_gil` in their own
branch (80 to 1500), one takes 1, and three are free —

| free rest | where | reachable from South Figaro |
|---|---|---|
| `EventTrigger::_59` `{47,52}` → `_ca71bf` | Figaro Castle, map 59 | no — different walkable region, and the castle submerges |
| `EventTrigger::_123` `{4,12}` → `_cb827d` | map 123, gated on `$0032` | no |
| `NPCProp::_109` / `_111` → `_caf64b` / `_caf64e` | **the Returner Hideout, maps 109 and 111** | not yet — it is the far end of this arc |

**Duncan's house is real, and it is inside the town.** Map 86's title index
(`map_prop.dat` byte 0 = `$1C`) is `map_title_en` 28, `DUNCAN'S HOUSE`, and
his wife is `NPCProp::_86`'s first record, the `OLD_WOMAN` at `{54,51}`
running `_ca7a90`; at this point in the story her branch is `_ca7b20`,
`dlg $00B9` — *"My husband, Duncan, is a world-famous martial artist! He's
taking his disciples to Mt. Kolts for meditation and training."* It is
entered from map 75 `(46,39)` → map 86 `(49,54)`, one door off the street
this route already walks, and `EventTrigger::_86` holds eight triggers, all
of them exit redirects. **There is no bed in it.**

**The hut on the road north of town has no bed either.** World `(90,99)` →
map 93 `(7,14)` is a real building between South Figaro and Mt Kolts, and it
is the one Sabin was staying in: its single NPC runs `_ca8198`, where the
MAN says he *"left a couple of days ago after he heard Master Duncan was
slain… He headed into the mountains."* `EventTrigger::_93` is **empty** — the
map has no triggers at all, so nothing on it can be slept in.

So the route pays the inn, deliberately. At 434 gil a lap the 80 GP is about
a fifth of one lap, and one rest across the whole 22-lap stop is under 1% of
what the stop earns. The thing worth carrying forward is the third row of
that table: **the Returner Hideout's beds are free**, which is where issue
#101's Lete River grind will want to rest.

**Taking EDGAR's MithrilBlade instead of buying one does not work**, and it
is worth writing down because it is the obvious saving. LOCKE carries
exactly one weapon into his solo scenario — `remove_equip` returns only what
he is *wearing* to the shared bag — and TunnelArmr, at the end of that
scenario, is `5, OT6_PIERCE` (`ff6/src/battle/ot6_hud.asm:1943`). Handing
him a slash blade and nothing else leaves that boss unbreakable by the party
that has to face it. Buying one leaves his own Dirk unequipped in the bag,
which does ride to the split, so he arrives with both classes. The gate
soldier's HeavyArmor is `3, OT6_SLASH|OT6_PIERCE` (`:2013`), so the blade
breaks it either way.

**The purse is no longer the constraint.** With 3974 at the counter the list
did not fit — three pendants alone are more than four times the
discretionary remainder after the existing 3650 of Fenix Downs, Antidotes
and Tonics. §8's grind changes the arithmetic rather than the list: the
route now buys the insurance first out of 3974, earns about 9500 more
outside the gate, and spends 4880 of it on the rest.

Measured on the chain of 2026-08-12, at the moment the party leaves town:

| | before | after |
|---|---|---|
| gil | 324 | 4996 |
| Tonic / Potion / Fenix Down / Antidote | 25 / 5 / 5 / 3 | 40 / 5 / 8 / 3 |
| LOCKE | L6, Dirk, no shield | L9, MithrilBlade, Heavy Shld, Star Pendant |
| TERRA / EDGAR | L5 / L7 | L8 / L9, both wearing Star Pendants |
| party HP and MP | walked in hurt | full, from the inn |

## 7. What battle 11 actually looks like

**With the stop in, LOCKE wins it on the first attempt, three times over.**
Measured 2026-08-12 on the regenerated chain: `gen_sfigaro` passes end to
end, and all three of its gate-soldier engagements (the opening fight and
the two re-fights the map-75 reloads force) are won on attempt 1. He arrives
at level 10 with 221 HP, equip Optimum arms him with the MithrilBlade the
route bought (`[locke kit] done: c1=0A`), and the opening fight runs
HeavyArmor 495 → 0 in about 7700 frames while his own HP sits at 170 of 221
from the third round onward. `sfigaro_town` and `sfigaro_passage` generate.

The fail-before, on the same day and the same ROM with the town stop removed:
all three attempts lost, three distinct battle RNG seeds (`$54`, `$A4`,
`$04`), and the assertion `battle 11 won within 3 attempts` red. That is the
state the Locke chain had been blocked in.

What the fight looked like when it was lost, for the record: LOCKE breaks the
armour and gets into the damage phase, and then loses a race. Chips do 5, the
breaking hit lands 92, ordinary Fights 22 and boosted ones 94. `OT6_BREAK_TICKS`
is `$10`, which is 2159 frames, and inside one window he took the soldier from
485 to 255. Then the window expired and all three shields came back. What ended
it was healing: his own HP went 168 → 113 → 27, he drank the bag's single
Potion back to 168, took 52 more, and sat at 116 until a row-exempt special of
111 or more killed him. The driver refused every Tonic on the way and said why:
*"$E8 restores 50 and a round costs 86, so the turn buys back less than it
spends"*.

Level 10 answers that directly. 221 maximum HP is the difference between one
special killing him from most of his bar and not, and the MithrilBlade's
power 38 against the Dirk's 26 shortens the race it has to be survived for.

**Two of the three losing attempts are suspect, and this is unresolved.**
In the fail-before run, attempts 1 and 3 both ended with the log reading
`monhp=0/sh0` — the HeavyArmor at zero — and LOCKE alive at 114 and 111 of
168, and both were scored `LOST (scenario reset) at (30,43)`. (30,43) is not
the reset tile; a real loss lands on (47,43), which is where attempt 2 ended.
`M.clearGateSoldier` decides a win by asking whether the party is off the
reset tile *and* `H.bfsPath` can reach the probe tile, and on those two
attempts the path query said no. The same test scored the same position a
win in the passing run. So either the fight was already winnable at level 8
on two seeds in three and the reachability probe called both wins losses, or
something ends that fight with the monster at zero and the lane still shut.
Nobody has instrumented it. Until somebody does, the honest statement is
that the fail-before was red and the after is green, and that the size of
the improvement the town stop is responsible for is not established.

## 8. The paced grind outside the west gate

The corridor, derived statically from `world_1_tilemap.dat` and
`WorldTileProp` and then walked by `tools/tests/probe_sfiggrind.lua`:

- The southern walkable region is **422 tiles** (the same figure
  `gen_kolts.lua`'s header records for the cave crossing, from an
  independent flood fill), 371 of them battle-bg 0 and 51 bg 3.
- Sector index is `(tileY & $E0) | ((tileX >> 3) & $1C)`
  (`ff6/src/field/battle.asm:122-136`); South Figaro's is 104, and
  `WorldBattleRate[26]` is `$00`, so **every tile in the region draws at the
  normal rate**. bg 0 selects `WorldBattleGroup[104] = 3` — GreaseMonk,
  Rhodox, Rhinotaur — and bg 3 selects group 4.
- Group 3 is worth an expected **358 experience and 720 gil a fight** once
  OT6's `Ot6RewardMulW = $0020` doubling is applied
  (`ff6/src/battle/ot6_break.asm:695-696`).
- The per-step danger increment is **halved** by the paired knob
  (`Ot6DangerMulW = $0008`, `:693-694`), so the world's vanilla `$00C0`
  becomes `$0060` and a fight is expected about every 37 steps.
- The lap is **(100,105) ↔ (87,105)**, 13 steps each way on row 105, with no
  world entrance or event trigger on it.

Two things had to be derived before it would run.

- **The first hop out of town is north.** Leaving by map 75's x=0 column
  lands at world (84,112), and (85,112) and (86,112) are two of South
  Figaro's own four entrance tiles (`short_entrance.dat`, world list). The
  23-step shortest path east from the exit has both on it, so a plan
  straight to the corridor walks back into the town. The route stages at
  (84,108) first, and `H.worldNavTo` has no `avoid` option to correct it
  with afterwards.
- **The grind stays on the world map.** The danger counter is zeroed by
  every battle and by every map load, so a lap that ducks into town throws
  away whatever it had accumulated.

Measured on the generated chain, 22 laps, about 39700 frames:

| | at `south_figaro` | after the grind |
|---|---|---|
| gil | 324 (post-shop) | 9876 |
| TERRA | L5, 94 HP | L8, 160 HP |
| LOCKE | L6, 122 HP, 814 xp | L9, 194 HP, 2364 xp |
| EDGAR | L7, 145 HP | L9, 195 HP |
| Tonics spent | — | 4 |

So **a lap is worth about 434 gil and 70 LOCKE experience**, and the whole
grind cost four Tonics — OT6 restores HP and MP in full on level up
(`ot6_progression.asm:3-6`), which is most of the healing a levelling party
needs, and the inn covers the rest for 80 GP.

The stop is bounded by LOCKE's experience rather than by a lap count: 2250,
which lands him at level 10 for the gate soldier once Mt Kolts, VARGAS and
the hideout have added their measured +943. It is a level or two, not an
open-ended grind, and 24 laps is the hard ceiling in the generator.

It cost `gen_kolts` its runtime: the generator now runs 87749 frames against
34642 before, which is past `run.sh`'s 600-second wall-clock default on a
loaded machine, so the savestate graph gained a `timeout=` field and those
three states use 1800.
