; ------------------------------------------------------------------------------
; OT6: Dance's terrain roll, on the boost's ladder (#473)
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
