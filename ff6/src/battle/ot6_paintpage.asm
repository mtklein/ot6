; ------------------------------------------------------------------------------
; Relm's field Painter page (#549): the one bank-F0 leaf it needs beyond the
; list's own (Ot6PaintName, Ot6PaintBase), appended after everything so no
; symbol already in bank $f0 moves.  The page itself is menu code
; (menu/ot6_painter_page.asm).
; ------------------------------------------------------------------------------

; [ the field Painter page: row n's id, or $ff when it is not learned yet ]
; The twin of Ot6ThiefPageRow (ot6_thief.asm).  The page draws the eight rows
; in this table's order, which is the battle list's read a column at a time
; (Ot6PaintListOpen packs the learned rows down the left column, then the
; right), and asks the same Ot6PaintRowKnown the list asks.
; in: A = the page row 0-7.  out: A = the row's id or $ff.  any widths, any
; db.  preserves X and Y.  rtl.
.proc Ot6PaintPageRow
        php
        sep     #$20
        .a8
        rep     #$10
        .i16
        phx
        phb
        pha
        lda     #$7e
        pha
        plb                     ; db = $7e for Ot6PaintRowKnown's reads
        pla
        longa
        and     #$0007
        asl
        asl                     ; row * OT6_PAINT_REC
        tax
        shorta0
        jsl     Ot6PaintRowKnown
        bcc     @no
        lda     f:Ot6PaintRowTbl,x
        bra     @out
@no:    lda     #$ff
@out:   plb
        plx
        plp
        rtl
.endproc
