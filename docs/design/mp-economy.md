# The MP economy — design dive v1 (2026-07-17)

Scope: game-wide rules, WoB-sized numbers. Nothing here is
locked, and every number is a placeholder for playtest — said
once here instead of per row. Terminology (ruling 2026-07-17):
the pool keeps its vanilla name MP — the name existing players
already know — enemy break counters are "shields", and SP is
not used.

## The target, stated by the owner (2026-07-29)

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
non-choice intact with extra bookkeeping. The v0.7 playtest found the
loose failure: at LV14 Cyan's available techs cost 1-3 MP against a 96
pool while BP was not scarce either, so neither currency bound him and
Fight had no case.

**And the owner's standing expectation: this will take a while.** Getting
a number that is Octopath-right and FF6-right at once is a playtest loop,
not a derivation — so a pass that improves the shape and gets played is
worth more than one that waits to be correct. Successive rescales are
expected and are not churn.

## The ceiling: 99 (proposed 2026-07-29, issue #57)

The owner's shape for the top of every ladder: **each character's own
ultimate costs 99 MP.** It agrees with the ruler below — 99 against a
L70 pool of ~760 is 13%, inside the 8-20% band — so it anchors the table
rather than recalibrating it, and it makes ladders comparable across
characters, which they are not today.

It is also the **hard display ceiling**: the loadout pages render two
digits (#56), so 99 is the largest cost that can be shown at all. Treat
that as a constraint, not a coincidence — no cost anywhere may exceed it.

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

Open: what counts as an ultimate for characters whose top verb is not a
priced ladder (Slot is free, Rage and Dance are flat), and whether Magic
participates. See #57.

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
  being free under Octopath rules. **Confirmed absolute (owner,
  2026-07-22): only the basic Fight command is free — every
  other verb costs MP as its character's kit comes online. (Item
  is inventory-gated, not an MP verb.)**

  > **AMENDMENT (2026-07-29, owner) — the absolute is about the FIGHT
  > ROW, not about the word "Fight". Leap is free.** Owner's words:
  > *"I don't recall showing a cost for Leap. If it's 2 MP, let's just
  > make it free."* Two things force it, and both are about surfaces
  > rather than balance:
  >
  > 1. **The price was never displayed.** Leap is a top-level command
  >    *row*, not a list entry, and the four-row battle command window
  >    draws names only. `command_window_data_set`
  >    (`btlgfx_main.asm:10099-10125`) writes exactly two things per
  >    row — the command byte, and a colour from `GetTextColor` — on a
  >    9-byte stride over four rows, and its template `MenuText::_4`
  >    (`btlgfx_main.asm:45137`) is four fixed 8-byte records with no
  >    numeric field. `GetTextColor` (`btlgfx_main.asm:10704-10707`) is
  >    `and #$80` on the *disabled* flag, so the one grey that window has
  >    is "command unavailable", **not** "you cannot afford it". Contrast
  >    `Ot6BlitzRowDecorate` (`ot6_kits.asm:563-585`), where a list row
  >    explicitly stamps a two-digit cost and greys by affordability
  >    through `Ot6AbilityGrey`. So there was no surface that could show
  >    Leap's 2 MP, and the only way to meet it was a refusal *after* the
  >    turn was spent — the refusal path (`battle_main.asm:8354-8371`)
  >    queues a generic attack message through `_setattackmes`
  >    (`:8720`) and composes no number anywhere. *(The exact refusal
  >    string is **unverified** — I did not trace `$3a71/$3a72` to its
  >    text. What is verified is that no number reaches the player.)* A
  >    price that is invisible until it refuses is a lying surface, and
  >    this document's own economy depends on the player being able to
  >    see what things cost.
  > 2. **Leap now occupies the Fight row** on the Veldt (kits.md's
  >    row-sharing rule, `Ot6VeldtRow`). The absolute exists so that
  >    every character can always decline to spend; a priced verb
  >    *in the Fight row* breaks exactly that, in the one territory Gau
  >    lives in. So the honest reading of the absolute is that the
  >    **free floor** is what is protected, and on the Veldt that floor
  >    is Leap.
  >
  > **Steal keeps its flat 2** — it is a verb *beside* Fight, not the
  > Fight row — but it shares Leap's invisibility problem exactly
  > (same window, same "Need MP", nothing drawn). That is issue #52's,
  > and it is a display bug before it is a pricing question.
- **Boost never raises MP cost.** The shipped tier fold queues
  Fire 3 at Fire's cost (DEMO.md): BP is the tier price, MP the
  cast price. That split ports unchanged to every costed verb —
  including the now-shipped **boost-tiered Steal** (kits.md): its
  BP buys the guarantee, and its MP question is unchanged by the
  boost, riding the M4 costing (the "flat small ~2" row below)
  exactly like every other free-in-vanilla verb. **Steal is
  costed as of v0.5** (this change): cmd $05 takes a flat-cost
  path in `Ot6AbilityCost` — a single verb with one price, 2 MP,
  keyed on the command rather than an ability-id table row (Steal
  has no per-ability id in the disjoint ranges the id table
  keys on) — and is charged, and refused when the pool is short,
  by the same universal machinery as Blitz/SwdTech/Tools. With
  `OT6_MP_COSTS` off it reverts to free, byte-for-byte.
- **One price scale.** Kit skills live in the same ability
  records as spells (research/data-formats.md), so they price
  on the vanilla spell ruler: Fire 4, Fire 2 20, Fire 3 51.

## The verb survey

Already costed, unchanged: **Magic**, **Lore**, and **summons**
keep their vanilla MP costs (house rule); summons additionally
stay once per battle (DESIGN.md).

> **AMENDMENT (v0.6, 2026-07-27) — one named exception to the
> vanilla-MP-costs house rule: Osmose `$29`, 1 MP → 8 MP.**
> Recorded here rather than left implicit, because
> magicite-ifrit-shiva.md §12.10 is right that this rule has to
> be *amended*, not quietly bent. The rule was written on
> 2026-07-17, **before** `OT6_MP_COSTS` went live and before the
> "only Fight is free" absolute of 2026-07-22 — it priced magic
> for a game in which four characters spent MP at all. Under OT6
> every verb does, and vanilla's 1 MP Osmose is not a spell but
> an off switch for the currency v0.5 had just turned on:
> Magitek Research Facility boss pools run 447–810
> (`monster_prop.dat` +$0a) against party pools of 40–60, and one
> cast computes for many times the caster's whole bar. 8 MP keeps
> it strongly net-positive — measured on the shipped ROM at 30 MP
> against a 500 MP pool: 30 → 22 → 63, so a +33 net refill for 8
> — while stopping it being free, and it stays castable on a
> nearly empty pool. It applies globally, so ZoneSeek inherits it,
> correctly: it is the same spell. The byte lives in
> `battle_main.asm`'s `MagicProp` splice with its argument beside
> it; `tools/tests/battle_magicite.lua` pins both the price and
> the 7-MP boundary that only 8 can produce. **No other magic
> price is touched, and the rule otherwise stands.** Strago's kit is Lores, so it
is already priced — his "free signature" Aqua Rake (kits.md)
is free at join, and costs MP like any lore. **Divines** cost
MP in addition to their gates — broken target, the 5-BP bank,
once per battle (ruling 2026-07-17): no free apex actions; the
gate limits frequency, MP prices the cast.

Vanilla-free player verbs, with proposed cost shapes:

| Verb | Shape | MP | Rationale |
|---|---|---|---|
| Steal (Locke #1) | flat small | 2 | the probe-collect verb prices like the cheapest spell |
| New kit skills (Locke #2–7, Analyze, …) | scaled by tier | 3–20 | born costed via M4 kit tables — never free in vanilla; Analyze stays cheap (2–3) because scouting fuels the loop |
| Tools (Edgar) | scaled by tier | 3–20 | reusable capital bought with gil; MP is the operating cost — AutoCrossbow 3–4, Drill/Chain Saw 12–20, Debilitator 8–12, Overclock costs the sum of the two tools it fires |
| Blitz (Sabin) | scaled by tier | 4–46 | **rescaled by #45** (was 2–30): the ladder must fit the game's smallest pool (base 3 MP), but the floor was under the vanilla ruler — Pummel 4, mid-kit 10–22, Bum Rush 46 at the top |
| SwdTech (Cyan) | BP tier + MP at Blitz parity | 4–46 | **rescaled by #45** (was 1–8, "discounted"): he still pays both currencies (ruling 2026-07-17, below), but the ~⅓ discount is retired — see the amendment box under "Cyan pays in both" |
| Dance (Mog) | flat, paid at start | 4–10 | one payment starts a whole-battle state — vanilla's can't-stop-dancing lock is preserved, so the price is per battle, not per step |
| ~~Capture (Gau)~~ | ~~flat small~~ | ~~2~~ | superseded — the Capture/controllable-stable model was replaced by kit-gau.md's Ochette model, so this row never shipped. The two Gau verbs that did are below |
| Rage (Gau) | flat, paid at start | 8 | one payment starts a whole-battle possession, every possessed turn after it free — the same rule Dance takes, and `Ot6RageCost` tail-calls `Ot6DanceCost` so the two can never drift (#40) |
| Leap (Gau) | free — exception | 0 | **the free floor, not an exemption**: Leap shares Gau's FIGHT row on the Veldt (kits.md), so on the Veldt it *is* the Fight command. It also had no surface that could ever show a price — see the amendment above (owner, 2026-07-29; was flat 2 under #40) |
| Beast skills (Gau's stable) | flat per beast | 3–10 | authored alongside the stable curation pass (M6) |
| Sketch (Relm) | flat small | 2–4 | pay to roll; the Sketch bug stays (house rule) and does not refund |
| Control (Relm, kit TBD) | flat moderate | 8–12 | vanilla's strongest free verb — full command of a monster; priced when her kit lands |
| Slot (Setzer) | flat small | 1–3 | the reels stay the real price; MP only makes spins finite |
| Runic (Celes) | free — exception | 0 | the income verb: vanilla Runic already credits the absorbed spell's cost to her pool — kept, on top of +1 BP (kits.md) |
| Throw (Shadow) | free — exception | 0 | the thrown item is consumed; a per-use price already exists |
| Coin Toss, Hired Help (Setzer) | free — exception | 0 | GP-priced verbs stay GP-priced — Octopath's merchant skills spend money, not MP; same precedent |
| Mimic (Gogo) | free — exception | 0 | vanilla Mimic copies the action, never the price; bonus-character jank preserved |
| Guest verbs: Health (Banon), Shock (Leo), magitek beams, Possess (Ghost) | free — exception | 0 | guests have no kit tables; their stretches are authored tutorial texture (the Whelk line is balanced on free beams — balance-metrics.md), and Possess already costs the ghost |
| Relic-morphed commands (Jump, GP Rain, X Magic, …) | inherit | — | assigned at M4 data entry in the same records as everything else |

### Cyan pays in both (ruling 2026-07-17)

SwdTech keeps kits.md's BP ladder — Dispatch 0 up to the 3-BP
tier — and adds a discounted MP cost on top, lighter than
comparable-power skills elsewhere, because the banked-BP
requirement is the real price. The ladder replaces the vanilla
charge gauge's wait-to-charge rhythm while preserving agency:
the wait still exists — later techs need a fuller bank — but
Cyan acts while it builds. The design consequence: Cyan is the
one kit where banking BP has intrinsic purpose. Measurement #3
(balance-metrics.md) found greedy spending beats banking
against trash, so for every other kit banking needs a boss to
justify it; Cyan's later techs require the bank, so the
decision exists in every fight he is in. Roadmap rung 3's
BP-SwdTech gate stands; the MP column joins the same data
pass. Detailed Cyan tuning is deliberately deferred until he
is playtestable.

**Amended by what shipped (M3, `Ot6BushidoTier`).** The BP half
landed; the MP half is now BUILT (v0.4) but dormant — SwdTech
costs 0 MP in the shipped ROM and its priced column
(kits.md, proposed there) charges only under `OT6_MP_COSTS`
(see "Where it lands / M4" below). Two clauses of the
ruling above did not survive contact:

- "BP spent beyond a tech's tier requirement boosts it with the
  same scaling logic as any other action" is not what shipped.
  Boost *selects* the tech rather than gating a menu choice, so
  there is no surplus to scale: a spend always buys the best
  tech it can reach. SwdTech is excluded from `Ot6BoostDmg`'s
  multiplier for the same no-double-dip reason folded spells
  are. Unusable spend (three points before Cyan has learned past
  Dispatch) is consumed, not refunded — the deal a mage already
  takes on a third point on Fire. A menu that lets him pick a
  *lower* tech than his spend affords is what would revive the
  surplus case; it is not built, and it needs the menu bank.
- "the wait still exists — later techs need a fuller bank"
  holds, and is now the whole mechanic rather than a
  requirement checked against one: banking to 3 is the only way
  to reach the top band.

The MP column, when it lands, prices the cast on top of the
band the BP bought; nothing above about the split ("BP is the
tier price, MP the cast price") changed.

> **AMENDMENT (v0.8, 2026-07-29, issue #45) — the ~⅓ SwdTech
> discount is RETIRED, and the Blitz floor is lifted.** The
> discount above was justified by one sentence — "the banked-BP
> requirement is the real price" — and that sentence was about
> the *four-rung* 0×/1×/2×/3× ladder. **#38 rewrote that ladder
> to 1×/2×/3× and explicitly deferred the MP column** ("MP costs
> per tech unchanged"), so from that moment the discount was
> being applied on the strength of a premise that had already
> been edited. The v0.7 playtest found the consequence from the
> other end (the target box at the top of this file): at LV14
> Cyan holds 96 MP against techs costing 1/2/3, BP is not scarce
> either, so neither currency binds him and Fight has no case.
>
> SwdTech now prices at **parity with the Blitz row of the same
> index**. That is a *level* claim, not an index coincidence:
> `BlitzLevelTbl` is 1/6/10/15/23/30/42/70 and
> `BushidoLevelTbl` 1/6/12/15/24/34/44/70
> (`ff6/src/field/event.asm:1236-1240`), so row *n* of either kit
> arrives in the same band against nearly the same pool. Cyan
> still pays BP on top; if parity plus #38's 1-BP floor leaves
> him starved, #38's own ruling names the lever — **BP
> seed/regen, not the floor, and not this column.**
>
> One deviation from parity: **Empowerer 18 rather than Mantra's
> 16**, because the SwdTech column must stay monotonic with the
> tech index — the boost window offers techs weakest→strongest
> and *the row is the boost level* (kits.md), so a 2× row dearer
> than the 3× row would read as a bug. Blitz is a free-choice
> menu and needs no such rule, which is why Mantra stays a
> cheap utility off-ramp under Fire Dance.

### The ruler, finally measured (issue #45)

This document has claimed since 2026-07-17 that kit skills
"price on the vanilla spell ruler", and never said what that
ruler *is*. Measured — cost as a fraction of the caster's real
max MP **at the level the ability is learned**, pools computed
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
first cast from.** Against that ruler, here is what the v0.5
columns actually were and what #45 makes them. Rows 1–2 are
priced at L10, the earliest either character is in the party at
all (measured: `gau_joined` has Cyan and Sabin both at LV11):

| Blitz | learned | pool | was | was % | now | now % |
|---|---|---|---|---|---|---|
| Pummel | L1 | 56 | 2 | 3.6% | **4** | 7.1% |
| AuraBolt | L6 | 56 | 5 | 8.9% | **10** | 17.9% |
| Suplex | L10 | 56 | 7 | 12.5% | **13** | 23.2% |
| Fire Dance | L15 | 104 | 9 | 8.7% | **17** | 16.3% |
| Mantra | L23 | 191 | 8 | 4.2% | **16** | 8.4% |
| Air Blade | L30 | 278 | 12 | 4.3% | **22** | 7.9% |
| Spiraler | L42 | 449 | 18 | 4.0% | **30** | 6.7% |
| Bum Rush | L70 | 760 | 30 | 3.9% | **46** | 6.1% |

| SwdTech | learned | pool | was | was % | now | now % |
|---|---|---|---|---|---|---|
| Dispatch | L1 | 58 | 1 | 1.7% | **4** | 6.9% |
| Retort | L6 | 58 | 2 | 3.4% | **10** | 17.2% |
| Slash | L12 | 76 | 3 | 3.9% | **13** | 17.1% |
| Quadra Slam | L15 | 106 | 4 | 3.8% | **16** | 15.1% |
| Empowerer | L24 | 205 | 5 | 2.4% | **18** | 8.8% |
| Stunner | L34 | 334 | 6 | 1.8% | **22** | 6.6% |
| Quadra Slice | L44 | 483 | 7 | 1.4% | **30** | 6.2% |
| Cleave | L70 | 762 | 8 | 1.0% | **46** | 6.0% |

Three things fall out of the measurement that were not visible
from the numbers alone:

- **Tools were already right, and are deliberately untouched.**
  Against Edgar's real pool at the band each tool is acquired
  they run 7–21% — AutoCrossbow 11.1% at L7, Drill 18.4% and
  Chain Saw 20.7% at L13 — i.e. dead on the ruler above. The
  general floor lift was offered to them and the data declined
  it: 1.5× on Chain Saw would be 31%, off the top of the scale.
  Gil buys the tool once and MP is the per-use cost; that price
  was correct the first time.
- **The feared ceiling break does not exist.** The worry that a
  4× would push "Bum Rush 30 → 120 past WoB pools" does not
  survive contact with the level gate: Bum Rush is **L70**, and
  Sabin's L70 pool is **760**. Every top-tier row stays payable
  with a wide margin at the level it arrives (the thinnest row
  in the whole table is Suplex, at 4 uses from a full L10 pool).
  The squeeze is at the *floor* and in early WoB, exactly where
  this document already said it was.
- **The gate now exists.** `tools/tests/battle_costtable.lua`
  recomputes every one of these fractions from the ROM's own
  tables on each `make test` and refuses a column that has
  fallen outside 4–25%. The v0.4 column drifted 3–8× under the
  ruler with no test noticing; the owner found it by playing,
  which is an expensive way to learn an arithmetic fact.

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

**Measured, not estimated (issue #45).** The paragraph above was
derived; these are read off the minted chain by
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

- The pacing conservation (Measurement #4,
  balance-metrics.md) pinned XP per step to vanilla — 2x
  rewards at 0.5x encounter rate — so refill cadence tracks
  vanilla's leveling rhythm. The paired danger/reward knobs
  now carry a third duty: they set how often the party
  refills. Changing the pair moves sustain too.
- Attrition changes meaning. Tents, inns, and save points stop
  being the only income; they matter most inside long
  same-level stretches and least right after a level. HP
  refills too, which softens dungeon attrition — the danger
  numbers in balance-metrics.md were measured without a
  level-up in the window, so the M6 pass should watch it.
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
- **Chip rebate** — a weakness chip restores 1 MP; multi-hit
  shredders (AutoCrossbow, Quadra Slam) make this strong, so it
  likely needs a per-action cap.
- kits.md's *Afterglow* (first cast each battle free) is the
  same family on the character-passive side.

The WoB roster's passive column (magicite.md) is already full;
these either displace listed candidates or ride WoR espers —
driver's call at M5 data entry.

Adjacent income, active rather than passive: MP-drain verbs
stay (ruling 2026-07-17), on Octopath's pattern — balanced
when they deal little or no damage themselves and appear on
only a few characters. Osmose (Shiva) and Rasp (Ramuh) sit in
the esper pool (magicite.md), and reaching one is a deliberate
perk: this character can manage their own resources. The M6
pass still watches Osmose-cycling next to Facet + Rune Eater.
**Superseded in part (v0.6):** that ruling predates live MP
costs, and Osmose's *price* has since been amended to 8 MP —
see the amendment box above. The verb itself still stays; what
changed is that it is no longer nearly free.

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
5. **Terminology.** Resolved (ruling 2026-07-17, the
   preamble): the pool is MP as in vanilla, break counters are
   shields, SP is retired — this doc is swept. Older docs
   still write SP for shield points — DESIGN.md's break
   section — left for a later touch-up.

## Where it lands

- **M4 — costs and refill. The charge side is BUILT (v0.4),
  and v0.5 flipped it ON by default** (see "Why dormant" below —
  the flag now ships live; the shipped ROM charges MP). The
  prediction below held exactly:
  the code was one dispatch change. Vanilla's `GetMPCost`
  (battle_main.asm) prices only magic/lore/summon/x-magic;
  every other command — Blitz, SwdTech, Tools, the free floor —
  falls through it returning 0, so the universal charge at
  `CalcAttackEffect` (the `$3a4c` subtract, and its
  insufficient-MP fizzle) never fires for them. `Ot6AbilityCost`
  (ff6/src/battle/ot6.asm) is the single hook, right after that
  `GetMPCost`: for the three costed verbs it swaps the 0 for the
  kit price. Charge AND the insufficient-MP **refusal** are both
  already universal — they act on whatever `$3620`→`$3a4c` holds
  — so nothing new was needed there. The cost data is NOT the
  record's +$05 byte after all (GetMPCost reads the character
  spell-list copy for magic, ignores it for the rest); it is a
  parallel bank-$F0 table `Ot6AbilityCostTbl`, keyed by the id
  already in `$3a7b` (attack id $5d–$64 Blitz, $55–$5c SwdTech;
  tool item id $a3–$aa Tools) — the same shape as the class and
  element tables. Numbers are kits.md's columns (Cyan's proposed
  there for the first time).
  - **Why dormant, not shipped enabled.** The one magic-specific
    piece is the menu grey-out/display (`CheckMagicEnabled`):
    the Magic menu shows an MP column and greys unaffordable
    spells, but the Blitz/SwdTech/Tools menus show no cost and
    check no MP. A silent charge on a menu that says nothing is a
    hidden tax, and there is no honest subset that can ship
    enabled now (no new verb's menu can show a cost without the
    menu-bank work). So the whole mechanic gated on a build-time
    flag **`OT6_MP_COSTS`**. **v0.5 flipped it: the flag now
    defaults ON, so the shipped ROM charges MP — the headline
    v0.5 combat-economy change, landing alongside the menu-bank
    cost display that ends the silence.** An explicit
    `-D OT6_MP_COSTS=0` still reassembles the pre-feature
    vanilla-OT6 baseline (not one byte of the machinery,
    byte-identical to what shipped before), kept as the
    differ-checked regression control (`make -C ff6 ff6-en-nomp`
    → `ff6-en-nomp.sfc`). The A/B is proven both ways by
    `tools/tests/battle_mpcost.lua` (self-detecting: charge+refusal
    on the shipped ON ROM, free+absent on the `nomp` baseline).
  - The level-up refill (the income half) is NOT built here — it
    is a separate battle-bank hook where level-ups apply
    (DoLevelUp), and costs+refill must ship together (costs alone
    are attrition without income). That, plus the menu display,
    is what still gates flipping the flag on.
  - Demo rungs 1–2 are unaffected (guest verbs stay free,
    Terra's magic is already costed); rung 2–3 fixtures
    re-measure when it lands.

  **The menu work order.** To flip
  `OT6_MP_COSTS` on honestly, the menu bank must show and enforce
  these costs the way it already does for Magic:
  - The Magic menu's cost column and grey-out are
    `UpdateEnabledMagic` / `CheckMagicEnabled` (battle_main.asm)
    walking the character spell list and comparing each spell's
    MP byte against current MP. Blitz/SwdTech/Tools have no
    equivalent — their menus (btlgfx bank C1 / menu bank C3) draw
    no MP column and run no enable pass.
  - Needed: (1) a per-row cost lookup for those menus that reads
    `Ot6AbilityCostTbl` (already the runtime authority, so the
    menu and the charge can never disagree); (2) a draw routine
    that renders the cost string in the ability-list window
    (the same MP-column cell Magic uses — small-font digits
    $B4–$BD, per surgery-map.md §5); (3) a grey-out/refuse pass
    that disables (or blocks confirm on) a row whose cost exceeds
    current MP, mirroring `CheckMagicEnabled`. The SwdTech window
    is special: it is `UpdateMenuState_37` (already OT6-owned via
    `Ot6BushidoTier`), and the cost shown must track the
    boost-selected tech, whose id is what `Ot6AbilityCost` reads.
  - This is C3/C1 menu-bank work (research/battle-code-map.md
    notes the C3 Compendium is fully commented, so it is
    well-lit); it is the reason the charge shipped dormant.
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
