# OT6 Roadmap

Every milestone ends with a buildable ROM, a distributable `.bps` patch, and
a save/savestate that demos the new behavior. Order is chosen so the two
signature systems (Break, BP) are playable against vanilla content early —
menus, data entry, and balance come after the fun is proven.

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

## M2 — BP economy + Cyan

- BP accrual (+1 on turn, cap 5, no-regen after boosting), spend ≤3 at
  action confirm.
- Boost effects, first pass: Attack +1 hit/BP; a flat damage multiplier for
  skills/magic.
- BP display (MVP: numeric next to name/HP).
- Cyan converted: charge gauge removed, Bushido menu priced in BP per DESIGN.

**Exit:** Lete River stretch playable with boost decisions mattering; Cyan
usable start to finish without the charge gauge.

## M3 — Weapon classes + reveal

- Weapon-class table for all weapons; per-enemy weapon-weakness byte
  (new side table in expanded ROM).
- Skill chip assignments (each Blitz/Tool/Lore/Dance gets class or element).
- Discovered-weakness tracking per battle; target-select shows known
  weaknesses + shield count (text MVP). Strago's Analyze added.

**Exit:** full break loop indistinguishable in structure from Octopath's:
probe, reveal, chip, break, nuke.

## M4 — Skill lists + JP

- Per-character 8-skill kits enforced; boost-tier spell folding
  (Fire/Fira/Firaga via BP) replaces spell-tier bloat.
- Magic AP → JP; purchase menu (menu-bank work); escalating costs; passives
  unlock at 2/4/6/8.

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
