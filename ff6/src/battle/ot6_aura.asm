; ------------------------------------------------------------------------------
; [ boost aura: a character holding a pending boost glows (#445) ]
;
; While a character has a boost pending ($3e9d,x 1-3: raised with R in their
; menu, held through target select, the queue and the action itself, and
; cleared by Ot6ActionEnd's charge), they wear an aura of two parts:
;   * the glow (Ot6Aura): the sprite's outline colour (colour 1, which FF6's
;     battle sprites use for the silhouette's edge and their inner lines)
;     pulses through Ot6AuraOutline's row for the level, and at 2-3 BP the
;     body brightens a little on the pulse;
;   * the halo (Ot6AuraHalo): copies of the character's own body sprites, a
;     pixel out, drawn behind them, so the glowing edge thickens outward.
; The level sets both:
;   1 BP  dark -> amber outline, copies left/right, a slow pulse (32 frames)
;   2 BP  amber -> gold, all four sides, twice as fast
;   3 BP  orange <-> bright gold flicker (8 frames), four sides and above
;
; Built from what the character already has on screen: the battle's sprite
; palettes are all spoken for (objpal 0-2 monsters, 3 the animation/flash
; scratch, 4-7 the four characters) and so is the sprite VRAM (characters
; $2000, animations $2400-$2dff, numerals/status $2e00, monsters $3000), so
; the glow edits the character's own palette (the frame's sprite-palette DMA
; carries it) and the halo reuses the character's own tiles.  Both follow the
; character through every pose, list and animation.
;
; Where it runs: inside the battle NMI (BattleNMI does the frame's sprite and
; palette work), which calls UpdateCharPal -- it refreshes ONE character's
; palette per frame (slot = (frame+1) & 3) from the unaltered copy at w7e81ad
; and applies vanilla's status colours -- and then the per-frame ot6 hook at
; @0cdd (Ot6FramePost_ext, its jsl target repointed: no C1 size change).  The
; glow edits the palette UpdateCharPal just refreshed, on top of whatever
; status colouring it applied, so each character's glow steps at 15 Hz, as
; vanilla's own status glows do (UpdateStatusOutlineColor), and the colours
; return to normal within 4 frames of the boost clearing, by UpdateCharPal's
; own refresh.  While an animation owns the character palettes (w7e62bf
; nonzero, the same test that skips UpdateCharPal) the glow leaves them alone
; too.
;
; Cost, in CPU cycles of the NMI (measured, build/attempts/wt/v032-boost-aura/):
; with no boost pending anywhere, four loads and a branch (the hook's whole
; run is at most 22 cycles); at 3 BP, ~260 for the glow (averaged over its one
; frame in four) and ~1500 for the halo, against an NMI of ~21000.
; ------------------------------------------------------------------------------

; Ot6RestageGate_ext's caller in C1 now lands here first.
.proc Ot6FramePost_ext
        .a8
        .i16
        lda     $3e9d                   ; any character's pending boost?
        ora     $3e9f
        ora     $3ea1
        ora     $3ea3
        beq     :+
        jsr     Ot6Aura
        jsr     Ot6AuraHalo
:       jmp     Ot6RestageGate_ext      ; rtl's back to the C1 frame loop
.endproc

.proc Ot6Aura
        .a8
        .i16
        lda     $62bf                   ; an animation owns the palettes
        beq     :+
        rts
:       phx
        phy
        lda     $98                     ; UpdateCharPal's slot this frame
        inc     a
        and     #$03
        longa
        and     #$00ff
        asl     a
        tax                             ; entity offset (slot * 2)
        asl     a
        asl     a
        asl     a
        asl     a
        tay                             ; palette offset (slot * 32)
        shorta0
        lda     $3e9d,x                 ; this character's pending boost
        bne     :+
        jmp     @pop
:       cmp     #$04
        bcc     :+
        lda     #$03                    ; (defensive: pending is 0-3)
:       dec     a
        sta     $36                     ; level - 1 (0..2)
        ; pulse phase: (refresh count << level-1) & 7, so 2 BP runs twice as
        ; fast as 1 and 3 BP four times (on/off).  The refresh count is
        ; frame / 4: this slot is refreshed once every four frames.
        lda     $98
        lsr     a
        lsr     a
        sta     $37
        lda     $36
        beq     @ph
:       asl     $37
        dec     a
        bne     :-
@ph:    lda     $37
        and     #$07
        tax
        lda     f:Ot6AuraTri,x          ; intensity 0-4
        sta     $37
        lda     $36                     ; table row = level * 5 + intensity
        asl     a
        asl     a
        clc
        adc     $36
        clc
        adc     $37
        tax                             ; 0..14
        lda     f:Ot6AuraAdd,x          ; body brightening, per channel
        longa
        and     #$00ff
        sta     $38                     ; red add
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        sta     $3a                     ; green add (<< 5)
        lda     $38
        lsr     a                       ; blue gets half: a warm (gold) glow
        xba
        asl     a
        asl     a                       ; << 10
        sta     $3c
        txa
        asl     a
        tax
        lda     f:Ot6AuraOutline,x      ; the outline colour
        sta     a:$7f82,y               ; w7e7e00::_12::Color1, this slot
        lda     $38
        beq     @body                   ; no brightening at this step
        ldx     #$000a                  ; colours 2-11: the body
@col:   lda     a:$7f84,y               ; w7e7e00::_12::Color2 + 2n
        and     #$001f
        clc
        adc     $38
        cmp     #$0020
        bcc     :+
        lda     #$001f
:       sta     $3e
        lda     a:$7f84,y
        and     #$03e0
        clc
        adc     $3a
        cmp     #$0400
        bcc     :+
        lda     #$03e0
:       ora     $3e
        sta     $3e
        lda     a:$7f84,y
        and     #$7c00
        clc
        adc     $3c
        cmp     #$8000
        bcc     :+
        lda     #$7c00
:       ora     $3e
        sta     a:$7f84,y
        iny
        iny
        dex
        bne     @col
@body:  shorta0
@pop:   ply
        plx
        rts
.endproc

;------------------------------------------------------------------------------
; [ boost aura: the halo ]
;
; The glow above recolours the sprite's outline colour (colour 1, which FF6's
; battle sprites use for the silhouette's edge and their inner lines).  The
; halo thickens that edge outward: for each boosting character it draws extra
; copies of the character's own two sprites, offset by a pixel, BEHIND the
; character (higher OAM index = lower priority among equal-priority sprites),
; so what shows of them is a ring of the copies' edge pixels -- colour 1, the
; glowing outline -- just outside the character's own.  More boost, more
; copies: 1 BP left/right, 2 BP all four sides, 3 BP all four plus three above
; (the glow rises off the head).
;
; Copies, not new graphics: the sprite VRAM is spoken for (characters $2000,
; animations $2400-$2dff, numerals/status $2e00, monsters $3000) and so is
; every sprite palette, while the character's own tiles and palette are
; already there.
;
; This hook runs after UpdateSprites has built the frame's OAM buffer ($0300,
; next free entry in $71; ClearSpriteData resets entries 8-114 each frame),
; so the character's entries are found by what DrawCharSprite wrote: the
; slot's own tiles (slot * 4 + 0/2, first name table) in the slot's palette
; (4 + slot).  The copies are appended at $71 and stop short of entry 112,
; whose high-table byte ClearSpriteData does not clear.  A character drawn
; at the floor DrawCharSprite clamps to (y = $97: parked) gets no copies.
;
; One pass over the frame's entries serves every boosting character: a
; body tile ($00-$0f) names its slot (tile / 4), which names the palette
; (4 + slot) and the pending boost to check.
;
; a8/i16, db=$7e.  Clobbers a and $36-$3f; preserves x/y.

.proc Ot6AuraHalo
        .a8
        .i16
        phx
        phy
        longa
        lda     $71                     ; the frame's own entries end here;
        and     #$00ff                  ;   copies appended below are not
        asl     a                       ;   scanned
        asl     a
        pha
        stz     $3c                     ; body entries left to find: two per
        ldx     #$0006                  ;   boosting character, after which
@count: lda     $3e9d,x                 ;   the scan stops (DrawCharSprite
        and     #$00ff                  ;   draws them early, entries ~10-20)
        beq     :+
        inc     $3c
        inc     $3c
:       dex
        dex
        bpl     @count
        ldy     #$0020                  ; entry 8, the first per-frame one
@scan:  tya
        cmp     $01,s
        bcs     @end
        lda     $3c
        beq     @end
        lda     $0302,y                 ; tile | attr << 8
        bit     #$00f0                  ; character body tiles are $00-$0f
        bne     @skip
        and     #$000c
        lsr     a
        tax                             ; slot * 2: the entity offset
        ora     #$0008                  ; palette 4 + slot, name table 0
        sta     $3e
        lda     $0303,y
        and     #$000f
        cmp     $3e
        bne     @skip
        lda     $3e9d,x                 ; pending boost
        and     #$00ff
        beq     @skip
        dec     $3c                     ; one of the body entries sought
        cmp     #$0004
        bcc     :+
        lda     #$0003
:       tax
        lda     f:Ot6HaloCount-1,x      ; copies per sprite at this level
        and     #$00ff
        asl     a
        sta     $36                     ; ... * 2: Ot6HaloOffsets' stride
        lda     $0301,y
        and     #$00ff
        cmp     #$0097                  ; parked at the floor: no halo
        bcs     @skip
        jsr     Ot6HaloCopies
@skip:  iny
        iny
        iny
        iny
        bra     @scan
@end:   pla
        shorta0
        ply
        plx
        rts
.endproc

; append copies of the OAM entry at y (entry * 4) at Ot6HaloDelta's first
; $36 / 2 offsets, at $71 onward, stopping short of entry 112.
;
; Characters are small (16x16) sprites well inside the screen, so the high
; table (x bit 8, size) is all zeroes for them and for their copies, and
; ClearSpriteData leaves it that way for entries 4-111: the copies need no
; high-table writes.  An entry that is large, has x bit 8 set or sits within
; three pixels of either edge (where a pixel's shift could wrap x) gets no
; copies rather than a slower path.  With x in 3..252 and y below $97, a
; copy's position is one 16-bit add of (dy << 8) + dx to (y << 8) | x.
;
; a16/i16, db=$7e.  preserves y; clobbers a, x, $38-$3b.
.proc Ot6HaloCopies
        .a16
        .i16
        phy
        tya
        lsr     a
        lsr     a
        pha                             ; entry index
        lsr     a
        lsr     a
        tax
        pla
        and     #$0003
        phx
        tax
        lda     f:Ot6HiX,x              ; the entry's two high-table bits
        and     #$00ff
        sta     $38
        asl     a
        tsb     $38
        plx
        lda     $0500,x
        and     $38
        bne     @done                   ; large or x >= 256: no halo
        lda     $0300,y                 ; (y << 8) | x
        sta     $38
        and     #$00ff
        cmp     #$0003
        bcc     @done                   ; at an edge: no halo
        cmp     #$00fd
        bcs     @done
        lda     $0302,y
        sta     $3a                     ; tile | attr: copied as they are
        lda     $71
        and     #$00ff
        asl     a
        asl     a
        tay                             ; the first destination * 4
        ldx     #$0000                  ; offset index * 2
@copy:  cpx     $36
        bcs     @end                    ; this level's copies all placed
        cpy     #$01c0
        bcs     @end                    ; entries 112+ are not ours to fill
        lda     $38
        clc
        adc     f:Ot6HaloDelta,x
        sta     $0300,y                 ; x, y
        lda     $3a
        sta     $0302,y                 ; tile, attr
        iny
        iny
        iny
        iny
        inx
        inx
        bra     @copy
@end:   tya
        lsr     a
        lsr     a
        shorta
        sta     $71                     ; the next free entry
        longa
@done:  ply
        rts
.endproc

; copies per sprite at 1/2/3 BP
Ot6HaloCount:
        .byte   2, 4, 7

; x-bit-8 mask for an entry's position within its high-table byte
Ot6HiX:
        .byte   $01, $04, $10, $40

; halo offsets as 16-bit (dy << 8) + dx deltas to (y << 8) | x: the first
; n are used at a level
Ot6HaloDelta:
        .word   $ffff, $0001            ; left, right
        .word   $ff00, $0100            ; up, down
        .word   $feff, $ff01            ; up-left, up-right
        .word   $fe00                   ; two up

; intensity over the 8-step pulse: a triangle
Ot6AuraTri:
        .byte   0, 1, 2, 3, 4, 3, 2, 1

; body brightening (added to red and green, half to blue), by level and
; intensity 0-4
Ot6AuraAdd:
        .byte   0, 0, 0, 0, 0           ; 1 BP
        .byte   0, 0, 0, 1, 1           ; 2 BP
        .byte   0, 1, 1, 2, 3           ; 3 BP

; outline colour (BGR555), by level and intensity 0-4; (r,g,b) in comments
Ot6AuraOutline:
        .word   $0c63, $04c9, $0550, $01d6, $025c ; 1 BP 3,3,3 9,6,1 16,10,1 22,14,0 28,18,0
        .word   $0194, $05f7, $0a7a, $0efd, $135f ; 2 BP 20,12,0 23,15,1 26,19,2 29,23,3 31,26,4
        .word   $029f, $0eff, $173f, $239f, $2bdf ; 3 BP 31,20,0 31,23,3 31,25,5 31,28,8 31,30,10
