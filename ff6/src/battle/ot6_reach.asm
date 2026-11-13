; ------------------------------------------------------------------------------
; OT6: reach -- one more body per boost point (#469)
;
; boost-rewards.md proposal 1.  Vanilla gave Haste and Slow a second tier
; that is the same status on every body (Haste2, Slow 2); the single-target
; statuses and cures whose line has no second spell take that move as their
; boost reward: a point covers one more body on the target's side, in battle
; order after the target and wrapping, passing over a body the spell cannot
; land on.  Three points cover a party of four.  The spells (Ot6ReachTbl):
; Safe, Shell, Rflect, Vanish, Bserk, Regen, Antdot, Remedy, Mute, Sleep,
; Muddle, Stop, Imp and Dispel.  Vanish reaches allies only: on an enemy it
; makes vanilla's death spells land, and a formation of it would rebuild the
; mass kill the divines own (Ot6QueueFold drops a boost raised for Vanish at
; a monster).  Doom and X-Zone are not here, for the same reason (Cleave).
; Each body pays its own cast: Ot6MagicPrice prices a reach spell at base x
; (1 + boost), Ot6PerPointPrice.
;
; Shadow's smoke and exit tricks (Ot6TrickReach, ot6_shadow.asm) were the
; first reach; both walk with Ot6ReachWalk below, so a thrown trick and a
; cast spell pass over the same bodies for the same reasons.
;
; A body the attack cannot land on (Ot6ReachLands): one not standing ($3a74);
; for a physical attack (a thrown trick), one under Vanish, which a physical
; hit misses; for a reflectable spell, one under Rflect, which would bounce
; it; and one on which none of the attack's statuses ($11aa-$11ad) would
; change: for a spell that sets them, a body that already holds each one or
; is immune to it (the allowed masks $331c/$331d/$3330/$3331 UpdateStatus
; reads); for one that lifts them ($11a4.2: Antdot, Remedy, Dispel), a body
; holding none of them.  A point beyond the bodies left finds nobody and is
; spent, as a Scan's boost is with one body standing.
; ------------------------------------------------------------------------------

.segment "ot6_code"

; the reach spells, $ff-terminated
Ot6ReachTbl:
        .byte   $1b,$1c,$1d,$1e ; Mute, Safe, Sleep, Muddle
        .byte   $20,$21,$23,$24 ; Stop, Bserk, Imp, Rflect
        .byte   $25,$26,$2c,$32 ; Shell, Vanish, Dispel, Antdot
        .byte   $33,$34         ; Remedy, Regen
        .byte   $ff

; [ is this spell a reach spell? ]
; in: A = spell id.  out: carry set = yes.  a8, either index width; preserves
; A, X and Y.  rtl.
.proc Ot6InReachTbl
        .a8
        php
        longi
        .i16
        phx
        ldx     #$0000
@scan:  pha
        lda     f:Ot6ReachTbl,x
        cmp     #$ff
        beq     @no
        cmp     $01,s
        beq     @yes
        pla
        inx
        bra     @scan
@yes:   pla
        plx
        plp
        sec
        rtl
@no:    pla
        plx
        plp
        clc
        rtl
.endproc

; [ can the attack land on this body? ]
; in: y = the body's entity offset (i16), the attack's props in $11a2-$11ad,
; db=$7e, a8.  out: carry set = it lands.  Preserves X and Y; clobbers A.
.proc Ot6ReachLands
        .a8
        .i16
        longa
        lda     $3018,y         ; this body's bit
        and     $3a74           ; standing (alive and in the fight)
        shorta
        beq     @no
        lda     $11a2
        lsr
        bcc     :+              ; a physical attack...
        lda     $3ee4,y
        bit     #$10            ;   ...misses a vanished body
        bne     @no
:       lda     $11a3
        bit     #$02
        bne     :+              ; a reflectable spell...
        lda     $3ef8,y         ;   ...bounces off a Rflect body
        bmi     @no
:       lda     $11a4
        and     #$04            ; lift (Antdot, Remedy, Dispel) or set
        bne     @lift
        lda     $3ee4,y         ; set: a status it does not hold and may take
        eor     #$ff
        and     $331c,y
        and     $11aa
        bne     @yes
        lda     $3ee5,y
        eor     #$ff
        and     $331d,y
        and     $11ab
        bne     @yes
        lda     $3ef8,y
        eor     #$ff
        and     $3330,y
        and     $11ac
        bne     @yes
        lda     $3ef9,y
        eor     #$ff
        and     $3331,y
        and     $11ad
        bne     @yes
@no:    clc
        rts
@lift:  lda     $3ee4,y         ; lift: a status it holds and may lose
        and     $331c,y
        and     $11aa
        bne     @yes
        lda     $3ee5,y
        and     $331d,y
        and     $11ab
        bne     @yes
        lda     $3ef8,y
        and     $3330,y
        and     $11ac
        bne     @yes
        lda     $3ef9,y
        and     $3331,y
        and     $11ad
        beq     @no
@yes:   sec
        rts
.endproc

; [ walk the target's side for the bodies a boost's points reach ]
; in: y = the first body (the target, or the thrower), A = the points (1-3),
; db=$7e, a8.  Adds each body reached to the target mask $b8/$b9 (a word:
; characters in $b8, monsters in $b9, $3018,y each one's bit).  The side is
; the first body's: characters 0-6, monsters 8-$12.  Writes OT6_SCR_BIT
; (scratch: the points left).  Preserves X and Y; clobbers A.  rtl.
.proc Ot6ReachWalk
        .a8
        php
        longi
        .i16
        phx
        phy                     ; [$01,s] the first body (low byte)
        sta     OT6_SCR_BIT     ; the points left to place
@next:  iny
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
        cmp     $01,s           ; back to the first body: every seat asked
        beq     @out
        jsr     Ot6ReachLands
        bcc     @next
        longa
        lda     $3018,y
        tsb     $b8             ; reached
        shorta
        dec     OT6_SCR_BIT
        bne     @next
@out:   ply
        plx
        plp
        rtl
.endproc

; [ a boosted reach spell covers more bodies ]
;
; jsl from CalcAttackEffect right after ChooseTarget, so the mask it widens is
; the one target the cursor (or a retarget) settled on, and everything after
; (the target count, CheckHit per body, the animation) sees the reach.
; Served: a character's Magic or X-Magic ($3a7c: a Mimic's copy is queued as
; the copied command and reads the copier's pending boost), not a counter
; ($b1.0, Ot6FightBoost's test: no Ot6ActionEnd charges a counter), the pass's
; attack ($b6) in Ot6ReachTbl, with a boost pending.  Vanish aimed at a
; monster reaches nobody.
;
; x = attacker, a16/i8 (CalcAttackEffect's), db=$7e.  Preserves A, X, Y, P.
.proc Ot6SpellReach
        php
        sep     #$20
        .a8
        pha
        txa                     ; width-neutral character test
        cmp     #$08
        bcs     @out
        lda     $b1
        lsr
        bcs     @out            ; a counterattack
        lda     $3a7c
        cmp     #$02            ; Magic
        beq     :+
        cmp     #$17            ; X-Magic
        bne     @out
:       lda     $b6
        jsl     Ot6InReachTbl
        bcc     @out
        lda     OT6_BOOST_REVEALED,x
        beq     @out            ; unboosted: the one body, vanilla
        phy
        php
        rep     #$10
        .i16
        ldy     #$0000          ; the target: a character...
        lda     $b8
        bne     @find
        lda     $b6
        cmp     #OT6_VANISH_SPELL
        beq     @done           ; (Vanish reaches allies only)
        ldy     #$0008          ; ...or a monster
        lda     $b9
        beq     @done           ; nobody targeted
@find:  lsr
        bcs     @have
        iny
        iny
        bra     @find
@have:  lda     OT6_BOOST_REVEALED,x
        cmp     #$04
        bcc     :+
        lda     #$03            ; (defensive: Ot6Boost caps the spend at 3)
:       jsl     Ot6ReachWalk
@done:  plp
        .i8
        ply
@out:   pla
        plp
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ a Sketch whose attack has no number drops its boost (#469) ]
;
; A sketched attack runs under its own command (_c21554: GetCmdForAI), so no
; spell queue ever judged it, and a boost raised for the Sketch bought the
; multiplier only when the attack the brush drew has a number.  One without
; (Ot6SpellNoBoost: no power, or a fraction) bought nothing: the pending boost
; is dropped here (Ot6KeepBoost), before Ot6ActionEnd charges it, the way a
; Mimic's copy that cannot use its boost keeps it.  The menu cannot refuse R
; for it: which of the monster's two sketches the brush draws is a roll.  The
; monster's plain attack and its physical Special ($ee, $ef) run as Fight and
; buy swings, so they keep the boost.
;
; jsl from Cmd_0d once the sketch has landed and its attack is in $b6.
; x = the sketcher, a8/i8, db=$7e.  A = $b6.  Preserves A, X and Y.
.proc Ot6SketchNoBoost
        .a8
        .i8
        pha
        cpx     #$08
        bcs     @out            ; a monster's (Control's) sketch
        cmp     #$ee
        bcs     @out            ; Battle, Special: Fight's swings
        jsl     Ot6SpellNoBoost
        bcc     @out
        jsl     Ot6KeepBoost
@out:   pla
        rtl
.endproc
