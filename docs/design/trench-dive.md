# The Serpent Trench — Aspik's dying counter, and the one verb that draws it (#194)

Authored 2026-09-18 from `tools/tests/trenchdivelab.py` (the lab; its
docstring carries the policies), the v0.19 tree's own
`build/states/sabin_done.log`, and a six-seed spread of `gen_sabin_trench`
over seven policies — five cuts of the fight driver and the ROM on the
shipped generator, and two candidate levers. Every number below is quoted
from a retained log under `build/lab/trench-dive/` — the lab keeps every
attempt, failures included. `python3 tools/tests/trenchdivelab.py aggregate`
prints them all; `build/lab/trench-dive/aggregate.txt` is that output,
`counters-before.txt`, `counters-after.txt` and `counters-noblitz.txt` the
who-provoked-what roll-ups, and `table-head-seed00.txt` /
`table-focus-seed00.txt` the per-battle tables for the seed the route
itself regenerates on.

## What the build says

`sabin_done` passes and burns its own retry ladder doing it
(`build/states/sabin_done.log`, `tools/audit_boost.py ... -v`):

```
Boost audit: 12 party death(s), 5 holding >= 3 BP, 2 wipe(s) across 1 logs.
sabin_done   fight  5 f+930  e0 260/363 bp2  slot 5 cmd $0C atk $B9
sabin_done   fight  5 f+6529 e1  18/358 bp2  slot 2 cmd $00 atk $EE   -> WIPE
sabin_done   fight  8 ... 5 more deaths ...                           -> WIPE
sabin_done   fight 10 f+1053 e0 325/363 bp2  slot 3 cmd $0C atk $B9 ONE ACTION
```

Three dive attempts, the third one lands. The ladder has no fourth.

## The cast

The dive's battles draw three formations, decoded from the tree's own
`battle_monsters.dat` and confirmed by species word ($57C0) at every
battle-start line the lab writes:

| formation | slots | HP each |
|---|---|---|
| 47 | Actaneon x3 | 230 |
| 86 | Anguiform + Actaneon + Aspik | 315 / 230 / 220 |
| 67 | Actaneon x3 + **Aspik x2** | 230 / 220 |

The party is three: SABIN (L14, **363** HP), CYAN (L14, 358), GAU (L15,
394), all front row, and GAU with nothing equipped at all, which is where
vanilla leaves him (`table-head-seed00.txt`'s party line).

`atk $B9` is **Giga Volt** and `cmd $0C` is Lore, which is the command a
monster's scripted cast rides. `atk $EE`/`$EF` are Battle and Special, the
plain physicals. `atk $8E` is **Aqua Rake**, which Anguiform casts when it
is the last one standing (`if_num_monsters 1`, ai_script.asm `; anguiform`).

## What is killing them

**Aspik's retaliation script**, `ai_script.asm` `; aspik`:

```
        end                              <- the main script ends here
        if_cmd FIGHT
                attack BATTLE, NOTHING, NOTHING
                end_if
        if_hit
                attack GIGA_VOLT, NOTHING, NOTHING
        end_retal
```

Aspik's *main* script never casts. Every Giga Volt in this segment is a
**counter**, and which counter it is depends on the verb that hit it. The
AI walker decides which: `AICmd_fc` enters a block whose condition holds,
and the `end_if` that closes it is `AICmd_fe`, which sets `$f5 = $ff` and
**ends the script** — so the first block that matches is the only one that
runs. A condition that misses falls through `conditionmiss` to the next
block instead (all three in `battle_main.asm`). So a **Fight** takes the
first branch and is answered with Aspik's own Battle — and Aspik has 2
battle power — while **anything else** falls through to `if_hit` and is
answered with Giga Volt.

Measured rather than read off the script. Over the whole 30-run spread
(`counters-before.txt`), counting only party actions into a formation that
carries an Aspik:

| verb | actions | Giga Volts drawn |
|---|---|---|
| Fight | **524** | **0** |
| Blitz (SABIN's Pummel, `$5D`) | **123** | **34** |

and the roll-up's own last line:

```
the verb immediately before each Giga Volt: Blitz x34
```

Giga Volt is lightning, spell power 110, single target
(`magic_prop_en.dat` `$B9`: targeting `$63`, element `$04`, power `$6E`),
and it comes back at the character who threw the Pummel. The largest one
the lab caught took **363** off a SABIN at **363/363**
(`preprice/seed25.log`, `head/seed25.log`) — a **one-shot from full**. The
ceiling is higher than that; 363 is only where SABIN stops.

Pummel is single-target with `AUTO_CONFIRM` (`$5D` targeting `$53`), so
SABIN does not choose who he hits and the driver cannot steer him: the log
line is `Blitz $5D committed from the list (no target select)`. In
formation 67 two of the five bodies are Aspiks.

### Seed 0, fight 5, in three lines

`table-head-seed00.txt`, and the raw trace in `head/seed00.log`:

```
[fight] 5 a1 f17874 form=s1=$005E:230+s2=$005E:230+s3=$005E:230+s4=$0059:220+s5=$0059:220
[act] f18670 slot0 char5 Blitz($0A) atk=$5D bp=1 dmg=220
[act] f18932 mon5  char99 Lore($0C) atk=$B9 took=260 hurt=e0-260
```

SABIN's 1-BP Pummel does **220**, which is exactly an Aspik's entire HP.
Slot 5 answers with Giga Volt and **acts twice in the whole fight** —
the counter and one no-op — while slots 1-4 act eight and nine times each.
It was the dying counter of the monster he had just killed.

SABIN is dead at battle tick 930, and the rest of the fight is the
consequence: two members, **36 monster actions**, 925 HP off the party, a
Fenix Down that raises him to 45/363 into a formation whose smallest hit is
19 and whose largest is over 300, and the wipe. The same shape again in
fight 8 (5 deaths) and fight 10.

Across `head`'s six seeds: **nine fights had a party death, and seven of
the nine first deaths were a Giga Volt.** The other twelve deaths are
ordinary physicals — Battle x5, Special x3, Aqua Rake x3, one unattributed
— landing on a party that is already a member short.

**So the first death is not the accepted rare-spectacular class.** It is
not a bad draw and it is not under-levelling in the sense the owner's
one-shot rule means: it is the same avoidable trade, made the same way,
every time SABIN reaches for his Blitz in front of a jellyfish.

## Is it a regression from this cycle?

**No.** Four cuts of the driver, the same fixture, the same ROM, the same
six shifts (`aggregate.txt`):

| policy | driver | pass | deaths | banked | wipes | Fenix | mean frames | attempts 1/2/3 |
|---|---|---|---|---|---|---|---|---|
| `head` | today's | 6/6 | 19 | 7 | 3 | 9 | 37,927 | 4/1/1 |
| `pre235` | before #235 | 6/6 | 19 | 7 | 3 | 10 | 38,365 | 4/1/1 |
| `pre230` | before #230 | 6/6 | 19 | 7 | 3 | 10 | 38,365 | 4/1/1 |
| `v018` | the v0.18 driver | 6/6 | 17 | 7 | 3 | 8 | 37,422 | 4/1/1 |
| `preprice` | today's, on the `-D OT6_BOOST_PRICE=0` ROM | 6/6 | 16 | 8 | 2 | 10 | 34,224 | 4/2/0 |

`pre235` and `pre230` are **frame-for-frame identical to each other on all
six seeds**, so #230 changed nothing here at all; #235 moved three seeds by
a few hundred frames and left the totals where they were. And the driver
v0.18 shipped produces **11 deaths and 2 wipes on seed 0**, against today's
12 and 2, on a run that also takes all three dive attempts. The three
commits the coordinator named are not what did this.

The `-D OT6_BOOST_PRICE=0` control is a different ROM, so every later RNG
consumer moves and its seed-0 timeline is its own (9 deaths, 1 wipe, 2
attempts). It is not cleaner than the shipped economy by any margin worth
reading, and it is not the axis.

**The earlier single-death reading was a different build.** The 2026-09-16
baseline (`build/attempts/baseline-2026-09-16/audit_fenix.txt`, a v0.17 tree
and a v0.17 `gau_joined`) records `sabin_done 2 deaths, 1 banked`, the dive
landing on attempt 1 at f25793 — and its one killer was the same `cmd $0C
atk $B9`. Since then the whole upstream chain was regenerated on the v0.19
ROM, so the dive is entered from a different RNG state, and shift 0 now
draws the double-Aspik formation **three times** where the v0.17 timeline
drew it once. The party arrives at identical levels and identical maxima
(358 / 363 / 394 in both logs), which is what says the difference is the
timeline and not the route.

## The banked pips

Five of the twelve deaths in the build's own log were at >= 3 BP, and the
audit calls that "the driver left boost on the table". **It is not, here.**
The spend rule was asked, and what it answered is in the log
(`table-head-seed00.txt`, bottom):

```
actor=1 SPEND (care): 208/358 is inside one round of death (921) holding 2 BP,
  and no heal saves it (item $E9 +250 = 458) -- Fight at 2 BP ... (#175)
actor=2 SPEND (care): 264/394 is inside one round of death (634) holding 2 BP,
  and no heal saves it (item $E9 +250 = 514) -- Fight at 2 BP ... (#175)
actor=1 no spend (care): item $E9 saves: 54 + 250 = 304 survives the 135 round
```

It fired twice and correctly declined four times, each time because a
Potion in the bag really did lift that member clear of the priced round.
Taking the seven banked deaths of the whole `head` spread one at a time:

| seed | who | HP at death | BP | killed by |
|---|---|---|---|---|
| 0 | GAU | 16/394 | 3 | Battle |
| 0 | GAU | 88/394 | 3 | Battle |
| 0 | SABIN | 24/363 | 3 | Battle |
| 0 | GAU | **290/394** | 3 | Special |
| 0 | SABIN | **254/363** | 4 | Giga Volt |
| 5 | SABIN | **320/363** | 3 | Giga Volt |
| 20 | GAU | 166/394 | 3 | Aqua Rake |

**Three of the seven died from 65-88% of maximum.** No spend rule reaches
those: they were never inside a round of death, and two of them were killed
by the counter this document is about, from healthy. The other four are
#194's own case (c), written into the issue a cycle ago — *"a member who
gets no turn between entering lethal range and dying (the rule only runs on
their own turn)"*. They are members stuck in a heal-and-raise loop after
SABIN went down, holding pips because #174 keyed their Fight at 0 BP (`0 BP
lands 1 chip(s) ... unboosted, the pip banks`) and then never getting
another turn.

So the banked-pip count here is a **symptom of the first death**, not a
second defect. Fix the first death and it goes with it — which is what the
numbers below show.

## The spread

Six `OT6_SEED_SHIFT` values, 0 through 25 in steps of 5 — idle frames the
segment runner inserts at the boot point, the beat a player pauses before
walking on — with the segment runner's retries **off** (`OT6_RETRIES=1`),
so every seed reports the generator's **own** three-attempt dive ladder and
not a re-boot on top of it. Nothing is published to `build/states`. All six
shifts draw a different first battle (`be44`, `be5C`, `be70`, `be80`,
`be94`, `beAC`), so six shifts are six distinct samples.

## Recommendation

**Kill order: the Aspiks first** -- and that is the change this branch
lands.
 One option on the generator's own fight
driver, `tools/tests/gen_sabin_trench.lua`:

```lua
  local ASPIK = 0x0059
  local F = H.newFightDriver("trench " .. what, { tactical = true,
    boost = true, bank = 3, items = true, healPercent = 60, cadence = 12,
    focus = { { species = ASPIK } } })
```

`opts.focus` is the driver's existing kill-order steer (`M.focusSlots`):
it points every single-target plan at the first named species that is
alive and on stage. It cannot steer the Pummel — nothing can, the row
auto-confirms — but it puts CYAN's and GAU's Fights on the Aspiks, which
are also the flimsiest things on the stage (220 HP against Actaneon's 230,
2 battle power against 13), and a dead Aspik has no counter to give. It is
inert on the formations that carry none, including the Crescent Mountain
walk this same driver plays.

Naming a species in a generator is **route knowledge**, the same kind the
step already carries about which tile opens the helmet scene and which
dialog row boards the ferry, and the same kind `opts.focus` was built for
(the Air Force's Speck, `M.focusSlots`). It is labelled here rather than
left implicit: the fight driver itself learns nothing new, and nothing in
the battle reads a hidden weakness or a future roll. It is the kill order
a person writes down after the first time a jellyfish kills SABIN.

Measured over the same six shifts, everything else held (`aggregate.txt`):

| | pass | deaths | banked | wipes | Fenix | mean frames | attempts 1/2/3 |
|---|---|---|---|---|---|---|---|
| before (`head`) | 6/6 | 19 | 7 | 3 | 9 | 37,927 | 4/1/1 |
| **after (`focus`)** | **6/6** | **5** | **1** | **1** | **2** | **32,054** | **5/1/0** |

and per seed:

| seed | key | before: deaths/wipes/attempts/frames | after |
|---|---|---|---|
| 0 | be44 | **12 / 2 / 3 / 70,479** | **0 / 0 / 1 / 30,799** |
| 5 | be5C | 1 / 0 / 1 / 28,879 | 1 / 0 / 1 / 31,394 |
| 10 | be70 | 2 / 0 / 1 / 34,411 | 0 / 0 / 1 / 28,266 |
| 15 | be80 | 0 / 0 / 1 / 26,082 | 0 / 0 / 1 / 27,426 |
| 20 | be94 | 3 / 1 / 2 / 35,311 | 4 / 1 / 2 / 39,816 |
| 25 | beAC | 1 / 0 / 1 / 32,402 | 0 / 0 / 1 / 34,623 |

Seed 20 is the one that does not improve, and it is honest to say so: it
loses a ride and reloads in both arms, and after the change it loses one
more member doing it. Every other seed is level or better, and **seed 0 —
the shift the ninja graph regenerates `sabin_done` on — goes from the
build's 12 deaths, 2 wipes and a ladder spent to its last attempt, to a
clean first-try dive.**

The generate edge itself, the shipped generator run unmodified through
`run.sh` with the graph's own ladder and nothing published
(`build/lab/trench-dive/shipped/sabin_done.log`):

```
[ot6] [trench] dive attempt 1 LANDED at Nikeah f26401
[ot6] PASS (frame 30799) attempts=1/3
```

First try, and the same frame as the lab's `focus` seed 0 — which is what
says the observers do not change the run in either direction.
`tools/audit_boost.py build/lab/trench-dive/shipped/sabin_done.log -v`:

```
Boost audit: no party deaths in the scanned logs (1 logs).
```

The counter is not abolished, only made rare. `counters-after.txt`: the
six after-seeds still put **25** Blitzes into an Aspik formation and
still drew **2** Giga Volts — 8% of Pummels against `head`'s 34 in 123,
which is 28%. Part of that is the Aspiks dying sooner, and part of it is
that a fight won in nine turns instead of thirty-six moves the ride's
later encounter rolls, so the after-arm's seed 0 never meets formation 67
at all. Both halves are real and neither is the whole of it.

### What it stales

Editing the generator moves `gen_sabin_trench`'s own hash, so `sabin_done`
and everything downstream of it go STALE by the graph's own rule
(`compose.py --check-states`). Regenerating the route is the coordinator's
to sequence; this branch does not run it. The `shipped` run above is the
generate edge played for its verdict only, with `OT6_NO_PUBLISH=1`.

## Options not taken

- **Turn SABIN's Blitz off for the dive.** Measured, as the `noblitz`
  policy: two words in `lib/ot6.lua` (`opts.blitz ~= false` on the two
  sites that offer the Blitz, exactly as `opts.tools = false` already
  gates EDGAR's AutoCrossbow for the formations a multi-target tool heals)
  and `blitz = false` in the generator. It works — 6 deaths, 1 banked, 1
  wipe, 2 Fenix, and the fastest mean of the lot at 29,950 frames, with
  **zero** Giga Volts because SABIN never gives one a reason. It is not
  what shipped because it costs the verb rather than the trigger: measured
  over `head`'s six seeds, SABIN's Pummel averages **186 damage a turn
  across 41 turns** against his Fight's **109 across 30**, and turning it
  off gives that up in the fights that carry no Aspik at all -- 18 of the
  39 the `head` spread played. The lab keeps the arm: if the kill order
  ever stops being enough, this is the next lever and it is two words
  away.
- **Levels or HP.** Giga Volt was measured taking a full 363/363 SABIN to
  zero, so the HP that survives it is strictly more than 363 and this lab
  never found the ceiling. Buying it would be three or four levels off the
  Veldt grind upstream in `gen_sabin_gau`, which reshuffles every later
  encounter in the run. Not measured here, and not proposed for a counter
  the party can decline to provoke.
- **Gear.** There is none. Scanning `item_prop_en.dat` for equipment that
  halves, nulls or absorbs lightning gives Force Shld, Cat Hood, Force
  Armor and the Beads — all of them WoR or late WoB, none of them in the
  bag or in a shop this route passes. Rows do not enter into it either:
  Giga Volt is magical, and the back row does not reduce it.
- **Runic.** CYAN is in the party and has it, but the trench's counter is
  a monster's scripted Lore, not a spell Runic's gate admits, and it is
  aimed at whoever swung. Not a lever here.
- **A driver that learns the counter.** The honest general answer — "a
  person who watched SABIN eat 363 lightning for a Pummel stops
  Pummelling" — and the driver has most of the parts already (it attributes
  every death to the monster action that caused it). It is real machinery
  for one segment, and it is not a thing to build in the week a release is
  cut. Worth an issue; the kill order buys the release.
- **Retuning Aspik.** Never. The counter is vanilla FF6 and the answer is
  the kill order.

## The lab

`tools/tests/trenchdivelab.py`, `narshedescentlab.py`'s shape with one
difference that the segment forced.

`gen_sabin_trench` has **no private fighter** — it plays every trench
battle with the library's own `H.newFightDriver` — so the policy under test
is not a region of the generator but the driver itself, and the axes are
`tools/tests/lib/ot6.lua` at a named commit and the ROM. `compose.py`
resolves the lib by path with no override, so `run` swaps the file in,
plays every seed of the policy, and puts the shipped copy back in a
`finally`; policies run one at a time and seeds inside a policy run in
parallel. `trenchdivelab.py restore` puts it back by hand if a run ever
dies mid-policy. The `noblitz` arm's lib is cut the same way, from the
shipped copy plus two anchored substitutions that each assert they matched
exactly once.

The derived script is the generator verbatim plus two read-only CPU exec
observers, one settled per-battle line naming the formation by species, one
party line, and one assignment carrying the dive ladder's attempt number.
Every substitution asserts it matched exactly once, so a generator edit
that moves an anchor fails the derivation rather than silently measuring
something else.

The observers are the descent lab's — `ExecCmd@battle_code` parks the
acting entity's MP, banked BP, revealed boost, the party's HP and every
stage slot's HP; `SaveForMimic` settles them — with the one change this
segment needed: they record **entities 4 through 9** as well as the party.
The trench's killer is a counter, and an enemy action has to be readable
beside the party action that provoked it. That pairing is the whole of the
`counters` report. They read; they never write.
