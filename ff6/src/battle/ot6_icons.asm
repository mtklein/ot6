; ------------------------------------------------------------------------------

; [ a battle dialogue clobbered our font cells; restore, then flag a re-lay ]

; called from _c143b9 (dialogue close, small-font restore) in bank C1 in
; TAIL position, with WaitTfrVRAM's parameters live in the registers
; (A = source bank, X = source, Y = vram dest, $10 = size). we pass them
; straight through to the vanilla staged restore — WaitTfrVRAM streams
; $400 bytes per frame and returns only after the LAST chunk has landed
; in vram — and only THEN raise OT6_FONTDIRTY so the battle nmi re-lays
; our icons over a fully-restored font (in vblank, where direct vram
; writes actually land). the re-lay is STAGED: OT6_FONTDIRTY counts
; stages remaining, and the nmi flush runs one ~128-byte slice per
; frame — the whole 768-byte re-lay measured ~46 scanlines of PIO,
; more than an entire vblank, so a single-shot re-lay tore the frame
; (probe_banner measured end-of-flush at scanline 292 of 262).
;
; both halves of the restore-then-flag ordering are the whelk
; garbled-menu bug fix (battle_dlgmenu is the regression gate):
;   * the first cut of this shim ran BEFORE the jmp WaitTfrVRAM and
;     clobbered A with the flag value, so the "restore" streamed $1000
;     bytes of bank-$01 open bus over the font and every battle menu
;     after a scripted dialogue rendered as noise;
;   * raising the flag BEFORE the restore let the nmi re-lay fire
;     between restore chunks, and the later chunks squashed the icons
;     right back to vanilla (the original icons-vanish symptom).

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
; screen borders) — filling those cells paints garbage at the edges. every
; cell below was verified unreferenced in the battle tilemap regions.
;
; the upload is split into three ~128-byte slices so the nmi flush can
; re-lay the font one slice per vblank after a battle dialogue (the
; whole 384 bytes as PIO measured ~23 scanlines — more than a vblank).
; this entry point runs ALL slices back to back: it is only called in
; forced blank (battle init), where budget is unlimited.
;
; (was six slices: three more uploaded the over-character boost-mark OBJ
;  tiles, retired because they sat in vanilla's damage-numeral vram —
;  see the block comment where Ot6BoostMarksNmi_ext used to live.)

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
        .byte   $64             ; poison ($ee is vanilla's border junk fill!)
        .byte   $ef             ; wind
        .byte   $fb             ; holy
        .byte   $fc             ; earth
        .byte   $fd             ; water

OT6_QMARK := $bf                ; '?' glyph (unrevealed weakness slot)

; battle-only scratch (unused vanilla ram $3ecb-$3ed3, ours since m1)
                                ; OT6_DIVINE_USED is the per-character
                                ; once-per-battle divine latch
                                ;   (----1234, the $3f2f "desperation used"
                                ;   precedent): bit set = that character has
                                ;   spent their kit-8 divine this battle. lives
                                ;   in the retired row-glyph buffer byte (the
                                ;   ONE byte of the $3ecb-$3ed3 scratch range
                                ;   the OT6_SCR walkers never touch -- they own
                                ;   $3ecc-$3ed3 as words). InitBattle's
                                ;   $3a20-$3ed3 clear zeroes it on every fresh
                                ;   battle, and a Cmd_20 scene-change reload
                                ;   (which skips that clear) deliberately keeps
                                ;   it -- a multi-phase boss is ONE battle, so a
                                ;   divine spent in phase 1 stays spent. NOT
                                ;   $3f2f itself: vanilla's low-HP fight trigger
                                ;   still writes that byte (battle_main.asm:3432
                                ;   tsb $3f2f), so a random desperation would
                                ;   otherwise lock a divine out.
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
        lda     OT6_SCR_BIT     ; glyph, or $ff = blank: ALWAYS draw, so the
        longa                   ; icon column can never go stale on reused
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
; exactly how the same icons render as item-name leading glyphs
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
; shares. only the TOOLS window decorates ($7bc2 holds menu state $2e
; for every row it stages): item/throw/equip rows already wear a
; weapon's class as the leading name icon, and a second copy there
; would be noise — but tools keep their vanilla wrench icons ✦, so the
; class rides after the name, exactly where abilities show theirs.
; the icon replaces the name field's trailing blank (the field is
; always fully rewritten by the name loop, so the column can never go
; stale); a full 13-char name has no blank and keeps all its letters —
; autocrossbow, by the same rule that trims 10-char ability names in
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
        cmp     #$00            ; RETEST. plx sets n/z from the value it
                                ; PULLED, so the two guards below were reading
                                ; the caller's restored x — never the class
                                ; byte. x is ListTextCmd_0e's ItemName cursor
                                ; (id*13 + 13), nonzero and positive for every
                                ; item, so both guards fell through on a
                                ; CLASSLESS tool and @bit spun on a zero
                                ; OT6_SCR_BIT forever — a hard lock, measured
                                ; at $F0:057D with the battle nmi's $98
                                ; frozen. see battle_vargas.lua proof 3.
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

; [ element glyph for an ability — or its weapon-class glyph ]

; a = ability id (0-255) -> a = element icon glyph, or the ability's
; CLASS icon glyph when it has no element (Ot6SkillClassTbl: physical
; skills wear their class exactly where spells wear their element —
; TekMissile shows pierce in the magitek list, Pummel bludgeon, quadra
; slam slash), or $ff for the classless-and-elementless rest. first set
; bit wins on both axes; an element always beats the class (the design:
; "consult the class when the ability has no element"). null-break rows
; would advertise a class they never chip, so bit 7 hides the icon too.
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

; class bit index (slash 0 .. special 3) -> small font glyph. these four
; cells ship IN the vanilla small font (they are the item icons the m3
; weapon renames lean on), so unlike the element icons they need no
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

