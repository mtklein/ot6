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
| 6 | early WoB | Menus sometimes show another character's spells — e.g. **Tools shows Cure 2** (cross-list contamination) | #36 FIXED — OT6 regression (live re-fold, 0c1de19, in every tag); display-only proven (execution used the real tool id); 12-line fix + regression; rc2 cherry-pick |
| 7 | South Figaro → Mt. Kolts | **No release blockers so far** | positive; rc1 holding through band 2 |
| 8 | pre-Kolts | Full HP/MP restore on level-up works as expected | positive; v0.4 feature confirmed in natural play |
| 9 | Vargas | **Blitz updates + the faithfully-kept triple-tutorial: loved.** Owner decision: tutorial stays verbatim, permanently — charm, not redundancy | positive; pinned in bosses-wob.md so no cleanup pass touches it |
| 10 | Imperial Camp (Sabin/Shadow scenario) | **Telstar monster-in-a-box nearly wiped the party — "that was exciting!"** | positive; the ambush-fight class delivering intended tension (unprobed enemy, no codex, full price) |
| 11 | scenarios (Cyan fresh in mind) | Bushido 0-boost tech "feels a bit too much like better attack" — explore ≥1 BP floor, 3-slot window | #38, v0.7; design endorsed — Bushido becomes pure bank-spending, Fight is the free swing |
| 12 | scenario split (Cyan LV14) | **Field Skills→SwdTech page is garbled tile soup** (screenshot; frames/LV/HP fine, list body corrupt) | #39, fix dispatched — suite covered the loadout path, not the player's path; ratchet check (v0.5-era?) included |
| 13 | Phantom Train (Sabin scenario) | **Phantom Train monster-in-a-box also a good challenge** | positive; second ambush-fight data point — the class is tuned right, not just Telstar |
| 14 | Veldt (Gau pickup) | Owner pause: plan Gau — choose-from-8 rages, MP costs, Octopath model | #40 filed with the full plan; design doc next, build v0.7 |
