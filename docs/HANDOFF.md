# Handoff — state of play

Last refreshed 2026-08-06; rewritten 2026-07-30, replacing the 2026-07-27
version wholesale. That one
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

**Dated 2026-08-06.** The owner's 2026-08-03 directive supersedes normal
open-work ordering until done: tests and fixture mints may press buttons and
read memory, NEVER write emulated game state ("if you are not playing actual
game states that have been reached through actual game choices, you are just
wasting time pretending"). The bar is PLAYABILITY — a player's inputs could
do this, TAS-style margins fine — with balance observations logged as data
for the post-1.0 balancing era, never treated as blockers. Fault-injection
mechanism tests survive as a loudly-labeled quarantine (owner ruling). The
running record is issue #75; the rule itself leads tools/tests/README.md's
"Writing a test".

**The 2026-08-06 integration is landed directly on `main`; the old remote
safety ref is `origin/feed-gau` at `2e4cabc`.** It was based on main `7770428`
and contains the formerly
queued Sabin, Gau, Figaro/Kolts/Vargas, Locke/Terra, Narshe/Kefka, Zozo and
Opera conversions, plus the v0.6 route through the Ifrit doorstep. Do not
restart those branch integrations. The static ratchet currently reports
344 Lua files, 1496 state-write sites and **318 waived `(file,token)` pairs**
(374 at birth); no unwaived writes and no stale waivers.

The important newly-proven route facts are:

- Gau is fed Dried Meat through the real Item menu (`53700fc`); the old
  "undrivable" model was wrong. `079043d` preserves him through the Veldt
  mint route. The owner's command rule is explicit: **Leap on the Veldt,
  Fight off the Veldt.**
- The full Sabin line is honest, including real shopping, healing/revival
  and the Phantom Train win. The integrated route also includes honest
  Vargas, TunnelArmr, Kefka, Dadaluma and Ultros 2 wins; the Opera rats and
  Zozo bridge are passed by real controller play.
- `H.loadState` no longer wipes codex SRAM (`4dbfca4`); that premise was
  measured and disproved. The shared observed-menu fighter now supports
  real Item use for healing and Fenix Down revival (`0efa432`).
- The Vector/factory chain is replayed green in dependency order through
  `gen_vector_doorstep`, `gen_vector_sneak`, `gen_mrf_entry`,
  `gen_mrf_chute`, `gen_mrf_263`, `gen_mrf_kefka` and
  `gen_ifrit_doorstep`. Traversal fights legitimately hold L+R to flee;
  they are not kill-bitted. The last leg passes at frame 2056, validates all
  17 fields of `mrf-save-room-v1`, mints the quiet doorstep and verifies one
  A press opens battle 70 containing Ifrit and Shiva. Commit `d506075` is
  that terminal checkpoint.

**Wrap checkpoint, 2026-08-06:** a clean
`make frontier FRONTIER_JOBS=4` passed the state-write ratchet and the first
101 of 178 frontier edges, then failed while minting `vargas_won` from the
freshly regenerated `vargas_doorstep`. That honest doorstep has EDGAR at
1/145 HP, LOCKE at 122/122, TERRA down at 0/94, and seven Potions but no
Fenix Down; all four real Vargas attempts wiped before Sabin's phase. The
retained evidence is
`build/test-runs/vargas_won.JaO70HVC/run.log`. A scratch Item-cursor fix
(`$8947+actor` scroll + `$894F+actor` row) did select and spend a Potion, but
could not make the doomed party viable and was intentionally not retained.
Start by adding an honest layer of care before Vargas—preferably keeping the
party alive during the Mt. Kolts flee route or buying/using recovery supplies
through real menus—then replay `gen_kolts.lua` -> `gen_vargas.lua` and resume
the full frontier gate. This known frontier regression was documented before
the integration was landed on `main`; it is the first restart task.

**After that regression is green, resume at
`tools/tests/gen_ifrit_magicite.lua`.** It still contains
its kill-bit helper and uses the old cheating `H.advanceStory` path for the
forced Ifrit/Shiva win. No new implementation was started after `d506075`.
The known honest strategy already exists in `battle_brokendeath.lua`: equip
all four characters through Equip → Optimum, have Celes cast Ice and Edgar
use AutoCrossbow to chip the six shields, then finish the real scripted
fight. Reuse or factor that observed-menu drive; do not substitute a generic
tap-A claim without a live win. Incidental traversal battles may flee.

After Ifrit/Shiva, continue in this order: `gen_n024_doorstep` traversal;
the forced Number 024 win in `gen_esper_tubes`; the tube-room set piece in
`gen_esper_tubes_done`; `gen_minecart_doorstep`; then the minecart and
Number 128 chain. The Number 128 party must be **Locke + Edgar + Sabin** per
the owner, selected through the real upstream party menu — never solo Locke.

**Still required before #75 may close:** finish the v0.6 chain and banquet;
re-cut all legacy battery anchors through the real Save UI; convert the
remaining gameplay/lab consumers; delete the shared kill-bit paths from
`lib/ot6_field.lua` and `H.clearBattle`; land the compose-time runtime write
gate; re-mint every fixture under the final gate/provenance contract; reduce
the waiver file to only the explicitly quarantined mechanism tests; run the
complete test and frontier gates. The branch has targeted green replays, but
no post-integration full-suite/full-frontier result yet — do not represent
the program as complete.

**Traps this program has already paid for (don't rediscover):**
capture-calm does NOT imply reload-calm — every mint should reload its own
capture and verify (`gen_sabin_gau`'s pattern, three gens use it); a stale
seeded fixture reads exactly like a product bug (`--check-states` first —
the Marshal "impossible geometry" was a corrupt fixture); the battle Item
cursor is a SUM (`$8947` scroll + `$894F` row); command row zero is not
universally Fight; concurrent worktree suites can SIGTERM each other's Mesen
runs (stagger heavy gates).

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
