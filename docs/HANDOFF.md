# Hard-won facts

The things that cost real time to rediscover. Start with
[README.md](../README.md) for what OT6 is, [CONTRIBUTING.md](../CONTRIBUTING.md)
for the house rules, and [ROADMAP.md](ROADMAP.md) for the release plan.

## Doctrine (measured; do not re-derive)

- **fieldCare** drives the real Item→use→target windows; A on the field
  item list PICKS A SLOT UP, only a second A on the same slot uses it.
  Its world-map exit is BROKEN (careBackOnMap's witness passes a moment
  that isn't "world module running") — care on the field, not the world,
  until fixed. Its exit also reads a one-frame transient and can leave the
  menu open; it wants a debounce.
- **`honest="flee"` vs `"tactical"` vs `true`**: fleeing is standing still
  while the formation takes free rounds; blind-A `honest=true` is a
  foot-gun that stalls or wipes on any leg that can draw an encounter.
  `M.FLEE_CAP` default 1800, per-call `opts.fleeCap` (the South Figaro
  escape route uses 420). Cave pincer formations cannot be fled at all —
  FF6's own rule.
- **Rows**: `$B3 = $FF` for every command and only the weapon swing
  clears it — Tools, Magic, Blitz, SwdTech, Throw, Steal are row-exempt.
  Where damage is break-driven, back row wins; where the chipper is a
  weapon swing, it loses (South Figaro vs Phantom Train, both measured).
  Rows are persistent state — set them per leg on purpose.
- **The equip audit** (`tools/audit_equipment.py`, a `make test` gate with its
  own shrink-only story-waiver list): any red leg gets checked against it
  BEFORE being called balance.
- **A party wipe must say so**: the navigators' `M.partyWiped()` canary
  misses IN-BATTLE wipes (`$1600` keeps pre-battle HP); a battle-module
  witness (`$3BF4` under `battleLoadStarted()`) is the filed fix. Three
  wipes have impersonated stuck navigators.
- **Retry ladders are 3 attempts, phase-spread by 37 frames** (battle RNG
  seed = frame phase at init). Widening a ladder until it gets lucky is not
  acceptable; a ladder that loses all three reports a finding.
- **Every anchor is minted through the game's own save routine, never
  synthesised.**

## The things that will cost you a day

**1. Module WRAM ownership lies to you.** `$7E3BF4` is the party battle-HP
table only while the battle module owns that RAM. `$021f` has exactly four
writers, all menu lifecycle — forcing `ZMENUSTATE` mid-flow leaves corrupted
menu tasks running and the cell reads as overlaid. Ask which module owns a
`$02xx` cell before trusting it, verify by instrumenting (block moves are
invisible to Mesen write callbacks — sample, don't watchpoint), and witness
persistent facts through SRAM (`$307ff0`, the codex pages) when a
context-free channel exists.

**2. Cycle budgets are PER SITE, and only one site has a measured number.**
`Ot6BgHud_ext` runs from `WaitFrame` immediately after `WaitVblank` returns,
once per battle frame, and has under 80 cycles of slack — possibly under 20.
Measured with bare-NOP controls carrying no feature at all: 12 NOPs pass, 80
NOPs fail, and the penalty **saturates** (20 and 110 cycles both cost the
same 163 frames). The symptom is not a crash or a wrong result — it is
everything running ~10% slower, which flips timing-sensitive tests elsewhere
and looks like their bug. Gate work there INLINE at the call site; a `jsr`
into a proc that early-outs is already over the line.

12 NOPs being safe *there* does not make 12 NOPs safe anywhere: the same
bare-NOP control in bank `$C2`'s **action** path fails at **five** NOPs, so
that path's margin is under 10 cycles. But `$C2` growth per se is not the
trigger — four `$C2` call sites were added (`battle_main.asm:514`, `:3409`,
`:4152`, `:14652`, plus `Ot6RecheckMagic` at `:14715`) with no degradation at
all. **Hypothesis, UNVERIFIED:** what costs is per-battle-*frame* code, not
per-action or per-menu-redraw code; nobody has run the NOP control at those
four sites, and that is the experiment that would settle it. The full record
is the block comment over `OT6_BRKLIVE` in
`ff6/src/battle/ot6_memory.inc`. (Distinct from the vblank-TRANSFER budget,
which is about VRAM words, not cycles.)

**3. `H.sym` resolves a duplicate symbol name silently wrong.**
`parse_dbg_syms` (`tools/tests/lib/compose.py:218-250`) walks `ff6-en.dbg`
taking **the first** `type=lab` record for each wanted name and then skips
that name forever (`if name in out: continue`, `:241`). `ExecCmd` is defined
twice — `$C09B1B` and the battle one at `$C213E6` — so a probe that hooks
`ExecCmd` gets the wrong module's address, its instrumentation window never
closes, and every later event is misattributed. Silently. Before you hook a
symbol by name, check how many label records in the `.dbg` carry it; if more
than one, use the address directly or attribute by something else.

**4. A mismatched ROM/fixture pair presents as "timeout waiting for main
menu".** Savestates are genuinely ROM-coupled. When a fixture was minted from
a different ROM than the one under test, the failure you see is a menu that
never opens — nothing says "stale state". If a menu drive times out and you
have recently changed ROM-affecting source, re-mint before you debug the
menu. `tools/worktree-setup.sh` prints a matching warning when it seeds
states minted on a different branch — read it.

**5. NPC record order is NPC identity.** Event scripts address NPCs as
{map, index-within-block}, so a record inserted ahead of an existing NPC
renumbers everything after it. **Append, never insert.**

**6. `navTo` lands at rest; a tile that takes the party away is entered with a
held press, not a `navTo` whose goal it is.** Position samples are only valid
at rest on a tile (`tools/tests/lib/ot6_field.lua:459`, `:616`).

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

Also paid for, and cheaper to read than to rediscover: capture-calm does NOT
imply reload-calm — every mint reloads its own capture and verifies; a stale
seeded fixture reads exactly like a product bug (`--check-states` first); the
battle Item cursor is a SUM (`$8947` scroll + `$894F` row); command row zero
is not universally Fight; concurrent worktree suites can SIGTERM each other's
Mesen runs (stagger heavy gates, `nice` everything, one heavy gate at a time
per machine).

## Canonical facts you should not re-derive

- **The fixture party is LOCKE, CELES, SABIN, EDGAR** (four through the
  Facility, three once the tube room takes Celes), measured per doorstep in
  `design/wob-route.md`; the post-opera anchor's entry contract counts the
  `$1850` assignments so a chain that loses members fails loudly.
- **Map 323 is Albrook; Vector is 242 and 253** (`design/vector-route-recon.md`,
  both title index 49).
- **The item equip mask is `item_prop_en.dat` offset `+$01`, 16-bit, bit N =
  actor N** (`research/data-formats.md`). Byte `+$00` always looks like a mask
  and always claims Terra.
- **`monster_prop.dat` `+23` is absorb, `+25` is weak** — `check_boss_rows.py`
  and `check_break_reach.py` enforce doc/data agreement inside `make test`.
- **`OT6_BREAK_TICKS` is `$10`** (`ff6/src/battle/ot6_break.asm:1`) and buys
  a **2159-frame** window, ~36 s. Not "roughly one turn".
- **There are exactly three multi-hit abilities in the game** — Quadra Slam
  ×4, Quadra Slice ×4, Empowerer ×2. `tools/audit_multihit.py` proves it and
  fails if that changes.
- **SwdTech has a 1-BP floor** — there is no 0-BP rung. `Ot6BushidoTech`
  (`ff6/src/battle/ot6_kits.asm:74-79`) clamps a stray 0 up, and boost 1/2/3
  selects Cyan's *top three learned* techs, so a given rung's price slides as
  he learns more.
- **A poison DOT tick chips a shield; Sap does not.** A tick is an ordinary
  poison hit with no attacker and chips exactly one axis. A broken monster
  takes no ticks at all.
- **The `event_triggers` fixed block has room for 2 more triggers
  game-wide** — 13 trailing `$FF` bytes in the block at `C40000`+`$1A10`, and
  a trigger is 5 bytes. (`npc_prop` has 76 trailing bytes ≈ 8 more NPC
  records, an upper bound — an NPC record's last byte could legitimately be
  `$FF`.) Any further save-point work needs segment relocation first
  (`design/save-points-vector.md` §1).
- **The suite is self-registering**, discovered from each test's `-- @suite`
  marker; `tools/tests/suite.sh --list` reports what runs. Frontier-gated
  tests join once `make frontier` has minted their fixtures.

## Working agreements

- Delegated work gets [agent-brief.md](agent-brief.md) included by reference —
  **cite the copy in the agent's own worktree**, never the owner's checkout,
  which sits on the release branch he is playtesting and can be weeks stale.
- Agents commit to their own branches in revertible units, file exclusivity is
  "declare your hunks and expect merges", and targeted re-mints
  (`ninja -f build/build.ninja <state>`) are theirs. The full frontier chain
  stays with the dispatcher.
- Agents report follow-ups; the dispatcher files issues.
- Parallel work goes in separate git worktrees; `tools/worktree-setup.sh`
  seeds the ROM, emulator links, states, and the ninja build log. **Worktrees
  live under `.claude/worktrees/<name>` inside the repo**, never as siblings
  of `~/ot6` or anywhere else in the home directory.
- Keep `main`, the integration branch, and the owner's checkout
  fast-forwarded together at every gate-green checkpoint.
- Commit messages here run long and explain the why, including what was ruled
  out. Match that.

## The failure mode worth knowing about

Nearly every wrong turn in this project has been the same one: **reasoning
substituted for looking, when looking was cheap.** Both of the most expensive
entries in the case file are about *absence* being read as information — a
symbol lookup that silently returned the wrong module's address, so an
instrumentation window never closed and every later event was attributed to
it (trap 3); and a design table that stated intent as shipped fact for months
because nobody had enumerated the records. In both, one grep or one audit
script would have settled it.

If a conclusion requires believing a documented measurement is wrong, the odds
strongly favor your instrumentation over the record — verify with the cheapest
possible look (a probe, a byte read, a re-run). Trust the mechanical anchors
over reasoning: the state-write checker and its shrink-only list, the
equipment audit, `compose.py --check-states` before debugging any red test,
the runtime write gate, and `make frontier NINJAFLAGS="-k 0"` to enumerate
blockers rather than hitting them one per run.

The rules in CONTRIBUTING under *"your job is not to write correct code, it
is to prove the code is correct"* exist because of specific incidents.
