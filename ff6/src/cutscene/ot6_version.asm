; ------------------------------------------------------------------------------
; ot6: the build's version on the boot splash (the white "FINAL FANTASY III"
; logo over the copyright lines)
;
; Ot6VersionText (c0/ffa0, field/header.asm) is the build's "OT6 v<VERSION>",
; menu-encoded and $00-terminated, stamped after the link by
; tools/build/rom_version.py; the Config screen draws the same field.  Here
; it goes on BG1's right screen, the splash's one opaque layer (the logo is
; its rows 8-15, laid over a fill of tile $377 in colour 1, the backdrop
; grey; _7e7a33), on row 17, centered: under the logo and above the
; copyright sprites (y=160).  The glyphs are the menu font's
; (SmallFontGfx), recoloured into the logo's palette 1 (SplashPal: ink
; white $7fff, shadow black $0000, the rest the backdrop grey $1063), in
; BG1 tiles $310-$319 (VRAM $6100-$619f), which nothing loads: they stay
; zero from ClearVRAM through the splash and the title.
;
; Timing and footprint, so the boot plays exactly as before:
;   - The cutscene program is vanilla byte for byte, so its decompression
;     (here and again for the opening) takes exactly the time it always did.
;     The title entry in C2 jumps to Ot6TitleScreen instead of straight to
;     TitleMain; that copies two small trampolines to the end of the
;     decompressed program in WRAM and points the splash's two calls at them
;     (SplashState_00's jsr _7e5306, SplashLoop's last jsr DisableInterrupts).
;     The opening decompresses the program afresh, which erases both.
;   - The drawing and erasing run in forced blank (before the splash's first
;     WaitVBlank; after DisableInterrupts at its end), touch no RAM but the
;     patched program, and write VRAM only.
;   - At the end of the splash the cells go back to tile $377 and the tiles
;     to zero, so the title and everything after it see the VRAM they
;     always did.
; ------------------------------------------------------------------------------

.segment "ot6_title_version"

.import Ot6VersionText, SmallFontGfx

OT6_SPLASH_MAX = 10                     ; the Config tab's width (rom_version.py)
OT6_SPLASH_ROW = 17
OT6_SPLASH_MAP = $0400                  ; BG1SC $03: 64x64; the splash shows
                                        ; the top-right screen (BG1 hscroll 256)
OT6_SPLASH_FILL = $0777                 ; that screen's fill (_7e7a4c, EN)
OT6_SPLASH_TILE = $0310
OT6_SPLASH_CHR = $3000 + OT6_SPLASH_TILE * 16  ; BG12NBA $23: BG1 4bpp at $3000
OT6_SPLASH_ATTR = 1 << 10               ; palette 1, the logo's

; ------------------------------------------------------------------------------

; [ title screen entry: point the splash's two calls at the trampolines ]

; from TitleScreen (C2), the program just decompressed to $7e5000; every
; register is preserved for TitleMain, which saves them for the event code

Ot6TitleScreen:
        php
        longai
        pha
        phx
        ldx     #0
@copy:  lda     f:Ot6SplashTramp,x
        sta     f:Ot6CutsceneProgEnd,x
        inx2
        cpx     #OT6_TRAMP_SIZE
        bcc     @copy
        lda     #.loword(Ot6CutsceneProgEnd)
        sta     f:Ot6SplashOnSite+1     ; jsr Ot6SplashVersionOn
        lda     #.loword(Ot6CutsceneProgEnd) + OT6_TRAMP_OFF
        sta     f:Ot6SplashOffSite+1    ; jsr Ot6SplashVersionOff
        plx
        pla
        plp
        jml     TitleScreen_ext2

; ------------------------------------------------------------------------------

; the trampolines, as they run at Ot6CutsceneProgEnd (WRAM)

Ot6SplashTramp:
; [ splash init: the version, then the copyright sprites (_7e5306) ]
        .byte   $22                     ; jsl Ot6DrawSplashVersion
        .faraddr Ot6DrawSplashVersion
        .byte   $4c                     ; jmp _7e5306
        .word   .loword(_7e5306)
OT6_TRAMP_OFF = * - Ot6SplashTramp
; [ splash end: forced blank (DisableInterrupts), then erase the version ]
        .byte   $20                     ; jsr DisableInterrupts
        .word   .loword(DisableInterrupts)
        .byte   $22                     ; jsl Ot6EraseSplashVersion
        .faraddr Ot6EraseSplashVersion
        .byte   $60                     ; rts
        .byte   $00                     ; (pad to whole words)
OT6_TRAMP_SIZE = * - Ot6SplashTramp


; [ draw the version on the splash ]

; forced blank; A 8-bit, X/Y 16-bit on entry and exit

Ot6DrawSplashVersion:
        php
        phb
        shorta
        longi
        jsr     Ot6SplashMapAddr        ; VMADD = the text's first cell, X = 0
@cell:  lda     f:Ot6VersionText,x      ; one map word per character:
        beq     @glyphs                 ; palette 1, tile $310 + i
        longa
        txa
        clc
        adc     #OT6_SPLASH_ATTR | OT6_SPLASH_TILE
        sta     f:hVMDATAL
        shorta
        inx
        cpx     #OT6_SPLASH_MAX
        bne     @cell
@glyphs:
        longa
        lda     #OT6_SPLASH_CHR
        sta     f:hVMADDL
        shorta
        lda     #^SmallFontGfx
        pha
        plb
        ldx     #0
; each 2bpp font pixel s (planes p0, p1) becomes 4bpp colour t of palette 1:
; s 0 -> 1 (backdrop grey), s 1 -> 3 (black), s 2 -> 2 (grey), s 3 -> 4 (white)
; so plane 0 = ~p1, plane 1 = p0 ^ p1, plane 2 = p0 & p1, plane 3 = 0
@char:  lda     f:Ot6VersionText,x
        beq     @done
        jsr     Ot6SplashGlyphY         ; Y = the glyph's 16 bytes
@p01:   lda     .loword(SmallFontGfx)+1,y
        eor     #$ff
        sta     f:hVMDATAL              ; plane 0
        lda     .loword(SmallFontGfx),y
        eor     .loword(SmallFontGfx)+1,y
        sta     f:hVMDATAH              ; plane 1
        iny2
        tya
        and     #$0f
        bne     @p01
        lda     f:Ot6VersionText,x
        jsr     Ot6SplashGlyphY
@p23:   lda     .loword(SmallFontGfx),y
        and     .loword(SmallFontGfx)+1,y
        sta     f:hVMDATAL              ; plane 2
        lda     #0
        sta     f:hVMDATAH              ; plane 3
        iny2
        tya
        and     #$0f
        bne     @p23
        inx
        cpx     #OT6_SPLASH_MAX
        bne     @char
@done:  plb
        plp
        rtl

; ------------------------------------------------------------------------------

; [ Y = the font offset of character A (A 8-bit) ]

Ot6SplashGlyphY:
        longa
        and     #$00ff
        asl4
        tay
        shorta
        rts

; ------------------------------------------------------------------------------

; [ erase the version: the fill back in its cells, its tiles back to zero ]

; forced blank; A 8-bit, X/Y 16-bit on entry and exit

Ot6EraseSplashVersion:
        php
        shorta
        longi
        jsr     Ot6SplashMapAddr
@cell:  lda     f:Ot6VersionText,x
        beq     @glyphs
        longa
        lda     #OT6_SPLASH_FILL
        sta     f:hVMDATAL
        shorta
        inx
        cpx     #OT6_SPLASH_MAX
        bne     @cell
@glyphs:
        longa
        lda     #OT6_SPLASH_CHR
        sta     f:hVMADDL
        shorta
        ldx     #0
@char:  lda     f:Ot6VersionText,x
        beq     @done
        ldy     #16
        longa
        lda     #0
@word:  sta     f:hVMDATAL
        dey
        bne     @word
        shorta
        inx
        cpx     #OT6_SPLASH_MAX
        bne     @char
@done:  plp
        rtl

; ------------------------------------------------------------------------------

; [ VMADD = the first cell of the centered text; X = 0 ]

; the text is n characters (up to OT6_SPLASH_MAX), from column (32 - n) / 2

Ot6SplashMapAddr:
        lda     #$80                    ; increment after the high byte (as
        sta     f:hVMAINC               ; InitHWRegs set it)
        ldx     #0
@len:   lda     f:Ot6VersionText,x
        beq     @addr
        inx
        cpx     #OT6_SPLASH_MAX
        bne     @len
@addr:  longa
        txa
        eor     #$ffff
        sec
        adc     #32                     ; 32 - n
        lsr
        clc
        adc     #OT6_SPLASH_MAP + OT6_SPLASH_ROW * 32
        sta     f:hVMADDL
        shorta
        ldx     #0
        rts

; ------------------------------------------------------------------------------
