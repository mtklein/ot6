.ifndef OT6_MEMORY_INC
OT6_MEMORY_INC = 1

; OT6 memory ABI.  This file only names owned storage and proves its bounds;
; routine width/clobber contracts remain beside the routines that implement
; them.  Keep this include non-emitting.

; Per-entity battle state. Entity offsets are $00-$06 for characters and
; $08-$12 for monsters.
OT6_SHIELD_CUR       := $3e38
OT6_SHIELD_MAX       := $3e39
OT6_BROKEN_TICKS     := $3e88
OT6_REVEALED_ELEM    := $3e89
OT6_BP_CLASS         := $3e9c
OT6_BOOST_REVEALED   := $3e9d

.assert OT6_SHIELD_CUR + $12 < OT6_BROKEN_TICKS, error, "OT6 entity state overlaps"
.assert OT6_BROKEN_TICKS + $12 < OT6_BP_CLASS, error, "OT6 entity state overlaps"
.assert OT6_BOOST_REVEALED + $12 <= $3eaf, error, "OT6 entity state exceeds owned battle RAM"

; Per-save weakness codex. Each save owns a $400-byte SRAM page; the fourth
; page is transient knowledge for an unsaved New Game.
OT6_CODEX_ROOT       := $316000
OT6_CODEX_STRIDE     := $0400
OT6_CODEX_MAGIC      := OT6_CODEX_ROOT
OT6_CODEX            := OT6_CODEX_ROOT+$0010
OT6_CODEX_CLASS      := OT6_CODEX_ROOT+$0190
OT6_CODEX_TEMP       := $0c00
OT6_CODEX_USED       := $0310

.assert OT6_CODEX_ROOT >= $316000, error, "OT6 codex precedes expanded SRAM"
.assert OT6_CODEX_TEMP = 3 * OT6_CODEX_STRIDE, error, "transient codex is not page four"
.assert OT6_CODEX_CLASS + 384 <= OT6_CODEX_ROOT + OT6_CODEX_USED, error, "class codex exceeds used page"
.assert OT6_CODEX_USED <= OT6_CODEX_STRIDE, error, "OT6 codex page exceeds stride"
.assert OT6_CODEX_ROOT + OT6_CODEX_TEMP + OT6_CODEX_USED <= $317000, error, "OT6 codex exceeds expanded SRAM"

; Per-save working-data word, copied and checksummed by vanilla save code.
OT6_LOADOUT          := $7e1e1d
.assert (OT6_LOADOUT & $ffff) >= $1600, error, "loadout must sit inside the save block"
.assert (OT6_LOADOUT & $ffff) + 1 <= $1ffd, error, "loadout word must sit inside the checksum window"

; Battle-only scratch. InitBattle clears through $3ed3. OT6_DIVINE_USED is
; one per-character bitmask; the walkers use the interleaved even words.
OT6_DIVINE_USED      := $3ecb
OT6_SCR_SLOT2        := $3ecc
OT6_SCR_BIT          := $3ece
OT6_SCR_IDX          := $3ed0
OT6_SCR_COLS         := $3ed2

.assert OT6_DIVINE_USED >= $3ecb, error, "OT6 battle scratch precedes owned range"
.assert OT6_SCR_COLS + 1 <= $3ed3, error, "OT6 battle scratch exceeds owned range"

; Battle/HUD global scratch.
OT6_MAPBASE          := $57b6
OT6_ATKCLASS         := $57b8
OT6_FONTDIRTY        := $57b9
OT6_SLOTTIER         := $57ba   ; Slot's latched boost tier (#31 backfill):
                                ;   written at the spin's first A press by
                                ;   Ot6SlotRig, re-banked into
                                ;   OT6_BOOST_REVEALED by Ot6SlotCommit so
                                ;   Ot6ActionEnd charges what the reels
                                ;   delivered (ot6_kits.asm, the Slot strip)
OT6_RANDPEND         := $57bc
OT6_RANDBTL          := $57bd
OT6_HUDVEIL          := $57be
OT6_SCRIPTBUSY       := $57bf
OT6_SPECIES          := $57c0
OT6_PIPCUR           := $57cc
OT6_PIPPREV          := $57ce
OT6_PIPCELL          := $57d0
OT6_LASTLR           := $57d2
OT6_RESTAGE          := $57d4

.assert OT6_MAPBASE + 1 < OT6_ATKCLASS, error, "OT6 HUD scratch overlaps"
.assert OT6_ATKCLASS < OT6_FONTDIRTY, error, "OT6 HUD scratch overlaps"
.assert OT6_RANDPEND + 3 = OT6_SCRIPTBUSY, error, "OT6 HUD flags are not contiguous"
.assert OT6_SCRIPTBUSY < OT6_SPECIES, error, "OT6 HUD scratch overlaps"
.assert OT6_SPECIES + 11 < OT6_PIPCUR, error, "OT6 species and pip scratch overlap"
.assert OT6_RESTAGE = $57d4, error, "OT6 restage byte moved outside owned range"

; BG HUD line shadow buffer.
OT6_SHADOW           := $ecf1
.assert OT6_SHADOW + (14 * 6) - 1 <= $ed44, error, "OT6 HUD shadow exceeds owned range"

.endif
