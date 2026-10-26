; ------------------------------------------------------------------------------
; OT6: Mog's Water Rondo, the divine of his Dance (#380)
;
; kits.md "Divines": a divine's one gate is a full 3-BP boost (owner,
; 2026-10-11), and Mog's is Water Rondo, the dance vanilla teaches on the
; Lete River.  A Dance is a whole-battle state: the start pays once (Dance's
; 8 MP x2.5 per pending boost, so 99 at three points) and every step after it
; takes the tier the start bought (OT6_DANCETIER, #294), so three points on
; Water Rondo are El Nino, Plasma, Specter and Wild Bear at x8 for the rest
; of the battle.  Like any dance at three points (Ot6DanceTerrain's ladder,
; #473) it never stumbles: the river is a terrain the party almost never
; fights on again, and danced with all three points it starts wherever the
; party stands, the background turning to the river, as a dance that does
; not stumble turns it.
;
; With fewer than three points pending it is not offered: its row greys and
; the confirm buzzes (Ot6DanceRowColor, the Jackpot/Morph shape).  An engine
; pick spends no boost, so it closes there too:
;   * a random Dance (Muddle, Charm, the Colosseum: RandCharAction's dance
;     arm) draws from the known dances less Water Rondo (Ot6DanceKnownRand);
;   * any Water Rondo start that still arrives with fewer than three points
;     pending -- a dance id left from an earlier divine start in this battle,
;     or a Mimic by a Gogo who did not boost it -- stumbles: no dance begins,
;     and the stumble charges nothing, neither MP (Ot6DanceStumble, #313) nor
;     pips (Ot6DanceTerrain drops them: no boost under three could buy this
;     start).  Its dance id is cleared, so a random Dance draws afresh.
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

; [ the start's terrain roll: the boost's ladder, and the divine's gate ]
; jsl from Cmd_13 (battle_main.asm) in place of `ldx $11e2 / cmp
; f:BattleBGDance,x`, after the DANCE status is set and the dance id fixed,
; on the start and on every locked-in step.  Vanilla then goes on to Cmd_02
; when the dance matches the background, and otherwise rolls RandCarry: half
; the time the background turns to the dance's, half the time the dancer
; stumbles.  RNGTbl is a permutation of 0-255, so that coin is exactly 1/2
; (128 of its 256 entries are even).
;
; Dance is a chance verb in this one respect (#473): the boost the start
; bought (OT6_DANCETIER, recorded by Ot6DanceStartGate from the pending boost
; and read back by every step) tilts the stumble, the Rage coin's ladder,
; since vanilla's stumble is the same 1/2 coin Rage's special is:
;   tier 0   vanilla's RandCarry, untouched (no extra draw)     stumble 1/2
;   tier 1   stumble when a fresh draw < $40 (64 of 256)        stumble 1/4
;   tier 2   stumble when a fresh draw < $10 (16 of 256)        stumble 1/16
;   tier 3   stumble when a fresh draw < $00: never             stumble 0
; (Ot6DanceStumbleOdds holds the three thresholds).  A dance that lands turns
; the background to its own, as vanilla's roll does, so every later step
; matches.  The stumble spends the boost (Ot6DanceStumble): the boost bought
; the odds, and the roll was taken.
;
; Water Rondo under three points (an engine pick, a Mimic not boosted) is the
; divine's gate: it stumbles whatever the roll, and the dance id is cleared so
; a random Dance draws afresh.  The boost could not buy that start, so the
; pending boost is dropped (Ot6KeepBoost), not spent.  At three points Water
; Rondo is any tier-3 dance: it never stumbles, and the background turns to
; the river.
; out: A = the dance id (the roll's `tax` reads it); Z set = on to Cmd_02, no
;   roll; V set = the stumble; both clear = vanilla's roll decides.
; in: A = the dance id, y = the dancer.  a8/i8, db=$7e.  clobbers X.
.proc Ot6DanceTerrain
        .a8
        .i8
        pha                     ; [$01,s] the dance id
        tyx
        lda     f:$7e0000+OT6_DANCETIER,x
        pha                     ; [$01,s] the tier, [$02,s] the id
        lda     $02,s
        cmp     #OT6_WATER_RONDO
        bne     @terrain
        lda     $01,s
        cmp     #$03
        bcc     @gate           ; the divine under three points
@terrain:
        ldx     $11e2           ; the current background
        lda     $02,s
        cmp     f:BattleBGDance,x
        beq     @lands          ; on its own terrain: no roll
        lda     $01,s
        bne     @tilt
        pla                     ; tier 0: vanilla's roll decides
        pla                     ; A = the dance id
        rep     #$02            ; Z clear
        clv
        rtl
@tilt:  cmp     #$03
        bcc     :+
        lda     #$03            ; (a tier past three reads as three)
:       tax
        lda     f:Ot6DanceStumbleOdds-1,x
        sta     $01,s           ; [$01,s] the threshold
        ot6_rand                ; A = a fresh draw 0-255 (X kept)
        cmp     $01,s           ; carry clear = draw < threshold
        bcc     @stumble
        lda     $02,s           ; it lands: the background turns to the
        tax                     ;   dance's (the change Cmd_13's roll makes)
        lda     f:DanceBG,x
        sta     $b7
        sta     $11e2
@lands: pla                     ; drop the tier
        pla                     ; A = the dance id
        clv
        sep     #$02            ; Z set: on to Cmd_02, no roll
        rtl
@gate:  tyx
        jsl     Ot6KeepBoost    ; the boost could not buy this start: dropped
        lda     #$ff
        sta     $32e1,y         ; no dance chosen: a random Dance draws afresh
@stumble:
        pla                     ; drop the tier/threshold
        pla                     ; A = the dance id
        rep     #$02            ; Z clear
        sep     #$40            ; V set: the stumble
        rtl
.endproc

; the stumble thresholds for tiers 1-3: a draw below the tier's byte stumbles
; (1/4, 1/16, never).  Tier 0 is vanilla's RandCarry, which no byte here
; describes.
Ot6DanceStumbleOdds:
        .byte   $40, $10, $00
