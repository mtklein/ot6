; ------------------------------------------------------------------------------
; ot6: the field Skills > Magic list, packed (#541)
;
; Vanilla's field Magic list ($7e9d89, CalcMagicOrder) is all 54 spells in the
; Config "Magic Order", two to a row, and a spell the character cannot cast is
; drawn as a blank cell (the draw writes $ff over it, _c34fc4 @501a), so the
; page scrolls 27 rows of mostly blank cells.  Here the order is built the
; same way and then packed: each spell the character can cast right now
; (_c350a2: his learned table, his stone's and his gear's grants, Strago's
; Analyze; for Gogo, any party member's) keeps its place in that order, the
; rest close up, and the tail is $ff.  The page then scrolls only as far as
; the list reaches ($5c), and the cursor never rests past its last spell.
;
; Called through the two `jsr CalcMagicOrder` sites (DrawMagicMenu and the Y
; toggle in MenuState_1a) and the `jsr MoveListCursor` in UpdateMagicCursor,
; each retargeted here with the same three bytes.  This code sits in its own
; segment after the vanilla bank (ot6_menu_dense, cfg/ff6-en.cfg), so no
; vanilla menu code or data moves (skills.asm _c350ae's note: field states
; can hold live C3 return addresses).
; ------------------------------------------------------------------------------

.if LANG_EN

.segment "ot6_menu_dense"

OT6_MAGIC_SPELLS = $36          ; 54
OT6_MAGIC_ROWS_SHOWN = 8

; [ build the Magic list in the Config order, then pack it ]

; a8/i16, the menu's DBR.  Sets $5c (the scroll's top) and keeps the cursor
; on a listed spell.  Clobbers a/x/y and $e0/$e1 (_c350a2's own scratch).
Ot6MagicOrderDense:
        jsr     CalcMagicOrder          ; $7e9d89[0..53]: the Config order
        ldx     z0                      ; x: the cell read
        txy                             ; y: the cell written
@cell:  phx
        phy
        lda     $7e9d89,x
        cmp     #$ff
        beq     @drop
        jsr     _c350a2                 ; $ff = this character can cast it
        cmp     #$ff
        bne     @drop
        ply
        plx
        lda     $7e9d89,x
        phx
        tyx
        sta     $7e9d89,x               ; written at or before the read
        plx
        iny
        bra     @next
@drop:  ply
        plx
@next:  inx
        cpx     #OT6_MAGIC_SPELLS
        bne     @cell
        tyx
        lda     #$ff
@fill:  cpx     #OT6_MAGIC_SPELLS
        beq     @top
        sta     $7e9d89,x
        inx
        bra     @fill
@top:   tya                             ; n, the spells listed
        inc
        lsr                             ; rows: ceil(n / 2)
        sec
        sbc     #OT6_MAGIC_ROWS_SHOWN
        bcs     :+
        lda     #0                      ; one page or less: no scroll
:       sta     $5c
        lda     $4a
        cmp     $5c
        bcc     :+
        lda     $5c
        sta     $4a                     ; the scroll at most the top
:       jsr     Ot6MagicClampDense
        jmp     InitMagicCursor         ; the cursor sprite, $4b and the
                                        ;   saved position, from the clamp

; [ UpdateMagicCursor's move, then the clamp ]

Ot6MagicMoveDense:
        jsr     MoveListCursor
        ; fall through

; [ a cursor past the last listed spell moves to the last one ]

; $4a scroll, $4e row on the page, $50 its absolute row, $4d/$4f column.
; Clobbers a/x.
Ot6MagicClampDense:
        ldx     z0
@n:     lda     $7e9d89,x               ; n: the packed list's length
        cmp     #$ff
        beq     @have
        inx
        cpx     #OT6_MAGIC_SPELLS
        bne     @n
@have:  cpx     #0
        beq     @done                   ; nothing listed (the page is not
                                        ;   offered then): leave it be
        lda     $4a
        clc
        adc     $4e
        sta     $50                     ; the absolute row, kept with $4a
        asl
        clc
        adc     $4d                     ; the cell
        stx     $e0
        cmp     $e0
        bcc     @done                   ; on a spell
        dex                             ; the last spell
        txa
        and     #$01
        sta     $4d
        sta     $4f
        txa
        lsr
        sta     $50                     ; its row
        cmp     $4a
        bcs     :+
        sta     $4a                     ; (above the page: scroll to it)
:       sec
        sbc     $4a
        sta     $4e
@done:  rts

.endif
