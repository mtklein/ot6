# The MP economy

Scope: game-wide rules, WoB-sized numbers. Nothing here is
locked, and every number is a placeholder for playtest — said
once here instead of per row. Terminology:
the pool keeps its vanilla name MP — the name existing players
already know — enemy break counters are "shields", and SP is
not used.

## The target, stated by the owner

The economy exists to buy back a choice vanilla never offered.

> *"In that game there really wasn't ever any reason for Cyan or Sabin to
> just attack instead of using one of their abilities."*

That is the honest diagnosis of FF6: for the ability characters, the
ability strictly dominates Fight, so the "choice" each turn is not one.
Octopath's answer is resources — you bank by *not* spending, and a plain
attack is what banking looks like. So the target for every number in this
document is:

**Fight must sometimes be the right move, without Cyan and Sabin ceasing
to feel like ability characters.**

Both halves bind. An economy so tight that SwdTech is rationed makes Cyan
a worse Locke; one so loose that Fight is never correct leaves vanilla's
non-choice intact with extra bookkeeping.

**And the owner's standing expectation: this will take a while.** Getting
a number that is Octopath-right and FF6-right at once is a playtest loop,
not a derivation — so a pass that improves the shape and gets played is
worth more than one that waits to be correct. Successive rescales are
expected and are not churn.

## The ceiling: 99

The owner's shape for the top of every ladder: **each character's own
ultimate costs 99 MP.** It agrees with the ruler below — 99 against a
L70 pool of ~760 is 13%, inside the 8-20% band — so it anchors the table
rather than recalibrating it, and it makes ladders comparable across
characters.

It is also the **hard display ceiling**. Every OT6 price drawer renders
exactly two digits:
`ListText` command `$02` (`btlgfx_main.asm:15045-15073`) divides by ten
exactly *once* and emits a tens cell and a ones cell, and
`Ot6LoadoutDrawCost` (`field_menu.asm:3057`) has one tens loop. A cost of
100 does not print as a big number; it prints as punctuation. So 99 is
the largest cost that can be shown at all, and no cost anywhere may
exceed it. `battle_costtable.lua` asserts that bound on every row of
the live table, not just the rows it pins by name.

**Vanilla already agrees.** Measured off `magic_prop_en.dat` +$05: the
dearest *spell* in the game is **Quick at exactly 99**, then Merton 85
and Ultima 80. So the anchor is not an imported number — it is the
ceiling FF6's own spell table already sits under, which is why a 99 kit
ultimate reads as "the top" instead of as an outlier.

The single value above 99 anywhere in that table is **Phoenix at 110**,
an esper. It is untouched and needs no exemption argument: summons draw
their price through `ListText` command `$16`
(`btlgfx_main.asm:15000-15043`), which is the **three**-digit routine —
hundreds, tens, ones — wired into `SummonMagicListText` and fed from
`$2091` (`btlgfx_main.asm:11368`). Vanilla's summon window has always
been able to render it; none of OT6's two-digit drawers ever sees it.

**And it is the right number for reasons that are not arithmetic.** The
owner: *"seeing things like 99, 999, and 9999 in Final Fantasy games
feels right. Very classic feel."* Those caps are texture, not just
limits — a player who has met 9999 damage and a 99-item stack reads 99 MP
as *the top* without being told. This is the same instinct as keeping the
FF3-US names (CONTRIBUTING) and the Vargas tutorial (bosses-wob.md):
fidelity to what the original felt like, even where a cleaner number
exists.

**General rule that falls out:** where OT6 needs a cap, a ceiling or a
round maximum, prefer the series' own — 99, 999, 9999 — over an
arbitrary one. If a design wants 100 or 50, it should say why the classic
number is wrong rather than defaulting past it.

**Scope (owner): 99 where it makes sense, not universal.**
Where a character has a genuine ultimate, that ultimate costs 99. Where
the top verb is flat or free — Slot, Rage, Dance — the character simply
does not participate, and that is a stated non-answer rather than a gap
to fill with an invented capstone.

**Who qualifies, from the ladders:**

| kit | top row | 99? | why |
|---|---|---|---|
| Blitz | **Bum Rush** `$64` | **yes** | divine, L70, the ladder's stated top |
| SwdTech | **Cleave** `$5c` | **yes** | divine, the window's conditional top rung |
| Tools | **Overclock** | **no — not yet** | Edgar's divine, and it is *not built*. It has no tool item id and therefore no row in `Ot6AbilityCostTbl`; kits.md prices it as the **sum** of the two tools it fires (max 34). |
| Steal / Slot / Rage / Dance | — | **no** | flat verbs, no ladder |

**Air Anchor is not the Tools capstone.** kits.md is explicit: "Air Anchor
stays a findable *item* mid-kit gag, not the capstone." So Tools has no
top row to anchor today, and when Overclock is built the Σ rule and the 99
anchor collide — **that decision belongs to the change that builds
Overclock**, because either answer prices an ability that currently has no
code.

Locke is the other case worth naming: Steal is flat *for now*, but his
kit (`kits.md`) already designs **Master's Mark** — steal from all
enemies and reveal everything — which is exactly a 99's shape: it fires
once and ends the probing phase outright. That is his anchor, which also
means Steal is a rung, not the ceiling.

**Does Magic participate? No — and measurement says it should not.**
Against `magic_prop_en.dat` +$05: Ultima
80, Merton 85, W Wind 75, Meteor 62; the dearest spell of any kind is
Quick at 99. Ultima at 80 sits *below* a 99 kit ultimate rather than
oddly beside it, which is the right order — Ultima is a spell any
character with the esper can learn, Bum Rush is one character's once-per-
kit divine. Nothing needs changing, and the vanilla-MP-costs house rule
stands with its one named exception (Osmose, below).

## Unresolved numbers are not blockers

Where two documents disagree about a *value* — Overclock priced as the sum
of its tools (`kits.md`) versus the 99 anchor above — that is not a
contradiction to resolve on paper. The owner's ruling: *"doesn't matter
what we start with, playtesting will help make it clear."*

So: pick the defensible default, ship it where it can be played, note the
alternative in a comment, and let the playthrough decide. Blocking a build
on a number nobody can evaluate without playing it is the expensive
mistake, not shipping the wrong number once.

## Principles

- **FF6's MP pool does Octopath's job.** Every character
  already has an MP stat, a growth curve, current/max cells in
  save RAM, and menu plumbing. OT6 adds no new resource and no
  new name; it widens who pays from that pool.
- **Three currencies.** HP is danger, MP is sustain, BP is
  spikes. The break interacts with all three: shielded resistance
  (DESIGN.md — the HP multiplier retired to 1x) makes probing
  necessary by halving off-weakness damage, the
  restore-on-break passive (below) makes breaks MP income, and
  boosting spends the BP bank into the ×2 window.
- **The free floor.** Fight, Def., Item, and Row never cost
  MP — Octopath's own floor. An empty pool leaves a character
  diminished, never stranded, and Item is the channel refill
  consumables arrive through.
- **Free-to-learn is not free-to-use.** Pillar 1's "signature
  is free" (DESIGN.md) reads as free at join — no deed, no
  level gate, no JP. Signatures become the cheapest rows of
  their kits (1–4 MP), not costless: the driver's directive is
  that verbs free in vanilla — Steal and Tools by name — stop
  being free under Octopath rules. **The absolute (owner): only the
  Fight ROW is free — every other verb costs MP as its character's kit
  comes online. (Item is inventory-gated, not an MP verb.)** The rule is
  about the row, not about the word "Fight": on the Veldt Leap occupies
  the Fight row (kits.md's row-sharing rule, `Ot6VeldtRow`), so on the
  Veldt the free floor is Leap, and Leap is free. Steal is priced — it
  is a verb *beside* Fight, not the Fight row.
- **BP buys tempo. MP buys power.** One Fire 3 instead of three Fires
  saves two turns — that is what the boost buys — and the magnitude is
  paid for at the tier's own price. Measured out of `magic_prop_en.dat`:
  the spread is **2.0×** (Life → Life 2, 30 → 60) to **8.7×** (Poison →
  Bio, 3 → 26), with Fire 4 → 20 → 51. Dearest folded tier is Life 2 at
  60, well under the 99 ceiling. `tools/tests/battle_foldcost.lua`
  recomputes the whole table from the ROM and holds it to the ceiling, to
  monotonicity, and to a two-sided check that the fold still buys
  something without buying it too cheaply.

  As %-of-pool those tiers run **8–11% at the level they are
  naturally learned** — dead on the 8–20% vanilla ruler, which is
  unsurprising since they *are* vanilla prices — but **40–133% at
  the level folding reaches them**. That gap is the purchase: at L6
  a folded Fire 3 costs more than Terra's entire bar, so it is
  simply not castable until L8 and empties her when it is. The one
  soft spot is **Haste2 at 12.0%**, because Haste itself is not
  learned until Celes is L32 with a 316 pool.

  The list does not lie about it: the price, the grey-out and the
  A-button's refusal all follow the folded tier, because they and
  `GetMPCost` read one cell and OT6 moves that cell (`Ot6FoldPrices`).
  Folding still reaches tiers the caster never learned — that is the
  trick that keeps every spell list at 8 — but it is a purchase at the
  tier's real price instead of a freebie.

  The split ports unchanged to every costed verb, including
  **boost-tiered Steal** (kits.md): its
  BP buys the guarantee, and its MP question is unchanged by the
  boost, riding the "flat small" row below
  exactly like every other free-in-vanilla verb. **Steal costs 4 MP**:
  cmd $05 takes a flat-cost
  path in `Ot6AbilityCost` — a single verb with one price,
  keyed on the command rather than an
  ability-id table row (Steal has no per-ability id in the disjoint
  ranges the id table keys on) — and is charged, and refused when the
  pool is short, by the same universal machinery as
  Blitz/SwdTech/Tools. That number lives in the
  `Ot6StealCost` leaf rather than inline, the same shape
  `Ot6DanceCost` has, so the charge and any future menu row read one
  authority. With `OT6_MP_COSTS` off it reverts to free, byte-for-byte.
- **One price scale.** Kit skills live in the same ability
  records as spells (research/data-formats.md), so they price
  on the vanilla spell ruler: Fire 4, Fire 2 20, Fire 3 51.

## The verb survey

Already costed, unchanged: **Magic**, **Lore**, and **summons**
keep their vanilla MP costs (house rule); summons additionally
stay once per battle (DESIGN.md).

**One named exception to the vanilla-MP-costs house rule:
Osmose `$29` costs 8 MP, not vanilla's 1.** Under OT6 every verb
spends MP, and a 1-MP Osmose is not a spell but an off switch for
the currency: Magitek Research Facility boss pools run 447–810
(`monster_prop.dat` +$0a) against party pools of 40–60, and one
cast computes for many times the caster's whole bar. 8 MP keeps
it strongly net-positive — measured on the shipped ROM at 30 MP
against a 500 MP pool: 30 → 22 → 63, a +33 net refill for 8 —
while stopping it being free, and it stays castable on a nearly
empty pool. It applies globally, so ZoneSeek inherits it,
correctly: it is the same spell. The byte lives in
`battle_main.asm`'s `MagicProp` splice with its argument beside
it; `tools/tests/battle_magicite.lua` pins both the price and
the 7-MP boundary that only 8 can produce. **No other magic
price is touched.**

Strago's kit is Lores, so it
is already priced — his "free signature" Aqua Rake (kits.md)
is free at join, and costs MP like any lore. **Divines** cost
MP in addition to their gates — broken target, the 5-BP bank,
once per battle: no free apex actions; the
gate limits frequency, MP prices the cast.

Vanilla-free player verbs, with proposed cost shapes:

| Verb | Shape | MP | Rationale |
|---|---|---|---|
| Steal (Locke #1) | flat small | **4** | 12.9% of the 31 MP pool Locke actually joins with, and exact parity with every other kit's signature row (Pummel, Dispatch, AutoCrossbow are all 4) — see "Steal's price is real and invisible" below |
| New kit skills (Locke #2–7, Analyze, …) | scaled by tier | 3–20 | born costed via M4 kit tables — never free in vanilla; Analyze stays cheap (2–3) because scouting fuels the loop |
| Tools (Edgar) | scaled by tier | 3–20 | reusable capital bought with gil; MP is the operating cost — AutoCrossbow 3–4, Drill/Chain Saw 12–20, Debilitator 8–12, Overclock costs the sum of the two tools it fires |
| Blitz (Sabin) | scaled by tier | 4–99 | Pummel 4, mid-kit 10–17, then 28/50 into **Bum Rush 99, the anchor** |
| SwdTech (Cyan) | BP tier + MP at Blitz parity | 4–99 | he pays both currencies (below), and **Cleave anchors at 99** |
| Dance (Mog) | flat, paid at start | 4–10 | one payment starts a whole-battle state — vanilla's can't-stop-dancing lock is preserved, so the price is per battle, not per step |
| Rage (Gau) | flat, paid at start | 8 | one payment starts a whole-battle possession, every possessed turn after it free — the same rule Dance takes, and `Ot6RageCost` tail-calls `Ot6DanceCost` so the two can never drift |
| Leap (Gau) | free — exception | 0 | **the free floor, not an exemption**: Leap shares Gau's FIGHT row on the Veldt (kits.md), so on the Veldt it *is* the Fight command |
| Sketch (Relm) | flat small | 2–4 | pay to roll; the Sketch bug stays (house rule) and does not refund |
| Control (Relm, kit TBD) | flat moderate | 8–12 | vanilla's strongest free verb — full command of a monster; priced when her kit lands |
| Slot (Setzer) | flat small | 1–3 | the reels stay the real price; MP only makes spins finite |
| Runic (Celes) | free — exception | 0 | the income verb: vanilla Runic already credits the absorbed spell's cost to her pool — kept, on top of +1 BP (kits.md) |
| Throw (Shadow) | free — exception | 0 | the thrown item is consumed; a per-use price already exists |
| Coin Toss, Hired Help (Setzer) | free — exception | 0 | GP-priced verbs stay GP-priced — Octopath's merchant skills spend money, not MP; same precedent |
| Mimic (Gogo) | free — exception | 0 | vanilla Mimic copies the action, never the price; bonus-character jank preserved |
| Guest verbs: Health (Banon), Shock (Leo), magitek beams, Possess (Ghost) | free — exception | 0 | guests have no kit tables; their stretches are authored tutorial texture (the Whelk line is balanced on free beams — balance-metrics.md), and Possess already costs the ghost |
| Relic-morphed commands (Jump, GP Rain, X Magic, …) | inherit | — | assigned at M4 data entry in the same records as everything else |

### Steal's price is real and invisible

**The price: 4 MP.** This document's ruler measures
an ability against the pool at the level it **arrives**, and Steal
arrives at Narshe with Locke at **LV6 holding 31 MP** (measured,
`probe_mppools.lua` off `worldmap_narshe`), where 4 MP is **12.9%**,
between Fire's 10.0% and Cure's 12.5%.

Worth stating plainly because it will come up again: **every signature
dilutes the way Steal does.** Pummel is 4.3% of Sabin's LV14 pool and
Dispatch 4.3% of Cyan's. Chasing the late-game fraction would mean
per-level prices, which this ruler explicitly does not do.

4 is also **exact parity with the cheapest row of all three ladder
kits** — Pummel, Dispatch and AutoCrossbow are each 4 — which is what
"signatures become the cheapest rows of their kits" means in numbers.
Steal is rung one of Locke's ladder, not a
one-off, and his 99 is Master's Mark. `battle_costtable.lua` asserts
that parity, so moving one signature without the others is a red test.

**The display half: it stays invisible, and that is the ruling.** The
evidence, all read rather than recalled:

- The four-row battle command window has **no numeric field at all**.
  `command_window_data_set` (`btlgfx_main.asm:10099`) writes exactly two
  things per row — the command byte, and a colour from `GetTextColor` —
  and its template `MenuText::_4` (`btlgfx_main.asm:45162`) is four
  fixed 8-byte records, `$ff $ff $04 $21 $0d $00 $ff $01`: two spaces, a
  font, a name command and its id, a space, a terminator. No `$02` and
  no `$16` anywhere in it.
- `GetTextColor` (`btlgfx_main.asm:10704-10707`) is `and #$80` on the
  **disabled** flag. The one grey that window has means "command
  unavailable", never "you cannot afford it".
- Every *other* costed verb has a submenu that solves this for free —
  `Ot6BlitzRowDecorate`, `Ot6ToolRowDecorate`, `Ot6DanceRowDecorate`
  (`ot6_kits.asm:526`, `:614`, `:679`) each stamp a two-digit price and
  grey by affordability through `Ot6AbilityGrey`. **Steal is the only
  costed verb with no list to put a number in.**

Building a numeric field into that window would mean re-laying out three
templates (short mode, window mode, and `MenuText::_4`) plus a
command-keyed cost lookup, for **one verb**, when Locke's own submenu
makes all of it dead code. That is the argument, and
it is why the answer is not "build the surface".

Nor is it Leap's answer. Leap is free, but that ruling rests on a second
reason Steal does not have — Leap occupies the *Fight row* on the Veldt,
and the free floor has to survive the substitution. Steal is a verb
beside Fight. Making it free would contradict the owner's absolute (only
the Fight row is free).

So: **the price is charged and not drawn, deliberately.** The
mitigation is that it is a *leaf* — `Ot6StealCost`
(`ot6_boost.asm`), the `Ot6DanceCost` shape — so the day Locke gets a
submenu its row decorator reads the same byte the charge does and the
two cannot disagree. And the exposure is small at 4 MP: Locke affords 7
steals from the pool he joins with, so the refusal path is somewhere a
player has to work to reach.

### Cyan pays in both

SwdTech costs both currencies: a BP rung (there is no 0-BP rung —
`Ot6BushidoTech`, `ot6_kits.asm:74-79`, clamps a stray 0 up to 1, and the
window is three rungs over Cyan's top three *learned* techs,
`ot6_kits.asm:65-70`) plus an MP price on top. The ladder replaces the
vanilla charge gauge's wait-to-charge rhythm while preserving agency:
the wait still exists — later techs need a fuller bank, and banking to 3
is the only way to reach the top band — but Cyan acts while it builds.
The design consequence: Cyan is the one kit where banking BP has
intrinsic purpose. Greedy spending beats banking against trash, measured,
so for every other kit banking
needs a boss to justify it; Cyan's later techs require the bank, so the
decision exists in every fight he is in.

Boost *selects* the tech rather than gating a menu choice, so
there is no surplus to scale: a spend always buys the best
tech it can reach. SwdTech is excluded from `Ot6BoostDmg`'s
multiplier for the same no-double-dip reason folded spells
are. Unusable spend (three points before Cyan has learned past
Dispatch) is consumed, not refunded — the deal a mage already
takes on a third point on Fire. A menu that lets him pick a
*lower* tech than his spend affords is what would revive the
surplus case; it is not built, and it needs the menu bank.

SwdTech prices at **parity with the Blitz row of the same
index**, and ships at 4/10/13/16/18/28/50/99 (`Ot6AbilityCostTbl`,
`ot6_boost.asm:1377-1384`). That is a *level* claim, not an index
coincidence: `BlitzLevelTbl` is 1/6/10/15/23/30/42/70 and
`BushidoLevelTbl` 1/6/12/15/24/34/44/70
(`ff6/src/field/event.asm:1236-1240`), so row *n* of either kit
arrives in the same band against nearly the same pool. Cyan
pays BP on top; if parity plus the 1-BP floor leaves
him starved, the lever is **BP seed/regen, not the floor, and not this
column.**

One deviation from parity: **Empowerer 18 rather than Mantra's
16**, because the SwdTech column must stay monotonic with the
tech index — the boost window offers techs weakest→strongest
and *the row is the boost level* (kits.md), so a 2× row dearer
than the 3× row would read as a bug. Blitz is a free-choice
menu and needs no such rule, which is why Mantra stays a
cheap utility off-ramp under Fire Dance.

### The ruler

Kit skills price on the vanilla spell ruler: cost as a fraction of the
caster's real max MP **at the level the ability is learned**, pools computed
the way `InitMaxMP` computes them (`CharProp+$01` plus the
`LevelUpMP` running sum) and cross-checked against pools read
out of minted saves (`tools/tests/probe_mppools.lua`):

Spells learned below Terra's earliest *measured* level are
priced at that level (L6, pool 40 — read off `kolts_doorstep`),
the same clamp the kit tables below use, because pricing a spell
against a pool the game never presents is arithmetic about an
unreachable state. MP costs are `magic_prop_en.dat` +$05.

| vanilla spell | MP | learned | pool | % of pool |
|---|---|---|---|---|
| Antdot | 3 | L6 | 40 | 7.5% |
| Warp | 20 | L26 | 240 | 8.3% |
| Fire | 4 | L3 → L6 | 40 | 10.0% |
| Fire 2 | 20 | L22 | 192 | 10.4% |
| Cure | 5 | L1 → L6 | 40 | 12.5% |
| Drain | 15 | L12 | 87 | 17.2% |
| Life | 30 | L18 | 148 | 20.3% |

**So a vanilla spell costs roughly 8–20% of the pool it is
first cast from.** Against that ruler, the shipped columns. Rows 1–2 are
priced at L10, the earliest either character is in the party at
all (measured: `gau_joined` has Cyan and Sabin both at LV11). Every
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

%-of-pool climbs *into* the 13.0% anchor along each ladder (8.4 → 10.1 →
11.1 → 13.0 for Blitz) rather than falling away from it.

Two deliberate non-uniformities:

- **Mantra stays at 16, under Fire Dance's 17.** It is a utility
  off-ramp, not a damage rung, and Blitz is a free-choice menu where all
  learned rows are visible at once — a heal that costs more than the
  fire-all rung reads as a bug. At 8.4% of the L23 pool it is still on
  the ruler; the dip is in the *shape*, not off the scale. Empowerer
  keeps its +2 over Mantra for SwdTech's monotonicity rule.
- **The signature rows stay at 4** (7.1% / 6.9%), just under the 8%
  vanilla floor, and **Suplex stays at 23.2%**, just over the 20% top —
  the "cheapest row" floor and the thinnest row in the table. Both sit
  inside the 4–25% bracket `battle_costtable.lua` enforces.

Two things the measurement adds that the numbers alone do not show:

- **Tools are deliberately untouched.**
  Against Edgar's real pool at the band each tool is acquired
  they run 7–21% — AutoCrossbow 11.1% at L7, Drill 18.4% and
  Chain Saw 20.7% at L13 — i.e. dead on the ruler above. A general
  floor lift does not apply to them: 1.5× on Chain Saw would be 31%,
  off the top of the scale. Gil buys the tool once and MP is the
  per-use cost.
- **The gate.** `tools/tests/battle_costtable.lua`
  recomputes every one of these fractions from the ROM's own
  tables on each `make test` and refuses a column that has
  fallen outside 4–25%.

Per the preamble, every number here is still a playtest
placeholder and successive rescales are expected, not churn.

## Early pools, from the character data

Base MP (ff6/src/field/char_prop.asm): Terra 16, Locke 7,
Edgar 6, Cyan 5, Sabin 3, Celes 15, Strago 13, Relm 18,
Setzer 9, Mog 16, Gau 10, Umaro 0. The shared gain table
(LevelUpMP, ff6/src/field/event.asm) adds 4–6 MP per early
level, so around L5 the pools sit near Terra 29–34, Locke
20–25, Edgar ~19, Cyan ~18, Sabin ~16 — Sabin's floor sizes
the bottom of every ladder. The curve ramps toward 17 MP per
level through the 40s, so pools outgrow mid-kit costs as kits
fill in on their level schedules (kits.md); the squeeze is
early WoB, which is where the demo lives.

Measured pools, read off the minted chain by
`tools/tests/probe_mppools.lua`, which boots each state and dumps
every `$1600` record. Max MP, in-party characters only (a
character who has not joined yet carries a placeholder record —
Cyan reads LV7/39 at `kolts_doorstep`, which is *not* a pool
anyone can spend):

| band (fixture) | Terra | Locke | Cyan | Edgar | Sabin | Celes | Gau |
|---|---|---|---|---|---|---|---|
| Narshe (`worldmap_narshe`) | 29 `L4` | 31 `L6` | — | — | — | — | — |
| Mt Kolts (`kolts_doorstep`) | 40 `L6` | 37 `L7` | — | 36 `L7` | — | — | — |
| Serpent Trench (`gau_joined`) | 69 `L10` | 44 `L8` | 67 `L11` | 59 `L10` | 65 `L11` | — | 72 `L11` |
| scenario hub (`scenario_hub`) | 69 `L10` | 44 `L8` | — | 59 `L10` | 56 `L10` | — | — |
| Zozo (`zozo_arrival`) | 78 `L11` | 69 `L11` | 76 `L12` | 87 `L13` | 84 `L13` | 77 `L11` | 81 `L12` |
| Opera (`opera_doorstep`) | 78 `L11` | 88 `L13` | 76 `L12` | 97 `L14` | 94 `L14` | 96 `L13` | 81 `L12` |
| Vector (`vector_doorstep`) | 78 `L11` | 98 `L14` | 67 `L11` | 107 `L15` | 104 `L15` | 106 `L14` | 72 `L11` |

Every one of these equals `CharProp+$01` plus the `LevelUpMP`
running sum to that level, exactly as `InitMaxMP`
(`ff6/src/field/event.asm:1405`) builds it — so the pool at *any*
level is computable, and the owner's reported "LV14 Cyan, 96 MP"
is reproduced to the byte (5 + 91). That is what makes the ruler
table above checkable rather than anecdotal.

## Full HP/MP restore on level up

The rule, Octopath's, ported whole: when a character gains a
level, current HP and MP are set to the new maximums.

- The pacing conservation pins XP per step to vanilla — 2x
  rewards at 0.5x encounter rate — so refill cadence tracks
  vanilla's leveling rhythm. The paired danger/reward knobs
  now carry a third duty: they set how often the party
  refills. Changing the pair moves sustain too.
- Attrition changes meaning. Tents, inns, and save points stop
  being the only income; they matter most inside long
  same-level stretches and least right after a level. HP
  refills too, which softens dungeon attrition — the danger
  numbers were measured without a level-up in the window, so
  the M6 pass should watch it.
- Flagged for playtest: whether free refills make tents and
  Ethers dead stock early, and whether long boss-less
  stretches drain pools faster than the next level arrives.

## MP-management passives

The esper passive pool (magicite.md) is where MP relief lives;
slot rules and learning stay as written there — up to 4 slots,
learned by battles carried, stat passives competing for the
same slots. The anchor pair follows Octopath's support-skill
shapes; names here are descriptive placeholders:

- **MP on victory** — winning a battle restores ~15–25% of max
  MP. Octopath's victory-restore shape; keeps trash chains
  self-sustaining without inn trips.
- **MP on break** — the character who lands a break restores a
  few MP. Octopath's restore-on-break shape; probing spends MP
  and breaking rebates it, tying sustain to the loop's payoff.

Further candidates, one line each:

- **Cost down** — active skills cost −25%, floor 1.
- **Max MP up** — a +max-MP magnitude in the stat-passive
  channel magicite.md already defines.
- **Broken-field regen** — +1–2 MP per turn while any enemy is
  broken; spend the window harder.
- **Chip rebate** — a weakness chip restores 1 MP; Quadra Slam's ×4
  makes this strong, so it likely needs a per-action cap. AutoCrossbow
  wants one too, but for breadth against a wave rather than rate against
  a boss: it is whole-side, one hit per body, not multi-hit — see
  `design/multi-hit.md`.
- kits.md's *Afterglow* (first cast each battle free) is the
  same family on the character-passive side.

The WoB roster's passive column (magicite.md) is already full;
these either displace listed candidates or ride WoR espers —
driver's call at M5 data entry.

Adjacent income, active rather than passive: MP-drain verbs
stay, on Octopath's pattern — balanced
when they deal little or no damage themselves and appear on
only a few characters. Osmose (Shiva, at 8 MP — above) and Rasp (Ramuh)
sit in the esper pool (magicite.md), and reaching one is a deliberate
perk: this character can manage their own resources. The M6
pass still watches Osmose-cycling next to Facet + Rune Eater.

## Open questions for the driver

1. **Cost display.** Costed verbs need menus that show costs.
   The magic menu already renders MP columns; Tools, Blitz,
   Dance, stable, and Slot menus do not. The menu list
   machinery exists (class icons and fold previews already
   ride it); scope this ca65 work
   this with M4's curated-kit menus. Noted for later polish,
   M4/M5 era: the pool's on-screen label can read "SP" for a
   character who does not yet know any magic, unifying to "MP"
   once the first spell lands (magicite or otherwise) — one
   pool, one mechanic, only the label differing, narrating the
   character's growth into magic. Caveat: item and spell
   descriptions say "MP" universally, so the mismatch for
   SP-labeled characters should be eyeballed at implementation.
2. **Enemy-side MP.** Enemies already have MP and spend it in
   vanilla, and the MP kill stays (bosses-wob.md). Proposal:
   change nothing — no shield/MP interaction, no enemy boost.
   Rasp and Osmose quietly gain value as attack and income
   against that pool; watch, don't redesign.
3. **Does the free floor hold?** Yes. Tools are not
   consumables — gil once, reusable forever, so MP is their
   per-use price. Attack/Defend/Item stay free because a
   character with no legal action is a soft lock, and because
   Octopath's floor is the model. Restated as a question only
   so the driver can veto.
4. **Refill items.** Tinctures and Ethers are vanilla-scarce.
   With costed verbs they become a real economy knob — stock
   lists and prices join the M6 tuning surface.
5. **Terminology.** The pool is MP as in vanilla, break counters are
   shields, SP is retired. Older docs
   still write SP for shield points — DESIGN.md's break
   section — left for a later touch-up.

## Where it lands

- **M4 — costs and refill.** Vanilla's `GetMPCost`
  (battle_main.asm) prices only magic/lore/summon/x-magic;
  every other command — Blitz, SwdTech, Tools, the free floor —
  falls through it returning 0, so the universal charge at
  `CalcAttackEffect` (the `$3a4c` subtract, and its
  insufficient-MP fizzle) never fires for them. `Ot6AbilityCost`
  (`ff6/src/battle/ot6_boost.asm:878`) is the single hook, right after that
  `GetMPCost`: for the costed verbs it swaps the 0 for the
  kit price. Charge AND the insufficient-MP **refusal** are
  universal — they act on whatever `$3620`→`$3a4c` holds. The cost
  data is not the record's +$05 byte (GetMPCost reads the character
  spell-list copy for magic, ignores it for the rest); it is a
  parallel bank-$F0 table `Ot6AbilityCostTbl`, keyed by the id
  already in `$3a7b` (attack id $5d–$64 Blitz, $55–$5c SwdTech;
  tool item id $a3–$aa Tools) — the same shape as the class and
  element tables. Numbers are kits.md's columns.
  - The whole mechanic gates on the build-time flag
    **`OT6_MP_COSTS`**, which defaults ON, so the shipped ROM
    charges MP. An explicit
    `-D OT6_MP_COSTS=0` reassembles the pre-feature
    vanilla-OT6 baseline (not one byte of the machinery), kept as the
    differ-checked regression control (`make -C ff6 ff6-en-nomp`
    → `ff6-en-nomp.sfc`). The A/B is proven both ways by
    `tools/tests/battle_mpcost.lua` (self-detecting: charge+refusal
    on the shipped ON ROM, free+absent on the `nomp` baseline).
  - Costs and the level-up refill ship together: costs alone are
    attrition without income.
- **M5 — passives.** The anchor pair rides the esper passive
  machinery; max-MP-up rides the stat channel.
- **M6 — numbers.** The harness (balance-metrics.md) grows MP
  lines: per-fight mp_spent / mp_restored / pool fraction at
  fight end; refill cadence as fights-between-level-ups on the
  pacing route (the mines_pace rig); mp-zero incidence. First
  proposed bands, to be re-proposed after measurement: a trash
  fight spends ~10–25% of an on-curve pool unboosted; mp-zero
  never happens on-route at on-curve levels; a refill arrives
  before ~70% depletion.
