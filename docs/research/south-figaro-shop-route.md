# South Figaro: the honest shopping / resting stop

Every coordinate is `(x,y)` in field tiles.

---

## 0. The four shop events

South Figaro's four shops are opened at **`event_main.asm:18285-18313`**:

| label | line | shop | alt (`$00A4=1`) | type | map | NPC record |
|---|---|---|---|---|---|---|
| `_ca7860` | 18285 | 5 | 60 | Weapon | 77 | `npc_prop.asm:3465` `{103,9}` |
| `_ca786c` | 18292 | 6 | 61 | Armor  | 77 | `npc_prop.asm:3473` `{114,10}` |
| `_ca7878` | 18299 | 7 | 62 | Relics | 76 | `npc_prop.asm:3406` `{51,9}` |
| `_ca7884` | 18306 | **8** | 63 | **Item** | **85** | **`npc_prop.asm:3758` `{106,52}`** |

Map 85 — the item shop's interior — is reachable only from map 75
(`ShortEntrance::_85` has exactly one record, `+$07e6` → map 75 `(44,32)`).

---

## 1. Shop record format (so the row indices below are checkable)

`ShopProp` is `.incbin "shop_prop.dat"` at `ff6/src/menu/shop.asm:2309`;
1152 bytes = **128 records of 9 bytes** (the index is multiplied by 9
through the hardware multiplier at `shop.asm:1795-1802`).

- byte 0: bits 0-2 = shop type, bits 3-5 = price adjustment
  (`shop.asm:1802` `and #$07`; `AdjustShopPrice` `shop.asm:874-886`
  `and #$38`).
- bytes 1-8: eight item ids, `$FF` = empty (`shop.asm:819-827`; the buy
  loop runs `cpy #8` at `:846`).

Type names, `menu_text_en.inc:483-487`: 1 Weapon, 2 Armor, **3 Item**,
4 Relics, 5 Vendor.

Price = `ItemProp[item*30 + $1c]`, 16-bit (`CalcShopPrice`,
`shop.asm:874-881`; record size 30 from `item_prop_en.dat` being 7680
bytes for 256 items).

Neither `ff6/src/menu/shop_prop.dat` nor `ff6/src/menu/item_prop_en.dat`
has been touched by OT6 — `git log` on both shows only `fba50e7 flatten:
absorb ff6 disassembly into the main repo`.  The stock and prices below are
vanilla.

---

## 2. Shop 8 — the South Figaro ITEM shop

`shop_prop.dat` offset **`$0048`** (= 8*9), byte 0 = `$03`
→ type 3 (Item), price adjustment 0 (no markup).

| row `r` | id | name | price |
|---|---|---|---|
| 0 | `$E8` | Tonic | 50 |
| 1 | `$F2` | Antidote | 50 |
| 2 | `$F4` | Soft | 200 |
| 3 | `$F3` | Eyedrop | 50 |
| 4 | `$FB` | Echo Screen | 120 |
| **5** | **`$F0`** | **Fenix Down** | **500** |
| 6 | `$F6` | Sleeping Bag | 500 |
| 7 | `$F7` | Tent | 1200 |

So for the `gen_edgar` shop drive (`$7E9D89+r` = row item, `$7E9F09+2r` =
row price, row cell `$4B`):

- **Fenix Down = row 5, 500 GP each.**
- **Potion is not available.**  The nearest analogue on this shelf is
  **Tonic, row 0, 50 GP**.
- Figaro Castle's item shop (shop 4, `event_main.asm:15480`, map 59) has
  the same profile — Tonic + Fenix Down, no Potion.  The nearest Potion
  vendor reachable in the world at all is shop 3 on **map 26**, a Narshe
  interior (`ShortEntrance::_26` `+$02d6` `(44,14)` → map 20 `(41,24)`;
  map 20 is Narshe exterior per `docs/research/world-map-nav.md`), and
  Narshe is in a different walkable world region from the Figaro desert
  (`gen_kolts.lua` header, finding 2).

The alternate, **shop 63** (`$0237`, taken when `$00A4=1`) is
`Potion, Tincture, Eyedrop, Echo Screen, Fenix Down, Revivify, Remedy,
Tent`.  `$00A4` is set exactly once, at `event_main.asm:12423`, inside the
Locke/Celes escape scene (`norm_lvl CELES` / `max_hp CELES` two lines
later) — i.e. **long after** the Terra+Locke+Edgar visit.  Every other
`$00A4` mention in `event_main.asm` is a test, not a set (57214, 62376,
65400 are all inside `if_any` blocks).  **At the pre-Kolts stage `$00A4=0`
and the base shops 5/6/7/8 are what open.**

---

## 3. The route: map 75 (1,28) → the item merchant

### 3.1 Legs

```
leg 1  map 75: walk (1,28) -> (44,32)                    [73 steps, BFS]
leg 2  map 75: at (44,32) HOLD UP
         -> first UP press opens the door (CheckDoor), party does not move
         -> next two UP steps: (44,31), (44,30)
         -> (44,30) is ShortEntrance +$0726 -> map 85 (104,57), facing UP
leg 3  map 85: walk (104,57) -> (106,54)                 [5 steps, BFS]
leg 4  map 85: face UP, press A
         -> talks ACROSS the counter (106,53) to NPC index 2 at (106,52)
         -> _ca7884 -> shop_menu 8
return map 85: walk (106,54) -> (104,58) [6 steps]; (104,58) is
         ShortEntrance +$07e6 -> map 75 (44,32), facing DOWN
```

### 3.2 The door is a BUMP entrance, not a walkable tile

`(44,30)` on map 75 is BG1 tile `$05` whose `TOWN_EXT` property byte is
`p1 = $F7` — **fully impassable**.  The tile below it, `(44,31)`, is tile
`$15`, `p1 = $23` (walkable, plus the `$20` "door" bit).

`CheckDoor` (`ff6/src/field/player.asm:959-1005`):

- returns unless the party is facing UP or DOWN (`:960-966`,
  `lda $087f,y / lsr / bcs return`);
- facing UP it reads `$a7`, which `UpdateLocalTiles` (`player.asm:1379-1440`)
  fills with the tile at `(x, y-1)`, and requires it to be `$15`
  (`:978`), with the door's own position `$90 = y-2` (`:967-970`);
- it then checks `$7e7615 & $20` (the `$15` prop's door bit, `:979-985`)
  and `ModifyMap`s tiles `$04/$14` over `(x,y-2)/(x,y-1)`
  (`OpenDoorTiles1`, `:1063-1066`).

So the **doorstep is `(44,32)`**: from there `(44,31)` is `$15` and the
door being opened is `(44,30)`.  `CheckDoor` is called before
`CheckPlayerMove` on every directional press (`player.asm:463/476/489/502`)
and the frame the door opens the party does **not** step
(`bne @49ef`, `:490-491`) — so this leg must be a *held* UP, not a tap.
After the open, `$04`/`$14` both carry `p1 = $03` (walkable) and the two
UP steps land the party on `(44,30)`, where `CheckShortEntrance`
(`entrance.asm:269-300`, exact `$af` XY match) fires.

Independent confirmation that `(44,32)` is the doorstep: the reverse record
`ShortEntrance` `+$07e6` puts the party back on map 75 at exactly
`(44,32)`.

Nine of map 75's twelve short-entrance sources are `$F7` door tiles like
this — see the hazard table in section 6, which is why they are *not* BFS
hazards.

### 3.3 The verified map-75 path

Static BFS over the engine's own step rule (see section 8), party z-level
2, with the nine init-spawned NPCs treated as occupied:

```
(1,28) (2,28) (3,28) (4,28) (5,28) (5,29) (5,30) (5,31) (5,32) (5,33)
(6,33) (6,34) (7,34) (8,34) (9,34) (10,34) (11,34) (12,34) (12,33)
(13,33) (14,33) (15,33) (16,33) (17,33) (18,33) (19,33) (20,33) (21,33)
(22,33) (23,33) (24,33) (24,34) (24,35) (24,36) (25,36) (26,36) (27,36)
(28,36) (29,36) (30,36) (30,37) (30,38) (30,39) (30,40) (30,41) (30,42)
(31,42) (32,42) (33,42) (34,42) (34,43) (34,44) (34,45) (34,46) (35,46)
(36,46) (37,45) (38,44) (38,43) (38,42) (39,42) (39,41) (40,41) (41,40)
(42,39) (42,38) (42,37) (42,36) (42,35) (42,34) (42,33) (42,32) (43,32)
(44,32)
```

73 steps.  **No hazard tile lies on any shortest path** — checked by
computing `d((1,28),h) + d(h,(44,32))` for every hazard `h` in section 6
and confirming none equals 73.  A shortest-path BFS therefore cannot
wander onto one by tie-breaking, but the assertion is still worth writing
(the harness's BFS and mine are two implementations of the same rule, not
the same code).

### 3.4 Inside map 85

Map 85's walkable region around the arrival tile is exactly 30 tiles:

```
x=102..107, y=54..57   (the customer floor)
x=103..104, y=51..53   (the left aisle)
x=106..107, y=54..55   plus (104,58) — the exit tile
```

Path `(104,57) → (104,56) → (104,55) → (104,54) → (105,54) → (106,54)`,
5 steps.

---

## 4. The merchant interaction — it is a COUNTER talk

The item merchant stands at `(106,52)`, `p1 = $02` (walkable), enclosed by
counter tiles.  The party **cannot** stand adjacent to him:

| tile | `p1` | meaning |
|---|---|---|
| `(105,50)` `(105,51)` `(105,52)` | `$07` | counter (`&7 == 7`, not `$F7`) |
| `(106,53)` `(107,53)` | `$07` | counter |
| `(104,52)` `(106,54)` | `$02` | walkable |

`CheckNPCs` (`ff6/src/field/player.asm:142-200`) handles this: when the
tile the party faces holds no object (`:172-174`,
`lda $7e2000,x / bmi @478e`), it falls into the counter branch at
`player.asm:188-200` —

```
lda $7e7600,x ; cmp #$f7 ; beq return      ; adjacent tile fully impassable
and #$07 ; cmp #$07 ; bne return           ; not a counter -> nothing to do
... adc ThruTileOffsetX/Y ...              ; go ONE MORE tile that way
lda $7e2000,x ; bmi return                 ; is there an NPC there?
```

So there are two working talk spots:

- **`(106,54)` facing UP** → counter `(106,53)` → merchant `(106,52)`.
  *Preferred*: the merchant's own `set_npc_dir DOWN` makes it
  face-to-face, and it is tied for shortest (5 steps).
- `(104,52)` facing RIGHT → counter `(105,52)` → merchant `(106,52)`.
  Also 5 steps; kept as the fallback if the first is ever wrong.

**NPC record** (`ff6/src/event/npc_prop.asm:3758-3764`, third record of
`NPCProp::_85` which starts at `:3740`):

```
make_npc {106, 52}, $0300
        set_npc_event _ca7884
        set_npc_dir DOWN
        set_npc_speed SLOW
        set_npc_gfx SHOPKEEPER, LOCKE
        end_npc
```

- **NPC index 2** on map 85 → **object number 18** (`2 + 16`).
- Spawn switch `$0300`.  `make_npc` stores `switch_id - $0300`
  (`npc_prop.asm:105-115`), and `InitNPCSwitches` copies
  `init_npc_switch.dat` to **`$1EE0`** = `$1E80 + $60` = event bit `$0300`
  (`ff6/src/field/obj.asm:176-187`).  `init_npc_switch.dat[0] = $BB`, bit
  0 set → **the merchant is spawned from game start** and nothing in
  `event_main.asm` ever clears `$0300`.
- The other two `NPCProp::_85` records — `{103,51}` and `{107,55}` — carry
  switch `$030C`, whose init bit is **0** (`init_npc_switch.dat[1] = $AB`,
  bit 4 clear).  `$030C` is set only by `_ca84ab`
  (`event_main.asm:20206`), the Empire-occupation setup in Locke's
  scenario.  **At the pre-Kolts stage the merchant is the only NPC on
  map 85.**
- `set_npc_no_react` is *not* set on him, and would not matter anyway: it
  becomes `$087c` bit 5 (`NPC_REACT::NONE = 1<<2`,
  `ff6/include/event/npc_prop.inc:40-44`, `asl3` at
  `ff6/src/field/obj.asm:348-353`), whereas the "cannot be talked to"
  gate `CheckNPCs` uses is `$087c & $40` (`player.asm:181-183`), which comes
  from `NPC_MOVEMENT`.

The event it runs (`event_main.asm:18306-18309`):

```
_ca7884:
        if_switch $00A4=1, _ca788d
        shop_menu 8
        return
```

No dialogue, no `player_ctrl_off` preamble — A opens the shop menu
directly, which is exactly the shape `gen_edgar.lua`'s shop drive expects.

---

## 5. The inn

### 5.1 Where it is

**Innkeeper: map 76, NPC index 3 (object number 19), tile `{81,17}`,
facing DOWN, spawn switch `$0300`** — `npc_prop.asm:3414-3420`, fourth
record of `NPCProp::_76` (`:3388`):

```
make_npc {81, 17}, $0300
        set_npc_event _ca7894
        set_npc_no_react
        set_npc_dir DOWN
        set_npc_speed SLOW
        set_npc_gfx SHOPKEEPER, LOCKE
        end_npc
```

Also a **counter talk**: `(81,18)` is `p1 = $07`, `(81,19)` is `p1 = $02`.
**Stand at `(81,19)`, face UP, press A.**

This is confirmed independently by the rest script itself: `_ca789f`
(`event_main.asm:18326-18355`) walks the party `move LEFT, 4` then
`move UP, 2` — from `(81,19)` that is `(77,19)` then `(77,17)` — and then
`mod_bg_tiles BG1, {77, 15}, {1, 2}` with `$04/$14`, i.e. it opens the
door at `(77,15)`, which is BG1 tile `$05` in the `SOUTH_FIGARO_INT` map.
**The scripted walk only lands on the door if the party is standing on
`(81,19)` when A is pressed.**

### 5.2 Getting there

Map 76's only entrance from map 75 is `ShortEntrance` **`+$070e`**:
map 75 `(15,37)` → map 76 `(52,14)`.  `(15,37)` is another `$05`/`$F7`
door tile with `$15` below it, so the **doorstep is `(15,39)`** — and
again the reverse record `+$0732` (map 76 `(52,15)` → map 75 `(15,39)`)
agrees.

Map 76's interior is **two disjoint regions** joined by a same-map short
entrance pair (`+$0738` `(48,3)` → `(69,10)`; `+$073e` `(70,11)` →
`(49,4)`):

- region A, 50 tiles around `x=48..56, y=3..15` — the **relic shop**
  (shop 7, NPC `{51,9}`), with a diagonal staircase (`p1` bit 7 / bit 6
  tiles `$C5=$8B`, `$D6=$83`) climbing to `(48,3)`;
- region B, 245 tiles around `x=67..90, y=7..21` — the **inn**.

```
leg 1  map 75: walk (1,28) -> (15,39)                    [25 steps]
leg 2  map 75: at (15,39) HOLD UP -> door (15,37)
         -> ShortEntrance +$070e -> map 76 (52,14)
leg 3  map 76: walk (52,14) -> (48,3)                    [17 steps]
         (52,14)(52,13)(52,12)(52,11)(53,11)(53,10)(53,9)(54,9)(55,9)
         (55,8)(55,7)(54,7)(53,6)(52,5)(51,5)(50,5)(49,4)(48,3)
         -- (49,4) and (48,3) are DIAGONAL steps (p1 bit7/bit6); the
            lib's diagonal branch already models these
            (tools/tests/lib/ot6_field.lua:122-141, diagStep)
leg 4  (48,3) is ShortEntrance +$0738 -> map 76 (69,10)
leg 5  map 76: walk (69,10) -> (81,19)                   [26 steps]
         (69,10)(68,9)(67,9)(67,10)..(67,17)(68,17)(69,17)(70,17)
         (70,18)(71,18)..(78,18)(78,19)(79,19)(80,19)(81,19)
leg 6  face UP, press A -> _ca7894
```

Total from `(1,28)`: 25 + 17 + 26 = 68 walked steps, three map loads.

There is a second way into region B — map 75 `(22,42)` door → map 78
`(26,52)`, walk 25 to map 78 `(28,36)`, `ShortEntrance +$0756` → map 76
`(87,20)`, walk 7 to `(81,19)`: 37 + 25 + 7 = 69 steps.  **Prefer the
first**: map 78's init event `_caec39` (`event_main.asm:34980-35000`)
runs an ASYNC `obj_script NPC_9` that does `pos {26,53}` — one tile from
the arrival tile — and then walks it north across the room, whenever
`$0303=1 && $00A4=0`, which is exactly our stage.

From the item shop, `(44,32) → (15,39)` on map 75 is 56 steps, so
shop-then-inn is the natural order.

### 5.3 What it costs and what it restores

`event_main.asm:18318-18355`:

```
_ca7894:
        dlg $0B89        ; "80 GP per night! Well?  0: Yes  1: No"
        choice _ca789f, EventReturn
        return
_ca789f:
        take_gil 80
        if_switch $01BE=1, _cb69ff        ; -> dlg $0B19 "……Not enough money."
        ... walk to the bed, open (77,15), call _cacd3c ...
        load_map 76, {81, 9}, DOWN, {ASYNC, Z_UPPER, NO_FADE_IN}
        obj_script SLOT_1  pos {83, 7}  dir DOWN  end
        ... call _cacf98
```

- **Cost: 80 GP.**  `take_gil` sets `$01BE` when the party cannot pay, and
  the script then bails to `_cb69ff` (`event_main.asm:53769`, "……Not
  enough money.") **without** resting.  A fixture must assert gold ≥ 80
  before this, or it will silently get nothing.
- The heal is inside `_cacd3c` → `_cacf67` (`event_main.asm:31802-31833`),
  whose tail is `call _cacfbd`.

`_cacfbd` (`event_main.asm:31862-31875`) is, for all four slots:

```
and_status SLOT_n, {MAGITEK, INTERCEPTOR}
max_hp     SLOT_n
max_mp     SLOT_n
```

- `and_status` is event command `$88` with a 16-bit **keep** mask
  (`ff6/include/event_cmd.inc:557-559,589`; the mask is built over
  `STATUS14`).  `EventCmd_88` (`ff6/src/field/event.asm:3310-3327`) does
  `lda $1614,y / and $ec / sta $1614,y` — `$1614` is the persistent
  status word (status 1 low byte, status 4 high byte).
- The mask keeps only `MAGITEK` (`STATUS1::MAGITEK = BIT_3`) and
  `INTERCEPTOR` (`STATUS4::INTERCEPTOR = BIT_6 << 8`)
  — `ff6/include/const.inc:1488-1536`.  Everything else is cleared,
  **including `STATUS1::DEAD = BIT_7`**.
- `max_hp` is command `$8b` with `$7f` (`event_cmd.inc:595`), and
  `EventCmd_8b`'s `$7f` branch (`event.asm:3407-3411`) writes
  `CalcMaxHP`'s result straight to `$1609,y` with no "is alive" guard.
  Order matters and is correct: statuses are cleared first, HP restored
  second.

**So: the South Figaro inn costs 80 GP and restores full HP, full MP, and
clears every persistent status including KO.  It does revive.**  (This is
the standard FF6 inn routine — `_cacd3c` is shared; the 150 GP inn at
`event_main.asm:21561` calls the same thing.)

---

## 6. Hazards

### 6.1 Map 75 — the full transition inventory

Decoded from `ff6/src/field/trigger/long_entrance.dat` /
`short_entrance.dat` using the pointer tables in
`ff6/include/field/{long,short}_entrance.inc` (`_75 := LongEntrance +
$010a`, `_75 := ShortEntrance + $06ea`).  Record layout from the same
`.inc` files: short = `SrcX,SrcY,Map(word),DestX,DestY` (6 bytes), long =
`SrcX,SrcY,Length,Map(word),DestX,DestY` (7 bytes); the length byte's
bit 7 selects vertical (`entrance.asm:65-66`), and the span is
`Src..Src+Length` **inclusive** (`entrance.asm:70-77`,
`cmp / bcs DoEntrance`).

`p1` is the `TOWN_EXT` property byte for the tile that actually sits
there.  `d` is the static BFS distance from `(1,28)`; `—` means
unreachable from the spawn region.

**Long entrances** (`long_entrance.dat`):

| off | span | → | `p1` | `d` | note |
|---|---|---|---|---|---|
| `+$010a` | **column x=0, y=0..47** (V, len `$AF`) | world | `$02` | **1** | party spawns one tile away |
| `+$0111` | column x=56, y=0..47 (V, len `$AF`) | world | `$02` | — | see 6.3 (wrap) |
| `+$0118` | **row y=1, x=0..63** (H, len `$3F`) | world | `$02` | 48 | reachable at x=21..24 only |
| `+$011f` | **(18..20, 55)** (H, len 2) | map 91 `(9,2)` | `$0A/$02` | 45 | |
| `+$0126` | **(8..10, 32)** (H, len 2) | map 80 `(88,46)` | `$02` | **16** | *the one `gen_kolts` does not document* |

`gen_kolts.lua`'s header is **correct but incomplete**: it names the two
vertical columns and `y=1`, and omits `(18..20,55)` and `(8..10,32)`.
`(8..10,32)` is the dangerous one — 16 steps from the spawn, in the same
quadrant the route crosses (the derived path passes `(8,34)`/`(9,34)`,
two rows below it).

**Short entrances** (`short_entrance.dat`, `_75` = `+$06ea`):

| off | src | → | `p1` | `d` | hazard? |
|---|---|---|---|---|---|
| `+$06ea` | (15,18) | 81 (4,16) | `$F7` | — | no — `$05` door |
| `+$06f0` | (23,15) | 81 (16,15) | `$F7` | — | no — door |
| `+$06f6` | (22,14) | 86 (8,27) | `$02` | — | steppable, but outside the spawn region |
| `+$06fc` | **(48,37)** | 86 (52,29) | `$03` | 26 | **yes — plain floor** |
| `+$0702` | **(34,35)** | 86 (4,6) | `$02` | 46 | **yes — plain floor** |
| `+$0708` | (37,40) | 86 (36,22) | `$F7` | — | no — door |
| `+$070e` | (15,37) | 76 (52,14) | `$F7` | — | no — door (**the inn's**) |
| `+$0714` | (22,42) | 78 (26,52) | `$F7` | — | no — door |
| `+$071a` | (29,17) | 77 (103,16) | `$F7` | — | no — door (weapon shop) |
| `+$0720` | (35,17) | 77 (114,16) | `$F7` | — | no — door (armor shop) |
| `+$0726` | **(44,30)** | **85 (104,57)** | `$F7` | — | the **item shop** door |
| `+$072c` | (46,39) | 86 (49,54) | `$F7` | — | no — door |

That is the useful structural finding: **on map 75 only two short
entrances and two long-entrance rows are walk-onto hazards**; every other
building door is an `$F7` tile that a BFS over the engine's rule cannot
route through in the first place.

**Consolidated BFS blocklist for map 75:**

```
(8,32) (9,32) (10,32)          -> map 80
(18,55) (19,55) (20,55)        -> map 91
(48,37)                        -> map 86
(34,35)                        -> map 86
(22,14)                        -> map 86
(0,y) for y=0..47              -> world
(56,y) for y=0..47             -> world
(x,1) for x=0..63              -> world
```

### 6.2 Event triggers on the path

Map 75 has exactly **one** event trigger: `EventTrigger::_75` =
`make_event_trigger {23,17}, _ca7b46` (`event_trigger.asm:317-318`).
`_ca7b46` (`event_main.asm:18704-18711`) is
`if_any switch $001A=0 / $001E=1 / $01F0=1 -> EventReturn` — at the
pre-Kolts stage `$001A=0`, so it is a no-op.  It is not on the derived
path anyway.

Map 85 has exactly one: `{104,58}` → `_ca8007` (`event_trigger.asm:365`;
`event_main.asm:19399-19402`), which is
`if_switch $00A4=0, EventReturn` and then `load_map 74` — the WoR
redirect.  At our stage it returns immediately and the co-located
**short entrance `+$07e6` back to map 75 is what actually fires**.

Map 75's *init* event is `_caeba1` (`map_init_event.asm:94`;
`event_main.asm:34876-34979`):

- `if_switch $01B6=1 -> return`;
- **first visit only** (`$000A=0`): `create_obj NPC_6 / show_obj / ASYNC
  obj_script` walking NPC 6 (the `{48,44}` townsman) DOWN 4, RIGHT 7,
  DOWN_RIGHT 2, DOWN 2, RIGHT 6, DOWN 5, RIGHT 3, UP 1, `hide_obj`, then
  `switch $000A=1`.  The walk goes **south-east away from the route**
  (max route x is 44), but it is asynchronous and it is a moving object;
- the `$0101` / `$0102` cross-town NPC walks are gated on switches set
  only by the map-78 cider scenes (`event_main.asm:19081`, `:19140`) in
  Locke's scenario, so they do not run here;
- `$030C` (the Imperial-soldier choreography at `:34895`) is 0 here.

### 6.3 The x-wrap is real

`H.maptile` masks coordinates with `$86`/`$87`
(`tools/tests/lib/ot6_field.lua:117-120`), and so does the engine
(`player.asm:1405-1412`, `and $86` / `and $87`).  Map 75's masks are
`$3F/$3F` (`map_prop.dat` record `33*75 + 23 = $AA`; `$AA>>6 = 2` and
`($AA>>4)&3 = 2` index `ScrollClipTbl` = `$3F`,
`ff6/src/field/scroll.asm:242-320`).  **So x=0 and x=63 are neighbours.**
In my static model the entire `x=56` world-exit column is reachable *only*
through that wrap (blocking `x=0`/`x=63` removes all of it), and stepping
on `x=0` fires the world exit first — so it is not a live hazard for a
party spawning at `(1,28)`.  It is still worth an assertion, because a
BFS that ever plans a leftward leg from the west edge would tunnel.

### 6.4 The other doorsteps are one step from an exit

Both landing tiles on this route sit adjacent to their own return trigger:

- map 75 `(1,28)` is one LEFT step from `(0,28)` (world);
- map 85 `(104,57)` is one DOWN step from `(104,58)` (back to map 75);
- map 76 `(69,10)` is one step from `(70,11)` (back to `(49,4)`);
- map 76 `(52,14)` is one DOWN step from `(52,15)` (back to map 75).

Each of the derived paths above steps *away* from its trigger on the first
move, but every one of these deserves an explicit assert.

### 6.5 No random encounters anywhere on this route

Random battles are gated on `$0525` bit 7 (`ff6/src/field/battle.asm:332`,
`lda $0525 / bpl Done`), i.e. `map_prop.dat` record `33*map + 5`.  That
byte is `$00` for maps **75, 76, 77, 78, 80, 85, 86** — all zero, no
encounters.  (For contrast the cave maps 70/72/73 are `$80`.)  So the
shopping/resting stop needs no `honest="flee"` handling of its own; only
the approach through the cave does.

---

## 7. Story gating — is anything closed at this stage?

Nothing blocks the town.

- **NPC spawn switches.**  `init_npc_switch.dat` (128 bytes, base event bit
  `$0300`) has `[0]=$BB [1]=$AB`.  For map 75: `$0303`, `$0304`, `$0305`,
  `$0307` are **set** (the nine townsfolk, `npc_prop.asm:3196-3270`), and
  `$030A`, `$030C`, `$0318`, `$0319`, `$031B`, `$0360` are **clear** (the
  Empire-occupation cast).  Nothing in `event_main.asm` sets the latter
  before `_ca84ab` (`:20204-20213`), which is the Locke-scenario setup.
- **The four shop NPCs and the innkeeper are all switch `$0300`**, bit 0
  of `init_npc_switch.dat[0] = $BB` → set from game start, never cleared.
- **The shop alternates are all `$00A4`-gated** and `$00A4=0` here (§2).
- **The interior→exterior redirect events** (`_ca7f78` … `_ca8021`,
  `event_main.asm:19355-19412`), which would send exits to map 74 instead
  of map 75, are every one of them `if_switch $00A4=0, EventReturn`.  At
  this stage all interiors return to map 75 exactly as the short-entrance
  records say.
- The only town NPC that stands *in the way* of anything is the relic
  demonstrator at map 76 `{51,11}` (switch `$0358`, init bit **set**;
  `npc_prop.asm:3422-3427`).  He occupies the *only* tile from which the
  relic shopkeeper at `{51,9}` can be counter-talked, and he despawns via
  `switch $0358=0` at the end of his own scene (`event_main.asm:18394`).
  **This does not affect the item shop or the inn**, but it means a
  "buy relics in South Figaro" fixture has to talk to him first.

---

## 8. How the walkable model was built (so it can be re-derived or refuted)

No emulator was run.  The tilemap and tile properties were reconstructed
statically:

1. `map_prop.dat` is 415 records of **33 bytes** (`LoadMapProp`,
   `ff6/src/field/map.asm:143-158`, copies 33 bytes to `$0520`).  Byte 4
   = `$0524` = tile-property index (`LoadTileProp`, `map.asm:177-193`);
   bytes 13-14 = `$052D` = BG1 layout index, `& $03FF` (`LoadMapTiles`,
   `map.asm:1753-1766`); byte 23 = `$0537` = the size-mask packing
   (`InitScrollClip`, `scroll.asm:298-320`).
2. Map 75 → layout **7** = `SUB_TILEMAP::SOUTH_FIGARO_EXT_BG1`, tile prop
   **4** = `MAP_TILE_PROP::TOWN_EXT`, masks `$3F/$3F` → **64x64**.
   Maps 76/77/78/85/86 → layout **32** = `SOUTH_FIGARO_INT_BG1`, tile prop
   **7** = `TOWN_INT`, masks `$7F/$3F` → **128x64** — i.e. *all five South
   Figaro interior maps are views into one shared 128x64 tilemap*,
   differing only in NPC list, entrances and triggers.
3. The uncompressed sources are checked in next to the `.lz` files:
   `sub_tilemap/south_figaro_ext_bg1.dat` (4096 B = 64*64),
   `sub_tilemap/south_figaro_int_bg1.dat` (8192 B = 128*64),
   `map_tile_prop/town_ext.dat` and `town_int.dat` (512 B each =
   256 `p1` bytes at `$7E7600` + 256 `p2` bytes at `$7E7700`).
   `CopyMapTiles` (`map.asm:1869-1960`) lays the file out at `$7F0000`
   with a row stride of 256, so `tile(x,y) = file[y*width + x]` and
   `p1 = tileprop[tile]`, `p2 = tileprop[256 + tile]`.
4. The step rule is a transcription of
   `tools/tests/lib/ot6_field.lua:135-187` (`stepAllowed` / `diagStep`),
   which is itself the documented port of `player.asm:368-453` and
   `CheckPlayerMove` `player.asm:1072-1120`.  Object occupancy was
   modelled from the NPC records whose spawn switch is set in
   `init_npc_switch.dat`.

Sanity checks that the model is not fantasy, all of which passed:

- every one of map 75's `$05` door tiles has its `$15` partner one row
  below and a walkable tile below that, and each of those matches the
  destination coordinate of the *reverse* short-entrance record
  (`(44,32)`, `(15,39)`, `(22,44)`);
- the innkeeper's talk spot `(81,19)` is the only tile from which
  `_ca789f`'s hard-coded `LEFT 4 / UP 2` lands on the bed-room door at
  `(77,15)`, which is a `$05` tile;
- map 85's derived room is closed except for `(104,58)`, which is exactly
  the map's single short-entrance source and its single event trigger.

---

## 9. What I could NOT establish, and the probe for each

1. **Whether the harness's live BFS picks the same paths.**  Mine is a
   second implementation of the same rule against ROM data; the harness
   reads `$7F0000`/`$7E7600` from a running machine, where `ModifyMap` may
   have changed tiles (opened doors, opened chests).  *Probe:* a
   `probe_sfig.lua` that loads `build/states/south_figaro.mss`, asserts
   `H.mapId()&0x1ff == 75`, dumps `$86/$87` (expect `$3F/$3F`), memcmps
   `$7F0000` row-by-row against `south_figaro_ext_bg1.dat`, and prints
   `H.fieldBfs((1,28) -> (44,32))` length (expect 73).
2. **The party z-level `$b2` on arrival at `(1,28)`.**  I assumed 2
   (lower), taken from `p1(1,28) = $02`; the entrance flags say
   `$0744 = 1` (upper) by default (`entrance.asm:325-340`).  Every tile on
   the route is `$02`/`$03`, so the z-tracking cannot change the answer,
   but I did not verify the seed.  *Probe:* read `$00b2` at settle in the
   same probe.
3. **Whether NPC 6's ASYNC first-visit walk is still in flight in
   `south_figaro.mss`.**  `$000A` is set by `_caeba1` on the first load, so
   a fixture minted at `(1,28)` has already started it.  *Probe:* read
   event bit `$000A` and `$7E2000` occupancy along the route at settle,
   and re-read after 600 frames.
4. **Whether the counter-talk actually opens shop 8.**  The mechanism is
   read, not run.  *Probe:* the mint itself — stand at `(106,54)`, face
   UP, tap A, assert `ZMENUSTATE $25` reaches the shop options state and
   `$7E9D89+5 == $F0`.
5. **Gold.**  Fenix Down is 500 GP and the inn is 80 GP; I did not check
   what the party carries at `figaro_cleared`.  Both `take_gil` (inn) and
   the shop fail *quietly* when short.  *Probe:* assert gold before each,
   in the generator.
6. **Map 76 leg 3's diagonal staircase.**  `(49,4)` and `(48,3)` are
   diagonal-only steps in my model (`p1` bit 7/bit 6).  The lib models
   these (it was built for Figaro's staircases) but this particular
   staircase has never been walked by a fixture.  *Probe:* only needed if
   the inn stop is built; the shop stop does not touch map 76.

---

## 10. Appendix — the other three South Figaro shops

For completeness; all four are pre-`$00A4` and all four are open now.

| shop | type | map | via | doorstep on 75 | merchant | talk spot |
|---|---|---|---|---|---|---|
| 5 | Weapon | 77 `(103,16)` | `+$071a` (29,17) | `(29,19)` | `{103,9}` | `(103,11)` face UP (counter `(103,10)`) |
| 6 | Armor | 77 `(114,16)` | `+$0720` (35,17) | `(35,19)` | `{114,10}` | `(114,12)` face UP (counter `(114,11)`) |
| 7 | Relics | 76 `(52,14)` | `+$070e` (15,37) | `(15,39)` | `{51,9}` | `(51,11)` face UP (counter `(51,10)`) — **blocked by the `$0358` NPC until he is talked to** |
| 8 | Item | 85 `(104,57)` | `+$0726` (44,30) | `(44,32)` | `{106,52}` | `(106,54)` face UP (counter `(106,53)`) |

Stock, for the record:

- shop 5 (Weapon): `$00 $01 $0A $0B $A3 $A4`
- shop 6 (Armor): `$5A $5B $6A $6B $85 $86`
- shop 7 (Relics): `$E6` (Sprint Shoes) `$B0 $B1 $B5 $BE`
- shop 8 (Item): see §2
