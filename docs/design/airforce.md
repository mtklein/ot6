# The Air Force -- the IAF gauntlet's last fight (#201)

Authored 2026-09-16 from `tools/tests/lab_airforce_template.lua` (the lab;
its header carries the decoded rows), `tools/tests/lab_airforce_bake.lua`
(the fixture) and the v0.17 fc_landing regeneration log
`build/states/fc_landing.log`.  Every number below is quoted from a retained
run log under `build/attempts/airforce-lab/` (the batch runner keeps every
attempt; `python3 tools/tests/airforcelab_aggregate.py` prints them all).

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
4; species `113 -- 145 146 147 --`.  The Speck sits in slot 3, off stage
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

`build/attempts/airforce-lab/bake.log` (`[party teaser]`, the gen's own
route from the `thamasa-done-v1` battery: shop, boarding, the deck kit):

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

(filled from `python3 tools/tests/airforcelab_aggregate.py` below)

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

## What landed

(filled after the campaign)
