; ------------------------------------------------------------------------------
; ot6: the field Skills list's ninth row, Painter, and Relm's page behind it
; (#549)
;
; The counterpart of Locke's Treasure Hunter page (skills.asm, "The field
; Thief page"): the eight rows of her list behind Sketch, in the battle list's
; order read a column at a time, each learned row its name and price and each
; other one the locked marker.  The page has the Thief page's shape and
; geometry (rows 1/3/.../15 of BG1 screen A, name at column 3 against the
; cursor at x=8, price at column 16) and shares its cursor tables; the help
; window at the top shows the line of the row under the cursor, as Locke's
; page does (Ot6PainterPageDesc, below).
;
;   the rows    Ot6PaintPageRow (bank F0): Ot6PaintRowTbl's id when
;               Ot6PaintRowKnown says the row is learned (the switch or level
;               the battle list tests), else $ff
;   the names   Ot6PaintName, the records the battle list draws its names from
;               (Ot6PaintListName); row n is id $e8 + n
;   the prices  Ot6PaintBase, the leaf the battle list stamps each row's price
;               from and prices a row at no boost through (Ot6PaintRowCost).
;               Sketch's 0 draws blank, as the battle list's two blanks do;
;               the reach rows' "a body" is the one body of no boost.
;
; The row is white for whoever carries Sketch in their four commands, as the
; battle list opens for whoever holds Sketch (a Gogo too, #547), and grey for
; a Sketch holder wearing a piece whose relic effects turn Sketch into Control
; (the Fake Mustache): in battle that character has Control and no painter's
; list (vanilla's RelicCmdTbl rewrite, kit-relm.md "The Fake Mustache"), so the
; field menu offers no page either.  The test reads ItemProp's relic-effects
; byte (+10) of the six worn pieces, the byte UpdateEquip ORs into $11d6 and
; the battle's command rewrite tests ($10); no esper rung carries that bit
; (menu_painterpage_wor checks Ot6LadderTbl), so the gear is the whole answer.
;
; This code sits in its own segment after the vanilla bank (ot6_menu_painter,
; cfg/ff6-en.cfg), as ot6_dense_menu.asm does: the hooks in menu_code are
; same-size operand changes (skills.asm, field_menu.asm, menu_common.asm), so
; no menu_code address moves.  The two tables that grew a ninth entry, the
; Skills cursor positions and the Skills jump table, are copied here whole and
; their one reader repointed; the old eight-entry copies stay where they were,
; unread.
; ------------------------------------------------------------------------------

.if LANG_EN

.segment "ot6_menu_painter"

MENU_STATE_PAINTER = $31                ; vanilla $30-$32 are unused (menu_misc
                                        ;   .asm); $30 is the Thief page's
OT6_RELIC_CONTROL  = $10                ; ItemProp+10 / $11d6: Sketch -> Control
OT6_RELIC_CAPTURE  = $40                ;   and Steal -> Capture (Thief Glove)

; ------------------------------------------------------------------------------

; [ the Skills list: draw the eighth and ninth rows, then vanilla's tail ]
; _c34c80's tail comes here.  Each row reads its character's battle command
; name, the string the battle command window draws, so the two cannot drift
; and the rows fit the list's vanilla seven columns (the owner, #549: "the
; same abbrev we do in the combat menus, much like SwdTech above for cyan"):
; Locke's BattleCmdName's Steal record ("TresHnt") and Relm's Sketch record
; ("Painter", the owner, 2026-11-21: the command is Painter, and Sketch is
; one row of its list, as Steal is of TresHnt's).
Ot6SkillsKitRows:
        lda     zSkillsTextColor::Thief
        sta     zTextColor
        ldy_pos BG3A, {2, 19}
        ldx     #BATTLE_CMD::STEAL * BattleCmdName::ITEM_SIZE
        jsr     Ot6SkillsCmdRow
        lda     zSkillsTextColor::Painter
        sta     zTextColor
        ldy_pos BG3A, {2, 21}
        ldx     #BATTLE_CMD::SKETCH * BattleCmdName::ITEM_SIZE
        jsr     Ot6SkillsCmdRow
        jmp     Ot6SkillsRuneRow        ; the tenth, Celes's, then
                                        ;   TfrBG3ScreenAB (ot6_runeknt_page.asm)

; [ one Skills row: a BattleCmdName record at a BG3 position ]
; in: X = the record's offset in BattleCmdName, Y = the text position.
Ot6SkillsCmdRow:
        phx
        jsr     InitTextBuf             ; the position header; WMADD at the text
        plx
        ldy     #BattleCmdName::ITEM_SIZE
:       lda     f:BattleCmdName,x
        sta     hWMDATA
        inx
        dey
        bne     :-
        stz     hWMDATA
        jmp     DrawPosTextBuf

; [ the Skills list: the eighth and ninth rows' colours, as battle has them ]
; _c34d3d's `lda 0,y` comes here (a jsr in its three bytes), after the scan
; has coloured the other eight and with Y the character's record.  The init
; loop has already greyed the Painter row.  Then the relic rewrite battle
; makes (RelicCmdTbl1/2): a worn Thief Glove turns Steal into Capture, which
; opens no list in battle (ot6_thief.asm's header: command $06 keeps vanilla
; Capture), so the Treasure Hunter row greys as the Painter row does under
; the Fake Mustache.  out: A = the actor byte, as `lda 0,y` left it (flags
; too), but $ff for Gogo revealed as Leo, whose Espers row this makes white
; (#552 piece F).  a8/i16.  clobbers X.
Ot6SkillsPainterColor:
        lda     zSkillsTextColor::Thief
        cmp     #$20
        bne     @paint                  ; no Steal: grey already
        lda     #OT6_RELIC_CAPTURE
        jsr     Ot6WornRelicCmd
        beq     @paint
        lda     #$24                    ; Capture in battle: grey
        sta     zSkillsTextColor::Thief
@paint: phy
        ldx     #$0004
@cmd:   lda     $0016,y                 ; battle commands
        cmp     #BATTLE_CMD::SKETCH
        beq     @sketch
        iny
        dex
        bne     @cmd
        ply
        bra     @done                   ; no Sketch: grey
@sketch:
        ply
        lda     #OT6_RELIC_CONTROL
        jsr     Ot6WornRelicCmd
        bne     @done                   ; Control in battle: stays grey
        lda     #$20                    ; Sketch, and Sketch in battle: white
        sta     zSkillsTextColor::Painter
@done:  jsr     Ot6SkillsRuneColor      ; the tenth row's colour, which ends
                                        ;   in the `lda 0,y` the hook replaced
                                        ;   (ot6_runeknt_page.asm, #563)
        cmp     #CHAR_PROP::GOGO
        bne     @out
        jsr     Ot6LeoGenjuRow          ; #552 piece F
@out:   rts

; Gogo's Espers row (A = CHAR_PROP::GOGO in, Y = his record).  Revealed as
; Leo, the esper is one of his picks (the owner, 2026-11-23): with Summon
; among his commands the row is white (he wears, earns and keeps ranks as
; anyone does, and Summon casts his stone) and A comes back $ff, so the
; caller's Gogo test greys nothing.  Unrevealed, or Summon not picked: A
; stays Gogo's and the caller greys the row, as vanilla.  (mutant_rom.py's
; seam: an rts first.)
Ot6LeoGenjuRow:
        lda     f:OT6_LEO_FLAG
        and     #OT6_LEO_BIT
        beq     @no
        lda     a:$0016,y               ; his four commands (record +$16)
        cmp     #BATTLE_CMD::SUMMON
        beq     @yes
        lda     a:$0017,y
        cmp     #BATTLE_CMD::SUMMON
        beq     @yes
        lda     a:$0018,y
        cmp     #BATTLE_CMD::SUMMON
        beq     @yes
        lda     a:$0019,y
        cmp     #BATTLE_CMD::SUMMON
        beq     @yes
@no:    lda     #CHAR_PROP::GOGO
        rts
@yes:   lda     #$20
        sta     zSkillsTextColor::Genju
        lda     #$ff
        rts

; [ the revealed Leo's esper pick: Summon in Gogo's Status-screen list ]
;
; #552 piece F (the owner, 2026-11-23): once revealed, Leo picks his esper
; like any other ability.  The pick is Summon ($19, BattleCmdName "Summon",
; the command that casts the stone he wears: vanilla already lets Gogo use
; it, but no record holds it, so vanilla never offered it).  From
; DrawStatusGogoWindow after its record scan: with the switch set and no
; record's command already Summon (his own, once picked: the scan lists it
; there, BattleCmdProp's Gogo flag being set), Summon is written as the next
; row.  Y (i16) = the rows written so far, WMADD at the next; a8.  X
; clobbered (the caller reloads it).
Ot6LeoSummonList:
        lda     f:OT6_LEO_FLAG
        and     #OT6_LEO_BIT
        beq     @out
        ldx     #$0000
@scan:  lda     f:$7e9e09,x             ; the scan's 64 commands, duplicates $ff
        cmp     #BATTLE_CMD::SUMMON
        beq     @out                    ; a record holds it: listed already
        inx
        cpx     #$0040
        bne     @scan
        lda     #BATTLE_CMD::SUMMON
        sta     hWMDATA
        iny
@out:   rts

; Gogo's command list holds up to 17 rows once he is revealed (the blank,
; the 14 commands a full roster's records hold, Shock and Summon); vanilla's
; cursor and the status menu's BG3 scroll stop at 16 (status.asm
; GogoCmdListProp/Pos, StatusBG3ScrollHDMA, kept there unread).  These are
; their copies with one more row, the readers repointed (same-size operands).
Ot6GogoCmdListProp:
        cursor_prop {0, 0}, {1, 17}, NO_X_WRAP

Ot6GogoCmdListPos:
        .repeat 17, i
        cursor_pos {240, 16 + i * 12}
        .endrep

Ot6StatusBG3ScrollHDMA:
        .byte   $27,$00,$00
        .repeat 16, i
        .byte   $0c, 4 * (i + 1), $00
        .endrep
        .byte   $00

; [ does a worn piece carry this relic command rewrite? ]
; in: A = the $11d6 bit (OT6_RELIC_*), Y = the character's record.  out: Z
; clear (A nonzero) when one of the six worn pieces' relic-effects byte
; (ItemProp+10, the byte UpdateEquip ORs into $11d6 and the battle's
; RelicCmdTbl rewrite tests) carries it.  The pieces are read as UpdateEquip
; reads them ($ff included: its record is all zero).  a8/i16.  preserves Y;
; clobbers X; no direct-page scratch (CheckShoulderBtns holds its next state
; in $e0 across CheckSkillValid).
Ot6WornRelicCmd:
        pha                             ; [1,s] the bit
        phy                             ; [3,s] the bit
        ldx     #$0006
@gear:  lda     $001f,y
        sta     hWRMPYA
        lda     #30
        sta     hWRMPYB
        phx
        nop2
        ldx     hRDMPYL
        lda     f:ItemProp+10,x         ; relic effects, the $11d6 byte
        plx
        and     $03,s
        bne     @out
        iny
        dex
        bne     @gear                   ; (A = 0 when the loop ends)
@out:   ply
        sta     $01,s                   ; the answer over the bit
        pla                             ; Z from the answer
        rts

; [ the Skills list's cursor positions: vanilla's eight, Painter, RuneKnt ]
; InitSkillsCursor reads this copy (skills.asm); y = 8n - 4 for BG3A row n.
Ot6SkillsCursorPos:
        cursor_pos {0, 20}
        cursor_pos {0, 36}
        cursor_pos {0, 68}
        cursor_pos {0, 84}
        cursor_pos {0, 100}
        cursor_pos {0, 116}
        cursor_pos {0, 132}
        cursor_pos {0, 148}             ; Treasure Hunter, BG3A row 19
        cursor_pos {0, 164}             ; Painter, BG3A row 21
        cursor_pos {0, 180}             ; RuneKnt, BG3A row 23 (#563)

; [ the Skills list's A: SelectSkillsOption jumps through this copy ]
Ot6SkillsOptionTbl:
        .addr   SkillsOption_00
        .addr   SkillsOption_01
        .addr   SkillsOption_02
        .addr   SkillsOption_03
        .addr   SkillsOption_04
        .addr   SkillsOption_05
        .addr   SkillsOption_06
        .addr   SkillsOption_07         ; Treasure Hunter
        .addr   SkillsOption_08         ; Painter
        .addr   SkillsOption_09         ; RuneKnt (ot6_runeknt_page.asm)

; ------------------------------------------------------------------------------

; [ skills menu $08: painter (init) ]
; SkillsOption_07's shape.  The cursor is the Thief page's (one column of
; eight at the same pitch).
SkillsOption_08:
        stz     $4a
        jsr     LoadThiefCursor
        jsr     InitThiefCursor
        ldy     #$0100
        sty     zBG2HScroll
        sty     zBG3HScroll
        jsr     DrawPainterMenu
        lda     #MENU_STATE_PAINTER
        sta     zMenuState
        rts

; [ menu state $31: painter page ]
; MenuState_30_Thief's shape: the cursor over the rows, B backs out to the
; Skills list, A does nothing.  The help window shows the row's line
; (Ot6PainterPageDesc).
MenuState_31_Painter:
        lda     #$10
        trb     z45
        jsr     InitDMA1BG1ScreenA
        jsr     UpdateThiefCursor
        jsr     Ot6PainterPageDesc
        lda     z08+1
        bit     #>JOY_B
        beq     @done
        jsr     Ot6PainterTitleOff
        jsr     ReloadSkillsMenu
@done:  rts

; [ draw painter menu ]
; "Painter" is seven letters, so the title fits the shared seven-tile box at
; column 23 as SwdTech does; no wider box is drawn.
DrawPainterMenu:
        jsr     ClearBG1ScreenA
        jsr     Ot6PainterPageDraw
        lda     #$2c
        sta     zTextColor
        ldy     #near SkillsPainterTitleText
        jsr     DrawPosKana
        jsr     CreateSubPortraitTask
        jmp     InitDMA1BG3ScreenB

; ---- leaving the page: the title gone ----
; The other pages write their shorter titles at column 23 and clear nothing,
; so "Painter" must not outlast the page (Espers over it would read
; "Espersr").  Blanked as Ot6ThiefTitleBoxOff blanks the long title (the same
; blank run, columns 15-29), pushed up in one vblank, and DMA 1 put back on
; BG1 screen A so the list's cleared BG1 reaches VRAM.
Ot6PainterTitleOff:
        ldy     #near SkillsThiefTitleBlankText
        jsr     DrawPosKana
        jsr     InitDMA1BG3ScreenB
        jsr     WaitVblank
        jmp     InitDMA1BG1ScreenA

; ---- draw the eight rows ----
Ot6PainterPageDraw:
        ldx     #$0000
@lp:    stx     $e2                     ; row index 0..7 (word: $e2/$e3)
        lda     $e2
        asl
        inc
        sta     $e6                     ; row = 1 + i*2: odd rows 1..15
        lda     $e2
        jsl     Ot6PaintPageRow         ; F0: the row's id, $ff if not learned
        cmp     #$ff
        beq     @locked
        pha
        lda     #BG1_TEXT_COLOR::DEFAULT
        sta     zTextColor
        lda     $e2
        sta     $e5                     ; Ot6PaintName record: row n is id $e8+n
        ldx     #OT6_BLITZ_NAME_COL
        jsr     Ot6PainterDrawName
        pla                             ; the row's id
        jsl     Ot6PaintBase            ; F0: A = its price
        ldx     #OT6_BLITZ_COST_COL
        jsr     Ot6LoadoutDrawCost      ; the one field-menu price drawer
        bra     @next
@locked:
        lda     #BG1_TEXT_COLOR::BLUE   ; chrome, as on the Thief page
        sta     zTextColor
        ldx     #OT6_BLITZ_NAME_COL
        jsr     Ot6BlitzDrawLocked
        lda     #$00
        ldx     #OT6_BLITZ_COST_COL
        jsr     Ot6LoadoutDrawCost      ; cost 0 -> blanks
@next:  ldx     $e2
        inx
        cpx     #$0008
        bcc     @lp
        rts

; ---- one row's name.  in: $e5 = Ot6PaintName index, $e6 = row, X = col ----
Ot6PainterDrawName:
        ldy     #near Ot6PaintName
; in: Y = a table of ten-tile names in Ot6PaintName's bank (Celes's page
; draws Ot6RuneName through this), $e5 = the record, $e6 = row, X = col
Ot6KitDrawName:
        sty     $ef
        lda     $e6
        jsr     GetBG1TilemapPtr        ; A = row, X = col -> X = tilemap dest
        longa
        txa
        sta     $7e9e89                 ; DrawPosTextBuf position header
        shorta
        ldy     #10                     ; the record
        sty     $eb
        lda     #^Ot6PaintName
        sta     $f1
        lda     $e5
        jsr     LoadArrayItem           ; write the 10-tile name into $7e9e8b
        jmp     DrawPosTextBuf

; ---- the help window: the line of the row under the cursor (#549) ----
; As the vanilla Skills pages do (LoadBlitzDesc), through LoadBigText's own
; copy (LoadItemDesc: A = the line's index, $e7 the pointer table, $eb the
; strings, WMADD at the help buffer).  The lines are tools/kit_pages.py's,
; sixteen a page: the row's own when it is learned, row + 8 (how it is
; learned) when not, by the same test the page's rows draw by.  Called every
; frame, as the other pages' loaders are.
Ot6ThiefPageDesc:
        ldx     #near Ot6ThiefPageDescPtrs
        stx     $e7
        ldx     #near Ot6ThiefPageDescStr
        stx     $eb
        lda     #^Ot6ThiefPageDescPtrs
        sta     $e9
        lda     #^Ot6ThiefPageDescStr
        sta     $ed
        lda     $4b
        jsl     Ot6ThiefPageRow         ; F0: the row's id, $ff if not learned
        bra     Ot6KitPageDesc

Ot6PainterPageDesc:
        ldx     #near Ot6PaintPageDescPtrs
        stx     $e7
        ldx     #near Ot6PaintPageDescStr
        stx     $eb
        lda     #^Ot6PaintPageDescPtrs
        sta     $e9
        lda     #^Ot6PaintPageDescStr
        sta     $ed
        lda     $4b
        jsl     Ot6PaintPageRow         ; F0: the row's id, $ff if not learned
; in: A = the row's id or $ff; $4b = the row
Ot6KitPageDesc:
        cmp     #$ff                    ; carry set: not learned
        clr_a                           ; B = 0: LoadItemDesc indexes in 16 bits
        lda     $4b
        and     #$07
        bcc     :+                      ; learned: the row's own line
        ora     #$08                    ; not yet: how it is learned
:       ldx     #$9ec9
        stx     hWMADDL
        jmp     LoadItemDesc

SkillsPainterTitleText:         pos_text SKILLS_PAINTER_TITLE

.endif
