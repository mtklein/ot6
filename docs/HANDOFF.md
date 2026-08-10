# Handoff — state of play

Last refreshed 2026-08-09 (the honesty section rewritten wholesale that
day); before that 2026-08-06; rewritten 2026-07-30, replacing the
2026-07-27 version wholesale. That one
described v0.6-era state and three releases had shipped since; a handoff that
is behind is worse than no handoff, so this file is the exception to
CONTRIBUTING's "append a dated correction" rule — **rewrite it when it goes
stale, and say when you did.** Everything else in `docs/` gets a correction
appended instead.

Update this file when you land something that changes the picture; it is
meant to be the one place that says where things are.

Start with [README.md](../README.md) for what OT6 is,
[CONTRIBUTING.md](../CONTRIBUTING.md) for the house rules, and
[ROADMAP.md](ROADMAP.md) for the release plan. This file is the delta: what is
true right now and what will cost you a day if you do not know it.

## Where the project is

**v0.9 is released** — "Locke, and the break economy". Four releases have now
shipped without moving the playable frontier (v0.6 → v0.7 → v0.8 → v0.9), and
that is deliberate, not drift: the loop is *owner plays → files findings →
themed release folds them in*, recorded in ROADMAP as the chosen cadence.
Milestones are named for their theme. The frontier push to the end of the
World of Balance is **v0.10**'s job.

0.9 is followed by **0.10**, not 1.0. The end of WoB is about halfway through
the game and the World of Ruin is unstarted, so 1.0 — the line where a
player's save becomes something they are entitled to keep — is far off.

**The frontier still stands at Terra's return (v0.6's line).** The Sealed Gate
route is minted through the airship crash — anchors F through I with measured
entry/exit contracts — and the banquet is fully decoded with its score tier
settled at ≥67. Legs J–K remain.

What shipped since the last handoff, in one line each:

- **v0.7** — the clockwork HUD sync, the in-battle MP wallet, Dance's MP
  cost, SwdTech's ≥1-BP floor (#38) and its page fix, Gau's Ochette kit.
- **v0.8 — "the economy bites"** — every kit price recalibrated to vanilla's
  own ruler (a spell costs 8–20% of the pool at the level it arrives, a
  number this design had never measured), ultimates anchored at 99 (which is
  vanilla's own dearest spell, Quick), the break flash and sound, Gau's Fight
  with Leap sharing the Fight row, magicite as gear packages in FF6's own
  two-byte stat encoding, Steal at 4, and three menu pages that had been
  lying to the player since v0.5.
- **v0.9 — "Locke, and the break economy"** — Locke's thief submenu (Steal /
  Filch / Bestow, and Steal's price finally visible), boost-folded spells
  charging the tier's real MP (#64), boosted Runic buying *duration* with
  Celes acting through the stance (#59), the broken-shield glyph redrawn as
  an X, a tagged-out monster's break timer no longer freezing, element icons
  on the field ability pages (#53), and the poison-DOT chip measured and
  pinned (#60).

## The honesty program (#75) — the current all-hands effort

**Rewritten 2026-08-09 (end of the second session that day), replacing the
2026-08-06 strata wholesale** — the blocker narrative it carried was three
findings out of date, and two of its diagnoses had been measured wrong.

**The directive (owner, 2026-08-03), unchanged:** tests and fixture mints
may press buttons and read memory, NEVER write emulated game state ("if you
are not playing actual game states that have been reached through actual
game choices, you are just wasting time pretending").  The bar is
PLAYABILITY — a player's inputs could do this, TAS-style margins fine —
with balance observations logged as data for the post-1.0 balancing era,
never treated as blockers.  Fault-injection mechanism tests survive as a
loudly-labeled quarantine (owner ruling; the label template is
battle_loadgate, and the three owner-named cases carry it).  The running
record is issue #75; the rule leads tools/tests/README.md's "Writing a
test".

### Where the chain stands (2026-08-09, branch claude/issue-75-9a89a6)

**Every gameplay leg of the v0.3–v0.6 route is converted.**  Power-on
through the airship crash (anchor I) now runs on inputs and reads alone:
the Whelk, Marshal, Ultros, Vargas, TunnelArmr, Kefka, Dadaluma, the gate
soldier, the Phantom Train (#74 — honest win, medic doctrine, margin
characterized on that issue), Ifrit/Shiva, Number 024, the tube-room set
piece, and Number 128 (LOCKE+EDGAR+SABIN per the owner rule, blades'
regeneration measured, split heal policy 75% trash / 55% boss).  The
banquet (legs J–K) is being measured feasibility-first as of this writing;
gau_joined's post-join Veldt walk is the one remaining red gameplay mint.

**Both 2026-08-09-morning frontier blockers are closed, and both
diagnoses were wrong in instructive ways:**

- `sfigaro_escape` was never the gate soldier: the park was on **map 87**
  (same (41,43) coordinates, different map — the nav heartbeat printed no
  map id), a random encounter dying under `honest=true`'s blind-A branch.
  The soldier's choke is east of the whole escape route.  Five lib-level
  fixes came out: `opts.fleeCap` (cave pincers can't be fled; the
  1800-frame default killed the pair silently), `opts.healer` on the
  fight driver (an all-medic pair heal-locks), rows re-dealt per leg
  (persistent state — solo-LOCKE's back row was backwards for the pair),
  the map-70 recovery spring at (47,29) (boss entered full for free), and
  CELES armed at boot (equipment_waivers.txt carries the celes_freed
  story-moment line).
- `train_done` was never damage: the honest chain reaches the fight with
  identical combat stats to the old winning lineage and a 9,000-gil
  poorer purse (flee discipline earns nothing; the ghost merchant list is
  now a hard budget).  The win needed TRIAGE — Cyan full-time medic <75%,
  Sabin self-preserving <65%, Shadow backing up <45% — and 5 chips 6→1.
  The break never completes; that structural margin is logged on #74.

**Infrastructure landed the same day:**

- **The runtime write gate (plan item 4)**: compose.py swaps the global
  `emu` for a write-refusing proxy in every composed script whose file
  has zero waivers; the lib keeps the confined raw handle only while its
  own waivers survive, so deleting the lib kill-bit flips everything
  strict with no further compose change.  `__OT6_EMU_RAW` is a forbidden
  static token.  Verified both directions under Mesen.
- **docs/waiver-burndown-plan.md**: all 60 remaining waived suite tests
  classified with per-file work orders (1 redundant — deleted, 9
  convert-cheap — in progress, ~35 fixture swaps, 2.5 quarantine).  The
  headline: the honest root fixture is a kit-less MAGITEK party, and that
  one fact causes half the remaining waivers.  Two systemic calls pend:
  a leveled/collected fixture tier (5 files), and an observation-window
  doctrine (~20 files).
- Waivers **318 → 123** across 2026-08-09/10, all shrink, checker green
  at every merge; write sites 1617 → 762.  The probe retirement executed
  (owner-delegated): 73 settled one-shots deleted, 26 kept by reference.
- **A FALSE GREEN LIVED IN THE HARNESS UNTIL 2026-08-10 -- read this
before trusting any pre-fix green.**  `run.sh` decided pass-vs-fail with
`grep '^\[ot6\] PASS'`, a PREFIX.  Nine converted tests log
`H.log("PASSED...")` lines (battle_thief, battle_blitzlist/grey/cursor,
battle_bushido, battle_bushidoloadout, battle_dancemp, battle_crosslist,
battle_rage), so any of them KILLED BY THE WALL-CLOCK CAP partway through
matched the pass pattern and was scored green -- reproduced directly as
`testrunner exit: 255 (verdict: 0)`.  Fixed: PASS_RE/FAIL_RE anchor on
the parenthesis and colon only the real verdicts carry, one definition
feeds every consumer, and `run.sh --verdict-selftest` (nine cases, the
regression verbatim, fail-before proven) is wired into `make test`.  A
reap now also RETRIES itself (OT6_REAP_RETRIES, default 1) -- reaps are
non-verdicts and runs are isolated, so that is safe; a real FAIL is
never retried.
**OPEN, AND IT IS THE TOP ITEM: those nine tests have NOT been re-run
under the fixed harness.**  Their greens were reported by agent sessions
using the broken parser.  Nothing proves they were reaped -- each agent
quoted a terminal `PASS (frame N)`, which a reaped run cannot produce --
but "probably fine" is not this program's standard.  Re-run all nine and
record the frames.  THREE ARE DONE (2026-08-10, under the fixed
harness, terminal verdicts, zero reaps): battle_bushidoloadout f649,
battle_crosslist f1161, battle_blitzlist f1530.  Six remain:
battle_bushido, battle_blitzcursor, battle_blitzgrey, battle_thief,
battle_dancemp, and battle_rage (the last is the unmerged WIP).

**2026-08-10 additions**: five batteries re-cut through the real Save
  UI (post-opera + boundaries B-E); the fight driver casts real attack
  magic (opts.magic); H.cond re-asks its predicate; the banquet and
  moogle_defense graph edges are live (114 states); ~35 suite tests
  converted by fixture-swap waves (see git log wt/menu-family,
  wt/mech-family, wt/convert-cheap).
- **RESOLVED 2026-08-10 — the Cranes were never a balance wall** (the
  ruling request is withdrawn): the "honestly unwinnable" verdict was a
  LOADOUT bug — `H.equipOptimum` had armed LOCKE and EDGAR with Thunder
  Blades (lightning), and the Left Crane *absorbs* lightning, so every
  Fight healed the boss and charged its Giga Volt counter.  The vanilla
  playbook wins attempt 1 of the standard ladder (probe_cranes_water,
  PASS f19772): BISMARK/SHIVA/CARBUNKL worn through the real Skills
  menu (Sea Song IS obtainable water — the "no water access" premise
  was false, $1A69 reads $EF at boundary E), daggers swapped in through
  the real Equip menu (pierce = the Cranes' class weak, element-clean),
  back rows, SETZER-only medic, focus-fire the Left.  Lib grew
  equipEsper/equipWeapon/opts.summon/opts.focus/opts.tools for it.
  Historical wipe record: gen_terra_returned_anchor f7d32da +
  probe_cranes_wedge (one retracted wrong verdict lives there — the
  Game Over continue-flow read as a completing scene; trust f7d32da,
  not cc2ce35).  The terra-returned re-cut and the chained tail are ALL
  CUT on the honest lineage the same day, each through the real Save UI
  with sealed mechanical provenance: terra-returned-v1 (PASS f52308, 21
  fields), narshe-mission-v1 (f10369, 27), gate-cave-save-v1 (f14754,
  22), vector-crash-v1 (f28613, 30), and banquet-done-v1 (f52694, 40
  fields; the honest 70-point tier reproduced exactly -- window 21 +
  dinner 49 -- with the >=77/>=90 reward negatives verified).

### Doctrine (measured; do not re-derive)

- **fieldCare** drives the real Item→use→target windows; A on the field
  item list PICKS A SLOT UP, only a second A on the same slot uses it.
  Its world-map exit is BROKEN (careBackOnMap's witness passes a moment
  that isn't "world module running") — care on the field, not the world,
  until fixed.  Its exit also reads a one-frame transient (can leave the
  menu open); a debounce wants the next planned lib-staling change.
- **honest="flee" vs "tactical" vs true**: fleeing is standing still
  while the formation takes free rounds; blind-A `honest=true` is a
  foot-gun that stalls or wipes on any leg that can draw an encounter
  (deprecation pending).  `M.FLEE_CAP` default 1800, per-call
  `opts.fleeCap` (the escape route uses 420).  Cave pincer formations
  cannot be fled at all — FF6's own rule.
- **Rows**: `$B3 = $FF` for every command and only the weapon swing
  clears it — Tools, Magic, Blitz, SwdTech, Throw, Steal are row-exempt.
  Where damage is break-driven, back row wins; where the chipper is a
  weapon swing, it loses (South Figaro vs Phantom Train, both measured).
  Rows are persistent state — set them per leg on purpose.
- **The equip audit** (tools/audit_equipment.py, a make-test gate with
  its own shrink-only story-waiver list): any red leg gets checked
  against it BEFORE being called balance.  LOCKE and CELES fought the
  entire measured WoB bare-handed until 2026-08-09.  The audit currently
  exits 1 on ~33 stale downstream fixtures that burn down with the
  re-mint.
- **A party wipe must say so**: the navigators' M.partyWiped() canary
  misses IN-BATTLE wipes ($1600 keeps pre-battle HP) — a battle-module
  witness ($3BF4 under battleLoadStarted()) is the filed fix.  Three
  wipes have now impersonated stuck navigators.
- **Retry ladders are 3 attempts, phase-spread by 37 frames** (battle RNG
  seed = frame phase at init).  Widening a ladder until it gets lucky is
  the #74 mistake; a ladder that loses all three reports a finding.

### What remains before #75 may close

0. **Re-run the nine PASSED-logging tests under the fixed harness**
   (above).  Cheapest real check available and it gates trusting today's
   conversion waves.
1. **The full root-first re-mint under the new lib** — the sfigaro-escape
   merge's lib promotion deliberately staled ~106/109 stamps by hash;
   `make frontier NINJAFLAGS="-k 0"` is the next dispatcher action, and
   its result decides the frontier claim.  A first attempt ran
   2026-08-10 and was STOPPED at edge 66 of 149 to end the session
   cleanly; it left 30 of 111 fixtures fresh and reported ZERO reaps.
   Two real failures in that partial run, both honest ladders losing
   three attempts on freshly re-minted upstreams -- `magicite_ifrit_shiva`
   (battle 70) and `n128_won` (the minecart ride).  Both legs passed when
   minted individually by their agents, so the suspicion is upstream
   party/economy drift now that the whole chain is honest, not the
   drives.  That is the first thing the next full run will re-answer.
2. The banquet feasibility verdict (in flight), gau_joined's post-join
   ladder (in flight), and the convert-cheap test wave (in flight).
3. **Re-cut all legacy battery anchors through the real Save UI** — now
   the dominant remaining waiver class on the route (the Save-UI poke
   blocks in gen_gate_cave_save / gen_vector_crash / the anchor-cutter
   gens keep their waivers deliberately until this line executes).
4. The remaining suite-test conversions per docs/waiver-burndown-plan.md,
   including the two systemic calls it names.
5. **Delete the shared kill-bit paths** from lib/ot6_field.lua and
   H.clearBattle once no leg rides them — which flips the runtime write
   gate strict everywhere automatically.
6. Reduce the waiver file to the quarantine roster only; run the complete
   test and frontier gates; only then represent the program as complete.

**`make test` stops at its own `--check-states` gate while the frontier
is mid-re-mint — that is the gate working, not a failure.**

**Traps this program has already paid for (don't rediscover):**
capture-calm does NOT imply reload-calm — every mint reloads its own
capture and verifies; a stale seeded fixture reads exactly like a product
bug (`--check-states` first); the battle Item cursor is a SUM (`$8947`
scroll + `$894F` row); command row zero is not universally Fight;
concurrent worktree suites can SIGTERM each other's Mesen runs (stagger
heavy gates, `nice` everything, one heavy gate at a time per machine).

## Open work, in the order I would take it

Finish #75 before taking this normal product-work list; the honesty section
above is the authoritative resume order while that program remains open.

1. **#67 — de-fragilise `battle_trueknight` phase 6a.** This is the top of
   the list because it *blocks* #66. 6a currently fails on essentially any
   growth of bank `$C2`'s per-frame battle path, proven with a five-bare-NOP
   control that reproduces the failure byte for byte. It pins delivery via
   the numeral frame, which a shifted frame budget flips. Assert "the pip is
   delivered on the numeral frame or the backstop, and never dropped" —
   **do not simply widen the tolerance until it passes**, which would delete
   the canary the test exists to be.
2. **#66 — a Broken monster still acts.** Confirmed and measured: 103
   executions with the broken timer up in one battle-70 run, including 7
   casts of Fire by a Broken Ifrit, ~600 party HP inside a single break
   window. `Ot6Gate` is fine (consulted 360 times, correctly refused 50);
   counterattacks and pre-queued actions never reach it. The fix
   (`Ot6MayAct`, 103 → 2) is written, measured, and preserved on
   `wt/ifritbreak` at `945b9ed`; re-apply by reverting `8d8a570`. Its
   placement inside `CheckRetal` is load-bearing — gating at the top of that
   routine **deletes the Ifrit/Shiva recognition scene**, and
   `battle_brokendeath.lua` (already on `main`) guards that.
3. **#54 — multi-hit as a real dial.** The audit landed and the answer was
   worse than expected: across all 256 `MagicProp` + 256 `ItemProp` records
   there are **exactly three** multi-hit abilities — Quadra Slam ×4, Quadra
   Slice ×4, Empowerer ×2. Pummel hits once. Bum Rush hits once. Cyan is the
   only character in the game with a multi-hit ability. `design/multi-hit.md`
   §10 is the literal build list; `tools/audit_multihit.py` re-derives the
   enumeration on every run and exits nonzero if it goes stale.
4. **The break window wants a number.** `OT6_BREAK_TICKS = $10`
   (`ot6_break.asm:1`) measures **2159 frames ≈ 36 seconds** on Ifrit &
   Shiva, where `break-impl.md` step 3 specified "~1.5 turn-cycles". Named
   as a known gap in the v0.9 release notes. This is a balance call, not a
   bug fix — and nobody has measured a boss's turn cadence against the
   window, so "many boss turns" is still an inference from the frame count.
5. **Cut anchors B–F and convert the legs** — the remaining #25 payoff.
   `design/save-points-vector.md` §5 maps the band onto six boundaries; each
   needs a gen that drives to the save point, saves through the real UI, and
   exports the battery payload (the `gen_post_opera_anchor` pattern). In the
   graph, converting a leg is `prev=` → `anchor=` on one line. **Every anchor
   must be minted through the game's own save routine, never synthesised.**
6. **#68 / #69 — menu surfaces.** Locke's thief page has no field Skills row
   (hard seven-row limit); the field Magic list still shows no element icons
   even though the field font now carries them.

**Settled, do not re-litigate:** Sketch stays unfixed by explicit owner
decision (reaffirmed 2026-07-28; #28 briefly made it a v0.8 gate and was
itself reversed). The FF3-US translation is our vocabulary in prose and on
screen (owner decision 2026-07-29). Before 1.0, saves are not
forward-compatible and we do not build migration machinery. CONTRIBUTING
carries all three with their history.

## The things that will cost you a day

**1. Module WRAM ownership lies to you — and so did this trap's first
draft.** `$7E3BF4` is the party battle-HP table only while the battle module
owns that RAM. `$021f` was once reported here as overlaid by the world module
after any menu close; the #29 audit (2026-07-28,
`research/codex-context-audit.md`) disproved that mechanism — the cell has
exactly four writers, all menu lifecycle, and the overlaid values came from a
test forcing `ZMENUSTATE` mid-flow, leaving corrupted menu tasks running.
Both lessons stand: ask which module owns a `$02xx` cell before trusting it,
verify by instrumenting (block moves are invisible to Mesen write callbacks —
sample, don't watchpoint), and witness persistent facts through SRAM
(`$307ff0`, the codex pages) when a context-free channel exists.

**2. Cycle budgets are PER SITE, and only one site has a measured number.**
`Ot6BgHud_ext` runs from `WaitFrame` immediately after `WaitVblank` returns,
once per battle frame, and has under 80 cycles of slack — possibly under 20.
Measured 2026-07-29 with bare-NOP controls carrying no feature at all: 12
NOPs pass, 80 NOPs fail, and the penalty **saturates** (20 and 110 cycles
both cost the same 163 frames). The symptom is not a crash or a wrong result
— it is everything running ~10% slower, which flips timing-sensitive tests
elsewhere and looks like their bug. Gate work there INLINE at the call site;
a `jsr` into a proc that early-outs is already over the line.

**The scoping correction (2026-07-30, #67): 12 NOPs being safe *there* does
not make 12 NOPs safe anywhere.** The same bare-NOP control in bank `$C2`'s
**action** path fails at **five** NOPs, so that path's margin is under 10
cycles. But `$C2` growth per se is not the trigger: v0.9 added four new `$C2`
call sites (`battle_main.asm:514`, `:3409`, `:4152`, `:14652` plus
`Ot6RecheckMagic` at `:14715`, ~49 bytes by a static diff count) and
`battle_trueknight` 6a stayed at its passing 1635 frames with no partial
degradation. **Hypothesis, UNVERIFIED:** what costs is per-battle-*frame*
code, not per-action or per-menu-redraw code. Nobody has run the NOP control
at those four v0.9 sites, and that is the experiment that would settle it.
The full record is the block comment over `OT6_BRKLIVE` in
`ff6/src/battle/ot6_memory.inc`. (Distinct from the vblank-TRANSFER budget,
which is about VRAM words, not cycles.)

**3. `H.sym` resolves a duplicate symbol name silently wrong.**
`parse_dbg_syms` (`tools/tests/lib/compose.py:218-250`) walks `ff6-en.dbg`
taking **the first** `type=lab` record for each wanted name and then skips
that name forever (`if name in out: continue`, `:241`). `ExecCmd` is defined
twice — `$C09B1B` and the battle one at `$C213E6` — so a probe that hooked
`ExecCmd` got the wrong module's address, its instrumentation window never
closed, and every later event was misattributed. **Silently.** This cost an
investigation during #60. Before you hook a symbol by name, check how many
label records in the `.dbg` carry it; if more than one, use the address
directly or attribute by something else (that probe switched to same-frame
attribution cross-checked against the record's own byte signature).

**4. A mismatched ROM/fixture pair presents as "timeout waiting for main
menu".** Savestates are genuinely ROM-coupled. When a fixture was minted from
a different ROM than the one under test, the failure you see is a menu that
never opens — nothing says "stale state". Recorded in `88129cb`, where
`arvis_wake` had to be re-minted from each purpose-built ROM to run a
fail-before/pass-after pair. If a menu drive times out and you have recently
changed ROM-affecting source, re-mint before you debug the menu.
`tools/worktree-setup.sh` prints the matching warning when it seeds states
minted on a different branch — read it; the same class of confusion cost a
full investigation on 2026-07-29.

**5. NPC record order is NPC identity.** Event scripts address NPCs as
{map, index-within-block}, so a record inserted ahead of an existing NPC
renumbers everything after it — the first 273 save-sparkle attempt shifted
NUMBER_024 to index 1 and the post-battle cleanup cleared the sparkle
instead. **Append, never insert.** The mint caught it two legs downstream,
which is the system working.

**6. `navTo` lands at rest (#22); a tile that takes the party away is entered
with a held press, not a `navTo` whose goal it is.** Position samples are
only valid at rest on a tile (`tools/tests/lib/ot6_field.lua:459`, `:616`).
Generators relying on the old mid-glide handoff still surface occasionally.

**7. `event_main.asm` is a dump of separately-addressed scripts.** Adjacency
means nothing. Party composition is runtime state: read `$1850` at a fixture.
`bosses-wob.md` is authoritative on party composition.

**8. `LoadMagicProp` fills one shared buffer** — freeze the rest of the party
when measuring an ability, or an ally's action mid-window reads as "the
summon was free". Documented at `freezeOthers`
(`tools/tests/battle_magicite.lua:232`).

**9. The 600-second reap starves agents against each other, not against the
owner.** `nice` fixes contention with the owner's game; it does not fix
Mesen's testrunner wall-clock kill. The signature is several mints failing
`code=255` at once while the same mints pass in isolation. Lower `-j` and
retry rather than debugging the generator. Bound a full `make frontier` with
`NINJAFLAGS=-j4` when other agents are live.

## Canonical facts you should not re-derive

- **The fixture party is LOCKE, CELES, SABIN, EDGAR** (four through the
  Facility, three once the tube room takes Celes), measured per doorstep in
  `wob-route.md:104`; the post-opera anchor's entry contract counts the
  `$1850` assignments so a chain that loses members fails loudly (#21).
- **Map 323 is Albrook; Vector is 242 and 253** (`vector-route-recon.md:30`,
  both title index 49).
- **The item equip mask is `item_prop_en.dat` offset `+$01`, 16-bit, bit N =
  actor N** (`research/data-formats.md:45`). Byte `+$00` always looks like a
  mask and always claims Terra.
- **`monster_prop.dat` `+23` is absorb, `+25` is weak** — `check_boss_rows.py`
  and `check_break_reach.py` enforce doc/data agreement inside `make test`.
- **`OT6_BREAK_TICKS` is `$10`** (`ff6/src/battle/ot6_break.asm:1`) and buys
  a **2159-frame** window, ~36 s. Not "roughly one turn".
- **There are exactly three multi-hit abilities in the game** — Quadra Slam
  ×4, Quadra Slice ×4, Empowerer ×2. `tools/audit_multihit.py` proves it and
  fails if that changes.
- **SwdTech has a 1-BP floor** since #38 — there is no 0-BP rung.
  `Ot6BushidoTech` (`ff6/src/battle/ot6_kits.asm:74-79`) clamps a stray 0 up,
  and boost 1/2/3 selects Cyan's *top three learned* techs, so a given rung's
  price slides as he learns more.
- **A poison DOT tick chips a shield; Sap does not** (#60, measured). A tick
  is an ordinary poison hit with no attacker and chips exactly one axis. A
  broken monster takes no ticks at all.
- **The `event_triggers` fixed block has room for 2 more triggers
  game-wide.** Re-measured against `build/ot6.sfc` on 2026-07-30: 13 trailing
  `$FF` bytes in the block at `C40000`+`$1A10`, and a trigger is 5 bytes.
  (`npc_prop` has 76 trailing bytes ≈ 8 more NPC records, an upper bound —
  an NPC record's last byte could legitimately be `$FF`.) The deferred
  Opera-band save list needs segment relocation first
  (`design/save-points-vector.md` §1).
- **The suite is self-registering**, discovered from each test's `-- @suite`
  marker; `tools/tests/suite.sh --list` reports 82 tests, 25 of them slow
  (2026-07-30). Frontier-gated tests join once `make frontier` has minted
  their fixtures.

## Working this program on smaller models (owner-requested, 2026-08-10)

Sonnet and Opus sessions pick this program up on days the larger model is
unavailable.  The work is tiered so capability is spent where it matters;
when in doubt about which tier a task is, treat it as the higher one and
STOP-AND-NOTE instead of deciding.

**Tier 1 — take freely (mechanical, precedent-rich).**  Fixture-swap test
conversions from docs/waiver-burndown-plan.md (the per-file work orders
name the fixture, the writes, and the replacement idiom; four merged
waves in git log are worked examples — copy their shapes: the $7BC2 menu
machine, flee-not-kill-bit, baseline-latch, earn-don't-hand, the counted
ledger, the read-only RNG decode).  Waiver/probe hygiene.  Doc
corrections with measurements in hand.  Running the frontier or suite
gates and reporting results verbatim.  Rules that are absolute in this
tier: KEEP every original assertion (conversions change how state is
REACHED, never what is claimed); one commit per test with the
measurement in the message; the checker green with the file's waiver
lines deleted before commit; fail-before/pass-after when a claim is "the
poke was unnecessary".

**Tier 2 — take with the guardrails on (judgment inside a template).**
Boss-fight legs and gen re-mints: use the established toolkit only
(equipOptimum + fieldCare prep, newFightDriver with tactical/boost/
bank/items/healer/magic, 3-attempt phase-spread ladder, reload-verified
mints).  The ladder stays at 3 — widening it until it gets lucky is the
#74 mistake and is never acceptable.  A leg that loses all three
attempts is a FINDING: write the numbers at the assert, leave the leg
red, note it on #75.  Do not retune game data, ever.

**Tier 3 — do NOT decide on a smaller-model day; stop and leave a note.**
Overturning any documented measurement or verdict (the record shows even
strong runs got the Cranes wrong twice — the cost of a confident wrong
correction is days); lib/*.lua changes (they stale every fixture and
their bugs surface as OTHER legs' failures); frontier_graph.py edges and
anchor entry/exit contracts; quarantine/isolation-arm classification
calls; anything requiring a NEW diagnosis mechanism rather than an
established one.  For these, write the observation (what was measured,
what it seems to mean, what you did NOT do) into the relevant file
header or a #75 comment and move to Tier-1 work instead.

**Pace is sanctioned to drop (owner, 2026-08-10): "i'd rather it go
steadily well than quickly but wrong."**  Doing one Tier-1 item
carefully beats three hastily; an idle day beats a wrong finding.  No
session should feel pressure to match the large-model sessions' merge
rate.

**The escalation rule that subsumes the tiers:** before concluding
anything surprising, re-read "The failure mode worth knowing about"
below.  If your conclusion requires believing a documented measurement
is wrong, the odds strongly favor your instrumentation over the record —
verify with the cheapest possible look (a probe, a byte read, a re-run)
or leave it for a stronger session.  A wrong finding written confidently
is the most expensive artifact this program produces; three of them are
already in the record, each caught only by re-measurement.

**Mechanical anchors that keep any session honest:** the state-write
checker and its shrink-only list; the equipment audit; compose
--check-states before debugging any red test; the runtime write gate
(violations name themselves at the call); `make frontier
NINJAFLAGS="-k 0"` to enumerate blockers rather than hitting them one
per run.  Trust these over reasoning.  Keep main, the integration
branch, and the owner's checkout fast-forwarded together at every
gate-green checkpoint (owner rule: simple, visible, clear).

## Branch and worktree state (2026-08-10 wrap)

`main`, `claude/issue-75-9a89a6` and the owner's checkout are all at the
same commit and stay that way (owner rule: simple, visible, clear).

Today's eight agent branches are merged, and their branches and
worktrees are deleted.  What is deliberately still around:

- **`wt/tail-a`** (branch + worktree) — holds ONE unmerged commit, the
  `battle_rage` conversion, which is labeled UNVERIFIED and must not
  reach main until it runs green on a re-minted `gau_joined`.
- **`origin/feed-gau`** — fully merged, kept as the documented pre-#75
  safety ref.
- **Four `origin/worktree-agent-*` branches** (`a20451ce`, `a53262d5`,
  `aaa205d8`, `af03cb95`, `afa759a4`) carry 1-9 unmerged commits each
  from the early-August sessions.  Their work was integrated by
  RE-IMPLEMENTATION rather than by merge, so those commits are believed
  superseded, not lost — but nobody has verified that commit by commit,
  so they are left alone rather than deleted on a guess.  Anyone
  cleaning up should diff them against main first.

## Working agreements

- Delegated work gets [agent-brief.md](agent-brief.md) included by reference —
  **cite the copy in the agent's own worktree, never `/Users/mtklein/ot6/docs/`.**
  The owner's checkout sits on the release branch he is playtesting, so a doc
  read from it can be weeks stale; on 2026-07-29 every agent that day read a
  brief from two days earlier and followed rules already replaced.
- Agents commit to their own branches in revertible units, file exclusivity is
  "declare your hunks and expect merges", and targeted re-mints
  (`ninja -f build/build.ninja <state>`) are theirs. The full frontier chain
  stays with the dispatcher. Rationale in `rules-audit.md`; the owner's
  framing is that occasional rework from an unexpected conflict is an accepted
  cost as long as it stays unusual.
- Agents report follow-ups; the dispatcher files issues. `spawn_task` is
  denied in `.claude/settings.json`.
- Parallel work goes in separate git worktrees; `tools/worktree-setup.sh`
  seeds the ROM, emulator links, states, and the ninja build log. **Worktrees
  live under `.claude/worktrees/<name>` inside the repo** (owner rule,
  2026-07-28: never as siblings of `~/ot6` or anywhere else in the home
  directory).
- Commit messages here run long and explain the why, including what was ruled
  out. Match that.

## The failure mode worth knowing about

Nearly every wrong turn in this project has been the same one: **reasoning
substituted for looking, when looking was cheap.** The two newest entries in
the case file are both about *absence* being read as information: a symbol
lookup that silently returned the wrong module's address, so an
instrumentation window never closed and every later event was attributed to
it (trap 3); and `kits.md`'s Chip column, which stated design intent as
shipped fact for months because nobody had enumerated the records. In both,
one grep or one audit script would have settled it.

The rules in CONTRIBUTING under *"your job is not to write correct code, it
is to prove the code is correct"* exist because of specific incidents.
`make smoke` and the ninja graph exist to make looking cheap enough that it
is the default.
