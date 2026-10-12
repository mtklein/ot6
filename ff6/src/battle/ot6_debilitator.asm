; ------------------------------------------------------------------------------
; OT6: Debilitator adds a weakness and reveals it (#378)
;
; kits.md: Edgar's Debilitator adds a random weakness to its target and
; reveals it.  Vanilla's TargetEffect_56 already adds one element the body
; is not weak to (and clears it from the resist/absorb/null bytes), and
; the break system reads the weak byte live, so the added element is a chip
; trigger at once.  What it lacked was the reveal: the HUD drew the new
; weakness as '?' until an elemental hit on it chipped.  So the added bit is
; set straight in this body's own revealed byte (OT6_REVEALED_ELEM), and the
; HUD draws its element glyph.  Not through the pending reveal
; (OT6_RVPEND_ELEM): Ot6RevealCommit copies a pending bit to every slot of
; the same species, which is right for a weakness the species has and wrong
; for this one -- a sibling would show the glyph, and its own weak-element
; chip would write the false bit into the save's codex.
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
        ora     OT6_REVEALED_ELEM,y     ; this body only (not the species)
        sta     OT6_REVEALED_ELEM,y
        lda     $01,s
        ora     OT6_DEBIL-8,y
        sta     OT6_DEBIL-8,y
@out:   pla
        rtl
.endproc
