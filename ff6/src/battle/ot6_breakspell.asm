; ------------------------------------------------------------------------------
; OT6: the Break spell takes shields (#398)
;
; Vanilla Break ($0c) petrified one target.  OT6's Break deals no damage and
; sets no status; it takes shields off its one target, ignoring class and
; element: one, plus one per boost point (three points take four, the same
; ceiling as Quadra Slice or Bum Rush x4).  It reveals nothing (Filch's rule:
; a shield taken is not a weakness learned).  The record edits that turn the
; petrify roll off are MagicProp overrides 7-10 (battle_main.asm): no status,
; no instant-death flag, can't dodge.
;
; Who casts it, and what each cast buys:
;   * a character's Magic, X-Magic or a Mimic of one (Shoat, Terra's level-24
;     spell): 1 + the caster's pending boost.  Boost buys chips here, never a
;     tier and never the damage multiplier (Break is a row of Ot6FoldTbl that
;     folds to itself, so its MP stays 25 at every boost and Ot6BoostDmg
;     multiplies nothing);
;   * the Break Blade's on-hit cast (OT6_WEAPSPELL bit 6): 1.  The swing's
;     boost bought swings, not the spell it throws (owner ruling, v0.21);
;   * a Rage, Sketch or Control special: 1 (a Rage's boost bought the coin);
;   * a monster: 1, and against the party nothing (characters have no
;     shields).
; Nothing is taken from a Broken or shieldless body.  The last shield taken
; sets the break exactly as a chip does (OT6_BROKEN_TICKS and the pending
; flash), and Ot6ActionEnd's reveal backstop lands the flash, since the cast
; shows no numeral.
;
; jsl from CalcAttackEffect's per-target loop (@3440), before
; MagicStatusEffect, for every target the attack hit.  Power 0 never reaches
; CalcTargetDmg (its `lda $11a6 / jeq` gate), so the damage path's chip
; hooks cannot see Break; this is the per-target point that can.
; x = attacker, y = target (entity offsets), $b6 = the pass's attack id,
; db = $7e, any widths.  Preserves A, X, Y and P.  rtl.
; ------------------------------------------------------------------------------

.segment "ot6_code"

OT6_BREAK_SPELL = $0c

.proc Ot6BreakSpell
        php
        sep     #$20
        .a8
        pha
        lda     $b6
        cmp     #OT6_BREAK_SPELL
        bne     @out
        tya                     ; width-neutral target test
        cmp     #$08
        bcc     @out            ; a character: no shields
        jsr     Ot6BreakChips   ; A = shields this cast takes
        sta     OT6_SCR_BIT
@chip:  lda     OT6_BROKEN_TICKS,y
        bne     @out            ; Broken: nothing more to take
        lda     OT6_SHIELD_CUR,y
        beq     @out            ; shieldless
        dec     a
        sta     OT6_SHIELD_CUR,y
        bne     @more
        lda     #OT6_BREAK_TICKS
        sta     OT6_BROKEN_TICKS,y      ; shields down: Break
        lda     #$ff
        sta     OT6_BRKTICK-8,y         ; the flash, pending (Ot6BreakArm)
        bra     @out
@more:  dec     OT6_SCR_BIT
        bne     @chip
@out:   pla
        plp
        rtl
.endproc

; [ how many shields this Break takes: 1, plus the caster's boost ]
; a8, x = attacker.  out: A = 1..4.  preserves x/y.
.proc Ot6BreakChips
        .a8
        txa                     ; width-neutral character test
        cmp     #$08
        bcs     @one            ; a monster's cast
        lda     f:$7e0000+OT6_WEAPSPELL
        bit     #$40
        bne     @one            ; the Break Blade's own cast
        lda     $3a7c           ; the queued command
        cmp     #$02            ; Magic (a Mimic of it included)
        beq     @boost
        cmp     #$17            ; X-Magic
        bne     @one            ; Rage, Sketch, Control: the special alone
@boost: lda     OT6_BOOST_REVEALED,x
        cmp     #$04
        bcc     :+
        lda     #$03            ; (defensive: Ot6Boost caps the spend at 3)
:       inc     a
        rts
@one:   lda     #$01
        rts
.endproc
