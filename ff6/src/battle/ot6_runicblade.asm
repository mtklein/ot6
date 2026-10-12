; ------------------------------------------------------------------------------
; OT6: Celes's RunicBlade, the divine of her Runic (#378)
;
; kits.md: RunicBlade is a Runic stance that also reflects what it absorbs --
; the MP is absorbed and the BP earned as for any Runic, and the spell goes
; back at its caster.  A divine's one gate is a full 3-BP boost (kits.md
; "Divines", owner 2026-10-11): once CELES has learned it, a Runic she raises
; with all three points is a RunicBlade.  Boost buys a reactive verb its
; duration, so the stance stands for her next three turns, as a 3-BP Runic
; always has (Ot6RunicRaise / Ot6RunicHold); the divine adds the bounce.
; There is no once-a-battle limit.
;
; The bounce is Celes's counterattack: the spell she absorbed, cast by her at
; the one who cast it, free (the mimic path's no-MP queue, $b1.6), through
; vanilla's own counterattack queue (CreateRetalAction from CheckRetal, the
; Retort and Black Belt route), so it is drawn and resolved as her own cast
; of that spell.  It is the absorbed spell, not a stronger one: no fold and
; no multiplier (Ot6QueueFold keeps a counter's id; Ot6BoostDmg skips
; counters).  Only player-magic ids ($00-$35) bounce; anything else runic
; can catch (none in the shipped data) is absorbed only.  A counter is not
; countered (vanilla's rule), and a battle with counters off ($341a = 0)
; bounces nothing.
;
; Learned at the Magitek factory: event switch $0068, the same as Edgar's
; Overclock (ot6_overclock.asm), set where the tube room's way out opens after
; the espers' scene, Celes's turn against Kefka.
;
; State (ot6_memory.inc): OT6_RUNICBLADE, the per-character bit "this stance
; is a RunicBlade", set at the raise and cleared when the stance's turns run
; out; OT6_BLADEPEND/CASTER/SPELL, the one bounce an absorb banked for the
; CheckRetal that ends the same action.
; ------------------------------------------------------------------------------

.segment "ot6_code"

OT6_CHAR_CELES = $06

; [ the raise: is this Runic a RunicBlade? ]
; From Ot6RunicRaise, after the turns are recorded.  a8, x = Celes's entity
; offset (a character: the caller refused monsters), db = $7e.  clobbers A.
.proc Ot6BladeRaise
        .a8
        lda     $3ed8,x         ; character id
        cmp     #OT6_CHAR_CELES
        bne     @plain
        lda     OT6_BOOST_REVEALED,x
        cmp     #$03            ; the divine's one gate: a full boost
        bcc     @plain
        lda     f:$7e0000+OT6_FACTORY_SW
        and     #OT6_FACTORY_BIT
        beq     @plain          ; not learned yet
        lda     $3018,x
        ora     f:$7e0000+OT6_RUNICBLADE
        sta     f:$7e0000+OT6_RUNICBLADE
        rtl
@plain: lda     $3018,x         ; a plain Runic: no bounce
        eor     #$ff
        and     f:$7e0000+OT6_RUNICBLADE
        sta     f:$7e0000+OT6_RUNICBLADE
        rtl
.endproc

; [ the stance ran out: no more bounces ]
; From Ot6RunicHold when the turns are spent and vanilla's clear stands.
; a8, x = the character's entity offset.  clobbers A.
.proc Ot6BladeEnd
        .a8
        lda     $3018,x
        eor     #$ff
        and     f:$7e0000+OT6_RUNICBLADE
        sta     f:$7e0000+OT6_RUNICBLADE
        rtl
.endproc

; [ an absorb by a RunicBlade banks its bounce ]
; From Ot6RunicBP, where the absorb is certain.  a8, y = the absorbing
; character's entity offset, x = the caster's, $b6 = the spell, db = $7e.
; clobbers A; preserves X and Y.
.proc Ot6BladeAbsorb
        .a8
        lda     $3018,y
        and     f:$7e0000+OT6_RUNICBLADE
        beq     @out            ; a plain Runic
        lda     $b6
        cmp     #$36
        bcs     @out            ; player magic only
        sta     f:$7e0000+OT6_BLADESPELL
        txa
        sta     f:$7e0000+OT6_BLADECASTER
        tya
        ora     #$80            ; valid
        sta     f:$7e0000+OT6_BLADEPEND
@out:   rtl
.endproc

; [ CheckRetal's head: queue the bounce the action banked ]
; jsl from CheckRetal's first instruction, a8/i8, db = $7e.  out: carry set =
; queue it: x = Celes's entity, $3a7a/$3a7b = magic / the spell, $b8/$b9 =
; the caster, $b1.6 set (GetMPCost prices the counter 0, the mimic's path);
; the caller jsr's CreateRetalAction.  carry clear = nothing to bounce.
; Either way the pending bounce is consumed.
.proc Ot6BladeBounce
        .a8
        .i8
        lda     f:$7e0000+OT6_BLADEPEND
        bpl     @no
        and     #$7f
        tax                     ; x = Celes
        lda     #$00
        sta     f:$7e0000+OT6_BLADEPEND
        lda     $341a
        beq     @no             ; counterattacks are off in this battle
        lda     $b1
        lsr
        bcs     @no             ; the absorbed cast was a counter: none back
        lda     $3ee4,x
        bit     #$c2
        bne     @no             ; Celes fell, or was petrified or zombied
        lda     f:$7e0000+OT6_BLADECASTER
        tay
        lda     $3aa0,y
        lsr
        bcc     @no             ; the caster has left the field
        longa
        lda     $3018,y         ; the caster's bit, either side of the field
        sta     $b8
        shorta
        lda     #$02
        sta     $3a7a           ; magic
        lda     f:$7e0000+OT6_BLADESPELL
        sta     $3a7b           ; the absorbed spell
        lda     #$40
        tsb     $b1             ; priced 0, as a mimic's copy is
        sec
        rtl
@no:    clc
        rtl
.endproc

; [ RunicEffect's head: the bounce goes through every Runic stance ]
; The bounce is CELES's own cast, and her stance stands while it flies: a
; Runic stance absorbs every runic-able spell, a friendly one included
; (kits.md's "ally-spell quirk"), so the bounce was eaten by the stance that
; sent it.  A counterattack ($b1.0) of Magic by a character whose stance is
; a RunicBlade is that bounce (her only magic counter), and it is made
; un-absorbable for this pass: $11a3 bit 3 cleared, the bit RunicEffect
; tests first.
; jsl from RunicEffect's head, a8/i8, x = the attacker, db = $7e.  clobbers
; A; preserves X and Y.
.proc Ot6BladeNoRunic
        .a8
        lda     $b1
        lsr
        bcc     @out            ; not a counterattack
        txa
        cmp     #$08
        bcs     @out            ; a monster's counter
        lda     $3a7c
        cmp     #$02
        bne     @out            ; not Magic
        lda     $3018,x
        and     f:$7e0000+OT6_RUNICBLADE
        beq     @out            ; not a RunicBlade's
        lda     $11a3
        and     #$f7            ; runic-able off for this pass
        sta     $11a3
@out:   rtl
.endproc
