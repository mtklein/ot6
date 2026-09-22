# The Air Force -- the IAF gauntlet's last fight (#201)

Authored 2026-09-16 from `tools/tests/lab_airforce_template.lua` (the lab;
its header carries the decoded rows), `tools/tests/lab_airforce_bake.lua`
(the fixture) and the v0.17 fc_landing regeneration log
`build/states/fc_landing.log`.  Every number below is quoted from a retained
run log under `build/attempts/airforce-lab/` (the batch runner keeps every
attempt; `python3 tools/tests/airforcelab_aggregate.py` prints them all).

**The `build/attempts/airforce-lab/` tree is gone** (#222): it lived in the
agent worktree this work was done in and went with it.  Every path under it
cited below is a retained run log lost with the agent worktree; see the
merge message for the quoted lines.  The numbers stand as they were quoted;
they cannot be re-opened from this tree.  `tools/retain_evidence.py` keeps
the next lab's logs.

## What happened in the regeneration

`gen_fc_landing` (v0.17, wt/potion-holds) passed `PASS (frame 61408)
attempts=3/3`.  Both losses were the Air Force, the gauntlet's last fight:

    [retry] attempt 1/3 wipe context: the last battle up (f59040) was formation 0113 FFFF 0145 0146 0147 FFFF; seats at that reading a0:316/960 bp1 a1:528/1129 bp3 a4:0/1048 bp3 - (actor:hp/maxhp bp)
    [retry] attempt 2/3 wipe context: the last battle up (f62430) was formation 0113 FFFF 0145 0146 0147 FFFF; seats at that reading a0:0/960 bp0 a1:445/1129 bp3 a4:314/1048 bp1 - (actor:hp/maxhp bp)

The one `[death]` line attempt 1 logged, and the plan lines before it:

    [IAF] actor=2 no spend (care): item $E9 saves: 550 + 250 = 800 survives the 620 round
    [IAF] actor=2 heal entity 0 (364/960) with $E9 -- restores 250, a round costs 372 (covering an ally)
    [IAF] actor=2 char=4 plan=item
    [IAF] battle f+39000 menu=00 state=00 actor=1 cursor=3 cmds=00,05,02,01 partyhp=90,278,34,0 roundcost=372,574,620,0 monhp=s0:6509/sh3,s2:0/sh3,s4:188/sh1 monsters=3
    [IAF] actor=0 party cure: 3 hurt (worst 1%), boost 1 folds $2D -> $2E (25 MP), all allies
    [IAF] battle f+39600 menu=00 state=00 actor=0 cursor=2 cmds=00,03,02,01 partyhp=328,528,18,0 roundcost=372,574,620,0 monhp=s0:6509/sh3,s2:0/sh3,s4:188/sh1 monsters=3
    [IAF] [death] f+39649 entity 2 char 4 from 18/1048 by nobody (no monster action attributed) bp=3 party_bp=1,3,3,1 -- died holding 3 BP

Three things are in those lines:

1. **The spend rule's "a heal saves" exemption priced a heal EDGAR did not
   take.**  At 550/1048 under a measured 620 round he *was* inside one
   round of death holding 3 BP; `M.spendDecision` waived the spend because
   `item $E9 saves: 550 + 250 = 800` -- a Potion on himself -- and the care
   line then spent that turn on TERRA (`heal entity 0 ... covering an
   ally`).  He took the next AoE at 550, landed at 34, and Seizure ticked
   him out (`by nobody`) before another turn came.  #194's shape.
2. **Deaths here are ticks, not blows.**  MissileBay's Missile ($DD)
   sets status 2 `$40` Seizure; the AoE (Laser Gun's Atomic Ray $B4 / Diffuser
   $B6) drops everyone to double digits and the tick finishes them with no
   monster action to attribute, and no ATB turn in between for the rule to
   fire on.
3. **The pods are unmodelled** (#189): the driver fought the parts as
   three independent slots, and the kill order it fell into (gun first)
   is the one that starts the body's countdown (below).

## The fight, decoded

Formation `$1CB` (`battle_monsters.dat`): present mask `$15` -- slots 0, 2,
4; species `113 -- 145 146 147 --`.  The Speck sits in slot 3, out of the formation
until the body's script restores it.

| part | slot | HP | def / mdef / mpow | speed | shields (Ot6ShieldTbl) | weak (+25) |
|---|---|---|---|---|---|---|
| AirForce `$113` | 0 | 8000 | 150 / 120 / 12 | 35 | **8**, PIERCE | `$84` bolt \| water |
| Laser Gun `$145` | 2 | 3300 | 130 / 140 / 9 | 30 | 3, PIERCE | `$84` |
| Speck `$146` | 3 | 420 | 230 / 160 / 10 | 15 | 1, any class | `$84` |
| MissileBay `$147` | 4 | 3000 | 135 / 150 / 8 | 20 | 3, PIERCE | `$84` |

(`monster_prop.dat` rows at id*32; absorb +23 and null +24 are `$00` on
all four.)  The moves (`magic_prop_en.dat`, 14 bytes at id*14; the AI
from `ff6/src/battle/ai_script.asm` `_275` / `_325` / `_326` / `_327`):

| move | id | targets | element | power | note |
|---|---|---|---|---|---|
| Tek Laser | `$B5` | one | bolt | 20 | the body's default, 2 per turn |
| Atomic Ray | `$B4` | all party | fire | 80 | Laser Gun at HP >= 1536 (with 2 Tek Lasers) |
| Diffuser | `$B6` | all party | bolt | 62 | Laser Gun under 1536, twice a round; the body's second move while 2 monsters stand |
| Missile | `$DD` | one | -- | 4, hit 126 | MissileBay every turn: **status 2 `$40` Seizure**; ~200 on landing, then 13-20 a tick |
| Launcher | `$CD` | random | -- | 8 | MissileBay under 1536 |
| WaveCannon | `$B7` | all party | bolt | 110 | the countdown's end |

**The countdown, measured** (`control_i0/i6/i12`; entity 4 is slot 0, the
body; entity 6 the gun, entity 8 the bay).  The gun's death script is
`if_self_dead / if_num_monsters 2 / set_battle_switch 0,0`: with the bay
alive that leaves two standing, so the switch is set and the body's next
turns are, in order:

    [act] t=3813 start e4 cmd=$24 atk=$03 tgt=$0800 ...   restore_monsters slot 3: the Speck (control_i6)
    [act] t=3886 start e4 cmd=$30 atk=$0B ...             set_status HASTE
    [act] t=3893 start e4 cmd=$21 atk=$22 ...             "Air Force launched a Speck. A Speck absorbs magic!"
    [act] t=4199 start e4 cmd=$21 atk=$38 ...             Count 6
    [act] t=5376 start e4 cmd=$21 atk=$39 ...             Count 5
    [act] t=6212 start e4 cmd=$21 atk=$3A ...             Count 4
    [act] t=7541 start e4 cmd=$21 atk=$3B ...             Count 3
    [act] t=8605 start e4 cmd=$21 atk=$3C ...             Count 2
    [kill] t=10366 slot 0 (id $113) down; order so far s2@2770,s4@7125,s0@10366

Count 1 (`$45`) and then `WAVECANNON` (`attack WAVECANNON` after
`kill_monsters MONSTER_4`) never came: both long control wins killed the
body **two body-turns short of the cannon**.  A body-turn is ~1000 frames
here (hasted), so a fight that outlives the gun by ~7000 frames eats a
110-power bolt AoE.  The bay dying first leaves three standing (no
switch), and the gun dying second leaves one (no switch): **bay, then
gun, then body** never launches the Speck and never counts.  And the
body's `boss_death` ends the fight whatever else stands (`control_i0`:
`kills=s2@4659,s0@5939`, the bay alive at 1321).

## The party at the doorstep

`build/attempts/airforce-lab/bake.log` (lost with the worktree;
`[party teaser]`, the gen's own route from the `thamasa-done-v1` battery:
shop, boarding, the deck kit):

    [party teaser] char=0 L24 hp=960/960 mp=216/216 row=back esper=$FF gear=0E,5C,6E,89,B7,B1 spells=00,04,05,2D,30,32
    [party teaser] char=1 L26 hp=1129/1129 mp=231/231 row=back esper=$06 gear=0F,05,73,8A,D1,B1 spells=
    [party teaser] char=4 L25 hp=1048/1048 mp=218/218 row=back esper=$02 gear=0B,5B,76,8F,B3,B1 spells=
    [bag teaser] tonic=54 potion=62 fenix=28 autocrossbow=1 gil=199955

**TERRA wears no esper and knows no Bolt** (Fire, Drain, Fire2, Cure, Life,
Antdot).  `gen_fc_landing`'s `FIGHT.magic = { [TERRA] = { spell = 2 } }` and
its `nuke = { 2 }` never fire for her: every free turn of hers is a bare
Fight (`actor=0's fight took 0 off the monsters`, twice in the
regeneration's attempt 2; 82-86 a hit in the lab), and the escape config's
`summon = { [TERRA] = ... }` line would have nothing to fire from here.
LOCKE (Maduin worn; casts Bolt at 6 MP) and EDGAR (Shiva worn; the
AutoCrossbow) carry the keys.

## The lab

Fixture `build/states/airforcelab_teaser.mss`, baked by
`lab_airforce_bake.lua` = `gen_fc_landing`'s route verbatim to the Ultros
teaser ($01F0), the last field-control window of the chain (`[bake]
airforcelab_teaser banked at f37770, $021e=39, at (14,6)`; `PASS (frame
47750) attempts=1/3`).  The bake then fought Ultros IV + Chupon and
pressed nothing, looking for a later doorstep:

    [bake] Ultros IV torn down at f47581 ($021e=19); pressing nothing until the game waits on the player
    [bake] the Air Force loaded at f47750 with no input window after Ultros (ultrosDone=true): only the teaser snapshot is banked

169 frames, no dialog, no control: there is no doorstep after Ultros.  So
every lab run stands IDLE frames at the teaser (the seed knob: `$021e`
ticks once a frame, period 60), walks to (22,6) and fights Ultros IV +
Chupon **under the gen's own driver, the same for every policy**, then
the Air Force under the policy.  With the same idle the Ultros fight is
bit-identical across policies, so the Air Force entry (HP, MP, pips, bag,
seed) is paired per idle: a policy column is an A/B against the control
at the same seed.  The declared spread is **10 idles, 0..54 step 6**; the
`[result]` line carries the seed the Air Force's InitBattle drew (`$be`).

Policies (`tools/tests/airforcelab_batch.sh <policy> <idles>`; every one
is fight-driver options the gen could carry; none reads hidden state):

- **control** -- `gen_fc_landing`'s FIGHT as it ships: tactical, boost,
  bank 2, items, healPercent 50, Bolt for TERRA/LOCKE, nuke Bolt.
- **bank0 / bank3** -- the bank at 0 (spend pips as they come) / 3.
- **keyboost** -- `keyBoost = true`: the keyed line spends the bank's
  boost instead of the smallest break.
- **pods** -- `focus` gun (slot 2) -> bay (slot 4) -> body: the order the
  control falls into, made explicit (starts the countdown).
- **bay** -- `focus` bay -> gun -> body: the order that never sets the
  switch.
- **body** -- `focus` body first.
- **summon** -- EDGAR's Shiva once (27 MP); TERRA has no stone.
- **terrafire** -- TERRA's magic line set to Fire2 (`$05`), the strongest
  cast she holds, in place of the Bolt she does not.
- **heal70** -- healPercent 70.

Focus masks were measured before the focus policies ran: `mons=04` on
LOCKE's Bolt moved slot 2, `mons=01` on his Fight moved slot 0, `mons=15`
is the crossbow's all-three, `mons=08` the Speck's slot 3 -- bit = slot.

## Results

`python3 tools/tests/airforcelab_aggregate.py` (full per-attempt rows in
`build/attempts/airforce-lab/table.txt`, lost with the worktree; frames =
mean Air Force battle length; fenix/potion = spent in the Air Force fight;
bp>=3 = deaths holding
three or more pips; speck = fights where the body launched it; wcann =
WaveCannons fired):

```
policy        n wins losses                     frames fenix potion deaths  bp>=3 speck wcann
bank0        10    7 lost_gameover:3              9573     0     21      6      0     7     1
bay          10    9 lost_cap:1                  16524     5     55      6      1    10     6
body         10    8 lost_gameover:2              8113     3     26     11      5     0     0
control      10   10 -                           10568     0     14      1      0    10     0
gunbody      10   10 -                           10465     0     17      1      0    10     0
heal70       10    8 lost_gameover:2             11584     1     23      4      0    10     3
pods         10   10 -                           11432     1     18      1      0    10     2
terrafire    10   10 -                           13296     1     35      2      0    10     2
```

(`bay_trace`, one run at idle 6, is `bay` with the target-window trace; it
replayed `bay_i6` exactly: `t=13527`, same kills.)  Seeds drawn per idle
0..54: `$84 $0C $04 $10 $D8 $B4 $2C $94 $B4 $40` -- idles 30 and 48 drew the
same seed and, under every policy, the same fight, so the spread is **9
distinct Air Force seeds**, not 10.  Three `body` runs (idles 0, 6, 12) were
killed by run.sh's 1800 s wall cap inside the Ultros fight while the host
ran at load ~50 from other worktrees (`KILLED BY THE TIMEOUT: no verdict,
and the run lasted 1806s`); they are kept under `timeouts/` and were re-run
with a 3600 s cap, and those re-runs are the rows above.

The losses, raw:

- **body** (idles 30 and 48, seed `$B4`): the Laser Gun left standing
  fires Atomic Ray twice -- `[AF] [death] f+4009 entity 1 char 1 from
  141/1129 by slot 2 cmd $0C atk $B4 bp=0` and `[AF] [death] f+4010 entity
  0 char 0 from 301/960 by slot 2 cmd $0C atk $B4 bp=3 party_bp=3,0,3,1 --
  died holding 3 BP`.
- **bank0** (idles 6, 30, 48): the same early Atomic Ray shape with the
  pips already spent (`deaths=e1@2573:bp0;e0@3356:bp1`).
- **heal70** (idles 0 and 6): the count ran out.  `heal70_i6`:
  `[act] t=9400 start e8 cmd=$0C atk=$CD` (Launcher, bay at 567) `[hp] t=9402
  entity 0 866 -> 28 (-838)`, `entity 1 679 -> 85 (-594)`; Count 1 at
  t=10823; `[act] t=12214 start e4 cmd=$0C atk=$B7 ... af=4787/sh1 ...
  hp=344,219,0` -- WaveCannon onto a party already down one.
- **bay** (idle 12, `lost_cap` at 24000 frames): the focus steer never
  reached the bay (below), and EDGAR died holding 4 BP --
  `[AF] actor=2 no press: entity 1 (363/1129) is inside one round of death
  (382) and Tools $AA lands 0 chip(s) against 3 shield(s) on slot 4 --
  caring first`, then `[act] t=7638 start e4 cmd=$0C atk=$B5 tgt=$0004`
  `[hp] t=7640 entity 2 393 -> 186 (-207)` and `[act] t=7990 start e6
  cmd=$0C atk=$B5 tgt=$0004` `[hp] t=7991 entity 2 170 -> 0 (-170)`,
  `[AF] [death] f+8075 entity 2 char 4 from 170/1048 by slot 2 cmd $0C atk
  $B5 bp=4 party_bp=0,5,4,1 -- died holding 4 BP`.  Two Tek Lasers from
  two different parts converged on him between his turns (207 + 170 = 377
  from 393), more than any round cost the driver had measured for him.

**Wave Cannon and Launcher, measured.**  `pods_i0`: `[act] t=11904 start e4
cmd=$0C atk=$B7 tgt=$0007` `[hp] t=11905 entity 0 960 -> 395 (-565)`,
`entity 1 1033 -> 321 (-712)`, `entity 2 966 -> 330 (-636)`.
`terrafire_i30`: `[act] t=10705 start e8 cmd=$0C atk=$CD tgt=$0007` (bay at
430) `[hp] t=10707 entity 0 491 -> 123 (-368)`, `entity 1 1072 -> 67
(-1005)`, `entity 2 703 -> 176 (-527)`.  Either one is survivable at full
HP and a wipe at the few hundred HP the in-fight AoE leaves.

**What the lab does and does not separate.**  From the teaser, `control`,
`gunbody`, `pods` and `terrafire` all win 10 of 10; they do not separate on
wins.  `gunbody` and `control` also match on the countdown (Counts summed
over the 10 fights: 41 each) and on WaveCannons (0 each).  The policies
that lose are the ones that leave the Laser Gun up (`body`), spend the
pips as they come (`bank0`), or spend turns the countdown does not allow
(`heal70`'s care, `bay`'s failed steer).  `terrafire`'s frame counts are
confounded by #207 (TERRA's Fire2 lands -- `[hit] t=1583 slot 2 hp=2525
(-483)` -- while the driver records `actor=0's magic took 0 off the
monsters`, which feeds its press and chip decisions).

**The lab does not reproduce the v0.17 losses.**  All three v0.17 attempts
arrived at the Air Force exactly as the lab does -- `partyhp=960,1129,1048`
on the first status line of the fight, and LOCKE's first cast `6 MP of 231`
(attempts 1 and 2 and `control_i0` alike) -- so the arrival state is not
the difference; the Air Force seed is, and the v0.17 seeds are not among
the lab's.  The loss that decides the landing is therefore the v0.17 one
itself, below.

## The steer cannot reach the bay from the gun

`bay` gave up its focus 31 times across its 10 runs, every one the same
line: `[AF] focus steer gave up (mons=04 want=10) -- confirming on whoever
is highlighted`.  `bay_trace_i6` logged the target window every frame
(`python3 tools/tests/airforcelab_tgtwatch.py
build/attempts/airforce-lab/bay_trace_i6.log`, lost with the worktree):

    moves (from --button--> to):
        9  mons=04 chars=00 --left--> mons=01 chars=00
        9  mons=04 chars=00 --right--> mons=00 chars=01
        3  mons=01 chars=00 --down--> mons=10 chars=00
       10  mons=01 chars=00 --right--> mons=00 chars=01
        9  mons=01 chars=00 --right--> mons=04 chars=00
    presses that moved nothing:
        6  mons=04 chars=00 --down--> (no change)
        9  mons=04 chars=00 --up--> (no change)
       21  mons=01 chars=00 --left--> (no change)
        6  mons=01 chars=00 --up--> (no change)

From the gun (`04`) LEFT goes to the body and RIGHT leaves the monsters for
the party; UP and DOWN do nothing.  The bay (`10`) is reached only by DOWN
**from the body**.  The driver's walk (`lib/ot6.lua`, the focus block
after `opts.focus = { {slot=S, mask=M}, ... }`) rotates left/right/down/up
every 6 spins of a 24-spin budget, and its DOWN turns land while the
cursor sits on the gun, so it never presses DOWN from the body.  Once the
gun is dead the cursor starts on the body and DOWN works (`pods` never gave
up).  #189 territory: the parts' layout is a graph, not a row.

## What the driver did, read off the control runs

`control_i0` (seed `$84`): TERRA died at t=2617 holding 2 BP.

    [act] t=2098 start e6 cmd=$0C atk=$B4 tgt=$0007 af=7837/sh7 gun=2660/sh1 speck=420/sh1 bay=2825/sh2 hp=350,1129,1048 bp=2,2,2 st2=40,00,00
    [hp] t=2099 entity 0 350 -> 4 (-346) bp=2 st2=40
    [AF] actor=0 no spend (care): cure $2D is not yet measured; it may save (measure it)
    [AF] actor=0 cure entity 0 (4/960) with $2D, cell 0, 5 MP of 216 -- restores ?, a round costs 795 (not yet measured)
    [AF] actor=2 heal entity 0 (4/960) with $E9 -- restores 250, a round costs 795 (covering an ally)
    [hp] t=2617 entity 0 4 -> 0 (-4) bp=2 st2=00
    [AF] [death] f+2702 entity 0 char 0 from 4/960 by nobody (no monster action attributed) bp=2 party_bp=2,2,2,1

Atomic Ray to 4 HP with Seizure on; her own 5-MP Cure and EDGAR's Potion
were both still walking their menus when the tick landed 518 frames later.
The spend rule had nothing to spend on: her only damage line is a Fight
that lands 82.  She then stayed dead for the fight (`no raise: Fenix Down
would put entity 0 at 120 HP (1/8 of 960), the living enemy's smallest hit
161 ... 120 HP does not survive the 161 hit`), and the win came from the
spend rule firing on the other two at 240/1048 and 249/1129:

    [AF] actor=2 SPEND (care): 240/1048 is inside one round of death (729) holding 3 BP, and no heal saves it (item $E9 +250 = 490) -- Tools $AA (1 chip(s) on slot 0) rather than die holding boost (#175)
    [hit] t=4659 slot 0 hp=6499 (-1338) sh=6 (+0) bp=2,4,3
    [hit] t=4659 slot 2 hp=0 (-2660) sh=0 (+0) bp=2,4,3
    [hit] t=4659 slot 4 hp=1321 (-1504) sh=1 (+0) bp=2,4,3
    [AF] actor=1 SPEND (care): 249/1129 is inside one round of death (575) holding 4 BP, and no heal saves it (item $E9 +250 = 499) -- Fight at 4 BP (5 chip(s) on slot 0) rather than die holding boost (#175)
    [hit] t=5936 slot 0 hp=6334 (-165) sh=5 (-1) bp=2,4,0
    [hit] t=5937 slot 0 hp=6068 (-266) sh=3 (-2) bp=2,4,0
    [hit] t=5938 slot 0 hp=5824 (-244) sh=1 (-2) bp=2,4,0
    [hit] t=5939 slot 0 hp=0 (-5824) sh=0 (-1) bp=2,4,0

A 3-BP AutoCrossbow took 5502 off the three parts in one action (the 0-BP
one before it: 520); a 4-BP Fight broke the body's six shields and killed
it from 6499 in one turn.  The pips were there the whole fight; the keyed
rule (#174) kept them banked (`0 BP lands 1 chip(s), the most the bank
allows; unboosted, the pip banks`) because no boost *breaks* an 8-shield
body in one turn, and the care line took the turns in between.

**The Speck absorbs every party spell while it stands.**  `control_i6`,
after the launch at t=3813:

    [act] t=4655 start e1 cmd=$02 atk=$02 tgt=$0100 af=6589/sh6 gun=0/sh0 speck=420/sh1 bay=2050/sh1 ...
    [AF] actor=1's magic took 0 off the monsters (0 shielded-equivalent over 0 hit(s), 0 a hit; the press rule counts it)
    [act] t=6778 start e1 cmd=$02 atk=$0B tgt=$0800 af=6249/sh4 gun=0/sh3 speck=42/sh1 bay=490/sh0 ...
    [AF] actor=1's magic took 0 off the monsters (0 shielded-equivalent over 0 hit(s), 0 a hit; the press rule counts it)
    [act] t=9220 start e1 cmd=$02 atk=$02 tgt=$0100 af=4437/sh2 gun=0/sh3 speck=0/sh1 bay=0/sh3 ...
    [AF] actor=1's magic took 365 off the monsters (365 shielded-equivalent over 1 hit(s), 365 a hit; the press rule counts it)

A Bolt at the body and a folded Bolt at the Speck itself both land 0; the
first Bolt after the Speck dies lands 365.  The driver has no model of
this (#189): it casts into the Speck for as long as the Speck lives, and
the Speck dies only when the crossbow's random bolts happen to find it.
That is the regeneration's `actor=1's magic took 0 off the monsters`
(attempt 1, f+33000 and f+35400, both after the gun's death) and the pace
that let the count run out.

## The decisive fight: v0.17 attempt 1, replayed

The v0.17 regeneration's loss is deterministic.  `seed_sweep.py fc_landing`
on the unchanged generator (`build/attempts/airforce-lab/sweep_baseline/`,
lost with the worktree) returned, for shifts 0, 10, 20 and 30:

    seed  1 shift  10: FAIL frames=59364 wipe GAME OVER fired ...
    seed  0 shift   0: FAIL frames=59364 wipe GAME OVER fired ...
    seed  2 shift  20: FAIL frames=59364 wipe GAME OVER fired ...
    seed  3 shift  30: FAIL frames=59364 wipe GAME OVER fired ...

each with v0.17 attempt 1's own wipe context (`seats at that reading
a0:316/960 bp1 a1:528/1129 bp3 a4:0/1048 bp3`).  The shift was applied
(`seed shift done at f1406 ($021e=5, ...)`) and changed nothing: every
sweep seed reaches `[IAF battle 11] f47210`.  (v0.17's retried attempt 2
with the same 20-frame shift did diverge, by battle 5; its boot point read
`$021e=57` against the sweep's `$021e=55`.)  So this route has one
reproducible losing Air Force fight, and the rest of the route up to it
is fixed: a generator change that touches only the Air Force's driver
replays that exact fight.

Three one-off generator copies (`build/attempts/airforce-lab/
gen_fc_landing_cand_*.lua`, lost with the worktree; shift 0, retries off,
nothing published), each a second driver built from `FIGHT` and used only
while formation `$113` is up:

| candidate | Air Force driver | verdict |
|---|---|---|
| `fresh` | `FIGHT`, no focus | `FAIL ... frame=59364` -- `wipe context ... a0:316/960 bp1 a1:528/1129 bp3 a4:0/1048 bp3` (v0.17's, exactly) |
| `pods` | focus gun -> bay -> body | `PASS (frame 59992) attempts=1/1` |
| `gunbody` | focus gun -> body -> bay | `PASS (frame 59480) attempts=1/1` |

All three reach `[IAF battle 11] f47210`.  `fresh` shows that the driver's
state carried over from the earlier waves is not what lost; the kill order
is.  The two fights are line-for-line identical through f+3900 (the gun is
dead by f+3000 in both: `monhp=s0:7842/sh7,s2:0/sh0,s4:2821/sh2`) and apart
by f+4800 (`fresh`: `s0:7173/sh6,...,s4:2103/sh1`; `gunbody`:
`s0:7675/sh6,...,s4:2641/sh1`).  By f+6300 `gunbody` had the bay dead and
the body falling (`s0:6348/sh5,s2:0/sh3,s4:0/sh0`), `fresh` had neither
(`s0:7173/sh6,s2:0/sh3,s4:2103/sh1`); `gunbody` read `s0:3768/sh2` at
f+8100 and won, `fresh` wiped.  The focus changes which target each
single-target turn lands on; in this fight the crossbow's all-target
spend still took the bay first.

## What landed

`tools/tests/gen_fc_landing.lua`: a second fight driver, `FIGHT` plus
`focus = { gun (slot 2, mask $04), body (slot 0, $01), bay (slot 4, $10) }`,
driving every frame the Air Force's formation (`$113`) is loaded; every
other IAF battle keeps `FIGHT` unchanged.  Chosen over `pods` because on
the lab it matched `control` on wins, Counts and WaveCannons (10/10, 41, 0)
where `pods` took two cannons, and it passed the decisive fight 512 frames
sooner.  The masks are the measured window bits; the gun is the default
cursor and the body is one LEFT from it, so the order never asks for the
steer this lab showed cannot reach the bay from the gun.

`ninja build/states/fc_landing.mss.lua`:

    [ot6]   [IAF battle 11] f47210
    [ot6] IAF: 11 battles; FC landing at (4,12)
    [ot6] PASS (frame 59480) attempts=1/3

No `[death]` line in the Air Force fight.  The `fc-landing-v1` battery
checkpoint that `gen_fc_alcove` cold-boots was not re-sealed here.

What the landing does not claim: the lab could not separate `gunbody` from
`control` from the teaser, and the sweep cannot vary this route, so the
evidence that the order matters is the one reproducible losing fight
(`fresh` FAIL vs `gunbody` PASS) plus the mechanism (the countdown only
the body's death stops).  It is not a success rate.
