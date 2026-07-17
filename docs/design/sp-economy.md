# The SP economy — design dive v1 (2026-07-17)

Scope: game-wide rules, WoB-sized numbers. Nothing here is
locked, and every number is a placeholder for playtest — said
once here instead of per row. In this doc SP means the skill
pool; enemy shield counters are written "shields" (older docs
use SP for those — open question 7).

## Principles

- **SP is FF6's MP pool doing Octopath's job.** Every character
  already has an MP stat, a growth curve, current/max cells in
  save RAM, and menu plumbing. OT6 adds no new resource; it
  widens who pays from that pool. Whether the on-screen label
  reads MP or SP is cosmetic and out of scope here.
- **Three currencies.** HP is danger, SP is sustain, BP is
  spikes. The break interacts with all three: the 2x difficulty
  transform (DESIGN.md) makes probing necessary, the
  restore-on-break passive (below) makes breaks SP income, and
  boosting spends the BP bank into the ×2 window.
- **The free floor.** Attack, Defend, Item, and Row never cost
  SP — Octopath's own floor. An empty pool leaves a character
  diminished, never stranded, and Item is the channel refill
  consumables arrive through.
- **Free-to-learn is not free-to-use.** Pillar 1's "signature
  is free" (DESIGN.md) reads as free at join — no deed, no
  level gate, no JP. Signatures become the cheapest rows of
  their kits (1–4 SP), not costless: the driver's directive is
  that verbs free in vanilla — Steal and Tools by name — stop
  being free under Octopath rules.
- **Boost never raises SP cost.** The shipped tier fold queues
  Fire 3 at Fire's cost (DEMO.md): BP is the tier price, SP the
  cast price. That split ports unchanged to every costed verb.
- **One price scale.** Kit skills live in the same ability
  records as spells (research/data-formats.md), so they price
  on the vanilla spell ruler: Fire 4, Fire 2 20, Fire 3 51.

## The verb survey

Already costed, unchanged: **Magic**, **Lore**, and **summons**
keep their vanilla MP costs (house rule); summons additionally
stay once per battle (DESIGN.md). Strago's kit is Lores, so it
is already priced — his "free signature" Aqua Breath (kits.md)
is free at join, and costs MP like any lore. Divines are gated
rather than priced today; see open question 2.

Vanilla-free player verbs, with proposed cost shapes:

| Verb | Shape | SP | Rationale |
|---|---|---|---|
| Steal (Locke #1) | flat small | 2 | the probe-collect verb prices like the cheapest spell |
| New kit skills (Locke #2–7, Analyze, …) | scaled by tier | 3–20 | born costed via M4 kit tables — never free in vanilla; Analyze stays cheap (2–3) because scouting fuels the loop |
| Tools (Edgar) | scaled by tier | 3–20 | reusable capital bought with gil; SP is the operating cost — AutoCrossbow 3–4, Drill/Chainsaw 12–20, Debilitator 8–12, Overclock costs the sum of the two tools it fires |
| Blitz (Sabin) | scaled by tier | 2–30 | the ladder must fit the game's smallest pool (base 3 MP): Pummel 2–3, mid-kit 6–15, Bum Rush at the top |
| Bushido (Cyan) | BP tier + discounted SP | 1–8 | both currencies (ruling 2026-07-17, below): the BP ladder is the real price, so SP rides lighter than comparable-power skills |
| Dance (Mog) | flat, paid at start | 4–10 | one payment starts a whole-battle state — vanilla's can't-stop-dancing lock is preserved, so the price is per battle, not per step |
| Capture (Gau) | flat small | 2 | the other probe-collect verb, priced with Steal (Leap and berserk Rage are retired — kits.md) |
| Beast skills (Gau's stable) | flat per beast | 3–10 | authored alongside the stable curation pass (M6) |
| Sketch (Relm) | flat small | 2–4 | pay to roll; the Sketch bug stays (house rule) and does not refund |
| Control (Relm, kit TBD) | flat moderate | 8–12 | vanilla's strongest free verb — full command of a monster; priced when her kit lands |
| Slots (Setzer) | flat small | 1–3 | the reels stay the real price; SP only makes spins finite |
| Runic (Celes) | free — exception | 0 | the income verb: vanilla Runic already credits the absorbed spell's cost to her pool — kept, on top of +1 BP (kits.md) |
| Throw (Shadow) | free — exception | 0 | the thrown item is consumed; a per-use price already exists |
| Coin Toss, Hired Help (Setzer) | free — exception | 0 | GP-priced verbs stay GP-priced — Octopath's merchant skills spend money, not SP; same precedent |
| Mimic (Gogo) | free — exception | 0 | vanilla Mimic copies the action, never the price; bonus-character jank preserved |
| Guest verbs: Health (Banon), Shock (Leo), magitek beams, Possess (Ghost) | free — exception | 0 | guests have no kit tables; their stretches are authored tutorial texture (the Whelk line is balanced on free beams — balance-metrics.md), and Possess already costs the ghost |
| Relic-morphed commands (Jump, GP Rain, X-Magic, …) | inherit | — | assigned at M4 data entry in the same records as everything else |

### Cyan pays in both (ruling 2026-07-17)

Bushido keeps kits.md's BP ladder — Fang 0 up to the 3-BP
tier — and adds a discounted SP cost on top, lighter than
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
BP-Bushido gate stands; the SP column joins the same data
pass. Exact discounts are playtest placeholders like every
other number here.

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

## Full HP/SP restore on level up

The rule, Octopath's, ported whole: when a character gains a
level, current HP and SP are set to the new maximums.

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

## SP-management passives

The esper passive pool (magicite.md) is where SP relief lives;
slot rules and learning stay as written there — up to 4 slots,
learned by battles carried, stat passives competing for the
same slots. The anchor pair follows Octopath's support-skill
shapes; names here are descriptive placeholders:

- **SP on victory** — winning a battle restores ~15–25% of max
  SP. Octopath's victory-restore shape; keeps trash chains
  self-sustaining without inn trips.
- **SP on break** — the character who lands a break restores a
  few SP. Octopath's restore-on-break shape; probing spends SP
  and breaking rebates it, tying sustain to the loop's payoff.

Further candidates, one line each:

- **Cost down** — active skills cost −25%, floor 1.
- **Max SP up** — a +max-SP magnitude in the stat-passive
  channel magicite.md already defines.
- **Broken-field regen** — +1–2 SP per turn while any enemy is
  broken; spend the window harder.
- **Chip rebate** — a weakness chip restores 1 SP; multi-hit
  shredders (AutoCrossbow, Flurry) make this strong, so it
  likely needs a per-action cap.
- kits.md's *Afterglow* (first cast each battle free) is the
  same family on the character-passive side.

The WoB roster's passive column (magicite.md) is already full;
these either displace listed candidates or ride WoR espers —
driver's call at M5 data entry.

## Open questions for the driver

1. **Cost display.** Costed verbs need menus that show costs.
   The magic menu already renders MP columns; Tools, Blitz,
   Dance, stable, and Slots menus do not. The menu list
   machinery exists (class icons and fold previews already
   ride it), and the C toolchain points at menu work — scope
   this with M4's curated-kit menus.
2. **Divine pricing.** Divines are gated (broken target, the
   5-BP bank, once per battle) — do they also carry a large SP
   price, Octopath-style, or is the gate the whole price?
   Overclock's sum-of-tools shape suggests per-divine answers.
3. **Enemy-side SP.** Enemies already have MP and spend it in
   vanilla, and the MP kill stays (bosses-wob.md). Proposal:
   change nothing — no shield/SP interaction, no enemy boost.
   Rasp and Osmose quietly gain value as attack and income
   against that pool; watch, don't redesign.
4. **Does the free floor hold?** Yes. Tools are not
   consumables — gil once, reusable forever, so SP is their
   per-use price. Attack/Defend/Item stay free because a
   character with no legal action is a soft lock, and because
   Octopath's floor is the model. Restated as a question only
   so the driver can veto.
5. **Refill items.** Tinctures and Ethers are vanilla-scarce.
   With costed verbs they become a real economy knob — stock
   lists and prices join the M6 tuning surface.
6. **Income spells.** Osmose (Shiva) and Rasp (Ramuh) sit in
   the esper pool (magicite.md). Osmose-cycling under costed
   kits is the obvious degenerate loop; the M6 pass watches it
   next to Facet + Rune Eater.
7. **Terminology.** Older docs use SP for shield points
   (DESIGN.md's break section). One sweep should settle skill
   pool vs shields naming; cosmetic, deferred.
8. **Boosting Bushido.** Downstream of the Cyan ruling: a
   tech's BP tier is its price — can further BP be spent on
   top to boost it, or is the tier the whole BP interaction?
   Playtest at rung 3.

## Where it lands

- **M4 — costs and refill.** Skill SP costs are data in the
  same ability records the kit tables edit: the 14-byte record
  already carries an MP-cost byte for IDs 81–255 — Blitzes,
  SwdTechs, Tools, Dances (research/data-formats.md). Pricing
  is data entry; the code is one dispatch change — commands
  that skip the MP check stop skipping it — plus menu gray-out
  at 0. The level-up refill is a small battle-bank hook where
  level-ups apply (DoLevelUp). Costs and refill ship together:
  costs alone are attrition without income; refill alone is
  free lunch. Demo rungs 1–2 are unaffected (guest verbs stay
  free, Terra's magic is already costed); rung 2–3 fixtures
  re-measure when it lands.
- **M5 — passives.** The anchor pair rides the esper passive
  machinery; max-SP-up rides the stat channel.
- **M6 — numbers.** The harness (balance-metrics.md) grows SP
  lines: per-fight sp_spent / sp_restored / pool fraction at
  fight end; refill cadence as fights-between-level-ups on the
  pacing route (the mines_pace rig); sp-zero incidence. First
  proposed bands, to be re-proposed after measurement: a trash
  fight spends ~10–25% of an on-curve pool unboosted; sp-zero
  never happens on-route at on-curve levels; a refill arrives
  before ~70% depletion.
