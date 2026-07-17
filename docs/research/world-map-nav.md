# World-map navigation — engine notes

Ground-truth for building `H.worldNavTo` (the overworld analog of the
field `navTo` in `tools/tests/lib/ot6.lua`). The world map is a
separate Mode-7 engine (`ff6/src/world/`) from the field engine, but
on-foot navigation is simpler. Pins below are from the disassembly and
`rom/ff6-en.dbg`. Items marked LIVE-PROBE need confirmation in the
emulator when the build lands.

## Mode detection

Top-level dispatch: `ff6/src/field/reset.asm:64-77`. Read `$1F64`:
`peek16($1F64) & 0x1FF` is `0` (World of Balance), `1` (World of
Ruin), or `2` (Serpent Trench) when on the world map, and `>= 3` (a
field/sub map id) when on a field map. So **on the world map iff
`(mapId & 0x1FF) < 3`**. `H.mapId()` already reads `$1F64`.

On-foot vs vehicle is `$11FA & 3` at `world/init.asm:95-102`
(`0` = on foot). The Sabin route is always on foot.

## Party position

World map is 256x256 tiles, one tile-type byte per cell, in WRAM at
`$7F0000` (index `= (tileY & 0xFF)*256 + (tileX & 0xFF)`).

| RAM | meaning |
|---|---|
| `$E0` / `$E2` | integer tile X / Y (all trigger/collision code reads these) |
| `$DF` / `$E1` (low byte of the 16-bit `$DF`/`$E1`) | sub-tile fraction 0-255 |
| `$1F60` / `$1F61` | persistent saved tile X / Y (what a save stores) |
| `$F6` / `$1F68` | facing (0=up 1=right 2=down 3=left, as field `$0743`) |

Tile-aligned at rest iff `peek8($DF)==0 and peek8($E1)==0`. A freshly
loaded party is aligned (init seeds from `$1F60/$1F61`,
`world/init.asm:758-769`).

## Passability (on foot)

One rule, no directional exits / z-levels / bridges / object map. A
tile is passable iff **bit 4 (`0x0010`) of its 16-bit property word is
clear**. `GetWorldTileProp` at `move.asm:1366-1393`, consumed at
`move.asm:1012-1016`.

Property table is ROM: `WorldTileProp = $EE9B14` (WoB), `$EE9D14`
(WoR), 256 words per world (`world/tile_prop.asm:4,41`). Read once and
cache.

```lua
local WORLD_TILEPROP = 0xEE9B14
local function worldPassable(tx, ty)
  local world = H.peek16(0x1F64) & 0x1FF                 -- 0=WoB 1=WoR
  local ttype = H.peek8(0x7F0000 + (ty&0xFF)*256 + (tx&0xFF))
  local prop  = H.peekRom16(WORLD_TILEPROP + world*512 + ttype*2)
  return (prop & 0x0010) == 0
end
```

Other bits of the same word (informational): bit 5 (`0x0020`) =
forest (legal, sets the hidden flag); low-byte bit 6 (`0x0040`) =
random battles enabled here; property high byte selects battle
BG/zone.

## Movement mechanics

- Cardinal only (up=-Y down=+Y left=-X right=+X); no player diagonals.
- Held-direction read via the shared `UpdateCtrlField_ext`
  (`world_start.asm:407`), same `$04` bit layout as the field
  (Right `0x0100`, Left `0x0200`, Down `0x0400`, Up `0x0800`). Existing
  pad injection drives world movement unchanged.
- 16 sub-units/frame, tile = 256 units => 16 frames/tile, same cadence
  as the field.
- **Movement is smooth, not tile-locked.** `GetPlayerInput` re-zeroes
  velocity each frame and only re-sets it while a direction is held;
  there is no step-completion latch. Releasing mid-tile strands the
  party at a non-zero fraction. Hitting a wall zeroes velocity exactly
  at the tile boundary (clean), so only a voluntary mid-transit release
  strands you.
  - Executor consequence: hold each straight run for a whole number of
    16-frame ticks (N tiles = N*16 frames) and verify `$DF/$E1` low
    bytes are 0 before releasing. Do NOT reuse the field walker's
    "release the instant the tile coord flips" idiom — that flips at
    fraction rollover and would strand on release latency. LIVE-PROBE:
    confirm mid-tile release strands (code strongly implies yes).

## Encounters

`MovePlayer` gates on the tile's battle-enable bit, then
`jsl CheckBattleWorld_ext` (`move.asm:878-883`). `CheckBattleWorld`
(`field/battle.asm:97-214`) uses the SAME `$1F6E` danger counter and
the SAME OT6 `Ot6DangerStep`/`Ot6MarkRandom` hooks as the field's
`CheckBattleSub`, so the encounter-rate scale and the random-vs-event
marker already cover the world map. On-foot random battles do not
reload the world: after the fight `WorldMain` resumes with position
untouched. `H.clearBattle` and the kill-bit idiom (`$3AA8` bit0 ->
`$3EEC` bit7) work unchanged (battle module is engine-agnostic).

Zone index (`battle.asm:122-136`):
`zone = (tileY & 0xE0) | ((tileX >> 3) & 0x1C)`, plus a per-BG group
offset, indexing `WorldBattleGroup = $CF5400` (512 B) and
`WorldBattleRate = $CF5800` (128 B). Group -> concrete formation needs
the formation tables or a LIVE-PROBE.

## Warp / teleport levers

- World -> field (enter a location): `CheckEntrance`
  (`move.asm:1246-1303`) matches the party tile against the world
  short-entrance records and sets `$19` (fade/exit trigger);
  `ExitWorld` (`world/init.asm:1691`) sets `$1F64` to the destination
  field-map id and returns to `FieldMain`. Preferred: step onto the
  real entrance tile (Whelk-style) for byte-exact determinism.
- Land on the world map at a chosen tile: set `$1F64=0`,
  `$1F60`=tileX, `$1F61`=tileY, facing `$1F68`; `InitWorld` seeds the
  live position from them.
- Preferred fixture lever overall: save injection (the proven OT6
  flow) — a save made on the world map stores `$1F64`(=0) and
  `$1F60/$1F61` and reproduces a world spawn deterministically.

## Sabin route breakdown (Narshe -> Vargas)

Two short world-nav legs (both WoB, on foot); the rest is field-nav
plus one scripted-event stretch, and Vargas is a field trigger.

| leg | model |
|---|---|
| Narshe interior/exterior to the map edge | field-nav (existing `navTo`); a field short-entrance with destination map 0 auto-loads the world |
| Narshe world spawn -> Figaro Castle approach | **world-nav** (new) |
| step onto Figaro entrance tile -> interior | transition (short-entrance, step-on) |
| Figaro: Edgar join, King dialogue, submerge | scripted event (`advanceStory`); done-predicate is LIVE-PROBE |
| Figaro emerges -> South Figaro / world | world-nav then field-nav |
| world -> Mt. Kolts entrance | **world-nav** (short) + transition |
| Mt. Kolts interior -> Vargas trigger | field-nav + event trigger; Vargas is a field trigger tile (like Whelk (42,5)), formation passed via `opts.spare` |

## What ports from the field navTo vs is new

Ports as-is: BFS structure, target thunks, re-plan-on-deviation,
`opts.arrive`/`maxFrames`; encounter handling (`clearBattle`, kill-bit,
`opts.spare`, dialog edge-tap, 3-frame debounce); pad injection;
facing semantics.

New/rebuilt: position source (`$E0/$E2` tile, `$DF/$E1` alignment);
1-bit `worldCanStep`; the hold-whole-ticks executor control law; the
world control-gate predicate (`$1F64<3`, no active world event `$E7`
bit0, not fading `$19==0`, menu-not-opening) — the field
`$087C`/`$1EB9`/`$E5-E7` idioms are field-only; and a route driver
that detects `$1F64` crossing 3 to hand off between field and world
navigation at each transition.

## Live-probe checklist (do these when the build lands)

1. Concrete map ids: Narshe exterior, Figaro Castle interior, South
   Figaro, Mt. Kolts (parse `short_entrance.dat` at `$DFBF02`, or
   read `$1F64` live after each transition).
2. Figaro Castle world tile (SrcX/SrcY of the WoB short-entrance whose
   Map = Figaro interior).
3. Mt. Kolts world tile; Vargas Kolts event-trigger tile + formation
   id (like the Whelk analysis).
4. Confirm mid-tile release strands the party (executor control law).
5. `$20` live value on foot; any extra on-foot-vs-vehicle flag.
6. Figaro-interior event done-predicate for `advanceStory`.
7. Narshe -> world exit spawn tile on the WoB.

## Symbol crib

- `WorldMain` = `$EE0251` (`world/world_start.asm:259`, main loop
  398-518, `MovePlayer` call :408).
- `MovePlayer` = `$EE1D0E` (`world/move.asm:809`).
- `GetPlayerInput` `move.asm:992-1128`; `GetWorldTileProp`
  `move.asm:1366-1393`.
- `WorldTileProp` `$EE9B14`/`$EE9D14` (`world/tile_prop.asm:4,41`).
- Tilemap WRAM `$7F0000` (source `world/world_1_tilemap.dat`, 65536 B).
- Position init `world/init.asm:758-769`; on-foot select :95-102;
  save-back `world_start.asm:429-434`.
- `CheckBattleWorld` `field/battle.asm:97-214`; OT6 hook `:168`; zone
  `:122-136`. `WorldBattleGroup` `$CF5400`, `WorldBattleRate` `$CF5800`.
- `CheckEntrance` `move.asm:1246-1303`; `ShortEntrance` data `$DFBF02`
  (6 B: SrcX,SrcY,Map,Flags,DestX,DestY). `CheckEvent`
  `move.asm:1309-1357`; `EventTriggerPtrs` `$C40000`. `ExitWorld`
  `world/init.asm:1691`; `$19` fade trigger `world_start.asm:500`.
</content>
