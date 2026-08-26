; ------------------------------------------------------------------------------

; [ a battle dialogue clobbered our font cells; restore, then flag a re-lay ]

; called from _c143b9 (dialogue close, small-font restore) in bank C1 in
; TAIL position, with WaitTfrVRAM's parameters live in the registers
; (A = source bank, X = source, Y = vram dest, $10 = size). they are passed
; straight through to the vanilla staged restore (WaitTfrVRAM streams
; $400 bytes per frame and returns only after the last chunk has landed
; in vram), and OT6_FONTDIRTY is raised only after that, so the battle nmi
; re-lays our icons over a fully-restored font (in vblank, where direct vram
; writes land). the re-lay is staged: OT6_FONTDIRTY counts
; stages remaining, and the nmi flush runs one ~128-byte slice per
; frame, since the whole 768-byte re-lay as PIO would run ~46 scanlines,
; more than an entire vblank.
;
; The restore must complete before the flag is raised: raising the flag
; before the restore would let the nmi re-lay fire between restore chunks,
; and the later chunks would overwrite the icons back to vanilla.

.proc Ot6FontRestoreMark_ext
        jsl     WaitTfrVRAM_far ; registers pass through untouched
        php
        sep     #$20            ; a8 (index width irrelevant)
        pha
        lda     #OT6_RELAY_STAGES
        sta     f:$7e0000+OT6_FONTDIRTY
        pla
        plp
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ upload element icon tiles into the battle small font ]

; called from LoadMenuGfx right after the small font transfer (forced
; blank). one 2bpp tile (8 words) per element, cell per Ot6ElemGlyphTbl.
;
; cell choice matters: vanilla battle tilemaps are junk-padded with codes
; that point at blank font cells ($ee alone appears 1000+ times around the
; screen borders), and filling those cells paints garbage at the edges. every
; cell below was verified unreferenced in the battle tilemap regions.
;
; the upload is split into three ~128-byte slices so the nmi flush can
; re-lay the font one slice per vblank after a battle dialogue (the
; whole 384 bytes as PIO would run ~23 scanlines, more than a vblank).
; this entry point runs all slices back to back: it is only called in
; forced blank (battle init), where there is no time budget.

.proc Ot6LoadFontIcons_ext
        .a8
        .i16
        php
        phb
        clr_a
        pha
        plb                     ; db = $00 for hardware registers
        longi
        shorta
        lda     #$80
        sta     hVMAINC         ; increment on high byte, +1 word
        jsr     Ot6LoadElemIcons
        jsr     Ot6LoadBgGlyphsA
        jsr     Ot6LoadBgGlyphsB
        plb
        plp
        rtl
.endproc

; [ re-lay slice: the eight element icon tiles (128 bytes) ]

; a8/i16, db = $00, vmainc $80. exits a8. clobbers a/x/y.

.proc Ot6LoadElemIcons
        .a8
        .i16
        ldx     #$0000          ; icon index (long,y indexing doesn't exist)
@icon:  shorta
        lda     f:Ot6ElemGlyphTbl,x
        longa
        and     #$00ff
        asl
        asl
        asl
        clc
        adc     #$5800          ; vram word address of the font cell
        sta     hVMADDL
        txa
        asl
        asl
        asl
        asl
        tax                     ; x becomes data offset = icon * 16
@word:  lda     f:Ot6FontIcons,x
        sta     hVMDATAL
        inx2
        txa
        and     #$000f
        bne     @word
        txa                     ; recover icon index: offset / 16
        lsr
        lsr
        lsr
        lsr
        tax
        cpx     #$0008
        bcc     @icon
        shorta
        rts
.endproc

; element bit (fire $01 .. water $80) -> small font glyph/tile code.
; the weakness strip draws from this same table.
Ot6ElemGlyphTbl:
        .byte   $eb             ; fire
        .byte   $ec             ; ice
        .byte   $ed             ; lightning
        .byte   $64             ; poison ($ee is vanilla's border junk fill)
        .byte   $ef             ; wind
        .byte   $fb             ; holy
        .byte   $fc             ; earth
        .byte   $fd             ; water

OT6_QMARK := $bf                ; '?' glyph (unrevealed weakness slot)

; ------------------------------------------------------------------------------

; [ the same eight element tiles, in the field menu's font ]

; These tiles exist only in the battle font.  Ot6LoadFontIcons_ext above
; uploads them to vram word $5800 from LoadMenuGfx (btlgfx_main.asm:8911),
; which is the battle graphics path and runs nowhere else, so a field page
; asking for an element glyph would draw whatever occupied that cell of the
; menu's own font.  Only class glyphs (which ship in the vanilla font art
; itself, the Ot6ClassGlyphTbl note below) were available there before this.
;
; Where the menu's font is, and there are two copies, neither at $5800:
;   * LoadFontGfx2bpp (menu_gfx.asm:120) lays 256 2bpp tiles at word $6000,
;     BG2/BG3's char base (hBG34NBA = $66, menu_init_2.asm:435);
;   * LoadFontGfx4bpp (:139) expands the same source art into 4bpp tiles at
;     word $5000, BG1's char base (hBG12NBA = $65, :433), with the upper two
;     bitplanes zeroed.
; Every field ability page draws through GetBG1TilemapPtr, i.e. BG1, so the
; $5000 copy is the one the Blitz page reads.  The $6000 copy is patched too
; because BG3A carries menu text as well (config.asm:2044, colosseum.asm:328).
;
; Free space, measured rather than assumed: gfx/small_font_en.2bpp is 4096
; bytes / 256 tiles, and cells $00-$7f, $d0-$d1, $eb-$ef and $fb-$ff are
; sixteen zero bytes each.  So all eight cells Ot6ElemGlyphTbl names above
; ($eb $ec $ed $64 $ef $fb $fc $fd) are blank in the field font as
; they are in the battle one, and the menu text codec cannot spell them
; (small_symbols_en.json stops at $ea and resumes at $f0; text_en.json's
; letters start at $80).  Nothing had to move to make room, and both loops
; below write strictly inside the range the vanilla loader just blanked, so
; they cannot step outside the font.
;
; What it costs, per menu open: eight tiles.  The 4bpp pass writes 8 data
; words + 8 zero words each = 128 word writes; the 2bpp pass 8 each = 64.
; The font expansions they hang off write 4096 and 3072 words respectively
; (and LoadFontGfx4bpp then streams 2048 more for WindowGfx before our hook
; runs at all), so this is +3.1% and +2.1% of an upload already happening, and
; +2.1% of LoadFontGfx4bpp end to end.  All of it in the same forced-blank
; menu init (InitMenu -> InitMenuGfx, menu_common.asm:133), before a frame is
; shown.  No re-lay machinery is needed: unlike the battle font, which a
; dialogue window re-uploads mid-fight (the reason Ot6FontRestoreMark
; and OT6_FONTDIRTY exist above), nothing rewrites the menu font while a menu
; is open.  So there are two plain entry points and no nmi slicing.
;
; Two entry points rather than one that does both: menu types 1
; and 6 (name change, SwdTech rename) call LoadFontGfx4bpp without
; LoadFontGfx2bpp (menu_gfx.asm:52,108), so a single proc writing $6000 as
; well would overwrite whatever else those types put there.  Each entry
; patches only the copy the loader it hangs off has just laid down.
;
; ------------------------------------------------------------------------------

; ---- the 4bpp copy at word $5000 (BG1: every ability page) ----
.proc Ot6MenuIcons4bpp_ext
        .a8
        .i16
        php
        phb
        clr_a
        pha
        plb                     ; db = $00 for hardware registers
        longi
        shorta
        lda     #$80
        sta     hVMAINC         ; increment on high byte, +1 word
        ldx     #$0000          ; icon index 0..7
@icon:  longa
        jsr     Ot6MenuIconCell ; a = the font cell this icon claims
        asl4                    ; * 16 words = the 4bpp tile stride
        clc
        adc     #$5000
        sta     hVMADDL
        jsr     Ot6MenuIconArt  ; the tile's eight art words (exits a16)
        ldy     #$0008
:       stz     hVMDATAL        ; bitplanes 2/3: the art is 2bpp, as
        dey                     ;   vanilla's own expansion leaves them
        bne     :-              ;   (menu_gfx.asm:164)
        shorta
        inx
        cpx     #$0008
        bcc     @icon
        plb
        plp
        rtl
.endproc

; ---- the 2bpp copy at word $6000 (BG2/BG3) ----
.proc Ot6MenuIcons2bpp_ext
        .a8
        .i16
        php
        phb
        clr_a
        pha
        plb
        longi
        shorta
        lda     #$80
        sta     hVMAINC
        ldx     #$0000
@icon:  longa
        jsr     Ot6MenuIconCell
        asl3                    ; * 8 words = the 2bpp tile stride
        clc
        adc     #$6000
        sta     hVMADDL
        jsr     Ot6MenuIconArt
        shorta
        inx
        cpx     #$0008
        bcc     @icon
        plb
        plp
        rtl
.endproc

; the two halves both passes share, so the pair differs only in the vram base
; and the tile stride, which is the only difference between a 4bpp
; and a 2bpp copy of the same art.  Both read the same two tables the battle
; upload reads, so no third opinion about which cell an element owns can appear.

; x = icon index -> a = its font cell code.  a16 throughout (the high byte of
; the word read is the next table entry, and is masked off); x preserved.
Ot6MenuIconCell:
        .a16
        .i16
        lda     f:Ot6ElemGlyphTbl,x
        and     #$00ff
        rts

; x = icon index -> the icon's eight art words to hVMDATAL.  a16, x preserved.
Ot6MenuIconArt:
        .a16
        .i16
        phx
        txa                     ; a16 + i16: the whole index, 0..7
        asl4                    ; icon * 16 = byte offset into Ot6FontIcons
        tax
        ldy     #$0008
:       lda     f:Ot6FontIcons,x
        sta     hVMDATAL
        inx2
        dey
        bne     :-
        plx
        rts

; ------------------------------------------------------------------------------

; [ write one menu character ]

; replicates btlgfx's DrawMenuKana buffer writes: char + attribute pairs
; into the two row buffers. caller context: menu text drawing (dp $4a/$4c
; buffer pointers, $4e attribute, y = column position, a8/i16, db=$7e).
; a = character code; y advances by 2.

.proc Ot6DrawChar
        .a8
        .i16
        sta     ($4c),y
        lda     #$ff
        sta     ($4a),y
        iny
        lda     $4e
        sta     ($4c),y
        sta     ($4a),y
        iny
        rts
.endproc



; ------------------------------------------------------------------------------

; [ ability element icon + padding for battle ability lists ]

; replaces MenuTextCmd_11's pad logic; called right after MenuTextCmd_0f
; drew the ability name, ($48) still pointing at the ability id.
;   $ff empty slot:            three blanks (as vanilla)
;   spells (< $36, 7 wide):    [element icon or blank][blank][blank]
;   attacks (10 wide):         trailing blank replaced by the icon
; a8/i16, db=$7e, y = column, preserves x

.proc Ot6AbilityPad_ext
        .a8
        .i16
        lda     ($48)
        cmp     #$ff
        beq     @blank3
        cmp     #$36
        bcs     @attack
        jsr     Ot6ElemGlyphFor ; spell: icon (or blank) + two blanks
        jsr     Ot6DrawChar
        bra     @blank2
@attack:
        jsr     Ot6ElemGlyphFor
        cmp     #$ff
        beq     @done           ; no element: leave the name alone
        dey
        dey                     ; back up onto the name's last column
        pha
        lda     ($4c),y
        cmp     #$ff
        bne     @keep           ; 10-char name: no room for an icon
        pla
        jsr     Ot6DrawChar     ; overwrite trailing blank (y returns)
        bra     @done
@keep:  pla
        iny
        iny
@done:  rtl
@blank3:
        lda     #$ff
        jsr     Ot6DrawChar
@blank2:
        lda     #$ff
        jsr     Ot6DrawChar
        lda     #$ff
        jsr     Ot6DrawChar
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ element icon after an ability name in a battle list window ]

; called after ListTextCmd_0f's name loops (battle ability lists draw
; through the LIST text system, not the menu text system). $2c = ability
; id, y = list column, b = tile attribute (must be preserved), ($53)/($51)
; = list buffer pointers, $55 = second-plane attribute word.

; common core: a = GLOBAL ability id; draws the element icon (if any)
; at the current list column, preserving b (the tile attribute) for the
; caller but recoloring our own icon via the palette bits: the battle
; menu ships text palettes 0..7 with distinct color-3 hues (0 white,
; 1 gray, 2 yellow, 3 blue, 6 green, 7 red).
.proc Ot6ListIconCommon
        .a8
        .i16
        sta     OT6_SCR_IDX     ; ability id
        xba
        pha                     ; save the tile attribute living in b
        xba
        lda     OT6_SCR_IDX
        jsr     Ot6ElemGlyphFor ; glyph in a, element index in OT6_SCR_COLS,
        sta     OT6_SCR_BIT     ;   b cleared internally
        cmp     #$ff
        beq     @keep           ; no element: blank glyph, caller's attr
        phx
        lda     OT6_SCR_COLS    ; element index 0-7
        tax                     ; (b = 0 here, so tax is safe)
        lda     f:Ot6ElemPalTbl,x
        plx
        sta     OT6_SCR_COLS    ; palette bits for this element
        pla                     ; caller attr ...
        and     #%11100011      ; ... palette bits swapped for our color
        ora     OT6_SCR_COLS
        bra     @attr
@keep:  pla
@attr:  xba                     ; b = attr for the 16-bit store
        lda     OT6_SCR_BIT     ; glyph, or $ff = blank: always draw, so the
        longa                   ; icon column cannot go stale on reused
        sta     ($53),y         ; row buffers (replicates DrawListLetter)
        lda     $55
        sta     ($51),y
        shorta                  ; b holds our attr; caller reloads per char
        iny
        iny
        rts
.endproc

; element index -> tilemap palette bits (palette << 2); indices 8-11 are
; the four weapon classes (Ot6ElemGlyphFor's class fallback): menu-white,
; the same way these icons render as item-name leading glyphs
Ot6ElemPalTbl:
        .byte   7 << 2          ; fire: red
        .byte   3 << 2          ; ice: blue
        .byte   2 << 2          ; lightning: yellow
        .byte   6 << 2          ; poison: green
        .byte   0 << 2          ; wind: white
        .byte   2 << 2          ; holy: yellow (star shape vs bolt zigzag)
        .byte   1 << 2          ; earth: gray
        .byte   3 << 2          ; water: blue (wave shape vs ice crystal)
        .byte   0 << 2          ; slash: white
        .byte   0 << 2          ; pierce: white
        .byte   0 << 2          ; bludgeon: white
        .byte   0 << 2          ; special ¤: white

; generic battle lists ($2c already holds a global ability id)
.proc Ot6ListIcon_ext
        .a8
        .i16
        lda     $2c
        jsr     Ot6ListIconCommon
        rtl
.endproc

; magitek list: $2c is a local index into the magitek attacks (base $83)
.proc Ot6MagitekIcon_ext
        .a8
        .i16
        lda     $2c
        clc
        adc     #$83
        jsr     Ot6ListIconCommon
        rtl
.endproc

; lore list: $2c is a local lore index (base $8b)
.proc Ot6LoreIcon_ext
        .a8
        .i16
        lda     $2c
        clc
        adc     #$8b
        jsr     Ot6ListIconCommon
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ class icon after a tool name in the battle Tools list ]

; tail of ListTextCmd_0e, the item-name drawer every battle item list
; shares. only the tools window decorates ($7bc2 holds menu state $2e
; for every row it stages): item/throw/equip rows already carry a
; weapon's class as the leading name icon, and a second copy there
; would be redundant. tools keep their vanilla wrench icons ✦, so the
; class goes after the name, where abilities show theirs.
; the icon replaces the name field's trailing blank (the field is
; always fully rewritten by the name loop, so the column cannot go
; stale); a full 13-char name has no blank and keeps all its letters,
; e.g. autocrossbow, by the same rule that trims 10-char ability names in
; Ot6AbilityPad. classless tools ($00) and null-break rows draw
; nothing. a8/i16, db=$7e, $2c = the item id just named, y = list
; column past the name, b = tile attribute (preserved).

.proc Ot6ToolListIcon_ext
        .a8
        .i16
        xba
        pha                     ; stash the tile attr living in b
        xba
        lda     a:$7bc2         ; battle menu state under update
        cmp     #$2e            ; $2e = the tools window staging its rows
        bne     @out
        phx
        lda     $2c             ; the item id the row just named
        longa
        and     #$00ff
        tax
        shorta0
        lda     f:Ot6WeapClassTbl,x
        plx
        cmp     #$00            ; retest: plx sets n/z from the value it
                                ; pulled, so without this the two guards below
                                ; would read the caller's restored x rather
                                ; than the class byte. x is ListTextCmd_0e's
                                ; ItemName cursor (id*13 + 13), nonzero and
                                ; positive for every item, so both guards
                                ; would fall through on a classless tool and
                                ; @bit would spin on a zero OT6_SCR_BIT
                                ; forever.
        beq     @out            ; classless tool: nothing to teach
        bmi     @out            ; null-break: teaches nothing, shows nothing
        sta     OT6_SCR_BIT
        phx
        ldx     #$0000
@bit:   lsr     OT6_SCR_BIT
        bcs     @glyph
        inx
        bra     @bit
@glyph: lda     f:Ot6ClassGlyphTbl,x
        plx
        sta     OT6_SCR_BIT     ; the class glyph
        dey
        dey                     ; back onto the name's last column
        lda     ($53),y
        cmp     #$ff
        bne     @full           ; 13-char name: no room for an icon
        pla                     ; the caller's attr ...
        xba                     ; ... into b for the 16-bit store
        lda     OT6_SCR_BIT
        longa
        sta     ($53),y         ; glyph | attr<<8 (replicates DrawListLetter)
        lda     $55
        sta     ($51),y
        shorta                  ; b holds the attr; caller reloads per char
        iny
        iny
        rtl
@full:  iny
        iny
@out:   pla
        xba                     ; restore b for the caller
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ element glyph for an ability, or its weapon-class glyph ]

; a = ability id (0-255) -> a = element icon glyph, or the ability's
; class icon glyph when it has no element (Ot6SkillClassTbl: physical
; skills show their class where spells show their element, so
; TekMissile shows pierce in the magitek list, Pummel bludgeon, and quadra
; slam slash), or $ff when it has neither. first set
; bit wins on both axes; an element takes priority over the class (the design:
; "consult the class when the ability has no element"). null-break rows
; would show a class they never chip, so bit 7 hides the icon too.
; OT6_SCR_COLS = palette index: 0-7 element hues, 8-11 the class rows.
; preserves x/y.

.proc Ot6ElemGlyphFor
        .a8
        .i16
        phx
        pha                     ; the ability id, for the class fallback
        longa
        and     #$00ff
        asl                     ; id * 2
        pha
        asl
        pha                     ; id * 4
        asl                     ; id * 8
        clc
        adc     $01,s           ; + id*4
        clc
        adc     $03,s           ; + id*2  = id * 14
        tax
        pla
        pla
        shorta0
        lda     f:MagicProp+1,x ; ability element byte
        beq     @class
        ldx     #$0000
@bit:   lsr
        bcs     @hit
        inx
        bra     @bit
@hit:   txa
        sta     OT6_SCR_COLS    ; element index, for palette selection
        pla                     ; (discard the stashed id)
        lda     f:Ot6ElemGlyphTbl,x
        plx
        rts
@class: ; elementless: a physical skill's class carries the icon
        ldx     #$0000
@scan:  lda     f:Ot6SkillClassTbl,x
        cmp     #$ff
        beq     @none           ; end of table: classless ability
        cmp     $01,s
        beq     @found
        inx
        inx
        bra     @scan
@found: lda     f:Ot6SkillClassTbl+1,x
        bmi     @none           ; null-break: teaches nothing, shows nothing
        ldx     #$0000
@cbit:  lsr
        bcs     @cidx
        inx
        bra     @cbit
@cidx:  txa
        clc
        adc     #$08
        sta     OT6_SCR_COLS    ; palette index 8-11: the class rows
        pla                     ; (discard the stashed id)
        lda     f:Ot6ClassGlyphTbl,x
        plx
        rts
@none:  pla                     ; (discard the stashed id)
        lda     #$ff
        plx
        rts
.endproc

; ------------------------------------------------------------------------------

; [ the same element-or-class glyph, callable from the menu bank ]

; The field pages need what Ot6ElemGlyphFor decides (element first,
; the ability's break class when it has none, blank when it has neither) and
; they must not get a second opinion about it.  Ot6ElemGlyphFor is an rts
; leaf, so the field bank calls this rtl wrapper instead; the class-only leaf
; is retired, so there is one glyph authority for both halves of the game.
;
; Why it saves and restores a byte of RAM.  Ot6ElemGlyphFor reports its palette
; index by storing OT6_SCR_COLS ($3ed2), which is battle-only scratch, and in
; the field menu that address is inside wBG1Tiles::ScreenA ($7e3849 + $0800,
; menu_ram.inc:458): $3ed2 is the attribute byte of row 26, column 4 of the
; tilemap shadow.  A stray write there would not be visible on screen (row 26
; is outside this window and its char byte stays $00, the blank tile), but
; the byte is saved and restored anyway.  The menu needs no palette index: a
; field icon draws in its row's text colour.
;
; db is forced to $7e so that store lands where the battle path puts it rather
; than in bank $00 open bus; menu-bank callers run with db = $00.
;
; in: A = ability id.  out: A = the glyph, or $ff for neither.  preserves X/Y.
.proc Ot6SkillIconGlyph
        .a8
        .i16
        phb
        pha                     ; [S+2] the ability id
        lda     #$7e
        pha
        plb                     ; db = $7e (Ot6ElemGlyphFor's scratch bank)
        lda     OT6_SCR_COLS
        pha                     ; [S+1] the tilemap byte we are about to clobber
        lda     $02,s           ; the ability id again
        jsr     Ot6ElemGlyphFor
        sta     $02,s           ; the answer replaces the parked id
        pla
        sta     OT6_SCR_COLS    ; ... and the tilemap byte goes back
        pla                     ; the glyph
        plb
        rtl
.endproc

; class bit index (slash 0 .. special 3) -> small font glyph. these four
; cells ship in the vanilla small font (they are the item icons the m3
; weapon renames use), so unlike the element icons they need no
; upload: every battle text system and the bg3 field map index the same
; $5800 font tiles.
Ot6ClassGlyphTbl:
        .byte   $d9             ; slash: the sword icon
        .byte   $da             ; pierce: the spear icon
        .byte   $dc             ; bludgeon: the staff icon
        .byte   $df             ; special ¤: the sparkle icon

; 8x8 2bpp element icons, element-bit order (fire $01 ... water $80)
Ot6FontIcons:
; fire ($eb)
        .byte   $10,$10,$30,$38,$38,$3c,$6c,$7c
        .byte   $6e,$7e,$ee,$fe,$7e,$7c,$3c,$00
; ice ($ec)
        .byte   $10,$10,$10,$38,$6c,$7c,$ee,$fe
        .byte   $6e,$7c,$14,$38,$18,$10,$08,$00
; lightning ($ed)
        .byte   $1e,$1e,$3c,$38,$78,$70,$fc,$fc
        .byte   $3c,$18,$38,$30,$70,$60,$60,$00
; poison ($ee)
        .byte   $00,$10,$30,$38,$78,$7c,$5c,$7c
        .byte   $de,$fe,$fe,$fe,$7e,$7c,$3c,$00
; wind ($ef)
        .byte   $00,$00,$78,$7c,$0c,$04,$fa,$fc
        .byte   $0c,$00,$7c,$78,$3c,$00,$00,$00
; holy ($fb)
        .byte   $10,$10,$10,$18,$6c,$7c,$92,$fe
        .byte   $6e,$7c,$14,$18,$18,$10,$08,$00
; earth ($fc)
        .byte   $00,$00,$10,$10,$28,$38,$6c,$7c
        .byte   $4c,$7c,$ee,$fe,$fe,$fe,$7e,$00
; water ($fd)
        .byte   $00,$00,$30,$30,$4a,$7a,$4c,$4e
        .byte   $c6,$80,$7c,$7e,$7e,$7c,$3c,$00

