# The OT6 level curve — party levels by area

> This is the authoritative party-level reference, and it is *empirical*: the
> levels below are read directly off the routed **checkpoint savestate chain**
> (`build/states/*.mss`), not from a vanilla walkthrough — so they are the
> levels OT6's own route actually reaches, which is what tuning must answer to.
>
> Regenerate with `tools/savestate_party.py`'s `read_party` over the checkpoints
> (the snippet at the bottom). Requires `make savestates` to have built the
> chain.

## The curve (active party at each checkpoint)

| area / checkpoint | party (name L) | range |
|---|---|---|
| Narshe start (arvis_wake) | TERRA 4 | L4 |
| Figaro (figaro_intro) | TERRA 5 | L5 |
| Mt. Kolts (kolts_cave) | TERRA 8 · LOCKE 9 · EDGAR 10 | L8–10 |
| Vargas (vargas_won) | TERRA 10 · LOCKE 10 · EDGAR 11 · SABIN 12 | L10–12 |
| Returner Hideout | TERRA 10 · LOCKE 11 · EDGAR 11 · SABIN 12 | L10–12 |
| Lete River (banon aboard) | TERRA 10 · EDGAR 11 · SABIN 12 · BANON | L10–12 |
| Sabin scenario (camp/Doma) | CYAN 13 · SHADOW 11 · SABIN 13 | L11–13 |
| Sabin's leap done (sabin_done) | UMARO-slot 17 | ~L17 |
| Battle for Narshe (kefka_won) | LOCKE 12 · EDGAR 13 · SABIN 13 · CELES 12 | L12–13 |
| Zozo arrival (zozo_arrival) | LOCKE 18 · EDGAR 18 · SABIN 19 · CELES 18 | L18–19 |
| Zozo (zozo_done) | LOCKE 18 · EDGAR 19 · SABIN 19 · CELES 18 | L18–19 |
| Opera / Vector (ultros2_entry) | LOCKE 14 · EDGAR 15 · SABIN 15 | L14–15 |
| Blackjack (post-Vector) | LOCKE 14 · EDGAR 15 · SABIN 15 · CELES 14 | L14–15 |
| Crescent → Thamasa | TERRA 14 · LOCKE 15 · SHADOW 14 | L14–15 |
| Esper Mtn / Ultros③ | TERRA 15 · LOCKE 16 · STRAGO 17 | L15–17 |
| **FC entry (thamasa_done)** | **TERRA 15 · LOCKE 16 · STRAGO 17 · RELM 15** | **L15–17** |

## The supply curve (what the bag carries at each level)

The care split is a directive: **outside battle heal with Tonics** (the
field care between fights; a menu turn is free), **in battle heal with
Potions** (turns are scarce, and a Tonic's +50 is under the measured
round cost from the Sabin scenario on), and a **Fenix Down** is the WoB's
only answer to a death.  The stock the route carries, topped up at every
town that sells the item, scales with the active party's highest level:

| item | band | first shop on the route |
|---|---|---|
| Tonic | ~level x5, cap 99 | Figaro Castle (shop 4, `gen_edgar`) |
| Fenix Down | ~level, ~15-20 | South Figaro (shop 8, `gen_kolts`) |
| **Potion** | **~level x1.5, minimum 10** | the Phantom Train's ghost merchant (shop 85, `gen_sabin_train`; L14 -> 21) |

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
It is a World of Balance band: `audit_supplies` stops applying it at the
WoR landing's graph row (`wor_landing` and its `escape_start` sibling),
where the party, the shops and the level curve are all different.

The WoB Potion shops on the route, decoded from `npc_prop.asm` (the
counter NPC's event) and `shop_prop.dat` (the rows), with the stop each
generator makes (#176):

| shop | where | rows (Tonic / Potion / Fenix) | stop |
|---|---|---|---|
| 85 | Phantom Train car B, map 85 | 0 / 1 / 4 | `gen_sabin_train`: POTION to 30 (L14 band 21 + the train fight's 9) |
| 12 | Mobliz, map 164 | 1 / 2 / 5 | `gen_sabin_gau`: POTION to 23 (L15) |
| 15 | Nikeah, the counter at (24,39) on town map 169 | 0 / 1 / 5 | `gen_sabin_trench`: POTION to 27 (L18).  The last Potion shop before the reunion: the Terra scenario never walks a town with control (its Narshe arrival is the isolated clifftop ledge; Arvis's front door lies past the reunion trigger; the map-22 staging boxes the party -- `probe_narshe_preshop`), so this bag is what TERRA's L13 party (band 20) and the Battle for Narshe (L14, 21) carry. |
| 3 | Narshe, map 26 off town map 20's (41,22) door | 0 / 1 / 4 | `gen_zozo1_submerge`: TONIC to 99, FENIX DOWN to 15, no Potion line (Nikeah's 27 arrives intact, over the L14 band).  The last Tonic counter before the post-opera checkpoint. |
| 22 | Jidoor, map 201 off town map 198's (27,41) door; no Tonic | - / 0 / 5 | `gen_zozo2_arrival` after the L18 grind: POTION to 39 (the #158 target of 30 + 9 for field care: 49 Tonics measured from Jidoor to the opera's end), FENIX DOWN to 20.  `gen_narshe_mission`'s plains grind restocks here too: POTION to 35 per leg, to 60 on departure. |
| 24 | Albrook, map 328 off (7,13); no Tonic | - / 0 / 5 | `gen_vector_entry`: POTION to 35 (L18 band 27 + the factory's measured 6, a floor: the bag ran dry at Ifrit & Shiva, + 2 for the factory's 9 Tonics of field care).  Vector itself sells no Potions -- weapon 27 and armour 28 only (maps 246/248). |
| 44 | Narshe again, once `$006B` (the factory escape) swaps shop 3 for 44; no Tonic | - / 0 / 2 | none: `gen_narshe_mission` shops at Jidoor instead (row 22 above) |
| 15 | Nikeah again, by the Blackjack (lands on world (116,61); town 169 (1,35)) | 0 / 1 / 5 | `gen_narshe_mission` (#210): TONIC to 99 before the plains grind and again on the flight to Narshe, each when the bag is under 74 (3/4 of the L21-23 band of 99).  The first Tonic counter the route can reach after Narshe's swap to 44: the Blackjack's wheel is dead until the factory escape (`_caf532` returns while `$01B3`/`$01B4` is clear -- `probe_tonic_airship`), South Figaro's shop 8 still sits behind the occupation's troopers, and Figaro Castle's merchants refuse EDGAR and SABIN. |
| 24 | Albrook again | - / 0 / 5 | `gen_voyage`: POTION to 38 (L25; no field-care extra: the legs to Thamasa's Tonic counter spent none) |
| 35 | Thamasa, map 347 off (26,37) | 0 / 1 / 6 | `gen_thamasa_fire`: POTION to 45 (L26 band 39 + 6, the spend the seeded lineage measured from fire_out's 15 to thamasa_done's 9), FENIX DOWN to 20, TONIC to 99.  The re-cut M..P lineage (2026-09-16) spent none of it: fire_out, esper_mtn_save, ultros_won and thamasa_done all carry `potion=45`. |
| 35 | Thamasa again, the FC prep | 0 / 1 / 6 | `gen_fc_landing`: POTION to 65 (L29 band 44 + 21, the old lineage's measured spend: the IAF gauntlet 16, the alcove leg 3, the escape 2), FENIX DOWN to 25, TONIC to 99, then the bag arranged (combat items on top).  Re-cut 2026-09-16: the gauntlet's winning attempt spent 8 (`fc_landing` lands with `potion=57`, band 41 at L27) and the alcove leg 10 (`fc_alcove` at 47, band 42 at L28); the first two gauntlet attempts wiped in the Air Force fight -- a lab signal, not a fixed segment.  Both targets were held for #179 (the bigger purchase moved the RNG under fire_out's burning-house walk and an IAF wave) until the segment runner (#178) retried such losses; the walk itself needed two fixes a person would make (wait out a wandering flame; heal after the FlameEater's cutscene, not during it), in `gen_thamasa_fire` and `H.fieldCare`/`H.newCareDriver`. |

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

## Zozo: the level gate nobody authored (#155, levelled for #158)

The routed Zozo party as it was (L14-15) met map 225's solo SlamDancer
(formation $069, 31% of that map's rolls), whose `if_one_monster_type`
branch casts Fire 2 / Ice 2 / Bolt 2 every turn.  Measured in
`tools/tests/lab_zozo_street.lua` (15 seeds x 5 policies, raw damage
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
(`lab_zozo_street.lua`'s control policy on a fixture baked at the P9a
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
`probe_j39_backattack`), and the no-effect watchdog cut it at frame
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

The routed party reaches the **Floating Continent at L15–17**. Rough vanilla
FF6 expectation for the same content is **~L25–30** (AtmaWeapon is a ~L30 fight
in vanilla). So OT6 arrives at the FC roughly **ten levels light**, and the gap
is widest here — the WoB's hardest stretch against its lowest-relative party.

The deficit is real, and there are two answers, not one — a player can lean on
tactics, **or grind to close part of the gap** with the Blackjack. See
"Pre-FC grinding" below. Two things carry the deficit even without grinding:

- **Break, not levels, is the damage.** OT6's fights are Octopath shield/break
  tactics; boss shield and weakness rows are authored *against the routed
  levels* (`check_boss_rows.py` is green through Nerapa, i.e. the FC bosses'
  data already matches the party they will actually meet). Raw level gates HP
  and survivability more than damage output.
- **Prep is the lever.** Row, boost banking, weakness coverage, and the field
  care between fights (the humane line) are what a player spends to clear a
  stretch they are under-levelled for — the same discipline the Thamasa arc
  already shipped (`ROADMAP.md`: "winnable at route level with a player's
  prep").

Practical consequences of the route as it stands:
- The IAF gauntlet is eight fights with **no save and a real Game Over on a
  loss** (the `_ca5ea9` handler). At L15–17 that is a survivability test, not a
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
  (mid-map). Exact fly-to coordinates want a world-tile probe (the #131
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

The owner's warning was "behind in gear **and** levels"; the gear half, read
from the same checkpoint:

| char | weapon | armor | relic |
|---|---|---|---|
| TERRA | **ThunderBlade** (bolt) | Mithril Vest | — |
| LOCKE | **ThunderBlade** (bolt) | Kung Fu Suit | — |
| STRAGO | Fire Rod | Cotton Robe | — |
| RELM | Chocobo Brush | Silk Robe | Memento Ring |

Two things stand out:
- **Two ThunderBlades** — the party already carries bolt weapons, and the whole
  IAF (and AtmaWeapon) is bolt-weak (`floating-continent-route.md` §3). Front-row
  Terra/Locke swings, or their Thunder, are a natural break answer; a bolt-leaning
  three is available without new purchases.
- **Empty relic slots on three of four**, mid-tier (Mithril/cloth) armor. Relics
  are the clearest under-gear, and survivability relics are exactly what the IAF's
  care-stop-less attrition punishes the lack of. The Blackjack reopens WoB shops
  (Thamasa and others), so gear/relic shopping is part of FC prep alongside a
  grind.

## How to regenerate

```py
import sys; sys.path.insert(0, "tools")
import savestate_party as sp
for stem in ("arvis_wake", "kolts_cave", ..., "thamasa_done"):
    party, err = sp.read_party("build/states/%s.mss" % stem)
    active = [m for m in party if m["active"]]
    print(stem, [(m["name"], m["level"]) for m in active])
```

Each member dict carries `name`, `level`, `hp`/`maxhp`, `mp`/`maxmp`, `weapon`,
`gear`, and the `active`/`party` flags — so this same read backs a gear/HP
audit at any checkpoint, not just levels.
