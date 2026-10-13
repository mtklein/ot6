; ------------------------------------------------------------------------------
; OT6: Analyze, Strago's scouting row (#381)
;
; kits.md ("Strago"): Analyze is cheap and early, a full weakness reveal.
; It is the Scan spell ($18, 3 MP; Magic names hold six letters, so the
; game prints "Scan"):
;   * Strago always knows it.  Ot6EsperSpellKnown, Ot6UnionEspers and
;     Ot6FieldSpellKnown (ot6_progression.asm) grant it to him in battle and
;     in the field, as a stone grants its spells, so his Magic row is there
;     from the day he joins, with or without a stone.  CELES still learns it
;     at level 18 (vanilla's NaturalMagic), and a stone that lists it grants
;     it as before.
;   * A character's Scan reads its target: every weak element and every
;     weak class of the body goes onto the HUD at once and into the save's
;     codex for its species, as if each had been chipped (nothing is
;     chipped).  Vanilla's text still runs (TargetEffect_10, Cmd_27), and a
;     body vanilla will not scan ($3c80 bit 4) stays unread.
;   * The boost buys breadth (guidelines.md, "boost pays once"): with a
;     point or more pending, the cast reads every enemy on the field, not
;     only its target.  The price stays 3 MP; the pips are spent as on any
;     boosted turn (Ot6ActionEnd).
; The reveal goes through the pending bytes (OT6_RVPEND_*), so it lands
; with the same commit a chip's does (Ot6RevealCommit, which Ot6ActionEnd
; runs for an action with no numeral) on every slot of the species.  A
; weakness Debilitator added to one body is that body's, not the species'
; (ot6_debilitator.asm): it is left out of the pending byte and the codex.
; Inside the Fanatics' Tower the Magic row stays, so Scan does too (#420
; removes the kit rows, not Magic).
; ------------------------------------------------------------------------------

.segment "ot6_code"

OT6_ANALYZE_SPELL = $18         ; ATTACK::SCAN
OT6_CHAR_STRAGO   = $07

; jsl from CalcAttackEffect's per-target loop, beside Ot6BreakSpell: every
; target the attack hit.  x = attacker, y = target (entity offsets), $b6 =
; the pass's attack id, db = $7e, any widths.  Preserves A, X, Y and P.
.proc Ot6Analyze
        php
        sep     #$20
        .a8
        pha
        lda     $b6
        cmp     #OT6_ANALYZE_SPELL
        bne     @out
        txa                     ; width-neutral attacker test
        cmp     #$08
        bcs     @out            ; not a character's cast
        tya
        cmp     #$08
        bcc     @out            ; a character target: nothing to read
        rep     #$10            ; i16 for the codex; 8-bit index mode left
        .i16                    ;   the high bytes zero
        lda     OT6_BOOST_REVEALED,x    ; the caster's pending boost
        bne     @all
        jsr     Ot6AnalyzeOne   ; unboosted: the target alone
        bra     @out
@all:   phy
        ldy     #$0008          ; every monster slot, 8..18
@slot:  lda     $3aa0,y         ; present on the field? (entity offsets)
        lsr
        bcc     :+
        jsr     Ot6AnalyzeOne
:       iny
        iny
        cpy     #$0014
        bcc     @slot
        ply
@out:   pla
        plp
        rtl
.endproc

; [ read one body: its weaknesses, pending for the commit, and the codex ]
; a8/i16, y = monster entity offset, db = $7e.  preserves x/y; clobbers a.
.proc Ot6AnalyzeOne
        .a8
        .i16
        lda     $3c80,y
        bit     #$10
        bne     @done           ; vanilla's "can't be scanned"
        lda     OT6_DEBIL-8,y
        eor     #$ff
        and     $3be0,y         ; the body's weak elements, the species' own
        ora     OT6_RVPEND_ELEM-8,y
        sta     OT6_RVPEND_ELEM-8,y
        lda     OT6_BP_CLASS,y  ; the body's weak classes (monster half)
        ora     OT6_RVPEND_CLS-8,y
        sta     OT6_RVPEND_CLS-8,y
        ; learn it forever, as a chip does: codex = everything known so far
        phx
        lda     OT6_DEBIL-8,y
        eor     #$ff
        and     OT6_REVEALED_ELEM,y
        ora     OT6_RVPEND_ELEM-8,y
        pha                     ; elements
        lda     OT6_RVPEND_CLS-8,y
        ora     OT6_BOOST_REVEALED,y    ; revealed classes (monster half)
        pha                     ; classes
        jsr     Ot6CodexActive  ; x = this save's codex page
        longa
        txa
        clc
        adc     OT6_SPECIES-8,y
        tax
        shorta0
        pla
        sta     f:OT6_CODEX_CLASS,x
        pla
        sta     f:OT6_CODEX,x
        plx
@done:  rts
.endproc
