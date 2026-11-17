; ------------------------------------------------------------------------------
; OT6: five-digit damage numerals (#550, Bahamut's Limit Break)
;
; A Limit Break holder's damage goes past 9999 (Ot6DmgCap, ot6_esper.asm), so
; a numeral may need five digits.  It draws them in the same two 16x16 sprites
; and the same four tiles as any numeral, with condensed digits: 6x8 glyphs in
; the numerals' own style and palette indices (outline 12, fill 13, so white
; damage and green healing work unchanged), five spanning 30 pixels centred in
; the 32 (tools/numeral_font.py, ot6_numeral_font.inc).  One to four digits
; draw with vanilla's glyphs exactly as before.  Every numeral, single or
; multi-target, keeps vanilla's sprites, tiles, threads, VRAM transfers and
; timing; only what is drawn into the tile buffer changes.
;
; The value word.  Vanilla's numeral word carried the heal colour in bit 15
; and "Miss" in bit 14 beside a value of at most 9999 (_c262ef), and its
; readers took the value as `and #$3fff`.  A value past 16,383 cannot share
; the word with those flags, so they are coded as ranges past any damage:
;
;   $0000-$bfff   damage of that amount (the cap, OT6_LIMIT, is below $c000)
;   $c000+v       a heal of v (healing is capped at 9999)
;   $f000         Miss
;   $ffff         no numeral (vanilla's, unchanged)
;
; _c262ef writes the heal and Miss codes (`ora #OT6_NUM_HEAL`, `lda
; #OT6_NUM_MISS`, same size as vanilla's), and only the two numeral commands
; read them: GfxCmd_0b (single, Ot6NumSingle_ext, in place of its Miss and
; digit branches) and GfxCmd_03's set-up (_c1a5fa, Ot6NumMulti_ext, likewise).
; #539's machinery is untouched: four threads, and GfxCmd_0b's closing `inc
; $632e` its last act.
;
; Composing five digits: position p's digit is OR-ed into the buffer as a
; pre-shifted pair of tiles, Ot6NumCondensed + (p * 10 + digit) * 64, at the
; buffer's byte Ot6NumCondFirst[p]; a digit that straddles two tiles fills
; both, and the glyphs do not overlap, so OR is exact.
; ------------------------------------------------------------------------------

OT6_NUM_HEAL = $c000
OT6_NUM_MISS = $f000
.assert OT6_LIMIT < OT6_NUM_HEAL, error, "the Limit Break cap must stay below the heal code"
.assert OT6_NUM_HEAL + 9999 < OT6_NUM_MISS, error, "a heal's code must stay below Miss's"
.assert OT6_LIMIT <= 99999, error, "the numerals draw at most five digits"

OT6_NUMGLYPH = $bc40            ; $7f: vanilla's ten digit glyphs, 32 bytes each
OT6_NUMMISS  = $bc00            ; $7f: "Miss", two tiles

        .include "ot6_numeral_font.inc"

; vanilla's multi-target slots in the $7f:e400 buffer (btlgfx _c1a749, copied:
; it is not exported)
Ot6NumMultiSlot:
        .word   $e400, $e480, $e500, $e580, $e800, $e880, $e900, $e980
        .word   $ec00, $ec80

; ------------------------------------------------------------------------------

; [ decode a numeral word into its kind and digits ]
;
; in: A (a16) = the word.  out: $1e = $80 for a heal (green), else 0; carry
; set for Miss; else $69-$6d = the five decimal digits (most significant
; first) and A (a16) = how many are shown (1-5, no leading zeros).  dp is the
; battle graphics' (0); $22-$23 scratch (HexToDec's).  x/y kept; a16 out.
.proc Ot6NumDecode
        .a16
        sep     #$20
        .a8
        stz     $1e
        rep     #$20
        .a16
        cmp     #OT6_NUM_MISS
        bne     :+
        sec
        rts
:       cmp     #OT6_NUM_HEAL
        bcc     @val
        and     #$3fff          ; a heal
        sep     #$20
        .a8
        pha
        lda     #$80
        sta     $1e
        pla
        rep     #$20
        .a16
@val:   phx
        ldx     #$0000
@dig:   stz     $22             ; this digit
@sub:   cmp     f:@pow,x
        bcc     @put
        sbc     f:@pow,x
        inc     $22
        bra     @sub
@put:   pha
        txa
        lsr
        tax
        sep     #$20
        .a8
        lda     $22
        sta     $69,x
        rep     #$20
        .a16
        txa
        asl
        tax
        pla
        inx
        inx
        cpx     #$000a
        bcc     @dig
        ldx     #$0000          ; the shown count: 5 less the leading zeros,
@lead:  lda     $69,x           ;   never below 1
        and     #$00ff
        bne     @count
        inx
        cpx     #$0004
        bcc     @lead
@count: txa
        eor     #$ffff
        sec
        adc     #$0005          ; 5 - x
        plx
        clc
        rts
@pow:   .word   10000, 1000, 100, 10, 1
.endproc

; [ draw a decoded value into a four-tile buffer ]
;
; in: a16 i16, A = the shown count (Ot6NumDecode's), $69-$6d the digits, Y =
; the buffer (cleared, in the data bank: `sta a:0,y`).  out: $14 = the half
; width, four pixels a digit as vanilla's (16 for five: the condensed row is
; centred in the same 32 pixels).  x/y clobbered, $22-$27 scratch; a16 out.
.proc Ot6NumDraw
        .a16
        .i16
        cmp     #$0005
        bcs     @five
; one to four digits: vanilla's glyphs, left-aligned, one tile each
        pha
        asl
        asl
        sta     $14
        lda     #$0005
        sec
        sbc     1,s
        tax                     ; the first shown digit
        pla
@std:   lda     $69,x
        phx
        and     #$000f
        asl
        asl
        asl
        asl
        asl
        clc
        adc     #OT6_NUMGLYPH
        tax
        lda     #$0010
        sta     $22
:       lda     f:$7f0000,x
        sta     a:$0000,y
        inx
        inx
        iny
        iny
        dec     $22
        bne     :-
        plx
        inx
        cpx     #$0005
        bcc     @std
        rts
; five: the condensed digits OR-ed in, position by position
@five:  lda     #$0010
        sta     $14
        sty     $24             ; the buffer
        ldx     #$0000
@pos:   phx                     ; [1,s] the position
        lda     $69,x
        and     #$000f
        sta     $22             ; its digit
        lda     f:Ot6NumCondFirst,x
        and     #$00ff
        clc
        adc     $24
        tay                     ; where its pair goes
        lda     1,s
        asl
        sta     $26
        asl
        asl
        clc
        adc     $26             ; position * 10
        clc
        adc     $22             ; + digit
        xba                     ; * 256
        lsr
        lsr                     ; * 64
        tax
        lda     #$0020          ; 32 words: the pair
        sta     $26
:       lda     f:Ot6NumCondensed,x
        ora     a:$0000,y
        sta     a:$0000,y
        inx
        inx
        iny
        iny
        dec     $26
        bne     :-
        plx
        inx
        cpx     #$0005
        bcc     @pos
        rts
.endproc

; ------------------------------------------------------------------------------

; [ a single numeral's digits ]
;
; jsl from GfxCmd_0b (btlgfx_main.asm @a510) in place of its Miss and digit
; branches, once the value's high byte has been found not to be $ff.  in: a8
; i16, db=$7e, ($76) = the script command (+2 the value word), the buffer
; $60b3 cleared (and its bottoms sent: vanilla's first transfer).  out: $14 =
; the half width, $1e = the green flag, the buffer drawn; a8 with A = 0 (B
; too: the caller's `tax` is i16).  The caller goes on at @a589.
.proc Ot6NumSingle_ext
        .a8
        .i16
        rep     #$20
        .a16
        ldy     #$0002
        lda     ($76),y
        jsr     Ot6NumDecode
        bcc     @num
; Miss: vanilla's two tiles in slots 1-2, half width 8
        ldx     #$0000
:       lda     f:$7f0000+OT6_NUMMISS,x
        sta     $60b3+$20,x
        inx
        inx
        cpx     #$0040
        bcc     :-
        lda     #$0008
        sta     $14
        bra     @out
@num:   ldy     #$60b3
        jsr     Ot6NumDraw
@out:   tdc
        sep     #$20
        rtl
.endproc

; [ a multi-target numeral's digits ]
;
; jsl from _c1a5fa (btlgfx_main.asm @a627) in place of its Miss and digit
; branches, for target $20 whose value's high byte ($1e) is not $ff.  in: a8
; i16, db=$7e, y = the target * 2 (its word in the $2bce block), the $7f:e400
; buffer cleared.  out: $14 = the half width (0 for Miss, as vanilla left it
; on that path), $1e = the green flag, the target's four tiles drawn; a8 with
; A = 0, y kept; the caller goes on at @a6bd.
.proc Ot6NumMulti_ext
        .a8
        .i16
        phy
        rep     #$20
        .a16
        lda     $2bce,y
        jsr     Ot6NumDecode
        pha                     ; the shown count
        php                     ; (carry: Miss)
        lda     $20
        and     #$00ff
        asl
        tax
        lda     f:Ot6NumMultiSlot,x
        tay                     ; the target's first tile
        sep     #$20
        .a8
        phb
        lda     #$7f
        pha
        plb                     ; db=$7f: the buffer's bank
        rep     #$20
        .a16
        lda     2,s             ; the pushed p (above the pushed b)
        and     #$0001
        beq     @num
; Miss: vanilla's two tiles in slots 1-2
        ldx     #$0000
:       lda     f:$7f0000+OT6_NUMMISS,x
        sta     a:$0020,y
        iny
        iny
        inx
        inx
        cpx     #$0040
        bcc     :-
        stz     $14
        bra     @out
@num:   lda     3,s             ; the shown count
        jsr     Ot6NumDraw
@out:   sep     #$20
        .a8
        plb
        plp
        rep     #$20
        .a16
        pla
        ply
        tdc
        sep     #$20
        rtl
.endproc
