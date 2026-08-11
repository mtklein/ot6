; ------------------------------------------------------------------------------
; Divine abilities (kit slot 8): the resolution-time gates
;
; Ot6Oblivion (Cyan) and Ot6Assassinate (Shadow): the two divines whose gate
; cannot be read at command-select time, so they hook CalcAttackEffect instead.
; The select-time half of Oblivion is Ot6BushidoOblivion, in ot6_bushido.asm.
; ------------------------------------------------------------------------------
; Split out of ot6_kits.asm (v0.9, 3037 lines) with the emission order of
; every instruction preserved: ot6.asm includes these files in exactly the
; order their text sat in the old one, so the assembler receives the identical
; token stream and the linker the identical segment. ROM CRC32 0x2E9B5A7F and
; ff6-en.map are byte-identical across the split.
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
; action, and (per the counterattack audit, the $b1.0 convention this file keeps
; in Ot6BoostDmg/Ot6FightBoost/Ot6QueueFold) a countered action never reaches
; ActionEnd to charge, so the divines inherit that invariant through the
; commands they ride. This region is kept separate from the HUD-flush
; and sub-jobs regions.
; ------------------------------------------------------------------------------

; [ Oblivion (Cyan, Bushido tech 8): instant death iff the target is Broken ]
;
; kits.md: "Oblivion (divine) | 3, target must be Broken". The tech is vanilla
; swdtech 8, attack id $5c, which magic_prop already builds as a pure
; instant-death strike: power 0, Status-1 $80 (Death), the $11a2.1
; instant-death-spell flag, and $11a7.0 "auto-miss if the target is immune to
; the status". What it lacked was the Broken gate, and the survey that shipped
; Ot6BushidoTier left it out of the ladder because that gate cannot be read at
; command-latch time: swdtech is in RetargetCmdTbl (battle_main.asm:12810), which
; clears the target there; the target is then re-chosen at resolution.
;
; The gate is read at the one seam where the target exists and
; the attack's properties are still editable: immediately after ChooseTarget in
; CalcAttackEffect (battle_main.asm:8185), which fills $b8/$b9 for this attack.
; (An earlier draft hooked Cmd_07's first instruction and always read an empty
; target, because the retarget had cleared it and InitCmdTarget had not yet
; re-picked it, so every Oblivion folded; battle_divines' broken-kill drive
; caught it.)
; Here x is still the attacker (CalcAttackEffect indexes $3c08,x etc. right
; below), $3a7d is the resolved attack id, and the loaded MagicProp bytes
; ($11a6 power, $11aa Status-1, $11a2/$11a7 flags) are the ones the per-target
; loop about to run will consume.
;
;   Broken and killable  -> mark Death directly in the target's "status to set"
;                           ($3dd4, what SetStatus1 writes at :2254, applied by
;                           UpdateStatus :11067 for every present entity inde-
;                           pendent of the hit roll).  This is a guaranteed
;                           kill; the Break window is the guarantee, the same
;                           ruling Assassinate takes. Set the once-per-battle
;                           latch.
;   unbroken, OR a Broken
;   but death-immune boss -> the props are patched to a Tempest-like hit in
;                           place: power 70, Status-1 cleared (no Death), the
;                           instant-death-spell and auto-miss flags cleared. The
;                           per-target loop then lands a 70-power elementless
;                           slash, the "reduced" fallback (kits.md names
;                           fizzle-or-reduced). Keeping a real hit as the
;                           fallback is why Oblivion could rejoin
;                           the BP3 tier without retiring Tempest, and the latch
;                           stays clear (the divine was not spent), so the menu
;                           keeps offering Oblivion until it lands.
;
; The death-immune fold matters because a boss can be Broken too (bosses carry
; shields, DESIGN.md): without it, Oblivion against a Broken boss would spend
; the once-per-battle latch on a target Death cannot kill. Folding it to a
; Tempest hit spends the turn on damage and leaves the divine unspent.
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

; [ Assassinate (Shadow, divine): instant-kill a Broken non-boss ]
;
; kits.md sketch: "Shadow -- Assassin (piercing, thrown): Throw signature; ...
; divine Assassinate -- instant kill a Broken non-boss." The two gates the
; sketch names are the Broken check (OT6_BROKEN_TICKS nonzero) and the non-boss
; check ($3aa1 bit 2, the instant-death-protection bit a boss carries, the
; same one ScimitarEffect reads at battle_main.asm:9147). Both are read at the
; same seam Oblivion uses, after ChooseTarget in CalcAttackEffect where the
; target exists, so the kill is the same guaranteed $3dd4 Death mark
; (SetStatus1's byte, applied by UpdateStatus for every present entity regardless
; of the hit roll) and the once-per-battle gate is the shared OT6_DIVINE_USED
; bit. A Broken non-boss dies; a boss (Death cannot kill it) or an unbroken
; target is left alone, and the ordinary attack stands as the no-op fallback.
;
; UNDERSPECIFIED, reported rather than invented: the sketch does not say how
; Shadow invokes it (his Throw signature, a dedicated command, or a boost cost),
; and his kit is not built. This milestone ships the part that is specified (the
; two gates, the guaranteed kill, and the once-per-battle latch) gated on the
; attacker being Shadow (char id $03, $3ed8 keyed by the entity offset since
; offset = slot*2) with an unspent divine: any attack Shadow lands on a Broken
; non-boss assassinates it, once per battle. Narrowing it to
; Throw-only ($b5 == $08) or adding an arming cost is a one-line change to the
; gate below once his kit and its invocation are designed. It is dormant until
; then, because no Shadow is fielded, so the char-id gate never matches.
;
; entry: jsl from CalcAttackEffect just after ChooseTarget (beside Ot6Oblivion).
; a16/i8, db=$7e; x = attacker entity offset, $b8/$b9 = target mask. preserves
; x (the caller indexes it right after) and y.

.proc Ot6Assassinate
        php
        shortai
        .a8
        .i8
        cpx     #$08
        bcs     done            ; monster attacker: never
        lda     $3ed8,x         ; attacker char id (offset = slot*2)
        cmp     #$03            ; CHAR::SHADOW
        bne     done            ; not shadow: dormant
        lda     $3018,x
        and     OT6_DIVINE_USED
        bne     done            ; divine already spent this battle
        phx                     ; save attacker (i8, 1 byte)
        ; --- primary target -> entity offset. $b8 low = characters (bit c ->
        ;     offset c*2), $b9 high = monsters (bit m -> offset 8 + m*2). We want
        ;     an enemy, so scan the monster half only. ---
        ldx     #$08
        lda     $b9             ; monster mask (slots 0-5)
@mon:   lsr
        bcs     @have
        inx
        inx
        cpx     #$14
        bcc     @mon
        plx                     ; no monster target: bail
        bra     done
@have:  cpx     #$08
        bcc     @bail           ; a character target: not an enemy
        lda     OT6_BROKEN_TICKS,x         ; Broken?
        beq     @bail           ; no: ordinary attack
        lda     $3aa1,x
        bit     #$04            ; a boss (instant-death protected)?
        bne     @bail           ; yes: no-op fallback (Death cannot kill it)
        ; --- Broken non-boss: assassinate (guaranteed) + spend the divine ---
        lda     $3dd4,x
        ora     #$80            ; Death (status to set)
        sta     $3dd4,x
        plx                     ; x = attacker entity offset
        lda     $3018,x
        tsb     OT6_DIVINE_USED
        bra     done
@bail:  plx                     ; restore attacker; the attack stands untouched
done:   plp
        rtl
.endproc
