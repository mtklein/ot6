# Playtest findings — v0.6-rc1 (owner run, started 2026-07-28)

Live ledger: every owner report from the rc1 playthrough, with its
disposition. Positive signals recorded too — balance findings are data,
not just bugs.

| # | where | finding | disposition |
|---|---|---|---|
| 1 | general | Boost pips should clear exactly when the boosted ability resolves; weakness reveals should appear exactly on the matching damage frame, across all same-species enemies — "these things need to feel connected" | #33, v0.7 battle-UI wave |
| 2 | general | Dance needs to cost MP | #34, design already in mp-economy.md:96 (flat, at dance-start) |
| 3 | Moogle defense | No MP visible anywhere in battle for Locke; Steal charges invisibly | #35 — root cause: vanilla has NO battle MP display at all; wallet-in-the-shop design, front of the wave, rc2 candidate |
| 4 | through Moogle defense | **Combat balance is good so far — tense, even** | positive; first human validation of the break/boost tuning bands (M6's Kolts/Zozo passes were machine-measured only) |
| 5 | Moogle defense | Locke shows no MP in the FIELD menu either (Terra does) | folded into #35 — CheckMPVisible (menu_common.asm:2311) gates on espers-owned/spell-known; the blackout self-resolves at the first magicite, i.e. exactly the opening stretch is dark |
| 6 | early WoB | Menus sometimes show another character's spells — e.g. **Tools shows Cure 2** (cross-list contamination) | #36 — owner: predates v0.6, NOT a tag blocker; re-milestoned v0.7; investigation running (blame sweep + severity check decide if it jumps the queue) |
| 7 | South Figaro → Mt. Kolts | **No release blockers so far** | positive; rc1 holding through band 2 |
