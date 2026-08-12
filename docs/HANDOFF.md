# Facts that are expensive to rediscover

These cost real time to work out the first time. Start with
[README.md](../README.md) for what OT6 is, [CONTRIBUTING.md](../CONTRIBUTING.md)
for the house rules, and [ROADMAP.md](ROADMAP.md) for the release plan.

## Measured facts (do not re-derive)

- **fieldCare drives the real menus and prefers casting to drinking.** It
  walks Item→use→target for a consumable and Skills→Magic→spell→target for a
  cure spell, and it reaches for the bag only when nobody can cast, when the
  MP is short, or when the target is KO'd and wants a Fenix Down. The reason
  is OT6's own rule that level up restores HP and MP in full
  (`ot6_progression.asm:3-6`, called from `battle_main.asm:16251`): MP spent
  in a corridor is refunded and a Tonic is not. Measured at
  gen_ifrit_magicite's stop before battle 70: 3 Potions before, 0 items and
  25 MP after, in fewer frames (143 against 229), because a second cast for
  the same caster never leaves `$3B` while each item use pays a full fade
  round trip. `opts.magic=false` restores the item-only drive for a step
  that wants its MP kept. On the field item list, A picks a slot up; only a
  second A on the same slot uses it.
- **The battle fighter prefers casting too, and the grant behind it is
  battle-only.** `newFightDriver`'s heal branch casts a cure where it can
  and reaches for the bag where it cannot; `opts.cure=false` is the old
  item-only drive. It is spelled `cure` rather than `magic` because that
  driver already spends `opts.magic` on its attack line. Both lines find
  the spell in the actor's **live** battle Magic list (`$302C`,entity is
  the engine's own pointer at it; record 0 is the esper row, record n+1 is
  grid cell n, `+3` is the price `GetMPCost` walks) rather than at a row
  the caller names, because OT6 compacts that list to the party's union and
  then prunes it per character (`Ot6UnionEspers` and
  `Ot6EsperSpellKnown`, `ot6_progression.asm:205`, `:144`), so one spell
  sits at different cells under different loadouts. **Those two hooks are
  on the battle spell-list path only** (`battle_main.asm:14455`, `:14628`):
  a Kirin bearer has Cure in battle and no Magic row at all in the field
  menu, so `fieldCare` cannot cast a granted cure and still drinks. There
  is also no revival by magic anywhere in the WoB — no owned esper grants
  Life (`genju_prop.asm`) — so a segment with no Fenix Down in the bag has
  no answer to a death at all.
- **zMosaic (`$B5`) is never cleared, so "was that refused" is an edge, not
  a level.** `MosaicTask` writes `$17 $27 $37 $47 $37 $27 $17 $07` and
  terminates (`field_menu.asm:3820-3844`); nothing re-zeroes it after menu
  init (`menu_init_2.asm:506`). Measured: 40 frames after a real refusal
  `$B5` reads `$07`. Test `$B5 & $F0`, which is nonzero only while the
  animation runs, or every plan after the first refusal reads as refused.
- **fieldCare's world-map exit is debounced, not fixed at the root.**
  `careBackOnMap` on its own still passes at a moment that is not "world
  module running"; `careClose` is what makes the drive safe, by requiring 30
  consecutive satisfying frames plus "not parked on any menu screen" in
  world mode. Field mode takes the raw first true frame, and debouncing it
  there hangs instead. gen_sabin_gau cares on the overworld and passes.
- **`opts.playBattles="flee"` vs `"tactical"` vs `true`**: fleeing means
  standing still while the formation takes free rounds. Blind-A
  `opts.playBattles=true` stalls or wipes the party on any segment that can
  draw an encounter.
  `M.FLEE_CAP` default 1800, per-call `opts.fleeCap` (the South Figaro
  escape route uses 420). Cave pincer formations cannot be fled at all,
  which is FF6's own rule.
- **Rows**: `$B3 = $FF` for every command and only the weapon swing
  clears it, so Tools, Magic, Blitz, SwdTech, Throw and Steal are
  row-exempt. Back row wins where damage is break-driven and loses where the
  chipper is a weapon swing (South Figaro vs Phantom Train, both measured).
  Where **nobody's** chipper is a weapon swing the back row is simply free,
  and worth taking: Number 128 is fought with Tools, Magic and Magic, and
  moving all three back turned a fight that lost attempt 1 with the party
  arriving intact into one that wins attempt 1 arriving worse (#92).
  Rows are persistent state, so set them deliberately per segment.
- **The equip audit** (`tools/audit_equipment.py`, a `make test` check with its
  own only-shrinks story-waiver list): check any red segment against it
  before calling the result balance.
- **Absorb fails the run; null does not, and must not.** The absorb guard
  in `M.run`'s frame callback (`lib/ot6.lua`, `battle_absorbguard.lua` is
  the check) reads the formation's species and everyone's equipped weapon
  once per battle and aborts when an element is absorbed, because then
  every swing heals the enemy — the Cranes, where Optimum's ThunderBlades
  healed a bolt-absorbing boss for up to 943 a swing. Do **not** widen it
  to null. On battle 70 both siblings null bolt and the ThunderBlade pick
  is still correct, because that fight is won by chipping shields and a
  chip goes by weapon **class**; the element-aware equip swapped to
  daggers and lost all three attempts. Random encounters log instead of
  failing (`OT6_RANDBTL`, `ot6_boost.asm:14-29`).
- **The party-hp audit** (`tools/audit_party_hp.py`, same shape, same kind of
  waiver list) is the other half of that: no fixture ships a party member
  dead, petrified, zombie, or at or below max HP / 8. Max/8 is the game's own
  near-fatal line (`battle_main.asm:11544-11549`), and the bar is there rather
  than at half HP because the measured distribution has a wide gap — 241 party
  records across 98 fixtures run 0%, 6.5%, then nothing until 36.6%. Both
  audits share one savestate reader, `tools/savestate_party.py`.
  `H.assertPartyStanding` is the same three conditions as a generator exit
  contract, and the two must be changed together.
- **A party wipe must be reported as a wipe.** The navigators'
  `M.partyWiped()` check misses in-battle wipes, because `$1600` keeps
  pre-battle HP. The filed fix is a battle-module check (`$3BF4` under
  `battleLoadStarted()`). Three wipes have been mistaken for stuck
  navigators.
- **Retry ladders are 3 attempts, and go through `H.newSeedLadder`.** A
  battle's whole RNG stream hangs off `$be`, seeded once at battle init from
  the game-time frame counter: `lda $021e / asl2 / sta $be`
  (`battle_main.asm:6174-6176`), so the phase has period 60 and picks one of
  sixty seeds. `L.spread(n)` holds each attempt until `$021e` reaches its own
  phase; `L.report()` reads the seed off the store instruction and fails if
  two attempts drew the same one. The old fixed 37-frame stagger did not
  guarantee that: attempt 1 sat at whatever phase the route happened to leave
  it, and one lead value in sixty put it on attempt 2's seed — a ladder
  playing one fight twice, with no symptom (#83; `battle_seedladder.lua` is
  the check, `probe_ladder_seed.lua` the measurement). Do not widen a ladder
  until it succeeds by chance; a ladder that loses all three attempts is
  reporting a finding.
- **Every saved checkpoint is generated through the game's own save routine,
  never synthesised.**

## Traps

**1. A WRAM cell means what its owning module says it means.** `$7E3BF4` is
the party battle-HP table only while the battle module owns that RAM. `$021f`
has exactly four writers, all menu lifecycle, so forcing `ZMENUSTATE` mid-flow
leaves corrupted menu tasks running and the cell reads as overlaid. Ask which
module owns a `$02xx` cell before trusting it, verify by instrumenting (block
moves are invisible to Mesen write callbacks, so sample rather than set a
watchpoint), and confirm persistent facts through SRAM (`$307ff0`, the codex
pages) when a context-free channel exists.

**2. Cycle budgets are per site, and there is no room left on any of them.**
`Ot6BgHud_ext` runs from `WaitFrame` immediately after `WaitVblank` returns,
once per battle frame, and has under 80 cycles of slack, possibly under 20.
Measured with bare-NOP controls carrying no feature at all: 12 NOPs pass, 80
NOPs fail, and the penalty saturates (20 and 110 cycles both cost the
same 163 frames). The symptom is not a crash or a wrong result. Everything
runs about 10% slower, which flips timing-sensitive tests elsewhere and looks
like a bug in those tests. Keep work there inline at the call site; a `jsr`
into a proc that early-outs is already too expensive.

12 NOPs being safe at that site does not make 12 NOPs safe anywhere else: the
same bare-NOP control in bank `$C2`'s **action** path fails at **nine** NOPs,
so that path's margin is under 18 cycles. The canary is
`battle_trueknight` phase 4b, whose covers span reads 1635 intact and 1798
over.

**Twelve cycles per battle frame is over the cliff on the v0.10 branch.**
Measured 2026-08-11 landing issue #87, at the other per-battle-frame site,
`Ot6RestageGate_ext` polled from bank `$C1`'s frame loop
(`btlgfx_main.asm:1749`). Its idle path is 14 cycles. Shortening its
standing-request path build by build gave 1798 at 40 cycles, 1798 at 33,
1798 at 26, and 1635 only once the request was dropped so that the path
became the idle one. Every build was identical apart from that one proc, so
this is 12 cycles per battle frame flipping the canary and nothing else.
Read it as the budget's remaining slack having been spent since v0.9 rather
than as this site being twice as tight as `Ot6BgHud_ext`: the 12-NOP result
was taken with less OT6 code on the per-frame path. Either way, plan a
per-frame change around making the resting path shorter, because there is no
headroom to spend.

**It is cycles on code that runs, not bytes.** Settled 2026-08-11 landing
issue #66, with the control that had been missing: nine *unreachable* bytes
placed just before `ExecAction`'s label give 1635 and pass, while nine bare
NOPs at `ExecAction`'s pre-dispatch check (`battle_main.asm:274`) give 1798
and fail. Both builds grow `battle_code` by the same nine bytes, to `$652c`,
so bank `$C2`'s size and the code motion of everything after the insertion
point are both ruled out. That also disposes of the old hypothesis here that
only per-battle-*frame* code moves this number; per-action code moves it too,
and the four `$C2` call sites that were added for free
(`battle_main.asm:514`, `:3409`, `:4152`, `:14652`, plus `Ot6RecheckMagic` at
`:14715`) were free for some other reason. The practical rule: a change that
lands here needs to spend fewer cycles on the executed path, not to find a
smaller encoding. Issue #66 shipped one gate site instead of two on that
basis, and moved the surviving one below a test that makes it run rarely. The
`Ot6BgHud_ext` record is the block comment over `OT6_BRKLIVE` in
`ff6/src/battle/ot6_memory.inc`. (This is distinct from the vblank-TRANSFER
budget, which is about VRAM words, not cycles.)

**3. `H.sym` resolves a duplicate symbol name to the wrong address, with no
error.** `parse_dbg_syms` (`tools/tests/lib/compose.py:218-250`) walks
`ff6-en.dbg` taking **the first** `type=lab` record for each wanted name and
then skips that name forever (`if name in out: continue`, `:241`). `ExecCmd`
is defined twice — `$C09B1B` and the battle one at `$C213E6` — so a probe that
hooks `ExecCmd` gets the wrong module's address, its instrumentation window
never closes, and every later event is misattributed without anything
reporting a problem. Before hooking a symbol by name, check how many label
records in the `.dbg` carry it; if more than one, use the address directly or
attribute by something else.

**4. A mismatched ROM/fixture pair presents as "timeout waiting for main
menu".** Savestates are ROM-coupled. When a fixture was generated from a
different ROM than the one under test, the failure you see is a menu that
never opens, and nothing in the output mentions stale state. If a menu drive
times out and you have recently changed ROM-affecting source, regenerate
before you debug the menu. `tools/worktree-setup.sh` prints a matching warning
when it seeds savestates generated on a different branch.

**5. NPC record order determines NPC identity.** Event scripts address NPCs as
{map, index-within-block}, so a record inserted ahead of an existing NPC
renumbers everything after it. **Append records; never insert them.**

**6. `navTo` lands at rest, so a tile that takes the party away must be
entered with a held press rather than made the goal of a `navTo`.** Position
samples are only valid at rest on a tile
(`tools/tests/lib/ot6_field.lua:459`, `:616`).

**7. `event_main.asm` is a dump of separately-addressed scripts.** Adjacency
in it means nothing. Party composition is runtime state: read `$1850` at a
fixture. `bosses-wob.md` is authoritative on party composition.

**8. `LoadMagicProp` fills one shared buffer.** Freeze the rest of the party
when measuring an ability, or an ally's action inside the measurement window
will read as the summon costing nothing. Documented at `freezeOthers`
(`tools/tests/battle_magicite.lua:232`).

**9. The 600-second timeout makes agents starve each other, though not the
owner.** `nice` fixes contention with the owner's game; it does not fix
Mesen's testrunner wall-clock kill. The signature is several savestates
failing to generate with `code=255` at once while the same ones succeed in
isolation. Lower `-j` and retry rather than debugging the generator. Bound a
full `make savestates` with `NINJAFLAGS=-j4` when other agents are live.

Also measured, and cheaper to read here than to rediscover: capture-calm does
not imply reload-calm, so every generator reloads its own capture and
verifies; a stale seeded fixture looks exactly like a product bug, so run
`--check-states` first; the battle Item cursor is a sum (`$8947` scroll +
`$894F` row); command row zero is not universally Fight; concurrent worktree
suites can SIGTERM each other's Mesen runs, so stagger the heavy runs, `nice`
everything, and keep to one heavy run at a time per machine.

## Canonical facts you should not re-derive

- **The fixture party is LOCKE, CELES, SABIN, EDGAR** (four through the
  Facility, three once the tube room takes Celes), measured at each fight's
  entry point in `design/wob-route.md`; the post-opera checkpoint's entry
  contract counts the `$1850` assignments, so a chain that loses members
  fails with an error rather than continuing.
- **Map 323 is Albrook; Vector is 242 and 253** (`design/vector-route.md`,
  both title index 49).
- **The item equip mask is `item_prop_en.dat` offset `+$01`, 16-bit, bit N =
  actor N** (`research/data-formats.md`). Byte `+$00` also looks like a mask
  and always claims Terra.
- **`monster_prop.dat` `+23` is absorb, `+25` is weak** — `check_boss_rows.py`
  and `check_break_reach.py` enforce doc/data agreement inside `make test`.
- **`OT6_BREAK_TICKS` is `$10`** (`ff6/src/battle/ot6_break.asm:1`) and gives
  a **2159-frame** window, about 36 s, not roughly one turn.
- **There are six multi-hit abilities in the game:** vanilla's Quadra Slam
  ×4, Quadra Slice ×4 and Empowerer ×2, plus v0.10's Pummel ×2, Bum Rush ×4
  and Drill ×2 (`Ot6HitCountTbl`, `ff6/src/battle/ot6_hitcount.asm`).
  `tools/audit_multihit.py` checks this and fails if it changes. **Hit count
  is authored in that table, not in the `.dat` files**, and each ability's
  power is divided by its count through a named splice, so reading a power
  byte out of `magic_prop_en.dat` or `item_prop_en.dat` gives the vanilla
  number rather than the shipped one.
- **SwdTech has a 1-BP floor**; there is no 0-BP tier. `Ot6BushidoTech`
  (`ff6/src/battle/ot6_bushido.asm:92-94`) clamps a stray 0 up, and boost 1/2/3
  selects Cyan's *top three learned* techs, so a given tier's price slides as
  he learns more.
- **A poison DOT tick chips a shield; Sap does not.** A tick is an ordinary
  poison hit with no attacker and chips exactly one axis. A broken monster
  takes no ticks at all.
- **The `event_triggers` fixed block has room for 2 more triggers
  game-wide** — 13 trailing `$FF` bytes in the block at `C40000`+`$1A10`, and
  a trigger is 5 bytes. (`npc_prop` has 76 trailing bytes ≈ 8 more NPC
  records, an upper bound, since an NPC record's last byte could legitimately
  be `$FF`.) Any further save-point work needs segment relocation first
  (`design/save-points-vector.md` §1).
- **The suite is self-registering**, discovered from each test's `-- @suite`
  marker; `tools/tests/suite.sh --list` reports what runs. Tests that load a
  deep story savestate join once `make savestates` has generated it.

## Working agreements

- Delegated work gets [agent-brief.md](agent-brief.md) included by reference.
  **Cite the copy in the agent's own worktree**, never the owner's checkout,
  which sits on the release branch he is playtesting and can be weeks stale.
- Agents commit to their own branches in revertible units, file exclusivity is
  "declare your hunks and expect merges", and regenerating a single savestate
  (`ninja -f build/build.ninja <state>`) is theirs. The full `make savestates`
  chain stays with the dispatcher.
- Agents report follow-ups; the dispatcher files issues.
- Parallel work goes in separate git worktrees; `tools/worktree-setup.sh`
  seeds the ROM, emulator links, states, and the ninja build log. **Worktrees
  live under `.claude/worktrees/<name>` inside the repo**, never as siblings
  of `~/ot6` or anywhere else in the home directory.
- Keep `main`, the integration branch, and the owner's checkout
  fast-forwarded together at every checkpoint where the tests are green.
- Commit messages here run long and explain why the change was made,
  including what was ruled out. Match that.

## The most common failure mode

Nearly every wrong turn in this project has been the same one: reasoning used
in place of looking, when looking was cheap. The two most expensive cases both
read an absence as information. One was a symbol lookup that returned the
wrong module's address without reporting an error, so an instrumentation
window never closed and every later event was attributed to it (trap 3). The
other was a design table that stated intent as shipped fact for months because
nobody had enumerated the records. One grep or one audit script would have
settled either.

If a conclusion requires believing a documented measurement is wrong, the
instrumentation is more likely to be at fault than the record. Verify with the
cheapest available look: a probe, a byte read, a re-run. Prefer the mechanical
checks to reasoning: the state-write checker and its only-shrinks list, the
equipment audit, `compose.py --check-states` before debugging any red test,
the runtime write guard, and `make savestates NINJAFLAGS="-k 0"` to enumerate
blockers rather than hitting them one per run.

The rules in CONTRIBUTING under "Prove the code is correct" exist because of
specific incidents.
