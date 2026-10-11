; ------------------------------------------------------------------------------
; OT6: Debilitator adds a weakness and reveals it (#378)
;
; kits.md: Edgar's Debilitator adds a random weakness to its target and
; reveals it.  Vanilla's TargetEffect_56 already adds one element the body
; is not weak to (and clears it from the resist/absorb/null bytes), and
; the break system reads the weak byte live, so the added element is a chip
; trigger at once.  What it lacked was the reveal: the HUD drew the new
; weakness as '?' until an elemental hit on it chipped.  So the added bit is
; banked as a pending reveal (OT6_RVPEND_ELEM), which Ot6RevealCommit lands
; on the damage frame or at Ot6ActionEnd, the same path a chip's reveal
; takes, and the HUD draws its element glyph.
;
; It is recorded in OT6_DEBIL too, because the weakness belongs to this
; body for this battle, not to the species: Ot6Chip keeps those bits out of
; the codex, so the next battle with that species does not "remember" a
; weakness it never had.
;
; jsl from TargetEffect_56 right after the added bit is ORed into $3be0,y.
; in: A = the added element bit, y = the target's entity offset, a8, db=$7e,
; index width either.  clobbers A; preserves X and Y.
; ------------------------------------------------------------------------------

.segment "ot6_code"

.proc Ot6DebilReveal
        .a8
        pha
        tya                     ; width-neutral monster test
        cmp     #$08
        bcc     @out            ; a character (a Debilitator on the party)
        lda     $01,s
        ora     OT6_RVPEND_ELEM-8,y
        sta     OT6_RVPEND_ELEM-8,y
        lda     $01,s
        ora     OT6_DEBIL-8,y
        sta     OT6_DEBIL-8,y
@out:   pla
        rtl
.endproc
