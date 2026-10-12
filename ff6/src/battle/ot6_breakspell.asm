; ------------------------------------------------------------------------------
; OT6: the Break spell takes shields (#398)
;
; Vanilla Break ($0c) petrified one target, and its MagicProp record is still
; vanilla's.  Who casts it decides which Break it is (the Life 3 precedent,
; magicite.md: a character's own casts get OT6's behaviour, everything else
; stays vanilla):
;   * OT6's Break -- a character's Magic, X-Magic or a Mimic of one (Shoat,
;     Terra's level-24 spell), or the Break Blade's on-hit cast
;     (OT6_WEAPSPELL bit 6).  It deals no damage and sets no status; it takes
;     shields off its one target, ignoring class and element.  A Magic or
;     X-Magic cast takes 1 + the caster's pending boost (three points take
;     four, the ceiling Quadra Slice or Bum Rush x4 has); boost buys chips
;     here, never a tier and never the damage multiplier (Break is in no
;     Ot6FoldTbl family, but Ot6InFoldTbl answers yes for it after the
;     table scan, so the boost leaves its MP at 25 and Ot6BoostDmg
;     multiplies nothing).  The Break Blade's cast takes 1: the swing's
;     boost bought swings, not the spell it throws (owner ruling, v0.21).
;     It reveals nothing (Filch's rule: a shield taken is not a weakness
;     learned).  On a party member it does nothing (characters carry no
;     shields).
;   * vanilla's Break -- a monster's cast, and Control, Sketch and a Rage,
;     which cast as the monster does: the petrify roll, untouched.
; Ot6BreakProps turns the loaded record into OT6's for an OT6 Break (see
; battle_main.asm's MagicProp notes for the four bytes); Ot6BreakSpell takes
; the shields.  Nothing is taken from a Broken or shieldless body.  The last
; shield taken sets the break exactly as a chip does (OT6_BROKEN_TICKS and the
; pending flash), and Ot6ActionEnd's reveal backstop lands the flash, since
; the cast shows no numeral.
; ------------------------------------------------------------------------------

.segment "ot6_code"

OT6_BREAK_SPELL = $0c

; [ is this pass OT6's Break? ]  a8, x = attacker.  carry set iff a
; character casts it through Magic or X-Magic (a Mimic included), or it is
; the Break Blade's on-hit cast.  Preserves x/y.
.proc Ot6BreakOurs
        .a8
        txa                     ; width-neutral character test
        cmp     #$08
        bcs     @no             ; a monster (Control's too): vanilla
        lda     f:$7e0000+OT6_WEAPSPELL
        bit     #$40
        bne     @yes            ; the Break Blade's own cast
        lda     $3a7c           ; the queued command
        cmp     #$02            ; Magic (a Mimic of it included)
        beq     @yes
        cmp     #$17            ; X-Magic
        beq     @yes
@no:    clc                     ; Sketch, Rage: the monster's Break
        rts
@yes:   sec
        rts
.endproc

; [ OT6's Break: the loaded record loses its petrify roll ]
; jsr from Ot6Life3Targeting (ot6_boost.asm), CalcAttackEffect's head, before
; ChooseTarget and CheckHit.  a8, x = attacker, $b6 = the pass's attack id.
; Clobbers A.
.proc Ot6BreakProps
        .a8
        lda     $b6
        cmp     #OT6_BREAK_SPELL
        bne     @out
        jsr     Ot6BreakOurs
        bcc     @out
        lda     $11a2
        and     #$fd            ; no instant-death flag
        sta     $11a2
        lda     $11a4
        and     #$ef            ; no stamina-evade death check,
        ora     #$20            ;   and can't dodge: a chip takes no hit roll
        sta     $11a4
        lda     $11a7
        and     #$fe            ; no auto-miss on a status-immune target
        sta     $11a7
        lda     $11aa
        and     #$bf            ; no Petrify
        sta     $11aa
@out:   rts
.endproc

; jsl from CalcAttackEffect's per-target loop (@3440), before
; MagicStatusEffect, for every target the attack hit.  Power 0 never reaches
; CalcTargetDmg (its `lda $11a6 / jeq` gate), so the damage path's chip hooks
; cannot see Break; this is the per-target point that can.  x = attacker,
; y = target (entity offsets), $b6 = the pass's attack id, db = $7e, any
; widths.  Preserves A, X, Y and P.  rtl.
.proc Ot6BreakSpell
        php
        sep     #$20
        .a8
        pha
        lda     $b6
        cmp     #OT6_BREAK_SPELL
        bne     @out
        jsr     Ot6BreakOurs
        bcc     @out            ; vanilla's Break: the petrify roll
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

; [ how many shields OT6's Break takes: 1, plus the caster's boost ]
; a8, x = attacker (a character: Ot6BreakOurs passed).  out: A = 1..4.
; preserves x/y.
.proc Ot6BreakChips
        .a8
        lda     f:$7e0000+OT6_WEAPSPELL
        bit     #$40
        bne     @one            ; the Break Blade's own cast
        lda     OT6_BOOST_REVEALED,x
        cmp     #$04
        bcc     :+
        lda     #$03            ; (defensive: Ot6Boost caps the spend at 3)
:       inc     a
        rts
@one:   lda     #$01
        rts
.endproc
