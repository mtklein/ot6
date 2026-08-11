# Front row / back row: driving the row toggle through the field menu

Companion to `docs/research/field-care-menu.md`, which established the shared
conventions (`zMenuState` = DP `$26`, list cursor = DP `$4B`, `zCharID` at
`$69..$6C`, the one-frame cursor lag, the `$B5` mosaic refusal flag). Those all
hold here and are not re-derived.

---

## 1. Where the row is toggled: the exact path from `$05`

### 1.1 States

The states involved are in the dispatcher table at `menu_common.asm:306-310`
(`$65` at `menu_common.asm:393`):

| State | What it is | Handler |
|---|---|---|
| `$0F` | order — select character | `field_menu.asm:1784` |
| `$10` | order — character picked up | `field_menu.asm:1823` |
| `$11` | order — party swap in progress | `field_menu.asm:1877` |
| `$12` | order — wait for portrait slide | `field_menu.asm:1964` |
| `$65` | horizontal menu scroll (shared) | `field_menu.asm:4927` |

### 1.2 Getting in

`MenuState_05` checks A first, then LEFT, then B (`field_menu.asm:563-585`). The
LEFT branch is `field_menu.asm:571-576`:

```
        lda     z08+1
        bit     #>JOY_LEFT
        beq     @1dbc
        jsr     PlayMoveSfx
        jmp     MainMenuLeftBtn
```

`MainMenuLeftBtn` (`field_menu.asm:3491-3508`):

- `trb z46` bit `$02` — disable the main-menu cursor.
- `InitCharSelectCursor` + create `CharSelectCursorTask`
  (`field_menu.asm:3494-3497`).
- `zWaitCounter = 6`, `zMenuScrollRate = -12` (`field_menu.asm:3498-3501`).
- `zNextMenuState = $0F`, `zMenuState = $65` (`field_menu.asm:3504-3507`).

`MenuState_65` idles until `zWaitCounter` hits 0 and then loads
`zNextMenuState` (`field_menu.asm:4927-4933`); `zWaitCounter` is decremented once
per frame by the NMI handler (`menu_common.asm:3491-3494`). So:

```
$05 --LEFT--> $65 (6 frames) --> $0F
```

No fade states (`$00`/`$01`/`$02`) are involved on this path.

### 1.3 `$0F` — pick the character

`MenuState_0f` (`field_menu.asm:1784-1817`):

- The handler's first action every frame is `jsr _c36989`
  (`field_menu.asm:1786`), the commit to `$1850` (see §2.2). It runs before the
  button handling.
- B or RIGHT → cancel: `zWaitCounter = 6`, `zMenuScrollRate = +12`,
  `zNextMenuState = $03`, `zMenuState = $65` (`field_menu.asm:1787-1804`).
  `MenuState_03` re-creates the main-menu cursor and sets `zMenuState = $05`
  in one frame, no fade (`field_menu.asm:550-557`). RIGHT cancels here; do not
  press it.
- A → `PlaySelectSfx`; `zSelIndex ($28) = $4B`; `zMenuState = $10`;
  `_c32f21` (flashing "held" cursor, `field_menu.asm:3546-3560`);
  `LoadCharSelectCursorProp`; save `$4E → $5E` (`field_menu.asm:1805-1816`).

There is no validity check on A. The Skills/Equip/Relic path runs
`CheckSkillValid` and refuses wounded/petrified/zombie characters
(`field_menu.asm:656-668`, `:684-748`); `MenuState_0f` calls nothing. A KO'd
character's row can be toggled. See §5.

### 1.4 `$10`: press A again on the same slot

`MenuState_10` (`field_menu.asm:1823-1871`):

- B → back to `$0F`, restoring `$4E` from `$5E` (`field_menu.asm:1825-1838`).
- A with `zSelIndex == $4B` (the same slot) → row toggle:
  `trb z46` bit `$01`, `zMenuState = $12`, `jsr _c32e10`, `zWaitCounter = 12`,
  `jmp InitCharSelectCursor` (`field_menu.asm:1845-1857`).
- A with a different `$4B` → party order swap instead:
  `CreateCharSwapTask`, `z22 = 24`, `zMenuState = $11`
  (`field_menu.asm:1859-1870`).

This is the same A-then-A-on-one-slot shape as using an item
(`field-care-menu.md` §2.4). Moving the cursor between the two A presses turns
a row toggle into a party reorder.

### 1.5 `$12`: 12 frames, then back to `$0F`

`MenuState_12` (`field_menu.asm:1964-1970`) does nothing but wait for
`zWaitCounter` to reach 0 and then set `zMenuState = $0F`. So the full toggle is:

```
$0F --A--> $10 --A (same $4B)--> $12 (12 frames) --> $0F
```

and the write to `$1850` lands on the **first frame back in `$0F`**, because
`_c36989` is the first instruction of that handler (`field_menu.asm:1786`).

### 1.6 What `_c32e10` does

`_c32e10` (`field_menu.asm:3355-3379`):

```
lda zSelIndex ; tax
lda $75,x     ; zCharRowOrder[slot]
sta $e0
lda $60,x     ; portrait task offset for that slot
tax
lda $e0
bit #$20
beq @2e29
    lda #$20 : trb $e0     ; was back row -> clear -> front
    lda #$03               ; portrait task state 3 (slide out)
    bra @2e2f
@2e29:
    lda #$20 : tsb $e0     ; was front row -> set  -> back
    lda #$02               ; portrait task state 2 (slide in)
@2e2f:
sta wTaskState,x
lda zSelIndex ; tax
lda $e0
sta $75,x                  ; write back
```

So the toggle is `$75 + slot` bit `$20`, plus a portrait animation, and nothing
else. `$60..$63` (`z60..z63`, `menu_ram.inc:159-162`) hold the portrait task
offsets, one per party slot.

The row is visible on screen as the portrait's x offset: `InitPortraitRowPos`
(`menu_common.asm:2009-2023`) reads `$75,x` bit `$20` and sets the portrait
task's x to 26 (back) or 14 (front).

### 1.7 Getting out

```
$0F --B or RIGHT--> $65 (6 frames) --> $03 (1 frame) --> $05
$05 --B--> UpdateEquipAfterMenu -> TERMINATE (field_menu.asm:577-585)
```

---

## 2. Where the row is stored

### 2.1 The copies, and which one is master

| Address | Bit | What it is | Citation |
|---|---|---|---|
| **`$1850 + c`** | **`$20`** | **master.** `verbbppp`: v=visible, e=enabled, **r=battle row (set = back row)**, bb=battle order, ppp=party | `ff6/notes/field-ram.txt:928-932` |
| `$0867 + 41*obj` | `$20` | field object-settings copy, same bit layout | `ff6/notes/field-ram.txt:518-522` ("characters only, though `$1850` is *master* data") |
| DP `$75 + slot` | `$20` | `zCharRowOrder[slot]` — the menu's working copy, **indexed by party slot 0-3, not by character** | `menu_ram.inc:182-187`; `menu_init.asm:49`; `field_menu.asm:3359` |
| `$3AA1 + 2*i` | `$20` | battle-side mirror, "5: row (0 = front, 1 = back)" | `ff6/notes/battle-ram.txt:906-909`; `battle_main.asm:8065-8074` |
| `$2EC5 + 16*i` | `$20` | battle *graphics* copy | `ff6/notes/battle-ram.txt:540`; `battle_main.asm:7796-7803` |

`c` is the character index 0-15 (`CHAR::TERRA = 0` … `CHAR::EDGAR = 4`,
`const.inc` `.enum CHAR`). The stride of `$1850` is 1 byte rather than 37; the
`$1600 + 37*c` block does not contain the row.

### 2.2 How the menu's DP copy reaches `$1850`

Load, at menu open (`InitCharProp`, `menu_init.asm:31-74`):

```
for x in 0..15:
    if ($1850+x & $40) == 0: skip                ; not enabled
    if ($1850+x & $07) != $1a6d: skip            ; not in current party
    y = ($1850+x & $18) >> 3                     ; battle order = menu slot
    zCharRowOrder[y] = $1850+x                   ; WHOLE byte, row bit included
    zCharID[y]       = x
```
(`menu_init.asm:42-51`)

Store, every frame of `MenuState_0f` (`_c36989`, `menu_init.asm:88-105`):

```
for x in 0..3:
    if zCharID[x] < 0: skip
    y = zCharID[x]
    $1850+y = (zCharRowOrder[x] & %11100111) | (x << 3)
```

The mask `%11100111` clears the battle-order bits (3-4) and preserves bit 5.
The battle-order bits are then re-supplied from the slot index. So the row bit
survives unchanged and the battle-order bits are rewritten from the current
slot, which is how the same screen commits a party reorder.

`_c36989` is called from one gameplay site, `field_menu.asm:1786`
(`MenuState_0f`). The other five call sites are all save/load bookkeeping
(`field_menu.asm:2020-2021`, `:2053-2054`, `:2069`, `:2741`). If control never
returns to `$0F` after the toggle, `$1850` is never written.
`MenuState_12` always returns to `$0F`, so this is not reachable through the UI.

### 2.3 How it survives leaving the menu

`OpenMenu` (`ff6/src/field/menu.asm:303-340`) brackets the whole menu:

- `PushCharFlags` runs before (`field/menu.asm:305`): `obj.asm:3650-3669` copies
  `$0867 & $E7 | ($1850 & $18)` into `$1850`, so the object copy is
  authoritative for the row bit on the way in.
- `PopCharFlags` runs after (`field/menu.asm:328`): `obj.asm:3630-3644` copies
  `$1850` straight into `$0867` for all 16 characters.

So the menu's `$1850` write propagates to `$0867`, and the next
`PushCharFlags` (before a battle, `field/battle.asm:66-91`) copies it back
unchanged. `$1850 + c` bit `$20` is the durable, save-backed value
(`$1600-$1FFF` is Save RAM, `ff6/notes/field-ram.txt:883`).

### 2.4 How to read it to verify a toggle landed

Three reads, in decreasing order of preference for a fixture:

1. `$1850 + charID`, bit `$20`. This is the master copy; it persists after the
   menu closes and is independent of party slot. Get `charID` from `zCharID` at
   `$69 + slot` (`menu_ram.inc:168-173`); do not assume slot == character
   (`menu_init.asm:42-51`).
2. DP `$75 + slot`, bit `$20`, while the menu is open. This is what
   `_c32e10` writes, so it changes one frame earlier than `$1850`. It can be
   used to assert the toggle fired before asserting that it committed.
3. `$0867 + 41*charID`, bit `$20`, after the menu closes: the field object copy.

There is no refusal path on this screen: `MenuState_10`'s A handler calls
`PlaySelectSfx` unconditionally and then toggles (`field_menu.asm:1844-1857`).
Neither `PlayInvalidSfx` nor `CreateMosaicTask` appears anywhere in
`MenuState_0f`/`_10`/`_11`/`_12`. So the `$B5` mosaic flag from
`field-care-menu.md` §3 does not fire here, and a fixture must verify by
reading the bit rather than by waiting for a refusal signal.

---

## 3. What the back row changes in this ROM

### 3.1 Loading the row into battle

`battle_main.asm:8060-8074`, in the per-character init loop:

```
lda     $1850,y                 ; get battle row
and     #$20
sta     $fe
...
lda     $fe
sta     $3aa1,x                 ; $3aa1.5 character row (other flags are cleared)
```

Then `battle_main.asm:7793-7803` copies `$3AA1,x & $20` to `$2EC5` for graphics.

### 3.2 Damage dealt: halved unless the attack is exempt

The only site that reads the attacker's row for damage is
`battle_main.asm:8471-8479`:

```
@3392:  lda     #$20
        bit     $b3
        bne     @33a3       ; skip if "ignore attacker row" is set
        bit     $3aa1,x
        beq     @33a3       ; skip if front row
        lsr     $11b1
        ror     $11b0       ; damage /= 2
```

`$B3` bit `$20` is documented as "r: ignore attacker row"
(`ff6/notes/battle-ram.txt:134-137`).

The exemption rule:

`ExecCmd` sets `$B2 = $FF` and `$B3 = $FF` at the top of every command
(`battle_main.asm:3131-3133`). So the ignore-attacker-row bit starts set, and
the default for every command in the game is no row penalty. One routine
clears it: `_c2299f` / `_magicpunch`, the weapon-swing setup
(`battle_main.asm:7099-7146`), at `battle_main.asm:7127-7133`:

```
        lda     #$62
        tsb     $b3                     ; set bits 6,5,1
        lda     $3ba4,x                 ; main-hand weapon effects
        and     #$60
        eor     #$20
        trb     $b3                     ; clear bit 5 iff weapon lacks BACK_ROW
```

`$3BA4` is "Main Hand Weapon Properties" (`ff6/notes/battle-ram.txt:936`), loaded
from `$DA` at `battle_main.asm:6884-6886`, which is `$11DA` "Weapon Effects (main
hand) `765---1-`, **5: no back row penalty**"
(`ff6/notes/battle-ram.txt:368-372`), which is loaded from **`ItemProp + 19`**
(`battle_main.asm:2670-2671`). The assembler names the bit:

```
.enum WEAPON_FLAG
        SWDTECH   = $02
        BACK_ROW  = $20
        TWO_HAND  = $40
        RUNIC     = $80
.endenum
```
(`ff6/include/const.inc:881-886`)

So `eor #$20` inverts the weapon's BACK_ROW bit before `trb`. If the weapon has
BACK_ROW, `$B3.5` stays set and there is no penalty. If the weapon lacks it,
`$B3.5` is cleared and damage is halved.

Which commands reach `_c2299f`: it has two callers
(`battle_main.asm:3940`, `:8232`):

- `ExecAttack` (`battle_main.asm:8213-8236`) calls it only when
  `$3400 == $FF` **and** `$3413` has bit 7 clear. `$3413` is `$FF` after
  `ExecCmd`'s blanket init (`battle_main.asm:3134-3137`); the only place it is
  set to a real command is `FightAttack` (`battle_main.asm:3498-3513`,
  `lda $b5 / sta $3413`), which serves Fight (`$00`) and Capture (`$06`).
- `Cmd_16` (Jump) calls it at `battle_main.asm:3940` and then immediately
  does `lda #$20 / tsb $b3` at `:3942-3943`, putting the bit back. Jump is
  always exempt.

Every other command leaves `$3413 = $FF`, never reaches `_c2299f`, and therefore
keeps `$B3.5` set. I checked every `trb $b3` in the battle code:
`battle_main.asm:3428` (`#$01`), `:3608` (`#$02`), `:4018` (`#$10`), `:4028`
(`#$80`), `:4058` (`#$04`), `:8201` (`#$80`), `:13385` (`#$90`). None of them
touches bit `$20`. The commands confirmed exempt, with each one's path:

| Command | Path | Exempt? |
|---|---|---|
| Fight `$00` | `Cmd_00` → `FightAttack` → `$3413 = 0` → `_c2299f` | **only if the weapon has `WEAPON_FLAG::BACK_ROW`** |
| Capture `$06` | shares `FightAttack` (`battle_main.asm:8226-8231`) | same as Fight |
| Magic `$02` / X-Magic / Summon / Lore | never sets `$3413` | yes |
| **Tools `$09`** | `Cmd_09` → `_189e` → `CalcItemEffect` → `ExecAttack` (`battle_main.asm:4004-4008`, `:4030-4060`) | **yes** |
| Throw `$08` | `Cmd_08` → `_189e` (`battle_main.asm:4014-4019`) | yes |
| Item `$01` | `Cmd_01` → `_189e`, and additionally `stz $3414` (`battle_main.asm:4024-4026`) | yes |
| Blitz `$0A` | `Cmd_0a` → `ExecAttack` (`battle_main.asm:3424-3443`) | yes |
| Steal `$05` | `Cmd_05` → `_c2298a` → `ExecAttack` (`battle_main.asm:3406-3417`); no damage at all | yes |
| Jump `$16` | `Cmd_16`, re-sets `$B3.5` (`battle_main.asm:3937-3943`) | yes |

In this ROM every command except Fight and Capture is row-exempt, because `$B3`
starts at `$FF`. Tools, Blitz, SwdTech, Magic and Throw all do full damage from
the back row.

### 3.3 Damage taken: halved for physical only

`CalcDmgMod` (`battle_main.asm:1987-2049`), called from `CalcTargetDmg`
(`battle_main.asm:1833-1841`) with `y` = the target:

```
        lda     $3414
        jeq     @0d3b       ; damage modification disabled -> skip everything
        ...
        clc
        lda     $11a3
        bmi     @0cc4       ; $11a3.7 "affect mp" -> carry stays clear
        lda     $11a2
        lsr                 ; carry = $11a2.0 = "physical damage"
@0cc4:  lda     $11a2
        bit     #$20
        bne     @0d22       ; $11a2.5 "ignore target's defense" -> skip defense
                            ;   AND the defend/row halving entirely
        php
        ...defense subtraction...
        plp
        bcc     @0d17       ; carry clear -> magical branch, no row check
        lda     $3aa1,y
        bit     #$02
        beq     @0d0d
        lsr $f1 : ror $f0   ; halve: target used Defend ($3aa1.1)
@0d0d:  bit     #$20
        beq     @0d22
        lsr $f1 : ror $f0   ; halve: TARGET IS IN THE BACK ROW
```

Bit meanings from `ff6/notes/battle-ram.txt:212-220`: `$11A2` bit 0 = "physical
damage", bit 5 = "ignore target's defense". `$3414` is "Enable Damage
Modification (… defending, row, morph …)" (`ff6/notes/battle-ram.txt:771`); it is
`$FF` by default from `ExecCmd`'s init loop (`battle_main.asm:3134-3137`).

Rule: a back-row defender takes half damage iff the incoming attack is
flagged physical (`$11A2.0`), is not MP-affecting (`$11A3.7` clear), does not
ignore defense (`$11A2.5` clear), and damage modification is on (`$3414 != 0`).
Magic does full damage to the back row, as does anything that ignores defense,
including Tools, which set `$11A2 = $21` (physical and ignore defense,
`battle_main.asm:7188-7190`).

The defender-side halving is not gated on the attacker's weapon flag. A
monster using a ranged attack still does half damage to a back-row character.

### 3.4 Battle-type traps

- Back attack (`$201F == 1`): `InitBattleType_01` flips every character's
  `$3AA1.5` (`battle_main.asm:7855-7862`). Back row becomes front.
- Pincer (`$201F == 2`): `InitBattleType_02` forces every character to the
  front row (`battle_main.asm:7847-7853`).
- The in-battle Row command `$14` (`battle_main.asm:4133-4140`) toggles
  `$3AA1.5` only. It never writes `$1850`, so it does not persist past the
  battle. It costs a turn, since it goes through `ExecSelfAttack`.

A fixture asserting that Edgar is in the back row during battle must also
read `$201F`; otherwise `$3AA1` can disagree with `$1850` even though the menu
behaved correctly.

---

## 4. Terra / Locke / Edgar: what each one loses in the back row

### 4.1 The commands

`CharProp` (`ff6/src/field/char_prop.asm:143`) is the table `EventCmd_40` copies
from when a character joins (`ff6/src/field/event.asm:1031-1075`):

| Char | Commands (`char_prop.asm`) | Starting weapon |
|---|---|---|
| Terra (0) | FIGHT, MORPH, MAGIC, ITEM (`:147-153`) | `MITHRILKNIFE` `$01` |
| Locke (1) | FIGHT, STEAL, MAGIC, ITEM (`:157-165`) | `DIRK` `$00` |
| Edgar (4) | FIGHT, TOOLS, MAGIC, ITEM (`:192-199`) | `MITHRILBLADE` `$0A` |

(OT6 reshapes the in-battle command windows
(`ff6/src/battle/ot6_cmdmenu.asm`) but `char_prop.asm` is unmodified vanilla for
these three.)

### 4.2 The weapons

`ItemProp` is `item_prop_en.dat`, `incbin`'d whole with no OT6 splice
(`ff6/src/menu/item.asm:2592-2601`); records are 30 bytes
(`GetItemPropPtr`, `ff6/src/menu/item.asm:1001-1013`, `mul 30`). Byte `+19` is
the weapon-flags byte (`battle_main.asm:2670-2671`). Reading that file:

| Weapon | id | `+19` | has `BACK_ROW`? |
|---|---|---|---|
| `MITHRILKNIFE` (Terra) | `$01` | `$C0` | **no** |
| `DIRK` (Locke) | `$00` | `$C0` | **no** |
| `MITHRILBLADE` (Edgar) | `$0A` | `$C2` | **no** |

Every type-1 (weapon) record in the ROM with `WEAPON_FLAG::BACK_ROW`, with
its equip mask (`ItemProp+1/+2`, `item.asm:1358`; bits 0-13 = `CHAR` enum):

| Weapon | id | can equip |
|---|---|---|
| `ILLUMINA` | `$1A` | Terra, Locke, Edgar, Celes |
| `SHURIKEN` `NINJA_STAR` `TACK_STAR` | `$41`-`$43` | *nobody* (Throw-only) |
| `FLAIL` `MORNING_STAR` | `$44` `$46` | **Terra**, Celes, Strago, Relm, Gogo |
| `FULL_MOON` `BOOMERANG` `RISING_SUN` `HAWK_EYE` `SNIPER` `WING_EDGE` | `$45` `$47` `$48` `$49` `$4B` `$4C` | **Locke** |
| `CARDS` `DARTS` `DOOM_DARTS` `TRUMP` `DICE` `FIXED_DICE` | `$4D`-`$52` | Setzer |

### 4.3 Summary

| | Fight from the back row | Their main damage command | Net |
|---|---|---|---|
| Edgar | halved (Mithril Blade has no `BACK_ROW`) | Tools; `Cmd_09` never reaches `_c2299f` (§3.2), so it is unpenalised | loses nothing. Edgar cannot equip any back-row weapon before Illumina: no `$41`-`$52` record lists char 4. His Fight stays halved in the back row, but Tools is the command he uses for damage. |
| Terra | halved with Mithril Knife | Magic, unpenalised | loses nothing while casting. Fighting is halved unless she is holding a `FLAIL` `$44` or `MORNING_STAR` `$46`, either of which removes the penalty from her Fight as well. |
| Locke | halved with Dirk | Steal deals no damage (`Cmd_05` → `_c2298a`, `battle_main.asm:3406-3417`), so Fight is his only damage | loses damage; he is the one of the three who trades damage for defence. `FULL_MOON` `$45`, `BOOMERANG` `$47` or `HAWK_EYE` `$49` removes the penalty. |

All three take half physical damage in the back row (§3.3) in exchange.

### 4.4 What I could not settle from source, and the probe

`char_prop.asm` gives the weapon each character joins with. What they hold
when the input-driven route reaches the Magitek Factory
depends on chests, shops and whatever the generator equipped; that is save
state rather than source. Probe: read the equipped weapon at
**`$1600 + 37*c + $1F`** (`ff6/notes/field-ram.txt:923`,
`field/event.asm:1056-1057`) and the off-hand at `+$20`, then look up
`ItemProp + 30*id + 19` and test bit `$20`. `ItemProp` is an exported symbol
(`item.asm:2592`), so a fixture can resolve it from the map file the way
`tools/tests/battle_magicite.lua` resolves `MagicProp`.

Shops stock back-row weapons early: scanning `ff6/src/menu/shop_prop.dat`
(128 records × 9 bytes: type byte + 8 item ids) shows `FLAIL` in shop records 0
and 17, `FULL_MOON` in 0, 20 and 29, `BOOMERANG` in 29, 37 and 41. I did not
determine which town each shop record belongs to; that mapping is in event/map
data I did not read. Probe: read the shop index the game passes to the shop
menu, or grep the field event scripts for `shop` commands.

---

## 5. Traps

1. **A twice on the same slot.** `MenuState_10` compares `zSelIndex` to `$4B`
   (`field_menu.asm:1845-1847`); a different slot performs a party reorder
   (`field_menu.asm:1859-1870`), which rewrites `zCharID`, `zCharPropPtr` and
   `zCharRowOrder` for both slots (`_c32dd1`, `field_menu.asm:3316-3349`). Any
   cached slot→character mapping is invalid afterwards.
2. **The one-frame cursor lag applies.** `MenuLoop` runs the state handler and
   then `ExecTasks` (`menu_common.asm:269-283`), and `$4B` is recomputed inside
   `CharSelectCursorTask` state 1 (`field_menu.asm:3742-3757` → `MoveCursor` →
   `CalcShortListIndex`). Move, release, wait ≥1 frame, read `$4B`, then press A.
3. **RIGHT cancels in `$0F`.** `MenuState_0f` treats RIGHT the same as B
   (`field_menu.asm:1787-1792`). Only up and down are safe.
4. **The cursor wraps.** `CharSelectCursorProp: cursor_prop {0,0}, {1,4},
   NO_X_WRAP` (`field_menu.asm:3765-3766`): only the x wrap is disabled, so
   up/down wrap around all four slots. With `$53 = 1` left and right cannot
   move the cursor. `$4B` is the party slot 0-3.
5. **Empty slots are selectable in `$10` but not in `$0F`.**
   `InitCharSelectCursor` zeroes `$85 + 2*slot` for slots whose `zCharID` is
   negative (`field_menu.asm:3643-3655`), and the task re-runs `MoveCursor` until
   `$55 != 0` (`field_menu.asm:3749-3756`). `MenuState_0f`'s A handler calls
   plain `LoadCharSelectCursorProp` (`field_menu.asm:1814`), which restores all
   four x positions, so in `$10` the cursor can land on an empty slot. That is
   the vanilla way to move a character to an empty position; it cannot produce a
   row toggle, because a toggle requires `$4B == zSelIndex` and `zSelIndex` was
   necessarily a real slot.
6. **No KO gate.** Nothing on this path calls `CheckSkillValid`
   (contrast `field_menu.asm:656-668`). A wounded, petrified or zombie character
   can be moved to the back row. The Skills screen behaves differently.
7. **It costs no turn and no resource.** The field row toggle is free. The
   in-battle Row command `$14` costs a turn and does not persist (§3.4).
8. **No auto-close.** `$0F` stays until B or RIGHT is pressed. Several
   characters can be toggled in one visit.
9. **Cursor memory applies here.** `CharSelectCursorTask` state 0 restores
   `w022d` into `$4D` when `$1D4E & $40` is set, unless `z45` bit `$40` is set
   (`field_menu.asm:3690-3697`). The item/magic target screens set that bit to opt
   out (`item.asm:2135-2136`, `field_menu.asm:2811-2812`); `MainMenuLeftBtn`
   does not (`field_menu.asm:3491-3508`). So on the order screen the cursor
   resumes where it was left if the player turned cursor memory on. New game
   clears `$1D4E` (`ff6/src/field/init.asm:250`).
10. **No confirmation, no refusal, no sound difference.** `PlaySelectSfx` fires
    for both the row toggle and the party swap (`field_menu.asm:1844`). The only
    way to know which happened is to read the bit.
11. **Battle type overrides the row:** back attack flips it, pincer clears it
    (§3.4). Read `$201F` before asserting `$3AA1.5`.
12. **`_c36989` also rewrites the battle-order bits** of `$1850` from the current
    slot index every frame in `$0F` (`menu_init.asm:93-101`). A fixture reading
    the whole byte will see bits 3-4 change if it reordered the party; mask to
    `$20`.

---

## 6. Cell reference for the fixture

All of these are reads; nothing here is written by the harness.

| Address | Meaning |
|---|---|
| `$26` | `zMenuState` — `$05` main, `$65` scroll, `$0F` order-select, `$10` picked-up, `$11` swapping, `$12` portrait slide |
| `$27` | `zNextMenuState` |
| `$28` | `zSelIndex` — the slot picked in `$0F` |
| `$4B` | cursor index; on `$0F`/`$10` it is the **party slot 0-3** |
| `$4E` | cursor y within page; `$5E` holds the saved copy from `$0F` |
| `$55` | cursor sprite x; `0` ⇒ blanked (empty) slot |
| `$60`..`$63` | portrait task offsets per slot |
| `$69`..`$6C` | `zCharID[0..3]` — character index, `$FF` = empty |
| `$75`..`$78` | **`zCharRowOrder[0..3]` — bit `$20` = back row** (menu's working copy) |
| `$1850 + c` | **master party/order byte — bit `$20` = back row** |
| `$0867 + 41*c` | field object copy of the same byte |
| `$1600 + 37*c + $1F` | equipped weapon id (`+$20` = off-hand) |
| `$1D4E` | config; bit `$40` = cursor memory |
| `$201F` | battle type: 0 normal, 1 back attack, 2 pincer, 3 side |
| `$3AA1 + 2*i` | in-battle row mirror, bit `$20` |
| `$11DA` / `$3BA4 + 2*i` | weapon effects; bit `$20` = "no back row penalty" |
| `$B3` | attack flags; bit `$20` = "ignore attacker row" (starts `$FF`) |
| `ItemProp + 30*id + 19` | ROM: weapon flags; bit `$20` = `WEAPON_FLAG::BACK_ROW` |

---

## 7. The recipe

```
field                          press X
wait $26 == $05
press LEFT                     (not a cursor row -- see §1.2)
wait $26 == $0F                (~6 frames of $65)

slot = the target party slot; charID = read $69 + slot
before = ($1850 + charID) & $20

drive UP/DOWN only until $26 == $0F and $4B == slot
release, wait >= 1 frame, re-read $4B to confirm      (§5.2)
press A
wait $26 == $10
assert $28 == slot                                    (the pick-up landed)
press A                        (do not move the cursor between the two)
wait $26 == $12                (then 12 frames)
wait $26 == $0F

after = ($1850 + charID) & $20
assert after != before                                (the toggle committed)
  -- earlier and equally valid: ($75 + slot) & $20 flips one frame sooner

press B                        ($0F -> $65 -> $03 -> $05)
wait $26 == $05
press B                        ($05 -> terminate -> field)
```

Assert `before != after` rather than a fixed value: whether the character
starts in the front row depends on the save, and asserting that the character
ends up in the back row would pass vacuously if the toggle never ran. A fixture
that needs an absolute end state should read the bit, decide whether a toggle is
needed, assert the bit afterwards, and also assert that a toggle was performed
when one was needed.

---

## 8. What I could not determine from the source

- **Fail-before / pass-after: none of this was executed.** Every state number,
  cell address and button rule above comes from reading the assembly, not from
  observing the running game. To falsify it, log `$26` every
  frame across one full toggle and diff the trace against §7, and log
  `$1850+charID` and `$75+slot` across the same window.
- **The exact frame on which `$1850` updates.** I believe it is the first frame
  back in `$0F` because `_c36989` is the handler's first instruction
  (`field_menu.asm:1786`) and `MenuLoop` calls the handler before `ExecTasks`
  (`menu_common.asm:280-281`). Not verified.
- **Which town each `shop_prop.dat` record belongs to** (§4.4); that mapping is
  in map/event data I did not read.
- **What bit 15 of the `ItemProp+1/+2` equip mask means.** It is set on every
  weapon I looked at and there are only 14 characters. I reported bits 0-13 only.
  Probe: try to equip a weapon whose mask is `$8000` alone.
- **Whether OT6's class system ever hands one of these three a back-row weapon.**
  `Ot6WeaponClass` (`ff6/src/battle/ot6_break.asm:1599`, called from
  `battle_main.asm:7134`) runs inside `_c2299f`, after the `trb $b3` at
  `:7131`. I read its call site but not its body; no OT6 file contains any
  reference to `$b3` or `$3ba4` (grepped across `ff6/src/battle/ot6_*.asm`), so I
  believe it cannot re-open the row penalty, but I did not read the proc.
