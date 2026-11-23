; ------------------------------------------------------------------------------
; Celes's field Rune Knight page (#563): the one bank-F0 leaf it needs beyond
; the list's own (Ot6RuneName, Ot6RuneBitTbl, Ot6BreakLearned), appended
; after everything so no symbol already in bank $f0 moves.  The page itself
; is menu code (menu/ot6_runeknt_page.asm).
; ------------------------------------------------------------------------------

; the page's help lines (tools/kit_pages.py --write)
        .include "ot6_runepage_desc.inc"

; The page's rows, in the menu's list buffer.  A row is its id less
; OT6_RUNE_RUNIC, which is also its help line (the menu's LoadBigText reads
; the row under the cursor from this buffer): 0 Runic, 1-8 a blade row by
; element bit, 9 Break Blade, 10 Break Blade not learned yet, $ff no row.
OT6_RPAGE_ROW    = $9d89        ; eight rows
OT6_RPAGE_COST   = $9d91        ; and their prices
OT6_RPAGE_KNOWN  = $9d99        ; the menu's verdict on spells $00-$35: $ff
                                ;   where the field Magic list has the spell
OT6_RPAGE_SPELLS = $36
OT6_RPAGE_LOCKED = OT6_RUNE_BREAK + 1 - OT6_RUNE_RUNIC
OT6_RPAGE_BLADES = 6            ; the battle shell's eight cells: Runic, six
                                ;   blades, Break Blade

; [ the field Rune Knight page: its rows and their prices ]
; The field's reading of Ot6RuneListOpen.  The battle list asks the caster's
; battle Magic list ($302c) which elements she can cast; the field has no
; such list, so the menu asks its own Magic list's test of each spell
; (skills.asm _c350a2: Ot6FieldSpellKnown, and for a GOGO the seated
; party's union, as his field Magic list shows) and stages the answers at
; OT6_RPAGE_KNOWN.  From them, as the battle list packs its cells:
;   Runic, free;
;   a blade row for each element, in bit order, of which one of those
;     spells carries the bit (MagicProp+1), priced at the cheapest such
;     spell (MagicProp+5) through the character's Gold Hairpin or Economizer
;     as the field Magic list prices a spell ($11d7, which the Skills menu
;     set for this character: skills.asm _c3510d), six at most;
;   Break Blade at its 99 when it is learned (Ot6BreakLearned), and its
;     locked row when not.  The battle list has no cell for an unlearned
;     Break Blade and would give it to a seventh blade; no save can hold
;     seven elements before the Floating Continent.
; in: OT6_RPAGE_KNOWN.  out: OT6_RPAGE_ROW, OT6_RPAGE_COST; A = the rows
; (2-8).  any widths, any db.  Preserves X and Y.  rtl.
.proc Ot6RunePageRows
        php
        sep     #$20
        .a8
        rep     #$10
        .i16
        phb
        phx
        phy
        lda     #$7e
        pha
        plb
        ldx     #$0007
:       lda     #$ff
        sta     OT6_RPAGE_ROW,x
        stz     OT6_RPAGE_COST,x
        dex
        bpl     :-
        stz     OT6_RPAGE_ROW   ; Runic, free
        ldy     #$0001          ; y = the rows placed
        lda     #$00
@elem:  pha                     ; [1,s] the element
        cpy     #OT6_RPAGE_BLADES+1
        bcs     @full
        jsr     Ot6RunePageCheapest
        bcc     @next
        jsr     Ot6RunePageMP
        sta     OT6_RPAGE_COST,y
        lda     $01,s
        inc     a               ; OT6_RUNE_BLADE - OT6_RUNE_RUNIC
        sta     OT6_RPAGE_ROW,y
        iny
@next:  pla
        inc     a
        cmp     #$08
        bcc     @elem
        pha
@full:  pla
        jsl     Ot6BreakLearned
        bcc     @locked
        lda     #OT6_BREAK_MP
        sta     OT6_RPAGE_COST,y
        lda     #OT6_RUNE_BREAK - OT6_RUNE_RUNIC
        bra     @put
@locked:
        lda     #OT6_RPAGE_LOCKED
@put:   sta     OT6_RPAGE_ROW,y
        iny
        tya
        ply
        plx
        plb
        plp
        rtl
.endproc

; [ the cheapest spell of an element the field Magic list has ]
; in: A = the element's bit index.  out: carry set = there is one, A = its
; MagicProp price; clear = none.  a8/i16, db=$7e.  Preserves X and Y.
.proc Ot6RunePageCheapest
        .a8
        .i16
        phx
        phy
        longa
        and     #$0007
        tax
        shorta
        lda     f:Ot6RuneBitTbl,x
        pha                     ; the element's bit
        lda     #$ff
        pha                     ; [1,s] the cheapest so far, [2,s] the bit
        ldx     #$0000          ; x = the spell's MagicProp record
        ldy     #$0000          ; y = the spell
@spell: lda     OT6_RPAGE_KNOWN,y
        inc     a
        bne     @skip           ; not in the Magic list
        lda     f:MagicProp+1,x ; its elements
        and     $02,s
        beq     @skip
        lda     f:MagicProp+5,x ; its price
        cmp     $01,s
        bcs     @skip
        sta     $01,s
@skip:  longa
        txa
        clc
        adc     #14             ; MagicProp's stride
        tax
        shorta
        iny
        cpy     #OT6_RPAGE_SPELLS
        bcc     @spell
        pla                     ; the cheapest
        sta     $01,s           ; (over the bit)
        pla
        ply
        plx
        cmp     #$ff
        bne     @have
        clc
        rts
@have:  sec
        rts
.endproc

; [ a spell's price for the character whose Skills menu is open ]
; _c3510d's relic arithmetic (and Ot6SpellMP's, the battle's): an Economizer
; makes it 1 and beats the Gold Hairpin's half, rounded up.
; in: A = MagicProp's price.  out: A = the price.  a8, db=$7e.  Preserves X
; and Y.
.proc Ot6RunePageMP
        .a8
        pha
        lda     $11d7           ; relic effects 2 (UpdateEquip)
        bit     #$40
        bne     @econ
        bit     #$20
        beq     @plain
        pla
        inc     a
        lsr
        rts
@econ:  pla
        lda     #$01
        rts
@plain: pla
        rts
.endproc
