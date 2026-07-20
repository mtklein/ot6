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
| 3 | scenario split → Kefka at Narshe | shipped in v0.3. ~~Cyan BP-Bushido~~ shipped (M3, `Ot6BushidoTier`; kits.md); remaining: fixtures reaching and crossing the split, the Narshe defense's 3-party machinery, Celes's Runic→BP, and Cyan's MP column (mp-economy.md). Enemy data authored through here (armor line + Kefka poison) |
| **4 (current)** | **Zozo / first espers — through Zozo, Dadaluma beaten, sub-jobs in hand** | M5 magicite sub-jobs |
| 5 | end of WoB (Floating Continent) | M4 kits + sweeps (boss data already reaches Nerapa) |

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
  persist across battles in the second SRAM bank (`battle_codex.lua`).
- ✅ Under-monster HUD on the BG3 field map: shield-with-count glyph
  ('B' broken) + per-weakness revealed-icon/'?' cells — the M1
  "weakness strip" is superseded by this.
- ✅ **Boost feedback** (2026-07-16): ching/buzz/click on R/L, pending
  boost as a pulsing arrow cell (the party window is double-buffered —
  live cells paint both bands), boosted spell lists preview folded
  names before the choice is made, and an arrow mark floats beside
  every boosting character on the battlefield until their action
  resolves.
- ✅ **C toolchain pilot** (2026-07-16): Calypsi 65816 compiles
  `ff6/src/c/` into blobs pinned at `$f0f000`, exercised in-battle by
  the gate (battle_c). Menu-heavy M4/M5 modules can be written in C;
  hooks and NMI code stay ca65. First real port candidate: the codex.
- ✅ **Attack +1 hit per BP** (2026-07-16): extra swings via the vanilla
  alternating-hands machinery; Genji Glove doubles the bonus.
- ✅ **Boost-tier spell folding** (2026-07-16): Fire → Fire 2 → Fire 3
  at 1/2 BP, queued as the higher tier (name, animation, power) with
  the base spell's MP cost; tier-family spells never take the generic
  multiplier. Fire/Ice/Bolt/Poison/Cure/Life/Slow/Haste lines.
- ⬜ Cyan converted (charge gauge → BP Bushido): post-demo, he is not
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

## M4 — Skill lists on the native verbs

- Per-character 8-skill kits enforced; boost-tier spell folding
  already shipped with the demo.
- Learn schedules scripted on each character's native verb (levels,
  items, deeds, story — design/kits.md): **likely no JP system at
  all**; JP returns only if playtesting wants a pacing knob.
- Curated-kit machinery for Gau and Strago (learn many, equip ~5 —
  the Ochette/Hikari model); menu-bank work shifts here from the
  cancelled JP purchase menu, and the C toolchain carries it.
- Passives unlock at 2/4/6/8 skills learned.

**Exit:** fresh save through Zozo with every character on their kit.

## M5 — Magicite as sub-jobs

- Esper equip grants spell list + stat mods while equipped; permanent
  learning removed; summon = once-per-battle divine.
- Level-up esper bonuses removed (replaced by the equip mods).

**Exit:** swapping magicite mid-dungeon visibly swaps a character's kit.

## M6 — Tuning pass

- Shield values + weakness sets hand-authored for Narshe → Zozo encounters
  and bosses; global enemy HP reduction; boss telegraphs.
- Playtest loop with scripted battle regressions.

**Exit:** the opening third of the game plays as a coherent Octopath-like.

## Stretch

- True round-based turn order with visible queue (replaces ATB).
- Shield pips / weakness icons as real battle-UI graphics.
- Passive-equip menu (choose 4), damage cap raise, Trance rework,
  Gau capture/stable UI.
