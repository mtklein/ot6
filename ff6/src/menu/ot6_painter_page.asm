; ------------------------------------------------------------------------------
; ot6: the field Skills list's ninth row, Painter, and Relm's page behind it
; (#549)
;
; The counterpart of Locke's Treasure Hunter page (skills.asm, "The field
; Thief page"): the eight rows of her list behind Sketch, in the battle list's
; order read a column at a time, each learned row its name and price and each
; other one the locked marker.  The page has the Thief page's shape and
; geometry (rows 1/3/.../15 of BG1 screen A, name at column 3 against the
; cursor at x=8, price at column 16) and shares its cursor tables; there is no
; help line, as there is none on Locke's page.
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

; ------------------------------------------------------------------------------

; [ the Skills list: draw the ninth row, then vanilla's tail ]
; _c34c80's last jmp comes here.
Ot6SkillsPainterRow:
        lda     zSkillsTextColor::Painter
        sta     zTextColor
        ldy     #near SkillsPainterText
        jsr     DrawPosKana
        jmp     TfrBG3ScreenAB

; [ the Skills list: the ninth row's colour ]
; _c34d3d's `lda 0,y` comes here (a jsr in its three bytes), after the scan
; has coloured the other eight and with Y the character's record.  The init
; loop has already greyed the row.  out: A = the actor byte, as `lda 0,y`
; left it (flags too).  a8/i16.  clobbers X.
Ot6SkillsPainterColor:
        phy
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
        phy
        ldx     #$0006
@gear:  lda     $001f,y                 ; the six worn pieces, as UpdateEquip
        sta     hWRMPYA                 ;   reads them ($ff included: its
        lda     #30                     ;   record is all zero)
        sta     hWRMPYB
        phx
        nop2
        ldx     hRDMPYL
        lda     f:ItemProp+10,x         ; relic effects, the $11d6 byte
        plx
        and     #OT6_RELIC_CONTROL
        bne     @control
        iny
        dex
        bne     @gear
        ply
        lda     #$20                    ; Sketch, and Sketch in battle: white
        sta     zSkillsTextColor::Painter
        bra     @done
@control:
        ply                             ; Control in battle: stays grey
@done:  lda     0,y                     ; the instruction the hook replaced
        rts

; [ the Skills list's cursor positions: vanilla's eight, then Painter ]
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
; Skills list, A does nothing.  The description stays blank: the page stages
; $ff in $7e9d89 for every row and LoadThiefDesc runs LoadBigText's $ff arm.
MenuState_31_Painter:
        lda     #$10
        trb     z45
        jsr     InitDMA1BG1ScreenA
        jsr     UpdateThiefCursor
        jsr     LoadThiefDesc
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
        lda     #$ff
        sta     f:$7e9d89,x             ; no description: LoadBigText's $ff arm
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
        lda     $e6
        jsr     GetBG1TilemapPtr        ; A = row, X = col -> X = tilemap dest
        longa
        txa
        sta     $7e9e89                 ; DrawPosTextBuf position header
        shorta
        ldy     #10                     ; Ot6PaintName's record
        sty     $eb
        ldy     #near Ot6PaintName
        sty     $ef
        lda     #^Ot6PaintName
        sta     $f1
        lda     $e5
        jsr     LoadArrayItem           ; write the 10-tile name into $7e9e8b
        jmp     DrawPosTextBuf

SkillsPainterText:              pos_text SKILLS_LIST_PAINTER
SkillsPainterTitleText:         pos_text SKILLS_PAINTER_TITLE

.endif
