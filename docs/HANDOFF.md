# Handoff — state of play

Written 2026-07-27, rewritten late the same day after the backlog burn-down.
Update this file when you land something that changes the picture; it is
meant to be the one place that says where things are.

Start with [README.md](../README.md) for what OT6 is,
[CONTRIBUTING.md](../CONTRIBUTING.md) for the house rules, and
[ROADMAP.md](ROADMAP.md) for the release plan. This file is the delta: what is
true right now and what will cost you a day if you do not know it.

## Where the project is

**v0.8 is released** — "the economy bites". Three releases shipped in three
days, and none of the last two moved the playable frontier: the loop is now
*owner plays → files findings → themed release folds them in*, which is
recorded in ROADMAP as the deliberate cadence. Milestones are named for
their theme; the frontier push to the end of the World of Balance is
**v0.10**'s job. Note 0.9 is followed by 0.10, not 1.0 — the end of WoB is
about halfway through the game and the World of Ruin has not been started,
so 1.0 (where saves become forward-compatible) is far off.

What v0.8 shipped: every kit price recalibrated to vanilla's own ruler
(a spell costs 8-20% of the pool at the level it arrives — the number this
design had never measured), ultimates anchored at 99 (which turns out to be
vanilla's own dearest spell, Quick), the break flash and sound, Gau's Fight
with Leap sharing the Fight row on the Veldt, magicite as gear packages in
FF6's own two-byte stat encoding, Steal at 4, and three menu pages that had
been lying to the player since v0.5.

**The frontier stands at Terra's return (v0.6's line).** The Sealed Gate
route is minted through the airship crash — anchors F through I with
measured entry/exit contracts — and the banquet is fully decoded with its
score tier settled at >=67. Legs J-K are what remain, and they are v1.0's.

**The rules were audited and loosened** (`rules-audit.md`, at the owner's
request). Agents commit to their own branches now, file exclusivity is
down to "declare your hunks, expect merges", and targeted re-mints are
theirs. The four that stayed are all about not fooling ourselves, and they
each caught something real the day they were reaffirmed.

## Open work, in the order I would take it

1. **Cut anchors B–F and convert the legs** — the remaining #25 payoff.
   `design/save-points-vector.md` §5 maps the band onto six boundaries; each
   needs a gen that drives to the save point, saves through the real UI, and
   exports the battery payload (the `gen_post_opera_anchor` pattern). In the
   graph, converting a leg is `prev=` → `anchor=` on one line. Every anchor
   must be minted through the game's own save routine, never synthesised.
2. **#29 — the `$021f` context audit.** `Ot6CodexActive` trusts a cell that is
   `wSaveSlotToLoad` only while the menu owns the `$0200` region. Measurements
   and scope are in the issue; the codex battle path is the part that matters.
3. **#15's release-gate residue**: save/reset/load validation at the new 273
   save point, the v0.6 human playthrough, and release notes.
4. **Sketch stays unfixed, by explicit owner decision (2026-07-28).** #28
   briefly made it a v0.8 gate; that reversed the owner's standing call
   without sign-off and is itself reversed — see CONTRIBUTING. v0.8 ships
   it documented in the release notes, not fixed.

## The things that will cost you a day

**1. Module WRAM ownership lies to you — and so did this trap's first
draft.** `$7E3BF4` is the party battle-HP table only while the battle
module owns that RAM. `$021f` was reported here as overlaid by the world
module after any menu close; the #29 audit (2026-07-28,
`research/codex-context-audit.md`) disproved that mechanism — the cell has
exactly four writers, all menu lifecycle, and the overlaid values came
from a test forcing `ZMENUSTATE` mid-flow, leaving corrupted menu tasks
running. Both lessons stand: ask which module owns a `$02xx` cell before
trusting it, verify the answer by instrumenting (block moves are invisible
to Mesen write callbacks — sample, don't watchpoint), and witness
persistent facts through SRAM (`$307ff0`, the codex pages) when a
context-free channel exists.

**2. `Ot6BgHud_ext` has under 80 cycles of slack per battle frame, and
possibly under 20.** It runs from `WaitFrame` immediately after
`WaitVblank` returns, so work added there can make the iteration miss
vblank and cost a whole extra hardware frame. Measured 2026-07-29 with
BARE-NOP CONTROLS carrying no feature at all: 12 NOPs pass, 80 NOPs fail,
and the penalty saturates (20 and 110 cycles cost the same 163 frames).
The symptom is not a crash or a wrong result — it is everything running
~10% slower, which flips timing-sensitive tests elsewhere and looks like
their bug. If you must add work there, gate it INLINE at the call site;
a `jsr` into a proc that early-outs is already ~20 cycles and over the
line. (Distinct from the vblank-TRANSFER budget in trap 6, which is about
VRAM words, not cycles.)

**3. NPC record order is NPC identity.** Event scripts address NPCs as
{map, index-within-block}, so a record inserted ahead of an existing NPC
renumbers everything after it — the first 273 save-sparkle attempt shifted
NUMBER_024 to index 1 and the post-battle cleanup cleared the sparkle instead.
Append, never insert. The mint caught it two legs downstream, which is the
system working.

**4. `navTo` lands at rest (#22); a tile that takes the party away is entered
with a held press, not a `navTo` whose goal it is.** Generators relying on the
old mid-glide handoff still surface occasionally.

**5. `event_main.asm` is a dump of separately-addressed scripts.** Adjacency
means nothing. Party composition is runtime state: read `$1850` at a fixture.
`bosses-wob.md` is authoritative on party composition.

**6. `LoadMagicProp` fills one shared buffer** — freeze the rest of the party
when measuring an ability, or an ally's action mid-window reads as "the summon
was free". Documented at `freezeOthers`.

## Canonical facts you should not re-derive

- **The fixture party is LOCKE, CELES, SABIN, EDGAR** (four through the
  Facility, three once the tube room takes Celes), measured per doorstep in
  `wob-route.md`; the post-opera anchor's entry contract counts the `$1850`
  assignments so a chain that loses members fails loudly (#21).
- **Map 323 is Albrook; Vector is 242 and 253.**
- **The item equip mask is `item_prop_en.dat` offset `+$01`, 16-bit, bit N =
  actor N** (`research/data-formats.md`). Byte 0 always looks like a mask and
  always claims Terra.
- **`monster_prop.dat` `+23` is absorb, `+25` is weak** — `check_boss_rows.py`
  and `check_break_reach.py` now enforce doc/data agreement in `make test`.
- **The `event_triggers` fixed block has room for 2 more triggers game-wide**
  (was 3; the 273 save point spent one). The deferred Opera-band save list
  needs segment relocation first (`design/save-points-vector.md` §1).

## Working agreements

- Delegated work gets [agent-brief.md](agent-brief.md) included by reference —
  **cite the copy in the agent's own worktree, never `/Users/mtklein/ot6/docs/`.**
  The owner's checkout sits on the release branch he is playtesting, so a
  doc read from it can be weeks stale; on 2026-07-29 every agent that day
  read a brief from two days earlier and followed rules already replaced.
  **Revised 2026-07-29** after `rules-audit.md`: agents commit to their own
  branches in revertible units, file exclusivity is dropped to "declare your
  hunks and expect merges", and targeted re-mints are theirs. The owner's
  framing: occasional rework from an unexpected conflict is an accepted
  cost as long as it stays unusual, and agents should work how they work
  best while we adapt the tools to suit.
- Agents report follow-ups; the dispatcher files issues. `spawn_task` is denied
  in `.claude/settings.json`.
- Parallel work goes in separate git worktrees;
  `tools/worktree-setup.sh` seeds the ROM, emulator links, states, and the
  ninja build log. **Worktrees live under `.claude/worktrees/<name>` inside
  the repo (owner rule, 2026-07-28: never as siblings of `~/ot6` or
  anywhere else in the home directory)** — compose.py's nested-checkout
  refusal already models exactly that layout.
- Commit messages here run long and explain the why, including what was ruled
  out. Match that.

## The failure mode worth knowing about

Nearly every wrong turn in this project has been the same one: **reasoning
substituted for looking, when looking was cheap.** Today's additions to the
case file: a test that passed for months because a module-overlay variable
coincidentally held the expected value (`codex_saveas`), and a save-point
insert whose bug was caught not by review but by the mint two legs
downstream. The rules in CONTRIBUTING under *"your job is not to write correct
code, it is to prove the code is correct"* exist because of specific
incidents. `make smoke` and the ninja graph exist to make looking cheap enough
that it is the default.
