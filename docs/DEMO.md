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
  Fire 3 — the higher tier's name, animation, power **and MP cost**.
  BP buys the tempo, MP buys the power (#64): one Fire 3 instead of
  three Fires still saves you two turns, and you pay 51 rather than
  4 for the magnitude. Fire/Ice/Bolt/Poison/Cure/Life/Slow/Haste lines
  all fold.
- **Everything else**: damage ×2/×4/×8.
- **The list tells you first, live**: spell lists show tiered spells
  under their folded names, and they re-fold in place as you tap R
  and L — "Cure — Fire" becomes "Cure 2 — Fire 2" mid-browse, **and
  the MP cost and the grey-out follow** (#64): a tier you cannot afford
  goes grey the moment you boost into it, and un-greys when you tap L
  back. What you see is what will cast, and what it says it costs is
  what it costs.

## Systems live under the hood

- Shields seed from monster level (2 + level/8, cap 6). Hitting a
  monster's elemental weakness chips 1 shield point and reveals that
  weakness. At 0 the monster **breaks**: it loses its turns for a
  while and takes ×2 damage until it recovers (shields restore,
  reveals persist).
- **Weakness codex**: reveals persist *across battles*, Octopath
  style — fight a species once and its known weaknesses show from the
  start forever after in that save slot (stored in a per-slot page of
  the save SRAM's second bank; the cartridge header grew to 32KB battery
  RAM for it).

## Verification

`make test` runs the whole gate headless — 35 tests plus same-mint pixel
goldens, plus the mp-cost A/B's ON half on the flagged variant ROM;
`tools/tests/suite.sh` is the list of record (this doc used to
enumerate 12 and drifted). Green as of the v0.1 tag; the 21st test
(probe_shadow_overlap) joined after, in 6275f02.

Six more — `battle_vargas`, `battle_kefka`, `battle_flyin`,
`battle_hudclobber`, `battle_hudanim16`, `battle_hudtrail` — are
FRONTIER-GATED: each asserts on a fixture only `make frontier` mints
(Vargas's ledge, the Battle for Narshe, the Mt. Kolts cave pool, the
moogle defense, the Lete River raft), so `make test` reports them as
skipped until those fixtures exist rather than dragging the whole story
chain into the gate. `make frontier-test` mints the chain and runs the
same suite with them included (39 tests).

> **CORRECTION — 2026-07-30. This is a v0.1-era demo note; every count in
> the two paragraphs above is stale, and the A/B is described backwards.**
> The paragraph's own advice — *`tools/tests/suite.sh` is the list of
> record* — is the right answer, and this doc drifted again exactly as it
> warned it would.
>
> - **35 / 39 tests → 59 non-frontier, 23 frontier-gated, 82 total**
>   (`grep -h '^-- @suite' tools/tests/*.lua`, 2026-07-30). The
>   frontier-gated set is no longer six: it now also includes
>   `battle_brokendeath`, `battle_costtable`, `battle_gaufight`,
>   `battle_naturalmp`, `battle_ultros2`, `codex_ctx`, `codex_saveas`,
>   `field_mpvisible`, `field_navstep`, `save_checksum` and the six
>   `menu_*` pages.
> - **The mp-cost A/B runs the other way round.** `OT6_MP_COSTS` defaults
>   to **1**, so `battle_mpcost.lua` runs its **ON** half (charge +
>   insufficient-MP refusal) on the **shipped** ROM as an ordinary suite
>   member; the `test` recipe then re-runs the same self-detecting script
>   with `OT6_ROM=ff6/rom/ff6-en-nomp.sfc` for the **OFF** negative
>   control (`Makefile:127-137`, `:164-166`). The variant ROM is the
>   *baseline*, not the flagged build. `docs/TOOLING.md` states this
>   correctly.
> - **"the 21st test"** was already inconsistent with "35 tests" two lines
>   above it when written. `probe_shadow_overlap` and commit `6275f02` are
>   both real; only the ordinal is dead.

## Known limits (by design, for now)

- (M3 shipped: weapon classes chip shields alongside elements.)
- Cyan's BP-priced Bushido menu is implemented-after-demo (he isn't
  reachable in the demo stretch).
  *(**Shipped in v0.5** — the direct SwdTech submenu and configurable
  loadout, `Ot6BushidoListOpen` at `ot6_kits.asm:842`.)*
- Enemy shield counts come from an authored per-species table where one
  exists (`Ot6ShieldTbl`, 43 species today, checked before the level
  formula); everything else still falls back to the level formula
  (2 + level/8, cap 6). Broad M6 authoring is the remaining work.
  *(**2026-07-30:** 43 → **74** authored species, `ot6_hud.asm:1676-2155`.
  The formula fallback and its bounds are unchanged.)*
