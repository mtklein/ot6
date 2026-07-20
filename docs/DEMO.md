# OT6 — MVP demo notes (2026-07-15)

The demo is the opening Narshe stretch of FF6 with the Octopath combat
loop live: probe weaknesses, chip shields, break, boost, and nuke.

## Playing it

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
  (max 3, never more than you have). **L** takes one back.
- Every press answers: R rings a "ching" (a buzz when you can't), L
  clicks, and while boost is pending the cell by your name swaps to
  1–3 fat arrows pulsing yellow/white. The pips return when you're
  back to zero.
- Out on the battlefield, a matching arrow mark floats beside every
  boosting character — it rides from the R press until their boosted
  action resolves, so you can read everyone's commitment at a glance.

## What boost buys

- **Fight**: +1 real hit per BP (a Genji Glove pair swings both hands
  again, doubling the bonus, the same way it doubles everything else).
- **Tiered spells fold**: Fire boosted once casts as Fire 2, twice as
  Fire 3 — the higher tier's name, animation, and power, while MP is
  charged for the base spell. BP is the price, not MP. Fire/Ice/Bolt/
  Poison/Cure/Life/Slow/Haste lines all fold.
- **Everything else**: damage ×2/×4/×8.
- **The list tells you first, live**: spell lists show tiered spells
  under their folded names, and they re-fold in place as you tap R
  and L — "Cure — Fire" becomes "Cure 2 — Fire 2" mid-browse, with
  the MP cost still the base spell's. What you see is what will cast.

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

`make test` runs the whole gate headless — 29 tests plus same-mint pixel
goldens; `tools/tests/suite.sh` is the list of record (this doc used to
enumerate 12 and drifted). Green as of the v0.1 tag; the 21st test
(probe_shadow_overlap) joined after, in 6275f02.

One more, `battle_vargas`, is FRONTIER-GATED: it fights Vargas on Mt.
Kolts out of `vargas_doorstep.mss`, which only `make frontier` mints, so
`make test` reports it as skipped until that fixture exists rather than
dragging the whole story chain into the gate. `make frontier-test` mints
the chain and runs the same suite with it included (31 tests).

## Known limits (by design, for now)

- (M3 shipped: weapon classes chip shields alongside elements.)
- Cyan's BP-priced Bushido menu is implemented-after-demo (he isn't
  reachable in the demo stretch).
- Enemy shield counts come from an authored per-species table where one
  exists (`Ot6ShieldTbl`, 43 species today, checked before the level
  formula); everything else still falls back to the level formula
  (2 + level/8, cap 6). Broad M6 authoring is the remaining work.
