# The World of Ruin opening: the Solitary Island to the first save (`wor-start-v1`)

Authored 2026-09-22 for #253 (the first step of #250). The segment is
`gen_wor_start` (`tools/tests/gen_wor_start.lua`): it boots `wor_landing`
(solo CELES at Cid's bedside, map 397, `$00A4` set), saves Cid, rides the
raft and saves on the World of Ruin map where it lands; that save is the
battery checkpoint `wor-start-v1`. Every number below is quoted from a log
under `build/attempts/wt/wor-start/` (`lab/` the probes and the earlier
generator cuts, `sweeps/` the seed sweep, `probes/` the one-off scripts
those logs came from). Nothing here was measured by writing game state.

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
396-400). Celes met no battle on the whole segment.

**Celes arrives bare.** At the landing every one of her six slots reads
`$FF`; her escape kit (Break Blade, Star Pendant, Jewel Ring) is in the bag
(`lab/probe_wor_kit.log`: `CELES equip FF FF FF FF FF FF`;
`python3 tools/audit_readiness.py build/states/wor_landing.mss`: `CELES
row=BACK def=0 mdef=0 NOTHING AT ALL`, six empty slots the bag could fill).
She is L25, 1043/1043 HP, 227 MP, and the bag holds `tonic=4 potion=39
fenix=22` (`[wor] boot f5: map 397 (99,38), party 1, CELES L25 HP 1043/1043
MP 227, Cid health 120, timer 0 flags $80 at $533F, fish 1101, tonic=4
potion=39 fenix=22`). The generator dresses her first: Genji Glove and
Czarina Ring on the Relic screen, after which the game's own Optimum fills
the gear (`[CELES relics] char=6 after=11 0E 76 8F D1 C1`: Break Blade,
Blizzard, Gold Helmet, Gold Armor).

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
  no fishing costs 11: `[cid] trip 4 done: 910 frames, caught {}, health
  184 -> 173`).
- **Where it stops.** FIELD_ONLY sets `$1188` bit 7, which
  `DecTimersMenuBattle` (`field/event.asm:5562`) skips, so menus and
  battles cost nothing (dressing her, two menu sessions and the field
  frames between them: `Cid health 120 before the menus, 118 after`); the
  world map does not run the field timer at all
  (`lab/probe_wor_islesave_1.log`: `[isle world] f451 ... health=114 timer0
  80/16`, 600 frames later `[isle world +600] f1051 ... health=114 timer0
  80/16`).
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
at each fish. The two SLOW fish look and swim alike; a player cannot tell
the +16 from the -4.

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
the beach entry (4,2) the shore is 14 steps (224 frames of walking), and the
fast fish is caught soon after Celes gets there (`catch_times.txt`:
`fast-fish catch frames after arrival: n=287 mean=411.8 p10=237 median=333
p90=685 max=701`), so the chase itself is not where the time goes: the
walk is.

## The policy, and what it wins

**Policy** (visible cues only: a fish's swim speed): if the fast fish is
swimming, catch it, plus a slow fish that swims up beside her on the way,
plus a slow one still within 240 frames once the fast one is caught; if
it is not, walk straight back and talk to him, which is the reroll. Never
the slowest fish.

Why, measured on `wor_landing` with probe variants of the same loop:

- **Fast fish only** drifts nowhere: 40 trips, health 120 -> 104
  (`lab/probe_wor_fish_4_min2.log`: `[fish end] trip 40 f50008 ... var7=104
  ... B3=0`). A trip that finds no fast fish costs 11; one that catches it
  nets about +12 after the walk to the shore and back.
- **Every fish but the slowest** recovered him in 18 trips on that seed
  (`lab/probe_wor_fish_4_min1.log`: `[fish end] trip 18 f35461 ... var7=274
  ... B3=1`), but chasing slow fish when the fast one is absent costs 14-34
  a trip for an expected +6 a fish.
- **The policy above**, over every trip of every generator log
  (`trips_bootstrap.txt`: `probes/trips.py` over both sweeps and
  `lab/gen_wor_start_{2,3}.log`; the recovering trip of each run left out):
  `fast present: n=269 mean delta +15.94 min 2 max 30`, `slow only: n=170
  mean delta -11.00 min -11 max -11`, `none: n=23 mean delta -11.00`.
  Bootstrapped from the island save's health 112 with the fast fish
  present half the time (its switch is one `if_rand`): `P(recovered)=0.8070;
  trips median 41, p90 90, p99 158`.

So an efficient, honest player saves Cid about **four times in five** per
attempt; the rest of the time the draw starves him. That is vanilla FF6
(every value above is the vanilla script), not an OT6 change, and it is a
lab candidate by the owner's bar (a segment not won reliably on the first
attempt).

## The island save, and the reload

Off 396's west edge Celes stands on the island's own World of Ruin tile
(76,239). The world map allows saving (`lab/probe_wor_islesave_1.log`: `ok:
island save: $0201 bit7 SET -- the game allows saving here = true`; `[isle
saved] slot 3 map 1 ($3001) world (76,239)`) and Cid's clock stands still
there, so a person who knows
he can be lost saves here before fishing. **This is the first save the
World of Ruin offers**, before the raft. The generator does the same, and
when an attempt loses him it reloads that save's snapshot and goes again,
at most 4 attempts, every attempt logged (`[cid] ladder: attempt n: ...`).
A reloaded attempt lingers 23 frames more per rung on its first look at the
beach, so the fish move the field RNG and the next reroll is a different
draw; the generator asserts each attempt's first reroll differs from every
earlier one. At the measured 0.81 the chance of losing all four is about
0.1% (`P(all 4 attempts lost) = 0.00139`).

The negative control is a mutant that never catches a fish
(`probes/mutant_wor_start_nofish.lua`, `SPEED_FAST = 9`): all four
attempts lose him on trip 9, on four different draws, and the run fails
naming the finding (`lab/mutant_nofish_1.log`):

```
[cid] ladder: attempt 1: Cid LOST on trip 9 at f9586 (health 21 entering the house), first reroll 0101 rand $AA; ...
[cid] ladder: attempt 2: Cid LOST on trip 9 at f17599 (health 20 entering the house), first reroll 1111 rand $B0; ...
[cid] ladder: attempt 3: Cid LOST on trip 9 at f25636 (health 20 entering the house), first reroll 1001 rand $B3; ...
[cid] ladder: attempt 4: Cid LOST on trip 9 at f33697 (health 20 entering the house), first reroll 1100 rand $B6; ...
FAIL: Cid died on all 4 attempts from the island save; the attempt lines above are the finding (a lab candidate)
```

## The raft and the landing

His recovery scene hides the stair cover (obj `$12` at (94,39)), which
opens the way down to the raft (397 (85,51)); `H.navTo` finds it once the
cover is gone. Talking to it plays his farewell (dlg `$0891`) and the
voyage: maps 397 -> 400 -> 1 -> 3 -> 1, control on the World of Ruin map at
(146,212), outside Albrook (`wor_start_ninja.log`: `[wor] the voyage: map
397 at f30916`, `dialog $0891`, `map 400 at f31714`, `map 1 at f32904`,
`map 3 at f34875`, `map 1 at f35034`, `[wor] landed: world 1 at (146,212)
f35136, CELES HP 1043/1043`: about 4,200 frames from the raft talk to
control). No choice prompt anywhere on the island or the raft.

## The checkpoint

`wor-start-v1` is the slot-3 save at the landing, through the real Save UI:
`[saved] wor-start-v1: slot 3 holds map 1 ($0401) world tile (146,212)`.
Its manifest declares `"saved": {"slot": 3, "world": {"map": 1, "x": 146,
"y": 212}}` (`lib/sram_checkpoint.py` now reads map 1 as the World of Ruin
world map), and `lib/ot6_contract.lua` carries its contract (world map 1
at (146,212), `$00A4`/`$00B3` set, `$00B4` clear, CELES alone), asserted by
the generator after the save and by a WoR generator's cold Continue
(`H.assertEntryContract("wor-start-v1")`).

## The runs behind it

- **The graph edge** (`nice ninja build/states/wor_start.mss.lua`,
  `wor_start_ninja.log`): `[cid] ladder: attempt 1: Cid RECOVERED on trip
  20 at f30060, first reroll 1110 rand $2B`, `contract wor-start-v1 (exit):
  all 11 fields hold`, `PASS (frame 35450) attempts=1/3`, 2:11 of wall
  clock (`ninja_wor_start_pre-comment-edit.txt`; the final edge is
  `ninja_wor_start.txt`, same verdict after a comment-only generator edit).
- **The capture** (`capture_wor_start.log`, `OT6_CAPTURE_SRM`, artifacts
  kept out of `build/states`): the same run frame for frame, `PASS (frame
  35450) attempts=1/3`, and its `wor_start.mss` byte-identical to the
  edge's; sealed and validated (`validate_wor_start_v1.txt`): `valid
  ot6.sram-checkpoint/v1: 32768 bytes sha256=1ae3a148... holds=slot 3
  world 1 (146,212) [$1F64=$0401] (saved: declared and checked)`.
- **Other draws** (`sweeps/wor_start-final/`, 8 seed shifts, retries off):
  `8/8 seeds passed`, every one on attempt 1. The shifts reach four
  different feeding runs: shifts 0 and 7 draw `first reroll 1110 rand $2B`
  and recover him on trip 20; shifts 14, 21 and 49 draw `1000 rand $3C`
  and need 35 trips (`[cid] ladder: attempt 1: Cid RECOVERED on trip 35 at
  f50913, first reroll 1000 rand $3C`, `PASS (frame 56304)`); shift 28
  recovers him on trip 21 and shifts 35/42 on trip 22 from the same first
  reroll after the paths part. (A seed shift idles at the boot on 397,
  where nothing draws from the field RNG; it moves the draw only through
  when the timer event interrupts the first walk, so neighbouring shifts
  often share a run.)
- **The cold Continue** of the sealed battery on this ROM
  (`OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/wor-start-v1
  tools/tests/run.sh tools/tests/probe_wor_start_continue.lua`,
  `continue_wor_start_v1.log`): `contract wor-start-v1 (entry): all 11
  fields hold`, `[continue] world 1 at (146,212): CELES L25 HP 1043/1043
  MP 227 kit 11 0E 76 8F D1 C1; Cid recovered $00B3=1; tonic=4 potion=39
  fenix=22 gil=215563`, `PASS (frame 1386)`.

**For the next leg:** Tonics are far below the band (4 against about
L25 x 5, capped 99); Albrook, the town beside the landing, is the first
shop. CELES wears Break Blade / Blizzard on the Genji Glove, Gold Helmet,
Gold Armor and the Czarina Ring, and stands in the BACK row
(`audit_readiness`: `CELES row=BACK`), which halves her own Fight damage;
where a lone swordswoman stands is the first WoR fight's call.
