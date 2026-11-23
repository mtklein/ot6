; Per-save weakness codex.  Each save owns a $400-byte page in SRAM bank
; $31; only $310 bytes are currently used (magic + two 384-species tables:
; revealed weak elements, then revealed weapon classes, six since v0.51).
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
OT6_CODEX_V3     := $394f       ; 'O9': per-save elements + six classes (#566)
OT6_CODEX_V2     := $384f       ; 'O8': per-save elements + four classes
                                ;   (v0.5-v0.50): read and migrated, never
                                ;   written
OT6_CODEX_GLOBAL := $374f       ; 'O7': legacy cartridge-global layout
OT6_CODEX_FOUR   = $0f          ; the class bits an O7 or O8 page can hold:
                                ;   slash, pierce, bludgeon, special
OT6_CODEX_SPECIES = 384         ; species a table holds, one byte each

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

; Ensure codex page X is signed 'O9'.  The one-time O7 migration clones the
; former global knowledge into all three slots: existing players lose nothing,
; while discoveries made after migration remain isolated.  A four-class page
; (O8, or an O7 clone) has its class bytes rewritten for the six classes
; once (Ot6CodexSix), and takes the new magic.  A fresh page is zeroed
; independently.
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
        beq     Legacy
        lda     f:OT6_CODEX_MAGIC,x
        cmp     #OT6_CODEX_V3
        bne     :+
        jmp     Done
:       cmp     #OT6_CODEX_V2
        bne     Fresh
        jsr     Ot6CodexSix     ; #566: a four-class page, on its first touch
        jmp     Done

Legacy:
        ; O7's two tables already occupy page 1.  Clone their contiguous
        ; $300-byte payload to pages 2/3 before replacing all three magics.
        shorta0
        ldx     #$0000
Migrate:
        lda     f:OT6_CODEX,x
        sta     f:OT6_CODEX+$0400,x
        sta     f:OT6_CODEX+$0800,x
        inx
        cpx     #$0300
        bcc     Migrate
        ; #566: O7's classes are the four, so each clone becomes a six-class
        ; page and takes its magic.  Page 1 goes last: its O7 magic is what
        ; starts this over, from a payload still whole, if the console loses
        ; power before all three are done.
        ldx     #$0400
        jsr     Ot6CodexSix
        ldx     #$0800
        jsr     Ot6CodexSix
        ldx     #$0000
        jsr     Ot6CodexSix
        ; The legacy global knowledge belongs to existing saved games, not a
        ; newly started unsaved game. Initialize its transient page blank.
        shorta0
        lda     #$00
        ldx     #$0000
WipeNew: sta     f:OT6_CODEX+$0c00,x
        inx
        cpx     #$0300
        bcc     WipeNew
        longa
        lda     #OT6_CODEX_V3
        sta     f:OT6_CODEX_MAGIC+$0c00
        bra     Done

Fresh:
        ; An unsigned page: zero both tables, then sign it.  One loop for
        ; whichever page, long through X, so no scratch RAM is needed while
        ; battle initialization is live.  (Through v0.50 this was a fixed
        ; loop a page, and the three after the first were assembled with
        ; the 16-bit accumulator of the lines above them while the CPU
        ; arrived 8-bit: an unsigned page for slot 2, slot 3 or an unsaved
        ; game ran `lda #$00` into a BRK.  No OT6 save leaves such a page.)
        shorta0
        lda     #$00
        ldy     #$0300
FreshWipe:                      ; (mutant_rom.py's seam: the wipe's store)
        sta     f:OT6_CODEX,x
        inx
        dey
        bne     FreshWipe
        longa
        lda     3,s             ; the page offset (under the phy)
        tax
        lda     #OT6_CODEX_V3
        sta     f:OT6_CODEX_MAGIC,x
Done:  ply
        plx
        plp
        rts
.endproc

; [ a four-class codex page becomes a six-class one ] (#566)
;
; v0.51 regrouped the four weapon classes into six.  A page written by
; v0.50 or earlier (magic O8, or an O7 clone) holds, per species, the
; revealed bits of the four: slash $01, pierce $02, bludgeon $04, special
; $08.  Each of a species' four-class weaknesses became one six-class
; weakness (all six, for the two rows any weapon breaks), and
; Ot6ClassSplitTbl records which: four bytes a species, byte k the six-class
; bits its weakness of four-class bit k became (ot6_class_split.inc).  So
; each class byte becomes the OR of the table's bytes for the four-class
; bits set in it, and every other bit is dropped.  The element table is
; untouched.  The page then takes the six-class magic, so this runs once a
; page: run again it would not give the same bytes (a Katana bit read as
; four-class is dropped), and the magic is the only record that it has been
; done.  The magic is written last, and only its high byte differs from
; O8's, so the signing is one byte's write.  A console that loses power
; inside the 384-byte rewrite keeps O8 over a part-rewritten table, and the
; next touch rewrites all of it: a reveal already moved to a bit the four
; did not have can be lost and has to be found again.  Nothing false is
; drawn either way (below).
;
; A revealed bit the species' six-class row does not answer to (a row that
; changed since the save was written) is kept here and never drawn:
; Ot6SeedShields masks the byte with the body's row.
;
; No scratch RAM (battle initialization may be live, as in Ot6CodexEnsure)
; and no data-bank change: the page is read and written long through X, and
; X is lent to the table reads.  X (i16) = the page offset.  x/y and widths
; preserved; A clobbered.
.proc Ot6CodexSix
        php
        longi
        phx
        phy
        shorta
        ldy     #$0000          ; y = the species' row in the split table
                                ;   (species * 4); x = page offset + species
SixNext: lda    f:OT6_CODEX_CLASS,x
SixFour:                        ; (mutant_rom.py's seam: the four bits kept)
        and     #OT6_CODEX_FOUR
        phx                     ; [1,s] x
        pha                     ; [1,s] the four-class bits still to place
        lda     #$00
        pha                     ; [1,s] the six-class byte so far, the bits
                                ;   [2,s], x [3,s]
        tyx                     ; x walks the species' four table bytes
SixBit: lda     2,s
        beq     SixPut          ; none left to place
        lsr
        sta     2,s
        bcc     SixSkip         ; this four-class bit was not revealed
SixRead:                        ; (mutant_rom.py's seam: the table read)
        lda     f:Ot6ClassSplitTbl,x
        ora     1,s
        sta     1,s
SixSkip: inx
        bra     SixBit
SixPut: pla                     ; the six-class byte ...
        sta     1,s             ;   ... over the spent bits,
        pla                     ;   and off the stack with them
        plx
        sta     f:OT6_CODEX_CLASS,x
        inx
        iny
        iny
        iny
        iny
        cpy     #OT6_CODEX_SPECIES * 4
        bcc     SixNext
SixTail:                        ; (mutant_rom.py's seam jumps here from
        ply                     ;   SixNext: signed, nothing rewritten)
        plx
        longa
SixSign:                        ; (mutant_rom.py's seam: the page's new magic)
        lda     #OT6_CODEX_V3
        sta     f:OT6_CODEX_MAGIC,x
        plp
        rts
.endproc

        .include "ot6_class_split.inc"  ; Ot6ClassSplitTbl
.assert * - Ot6ClassSplitTbl = OT6_CODEX_SPECIES * 4, error, "Ot6ClassSplitTbl is four bytes a codex species"

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
        lda     #OT6_CODEX_V3
        sta     f:OT6_CODEX_MAGIC+$0c00
        jsr     Ot6EsperNewGame ; #328: and no esper progress
        jsr     Ot6NewGameClear ; #389: and no power-on junk in the scrap
        plp
        rtl
.endproc

; New Game, and power-on (Ot6PowerOnClear): zero the save block's OT6
; scrap ($1e1d-$1e3f: the three loadouts, the signature and the reserve),
; vanilla's unused tail ($1ff7-$1ffd), and the vanilla save-block ranges
; that New Game leaves unwritten (Ot6NewGameZero).  Vanilla clears WRAM
; only to $11ff (ClearRAM) and its New Game names none of these bytes, so
; on a console or emulator whose RAM powers on non-zero they held junk:
; all-$FF loadouts read as a manual Rage and Lore loadout whose every slot
; names an unknown entry, and Gau and Strago came up with empty lists.
; Zero is AUTO and unsigned, and the value vanilla assumes elsewhere.
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

; At power-on, before the field's first init: the reset path runs InitNewGame
; and loads the starting map, which reads the objects' saved positions
; ($1fd3-$1ff2, obj.asm:3437) before a New Game or a Continue writes them,
; and a Continue does not reload the objects from the block, so the junk
; stayed on the off-screen characters (gen_wob_airship_hunt under the
; all-ones fill: "party 1 ... at map 3 (255,255)").  The same zeroing as a
; New Game's; a Continue then loads the slot over all of it.
.proc Ot6PowerOnClear
        php
        jsr     Ot6NewGameClear
        plp
        rtl
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
        .byte   24      ; the timers' saved copy (PushTimers at a save,
                        ;   PopTimers at a load and on leaving the field
                        ;   menu, menu/save.asm): zero is no timer running
        .word   $1fc2
        .byte   16      ; event variables 0-7 (EventCmd_e8-eb; add_var 0 runs
                        ;   on what is there)
        .word   $1fd3
        .byte   32      ; the 16 objects' saved positions (PushPartyMap,
                        ;   read back at field init, obj.asm:3437).  The
                        ;   reader is the reset path's first field init,
                        ;   which Ot6PowerOnClear covers; at New Game they
                        ;   are already zero, so this entry is redundant
                        ;   there and kept so both callers share one list
        .word   $0000
        .byte   0

; [ sign the save block, and keep the reserve zero ] (#389)
;
; Called by Ot6CodexSaveAs at the head of CopyGameDataToSRAM, before the
; checksum and the copy, so the signature rides in the slot and is summed.
; An unsigned block (a save from before this build, or a New Game's first
; save) has the rest of the scrap ($1e2f-$1e3f) and the block's unused
; tail ($1ff7-$1ffd) zeroed, then takes the signature and version; a
; signed block keeps its signature, and a lower version is raised to
; today's (#552: version 2's esper row 12 is written by Ot6EsperSaveAs just
; before).  Every save also zeroes the destination
; slot's codex and esper page reserves (each page's +$002-$00f, the codex
; page past +$310 and the esper page past +$2b4): no build writes them, and
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
        cmp     #OT6_SAVEVER_CUR
        bcs     Pages           ; signed with today's version: as it is
        ; A lower signed version (1, v0.45-v0.50): its one new field, the
        ; esper page's row 12 (#552 piece F), is set up already: the live
        ; page's row 12 was cleared by the load (Ot6EsperLeoRow) and has
        ; only what this game earned since, and Ot6EsperSaveAs has just
        ; copied it into the slot.  Nothing else in the block changed
        ; meaning, so the block now claims today's version.
Raise:  lda     #OT6_SAVEVER_CUR        ; (mutant_rom.py's seam: 6 bytes)
        sta     f:OT6_SAVEVER
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
LoadEnsure:                     ; (mutant_rom.py's seam: a load's ensure)
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
        lda     #OT6_CODEX_V3
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
