
; +----------------------------------------------------------------------------+
; |                                                                            |
; |                            FINAL FANTASY VI                                |
; |                                                                            |
; +----------------------------------------------------------------------------+
; | file: field_menu.asm                                                       |
; |                                                                            |
; | description: main menu                                                     |
; |                                                                            |
; | created: 9/23/2022                                                         |
; +----------------------------------------------------------------------------+

.if !LANG_EN
inc_lang "text/char_title_%s.inc"
.endif
inc_lang "text/item_name_%s.inc"
; issue #40: the rage loadout page blanks a slot row to MonsterName::ITEM_SIZE
; tiles.  skills.asm includes this too (the .inc is .ifndef-guarded), but it is
; assembled AFTER this file, so the scope has to be pulled in here as well.
inc_lang "text/monster_name_%s.inc"

.import GenjuName, MagicProp

.segment "menu_code"

; ------------------------------------------------------------------------------

; [ menu state $04: main menu (init) ]

MenuState_04:
@1a8a:  jsr     DisableInterrupts
        jsr     InitPortraits
        jsr     DisableDMA2
        jsr     DisableWindow2PosHDMA
        lda     #$04        ; enable hdma channel #2 (window 1 position)
        tsb     zEnableHDMA
        jsr     DisableDMA2
        jsr     ClearBGScroll
        lda     #$03        ; set bg1 data address and screen size (4 screens)
        sta     hBG1SC
        lda     #$43        ; set bg3 data address and screen size (4 screens)
        sta     hBG3SC
        lda     #$c0        ; disable hdma channel #6 and #7 (bg1 horizontal & vertical scroll)
        trb     zEnableHDMA
        lda     #$02        ; cursor 1 is active
        sta     z46
        jsr     DrawMainMenu
        lda     #0
        ldy     #near MainMenuCursorTask
        jsr     CreateTask
        jsr     CreateCursorTask
        jsr     _c3354e
        ldy     #$0002      ; bg1 vertical scroll = 2
        sty     zBG1VScroll
        jsr     InitMainMenuBG3VScrollHDMA
        lda     #$05        ; set next menu state
        sta     zNextMenuState
        lda     #MENU_STATE::FADE_IN
        sta     zMenuState
        jmp     EnableInterrupts

; ------------------------------------------------------------------------------

; [ menu state $07: item (init) ]

MenuState_07:
@1ad6:  jsr     _c31ae2
        jsr     _c31afe
        jsr     _c31b0e
        jmp     _c31b2e

; ------------------------------------------------------------------------------

; [  ]

_c31ae2:
@1ae2:  jsr     DisableInterrupts
        jsr     InitBigText
        jsr     ClearBGScroll
        stz     $4a         ; scroll position = 0
        stz     $49         ; cursor position = 0
.if LANG_EN
        lda     #$f5        ; max scroll position = 245
        sta     $5c
        lda     #$0a        ; page height = 10
        sta     $5a
        lda     #$01        ; page width = 1
.else
        lda     #$76        ; max scroll position = 118
        sta     $5c
        lda     #$0a        ; page height = 10
        sta     $5a
        lda     #$02        ; page width = 2
.endif
        sta     $5b
        jmp     LoadItemListCursor

; ------------------------------------------------------------------------------

; [  ]

_c31afe:
@1afe:  lda     $1d4e       ; branch if cursor is not memory
        and     #$40
        beq     @1b08
        jsr     RestoreItemCursorPos
@1b08:  jsr     InitItemListCursor
        jmp     DrawItemListMenu

; ------------------------------------------------------------------------------

; [  ]

_c31b0e:
@1b0e:  jsr     InitItemBGScrollHDMA
        jsr     CreateCursorTask
        jsr     CreateScrollArrowTask1
        longa
.if LANG_EN
        lda     #$0070
.else
        lda     #$00ea
.endif
        sta     wTaskSpeedY,x
        lda     #$0058
        sta     wTaskSpeedX,x
        shorta
        lda     #MENU_STATE::FADE_IN
        sta     zMenuState
        rts

; ------------------------------------------------------------------------------

; [  ]

_c31b2e:
@1b2e:  lda     #$08        ; set next menu state
        sta     zNextMenuState
        jmp     EnableInterrupts

; ------------------------------------------------------------------------------

; [ menu state $77: item select (init, return from character select) ]

MenuState_77:
@1b35:  jsr     _c31ae2
        lda     $8e
        sta     $4d
        ldy     $8e
        sty     $4f
        lda     $90
        sta     $4a
        lda     $4a
        sta     $e0
        lda     $50
        sec
        sbc     $e0
        sta     $4e
        jsr     InitItemListCursor
        jsr     DrawItemListMenu
        jsr     _c31b0e
        jmp     _c31b2e

; ------------------------------------------------------------------------------

; [ menu state $09: skills (init) ]

MenuState_09:
@1b5b:  jsr     DisableInterrupts
        clr_a
        lda     zSelIndex         ; selected character slot
        tax
        lda     zCharID,x       ; selected character number
        jsl     UpdateEquip_ext
        jsr     InitPortraits
        jsr     DisableWindow1PosHDMA
        stz     $4a         ; clear scroll positions
        stz     $49
        jsr     InitSkillsBGScrollHDMA
        jsr     _c34c80
        jsr     LoadSkillsCursor
        lda     $1d4e       ; branch if cursor setting is not memory
        and     #$40
        beq     @1b85
        jsr     RestoreSkillsCursorPos
@1b85:  jsr     InitSkillsCursor
        jsr     CreateCursorTask
        jsr     InitBigText
        lda     #MENU_STATE::FADE_IN
        sta     zMenuState
        lda     #MENU_STATE::SKILLS_SELECT
        sta     zNextMenuState
        jmp     EnableInterrupts

; ------------------------------------------------------------------------------

; [ init description text ]

InitBigText:
@1b99:  jsr     ClearBigTextBuf
        jsr     TfrBigTextGfx
        lda     #0
        ldy     #near BigTextTask
        jsr     CreateTask
        rts

; ------------------------------------------------------------------------------

; [ init character portraits ]

InitPortraits:
@1ba8:  jsr     InitCharProp
        jsr     LoadPortraitGfx
        jsr     LoadPortraitPal
        lda     #$05                    ; enable ??? & color palette dma
        tsb     z45
        jmp     TfrPal

; ------------------------------------------------------------------------------

; [ menu state $35: equip menu (init) ]

MenuState_35:
@1bb8:  jsr     _c31bbd
        bra     _c31bd7

; ------------------------------------------------------------------------------

; [  ]

_c31bbd:
@1bbd:  jsr     DisableInterrupts
        jsr     DisableWindow1PosHDMA
        lda     #$06
        tsb     z46
        stz     $4a
        stz     $49
        jsr     InitEquipScrollHDMA
        jsr     LoadEquipOptionCursor
        jsr     InitEquipOptionCursor
        jmp     CreateCursorTask

; ------------------------------------------------------------------------------

; [  ]

_c31bd7:
@1bd7:  jsr     DrawEquipMenu
        lda     #MENU_STATE::FADE_IN
        sta     zMenuState
        lda     #$36
        sta     zNextMenuState
        jmp     EnableInterrupts

; ------------------------------------------------------------------------------

; [ menu state $7e: switch character (equip) ]

MenuState_7e:
@1be5:  jsr     _c31c01
        jsr     DrawEquipTitleEquip
        jsr     _c31c0a
        lda     #$55
        jmp     _c31c15

; ------------------------------------------------------------------------------

; [ menu state $7f: switch character (equip remove) ]

MenuState_7f:
@1bf3:  jsr     _c31c01
        jsr     DrawEquipTitleRemove
        jsr     _c31c0a
        lda     #$56
        jmp     _c31c15

; ------------------------------------------------------------------------------

; [  ]

_c31c01:
@1c01:  jsr     _c31bbd
        jsr     DrawEquipMenu
        jmp     _c39614

; ------------------------------------------------------------------------------

; [  ]

_c31c0a:
@1c0a:  jsr     LoadEquipSlotCursor
        jsr     InitEquipSlotCursor
        lda     #MENU_STATE::FADE_IN
        sta     zMenuState
        rts

; ------------------------------------------------------------------------------

; [  ]

_c31c15:
@1c15:  sta     zNextMenuState
        jmp     EnableInterrupts

; ------------------------------------------------------------------------------

; [ menu state $6d: equip menu after optimize ]

MenuState_6d:
@1c1a:  jsr     _c31bbd
        jsr     EquipOptimum
        lda     #$02
        sta     z25
        bra     _c31bd7

; ------------------------------------------------------------------------------

; [ menu state $6e: equip menu after remove all ]

MenuState_6e:
@1c26:  jsr     _c31bbd
        jsr     EquipRemoveAll
        lda     #$02
        sta     z25
        bra     _c31bd7

; ------------------------------------------------------------------------------

; [ menu state $38: party equipment overview (init) ]

MenuState_38:
@1c32:  jsr     DisableInterrupts
        jsr     InitPartyEquipScrollHDMA
        jsr     DrawPartyEquipMenu
        lda     #MENU_STATE::FADE_IN
        sta     zMenuState
        lda     #$39
        sta     zNextMenuState
        jmp     EnableInterrupts

; ------------------------------------------------------------------------------

; [ menu state $0b: status (init) ]

MenuState_0b:
@1c46:  jsr     DisableInterrupts
        jsr     InitStatusBG3ScrollHDMA
        jsr     DrawStatusMenu
        jsr     InitStatusCursor
        lda     #MENU_STATE::FADE_IN
        sta     zMenuState
        lda     #$0c
        sta     zNextMenuState
        jmp     EnableInterrupts

; ------------------------------------------------------------------------------

; [ init cursor for status menu ]

InitStatusCursor:
@1c5d:  clr_a
        lda     zSelIndex
        asl
        tax
        ldy     zCharPropPtr,x
        lda     0,y
        cmp     #CHAR_PROP::GOGO
        bne     @1c78                   ; branch if not Gogo
        jsr     LoadGogoStatusCursor
        jsr     InitGogoStatusCursor
        lda     #$06
        tsb     z46
        jmp     CreateCursorTask

; not Gogo
@1c78:  lda     #$06                    ; no cursor
        trb     z46
        rts

; ------------------------------------------------------------------------------

; [ menu state $0d: config (init) ]

MenuState_0d:
@1c7d:  jsr     DisableInterrupts
        stz     $4a         ; set page to 0
        jsr     InitWindow2PosHDMA
        jsr     DrawConfigMenu
        jsr     LoadConfigPage1Cursor
        lda     $5f         ; restore cursor position
        sta     $4e
        jsr     InitConfigPage1Cursor
        jsr     CreateCursorTask
        lda     #MENU_STATE::FADE_IN
        sta     zMenuState
        lda     #$0e
        sta     zNextMenuState         ; config menu state
        jmp     EnableInterrupts

; ------------------------------------------------------------------------------

; [ menu state $13: save select (init) ]

MenuState_13:
@1ca0:  jsr     DisableInterrupts
        ldy     #$0002
        sty     zBG1VScroll
        jsr     InitMainMenuBG3VScrollHDMA
        lda     #$e3
        trb     zEnableHDMA         ; disable hdma 2, 3, 4
        jsr     DrawGameSaveMenu
        jsr     LoadCharPal
        jsr     LoadMiscMenuSpritePal
        jsr     LoadGameSaveCursor
        ldy     $91
        bne     @1cc7
        ldy     $93
        bne     @1cc7
        ldy     $95
        beq     @1ccd
@1cc7:  lda     wSelSaveSlot
        dec
        sta     $4e         ; set cursor position
@1ccd:  jsr     InitGameSaveCursor
        jsr     CreateCursorTask
        lda     $4b
        inc
        sta     zSelSaveSlot
        lda     #$52        ; menu state $52 (fade in, save menu)
        sta     zMenuState
        lda     #MENU_STATE::SAVE_SELECT
        sta     zNextMenuState
        jmp     EnableInterrupts

; ------------------------------------------------------------------------------

; [ menu state $15: save confirm (init) ]

MenuState_15:
@1ce3:  jsr     DisableInterrupts
        jsr     InitCharProp
        jsr     DrawGameSaveConfirmMenu
        jsr     LoadSaveConfirmCursor
        jsr     InitSaveConfirmCursor
        jsr     CreateCursorTask
        jsr     _c318d1
        lda     #$16        ; next menu state $16 (save confirm)
        sta     zNextMenuState
        lda     #MENU_STATE::FADE_IN
        sta     zMenuState
        jmp     EnableInterrupts

; ------------------------------------------------------------------------------

; [ menu state $20: restore game (init) ]

MenuState_20:
@1d03:  jsr     DisableInterrupts
        ldy     #$0002
        sty     zBG1VScroll
        jsr     InitMainMenuBG3VScrollHDMA
        lda     #$e3
        trb     zEnableHDMA
        ldy     z0
        sty     zBG1HScroll
        sty     zBG2HScroll
        sty     zBG3HScroll
        lda     #$02
        sta     z46
        jsr     DrawGameLoadMenu
        jsr     LoadCharPal
        jsr     LoadMiscMenuSpritePal
        jsr     LoadGameLoadCursor
        ldy     $91
        bne     @1d36       ; branch if slot 1 is valid
        ldy     $93
        bne     @1d36       ; branch if slot 2 is valid
        ldy     $95
        beq     @1d3c       ; branch if slot 3 is not valid
@1d36:  lda     $307ff0     ; most recently saved slot
        sta     $4e         ; set current position
@1d3c:  jsr     InitGameLoadCursor
        jsr     CreateCursorTask
        lda     $4b
        sta     zSelSaveSlot
        lda     #$21        ; next menu state $21 (restore game)
        sta     zNextMenuState
        lda     #$52        ; current menu state $52 (fade in, save menu)
        sta     zMenuState
        jmp     EnableInterrupts

; ------------------------------------------------------------------------------

; [ menu state $22: restore confirm (init) ]

MenuState_22:
@1d51:  jsr     DisableInterrupts
        jsr     InitCharProp
        jsr     DrawGameLoadConfirmMenu
        jsr     LoadSaveConfirmCursor
        jsr     InitSaveConfirmCursor
        jsr     CreateCursorTask
        jsr     _c318d1
        lda     #$23
        sta     zNextMenuState
        lda     #MENU_STATE::FADE_IN
        sta     zMenuState
        jmp     EnableInterrupts

; ------------------------------------------------------------------------------

; [ menu state $00: fade out (init) ]

MenuState_00:
@1d71:  jsr     CreateFadeOutTask
        ldy     #8                      ; set wait counter
        sty     zWaitCounter
        lda     #MENU_STATE::WAIT_FADE
        sta     zMenuState
        rts

; ------------------------------------------------------------------------------

; [ menu state $01: fade in (init) ]

MenuState_01:
@1d7e:  jsr     CreateFadeInTask
        ldy     #8                      ; set wait counter
        sty     zWaitCounter
        lda     #MENU_STATE::WAIT_FADE
        sta     zMenuState
        rts

; ------------------------------------------------------------------------------

; [ menu state $02: wait for fade ]

MenuState_02:
@1d8b:  ldy     zWaitCounter         ; return if frame counter is not 0
        bne     @1d93
        lda     zNextMenuState         ; go to next menu state
        sta     zMenuState
@1d93:  rts

; ------------------------------------------------------------------------------

; [ menu state $03: main menu re-init (from char select) ]

MenuState_03:
@1d94:  lda     #0                      ; priority 0
        ldy     #near MainMenuCursorTask
        jsr     CreateTask
        jsr     CreateCursorTask
        lda     #MENU_STATE::FIELD_MENU_SELECT
        sta     zMenuState
        rts

; ------------------------------------------------------------------------------

; [ menu state $05: main menu ]

MenuState_05:
@1da4:  jsr     UpdateTimeText

; A button
        lda     z08
        bit     #JOY_A
        jne     SelectMainMenuOption

; left button
        lda     z08+1
        bit     #>JOY_LEFT
        beq     @1dbc       ; branch if left button is not pressed
        jsr     PlayMoveSfx
        jmp     MainMenuLeftBtn

; B button
@1dbc:  lda     z08+1
        bit     #>JOY_B
        beq     @1dd1       ; return if b button is not pressed
        stz     w0205
        jsr     PlayCancelSfx
        jsr     UpdateEquipAfterMenu
        lda     #MENU_STATE::TERMINATE
        sta     zNextMenuState
        stz     zMenuState
@1dd1:  rts

; ------------------------------------------------------------------------------

; [ update field equipment effects ]

UpdateEquipAfterMenu:
@1dd2:  stz     $11df       ; clear all field equipment effects
        ldx     z0
@1dd7:  lda     zCharID,x       ; character in each party slot
        bmi     @1de1
        phx
        jsl     UpdateEquip_ext
        plx
@1de1:  inx                 ; next character slot
        cpx     #4
        bne     @1dd7
        rts

; ------------------------------------------------------------------------------

; [ menu state $06: main menu (select character) ]

MenuState_06:
@1de8:  jsr     UpdateTimeText

; B button
        lda     z08+1
        bit     #>JOY_B
        beq     @1dfd       ; branch if b button is not pressed
        jsr     PlayCancelSfx
        lda     #$05
        trb     z46         ; disable cursor 2 and flashing cursor
        lda     #MENU_STATE::FIELD_MENU_REINIT
        sta     zMenuState
        rts

; left button
@1dfd:  lda     z08+1         ; branch if left button is not pressed
        bit     #>JOY_LEFT
        beq     @1e1f
        lda     z25         ; branch if not equip or relic
        cmp     #$02
        beq     @1e0d
        cmp     #$03
        bne     @1e1f
@1e0d:  jsr     PlayMoveSfx
        lda     #$06
        trb     z46         ; disable cursor 1 and 2
        lda     #$37
        sta     zMenuState         ; set menu state to $37 (select all)
        lda     $4e         ; save cursor position
        sta     $5e
        jmp     CreateMultiCursorTask

; A button
@1e1f:  lda     z08         ; return if a button is not pressed
        bit     #JOY_A
        beq     @1e2c
        lda     $4b         ; cursor selection
        sta     zSelIndex         ; set selected character slot
        jmp     _c31e2d
@1e2c:  rts

; ------------------------------------------------------------------------------

; [  ]

_c31e2d:
@1e2d:  jsr     CheckSkillValid
        bcs     @1e42       ; branch if not
        clr_a
        lda     z25         ; main menu selection
        tax
        lda     f:_c31e49,x   ; init menu state
        sta     zNextMenuState
        stz     zMenuState         ; fade out
        jsr     PlaySelectSfx
        rts
@1e42:  jsr     PlayInvalidSfx
        jsr     CreateMosaicTask
        rts

; ------------------------------------------------------------------------------

; init menu states for main menu commands
_c31e49:
@1e49:  .byte   $ff,$09,$35,$58,$0b

; ------------------------------------------------------------------------------

; [ check if character slot is valid (skills/equip/relic/status) ]

; carry clear = valid
; carry set = invalid

CheckSkillValid:
@1e4e:  clr_a
        lda     z25         ; main menu selection
        cmp     #$01
        beq     @1e89       ; branch if skills
        cmp     #$02
        beq     @1e5f       ; branch if equip
        cmp     #$03
        beq     @1e74       ; branch if relic
        bra     @1eb3       ; branch if status (always valid)

; equip
@1e5f:  clr_a
        lda     zSelIndex
        asl
        tax
        longa
        lda     zCharPropPtr,x
        shorta
        tax
        lda     a:0,x     ; not valid for characters $0d (umaro) and higher
        cmp     #CHAR_PROP::UMARO
        bcs     @1eb1
        bra     @1e9c

; relic
@1e74:  clr_a
        lda     zSelIndex
        asl
        tax
        longa
        lda     zCharPropPtr,x
        shorta
        tax
        lda     a:0,x     ; not valid for characters $0e and higher
        cmp     #CHAR_PROP::BANON
        bcs     @1eb1
        bra     @1e9c

; skills
@1e89:  jsr     _c34d3d
        lda     #$24
        ldx     z0
@1e90:  cmp     zSkillsTextColor,x       ; branch if at least one is not disabled
        bne     @1e9c
        inx
        cpx     #$0007
        bne     @1e90
        bra     @1eb1

; check status
@1e9c:  clr_a
        lda     zSelIndex
        asl
        tax
        longa
        lda     zCharPropPtr,x
        shorta
        tax
        lda     a:$0014,x     ; not valid if wound, petrify, or zombie status
        and     #$c2
        bne     @1eb1
        bra     @1eb3

; invalid
@1eb1:  sec
        rts

; valid
@1eb3:  clc
        rts

; ------------------------------------------------------------------------------

; [ menu state $37: main menu (select all for equip/relic) ]

MenuState_37:
@1eb5:  jsr     UpdateTimeText
        lda     z08+1
        bit     #>JOY_B
        bne     @1ec4       ; branch if b button is down
        lda     z08+1
        bit     #>JOY_RIGHT
        beq     @1ee5       ; branch if right button is not down

; B button or right button
@1ec4:  jsr     PlayCancelSfx
        jsr     InitCharSelectCursor
        jsr     CreateCursorTask
        lda     #0
        ldy     #near CharSelectCursorTask
        jsr     CreateTask
        jsr     ExecTasks
        lda     $5e         ; restore cursor position
        sta     $4e
        lda     #MENU_STATE::FIELD_MENU_CHAR
        sta     zMenuState
        lda     #$08        ; disable multi-cursor
        trb     z46
        rts

; A button
@1ee5:  lda     z08         ; return if a button is not down
        bit     #JOY_A
        beq     @1ef5
        jsr     PlaySelectSfx
        stz     zMenuState
        lda     #$38        ; menu state $38 (equip all, init)
        sta     zNextMenuState
        rts
@1ef5:  rts

; ------------------------------------------------------------------------------

; [ menu state $08: item (select) ]

.proc MenuState_08_proc

_1ef6:  rts

::MenuState_08:
_1ef7:  lda     #$10
        trb     z45
        clr_a
        sta     zListType
        jsr     InitDMA1BG1ScreenA
        jsr     ScrollListPage
        bcs     _1ef6
        jsr     UpdateItemListCursor
        jsr     InitItemDesc

; B button
        lda     z08+1
        bit     #>JOY_B
        beq     _1f3b
        jsr     PlayCancelSfx
        ldy     $4f
        sty     w022f
        lda     $4a
        sta     w0231
        jsr     LoadItemOptionCursor
        lda     $1d4e
        and     #$40
        beq     _1f2c
        ldy     w0234
        sty     $4d

::GotoItemOption:
_1f2c:  jsr     InitItemOptionCursor
        lda     #MENU_STATE::ITEM_OPTIONS
        sta     zMenuState
        jsr     ClearItemCount
        jmp     InitDMA1BG3ScreenA

; A button
_1f3b:  lda     z08
        bit     #JOY_A
        beq     _1f4f
        jsr     PlaySelectSfx
        lda     $4b
        sta     zSelIndex
        lda     #MENU_STATE::ITEM_MOVE
        sta     zMenuState
        jmp     _c32f21

_1f4f:  rts

.endproc

; ------------------------------------------------------------------------------

; [ scroll list text up/down one page ]

.proc ScrollListPage_proc

; (branch from c3/1f9b)
_1f50:  stz     $50
        stz     $4e
        sec
        rts

; (branch from c3/1f72)
_1f56:  lda     $54
        dec
        sta     $4e
        clc
        adc     $4a
        sta     $50
        sec
        rts

; waiting (branch from c3/1f66)
_1f62:  clc
        rts

::ScrollListPage:
_1f64:  lda     zWaitCounter
        bne     _1f62                   ; branch if wait frame counter not zero

; R button
        lda     z0a
        bit     #$10
        beq     _1f93                   ; branch if R button is not pressed
        lda     $4a
        cmp     $5c
        beq     _1f56
        lda     $5c
        sec
        sbc     $4a
        cmp     $5a
        bcs     _1f7f
        bra     _1f81
_1f7f:  lda     $5a
_1f81:  sta     $e0
        lda     $4a
        clc
        adc     $e0
        sta     $4a
        lda     $50
        clc
        adc     $e0
        sta     $50
        bra     _1fb7

; L button
_1f93:  lda     z0a
        bit     #$20
        beq     _1f62                   ; branch if L button is not pressed
        lda     $4a
        beq     _1f50                   ; branch if at the top of the list
        cmp     $5a
        bcs     _1fa5
        lda     $4a
        bra     _1fa7
_1fa5:  lda     $5a
_1fa7:  sta     $e0
        lda     $4a
        sec
        sbc     $e0
        sta     $4a
        lda     $50
        sec
        sbc     $e0
        sta     $50
_1fb7:  jsr     PlayMoveSfx
        clr_a
        lda     zListType
        asl
        tax
        jsr     (near ScrollListPageTbl,x)
        sec
        rts

; ------------------------------------------------------------------------------

; jump table for list type
ScrollListPageTbl:
        make_jump_tbl ScrollListPage, 6
; ------------------------------------------------------------------------------

; 0: item list
make_jump_label ScrollListPage, LIST_TYPE::ITEM
@1fd0:  jsr     LoadItemBG1VScrollHDMATbl
        jmp     DrawItemList

; ------------------------------------------------------------------------------

; 1: magic
make_jump_label ScrollListPage, LIST_TYPE::MAGIC
@1fd6:  jsr     LoadSkillsBG1VScrollHDMATbl
        jmp     DrawMagicList

; ------------------------------------------------------------------------------

; 2: lore
make_jump_label ScrollListPage, LIST_TYPE::LORE
@1fdc:  jsr     LoadSkillsBG1VScrollHDMATbl
        jmp     DrawLoreList

; ------------------------------------------------------------------------------

; 3: rage
make_jump_label ScrollListPage, LIST_TYPE::RAGE
@1fe2:  jsr     LoadSkillsBG1VScrollHDMATbl
        jmp     DrawRageList

; ------------------------------------------------------------------------------

; 4: esper
make_jump_label ScrollListPage, LIST_TYPE::GENJU
@1fe8:  jsr     LoadSkillsBG1VScrollHDMATbl
        jmp     DrawGenjuList

; ------------------------------------------------------------------------------

; 5: equip/relic item list
make_jump_label ScrollListPage, LIST_TYPE::EQUIP
@1fee:  jsr     LoadEquipBG1VScrollHDMATbl
        jmp     DrawEquipItemList

.endproc

; ------------------------------------------------------------------------------

; [ menu state $0a: skills (select option) ]

MenuState_0a:
@1ff4:  lda     #$10        ;
        tsb     z45
        lda     #$c0        ; page can't scroll up or down
        trb     z46
        jsr     UpdateSkillsCursor

; return to main menu (b button)
        lda     z08+1
        bit     #>JOY_B
        beq     @200f       ; branch if b button is not pressed
        jsr     PlayCancelSfx
        lda     #MENU_STATE::FIELD_MENU_INIT
        sta     zNextMenuState
        stz     zMenuState
        rts

; open selected skills menu (a button)
@200f:  lda     z08         ; branch if a button is not pressed
        bit     #JOY_A
        beq     @201c
        lda     $4e
        sta     $5e
        jmp     SelectSkillsOption

; go to next character (top r button)
@201c:  lda     #$09        ; next menu state (init another character's skills menu)
        sta     $e0
        bra     CheckShoulderBtns

; ------------------------------------------------------------------------------

; [ check r & l shoulder buttons ]

; $e0: menu state to go to if user pressed top R or L

CheckShoulderBtns:
.if LANG_EN
@2022:  lda     zMosaic
        and     #$f0
        bne     @2089       ; return if mosaic'ing
.endif

; go to next character (top R button)
        lda     z08
        bit     #JOY_R
        beq     @2059
        lda     z25
        cmp     #$03
        bne     @203f
        jsr     CheckReequip
        lda     $99
        beq     @203f
        jsr     PlayMoveSfx
        rts
@203f:  clr_a
        lda     zSelIndex                     ; increment selected character slot
        inc
        and     #$03
        sta     zSelIndex
        tax
        lda     zCharID,x
        bmi     @203f
        jsr     CheckSkillValid
        bcs     @203f
        lda     $e0
        sta     zMenuState
        jsr     PlayMoveSfx
        rts

; go to previous character (top L button)
@2059:  lda     z08
        bit     #JOY_L
        beq     @2089
        lda     z25
        cmp     #$03
        bne     @2070
        jsr     CheckReequip
        lda     $99
        beq     @2070
        jsr     PlayMoveSfx
        rts
@2070:  clr_a
        lda     zSelIndex                     ; decrement selected character slot
        dec
        and     #$03
        sta     zSelIndex
        tax
        lda     zCharID,x
        bmi     @2070
        jsr     CheckSkillValid
        bcs     @2070
        lda     $e0
        sta     zMenuState
        jsr     PlayMoveSfx
@2089:  rts

; ------------------------------------------------------------------------------

; [ open selected skills menu (A button) ]

SelectSkillsOption:
@208a:  clr_a
        lda     $4b                     ; current selection
        tax
        lda     zSkillsTextColor,x                   ; branch if not enabled
        cmp     #$20
        bne     @209e
        jsr     PlaySelectSfx
        lda     $4b
        asl
        tax
        jmp     (near SkillsOptionTbl,x)

; invalid selection
@209e:  jsr     PlayInvalidSfx
        jsr     CreateMosaicTask
        rts

; ------------------------------------------------------------------------------

; skills menu jump table (espers, magic, swdtech, blitz, lore, rage, dance)
SkillsOptionTbl:
@20a5:  .addr   SkillsOption_00
        .addr   SkillsOption_01
        .addr   SkillsOption_02
        .addr   SkillsOption_03
        .addr   SkillsOption_04
        .addr   SkillsOption_05
        .addr   SkillsOption_06

; ------------------------------------------------------------------------------

; [ skills menu $00: espers (init) ]

SkillsOption_00:
@20b3:  stz     $4a
        jsr     CreateScrollArrowTask1
        longa
.if LANG_EN
        lda     #$1000
        sta     wTaskSpeedY,x
        lda     #$0068
        sta     wTaskSpeedX,x
        shorta
        jsr     LoadGenjuCursor
        jsr     InitGenjuCursor
        lda     #$06                    ; max page scroll position = 6
        sta     $5c
        lda     #$08
.else
        lda     #$1333
        sta     wTaskSpeedY,x
        lda     #$0060
        sta     wTaskSpeedX,x
        shorta
        jsr     LoadGenjuCursor
        jsr     InitGenjuCursor
        lda     #$05                    ; max page scroll position = 5
        sta     $5c
        lda     #$09
.endif
        sta     $5a
        lda     #$02
        sta     $5b
        ldy     #$0100
        sty     zBG2HScroll
        sty     zBG3HScroll
        jsr     DrawGenjuMenu
        lda     #MENU_STATE::SKILLS_GENJU
        sta     zMenuState
        jsr     _c32eeb
        rts

; ------------------------------------------------------------------------------

; [ skills menu $02: swdtech (init) ]

SkillsOption_02:
@20ee:  stz     $4a
        ldy     #$0100
        sty     zBG2HScroll
        sty     zBG3HScroll
.if LANG_EN
        ; issue #8 Layer B: SwdTech opens the loadout CONFIGURATOR, not the
        ; vanilla browse list.  The configurator names the learned techs too
        ; (the pool), so the browse list's only job is subsumed.  All state
        ; logic is bank-F0; Ot6LoadoutInitC3 does the C3 framework draw.
        jsr     Ot6LoadoutInitC3
        lda     #$01
        sta     $4a                     ; init done (state $7b self-init sentinel)
        lda     #MENU_STATE_LOADOUT     ; $7b
        sta     zMenuState
.else
        jsr     LoadAbilityCursor
        jsr     InitAbilityCursor
        jsr     _c352d7
        lda     #$3e
        sta     zMenuState
.endif
        rts

; ------------------------------------------------------------------------------

; [ skills menu $03: blitz (init) ]

SkillsOption_03:
@2105:  stz     $4a
.if LANG_EN
        ; issue #46: the page is ONE column of eight rows now (name, break class,
        ; MP price), not vanilla's 2x4 grid of button-combo glyphs, so it wants
        ; its own cursor.  LoadAbilityCursor's {2,4} table is still Dance's
        ; (SkillsOption_06) and must not move with this page.
        jsr     LoadBlitzCursor
        jsr     InitBlitzCursor
.else
        jsr     LoadAbilityCursor
        jsr     InitAbilityCursor
.endif
        ldy     #$0100
        sty     zBG2HScroll
        sty     zBG3HScroll
        jsr     DrawBlitzMenu
        lda     #$33
        sta     zMenuState
        rts

; ------------------------------------------------------------------------------

; [ skills menu $01: magic (init) ]

SkillsOption_01:
@211c:  jsr     _c32130
        jsr     _c32148
        jsr     InitMagicMenu
        jsr     _c351c6
        jsr     InitDMA1BG3ScreenB
        lda     #$1a
        sta     zMenuState
        rts

; ------------------------------------------------------------------------------

; [  ]

_c32130:
@2130:  stz     $4a
        jsr     CreateScrollArrowTask1
        longa
.if LANG_EN
        lda     #$050d
        sta     wTaskSpeedY,x
        lda     #$0068
.else
        lda     #$08ba
        sta     wTaskSpeedY,x
        lda     #$0060
.endif
        sta     wTaskSpeedX,x
        shorta
        rts

; ------------------------------------------------------------------------------

; [  ]

_c32148:
@2148:  jsr     LoadMagicCursor
        lda     $1d4e
        and     #$40
        beq     @2155
        jsr     RestoreMagicCursorPos
@2155:  jmp     InitMagicCursor

; ------------------------------------------------------------------------------

; [ init magic menu ]

InitMagicMenu:
.if LANG_EN
@2158:  lda     #$13
        sta     $5c
        lda     #$08
        sta     $5a
        lda     #$02
.else
        lda     #$0b
        sta     $5c
        lda     #$09
        sta     $5a
        lda     #$03
.endif
        sta     $5b
        ldy     #$0100
        sty     zBG2HScroll
        sty     zBG3HScroll
        jmp     DrawMagicMenu

; ------------------------------------------------------------------------------

; [ skills menu $04: lore (init) ]

SkillsOption_04:
@216e:  stz     $4a
        jsr     CreateScrollArrowTask1
        longa
.if LANG_EN
        lda     #$0600
        sta     wTaskSpeedY,x
        lda     #$0068
        sta     wTaskSpeedX,x
        shorta
        jsr     LoadLoreCursor
        jsr     InitLoreCursor
        lda     #$10
        sta     $5c
        lda     #$08
        sta     $5a
        lda     #$01
.else
        lda     #$2000
        sta     wTaskSpeedY,x
        lda     #$0060
        sta     wTaskSpeedX,x
        shorta
        jsr     LoadLoreCursor
        jsr     InitLoreCursor
        lda     #$03
        sta     $5c
        lda     #$09
        sta     $5a
        lda     #$02
.endif
        sta     $5b
        ldy     #$0100
        sty     zBG2HScroll
        sty     zBG3HScroll
        jsr     _c351f9
        lda     #$1b
        sta     zMenuState
        rts

; ------------------------------------------------------------------------------

; [ skills menu $05: rage (init) ]

SkillsOption_05:
@21a6:  stz     $4a
.if LANG_EN
        ; issue #40: Rage opens the 8-slot LOADOUT CONFIGURATOR, not the
        ; vanilla browse list -- the SkillsOption_02 repoint, re-applied.  The
        ; browse list's only job was naming what Gau knows; the configurator
        ; names it too (and prices it, and lets him carry eight of it into the
        ; fight).  All state logic is bank-F0; Ot6RageInitC3 does the C3
        ; framework draw.  The vanilla browse (InitRageList / ExpandRageList /
        ; menu state $1d) stays assembled for the non-EN branch, exactly as the
        ; SwdTech browse did.
        ldy     #$0100
        sty     zBG2HScroll
        sty     zBG3HScroll
        jsr     Ot6RageInitC3
        lda     #$01
        sta     $4a                     ; init done (state $7c self-init sentinel)
        lda     #MENU_STATE_RAGELOAD    ; $7c
        sta     zMenuState
        rts
.else
        jsr     CreateScrollArrowTask1
        longa
        lda     #$00ce
        sta     wTaskSpeedY,x
        lda     #$0060
        sta     wTaskSpeedX,x
        shorta
        jsr     LoadRageCursor
        jsr     InitRageCursor
        lda     #$77
        sta     $5c
        lda     #$09
        sta     $5a
        lda     #$02
        sta     $5b
        ldy     #$0100
        sty     zBG2HScroll
        sty     zBG3HScroll
        jsr     InitRageList
        lda     #$1d
        sta     zMenuState
        rts
.endif

; ------------------------------------------------------------------------------

; [ skills menu $06: dance (init) ]

SkillsOption_06:
@21de:  stz     $4a
        jsr     LoadAbilityCursor
        jsr     InitAbilityCursor
        ldy     #$0100
        sty     zBG2HScroll
        sty     zBG3HScroll
        jsr     DrawDanceMenu
        lda     #$1c
        sta     zMenuState
        rts

; ------------------------------------------------------------------------------

; [ menu state $0c: status ]

MenuState_0c:
@21f5:  jsr     InitDMA1BG3ScreenA

; shoulder R button
        lda     z08
        bit     #JOY_R
        beq     @221e
        lda     zSelIndex
        sta     $79
@2202:  clr_a
        lda     zSelIndex
        inc
        and     #$03
        sta     zSelIndex
        tax
        lda     zCharID,x
        bmi     @2202
        lda     zSelIndex
        cmp     $79
        beq     @2218
        jsr     PlayMoveSfx
@2218:  jsr     InitStatusCursor
        jmp     _c35d83

; shoulder L button
@221e:  lda     z08
        bit     #JOY_L
        beq     @2244
        lda     zSelIndex
        sta     $79
@2228:  clr_a
        lda     zSelIndex
        dec
        and     #$03
        sta     zSelIndex
        tax
        lda     zCharID,x
        bmi     @2228
        lda     zSelIndex
        cmp     $79
        beq     @223e
        jsr     PlayMoveSfx
@223e:  jsr     InitStatusCursor
        jmp     _c35d83

; B button
@2244:  lda     z08+1
        bit     #>JOY_B
        beq     @2254
        jsr     PlayCancelSfx
        lda     #$04
        sta     zNextMenuState
        stz     zMenuState
        rts
@2254:  clr_a
        lda     zSelIndex
        asl
        tax
        ldy     zCharPropPtr,x
        lda     0,y
        cmp     #CHAR_PROP::GOGO
        bne     @22b3                   ; return if not Gogo
        jsr     UpdateGogoStatusCursor

; A button
        lda     z08
        bit     #JOY_A
        beq     @22b3
        jsr     PlaySelectSfx
        lda     $4b
        sta     $e7
        stz     $e8
        clr_a
        lda     zSelIndex
        asl
        tax
        ldy     zCharPropPtr,x
        longa
        tya
        clc
        adc     $e7
        tay
        shorta
        lda     $0016,y
        cmp     #$12
        beq     @22b3
        jsr     _c32f06
        lda     $4e
        sta     $5e
        lda     $4b
        sta     $64
        lda     #$06
        sta     zWaitCounter
        ldy     #12
        sty     zMenuScrollRate
        lda     #$6a
        sta     zNextMenuState
        lda     #$65
        sta     zMenuState
        jsr     LoadGogoCmdListCursor
        lda     $7e9d89
        sta     $54
        jmp     InitGogoCmdListCursor
@22b3:  rts

; ------------------------------------------------------------------------------

; [ menu state $6b: unused ]

MenuState_6b:
@22b4:  lda     z08+1
        bit     #>JOY_B
        beq     @22c4
        jsr     PlayCancelSfx
        lda     #$04
        sta     zNextMenuState
        stz     zMenuState
        rts
@22c4:  rts

; ------------------------------------------------------------------------------

; [ menu state $0e: config ]

MenuState_0e:
@22c5:  jsr     InitDMA1BG1ScreenAB
        lda     z0a+1
        bit     #$04
        beq     @22e0
        lda     $4e
.if LANG_EN
        cmp     #$08
.else
        cmp     #$09
.endif
        bne     @22e0
        lda     #$50
        sta     zMenuState
        lda     #$11
        sta     zWaitCounter
        jsr     PlayMoveSfx
        rts
@22e0:  lda     z0a+1
        bit     #$08
        beq     @22fa
        lda     $4e
        bne     @22fa
        lda     $4a
        beq     @22fa
        lda     #$51
        sta     zMenuState
        lda     #$11
        sta     zWaitCounter
        jsr     PlayMoveSfx
        rts
@22fa:  lda     $4a
        beq     @2303
        jsr     UpdateConfigPage2Cursor
        bra     @2306
@2303:  jsr     UpdateConfigPage1Cursor

; B button
@2306:  lda     z08+1
        bit     #>JOY_B
        beq     @2316
        jsr     PlayCancelSfx
        lda     #$04
        sta     zNextMenuState
        stz     zMenuState
        rts

; left or right button
@2316:  lda     z0a+1
        bit     #$01
        bne     @2322
        lda     z0a+1
        bit     #$02
        beq     @2325
@2322:  jmp     ChangeConfigOption

; A button
@2325:  lda     z08
        bit     #JOY_A
        jne     SelectConfigOption
        jmp     ScrollConfigPage

; ------------------------------------------------------------------------------

; [ select config option ]

SelectConfigOption:
@2331:  lda     $4e
        sta     $5f
        lda     $4a
        bne     SelectConfigOptionPage2

; page 1
        clr_a
        lda     $4b
        asl
        tax
        jmp     (near SelectConfigOptionTbl1,x)

; ------------------------------------------------------------------------------

; config options that can't be selected
SelectConfigOptionReturn:
@2341:  rts

; ------------------------------------------------------------------------------

SelectConfigOptionPage2:
@2342:  clr_a
        lda     $4b
        asl
        tax
        jmp     (near SelectConfigOptionTbl2,x)

; ------------------------------------------------------------------------------

; config option jump table (page 1)
SelectConfigOptionTbl1:
@234a:  .addr   SelectConfigOptionReturn
        .addr   SelectConfigOptionReturn
        .addr   SelectConfigOptionReturn
        .addr   SelectConfigOption_03
        .addr   SelectConfigOptionReturn
        .addr   SelectConfigOptionReturn
        .addr   SelectConfigOptionReturn
        .addr   SelectConfigOptionReturn
.if !LANG_EN
        .addr   SelectConfigOption_08j
.endif
        .addr   SelectConfigOption_08

; config option jump table (page 2)
SelectConfigOptionTbl2:
@235c:  .addr   SelectConfigOptionReturn
        .addr   SelectConfigOptionReturn
        .addr   SelectConfigOption_0b
        .addr   SelectConfigOption_0c
        .addr   SelectConfigOption_0d
        .addr   SelectConfigOption_0e

; ------------------------------------------------------------------------------

; [ open custom battle command menu ]

SelectConfigOption_03:
@2368:  lda     $1d4d
        bit     #$80
        beq     SelectConfigOptionReturn
        jsr     PlaySelectSfx
        lda     #$47
        sta     zNextMenuState
        stz     zMenuState
        rts

; ------------------------------------------------------------------------------

.if !LANG_EN

; [  ]

SelectConfigOption_08j:
@2379:  lda     $1d54
        bit     #$40
        beq     SelectConfigOptionReturn
        jsr     PlaySelectSfx
        lda     #$49
        sta     zNextMenuState
        stz     zMenuState
        rts

.endif

; ------------------------------------------------------------------------------

; [ open character controller select menu ]

SelectConfigOption_08:
@2379:  lda     $1d54
        bpl     SelectConfigOptionReturn
        jsr     PlaySelectSfx
        lda     #$4b
        sta     zNextMenuState
        stz     zMenuState
        rts

; ------------------------------------------------------------------------------

; [ revert font color or window color component to default ]

SelectConfigOption_0b:
SelectConfigOption_0c:
SelectConfigOption_0d:
SelectConfigOption_0e:
@2388:  jsr     PlaySelectSfx
        lda     $1d54
        and     #$38
        beq     @239b

; window color
        jsr     RevertWindowPal
        jsr     LoadWindowGfx
        jmp     UpdateConfigColorBars

; font color
@239b:  ldy     #$7fff                  ; revert font color to default
        sty     $1d55
        jsr     InitFontColor
        jmp     UpdateConfigColorBars

; ------------------------------------------------------------------------------

; [ revert window palette to default ]

RevertWindowPal:
@23a7:  clr_a
        lda     $1d4e                   ; window index
        and     #$0f

; calculate pointers to window palette in rom and sram
        longa
        tay
        stz     $eb
        stz     $ed
@23b4:  dey
        bmi     @23c9
        lda     #14                     ; palettes are 7 colors in SRAM
        clc
        adc     $eb
        sta     $eb
        lda     #$0020                  ; palettes are 16 colors in ROM
        clc
        adc     $ed
        sta     $ed
        bra     @23b4

; copy default palette to SRAM and WRAM
@23c9:  ldx     #$312b
        stx     hWMADDL
        lda     $eb
        tay
        lda     $ed
        tax
        shorta
        lda     #14                     ; copy 14 bytes (7 colors)
        sta     $e9
@23db:  lda     f:WindowPal+2,x
        sta     $1d57,y
        sta     hWMDATA
        inx
        iny
        dec     $e9
        bne     @23db
        rts

; ------------------------------------------------------------------------------

; [ config menu page scroll ]

ScrollConfigPage:
@23ec:  lda     z08                     ; check L and R buttons
        bit     #JOY_R
        bne     @23f6
        bit     #JOY_L
        beq     @240b
@23f6:  jsr     PlayMoveSfx
        stz     $5f
        lda     $4a
        bne     @2406
        lda     #1
        sta     $4a
        jmp     ShowConfigPage2
@2406:  stz     $4a
        jsr     ShowConfigPage1
@240b:  rts

; ------------------------------------------------------------------------------

; [ menu state $0f: order (select character) ]

MenuState_0f:
@240c:  jsr     UpdateTimeText
        jsr     _c36989
        lda     z08+1
        bit     #>JOY_B
        bne     @241e
        lda     z08+1
        bit     #>JOY_RIGHT
        beq     @2437
@241e:  jsr     PlayCancelSfx
        lda     #$06
        sta     zWaitCounter
        ldy     #12
        sty     zMenuScrollRate
        lda     #$05
        trb     z46
        lda     #$03
        sta     zNextMenuState
        lda     #$65
        sta     zMenuState
        rts
@2437:  lda     z08
        bit     #JOY_A
        beq     @2452
        jsr     PlaySelectSfx
        lda     $4b
        sta     zSelIndex
        lda     #$10
        sta     zMenuState
        jsr     _c32f21
        jsr     LoadCharSelectCursorProp
        lda     $4e
        sta     $5e
@2452:  rts

; ------------------------------------------------------------------------------

; [ menu state $10: order (move/row) ]

MenuState_10:
@2453:  jsr     UpdateTimeText
        lda     z08+1
        bit     #>JOY_B
        beq     @246f       ; branch if b button is not pressed

; cancel
        jsr     PlayCancelSfx
        lda     #$01
        trb     z46         ; disable flashing cursor task
        lda     #$0f
        sta     zMenuState         ; menu state $0f (order, select character)
        jsr     InitCharSelectCursor
        lda     $5e
        sta     $4e         ; restore cursor position
        rts

; no cancel
@246f:  lda     z08
        bit     #JOY_A
        beq     @24a8       ; return if a button is not pressed
        jsr     PlaySelectSfx
        lda     zSelIndex
        cmp     $4b
        bne     @2491       ; branch if order changed

; character row changed
        lda     #$01
        trb     z46         ; disable flashing cursor task
        lda     #$12        ; menu state $12 (order, wait for portrait slide)
        sta     zMenuState
        jsr     _c32e10
        ldy     #12
        sty     zWaitCounter         ; wait 12 frames
        jmp     InitCharSelectCursor

; party order changed
@2491:  lda     #$10
        trb     z46
        lda     #$0c
        trb     z45
        jsr     CreateCharSwapTask
        lda     #$18        ; set frame counter to 24 (12 frames to hide, 12 frames to show)
        sta     z22
        lda     #$01
        trb     z46
        lda     #$11        ; menu state $11 (change party order)
        sta     zMenuState
@24a8:  rts

; ------------------------------------------------------------------------------

; [ menu state $11: change party order ]

MenuState_11:
@24a9:  jsr     UpdateTimeText
        lda     z22
        beq     @24e0
        cmp     #$0c
        bne     @24ed
        jsr     UpdatePlayer2Chars
        jsr     _c32dd1
        jsr     _c324ee
        jsr     ClearBG1ScreenA
        jsr     DrawCharBlock1
        jsr     DrawCharBlock2
        jsr     DrawCharBlock3
        jsr     DrawCharBlock4
        jsr     SwapSavedCharCursorPos
        jsr     InitDMA1BG1ScreenA
        jsr     InitCharSelectCursor
        jsr     ExecTasks
        jsr     WaitVblank
        lda     #$08
        tsb     z45
        rts
@24e0:  lda     #$0f        ; menu state $0f (order, select character)
        sta     zMenuState
        lda     #$10
        tsb     z46
        lda     #$04
        tsb     z45
        rts
@24ed:  rts

; ------------------------------------------------------------------------------

; [  ]

_c324ee:
@24ee:  jsr     _c32e3c
        lda     #$01
        trb     $47
        jmp     ExecTasks

; ------------------------------------------------------------------------------

; [ update characters controlled by player 2 ]

UpdatePlayer2Chars:
@24f8:  clr_ax
        stx     $e0
        stx     $e2
        lda     $1d4f
        clc
@2502:  ror
        bcc     @2507
        inc     $e0,x
@2507:  inx
        cpx     #$0004
        bne     @2502
        clr_a
        lda     $4b
        tax
        lda     $e0,x
        sta     $e5
        lda     zSelIndex
        tax
        lda     $e0,x
        sta     $e6
        lda     $e5
        sta     $e0,x
        lda     $4b
        tax
        lda     $e6
        sta     $e0,x
        clc
        lda     $e3
        asl
        adc     $e2
        asl
        adc     $e1
        asl
        adc     $e0
        sta     $1d4f
        rts

; ------------------------------------------------------------------------------

; [ menu state $12: order (wait for portrait slide) ]

MenuState_12:
@2537:  ldy     zWaitCounter
        bne     @253f
        lda     #$0f        ; menu state $0f (order, select character)
        sta     zMenuState
@253f:  rts

; ------------------------------------------------------------------------------

; [ menu state $14: save select ]

MenuState_14:
@2540:  lda     $4b
        inc
        sta     zSelSaveSlot
        jsr     DrawSaveMenuChars
        jsr     UpdateGameSaveCursor

; B button
        lda     z08+1
        bit     #>JOY_B
        beq     @255d                   ; branch if B button is not pressed
        jsr     PlayCancelSfx
        lda     $9f
        sta     zNextMenuState
        lda     #$53
        sta     zMenuState
        rts

; A button
@255d:  lda     z08
        bit     #JOY_A
        beq     @259c                   ; return if A button is not pressed
        clr_a
        lda     $4b
        asl
        tax
        ldy     $91,x                   ; sram checksum
        bne     @2580                   ; branch if sram is valid

; slot is empty, save instantly
        jsr     PlaySuccessSfx
        jsr     SaveGame
        lda     $9e                     ; previous menu state
        sta     zNextMenuState
        lda     #$53                    ; menu state $53 (fade out, save menu)
        sta     zMenuState
        rts

; sram valid, prompt before overwriting
@2580:  jsr     PlaySelectSfx
        jsr     PushSRAM
        lda     $4b
        inc
        sta     zSelSaveSlot
        jsr     LoadSaveSlot
        jsr     InitCharProp
        jsr     _c36989
        lda     #$15                    ; next menu state $15 (save confirm, init)
        sta     zNextMenuState
        lda     #$53                    ; menu state $53 (fade out, save menu)
        sta     zMenuState
@259c:  rts

; ------------------------------------------------------------------------------

; [ menu state $16 & $1f: save confirm ]

MenuState_16:
MenuState_1f:
@259d:  jsr     UpdateSaveConfirmCursor
        lda     z08+1
        bit     #>JOY_B
        bne     @25c2       ; branch if b button is down
        lda     z08
        bit     #JOY_A
        beq     @25de       ; return if a button is not pressed
        lda     $4b
        bne     @25c7
        jsr     PlaySuccessSfx
        jsr     SaveGame
        lda     $9e         ; previous menu state
        sta     zNextMenuState
        stz     zMenuState         ; menu state $00 (fade out)
        rts
@25c2:  jsr     PlayCancelSfx
        bra     @25ca
@25c7:  jsr     PlaySelectSfx
@25ca:  jsr     PopSRAM
        jsr     InitCharProp
        jsr     _c36989
        lda     #$13        ; menu state $13 (save select, init)
        sta     zNextMenuState
        stz     zMenuState
        lda     zSelSaveSlot
        sta     wSelSaveSlot
@25de:  rts

; ------------------------------------------------------------------------------

; [ save game ]

SaveGame:
@25df:  jsr     PopSRAM
        jsr     InitCharProp
        jsr     _c36989
        longa
        inc     $1dc7       ; increment the number of times the game has been saved
        shorta
        lda     zSelSaveSlot
        jmp     CopyGameDataToSRAM

; ------------------------------------------------------------------------------

; [ menu state $17: item options (use, arrange, rare) ]

MenuState_17:
@25f4:  lda     #$c0
        trb     z46
        lda     #$10
        tsb     z45
        jsr     InitDMA1BG1ScreenA
        jsr     UpdateItemOptionCursor

; B button
        lda     z08+1
        bit     #>JOY_B
        beq     @2611
        jsr     PlayCancelSfx
        lda     #$04
        sta     zNextMenuState
        stz     zMenuState

; A button
@2611:  lda     z08
        bit     #JOY_A
        beq     @261d
        jsr     PlaySelectSfx
        jsr     SelectItemOption
@261d:  rts

; ------------------------------------------------------------------------------

; [ select an item option (use, arrange, rare) ]

SelectItemOption:
@261e:  clr_a
        lda     $4b
        asl
        tax
        jmp     (near SelectItemOptionTbl,x)

; ------------------------------------------------------------------------------

SelectItemOptionTbl:
@2626:  .addr   SelectItemOption_00
        .addr   SelectItemOption_01
        .addr   SelectItemOption_02

; ------------------------------------------------------------------------------

; [ select use items ]

SelectItemOption_00:
@262c:  jsr     LoadItemListCursor
        lda     $1d4e
        and     #$40
        beq     @263b
        jsr     RestoreItemCursorPos
        bra     @264b
@263b:  lda     w0231
        sta     $4a
        ldy     $4d
        sty     $4f
        lda     $4a
        clc
        adc     $50
        sta     $50
@264b:  jsr     InitItemListCursor
        jsr     InitItemListText
        jsr     InitItemDesc
        jsr     InitDMA1BG3ScreenA
        jsr     WaitVblank
        jsr     CreateScrollArrowTask1
        longa
.if LANG_EN
        lda     #$0070
.else
        lda     #$00ea
.endif
        sta     wTaskSpeedY,x
        lda     #$0058
        sta     wTaskSpeedX,x
        shorta
        lda     #$08
        sta     zMenuState
        lda     #0
        ldy     #near BigTextTask
        jsr     CreateTask
        rts

; ------------------------------------------------------------------------------

; [ arrange items ]

SelectItemOption_01:
@267c:  jsr     ClearBG1ScreenA
        jsr     _c326b8
        jsr     SortItemsByIcon
        jsr     DrawItemList
        jsr     LoadItemOptionCursor
        jmp     GotoItemOption

; ------------------------------------------------------------------------------

; [ select rare items ]

SelectItemOption_02:
@268e:  jsr     LoadRareItemCursor
        lda     $1d4e
        and     #$40
        beq     @269d
        ldy     w0232
        sty     $4d
@269d:  jsr     InitRareItemCursor
        jsr     InitRareItemList
        jsr     InitBigText
        jsr     InitRareItemDesc
        jsr     InitDMA1BG3ScreenA
        jsr     WaitVblank
        lda     #$c0
        trb     z46
        lda     #$18
        sta     zMenuState
        rts

; ------------------------------------------------------------------------------

; [  ]

_c326b8:
@26b8:  clr_ax
@26ba:  lda     $1869,x
        sta     $7eaa8d,x
        lda     #$ff
        sta     $1869,x
        inx
        cpx     #$0100
        bne     @26ba
        clr_ax
@26ce:  lda     $1969,x
        sta     $7eab8d,x
        clr_a
        sta     $1969,x
        inx
        cpx     #$0100
        bne     @26ce
        rts

; ------------------------------------------------------------------------------

; [ sort items by their icon ]

SortItemsByIcon:
@26e0:  clr_ayx
@26e3:  lda     f:ItemIconTbl,x
        phx
        sta     $e0
        jsr     FindItemsWithIcon
        plx
        inx
        cpx     #$0011
        bne     @26e3
        rts

; ------------------------------------------------------------------------------

ItemIconTbl:
.if LANG_EN
@26f5:  .byte   $ff,$d8,$d9,$da,$db,$dc,$dd,$de,$df,$e0,$e1,$e2,$e3,$e4,$e5,$e6,$e7
.else
        .byte   $ff,$e3,$e4,$e5,$e6,$e7,$e8,$e9,$ea,$eb,$ec,$ed,$f0,$f1,$f2,$f3,$f4
.endif

; ------------------------------------------------------------------------------

; [ find all items with this icon ]

; $e0: icon to find

FindItemsWithIcon:
@2706:  clr_ax
@2708:  phx
        lda     $7eaa8d,x
        cmp     #$ff
        beq     @2739
        sta     hWRMPYA
        lda     #ItemName::ITEM_SIZE
        sta     hWRMPYB
        nop3
        ldx     hRDMPYL
        lda     f:ItemName,x
        cmp     $e0
        bne     @2739
        plx
        lda     $7eaa8d,x
        sta     $1869,y
        lda     $7eab8d,x
        sta     $1969,y
        iny
        bra     @273a
@2739:  plx
@273a:  inx
        cpx     #$0100
        bne     @2708
        rts

; ------------------------------------------------------------------------------

; [ menu state $18: item (rare item select) ]

MenuState_18:
@2741:  lda     #$10
        trb     z45
        jsr     InitDMA1BG1ScreenA
        jsr     UpdateRareItemCursor
        jsr     InitRareItemDesc
        lda     z08+1
        bit     #>JOY_B
        beq     @2778
        jsr     PlayCancelSfx
        lda     #$17
        sta     zMenuState
        ldy     $4d
        sty     w0232
        jsr     LoadItemOptionCursor
        lda     $1d4e
        and     #$40
        beq     @276f
        ldy     w0234
        sty     $4d
@276f:  jsr     InitItemOptionCursor
        jsr     ClearItemCount
        jmp     InitDMA1BG3ScreenA
@2778:  rts

; ------------------------------------------------------------------------------

; [ menu state $19: item (move) ]

MenuState_19:
@2779:  jsr     InitDMA1BG1ScreenA
        jsr     UpdateItemListCursor
        jsr     InitItemDesc
        lda     z08+1
        bit     #>JOY_B
        beq     @2794
        jsr     PlayCancelSfx
        lda     #$01
        trb     z46
        lda     #$08
        sta     zMenuState
        rts
@2794:  lda     z08
        bit     #JOY_A
        beq     @27e1       ; branch if a button is not pressed
        jsr     PlaySelectSfx
        lda     zSelIndex
        cmp     $4b
        bne     @27aa
        lda     #$01
        trb     z46
        jmp     UseItem
@27aa:  lda     #$10
        tsb     z45
        lda     #$01
        trb     z46
        lda     #$08
        sta     zMenuState
        clr_a
        lda     zSelIndex
        tay
        lda     $1869,y     ; swap item slots
        sta     $e0
        lda     $1969,y
        sta     $e1
        clr_a
        lda     $4b
        tax
        lda     $1869,x
        sta     $1869,y
        lda     $e0
        sta     $1869,x
        lda     $1969,x
        sta     $1969,y
        lda     $e1
        sta     $1969,x
        jmp     DrawItemList
@27e1:  rts

; ------------------------------------------------------------------------------

; [ menu state $1a: magic (select) ]

MenuState_1a:
@27e2:  lda     #$10
        trb     z45
        lda     #LIST_TYPE::MAGIC
        sta     zListType
        jsr     InitDMA1BG1ScreenA
        lda     wGameTimeFrames
        ror
        bcc     @27f8
        jsr     InitDMA2BG3ScreenB
        bra     @27fb
@27f8:  jsr     TfrBigTextGfx
@27fb:  jsr     ScrollListPage
        bcs     @2861
        jsr     UpdateMagicCursor
        jsr     LoadMagicDesc
        jsr     _c351c6
        lda     z08+1
        bit     #>JOY_Y
        beq     @2822
        jsr     PlaySelectSfx
        lda     $9e
        not_a
        sta     $9e
        lda     #$10
        tsb     z45
        jsr     _c34f1c
        jmp     DrawMagicList
@2822:  lda     z08
        bit     #JOY_A
        beq     @2855
        clr_a
        lda     $4b
        tax
        lda     $7e9e09,x
        cmp     #$20
        bne     @2862
        jsr     PlaySelectSfx
        ldy     $4f
        sty     $8e
        lda     $4a
        sta     $90
        lda     $4b
        sta     $99
        jsr     GetSelMagic
        cmp     #$12
        beq     @2869       ; branch if x-zone
        cmp     #$2a
        beq     @2874       ; branch if warp
        lda     #$3a
        sta     zNextMenuState
        stz     zMenuState
        rts
@2855:  lda     z08+1
        bit     #>JOY_B
        beq     @2861
        jsr     InitDMA1BG1ScreenA
        jsr     ReloadSkillsMenu
@2861:  rts
@2862:  jsr     PlayInvalidSfx
        jsr     CreateMosaicTask
        rts

; x-zone
@2869:  lda     w0201
        bit     #$01
        beq     @2862       ; branch if x-zone is disabled
        lda     #$04        ; return code $04
        bra     @287d

; warp
@2874:  lda     w0201
        bit     #$02
        beq     @2862       ; branch if warp is disabled
        lda     #$03        ; return code $03
@287d:  sta     w0205
        jsr     _c32cea
        lda     #$ff        ; exit menu
        sta     zNextMenuState
        stz     zMenuState
        rts

; ------------------------------------------------------------------------------

; [ menu state $1b: lore (select) ]

MenuState_1b:
@288a:  lda     #$10
        trb     z45
        lda     #LIST_TYPE::LORE
        sta     zListType
        jsr     InitDMA1BG1ScreenA
        jsr     ScrollListPage
        bcs     @28a9
        jsr     UpdateLoreCursor
        jsr     LoadLoreDesc
        lda     z08+1
        bit     #>JOY_B
        beq     @28a9
        jsr     ReloadSkillsMenu
@28a9:  rts

; ------------------------------------------------------------------------------

; [ menu state $1c: dance (select) ]

MenuState_1c:
@28aa:  jsr     InitDMA1BG1ScreenA
        jsr     UpdateAbilityCursor
        lda     z08+1
        bit     #>JOY_B
        beq     @28b9
        jsr     ReloadSkillsMenu
@28b9:  rts

; ------------------------------------------------------------------------------

; [ menu state $1d: rage (select) ]

MenuState_1d:
@28ba:  lda     #LIST_TYPE::RAGE
        sta     zListType
        jsr     InitDMA1BG1ScreenA
        jsr     ScrollListPage
        bcs     @28d2
        jsr     UpdateRageCursor
        lda     z08+1
        bit     #>JOY_B
        beq     @28d2
        jsr     ReloadSkillsMenu
@28d2:  rts

; ------------------------------------------------------------------------------

; [ menu state $1e: espers (select) ]

MenuState_1e:
@28d3:  lda     #$10
        trb     z45
        lda     #LIST_TYPE::GENJU
        sta     zListType
        jsr     InitDMA1BG1ScreenA
        jsr     ScrollListPage
        bcs     @2928
        jsr     UpdateGenjuCursor
        jsr     LoadGenjuAttackDesc

; A button
        lda     z08
        bit     #JOY_A
        beq     @291b
        jsr     PlaySelectSfx
        clr_a
        lda     $4b
        tax
        lda     $7e9d89,x
        cmp     #$ff
        beq     @2908

; open esper detail menu
        sta     $99
        jsr     InitEsperDetailMenu
        lda     #$4d
        sta     zMenuState
        rts

; unequip esper
@2908:  lda     #$ff
        sta     $e0
        jsr     _c32929
        jsr     DrawGenjuList
        jsr     InitDMA1BG1ScreenB
        jsr     WaitVblank
        jmp     InitDMA1BG1ScreenA

; B button
@291b:  lda     z08+1
        bit     #>JOY_B
        beq     @2928
        lda     #$08
        trb     z46
        jsr     ReloadSkillsMenu
@2928:  rts

; ------------------------------------------------------------------------------

; [  ]

_c32929:
@2929:  clr_a
        lda     zSelIndex
        asl
        tax
        ldy     zCharPropPtr,x
        lda     $e0
        sta     $001e,y
        lda     $e0
        jmp     _c34f08

; ------------------------------------------------------------------------------

; [ menu state $34: wait for esper equip error message ]

MenuState_34:
@293a:  ldy     zWaitCounter
        bne     @2947
        ldy     #near GenjuBlankMsg
        jsr     DrawPosKana
        jmp     _c35913
@2947:  rts

; ------------------------------------------------------------------------------

; blank text to clear esper equip error
GenjuBlankMsg:
.if LANG_EN
@2948:  .byte   $cd,$40,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        .byte   $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$00
.else
        .byte   $dd,$40,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        .byte   $ff,$ff,$ff,$ff,$00
.endif

; ------------------------------------------------------------------------------

; [ menu state $39: party equipment overview ]

MenuState_39:
@2966:  lda     z08+1                     ; wait for B button
        bit     #>JOY_B
        beq     @2976
        jsr     PlayCancelSfx
        lda     #$04
        sta     zNextMenuState
        stz     zMenuState
        rts
@2976:  rts

; ------------------------------------------------------------------------------

; [ menu state $33: blitz menu ]

MenuState_33:
@2977:  lda     #$10
        trb     z45
        jsr     InitDMA1BG1ScreenA
.if LANG_EN
        jsr     UpdateBlitzCursor       ; #46: one column of eight, not Dance's 2x4
.else
        jsr     UpdateAbilityCursor
.endif
        jsr     LoadBlitzDesc
        lda     z08+1
        bit     #>JOY_B
        beq     @298d
        jsr     ReloadSkillsMenu
@298d:  rts

; ------------------------------------------------------------------------------

; [ menu state $3e: swdtech menu ]

MenuState_3e:
@298e:  lda     #$10
        trb     z45
        jsr     InitDMA1BG1ScreenA
        jsr     UpdateAbilityCursor
        jsr     LoadBushidoDesc
.if LANG_EN
        lda     z08+1
        bit     #>JOY_B
        beq     @29a4
        jsr     ReloadSkillsMenu
.else
        lda     z08
        bit     #JOY_A
        beq     @2a2a
        clr_a
        lda     z4b
        tax
        lda     $7e9d89,x
        bmi     @2a24
        sta     w0206
        lda     #$ff
        sta     w0205
        lda     #$ff
        sta     zNextMenuState
        stz     zMenuState
        rts
@2a24:
.if LANG_EN
        jsr     InitDMA1BG1ScreenA
        jsr     ReloadSkillsMenu
.else
        jsr     PlayInvalidSfx
        jsr     CreateMosaicTask
.endif
@2a2a:  lda     z08+1
        bit     #>JOY_B
        beq     @29a4
        jsr     ClearBG3ScreenB
        jsr     _c3a662
        jsr     InitDMA1BG3ScreenB
        jsr     WaitVblank
        jsr     ReloadSkillsMenu
.endif
@29a4:  rts

; ------------------------------------------------------------------------------

; [ reload to skills menu ]

ReloadSkillsMenu:
@29a5:  jsr     PlayCancelSfx
        ldy     z0
        sty     zBG2HScroll
        sty     zBG3HScroll
        lda     #$0a
        sta     zMenuState
        jsr     _c34d27
        jsr     LoadSkillsCursor
        lda     $5e
        sta     $4e
        jsr     InitSkillsCursor
        jmp     _c35807

; ==============================================================================
; BUSHIDO LOADOUT CONFIGURATOR (issue #8 Layer B) -- thin C3 shim over bank F0
;
; Skills -> SwdTech opens this in place of the vanilla browse list: the browse
; list only NAMED the learned techs, and this names them too (the LEARNED pool)
; beside the four editable boost slots, so nothing is lost.  Every decision --
; seed-from-auto, each slot's validated tech, assign/cycle, revert, the write to
; $1e1d -- is made by the OT6 bank-F0 procs jsl'd below; the code here does only
; the tilemap / cursor / DMA framework work that MUST run in the menu bank.
;
;   Up / Down   move the cursor over the four boost slots (0x..3x)
;   L / R       cycle the cursored slot through the LEARNED techs (first edit
;               flips the loadout to MANUAL)
;   Y           revert to AUTO (reseed the slots from the moving window).  Y and
;               not Select: FF6's default pad config aliases physical Select onto
;               the R bit, so it can't be distinguished from the R-shoulder cycle.
;   B           save-and-exit (writes are already live in the checksummed block)
;
; MP cost is priced through Ot6LoadoutCost (returns 0 under nomp, so that build
; simply draws no number -- the shared menu object links against either battle).
; ------------------------------------------------------------------------------
.if LANG_EN

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
; and the 0x row is gone.  Row i (0..2) draws WORD SLOT i+1 -- the stored format
; is untouched (four 3-bit fields at $1e1d), slot 0 is simply never read.
;
; THE 12-PIXEL CADENCE (issue #43), and why every row on this page is ODD.
; The EN field-menu window does NOT show BG1 ScreenA one tile row per eight
; scanlines: a tilemap row PAIR is displayed in twelve scanlines, the odd row
; getting eight of them and the even row four, and nothing past row 15 is
; inside the window at all.  Measured with a per-row glyph ruler poked into the
; shadow (tools/tests/probe_ragegeom.lua): odd rows 1,3,5,..,15 render whole at
; screen y = 116 + 6*(row-1); even rows show only their bottom three scanlines.
; Vanilla says the same from the other side -- every EN cursor list for this
; window is `cursor_pos {x, 116 + n*12}` (skills.asm:125-126, :249-250,
; :292-293) and DrawRageName biases its row `.if LANG_EN` (skills.asm:1571-1574).
;
; This page shipped with its slots on EVEN rows 4/6/8 and its LEARNED grid on
; 15/17/19/21, so every tech name was a four-scanline sliver beside a
; full-height title and three of the pool's four rows were off the bottom of
; the window.  #39 fixed the page's GLYPHS; this is its geometry.  The layout
; is now vanilla's own shape for this window -- eight usable text rows:
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
; The page needs NINE rows and the window has eight, so the pool's caption
; rides the title row -- the same resolution the Rage page used for its price
; line, and the title row is the one row where a second blue chrome word
; cannot be misread as a slot's data.
;
; #44: and a THIRD word rides it, the L/R control hint.  With all eight rows
; spoken for, the room came out of the title -- "BUSHIDO LOADOUT" (cols 3-17)
; became "SWDTECH" (3-9), which is also the name every other EN string uses for
; this skill and the name of the row the player picked to get here.  The only
; other free run on the page is columns 23-29 of the three slot rows, seven
; cells wide and split across three rows; nothing legible fits there.  See
; OT6_LOADOUT_HINT in menu_text_en.inc.
;
; THE CURSOR GUTTER (#43, third round), and why every column above is one
; further right than it shipped.  `cursor_pos {x,y}` is the top-left of a 16x16
; sprite, so the cursor at x=8 owns tilemap columns 1 AND 2 -- it drew straight
; over the "1" of "1x" at column 2.  Vanilla's rule is exactly
; cursor_x = 8*col - 16, without exception: magic 3/16 under 8/112
; (skills.asm:831,:836 vs :125-126), espers 3/17 under 8/120 (:1733,:1737 vs
; :249-250), rage 5/19 under 24/136 (:1544,:1548 vs :292-293), config col 14
; under 96 (config.asm:50).  The cursor table below was already vanilla's;
; the TEXT was one column too far left.  Everything shifts by one and the
; window's own right border is still column 30.  The pool's right column moves
; 16 -> 17 with it, keeping the two-column gutter between two full-width names
; ("Quadra Slice" fills all twelve cells); a 12-cell name at 17 ends at 28,
; still inside the frame.
;
; THE COLUMN BUDGET (issue #56), and where the price field's second digit came
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
; because "nn MP" is five.  Of the two GAPS, the one at 23 is load-bearing --
; #49 measured "7 MPMANUAL" on screen without it -- and so is the one before
; the price, which is the only thing keeping "Quadra Slice" off "30 MP".
;
; So the donor is the gap between the rung LABEL and the name: names start at
; column 5 now, directly after "1x".  That gap is the one on the row whose two
; sides cannot be confused for each other -- a digit and a lowercase 'x' against
; a capitalised tech name -- where both of the others separate things that read
; as the same kind of token.  Screenshots of both a one-digit and a two-digit
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
        asl                             ; row = 3 + i*2 -- ODD rows 3/5/7 (#43)
        clc
        adc     #$03
        sta     $e6
        ldx     #$0005                  ; name column (5: right after "1x" at
        jsr     Ot6DrawBushName         ;   3-4 -- the budget note above)
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
        ; fallthrough -- #49: the mode block is drawn LAST on purpose, see below

; ---- #49: AUTO / MANUAL, and the control that gets back to AUTO ----
; The page's ONE free block is columns 23-29 of the three slot rows (surveyed in
; issue #49); the mode takes row 3 and the control that changes it row 5, so the
; two read as a pair.  Column 23 is spent as a SEPARATOR -- the slot's price
; field abuts it and a block starting at 23 renders the row as "7 MPMANUAL"
; (measured, the first screenshot of that change) -- so the six cells run 24-29,
; up to but not into the window's border column 30.
;
; #56 widened the price field to "nn MP" and moved it LEFT to 18-22 rather than
; letting it grow rightwards into 23, so this block and its separator are
; untouched by that change; the donor column came off the label/name gap on the
; other side of the row (the budget note over Ot6LoadoutDrawSlots).
;
; Drawn from HERE, at the tail of the slot redraw, rather than from
; Ot6LoadoutDrawC3 with the other chrome.  Two reasons and both matter:
;   * the mode is LIVE -- the first L/R cycle flips AUTO -> MANUAL and Y flips it
;     back, and Ot6LoadoutDrawSlots is the only thing that runs on a redraw
;     (MenuState_7b @run), so a mode drawn at init would state the state the page
;     was OPENED in for as long as the player stayed on it;
;   * Ot6LoadoutDrawCost's zero-cost arm blanks the FULL five-cell price field,
;     which under nomp (every row prices 0) is drawn on every redraw.  It now
;     stops at column 22 -- before #56 it started at 19 and ran through 23, i.e.
;     into the first cell of a block drawn earlier in the frame -- but drawing
;     after the slot loop is still what makes the ordering unconditionally safe.
; The hint is redrawn every time too; six cells is not worth a second code path
; to skip, and it removes the ordering hazard for good.
Ot6LoadoutDrawMode:
        jsl     Ot6LoadoutIsAuto        ; F0: carry set = AUTO (the packed word)
        lda     #$00
        bcs     :+
        lda     #$01                    ; MANUAL
:       sta     $e5                     ; -> Ot6DrawModeWord's selector
        lda     #BG1_TEXT_COLOR::DEFAULT
        sta     zTextColor              ; the mode is DATA, not chrome
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
; two can never come to disagree about what the words are or how wide the field
; is.  OT6_MODE_AUTO is space-padded to OT6_MODE_MANUAL's six cells, so a
; MANUAL -> AUTO revert overwrites the whole field -- the Ot6RageEmptyTiles rule.
Ot6DrawModeWord:
        lda     $e6
        jsr     GetBG1TilemapPtr        ; A = row, X = col -> X = tilemap dest
        longa
        txa
        sta     $7e9e89                 ; DrawPosTextBuf position header
        shorta
        ldx     #$9e8b
        stx     hWMADDL
        ldx     #$0000                  ; (long,X -- there is no long,Y mode)
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
Ot6ModeManualTiles:     raw_text OT6_MODE_MANUAL ; "MANUAL" + $00 -- encoded via
                        ; menu_text_en.inc; a bare literal here picks up
                        ; ending_anim.asm's credits charmap and carries no
                        ; terminator, which is what garbled the page in #39)

; ---- draw the LEARNED pool as a 2 x 4 grid on the window's ODD rows (#43) ----
; Column-major: filled cells 0..3 go down the left column (col 3), 4..7 down the
; right (col 17), both on rows 9/11/13/15.  All eight Bushido techs therefore
; fit INSIDE the window -- the old {15,17,19,21} grid put three of its four rows
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
; THE ONE MP-PRICE DRAWER FOR THE WHOLE FIELD MENU (issue #56).  This proc drew
; a SINGLE digit until v0.7 and said so in its own comment -- "kit costs 1..8",
; true when it was written.  #45 rescaled SwdTech to 4/10/13/16/18/22/30/46, so
; seven of the eight rungs printed `cost + ZERO_CHAR` past '9' ($bd) and came
; out as punctuation: Retort's 10 rendered as $be and Quadra Slice's 30 as '='
; (measured on the pre-change ROM, tools/tests/probe_swdtechcost.lua).  #46 had
; already hit the same wall on the Blitz ladder and answered it with a private
; copy, Ot6BlitzDrawCost in skills.asm, whose own report flagged the duplicate
; as the trap to remove; the copy is gone and its body is here, so there is one
; price drawer and a third page cannot inherit the single-digit version again.
;
; RIGHT-ALIGNED, with a LEADING BLANK and never a leading zero -- " 4 MP" sits
; under "30 MP" so a column of prices reads as a column.  That is vanilla's own
; rule for a menu number and not a new invention: HexToDec3 converts to three
; digits and then overwrites each leading '0' with $ff, the blank tile
; (menu_common.asm:906-918), and DrawNum2 prints the low two of those three
; (menu_common.asm:856-860) -- which is exactly how the esper/magic detail
; window prints a spell's MP (skills.asm:2615-2621).  A cost of 0 blanks all
; five cells: that is the nomp build (Ot6LoadoutCost returns 0 with no cost
; table linked) and the Blitz page's locked rows, and blanking the FULL width is
; what keeps the redraw-overwrites-what-was-there property every field on these
; pages has (the Ot6RageEmptyTiles rule).
;
; The arithmetic is a repeated subtract rather than a divide because 65816 has
; no divide and the values are two digits: `cmp #10` leaves C set on the taken
; branch, so the `sbc #10` under it is exact without a preceding `sec`.
;
; Costs above 99 would wrap into the tens loop silently.  Nothing in the game
; prices one, and as of issue #57 that is a DESIGN RULE rather than a lucky
; margin: the dearest row anywhere is Cleave/Bum Rush at exactly 99 -- each
; character's genuine ultimate is anchored there, and 99 is the largest number
; this drawer (and ListText cmd $02, btlgfx_main.asm:15045) can render at all
; (Ot6AbilityCostTbl, ot6_boost.asm).  tools/tests/menu_*page.lua assert every
; drawn field against that table and tools/tests/battle_costtable.lua asserts
; the <= 99 bound directly, so a three-digit price shows up as a red test
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
        lda     #$ff                    ; leading BLANK, not a leading zero
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
                        ; encoded via menu_text_en.inc -- a bare literal here
                        ; picks up ending_anim.asm's credits charmap)

; ---- cursor: single column, three rows over the boost slots (#38) ----
; y = 116 + n*12 is the EN field menu's text pitch for THIS window, copied from
; vanilla's own magic/esper/rage cursor tables (skills.asm:125-126, :249-250,
; :292-293).  Tilemap row = 2n + 1, so rows 3/5/7 are n = 1/2/3.  The old
; {30,46,62} was an 8px-per-row assumption and put the cursor above the window.
;
; x = 8 is vanilla's magic/esper left-column x, and it PAIRS WITH TEXT AT COLUMN
; 3 -- the sprite is 16x16 with cursor_pos as its top-left, so it covers columns
; 1-2 (measured: `cursor_pos {8,116}` lights screen x 8..23, y 116..131, from
; the shipped ROM's own magic list -- tools/tests/probe_menucols.lua).  Do not
; move this table to fix an overlap: move the TEXT.  The rule is
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
; the tilemap -- the garbled-page bug) ----
Ot6LoadoutTitleText:    pos_text OT6_LOADOUT_TITLE
Ot6LoadoutHintText:     pos_text OT6_LOADOUT_HINT
Ot6LoadoutModeHintText: pos_text OT6_LOADOUT_MODE_HINT  ; #49: "Y=AUTO" at {23,5}
Ot6LoadoutPoolText:     pos_text OT6_LOADOUT_POOL
Ot6LoadoutLbl1Text:     pos_text OT6_LOADOUT_LBL1
Ot6LoadoutLbl2Text:     pos_text OT6_LOADOUT_LBL2
Ot6LoadoutLbl3Text:     pos_text OT6_LOADOUT_LBL3

; ------------------------------------------------------------------------------
; GAU'S RAGE LOADOUT PAGE (issue #40) -- the MenuState_7b shim, at eight rows
;
; Every decision is bank-F0 (Ot6Rage* in ot6_kits.asm); this is tilemap, cursor
; and DMA only, exactly as the Bushido page's shim is.  Two shape differences,
; both forced by Gau's numbers: names come from MonsterName (255 candidates)
; instead of BushidoName (8), and there is no drawn "pool" grid -- the L/R
; cycle IS the browse, and a LEARNED count stands in for the grid.

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
        ldy     #near Ot6RageHintText           ; #44: "L/R SWAPS" on row 3
        jsr     DrawPosText
        ldy     #near Ot6RageLearnedText
        jsr     DrawPosText
        lda     #BG1_TEXT_COLOR::DEFAULT
        sta     zTextColor
        jsr     Ot6RagePrice
        jsr     Ot6RageDrawSlots
        jmp     Ot6RageDrawCount

; ---- the flat trance price, stated ONCE on the title row: "8 MP EACH" ----
; Blank under nomp -- the LABEL rides the number, so a zero price prints
; nothing rather than a bare "EACH".
;
; #56: the price field is five cells wide now, not four, and it starts at column
; 16 rather than 17 so that "EACH" (a fixed pos_text at 22) keeps its gap at 21.
; Growing rightwards instead would have rendered "10 MPEACH".  This page's price
; is 8 today and CAN reach two digits without anyone editing this file: it is a
; tail-call to Ot6DanceCost (ot6_boost.asm:600-619) -- deliberately Dance's own
; number and not a copy of it -- and mp-economy.md's band for a flat
; possess-verb price is 4-10.  The title row still fits: "RAGE LOADOUT" ends at
; 14, so 15 is the gap, the price is 16-20, 21 is the gap, "EACH" is 22-25.
Ot6RagePrice:
        jsl     Ot6RageRowCost          ; F0: A = MP cost (0 under nomp)
        beq     @none                   ; (rtl preserves the lda's Z)
        pha
        lda     #$01                    ; the title row
        sta     $e6
        ldx     #$0010                  ; col 16: "nn MP" is 16..20
        pla
        jsr     Ot6LoadoutDrawCost      ; the one field-menu price drawer (#56)
        ldy     #near Ot6RageEachText   ; ... and "EACH" at col 22
        jmp     DrawPosText
@none:  rts

; ---- draw the eight loadout rows (beast name; the price is on the title) ----
;
; THE 12-PIXEL CADENCE, and why the slots sit on ODD tilemap rows in two
; columns.  The EN field-menu window this page lives in does NOT show BG1
; ScreenA one tile row per eight scanlines: a tilemap row PAIR is displayed in
; twelve scanlines, the odd row getting eight of them and the even row four.
; Measured with a per-row glyph ruler poked straight into the shadow
; (probe_ragegeom.lua): odd rows 1,3,5,..,15 render whole at screen y =
; 116 + 6*(row-1); even rows show only their bottom three scanlines; nothing
; past row 15 is inside the window at all.  Vanilla's own tables say the same
; thing from the other side -- every EN cursor list for this window is
; `cursor_pos {x, 116 + n*12}` (skills.asm:125-126, :249-250, :292-293), and
; DrawRageName biases its row by one under `.if LANG_EN` (skills.asm:1571-1574)
; for exactly this reason.
;
; So the window holds EIGHT usable text rows, and the page needs ten (title,
; eight slots, LEARNED).  Two columns of four is the resolution, and it is
; also vanilla's shape for this very window (the rage browse is
; `cursor_prop {0,0}, {2,8}`, skills.asm:281-299):
;
;   row  1   RAGE LOADOUT                    8 MP EACH
;   row  3   L/R SWAPS       (#44: the control hint -- row 3 was spare)
;   row  5   slot 0 (col 3)  slot 1 (col 16)
;   row  7   slot 2          slot 3
;   row  9   slot 4          slot 5
;   row 11   slot 6          slot 7
;   row 15   LEARNED nnn
;
; THE CURSOR GUTTER (#43, third round).  Columns 3 and 16 are not free choices:
; `cursor_pos {x,y}` is the top-left of a 16x16 sprite, so a cursor at x owns
; tilemap columns x/8 and x/8+1 and the text it points at must start at
; x/8 + 2 -- cursor_x = 8*col - 16, vanilla's rule in every list it draws in
; this window (magic cols 3/16 under 8/112, skills.asm:831,:836 vs :125-126;
; espers 3/17 under 8/120, :1733,:1737 vs :249-250; rage 5/19 under 24/136,
; :1544,:1548 vs :292-293).  This page's RIGHT column was already correct --
; col 16 under `cursor_pos {112,...}` is vanilla's magic pair verbatim -- but
; the LEFT column shipped at col 2 under a cursor at x=8, so the sprite drew
; over the first letter of every left-hand beast name.  Only the left column
; moved; {3, 16} under {8, 112} is now magic's geometry exactly.
;
; THE PRICE IS STATED ONCE, on the title row, not once per row.  Not a
; simplification: two ten-cell monster names plus two cursor columns plus two
; four-cell "n MP" fields is 30 columns, and the window's own right border
; lives in column 30 (measured: the border rule is at screen x = 245).  The
; price is flat by design (kit-gau.md §5) -- eight identical copies of the same
; number was what did not fit, and one copy teaches the same rule.  Under nomp
; the cost is 0 and the whole "8 MP EACH" group is skipped, label included.
;
; Slot order is the cursor framework's own index -- $4b = cols*row + col
; (CalcShortListIndex) -- so slot even = left column, slot odd = right, and
; row = 5 + (slot & ~1).  Ot6RageCurSlot (ot6_kits.asm) computes the same
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
        ; --- the beast, or #44's empty marker ---
        ; An unset slot draws "- EMPTY -" in BLUE, the page's chrome colour, so
        ; it cannot be mistaken for a beast (every MonsterName is Mixed Case in
        ; the DEFAULT colour).  The colour has to be chosen per row rather than
        ; once for the loop, because which rows are empty changes with the
        ; loadout -- and with the collection, since AUTO's window is only as
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
        ; fallthrough -- #49, exactly as the SwdTech page's slot loop does

; ---- #49: AUTO / MANUAL, and the control that gets back to AUTO ----
; Row 13 -- the one row this page never drew on (it uses 1/3/5/7/9/11/15), which
; issue #49's survey costed at 27 free columns.  The mode sits at column 3 and
; the control at column 16: the page's OWN two slot columns, so the pair lines up
; under the grid instead of floating in the middle of the row.
;
; Drawn from the tail of the slot redraw for the same reason the SwdTech page
; draws its block there: Ot6RageDrawSlots is the only proc a redraw runs
; (MenuState_7c @run), and the mode is live -- the first L/R cycle calls
; Ot6RageSeed and the page is MANUAL from that frame on, Y clears it back.  A
; mode drawn once in Ot6RageDrawC3 would freeze at whatever it was on entry,
; which is precisely the state the page failed to report before.
Ot6RageDrawMode:
        jsl     Ot6RageIsAuto           ; F0: carry set = AUTO (all eight bytes 0)
        lda     #$00
        bcs     :+
        lda     #$01                    ; MANUAL
:       sta     $e5                     ; -> Ot6DrawModeWord's selector
        lda     #BG1_TEXT_COLOR::DEFAULT
        sta     zTextColor              ; the mode is DATA, not chrome
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
; #44: an unset slot used to be a run of $ff pads -- correct (it overwrote the
; whole name field, so a revert wiped what was there) and unreadable.  The
; owner's playtest read the blank rows as a bug rather than as "you have not
; hunted eight species yet".  It now spells "- EMPTY -", which is the honest
; word in BOTH of the states that produce a blank row: an AUTO window shorter
; than eight, and a MANUAL slot whose byte is $00.  Ot6RageList skips exactly
; these slots when it builds the battle menu, so an empty row here is an empty
; slot there.  See OT6_RAGE_EMPTY in menu_text_en.inc for the full derivation
; and for why "-default-" would have been a lie.
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
:       lda     f:Ot6RageEmptyTiles,x   ; (long,X -- there is no long,Y mode)
        beq     :+
        sta     hWMDATA
        inx
        bra     :-
:       stz     hWMDATA
        jmp     DrawPosTextBuf

Ot6RageEmptyTiles:      raw_text OT6_RAGE_EMPTY ; "- EMPTY - " + $00 (issue #39:
                        ; encoded via menu_text_en.inc -- a bare literal here
                        ; picks up ending_anim.asm's credits charmap)

; ---- draw the LEARNED count (three digits, col 11 of the caption row) ----
; #44: the colour is set HERE rather than inherited.  Ot6RageDrawSlots now
; picks DEFAULT or BLUE per row (the empty marker is chrome), so whatever the
; last slot happened to be would otherwise decide what colour the collection
; score came out in.  The count is data: DEFAULT, always.
Ot6RageDrawCount:
        lda     #BG1_TEXT_COLOR::DEFAULT
        sta     zTextColor
        jsl     Ot6RageCount            ; F0: A = rages known (0..255)
        pha
        lda     #$0f                    ; row 15 -- the LAST row the window
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
; x = {8, 112} pairs with text columns {3, 16} -- cursor_x = 8*col - 16, see the
; cursor-gutter note on Ot6RageDrawSlots.  Do not move this table to fix an
; overlap: move the TEXT.  menu_ragepage.lua's cursor canary asserts the pair.
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
Ot6RageModeHintText:    pos_text OT6_RAGE_MODE_HINT     ; #49: "Y=AUTO" at {16,13}
Ot6RageEachText:        pos_text OT6_RAGE_EACH
Ot6RageLearnedText:     pos_text OT6_RAGE_LEARNED

.endif   ; LANG_EN

; ------------------------------------------------------------------------------

; [ menu state $21: restore saved game (init) ]

MenuState_21:
@29c2:  lda     $4b
        sta     zSelSaveSlot
        jsr     DrawSaveMenuChars
        jsr     UpdateGameLoadCursor
        lda     z08
        bit     #JOY_A
        beq     @2a06
        clr_a
        lda     $4b
        beq     @2a07
        sta     zSelSaveSlot
        dec
        asl
        tax
        ldy     $91,x
        beq     @2a00
        jsr     PushSRAM
        jsr     PlaySelectSfx
        lda     zSelSaveSlot
        sta     wSelSaveSlot
        jsr     LoadSaveSlot
        jsr     InitCharProp
        jsr     _c36989
        jsr     PopTimers
        lda     #$22
        sta     zNextMenuState
        lda     #$53
        sta     zMenuState
        rts
@2a00:  jsr     PlayInvalidSfx
        jsr     CreateMosaicTask
@2a06:  rts
@2a07:  jsr     PlaySelectSfx
        jsr     ResetGameTime
        jsl     Ot6CodexNewGame         ; OT6: blank transient, never slot 1
        lda     #1
        sta     wSelSaveSlot
        stz     wSaveSlotToLoad
        stz     w0205
        lda     #$ff
        sta     zNextMenuState
        lda     #$53
        sta     zMenuState
        rts

; ------------------------------------------------------------------------------

; [ clear game time ]

ResetGameTime:
@2a21:  clr_ay
        sty     wGameTimeHours
        sty     wGameTimeSeconds
        rts

; ------------------------------------------------------------------------------

; [ menu state $23: restore saved game ]

MenuState_23:
@2a2a:  jsr     UpdateSaveConfirmCursor
        lda     z08+1
        bit     #>JOY_B
        bne     @2a58
        lda     z08
        bit     #JOY_A
        beq     @2a64
        jsr     PlaySelectSfx
        lda     $4b
        bne     @2a5b
        ldy     $1863
        sty     wGameTimeHours
        lda     $1865
        sta     wGameTimeSeconds
        lda     zSelSaveSlot
        sta     wSaveSlotToLoad
        lda     #MENU_STATE::TERMINATE
        sta     zNextMenuState
        stz     zMenuState
        rts
@2a58:  jsr     PlayCancelSfx
@2a5b:  jsr     PopSRAM
        lda     #$20
        sta     zNextMenuState
        stz     zMenuState
@2a64:  rts

; ------------------------------------------------------------------------------

; [ menu state $3a: magic target (init) ]

MenuState_3a:
@2a65:  lda     #$40
        tsb     z45
        jsr     _c32a76
        jsr     _c35812
        jsr     CreateCursorTask
        lda     #$3b
        bra     _c32aa5

_c32a76:
@2a76:  jsr     DisableInterrupts
        lda     #$01
        tsb     z45
        lda     #$04
        tsb     zEnableHDMA
        stz     zDMA2Dest
        stz     zDMA2Dest+1
        jsr     ClearBGScroll
        jsr     InitPortraits
        lda     #$03
        sta     hBG1SC
        lda     #$c0
        trb     zEnableHDMA
        ldy     #$0002
        sty     zBG1VScroll
        jsr     InitCharSelectCursor
        lda     #0
        ldy     #near CharSelectCursorTask
        jsr     CreateTask
        rts

_c32aa5:
@2aa5:  sta     zNextMenuState
        lda     #$01
        sta     zMenuState
        jmp     EnableInterrupts

; ------------------------------------------------------------------------------

; [ menu state $3b: magic target (single target) ]

MenuState_3b:
@2aae:  lda     z08
        bit     #JOY_R
        bne     @2ac6
        lda     z08
        bit     #JOY_L
        bne     @2ac6
        lda     z08+1
        bit     #>JOY_RIGHT
        bne     @2ac6
        lda     z08+1
        bit     #>JOY_LEFT
        beq     @2af3
@2ac6:  jsr     PlayMoveSfx
        jsr     GetSelMagic
        jsr     _c350f5
        longa_clc
        lda     hMPYL
        adc     #0
        tax
        clr_a
        shorta
        lda     f:MagicProp,x   ; spell data
        and     #$20
        beq     @2af3
        lda     $4e
        sta     $5f
        lda     #$06
        trb     z46
        jsr     CreateMultiCursorTask
        lda     #$3d
        sta     zMenuState
        rts
@2af3:  lda     z08
        bit     #JOY_A
        jne     @2b0c
        lda     z08+1
        bit     #>JOY_B
        beq     @2b0b
        jsr     PlayCancelSfx
        lda     #$3c
        sta     zNextMenuState
        stz     zMenuState
@2b0b:  rts
@2b0c:  stz     $9c
        jsr     _c32ccc
        jsr     GetTargetCharPtr
        jsr     _c32c14
        bcc     @2b32
        jsr     _c32cea
        jsr     PlayCureSfx
        jsr     GetTargetCharPtr
        lda     $0014,y
        sta     $f8
        lda     $0015,y
        sta     $fb
        jsr     _c32b39
        jmp     _c32bde
@2b32:  jsr     PlayInvalidSfx
        jsr     CreateMosaicTask
        rts

; ------------------------------------------------------------------------------

; [  ]

_c32b39:
_magic_exec_call_c:
@2b39:  lda     $000b,y     ; max hp
        sta     $11b2
        lda     $000c,y
        sta     $11b3
        phy
        jsr     GetSelMagic
        ldx     z0          ; 0: spell effect
        jsl     CalcMagicEffect_ext
        ply
        lda     $9c
        beq     @2b5c
        longa_clc
        lda     $11b0
        lsr
        bra     @2b61
@2b5c:  longa_clc
        lda     $11b0
@2b61:  adc     $0009,y
        sta     $0009,y
        shorta
        jsr     CheckMaxHP
        lda     $fc
        sta     $0014,y
        lda     $ff
        sta     $0015,y
        lda     $9c
        bne     @2b99
        clr_a
        lda     $4b
        tax
        lda     zCharID,x
        jsl     UpdateEquip_ext
        clr_a
        lda     $4b
        asl
        tax
        ldy     zCharPropPtr,x
        sty     zSelCharPropPtr
        lda     $11d2
        jsr     _c391ec
        lda     $11d4
        jmp     _c391fb
@2b99:  rts

; ------------------------------------------------------------------------------

; [ check current hp vs max ]

CheckMaxHP:
@2b9a:  lda     $000b,y     ; max hp
        sta     $f3
        lda     $000c,y
        sta     $f4
        jsr     CalcMaxHPMP
        jsr     ValidateMaxHP
        longa
        lda     $0009,y     ; current hp
        cmp     $f3
        bcc     @2bb9       ; return if not greater than max (return clear carry)
        lda     $f3
        sta     $0009,y     ; set current hp (return set carry)
        sec
@2bb9:  shorta
        rts

; ------------------------------------------------------------------------------

; [ check current mp vs max ]

CheckMaxMP:
@2bbc:  lda     $000f,y
        sta     $f3
        lda     $0010,y
        sta     $f4
        jsr     CalcMaxHPMP
        jsr     ValidateMaxMP
        longa
        lda     $000d,y
        cmp     $f3
        bcc     @2bdb
        lda     $f3
        sta     $000d,y
        sec
@2bdb:  shorta
        rts

; ------------------------------------------------------------------------------

; [  ]

_c32bde:
@2bde:  jsr     _c32c01
        jsr     _c32cdf
        jsr     GetCasterCharPtr
        jsr     GetSelMagic
        jsr     _c3510d
        stx     $e7
        ldx     a:$000d,y
        cpx     $e7
        bcs     @2c00
        lda     #$02
        sta     z46
        lda     #$3c
        sta     zNextMenuState
        stz     zMenuState
@2c00:  rts

; ------------------------------------------------------------------------------

; [  ]

_c32c01:
@2c01:  lda     $4b
        sta     $9c
        jsr     _c324ee
        jsr     ClearBG1ScreenA
        jsr     _c33193
        jsr     LoadPortraitPal
        jmp     GetPortraitGfxPtr

; ------------------------------------------------------------------------------

; [  ]

_c32c14:
@2c14:  lda     $0014,y
        and     #$80
        bne     @2c40
        jsr     GetSelMagic
        cmp     #$2d
        beq     @2c76
        cmp     #$2e
        beq     @2c76
        cmp     #$2f
        beq     @2c76
        cmp     #$32
        beq     @2c6d
        cmp     #$33
        beq     @2c64
        cmp     #$22
        beq     @2c4d
        cmp     #$23
        beq     @2c84
        cmp     #$2c
        beq     @2c56
        bra     @2c82
@2c40:  jsr     GetSelMagic
        cmp     #$30
        beq     @2c84
        cmp     #$31
        beq     @2c84
        bra     @2c82
@2c4d:  lda     $0015,y
        and     #$80
        bne     @2c82
        bra     @2c84
@2c56:  lda     $0014,y
        and     #$7f
        ora     $0015,y
        and     #$90
        beq     @2c82
        bra     @2c84
@2c64:  lda     $0014,y
        and     #$45
        beq     @2c82
        bra     @2c84
@2c6d:  lda     $0014,y
        and     #$04
        beq     @2c82
        bra     @2c84
@2c76:  lda     $0014,y
        and     #$c2
        bne     @2c82
        jsr     CheckMaxHP
        bcc     @2c84
@2c82:  clc
        rts
@2c84:  sec
        rts

; ------------------------------------------------------------------------------

; [  ]

_c32c86:
@2c86:  stz     $af
        lda     #$01
        sta     $9c
        jsr     _c32ccc
        clr_a
@2c90:  pha
        asl
        tax
        ldy     zCharPropPtr,x
        beq     @2cb8
        jsr     _c32c14
        bcc     @2cb8
        lda     $0014,y
        sta     $f8
        lda     $0015,y
        sta     $fb
        jsr     _c32b39
        jsr     _c32ccc
        lda     $af
        bne     @2cb8
        jsr     PlayCureSfx
        jsr     _c32cea
        inc     $af
@2cb8:  clr_a
        pla
        inc
        cmp     #$04
        bne     @2c90
        lda     $af
        bne     @2cc9
        jsr     PlayInvalidSfx
        jsr     CreateMosaicTask
@2cc9:  jmp     _c32bde

; ------------------------------------------------------------------------------

; [  ]

_c32ccc:
@2ccc:  jsr     _c32cdf
        lda     $11a0       ; mag.pwr
        sta     $11ae       ; hit rate
        jsr     GetCasterCharPtr
        lda     $0008,y
        sta     $11af       ; level
        rts

; ------------------------------------------------------------------------------

; [  ]

_c32cdf:
@2cdf:  clr_a
        lda     zSelIndex
        tax
        lda     zCharID,x
        jsl     UpdateEquip_ext
        rts

; ------------------------------------------------------------------------------

; [ subtract spell's mp cost ]

_c32cea:
@2cea:  jsr     GetSelMagic
        jsr     _c3510d
        stx     $e7
        jsr     GetCasterCharPtr
        longa
        lda     $000d,y
        sec
        sbc     $e7
        sta     $000d,y
        shorta
        rts

; ------------------------------------------------------------------------------

; [ get pointer to spell caster's character data ]

GetCasterCharPtr:
@2d03:  clr_a
        lda     zSelIndex
        asl
        tax
        ldy     zCharPropPtr,x
        rts

; ------------------------------------------------------------------------------

; [ get pointer to target character data ]

GetTargetCharPtr:
@2d0b:  clr_a
        lda     $4b         ; cursor position
        asl
        tax
        ldy     zCharPropPtr,x       ; pointer to character data
        rts

; ------------------------------------------------------------------------------

; [ get selected spell index ]

GetSelMagic:
@2d13:  clr_a
        lda     $99
        tax
        lda     $7e9d89,x
        rts

; ------------------------------------------------------------------------------

; [ menu state $3c: return to magic menu after casting a spell ]

MenuState_3c:
@2d1c:  jsr     DisableInterrupts
        jsr     DisableWindow1PosHDMA
        lda     #$42
        trb     z45
        stz     $4a
        stz     $49
        jsr     InitSkillsBGScrollHDMA
        jsr     _c34c80
        jsr     CreateCursorTask
        jsr     _c32130
        jsr     LoadMagicCursor
        lda     $8e
        sta     $4d
        ldy     $8e
        sty     $4f
        lda     $90
        sta     $4a
        lda     $4a
        sta     $e0
        lda     $50
        sec
        sbc     $e0
        sta     $4e
        jsr     InitMagicCursor
        jsr     InitMagicMenu
        jsr     _c351c6
        jsr     TfrBG3ScreenAB
        jsr     WaitVblank
        ldy     z0
        sty     zBG1HScroll
        jsr     InitBigText
        lda     #$10
        tsb     z45
        jsr     InitDMA1BG1ScreenA
        lda     #$1a
        sta     zNextMenuState
        lda     #$01
        sta     zMenuState
        jmp     EnableInterrupts

; ------------------------------------------------------------------------------

; [ menu state $3d: magic target (multi-target) ]

MenuState_3d:
@2d78:  lda     z08
        bit     #JOY_R
        bne     @2d90
        lda     z08
        bit     #JOY_L
        bne     @2d90
        lda     z08+1
        bit     #>JOY_RIGHT
        bne     @2d90
        lda     z08+1
        bit     #>JOY_LEFT
        beq     @2d9b
@2d90:  jsr     PlayMoveSfx
        jsr     _c32db7
        lda     #$3b
        sta     zMenuState
        rts
@2d9b:  lda     z08
        bit     #JOY_A
        jne     _c32c86
        lda     z08+1
        bit     #>JOY_B
        beq     @2db6
        jsr     PlayCancelSfx
        jsr     _c32db7
        lda     #$3c
        sta     zNextMenuState
        stz     zMenuState
@2db6:  rts

; ------------------------------------------------------------------------------

; [  ]

_c32db7:
@2db7:  jsr     InitCharSelectCursor
        jsr     CreateCursorTask
        lda     #0
        ldy     #near CharSelectCursorTask
        jsr     CreateTask
        jsr     ExecTasks
        lda     $5f
        sta     $4e
        lda     #$08
        trb     z46
        rts

; ------------------------------------------------------------------------------

; [  ]

_c32dd1:
@2dd1:  clr_a
        lda     zSelIndex
        tax
        lda     $4b
        tay
        lda     $75,x
        sta     $e0
        lda     zCharRowOrder,y
        sta     $75,x
        lda     $e0
        sta     zCharRowOrder,y
        lda     zCharID,x
        sta     $e0
        lda     zCharID,y
        sta     zCharID,x
        lda     $e0
        sta     zCharID,y
        clr_a
        lda     zSelIndex
        asl
        tax
        lda     $4b
        asl
        tay
        longa
        lda     zCharPropPtr,x
        sta     $e7
        lda     zCharPropPtr,y
        sta     zCharPropPtr,x
        lda     $e7
        sta     zCharPropPtr,y
        shorta
        rts

; ------------------------------------------------------------------------------

; [  ]

_c32e10:
@2e10:  clr_a
        lda     zSelIndex
        tax
        lda     $75,x
        sta     $e0
        lda     $60,x
        tax
        lda     $e0
        bit     #$20
        beq     @2e29
        lda     #$20
        trb     $e0
        lda     #$03
        bra     @2e2f
@2e29:  lda     #$20
        tsb     $e0
        lda     #$02
@2e2f:  sta     wTaskState,x
        clr_a
        lda     zSelIndex
        tax
        lda     $e0
        sta     $75,x
        rts

; ------------------------------------------------------------------------------

; [  ]

_c32e3c:
@2e3c:  clr_a
        lda     $60
        tax
        lda     #$ff
        sta     $7e35c9,x
        lda     $61
        tax
        lda     #$ff
        sta     $7e35c9,x
        lda     $62
        tax
        lda     #$ff
        sta     $7e35c9,x
        lda     $63
        tax
        lda     #$ff
        sta     $7e35c9,x
        rts

; ------------------------------------------------------------------------------

; [ main menu: a button pressed ]

SelectMainMenuOption:
@2e62:  clr_a
        lda     $4b
        sta     z25         ; set main menu cursor position
        asl
        tax
        jmp     (near SelectMainMenuOptionTbl,x)

; ------------------------------------------------------------------------------

; main menu jump table
SelectMainMenuOptionTbl:
@2e6c:  .addr   SelectMainMenuOption_00
        .addr   SelectMainMenuOption_01
        .addr   SelectMainMenuOption_02
        .addr   SelectMainMenuOption_03
        .addr   SelectMainMenuOption_04
        .addr   SelectMainMenuOption_05
        .addr   SelectMainMenuOption_06

; ------------------------------------------------------------------------------

; config
SelectMainMenuOption_05:
@2e7a:  jsr     PlaySelectSfx
        stz     $5f
        stz     zMenuState                     ; fade out
        lda     #$0d
        sta     zNextMenuState                     ; config (init)
        rts

; ------------------------------------------------------------------------------

; item
SelectMainMenuOption_00:
@2e86:  jsr     PlaySelectSfx
        stz     zMenuState                     ; fade out
        lda     #$07
        sta     zNextMenuState                     ; item (init)
        rts

; ------------------------------------------------------------------------------

; skills, equip, relic, status
SelectMainMenuOption_01:
SelectMainMenuOption_02:
SelectMainMenuOption_03:
SelectMainMenuOption_04:
@2e90:  jsr     PlaySelectSfx
        lda     #$02
        trb     z46                     ; disable cursor 1
        jsr     InitCharSelectCursor
        lda     #0
        ldy     #near CharSelectCursorTask
        jsr     CreateTask
        jsr     _c32f06
        lda     #$06
        sta     zMenuState                     ; character select menu state
        rts

; ------------------------------------------------------------------------------

; save
SelectMainMenuOption_06:
@2eaa:  lda     w0201                   ; branch if save is not enabled
        bpl     @2ebf
        jsr     PlaySelectSfx
        stz     zMenuState                     ; fade out
        lda     #$13
        sta     zNextMenuState                     ; save select (init) menu state
        sta     $9e                     ;
        lda     #$04
        sta     $9f                     ;
        rts
@2ebf:  jsr     PlayInvalidSfx
        jsr     CreateMosaicTask
        rts

; ------------------------------------------------------------------------------

; [ main menu: left button pressed ]

MainMenuLeftBtn:
@2ec6:  lda     #$02                    ; disable cursor 1
        trb     z46
        jsr     InitCharSelectCursor
        lda     #0
        ldy     #near CharSelectCursorTask
        jsr     CreateTask
        lda     #$06
        sta     zWaitCounter                     ; wait 6 frames
        ldy     #.loword(-12)
        sty     zMenuScrollRate
        lda     #$05                    ; disable cursor 2 and flashing cursor
        trb     z46
        lda     #$0f                    ; order (char select)
        sta     zNextMenuState
        lda     #$65                    ; scroll menu
        sta     zMenuState
        rts

; ------------------------------------------------------------------------------

; [  ]

_c32eeb:
@2eeb:  lda     #2
        ldy     #near MultiCursorTask
        jsr     CreateTask
        longa
        lda     #$0038
        sta     wTaskPosX,x
        lda     #$0036
        sta     wTaskPosY,x
        shorta
        rts

; ------------------------------------------------------------------------------

; [ create flashing cursor (2 pixels to the right) ]

_c32f06:
@2f06:  lda     #2
        ldy     #near FlashingCursorTask
        jsr     CreateTask
        longa
        lda     $55                     ; cursor x position
        inc2
        sta     wTaskPosX,x               ; set task x position
        lda     $57                     ; cursor y position
        sta     wTaskPosY,x               ; set task y position
        shorta
        rts

; ------------------------------------------------------------------------------

; [ create flashing cursor (4 pixels right/up) ]

_c32f21:
@2f21:  lda     #1
        ldy     #near FlashingCursorTask
        jsr     CreateTask
        longa
        lda     $55
        clc
        adc     #4
        sta     wTaskPosX,x
        lda     $57
        sec
        sbc     #4
        sta     wTaskPosY,x
        shorta
        rts

; ------------------------------------------------------------------------------

; [ main menu cursor task ]

MainMenuCursorTask:
@2f42:  tax
        jmp     (near MainMenuCursorTaskTbl,x)

; ------------------------------------------------------------------------------

; main menu cursor task jump table
MainMenuCursorTaskTbl:
@2f46:  .addr   MainMenuCursorTask_00
        .addr   MainMenuCursorTask_01

; ------------------------------------------------------------------------------

; state 0: init
MainMenuCursorTask_00:
@2f4a:  ldx     zTaskOffset
        lda     #$02
        tsb     z46                     ; enable cursor 1
        inc     near wTaskState,x                 ; increment task counter
        ldy     #near MainMenuCursorProp
        jsr     LoadCursor
        lda     $1d4e                   ; branch if cursor is on memory
        and     #$40
        beq     @2f65
        ldy     w022b                   ; load saved cursor position
        sty     $4d
@2f65:  ldy     #near MainMenuCursorPos
        jsr     UpdateCursorPos
; fallthrough

; ------------------------------------------------------------------------------

; state 1: update
MainMenuCursorTask_01:
@2f6b:  lda     z46
        bit     #$02
        beq     @2f83                   ; terminate if cursor 1 is not active
        ldx     zTaskOffset
        jsr     MoveCursor
        ldy     #near MainMenuCursorPos
        jsr     UpdateCursorPos
        ldy     $4d
        sty     w022b                   ; save cursor position
        sec
        rts
@2f83:  clc
        rts

; ------------------------------------------------------------------------------

; main menu cursor data
MainMenuCursorProp:
        cursor_prop {0, 0}, {1, 7}, NO_X_WRAP

; ------------------------------------------------------------------------------

; main menu cursor positions
MainMenuCursorPos:
.if LANG_EN
        @X_OFFSET = 175
.else
        @X_OFFSET = 183
.endif

        cursor_pos {@X_OFFSET, 18}
        cursor_pos {@X_OFFSET, 33}
        cursor_pos {@X_OFFSET, 48}
        cursor_pos {@X_OFFSET, 63}
        cursor_pos {@X_OFFSET, 78}
        cursor_pos {@X_OFFSET, 93}
        cursor_pos {@X_OFFSET, 108}

; ------------------------------------------------------------------------------

; [ init character select cursor ]

InitCharSelectCursor:
@2f98:  jsr     LoadCharSelectCursorProp
        clr_axy
@2f9e:  lda     a:zCharID,x
        bpl     @2faa                   ; branch if slot is not empty
        phx
        txa
        asl
        tax
        stz     $85,x                   ; disable cursor position
        plx
@2faa:  inx
        cpx     #4
        bne     @2f9e
        rts

; ------------------------------------------------------------------------------

; [ load character select cursor data ]

LoadCharSelectCursorProp:
@2fb1:  ldx     z0
@2fb3:  lda     f:CharSelectCursorProp,x
        sta     $80,x
        inx
        cpx     #13
        bne     @2fb3
        rts

; ------------------------------------------------------------------------------

; [ character select cursor task ]

CharSelectCursorTask:
@2fc0:  tax
        jmp     (near CharSelectCursorTaskTbl,x)

CharSelectCursorTaskTbl:
        make_jump_tbl CharSelectCursorTask, 2

; ------------------------------------------------------------------------------

; [  ]

make_jump_label CharSelectCursorTask, 0
@2fc8:  ldx     zTaskOffset
        lda     #$14
        tsb     z46
        inc     near wTaskState,x
        jsr     _c32ff5
        lda     z45
        bit     #$40
        bne     @2fe6
        lda     $1d4e
        and     #$40
        beq     @2fe6
        ldy     w022d
        sty     $4d
@2fe6:  jsr     _c33008
        lda     $55
        bne     @2ff3
        jsr     _c32ff5
        jsr     _c33008
@2ff3:  sec
        rts

; ------------------------------------------------------------------------------

; [  ]

_c32ff5:
@2ff5:  ldy     #$0080
        jsr     LoadCursor
        ldy     #$0080
        lda     #$00
        sta     $ed
        jsr     LoadCursorFar
        jmp     SelectFirstChar

; ------------------------------------------------------------------------------

; [  ]

_c33008:
@3008:  ldy     #$0085
        sty     $e7
        lda     #$00
        sta     $e9
        jmp     UpdateCursorPosFar

; ------------------------------------------------------------------------------

; [  ]

make_jump_label CharSelectCursorTask, 1
@3014:  lda     z45
        bit     #$40
        bne     @301f
        ldy     $4d
        sty     w022d
@301f:  lda     z46
        bit     #$04
        beq     @3040
        bit     #$10
        beq     @303e
        ldx     zTaskOffset
@302b:  jsr     MoveCursor
        ldy     #$0085      ; cursor data pointer = $000085
        sty     $e7
        lda     #$00
        sta     $e9
        jsr     UpdateCursorPosFar
        lda     $55
        beq     @302b
@303e:  sec
        rts
@3040:  clc
        rts

; ------------------------------------------------------------------------------

; character select cursor data
CharSelectCursorProp:
        cursor_prop {0, 0}, {1, 4}, NO_X_WRAP

; ------------------------------------------------------------------------------

; character select cursor positions
CharSelectCursorPos:
@3047:  cursor_pos {8, 40}
        cursor_pos {8, 88}
        cursor_pos {8, 136}
        cursor_pos {8, 184}

; ------------------------------------------------------------------------------

; [ create fade out task ]

CreateFadeOutTask:
@304f:  clr_a                           ; priority 0
        ldy     #near FadeOutTask
        jmp     CreateTask

; ------------------------------------------------------------------------------

; [ create fade in task ]

CreateFadeInTask:
@3056:  clr_a                           ; priority 0
        ldy     #near FadeInTask
        jmp     CreateTask

; ------------------------------------------------------------------------------

; [ create mosaic task ]

CreateMosaicTask:
@305d:  clr_a                           ; priority 0
        ldy     #near MosaicTask
        jmp     CreateTask

; ------------------------------------------------------------------------------

; [ mosaic task ]

.proc MosaicTask
        tax
        jmp     (near MosaicTaskTbl,x)

MosaicTaskTbl:
        make_jump_tbl MosaicTask, 2

; 0: init mosaic
make_jump_label MosaicTask, 0
        ldx     zTaskOffset
        inc     near wTaskState,x
        stz     near wTaskPosX,x
        lda     #8
        sta     near w7e3349,x

; 1: update mosaic
make_jump_label MosaicTask, 1
        ldx     zTaskOffset
        lda     near w7e3349,x
        beq     terminate
        clr_a
        lda     near wTaskPosX,x
        tax
        lda     f:MosaicTbl,x
        sta     zMosaic
        ldx     zTaskOffset
        inc     near wTaskPosX,x
        dec     near w7e3349,x
        sec
        rts

terminate:
        clc
        rts

; mosaic data
MosaicTbl:
        .byte   $17,$27,$37,$47,$37,$27,$17,$07

.endproc  ; MosaicTask

; ------------------------------------------------------------------------------

; [ fade out task ]

.proc FadeOutTask
        tax
        jmp     (near FadeOutTaskTbl,x)

FadeOutTaskTbl:
        make_jump_tbl FadeOutTask, 2

; 0: init fade out
make_jump_label FadeOutTask, 0
        ldx     zTaskOffset
        inc     near wTaskState,x
        lda     #$0f
        sta     near wTaskPosX,x

; 1: update fade out
make_jump_label FadeOutTask, 1
        ldy     zWaitCounter
        beq     terminate
        ldx     zTaskOffset
        lda     near wTaskPosX,x
        sta     zScreenBrightness
        dec     near wTaskPosX,x
        dec     near wTaskPosX,x
        sec
        rts

terminate:
        lda     #$01
        sta     zScreenBrightness
        clc
        rts
.endproc  ; FadeOutTask

; ------------------------------------------------------------------------------

; [ fade in task ]

.proc FadeInTask
        tax
        jmp     (near FadeInTaskTbl,x)

FadeInTaskTbl:
        make_jump_tbl FadeInTask, 2

; 0: init fade in
make_jump_label FadeInTask, 0
        ldx     zTaskOffset
        inc     near wTaskState,x
        lda     #1
        sta     near wTaskPosY,x

; 1: update fade in
make_jump_label FadeInTask, 1
        ldy     zWaitCounter
        beq     terminate
        ldx     zTaskOffset
        lda     near wTaskPosY,x
        sta     zScreenBrightness
        inc     near wTaskPosY,x
        inc     near wTaskPosY,x
        sec
        rts

terminate:
        lda     #$0f
        sta     zScreenBrightness
        clc
        rts
.endproc  ; FadeInTask

; ------------------------------------------------------------------------------

; [ init bg (main menu) ]

DrawMainMenu:
@30f5:  jsr     InitFontColor
        jsr     ClearBG2ScreenA
        jsr     ClearBG2ScreenB
        jsr     ClearBG1ScreenB
        jsr     ClearBG3ScreenB
        ldy     #near MainMenuOrderWindow1
        jsr     DrawWindow
        ldy     #near MainMenuOrderWindow2
        jsr     DrawWindow
        ldy     #near MainMenuCharWindow
        jsr     DrawWindow
        ldy     #near MainMenuOptionsWindow
        jsr     DrawWindow
        jsr     _c33170
        jsr     DrawTime
        jsr     DrawMainMenuListText
        jmp     _c3319f

; ------------------------------------------------------------------------------

; [ draw menu for confirming a save slot to save ]

DrawGameSaveConfirmMenu:
@3128:  jsr     InitFontColor
        jsr     LoadPortraitGfx
        jsr     LoadPortraitPal
        jsr     _c331a8
        ldy     #near MainMenuCharWindow
        jsr     DrawWindow
        ldy     #near SaveChoiceWindow
        jsr     DrawWindow
        jsr     _c33170
        jsr     _c33295
        jsr     DrawGameSaveChoiceText
        jmp     _c3319f

; ------------------------------------------------------------------------------

; [ draw menu for confirming a save slot to load ]

DrawGameLoadConfirmMenu:
@314c:  jsr     InitFontColor
        jsr     LoadPortraitGfx
        jsr     LoadPortraitPal
        jsr     _c331a8
        ldy     #near MainMenuCharWindow
        jsr     DrawWindow
        ldy     #near SaveChoiceWindow
        jsr     DrawWindow
        jsr     _c33170
        jsr     _c33295
        jsr     DrawGameLoadChoiceText
        jmp     _c3319f

; ------------------------------------------------------------------------------

; [  ]

_c33170:
@3170:  clr_a
        jsl     InitGradientHDMA
        ldy     #near MainMenuTimeWindow
        jsr     DrawWindow
        ldy     #near MainMenuStepsWindow
        jsr     DrawWindow
        jsr     TfrBG2ScreenAB
        jsr     _c3318a
        jmp     DrawGilStepsText

; ------------------------------------------------------------------------------

; [  ]

_c3318a:
@318a:  jsr     ClearBG1ScreenA
        jsr     ClearBG3ScreenA
        jsr     ClearBG3ScreenC

_c33193:
@3193:  jsr     DrawCharBlock1
        jsr     DrawCharBlock2
        jsr     DrawCharBlock3
        jmp     DrawCharBlock4

; ------------------------------------------------------------------------------

; [  ]

_c3319f:
@319f:  jsr     TfrBG1ScreenAB
        jsr     TfrBG3ScreenAB
        jmp     TfrBG3ScreenCD

; ------------------------------------------------------------------------------

; [  ]

_c331a8:
@31a8:  lda     zSelSaveSlot
        cmp     #1
        beq     @31b5
        cmp     #2
        beq     @31b8
        jmp     LoadSaveSlot3WindowGfx
@31b5:  jmp     LoadSaveSlot1WindowGfx
@31b8:  jmp     LoadSaveSlot2WindowGfx

; ------------------------------------------------------------------------------

; main menu window data

.if LANG_EN
MainMenuOptionsWindow:                  make_window BG2A, {23, 1}, {6, 13}
MainMenuTimeWindow:                     make_window BG2A, {23, 16}, {6, 2}
.else
MainMenuOptionsWindow:                  make_window BG2A, {24, 1}, {5, 13}
MainMenuTimeWindow:                     make_window BG2A, {24, 16}, {5, 2}
.endif
MainMenuStepsWindow:                    make_window BG2A, {22, 20}, {7, 5}
MainMenuCharWindow:                     make_window BG2A, {1, 1}, {28, 24}
SaveChoiceWindow:                       make_window BG2A, {22, 1}, {7, 10}
MainMenuOrderWindow1:                   make_window BG2B, {24, 1}, {7, 2}
MainMenuOrderWindow2:                   make_window BG2A, {30, 0}, {1, 2}

; ------------------------------------------------------------------------------

; [ draw "yes/no/erasing data, okay?" text ]

DrawGameSaveChoiceText:
@31d7:  lda     #BG1_TEXT_COLOR::DEFAULT
        sta     zTextColor
        ldx     #near GameSaveChoiceTextList
        ldy     #sizeof_GameSaveChoiceTextList
        jsr     DrawPosKanaList
        rts

; ------------------------------------------------------------------------------

; [ draw "yes/no/this data?" text ]

DrawGameLoadChoiceText:
@31e5:  lda     #BG1_TEXT_COLOR::DEFAULT
        sta     zTextColor
        ldx     #near GameLoadChoiceTextList
        ldy     #sizeof_GameLoadChoiceTextList
        jsr     DrawPosKanaList
        rts

; ------------------------------------------------------------------------------

; [ draw "item/skills/equip/relic/status/config/save" text ]

DrawMainMenuListText:
@31f3:  lda     #BG3_TEXT_COLOR::DEFAULT
        sta     zTextColor
        ldx     #near MainMenuOptionsTextList1
        ldy     #sizeof_MainMenuOptionsTextList1
        jsr     DrawPosList
        lda     #BG1_TEXT_COLOR::DEFAULT
        sta     zTextColor
        ldx     #near MainMenuOptionsTextList2
        ldy     #sizeof_MainMenuOptionsTextList2
        jsr     DrawPosKanaList
        lda     w0201
        bpl     @3216       ; branch if save is disabled
        lda     #BG3_TEXT_COLOR::DEFAULT
        bra     @3218
@3216:  lda     #BG3_TEXT_COLOR::GRAY
@3218:  sta     zTextColor
        ldy     #near MainMenuSaveText
        jsr     DrawPosKana
        rts

; ------------------------------------------------------------------------------

; [ draw gp and steps ]

DrawGilStepsText:
@3221:  lda     #BG3_TEXT_COLOR::DEFAULT
        sta     zTextColor
        ldy     #near MainMenuColonText
        jsr     DrawPosText
        lda     #BG3_TEXT_COLOR::TEAL
        sta     zTextColor
        ldx     #near MainMenuLabelTextList
        ldy     #sizeof_MainMenuLabelTextList
        jsr     DrawPosList
        ldy     #near MainMenuGilText
        jsr     DrawPosKana
        jsr     ValidateMaxGil
        lda     #BG3_TEXT_COLOR::DEFAULT
        sta     zTextColor
        ldy     $1866                   ; gp
        sty     zf1
        lda     $1868
        sta     zf3
        jsr     HexToDec8
        ldx_pos BG3A, {23, 22}
        jsr     DrawNum7
        ldy     $1860                   ; steps
        sty     zf1
        lda     $1862
        sta     zf3
        jsr     HexToDec8
        ldx_pos BG3A, {23, 25}
        jsr     DrawNum7
        rts

; ------------------------------------------------------------------------------

; [ draw game time or timer ]

DrawTime:
@326c:  lda     $1188                   ; branch if timer 0 is not active
        bit     #$10
        beq     @3289
        ldy     $1189
        jsr     Div60
        jsr     Div60
        lda     $e7
        sta     $1863
        lda     hRDMPYL
        sta     $1864
        bra     _c33295
@3289:  ldy     wGameTimeHours
        sty     $1863
        lda     wGameTimeSeconds
        sta     $1865

_c33295:
@3295:  lda     #BG3_TEXT_COLOR::DEFAULT
        sta     zTextColor
        lda     $1863
        jsr     HexToDec3
        ldx_pos BG3A, {25, 18}
        jsr     DrawNum2
        lda     $1864
        jsr     HexToDecZeroes3
        ldx_pos BG3A, {28, 18}
        jsr     DrawNum2
        rts

; ------------------------------------------------------------------------------

; [ divide by 60 ]

; convert frames to seconds, seconds to minutes, or minutes to hours

Div60:
@32b2:  sty     hWRDIVL
        lda     #60
        sta     hWRDIVB
        nop8
        nop6
        ldy     hRDDIVL
        sty     $e7
        rts

; ------------------------------------------------------------------------------

; [ check max gil ]

ValidateMaxGil:
@32ce:  lda     #<MAX_GIL        ; 9999999 max
        cmp     $1860
        lda     #>MAX_GIL
        sbc     $1861
        lda     #^MAX_GIL
        sbc     $1862
        bcs     @32ea
        ldy     #.loword(MAX_GIL)
        sty     $1860
        lda     #^MAX_GIL
        sta     $1862
@32ea:  rts

; ------------------------------------------------------------------------------

; [ draw hp/mp/lv number text (slot 1) ]

_32eb:  jsr     CreatePortraitTask1
        jmp     HidePortrait

DrawCharBlock1:
@32f1:  lda     zCharID::Slot1
        bmi     _32eb
        ldx     zCharPropPtr
        stx     zSelCharPropPtr
        lda     #BG1_TEXT_COLOR::TEAL
        sta     zTextColor
        ldx     #near CharBlock1LabelTextList
        ldy     #sizeof_CharBlock1LabelTextList
        jsr     DrawPosList
.if LANG_EN
        ldy_pos BG1A, {15, 3}
.else
        ldy_pos BG1A, {15, 2}
.endif
        ldx     #$1578
        stz     z48
        jsr     DrawStatusIcons
        ldx     #near CharBlock1SlashTextList
        stx     zf1
        ldy     #sizeof_CharBlock1SlashTextList
        sty     zef
        jsr     DrawPosList
.if LANG_EN
        ldy_pos BG1A, {8, 3}
.else
        ldy_pos BG1A, {8, 2}
.endif
        jsr     DrawCharName
        ldx     #near _c3332d
        jsr     DrawCharBlock
        jmp     CreatePortraitTask1

; ------------------------------------------------------------------------------

; ram addresses for lv/hp/mp text (slot 1)
; c3/332d: bg1_0(15, 5) lv
;          bg1_0(13, 6) current hp
;          bg1_0(18, 6) max hp
;          bg1_0(13, 7) current mp
;          bg1_0(18, 7) max mp
_c3332d:
        make_pos BG1A, {15, 5}
        make_pos BG1A, {13, 6}
        make_pos BG1A, {18, 6}
        make_pos BG1A, {13, 7}
        make_pos BG1A, {18, 7}

; ------------------------------------------------------------------------------

; [ draw hp/mp/lv number text (slot 2) ]

_3337:  jsr     CreatePortraitTask2
        jmp     HidePortrait

DrawCharBlock2:
@333d:  lda     zCharID::Slot2
        bmi     _3337
        ldx     $6f
        stx     zSelCharPropPtr
        lda     #BG1_TEXT_COLOR::TEAL
        sta     zTextColor
        ldx     #near CharBlock2LabelTextList
        ldy     #sizeof_CharBlock2LabelTextList
        jsr     DrawPosList
.if LANG_EN
        ldy_pos BG1A, {15, 9}
.else
        ldy_pos BG1A, {15, 8}
.endif
        ldx     #$4578
        stz     z48
        jsr     DrawStatusIcons
        ldx     #near CharBlock2SlashTextList
        stx     zf1
        ldy     #sizeof_CharBlock2SlashTextList
        sty     zef
        jsr     DrawPosList
.if LANG_EN
        ldy_pos BG1A, {8, 9}
.else
        ldy_pos BG1A, {8, 8}
.endif
        jsr     DrawCharName
        ldx     #near _c33379
        jsr     DrawCharBlock
        jmp     CreatePortraitTask2

; ------------------------------------------------------------------------------

; ram addresses for lv/hp/mp text (slot 2)
_c33379:
        make_pos BG1A, {15, 11}
        make_pos BG1A, {13, 12}
        make_pos BG1A, {18, 12}
        make_pos BG1A, {13, 13}
        make_pos BG1A, {18, 13}

; ------------------------------------------------------------------------------

; [ draw hp/mp/lv number text (slot 3) ]

_3383:  jsr     CreatePortraitTask3
        jmp     HidePortrait

DrawCharBlock3:
@3389:  lda     zCharID::Slot3
        bmi     _3383
        ldx     $71
        stx     zSelCharPropPtr
        lda     #BG1_TEXT_COLOR::TEAL
        sta     zTextColor
        ldx     #near CharBlock3LabelTextList
        ldy     #sizeof_CharBlock3LabelTextList
        jsr     DrawPosList
.if LANG_EN
        ldy_pos BG1A, {15, 15}
.else
        ldy_pos BG1A, {15, 14}
.endif
        ldx     #$7578
        stz     z48
        jsr     DrawStatusIcons
        ldx     #near CharBlock3SlashTextList
        stx     zf1
        ldy     #sizeof_CharBlock3SlashTextList
        sty     zef
        jsr     DrawPosList
.if LANG_EN
        ldy_pos BG1A, {8, 15}
.else
        ldy_pos BG1A, {8, 14}
.endif
        jsr     DrawCharName
        ldx     #near _c333c5
        jsr     DrawCharBlock
        jmp     CreatePortraitTask3

; ------------------------------------------------------------------------------

; ram addresses for lv/hp/mp text (slot 3)
_c333c5:
        make_pos BG1A, {15, 17}
        make_pos BG1A, {13, 18}
        make_pos BG1A, {18, 18}
        make_pos BG1A, {13, 19}
        make_pos BG1A, {18, 19}

; ------------------------------------------------------------------------------

; [ draw hp/mp/lv number text (slot 4) ]

_33cf:  jsr     CreatePortraitTask4
        jmp     HidePortrait

DrawCharBlock4:
@33d5:  lda     zCharID::Slot4
        bmi     _33cf       ; branch if slot is empty
        ldx     $73
        stx     zSelCharPropPtr
        lda     #BG1_TEXT_COLOR::TEAL
        sta     zTextColor
        ldx     #near CharBlock4LabelTextList
        ldy     #sizeof_CharBlock4LabelTextList
        jsr     DrawPosList
.if LANG_EN
        ldy_pos BG1A, {15, 21}
.else
        ldy_pos BG1A, {15, 20}
.endif
        ldx     #$a578
        stz     z48
        jsr     DrawStatusIcons
        ldx     #near CharBlock4SlashTextList
        stx     zf1
        ldy     #sizeof_CharBlock4SlashTextList
        sty     zef
        jsr     DrawPosList
.if LANG_EN
        ldy_pos BG1A, {8, 21}
.else
        ldy_pos BG1A, {8, 20}
.endif
        jsr     DrawCharName
        ldx     #near _c33411
        jsr     DrawCharBlock
        jmp     CreatePortraitTask4

; ------------------------------------------------------------------------------

; ram addresses for lv/hp/mp text (character slot 4)
_c33411:
        make_pos BG1A, {15, 23}
        make_pos BG1A, {13, 24}
        make_pos BG1A, {18, 24}
        make_pos BG1A, {13, 25}
        make_pos BG1A, {18, 25}

; ------------------------------------------------------------------------------

; [ hide portrait ]

HidePortrait:
@341b:  longa
        lda     #$00d8      ; set y position to 216 (off-screen)
        sta     wTaskPosY,x
        shorta
        rts

; ------------------------------------------------------------------------------

; [ draw status icons ]

; also sets text color for hp/mp/level
; +X: xy position
; +Y: pointer to bg tilemap

DrawStatusIcons:
@3427:  stx     ze7
        jsr     InitTextBuf
        lda     $0014,y                 ; status 1
        bmi     @34b0                   ; branch if character has wound status
        and     #$70                    ; isolate clear, imp, and petrify status
        sta     ze1
        lda     $0014,y
        and     #$07                    ; isolate dark, zombie, and poison status
        asl
        sta     ze2
        lda     $0015,y                 ; status 4
        and     #$80                    ; isolate float status
        ora     ze1
        ora     ze2
        sta     ze1                     ; feicpzd-
        beq     @34a9                   ; branch if character has no status icons
        stz     zf1                     ; clear icon index
        stz     zf2
        ldx     #7                      ; loop through each status
@3451:  phx
        asl
        bcc     @349c                   ; continue if character doesn't have this status
        pha
        lda     #3
        ldy     #near CharIconTask
        jsr     CreateTask
        lda     #$01
        sta     wTaskFlags,x               ; task doesn't scroll with bg
        lda     z48
        sta     wTaskState,x               ; task state
        txy
        ldx     zf1                     ; icon index
        phb
        lda     #$7e
        pha
        plb
        longa
        lda     f:StatusIconAnimPtrs,x
        sta     near wTaskAnimPtr,y
        shorta
        lda     ze7
        sta     near wTaskPosX,y                 ; x position
        lda     ze8
        sta     near wTaskPosY,y                 ; y position
        clr_a
        sta     near {wTaskPosX + 1},y                 ; clear high bytes
        sta     near {wTaskPosY + 1},y
        lda     #^StatusIconAnimPtrs
        sta     near wTaskAnimBank,y
        plb
        clc
        lda     #$0a
        adc     ze7                     ; increment positioned text pointer ???
        sta     ze7
        pla
@349c:  inc     zf1                     ; increment icon index
        inc     zf1
        plx
        dex                             ; next status
        bne     @3451
        lda     #BG1_TEXT_COLOR::DEFAULT
        sta     zTextColor
        rts

; character has no status icons
@34a9:  lda     #BG1_TEXT_COLOR::DEFAULT
        sta     zTextColor                     ; white text
        jmp     _c33583

; character has wound status
@34b0:  ldx     #$9e8b
        stx     hWMADDL
        ldx     z0
@34b8:  lda     f:MainMenuWoundedText,X ; text: "wounded"
        sta     hWMDATA
        inx
        cpx     #sizeof_MainMenuWoundedText
        bne     @34b8
        stz     hWMDATA
        lda     #BG1_TEXT_COLOR::GRAY
        sta     zTextColor
        jmp     DrawPosTextBuf

; ------------------------------------------------------------------------------

; [ draw character name ]

DrawCharName:
@34cf:  jsr     InitTextBuf

_c334d2:
@34d2:  ldx     #6
@34d5:  lda     $0002,y               ; character name
        sta     hWMDATA
        iny
        dex
        bne     @34d5
        stz     hWMDATA
        jmp     DrawPosTextBuf

; ------------------------------------------------------------------------------

; [ draw character title ]

DrawCharTitle:
.if LANG_EN
_c33583:
@34e5:  rts
.else
@3580:  jsr     InitTextBuf

_c33583:
        lda     $0000,y
        sta     hWRMPYA
        lda     #CharTitle::ITEM_SIZE
        sta     hWRMPYB
        nop4
        ldx     hRDMPYL
        ldy     #CharTitle::ITEM_SIZE
@3598:  lda     f:CharTitle,x
        sta     hWMDATA
        inx
        dey
        bne     @3598
        lda     #$ff
        sta     hWMDATA
        stz     hWMDATA
        jmp     DrawPosTextBuf
.endif

; ------------------------------------------------------------------------------

; [ draw equipped esper name ]

DrawEquipGenju:
@34e6:  jsr     InitTextBuf
        lda     $001e,y               ; equipped esper
        cmp     #$ff
        beq     @3508                   ; branch if no esper is equipped
        asl3
        tax
        ldy     #8
@34f7:  lda     f:GenjuName,x
        sta     hWMDATA
        inx
        dey
        bne     @34f7
        stz     hWMDATA
        jmp     DrawPosTextBuf
@3508:  ldy     #8
        lda     #$ff
@350d:  sta     hWMDATA                 ; clear equipped esper name
        dey
        bne     @350d
        stz     hWMDATA
        jmp     DrawPosTextBuf

; ------------------------------------------------------------------------------

; [ init positioned text buffer ]

; +Y: text position

InitTextBuf:
@3519:  ldx     #$9e89                  ; set pointer to text buffer
        stx     hWMADDL
        longa
        tya
        shorta
        sta     hWMDATA
        xba
        sta     hWMDATA
        clr_a
        ldy     zSelCharPropPtr
        rts

; ------------------------------------------------------------------------------

; [ disable interrupts ]

DisableInterrupts:
@352f:  lda     #$80        ; screen off
        sta     hINIDISP
        jsr     ResetTasks
        stz     hNMITIMEN
        stz     hMDMAEN
        stz     hHDMAEN
        rts

; ------------------------------------------------------------------------------

; [ enable interrupts ]

EnableInterrupts:
@3541:  lda     #$01        ; screen register (screen on, brightness 1)
        sta     zScreenBrightness
        jmp     WaitVblank

; ------------------------------------------------------------------------------

; [ draw time text ]

UpdateTimeText:
@3548:  jsr     InitDMA1BG3ScreenA
        jmp     DrawTime

; ------------------------------------------------------------------------------

; [ init main screen designation hdma (main menu) ]

_c3354e:
@354e:  ldx     z0
        lda     #$17        ; main screen designation (-> $212c)
@3552:  sta     $7e9a09,x
        inx
        cpx     #$00df
        bne     @3552
        lda     #$40        ; hdma channel #6 - indirect addressing
        sta     hDMA6::CTRL
        lda     #<hTM
        sta     hDMA6::HREG
        ldy     #near _c3357b
        sty     hDMA6::ADDR
        lda     #^_c3357b
        sta     hDMA6::ADDR_B
        lda     #$7e
        sta     hDMA6::HDMA_B
        lda     #BIT_6
        tsb     zEnableHDMA
        rts

; ------------------------------------------------------------------------------

; main screen designation hdma table (main menu)
_c3357b:
        hdma_addr 112 | BIT_7, $9a09
        hdma_addr 112 | BIT_7, $9a79
        hdma_end

; ------------------------------------------------------------------------------

; [ init character swap tasks ]

CreateCharSwapTask:
@3582:  lda     zSelIndex
        cmp     $4b
        bcc     @359d
        lda     #3
        ldy     #near CharSwapTopTask
        jsr     CreateTask
        jsr     @35c1
        lda     #3
        ldy     #near CharSwapBtmTask
        jsr     CreateTask
        bra     @35b2
@359d:  lda     #3
        ldy     #near CharSwapTopTask
        jsr     CreateTask
        jsr     @35b2
        lda     #3
        ldy     #near CharSwapBtmTask
        jsr     CreateTask
        bra     @35c1

@35b2:  txy
        clr_a
        lda     zSelIndex
        tax
        lda     f:_c335d0,x
        tyx
        sta     wTaskPosX,x
        rts

@35c1:  txy
        clr_a
        lda     $4b
        tax
        lda     f:_c335d0,x
        tyx
        sta     wTaskPosX,x   ; x position
        rts

; ------------------------------------------------------------------------------

_c335d0:
@35d0:  .byte   $0d,$3d,$6d,$9d

; ------------------------------------------------------------------------------

; [ character swap task (top character) ]

CharSwapTopTask:
@35d4:  tax
        jmp     (near CharSwapTopTaskTbl,x)

CharSwapTopTaskTbl:
@35d8:  .addr   CharSwapTopTask_00
        .addr   CharSwapTopTask_01
        .addr   CharSwapTopTask_02

; ------------------------------------------------------------------------------

; [ state 0: init ]

CharSwapTopTask_00:
@35de:  ldx     zTaskOffset
        inc     near wTaskState,x
; fallthrough

; ------------------------------------------------------------------------------

; [ state 1: hide character in old slot ]

CharSwapTopTask_01:
@35e3:  ldy     zTaskOffset
        lda     z22
        cmp     #12
        beq     @35fa
        clr_a
        lda     near wTaskPosX,y     ; x position
        tax
        lda     #$06
        jsr     UpdateCharSwapHDMA1
        sta     near wTaskPosX,y
        sec
        rts
@35fa:  ldx     zTaskOffset
        inc     near wTaskState,x
        dec     near wTaskPosX,x
; fallthrough

; ------------------------------------------------------------------------------

; [ state 2: show character in new slot ]

CharSwapTopTask_02:
@3602:  lda     z45
        bit     #$08
        beq     @361b
        ldy     zTaskOffset
        lda     z22
        beq     @361d
        clr_a
        lda     near wTaskPosX,y     ; x position
        tax
        lda     #$17
        jsr     UpdateCharSwapHDMA2
        sta     near wTaskPosX,y
@361b:  sec
        rts
@361d:  clc
        rts

; ------------------------------------------------------------------------------

; [ character swap task (bottom character) ]

CharSwapBtmTask:
@361f:  tax
        jmp     (near CharSwapBtmTaskTbl,x)

CharSwapBtmTaskTbl:
@3623:  .addr   CharSwapBtmTask_00
        .addr   CharSwapBtmTask_01
        .addr   CharSwapBtmTask_02

; ------------------------------------------------------------------------------

; [ init ]

CharSwapBtmTask_00:
@3629:  ldx     zTaskOffset
        inc     near wTaskState,x
        lda     near wTaskPosX,x
        clc
        adc     #$2f
        sta     near wTaskPosX,x
; fallthrough

; ------------------------------------------------------------------------------

; [ hide character in old slot ]

CharSwapBtmTask_01:
@3637:  ldy     zTaskOffset
        lda     z22
        cmp     #12
        beq     @3650
        clr_a
        lda     near wTaskPosX,y
        tax
        lda     #$06
        jsr     UpdateCharSwapHDMA2
        sta     near wTaskPosX,y
        dec     z22
        sec
        rts
@3650:  ldx     zTaskOffset
        inc     near wTaskState,x
        inc     near wTaskPosX,x
; fallthrough

; ------------------------------------------------------------------------------

; [ show character in new slot ]

CharSwapBtmTask_02:
@3658:  lda     z45
        bit     #$08
        beq     @3673
        ldy     zTaskOffset
        lda     z22
        beq     @3675
        clr_a
        lda     near wTaskPosX,y
        tax
        lda     #$17
        jsr     UpdateCharSwapHDMA1
        sta     near wTaskPosX,y
        dec     z22
@3673:  sec
        rts
@3675:  clc
        rts

; ------------------------------------------------------------------------------

; [ update bg1 hscroll dma table (character swap, hide top/show bottom) ]

UpdateCharSwapHDMA1:
@3677:  sta     $7e9a09,x
        inx
        sta     $7e9a09,x
        inx
        sta     $7e9a09,x
        inx
        sta     $7e9a09,x
        inx
        txa
        rts

; ------------------------------------------------------------------------------

; [ update bg1 hscroll dma table (character swap, show top/hide bottom) ]

UpdateCharSwapHDMA2:
@368d:  sta     $7e9a09,x
        dex
        sta     $7e9a09,x
        dex
        sta     $7e9a09,x
        dex
        sta     $7e9a09,x
        dex
        txa
        rts

; ------------------------------------------------------------------------------

; [ init bg3 vscroll hdma (main menu) ]

InitMainMenuBG3VScrollHDMA:
@36a3:  lda     #$02
        sta     hDMA5::CTRL
        lda     #<hBG3VOFS
        sta     hDMA5::HREG
        ldy     #near MainMenuBG3VScrollHDMATbl
        sty     hDMA5::ADDR
        lda     #^MainMenuBG3VScrollHDMATbl
        sta     hDMA5::ADDR_B
        lda     #^MainMenuBG3VScrollHDMATbl
        sta     hDMA5::HDMA_B
        lda     #BIT_5
        tsb     zEnableHDMA
        rts

; ------------------------------------------------------------------------------

; bg3 vertical scroll hdma table (main menu)
MainMenuBG3VScrollHDMATbl:
        hdma_word 15, 0
        hdma_word 15, 3
        hdma_word 15, 4
        hdma_word 15, 5
        hdma_word 15, 6
        hdma_word 15, 7
        hdma_word 15, 8
        hdma_word 15, 9
        hdma_word 7, 8
        hdma_word 8, 0
        hdma_word 8, 0
        hdma_word 24, 0
        hdma_end

; ------------------------------------------------------------------------------

; [ menu state $65: scroll menu horizontal ]

MenuState_65:
@36e7:  lda     zWaitCounter            ; branch if wait counter is not clear
        bne     @36ef
        lda     zNextMenuState          ; go to next menu state
        sta     zMenuState
@36ef:  longa
        lda     zBG1HScroll
        clc
        adc     zMenuScrollRate
        sta     zBG1HScroll
        sta     zBG2HScroll
        sta     zBG3HScroll
        shorta
        rts

; ------------------------------------------------------------------------------

; [ init cursor for gogo's status menu ]

LoadGogoStatusCursor:
@36ff:  ldy     #near GogoStatusCursorProp
        jmp     LoadCursor

; ------------------------------------------------------------------------------

; [ update cursor for gogo's status menu ]

UpdateGogoStatusCursor:
@3705:  jsr     MoveCursor

InitGogoStatusCursor:
@3708:  ldy     #near GogoStatusCursorPos
        jmp     UpdateCursorPos

; ------------------------------------------------------------------------------

GogoStatusCursorProp:
        cursor_prop {0, 0}, {1, 4}, NO_X_WRAP

GogoStatusCursorPos:
@3713:  cursor_pos {144, 89}
        cursor_pos {144, 101}
        cursor_pos {144, 113}
        cursor_pos {144, 125}

; ------------------------------------------------------------------------------

MainMenuWoundedText:
        raw_text MAIN_MENU_WOUNDED
        calc_size MainMenuWoundedText

MainMenuLabelTextList:
@3723:  .addr   MainMenuTimeText
        .addr   MainMenuStepsText
        .addr   MainMenuOrderText
        calc_size MainMenuLabelTextList

MainMenuOptionsTextList1:
@3729:  .addr   MainMenuItemText
        .addr   MainMenuSkillsText
        .addr   MainMenuRelicText
        .addr   MainMenuStatusText
        calc_size MainMenuOptionsTextList1

CharBlock1SlashTextList:
@3731:  .addr   CharBlock1HPSlashText
        .addr   CharBlock1MPSlashText
        calc_size CharBlock1SlashTextList

CharBlock2SlashTextList:
@3735:  .addr   CharBlock2HPSlashText
        .addr   CharBlock2MPSlashText
        calc_size CharBlock2SlashTextList

CharBlock3SlashTextList:
@3739:  .addr   CharBlock3HPSlashText
        .addr   CharBlock3MPSlashText
        calc_size CharBlock3SlashTextList

CharBlock4SlashTextList:
@373d:  .addr   CharBlock4HPSlashText
        .addr   CharBlock4MPSlashText
        calc_size CharBlock4SlashTextList

CharBlock1LabelTextList:
@3741:  .addr   CharBlock1LevelText
        .addr   CharBlock1HPText
        .addr   CharBlock1MPText
        calc_size CharBlock1LabelTextList

CharBlock2LabelTextList:
@3747:  .addr   CharBlock2LevelText
        .addr   CharBlock2HPText
        .addr   CharBlock2MPText
        calc_size CharBlock2LabelTextList

CharBlock3LabelTextList:
@374d:  .addr   CharBlock3LevelText
        .addr   CharBlock3HPText
        .addr   CharBlock3MPText
        calc_size CharBlock3LabelTextList

CharBlock4LabelTextList:
@3753:  .addr   CharBlock4LevelText
        .addr   CharBlock4HPText
        .addr   CharBlock4MPText
        calc_size CharBlock4LabelTextList

MainMenuOptionsTextList2:
@3759:  .addr   MainMenuEquipText
        .addr   MainMenuConfigText
        calc_size MainMenuOptionsTextList2

GameLoadChoiceTextList:
@375d:  .addr   GameLoadYesText
        .addr   GameLoadNoText
        .addr   GameLoadMsgText1
        .addr   GameLoadMsgText2
        calc_size GameLoadChoiceTextList

GameSaveChoiceTextList:
        .addr   GameLoadYesText
        .addr   GameLoadNoText
        .addr   GameSaveMsgText1
        .addr   GameSaveMsgText2
        .addr   GameSaveMsgText3
        calc_size GameSaveChoiceTextList

CharBlock1LevelText:            pos_text CHAR_BLOCK_1_LEVEL
CharBlock1HPText:               pos_text CHAR_BLOCK_1_HP
CharBlock1MPText:               pos_text CHAR_BLOCK_1_MP
CharBlock1HPSlashText:          pos_text CHAR_BLOCK_1_HP_SLASH
CharBlock1MPSlashText:          pos_text CHAR_BLOCK_1_MP_SLASH

CharBlock2LevelText:            pos_text CHAR_BLOCK_2_LEVEL
CharBlock2HPText:               pos_text CHAR_BLOCK_2_HP
CharBlock2MPText:               pos_text CHAR_BLOCK_2_MP
CharBlock2HPSlashText:          pos_text CHAR_BLOCK_2_HP_SLASH
CharBlock2MPSlashText:          pos_text CHAR_BLOCK_2_MP_SLASH

CharBlock3LevelText:            pos_text CHAR_BLOCK_3_LEVEL
CharBlock3HPText:               pos_text CHAR_BLOCK_3_HP
CharBlock3MPText:               pos_text CHAR_BLOCK_3_MP
CharBlock3HPSlashText:          pos_text CHAR_BLOCK_3_HP_SLASH
CharBlock3MPSlashText:          pos_text CHAR_BLOCK_3_MP_SLASH

CharBlock4LevelText:            pos_text CHAR_BLOCK_4_LEVEL
CharBlock4HPText:               pos_text CHAR_BLOCK_4_HP
CharBlock4MPText:               pos_text CHAR_BLOCK_4_MP
CharBlock4HPSlashText:          pos_text CHAR_BLOCK_4_HP_SLASH
CharBlock4MPSlashText:          pos_text CHAR_BLOCK_4_MP_SLASH

MainMenuItemText:               pos_text MAIN_MENU_ITEM
MainMenuSkillsText:             pos_text MAIN_MENU_SKILLS
MainMenuEquipText:              pos_text MAIN_MENU_EQUIP
MainMenuRelicText:              pos_text MAIN_MENU_RELIC
MainMenuStatusText:             pos_text MAIN_MENU_STATUS
MainMenuConfigText:             pos_text MAIN_MENU_CONFIG
MainMenuSaveText:               pos_text MAIN_MENU_SAVE
MainMenuTimeText:               pos_text MAIN_MENU_TIME
MainMenuColonText:              pos_text MAIN_MENU_COLON
MainMenuStepsText:              pos_text MAIN_MENU_STEPS
MainMenuGilText:                pos_text MAIN_MENU_GIL

GameLoadYesText:                pos_text GAME_LOAD_YES
GameLoadNoText:                 pos_text GAME_LOAD_NO
GameLoadMsgText1:               pos_text GAME_LOAD_MSG_1
GameLoadMsgText2:               pos_text GAME_LOAD_MSG_2

GameSaveMsgText1:               pos_text GAME_SAVE_MSG_1
GameSaveMsgText2:               pos_text GAME_SAVE_MSG_2
GameSaveMsgText3:               pos_text GAME_SAVE_MSG_3
.if !LANG_EN
GameSaveUnusedText:             pos_text GAME_SAVE_UNUSED
.endif

MainMenuOrderText:              pos_text MAIN_MENU_ORDER

; ------------------------------------------------------------------------------
