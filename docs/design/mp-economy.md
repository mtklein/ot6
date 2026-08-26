# The MP economy

Scope: game-wide rules, WoB-sized numbers. Terminology: the pool keeps
its vanilla name MP, the name existing players already know; enemy break
counters are "shields"; SP is not used.

The economy exists to make Fight a real option. In vanilla FF6, for the
ability characters, the ability always beats Fight, so there is no
decision to make each turn. Octopath handles this with resources: a
character banks resources by not spending them, and a plain attack is
the action that banks. OT6's target: Fight must sometimes be the right
move, and Cyan and Sabin must still play as ability characters. Both
halves constrain the numbers — an economy tight enough to ration SwdTech
makes Cyan a worse Locke, and an economy loose enough that Fight is
never correct keeps vanilla's lack of a choice and adds bookkeeping.

## The ceiling: 99

The rule for the top of every ladder is that each character's own
ultimate costs 99 MP. It agrees with the baseline below: 99 against a
L70 pool of ~760 is 13%, inside the 8-20% range. It therefore caps the
table rather than recalibrating it, and it makes ladders comparable
across characters.

99 is also the display maximum. Every OT6 price drawer renders
exactly two digits:
`ListText` command `$02` (`btlgfx_main.asm:15045-15073`) divides by ten
once and emits a tens cell and a ones cell, and
`Ot6LoadoutDrawCost` (`field_menu.asm:3057`) has one tens loop. A cost of
100 renders as a punctuation glyph rather than as a number. 99 is
therefore the largest cost that can be shown, and no cost anywhere may
exceed it. `battle_costtable.lua` asserts that bound on every row of
the live table, not just the rows it pins by name.

Vanilla uses the same bound. Measured off `magic_prop_en.dat` +$05, the
dearest spell in the game is Quick at 99, then Merton at 85
and Ultima at 80. The number is not imported: 99 is the maximum FF6's own
spell table already stays under, so a 99 kit ultimate reads as the top of
the scale rather than as an outlier.

The single value above 99 anywhere in that table is Phoenix at 110,
an esper. It is untouched and needs no exemption: summons draw
their price through `ListText` command `$16`
(`btlgfx_main.asm:15000-15043`), the three-digit routine (hundreds, tens,
ones), which is wired into `SummonMagicListText` and fed from
`$2091` (`btlgfx_main.asm:11368`). Vanilla's summon window can render it,
and none of OT6's two-digit drawers sees it.

99 applies where it makes sense, not universally. Where a character has
an ultimate, that ultimate costs 99. Where the top verb is flat or free,
as with Slot, Rage and Dance, the character does not participate in the
rule.

**Who qualifies, from the ladders:**

| kit | top row | 99? | why |
|---|---|---|---|
| Blitz | **Bum Rush** `$64` | **yes** | divine, L70, the top row of the kit |
| SwdTech | **Cleave** `$5c` | **yes** | divine, the window's conditional top tier |
| Tools | **Overclock** | **no, not yet** | Edgar's divine, and it is not built. It has no tool item id and therefore no row in `Ot6AbilityCostTbl`; kits.md prices it as the sum of the two tools it fires (max 34). |
| Steal / Slot / Rage / Dance | — | **no** | flat verbs, no ladder |

Air Anchor is not the Tools capstone. kits.md states: "Air Anchor
stays a findable *item* mid-kit gag, not the capstone." Tools therefore
has no top row to price today.

Locke is the other case worth naming. Steal is flat for now, but his
kit (`kits.md`) already designs Master's Mark, which steals from all
enemies and reveals everything. It has the shape of a 99 ability: it
fires once and ends the probing phase. Master's Mark is Locke's 99, so
Steal is a tier in his ladder rather than its top.

Magic does not participate, and the measured prices say it should not.
Against `magic_prop_en.dat` +$05: Ultima
80, Merton 85, W Wind 75, Meteor 62; the dearest spell of any kind is
Quick at 99. Ultima at 80 sits below a 99 kit ultimate rather than
beside it, which is the right order, because Ultima is a spell any
character with the esper can learn while Bum Rush is one character's
once-per-kit divine. Nothing needs changing, and the vanilla-MP-costs
house rule stands with its one named exception (Osmose, below).

## Principles

- **FF6's MP pool is the resource.** Every character
  already has an MP stat, a growth curve, current/max cells in
  save RAM, and menu plumbing. OT6 adds no new resource and no
  new name; it widens who pays from that pool.
- **Three currencies.** HP measures danger, MP measures sustain, and BP
  pays for burst. The break interacts with all three: shielded resistance
  (DESIGN.md, with the HP multiplier retired to 1x) halves off-weakness
  damage and so makes probing necessary, and
  boosting spends the BP bank into the ×2 window.
- **The free floor.** Fight, Def., Item, and Row never cost
  MP, matching Octopath's floor. A character with an empty pool still
  has legal actions, and Item is the channel refill
  consumables arrive through.
- **Signatures are free to learn and still cost MP to use.** Pillar 1's
  "signature is free" (DESIGN.md) means free at join: no deed, no
  level gate, no JP. Signatures become the cheapest rows of
  their kits (1–4 MP) rather than costing nothing: verbs free in
  vanilla, Steal and Tools by name, stop being free under Octopath rules.
  Only the Fight row is free, and every other verb costs MP as its
  character's kit comes online. (Item is inventory-gated, not an MP
  verb.) The rule is about the row, not about the word "Fight": on the
  Veldt Leap occupies the Fight row (kits.md's row-sharing rule,
  `Ot6VeldtRow`), so on the Veldt the free floor is Leap, and Leap is
  free. Steal is priced, because it is a verb beside Fight rather than
  the Fight row itself.
- **BP buys tempo and MP buys power.** One Fire 3 instead of three Fires
  saves two turns, which is what the boost buys, and the magnitude is
  paid for at the tier's own price. Measured out of `magic_prop_en.dat`:
  the spread is 2.0× (Life → Life 2, 30 → 60) to 8.7× (Poison →
  Bio, 3 → 26), with Fire 4 → 20 → 51. Dearest folded tier is Life 2 at
  60, under the 99 ceiling. `tools/tests/battle_foldcost.lua`
  recomputes the whole table from the ROM and holds it to the ceiling, to
  monotonicity, and to a two-sided check that the fold still buys
  something without buying it too cheaply.

  As a percentage of pool those tiers run 8–11% at the level they are
  naturally learned, which is on the 8–20% vanilla baseline because they
  are vanilla prices, and 40–133% at
  the level folding reaches them. That gap is what the boost purchases:
  at L6 a folded Fire 3 costs more than Terra's whole pool, so it is
  not castable until L8 and empties her when it is. The exception is
  Haste2 at 12.0%, because Haste itself is not
  learned until Celes is L32 with a 316 pool.

  The list displays this correctly: the price, the grey-out and the
  A-button's refusal all follow the folded tier, because they and
  `GetMPCost` read one cell and OT6 moves that cell (`Ot6FoldPrices`).
  Folding still reaches tiers the caster never learned, which is what
  keeps every spell list at 8 entries, and it charges the tier's real
  price.

  The split applies unchanged to every costed verb, including
  boost-tiered Steal (kits.md): its
  BP buys the guarantee, and its MP price is unchanged by the
  boost, using the "flat small" row below
  like every other verb that is free in vanilla. Steal costs 4 MP.
  cmd $05 takes a flat-cost
  path in `Ot6AbilityCost`, a single verb with one price
  keyed on the command rather than on an
  ability-id table row, because Steal has no per-ability id in the
  disjoint ranges the id table keys on. It is charged, and refused when
  the pool is short, by the same universal machinery as
  Blitz/SwdTech/Tools. That number lives in the
  `Ot6StealCost` leaf rather than inline, in the same shape as
  `Ot6DanceCost`, so the charge and any future menu row read one
  authority. With `OT6_MP_COSTS` off it reverts to free, byte-for-byte.
- **One price scale.** Kit skills live in the same ability
  records as spells (research/data-formats.md), so they price
  on the vanilla spell baseline: Fire 4, Fire 2 20, Fire 3 51.

## The verb survey

Already costed, unchanged: **Magic**, **Lore**, and **summons**
keep their vanilla MP costs (house rule); summons additionally
stay once per battle (DESIGN.md).

There is one named exception to the vanilla-MP-costs house rule:
Osmose `$29` costs 8 MP rather than vanilla's 1. Under OT6 every verb
spends MP, and at 1 MP Osmose would switch the currency off:
Magitek Research Facility boss pools run 447–810
(`monster_prop.dat` +$0a) against party pools of 40–60, so one
cast recovers many times the caster's whole pool. 8 MP keeps
it net-positive by a wide margin, measured on the shipped ROM at 30 MP
against a 500 MP pool: 30 → 22 → 63, a +33 net refill for 8. It also
stops the spell being free, and it stays castable on a nearly
empty pool. The price applies globally, so ZoneSeek inherits it, which
is correct because it is the same spell. The byte lives in
`battle_main.asm`'s `MagicProp` splice with its argument beside
it, and `tools/tests/battle_magicite.lua` pins both the price and
the 7-MP boundary that only 8 can produce. No other magic
price is touched.

Strago's kit is Lores, so it
is already priced. His "free signature" Aqua Rake (kits.md)
is free at join, and costs MP like any lore. Divines cost
MP in addition to their gates (broken target, the 5-BP bank,
once per battle), so there are no free apex actions: the
gate limits frequency and MP prices the cast.

Vanilla-free player verbs, with their cost shapes:

| Verb | Shape | MP | Rationale |
|---|---|---|---|
| Steal (Locke #1) | flat small | **4** | 12.9% of the 31 MP pool Locke joins with, and parity with every other kit's signature row (Pummel, Dispatch and AutoCrossbow are all 4); see "Steal's price is real and invisible" below |
| New kit skills (Locke #2–7, Analyze, …) | scaled by tier | 3–20 | costed from the start via the kit tables, and never free in vanilla; Analyze stays cheap (2–3) so scouting stays frequent |
| Tools (Edgar) | scaled by tier | 3–20 | bought once with gil and reusable, so MP is the per-use cost: AutoCrossbow 3–4, Drill/Chain Saw 12–20, Debilitator 8–12, Overclock costs the sum of the two tools it fires |
| Blitz (Sabin) | scaled by tier | 4–99 | Pummel 4, mid-kit 10–17, then 28/50, then Bum Rush at the 99 maximum |
| SwdTech (Cyan) | BP tier + MP at Blitz parity | 4–99 | he pays both currencies (below), and Cleave costs 99 |
| Dance (Mog) | flat, paid at start | 4–10 | one payment starts a whole-battle state; vanilla's can't-stop-dancing lock is preserved, so the price is per battle rather than per step |
| Rage (Gau) | flat, paid at start | 8 | one payment starts a whole-battle possession and every possessed turn after it is free, the same rule Dance takes; `Ot6RageCost` tail-calls `Ot6DanceCost` so the two cannot drift |
| Leap (Gau) | free — exception | 0 | the free floor rather than an exemption: Leap shares Gau's FIGHT row on the Veldt (kits.md), so on the Veldt it is the Fight command |
| Sketch (Relm) | flat small | 2–4 | pay to roll; the Sketch bug stays (house rule) and does not refund |
| Control (Relm, kit not yet built) | flat moderate | 8–12 | vanilla's strongest free verb, giving full command of a monster |
| Slot (Setzer) | flat small | 1–3 | the reels are the main price; MP makes the number of spins finite |
| Runic (Celes) | free — exception | 0 | an income verb: vanilla Runic already credits the absorbed spell's cost to her pool, kept, on top of +1 BP (kits.md) |
| Throw (Shadow) | free — exception | 0 | the thrown item is consumed; a per-use price already exists |
| Coin Toss, Hired Help (Setzer) | free — exception | 0 | GP-priced verbs stay GP-priced; Octopath's merchant skills also spend money rather than MP |
| Mimic (Gogo) | free — exception | 0 | vanilla Mimic copies the action and not the price; the bonus-character jank is preserved |
| Guest verbs: Health (Banon), Shock (Leo), magitek beams, Possess (Ghost) | free — exception | 0 | guests have no kit tables; their stretches are authored tutorial content (the Whelk line is balanced on free beams, balance-metrics.md), and Possess already costs the ghost |
| Relic-morphed commands (Jump, GP Rain, X Magic, …) | inherit | — | assigned in the same records as everything else |

### Steal's price is real and invisible

The price is 4 MP. This document's baseline measures
an ability against the pool at the level it arrives, and Steal
arrives at Narshe with Locke at LV6 holding 31 MP (measured,
`probe_mppools.lua` off `worldmap_narshe`), where 4 MP is 12.9%,
between Fire's 10.0% and Cure's 12.5%.

Every signature dilutes as levels rise, in the same way Steal does:
Pummel is 4.3% of Sabin's LV14 pool and
Dispatch 4.3% of Cyan's. Holding the late-game fraction constant would
require per-level prices, which this baseline does not do.

4 also matches the cheapest row of all three ladder
kits, since Pummel, Dispatch and AutoCrossbow are each 4, which is what
"signatures become the cheapest rows of their kits" means in numbers.
Steal is the first tier of Locke's ladder rather than a
one-off, and his 99 is Master's Mark. `battle_costtable.lua` asserts
that parity, so moving one signature without the others fails the test.

The ruling on display: the price is not shown anywhere. The
evidence, all read rather than recalled:

- The four-row battle command window has no numeric field.
  `command_window_data_set` (`btlgfx_main.asm:10099`) writes two
  things per row, the command byte and a colour from `GetTextColor`,
  and its template `MenuText::_4` (`btlgfx_main.asm:45162`) is four
  fixed 8-byte records, `$ff $ff $04 $21 $0d $00 $ff $01`: two spaces, a
  font, a name command and its id, a space, a terminator. It contains no
  `$02` and no `$16`.
- `GetTextColor` (`btlgfx_main.asm:10704-10707`) is `and #$80` on the
  disabled flag. The single grey that window can show means "command
  unavailable" and not "insufficient MP".
- Every other costed verb has a submenu that handles this already:
  `Ot6BlitzRowDecorate`, `Ot6ToolRowDecorate`, `Ot6DanceRowDecorate`
  (`ot6_kits.asm:526`, `:614`, `:679`) each stamp a two-digit price and
  grey by affordability through `Ot6AbilityGrey`. Steal is the only
  costed verb with no list to put a number in.

Building a numeric field into that window would mean re-laying out three
templates (short mode, window mode, and `MenuText::_4`) plus a
command-keyed cost lookup, for one verb, and Locke's own submenu would
later make all of it dead code. That is why the display is not built.

Making Steal free is not an option either. Leap is free because it
occupies the Fight row on the Veldt and the free floor has to survive
the substitution. Steal is a verb beside Fight, so making it free would
contradict the rule that only the Fight row is free.

The price is therefore charged and not drawn, deliberately. The cost is
kept in a leaf, `Ot6StealCost`
(`ot6_boost.asm`), in the `Ot6DanceCost` shape, so when Locke gets a
submenu its row decorator will read the same byte the charge reads and
the two cannot disagree. The exposure is small at 4 MP: Locke can afford
7 steals from the pool he joins with, so a player rarely reaches the
refusal path.

### Cyan pays in both

SwdTech costs both currencies: a BP tier plus an MP price. There is no
0-BP tier, since `Ot6BushidoTech` (`ot6_kits.asm:74-79`) clamps a stray 0
up to 1, and the window is three tiers over Cyan's top three learned
techs (`ot6_kits.asm:65-70`). The BP tier replaces the
vanilla charge gauge's wait-to-charge timing while preserving agency:
the wait still exists, because later techs need a fuller bank and banking
to 3 is the only way to reach the top of the ladder, but Cyan acts while
it builds. The consequence is that Cyan is the one kit where banking BP
has purpose on its own. Greedy spending beats banking against trash,
measured, so every other kit needs a boss to justify banking, while
Cyan's later techs require the bank, so the
decision exists in every fight he is in.

Boost selects the tech rather than gating a menu choice, so
there is no surplus to scale: a spend always buys the best
tech it can reach. SwdTech is excluded from `Ot6BoostDmg`'s
multiplier for the same no-double-dip reason folded spells
are. Unusable spend, such as three points before Cyan has learned past
Dispatch, is consumed rather than refunded, which is the same deal a mage
takes on a third point on Fire. A menu that let him pick a
lower tech than his spend affords would bring the
surplus case back; it is not built, and it needs the menu bank.

SwdTech prices at parity with the Blitz row of the same
index, and ships at 4/10/13/16/18/28/50/99 (`Ot6AbilityCostTbl`,
`ot6_boost.asm:1377-1384`). The parity holds by level and not only by
index: `BlitzLevelTbl` is 1/6/10/15/23/30/42/70 and
`BushidoLevelTbl` 1/6/12/15/24/34/44/70
(`ff6/src/field/event.asm:1236-1240`), so row n of either kit
arrives at the same stage against nearly the same pool. Cyan
pays BP on top. If parity plus the 1-BP floor leaves
him short of resources, the adjustment to make is BP seed or regen, not
the floor and not this column.

One deviation from parity: Empowerer costs 18 rather than Mantra's
16, because the SwdTech column must stay monotonic with the
tech index. The boost window offers techs weakest→strongest
and the row is the boost level (kits.md), so a 2× row dearer
than the 3× row would read as a bug. Blitz is a free-choice
menu and needs no such rule, so Mantra stays a
cheap utility option priced under Fire Dance.

### The baseline

Kit skills price on the vanilla spell baseline: cost as a fraction of the
caster's real max MP at the level the ability is learned, pools computed
the way `InitMaxMP` computes them (`CharProp+$01` plus the
`LevelUpMP` running sum) and cross-checked against pools read
out of generated savestates (`tools/tests/probe_mppools.lua`):

Spells learned below Terra's earliest measured level are
priced at that level (L6, pool 40, read off `kolts_entry`),
the same clamp the kit tables below use, because a pool the game never
presents cannot be reached in play. MP costs are `magic_prop_en.dat` +$05.

| vanilla spell | MP | learned | pool | % of pool |
|---|---|---|---|---|
| Antdot | 3 | L6 | 40 | 7.5% |
| Warp | 20 | L26 | 240 | 8.3% |
| Fire | 4 | L3 → L6 | 40 | 10.0% |
| Fire 2 | 20 | L22 | 192 | 10.4% |
| Cure | 5 | L1 → L6 | 40 | 12.5% |
| Drain | 15 | L12 | 87 | 17.2% |
| Life | 30 | L18 | 148 | 20.3% |

A vanilla spell therefore costs roughly 8–20% of the pool it is
first cast from. The shipped columns are measured against that baseline.
Rows 1–2 are priced at L10, the earliest either character is in the party
at all (measured: `gau_joined` has Cyan and Sabin both at LV11). Every
figure is recomputed by `battle_costtable.lua` from the ROM's own tables
on each `make test`, not derived by hand.

| Blitz | learned | pool | MP | % of pool | uses |
|---|---|---|---|---|---|
| Pummel | L1 | 56 | **4** | 7.1% | 14 |
| AuraBolt | L6 | 56 | **10** | 17.9% | 5 |
| Suplex | L10 | 56 | **13** | 23.2% | 4 |
| Fire Dance | L15 | 104 | **17** | 16.3% | 6 |
| Mantra | L23 | 191 | **16** | 8.4% | 11 |
| Air Blade | L30 | 278 | **28** | 10.1% | 9 |
| Spiraler | L42 | 449 | **50** | 11.1% | 8 |
| Bum Rush | L70 | 760 | **99** | 13.0% | 7 |

| SwdTech | learned | pool | MP | % of pool | uses |
|---|---|---|---|---|---|
| Dispatch | L1 | 58 | **4** | 6.9% | 14 |
| Retort | L6 | 58 | **10** | 17.2% | 5 |
| Slash | L12 | 76 | **13** | 17.1% | 5 |
| Quadra Slam | L15 | 106 | **16** | 15.1% | 6 |
| Empowerer | L24 | 205 | **18** | 8.8% | 11 |
| Stunner | L34 | 334 | **28** | 8.4% | 11 |
| Quadra Slice | L44 | 483 | **50** | 10.4% | 9 |
| Cleave | L70 | 762 | **99** | 13.0% | 7 |

| flat verb | arrives | pool | MP | % of pool | uses |
|---|---|---|---|---|---|
| Steal (Locke) | L6, Narshe | 31 | **4** | 12.9% | 7 |
| Rage / Dance | — | — | **8** | — | — |

Percentage of pool climbs toward the 13.0% maximum along each ladder
(8.4 → 10.1 → 11.1 → 13.0 for Blitz) rather than falling away from it.

Two deliberate non-uniformities:

- **Mantra stays at 16, under Fire Dance's 17.** It is a utility option
  rather than a damage tier, and Blitz is a free-choice menu where all
  learned rows are visible at once, so a heal that costs more than the
  fire-all tier would read as a bug. At 8.4% of the L23 pool it is still
  on the baseline: the dip is in the ordering, not in the scale.
  Empowerer keeps its +2 over Mantra for SwdTech's monotonicity rule.
- **The signature rows stay at 4** (7.1% / 6.9%), just under the 8%
  vanilla floor, and Suplex stays at 23.2%, just over the 20% top. The
  first is the "cheapest row" floor and the second is the tightest row in
  the table. Both sit inside the 4–25% bracket `battle_costtable.lua`
  enforces.

Two things the measurement adds that the numbers alone do not show:

- **Tools are deliberately untouched.**
  Against Edgar's real pool at the stage each tool is acquired
  they run 7–21%: AutoCrossbow 11.1% at L7, Drill 18.4% and
  Chain Saw 20.7% at L13, which is on the baseline above. A general
  floor lift does not apply to them, because 1.5× on Chain Saw would be
  31%, above the top of the scale. Gil buys the tool once and MP is the
  per-use cost.
- **The test.** `tools/tests/battle_costtable.lua`
  recomputes every one of these fractions from the ROM's own
  tables on each `make test` and refuses a column that has
  fallen outside 4–25%.

## Early pools, from the character data

Base MP (ff6/src/field/char_prop.asm): Terra 16, Locke 7,
Edgar 6, Cyan 5, Sabin 3, Celes 15, Strago 13, Relm 18,
Setzer 9, Mog 16, Gau 10, Umaro 0. The shared gain table
(LevelUpMP, ff6/src/field/event.asm) adds 4–6 MP per early
level, so around L5 the pools sit near Terra 29–34, Locke
20–25, Edgar ~19, Cyan ~18, Sabin ~16. Sabin's is the smallest, so it
sets the bottom of every ladder. The curve rises toward 17 MP per
level through the 40s, so pools outgrow mid-kit costs as kits
fill in on their level schedules (kits.md). The tight period is
early WoB, which is where the demo is set.

Measured pools, read off the generated chain by
`tools/tests/probe_mppools.lua`, which boots each state and dumps
every `$1600` record. Max MP, in-party characters only (a
character who has not joined yet carries a placeholder record:
Cyan reads LV7/39 at `kolts_entry`, which is not a pool
anyone can spend):

| stretch (fixture) | Terra | Locke | Cyan | Edgar | Sabin | Celes | Gau |
|---|---|---|---|---|---|---|---|
| Narshe (`worldmap_narshe`) | 29 `L4` | 31 `L6` | — | — | — | — | — |
| Mt Kolts (`kolts_entry`) | 40 `L6` | 37 `L7` | — | 36 `L7` | — | — | — |
| Serpent Trench (`gau_joined`) | 69 `L10` | 44 `L8` | 67 `L11` | 59 `L10` | 65 `L11` | — | 72 `L11` |
| scenario hub (`scenario_hub`) | 69 `L10` | 44 `L8` | — | 59 `L10` | 56 `L10` | — | — |
| Zozo (`zozo_arrival`) | 78 `L11` | 69 `L11` | 76 `L12` | 87 `L13` | 84 `L13` | 77 `L11` | 81 `L12` |
| Opera (`opera_entry`) | 78 `L11` | 88 `L13` | 76 `L12` | 97 `L14` | 94 `L14` | 96 `L13` | 81 `L12` |
| Vector (`vector_entry`) | 78 `L11` | 98 `L14` | 67 `L11` | 107 `L15` | 104 `L15` | 106 `L14` | 72 `L11` |

Every one of these equals `CharProp+$01` plus the `LevelUpMP`
running sum to that level, as `InitMaxMP`
(`ff6/src/field/event.asm:1405`) builds it. The pool at any
level is therefore computable, and the owner's reported "LV14 Cyan, 96 MP"
is reproduced to the byte (5 + 91). That is what makes the baseline
table above checkable rather than anecdotal.

## Full HP/MP restore on level up

The rule is Octopath's, ported unchanged: when a character gains a
level, current HP and MP are set to the new maximums.

- The pacing conservation pins XP per step to vanilla, at 2x
  rewards and 0.5x encounter rate, so refill cadence tracks
  vanilla's leveling pace. The paired danger/reward settings
  now have a third effect: they set how often the party
  refills. Changing the pair changes sustain as well.
- Attrition works differently. Tents, inns, and save points stop
  being the only income; they matter most inside long
  same-level stretches and least right after a level. HP
  refills too, which reduces dungeon attrition.

MP-drain verbs stay, on Octopath's pattern, where they are balanced by
dealing little or no damage themselves and appearing on only a few
characters. Osmose (Shiva, at 8 MP, above) and Rasp (Ramuh) sit in the
esper pool (magicite.md), and reaching one is a deliberate perk that
lets a character manage their own resources. Enemies already have MP
and spend it in vanilla, and the MP kill stays (bosses-wob.md); Rasp and
Osmose gain value as attack and income against that pool.

The free floor holds: Tools are not consumables — gil buys them once
and they are reusable, so MP is their per-use price — and
Attack/Defend/Item stay free because a character with no legal action
is a soft lock. The pool is MP as in vanilla, and break counters are
shields; SP is retired.

## How costs are applied

Vanilla's `GetMPCost` (battle_main.asm) prices only magic/lore/summon/x-magic.
Every other command, including Blitz, SwdTech, Tools and the free
floor, falls through it returning 0, so the universal charge at
`CalcAttackEffect` (the `$3a4c` subtract, and its
insufficient-MP fizzle) never fires for them. `Ot6AbilityCost`
(`ff6/src/battle/ot6_boost.asm:878`) is the single hook, right after that
`GetMPCost`: for the costed verbs it swaps the 0 for the
kit price. Both the charge and the insufficient-MP refusal are
universal, acting on whatever `$3620`→`$3a4c` holds. The cost
data is not the record's +$05 byte, because GetMPCost reads the
character spell-list copy for magic and ignores it for the rest; it is a
parallel bank-$F0 table `Ot6AbilityCostTbl`, keyed by the id
already in `$3a7b` (attack id $5d–$64 Blitz, $55–$5c SwdTech;
tool item id $a3–$aa Tools), in the same shape as the class and
element tables. Numbers are kits.md's columns.

The whole mechanic gates on the build-time flag
`OT6_MP_COSTS`, which defaults ON, so the shipped ROM
charges MP. An explicit
`-D OT6_MP_COSTS=0` reassembles the pre-feature
vanilla-OT6 baseline, with none of the machinery present, kept as the
differ-checked regression control (`make -C ff6 ff6-en-nomp`
→ `ff6-en-nomp.sfc`). The A/B is checked both ways by
`tools/tests/battle_mpcost.lua` (self-detecting: charge+refusal
on the shipped ON ROM, free+absent on the `nomp` baseline). Costs and
the level-up refill ship together, since costs alone would be
attrition without income.
