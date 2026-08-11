# Field care: heal and revive through the field menu

Scope: opening the field menu, using a consumable (Potion `$E9`, Tonic `$E8`,
Fenix Down `$F0`) on a party member, and casting a field heal spell
(Cure `$2D`), using only pad input and memory reads.

---

## 1. Menu state names and the dispatcher

`zMenuState` (`$26`) indexes `MenuStateTbl` every frame
(`menu_common.asm:273-289`, table at `menu_common.asm:291-424`). The symbolic
names live in `menu_ram.inc:3-40`:

| State | Enum name | Handler |
|---|---|---|
| `$00` | `FADE_OUT` | `field_menu.asm:515` |
| `$01` | `FADE_IN` | `field_menu.asm:527` |
| `$02` | `WAIT_FADE` | `field_menu.asm:539` |
| `$03` | `FIELD_MENU_REINIT` | `field_menu.asm:550` |
| `$04` | `FIELD_MENU_INIT` | `field_menu.asm:31` |
| `$05` | `FIELD_MENU_SELECT` | `field_menu.asm:563` |
| `$06` | `FIELD_MENU_CHAR` | `field_menu.asm:611` |
| `$07` | `ITEM_INIT` | `field_menu.asm:67` |
| `$08` | `ITEM_SELECT` | `field_menu.asm:804` (inside `.proc MenuState_08_proc`, `field_menu.asm:800`) |
| `$09` | `SKILLS_INIT` | `field_menu.asm:169` |
| `$0A` | `SKILLS_SELECT` | `field_menu.asm:990` |
| `$17` | `ITEM_OPTIONS` | `field_menu.asm:2080` |
| `$18` | `ITEM_RARE` | `field_menu.asm:2285` |
| `$19` | `ITEM_MOVE` | `field_menu.asm:2314` |
| `$1A` | `SKILLS_MAGIC` | `field_menu.asm:2368` |

States above `$21` have no enum names; the ones on our paths are:

| State | What it is | Handler |
|---|---|---|
| `$3A` | magic target (init) | `field_menu.asm:2810` |
| `$3B` | magic target (single target) | `field_menu.asm:2851` |
| `$3C` | return to magic list after casting | `field_menu.asm:3219` |
| `$3D` | magic target (all targets) | `field_menu.asm:3264` |
| `$6F` | use item — character select (init) | `item.asm:2132` |
| `$70` | use item — character select | `item.asm:2145` |
| `$77` | item select (init, returning from target select) | `field_menu.asm:146` |

### `$00`/`$01`/`$02` are a three-state fade

`MenuState_00` creates the fade-out task, sets `zWaitCounter` = 8 and
immediately becomes `$02` (`field_menu.asm:515-522`). `MenuState_01` is the same
with a fade-in task (`field_menu.asm:527-534`). `MenuState_02` idles until
`zWaitCounter` (`$20`, 16-bit) hits 0 and then loads `zNextMenuState` (`$27`)
into `zMenuState` (`field_menu.asm:539-545`).

Every fade transition is 1 frame in `$00`/`$01`, 8 frames in `$02`, then the
target. A poller that waits for an exact state must expect `$02`, and must not
treat `$02` as still being in the previous screen.

---

## 2. Item path: exact state machine

### 2.1 Field menu → item list

```
field  --X-->  $05 (main menu)
```
(the X-to-open is field code, outside `src/menu`; not re-derived here)

In `$05`, A calls `SelectMainMenuOption` (`field_menu.asm:563-570`,
`field_menu.asm:3409-3416`), which copies `$4B` into `z25` (`$25`, "main menu
selection") and jumps through `SelectMainMenuOptionTbl`
(`field_menu.asm:3420-3427`):

| `$4B` | option | label | target |
|---|---|---|---|
| 0 | Item | `menu_text_en.inc:43` | `SelectMainMenuOption_00`, `field_menu.asm:3443` |
| 1 | Skills | `menu_text_en.inc:44` | `field_menu.asm:3453` |
| 2 | Equip | `menu_text_en.inc:45` | `field_menu.asm:3454` |
| 3 | Relic | `menu_text_en.inc:46` | `field_menu.asm:3455` |
| 4 | Status | `menu_text_en.inc:47` | `field_menu.asm:3456` |
| 5 | Config | `menu_text_en.inc:48` | `field_menu.asm:3432` |
| 6 | Save | `menu_text_en.inc:49` | `field_menu.asm:3472` |

Main-menu cursor: `cursor_prop {0,0}, {1,7}, NO_X_WRAP`
(`field_menu.asm:3618-3619`), 7 positions at `field_menu.asm:3623-3637`. One
column, so `$4B = $53*$4E + $4D = $4E`, i.e. `$4B` is the row 0..6, and
up/down wrap (only `NO_X_WRAP` is set).

Item selected:
```
$05 --A--> $00 (1f) -> $02 (8f) -> $07 (1f) -> $01 (1f) -> $02 (8f) -> $08
```
`SelectMainMenuOption_00` sets `zMenuState=$00`, `zNextMenuState=$07`
(`field_menu.asm:3443-3448`). `MenuState_07` runs `_c31ae2` / `_c31afe` /
`_c31b0e` / `_c31b2e` (`field_menu.asm:67-71`); `_c31b0e` ends by setting
`zMenuState = FADE_IN` (`field_menu.asm:129-130`) and `_c31b2e` sets
`zNextMenuState = $08` (`field_menu.asm:137-140`).

### 2.2 Item list `$08`

`MenuState_08` (`field_menu.asm:804-847`):

- Sets `zListType = LIST_TYPE::ITEM` (0) (`field_menu.asm:806-808`).
- `ScrollListPage` first; if it returns carry set, the rest of the state is
  skipped for that frame (`field_menu.asm:810-811`, routine at
  `field_menu.asm:857-916`, entry `::ScrollListPage:` at `field_menu.asm:879`). Carry is set when L or R paged the list, and also
  when the page is already at an end. An L/R press therefore discards that
  frame's A/B.
- B → saves cursor state to `w022f`/`w0231`, then `GotoItemOption`
  (`field_menu.asm:815-836`): `zMenuState = $17` directly, with no fade.
- A → `PlaySelectSfx`, `zSelIndex ($28) = $4B`, `zMenuState = $19`
  (`field_menu.asm:839-846`), plus a flashing "held item" cursor task
  (`_c32f21`, `field_menu.asm:3547-3561`).

Item-list cursor (LANG_EN): `cursor_prop {0,0}, {1,10}, NO_Y_WRAP`
(`item.asm:47-53`), page height `$5A=10`, page width `$5B=1`, max scroll
`$5C=$F5=245` (`field_menu.asm:83-93`). It is a scrolling list, so
`CalcLongListIndex` computes `$4B = $53*$50 + $4F = $50`
(`menu_common.asm:1230-1246`); with one column, `$4B` is the inventory slot
index. `$4A` is the page scroll, `$4E` the row within the page,
`$50 = $4A + $4E`.

> Source-read observation, not verified in the emulator: with `$5C = 245` and
> `$54 = 10`, the largest reachable `$50` is 254 (`item.asm:794-812`,
> `item.asm:867-877`), so inventory slot 255 cannot be selected. Probe:
> fill slots to 255 and drive the cursor to the bottom, then read `$4B`.

### 2.3 Item options `$17`

`MenuState_17` (`field_menu.asm:2080-2093`). Cursor prop
`cursor_prop {0,0}, {3,1}, NO_Y_WRAP` (`item.asm:144-145`): one row, three
columns, and x wraps (bit 7 clear). Single page, so
`CalcShortListIndex` gives `$4B = $53*$4E + $4D = $4D`
(`menu_common.asm:1205-1222`).

| `$4B` | option | label |
|---|---|---|
| 0 | USE | `menu_text_en.inc:311` |
| 1 | ARRANGE | `menu_text_en.inc:312` |
| 2 | RARE | `menu_text_en.inc:313` |

Handlers via `SelectItemOptionTbl` (`field_menu.asm:2109-2124`):

- **USE** (`SelectItemOption_00`, `field_menu.asm:2127-2167`) restores the item
  cursor and sets `zMenuState = $08`. It sets no use-mode flag; it returns to
  the list. Using an item does not require going through USE.
- **ARRANGE** (`field_menu.asm:2169-2179`) sorts the inventory by item icon
  (`SortItemsByIcon`, `field_menu.asm:2225-2237`, icon order table
  `field_menu.asm:2241-2246`), which rewrites `$1869`/`$1969`, and returns
  to `$17`.
- **RARE** (`field_menu.asm:2181-2196`) → `zMenuState = $18`.

B in `$17` → `zNextMenuState = $04`, `zMenuState = $00`
(`field_menu.asm:2087-2093`), i.e. fade back to the main-menu init and then
`$05` (`field_menu.asm:57-59`).

### 2.4 Item move `$19`, where the item is used

`MenuState_19` (`field_menu.asm:2314-2367`):

- B → `zMenuState = $08` (`field_menu.asm:2319-2327`).
- A with `zSelIndex == $4B` (same slot) → `UseItem` (`field_menu.asm:2331-2336`).
- A with a different `$4B` → swap `$1869`/`$1969` between the two slots, back to
  `$08` (`field_menu.asm:2337-2366`).

### 2.5 `UseItem` → target select

`UseItem` (`item.asm:1283-1349`):

1. `zSelIndex = $4B`; if `$1869[$4B]` is `$FF` (empty) or `$EF` → `zMenuState =
   $08`, nothing happens (`item.asm:1284-1292`, `item.asm:1347-1349`).
2. Item property byte: `ItemProp & $07` must equal `$06` (`ITEM_TYPE::CONSUMABLE`,
   `const.inc:1625-1633`) or it falls through to the **item-details** screen,
   `zMenuState = $64` (`item.asm:1293-1298`, `item.asm:1351-1408`). Tools
   (`type 0`) bounce straight back to `$08` (`item.asm:1354-1355`).
3. `ItemProp & ITEM_USAGE::MENU` (`$40`, `const.inc:1635-1639`) must be set, or
   back to `$08` (`item.asm:1299-1301`).
4. Tent `$F7` / Sleeping Bag `$F6` / Warp Stone `$FD` take special exits
   (`item.asm:1303-1345`). Potion/Tonic/Fenix Down do not.
5. Otherwise: save `$4F→$8E`, `$4A→$90`, `zNextMenuState = $6F`, `zMenuState =
   $00` (`item.asm:1312-1319`).

```
$19 --A(same slot)--> $00 (1f) -> $02 (8f) -> $6F (1f) -> $01 (1f) -> $02 (8f) -> $70
```
`MenuState_6F` (`item.asm:2132-2140`) draws the target menu and ends in
`_c32aa5` (`field_menu.asm:2841-2846`), which sets `zNextMenuState = $70` and
`zMenuState = $01`.

### 2.6 Target select `$70`

`MenuState_70` (`item.asm:2145-2166`):

- A is checked before B (`item.asm:2149-2157`). If both are pressed in one
  frame, both fire.
- A → `GetInventoryItemID` (`item.asm:2390-2395`: `$1869[zSelIndex]`); Rename
  Card `$E7` has a special branch (`item.asm:2168-2186`); everything else goes
  to the local `@8ae7` (`item.asm:2188-2202`):
  - `GetTargetCharPtr` (`field_menu.asm:3196-3202`): `+Y = zCharPropPtr[$4B*2]`.
  - `CheckCanUseItem` (`item.asm:2243-2330`). Carry clear means refused.
  - Refused → `PlayInvalidSfx` + `CreateMosaicTask`, and the state stays `$70`
    (`item.asm:2199-2201`).
  - Accepted → `PlayCureSfx`, `_c38b11` (apply effect + `DecItemQty`,
    `item.asm:2206-2217`), redraw quantity and char blocks, then: if
    `$1969[zSelIndex]` is now 0, jump to `@8ab5` (leave); otherwise the state
    stays `$70` for another use (`item.asm:2194-2202`).
- B (or the ran-out path) → `zNextMenuState = $77`, `zMenuState = $00`
  (`item.asm:2157-2166`). `MenuState_77` (`field_menu.asm:146-166`) restores the
  saved list position from `$8E`/`$90` and fades back into `$08`.

---

## 3. The target cursor: cell, values, buttons, and who is selectable

### Where it lives

Both `$6F` (items) and `$3A` (magic) call `_c32a76`
(`field_menu.asm:2819-2839`; called at `item.asm:2133` and
`field_menu.asm:2814`), which calls `InitCharSelectCursor`
(`field_menu.asm:3643-3655`) and creates `CharSelectCursorTask`
(`field_menu.asm:3676-3681`; state 0 at `field_menu.asm:3687-3707`, state 1 at
`field_menu.asm:3737-3760`).

`InitCharSelectCursor` copies 13 bytes of cursor data into DP `$80..$8C`
(`LoadCharSelectCursorProp`, `field_menu.asm:3661-3668`) from
`CharSelectCursorProp` = `cursor_prop {0,0}, {1,4}, NO_X_WRAP`
(`field_menu.asm:3765-3766`) followed by `CharSelectCursorPos`, which is four
`(x,y)` pairs `(8,40) (8,88) (8,136) (8,184)` (`field_menu.asm:3770-3774`). It then
zeroes the x byte at `$85 + 2*slot` for every slot whose `zCharID` is
negative (empty), `field_menu.asm:3645-3654`.

`LoadCursorFar` (`menu_common.asm:1095-1113`) then unpacks that block:

| DP | meaning |
|---|---|
| `$59` | flags (`$80` = no x wrap, `$01` = no y wrap) — `menu_ram.inc:567-571` |
| `$4D` | cursor x within page |
| `$4E` | cursor y within page |
| `$4F`,`$50` | absolute x, y (zeroed here) |
| `$51`,`$52` | zeroed |
| `$53` | max x |
| `$54` | max y |
| `$4B` | **derived index** |
| `$55`,`$57` | cursor sprite x, y |

For character select `$53 = 1`, `$54 = 4`, so `CalcShortListIndex`
(`menu_common.asm:1205-1222`) gives `$4B` = the party slot, 0..3.

`SelectFirstChar` (`menu_common.asm:1116-1130`) advances `$4E` past leading
empty slots at init.

### Which buttons move it

`MoveCursor` (`menu_common.asm:1318-1379`), driven from
`CharSelectCursorTask` state 1 (`field_menu.asm:3737-3760`):

- Only up and down move the cursor. Left/Right are read
  (`menu_common.asm:1357-1378`) but with `$53 = 1` and `NO_X_WRAP` set they
  cannot move it.
- Up/Down wrap (flags bit 0 clear).
- It reads `z0a` (`$0A`), the repeating button word, rather than `z08`. Repeat
  timing is set in `InitCtrl`: 8-frame delay, 3-frame rate
  (`ctrl.asm:20-25`; the repeat state machine is `_c3a4bd`, `ctrl.asm:113-137`). Holding a direction auto-repeats.
- Empty slots are skipped by the task loop rather than by `MoveCursor`: the task calls
  `MoveCursor` repeatedly until the cursor sprite x (`$55`) is nonzero
  (`field_menu.asm:3749-3756`), and `$55` is 0 exactly for the slots
  `InitCharSelectCursor` blanked. The same "re-run until `$55 != 0`" guard runs
  once at task init (`field_menu.asm:3701-3705`).

In state `$3B` (magic target) Left/Right/L/R are intercepted before the A/B
check and switch to all-targets state `$3D` if the spell has `MagicProp & $20`
(`field_menu.asm:2851-2874`). Do not press left or right during magic
targeting. State `$70` (item target) has no such handler.

### A KO'd character can be selected

Nothing in the target cursor path looks at status. `zCharID` is `$FF` only for
an absent slot (`menu_init.asm:35-52`); a wounded character keeps their id, so
their slot keeps a nonzero `$85+2*slot` and the cursor lands on it normally.

### The game refuses a Potion on a dead character

`CheckCanUseItem` (`item.asm:2243-2330`), `+Y` = char data pointer:

- `if (status1 & STATUS1::DEAD)` → only Fenix Down `$F0` is valid; every
  other item returns carry clear (`item.asm:2244-2246`, `item.asm:2283-2286`,
  valid exit `item.asm:2321-2323`).
- Not dead, and item is Dried Meat / Tonic / Potion / X-Potion → require
  `status1 & $C2 == 0` (not wound/petrify/zombie) and `CheckMaxHP` carry
  clear, i.e. current HP strictly below effective max
  (`item.asm:2249-2258`, `item.asm:2325-2330`, `CheckMaxHP` at
  `field_menu.asm:2967-2986`).
- Ether family checks `CheckMaxMP` the same way (`item.asm:2311-2317`,
  `field_menu.asm:2988-3007`).

So a Potion on a full-HP character is refused, a Potion on a KO'd character is
refused, and a Fenix Down on a healthy character is refused, since it only
passes through the dead branch.

Refusal is observable in RAM. `PlayInvalidSfx` + `CreateMosaicTask`
(`item.asm:2199-2200`) starts an 8-frame mosaic task
(`field_menu.asm:3799-3849`) that writes `zMosaic` = `$b5` from
`MosaicTbl {$17,$27,$37,$47,$37,$27,$17,$07}`. `zMosaic` is cleared once at menu
init (`menu_init_2.asm:506`) and never re-zeroed, so `$B5 != 0` is a sticky flag
meaning at least one refusal happened since the menu opened, and `$B5 & $F0 !=
0` marks the 7 frames right after one. (Caveat: the same task fires for other
invalid selections; there are 21 `jsr CreateMosaicTask` sites across
`src/menu`, including `field_menu.asm:668` (invalid character for
skills/equip/status), `field_menu.asm:1106` (disabled skills option),
`field_menu.asm:2428` (uncastable spell), `field_menu.asm:2910` (invalid magic
target), `item.asm:2184` (Rename Card on an invalid actor) and `item.asm:2203`
(the item refusal described here). It is a menu-wide flag rather than an
item-specific one. `PlayInvalidSfx` itself writes only APU I/O
(`menu_common.asm:2666-2670`) and leaves no readable cell; `$AE` only tracks the
move/cancel sfx, `menu_common.asm:2628-2646`.)

`CheckMaxHP` has a side effect: when current HP exceeds effective max it
writes the clamp back to `$0009,y` (`field_menu.asm:2977-2980`). The game
performs that write, not the harness, but a fixture diffing HP across a
refused Potion should expect HP to change.

---

## 4. Character data: addresses, packing, and slot→character mapping

### The block

`$1600-$184F`, 16 characters × 37 bytes (`ff6/notes/field-ram.txt:885`), and the
menu's own pointer table confirms the stride:
`CharPropPtrs: .repeat 16, i / .word $1600 + i*37` (`menu_init.asm:79-82`).

Offsets, each confirmed twice, once in the notes
(`ff6/notes/field-ram.txt:886-923`) and once in code:

| Offset | Address for char *c* | Meaning | Code citation |
|---|---|---|---|
| `+$00` | `$1600 + 37c` | actor index | `item.asm:2171`, `skills.asm:1035-1037` |
| `+$08` | `+8` | level | `menu_common.asm:2227`, `field_menu.asm:3116` |
| `+$09` | `+9` | **current HP** (word) | `field_menu.asm:2975-2979`, `field_menu.asm:2937-2939` |
| `+$0B` | `+11` | **`bbhhhhhh hhhhhhhh` — boost + base max HP** | `field_menu.asm:2968-2970`, `menu_common.asm:2377-2400` |
| `+$0D` | `+13` | **current MP** (word) | `field_menu.asm:2996-2999`, `field_menu.asm:3184-3191` |
| `+$0F` | `+15` | **`bbmmmmmm mmmmmmmm` — boost + base max MP** | `field_menu.asm:2989-2991` |
| `+$14` | `+20` | status 1 (`$80` wound, `$40` petrify, `$02` zombie, …) | `item.asm:2244`, `ff6/notes/field-ram.txt:901-909` |
| `+$15` | `+21` | status 4 | `item.asm:2229`, `ff6/notes/field-ram.txt:910-918` |

**Effective max HP** (what the menu draws, and what `CheckMaxHP` compares
against): take the raw word `W`, `base = W & $3FFF`, `boost = W >> 14`, then
`CalcMaxHPMP` (`menu_common.asm:2377-2400`) computes

| boost | result |
|---|---|
| 0 | `base` |
| 1 | `base + base/4` (25%) |
| 2 | `base + base/2` (50%) |
| 3 | `base + base/8` (12.5%) |

then `ValidateMaxHP` clamps to 9999 (`menu_common.asm:2424-2436`) and
`ValidateMaxMP` to 999 (`menu_common.asm:2438-2447`).

The boost bits come from equipment/espers via `UpdateEquip`, which the menu
re-runs on entry and after each cast (`field_menu.asm:1176` region,
`field_menu.asm:3178-3183`). I did not read `UpdateEquip` itself. If a
fixture needs to assert what the boost bits are at a given moment, the
probe is to read `$1600+37c+$0C` before and after equipping a boost relic and
compare the top two bits.

### Menu slot 0..3 → character index

Built in `menu_init.asm:35-52`:

```
for x in 0..15:
    if ($1850+x & $40) == 0: skip          ; not enabled
    if ($1850+x & $07) != $1A6D: skip      ; not in the current party
    y = ($1850+x & $18) >> 3               ; battle order
    zCharRowOrder[y] = $1850+x
    zCharID[y]       = x                   ; <- the mapping
```

then `menu_init.asm:53-68` fills `zCharPropPtr[y] = CharPropPtrs[zCharID[y]]`.

So the menu slot is the battle-order slot from `$1850+c` bits 3-4 rather than
party order:

| Cell | DP address | Contents |
|---|---|---|
| `zCharID` slots 1-4 | **`$69`,`$6A`,`$6B`,`$6C`** | character index 0..15, `$FF` if empty |
| `zCharPropPtr` slots 1-4 | **`$6D`,`$6F`,`$71`,`$73`** (words) | `$1600 + 37*charID` |
| `zCharRowOrder` slots 1-4 | `$75`..`$78` | copy of `$1850+c` |

(`menu_ram.inc:168-187`. The `$6F` figure is confirmed in the source:
`DrawCharBlock2` writes `ldx $6f`, `field_menu.asm:4267`.)

For the fixture: read `zCharID` at `$69+slot` and compute `$1600 + 37*charID`,
or read the pointer word at `$6D + 2*slot`. Do not assume slot == character.

### There is no "display HP" RAM cell

`DrawCharBlock` (`menu_common.asm:2221-2320`) reads straight from
`zSelCharPropPtr` (DP `$67`, set per slot by `DrawCharBlock1..4`,
`field_menu.asm:4211-4245` and following) and renders digits into the BG1
tilemap at `$7E3xxx`. The four destination address lists are
`_c3332d` (`field_menu.asm:4253-4257`) and its siblings; the pointer order is
`lv, cur HP, max HP, cur MP, max MP` (`menu_common.asm:2219`). So the only
authoritative numbers are in the `$1600` block; reading the tilemap would mean
decoding font tiles. The item-target screen redraws all four blocks
(`DrawItemTargetMenu` → `_c3318a` → `_c33193` → `DrawCharBlock1..4`,
`item.asm:2054-2070`, `field_menu.asm:4001-4010`), so the on-screen numbers and
`$1600` agree by construction.

---

## 5. Magic path: main menu → Skills → Magic → spell → target

### 5.1 Main menu → character select `$06`

`SelectMainMenuOption_01..04` (`field_menu.asm:3453-3469`) set `zMenuState = $06`
directly, with no fade, and start `CharSelectCursorTask`.

`MenuState_06` (`field_menu.asm:611-650`):
- B → `zMenuState = $03` (main menu re-init, `field_menu.asm:615-622`).
- Left → order/row screen for Equip/Relic only (`field_menu.asm:624-641`).
- A → `zSelIndex = $4B`, then `_c31e2d` (`field_menu.asm:644-649`,
  `field_menu.asm:652-668`): `CheckSkillValid`, and on success
  `zNextMenuState = _c31e49[z25]`, `zMenuState = $00`.

`_c31e49 = $FF,$09,$35,$58,$0B` (`field_menu.asm:674-675`), indexed by `z25`.
`z25 = 1` (Skills) → `$09`.

`CheckSkillValid` for Skills (`field_menu.asm:684-736`): requires at least one
of `zSkillsTextColor[0..6]` (`$79..$7F`) to differ from `$24` (disabled)
and `status1 & $C2 == 0`, so a wounded, petrified or zombie character
cannot be picked for Skills (`field_menu.asm:722-731`,
`field_menu.asm:738-748`). Refusal here is `PlayInvalidSfx` + mosaic
(`field_menu.asm:665-668`).

```
$05 --A on row 1--> $06 --A--> $00 (1f) -> $02 (8f) -> $09 (1f) -> $01 (1f) -> $02 (8f) -> $0A
```
(`MenuState_09` ends with `zMenuState = FADE_IN`, `zNextMenuState = SKILLS_SELECT`,
`field_menu.asm:186-191`.)

### 5.2 Skills option list `$0A`

`MenuState_0a` (`field_menu.asm:990-1021`). Cursor:
`SkillsCursorProp: cursor_prop {0,1}, {1,7}, NO_X_WRAP` (`skills.asm:64-66`).
The source comments, *"this is the only cursor that doesn't have an initial
position of (0,0)"*. One column, so `$4B = $4E`, and the initial `$4B` is 1,
which is Magic.

| `$4B` | option | enable byte |
|---|---|---|
| 0 | Esper | `$79` |
| 1 | **Magic** | `$7A` |
| 2 | SwdTech | `$7B` |
| 3 | Blitz | `$7C` |
| 4 | Lore | `$7D` |
| 5 | Rage | `$7E` |
| 6 | Dance | `$7F` |

(order from `SkillsOptionTbl`, `field_menu.asm:1112-1120`; the parallel
`zSkillsTextColor` scope is `menu_ram.inc:189-197`, based at `$79`.)

`SelectSkillsOption` (`field_menu.asm:1091-1104`) refuses unless
`zSkillsTextColor[$4B] == $20`; `$24` means disabled (`field_menu.asm:724-726`).
So `$7A == $20` is a readable gate meaning this character can open Magic.

L/R in `$0A` cycle to the previous/next valid character
(`CheckShoulderBtns`, `field_menu.asm:1024-1088`). The whole handler is skipped
while the mosaic is running (`field_menu.asm:1026-1029`); this is the only
place the mosaic gates input.

Magic selected: `SkillsOption_01` (`field_menu.asm:1219-1228`) sets
`zMenuState = $1A` directly, with no fade.

### 5.3 The spell list

Layout (LANG_EN, `InitMagicMenu`, `field_menu.asm:1260-1275`):
`$5C` (max scroll) = `$13` = 19, `$5A` (page height) = 8, `$5B` (page width) = 2.
Cursor `MagicCursorProp: cursor_prop {0,0}, {2,8}, NO_Y_WRAP`
(`skills.asm:112-117`), positions `skills.asm:119-129`. It is a scrolling list,
so `$4B = $53*$50 + $4F = 2*absoluteRow + column`, 0..53 (`CalcLongListIndex`,
`menu_common.asm:1230-1246`).

`$4A` is the page scroll (0..19), `$4E = $50 - $4A` the row within the page.

Movement uses `MoveListCursor` (`item.asm:790-885`) rather than `MoveCursor`:
left at column 0 wraps to the previous row's last column and scrolls if needed
(`item.asm:815-841`); right at the last column advances a row
(`item.asm:849-880`). It returns immediately while `zWaitCounter != 0`
(`item.asm:791-793`).

#### Cell layout: `$7E9D89` and `$7E9E09`

- `$7E9D89 + i`, i = 0..`$35` (54): the spell id displayed at list index i.
- `$7E9E09 + i`: the text colour for that row. `$20` = castable, `$28` =
  gray, `$24` = "known, no number" (`skills.asm:1105-1122`,
  `skills.asm:1146-1155`, `skills.asm:1163-1166`).

`CalcMagicOrder` (`skills.asm:734-747`) fills `$7E9D89` with `$FF` and then lays
down three runs per `MagicOrderTbl[($1D54 & 7) * 4]`
(`skills.asm:766-772`, expanded by `_c34f61`, `skills.asm:776-800`):

| run start | count | meaning |
|---|---|---|
| `$00` | `$18` = 24 | black magic |
| `$18` | `$15` = 21 | effect magic |
| `$2D` | `$09` = 9 | white magic |

`MagicOrderTbl` row 0 is `$2D, $00, $18`: white, then black, then effect. New
game sets `$1D54 = 0` (`ff6/src/field/init.asm:249`), so by default Cure `$2D`
is list index 0, giving `$4B = 0`, page row 0, column 0, `$4A = 0`. The player
can change spell order in Config, so do not hardcode it.

#### How to find Cure reliably

Read `$7E9D89 + i` for i in 0..`$35` and take the i where the byte is `$2D`;
that i is the `$4B` to reach. Then check `$7E9E09 + i == $20` before
pressing A. That is the gate `MenuState_1a` applies
(`field_menu.asm:2396-2402`).

**Trap: `$7E9D89` is modified by drawing.** `DrawMagicListRow`
(`skills.asm:829-853` → `_c34fc4`, `skills.asm:860-985`) overwrites
`$7E9D89[i] = $FF` for rows it draws that the character does not know
(`skills.asm:914-916`, reached from `skills.asm:900-901` and
`skills.asm:1043-1048`). `DrawMagicList` only draws the 8 visible rows (16
entries) starting at `$e5 = $4A * $5B` (`skills.asm:805-818`,
`GetListTextPos`, `item.asm:1168-1181`). So entries for pages that have not
been scrolled to still hold their original spell id. Consequences:

- `$7E9D89[i] == $2D` does not by itself mean the character knows Cure.
- `$7E9D89[i] == $FF` on a drawn page means the spell is not usable or not
  known.

The authoritative known-spell test is the learn array: `$1A6E + 54*actor +
spellId`, where `actor` is the byte at `$1600 + 37*charID + 0` rather than the
character id (`_c350a2`/`_c350ae`, `skills.asm:1030-1044`; `_c34edd` supplies
the pointer, `skills.asm:677-683`; block documented at
`ff6/notes/field-ram.txt:939-940`). Value `$FF` = fully learned. For Terra
(actor 0) and Cure (`$2D`) that is `$1A9B`.

There is a second display mode. `$9E` is zeroed on entering the skills screen
(`_c34c80`, `skills.asm:306-307`, called from `MenuState_09`,
`field_menu.asm:181`) and toggled by **Y** inside `MenuState_1a`
(`field_menu.asm:2374-2385`). `$9E == 0` draws learn percentages; `$9E != 0`
draws MP costs and blanks more partially-learned spells with `$FF`
(`skills.asm:868-871` selects between `skills.asm:872-913` and
`skills.asm:1017-1028`). Do not press Y while in `$1A`.

Spell colour is set by `_c3514d` (`skills.asm:1093-1122`): gray unless
`MagicProp+3 & $01` ("usable outside battle") and the caster's current MP
(`+$0D`) is at least the cost. The cost comes from `_c3510d`
(`skills.asm:1055-1090`), adjusted by `$11D7`: bit `$40` (Economizer) → 1 MP,
bit `$20` (Gold Hairpin) → half. So `$7E9E09[i] == $20` encodes that the
character knows the spell, can cast it outside battle, and has the MP.

#### `$1A` A-button

`field_menu.asm:2396-2419`: gate on `$7E9E09[$4B] == $20`; then save
`$4F→$8E`, `$4A→$90`, `$4B→$99`, and `zNextMenuState = $3A`,
`zMenuState = $00`. X-Zone `$12` and Warp `$2A` branch elsewhere
(`field_menu.asm:2411-2416`). `GetSelMagic` (`field_menu.asm:3208-3213`) is
`$7E9D89[$99]`, so `$99` holds the list index of the chosen spell.

### 5.4 Magic target `$3A` → `$3B`

`MenuState_3a` (`field_menu.asm:2810-2817`) → `_c32a76` (same character-select
cursor as items) → `_c32aa5` sets `zNextMenuState = $3B`, `zMenuState = $01`.

```
$1A --A--> $00 (1f) -> $02 (8f) -> $3A (1f) -> $01 (1f) -> $02 (8f) -> $3B
```

`MenuState_3b` (`field_menu.asm:2851-2916`):
- L, R, Left and Right are checked first → if `MagicProp & $20` (can target
  all), save `$4E→$5F`, clear `z46` bits `$06`, `zMenuState = $3D`
  (`field_menu.asm:2852-2874`). Cure is a party-targetable spell in vanilla, so
  expect this to fire. Do not press these buttons.
- A → `_c32ccc` (set caster level/mag.pwr), `GetTargetCharPtr`, `_c32c14`
  (validity). Carry clear → `PlayInvalidSfx` + mosaic, stay
  (`field_menu.asm:2895-2916`).
- B → `zNextMenuState = $3C`, `zMenuState = $00` (`field_menu.asm:2879-2885`);
  `$3C` (`field_menu.asm:3219-...`) rebuilds the spell list.

`_c32c14` (`field_menu.asm:3043-3086`) is the spell-side equivalent of
`CheckCanUseItem`:
- Target dead (`status1 & $80`) → only `$30`/`$31` (the Life spells) are valid.
- Cure `$2D` / Cure 2 `$2E` / Cure 3 `$2F` → `status1 & $C2 == 0` and
  `CheckMaxHP` carry clear, i.e. current HP below effective max
  (`field_menu.asm:3076-3081`). Same refusal rule as a Potion.

On success (`field_menu.asm:2900-2915`): `_c32cea` deducts MP from the caster
(`field_menu.asm:3184-3194`), `_c32b39` applies the heal
(`field_menu.asm:2917-2965`), then `_c32bde` (`field_menu.asm:3010-3024`) checks
whether the caster can still afford the spell; if not, `zNextMenuState = $3C`,
`zMenuState = $00`. Otherwise the state stays `$3B` and another cast is
possible.

### 5.5 This hack's custom pages do not touch the magic path

`ff6/src/menu/ot6_loadout_page.asm` (state `$7B`, `ot6_loadout_page.asm:38`) and
`ff6/src/menu/ot6_rage_page.asm` (state `$7C`, `ot6_rage_page.asm:24`) replace
SwdTech (`field_menu.asm:1174-1186`) and Rage (`field_menu.asm:1339`
region); Blitz got a new one-column cursor (`field_menu.asm:1199-1206`). The
only `issue #` markers in `field_menu.asm` and `item.asm` are at
`field_menu.asm:18`, `:1174`, `:1199`, `:1339`, none of them on the item or
magic paths. `skills.asm`'s markers are `:1876`, `:1888`, `:2088`, all Blitz.
So the Item and Magic flows described above are vanilla, and OT6's field
ability pages are the SwdTech/Rage/Blitz configurators rather than a paged
field magic list.

---

## 6. Traps

1. **Transitional states.** Every fade is `$00`/`$01` for 1 frame then `$02` for
   8. Poll for the destination state; do not assert that the menu is still in
   the previous state (`field_menu.asm:515-545`).
2. **Handler runs before the cursor task.** `MenuLoop` does
   `jsr (MenuStateTbl,x)` and then `jsr ExecTasks`
   (`menu_common.asm:273-283`), and `$4B` is recomputed inside the cursor task
   (`field_menu.asm:3727-3733` → `menu_common.asm:1205-1222`). So the A handler
   sees the previous frame's `$4B`. Move, release, wait ≥1 frame,
   read `$4B`, then press A. The existing `driveCursor` helper in
   `tools/tests/gen_sabin_gau.lua:165-176` has this shape.
3. **L/R eats a frame in `$08`.** `ScrollListPage` returning carry set aborts
   the rest of `MenuState_08` (`field_menu.asm:810-811`).
4. **Left/Right in `$3B` jumps to all-target `$3D`.** Only up and down are safe
   during magic targeting (`field_menu.asm:2852-2874`).
5. **Y in `$1A` flips the list display mode** and changes which entries of
   `$7E9D89` are set to `$FF` (`field_menu.asm:2374-2385`).
6. **`$7E9D89` is rewritten as pages are drawn.** See §5.3.
7. **Auto-repeat on held directions**: 8-frame delay then every 3 frames
   (`ctrl.asm:20-25`; repeat state machine `_c3a4bd`, `ctrl.asm:113-137`). `MoveCursor`/`MoveListCursor` read `z0a` (`$0A`), the
   repeat word (`menu_common.asm:1321`, `item.asm:794`). The A button does
   not auto-repeat in menus: `UpdateCtrlMenu` omits the
   A-repeat routine `_c3a4f6` (`ctrl.asm:62-66` vs battle's `ctrl.asm:53-56`; `_c3a4f6` itself is `ctrl.asm:143-166`).
8. **Buttons are remappable.** `z06` passes the d-pad through but routes the 8
   face/shoulder buttons through `w0220..w0223`
   (`ctrl.asm:192-254`, table `ctrl.asm:257-258`), loaded from `$1D50-$1D53`
   when `$1D54 & $40` is set (`ctrl.asm:28-33`, `SetCustomBtnMap` at `ctrl.asm:264-269`), else the
   default `$3412`/`$0656` (`SetDefaultBtnMap`, `ctrl.asm:275-280`). New game clears `$1D54`
   (`ff6/src/field/init.asm:249`), so the default holds. A fixture that
   walks the Config screen could break its own later input.
9. **Cursor memory.** If `$1D4E & $40` is set, the main-menu cursor
   (`field_menu.asm:3586-3592`, saved in `w022b`), the item list
   (`field_menu.asm:104-107`, `menu_common.asm:2450-2456`), the skills cursor
   (`field_menu.asm:183-186`) and the magic cursor
   (`field_menu.asm:1252-1255`, `menu_common.asm:2514-2527`) all resume at
   their last position instead of at their init positions. New game clears
   `$1D4E` (`ff6/src/field/init.asm:250`). The item/magic target cursor is
   exempt:
   `$6F` and `$3A` set `z45` bit `$40` first (`item.asm:2135-2136`,
   `field_menu.asm:2811-2812`), which makes `CharSelectCursorTask` skip the
   `w022d` restore (`field_menu.asm:3693-3700`) and the save
   (`field_menu.asm:3738-3742`).
10. **A is checked before B in `$70`** (`item.asm:2149-2157`). Do not press both.
11. **`DecItemQty` decrements the first matching slot rather than `zSelIndex`**
    (`equip.asm:2509-2522`). With duplicate stacks of the same item the slot
    that shrinks may not be the selected slot, while `MenuState_70`'s
    ran-out test reads `$1969[zSelIndex]`
    (`item.asm:2196-2201`). When the count hits 1→0 the slot becomes
    `$1869[slot] = $FF`, `$1969[slot] = 0` (`equip.asm:2517-2521`).
12. **ARRANGE rewrites the whole inventory** (`field_menu.asm:2169-2179`;
    `_c326b8` blanks `$1869`/`$1969` into scratch at `field_menu.asm:2204-2221`,
    `SortItemsByIcon` refills them at `field_menu.asm:2227-2237`). Any cached slot index is invalid afterwards.
13. **`CheckMaxHP`/`CheckMaxMP` clamp and write back** when current exceeds max
    (`field_menu.asm:2977-2980`, `field_menu.asm:2998-3001`).
14. No confirmation window exists on either path; every A press commits
    immediately.

---

## 7. Cell reference for the fixture

All of these are reads; nothing here is written by the harness.

| Address | Name | Meaning |
|---|---|---|
| `$26` | `zMenuState` | current state (`menu_ram.inc:112`) |
| `$27` | `zNextMenuState` | state after the current fade |
| `$28` | `zSelIndex` | selected item slot (item path) / selected character slot (skills path) |
| `$25` | `z25` | main-menu option chosen (0=Item … 6=Save) |
| `$4A` | page scroll | list scroll position |
| `$4B` | cursor index | the cell that identifies the selection; see the per-screen table below |
| `$4D`,`$4E` | cursor x,y within page | |
| `$4F`,`$50` | absolute cursor x,y | scrolling lists only |
| `$53`,`$54` | max x, max y | |
| `$55`,`$57` | cursor sprite x,y | `$55 == 0` ⇒ empty party slot |
| `$59` | cursor wrap flags | `$80` no-x-wrap, `$01` no-y-wrap |
| `$69`..`$6C` | `zCharID[0..3]` | character index per menu slot, `$FF` = empty |
| `$6D`,`$6F`,`$71`,`$73` | `zCharPropPtr[0..3]` | word = `$1600 + 37*charID` |
| `$79`..`$7F` | `zSkillsTextColor` | `$20` enabled / `$24` disabled, order Esper, Magic, SwdTech, Blitz, Lore, Rage, Dance |
| `$99` | selected magic list index | set on A in `$1A` |
| `$B5` | `zMosaic` | nonzero ⇒ an invalid selection happened since menu open |
| `$1600 + 37c + 9` | current HP (word) | |
| `$1600 + 37c + 11` | boost\|base max HP (word) | see §4 for the unpack |
| `$1600 + 37c + 13` | current MP (word) | |
| `$1600 + 37c + 15` | boost\|base max MP (word) | |
| `$1600 + 37c + 20` | status 1 | `$80` wound, `$40` petrify, `$02` zombie |
| `$1600 + 37c` | actor index | index for the learn array |
| `$1850 + c` | party/order byte | `$40` enabled, `&7` party, `>>3 &3` battle order |
| `$1869 + i` | inventory item id | `$FF` = empty |
| `$1969 + i` | inventory count | |
| `$1A6E + 54*actor + spell` | learn % | `$FF` = fully learned |
| `$1D4E` | config | bit `$40` = cursor memory |
| `$1D54` | config | bits 0-2 = spell order index |
| `$7E9D89 + i` | field magic list order | spell id at list index i, `$FF` = blank |
| `$7E9E09 + i` | field magic list colour | `$20` = castable now |

What `$4B` means, per screen:

| State | `$4B` |
|---|---|
| `$05` main menu | option row 0..6 |
| `$06` char select (skills/equip/…) | party slot 0..3 |
| `$08` / `$19` item list (LANG_EN) | inventory slot 0..254 |
| `$17` item options | 0=USE, 1=ARRANGE, 2=RARE |
| `$0A` skills options | 0=Esper, 1=Magic, 2=SwdTech, 3=Blitz, 4=Lore, 5=Rage, 6=Dance |
| `$1A` magic list | `2*row + column`, 0..53; index into `$7E9D89` |
| `$70` item target | party slot 0..3 |
| `$3B` magic target | party slot 0..3 |

---

## 8. The two recipes

### Heal / revive with a consumable

```
field                       press X
wait $26 == $05
drive up/down until $26==$05 and $4B == 0        (Item)
press A
wait $26 == $08                                  (~19 frames of $00/$02/$07/$01/$02)
drive up/down until $26==$08 and $4B == slotOf(item)
                                                  slotOf: scan $1869+i for the id
release, wait >=1 frame, press A
wait $26 == $19
press A            (same $4B; do not move the cursor between the two A presses)
wait $26 == $70                                  (~19 frames)
drive up/down until $26==$70 and $4B == targetSlot
release, wait >=1 frame
read HP/status before                            $1600+37*zCharID[$4B]+9 / +20
press A
wait one of:
  - HP/status changed        -> accepted
  - $B5 became nonzero       -> refused
press B (repeatedly) to unwind: $70 -> $00/$02 -> $77 -> $01/$02 -> $08
                               $08 --B--> $17 --B--> $00/$02 -> $04 -> $01/$02 -> $05
                               $05 --B--> field
```

Preconditions to assert before pressing A on the target, since failing either
one is a guaranteed refusal (§3): Potion/Tonic needs `status1 & $C2 == 0` and
`curHP < effectiveMaxHP`; Fenix Down needs `status1 & $80 != 0`.

### Cast Cure

```
field                       press X
wait $26 == $05
drive to $4B == 1                                (Skills)
press A
wait $26 == $06
drive to $4B == casterSlot                       (caster must have status1 & $C2 == 0)
press A
wait $26 == $0A                                  (~10 frames; no fade on $05->$06)
assert $7A == $20                                (Magic enabled for this character)
drive to $4B == 1                                (Magic; it already starts there)
press A
wait $26 == $1A                                  (no fade)
i = index in $7E9D89[0..0x35] whose value is 0x2D
assert $7E9E09[i] == 0x20                        (known, field-usable, MP affordable)
drive up/down (trap 4 applies to $3B; in $1A left/right are legitimate
  column moves) until $26==$1A and $4B == i
press A
wait $26 == $3B                                  (~19 frames)
drive UP/DOWN only until $4B == targetSlot
press A
observe target HP at $1600+37*zCharID[$4B]+9, or $B5 for a refusal
B unwinds: $3B -> $3C -> $1A -> ... (B in $1A not traced here)
```

In `$1A` left and right are normal column movement (`MoveListCursor`,
`item.asm:815-880`); in `$3B` they are the all-targets shortcut
(`field_menu.asm:2852-2874`).

---

## 9. What I could not determine from the source

- **Whether Cure `$2D` has `MagicProp & $20`** (party-targetable), i.e.
  whether left/right in `$3B` flips to `$3D` for Cure. `MagicProp` is
  `.import`ed into `skills.asm` (`skills.asm:29`) and lives outside
  `src/menu`; I did not read the data table. Probe: in `$3B` with Cure
  selected, tap Left once and read `$26`; `$3D` means the bit is set.
- **Whether `MagicProp+3 & $01` is set for Cure** (usable outside battle). Same
  table. The observable proxy is `$7E9E09[i] == $20`, which the game uses
  as the gate, so a fixture does not need the ROM value.
- **The exact `UpdateEquip` rules that set the HP/MP boost bits** at `+$0C`/`+$10`.
  Probe named in §4.
- **Whether inventory slot 255 is unreachable.** Probe named in §2.2.
- **Fail-before/pass-after**: none of this was executed. Every state number,
  cell address and button rule above comes from reading the assembly, not from
  observing the running game. The first fixture built on it should log
  `$26` every frame across one full heal and one full cast and diff that trace
  against §8, which checks the whole document at once.
