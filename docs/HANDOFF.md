# Handoff — state of play

Written 2026-07-27, rewritten late the same day after the backlog burn-down.
Update this file when you land something that changes the picture; it is
meant to be the one place that says where things are.

Start with [README.md](../README.md) for what OT6 is,
[CONTRIBUTING.md](../CONTRIBUTING.md) for the house rules, and
[ROADMAP.md](ROADMAP.md) for the release plan. This file is the delta: what is
true right now and what will cost you a day if you do not know it.

## Where the project is

**v0.5 is released** (Opera complete, Setzer joined, Blackjack acquired) and
**still not human-playtested** — that gate is the owner's, and two releases of
unvalidated frontier should not stack.

**v0.6 is in progress and the backlog is clean.** In one day the open-issue
list went from eight standing trackers to four scoped items: the full frontier
re-minted from power-on through Terra's return (114 states, the Vector band's
first honest mint in this tree), the Vector-band break floor closed out with an
encounter/party reachability gate in `make test` (#11), one authored save point
landed before Number 024 with the rest of the band's cadence deliberately
declined on recorded reasoning (#10, `design/save-points-vector.md`), the esper
detail page now shows the while-worn stat mod (#27), the destructive-bug policy
is written into CONTRIBUTING (#13; Sketch itself stays, see below), and tests can no
longer reference fixtures by absolute path at all (#26).

**The frontier build system is ninja now (#25).** `make frontier` is a thin
wrapper: `tools/tests/frontier_graph.py` declares the graph as data,
`tools/tests/lib/frontier_ninja.py` emits `build/build.ninja`, and content
staleness is ninja `restat` latches — the stamp-plus-`touch` dance, the
generated deps include, and `frontier_deps.sh` are gone. The failure class
where "rom content changed" printed while stale-ROM savestates booted anyway
(observed twice on 2026-07-27) has no mechanism left to occur in. Battery
anchors are keyed (`tools/tests/anchors/<key>/`), legs declare entry/exit
contracts as data (`lib/ot6_contract.lua`), an anchor whose
`persistent_layout` a leg does not declare is refused before the emulator
boots, and `make anchor-negatives` (in `make test`) proves both refusal paths
stay loud.

`make test` is the gate and must be green before anything lands.
`make -j10 smoke` is still the fast falsification loop (~80s).

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

**2. NPC record order is NPC identity.** Event scripts address NPCs as
{map, index-within-block}, so a record inserted ahead of an existing NPC
renumbers everything after it — the first 273 save-sparkle attempt shifted
NUMBER_024 to index 1 and the post-battle cleanup cleared the sparkle instead.
Append, never insert. The mint caught it two legs downstream, which is the
system working.

**3. `navTo` lands at rest (#22); a tile that takes the party away is entered
with a held press, not a `navTo` whose goal it is.** Generators relying on the
old mid-glide handoff still surface occasionally.

**4. `event_main.asm` is a dump of separately-addressed scripts.** Adjacency
means nothing. Party composition is runtime state: read `$1850` at a fixture.
`bosses-wob.md` is authoritative on party composition.

**5. `LoadMagicProp` fills one shared buffer** — freeze the rest of the party
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

- Delegated work gets [agent-brief.md](agent-brief.md) included by reference.
- Agents report follow-ups; the dispatcher files issues. `spawn_task` is denied
  in `.claude/settings.json`.
- Parallel work goes in separate git worktrees with disjoint file ownership;
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
