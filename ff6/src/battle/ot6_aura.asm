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
;     One character has it at a time (the menu's, else the highest boost),
;     within the scanline sprite budget (see the halo's block comment).
; The level sets both:
;   1 BP  dark -> amber outline, copies left/right, a slow pulse (32 frames)
;   2 BP  amber -> gold, all four sides, twice as fast
;   3 BP  orange <-> bright gold flicker (8 frames), four sides and rising
;         off the head
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
; Cost, in CPU cycles of the NMI (measured, build/attempts/wt/v032-boost-aura/
; and v032-boost-aura-2/): with no boost pending anywhere, four loads and a
; branch (the aura's part of the hook is at most 22 cycles); with any, ~420
; for the glow per boosting character (averaged over its one frame in four)
; and ~4,500 for the halo, against an NMI of ~21,000-24,500 in a ~45,200-cycle
; frame.  The scratch bracket below adds about 150 more on every unpaused
; NMI, boost or not: 79 for Ot6NmiScratchSave with its jsr and 71 for
; Ot6NmiScratchRestore_ext before its jml (counted from the opcode cycle
; table, not measured).
; ------------------------------------------------------------------------------

; Ot6RestageGate_ext's caller in C1 now lands here first.
.proc Ot6FramePost_ext
        .a8
        .i16
        jsr     Ot6NmiScratchSave
        lda     $3e9d                   ; any character's pending boost?
        ora     $3e9f
        ora     $3ea1
        ora     $3ea3
        beq     :+
        jsr     Ot6Aura
        jsr     Ot6AuraHalo
:       jmp     Ot6RestageGate_ext      ; rtl's back to the C1 frame loop
.endproc

; ------------------------------------------------------------------------------
; [ the battle NMI leaves the main thread's scratch as it found it ]
;
; OT6's battle scratch ($3ecc-$3ed3: OT6_SCR_SLOT2, OT6_SCR_BIT, OT6_SCR_IDX,
; OT6_SCR_COLS and the glyph byte after them) is written by code on both
; sides of the battle NMI.  On the main thread: the HUD's per-monster walkers
; (Ot6BgHudLine, from WaitFrame), the pip and wallet stages, and the battle
; program's break, boost and damage math.  Inside the NMI: the menu-text and
; menu-state work that draws the battle lists (_c15a5c, UpdateMenuState ->
; ListTextCmd_0f -> Ot6PreviewList_ext -> Ot6FoldSteps, the list icons) and
; the boost re-fold (Ot6RestageGate_ext).  An NMI that lands inside a main-
; thread walker therefore changed its counter under it.  The HUD's class
; walk (Ot6BgHudLine @cbit) shifts OT6_SCR_BIT left until it reaches $10;
; when the NMI's Ot6FoldSteps stored a 0 there mid-walk, the walk never
; ended, the main thread spun in it for good and the battle froze with the
; animation on screen (build/attempts/wt/v038-mirror-freeze/: the Cultists'
; Tower freeze, a magic list opened while a four-mirror Bolt bounce had
; the frame's work running late into the vblank).
;
; The NMI's OT6 work is bracketed instead of each writer: Ot6FramePost_ext,
; the first OT6 call on the NMI's unpaused path, saves the eight bytes, and
; the jsl to IncGameTime_ext at the end of that path (repointed here, same
; size) puts them back.  Every NMI list draw sits between the two, on one
; straight-line path (BattleNMI @0cdd-@0cfd); the paused path skips both.
; ------------------------------------------------------------------------------

; jsr from Ot6FramePost_ext.  Preserves every register and flag.
.proc Ot6NmiScratchSave
        php
        rep     #$20
        .a16
        pha
        lda     f:$7e0000+OT6_SCR_SLOT2
        sta     f:$7e0000+OT6_NMISCR
        lda     f:$7e0000+OT6_SCR_BIT
        sta     f:$7e0000+OT6_NMISCR+2
        lda     f:$7e0000+OT6_SCR_IDX
        sta     f:$7e0000+OT6_NMISCR+4
        lda     f:$7e0000+OT6_SCR_COLS
        sta     f:$7e0000+OT6_NMISCR+6
        pla
        plp
        rts
.endproc

; jsl from BattleNMI in place of `jsl IncGameTime_ext`.  Preserves every
; register and flag, then runs the call it replaced.
.proc Ot6NmiScratchRestore_ext
        php
        rep     #$20
        .a16
        pha
        lda     f:$7e0000+OT6_NMISCR
        sta     f:$7e0000+OT6_SCR_SLOT2
        lda     f:$7e0000+OT6_NMISCR+2
        sta     f:$7e0000+OT6_SCR_BIT
        lda     f:$7e0000+OT6_NMISCR+4
        sta     f:$7e0000+OT6_SCR_IDX
        lda     f:$7e0000+OT6_NMISCR+6
        sta     f:$7e0000+OT6_SCR_COLS
        pla
        plp
        jml     IncGameTime_ext
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
; halo thickens that edge outward: copies of the character's own two body
; sprites, offset by a pixel, BEHIND the character (higher OAM index = lower
; priority among sprites), so what shows of them is a ring of the copies'
; edge pixels -- colour 1, the glowing outline -- just outside the
; character's own.  More boost, more copies (Ot6HaloOff):
;   top half (head):    1 BP left, right; 2 BP + up; 3 BP + two up,
;                       up-left, up-right (the glow rises off the head)
;   bottom half (feet): 1 BP left, right; 2-3 BP + down
; The top half's copies only move up and the bottom half's only down, so the
; two halves' copies never share a scanline: a line holds one half's copies
; at most.
;
; The scanline budget.  The PPU draws at most 34 8-pixel sprite slivers on a
; line (and 32 sprites); past that it drops slivers, the LOWEST-index
; sprites' first, so an overfull line loses the character's own body before
; the copies behind it (the v0.32 review: two neighbours at 3 BP, seven
; copies a half each, reached 40 slivers on a line and their bodies went
; see-through, build/attempts/wt/review-v032-boost-aura/).  So:
;   * one character has the halo at a time: the one whose menu is open if
;     it is boosting, else the highest boost (the lowest slot on a tie).
;     Every other boosting character keeps the glow.  Two halos stacked on
;     neighbouring rows is what overflowed, and one halo's cost is bounded;
;   * its copies are granted against a measured budget.  Every sprite in
;     the frame's OAM buffer whose rows touch the halo's rows -- vanilla's,
;     the cursor, the monsters, the other characters, the character's own
;     body -- adds its slivers (16x16 = 2, 32x32 = 4) to the 16-line bands
;     it touches; a half then gets n copies only while its fullest band
;     + 2n <= 34.  A band's count is at least the count on any one of its
;     lines, so no line the halo touches ends above 34 whatever else is on
;     screen, and a band already full gets no copies.  (34 slivers is at
;     most 17 sprites, under the 32-sprite limit.)
; The budget stops at line $97: FF6 parks nine 32x32 sprites from $97 down
; (OAM entries 115-123) to overflow those lines on purpose and hide what
; goes behind the menu window, so they are no budget of ours.  Cost (CPU
; cycles in the NMI, of a ~45,200-cycle frame; build/attempts/wt/
; v032-boost-aura-2/): ~3,100 for the band scan and ~1,300 for the copies,
; whatever the number of boosting characters.
;
; Copies, not new graphics: the sprite VRAM is spoken for (characters $2000,
; animations $2400-$2dff, numerals/status $2e00, monsters $3000) and so is
; every sprite palette, while the character's own tiles and palette are
; already there.
;
; This hook runs after UpdateSprites has built the frame's OAM buffer ($0300,
; next free entry in $71; ClearSpriteData resets entries 8-114 each frame),
; so the character's entries are found by what DrawCharSprite wrote: the
; slot's own tiles (slot * 4: + 0 the top half, + 2 the bottom; first name
; table) in the slot's palette (4 + slot).  The copies are appended at $71
; and stop short of entry 112, whose high-table byte ClearSpriteData does
; not clear.  A half drawn at the floor DrawCharSprite clamps to (y = $97,
; parked) is not found and gets no copies.
;
; a8/i16, db=$7e.  Clobbers a, $3f and OT6_AURAWORK; preserves x/y.

AW_TOP   = OT6_AURAWORK+0               ; the halo's body entries * 4:
AW_BOT   = OT6_AURAWORK+2               ;   top, bottom half (0 = none)
AW_SLOT2 = OT6_AURAWORK+4               ; its entity offset
AW_LEVEL = OT6_AURAWORK+6
AW_TT    = OT6_AURAWORK+8               ; its top tile (byte)
AW_AN    = OT6_AURAWORK+9               ; its attr low nibble (byte)
AW_S     = OT6_AURAWORK+10              ; 0 top / 2 bottom
AW_END   = OT6_AURAWORK+12              ; the frame's entries end * 4
AW_WLO   = OT6_AURAWORK+14              ; the window: the copies' rows
AW_WHI   = OT6_AURAWORK+16              ;   (the line past it)
AW_HIDX  = OT6_AURAWORK+18              ; the high-table byte being read
AW_LO    = OT6_AURAWORK+20              ; a half's copies' first row
AW_HI    = OT6_AURAWORK+22              ; ... and last
AW_NMAX  = OT6_AURAWORK+24              ; copies wanted, then fitting
AW_X     = OT6_AURAWORK+26              ; Ot6HaloOff index: first, past last
AW_ENDX  = OT6_AURAWORK+28
AW_SUM   = OT6_AURAWORK+30              ; the fullest band's slivers
AW_B0    = OT6_AURAWORK+32              ; a half's bands, first and last
AW_B1    = OT6_AURAWORK+34
AW_Y     = OT6_AURAWORK+36
AW_HB    = OT6_AURAWORK+38
AW_XY    = OT6_AURAWORK+40              ; the source's (y << 8) | x
AW_TA    = OT6_AURAWORK+42              ; ... and its tile | attr << 8
AW_HIST  = OT6_AURAWORK+44              ; slivers per 16-line band, bytes
OT6_AURABANDS = 12                      ; bands 0-11: lines $00-$bf (+1 pad)

; one OAM entry of the band scan, at y + K: if its rows touch the window,
; its slivers go into the 16-line bands it touches.  a8 (b = 0)/i16.
; $3e holds the group's high-table byte.
.macro ot6_halo_entry K
        .local large, next
        lda     $0301+K,y
        cmp     AW_WHI
        bcs     next                    ; starts below the window (or the floor)
        lda     $3e
        and     #(2 << (K / 2))         ; this entry's size bit
        bne     large
        lda     $0301+K,y               ; 16x16: rows y .. y + 15, 2 slivers
        clc
        adc     #$0f
        cmp     AW_WLO
        bcc     next                    ; ends above it
        lda     $0301+K,y
        tax
        lda     f:Ot6Band16,x
        tax
        lda     AW_HIST,x
        clc
        adc     #$02
        sta     AW_HIST,x
        lda     $0301+K,y
        and     #$0f
        beq     next
        lda     AW_HIST+1,x
        clc
        adc     #$02
        sta     AW_HIST+1,x
        bra     next
large:  lda     $0301+K,y               ; 32x32: rows y .. y + 31, 4 slivers
        clc
        adc     #$1f
        bcs     :+                      ; (wraps past 255: it reaches the window)
        cmp     AW_WLO
        bcc     next
:       lda     $0301+K,y
        tax
        lda     f:Ot6Band16,x
        tax
        lda     AW_HIST,x
        clc
        adc     #$04
        sta     AW_HIST,x
        lda     AW_HIST+1,x
        clc
        adc     #$04
        sta     AW_HIST+1,x
        lda     $0301+K,y
        and     #$0f
        beq     next
        lda     AW_HIST+2,x
        clc
        adc     #$04
        sta     AW_HIST+2,x
next:
.endmacro

.proc Ot6AuraHalo
        .a8
        .i16
        phx
        phy
        shorta0                         ; (b = 0 from here: tax moves 16 bits)
        stz     AW_S+1
        ; the halo's character: the one whose menu is open if it boosts,
        ; else the highest boost, the lowest slot on a tie
        lda     $7bca
        beq     h_pick
        lda     $62ca
        and     #$03
        asl     a
        tax
        lda     $3e9d,x
        bne     h_have
h_pick: stz     $3f
        ldx     #$0006
:       lda     $3e9d,x
        cmp     $3f
        bcc     :+
        sta     $3f
        stx     AW_SLOT2
:       dex
        dex
        bpl     :--
        ldx     AW_SLOT2
        lda     $3f
        bne     h_have
        jmp     h_out
h_have: stx     AW_SLOT2
        lda     $3e9d,x
        cmp     #$04
        bcc     :+
        lda     #$03
:       sta     AW_LEVEL
        stz     AW_LEVEL+1
        txa
        asl     a
        sta     AW_TT                   ; its top tile: slot * 4
        txa
        ora     #$08
        sta     AW_AN                   ; its attr: palette 4 + slot, table 0
        ; its two body entries: the first of each tile in its palette
        longa
        stz     AW_TOP
        stz     AW_BOT
        lda     $71
        and     #$00ff
        asl     a
        asl     a
        sta     AW_END                  ; the frame's own entries end
        shorta0
        ldy     #$0020                  ; entry 8, the first per-frame one
h_find: cpy     AW_END
        bcs     h_found
        lda     $0302,y
        eor     AW_TT
        beq     :+                      ; the top tile
        cmp     #$02
        bne     h_fnext                 ; nor the bottom
:       sta     AW_S                    ; 0 top, 2 bottom
        lda     $0303,y
        and     #$0f
        cmp     AW_AN
        bne     h_fnext
        lda     $0301,y
        cmp     #$97
        bcs     h_fnext                 ; parked at the floor: no halo
        ldx     AW_S
        lda     AW_TOP,x
        ora     AW_TOP+1,x
        bne     h_fnext                 ; (the first found is the body)
        longa
        tya
        sta     AW_TOP,x
        lda     AW_TOP                  ; both found: done (DrawCharSprite
        beq     :+                      ;   draws the bodies early, so this
        lda     AW_BOT                  ;   stops in a few entries)
        beq     :+
        shorta0
        bra     h_found
:       shorta0
h_fnext:
        iny
        iny
        iny
        iny
        bra     h_find
h_found:
        longa
        lda     AW_TOP
        bne     :+
        jmp     h_out
:       tay
        lda     $0301,y                 ; the window: the top half's copies'
        and     #$00ff                  ;   first row (y - 2) ...
        sec
        sbc     #$0002
        bcs     :+
        lda     #$0000
:       sta     AW_WLO
        lda     $0301,y                 ; ... to the bottom's last (y + 16),
        and     #$00ff                  ;   or the top's (y + 15) without one
        clc
        adc     #$0010
        ldx     AW_BOT
        beq     :+
        lda     $0301,x
        and     #$00ff
        clc
        adc     #$0011
:       cmp     #$0097                  ; from the floor down: not ours
        bcc     :+
        lda     #$0097
:       sta     AW_WHI                  ; (the line past the window)
        ; the band histogram: every sprite touching the window, its slivers
        ; into the 16-line bands it touches.  Entries 0 to the frame's end,
        ; then the fixed 112-127, four a step (one high-table byte); those
        ; between are ClearSpriteData's ($e0: off screen).
        shorta0
        ldx     #OT6_AURABANDS+2
:       stz     AW_HIST,x
        dex
        bpl     :-
        stz     AW_HIDX+1
        stz     AW_HIDX
        ldy     #$0000
h_step: cpy     AW_END
        bcc     :+
        cpy     #$01c0
        bcs     :+
        ldy     #$01c0                  ; past the frame's: on to entry 112
        lda     #$1c
        sta     AW_HIDX
:       cpy     #$0200
        bcc     :+
        jmp     h_grant
:       ldx     AW_HIDX
        lda     $0500,x
        sta     $3e
        inc     AW_HIDX
        ot6_halo_entry 0
        ot6_halo_entry 4
        ot6_halo_entry 8
        ot6_halo_entry 12
        longa_clc
        tya
        adc     #$0010
        tay
        shorta0
        jmp     h_step
h_grant:
        longa
        ldy     AW_TOP                  ; the top half: rows y - 2 .. y + 15
        lda     $0301,y
        and     #$00ff
        sec
        sbc     #$0002
        bcs     :+
        lda     #$0000
:       sta     AW_LO
        clc
        adc     #$0011
        sta     AW_HI
        ldx     AW_LEVEL
        lda     f:Ot6HaloTopN-1,x
        and     #$00ff
        sta     AW_NMAX
        stz     AW_X
        jsr     Ot6HaloHalf
        ldy     AW_BOT                  ; the bottom half: rows y .. y + 16
        beq     h_out
        lda     $0301,y
        and     #$00ff
        sta     AW_LO
        clc
        adc     #$0010
        sta     AW_HI
        ldx     AW_LEVEL
        lda     f:Ot6HaloBotN-1,x
        and     #$00ff
        sta     AW_NMAX
        lda     #OT6_HALOBOT
        sta     AW_X
        jsr     Ot6HaloHalf
h_out:  shorta0
        ply
        plx
        rts
.endproc

; band of a line (16 lines a band), for every y
Ot6Band16:
        .repeat 256, I
        .byte   I >> 4
        .endrepeat

; one half: y = its entry * 4, rows AW_LO..AW_HI (inclusive) its copies
; cover, AW_NMAX copies wanted from Ot6HaloOff index AW_X.  The fullest band
; those rows touch sets how many fit (2 slivers each, 34 a line); those are
; placed and their slivers added to the bands.  a16/i16.  clobbers a, x, y.
.proc Ot6HaloHalf
        .a16
        .i16
        lda     AW_LO                   ; bands: 16 lines each
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        sta     AW_B0
        lda     AW_HI
        cmp     #$0097                  ; from the floor down: not ours
        bcc     :+
        lda     #$0096
:       lsr     a
        lsr     a
        lsr     a
        lsr     a
        cmp     #OT6_AURABANDS
        bcc     :+
        lda     #OT6_AURABANDS-1
:       sta     AW_B1
        stz     AW_SUM                  ; the fullest band
        ldx     AW_B0
:       lda     AW_HIST,x
        and     #$00ff
        cmp     AW_SUM
        bcc     :+
        sta     AW_SUM
:       cpx     AW_B1
        inx
        bcc     :--
        lda     #34                     ; 2n <= 34 - fullest
        sec
        sbc     AW_SUM
        bcs     :+
        lda     #$0000
:       lsr     a
        cmp     AW_NMAX
        bcc     :+
        lda     AW_NMAX
:       sta     AW_NMAX                 ; the copies that fit
        beq     @none
        asl     a
        clc
        adc     AW_X
        sta     AW_ENDX
        lda     $71                     ; (count what Ot6HaloCopies places)
        and     #$00ff
        pha
        jsr     Ot6HaloCopies
        lda     $71
        and     #$00ff
        sec
        sbc     $01,s
        asl     a                       ; slivers a line gained
        sta     AW_SUM
        pla
        ldx     AW_B0
:       lda     AW_HIST,x               ; (a byte count: the add never
        clc                             ;   carries into the next band's)
        adc     AW_SUM
        sta     AW_HIST,x
        cpx     AW_B1
        inx
        bcc     :-
@none:  rts
.endproc

; append copies of the OAM entry at y (entry * 4) at Ot6HaloOff's offsets
; [AW_X, AW_ENDX), at $71 onward, stopping short of entry 112.
;
; Characters are small (16x16) sprites well inside the screen, so the high
; table (x bit 8, size) is all zeroes for them and for their copies, and
; ClearSpriteData leaves it that way for entries 4-111: the copies need no
; high-table writes.  An entry that is large, has x bit 8 set or sits within
; three pixels of either edge (where a pixel's shift could wrap x) gets no
; copies rather than a slower path.  With x in 3..252 and y below $97, a
; copy's position is one 16-bit add of (dy << 8) + dx to (y << 8) | x.
;
; a16/i16, db=$7e.  clobbers a, x, y.
.proc Ot6HaloCopies
        .a16
        .i16
        tya
        lsr     a
        lsr     a
        pha                             ; entry index
        lsr     a
        lsr     a
        tax
        lda     $0500,x                 ; its high-table byte
        sta     AW_HB
        pla
        and     #$0003
        tax
        lda     f:Ot6HiX,x              ; x bit 8 | size: both must be clear
        and     #$00ff
        sta     AW_Y
        asl     a
        ora     AW_Y
        and     AW_HB
        bne     @done                   ; large or x >= 256: no halo
        lda     $0300,y                 ; (y << 8) | x
        sta     AW_XY
        and     #$00ff
        cmp     #$0003
        bcc     @done                   ; at an edge: no halo
        cmp     #$00fd
        bcs     @done
        lda     $0302,y
        sta     AW_TA                   ; tile | attr: copied as they are
        lda     $71
        and     #$00ff
        asl     a
        asl     a
        tay                             ; the first destination * 4
        ldx     AW_X
@copy:  cpx     AW_ENDX
        bcs     @end                    ; this half's copies all placed
        cpy     #$01c0
        bcs     @end                    ; entries 112+ are not ours to fill
        lda     AW_XY
        clc
        adc     f:Ot6HaloOff,x
        sta     $0300,y                 ; x, y
        lda     AW_TA
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
@done:  rts
.endproc

; copies a half at 1/2/3 BP (before the budget)
Ot6HaloTopN:
        .byte   2, 3, 6
Ot6HaloBotN:
        .byte   2, 3, 3

; x-bit-8 mask for an entry's position within its high-table byte (its size
; bit is the next one up)
Ot6HiX:
        .byte   $01, $04, $10, $40

; halo offsets as 16-bit (dy << 8) + dx deltas to (y << 8) | x; a level
; uses the first n of its half's run.  The top half's move up only, the
; bottom half's down only (see the block comment).
Ot6HaloOff:
        .word   $ffff, $0001            ; top: left, right
        .word   $ff00                   ;   up
        .word   $fe00                   ;   two up
        .word   $feff, $ff01            ;   up-left, up-right
OT6_HALOBOT = * - Ot6HaloOff
        .word   $ffff, $0001            ; bottom: left, right
        .word   $0100                   ;   down

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
