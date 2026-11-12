# The OT6 level curve — party levels by area

> This is the authoritative party-level reference, and it is *empirical*: the
> levels below are read off the routed **tracked checkpoints**
> (`tools/tests/checkpoints/*-v1`), not from a vanilla walkthrough, so they
> are the levels OT6's own route reaches, which is what tuning must answer to.
>
> Regenerate with `tools/savestate_party.py`'s `read_party_sram` (the snippet
> at the bottom).

## The curve (active party at each checkpoint)

Read from the tracked checkpoints (`tools/tests/checkpoints/*-v1`) with
`read_party_sram`, re-read for v0.31 after the v0.30 re-cut and the gear
policy (#434): `build/attempts/wt/v031-cleanup/levels-421.log`; re-read
for v0.42 from the v0.41 saves (#497,
`build/attempts/wt/v042-leveling-plan/roster_checkpoints.txt`), where the
Thamasa and Floating Continent rows moved by a level.  The scenario rows
show the one member saved in that slot.  The whole roster, bench included,
at every save is in "The leveling plan" below.

| area / checkpoint | party (name L) | range |
|---|---|---|
| Narshe, on the world map (`world-narshe-v1`) | TERRA 5 · LOCKE 7 | L5–7 |
| Figaro, on the world map (`world-figaro-v1`) | TERRA 5 · LOCKE 7 · EDGAR 8 | L5–8 |
| Mt. Kolts summit (`kolts-summit-v1`) | TERRA 10 · LOCKE 11 · EDGAR 11 | L10–11 |
| Sabin's scenario, the camp (`camp-escaped-v1`) | CYAN 14 · SHADOW 12 · SABIN 14 | L12–14 |
| Sabin's scenario, the falls (`falls-done-v1`) | CYAN 14 · SABIN 14 | L14 |
| Scenario hub / Locke done / Sabin done | one member, L17–18 | L17–18 |
| Battle for Narshe (`kefka-won-v1`) | LOCKE 13 · EDGAR 13 · SABIN 14 · CELES 13 | L13–14 |
| Zozo (`zozo-outside-v1`) | LOCKE 18 · EDGAR 18 · SABIN 18 · CELES 18 | L18 |
| After the opera (`post-opera-v1`) | LOCKE 19 · EDGAR 19 · SABIN 19 · CELES 19 | L19 |
| Vector, the MRF save room (`mrf-save-room-v1`) | LOCKE 20 · EDGAR 20 · SABIN 20 · CELES 20 | L20 |
| The MRF, after Ifrit and Shiva (`n024-entry-save-v1`) | LOCKE 21 · EDGAR 21 · SABIN 21 · CELES 21 | L21 |
| The minecart (`minecart-platform-v1`) | LOCKE 21 · EDGAR 21 · SABIN 21 | L21 |
| Terra returned (`terra-returned-v1`) | LOCKE 21 · EDGAR 21 · SABIN 22 · SETZER 18 | L18–22 |
| Narshe mission (`narshe-mission-v1`) | LOCKE 22 · EDGAR 22 · SABIN 23 · SETZER 19 | L19–23 |
| Water Rondo (`water-rondo-v1`) | LOCKE 22 · EDGAR 22 · SABIN 23 · MOG 25 | L22–25 |
| Esper Gate cave (`gate-cave-save-v1`) | TERRA 20 · LOCKE 23 · EDGAR 24 · SABIN 24 | L20–24 |
| Vector crash (`vector-crash-v1`) | TERRA 22 · LOCKE 25 · EDGAR 25 · SABIN 25 | L22–25 |
| Banquet (`banquet-done-v1`) | TERRA 22 · LOCKE 25 | L22–25 |
| Crescent landing (`crescent-landing-v1`) | TERRA 22 · LOCKE 25 · SHADOW 22 | L22–25 |
| Thamasa, the night (`thamasa-night-v1`) | TERRA 22 · LOCKE 25 · SHADOW 22 | L22–25 |
| Thamasa fire (`fire-out-v1`) | TERRA 23 · LOCKE 26 · STRAGO 25 | L23–26 |
| Esper Mtn (`esper-mtn-save-v1`) | TERRA 23 · LOCKE 26 · STRAGO 25 | L23–26 |
| Ultros③ (`ultros-won-v1`) | TERRA 23 · LOCKE 26 · STRAGO 25 · RELM 22 | L22–26 |
| **FC entry (`thamasa-done-v1`)** | **TERRA 23 · LOCKE 26 · STRAGO 25 · RELM 22** | **L22–26** |
| FC landing (`fc-landing-v1`) | TERRA 24 · LOCKE 26 · EDGAR 25 | L24–26 |
| FC alcove (`fc-alcove-v1`) | TERRA 26 · LOCKE 28 · SHADOW 25 · EDGAR 26 | L25–28 |

The World of Ruin rows are in "The World of Ruin" below.

## The supply curve (what the bag carries at each level)

The care split is a directive: **outside battle heal with Tonics** (the
field care between fights; a menu turn is free), **in battle heal with
Potions** (turns are scarce, and a Tonic's +50 is under the measured
round cost from the Sabin scenario on), and a **Fenix Down** is the WoB's
only answer to a death.  The stock the route carries, topped up at every
town that sells the item, scales with the active party's highest level:

| item | band | first shop on the route |
|---|---|---|
| Tonic | ~level x5, cap 99 | Figaro Castle (shop 4, `gen_edgar`).  In the World of Ruin, where most stretches have no Tonic counter, the audit counts field-care HP: Tonics at 50, Potions at 250, against the band's HP (#411) |
| Fenix Down | ~level, ~15-20 | Figaro Castle (shop 4, `gen_edgar`, #307): toward the band with at most half the purse the tool shop leaves (two at L7, carrying three into the desert); South Figaro (shop 8, `gen_kolts`) fills it.  `audit_supplies` holds the band from that fill (`kolts_entry`) on, into the World of Ruin, with two of slack for the levels gained between counters (#411) |
| **Potion** | **~level x1.5, minimum 10** | the Phantom Train's ghost merchant (shop 85, `gen_sabin_train`; L14 -> 21) |
| **Tincture** | **~level / 4, rounded up** (the MP column, #231: one caster's pool per stretch; [supply.md](supply.md)) | Narshe (shop 3, `gen_zozo1_submerge`; L14 -> 4).  Figaro Castle sells them too, and its purse cannot carry one. |
| Tent | 4 from Albrook (the factory's two save points), 10 from Jidoor | Albrook (shop 24, `gen_vector_entry`); `gen_narshe_mission`'s TENT to 10 stands |
| Revivify | 3 | Jidoor (shop 22, `gen_zozo2_arrival`) |
| Remedy | 5 before the Floating Continent (#361: its map 394 deals Mute casters, Apokryphos and Misfits, in half its draws; one cure a leg plus two) | Thamasa (shop 35, row 3, `gen_fc_landing`); no Echo Screen counter on the way |

The MP rows are measured and ruled on in [supply.md](supply.md): the
prices and yields off `item_prop_en.dat`, the inns' prices per town, where
the counters and save points stand against the Narshe descent, the Vector
approach and the Floating Continent prep, and the rule for each option
(Tonic, Potion, Tincture, Tent, inn, and the one rule for Elixirs).

The Potion band starts at the first town that sells them.  On this route
that is the Phantom Train (`shop_prop.dat`: Figaro's shop 4 and South
Figaro's shop 8 stock no Potion; the eight or so the bag holds before the
train are chests and drops), so the Locke scenario and the Imperial camp /
Doma stretch run on what they find, and the band is measured from
`train_done` on.  Below the band at a fixture is a warning from
`tools/audit_supplies.py` (`-v` lists each fixture with its count, band and
level); a shop stop is written as `POTION to N` beside its `TONIC to N` /
`FENIX DOWN to N` lines, essentials and Potions before the Tonic soak so a
short purse shorts Tonics.  The band is what the bag should hold *arriving*
at the next fight, so the last shop before a shopless boss stretch buys the
band plus that stretch's measured spend (the train merchant: 21 for L14
plus the 9 the GhostTrain fight spent = 30, so Baren Falls still holds 21).
The band runs on through the World of Ruin, where every item counter on
the route sells Potions, and caps at 79 (L53; #386, "The World of Ruin"
below).

The WoB Potion shops on the route, decoded from `npc_prop.asm` (the
counter NPC's event) and `shop_prop.dat` (the rows), with the stop each
generator makes (#176):

| shop | where | rows (Tonic / Potion / Fenix) | stop |
|---|---|---|---|
| 8 | occupied South Figaro, map 85 off (44,30); no Potion | 0 / - / 5 | `gen_sfigaro` (#213): TONIC to 78 before the gate soldier (the L13 band 65 + the 13 the seeded scenario spent from 20 to locke_done's 7).  The door is in LOCKE's starting pocket only: from the main street past the cafe the shop is unreachable (`probe_locke_tonic` (deleted in 895b8e67; last version at f9bca17b)). |
| 39 | the merchant in the yard of SHADOW's house, map 115 (obj 18 at (8,10)); vendor, no Potion | 0 / - / 1 | `gen_sabin_world` (#213): FENIX DOWN to 14, TONIC to 86 (the L14 band 70 + 16, measured by the first cut's 85 from sabin_camp to forest_done's 69; the 86 cut spent 21, forest_done 65 -- the stretch's care is seed-dependent, 16..21).  Before SHADOW's scene: the merchant is gone from the yard once SHADOW joins (`probe_sabin_merchant` (deleted in 895b8e67; last version at 276db754)). |
| 85 | Phantom Train car B, map 85 | 0 / 1 / 4 | `gen_sabin_train`: POTION to 30 (L14 band 21 + the train fight's 9) |
| 12 | Mobliz, map 164 | 1 / 2 / 5 | `gen_sabin_gau`: POTION to 23 (L15) |
| 15 | Nikeah, the counter at (24,39) on town map 169 | 0 / 1 / 5 | `gen_sabin_trench`: POTION to 27 (L18).  The last Potion shop before the reunion: the Terra scenario never walks a town with control (its Narshe arrival is the isolated clifftop ledge; Arvis's front door lies past the reunion trigger; the map-22 staging boxes the party -- `probe_narshe_preshop` (deleted in 895b8e67; last version at 07e6dadf)), so this bag is what TERRA's L13 party (band 20) and the Battle for Narshe (L14, 21) carry. |
| 3 | Narshe, map 26 off town map 20's (41,22) door | 0 / 1 / 4 | `gen_zozo1_submerge`: TONIC to 99, FENIX DOWN to 15, no Potion line (Nikeah's 27 arrives intact, over the L14 band).  The last Tonic counter before the post-opera checkpoint.  TINCTURE to 4 (#231: the L14 MP band, row 2; the first Tincture counter whose purse can carry them). |
| 22 | Jidoor, map 201 off town map 198's (27,41) door; no Tonic | - / 0 / 5 | `gen_zozo2_arrival` after the L18 grind: POTION to 39 (the #158 target of 30 + 9 for field care: 49 Tonics measured from Jidoor to the opera's end), FENIX DOWN to 20, REVIVIFY to 3 and TINCTURE to 5 (#231: rows 4 and 1, the L19 MP band).  `gen_narshe_mission`'s plains grind restocks here too: POTION to 35 per leg, to 60 on departure, and at every restock REVIVIFY to 3, TINCTURE to 6 (the L23 band), TENT to 10. |
| 24 | Albrook, map 328 off (7,13); no Tonic | - / 0 / 5 | `gen_vector_entry`: POTION to 50 (#210: the L21 band 32 + the regenerated run's measured spend from post-opera-v1's 37 to terra-returned-v1's 20, which includes the field care of a stretch whose Tonics sat at the kernel's floor of 4 from the save room on; was 35).  REVIVIFY to 3, TINCTURE to 5 and TENT to 4 (#231: rows 4, 1 and 6 -- the L20 MP band, and a Tent for each of the factory's save points, 270 and 273).  Vector itself sells no Potions -- weapon 27 and armour 28 only (maps 246/248). |
| 44 | Narshe again, once `$006B` (the factory escape) swaps shop 3 for 44; no Tonic | - / 0 / 2 | none: `gen_narshe_mission` shops at Jidoor instead (row 22 above) |
| 15 | Nikeah again, by the Blackjack (lands on world (116,61); town 169 (1,35)) | 0 / 1 / 5 | `gen_narshe_mission` (#210): TONIC to 99 before the plains grind and again on the flight to Narshe, each when the bag is under 74 (3/4 of the L21-23 band of 99).  The first Tonic counter the route can reach after Narshe's swap to 44: the Blackjack's wheel is dead until the factory escape (`_caf532` returns while `$01B3`/`$01B4` is clear -- `probe_tonic_airship` (deleted in 895b8e67; last version at 437e9105)), South Figaro's shop 8 still sits behind the occupation's troopers, and Figaro Castle's merchants refuse EDGAR and SABIN. |
| 15 | Nikeah, by the Blackjack before the Sealed Gate | 0 / 1 / 5 | `gen_gate_cave_save` (#213): POTION to 60, FENIX DOWN to 24, TONIC to 99, only when the bag is under 3/4 of the Tonic band or under the L25 Potion band (38).  The last live flight: the wheel is dead from the gate on, and nothing to Thamasa sells Tonics.  The seeded `narshe-mission-v1` (tonic=0 potion=0) fires it; `gen_narshe_mission`'s regenerated departure (tonic=99 potion=60) would not. |
| 24 | Albrook again | - / 0 / 5 | `gen_voyage`: POTION to 38 (L25; no field-care extra: the legs to Thamasa's Tonic counter spent none), REVIVIFY to 3, TINCTURE to 7 (#231: the L26 MP band) |
| 35 | Thamasa, on arrival | 0 / 1 / 6 | `gen_thamasa_arrive` (#213): POTION to 38, FENIX DOWN to 25, REVIVIFY to 3, TINCTURE to 7, TENT to 10 (#231: rows 5, 2 and 7), TONIC to 99 before the chests and Strago; the seeded chain walked the K tile to the L save with tonic=0 and first shopped the next morning. |
| 35 | Thamasa, map 347 off (26,37) | 0 / 1 / 6 | `gen_thamasa_fire`: POTION to 45 (L26 band 39 + 6, the spend the seeded run measured from fire_out's 15 to thamasa_done's 9), FENIX DOWN to 20, REVIVIFY to 3, TINCTURE to 7, TENT to 10 (#231), TONIC to 99.  The re-cut M..P run (2026-09-16) spent none of it: fire_out, esper_mtn_save, ultros_won and thamasa_done all carry `potion=45`. |
| 35 | Thamasa again, the FC prep | 0 / 1 / 6 | `gen_fc_landing`: POTION to 65 (L29 band 44 + 21, the old run's measured spend: the IAF gauntlet 16, the alcove leg 3, the escape 2), FENIX DOWN to 25, REVIVIFY to 3, TINCTURE to 7, TENT to 10 (#231: the L28 MP band, and Tents for the landing and alcove save points), TONIC to 99, then the bag arranged (combat items on top).  Re-cut 2026-09-16: the gauntlet's winning attempt spent 8 (`fc_landing` lands with `potion=57`, band 41 at L27) and the alcove leg 10 (`fc_alcove` at 47, band 42 at L28); the first two gauntlet attempts wiped in the Air Force fight -- a lab signal, not a fixed segment.  Both targets were held for #179 (the bigger purchase moved the RNG under fire_out's burning-house walk and an IAF wave) until the segment runner (#178) retried such losses; the walk itself needed two fixes a person would make (wait out a wandering flame; heal after the FlameEater's cutscene, not during it), in `gen_thamasa_fire` and `H.fieldCare`/`H.newCareDriver`. |

Shop 71 is Narshe's `$00A4` variant and never opens on this route.  The
Locke scenario has no Potion source: South Figaro's shop 8 sells none and
its `$00A4` alternate 63 (which does) opens only after the escape scene
sets the flag, when the town is occupied and the route is in the
basement.  From Narshe's Tonic stop (`gen_zozo1_submerge`) to the factory
escape nothing the route can reach sells Tonics to that party (Jidoor 22,
Kohlingen 19 and Albrook 24 stock none; Figaro Castle refuses
EDGAR and SABIN; the Blackjack does not fly), so on that leg the care
kernel's field heals come out of the Potion stack.  Once the Blackjack
flies, Nikeah is a flight away (#210, the row above); from the Narshe
mission on foot (shops 44 and 24) nothing sells them again until Thamasa
-- the seeded chain from the `terra-returned-v1` checkpoint walked the
whole Sealed Gate, crash, banquet and voyage with `tonic=0 potion=0..3`.
`tools/audit_supplies.py` warns under the Tonic band (~level x5, cap 99)
from Figaro Castle's shop to the WoR landing, beside the Potion band.

The Floating Continent cannot hold the band on Tonics alone (#213,
measured on the regenerated `fc_landing`): Thamasa's prep stop leaves at
`tonic=99`, the between-wave care of the IAF gauntlet uses 33 (99 -> 66)
and the care at the landing save point 28 more (the party arrives at
424/960, 469/1129 and 766/1048 HP) to `tonic=38`.  A Tonic is +50 HP
against L26 maxima near 1000, so one stretch of field care costs ~60, and
99 is the cap a bag slot holds; the last WoB counter is behind the party.

## Zozo: the level gate nobody authored (#155, levelled for #158)

The routed Zozo party as it was (L14-15) met map 225's solo SlamDancer
(formation $069, 31% of that map's rolls), whose `if_one_monster_type`
branch casts Fire 2 / Ice 2 / Bolt 2 every turn.  Measured in
`tools/tests/lab_zozo_street.lua` (deleted in 8d350a73; last version at f6507ff0) (15 seeds x 5 policies, raw damage
word): the single-target roll is **464..492**, above every member's max
HP (353/349/398/407); the all-target split lands 207..263 each.  Rows,
gear and Runic do not move it; L17-18 would.  It is vanilla data
(`monster_prop.dat` $052 is byte-identical to the vanilla ROM) meeting a
party three levels under vanilla's Zozo tier.  Details, the per-attempt
table and the retune options: [zozo-street.md](zozo-street.md).

The owner chose levels over a retune (#158).  `gen_zozo2_arrival` grinds
the x=34 column (world battle group 10) until every member is L18, then
stops at Jidoor's item shop (shop 22: Potion to 30, Fenix Down to 20; it
sells no Tonic).  The SlamDancer is L15 whatever the party is, so its roll
stays where it was; max HP is what moves (LevelUpHP +54 at L17, +57 at
L18).  L17 would have left LOCKE at 501 and CELES at 497, 5..9 over the
largest roll seen; L18 is the target.

| fixture | LOCKE | EDGAR | SABIN | CELES | Tonic / Potion / Fenix |
|---|---|---|---|---|---|
| grind start, world (34,99) | L13 314 | L14 354 | L15 407 | L13 310 | 75 / 21 / 14 |
| zozo_arrival | L18 558 | L18 559 | L19 629 | L18 554 | 43 / 39 / 21 (#176 stops: was 52 / 30 / 20) |
| zozo_done | L18 558 | L19 620 | L19 629 | L18 554 | 16 / 40 / 21 (was 14 / 31 / 18) |

The grind was 57 laps (43 fights, frames 14897 -> 162667 of the
generator), no Fenix Down and no death in it.  The first try at the
crossing's 0.9 care threshold emptied the Tonics by lap 52; the lap stop
now cares at 0.6 and level-ups do the rest.  The Tonic count is below its
~level x5 band from here to the next Tonic shop: none is reachable from
the column (Figaro's shop refuses EDGAR and SABIN).

Measured on the regenerated chain, map 225 with this party
(`lab_zozo_street.lua`'s (deleted in 8d350a73) control policy on a fixture baked at the P9a
landing, 15 seeds, every one rolling the solo SlamDancer): 9 casts, 4
single-target (Ice 2 436 and Bolt 2 464 / 472 on CELES, Bolt 2 484 on
EDGAR), 5 all-target (207..259 each); 0 deaths, 0 Fenix Downs, 0 wipes.
Every single-target cast left its target standing (82..136 HP).  The
street itself (`gen_zozo3_clock` 1 fight, `gen_zozo4_dadaluma` 8 fights
including one solo SlamDancer's all-target Fire 2) spent no Fenix Down in
a random; Dadaluma killed EDGAR and CELES (2 Fenix at the care after him).

With the #176 Potion stops in front of it (Nikeah, Narshe, Jidoor: the
bag above), the chain from `dadaluma_entry` to `blackjack` regenerated
under the segment runner (#178) with one counted retry: `dadaluma_entry`
attempt 1 drew the J39-row fight as a back attack, where the fight
driver's LEFT target steer cannot cross to the monster side (#185,
`probe_j39_backattack`, deleted in 4b257a86; last version at f157c19b),
and the no-effect watchdog cut it at frame
23808 instead of the 9000-frame step budget; attempt 2, the seed moved 20
frames at the boot point, climbed clean (16 fights played, no Fenix Down,
`care after Dadaluma: nothing to do`) and passed at frame 46149.  Every
later segment (`zozo_done` through `blackjack`) passed on its first
attempt; the Fenix count stays 21 from `zozo_arrival` to `blackjack`.
The back-attack steer itself is still open (#185).

## Map 269: the L16 parity trap (#171)

The first random after the Ifrit & Shiva save (map 269, formation $076,
Trapper x3, 37.5% of that map's rolls) casts **L4 Flare** on its second
turn a third of the time: power 66, ignore-defence, no split, every
level-multiple-of-4 target.  The routed party is LOCKE L16 / CELES L16 /
EDGAR L17 / SABIN L17, so exactly the two L16s take a **745..848** roll
(measured off `_writedamage`, 15 seeds x 5 policies) against 447 / 443
max HP; the L17s cannot be touched by any of the trio's three level
spells.  Rows and boost do not move it; the party's kill speed does
(LOCKE's ThunderBlade and SABIN's Pummel are the bolt and bludgeon keys).
The as-shipped leg walked in with SABIN dead from battle 70 and drew the
double kill in 9/15 fights; cared (the fix now in `gen_n024_entry`) draws
it in 4/15.  L17 for the pair would be immune -- 1055 / 1119 XP, three or
four Trapper trios at 352 each -- and L20 is exposed again (4 and 5).
Vanilla data, vanilla's own L20 party eats it too.  Details, the
per-attempt table and the levers: [map269-random.md](map269-random.md).

## The Floating Continent gap

The routed party reaches the **Floating Continent at L22–26**
(`thamasa-done-v1`). Rough vanilla FF6 expectation for the same content is
**~L25–30** (AtmaWeapon is a ~L30 fight in vanilla), so OT6 arrives a few
levels light, not the ten an earlier cut showed (L15–17, before the #158
grind and the re-cuts since).

What carries the remaining gap:

- **Break, not levels, is the damage.** OT6's fights are Octopath shield/break
  tactics; boss shield and weakness rows are authored *against the routed
  levels* (`check_boss_rows.py` is green through Nerapa, i.e. the FC bosses'
  data already matches the party they will actually meet). Raw level gates HP
  and survivability more than damage output.
- **Prep is the lever.** Row, boost banking, weakness coverage, and the field
  care between fights are what a player spends to clear a stretch they are
  under-levelled for, and the Blackjack grind ("Pre-FC grinding" below) closes
  the rest.

Practical consequences of the route as it stands:
- The IAF gauntlet is eight fights with **no save and a real Game Over on a
  loss** (the `_ca5ea9` handler). At L22–26 that is a survivability test, not a
  damage race — budget for HP attrition across the chain and lean on break to
  end fights fast.
- The FC's random pool (forms 177–188) includes **pincer-capable formations**
  (`audit_encounters.py 394`), so the walk between save points is itself a
  drain — care at the 394 (7,12) / 358 (8,10) save points matters.
- If tuning shows a fight is unwinnable at these levels even with perfect
  break/prep *and* a reasonable grind, that is a **balance signal** (retune the
  shield row).

## Pre-FC grinding (with the Blackjack)

Once the Blackjack is repaired (the stop line), the whole WoB world map is
reachable: fly to a region, land, and farm on foot. Ranked by XP, derived from
this ROM's data (`monster_prop.dat +12` = XP, `+16` = level; world encounters
via `world_battle_group.dat` → `rand_battle_group` → `battle_monsters.dat`):

| spot (WoB world encounter) | formation | XP | levels | note |
|---|---|---|---|---|
| **Chimera + Cephaler** | form 190 | **1572** | Chimera L22, Cephaler L21 | best WoB world XP; group 22/25 |
| Chimera solo | form 161 | 1144 | L22 | same zone |
| Ralph + Wyvern | form 144 | 1223 | L17–18 | group 14/15/21 |
| Ralph + Wyvern + ChickenLip | form 145 | 1119 | L17–18 | group 17/18 |
| ChickenLip ×5 | form 149 | 950 | L18 | group 15/17/18 |

Notes and cautions:
- **Chimera + Cephaler (~1572 XP) is the standout** and only ~L21–22, a few
  above the party — an efficient close-the-gap grind. It sits in world
  encounter group 22 (top-of-map zones, roughly X 64–128) and group 25
  (mid-map). Exact fly-to coordinates need a world-tile probe (the #131
  airship-driver can now fly and read the roll); until then, fly the eastern/
  central WoB landmasses and land where Chimera/Cephaler roll.
- **Intangir is NOT an XP grind here** — `monster_prop` gives it **0 XP**
  (species `$0a3`). The Triangle Island trick is a magic/gil story, not levels.
- The huge-XP formations (Tyranosaur 8800, Doom Drgn 8500, Brachosaur 14396)
  are all **WoR-gated** (L44–77) and unreachable pre-FC. The route grinds
  the Tyranosaurs before Kefka's Tower (`route-wor-side-trips.md`) and runs
  from the Brachosaur.
- **The Veldt pays no XP** (`$11E4` bit 1; HANDOFF), so Gau's stretch is not a
  grind — `WorldBattleGroup` marks veldt sectors with `$FF`
  (`field/battle.asm:138-142`).
- OT6 scales XP by the inverse of the encounter rate (`DESIGN.md:408`), so
  absolute numbers differ from vanilla but the *ranking* of spots holds (same
  monster data, uniform scale).

## Gear at the FC entry (thamasa_done)

Read from `thamasa-done-v1` (`build/attempts/wt/v031-cleanup/thamasa-done-gear-421.log`):

| char | weapon | shield | helmet | armor | relic |
|---|---|---|---|---|---|
| TERRA | Blizzard (ice) | Mithril Shld | Bandana | Mithril Vest | — |
| LOCKE | **ThunderBlade** (bolt) | Guardian | Head Band | Kung Fu Suit | Genji Glove |
| STRAGO | Fire Rod | Mithril Shld | Plumed Hat | Cotton Robe | — |
| RELM | Chocobo Brsh | Mithril Shld | Plumed Hat | Silk Robe | Memento Ring |

- **One ThunderBlade.** The IAF (and AtmaWeapon) is bolt-weak
  (`floating-continent-route.md` §3); Locke's swings and its Thunder are the
  party's bolt key.
- **Empty relic slots on two of four**, mid-tier (Mithril/cloth) armor.
  Survivability relics are what the IAF's care-stop-less attrition punishes
  the lack of. The Blackjack reopens WoB shops (Thamasa and others), so
  gear/relic shopping is part of FC prep ("Buying power" below).

## The World of Ruin (#386)

Evidence: `build/attempts/wt/v027-wor-plan/` (`checkpoints.log`, the
tracked checkpoints read by `wordump.py`; `xp_by_map.txt`,
`town_pools.txt`, `bosses.txt` and `shops*.txt` from `build/ot6.sfc` via
`route_data.py`; `projection.log`).  Levels past the Falcon were
**estimates** until each arc played them; every arc plays now, and the
measured levels of the whole line are in "The leveling plan" below.

### Measured: the landing to the Falcon

| checkpoint | active party | Potion / Fenix / Tincture / Revivify | gil |
|---|---|---|---|
| `wor-start-v1` | CELES 25 | 79 / 25 / 9 / 9 | 172,785 |
| `wor-tzen-door-v1` | CELES 27 | 79 / 27 / 9 / 9 | 194,259 |
| `wor-sabin-v1` | SABIN 28 · CELES 28 | 79 / 28 / 9 / 9 | 172,513 |
| `wor-edgar-v1` | EDGAR 31 · SABIN 31 · CELES 31 | 77 / 29 / 9 / 9 | 232,131 |
| `wor-kohlingen-v1` | EDGAR 31 · SABIN 32 · CELES 32 · SETZER 31 | 95 / 29 / 9 / 10 | 217,087 |
| `wor-falcon-v1` | EDGAR 32 · SABIN 33 · CELES 33 · SETZER 31 | 70 / 29 / 9 / 25 | 248,627 |

`wor-falcon-v1 EDGAR L32 1481/1701 ... SABIN L33 1414/1812 ... CELES L33
1518/1798 ... SETZER L31 1360/1597`; `xp EDGAR 96891, SABIN 101443, CELES 104577,
SETZER 91189`.  Re-read from the tracked checkpoints on 2026-10-18
(`build/attempts/wt/v031-callbacks/wordump_falcon.log`, #438); the table
had kept the v0.27 plan's figures.

### How the World of Ruin pays

- A random pays its formation's XP x2 (`Ot6RewardMulW`), divided among the
  living members (`battle_main.asm` @5db0: total / `$3a76`).  Bosses pay
  none (`bosses.txt`: every boss below has `XP 0`), and neither do the
  Veldt (`$11E4`) nor the Fanatics' Tower's pool (`map 365 ... L.90 Magic
  ... XP 0`).
- A level costs `LevelUpExp` x8 (`levels.txt`): 9,792 for L35, 12,792 for
  L40, 20,000 for L50, 28,792 for L60.
- The bench gains nothing.  A recruit joins at the available characters'
  average (`norm_lvl`: TERRA `event_main.asm:88191`, CYAN `:86689`, MOG
  `:85197`, RELM `:48897`, STRAGO `:89448`, LOCKE `:83903`, SHADOW
  `:93791`; Gogo and Umaro through `InitChar`'s average, Gogo +2).  The
  plan once had rotation keep the extra members within
  `audit_levels.py`'s straggler gap of 3; the line does not (seven of
  fourteen at L32-41 against the carriers' 64 at the tower's boot), and
  the owner's shape is six to eight strong carrying the rest (#496; "The
  leveling plan" below).

Expected XP per random, x2, before the split (`xp_by_map.txt`,
`town_pools.txt`):

| area | pool | top monster L | XP per random | per member of four |
|---|---|---|---|---|
| Mobliz's plain | world group 38 | 26 | 2,286 | 572 |
| Thamasa's plain, Ebot's door | world group 55 | 42 | 5,035 | 1,259 |
| Zozo, Jidoor, Maranda | world group 49 | 54 | 12,673 | 3,168 |
| Narshe's plain | world group 51 | 54 | 14,811 | 3,703 |
| Doma's plain | world group 52 | 55 | 16,710 | 4,178 |
| Mt. Zozo | maps 176-179 | 35 | 3,990-7,402 | 1,000-1,850 |
| Narshe, the moogle cave | maps 32-38 | 32 | 3,798-4,038 | ~1,000 |
| Cyan's dream | maps 125/126/144, 317-322 | 40 | 4,822-6,092 | 1,200-1,520 |
| Owzer's house | map 207 | 36 | 6,534 | 1,634 |
| the Fanatics' Tower | maps 359-370 | 58 | 0 | 0 |
| the Phoenix Cave | maps 313, 315 | 49 | 12,409-13,651 | 3,100-3,400 |
| the Cave in the Veldt | map 353 | 36 | 4,998 | 1,250 |
| the Zone Eater | maps 276-278 | 44 | 6,449-7,707 | 1,600-1,930 |
| Ebot's Rock | maps 404, 405 | 38 | 4,790-5,596 | 1,200-1,400 |
| Umaro's cave | maps 281-283 | 33 | 5,525-5,688 | ~1,400 |
| the Ancient Castle | maps 401-407 | 47 | 8,306-8,772 | 2,100-2,200 |
| Kefka's Tower | maps 287-355, 409, 410 | 59 | 8,775-23,375 | 2,200-5,800 |

Areas are named from their species (`pool_names.txt`) and the world map's
doors (`world-entrances 1`); Cyan's dream is named by its CYAN NPCs (maps
125, 126, 319, 320) and Umaro's cave by its events (route-wor-narshe.md).  The plains around
Narshe, Zozo and Doma (groups 49-52) pay two to four times what most arcs'
dungeons pay (the Phoenix Cave matches them); they are the World of Ruin's grind, a
short Falcon hop from any arc.

### The plan by milestone

Projected levels walk each arc with an assumed fight count (**estimate**;
`projection.log` lists the counts) from `wor-falcon-v1`'s mean 98,525 XP (re-read 2026-10-18; the
projected levels below were walked from the older 105,612 and not re-run).
The target column is the healthy level for the stop's key fight; it is an
estimate until a lab sets it, as the Tentacles' L30 (route-wor-edgar.md
4.1) and Dullahan's were.  The "met at" column is the seated party as the
v0.41 line plays it (#497: `route_levels.txt` in
`build/attempts/wt/v042-leveling-plan/`; "The leveling plan" below reads
it).

| milestone | key fights (ROM: L, HP) | what bites (AI script) | projected | target | met at (v0.41, seated) |
|---|---|---|---|---|---|
| v0.27 Terra | Phunbaba (L26 60,000; L31 28,000 / 26,000) | Blow Fish, Bolt 3; absorbs bolt | 33-34 | as reached: the boss is under the party | 32-33 |
| v0.28 Cyan | Storm Drgn (L74 42,000) | Aero, Cyclonic (Near Fatal), Wind Slash; absorbs wind, weak bolt | 36 | 35 with the gear policy's kit (38 before; "Buying power" below) | 35-38 (CYAN 35, the grind's floor) |
| v0.29 Narshe | Umaro (L33 17,200), Tritoch (L62 30,000), Ice Dragon (L74 24,400) | Tritoch: Ice 3, Cold Dust (Frozen); nulls bolt and five more, weak fire | 39 | 40 | 35-40 (MOG 35-36 to CELES 39-40) |
| v0.30 Jidoor & Thamasa | Chadarnook (L37 56,000; L41 30,000), MagiMaster (L68 50,000), Holy Drgn (`White Drgn`, L71 18,500) | MagiMaster: Fire/Ice/Bolt 3, Doom, and **Ultima as his death counter**; the tower is magic-only | 41 | 45 for MagiMaster | 38-41 at Owzer; 46-49 at MagiMaster |
| v0.32 Locke | Red Dragon (L67 30,000) | -- | 44 | 44 | 46-50 (party 1), 36-40 (party 2) |
| v0.34 Gogo | Hidon (L43 25,000), Doom Gaze (L68 55,555), Dirt Drgn (L53 28,500) | -- | 46 | 46 | 47-55 (GOGO joins at 44) |
| v0.35 Dreams | Wrexsoul (L53 23,066), Blue Drgn (L65 26,900) | -- | 49 | 49 | 53-57 (CYAN 40-42 for his own dream) |
| v0.38 Kefka's Tower | Guardian (L71 50,000; L67 60,000), Inferno (L67 30,800), the statues (Doom L73 63,000, Goddess L68 44,000, Poltrgeist L67 58,000), Gold and Skull Drgn (L62) | -- | 51 | 52, each of three parties | at the boot 32-64 (party means 46, 49, 48); trained in the tower to 46-69 |
| v0.39 The End | Kefka (L71 62,000) | Goner, Meteor, Havoc Wing; Ultima as a counter | 51 | 55 | the order's first four 59-69 (CELES, TERRA 69, RELM 61, STRAGO 59) |

Notes on the targets:

- **The Fanatics' Tower is magic-only** (`battle_main.asm` @5354: with
  `$3EBB` bit 0 set, Fight becomes Magic and every command but Magic,
  Item and Mimic is removed).  Its pool pays no XP, so the party arrives
  at MagiMaster with the level it brought in, and every member fights
  with the spells its Esper or natural magic gives (magicite.md, "When
  each stone arrives").  The grind for it is outside: groups 49 and 51,
  about 3,200-3,700 per member a fight, about 15 fights for L41 to L45.
- **MagiMaster's death counter is Ultima** (`counter: Ultima<pow 150>`).
  Vanilla's answer is Life 3, and here it is any Life boosted two or
  more: Terra's natural Life (L18) and Sraphim's are in hand, so Life 3
  pre-cast on the party answers it, with Shell (Shiva, ZoneSeek)
  and HP besides; the roll at the party's MDef is the lab's first
  measurement, and it sets the target.
- **Kefka's Tower takes three parties**, so the target applies to twelve
  members (or as many as the route seats).  From v0.32 on, rotation is part
  of the plan, not an afterthought.
- **The eight dragons** stay at their milestones (Storm v0.28, Ice v0.29,
  Holy v0.30, Red v0.32, Dirt v0.34, Blue v0.35, Gold and Skull v0.38); a
  dragon the projected level cannot take on the first attempt is a lab and
  a grind on the nearest of groups 49-52, not a skip.

### Supplies and gil

The bands run on from the WoB (`tools/audit_supplies.py`, #386): Potions
~level x1.5, Tinctures ~level / 4, Revivify 3, Fenix Down ~level capped
at 20, and the field care as HP (99 Tonics' 4950 capped).  No World of Ruin
counter sells Tonics (supply.md), so the field care rides on Potions.
Every tracked WoR checkpoint holds every band (`wor_bands.log`:
`wor-falcon-v1 L34 potion 79/51 ok; field 7200/4950 HP ok; tincture 13/9
ok; revivify 32/3 ok; fenix 31/20 ok`).

The WoR item counters on the route, each selling Potion 300, Tincture
1500, Fenix Down 500 and Revivify 300, and all but Tzen's Remedy 1000
(`shops.txt`, `shops_wor_ahead.txt`): Albrook 48, Tzen 54, Nikeah 58,
South Figaro 63, Kohlingen 67, Thamasa 74, Jidoor 78.  Narshe's 71 is
behind a door only LOCKE opens (route-wor-narshe.md).  Mobliz, Zozo and
Maranda have none.

**The Potion stack fills at L53.**  The bag holds 99 of an item, and the
reserve plus the field care's 20 Potions reach 99 at a reserve of 79, so
`audit_supplies` caps the band there.  Past it the field care moves to
Tents (save points and the world map), inns and boosted Cure; X-Potions and
Elixirs are chest and steal items only.  `H.careStockPotions`
(`ot6_field.lua`), which adds a four-level look-ahead and the legs' spend,
raises at about L43 with a spend of 10; the v0.30 and later counters need
the same cap there (a library change, so a replay; not made here).

**Gil is not the limit.**  `wor-falcon-v1` carries 248,627, and the plains
of groups 49 and 51 pay 500-2,600 GP a body, x2 (`group49.txt`,
`group51.txt`).  The stops' big buys:
Golem (20,000) and ZoneSeek (10,000) at Jidoor's auction (`take_gil 20000`
before `give_genju GOLEM`, `event_main.asm:49702`/`:49745`; `take_gil
10000` before ZONESEEK, `:49987`/`:50029`); four Crystal Mails at Maranda
(17,000 each).

### Buying power (#434)

Every town stop with weapon and armor counters runs `H.gearStop`
(`ot6_field.lua`, "the gear policy"): it plans upgrades for the seated
party by item value (power, defense, magic defense, evade, stats,
elements, status protection) plus the break keys a weapon's class and
element bring, one pick at a time within the purse less the supply
reserve, then dresses the party from the bag.  Relics, Espers and the
hands of a two-weapon relic's wearer stay the kits'.  Nikeah's street
stalls are left out (no talk tile reaches them).  What it bought on the
qualification play at 04756857 (`build/attempts/wt/gear-policy/qual3/
qual3-buys.txt`):

| stop | spent | pieces |
|---|---|---|
| Narshe (kefka_won, L13) | 6,800 | Mithril Claw, Mithril Shld x2, Iron Armor x2, Iron Helmet, Magus Hat, Silk Robe |
| Jidoor (after the Zozo grind, L18) | 11,000 | Kaiser, Ninja Gear x2, Mithril Vest, White Dress, Head Band x2, Mithril Shld |
| Albrook (vector_entry, L19) | 17,500 | Epee x2, Poison Claw, Bard's Hat x3 |
| Albrook (voyage, for SHADOW) | 3,200 | Blossom |
| Thamasa (arrival, FC prep) | 29,000 | Power Sash x2, Gaia Gear, Mystery Veil, Gold Shld, Morning Star |
| South Figaro, Kohlingen, Maranda (WoR) | 62,500 | Diamond Armor x2, Gold Lance, Diamond Shld, Falchion |
| Jidoor (WoR) | 46,000 | Man Eater, Circlet x5 |

Against main's play of the same route with nothing else changed
(`chain-base/`, `chain-policy-r6/`): deaths over the line 11 -> 7, the
one event loss (wor_terra) in both, the Air Force gauntlet (fc_landing)
2 deaths -> 0.  Two grinds were tried against it.  The Zozo grind as an HP
floor that follows each member's magic defense still needed L18 (LOCKE's
magic defense stays at 65 after Jidoor; `zozo-hpfloor/`), so it stays.
The Storm Dragon's grind went from L38 to L35, 22 battles where it was
55 (gen_wor_cyan; `storm/`): by distinct battle key, 16 seeds a sweep,
main at L38 12 keys, 1 wipe, 15 deaths; the policy at L38 12 keys, 0
lost, 2 deaths; at L35 13 keys, 0 lost, 18 deaths (the final policy) or
12 (before the pair rule); with no grind 13 keys, 0 lost, 34 deaths.

### Gear on the way

| shop | where | best rows (GP) |
|---|---|---|
| 72 weapon | Thamasa | Gravity Rod 13,000, Pearl Rod 12,000, DaVinci Brsh 7,000, Trump 13,000, Man Eater 11,000 |
| 73 armor | Thamasa | Light Robe 11,000, Diamond Vest 12,000, Dark Hood 7,500, Circlet 7,000 |
| 75 relic | Thamasa | Guard Ring 5,000, Cure Ring 8,000, Czarina Ring 3,000, Wall Ring 6,000 |
| 76 weapon | Jidoor | Crystal 15,000, Sniper 15,000, Partisan 13,000 |
| 77 armor | Jidoor | Dark Gear 13,000, Crystal Helm 10,000 |
| 79 relic | Jidoor | Cherub Down 6,300, Atlas Armlet 5,000, Guard Ring 5,000 |
| 80 weapon | Maranda | Falchion 17,000, SwordBreaker 16,000, Gravity Rod 13,000, the five Edges |
| 81 armor | Maranda | Crystal Mail 17,000, Tao Robe 13,000, Crystal Shld 7,000, Oath Veil 9,000 |
| 68-70 | Narshe | empty (each row lists only `$00 Dirk`); the item counter 71 is behind LOCKE's lock |

Shop owners from the `shop_menu` lines' event regions (Thamasa 72-75 beside
Gungho's scene, `event_main.asm` ~:55109; Maranda 80/81 beside its town
talk, ~:92006; Jidoor 76-79 beside the WoB rows 20-23).  Chests and steals
are each arc's route plan.

## The leveling plan (#497)

The line now plays from power-on to The End, so this section reads the
whole of it and says where it should grind, how long and with whom.  This
is the plan's first phase: the measurements below and the moves they
suggest.  Nothing here changes play; each move is its own branch, labbed
and re-measured when it lands.

Evidence: `build/attempts/wt/v042-leveling-plan/` (its `README.txt` lists
every command).  The source is a fresh full replay of the line at ba5c7e68
(px13, `~/work/v041-release`, v0.41's code): its `build/states/*.log` and
`.mss`, and the v0.41 tracked saves.  The instrument is
`tools/route_levels.py`: one row a leg in play order, the battles its last
attempt fought, its deaths and Fenix Downs, the random XP each member was
paid, and every recruited character's level at the leg's boot and its end,
the bench marked.  The main line is the chain of `prev` links from
`wor_kefka` back to power-on; every other leg is a branch nothing on the
line boots.  Two limits: a few World of Balance legs whose drivers predate
the `[outcome]` line count no battles (the legs before South Figaro, the
Returners' hideout, the Lete River), though their levels read true; and a
Fenix Down is counted when a `fenix=` field drops, as `audit_fenix` counts
what left the bag, so a revive by spell is a death without one.

### What the line does today

**Totals.**  Main line, random battles / deaths / Fenix Downs that left the
bag: the World of Balance at least 177 / 2 / 0; the World of Ruin to the desert
389 / 27 / 14; Kefka's Tower and Kefka 125 / 13 / 10.  No main-line leg
needed a second attempt in this replay (`retries.txt` lists only suites
and the negative controls), and Kefka was reached with "the bag for Kefka:
25 Fenix Downs (floor 10)" and won on the first attempt ("PASS (frame
168241) attempts=1/3").

**The grinds and training stops on the main line** (legs with eight or
more random battles, or a named grind).  Levels are at the leg's boot and
at the state the next leg boots.

| leg | where | random battles | who | levels before -> after | what sets the stop |
|---|---|---|---|---|---|
| `south_figaro` | the plain by South Figaro, before Mt. Kolts | 25 | TERRA, LOCKE, EDGAR | 5, 6, 7 -> 10, 10, 10 | the climb |
| `sfigaro_escape` | Locke's escape (the walk, not a grind) | 9 | LOCKE, CELES | 12, 12 -> 13, 13 | -- |
| `zozo_arrival` | world column x=34 (group 10) by Zozo | 44 | LOCKE, EDGAR, SABIN, CELES | 13, 13, 14, 13 -> 18 each | the SlamDancer: every member L18 (#158, the lab) |
| `n024_entry` | map 269 past the Ifrit and Shiva save | 11 | LOCKE, EDGAR, SABIN, CELES | 20 -> 21 each | the L16 parity trap (#171) |
| `narshe_mission` | the plains on the Narshe mission | 17 | LOCKE, EDGAR, SABIN, SETZER | 21, 21, 22, 18 -> 22, 22, 23, 19 | the mission's supplies |
| `wor_tzen_door` | the plain north of Albrook | 13 | CELES | 25 -> 27 | L27 (`TARGET_LEVEL`) |
| `wor_edgar` | the South Figaro continent, the cave | 26 | CELES, SABIN (EDGAR joins) | 29, 28 -> 31, 31, 31 | the Tentacles: L30 (the lab) |
| `wor_cyan` | Mt. Zozo's east face | 47 | TERRA, CYAN, SABIN, CELES (EDGAR 32 -> 34 on the climb, then benched) | 32, --, 32, 33 -> 36, 35, 37, 37 | the Storm Dragon: the lowest L35 |
| `wor_narshe` | Narshe's arc | 18 | TERRA, CYAN, CELES, MOG | 37, 35, 38, -- -> 38, 37, 39, 35 | -- |
| `wor_relm` | the plain north-west of Jidoor (group 48) | 54 | TERRA, CELES, STRAGO, RELM | 40, 41, --, -- -> 49, 49, 46, 46 | the Fanatics' Tower: the lowest L46 |
| `wor_belly` | the Zone Eater's belly | 27 | TERRA, CELES, STRAGO, RELM | 50, 51, 47, 48 -> 53, 53, 50, 50 | the dungeon |
| `wor_gogo` | map 278, to Gogo | 25 | TERRA, CELES, STRAGO, RELM | 53, 53, 50, 50 -> 55, 55, 52, 52 | the dungeon |
| `wor_colosseum` | the grind plains (#483) | 15 | TERRA, CYAN, CELES, SHADOW | 57, 42, 57, -- -> 58, 45, 58, 45 | the plains' coverage |
| `wor_dino` | the dinosaur forest | 29 | TERRA, CYAN, SHADOW, CELES | 58, 45, 45, 58 -> 63, 52, 52, 63 | the tower: the lowest L52 |
| `wor_kt_guardian` | party 1 by its landing on 334 | 59 | TERRA, RELM, EDGAR, SETZER | 64, 54, 34, 32 -> 69, 61, 47, 54 | the bench L46, at most 60 battles (#521) |
| `wor_kt_doom` | party 3 below Doom on 355 | 15 | CYAN, SHADOW, SABIN, GOGO | 53, 54, 42, 46 -> 56, 57, 46, 49 | the bench L46 |
| `wor_kt_poltergeist` | party 2 on 334's north | 45 | CELES, STRAGO, LOCKE, MOG | 64, 53, 42, 40 -> 69, 59, 51, 50 | the bench L50 |

Raw lines: "[grind] f362034 done after 51 battles ... TERRA(p1) L49 ...
CELES(p1) L49 ... STRAGO(p1) L46 ... RELM(p1) L46" (`wor_relm`); "[grind]
the forest until the lowest of the four stands at L52 (now L45)"
(`wor_dino`: the plain before it fought nothing, CYAN and SHADOW were
already L45); "[train] f300919 party 1 after 45 battles by its landing:
TERRA L68, RELM L60, EDGAR L46, SETZER L52"; "[train] f71562 party 3 below
Doom: after 13 battles: CYAN L56, SHADOW L57, SABIN L46, GOGO L49";
"[train] f242263 party 2 on 334's north: after 44 battles: CELES L69,
STRAGO L59, LOCKE L51, MOG L50".  SETZER wears the Exp. Egg: the Guardian
leg paid him 350,900 against 175,450 each for the other three.

**The hunts, all on branch legs** (nothing on the line boots them, so none
moves a save): the World of Ruin's coverage hunts from #485 and #488 and
the ones before them.

| branch | boots | random battles | who | levels before -> after |
|---|---|---|---|---|
| `kolts_cave` | `kolts_pool` | 5 | TERRA, LOCKE, EDGAR | 10, 10, 10 -> 10, 11, 11 |
| `wor_island_plain` | `wor-island-v1` | 4 | CELES | 25 -> 25 |
| `wor_tzen_plain` | `wor-sabin-v1` | 4 | SABIN, CELES | 28, 28 -> 28, 29 |
| `wor_tzen_boxes` | `wor-tzen-door-v1` | 3 | CELES | 27 -> 28 |
| `wor_nikeah_plain` | `wor-nikeah-v1` | 8 | SABIN, CELES | 28, 29 -> 30, 30 |
| `wor_passage_hunt` | `wor_figaro_sweep_town` | 8 | EDGAR, SABIN, CELES | 31, 31, 31 -> 31, 31, 32 |
| `wor_figaro_desert` | `wor-edgar-v1` | 3 | EDGAR, SABIN, CELES | 31, 31, 31 -> 31, 31, 32 |
| `wor_kohlingen_plain` | `wor-kohlingen-v1` | 10 | EDGAR, SABIN, CELES, SETZER | 32 -> 32, 32, 33, 32 |
| `wor_tomb_b1_hunt` | `wor-kohlingen-v1` | 8 (7 deaths) | the same | 32 -> 32, 32, 33, 32 |
| `wor_tomb_hunt` | `wor-tomb-v1` | 10 | the same | 32, 32, 33, 32 -> 33 each |
| `wor_zozo_hunt` | `wor_cyan_rustrid` | 20 | TERRA, EDGAR, SABIN, CELES | 32, 32, 32, 33 -> 32, 33, 33, 33 |
| `wor_zozo_north` | `wor_cyan_rustrid` | 5 | the same | no change |
| `wor_mtzozo_hunt` | `wor-mtzozo-v1` | 10 | TERRA, CYAN, SABIN, CELES | 36, 35, 37, 37 -> 37, 36, 38, 38 |
| `wor_umaro_hunt` | `wor_tritoch_cave` | 25 | TERRA, CYAN, CELES, MOG | 38, 37, 39, 36 -> 41, 39, 42, 38 |
| `wor_ebot_hunt` | `wor_ebot_hub` | 15 | TERRA, STRAGO, RELM, GOGO | 55, 52, 52, 44 -> 56, 53, 53, 45 |
| `wor_ebot_rooms_hunt` | `wor_ebot_rooms` | 15 | the same | 55, 52, 52, 44 -> 55, 53, 53, 45 |
| `wor_thamasa_plain` | `wor-gogo-v1` | 5 | the same | no change |
| `wor_dream_hunt` | `wor_dream_scape` | 35 | TERRA, CELES, RELM | 55, 55, 53 -> 58, 57, 55 |
| `wor_dream_cave_hunt` | `wor_dream_cave` | 5 | the same | 56, 55, 53 -> 56, 56, 53 |
| `wor_doma_hunt` | `wor-dream-v1` | 9 | the same | 56, 55, 53 -> 56, 56, 54 |
| `wor_ancient_hunt` | `wor_ancient_yard` | 40 | TERRA, CYAN, CELES, RELM | 57, 41, 56, 54 -> 60, 47, 59, 57 |
| `wor_ancient_boxes` | `wor_ancient_yard` | 3 | the same | 57, 41, 56, 54 -> 57, 42, 56, 54 |
| `wor_kt_gauntlet` | `wor-kt-inferno-v1` | 2 | CYAN, SHADOW, SABIN, GOGO | 53, 54, 41, 45 -> 54, 54, 41, 46 |

The rule holds: the hunts ride branches, and the levels they add reach
nothing downstream.  They seat whoever the arc seats, so they too feed the
two carriers.

**Who sits on the bench, and for how long** (the main line, World of Ruin;
a span is the run of legs a recruit spends in no party, with its level).
In the World of Balance the bench is the story's: the scenarios, and CYAN
and GAU at L14 from the Battle for Narshe to Thamasa (38 legs), raised to
L24 by the party's average when they rejoin there.

| character | benched | legs | level |
|---|---|---|---|
| SETZER | `wor_terra` .. `wor_desert` | 23 | 32 |
| EDGAR | `wor_cyan` .. `wor_desert` | 22 | 34 |
| UMARO | `wor_locke` .. `wor_kt_plates` (sits out the tower) | 22 | 37 |
| GAU | `wor_belly` .. `wor_kefka` (sits out the tower) | 19 | 33 |
| MOG | `wor_locke` .. `wor_desert` (and 3 at Owzer and the Fanatics' Tower) | 14 | 38 (36) |
| LOCKE | `wor_veldt` .. `wor_desert` (joins at `wor_locke` L41) | 12 | 41 |
| SABIN | `wor_belly` .. `wor_desert` (and 2, 2 and 3 legs before) | 10 | 40 (37-40) |
| CYAN | `wor_locke` .. `wor_dream` | 9 | 40 |
| GOGO | `wor_dream` .. `wor_desert` | 6 | 44 |
| STRAGO | `wor_dream` .. `wor_desert` (and `wor_locke` .. `wor_gau`, 4) | 6 | 52 (47) |
| RELM | `wor_colosseum` .. `wor_desert` | 3 | 54 |
| CELES | `wor_gogo` .. `wor_ebot` | 2 | 55 |
| TERRA | `wor_opera` | 1 | 55 |

TERRA and CELES are seated in every arc from Terra's on but one leg each,
and take a quarter of every random battle: 144,062 each on the Jidoor
plain, 148,665 each in the dinosaur forest, then 175,450 (TERRA, party 1)
and 158,033 (CELES, party 2) in the tower's training.

**Levels at every save** (the v0.41 tracked saves, `roster.py`; bold is
seated, plain is recruited and on the bench; a scenario's save shows the
slot's own members):

| save | Ter | Loc | Cya | Sha | Edg | Sab | Cel | Str | Rel | Set | Mog | Gau | Gog | Uma |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `world-narshe-v1` | **4** | **6** |  |  |  |  |  |  |  |  |  |  |  |  |
| `world-figaro-v1` | **5** | **6** |  |  | **7** |  |  |  |  |  |  |  |  |  |
| `kolts-summit-v1` | **10** | **11** |  |  | **11** |  |  |  |  |  |  |  |  |  |
| `hub-v1` | 12 | 12 |  |  | 12 | 13 |  |  |  |  |  |  |  | **17** |
| `locke-done-v1` | 12 | 13 |  |  | 12 | 13 | 13 |  |  |  |  |  |  | **17** |
| `camp-escaped-v1` | 12 | 13 | **14** | **12** | 12 | **14** | 13 |  |  |  |  |  |  |  |
| `falls-done-v1` | 12 | 13 | **14** |  | 12 | **14** | 13 |  |  |  |  |  |  |  |
| `sabin-done-v1` | 12 | 13 |  |  | 12 | 14 | 13 |  |  |  |  | 14 |  | **18** |
| `kefka-won-v1` |  | **13** | 14 |  | **13** | **14** | **13** |  |  |  |  | 14 |  |  |
| `zozo-outside-v1` |  | **18** | 14 |  | **18** | **18** | **18** |  |  |  |  | 14 |  |  |
| `post-opera-v1` |  | **19** | 14 |  | **19** | **19** | **19** |  |  |  |  | 14 |  |  |
| `mrf-save-room-v1` |  | **20** | 14 |  | **20** | **20** | **20** |  |  |  |  | 14 |  |  |
| `n024-entry-save-v1` |  | **21** | 14 |  | **21** | **21** | **21** |  |  |  |  | 14 |  |  |
| `minecart-platform-v1` |  | **21** | 14 |  | **21** | **21** |  |  |  |  |  | 14 |  |  |
| `terra-returned-v1` | 19 | **21** | 19 |  | **21** | **22** |  |  |  | **18** |  | 18 |  |  |
| `narshe-mission-v1` | 19 | **22** | 19 |  | **22** | **23** |  |  |  | **19** |  | 18 |  |  |
| `water-rondo-v1` | 19 | **22** | 19 |  | **22** | **23** |  |  |  | 19 | **25** | 18 |  |  |
| `gate-cave-save-v1` | **20** | **24** | 19 |  | **24** | **24** |  |  |  | 19 | 25 | 18 |  |  |
| `vector-crash-v1` | **22** | **25** | 19 |  | **25** | **25** |  |  |  | 19 | 25 | 18 |  |  |
| `banquet-done-v1` | **22** | **25** | 19 |  | 25 | 26 |  |  |  | 19 | 25 | 18 |  |  |
| `crescent-landing-v1` | **22** | **25** | 19 | **22** | 25 | 26 |  |  |  | 19 | 25 | 18 |  |  |
| `thamasa-night-v1` | **22** | **25** | 19 | **22** | 25 | 26 |  |  |  | 19 | 25 | 18 |  |  |
| `fire-out-v1` | **23** | **26** | 19 |  | 25 | 26 |  | **25** |  | 19 | 25 | 18 |  |  |
| `esper-mtn-save-v1` | **23** | **26** | 19 |  | 25 | 26 |  | **25** |  | 19 | 25 | 18 |  |  |
| `ultros-won-v1` | **23** | **26** | 19 |  | 25 | 26 |  | **25** | **22** | 19 | 25 | 18 |  |  |
| `thamasa-done-v1` | **23** | **26** | 24 |  | 25 | 26 | 24 | **25** | **22** | 24 | 25 | 24 |  |  |
| `fc-landing-v1` | **24** | **26** | 24 |  | **25** | 26 | 24 | 25 | 22 | 24 | 25 | 24 |  |  |
| `fc-alcove-v1` | **26** | **28** | 24 | **25** | **27** | 26 | 24 | 25 | 22 | 24 | 25 | 24 |  |  |
| `wor-island-v1` |  |  |  |  |  |  | **25** |  |  |  |  |  |  |  |
| `wor-start-v1` |  |  |  |  |  |  | **25** |  |  |  |  |  |  |  |
| `wor-tzen-door-v1` |  |  |  |  |  |  | **27** |  |  |  |  |  |  |  |
| `wor-sabin-v1` |  |  |  |  |  | **28** | **28** |  |  |  |  |  |  |  |
| `wor-nikeah-v1` |  |  |  |  |  | **28** | **29** |  |  |  |  |  |  |  |
| `wor-south-figaro-v1` |  |  |  |  |  | **28** | **29** |  |  |  |  |  |  |  |
| `wor-edgar-v1` |  |  |  |  | **31** | **31** | **31** |  |  |  |  |  |  |  |
| `wor-figaro-sweep-v1` |  |  |  |  | **31** | **31** | **32** |  |  |  |  |  |  |  |
| `wor-kohlingen-v1` |  |  |  |  | **32** | **32** | **32** |  |  | **32** |  |  |  |  |
| `wor-tomb-v1` |  |  |  |  | **32** | **32** | **33** |  |  | **32** |  |  |  |  |
| `wor-falcon-v1` |  |  |  |  | **32** | **32** | **33** |  |  | **32** |  |  |  |  |
| `wor-terra-v1` | **32** |  |  |  | **32** | **32** | **33** |  |  | 32 |  |  |  |  |
| `wor-mtzozo-v1` | **36** |  | **35** |  | 34 | **37** | **37** |  |  | 32 |  |  |  |  |
| `wor-cyan-v1` | **37** |  | **35** |  | 34 | **37** | **38** |  |  | 32 |  |  |  |  |
| `wor-narshe-cliffs-v1` | **38** |  | **37** |  | 34 | 37 | **39** |  |  | 32 | **35** |  |  |  |
| `wor-narshe-v1` | **39** |  | 38 |  | 34 | 37 | **40** |  |  | 32 | **36** |  |  | **36** |
| `wor-owzer-v1` | **40** |  | **38** |  | 34 | **38** | **41** |  |  | 32 | 36 |  |  | 36 |
| `wor-tower-v1` | **49** |  | 38 |  | 34 | 38 | **49** | **46** | **46** | 32 | 36 |  |  | 36 |
| `wor-thamasa-v1` | **49** |  | 38 |  | 34 | 38 | **49** | **46** | **46** | 32 | 36 |  |  | 36 |
| `wor-phoenix-v1` | **49** |  | **40** |  | 34 | **39** | **50** | **47** | **47** | 32 | **38** |  |  | **37** |
| `wor-locke-v1` | **50** | **41** | 40 |  | 34 | 40 | **50** | 47 | **47** | 32 | 38 |  |  | 37 |
| `wor-ragnarok-v1` | **50** | **41** | 40 |  | 34 | 40 | **50** | 47 | **47** | 32 | 38 |  |  | 37 |
| `wor-veldt-cave-v1` | **50** | 41 | 40 |  | 34 | 40 | **51** | 47 | **48** | 32 | 38 | **32** |  | 37 |
| `wor-gau-v1` | **50** | 41 | 40 |  | 34 | **40** | **51** | 47 | 48 | 32 | 38 | **33** |  | 37 |
| `wor-belly-v1` | **53** | 41 | 40 |  | 34 | 40 | **53** | **50** | **50** | 32 | 38 | 33 |  | 37 |
| `wor-gogo-v1` | **55** | 41 | 40 |  | 34 | 40 | 55 | **52** | **52** | 32 | 38 | 33 | **44** | 37 |
| `wor-ebot-v1` | **55** | 41 | 40 |  | 34 | 40 | 55 | **52** | **53** | 32 | 38 | 33 | **44** | 37 |
| `wor-opera-v1` | 55 | 41 | 40 |  | 34 | 40 | **55** | **52** | **53** | 32 | 38 | 33 | **44** | 37 |
| `wor-dream-v1` | **56** | 41 | 40 |  | 34 | 40 | **55** | 52 | **53** | 32 | 38 | 33 | 44 | 37 |
| `wor-doma-v1` | **56** | 41 | **40** |  | 34 | 40 | **56** | 52 | **53** | 32 | 38 | 33 | 44 | 37 |
| `wor-ancient-v1` | **57** | 41 | **42** |  | 34 | 40 | **57** | 52 | **54** | 32 | 38 | 33 | 44 | 37 |
| `wor-colosseum-v1` | **58** | 41 | **45** | **45** | 34 | 40 | **58** | 52 | 54 | 32 | 38 | 33 | 44 | 37 |
| `wor-dino-v1` | **63** | 41 | **52** | **52** | 34 | 40 | **63** | 52 | 54 | 32 | 38 | 33 | 44 | 37 |
| `wor-desert-v1` | **64** | 41 | **53** | **53** | 34 | 40 | **64** | 52 | 54 | 32 | 38 | 33 | 44 | 37 |
| `wor-kt-factory-v1` | **64** | **41** | **53** | **54** | **34** | **41** | **64** | **52** | **54** | **32** | **38** | 33 | **45** | 37 |
| `wor-kt-inferno-v1` | **64** | **41** | **53** | **54** | **34** | **41** | **64** | **52** | **54** | **32** | **38** | 33 | **45** | 37 |
| `wor-kt-atma-v1` | **64** | **41** | **53** | **54** | **34** | **41** | **64** | **52** | **54** | **32** | **39** | 33 | **45** | 37 |
| `wor-kt-guardian-v1` | **69** | **42** | **53** | **54** | **47** | **42** | **64** | **53** | **61** | **54** | **40** | 33 | **46** | 37 |
| `wor-kt-doom-v1` | **69** | **42** | **56** | **57** | **47** | **46** | **64** | **53** | **61** | **54** | **40** | 33 | **49** | 37 |
| `wor-kt-poltergeist-v1` | **69** | **51** | **56** | **57** | **47** | **46** | **69** | **59** | **61** | **54** | **50** | 33 | **49** | 37 |
| `wor-kt-goddess-v1` | **69** | **51** | **56** | **57** | **47** | **46** | **69** | **59** | **61** | **54** | **50** | 33 | **49** | 37 |
| `wor-kt-plates-v1` | **69** | **51** | **56** | **57** | **47** | **46** | **69** | **59** | **61** | **54** | **50** | 33 | **49** | 37 |

**Where the line pays for levels.**  The World of Balance spends no Fenix
Down on the line and loses two members (the Moogle defence and one random
on Esper Mountain); its grinds are the ones the labs set.  Every leg of the
World of Ruin that lost a member:

| leg | seated (L) | random battles | deaths | Fenix | what |
|---|---|---|---|---|---|
| `wor_storm` | 35-38 | 7 | 1 | 1 | |
| `wor_owzer` | 38-41 | 2 | 1 | 1 | |
| `wor_relm` | 40-49 | 54 | 2 | 2 | the grind |
| `wor_tower` | 46-49 | 18, no XP | 9 | 6 | one action from full HP: "[navTo] [death] f+8813 entity 1 char 6 from 3595/3595 by slot 2 cmd $02 atk $12 (ONE ACTION from >= 80%)"; MagiMaster's death counter fells all four in a battle the leg wins ("class=died with 5 BP banked", then "battle $162 WON after 26153 ticks") |
| `wor_phoenix` | 46-50 and 36-40 | 9 | 3 | 2 | party 2 is the bench (CYAN, SABIN, MOG, UMARO), six under the Red Dragon's 44 |
| `wor_gogo` | 50-55, GOGO 44 | 25 | 7 | 0 | CELES (L53-55) felled by one Fight in map 278's formations $15A and $15B, six times: "[death] f+1222 entity 1 char 6 from 3801/4117 by slot 1 cmd $00 atk $EF (ONE ACTION from >= 80%)" |
| `wor_doma` | 40-56 | 3 | 1 | 1 | |
| `wor_dino` | 45-63 | 29 | 1 | 1 | |
| `wor_kt_factory` | tower boot | 4 | 1 | 1 | SABIN L41 in formation $18E |
| `wor_kt_atma` | | 2 | 2 | 2 | CELES twice on Atma's walk ($1AA) |
| `wor_kt_guardian` | | 59 | 2 | 2 | CYAN ($1AB); LOCKE in formation 329 ($149) |
| `wor_kt_poltergeist` | | 45 | 5 | 5 | LOCKE, L43-51, from full HP in 329 four times and 272 once: "[death] f+1250 entity 2 char 1 from 3509/3727 by slot 1 cmd $00 atk $EF (ONE ACTION from >= 80%)" |
| `wor_kefka` | | 0 | 3 | 0 | |

The tower's bag in this replay, leg by leg (first and last `fenix=` of
each log): the factory 35 after Kohlingen's buy, 34 at its end; Atma 34 ->
32; Guardian 32 -> 30; Doom 30 -> 30; the Poltergeist 30 -> 25; the
Goddess and the plates 25.  So 10 of 35, against the 15 of #521's replay
at 3e6e8cea (route-wor-kefka-tower.md 7.6) and the 21-29 before it: the
tower's spend moves by draw, and its biggest single cause here is LOCKE,
party 2's bench, in the GtBehemoth's formation 329, which #521's grid
already named (40 of 74 deaths over 16 runs).  (The killer in 329 turned
out to be the Evil Oscar's Death counter to Magic, not the GtBehemoth:
move 1 below.)

**Where it over-levels.**  Through the World of Balance and the World of
Ruin to Owzer the seated party meets its key fights within a few levels
of the targets (the plan table above).  From the Jidoor grind on, the two
carriers run ahead: L49 at MagiMaster (target 45), 53-55 for the Gogo arc
(46), 55-57 in the Dreams (49), 64 at the tower's boot (52 a party), 69 at
Kefka (55).  The arc recruits meet their fights on target (CYAN and
SHADOW L52-53, RELM 54 and STRAGO 52 at the boot), and the bench is far
under: seven of the fourteen at L32-41 at the tower's boot.

**The bench's shape** (#496: about six to eight strong carrying the rest).
At the tower's boot: six at L52-64 (TERRA and CELES 64, RELM 54, CYAN and
SHADOW 53, STRAGO 52), GOGO at 44, and seven at L32-41.  At Kefka's boot,
after the tower's training: seven at L54-69 (TERRA and CELES 69, RELM 61,
STRAGO 59, SHADOW 57, CYAN 56, SETZER 54), five at L46-51 (LOCKE 51, MOG
50, GOGO 49, EDGAR 47, SABIN 46), GAU 33 and UMARO 37 out.  Kefka's order
put CELES, TERRA, RELM and STRAGO first.  So the line already ends in the
owner's shape; what is off is its top, eleven to fourteen over the targets,
and the price the tower pays to raise the bench from L32-41 (102 of its
125 random battles are the three training laps, and their deaths are
the bench's).

### The plan

**The aim, by level.**  A key fight is met near its target when its seated
party is within about three levels of it.  A carrier may stand up to about
five over; a member being carried, up to about ten under.  The World of
Balance meets this now and the plan leaves it alone.  In the World of Ruin
the lever is seats, not grinds: the carriers take a quarter of every
battle in grinds whose targets the labs set for someone else (the Jidoor
plain for STRAGO and RELM, the forest for CYAN and SHADOW), so moving those
seats to the bench lowers the top and raises the bottom for the same
battles.  The tower stays the bench's training ground in mixed parties, as
the owner plays it; the moves shrink what it has to raise.

**The moves, in landing order.**  Each is one branch, labbed from the
graph's own captures and replayed from the earliest leg it reaches.
Cheapest and latest first: an early move re-cuts more of the line, and its
re-measure then includes every later one's.

1. **Formation 329 against party 2's bench (#521).**  Not a seat or a
   grind but the place the tower's training meets its limit: LOCKE dies
   from full HP to one blow at L42 and at about L50 alike (2,766 to 3,727
   max HP), so levels alone do not
   answer it.  **Done (wt/v042-tower-deaths, route-wor-kefka-tower.md
   7.7).**  The blow is not the GtBehemoth's Meteor but the Evil Oscar's
   counter to Magic: Demon Kiss, a Death Special, aimed at whoever cast
   at it (slot 1 in 329 and in 272, "by slot 1 cmd $00 atk $EF").  LOCKE
   cast his boosted Fire at it, its weakness; TERRA's casts did the same
   in party 1's lap.  The driver now casts at another body, or swings at
   the Oscar, when the caster wears no Death guard: the Poltergeist leg
   from `wor-kt-doom-v1`, 16 shifts a side, went from 78 deaths and 78
   Fenix Downs to 2 and 2, every run passed, and the Guardian leg (12 a
   side) from 73 to 43.  The same branch fixed the Fanatics' Tower's
   X-Zone deaths (move 3's "separate finding").
2. **The dinosaur forest seats the bench the tower pays for**
   (`gen_wor_dino`).  Today TERRA and CELES ride it from 58 to 63.  Give
   one or both carrier seats to the bench members the tower's laps raise at
   the most cost (party 1's EDGAR and SETZER in #521's earlier replays,
   party 2's LOCKE in this one), keeping one carrier with a cure.  The
   leg's own rule (the plain by the Falcon until the lowest of the four is
   L45, then the forest to L52) does the catching up: about 150,000 XP
   takes EDGAR from 34 to 45, near fifty battles of group 49 at the 3,168 a
   member this doc's table gives it (an estimate), and the forest's 148,665
   a seat then puts him near 52.  Moves: the forest and the desert, every
   tower leg (party 1's landing training, which fought 45 battles to lift
   EDGAR to 46 and SETZER to 52, should shrink to a handful; the L.5 Doom check
   at 352; the laps' exposure to 329), Kefka's order.  Re-measure: the
   forest's wins and deaths by distinct key against `dn3`/`dn4` (1 lost of
   41), the levels at `wor-desert-v1`, the 7.6 grid on the new
   `wor-kt-atma-v1`, the tower's bag by leg, Kefka's grid.  The tower's
   floors (46, 46, 50 and the 60-battle cap) stay; what changes is how much
   they fight.  The line's random battles go up by the plain's and down by
   the training's.  **Done (wt/v042-leveling-move2), measured below.**
3. **The Fanatics' Tower's grind** (`gen_wor_relm`).  The plain is ground
   until STRAGO and RELM, who join at the party's average, stand at L46;
   TERRA and CELES climb 40 -> 49 beside them.  The generator's own lab
   found the tower's fourth floor lost at L46 (TERRA and CELES 49) and at
   L50 (52 and 53) alike, so levels are not its answer.  First a lab: the
   tower and MagiMaster with TERRA and CELES at their arrival levels (about
   41) against 49.  If they hold, the plain seats STRAGO and RELM with two
   of the bench and the carriers rejoin for the tower: about 290,000 XP
   moves from the two carriers to two bench members.  Moves: every arc from
   Thamasa to the tower, about forty states.  Re-measure: the tower's floors
   and MagiMaster, then each later arc's key fight.  The tower's nine
   deaths and six Fenix Downs in its no-XP battles are a separate finding
   (a one-action kill from full HP), not this move's.
4. **The free seats of the late arcs** (the Zone Eater and Gogo, Ebot's
   Rock, the Dreams, the Ancient Castle, the Colosseum).  Where an arc's
   story needs neither carrier, a seat goes to one of the strong six to
   eight the owner names; the carriers stop at their arcs' targets.  One
   branch an arc, upstream first, each re-measuring its key fight and the
   levels at every later save.  This is the biggest replay and the one
   that most needs the owner's answer on who the strong ones are.

The canon line stays the middle path: no move adds a hunt to it, and each
changes only who sits in a grind or an arc the line already plays, the
way a player rotates the party.  The hunts stay on their branches (#496
had offered a pre-tower training stretch as their main-line home; it was
withdrawn).

### Move 2, measured (2026-11-12)

EDGAR takes CELES's seat in the dinosaur forest; TERRA stays as the carrier
with a cure (her 1-MP Cure under the Economizer, and Ice), CYAN and SHADOW
the arc's own.  One seat, not both: the forest's four need a Cure and Ice
at the boot's levels (route-wor-side-trips.md section 4: Fight alone lost,
Ice won 6 of 6), and among the bench only a stone moved off TERRA or CELES
would bring them.  EDGAR rather than SETZER: he is one of the strong eight,
and the tower's split hands the Exp. Egg to its furthest behind, which is
then SETZER.  The seats are taken in the Falcon's cabin at the leg's start,
and the dress moves the Egg to EDGAR there ("the Exp. Egg $E4 on EDGAR's
slot 4 (furthest behind on levels)").  The tower's caps follow the bench's
arrival: party 1's landing training at most 40 battles (was 60), the
Goddess's lap at most 10.

Evidence: `build/attempts/wt/v042-leveling-move2/` (its `README.txt`).
The line is the replay from power-on at 8bfc3e1a (gate green; the scoped
replay at 4f550744 read the same, leg for leg) against main's at
849db981 (#524 round 2, the line at 9d0374c8).

| leg | random battles before -> after | levels after (before) |
|---|---|---|
| `wor_dino` | 20 -> 38 (the plain 0 -> 27, the forest 20 -> 11) | TERRA 63 (61), CYAN 53 (52), SHADOW 54 (56), EDGAR 52 (34, benched), CELES 57 benched (60) |
| `wor_desert` | 8 -> 8 | TERRA 64, CYAN 54, SHADOW 55, CELES 57 |
| `wor_kt_factory` | 4 -> 4 | |
| `wor_kt_atma` | 2 -> 2 | |
| `wor_kt_guardian` | 59 -> 40 (the landing lap 45 -> 25) | TERRA 67, RELM 59, EDGAR 56, SETZER 48 (67, 62, 47, 54) |
| `wor_kt_doom` | 18 -> 18 | CYAN 58, SHADOW 59, SABIN 46, GOGO 50 |
| `wor_kt_poltergeist` | 46 -> 43 (the lap 45 -> 42) | CELES 63, STRAGO 60, LOCKE 51, MOG 50 (66, 60, 52, 50) |
| `wor_kt_goddess` | 0 -> 1 | EDGAR 57, SETZER 49 |

Raw lines: "[wor] f105995 the plain by Maranda: 27 battles (won 13F x22, won
143 x5) ... SHADOW L51 ..., EDGAR L45 ..., CYAN L50 ..., TERRA L60"; "[wor]
f163390 the forest: 11 battles (won 140 x6, won 141 x5) ... SHADOW L54 ...,
EDGAR L52 ..., CYAN L53 ..., TERRA L63"; "[train] f198968 party 1 after 25
battles by its landing: TERRA L66, RELM L59, EDGAR L56, SETZER L46" (at
9d0374c8: "party 1 after 45 battles by its landing: TERRA L66, RELM L61,
EDGAR L46, SETZER L52"); "[train] f189312 party 2 on 334's north: after 42
battles: CELES L63, STRAGO L60, LOCKE L51, MOG L50".

**Totals.**  From the forest's boot to Kefka: random battles 157 -> 154;
Kefka's Tower's own 129 -> 108.  Deaths and Fenix Downs that left the bag
(`supplies.py`, every attempt): 12 and 11 -> 9 and 8; the bag reached Kefka
with 29 Fenix Downs (28 before).  Every leg passed on its first attempt,
Doom and Kefka included ("PASS (frame 96805) attempts=1/3", "PASS (frame
167821) attempts=1/3"): #525's retries did not recur.  The battle budget
from power-on falls by three.

**The forest's fights.**  The line and eight seed shifts of the leg from the
same `wor-colosseum-v1` capture: 86 forest battles over 60 distinct battle
keys, one lost (`beC0-g0140`, the two Tyranosaurs, shift 3's fourth forest
battle: "deaths=e2@f+1427 ... e3@f+5383:925/5237:bp0 class=worn down (no
one-shot, no pips banked)"), against 1 of 41 at the old seats (`dn3`/`dn4`).
The other seven shifts passed.

**What it leaves.**  Party 2's lap on 334's north is bound by MOG (L41 ->
50 for the Poltergeist), whom no forest seat reached, so it barely moved;
a second seat for MOG would need a Cure and Ice in the forest without
TERRA or CELES, or the Poltergeist's L50 relabbed.  SETZER, carried,
now meets the Guardian's lane at L46-48 rather than 52-54 (the Egg works
for the lap's level, not past it).  CELES rides the forest no longer, and
stands at 57-63 through the tower instead of 60-66.

**#521** (the tower's Fenix Downs): moves 1 and 2 are its leveling half.
Move 1 is the lab its own write-up left open (formation 329); move 2
lowers the training the tower's random battles feed.  The stock (35 at
Kohlingen, Kefka's floor 10) is re-read after each.

**#522** (`crescent_landing`'s no-effect retry): not a leveling matter.
It is a press the game does not answer in `gen_voyage`, in the World of
Balance, which no move here reaches, so none of these replays re-measures
it.  In this replay the leg passed on its first attempt with no watchdog
trip ("[watch] 2098 samples, pad down 3528 frames, 0 trip(s)", "PASS
(frame 33577) attempts=1/3"); it stays its own lab.

**The owner's answers (2026-11-11) and the calls taken.**

- *Grind budget:* about 690 random battles is fine overall, but Kefka's
  Tower may need fewer than its 125 (102 of them training laps).  Call:
  move the bench's catching up earlier (move 2) and trim the tower's laps
  to what its fights need.
- *The strong six to eight* is ours to pick (owner: favourites in the end
  game are preference).  Call: TERRA, CELES, RELM, STRAGO, SHADOW, CYAN,
  EDGAR and LOCKE; SETZER carried (the Exp. Egg goes to whoever is furthest behind, which in the tower is often him).
- *The dinosaur forest:* no preference, so long as the line stops there and
  proves its fights doable.  Call: seat the bench there (move 2).
- *Holding the carriers back:* ours to choose; a human player picks
  favourites and lets them grow well past the rest.  Call: don't cap them.
  Move 3 (the Fanatics' Tower at the carriers' arrival levels) is dropped;
  the favourites stay strong and the bench is raised to the tower's need.

**Questions for the owner (as asked).**

- *How grindy should the canon playthrough be?*  Today it fights about 690
  random battles from power-on to Kefka (177 in the World of Balance,
  389 in the World of Ruin before the tower, 125 in it).  My
  recommendation is to hold that number about where it is and move
  battles rather than add them: move 2 adds the plain's and takes about as
  many from the tower's training.
- *Who are the strong six to eight?*  The line's own answer at Kefka is
  TERRA, CELES, RELM, STRAGO, SHADOW, CYAN and SETZER.  I would name those
  six without SETZER, plus EDGAR and LOCKE: the two whose tower deaths have
  cost the most Fenix Downs (party 1's lane in #521's replays, LOCKE in
  this one).  SETZER's Exp. Egg already raises him faster than anyone in
  the tower, so he can stay carried.
- *Is seating the bench in the dinosaur forest the pre-tower training
  stretch you ruled out?*  I read it as a seat in a grind the line already
  makes (you placed the forest late so its XP feeds the tower), but it
  does move training out of the tower, where you said the bench levels.
- *Should the carriers be held down?*  #496 asks to raise the average
  while keeping the max down; the carriers are eleven to fourteen over at
  the tower and Kefka.  I would hold them to about five over by moving
  seats, and never by cutting a grind a lab set.

## How to regenerate

```py
import glob, os, sys; sys.path.insert(0, "tools")
import savestate_party as sp
for d in sorted(glob.glob("tools/tests/checkpoints/*-v1")):
    party, err = sp.read_party_sram(glob.glob(d + "/*.sram")[0])
    active = [m for m in party or [] if m["active"]]
    print(os.path.basename(d), [(m["name"], m["level"]) for m in active])
```

Each member dict carries `name`, `level`, `hp`/`maxhp`, `mp`/`maxmp`, `weapon`,
`gear`, and the `active`/`party` flags — so this same read backs a gear/HP
audit at any checkpoint, not just levels.

The bench, which that read leaves out: `python3 tools/roster.py
tools/tests/checkpoints/*-v1` (every recruited character in each save).
The line leg by leg, from a replay's `build/states` (the leveling plan's
tables): `python3 tools/route_levels.py --branches` (`--csv` for the long
form); run it in the replay's tree, or with `--repo` and `--dir` pointed
at one.
