; ------------------------------------------------------------------------------
; ot6: the field Skills list's tenth row, RuneKnt, and Celes's page behind it
; (#563)
;
; The counterpart of Locke's Treasure Hunter page and Relm's Painter page
; (skills.asm "The field Thief page", ot6_painter_page.asm): the rows of the
; Rune Knight's list behind Runic (battle/ot6_rune.asm), in the battle list's
; order, each its name and price.  The page has their shape and geometry
; (rows 1/3/.../15 of BG1 screen A, name at column 3, price at column 16),
; the Thief page's cursor, the Painter page's title box and exit, and the
; help window's line for the row under the cursor.
;
; Unlike theirs, this list's rows are not fixed: the battle list offers a
; blade row for each element the caster can cast in that battle.  The page
; lists the rows she would be offered now:
;
;   Runic        always, free (its price draws blank, as Sketch's does)
;   the blades   one for each element of which the field Magic list has a
;                spell for this character, in element bit order, priced at
;                the cheapest such spell as that list prices it (her Gold
;                Hairpin or Economizer included).  The test of each spell is
;                the Magic list's own (_c350a2, skills.asm: learned spells,
;                CELES's Break by her level, the worn esper's spells and worn
;                items' grants through Ot6FieldSpellKnown; for a GOGO the
;                seated party's union, as his Magic list has it), so the
;                page and the Magic list cannot disagree, and it follows an
;                esper put on or taken off.  Six at most, the battle shell's
;                eight cells less Runic and Break Blade.
;   Break Blade  last: its name and 99 once it is learned (Ot6BreakLearned),
;                and until then the locked marker of the other pages, with
;                the help window saying where it is learned.
;
; Ot6RunePageRows (bank F0, battle/ot6_runepage.asm) builds the rows into the
; menu's list buffer from the spell verdicts staged here; the cursor walks
; only the rows there are.  The names are Ot6RuneName's, the records the
; battle list draws (the sword icon $d9 is the item lists' own tile, in the
; menu's font as in the battle's).  The title is BattleCmdName's record, as
; the Skills row is.
;
; The row is white for whoever carries the Runic command in their four
; commands and holds a weapon that allows Runic, and grey otherwise.  No
; relic rewrites command $0b (RelicCmdTbl has no Runic entry), but battle
; greys the command when neither hand's weapon carries the runic property
; (UpdateCmd_01: $3ba4/$3ba5 bit 7, the ItemProp+19 byte UpdateEquip stores
; for a weapon in a hand): a Flail, a Morning Star, the Atma Weapon, bare
; hands, and most of what a GOGO holds.  There the list cannot be opened, so
; the field menu offers no page either, as it offers none under a Thief
; Glove or a Fake Mustache.
;
; This code sits in its own segment after the Painter page's
; (ot6_menu_runeknt, cfg/ff6-en.cfg).  The hooks: the Painter page's two
; Skills-list routines end in this file's (Ot6SkillsKitRows,
; Ot6SkillsPainterColor), its cursor table and jump table grew a tenth
; entry, and menu_code's same-size operands count ten rows (skills.asm,
; field_menu.asm, menu_common.asm's state table).
; ------------------------------------------------------------------------------

.if LANG_EN

.segment "ot6_menu_runeknt"

MENU_STATE_RUNEKNT = $32                ; the last of vanilla's unused $30-$32
                                        ;   (menu_misc.asm)
OT6_WEAPON_RUNIC   = $80                ; ItemProp+19, a weapon's special
                                        ;   effects: it allows Runic
; the page's rows in the menu's list buffer (battle/ot6_runepage.asm)
OT6_RPAGE_ROW      = $7e9d89            ; eight rows: the help line's index
                                        ;   (LoadBigText reads it), $ff none
OT6_RPAGE_COST     = $7e9d91            ; and their prices
OT6_RPAGE_KNOWN    = $7e9d99            ; spells $00-$35: the Magic list's
                                        ;   verdict, $ff = she has the spell
OT6_RPAGE_LOCKED   = 10                 ; Break Blade not learned yet
OT6_RPAGE_NAME0    = 8                  ; Ot6RuneName's record of row 0, Runic
                                        ;   (id $d0, less the table's first $c8)

; ------------------------------------------------------------------------------

; [ the Skills list: draw the tenth row, then vanilla's tail ]
; Ot6SkillsKitRows' tail comes here.  The row is BattleCmdName's Runic record
; ("RuneKnt"), the string the battle command window draws.
Ot6SkillsRuneRow:
        lda     zSkillsTextColor::RuneKnt
        sta     zTextColor
        ldy_pos BG3A, {2, 23}
        ldx     #BATTLE_CMD::RUNIC * BattleCmdName::ITEM_SIZE
        jsr     Ot6SkillsCmdRow
        jmp     TfrBG3ScreenAB

; [ the Skills list: the tenth row's colour, as battle has the command ]
; Ot6SkillsPainterColor's tail comes here, with Y the character's record and
; the init loop having greyed the row.  White when the record carries the
; Runic command and a hand holds a weapon that allows it (the header).
; out: A = the actor byte, as the `lda 0,y` _c34d3d's hook replaced left it
; (flags too).  a8/i16.  preserves Y; clobbers X; no direct-page scratch
; (CheckShoulderBtns holds its next state in $e0 across CheckSkillValid).
Ot6SkillsRuneColor:
        phy
        ldx     #$0004
@cmd:   lda     $0016,y                 ; battle commands
        cmp     #BATTLE_CMD::RUNIC
        beq     @runic
        iny
        dex
        bne     @cmd
        ply
        bra     @done                   ; no Runic: grey
@runic: ply
        lda     $001f,y                 ; the right hand
        jsr     @hand
        bmi     @white
        lda     $0020,y                 ; the left
        jsr     @hand
        bpl     @done                   ; neither allows Runic: grey in battle
@white: lda     #$20
        sta     zSkillsTextColor::RuneKnt
@done:  lda     0,y                     ; the instruction the hook replaced
        rts

; a hand's piece: N set when it is a weapon that allows Runic, as UpdateEquip
; reads it (a shield's byte is not a weapon's; an empty hand's record has
; none).  in: A = the item.  clobbers X.
@hand:  sta     hWRMPYA
        lda     #30
        sta     hWRMPYB
        nop3
        ldx     hRDMPYL
        lda     f:ItemProp,x
        and     #$07
        cmp     #$01                    ; a weapon
        bne     @none
        lda     f:ItemProp+19,x         ; its special effects
        rts
@none:  lda     #$00
        rts

; ------------------------------------------------------------------------------

; [ skills menu $09: rune knight (init) ]
; SkillsOption_08's shape.  The cursor is the Thief page's, one column at the
; same pitch, cut to the rows there are.
SkillsOption_09:
        stz     $4a
        jsr     LoadThiefCursor
        jsr     InitThiefCursor
        ldy     #$0100
        sty     zBG2HScroll
        sty     zBG3HScroll
        jsr     DrawRuneKntMenu
        lda     #MENU_STATE_RUNEKNT
        sta     zMenuState
        rts

; [ menu state $32: rune knight page ]
; MenuState_31_Painter's shape: the cursor over the rows, B backs out to the
; Skills list, A does nothing.  The help window shows the row's line.
MenuState_32_RuneKnt:
        lda     #$10
        trb     z45
        jsr     InitDMA1BG1ScreenA
        jsr     UpdateThiefCursor
        jsr     Ot6RuneKntPageDesc
        lda     z08+1
        bit     #>JOY_B
        beq     @done
        jsr     Ot6PainterTitleOff      ; the seven-letter title gone again
        jsr     ReloadSkillsMenu
@done:  rts

; [ draw rune knight menu ]
; The title is the command's seven letters in the shared seven-tile box at
; column 23, as "Painter" and "SwdTech" are.
DrawRuneKntMenu:
        jsr     ClearBG1ScreenA
        jsr     Ot6RuneKntPageDraw
        lda     #$2c
        sta     zTextColor
        ldy_pos BG3B, {23, 5}
        ldx     #BATTLE_CMD::RUNIC * BattleCmdName::ITEM_SIZE
        jsr     Ot6SkillsCmdRow
        jsr     CreateSubPortraitTask
        jmp     InitDMA1BG3ScreenB

; ---- build the rows and draw them ----
Ot6RuneKntPageDraw:
        ldx     #$0035                  ; spells $35-$00: does the Magic list
@spell: phx                             ;   have it for this character?
        txa
        jsr     _c350a2                 ; A = $ff when it does (skills.asm)
        plx
        sta     f:OT6_RPAGE_KNOWN,x
        dex
        bpl     @spell
        jsl     Ot6RunePageRows         ; F0: the rows, the prices; A = rows
        sta     $54                     ; the cursor's rows (LoadCursor's max y)
        ldx     #$0000
@lp:    stx     $e2                     ; row index 0..7 (word: $e2/$e3)
        lda     $e2
        asl
        inc
        sta     $e6                     ; row = 1 + i*2: odd rows 1..15
        lda     f:OT6_RPAGE_ROW,x
        bmi     @next                   ; no row
        cmp     #OT6_RPAGE_LOCKED
        beq     @locked
        clc
        adc     #OT6_RPAGE_NAME0
        sta     $e5                     ; Ot6RuneName record
        lda     #BG1_TEXT_COLOR::DEFAULT
        sta     zTextColor
        ldx     #OT6_BLITZ_NAME_COL
        ldy     #near Ot6RuneName
        jsr     Ot6KitDrawName
        ldx     $e2
        lda     f:OT6_RPAGE_COST,x      ; (Runic's 0 draws blank)
        bra     @cost
@locked:
        lda     #BG1_TEXT_COLOR::BLUE   ; chrome, as on the Thief page
        sta     zTextColor
        ldx     #OT6_BLITZ_NAME_COL
        jsr     Ot6BlitzDrawLocked
        lda     #$00                    ; cost 0 -> blanks
@cost:  ldx     #OT6_BLITZ_COST_COL
        jsr     Ot6LoadoutDrawCost      ; the one field-menu price drawer
@next:  ldx     $e2
        inx
        cpx     #$0008
        bcc     @lp
        rts

; ---- the help window: the line of the row under the cursor ----
; LoadBlitzDesc's shape: LoadBigText reads the line's index from the list
; buffer's cell under the cursor, which is where Ot6RunePageRows put the row
; (tools/kit_pages.py's RUNE table: the row, or Break Blade not learned yet).
; Called every frame, as the other pages' loaders are.
Ot6RuneKntPageDesc:
        ldx     #near Ot6RunePageDescPtrs
        stx     $e7
        ldx     #near Ot6RunePageDescStr
        stx     $eb
        lda     #^Ot6RunePageDescPtrs
        sta     $e9
        lda     #^Ot6RunePageDescStr
        sta     $ed
        jmp     LoadBigText

.endif
