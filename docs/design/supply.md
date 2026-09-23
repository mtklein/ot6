# The care supply: Tonics, Potions, Tinctures, Tents and inns (#231)

Owner ruling, 2026-09-21 (#231): Tinctures and Elixirs are Tonic/Potion
analogues one level rarer -- a Tincture is costed like a Potion, an Elixir
above that.  Field care should learn Tinctures and Elixirs the way it
knows healing items, and reason about Tents and inns, which restore both
resources: there is a cost-benefit analysis to do among health-only,
MP-only, tent and inn.  Elixirs stay out of field care; a dry caster
mid-fight is the fight driver's call.

The supply band in [level-curve.md](level-curve.md) predates MP being a
per-fight consumable (#219 priced boosted abilities), which is why casters
run dry between save points: #228's descent had EDGAR's 87 MP buying two
boosted crossbows across seven battles with no refill.  This page is the
measured design for the MP half of the band.  Every number is read off the
ROM's own tables or a generated fixture; the readers and their output are
under `build/lab/mp-supply/`.

## 1. Prices and yields, off the ROM

`ff6/src/menu/item_prop_en.dat`, 30 bytes per item, decoded the way the
field item routine reads it (`item.asm` `lpitem_exec`: +$13 bit 3 restores
HP, bit 4 restores MP, bit 7 makes +$14 a count of sixteenths of the
maximum instead of a flat amount; the price is the word at +$1C).  The
twelve records are byte-identical in `build/ot6.sfc`, the vanilla ROM and
the data file (`build/lab/mp-supply/item_records.txt`):

| item | id | restores | price | gil per HP | gil per MP | where it comes from |
|---|---|---|---|---|---|---|
| Tonic | `$E8` | +50 HP, one member | 50 | 1.0 | -- | every item counter but Jidoor's and Albrook's |
| Potion | `$E9` | +250 HP | 300 | 1.2 | -- | every counter from the Phantom Train on |
| X-Potion | `$EA` | full HP | 2 | -- | -- | not sold (no shop row holds `$EA`); chests |
| Tincture | `$EB` | +50 MP | 1500 | -- | 30 | Figaro Castle 4, Narshe 3, Jidoor 22, Albrook 24, Thamasa 35 |
| Ether | `$EC` | +150 MP | 2 | -- | -- | not sold; the gate cave chest |
| X-Ether | `$ED` | full MP | 2 | -- | -- | not sold |
| Elixir | `$EE` | full HP and MP, one member | 2 | -- | -- | not sold; chests (the bag holds 2 at the descent, 4 by Thamasa) |
| Megalixir | `$EF` | full HP and MP, whole party | 2 | -- | -- | not sold |
| Fenix Down | `$F0` | revive at 2/16 of max HP | 500 | -- | -- | every item counter |
| Sleeping Bag | `$F6` | full HP and MP, one member; save point only | 500 | -- | -- | Figaro Castle 4, South Figaro 8, Mobliz 12, Nikeah 15, Narshe 3, the train 85; the bag holds 3 from chests |
| Tent | `$F7` | full HP and MP and revival, whole party; save point or world map only | 1200 | -- | -- | Figaro Castle 4, South Figaro 8, Mobliz 12, Nikeah 15, Narshe 3, Jidoor 22, Albrook 24, Thamasa 35 |

A price of 2 is the game's way of saying "not for sale": the value only
ever feeds the sell-back half of the shop.  `shop_prop.dat` (128 shops of
eight rows) holds no `$EA`, `$EC`, `$ED`, `$EE` or `$EF` anywhere, so
those five are chest items for the whole game.

Two prices that do not fit in the columns above:

- **A Tent is 1200: as much as 24 Tonics, less than one Tincture.**  It
  restores every pool of every member, so its gil per point is whatever the
  party is missing divided into 1200, and it beats the items whenever the
  party is missing more than 1200 HP in total *or* any member is missing
  more than 40 MP.  Its limit is where it can be used: the item list greys
  it off a save point (`item.asm:579-582`, `$0201` bit 7, which
  `OpenMainMenu` copies from the save-enable bit `$01BF`; the world map sets
  the same bit).
- **An inn is 80-350 gil on this route for the same whole-party full
  restore, statuses cleared** (the rest routine `_cacd3c`; `gen_kolts`'s
  `innRest` asserts every member at full HP and full MP after it).  An inn
  pays for itself at two to seven Tonics, and it refills MP that only a
  1500-gil Tincture otherwise touches.  Its limit is that it is in town.

The inns, read off `event_main.asm` (`take_gil` beside the innkeeper's
dialog) and `npc_prop.asm` (the keeper's map), `build/lab/mp-supply/inns_and_shops.txt`:

| town | inn map | price | the route passes it |
|---|---|---|---|
| South Figaro | 76 | 80 | `gen_kolts` already rests here (Mt Kolts prep) |
| Returners' hideout | 111 | free | `gen_returner` / `gen_banon` |
| Mobliz | 160 | 100 | Sabin scenario, `gen_sabin_gau`'s shop |
| Nikeah | 171 | 150 | the trench's end; the airship stops (`gen_narshe_mission`, `gen_gate_cave_save`) |
| Narshe | 28 | 200 | after Kefka, `gen_zozo1_submerge`'s shop -- and never before it (see squeeze 1) |
| Jidoor | 206 | 250 | `gen_zozo2_arrival`, `gen_narshe_mission`'s restocks |
| Albrook | 325 | 300 | `gen_vector_entry`, `gen_voyage` |
| Vector | 245 | "It's on the house", then 1000 GP stolen while the party sleeps (`take_gil 1000`, dlg `$055A`) | `gen_vector_entry` -- not an inn a person uses twice |
| Thamasa | 346 | 1500 as strangers (`$007D=0` or `$008D=0`); 1 GP once both are set | both switches are set at `thamasa_night` already (measured), so every Thamasa stop rests for 1 GP |
| Kohlingen 191, Maranda 288, Tzen 308 | -- | 200 / 200 / 350 | off the walked route |

## 2. Counters, inns and save points against the three squeezes

Where each option is on the route, read off `shop_prop.dat` (which shop
holds `$EB` and `$F7`), `event_trigger.asm` (every `SavePoint` trigger and
its map) and the seeded fixtures (`build/lab/mp-supply/bag_scan_seeded.txt`:
gil, every member's HP and MP, and the healing stock at all 94 states).

Tincture counters on the walked route: Figaro Castle shop 4 (row 1, the
TERRA+LOCKE window `gen_edgar` shops in), Narshe shop 3 (row 2), Jidoor 22
(row 1), Albrook 24 (row 1), Thamasa 35 (row 2).  The issue's "Vector-area
31" is Tzen's item shop (map 307, counter `_cc5c81`; Tzen is map 306,
airship-only, off the route), Kohlingen's 19 is off the route, and Narshe's
44 is the post-escape variant the route never opens.  Tent counters: the
same five plus South Figaro 8, Mobliz 12, Nikeah 15 and the merchant in
SHADOW's yard (39).  Revivify (`$F1`, 300): Jidoor 22 row 4, Albrook 24 row
4, Thamasa 35 row 5 -- the scope note on #231 asked for a small line of it
once this column existed.

**Squeeze 1, the Narshe descent (#228).**  `reunion_ready` (map 22, the
staging) to KEFKA: no shop, no inn, no save point (the only one in the
Narshe maps is the lose-path regroup, 34 (25,5)).  EDGAR walks in at 2 of
87 MP -- the Lete River left him at 12 (`rapids_done`), the clifftop at 2
(`terra_clifftop`) -- and the bag holds `tincture=0 elixir=2 sleepbag=3
tent=2`; the bags and Tents are greyed off a save point.  Nothing the
Terra scenario walks sells a Tincture, and Narshe's own inn and counter
are behind the reunion trigger (`probe_narshe_preshop`).  The one counter
before it is Figaro Castle at L5-7: `figaro_entry gil=5338`, and the stop
spends 1300 on Tonics and 1250 on the two tools, leaving 2788, after which
`gen_kolts` grinds until the purse covers South Figaro's whole bill (the
gear, the relics, the inn and the supply band, priced off the ROM:
"gil=10896 of the town's 10230" on the regenerated chain,
build/attempts/wt/gen-robust-fix/chain/south_figaro.log).  A
Tincture is 1500 there -- 28% of the purse, the same 1500 whose Tonic
equivalent that generator's own note says starved South Figaro's Softs --
and one bought at L7 would be drunk by the scenarios' care long before
L13.  So the descent stays what #228 made it: a ration-and-level-up
segment.  This column does not reach it, and this page does not pretend it
does.

**Squeeze 2, the Vector approach.**  Albrook first: inn 300 (map 325),
shop 24 with Tincture, Tent and Revivify, and 98,495 gil in the purse
(`vector_entry`).  Vector sells nothing usable (weapon 27, armour 28) and
its inn robs the party.  Inside the factory: the vanilla save room 270
(25,10), where `mrf-save-room-v1` is cut; OT6's own save point 273 (26,53)
after Ifrit & Shiva (`n024-entry-save-v1`); then the tubes and the mine
cart with nothing.  The measured pools at those stops:

    ifrit_entry            EDGAR 120/160  SABIN 85/157  CELES 83/158       tent=4
    magicite_ifrit_shiva   LOCKE 105/150  SABIN 125/157 CELES 13/158       tent=4
    n024_won               LOCKE 168/172  EDGAR 119/171 SABIN 116/179      tent=4
    n128_won               LOCKE 148/172  EDGAR 113/171 SABIN 91/179       tent=5

119-226 MP short per stop (the deficits summed over the party) with four
Tents in the bag and a save point underfoot twice.

**Squeeze 3, the Floating Continent prep.**  Thamasa: inn 1 GP (map 346),
shop 35 with Tincture, Tent and Revivify, the town's own save point 343
(33,25), 177,513 gil (`thamasa_done`).  The IAF gauntlet has no field
window (eight fights, a Game Over on a loss, `floating-continent-route.md`).
Then the landing save 394 (7,12) -- `fc_landing` stands on it with the
save-enable bit set (`$01BF=1`, measured) at

    fc_landing   TERRA 178/228  LOCKE 73/256  EDGAR 114/218   tent=10 tincture=4

-- and the alcove save 358 (8,10) before the descent.  The Sealed Gate cave
is the same shape a chapter earlier: `gate_cave_save` stands on 291 (12,12)
with `$01BF=1`, TERRA at 45/170, `tent=10`.

## 3. The rule for each option

In a person's terms, one rule each; field care carries the first four, the
route carries the inn, and the sixth is the fight driver's.

- **Tonic** -- HP only, cheap, anywhere.  The field heal between fights,
  as the existing directive says: a menu turn is free, so a big hole costs
  Tonics rather than turns.
- **Potion** -- HP in combat, where turns are scarce and +50 is under a
  round's cost.  Never for a field top-up while a Tonic remains.
- **Tincture** -- a caster dry between save points, anywhere.  At 30 gil
  per MP it is the dearest point in the game, and it is bought because MP
  is the one thing nothing cheaper restores away from a save point.  The
  band it serves: a living member whose MP is under a quarter of their
  maximum drinks one, and another if still under; the last one in the bag
  is kept back the way the last four Tonics are.  Every member is a caster
  in OT6 -- every verb but Fight costs MP (`mp-economy.md`) -- so there is
  no list of who qualifies.  Off a save point with a Tent in the bag this
  is still the answer; on one it is not (next rule).
- **Tent** -- a save point (or the world map) with both pools down: the
  whole party, both pools, revival, 1200.  Cheaper than one Tincture and
  as dear as 24 Tonics, so where the item list offers it, it is pitched
  whenever a Tincture would otherwise be due for anyone, or the party's HP
  deficit alone is past 1200; below that the Tonics are the cheaper answer
  and the Tent is saved.  A Sleeping Bag (500, one member) sits between a
  Tent and a Tincture; the route only ever holds the three it finds in
  chests, and field care leaves them to the person.
- **Inn** -- in town, both pools, whole party, statuses, for 80-350: the
  cheapest per point whenever more than a handful of Tonics' worth is
  missing, and the only full MP refill that costs less than one Tincture.
  An inn is a walk and a talk, not a menu, so it is the route's step
  (`M.innRest`, `gen_kolts`'s `innRest` promoted with the keeper's spot
  and the price as arguments), taken at a stop whose next stretch has no
  counter when somebody is short: Albrook before Vector (`gen_vector_entry`;
  the seeded boot reached the shop with LOCKE 471/619, EDGAR 475/620 and
  127/149 MP).  Thamasa's 1-GP bed before the gauntlet is not taken,
  because `thamasa_done` arrives whole in both pools (measured); the step
  is there for a run that does not.
- **Elixir** -- never in the field.  `careKernel` does not name `$EE`,
  `$EC` or `$ED`, and a roster that lists two Elixirs at a care stop is
  correct to leave them.  A dry caster mid-fight is the fight driver's
  decision (`tools/tests/lib/ot6.lua`, not this page's file).  The rule
  for that queue, so it is written down once: an Item turn on an
  Ether/X-Ether/Elixir is worth a turn when the actor's pool cannot pay
  even the unboosted verb the plan wants (`M.affordBoost` returning nil)
  *and* the fight is one the driver was handed a boss plan for; in a
  random it is never worth it (Fight is free and the fight ends anyway),
  and among the three the cheapest that refills the plan's price goes
  first (Ether +150, then X-Ether, then Elixir).  Not implemented here.

## 4. The band gains an MP column

| item | band | first counter on the route |
|---|---|---|
| Tincture | ~level / 4, rounded up | Narshe shop 3 (`gen_zozo1_submerge`); Figaro Castle's purse cannot carry one (squeeze 1) |
| Tent | 4 from Albrook (the factory's two save points and the world legs); 10 from Jidoor (`gen_narshe_mission`, unchanged) | Albrook shop 24 (`gen_vector_entry`) |
| Revivify | 3 | Jidoor 22 |

Why level / 4: a pool grows about 9 MP a level over the levels this band
covers (measured off the fixtures: 97 at L14, 160 at L20, 256 at L28), so
level / 4 Tinctures is 12.5 x level MP -- one whole pool at any level, the
caster who ran dry made whole once per stretch with a half pool left for
the next one.  That is the Tonic band's shape (level x 5 Tonics is 250 x
level HP, about one party's HP at L14), one currency over.  The cap is
the bag slot's 99 in name only: the WoB tops out at 7.

What it costs, per stop, against the purse the fixture holds:

| stop | level | band | gil before | the line |
|---|---|---|---|---|
| Narshe shop 3, `gen_zozo1_submerge` | 14 | 4 | 16,871 (`kefka_won`) | TINCTURE to 4 (6000) after the Tonics |
| Jidoor 22, `gen_zozo2_arrival` | 19 | 5 | 82,865 (`zozo_arrival`) | TINCTURE to 5, REVIVIFY to 3 |
| Albrook 24, `gen_vector_entry` | 20 | 5 | 98,495 (`vector_entry`) | TINCTURE to 5, TENT to 4, REVIVIFY to 3, then the inn (300) |
| Jidoor 22, `gen_narshe_mission` | 23 | 6 | 125,597 (`narshe_mission`) | TINCTURE to 6, REVIVIFY to 3 (TENT to 10 as today) |
| Albrook 24, `gen_voyage` | 26 | 7 | 155,511 (`crescent_landing`) | TINCTURE to 7, REVIVIFY to 3 |
| Thamasa 35, `gen_thamasa_arrive` / `gen_thamasa_fire` / `gen_fc_landing` | 26 / 27 / 28 | 7 | 154,737 / 167,386 / 177,513 | TINCTURE to 7, REVIVIFY to 3, TENT to 10; the 1-GP inn |

The Tincture line goes after the essentials and before the Tonic soak,
like the Potion line: a short purse shorts the soak, then the Tinctures,
never the revives.  `tools/audit_supplies.py` warns under the Tincture band
from Narshe's counter (the `figaro_submerged` row) to the WoR landing,
beside the Tonic and Potion warnings.
