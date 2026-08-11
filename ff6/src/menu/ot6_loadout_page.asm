; ------------------------------------------------------------------------------
; Split out of field_menu.asm, which is otherwise vanilla FF6 disassembly.
; Included from field_menu.asm at the exact spot this text used to occupy, so
; emission order is unchanged: ff6-en.sfc CRC32 0x2E9B5A7F and
; ff6-en-nomp.sfc 0xE8978806 are both byte-identical across the extraction.
;
; Still bank $C3 ("menu_code"), still under ending_anim.asm's un-popped
; .charmap (menu_text_en.inc:114-121, issue #39), and still inside
; field_menu.asm's `.if LANG_EN`.  Do not assemble this file on its own.
; ------------------------------------------------------------------------------

; ==============================================================================
; Bushido loadout configurator (issue #8 Layer B): thin C3 shim over bank F0
;
; Skills -> SwdTech opens this in place of the vanilla browse list: the browse
; list only named the learned techs, and this names them too (the LEARNED pool)
; beside the four editable boost slots, so nothing is lost.  Every decision
; (seed-from-auto, each slot's validated tech, assign/cycle, revert, and the
; write to $1e1d) is made by the OT6 bank-F0 procs jsl'd below; the code here
; does only the tilemap / cursor / DMA framework work that must run in the
; menu bank.
;
;   Up / Down   move the cursor over the four boost slots (0x..3x)
;   L / R       cycle the cursored slot through the LEARNED techs (first edit
;               flips the loadout to MANUAL)
;   Y           revert to AUTO (reseed the slots from the moving window).  Y and
;               not Select: FF6's default pad config aliases physical Select onto
;               the R bit, so it cannot be told apart from the R-shoulder cycle.
;   B           save-and-exit (writes are already live in the checksummed block)
;
; MP cost is priced through Ot6LoadoutCost (returns 0 under nomp, so that build
; draws no number; the shared menu object links against either battle).
; ------------------------------------------------------------------------------


MENU_STATE_LOADOUT = $7b

; menu state $7b: loadout configurator, per frame
MenuState_7b:
@ldo:   lda     $4a                     ; self-init sentinel (0 = not yet drawn)
        bne     @run
        jsr     Ot6LoadoutInitC3
        lda     #$01
        sta     $4a
        rts
@run:   lda     #$10
        trb     z45
        jsr     InitDMA1BG1ScreenA
        ldy     #near Ot6LoadoutCursorPos
        jsr     UpdateCursorPos         ; track the cursor sprite to $4e (slot)
        jsl     Ot6LoadoutInput         ; F0: 0 = idle, 1 = redraw, 2 = exit
        cmp     #$02
        beq     @exit
        cmp     #$01
        bne     @done
        jsr     PlayMoveSfx
        jsr     Ot6LoadoutDrawSlots     ; labels + pool stay; redraw the slot column
@done:  rts
@exit:  stz     $4a                     ; re-arm self-init for the next entry
        jmp     ReloadSkillsMenu

; ---- init: load the slot cursor, seed + draw, flush both screens ----
Ot6LoadoutInitC3:
        ldy     #near Ot6LoadoutCursorProp
        jsr     LoadCursor
        jsl     Ot6LoadoutOpen          ; F0: reset the slot cursor to the top slot
        jsr     Ot6LoadoutDrawC3
        ldy     #near Ot6LoadoutCursorPos
        jsr     UpdateCursorPos
        jsr     InitDMA1BG1ScreenA
        jmp     InitDMA1BG3ScreenB

; ---- draw the whole configurator ----
Ot6LoadoutDrawC3:
        jsr     ClearBG1ScreenA
        jsr     ClearBG3ScreenB         ; wipe the caller's BG3 text (skills list)
        lda     #BG1_TEXT_COLOR::BLUE
        sta     zTextColor
        ldy     #near Ot6LoadoutTitleText
        jsr     DrawPosText
        ldy     #near Ot6LoadoutHintText        ; #44: "L/R SWAPS", blue chrome
        jsr     DrawPosText
        ldy     #near Ot6LoadoutPoolText
        jsr     DrawPosText
        lda     #BG1_TEXT_COLOR::DEFAULT
        sta     zTextColor
        ldy     #near Ot6LoadoutLbl1Text
        jsr     DrawPosText
        ldy     #near Ot6LoadoutLbl2Text
        jsr     DrawPosText
        ldy     #near Ot6LoadoutLbl3Text
        jsr     DrawPosText
        jsr     Ot6LoadoutDrawSlots
        jmp     Ot6LoadoutDrawPool

; ---- draw the three boost-slot rows (tech name + MP cost) ----
; issue #38: every Bushido tech costs at least 1 BP, so the page shows 1x/2x/3x
; and the 0x row is gone.  Row i (0..2) draws word slot i+1; the stored format
; is untouched (four 3-bit fields at $1e1d), and slot 0 is never read.
;
; The 12-pixel cadence (issue #43), and why every row on this page is odd.
; The EN field-menu window does not show BG1 ScreenA one tile row per eight
; scanlines: a tilemap row pair is displayed in twelve scanlines, the odd row
; getting eight of them and the even row four, and nothing past row 15 is
; inside the window at all.  Measured with a per-row glyph ruler poked into the
; shadow (tools/tests/probe_ragegeom.lua): odd rows 1,3,5,..,15 render whole at
; screen y = 116 + 6*(row-1); even rows show only their bottom three scanlines.
; Vanilla's own tables agree: every EN cursor list for this
; window is `cursor_pos {x, 116 + n*12}` (skills.asm:125-126, :249-250,
; :292-293) and DrawRageName biases its row `.if LANG_EN` (skills.asm:1571-1574).
;
; This page shipped with its slots on even rows 4/6/8 and its LEARNED grid on
; 15/17/19/21, so every tech name was a four-scanline strip beside a
; full-height title and three of the pool's four rows were off the bottom of
; the window.  #39 fixed the page's glyphs; this change fixes its geometry.
; The layout is now vanilla's own shape for this window, eight usable rows:
;
;   row  1   SWDTECH  L/R SWAPS  LEARNED  (cols 3 / 11 / 22)
;   row  3   1x<tech, 12 cells @5>  nn MP @18
;   row  5   2x  ...
;   row  7   3x  ...
;   row  9   pool cell 0 (col 3)   pool cell 4 (col 17)
;   row 11   pool cell 1           pool cell 5
;   row 13   pool cell 2           pool cell 6
;   row 15   pool cell 3           pool cell 7
;
; The page needs nine rows and the window has eight, so the pool's caption
; sits on the title row, the same fix the Rage page used for its price
; line.  The title row is the one row where a second blue chrome word
; cannot be misread as a slot's data.
;
; #44: a third word sits on the title row too, the L/R control hint.  With all
; eight rows in use, the room came from the title: "BUSHIDO LOADOUT" (cols 3-17)
; became "SWDTECH" (3-9), which is also the name every other EN string uses for
; this skill and the name of the row the player picked to get here.  The only
; other free run on the page is columns 23-29 of the three slot rows, seven
; cells wide and split across three rows, and nothing legible fits there.  See
; OT6_LOADOUT_HINT in menu_text_en.inc.
;
; The cursor gutter (#43, third round), and why every column above is one
; further right than it shipped.  `cursor_pos {x,y}` is the top-left of a 16x16
; sprite, so the cursor at x=8 owns tilemap columns 1 and 2, and it drew
; over the "1" of "1x" at column 2.  Vanilla's rule is
; cursor_x = 8*col - 16 in every case: magic 3/16 under 8/112
; (skills.asm:831,:836 vs :125-126), espers 3/17 under 8/120 (:1733,:1737 vs
; :249-250), rage 5/19 under 24/136 (:1544,:1548 vs :292-293), config col 14
; under 96 (config.asm:50).  The cursor table below was already vanilla's;
; the text was one column too far left.  Everything shifts by one and the
; window's own right border is still column 30.  The pool's right column moves
; 16 -> 17 with it, keeping the two-column gutter between two full-width names
; ("Quadra Slice" fills all twelve cells); a 12-cell name at 17 ends at 28,
; still inside the frame.
;
; The column budget (issue #56), and where the price field's second digit came
; from.  #45's rescale made seven of eight SwdTech prices two digits, so the
; price field had to grow from four cells to five, and this row had none spare.
; Columns 3..29 is 27 cells and the row wanted 28:
;
;   label 2 + gap 1 + name 12 + gap 1 + price 5 + gap 1 + mode 6  =  28
;
; Four of those six terms are fixed by something outside this page and cannot
; be the donor: the left margin is column 3 because the cursor sprite owns 1-2
; (above); the name is a 12-byte BushidoName record drawn whole, pads and all,
; and "Quadra Slice" uses every cell of it; the mode words are six cells and
; already end on 29, the last column before the border; and the price is five
; because "nn MP" is five.  Of the two gaps, the one at 23 is required
; (#49 measured "7 MPMANUAL" on screen without it), and so is the one before
; the price, which is the only thing keeping "Quadra Slice" off "30 MP".
;
; So the donor is the gap between the tier label and the name: names start at
; column 5 now, directly after "1x".  That gap is the one whose two
; sides cannot be confused for each other, a digit and a lowercase 'x' against
; a capitalised tech name, whereas the other two gaps separate tokens that read
; as the same kind.  Screenshots of both a one-digit and a two-digit
; price are in the #56 report.
;
;   3-4 "1x" | 5..16 name | 17 gap | 18..22 "nn MP" | 23 gap | 24..29 mode
Ot6LoadoutDrawSlots:
        lda     #BG1_TEXT_COLOR::DEFAULT
        sta     zTextColor
        ldx     #$0000
@lp:    stx     $e2                     ; row loop var (0..2)
        txa
        inc     a                       ; row i -> word slot i+1 (#38)
        jsl     Ot6LoadoutSlotTech      ; F0: A = validated tech for this slot
        sta     $e5                     ; -> name value
        lda     $e2
        asl                             ; row = 3 + i*2: odd rows 3/5/7 (#43)
        clc
        adc     #$03
        sta     $e6
        ldx     #$0005                  ; name column (5: right after "1x" at
        jsr     Ot6DrawBushName         ;   3-4; see the budget note above)
        lda     $e5
        clc
        adc     #$55                    ; tech index -> attack id
        jsl     Ot6LoadoutCost          ; F0: A = MP cost (0 under nomp)
        ldx     #$0012                  ; cost column (18: "nn MP" is 18..22,
        jsr     Ot6LoadoutDrawCost      ;   right-aligned; 17 is the gap)
        ldx     $e2
        inx
        cpx     #$0003
        bcc     @lp
        ; fallthrough to #49: the mode block is drawn last on purpose, see below

; ---- #49: AUTO / MANUAL, and the control that gets back to AUTO ----
; The page's one free block is columns 23-29 of the three slot rows (surveyed in
; issue #49); the mode takes row 3 and the control that changes it row 5, so the
; two read as a pair.  Column 23 is spent as a separator, because the slot's
; price field abuts it and a block starting at 23 renders the row as "7 MPMANUAL"
; (measured, the first screenshot of that change), so the six cells run 24-29,
; up to but not into the window's border column 30.
;
; #56 widened the price field to "nn MP" and moved it left to 18-22 rather than
; letting it grow rightwards into 23, so this block and its separator are
; untouched by that change; the donor column came off the label/name gap on the
; other side of the row (the budget note over Ot6LoadoutDrawSlots).
;
; Drawn here, at the tail of the slot redraw, rather than from
; Ot6LoadoutDrawC3 with the other chrome.  Two reasons:
;   * the mode is live: the first L/R cycle flips AUTO -> MANUAL and Y flips it
;     back, and Ot6LoadoutDrawSlots is the only thing that runs on a redraw
;     (MenuState_7b @run), so a mode drawn at init would keep reporting the
;     state the page was opened in for as long as the player stayed on it;
;   * Ot6LoadoutDrawCost's zero-cost arm blanks the full five-cell price field,
;     which under nomp (every row prices 0) is drawn on every redraw.  It now
;     stops at column 22; before #56 it started at 19 and ran through 23, into
;     the first cell of a block drawn earlier in the frame.  Drawing
;     after the slot loop is what makes the ordering safe in all cases.
; The hint is redrawn every time too; six cells is not worth a second code path
; to skip, and redrawing removes the ordering hazard.
Ot6LoadoutDrawMode:
        jsl     Ot6LoadoutIsAuto        ; F0: carry set = AUTO (the packed word)
        lda     #$00
        bcs     :+
        lda     #$01                    ; MANUAL
:       sta     $e5                     ; -> Ot6DrawModeWord's selector
        lda     #BG1_TEXT_COLOR::DEFAULT
        sta     zTextColor              ; the mode is data, not chrome
        lda     #$03                    ; row 3
        sta     $e6
        ldx     #$0018                  ; col 24 (23 is the separator, see above)
        jsr     Ot6DrawModeWord
        lda     #BG1_TEXT_COLOR::BLUE
        sta     zTextColor              ; ... the control that changes it is chrome
        ldy     #near Ot6LoadoutModeHintText
        jmp     DrawPosText

; ---- draw the mode word.  in: $e5 = 0 AUTO / 1 MANUAL, $e6 = row, X = col ----
; Shared by both loadout pages (the Rage page's Ot6RageDrawMode calls it), so the
; two cannot disagree about what the words are or how wide the field
; is.  OT6_MODE_AUTO is space-padded to OT6_MODE_MANUAL's six cells, so a
; MANUAL -> AUTO revert overwrites the whole field, the Ot6RageEmptyTiles rule.
Ot6DrawModeWord:
        lda     $e6
        jsr     GetBG1TilemapPtr        ; A = row, X = col -> X = tilemap dest
        longa
        txa
        sta     $7e9e89                 ; DrawPosTextBuf position header
        shorta
        ldx     #$9e8b
        stx     hWMADDL
        ldx     #$0000                  ; (long,X: there is no long,Y mode)
        lda     $e5
        bne     @man
@auto:  lda     f:Ot6ModeAutoTiles,x
        beq     @term
        sta     hWMDATA
        inx
        bra     @auto
@man:   lda     f:Ot6ModeManualTiles,x
        beq     @term
        sta     hWMDATA
        inx
        bra     @man
@term:  stz     hWMDATA
        jmp     DrawPosTextBuf

Ot6ModeAutoTiles:       raw_text OT6_MODE_AUTO   ; "AUTO  " + $00 (issue #39:
Ot6ModeManualTiles:     raw_text OT6_MODE_MANUAL ; "MANUAL" + $00, encoded via
                        ; menu_text_en.inc; a bare literal here picks up
                        ; ending_anim.asm's credits charmap and carries no
                        ; terminator, which is what garbled the page in #39)

; ---- draw the LEARNED pool as a 2 x 4 grid on the window's ODD rows (#43) ----
; Column-major: filled cells 0..3 go down the left column (col 3), 4..7 down the
; right (col 17), both on rows 9/11/13/15.  All eight Bushido techs therefore
; fit inside the window; the old {15,17,19,21} grid put three of its four rows
; past row 15, where this window shows nothing (see the cadence note above).
Ot6LoadoutDrawPool:
        lda     #BG1_TEXT_COLOR::DEFAULT
        sta     zTextColor
        stz     $e2                     ; filled-cell counter 0..7
        ldx     #$0000                  ; tech 0..7
@lp:    stx     $e3
        txa
        jsl     Ot6TechLearned          ; F0: carry = learned (A/X/Y preserved)
        bcc     @skip
        lda     $e3
        sta     $e5                     ; name value
        lda     $e2
        cmp     #$04
        bcc     @left
        sec
        sbc     #$04
        asl
        clc
        adc     #$09                    ; right column, row 9 + (cell-4)*2
        sta     $e6
        ldx     #$0011                  ; col 17 (12-cell name -> 17..28 < 30)
        bra     @draw
@left:  asl
        clc
        adc     #$09                    ; left column, row 9 + cell*2
        sta     $e6
        ldx     #$0003                  ; col 3 (the cursor gutter is 1-2)
@draw:  jsr     Ot6DrawBushName
        inc     $e2
@skip:  ldx     $e3
        inx
        cpx     #$0008
        bcc     @lp
        rts

; ---- draw one bushido tech name.  in: $e5 = tech value, $e6 = row, X = col ----
Ot6DrawBushName:
        lda     $e6
        jsr     GetBG1TilemapPtr        ; A = row, X = col -> X = tilemap dest
        longa
        txa
        sta     $7e9e89                 ; DrawPosTextBuf position header
        shorta
        jsr     _c35328                 ; BushidoName array ptr ($eb/$ef/$f1)
        lda     $e5
        jsr     LoadArrayItem           ; stage the 12-tile name into $7e9e8b
        jmp     DrawPosTextBuf

; ---- a row's MP cost, "nn MP" (blanks when cost 0).  in: A=cost,$e6=row,X=col --
;
; The one MP-price drawer for the whole field menu (issue #56).  This proc drew
; a single digit until v0.7 and said so in its own comment ("kit costs 1..8"),
; which was true when it was written.  #45 rescaled SwdTech to
; 4/10/13/16/18/22/30/46, so
; seven of the eight tiers printed `cost + ZERO_CHAR` past '9' ($bd) and came
; out as punctuation: Retort's 10 rendered as $be and Quadra Slice's 30 as '='
; (measured on the pre-change ROM, tools/tests/probe_swdtechcost.lua).  #46 had
; already hit the same limit on the Blitz ladder and answered it with a private
; copy, Ot6BlitzDrawCost in skills.asm, whose own report flagged the duplicate
; as something to remove; the copy is gone and its body is here, so there is one
; price drawer and a third page cannot inherit the single-digit version again.
;
; Right-aligned, with a leading blank and never a leading zero, so " 4 MP" sits
; under "30 MP" and a column of prices lines up.  That is vanilla's own
; rule for a menu number: HexToDec3 converts to three
; digits and then overwrites each leading '0' with $ff, the blank tile
; (menu_common.asm:906-918), and DrawNum2 prints the low two of those three
; (menu_common.asm:856-860), which is how the esper/magic detail
; window prints a spell's MP (skills.asm:2615-2621).  A cost of 0 blanks all
; five cells: that is the nomp build (Ot6LoadoutCost returns 0 with no cost
; table linked) and the Blitz page's locked rows, and blanking the full width is
; what keeps the property that a redraw overwrites what was there, which every
; field on these pages relies on (the Ot6RageEmptyTiles rule).
;
; The arithmetic is a repeated subtract rather than a divide because 65816 has
; no divide and the values are two digits: `cmp #10` leaves C set on the taken
; branch, so the `sbc #10` under it is exact without a preceding `sec`.
;
; Costs above 99 would wrap into the tens loop with no warning.  Nothing in the
; game prices one, and as of issue #57 that is a design rule rather than a
; coincidence: the most expensive row anywhere is Cleave/Bum Rush at 99, where
; each character's ultimate is anchored, and 99 is the largest number
; this drawer (and ListText cmd $02, btlgfx_main.asm:15045) can render
; (Ot6AbilityCostTbl, ot6_boost.asm).  tools/tests/menu_*page.lua assert every
; drawn field against that table and tools/tests/battle_costtable.lua asserts
; the <= 99 bound directly, so a three-digit price shows up as a failing test
; rather than as a wrong number on screen.
Ot6LoadoutDrawCost:
        pha                             ; save cost
        lda     $e6
        jsr     GetBG1TilemapPtr        ; X = tilemap dest
        longa
        txa
        sta     $7e9e89
        shorta
        ldx     #$9e8b
        stx     hWMADDL
        pla                             ; cost
        beq     @blank
        ldx     #$0000                  ; X = tens
@t:     cmp     #10
        bcc     @t2
        sbc     #10                     ; C set by the cmp, so sbc is exact
        inx
        bra     @t
@t2:    pha                             ; park the ones
        txa
        beq     @notens
        clc
        adc     #ZERO_CHAR
        bra     @puttens
@notens:
        lda     #$ff                    ; leading blank, not a leading zero
@puttens:
        sta     hWMDATA
        pla
        clc
        adc     #ZERO_CHAR              ; ones
        sta     hWMDATA
        ldx     #$0000
@ct:    lda     f:Ot6LoadoutCostTiles,x
        beq     @term
        sta     hWMDATA
        inx
        bra     @ct
@term:  stz     hWMDATA
        jmp     DrawPosTextBuf
@blank: ldy     #$0005                  ; the full "nn MP" width, so a revert
        lda     #$ff                    ;   wipes whatever was there
@bl:    sta     hWMDATA
        dey
        bne     @bl
        stz     hWMDATA
        jmp     DrawPosTextBuf

Ot6LoadoutCostTiles:    raw_text OT6_LOADOUT_MP_SUFFIX  ; " MP" + $00 (issue #39:
                        ; encoded via menu_text_en.inc; a bare literal here
                        ; picks up ending_anim.asm's credits charmap)

; ---- cursor: single column, three rows over the boost slots (#38) ----
; y = 116 + n*12 is the EN field menu's text pitch for this window, copied from
; vanilla's own magic/esper/rage cursor tables (skills.asm:125-126, :249-250,
; :292-293).  Tilemap row = 2n + 1, so rows 3/5/7 are n = 1/2/3.  The old
; {30,46,62} was an 8px-per-row assumption and put the cursor above the window.
;
; x = 8 is vanilla's magic/esper left-column x, and it pairs with text at column
; 3: the sprite is 16x16 with cursor_pos as its top-left, so it covers columns
; 1-2 (measured: `cursor_pos {8,116}` lights screen x 8..23, y 116..131, from
; the shipped ROM's own magic list, tools/tests/probe_menucols.lua).  Do not
; move this table to fix an overlap; move the text.  The rule is
; cursor_x = 8*col - 16 and it holds for every list vanilla draws in this
; window.  menu_swdtechpage.lua's cursor canary asserts the pairing.
Ot6LoadoutCursorProp:
        cursor_prop {0, 0}, {1, 3}, NO_XY_WRAP
Ot6LoadoutCursorPos:
        cursor_pos {8, 116 + 1 * 12}    ; row 3  (1x at col 3)
        cursor_pos {8, 116 + 2 * 12}    ; row 5  (2x at col 3)
        cursor_pos {8, 116 + 3 * 12}    ; row 7  (3x at col 3)

; ---- positioned labels (issue #39: the strings live in menu_text_en.inc so
; the encode pipeline maps them to menu-font tiles and null-terminates them;
; bare literals here assemble under ending_anim.asm's credits charmap, and
; without a terminator DrawPosText streams the data/code that follows into
; the tilemap, which was the garbled-page bug) ----
Ot6LoadoutTitleText:    pos_text OT6_LOADOUT_TITLE
Ot6LoadoutHintText:     pos_text OT6_LOADOUT_HINT
Ot6LoadoutModeHintText: pos_text OT6_LOADOUT_MODE_HINT  ; #49: "Y=AUTO" at {23,5}
Ot6LoadoutPoolText:     pos_text OT6_LOADOUT_POOL
Ot6LoadoutLbl1Text:     pos_text OT6_LOADOUT_LBL1
Ot6LoadoutLbl2Text:     pos_text OT6_LOADOUT_LBL2
Ot6LoadoutLbl3Text:     pos_text OT6_LOADOUT_LBL3

