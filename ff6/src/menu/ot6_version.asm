; ------------------------------------------------------------------------------
; ot6: the build's version on the Config screen
;
; Ot6VersionText (c0/ffa0, field/header.asm) is OT6_VERSION_CELLS (15)
; menu-font cells, "OT6 v<VERSION>" centered and space-padded, stamped after
; the link by tools/build/rom_version.py.  The Config screen shows all 15 cells
; centered on BG3 row 25, the bottom row inside its main window: below the
; last option on either page (page 1 ends at row 21, page 2 at row 23), clear
; of the window's frame, the "Config" tab and the page arrow.  BG3 does not
; scroll between the two pages, so it shows on both.
;
; Not in the Config init.  DrawConfigMenu runs with interrupts off and ends
; in vblank with few scanlines to spare (the game clock, which seeds
; battles, loses a tick if it ends after vblank), so it is exactly vanilla.
; The row is drawn by the first frame of the Config select state instead:
; MenuState_0e's first jsr (field_menu.asm, same size) comes here.  That
; frame writes the 15 cells into the BG3 buffer and queues them on DMA2; the
; next frame, finding DMA2 still pointed at the row, releases it; after that
; the drawn row (its first cell no longer 0) makes this a compare and a jmp.
; Every Config open draws it again: DrawConfigMenu clears the BG3 buffer.
;
; This code sits in its own segment after the vanilla bank (ot6_menu_version,
; cfg/ff6-en.cfg): no vanilla menu code or data moves.
; ------------------------------------------------------------------------------

.import Ot6VersionText
.include "ot6_version.inc"

OT6_CFG_ROW = 25
OT6_CFG_X = (32 - OT6_VERSION_CELLS) / 2
OT6_CFG_CELL = OT6_CFG_ROW * 32 + OT6_CFG_X     ; in BG3 screen A, in cells
OT6_CFG_VRAM = $4000 + OT6_CFG_CELL             ; TfrBG3ScreenAB's VRAM address
OT6_CFG_ATTR = BG3_TEXT_COLOR::GRAY

.segment "ot6_menu_version"

; ------------------------------------------------------------------------------

; [ Config select, each frame: the version row, then vanilla's first call ]

Ot6ConfigSelectFrame:
        ldy     zDMA2Dest
        cpy     #OT6_CFG_VRAM
        bne     @idle
        jsr     DisableDMA2             ; the row went to VRAM last vblank
        bra     @done
@idle:  cpy     #0
        bne     @done                   ; DMA2 is someone else's
        lda     f:wBG3Tiles::ScreenA + OT6_CFG_CELL * 2
        bne     @done                   ; drawn already (a cell is $ff or a glyph)
        ldy     #.loword(Ot6VersionText)
        sty     $e7
        lda     #^Ot6VersionText
        sta     $e9
        ldx     z0                      ; X: the buffer, two bytes a cell
        txy                             ; Y: the field, all 15 cells
@cell:  lda     [$e7],y
        sta     f:wBG3Tiles::ScreenA + OT6_CFG_CELL * 2,x
        lda     #OT6_CFG_ATTR
        sta     f:wBG3Tiles::ScreenA + OT6_CFG_CELL * 2 + 1,x
        inx2
        iny
        cpy     #OT6_VERSION_CELLS
        bne     @cell
        ldy     #near wBG3Tiles::ScreenA + OT6_CFG_CELL * 2
        sty     zDMA2Src
        lda     #^wBG3Tiles::ScreenA
        sta     zDMA2Src+2
        ldy     #OT6_VERSION_CELLS * 2
        sty     zDMA2Size
        ldy     #OT6_CFG_VRAM
        sty     zDMA2Dest               ; last: TfrVRAM2 runs on a nonzero dest
@done:  jmp     InitDMA1BG1ScreenAB

; ------------------------------------------------------------------------------
