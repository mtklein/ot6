; ------------------------------------------------------------------------------
; OT6: a boosted Magicite draws an esper the boost can pay for (#368)
;
; The Magicite item casts a random esper (AttackerEffect_49: RandGenju, 25
; espers, $36-$40 and $43-$50).  Its boost is the damage multiplier
; (Ot6BoostDmg, guidelines "boost pays once": everything else buys the
; multiplier), and half of the pool has nothing for it to multiply: twelve
; espers of power 0 (Siren, Shoat, Stray, Palidor, Ragnarok, Kirin, ZoneSeek,
; Carbunkl, Phantom, Golem, Unicorn, Fenrir) and Phoenix's revival, 0.520 of
; a draw (build/attempts/wt/procboost-magicite/summary.txt).  A boosted
; Magicite that drew one spent its pips and bought nothing.  And Crusader's
; Purifier strikes both sides (vanilla's record, byte for byte), so a boosted
; one multiplied onto the caster's own party: x8 is 9999 on every seat.
;
; So a boosted Magicite draws again until the esper is one the multiplier
; serves on the enemy or as healing: power above 0, not a revival, and, unless
; it heals, unable to reach the party.  Every draw is vanilla's RandGenju, on
; the battle RNG; an unboosted Magicite takes the first draw, whatever it is,
; exactly as vanilla does (Crusader included).  The rule reads MagicProp,
; so it follows the espers' records rather than a list; battle_magiciteboost
; decodes the same rule from the ROM and checks the draws.  RNGTbl is a
; permutation of 0-255, so 256 draws in a row reach every slot of the pool,
; and the pool holds payable espers (Ramuh, Ifrit, ...): the loop ends.
;
; jsl from AttackerEffect_49, right after each RandGenju.  a8/i8 there
; (DoAttackerEffect's shortai), y = the attacker.  in: A = the drawn esper's
; attack id.  out: A unchanged, y unchanged; carry set = draw again.
; ------------------------------------------------------------------------------

.segment "ot6_code"

.proc Ot6MagiciteKeep
        .a8
        php
        shorti                  ; 8-bit pushes, popped 8-bit below
        pha                     ; the draw, back to the caller in A
        phx
        phy
        longi
        tyx
        jsl     Ot6BoostLevel   ; the attacker's boost (x = its entity)
        beq     @keep           ; unboosted: vanilla's draw, whatever it is
        lda     $03,s           ; the drawn esper's attack id
        longa
        and     #$00ff
        pha                     ; parked at $01,s for the stride multiply
        asl3                    ; id * 8
        sec
        sbc     $01,s           ; id * 7
        asl                     ; id * 14 -- MagicProp's record stride
        tax
        pla
        shorta0
        lda     f:MagicProp+6,x ; power
        beq     @again          ; nothing to multiply
        lda     f:MagicProp+2,x
        bit     #$04
        bne     @again          ; a revival (Phoenix): nothing to multiply
        lda     f:MagicProp+4,x
        lsr
        bcs     @keep           ; heals: the multiplier is the heal
        lda     f:MagicProp+2,x
        bmi     @keep           ; "can't target characters": spares the party
        lda     f:MagicProp,x   ; targeting
        and     #$0c
        cmp     #$04
        beq     @again          ; both sides (Crusader): it would hit the party
        lda     f:MagicProp,x
        and     #$40
        bne     @keep           ; the enemy side
@again: shorti
        ply
        plx
        pla
        plp
        sec                     ; after plp, which restored the caller's carry
        rtl
@keep:  shorti
        ply
        plx
        pla
        plp
        clc
        rtl
.endproc
