# OT6 v0.6 — Vector / Magitek Research Facility route recon

READ-ONLY reverse-engineering pass, 2026-07-26. No source touched, no fixture
minted, nothing committed. Scope: the post-Opera doorstep through the Magitek
Research Facility, the Cranes, and Terra's return, so that a later minting pass
can drive it without re-discovering the map/event structure.

Every claim below cites a file and line in the vendored disassembly, or is
explicitly labelled **UNVERIFIED**. Where I could not settle something from
source I say what a probe would have to measure. Line numbers are from this
repo on 2026-07-26.

**All static map/battle data used here was verified byte-identical between
`build/ot6.sfc` and vanilla** for the segments involved: `short_entrance`,
`long_entrance`, `map_prop`, `event_triggers`, `npc_prop`, `battle_groups`
(compared at the segment addresses in `ff6/rom/ff6-en.map:200,201,226,289,323,325`).
So decoding vanilla data files is decoding the OT6 ROM here.

---

## 0. HEADLINE — the existing v0.6 doorstep fixture is standing in the wrong town

**`tools/tests/gen_vector_arrival.lua` does not enter Vector. It enters
ALBROOK.** Three independent source confirmations:

1. `ff6/src/field/map_prop.dat` is 33 bytes × 415 maps; byte 0 is the map-title
   index (`ff6/src/field/text.asm:114`, `ShowMapTitle` reads `$0520`, which is
   map_prop byte 0 after `LoadMapProp`, `ff6/src/field/map.asm:143-157`).
   Map 323 → title index 53 → `"ALBROOK"` in `ff6/src/text/map_title_en.json`.
   **Vector is maps 242 and 253** (both title index 49).
2. Map 323's BG1 layout index (`map_prop` bytes 13-14 & `$03ff`,
   `ff6/src/field/map.asm:1755`) is 13 → `albrook_ext_bg1`
   (`ff6/src/field/sub_tilemap.asm`, declaration order = index order).
3. The world entrance the generator walks into is the ALBROOK record:
   WoB world short-entrance table (map index 0, `ff6/src/world/move.asm:1246`
   `CheckEntrance` reads `ShortEntrancePtrs` for the world id) contains
   `(138,203)` and `(139,203)` → **map 323, dest (2,17)** — exactly the map id
   and the `fieldX/fieldY` the generator asserts
   (`tools/tests/gen_vector_arrival.lua:49-58`).

Map 323's only exits are the four Albrook shops (325-328), map 330 (×2), map 332,
and the long entrance back out to world `(137,203)`. **Nothing in the Albrook
cluster leads toward Vector or the Magitek Research Facility.** Albrook is a
wrong turn for v0.6.

Two notes so this is not over-read:

- `tools/tests/gen_post_opera_anchor.lua:57-72` steps into map 323 and
  immediately back out *on purpose* — the comment says it is there to leave the
  ordinary world menu available before saving. That trick is fine; only its
  **naming** ("step right into Vector", "Vector entrance x/y") is wrong. The
  anchor itself ends at world `(137,203)`, which is a legitimate v0.6 start.
- `gen_vector_arrival.lua`, by contrast, **mints a fixture (`vector_arrival.mss`)
  while standing inside Albrook** and logs "cold battery Continue entered
  Vector". That fixture is not a Vector doorstep and should not be the boot
  state of the v0.6 chain. Treat it as untrusted.

`build/states/` in this worktree contains no `vector_arrival.mss`, so I could
not probe it; the above is source-only and I consider it settled.

---

## 1. Leg 1 — post-Opera anchor → Vector town → Magitek Factory door

### 1a. Vector is entered by a world EVENT TRIGGER, not an entrance record

I dumped **all 45 WoB world short-entrance records** (world map id 0). There is
**no entrance record anywhere in the game whose destination is map 242 or 253**
(I also swept all 415 maps' short+long entrance tables for targets 240/242/253/262:
the only hits are `242 (57,2)→262`, `240 (57,2)→262`, `262 (28,9)→242`, and
`263→262`). So the earlier claim "no world entrance leads into Vector town" is
correct *about the entrance tables* — but it is not the whole mechanism.

Vector is entered from the **world event-trigger table**, a different structure
(`ff6/src/world/move.asm:1309` `CheckEvent`, table in
`ff6/src/event/event_trigger.asm`):

```
ff6/src/event/event_trigger.asm:36-37
        make_event_trigger {120, 187}, _ca5ecf
        make_event_trigger {121, 187}, _ca5ecf
```

```
ff6/src/event/event_main.asm:14196-14205
_ca5ecf:
        set_script_mode WORLD
        if_switch $0079=1, _ca5edc
        load_map 242, {32, 61}, UP, {Z_UPPER, SHOW_TITLE, SET_PARENT, STARTUP_EVENT}
        ...
_ca5edc:
        load_map 253, {32, 61}, UP, ...
```

`$0079` selects the post-story Vector (253). It is set at
`event_main.asm:46316`, `:97003`, `:99716` — all after v0.6 — so on the v0.6
route the trigger loads **map 242 at (32,61) facing UP, Z_UPPER**.

Vector's way back out is a long entrance: `242 (30,63) len 12 → map 511
(= "return to parent/world") dest (120,188)`.

**So the v0.6 opening is an ordinary on-foot world walk, not an airship
sequence.** No `vehicle`/`airship_pos` opcode is involved in reaching Vector.

### 1b. The world walk (measured offline from ROM data)

Passability model: `M.worldPassable` = destination tile prop bit4 clear
(`tools/tests/lib/ot6_field.lua:577-586`, from `ff6/src/world/move.asm:992+`).
I reproduced it offline against `ff6/src/world/world_1_tilemap.dat` and
`ff6/src/world/tile_prop.asm:4` (`WorldTileProp`, world 0 = first 256 words).

BFS from the anchor tile **(137,203)** to **(122,187)**: **31 steps**, path

```
(137,203) (137,202) (137,201) (137,200) (137,199) (137,198) (136,198) (135,198)
(134,198) (133,198) (132,198) (131,198) (131,197) (130,197) (130,196) (129,196)
(129,195) (128,195) (128,194) (128,193) (127,193) (127,192) (126,192) (126,191)
(125,191) (125,190) (125,189) (125,188) (125,187) (124,187) (123,187) (122,187)
```

then **one LEFT step onto (121,187)** fires `_ca5ecf`.

**HAZARD:** 32 of the 32 tiles on that path carry world tile-prop bit6 (`$40`),
the random-battle-enabled bit (`tools/tests/lib/ot6_field.lua:582-583`). This is
exactly the band that broke `gen_opera1` (`docs/design/wob-route.md:623-632`):
`worldNavTo`'s verified-step blocklist condemns edges whenever a battle snapshots
and restores the party to the same tile. **Use `gen_opera1_doorstep.lua`'s
`worldGrind` (tools/tests/gen_opera1_doorstep.lua:56-75), not `worldNavTo`.**
Also target **(122,187)**, not (120,187) — a plan that routes *through*
(121,187) will fire the Vector trigger mid-leg.

### 1c. Inside Vector: the gate is physically sealed and there is a trap row

Map 242 is 64×64, tile-prop set `vector`, BG1 `vector_ext_bg1` (map_prop bytes
4 / 13-14). I ported `stepAllowed`/`zAfter`/`bfsPath` from
`tools/tests/lib/ot6_field.lua:125-237` offline and ran it on this map. The
model matches the lib exactly **except that it does not model object occupancy
(`$7E2000`)** — the lib's rule at `ot6_field.lua:166-168`. That difference only
ever *removes* paths, so an offline path is an upper bound on reachability.

The Magitek Factory door is a long entrance:

```
map 242 long entrance (57,2) length 2 → map 262, dest (28,8)
```

Offline BFS from the Vector arrival tile (32,61) to (57,2) is **88 steps and it
routes through (56,39)**. That matters, because:

- `event_trigger.asm:1070-1073` puts an **ungated** trigger at **(56,39),
  (57,39), (58,39)** → `_cc93dc` (`event_main.asm:99473`):
  dlg $06B0 *"You!? How'd you get in here?"* → `call _cc93f1` →
  **`battle 29`** → `_cc93f4` → `load_map 242 {34,58}` and the party is walked
  back down to the south of the map with dlg $0555 "Danger…danger…".
  A naive `navTo(57,2)` therefore gets caught, fights, and is teleported.
- But the party cannot actually get that far unaided. Three guard NPCs stand at
  **(54,39), (55,40), (54,41)** (`npc_prop.asm:10777,10784,10791`, visibility
  switch `$062B`, event `_cc93ce` = *"Magitek Research Facility. No Entry!"*).
  `$062B` is **1 at new game** (`ff6/src/field/init_npc_switch.dat`, loaded by
  `InitNPCSwitches`, `ff6/src/field/obj.asm:176-184`, into `$1EE0` = switch
  `$0300`) and is cleared exactly once, at `event_main.asm:96986` — *after* the
  factory escape. So during v0.6 they are present.
  Blocking those three tiles in the offline BFS makes **(57,2) and (58,2)
  unreachable** from (32,61): the corridor is three parallel lanes at y=39/40/41
  and each guard plugs one lane. The tile map:

```
      x=44                       x=63
 y=38  .......S....################      S = (43,38) the sneak trigger
 y=39  .......##O........G#TTT#####      O = (45,39) old man, G = guards, T = _cc93dc
 y=40  .........##........G########
 y=41  ..................G#########
```

### 1d. The intended way in — the old man, then a facing-gated ledge

```
ff6/src/event/npc_prop.asm:10770-10775
        make_npc {45, 39}, $063b
                set_npc_event _cc9627
```

```
ff6/src/event/event_main.asm:99897-99931
_cc9627:
        if_switch $01F0=1, _cc96c5
        dlg $054C  ; "Shh! I'm a Returner sympathizer!"
        ...
        dlg $054D  ; "While I distract the soldiers, climb onto the steel tower
                   ;  from this box, and enter the facility!"
        dlg $054E  ; "All ready?  0: Yes  1: No"
        choice _cc9659, _cc96bd
```

Picking **0 (Yes)** runs `_cc9659` (`:99932`), the drunk act, ending at
`event_main.asm:100017` with **`switch $01F0=1`**. Picking 1 (`_cc96bd`) does
nothing. This is the `gen_zozo3_clock` choice-dialog shape.

Then the ledge:

```
ff6/src/event/event_trigger.asm:1067
        make_event_trigger {43, 38}, _cc96c9
```

```
ff6/src/event/event_main.asm:100025-100030
_cc96c9:
        if_any
                switch $01F0=0
                switch $01B2=0
                goto EventReturn
        ...
```

i.e. it fires only if `$01F0=1` **and `$01B2=1`**. `$01B2` is not a story
switch — see §7. It is **"the party is facing DOWN"**. So the party must arrive
on (43,38) by stepping **down** from (43,37).

The scene then walks SLOT_1 over non-walkable rooftop tiles — `(43,38) →
(42,38) → (41,38) → (41,35) → (49,35) → (49,34) → (54,34) → (54,35) → (57,35) →
(57,34)` — clears `$01F0`, and returns control at **(57,34)**, *north* of both
the guards and the trap row. From there (57,34) → (57,2) is a clean column walk
(no z-split; the offline model finds it at every z seed).

### Leg 1 route summary (drive order)

| step | where | what |
|---|---|---|
| 1 | world | `worldGrind` (137,203) → **(122,187)** — dense battle band |
| 2 | world | one LEFT step → (121,187) fires `_ca5ecf` → **map 242 (32,61)** |
| 3 | 242 | `navTo` to a tile adjacent to **(45,39)**, face the old man, talk |
| 4 | 242 | choice dialog: pick **0 (Yes)** → `$01F0=1` (`ev:100017`) |
| 5 | 242 | `navTo (43,37)` then step **DOWN** onto **(43,38)** → sneak scene → control at **(57,34)** |
| 6 | 242 | `navTo (57,2)` → long entrance → **map 262 (28,8)** |

**Do not `navTo(57,2)` before step 5** — it is NO-PATH while the guards stand
there, and `navTo` will burn its 20 no-path retries and then error
(`ot6_field.lua:406-419`). That failure is at least loud.

---

## 2. Leg 2 — the Facility interior and the Ifrit / Shiva encounter

### Map graph (all from entrance tables + `load_map` opcodes)

```
242 (57,2)L ──► 262 (28,8)          Magitek Factory, upper   [32×64]
262 (28,9)S ──► 242 (58,3)          (overridden to map 240 once $0069=1, ev:94202)
262 (22,53)/(22,54) trigger ─►(scripted)─► 263 (16,9)        ev:94789/94797 → _cc7666 :94805
262 (12,60)S / (15,60)L      ──► 263 (12,7)/(15,9)
263 (36,44)/(37,44)/(38,44) trigger ─►(scripted chute)─► 264 (14,0)   ev:94649 _cc7588 → load_map 264 @94665
264 (6,6) trigger  ──► back to 263 (17,30)                    ev:94730 _cc75f6 (gated $0273=0)
264 (9,5)S  ──► 269 (44,53)      264 (3,5)S ──► 270 (25,14)  [270 = SAVE POINT room, trigger (25,10)]
269 (42,12)S ──► 271 (31,28)     "MAGITEK RES. FACILITY"
271 (3,27)S  ──► 273 (30,60)
273 (25,50)S ──► 274 (10,25)     the esper tube room [32×32]
274 (20,13) trigger ─► load_map 266 (7,0) (the lift) ─► load_map 272 (8,46)   ev:96313 _cc7f43
272 → `cutscene TRAIN` (the minecart) ─► load_map 240 (64,13)                 ev:96580/96586
240 (52,39)/(52,40)/(52,41) trigger ─► _cc818c ─► map 6 (Blackjack) ─► battle 71
```

Offline BFS says **269, 271, 273 and 274 are ordinary single-z BFS maps** (no
z-split, paths found at every z seed):

| map | leg | offline BFS |
|---|---|---|
| 269 | (44,54) → (42,12) | 60 steps |
| 271 | (31,27) → (3,27) | 38 steps |
| 273 | (30,60) → (25,51) Number 024 | 14 steps |
| 273 | (30,60) → (25,50) door to 274 | 15 steps |
| 274 | (10,25) → (10,9) | 16 steps |
| 274 | (10,25) → (20,13) | 24 steps |

Maps **262, 263 and 264 are NOT statically navigable** — see §8, hazard 3.

### The Ifrit / Shiva fight

The pair lives on **map 264**, in a 53-tile alcove at the top of the map
(x 2–12, y 4–10) that the chute drop lands you in:

```
ff6/src/event/npc_prop.asm:12289-12296   map 264 NPC_5  {3, 8}  sw $0646  ev _cc7937   gfx IFRIT
ff6/src/event/npc_prop.asm:12298-12305   map 264 NPC_6  {9, 6}  sw $0646  ev _cc7992   gfx SHIVA
```

`$0646` = 1 at new game (`init_npc_switch.dat`), cleared only at
`event_main.asm:95353`. (A second, unused-in-this-beat Ifrit/Shiva pair exists on
map 263 at (36,41)/(37,40) behind `$0645`, `npc_prop.asm:12211/12220`; `$0645` is
**0** at new game, so those are not the ones you meet.)

They sit on the two doors: Ifrit (3,8) is under `264 (3,5)→270` (the save room),
Shiva (9,6) is under `264 (9,5)→269` (the way onward).

```
ff6/src/event/event_main.asm:95260-95315
_cc7937:
        if_switch $0060=1, _cc7986      ; already fought -> just talk
        ...
        battle 70                       ; :95283
        call _ca5ea9
        ... dlg $055F  ; IFRIT: Hmmm…  SHIVA: Well, Ramuh DID entrust them…
        switch $0060=1                  ; :95312
        switch $0273=1                  ; :95313
        player_ctrl_on
```

**Battle 70 → formation 439 → species `$0109` "Ifrit" only.**
Decoded from `ff6/src/field/event_battle_group.dat` (4 bytes per event battle:
two 16-bit formation ids, 75%/25% — `ff6/src/field/battle.asm:506-517` +
`EventBattle`, `ff6/src/field/event.asm:1907-1935`) and
`ff6/src/battle/battle_monsters.dat` (15 bytes per formation; +1 = present
bitmask, +2..7 = low id bytes, +14 = high id bits, per
`ff6/src/btlgfx/btlgfx_main.asm:2011-2023`). Both formation slots of battle 70
are 439.

**Shiva `$0108` is NOT in the formation.** She is not in *any* formation in the
game — I swept all 576. So Shiva must enter through Ifrit's in-battle script.
**UNVERIFIED:** I did not decode `ff6/src/battle/ai_script.asm` to prove the
entrance command. A probe should read `formationWords()` at battle start
(expect only `$0109` present) and again after the first monster turn to see
`$0108` appear. `docs/design/wob-route.md:256` calls this a "tag fight"; that is
consistent with a one-monster formation plus a scripted entrance, but the
mechanism is unproven here.

### The magicite

Talking to each afterwards:

```
_cc7986 (:95316)  Ifrit  -> switch $0272=1 ; if $0274=1 goto _cc79a4
_cc7992 (:95323)  Shiva  -> switch $0274=1 ; if $0272=1 goto _cc79a4
_cc79a4 (:95331)  -> switch $0646=0, $0647=1, $0648=1, $0273=0   (:95353-95356)
```

`$0647`/`$0648` reveal the two MAGICITE NPCs (`npc_prop.asm:12307/12316`, map 264
(3,8) and (9,6)) whose events are:

```
_cc79cd (:95359)  dlg $0564 "Received the Magicite 'Ifrit.'"  give_genju IFRIT   switch $0647=0
_cc79dd (:95372)  dlg $0565 "Received the Magicite 'Shiva.'"  give_genju SHIVA   switch $0648=0
```

**Both espers require touching both dying espers first, then touching each
magicite.** Four separate NPC interactions. `$0273` also gates the way *back*
up to map 263 (`_cc75f6`, `:94730`: returns immediately while `$0273=1`), so the
party is locked in the alcove between the fight and the hand-off.

---

## 3. Leg 3 — Number 024

```
ff6/src/event/npc_prop.asm:12478-12486   map 273 NPC_1 {25, 51} sw $0649 ev _cc79ed gfx NUMBER_024
```

`$0649` = 1 at new game; cleared only at `event_main.asm:95390`.

```
ff6/src/event/event_main.asm:95385-95395
_cc79ed:
        battle 72
        call _ca5ea9
        hide_obj NPC_1
        sort_obj
        switch $0649=0
        fade_in / wait_fade
        return
```

**Battle 72 → formation 441 → species `$010a` "Number 024"**, single monster,
both formation slots identical.

Geometry: 273 (25,51) sits directly below the door `273 (25,50) → 274 (10,25)`,
so 024 physically blocks the esper room. Contact/talk fires the fight; there is
no `if_b_switch $40` gate on the post-battle tail, so the kill-bit idiom should
be enough to clear it (**UNVERIFIED** — `_cc79ed` has no battle-switch check at
all, which is *weaker* than a `$40` gate, so the kill-bit should work; confirm
by watching `$0649` go to 0).

---

## 4. Leg 4 — the esper tubes, Cid, and the minecart

### The tube room (map 274) — a facing+A-gated trigger

```
ff6/src/event/event_trigger.asm:1216   make_event_trigger {10, 9}, _cc7a60
```

```
ff6/src/event/event_main.asm:95456-95461
_cc7a60:
        if_any
                switch $01B0=0
                switch $01B4=0
                switch $0068=1
                goto EventReturn
```

`$01B0` = **facing UP**, `$01B4` = **A button held** (§7). So the scene fires
only when the party stands on (10,9) **facing up with A held** — this is the
"big switch" NPC at (10,8) (`npc_prop.asm:12631`, gfx BIG_SWITCH). A plain
`navTo` will never trigger it.

The scene (≈850 lines, `:95456`–`:96312`) is the whole Cid/Kefka set piece:

- `give_genju MADUIN, PHANTOM, UNICORN, BISMARK, CARBUNKL, SHOAT`
  (`event_main.asm:95777-95782`) — **six espers**, in one uninterruptible block.
- `party_chars LOCKE, CELES` (`:95796`).
- **`delete_obj CELES`, `char_party CELES, 0`, `party_chars LOCKE`,
  `switch $02F6=0`, `remove_equip CELES`** (`:96148-96158`). Celes stays behind
  with Cid; see §6 — this is a *party-size* event, not cosmetic.
- ends `switch $064B=1`, **`switch $0068=1`** (`:96298-96299`), `player_ctrl_on`.

`$0068` then unlocks the lift trigger:

```
ff6/src/event/event_trigger.asm:1217   make_event_trigger {20, 13}, _cc7f43
ff6/src/event/event_main.asm:96313-96314
_cc7f43:
        if_switch $0068=0, EventReturn
```
→ `load_map 266 {7,0}` (`:96341`) → Cid dialogue → `load_map 272 {8,46}`
(`:96406`) → controllable on map 272, which has a **save point at (3,55)**
(`event_trigger.asm:1211`, `npc_prop.asm:12434`).

### The minecart is a CUTSCENE, not an event map

```
ff6/src/event/event_main.asm:96579-96581
        switch $02BC=1
        cutscene TRAIN
        call _ca5ea9
```

`cutscene TRAIN` is opcode `$ae` with `CUTSCENE::TRAIN = $ae`
(`ff6/include/event_cmd.inc:707`). The ride runs in the world module's train
engine, `ff6/src/world/train_script.asm`, driven by a **52-item × 5-byte script**
(`train_script.asm:615-660`, `trcourse`), one item advanced every `$21` (33)
ticks of counter `$36` (`train_script.asm:22-50`). Byte 4 of each item is a
command:

| script item (0-based) | cmd | effect |
|---|---|---|
| 3 | `$e0` | `TrainCmd_e0` (`:829`) → **event battle `$29` = battle 41** |
| 9 | `$e1` | `TrainCmd_e1` (`:864`) → **event battle `$90` = battle 144** |
| 14 | `$e0` | battle 41 |
| 24 | `$e1` | battle 144 |
| 31 | `$e1` | battle 144 |
| **36** | **`$e2`** | `TrainCmd_e2` (`:899`) → **event battle `$49` = battle 73 — Number 128** |
| 38 | `$ff` | end of course |

- battle 41 → formations 111 / 117 → Mag Roader `$06` (×1, or `$06`+`$af`)
- battle 144 → formations 406 / 407 → Mag Roader `$06`×2 / `$af`×4
- **battle 73 → formation 442 → `$010b` Number 128 (slot 0), `$0140` Left Blade
  (slot 1), `$013f` RightBlade (slot 3)** — battle bg `$2c`
  (`train_script.asm:906-909`)

**This is the single most likely time-sink for the minting pass.** `battle 73`
appears **nowhere** in `event_main.asm` — grepping the event script for
"battle 73" returns nothing. It is issued by ASM writing `$0011E0` directly.
Anyone looking for the Number 128 trigger in the event disassembly will not
find it.

Frame budget for the ride: 42 items × ~33 ticks ≈ 1400 ticks plus six battles.
**UNVERIFIED** — I did not trace where `$36` is decremented, so "one tick = one
frame" is an assumption. Measure it rather than trusting it.

---

## 5. Leg 5-6 — the escape, map 240, and both Cranes

After the cutscene:

```
ff6/src/event/event_main.asm:96582-96586
        switch $01CC=1 ; $02BC=0 ; $06A3=1 ; $06AE=0
        load_map 240, {64, 13}, LEFT, {ASYNC, Z_UPPER, NO_FADE_IN, STARTUP_EVENT}
```

**Map 240 is a second copy of Vector** — same BG1 (`vector_ext_bg1`) and same
tile props as 242, different NPCs/triggers/palette, used for the escape. (Its
title index is 0, so no map name is shown.) Note the load x=64 on a 64-wide map
(`map_prop` `$0537 = $aa` → x mask `$3f`); the party is walked in from off-grid.
Flagged as odd, not investigated.

The Kefka explosion plays out and control returns at
`event_main.asm:96684-96690`:

```
        switch $0069=1        ; from now on 262 (28,9) exits to map 240, not 242 (ev:94202)
        switch $0666=1
        switch $06AE=1        ; reveals the SAVE POINT NPC at 240 (58,7)
        switch $01CC=0
        player_ctrl_on
```

**This is a natural fixture site** — controllable, on a map with a save point at
(58,7) (`event_trigger.asm:1062`, `npc_prop.asm:10637`).

Then:

```
ff6/src/event/event_trigger.asm:1059-1061   {52,39}/{52,41}/{52,40} → _cc8157/_cc816b/_cc817f
event_main.asm:96692-96722  (each: if $0069=0 or $006B=1 → EventReturn) → _cc818c (:96723)
```

`_cc818c` is the Setzer reunion. Its tail:

```
ff6/src/event/event_main.asm:96980-96997
        norm_lvl SETZER
        create_obj SETZER
        char_party SETZER, 1        ; <-- SETZER becomes playable HERE
        switch $02E9=1
        switch $02F9=1              ; <-- and available HERE (see §7)
        switch $062B=0              ; Vector gate guards removed
        switch $0645=0 ; $064D=1 ; $064C=1 ; $063B=0
        switch $006B=1
        call _cb3ff1                ; <-- the Blackjack deck
        if_switch $022F=0, _cac3c7
```

```
ff6/src/event/event_main.asm:46907-47075
_cb3ff1:
        load_map 6, {20, 6}, LEFT, {ASYNC, NO_FADE_IN}
        switch $0246=1
        ... party reaction dialogue (_cb40f2 / _cb4132) ...
        battle 71, AIRSHIP_CENTER      ; :47070
        call _ca5ea9
        return
```

**Battle 71 → formation 440 → `$010d` "Crane" + `$010e` "Crane"** (Left/Right).
The fight is **on the Blackjack deck (map 6), with `AIRSHIP_CENTER` background**,
reached with **no player navigation at all** — it auto-plays from the map-240
trigger. So `crane_doorstep` should be minted on map 240 one step from
(52,39/40/41), not anywhere near the factory.

Between the trigger and the fight there is a long `TEXT_ONLY`-heavy stretch
(`_cb40f2`/`_cb4132` are per-character reaction lines gated on who is in the
party) — the `rideScene`/`hasControl()`-gated idiom from
`docs/design/wob-route.md:96-102` is the tool.

---

## 6. Leg 7 — Terra's return, and the v0.6 stop line

*(This section answers the coordinator's Terra questions directly.)*

### 6a. The chain, end to end

`_cc818c` → `_cb3ff1` (Cranes) → falls through to
**`_cac3c7` (`event_main.asm:30250`)**, which is entirely non-interactive:

- `load_map 0 {121,188} AIRSHIP` + `set_script_mode VEHICLE`, a scripted flight,
  then `load_map 6 {15,6}` for the Locke/Setzer "I'm worried about TERRA. Let's
  return to Zozo" scene (`:30297-30310`);
- a second scripted flight to `airship_pos {22,90}` and `load_map 226 {82,37}`
  (Zozo) (`:30326-30340`);
- `_cac4b0` (`:30361`): `switch $006B=1`, then Locke: "TERRA…", "Magicite!!",
  TERRA: "Father…?", "I remember it all… I was raised in the Esper's world."
- then the flashback opens: `char_prop WEDGE, MADUIN`, `char_party WEDGE, 1`,
  everyone else `char_party …, 0`, `load_map 217 {32,12}` ("ESPERVILLE"),
  then `load_map 219 {34,10}` + **`player_ctrl_on`** with
  `switch $0338=1`, `$0337=1`, `$01C2=1` (`:30508-30514`).

**The flashback is interactive.** The party is Maduin (the WEDGE actor) walking
around Esperville (maps 217 / 218 / 219). The chain is
`$0117` (`:24041`) → the map-218 trigger `{56,49}` → `_caa78f` (`:25678`,
gated `$0117=1 && $0118=0`) → **`switch $0118=1`** (`:25755`) → the NPC event
`_ca9fbf` (`:24412`) → `if_switch $0118=1, _caa4e0` → the finale
**`_caa4e0` (`:25241`)**.

Map 217↔219 is a five-door long/short-entrance pair set; 217 `(32,6)` → 218
`(56,49)`. **UNVERIFIED / needs probing:** I did not decode the Esperville
interactive sequence beyond that skeleton — which NPC carries `_ca9fbf`, what
sets `$0117`, and whether any of it is z-split. This is a real, unmapped leg of
v0.6, not a cutscene ride.

### 6b. Where Terra becomes selectable again — **`event_main.asm:25542`**

The finale tail (`_caa4e0`/`_caa5fb`, `:25402`–`:25551`):

```
 25405         create_obj TERRA
 25407         char_party LOCKE, 1
 25408         char_party WEDGE, 0
 25409         char_party SETZER, 1
 25410-25427   CYAN / EDGAR / SABIN / GAU restored iff they were in the active party
 25430         load_map 226, {82, 17}   (Zozo)
 25436         party_chars LOCKE, SETZER
 ...
 25488         dlg $05D4  ; TERRA: "…I finally feel I can begin to control this power of mine…"
 ...
 25541         norm_lvl TERRA
 25542         switch $02F0=1        <-- TERRA BECOMES AVAILABLE
 25543         switch $0070=1        <-- arms the Blackjack party-swap room
 25545         call _cc6928
 25546         load_map 0, {22,94} AIRSHIP  -> _caa6c0 -> load_map 6 {16,6}
 ...          Setzer's airship tutorial (three choice dialogs)
 25669         call _cacb95          <-- player_ctrl_on
 25671-25676   switch $016F=1 ; $045C=0 ; $01CC=0 ; $01BA=0 ; $01C2=0
```

**`$02F0` is not an ordinary story flag — it is bit 0 of `$1EDE`, the engine's
"available characters" word.** Proof chain:

- switch id → RAM: switch `$02F0` lives at `$1E80 + ($2F0>>3)` = **`$1EDE`**,
  bit 0 (`ff6/src/field/event.asm:5440-5445`, `GetEventSwitch0` reads `$1e80,y`).
- `ff6/notes/field-ram.txt:1114-1116` labels `+$1EDE` as
  `sncccccc cccccccc`, `c: available characters`, `s: there is at least one
  saved game`, `n: go to first Narshe scene`.
- `set_case AVAIL_CHARS` is event opcode `$e1`
  (`ff6/include/event_cmd.inc:916`), implemented at
  `ff6/src/field/event.asm:4443-4448` as `ldx $1ede / stx $1eb4` — and
  `$01A0`-`$01AD` are `$1EB4`/`$1EB5` bits 0-13. So `set_case AVAIL_CHARS` +
  `if_switch $01A0` **is** a read of `$02F0`.
- The per-character block is confirmed by `_cac90b`/`_cac97c`
  (`event_main.asm:30939-31010`), which walk `$02F0`→`$02FD` one per character
  in the canonical order TERRA, LOCKE, CYAN, SHADOW, EDGAR, SABIN, CELES,
  STRAGO, RELM, SETZER, MOG, GAU, GOGO, UMARO; and by the boot code's use of
  `$02FE`/`$02FF` (`event_main.asm:14164-14169`) matching the `n`/`s` bits.
- Cross-check in the other direction: `switch $02F9=1` at `:96985` is exactly
  where Setzer joins, and `switch $02F6=0` at `:96157` is exactly where Celes
  leaves. Both match `$02F0 + charId`.

So: **Terra becomes a selectable party member at `event_main.asm:25542`
(`switch $02F0=1`), inside the Esper-World flashback finale, together with
`norm_lvl TERRA` (:25541) and `create_obj TERRA` (:25405).**

### 6c. Is "Terra recovers her will" a separate, later event? **No.**

The line the phrase refers to — dlg `$05D4`, *"…Now I understand… I finally feel
I can begin to control this power of mine…"* — is at
**`event_main.asm:25488`, 54 lines before `switch $02F0=1`**, in the same
uninterruptible tail. There is no separate later "recovers her will" event.

The later Terra beat that does exist is the **Sealed Gate esper burst**,
`_cb39ca` (`event_main.asm:45953`-`:46203`): `party_chars TERRA` (:45967),
`char_party TERRA, 0` (:46095), `battle 121` (:46105), `battle 122` (:46196),
then `char_party TERRA, 1` + `party_chars TERRA` (:46202-46203). That is Terra
being taken by the espers and coming back — a v0.7 Beat-C event, and it is
**not** where she recovers her will or becomes available.

**Verdict on the doc conflict:** `docs/design/wob-route.md:63` ("v0.6 finishes
after the Cranes, Factory escape, and Terra's return") and `docs/ROADMAP.md`
are right; **`docs/design/wob-route.md:53` is wrong to put "Terra recovers her
will" in Beat C / v0.7.** The two phrases name the same beat, and that beat is
v0.6's terminal. v0.6's stop line should name it as *"the Esper-World flashback
finale — `$02F0=1`, first control on the Blackjack"*.

### 6d. What the party actually looks like at the v0.6 stop line

The first controllable, menu-capable state after Terra's return is **map 6 (the
Blackjack cabin), `player_ctrl_on` via `_cacb95` at `event_main.asm:25669`**,
with `$016F=1`, `$01CC=0`, `$01C2=0`, `$0070=1`, `$02F0=1`. From there the
player takes off into the world map — the first *saveable* state in the vanilla
sense (world map / save point) is one takeoff later, or at the map-240 save
point earlier in the leg.

At that stop line, from source:

- **Terra: available in the roster, NOT in the active party.** `$02F0=1`
  (:25542) and `create_obj TERRA` (:25405) make her selectable; but the tail
  never executes `char_party TERRA, …`, and the last `party_chars` is
  `LOCKE, SETZER` (:25436), re-derived by `_cac6ac` at :25556. The Blackjack
  party-change room is armed by `$0070=1` (:25543), which gates `_cb41a5`
  (`event_main.asm:47154`) — the routine that shows a crew NPC for each
  character who is available but not active.
- **Locke and Setzer: active** (`char_party LOCKE, 1` :25407,
  `char_party SETZER, 1` :25409).
- **Celes: absent from the roster.** `switch $02F6=0` at `:96157` made her
  unavailable in the tube room, and nothing in the escape/return chain restores
  her. (The next `char_party CELES, 1` on the WoB line is `_cadd31`,
  `event_main.asm:32965`, a later beat.)
- Cyan/Edgar/Sabin/Gau are restored only if they were in the active party at the
  Cranes (`$0333`-`$0336` bookkeeping, `:30364-30411` vs `:25410-25427`).

**Residual uncertainty (probe this):** Terra's `$1850[TERRA]` party nibble is
never written by this chain, so it carries in from the Zozo beat. `char_party`
writes both `$0867,y` and `$1850,y` (`ff6/src/field/event.asm:563-585`);
`create_obj` sets `$1850` bit 6 (`:709-728`). Whether the party-select menu
requires a nonzero party nibble in addition to `$02F0` is something I did not
trace into `ff6/src/menu/party.asm`. **Probe:** at the stop line read
`$1850+0` (Terra), `$1EDE`/`$1EDF`, and `$1A6D` (active party number); then
open the party menu and confirm Terra is offered.

> **Correction (2026-07-28, measured on the minted chain during the B–F
> anchor pass):** the source reading above was derived while the fixture
> chain still left Zozo two-handed.  With the four-party chain upstream
> (#21: LOCKE + CELES + SABIN + EDGAR through the Facility), EDGAR and
> SABIN **were** in the active party at the Cranes, so the `:25410-25427`
> restore applies to them — the finale restores both.  The measured party
> at the stop line is **LOCKE, EDGAR, SABIN, SETZER**, with **TERRA
> available but not active** (as derived above).  The Locke+Setzer-only
> reading holds only for a chain that reaches the Cranes two-handed.

### 6e. The load-bearing balance consequence

**v0.6 cannot assume Terra for any of its fights.** She becomes available only
*after* the last v0.6 fight. Fight-by-fight party, derived from the `char_party`
/ `$02Fx` writes above plus the measured post-Opera roster:

| fight | party (from source) |
|---|---|
| Ifrit `$0109` (battle 70) | **Locke + Celes** |
| Number 024 `$010a` (battle 72) | **Locke + Celes** |
| minecart Mag Roaders (battles 41, 144 ×5) | **Locke solo** (Celes removed at :96154) |
| Number 128 + blades `$010b/$0140/$013f` (battle 73) | **Locke solo** |
| Cranes `$010d/$010e` (battle 71) | **Locke + Setzer** (Setzer joins at :96982) |

This contradicts `docs/design/wob-route.md:192-193`, which says
"MRF (Ifrit/Shiva/024): Locke, Celes + 2" and "Number 128 / Cranes: the factory
four (fixed set)". There is no "+2" and there is no factory four.

**Caveat, stated plainly:** the "Locke + Celes" starting roster is inherited
from `zozo_done`/the Opera, where `docs/design/wob-route.md:317` measured
`$1850` as LOCKE=`$C1`, CELES=`$51`, rest `$00`; I did not re-measure it at the
post-Opera anchor. The *deltas* above (Celes removed, Setzer added, Terra added)
are source-proven; the *base* is one measurement old. **Probe:** read `$1850+0..13`
at the post-Opera anchor before authoring any balance work.

> **Correction (2026-07-28, from the B–F anchor pass):** the table above is
> the **two-man-chain measurement** — its base roster predates #21's
> four-party chain.  On the minted four-party chain the Facility fights run
> four-handed (Locke, Celes, Sabin, Edgar; three once the tube room takes
> Celes) and **the Cranes were fought by four** (Locke, Edgar, Sabin +
> Setzer joining at `:96982`), not by Locke + Setzer alone.  The structural
> claim stands — Terra is available only after the last v0.6 fight — but
> per-fight party sizing must come from the minted chain's doorstep
> measurements (`wob-route.md`, and each generator's `partyReport` logs),
> not from this table.

---

## 7. THE BIG ONE — switches `$01B0`-`$01B7` are not story bits

`docs/design/wob-route.md:653-658` records the opera weight trap as an open
question: *"`$01B0`/`$01B4` are only ever cleared or read — never set by a
`switch` opcode … the trap is armed by the puzzle's ASM / object-position
logic."* That is half right (they are never set by a `switch` opcode) and the
conclusion is wrong. **They are not story switches at all.**

Switch `$01B0` = `$1E80 + ($1B0>>3)` = **`$1EB6` bit 0**. `$1EB6` is an engine
state byte:

```
ff6/notes/field-ram.txt:1072-1080
      $1EB6 sotaldru
            s: serpent trench arrow direction
            o: map's object data needs to be loaded
            t: tile event bit (gets cleared when the party moves to a new tile)
            a: A button is down
            l: character is facing left
            d: character is facing down
            r: character is facing right
            u: character is facing up
```

(The notes list bit 7 first; confirmed by the same file's `$1EB9 up?s????`
against `field-ram.txt:427`, "Clear event bit `$1EB9.7`".)

Confirmed in code, three ways:

```
ff6/src/field/event.asm:5415-5433   UpdateCtrlFlags
        lda $087f,y        ; party facing direction (0=UP 1=RIGHT 2=DOWN 3=LEFT,
        tax                ;  const.inc:72-77 EVENT_DIR)
        lda $1eb6
        and #$f0
        ora f:BitOrTbl,x   ; BitOrTbl = BIT_0..BIT_7  (event.asm:5523-5524)
        sta $1eb6
        lda $06            ; A button
        bpl :+
        lda $1eb6 / ora #$10 / sta $1eb6      ; bit 4 = A held
:       lda $1eb6 / and #$ef / sta $1eb6
```
```
ff6/src/field/event.asm:92     jsr UpdateCtrlFlags   (top of ExecEvent, every event tick)
ff6/src/field/player.asm:529-531   lda $1eb6 / and #$df / sta $1eb6   ; clear bit5 each step
ff6/src/field/init.asm:465-476     bit6 = object-map-update flag
```

Therefore:

| switch | meaning |
|---|---|
| `$01B0` | party is facing **UP** |
| `$01B1` | party is facing **RIGHT** |
| `$01B2` | party is facing **DOWN** |
| `$01B3` | party is facing **LEFT** |
| `$01B4` | **A button is held this frame** |
| `$01B5` | tile-event bit (cleared on every step — a "once per tile" latch) |
| `$01B6` | map object data needs loading (map-init guard) |
| `$01B7` | serpent-trench arrow direction |

This retro-explains the opera trap (`_cab497` needs `$01B0=1 && $01B4=1` =
*face up and hold A*) and it is load-bearing three times in v0.6:

- `_cc96c9` (Vector sneak, §1d): `$01B2` = face DOWN.
- `_cc7a60` (esper tube room, §4): `$01B0 && $01B4` = face UP + hold A.
- `_cc76cc` / `_cc76f1` (map 262 platform hops, §8): `$01B1`/`$01B3` + `$01B4`.
- `$01B5` guards every one-shot door-opening trigger on map 262
  (`_cc7735`/`_cc7753`/`_cc77b0`/`_cc77ce`, `event_main.asm:94960-95050`).

**Consequence for the driver:** `navTo` releases the pad between steps and never
presses A on the open field (`ot6_field.lua:340-351`). Every one of these
triggers needs a bespoke "arrive facing D, then hold A" step. This is not
optional and it is not discoverable by walking.

`$022F` note, while on the subject: `if_switch $022F=0, X` appears 83 times in
`event_main.asm` and **`switch $022F=…` appears zero times**. It is the
disassembly's rendering of an unconditional long jump. Read those as `goto X`.

---

## 8. Hazards, ranked by how much time I expect them to cost

1. **`gen_vector_arrival` goes to Albrook (§0).** If the v0.6 chain is built on
   that fixture, everything downstream is wrong. Rewrite the leg as §1.
2. **`battle 73` (Number 128) is not in the event script (§4).** It is issued by
   `TrainCmd_e2` inside the `cutscene TRAIN` engine
   (`ff6/src/world/train_script.asm:899-917`). Budget for the fact that the
   minecart is an on-rails cutscene with **six forced battles**, not a map.
3. **Maps 262 / 263 / 264 are not statically navigable.** Offline BFS on the
   real tile data (same model as `ot6_field.lua`):
   - map 262 from the Vector door (28,8): only 130 tiles reachable. `(4,22)`,
     `(11,45)`, `(12,60)`, `(22,53)`, `(22,54)` are all NO-PATH.
   - map 263 from (16,9): **10 tiles**. From (17,30): **4 tiles**.
   - map 264 from the chute landing ≈(10,7): **53 tiles** — the Ifrit/Shiva
     alcove — and it is *disconnected* from the 1670-tile main region of the map.

   Two reasons, both real: (a) the maps are stitched by **scripted transitions**
   (`_cc7666`, `_cc7588`, `_cc7905`, `_cc75f6` — each is an `obj_script` that
   walks the party over non-walkable tiles), and (b) several triggers
   **rewrite the BG1 tilemap at runtime** (`mod_bg_tiles BG1 {19,24}` /
   `{21,24}`, `event_main.asm:94962-95060`), so the static tilemap does not
   describe the map after the doors open. **A minting pass must probe these
   maps live**; the offline model is only useful for 269 / 271 / 273 / 274.
4. **The map-262 moving-platform hops are a timing puzzle.**
   `_cc76cc` (`{4,22}`) needs facing RIGHT + A + `$0270=1`; `_cc76f1` (`{9,22}`)
   needs facing LEFT + A + `$0271=1`. `$0270`/`$0271` are set for **2 object-script
   ticks each** by NPC_5's own movement loop
   (`event_main.asm:94259-94270` — `move RIGHT,3 / switch $0271=1 / wait 2 /
   switch $0271=0 / move LEFT,3 / switch $0270=1 / wait 2 / switch $0270=0`).
   So this is "press A toward the platform when it is next to you", a periodic
   window. No existing generator idiom covers it.
5. **The Vector guard row `_cc93dc` (§1c).** The natural BFS path to the factory
   door runs straight over `(56,39)` → forced `battle 29` → teleport to (34,58).
   Before the sneak scene the guards make the door NO-PATH; after it the party
   starts north of the trap. Sequence matters.
6. **The world band at (137,203)→(122,187) (§1b).** 32/32 tiles battle-enabled.
   Known-fatal for `worldNavTo`; use `worldGrind`.
7. **`_cc93e8` / `_cc941e` patrolling soldiers in Vector.** Map 242's map-init
   `_cc9540` (`event_main.asm:99721-99730`) does `collision_on NPC_6, NPC_11..16`
   while `$007B=0` — i.e. during v0.6 the soldier NPCs at (29,15), (24,6),
   (34,6), (24,14), (34,14), (22,21), (14,29) catch the party **on contact**
   (`_cc93e8` → `battle 29` / `_cc941e` → `battle 28`, both falling into
   `_cc93f4`'s teleport). Several have `movement RANDOM`. They are away from the
   §1d route, but a re-planning `navTo` that drifts north-west will find them.
8. **The Esper-World flashback is interactive and unmapped (§6a).** Treat it as
   a genuine leg, not a ride.
9. **`_cc8321` afterwards.** Once `$006B=1` (escape complete), re-entering
   Vector puts the invincible **Guardian `$0111` (battle 75)** on the south gate
   tiles `(30,59)`-`(34,59)` (`event_main.asm:97000-97012`). Do not route back
   through Vector after the escape.

---

## 9. Suggested fixture chain

Names are suggestions; the point is the split points.

| fixture | boot | ends at |
|---|---|---|
| `vector_doorstep` | post-Opera anchor | map 242, controllable near (46,39), pre-old-man |
| `vector_sneak_done` | ↑ | map 242 **(57,34)**, `$01F0=0`, guards bypassed |
| `mrf_entry` | ↑ | map 262 (28,8) |
| `mrf_chute` | ↑ | map 264 alcove ≈(10,7) — **needs live probing of 262/263** |
| `ifrit_doorstep` / `ifrit_won` | ↑ | battle 70; then `$0060=1`, `$0273=1` |
| `magicite_ifrit_shiva` | ↑ | `$0647=0`, `$0648=0`, Ifrit+Shiva owned |
| `n024_doorstep` / `n024_won` | ↑ | map 273 (25,52) facing (25,51); `$0649=0` |
| `esper_tubes` | ↑ | map 274, `$0068=1`, six espers, **Celes gone** |
| `minecart_doorstep` | ↑ | map 272, save point (3,55), one step from (20,13)… |
| `n128_won` | ↑ | after `cutscene TRAIN`; map 240 controllable, `$0069=1`, `$06AE=1` |
| `cranes_doorstep` | ↑ | map 240, one step from (52,40) |
| `cranes_won` | ↑ | after battle 71 on map 6 |
| `esper_world` | ↑ | map 219 (34,10), `$0338=1`, Maduin controllable |
| `terra_returned` | ↑ | **map 6, `$02F0=1`, `$0070=1`, `$016F=1`** — the v0.6 stop line |

---

## 10. What still needs a runtime probe

| # | question | what to measure |
|---|---|---|
| 1 | Does Shiva `$0108` enter battle 70 via the AI script? | `formationWords()`/`monsterIds()` at battle start and after monster turn 1 |
| 2 | Map 262 / 263 / 264 navigation | live `canStep`/`bfsPath` dumps at each landing tile; watch `$b2` (z) across the chute and platform hops; dump BG1 tiles before/after each `mod_bg_tiles` trigger |
| 3 | The `$0270`/`$0271` platform window | watch `$1E80+0x4E` bits 0/1 per frame on map 262 while NPC_5 loops; measure the duty cycle |
| 4 | Minecart duration | frame count from `cutscene TRAIN` to control on map 240; number of battles observed |
| 5 | Kill-bit adequacy for battles 70 / 72 / 73 / 71 | none of their post-battle tails read a battle switch (`if_b_switch`); confirm the win latches (`$0060`, `$0649`, and control return) |
| 6 | Terra's roster state at the stop line | `$1850+0`, `$1EDE`/`$1EDF`, `$1A6D`; open the party menu and confirm she is offered |
| 7 | Post-Opera roster base | `$1850+0..13` at the anchor (the "Locke + Celes" base is one measurement old) |
| 8 | The Esper-World flashback | full decode of maps 217/218/219: which NPC carries `_ca9fbf`, what sets `$0117`, z-splits |
| 9 | `_cc96c9`'s exit position | I read (57,34) off the `obj_script` move list; confirm live |

---

## Appendix — key addresses

| thing | citation |
|---|---|
| Vector world trigger | `event_trigger.asm:36-37` → `event_main.asm:14196` `_ca5ecf` |
| Vector old man (choice) | `npc_prop.asm:10770` → `event_main.asm:99897` `_cc9627`; `$01F0=1` at `:100017` |
| Vector sneak ledge | `event_trigger.asm:1067` → `event_main.asm:100025` `_cc96c9` |
| Vector "caught" trap | `event_trigger.asm:1070-1072` → `event_main.asm:99473` `_cc93dc` → `battle 29` |
| Factory door | map 242 long entrance `(57,2)` len 2 → map 262 `(28,8)` |
| Kefka esper-drain | `event_main.asm:94409` `_cc7451`, `switch $005F=1` `:94620` |
| Chute 263→264 | `event_main.asm:94649` `_cc7588`, `load_map 264` `:94665` |
| Ifrit / Shiva NPCs | `npc_prop.asm:12289`, `:12298` (map 264) |
| Ifrit fight | `event_main.asm:95260` `_cc7937`, **`battle 70` `:95283`** → formation 439 = `$0109` |
| esper hand-off | `event_main.asm:95331` `_cc79a4`; magicite `_cc79cd` `:95359`, `_cc79dd` `:95372` |
| Number 024 | `npc_prop.asm:12478` → `event_main.asm:95385` `_cc79ed`, **`battle 72`** → formation 441 = `$010a` |
| tube-room switch | `event_trigger.asm:1216` → `event_main.asm:95456` `_cc7a60` (facing UP + A) |
| six espers | `event_main.asm:95777-95782` |
| Celes leaves | `event_main.asm:96148-96158` |
| lift | `event_trigger.asm:1217` → `event_main.asm:96313` `_cc7f43` |
| minecart | `event_main.asm:96580` `cutscene TRAIN`; script `world/train_script.asm:615-660` |
| **Number 128** | `world/train_script.asm:899-917` `TrainCmd_e2`, event battle `$49` = **battle 73** → formation 442 = `$010b` + `$0140` + `$013f` |
| escape control point | `event_main.asm:96684-96690` (map 240, save point (58,7)) |
| Setzer joins | `event_main.asm:96980-96985` |
| Cranes | `event_main.asm:46907` `_cb3ff1` → **`battle 71`** `:47070` → formation 440 = `$010d` + `$010e` |
| Terra return chain | `event_main.asm:30250` `_cac3c7` → `:30361` `_cac4b0` → flashback → `:25241` `_caa4e0` |
| **Terra available** | `event_main.asm:25542` `switch $02F0=1` (= `$1EDE` bit 0) |
| v0.6 stop line | `event_main.asm:25669` `call _cacb95` (map 6, Blackjack cabin) |
| `$01B0`-`$01B7` decode | `notes/field-ram.txt:1072-1080`; `field/event.asm:5415-5433`, `:92`, `:5523`; `field/player.asm:529-531`; `include/const.inc:72-77` |
| `$02F0`-`$02FD` decode | `notes/field-ram.txt:1114-1116`; `field/event.asm:4443-4448`; `event_main.asm:30939-31010` |
| event-battle → formation | `field/battle.asm:506-517`; `field/event.asm:1907-1935`; `battle/battle_main.asm:16494-16505` |
| ROM/vanilla data identity | `ff6/rom/ff6-en.map:200,201,226,289,323,325` |

---

## 11. CORRECTIONS — measured on the minting pass, 2026-07-26

The route above was driven from the post-Opera anchor to the minecart
platform (map 272) and thirteen fixtures were minted from it.  Everything
in §1-§5 held except the items below.  Each correction cites the fixture
whose log measured it; all of them are in `build/states/last_run.log` at
mint time and in the generators' own assertions.

**§2 — Shiva IS in battle 70's formation (probe 1, answered).**  The recon
decoded battle 70 as formation 439 = "species `$0109` Ifrit only", said
"Shiva `$0108` is NOT in the formation ... she is not in *any* formation in
the game — I swept all 576", and listed her entrance as an open question.
Read live at the doorstep the instant the fight opens
(`gen_ifrit_doorstep.lua`'s post-mint verification, re-asserted in
`gen_ifrit_magicite.lua`), the formation species words `$57C0` are

```
0109 0108 0109 0108 FFFF FFFF
```

Shiva is present from the first frame.  No AI-script entrance is involved.
Whatever the offline `battle_monsters.dat` decode was reading, it was not
what the engine loads.

**§2 — the alcove is only half sealed.**  "They sit on the two doors:
Ifrit (3,8) is under `264 (3,5)→270` (the save room), Shiva (9,6) is under
`264 (9,5)→269`."  Only the second holds.  Shiva at (9,6) is the tile
directly below the (9,5) door and does make it NO-PATH; Ifrit at (3,8) is
three tiles below (3,5) and does not — the save room is 9 steps away and
reachable *before* the fight (`gen_ifrit_doorstep.lua`, `[doors]` log).

**§8 hazard 3 — map 262's upper floor is one region, not 130 tiles.**  The
offline model said only ~130 tiles were reachable from the factory door and
that `(4,22)`, `(11,45)`, `(12,60)`, `(22,53)`, `(22,54)` were NO-PATH.
Measured live from (28,8) (`gen_mrf_entry.lua`'s census), the upper floor is
a single connected region that contains BOTH chutes and BOTH door-animation
pairs — `(19,23)` 39 steps, `(19,25)` 41, `(21,25)` 43, `(9,22)` 44,
`(11,16)` 32, `(5,12)` 34 — while `(11,45)`, `(10,54)`, `(6,31)`, `(21,27)`,
`(4,22)`, `(22,53)`, `(22,54)`, `(12,60)` and `(15,60)` really are NO-PATH.
The *conclusion* stands (the lower half is entered only through scripts);
the tile count did not.

**§8 hazard 4 — the platform hop is not on the route.**  `(4,22)`/`(9,22)`
never have to be used: the way down is the ungated chute `_cc7771` on
`{19,25}`, which lands the party at `{10,45}`, and from there `{11,45}`'s
conveyor `_cc78d0` reaches `{20,45}` and `{22,53}` is 10 steps away.  The
`$0270`/`$0271` window was measured anyway (probe 3): over 600 frames each
switch opened **3 times for 12 frames**, i.e. a ~2% duty cycle on a ~200
frame period.

**§10 probe 4 — the ride is ~6400 frames and its six battles are exactly
as decoded.**  From `cutscene TRAIN` to the sixth fight: battles at frames
+212, +1381, +2405, +4101, +5477, +6445, in the order Mag Roader / Mag
Roader ×2 / Mag Roader / ×2 / ×2 / **`010B 0140 292A 013F`** — Number 128
with both blades.  `train_script.asm`'s course decode is confirmed.

**§10 probe 9 — the sneak scene's exit is exactly (57,34).**  Confirmed
live (`gen_vector_sneak.lua`), and `(57,2)` goes from NO-PATH to a 38-step
plan across the scene.

**§10 probe 5 — the kill-bit idiom does latch battles 70 and 72.**
`$0060`/`$0273` and `$0649` all move.  It does **not** get the party
through battle 73; see below.

**§10 probe 7 — the post-Opera roster, measured.**  `$1850+0..13` at the
anchor reads `00 C1 00 00 00 00 49 00 00 00 00 00 00 00` with `$1A6D=1`,
`$1EDE=$76`, `$1EDF=$88`.  So: LOCKE (`$C1`, order 0) and CELES (`$49`,
order 1) are the whole active party, and LOCKE, CYAN, EDGAR, SABIN, CELES
and GAU are available.  Unchanged at every doorstep down to the tube room.

### The thing the recon did not predict: the party is two, not four

`docs/design/bosses-wob.md` §13/§14 say "Locke, Celes + two" and §6e above
says "Locke + Celes".  **Both are describing a party the fixture chain does
not have.**  `event_main.asm:26287`, the Zozo departure, is

```
        char_party LOCKE, 1
        char_party CELES, 1
        party_menu 1, NO_RESET, {LOCKE, CELES}
```

— a four-slot menu with two characters forced and two slots free, and
`$1EDE`/`$1EDF` say CYAN, EDGAR, SABIN and GAU are all eligible.  The v0.5
leg that answered that menu confirmed it without adding anyone, so the
whole v0.6 chain runs two-handed, and after the tube room takes Celes
(`char_party CELES, 0`, :96154) it runs **one**-handed.

That is what stops the minecart.  Locke enters the ride solo at 501 HP,
loses ~70 per Mag Roader fight even with every fight kill-bitted three
frames after `battleLoadStarted()`, reaches Number 128 on 151, and dies.
`tools/tests/gen_n128.lua` and `tools/tests/probe_train_tail.lua` carry the
frame-by-frame measurement and the screenshot.  The fix is a v0.5 re-mint
(and a new post-Opera anchor), not a v0.6 route change and not a balance
edit.
