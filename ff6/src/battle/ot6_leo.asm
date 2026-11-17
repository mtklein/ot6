; ------------------------------------------------------------------------------
; #552: Gogo is General Leo (docs/design/leo-reveal.md)
;
; An optional scene at Leo's grave in the World of Ruin's Thamasa, with Gogo
; in the party, reveals that Gogo is Leo.  The slot keeps actor $0C, so
; Mimic, the Status-screen command picker, the final battle's order and
; everything else keyed on Gogo keep working; the scene's own commands
; (char_name, obj_gfx, obj_pal) give the record Leo's name, sprite and
; palette, and the rest follows from event switch $00E0 (OT6_LEO_FLAG):
;
;   Ot6LeoReveal      event command $9f: the better of Gogo's and Leo's
;                     vigor, speed, stamina and magic power, written once;
;                     Leo's higher base HP added to max HP; the switch.
;   Ot6LeoBattleRow   UpdateEquip: battle power, defense, magic defense,
;                     evade and magic block from Leo's CharProp row.
;   Ot6LeoActorMask   UpdateEquipBattle: in battle the slot can equip what
;                     Gogo can and Leo's own set (bit 15, the Merit Award's).
;
; The menu's equip masks, the Shock entry in the picker, the shop's sprite,
; the vehicle frames and the ending read the switch where they are.
; ------------------------------------------------------------------------------

OT6_LEO_GOGO_REC = CHAR_PROP::GOGO * $25        ; Gogo's record, from $1600
OT6_LEO_GOGO_ROW = CHAR_PROP::GOGO * $16        ; CharProp rows, 22 bytes
OT6_LEO_LEO_ROW = CHAR_PROP::LEO * $16

; ------------------------------------------------------------------------------

; [ event command $9f: the reveal's stats and switch ]
;
; jsl from EventCmd_9f (field, any data bank).  Once only: a second run (the
; switch already set) changes nothing, so the HP bonus is never paid twice.
; Each of vigor, speed, stamina and magic power ($161a-$161d) becomes the
; higher of the record's and Leo's CharProp value; OT6 never grows these
; four (esper bonuses fold in at UpdateEquip), so the write is the stat for
; good.  Max HP and MP: Leo's row starts higher on HP (50 against 36) and
; lower on MP (10 against 12); levels add the same to both, so the record
; takes the positive difference of each base (HP +14, MP nothing), capped
; at 9999/999 with the boost bits (14-15) kept, and current HP/MP gain the
; same.  Preserves A, X, Y and the flags' widths.

.proc Ot6LeoReveal
        php
        phb
        longi
        shorta
        pha
        phx
        phy
        lda     #$7e
        pha
        plb
        lda     f:OT6_LEO_FLAG
        and     #OT6_LEO_BIT
        bne     Done                    ; revealed already: nothing again
        ldy     #OT6_LEO_GOGO_REC
        ldx     #0
Stat:   lda     f:CharProp+OT6_LEO_LEO_ROW+6,x
        cmp     $161a,y
        bcc     :+
        sta     $161a,y                 ; the higher of the two
:       iny
        inx
        cpx     #4
        bne     Stat
        ldy     #OT6_LEO_GOGO_REC
        ldx     #0                      ; HP: CharProp+0, record $1609/$160b
        jsr     Grow
        ldy     #OT6_LEO_GOGO_REC + 4   ; MP: CharProp+1, record $160d/$160f
        ldx     #1
        jsr     Grow
        lda     f:OT6_LEO_FLAG
        ora     #OT6_LEO_BIT
        sta     f:OT6_LEO_FLAG
Done:   ply
        plx
        pla
        plb
        plp
        rtl

; X = 0 (HP) or 1 (MP), Y = the record plus 0 or 4.  A 8-bit in and out.
; The gain and the new base ride the stack (no scratch RAM in the field).
Grow:   lda     f:CharProp+OT6_LEO_LEO_ROW,x
        sec
        sbc     f:CharProp+OT6_LEO_GOGO_ROW,x
        bcc     GrowDone                ; Gogo's base is the higher: keep it
        beq     GrowDone
        longa
        and     #$00ff
        pha                             ; 3,s once the base is pushed: the gain
        lda     $160b,y                 ; max: base | boost bits 14-15
        and     #$3fff
        clc
        adc     1,s
        jsr     Cap
        pha                             ; 1,s: the new base
        lda     $160b,y
        and     #$c000
        ora     1,s
        sta     $160b,y
        lda     $1609,y                 ; current: up by the gain (the boosted
        clc                             ;   max rose by at least as much)
        adc     3,s
        jsr     Cap
        sta     $1609,y
        pla
        pla
        shorta
GrowDone:
        rts

; A 16-bit: at most 9999 (X = 0, HP) or 999 (X = 1, MP)
.a16
Cap:    cpx     #0
        bne     :+
        cmp     #10000
        bcc     :++
        lda     #9999
        rts
:       cmp     #1000
        bcc     :+
        lda     #999
:       rts
.a8
.endproc  ; Ot6LeoReveal

; ------------------------------------------------------------------------------

; [ battle stats from Leo's row ]
;
; jsl from UpdateEquip (battle_main.asm), in place of vanilla's loads of
; battle power, defense, magic defense, evade and magic block from the
; actor's CharProp row.  X = the actor's row offset (16-bit, as UpdateEquip
; leaves it), DB = $7e, A 8-bit.  For the revealed slot (actor $0C, switch
; set) the five come from Leo's row, every one higher than Gogo's (60/63/41/
; 22/21 against 13/39/25/10/6); the run factor stays Gogo's (Leo's is low),
; read by the caller from the unchanged X.  Used by the menu's stats and the
; battle's alike.  Preserves X.

.proc Ot6LeoBattleRow
        php
        longi
        phx
        cpx     #OT6_LEO_GOGO_ROW
        bne     :+
        lda     f:OT6_LEO_FLAG
        and     #OT6_LEO_BIT
        beq     :+
        ldx     #OT6_LEO_LEO_ROW
:       lda     f:CharProp+10,x         ; battle power
        sta     $11ac
        sta     $11ad
        longa
        lda     f:CharProp+11,x         ; defense & magic defense
        sta     $11ba
        lda     f:CharProp+13,x         ; evade & magic block
        shorta
        sta     $11a8
        xba
        sta     $11aa
        plx
        plp
        rtl
.endproc  ; Ot6LeoBattleRow

; ------------------------------------------------------------------------------

; [ in-battle equippability ]
;
; jsl from UpdateEquipBattle (battle_main.asm), in place of vanilla's
; `asl $3a21,x / asl3 / ror $3a21,x`, which copies the Merit Award's bit
; (relic effects 4, bit 5, in A) into bit 15 of the slot's actor mask
; $3a20.  The in-battle equip lists test an item's equip word against that
; mask, and bit 15 is Leo's own (actor 15) as well as the Merit Award's:
; the revealed slot (actor $0C, $3ed8,x) sets it too, so in battle he can
; take up what Gogo can and Leo's whole set, as in the Equip menu.  X = the
; entity offset (either width), A 8-bit, DB = $7e.

.proc Ot6LeoActorMask
        php
        asl
        asl
        asl                             ; carry: the Merit Award
        lda     #0
        rol
        pha
        lda     $3ed8,x                 ; actor
        cmp     #CHAR_PROP::GOGO
        bne     :+
        lda     f:OT6_LEO_FLAG
        and     #OT6_LEO_BIT
        beq     :+
        pla
        lda     #1
        pha
:       pla
        lsr                             ; carry: the bit
        asl     $3a21,x
        ror     $3a21,x
        plp
        rtl
.endproc  ; Ot6LeoActorMask
