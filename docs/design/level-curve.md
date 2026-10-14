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
policy (#434): `build/attempts/wt/v031-cleanup/levels-421.log`.  The
scenario rows show the one member saved in that slot.

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
| Esper Mtn (`esper-mtn-save-v1`) | TERRA 24 · LOCKE 26 · STRAGO 26 | L24–26 |
| Ultros③ (`ultros-won-v1`) | TERRA 24 · LOCKE 26 · STRAGO 26 · RELM 23 | L23–26 |
| **FC entry (`thamasa-done-v1`)** | **TERRA 24 · LOCKE 26 · STRAGO 26 · RELM 23** | **L23–26** |
| FC landing (`fc-landing-v1`) | TERRA 25 · LOCKE 26 · EDGAR 25 | L25–26 |
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

The routed party reaches the **Floating Continent at L23–26**
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
  loss** (the `_ca5ea9` handler). At L23–26 that is a survivability test, not a
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
  are all **WoR-gated** (L44–77) and unreachable pre-FC.
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
`route_data.py`; `projection.log`).  Levels past the Falcon are
**estimates** until each arc plays them.

### Measured: the landing to the Falcon

| checkpoint | active party | Potion / Fenix / Tincture / Revivify | gil |
|---|---|---|---|
| `wor-start-v1` | CELES 25 | 85 / 31 / 11 / 5 | 181,494 |
| `wor-tzen-door-v1` | CELES 27 | 85 / 31 / 11 / 5 | 201,220 |
| `wor-sabin-v1` | SABIN 28 · CELES 28 | 85 / 31 / 11 / 5 | 184,572 |
| `wor-edgar-v1` | EDGAR 31 · SABIN 31 · CELES 32 | 85 / 31 / 13 / 5 | 248,834 |
| `wor-kohlingen-v1` | EDGAR 32 · SABIN 32 · CELES 33 · SETZER 32 | 97 / 31 / 13 / 10 | 239,364 |
| `wor-falcon-v1` | EDGAR 33 · SABIN 33 · CELES 34 · SETZER 33 | 79 / 31 / 13 / 32 | 280,318 |

`wor-falcon-v1 EDGAR L33 1207/1803 ... CELES L34 1313/1900 ... SETZER L33
1402/1800`; `xp EDGAR 101737, SABIN 105683, CELES 111711, SETZER 103319`.

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
  `:93791`; Gogo and Umaro through `InitChar`'s average, Gogo +2).  From
  the Phoenix Cave (two parties) and Kefka's Tower (three) the route levels
  more than four, so rotation keeps the extra members within
  `audit_levels.py`'s straggler gap of 3.

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
`projection.log` lists the counts) from `wor-falcon-v1`'s mean 105,612 XP.
The target column is the healthy level for the stop's key fight; it is an
estimate until a lab sets it, as the Tentacles' L30 (route-wor-edgar.md
4.1) and Dullahan's were.

| milestone | key fights (ROM: L, HP) | what bites (AI script) | projected | target |
|---|---|---|---|---|
| v0.27 Terra | Phunbaba (L26 60,000; L31 28,000 / 26,000) | Blow Fish, Bolt 3; absorbs bolt | 33-34 | as reached: the boss is under the party |
| v0.28 Cyan | Storm Drgn (L74 42,000) | Aero, Cyclonic (Near Fatal), Wind Slash; absorbs wind, weak bolt | 36 | 35 with the gear policy's kit (38 before; "Buying power" below) |
| v0.29 Narshe | Umaro (L33 17,200), Tritoch (L62 30,000), Ice Dragon (L74 24,400) | Tritoch: Ice 3, Cold Dust (Frozen); nulls bolt and five more, weak fire | 39 | 40 |
| v0.30 Jidoor & Thamasa | Chadarnook (L37 56,000; L41 30,000), MagiMaster (L68 50,000), Holy Drgn (`White Drgn`, L71 18,500) | MagiMaster: Fire/Ice/Bolt 3, Doom, and **Ultima as his death counter**; the tower is magic-only | 41 | 45 for MagiMaster |
| v0.32 Locke | Red Dragon (L67 30,000) | -- | 44 | 44 |
| v0.34 Gogo | Hidon (L43 25,000), Doom Gaze (L68 55,555), Dirt Drgn (L53 28,500) | -- | 46 | 46 |
| v0.35 Dreams | Wrexsoul (L53 23,066), Blue Drgn (L65 26,900) | -- | 49 | 49 |
| v0.38 Kefka's Tower | Guardian (L71 50,000; L67 60,000), Inferno (L67 30,800), the statues (Doom L73 63,000, Goddess L68 44,000, Poltrgeist L67 58,000), Gold and Skull Drgn (L62) | -- | 51 | 52, each of three parties |
| v0.39 The End | Kefka (L71 62,000) | Goner, Meteor, Havoc Wing; Ultima as a counter | 51 | 55 |

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

**Gil is not the limit.**  `wor-falcon-v1` carries 280,318, and the plains
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
