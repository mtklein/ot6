; ------------------------------------------------------------------------------
; OT6: the Dragoon Boots' spear permit (#567)
;
; While a character wears the Dragoon Boots, every spear is equippable by
; that character.  The spears are vanilla's lance group, item ids $1D-$24
; (Mithril Pike, Trident, Stout Spear, Partisan, Pearl Lance, Gold Lance,
; Aura Lance, Imp Halberd); the Imp Halberd's own word already names every
; actor but Umaro.  The permit reaches actors 0-12 (Terra to Gogo): each has
; a weapon hand under vanilla's rules (Gau's is the Imp Halberd, Gogo's a
; rod or the like), and Umaro (13), whose Bone Club the game never lets go
; (the Equip menu is closed to him), gets nothing.  The guests in blocks 14
; and 15 are left to their vanilla rules.
;
; Every check of an item's equip word against a character goes through
; Ot6EquipWord in place of vanilla's `lda f:ItemProp+1,x`: the Equip menu's
; lists and Optimum (equip.asm), the shop's marks (shop.asm), the Item
; menu's "can be used by" names (item.asm) and the battle inventory's
; per-slot equippability (battle_main.asm LoadItemProp, ot6_thief.asm).
; Taking the boots off is caught by the relic menu's reequip check
; (equip.asm CheckReequipRelics, whose body is Ot6ReequipRelics below), which
; treats the Dragoon Boots as vanilla treats the Genji Glove, Gauntlet and
; Merit Award.
; ------------------------------------------------------------------------------

; the permit's data, read by Ot6EquipWord and by the test harness
; (tools/tests/lib/ot6_field.lua): the first and last spear, the relic that
; lends them, and the last actor it reaches.
Ot6SpearPermit:
        .byte   ITEM::MITHRIL_PIKE
        .byte   ITEM::IMP_HALBERD
        .byte   ITEM::DRAGOONBOOTS
        .byte   CHAR_PROP::GOGO

; [ an item's equip word, with the spear permit ]
; jsl in place of `lda f:ItemProp+1,x`.  in: X = the item's ItemProp offset
; (id * 30), 16-bit index.  out: A (16-bit) = the item's equip word, with
; the bit of every actor 0-12 who wears the Dragoon Boots added when the
; item is a spear.  The actor is read from each of the 16 character
; blocks' first byte, not assumed from the block's place: before the
; recruits arrive, blocks hold guests (block 2 holds actor $12 at
; banon_joined).  Callers run a16/i16; any data bank (the char blocks are
; read long).  Preserves X and Y.
.proc Ot6EquipWord
        php
        longai
        phy
        phx
        lda     f:ItemProp+1,x
        pha                             ; 1,s word, 3,s X, 5,s Y
        lda     f:Ot6SpearPermit        ; first spear
        and     #$00ff
        jsr     Times30
        cmp     3,s
        beq     @spear
        bcs     @done                   ; X below the first spear
        lda     f:Ot6SpearPermit+1      ; last spear
        and     #$00ff
        jsr     Times30
        cmp     3,s
        bcc     @done                   ; X past the last spear
@spear: ldy     #16                     ; Y = character blocks to scan
        ldx     #0                      ; X = the block's offset
@block: shorta
        lda     f:$7e1600+$23,x         ; relic 1
        cmp     f:Ot6SpearPermit+2
        beq     @wears
        lda     f:$7e1600+$24,x         ; relic 2
        cmp     f:Ot6SpearPermit+2
        bne     @next
@wears: lda     f:$7e1600,x             ; the block's actor
        cmp     f:Ot6SpearPermit+3
        beq     @lend
        bcs     @next                   ; past the last actor (Umaro, guests)
@lend:  longa
        and     #$000f
        phx
        tax
        lda     #1
:       dex
        bmi     :+
        asl
        bra     :-
:       plx
        ora     1,s
        sta     1,s                     ; the actor's bit into the word
@next:  longa
        txa
        clc
        adc     #$0025                  ; next character block
        tax
        dey
        bne     @block
@done:  pla
        plx
        ply
        plp
        rtl

; A = A * 30 (16-bit).  uses one stack word.
Times30:
        asl                             ; 2n
        pha
        asl
        asl
        asl
        asl                             ; 32n
        sec
        sbc     1,s                     ; 30n
        sta     1,s
        pla
        rts
.endproc  ; Ot6EquipWord

; ------------------------------------------------------------------------------

; [ check for relics requiring reequip ]
; jsl from CheckReequipRelics (menu/equip.asm), whose vanilla body this is,
; with the Dragoon Boots added to vanilla's three relics: on leaving the Relic
; menu, when the relics changed and the old pair (zb0/zb1, $b0/$b1) or the new
; one ($0023,y/$0024,y) holds one of Ot6ReequipRelicTbl's, the menu re-equips
; the character (Optimum, or Empty, by the Config setting), which is how a
; spear the boots lent comes off with them.  in: Y = the character's data
; pointer (GetSelCharPropPtr), a8, the menu's direct page and data bank.
; out: A = 1 to re-equip, else 0.  Preserves X and Y.
Ot6ReequipRelicTbl:
        .byte   ITEM::GENJI_GLOVE
        .byte   ITEM::GAUNTLET
        .byte   ITEM::MERIT_AWARD
        .byte   ITEM::DRAGOONBOOTS

.proc Ot6ReequipRelics
        .a8
        lda     $0023,y
        cmp     $b0
        bne     @changed
        lda     $0024,y
        cmp     $b1
        beq     @no                     ; the relics did not change
@changed:
        lda     $b0                     ; the old pair
        jsr     Listed
        bcs     @yes
        lda     $b1
        jsr     Listed
        bcs     @yes
        lda     $0023,y                 ; the new pair
        jsr     Listed
        bcs     @yes
        lda     $0024,y
        jsr     Listed
        bcs     @yes
@no:    lda     #0
        rtl
@yes:   lda     #1
        rtl

; carry set when A (8-bit) is one of Ot6ReequipRelicTbl's relics
Listed:
        cmp     f:Ot6ReequipRelicTbl
        beq     :+
        cmp     f:Ot6ReequipRelicTbl+1
        beq     :+
        cmp     f:Ot6ReequipRelicTbl+2
        beq     :+
        cmp     f:Ot6ReequipRelicTbl+3
        beq     :+
        clc
        rts
:       sec
        rts
.endproc  ; Ot6ReequipRelics

.a8
.i16
