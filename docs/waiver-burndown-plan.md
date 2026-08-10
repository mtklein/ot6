# Waiver burn-down plan — the remaining suite tests, classified

Produced 2026-08-09 by a read-only classification sweep over every waived
suite-test file (issue #75).  This is the work-order source for the
conversion waves: each entry names the write sites, why they exist, and
either the honest replacement or the quarantine justification.  gen_* and
probe_* files are out of scope here (gens convert leg-by-leg with the
frontier; the probe disposition is a pending owner call on #75).

Scope: the waiver file's unique suite-test paths yield **60 files**.
8 of the 60 are instruments/evidence scripts, not `@suite` tests:
`bal_dpb`, `bal_mines`, `bal_party`, `battle_assassinate` (self-declared
scaffold), `metrics_battle`, `mines_pace`, `shot_battle_items`,
`shot_field_items`.

## Cross-cutting facts the table leans on

- **`battle_doorstep`/`first_battle` is a MAGITEK party** (Terra/Biggs/
  Wedge, no Fight, no Magic, no kits).  That single fact causes ~30 of the
  60 waivers: every "install CHAR::X into $3ED8 + rewrite $202E command
  rows + clear the magitek status bit" block exists only because the
  honest root has no kit.  Every one of those is fixed by a **fixture
  swap**, not by cleverness.
- **Real-kit fixtures now exist and are Aug-9 re-mints**: Cyan →
  `cyan_defence` / `doma_defended` / `camp_escaped`; Sabin → `vargas_won`
  (L9, Blitz) and `vector_doorstep` (LOCKE CELES SABIN EDGAR, post-opera
  anchor); Edgar → `figaro_cleared`, `vector_doorstep`; Locke+Terra with
  Magic and live world encounters → `worldmap_narshe`; Celes →
  `celes_freed`, `vector_doorstep`; Mog → `moogle_defense` (P2 leader);
  Setzer → the terra-returned-v1 anchor (`battle_slotsboot` boots it);
  Gau → `gau_joined`; Shadow → `camp_intro` / `camp_escaped`; espers
  really in the bag → `magicite_ifrit_shiva` and `esper_tubes`.
- **Saved-cursor pokes are one shared conversion.**  `$8913/$8917/$891b`
  (magic), `$895F/$8963/$8967` (tools/blitz/bushido), `$892B/$892F/$8933`
  (rage), esper-list CURSOR_* — poked in ~14 files to select a list row.
  All convert to d-pad edges gated on the menu-state bank `$7BC2` — the
  idiom `battle_boost` uses.
- **`H.enterEncounter()` is honest** (hold up + A).  Nothing below is
  blocked on the lib.
- **Precedents already landed** that decide several calls: `77bc4f9`
  (danger pin bought nothing — natural roll), `1914283` (incidental
  encounters flee), `cb8e605` (baseline-latch beats scratch-blanking),
  `gen_narshe_battle` (honest Kefka, zero writes), `gen_vargas` (real
  Pummel), `battle_hudtrail` (real monster slide on `rapids_start`).

## REDUNDANT (delete, don't convert)

- **battle_bp** → superseded by the converted `battle_boost` (opens-with-1,
  +1 regen, boost consumed/no-regen/pending-cleared all covered).  The one
  uncovered line (`dmg > 250`) lives more precisely in `battle_fold` and
  `bal_dpb`.  Writes it carried: guard HP := 500 (fight longevity), actor
  bp := 4 / pending := 3 (handed bank).

## CONVERT-CHEAP — real input, existing honest fixture, no new mint

- **field_navstep** — one write: kill-bit on incidental encounters during
  the corridor walk on `vector_sneak`.  Swap for `H.fleeBattle()` (L+R).
  The subject (navTo release timing on map 242) is unaffected by how the
  interrupting fight ends.  The single cheapest waiver line in the set.
- **battle_kefka** (frontier=`kefka_doorstep`) — party-HP max pin (likely
  a no-op: the fixture is minted one tile from the trigger with a full
  party — measure and delete), ATB hurry, Kefka MHP := 1 after two chips.
  `gen_narshe_battle` beats this exact Kefka honestly; lift that drive.
- **battle_vargas** (frontier=`vargas_doorstep`) — HP/MP pins at open,
  Ipooh kill-clamp, Vargas MHP clamp under the phase threshold, cursor
  pokes, $202E command installs.  The doorstep party genuinely holds
  Edgar-with-Tools and Sabin-with-Blitz: read the rows instead of
  installing them; `gen_vargas` kills the boss with a real Pummel; cursor
  → $7BC2 d-pad.  Only the MP pin may need a real check first.
- **battle_naturalmp** (frontier=`kolts_cave`) — the identical danger pin
  `77bc4f9` deleted on this very fixture, plus monster stop/HP-floor.
  The MP survey happens at battle init: read MP in the first ~120 frames,
  then flee.
- **hud_stability** — guard HP := 500 twice, berserk toggled to force
  menu-less actions.  Replace with $7BC2-driven menu + a no-damage action
  (Heal Force), which also removes the HP pin's reason.
- **battle_dmgnum** — bp := 3 handed, guard HP 3000, party HP 900.  Earn
  the bank as `battle_boost` does; choose the non-lethal action; if the
  numeral window is too short, becomes a headroom swap.
- **codex_saveas** (frontier=`worldmap_narshe`) — $021F force, forged
  slot-3 header/codex bytes, zeroing writes that assert an emptiness they
  should read.  Earn the transient page: fight one world encounter, chip
  a shield (the game's own codex write), then save via the already-honest
  pad-driven Save UI.
- **codex_ctx** (frontier=`worldmap_narshe`, moderate) — kill-bit → flee;
  the two distinguishable codex pages are producible by play: break enemy
  A → save → break enemy B; assert the difference (baseline-change).
- **battle_reveal_poweron** — already the honest half of its pair; only
  the battery is forged.  Boot with a real tracked anchor whose slot
  carries a real OT6 codex page (post-opera-v1) and assert New Game does
  not inherit it.  Moves to NEEDS-FIXTURE only if slot 1 specifically is
  required.

## CONVERT-NEEDS-FIXTURE — a different/new fixture or a headroom swap

**Group A — "the character does not exist at the doorstep."**  Same
conversion everywhere: boot the fixture where the character is really in
the party with the real command row, fight a real encounter, drive lists
with $7BC2-gated d-pad.  Per-file specifics:

- **battle_toolslist / battle_toolsgrey** → `figaro_cleared` /
  `vector_doorstep` (gen_edgar BUYS BioBlaster/NoiseBlaster — real tools
  exist).  Grey knob: spend MP with real casts until the row greys —
  stronger than a poked pool (proves charge and grey agree).
- **battle_blitzlist / battle_blitzgrey / battle_blitzcursor** →
  `vargas_won` / `vector_doorstep`.  Learned set = whatever the save
  holds (the `menu_blitzpage_sabin` doctrine); the 2x2-grid geometry
  claim needs ≥4 learned blitzes (Sabin L10+ → `vector_doorstep`).
  blitzcursor's Config bit is set in the real field Config menu; a fresh
  command-window open is the next turn, not a $7BC2 poke.
- **battle_walletmp** → `vector_doorstep`.  Poking $3C08 proves the paint
  follows a poke; SPENDING MP proves it follows the game.  The 47→123
  switch becomes two casters with different pools.
- **battle_bushidogrey / battle_bushido / battle_bushidoloadout /
  battle_mpcost** → `cyan_defence` / `doma_defended`.  A real katana
  carries the SWDTECH flag; BP-grey is earned +1/action and asserted as
  the bank climbs; the stored loadout word's honest writer is the field
  configurator `menu_bushidoloadout` drives — chain field-configure →
  fight → assert battle reads it.  battle_bushido/mpcost need slash-weak
  HP-heavy targets (Vargas 5/5 + slash-weak Ipoohs, or Doma courtyard).
- **battle_divines** → `cyan_defence` + a **leveled-Cyan** mint.
  Everything converts except Oblivion = tech 8 (L68); either mint a
  leveled Cyan (a grind, not an impossible input) or split that one arm
  into a labeled quarantine.  The "make this guard a boss" $3AA1.2 poke
  should become a real boss target instead.
- **battle_clockwork** → `vector_doorstep` (Setzer) + Cyan fixture.  The
  chip-without-break window = a real 5-gauge boss (Vargas) chipped by a
  real weapon class.
- **battle_steal / battle_stealmp / battle_thief** → real Locke fixtures.
  Steal slots and level are species properties — pick a formation whose
  rare/common slots are populated; Sneak Ring is a real relic equipped in
  the field menu; the $BE RNG arming becomes N sampled attempts and a
  rate assertion (the 3-BP guaranteed arm draws no RNG at all); Bestow
  arithmetic: drive two characters to known banks by counting actions.
- **battle_runic** → `celes_freed` / `vector_doorstep`.  Muddle exists
  only to force menu-less casts — with a real party, pick Magic from the
  menu; Runic is a real command and must be issued, not written.
- **battle_dancemp** → `moogle_defense` (the header's "Mog is not in the
  supported frontier" is STALE — he leads P2 there).  Dances are
  terrain-derived and real; the cost boundary is earned by dancing twice.
- **battle_rage / battle_gaufight / menu_ragepage** → `gau_joined` + a
  **rage-collection mint** (the Veldt grind `gen_sabin_gau` already
  performs — known shape).  The 8-slot loadout's honest writer is the
  field Rage page; the Veldt bit is geography — walk off the Veldt
  instead of clearing $11E4 in a callback; bench-wounding → X-defer.
- **battle_slots** (install half) / **battle_slotsboot** — the Setzer
  install and bp banks convert onto the terra-returned-v1 anchor
  (`battle_slotsboot` is already the honest model; its only writes are
  the observation-window staging).  slotsboot's fix is target selection:
  a formation that survives three Slot resolutions.  Delete battle_slots
  arms slotsboot already covers (tier latch, forced-benevolent at 3, 3bp
  charged); the forced-icon arms → quarantine, below.
- **battle_magicite** → `magicite_ifrit_shiva` (both stones honestly in
  the bag).  Equipping is a real field-menu action; re-summon arms become
  second battles; Osmose targets and Slow-immunity are species choices
  (MRF species carry 447-810 MP per the file's own header).
- **battle_subjob** → `magicite_ifrit_shiva` + the level-up fixture.
  Re-point grant assertions at the owned stone's authored spells.
- **battle_levelup** → a "one honest fight short of a level" mint (any
  chain leg can emit it as a side artifact).  The record-sentinel writes
  are textbook baseline-change detection (`cb8e605`) — latch and compare,
  no writes.  HP 1 / MP 0 by real hits and casts.
- **battle_hits** → any real-party fixture (`worldmap_narshe`): Fight is
  on row 0; berserk/Fight-only installs drop out entirely.
- **battle_class** → real party + big-boss headroom.  Four real weapons
  of different classes equipped in the field menu between phases ARE the
  probe-class swap; class weaknesses and absorbs are species selection.
  Expect a split into 2-3 honest tests.
- **battle_dotchip** → the owner FOUND this in real play at Zozo with the
  Bio Blaster: `gen_edgar` buys the tool, the Zozo fixtures re-mint on
  the honest chain, poison arrives by using it; the fire-weak control is
  a second species in the same formation.
- **battle_break / battle_reveal (lab half)** → one shared species choice
  (element-weak, HP-heavy; candidates to measure: kolts_cave pool, mines
  pool, the Whelk).  One work order, one fixture decision.
- **battle_breakflash** → a multi-target spell against two 1-gauge
  enemies breaks both on one damage frame (the honest arming of the
  double-flash); `regauge` becomes a fresh battle.  Its own #63 comment
  admits the pins hid a real bug — prioritize.
- **battle_hudtrack** → `rapids_start`: `battle_hudtrail` already proves
  the entrance slide is a real battlefield move; assert anchor adoption
  against the slide instead of the injected $80C3 coordinate bump.
- **battle_trueknight** → a fixture owning + equipping the True Knight
  relic (field menu makes $3C58 an assertion); near-fatal by real hits;
  bp earned.  Arm 6b (numeral-suppressed backstop) may be a legitimate
  single-arm quarantine if measurement shows no numeral-less covering
  action exists — split it if so.
- **battle_crosslist** → a party with real Magic AND Tools
  (`figaro_cleared`/`vector_doorstep`).  Kill first: L163's "greyed row
  forced selectable" — the same lying surface the grey tests prevent.
- **battle_fold / battle_preview / battle_lateboost** →
  `worldmap_narshe` (real Terra, real Fire/Cure).  The fold's ≥51-MP
  charge is only meaningful against a real pool: "she can afford it once
  and not twice" is the stronger assert.
- **menu_esperdetail** → `magicite_ifrit_shiva`; **menu_esperdetail_tube6**
  → `esper_tubes` (the six stones the set piece grants).  One-line
  fixture swaps.
- **menu_swdtechpage / menu_bushidoloadout** → Cyan fixtures (the "we do
  not mint a Cyan field fixture" headers are STALE).  NOT redundant with
  each other: bushidoloadout uniquely owns the packed-word semantics.
  The all-eight phases wait on the learn-ceiling call.
- **menu_blitzpage** → convert zero/partial-learned phases onto
  `vargas_won`; the all-eight phase (L70) waits on the learn-ceiling
  call.  `menu_blitzpage_sabin` already covers realness.
- **metrics_battle / bal_party / bal_mines / mines_pace** (instruments) —
  three shared conversions: (a) the "vanilla arm" ROM patches become a
  second ROM build via OT6_ROM (battle_mpcost's A/B pattern), (b) danger
  zeroing goes, (c) seeded RNG draws become unseeded sampling with more
  battles.  mines_chase.mss is a Jul-27 fixture — re-mint before landing.
- **battle_assassinate** (not in suite) → `camp_intro` (real SHADOW with
  a real Fight).  Good low-risk first proof of the real-kit pattern.
- **shot_battle_items / shot_field_items** (evidence scripts) → a late
  fixture whose bag really holds class-covering weapons, or buy from a
  real shop; four classes instead of five is not a coverage loss (the
  assertions live in battle_class/battle_breaktbl).

## QUARANTINE-CANDIDATE

- **battle_reveal phase 1** — masks dirtied inside the Ot6SeedShields
  exec callback.  InitBattle clears $3A20-$3ED3 before every normal
  battle; only a Cmd_20 scene reload or uninitialized RAM presents dirty
  masks, and neither is a button.  **Measure first** whether any
  reachable formation runs Cmd_20 (Number 128's train chain, MRF fights)
  — if one does, this converts to a real multi-phase fight instead.
  Split the lab half out regardless.
- **battle_slots reel arms** — the rig byte is a single Rand at the first
  A press; no player input selects a reel icon, so the icon-specific arms
  (joker-doom gating, cursed-icon refusal) cannot be produced on cue.
  Quarantine a much smaller file after deleting the honestly-covered arms
  and moving the install onto the anchor.
- **bal_dpb** (labeled lab) — a ratio between target states with base
  damage held constant; no reachable encounter holds a species
  simultaneously unbroken/weak/broken for N samples against equalized
  casters.  Keep waiver + loud label + a header ban on quoting its
  numbers as player experience without a live-pool cross-check.

## Dead / deletable writes (free waiver reductions)

- `metrics_battle.lua:867-870` — BUFF_FIRE hard-coded false, BUFF_HP 0.
- `bal_party.lua:1194,:1199-1202` — BUFF_HP/BUFF_CLASS hard-coded 0
  (`:1196-1197` is env-gated, live).
- `battle_assassinate.lua:96` — pinGuardHp false at every site.

## Two systemic calls — both now decided

1. **The learn-ceiling tier: RULED, owner, 2026-08-10.**  No
   leveled-fixture grind tier.  The bar is AREA-level honesty ("when we
   say we've rebalanced an area, we have played through it in a way that
   is possible for a person with a controller to do"); targeted feature
   questions answered via isolated memory-hack tests are acceptable, and
   as the project expands toward higher-level content we look for
   opportunities to exercise those features organically instead.  So the
   true ceiling arms — Cyan tech 8 (L68) in battle_divines /
   battle_bushido / menu_swdtechpage's all-eight phase, Sabin's eighth
   Blitz (L70) in menu_blitzpage — stay waived as labeled isolation
   arms, converted organically later.
   **CORRECTION that shrank the class:** `InitRage` (field/init.asm:355)
   grants Gau NINE rages at New Game — the 8-slot rage loadout was never
   a ceiling case.  battle_rage and menu_ragepage convert against the
   existing honest gau_joined with no collection mint.
2. **The observation-window doctrine.**  "Monsters STOPped + HP floored +
   death-protected" appears in ~20 files — the single most common
   remaining waiver.  Under the owner's area-vs-mechanism calibration,
   these are per-file judgment: where the observation is a MECHANISM
   claim (a decode, a renderer), the staging may stay as a labeled
   isolation arm; where it claims play behavior, convert via no-damage
   actions, a real high-gauge boss for headroom, or one observation per
   battle.  Decide per file in the wave, not twenty separate doctrines.

## Probe disposition (dispatcher call, delegated by the owner 2026-08-10)

Keep a named handful, retire the rest: settled one-shot probes are
deleted (their measurements live in docs/commits, and most were taken
against poked states — re-derivation against the honest chain is the
right move if a number ever matters again); instruments that docs or
current investigations actively point at stay (the stall/trench/banquet
reproduction probes, probe_lockekit, the pad-input save template
probe_banquet_timer_save, and kin — the retirement wave assembles the
keep-list from actual references, not memory).
