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

| boot point | shifts | first draws |
|---|---|---|
| the cold Continue, world map (`contboot`) | 0, 15, 30, 45 | all `roll 1010 rand $BC health 139` (`fish-firstlook/fishlab_drawcheck.txt`) |
| the first look at the beach | 0, 15, 30, 45 | all `roll 1010 rand $BC health 139`: the idle is absorbed, since the first catch waits on the fish, whose swim runs from the map load |
| the beach after the first visit's catches | 0, 15, 30, 45 | `rand $BC`, `$BE`, `$C1`, `$C3` (`fish-retryshifts/fishlab_drawcheck2.txt`) |

So `gen_wor_start` asserts the entry contract without the boot mark and
marks its boot point on the beach after the first visit's catches, a beat
before the walk back (`H.run({ ..., bootFallback = false })` keeps the
runner from marking one for it at frame 2400). Each attempt records its
first draw (the spawn roll, the RNG index and Cid's health after the first
feed) and asserts it differs from every earlier failed attempt's.

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

Shifts 0-273 and 3-276 in steps of 7, and for the two leaders 280-553
too. Two shifts that draw the same first draw (spawn roll, RNG index and
health after the first feed) play the same continuation, so the rate that
counts is over distinct first draws (`fish/fishlab_aggregate.txt`, from
`python3 tools/tests/fishlab.py aggregate`):

| policy | attempts | recovered | distinct draws | recovered | lost | both |
|---|---|---|---|---|---|---|
| **all** | 120 | 119 | 48 | **47** | 1 | 0 |
| near | 120 | 113 | 48 | 44 | 3 | 1 |
| fastslow | 80 | 60 | 34 | 27 | 5 | 2 |
| fast | 40 | 8 | 27 | 5 | 22 | 0 |
| wait | 40 | 0 | 15 | 0 | 15 | 0 |
| allnear (cut) | 7 | 5 | 5 | 3 | 2 | 0 |

Raw: `all attempts=120 recovered=119 lost=1 other=0 rate=0.992 distinct
first draws=48 ... trips median=44 max=112 cid-frames median=69582
max=216277`, `all distinct samples=48 recovered=47 lost=1 mixed=0
rate=0.979`; `near distinct samples=48 recovered=44 lost=3 mixed=1
rate=0.917`; `fastslow distinct samples=34 recovered=27 lost=5 mixed=2
rate=0.794`; `fast distinct samples=27 recovered=5 lost=22 mixed=0
rate=0.185`; `wait distinct samples=15 recovered=0 lost=15 mixed=0
rate=0.000`.

**Paired**, shift by shift (the same shift is the same boot): near lost on
shifts 28/31/35 (`rand $C1`), 262 and 490/497/504; all recovered on every
one of them (`OK/19`, `OK/31`, `OK/47`, `OK/38`, `OK/104` trips). all lost
once, at shift 476 (`LOST: Cid died -- health 20 as Celes walked into the
house on trip 7; first draw [roll 0011 rand $EA health 132]`: three
rerolls running with no fast fish and the -4 fish the only slow one,
`health 132 -> 111`, `111 -> 77`, `77 -> 51` with it caught each time;
`fish/all/shift476.ot6.log`), where near recovered (`OK/56`).

**Why**, per trip (`fish/fishtrips.txt`: Cid's health change by what swam,
over every trip of every run):

| what swam | near | all | fast | wait |
|---|---|---|---|---|
| no fast fish, no slow | -11.00 | -11.00 | -11.00 | -11.00 |
| no fast fish, one slow | -11.00 (back at once) | **-9.90** (catches it) | -11.00 | -10.99 |
| the fast fish and one slow | +18.57 | **+21.90** | +12.24 | +2.11 |
| the fast fish and two slow | +13.17 | +19.37 | +13.41 | -23.62 |

A slow fish is worth catching even when the fast one is absent: on
average it more than pays for the extra walk (-9.90 against -11.00 for
walking straight back), though a lone -4 fish does not, and that is how
`all` lost its one draw. Waiting at a spot is ruinous: over the `wait` runs
the fast fish swam beside (8,12) a median 1,589 frames after Celes reached
the beach (94 catches, 237 to 2,181; `fish/catch_times.txt`;
`fish/wait/shift00.ot6.log`: `caught fish 11 (speed 2) 1589 frames after
arriving`), against a median 277 for the chase (4,808 catches over the
`all` and `near` runs, p90 621). Catching only the fast fish leaves every
no-fast trip at -11. The first 40 `wait` runs are kept in
`fish-wait-fallback/`: their boot point fell to the runner's 2400-frame
fallback mid-wait, so all 40 were one draw (0 recovered); the re-run above
has the boot point on the beach.

**So the generator ships `all`**: every fish but the slowest, the fast one
first, whether or not it swims. Measured from the island save it recovers
Cid on 47 of 48 distinct draws, so a person playing this way saves him
first try about 49 times in 50, and the runner's retry covers the rest.
That is a ceiling of this bot's play, not of the game: the bot's timing is
deterministic, so a run can lock into a repeating cycle of rerolls
(`fish/allnear/shift00.ot6.log`: trips 11, 18 and 24 draw and catch the same
fish), which a person's uneven timing would break; and the lab's long
shifts cost Cid up to ~8 health before the first feed (the same for every
policy).

## The retry

A lost Cid is a lost attempt. The body raises `LOST: Cid died -- ...`; the
segment runner files it as class `lost` (`lib/ot6.lua` `classify`, one of
the seed-dependent classes with the wipe) and replays the body from the
boot snapshot at the next seed shift, bounded by its default 3 attempts,
each a `[retry] attempt n/N FAILED class=lost ...` line that
`tools/audit_retries.py` lists. Measured with the final generator
(`retry/final/`, the variants derived from it by one line each):

- `retry/final/fastslow14.log` (POLICY `fastslow`, which loses about one
  draw in five, at `OT6_SEED_SHIFT=14`): `[retry] attempt 1/3 FAILED
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
  back on the world map: the draw assertion's negative control): attempt 2
  draws attempt 1's `roll 1001 rand $09 health 105` and fails at once,
  `class=assert`: `assertEq failed: the first draw (roll 1001 rand $09
  health 105) differs from attempt 1's: the seed shift moved the fish
  rolls: got false, want true`.
- `retry/final/audit_retries.txt`: `lost x6 gen_wor_start_fastslow,
  gen_wor_start_nofish, gen_wor_start_nofish_contboot`, `assert x1
  gen_wor_start_nofish_contboot`.
- `retry/pre-final/` holds the same three shapes from the generator before
  its policy and budget settled (`shift30.log`: POLICY `near`, lost on the
  `rand $C1` draw, recovered on attempt 2, `PASS (frame 41886)
  attempts=2/4`).

The runner's own suites still hold with the new class and option
(`runner_suites_verdicts.txt`): `segment_retry: [ot6] PASS (frame 181)
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
397 at f80242`, `dialog $0891`, `map 400 at f81043`, `map 1 at f82233`,
`map 3 at f84204`, `map 1 at f84363`, `[wor] landed: world 1 at (146,212)
f84464, CELES HP 1043/1043`), about 4,200 frames from the raft talk. No choice prompt anywhere on the island or the raft.

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
  draw: roll 1010 rand $BC health 139`, `Cid recovered on trip 56 at
  f79386, health 266`, `[saved] wor-start-v1: slot 3 holds map 1 ($0401)
  world tile (146,212)`, `contract wor-start-v1 (exit): all 11 fields
  hold`, `PASS (frame 84778) attempts=1/3`. The capture
  (`capture_wor_start.log`) is the same run, `wor_start.mss` byte-identical;
  `validate_wor_start_v1.txt`: `holds=slot 3 world 1 (146,212)
  [$1F64=$0401] (saved: declared and checked)`.
- **Other draws** (`python3 tools/tests/seed_sweep.py wor_start --seeds 4`,
  `sweeps/wor_start-final3/`, retries off): `4/4 seeds passed`, first
  draws `rand $BC`, `$BE`, `$C1`, `$C3`, recovered on trips 56, 43, 19, 26
  (shift 30's `rand $C1` is the draw `near` loses). The lab above is the
  wider version: 119 of 120 attempts, 47 of 48 distinct draws.
- **The cold Continue** of the sealed `wor-start-v1` on this ROM
  (`OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/wor-start-v1
  tools/tests/run.sh tools/tests/probe_wor_start_continue.lua`,
  `continue_wor_start_v1.log`): `contract wor-start-v1 (entry): all 11
  fields hold`, `[continue] world 1 at (146,212): CELES L25 HP 1043/1043
  MP 227 kit 11 0E 76 8F D1 C1; Cid recovered $00B3=1; tonic=4 potion=39
  fenix=22 gil=215563`, `PASS (frame 1386)`.
- **The graph**: `python3 tools/tests/lib/compose.py --check-states`
  (`check_states.txt`): `fixtures: 96/96 fresh (ROM, generator, artifact and
  ancestor bindings all verify)`; `ninja build/checks/checkpoint_saves.ok`
  (`ninja_checks.txt`): `checkpoint-saves: PASS -- 29 checkpoints validate;
  each line names the save its battery holds`.

**For the next leg:** Tonics are far below the band (4 against about
L25 x 5, capped 99); Albrook, the town beside the landing, is the first
shop. CELES wears Break Blade / Blizzard on the Genji Glove, Gold Helmet,
Gold Armor and the Czarina Ring, and stands in the back row (above).
