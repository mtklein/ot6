; ------------------------------------------------------------------------------
; Included from field_menu.asm at its include site, inside `.if LANG_EN` and
; under ending_anim.asm's un-popped .charmap (menu_text_en.inc:114-121).
; Do not assemble this file on its own.
; ------------------------------------------------------------------------------

; ------------------------------------------------------------------------------
; Strago's lore loadout page: the MenuState shim, at five rows
;
; Every decision is bank-F0 (Ot6Lore* in ot6_lore.asm); this is tilemap,
; cursor and DMA only.  The single-column-of-five shape is the Bushido page's,
; not Gau's two columns: five slots fit the window's odd-row cadence (the
; measured 12px pitch; see Ot6RageDrawSlots' header) with the title, hint and
; LEARNED rows intact, and the freed right column carries what Gau's page
; could not fit: a per-row MP price.  Lore prices are vanilla MagicProp data
; and differ per lore, so the price is per row where the possess-verb pages
; state one flat number on the title.
;
;   row  1   LORE LOADOUT
;   row  3   L/R SWAPS                       Y=AUTO
;   row  5   slot 0 (col 3)                  nn MP (col 16)
;   row  7   slot 1                          nn MP
;   row  9   slot 2                          nn MP
;   row 11   slot 3                          nn MP
;   row 13   slot 4                          nn MP
;   row 15   LEARNED nn                      AUTO / MANUAL
;
; The cursor gutter rule (cursor_x = 8*col - 16) puts the cursor at x = 8 for
; names in column 3, magic's own geometry.  Lore names come from AttackName
; (record 58 onward = attack ids $8b..$a2, the same table the vanilla browse
; reads through skills.asm's @LoreName), ITEM_SIZE 10, so "- EMPTY - " (10
; cells, shared with the rage page) keeps the full-field overwrite property.

MENU_STATE_LORELOAD = $80

inc_lang "text/attack_name_%s.inc"      ; the AttackName scope (guarded; skills
                                        ;   .asm includes the same constants)
Ot6LoreNameBase := AttackName+58*AttackName::ITEM_SIZE

; menu state $80: lore loadout configurator, per frame
MenuState_80:
@lrl:   lda     $4a                     ; self-init sentinel (0 = not yet drawn)
        bne     @run
        jsr     Ot6LoreInitC3
        lda     #$01
        sta     $4a
        rts
@run:   lda     #$10
        trb     z45
        jsr     InitDMA1BG1ScreenA
        ldy     #near Ot6LoreCursorPos
        jsr     UpdateCursorPos         ; track the cursor sprite to $4e (slot)
        jsl     Ot6LoreInput            ; F0: 0 = idle, 1 = redraw, 2 = exit
        cmp     #$02
        beq     @exit
        cmp     #$01
        bne     @done
        jsr     PlayMoveSfx
        jsr     Ot6LoreDrawSlots        ; chrome + count stay; redraw the slots
@done:  rts
@exit:  stz     $4a                     ; re-arm self-init for the next entry
        jmp     ReloadSkillsMenu

; ---- init: load the slot cursor, draw, flush both screens ----
Ot6LoreInitC3:
        ldy     #near Ot6LoreCursorProp
        jsr     LoadCursor
        jsl     Ot6LoreOpen             ; F0: cursor to the top slot
        jsr     Ot6LoreDrawC3
        ldy     #near Ot6LoreCursorPos
        jsr     UpdateCursorPos
        jsr     InitDMA1BG1ScreenA
        jmp     InitDMA1BG3ScreenB

; ---- draw the whole configurator ----
Ot6LoreDrawC3:
        jsr     ClearBG1ScreenA
        jsr     ClearBG3ScreenB         ; wipe the caller's BG3 text (skills list)
        lda     #BG1_TEXT_COLOR::BLUE
        sta     zTextColor
        ldy     #near Ot6LoreTitleText
        jsr     DrawPosText
        ldy     #near Ot6LoreHintText
        jsr     DrawPosText
        ldy     #near Ot6LoreModeHintText
        jsr     DrawPosText
        ldy     #near Ot6LoreLearnedText
        jsr     DrawPosText
        lda     #BG1_TEXT_COLOR::DEFAULT
        sta     zTextColor
        jsr     Ot6LoreDrawSlots
        jmp     Ot6LoreDrawCount

; ---- draw the five loadout rows: name at col 3, the lore's own MP at 16 ----
; Per-row colour discipline as the rage page: a name is data (DEFAULT), the
; empty marker is chrome (BLUE).  The price field is drawn on every row so a
; row that BECOMES empty (a revert shrinking the AUTO window) erases the
; price a fuller loadout left behind -- the same overwrite property the
; 10-cell empty marker keeps for the name field.
Ot6LoreDrawSlots:
        ldx     #$0000
@lp:    stx     $e2                     ; slot loop var (word: $e2/$e3)
        lda     $e2
        asl                             ; row = 5 + slot*2: 5/7/9/11/13
        clc
        adc     #$05
        sta     $e6
        ; --- the lore, or the shared empty marker ---
        lda     $e2
        jsl     Ot6LoreShow             ; F0: carry set + A = the id to draw
        bcs     @lore
        lda     #BG1_TEXT_COLOR::BLUE
        sta     zTextColor
        lda     #$ff                    ; the blank sentinel
        bra     @name
@lore:  pha                             ; park the id across the colour store
        lda     #BG1_TEXT_COLOR::DEFAULT
        sta     zTextColor
        pla
@name:  sta     $e5                     ; -> name value ($ff = empty)
        ldx     #$0003                  ; col 3 (cursor at x=8 owns 1-2)
        jsr     Ot6DrawLoreName
        ; --- the price, or its eraser ---
        lda     #BG1_TEXT_COLOR::DEFAULT
        sta     zTextColor              ; the price is data even on chrome rows
        lda     $e5
        cmp     #$ff
        beq     @nocost
        jsl     Ot6LoreRowCost          ; F0: A = the lore's vanilla MP cost
        ldx     #$0010                  ; col 16: "nn MP" is 16..20
        jsr     Ot6LoadoutDrawCost      ; the one field-menu price drawer
        bra     @next
@nocost:
        lda     $e6                     ; blank the 5-cell price field so a
        ldx     #$0010                  ;   revert erases a stale number
        jsr     Ot6LoreBlankCost
@next:  ldx     $e2
        inx
        cpx     #$0005                  ; OT6_LORESLOTS (ot6_memory.inc; the
        bcc     @lp                     ;   menu object cannot include it)
        ; fallthrough: the mode is live (first L/R goes MANUAL, Y comes back)
Ot6LoreDrawMode:
        jsl     Ot6LoreIsAuto           ; F0: carry set = AUTO (all five zero)
        lda     #$00
        bcs     :+
        lda     #$01                    ; MANUAL
:       sta     $e5                     ; -> Ot6DrawModeWord's selector
        lda     #BG1_TEXT_COLOR::DEFAULT
        sta     zTextColor              ; the mode is data, not chrome
        lda     #$0f                    ; row 15, beside the LEARNED count
        sta     $e6
        ldx     #$0010                  ; col 16 (the price column, re-used)
        jmp     Ot6DrawModeWord         ; the SwdTech page's own mode drawer

; ---- draw one lore name.  in: $e5 = lore id ($ff = empty), $e6 = row,
;      X = col.  The Ot6DrawRageName shape over AttackName's lore records. ----
Ot6DrawLoreName:
        lda     $e6
        jsr     GetBG1TilemapPtr        ; A = row, X = col -> X = tilemap dest
        longa
        txa
        sta     $7e9e89                 ; DrawPosTextBuf position header
        shorta
        lda     $e5
        cmp     #$ff
        beq     @blank
        ldy     #AttackName::ITEM_SIZE  ; the vanilla browse's own pointer
        sty     $eb                     ;   triple (skills.asm _c35266), aimed
        ldy     #near Ot6LoreNameBase   ;   at the lore records
        sty     $ef
        lda     #^Ot6LoreNameBase
        sta     $f1
        lda     $e5
        jsr     LoadArrayItem           ; stage the name into $7e9e8b
        jmp     DrawPosTextBuf
@blank: ldx     #$9e8b                  ; the rage page's 10-cell marker: same
        stx     hWMADDL                 ;   field width, same overwrite property
        ldx     #$0000
:       lda     f:Ot6RageEmptyTiles,x
        beq     :+
        sta     hWMDATA
        inx
        bra     :-
:       stz     hWMDATA
        jmp     DrawPosTextBuf

; ---- blank the 5-cell price field.  in: A = row, X = col ----
Ot6LoreBlankCost:
        jsr     GetBG1TilemapPtr
        longa
        txa
        sta     $7e9e89
        shorta
        ldx     #$9e8b
        stx     hWMADDL
        ldy     #$0005
        lda     #$ff                    ; the menu's blank tile
:       sta     hWMDATA
        dey
        bne     :-
        stz     hWMDATA
        jmp     DrawPosTextBuf

; ---- draw the LEARNED count (two digits: the collection is 24 lores) ----
Ot6LoreDrawCount:
        lda     #BG1_TEXT_COLOR::DEFAULT
        sta     zTextColor
        jsl     Ot6LoreCount            ; F0: A = lores known (0..24)
        pha
        lda     #$0f                    ; row 15; must track OT6_LORE_LEARNED
        ldx     #$000b                  ; col 11, just past "LEARNED "
        jsr     GetBG1TilemapPtr
        longa
        txa
        sta     $7e9e89
        shorta
        ldx     #$9e8b
        stx     hWMADDL
        pla                             ; the count
        ldx     #$0000
@t:     cmp     #10                     ; tens
        bcc     @t2
        sbc     #10                     ; C set by the cmp, so sbc is exact
        inx
        bra     @t
@t2:    pha
        txa
        clc
        adc     #ZERO_CHAR
        sta     hWMDATA
        pla
        clc
        adc     #ZERO_CHAR              ; ones
        sta     hWMDATA
        stz     hWMDATA
        jmp     DrawPosTextBuf

; ---- cursor: one column of five, on vanilla's 12px cadence ----
; y = 116 + n*12 for rows 5/7/9/11/13 (n = 2..6); x = 8 pairs with text
; column 3 (cursor_x = 8*col - 16).
Ot6LoreCursorProp:
        cursor_prop {0, 0}, {1, 5}, NO_XY_WRAP   ; OT6_LORECOLS x OT6_LOREROWS
Ot6LoreCursorPos:
        cursor_pos {8, 116 + 2 * 12}    ; row 5:  slot 0
        cursor_pos {8, 116 + 3 * 12}    ; row 7:  slot 1
        cursor_pos {8, 116 + 4 * 12}    ; row 9:  slot 2
        cursor_pos {8, 116 + 5 * 12}    ; row 11: slot 3
        cursor_pos {8, 116 + 6 * 12}    ; row 13: slot 4

Ot6LoreTitleText:       pos_text OT6_LORE_TITLE
Ot6LoreHintText:        pos_text OT6_LORE_HINT
Ot6LoreModeHintText:    pos_text OT6_LORE_MODE_HINT
Ot6LoreLearnedText:     pos_text OT6_LORE_LEARNED
