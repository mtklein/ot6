; ------------------------------------------------------------------------------
; Divine abilities (kit slot 8): the resolution-time gates
;
; Ot6Oblivion (Cyan) and Ot6Assassinate (Shadow): the two divines whose gate
; cannot be read at command-select time, so they hook CalcAttackEffect instead.
; The select-time half of Oblivion is Ot6BushidoOblivion, in ot6_bushido.asm.
; Assassinate's gate is also reached from Ot6HitJoin (ot6_break.asm), on the
; hit that breaks a body.
; ------------------------------------------------------------------------------

; ==============================================================================
; Divine abilities (kit slot 8): resolution-time gates + once-per-battle latch
;
; The kit-8 divines whose gates cannot be read at command-select time land here,
; gated at resolution, where the target exists. Each is once-per-battle
; through OT6_DIVINE_USED (per-character bit, $3ecb): the latch is read at select
; time (Ot6BushidoTier drops a spent Oblivion back to Tempest) and set when
; the divine lands. Every divine uses the boost economy the same way its kit
; does: BP is spent through Ot6ActionEnd like any boosted
; action, and a countered action never reaches ActionEnd to charge, so the
; divines inherit that invariant through the commands they ride.
; ------------------------------------------------------------------------------

; [ Oblivion (Cyan, Bushido tech 8): instant death iff the target is Broken ]
;
; The tech is vanilla swdtech 8, attack id $5c, which magic_prop already builds
; as a pure instant-death strike: power 0, Status-1 $80 (Death), the $11a2.1
; instant-death-spell flag, and $11a7.0 "auto-miss if the target is immune to
; the status". What it lacked was the Broken gate: that gate cannot be read at
; command-latch time, since swdtech is in RetargetCmdTbl
; (battle_main.asm:12810), which clears the target there; the target is then
; re-chosen at resolution.
;
; The gate is read at the one seam where the target exists and
; the attack's properties are still editable: immediately after ChooseTarget in
; CalcAttackEffect (battle_main.asm:8185), which fills $b8/$b9 for this attack.
; Here x is still the attacker (CalcAttackEffect indexes $3c08,x etc. right
; below), $3a7d is the resolved attack id, and the loaded MagicProp bytes
; ($11a6 power, $11aa Status-1, $11a2/$11a7 flags) are the ones the per-target
; loop about to run will consume.
;
;   Broken and killable  -> mark Death directly in the target's "status to set"
;                           ($3dd4, what SetStatus1 writes at :2254, applied by
;                           UpdateStatus :11067 for every present entity inde-
;                           pendent of the hit roll).  This is a guaranteed
;                           kill, the same ruling Assassinate takes. Set the
;                           once-per-battle latch.
;   unbroken, OR a Broken
;   but death-immune boss -> the props are patched to a Tempest-like hit in
;                           place: power 70, Status-1 cleared (no Death), the
;                           instant-death-spell and auto-miss flags cleared. The
;                           per-target loop then lands a 70-power elementless
;                           slash, the reduced fallback. Keeping a real hit as
;                           the fallback is why Oblivion could rejoin
;                           the BP3 tier without retiring Tempest, and the latch
;                           stays clear (the divine was not spent), so the menu
;                           keeps offering Oblivion until it lands.
;
; The death-immune fold matters because a boss can be Broken too: without it,
; Oblivion against a Broken boss would spend the once-per-battle latch on a
; target Death cannot kill. Folding it to a Tempest hit spends the turn on
; damage and leaves the divine unspent.
;
; entry: jsl from CalcAttackEffect just after ChooseTarget. a16/i8, db=$7e;
; x = attacker entity offset, $b8/$b9 = target mask, $3a7d = attack id. preserves
; x (the caller indexes it right after) and y; may edit $11a6/$11aa/$11a2/$11a7.

.proc Ot6Oblivion
        php
        shortai
        .a8
        .i8
        lda     $3a7d
        cmp     #$5c            ; oblivion's attack id?
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
        lda     OT6_BROKEN_TICKS,x         ; broken timer (nonzero = Broken)
        beq     @tempest        ; not broken: reduced fallback
        lda     $3aa1,x
        bit     #$04            ; Broken but death-immune (a boss)?
        bne     @tempest        ; ... Death cannot kill it: fall back
        ; --- Broken and killable: guaranteed kill + spend the divine ---
        lda     $3dd4,x
        ora     #$80            ; Death (status to set)
        sta     $3dd4,x
        plx                     ; x = attacker entity offset
        cpx     #$08
        bcs     done            ; (defensive: only characters own a divine)
        lda     $3018,x         ; attacker's entity bit ($01/$02/$04/$08)
        tsb     OT6_DIVINE_USED ; latch: divine spent this battle
        bra     done
@tempest:
        plx                     ; discard the saved attacker (unused on this arm)
        lda     #$46            ; Tempest power (70): the reduced fallback
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
; x = attacker, y = target, both entity offsets.  Shadow's hit on a Broken
; non-boss kills it: Death is marked in the target's "status to set" ($3dd4,
; SetStatus1's byte, applied by UpdateStatus at the tail of the same action
; for every present entity, whatever the hit roll) and the once-per-battle
; latch is spent.  Anything else leaves the attack as it was: an attacker
; who is not Shadow (char id $03, $3ed8 keyed by the entity offset since
; offset = slot*2), a divine already spent (OT6_DIVINE_USED, the attacker's
; $3018 bit), a character target, an unbroken target, or a boss ($3aa1 bit
; 2, the instant-death protection ScimitarEffect reads at
; battle_main.asm:9147; Death cannot kill it, so the latch is kept).
;
; Two callers, because of where a break is decided inside one action.
; Ot6HitJoin (ot6_break.asm) calls it for every landed hit, after both chip
; procs have run, so the hit that empties the last shield reads its own
; break here: the "shields down: break" store to OT6_BROKEN_TICKS (Ot6Chip,
; Ot6ClassChip) comes first, this gate next, then _c262ef's ApplyDmg takes
; the doubled hit off the HP and ExecAttack's UpdateStatus applies the
; Death.  The hit that breaks a non-boss is the kill (#239).  Ot6Assassinate
; below calls it from the ChooseTarget seam, before the hit roll, for a body
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
        lda     $3018,x         ; attacker's entity bit ($01/$02/$04/$08)
        and     OT6_DIVINE_USED
        bne     done            ; divine already spent this battle
        tya                     ; target entity offset, width-neutral test
        cmp     #$08
        bcc     done            ; a character target: not an enemy
        lda     OT6_BROKEN_TICKS,y
        beq     done            ; not Broken, this hit's chip included
        lda     $3aa1,y
        bit     #$04            ; a boss (instant-death protected)?
        bne     done            ; yes: Death cannot kill it, the latch is kept
        lda     $3dd4,y
        ora     #$80            ; Death (status to set)
        sta     $3dd4,y
        lda     $3018,x
        tsb     OT6_DIVINE_USED ; latch: divine spent this battle
done:   rts
.endproc

; [ Assassinate at the ChooseTarget seam: the primary monster target ]
;
; The seam Oblivion uses, after ChooseTarget in CalcAttackEffect, where the
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
