; ------------------------------------------------------------------------------
; OT6: Dance's two rolls, on the boost's ladder: the start's terrain roll
; (#473) and the opening step (owner, 2026-11-23)
;
; Every dance is an ordinary dance (#478: Mog has no divine for now; Water
; Rondo, which was one under #380, is learned, priced, boosted and rolled
; like the other seven).
; ------------------------------------------------------------------------------

.segment "ot6_code"

; [ the start's terrain roll: the boost's ladder ]
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

; ------------------------------------------------------------------------------

; [ a boosted Dance opens on its rare step ]
;
; Each dance has four steps (DanceProp), and vanilla's RandDance picks one
; per turn from one draw of the battle RNG against DanceRateTbl ($10, $30,
; $90): the fourth step below $10, the third below $30, the second below
; $90, else the first.  RNGTbl is a permutation of 0-255, so the odds are
; exactly 16, 32, 96 and 112 of 256: 1/16, 1/8, 3/8 and 7/16.  The fourth is
; the rare step (Cokatrice, Wombat, Kitty, Tapir, Whump, Wild Bear, Pois.
; Frog, Ice Rabbit).
;
; The boost a Dance start is bought with loads that roll for the turn the
; dance starts, its opener, and only that turn (owner, 2026-11-23: "have
; boosted dances guarantee the 1/16th move as a starter"):
;   0 BP   vanilla's RandDance, untouched (nothing drawn here)   rare 1/16
;   1 BP   the rare step when the draw < $40 (64 of 256)         rare 1/4
;   2 BP   the rare step when the draw < $80 (128 of 256)        rare 1/2
;   3 BP   the rare step, whatever the draw                      rare 1
; At 1 and 2 BP the three common steps share what is left in vanilla's own
; proportions (7 : 6 : 2), to the nearest 256th: Ot6DanceOpenerOdds holds the
; rows in DanceRateTbl's shape.  Every level takes the one draw RandDance
; takes (at 3 BP it is taken and not read), so a boosted start changes
; which step opens and leaves the battle RNG where vanilla's would.
;
; This is the opener the menu queues, so it is danced only if the start
; lands: off its terrain Cmd_13's roll (Ot6DanceTerrain, above) can still
; stumble at 1 and 2 BP, and a stumble dances no step.  At 3 BP neither
; roll can miss.  The boost's multiplier covers the opener as it covers
; every step (Ot6BoostLevel).  Every later step is RandDance's, at
; vanilla's odds, and so is a dance the engine starts on its own (Muddle,
; the Colosseum): those never pass FixPlayerAttack, the one caller.
;
; entry: jsl from FixPlayerAttack's cmd-$13 arm (battle_main.asm @4ddb), in
; place of its bare `jsr RandDance`, after the menu's dance id is stored in
; $32e1,y.  a8, index width not assumed; y = the dancer; db=$7e.
; out: carry clear = unboosted: the caller runs RandDance (A is not the
;   step); carry set = A = the opening step's attack id.  Preserves x and y;
;   clobbers $ee (RandDance's own scratch).
.proc Ot6DanceOpener
        .a8
        lda     OT6_BOOST_REVEALED,y    ; the start's pending boost
        bne     @boosted
        clc                     ; 0 BP: vanilla's roll decides
        rtl
@boosted:
        php
        sep     #$10            ; i8: an entity offset and a table index
        .i8
        phx
        dec                     ; tier 1-3 -> row 0-2
        cmp     #$02
        bcc     :+
        lda     #$02            ; (a boost past three reads as three)
:       pha
        asl
        clc
        adc     $01,s
        tax                     ; X = the tier's row, 3 bytes each
        pla
        lda     $32e1,y         ; the dance the menu chose
        asl
        asl
        sta     $ee             ; its first step in DanceProp
        ot6_rand                ; A = the one draw RandDance takes (X kept)
        cpx     #$06
        bcs     @s3             ; three points: the rare step, no gamble
        cmp     f:Ot6DanceOpenerOdds,x
        bcc     @s3             ; below the row's first byte: the rare step
        cmp     f:Ot6DanceOpenerOdds+1,x
        bcc     @s2
        cmp     f:Ot6DanceOpenerOdds+2,x
        bcc     @s1
        bra     @s0
@s3:    inc     $ee
@s2:    inc     $ee
@s1:    inc     $ee
@s0:    ldx     $ee
        lda     f:DanceProp,x   ; the step's attack id
        plx
        plp
        sec
        rtl
.endproc

; the opener's odds at 1 and 2 BP, a row each in DanceRateTbl's shape: a draw
; below the first byte is the fourth (rare) step, below the second the third,
; below the third the second, else the first.  Of 256 draws:
;   1 BP   64 rare, 25, 77, 90      (vanilla's 32 : 96 : 112 over 192)
;   2 BP   128 rare, 17, 51, 60     (the same over 128)
; 3 BP has no row: it never reads the draw.
Ot6DanceOpenerOdds:
        .byte   $40, $59, $a6
        .byte   $80, $91, $c4
