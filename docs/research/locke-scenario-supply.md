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
list: they cost more than four times the whole discretionary remainder. Nor
does simply fighting the cave pay for them (§5, measured: `+256`). What is
left, in rough order of how much play each costs:

1. **Cut Fenix Downs from 5 to 3** and free 1000. The comment that set the
   figure at five recorded a pass that spent all five on map 98; the chain of
   2026-08-12 spends **one** (5 at `vargas_entry`, 4 at `vargas_won`). The
   figure is stale against its own justification. This leaves the entry
   contract's floor of 3 exactly met, with no margin, which is the argument
   against.
2. **A deliberate paced grind in the cave**, about six fights for 1500 (§5).
3. **Visit Figaro Castle's shop 4 before leaving.** Unrelated to pendants but
   it belongs on the same list: the route opens shop 82 for EDGAR's Tools in
   that castle and never opens shop 4, which sells Fenix Downs at 500. The
   party then walks into an unknown cave with no revives, and buying them
   there instead of in South Figaro would free the South Figaro budget for
   relics.

A MithrilBlade at 450 is the cheapest item on any of these lists and the one
with a measured effect on the fight (§7).

## 7. What battle 11 actually looks like

Measured 2026-08-12 on the chain regenerated for this file, three attempts,
seeds `$38` / `$88` / `$D8`. All three lost, so `sfigaro_town` cannot be
generated at all on this ROM today, and the Locke chain is blocked there.

The shape is not the one the issue was working from. LOCKE is not stuck
chipping and dying in two turns. He breaks the armour and gets into the
damage phase, and then loses a race. Attempt 3, monster HP and shields
straight off the driver's log:

| frame | monster | note |
|---|---|---|
| f+300 | 490 / sh2 | a chip does 5 |
| f+900 | 485 / sh1 | |
| f+2400 | **393 / sh0** | broken; the breaking hit lands 92 |
| f+3300 | 371 / sh0 | an ordinary Fight does 22 |
| f+3900 | 349 / sh0 | |
| f+4200 | 255 / sh0 | a boosted Fight lands 94 |
| **f+4500** | **255 / sh3** | **the break expires and all three shields return** |
| f+5100 | 250 / sh2 | chipping again, 5 a hit |

The break window is the fight. `OT6_BREAK_TICKS` is `$10`, which is 2159
frames (`docs/HANDOFF.md`), and the measured gap from `sh0` to `sh3` here is
about 2100. Inside one window LOCKE takes the soldier from 485 to 255, which
is 230 of 495. He needs a bit over two clean windows and each one costs three
chip turns to re-open, and he does not survive that long.

What ends it is healing, not damage. His own HP went 168 → 113 → 27, he drank
the bag's single Potion back to 168, took 52 more, and then sat at 116 until a
row-exempt special of 111 or more killed him. The driver refused every Tonic
on the way, and said why: *"$E8 restores 50 and a round costs 86, so the turn
buys back less than it spends"*. Eleven Tonics in the bag were worth nothing
to him.

So all three levers in this file bear on the fight, which is the opposite of
what §6 would suggest on its own:

- **A weapon.** The MithrilBlade is power 38 against the Dirk's 26. The
  22-damage Fights and the 92/94 breaking hits all scale off that, and they
  are what has to fit inside a 2159-frame window.
- **Levels.** He dies from 116 to a hit of 111+. Level 10 is 221 max HP and
  level 11 is 249 (§4), which is the difference between one special killing
  him from most of his bar and not.
- **Potions.** The single most direct one, and the route gives it away. The
  bag holds 5 Potions at `vargas_entry` and 0 at `vargas_won`: the Vargas
  medic drinks all five. LOCKE reaches his solo fight with the one Potion the
  river dropped. **No shop he can reach sells Potions** — not South Figaro's
  shop 8, not Figaro Castle's shop 4, and the nearest vendor is Narshe's shop
  3 in a different walkable region (`south-figaro-shop-route.md` §2) — so they
  cannot be replaced, only not spent.

None of this is a balance change, and the fight should not be re-tuned until
a LOCKE who is armed, a level or two up, and carrying more than one usable
heal has been put in front of it.

**Unverified, and worth settling first:** whether the soldier's killing action
scales with the target's level. It comes through command `$0C` (`Cmd_0c` /
`_actbluemagic0`, `ff6/src/battle/battle_main.asm:3740`). If its damage tracks
LOCKE's level or maximum HP then the levelling lever above is worth less than
it looks, and the weapon and the Potions carry the whole fix.
