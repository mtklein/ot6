; ------------------------------------------------------------------------------
; OT6: five-digit damage numerals (#550, Bahamut's Limit Break)
;
; A Limit Break holder's damage goes past 9999 (Ot6DmgCap, ot6_esper.asm), so
; the numerals draw up to five digits, with the same glyphs, the same bounce
; and the same timing as vanilla's four, centred the same way.
;
; The value word.  Vanilla's numeral word carried the heal colour in bit 15
; and "Miss" in bit 14 beside a value of at most 9999 (_c262ef), and its
; readers took the value as `and #$3fff`.  A value past 16,383 cannot share
; the word with those flags, so they are coded as ranges past any damage:
;
;   $0000-$bfff   damage of that amount (the cap, OT6_LIMIT, is below $c000)
;   $c000+v       a heal of v (healing is capped at 9999, so v < $3fff)
;   $f000         Miss
;   $ffff         no numeral (vanilla's, unchanged)
;
; _c262ef writes the heal and Miss codes (`ora #OT6_NUM_HEAL`, `lda
; #OT6_NUM_MISS`, same size as vanilla's), and only the two numeral commands
; read them: GfxCmd_0b (single, Ot6NumSingle) and GfxCmd_03's set-up
; (_c1a5fa, Ot6NumMulti).
;
; Single numerals (four threads, GfxCmd_0b; #539's Ot6NumQueued and
; Ot6RevealPoll rely on the four and on the command's closing `inc $632e`, and
; both are as vanilla left them).  Each numeral is 16x16 sprites whose top
; tiles hold the digits and whose bottom tiles are blank.  Vanilla packed four
; threads of four digit tiles into sprite tiles $c0-$cf (bottoms $d0-$df);
; five digits need a fifth tile per thread, and only tiles outside the
; animation area ($40-$bf, which every sprite animation reloads, even while
; a numeral from an earlier hit is still up) are safe.  So a thread's five
; slots are an A pair (slots 0-1) and a B triple (slots 2-4):
;
;   thread   A pair    B triple   (bottoms: the row below each, blank)
;     0      $c0-$c1   $c2-$c4
;     1      $c5-$c6   $c7-$c9
;     2      $ec-$ed   $ca-$cc    $ec-$ef/$fc-$ff are the status block's
;     3      $ee-$ef   $cd-$cf    four blank columns (status_en.4bpp)
;
; Sprite A shows slots 0-1, sprite B slots 2-3 and, for five digits only,
; sprite C slots 3-4, drawn eight pixels right of B so its slot 3 lands on
; B's: the same tile at the same place, so nothing shows twice.  Digits are
; left-aligned in the slots and the half width ($6326) is four pixels a
; digit, as vanilla's: one to four digits draw exactly as before (A and B,
; same tiles' contents, same places).  The digits reach the tiles in
; GfxCmd_0b's two transfers, a frame apart, as before; the digits are drawn
; before the first (Ot6NumPrep), so the second, on the numeral's own frame,
; is one transfer no larger than vanilla's (Ot6NumTfr).  Slots 0-3 are
; vanilla's 128-byte buffer ($60b3, same layout); slot 4 is a glyph number in
; the thread's $632a, which vanilla only ever cleared.
;
; Multi-target numerals (five or more targets, GfxCmd_03, ten numerals).
; Vanilla's ten four-tile slots fill the animation area's rows $60, $80, $a0
; at once, with $a8-$af/$b8-$bf left over, and the whole block is DMA'd from
; $7f:e400 when the numerals start, then shown while the script waits them
; out.  A fifth digit there is the ten-thousands digit, 1 to 5 (OT6_LIMIT <=
; 59,999), drawn by a third sprite from a glyph row kept in the left-over
; tiles: $a9 "1", $aa "2", $ac "3", $ad "4", $af "5", with $a8, $ab, $ae and
; $b8-$bf blank, so each glyph has a blank neighbour (sprite $a8 shows
; [blank 1], $aa [2 blank], $ab [blank 3], $ad [4 blank], $ae [blank 5]).  The
; four vanilla slots hold the other four digits and the half width is set so
; the five centre as one.  The digit is kept in the target's $7b5d, which
; vanilla only ever cleared.
;
; OAM: a five-digit numeral takes three entries, not two.  The third is
; drawn only while the next entry is at most 111 (ClearSpriteData clears the
; high table through entry 111; 115-123 are the menu's parked sprites).
; ------------------------------------------------------------------------------

OT6_NUM_HEAL = $c000
OT6_NUM_MISS = $f000
.assert OT6_LIMIT < OT6_NUM_HEAL, error, "the Limit Break cap must stay below the heal code"
.assert OT6_NUM_HEAL + 9999 < OT6_NUM_MISS, error, "a heal's code must stay below Miss's"

OT6_NUMGLYPH = $bc40            ; $7f: the ten digit glyphs, 32 bytes each
OT6_NUMMISS  = $bc00            ; $7f: "Miss", two tiles

; the tops of each thread's slots (VRAM word addresses): A pair, B triple
Ot6NumTopA:
        .word   $2c00, $2c50, $2ec0, $2ee0
Ot6NumTopB:
        .word   $2c20, $2c70, $2ca0, $2cd0
; the bottoms of the slots that sit in rows $c0/$d0 (A's too for threads 0
; and 1), and how many bytes they are
Ot6NumBot:
        .word   $2d00, $2d50, $2da0, $2dd0
Ot6NumBotLen:
        .word   $00a0, $00a0, $0060, $0060
; sprite tiles A, B and C per thread
Ot6NumTileA:
        .byte   $c0, $c5, $ec, $ee
Ot6NumTileB:
        .byte   $c2, $c7, $ca, $cd
Ot6NumTileC:
        .byte   $c3, $c8, $cb, $ce
; the multi glyph row: per ten-thousands digit 1-5, the sprite's tile and its
; x offset from sprite A (-8: the glyph is the sprite's left half; -16: right)
Ot6NumMultiTile:
        .byte   $a8, $aa, $ab, $ad, $ae
Ot6NumMultiDx:
        .word   $fff0, $fff8, $fff0, $fff8, $fff0
; where each glyph goes in the $7f:e400 buffer ((tile - $60) * 32 + $e400)
Ot6NumMultiAt:
        .word   $ed20, $ed40, $ed80, $eda0, $ede0
; blank tiles: a slot with no digit, and the bottoms (up to five)
Ot6NumBlank:
        .res    160, $00

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

; [ copy one digit glyph to a buffer slot ]
;
; in: a8, $22 = scratch, A = the digit, Y (i16) = the destination (bank $7e,
; or bank $7f when the caller's db is $7f: the store is `sta a:0,y` through
; db), x clobbered.  Leaves a8.
.proc Ot6NumGlyph
        .a8
        rep     #$20
        .a16
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
        sep     #$20
        .a8
        rts
.endproc

; ------------------------------------------------------------------------------

; [ a single numeral's digits ]
;
; jsl from GfxCmd_0b (btlgfx_main.asm @a510) in place of its Miss and digit
; branches, once the value's high byte has been found not to be $ff.  in: a8
; i16, db=$7e, ($76) = the script command (+2 the value word), the buffer
; $60b3 cleared, the thread $632e & 3.  out: $14 = the half width, $1e = the
; green flag, the buffer's slots 0-3 and the thread's $632a (slot 4's digit +
; 1, or 0) filled; a8 with A = 0 (B too: the caller's `tax` is i16).  The
; caller goes on at @a589.
.proc Ot6NumSingle_ext
        .a8
        .i16
        rep     #$20
        .a16
        lda     $632e
        and     #$0003
        tax
        sep     #$20
        .a8
        stz     $632a,x         ; no fifth digit, unless one is found below
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
@num:   pha                     ; the shown count
        asl
        asl
        sta     $14             ; the half width: 4 pixels a digit
        lda     #$0005
        sec
        sbc     1,s
        tax                     ; the first shown digit
        pla
        ldy     #$60b3          ; slot 0
        sep     #$20
        .a8
@slot:  cpy     #$60b3 + $80
        bcs     @fifth
        lda     $69,x
        phx
        jsr     Ot6NumGlyph     ; (y moves on 32)
        plx
        inx
        cpx     #$0005
        bcc     @slot
        bra     @out
@fifth: lda     $69,x           ; slot 4 (only with five digits)
        inc     a
        pha
        rep     #$20
        .a16
        lda     $632e
        and     #$0003
        tax
        sep     #$20
        .a8
        pla
        sta     $632a,x
@out:   tdc
        sep     #$20
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ a single numeral's tiles to VRAM, in the NMI ]
;
; jsl from _c10640 (the battle NMI) in place of its one 128-byte transfer,
; once GfxCmd_0b has asked for one ($6316, cleared by the caller; $6317 the
; VRAM address from its tables).  GfxCmd_0b asks twice, a frame apart: first
; the bottoms ($2d00 + $40 * thread, vanilla's table), then the tops (its
; second table, repointed to $2c00, $2c50, $2ca0, $2cd0).  Ot6NumPrep has
; drawn the digits by the first, so the first frame carries everything but
; four tiles: the thread's bottoms blanked, slot 4 (the glyph $632a names, or
; a blank) and, for threads 2 and 3, the A pair (slots 0-1) in the status
; block.  The second frame, the one the numeral appears on and the one
; #539's reveal and its HUD redraw land on, carries one transfer no larger
; than vanilla's: slots 0-3 (threads 0 and 1) or slots 2-3 (threads 2 and 3)
; from the buffer.  (A first version moved all five slots on the second
; frame, in two or three transfers: about three scanlines of the NMI where
; vanilla's took one, on the frame #539's reveal redraws the HUD, whose flush
; runs late in the same NMI: build/attempts/wt/v049-limitbreak/lab/
; reveal_nmi2.log.)  Each
; transfer is TfrVRAM's (DMA channel 7, VMAINC as the NMI left it).  a8 i16,
; db=$7e, dp=0.  Clobbers a/x/y; a8, A = 0 out.
.proc Ot6NumTfr_ext
        .a8
        .i16
        rep     #$20
        .a16
        lda     $6317
        bit     #$0100
        bne     @bottom
; the numeral's frame: one transfer, from $7e
        sta     f:$002116
        cmp     #$2ca0
        bcs     :+
        ldx     #$60b3          ; threads 0 and 1: slots 0-3
        ldy     #$0080
        bra     @top
:       ldx     #$60b3 + $40    ; threads 2 and 3: slots 2-3
        ldy     #$0040
@top:   txa
        sta     f:$004372
        tya
        sta     f:$004375
        sep     #$20
        .a8
        lda     #$7e
        sta     f:$004374
        lda     #$01
        sta     f:$004370
        lda     #$18
        sta     f:$004371
        lda     #$80
        sta     f:$00420b
        tdc
        rtl
; the frame before: the bottoms, slot 4 and (threads 2, 3) the A pair
        .a16
@bottom:
        phb
        pea     $0000
        plb
        plb                     ; db=0 for the PPU and DMA registers
        lsr
        lsr
        lsr
        lsr
        lsr
        and     #$0006
        tax                     ; the thread * 2
        lda     f:Ot6NumBot,x
        tay
        lda     f:Ot6NumBotLen,x
        phx
        ldx     #.loword(Ot6NumBlank)
        jsr     @dmaF0          ; the bottoms
        lda     1,s
        tax
        lda     f:Ot6NumTopB,x
        clc
        adc     #$0020
        tay                     ; slot 4's tile
        txa
        lsr
        tax
        lda     f:$7e632a,x
        and     #$00ff
        beq     @blank
        dec     a
        asl
        asl
        asl
        asl
        asl
        clc
        adc     #OT6_NUMGLYPH
        tax
        lda     #$0020
        sta     $36
        sep     #$20
        .a8
        lda     #$7f
        jsr     @dma
        rep     #$20
        .a16
        bra     @pair
@blank: ldx     #.loword(Ot6NumBlank)
        lda     #$0020
        jsr     @dmaF0
@pair:  plx
        cpx     #$0004
        bcc     @done           ; threads 0 and 1: slots 0-1 go with the tops
        lda     f:Ot6NumTopA,x
        tay
        lda     #$0040
        sta     $36
        ldx     #$60b3
        sep     #$20
        .a8
        lda     #$7e
        jsr     @dma
@done:  sep     #$20
        .a8
        plb
        tdc
        rtl
        .a16
; A (a16) = the length, X = the source in this bank (a blank), Y = the VRAM
; word address
@dmaF0: sta     $36
        sep     #$20
        .a8
        lda     #^Ot6NumBlank
        jsr     @dma
        rep     #$20
        .a16
        rts
; A (a8) = the source bank, X = the source, Y = the VRAM word address, $36
; = the length; db=0.  X clobbered, Y kept, a8.
        .a8
@dma:   sty     $2116
        stx     $4372
        sta     $4374
        lda     #$01
        sta     $4370
        lda     #$18
        sta     $4371
        ldx     $36
        stx     $4375
        lda     #$80
        sta     $420b
        rts
.endproc

; ------------------------------------------------------------------------------

; [ a single numeral's digits, drawn ahead ]
;
; jsl from GfxCmd_0b (btlgfx_main.asm @a4e2) in place of its buffer clear,
; before it asks for the first transfer: the buffer cleared and, unless the
; word is $ffff (no numeral), the digits drawn into it and slot 4 into the
; thread's $632a (Ot6NumSingle's work, which @a510 repeats for its $14 and
; $1e).  a8 i16, db=$7e.  a8, A = 0 out (the caller's next `tax` is i16).
.proc Ot6NumPrep_ext
        .a8
        .i16
        rep     #$20
        .a16
        ldx     #$007e
:       stz     $60b3,x
        dex
        dex
        bpl     :-
        ldy     #$0002
        lda     ($76),y
        cmp     #$ffff
        bne     :+
        lda     $632e
        and     #$0003
        tax
        sep     #$20
        .a8
        stz     $632a,x
        tdc
        rtl
:       sep     #$20
        .a8
        jml     Ot6NumSingle_ext
.endproc

; ------------------------------------------------------------------------------

; [ one 16x16 numeral entry at $71 ]
;
; in: A (a16) = the attribute << 8 | the tile, $36 (word) = its x, $38 = its
; y; db=$7e, i16.  $71 moves on one.  x kept; a16 out.
.proc Ot6NumOam
        .a16
        .i16
        phx
        pha
        lda     $71
        and     #$00ff
        asl
        asl
        tay
        pla
        sta     $0302,y         ; tile, attribute
        sep     #$20
        .a8
        lda     $38
        sta     $0301,y
        lda     $36
        sta     $0300,y
        lda     $37
        and     #$01
        beq     :+
        rep     #$20            ; the x high bit, as vanilla sets it
        .a16
        lda     $a17f,y
        and     #$00ff
        tax
        sep     #$20
        .a8
        lda     $0500,x
        ora     $a77f,y
        sta     $0500,x
:       inc     $71
        rep     #$20
        .a16
        plx
        rts
.endproc

; [ a single numeral's sprites ]
;
; jsl from _c12cc2 (btlgfx_main.asm @2d12) in place of its two-sprite write.
; in: x = the thread, $36 (word) = sprite A's x, $38 = the y, $3a = the
; palette mask (vanilla's: $ff for a character, the monster's $80e8), db=$7e,
; a8.  Writes A and B (and C with five digits) at $71 and moves $71 on;
; $36 and $38 are left as scratch (vanilla's last use of them).  a8, A = 0.
.proc Ot6NumSprSingle_ext
        .a8
        php
        rep     #$10
        .i16
        phx
        lda     $631a,x         ; green?
        and     #$80
        bne     :+
        lda     #$38            ; palette 4 (white numerals)
        bra     :++
:       lda     #$3a            ; palette 5 (green numerals)
:       and     $3a
        xba                     ; the attribute in B
        lda     $38
        cmp     #$97
        bcc     :+
        lda     #$e0            ; hidden at y $97 and below, as vanilla
        sta     $38
:       lda     f:Ot6NumTileA,x
        rep     #$20
        .a16
        pha                     ; [1,s] tile A, [2,s] the attribute
        jsr     Ot6NumOam       ; A
        lda     $36
        clc
        adc     #$0010
        sta     $36
        sep     #$20
        .a8
        lda     2,s
        xba
        lda     f:Ot6NumTileB,x
        rep     #$20
        .a16
        jsr     Ot6NumOam       ; B
        sep     #$20
        .a8
        lda     $632a,x
        beq     @out            ; four digits or fewer
        lda     $71
        cmp     #112
        bcs     @out            ; no room (see the header)
        rep     #$20
        .a16
        lda     $36
        clc
        adc     #$0008
        sta     $36
        sep     #$20
        .a8
        lda     f:Ot6NumTileC,x
        xba
        lda     2,s             ; the attribute
        xba
        rep     #$20
        .a16
        jsr     Ot6NumOam       ; C
@out:   rep     #$20
        .a16
        pla
        plx
        plp
        tdc
        rtl
.endproc

; ------------------------------------------------------------------------------

; vanilla's multi-target slots in the $7f:e400 buffer and their sprite tiles
; (btlgfx _c1a749 and _c2e398, copied: neither is exported)
Ot6NumMultiSlot:
        .word   $e400, $e480, $e500, $e580, $e800, $e880, $e900, $e980
        .word   $ec00, $ec80
Ot6NumMultiTileA:
        .byte   $60, $64, $68, $6c, $80, $84, $88, $8c, $a0, $a4

; [ a multi-target numeral's digits ]
;
; jsl from _c1a5fa (btlgfx_main.asm @a627) in place of its Miss and digit
; branches, for target $20 whose value's high byte ($1e) is not $ff.  in: a8
; i16, db=$7e, y = the target * 2 (its word in the $2bce block), the $7f:e400
; buffer cleared.  out: $14 = the half width, $1e = the green flag, the
; target's four slots and $7b5d (its ten-thousands digit, 0 for none) filled,
; and the glyph row written; a8 with A = 0, y kept; the caller goes on at
; @a6bd.
.proc Ot6NumMulti_ext
        .a8
        .i16
        phy
        phb
        lda     #$7f
        pha
        plb
        ldx     #$0000          ; the glyph row (each time: cheap, and the
@row:   phx                     ;   buffer was just cleared)
        rep     #$20
        .a16
        txa
        asl
        tax
        lda     f:Ot6NumMultiAt,x
        tay
        sep     #$20
        .a8
        lda     1,s
        inc     a               ; the digit, 1-5
        jsr     Ot6NumGlyph
        plx
        inx
        cpx     #$0005
        bcc     @row
        plb                     ; db=$7e again
        rep     #$20
        .a16
        lda     $20
        and     #$00ff
        tax
        sep     #$20
        .a8
        stz     $7b5d,x         ; no fifth digit, unless one is found below
        rep     #$20
        .a16
        lda     1,s             ; the target * 2
        tay
        lda     $2bce,y
        jsr     Ot6NumDecode
        bcc     @num
; Miss: vanilla's two tiles in slots 1-2 ($14 stays 0, as vanilla left it
; on this path)
        jsr     @slot0
        phb
        sep     #$20
        .a8
        lda     #$7f
        pha
        plb
        rep     #$20
        .a16
        ldx     #$0000
:       lda     f:$7f0000+OT6_NUMMISS,x
        sta     a:$0020,y
        iny
        iny
        inx
        inx
        cpx     #$0040
        bcc     :-
        plb
        stz     $14
        bra     @out
@num:   cmp     #$0005
        bcc     @four
; five digits: the first is the glyph row's, the other four the slots', and
; the half width puts the five's centre where vanilla's four had theirs
        lda     $20
        and     #$00ff
        tax
        sep     #$20
        .a8
        lda     $69
        sta     $7b5d,x
        rep     #$20
        .a16
        lda     #$000c
        sta     $14
        ldx     #$0001          ; the slots show digits 1-4
        bra     @fill
@four:  pha
        asl
        asl
        sta     $14             ; four pixels a digit, as vanilla
        lda     #$0005
        sec
        sbc     1,s
        tax                     ; the first digit the slots show
        pla
@fill:  jsr     @slot0
        phb
        sep     #$20
        .a8
        lda     #$7f
        pha
        plb
@dig:   lda     $69,x
        phx
        jsr     Ot6NumGlyph
        plx
        inx
        cpx     #$0005
        bcc     @dig
        plb
@out:   ply
        tdc
        sep     #$20
        rtl
        .a16
; y = the target's first slot in the $7f:e400 buffer; x kept
@slot0: phx
        lda     $20
        and     #$00ff
        asl
        tax
        lda     f:Ot6NumMultiSlot,x
        tay
        plx
        rts
.endproc

; ------------------------------------------------------------------------------

; [ a multi-target numeral's sprites ]
;
; jsl from DrawDmgNumSprites (btlgfx_main.asm @2b80) in place of its
; two-sprite write.  in: $3a = the target, $36 (word) = sprite A's x, $38 =
; the y, db=$7e, a8.  Writes A and B (and, for a five-digit value, the glyph
; row's sprite left of A) at $71 and moves $71 on.  a8, A = 0 out.
.proc Ot6NumSprMulti_ext
        .a8
        php
        rep     #$30
        .a16
        .i16
        lda     $3a
        and     #$00ff
        tax
        sep     #$20
        .a8
        lda     $7b3f,x
        and     #$80
        bne     :+
        lda     #$38
        bra     :++
:       lda     #$3a
:       xba                     ; the attribute in B
        lda     f:Ot6NumMultiTileA,x
        rep     #$20
        .a16
        pha
        jsr     Ot6NumOam       ; A
        lda     $36
        pha                     ; A's x
        clc
        adc     #$0010
        sta     $36
        lda     3,s
        inc     a
        inc     a
        jsr     Ot6NumOam       ; B
        pla
        sta     $36
        sep     #$20
        .a8
        lda     $7b5d,x
        beq     @out
        lda     $71
        cmp     #112
        bcs     @out            ; no room (see the header)
        lda     $7b5d,x
        dec     a
        rep     #$20
        .a16
        and     #$00ff
        asl
        tax
        lda     $36
        clc
        adc     f:Ot6NumMultiDx,x
        sta     $36
        txa
        lsr
        tax
        sep     #$20
        .a8
        lda     f:Ot6NumMultiTile,x
        xba
        lda     2,s             ; the attribute
        xba
        rep     #$20
        .a16
        jsr     Ot6NumOam       ; the ten-thousands digit
@out:   rep     #$20
        .a16
        pla
        plp
        tdc
        rtl
.endproc
