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
`battle/ot6_codex.asm`, `battle/ot6_esper.asm` and `battle/ot6_memory.inc`.

## Compatibility policy

Only upgrades matter: a newer ROM must load older saves. A save made on a
newer ROM and loaded on an older one is not supported, and no design or
test effort goes into it.

A v1.y.z change **may**:

- use reserved space for a new field, provided the field's "absent" value
  is what an older save holds there (see "Reserve" below: zero only where
  zero is guaranteed, otherwise behind a signature);
- add a new signed page in reserved battery space: a magic word that an
  older battery cannot hold by accident, and "unsigned reads as absent";
- give an existing signed page a new magic word, provided the new ROM
  migrates every older magic it may meet (as the codex's O7-to-O8 step
  does) and never writes the older magic again;
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
are wrong (`ClearSRAM`, battery `$0000-$1FFF` only), `never` never.

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
| $2000-$2001 | 2 | slot1 | Codex page, slot 1: magic (`$384F` O8; `$374F` O7 is the pre-v0.5 global codex) | OT6_CODEX_MAGIC | load, play, save | Any other value: the page is zeroed and signed before use, so the codex starts empty; O7 is cloned into all three slots once |
| $2002-$200F | 14 | slot1 | Reserved | - | never | - |
| $2010-$218F | 384 | slot1 | Revealed weak elements, one byte per species | OT6_CODEX | load, play, save | Zero: nothing revealed |
| $2190-$230F | 384 | slot1 | Revealed break class, one byte per species | OT6_CODEX_CLASS | load, play, save | Zero: nothing revealed |
| $2310-$23FF | 240 | slot1 | Reserved | OT6_CODEX_ROOT+OT6_CODEX_USED | never | - |
| $2400-$2401 | 2 | slot2 | Codex page, slot 2: magic | OT6_CODEX_MAGIC+OT6_CODEX_STRIDE | load, play, save | as slot 1 |
| $2402-$240F | 14 | slot2 | Reserved | - | never | - |
| $2410-$270F | 768 | slot2 | Revealed elements, then classes | OT6_CODEX+OT6_CODEX_STRIDE | load, play, save | Zero: nothing revealed |
| $2710-$27FF | 240 | slot2 | Reserved | - | never | - |
| $2800-$2801 | 2 | slot3 | Codex page, slot 3: magic | OT6_CODEX_MAGIC+$0800 | load, play, save | as slot 1 |
| $2802-$280F | 14 | slot3 | Reserved | - | never | - |
| $2810-$2B0F | 768 | slot3 | Revealed elements, then classes | OT6_CODEX+$0800 | load, play, save | Zero: nothing revealed |
| $2B10-$2BFF | 240 | slot3 | Reserved | - | never | - |
| $2C00-$2C01 | 2 | newgame | Codex page for an unsaved New Game: magic | OT6_CODEX_MAGIC+OT6_CODEX_TEMP | newgame, load, play | Zeroed and signed before use |
| $2C02-$2C0F | 14 | newgame | Reserved | - | never | - |
| $2C10-$2F0F | 768 | newgame | Revealed elements, then classes; the first save copies them into its slot | OT6_CODEX+OT6_CODEX_TEMP | newgame, load, play | Zero: nothing revealed |
| $2F10-$2FFF | 240 | newgame | Reserved | - | never | - |
| $3000-$3001 | 2 | slot1 | Esper page, slot 1: magic `$3145` ('E1') | OT6_ESPER_ROOT | save | Any other value: the slot has no esper progress |
| $3002-$300F | 14 | slot1 | Reserved | - | never | - |
| $3010-$327F | 624 | slot1 | Magic Points per character (actors 0-11) per esper slot (26, GenjuProp order, Odin and Raiden share one), little-endian words, actor-major, capped at 9999 | OT6_ESPER_ROOT+OT6_ESPER_CTR | save | Read only when signed |
| $3280-$33FF | 384 | slot1 | Reserved | OT6_ESPER_ROOT+OT6_ESPER_COPY | never | - |
| $3400-$3401 | 2 | slot2 | Esper page, slot 2: magic | OT6_ESPER_ROOT+OT6_ESPER_STRIDE | save | as slot 1 |
| $3402-$340F | 14 | slot2 | Reserved | - | never | - |
| $3410-$367F | 624 | slot2 | Magic Points, as slot 1 | - | save | Read only when signed |
| $3680-$37FF | 384 | slot2 | Reserved | - | never | - |
| $3800-$3801 | 2 | slot3 | Esper page, slot 3: magic | OT6_ESPER_ROOT+$0800 | save | as slot 1 |
| $3802-$380F | 14 | slot3 | Reserved | - | never | - |
| $3810-$3A7F | 624 | slot3 | Magic Points, as slot 1 | - | save | Read only when signed |
| $3A80-$3BFF | 384 | slot3 | Reserved | - | never | - |
| $3C00-$3C01 | 2 | shared | Live esper page: magic. The only page play reads and writes | OT6_ESPER_LIVE+OT6_ESPER_MAGIC | load, newgame, play, save | Unsigned: cleared and signed before use (no progress) |
| $3C02-$3C0F | 14 | shared | Reserved | - | never | - |
| $3C10-$3E7F | 624 | shared | Live Magic Points: a load copies its slot's page here, a victory adds to them, a save copies them into the slot | OT6_ESPER_LIVE+OT6_ESPER_CTR | load, newgame, play | - |
| $3E80-$3EFF | 128 | shared | Unused, zeroed with the counters | OT6_ESPER_LIVE+OT6_ESPER_COPY | load, newgame | - |
| $3F00-$3F03 | 4 | shared | Victory screen's pending rank lines, one byte per party slot | OT6_ESPER_LIVE+OT6_ESPER_PEND | load, newgame, play | Zero: none |
| $3F04-$3F05 | 2 | shared | Magic Points to announce on the victory screen (0 = none) | OT6_ESPER_LIVE+OT6_ESPER_SHOWN | load, newgame, play | Zero: none |
| $3F06-$3FFF | 250 | shared | Reserved | - | never | - |
| $4000-$7FFF | 16384 | shared | Reserved (banks `$32-$33`) | - | never | - |

## Magic words

| Symbol | Value | Meaning |
|---|---|---|
| OT6_CODEX_V2 | $384F | 'O8', a per-save codex page |
| OT6_CODEX_GLOBAL | $374F | 'O7', the v0.1-v0.4 cartridge-wide codex (page 1 only), migrated on first touch |
| OT6_ESPER_MAGIC_WORD | $3145 | 'E1', an esper page |

Vanilla's validity word `$E41B` (`menu_sram.asm`) is not an OT6 symbol.

## Save-block fields

The vanilla save block is WRAM `$1600-$1FFF`, copied whole into a slot on
save and back on load; `CalcSaveSlotChecksum` sums `$1600-$1FFD` and the
word lands at `$1FFE`. OT6 adds three fields in the range vanilla leaves
unused. Address is inclusive; Symbol is the ca65 name in
`ff6/src/battle/ot6_memory.inc`.

| Address | Bytes | Symbol | Meaning | Owner procs | Since | Old-save read |
|---------|-------|--------|---------|-------------|-------|---------------|
| $1E1D-$1E1E | 2 | OT6_LOADOUT | Cyan's Bushido loadout: a packed word, three bits per boost slot (slots 1/2/3 at bits 3-5/6-8/9-11), each a 0..7 SwdTech index. `$0000` = AUTO. | ot6_bushido.asm `Ot6BushidoTech` reads it in battle; ot6_loadout.asm `Ot6LoadoutAssign` writes a slot and `Ot6LoadoutInput` writes `$0000` to revert to AUTO; `Ot6LoadoutUnpack`/`Ot6LoadoutIsAuto`/`Ot6LoadoutSlotTech` read it in the field page. | v0.5 | `$0000` = AUTO. A non-zero word is decoded per slot and a slot naming an unlearned tech falls back to AUTO (`Ot6TechLearned`). |
| $1E1F-$1E26 | 8 | OT6_RAGELOAD | Gau's 8-slot Rage loadout, one byte per slot: byte = rage id + 1, `$00` = unset. All eight `$00` = AUTO. | ot6_rage.asm `Ot6RageList` builds the battle Rage list from it; `Ot6RageSeed` writes the window on the first edit, `Ot6RageCycleCore`/`Ot6RageInput` write field edits; `Ot6RageSlot`/`Ot6RageIsAuto` read it. | v0.7 | all `$00` = AUTO. A byte naming an unknown or unlearned rage is dropped from the list. |
| $1E27-$1E2B | 5 | OT6_LORELOAD | Strago's 5-slot Lore loadout, one byte per slot: byte = lore id + 1 (ids 0..23), `$00` = unset. All five `$00` = AUTO. | ot6_lore.asm `Ot6LoreMask`/`Ot6LoreMaskSet` build the battle Lore mask from it; `Ot6LoreSeed`, `Ot6LoreCycleCore`/`Ot6LoreInput` write it; `Ot6LoreSlot`/`Ot6LoreIsAuto` read it. | v0.13 | all `$00` = AUTO. A byte naming an unknown or unlearned lore is dropped from the mask. |

Declared free (reserved) space in the block:

- Scrap `$1E1D-$1E3F` (35 bytes). Used: `$1E1D-$1E2B`. Reserved:
  `$1E2C-$1E3F`, 20 bytes.
- Scrap `$1FF7-$1FFD` (7 bytes), vanilla's unused tail inside the checksum
  window. Reserved.

Neither is guaranteed zero. Vanilla's power-on clear (`ClearRAM`,
`field/reset.asm`) stops at WRAM `$11FF`, and a New Game initializes only
the fields it names, so these bytes start as whatever the console or
emulator left in RAM. Under an all-ones power-on fill a New Game leaves
`$FF` in all of `$1E1D-$1E3F` and `$1FF7-$1FFD`
(`build/attempts/wt/v1-save-freeze/poweron_allones_newgame.log`), and every
save of that game carries them until the player edits a loadout. Every save the harness makes is zero there because
the harness pins an all-zeros fill. So a new field here must either read
any byte value sensibly or wait for the layout signature proposed under
"Reserve and the layout version".

The three loadouts already meet such junk. The Bushido word reads `$FFFF`
as Cleave in every slot, and as AUTO while Cleave is unlearned. The Rage
and Lore loadouts read all-`$FF` bytes as a manual loadout whose every slot
names an unknown entry, so in such a game Gau's Rage list and Strago's
Lore list (but for the free row) are empty until the player sets the
loadout or resets it to AUTO on its page (read from `Ot6RageList` and
`Ot6LoreMask`; not measured in play).

`$1E40-$1E7F` is vanilla's treasure bitfield and `$1E80-$1F5F` its event
switches (all live game state); OT6 claims none of them.

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
| `$1E80-$1F5F` | Event switches | Read by OT6 code (`$00BF` Terra's return, `$0068` the tube room, `$00CA`, `$02E3` Shadow's initialization); OT6 sets no new switches; its three added save points ride vanilla's standing `$0632` |
| `$1F6E` | Random battle counter | `Ot6DangerStep` scales the step and adds it there |
| `$1616-$1619` | Battle commands | Gau's join gives FIGHT, RAGE, MAGIC, ITEM (v0.8; vanilla RAGE, LEAP, MAGIC, ITEM). Set when he joins, so a save where he joined earlier keeps the old list |

## Who writes what, and when

- **The title.** Start opens the load menu (`EventCmd_ab`, `GameLoadMenu`),
  which adds 1 to the seed `$1FF1` and 13 more as it closes. If the
  validity words are wrong, `ClearSRAM` zeroes battery `$0000-$1FFF` (the
  slots and bank `$30`'s tail; banks `$31-$33` are not cleared) and the
  menu ends at once in a New Game, with no slot list shown.
- **New Game.** `Ot6CodexNewGame` zeroes and signs the New-Game codex page
  `$2C00` and `Ot6EsperNewGame` clears and signs the live esper page
  `$3C00`. Nothing in a slot is written. (Measured on an all-ones power-on
  fill: `GameLoadMenu`, `CheckSRAM`, `ClearSRAM` and `Ot6CodexNewGame` each
  ran once, battery `$1E00` read 0 and both pages were signed afterwards,
  while bank `$31`'s slot pages and `$4000` still read `$FF`;
  `build/attempts/wt/v1-save-freeze/poweron_allones_newgame.log`.)
- **Continue** (title). The load menu copies the slot into WRAM `$1600`,
  the confirm runs `Ot6EsperContinue`, which copies the slot's esper page
  into the live page if signed and clears the live page if not.
- **Reload after a game over.** `LoadSavedGame` runs `Ot6CodexLoaded`:
  the slot's codex page is signed if it was not (zeroed first), O7 is
  migrated, and the esper copy runs as on a Continue.
- **Battle and field.** Reveals write the active codex page in place
  (slot 1-3, or the New-Game page before the first save); a victory adds
  Magic Points to the live esper page and sets its pending lines.
- **Save.** `CopyGameDataToSRAM`: `Ot6CodexSaveAs` copies the live esper
  page into the destination slot's esper page (signed), and copies the
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
| Save block `$1E2C-$1E3F`, `$1FF7-$1FFD` | 27 per slot | No: power-on junk from a New Game |
| Codex page tails `+$310-$3FF`, pads `+$002-$00F` | 254 per page | No: bank `$31` is never cleared, and an emulator can fill SRAM with junk; inside a signed page, but the page's zeroing covers only `+$010-$30F` |
| Esper page tails `+$280-$3FF`, pads `+$002-$00F` | 398 per page | No, for the same reason (the live page's `+$280-$305` is zeroed) |
| Battery `$1E00-$1FEF`, `$1FF2-$1FF7` | 502 | Yes, in any battery the game has validated (`ClearSRAM`) |
| Battery `$4000-$7FFF` | 16384 | No: never written |

So, with no ROM change, a v1.y field goes in one of two places: a new
signed page in `$4000-$7FFF` (one per slot, copied on save and load as the
esper pages are), or `$1E00-$1FEF`. The in-slot reserve takes only fields
that read any value sensibly.

There is no layout-version byte today. Each OT6 region has its own magic
word (O8, E1), which works as a per-region version, and every change so far
has been an append. The recommendation for v1.0 (not yet built; #389) is a
small ROM change: a two-byte signature and a version byte in the save block
at `$1E2C-$1E2E`, written by every save, which zeroes `$1E2F-$1E3F` and
`$1FF7-$1FFD` the first time it signs a block. A later release then reads
"signed, version N" as a promise that the reserve was zero when version N
wrote it, and a v1.y field there needs no junk tolerance.

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

So no release has moved or re-encoded a field: every layout change was an
append (four new fields, one migration), the last at v0.44. Three releases
changed content that a save fixes when it is written (v0.8, v0.23, v0.28);
those saves load and play, without the new rule for what they already hold.

From now on the notes' line should say which saves load, not name a
layout: "Saves from v1.0 and later load in this release" (or, before v1.0,
"Saves from v0.X load; ..." with what an older save lacks, as v0.44's did
for esper progress).

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
reading, gil, bag, map, tile, story switches), that its codex page and
esper progress carry over (none for a save from before v0.44), saves into
the same slot, reloads, and checks that the battery changed only inside the
ranges the battery map says today's ROM writes. A copy of a v0.44 save with
its esper signature zeroed is the negative: the check must refuse it.

At each release, after it is published, add its saves:

    gh release download vX.Y -p '*.zip' -D /tmp/ot6-vX.Y
    python3 tools/golden_saves.py add vX.Y /tmp/ot6-vX.Y/ot6-vX.Y.zip \
        kolts-summit-v1 esper-mtn-save-v1 wor-cyan-v1 wor-kt-plates-v1
    python3 configure.py && ninja

(an early, a middle, a World of Ruin and an end-game save; `--no-esper`
only for a release before v0.44) and commit the new `golden-saves/vX.Y/`
and `MANIFEST.json`.
