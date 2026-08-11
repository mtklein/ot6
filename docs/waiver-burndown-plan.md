# Waiver burn-down plan — the remaining suite tests, classified

The work-order source for the conversion waves: each entry names the write
sites, why they exist, and either the input-driven replacement or the
quarantine justification.  gen_* and probe_* files are out of scope here;
gens convert step-by-step with the chain of generated savestates.

Scope: the waiver file's unique suite-test paths yield **60 files**.
8 of the 60 are instruments/evidence scripts, not `@suite` tests:
`bal_dpb`, `bal_mines`, `bal_party`, `battle_assassinate` (self-declared
scaffold), `metrics_battle`, `mines_pace`, `shot_battle_items`,
`shot_field_items`.

## Cross-cutting facts the table depends on

- **`battle_entry`/`first_battle` is a MAGITEK party** (Terra/Biggs/
  Wedge, no Fight, no Magic, no kits).  That fact causes ~30 of the
  60 waivers: every "install CHAR::X into $3ED8 + rewrite $202E command
  rows + clear the magitek status bit" block exists only because the
  input-driven root has no kit.  Each of those is fixed by a
  fixture swap.
- **Real-kit fixtures exist**: Cyan →
  `cyan_defence` / `doma_defended` / `camp_escaped`; Sabin → `vargas_won`
  (L9, Blitz) and `vector_entry` (LOCKE CELES SABIN EDGAR, post-opera
  checkpoint); Edgar → `figaro_cleared`, `vector_entry`; Locke+Terra with
  Magic and live world encounters → `worldmap_narshe`; Celes →
  `celes_freed`, `vector_entry`; Mog → `moogle_defense` (P2 leader);
  Setzer → the terra-returned-v1 checkpoint (`battle_slotsboot` boots it);
  Gau → `gau_joined`; Shadow → `camp_intro` / `camp_escaped`; espers
  really in the bag → `magicite_ifrit_shiva` and `esper_tubes`.
- **Saved-cursor pokes are one shared conversion, and here is the whole
  recipe.**  `$8913/$8917/$891b` (magic), `$895F/$8963/$8967`
  (tools/blitz/bushido), `$892B/$892F/$8933` (rage), esper-list `CURSOR_*` —
  poked in ~14 files to select a list row.  All convert to d-pad edges
  driven off the battle menu-state byte `$7BC2`.  The reference
  implementation is `battle_boost.lua:62-98`; copy its shape rather than
  writing a new one.  What it does, and why each part is there:

  | `$7BC2` | what is up | what to press |
  |---|---|---|
  | `$01` | transitional | nothing — leave the pad alone |
  | `$05` | the top command window | `a` to open the list |
  | `$2A` | a command's list/submenu | `down`/`up` to the row, then `a` |
  | `$38` | target select | `a` for the default target |
  | other | somewhere unexpected | `b` to back out and rebuild |

  Three rules come with it, all measured in that file's own comment.  Drive
  on menu state, never on a fixed button sequence: a fixed sequence lands
  its `down`s in whatever window happens to hold the cursor.  Count the
  `down`s on the pulse edge (`(mf - 1) % 8 == 0`), not per frame, or one
  press repeats.  And when a character other than the one under test holds
  the menu, defer with `x`, which is vanilla's own turn-cycling key, rather
  than acting for them.  Converting a cursor poke is cheap per site, but it
  only removes a waiver line when it is the file's last write, so sequence
  it after the file's other writes rather than before.
- **`H.enterEncounter()` is input-driven** (hold up + A).  Nothing below is
  blocked on the lib.
- **Precedents already landed** that decide several calls: `77bc4f9`
  (danger pin gained nothing; natural roll), `1914283` (incidental
  encounters flee), `cb8e605` (baseline-latch beats scratch-blanking),
  `gen_narshe_battle` (input-driven Kefka, zero writes), `gen_vargas` (real
  Pummel), `battle_hudtrail` (real monster slide on `rapids_start`).

## Redundant (delete, don't convert)

- **battle_bp** → superseded by the converted `battle_boost` (opens-with-1,
  +1 regen, boost consumed/no-regen/pending-cleared all covered).  The one
  uncovered line (`dmg > 250`) is covered more precisely by `battle_fold` and
  `bal_dpb`.  Writes it carried: guard HP := 500 (fight longevity), actor
  bp := 4 / pending := 3 (handed bank).

## Convert-cheap: real input, existing fixture, no new savestate

- **field_navstep** — DONE.  One write: the flag that marked incidental
  encounters' monsters dead during the corridor walk on `vector_sneak`.
  Swapped for `H.fleeBattle()` (L+R), and the navTo beside it now passes
  `playBattles = "flee"` too, which is the half the first pass missed.  The
  subject (navTo release timing on map 242) is unaffected by how the
  interrupting fight ends.
- **battle_kefka** (`savestate=kefka_entry`) — party-HP max pin (likely
  a no-op: the fixture is generated one tile from the trigger with a full
  party, so measure and delete), ATB hurry, Kefka MHP := 1 after two chips.
  `gen_narshe_battle` beats this Kefka on real input; reuse that drive.
- **battle_vargas** (`savestate=vargas_entry`) — HP/MP pins at open,
  Ipooh kill-clamp, Vargas MHP clamp under the phase threshold, cursor
  pokes, $202E command installs.  The party just before that fight
  holds Edgar-with-Tools and Sabin-with-Blitz: read the rows
  instead of installing them; `gen_vargas` kills the boss with a real
  Pummel; cursor → $7BC2 d-pad.  Only the MP pin may need a real check
  first.
- **battle_naturalmp** (`savestate=kolts_cave`) — the same danger pin
  `77bc4f9` deleted on this fixture, plus monster stop/HP-floor.
  The MP survey happens at battle init: read MP in the first ~120 frames,
  then flee.
- **hud_stability** — guard HP := 500 twice, berserk toggled to force
  menu-less actions.  Replace with $7BC2-driven menu + a no-damage action
  (Heal Force), which also removes the HP pin's reason.
- **battle_dmgnum** — bp := 3 handed, guard HP 3000, party HP 900.  Earn
  the bank as `battle_boost` does; choose the non-lethal action; if the
  numeral window is too short, becomes a headroom swap.
- **codex_saveas** (`savestate=worldmap_narshe`) — $021F force, forged
  slot-3 header/codex bytes, zeroing writes that assert an emptiness they
  should read.  Earn the transient page: fight one world encounter, chip
  a shield (the game's own codex write), then save via the Save UI, which
  is already pad-driven.
- **codex_ctx** (`savestate=worldmap_narshe`, moderate) — monster-dead flag
  write → flee;
  the two distinguishable codex pages are producible by play: break enemy
  A → save → break enemy B; assert the difference (baseline-change).
- **battle_reveal_poweron** — already the input-driven half of its pair;
  only the save data is forged.  Boot with a real tracked checkpoint whose
  slot carries a real OT6 codex page (post-opera-v1) and assert New Game
  does not inherit it.  Moves to NEEDS-FIXTURE only if slot 1 specifically is
  required.

## Convert-needs-fixture: a different or new fixture, or a headroom swap

**Group A — "the character is not in the party just before the fight."**
Same conversion everywhere: boot the fixture where the character is
in the party with the real command row, fight a real encounter, drive lists
with a $7BC2-driven d-pad.  Per-file specifics:

- **battle_toolslist / battle_toolsgrey** → `figaro_cleared` /
  `vector_entry` (gen_edgar buys BioBlaster/NoiseBlaster, so real tools
  exist).  Grey knob: spend MP with real casts until the row greys.  This is
  stronger than a poked pool because it proves charge and grey agree.
- **battle_blitzlist / battle_blitzgrey / battle_blitzcursor** →
  `vargas_won` / `vector_entry`.  Learned set = whatever the save
  holds (the `menu_blitzpage_sabin` doctrine); the 2x2-grid geometry
  claim needs ≥4 learned blitzes (Sabin L10+ → `vector_entry`).
  blitzcursor's Config bit is set in the real field Config menu; a fresh
  command-window open is the next turn, not a $7BC2 poke.
- **battle_walletmp** → `vector_entry`.  Poking $3C08 proves only that the
  paint follows a poke; spending MP proves it follows the game.  The 47→123
  switch becomes two casters with different pools.
- **battle_bushidogrey / battle_bushido / battle_bushidoloadout /
  battle_mpcost** → `cyan_defence` / `doma_defended`.  A real katana
  carries the SWDTECH flag; BP-grey is earned +1/action and asserted as
  the bank climbs; the stored loadout word is written by the field
  configurator that `menu_bushidoloadout` drives, so chain field-configure →
  fight → assert battle reads it.  battle_bushido/mpcost need slash-weak
  HP-heavy targets (Vargas 5/5 + slash-weak Ipoohs, or Doma courtyard).
- **battle_divines** → `cyan_defence` + a **leveled-Cyan** savestate.
  Everything converts except Oblivion = tech 8 (L68); either generate a
  leveled Cyan (a grind, but possible with input) or split that one arm
  into a labeled quarantine.  The "make this guard a boss" $3AA1.2 poke
  should become a real boss target instead.
- **battle_clockwork** → `vector_entry` (Setzer) + Cyan fixture.  The
  chip-without-break window = a real 5-gauge boss (Vargas) chipped by a
  real weapon class.
- **battle_steal / battle_stealmp / battle_thief** → real Locke fixtures.
  Steal slots and level are species properties — pick a formation whose
  rare/common slots are populated; Sneak Ring is a real relic equipped in
  the field menu; the $BE RNG arming becomes N sampled attempts and a
  rate assertion (the 3-BP guaranteed arm draws no RNG); Bestow
  arithmetic: drive two characters to known banks by counting actions.
- **battle_runic** → `celes_freed` / `vector_entry`.  Muddle exists
  only to force menu-less casts.  With a real party, pick Magic from the
  menu.  Runic is a real command and must be issued rather than written.
- **battle_dancemp** → `moogle_defense` (the header's claim that Mog is
  unsupported is stale; he leads P2 there).  Dances are terrain-derived
  and real; the cost boundary is earned by dancing twice.
- **battle_rage / battle_gaufight / menu_ragepage** → `gau_joined` (no
  rage-collecting savestate needed: `InitRage` already grants nine rages
  at New Game).  The 8-slot loadout is really written by the
  field Rage page; the Veldt bit is geography, so walk off the Veldt
  instead of clearing $11E4 in a callback; bench-wounding → X-defer.
- **battle_slots** (install half) / **battle_slotsboot** — the Setzer
  install and bp banks convert onto the terra-returned-v1 checkpoint
  (`battle_slotsboot` is already the input-driven model; its only writes
  are the observation-window staging).  slotsboot's fix is target selection:
  a formation that survives three Slot resolutions.  Delete battle_slots
  arms slotsboot already covers (tier latch, forced-benevolent at 3, 3bp
  charged); the forced-icon arms → quarantine, below.
- **battle_magicite** → `magicite_ifrit_shiva` (both stones are in
  the bag).  Equipping is a real field-menu action; re-summon arms become
  second battles; Osmose targets and Slow-immunity are species choices
  (MRF species carry 447-810 MP per the file's own header).
- **battle_subjob** → `magicite_ifrit_shiva` + the level-up fixture.
  Re-point grant assertions at the owned stone's authored spells.
- **battle_levelup** → a "one real fight short of a level" savestate (any
  step in the chain can emit it as a side artifact).  The record-sentinel
  writes are baseline-change detection (`cb8e605`): latch and
  compare, no writes.  HP 1 / MP 0 by real hits and casts.
- **battle_hits** → any real-party fixture (`worldmap_narshe`): Fight is
  on row 0; berserk/Fight-only installs drop out.
- **battle_class** → real party + big-boss headroom.  Four real weapons
  of different classes equipped in the field menu between phases are the
  probe-class swap; class weaknesses and absorbs are species selection.
  Expect a split into 2-3 input-driven tests.
- **battle_dotchip** → the owner found this in real play at Zozo with the
  Bio Blaster: `gen_edgar` buys the tool, the Zozo fixtures regenerate on
  the input-driven chain, poison arrives by using it; the fire-weak control
  is a second species in the same formation.
- **battle_break / battle_reveal (lab half)** → one shared species choice
  (element-weak, HP-heavy; candidates to measure: kolts_cave pool, mines
  pool, the Whelk).  One work order, one fixture decision.
- **battle_breakflash** → a multi-target spell against two 1-gauge
  enemies breaks both on one damage frame (the input-driven arming of the
  double-flash); `regauge` becomes a fresh battle.  Its #63 comment
  records that the pins hid a real bug; prioritize.
- **battle_hudtrack** → `rapids_start`: `battle_hudtrail` already proves
  the entrance slide is a real battlefield move; assert anchor adoption
  against the slide instead of the injected $80C3 coordinate bump.
- **battle_trueknight** → a fixture owning + equipping the True Knight
  relic (field menu makes $3C58 an assertion); near-fatal by real hits;
  bp earned.  Arm 6b (numeral-suppressed backstop) may be a legitimate
  single-arm quarantine if measurement shows no numeral-less covering
  action exists; split it if so.
- **battle_crosslist** → a party with real Magic and Tools
  (`figaro_cleared`/`vector_entry`).  Delete first: L163's "greyed row
  forced selectable", which is the same false surface the grey tests prevent.
- **battle_fold / battle_preview / battle_lateboost** →
  `worldmap_narshe` (real Terra, real Fire/Cure).  The fold's ≥51-MP
  charge is only meaningful against a real pool: "she can afford it once
  and not twice" is the stronger assert.
- **menu_esperdetail** → `magicite_ifrit_shiva`; **menu_esperdetail_tube6**
  → `esper_tubes` (the six stones the set piece grants).  One-line
  fixture swaps.
- **menu_swdtechpage / menu_bushidoloadout** → Cyan fixtures (the headers
  saying no Cyan field fixture exists are stale).  They are not redundant
  with each other: bushidoloadout uniquely owns the packed-word semantics.
  The all-eight phases wait on the learn-ceiling call.
- **menu_blitzpage** → convert zero/partial-learned phases onto
  `vargas_won`; the all-eight phase (L70) waits on the learn-ceiling
  call.  `menu_blitzpage_sabin` already covers realness.
- **metrics_battle / bal_party / bal_mines / mines_pace** (instruments) —
  three shared conversions: (a) the "vanilla arm" ROM patches become a
  second ROM build via OT6_ROM (battle_mpcost's A/B pattern), (b) danger
  zeroing goes, (c) seeded RNG draws become unseeded sampling with more
  battles.  mines_chase.mss is a Jul-27 fixture; regenerate before landing.
- **battle_assassinate** (not in suite) → `camp_intro` (real SHADOW with
  a real Fight).  Good low-risk first proof of the real-kit pattern.
- **shot_battle_items / shot_field_items** (evidence scripts) → a late
  fixture whose bag holds class-covering weapons, or buy from a
  real shop; four classes instead of five is not a coverage loss (the
  assertions live in battle_class/battle_breaktbl).

## Quarantine-candidate

- **battle_reveal phase 1** — masks dirtied inside the Ot6SeedShields
  exec callback.  InitBattle clears $3A20-$3ED3 before every normal
  battle; only a Cmd_20 scene reload or uninitialized RAM presents dirty
  masks, and neither can be produced by player input.  **Measure first**
  whether any reachable formation runs Cmd_20 (Number 128's train chain,
  MRF fights); if one does, this converts to a real multi-phase fight
  instead.  Split the lab half out regardless.
- **battle_slots reel arms** — the rig byte is a single Rand at the first
  A press; no player input selects a reel icon, so the icon-specific arms
  (joker-doom triggering, cursed-icon refusal) cannot be produced on cue.
  Quarantine a much smaller file after deleting the arms real input
  already covers and moving the install onto the checkpoint.
- **bal_dpb** (labeled lab) — a ratio between target states with base
  damage held constant; no reachable encounter holds a species
  simultaneously unbroken/weak/broken for N samples against equalized
  casters.  Keep the waiver, a clear label, and a header ban on quoting its
  numbers as player experience without a live-pool cross-check.

## Dead / deletable writes (free waiver reductions)

- `metrics_battle.lua:867-870` — BUFF_FIRE hard-coded false, BUFF_HP 0.
- `bal_party.lua:1194,:1199-1202` — BUFF_HP/BUFF_CLASS hard-coded 0
  (`:1196-1197` is env-controlled, live).
- `battle_assassinate.lua:96` — pinGuardHp false at every site.

## Two systemic calls — both now decided

1. **The learn-ceiling tier: ruled by owner, 2026-08-10.**  No
   leveled-fixture grind tier.  The bar is area-level real play ("when we
   say we've rebalanced an area, we have played through it in a way that
   is possible for a person with a controller to do"); targeted feature
   questions answered via isolated memory-hack tests are acceptable, and
   as the project expands toward higher-level content we look for
   opportunities to exercise those features organically instead.  The
   true ceiling arms (Cyan tech 8 (L68) in battle_divines /
   battle_bushido / menu_swdtechpage's all-eight phase, and Sabin's eighth
   Blitz (L70) in menu_blitzpage) stay waived as labeled isolation
   arms, to be converted organically later.
   The 8-slot rage loadout is not in that class: `InitRage`
   (field/init.asm:355) grants Gau NINE rages at New Game, so battle_rage
   and menu_ragepage convert against the existing input-driven gau_joined
   with no rage-collecting savestate.
2. **The observation-window doctrine.**  "Monsters STOPped + HP floored +
   death-protected" appears in ~20 files and is the most common
   remaining waiver.  Under the owner's area-vs-mechanism calibration,
   these are per-file judgment: where the observation is a mechanism
   claim (a decode, a renderer), the staging may stay as a labeled
   isolation arm; where it claims play behavior, convert via no-damage
   actions, a real high-gauge boss for headroom, or one observation per
   battle.  Decide per file in the wave rather than writing twenty
   separate doctrines.
3. **HP pinned for measurement headroom: pick a different body, don't
   write HP.**  Settled by a worked case rather than by argument.
   `battle_break` and `battle_reveal` both built the same laboratory on the
   entry-point Guards — fire weakness OR'd in, HP written to 4000, casters'
   level and mag.pwr pinned equal — because a 40-HP Guard with no fire
   weakness cannot show a chip, a break and a recovery.  Both now boot the
   Whelk head instead and write nothing.  The rule the case establishes:
   when a test pins HP so that a measurement fits, the fix is a body that
   already has the HP, the weakness and the gauge; when it pins stats so a
   comparison is fair, the fix is to make the measurement single-source
   (one character, one spell) rather than to equalize several.  The second
   half is strictly stronger than the pin it replaces, because a pin makes
   casters equal on paper while single-sourcing makes the measurement equal
   in fact.

   **What to pick from, measured.**  Decode `monster_prop.dat` (record 32
   bytes; HP at +8 16-bit, level +$10, absorb +23, null +24, weak +25) and
   apply `Ot6ElemAddTbl` (`ot6_break.asm:404+`) and `Ot6ShieldTbl`
   (`ot6_hud.asm`, else the level floor `min(6, 2 + level/8)`);
   `tools/check_boss_rows.py` already parses all four and can be imported.
   The early-game answer is the Whelk head, `$0134`: 1600 HP, authored
   4 shields, authored `OT6_PIERCE`, authored fire weakness, reachable from
   `whelk_entry` with a party that owns Fire Beam and TekMissile — so it
   offers an element axis and a class axis on the same body, which is what
   a "one chip reveals one thing" control needs.  Do **not** reach for this
   stretch's fire-weak trash (leafer, dark wind, hornet, bleary, crawly,
   trilium, vaporite): `ot6_break.asm:354-360` already records that they
   run 33 to 147 HP against a 4x breaking hit and cannot hold a break
   window at all.

   **Driving that fight costs nothing new.**  `battle_whelkwipe.lua:177-210`
   is the field walk and intro dismissal, and the menu policy is
   `whelkbal_run.lua:103-127`: from the settled top command menu, a beam at
   the default target is `A A A` and Heal Force is `A dn dn A A`.  Give
   every character that is not the one under test Heal Force.  That
   self-targets, moves no gauge and heals, which at once keeps the
   measurement single-source, keeps every hit off the shell (whose MegaVolt
   counter is lethal), and removes the reason the party-HP floor existed.

## Deleting the monster-dead flag write: what still blocks it

The last structural #75 item is deleting the shared paths that flag a
mid-route battle's monsters as dead: 7 sites in `lib/ot6_field.lua` and
`M.clearBattle` (`lib/ot6.lua`).  Deleting them also flips the compose-time
runtime write check strict everywhere with no further compose change.

**Status, 2026-08-11: the call-site sweep is done and one blocker remains.**

**1. `M.clearBattle` has one live caller left, and it is deliberate.**  The
earlier count here said one live call (`probe_world.lua:166`) and six files
citing it in prose.  That was wrong: there were two.  `probe_world` is
converted -- it wins its measured encounter with `H.fightBattle(20000)`,
which keeps the reload measurement comparable because the flag write also
ended that fight as a win.  The other is `battle_subjob.lua:490`,
`H.clearBattle(20000)  -- ISOLATION WIN (lib waiver)`, which the file's
header records as a labeled isolation arm under the owner's 2026-08-10
ruling: no fixture sits one real fight short of a level, so that arm keeps
an XP pin and a library win, and converts organically when a
near-threshold fixture exists.  So `M.clearBattle` cannot simply be
deleted.  The choices are to convert `battle_subjob`'s arm D onto a
near-threshold fixture, or to keep the helper as an explicitly-waived
isolation-only helper and delete only the seven navigator sites.  The five
remaining mentions are prose (battle_naturalmp, gen_arvis,
gen_whelk_poweron, probe_input, probe_vargas).

**2. The navigator sites' guard is now unreachable from any live caller.**
The flag write fires only for a caller that passes no `playBattles` option
(`if M.monstersPresent() > 0 and not opts.playBattles`).  Every call to
`navTo`, `advanceStory` and `worldNavTo` in `tools/tests` now passes one.
The two matches a scan still reports are both correct as they stand:
`gen_sabin_train.lua:175` is inside a local `nav()` wrapper that sets
`o.playBattles = "flee"` on the caller's table first, and
`lib/ot6_field.lua:1213-1214` is `M.route` handing `rstep.opts` straight
through (that helper has no callers, and could not work if it did: `local
steps = {}` shadows its own parameter).

**How each site's spelling was decided,** so a reviewer can check it rather
than trust it.  A field map rolls for a random battle only when byte +5 of
its 33-byte `map_prop.dat` record has bit 7 set: `LoadMapProp` copies the
record to `$0520` (`ff6/src/field/map.asm:143-158`) and the field step
handler returns before the roll unless `$0525` is negative
(`ff6/src/field/battle.asm:333-347`).  A map's pool is
`sub_battle_group.dat[map]`, and that group's four formations are the four
words at `rand_battle_group.dat[group*8]`; a formation's monsters are
`battle_monsters.dat` (15 bytes: `+1` present mask, `+2..+7` indices, `+14`
index high bits), and a formation permits a pincer when
`battle_prop.dat` word `[f*4] ^ $00F0` has bit 6 set
(`battle_main.asm:8175-8180` loads it, `:7758-7768` masks it).  Decoding
that chain reproduces the library's own recorded map-98 measurement
(Trilium + Tusker + two Cirpius) exactly, which is what validates it.

  * **encounters disabled on every map the step touches** -- most sites.
    The option is intent only.  These take `"tactical"`, because a goal
    fight is handed back by `opts.spare`/`opts.arrive` before `playBattles`
    is consulted, so the only battle that can reach the option is an
    unscripted surprise, and fighting one beats spending `M.FLEE_CAP`
    frames failing to run from it.  The banquet family is the exception:
    those files take `"flee"` to match `gen_banquet_done`, since
    consistency inside one route is worth more than consistency across the
    sweep when the choice is moot anyway.
  * **corridor travel that really can draw a battle** -- world crossings,
    the Phantom Train, the Magitek Research Facility floors -- takes
    `"flee"`.
  * **`"tactical"` where fleeing is expensive or costs the route
    something.**  Zozo (maps 221/225): several of those formations permit a
    pincer, which raises run difficulty from 2 to 6 per monster
    (`battle_main.asm:15584-15594`), and `gen_zozo5_ramuh` already clears
    the same pool on the same maps with blind A-taps.
  * **`playBattles = true` at exactly one site**, `gen_whelk`.  Map 41
    draws encounters, but the party is the Magitek trio, whose command rows
    carry no Fight, and the tactical driver's fallback for an actor with no
    Fight row is to press X and pass the turn, so no actor would ever act.
    Blind A-taps do end it.  `gen_whelk_poweron`, the maintained sibling on
    the same map with the same party, already passes `true` for this
    reason.

**Frame budgets grew** at the sites that can now be interrupted by a real
battle, since a played-out or fled battle costs ATB rounds where the write
cost none: `gen_zozo3_clock` (run 60000 -> 90000, its two walks), and
`probe_clock`, `probe_train2`, `probe_v07_384toggle`, `probe_v07_385`,
`probe_world`.

**The general rule, which is what this whole item is for:** converting a
test's own flag write does not make its step input-driven if it still calls
a navigator bare, because the library would end a mid-step battle by the
same write.  A conversion is complete only when both halves are covered.
`field_navstep` was the worked example of getting exactly half, and is now
whole.

**What is left:** delete the seven navigator sites, decide
`M.clearBattle`'s fate against `battle_subjob`'s isolation arm, and flip
the runtime write check strict.  Do not delete before re-running the
chain: the sweep was decided by reading the map and formation tables, and
almost none of it has been executed, so a step that silently relied on the
write would surface as a party wipe or a timeout at the deletion and get
the blame for it.
