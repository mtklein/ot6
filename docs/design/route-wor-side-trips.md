# World of Ruin: the grinds before Kefka's Tower

Issues #481 (the dinosaur forest, world group 54) and #482 (the Cactrot
desert, world group 111), from the coverage audit (`wor-coverage.md`
section 3.2, units 1 and 2). Two legs on the main line after the Colosseum:
the forest, the classic late-game grind, fought until the four stand at
Kefka's Tower's target level, then the desert beside Maranda for its gil, and
a save back on the Falcon's tile by Maranda where the line left it. Their XP
and gil carry into Kefka's Tower, the next arc.

Evidence is under `build/attempts/wt/v038-dino-desert/` (section 7 quotes
the lines behind each number).

---

## 0. Findings

1. **The forest is the late grind it is famous for, and the party at the
   Colosseum's save is not ready for it.** One Tyranosaur pays 4,400 a member,
   two pay 8,800, more than any plain. At `wor-colosseum-v1` (SHADOW and CYAN
   L41, 2,656 HP) three of six runs of the leg wiped inside its first five
   forest battles, two of them in the two-Tyranosaur formation, two Meteors a
   round (`dnrun_s20`, `dnfight_s20`; `dnfight_s10` the battle after it).
   So the leg first
   fights the plain by the Falcon (world group 49, the World of Ruin's grind)
   until the lowest of the four is L45, then the forest.
2. **The dinosaurs fall to Ice, and the driver alone never casts it.** The
   fight driver Fights; six forest battles with Fight ended in a wipe in the
   first two-Tyranosaur battle (`ty_fight`), and with whoever holds Ice
   casting it (TERRA's at 1 MP under the Economizer) the same six were won
   (`ty_ice`). The legs set it as a live option (`FIGHT.nuke`).
3. **The two-Tyranosaur formation refuses the run** (`$B1` bit 1:
   "this formation refuses the run ($b1=22 ...)", `brrun0`), so it must be
   won. On four shields, with the after-battle care at its 65% default, it
   lost 4 of 12 (`dn2_s*`). On three shields, with the care to full between
   the forest's battles and casting first, it lost 1 of 41 over 30 distinct
   keys (`dn3_s*`, `dn4_s*`), still with 24 deaths: a Fenix Down most pair
   battles.
4. **The Brachosaur is a run.** Fought with Ice it won 3 of 9 (L41-61; its
   Ultima, `atk $14`, and Meteor take the party), so the leg runs from it, as
   a person would from a fight they cannot win: 15 runs of 15 got away, no
   death (12 distinct keys).
5. **The Cactrot cannot be hit by Fight or a spell, and a thrown Water Edge
   cannot miss.** Evade 250 and MBlock 250 turned every Fight and Ice away and
   its Blow Fish wiped the party (`cact_ice`: "battle $0DD LOST after 16385
   ticks"). A skean cannot be dodged (`MagicProp` $51-$53 +4 bit $20), the
   Water Edge is its weakness, and one shield makes the breaking throw the
   kill: 12 of 12 (`de5*`). The driver's Throw could not reach a Water Edge
   in this bag at all (section 6).
6. **The Hoover's Sand Storm answers every hit.** On four shields it killed
   42 members in 36 battles (`de4*`); on two, 22 in 36, and one battle lost
   with a sneezed member left standing (`de5*`). It stays a hard fight at
   L52-63: a tuning note.

## 1. The legs

| leg | boots | saves | what |
|---|---|---|---|
| `gen_wor_dino` | `wor-colosseum-v1` | `wor-dino-v1` | the plain by Maranda until the lowest of the four is L45; Kohlingen's counter; the Falcon down at (195,46) beside the forest; the forest fought until the lowest is L52, with a trip back to Kohlingen when the bag falls under half the band; the save on the Falcon's tile |
| `gen_wor_desert` | `wor-dino-v1` | `wor-desert-v1` | the Falcon back to its tile by Maranda (69,183); the desert seven steps south fought for eight battles; the save on the Falcon's tile, Kefka's Tower's boot |

**Where they sit, and why on the line.** The audit offered the forest off
`wor-gau-v1` or later and the desert off `wor-colosseum-v1`. Both sit at the
end of the line, after the Colosseum, for three reasons. The forest is the
game's classic late grind (owner, 2026-10-27: "place it late, as the grind
before Kefka's Tower, on the main line, so its XP feeds the tower"). The party
is not ready for it earlier: at `wor-colosseum-v1` itself, with SHADOW and
CYAN at L41, the two-Tyranosaur formation wiped the party in the first
battles (section 4), so an earlier branch would only be weaker. And at the
frontier nothing downstream replays: the legs feed Kefka's Tower, which no
leg plays yet, so the XP and gil they add reach no tracked checkpoint but
their own.

**What they do downstream.** Kefka's Tower boots `wor-desert-v1` instead of
`wor-colosseum-v1`. They raise the four Kefka's Tower would seat first:
SHADOW from L43 and CYAN from L44 to L52-54, CELES and TERRA from L54 to
L61-62, and they add about 210,000 GP (55,000 on the plain and in the forest,
the rest the desert's Hoovers and Cactrots), against Kefka's Tower's target of L52 for
each of three parties (`level-curve.md`). The bench gains nothing: the other
eight stay where the Colosseum left them (RELM L50, STRAGO L47, GOGO L42,
LOCKE L41, SABIN L39, MOG and UMARO L38, EDGAR L34, GAU L33, SETZER L31), so
the tower's arc still has its second and third parties to raise. The fights
the four will meet there were never measured at these levels; the tower's arc
starts from the new save.

## 2. Species and break rows

Four rows, all of them new (the generated floor stood for each: six shields,
pierce for the dinosaurs, slash for the desert's two). The cabin at
`wor-colosseum-v1` seats three blades (CELES, CYAN, TERRA: slash) and
SHADOW's Striker (pierce), with his skeans (fire, water, bolt) and the mages'
Fire, Ice and Bolt. Vanilla elements stay.

| species | L / HP | vanilla | shields | classes | why |
|---|---|---|---|---|---|
| Hoover `$03E` | 49 / 12,018 | weak ice, water; counters every hit with Sand Storm (wind) | 2 | slash, bludgeon | a soft sand-eater: cut it or crush it. The desert keys the blades; its counter answers every hit, so a break by element (Ice, the Water Edge) saves hits |
| Cactrot `$04C` | 27 / 3 | weak ice, water; evade 250, MBlock 250, defence 255 | 1 | pierce | three HP behind an evade almost nothing beats: a hit that lands does 1, and 0 while it shields, so the break is the kill. SHADOW's thrown point (pierce, and it cannot be dodged), or ice and water |
| Tyranosaur `$027` | 57 / 12,770 | weak ice; Meteor | 3 | pierce, bludgeon | a dinosaur's hide, as the Allosaurus's (Cyan's dream): a point or a blow, not an edge. The forest's lesson is the reverse of the desert's: the blades skid, SHADOW's point and the mages' Ice find it |
| Brachosaur `$026` | 77 / 46,050 | weak ice; Disaster, Meteor, Sneeze, Ultima | 6 | pierce, bludgeon | the same hide on a body four times the size; six, so a break holds its turns, Ultima among them |

`battle_breakwor_sidetrips` checks the four rows in the built ROM, their
vanilla weak and absorb bytes, that every species of world groups 54 and 111
has an authored row and a key for the four, and the lessons (the Hoover takes
slash and the Water Edge; neither dinosaur takes slash, both take pierce and
Ice; the Cactrot has one shield). Red on main's rows (`rows/final/main.log`: 14 mismatches, "$026
Brachosaur has no Ot6ShieldTbl row (want 6, class $06)") and on two mutants:
the Tyranosaur keyed by slash (`mutA`: "$027 Tyranosaur class mask $07, want
$06") and the Cactrot on two shields (`mutB`: "$04C Cactrot shields 2, want
1"); PASS on the rows (`rows/final/rows.log`).

Two rows moved with play. The Tyranosaur went from four shields to three
(finding 3) and the Hoover from four to two (finding 6): a break that comes
before the Meteors and the counters pile up is what the rows are for.

## 3. The desert

The Falcon back on its tile by Maranda (69,183), then the desert seven
steps south (the zone tile nearest (70,187) whose own zone deals group 111,
read from `WorldBattleGroup`), eight battles there, and the save on the
Falcon's tile. Hoover is slots 1 and 3 of the pool (62.5%), the Cactrot slots
2 and 4 (37.5%).

- **The Cactrot.** SHADOW throws the Water Edge (`FIGHT.throwRead` while one
  stands: the policy reads its weakness, as a player who knows the Cactrot
  does). Without a Water Edge in the bag or SHADOW standing, the leg runs
  from it (`cactrotRun`): it pays no experience, and nothing else the party
  holds reaches it. 12 of 12 won, 0 deaths, 11 distinct keys (`de5*`).
- **The Hoover.** Whoever holds Ice casts it while one stands (`FIGHT.nuke`).
  2 shields: 35 of 36 won, 22 deaths, 28 distinct keys (`de5*`); the one
  loss ended with a sneezed member standing, so the game went on. On four
  shields, 32 of 36 and 42 deaths (`de4*`).

Before the forest, at L41-53, the desert was worse: the Hoover lost 6 of 18
with 30 deaths (`de_s*`), which is why the desert comes after the forest.

The leg's six runs (two boots from the forest's lab captures, seed shifts and
K = 2, 5 encounters used up first) all passed (`de5*`): on the lab boots, Cactrot 12 of 12 and Hoover 35 of 36 with 22 deaths.

**From the graph's own capture** (`lab/air/gs_*`, booted from the line's
`wor-dino-v1`: seed shifts 0-30 and K = 2, 5), with the care casting first and
a restock at Kohlingen when the bag comes out short: 6 of 6 PASS; the Cactrot
12 of 12 (9 keys, 1 death), the Hoover 35 of 36 (26 keys, 13 deaths). The
restock: the line's first play of the leg came back with 4 Potions of 97
("on the save tile ... potion=4"), so the leg now tops up and flies back
before saving ("the restock after the desert ... potion=99"; "on the save
tile world (69,183) ... potion=99 ... fenix=20 ... gil=928573").
Without a Water Edge (`gs_noedge`, a lab battery with the nine removed) the
leg runs from the Cactrot: "[desert] no throw for the Cactrot (SHADOW standing, 0 Water Edge): running
from it", both Cactrots run from, the eight Hoovers won, PASS.

The run is read at each battle's open and every 30 frames while the battle is
fought, on every walk of the leg (onto the desert, the pacing, back to the
Falcon). With no Water Edge, the leg's own walks between the Falcon and the
desert met a Cactrot and ran (`walks_noedge_s0`, `s20`: "[desert] no throw for
the Cactrot (SHADOW standing, 0 Water Edge): running from it (run 1)"). With
SHADOW not throwing (a lab that switches the throw off), the Blow Fish felled
him mid-battle and the fight turned into a run ("[death] f+9296 entity 0 char 3
... atk $90", then "(SHADOW down, 9 Water Edge): running from it (run 1)",
`midfall_s0`; `midfall_s20` the same). The summary counts runs from the
leg's own count, once a battle: "after the desert: 10 battles, 8 won, 2 run
from, 0 lost" (`de_nedge_full`).

The save the tower boots: SHADOW L53-54, CYAN L52-53, CELES L61-62, TERRA
L62, 930,000-970,000 GP, the bag at its band.

## 4. The forest and the Brachosaur

**The plain first.** From the Falcon's tile by Maranda the four pace the
plain (world group 49: the Crawler trio, Mantodea with Sprinter and Spek Tor)
until the lowest stands at L45: 12-20 battles, about 80,000 frames, one
death in 120 (`dn4_*`: "the plain by Maranda: 20 battles (won 13F x16, won
143 x4) ... SHADOW L45 ... CELES L55 ... CYAN L45 ... TERRA L55").

**Kohlingen, then the forest.** The bag to the band at Kohlingen's counter,
the Falcon down at (195,46), and the forest until the lowest of the four
stands at L52, Kefka's Tower's target: 23-25 battles (two Tyranosaurs about
one in three), about 100,000 frames. The care between the forest's battles
tops everyone up to full and casts first (`H.careThreshold = 1.0`,
`H.careMagic`, `H.careCastFirst`; TERRA's Cure costs 1 MP). The leg leaves
for Kohlingen when the bag falls under half its band; in the measured runs it
never did.

| | runs | PASS | two Tyranosaurs | one | deaths | the four at the save |
|---|---|---|---|---|---|---|
| `dn4_s0`, `s20`, `k2`, `k4`, `k6`, `k8` | 6 | 5 | won 40, lost 1 (30 keys) | won 86 (47 keys) | 24, all in the pair | SHADOW L52-53, CELES L59-60, CYAN L52, TERRA L60-61 |

The one loss (`dn4_k6`, K = 6) was the first pair battle at L45: two Meteors
before SHADOW and CYAN acted ("[death] f+1816 entity 0 char 3 from 1591/3235
by slot 0 cmd $02 atk $13"). In the graph's line a wipe is retried from the
leg's boot, counted, as a person reloads.

**The Brachosaur.** The question #481 asks: does the party win it, or does a
player run? Measured both ways from the same boots:

| policy | levels | Brachosaur battles | won | lost | runs | deaths |
|---|---|---|---|---|---|---|
| fight (Ice, as the dinosaurs) | L41-53 | 2 | 1 | 1 | - | 4 (`brice0_s40`, `dnfight_s0`) |
| fight | L52-61 | 7 | 2 | 5 (one a wipe) | - | 25 (`b52f_*`) |
| run (L+R) | L41-61 | 15 | - | - | 15 | 0 (`ty_ice`, `dnrun_*`, `b52r_*`) |

3 of 9 won: Ultima ("cmd $02 atk $14") and Meteor kill, and Disaster's
Muddle turned CYAN on CELES once ("by entity 2 char 2 cmd $00 atk $FF"). The
Brachosaur's XP (7,198 a member) is not worth a coin flip, so the leg runs
(`FLEE = { BRACHOSAUR }`), and the run has never failed. With twelve more
levels the fight may turn; that is for whoever grinds past L60.

**From the graph's own capture.** After the rebase onto the grind plains
(#483, `c1d9745d`: the party arrives at SHADOW L43, CYAN L44, CELES and TERRA
L54), the line replayed from `wor_ragnarok` and its `wor_colosseum` capture
booted six sweep runs of `gen_wor_dino` (`lab/air/gd_*`: seed shifts 0, 10,
20, 30; K = 3 and 6 encounters used up first). The line's own play of the leg
(`qual/wor_dino.log`) booted the same capture at shift 0, so it is `gd_s0`'s
draw, counted once (the same battles to the frame: "the forest: 28 battles
... f140895" in both):

| | runs | PASS | plain | forest | two Tyranosaurs | one | Brachosaur | deaths | the forest done |
|---|---|---|---|---|---|---|---|---|---|
| `gd_*` | 6 | 6 | 1-7 battles | 25-28 battles | won 37 (28 keys) | won 117 (50 keys) | run from 6 of 6 (6 keys) | 14 (13 in the pair) | f126,886-f140,895 |

The four leave the forest at SHADOW L52-53, CYAN L52, CELES L59-61 and TERRA
L60-61, with about 55,000 GP more than they came with and the bag still
nearly full (Potions 94-97 of 99, Fenix Downs 18-21; no trip back to
Kohlingen was needed). The grind is about 35 battles and 130,000-140,000
frames, some 36-39 minutes of play: "the forest: 28 battles (won 140 x7, won
141 x21) ... SHADOW L53 4124/4124, CELES L61 5241/5241, CYAN L52 3993/3993,
TERRA L61 5237/5237" (`qual/wor_dino.log`).

## 5. What the legs depend on (#480)

The entry contracts (`lib/ot6_contract.lua`) already hold the story both legs
stand on: SHADOW recruited (`$02F3`, gen_wor_colosseum) and the Falcon parked
beside the party. What each leg asserts besides, as it starts:

| leg | asserts (hard: only upstream supplies it) | tops up (soft) | negative |
|---|---|---|---|
| `gen_wor_dino` | one of the four knows Ice (TERRA's stone and shield, CELES's natural magic); gil for Kohlingen's top-ups (60,000: 99 Potions, 20 Remedies, 20 Fenix Downs) | the seated four (the cabin), the bag (Kohlingen, before the forest and whenever it falls under half the band), HP (the care) | `neg_dino_noice` ("[deps] Ice: nobody" ... "assertEq failed: one of the four knows Ice"), `neg_dino_poor` ("gil for Kohlingen's top-ups: 1000 GP, the floor 60000") |
| `gen_wor_desert` | gil for Kohlingen's top-up | the seated four, the bag (Kohlingen when short), the Water Edges (without one the Cactrot is run from), HP | `neg_desert_poor` ("gil for Kohlingen's top-up: 1000 GP, the floor 60000 (the line's purse)") |

Both negatives are lab-only batteries (`scripts/make_negative.py`: slot 3's
WRAM edited, its checksum recomputed, provenance prose saying so). Their
positive controls are every run of section 3 and 4, which pass the same
asserts ("[deps] Ice: CELES, TERRA").

## 6. The harness

- **Throw** (`lib/ot6.lua`). The English Throw window is one column
  (`UpdateMenuState_2d`, `LANG_EN`), its scroll `$8953`+actor and row
  `$895B`+actor; the steer read the two-column tools cells and the first 16
  rows, so with a bag of weapons the Water Edge was "not in the list" and
  SHADOW planned a throw every turn and threw nothing (`cact_throw`). It now
  walks the whole list, the parked-window watch carries the pair, and a
  throw's pulse budget is the ceiling. `opts.throwRead` lets a policy read
  the weak byte (`$3BE0`+entity) instead of waiting for a reveal a miss never
  makes.
- **Runs** (`lib/ot6_field.lua`). `worldNavTo`'s `fleeSpecies` may be a
  function, read as each battle opens (the desert's Cactrot when SHADOW
  cannot throw), and `K.pace` passes it (`opts.flee`) with `opts.pick`, the
  neighbour the pacing may take (a tile of the same world group).
- **A grind's stop is read between battles.** A pace whose stop was a level
  or the bag ended inside a battle's hand-back and the walk after it stalled
  (`dnrun_s0`, `dnrun_s10`: "no-progress ... W:0.216.128.0.1"); the forest's
  stops are read only on the world, settled.
- **`battle_slotcancel`** (not this branch's suite) went red on this ROM: its
  blind reel taps landed 2-2-2 and the drawn Crusader took the party before
  the property was measured. Reel 1 is now not timed on a 7 or the esper. It
  passes at seed shifts 0, 10, 20 and with its first K = 1, 2, 3 draws run
  from (six distinct battle keys, `slotcancel/final_s*.log`, `k*.log`); the
  suite before the fix also passes at those K, so only the shift-0 draw met
  the esper.
- **Fled battles print no `[outcome]`.** The sweeps count a run from the
  battle keys (`scripts/sweep.py`: a key with no outcome before the next).

## 7. Evidence

Directory `build/attempts/wt/v038-dino-desert/`: `rows/` (the suite on
main's rows, the mutants and the rows), `lab/air/` and `lab/px13/` (each
run's `run.log.gz`, `rc.txt`, `env.txt`, `commit.txt`, `rom.txt`,
`script.lua`), `scripts/` (the lab builders: `br/mkbr.py` the Brachosaur
arms, `br/mkty.py` the Tyranosaur arms, `br/mkcact.py` the Cactrot answers,
`br/mkk.py` the K variants, `br/mkarm.py`; `sweep.py` the tally;
`make_negative.py`), and `qual/` (the graph's line and the gate).

Quoted lines behind the tables (each from the file named):

```
lab/air/gd_s0/run.log.gz: [ot6] [wor] f29762 the plain by Maranda: 7 battles (won 13F x5, won 143 x2) ... SHADOW L45 3116/3116, CELES L55 3943/4387, CYAN L45 2897/3118, TERRA L55 4383/4383; potion=98 ... fenix=22
lab/air/gd_s0/run.log.gz: [ot6] [wor] f140895 the forest: 28 battles (won 140 x7, won 141 x21) ... SHADOW L53 4124/4124, CELES L61 5241/5241, CYAN L52 3993/3993, TERRA L61 5237/5237; potion=97 ... fenix=19
sweep.py gd_*: form 320 ($140): won 37; deaths 13; distinct keys 28 / form 321 ($141): won 117; deaths 1; distinct keys 50 / form 322 ($142): run from 6; deaths 0; distinct keys 6
sweep.py gs_*: form 221 ($0DD): won 12; deaths 1; distinct keys 9 / form 237 ($0ED): lost 1, won 35; deaths 13; distinct keys 26
sweep.py dn4_*: form 320 ($140): lost 1, won 40; deaths 24; distinct keys 30
sweep.py dn2_*: form 320 ($140): lost 4, won 8 (four shields, the care at 65%)
sweep.py brice0_s40 dnfight_s0 b52f_*: form 322 ($142): lost 5, won 3; deaths 29; distinct keys 10 (and b52f_b0's wipe in it)
sweep.py ty_ice dnrun_s0 dnrun_s10 b52r_*: form 322 ($142): run from 15; deaths 0; distinct keys 12
sweep.py de4*: form 237 ($0ED): lost 4, won 32; deaths 42 (four shields) / de5*: lost 1, won 35; deaths 22 (two)
lab/px13/brrun0: flee: this formation refuses the run ($b1=22 $2f4b=00 held 60 frames ...)
lab/px13/cact_ice: [outcome] battle $0DD LOST after 16385 ticks: killed none
lab/air/cact_trace2: actor=0's throw took 3 off the monsters (0 shielded-equivalent over 1 hit(s), 0 a hit ...) [exec cmd $08 atk $AC]
lab/air/neg_dino_noice: [deps] Ice: nobody / assertEq failed: one of the four knows Ice (TERRA's natural magic, or a stone the line gave)
```

The line's own play of the legs at the final commit: `qual/wor_dino.log`
(PASS, first attempt: plain 7, forest 28, two Tyranosaurs won 7, the
Brachosaur run from once, 3 deaths) and `qual/wor_desert.log` (PASS: Cactrot
2 of 2, Hoover 6 of 6, 4 deaths; "on the save tile world (69,183) ...
potion=99 ... fenix=20 ... gil=928573").

**The re-cut.** The rows change the ROM, and the play from power-on moved
with it. The first save to move is in the World of Balance, `kolts-summit-v1`
(the two before it, `world-narshe-v1` and `world-figaro-v1`, are unchanged);
from there 60 of the 62 tracked checkpoints differed from the graph's capture
(`qual/drift_before_recut.txt`), all re-cut from the play at `e0280579`
(`qual/recut.txt`).

**After MagiMaster (`d300045e`).** Rebased onto it, the line replayed from
`wor_tower` on, and 16 saves drifted from it: the 14 main had just re-cut
(`wor-thamasa-v1` to `wor-colosseum-v1`, played on main's ROM) and this
branch's two. All 16 were re-cut from the play at `994c8a46` (`qual/recut2.txt`:
"checkpoint drift wor-dino-v1: 107 byte(s) differ ... TERRA exp: fresh 642951,
tracked 628913"; "checkpoint drift wor-desert-v1: 106 byte(s) differ"). The
line's play of the legs there: the forest 29 battles (two Tyranosaurs won 7,
the Brachosaur run from once), the four at SHADOW L53, CELES L60, CYAN L52,
TERRA L61; the desert 8 battles (Cactrot 2 of 2, Hoover 5 of 6, the loss with a
sneezed member standing), the save at potion 99, gil 878,073
(`qual/gate5.out`). The re-cut wor_colosseum also needed its grind plains'
fixture cared for before it is saved (CELES poisoned on this ROM,
`audit_party_hp` in `qual/gate4.out`).

**A retry in the qualified play.** `wor_phoenix` (not this branch's leg) wiped
on its first attempt and passed on its second: "[retry] attempt 1/3 FAILED
class=wipe frame=66449" (`qual/wor_phoenix.log`). gen_wor_ragnarok, main's own change before this branch,
reproduces main's tracked save byte for byte on main's ROM with main's lib
and with this branch's lib (`lab/air/probe_main`, `probe_mylib`), so the
drift is the ROM's, not the lib's.

The tables' "lab boots" rows booted the tracked `wor-colosseum-v1` of v0.37
(made on main's ROM, a Continue across builds: a lab, not a measurement of the
graph); the `gd_`/`gs_` rows and `qual/` are the graph's own captures.
