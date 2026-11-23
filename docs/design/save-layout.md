# OT6 save layout

Every byte of the battery save OT6 reads or writes, who writes it and when,
how a missing or unsigned region reads, and what is reserved. From v1.0
this layout is frozen: every v1.y.z release loads every earlier v1 save
(the owner, 2026-11-15, #389). Two checks hold the build to this file:
`tools/check_save_layout.py` (the static check, in qualification as
`save_layout`) and the golden-save suite (`tools/tests/save_golden.lua`
with `tools/golden_saves.py`, one `build/results/golden/*.ok` per save).

Derived from the ROM source: `ff6/src/menu/save.asm`, `menu_sram.asm`,
`menu_common.asm`, `field_menu.asm`, `field/event.asm`, `field/header.asm`,
`battle/ot6_codex.asm`, `battle/ot6_class_split.inc`, `battle/ot6_esper.asm`
and `battle/ot6_memory.inc`.

## Compatibility policy

Only upgrades matter: a newer ROM must load older saves. A save made on a
newer ROM and loaded on an older one is not supported, and no design or
test effort goes into it.

A v1.y.z change **may**:

- use reserved space for a new field, provided the field's "absent" value
  is what an older save holds there: zero in a signed slot's reserves (the
  save block's, and its codex and esper pages'), and behind a signature
  anywhere else (see "Reserve and the layout version");
- read the save block's layout version (`OT6_SAVEVER`) to tell a save
  written before a field existed from one that holds it, and raise the
  version when it adds one;
- add a new signed page in reserved battery space: a magic word that an
  older battery cannot hold by accident, and "unsigned reads as absent";
- give an existing signed page a new magic word, provided the new ROM
  migrates every older magic it may meet (as the codex's O7 and O8 steps
  do) and never writes the older magic again;
- change what the game does with a field, as long as every value an older
  save can hold there still reads sensibly.

A v1.y.z change **may not**:

- move, resize or re-encode a field below, or change what one of its
  values means;
- reuse a retired field's bytes (a retired field stays reserved, since an
  old save may still carry a value there);
- change the vanilla slot layout, its checksum or the slot pointers;
- make a range a later release can't read back: the battery map below is
  exhaustive, and a ROM that writes outside it fails `save_layout`.

A future field must behave on an older save the way the esper pages did at
v0.44: the save loads with the field absent, the game runs as if the
player had never earned or set it, and the first save afterwards writes it.
It never fails the load, never reads stale junk as a real value, and never
changes another field.

Content is part of the save too. A save stores ids (items, spells, espers,
rages, characters, event switches, chests) whose meaning lives in the ROM's
tables, and values fixed when they were written (a character's commands
and starting gear, set when the character joins; spells learned under the
learn rules of the day). A v1.y change to such a table reaches only what is
looked up at run time; what an older save already holds stays as it was.
Prefer changes whose old values still make a playable game, and note in the
release notes when a change reaches only new games or new joins.

## Battery map

The battery is 32 KiB. The header declares 256 kbit (`field/header.asm`),
and the SRAM windows `$6000-$7FFF` of banks `$30-$33` map to battery
offsets `$0000-$7FFF` (bank `$30` is `$0000-$1FFF`, `$31` is
`$2000-$3FFF`, and so on). Rows tile the whole battery.

Scope: `slot1`-`slot3` belong to one save slot, `newgame` to an unsaved
New Game, `shared` to the battery as a whole (every slot sees it).
Written: when today's ROM writes the range. `save` is the Save menu (and
Save over another slot), `load` the title's Continue and the reload after a
game over, `title` the title screen, `play` the field or a battle,
`newgame` a New Game, `clear` the reset of a battery whose validity words
are wrong (`ClearSRAM`, battery `$0000-$1FFF` only), `zero` a save writes
zeros there (the destination slot's page reserves, `Ot6SaveSign`), `never`
never.

| Battery | Bytes | Scope | Holds | Anchor | Written | Absent or unsigned |
|---|---|---|---|---|---|---|
| $0000-$09FF | 2560 | slot1 | Slot 1: the vanilla save block, WRAM `$1600-$1FFF` copied whole (`CopyGameDataToSRAM`), with its checksum at `$1FFE` | SRAMSlotPtrs[1] | save, clear | A checksum that does not match marks the slot empty (Continue does not offer it) |
| $0A00-$13FF | 2560 | slot2 | Slot 2, the same | SRAMSlotPtrs[2] | save, clear | as slot 1 |
| $1400-$1DFF | 2560 | slot3 | Slot 3, the same | SRAMSlotPtrs[3] | save, clear | as slot 1 |
| $1E00-$1FEF | 496 | shared | Unused by vanilla and OT6 | - | clear | Zero in any battery the game has validated |
| $1FF0 | 1 | shared | The slot last saved (the load menu's first cursor) | - | save, clear | 0 on a fresh battery: the cursor starts on slot 1 |
| $1FF1 | 1 | shared | Random seed: the load menu adds 1 as it starts (`GameLoadMenu`) and 13 as it closes (`EventCmd_ab`), which seeds `$1F6D` and the five encounter counters | - | title, clear | Any value is valid |
| $1FF2-$1FF7 | 6 | shared | Unused | - | clear | Zero in any battery the game has validated |
| $1FF8-$1FFF | 8 | shared | Validity words: `$E41B` four times (`ValidateSRAM`); none matching means the battery is cleared and a New Game starts | - | save, clear | Cleared: all three slots read empty |
| $2000-$2001 | 2 | slot1 | Codex page, slot 1: magic (`$394F` O9; `$384F` O8 is a four-class page from v0.5-v0.50 and `$374F` O7 the pre-v0.5 global codex, each migrated on first touch) | OT6_CODEX_MAGIC | load, play, save | Any other value: the page is zeroed and signed before use, so the codex starts empty; O7 is cloned into all three slots once; O8 has its class table rewritten once ("The six-class codex") |
| $2002-$200F | 14 | slot1 | Reserved; a save into the slot zeroes it | - | zero | Zero in a slot a signing build (v0.45 on) saved |
| $2010-$218F | 384 | slot1 | Revealed weak elements, one byte per species | OT6_CODEX | load, play, save | Zero: nothing revealed |
| $2190-$230F | 384 | slot1 | Revealed weapon classes, one byte per species: the six classes' bits `$01`-`$20` in an O9 page (v0.51 on), the four classes' bits `$01`-`$08` in an O8 or O7 page, which the first load rewrites | OT6_CODEX_CLASS | load, play, save | Zero: nothing revealed |
| $2310-$23FF | 240 | slot1 | Reserved; a save into the slot zeroes it | OT6_CODEX_ROOT+OT6_CODEX_USED | zero | Zero in a slot a signing build (v0.45 on) saved |
| $2400-$2401 | 2 | slot2 | Codex page, slot 2: magic | OT6_CODEX_MAGIC+OT6_CODEX_STRIDE | load, play, save | as slot 1 |
| $2402-$240F | 14 | slot2 | Reserved; a save into the slot zeroes it | - | zero | Zero in a slot a signing build (v0.45 on) saved |
| $2410-$270F | 768 | slot2 | Revealed elements, then classes | OT6_CODEX+OT6_CODEX_STRIDE | load, play, save | Zero: nothing revealed |
| $2710-$27FF | 240 | slot2 | Reserved; a save into the slot zeroes it | - | zero | Zero in a slot a signing build (v0.45 on) saved |
| $2800-$2801 | 2 | slot3 | Codex page, slot 3: magic | OT6_CODEX_MAGIC+$0800 | load, play, save | as slot 1 |
| $2802-$280F | 14 | slot3 | Reserved; a save into the slot zeroes it | - | zero | Zero in a slot a signing build (v0.45 on) saved |
| $2810-$2B0F | 768 | slot3 | Revealed elements, then classes | OT6_CODEX+$0800 | load, play, save | Zero: nothing revealed |
| $2B10-$2BFF | 240 | slot3 | Reserved; a save into the slot zeroes it | - | zero | Zero in a slot a signing build (v0.45 on) saved |
| $2C00-$2C01 | 2 | newgame | Codex page for an unsaved New Game: magic | OT6_CODEX_MAGIC+OT6_CODEX_TEMP | newgame, load, play | Zeroed and signed before use |
| $2C02-$2C0F | 14 | newgame | Reserved | - | never | - |
| $2C10-$2F0F | 768 | newgame | Revealed elements, then classes; the first save copies them into its slot | OT6_CODEX+OT6_CODEX_TEMP | newgame, load, play | Zero: nothing revealed |
| $2F10-$2FFF | 240 | newgame | Reserved | - | never | - |
| $3000-$3001 | 2 | slot1 | Esper page, slot 1: magic `$3145` ('E1') | OT6_ESPER_ROOT | save | Any other value: the slot has no esper progress |
| $3002-$300F | 14 | slot1 | Reserved; a save into the slot zeroes it | - | zero | Zero in a slot a signing build (v0.45 on) saved |
| $3010-$327F | 624 | slot1 | Magic Points per character (actors 0-11) per esper slot (26, GenjuProp order, Odin and Raiden share one), little-endian words, actor-major, capped at 9999 | OT6_ESPER_ROOT+OT6_ESPER_CTR | save | Read only when signed |
| $3280-$32B3 | 52 | slot1 | Row 12: Magic Points for actor 12 (Gogo's slot: a holder once revealed as Leo, while Summon is one of his picks), 26 words as the rows above (v0.51, layout version 2) | OT6_ESPER_ROOT+OT6_ESPER_LEO | save | Read only when the page is signed and the slot's block is signed with `OT6_SAVEVER` 2 or more; otherwise no progress (reserve before v0.51: zero from v0.45 on, junk possible in a v0.44 page) |
| $32B4-$33FF | 332 | slot1 | Reserved; a save into the slot zeroes it | OT6_ESPER_ROOT+OT6_ESPER_COPY | zero | Zero in a slot a signing build (v0.45 on) saved |
| $3400-$3401 | 2 | slot2 | Esper page, slot 2: magic | OT6_ESPER_ROOT+OT6_ESPER_STRIDE | save | as slot 1 |
| $3402-$340F | 14 | slot2 | Reserved; a save into the slot zeroes it | - | zero | Zero in a slot a signing build (v0.45 on) saved |
| $3410-$367F | 624 | slot2 | Magic Points, as slot 1 | - | save | Read only when signed |
| $3680-$36B3 | 52 | slot2 | Row 12, as slot 1 | - | save | as slot 1 |
| $36B4-$37FF | 332 | slot2 | Reserved; a save into the slot zeroes it | - | zero | Zero in a slot a signing build (v0.45 on) saved |
| $3800-$3801 | 2 | slot3 | Esper page, slot 3: magic | OT6_ESPER_ROOT+$0800 | save | as slot 1 |
| $3802-$380F | 14 | slot3 | Reserved; a save into the slot zeroes it | - | zero | Zero in a slot a signing build (v0.45 on) saved |
| $3810-$3A7F | 624 | slot3 | Magic Points, as slot 1 | - | save | Read only when signed |
| $3A80-$3AB3 | 52 | slot3 | Row 12, as slot 1 | - | save | as slot 1 |
| $3AB4-$3BFF | 332 | slot3 | Reserved; a save into the slot zeroes it | - | zero | Zero in a slot a signing build (v0.45 on) saved |
| $3C00-$3C01 | 2 | shared | Live esper page: magic. The only page play reads and writes | OT6_ESPER_LIVE+OT6_ESPER_MAGIC | load, newgame, play, save | Unsigned: cleared and signed before use (no progress) |
| $3C02-$3C0F | 14 | shared | Reserved | - | never | - |
| $3C10-$3E7F | 624 | shared | Live Magic Points: a load copies its slot's page here, a victory adds to them, a save copies them into the slot | OT6_ESPER_LIVE+OT6_ESPER_CTR | load, newgame, play | - |
| $3E80-$3EB3 | 52 | shared | Live row 12 (actor 12): a load copies its slot's row here when the block is version 2 or more and clears it otherwise (`Ot6EsperLeoRow`), a victory adds to it once Leo is revealed, a save copies it into the slot | OT6_ESPER_LIVE+OT6_ESPER_LEO | load, newgame, play | - |
| $3EB4-$3EFF | 76 | shared | Unused, zeroed with the counters | OT6_ESPER_LIVE+OT6_ESPER_COPY | load, newgame | - |
| $3F00-$3F03 | 4 | shared | Victory screen's pending rank lines, one byte per party slot | OT6_ESPER_LIVE+OT6_ESPER_PEND | load, newgame, play | Zero: none |
| $3F04-$3F05 | 2 | shared | Magic Points to announce on the victory screen (0 = none) | OT6_ESPER_LIVE+OT6_ESPER_SHOWN | load, newgame, play | Zero: none |
| $3F06-$3FFF | 250 | shared | Reserved | - | never | - |
| $4000-$7FFF | 16384 | shared | Reserved (banks `$32-$33`) | - | never | - |

## Magic words

| Symbol | Value | Meaning |
|---|---|---|
| OT6_CODEX_V3 | $394F | 'O9', a per-save codex page whose class table holds the six weapon classes (v0.51 on); the only codex magic today's ROM writes |
| OT6_CODEX_V2 | $384F | 'O8', a per-save codex page whose class table holds the four classes (v0.5-v0.50), migrated on first touch |
| OT6_CODEX_GLOBAL | $374F | 'O7', the v0.1-v0.4 cartridge-wide codex (page 1 only), migrated on first touch |
| OT6_ESPER_MAGIC_WORD | $3145 | 'E1', an esper page |
| OT6_SAVESIG_WORD | $5653 | 'SV' (bytes `$53 $56` at `$1E2C`), a signed save block |
| OT6_SAVEVER_CUR | $0002 | the layout version today's ROM signs with (a byte at `$1E2E`); 2 since v0.51 |

Vanilla's validity word `$E41B` (`menu_sram.asm`) is not an OT6 symbol.

## Save-block fields

The vanilla save block is WRAM `$1600-$1FFF`, copied whole into a slot on
save and back on load; `CalcSaveSlotChecksum` sums `$1600-$1FFD` and the
word lands at `$1FFE`. OT6 adds three fields and a signature in the range
vanilla leaves unused, and names the rest of that range as reserve. Address is inclusive; Symbol is the ca65 name in
`ff6/src/battle/ot6_memory.inc`.

| Address | Bytes | Symbol | Meaning | Owner procs | Since | Old-save read |
|---------|-------|--------|---------|-------------|-------|---------------|
| $1E1D-$1E1E | 2 | OT6_LOADOUT | Cyan's Bushido loadout: a packed word, three bits per boost slot (slots 1/2/3 at bits 3-5/6-8/9-11), each a 0..7 SwdTech index. `$0000` = AUTO. | ot6_bushido.asm `Ot6BushidoTech` reads it in battle; ot6_loadout.asm `Ot6LoadoutAssign` writes a slot and `Ot6LoadoutInput` writes `$0000` to revert to AUTO; `Ot6LoadoutUnpack`/`Ot6LoadoutIsAuto`/`Ot6LoadoutSlotTech` read it in the field page. | v0.5 | `$0000` = AUTO. A non-zero word is decoded per slot and a slot naming an unlearned tech falls back to AUTO (`Ot6TechLearned`). |
| $1E1F-$1E26 | 8 | OT6_RAGELOAD | Gau's 8-slot Rage loadout, one byte per slot: byte = rage id + 1, `$00` = unset. All eight `$00` = AUTO. | ot6_rage.asm `Ot6RageList` builds the battle Rage list from it; `Ot6RageSeed` writes the window on the first edit, `Ot6RageCycleCore`/`Ot6RageInput` write field edits; `Ot6RageSlot`/`Ot6RageIsAuto` read it. | v0.7 | all `$00` = AUTO. A byte naming an unknown or unlearned rage is dropped from the list. |
| $1E27-$1E2B | 5 | OT6_LORELOAD | Strago's 5-slot Lore loadout, one byte per slot: byte = lore id + 1 (ids 0..23), `$00` = unset. All five `$00` = AUTO. | ot6_lore.asm `Ot6LoreMask`/`Ot6LoreMaskSet` build the battle Lore mask from it; `Ot6LoreSeed`, `Ot6LoreCycleCore`/`Ot6LoreInput` write it; `Ot6LoreSlot`/`Ot6LoreIsAuto` read it. | v0.13 | all `$00` = AUTO. A byte naming an unknown or unlearned lore is dropped from the mask. |
| $1E2C-$1E2D | 2 | OT6_SAVESIG | The block's signature, `$5653` ('SV') when signed. | ot6_codex.asm `Ot6SaveSign` writes it when it signs an unsigned block, at the save, before the checksum; `Ot6NewGameClear` zeroes it at New Game. | v0.45 | Signed means `$5653` here AND an `OT6_SAVEVER` of 1 through `OT6_SAVEVER_CUR`; a signed block keeps its signature. Anything else is unsigned, and its first save zeroes `OT6_SAVERSV` and `OT6_SAVETAIL`, then signs. |
| $1E2E | 1 | OT6_SAVEVER | The layout version of the block (today 2): every field a version names is set up in the block and its slot's pages. Version 2 (v0.51) adds the esper pages' row 12. | `Ot6SaveSign` writes it with the signature when it signs an unsigned block, and raises a lower signed version to `OT6_SAVEVER_CUR` at the save (`Raise`), after `Ot6EsperSaveAs` has written the new field. | v0.45 | 0, or past `OT6_SAVEVER_CUR`: the block is unsigned. 1 (v0.45-v0.50): signed, its esper pages' row 12 reads as no progress. |
| $1E2F-$1E3F | 17 | OT6_SAVERSV | Reserved. | Zeroed by `Ot6SaveSign` when it first signs a block, and by `Ot6NewGameClear`. | v0.45 | Zero in a signed block; junk possible in an unsigned one. |
| $1FF7-$1FFD | 7 | OT6_SAVETAIL | Reserved (vanilla's unused tail inside the checksum window). | Zeroed as `OT6_SAVERSV` is. | v0.45 | Zero in a signed block; junk possible in an unsigned one. |

Declared free (reserved) space in the block:

- Scrap `$1E1D-$1E3F` (35 bytes): the three loadouts, the signature, and
  `OT6_SAVERSV`.
- Scrap `$1FF7-$1FFD` (7 bytes), vanilla's unused tail inside the checksum
  window: `OT6_SAVETAIL`.

Vanilla's power-on clear (`ClearRAM`, `field/reset.asm`) stops at WRAM
`$11FF`, and its New Game names none of these bytes, so before v0.45 they
started as whatever the console or emulator left in RAM: under an all-ones
power-on fill a New Game left `$FF` in all of `$1E1D-$1E3F` and
`$1FF7-$1FFD` (`build/attempts/wt/v1-save-freeze/poweron_allones_newgame.log`),
and every save of that game carried them. All-`$FF` Rage and Lore loadouts
read as manual loadouts whose every slot names an unknown entry, so Gau's
Rage list and Strago's Lore list (but for the free row) came up empty until
the player set the loadout or reset it to AUTO on its page
(`battle_newgameloadouts` on v0.44's ROM, `build/attempts/wt/v1-save-sign/`);
the Bushido word reads `$FFFF` as Cleave in every slot (AUTO while Cleave
is unlearned). Since v0.45 a New Game zeroes both ranges
(`Ot6NewGameClear`), and the first save of an unsigned block zeroes the
reserve and the tail. No save edits the loadouts (owner, 2026-11-15: no
code that edits a player's save by inference; the underlying bugs are
caught at development time instead), so a save from before v0.45 whose game
was started on a console that did not power on blank keeps its loadouts
until the player resets each to AUTO on its page.
Every save the harness makes was zero there all along, because the harness
pins an all-zeros fill.

`$1E40-$1E7F` is vanilla's treasure bitfield and `$1E80-$1F5F` its event
switches (all live game state).  OT6 claims no treasure bit and one event
switch, with vanilla's encoding (the next section).

## Event switches

A vanilla event switch OT6 sets and reads for a rule of its own.  Each is a
bit of vanilla's switch array (`$1E80` + switch/8, bit switch%8), written
and read with vanilla's encoding, so it needs no reserve and no layout
version: every save from any release holds the bit, and an older save holds
0 there.  `tools/check_save_layout.py` checks each row against the build
(the byte and bit are the switch's, the symbol assembles at that byte, its
`_BIT` equate is the bit) and refuses an OT6 symbol in the switch array
without a row.

| Switch | Byte | Bit | Symbol | Meaning | Since | Old-save read |
|---|---|---|---|---|---|---|
| $00E0 | $1E9C | 0 | OT6_LEO_FLAG | General Leo's reveal has played (#552, [leo-reveal.md](leo-reveal.md)): set once by event command $9F (`Ot6LeoReveal`) at Leo's grave in the World of Ruin with Gogo in the party; read by the battle row, the equip masks, the Status screen's command list, the shop, the ending | v0.49 | 0 in every save before v0.49 (checked: the golden saves and every tracked checkpoint): Gogo unrevealed, and the scene can play |

Taking a free switch.  A switch is free when nothing reads or writes it:
no event script names it (`switch`, `if_switch`, `set_switch`,
`clr_switch`, `loop_until`, an `if_any`/`if_all` list, an NPC's show
switch), no assembly addresses its byte, and every save a player may hold
reads 0 there.  Before taking one, scan the source and the built event
script's raw command bytes for it (the set/clear opcodes `$D0`-`$D5` and
the object script's `$E1`-`$E6` with its low byte, the world's `$C8`/`$C9`
with its word, and the word, with or without bit 15, in a conditional's
switch list), read it in every golden save and tracked checkpoint, and
record both (#552's evidence: `build/attempts/wt/v049-leo/switch_scan.txt`,
`switch_saves.txt`).  The range `$00E0`-`$00FF` was unreferenced in
vanilla and is where OT6 takes from; `$00E0` is taken.  A taken switch stays
taken: its meaning never changes, and a retired one is never reused.

## Vanilla fields OT6 uses

OT6 reads and writes these vanilla save-block fields with their vanilla
encoding; listed because OT6's rules give them weight they did not have.
None is moved or re-encoded.

| Field | Vanilla meaning | What OT6 does with it |
|---|---|---|
| `$1600-$184F` | The 16 character records | Read by the esper ladder (`Ot6EsperEarn`: actor `$1600`, worn esper `$161E`) and the item grants; max HP/MP at `$160B`/`$160F` keep vanilla's boost bits 14-15 (`Ot6LevelUpHeal`) |
| `$1A69-$1A6C` | Espers held | Unchanged; esper progress is per character per esper, in the esper pages |
| `$1A6E-$1CF5` | Spells learned, 54 bytes a character (`$FF` learned) | Esper learning is retired (v0.4): equipped espers grant spells while worn (`Ot6EsperSpellKnown`). Strago's Bserk is learned by watching (`Ot6BlueLearn` writes `$1A6E + 7*$36 + $21`, v0.38) |
| `$1CF6` | Morph gauge | Read for Terra's Trance |
| `$1CF7` | SwdTechs learned | Cleave (bit 7) is taught by the Phantom Train farewell (`give_bushido_tech`, `EventCmd_9e` ORs the bit, v0.28); the level table no longer teaches it |
| `$1D28`, `$1D29-$1D2B`, `$1D2C-$1D4B` | Blitzes, lores, rages learned | Read by the command menu, the divines and the loadouts |
| `$1860-$1862` | Gil | Read by Setzer's coin attacks |
| `$1EDE-$1EDF` | Characters available | Vanilla's random Shadow departure is gone (v0.16): the bit is no longer cleared after battle |
| `$1E80-$1F5F` | Event switches | Read by OT6 code (`$00BF` Terra's return, `$0068` the tube room, `$00CA`, `$02E3` Shadow's initialization, and Relm's list: `$02E8` her recruitment, `$0240` Owzer's mansion after Chadarnook, `$00BA` Strago's return); OT6 sets one switch of its own, `$00E0` (the section above); its three added save points ride vanilla's standing `$0632` |
| `$1F6E` | Random battle counter | `Ot6DangerStep` scales the step and adds it there; zeroed at New Game (`Ot6NewGameClear`) |
| `$1616-$1619` | Battle commands | Gau's join gives FIGHT, RAGE, MAGIC, ITEM (v0.8; vanilla RAGE, LEAP, MAGIC, ITEM). Set when he joins, so a save where he joined earlier keeps the old list |

## Who writes what, and when

- **The title.** Start opens the load menu (`EventCmd_ab`, `GameLoadMenu`),
  which adds 1 to the seed `$1FF1` and 13 more as it closes. If the
  validity words are wrong, `ClearSRAM` zeroes battery `$0000-$1FFF` (the
  slots and bank `$30`'s tail; banks `$31-$33` are not cleared) and the
  menu ends at once in a New Game, with no slot list shown.
- **New Game.** `Ot6CodexNewGame` zeroes and signs the New-Game codex page
  `$2C00`, `Ot6EsperNewGame` clears and signs the live esper page `$3C00`,
  and `Ot6NewGameClear` zeroes WRAM `$1E1D-$1E3F` and `$1FF7-$1FFD`, and
  vanilla's own bytes that New Game leaves unwritten (`Ot6NewGameZero`;
  the power-on fill found each read unwritten or carried into every save):
  `$1E70-$1E7F` (unused, after the treasure bits), `$1F60-$1F63` (world
  and airship positions, which an event sets before use), `$1F6E-$1F6F`
  (the random-battle counter), `$1FA8-$1FBF` (the timers' saved copy, `PushTimers`/`PopTimers`; zero
  means no timer), `$1FC2-$1FD1`
  (event variables 0-7) and `$1FD3-$1FF2` (the objects' saved positions).
  Each is zeroed at New Game, and at power-on before the field's first
  init (`Ot6PowerOnClear`); zero is the value vanilla assumes, and no
  field's meaning changes. A save from an older release keeps what it
  holds there.
  Nothing in the battery's slots is written. (Measured on an all-ones power-on
  fill: `GameLoadMenu`, `CheckSRAM`, `ClearSRAM` and `Ot6CodexNewGame` each
  ran once, battery `$1E00` read 0 and both pages were signed afterwards,
  while bank `$31`'s slot pages and `$4000` still read `$FF`;
  `build/attempts/wt/v1-save-freeze/poweron_allones_newgame.log`.)
- **Continue** (title). The load menu copies the slot into WRAM `$1600`,
  the confirm runs `Ot6EsperContinue`, which runs the reload's
  `Ot6CodexLoaded` (since v0.51; before, only the esper half ran here and
  the codex page waited for its first battle or save): the slot's esper
  page is copied into the live page if signed and the live page cleared if
  not, and the slot's codex page is ensured (`Ot6CodexEnsure`): an O9 page
  is left alone, an O8 page has its class table rewritten for the six
  classes and is signed O9, an O7 codex is cloned into all three slots and
  each clone rewritten, and any other page is zeroed and signed.
- **Reload after a game over.** `LoadSavedGame` runs `Ot6CodexLoaded`,
  the same call.
- **Battle and field.** Every touch of the active page ensures it first
  (`Ot6CodexActive`), which finds it O9 after any load or New Game. Reveals
  write the active codex page in place
  (slot 1-3, or the New-Game page before the first save); a victory adds
  Magic Points to the live esper page and sets its pending lines.
- **Save.** `CopyGameDataToSRAM`: `Ot6CodexSaveAs` copies the live esper
  page into the destination slot's esper page (signed); `Ot6SaveSign`
  signs an unsigned block (zeroing `$1E2F-$1E3F` and `$1FF7-$1FFD` first)
  and zeroes the destination's codex and esper page reserves; it copies the
  active codex page into the destination's when they differ (Save over
  another slot, or the first save of a New Game); then `$1FF0` takes the
  slot, the block's checksum is computed, the block is copied into the
  slot, and the validity words are rewritten.

### State outside the slot

Three things a player may think of as part of a save are not in its slot:

- **The codex is written in place.** A reveal goes straight to the slot's
  codex page, not to WRAM, so reloading a save does not take back a reveal
  made since; a reveal made in a game loaded from slot 1 is in slot 1's
  page even if the player never saves. (Save over another slot copies the
  page, so the copy is consistent from then on.)
- **The live esper page is shared.** Progress earned since the last save
  lives in `$3C00`, one page for the battery. A load replaces it with the
  loaded slot's, so it never leaks between slots, but a battery copied out
  mid-play carries it.
- **`$1FF0` and `$1FF1` are shared.** The last-saved slot and the seed the
  encounter counters start from.

## Reserve and the layout version

Reserved space for v1.y:

| Where | Bytes | Zero guaranteed? |
|---|---|---|
| Save block `OT6_SAVERSV` `$1E2F-$1E3F`, `OT6_SAVETAIL` `$1FF7-$1FFD` | 24 per slot | In a signed block (`OT6_SAVESIG` = `$5653`): zeroed when it was first signed. An unsigned block (a save from v0.44 or earlier) may hold junk until its first save on v0.45 or later |
| Codex page pads `+$002-$00F` and tails `+$310-$3FF`, slots 1-3 | 254 per page | In a slot saved by v0.45 or later: every save zeroes the destination's. Not in the New-Game page |
| Esper page pads `+$002-$00F` and tails `+$2B4-$3FF`, slots 1-3 | 346 per page | As the codex pages (`+$280-$2B3` was reserve until v0.51 and is now row 12) |
| Live esper page `+$002-$00F`, `+$306-$3FF` | 260 | No: never written |
| Battery `$1E00-$1FEF`, `$1FF2-$1FF7` | 502 | Yes, in any battery the load menu has cleared (`ClearSRAM`) |
| Battery `$4000-$7FFF` | 16384 | No: never written |

The save block's signature is the layout version. A block is signed when
`$1E2C-$1E2D` holds `$5653` and `$1E2E` holds a version from 1 through
`OT6_SAVEVER_CUR`; a block with the signature but version 0, or a version
past the build's own, is unsigned (junk can match two bytes, and a version
this build does not know promises nothing it can check). A save signs only
an unsigned block: it zeroes the reserve and the tail and writes the
signature and `OT6_SAVEVER_CUR`. A signed block
keeps its signature through every later save; a signed block of a lower
version is raised to `OT6_SAVEVER_CUR` at its next save, once the save has
written the fields the higher version adds.

A later release that adds a field to the reserve raises `OT6_SAVEVER_CUR`.
It reads the field only from a block signed with a version at least that
high and treats every lower version (and an unsigned block) as "absent".
It handles a lower signed version in `Ot6SaveSign`: at the save, it first
sets up the new field (its "absent" value, or whatever the field needs from
the rest of the block), then raises the version byte, so no block ever
claims a version whose fields it does not hold. A signing build also zeroes
the destination slot's codex and esper page pads and tails at every save
(the release that claims such bytes stops zeroing them).

Version 2 (v0.51, #552 piece F) is the first raise. Its field is the
esper pages' row 12 (`$x280-$x2B3` of each slot's page, `$3E80-$3EB3` live):
Magic Points for actor 12, Gogo's slot, who wears espers once revealed as
General Leo, while Summon is one of his picks ([leo-reveal.md](leo-reveal.md)). It sits in what was the
pages' tail reserve: zero in every slot a signing build (v0.45-v0.50) saved,
but a v0.44 page never had its tail zeroed, so the row is read only from a
block that says version 2 (`Ot6EsperLeoRow`, at every load: the slot's row
is copied live when the block is signed with version 2 or more, and the live
row cleared otherwise). An older save therefore loads with Leo holding no
esper progress, whatever its page's tail holds, and Gogo's worn-esper byte
(`$161E` of record 12) is `$FF` in every golden save and tracked checkpoint
(checked: `build/attempts/wt/v051-leo-espers/row12_saves.txt`), so he
wears nothing either. Its first save copies the live row (zeros, or what was
earned since the load) into the slot, then raises the block to version 2.
Nothing else in the block changes meaning, so version 1 is otherwise read
exactly as before.

Rules for future fields elsewhere:

- **A codex-page field** changes the codex page's magic (as O8 became O9
  for the six classes at v0.51; the next takes a word no release has used,
  with a migration from O9, O8 and O7), not `OT6_SAVEVER`: the codex page
  is written in place during play, before any save, so its own magic is
  what says what it holds.
- **A field in a shared battery range** (`$1E00-$1FEF`, `$1FF2-$1FF7`, the
  live page's reserve) treats zero as absent: no slot signature covers it.
- **A new signed page in `$4000-$7FFF`** uses a 32-bit magic, not 16-bit:
  the range is never cleared, and a longer magic makes a junk match
  negligible.
- **OT6 events keep to parties 1-3.** `ChangeParty` writes the party's Z
  level at `$1FF3 + party`; a party number past 3 would write into the
  reserved tail `$1FF7-$1FFD`.

`$4000-$7FFF`, the live page's reserve and the New-Game codex page's are
never written, and banks `$31-$33` are never cleared, so they can hold
anything an emulator or cartridge left in the battery. They are left alone
at New Game and at signing on purpose: nothing could later tell a cleared
range from junk, and a range shared by all slots has no one slot's
signature to key on. A future field there lives in a signed page of its own
(a magic word an older battery cannot hold by accident, initialized by the
build that first writes it, one page per slot copied at save and load as
the esper pages are), and an unsigned page reads as absent.

## The six-class codex

v0.51 (#566) replaced the four weapon classes with six. A codex page's
class table still holds one byte of revealed classes per species, but the
byte's bits changed meaning, so the page's magic changed with them: O9
(`OT6_CODEX_V3`) is a page of six-class bytes, O8 a page of four-class
bytes. `OT6_SAVEVER` is untouched (it stays 2): the save block holds no
class data, and the rule above puts a codex-page change in the page's own
magic.

Each of a species' four-class weaknesses became exactly one of that class's
two children, so a revealed four-class bit has one meaning per species.
`Ot6ClassSplitTbl` (`ot6_class_split.inc`, one byte per species id 0-383)
records which: bit k set means the weakness of four-class bit k became its
second child, clear its first. `tools/check_save_layout.py` holds this table
to the build:

| Four-class bit | Class | First child | Second child |
|---|---|---|---|
| $01 | slash | OT6_SWORD `$01` | OT6_KATANA `$10` |
| $02 | pierce | OT6_DAGGER `$02` | OT6_SPEAR `$20` |
| $04 | bludgeon | OT6_FIST `$04` | OT6_ARCANE `$08` |
| $08 | special | OT6_ARCANE `$08` | OT6_DAGGER `$02` |

The migration (`Ot6CodexSix`, run by `Ot6CodexEnsure` when it meets an O8
page, and on each clone of an O7 codex): every class byte becomes, for each
of bits `$01`-`$08` set in it, the child the table above and the species'
split byte name; every other bit is dropped; the element table, the pad and
the tail are not touched; then the page is signed O9. A first child keeps
its parent's bit, so only second children move.

- **When.** At the first load of the slot on a six-class ROM (the title's
  Continue or the reload after a game over), while the load menu owns the
  machine. `Ot6CodexEnsure` also runs before every battle and save touch of
  the active page, so a four-class page that reaches play some other way is
  still migrated before it is read. A slot that is never loaded keeps its O8
  page until it is; Save over another slot copies the loaded slot's page,
  already O9, over it.
- **Once.** The magic is the only record that a page has been rewritten,
  and the rewrite is not repeatable (a Katana or Spear bit read again as
  four-class would be dropped), so the magic is written last and nothing
  writes O8 again. Its two bytes differ from O8's only in the high byte, so
  the signing is one byte's write. A console that loses power inside the
  384-byte rewrite keeps O8 over a part-rewritten table, and the next load
  rewrites all of it: a reveal already moved to Katana or Spear can be lost
  and has to be found again. An O7 migration rewrites page 1 last, so its
  O7 magic restarts an interrupted one from a whole payload.
- **No lie on screen.** A revealed bit the species' six-class row does not
  answer to stays in the page and is never drawn: the seed masks the page's
  byte with the body's row (`Ot6SeedShields`, `and OT6_BP_CLASS,y`). That
  covers a save from a release whose row for the species differed from
  v0.50's (three such species in the v0.28-v0.44 golden saves), any later
  change to a row, and a part-migrated page. The next reveal for that
  species writes the byte afresh, without the stale bit.
- **The table is history.** `Ot6ClassSplitTbl` says what v0.50's saves
  mean. Once v0.51 is published it never changes, even when a species'
  row does: a changed row is a content change, and the mask above keeps it
  honest.
- **Old tools' names.** The harness's checkpoint layout tag stays
  `ot6-codex-o8-v1` (`OT6_CHECKPOINT_LAYOUT`, each checkpoint's
  `persistent_layout`): it names the family of batteries a step can
  Continue, and today's ROM Continues an O8 battery as well as an O9 one.

### Going back to four classes

The owner accepts that a later release may return to four classes (#566,
2026-11-23). What that release would have to do, and what it would cost:

- **Saves in the field then:** O9 pages (six-class bytes, from every save
  loaded on v0.51), O8 pages (never loaded on v0.51, still four-class and
  still right) and, in principle, O7.
- **A new magic, not O8 again.** A migrated magic is never written again
  (the policy above), so the four-class page of that release takes a word
  no release has used. Its `Ot6CodexEnsure` would: leave the new magic
  alone; re-sign an O8 page as it is (masking each class byte to `$0F`);
  clone an O7 codex and re-sign the clones; and map an O9 page's bytes back
  (below). `OT6_SAVEVER` and the save block are again untouched: nothing in
  the block depends on the class count.
- **Six to four.** Every child has a parent, so each six-class bit maps
  back: Sword and Katana to slash, Spear to pierce, Fist to bludgeon. Dagger
  is pierce's first child and special's second, and Arcane special's first
  and bludgeon's second, so those two need the species: with
  `Ot6ClassSplitTbl`, a revealed Dagger is special where the species' split
  byte has bit `$08` and pierce otherwise, and a revealed Arcane is
  bludgeon where it has bit `$04` and special otherwise. (Without the
  table, reveal both parents and let the seed's row mask keep the one the
  species answers to: never a false weakness, at worst a true one shown
  before it was found.) What is lost is only the distinction the six
  classes added: a save that had found Katana but not Sword shows slash.
- **The data.** The four-class rows (`Ot6ShieldTbl`, the generated floor),
  the weapon and skill class tables and the class constants come back from
  v0.50 (`git show v0.50:ff6/src/battle/ot6_hud.asm`, `ot6_class.asm`), or
  from the six-class rows through the same child-to-parent map
  (`ff6/tools/six_class_split.json` records how each row was split); a row
  edited after the split needs a person's call.
- **The checks.** `tools/golden_saves.py`'s `codex_loaded` gains the O9
  branch, the golden set by then holds v0.51's six-class saves to run it
  on, and `battle_sixcodex` gets a twin on one of them.

What keeps that cheap while six classes ship: the class table stays one
byte per species with the six bits where they are; a class added later has
a four-class parent; `Ot6ClassSplitTbl` stays in the tree unchanged; and
no other saved field starts to hold class bits (one that must would need
its own map back).

## Compatibility history of the v0 releases

How each release's saves load on the next, from the save-touching source's
history (`git log` on the files named at the top) and from loading saves
of eight releases on today's ROM through the golden-save suite
(`build/attempts/wt/v1-save-freeze/history/hist.check`, and the golden
runs beside it). The release
notes' "the vX.Y save layout" line is not evidence: up to v0.30 each notes
file named the previous release, and from v0.30 on the template kept
saying v0.29.

| Release | Loads the previous release's saves? | What changed in the save | Its saves on today's ROM |
|---|---|---|---|
| v0.1 | - | The codex: one cartridge-wide page at `$2000`, magic O7, and the 32 KiB battery | not tested (no saves shipped before v0.28) |
| v0.2-v0.4.1 | yes | nothing (v0.4 retired esper learning: spells already learned stay learned) | not tested |
| v0.5 | yes | The codex becomes per-save (O8, pages per slot); an O7 page is cloned into all three. The Bushido loadout `$1E1D` (new field) | not tested |
| v0.6 | yes | A save whose checksum sums to zero is stored as `$FFFF` (#18); before, the game treated it as empty | not tested |
| v0.7 | yes | Gau's Rage loadout `$1E1F` (new field) | not tested |
| v0.8 | yes, with content drift | Gau's command list (set when he joins): a save where he had joined keeps RAGE, LEAP, MAGIC, ITEM | not tested |
| v0.9-v0.12 | yes | nothing | not tested |
| v0.13 | yes | Strago's Lore loadout `$1E27` (new field) | not tested |
| v0.14-v0.22 | yes | nothing (v0.16: Shadow no longer leaves; the bit stays set) | not tested |
| v0.23 | yes, with content drift | Natural magic and esper lists replanned: spells learned under the old lists stay learned | not tested |
| v0.24-v0.27 | yes | nothing | not tested |
| v0.28 | yes, with content drift | Cleave is taught at the Phantom Train farewell instead of by level: a save already past the farewell never gets it (unless it had it). First release to ship saves | tested: Mt. Kolts, Esper Mountain and the Falcon after the Storm Dragon load and round-trip (golden set) |
| v0.29 | yes | nothing | tested: Mt. Kolts, Esper Mountain, the Falcon outside Narshe |
| v0.30-v0.43 | yes | nothing in the layout | tested: three saves each from v0.31, v0.35 and v0.42, and the golden sets of v0.40 and v0.43 (early, middle, World of Ruin, end game) |
| v0.44 | yes | Esper pages at `$3000-$3FFF` (new, signed); an older save loads with no esper progress | tested: 4 golden saves |
| v0.45 | yes | The save-block signature `$1E2C-$1E2E` (new field); the first save of an older block zeroes its reserve, every save zeroes the slot's page reserves, and a New Game zeroes the scrap | tested: every golden save, all unsigned, is signed at its first save |
| v0.46-v0.50 | yes | nothing in the layout (v0.49: event switch `$00E0`, a vanilla bit) | tested: four golden saves each |
| v0.51 | yes | Layout version 2: the esper pages' row 12 (actor 12) in the pages' former tail reserve, read only from a version-2 block; a version-1 block is raised at its first save. The codex page becomes O9: its class table holds six weapon classes, and an O8 page's revealed classes are rewritten at its first load, each to the child its species took ("The six-class codex") | in development: every golden save v0.28-v0.50 loads with its page migrated |

So no release has moved a field or read an old value under a new meaning:
every layout change was an append (six new fields) or a migration behind a
new magic word (two: the cartridge-wide codex to per-save pages at v0.5,
the class table to six classes at v0.51). Three releases
changed content that a save fixes when it is written (v0.8, v0.23, v0.28);
those saves load and play, without the new rule for what they already hold.

From v0.45 the notes' Saves section opens with "Saves from v0.28 and later
load in this release" (the oldest release in the golden set; from v1.0 on,
the oldest v1 release) and says what an older save lacks. `golden_saves.py
notes` refuses notes without that line or with a "save layout" phrase: on
docs/release-notes-next.md in `ninja` (`notes_saves`) and on the cut's notes
in `ninja release`.

## Checksum interaction

- `CalcSaveSlotChecksum` (`save.asm`) sums bytes `$1600` up to but not
  including `$1600 + $09FE` (`cpx #$09fe`), i.e. **`$1600-$1FFD`**, stores
  `$FFFF` when the sum is zero (#18), and the save writes the word at
  `$1FFE`. The stored word sits outside the summed range.
- The three OT6 fields and both reserved scraps are inside the summed
  range. An older save carrying any bytes there was summed over the same
  range by the older build, so its stored checksum still matches.
- The codex and esper pages are outside the slot and outside the checksum;
  their magic words stand in for it.

## Golden saves

`tools/tests/golden-saves/` keeps saves from published releases
(`MANIFEST.json`: each save's hash, the zip it came from, and whether its
release signs esper pages). For each one, qualification Continues it on
today's ROM, checks that the game it loads is the file's (tools/roster.py's
reading, gil, bag, map, tile, story switches), that its codex page is the
file's, migrated (byte for byte the page `Ot6CodexEnsure` must make of
the file's: for an O8 page the class table rewritten by the built ROM's
`Ot6ClassSplitTbl`, the element table, pad and tail as they were, the magic
O9; the rewrite ran once at the first load and not again at the saves or
the second load) and that its
esper progress carries over (none for a save from before v0.44, and none
in row 12 for a block older than version 2: the live row must be zero
whatever the slot's page holds there), saves into
the same slot, reloads, and checks that the battery changed only inside the
ranges the battery map says today's ROM writes. The run saves twice. The
first save of a save from before v0.45 must sign it, zero its reserve and
tail, and change nothing else in the block (the loadouts included)
but the play time, the timers and the checksum (read against the block at
`CopyGameDataToSRAM`'s entry); the reload must read that save back byte for
byte; the first save of a version-1 block (v0.45-v0.50) must raise its
version to 2 and change nothing else but the save's own bytes; the second
save, of a block signed with today's version, must change only the play
time, timers and checksum. After each save the slot's esper page, row 12
included, is the live page. A copy of a v0.44 save with its esper signature
zeroed is the negative: the check must refuse it.

`golden-saves/junk/` holds synthetic saves built from v0.44 ones, carrying
the `$FF` an all-ones console leaves: in the reserve and tail, in every
codex and esper page's pads and tails, and in `$4000-$7FFF`.

- `v0.44-wor-cyan` also has `$FF` loadouts: its first save keeps them as
  they are and zeroes slot 3's reserves. The run then saves over slot 1 (Save
  over another slot): slot 1's page pads and tails must be zero, its codex
  magic and tables slot 3's and its esper page the live page; slot 3's
  pages and `$4000-$7FFF` must be untouched.
- `v0.44-sig-ver0` and `v0.44-sig-verFF` carry the signature with version
  0 or `$FF`: each must be treated as unsigned, so its first save zeroes the
  reserve and signs it version 2.
- every junk save's slot pages carry `$FF` in what is now row 12: its load
  must read row 12 as no progress (the live row zero), and its first save
  writes the live row's zeros there.
- `v0.46-kolts-classff` is `v0.46/kolts-summit-v1` with every byte of slot
  3's class table `$FF` (`golden_saves.py classff` builds it and `verify`
  holds it to that): all four classes revealed for every species, and four
  bits no four-class build wrote. Its load must migrate every byte exactly
  (the four high bits dropped), and `battle_sixcodex` reads it in battle.
- `v0.44-mixed` (from `wor-gau-v1`, `$1CF7` = `$BF`) carries the Bushido
  word the page seeds there (`$0F64`, slot 0 set) and real Rage and Lore
  bytes beside impossible ones (an unlearned rage, a lore byte `$19`, an
  unlearned lore, `$FF`): the first save keeps every one of them.

The New Game's first save is the play from power-on's first save
(`world-narshe-v1`, `gen_worldmap`); `first_save_signed` checks that
capture: signed `$5653` version 2, its reserve, tail and page reserves zero,
its loadouts AUTO.

`battle_newgameloadouts` starts a New Game under an all-ones power-on fill,
reads the scrap and tail, then Continues a v0.44 save seating Gau
(`wor-gau-v1`) or Strago (`wor-opera-v1`), puts the New Game's loadout
bytes in its loadouts, and reads the lists a random battle builds: AUTO's
eight rages, AUTO's five lores and the free row.

`battle_sixcodex` Continues a four-class Mt. Kolts save, walks onto the
cliff beside its save room and reads every body of a random battle before
anyone acts: the species' class byte in the migrated page against the
file's byte and the ROM's split byte, and the body's revealed classes
(`$3EA5` + slot x 2) against the page's byte masked by the body's row. On
`v0.46/kolts-summit-v1` as published it must find a weakness that took its
first child and one that took its second; on `v0.46-kolts-classff` also a
revealed bit the row does not answer to, kept in the page and not drawn,
and the four dropped bits. Then the console's Reset, a second Continue and
the same battle again: the rewrite has still run once, and the whole page
is the file's, migrated.

Twelve mutant ROMs (`tools/build/mutant_rom.py`: the real build with one
routine returning at once, or a labelled seam rewritten) must go red:

- without `Ot6SaveSign`, the junk save's first save is unsigned;
- with the version test gone (`VerCheck`), `v0.44-sig-ver0` passes for
  signed: its version 0 is raised in place, and its junk reserve stays;
- without row 12's version test (`Ot6EsperLeoRow` returning at once), a
  junk save's `$FF` row 12 loads as Leo's progress;
- without the raise (`Raise`), a v0.50 save's first save keeps version 1;
- reading the slot loaded (`wSaveSlotToLoad`) instead of the slot saved
  into (`SlotAt`), the save over slot 1 leaves slot 1's page reserves
  junk;
- without `Ot6NewGameClear`, Gau's Rage list comes up empty;
- without `Ot6CodexSix`, a v0.50 save's codex page is not signed O9
  (the golden run and `battle_sixcodex`);
- with the rewrite's first children dropped (`SixFirst`), a v0.50 save's
  revealed classes are not the file's, migrated, and `battle_sixcodex`'s
  first child is missing from the page;
- with its second children dropped (`SixSecond`), `battle_sixcodex`'s
  second child is missing;
- with its four-bit mask gone (`SixFour`), the `$FF` fixture's class bytes
  keep bits past the four;
- with the seed's row mask gone (`SixMask`), the `$FF` fixture's stale
  classes are drawn;
- with every load running the rewrite (`LoadEnsure`), the second load
  runs it a second time (the golden run and `battle_sixcodex`).

At each release, after it is published, add its saves:

    gh release download vX.Y -p '*.zip' -D /tmp/ot6-vX.Y
    python3 tools/golden_saves.py add vX.Y /tmp/ot6-vX.Y/ot6-vX.Y.zip \
        kolts-summit-v1 esper-mtn-save-v1 wor-cyan-v1 wor-kt-plates-v1
    python3 configure.py && ninja

(an early, a middle, a World of Ruin and an end-game save; `--no-esper`
only for a release before v0.44) and commit the new `golden-saves/vX.Y/`
and `MANIFEST.json`.
