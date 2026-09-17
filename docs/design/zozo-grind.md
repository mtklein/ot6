# The Zozo grind — the Iron Fist that casts Stone (#195)

Authored 2026-09-16 from `tools/tests/zozogrindlab.py` (the lab; its
docstring carries the policies), the v0.17 tree's
`build/states/zozo_arrival.log` (2026-09-16 14:15, copied to
`build/lab/zozo-grind/baseline-coordinating-tree.log`) and two 6-seed
sweeps of `zozo_arrival`, before and after the change.  Every number below
is quoted from a retained log under `build/lab/zozo-grind/` (the lab keeps
every attempt; `python3 tools/tests/zozogrindlab.py aggregate` prints them
all, and `build/lab/zozo-grind/aggregate.txt` is that output).

**The `build/lab/zozo-grind/` tree is gone** (#222): it lived in the agent
worktree this work was done in and went with it.  Every path under it cited
below is a retained log lost with the agent worktree; see the merge message
for the quoted lines.  The numbers stand as they were quoted; they cannot be
re-opened from this tree.  `tools/retain_evidence.py` keeps the next lab's
logs.

## What happened in the qualification

`zozo_arrival` (gen_zozo2_arrival) in the v0.17 tree passed first try,
`PASS (frame 198707) attempts=1/3`, and spent six deaths and five Fenix
Downs in randoms doing it (`audit_fenix.py`: `RANDOM  Fenix in randoms --
underleveled or lab these encounters`).  Four of the six name the same
seat and the same attack:

    [worldNavTo] [death] f+1025 entity 3 char 5 from 407/407 by slot 2 cmd $0C atk $9F (ONE ACTION from >= 80%) bp=0 party_bp=0,2,2,0
    [worldNavTo] [death] f+2596 entity 2 char 4 from 156/354 by slot 2 cmd $0C atk $9F bp=3 party_bp=1,3,3,1 -- died holding 3 BP
    [worldNavTo] [death] f+1315 entity 2 char 4 from 235/354 by slot 2 cmd $0C atk $9F bp=0 party_bp=0,2,0,2
    [worldNavTo] [death] f+1570 entity 1 char 6 from 295/443 by slot 2 cmd $0C atk $9F bp=0 party_bp=0,0,0,0
    [worldNavTo] [death] f+2050 entity 0 char 1 from 42/447 by nobody (no monster action attributed) bp=0 party_bp=0,2,0,0
    [worldNavTo] [death] f+3644 entity 3 char 5 from 37/511 by nobody (no monster action attributed) bp=2 party_bp=1,4,2,2

and every one of those fights read the same stage at f+1:
`monhp=s0:412/sh3,s2:333/sh2 monsters=2`.

The 6-seed sweep of the same generator in this tree
(`python3 tools/tests/seed_sweep.py zozo_arrival --seeds 6 --jobs 3`,
retries off) says the qualification was a good draw:

```
seed shift verdict  frames  class        message
   0     0 FAIL     136894  wipe         GAME OVER fired (GameOver read x0, TitleScreen exec x0, battle wipe x1) -- the run lost and any further input auto-Continues the last save,
   1    10 PASS     201529
   2    20 FAIL     209734  timeout      timeout after 4000 frames driving toward into Jidoor (map 198)
   3    30 PASS     210180
   4    40 FAIL     195440  timeout      timeout after 4000 frames driving toward into Jidoor (map 198)
   5    50 PASS     219965

3/6 seeds passed; table in build/lab/zozo-grind/sweep-baseline/summary.tsv
```

(That `sweep-baseline/` table and its per-seed logs went with the worktree
too.)

`[death]` / `used $F0` / deaths to `atk $9F` per seed (grep counts over
`sweep-baseline/zozo_arrival.seedNN.log`): 9/5/5, 6/6/6, 9/8/6, 5/5/4,
12/12/11, 12/11/6 — **53 deaths, 47 Fenix Downs, 38 of the deaths to
`atk $9F`** in six attempts.  The two timeouts are a separate generator
bug (below, "The door step").

## The row, decoded

The grind column x=34 (y=99..112) and 158 of the crossing's 177 tiles are
world battle group 10 (`tools/tests/probe_zozo_zones.lua` reads the group
per tile the way `CheckBattleWorld` does; the grid is
`build/lab/zozo-grind/zones.log`, lost with the worktree).  Group 10,
decoded by `tools/tests/zozogrindlab/decode_group10.py`:

| roll | formation | bodies |
|---|---|---|
| 31.25% | $064 | slot 0 Vulture ($02A), slot 2 **Iron Fist** ($06C) |
| 31.25% | $065 | Mind Candy ($08C) x4 |
| 31.25% + 6.25% | $060 | Iron Fist x2 (slots 0, 1), Mind Candy x2 (slots 2, 3) |

| | value | source |
|---|---|---|
| Vulture $02A | L15, HP 412, speed 30, atk 13, def 100, mdef 155; 3 shields at f+1 | `monster_prop.dat` +$0540 |
| **Iron Fist $06C** | **L15**, HP 333, speed 35, atk 13, def 75, mdef 145, mpow 10; absorbs poison; 2 shields | `monster_prop.dat` +$0D80 |
| Mind Candy $08C | L15, HP 290, speed 30, atk 14, def 105, mdef 165 | `monster_prop.dat` +$1180 |
| Iron Fist AI | `if_num_monsters 1` -> `attack BATTLE, STONE, STONE`; else Battle/Battle/Nothing, wait, Battle/Battle/Special | `ai_script.asm:855-865` |
| Vulture AI | `if_num_monsters 1` -> `attack SPECIAL, SHIMSHAM, SHIMSHAM`; else Battle/Shimsham/Battle, wait, Battle/Battle/Nothing | `ai_script.asm:841-851` |
| Mind Candy AI | Battle/Battle/Nothing, wait, Battle/Battle/Special; no solo branch | `ai_script.asm:869-874` |
| `cmd $0C` | the Lore command | `const.inc:539` |
| **Stone `atk $9F`** | power 40, hit 75, targeting $63, no element, status2 **$20 = Muddle**, special effect **$22** | `magic_prop_en.dat` $9F: `63 00 00 26 00 16 28 02 4b 22 00 20 00 00`; `const.inc:756` |
| effect $22 | `lda $3b18,x / cmp $3b18,y / bne @3933 / lda #$0d / adc $bc / sta $bc`: caster level == target level adds 13 + carry (set by the equal compare) = **14** to the damage multiplier | `battle_main.asm` `TargetEffect_22` (@3922) |
| the multiplier | `ApplyDmgMult`: `+A *= (1 + ($bc / 2))`, so 14 is **x8** | `battle_main.asm` @370b |

So `slot 2 cmd $0C atk $9F` is formation $064's Iron Fist casting Stone,
which it does only when **it is the last body on the stage**.  The Vulture
in slot 0 is where the driver's lines aim first (the qualification's
`actor=3 KEYED: Fight at 1 BP lands 3 chip(s) on slot 0's 3 shield(s)`,
and the last status before each of the four `atk $9F` deaths reads
`s0:0/sh0` with the Iron Fist at `s2:333/sh2` (twice), `s2:254/sh2` and
`s2:256/sh2`), dies
first, and leaves the Iron Fist alone on a two-in-three Stone line.  Stone is a sizeable hit with Muddle on it
for anyone, and **x8 for a member whose level equals the Iron Fist's
L15** — and the grind walks every member through L15.

### Measured

The lab's `[hit]` lines carry the engine's damage word at `_writedamage`
(before `ApplyDmg` clamps it to HP) and every seat's battle level ($3b18),
over 198 Stone casts in 25 lab attempts (68 wrote no damage word: a miss or
a Muddle-only land):

```
non-parity single      46 casts  raw 298..347   levels 13, 14, 16, 17, 18
non-parity all-target 167 hits   raw 147..175   levels 13, 14, 16, 17, 18
parity (L15) single     9 casts  raw 2353..2800
parity (L15) all-target 27 hits  raw 1169..1393
```

    [zozogrindlab] [hit] f13614 IronFist(s2) L15 cmd=0C atk=Stone tgt=000F dmg=172,163,160,159 raw=172,163,160,159 lvl=13,13,14,14 kills=0 party=31,147,17,174
    [zozogrindlab] [hit] f22604 IronFist(s2) L15 cmd=0C atk=Stone tgt=000F dmg=0,153,156,403 raw=16383,153,156,1296 lvl=13,13,14,15 kills=1 party=289,135,186,0
    [zozogrindlab] [hit] f74721 IronFist(s2) L15 cmd=0C atk=Stone tgt=0001 dmg=334,0,0,0 raw=2769,16383,16383,16383 lvl=15,15,16,16 kills=1 party=0,181,420,431

The ratio is the decode's x8 (147 -> 1169, 298 -> 2353).

### Does a topped member survive it, by level?

Party levels over the qualification's grind (its roster lines):

```
hop 1          LOCKE L13 EDGAR L14 SABIN L14 CELES L13
hop 11         LOCKE L13 EDGAR L14 SABIN L15 CELES L13
hop 13         LOCKE L13 EDGAR L14 SABIN L15 CELES L14
lap 4          LOCKE L14 EDGAR L14 SABIN L15 CELES L14  f34024
lap 10         LOCKE L14 EDGAR L15 SABIN L15 CELES L14  f49823
lap 13         LOCKE L14 EDGAR L15 SABIN L16 CELES L15  f59368
lap 14         LOCKE L15 EDGAR L15 SABIN L16 CELES L15  f62544
lap 21         LOCKE L15 EDGAR L16 SABIN L16 CELES L15  f83096
lap 22         LOCKE L15 EDGAR L16 SABIN L16 CELES L16  f89408
lap 27         LOCKE L16 EDGAR L16 SABIN L17 CELES L16  f99391
...
lap 56         LOCKE L17 EDGAR L18 SABIN L18 CELES L18  f183731
```

| level | max HP on this route (roster lines) | single Stone (298..347 / parity 2353..2800) | all-target Stone (147..175 / parity 1169..1393) |
|---|---|---|---|
| L13 | LOCKE 314, CELES 310 | **dies** to a roll of 314+ (heal75 s0: `raw=344` on LOCKE `314/314`, `kills=1`) | survives topped |
| L14 | 353 / 354 / 349 | survives topped, by 2..7 HP | survives topped |
| **L15** | 397 / 398 / 407 / 393 | **dies at any HP** | **dies at any HP** |
| L16 | 447 / 448 / 457 / 443 | survives topped | survives topped |
| L17-18 | 497..629 | survives topped | survives topped |

Every member spends 20-40 laps at L15 (SABIN from crossing hop 11, CELES
from lap 13 to 22, LOCKE from 14 to 27, EDGAR from 10 to 21).  Top-ups do
not change a parity roll, and the non-parity single roll is within a few
HP of an L14 member's maximum, so a member under ~95% at L13/L14 dies to
it too.

### The deaths the log calls "nobody"

Stone's second half is Muddle.  Every `[death] ... by nobody` in the lab
follows a Stone cast and a `MUDDLED` driver line in the same battle
(control 10/10, heal75 6/6, care80 11/11, breakfirst 7/7, boostfight 5/5
with 4 MUDDLED lines, gentle 1/1): muddled members hitting each other, and
members whose turn the driver deferred because it was muddled (`actor=N is
MUDDLED (STATUS2 $20) -- not planning ... deferring the window (X)`).  So
the "nobody" deaths are Stone's too.

## The lab

`tools/tests/zozogrindlab.py`.  **Fixture**: `build/states/zozogrind_landing.mss`,
baked by `zozogrindlab.py bake` — the generator itself with a `saveState`
after "west landing" (`build/lab/zozo-grind/bake/bake.log`, lost with the
worktree: boots `figaro_submerged.mss.lua`, plays the castle exit,
`[west landing] c1 L13 xp=6831 314/314 hp ... | gil=12501 tonic=99
potion=27 fenix=15`).  Each policy is a derived copy of the generator (the landing fixture in place of
the castle exit, the policy written into the generator's `GRIND` table,
read-only observers, a `[result]` line after "grind done"), run once per
seed under `run.sh` with retries off and `OT6_SEED_SHIFT` idle frames at
the fixture load.  The crossing and grind are 150-200k frames of play, so
the formations and seeds diverge from the first fight on; the declared
spread is **seeds 0,12,24,36,48** for control and focus, and **0,24,48**
for the other policies (a person's grind is long, the matrix was cut to
fit the machine; same three seeds in every policy, so those three are a
paired comparison).  None of the policies reads hidden state: the Iron
Fist's Stone is visible the first time it casts, and its kill order is
chosen by species on the screen.

Policies (a person's levers):

- **control** — the generator as it shipped (lap care 0.6, post-battle
  care 0.65, healPercent 60, the walk driver's bank, keyed chip line,
  SABIN to the back row).
- **heal75** — healPercent 75: the in-battle top-up comes sooner (Potions
  under the hit).
- **care80** — lap care and post-battle care at 0.8.
- **breakfirst** — bank 0.
- **boostfight** — `keyed = false`: the plain boost-Fight default.
- **allback** — everyone in the back row.
- **focus** — kill order: Iron Fists first (the driver's `focus`, species
  read off $57C0 every frame).
- **gentle** — first grind the group-9 column x=30, y=53..61 by the castle
  (Red Fang / Vulture only, no Iron Fist) until every member is L16, then
  cross.

### Results

`python3 tools/tests/zozogrindlab.py aggregate` (n = attempts; done =
reached "grind done"; fenix = Fenix Downs resolved, care + battle; wipe =
canary wipes; frames = mean over done attempts, from the landing fixture;
laps = mean x=34 laps + gentle laps; stone = Stone casts; kills = members
Stone killed; parity = those at L15):

```
policy        n done deaths fenix wipe  frames  laps stone  kills parity  stone raw (min..max, non-parity / parity)
control       5    3     27    23    2  186413  58.0    56    16      8  147..347 / 1169..2769
focus         5    5      2     2    0  180372  57.6     3     2      2  160..309 / 1248..1312
heal75        3    2     16    15    1  187551  60.5    32    10      6  153..347 / 1169..2577
care80        3    3     23    23    0  204496  61.3    51    12      7  147..347 / 1232..2800
breakfirst    3    2     18    17    1  183759  57.0    41    11      6  147..338 / 1169..1313
boostfight    3    3     13    14    0  174543  58.3    11     8      7  149..332 / 1185..2464
allback       3    2     19    16    1  205078  57.5    39    15      9  149..338 / 1185..2769
gentle        3    3      2     2    0  192530  88.7     9     1      0  151..347 / -
```

Paired on seeds 0, 24, 48:

```
policy        n done deaths fenix wipe  frames  laps stone  kills parity  stone raw (min..max, non-parity / parity)
control       3    2     18    17    1  183759  57.0    41    11      6  147..338 / 1169..1313
focus         3    3      2     2    0  180647  57.3     3     2      2  160..309 / 1248..1312
heal75        3    2     16    15    1  187551  60.5    32    10      6  153..347 / 1169..2577
care80        3    3     23    23    0  204496  61.3    51    12      7  147..347 / 1232..2800
breakfirst    3    2     18    17    1  183759  57.0    41    11      6  147..338 / 1169..1313
boostfight    3    3     13    14    0  174543  58.3    11     8      7  149..332 / 1185..2464
allback       3    2     19    16    1  205078  57.5    39    15      9  149..338 / 1185..2769
gentle        3    3      2     2    0  192530  88.7     9     1      0  151..347 / -
```

What the table says:

1. **The kill order is the lever.**  focus is 2 deaths and 2 Fenix in 5
   attempts, 5/5 reaching L18, against control's 27 deaths, 23 Fenix and 2
   wipes; on the paired seeds 2 against 18.  Stone casts fall from 56 to 3:
   with the Iron Fist dead first, the Vulture or the Mind Candies are what
   is left alone, and neither has a Stone line.  Its two deaths (seed 24)
   are formation $060's second Iron Fist (`by slot 1`, 87 HP) left alone
   after EDGAR's AutoCrossbow (`actor=2's skill took 887 off the monsters
   ... over 4 hit(s)`) and a Fight finished both Mind Candies (`monhp=s0:0/sh1,
   s1:87/sh1,s2:0/sh3,s3:0/sh3` at f+2400): one all-target parity Stone
   killing CELES and EDGAR at L15.  The focus steer also gave up once in
   that fight (`focus steer gave up (mons=08 want=01)`).  It is also the fastest policy that
   reaches L18 every time (mean 180372 frames from the landing).
2. **Levels around the parity are the other lever.**  gentle (group-9 laps
   to L16 first) is 2 deaths in 3 with 0 parity kills, but costs 62 gentle
   laps and ~12k more frames than focus, and its two deaths are a Stone at
   L16 on LOCKE (`from 305/447`, non-parity) and a muddled follow-up.
3. **Care thresholds do not touch it.**  care80 spent the most frames
   (204496) and still lost 23 members; heal75 lost 16 and wiped once.  A
   parity roll (1169..2800) is over every max HP on the route, and the
   non-parity roll kills an L13 at full HP.
4. **Rows do not touch it.**  allback lost 19 and wiped once: Stone is a
   lore.
5. **breakfirst is control** (bank 0 == the walk driver's nil bank: same
   frames, same deaths on seeds 0 and 48).
6. **boostfight** (no keyed line) is the best of the non-focus levers
   (13 deaths, 0 wipes, 11 Stone casts).  Why it leaves the Iron Fist alone
   less often was not measured here (a plausible reading is that without
   the keyed line the swings are not steered onto slot 0's break); three
   attempts, and it still lost 13 members.

**Verdict: focus** (Iron Fists first), as a generator config field.

Every raw `[death]` line, per policy and seed, is in the appendix.

## The door step

The two baseline timeouts are the generator's, not the grind's.
`walk(27, 129, "Jidoor approach", { arrive = not worldMode })` then held
DOWN for 4000 frames with no battle handling; a random on the last step
put the party in a fight the hold could not play (seed 2's failure frame:
`attempt1_timeout_f209734.png`, a Vulture and an Iron Fist with the
command window open).  `probe_jidoor_door_walk.lua` shows `worldNavTo`
cannot take that step itself: it reaches the entrance tile and the town
does not load (`[probe] after the walk: map=0 world=true`).  The generator
now takes both door steps (Jidoor and Zozo) with `enterDoor`: press toward
the door while the world has control, play any battle with the walk's
driver, and run a care stop on the far side if a fight happened.

## What landed

`gen_zozo2_arrival.lua` now carries a `GRIND` config (each lever above is a
field) with **`focus = "ironfist"`**: every fight driver the walk builds is
wrapped so its kill order is recomputed each frame from the stage's
species words, Iron Fists first.  Everything else is as it shipped.  And
`enterDoor` for the two door steps.

`ninja build/states/zozo_arrival.mss.lua` (graph seed):

    [ot6] [grind] 57 laps: min L18 (target L18), gil=83416, f175816
    [ot6] [zozo_arrival] c1 L18 xp=17429 546/558 hp 139/139 mp | c4 L18 xp=18310 554/559 hp 134/138 mp | c5 L19 xp=20039 601/629 hp 142/146 mp | c6 L18 xp=17882 554/554 hp 132/147 mp | gil=82972 tonic=55 potion=39 fenix=21
    [ot6] PASS (frame 190854) attempts=1/3

0 `[death]` lines (v0.17: 6), and `python3 tools/audit_fenix.py
build/states/zozo_arrival.log -v`:

    Fenix audit: no threshold violations in the scanned logs (1 logs, 0 Fenix Down(s) resolved).
    Boost audit: no party deaths in the scanned logs (1 logs).

(v0.17: `6 Fenix Down(s) resolved`, five of them `used $F0` care lines.)
The arrival bag is `tonic=55 potion=39 fenix=21`.

The 6-seed sweep, before and after (retries off, every seed a first try):

```
                 baseline                                    post-fix
seed shift   verdict frames  class    deaths Fenix   verdict frames  deaths Fenix
   0     0   FAIL    136894  wipe          9     5   PASS    190854       0     0
   1    10   PASS    201529                6     6   PASS    200324       0     0
   2    20   FAIL    209734  timeout       9     8   PASS    193082       0     0
   3    30   PASS    210180                5     5   PASS    192244       0     0
   4    40   FAIL    195440  timeout      12    12   PASS    197676       0     0
   5    50   PASS    219965               12    11   PASS    199774       0     0
             3/6 seeds passed; 53 deaths, 47 used $F0      6/6 seeds passed; 0, 0
```

(`sweep-baseline/summary.tsv`, `sweep-postfix/summary.tsv`; deaths and
Fenix are grep counts of `[death]` and `used $F0` in each seed's log.)  No
post-fix seed drew a battle on a door step (`[care after the fight at` 0
times), so `enterDoor`'s battle branch is not exercised by these runs; the
two baseline timeouts are passes after the change because the seeds moved,
not because that branch was proven.

## #194: the deaths holding BP

`tools/tests/zozogrindlab/banked_deaths.py` prints, for every death holding
BP, the battle's status lines once the member's HP sat inside their
measured round cost and every line naming that actor
(`build/lab/zozo-grind/banked-sweep.txt`, lost with the worktree).  The
spend rule (#175, `M.spendDecision` via `spendPlan`) is asked only inside
the dying actor's own command window, and only when
`hp <= roundCost[actor]`.  Across the
qualification and the baseline sweep the deaths at 3+ BP fall in three
shapes:

1. **No command window between entering the round and dying.**  The
   qualification's EDGAR: status `partyhp=128,138,156,400
   roundcost=181,159,169,0` at f+2100 (156 <= 169, inside), EDGAR's last
   driver line is `actor=2 char=4 plan=fight` at f+~900 (log line 9598),
   and the Stone lands at f+2596 before his next window.  The rule was
   never asked.  Firing would have needed the pips spent a window earlier,
   when he was at 156 with a round cost of 0 measured on him (the round
   cost is per member, and his was unmeasured until the f+2100 status).
2. **Muddled.**  Sweep seed 2 EDGAR (`bp=3`) and seed 5 LOCKE (`bp=4`):
   the windows inside the round went to `actor=N is MUDDLED (STATUS2 $20)
   -- not planning: its command would be re-aimed by the engine; deferring
   the window (X)`.  A muddled actor's spend would be re-aimed by the
   engine; the rule cannot fire there as written.
3. **Pre-empted by the unmuddle line.**  Sweep seed 0 EDGAR (`2/502`,
   `bp=3`): inside one round from f+600 (`partyhp=305,305,167,363
   roundcost=0,0,167,0`, 167 <= 167), his windows at f+1800 and f+3300 went
   to `actor=2: entity 0 (143/447) is MUDDLED (STATUS2 $20) -- a plain
   unboosted Fight on the ally clears it; before any other plan` and the
   same for entity 3.  That rule sits "before any other plan", ahead of the
   spend rule.  Sweep seed 0 CELES (`53/443`, `bp=3`) died the same way
   while her own round cost was still unmeasured (`first status line with
   E inside one round: never`).

For #194: shape 3 is an ordering question in the driver (unmuddle-an-ally
ahead of spend-before-you-die); shape 1 needs the rule to look ahead of the
measured round (an unmeasured member facing a monster whose hits on others
are measured); shape 2 is out of the rule's reach while Muddle holds.

## Out of scope, noticed on the way

- `H.monsterIds()` reads the Vulture as `$12A` and the Red Fang as `$178`
  in these formations (high bit wrong); `$57C0` (`H.FORMATION`) reads
  `$02A` / `$078`.  The lab and the landed focus use `$57C0`.
- `worldNavTo` builds its fight driver from a fixed option list (no
  `keyed`, `focus`, `tools`, `traceTgt`), so a generator cannot set those
  without wrapping `H.newFightDriver`, as this one did.  (#209: every
  walker now takes a `fight = { ... }` table, `H.fightDriverFor`, and the
  generator passes its focus through it.)
- `bank = 0` and the walk driver's default (`bank = nil`) are the same
  policy: breakfirst matched control frame-for-frame on seeds 0 and 48
  (`frame=179663`; the seed-48 wipe at `frame=33339`).
- The first allback batch never moved LOCKE: the lab's boot replacement
  cut the generator's `setRows` step with the castle exit.  Those three
  attempts were kept under `build/lab/zozo-grind/allback-norows-invalid/`
  (lost with the worktree) and are not in the table; the lab re-applies the
  rows now.
- `[unknown-menu] state $04` and `$10` fire in these fights (`unknown_menu_04_f11046.png`, `unknown_menu_10_f14416.png` in the focus seed 0 run).
- The Tonic bag leaves the grind at 0 in the baseline sweep's seed 2
  (`tonic=0 potion=22 fenix=10` at "Jidoor approach"); the landed run
  arrives with 55.

## Appendix: every [death] line in the lab

```
== control
seed00.log: DONE frame=179663 laps=56 gentle=0 deaths=5 fenix=4+1 wipes=0
  [worldNavTo] [death] f+1834 entity 3 char 5 from 355/407 by slot 2 cmd $0C atk $9F (ONE ACTION from >= 80%) bp=1 party_bp=0,2,2,1
  [worldNavTo] [death] f+1291 entity 3 char 5 from 249/407 by slot 2 cmd $0C atk $9F bp=2 party_bp=0,0,2,2
  [worldNavTo] [death] f+1025 entity 2 char 4 from 398/398 by slot 2 cmd $0C atk $9F (ONE ACTION from >= 80%) bp=2 party_bp=0,2,2,0
  [worldNavTo] [death] f+1025 entity 3 char 5 from 274/407 by slot 2 cmd $0C atk $9F bp=0 party_bp=0,2,2,0
  [worldNavTo] [death] f+2659 entity 2 char 4 from 176/448 by slot 2 cmd $0C atk $9F bp=1 party_bp=1,3,1,1
seed12.log: DONE frame=191720 laps=60 gentle=0 deaths=6 fenix=6+0 wipes=0
  [worldNavTo] [death] f+1322 entity 0 char 1 from 309/314 by slot 2 cmd $0C atk $9F (ONE ACTION from >= 80%) bp=0 party_bp=0,0,2,2
  [worldNavTo] [death] f+1395 entity 3 char 5 from 378/407 by slot 2 cmd $0C atk $9F (ONE ACTION from >= 80%) bp=0 party_bp=0,2,0,0
  [worldNavTo] [death] f+1025 entity 0 char 1 from 289/314 by slot 2 cmd $0C atk $9F (ONE ACTION from >= 80%) bp=0 party_bp=0,2,2,0
  [worldNavTo] [death] f+1499 entity 0 char 1 from 334/397 by slot 2 cmd $0C atk $9F (ONE ACTION from >= 80%) bp=0 party_bp=0,2,2,0
  [worldNavTo] [death] f+1786 entity 3 char 5 from 208/511 by nobody (no monster action attributed) bp=0 party_bp=0,2,0,0
  [worldNavTo] [death] f+1611 entity 2 char 4 from 173/502 by slot 2 cmd $0C atk $9F bp=0 party_bp=0,0,0,0
seed24.log: DONE frame=187856 laps=58 gentle=0 deaths=7 fenix=7+1 wipes=0
  [worldNavTo] [death] f+2398 entity 1 char 6 from 92/310 by nobody (no monster action attributed) bp=0 party_bp=1,0,0,0
  [worldNavTo] [death] f+3028 entity 0 char 1 from 19/314 by nobody (no monster action attributed) bp=1 party_bp=1,1,1,1
  [worldNavTo] [death] f+1424 entity 0 char 1 from 295/314 by slot 2 cmd $0C atk $9F (ONE ACTION from >= 80%) bp=0 party_bp=0,0,2,0
  [worldNavTo] [death] f+1025 entity 3 char 5 from 403/407 by slot 2 cmd $0C atk $9F (ONE ACTION from >= 80%) bp=0 party_bp=0,2,2,0
  [worldNavTo] [death] f+1784 entity 3 char 5 from 241/457 by nobody (no monster action attributed) bp=0 party_bp=0,2,0,0
  [worldNavTo] [death] f+1442 entity 1 char 6 from 196/443 by nobody (no monster action attributed) bp=2 party_bp=0,2,2,0
  [worldNavTo] [death] f+1469 entity 2 char 4 from 328/502 by slot 2 cmd $0C atk $9F bp=2 party_bp=0,0,2,0
seed36.log: FAIL frame=None laps=None gentle=None deaths=3 fenix=0+0 wipes=1 [retry] attempt 1/1 FAILED class=wipe frame=15593 totalframes=15594 shift=36 phase=33 screenshot=/Users/mtklein/ot6/.claude/worktrees/agent-ac853ed10d5b24439/bu
  [worldNavTo] [death] f+2133 entity 1 char 6 from 35/310 by nobody (no monster action attributed) bp=2 party_bp=0,2,0,0
  [worldNavTo] [death] f+2625 entity 2 char 4 from 17/354 by nobody (no monster action attributed) bp=0 party_bp=0,2,0,1
  [worldNavTo] [death] f+2807 entity 0 char 1 from 31/314 by slot 2 cmd $00 atk $EE bp=1 party_bp=1,2,1,1
seed48.log: FAIL frame=None laps=None gentle=None deaths=6 fenix=4+0 wipes=1 [retry] attempt 1/1 FAILED class=wipe frame=33339 totalframes=33340 shift=48 phase=6 screenshot=/Users/mtklein/ot6/.claude/worktrees/agent-ac853ed10d5b24439/bui
  [worldNavTo] [death] f+1944 entity 2 char 4 from 146/354 by nobody (no monster action attributed) bp=2 party_bp=0,1,2,0
  [worldNavTo] [death] f+2697 entity 3 char 5 from 172/363 by slot 2 cmd $0C atk $9F bp=1 party_bp=1,2,3,1
  [worldNavTo] [death] f+1948 entity 2 char 4 from 161/354 by nobody (no monster action attributed) bp=2 party_bp=0,1,2,0
  [worldNavTo] [death] f+2704 entity 3 char 5 from 185/363 by slot 2 cmd $0C atk $9F bp=1 party_bp=1,2,3,1
  [worldNavTo] [death] f+1628 entity 3 char 5 from 378/407 by slot 2 cmd $0C atk $9F (ONE ACTION from >= 80%) bp=0 party_bp=0,2,0,0
  [worldNavTo] [death] f+2684 entity 0 char 1 from 59/353 by nobody (no monster action attributed) bp=1 party_bp=1,3,1,0
== focus
seed00.log: DONE frame=176015 laps=58 gentle=0 deaths=0 fenix=0+0 wipes=0
seed12.log: DONE frame=178143 laps=58 gentle=0 deaths=0 fenix=0+0 wipes=0
seed24.log: DONE frame=183703 laps=56 gentle=0 deaths=2 fenix=2+0 wipes=0
  [worldNavTo] [death] f+2682 entity 1 char 6 from 226/393 by slot 1 cmd $0C atk $9F bp=1 party_bp=2,1,0,2
  [worldNavTo] [death] f+2682 entity 2 char 4 from 343/398 by slot 1 cmd $0C atk $9F (ONE ACTION from >= 80%) bp=0 party_bp=2,1,0,2
seed36.log: DONE frame=181775 laps=58 gentle=0 deaths=0 fenix=0+0 wipes=0
seed48.log: DONE frame=182224 laps=58 gentle=0 deaths=0 fenix=0+0 wipes=0
== heal75
seed00.log: DONE frame=179127 laps=60 gentle=0 deaths=3 fenix=3+0 wipes=0
  [worldNavTo] [death] f+1407 entity 0 char 1 from 314/314 by slot 2 cmd $0C atk $9F (ONE ACTION from >= 80%) bp=0 party_bp=0,1,0,0
  [worldNavTo] [death] f+1583 entity 3 char 5 from 407/407 by slot 2 cmd $0C atk $9F (ONE ACTION from >= 80%) bp=0 party_bp=0,2,0,0
  [worldNavTo] [death] f+1793 entity 0 char 1 from 64/447 by nobody (no monster action attributed) bp=0 party_bp=0,0,0,0
seed24.log: DONE frame=195975 laps=61 gentle=0 deaths=7 fenix=8+0 wipes=0
  [worldNavTo] [death] f+2398 entity 1 char 6 from 92/310 by nobody (no monster action attributed) bp=0 party_bp=1,0,0,0
  [worldNavTo] [death] f+3028 entity 0 char 1 from 19/314 by nobody (no monster action attributed) bp=1 party_bp=1,1,1,1
  [worldNavTo] [death] f+1424 entity 0 char 1 from 295/314 by slot 2 cmd $0C atk $9F (ONE ACTION from >= 80%) bp=0 party_bp=0,0,2,0
  [worldNavTo] [death] f+1025 entity 3 char 5 from 403/407 by slot 2 cmd $0C atk $9F (ONE ACTION from >= 80%) bp=0 party_bp=0,2,2,0
  [worldNavTo] [death] f+1611 entity 2 char 4 from 158/398 by slot 2 cmd $0C atk $9F bp=0 party_bp=0,0,0,0
  [worldNavTo] [death] f+1025 entity 0 char 1 from 341/397 by slot 2 cmd $0C atk $9F (ONE ACTION from >= 80%) bp=0 party_bp=0,2,2,0
  [worldNavTo] [death] f+1025 entity 0 char 1 from 397/397 by slot 2 cmd $0C atk $9F (ONE ACTION from >= 80%) bp=0 party_bp=0,2,2,0
seed48.log: FAIL frame=None laps=None gentle=None deaths=6 fenix=4+0 wipes=1 [retry] attempt 1/1 FAILED class=wipe frame=33339 totalframes=33340 shift=48 phase=6 screenshot=/Users/mtklein/ot6/.claude/worktrees/agent-ac853ed10d5b24439/bui
  [worldNavTo] [death] f+1944 entity 2 char 4 from 146/354 by nobody (no monster action attributed) bp=2 party_bp=0,1,2,0
  [worldNavTo] [death] f+2697 entity 3 char 5 from 172/363 by slot 2 cmd $0C atk $9F bp=1 party_bp=1,2,3,1
  [worldNavTo] [death] f+1948 entity 2 char 4 from 161/354 by nobody (no monster action attributed) bp=2 party_bp=0,1,2,0
  [worldNavTo] [death] f+2704 entity 3 char 5 from 185/363 by slot 2 cmd $0C atk $9F bp=1 party_bp=1,2,3,1
  [worldNavTo] [death] f+1628 entity 3 char 5 from 378/407 by slot 2 cmd $0C atk $9F (ONE ACTION from >= 80%) bp=0 party_bp=0,2,0,0
  [worldNavTo] [death] f+2684 entity 0 char 1 from 59/353 by nobody (no monster action attributed) bp=1 party_bp=1,3,1,0
== care80
seed00.log: DONE frame=192995 laps=60 gentle=0 deaths=5 fenix=5+0 wipes=0
  [worldNavTo] [death] f+1584 entity 0 char 1 from 209/314 by slot 2 cmd $0C atk $9F bp=0 party_bp=0,0,0,0
  [worldNavTo] [death] f+1399 entity 3 char 5 from 396/407 by slot 2 cmd $0C atk $9F (ONE ACTION from >= 80%) bp=0 party_bp=0,2,0,0
  [worldNavTo] [death] f+1630 entity 0 char 1 from 397/397 by slot 2 cmd $0C atk $9F (ONE ACTION from >= 80%) bp=0 party_bp=0,2,0,0
  [worldNavTo] [death] f+1454 entity 2 char 4 from 248/502 by nobody (no monster action attributed) bp=2 party_bp=0,2,2,0
  [worldNavTo] [death] f+1681 entity 0 char 1 from 62/447 by nobody (no monster action attributed) bp=0 party_bp=0,1,2,2
seed24.log: DONE frame=207229 laps=60 gentle=0 deaths=10 fenix=8+2 wipes=0
  [worldNavTo] [death] f+2027 entity 1 char 6 from 57/310 by nobody (no monster action attributed) bp=1 party_bp=1,1,2,2
  [worldNavTo] [death] f+2259 entity 0 char 1 from 39/314 by nobody (no monster action attributed) bp=1 party_bp=1,1,3,2
  [worldNavTo] [death] f+1573 entity 1 char 6 from 271/349 by slot 2 cmd $0C atk $9F bp=0 party_bp=0,0,0,0
  [worldNavTo] [death] f+1607 entity 2 char 4 from 164/398 by slot 2 cmd $0C atk $9F bp=0 party_bp=0,0,0,0
  [worldNavTo] [death] f+1499 entity 0 char 1 from 397/397 by slot 2 cmd $0C atk $9F (ONE ACTION from >= 80%) bp=0 party_bp=0,2,2,0
  [worldNavTo] [death] f+1383 entity 0 char 1 from 224/397 by slot 2 cmd $0C atk $9F bp=0 party_bp=0,1,0,0
  [worldNavTo] [death] f+2087 entity 2 char 4 from 29/448 by nobody (no monster action attributed) bp=0 party_bp=0,0,0,0
  [worldNavTo] [death] f+3474 entity 3 char 5 from 246/457 by nobody (no monster action attributed) bp=2 party_bp=0,1,1,2
  [worldNavTo] [death] f+2535 entity 0 char 1 from 44/447 by slot 2 cmd $0C atk $9F bp=1 party_bp=1,2,1,1
  [worldNavTo] [death] f+2946 entity 1 char 6 from 195/497 by nobody (no monster action attributed) bp=2 party_bp=1,2,1,1
seed48.log: DONE frame=213266 laps=64 gentle=0 deaths=8 fenix=8+0 wipes=0
  [worldNavTo] [death] f+1321 entity 0 char 1 from 314/314 by slot 2 cmd $0C atk $9F (ONE ACTION from >= 80%) bp=0 party_bp=0,0,2,2
  [worldNavTo] [death] f+1390 entity 3 char 5 from 359/407 by slot 2 cmd $0C atk $9F (ONE ACTION from >= 80%) bp=0 party_bp=0,0,0,0
  [worldNavTo] [death] f+1784 entity 0 char 1 from 116/314 by nobody (no monster action attributed) bp=0 party_bp=0,0,0,0
  [worldNavTo] [death] f+1256 entity 0 char 1 from 361/397 by slot 2 cmd $0C atk $9F (ONE ACTION from >= 80%) bp=0 party_bp=0,0,2,2
  [worldNavTo] [death] f+1919 entity 0 char 1 from 51/447 by nobody (no monster action attributed) bp=1 party_bp=1,1,2,2
  [worldNavTo] [death] f+2535 entity 0 char 1 from 44/447 by slot 2 cmd $0C atk $9F bp=1 party_bp=1,2,1,1
  [worldNavTo] [death] f+2946 entity 1 char 6 from 191/497 by nobody (no monster action attributed) bp=2 party_bp=1,2,1,1
  [worldNavTo] [death] f+1793 entity 0 char 1 from 64/447 by nobody (no monster action attributed) bp=0 party_bp=0,0,0,0
== breakfirst
seed00.log: DONE frame=179663 laps=56 gentle=0 deaths=5 fenix=4+1 wipes=0
  [worldNavTo] [death] f+1834 entity 3 char 5 from 355/407 by slot 2 cmd $0C atk $9F (ONE ACTION from >= 80%) bp=1 party_bp=0,2,2,1
  [worldNavTo] [death] f+1291 entity 3 char 5 from 249/407 by slot 2 cmd $0C atk $9F bp=2 party_bp=0,0,2,2
  [worldNavTo] [death] f+1025 entity 2 char 4 from 398/398 by slot 2 cmd $0C atk $9F (ONE ACTION from >= 80%) bp=2 party_bp=0,2,2,0
  [worldNavTo] [death] f+1025 entity 3 char 5 from 274/407 by slot 2 cmd $0C atk $9F bp=0 party_bp=0,2,2,0
  [worldNavTo] [death] f+2659 entity 2 char 4 from 176/448 by slot 2 cmd $0C atk $9F bp=1 party_bp=1,3,1,1
seed24.log: DONE frame=187856 laps=58 gentle=0 deaths=7 fenix=7+1 wipes=0
  [worldNavTo] [death] f+2398 entity 1 char 6 from 92/310 by nobody (no monster action attributed) bp=0 party_bp=1,0,0,0
  [worldNavTo] [death] f+3028 entity 0 char 1 from 19/314 by nobody (no monster action attributed) bp=1 party_bp=1,1,1,1
  [worldNavTo] [death] f+1424 entity 0 char 1 from 295/314 by slot 2 cmd $0C atk $9F (ONE ACTION from >= 80%) bp=0 party_bp=0,0,2,0
  [worldNavTo] [death] f+1025 entity 3 char 5 from 403/407 by slot 2 cmd $0C atk $9F (ONE ACTION from >= 80%) bp=0 party_bp=0,2,2,0
  [worldNavTo] [death] f+1784 entity 3 char 5 from 241/457 by nobody (no monster action attributed) bp=0 party_bp=0,2,0,0
  [worldNavTo] [death] f+1442 entity 1 char 6 from 196/443 by nobody (no monster action attributed) bp=2 party_bp=0,2,2,0
  [worldNavTo] [death] f+1469 entity 2 char 4 from 328/502 by slot 2 cmd $0C atk $9F bp=2 party_bp=0,0,2,0
seed48.log: FAIL frame=None laps=None gentle=None deaths=6 fenix=4+0 wipes=1 [retry] attempt 1/1 FAILED class=wipe frame=33339 totalframes=33340 shift=48 phase=6 screenshot=/Users/mtklein/ot6/.claude/worktrees/agent-ac853ed10d5b24439/bui
  [worldNavTo] [death] f+1944 entity 2 char 4 from 146/354 by nobody (no monster action attributed) bp=2 party_bp=0,1,2,0
  [worldNavTo] [death] f+2697 entity 3 char 5 from 172/363 by slot 2 cmd $0C atk $9F bp=1 party_bp=1,2,3,1
  [worldNavTo] [death] f+1948 entity 2 char 4 from 161/354 by nobody (no monster action attributed) bp=2 party_bp=0,1,2,0
  [worldNavTo] [death] f+2704 entity 3 char 5 from 185/363 by slot 2 cmd $0C atk $9F bp=1 party_bp=1,2,3,1
  [worldNavTo] [death] f+1628 entity 3 char 5 from 378/407 by slot 2 cmd $0C atk $9F (ONE ACTION from >= 80%) bp=0 party_bp=0,2,0,0
  [worldNavTo] [death] f+2684 entity 0 char 1 from 59/353 by nobody (no monster action attributed) bp=1 party_bp=1,3,1,0
== boostfight
seed00.log: DONE frame=171784 laps=56 gentle=0 deaths=3 fenix=3+0 wipes=0
  [worldNavTo] [death] f+1815 entity 2 char 4 from 22/354 by nobody (no monster action attributed) bp=1 party_bp=0,0,1,0
  [worldNavTo] [death] f+1661 entity 2 char 4 from 398/398 by slot 2 cmd $0C atk $9F (ONE ACTION from >= 80%) bp=0 party_bp=0,2,0,1
  [worldNavTo] [death] f+2121 entity 1 char 6 from 239/393 by slot 0 cmd $0C atk $9F bp=0 party_bp=0,0,0,0
seed24.log: DONE frame=183695 laps=61 gentle=0 deaths=6 fenix=7+0 wipes=0
  [worldNavTo] [death] f+2398 entity 1 char 6 from 92/310 by nobody (no monster action attributed) bp=0 party_bp=1,0,0,0
  [worldNavTo] [death] f+3028 entity 0 char 1 from 19/314 by nobody (no monster action attributed) bp=1 party_bp=1,1,1,1
  [worldNavTo] [death] f+2139 entity 2 char 4 from 318/398 by slot 0 cmd $0C atk $9F bp=0 party_bp=0,0,0,0
  [worldNavTo] [death] f+2139 entity 3 char 5 from 301/407 by slot 0 cmd $0C atk $9F bp=0 party_bp=0,0,0,0
  [worldNavTo] [death] f+2542 entity 0 char 1 from 67/353 by nobody (no monster action attributed) bp=0 party_bp=0,0,0,1
  [worldNavTo] [death] f+1667 entity 0 char 1 from 397/397 by slot 2 cmd $0C atk $9F (ONE ACTION from >= 80%) bp=0 party_bp=0,2,1,0
seed48.log: DONE frame=168151 laps=58 gentle=0 deaths=4 fenix=4+0 wipes=0
  [worldNavTo] [death] f+1846 entity 3 char 5 from 204/407 by slot 2 cmd $0C atk $9F bp=0 party_bp=0,0,0,0
  [worldNavTo] [death] f+1517 entity 0 char 1 from 397/397 by slot 2 cmd $0C atk $9F (ONE ACTION from >= 80%) bp=0 party_bp=0,2,0,1
  [worldNavTo] [death] f+1912 entity 1 char 6 from 288/443 by nobody (no monster action attributed) bp=2 party_bp=0,2,0,1
  [worldNavTo] [death] f+2514 entity 3 char 5 from 127/457 by slot 2 cmd $0C atk $9F bp=0 party_bp=1,2,1,0
== allback
seed00.log: DONE frame=209342 laps=60 gentle=0 deaths=7 fenix=6+1 wipes=0
  [worldNavTo] [death] f+1469 entity 0 char 1 from 256/314 by slot 2 cmd $0C atk $9F (ONE ACTION from >= 80%) bp=0 party_bp=0,0,0,0
  [worldNavTo] [death] f+1470 entity 3 char 5 from 404/407 by slot 2 cmd $0C atk $9F (ONE ACTION from >= 80%) bp=2 party_bp=0,1,2,2
  [worldNavTo] [death] f+2388 entity 1 char 6 from 144/349 by slot 2 cmd $0C atk $9F bp=2 party_bp=1,2,3,2
  [worldNavTo] [death] f+2740 entity 0 char 1 from 308/397 by slot 0 cmd $0C atk $9F bp=2 party_bp=2,0,0,3
  [worldNavTo] [death] f+1429 entity 0 char 1 from 242/397 by slot 2 cmd $0C atk $9F bp=0 party_bp=0,0,0,0
  [worldNavTo] [death] f+1442 entity 1 char 6 from 195/443 by nobody (no monster action attributed) bp=2 party_bp=0,2,2,0
  [worldNavTo] [death] f+1469 entity 0 char 1 from 296/447 by slot 2 cmd $0C atk $9F bp=0 party_bp=0,0,0,0
seed24.log: DONE frame=200815 laps=55 gentle=0 deaths=7 fenix=6+1 wipes=0
  [worldNavTo] [death] f+1645 entity 2 char 4 from 14/354 by nobody (no monster action attributed) bp=0 party_bp=0,2,0,2
  [worldNavTo] [death] f+1025 entity 2 char 4 from 398/398 by slot 2 cmd $0C atk $9F (ONE ACTION from >= 80%) bp=2 party_bp=0,2,2,0
  [worldNavTo] [death] f+1025 entity 3 char 5 from 309/407 by slot 2 cmd $0C atk $9F bp=0 party_bp=0,2,2,0
  [worldNavTo] [death] f+2746 entity 2 char 4 from 240/398 by slot 0 cmd $0C atk $9F bp=0 party_bp=2,0,0,3
  [worldNavTo] [death] f+2746 entity 3 char 5 from 300/407 by slot 0 cmd $0C atk $9F bp=3 party_bp=2,0,0,3 -- died holding 3 BP
  [worldNavTo] [death] f+1442 entity 1 char 6 from 256/443 by nobody (no monster action attributed) bp=2 party_bp=0,2,2,0
  [worldNavTo] [death] f+2281 entity 2 char 4 from 316/448 by slot 0 cmd $0C atk $9F bp=0 party_bp=3,0,0,2
seed48.log: FAIL frame=None laps=None gentle=None deaths=5 fenix=1+1 wipes=1 [retry] attempt 1/1 FAILED class=wipe frame=93933 totalframes=93934 shift=48 phase=25 screenshot=/Users/mtklein/ot6/.claude/worktrees/agent-ac853ed10d5b24439/bu
  [worldNavTo] [death] f+1570 entity 1 char 6 from 308/349 by slot 2 cmd $0C atk $9F (ONE ACTION from >= 80%) bp=0 party_bp=0,0,0,0
  [worldNavTo] [death] f+1321 entity 0 char 1 from 293/397 by slot 2 cmd $0C atk $9F bp=0 party_bp=0,0,2,2
  [worldNavTo] [death] f+1025 entity 1 char 6 from 331/393 by slot 2 cmd $0C atk $9F (ONE ACTION from >= 80%) bp=2 party_bp=0,2,2,0
  [worldNavTo] [death] f+1434 entity 0 char 1 from 264/397 by nobody (no monster action attributed) bp=0 party_bp=0,2,2,0
  [worldNavTo] [death] f+2627 entity 3 char 5 from 110/457 by slot 2 cmd $0C atk $9F bp=1 party_bp=0,2,3,1
== gentle
seed00.log: DONE frame=194151 laps=28 gentle=62 deaths=2 fenix=2+0 wipes=0
  [worldNavTo] [death] f+1680 entity 0 char 1 from 28/447 by nobody (no monster action attributed) bp=0 party_bp=0,1,2,2
  [worldNavTo] [death] f+1409 entity 0 char 1 from 305/447 by slot 2 cmd $0C atk $9F bp=0 party_bp=0,1,0,0
seed24.log: DONE frame=192136 laps=26 gentle=62 deaths=0 fenix=0+0 wipes=0
seed48.log: DONE frame=191303 laps=26 gentle=62 deaths=0 fenix=0+0 wipes=0
```
