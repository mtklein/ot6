# The World of Ruin opening: the Solitary Island, Cid, and the first saves (`wor-island-v1`, `wor-start-v1`)

Authored 2026-09-22 for #253 (the first step of #250). Two segments, one per
save point the game offers:

| segment | boots | plays | ends at | checkpoint |
|---|---|---|---|---|
| `gen_wor_island` | `wor_landing` (solo CELES at Cid's bedside, map 397, `$00A4` set) | dress CELES, walk out, save | the island's World of Ruin tile (76,239) | `wor-island-v1` |
| `gen_wor_start` | `wor-island-v1` (cold Continue) | feed Cid until he recovers, his scene, the raft, the voyage, save | the landing, World of Ruin (146,212) | `wor-start-v1` |

Every number below is quoted from a log under `build/attempts/wt/wor-start/`
(`lab/` the probes, `fish/` the fishing lab, `retry/` the runner's retry
runs and mutants, `single-segment/` the superseded first cut, `probes/` the
one-off scripts the probe logs came from). Nothing here was measured by
writing game state.

## The island

| map | what it is | ways out |
|---|---|---|
| 397 | Cid's house: the bed Cid (npc 1, obj `$10`, (100,38)), the stair cover (npc 3, obj `$12`, (94,39)), the raft (npc 4, obj `$13`, (85,51)) | (100,46) -> 396 (8,7) |
| 396 | the island outside the house | door (8,6) -> 397 (100,45); row 14, x 4-14 -> 398 (4,2); the west, north and east edges -> the World of Ruin map |
| 398 | the fishing beach: the bird (obj `$10`) and four fish (objs `$11`-`$14`) | row 1, x 0-6 -> 396 (8,12) |
| 1 (world) | the island's own tile, (76,239) on arrival | (76,240) -> 396 (8,12) |

(`ff6/src/field/trigger/short_entrance.dat`, `long_entrance.dat`, decoded
through `include/field/*_entrance.inc`; `ff6/src/event/npc_prop.asm:17552`
and `:17615`.) No random battles on 396-400 (`map_prop.dat` +5 bit 7 clear
for all five), and no chests (`tools/audit_chests.py`'s table has none on
396-400). Celes meets no battle in either segment.

**Celes arrives bare.** At the landing every one of her six slots reads
`$FF`; her escape kit (Break Blade, Star Pendant, Jewel Ring) is in the bag
(`lab/probe_wor_kit.log`: `CELES equip FF FF FF FF FF FF`;
`python3 tools/audit_readiness.py build/states/wor_landing.mss`: `CELES
row=BACK def=0 mdef=0 NOTHING AT ALL`). She is L25, 1043/1043 HP, 227 MP,
and the bag holds `tonic=4 potion=39 fenix=22` (`wor_island_ninja.log`:
`[wor] boot f5: map 397 (99,38), party 1, CELES L25 HP 1043/1043 MP 227,
Cid health 120, timer 0 flags $80 at $533F, fish 1101, tonic=4 potion=39
fenix=22`). `gen_wor_island` dresses her first: Genji Glove and Czarina
Ring on the Relic screen, after which the game's own Optimum fills the gear
(`[CELES relics] char=6 after=11 0E 76 8F D1 C1`: Break Blade, Blizzard,
Gold Helmet, Gold Armor).

**Her row is left for the next leg.** She stands in the BACK row
(`audit_readiness`: `CELES row=BACK`), which halves the damage her Fight
does and the physical damage she takes. Neither segment has a fight to
measure the choice on; the first World of Ruin random battle is where it
belongs (`H.setRows`, the field menu's Row).

## Cid's health

Event variable 7 (`$1FD0`), set to 120 as the opening hands over control
(`event_main.asm:12425`), with `start_timer 0, 64, _ca533f, FIELD_ONLY`
(`:12448`); `_ca533f` (`:12450`) subtracts 1 and restarts the timer.

- **The clock.** `DecTimers` runs every field frame (`field/reset.asm:98`)
  and `CheckTimer` fires the event only with no event running and the party
  tile-aligned (`field/event.asm:5680`). Standing still it is one per 64
  frames (`lab/probe_wor_island_3.log`: `[isle boot] f33 ... var7=119 ...
  ctr=38` then `[isle boot+200] f233 ... var7=116 ... ctr=33`); walking and
  map changes stretch it to about one per 83 frames (a 909-frame trip with
  no fishing costs 11: `lab/gen_wor_start_2.log`, `[cid] trip 4 done: 910
  frames, caught {}, health 184 -> 173`).
- **Where it stops.** FIELD_ONLY sets `$1188` bit 7, which
  `DecTimersMenuBattle` (`field/event.asm:5562`) skips, so menus and
  battles cost nothing (dressing her, two menu sessions and the field
  frames between them: `Cid health 120 before the menus, 118 after`); the
  world map does not run the field timer at all
  (`lab/probe_wor_islesave_1.log`: `[isle world] f451 ... health=114 timer0
  80/16`, 600 frames later `[isle world +600] f1051 ... health=114 timer0
  80/16`). The save keeps the timer (`menu/save.asm` PushTimers, `$1FA8`):
  a cold Continue of `wor-island-v1` reads `Cid health 112, timer 0 $80/48`.
- **Feeding.** Talking to him (`_ca5370`, `:12477`) first rerolls the fish
  (`_ca534a`, `:12454`), then eats everything Celes holds: `$01D2` +32,
  `$01D3` +16, `$01D4` -4, `$01D5` -16 (`:12488-12506`), then compares:
  above 256 he recovers (`_ca5713`, `:13022`: "I feel much better!", the
  timer stops, the stair cover goes, `$00B3` set); otherwise one of eight
  health lines ($0881-$0888, thresholds 230/200/160/120/90/60/30).
- **Lost.** Entering 397 with 30 or less sets `$00B4` (the map's init,
  `_caf42d`/`_caf461`, `:35997`/`:36018`); talking to him then plays his
  death, the cliff and the letter.
- **The talk.** From (99,38), facing right. From (100,39), below the bed,
  A never engaged him (`lab/probe_wor_fish_2.log`: `FAIL: timeout after
  1020 frames driving toward Cid: activation round 2`). After every entry
  into 397 his bed animation must finish before a talk does anything: the
  init's object script sets the per-map flag `$01F0` about 60 frames in
  (`[fish cid] n=48 obj10 (99,38) ... 01F0=0` then `[fish cid] n=60 obj10
  (100,38) ... 01F0=1`; `$1EBE` bit 0, cleared by every new map load,
  `field/init.asm:470`), and `_ca5370` returns at once while it is clear.
  By the time Celes has walked from the door to the bedside it is set.

## The fish

Every talk rerolls four spawn switches, 50% each (`if_rand`,
`field/event.asm:4026`: branch when `Rand >= $80`), from four consecutive
entries of the field RNG table (`Rand`, `field/reset.asm:888`, index
`$1F6D`):

| obj | npc | spawn tile | swim speed (`$0875`) | spawn switch | catch sets | eaten |
|---|---|---|---|---|---|---|
| `$11` | 2 | (12,11) | NORMAL (2) | `$0369` | `$01D2` | **+32** |
| `$12` | 3 | (10,13) | SLOW (1) | `$036A` | `$01D3` | +16 |
| `$13` | 4 | (13,13) | SLOW (1) | `$036B` | `$01D4` | -4 |
| `$14` | 5 | (14,11) | SLOWER (0) | `$036C` | `$01D5` | -16 |

(`npc_prop.asm:17615-17660`, `event_main.asm:13088-13107`.) The landing's
own roll is `1101`: the fast fish, the +16 and the -16. A caught fish is
deleted and stays gone until the next reroll, so one reroll is one chance
at each fish, and a fish that is not swimming cannot be waited for: only a
talk brings one. The two SLOW fish look and swim alike; a player cannot
tell the +16 from the -4.

**Catching** is an ordinary NPC talk: `CheckNPCs` (`field/player.asm:142`)
activates whatever the object map (`$7E2000`) holds on the tile Celes
faces while A is down. The shore is a staircase: land-edge tiles (exit byte
`$0F`, no random-move bit) and, beside them, water-edge tiles (`$8A`: Celes
can step on, but leave only up or left); the fish move only onto tiles with
the random-move bit (`NPCMoveRand`, `field/obj.asm:5155`), so they swim the
water-edge tile and everything deeper (`lab/probe_wor_fishmove_1.log`,
`[tiles] y=10 x6..16: 02/8F 02/8F 02/8F 02/8F 02/0F 02/8A 02/8F ...`).
In 9000 frames the fast fish changed tile 447 times, a slow one 270, the
slowest 126 (`[move] obj 11 speed 2: 447 tile changes in 9000 frames`,
`[move] obj 12 speed 1: 270 ...`, `[move] obj 14 speed 0: 126 ...`). From
the beach entry (4,2) the shore is 14 steps (224 frames of walking), and a
chase catches the fast fish soon after Celes gets there
(`single-segment/catch_times.txt`: `fast-fish catch frames after arrival:
n=287 mean=411.8 p10=237 median=333 p90=685 max=701`): the walk, not the
chase, is where Cid's health goes. Every leg is already the shortest walk:
each is a BFS path over the engine's own passability (`H.navTo`), and the
island's exits are fixed (the beach is entered only at (4,2), the house
only at (100,45)).

## The island save (`wor-island-v1`)

Off 396's west edge Celes stands on the island's own World of Ruin tile
(76,239). The world map allows saving and Cid's clock stands still there
(above), so a person who knows he can be lost saves here before fishing:
**this is the first save the World of Ruin offers**, before the raft.
`gen_wor_island` saves there through the real Save UI (`wor_island_ninja.log`:
`[saved] wor-island-v1: slot 3 holds map 1 ($3001) world tile (76,239), Cid
health 112`, `contract wor-island-v1 (exit): all 12 fields hold`). Its
contract (`lib/ot6_contract.lua`) is world map 1 at (76,239), `$00A4` set,
`$00B3`/`$00B4` clear, CELES alone, and Cid's clock armed (`$1188` = `$80`);
`gen_wor_start` asserts it after its cold Continue (`contract wor-island-v1
(entry): all 12 fields hold`).

## What varies the draw

A retry (and a lab sample) must meet a different draw: the fish each talk
rerolls. The rerolls read the field RNG index `$1F6D` (the cold Continue
seeds it from the battery, `EventCmd_ab`: `rand $FB` at the island save's
Continue), and what walks it on the island is the fish and the bird on the
beach, about one step per 7 frames while Celes stands there
(`lab/probe_wor_rand.log`: `world f5 $1F6D=$9A`, `396 f70 $1F6D=$9A`, `398
arrive f180 $1F6D=$9E`, 600 frames later `$1F6D=$11 (88 distinct values so
far)`). Measured with the runner's
own seed shift (idle frames at the boot point), retries off:

| boot point | shifts | first draws | the rest of the run |
|---|---|---|---|
| the cold Continue, world map (`contboot`) | 0, 15, 30, 45 | all `roll 1010 rand $BC health 139` | differs: Cid recovered on trips 37, 42, 37, 54 (`fish-firstlook/fishlab_drawcheck.txt`) |
| the first look at the beach | 0, 15, 30, 45 | all `roll 1010 rand $BC health 139` | the same: trips 37, 37, 37, 37 (the same file): the first catch waits on the fish, whose swim runs from the map load |
| the beach after the first visit's catches | 0, 15, 30, 45 | `rand $BC`, `$BE`, `$C1`, `$C3` | differs: trips 37, 22, lost on 20, 39 (`fish-retryshifts/fishlab_drawcheck2.txt`) |

So `gen_wor_start` asserts the entry contract without the boot mark and
marks its boot point on the beach after the first visit's catches, a beat
before the walk back. That lands at f2314 under the shipped policy, inside
the runner's own 2400-frame fallback, but a first visit that runs longer
(the lab's `wait`) would be pre-empted by the fallback mid-visit and every
shift would play one draw (it was: `fish-wait-fallback/`), so the generator
passes `H.run({ ..., bootFallback = false })`.

A first draw (the spawn roll, the RNG index and Cid's health after the
first feed) does not fix the run: the same one can go on differently (the
lab's `near` shifts 483 and 490 both drew `roll 1100 rand $EC health 132`;
483 recovered Cid on trip 35, 490 lost him on trip 20), and under `all` and
under `near` alike 15 of the 114 pairs of lab shifts 21 frames apart share a
first draw
(`build/attempts/review/wor-start/same_first_draw_21_apart.txt`). So each
attempt logs its first draw beside any earlier failed attempt's, and does
not gate on it: the runner's shifted attempts are the variation.

## The lab

`tools/tests/fishlab.py` derives `gen_wor_start.lua` once per policy (its
`POLICY` line) and plays it from `wor-island-v1` once per seed shift,
retries off, keeping every run. Policies (visible cues only: a fish's swim
speed; never the slowest fish):

- **near**: the fast fish if it swims, plus a slow fish that swims up beside
  her on the way, plus a slow one still within 240 frames once the fast one
  is caught; no fast fish: straight back to Cid (the talk is the reroll).
- **fast**: the fast fish only.
- **fastslow**: the fast fish, then every slow fish, however long it takes.
- **all**: every fish but the slowest, whether or not the fast one swims.
- **wait**: near, but stand on the land-edge tile beside the fast fish's two
  likeliest shore tiles, (8,12) (`lab/probe_wor_fishmove_1.log`: the fast
  fish sat on (9,12) 113 and (8,13) 92 of 2250 samples), and let the fish
  come.
- **allnear** (added mid-lab): near while the fast fish swims, every slow
  fish when it does not. Cut after 7 attempts: its runs were the lab's
  longest (82 trips, 149k frames) and it was already behind.

Each batch derived its variants from the generator as it then stood, so
besides the POLICY line they differ from the shipped one in comments, in how
the first draw is recorded (an assertion against earlier failed attempts
then, a log line now; with retries off there is no earlier attempt, so it
never fired), and in frame budgets: 400,000 or 600,000 frames an attempt
(380,000 or 560,000 for the feeding) against the shipped 200,000 and
180,000 (`fish/gen_wor_start_*.lua`, the last search batch's;
`fish/heldout-variants/`, the held-out runs'). No lab run ran out of frames
(`other=0` on every aggregate line). No `near` run came near the shipped
budget; some `all` runs would not have fit it (below).

**The search set.** Shifts 0-273 and 3-276 in steps of 7, and for the two
leaders 280-553 too. A first draw (the spawn roll, the RNG index and Cid's
health after the first feed) is counted once however many shifts drew it,
and one that went both ways is `mixed` (`fish/fishlab_aggregate.txt`, from
`python3 tools/tests/fishlab.py aggregate --root
build/attempts/wt/wor-start/fish`):

| policy | attempts | recovered | distinct first draws | recovered | lost | mixed |
|---|---|---|---|---|---|---|
| all | 120 | 119 | 48 | 47 | 1 | 0 |
| near | 120 | 113 | 48 | 44 | 3 | 1 |
| fastslow | 80 | 60 | 34 | 27 | 5 | 2 |
| fast | 40 | 8 | 27 | 5 | 22 | 0 |
| wait | 40 | 0 | 15 | 0 | 15 | 0 |
| allnear (cut) | 7 | 5 | 5 | 3 | 2 | 0 |

Raw: `all distinct samples=48 recovered=47 lost=1 mixed=0 rate=0.979`;
`near distinct samples=48 recovered=44 lost=3 mixed=1 rate=0.917`;
`fastslow distinct samples=34 recovered=27 lost=5 mixed=2 rate=0.794`;
`fast distinct samples=27 recovered=5 lost=22 mixed=0 rate=0.185`; `wait
distinct samples=15 recovered=0 lost=15 mixed=0 rate=0.000`. These are
search-set rates: the policy was picked on these draws.

**Held-out draws** (docs/TESTING.md: test the discovered strategy
separately from its search). Shifts 560-1113 in steps of 7 and 1120-1666 in
steps of 14, retries off, scored only on the first draws none of the
search's 90 ever drew (`python3 tools/tests/fishlab.py run --shifts
560-1113:7 --dir all-heldout all`, then `--shifts 1120-1666:14`, the same
for `near` and `fastslow`; `python3 tools/tests/fishlab.py heldout --root
build/attempts/wt/wor-start/fish all-heldout all near fastslow fast wait
allnear`, `fish/heldout_all.txt`, `fish/heldout_near.txt`,
`fish/heldout_fastslow.txt`). The later shifts
idle longer before the reroll the shift moves, so Cid's health after the
first feed runs from 130 down to 113, against 139 down to 131 in the
search: a harder start.

| policy | search set: distinct draws recovered | held-out attempts | recovered | held-out distinct draws | recovered | lost | mixed |
|---|---|---|---|---|---|---|---|
| all | 47 of 48 (0.979) | 120 | 117 | 67 | 65 (0.970) | 2 | 0 |
| **near** | 44 of 48 (0.917) | 120 | 117 | 67 | **64 (0.955)** | 3 | 0 |
| fastslow | 27 of 34 (0.794) | 41 (stopped) | 18 | 25 | 10 (0.400) | 14 | 1 |

Raw: `all-heldout held-out distinct samples=67 recovered=65 lost=2 mixed=0
rate=0.970`; `near-heldout held-out distinct samples=67 recovered=64 lost=3
mixed=0 rate=0.955`; `fastslow-heldout held-out distinct samples=25
recovered=10 lost=14 mixed=1 rate=0.400` (stopped at 40 runs,
`fish/fishlab_heldout_fastslow.txt`: it was losing more than half). Over
the same runs (`fish/fishlab_aggregate_heldout.txt`): `all-heldout
attempts=120 recovered=117 ... trips median=42 max=181 cid-frames
median=65336 max=356481`, `near-heldout attempts=120 recovered=117 ...
trips median=32 max=62 cid-frames median=46606 max=82915`. `all`'s long
chases are its tail: 11 of its held-out recoveries came past f180,000
(`fish/all-heldout/shift1064.ot6.log`: `Cid recovered on trip 181 at
f356481`) and 4 of its search ones (up to f216,277), at or past the
shipped budgets; `near`'s slowest in either set was f82,915.

**Paired**, shift by shift (the same shift is the same boot). In the
search, near lost on shifts 28/31/35 (`rand $C1`), 262 and 490/497/504, and
all recovered on every one of them; all lost once, at shift 476 (`LOST: Cid
died -- health 20 as Celes walked into the house on trip 7; first draw
[roll 0011 rand $EA health 132]`: trips 2 to 4 met no fast fish and the -4
fish as the only slow one, and caught it each time, `health 132 -> 111`,
`111 -> 77`, `77 -> 51`; `fish/all/shift476.ot6.log`), where near
recovered. Held out, all lost
shifts 1260, 1302 and 1316 and near recovered them (`OK/42`, `OK/35`,
`OK/35` trips); near lost 1190, 1400 and 1610 and all recovered them
(`OK/103`, `OK/77`, `OK/66`). No draw was lost under both.

**What the numbers are made of.** The bot's timing is fixed, so each
trip's length fixes how far the fish walk the field RNG before the next
talk, and a run walks the RNG table along a path that can return on itself
(`fish/allnear/shift00.ot6.log`: trips 11, 18 and 24 draw and catch the
same fish). Which fish a policy meets is therefore a property of its path
as much as of the coins. Over independent draws every fish swims half the
time and a lone slow fish is the +16 one half the time; the lab's trips
(`fish/fishcomp_search.txt`, `fish/fishcomp_heldout.txt`):

| policy | draws | trips | the fast fish swam | a lone slow fish was the +16 one (the fast fish swam) | (it did not) |
|---|---|---|---|---|---|
| all | search | 5,684 | 0.465 | 0.711 | 0.686 |
| all | held out | 6,146 | 0.482 | 0.659 | 0.658 |
| near | search | 4,052 | 0.534 | 0.559 | 0.474 |
| near | held out | 3,870 | 0.551 | 0.585 | 0.502 |
| fastslow | search | 2,943 | 0.490 | 0.560 | 0.578 |
| fastslow | held out | 1,693 | 0.425 | 0.573 | 0.562 |

`all`'s trip lengths lead it to the +16 fish about two times in three on
both sets; `near`'s are close to fair.

**Per trip** (`fish/fishtrips.txt`, the search runs: Cid's health change
by what swam, the fast fish and how many of the two slow ones, over every
trip but the recovering one; the slowest fish is never chased):

| what swam | all | near | fastslow | fast | wait |
|---|---|---|---|---|---|
| no fast fish, no slow | -11.00 | -11.00 | -11.00 | -11.00 | -11.00 |
| no fast fish, one slow | -11.11 | -11.00 | -11.00 | -11.00 | -10.99 |
| no fast fish, both slow | -8.61 (49 trips) | -10.99 | -11.00 | -11.00 | -11.00 |
| the fast fish alone | +14.91 | +14.40 | +14.28 | +13.87 | -7.25 |
| the fast fish and one slow | **+21.00** | +18.68 | +16.83 | +12.24 | +2.11 |
| the fast fish and both slow | **+19.12** | +12.49 | +17.12 | +13.41 | -23.62 |

Held out (`fish/fishtrips_heldout.txt`) the shape is the same: `all`
+18.43 and +18.73 with the fast fish and one or both slow, `near` +18.06
and +12.69; with no fast fish and one slow, `all` -12.02, `near` -11.00.

So `all`'s lead over `near` on the search set is in the fast-plus-slow
trips. By exact fish set (`fish/fishsets_search.txt`, trip 1 left out: its
cost holds the lab's idle; the digits are the fast fish, the +16, the -4
and the slowest, 1 where it swam) part of that is the policy and part the
path:

| set | all | near | fastslow |
|---|---|---|---|
| `1100` fast and +16 | +27.14 | +28.46 | +28.86 |
| `1010` fast and -4 | +7.62 | +8.78 | +7.47 |
| `1110` fast and both slow | **+19.77** | +14.20 | +20.21 |
| `1111` all four | **+17.21** | +10.03 | +15.19 |
| `0100` the +16 alone | -1.44 | -11.00 | -11.00 |
| `0010` the -4 alone | -30.34 | -11.00 | -10.99 |

With both slow fish swimming, `all` and `fastslow` catch both and `near`
only one that comes close: that is the policy, 5 to 7 health a trip. With
one slow fish, `near` does as well set for set, and `all`'s +21.00 against
+18.68 is its path meeting the +16 fish 71% of the time against 56%.
Without the fast fish `all` breaks even with `near` (-11.11 against -11.00)
only because of that path: the -4 fish swims from the far corner (13,13),
so a trip that chases it alone costs 30 health against 11 for walking
straight back, and at even odds a lone slow fish costs `all` about 16 a
trip. The one draw `all` lost in the search is three such trips running
(shift 476 above).

**Fair coins.** Resampling each policy's own trips per exact fish set
under independent draws -- trip 1 the island save's `1101`, every later set
four fair coins, Cid lost at 30 or less before a feed, saved past 256 --
models what the policy is worth to a person, whose timing does not repeat
(`fish/fishmodel.py`, 200,000 modelled runs each). From the search trips
(`fish/fishmodel_search.txt`): `all P(recovered)=0.788`, `near
P(recovered)=0.890`, `fastslow P(recovered)=0.917`, `fast
P(recovered)=0.772`, `wait P(recovered)=0.000`. From the held-out trips
(`fish/fishmodel_heldout.txt`): `all-heldout P(recovered)=0.738`,
`near-heldout P(recovered)=0.850`, `fastslow-heldout P(recovered)=0.895`.
It is a model, built from the bot's own trips; the lab is what this
generator scores.

**Waiting at a spot is ruinous.** Over the `wait` runs the fast fish swam
beside (8,12) a median 1,589 frames after Celes reached the beach
(`fish/catch_times.txt`: `wait (stand at (8,12)): n=94 min=237
median=1589 p90=1765 max=2181`, against `all + near (chase): n=4808
min=229 median=277 p90=621 max=1133`). A fish that is not swimming cannot
be waited for at all: only a talk brings one. The first 40 `wait` runs are
kept in `fish-wait-fallback/`: their boot point fell to the runner's
2400-frame fallback mid-visit, so all 40 were one draw (0 recovered); the
re-run above has the boot point on the beach.

**So the generator ships `near`**: the fast fish when it swims and a slow
one that comes near; no fast fish, straight back to Cid for the next
reroll. On this generator's draws it is about as good as `all` (44 of 48
searched and 64 of 67 held out, against 47 of 48 and 65 of 67), its slowest
recovery is under a quarter of `all`'s (f82,915 against f356,481), and it
keeps most of its rate under fair coins (0.85-0.89 against `all`'s
0.74-0.79). A change to the bot's timing (a lib navigation edit, a
different island save) moves the RNG path each policy walks, and with it
each policy toward its fair-coin rate: `all` further than `near`.
`fastslow`, the best under fair coins, loses on this bot's own paths (27 of
34 searched, 10 of 25 held out): the same lesson from the other side. A
lost first attempt is a retry (below).

## The retry

A lost Cid is a lost attempt. The body raises `LOST: Cid died -- ...`; the
segment runner files it as class `lost` (`lib/ot6.lua` `classify`, one of
the seed-dependent classes with the wipe) and replays the body from the
boot snapshot at the next seed shift, bounded by its default 3 attempts,
each a `[retry] attempt n/N FAILED class=lost ...` line that
`tools/audit_retries.py` lists. Measured with the final generator: each
variant in `retry/final/` is `tools/tests/gen_wor_start.lua` with the one
line its name says changed (two for `nofish_contboot`); `diff` shows
nothing else, frame budgets included:

- `retry/final/fastslow14.log` (POLICY `fastslow`, which this generator's
  paths lose often, at `OT6_SEED_SHIFT=14`): `[retry] attempt 1/3 FAILED
  class=lost ... LOST: Cid died -- health 24 as Celes walked into the house
  on trip 41; first draw [roll 1011 rand $BE health 139]`, attempt 2 at
  shift 34 draws `roll 1111 rand $C1 health 139` and is lost on trip 66,
  attempt 3 at shift 54 draws `roll 1101 rand $C4 health 138`, `Cid
  recovered on trip 17`, `PASS (frame 34031) attempts=3/3`.
- `retry/final/nofish.log` (SPEED constants 9: no fish is ever wanted):
  three attempts, three first draws (`rand $09`, `$10`, `$13`), each
  `class=lost` on trip 9, then `[retry] attempts=3/3 exhausted; failed
  attempts: 1:lost 2:lost 3:lost`.
- `retry/final/nofish_contboot.log` (the same mutant with the boot point
  back on the world map, where the shift does not move the first draw):
  attempts 2 and 3 draw attempt 1's first draw and say so, `[cid] first
  draw: roll 1001 rand $09 health 105 (the same first draw as failed
  attempt 1, 2; the continuation can still differ)`, and play on: the log
  line is a record, not a gate.
- `retry/final/audit_retries.txt`: `lost x8 gen_wor_start_fastslow,
  gen_wor_start_nofish, gen_wor_start_nofish_contboot`.
- Superseded, kept for the record: `retry/final-fb9c5721/` (the same
  three variants of the generator before a comment edit, with the same
  verdict lines), `retry/superseded-assert/` (the
  generator when the first-draw check was an assertion, with a 400,000 and
  380,000-frame budget and POLICY `all`: its `nofish_contboot` stopped with
  `class=assert`) and `retry/pre-final/` (earlier still: POLICY `near`,
  4 attempts, `PASS (frame 41886) attempts=2/4` on the `rand $C1` draw).

The runner's own suites still hold with the new class and option, on
the merged tree (`tools/tests/run.sh tools/tests/<suite>.lua`,
`runner_suites_final.txt`): `segment_retry: [ot6] PASS (frame 181)
attempts=2/3`, `seed_reroll: [ot6] PASS (frame 313) attempts=2/3`,
`wipe_reclass: [ot6] PASS (frame 1) attempts=2/2`, `step_reset: [ot6] PASS
(frame 376) attempts=1/1`, `watchdog_cantrun` and `watchdog_listend`
`PASS (frame 1) attempts=2/2`; `ninja build/checks/retry_negative.ok`:
`retry-negative: PASS -- attempt 1/3 failed class=assert, no attempt 2/3,
verdict names the class`.

## The raft and the landing

His recovery scene hides the stair cover (obj `$12` at (94,39)), which
opens the way down to the raft (397 (85,51)); `H.navTo` finds it once the
cover is gone. Talking to it plays his farewell (dlg `$0891`) and the
voyage: maps 397 -> 400 -> 1 -> 3 -> 1, control on the World of Ruin map at
(146,212), outside Albrook (`wor_start_ninja.log`: `[wor] the voyage: map
397 at f52787`, `dialog $0891`, `map 400 at f53584`, `map 1 at f54774`,
`map 3 at f56745`, `map 1 at f56905`, `[wor] landed: world 1 at (146,212)
f57007, CELES HP 1043/1043`), about 4,200 frames from the raft talk. No
choice prompt anywhere on the island or the raft.

## The checkpoints

Both are slot-3 saves through the real Save UI, captured from the
generator's own run (`OT6_CAPTURE_SRM`), sealed and validated; each manifest
declares its save (`"saved": {"slot": 3, "world": {"map": 1, ...}}`;
`lib/sram_checkpoint.py` now reads map 1 as the World of Ruin world map) and
each has a contract in `lib/ot6_contract.lua`, asserted by the generator
after its save and by the next segment's cold Continue.

## The runs behind it

- **`gen_wor_island`**: `nice ninja build/states/wor_island.mss.lua`
  (`ninja_wor_island.txt`, `wor_island_ninja.log`): `[saved] wor-island-v1:
  slot 3 holds map 1 ($3001) world tile (76,239), Cid health 112`,
  `contract wor-island-v1 (exit): all 12 fields hold`, `PASS (frame 1625)
  attempts=1/3`. Its capture (`capture_wor_island.log`, `OT6_CAPTURE_SRM`,
  artifacts outside `build/states`) is the same run, its `wor_island.mss`
  byte-identical; sealed and validated (`validate_wor_island_v1.txt`):
  `holds=slot 3 world 1 (76,239) [$1F64=$3001] (saved: declared and
  checked)`. No draw varies it: nothing on its path reads the field RNG.
- **`gen_wor_start`**: `nice ninja build/states/wor_start.mss.lua`
  (`ninja_wor_start.txt`, `wor_start_ninja.log`): `contract wor-island-v1
  (entry): all 12 fields hold`, `[retry] boot point: the fishing beach 398
  after trip 1's catches (health 100, rand $95) at f2314`, `[cid] first
  draw: roll 1010 rand $BC health 139`, `Cid recovered on trip 37 at
  f51931, health 271`, `[saved] wor-start-v1: slot 3 holds map 1 ($0401)
  world tile (146,212)`, `contract wor-start-v1 (exit): all 11 fields
  hold`, `PASS (frame 57321) attempts=1/3`. The capture
  (`capture_wor_start.log`) is the same run, `wor_start.mss` byte-identical;
  `validate_wor_start_v1.txt`: `holds=slot 3 world 1 (146,212)
  [$1F64=$0401] (saved: declared and checked)`.
- **Other draws**: the lab above is this policy over 240 shifts (120
  searched, 120 held out), retries off, in variants that differ from the
  generator only in comments, the first-draw record and budgets (above).
  The graph's own sweep (`python3 tools/tests/seed_sweep.py wor_start
  --seeds 4 --jobs 4 --out build/sweeps/wor_start-final5`, retries off,
  `sweeps/wor_start-final5/`): `3/4 seeds passed; 4 distinct first
  battle(s) across 4 seeds; 3/4 distinct samples passed`. First draws
  `rand $BC`, `$BE`, `$C1`, `$C3`; Cid recovered on trips 37, 22 and 39,
  and shift 30 lost him (`LOST: Cid died -- health 13 as Celes walked into
  the house on trip 20; first draw [roll 1111 rand $C1 health 139]`), the
  `rand $C1` draw `near` also lost at search shifts 28/31/35; in the graph
  that is a retry at the next shift. The island has no battles, so the
  sweep's distinct count is its seeds' (a seed with no first battle counts
  as its own sample); the first-draw lines are what differ here.
- **The cold Continue** of the sealed `wor-start-v1` on this ROM
  (`OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/wor-start-v1
  tools/tests/run.sh tools/tests/probe_wor_start_continue.lua`,
  `continue_wor_start_v1.log`): `contract wor-start-v1 (entry): all 11
  fields hold`, `[continue] world 1 at (146,212): CELES L25 HP 1043/1043
  MP 227 kit 11 0E 76 8F D1 C1; Cid recovered $00B3=1; tonic=4 potion=39
  fenix=22 gil=215563`, `PASS (frame 1386)`.
- **The graph** (after the merge of main): `nice ninja
  build/checks/checkpoint_saves.ok build/checks/checkpoint_negatives.ok
  build/checks/retry_negative.ok build/checks/state_writes.ok
  build/checks/playthrough_honest.ok build/checks/test_registration.ok ...`
  (`ninja_checks_final.txt`): `checkpoint-saves: PASS -- 29 checkpoints
  validate; each line names the save its battery holds`, among them
  `wor-island-v1: ... holds=slot 3 world 1 (76,239) [$1F64=$3001] (saved:
  declared and checked)` and `wor-start-v1: ... sha256=990aa6e6... holds=slot
  3 world 1 (146,212) [$1F64=$0401] (saved: declared and checked)`;
  `checkpoint-negatives: PASS`, `retry-negative: PASS`, `OK -- every state
  write is a declared unit-test expedient`. `python3
  tools/tests/lib/compose.py --check-states` (`check_states_final.txt`):
  `fixtures: 52 of 96 do not verify (52 STALE)`, every one a `gen_kolts` or
  `gen_sabin_gau` fixture or a descendant, the two generators that merge
  brought in (`check_states_stale_list.txt`: `fixture vargas_entry is STALE
  -- its generator gen_kolts changed`, `fixture gau_joined is STALE -- its
  generator gen_sabin_gau changed`, 48 more through their chains); none is
  on this route, and `ninja -n build/states/wor_landing.mss.lua
  build/states/wor_island.mss.lua build/states/wor_start.mss.lua`: `ninja:
  no work to do`. Before the merge: `fixtures: 96/96 fresh`
  (`check_states.txt`).

**For the next leg:** Tonics are far below the band (4 against about
L25 x 5, capped 99); Albrook, the town beside the landing, is the first
shop. CELES wears Break Blade / Blizzard on the Genji Glove, Gold Helmet,
Gold Armor and the Czarina Ring, and stands in the back row (above).
