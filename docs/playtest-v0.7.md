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
