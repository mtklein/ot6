# The South Figaro gate soldier — solo LOCKE vs HeavyArmor (#193)

Authored 2026-09-16 from `tools/tests/lab_sfigaro_gate.lua` (the lab; its
header carries the decoded rows), the v0.17 qualification log
(`build/attempts/baseline-2026-09-16/v017-requal2.log` in the main tree)
and the 10-seed baseline sweep of `sfigaro_town`.  Every number below is
quoted from a retained log under `build/attempts/locke-solo-lab/` (the
batch runner keeps every attempt; `tools/tests/sfigarolab_aggregate.py`
prints them all).

## What happened in the qualification

`sfigaro_town` (gen_sfigaro) attempt 1:

    [ot6] [B1 (open the town): ride battle 11 out] battle f+4800 menu=00 state=00 actor=0 cursor=0 cmds=00,05,FF,01 partyhp=137,0,0,0 roundcost=110,0,0,0 monhp=s0:117/sh3 monsters=1
    [ot6] [B1 (open the town): ride battle 11 out] actor=0 KEYED: Fight at 0 BP lands 1 chip(s) on slot 0's 3 shield(s) -- no boost within the bank (0) reaches 3 shield(s); 0 BP lands 1 chip(s), the most the bank allows; unboosted, the pip banks (#174)
    [ot6] [B1 (open the town): ride battle 11 out] battle f+5100 menu=00 state=00 actor=0 cursor=0 cmds=00,05,FF,01 partyhp=137,0,0,0 roundcost=110,0,0,0 monhp=s0:108/sh2 monsters=1
    [ot6] canary: BATTLE WIPE -- the battle table has read wiped for 300 frames (seats [a1:0/279 - - -], $3ebc=01: every present seat at 0 HP or LoseBattle's bit 0 set); the engine is sitting on the annihilated screen waiting for a press.  Counted as a game over (f7371).
    [ot6] pad frozen (f7371): the party was wiped in battle -- no further presses until a snapshot is restored, so nothing here can Continue a save
    [ot6] [retry] attempt 1/3 FAILED class=noprogress frame=9216 totalframes=9216 shift=0 phase=56: no-progress: nothing has moved for 1808 frames at F:75.30.43.82.0.1.00.10|m0|p0|i66 -- ...

Attempt 2 passed (`PASS (frame 34742) attempts=2/3`).  Two corrections
to the issue's framing come out of the decode below: the HeavyArmor is
**not a random** (map 75 rolls none), and the canary **did** name the seat
(`seats [a1:0/279 - - -]`); what went wrong on the runner side is what it
did next.

## The fight, decoded

Map 75 (occupied South Figaro) rolls no random battles at all:

    $ python3 tools/audit_encounters.py 75
    map 75: NO ENCOUNTERS (map_prop +5 bit 7 clear) -- ...

The HeavyArmor is the **gate soldier**: map 75 npc 10 / obj 26 at (30,42),
event `_ca854f` (event_main.asm:20296) → `battle 11, TOWN_EXT` → formation
64 = HeavyArmor `$09F` x1 (`battle_monsters.dat[64]` = `00 01 9f ff ff ff
ff ff ...`).  He blocks the only tile joining the starting pocket to the
town, so the fight is mandatory, and gen_sfigaro fights him three times
(B1 into town, R1 into the SE quarter, R2 out of it — he respawns on every
map-75 reload).

| | value | source |
|---|---|---|
| HeavyArmor $09F | L13, HP 495, MP 150, speed 40, atk 53, hit 100, def 150, mdef 110, mpow 11 | `monster_prop.dat` +$13E0 |
| weakness | `$84` = bolt \| water; no absorb, no null | `monster_prop.dat` +25/+23/+24 |
| shields | 3, SLASH\|PIERCE (LOCKE's Dirk is pierce: every Fight chips) | `Ot6ShieldTbl`, `ot6_hud.asm:1645` |
| **run bit** | special status 2 (+19) = `$00`: bit 3 clear, the fight **can** be run from | `battle_main.asm:7647` copies +19 to `$3c80,y`; `UpdateMonsterGfxBuf` (`:15631-15635`) `lda $3c88,y / lsr / bit #$04 / tsb $b1` sets the can't-run flag from its bit 3; measured: L+R escapes in ~560 frames, 3/3 seeds |
| formation flags | `battle_prop.dat[64]` = `43 00 00 00`: `$2f48` = `$0043 ^ $00f0` = `$00b3`, no pincer bit; `$2f4b` = 0 | `LoadBattleProp`, `battle_main.asm:8210-8220` |
| AI, fewer than 4 characters | `attack BATTLE` / `wait` / `attack BATTLE, TEK_LASER, SPECIAL` | `ai_script.asm:341-356` |
| TekLaser | `$B5`, magic_prop power 20, bolt, single target | `const.inc:778`, `magic_prop_en.dat` |

So every second HeavyArmor turn is one of Battle / TekLaser / Special.
The fight can be run from, but running does not open the lane (below).

**Measured on the fixture** (`locke_scenario.mss`: LOCKE L12, 279 HP,
Dirk / Leather Hat / LeatherArmor, back row; the lab's `[hit]` lines
carry the engine's damage word before the HP clamp, `raw`):

    control, 15 seeds, TekLaser raw:  149 150 153 155 161 162 165 168 168
    control, 15 seeds, Battle raw:    52-60 (58 of them), 113 x2 (criticals)
    control, 15 seeds, Special raw:   78-88

A TekLaser is 54-60% of LOCKE's 279; a Battle 19-21% in the back row.
Nothing here one-shots a topped LOCKE; the losses are a sequencing
matter, below.

## Why LOCKE dies

Every loss has the same shape.  The three baseline losses
(`build/attempts/locke-solo-lab/sweep-baseline/sfigaro_town.seed0{0,2,3}.log`):

    seed00  battle f+4800 ... partyhp=137 ... monhp=s0:117/sh3   -> KEYED: Fight at 0 BP ... -> canary: BATTLE WIPE (f7371)
    seed02  battle f+4800 ... partyhp=134 ... monhp=s0:111/sh3   -> KEYED: Fight at 0 BP ... -> canary: BATTLE WIPE (f7328)
    seed03  battle f+4800 ... partyhp=132 ... monhp=s0:109/sh3   -> KEYED: Fight at 0 BP ... -> canary: BATTLE WIPE (f7314)

and the lab's three control wipes:

    death=TekLaser:raw164:from137:bp1   (seed 40)
    death=TekLaser:raw153:from142:bp1   (seed 24)
    death=TekLaser:raw168:from134:bp1   (seed 52)

LOCKE at 132-142 HP, the soldier at 109-117 HP with his shields just
re-seeded to 3, and the driver plans a 0-BP chip (9 damage) rather than
the Potion that sits in the bag; the next enemy turn is the laser.  The
driver even knows the Potion saves him — seed 1's R1 loss in the sweep
(`sfigaro_town.seed01.log`):

    [R1 (into the SE quarter): ride battle 11 out] actor=0 no spend (attack): item $E9 saves: 22 + 250 = 272 survives the 152 round
    [R1 (into the SE quarter): ride battle 11 out] actor=0 KEYED: Fight at 0 BP lands 1 chip(s) on slot 0's 2 shield(s) -- ...
    [R1 (into the SE quarter): ride battle 11 out] slot 0's smallest hit this fight so far: 52, on entity 0 (74 -> 22)

The reason is the fight driver's **finisher gate** (`lib/ot6.lua`
`makePlan`): the whole care block — the press rule, the spend rule, the
raise and the heals — sits under `totalMon > 200`:

    if (row ~= nil or cureRow ~= nil) and totalMon > 200 and parkDropN < 3
       and careOpen then
      -- The press rule (#156), the finisher rule's sibling: ...

Once the monsters' total HP is 200 or less the actor never heals,
whatever his own HP.  For a party that is one break from ending a fight
that is the right call; for a solo L12 against a 495-HP soldier whose
shields re-seed to 3 inside that window, "under 200" is still three chips
and a break away — two or three more enemy turns, one of them a laser.
This is a lib matter (the lib halves were read-only for this lab); the
generator-level answer is below.

## The lab

`tools/tests/lab_sfigaro_gate.lua`, run by `tools/tests/sfigarolab_batch.sh
<policy> <seeds...>`, aggregated by `tools/tests/sfigarolab_aggregate.py`.
Fixture: `build/states/locke_scenario.mss`, gen_sfigaro's own boot state,
so an attempt is the generator's opening beat exactly (the kit, the back
row, the walk, the talk).  The declared spread is 15 seeds (0..56 step 4:
the whole `$021e` cycle; the hold-to-battle latency is quantized to 4
frames).  A wipe is the measurement; every attempt is kept.

Policies (none reads hidden state):

- **control** — `H.rideOut`'s driver as it ships: tactical, boost,
  bank 3, items, healPercent 60, cadence 12; back row.
- **boostfight** — control with `keyed = false` (the plain boost-Fight
  default, no keyed chip line).
- **breakfirst** — bank 0: every pip spent as it exists.
- **heal75** — healPercent 75; **heal75b0** — heal75 + bank 0.
- **tonics** — every Potion reserved: the in-combat heal is the Tonic.
- **front** — LOCKE in the front row (the contrast).
- **run** / **stealrun** — L+R held from the first frame / one Steal then
  L+R (3 seeds each: what a run buys, with the escape cells logged).
- **endgame** — control plus the one press a person makes there: a
  Potion, steered by the lab, when LOCKE is under 175 HP (the laser
  measured up to 168) inside the finisher window (total monster HP ≤
  200), where the driver's care block is closed.

### Results

`python3 tools/tests/sfigarolab_aggregate.py` (n = attempts; seeds = distinct
battle seeds drawn; potions/tonics = spent in fights that ended, since a
wiped fight's bag is never written back; maxraw = the largest damage word
the engine wrote; lasers = TekLasers that landed):

```
policy       n seeds  won wiped other potions tonics fenix  frames maxhit maxraw lasers
boostfight  15    15   13     2     0      16      0     0    6918    168    169      5
breakfirst  15    15   15     0     0      18      0     0    7353    165    165     10
control     15    15   12     3     0      21      0     0    6851    168    168     12
endgame     15    15   15     0     0      40      0     0    7920    169    169     14
endgameb0   15    15   15     0     0      31      0     0    8119    165    165     10
front       15    15   12     3     0      29      0     0    4710    230    230      7
heal75      15    15   15     0     0      27      0     0    7229    168    168      9
heal75b0    15    15   15     0     0      28      0     0    7565    165    165      9
run          3     3    0     0     3       0      0     0     564     57     57      0
stealrun     3     3    0     0     3       0     -1     0    1466    158    158      1
tonics      15    15   11     4     0       0      0     0    5721    168    168      5
```

The margin each 15/15 policy leaves (HP at the end of the winning fights,
and Potions per winning fight; the bag holds 6 and the Locke scenario has
no Potion seller):

```
breakfirst wins=15 hp_end min=15  q1=111 med=171 potions/win=1.20
heal75     wins=15 hp_end min=1   q1=109 med=221 potions/win=1.80
heal75b0   wins=15 hp_end min=61  q1=171 med=225 potions/win=1.87
endgame    wins=15 hp_end min=221 q1=221 med=223 potions/win=2.67
endgameb0  wins=15 hp_end min=196 q1=220 med=224 potions/win=2.07
control    wins=12 hp_end min=1   q1=28  med=221 potions/win=1.75
```

What the table says:

1. **The shipped driver loses one fight in five** (control 3/15; the
   10-seed baseline sweep of the whole segment lost 3/10 the same way,
   `build/attempts/locke-solo-lab/sweep-baseline/summary.tsv`).  Every
   loss is the finisher-window laser above.
2. **A keyed break is not the problem, nor is the boost-Fight default.**
   `boostfight` (no keyed line) loses 2/15 the same way; the keyed chip
   is just what a 0-BP actor does in that window either way.
3. **Spending the pips as they come (bank 0) removes the losses** (15/15)
   because the break comes a turn or two sooner and the soldier is dead
   before the window costs a laser -- but one fight still ended at 15 HP:
   a win by one Battle.
4. **A higher top-up threshold changes nothing** where it matters: heal75
   is bit-identical to control on every seed control won (same frames,
   same HP), and only differs on the three losing seeds; it too finishes
   a fight at 1 HP.  The threshold is inside the closed care block.
5. **Tonics are not a combat heal here**: with every Potion reserved the
   driver drinks nothing (`$E8 restores 50 and a round costs 87, so the
   turn buys back less than it spends -- acting instead`) and loses 4/15.
6. **The front row doubles the physicals** (Battle 104-120, one 229/230
   critical, Special 159-172) and loses 3/15 in half the frames.
7. **The fight can be run from.**  My first decode of the run bit was
   wrong (I read monster_prop +20); the engine copies **+19** (special
   status 2) to `$3c80,y` (`battle_main.asm:7647`) and tests its bit 3,
   and HeavyArmor's +19 is `$00`.  L+R escapes in ~560 frames on 3/3
   seeds (`$2f45=01`, `$3a38=01`, then `$3a39=01`; `run_s0.log`).  But
   the soldier stays on his post and the lane stays closed
   (`[after] the fight: map75(30,43):1DD1=10:obj26=(30,42):probe=false`),
   so running is a reset, not a route.  Steal lands on the 4th attempt
   (bank 2) and takes a Tonic; steal-and-run is a Tonic for ~1300 frames
   and 100-200 HP.
8. **The Potion a person drinks there wins with a margin.**  `endgame`
   (control + a Potion under 175 HP once the soldier is under 200) and
   `endgameb0` (the same with bank 0) are 15/15 with no fight ending under
   196 HP.  endgame is Potion-hungry (2.67 a fight, 16 steers in 15
   fights); endgameb0 steers 13 Potions in 15 fights, 2.07 a fight.

**Verdict: endgameb0.**  bank 0 for the sooner break, and the Potion
under 175 inside the finisher window.

## The runner: why the loss read as `no-progress`

The seat-based predicate worked.  `M.partyWipedInBattle` (ot6_field.lua:63)
reads the four seats (`$3ed8` actor, `$3aa0` present bit, `$3bf4`/`$3c1c`
HP) and `$3ebc`, and `M.wipeVerdict` said wiped for the one present seat:
`seats [a1:0/279 - - -], $3ebc=01`.  The canary counted it (`wipeFired`,
`M.gameOverFired = 1`) and **froze the pad** (`M.freezePad`, ot6.lua:6036).

Two things then made the attempt a `noprogress` instead of a `wipe`:

1. **gen_sfigaro runs with `allowGameOver = true`** (for the cider-steal
   ladder, #163).  The run loop's only wipe failure is
   `if M.gameOverFired > 0 and not RUN.opts.allowGameOver then failed("wipe", ...)`
   (ot6.lua:6042), so with the flag set the counted wipe raises nothing.
   The `wipe context:` line is printed by `attemptLine` only for
   `class == "wipe"` (ot6.lua:5910-5920), so it never printed either.
2. **The freeze blocked the only thing that could have moved the game
   on.**  Battle 11's loss is scripted, not a game over: the event's loss
   branch (`_ca854f` → `call _ca85ba`) resets the scenario and puts LOCKE
   back on (47,43), and `H.clearGateSoldier`'s ladder reads that as
   `$1DD1` bit 0 and reloads its pre-fight blob for the next rung (seed 1
   of the sweep shows the path working when the press gets through:
   `R1 (into the SE quarter): attempt 1 LOST (scenario reset) ($1DD1.0=1) at (47,43) f22612` →
   `R1 ... attempt 2 WON`).  With the pad frozen, `rideOut`'s A-taps into
   the Annihilated screen were dropped (`pad frozen: a press was dropped
   at f7372`), the screen never changed, and 1800 still frames later the
   no-progress watchdog filed the attempt with the field signature
   `F:75.30.43.82` (stale field RAM under a battle) and a screenshot of the
   Annihilated screen.

So a solo-party wipe does satisfy the predicate; the class was wrong
because the canary's "counted as a game over" has no effect under
`allowGameOver` except the freeze, and the freeze turns a recoverable
scripted loss into a stall.  The fix is in the report for the lib's
editor; the generator-side mitigation (a ride that ends on the wipe and
reloads, as the cider ladder does) is in `gen_sfigaro.lua`'s `clearGate`.

### The aftermath, measured

With the freeze thawed as it comes and A tapped the way a person does
(`probe40_s40.log`, control seed 40, the same TekLaser loss):

    [gatelab] WIPED f7253 (5467 frames in) $3ebc=00 locke=0/279 bp1 vs s0:HeavyArmor:108/sh2
    [gatelab after] +121 map=75 (30,43) ctl=false bright=15 $3ebc=00 msg=00FF bhp=0 event=true go=0 title=0 thaws=0 1DD1=00
    canary: BATTLE WIPE -- the battle table has read wiped for 300 frames (seats [a1:0/279 - - -], $3ebc=01: ...
    pad frozen (f7432): the party was wiped in battle -- ...
    [gatelab after] +241 map=75 (30,43) ctl=false bright=0 $3ebc=01 msg=00FF bhp=0 event=true go=0 title=0 thaws=1 1DD1=01
    [gatelab after] +361 map=75 (47,43) ctl=false bright=7 $3ebc=FF msg=FFFF bhp=65535 event=true go=0 title=0 thaws=1 1DD1=01
    [gatelab] [after] the loss: map75(47,43):ctl=true:1DD1=01:goScript=0:title=0:thaws=1:0103=0:0104=0:hp=279/279:wipe2field=685

LoseBattle's bit (`$3ebc` bit 0) is set only 240-360 frames after the HP
word hits 0 (TekLaser's animation and the Annihilated message), the
canary's freeze lands at 300, and the press the screen wants falls after
it.  Thawed, the game fades out, reloads map 75 at (47,43) with LOCKE at
279/279 and `$1DD1` bit 0 set, and the GameOver script is never read nor
TitleScreen executed.  In seed 1's R1 the same loss came from a Battle
(a short animation), the press landed before the 300th frame, and the
ladder's reload path ran.

## What landed

`gen_sfigaro.lua` now carries a `GATE` config and a generator-local
`clearGate` ladder (the lib's `H.clearGateSoldier` in shape):

- `GATE.driver` = `H.rideOut`'s driver with **bank 3 → 0**;
- `GATE.endgameFloor = 175` / `GATE.endgameTotalMon = 200`: inside the
  driver's finisher window, LOCKE under the floor with a Potion in the
  bag drinks it (the generator steers Item → Potion itself, the lib's
  item steer in shape);
- the ride ends on the wipe (the seat-based predicate held 90 frames, as
  the cider ladder does) and the next rung reloads the pre-fight blob, so
  a lost battle 11 is a counted `LOST (PARTY WIPED ...)` line and a
  retry, never a `no-progress` stall.

`ninja build/states/sfigaro_town.mss.lua` on the graph's seed (the one
that lost attempt 1 in the qualification and in the baseline sweep):

    [ot6] [B1 (open the town): ride battle 11 out] endgame: f6133 LOCKE 168/279 under the floor (175) with the monsters at 199 HP (<= 200, the driver's finisher gate): Item -> Potion (bag row 1) instead of the driver's turn
    [ot6] B1 (open the town): attempt 1 WON ($1DD1.0=0) at (30,43) f9784, probe=true
    [ot6] R1 (into the SE quarter): attempt 1 WON ($1DD1.0=0) at (30,41) f23912, probe=true
    [ot6] R2 (out of the SE quarter): attempt 1 WON ($1DD1.0=0) at (30,43) f34104, probe=true
    [ot6] PASS (frame 35902) attempts=1/3

The 10-seed sweep, before and after (`sweep-baseline/summary.tsv`,
`sweep-postfix/summary.tsv`; retries off, so every seed is a first try):

```
                 baseline                       post-fix
seed shift   verdict frames  class          verdict frames
   0     0   FAIL      9216  noprogress     PASS    35902
   1     6   PASS     41678                 PASS    36774
   2    12   FAIL      9168  noprogress     PASS    37061
   3    18   FAIL      9152  noprogress     PASS    36615
   4    24   PASS     33023                 PASS    48110
   5    30   PASS     33671                 PASS    35557
   6    36   PASS     34155                 PASS    42438
   7    42   PASS     34023                 PASS    38083
   8    48   PASS     34447                 PASS    36407
   9    54   PASS     32854                 PASS    33549
             7/10 seeds passed              10/10 seeds passed
```

Gate fights across the ten seeds: baseline 21 won / 1 lost (+3 stalls
that never reached the ladder); post-fix 30 won / 3 lost, all three
recovered by the reload (seed 4's R2 took rung 3, seed 6's R2 rung 2).
The three post-fix losses share one cause: **the Potion bag was empty**
by R2 (8 of 10 seeds end R2 with `potion=0`; the endgame steer fired 14
times in the sweep and had nothing to drink in those fights):

    [R2 (out of the SE quarter): ride battle 11 out] actor=0 not healing entity 0 (72/279): $E8 restores 50 and a round costs 87, so the turn buys back less than it spends -- acting instead
    R2 (out of the SE quarter): attempt 1 LOST (PARTY WIPED at f34604 (the lib's wipe predicate, 90 frames); reloading the pre-fight blob) ($1DD1.0=0) at (30,43) f34634, probe=false

Six Potions for three of these fights at ~2 a fight is the supply curve
this leg runs on (`level-curve.md`: the Locke scenario has no Potion
seller).  Not done here, cheap to try next: skip the endgame Potion when
the soldier is one hit from dead (3 of the 14 steers fired with him at
1, 12 and 25 HP), and a Potion stop upstream if the route ever passes
one.

## Out of scope, noticed on the way

- `tools/tests/seed_sweep.py --out <relative path>` crashes
  (`outdir.relative_to(ROOT)` on a relative `Path`); an absolute path works.
- The fight driver's finisher gate (`totalMon > 200`) closes the care
  block for a solo actor whose own HP is inside one enemy action; the
  spend rule under it even says the Potion saves and then the keyed chip
  line takes the turn.  A per-actor floor (a heal when the actor's HP is
  under the largest hit seen this fight, gate or no gate) is the lib
  change; this note lands the generator-side equivalent.
- For a solo party, `M.battleLoadStarted()` (any party battle-HP word > 0)
  reads false the instant the one seat hits 0, so `rideOut` stops calling
  `F.frame()` and the driver never logs its `[death]` / `[wipe]` records
  for a solo loss (none in any lost log here).
- Wiped fights never write the battle bag back, so a lost fight's Potions
  are "free" in the inventory counts; the lab's `acts=` field is the
  honest count.
- HeavyArmor's Special is 78-88 in the back row (1.5x Battle); nothing
  here is a one-shot on a topped 279.
