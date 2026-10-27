; ------------------------------------------------------------------------------
; OT6: Strago's blue Bserk (kits.md "Strago", magicite.md "Berserk")
;
; Strago learns by watching.  Lores are the attacks he learns that way; Bserk
; ($21, 16 MP, one target) is the one spell he learns the same way: the first
; battle in which a monster inflicts Berserk while he is present and able, he
; learns Bserk at the victory and keeps it, a Magic-row spell of his own.
;
;   * What counts: a monster's attack (the attacker is a monster, so Gau's
;     rage, a Muddled ally and a Siren wearer teach nothing) whose status set
;     carries Berserk ($11ab bit 4), and which neither removes nor toggles
;     status ($11a4 bits 2-3: Dispel takes Berserk off).  Lores are left to
;     vanilla's own path (Rippler and Pep Up name Berserk among the statuses
;     they swap or clear).  So: L.50 Magic's counter (Bserk itself, in the
;     Fanatics' Tower), Telstar's Megazerk, and the specials that berserk:
;     Insecare's Wing Whisp (Esper Mountain), CrassHoppr's Wing Snap,
;     WeedFeeder's Flap, Grenade's Mezmerize, Cactrot's Mind Sting, Woolly's
;     Frenzy; Evil Toot and Mind Blast, which carry it among others.
;   * Who sees it: vanilla's lore rule (LearnLore's own CheckStatus): Strago
;     in the battle and not dead, petrified, blind, a zombie, asleep,
;     muddled, berserk, stopped, frozen, raging or hidden when the attack
;     runs.  Whether it hits does not matter, as for a lore.
;   * When: at the victory, through vanilla's "learned" step: Ot6BlueLearn
;     marks the spell newly learned ($80) in his spell table and the battle-
;     end loop's ShowLearnedMagicMsg makes it $ff and prints "Strago learned
;     Bserk".  That loop visits the living only, so he learns it if he is
;     standing at the end; otherwise he must see it again.
;   * It is in his learned-spell table ($1a6e + 7 * $36 + $21), so the
;     Magic menus show it as they show TERRA's and CELES's natural spells,
;     and it rides the Magic row: it is his in the Fanatics' Tower, where
;     the Lore row is gone.
; LearnLore (battle_main.asm) runs Strago's eligibility before its lore test
; so that the watch below sees a non-lore attack with the same eyes.
; ------------------------------------------------------------------------------

.segment "ot6_code"

OT6_BLUE_SPELL   = $21          ; ATTACK::BSERK
OT6_BLUE_CELL    = $1a6e + $07 * $36 + OT6_BLUE_SPELL   ; STRAGO's Bserk learn byte

; jsl from LearnLore once Strago is known present and able.  x = attacker
; (entity offset), $b6 = the attack, db = $7e, a8; any index width.
; Preserves A, X, Y and P (LearnLore's lore test reads the carry it left).
.proc Ot6BlueWatch
        php
        sep     #$20
        .a8
        pha
        txa
        cmp     #$08
        bcc     @done           ; a character's action teaches nothing
        lda     $b6
        cmp     #$8b
        bcc     @spell
        cmp     #$a3
        bcc     @done           ; a lore: vanilla's own path
@spell: lda     $11a4
        and     #$0c            ; removes or toggles status (Dispel)
        bne     @done
        lda     $11ab
        and     #$10            ; STATUS2::BERSERK in the status it sets
        beq     @done
        lda     f:$7e0000+OT6_BLUE_CELL
        cmp     #$ff
        beq     @done           ; known already
        lda     #$01
        sta     f:$7e0000+OT6_BLUESEEN
@done:  pla
        plp
        rtl
.endproc

; jsl from the victory (battle_main.asm @5e0e), before the per-character
; learning loops.  db = $7e, any widths.  Preserves A, X, Y and P.
.proc Ot6BlueLearn
        php
        rep     #$30
        .a16
        .i16
        pha
        phx
        lda     f:$7e0000+OT6_BLUESEEN
        and     #$00ff
        beq     @done
        lda     $3007           ; Strago's slot ($ff: not in the battle)
        and     #$00ff
        cmp     #$0080
        bcs     @done
        tax
        sep     #$20
        .a8
        lda     $3018,x         ; his character mask
        and     $3a74           ; the living
        beq     @done           ; not standing: he sees it again first
        lda     f:$7e0000+OT6_BLUE_CELL
        cmp     #$ff
        beq     @done
        lda     #$80            ; newly learned: ShowLearnedMagicMsg says it
        sta     f:$7e0000+OT6_BLUE_CELL
@done:  rep     #$30
        .a16
        plx
        pla
        plp
        rtl
.endproc
