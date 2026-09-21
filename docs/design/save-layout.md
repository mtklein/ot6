# OT6 save layout

Every byte OT6 owns in a saved game, and the rules that keep an old `.srm`
loadable by a newer build. From v0.21 onward this file is a compatibility
contract: the fields below do not move or change meaning, and
`tools/check_save_layout.py` fails the build if the assembled symbols and
this table disagree.

OT6 stores persistent state in two places:

1. The vanilla save block, WRAM `$1600-$1FFF`. `CopyGameDataToSRAM`
   (`ff6/src/menu/save.asm`) copies all `$0A00` bytes of it into the SRAM
   slot on save and `LoadSaveSlot` copies them back on load;
   `CalcSaveSlotChecksum` sums `$1600-$1FFD` and stores the word at `$1FFE`.
   OT6 claims three fields inside the range vanilla leaves unused.
2. Expanded SRAM, bank `$31`, the per-save weakness codex. This is outside
   any vanilla slot and is validated by its own magic word, not the vanilla
   checksum. See the codex section below.

## Save-block fields (`$1600-$1FFF`)

One field per row. Address is inclusive. Symbol is the ca65 name in
`ff6/src/battle/ot6_memory.inc`; the build's debug file
(`ff6/rom/ff6-en.dbg`) resolves each to the bank-`$7E` WRAM address whose low
word is shown. "Since" is the release the field first shipped in
(`git log -S<symbol> --oneline | tail -1`, mapped to the earliest tag that
contains that commit). "Old-save read" is what the field yields when a save
written before the field existed (or by any older build) is loaded here.

| Address | Bytes | Symbol | Meaning | Owner procs | Since | Old-save read |
|---------|-------|--------|---------|-------------|-------|---------------|
| $1E1D-$1E1E | 2 | OT6_LOADOUT | Cyan's Bushido loadout: a packed word, three bits per boost slot (slots 1/2/3 at bits 3-5/6-8/9-11), each a 0..7 SwdTech index. `$0000` = AUTO. | ot6_bushido.asm `Ot6BushidoTech` reads it in battle; ot6_loadout.asm `Ot6LoadoutAssign` writes a slot and `Ot6LoadoutInput` writes `$0000` to revert to AUTO; `Ot6LoadoutUnpack`/`Ot6LoadoutIsAuto`/`Ot6LoadoutSlotTech` read it in the field page. | v0.5 | `$0000` = AUTO (the moving window). A stale non-zero word is decoded per slot and any slot naming an unlearned tech falls back to AUTO (`Ot6TechLearned`), so it never selects an uncastable tech. |
| $1E1F-$1E26 | 8 | OT6_RAGELOAD | Gau's 8-slot Rage loadout, one byte per slot: byte = rage id + 1, `$00` = unset. All eight `$00` = AUTO. | ot6_rage.asm `Ot6RageList` builds the battle Rage list from it; `Ot6RageSeed` writes the initial word, `Ot6RageCycleCore`/`Ot6RageInput` write field edits; `Ot6RageSlot`/`Ot6RageIsAuto` read it. | v0.7 | all `$00` = AUTO (first eight known rages in id order). A stale byte naming an unknown or unlearned rage is dropped from the list, so it never offers an uncastable rage. |
| $1E27-$1E2B | 5 | OT6_LORELOAD | Strago's 5-slot Lore loadout, one byte per slot: byte = lore id + 1 (ids 0..23), `$00` = unset. All five `$00` = AUTO. | ot6_lore.asm `Ot6LoreMask`/`Ot6LoreMaskSet` build the battle Lore mask from it; `Ot6LoreSeed` writes the initial word, `Ot6LoreCycleCore`/`Ot6LoreInput` write field edits; `Ot6LoreSlot`/`Ot6LoreIsAuto` read it. | v0.13 | all `$00` = AUTO (first five known lores in id order). A stale byte naming an unknown or unlearned lore is dropped from the mask. |

The three fields are contiguous: `$1E1D-$1E2B`, 15 bytes, the head of the
`$1E1D-$1E3F` scrap. The `.assert` chain in `ot6_memory.inc` proves they abut
without a gap and stay inside the checksum window.

## Expanded SRAM: the weakness codex (bank `$31`)

Per-save record of which enemy weaknesses the player has revealed. It lives
in expanded SRAM, not in a vanilla slot, and rides inside the 32 KiB battery
(`.srm`): the SRAM `$6000-$7FFF` window of banks `$30-$33` maps to battery
offsets `$0000-$7FFF`, so bank `$31` (codex root `$316000`) begins at battery
offset `$2000`. It is NOT covered by `CalcSaveSlotChecksum`; each page carries
a two-byte magic word and `Ot6CodexEnsure` (ot6_codex.asm) re-initializes any
page whose magic is wrong.

Four `$0400`-byte pages: one per save slot (1/2/3) plus a transient page for
an unsaved New Game. Each page uses `$0310` of its `$0400` bytes.

| Address (page 1) | Bytes | Symbol | Meaning | Owner procs | Since |
|------------------|-------|--------|---------|-------------|-------|
| $316000-$316001 | 2 | OT6_CODEX_MAGIC | Page signature. `$384F` ('O8') is the current per-save layout; `$374F` ('O7') is the legacy cartridge-global layout, migrated to O8 on first load. | ot6_codex.asm `Ot6CodexEnsure`/`Ot6CodexActive` | v0.5 |
| $316010-$31618F | 384 | OT6_CODEX | Revealed weak elements, one byte per species (384 species). | ot6_break.asm reveal path; ot6_codex.asm | v0.5 |
| $316190-$31630F | 384 | OT6_CODEX_CLASS | Revealed break class, one byte per species. | ot6_break.asm reveal path; ot6_codex.asm | v0.5 |

Page stride is `OT6_CODEX_STRIDE` (`$0400`): slot 2 at `$316400`, slot 3 at
`$316800`, transient at `$316C00`. Old-save read: a page with no valid magic
(a fresh cartridge, or a slot never used) is initialized blank, so the codex
starts empty and refills through play; an O7 page is cloned into all three
slots once, then stamped O8, so existing players lose no knowledge.

## Free space

- Scrap `$1E1D-$1E3F` (35 bytes). Used: `$1E1D-$1E2B` (the 15 bytes above).
  Free: **`$1E2C-$1E3F`, 20 bytes**, for new save-block fields.
- Codex page (`$0400` stride). Used: `$316000-$31630F` (`$0310` bytes). Free:
  **`$316310-$3163FF`, 240 bytes per page**, for new per-save codex data.

`$1E70-$1E7F` is **not** free, despite the community note in
`docs/research/ram-and-rom-space.md`. `$1E40-$1E7F` is vanilla's
treasure-opened bitfield: `player.asm:790-795` sets a bit and `event.asm:5549`
clears the range, indexed `0..63` from the 9-bit treasure id shifted right
three (`player.asm:786-788`), so all 64 bytes are live game state
(`ff6/notes/field-ram.txt:1035`). Do not claim any of `$1E40-$1E7F`.

## Rules from here

- **Append only.** A new save-block field takes the next bytes of documented
  free space (`$1E2C` upward). Add the symbol to `ot6_memory.inc` with a
  `.assert` proving its bounds, and add a row here, before the field ships.
- **No field moves or changes meaning.** An existing address keeps its symbol,
  width, and encoding forever. `$00`/`$0000` stays the "unset / AUTO" sentinel
  so that older saves, which carry zero in bytes their build never wrote, read
  as AUTO.
- **A removed field stays reserved.** If a field is retired, leave its row
  here marked reserved and do not reuse its bytes; a future load of an old
  save may still carry a value there.
- **A layout change bumps a marker.** There is no layout-version byte in the
  save block today, because every change so far has been a backward-compatible
  append. If a future change is ever not backward-compatible, add a version
  byte in the free scrap first and bump it on the change; this table records
  when that happens.

## Checksum interaction

Verified by reading `ff6/src/menu/save.asm`, not assumed:

- `CalcSaveSlotChecksum` (`save.asm`, label `@19d1`) sums bytes `$1600` up to
  but not including `$09FE` past `$1600` (loop terminates on `cpx #$09FE`),
  i.e. it covers **`$1600-$1FFD`**, and stores the 16-bit sum at `$1FFE`
  (`CopyGameDataToSRAM`, `save.asm:@151d`). The stored word at `$1FFE-$1FFF`
  sits outside the summed range.
- All three OT6 save-block fields (`$1E1D-$1E2B`) are inside `$1600-$1FFD`, so
  they are checksummed on both write and verify. An older save that carries
  zero in those bytes was checksummed over the same range by the older build,
  so its stored checksum still matches here and the slot validates. This was
  confirmed against 28 tracked batteries: recomputing the sum over each slot's
  `$1600-$1FFD` reproduces the stored `$1FFE` word for every one.
- The codex (bank `$31`) is outside `$1600-$1FFF` and is not part of this
  checksum. It is validated by `OT6_CODEX_MAGIC` instead.

## Fixtures carrying these bytes

- **Tracked SRAM checkpoints**, `tools/tests/checkpoints/*/*.sram` (28 batteries,
  32 KiB each). The saved `$1600` block lives at battery offset
  `SLOT_PTR[slot] + (address - 0x1600)` with `SLOT_PTR = {1:0x0000, 2:0x0A00,
  3:0x1400}` (`tools/tests/lib/sram_checkpoint.py`), and the codex at the
  bank-`$31` window (offset `$2000+`). `docs/research/data-formats.md:178-181`
  explains why this offset reads both a savestate and a checkpoint.
- **Savestates** (`.mss`) captured by the `gen_*` cutters carry the live WRAM
  `$1600` block directly.
- `tools/audit_*.py` and `tools/tests/lib/sram_checkpoint.py` read the block
  from both. `tools/check_save_layout.py` reads the assembled symbol addresses
  from `ff6/rom/ff6-en.dbg` and checks them against the table above.
