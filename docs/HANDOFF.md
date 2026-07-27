# Handoff — state of play

Written 2026-07-27. Update this file when you land something that changes the
picture; it is meant to be the one place that says where things are.

Start with [README.md](../README.md) for what OT6 is,
[CONTRIBUTING.md](../CONTRIBUTING.md) for the house rules, and
[ROADMAP.md](ROADMAP.md) for the release plan. This file is the delta: what is
true right now and what will cost you a day if you do not know it.

## Where the project is

**v0.5 is released** (Opera complete, Setzer joined, Blackjack acquired).
**v0.6 is in progress** — the Vector / Magitek Research Facility frontier mints
end to end, and the minecart completes. Number 128 was never a balance problem;
it was three characters' work being done by one, which is now fixed.

`make test` is the gate and must be green before anything lands.
`make frontier-test` re-mints the chain and runs the frontier-gated tests too.

## The five things that will cost you a day

**1. `make -j10 smoke` is the fast falsification loop. Use it first.**
A library change does not need a full re-mint to falsify. Savestates are tied to
ROM contents, so for a *lib-only* change the existing states still boot and any
generator can be run directly. `smoke` runs the seven generators that have
historically caught harness regressions in ~80 seconds, against an hour-plus for
`make frontier`. Three wrong guesses at one predicate cost three serial re-mints
before this existed. `make frontier` remains authoritative; smoke is what you run
between guesses.

**2. `$7E3BF4` is the party battle-HP table only while the battle module owns
that RAM.** Every other module scribbles those bytes. `battleLoadStarted()` now
judges the *shape* of the whole table — every word a plausible HP (0, or
1..9999) and someone alive — because three simpler rules each shipped and each
cost a full re-mint. The measured shapes and the three dead ends are documented
at the function in `tools/tests/lib/ot6.lua`. Do not "simplify" it.

**3. `navTo` lands at rest now (#22).** It used to hand the party over
mid-glide, and several generators silently depended on that. The rule that
falls out: *a tile that takes the party away is entered with a held press, not
with a `navTo` whose goal it is.* Three generators were found relying on the old
behaviour; assume more exist.

**4. `event_main.asm` is a dump of separately-addressed event scripts.**
Adjacency in that file means nothing about execution order — fourteen script
labels sat between two lines that were confidently presented as consecutive.
Party composition in particular is runtime state: read `$1850` at a fixture.
`bosses-wob.md` is authoritative on party composition and was right the whole
time it was being derived wrongly from the dump.

**5. `LoadMagicProp` fills one shared buffer.** An ally's action resolving inside
your caster's window overwrites the record mid-resolution, which reads as "the
summon charged 0 MP and applied no status" — summons look free. Freeze the rest
of the party when measuring. Documented at `freezeOthers`.

## Canonical facts you should not re-derive

- **The fixture party is LOCKE, CELES, SABIN, EDGAR**, seated at the Zozo
  `party_menu`. Four through the Facility, three once the tube room takes Celes.
  Measured per doorstep in `wob-route.md`. `gen_vector_doorstep` asserts the
  count of nonzero `$1850` entries is 4, so a chain that silently loses members
  fails loudly.
- **Map 323 is Albrook.** Vector is 242 and 253. A fixture called
  `vector_arrival` minted Albrook and passed green for a week.
- **The item equip mask is `item_prop_en.dat` offset `+$01`, 16-bit, bit N =
  actor N.** Byte 0 reads `type | mask<<8`, which always looks like a mask and
  always claims Terra; that misreading cost two investigations. Recorded in
  `research/data-formats.md`.
- **`monster_prop.dat` `+23` is absorb, `+25` is weak.** Check both before
  authoring an element row — Ultros ④ absorbs water, and adding the water its
  design story implied would have healed him. `battle_breaktbl` now asserts this
  for the whole `Ot6ElemAddTbl` automatically.

## Open work, in the order I would take it

1. **#25 — leg fixtures on battery anchors, plus the ninja migration.** The
   structural fix for everything above. Today cost four serial re-mints; a ROM
   byte currently invalidates 100 sequential states. Battery saves survive ROM
   changes (proven in #9), `mint_anchor` already exists, and `make -jN` already
   parallelises where the graph allows — the blocker is the serial trunk. Design
   is in `leg-fixtures.md`. The ninja part is folded in because the Makefile
   already bypasses make's mtime model and keeps biting us.
2. **#26 — tests hardcoding absolute `/Users/mtklein/ot6` paths.** Small, and a
   prerequisite for #25 working across parallel worktrees.
3. **#10 — save points.** Now safe to add: #18 fixed a bug where saving could
   silently eat a slot. Also supplies #25's leg boundaries.
4. **#11 next band · #27 esper menu copy · #13 write down the destructive-bug
   policy that #18 already applied ahead of · #20 remaining doc/data
   mismatches.**

## Outstanding for the owner

**v0.5 has not been playtested.** That was a deliberate owner decision at the
time, not an oversight. `playtest-v0.5.md` has the focused questions. Two
releases of unvalidated frontier should not stack.

## Working agreements

- Delegated work gets [agent-brief.md](agent-brief.md) included by reference —
  standing rules do not depend on whoever writes the dispatch remembering them.
- Agents report follow-ups; the dispatcher files issues. `spawn_task` is denied
  in `.claude/settings.json` so subagents cannot triage at the owner directly.
- Parallel work goes in separate git worktrees with disjoint file ownership.
  `make rom` writes one shared `build/ot6.sfc`, so two agents in one tree
  collide. Worktrees need the base ROM copied in — it is gitignored.
- Commit messages here run long and explain the why, including what was ruled
  out. Match that.

## The failure mode worth knowing about

Nearly every wrong turn in this project has been the same one: **reasoning
substituted for looking, when looking was cheap.** A design doc in this repo held
the right answer while it was being derived wrongly from source. A screenshot's
byte count contradicted the very note being cited for it. A variable was
"isolated" against a tree carrying two other changes.

The rules in CONTRIBUTING under *"your job is not to write correct code, it is to
prove the code is correct"* exist because of specific incidents, not as
aspiration. `make smoke` exists to make looking cheap enough that it is the
default.
