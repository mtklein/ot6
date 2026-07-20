# The MP economy — design dive v1 (2026-07-17)

Scope: game-wide rules, WoB-sized numbers. Nothing here is
locked, and every number is a placeholder for playtest — said
once here instead of per row. Terminology (ruling 2026-07-17):
the pool keeps its vanilla name MP — the name existing players
already know — enemy break counters are "shields", and SP is
not used.

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
- **The free floor.** Attack, Defend, Item, and Row never cost
  MP — Octopath's own floor. An empty pool leaves a character
  diminished, never stranded, and Item is the channel refill
  consumables arrive through.
- **Free-to-learn is not free-to-use.** Pillar 1's "signature
  is free" (DESIGN.md) reads as free at join — no deed, no
  level gate, no JP. Signatures become the cheapest rows of
  their kits (1–4 MP), not costless: the driver's directive is
  that verbs free in vanilla — Steal and Tools by name — stop
  being free under Octopath rules.
- **Boost never raises MP cost.** The shipped tier fold queues
  Fire 3 at Fire's cost (DEMO.md): BP is the tier price, MP the
  cast price. That split ports unchanged to every costed verb.
- **One price scale.** Kit skills live in the same ability
  records as spells (research/data-formats.md), so they price
  on the vanilla spell ruler: Fire 4, Fire 2 20, Fire 3 51.

## The verb survey

Already costed, unchanged: **Magic**, **Lore**, and **summons**
keep their vanilla MP costs (house rule); summons additionally
stay once per battle (DESIGN.md). Strago's kit is Lores, so it
is already priced — his "free signature" Aqua Breath (kits.md)
is free at join, and costs MP like any lore. **Divines** cost
MP in addition to their gates — broken target, the 5-BP bank,
once per battle (ruling 2026-07-17): no free apex actions; the
gate limits frequency, MP prices the cast.

Vanilla-free player verbs, with proposed cost shapes:

| Verb | Shape | MP | Rationale |
|---|---|---|---|
| Steal (Locke #1) | flat small | 2 | the probe-collect verb prices like the cheapest spell |
| New kit skills (Locke #2–7, Analyze, …) | scaled by tier | 3–20 | born costed via M4 kit tables — never free in vanilla; Analyze stays cheap (2–3) because scouting fuels the loop |
| Tools (Edgar) | scaled by tier | 3–20 | reusable capital bought with gil; MP is the operating cost — AutoCrossbow 3–4, Drill/Chainsaw 12–20, Debilitator 8–12, Overclock costs the sum of the two tools it fires |
| Blitz (Sabin) | scaled by tier | 2–30 | the ladder must fit the game's smallest pool (base 3 MP): Pummel 2–3, mid-kit 6–15, Bum Rush at the top |
| Bushido (Cyan) | BP tier + discounted MP | 1–8 | both currencies (ruling 2026-07-17, below): the BP ladder is the real price, so MP rides lighter than comparable-power skills |
| Dance (Mog) | flat, paid at start | 4–10 | one payment starts a whole-battle state — vanilla's can't-stop-dancing lock is preserved, so the price is per battle, not per step |
| Capture (Gau) | flat small | 2 | the other probe-collect verb, priced with Steal (Leap and berserk Rage are retired — kits.md) |
| Beast skills (Gau's stable) | flat per beast | 3–10 | authored alongside the stable curation pass (M6) |
| Sketch (Relm) | flat small | 2–4 | pay to roll; the Sketch bug stays (house rule) and does not refund |
| Control (Relm, kit TBD) | flat moderate | 8–12 | vanilla's strongest free verb — full command of a monster; priced when her kit lands |
| Slots (Setzer) | flat small | 1–3 | the reels stay the real price; MP only makes spins finite |
| Runic (Celes) | free — exception | 0 | the income verb: vanilla Runic already credits the absorbed spell's cost to her pool — kept, on top of +1 BP (kits.md) |
| Throw (Shadow) | free — exception | 0 | the thrown item is consumed; a per-use price already exists |
| Coin Toss, Hired Help (Setzer) | free — exception | 0 | GP-priced verbs stay GP-priced — Octopath's merchant skills spend money, not MP; same precedent |
| Mimic (Gogo) | free — exception | 0 | vanilla Mimic copies the action, never the price; bonus-character jank preserved |
| Guest verbs: Health (Banon), Shock (Leo), magitek beams, Possess (Ghost) | free — exception | 0 | guests have no kit tables; their stretches are authored tutorial texture (the Whelk line is balanced on free beams — balance-metrics.md), and Possess already costs the ghost |
| Relic-morphed commands (Jump, GP Rain, X-Magic, …) | inherit | — | assigned at M4 data entry in the same records as everything else |

### Cyan pays in both (ruling 2026-07-17)

Bushido keeps kits.md's BP ladder — Fang 0 up to the 3-BP
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
BP-Bushido gate stands; the MP column joins the same data
pass. Detailed Cyan tuning is deliberately deferred until he
is playtestable.

**Amended by what shipped (M3, `Ot6BushidoTier`).** The BP half
landed; the MP half is now BUILT (v0.4) but dormant — Bushido
costs 0 MP in the shipped ROM and its priced column
(kits.md, proposed there) charges only under `OT6_MP_COSTS`
(see "Where it lands / M4" below). Two clauses of the
ruling above did not survive contact:

- "BP spent beyond a tech's tier requirement boosts it with the
  same scaling logic as any other action" is not what shipped.
  Boost *selects* the tech rather than gating a menu choice, so
  there is no surplus to scale: a spend always buys the best
  tech it can reach. Bushido is excluded from `Ot6BoostDmg`'s
  multiplier for the same no-double-dip reason folded spells
  are. Unusable spend (three points before Cyan has learned past
  Fang) is consumed, not refunded — the deal a mage already
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
  shredders (AutoCrossbow, Flurry) make this strong, so it
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

## Open questions for the driver

1. **Cost display.** Costed verbs need menus that show costs.
   The magic menu already renders MP columns; Tools, Blitz,
   Dance, stable, and Slots menus do not. The menu list
   machinery exists (class icons and fold previews already
   ride it), and the C toolchain points at menu work — scope
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
  dormant behind a flag.** The prediction below held exactly:
  the code was one dispatch change. Vanilla's `GetMPCost`
  (battle_main.asm) prices only magic/lore/summon/x-magic;
  every other command — Blitz, Bushido, Tools, the free floor —
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
  already in `$3a7b` (attack id $5d–$64 Blitz, $55–$5c Bushido;
  tool item id $a3–$aa Tools) — the same shape as the class and
  element tables. Numbers are kits.md's columns (Cyan's proposed
  there for the first time).
  - **Why dormant, not shipped enabled.** The one magic-specific
    piece is the menu grey-out/display (`CheckMagicEnabled`):
    the Magic menu shows an MP column and greys unaffordable
    spells, but the Blitz/Bushido/Tools menus show no cost and
    check no MP. A silent charge on a menu that says nothing is a
    hidden tax, and there is no honest subset that can ship
    enabled now (no new verb's menu can show a cost without the
    menu-bank work, which needs the not-yet-reinstalled Calypsi
    C toolchain). So the whole mechanic gates on a build-time
    flag **`OT6_MP_COSTS`, default off**: with it off, not one
    byte of the machinery is assembled and the ROM is
    byte-identical to the pre-feature baseline; with it on
    (`make -C ff6 ff6-en-mp`), the charge and refusal land. The
    A/B is proven both ways by `tools/tests/battle_mpcost.lua`
    (self-detecting: charge+refusal on the ON ROM, free+absent on
    the shipped OFF ROM). It flips on the day the menu can
    display costs — see the menu work order below.
  - The level-up refill (the income half) is NOT built here — it
    is a separate battle-bank hook where level-ups apply
    (DoLevelUp), and costs+refill must ship together (costs alone
    are attrition without income). That, plus the menu display,
    is what still gates flipping the flag on.
  - Demo rungs 1–2 are unaffected (guest verbs stay free,
    Terra's magic is already costed); rung 2–3 fixtures
    re-measure when it lands.

  **The menu work order (for when Calypsi C lands).** To flip
  `OT6_MP_COSTS` on honestly, the menu bank must show and enforce
  these costs the way it already does for Magic:
  - The Magic menu's cost column and grey-out are
    `UpdateEnabledMagic` / `CheckMagicEnabled` (battle_main.asm)
    walking the character spell list and comparing each spell's
    MP byte against current MP. Blitz/Bushido/Tools have no
    equivalent — their menus (btlgfx bank C1 / menu bank C3) draw
    no MP column and run no enable pass.
  - Needed: (1) a per-row cost lookup for those menus that reads
    `Ot6AbilityCostTbl` (already the runtime authority, so the
    menu and the charge can never disagree); (2) a draw routine
    that renders the cost string in the ability-list window
    (the same MP-column cell Magic uses — small-font digits
    $B4–$BD, per surgery-map.md §5); (3) a grey-out/refuse pass
    that disables (or blocks confirm on) a row whose cost exceeds
    current MP, mirroring `CheckMagicEnabled`. The Bushido window
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
