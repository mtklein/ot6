; ------------------------------------------------------------------------------
; ot6: the Config screen's version tab
;
; Ot6VersionText (c0/ffa0, field/header.asm) is the build's "OT6 v<VERSION>",
; menu-encoded and $00-terminated, stamped after the link by
; tools/build/rom_version.py.  The Config screen shows it in a tab in its
; top-left corner, the mirror of the "Config" tab top right: the window on
; BG2, the text on BG3, which does not scroll between the two Config pages,
; so it shows on both.
;
; This code sits in its own segment after the vanilla bank (ot6_menu_version,
; cfg/ff6-en.cfg) and DrawConfigMenu reaches it through two retargeted jsr
; operands, so no vanilla menu code or data moves: a run that never opens
; Config executes, and leaves on the stack, exactly what it did before.
; ------------------------------------------------------------------------------

.import Ot6VersionText

; The version tab.  Its inner width is the longest version text it shows:
; rom_version.py stamp refuses a VERSION whose "OT6 v<VERSION>" is wider.
CONFIG_VERSION_TEXT_WIDTH = 10

.segment "ot6_menu_version"

; ------------------------------------------------------------------------------

; [ draw the Config label window, then the version tab ]

; Y: the label window (config.asm DrawConfigMenu's argument to DrawWindow)

Ot6DrawConfigWindows:
        jsr     DrawWindow
        ldy     #near ConfigVersionWindow
        jmp     DrawWindow

; ------------------------------------------------------------------------------

; [ draw the Config title, then the version ]

; Y: the title text (DrawConfigMenu's argument to DrawPosKana)

Ot6DrawConfigTitle:
        jsr     DrawPosKana
        lda     #BG3_TEXT_COLOR::DEFAULT
        sta     zTextColor
        longa
        lda_pos BG3A, {2, 2}
        sta     $7e9e89                 ; the text buffer: screen position
        shorta
        ldx     z0
@copy:  lda     f:Ot6VersionText,x
        sta     $7e9e8b,x               ; ...then the text
        beq     @draw
        inx
        cpx     #CONFIG_VERSION_TEXT_WIDTH
        bne     @copy
        clr_a                           ; never draw past the tab
        sta     $7e9e8b,x
@draw:  ldy     #near $7e9e89
        sty     $e7
        lda     #^$7e9e89
        sta     $e9
        jmp     DrawPosTextFar

; ------------------------------------------------------------------------------

ConfigVersionWindow:    make_window BG2A, {1, 1}, {CONFIG_VERSION_TEXT_WIDTH, 2}

; ------------------------------------------------------------------------------
