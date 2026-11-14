; ------------------------------------------------------------------------------
; OT6: Shadow's kit -- the smoke and exit tricks (#383)
;
; kits.md "Shadow": his eight skills are the eight throwing items, learned by
; acquisition as Edgar's Tools are, behind Throw, his signature; his divine is
; Assassinate (ot6_divine.asm).  Six of the eight deal damage and carry a key:
; the three stars by Ot6WeapClassTbl (pierce, thrown as weapons through
; CalcItemEffect), the Fire Skean, Water Edge and Bolt Edge by their element
; and, since #383, by Ot6SkillClassTbl (pierce: they resolve as the spells
; $51-$53, ThrowToolsOffsetTbl).  A boost multiplies all six (Ot6BoostDmg).
;
; The other two are the tricks, which deal no damage, so a multiplier bought
; nothing on them:
;   * the Shadow Edge, the smoke: Image (a double that turns physical hits
;     aside), CalcItemEffect @2ae9;
;   * the Inviz Edge, the exit: Vanish (physical hits miss), @2adc.
; Vanilla puts either on the thrower alone.  Here the boost buys reach: each
; point covers one more living ally, taken in battle order after the
; thrower (wrapping), so three points cover a party of four.  An ally the
; trick cannot land on is passed over for the next: one under Vanish (a
; thrown item is physical, and a physical hit misses a vanished body) or one
; already holding the trick's status (Ot6ReachWalk, ot6_reach.asm, the walk
; the reach spells share since #469).  A point beyond the allies left finds
; nobody and is spent, as a Scan's boost is with one body standing (DESIGN.md
; "Every boost buys something").  Any character who
; Throws a trick gets the reach, as any thrower gets the multiplier; a Mimic
; copy reads the copier's own pending, as the copied Jackpot does.
; *Reason: a smoke screen that hides the whole party is the assassin's way
; of covering a retreat, and a boost that buys targets is the one a status
; item can use.*
; ------------------------------------------------------------------------------

.segment "ot6_code"

; [ a trick's reach: one more living ally per boost point ]
; jsl from the non-spell item path (battle_main.asm, Cmd_01/Cmd_08's shared
; tail) in place of `lda #$04 / trb $b3`, after `$b8 &= $3a74 | $3a42` has
; kept the living targets and before ExecAttack.  A boosted trick also gets
; the targeting $0A ($bb), since ChooseTarget answers vanilla's $02 by
; putting the thrower alone back in $b8.  x = the actor's entity
; offset, a8, either index width, db=$7e.  $b5 is the command, $3411 the
; item (InitItemTarget).  Adds to $b8 (the target mask; characters are its
; low byte, $3018,y each one's bit).  Writes $b8, $bb (a
; boosted trick's targeting) and OT6_SCR_BIT ($3ECE, the points left: scratch).
; Preserves x and y.
.proc Ot6TrickReach
        .a8
        php
        longi
        .i16
        phx
        phy
        lda     $b5
        cmp     #$08            ; Throw
        bne     @out
        lda     $3411           ; the thrown item
        cmp     #ITEM::INVIZ_EDGE
        beq     @trick
        cmp     #ITEM::SHADOW_EDGE
        bne     @out
@trick: txa                     ; width-neutral: a character throws
        cmp     #$08
        bcs     @out
        lda     OT6_BOOST_REVEALED,x
        beq     @out            ; 0 BP: the thrower alone, vanilla
        pha
        lda     #$0a            ; the targeting: vanilla's $02 makes
        sta     $bb             ;   ChooseTarget put the thrower alone back
                                ;   in $b8 (@587e); $02|$08 (one side, the
                                ;   side's targets taken) keeps the mask
                                ;   this proc builds
        pla
        txy                     ; the walk starts after the thrower
        jsl     Ot6ReachWalk    ; (ot6_reach.asm, #469: the spells' reach
                                ;   walks the same way)
@out:   jmp     Ot6TrickReachOut
.endproc

; the tail, under its own name so battle_shadowkit can read the target mask
; the reach left ($b8) as it returns
.proc Ot6TrickReachOut
        .a8
        ply
        plx
        plp
        lda     #$04            ; the displaced instruction pair
        trb     $b3
        rtl
.endproc
