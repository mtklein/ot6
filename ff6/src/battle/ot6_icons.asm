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

; ------------------------------------------------------------------------------

; [ #53: the same eight element tiles, in the FIELD MENU's font ]

; Until now these tiles existed only in the BATTLE font.  Ot6LoadFontIcons_ext
; above uploads them to vram word $5800 from LoadMenuGfx (btlgfx_main.asm:8911),
; which is the battle graphics path and runs nowhere else -- so a field page
; asking for an element glyph drew whatever occupied that cell of the menu's own
; font, and #46 could only give the Blitz page CLASS glyphs, which ship in the
; vanilla font art itself (the Ot6ClassGlyphTbl note below).  Five of the eight
; Blitzes therefore showed nothing, three of them elemental probes.
;
; WHERE THE MENU'S FONT IS -- and it is TWO copies, neither at $5800:
;   * LoadFontGfx2bpp (menu_gfx.asm:120) lays 256 2bpp tiles at word $6000,
;     BG2/BG3's char base (hBG34NBA = $66, menu_init_2.asm:435);
;   * LoadFontGfx4bpp (:139) expands the SAME source art into 4bpp tiles at
;     word $5000, BG1's char base (hBG12NBA = $65, :433), with the upper two
;     bitplanes zeroed.
; Every field ability page draws through GetBG1TilemapPtr, i.e. BG1, so the
; $5000 copy is the one the Blitz page reads.  The $6000 copy is patched too
; because BG3A carries menu text as well (config.asm:2044, colosseum.asm:328).
;
; FREE SPACE, measured rather than assumed: gfx/small_font_en.2bpp is 4096
; bytes / 256 tiles, and cells $00-$7f, $d0-$d1, $eb-$ef and $fb-$ff are
; sixteen zero bytes each.  So all eight cells Ot6ElemGlyphTbl names above
; ($eb $ec $ed $64 $ef $fb $fc $fd) are blank in the field font exactly as
; they are in the battle one, and the menu text codec cannot even spell them
; (small_symbols_en.json stops at $ea and resumes at $f0; text_en.json's
; letters start at $80).  NOTHING had to move to make room, and both loops
; below write strictly inside the range the vanilla loader just blanked --
; they cannot step outside the font.
;
; WHAT IT COSTS, per menu OPEN: eight tiles.  The 4bpp pass writes 8 data
; words + 8 zero words each = 128 word writes; the 2bpp pass 8 each = 64.
; The font expansions they hang off write 4096 and 3072 words respectively
; (and LoadFontGfx4bpp then streams 2048 more for WindowGfx before our hook
; runs at all), so this is +3.1% and +2.1% of an upload already happening --
; +2.1% of LoadFontGfx4bpp end to end.  All of it in the same forced-blank
; menu init (InitMenu -> InitMenuGfx, menu_common.asm:133), before a frame is
; shown.  No re-lay machinery is needed: unlike the battle font -- which a
; dialogue window re-uploads mid-fight, the whole reason Ot6FontRestoreMark
; and OT6_FONTDIRTY exist above -- nothing rewrites the menu font while a menu
; is open.  Hence two plain entry points and no nmi slicing.
;
; TWO entry points rather than one that does both, deliberately: menu types 1
; and 6 (name change, SwdTech rename) call LoadFontGfx4bpp WITHOUT
; LoadFontGfx2bpp (menu_gfx.asm:52,108), so a single proc writing $6000 as
; well would scribble into whatever else those types put there.  Each entry
; patches only the copy the loader it hangs off has just laid down.
;
; ------------------------------------------------------------------------------
; WHICH FIELD SURFACES USE THEM, and why the ones that do not, do not.
;
; #53 asked for the Blitz page and then for every sibling to be CHECKED rather
; than left inconsistent -- this window family has already cost four rounds of
; fixes that way.  All of them were.  The Blitz page draws the icon
; (Ot6BlitzPageDraw, skills.asm); the rest are rulings, each with the
; measurement that produced it, so the next agent re-reads the number instead
; of re-deriving the question:
;
;   SwdTech (Skills -> SwdTech, the loadout page, field_menu.asm).  NO, and
;   the issue's premise for it is false.  "Several SwdTech are elemental" is
;   not true of this ROM: magic_prop_en.dat's element byte (record +1) is $00
;   for ALL EIGHT of $55-$5c, and Ot6SkillClassTbl gives all eight OT6_SLASH
;   (ot6_class.asm:185-192).  An icon column there would therefore print the
;   identical sword glyph on all eight rows -- eight copies of one fact, which
;   is the definition of chrome.  It also has nowhere to print it: the three
;   slot rows are the one page in this window whose columns are fully spent
;   (the #56 budget note over Ot6LoadoutDrawSlots costs the row at 28 cells
;   wanted against 27 available and pays for it by deleting a gap).  If a
;   SwdTech ever gains an element, the pool grid -- not the slot rows -- has
;   the free cells: 15 for the left column, 29 for the right.
;
;   Rage (Skills -> Rage, the loadout page).  NO, and this one has no
;   authority to read at all, which is the decisive form of no.  A Rage row
;   names a MONSTER (MonsterName, 10 cells), and the actions it grants are
;   that monster's own two attacks -- so "the element of a Rage" is not one
;   value, and nothing in the tree defines it.  An assertion here could not
;   read the icon out of the ROM the way #53 requires, because there is no
;   such row in any table.  (Geometry was not the blocker: columns 13-15 and
;   26-29 are free on that page.)
;
;   Magic / Lore (Skills -> Magic, the vanilla two-column list).  NOT DONE,
;   and the only one of these that is a genuine gap rather than a ruling --
;   spells DO carry elements, and the BATTLE Magic list already shows them
;   (Ot6AbilityPad_ext).  Three reasons it is filed and not done here: it is
;   vanilla's shared row drawer (_c34fc4, skills.asm:867) with several
;   callers, not an OT6 page; the field magic page has no render test to fail
;   first against; and every MagicName record ALREADY opens with a school
;   glyph ({black}/{white}/{effect}, magic_name_en.json), so a second icon per
;   row is a design question about two glyphs, not a mechanical copy of the
;   Blitz page.  Room exists when it is answered: the row is a 7-cell name +
;   blank + 2 digits at columns 3 and 16, leaving 13-15 and 26-29.
;
;   Esper detail (Skills -> Espers -> a stone).  NOT DONE, same shape as
;   Magic: the spells a stone grants have elements, the names are drawn at
;   column 5, and #62 has just taken columns 17-27 for the while-worn stat
;   block.  Filed with Magic -- they are one decision, and both are cheap now
;   that the tiles are in the font, which is what "available to" meant.

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
:       stz     hVMDATAL        ; bitplanes 2/3: the art is 2bpp, exactly as
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

; the two halves both passes share, so the pair differs ONLY in the vram base
; and the tile stride -- the one thing that genuinely differs between a 4bpp
; and a 2bpp copy of the same art.  Both read the SAME two tables the battle
; upload reads, so no third opinion about which cell an element owns can appear.

; x = icon index -> a = its font cell code.  a16 throughout (the high byte of
; the word read is the NEXT table entry, and is masked off); x preserved.
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

; ------------------------------------------------------------------------------

; [ #53: the same element-or-class glyph, callable from the MENU bank ]

; The field pages want exactly what Ot6ElemGlyphFor decides -- element first,
; the ability's break class when it has none, blank when it has neither -- and
; they must not get a second opinion about it.  #46 could not call it and wrote
; Ot6SkillClassGlyph (then in ot6_kits.asm, deleted in v0.9) instead for two reasons, both now gone: the
; element glyphs did not exist in the field font (the upload above), and
; Ot6ElemGlyphFor is an rts leaf.  This is the rtl wrapper; the CLASS-only leaf
; is retired, so there is one glyph authority for both halves of the game.
;
; WHY IT SAVES A BYTE OF RAM.  Ot6ElemGlyphFor reports its palette index by
; storing OT6_SCR_COLS ($3ed2) -- battle-only scratch, and in the FIELD MENU
; that address is inside wBG1Tiles::ScreenA ($7e3849 + $0800, menu_ram.inc:458):
; $3ed2 is the attribute byte of row 26, column 4 of the tilemap shadow.  A
; stray write there would be invisible on screen (row 26 is outside this
; window and its char byte stays $00, the blank tile) and, being an ATTRIBUTE
; byte, invisible to menu_blitzpage.lua's row canary too, which reads char
; bytes only.  That is precisely the kind of silent write this project does not
; leave lying around, so the byte is saved and put back.  The menu needs no
; palette index at all: a field icon draws in its row's text colour, exactly as
; #46's class glyphs already did.
;
; db is forced to $7e so that store lands where the battle path puts it rather
; than in bank $00 open bus -- menu-bank callers run with db = $00.
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

