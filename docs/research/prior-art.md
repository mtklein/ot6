# Research: prior-art FF6 mechanics hacks (verified 2026-07-14)

Headline: **no SNES FF hack has ever shipped an Octopath-style break/shield
system, a boost-point economy, or visible enemy HP/gauge UI.** OT6 is novel
on all three. Below: the nearest neighbors and which ones publish source.

## Brave New World (BTB & Synchysi) — source PUBLIC

https://github.com/Gens81/brave-new-world (xkas 0.06 asm + flips; ~95% asm)
- Per-character esper restrictions; custom per-esper spell lists (spell
  access defines identity — same instinct as OT6's kits).
- Esper-level stat growth decoupled from character levels; espers also give
  **on-equip bonuses active only while equipped** — reference code for our
  magicite-as-subjobs.
- Rewritten damage formulas; stamina rework; nATB (ATB pauses during
  animations, by Think0028).
- Caveat: `asm/private/` withheld, so public tree is ~complete-minus-easter-eggs.

## Comprehensive ATB Enhancement (RoSoDude, v2.00 Oct 2025) — source PUBLIC

https://www.romhacking.net/hacks/8513/ (asm ships in the download "as a
reference for other modders")
- Three modes: Modern ATB (time flows during animations), Classic ATB
  (pauses), and a **CTB Wait Addon: fully turn-based FF10-style battles** —
  the closest thing to a true non-ATB FF6 that exists.
- Direct relevance: our stretch goal (round-based Octopath turns) has
  working published prior art. Also doubles ATB rate, scales status timers.

## SwdTech / Blitz QoL prior art

- HatZen08 "Sword Tech Ready Stance" — menu-select the tech immediately
  (https://www.romhacking.net/hacks/995/). Validates killing the gauge.
- SilentEnigma "SwdTech Suspend" v1.1 (2025) — background charging
  (https://www.romhacking.net/hacks/7734/).
- Slick Productions' menu-based Blitz/SwdTech select patch — **source in
  zip**, rehosted: https://www.ff6hacking.com/forums/thread-3945-post-40789.html
- ReCast FF3 (C-Dude) simplified Blitz inputs + fallback on failed input
  (https://www.romhacking.net/hacks/5144/).

## Esper-rework prior art

- **HatZen08: magic castable only while esper equipped, learning disabled**
  — the exact skeleton of magicite-as-subjobs
  (https://ff6hacking.com/wiki/doku.php?id=ff3:ff3us:patches:hatzen08).
- Synchysi: per-character esper restrictions, standalone asm **posted
  in-thread**: https://www.ff6hacking.com/forums/thread-2770-post-38072.html
- Return of the Dark Sorcerer: espers don't teach/boost; abilities learned
  from class-restricted equipment (patch-only, no source; credits list ~70
  borrowed patches): https://www.romhacking.net/hacks/2207/
- FF6 Reimagined: FF12-style equipment passives; espers' level-up bonuses
  removed (https://romhackplaza.org/romhacks/final-fantasy-vi-reimagined-snes).
- A Soldier's Contingency: mage-only magic/espers; menu Blitz/Bushido
  (https://romhackplaza.org/romhacks/final-fantasy-vi-a-soldiers-contingency-extended-bestiary-edition-snes/).

## Confirmed absent (we'd be first)

- Enemy HP bars / numeric enemy HP in battle: none released (closest:
  bestiary menus out of battle; RetroAchievements overlays are
  emulator-side). Low confidence only that no unindexed WIP exists.
- Break/stagger/shield or boost/combo-point systems: none on FF4/5/6 SNES.

## Data-layout references

- Beyond Chaos randomizer (Python, open source) — item/monster/esper/spell
  table layouts in readable code: https://github.com/subtractionsoup/beyondchaos
- T-Edition docs (mechanics overhaul reference, no source):
  https://solairerocks.github.io/FF6T-EditionResources/
