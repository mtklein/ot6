; ------------------------------------------------------------------------------
; Celes's kit: the rune on her blade, and the Rune Knight's list (#563)
;
; Design and the owner's rulings: docs/design/kits.md, "Celes".
;
; The rune.  A character's blade can hold an element for the rest of the
; battle (OT6_RUNE, per character).  Two things arm it, through one leaf
; (Ot6RuneArm: a character, an element):
;   * a Runic absorb of a spell that carries an element (Ot6RuneAbsorb, from
;     Ot6RunicBP, where the absorb is certain), an enemy's spell or an ally's
;     (vanilla's ally-spell quirk, kept), by CELES or a GOGO (#547);
;   * a blade row of the list below.
; A later arming replaces it; a spell without an element leaves it.  Nothing
; clears it but the battle's end (InitBP): it stays through her fall and her
; return, and it is not the Runic stance's bit ($3e4c.2), which comes and
; goes with her turns.
;
; Its effect.  Her weapon's swings (_magicpunch: Fight and its boosted
; swings, either hand, a counter, Mug and Capture, Jump) carry the rune's
; element onto a target that is weak to it and neither absorbs, nulls nor
; halves it (Ot6RuneSwing notes the rune at the swing, Ot6RuneTarget judges
; each target); from there vanilla's weak branch doubles the hit and
; Ot6Chip takes the shield and reveals the weakness.  On any other target
; the rune does nothing (owner, 2026-11-23: "hurting more than helping is no
; good"), which is where it differs from Relm's Tint, a colour the player
; picked that lands on a body that drinks it.  The weapon's own element and
; a Tint still apply as before, OR'd.
;
; The list.  Anyone holding the Runic command (CELES; a GOGO who picked it)
; opens a Tools-shell list behind it, the twin of Locke's behind Steal and
; Relm's behind Sketch (mode w7e6168 = 7):
;   Runic        the stance, as it always was (free; a boost buys turns; at
;                three points RunicBlade, ot6_runicblade.asm)
;   <Elem>Blade  one row per element the caster can cast in this battle (a
;                spell of it in the battle Magic list: her own, and what her
;                worn esper lends), priced at the cheapest such spell: her
;                turn arms her blade with it.  Takes no boost.
;   BreakBlade   the divine, at a full boost, 99 MP: for three of her turns
;                every hit of her weapon takes one shield, whatever the
;                body's keys; the elemental rune waits and returns after.
; Command $0b's queued attack byte is free (FixPlayerAttack has no $0b arm
; and $0b is not in CmdWithAttackTbl), so each row queues its own id and
; Cmd_0b's head dispatches on it (Ot6RuneExec).  An engine-chosen Runic
; (Muddle, Charm, the Colosseum: RandCharAction) queues $00, which is no
; row's id: the plain stance, never a blade and never the divine.
; ------------------------------------------------------------------------------

.segment "ot6_code"

OT6_RUNE_RUNIC  = $d0           ; the Runic row: the stance
OT6_RUNE_BLADE  = $d1           ; $d1-$d8: a blade row, element bit (id - $d1)
OT6_RUNE_BREAK  = $d9           ; Break Blade, the divine
OT6_RUNE_LAST   = $d9
OT6_RUNE_IDS    = OT6_RUNE_LAST - OT6_RUNE_RUNIC + 1

OT6_BREAK_TURNS = 3             ; Break Blade lasts three of her turns
OT6_BREAK_MP    = 99
OT6_BREAK_BOOST = 3             ; the divine's one gate: a full boost

; Break Blade is learned on the Floating Continent, where CELES turns her
; sword on Kefka.  Switch $0266 is set in that scene when she is in the
; party there (event_main.asm, _cadd1e) and nothing clears it; a party that
; left her on the airship has it from the World of Ruin's first scene, her
; waking on the island (switch $00A4, set once).  No save can be made
; between the two, so a save past the beat has the row whatever version
; wrote it, as the other story-learned rows do (ot6_thief.asm).
OT6_STAB_SW     = $1e80 + ($0266 >> 3)
OT6_STAB_BIT    = 1 << ($0266 & 7)
OT6_RUIN_SW     = $1e80 + ($00a4 >> 3)
OT6_RUIN_BIT    = 1 << ($00a4 & 7)

; element bit index -> the bit
Ot6RuneBitTbl:
        .byte   $01, $02, $04, $08, $10, $20, $40, $80

; the list's names, ten letters each, $d0-$d9, in AttackName's encoding
Ot6RuneName:
        .byte   $91, $ae, $a7, $a2, $9c, $ff, $ff, $ff, $ff, $ff ; Runic
        .byte   $85, $a2, $ab, $9e, $81, $a5, $9a, $9d, $9e, $ff ; FireBlade
        .byte   $88, $9c, $9e, $81, $a5, $9a, $9d, $9e, $ff, $ff ; IceBlade
        .byte   $81, $a8, $a5, $ad, $81, $a5, $9a, $9d, $9e, $ff ; BoltBlade
        .byte   $8f, $a8, $a2, $ac, $a7, $81, $a5, $9a, $9d, $9e ; PoisnBlade
        .byte   $96, $a2, $a7, $9d, $81, $a5, $9a, $9d, $9e, $ff ; WindBlade
        .byte   $8f, $9e, $9a, $ab, $a5, $81, $a5, $9a, $9d, $9e ; PearlBlade
        .byte   $84, $9a, $ab, $ad, $a1, $81, $a5, $9a, $9d, $9e ; EarthBlade
        .byte   $96, $9a, $ad, $9e, $ab, $81, $a5, $9a, $9d, $9e ; WaterBlade
        .byte   $81, $ab, $9e, $9a, $a4, $81, $a5, $9a, $9d, $9e ; BreakBlade

; the battle banner's names, 13 letters, $d0-$d9 (Runic's is never shown)
OT6_RUNE_BANLEN = 13
Ot6RuneBanner:
        .byte   $91, $ae, $a7, $a2, $9c, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff ; Runic
        .byte   $85, $a2, $ab, $9e, $fe, $81, $a5, $9a, $9d, $9e, $ff, $ff, $ff ; Fire Blade
        .byte   $88, $9c, $9e, $fe, $81, $a5, $9a, $9d, $9e, $ff, $ff, $ff, $ff ; Ice Blade
        .byte   $81, $a8, $a5, $ad, $fe, $81, $a5, $9a, $9d, $9e, $ff, $ff, $ff ; Bolt Blade
        .byte   $8f, $a8, $a2, $ac, $a8, $a7, $fe, $81, $a5, $9a, $9d, $9e, $ff ; Poison Blade
        .byte   $96, $a2, $a7, $9d, $fe, $81, $a5, $9a, $9d, $9e, $ff, $ff, $ff ; Wind Blade
        .byte   $8f, $9e, $9a, $ab, $a5, $fe, $81, $a5, $9a, $9d, $9e, $ff, $ff ; Pearl Blade
        .byte   $84, $9a, $ab, $ad, $a1, $fe, $81, $a5, $9a, $9d, $9e, $ff, $ff ; Earth Blade
        .byte   $96, $9a, $ad, $9e, $ab, $fe, $81, $a5, $9a, $9d, $9e, $ff, $ff ; Water Blade
        .byte   $81, $ab, $9e, $9a, $a4, $fe, $81, $a5, $9a, $9d, $9e, $ff, $ff ; Break Blade

; The swing's colours (btlgfx InitWeaponAnim, Ot6SwingPal_ext): AttackPal
; ids for the weapon's sprite and for the hit drawn on the target, by
; element bit, then Break Blade's.  Fire, ice, bolt and pearl are the pairs
; vanilla gives the Flame Sabre, the Blizzard, the ThunderBlade and the
; Illumina (weapon_anim_prop.dat); the rest are the nearest existing
; palettes, so no palette data is added.
Ot6SwingPalTbl:
        .byte   $29             ; fire: the Flame Sabre's red
        .byte   $22             ; ice: the Blizzard's blue
        .byte   $20             ; bolt: the ThunderBlade's gold
        .byte   $1c             ; poison: steel with a green edge
        .byte   $1d             ; wind: teal
        .byte   $2a             ; pearl: the Illumina's white
        .byte   $21             ; earth: brown
        .byte   $1f             ; water: deep blue
        .byte   $2d             ; Break Blade: violet
Ot6SwingHitPalTbl:
        .byte   $34             ; fire: orange
        .byte   $32             ; ice: pale blue
        .byte   $37             ; bolt: yellow
        .byte   $31             ; poison: green
        .byte   $30             ; wind: pale green
        .byte   $32             ; pearl: the Illumina's
        .byte   $36             ; earth: white
        .byte   $33             ; water: blue
        .byte   $35             ; Break Blade: violet

; ------------------------------------------------------------------------------

; [ arm a character's blade with an element ]
; The one place a rune is set: a Runic absorb (Ot6RuneAbsorb), a blade row
; (Ot6RuneExec), and any later source.  in: A = the element bits, Y = the
; character's entity offset (0/2/4/6).  a8, either index width, db=$7e.
; Preserves X and Y; clobbers A.
.proc Ot6RuneArm
        .a8
        sta     OT6_RUNE,y
        rtl
.endproc

; [ a Runic absorb arms the blade with the spell's element ]
; jsr from Ot6RunicBP, past its gates: the absorb has happened, and it was
; the Runic command's stance (not a raging monster's "enemy runic").  $11a1
; is still the absorbed spell's element byte (RunicEffect rewrites the
; attack into the MP restore only after its entity loop).  A spell with no
; element leaves the rune; one with several is kept whole, and each element
; is judged on its own at the swing (none of the 20 elemental spells Runic
; can absorb carries two).  The Runic command is CELES's, and a GOGO's who
; picked it (#547).
; a8, either index width, db=$7e; y = the absorber.  Preserves X and Y.
.proc Ot6RuneAbsorb
        .a8
        lda     $11a1
        beq     @out
        lda     $3ed8,y         ; character id
        cmp     #OT6_CHAR_CELES
        beq     @arm
        cmp     #OT6_CHAR_GOGO
        bne     @out
@arm:   lda     $11a1
        jsl     Ot6RuneArm
@out:   rts
.endproc

; ------------------------------------------------------------------------------

; [ no weapon swing: the rune and Break Blade ride nothing ]
; jsr from Ot6SkillClass and Ot6ItemClass, which with Ot6WeaponClass cover
; every damage path: a spell, a skill, an item, a tool or a thrown weapon
; carries no rune.  a8.  Preserves A, X, Y and the carry.
.proc Ot6RuneNoSwing
        .a8
        pha
        lda     #$00
        sta     f:$7e0000+OT6_RUNESWING
        sta     f:$7e0000+OT6_BLADESWING
        pla
        rts
.endproc

; [ a weapon swing: what the swinging character's blade holds ]
; jsr from Ot6WeaponClass, after the hand's element is in $11a1 and a Tint
; is OR'd in.  OT6_RUNESWING = the rune's elements the swing does not
; already carry (so Ot6RuneTarget can take them off again), or 0; under
; Break Blade the rune waits and OT6_BLADESWING's bit 7 says every hit takes
; a shield.  a8/i16, x = the attacker's entity offset plus the hand.
; Preserves x and y.
.proc Ot6RuneSwing
        .a8
        .i16
        jsr     Ot6RuneNoSwing
        txa
        cmp     #$08
        bcs     @out            ; a monster's swing
        phx
        longa
        txa
        and     #$0006          ; the character, either hand
        tax
        sep     #$20
        .a8
        lda     f:$7e0000+OT6_BREAKBLADE,x
        beq     @rune
        lda     #$80
        sta     f:$7e0000+OT6_BLADESWING
        bra     @done
@rune:  lda     f:$7e11a1
        eor     #$ff
        and     f:$7e0000+OT6_RUNE,x
        sta     f:$7e0000+OT6_RUNESWING
@done:  plx
@out:   rts
.endproc

; [ which of these elements bite this body? ]
; The rune's whole rule: an element bites a monster that is weak to it
; (vanilla's weak byte, Ot6ElemAddTbl's rows merged in at load) and neither
; absorbs, nulls nor halves it, nor has it nulled by a ForceField.  One leaf
; for the hit (Ot6TargetPre) and for the swing's colour (Ot6SwingPal_ext).
; in: A = element bits, Y = the target's entity offset.  out: A = the bits
; that bite (Z set = none).  a8, either index width, db=$7e.  Preserves X
; and Y.
.proc Ot6RuneBites
        .a8
        pha
        tya
        cmp     #$08
        bcc     @none           ; a character: never
        lda     $3bcc,y         ; absorbed
        ora     $3bcd,y         ; nulled
        ora     $3be1,y         ; halved
        ora     $3ec8           ; nulled by a ForceField
        eor     #$ff
        and     $3be0,y         ; weak
        and     $01,s
        sta     $01,s
        pla
        rts
@none:  pla
        lda     #$00
        rts
.endproc

; [ CalcTargetDmg, each target: does the rune bite this body? ]
; jsl from CalcTargetDmg in place of its jsl Ot6SeraphHeal, which this ends
; in.  The rune's elements join the hit only on a body they bite
; (Ot6RuneBites): there the hit truly carries the element, and vanilla's
; weak branch below doubles it and chips (Ot6Chip).  On any other body the
; rune adds nothing, so it never turns her Fight into something a body
; drinks.
; a8, either index width, db=$7e; x = the attacker, y = the target.
; Preserves x and y; clobbers A.
.proc Ot6TargetPre
        .a8
        lda     f:$7e0000+OT6_BLADESWING
        and     #$80            ; this target's element chip has not happened
        sta     f:$7e0000+OT6_BLADESWING
        lda     f:$7e0000+OT6_RUNESWING
        beq     @out            ; no rune on this swing
        eor     #$ff
        and     $11a1           ; the swing's own elements again (an earlier
        sta     $11a1           ;   target's verdict is not this one's)
        lda     f:$7e0000+OT6_RUNESWING
        jsr     Ot6RuneBites
        beq     @out
        ora     $11a1
        sta     $11a1
@out:   jml     Ot6SeraphHeal
.endproc

; [ Ot6Chip took a shield from this target: Break Blade takes no second ]
; jsr from Ot6Chip at its decrement.  a8.  Preserves A, X and Y.
.proc Ot6RuneChipMark
        .a8
        pha
        lda     f:$7e0000+OT6_BLADESWING
        ora     #$01
        sta     f:$7e0000+OT6_BLADESWING
        pla
        rts
.endproc

; [ Break Blade: each hit of her weapon takes a shield, whatever the keys ]
; Bum Rush's kind of take (Ot6BumRushTake): one shield a landed hit, keyless.
; A body that keys the weapon's class loses its shield to the class chip
; instead (Ot6ClassChip, which also reveals the key), and one the hit's
; element already chipped (Ot6Chip, OT6_BLADESWING bit 0) loses no second,
; so a hit never takes two.  The gates are the class chip's: a monster, not
; Broken or shieldless (Ot6TakeShields), not wounded or petrified, not a
; resolved heal.
; jsr from Ot6HitJoin before Ot6ClassChip.  a8/i16, y = the target, db=$7e.
; Preserves x and y; clobbers A.
.proc Ot6BreakBladeTake
        .a8
        .i16
        lda     f:$7e0000+OT6_BLADESWING
        bpl     done            ; not a Break Blade swing
        lsr
        bcs     done            ; the element chip took this hit's shield
        tya
        cmp     #$08
        bcc     done            ; a character target: no shields
        lda     $3ee4,y
        bit     #$c0
        bne     done            ; wound/petrify: the hit was theater
        lda     $f2
        lsr
        bcs     done            ; a resolved heal
        lda     f:$7e0000+OT6_ATKCLASS
        beq     @take           ; (classless: nothing keys it)
        bmi     @take           ; (a null-break property: the class chips nothing)
        and     OT6_BP_CLASS,y
        bne     done            ; keyed: the class chip takes this hit's shield
@take:  lda     #$01
        jsr     Ot6TakeShields
done:   rts
.endproc

; [ Break Blade's turns: one spent as each of her actions ends ]
; jsr from Ot6ActionEnd's exit, beside Tint's counter.  The cast sets one
; more than OT6_BREAK_TURNS, since its own action's end counts one down, so
; the blade stands for the three turns of hers that follow, the span a
; three-point Runic stands for.  A fallen character takes no turns, so the
; blade waits on her.  a8/i16, x = the actor, db=$7e.  Preserves x and y.
.proc Ot6RuneActionEnd
        .a8
        .i16
        txa
        cmp     #$08
        bcs     @out
        lda     OT6_BREAKBLADE,x
        beq     @out
        dec     a
        sta     OT6_BREAKBLADE,x
@out:   rts
.endproc

; ------------------------------------------------------------------------------

; [ has the party learned Break Blade? ]  out: carry set = yes.
; a8, any index width, any db.  Preserves X and Y; clobbers A.
.proc Ot6BreakLearned
        .a8
        lda     f:$7e0000+OT6_STAB_SW
        and     #OT6_STAB_BIT
        bne     @yes
        lda     f:$7e0000+OT6_RUIN_SW
        and     #OT6_RUIN_BIT
        bne     @yes
        clc
        rtl
@yes:   sec
        rtl
.endproc

; [ can this caster cast a spell of an element, and what does the cheapest
;   cost? ]
; The caster's battle Magic list ($302c,x: row 0 the esper, rows 1-54 the
; spells this character can cast in this battle, natural and esper-lent, a
; GOGO's the seated party's union) is the list the Magic window draws, so a
; blade row follows an esper swap with no state of its own.  The price is
; the spell's own (Ot6SpellMP: MagicProp's cost through the caster's Gold
; Hairpin or Economizer), not the row's cell, which a pending boost folds.
; in: A = the element's bit index (0-7), X = the caster's entity offset.
; out: carry set = yes, A = the cheapest MP; clear = no such spell, A = 0.
; a8/i16, db=$7e.  Preserves X and Y.  Stack only: it runs from the menu.
.proc Ot6BladeCost
        .a8
        .i16
        phy
        phx
        longa
        and     #$0007
        tax
        shorta0
        lda     f:Ot6RuneBitTbl,x
        pha                     ; the element's bit
        lda     #$ff
        pha                     ; the cheapest so far ($ff: none)
        lda     #54
        pha                     ; [1,s] rows left, [2,s] cheapest, [3,s] the
                                ;   bit, [4,s] the caster (a word), [6,s] Y
        longa
        lda     $04,s
        tax
        lda     $302c,x
        tay                     ; -> the caster's list, row 0
        shorta0
@row:   iny
        iny
        iny
        iny
        lda     a:$0000,y       ; the row's spell
        cmp     #$36
        bcs     @next           ; empty, or not a spell
        pha                     ; [1,s] the spell; the rest one deeper
        longa
        and     #$00ff
        pha
        asl3                    ; id * 8
        sec
        sbc     $01,s           ; id * 7
        asl                     ; id * 14, MagicProp's stride
        tax
        pla
        shorta0
        lda     f:MagicProp+1,x ; its elements
        and     $04,s
        beq     @skip
        longa
        lda     $05,s
        tax                     ; the caster
        shorta0
        lda     $01,s
        jsl     Ot6SpellMP
        cmp     $03,s
        bcs     @skip
        sta     $03,s
@skip:  pla
@next:  lda     $01,s
        dec     a
        sta     $01,s
        bne     @row
        pla                     ; the rows
        pla                     ; the cheapest
        sta     $01,s           ; (over the bit)
        pla
        plx
        ply
        cmp     #$ff
        beq     @none
        sec
        rtl
@none:  lda     #$00
        clc
        rtl
.endproc

; the open window's character: X = its entity offset.  a8/i16, db=$7e.
; clobbers A.
.proc Ot6RuneCaster
        .a8
        .i16
        lda     $62ca
        and     #$03
        asl
        longa
        and     #$00ff
        tax
        shorta0
        rts
.endproc

; ------------------------------------------------------------------------------

; [ open Runic as the Rune Knight's list, the twin of Ot6PaintListOpen ]
; Runic, then a blade row for each element the caster can cast, in element
; bit order, then Break Blade once it is learned, packed down the left
; column and then the right.  Per row: Index = the id, Qty = the price,
; Flags = SELF ($02, the Runic command's own targeting byte), so every row
; takes the cursor Runic always took.  The shell has eight cells and does
; not scroll: Runic, Break Blade and six blades fill it, so a caster with
; more than six castable elements (a GOGO whose party holds all seven that
; player magic has) is not offered the last ones in bit order.  No character
; test: whoever holds the command opens it (a GOGO too, #547), with its own
; castable elements.  Mode w7e6168 = 7.
; entry: jsl from the C1 stub, db=$7e, a8/i16.  clobbers a/x/y.
.proc Ot6RuneListOpen
        .a8
        .i16
        jsr     Ot6PaintPad     ; the eight cells $ff, Qty 0
        lda     #0
        jsr     Ot6PaintCell
        lda     #OT6_RUNE_RUNIC
        sta     $4005,y
        lda     #$02
        sta     $4007,y
        jsl     Ot6BreakLearned
        lda     #8
        bcc     :+
        lda     #7              ; the last cell is Break Blade's
:       pha                     ; the cells the blades may fill up to
        lda     #1
        pha                     ; k, the rows placed
        lda     #0
        pha                     ; [1,s] e, [2,s] k, [3,s] the limit
        jsr     Ot6RuneCaster   ; x = the caster
@elem:  lda     $02,s
        cmp     $03,s
        bcs     @full
        lda     $01,s
        jsl     Ot6BladeCost
        bcc     @nexte
        pha                     ; [1,s] the price, [2,s] e, [3,s] k
        lda     $03,s
        jsr     Ot6PaintCell    ; y = the k-th packed cell
        lda     $03,s
        inc     a
        sta     $03,s
        lda     $02,s
        clc
        adc     #OT6_RUNE_BLADE
        sta     $4005,y
        pla
        sta     $4006,y
        lda     #$02
        sta     $4007,y
@nexte: lda     $01,s
        inc     a
        sta     $01,s
        cmp     #8
        bcc     @elem
@full:  pla                     ; drop e
        jsl     Ot6BreakLearned
        bcc     @done
        lda     $01,s
        jsr     Ot6PaintCell
        lda     #OT6_RUNE_BREAK
        sta     $4005,y
        lda     #OT6_BREAK_MP
        sta     $4006,y
        lda     #$02
        sta     $4007,y
@done:  pla                     ; drop k
        pla                     ; and the limit
        ldy     $62ca
        jsl     Ot6ThiefClamp   ; the cursor on a listed row
        stz     $7ba5           ; force MakeToolsList_04 to re-init the window
        lda     #$04
        sta     $7b9e           ; the tools state machine's draw phase
        lda     #$07
        sta     $6168           ; w7e6168 = 7: the Rune Knight's list
        rtl
.endproc

; [ a row's price as the window draws it, and as the confirm reads it ]
; Ot6KitRowCost's mode-7 arm.  in: A = id.  out: A = the price for the
; caster whose window is open.  a8/i16, db=$7e.  Preserves X and Y.
.proc Ot6RuneRowCost
        .a8
        .i16
        cmp     #OT6_RUNE_BREAK
        bne     :+
        lda     #OT6_BREAK_MP   ; its grey says when it cannot be had
        rtl
:       sec
        sbc     #OT6_RUNE_BLADE
        cmp     #8
        bcs     @free           ; Runic
        phx
        pha
        jsr     Ot6RuneCaster
        pla
        jsl     Ot6BladeCost
        plx
        rtl
@free:  lda     #$00
        rtl
.endproc

; [ the charge at the queue: Ot6AbilityCost's command $0b arm ]
; in: A = the queued id ($3a7b), X = the attacker.  out: A = the price.
; a8/i16, db=$7e.  Preserves X and Y.
;   Runic (and the $00 or $ff of a Runic no list queued): 0, as always;
;   a blade row: the cheapest spell of its element the caster holds;
;   Break Blade: 99 at three points pending, else 0 (a divine taken back
;     does nothing and charges nothing, kits.md "Divines").
.proc Ot6RuneCharge
        .a8
        .i16
        cmp     #OT6_RUNE_BREAK
        bne     @blade
        lda     OT6_BOOST_REVEALED,x
        cmp     #OT6_BREAK_BOOST
        bcc     @free
        lda     #OT6_BREAK_MP
        rtl
@blade: sec
        sbc     #OT6_RUNE_BLADE
        cmp     #8
        bcs     @free
        jml     Ot6BladeCost
@free:  lda     #$00
        rtl
.endproc

; [ the Rune Knight arm of Ot6BushidoRowGrey: a row its gate refuses ]
; Break Blade under three points pending (the divine's one gate).  Read by
; the row's colour and by the confirm (Ot6KitConfirmMP), so a greyed row is
; a refused one.  a8/i16.  in: A = the MP grey, Y = the row's wItemList
; offset.  out: A = A | ($04 if refused).  Preserves X and Y.  rtl.
.proc Ot6RuneRowGrey
        .a8
        .i16
        pha                     ; [1,s] the MP grey
        lda     $4005,y
        cmp     #OT6_RUNE_BREAK
        bne     @white
        phx
        jsr     Ot6RuneCaster
        lda     OT6_BOOST_REVEALED,x
        plx
        cmp     #OT6_BREAK_BOOST
        bcs     @white
        pla
        ora     #$04
        rtl
@white: pla
        rtl
.endproc

; [ R on the Rune Knight's list: a blade row buys nothing with a boost ]
; in: A = the row's id.  out: carry set = refuse.  Preserves A, X and Y.
.proc Ot6RuneNoBoost
        .a8
        cmp     #OT6_RUNE_BLADE
        bcc     @buys           ; Runic: turns
        cmp     #OT6_RUNE_BREAK
        bcs     @buys           ; Break Blade: its gate
        sec
        rtl
@buys:  clc
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ a row's name, for Ot6KitListName (mode 7) ]
; in: A = id, Y = the line buffer offset, $56 = the attribute.  out: carry
; set = drawn (Y past the name); clear = not a row (A, Y unchanged).
; a8/i16, db=$7e.  Preserves X.
.proc Ot6RuneListName
        .a8
        .i16
        pha                     ; [1,s] the id
        sec
        sbc     #OT6_RUNE_RUNIC
        cmp     #OT6_RUNE_IDS
        bcs     @no
        phx
        longa
        and     #$00ff
        pha
        asl
        asl
        clc
        adc     $01,s           ; * 5
        asl                     ; * 10
        tax
        pla
        shorta0
        lda     #10
        pha                     ; [1,s] letters left
@lp:    lda     $56
        xba
        lda     f:Ot6RuneName,x
        jsr     Ot6ListLetter
        inx
        lda     $01,s
        dec     a
        sta     $01,s
        bne     @lp
        pla
        plx
        pla
        sec
        rtl
@no:    pla
        clc
        rtl
.endproc

; [ attack name type 3 for a row: its banner ]
; From Ot6ThiefBannerName for ids $d0-$d9.  in: A = id, a8/i16, db=$7e.
; Writes the name, $00-terminated, at w7e57d5.  clobbers a/x/y.  rtl.
.proc Ot6RuneBannerName
        .a8
        .i16
        sec
        sbc     #OT6_RUNE_RUNIC
        ldy     #$0000
        cmp     #OT6_RUNE_IDS
        bcs     @end
        longa
        and     #$00ff
        tay
        lda     #$0000
@mul:   cpy     #$0000
        beq     @have
        clc
        adc     #OT6_RUNE_BANLEN
        dey
        bra     @mul
@have:  tax
        shorta0
@cp:    lda     f:Ot6RuneBanner,x
        cmp     #$ff
        beq     @end
        sta     $57d5,y
        inx
        iny
        cpy     #OT6_RUNE_BANLEN
        bne     @cp
@end:   lda     #$00
        sta     $57d5,y
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ run the row this Runic action selected ]
;
; jsl from Cmd_0b after its `tyx` and `jsr _c2298a` (the action's props
; cleared), db=$7e, a8/i8.  x = y = the attacker, $b6 = the queued id.  out:
; carry clear = Runic, the stance: Cmd_0b raises it as it always did (the
; Runic row's id is put back to the $ff a vanilla Runic queues); carry set =
; a blade row or Break Blade ran here, and Cmd_0b raises no stance.  Either
; way Cmd_0b ends in ExecSelfAttack: Runic's raised sword, and for a row its
; banner (attack name type 3, Ot6RuneBanner).
;
; A blade row takes no boost: one raised on the command window before the
; row was picked is dropped, never charged (Ot6KeepBoost; R on the row is
; refused, Ot6RuneNoBoost).  Break Blade under a full boost (taken back
; after the pick, or a Mimic's copy short of three) does nothing and costs
; nothing, as every list divine.  A caster who cannot pay the row's MP
; ($3c08 below $3a4c, the cost staged at action load) does nothing here:
; CalcAttackEffect's universal check refuses the cast after this.
;
; A Mimic's copy runs the same way, free, on the copier: Mimic copies the
; action, and the action is self-targeted (as a copy of Runic raises the
; copier's own stance), so a GOGO's copy of a blade row arms GOGO's blade
; with that element, and his copy of Break Blade takes his own full boost.
; Preserves x and y.
.proc Ot6RuneExec
        .a8
        php
        shortai
        .a8
        .i8
        lda     $b6
        cmp     #OT6_RUNE_RUNIC
        bne     :+
        lda     #$ff
        sta     $b6             ; the Runic row: vanilla's queued byte
        bra     @plain
:       bcc     @plain
        cmp     #OT6_RUNE_LAST+1
        bcs     @plain
        cpx     #$08
        bcs     @plain          ; (a monster never queues these)
        cmp     #OT6_RUNE_BREAK
        beq     @break
        jsl     Ot6KeepBoost    ; a blade takes no boost (clobbers A)
        jsr     Ot6RunePays
        bcc     @ran            ; short: nothing done (the fizzle follows)
        phx
        lda     $b6
        sec
        sbc     #OT6_RUNE_BLADE
        tax
        lda     f:Ot6RuneBitTbl,x
        plx
        jsl     Ot6RuneArm      ; y = the attacker
        bra     @ran
@break: lda     OT6_BOOST_REVEALED,x
        cmp     #OT6_BREAK_BOOST
        bcc     @none
        jsl     Ot6BreakLearned
        bcc     @none
        jsr     Ot6RunePays
        bcc     @ran
        lda     #OT6_BREAK_TURNS+1
        sta     OT6_BREAKBLADE,x
        bra     @ran
@none:  lda     #$00            ; under the full boost: nothing done, nothing
        sta     OT6_BOOST_REVEALED,x    ;   charged (priced 0 at the queue)
        stz     $3a4c
        stz     $3a4d
@ran:   lda     #$03            ; attack name type 3 -> Ot6RuneBanner
        sta     $3412
        plp
        sec
        rtl
@plain: plp
        clc
        rtl
.endproc

; can the attacker pay the action's staged MP?  a8/i8, x = the attacker,
; db=$7e.  out: carry set = yes.  Preserves x and y; clobbers A.
.proc Ot6RunePays
        .a8
        .i8
        longa
        lda     $3c08,x         ; the caster's MP ...
        cmp     $3a4c           ; ... against the row's cost
        sep     #$20
        .a8
        rts
.endproc

; ------------------------------------------------------------------------------

; [ the swing's colour ]
; jml from InitWeaponAnim's weapon-palette load (bank C1, through the
; Ot6SwingPal_c1 stub), in place of its jsr LoadSpriteAnimPal, which this
; ends in.  A character's swing at a monster his rune bites (Ot6RuneBites,
; on the pass's first monster target, w7e613e) is drawn in the element's
; colours, the weapon's sprite and the hit on the target both; a Break
; Blade swing at a monster in its own.  The colour is the bite's, not the
; blade's standing state: a swing at a body the rune does nothing to is the
; weapon's own, so the colour comes with the doubled number and the shield
; lost, and a red swing never lands on a body that shrugs fire off.  The
; standing sign is the party window's (Ot6RuneSignStage).  The verdict is
; read here, from the bytes the hit was judged on, and not carried from the
; hit: an action's passes are all computed before its script plays them.
; in: A = the weapon's own palette (w7e626d), a8/i16, db=$7e.  The attacker
; is read as GetAttackerID reads it, from the pass's block at $2c6e ($10 is
; scratch by this point of InitWeaponAnim).
.proc Ot6SwingPal_ext
        .a8
        .i16
        pha
        lda     $62d0           ; (GetAttackerID's other source: not a
        bne     @plain          ;   plain pass)
        lda     $2c6e           ; the pass's flags: bit 7, a monster attacks
        bmi     @plain
        lda     $2c6f           ; the attacker's seat
        and     #$03
        asl
        longa
        and     #$0006
        tax                     ; x = the swinging character
        shorta0
        lda     $613e           ; the pass's monster targets
        beq     @plain
        ldy     #$0008
:       lsr
        bcs     :+
        iny
        iny
        bra     :-
:       lda     OT6_BREAKBLADE,x
        beq     @rune
        ldx     #$0008          ; Break Blade's pair
        bra     @sub
@rune:  lda     OT6_RUNE,x
        beq     @plain
        jsr     Ot6RuneBites
        beq     @plain
        ldx     #$0000
:       lsr
        bcs     @sub
        inx
        bra     :-
@sub:   pla
        lda     f:Ot6SwingHitPalTbl,x
        sta     $626f           ; the hit palette, read next
        lda     f:Ot6SwingPalTbl,x
        jml     f:LoadSpriteAnimPal     ; a C1 rts: back to InitWeaponAnim
@plain: pla
        jml     f:LoadSpriteAnimPal
.endproc

; ------------------------------------------------------------------------------

; [ the standing sign: the rune's icon beside its holder's name ]
;
; The party window's name row is full: six name cells, the boost cell, four
; of HP and six of gauge (MenuTextBufData's 7 + 4 + 6).  The one cell free
; is the name's sixth when the name is shorter (CELES, GOGO and LEO all
; are), so the sign goes there, against the boost cell, and a six-letter
; name shows none (the item lists' class icon makes the same trade,
; Ot6ToolListIcon).  The sign is the element's icon in its colour, the one
; the weakness strip draws, or the sword for a running Break Blade.
;
; This stages row A's sign into the name buffer's sixth cell (w7e5b95 + row
; * 28, the tile row's cell 5), which the menu engine copies to the map with
; the names; Ot6BgHudFlush_ext writes the same cell beside each boost cell,
; so a rune armed between two stagings shows within four frames.  A cell
; that holds a letter is left alone.  Called for each row by Ot6PipStage
; every frame and by Ot6PipGlyph_ext when the engine has just staged a name
; (the cell is then the name's own again).
; in: A = the menu row (0-3).  a8/i16, any db.  Preserves x and y.
OT6_SIGN_CELL = $5b95 + 14 + 10 ; row 0's sixth name cell: tile, then attribute
.proc Ot6RuneSignStage
        .a8
        .i16
        phb
        phx
        phy
        pha
        lda     #$7e
        pha
        plb
        pla
        and     #$03
        pha                     ; the row, kept for the dirty bit
        longa
        and     #$0003
        tax
        shorta0
        lda     $64d6,x         ; menu row -> character slot
        cmp     #$ff
        jeq     @out
        asl
        longa
        and     #$0006
        tay                     ; y = the character
        txa
        asl
        tax
        lda     f:Ot6SignOffTbl,x
        tax                     ; x = the row's offset in the name buffer
        shorta0
        lda     OT6_BREAKBLADE,y
        beq     @rune
        lda     #$21            ; white
        xba
        lda     #$d9            ; the sword (Ot6ClassGlyphTbl's slash)
        bra     @have
@rune:  lda     OT6_RUNE,y
        beq     @none
        ldy     #$0000
:       lsr
        bcs     :+
        iny
        bra     :-
:       phx
        tyx
        lda     f:Ot6ElemPalTbl,x
        ora     #$21
        xba
        lda     f:Ot6ElemGlyphTbl,x
        plx
        bra     @have
@none:  lda     #$21
        xba
        lda     #$ff
@have:  longa
        pha                     ; [1,s] the tile wanted, [2,s] its attribute
        shorta0
        lda     a:OT6_SIGN_CELL,x
        cmp     $01,s
        bne     @differ
        cmp     #$ff
        beq     @same           ; blank as wanted, whatever its attribute
        lda     a:OT6_SIGN_CELL+1,x
        cmp     $02,s
        beq     @same
        bra     @write
@differ:
        cmp     #$ff
        beq     @write          ; a blank cell: the sign's to use
        jsr     Ot6IsSignGlyph
        bcc     @same           ; the name's sixth letter: no room
@write: lda     $01,s
        sta     a:OT6_SIGN_CELL,x
        lda     $02,s
        sta     a:OT6_SIGN_CELL+1,x
        lda     $03,s           ; the row
        phx
        longa
        and     #$0003
        tax
        shorta0
        lda     f:Ot6RuneBitTbl,x
        plx
        tsb     OT6_PIPDIRTY    ; the flush writes this row next
@same:  longa
        pla
        shorta0
@out:   pla                     ; drop the row
        ply
        plx
        plb
        rts
.endproc

; the name buffer's row offsets: row * 28 (7 cells, two lines of two bytes)
Ot6SignOffTbl:
        .word   0, 28, 56, 84

; is this tile one of the sign's?  in: A = the tile.  out: carry set = yes.
; a8/i16.  Preserves A, X and Y.
.proc Ot6IsSignGlyph
        .a8
        .i16
        cmp     #$d9
        beq     @yes
        phx
        ldx     #$0007
:       cmp     f:Ot6ElemGlyphTbl,x
        beq     @yesx
        dex
        bpl     :-
        plx
        clc
        rts
@yesx:  plx
@yes:   sec
        rts
.endproc
