# What LOCKE brings to his scenario, and where it comes from

Solo LOCKE fights the South Figaro gate soldier (battle 11) with a Dirk at
level 8. This file records where that loadout comes from, what the route
spends, and what the ground before the three-way split is worth if it is
played instead of fled. Issue #100.

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
experience split three ways:

- **3 fights** ≈ 396 experience to LOCKE and ≈ 1820 gil.
- **4 fights** ≈ 528 experience to LOCKE and ≈ 2420 gil.

427 is what LOCKE needs for level 9, so three to four cave fights reach it.

## 6. What that money buys

South Figaro's four shops are all open at this point in the story
(`docs/research/south-figaro-shop-route.md` §0, §7). Stock and row indices,
decoded from `shop_prop.dat`:

| shop | type | map | wanted item | row | price |
|---|---|---|---|---|---|
| 5 | Weapon | 77 | MithrilBlade `$0A`, power 38 | 2 | 450 |
| 7 | Relics | 76 | Star Pendant `$B1` | 2 | 500 |
| 8 | Item | 85 | Fenix Down `$F0` | 5 | 500 |
| 8 | Item | 85 | Tonic `$E8` | 0 | 50 |

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

The budget at the shop, with 3974 gil:

| list | cost | left |
|---|---|---|
| 5 Fenix Down + 20 Tonic (as of `bc0a894`) | 3500 | 474 |
| the same plus 3 Antidote | 3650 | 324 |
| the same plus 3 Star Pendant | 5150 | **−1176** |
| the same plus 3 Star Pendant and a MithrilBlade | 5600 | **−1626** |

Three pendants do not fit today and cannot be made to fit by reordering the
list: they cost more than four times the whole discretionary remainder. With
three or four cave fights fought on the way in they fit with room, and so
does the MithrilBlade.

## 7. What this does not do

It does not win battle 11, and the arithmetic says so before anyone spends
generation time finding out.

`probe_battle11.lua` recorded solo LOCKE at level 8 taking 168 → 111 to the
soldier's first action and 111 → 0 to his second, the second being
row-exempt. Against the max-HP table in §4:

- level 9 (194) survives that pair with 26 left, so it buys one more action.
- surviving a third such hit needs more than 279 max HP, about level 12.
- surviving a fourth needs more than 390, about level 15.

Level 12 is roughly 3300 more experience for LOCKE, about 25 cave fights;
level 15 is about 8000, about 60. Neither is a casual amount of play. A
better weapon does not help the turn count either, because a shield chip goes
by weapon class and costs one hit whatever the weapon is
(`docs/HANDOFF.md`), so the MithrilBlade changes the damage after the break
and not the number of turns to reach it.

**Unverified, and worth settling before anyone grinds for this reason:**
whether the soldier's killing action scales with the target's level. It comes
through command `$0C` (`Cmd_0c` / `_actbluemagic0`,
`ff6/src/battle/battle_main.asm:3740`). If its damage tracks LOCKE's level or
maximum HP then levelling him never reaches the fight at all, and the two
bullets above are optimistic rather than merely expensive.
