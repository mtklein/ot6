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
;     only its target.  The price is MagicProp's 3 MP, on the boost ladder
;     every boosted spell pays (8 at one point); the pips are spent as on
;     any boosted turn (Ot6ActionEnd).
; The reveal goes through the pending bytes (OT6_RVPEND_*), so it lands
; with the same commit a chip's does (Ot6RevealCommit, which Ot6ActionEnd
; runs for an action with no numeral) on every slot of the species.  A
; weakness Debilitator added to one body is that body's, not the species'
; (ot6_debilitator.asm): it is left out of the pending byte and the codex.
; Inside the Fanatics' Tower the Magic row stays, so Scan does too (#420
; removes the kit rows, not Magic).
;
; Study (#432, owner 2026-10-13): Strago's full boost.  His Scan with all
; three points pending reads every enemy as above and also learns every lore
; any monster on the field could cast: each present body's species row of
; Ot6StudyTbl (the lores its AI script names, main or counter section;
; tools/check_study_table.py holds the table to the scripts) is ORed into
; $3A84, vanilla's "lores learned this battle", less what $1D29 already
; knows, and the victory screen teaches them as it does a lore seen cast
; (battle_main.asm @5eca).  The full boost is the only gate.  The price is
; the shared ceiling, 99 MP (Ot6MagicPrice).  A pick the engine makes
; (Muddle, Charm, Berserk) spends no boost, so it never studies; a Gogo's
; copy is a Scan (the study is Strago's).
; ------------------------------------------------------------------------------

.segment "ot6_code"

OT6_ANALYZE_SPELL = $18         ; ATTACK::SCAN
OT6_CHAR_STRAGO   = $07
OT6_STUDY_BOOST   = 3           ; the full boost, the study's one gate
OT6_STUDY_MP      = 99          ; the shared ceiling

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
        jsr     Ot6StudyOne     ; Strago at the full boost: its lores
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

; [ the study: one body's lores, pending for the victory screen ]
; a8/i16, x = attacker, y = monster entity offset, db = $7e.  Learns only when
; the attacker is Strago with the full boost pending.  preserves x/y.
.proc Ot6StudyOne
        .a8
        .i16
        lda     $3ed8,x         ; the attacker's actor
        cmp     #OT6_CHAR_STRAGO
        bne     @done
        lda     OT6_BOOST_REVEALED,x
        cmp     #OT6_STUDY_BOOST
        bcc     @done
        phx
        ldx     #$0000
        rep     #$20
        .a16
@find:  lda     f:Ot6StudyTbl,x
        cmp     #$ffff
        beq     @none           ; a species whose script casts no lore
        cmp     OT6_SPECIES-8,y
        beq     @hit
        inx
        inx
        inx
        inx
        inx
        bra     @find
@hit:   sep     #$20
        .a8
        lda     $1d29           ; what he knows already stays as it is
        eor     #$ff
        and     f:Ot6StudyTbl+2,x
        ora     $3a84
        sta     $3a84
        lda     $1d2a
        eor     #$ff
        and     f:Ot6StudyTbl+3,x
        ora     $3a85
        sta     $3a85
        lda     $1d2b
        eor     #$ff
        and     f:Ot6StudyTbl+4,x
        ora     $3a86
        sta     $3a86
@none:  sep     #$20
        .a8
        plx
@done:  rts
.endproc

; [ species -> the lores its AI script can cast ]
; .word species, then the 3-byte lore mask in $1D29's bit order; ascending,
; ending $FFFF.  Generated by tools/check_study_table.py --emit, and checked
; against the built ROM's scripts by the same tool (the spell_grants-style
; build gate study_table).
Ot6StudyTbl:
        .word   $000c
        .byte   $00, $0e, $00
        .word   $000d
        .byte   $bb, $7f, $bb
        .word   $001f
        .byte   $08, $00, $00
        .word   $002b
        .byte   $10, $00, $00
        .word   $002d
        .byte   $00, $0e, $00
        .word   $003a
        .byte   $08, $00, $00
        .word   $003b
        .byte   $00, $00, $08
        .word   $0041
        .byte   $00, $00, $80
        .word   $0044
        .byte   $00, $00, $01
        .word   $004a
        .byte   $20, $00, $00
        .word   $004c
        .byte   $20, $00, $00
        .word   $004f
        .byte   $00, $00, $80
        .word   $0050
        .byte   $01, $00, $00
        .word   $0054
        .byte   $00, $40, $00
        .word   $0056
        .byte   $60, $00, $00
        .word   $0057
        .byte   $00, $00, $01
        .word   $005b
        .byte   $00, $00, $01
        .word   $0061
        .byte   $00, $00, $02
        .word   $006c
        .byte   $00, $00, $10
        .word   $006d
        .byte   $00, $0e, $00
        .word   $0072
        .byte   $00, $01, $00
        .word   $007e
        .byte   $08, $00, $00
        .word   $0083
        .byte   $80, $00, $00
        .word   $0087
        .byte   $00, $01, $00
        .word   $0089
        .byte   $10, $01, $00
        .word   $0098
        .byte   $00, $00, $08
        .word   $00a0
        .byte   $00, $00, $01
        .word   $00a6
        .byte   $0c, $00, $00
        .word   $00aa
        .byte   $00, $00, $80
        .word   $00ab
        .byte   $03, $20, $00
        .word   $00ac
        .byte   $80, $00, $00
        .word   $00b7
        .byte   $00, $00, $02
        .word   $00bb
        .byte   $01, $00, $00
        .word   $00bc
        .byte   $20, $00, $00
        .word   $00c9
        .byte   $00, $00, $10
        .word   $00d7
        .byte   $00, $08, $00
        .word   $00d9
        .byte   $00, $06, $00
        .word   $00db
        .byte   $00, $00, $04
        .word   $00de
        .byte   $00, $00, $80
        .word   $00e4
        .byte   $08, $00, $00
        .word   $00eb
        .byte   $00, $01, $00
        .word   $00ed
        .byte   $00, $00, $84
        .word   $00f6
        .byte   $00, $20, $00
        .word   $00f9
        .byte   $00, $12, $00
        .word   $00fb
        .byte   $03, $00, $00
        .word   $00fc
        .byte   $00, $02, $00
        .word   $00fd
        .byte   $00, $00, $01
        .word   $0101
        .byte   $20, $00, $00
        .word   $010a
        .byte   $08, $00, $00
        .word   $0112
        .byte   $00, $00, $10
        .word   $0118
        .byte   $03, $00, $00
        .word   $011c
        .byte   $00, $30, $00
        .word   $011d
        .byte   $10, $02, $00
        .word   $011f
        .byte   $00, $01, $00
        .word   $0123
        .byte   $00, $00, $40
        .word   $0124
        .byte   $20, $00, $00
        .word   $0127
        .byte   $00, $80, $00
        .word   $0128
        .byte   $00, $00, $20
        .word   $0129
        .byte   $10, $00, $00
        .word   $012d
        .byte   $00, $08, $00
        .word   $012e
        .byte   $08, $00, $10
        .word   $0138
        .byte   $04, $40, $00
        .word   $014b
        .byte   $10, $00, $00
        .word   $0151
        .byte   $01, $00, $00
        .word   $0152
        .byte   $0c, $00, $08
        .word   $0153
        .byte   $00, $04, $00
        .word   $015e
        .byte   $00, $01, $00
        .word   $015f
        .byte   $01, $00, $00
        .word   $016a
        .byte   $20, $00, $00
        .word   $016b
        .byte   $20, $00, $00
        .word   $016c
        .byte   $20, $00, $00
        .word   $016d
        .byte   $20, $00, $00
        .word   $0174
        .byte   $00, $00, $01
        .word   $017d
        .byte   $04, $00, $00
        .word   $ffff
