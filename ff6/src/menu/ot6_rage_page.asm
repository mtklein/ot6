; ------------------------------------------------------------------------------
; Included from field_menu.asm at the exact spot this text occupies, so
; emission order is unchanged.
;
; Still bank $C3 ("menu_code"), still under ending_anim.asm's un-popped
; .charmap (menu_text_en.inc:114-121), and still inside field_menu.asm's
; `.if LANG_EN`.  Do not assemble this file on its own.
; ------------------------------------------------------------------------------

; ------------------------------------------------------------------------------
; Gau's rage loadout page: the MenuState_7b shim, at eight rows
;
; Every decision is bank-F0 (Ot6Rage* in ot6_rage.asm); this is tilemap, cursor
; and DMA only, as the Bushido page's shim is.  Two shape differences,
; both forced by Gau's numbers: names come from MonsterName (255 candidates)
; instead of BushidoName (8), and there is no drawn "pool" grid: the L/R
; cycle is the browse, and a LEARNED count stands in for the grid.

MENU_STATE_RAGELOAD = $7c

; menu state $7c: rage loadout configurator, per frame
MenuState_7c:
@rgl:   lda     $4a                     ; self-init sentinel (0 = not yet drawn)
        bne     @run
        jsr     Ot6RageInitC3
        lda     #$01
        sta     $4a
        rts
@run:   lda     #$10
        trb     z45
        jsr     InitDMA1BG1ScreenA
        ldy     #near Ot6RageCursorPos
        jsr     UpdateCursorPos         ; track the cursor sprite to $4e (slot)
        jsl     Ot6RageInput            ; F0: 0 = idle, 1 = redraw, 2 = exit
        cmp     #$02
        beq     @exit
        cmp     #$01
        bne     @done
        jsr     PlayMoveSfx
        jsr     Ot6RageDrawSlots        ; chrome + count stay; redraw the slots
@done:  rts
@exit:  stz     $4a                     ; re-arm self-init for the next entry
        jmp     ReloadSkillsMenu

; ---- init: load the slot cursor, draw, flush both screens ----
Ot6RageInitC3:
        ldy     #near Ot6RageCursorProp
        jsr     LoadCursor
        jsl     Ot6RageOpen             ; F0: cursor to the top slot
        jsr     Ot6RageDrawC3
        ldy     #near Ot6RageCursorPos
        jsr     UpdateCursorPos
        jsr     InitDMA1BG1ScreenA
        jmp     InitDMA1BG3ScreenB

; ---- draw the whole configurator ----
Ot6RageDrawC3:
        jsr     ClearBG1ScreenA
        jsr     ClearBG3ScreenB         ; wipe the caller's BG3 text (skills list)
        lda     #BG1_TEXT_COLOR::BLUE
        sta     zTextColor
        ldy     #near Ot6RageTitleText
        jsr     DrawPosText
        ldy     #near Ot6RageHintText           ; "L/R SWAPS" on row 3
        jsr     DrawPosText
        ldy     #near Ot6RageLearnedText
        jsr     DrawPosText
        lda     #BG1_TEXT_COLOR::DEFAULT
        sta     zTextColor
        jsr     Ot6RagePrice
        jsr     Ot6RageDrawSlots
        jmp     Ot6RageDrawCount

; ---- the flat trance price, stated once on the title row: "8 MP EACH" ----
; Blank under nomp: the label rides the number, so a zero price prints
; nothing rather than a bare "EACH".
;
; The price field is five cells wide and starts at column 16 so that "EACH"
; (a fixed pos_text at 22) keeps its gap at 21; growing rightwards instead
; would render "10 MPEACH".  It is a tail-call to Ot6DanceCost
; (ot6_boost.asm:600-619), Dance's own number rather than a copy of it, so it
; can reach two digits without anyone editing this file.  The title row still
; fits: "RAGE LOADOUT" ends at 14, so 15 is the gap, the price is 16-20, 21
; is the gap, "EACH" is 22-25.
Ot6RagePrice:
        jsl     Ot6RageRowCost          ; F0: A = MP cost (0 under nomp)
        beq     @none                   ; (rtl preserves the lda's Z)
        pha
        lda     #$01                    ; the title row
        sta     $e6
        ldx     #$0010                  ; col 16: "nn MP" is 16..20
        pla
        jsr     Ot6LoadoutDrawCost      ; the one field-menu price drawer
        ldy     #near Ot6RageEachText   ; ... and "EACH" at col 22
        jmp     DrawPosText
@none:  rts

; ---- draw the eight loadout rows (beast name; the price is on the title) ----
;
; The 12-pixel cadence, and why the slots sit on odd tilemap rows in two
; columns.  The EN field-menu window this page lives in does not show BG1
; ScreenA one tile row per eight scanlines: a tilemap row pair is displayed in
; twelve scanlines, the odd row getting eight of them and the even row four.
; Odd rows 1,3,5,..,15 render whole at screen y = 116 + 6*(row-1); even rows
; show only their bottom three scanlines; nothing past row 15 is inside the
; window at all.  Vanilla's own tables agree: every EN cursor list for this
; window is `cursor_pos {x, 116 + n*12}` (skills.asm:125-126, :249-250,
; :292-293), and DrawRageName biases its row by one under `.if LANG_EN`
; (skills.asm:1571-1574) for this reason.
;
; So the window holds eight usable text rows, and the page needs ten (title,
; eight slots, LEARNED).  Two columns of four fits, and it is
; also vanilla's shape for this window (the rage browse is
; `cursor_prop {0,0}, {2,8}`, skills.asm:281-299):
;
;   row  1   RAGE LOADOUT                    8 MP EACH
;   row  3   L/R SWAPS       (the control hint; row 3 was spare)
;   row  5   slot 0 (col 3)  slot 1 (col 16)
;   row  7   slot 2          slot 3
;   row  9   slot 4          slot 5
;   row 11   slot 6          slot 7
;   row 15   LEARNED nnn
;
; The cursor gutter.  Columns 3 and 16 are not free choices: `cursor_pos
; {x,y}` is the top-left of a 16x16 sprite, so a cursor at x owns tilemap
; columns x/8 and x/8+1, and the text it points at must start at x/8 + 2,
; i.e. cursor_x = 8*col - 16.  That is vanilla's rule in every list it draws
; in this window (magic cols 3/16 under 8/112, skills.asm:831,:836 vs
; :125-126; espers 3/17 under 8/120, :1733,:1737 vs :249-250; rage 5/19 under
; 24/136, :1544,:1548 vs :292-293).  This page's right column matches (col 16
; under `cursor_pos {112,...}` is vanilla's magic pair), and the left column
; is {3} under a cursor at x=8, magic's own geometry.
;
; The price is stated once, on the title row, rather than once per row,
; because two ten-cell monster names plus two cursor columns plus two
; four-cell "n MP" fields is 30 columns, and the window's own right border is
; column 30.  The price is flat, so eight copies of the same number would not
; fit, and one copy states the same rule.  Under nomp the cost is 0 and the
; whole "8 MP EACH" group is skipped, label included.
;
; Slot order is the cursor framework's own index, $4b = cols*row + col
; (CalcShortListIndex), so slot even = left column, slot odd = right, and
; row = 5 + (slot & ~1).  Ot6RageCurSlot (ot6_rage.asm) computes the same
; number on the F0 side; the two must not drift.
Ot6RageDrawSlots:
        lda     #BG1_TEXT_COLOR::DEFAULT
        sta     zTextColor
        ldx     #$0000
@lp:    stx     $e2                     ; slot loop var (word: $e2/$e3)
        ; --- geometry from the slot: odd row, left or right column ---
        lda     $e2
        and     #$fe                    ; (slot & ~1) = the row pair
        clc
        adc     #$05                    ; row = 5 + (slot & ~1): 5/7/9/11
        sta     $e6
        lda     $e2
        and     #$01
        beq     :+
        ldx     #$0010                  ; odd slot  -> right column (16)
        bra     :++
:       ldx     #$0003                  ; even slot -> left column (3: the
                                        ;   cursor at x=8 owns columns 1-2)
:       phx                             ; Ot6RageShow kills X
        ; --- the beast, or the empty marker ---
        ; An unset slot draws "- EMPTY -" in BLUE, the page's chrome colour, so
        ; it cannot be mistaken for a beast (every MonsterName is Mixed Case in
        ; the DEFAULT colour).  The colour has to be chosen per row rather than
        ; once for the loop, because which rows are empty changes with the
        ; loadout, and with the collection, since AUTO's window is only as
        ; long as the number of species hunted.
        lda     $e2
        jsl     Ot6RageShow             ; F0: carry set + A = the id to draw
        bcs     @beast
        lda     #BG1_TEXT_COLOR::BLUE
        sta     zTextColor
        lda     #$ff                    ; the blank sentinel
        bra     @name
@beast: pha                             ; park the id across the colour store
        lda     #BG1_TEXT_COLOR::DEFAULT
        sta     zTextColor
        pla
@name:  sta     $e5                     ; -> name value
        plx                             ; X = the name column again
        jsr     Ot6DrawRageName
        ldx     $e2
        inx
        cpx     #$0008                  ; OT6_RAGESLOTS (ot6_memory.inc)
        bcc     @lp
        ; fallthrough, as the SwdTech page's slot loop does

; ---- AUTO / MANUAL, and the control that gets back to AUTO ----
; Row 13, the one row this page never drew on (it uses 1/3/5/7/9/11/15).  The
; mode sits at column 3 and the control at column 16, the page's own two slot
; columns, so the pair lines up under the grid rather than in the middle of
; the row.
;
; Drawn from the tail of the slot redraw for the same reason the SwdTech page
; draws its block there: Ot6RageDrawSlots is the only proc a redraw runs
; (MenuState_7c @run), and the mode is live: the first L/R cycle calls
; Ot6RageSeed and the page is MANUAL from that frame on, and Y clears it back.
; A mode drawn once in Ot6RageDrawC3 would stay at whatever it was on entry,
; which is the state the page failed to report before.
Ot6RageDrawMode:
        jsl     Ot6RageIsAuto           ; F0: carry set = AUTO (all eight bytes 0)
        lda     #$00
        bcs     :+
        lda     #$01                    ; MANUAL
:       sta     $e5                     ; -> Ot6DrawModeWord's selector
        lda     #BG1_TEXT_COLOR::DEFAULT
        sta     zTextColor              ; the mode is data, not chrome
        lda     #$0d                    ; row 13
        sta     $e6
        ldx     #$0003                  ; col 3 (the left slot column)
        jsr     Ot6DrawModeWord         ; the SwdTech page's own mode drawer
        lda     #BG1_TEXT_COLOR::BLUE
        sta     zTextColor              ; ... the control that changes it is chrome
        ldy     #near Ot6RageModeHintText
        jmp     DrawPosText

; ---- draw one monster (rage) name.  in: $e5 = rage id ($ff = unset),
;      $e6 = row, X = col.  The Ot6DrawBushName shape over MonsterName. ----
;
; An unset slot spells "- EMPTY -", which is accurate
; in both of the states that produce a blank row: an AUTO window shorter
; than eight, and a MANUAL slot whose byte is $00.  Ot6RageList skips these
; slots when it builds the battle menu, so an empty row here is an empty
; slot there.  See OT6_RAGE_EMPTY in menu_text_en.inc for the derivation
; and for why "-default-" would have been inaccurate.
Ot6DrawRageName:
        lda     $e6
        jsr     GetBG1TilemapPtr        ; A = row, X = col -> X = tilemap dest
        longa
        txa
        sta     $7e9e89                 ; DrawPosTextBuf position header
        shorta
        lda     $e5
        cmp     #$ff
        beq     @blank
        jsr     GetMonsterNamePtr       ; MonsterName array ptr ($eb/$ef/$f1)
        lda     $e5
        jsr     LoadArrayItem           ; stage the name into $7e9e8b
        jmp     DrawPosTextBuf
@blank: ldx     #$9e8b                  ; the marker is MonsterName::ITEM_SIZE
        stx     hWMADDL                 ;   cells wide, so it still overwrites
        ldx     #$0000                  ;   the full field a name left behind
:       lda     f:Ot6RageEmptyTiles,x   ; (long,X: there is no long,Y mode)
        beq     :+
        sta     hWMDATA
        inx
        bra     :-
:       stz     hWMDATA
        jmp     DrawPosTextBuf

Ot6RageEmptyTiles:      raw_text OT6_RAGE_EMPTY ; "- EMPTY - " + $00,
                        ; encoded via menu_text_en.inc; a bare literal here
                        ; would pick up ending_anim.asm's credits charmap

; ---- draw the LEARNED count (three digits, col 11 of the caption row) ----
; The colour is set here rather than inherited.  Ot6RageDrawSlots picks
; DEFAULT or BLUE per row (the empty marker is chrome), so otherwise whatever
; the last slot happened to be would decide the colour of the collection
; score.  The count is data, so it is always DEFAULT.
Ot6RageDrawCount:
        lda     #BG1_TEXT_COLOR::DEFAULT
        sta     zTextColor
        jsl     Ot6RageCount            ; F0: A = rages known (0..255)
        pha
        lda     #$0f                    ; row 15, the last row the window
                                        ;   shows, and odd (see the cadence
                                        ;   note on Ot6RageDrawSlots).  Must
                                        ;   track OT6_RAGE_LEARNED's own {3,15}
        ldx     #$000b                  ; col 11, just past "LEARNED " (3..9 + 1)
        jsr     GetBG1TilemapPtr
        longa
        txa
        sta     $7e9e89
        shorta
        ldx     #$9e8b
        stx     hWMADDL
        pla                             ; the count
        ldx     #$0000
@h:     cmp     #100                    ; hundreds
        bcc     @h2
        sbc     #100                    ; C set by the cmp, so sbc is exact
        inx
        bra     @h
@h2:    pha
        txa
        clc
        adc     #ZERO_CHAR
        sta     hWMDATA
        pla
        ldx     #$0000
@t:     cmp     #10                     ; tens
        bcc     @t2
        sbc     #10
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

; ---- cursor: two columns of four, on vanilla's 12px cadence ----
; Entries are in the framework's own index order ($4b = 2*row + col), i.e.
; reading order.  y = 116 + n*12 is the EN field menu's text pitch for this
; window, copied from vanilla's own rage/magic/esper cursor tables
; (skills.asm:125-126, :249-250, :292-293); rows 5/7/9/11 are n = 2/3/4/5.
; x = {8, 112} pairs with text columns {3, 16}, since cursor_x = 8*col - 16; see
; the cursor-gutter note on Ot6RageDrawSlots.  Do not move this table to fix an
; overlap; move the text.
Ot6RageCursorProp:
        cursor_prop {0, 0}, {2, 4}, NO_XY_WRAP   ; OT6_RAGECOLS x OT6_RAGEROWS
Ot6RageCursorPos:
        cursor_pos {8,   116 + 2 * 12}   ; row 5:  slot 0, slot 1
        cursor_pos {112, 116 + 2 * 12}
        cursor_pos {8,   116 + 3 * 12}   ; row 7:  slot 2, slot 3
        cursor_pos {112, 116 + 3 * 12}
        cursor_pos {8,   116 + 4 * 12}   ; row 9:  slot 4, slot 5
        cursor_pos {112, 116 + 4 * 12}
        cursor_pos {8,   116 + 5 * 12}   ; row 11: slot 6, slot 7
        cursor_pos {112, 116 + 5 * 12}

Ot6RageTitleText:       pos_text OT6_RAGE_TITLE
Ot6RageHintText:        pos_text OT6_RAGE_HINT
Ot6RageModeHintText:    pos_text OT6_RAGE_MODE_HINT     ; "Y=AUTO" at {16,13}
Ot6RageEachText:        pos_text OT6_RAGE_EACH
Ot6RageLearnedText:     pos_text OT6_RAGE_LEARNED

