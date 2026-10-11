; ------------------------------------------------------------------------------
; Divine abilities (kit slot 8): the resolution-time halves
;
; The owner's rule (2026-10-11, kits.md "Divines"): a divine's one gate is a
; full 3-BP boost, as in Octopath Traveler.  No once-a-battle limit, no
; Broken-target condition: a divine can be used again in the same battle
; whenever the bank holds three points.  Each divine's 3-BP test sits where
; its command already decides what the boost buys (Cyan's SwdTech window,
; Setzer's table, Ot6FoldSteps, Ot6RunicRaise, the Tools passes, the Morph
; gate); this file holds the two whose effect is decided where the target
; exists:
;   Ot6Oblivion     Cleave (Cyan), the SwdTech window's 3-BP row
;   Ot6Assassinate  Shadow's divine, on a hit of a 3-BP action
; BP is spent through Ot6ActionEnd like any boosted action.
; ------------------------------------------------------------------------------

; [ Cleave (Cyan, SwdTech tech 8): instant death, or the heaviest cut ]
;
; The tech is vanilla swdtech 8, attack id $5c, which magic_prop builds as a
; pure instant-death strike: power 0, Status-1 $80 (Death), the $11a2.1
; instant-death-spell flag, and $11a7.0 "auto-miss if the target is immune
; to the status".  It is reached only on the SwdTech window's 3-BP row
; (Ot6BushidoTech), so the boost has always been paid when this runs.
;
; The target is read at the one point where it exists and the attack's
; properties are still editable: immediately after ChooseTarget in
; CalcAttackEffect (battle_main.asm), which fills $b8/$b9 for this attack
; (swdtech is in RetargetCmdTbl, so the target is re-chosen here).
;
;   killable                -> mark Death directly in the target's "status to
;                              set" ($3dd4, applied by UpdateStatus for every
;                              present entity independent of the hit roll): a
;                              guaranteed kill.
;   death-immune (a boss)   -> the props are patched in place to the
;                              heaviest single cut a record can carry: power
;                              255, Status-1 cleared, the instant-death and
;                              auto-miss flags cleared.  The record ignores
;                              defence already ($11a2 $20).  A boss is the
;                              case a full boost must still pay for, and the
;                              old fallback (Quadra Slice's single 70) was
;                              less than the 2-BP Quadra Slice row lands.
;
; entry: jsl from CalcAttackEffect just after ChooseTarget. a16/i8, db=$7e;
; x = attacker entity offset, $b8/$b9 = target mask, $3a7d = attack id. preserves
; x (the caller indexes it right after) and y; may edit $11a6/$11aa/$11a2/$11a7.

OT6_CLEAVE_BOSS_POWER = 255

.proc Ot6Oblivion
        php
        shortai
        .a8
        .i8
        lda     $3a7d
        cmp     #$5c            ; cleave's attack id?
        bne     done            ; no: this attack is untouched
        phx                     ; save the attacker entity offset (i8, 1 byte)
        ; --- primary target -> entity offset. The mask is split: $b8 low byte
        ;     is characters (bit c -> offset c*2), $b9 high byte is monsters
        ;     (bit m -> offset 8 + m*2), not one flat 16-bit field. A swdtech
        ;     lands on an enemy, so try the monster half first. ---
        ldx     #$08
        lda     $b9             ; monster mask (slots 0-5)
@mon:   lsr
        bcs     @have
        inx
        inx
        cpx     #$14            ; 8 + 6*2
        bcc     @mon
        ldx     #$00
        lda     $b8             ; character mask (slots 0-3)
@chr:   lsr
        bcs     @have
        inx
        inx
        cpx     #$08
        bcc     @chr
        plx                     ; no target bit: restore attacker, bail
        bra     done
@have:  ; x = target entity offset
        lda     $3aa1,x
        bit     #$04            ; death-immune (a boss)?
        bne     @cut            ; ... Death cannot kill it: the heavy cut
        lda     $3dd4,x
        ora     #$80            ; Death (status to set): a guaranteed kill
        sta     $3dd4,x
        plx                     ; x = attacker entity offset
        bra     done
@cut:   plx
        lda     #OT6_CLEAVE_BOSS_POWER
        sta     $11a6
        stz     $11aa           ; clear Status-1 to inflict, so no Death $80
        lda     $11a2
        and     #$fd            ; clear the instant-death-spell flag (bit 1)
        sta     $11a2
        lda     $11a7
        and     #$fe            ; clear auto-miss-if-status-immune (bit 0)
        sta     $11a7
done:   plp
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ Assassinate (Shadow, divine): the gate and the kill ]
;
; x = attacker, y = target, both entity offsets.  A hit of Shadow's, on an
; action he boosted with all three points, kills a Broken non-boss: Death is
; marked in the target's "status to set" ($3dd4, SetStatus1's byte, applied
; by UpdateStatus at the tail of the same action for every present entity,
; whatever the hit roll).  The 3-BP boost is the divine's one gate (kits.md
; "Divines"); it can be used again in the same battle.  Anything else leaves
; the attack as it was: an attacker who is not Shadow (char id $03, $3ed8
; keyed by the entity offset since offset = slot*2), an action boosted by
; fewer than three points (OT6_BOOST_REVEALED, still pending until
; Ot6ActionEnd charges it), a character target, an unbroken target, or a
; boss ($3aa1 bit 2, the instant-death protection ScimitarEffect reads;
; Death cannot kill it).
;
; Two callers, because of where a break is decided inside one action.
; Ot6HitJoin (ot6_break.asm) calls it for every landed hit, after both chip
; procs have run, so the hit that empties the last shield reads its own
; break here: the "shields down: break" store to OT6_BROKEN_TICKS (Ot6Chip,
; Ot6ClassChip) comes first, this gate next, then _c262ef's ApplyDmg takes
; the doubled hit off the HP and ExecAttack's UpdateStatus applies the
; Death.  The hit that breaks a non-boss is the kill (#239).  Ot6Assassinate
; below calls it from the ChooseTarget hook point, before the hit roll, for a body
; already Broken when Shadow's attack resolves.
;
; a8; the index width is the caller's (Ot6HitJoin i16, Ot6Assassinate i8),
; so every index test goes through a and nothing compares an immediate
; against x or y.  db=$7e.  preserves x/y; clobbers a.

.proc Ot6AssassinateGate
        .a8
        txa                     ; attacker entity offset, width-neutral test
        cmp     #$08
        bcs     done            ; monster attacker: never
        lda     $3ed8,x         ; attacker char id
        cmp     #$03            ; CHAR::SHADOW
        bne     done            ; not shadow: dormant
        lda     OT6_BOOST_REVEALED,x
        cmp     #$03            ; the divine's one gate: a full 3-BP boost
        bcc     done            ;   on the action this hit belongs to
        tya                     ; target entity offset, width-neutral test
        cmp     #$08
        bcc     done            ; a character target: not an enemy
        lda     OT6_BROKEN_TICKS,y
        beq     done            ; not Broken, this hit's chip included
        lda     $3aa1,y
        bit     #$04            ; a boss (instant-death protected)?
        bne     done            ; yes: Death cannot kill it
        lda     $3dd4,y
        ora     #$80            ; Death (status to set)
        sta     $3dd4,y
done:   rts
.endproc

; [ Assassinate at the ChooseTarget hook point: the primary monster target ]
;
; The hook point Oblivion uses, after ChooseTarget in CalcAttackEffect, where the
; target mask exists and the hit has not rolled.  Resolves $b9's lowest
; monster bit to its entity offset and puts it to the gate above, so a body
; already Broken dies whatever the hit roll.  The hit that breaks a body
; reaches the gate from Ot6HitJoin instead.
;
; entry: jsl from CalcAttackEffect just after ChooseTarget (beside Ot6Oblivion).
; a16/i8, db=$7e; x = attacker entity offset, $b8/$b9 = target mask. preserves
; x (the caller indexes it right after) and y.

.proc Ot6Assassinate
        php
        shortai
        .a8
        .i8
        phy
        ; --- primary target -> entity offset. $b8 low = characters (bit c ->
        ;     offset c*2), $b9 high = monsters (bit m -> offset 8 + m*2). We want
        ;     an enemy, so scan the monster half only. ---
        ldy     #$08
        lda     $b9             ; monster mask (slots 0-5)
@mon:   lsr
        bcs     @have
        iny
        iny
        cpy     #$14
        bcc     @mon
        bra     done            ; no monster target: the attack stands
@have:  jsr     Ot6AssassinateGate
done:   ply
        plp
        rtl
.endproc
