# Save points — engine reference

## 1. How a vanilla save point works

A save point is **two data records plus one shared event script**. There is
no per-tile map flag; the tilemap is untouched.

### The trigger

`make_event_trigger {x, y}, SavePoint` in the map's block of
`ff6/src/event/event_trigger.asm`. The macro emits **5 bytes** — 2 bytes
{x,y}, 3-byte offset of the event script
(`ff6/src/event/event_trigger.asm:7-10`). The per-map blocks
(`EventTrigger::_N`) are indexed by an auto-generated pointer table at
`c4/0000` (`event_trigger.asm:19-22`), so inserting a record into a map's
block is safe at assembly time — every downstream pointer recomputes.

### The `SavePoint` event script (shared by all 38 save points in the game)

`ff6/src/event/event_main.asm:100749-100784`:

- gated on `$01B5=0` — the once-per-tile latch, so it fires once per arrival
  (`:100750`; `$01B5` = `$1EB6` bit 5, decoded at
  `vector-route-recon.md` §7);
- plays sfx 209 and a blue flash, sets **`$01BF=1`** (`:100752-100755`);
- the first save point the player ever touches (`$0133=0`) also shows the
  "eerie glow" info dialog `$000A`/`$06D4` (`:100759-100773`).

`$01BF` is `$1EB7` bit 7 — the **save-enable bit**. It is consumed, not
stored: `OpenMainMenu` copies it into the menu-flags byte `$0201`
(`ff6/src/field/menu.asm:229-235`), the Save command tests that flag
(`ff6/src/menu/field_menu.asm:3641-3643`), and Tent/Sleeping Bag are gated
on the same bit 7 of `$0201` (`ff6/src/menu/item.asm:579-582`, the
white/gray item-text gate; the field-side tent handler is the `cmp #$02`
branch after `OpenMenu`, `field/menu.asm:236-240`). The bit is cleared again on every orthogonal step
(`ff6/src/field/player.asm:532-534`); the diagonal-step gap in that clear is
known and below-the-bar (`docs/research/vanilla-destructive-bugs.md` §9).

### The sparkle

**Append the record at the end of the map's block, never insert it.** Event
scripts address NPCs as {map, index-within-block}, so a record added ahead of
an existing NPC renumbers everything after it.

A separate NPC record in `ff6/src/event/npc_prop.asm` at the same tile —
**9 bytes** (record layout `npc_prop.asm:137-176`). The two in-band examples
are identical in shape (`npc_prop.asm`, maps 270 and 272 blocks):

```
make_npc {25, 10}, $0632
        set_npc_no_react
        set_npc_anim FOUR_FRAMES, SPECIAL
        set_npc_speed NORMAL
        set_npc_gfx SAVE_POINT, RAINBOW
        set_npc_sprite_priority HIGH
        end_npc
```

Switch `$0632` is the standing "save sparkle visible" switch: **1 at new
game** (`ff6/src/field/init_npc_switch.dat` byte 6 bit 2), used by 30
save-point NPCs, and **never written by any event** (`switch $0632=` appears
nowhere in `event_main.asm`). A new save point can reuse it and needs no
switch of its own. Map 240's save point instead uses `$06AE`, which the
escape scene sets (`event_main.asm:96688`) — the pattern for a save point
that must not exist before a story beat.

### The world map

Saving is legal anywhere on the world map (dialog `$06D4`,
`event_main.asm:100776-100780`, and `vanilla-destructive-bugs.md` §9).

### Cost per placement

Per save point: **5 bytes** of `event_triggers` + **9 bytes** of `npc_prop`,
zero switches, zero tilemap edits, zero code.

Both segments are `fixed_block`s at hard addresses (`event_triggers` at
`C40000` size `$1A10`, `npc_prop` abutting at `C41A10` size `$50B0`,
`ff6/rom/ff6-en.map:200-201`; `fixed_block` errors at assembly if overrun,
`ff6/include/macros.inc:409-431`).

Any such edit is a ROM change, so it invalidates every savestate in the
frontier (`leg-fixtures.md`, "The problem"); battery anchors survive.
