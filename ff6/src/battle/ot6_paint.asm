; ------------------------------------------------------------------------------
; Relm's kit: the painter's list behind Sketch (#538)
;
; Design and the owner's rulings: docs/design/kit-relm.md.  Like Locke's list
; behind Steal (ot6_thief.asm) and Setzer's behind Slot (ot6_setzer.asm), the
; kit is a Tools-shell list behind the Sketch row, with Sketch as its first
; row, so no command slot is spent:
;   Sketch      vanilla Sketch
;   Portrait    an ally's next boosted action counts one point higher (the
;               gift); refuses a boost
;   Tint        a second list of the eight colours; the painted allies' weapon
;               attacks carry that element for OT6_TINT_TURNS of their turns
;   Varnish     the next enemy action that would land on the ally misses
;   Still Life  the body's break, this one or its next, lasts twice as long
;   Underpnt.   the next weakness hit on the body takes one more shield
;   Gesture     fills the ally's turn gauge: their turn comes up now
;   Mstrpiece   the divine: every other ally receives Portrait's gift
; The reach rows (Tint, Varnish, Still Life, Underpainting, Gesture) buy one
; more body a point, each body its own price (Ot6PerPointPrice).
;
; Anyone with the Sketch command opens it (a Gogo too, #547: each command he
; picks gives its owner's whole kit), with the rows Relm has learned.  The
; Fake Mustache's Sketch -> Control rewrite lands on command $0e, which keeps
; vanilla Control and no list, as a gloved Locke's Capture does.
;
; Command $0d's queued attack byte is free, as Steal's is: FixPlayerAttack has
; no $0d arm, $0d is not in CmdWithAttackTbl, and Cmd_0d overwrites $b6 with
; the sketched attack only after its own ExecAttack.  So each row queues its
; own id ($e8-$f7) and Cmd_0d's head dispatches on it (Ot6PaintExec).
; ------------------------------------------------------------------------------

OT6_PAINT_SKETCH   = $e8        ; vanilla Sketch
OT6_PAINT_PORTRAIT = $e9
OT6_PAINT_TINT     = $ea        ; opens the colour list; never queued
OT6_PAINT_VARNISH  = $eb
OT6_PAINT_STILL    = $ec
OT6_PAINT_UNDER    = $ed
OT6_PAINT_GESTURE  = $ee
OT6_PAINT_MASTER   = $ef        ; the divine
OT6_PAINT_COLOUR   = $f0        ; $f0-$f7: Tint in element bit (id - $f0)
OT6_PAINT_LAST     = $f7
OT6_PAINT_IDS      = OT6_PAINT_LAST - OT6_PAINT_SKETCH + 1

OT6_CHAR_RELM      = $08
OT6_CHAR_UMARO     = $0d
OT6_RELM_LEVEL     = $1600 + 37 * OT6_CHAR_RELM + 8     ; her record's level

OT6_TINT_TURNS     = 4          ; a Tint lasts four of the ally's turns
OT6_STILL_TICKS    = OT6_BREAK_TICKS    ; Still Life: a second whole break
OT6_MASTER_BOOST   = 3          ; the divine's one gate: a full boost
OT6_PAINT_ATTR     = $21 | (6 << 2)     ; the shield line's paint mark: green

; ------------------------------------------------------------------------------

; [ the eight rows: id, targeting, and how the row is learned ]
;
; Record: id, targeting byte, then either an event switch (byte offset from
; $1e80, bit; OT6_SW, ot6_thief.asm), or a level in the bit's place of zero
; (Relm's level, her character record's +8), or two zeros (at join).
;   Portrait   switch $02E8  her recruitment at Esper Mountain
;   Tint       level 18      she joins at 22, so she has it on joining
;   Varnish    level 24
;   Still Life switch $0240  Owzer's mansion, after Chadarnook
;   Underpnt.  level 36      her World of Ruin return (she rejoins at 36)
;   Gesture    level 42
;   Mstrpiece  switch $00BA  Strago's return at the Fanatics' Tower
; Each switch is set once by its beat and cleared by nothing, so a save past
; the beat has the row whatever version wrote it.  Targeting: $43 (MANUAL |
; ONE_SIDE | ENEMY, Sketch's own) for the enemy rows, $03 (MANUAL |
; ONE_SIDE) for the ally rows, $0a (ONE_SIDE | INIT_GROUP) for Masterpiece,
; whose cursor names the whole party.
OT6_PAINT_REC  = 4
OT6_PAINT_ROWS = 8
Ot6PaintRowTbl:
        .byte   OT6_PAINT_SKETCH,   $43, 0, 0
        .byte   OT6_PAINT_PORTRAIT, $03, OT6_SW($02e8)
        .byte   OT6_PAINT_TINT,     $03, 18, 0
        .byte   OT6_PAINT_VARNISH,  $03, 24, 0
        .byte   OT6_PAINT_STILL,    $43, OT6_SW($0240)
        .byte   OT6_PAINT_UNDER,    $43, 36, 0
        .byte   OT6_PAINT_GESTURE,  $03, 42, 0
        .byte   OT6_PAINT_MASTER,   $0a, OT6_SW($00ba)

; the base MP of each id, $e8-$f7 (the colours are Tint's)
Ot6PaintCostTbl:
        .byte   0, 12, 10, 14, 24, 28, 30, 99
        .byte   10, 10, 10, 10, 10, 10, 10, 10

; the list's names, ten letters each, $e8-$f7, in AttackName's encoding
Ot6PaintName:
        .byte   $92, $a4, $9e, $ad, $9c, $a1, $ff, $ff, $ff, $ff ; Sketch
        .byte   $8f, $a8, $ab, $ad, $ab, $9a, $a2, $ad, $ff, $ff ; Portrait
        .byte   $93, $a2, $a7, $ad, $ff, $ff, $ff, $ff, $ff, $ff ; Tint
        .byte   $95, $9a, $ab, $a7, $a2, $ac, $a1, $ff, $ff, $ff ; Varnish
        .byte   $92, $ad, $a2, $a5, $a5, $8b, $a2, $9f, $9e, $ff ; StillLife
        .byte   $94, $a7, $9d, $9e, $ab, $a9, $a7, $ad, $c5, $ff ; Underpnt.
        .byte   $86, $9e, $ac, $ad, $ae, $ab, $9e, $ff, $ff, $ff ; Gesture
        .byte   $8c, $ac, $ad, $ab, $a9, $a2, $9e, $9c, $9e, $ff ; Mstrpiece
        .byte   $85, $a2, $ab, $9e, $ff, $ff, $ff, $ff, $ff, $ff ; Fire
        .byte   $88, $9c, $9e, $ff, $ff, $ff, $ff, $ff, $ff, $ff ; Ice
        .byte   $81, $a8, $a5, $ad, $ff, $ff, $ff, $ff, $ff, $ff ; Bolt
        .byte   $8f, $a8, $a2, $ac, $a8, $a7, $ff, $ff, $ff, $ff ; Poison
        .byte   $96, $a2, $a7, $9d, $ff, $ff, $ff, $ff, $ff, $ff ; Wind
        .byte   $8f, $9e, $9a, $ab, $a5, $ff, $ff, $ff, $ff, $ff ; Pearl
        .byte   $84, $9a, $ab, $ad, $a1, $ff, $ff, $ff, $ff, $ff ; Earth
        .byte   $96, $9a, $ad, $9e, $ab, $ff, $ff, $ff, $ff, $ff ; Water

; the battle banner's names, 13 letters, $e8-$f7 (Sketch's is never shown)
OT6_PAINT_BANLEN = 13
Ot6PaintBanner:
        .byte   $92, $a4, $9e, $ad, $9c, $a1, $ff, $ff, $ff, $ff, $ff, $ff, $ff ; Sketch
        .byte   $8f, $a8, $ab, $ad, $ab, $9a, $a2, $ad, $ff, $ff, $ff, $ff, $ff ; Portrait
        .byte   $93, $a2, $a7, $ad, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff ; Tint
        .byte   $95, $9a, $ab, $a7, $a2, $ac, $a1, $ff, $ff, $ff, $ff, $ff, $ff ; Varnish
        .byte   $92, $ad, $a2, $a5, $a5, $fe, $8b, $a2, $9f, $9e, $ff, $ff, $ff ; Still Life
        .byte   $94, $a7, $9d, $9e, $ab, $a9, $9a, $a2, $a7, $ad, $a2, $a7, $a0 ; Underpainting
        .byte   $86, $9e, $ac, $ad, $ae, $ab, $9e, $ff, $ff, $ff, $ff, $ff, $ff ; Gesture
        .byte   $8c, $9a, $ac, $ad, $9e, $ab, $a9, $a2, $9e, $9c, $9e, $ff, $ff ; Masterpiece
        .byte   $85, $a2, $ab, $9e, $fe, $93, $a2, $a7, $ad, $ff, $ff, $ff, $ff ; Fire Tint
        .byte   $88, $9c, $9e, $fe, $93, $a2, $a7, $ad, $ff, $ff, $ff, $ff, $ff ; Ice Tint
        .byte   $81, $a8, $a5, $ad, $fe, $93, $a2, $a7, $ad, $ff, $ff, $ff, $ff ; Bolt Tint
        .byte   $8f, $a8, $a2, $ac, $a8, $a7, $fe, $93, $a2, $a7, $ad, $ff, $ff ; Poison Tint
        .byte   $96, $a2, $a7, $9d, $fe, $93, $a2, $a7, $ad, $ff, $ff, $ff, $ff ; Wind Tint
        .byte   $8f, $9e, $9a, $ab, $a5, $fe, $93, $a2, $a7, $ad, $ff, $ff, $ff ; Pearl Tint
        .byte   $84, $9a, $ab, $ad, $a1, $fe, $93, $a2, $a7, $ad, $ff, $ff, $ff ; Earth Tint
        .byte   $96, $9a, $ad, $9e, $ab, $fe, $93, $a2, $a7, $ad, $ff, $ff, $ff ; Water Tint


; ------------------------------------------------------------------------------

; [ has Relm learned this row? ]
; in: X = the row's record offset in Ot6PaintRowTbl.  out: carry set = known.
; a8/i16, db=$7e.  preserves X and Y; clobbers A.
.proc Ot6PaintRowKnown
        .a8
        .i16
        lda     f:Ot6PaintRowTbl+3,x
        beq     @level          ; no switch bit: a level, or at join
        phx
        pha                     ; [1,s] the switch's bit
        lda     f:Ot6PaintRowTbl+2,x
        longa
        and     #$00ff
        tax
        shorta0
        lda     $1e80,x         ; the switch's byte
        and     $01,s
        sta     $01,s
        pla                     ; the switch's bit, or 0
        plx                     ; (plx sets Z from X: test A again)
        cmp     #$00
        beq     @no
        sec
        rtl
@level: lda     f:Ot6PaintRowTbl+2,x
        beq     @yes            ; at join
        dec     a               ; level - 1 < Relm's: the level is hers
        cmp     OT6_RELM_LEVEL
        bcc     @yes
@no:    clc
        rtl
@yes:   sec
        rtl
.endproc

; [ is this id one of the list's rows past Sketch? ]
; in: A = the queued attack byte.  out: carry set (A preserved) for Portrait
; through the colours; clear for Sketch's $e8, the $ff of a Sketch nobody
; chose through the list, and anything else.  Preserves X and Y.
.proc Ot6PaintIsNew
        .a8
        cmp     #OT6_PAINT_PORTRAIT
        bcc     @no
        cmp     #OT6_PAINT_LAST+1
        bcs     @no
        sec
        rtl
@no:    clc
        rtl
.endproc

; does this id buy reach (one more body a point, each its own price)?
; in: A = id.  out: carry set = yes.  preserves A, X and Y.
.proc Ot6PaintReachRow
        .a8
        cmp     #OT6_PAINT_TINT
        bcc     @no             ; Sketch, Portrait
        cmp     #OT6_PAINT_MASTER
        beq     @no
        cmp     #OT6_PAINT_LAST+1
        bcs     @no
        sec
        rtl
@no:    clc
        rtl
.endproc

; [ a row's base price ]  in: A = id.  out: A = its base MP (0 for an id
; outside the list).  a8, either index width.  preserves X and Y.
.proc Ot6PaintBase
        .a8
        php
        rep     #$10
        .i16
        phx
        sec
        sbc     #OT6_PAINT_SKETCH
        cmp     #OT6_PAINT_IDS
        bcs     @none
        longa
        and     #$00ff
        tax
        shorta0
        lda     f:Ot6PaintCostTbl,x
        bra     @out
@none:  lda     #$00
@out:   plx
        plp
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ open Sketch as the painter's list, the twin of Ot6ThiefListOpen ]
; The learned rows, packed down the left column and then the right; the rest
; $ff (blank, unselectable).  Per row: Index = the id, Qty = the base price,
; Flags = the row's targeting byte.  Mode w7e6168 = 5.  No character test:
; whoever holds Sketch opens it (a Gogo too, #547), with Relm's rows.
; entry: jsl from the C1 stub, db=$7e, a8/i16.  clobbers a/x/y.
.proc Ot6PaintListOpen
        .a8
        .i16
        jsr     Ot6PaintPad
        ldx     #$0000
        lda     #0
        pha                     ; 1,s k, the rows placed
@row:   jsl     Ot6PaintRowKnown
        bcc     @next
        lda     1,s
        jsr     Ot6PaintCell    ; Y = the k-th packed cell's offset
        lda     1,s
        inc
        sta     1,s
        lda     f:Ot6PaintRowTbl,x
        sta     $4005,y
        jsl     Ot6PaintBase
        sta     $4006,y
        lda     f:Ot6PaintRowTbl+1,x
        sta     $4007,y
@next:  inx
        inx
        inx
        inx
        cpx     #OT6_PAINT_REC*OT6_PAINT_ROWS
        bcc     @row
        pla                     ; drop k
        ldy     $62ca
        jsl     Ot6ThiefClamp   ; the cursor on a listed row (any packed list)
        stz     $7ba5           ; force MakeToolsList_04 to re-init the window
        lda     #$04
        sta     $7b9e           ; the tools state machine's draw phase
        lda     #$05
        sta     $6168           ; w7e6168 = 5: the painter's list
        rtl
.endproc

; [ the eight colours, in the window the Tint row was picked in ]
; Called from Ot6KitConfirm when the Tint row is confirmed: the window's
; cells become Fire, Ice, Bolt, Poison down the left and Wind, Pearl, Earth,
; Water down the right (element bits 0-7, ids $f0-$f7), each at Tint's price,
; mode 6, the cursor on Fire, and the restage gate (Ot6RestageGate_ext)
; redraws the four lines in place, as it does when R moves a price, so the
; window never closes.  B leaves the window as from any list.
; a8, either index width, db=$7e.  clobbers a; preserves x and y.
.proc Ot6PaintColourOpen
        .a8
        php
        rep     #$10
        .i16
        phx
        phy
        jsr     Ot6PaintPad
        ldx     #$0000          ; x = the colour 0-7
@col:   txa
        jsr     Ot6PaintCell    ; y = its cell
        txa
        clc
        adc     #OT6_PAINT_COLOUR
        sta     $4005,y
        jsl     Ot6PaintBase
        sta     $4006,y
        lda     #$03            ; MANUAL | ONE_SIDE: an ally
        sta     $4007,y
        inx
        cpx     #$0008
        bcc     @col
        lda     #$06
        sta     $6168           ; w7e6168 = 6: the colours
        longa
        lda     $62ca
        and     #$0003
        tay
        shorta0
        sta     $8963,y         ; the cursor on Fire, the list unscrolled
        sta     $8967,y
        sta     $895f,y
        lda     #$80
        sta     f:$7e0000+OT6_RESTAGE   ; redraw the rows in place
        ply
        plx
        plp
        rtl
.endproc

; the eight cells $ff, Qty 0.  a8/i16.  clobbers a and x.
.proc Ot6PaintPad
        .a8
        .i16
        ldx     #$0000
@pad:   lda     #$ff
        sta     $4005,x
        stz     $4006,x
        inx
        inx
        inx
        cpx     #$0018
        bcc     @pad
        rts
.endproc

; the k-th packed cell, read down the columns: cell (k & 3) * 2 + k / 4.
; in: A = k (0-7).  out: Y = its wItemList offset (cell * 3).  a8/i16;
; preserves x; clobbers a.
.proc Ot6PaintCell
        .a8
        .i16
        pha                     ; [1,s] k
        and     #$03
        asl
        pha                     ; [1,s] (k & 3) * 2, [2,s] k
        lda     $02,s
        lsr
        lsr                     ; k / 4
        clc
        adc     $01,s           ; the cell
        sta     $01,s
        asl
        clc
        adc     $01,s           ; * 3
        sta     $02,s
        pla
        pla                     ; the offset
        longa
        and     #$00ff
        tay
        shorta0
        rts
.endproc

; ------------------------------------------------------------------------------

; [ the tools shell's confirm in modes 4 and up ]
; Setzer's table (4) and the painter's lists (5, 6).  in: A = the mode, X =
; the picked cell's wItemList offset, db=$7e, a8, either index width.  out:
; carry set = a kit row: target select (the thief arm); clear = the confirm
; did its own thing (the reels; the colours) and the menu stays put.
; preserves X and Y.
.proc Ot6KitConfirm
        .a8
        cmp     #$04
        bne     @paint
        jml     Ot6SetzerConfirm
@paint: cmp     #$05
        bne     @go             ; a colour: target select
        lda     $4005,x
        cmp     #OT6_PAINT_TINT
        bne     @go
        jsl     Ot6PaintColourOpen
        clc
        rtl
@go:    sec
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ the charge at the queue: Ot6AbilityCost's command $0d arm ]
; in: A = the queued id ($3a7b), X = the attacker.  out: A = the price.
; a8/i16, db=$7e.  preserves X and Y.
;   Sketch (and the $ff of an unlisted Sketch): 0, as Sketch always was;
;   Portrait: flat (it refuses the boost);
;   the reach rows: the base once per body, Ot6PerPointPrice;
;   Masterpiece: 99 at three points pending, else 0 (a divine taken back
;     does nothing and charges nothing, kits.md "Divines").
.proc Ot6PaintCharge
        .a8
        .i16
        jsl     Ot6PaintIsNew
        bcc     @free
        cmp     #OT6_PAINT_MASTER
        bne     @reach
        lda     OT6_BOOST_REVEALED,x
        cmp     #OT6_MASTER_BOOST
        bcc     @free
        lda     #OT6_PAINT_MASTER
        jml     Ot6PaintBase
@reach: jsl     Ot6PaintReachRow
        bcc     @flat
        jsl     Ot6PaintBase
        jml     Ot6PerPointPrice
@flat:  jml     Ot6PaintBase
@free:  lda     #$00
        rtl
.endproc

; [ a row's price as the window draws it: the charge's rule for the caster
;   whose window is open (Ot6KitRowCost's painter arms, and the confirm) ]
; in: A = id.  out: A = the price.  a8/i16.  preserves X and Y.
.proc Ot6PaintRowCost
        .a8
        .i16
        jsl     Ot6PaintReachRow
        bcc     @flat
        jsl     Ot6PaintBase
        jml     Ot6PendPerPoint
@flat:  jml     Ot6PaintBase    ; Masterpiece's 99 stands; its grey says
                                ;   when it cannot be had
.endproc

; [ the painter arm of Ot6BushidoRowGrey: a row its gate refuses ]
; Masterpiece under three points pending (the divine's one gate, Master's
; Mark's rule), and Gesture while the caster's own turn came from a Gesture
; (no Gesture off a Gestured turn: the loop limit).  Read by the row's colour
; and by the confirm (Ot6KitConfirmMP), so a greyed row is a refused one.
; a8/i16.  in: A = the MP grey, Y = the row's wItemList offset.
; out: A = A | ($04 if refused).  preserves X and Y.  rtl.
.proc Ot6PaintRowGrey
        .a8
        .i16
        pha                     ; [1,s] the MP grey
        phx
        lda     $62ca
        and     #$03
        asl
        longa
        and     #$00ff
        tax
        shorta0
        lda     $4005,y
        cmp     #OT6_PAINT_MASTER
        beq     @divine
        cmp     #OT6_PAINT_GESTURE
        bne     @white
        lda     f:Ot6CharBitTbl,x
        and     f:$7e0000+OT6_GESTURED
        bne     @grey
        bra     @white
@divine:
        lda     OT6_BOOST_REVEALED,x
        cmp     #OT6_MASTER_BOOST
        bcs     @white
@grey:  plx
        pla
        ora     #$04
        rtl
@white: plx
        pla
        rtl
.endproc

; [ R on the painter's list: Portrait buys nothing with a boost ]
; in: A = the row's id.  out: carry set = refuse.  preserves A, X and Y.
.proc Ot6PaintNoBoost
        .a8
        cmp     #OT6_PAINT_PORTRAIT
        beq     @none
        clc
        rtl
@none:  sec
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ a painter row's name, for Ot6KitListName ]
; in: A = id, Y = the line buffer offset, $56 = the attribute.  out: carry
; set = drawn (Y past the name); clear = not a painter row (A, Y unchanged).
; a8/i16, db=$7e.  preserves X.
.proc Ot6PaintListName
        .a8
        .i16
        pha                     ; [1,s] the id
        sec
        sbc     #OT6_PAINT_SKETCH
        cmp     #OT6_PAINT_IDS
        bcs     @no
        phx
        longa
        and     #$00ff
        pha
        asl
        asl
        clc
        adc     $01,s           ; * 5
        asl                     ; * 10
        tax
        pla
        shorta0
        lda     #10
        pha                     ; [1,s] letters left
@lp:    lda     $56
        xba
        lda     f:Ot6PaintName,x
        jsr     Ot6ListLetter
        inx
        lda     $01,s
        dec     a
        sta     $01,s
        bne     @lp
        pla
        plx
        pla
        sec
        rtl
@no:    pla
        clc
        rtl
.endproc

; [ attack name type 3 for a painter row: its banner ]
; The tail of Ot6ThiefBannerName for ids $e8 and up.  in: A = id, a8/i16,
; db=$7e.  Writes the name, $00-terminated, at w7e57d5.  clobbers a/x/y.
; rtl.
.proc Ot6PaintBannerName
        .a8
        .i16
        sec
        sbc     #OT6_PAINT_SKETCH
        ldy     #$0000
        cmp     #OT6_PAINT_IDS
        bcs     @end
        longa
        and     #$00ff
        tay
        lda     #$0000
@mul:   cpy     #$0000
        beq     @have
        clc
        adc     #OT6_PAINT_BANLEN
        dey
        bra     @mul
@have:  tax
        shorta0
@cp:    lda     f:Ot6PaintBanner,x
        cmp     #$ff
        beq     @end
        sta     $57d5,y
        inx
        iny
        cpy     #OT6_PAINT_BANLEN
        bne     @cp
@end:   lda     #$00
        sta     $57d5,y
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ run the painter row this Sketch action selected ]
;
; jsl from Cmd_0d after its `tyx` and `jsr _c2298a` (the action's props
; cleared, can't-dodge set), db=$7e, a8/i8.  x = y = the attacker, $b6 = the
; queued id, $b8/$b9 = the targets the menu chose.  out: carry set = handled
; (Cmd_0d runs ExecAttack with no special effect: the banner and the
; animation); clear = Sketch, vanilla (the Sketch row's id is put back to the
; $ff a vanilla Sketch queues).  Preserves x and y.
;
; Each row runs on its target, and the reach rows on one more body a point
; (Ot6PaintReach).  The bodies touched become the action's targets, so the
; animation lands on them; a row that touches nobody does nothing, keeps the
; boost (Ot6KeepBoost) and is charged no MP ($3a4c, the action's staged MP,
; which CalcAttackEffect charges later).  The banner is attack name type 3,
; named from Ot6PaintBanner.  A Mimic's copy runs the same way, free (no
; CreateAction priced it), with the copier's own boost.
.proc Ot6PaintExec
        .a8
        php
        shortai
        .a8
        .i8
        lda     $b6
        cmp     #OT6_PAINT_SKETCH
        bne     :+
        lda     #$ff
        sta     $b6             ; the Sketch row: vanilla's queued byte
        bra     @plain
:       jsl     Ot6PaintIsNew
        bcc     @plain
        cpx     #$08
        bcs     @plain          ; (a monster never queues these)
        phy
        rep     #$10
        .i16
        jsr     Ot6PaintRun
        sep     #$10
        .i8
        ply
        lda     #$03            ; attack name type 3 -> Ot6PaintBanner
        sta     $3412
        plp
        sec
        rtl
@plain: plp
        clc
        rtl
.endproc

; A caster who cannot pay the row's MP ($3c08 below $3a4c, the cost staged
; at action load) does nothing here: CalcAttackEffect's universal check
; refuses the cast after this and keeps the boost (Ot6FizzleDropBoost), so
; the row must not have landed first (#538 review: the effect ran unpaid).
; a8/i16, db=$7e, x = the attacker, A = the id.  clobbers a and y.
.proc Ot6PaintRun
        .a8
        .i16
        pha
        longa
        lda     $3c08,x         ; the caster's MP ...
        cmp     $3a4c           ; ... against the row's cost
        sep     #$20
        .a8
        pla
        bcc     @out            ; short: nothing done (the fizzle follows)
        sta     OT6_SCR_IDX     ; the id, for Ot6PaintFits/Apply
        stx     OT6_SCR_SLOT2   ; the caster (a word)
        cmp     #OT6_PAINT_MASTER
        beq     @master
        cmp     #OT6_PAINT_PORTRAIT
        bne     @gesture
        jsl     Ot6KeepBoost    ; Portrait refuses the boost: dropped, never
        lda     #1              ;   charged; one body
        bra     @walk
@gesture:
        cmp     #OT6_PAINT_GESTURE
        bne     @points
        lda     f:Ot6CharBitTbl,x       ; no Gesture off a Gestured turn (a
        and     OT6_GESTURED            ;   Mimic's copy included)
        bne     @refuse
@points:
        lda     OT6_BOOST_REVEALED,x
        and     #$03
        inc     a               ; the bodies: one, and one more a point
@walk:  jsr     Ot6PaintReach
        bra     @done
@master:
        lda     OT6_BOOST_REVEALED,x
        cmp     #OT6_MASTER_BOOST
        bcs     :+
        lda     #$00            ; under the full boost: nothing done,
        sta     OT6_BOOST_REVEALED,x    ;   nothing charged (priced 0 at
        bra     @nomp                   ;   the queue), as Master's Mark
:       jsr     Ot6Masterpiece
@done:  longa
        lda     $b8             ; did any body take it?
        sep     #$20
        .a8
        bne     @out
@refuse:
        jsl     Ot6KeepBoost    ; nobody: nothing done, nothing paid
@nomp:  stz     $3a4c
        stz     $3a4d
@out:   rts
.endproc

; [ Masterpiece: every other ally that can take a gift takes one ]
; a8/i16, db=$7e, x = the caster (OT6_SCR_SLOT2 too).  $b8/$b9 become the
; allies gifted.  clobbers a and y.
.proc Ot6Masterpiece
        .a8
        .i16
        stz     OT6_SCR_COLS
        stz     OT6_SCR_COLS+1
        ldy     #$0000
@ally:  longa
        lda     $3018,y
        and     $3a74           ; standing
        sep     #$20
        .a8
        beq     @next
        jsr     Ot6GiftFits
        bcc     @next
        jsr     Ot6GiftGive
        lda     $3018,y
        tsb     OT6_SCR_COLS
@next:  iny
        iny
        cpy     #$0008
        bcc     @ally
        longa
        lda     OT6_SCR_COLS
        sta     $b8
        shorta0
        rts
.endproc

; [ the bodies a row touches: its target, then one more a point ]
;
; The target the menu chose (the lowest bit of $b8, else of $b9) takes the
; row if it fits (Ot6PaintFits), else nobody does; from it, in battle order
; and wrapping within its side, each body the row fits takes the row
; (Ot6PaintApply) until A bodies have, or every seat of the side has been
; asked.  A point beyond the bodies left finds
; nobody and is spent, as a reach spell's is (#469).  $b8/$b9 become the
; bodies touched.  in: A = the bodies (1-4), OT6_SCR_IDX = the id,
; OT6_SCR_SLOT2 = the caster.  a8/i16, db=$7e, x = the caster.  clobbers a
; and y.
.proc Ot6PaintReach
        .a8
        .i16
        sta     OT6_SCR_BIT     ; the bodies left to place
        stz     OT6_SCR_COLS    ; the bodies touched (a word mask)
        stz     OT6_SCR_COLS+1
        ldy     #$0000
        lda     $b8
        bne     @find
        ldy     #$0008
        lda     $b9
        beq     @out            ; no target at all
@find:  lsr
        bcs     @first
        iny
        iny
        bra     @find
@first: phy                     ; [1,s] the first body
        jsr     Ot6PaintFits    ; the body named must take it, or nobody
        bcc     @done           ;   does (a point reaches from it, never
                                ;   past it to another)
@body:  jsr     Ot6PaintFits
        bcc     @skip
        jsr     Ot6PaintApply
        longa
        lda     $3018,y
        tsb     OT6_SCR_COLS
        sep     #$20
        .a8
        dec     OT6_SCR_BIT
        beq     @done
@skip:  iny
        iny
        lda     $01,s
        cmp     #$08
        bcs     @mside
        cpy     #$0008          ; characters wrap at 8
        bcc     @same
        ldy     #$0000
        bra     @same
@mside: cpy     #$0014          ; monsters wrap at $14
        bcc     @same
        ldy     #$0008
@same:  tya
        cmp     $01,s
        bne     @body           ; every seat asked once
@done:  ply
@out:   longa
        lda     OT6_SCR_COLS
        sta     $b8             ; the bodies touched are the targets
        shorta0
        rts
.endproc

; [ can row OT6_SCR_IDX take body y? ]  a8/i16, db=$7e, y = the body.
; out: carry set = yes.  preserves x and y; clobbers a.
;   a colour: any ally standing, the painter too;
;   Varnish: an ally standing without a coat (one a body);
;   Still Life, Underpainting: a monster standing that has shields and no
;     mark of the row yet;
;   Gesture: an ally standing, not the caster, who can take a turn now: not
;     asleep, stopped, frozen, removed, petrified or in the air, whose gauge
;     is not already full and who has no action queued (Gesture does not
;     reorder the queue);
;   Portrait, Masterpiece: Ot6GiftFits.
.proc Ot6PaintFits
        .a8
        .i16
        longa
        lda     $3018,y
        and     $3a74           ; standing (alive and in the fight)
        sep     #$20
        .a8
        beq     @no
        lda     OT6_SCR_IDX
        cmp     #OT6_PAINT_COLOUR
        bcs     @yes
        cmp     #OT6_PAINT_VARNISH
        beq     @varnish
        cmp     #OT6_PAINT_STILL
        beq     @still
        cmp     #OT6_PAINT_UNDER
        beq     @under
        cmp     #OT6_PAINT_GESTURE
        beq     @gesture
        cmp     #OT6_PAINT_PORTRAIT
        bne     @no
        jmp     Ot6GiftFits
@varnish:
        lda     $3018,y
        and     OT6_VARNISH
        bne     @no             ; one coat a body
@yes:   sec
        rts
@still: jsr     Ot6HitBit
        and     OT6_STILLMARK
        bra     @marked
@under: jsr     Ot6HitBit
        and     OT6_UNDERPAINT
@marked:
        bne     @no             ; one mark a body
        lda     OT6_SHIELD_MAX,y
        beq     @no             ; a body with no shields never breaks
        sec
        rts
@gesture:
        cpy     OT6_SCR_SLOT2
        beq     @no             ; not on herself
        lda     $3ee4,y
        and     #$c0
        bne     @no             ; wound, petrify
        lda     $3ee5,y
        bmi     @no             ; sleep
        lda     $3ef8,y
        and     #$10
        bne     @no             ; stop
        lda     $3ef9,y
        and     #$22
        bne     @no             ; freeze, removed (hide)
        lda     $3018,y
        and     $3f2c
        bne     @no             ; in the air (Jump)
        lda     $3219,y
        beq     @no             ; the gauge is full already
        lda     $32cc,y
        cmp     #$ff
        bne     @no             ; an action is queued
        sec
        rts
@no:    clc
        rts
.endproc

; [ can ally y take a gift? ]  not the caster (OT6_SCR_SLOT2), not Umaro
; (he never opens a window, and the engine drives his every turn), not
; wounded or petrified, and not holding one already (one gift a body).
; a8/i16, db=$7e.  out: carry.  preserves x and y; clobbers a.
.proc Ot6GiftFits
        .a8
        .i16
        cpy     OT6_SCR_SLOT2
        beq     @no
        lda     $3ed8,y         ; the character
        cmp     #OT6_CHAR_UMARO
        beq     @no
        lda     $3ee4,y
        and     #$c0
        bne     @no
        lda     $3018,y
        and     OT6_GIFT
        bne     @no
        sec
        rts
@no:    clc
        rts
.endproc

; [ row OT6_SCR_IDX takes body y ]  a8/i16, db=$7e.  preserves x and y;
; clobbers a.
.proc Ot6PaintApply
        .a8
        .i16
        lda     OT6_SCR_IDX
        cmp     #OT6_PAINT_COLOUR
        bcs     @tint
        cmp     #OT6_PAINT_VARNISH
        beq     @varnish
        cmp     #OT6_PAINT_STILL
        beq     @still
        cmp     #OT6_PAINT_UNDER
        beq     @under
        cmp     #OT6_PAINT_GESTURE
        beq     @gesture
        jmp     Ot6GiftGive     ; Portrait
@tint:  sec
        sbc     #OT6_PAINT_COLOUR
        phx
        longa
        and     #$0007
        tax
        shorta0
        lda     f:Ot6ElemBitTbl,x
        plx
        sta     OT6_TINTELEM,y  ; the colour (a second Tint repaints it)
        lda     #OT6_TINT_TURNS
        sta     OT6_TINT,y      ; and the turns start again (on Relm herself
                                ;   too: her casting action's end does not
                                ;   count one down -- measured, 4 turns held
                                ;   once it ended, battle_relmwor stage 8)
        rts
@varnish:
        lda     $3018,y
        tsb     OT6_VARNISH
        rts
@still: jsr     Ot6HitBit
        tsb     OT6_STILLMARK
        rts
@under: jsr     Ot6HitBit
        tsb     OT6_UNDERPAINT
        rts
@gesture:
        lda     #$ff            ; the gauge one tick from full: the next
        sta     $3218,y         ;   tick carries (actioncounter), and the
        sta     $3219,y         ;   window opens behind any already waiting
        lda     $3018,y
        tsb     OT6_GESTURED    ; this turn cannot Gesture
        rts
.endproc

Ot6ElemBitTbl:
        .byte   $01,$02,$04,$08,$10,$20,$40,$80

; [ ally y takes the gift: their next boosted action counts one point higher ]
; The gift is a mark (OT6_GIFT), spent by Ot6ActionEnd's charge (Ot6GiftSpend:
; the action is charged one point less).  So that it can be used without a
; banked point, the pending boost is raised by one now (up to three) and
; shows as an arrow, unless the ally's action is already committed (its
; boost is frozen: the gift takes a point off that action's charge if it
; was boosted, else the raise comes at its end, Ot6GiftRaise) or the engine
; is driving the ally (Muddle, Berserk: the gift waits, OT6_UNCTL).
; a8/i16, db=$7e, y = the ally.  preserves x and y; clobbers a.
.proc Ot6GiftGive
        .a8
        .i16
        lda     $3018,y
        tsb     OT6_GIFT
        and     OT6_UNCTL
        bne     @out
        lda     $3ef8,y
        lsr
        bcs     @out            ; dancing: the engine takes her turns, and
        lda     $3ef9,y         ;   raging his: the gift waits for a turn
        lsr                     ;   the player controls, as under Muddle
        bcs     @out            ;   (#538 review)
        tya
        lsr                     ; the character slot
        jsr     Ot6CommittedSlot
        bcs     @out
        lda     OT6_BOOST_REVEALED,y
        cmp     #$03
        bcs     @out
        inc     a
        sta     OT6_BOOST_REVEALED,y
        lda     $3204,y
        ora     #$80            ; vanilla's "recheck enabled magic": the
        sta     $3204,y         ;   ally's spell prices fold the raise
        jsr     Ot6BankMoved    ; an open kit window re-prices
@out:   rts
.endproc

; ------------------------------------------------------------------------------

; [ the gift at the charge: one point of the action is free ]
; jsr from Ot6ActionEnd's spend arm, with the pending boost (1 or more) in
; OT6_SCR_BIT.  A gifted actor's charge is one point less and the gift is
; spent, unless the engine drove the turn (OT6_UNCTL, a dance or a rage: the
; gift waits) or the action was Bestow, which hands only paid pips (the gift
; is not a pip): its pending holds the pips handed plus the gift's raise,
; and the raise is taken off the charge while the gift is kept.
; a8/i16, db=$7e, x = the actor.  preserves x and y; clobbers a.
.proc Ot6GiftSpend
        .a8
        .i16
        lda     f:Ot6CharBitTbl,x
        and     OT6_GIFT
        beq     @out
        lda     f:Ot6CharBitTbl,x
        and     OT6_UNCTL
        bne     @out
        lda     $3ef8,x
        lsr
        bcs     @out            ; a dance step or a raging turn: the gift
        lda     $3ef9,x         ;   waits
        lsr
        bcs     @out
        lda     $3a7c
        cmp     #$05            ; Steal's command, Bestow's row?
        bne     @take
        lda     $3a7d
        cmp     #OT6_THIEF_BESTOW
        beq     @raise          ; Bestow: the gift is kept, and its raise
                                ;   (on top of the pips handed, Ot6Bestow)
                                ;   is not charged
@take:  lda     f:Ot6CharBitTbl,x
        trb     OT6_GIFT
@raise: dec     OT6_SCR_BIT     ; the point the gift pays
@out:   rts
.endproc

; [ a gift still held is pending again for the next action ]
; jsr from Ot6PaintActionEnd.  a8/i16, db=$7e, x = the character.
; clobbers a.
.proc Ot6GiftRaise
        .a8
        .i16
        lda     f:Ot6CharBitTbl,x
        and     OT6_GIFT
        beq     @out
        lda     f:Ot6CharBitTbl,x
        and     OT6_UNCTL
        bne     @out
        lda     $3ef8,x
        lsr
        bcs     @out            ; dancing or raging: it waits
        lda     $3ef9,x
        lsr
        bcs     @out
        lda     OT6_BOOST_REVEALED,x
        bne     @out
        inc     a
        sta     OT6_BOOST_REVEALED,x
        lda     $3204,x
        ora     #$80
        sta     $3204,x
@out:   rts
.endproc

; [ the bank and the gift: what R may raise the pending boost to ]
; in: x = a character's entity offset, a8, either index width, any db.
; out: A = the bank, plus one while the gift is held.  preserves X and Y.
; rtl.
.proc Ot6BankGift
        .a8
        lda     f:Ot6CharBitTbl,x
        and     f:$7e0000+OT6_GIFT
        beq     :+
        lda     #$01
:       clc
        adc     f:$7e0000+OT6_BP_CLASS,x
        rtl
.endproc

; [ the pending points the action pays for: the pending, less the gift ]
; The boost display's spend (Ot6PipFace): a begun action shows its paid
; points gone from the pips, not the gift's.  in: x = the entity offset,
; a8/i16, any db.  out: A.  preserves X and Y.  rts.
.proc Ot6PaidPending
        .a8
        .i16
        lda     f:Ot6CharBitTbl,x
        and     f:$7e0000+OT6_GIFT
        beq     @all
        lda     f:Ot6CharBitTbl,x
        and     f:$7e0000+OT6_UNCTL
        bne     @all
        lda     f:$7e0000+$3ef8,x
        lsr
        bcs     @all            ; dancing or raging: the gift waits
        lda     f:$7e0000+$3ef9,x
        lsr
        bcs     @all
        lda     f:$7e0000+OT6_BOOST_REVEALED,x
        beq     :+
        dec     a
:       rts
@all:   lda     f:$7e0000+OT6_BOOST_REVEALED,x
        rts
.endproc

; [ the engine takes a gifted actor's turn: the gift waits ]
; jsl from Ot6UnctlMark for a character, a8, either index width, x = the
; actor.  A pending boost that is only the gift's raise goes back to 0, so
; an uncontrolled swing spends nothing of it.  preserves x and y; clobbers a.
.proc Ot6UnctlGift
        .a8
        lda     f:Ot6CharBitTbl,x
        and     f:$7e0000+OT6_GIFT
        beq     @out
        lda     f:$7e0000+OT6_BOOST_REVEALED,x
        cmp     #$01
        bne     @out
        lda     #$00
        sta     f:$7e0000+OT6_BOOST_REVEALED,x
@out:   rtl
.endproc

; ------------------------------------------------------------------------------

; [ the painter's marks at an action's end ]
; jsr from Ot6ActionEnd's last step, every actor.  A Varnish an enemy action
; spent stops that action's other hits only (OT6_VARNISHING); for a
; character, the Gesture mark ends with the granted turn, a Tint counts the
; turn, and a gift still held is pending again (Ot6GiftRaise).
; a8/i16, db=$7e, x = the actor.  preserves x and y; clobbers a.
.proc Ot6PaintActionEnd
        .a8
        .i16
        stz     OT6_VARNISHING
        txa
        cmp     #$08
        bcs     @out
        lda     f:Ot6CharBitTbl,x
        trb     OT6_GESTURED
        lda     OT6_TINT,x
        beq     :+
        dec     a
        sta     OT6_TINT,x
:       jsr     Ot6GiftRaise
@out:   rts
.endproc

; ------------------------------------------------------------------------------

; [ a Tinted ally's weapon carries the colour ]
; jsr from Ot6WeaponClass, right after _magicpunch banks the swinging hand's
; element in $11a1: Fight and its boosted swings, Mug and Capture, Jump.  The
; colour is OR'd in, so a weapon's own element stays and the hit carries
; both, and from here vanilla's rules apply to it: the weakness doubles the
; hit and chips a shield (Ot6Chip), and a body that absorbs or nulls the
; colour absorbs or nulls the hit, as it would a spell of it.
; a8/i16, x = the attacker's entity offset plus the hand.  preserves x, y.
.proc Ot6TintSwing
        .a8
        .i16
        txa
        cmp     #$08
        bcs     @out            ; a monster's swing
        phx
        longa
        txa
        and     #$0006          ; the character, either hand
        tax
        sep     #$20
        .a8
        lda     f:$7e0000+OT6_TINT,x
        beq     @none
        lda     f:$7e0000+OT6_TINTELEM,x
        ora     f:$7e11a1
        sta     f:$7e11a1
@none:  plx
@out:   rts
.endproc

; ------------------------------------------------------------------------------

; [ Varnish: the next enemy action that would land on the ally misses ]
;
; jsl from CheckHit's exit (@22e8, battle_main.asm), every path: the hits and
; the misses CheckHit judged.  The stack holds what CheckHit pushed at its
; head: its P at 4,s (carry set = a miss), and the attacker's X (low byte at
; 5,s), pushed at the caller's width; y = the target.  When the hit lands, a
; monster is the attacker and a varnished character the target, the coat is
; spent and the hit misses, through vanilla's own miss arm (@22d1's stores:
; the miss flag, the "Miss" target), and the rest of that action's hits on
; that body miss too (OT6_VARNISHING, cleared as each action begins,
; Ot6BpBegin).  A hit Image or evasion already turned aside never reaches
; here as a hit, and one that restores (the heal bit: a Runic ally's MP
; restore from the spell she absorbed) is let through, so neither spends
; the coat.  An ally's action never does.
; a8 or a16, either index width (CheckHit's), db=$7e.  preserves a/x/y.
.proc Ot6VarnishGate
        php                     ; [1,s] our P, [2..4,s] the return
        sep     #$20
        .a8
        pha                     ; [1,s] A, [2,s] P, [6,s] CheckHit's P,
                                ;   [7,s] the attacker
        lda     $06,s
        lsr
        bcs     @out            ; a miss already
        lda     $07,s
        cmp     #$08
        bcc     @out            ; a character's action
        lda     $11a4
        lsr
        bcs     @out            ; a hit that restores (the heal bit, $11a4
                                ;   bit 0): RunicEffect's MP restore on a
                                ;   Runic ally, with the monster still the
                                ;   attacker, is no attack to turn aside
        tya
        cmp     #$08
        bcs     @out            ; a monster's body
        lda     $3018,y
        and     f:$7e0000+OT6_VARNISHING
        bne     @miss           ; this action spent the coat on this body
        lda     $3018,y
        and     f:$7e0000+OT6_VARNISH
        beq     @out
        eor     f:$7e0000+OT6_VARNISH
        sta     f:$7e0000+OT6_VARNISH   ; the coat is spent
        lda     $3018,y
        ora     f:$7e0000+OT6_VARNISHING
        sta     f:$7e0000+OT6_VARNISHING
@miss:  lda     #$02            ; vanilla's miss arm (@22d1)
        tsb     $b2
        stz     $3a89
        lda     $341c
        beq     :+
        lda     $3018,y
        tsb     $3a5a           ; a character's bit: the word's low byte
:       lda     $06,s
        ora     #$01
        sta     $06,s           ; CheckHit returns carry set: a miss
@out:   pla
        plp
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ Still Life: a marked body's break lasts a second time over ]
; jsr from Ot6Tick when a body's break count reaches zero.  A body marked
; and not already held is held: the count starts again (OT6_STILL_TICKS),
; the mark goes and the held bit is set.  A held body recovers now and its
; held bit goes, so a mark laid during the extension waits for the next
; break: a break is lengthened once.  a8/i16, db=$7e, x = the body.
; out: carry set = held (the caller does not recover it).  preserves x/y.
.proc Ot6StillHold
        .a8
        .i16
        txa
        cmp     #$08
        bcc     @no
        phy
        txy
        jsr     Ot6HitBit       ; its slot bit
        ply
        pha                     ; [1,s] the bit
        and     OT6_STILLHELD
        bne     @release
        lda     $01,s
        and     OT6_STILLMARK
        beq     @plain
        trb     OT6_STILLMARK
        tsb     OT6_STILLHELD
        lda     #OT6_STILL_TICKS
        sta     OT6_BROKEN_TICKS,x
        pla
        sec
        rts
@release:
        trb     OT6_STILLHELD
@plain: pla
@no:    clc
        rts
.endproc

; [ Underpainting: the first weakness chip on a marked body takes one more ]
; jsr from Ot6Chip (beside Ot6Conductor) and Ot6ClassChip, right after the
; chip's own decrement.  in: A = the shields left, y = the body.  out: A =
; the shields left after the mark, the flags set from it.  a8, either index
; width.  preserves x and y.
.proc Ot6Underpaint
        .a8
        cmp     #$00
        beq     @out            ; the chip broke it: nothing more to take
        pha
        jsr     Ot6HitBit
        and     f:$7e0000+OT6_UNDERPAINT
        beq     @keep
        eor     f:$7e0000+OT6_UNDERPAINT
        sta     f:$7e0000+OT6_UNDERPAINT
        pla
        dec     a
        rts
@keep:  pla
@out:   rts
.endproc

; ------------------------------------------------------------------------------

; [ the shield line's paint marks (Ot6BgHudLine) ]
; Green ($21 | 6 << 2) where Relm has painted: the count tile while
; Underpainting waits on the body, the emblem while Still Life waits for its
; break, and the broken shield while Still Life holds the break or waits on
; the next.  a8/i16, db=$7e, y = the monster slot offset (0, 2, .. 10).
; out: A = the attribute.  preserves x and y; clobbers B.
.proc Ot6UnderAttr
        .a8
        .i16
        lda     OT6_UNDERPAINT
        jsr     Ot6SlotHas
        lda     #OT6_GAUGE_ATTR
        bcc     :+
        lda     #OT6_PAINT_ATTR
:       rts
.endproc

.proc Ot6StillAttr
        .a8
        .i16
        lda     OT6_STILLMARK
        jsr     Ot6SlotHas
        lda     #OT6_GAUGE_ATTR
        bcc     :+
        lda     #OT6_PAINT_ATTR
:       rts
.endproc

.proc Ot6StillBrokenAttr
        .a8
        .i16
        lda     OT6_STILLMARK
        ora     OT6_STILLHELD
        jsr     Ot6SlotHas
        lda     #OT6_BROKEN_ATTR
        bcc     :+
        lda     #OT6_PAINT_ATTR
:       rts
.endproc

; in: A = a monster mask, y = the slot offset.  out: carry set = the slot's
; bit is in it.  a8/i16.  preserves x and y; clobbers a and B.
.proc Ot6SlotHas
        .a8
        .i16
        cmp     #$00
        beq     @no             ; the common case: nothing painted
        phx
        pha
        longa
        tya
        lsr
        tax
        sep     #$20
        .a8
        lda     f:Ot6HitBitTbl,x
        and     $01,s
        beq     @none
        pla
        plx
        sec
        rts
@none:  pla
        plx
@no:    clc
        rts
.endproc
