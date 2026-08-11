; Per-save weakness codex.  Each save owns a $400-byte page in SRAM bank
; $31; only $310 bytes are currently used (magic + two 384-species tables).
; A fourth page is transient knowledge for an unsaved New Game, so it never
; inherits slot 1. The active page is 0 for transient or 1..3 for a saved
; game, read from wSaveSlotToLoad ($7e021f).
;
; Why that read is safe from battle context (issue #29, audited 2026-07-28).
; $021f is a menu-module variable, and Ot6CodexActive's callers all run in
; battle (ot6_break.asm:155/:884/:992), so the guarantee rests on nothing else
; ever writing the cell:
;   * it has exactly four writers, all lifecycle moments: New Game
;     (menu/menu_common.asm:250, menu/field_menu.asm:2756), validated load
;     confirm (menu/field_menu.asm:2794), and save (menu/save.asm:50, the
;     OT6 line that makes a first save leave the transient page);
;   * the world module's direct-page swap covers $0000-$00FF only
;     (world/init.asm:1446-1516 PushDP/PopDP) and its mode-7 var block is
;     $0520-$0bff (world/init.asm:1413-1440), so neither reaches $021f, and
;     the world->battle path (world/move.asm:860-940) restores DP before
;     Battle_ext without touching it;
;   * the menu's own live clock stops one byte short: wGameTimeHours..
;     Frames are $021b-$021e, ticked 8-bit (IncGameTime, menu_common.asm:3522-3546
;     under .a8), so the tick never carries into $021f.
; Measured per module (probe drives, 2026-07-28): the cell held the
; lifecycle value at every consumer read across field/world/battle/menu,
; fresh and slot-3-loaded, pre/post menu, pre/post save, including battles
; entered from the world map right after an in-menu save.  The overlaid
; values issue #29 reported (5; then 36/37 oscillation) reproduced only
; under codex_saveas's forced-ZMENUSTATE save drive, whose corrupted menu
; exit leaves menu tasks running, and in no player-reachable flow.
; tools/tests/codex_ctx.lua pins the guarantee end to end: world save into
; slot 3, menu close, encounter, and the battle's seed must surface the
; slot-3 page's knowledge, not the transient page's.
OT6_CODEX_V2     := $384f       ; 'O8': per-save elements + classes
OT6_CODEX_GLOBAL := $374f       ; 'O7': legacy cartridge-global layout

; Return the active codex page offset ($000/$400/$800/$c00) in X and ensure
; that page is initialized. Invalid values conservatively use transient.
.proc Ot6CodexActive
        php
        longi
        shorta0
        lda     f:$7e021f       ; wSaveSlotToLoad: 0=new, 1..3=saved
        cmp     #$01
        beq     @one
        cmp     #$02
        beq     @two
        cmp     #$03
        beq     @three
        ldx     #OT6_CODEX_TEMP
        bra     @ensure
@one:   ldx     #$0000
        bra     @ensure
@two:   ldx     #$0400
        bra     @ensure
@three: ldx     #$0800
@ensure:
        jsr     Ot6CodexEnsure
        plp
        rts
.endproc

; Ensure codex page X is signed 'O8'.  The one-time O7 migration clones the
; former global knowledge into all three slots: existing players lose nothing,
; while discoveries made after migration remain isolated.  A fresh page is
; zeroed independently.
.proc Ot6CodexEnsure
        php
        longi
        phx
        phy
        longa
        ; Detect the legacy global signature regardless of which save slot
        ; the player loads first.  Delaying migration until slot 1 was used
        ; could otherwise let slot 2 learn something and later overwrite it
        ; when slot 1 finally triggered the clone.
        lda     f:OT6_CODEX_MAGIC
        cmp     #OT6_CODEX_GLOBAL
        beq     @legacy
        lda     f:OT6_CODEX_MAGIC,x
        cmp     #OT6_CODEX_V2
        bne     :+
        jmp     @done
:
        bra     @fresh

@legacy:
        ; O7's two tables already occupy page 1.  Clone their contiguous
        ; $300-byte payload to pages 2/3 before replacing all three magics.
        shorta0
        ldx     #$0000
@migrate:
        lda     f:OT6_CODEX,x
        sta     f:OT6_CODEX+$0400,x
        sta     f:OT6_CODEX+$0800,x
        inx
        cpx     #$0300
        bcc     @migrate
        longa
        lda     #OT6_CODEX_V2
        sta     f:OT6_CODEX_MAGIC
        sta     f:OT6_CODEX_MAGIC+$0400
        sta     f:OT6_CODEX_MAGIC+$0800
        ; The legacy global knowledge belongs to existing saved games, not a
        ; newly started unsaved game. Initialize its transient page blank.
        shorta0
        lda     #$00
        ldx     #$0000
@wipet: sta     f:OT6_CODEX+$0c00,x
        inx
        cpx     #$0300
        bcc     @wipet
        longa
        lda     #OT6_CODEX_V2
        sta     f:OT6_CODEX_MAGIC+$0c00
        bra     @done

@fresh:
        ; Select one of three fixed loops so no scratch RAM is needed while
        ; battle initialization is live.
        shorta0
        cpx     #$0400
        beq     @fresh2
        cpx     #$0800
        beq     @fresh3
        cpx     #$0c00
        beq     @fresht
        lda     #$00
        ldx     #$0000
@wipe1: sta     f:OT6_CODEX,x
        inx
        cpx     #$0300
        bcc     @wipe1
        longa
        lda     #OT6_CODEX_V2
        sta     f:OT6_CODEX_MAGIC
        bra     @done
@fresh2:
        lda     #$00
        ldx     #$0000
@wipe2: sta     f:OT6_CODEX+$0400,x
        inx
        cpx     #$0300
        bcc     @wipe2
        longa
        lda     #OT6_CODEX_V2
        sta     f:OT6_CODEX_MAGIC+$0400
        bra     @done
@fresh3:
        lda     #$00
        ldx     #$0000
@wipe3: sta     f:OT6_CODEX+$0800,x
        inx
        cpx     #$0300
        bcc     @wipe3
        longa
        lda     #OT6_CODEX_V2
        sta     f:OT6_CODEX_MAGIC+$0800
        bra     @done
@fresht:
        lda     #$00
        ldx     #$0000
@wipet2:
        sta     f:OT6_CODEX+$0c00,x
        inx
        cpx     #$0300
        bcc     @wipet2
        longa
        lda     #OT6_CODEX_V2
        sta     f:OT6_CODEX_MAGIC+$0c00
@done:  ply
        plx
        plp
        rts
.endproc

; Begin an unsaved New Game with a freshly blank transient codex page.
.proc Ot6CodexNewGame
        php
        longi
        shorta0
        lda     #$00
        ldx     #$0000
@wipe:  sta     f:OT6_CODEX+$0c00,x
        inx
        cpx     #$0300
        bcc     @wipe
        longa
        lda     #OT6_CODEX_V2
        sta     f:OT6_CODEX_MAGIC+$0c00
        plp
        rtl
.endproc

; Initialize/migrate the selected persistent page while the load menu owns the
; machine, before gameplay can enter a battle through a caller with narrower
; register-width assumptions. A = validated slot 1..3.
.proc Ot6CodexLoaded
        php
        longi
        shorta0
        cmp     #$02
        beq     @two
        cmp     #$03
        beq     @three
        ldx     #$0000
        bra     @ensure
@two:   ldx     #$0400
        bra     @ensure
@three: ldx     #$0800
@ensure:
        jsr     Ot6CodexEnsure
        plp
        rtl
.endproc

; Copy the active game's codex when vanilla saves that game into a different
; slot.  This makes "Save As" behave like the rest of the slot-local game
; state, and carries a new game's transient knowledge into whichever slot the
; player chooses for its first save. A = destination slot (1..3).
.macro Ot6CopyCodexPage src, dst
        .local  copy
        shorta0
        ldx     #$0000
copy:   lda     f:OT6_CODEX+(src),x
        sta     f:OT6_CODEX+(dst),x
        inx
        cpx     #$0300
        bcc     copy
        longa
        lda     #OT6_CODEX_V2
        sta     f:OT6_CODEX_MAGIC+(dst)
        shorta0
.endmacro

.proc Ot6CodexSaveAs
        php
        phb
        longi
        phx
        phy
        shorta
        pha                     ; preserve destination for vanilla's stores
        jsr     Ot6CodexActive  ; ensure source; X = source page
        lda     $01,s           ; destination slot
        cpx     #OT6_CODEX_TEMP
        bne     :+
        cmp     #$01
        beq     temp_to_one
        cmp     #$02
        beq     temp_to_two
        Ot6CopyCodexPage $0c00, $0800
        jmp     done
temp_to_one:
        Ot6CopyCodexPage $0c00, $0000
        jmp     done
temp_to_two:
        Ot6CopyCodexPage $0c00, $0400
        jmp     done
:
        cmp     #$02
        beq     dest2
        cmp     #$03
        bne     :+
        jmp     dest3
:
        ; destination 1
        cpx     #$0000
        bne     :+
        jmp     done
:
        cpx     #$0400
        beq     two_to_one
        Ot6CopyCodexPage $0800, $0000
        jmp     done
two_to_one:
        Ot6CopyCodexPage $0400, $0000
        jmp     done
dest2:
        cpx     #$0400
        bne     :+
        jmp     done
:
        cpx     #$0800
        beq     three_to_two
        Ot6CopyCodexPage $0000, $0400
        jmp     done
three_to_two:
        Ot6CopyCodexPage $0800, $0400
        jmp     done
dest3:
        cpx     #$0800
        bne     :+
        jmp     done
:
        cpx     #$0400
        beq     two_to_three
        Ot6CopyCodexPage $0000, $0800
        jmp     done
two_to_three:
        Ot6CopyCodexPage $0400, $0800
done:   pla
        ply
        plx
        plb
        plp
        rtl
.endproc

; [ seed monster shields at battle init ]

; called from LoadRageProp just after the weak-elements load
; a8/i16, x = monster prop offset, y = entity offset, preserves x/y
