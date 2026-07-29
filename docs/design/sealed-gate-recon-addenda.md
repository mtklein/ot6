# Sealed Gate recon — addenda and §11-style corrections

Companion to `docs/design/sealed-gate-recon.md`. The recon was a read-only
pass; this file records what the **live** pass measured, in the recon's own
§11 spirit: an offline claim that survived contact, an offline claim that
did not, and the things nobody could have known without booting the game.

The recon itself is left unedited on purpose. It is the route bible as
written on 2026-07-28 before any emulator ran; a bible that quietly agrees
with every later measurement teaches nothing about how much to trust the
next one.

---

## Addendum 1 — 2026-07-28, the first minting pass (issue #31, legs F→G/G→H)

Source: `tools/tests/probe_v07_f2g.lua`, `probe_v07_fly.lua`,
`probe_v07_g2h.lua`, `probe_v07_base.lua`, `probe_v07_385.lua`,
`probe_v07_385walk.lua`, `probe_v07_gatebattles.lua`, and the minted leg
`tools/tests/gen_narshe_mission.lua`. Every claim below is either a log line
from one of those runs or a `file:line` read; nothing is inferred from the
recon's tables.

### 1.1 CORRECTION — the base entrance's first `$01A0` test is a party COUNT, not Terra

Recon **headline 3** and **§1 leg 2** read `_cb25d6` (`event_main.asm:44004`)
as "refuses passage unless TERRA is in the active party", citing the
`set_case PARTY_CHARS` + `if_switch $01A0` pair. The conclusion is right;
the mechanism as stated is not, and the difference matters to anyone writing
a fixture assertion against those switches.

```
event_main.asm:44008   call _cac5c1
event_main.asm:44009   if_switch $01A0=1, _cb2606      <- NOT "Terra in party"
event_main.asm:44010   set_case PARTY_CHARS
event_main.asm:44011   if_switch $01A0=1, _cb2a5b      <- THIS is the Terra gate
```

`_cac5c1` (`event_main.asm:30515-30588`) is a **party-size encoder**. It
zeroes `$0124-$0126`, walks the thirteen `$01A0-$01AD` PARTY_CHARS bits
calling `_cac680` (`:30589`) once per member — a three-bit counter — and
then **overwrites `$01A0-$01A3` with a one-hot encoding of (count − 1)**
(`:30561-30588`). So after the call:

| party size | switch left set |
|---|---|
| 1 | `$01A0` |
| 2 | `$01A1` |
| 3 | `$01A2` |
| 4 | `$01A3` |

Line 44009 therefore branches to `_cb2606` on a party of **one** — the solo
scene where Terra says "I can do it… But why do I feel so wretched?"
(dlg `$0660`) and the party is bounced back to world (164,194). Only after
`:44010` restores the real per-character case does `$01A0` mean TERRA again,
and only that second read is the recon's gate.

Live confirmation (`probe_v07_base.lua`, party TERRA·LOCKE·EDGAR·SABIN):
line 44009 fell through, line 44011 took `_cb2a5b`, and the "That's odd… No
Imperial soldiers…" beat played with `$0172` latching. The recon's practical
conclusion — **Terra is a hard gate, the leg needs a swap-room drive** — is
confirmed. Its citation is not usable as an assertion.

### 1.2 CORRECTION — the offline formation decode was a STRIDE error, not lying data

Recon §3.1 and §5 hazard 4 treat the offline `battle_monsters.dat` read as
untrustworthy, on the §11 precedent that it "proved wrong for battle 70
(Shiva is not in the formation — she was)".

`battle_monsters.dat` records are **fifteen bytes**, which the engine
computes as `index * 16 − index`:

```
ff6/src/battle/battle_main.asm:8123-8128
        lda     $11e0
        asl4                     ; *16
        sec
        sbc     $11e0            ; -1x  => *15
        tax
@3155:  lda     f:BattleMonsters,x
```

and the layout is byte 1 = present-bitfield, bytes 2-7 = monster id LOW
bytes, bytes 8-13 = positions, byte 14 = the six id HIGH bits. Decoded that
way:

| battle index | record | contents |
|---|---|---|
| 384 (event group 121) | `00 01 7B FF FF FF FF FF 47 00 00 00 00 00 3F` | one `$17b` |
| 385 (group 122) | `00 01 7B …  37 … 3F` | one `$17b` |
| 386 (group 123) | `00 01 7B …  48 … 3F` | one `$17b` |
| 387 (group 125) | `00 01 2E …  6A … 3F` | one `$12e` (Ultros ③) |
| 524 (group 149) | `00 01 03 …  97 … 3E` | one `$003` (Ninja) |
| **70** | `10 07 0E 0E 08 FF FF FF B5 44 9E 00 00 00 38` | **`$00e`, `$00e`, `$008` — three** |

Battle 70 decodes with three monsters, which is what the v0.6 doorstep run
actually saw. So the §11 entry is best read as **"the decode we ran was
wrong"**, not "this data cannot be decoded offline". A decode that names its
record stride and cites the engine's own index arithmetic is evidence; a
decode that does not is a guess. The gate formations survive contact
(§1.6 below reads them live).

Event-battle group → battle index comes from
`ff6/src/field/event_battle_group.dat`, 4 bytes per group, two candidate
indices selected 3/4 and 1/4 (`EventBattle`, `ff6/src/field/event.asm:1909-1941`).
For groups 121/122/123 **both candidates are identical**, so the roll cannot
vary the fight — worth knowing before anyone writes a formation guard.

### 1.3 NEW — how the Blackjack is actually flown (the recon says "fly to Narshe")

Recon §1 leg 1 says "Fly to Narshe" and stops there. Measured
(`probe_v07_fly.lua`, `probe_v07_f2g.lua`):

* A cold Continue of `terra-returned-v1` restores the party **on foot,
  standing on the parked ship's tile** — `save-points-vector.md` §5's
  F-anchor note, re-confirmed (`$11FA&3 = 0`, `$11F3 = 0`).
* **One A tap boards AND lifts off** in a single beat. There is no
  intermediate "aboard, grounded" state to wait for. In flight the on-foot
  position cells `$E0/$E2` read **zero**, so "airborne" is exactly
  `$E0 == 0 and $E2 == 0`, and the ship's own tile is
  `word($34) >> 4, word($38) >> 4`.
* **A bare d-pad in flight only ROTATES the ship.** 240 held frames per
  direction moved `$34`/`$38` not at all, while `$29`/`$2E` carried angular
  velocity and `$30` the heading. **Y + direction strafes** — the landing
  idiom `gen_terra_returned_anchor.lua` used to ground the ship is in fact
  the only way to fly a planned course at all.
* **X in flight exits to the Blackjack deck**, map 6 (16,6)
  (`ff6/src/world/ctrl.asm:371-391`, the `VehicleEvent_00` dispatch). This is
  how leg G→H reaches the party-swap room without landing.
* **B over a landable tile grounds the ship**: "landable" is the live prop
  byte `$c2` bit 1 clear (`LandAirship`). Grounded, the party is in the
  parked state again and one walkable step puts them on foot.
* **The wheel now asks.** `_caf532` (`event_main.asm:36118`) is facing-LEFT
  + A gated (`$01B3`/`$01B4`); on the *first* takeoff (`$0170 = 0`) it lifts
  off silently, which is why `gen_terra_returned_anchor`'s bare LEFT+A hold
  worked — **but that takeoff set `$0170`**, so from anchor F onward the
  wheel opens dlg `$052A` "0: (Lift-off) / 1: (Not just yet)"
  (`_caf56e`, `:36145`) and a held A yields only the edge that opens it.
  Any later leg that boards from the deck needs a choice-pick, not a hold.

Landing tiles confirmed: (84,36) beside Narshe and (163,194) in the Imperial
Base pass are both airship-landable, matching the recon's offline decode.

### 1.4 NEW — the party-swap room, the recon's open question 6

`_cb41a5` (`event_main.asm:47153`) is the swap room's arming script; the
talk handler is `_caf59d` (`:36171`). Measured flow, end to end
(`probe_v07_g2h.lua`):

1. The room is map **7**, the Blackjack interior, reached deck (20,6) →
   7 (40,11) → the (40,18) stairs → (50,51). The thirteen character NPCs
   stand at the `npc_prop.asm` map-7 coordinates; **TERRA is object `$16`**
   (`make_npc {58,58}, $0477`) and she **wanders** (`set_npc_movement RANDOM`),
   so the drive is a chase-talk that re-plans its approach every aligned
   frame, not a fixed navTo.
2. Talking her opens dlg `$0528` "Change party members? / 0: No / 1: Yes"
   (`_caf59d`, `:36172`). **Index 0 is No** — a blind A-tap answers "No" and
   the leg silently does nothing. The choice must be driven to index 1.
3. Yes runs `_caf5a8` → `_caf601` → `party_menu 1, NO_RESET, {LOCKE, CELES}`
   (`:36211-36217`). **Measured: the menu opens with all four party cells
   EMPTY** (`$7E9D89 + $10..$13` all `$FF`) and the pool holding
   `00 01 02 04 05 09 0B` = TERRA LOCKE CYAN EDGAR SABIN SETZER GAU. The
   `{LOCKE, CELES}` list in the opcode pre-fills nothing on this chain, so a
   drive that assumes Locke is already seated seats three and commits a
   party of three. All four must be placed.
4. START commits; `update_party` runs and the game **reloads map 7 at
   (40,16)** — the `$0246` branch's second `load_map` (`:36203`), one step
   below the (40,10) deck door.

`gen_kefka_won.lua`'s state-fed party-menu driver works unchanged here, with
one change: the pool cells must be **looked up at runtime** (`cell9d(c) ==
charId`), not hard-coded, because this menu's pool is availability-ordered
and will move the moment the roster changes.

### 1.5 CORRECTION/AMPLIFICATION — map 385's floor is harder than "navTo cannot drive it"

Recon §1 leg 3 and §5 hazard 2 say `navTo` cannot drive BASEMENT 2 and that
it needs "a phase-aware crossing". Both true. What the recon could not know
is that the room is **not a maze with moving damage tiles — it is two
complementary tilemaps**, and the reachable set in *either* phase is a dead
end from the entry.

Measured (`probe_v07_385.lua`, from the real cave entry state):

* Phase period is **158 frames**, not 144: the script's `wait 144` /
  `start_timer …,144,…` (`event_main.asm:44634-44758`) plus the callback's
  own `mod_bg_tiles`/`wait_bg` work.
* Row 2, as the tilemap flips (tile prop byte `$7E7600[tile]`):

  ```
  $01F5 on:  x=3..6 walkable (0A)   x=7 WALL   x=8 walkable   x=9 WALL
  $01F6 on:  x=3 walkable   x=4..6 WALL        x=7..9 walkable (02)
  ```

  — exactly complementary, and `F7` (the wall value) has bits 0-2 set, i.e.
  the model's counter/wall rule, *and* bits 6-7, i.e. it is also a diagonal
  tile. A walker that does not model both will mispredict.
* **Reachable-set census from the entry (1,2): 17 tiles in `$01F5`, 12 in
  `$01F6`.** Neither contains the (13,13) exit door, the (10,2) second
  cycle-A trigger, or either cycle-B trigger ((11,3)/(13,11)). So no single
  BFS can ever find a path; the crossing exists only across time.
* Arming works as the recon reads it: (3,2) fires `_cb2aca` (`:44634`),
  `$01F0`/`$01F2` set, and the timers start.

**And the trap the recon does not mention**: `_cb2dbb`/`_cb2dd2`
(`:44869`/`:44884`) hurt on the tile the party is **standing on**, not only
on the tile it steps onto. Measured (`probe_v07_385walk.lua` run 1): the
party walked to (6,2) during `$01F5`, stood still waiting for the swap, and
the swap itself fired (6,2)'s `_cb2dd2` — HP/8 to all four, teleport of
SLOT_1 to (2,6), and `_cb2dfa`'s wipe of **every** `$01F0-$01FF` bit, which
also stops the cycle. So a phase-aware walker must additionally never *rest*
on a tile that belongs to either hurt list; the safe standing tiles on row 2
are only (3,2), (8,2), (10,2) and x ≥ 11.

`phaseWalk` in `probe_v07_385walk.lua` implements the idiom (BFS-first,
greedy-no-regress fallback, wait for the swap, hurt-list guard on every
destination). It arms cycle A and moves correctly along row 2, and it is
**not yet a crossing**: the walker still cannot get from (6,2) to (8,2),
because doing so requires being on a *specific* tile at the *instant* of a
swap rather than merely stepping when a tile is open. **This is the leg
G→H blocker as of this pass** — see Follow-ups in the dispatch report. One
no-regress rule already fixed a 6000-frame oscillation (BFS routed the party
back west when the east tile closed), so the walker's shape is right; what
is missing is a phase-phase-aware *timing* rule, not more search.

### 1.6 ANSWERED — recon open question 1: what battles 121/122/123 really are

Driven live (`probe_v07_gatebattles.lua`), with the real gate party
(TERRA·LOCKE·EDGAR·SABIN), by writing the event-battle index straight to
`$0011E0` the way `EventBattle` does — the `gen_n128` idiom — and then
pressing **nothing but edge-A**: no kill-bit, no directions.

| | battle 121 (idx 384) | battle 122 (idx 385) | battle 123 (idx 386) |
|---|---|---|---|
| live formation `$57C0` | `017B FFFF ×5` | `017B FFFF ×5` | `017B FFFF ×5` |
| monster HP | 1 | 1 | 1 |
| party battle HP, start → end | 345/447/448/457 unchanged | unchanged | 345/447/312/0, unchanged |
| party FIELD HP before/after | 345/447/358/224 → identical | identical | identical |
| ends by itself after | 1278 frames | 1371 frames | 2603 frames |
| battle switches after | `$1DD0..DF` unchanged | unchanged | unchanged |

The offline decode is **confirmed live**: all three are the one-monster
`$17b` dummy formation, and `$17b`'s entire AI script
(`ff6/src/battle/ai_script.asm:8061-8086`) is a battle-id dispatcher with
**no attack command anywhere in it**:

```
AIScript::_379:
        target_off SELF                     ; untargetable in every fight
        if_battle_id $0180 (=384): battle_event $13, kill_monsters MONSTER_1, INSTANT
        if_battle_id $0181 (=385): battle_event $14, end_battle
        if_battle_id $0182 (=386): battle_event $15, end_battle
        ... ($0185/$0186/$0189 = other scenes reusing the same dummy)
```

**Verdicts for the H→I gen:**

1. **Contents: dummy, and that is the truth, not an artifact.** The theater
   is in `battle_event $13/$14/$15` (AI opcode `$f7` → battle command `$23`,
   `battle_main.asm:4544`), which is battle-internal choreography, not a
   formation.
2. **Not loseable.** Nothing in the three fights can reduce party HP: the
   monster is `target_off SELF`, has one HP, and issues no action. Measured
   party HP identical at both ends of all three, in battle and on the field.
   A party arriving at the gate on fumes still survives the set piece — the
   full heal `_cacfbd` before each (`:31862`) is belt-and-braces.
3. **The kill-bit idiom must NOT be used here.** 384 kills its own monster
   (`kill_monsters MONSTER_1, INSTANT`) after its event; 385 and 386 end via
   `end_battle`, which is not a victory and sets no win bit — consistent
   with the recon's observation that no `if_b_switch` follows either. Any
   driver that kill-bits the dummy risks pre-empting `battle_event` and
   cutting the scene. **The right drive is `advanceStory` with all three
   formations in `opts.spare`** (hands off, then edge-tap A after ~300
   frames), which is exactly the treatment the esper-zap set piece already
   gets.
4. **Budget them.** ~1280 / ~1370 / ~2600 frames of pure choreography, on
   top of `_cb39ca`'s field scene. Leg H→I is long before anything walks.
5. **`battle_event $15` rewrites the on-screen party.** The battle-123 HUD
   read **TERRA / LOCKE / SETZER** with slot 4 at 0 HP even though the field
   party going in was TERRA·LOCKE·EDGAR·SABIN — the deck scene stages the
   Blackjack crew. A fixture that asserts the roster across battle 123 must
   assert it on the FIELD side, before and after, never from inside.

Caveat, stated plainly: these fights were **forced from map 385**, not
reached through `_cb39ca`. Everything measured above is a property of the
battle (formation, AI, damage output, duration, self-termination) and is
context-free. What this probe does **not** establish is the surrounding
field script's behavior — in particular that `char_party TERRA, 0`
(`:46095`) before battle 121 leaves the fight loseable-in-a-different-way
with a three-person party, which it cannot, since the monster still never
acts.

### 1.7 CONFIRMED — everything else the legs touched

Route facts the recon states and this pass drove without surprise:

* Narshe: world (84,33) → map 20 (38,61); the (37-39,51) trigger row fires
  the escort; the meeting is on map 30; `$0076=1` and `$045E-$0467=0` at
  `event_main.asm:94170-94180`. Driven; contract `narshe-mission-v1` asserts
  all of it.
* The base: world (165,194) → 377 (6,17); the (6,16)/(7,17)/(6,18) trigger
  row; `$0172` latches the no-soldiers beat; the east door long entrance
  377 (31,12) → world (167,194); the pocket (167-169,194); (169,194) →
  382 (25,37). All driven.
* The cave graph 382 (31,43) → 383 (50,43) → (53,58) → 385 (1,2) →
  (13,13) → 384 (26,8): entrance records confirmed against the live
  transitions for every hop up to 385.
* The base entrance trigger row is a **re-entry trap** of the save-tile /
  BIG_SWITCH class: after the scene the party stands on a trigger tile,
  `_cb25d6` re-enters and `EventReturn`s every frame, and `hasControl()`
  never holds — a `navTo` there BFS'd zero steps for 20 000 frames. Leave
  with an unconditional held press. (The landing tile (6,17) is *not* itself
  a trigger; one held RIGHT both fires the beat and starts the crossing.)
* The world menu on foot at the Narshe exit spawn allows saving
  (`$0201` bit 7 = `$80`) and, like the grounded-airship world menu,
  **does not unwind on B** — 900 frames of edge-pressed B left `$0059`
  nonzero. Any world-save generator must mint its savestate *before*
  opening the menu.

## Addendum 2 — 2026-07-28, the crossing and anchor H (issue #31, leg G→H finished)

Source: `tools/tests/probe_v07_385win.lua`, `probe_v07_385door.lua`,
`probe_v07_385walk.lua` (draft 2), `probe_v07_384.lua`,
`probe_v07_386tile.lua`, `probe_v07_g_boot.lua`, and the minted leg
`tools/tests/gen_gate_cave_save.lua`.  Same rule as Addendum 1: every claim
is a log line or a `file:line` read.

### 2.1 RESOLVED — §1.5's blocker: the crossing is the REWRITE WINDOW

The missing "phase-aware timing rule" is three measured facts:

1. **Every swap callback rewrites the tilemap BEFORE it flips the phase
   switches** — `_cb2bb2` (`event_main.asm:44700`) is `call _cb2b24` (the
   ASYNC `mod_bg_tiles` + `wait_bg` block) and only THEN
   `switch $01F5=0 / $01F6=1`; `_cb2c57` (`:44735`), `_cb2d1e` (`:44812`)
   and `_cb2d97` (`:44853`) all have the same shape.  Measured on the live
   floor: the whole rewrite lands in ONE frame at **fsf 145** of the
   158-frame cycle (fsf = frames since the last `$01F6` edge), the switches
   flip at fsf 158.  For ~13 frames the NEXT phase's floor is physically in
   place while the hurt triggers — keyed on `$01F5`/`$01F6` — still answer
   for the OLD phase.
2. **A held press into a tile the window just opened is taken at fsf ~148**,
   even though `hasControl()` is false throughout (the timer callback is an
   event; `player_ctrl_on` stands).  Every hurt tile is an event-trigger
   tile that re-enters its script each frame when stood on (§1.7's re-entry
   class), so a `hasControl`-gated walker goes PASSIVE exactly on the
   boundary tiles — that, precisely, was draft 1's failure at (6,2), and
   why it then ate the swap standing still.  Unconditional holds are not
   optional here.
3. **Mid-step is immune.**  The party left (6,2) at fsf 148, was unaligned
   through the fsf-158 flip, and took no hurt even though (6,2) is on the
   `$01F6` hurt list; arrival on (7,2) at fsf 4 of the new phase ran
   `_cb2dbb`, which `EventReturn`ed (`$01F5` now 0).  `CheckEventTriggers`
   (`ff6/src/field/event.asm:5740`) demands exact sub-pixel alignment,
   which a party mid-step never has.

Walls also turned out to be walkable-off: an F7 tile's p2 byte reads $FF
(all four exit bits), so the engine lets the party step OFF a tile that
just closed under it — the model's `stepAllowed` agrees once given the
new-phase snapshot.

`phaseWalk` (now `lib/ot6_field.lua M.phaseWalk`, promoted with
`M.chaseTalk`) implements the full rule: snapshot the `canStep` grid once
per phase, BFS the UNION graph over (x,y,phase) nodes with three edge
kinds — `move` (inside a phase), `flip` (stand through a swap on a tile
walkable in both phases and on neither hurt list), `window` (the timed
boundary step, held from fsf ≥ 132) — and execute clocked on observed
`$01F6` edges (only the four timer callbacks touch `$01F6`; the arming
scripts' trailing `wait 144 / switch $01F5=1` touches `$01F5` alone).  An
in-phase lane of k steps is only STARTED when `fsf + 16k + 24 ≤ 158`.

The measured route (deterministic, byte-identical across two runs, and a
third inside the minted leg): arm A at (3,2) → moves to (6,2) in `$01F5` →
window → (7,2)..(11,2) in `$01F6` → (11,3) arms B → moves to (11,6) in
`$01F5` → window (11,7) → window (11,8) → (12,8) → window (12,9) → moves
to (13,12) in `$01F6` → door (13,13) → 384 (26,8).  Four window steps
total; the (11,7)→(11,8) pair is two windows back to back, which the
union BFS found on its own — the hand plan had a longer x=13/x=14 route.

Two more floor facts the crossing depends on:

* **Arming B kills cycle A** — `_cb2c6e` (`:44746`) runs `_cb2b06` = stop
  every timer + wipe all `$01F0-$01FF`, then re-arms only B, so `$01F0`
  reads 0 afterward and the WEST half freezes in whatever phase it was.
  Stepping back onto (3,2)/(10,2) then would RE-arm A and freeze the east
  half mid-crossing; the post-B `phaseWalk` lists both in `avoid`.
* **A random encounter does NOT reset the room.**  Map 385 carries an
  encounter group (a Zombone fired on the door step, walk run 3 — the
  first draft of the door hold read its battle module as "a menu opened,
  $59=52").  Measured (`probe_v07_385door`): the battle round-trip is a
  state restore, not a `LoadMap` — `$01F1`/`$01F3` survive, the timers
  keep flipping (156-frame gap across the return), and the door works
  after.  The map-init does re-base the DEAD cycle's region ($01F0=0 →
  `_cb2bc9`'s static layout), so `phaseWalk` re-snapshots and re-plans
  after any battle, stepping off a hurt-list tile first if the battle
  parked it there.

### 2.2 NEW — BASEMENT 3 (384) and the save room, the live census

From the (26,8) entry, fresh map (all `$01Fx` zero — the 385 door's
`LoadMap` wiped them):

* The reachable set is **263 tiles — the SOUTH loop**: (40,11), (58,18),
  (62,11) and (66,11) are inside; **(46,11), the save-room door (64,10),
  the gate door (9,27) and the (5,43) shortcut are NOT**.  The
  (41..45,11) span of the recon's west bridge is OUT on entry, so the
  (46,11) retract scene cannot fire on this route at all.
* **The save-room door is the (62,11) switch.**  `_cb3062`
  (`event_main.asm:45148`) is face-UP+A gated ($01B0/$01B4); its
  `_cb303e` patch rewrites {62,10} and {63,9}×{3,3} — which IS the (64,10)
  doorway (prop F7 → 02, measured) — and latches **persistent `$0173`**,
  now pinned in the gate-cave-save-v1 contract.  The lever idiom
  (gen_sabin_train's `upA`: stand ON the trigger, hold UP into the wall,
  edge-A) fires it in 45 frames.
* The (66,11) Ninja trap switch is two tiles east of the door and is
  face+A gated too — plain walk-over `EventReturn`s (`_cb307e:45156`
  checks `$01B5` and the $01B0/$01B4 pair first).  The route never
  presses it.
* 384 (64,10) → **386 (73,58)**, and the save point is the recon's
  (74,53) (`event_trigger.asm:1888`).  No phase floor anywhere on this
  route; `navTo` drives everything but the switch and the two doors.

### 2.3 NEW — a HELD press walks THROUGH a save point without firing it

Measured (`probe_v07_386tile`): held UP from (74,54) carried the party
straight over (74,53) to (74,51) with `$01BF` still 0 — the SavePoint
trigger never ran.  `CheckEventTriggers` (`field/event.asm:5740`) requires
the party at exact sub-pixel rest, and a held-press step chain never
rests.  This is the inverse of the §1.7 re-entry trap: held presses ESCAPE
trigger tiles, and they also SKIP them.  The idiom that stops ON the tile
is gen_n024_save_anchor's `tapInto` (tap 8 frames, release, settle) — 26
frames to `$01BF=1` in the minted leg.  Any future leg that must FIRE a
walk-over trigger should tap, not hold.

### 2.4 CORRECTION — word($34)/($38) are NOT "the ship" on foot

§1.3 said the ship's tile is `word($34)>>4, word($38)>>4`.  That held in
flight and aboard; ON FOOT on the world map those cells track the PARTY
(measured, `probe_v07_g_boot`: both pairs read the party's tile through a
walk).  The parked ship's true position is the save-block pair
**`$1F62`/`$1F63`**, and a cold Continue of narshe-mission-v1 restores the
ship exactly there — (84,36), two south of the party's (84,34) boot tile.
On anchor F the two coincided because that save was taken aboard.  The
G→H leg walks to (84,36) first; one A tap there boards and lifts off as
§1.3 says.

### 2.5 Anchor H stands

`gate-cave-save-v1` is cut: the whole G→H leg lives in
`gen_gate_cave_save.lua` (gen_narshe_mission's one-generator shape), ends
on the 386 (74,53) save tile through the real Save UI into slot 3, and
the graph edge `gate_cave_save` mints from the narshe-mission-v1 battery.
Exit contract: 22 fields (18 pre-save + the 4 sram witnesses), including
the Terra invariant party-by-name and `$0173`.  Fail-before observed by
perturbation (benching SABIN on the minted state fails the pre-save
contract by name — party count 4→3 and his membership — after an
unperturbed positive control held all 18); pass-after "all 22 fields
hold" through the real anchored ninja mint, frame-identical (14090) to
the by-hand capture run.

## Addendum 3 — 2026-07-28, leg H→I (issue #31): the 384 west traverse, the gate scene ridden, the crash measured

Source: `tools/tests/probe_v07_384west.lua` (+`west2`..`west5`),
`probe_v07_384toggle.lua`, `probe_v07_gatescene.lua` (+`2`/`3`), and the
minted leg `tools/tests/gen_vector_crash.lua`.  Same rule as before: every
claim is a log line or a `file:line` read.

### 3.1 ANSWERED — recon open question 2: the 384 west traverse is TWO levers and a teleport

The recon's expectation ("east across the bridges → toggles → teleport
back west → (9,27)") was directionally right, and five of the seven
switch sites are NOT on the route.  Measured, from the 386 exit
((73,59) → 384 **(64,12)**, short-entrance decode + live):

* **Fresh census from (64,12): 266 tiles** — the south loop again, with
  the save door held open by persistent `$0173`.  The gate door is not in
  it; neither teleport is.
* **(58,18) is a dead end for the traverse.**  It fires (face-UP+A), the
  event scripts a forced descent — `move DOWN,5` + `jump_low` + `DOWN,1`,
  the party ends at **(58,24)** and the ledge above rewrites, so the
  switch tile itself leaves the reachable set — and its `$01F9/$01FA`
  span (48..50,12) only opens the (46..41,11) west bridge row: census
  after (still 266 tiles) adds **no** goal tile.  The leg does not press
  it.
* **(71,15) (`$0174`, persistent) is the first real key**: the x=76
  column bridge (76,16..27) takes the census **266 → 587 tiles** — the
  whole east half, including both walk-over rows, (99,13) and the
  (104,17) toggle.  The three walk-overs ((89,29) `$0175`,
  (96,18)/(99,18) `$01F3/$01F4`) serve the treasure-alcove teleport
  ((94,25) → (90,58)) and the tower's internal ladders; none is needed
  to go west.
* **(104,17) (`$01F5`, session TOGGLE) is the second key**: its 5×13
  tower rewrite takes **587 → 655 tiles** and opens the (120..121,17..23)
  descent to the teleport pair.
* **The teleports are one-way single-tile entrance records** (6-byte
  short-entrance decode, offsets from `short_entrance.inc`’s pointer
  table): `(4,36)→(121,22)`, `(121,23)→(4,37)`, `(94,25)→(90,58)`,
  `(90,59)→(94,27)`.  They are LoadMaps: crossing (121,23) **wipes every
  `$01F0-$01FF` session switch** (`$01F5/$01F9/$01FA` all read 0 on the
  west side) while `$0173/$0174` re-apply through map-init `_cb2e3d`.
  Entrances fire under a held walk (only EVENT triggers demand the
  at-rest frame), so the crossing is a plain `pressWalk`.
* **The west side is a 64-tile pocket.**  The gate door row —
  `(9..11,27)`, one long entrance of length 2 → 391 (8,21) — is
  approached ONLY from the south, up the x=9..11 column; `(12,27)` is not
  walkable, so the doorstep is **(10,28)**, the same tile the scene later
  exits onto.  The (5,43) shortcut is NOT reachable before the scene —
  the recon's "inference, unverified" is now measured fact both ways:
  after `$0079=1` the `_cb2aa6` retile opens it (post-scene census: 60
  tiles, (5,43) inside).

### 3.2 NEW — the lever/toggle idiom has a sharp edge the G→H leg never hit

`probe_v07_384toggle`, frame-instrumented on (104,17):

* ONE 8-frame up+A tap fires `_cb33c9`; the event runs ~70 frames and
  `switch $01F5=1` is its LAST line (event_main.asm:45558) — the switch
  flips at the END, not on the press.
* Holding UP on the tile with A released for 900 frames does NOT
  re-fire.
* A SECOND tap runs the `_cb3506` reverse branch and toggles BACK.

So the G→H `upA` loop (A edges until the switch reads 1) is the WRONG
drive for a toggle: iteration 3 of the census probes watched `$01F5` hit
1 under that loop and read 0 again by the next census — the loop's own
lingering press had re-armed it.  The H→I generator's `tapLever` (tap
once, hold up, wait for the flip) is the idiom.  The latched levers
((62,11)/(71,15)) tolerate the old loop only because their guards
EventReturn once set.  Both lever tiles are stood-on re-entry triggers
(§1.7 class): leaving them takes an unconditional held press, and
DOWN from (71,15) is a wall — the escape must cycle directions.

### 3.3 ANSWERED — the gate scene fires on entry, and its tail is exactly the recon's

* The long entrance lands on the trigger and `_cb39ca` is running by the
  first observable frame after the map load — **no step needed** (recon
  §5 hazard 6's "frame-0 or first-step" is settled: frame-0 class).
* `advanceStory` with `opts.spare={0x017b}` rides the whole thing:
  exactly two battle loads (121 then 122, live formation `017B` each),
  never kill-bitted, ~10 270 frames from the door to control.
* Tail confirmed live: control returns at **384 (10,28)** with
  `$0079=1 $0471=1 $064D=1 $064C=0`, and the FIELD party is
  TERRA·LOCKE·EDGAR·SABIN again (`char_party TERRA,0` at :46095 undone
  at :46202) with SETZER still benched.

### 3.4 ANSWERED — the base re-cross and the crash, end to end

* From the pocket, (166,194) enters the base east door (30,13); the west
  trigger row fires `_cb280f`.  With SETZER benched (`$01A9=0`) the
  scene takes the `_cb28ea` NPC-crew branch (`$0459` latch): the deck
  scene stages a crew NPC where Setzer would stand, battle 123 loads
  once (`017B`), and the whole stretch — ensemble scene, `$0242=1`,
  deck scene, battle, crash flight — took **6 304 frames** from the
  trigger row to control.
* **Control returns on MAP 6 at (16,6)**, not on the world map: the
  crash tail is `set_parent_map 0,{83,239}` + `load_map 6,{16,6}` with
  a startup event (event_main.asm:44520-44531).  Recon leg 4's "control
  aboard the grounded wreck" means the DECK; the world map is only
  reached through the hatch.
* Switches after, measured: `$007A=1 $007B=1 $01BA=1 $0242=1 $0246=0`;
  the wreck's cells `$1F62/$1F63 = (83,238)` (`airship_pos`, :44494).
  The field party is intact across `battle_event $15` — the deck-roster
  rewrite never leaks out (§1.6 verdict 5 re-confirmed on the real
  route).

### 3.5 NEW — off the wreck: the hatch, the dead wheel, and where the leg actually ends

* The wheel refusal is the airship-dead behavior: with `$007A=1` and
  `$0176=0`, facing-LEFT+A on (14,6) EventReturns before any dialog
  (`_caf532`, event_main.asm:36118-36127) — 300 frames of LEFT+A edges
  open nothing (asserted in the generator).
* The way out is the map-7 hatch: deck door (20,6) → 7 (40,11), interior
  stairs (40,18)→(50,51) and (50,62)→(10,30) (short-entrance decode),
  then the (8,36) trigger `_caf4b1` — its `$007A=1/$009D=0` branch does
  `load_map 511` ON FOOT.
* **The hatch drops the party ON the wreck's own world tile (83,238)**,
  not the parent-map cell (83,239): measured `$E0/$E2=(83,238)`,
  `$1F60/61=(83,238)`, `$11FA` on-foot.  An A tap standing there
  RE-ENTERS the wreck interior (worldMode drops) — the wreck is
  enterable scenery that cannot fly, and the generator never presses A
  on the world because of it.
* Anchor I is therefore cut exactly at the recon §2.2 table's own tile,
  **(83,238)**, standing on the dead Blackjack.

### 3.6 Anchor I stands

`vector-crash-v1` is cut: the whole H→I leg lives in
`gen_vector_crash.lua` (the gen_gate_cave_save shape), cold-Continues the
gate-cave-save-v1 battery — whose boot tile is itself a §1.7 re-entry
trap (the SavePoint trigger re-enters every frame, so the boot gate
counts alignment, never control, and leaves with a held press — the
first cold Continue of a FIELD-save battery in the tree), and saves
through the real Save UI into slot 3 on the world map at (83,238).  Exit
contract: 30 fields (26 pre-save + the 4 sram witnesses), headlined by
the dead airship (`$007A=1`, `$0246=0`, the wreck cells) and the intact
gate four.  Fail-before observed by perturbation
(`probe_v07_i_negative`: clearing `$007A` on the minted state fails the
pre-save contract by name after an unperturbed positive control held all
26); pass-after "all 30 fields hold" through the real anchored ninja
mint (`vector_crash` from the gate-cave-save-v1 battery),
frame-identical (29001) to the by-hand capture run.

## Addendum 4 — 2026-07-28, leg I→J (issue #31): the grind, the castle that opens at the dais, and the window-feasibility measurement

Source: `tools/tests/probe_banquet_stage.lua`,
`probe_banquet_interior.lua`, `probe_banquet_castle.lua`, and the
in-progress leg `tools/tests/gen_banquet_done.lua`.  Same rule as
Addenda 1-3: every claim is a log line or a `file:line` read.

**This addendum is partial** — it records the leg's route work and the
score-tier measurement.  The tier is settled (§4.6, and
`banquet-decode.md` §9); the leg generator was not driven end to end and
anchor J was NOT cut.  §4.8 states exactly what remains.

### 4.1 CORRECTION — `worldBfs`'s node cap silently failed the 117-step grind

`M.worldBfs`'s BFS node cap was **20000**, sized (its own comment) for
the 63-step Narshe→Figaro leg.  The I→J grind is ~117 steps and its
search disc overruns that cap, so `worldBfs` returned **nil** — and the
shared `worldGrind` idiom treats nil as "no plan this frame" and idles.
Measured (`probe_banquet_stage` run 2): 60000 frames of a neutral pad at
world (83,238), and **not one log line**, because no caller logged the
nil.  Raised to 60000 (`lib/ot6_field.lua`, `M.worldBfs`) and every
copy of `worldGrind` now heartbeats a NO PATH line.

### 4.2 CORRECTION — the shared `worldGrind` desyncs on long paths

The `gen_vector_doorstep` grinder consumes **one plan entry per aligned
frame**.  The party is aligned for several frames before a press latches,
so on a straight line the wasted entries agree in direction and nothing
shows — but every TURN desyncs the plan against the party's real tile and
forces a full replan.  Measured on this leg (run 4): **~139 frames per
tile**, a (73,221)↔(73,222) oscillation with the plan length jumping
86→93, and the emulator dragged to ~40fps by the per-frame BFS.

The fix is navTo's own rule, worldized: consume an entry only when the
party **lands on that entry's destination tile**, replan on drift, and
abandon a press that has provably not moved the party in 90 aligned
frames.  Measured after: **16 frames per tile**, one BFS per leg.  This
lives in the I→J probes and generator; promoting it over the shared
idiom is a Follow-up (every world leg in the tree has the same latent
bug, hidden only by shorter paths).

### 4.3 NEW — the crash-site boot tile, confirmed as a hazard the gate must dodge

`H.worldMode()` reads **true at the title screen** (`$1F64 & $3FF` is
< 3 there too), so a Continue drive gated on `worldMode` alone stops
pressing A before the save even loads — run 1 timed out that way.  The
gate that works is **brightness + position**: press A only while the
screen is lit and the party is not yet at (83,238), and disarm forever
once it is.  That is also what keeps the leg off the H→I report's first
hazard — an A tap on (83,238) re-enters the wreck interior.

### 4.4 NEW — map 250 is severed until the banquet starts, by two NPCs

The recon's §8 ledger flags 250's interior passability as
"derived from entrances + NPC coordinates only; no live census".  The
live census contradicts the natural reading of it, and the mechanism is
worth pinning because it invalidates any route census taken before the
dais:

* **From the 250 entry (23,33) the reachable set is 131 tiles** — the
  entrance hall, the corridor, and the four hall soldiers.  The dais is
  NOT in it (`navTo (23,33)->(54,17)`: no path, 20 retries).
* The west and east columns are severed at exactly **(16,30)** and
  **(30,30)** — and those two tiles carry the `$0630` "Emperor Gestahl
  waits inside" servant NPCs (`npc_prop.asm` map-250 records 11-12,
  event `_cc83c6`).  They are OBJECT blocks, not tile blocks: the flood
  also shows the four hall soldiers' own tiles punched out of their rows.
* **`_cc8490` clears `$0630` one line before it sets `$007C`**
  (`event_main.asm:97415-97418`).  The castle therefore opens exactly
  when the window starts, and the circuit runs in a component no
  pre-banquet census can see.

**The route to the dais is the stairs, not a walk** (measured):
the `{22,29}` doorway is a door tile the BFS model reads as a wall and
needs a HELD UP press (the `{14,8}` class); **(23,12) is the messenger
trigger and WEDGES `navTo`** even gated off (`$007D=0`) because it
re-enters at every rest frame, so the messenger tile and the (23,9)
stairs are crossed in ONE held press (held presses skip walk-over
triggers, Addendum 2.3); (23,9) → (54,34) is a short entrance, and from
(54,34) the dais is an ordinary 17-step `navTo`.

### 4.5 CORRECTION — the dais is a stand-on face-UP+A trigger, and `tapLever` cannot drive it

`_cc8490`'s gate is `$01B4=0 or $01B0=0 or $007C=1 → EventReturn`
(`event_main.asm:97243-97247`): `$01B0` = facing up, **`$01B4` = A
HELD**.  `M.tapLever` — the Addendum 3.2 idiom, correct for 384's
latches and toggles — releases A after 8 frames and then holds only UP,
so the gate reads A clear forever: measured, 9000 frames on the tile with
no latch.

What makes facing-up work without walking off the trigger is the
**GESTAHL NPC standing at (54,15)** (the `$062E` object, `npc_prop`
map-250 record 5, cleared by the same `_cc8490` tail at `:97414`): it
blocks the step exactly the way `gen_sabin_train`'s `upA` holds into a
wall.  The drive is therefore **stand ON (54,16), hold UP+A** with a
short periodic A release so the edge re-arms.

`M.tapLever` and `M.stepOff` were promoted from `gen_vector_crash` into
`lib/ot6_field.lua` this pass (pre-approved); this correction is the
boundary of `tapLever`'s applicability, and belongs with it.

### 4.6 MEASURED — the window budget and the SCORE TIER

The window's arithmetic (timer `$1189`, counting DOWN from 14400):

| beat | timer | cost |
|---|---|---|
| control returns after the Gestahl/Cid scene | **14302** | tail ~98 |
| throne-tower exit (53,35) → corridor (23,11) | 13817 | **393** |
| four nearest soldiers talked | 12981 | **836** (209 avg) |

Pure talk cost ≈110-130 frames; the rest is walking (~16 frames/tile,
and the region traversals from the corridor are 38-62 steps EACH WAY).

**The tier decision, settled by measurement.**  The greedy circuit driver
(`probe_banquet_greedy.lua`) runs the window to expiry and reads `var0`
at the frame `$013C` latches.  Best of six runs: **`var0` = 26, 16 of 24
soldiers**; a second tuned run wedged at 19, so 26 is a floor with real
variance, not a ceiling.  Since the messenger scores window + Q&A (44) +
challenge (5), the total is **75** — the **≥67** tier (base weapons),
clearing its threshold by 8 with a driver that still wastes frames.
≥77 would need only 2 more window points and ≥90 would need 41 of 44,
i.e. a near-perfect circuit.  Ruling and full arithmetic are recorded as
a dated correction in `banquet-decode.md` §9.

Three route facts the driver had to learn the hard way, each now a
one-line rule:

* **243 is a one-way pocket** (§4.4 below) — visit it LAST, and route
  around its (22..24,34) door row until then.  A run that wandered in
  sat for 11 835 frames.
* **Never re-plan on the transition frame.**  Right after a map change
  `fieldX`/`fieldY` still read the old map's tile, so a `bfsPath` taken
  then finds a route `navTo` cannot, and burns its whole no-path retry
  budget (~950 frames).  Five of those cost one run 4750 frames.
* **One strike per NPC.**  A soldier that does not answer promptly is
  worth 1 point and cost 4400 frames across two retries.

### 4.7 NEW — `bfsPath`/`navTo`/`chaseTalk` gained an `avoid` set

A one-way entrance sitting inside an otherwise ordinary walkable region
is a hazard the navigator had no way to express: the 243 door row is
three tiles in the middle of 250's corridor, and a plan aimed anywhere
past it crossed it by accident.  `M.bfsPath(tx, ty, blockedEdges, avoid)`
now takes a tile set it will not route THROUGH (the goal tile itself is
exempt), plumbed through `M.navTo`'s `opts.avoid` and `M.chaseTalk`'s
`opts.avoid`.

A note for whoever writes the next guard: the first version of this one
was written `local p = (into243 and AVOID243()) and nil or bfs(...)`,
which reads like a guard and is not one — `X and nil` is `nil`, which is
falsy, so the `or` branch always runs and the guard never fires.  It
took a full run and a route dump to see it.  Guards get an explicit
`if`.

### 4.8 What this leg still owes

The tier is settled; the leg is not.  Not done, and explicitly NOT
claimed: `gen_banquet_done.lua` has not been driven end to end (its
circuit section still encodes the withdrawn ≥90 route and needs
rebuilding on the greedy driver plus the 243-last rule), **anchor J is
not cut**, and its contract `banquet-done-v1` — amended to the ≥67 tier,
with the two higher rewards asserted ABSENT — has never been evaluated
against a real state.  No fail-before/pass-after exists for it.
