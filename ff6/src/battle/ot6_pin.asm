; ------------------------------------------------------------------------------
; OT6: Shadow's throws hobble and pin (#546; docs/design/kit-shadow-pin.md)
;
; Octopath's Leghold Trap as FF6's own Slow and Stop, keyed on the Throw
; command (command $08) so it works with whatever the bag holds:
;   * every hit of a character's Throw that lands on a monster hobbles it
;     (Slow);
;   * a hit on a monster that is already Slowed, from any source, pins it
;     instead: Stop for OT6_PIN_TICKS status ticks (vanilla's Stop is 18), and
;     the pin uses up the hobble (the Slow is cleared);
;   * a throw at a pinned monster deals its damage and changes nothing else;
;   * a Broken monster is hobbled if free and never pinned;
;   * vanilla's immunities stand: the writes go through the status-to-set and
;     to-clear cells ($3de8/$3e10), which InitStatusVars masks with the body's
;     allowed statuses ($3330), so a Slow-immune body is never hobbled and a
;     Stop-immune one is never pinned (Ot6Pin tests it, so the Slow stays).
; Not affected: the smoke and the exit and any throw at an ally (the target
; is a character), a monster's throw (the attacker is a monster), Umaro's
; Throw (command $24), a counterattack ($b1 bit 0).  Gogo's Throw and a
; Mimic of a throw are command $08 by a character, so they get the rule.
; A boost keeps buying Throw's damage multiplier (Ot6BoostDmg) and nothing
; here reads it.
;
; The mark (ot6_hud.asm): a cell before the shield emblem shows the font's
; dagger while a monster is Slowed and a point-down knife while it is
; Stopped, from any source.  It rides #539's hold: an action that changes a
; monster's Slow, Stop or Haste holds its line (Ot6Pin -> Ot6Hold, which
; snapshots the mark into OT6_SHOWN's odd byte), each numeral's event
; carries the mark after its hit (Ot6EvPush, the class byte's bits 4-5), and
; the script's end releases the hold, so the mark lands with the hit that
; causes it and a numeral-less Slow shows at its script's end.
; ------------------------------------------------------------------------------

.segment "ot6_code"
.a8
.i16

OT6_PIN_TICKS   = 8             ; the pin: half a break (OT6_BREAK_TICKS), about
                                ;   two of a median enemy's turns
OT6_MARK_SLOW   = 1             ; OT6_MARKCELL / the held mark: hobbled
OT6_MARK_STOP   = 2             ;   pinned
OT6_MARK_STATUS = STATUS3::SLOW | STATUS3::STOP | STATUS3::HASTE

; [ a throw lands: hobble or pin ]
; jsl from CalcAttackEffect's per-target loop (battle_main.asm), right after
; MagicStatusEffect, so the attack's own statuses are in $3de8/$3e10 already.
; x = the attacker, y = the target (entity offsets), a16, either index
; width, db=$7e.  Preserves a/x/y/p.  rtl.
.proc Ot6Pin
        php
        rep     #$30
        .a16
        .i16
        pha
        shorta0                 ; a8, b = 0 (the high byte of every tax/tay
                                ;   below is zero)
        tya
        cmp     #$08
        bcc     @out            ; a character target: the smoke, the exit,
                                ;   a throw at an ally
        lda     $b5
        cmp     #$08            ; Throw (Shadow's, Gogo's, a Mimic of one)
        bne     @hold
        txa
        cmp     #$08
        bcs     @hold           ; a monster's throw
        lda     $b1
        lsr
        bcs     @hold           ; a counterattack
        lda     $3ef8,y         ; status 3
        bit     #STATUS3::STOP
        bne     @hold           ; pinned: the damage, nothing else
        bit     #STATUS3::SLOW
        beq     @hobble         ; free: hobble it
        lda     OT6_BROKEN_TICKS,y
        bne     @hold           ; Broken and hobbled: the hobble waits for
                                ;   it to rise; a Broken body is never pinned
        lda     $3330,y         ; allowed status 3
        bit     #STATUS3::STOP
        beq     @hold           ; Stop-immune: it stays hobbled
        lda     #STATUS3::STOP  ; the pin...
        ora     $3de8,y
        sta     $3de8,y
        lda     #STATUS3::SLOW  ; ...uses up the hobble
        ora     $3e10,y
        sta     $3e10,y
        jsr     Ot6HitBit
        tsb     OT6_PINNING     ; Ot6StopTicks gives this Stop the pin's length
        bra     @hold
@hobble:
        lda     #STATUS3::SLOW  ; a Slow-immune body loses it to
        ora     $3de8,y         ;   InitStatusVars' mask
        sta     $3de8,y
@hold:  ; any attack that changes a monster's Slow, Stop or Haste holds its
        ; line, so the mark changes with the hit (or the script's end), not
        ; when the status is computed
        lda     $3de8,y
        ora     $3e10,y
        and     $3330,y
        and     #OT6_MARK_STATUS
        beq     @out
        jsr     Ot6Hold
@out:   rep     #$30
        pla
        plp
        rtl
.endproc

; [ Stop's counter: the pin's length, or vanilla's ]
; jsl from SetStatus_14 (battle_main.asm) in place of `lda #$12 / sta
; $3af1,y`.  y = the body Stop lands on, a8, either index width, db=$7e.
; A Stop Ot6Pin queued as a pin (its bit in OT6_PINNING) counts
; OT6_PIN_TICKS and consumes the bit; every other Stop (Fenrir's, a
; spell's, a monster's) keeps vanilla's 18.  Clobbers a; preserves x/y.
.proc Ot6StopTicks
        .a8
        tya
        cmp     #$08
        bcc     @vanilla        ; a character
        jsr     Ot6HitBit
        and     OT6_PINNING
        beq     @vanilla
        jsr     Ot6HitBit
        trb     OT6_PINNING
        lda     #OT6_PIN_TICKS
        bra     @set
@vanilla:
        lda     #$12
@set:   sta     $3af1,y
        rtl
.endproc

; [ the live mark ]  y = entity offset -> a = 0 free, 1 Slowed, 2 Stopped.
; a8, either index width.  Preserves x/y.
.proc Ot6LiveMark
        .a8
        lda     $3ef8,y
        ; fall through
.endproc
; a = status 3 -> a = the mark it shows (Stop over Slow)
.proc Ot6MarkOf
        .a8
        bit     #STATUS3::STOP
        bne     @stop
        and     #STATUS3::SLOW
        beq     @out
        lda     #OT6_MARK_SLOW
@out:   rts
@stop:  lda     #OT6_MARK_STOP
        rts
.endproc

; [ the mark after this hit ]  y = entity offset -> a = the mark the body
; will show once UpdateStatus applies what this action queued: the live
; status 3, plus the pending set, less the pending clear, both masked by the
; body's allowed statuses (InitStatusVars' masks); a Haste set clears Slow
; (SetStatus_13).  For Ot6EvPush, whose numeral is queued before
; UpdateStatus runs.  a8, either index width, db=$7e.  Preserves x/y.
.proc Ot6PendMark
        .a8
        lda     $3de8,y
        and     $3330,y
        pha                     ; [$02,s] the set
        ora     $3ef8,y
        pha                     ; [$01,s] live | set
        lda     $3e10,y
        and     $3330,y
        eor     #$ff
        and     $01,s           ; less the clear
        sta     $01,s
        lda     $02,s
        and     #STATUS3::HASTE
        beq     :+
        lda     $01,s
        and     #<~STATUS3::SLOW
        sta     $01,s
:       pla
        sta     $01,s
        pla
        jmp     Ot6MarkOf
.endproc

; [ the shield line's mark, for the flush ]
; From Ot6BgHudLine, every frame a monster's line is live, right after its
; gauge read.  y = the slot offset (0,2..10), a = the gauge to draw
; (Ot6ShownGauge: $40 for a dead or petrified body, whose line draws empty
; and so shows no mark).  Writes OT6_MARKCELL for the slot: the held mark
; while the slot is held (#539: OT6_SHOWN's odd byte, which Ot6Hold
; snapshots and each event's hit sets), else the live status 3.  a8/i16,
; db=$7e.  Preserves a/x/y.
.proc Ot6MarkStage
        .a8
        .i16
        pha                     ; [$01,s] the gauge
        phx
        longa
        tya
        lsr
        tax                     ; the slot (y's high byte is zero)
        shorta0
        lda     $03,s
        bit     #$40
        bne     @none           ; dead or petrified: no mark
        lda     f:Ot6HitBitTbl,x
        and     OT6_HOLD
        beq     @live
        lda     OT6_SHOWN+1,y   ; the mark as of the last hit shown
        bra     @put
@live:  lda     $3f00,y         ; status 3 (+8: the monster half)
        jsr     Ot6MarkOf
        bra     @put
@none:  lda     #$00
@put:   sta     OT6_MARKCELL,x
        plx
        pla
        rts
.endproc
