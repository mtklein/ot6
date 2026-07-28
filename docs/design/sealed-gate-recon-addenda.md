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
