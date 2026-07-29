# Playtest findings — v0.7 (owner run, started 2026-07-29)

Same ledger discipline as v0.6: every owner report with its disposition,
positives included. The ratchet question this release must answer is
whether anything got *worse* than v0.6 in territory already played.

| # | where | finding | disposition |
|---|---|---|---|
| 1 | Skills → SwdTech | **The page works.** Four rounds of fixes (garble, geometry, cursor gutter) confirmed good by the owner | positive; #39/#43 verified in play |
| 2 | Skills → SwdTech | L/R being the swap control is not discoverable — "that part was not obvious" | #44, fix in flight; applies to Gau's Rage page too |
| 3 | Skills → Rage | **The Rage page looks good too.** Wants the same L/R note, plus `-default-` placeholders where a slot is unset rather than blanks | #44 scope extended; the placeholder wording depends on real semantics (page-wide AUTO vs a genuinely empty slot in a manual loadout) — honesty over the literal string |
| 4 | battle | **Everyone has MP now** | positive; #32's universal battle-MP fix confirmed in natural play, and the #35 wallet is what makes it legible |
| 5 | battle | **Weakness-reveal timing reads right** — "i almost didn't even notice it happening, which is perfect for a player" | positive; #33 confirmed. The desync removed was measured at 366 frames (holy) / 282 (bludgeon) on the Ghost Train leg — invisible is the target state |
| 6 | Cyan, LV14 | Bushido's 1-BP floor endorsed ("fine to have them always cost BP, at least for now — BP's not that scarce"), but **MP costs are noise**: 1/2/3 against a 96 MP pool | #45 — the sharper reading: NEITHER resource binds Cyan at this level. Costs ladder by ability tier, pools ladder by level, so the player always holds the cheap bottom of every ladder |
| 7 | Cyan, LV14 | Owner's starting number for the rescale: **at least 4x** | folded into #45; modelled rather than applied flat — 4x lands well at the floor but Bum Rush 30→120 would exceed WoB pools, so the shape is likely ladder compression |
| 8 | Skills → Blitz | Sabin's field page still teaches the **retired key combos**; wants names, MP costs, break icons | #46 — same class as #27's dead learn-rate columns: a page describing mechanics we no longer have |
| 9 | Gau | No free action — vanilla gives him Rage/Leap/Item and no Fight, so a priced Rage leaves an out-of-MP Gau with nothing | #47 — required by mp-economy's own target (Fight must sometimes be right). Also makes check_break_reach honest: it credits Gau with weapons and fists he currently cannot swing |
| 10 | Sabin vs Cyan | Blitz costs feel closer to right than Bushido: **Sabin ~2x, Cyan ~4x** | folded into #45 — and it decomposes: Bushido's ~1/3 discount was justified by its free BP0 rung, which #38 deleted. 4x/2x ≈ undoing that discount plus a general 1.5x lift |
| 11 | battle | **Breaking an enemy has no audio-visual moment** — the system's signature beat lands silently. Wants "the flash on critical, but local to the broken enemy" | #48 — and the engine already HAS a per-monster flash (btlgfx_main.asm:23386/:23398/:23441), distinct from the screen-wide critical flash the owner correctly ruled out |
| 12 | Serpent Trench, LV14 | **Barely survived — "intense, a cool experience!"** | positive, and a rare data point: this band was never balance-swept (M6's measured passes are Kolts and Zozo). Difficulty landing right here is unmeasured luck holding, worth knowing before any global HP/damage change |
| 13 | naming | **Keep the FF3-US translations** — SwdTech and Dispatch over Bushido and Fang; "they'll feel homey to the players" | recorded in CONTRIBUTING as a naming rule; #50 sweeps our prose and comments onto it. Also retroactively justifies #44's SWDTECH title |
