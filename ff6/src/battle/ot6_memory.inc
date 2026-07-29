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
OT6_PIPTAIL          := $57bb   ; #33: frames of live pip painting left after
                                ;   an ActionEnd with the battle menu closed
                                ;   -- keeps the charge visible on its own
                                ;   frame.  set by Ot6ActionEnd (characters),
                                ;   decremented by Ot6PipStage, cleared by
                                ;   InitBP (init-exempt strip: power-on junk
                                ;   would paint pips over the intro).
OT6_RANDPEND         := $57bc
OT6_RANDBTL          := $57bd
OT6_HUDVEIL          := $57be
OT6_SCRIPTBUSY       := $57bf
OT6_SPECIES          := $57c0
OT6_PIPCUR           := $57cc   ; live pip cell (0 = off); #33 keeps the
OT6_PIPPREV          := $57ce   ;   one-cell footprint and moves only WHICH
OT6_PIPCELL          := $57d0   ;   cell it is (see Ot6PipStage)
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

; The shadow tail: the same measured-free $7eecf1-$7ef11f range the shadow
; claims (ot6_hud.asm's four lines of evidence; PushMode7Vars owns $f120+).
;
; #33 pending reveals: a chip banks its newly-revealed weakness bits here at
; damage-CALC time; Ot6RevealCommit moves them into OT6_REVEALED_ELEM /
; monster OT6_BOOST_REVEALED (and every same-species slot) on the DAMAGE
; frame (the first numeral display, GfxCmd_0b), with Ot6ActionEnd as the
; no-numeral backstop.  One byte per monster slot, stride 2 (indexed by the
; slot offset 0,2..10 like $3e91/$3ea5; odd bytes unused).  Cleared by
; InitBP's shadow clear and per-slot by Ot6SeedShields (Cmd_20 reloads).
OT6_RVPEND_ELEM      := $ed45   ; 12 bytes
OT6_RVPEND_CLS       := $ed51   ; 12 bytes
; #35 wallet pseudo-line: current-MP display painted into the open costed
; list window every nmi.  CUR/PREV are the first cell's vram word address
; (0 = off; prev != cur blanks the old cells one-shot), CELLS the staged
; glyph|attr words.  CUR/PREV cleared by InitBP's extended shadow clear.
OT6_WALLETCUR        := $ed5d
OT6_WALLETPREV       := $ed5f
OT6_WALLET_W         = 5        ; [M][P][hundreds][tens][ones]
OT6_WALLETCELLS      := $ed61   ; OT6_WALLET_W words
OT6_WALLETSIG        := $ed6d   ; staged MP value; the flush repaints only
OT6_WALLETSIGP       := $ed6f   ;   when CUR or SIG moves (see the flush)
OT6_PIPSLOT          := $ed6b   ; #33: the character slot the live pip cell
                                ;   follows while OT6_PIPTAIL runs -- the one
                                ;   who just spent BP (Ot6ActionEnd sets both)
OT6_NUMCTR           := $ed71   ; #33: last-seen damage-numeral thread counter
                                ;   ($632e).  a change means GfxCmd_0b just
                                ;   allocated a numeral -- the damage frame --
                                ;   and Ot6RevealPoll commits pending reveals.
                                ;   past InitBP's clear on purpose: a stale
                                ;   value costs one no-op commit (see the proc)
OT6_COVERPAID        := $ed72   ; #37: per-character bitmask (----1234, the
                                ;   OT6_DIVINE_USED / $3f2f shape) -- bit set =
                                ;   that character's True Knight cover has
                                ;   already banked its BP this ROUND.  set by
                                ;   Ot6CoverBP, cleared per character by
                                ;   Ot6ActionEnd (the round boundary) and
                                ;   wholesale by InitBP.  unlike NUMCTR a stale
                                ;   value here would SUPPRESS a real earn, so
                                ;   it is init-cleared explicitly.
.assert OT6_RVPEND_ELEM = OT6_SHADOW + (14 * 6), error, "reveal-pending must follow the shadow (InitBP clears both in one loop)"
.assert OT6_WALLETPREV + 1 <= OT6_SHADOW + $70 - 1, error, "wallet cur/prev must sit inside InitBP's $70-byte clear"
.assert OT6_COVERPAID = OT6_NUMCTR + 1, error, "cover-earn latch must follow the numeral counter (both live past InitBP's shadow clear)"
.assert OT6_COVERPAID > OT6_SHADOW + $70 - 1, error, "cover-earn latch must sit PAST InitBP's shadow clear (it is cleared by its own store)"
.assert OT6_COVERPAID + 1 <= $ef1f, error, "OT6 shadow tail exceeds the measured-free range ($f120+ is PushMode7Vars')"

.endif
