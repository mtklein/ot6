; ------------------------------------------------------------------------------
; OT6: the endgame gear economy (#387) -- the Cursed Shield's count
;
; The Cursed Shield (ItemProp $66) becomes the Paladin Shield ($67) once 256
; battles are won with it worn: LearnItemMagic adds one to the battle
; variable $3EC0 (kept across battles as $1DD5) for each living wearer at
; every won battle, and the wrap to 0 lifts the curse.  OT6 halves random
; encounters (Ot6DangerMulW, 0.5x danger a step) and doubles their
; experience and gil to keep a step's worth vanilla (Ot6RewardMulW, random
; battles only); the curse's count is the same kind of thing, a reward for
; the walking, so it gets the same pair: a won random battle counts two, an
; event battle one.  The shield then takes the walking it took in vanilla,
; about 128 random battles worn (route-wor-colosseum.md section 5).
; ------------------------------------------------------------------------------

.segment "ot6_code"

; [ the Cursed Shield's count: two for a random battle, one for an event ]
; jsl from LearnItemMagic (battle_main.asm) in place of `cmp #$66 / bne @600c
; / inc $3ec0 / bne @600c`'s first three instructions; the caller keeps the
; `bne @600c`.  in: A = the equipped item.  out: Z set exactly when the count
; wrapped (the curse lifts: the caller's dispel path, which loads its own A);
; else Z clear and A the item as it came in.  a8, db=$7e; preserves x/y.
.proc Ot6CurseCount
        .a8
        cmp     #$66            ; ITEM::CURSED_SHLD
        bne     @plain          ; Z clear: another item
        pha
        lda     a:OT6_RANDBTL   ; a random battle (InitBP's flag)
        beq     @one
        lda     #$02
        bra     @add
@one:   lda     #$01
@add:   clc
        adc     $3ec0
        sta     $3ec0
        bcs     @wrap           ; past 255: the curse lifts
        pla                     ; A = $66: Z clear
        rtl
@wrap:  pla
        lda     #$00            ; Z set: the dispel path
        rtl
@plain: rtl
.endproc
