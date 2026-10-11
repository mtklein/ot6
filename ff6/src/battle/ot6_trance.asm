; ------------------------------------------------------------------------------
; OT6: Terra's Trance, the divine of her Morph (#378)
;
; kits.md: Trance is Terra's esper-state apex, and it is vanilla's Morph
; command: once Terra has awakened at Zozo (battle switch $42, which vanilla
; already reads to give her the Morph row, InitCmd_00), Morph sends her into
; her esper form, doubling her magic and halving the damage she takes for as
; long as the morph gauge lasts, all vanilla.  What OT6 adds is the divine's
; one gate, a full 3-BP boost (kits.md "Divines", owner 2026-10-11): no
; once-a-battle limit and no other condition.  Revert stays free.
;
; Two halves, one rule:
;   the menu   Ot6TranceOffer, from the C1 stub OpenCmdMenuTbl[$03] now
;              points at: Morph picked with fewer than three points pending
;              buzzes and leaves the command window up, so the turn and the
;              pips stay with the player (magic's refused-confirm shape);
;   the cast   Ot6TranceGate, at Cmd_03's head: a Morph whose boost was taken
;              back after the pick, or one the engine chose (Muddle,
;              Berserk), does not morph; the pending boost is dropped so
;              Ot6ActionEnd charges nothing for it.
; ------------------------------------------------------------------------------

.segment "ot6_code"

; [ the command window: may the active character pick Morph? ]
; jsl from the C1 stub, a8, either index width.  out: carry set = yes.
; clobbers A; preserves X and Y.
.proc Ot6TranceOffer
        .a8
        phx
        php
        rep     #$10
        .i16
        lda     f:$7e62ca       ; the active character's slot
        and     #$03
        asl
        longa
        and     #$00ff
        tax
        shorta
        lda     f:$7e0000+OT6_BOOST_REVEALED,x
        cmp     #$03            ; carry set iff a full boost is pending
        bcs     @yes
        plp
        plx
        clc
        rtl
@yes:   plp
        plx
        sec
        rtl
.endproc

; [ Cmd_03's head: does this Morph happen? ]
; jsl from Cmd_03, a8/i8, db = $7e, y = the attacker.  out: carry set = morph
; (vanilla runs on); carry clear = not, and the pending boost is dropped.
; clobbers A; preserves X and Y.
.proc Ot6TranceGate
        .a8
        tya                     ; width-neutral character test
        cmp     #$08
        bcs     @yes            ; (a monster never morphs; vanilla's business)
        lda     OT6_BOOST_REVEALED,y
        cmp     #$03
        bcs     @yes            ; a full boost: Trance
        lda     #$00
        sta     OT6_BOOST_REVEALED,y    ; nothing bought, nothing charged
        clc
        rtl
@yes:   sec
        rtl
.endproc
