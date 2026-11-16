; ------------------------------------------------------------------------------
; OT6: dense ability lists in battle (#541)
;
; The owner's playthrough: "abilities like magic should pack more tightly in
; menus ... it looks like we're leaving space for spells we'll never learn.
; let's just pack them densely as learned."
;
; Vanilla builds each character's battle spell list ($208e + slot*$13c, four
; bytes a row: id, flags, targeting, MP) in the layout of the PARTY's union of
; known spells: row p+1 is master-list position p for every caster, and a row
; this caster cannot cast is $ff.  So a caster's Magic window shows the gaps
; of every spell a party member (or a worn stone) knows and he does not, and
; the window scrolls a fixed 27 rows whatever the union holds.  The Lore
; segment (rows 55..78) is laid out by lore id, so STRAGO's five-slot loadout
; spreads over 24 rows.
;
; Here each caster's list is packed after ValidateSpellList has decided what
; he can cast: the rows he can cast slide up in their order (vanilla's spell
; order, the Config "Magic Order", esper-lent spells in their places among
; them), and the tail is empty.  Every reader that indexes the list by row --
; the window draw, the confirm, UpdateEnabledMagic's grey, the boost price
; decorators (Ot6FoldPrices) and the R refusal (Ot6RowNoBoost), the fight
; driver's spellCell/loreCell -- sees the packed rows with no change.  The
; two readers that went from spell to row through the master pointer table
; ($3084) are GetMPCost (Ot6SpellRowPtr below) and Ot6FoldPrices (now walks
; rows and reads each row's own id).
;
; The windows then scroll only as far as the packed list reaches, and the
; cursor never rests past its last entry (Ot6ListClamp): the scroll cap, the
; cursor store after a move, the window open (a remembered cursor from an
; earlier battle can point past a shorter list) and the scroll bar each call
; in through a size-neutral splice in btlgfx (bank C1 has no room to grow).
; The Rage list was already packed (Ot6RageList) but kept vanilla's 128-row
; scroll; it shares the clamp.
;
; Nothing in the save changes: the learned-spell table ($1a6e) and the lore
; and rage bitfields are read exactly as before.
; ------------------------------------------------------------------------------

.segment "ot6_code"

; ------------------------------------------------------------------------------

; [ pack one caster's spell and lore rows (ValidateSpellList's tail) ]
;
; Replaces `lda $f6 / sta $3cf8,x` at ValidateSpellList's end.  x = the
; entity offset (0,2,4,6), any widths.  Rows 1..54 (spells) and 55..78
; (lores) are packed separately, each in place and in order; an emptied row
; is $ff,$ff,$ff,$00 (id $ff = nothing; MP 0, AddToSpellList_01's shape).
; The spell count goes to $3cf8,x, what vanilla stored there, now counted
; from the rows (vanilla's $f6 missed the esper- and item-granted spells,
; whose grant hook returns with carry set, so RandMagic, the one other
; reader, never drew them for a Muddled caster).  Preserves a/x/y and P.
.proc Ot6PackSpellList
        php
        rep     #$30            ; save all of a: vanilla left its high byte
        .a16                    ;   alone here, and its callers may lean on it
        .i16
        pha
        phx
        phy
        sep     #$20
        .a8
        rep     #$20
        .a16
        lda     $302c,x         ; the caster's list (row 0, the esper's)
        clc
        adc     #$0004          ; row 1
        tax                     ; x = where the next kept row goes
        tay                     ; y = the row being read
        sep     #$20
        .a8
        lda     #54
        jsr     PackRows        ; -> a = rows kept
        pha
        lda     4,s             ; the entity offset's low byte (phx pushed it
        rep     #$20            ;   under phy and the count)
        .a16
        and     #$00ff
        tax
        sep     #$20
        .a8
        pla
        sta     $3cf8,x         ; the number of spells this caster can cast
        tyx                     ; both cursors stand at row 55, the lores
        lda     #24
        jsr     PackRows
        rep     #$30
        .a16
        ply
        plx
        pla
        plp
        rtl
        .a8

; in: x = y = the first row, a = the row count; a8/i16.  out: a = the rows
; kept; x = y = one past the segment's last row.
PackRows:
        pha                     ; 2,s rows left to read
        lda     #0
        pha                     ; 1,s rows kept
@read:  lda     a:$0000,y
        cmp     #$ff
        beq     @skip           ; this caster cannot cast it: drop the row
        rep     #$20
        .a16
        lda     a:$0000,y
        sta     a:$0000,x
        lda     a:$0002,y
        sta     a:$0002,x
        sep     #$20
        .a8
        inx4
        lda     1,s
        inc
        sta     1,s
@skip:  iny4
        lda     2,s
        dec
        sta     2,s
        bne     @read
        phy                     ; 1,s (word) the segment's end
        rep     #$20
        .a16
@fill:  txa
        cmp     1,s
        bcs     @done
        lda     #$ffff          ; id $ff, flags $ff
        sta     a:$0000,x
        lda     #$00ff          ; targeting $ff, MP 0
        sta     a:$0002,x
        inx4
        bra     @fill
@done:  sep     #$20
        .a8
        ply                     ; the end (= x)
        lda     1,s             ; rows kept
        ply                     ; drop the two counter bytes
        txy
        rts
.endproc

; ------------------------------------------------------------------------------

; [ the row a caster's spell or lore sits on (GetMPCost) ]
;
; Replaces GetMPCost's `phx / tax / lda $3084,x / plx / cmp #$ff / beq
; @none / longa / asl2 / adc $302c,x / tax / shorta`: the master pointer
; table $3084 gives the UNION's row, and a packed list puts the caster's spell
; on his own row.  So a spell ($00-$35) is looked up among his rows 1..54 and
; a lore ($8b-$a2, stored as id - $8b) among rows 55..78; anything else (a
; summon: its pointer is 0, row 0) keeps the vanilla read.
;
; in: a8/i16, a = the attack id ($3a7b) with b = 0, x = the caster's entity
; offset.  out: carry clear and x = the row (a8, as vanilla's shorta left
; it), or carry set and a = $00ff (vanilla's not-in-list value; the caller's
; xba makes the cost 0).  Preserves y.
.proc Ot6SpellRowPtr
        .a8
        .i16
        cmp     #$36
        bcc     @spell
        cmp     #$8b
        bcc     @vanilla
        cmp     #$a3
        bcs     @vanilla
        sbc     #$8b - 1        ; carry clear here: subtracts $8b
        phy
        ldy     #$00dc          ; row 55
        pha
        lda     #24             ; ...24 rows
        bra     @scan
@spell: phy
        ldy     #$0004          ; row 1
        pha
        lda     #54             ; ...54 rows
@scan:  rep     #$20
        .a16
        and     #$00ff
        asl2
        pha                     ; 1,s (word) the segment's length in bytes
        tya
        clc
        adc     $302c,x
        tax                     ; x = the first row of the segment
        clc
        adc     1,s
        sta     1,s             ; 1,s = one past its last row; 3,s the id
        sep     #$20
        .a8
@row:   lda     a:$0000,x
        cmp     3,s
        beq     @hit
        inx4
        rep     #$20
        .a16
        txa
        cmp     1,s
        sep     #$20
        .a8
        bcc     @row
        pla                     ; not his: drop the end and the id
        pla
        pla
        ply
        bra     @none
@hit:   pla
        pla
        pla
        ply
        clc
        rtl
@vanilla:
        phx
        tax
        lda     $3084,x
        plx
        cmp     #$ff
        beq     @none
        rep     #$20
        .a16
        and     #$00ff
        asl2
        adc     $302c,x
        tax
        sep     #$20
        .a8
        clc
        rtl
@none:  rep     #$20
        .a16
        lda     #$00ff
        sep     #$20
        .a8
        sec
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ keep a battle list's scroll and cursor inside its packed entries ]
;
; A list here is one of three per-slot cursor triples btlgfx keeps (scroll,
; then +4 the column, +8 the row, one byte per slot) over a packed list of n
; entries in c columns, four rows on screen:
;
;   Magic  $8913  c = 2  n = $3cf8 + slot*2 (Ot6PackSpellList's count)
;   Lore   $891f  c = 1  n = the caster's packed lore rows (rows 55..78 up
;                        to the first empty one; Ot6PackSpellList)
;   Rage   $892b  c = 2  n = $3a9a (Ot6RageList's count)
;
; The scroll's top is max(0, ceil(n/c) - 4), where vanilla used a constant
; (27, 24 and 128 rows).  A cursor past the last entry moves to the last
; entry; the scroll never passes its top.  With n = 0 the cursor stays where
; it is (there is nothing to land on; vanilla's buzz answers the A press).
;
; in: a8/i16, x = the list's kind (0 magic, 2 lore, 4 rage), y = the slot.
; out: a = the scroll's top.  Clobbers x; preserves y.
OT6_LIST_MAGIC = 0
OT6_LIST_LORE  = 2
OT6_LIST_RAGE  = 4

.proc Ot6ListClamp
        .a8
        .i16
        phy
        rep     #$20
        .a16
        tya
        and     #$0003
        tay                     ; the slot, clean
        cpx     #OT6_LIST_LORE
        beq     @lore
        cpx     #OT6_LIST_RAGE
        beq     @rage
        asl                     ; magic: the entity offset
        phx
        tax
        sep     #$20
        .a8
        lda     $3cf8,x
        plx
        bra     @n
@lore:  asl                     ; lore: the caster's own packed lore rows
        phx                     ;   (55..78 of his list, Ot6PackSpellList),
        tax                     ;   counted to the first empty one, not
        lda     $302c,x         ;   $3a87's count for every caster (the
        clc                     ;   v0.46 review)
        adc     #55 * 4
        tax
        sep     #$20
        .a8
        lda     #0
@lcnt:  pha
        lda     a:$0000,x
        cmp     #$ff
        pla
        bcs     @lend           ; an empty row (id $ff): the end
        inc
        inx4
        cmp     #24
        bcc     @lcnt
@lend:  plx
        bra     @n
@rage:  sep     #$20
        lda     $3a9a
@n:     pha                     ; n
        lda     f:ColsTbl,x
        pha                     ; c
        cmp     #2
        lda     2,s             ; n
        bcc     @rows           ; one column: rows = n
        inc                     ; two: rows = ceil(n / 2)
        lsr
@rows:  sec
        sbc     #4
        bcs     @top
        lda     #0              ; fewer than four rows: no scroll
@top:   pha                     ; 1,s top, 2,s c, 3,s n
        rep     #$20
        .a16
        tya
        clc
        adc     f:ScrollTbl,x
        tax                     ; x = this slot's scroll cell
        sep     #$20
        .a8
        lda     a:$0000,x
        cmp     1,s
        bcc     :+
        lda     1,s
        sta     a:$0000,x       ; the scroll at most the top
:       lda     3,s
        beq     @done           ; nothing listed: leave the cursor be
        lda     a:$0000,x
        clc
        adc     a:$0008,x       ; the cursor's absolute row
        pha                     ; 1,s row, 2,s top, 3,s c, 4,s n
        lda     3,s
        cmp     #2
        lda     1,s
        bcc     :+
        asl                     ; two columns: row * 2 + column
        clc
        adc     a:$0004,x
:       cmp     4,s
        bcc     @fine           ; on an entry
        lda     4,s
        dec                     ; the last entry
        pha                     ; 1,s idx, 2,s row, 3,s top, 4,s c, 5,s n
        lda     4,s
        cmp     #2
        lda     1,s
        bcc     @one
        and     #$01
        sta     a:$0004,x       ; its column
        lda     1,s
        lsr                     ; its absolute row
        bra     @row
@one:   lda     #0
        sta     a:$0004,x
        lda     1,s
@row:   sec
        sbc     a:$0000,x       ; - scroll
        bcs     :+
        clc                     ; (above the window: scroll to it)
        adc     a:$0000,x
        sta     a:$0000,x
        lda     #0
:       sta     a:$0008,x       ; its row in the window
        pla
@fine:  pla
@done:  pla                     ; the top
        plx                     ; drop c and n
        ply
        rep     #$20            ; b = 0: btlgfx's `tax` after these splices
        .a16                    ;   moves all of a (_c18414: `lda w7e62ca /
        and     #$00ff          ;   asl / tax`), and vanilla left b clear
        sep     #$20
        .a8
        rts

ColsTbl:
        .word   2, 1, 2
ScrollTbl:
        .word   $8913, $891f, $892b
.endproc

; the btlgfx splices, one set per list.  btlgfx runs a8/i16 with db = $7e
; (its own `lda w7e8913,y` reads), so the cells are read as absolutes.
.macro ot6_dense_list name, kind, scroll
; `lda scroll,y / cmp #top`: a = the scroll, z = at the top.  y = the slot.
.proc .ident(.concat("Ot6Dense", name, "AtTop"))
        .a8
        .i16
        phx
        ldx     #kind
        jsr     Ot6ListClamp
        plx
        cmp     scroll,y        ; top = scroll?
        php
        lda     scroll,y
        plp
        rtl
.endproc
; `lda $36 / sta scroll+4,y / lda $37 / sta scroll+8,y`, then the clamp.
.proc .ident(.concat("Ot6Dense", name, "Store"))
        .a8
        .i16
        phx
        lda     $36
        sta     scroll+4,y
        lda     $37
        sta     scroll+8,y
        ldx     #kind
        jsr     Ot6ListClamp
        plx
        rtl
.endproc
; `ldx w7e62ca / lda scroll,x` at the window's open, clamped first.
.proc .ident(.concat("Ot6Dense", name, "Open"))
        .a8
        .i16
        phy
        ldy     $62ca
        ldx     #kind
        jsr     Ot6ListClamp
        ply
        ldx     $62ca
        lda     scroll,x
        rtl
.endproc
; `lda #top / sta $36 / ldx #step / stx $2e` before the scroll bar's draw:
; $36 = the top, $2e = 36 pixels of travel / top (vanilla's 36 at its own
; top), carry set when the list does not scroll (no bar).  y = the slot.
.proc .ident(.concat("Ot6Dense", name, "Bar"))
        .a8
        .i16
        phx
        ldx     #kind
        jsr     Ot6ListClamp
        plx
        jmp     Ot6ListBar
.endproc
.endmacro

ot6_dense_list "Magic", OT6_LIST_MAGIC, $8913
ot6_dense_list "Lore",  OT6_LIST_LORE,  $891f
ot6_dense_list "Rage",  OT6_LIST_RAGE,  $892b

; OpenMagicWindow's head (`lda #$0d / sta w7e7bc2`), then the Magic clamp for
; the active slot, so a remembered cursor past the packed list's end is moved
; onto it before _c18414 reads its row's MP (the v0.46 review: the row read
; for one frame was an empty one).  a8/i16, db = $7e.  Clobbers a and x;
; preserves y.
.proc Ot6DenseMagicPre
        .a8
        .i16
        lda     #$0d
        sta     $7bc2
        phy
        ldy     $62ca
        ldx     #OT6_LIST_MAGIC
        jsr     Ot6ListClamp
        ply
        rtl
.endproc

; in: a = the top.  out as the Bar entries above.  Preserves x and y.
.proc Ot6ListBar
        .a8
        .i16
        cmp     #0
        bne     :+
        sec                     ; no scroll: no bar (b is 0: Ot6ListClamp)
        rtl
:       sta     $36
        rep     #$20
        .a16
        lda     #36 * 256
        sta     f:hWRDIVL
        sep     #$20
        .a8
        lda     $36
        sta     f:hWRDIVB       ; (the divisor write starts the division)
        nop4
        nop4
        rep     #$20
        .a16
        lda     f:hRDDIVL
        sta     $2e
        lda     #$0000          ; b = 0 (Ot6ListClamp's note)
        sep     #$20
        .a8
        lda     $36
        clc
        rtl
.endproc
