# OT6 Roadmap

Every milestone ends with a buildable ROM, a distributable `.bps` patch, and
a save/savestate that demos the new behavior. Order is chosen so the two
signature systems (Break, BP) are playable against vanilla content early —
menus, data entry, and balance come after the fun is proven.

## The headline metric: the playable frontier

Progress is measured in playtest terms: **how far into the game we'd tell a
playtester to play before stopping.** A rung is reached when the fixture
pipeline reaches it, the balance bands measure green there, and every
recruited character's kit is honest there.

| rung | stop point | gated on |
|---|---|---|
| 1 | the Moogle defense (~1 hour: mines → Whelk → escape) | shipped in v0.1: difficulty transform, encounter/XP/gil conservation, Whelk fire-add |
| 2 | Figaro → Vargas | shipped in v0.2: fixtures to the Vargas doorstep, the Narshe school, the Bio Blaster as poison key, Vargas's holy add. Band-2 sweep measured (Measurement #6) but *not* tuned — playtest endorsed the shipped resistance at Kolts; break uptime on trash remains ~0% |
| 3 | scenario split → Kefka at Narshe | shipped in v0.3. ~~Cyan BP-SwdTech~~ shipped (M3, `Ot6BushidoTier`; kits.md); remaining: fixtures reaching and crossing the split, the Narshe defense's 3-party machinery, Celes's Runic→BP, and Cyan's MP column (mp-economy.md). Enemy data authored through here (armor line + Kefka poison) |
| 4 | through Zozo — Dadaluma beaten, sub-jobs in hand | shipped in v0.4: M5 magicite sub-jobs (grant + stat bump), the Zozo balance pass (measured), the crane-maze/Ramuh route, Blitz-as-menu, boost-tiered Steal, full HP/MP restore on level-up, Cyan's Cleave |
| **5 (current)** | **end of the Opera sequence — Ultros ② beaten, Setzer joined, Blackjack acquired** | finish and gate the Opera fixture chain; activate the Ultros ② battle gate; ship the incidental systems/polish already accumulated since v0.4, including live ability MP costs, Cyan's SwdTech submenu/loadouts, and universal break-floor coverage |
| 6 | end of WoB (Vector → Floating Continent) | remaining kits and espers; the wide weakness/telegraph pass (boss data already reaches Nerapa); route and tune Vector through the Floating Continent |

## Releases

The rungs ship as tagged `.bps` patches ([README](../README.md) has the
links). What each delivers:

- **v0.1** — through the Moogle defense. Break + BP/boost live: shields,
  hidden weaknesses, chip → break → ×2, boost banking, spell folding
  (Fire → Fira → Firaga).
- **v0.2 / v0.2.1** — through Vargas at Mt. Kolts. The Narshe school
  teaches the loop; Edgar's Bio Blaster makes poison a real key; Vargas
  fights with a shield gauge under the scripted Pummel finish. Break
  authored to *land* — shields empty a round before the kill, so the
  Broken window is a real part of ordinary fights. (.2.1 was a HUD-pip
  fix.)
- **v0.3** — through Kefka at Narshe. All three scenario-split routes,
  the reunion, and the three-party Battle for Narshe. Cyan joins with
  SwdTech rebuilt on Boost Points; Celes with Runic that banks a BP.
- **v0.4** — through Zozo. Espers become sub-jobs (equip grants spells +
  a stat bump; *augment*, not replace, for the born mages); Blitz becomes
  a menu; Steal gains the chance-verb canon; full HP/MP restore on
  level-up; Cyan's Cleave divine (Assassinate built dormant behind
  Shadow; RunicBlade deferred pending its design call).
  Per-ability MP cost is built but dormant. Balance-tuned through Zozo.
- **v0.5** — through the complete Opera sequence: Ultros ② beaten,
  Setzer joined, and the Blackjack acquired. "Every ability costs MP" goes
  live with cost display implemented in ca65; Cyan gains a direct
  SwdTech submenu and configurable loadout; and the generated break floor
  makes every otherwise-unauthored enemy weapon-breakable. This deliberately
  favors getting a coherent playtest build into players' hands over holding
  those improvements for the much longer rest-of-WoB route.
- **v0.6 — Raid on Vector** — Vector and the Magitek Research Facility
  through Number 128, the Cranes, the escape, and Terra's return. Deep-polish
  release: complete redesigns for Ifrit and Shiva, honest Setzer/Factory-era
  kits, authored encounter coverage, boss contracts, player-facing save
  cadence, and a durable tested frontier.
**Releases decoupled from the frontier (2026-07-29).** v0.7 and v0.8 both
shipped without moving the playable frontier at all, and that turned out to
be the better cadence: the owner plays, files findings, and a themed
release folds them in within a day or two. So milestones are named for
their *theme* now, not their rung. The frontier push to the end of the
World of Balance is **v0.10**'s job.

**On versions:** 0.9 is followed by **0.10**, not 1.0 — these are ordinary
increments, not a countdown. 1.0 is a long way off: the end of the World of
Balance is roughly the game's halfway point, and the World of Ruin is
entirely unstarted. (1.0 is still the line where saves become
forward-compatible — see CONTRIBUTING — it is just nowhere near next.)

- **v0.8 — the economy bites** (released): every kit price recalibrated to
  vanilla's own ruler (8-20% of the pool at the level an ability arrives),
  ultimates anchored at 99, the break flash and sound, Gau's Fight and free
  Leap, magicite as gear packages in FF6's own stat encoding, and three
  menu pages that had been lying to the player.
- **v0.9 — Locke, and the break economy** (next): multi-hit as the
  break-rate dial (#54), Locke's kit at last (#55), boosted Runic (#59),
  and the balance work the v0.8 playtest opens.
- **v0.7 — the playtest release** (re-scoped 2026-07-28, owner call): folds
  in the v0.6 playtest's non-blockers — the clockwork HUD sync, the MP
  wallet display, Dance's MP cost, the SwdTech ≥1-BP floor and its
  page fix — plus Gau's Ochette kit (learn many, equip 8). The frontier
  need not move: Sealed Gate route work ships as far as it has landed
  (legs through the crash are already minted with anchors). The owner
  resumes playtesting from the Veldt on this release; any Sealed Gate
  tail rides with Thamasa.
- **v0.8 — Thamasa** — Thamasa and the burning house through Strago and
  Relm joining and the post-massacre mission transition. The Sketch bug
  ships as-is by owner decision, documented in the release notes
  (CONTRIBUTING has the policy history).
- **v0.9 — End of the World of Balance** — the IAF gauntlet, Floating
  Continent, AtmaWeapon, timed escape, and transition into the World of Ruin.

These are useful stopping points, not a promise to ship every number
separately. Adjacent rungs may combine when implementation and playtesting
make that the better release.

**v0.6 enabling order:** #14 isolated parallel test runners → #12 source
modules and central memory ABI → #9 battery-save anchor proof → Factory route.
Issues #11 and #10 are completed to the v0.6 frontier as the route grows.
Issue #13's policy and inventory begin now; Sketch itself stays vanilla by
owner decision (2026-07-28), shipping documented rather than fixed.

**Design canon:** *on damage verbs boost multiplies; on chance verbs
boost guarantees.* Steal shipped it in v0.4 (3 BP = a guaranteed steal of
the rare); Dance / Sketch / Slot / Rage inherit it when their characters
arrive.

**Release discipline:** every distributable is built through `make patch`,
which refuses any ROM the test suite has not stamped green. The human bar
is the owner's ratchet rule (2026-07-28): never release an inferior
experience — a tag must be at least as good as previous releases as far
as the owner has played; unplayed frontier ships on the machine gates
with its gaps documented, and the owner's playthrough trails behind.

## M0 — Toolchain ✅ (done 2026-07-14)

Repeatable build + test loop on this machine. What shipped (details in
[TOOLING.md](TOOLING.md)):

- ✅ Base ROM verified: FF3us 1.0, SHA1-pinned in the Makefile.
- ✅ **Source-rebuild approach** via the everything8215/ff6 disassembly
  (cc65): `make ff6-en` reproduces retail byte-for-byte. We hack real
  modular source, not address-pinned patches.
- ✅ `make rom` / `make patch` (45-byte BPS for the hello-world) /
  `make run` (Mesen GUI) / `make test` (headless Mesen testrunner + Lua,
  pass and fail exit codes both verified).
- ✅ Hello-world: default name TERRA→OCTO; 7-byte surgical ROM diff;
  asserted in-emulator.

**Exit met:** edit → build → automated in-emulator verification, end to end.

## M1 — Break system, elements only, WITH visible shields — ~90% ✅

Mechanics **implemented and acceptance-tested live** (2026-07-15,
`tools/tests/battle_break.lua` passes headless):

- ✅ Shields seed per monster (2 + level/8, cap 6; per-monster table later).
- ✅ Elemental weakness hits chip 1 SP; weakness revealed on first chip
  (vanilla "Weak against X!" message fires once per element).
- ✅ Break at 0 SP: turns skipped (pseudo-status timer), ×2 damage taken,
  shields restore on recovery, revealed weaknesses persist.
- ✅ Shield count digit beside each monster name ('B' while broken),
  verified rendering in live combat screenshots.
- ✅ Element icon tiles in the battle font ($eb-$ef/$fb-$fd), uploaded.
- ⬜ **Remaining:** revealed-weakness glyph strip on target-select (design
  in DESIGN.md; icons already in the font), and per-monster shield table
  to replace the level formula (M6 tuning can absorb this).

**Exit met** for mechanics + shield display; weakness strip carries into
the next work block.

## M2 — BP economy + boost input — ✅ core (2026-07-15)

- ✅ BP accrual (+1 on turn, cap 5, no-regen after boosting), seed 1.
- ✅ Boost damage multiplier ×2/×4/×8, both damage-calc tails.
- ✅ **L/R boost select** in the battle menu (spend ≤3, never past bp),
  with live BP-pip feedback (`battle_boost.lua`).
- ✅ BP display: Octopath-style pips beside each party name (5 sockets,
  bright = spendable), re-staged every menu open + live during boost.
- ✅ **Weakness codex** (pulled forward from M3's tracking): reveals
  persist across battles in a per-save-slot page of the second SRAM bank;
  legacy cartridge-global `O7` knowledge migrates into all three isolated
  `O8` pages. An unsaved New Game uses a fourth transient page until its
  first save (`battle_codex.lua`, `codex_saveas.lua`).
- ✅ Under-monster HUD on the BG3 field map: shield-with-count glyph
  ('B' broken) + per-weakness revealed-icon/'?' cells — the M1
  "weakness strip" is superseded by this.
- ✅ **Boost feedback** (2026-07-16): ching/buzz/click on R/L, pending
  boost as a pulsing arrow cell (the party window is double-buffered —
  live cells paint both bands), boosted spell lists preview folded
  names before the choice is made, and an arrow mark floats beside
  every boosting character on the battlefield until their action
  resolves.
- ✅ **Attack +1 hit per BP** (2026-07-16): extra swings via the vanilla
  alternating-hands machinery; Genji Glove doubles the bonus.
- ✅ **Boost-tier spell folding** (2026-07-16): Fire → Fire 2 → Fire 3
  at 1/2 BP, queued as the higher tier (name, animation, power);
  tier-family spells never take the generic multiplier.
  Fire/Ice/Bolt/Poison/Cure/Life/Slow/Haste lines. Shipped charging the
  BASE spell's MP; **#64 (v0.9) made it charge the tier's own**, and made
  the list's price and grey-out follow.
- ⬜ Cyan converted (charge gauge → BP SwdTech): post-demo, he is not
  reachable in the demo stretch.

**Exit met** for the demo scope: the full probe → chip → break → boost →
nuke loop is playable with visible state everywhere — and boosting is
audible, visible, and previewed. See DEMO.md.

## M3 — Weapon classes + reveal — ✅ core (2026-07-16)

- ✅ Four physical classes (slash/pierce/bludgeon/special ¤); the weapon
  sets Fight's class per swing, abilities keep their own; null-break as a
  per-weapon property (Fixed Dice). All 90 WoB weapon-icon items
  classified; Blitzes/SwdTechs/Tools assigned.
- ✅ Per-species class weaknesses ride the authored shield table (WoB boss
  arc through Nerapa + tutorial trash); codex v2 remembers classes.
- ✅ **Class icons**: each weapon's item icon is its break class icon on
  every surface that renders item names; the type column reads
  SLASH/PIERCE/BLUNT/SPECIAL; inventory Arrange groups by class.
- ⬜ Strago's Analyze (rides M4 kit work).

**Exit met:** the break loop is structurally Octopath's — probe, reveal,
chip, break, nuke — on both element and class axes.

## M4 — Skill lists on the native verbs — 🔨 shipping piecemeal

Landing across releases rather than as one block:
- ✅ **Boost-tier spell folding** (v0.1). ✅ **Cyan's SwdTech rebuilt on
  BP** (v0.3, charge gauge deleted). ✅ **Celes's Runic banks a BP**
  (v0.3). ✅ **Blitz becomes a menu** (v0.4, the fighting-game input
  retired the same way Cyan's gauge was). ✅ **Boost-tiered Steal** +
  the chance-verb canon (v0.4). ✅ **Full HP/MP restore on level-up**
  (v0.4). ✅ **Divine capstones** — Cleave/RunicBlade/Assassinate (v0.4).
- ⬜ **Per-character 8-skill kits enforced** with scripted learn
  schedules (levels/items/deeds/story — design/kits.md): **likely no JP
  system**; JP returns only if playtesting wants a pacing knob.
- ⬜ **Curated-kit machinery** for Gau/Strago (learn many, equip ~5 — the
  Ochette/Hikari model); menu-bank work remains in ca65.
- ⬜ **Passives** unlock at 2/4/6/8 skills learned.

**Exit:** fresh save through Zozo with every character on their kit.

## M5 — Magicite as sub-jobs — 🔨 core shipped v0.4, roster continues v0.6

- Esper equip grants its spell list live (usable while equipped, gone
  when unequipped); permanent learning and level-up esper bonuses
  removed; summon stays a once-per-battle divine.
- **Augment, not replace** (owner call): the born mages (Terra/Celes)
  keep their innate spells and the esper adds a second job; everyone
  else's magic *is* whatever magicite they hold — pure Octopath sub-job.
- **Stat mods are the simple while-equipped kind** for v0.4 (hold it,
  get the bump); the "earn-it-by-carrying" passive version is deferred.
- Boost spell-folding is source-agnostic, so a borrowed Fire folds to
  Firaga under boost. **Not for free since #64** — the fold reaches
  untaught tiers (kept, deliberately: it is what lets every spell list
  stay at 8) but pays that tier's real MP for them.
- v0.4 authors the Zozo espers (Ramuh + Kirin/Siren/Stray). Every esper
  encountered after that receives its own complete redesign in the release
  where it becomes available: Ifrit and Shiva in v0.6, then the later WoB
  roster with its route frontier. The shipped while-equipped spell/stat
  model remains canon for v0.6; learned passives are not a hidden requirement.

**Exit:** swapping magicite mid-dungeon visibly swaps a character's kit.

## M6 — Tuning pass — 🔨 per-stretch, alongside each release

Runs with each rung's balance pass rather than as one late block; the
lesson (Measurements #5–#8) is that break/boost only *land* with
authored weaknesses, and only measured against real fixtures:
- ✅ **Mt. Kolts** authored + measured (v0.2): shielded resistance
  carries difficulty (HP dial retired to 1×); breaks land a round before
  the kill; the weakness axis must be reachable but not the default swing.
- 🔨 **Zozo** (v0.4): poison-clean town (Bio Blaster is the key), the
  corridor's poison/fire absorbers authored around, no-weakness trash
  given a reachable axis. Fire is a coverage hole this stretch (Terra is
  the search target, absent).
- 🔨 **Opera** (v0.5): route and measure Ultros ②; carry the fixture through
  Setzer joining and acquisition of the Blackjack.
- ⬜ **Vector / Magitek Factory** (v0.6): authored encounter coverage,
  boss contracts, save cadence, and frontier fixtures through the Cranes,
  escape, and Terra's return.
- ⬜ **Sealed Gate / banquet** (v0.7), **Thamasa** (v0.8), and **IAF /
  Floating Continent** (v0.9): extend the same measured authoring discipline
  to each newly supported route band. Boss shield/class data already reaches
  Nerapa, but authored rows alone do not make those frontiers release-ready.

**Exit:** the opening third of the game plays as a coherent Octopath-like.

## Stretch

- True round-based turn order with visible queue (replaces ATB).
- Shield pips / weakness icons as real battle-UI graphics.
- Passive-equip menu (choose 4), damage cap raise, Trance rework,
  Gau capture/stable UI.
