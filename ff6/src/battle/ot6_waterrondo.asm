; ------------------------------------------------------------------------------
; OT6: Mog's Water Rondo, the divine of his Dance (#380)
;
; kits.md "Divines": a divine's one gate is a full 3-BP boost (owner,
; 2026-10-11), and Mog's is Water Rondo, the dance vanilla teaches on the
; Lete River.  A Dance is a whole-battle state: the start pays once (Dance's
; 8 MP x2.5 per pending boost, so 99 at three points) and every step after it
; takes the tier the start bought (OT6_DANCETIER, #294), so three points on
; Water Rondo are El Nino, Plasma, Specter and Wild Bear at x8 for the rest
; of the battle.  What the full boost buys beyond any other dance's: Water
; Rondo never stumbles.  A dance started off its own terrain stumbles half
; the time in vanilla (Cmd_13's roll), and the river is a terrain the party
; almost never fights on again; danced with all three points, it starts
; wherever the party stands, and the background turns to the river, as a
; dance that does not stumble turns it.
;
; With fewer than three points pending it is not offered: its row greys and
; the confirm buzzes (Ot6DanceRowColor, the Jackpot/Morph shape).  An engine
; pick spends no boost, so it closes there too:
;   * a random Dance (Muddle, Charm, the Colosseum: RandCharAction's dance
;     arm) draws from the known dances less Water Rondo (Ot6DanceKnownRand);
;   * any Water Rondo start that still arrives with fewer than three points
;     pending -- a dance id left from an earlier divine start in this battle,
;     or a Mimic by a Gogo who did not boost it -- stumbles: no dance begins,
;     and the stumble charges nothing, neither MP nor pips (Ot6DanceStumble,
;     #313).  Its dance id is cleared, so a random Dance draws afresh.
; A Gogo's Mimic of it reads Gogo's own pending boost, the Jackpot precedent
; (kits.md "Divines": the copy takes the full boost from Gogo's own bank
; where the copy reads it).
; ------------------------------------------------------------------------------

.segment "ot6_code"

OT6_WATER_RONDO = 5             ; DanceProp's sixth dance, $1d4c bit 5

; [ the colour of a Dance row: MP, and the divine's full boost ]
; The one verdict the draw (Ot6DanceRowDecorate) and the confirm
; (Ot6DanceConfirmMP) take, so the two cannot disagree: grey when the caster
; cannot pay the row's price at the pending boost (Ot6AbilityGrey), and, for
; Water Rondo, grey when fewer than three points are pending.  An empty ($ff)
; cell stays white.
; in: A = dance id.  out: A = $04 grey / $00 white.  a8/i16, db=$7e.
; preserves X and Y.
.proc Ot6DanceRowColor
        .a8
        .i16
        pha                     ; park the id ($01,s)
        jsl     Ot6DanceRowCost ; id -> the price at the pending boost
        jsl     Ot6AbilityGrey  ; -> the MP verdict
        bne     @out            ; already grey
        lda     $01,s
        cmp     #OT6_WATER_RONDO
        bne     @white
        phx
        lda     $62ca           ; the active character's slot
        longa
        and     #$0003
        asl
        tax                     ; -> entity offset
        shorta0
        lda     OT6_BOOST_REVEALED,x
        plx
        cmp     #$03            ; the divine's one gate: a full boost
        bcs     @white
        lda     #$04
        bra     @out
@white: lda     #$00
@out:   sta     $01,s
        pla
        rtl
.endproc

; [ a random Dance: the known dances, less the divine ]
; RandDance (battle_main.asm) draws a known dance when a Dance arrives with no
; dance chosen ($32e1 = $ff): RandCharAction's dance arm, for a Muddled or
; Charmed Mog and at the Colosseum.  That pick spends no boost, so Water Rondo
; is out of it.  If Water Rondo is the only dance known, the mask is left
; whole: the start then stumbles at Ot6DanceTerrain and charges nothing.
; jsl in place of `clr_a / lda $1d4c` (RandBit takes the mask as a word).
; a8, db=$7e.  out: A = the mask, B = 0.  preserves X and Y.
.proc Ot6DanceKnownRand
        .a8
        lda     $1d4c           ; known dances
        and     #<~(1 << OT6_WATER_RONDO)
        bne     :+
        lda     $1d4c           ; only the divine known: leave it whole
:       xba
        lda     #$00
        xba                     ; B = 0
        rtl
.endproc

; [ the start's terrain roll, with the divine's rule ]
; jsl from Cmd_13 (battle_main.asm) in place of `ldx $11e2 / cmp
; f:BattleBGDance,x`, after the DANCE status is set and the dance id fixed.
; Vanilla then goes on to Cmd_02 when the dance matches the background, and
; otherwise rolls: half the time the background turns to the dance's, half
; the time the dancer stumbles.
;   any dance but Water Rondo: vanilla's compare, untouched (V clear).
;   Water Rondo, its start's tier (OT6_DANCETIER, which Ot6DanceStartGate
;     recorded from the pending boost when this start began, and every
;     locked-in step reads back) three: it never stumbles.  On another
;     background the background turns to the river now, so every later step
;     matches.  Out: Z set.
;   Water Rondo at a tier under three (an engine pick, a Mimic not boosted):
;     the stumble, and the dance id cleared so a random Dance draws afresh.
;     Out: Z clear, V set.
; out: A = the dance id (the roll's `tax` reads it), Z = matches, V = stumble.
; in: A = the dance id, y = the dancer.  a8/i8, db=$7e.  clobbers X.
.proc Ot6DanceTerrain
        .a8
        cmp     #OT6_WATER_RONDO
        beq     @rondo
        ldx     $11e2           ; the current background
        cmp     f:BattleBGDance,x
        clv                     ; vanilla's roll decides the rest
        rtl
@rondo: pha
        tyx
        lda     f:$7e0000+OT6_DANCETIER,x
        cmp     #$03
        bcc     @stumble
        ldx     $11e2
        lda     $01,s           ; the dance
        cmp     f:BattleBGDance,x
        beq     @go             ; on the river already
        tax
        lda     f:DanceBG,x     ; the river's background
        sta     $b7             ;   (the change Cmd_13's roll makes)
        sta     $11e2
@go:    pla                     ; A = the dance id
        clv
        sep     #$02            ; Z set: on to Cmd_02, no roll
        rtl
@stumble:
        lda     #$ff
        sta     $32e1,y         ; no dance chosen: a random Dance draws afresh
        pla                     ; A = the dance id
        rep     #$02            ; Z clear
        sep     #$40            ; V set: the stumble
        rtl
.endproc
