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

**The 2026-08-06 frontier regression is FIXED (2026-08-09).** That run
failed minting `vargas_won` from a freshly regenerated `vargas_doorstep`
whose party was EDGAR 1/145, LOCKE 122/122, TERRA dead, seven Potions, no
Fenix Down -- and four honest VARGAS attempts wiped. It was never the
fight. Instrumenting `gen_kolts` leg by leg (a roster line now rides every
`where`) found three separate things, all fixed on `main`:

- **`advanceStory` accepted `honest="flee"` and ignored it.** Every other
  navigator had a flee branch; that one fell through to the blind A-tap, so
  every map settle that rolled an encounter fought a whole battle by
  mashing A while its caller's header said the route runs from them.
- **No route ever opened the item menu.** `H.fieldCare` (lib/ot6_field.lua)
  drives the real field Item -> use -> target windows, zero writes, closed
  loop on the game's own cells, and reads the engine's refusal flag ($B5)
  instead of mashing A at a window that will never accept the pick. The UI
  was MEASURED, not assumed: A on the item list PICKS A SLOT UP ($19), and
  only a second A on the SAME slot uses it -- a first pass quietly
  rearranged the bag instead of healing anyone. Citations:
  `research/field-care-menu.md`, probes `probe_fieldheal` /
  `probe_fieldcells` / `probe_fieldcare`.
- **Mt. Kolts and map 98 are FOUGHT now, not fled** (`honest="tactical"`).
  Fleeing is not free -- it is standing still while the formation takes
  free rounds. Three measured runs: fled -> TERRA dead at the doorstep;
  fled with care -> LOCKE dead on the last 53 steps; fought -> everyone
  alive, two levels up, at 136/168/169.
- **The party shops.** It walked through South Figaro and back out with no
  revive item; it now buys three Fenix Downs and tops Tonics to fifteen
  through the real shop UI. Route and stock in
  `research/south-figaro-shop-route.md` -- the shop is **8**, not 15, and
  it does **not** sell Potions at this point in the story.

Result: `gen_vargas` wins on **attempt 1** (the retry ladder never fires),
SABIN joins, `vargas_won` mints reload-verified, and the post-fight care
stop raises TERRA so everything downstream inherits a whole party.

**`M.FLEE_CAP` is written in blood.** At 5400 frames a cave-97 formation
refused to release a FULL-HEALTH party, the flee held for all ninety
seconds, the party wiped inside its own escape attempt, and the drive
tapped A through the Game Over into a brand-new game -- eleven maps of
intro before the budget expired. The cap is **1800** and the fallback is
the tactical fighter, not a blind A.

**Owner note, 2026-08-09 -- FRONT ROW / BACK ROW is an open gap.** "A lot
of ranged attackers can just sit in the back row forever at no cost."
EDGAR's damage here is Tools and TERRA's is magic; neither cares about row,
and no fixture in the chain has ever set one. Research is in
`research/row-menu.md`. Rows are persistent per-character state, so setting
them once early propagates to every downstream fixture -- do it before a
full re-mint, not after.

**`sfigaro_town` IS GREEN (2026-08-09).** It was never balance -- it was
FOUR defects stacked, and fixing any one alone still lost, which is why it
read as tuning for three runs: LOCKE bare-handed (8 damage a swing), the
bag drained by the Terra party upstream, the wrong ROW, and needing a top
up before the third rematch. All three gate engagements now win on
attempt 1. **The row is the load-bearing one** -- at ~110 a hit against
168 hp he must heal every turn from the front and can never swing; halved
he survives three, attacks two in three, and BREAKS the armour (495 -> 0,
shields 3 -> 0 three times, never below 112 hp).

**But the row lever does NOT generalise.** On the Phantom Train the same
change measures WORSE, twice, on a fresh chain: front row shields 6 -> 3
and SABIN down at f34707; back row shields 6 -> 6, casts 0, down at
f19108. Blitz/Throw/SwdTech really are row-exempt and the fight still went
the other way, so something that CHIPS that boss pays the penalty. Do not
re-derive it from the exemption rule.

**NEW BLOCKER, `sfigaro_escape` (gen_tunnelarmr):** navTo timeout, party
parked at map 75 (41,43) with no plan for 20000 frames, NOT a wipe (the
canary stays quiet). Almost certainly the gate soldier again -- he
respawns on every map-75 reload, nothing clears `$030C`, and (30,42) is
the only tile joining the quarters. `gen_sfigaro` has `clearGateSoldier`
for exactly this and `gen_tunnelarmr` has nothing; that helper wants
promoting into the library rather than copying.

**Frontier status, end of 2026-08-09: FOUR blockers found, TWO fixed.**
Running `make frontier NINJAFLAGS="-k 0"` (continue past failures) is how
to enumerate them in one pass instead of one per multi-hour run -- do that
first, always. The list:

| leg | looked like | actually was | now |
|---|---|---|---|
| `terra_clifftop` | "navTo timeout, 60000 frames" | the party WIPED; the leg walked BANON's escort on `honest=true` (blind A) and never opened the item menu | **FIXED** -- `honest="tactical"` + `H.fieldCare` per crossing, green at f12782 |
| `sfigaro_town` | balance wall | LOCKE unarmed, then out of supplies, then in-battle heals not landing | **OPEN**, see below |
| `train_done` | — | the #74 Phantom Train, thin margin | **OPEN**, attempt 1 got it to 744 hp / 3 shields of 6 |

**`sfigaro_town` IS A BALANCE FINDING. Nine hypotheses were tested and
killed to get there; do not re-test them:**

| hypothesis | verdict |
|---|---|
| blind button pattern, no menu awareness | replaced with `newFightDriver` -- no |
| LOCKE unarmed | REAL, fixed: 8 -> 21 damage a swing. Not enough |
| out of supplies | REAL, fixed: 12 Tonics + 4 Potions inherited, was 2 Tonics. Not enough |
| item cursor index != `$2686` index | MEASURED CORRECT (`probe_battleitem`): cursor sum 1 consumed index 1. No |
| solo-party target-cursor deadlock | real latent bug, fixed, no change here. No |
| boost bank never reaching 3 | `opts.bank` implemented. No |
| back row halving what he takes | front and back measure IDENTICALLY. No |
| sneaking past the soldier | polled `bfsPath` every 60 frames for 7200 frames -- he NEVER steps off the choke. No |
| Active battle mode punishing menu time | `$1D4D` already reads Wait, speed 2. No |

**CORRECTION, and it reverses the conclusion above.** I called this a
balance finding twice. It is not one. The arithmetic, done properly:

```
effective HP pool   168 + 4 Potions*250 + 12 Tonics*50 = 1768
enemy hits absorbed 1768 / 110                         = 16
actions in that time  16 * (600/300)                   = 32
  spent healing                                        = 16
  left to attack                                       = 16

never breaking the shields:  16 * 21          =  339  vs 495  LOSE
breaking first (3 chips, 1 per hit, measured):
  3*21 + 13*84                                = 1167  vs 495  WIN
```

Shielded damage is HALVED and the ladder is broken:weak:unweak = 4:2:1
(`Ot6ShieldedMulW`, `ot6_break.asm:1487-1497`), so a broken HeavyArmor
takes **84 a swing, not 21** -- and LOCKE chips one shield per boosted
Fight, measured (495/sh3 -> 484/sh2). Three chips and the fight is over
with more than double the margin. **The fight is winnable and the whole
thing turns on the break economy, which is what this game is about.**

So the real blocker is the ONE remaining harness bug: **LOCKE's heals do
not land**, so he never survives the sixteen actions the win needs. The
trace shows the confirm at `$38` followed by `$40 -> $01 -> $0A` -- the
item window RE-OPENING, which is what a REJECTED confirm looks like.
Leading hypothesis, unmeasured: **cursor memory** (`$1D4E & $40`) starts
the battle item cursor somewhere other than row 0, so the single `down`
the driver presses lands on an empty slot. Run `gen_sfigaro` with
`trace = true` on its `rideOut` driver -- the item-window dump prints
scroll/row/sum beside the live `$2686` contents, which settles it in one
run. Do NOT retune anything until that is chased.

**The first full-frontier run of the honest chain got to 117 of 187 edges**
(2026-08-09) and stopped at `sfigaro_town`. Everything through the Terra
scenario, the Sabin line, the rapids and the scenario split re-minted
green under the new lib.

**THE RESUME POINT IS `gen_sfigaro`, and the blocker is a balance finding,
not a harness bug.** Solo LOCKE loses `battle 11`, the South Figaro gate
soldier, on every attempt. Chased all the way down, in this order:

1. The drive was a 32-frame button pattern with no idea what a menu is --
   sixteen Tonics sat in the bag through three losses. It is
   `H.newFightDriver` now.
2. Still lost, so the driver's heartbeat learned to log ENEMY hp (monsters
   are entity slots 4..9, the same table eight bytes along). Answer:
   **495 -> 487 and stop. Eight damage a swing.**
3. Eight is low enough that "he is unarmed" was still live, so look:
   `probe_lockekit` reads `$1600+37*1+$1F..$23` as **`FF FF FF FF FF`**.
   **LOCKE starts his whole scenario with nothing equipped and his own
   Dirk in the bag.** `remove_equip` returns gear to inventory
   (`EventCmd_8d`) and the mint chain has never put it back on -- the same
   bug `battle_brokendeath` found at the Vector infiltration and fixed
   only for itself. **`H.equipOptimum` is now in the library.** Assume
   every post-`remove_equip` fixture in the chain is bare until checked.

Armed, his swing goes 8 -> 21 and he still loses: **~21 damage dealt per
300 frames against ~117 taken**, into 495 hp at level 13 whose weaknesses
(bolt, water) solo LOCKE cannot reach. He needs ~7200 frames of swings and
survives ~2500. Front row and back row measure the same. **That is a
#74-class finding and it is left FAILING on purpose.** It needs an owner
call: retune battle 11, or make the gate passable another way.

Two smaller fixes landed with it: `gen_sfigaro`'s B1 decided whether to
fight by asking "is this tile reachable this instant", and the gate
soldier WANDERS -- one inserted menu visit flipped the branch and the leg
then died of "no path"; it reads `$0104` now. And `newFightDriver`'s press
cadence is an option (at the historical 30, a boosted Fight costs two
seconds of wall clock just to TYPE).

**THE EQUIP AUDIT IS DONE AND IT WAS BIGGER THAN THE LEG THAT SURFACED
IT.** `tools/audit_equipment.py` (wired into `make test`) reads the
savestates directly -- no emulator, 118 fixtures in about a second -- and
found **LOCKE bare-handed in 42 fixtures and CELES in 29**. Two of the
four World-of-Balance characters have fought every honest battle this
chain has ever measured with their fists. `H.equipOptimum` stops are in
at the two chokepoints (`gen_celes` at the passage, `gen_narshe_battle`
at the reunion) plus `gen_sfigaro`; UMARO is excluded because the equip
mask says he can hold exactly one weapon record, which is derived rather
than assumed. Any leg still red after a re-mint should be checked against
this audit BEFORE it is called a balance finding.

**Two library traps worth knowing, both found the expensive way:**
`newFightDriver` re-read the battle inventory while the item window was
open, got nil, dropped the plan and pressed B -- forever ("mid-menu
inventory reads measurably lie" was already written down for the FIELD
inventory in gen_sabin_train's shop drive; the battle side had the same
trap). And a party wipe used to impersonate a stuck navigator: the three
navigators now carry a debounced `M.partyWiped()` canary that names it,
because neither of the two wipes so far produced a log containing the
word "died".

**The older follow-up note, kept for the numbers:** `event_main.asm` has **58 `remove_equip` sites
in 15 clusters** (the Vector infiltration strips all thirteen at
`:11979-11991`; `:26328-26352` and the two `:84472`/`:84534` blocks are the
other big ones), and the mint chain has never re-equipped after ANY of
them. Every fixture downstream of one should be checked with
`probe_lockekit`'s read (`$1600+37c+$1F..$23`, `$FF` = empty) and given an
`H.equipOptimum` stop if it comes back bare. Expect more walls that look
like balance and are not.

**`make test` stops at its own `--check-states` gate** while the frontier
is mid-re-mint, which is that gate working, not a failure.

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
`lib/ot6_field.lua` and `H.clearBattle`; re-mint every fixture under the
final gate/provenance contract; reduce the waiver file to only the
explicitly quarantined mechanism tests; run the complete test and frontier
gates.  (The compose-time runtime write gate LANDED 2026-08-09,
waiver-aware: zero-waiver scripts compose with the global `emu` proxied and
the write surface refused at the call; the lib keeps the confined raw
handle only while its own waivers survive, so the kill-bit deletion flips
the gate strict with no further compose change.  `__OT6_EMU_RAW` is a
forbidden static token, closing the reach-around.) The branch has targeted green replays, but
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
