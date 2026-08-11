# Facts that are expensive to rediscover

These cost real time to work out the first time. Start with
[README.md](../README.md) for what OT6 is, [CONTRIBUTING.md](../CONTRIBUTING.md)
for the house rules, and [ROADMAP.md](ROADMAP.md) for the release plan.

## Measured facts (do not re-derive)

- **fieldCare** drives the real Item→use→target windows. On the field item
  list, A picks a slot up; only a second A on the same slot uses it.
  Its world-map exit is broken: `careBackOnMap`'s check passes at a moment
  that is not "world module running". Use care on the field, not on the
  world map, until that is fixed. Its exit also reads a one-frame transient
  and can leave the menu open; it needs a debounce.
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
  Rows are persistent state, so set them deliberately per segment.
- **The equip audit** (`tools/audit_equipment.py`, a `make test` check with its
  own only-shrinks story-waiver list): check any red segment against it
  before calling the result balance.
- **A party wipe must be reported as a wipe.** The navigators'
  `M.partyWiped()` check misses in-battle wipes, because `$1600` keeps
  pre-battle HP. The filed fix is a battle-module check (`$3BF4` under
  `battleLoadStarted()`). Three wipes have been mistaken for stuck
  navigators.
- **Retry ladders are 3 attempts, phase-spread by 37 frames** (battle RNG
  seed = frame phase at init). Do not widen a ladder until it succeeds by
  chance; a ladder that loses all three attempts is reporting a finding.
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

**2. Cycle budgets are per site, and only one site has a measured number.**
`Ot6BgHud_ext` runs from `WaitFrame` immediately after `WaitVblank` returns,
once per battle frame, and has under 80 cycles of slack, possibly under 20.
Measured with bare-NOP controls carrying no feature at all: 12 NOPs pass, 80
NOPs fail, and the penalty saturates (20 and 110 cycles both cost the
same 163 frames). The symptom is not a crash or a wrong result. Everything
runs about 10% slower, which flips timing-sensitive tests elsewhere and looks
like a bug in those tests. Keep work there inline at the call site; a `jsr`
into a proc that early-outs is already too expensive.

12 NOPs being safe at that site does not make 12 NOPs safe anywhere else: the
same bare-NOP control in bank `$C2`'s **action** path fails at **five** NOPs,
so that path's margin is under 10 cycles. Growth in `$C2` by itself is not
the trigger: four `$C2` call sites were added (`battle_main.asm:514`, `:3409`,
`:4152`, `:14652`, plus `Ot6RecheckMagic` at `:14715`) with no degradation at
all. **Hypothesis, UNVERIFIED:** the cost comes from per-battle-*frame* code
rather than per-action or per-menu-redraw code. Nobody has run the NOP control
at those four sites, and that is the experiment that would settle it. The full
record is the block comment over `OT6_BRKLIVE` in
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
