; Per-save weakness codex.  Each save owns a $400-byte page in SRAM bank
; $31; only $310 bytes are currently used (magic + two 384-species tables).
; A fourth page is transient knowledge for an unsaved New Game, so it never
; inherits slot 1. The active page is 0 for transient or 1..3 for a saved
; game, read from wSaveSlotToLoad ($7e021f).
;
; That read is safe from battle context: $021f is a menu-module variable, and
; Ot6CodexActive's callers all run in battle (ot6_break.asm:155/:884/:992), so
; the guarantee rests on nothing else ever writing the cell:
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
        jsr     Ot6EsperNewGame ; #328: and no esper progress
        jsr     Ot6NewGameClear ; #389: and no power-on junk in the scrap
        plp
        rtl
.endproc

; New Game: zero the save block's OT6 scrap ($1e1d-$1e3f: the three
; loadouts, the signature and the reserve) and vanilla's unused tail
; ($1ff7-$1ffd).  Vanilla clears WRAM only to $11ff (ClearRAM) and its New
; Game names none of these bytes, so on a console or emulator whose RAM
; powers on non-zero they held junk: all-$FF loadouts read as a manual Rage
; and Lore loadout whose every slot names an unknown entry, and Gau and
; Strago came up with empty lists.  Zero is AUTO and unsigned.
; a/x widths saved.
.proc Ot6NewGameClear
        php
        longi
        shorta
        phx
        lda     #$00
        ldx     #$0000
@scrap: sta     f:OT6_LOADOUT,x
        inx
        cpx     #OT6_SCRAP_LEN
        bcc     @scrap
        ldx     #$0000
@tail:  sta     f:OT6_SAVETAIL,x
        inx
        cpx     #OT6_SAVETAIL_LEN
        bcc     @tail
        ; vanilla's own never-written save-block bytes (the power-on fill,
        ; tools/uninit_waivers.txt): every range below is read before New
        ; Game or its opening event writes it, or carried into every save
        ; unwritten, and zero is the value vanilla assumes (a console that
        ; powers on blank).  Ot6NewGameZero lists them.
        phy
        ldy     #$0000
@rng:   tyx
        lda     f:Ot6NewGameZero+2,x    ; length (bytes, < 256)
        beq     @rdone
        pha
        longa
        lda     f:Ot6NewGameZero,x      ; start, WRAM bank $7e
        tax
        shorta
        pla
@byte:  pha
        lda     #$00
        sta     f:$7e0000,x
        pla
        inx
        dec     a
        bne     @byte
        iny
        iny
        iny
        bra     @rng
@rdone: ply
        plx
        plp
        rts
.endproc

; (start, length) per range, a length of 0 ends the list
Ot6NewGameZero:
        .word   $1e70
        .byte   16      ; unused tail after the treasure bits ($1e40-$1e6f)
        .word   $1f60
        .byte   4       ; world position and airship position: an event sets
                        ;   each before the world map reads it
        .word   $1f6e
        .byte   2       ; the random-battle counter (field/battle.asm adds
                        ;   each step; vanilla clears it only after a battle)
        .word   $1fa8
        .byte   24      ; unused by any code
        .word   $1fc2
        .byte   16      ; event variables 0-7 (EventCmd_e8-eb; add_var 0 runs
                        ;   on what is there)
        .word   $1fd3
        .byte   32      ; the 16 objects' saved positions (PushPartyMap,
                        ;   read back at field init, obj.asm:3437)
        .word   $0000
        .byte   0

; [ sign the save block, and keep the reserve zero ] (#389)
;
; Called by Ot6CodexSaveAs at the head of CopyGameDataToSRAM, before the
; checksum and the copy, so the signature rides in the slot and is summed.
; An unsigned block (a save from before this build, or a New Game's first
; save) has the rest of the scrap ($1e2f-$1e3f) and the block's unused
; tail ($1ff7-$1ffd) zeroed, then takes the signature and version; a
; signed block is left as it is.  Every save also zeroes the destination
; slot's codex and esper page reserves (each page's +$002-$00f, the codex
; page past +$310 and the esper page past +$280): no build writes them, and
; bank $31 is never cleared, so a battery can hold junk there.  So a slot a
; signing build wrote holds zero in every reserve it owns.
; A (a8) = destination slot 1..3.  a/x/y widths saved; A preserved; Y
; clobbered.
.proc Ot6SaveSign
        php
        longai
        pha
        phx
        phy
        ; signed = the signature AND a version this build knows (1..CUR): a
        ; block whose signature is junk-matched or whose version byte is 0
        ; or past ours is treated as unsigned and signed afresh.  A release
        ; that raises OT6_SAVEVER_CUR handles a lower signed version here:
        ; it sets up its new field first, then raises the byte.
        lda     f:OT6_SAVESIG
        cmp     #OT6_SAVESIG_WORD
        bne     Sign
        shorta
        lda     f:OT6_SAVEVER
VerCheck:                       ; (mutant_rom.py's seam for the version test)
        beq     Sign
        cmp     #OT6_SAVEVER_CUR+1
        bcs     Sign
        bra     Pages
Sign:   shorta
        lda     #$00
        ldx     #$0000
@rsv:   sta     f:OT6_SAVERSV,x
        inx
        cpx     #OT6_SAVERSV_LEN
        bcc     @rsv
        ldx     #$0000
@tail:  sta     f:OT6_SAVETAIL,x
        inx
        cpx     #OT6_SAVETAIL_LEN
        bcc     @tail
        lda     #OT6_SAVEVER_CUR
        sta     f:OT6_SAVEVER
        longa
        lda     #OT6_SAVESIG_WORD
        sta     f:OT6_SAVESIG
Pages: longa
SlotAt: lda     5,s             ; the destination slot (under the phx/phy)
        nop                     ; (mutant_rom.py's seam: a 3-byte read here)
        and     #$0003
        beq     @done           ; not a slot: no pages
        dec
        xba
        asl
        asl                     ; (slot - 1) * $400
        pha                     ; [1,s] the page offset
        tax
        lda     #$0000
        ldy     #(OT6_CODEX - OT6_CODEX_MAGIC - 2) / 2
@cpad:  sta     f:OT6_CODEX_MAGIC+2,x
        inx
        inx
        dey
        bne     @cpad
        lda     1,s
        tax
        lda     #$0000
        ldy     #(OT6_CODEX_STRIDE - OT6_CODEX_USED) / 2
@ctail: sta     f:OT6_CODEX_ROOT+OT6_CODEX_USED,x
        inx
        inx
        dey
        bne     @ctail
        lda     1,s
        tax
        lda     #$0000
        ldy     #(OT6_ESPER_CTR - OT6_ESPER_MAGIC - 2) / 2
@epad:  sta     f:OT6_ESPER_ROOT+OT6_ESPER_MAGIC+2,x
        inx
        inx
        dey
        bne     @epad
        lda     1,s
        tax
        lda     #$0000
        ldy     #(OT6_ESPER_STRIDE - OT6_ESPER_COPY) / 2
@etail: sta     f:OT6_ESPER_ROOT+OT6_ESPER_COPY,x
        inx
        inx
        dey
        bne     @etail
        pla                     ; drop the page offset
@done:  ply
        plx
        pla
        plp
        rts
.endproc

; Initialize/migrate the selected persistent page while the load menu owns the
; machine, before gameplay can enter a battle through a caller with narrower
; register-width assumptions. A = validated slot 1..3.
.proc Ot6CodexLoaded
        php
        longi
        shorta                  ; NOT shorta0: A is the slot.  Until #328's
                                ;   review this cleared it, so every reload
                                ;   after a game over ensured slot 1's codex
                                ;   page and wiped the live esper page
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
        jsr     Ot6EsperLoaded  ; #328: the slot's esper progress goes live
                                ;   (A = the slot; Ot6CodexEnsure clobbers A)
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
        jsr     Ot6EsperSaveAs  ; #328: live esper progress into the slot
        jsr     Ot6SaveSign     ; #389: the block signed, the slot's reserves zero
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
