# OT6 — MVP demo notes (2026-07-15)

The demo is the opening Narshe stretch of FF6 with the Octopath combat
loop live: probe weaknesses, chip shields, break, boost, and nuke.

## Playing it

Legal cleanliness: the repo never distributes the ROM. The public
artifact is the patch.

    make patch      # -> build/dist/ot6-from-ff3us10.bps

Apply it to a verified FF3us 1.0 dump ("Final Fantasy III (USA).sfc",
SHA1 4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7) with Flips or any
BPS-capable patcher, or just:

    make run        # builds + opens the local Mesen with the patched rom

## What's new on screen

- **Under each monster**: a shield icon with its shield-point count
  ('B' while broken), followed by one cell per elemental weakness —
  a colored element icon once revealed, '?' while hidden.
- **Ability lists**: each ability shows its element icon, colored, so
  weaknesses and abilities can be matched Octopath-style.
- **After each party member's name**: BP pips (5 sockets, bright =
  spendable). Everyone opens battle with 1 BP and gains +1 per turn
  (cap 5) — but not on a turn they boosted.

## Controls

- **R** during your command menu: commit +1 BP to the coming action
  (max 3, never more than you have). **L** takes one back. The pips
  dim as you commit. Boost multiplies damage ×2/×4/×8.

## Systems live under the hood

- Shields seed from monster level (2 + level/8, cap 6). Hitting a
  monster's elemental weakness chips 1 shield point and reveals that
  weakness. At 0 the monster **breaks**: it loses its turns for a
  while and takes ×2 damage until it recovers (shields restore,
  reveals persist).
- **Weakness codex**: reveals persist *across battles*, Octopath
  style — fight a species once and its known weaknesses show from the
  start forever after (stored in the save SRAM's second bank; the
  cartridge header grew to 32KB battery RAM for it).

## Verification

`make test` runs the whole gate headless: smoke, battle_entry,
battle_break, battle_bp, battle_boost, battle_codex, visual_f1,
visual_f2, plus a same-mint pixel golden — across two battle
formations. All green at every commit on main.

## Known limits (by design, for now)

- Break/weakness system is element-only; weapon classes come in M3.
- Boost multiplies damage; per-skill boost effects (extra Attack hits,
  spell-tier folding) come with M3/M4.
- Cyan's BP-priced Bushido menu is implemented-after-demo (he isn't
  reachable in the demo stretch).
- Enemy shield counts use the level formula; a per-monster table is
  M6 tuning.
