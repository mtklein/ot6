# Split-party dungeons: the Phoenix Cave

#275, for milestone v0.32 (#268, LOCKE) and later Kefka's Tower (v0.35):
how the driver plays a dungeon with the party split, labbed on the
Phoenix Cave. Evidence is under `build/attempts/wt/v032-splitparty/`
(`lab/` the probes and runs, `suites/` the suite, its mutants and the
sweeps). Line numbers are into `ff6/src/event/event_main.asm` unless a
file is named.

## 1. What the engine does

- **The split.** Landing the Falcon on world (117,156) (the only World of
  Ruin tile whose property word has bit `$4000` and takes a landing;
  `LandAirship`, `world/init.asm`) runs `EnterPhoenixCave` (:787): "Right.
  We're going in!", `party_menu 2`, the two groups dropped onto map 318,
  and `_cc2090` turns switching on (`$01CE`, `$1EB9` bit 6). The menu is
  the one `H.partySelect` already drives (Narshe's defense, `party_menu 3`).
  Nothing gates the cave: it is open from the first Falcon flight.
- **Who is where.** `$1850+c` low bits are each character's party; `$1A6D`
  the walked one. Each character's field object keeps its own map and tile
  (`$088D`, `$086A`/`$086D`), and `PushPartyMap` (`field/obj.asm`) copies
  them into `$1F81`/`$1FD3` inside the save block, so a save keeps where
  every party stands and a Continue puts them back.
- **Switching.** `CheckChangeParty` takes Y edge-triggered (seen up, then
  down) with control, on a tile, no event running; `ChangeParty` steps
  `$1A6D` to the next party with a shown member and reloads the map (the
  same map, or the other party's).
- **Battles** are the walking party's: its four are seated (`$3ED8`), the
  experience goes to them. The bag is one bag for every party.
- **Plates.** Most of the cave's switches are tiles whose script re-runs
  under a party standing there (every 4 frames, control one frame in
  four), and `UpdatePartyFlags` (`field/player.asm`) clears each party's
  four step bits (`$02C4-$02C7` party 1, `$02C8-$02CB` party 2,
  `$02CC-$02CF` party 3) on every step. So a "held" switch is a party
  standing on its tile; two steps that open a bridge together (`_cc2aac`,
  `_cc2af0`) need a party on each at once; and the spike fields hurt on
  every tile stepped while their plate is not held (`_cc27d7`: about 400 HP
  a member a tile).
- **Jumps.** The rock jumps are trigger tiles that read the facing
  (`$01B0-$01B3`) and carry the party 4 to 16 tiles (`_cc216f` .. `_cc23dc`):
  entered moving their way, or stood on and pressed toward the gap.

## 2. The cave's switches

| where | what | held or set by |
|---|---|---|
| 315 (35,55) | opens the west gate (32,52) (`$02A2`/`$02A6`) | a party standing on it |
| 315 (35,52) | opens the east gate (38,52) (`$02A3`/`$02A7`) | a party standing on it |
| 315 (36,40), (46,43), (39,15) | retract a spike field (`$02A4`, `$02A9`, `$02D1`) | a party standing on it |
| 313 (40,38) | raises the rocks for the jump (36,34) (`$02A8`) | set for good |
| 313 (41,27) / (46,16) | turn the passage north between 313's west and east sides (`$02AA` on / off) | set / cleared by a step |
| 315 (19,10), up and A | drains the lava (`$02D0`), shows the Red Dragon (`$069C`) | set for good |
| 315 (23,19) | turns the bridge (18-20,22-24) north-south (`$02D2`/`$02D3`) | a party standing on it |
| 315 (12,23) | raises the rocks for the jumps (4,23)-(10,23) (`$02D4`/`$02D5`, and `$02AA`) | a party standing on it |
| 315 (10,32) + (12,32) | the last bridge (10,35) (`$02D6`) | a party on each at once |
| 315 (20,46) NPC_1 | the Red Dragon, event battle 138, a game over when lost | touch |
| 313 (18,54), (6,53) | LOCKE shown, then the scene (`$0698`, `$00D7`) | step |
| 315 (37,28) | the save point | |

## 3. The order

Party 1 is TERRA, STRAGO, SABIN and CYAN; party 2 CELES, RELM, MOG and
UMARO: two of the arc's four casters (L46-49) beside two of the bench
(L36-38) in each, a medic in each (TERRA's Cure and Life, CELES's Cure).

1. Party 2 holds the south plate; party 1 goes through the west gate to the
   north plate and holds it.
2. Party 2 steps off (the west gate closes behind party 1), through the
   east gate and down to 313, raises the rocks (40,38). The Warp Stone
   (55,53) is on its way.
3. Party 1 down to 313's west side, onto (41,27): the passage north opens
   for the east side.
4. Party 2 north (313 (49,12) -> 315 (50,23) -> 313 (46,11)), clears the
   passage (46,16) for the west side, then over to 315 (23,12) and drains
   the lava.
5. Party 1 over the rocks (36,34) and the jumps to 315 (42,23), the north
   room, and the save point. **The checkpoint** (section 5).
6. Party 1 holds the bridge plate (23,19); party 2 across the bridge, the
   Red Dragon, the Dragon Horn (20,40), and the jump plate (12,23).
7. Party 1 off its plate, round by 313 (13,9) (the Ribbon, 313 (13,20)) and
   315 (6,12), across the jumps (4,23) -> (10,23), onto the step (10,32).
8. Party 2 onto the step (12,32): the last bridge; down to 313 (18,52),
   LOCKE (6,53). The scene ends with CELES and LOCKE alone on the Falcon
   (map 189): the regroup and the save are #268's.

## 4. The library

`lib/ot6_field.lua`, "split parties" and "BFS navigation":

- `H.activeParty()`, `H.partyOfChar(c)`, `H.partyRoster(p)`,
  `H.partyNumbers()`, `H.partyWhere(p)` (the leader's object: map, x, y),
  `H.partiesLine()`.
- `H.switchParty(p)`: Y held 8 frames and released 8 while the map is lit
  and loaded, done when `$1A6D` reads p and control has been seen twice in
  16 frames. Pressing only on frames that read control never switched
  from a plate (phx4); judging arrival on 8 frames of control never ended
  on one (phx4, the mutant `switch_ctl`).
- The ledger, `H.splitBegin(opts)` .. `H.splitEnd()`: every battle with the
  party that fought it (`$1A6D` at the open), its seats checked against
  that party's actors, its outcome and each member's experience; every
  care item the bag loses, charged to the walking party (read only with
  control and no menu up: the Save menu's frames read as 78 Tinctures gone,
  g1). `H.splitReport()` one line a party.
- Supply: `splitBegin` shares the bag's Tonics, Potions, Tinctures, Fenix
  Downs and Remedies between the parties by member count (`opts.shares`);
  `H.splitReserveFor(p)` is the care floor plus every other party's
  unspent share, and `fieldCare` and the after-battle care take it by
  default, read when they plan. `H.splitCare(opts)` cares for each party in
  turn.
- `H.bfsReach(sx, sy, sz, links [, tx, ty])` and `H.navLinks(tx, ty,
  links, opts)`: reach and walk over the floor plus tile events that carry
  the party, each `{ x, y, move, tx, ty [, cond] }`, cond read live.
- `H.flyTo(..., { entersMap = true })` for a landing that starts an event,
  and a fight driver for a battle in the air (Doom Gaze met the Falcon
  between Thamasa and the cave, g1).
- `H.partyWeapons()` (the absorb guard) is the walking party's: SABIN's
  Flame Shld in the party not fighting failed the Red Dragon's guard
  (phx17).
- Contracts take `party.members` with a party number and `parties = { [p]
  = { map, x, y } }`, `walking` (`lib/ot6_contract.lua`).

## 5. Checkpointing mid-dungeon

The cave has one save point, 315 (37,28), in the north room. The save
keeps both parties (section 1), so a checkpoint there is a full retry
point: `wor-phoenix-v1`, party 1 on the save point walking, party 2 beside
the lava switch it pulled (315 (20,11)), the rocks, the passage and the
lava done, the Red Dragon and LOCKE ahead. Its contract checks the eight
members' parties, where party 2 stands and which party walks
(`M.contracts["wor-phoenix-v1"]`). The legs: `gen_wor_phoenix`
(wor-thamasa-v1 -> wor-phoenix-v1) and `gen_wor_locke` (wor-phoenix-v1 ->
LOCKE joined), both on the graph.

Rules that fell out:

- A party must not be left standing on a re-running tile unless it holds
  it: the step after a save, a switch or a care would read no control. The
  legs step party 2 off the lava switch before party 1 walks.
- The save point is the only place a Tent is offered, and **the offer
  outlives the switch**: `$01BF`, which the save point's script sets, stays
  set when Y hands the field to the other party, so party 2 at the lava
  switch pitched a Tent too (g2: "[care at the save point, party 2]
  pitched a Tent"). The game takes the press; it is a vanilla quirk, used
  here and noted.
- Kefka's Tower has three parties and save points of its own; the same
  contract fields and legs apply with `[3]`.

## 6. Measured

- The legs: `gen_wor_phoenix` PASS (frame 85177) attempts=1/3 (lab/g3);
  `gen_wor_locke` from its capture PASS (frame 44359) attempts=1/3 (lab/l2).
- Per party, first half (g3): party 1 3 battles, party 2 5, all won;
  Potions 99 -> 61 at the save point (party 1 spent 21, party 2 17, a Tent
  each). Second half (l2): party 1 1 battle, party 2 4 (the Red Dragon
  among them), 7 Potions.
- The Red Dragon (L67, 30,000 HP, weak to ice and water) fell to party 2
  in 4,783 to 6,065 ticks with nobody dead (l1, phx17).
- The bench members are under the cave: L36-38 against monsters at L49
  (Chaos Drgn, Aquila). The first runs lost members in random fights
  (g1: party 1 "TERRA +0, CYAN +0" in group 336, three Fenix Downs and a
  Megalixir; party 2 at "UMARO 1/2123" after group 339).
- The sweeps under varied luck are in section 7.

## 7. Sweeps

(filled from `suites/` when the runs are in)
