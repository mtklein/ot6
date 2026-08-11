# World-map navigation — engine notes

Ground-truth for `H.worldNavTo` (the overworld analog of the field
`navTo` in `tools/tests/lib/ot6_field.lua`). The world map is a separate
Mode-7 engine (`ff6/src/world/`) from the field engine, but on-foot
navigation is simpler. Pins below are from the disassembly and
`rom/ff6-en.dbg`.

## Mode detection

Top-level dispatch: `ff6/src/field/reset.asm:64-77` masks `$1F64` with
**`#$03ff`** and compares `< 3`: `0` (World of Balance), `1` (World of
Ruin), `2` (Serpent Trench); `>= 3` is a field map. So **on the world
map iff `(peek16($1F64) & 0x3FF) < 3`**. Never use a raw compare: the
high byte can carry flag bits from whatever record loaded the map.
Measured: after the Narshe south-gate exit `$1F64` reads **`$2000`**
(the parent-map record's facing bits land in bits 12-13); Figaro's
world-trigger `load_map 55 ... SET_PARENT` stores `$0037`
(that path consumes bit9 rather than storing it). The flag bits
are loader-dependent, so compares stay masked. The
world-id for table lookups masks the low byte only
(`GetWorldTileProp`, `move.asm:@21d7`, `and #$00ff`).

On-foot vs vehicle is `$11FA & 3` (`world/init.asm:95-102`; `0` = on
foot), but `world/init.asm:93-94` forces the airship from `$11F3`
first, so check both. Measured on the Sabin-route spawn: `$11FA=0`,
`$11F3=0`, `$20=$03` (world type byte; the main loop only compares it
against `#$04` = serpent trench).

## Party position

World map is 256x256 tiles, one tile-type byte per cell, in WRAM at
`$7F0000` (index `= (tileY & 0xFF)*256 + (tileX & 0xFF)`). The world
module keeps DP=$0000 (`world_start.asm` never relocates it; `PushDP`
only snapshots page 0 into $0A00 around battles, `move.asm:@90b2`),
so these are absolute zero-page addresses:

| RAM | meaning |
|---|---|
| `$E0` / `$E2` | integer tile X / Y (the high bytes of the 16-bit position words at `$DF`/`$E1`; word = tile*256 + fraction) |
| `$DF` / `$E1` (low bytes) | sub-tile fraction 0-255; both zero <=> at rest |
| `$E3` / `$E5` | 16-bit velocity (+-$10/frame while stepping) |
| `$1F60` / `$1F61` | persistent saved tile X / Y (what a save stores) |
| `$F6` / `$1F68` | facing (0=up 1=right 2=down 3=left) |

Tile-aligned at rest iff `peek8($DF)==0 and peek8($E1)==0`. The tile
byte flips at step completion when moving down/right, but on the first
frame when moving up/left (the word borrows through its high byte);
measured in `probe_world` step traces. Position samples therefore gate
on alignment, the same rule the field uses. Init seeds the tile bytes
from `$1F60/$1F61` and inherits the fraction bytes (`world/init.asm`
never zeroes `$DF`/`$E1`); measured after every observed transition
(Narshe exit, post-battle reload), the party arrives aligned.

## Passability (on foot)

There is one rule, and no directional exits, z-levels, bridges, or
object map. A step onto a tile is legal iff **bit 4 (`0x0010`) of the
destination tile's 16-bit property word is clear**. `GetPlayerInput`
tests this per held direction (`move.asm:@1ead-@1ff3`);
`GetWorldTileProp` at `move.asm:1366-1393`.

Property table is ROM: `WorldTileProp = $EE9B14` (WoB), `+512` (WoR),
256 words per world (`world/tile_prop.asm:4,41`); rom file offset
`$2E9B14`. Read once and cache; `H.worldTileProp` does.

Verified live at the Narshe spawn (84,34): predictions from this rule
matched real movement in all tried directions, including the refused
step east into the mountains (prop `$0057`, bit4 set).

Other bits of the same word (informational): bit 5 (`0x0020`) =
forest (legal, sets the hidden flag); bit 6 (`0x0040`) = random
battles enabled here; property high byte selects battle BG/zone.
The Narshe gate strip (84,33) is prop `$0007`: passable and
battle-free, so pacing there produces no encounters (measured; this is
why `probe_world` run 1 saw no encounters).

## Movement mechanics

- Cardinal only (up=-Y down=+Y left=-X right=+X); no player diagonals.
- Held-direction read via the shared `UpdateCtrlField_ext`
  (`world_start.asm:407`), same `$04` bit layout as the field
  (Right `0x0100`, Left `0x0200`, Down `0x0400`, Up `0x0800`). Existing
  pad injection drives world movement unchanged (measured).
- 16 sub-units/frame, tile = 256 units => 16 frames/tile, same cadence
  as the field (measured: fraction 16,32,...,240,0).
- **Movement is latched to the step.** `MovePlayer` gates its whole
  body, including the `jsr GetPlayerInput`, on `$DF == 0 && $E1 == 0`
  (`world/move.asm:834-841`); once velocity is set the step runs to the
  next boundary with no input read meanwhile. Measured: a 4-frame tap
  carries the party the full tile, velocity `$10` all 16 frames, then
  zeroes on the next aligned frame with no button held. A mid-tile
  release therefore loses no movement; `H.worldNavTo` holds the
  planned direction whenever aligned and the latch completes the step.

## Encounters

`MovePlayer` gates on `$1EB9` bit5 (the battles-disabled event switch,
`move.asm:870`) and the tile's battle-enable bit, then
`jsl CheckBattleWorld_ext` (`move.asm:878-883`) once per tile entry
(`$E8` bit3 latch). `CheckBattleWorld` (`field/battle.asm:97-214`)
uses the same `$1F6E` danger counter and the same OT6
`Ot6DangerStep`/`Ot6MarkRandom` hooks as the field's `CheckBattleSub`.

The roll: zone rate (2-bit, 3 = battle-free zone) picks a 16-bit
per-step increment from `WorldBattleRateTbl` (`$C0C2A6`; row selected
by `$11DF & 3` — moogle charm / charm bangle; rows 2/3 are all zeros),
OT6 scales it 0.5x (`Ot6DangerMulW=$0008`), it accrues into the 16-bit
`$1F6E`, and the encounter fires iff `rand8 < danger>>8`
(`battle.asm:170-176`). Measured on the WoB plains south of Narshe:
+$30/step, first encounter after a handful of steps at danger ~$1100.

**On-foot random battles reload the world.** `move.asm:916-921`
snapshots position/facing into `$1F60/$1F61/$1F68` first (from the
$0A00 page-0 snapshot), sets the reload bit in `$E8`, and
`world_start.asm:465-482` reruns `ReloadMap` after the battle.
Measured end to end (`probe_world3`): writing the monster-death flag
clears the fight, then ~95 frames of fade + re-init, and the party is
back on the same tile, same facing, aligned, danger counter zeroed,
`$E7=$00 $E8=$00 $19=$00`.
A plan in flight stays valid because the position is unchanged, but
`H.worldNavTo` re-plans anyway (BFS is cheap) and waits for full
screen brightness before the next step.

Zone index (`battle.asm:122-136`): `zone = (tileY & 0xE0) |
((tileX >> 3) & 0x1C)`, i.e. 32x32-tile cells, read from the
post-snapshot `$1F60/$1F61`, plus a per-BG group offset, indexing
`WorldBattleGroup = $CF5400` (512 B) and `WorldBattleRate = $CF5800`
(128 B). Narshe/Figaro corridor zones measured: rate byte `$45`
(rate 1) north half, `$00` (rate 0 -> increment $C0 vanilla) south.

## Warp / teleport levers

- World -> field (enter a location): two mechanisms.
  - `CheckEntrance` (`move.asm:1246-1303`) matches the party tile
    against the world's short-entrance records (same
    `ShortEntrancePtrs = $DFBF02` table the field uses, indexed by
    world id) and sets `$19` (fade) + the destination; e.g. WoB
    (84,33) -> map 20 (38,61) is Narshe's entrance.
  - `CheckEvent` (`move.asm:1309-1357`) matches world event triggers
    (`EventTriggerPtrs = $C40000`, map 0 list) and runs a world event
    script (`$E7 |= $41`); **Figaro Castle is one of these, not an
    entrance**: tiles (64,76)/(65,76), event `_ca5eb5`
    (event_main.asm:14184), gated `if_switch $010B=0, WorldReturn`,
    body `load_map 55, {28,42}, UP, {Z_UPPER, SHOW_TITLE, SET_PARENT,
    STARTUP_EVENT}`. $010B is set by the game-start event
    (event_main.asm:14157), so the gate is open from the beginning.
    (The castle's second tile pair (30,48)/(31,48) runs the same
    body gated on $010C.)
- Field -> world (leave a town map): a long/short entrance whose Map
  field is `$1FF` loads the PARENT map: `RestoreParentMap`
  (`field/entrance.asm:246-258`) inverts the saved facing, steps one
  tile past the saved position, and reloads it. Narshe's whole south
  edge (map 20, y=62, x=0..43) is one such long entrance; the parent
  was seeded by `set_parent_map 0, {84,33}, UP`
  (event_main.asm:14159), so the exit spawns at WoB **(84,34) facing
  DOWN**, as measured.
- Land on the world map at a chosen tile: set `$1F64=0`,
  `$1F60`=tileX, `$1F61`=tileY, facing `$1F68`; `InitWorld` seeds the
  live position from them (ReloadMap tail, `world/init.asm`).

## Concrete ids and tiles

1. Narshe exterior = map 20; world after its exit: `$1F64=$2000` (WoB).
   Figaro complex = map 55 via the world trigger (raw `$1F64=$0037` — that
   loader consumes the SET_PARENT bit); interior wings map 59 etc.; map 54
   has no entrances (submerge-ride only). South Figaro = 75; Mt. Kolts = 95
   (short-entrance table).
2. Figaro world tiles: (64,76)/(65,76), EVENT trigger (not entrance),
   gate switch $010B=1 from game start.
3. Mt. Kolts world tile: (102,100) short entrance -> map 95 (14,35).
5. `$20`=$03 on the WoB on foot; vehicle = `$11FA&3`==0 plus
   `$11F3`==0 (airship force-check).
7. Narshe -> world exit spawn: (84,34) facing DOWN, aligned, on foot.

## Symbol crib

- `WorldMain` = `$EE0251` (`world/world_start.asm:259`, main loop
  398-518, `MovePlayer` call :408).
- `MovePlayer` = `$EE1D0E` (`world/move.asm:809`).
- `GetPlayerInput` `move.asm:992-1128`; `GetWorldTileProp`
  `move.asm:1366-1393`.
- `WorldTileProp` `$EE9B14`/`+512` (`world/tile_prop.asm:4,41`); rom
  file `$2E9B14`.
- Tilemap WRAM `$7F0000` (source `world/world_1_tilemap.dat`, 65536 B).
- Position init/reload `world/init.asm` (ReloadMap tail seeds
  `$E0/$E2` from `$1F60/61`); on-foot select :95-102; save-back
  `world_start.asm:429-434`.
- `CheckBattleWorld` `field/battle.asm:97-214`; OT6 hook `:168`; zone
  `:122-136`. `WorldBattleGroup` `$CF5400`, `WorldBattleRate`
  `$CF5800` (file `$0F5400`/`$0F5800`), `WorldBattleRateTbl`
  `$C0C2A6`, `BattleBGRateTbl` `$C0C296`.
- `CheckEntrance` `move.asm:1246-1303`; `ShortEntrancePtrs` `$DFBB00`,
  records `$DFBF02` (6 B: SrcX,SrcY,MapLo,Flags,DestX,DestY; map bit8
  = flags bit0). `LongEntrancePtrs` `$EDF480` (7 B records, Length
  bit7 = vertical run). `CheckEvent` `move.asm:1309-1357`;
  `EventTriggerPtrs` `$C40000`. `ExitWorld` `world/init.asm:1691`;
  `$19` fade trigger `world_start.asm:500`.
