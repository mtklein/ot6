# Save points — the Vector / Magitek Factory band (issue #10, v0.6 slice)

Status: **proposal**, 2026-07-27. READ-ONLY analysis; nothing here is
implemented. Feeds #10 (player-facing save cadence) and #25 (leg-fixture
anchor boundaries, `leg-fixtures.md`).

Method: static analysis of the vendored disassembly plus the repo's route
docs, chiefly `vector-route-recon.md` (whose §11 corrections were measured
live on the 2026-07-26 minting pass). The Vector-band savestates are not
minted in this tree, so nothing below was verified dynamically in this pass;
distances marked *(offline BFS)* come from a Python port of
`tools/tests/lib/ot6_field.lua:125-237`'s step model run against the map data
files, calibrated below. Every claim cites source or is labelled
**unverified**.

---

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
game** (`ff6/src/field/init_npc_switch.dat` byte 6 bit 2 — read directly;
bit-order cross-checked against the recon's known values `$062B`/`$0646`/
`$0649`), used by 30 save-point NPCs, and **never written by any event**
(`switch $0632=` appears nowhere in `event_main.asm`). A new save point can
reuse it and needs no switch of its own. Map 240's save point instead uses
`$06AE`, which the escape scene sets (`event_main.asm:96688`) — the pattern
for a save point that must not exist before a story beat.

### The world map

Saving is legal anywhere on the world map (dialog `$06D4`,
`event_main.asm:100776-100780`, and `vanilla-destructive-bugs.md:763`). This
matters below: both ends of the band terminate on the world map, so neither
end needs authored machinery.

### Cost per placement, and the ROM budget — measured

Per save point: **5 bytes** of `event_triggers` + **9 bytes** of `npc_prop`,
zero switches, zero tilemap edits, zero code.

Both segments are `fixed_block`s at hard addresses (`event_triggers` at
`C40000` size `$1A10`, `npc_prop` abutting at `C41A10` size `$50B0`,
`ff6/rom/ff6-en.map:200-201`; `fixed_block` errors at assembly if overrun,
`ff6/include/macros.inc:409-431`). Trailing `$FF` padding measured in
`build/ot6.sfc` (2026-07-27):

- `event_triggers`: **18 bytes free → at most 3 new triggers game-wide**
  without segment surgery. (A trigger's last byte is the high byte of a
  ≤`$02E5FF` offset, never `$FF`, so the pad count is exact.)
- `npc_prop`: **85 bytes free → 9 new NPC records.** (An NPC record's last
  byte could in principle be `$FF`, so treat 85 as an upper bound;
  **unverified** beyond the trailing-run measurement.)

This proposal spends **1 of the 3** trigger slots. The deferred v0.5 band in
#10 wants roughly five more, so segment relocation (moving the `npc_prop`
boundary or the whole bank-C4 layout) is on the horizon — flagged in
Follow-ups, not attempted here.

Two more costs, named:

- **Any of these edits is a ROM change**, so it invalidates every savestate
  in the frontier (`leg-fixtures.md:9-11`). Land save points in the same
  change window as other pending ROM work, ideally the #25 anchor cut, so
  the re-mint is paid once.
- Save-frequency increases are safe now that #18 fixed the slot-eating save
  bug (`docs/HANDOFF.md:86-87`); the checksum-`$0000` companion bug is
  #13's open release-gate item (`vanilla-destructive-bugs.md`, bottom line)
  and is worth closing before a release that advertises more saving.

---

## 2. Inventory — existing save opportunities in the band

Route order, post-Opera anchor → v0.6 stop line. Trigger citations are the
map blocks in `event_trigger.asm`; the route structure is
`vector-route-recon.md` (§1-§6, as corrected by §11).

| # | where | what | evidence |
|---|---|---|---|
| S0 | world map, WoB | save anywhere; the post-Opera anchor itself is a world battery save at (137,203) | dlg `$06D4`; `Makefile:310`, `tools/tests/gen_post_opera_anchor.lua` |
| S1 | map 270 (25,10) | save room off the Ifrit/Shiva alcove, door `264 (3,5) → 270 (25,14)` | `event_trigger.asm:1206`; sparkle `npc_prop.asm` map-270 block; route `vector-route-recon.md:254` |
| S2 | map 272 (3,55) | minecart boarding platform | `event_trigger.asm:1211`; sparkle in map-272 block |
| S3 | map 240 (58,7) | escape-Vector copy; sparkle revealed by `$06AE=1` at the escape control point | `event_trigger.asm:1062`; `npc_prop.asm` map-240 block; `event_main.asm:96684-96690` |
| S4 | world map, post-return | after Terra's return the party is on the Blackjack (map 6, control at `event_main.asm:25669`); one flight later the world map is saveable again | `vector-route-recon.md` §6d |

No other `SavePoint` trigger exists on maps 240, 242, 253, 262-264, 266,
269-274 (their `EventTrigger::_N` blocks, read in full), and no inn or other
save-legal state exists inside the facility.

**The band is effectively one-way between S0 and S1.** Once inside the
factory, walking back out to the world map means re-crossing Vector's guard
row (`_cc93dc` → forced `battle 29` + teleport, `event_trigger.asm:1073-1075`,
`event_main.asm:99473`) and the 262→263→264 stitching is scripted chutes and
conveyors (`vector-route-recon.md` §8 hazard 3), one-way in practice. Treat
S0 as unreachable again until the escape.

---

## 3. Retry distances, fight by fight

Static measurements. *(offline BFS)* = the ported `ot6_field.lua` step model
run on `sub_tilemap/magitek_factory_other_bg1.dat` /
`vector_ext_bg1.dat` with tile props `magitek_lab_1/2.dat`, `vector.dat`
(map_prop bytes 4 and 13-14, extraction cross-checked against the recon's
map-323 = layout-13 = Albrook result). The model omits live NPC occupancy
except where noted, so distances are lower bounds; the same model matched
the 2026-07-26 live measurements everywhere it was checked (270 door→save
4 steps; 264 landing→save-room door 9 steps ≈ recon's "9 steps";
273 entry→024 13-14 steps).

| fight | nearest prior save | static retry distance | scenes replayed on retry |
|---|---|---|---|
| **Ifrit / Shiva** (battle 70, map 264 alcove) | S1, map 270 | 4 steps + door + ~8 steps *(offline BFS)*; alcove tiles are encounter-enabled (map 264 rate `$0040`, Flan — `break-band-vector.md:94`) | none |
| **Number 024** (battle 72, map 273 (25,51)) | S1, map 270 | ~119 steps + 4 map transitions: 270→264 (4+9), 264→269 door, 269 (44,54)→(42,12) 60, 271 (31,27)→(3,27) 38, 273 (30,60)→(25,52) 13 *(offline BFS + recon table §2)*; crosses **three** encounter maps (269/271/273, rate `$0070`) plus the alcove | none, but the Ifrit/Shiva magicite hand-off must not be redone (`$0060=1` latches; post-fight branch `_cc7986`, `event_main.asm:95316`) |
| **minecart + Number 128** (battles 41, 144×2, 73) | S2, map 272 | save → tile beside Cid (9,51): 8-9 steps *(offline BFS)*; then the ride is a `cutscene TRAIN` — ~6400 frames with 5 forced trash fights before Number 128, **measured** (`vector-route-recon.md` §11 probe 4) | the ride itself; it cannot be split (see §4.3) |
| **Cranes** (battle 71, fought on map 6) | S3, map 240 | save (58,7) → reunion trigger (52,39/40/41): **42 steps** *(offline BFS; map-240 NPC occupancy not modelled — unverified)* on an encounter map (rate `$0070`, `break-band-vector.md:98`); the trigger then auto-plays the whole Setzer reunion into `battle 71` with no further control (`event_main.asm:96723-96997`, `_cb3ff1:47070`) | the reunion + Blackjack scene, every retry |
| **post-escape / Terra-return settle** | S4, world map | n/a — the settle point *is* a save opportunity (one flight from the map-6 control point) | n/a |

The plain reading: vanilla already put a save point directly in front of
Ifrit/Shiva, directly behind the minecart, and on the escape map. The one
hole in the band is **Number 024**, whose retry walk is ~120 steps through
three encounter maps. The one *structural* gap is the S0→S1 stretch (the
whole approach: Vector sneak, the 262 door puzzles, the Kefka drain scene,
two chutes), which contains no save at all — but it also contains no fight
that can be lost, only attrition trash.

---

## 4. Proposals, per #10's v0.6 list

Summary: **one new save point** (map 273, before Number 024). Everything
else on the list is already served by vanilla machinery, and the reasons are
documented per #10's acceptance criteria. One optional addition (factory
entrance) is described with its trade-off and deliberately not recommended.

### 4.1 Before Ifrit / Shiva — NO new save point

Map 270's save room already sits 9 steps from the chute landing and is
reachable **before** the fight — Ifrit's NPC at (3,8) does not block the
(3,5) door (measured live, `vector-route-recon.md` §11 "the alcove is only
half sealed"). Adding anything closer would put two save opportunities
within a dozen steps. Principle served: retry cost is already ~15 steps with
no scene replay. **Action: document only.**

### 4.2 Before Number 024 — ADD, map 273, tile ≈(26,53)

The one real gap (~120-step retry through three encounter maps, §3).

- **Map**: 273 (`EventTrigger::_273` is currently empty;
  `NPCProp::_273` holds only NUMBER_024 — both read directly).
- **Tile**: **(26,53)** — inside the small antechamber in front of 024,
  one tile south of the walk-in line, 2 steps from the (25,52) contact
  tile. Offline BFS shows the chamber pocket x 23-27 × y 52-53 walkable at
  every z seed; **exact tile unverified live** — implementation must confirm
  with a `canStep`/`bfsPath` dump and may slide within that pocket.
  Alternate: (24,53), same properties.
- **Mechanism**: `make_event_trigger {26, 53}, SavePoint` in
  `EventTrigger::_273`, plus the standard 9-byte sparkle NPC on switch
  `$0632` in `NPCProp::_273` (the §1 template, verbatim from map 270).
- **Why there**: immediately before a major boss (principle 1); leaves the
  269/271 traversal as real attrition (principle 4 — a save at the 273
  *entrance* would too, but the chamber tile also covers deaths to 273's own
  Gobbler/Rhinox trash and is more player-legible); the room has no
  transient event state — 024's fight and cleanup latch on `$0649` and the
  battle itself (`event_main.asm:95385-95395`), nothing time- or
  choreography-dependent.
- **Hazard check**: the player reaches 273 through one-way scripted
  transitions, so a save-reset-load here must reconstruct: party of four
  (LOCKE/CELES/SABIN/EDGAR per `wob-route.md` measured table), both magicite
  owned (`$1A69` give_genju bits), `$0646=0`, `$0649=1`, and the door back
  toward 271 functional. Nothing suggests otherwise, but per #10's
  acceptance criteria this **needs explicit save/reset/load/progress
  verification at implementation** — not resolved here.

### 4.3 Around the minecart and Number 128 — NO new save point

#10 asks which side of the sequence the retry cost argues for. The answer is
**both sides already exist in vanilla**: S2 (272, 8 steps before boarding)
and S3 (240, on the escape map after). A mid-sequence save is impossible,
not merely undesirable: from `cutscene TRAIN` onward the ride runs in the
world module's train engine (`event_main.asm:96580`;
`ff6/src/world/train_script.asm`), and Number 128's `battle 73` is issued by
ASM inside it (`train_script.asm:899-917`) — there is no field, no menu, no
tile to put a trigger on. The ~6400-frame ride with five trash fights is the
retry cost of losing to Number 128, and that is exactly the "meaningful
attrition before a set piece" #10 says to preserve. **Action: document
only.**

### 4.4 Before the Cranes — NO new save point (the judgement call)

S3 is 42 steps from the reunion trigger on an encounter map, and a loss to
the Cranes replays the whole auto-played reunion scene. That is the weakest
existing placement in the band, and a save at, say, (52,36) — three tiles
north of the trigger row — would shave the walk to ~3 steps.

Recommended against, for three reasons: (a) the scene replay, not the walk,
dominates the retry cost, and a save point cannot remove it (the trigger row
auto-plays into the fight with no control between — placing the save closer
buys ~40 steps only); (b) the trigger-segment budget is 3 slots game-wide
and the Opera band will want them more (#10's own deferred list); (c) map
240's save is already *the* post-escape checkpoint and doubling saves on one
short map fails the density principle. If playtesting (issue #10 criterion,
last box) finds the Crane retry obnoxious, this is the first placement to
revisit — the analysis is done and the tile candidates are on the walkable
column read by the offline BFS ((52,36)-(52,38); **walkability unverified
live**, and the parked MAGITEK_TRAIN NPCs on map 240 are not in the model).

### 4.5 After the escape and Terra's return — NO new save point

The v0.6 stop line is first control on map 6 (`event_main.asm:25669`) with
Terra available (`$02F0=1`, `:25542`). The Blackjack has no vanilla save
point and does not need one: the world map — saveable everywhere — is one
takeoff away, and the map-240 save point earlier in the same leg covers the
escape itself. This mirrors the post-Opera precedent exactly: the v0.5
anchor is a world-map battery save, not an authored save point
(`gen_post_opera_anchor.lua`). **Caveat, unverified:** whether the menu can
open mid-flight (vs. after landing) was not checked; the anchor procedure in
§5 assumes land-then-save, which is safe either way.

### 4.6 Considered and not proposed: a factory-entrance save (map 262)

The S0→S1 stretch is the longest saveless run in the band (sneak scene, the
262 door/chute floor, the Kefka drain scene). A save just inside the factory
door — e.g. near (28,10), before any `mod_bg_tiles` door state exists —
would honor the "entrance of a long dungeon" principle. Not proposed for
v0.6: it spends the second of three remaining trigger slots on a stretch
with no losable fight; the attrition it removes is the kind #10 says to
keep; and 262 is the band's hazard map (runtime tilemap rewrites, scripted
platforms — `vector-route-recon.md` §8), so it carries the highest
verification cost per unit of player value. Revisit alongside segment
relocation if playtesting says the approach is too punishing. If it is ever
added, the tile must sit **before** the first door trigger pair at
(19,23-25)/(21,23-25) so a reload never restores a party past doors the
static tilemap shows closed.

---

## 5. Leg boundaries for #25

`leg-fixtures.md` wants anchors at "where the game lets the player save",
legs of a few thousand frames, entry/exit invariants per leg. With §4 the
band supports:

| anchor | battery save at | exists? |
|---|---|---|
| **A** `post-opera-v1` | world map (137,203) | yes — tracked (`Makefile:310`) |
| **B** `mrf-save-room` | map 270 (25,10) | vanilla save point |
| **C** `n024-doorstep-save` | map 273 (26,53) | **proposed**, §4.2 |
| **D** `minecart-platform` | map 272 (3,55) | vanilla save point |
| **E** `vector-escape` | map 240 (58,7) | vanilla save point |
| **F** `terra-returned` | world map, post-takeoff | world save, no authoring |

Legs, with the current fixture chain (`Makefile:775-841`) mapped onto them:

- **A→B** — world walk, Vector sneak, 262 floor, Kefka scene, both chutes.
  Today: `vector_doorstep` … `ifrit_doorstep` (7 fixtures). **The longest
  leg and the one over the frame target**; the only legal split (§4.6) is
  not proposed, so this leg stays big. Its entry contract is the existing
  anchor contract; exit: map 270, `$01F0=0`, party of 4, `$0646=1`.
- **B→C** — Ifrit/Shiva, the four-interaction magicite hand-off, the
  269/271/273 traversal. Today: `magicite_ifrit_shiva`, `n024_doorstep`.
  Exit: map 273, both magicite, `$0649=1`.
- **C→D** — Number 024, the tube-room set piece (six espers, **Celes
  leaves**, `$0068=1`), the lift. Today: `n024_won` … `minecart_doorstep`.
  Exit: map 272, party of 3, `$0068=1`.
- **D→E** — the minecart ride (~6400 frames, measured), Number 128, the
  escape scene to control on 240 (`$0069=1`, `$06AE=1`).
- **E→F** — Cranes, the non-interactive Terra chain, the **interactive and
  still unmapped** Esper-World flashback (`vector-route-recon.md` §6a),
  Setzer's tutorial, takeoff, land, save. **Flag: the second over-budget
  leg**, and it cannot be split legally — a save inside the flashback would
  be saving as the WEDGE-actor Maduin with the roster rewritten, the
  paradigm case of #10's transient-event-state prohibition. Accept the long
  leg or split it with a savestate (not an anchor) at `cranes_won`.

Tactical doorsteps that stay **hybrid** (short savestate drives from the
anchor, per `leg-fixtures.md:106-108`): `ifrit_doorstep` (B + ~13 steps +
face Ifrit), `n024_doorstep` (C + 2 steps + face up), `esper_tubes_doorstep`
(C + the 024 fight + 274's face-up-hold-A switch — the longest drive),
`minecart_doorstep` (D + 9 steps + face Cid), `cranes_doorstep` (E + 42
steps, halt one tile short of the trigger row). Number 128 has **no**
battery-reachable doorstep ever — it lives mid-cutscene; its leg is D→E
whole.

Every anchor B-E is producible through the game's own save routine at a
player-facing save point, which is the #25 requirement that anchors remain
evidence of playability (`leg-fixtures.md:116-118`).

---

## 6. What implementation must verify (not resolved here)

1. **Live walkability** of (26,53) (and any slide within the x 23-27 ×
   y 52-53 pocket) via `canStep`; the offline model has no live NPC
   occupancy.
2. **Save / reset / load / progress** at the new 273 save point, per §4.2's
   checklist and #10's acceptance criteria.
3. The 272 and 270 save points behave identically before and after the
   change (the trigger pointer table shifts for every map ≥ 273's block —
   mechanically safe by construction, but it is exactly the kind of claim
   the house rules say to check, not assert).
4. `fixed_block` still assembles — the 18-byte budget is measured from the
   built ROM, and the assembler is the authority (`macros.inc:421-423`
   errors on overrun).
5. Re-mint cost: this is a ROM change; the whole frontier re-mints. Batch it
   with the #25 anchor cut.

## Unverified-claims ledger

- All *(offline BFS)* distances: static model, no live NPC occupancy, no
  `mod_bg_tiles` runtime state (irrelevant on 273/270/272/240 — none of
  their triggers rewrite tiles; relevant if §4.6 is ever revived).
- Map 240 save→trigger 42 steps: parked MAGITEK_TRAIN NPCs not modelled.
- `npc_prop` free space "85 bytes": trailing-`$FF` measurement; a legal
  trailing `$FF` data byte would inflate it.
- Menu availability mid-flight (§4.5): unchecked; the proposal does not
  depend on it.
- The Esper-World flashback's internal structure (whether any tile there
  could even legally host a save): unmapped, per the recon; this proposal
  only asserts it *should not* host one.
