; ------------------------------------------------------------------------------
; OT6: Terra's Morph, and Trance, its divine (#378, #427)
;
; kits.md: Morph is vanilla's esper form (magic x2, damage taken halved),
; learned at the Zozo awakening (battle switch $42).  It is usable at any
; boost, and the boost buys its duration, once (guidelines "boost pays
; once"):
;   0-2 BP   a fixed span that grows with the boost (OT6_MORPH_SPEED);
;   3 BP     Trance, the divine: she stays morphed until the battle ends or
;            she reverts, vanilla's permanent morph (the Phunbaba battle's).
; Vanilla's cross-battle gauge ($1CF6: filled by magicite points, drained
; by each morph and saved between battles) no longer sets the duration or
; locks the command: battle_main.asm's RandMorph, UpdateCmd_00 and the
; morph's start no longer read it, and SaveMorphCounter is gone.  Revert
; stays free, so she can morph again in the same battle.
;
; Two halves:
;   Ot6MorphTake, at Cmd_03's head: keeps the boost this Morph was bought
;     with (OT6_MORPHBOOST), because her morph status lands in UpdateMorph
;     after Ot6ActionEnd has charged and cleared the pending byte.  A Morph
;     the engine chose (Muddle, Berserk, Charm, the Colosseum: OT6_UNCTL)
;     bought nothing; its pending byte is dropped and it takes the 0-BP span.
;     Mimic, Control and monsters never reach Cmd_03 as a character's Morph
;     (BattleCmdProp[$03] has neither GOGO nor MIMIC).
;   Ot6MorphSpan, in UpdateMorph where vanilla divided the counter speed out
;     of $1CF6: at 3 BP it leaves the morph unclocked (no morphed character
;     in $3EE2, no gauge), as vanilla's Phunbaba path does; under 3 it
;     starts the counter ($3F30 = $FFFF) at the span's speed ($3F32), which
;     DecMorphCounter subtracts once a battle tick (two frames of running
;     battle time) and shows as the gauge.  A span lasts 65536 / speed
;     ticks.
; ------------------------------------------------------------------------------

.segment "ot6_code"

; the counter's speed per boost, 0..2 BP: floor(65535 / speed) + 1 battle
; ticks each, 596, 800 and 993 (a tick is two frames of running battle
; time).  Set by measurement (kits.md, Terra): TERRA L26 acts about every
; 260 ticks, so 0 BP holds two of her turns after the one it cost, and an
; AtmaWeapon fight runs 2,100-3,200 ticks, so 2 BP is a third to a half of
; it.
OT6_MORPH_SPEED:
        .byte   110, 82, 66

; [ Cmd_03's head: keep the boost this Morph was bought with ]
; jsl from Cmd_03, a8/i8, db = $7e, y = the attacker.  clobbers A; preserves
; X, Y and carry is not an output.
.proc Ot6MorphTake
        .a8
        tya                     ; width-neutral character test
        cmp     #$08
        bcs     @out            ; (a monster never morphs; vanilla's business)
        lda     f:$7e0000+OT6_UNCTL
        and     $3018,y
        beq     @own            ; the player picked it
        lda     #$00
        sta     OT6_BOOST_REVEALED,y    ; the engine's pick buys nothing
@own:   lda     OT6_BOOST_REVEALED,y
        sta     OT6_MORPHBOOST
@out:   rtl
.endproc

; [ UpdateMorph: how long does this morph last? ]
; jsl from UpdateMorph's morph arm, a8, either index width, db = $7e,
; x = the morpher, no character morphed yet ($3EE2 negative).  out: carry set = a 3-BP Trance,
; which lasts the battle (nothing is clocked); carry clear = the morph is
; clocked: $3EE2 = x, $3F30 = $FFFF, $3F32 = the span's speed.
; clobbers A; preserves X and Y.
.proc Ot6MorphSpan
        .a8
        lda     OT6_MORPHBOOST
        cmp     #$03
        bcs     @out            ; a full boost: until the battle ends or she reverts
        php
        sep     #$10            ; (either index width at the call: x < $14)
        .i8
        stx     $3ee2           ; the morphed character
        phx
        tax
        lda     f:OT6_MORPH_SPEED,x
        sta     $3f32           ; the counter speed (a word)
        stz     $3f33
        lda     #$ff
        sta     $3f30           ; the counter starts full
        sta     $3f31
        plx
        plp
        .i16                    ; (the assembler's default again; plp restored the caller's)
        clc
@out:   rtl
.endproc

; [ Revert: an expired span's Revert is never dropped ]
; The span's end queues her Revert as a counterattack (DecMorphCounter's
; CreateRetalAction), and ExecRetal dropped a character's counterattack
; unexecuted while her $3aa0.4 or $3aa0.6 was set (the stretch from her own
; action's execution to her ATB gauge's restart).  A Revert dropped there
; was lost for good: $3EE2 was already cleared, so nothing clocked her
; again and the 0-BP span became the battle-long morph only a 3-BP Trance
; buys.  Measured on the battle_morphrandom stale arm (fc_alcove,
; wt/v029-shield-grants 770d5925 qual): `CreateRetalAction x=00 3A7A=04` at
; f27772 and no Cmd_04 after, $3aa0 reading $41 and $3EF9 bit 3 still set
; 230,000 frames on (build/attempts/wt/v029-shield-grants/morphrandom/).
; ExecRetal now runs a Revert ($b5 = $04) in that stretch instead of
; dropping it (battle_main.asm @4b9c's test): the span ends when the clock
; does, and she reverts at the next counterattack slot.  (Holding the clock
; at 0 until the stretch ended, the first cut, lengthened the 0-BP span to
; 701 ticks; build/attempts/wt/v029-shield-grants/qual-5e4e75a1.../.)

; [ Cmd_04's head: a Revert buys nothing, so it costs nothing (#430) ]
; Revert has no payoff a boost could buy (guidelines "boost pays once": a
; boost that costs pips and buys nothing is a bug), so a pending boost on it
; is dropped before Ot6ActionEnd can charge it: the turn ends as an
; unboosted one, regen pip included, and the magic rows fall back off any
; folded prices the raise put on them (the same request Ot6ActionEnd's spend
; arm makes).  Never a refund: nothing has been charged yet.  R on the
; command window raises a boost for whatever is picked next, so the boost
; is refused here, when the pick is Revert, rather than at the R press
; (Ot6KeepBoost's other no-reward rows, #463).
; jsl from Cmd_04, a8/i8, db = $7e, y = the actor (Cmd_03's context).
; clobbers A; preserves X and Y.
.proc Ot6RevertTake
        .a8
        tya                     ; width-neutral character test
        cmp     #$08
        bcs     @out            ; (a monster has no bank)
        lda     OT6_BOOST_REVEALED,y
        beq     @out            ; nothing raised: nothing to drop
        lda     #$00
        sta     OT6_BOOST_REVEALED,y
        lda     $3204,y
        ora     #$80            ; vanilla's "recheck enabled magic" request
        sta     $3204,y
@out:   rtl
.endproc
