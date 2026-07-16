; ------------------------------------------------------------------------------
; OT6 — Octopath Traveler mechanics module
;
; All new code and data live in expanded bank $F0 (segment "ot6_code") and
; are reached from vanilla banks via jsl. Keep vanilla-bank edits to minimal
; hook shims so bank $C2 stays under its fixed segment offsets.
;
; per-entity state (unused vanilla battle RAM, zeroed by InitBattle):
;   $3e38,X  current shield points (0 = broken or shieldless)
;   $3e39,X  max shield points
;   $3e88,X  broken timer (nonzero = broken; ticks with status counters)
;   $3e89,X  revealed weakness elements (bitmask, same bits as $3be0)
;   $3e9c,X  boost points (characters only, 0-5)
;   $3e9d,X  pending boost for the next action (0-3)
; entity offsets: $00-$06 characters, $08-$12 monsters
; ------------------------------------------------------------------------------

OT6_BREAK_TICKS := $10          ; a bit under vanilla stop duration ($12)

.segment "ot6_code"

; width discipline: callers vary (battle init calls some hooks with 8-bit
; index registers!). every entry point either (a) uses only width-agnostic
; instructions — no index immediates, no pushes — or (b) does php + longi
; and restores. entity-offset checks use tya/cmp (width-neutral), never
; cpy #imm. a-width is 8-bit at every hook site (verified per site in the
; assembler listings).
.a8
.i16

; ------------------------------------------------------------------------------

; [ seed monster shields at battle init ]

; called from LoadRageProp just after the weak-elements load
; a8/i16, x = monster prop offset, y = entity offset, preserves x/y

.proc Ot6SeedShields
        .a8
        .i16
        tya                     ; entity offset, width-neutral test
        cmp     #$08
        bcc     done            ; rage load onto a character: no shields
        lda     f:MonsterProp+16,x
        lsr
        lsr
        lsr
        clc
        adc     #$02            ; shields = 2 + level / 8 ...
        cmp     #$07
        bcc     store
        lda     #$06            ; ... capped at 6
store:  sta     $3e38,y
        sta     $3e39,y
        ; weakness codex: stash this slot's species and pre-reveal
        ; anything already learned in past battles
        phx
        longa
        txa
        lsr
        lsr
        lsr
        lsr
        lsr                     ; monster prop offset / 32 = species id
        sta     OT6_SPECIES-8,y
        lda     f:OT6_CODEX_MAGIC
        cmp     #$364f          ; 'O6' - codex bank initialized?
        beq     @learned
        ; first use (or no sram bank): wipe the table, then sign it.
        ; without 32k sram the magic never sticks and the codex is a
        ; harmless no-op: reads return open bus, merges are junk-free
        ; because we only merge after the magic matches.
        shorta0
        ldx     #$0000
@wipe:  sta     f:OT6_CODEX,x
        inx
        cpx     #$0180          ; 384 species
        bcc     @wipe
        longa
        lda     #$364f
        sta     f:OT6_CODEX_MAGIC
        cmp     f:OT6_CODEX_MAGIC
        bne     @nosram         ; write didn't stick: no codex bank
@learned:
        ldx     OT6_SPECIES-8,y ; species -> learned weakness bits
        shorta0
        lda     f:OT6_CODEX,x
        ora     $3e89,y
        sta     $3e89,y
@nosram:
        shorta0
        plx
done:   rtl
.endproc

; ------------------------------------------------------------------------------

; [ chip shields on an elemental weakness hit ]

; called from the weak-element branch of CalcTargetDmg (match confirmed)
; a8/i16, y = target, $11a1 = attack elements, preserves x/y

.proc Ot6Chip
        .a8
        .i16
        tya                     ; entity offset, width-neutral test
        cmp     #$08
        bcc     done            ; characters have no shields
        lda     $3e88,y
        bne     done            ; already broken: no chip until recovery
        lda     $3be0,y
        and     $11a1
        pha                     ; matched weakness bits
        lda     $3e89,y
        eor     #$ff
        and     $01,s
        beq     merge           ; all matched bits already revealed
        pha                     ; newly revealed bits
        lda     #$15            ; "Weak against fire!" etc. ($15 + element)
        sta     $3401
        pla
@bit:   lsr
        bcs     merge           ; message index for the lowest new element
        inc     $3401
        bra     @bit
merge:  pla                     ; reveal all matched weaknesses
        ora     $3e89,y
        sta     $3e89,y
        ; learn it forever: codex entry = everything revealed so far
        ; (seed merged the old codex bits in, so this is monotonic)
        phx
        pha
        ldx     OT6_SPECIES-8,y
        pla
        sta     f:OT6_CODEX,x
        plx
        lda     $3e38,y
        beq     done            ; shieldless monster
        dec     a
        sta     $3e38,y
        bne     refresh
        lda     #OT6_BREAK_TICKS
        sta     $3e88,y         ; shields down: BREAK
refresh:
        jsr     Ot6BuildRowGlyphs
        jsr     Ot6PokeRedraw
done:   rtl
.endproc

; ------------------------------------------------------------------------------

; [ double damage against a broken target ]

; called at the join of the elemental damage block, i.e. for every hit
; a8/i16, y = target, $f0 = 16-bit damage, $f2 = heal flag

.proc Ot6BrokenDmg
        .a8
        .i16
        tya                     ; entity offset, width-neutral test
        cmp     #$08
        bcc     done
        lda     $3e88,y
        beq     done            ; not broken
        lda     $f2
        bne     done            ; healing/drain: don't double
        lda     $f1
        bmi     done            ; avoid 16-bit overflow (matches vanilla)
        asl     $f0
        rol     $f1
done:   rtl
.endproc

; ------------------------------------------------------------------------------

; [ combined stop-or-broken turn gate ]

; replaces the stop status check in the pending-action gate;
; caller branches on nonzero to skip the turn
; a8/i16, x = entity

.proc Ot6Gate
        .a8
        .i16
        lda     $3ef8,x
        bit     #$10
        bne     done            ; stop status: skip turn (z clear)
        lda     $3e88,x         ; broken: skip turn (z clear if nonzero)
done:   rtl
.endproc

; ------------------------------------------------------------------------------

; [ tick the broken timer, restore shields on recovery ]

; called from DecCounters once per entity status-tick
; a8/i16, x = entity, a is free (caller reloads)

.proc Ot6Tick
        .a8
        .i16
        lda     $3e88,x
        beq     done
        dec     $3e88,x
        bne     done
        lda     $3e39,x         ; recovered: shields back to max
        sta     $3e38,x         ; (revealed weaknesses stay revealed)
        jsr     Ot6BuildRowGlyphs
        jsr     Ot6PokeRedraw
done:   rtl
.endproc

; ------------------------------------------------------------------------------

; [ force the monster name window to redraw ]

; invalidates btlgfx's monster-name cache (w7eebff, first byte);
; the name window diff check picks it up on the next frame

.proc Ot6PokeRedraw
        .a8
        .i16
        dec     $ebff           ; db = $7e throughout battle code
        rts
.endproc

; ------------------------------------------------------------------------------

; [ rebuild the per-row shield glyphs for the monster name window ]

; one glyph per name row ($200d grouping): $ff blank, 'B' if any monster in
; the group is broken, else the lowest shield count in the group as a digit.
; row glyphs live at $3ecb,X (X = 0,2,4,6 matching the $200d row offsets).
; preserves x/y and caller register widths.

.proc Ot6BuildRowGlyphs
        .a8
        .i16
        php
        longi                   ; callers vary: battle init runs i8
        phx
        phy
        shorta
        ldx     #$0000
@row:   lda     #$ff            ; default: blank
        sta     $3ecb,x
        ldy     #$0000          ; monster slot offset ($00-$0a)
@slot:  lda     $3aa8,y
        lsr
        bcc     @next           ; monster not present
        lda     $3eec,y
        bit     #$c2
        bne     @next           ; dead, petrified, or zombie
        longa
        lda     $3388,y         ; monster name id
        cmp     $200d,x
        shorta
        bne     @next           ; not this row's group
        lda     $3e90,y         ; broken timer (monster tables = entity + 8)
        beq     @shield
        lda     #$81            ; 'B': broken beats any digit
        sta     $3ecb,x
        bra     @next
@shield:
        lda     $3e40,y         ; current shield points
        beq     @next           ; shieldless: leave blank
        cmp     #$0a
        bcc     :+
        lda     #$09
:       clc
        adc     #$b4            ; digit glyph ($b4 = '0')
        cmp     $3ecb,x
        bcs     @next           ; keep the smaller glyph ('B' or lower digit)
        sta     $3ecb,x
@next:  iny2
        cpy     #$000c
        bcc     @slot
        inx2
        cpx     #$0008
        bcc     @row
        ply
        plx
        plp
        rts
.endproc

; jsl wrapper for hooks in vanilla banks
.proc Ot6BuildRowGlyphsFar
        .a8
        .i16
        jsr     Ot6BuildRowGlyphs
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ shield glyph for the monster name row being drawn ]

; called from btlgfx MenuTextCmd_0b in place of the trailing blank;
; returns the glyph in a for DrawMenuLetter. ($48) still points at the
; row slot byte of the menu text string.

.proc Ot6ShieldGlyph_ext
        .a8
        .i16
        phx
        longa
        lda     ($48)
        and     #$0003
        asl
        tax
        shorta0
        lda     $3ecb,x
        plx
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
        jsr     Ot6LoadBgGlyphs ; hud glyphs into free font cells
        plb
        plp
        rtl
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

; strip scratch (free odd bytes between the row-glyph slots; battle-only)
OT6_SCR_SLOT2 := $3ecc          ; targeted monster offset (slot * 2)
OT6_SCR_BIT   := $3ece          ; walking element bit
OT6_SCR_IDX   := $3ed0          ; element index 0-7
OT6_SCR_COLS  := $3ed2          ; strip columns drawn so far

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

; element index -> tilemap palette bits (palette << 2)
Ot6ElemPalTbl:
        .byte   7 << 2          ; fire: red
        .byte   3 << 2          ; ice: blue
        .byte   2 << 2          ; lightning: yellow
        .byte   6 << 2          ; poison: green
        .byte   0 << 2          ; wind: white
        .byte   2 << 2          ; holy: yellow (star shape vs bolt zigzag)
        .byte   1 << 2          ; earth: gray
        .byte   3 << 2          ; water: blue (wave shape vs ice crystal)

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

; [ element glyph for an ability ]

; a = ability id (0-255) -> a = element icon glyph, or $ff if the ability
; has no element. first set element bit wins. preserves x/y.

.proc Ot6ElemGlyphFor
        .a8
        .i16
        phx
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
        beq     @none
        ldx     #$0000
@bit:   lsr
        bcs     @hit
        inx
        bra     @bit
@hit:   txa
        sta     OT6_SCR_COLS    ; element index, for palette selection
        lda     f:Ot6ElemGlyphTbl,x
        plx
        rts
@none:  lda     #$ff
        plx
        rts
.endproc

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


; ------------------------------------------------------------------------------

; [ seed boost points at battle start ]

; called from InitBattle after its ram clears. runs in longa/longi
; context (InitBattle's php/longai is still active) - widths pinned here.

.proc Ot6InitBP
        .a16
        .i16
        php
        shorta0
        lda     #$01
        sta     $3e9c           ; characters open with 1 bp, octopath-style
        sta     $3e9e
        sta     $3ea0
        sta     $3ea2
        ; clear the bg-hud shadow (prev addresses especially: garbage here
        ; would make the first flush erase random vram)
        longa
        clr_a
        phx
        ldx     #$0000
@clr:   sta     f:$7e0000+OT6_SHADOW,x
        inx
        inx
        cpx     #$005e          ; shadow, map base, dirty (+spare)
        bcc     @clr
        ldx     #$0000
@clr2:  sta     f:$7e0000+OT6_HUDCOPY,x
        inx
        inx
        cpx     #$0054          ; last-flushed copies
        bcc     @clr2
        sta     f:$7e0000+OT6_PIPCUR    ; live pip cell off, no stale erase
        sta     f:$7e0000+OT6_PIPPREV
        sta     f:$7e0000+OT6_LASTLR
        plx
        plp
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ bp bookkeeping at the end of an entity's action ]

; called just before EndAction once the actor has no pending actions.
; characters: consume the pending boost if one was spent, otherwise
; gain 1 bp (octopath's no-regen-after-boosting rule), capped at 5.
; a8/i16, x = actor entity offset, a free

.proc Ot6ActionEnd
        php                     ; caller width varies: pin our own
        longi
        shorta0
        .a8
        .i16
        txa                     ; width-neutral character test
        cmp     #$08
        bcs     done            ; monsters have no bp
        lda     $3e9d,x         ; pending boost spent this action?
        beq     @gain
        sta     OT6_SCR_BIT     ; consume it: bp -= pending
        lda     $3e9c,x
        sec
        sbc     OT6_SCR_BIT
        bcs     :+
        lda     #$00            ; (defensive clamp)
:       sta     $3e9c,x
        lda     #$00
        sta     $3e9d,x         ; no regen on a boosted turn
        bra     done
@gain:  lda     $3e9c,x
        cmp     #$05
        bcs     done            ; capped at 5
        inc
        sta     $3e9c,x
done:   plp
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ boost the base damage of a boosted character action ]

; called at the tail of the physical and magic base-damage calcs.
; damage x2/x3/x4 for pending boost 1/2/3; the per-target 9999 cap
; still applies downstream. a8/i16, x = attacker, 16-bit damage $11b0.

.proc Ot6BoostDmg
        php                     ; caller width varies: pin our own
        longi
        shorta0
        .a8
        .i16
        txa                     ; width-neutral character test
        cmp     #$08
        bcs     done            ; monsters never boost
        lda     $3e9d,x         ; pending boost level
        beq     done
        sta     OT6_SCR_BIT
        longa
        lda     $11b0
@mul:   asl                     ; not a true xN, but x2/x4/x8 reads better
        bcs     @cap            ; on 16-bit overflow, saturate
        shorta                  ; 8-bit dec: a 16-bit rmw would clobber
        dec     OT6_SCR_BIT     ; the row-glyph byte next door
        longa                   ; (rep/sep leave z alone; a survives)
        bne     @mul
        bra     @store
@cap:   lda     #$7fff
@store: sta     $11b0
        shorta0
done:   plp
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ upload the bg hud glyphs into free font cells ]

; 13 2bpp tiles (shield-with-count 1-6/B, pip clusters 0-5) written to
; the battle font at vram $5800 + cell*8. runs inside the font uploader
; (db = $00, forced blank).

.proc Ot6LoadBgGlyphs
        .a8
        .i16
        ldx     #$0000          ; glyph index
@tile:  phx
        lda     f:Ot6BgGlyphCellTbl,x
        longa
        and     #$00ff
        asl
        asl
        asl
        clc
        adc     #$5800
        sta     hVMADDL
        txa                     ; data offset = index * 16
        asl
        asl
        asl
        asl
        tax
        ldy     #$0008          ; 8 words per 2bpp tile
@word:  lda     f:Ot6BgGlyphData,x
        sta     hVMDATAL
        inx
        inx
        dey
        bne     @word
        shorta
        plx
        inx
        cpx     #$0010          ; 16 glyphs
        bcc     @tile
        rts
.endproc

; ------------------------------------------------------------------------------

; [ per-frame bg hud: rebuild the shadow line buffer ]

; the hud lives on the bg3 field tilemap; this main-loop pass fills a
; shadow buffer in bank $7f, and the nmi flush copies it to vram during
; vblank. shadow at $7f:fe00, 10 lines x 12 bytes:
;   +0  vram word address of the line's first cell (0 = line disabled)
;   +2  five tilemap words (glyph | attr << 8)
; monsters: [shield-with-count][up to 4 weakness slots]. heroes: one
; pip-cluster cell. entities animate and drift, so each line remembers
; its previous address; the flush blanks the old cells when it moves.
; line layout: +0 cur addr (0 = disabled), +2 prev addr, +4 five cells.

OT6_SHADOW  := $5762            ; lines, stride 14 (trace-verified free)
OT6_MAPBASE := $57b6            ; word scratch: field bg3 map base

.proc Ot6BgHud_ext
        .a8
        .i16
        php
        longi
        shorta0
        phx
        phy
        phb
        lda     #$7e
        pha
        plb
        ; field bg3 map base (word address) from the hdma-fed value
        longa
        lda     $897b
        and     #$00fc
        xba                     ; << 8 == (>>2) << 10
        sta     f:$7e0000+OT6_MAPBASE
        shorta0
        ldy     #$0000          ; monster slot offset
        ldx     #$0000          ; shadow byte offset
@slot:  jsr     Ot6BgHudLine
        longa
        txa
        clc
        adc     #$000e
        tax
        shorta0
        iny
        iny
        cpy     #$000c
        bcc     @slot
        jsr     Ot6Boost        ; l/r boost input + live pip cell
        plb
        ply
        plx
        plp
        rtl
.endproc

; one monster line. x = shadow line base (kept), y = monster slot offset.
.proc Ot6BgHudLine
        .a8
        .i16
        lda     $3aa8,y
        lsr
        bcs     @on
        ; monster gone: disable the line (flush blanks the old cells once)
        longa
        lda     #$0000
        sta     f:$7e0000+OT6_SHADOW,x
        shorta0
        rts
@on:    ; blank the five cell words, rebuild below. the anchor word at +0
        ; is only committed at the very end (and only once per battle):
        ; the NMI flush can fire mid-rebuild, so the enable is the commit.
        longa
        lda     #$21ff
        sta     f:$7e0000+OT6_SHADOW+4,x
        sta     f:$7e0000+OT6_SHADOW+6,x
        sta     f:$7e0000+OT6_SHADOW+8,x
        sta     f:$7e0000+OT6_SHADOW+10,x
        sta     f:$7e0000+OT6_SHADOW+12,x
        shorta0
        ; dead monsters: cells stay blank, line stays live (erases old art)
        lda     $3eec,y
        bit     #$c2
        jne     @done
        ; cell 0: shield-with-count
        lda     $3e90,y
        beq     @count
        lda     #$71            ; shield-B
        bra     @shld
@count: lda     $3e40,y
        beq     @slots          ; shieldless
        cmp     #$07
        bcc     :+
        lda     #$06
:       phx
        longa
        and     #$00ff
        tax
        shorta0
        lda     f:Ot6ShieldCellTbl-1,x
        plx
@shld:  sta     f:$7e0000+OT6_SHADOW+4,x
        ; weakness slots into cells 1-4
@slots: phx                     ; base on stack for the cap test
        lda     #$01
        sta     OT6_SCR_BIT
        lda     #$00
        sta     OT6_SCR_IDX     ; element index
@elem:  lda     OT6_SCR_BIT
        beq     @edone
        and     $3be8,y
        beq     @next
        inx
        inx                     ; claim the next cell
        txa
        sec
        sbc     $01,s           ; cells used so far (byte diff, same page)
        cmp     #$09
        bcs     @edone          ; past slot cell 4 (offsets +6..+12)
        lda     OT6_SCR_BIT
        and     $3e91,y
        beq     @q
        phx
        lda     OT6_SCR_IDX
        longa
        and     #$00ff
        tax
        shorta0
        lda     f:Ot6ElemGlyphTbl,x
        sta     $3ed3           ; scratch: glyph (strip's old slot, free)
        lda     f:Ot6ElemPalTbl,x
        ora     #$21
        plx
        sta     f:$7e0000+OT6_SHADOW+5,x
        lda     $3ed3
        sta     f:$7e0000+OT6_SHADOW+4,x
        bra     @next
@q:     lda     #$bf            ; '?', default attr already in place
        sta     f:$7e0000+OT6_SHADOW+4,x
@next:  asl     OT6_SCR_BIT
        inc     OT6_SCR_IDX
        bra     @elem
@edone: plx
@done:  ; commit: latch the anchor once per battle. monsters never move
        ; ("moving" coords are attack-animation transients that made the
        ; line jitter and blink), so compute only while still disabled.
        longa
        lda     f:$7e0000+OT6_SHADOW,x
        bne     @keep
        shorta0
        phx
        lda     $804b,y
        clc
        adc     #$07            ; first row fully past the monster's tile
        and     #$f8            ; box: monsters blink by redrawing their
                                ; own box, and an anchor rounded into its
                                ; last row flickers with every blink
        longa
        and     #$00ff
        asl
        asl                     ; row * 32
        clc
        adc     f:$7e0000+OT6_MAPBASE
        pha
        shorta0
        lda     $800f,y
        lsr
        lsr
        lsr
        dec
        longa
        and     #$00ff
        clc
        adc     $01,s
        plx                     ; (discard pushed row sum)
        plx                     ; restore shadow base
        phx
        sta     f:$7e0000+OT6_SHADOW,x  ; enable line (atomic word)
        plx
@keep:  shorta0
        rts
.endproc


; ------------------------------------------------------------------------------

; [ vblank flush: shadow lines -> bg3 field tilemap ]

; called from the battle nmi right after the oam dma.

OT6_HUDCOPY := $57de            ; (retired; kept for the memory map)
OT6_HUDDIRTY := $57b8           ; (retired)

; weakness codex: learned weaknesses persist across battles, octopath
; style. lives in the second 8k sram bank (header sram size $05), which
; vanilla save files never touch. species stash: one word per monster
; slot so Ot6Chip can find the codex entry at reveal time.
OT6_CODEX_MAGIC := $316000      ; word 'O6' = codex initialized
OT6_CODEX       := $316010      ; one revealed-elements byte per species
OT6_SPECIES     := $57c0        ; per-slot species stash (6 words)
OT6_PIPCUR      := $57cc        ; live pip cell: menu-map word addr (0=off)
OT6_PIPPREV     := $57ce        ; last flushed addr (for erase-on-move)
OT6_PIPCELL     := $57d0        ; glyph|attr word to write
OT6_LASTLR      := $57d2        ; last frame's L/R bits (edge detect)

.proc Ot6BgHudFlush_ext
        .a8
        .i16
        php
        longi
        shorta0
        phx
        phy
        phb
        clr_a
        pha
        plb                     ; db = 0 for hardware registers
        lda     #$80
        sta     hVMAINC
        ldx     #$0000
@line:  longa
        lda     f:$7e0000+OT6_SHADOW+2,x         ; prev
        beq     @write
        cmp     f:$7e0000+OT6_SHADOW,x           ; moved?
        beq     @write
        sta     hVMADDL                          ; blank the old cells
        lda     #$21ff
        sta     hVMDATAL
        sta     hVMDATAL
        sta     hVMDATAL
        sta     hVMDATAL
        sta     hVMDATAL
@write: lda     f:$7e0000+OT6_SHADOW,x
        sta     f:$7e0000+OT6_SHADOW+2,x         ; prev = cur
        tay
        beq     @skip
        sty     hVMADDL
        lda     f:$7e0000+OT6_SHADOW+4,x
        sta     hVMDATAL
        lda     f:$7e0000+OT6_SHADOW+6,x
        sta     hVMDATAL
        lda     f:$7e0000+OT6_SHADOW+8,x
        sta     hVMDATAL
        lda     f:$7e0000+OT6_SHADOW+10,x
        sta     hVMDATAL
        lda     f:$7e0000+OT6_SHADOW+12,x
        sta     hVMDATAL
@skip:  shorta0
        longa
        txa
        clc
        adc     #$000e
        tax
        shorta0
        cpx     #$0054          ; 6 monster lines x 14
        bcc     @line
        ; live pip pseudo-line: one cell in the menu map (active char's
        ; spendable bp during boost select). tiny, runs every nmi.
        ; the party window is double-buffered: each name row is staged at
        ; map row 1+2r AND at 9+2r (+$100 words), and the window scroll
        ; picks a band (the active character's visible copy is the yellow
        ; one). paint BOTH so the live cell shows no matter which band is
        ; on screen (writing only the low band made boost feedback
        ; invisible whenever the high band was up).
@pip:   longa
        lda     f:$7e0000+OT6_PIPPREV
        beq     @cur
        cmp     f:$7e0000+OT6_PIPCUR
        beq     @cur
        sta     hVMADDL                  ; moved/closed: blank the old cell
        lda     #$21ff
        sta     hVMDATAL
        lda     f:$7e0000+OT6_PIPPREV
        clc
        adc     #$0100                   ; ...and its band twin
        sta     hVMADDL
        lda     #$21ff
        sta     hVMDATAL
@cur:   lda     f:$7e0000+OT6_PIPCUR
        sta     f:$7e0000+OT6_PIPPREV
        beq     @pdone
        sta     hVMADDL
        lda     f:$7e0000+OT6_PIPCELL
        sta     hVMDATAL
        lda     f:$7e0000+OT6_PIPCUR
        clc
        adc     #$0100
        sta     hVMADDL
        lda     f:$7e0000+OT6_PIPCELL
        sta     hVMDATAL
@pdone: shorta0
@out:   plb
        ply
        plx
        plp
        rtl
.endproc

; [ bp pip refresh: redraw the name rows when spendable bp changes ]

; called from UpdateCharText every main-loop frame. skips while the
; battle menu text is not up yet (same gate vanilla uses for hp/mp).

; [ l/r boost input + live pip feedback ]

; runs every main-loop frame from the hud builder (db=$7e, a8/i16).
; while a battle menu is open, R raises the active character's pending
; boost (cap 3, and never past their bp) and L lowers it. the pips by
; the party names show spendable bp (bp - pending), so feedback is
; immediate: the flush's one-cell pseudo-line repaints the active row's
; pip cell straight into the menu tilemap. window_open re-stages every
; row on the next open, cleaning up any transient state.

.proc Ot6Boost
        .a8
        .i16
        lda     $7bca           ; battle menu open?
        jeq     @off
        ; edge-detect L/R from the held-buttons byte
        lda     $0a
        and     #$30            ; held L/R bits
        sta     OT6_LASTLR+1    ; scratch: held ($57d3)
        eor     OT6_LASTLR      ; changed since last frame
        and     OT6_LASTLR+1    ; & held = newly pressed
        pha
        lda     OT6_LASTLR+1
        sta     OT6_LASTLR      ; remember for next frame
        ; active character -> entity offset in y
        lda     $62ca
        longa
        and     #$0003
        asl
        tay
        shorta0
        pla
        bit     #$10            ; R: boost up
        beq     @tryl
        lda     $3e9d,y
        inc     a
        cmp     #$04            ; spend at most 3
        bcs     @deny
        cmp     $3e9c,y         ; and never more than current bp
        beq     @store
        bcs     @deny
@store: sta     $3e9d,y
        inc     $6281           ; ching (spc $2c): boost committed
        bra     @show
@deny:  inc     $95             ; error buzz: at cap or out of bp
        bra     @show
@tryl:  bit     #$20            ; L: boost down
        beq     @show
        lda     $3e9d,y
        beq     @show
        dec     a
        sta     $3e9d,y
        inc     $94             ; cursor click: boost taken back
@show:  ; live pip cell for the active character's menu row
        lda     $62ca
        ldx     #$0000
@row:   cmp     $64d6,x         ; find the menu row showing this slot
        beq     @found
        inx
        cpx     #$0004
        bcc     @row
        bra     @off            ; not on screen: disable the pseudo-line
@found: ; map word = $7800 + (1 + row*2)*32 + 20
        longa
        txa
        asl                     ; row*2
        inc     a               ; +1
        asl
        asl
        asl
        asl
        asl                     ; *32
        clc
        adc     #$7814          ; $7800 + 20
        sta     f:$7e0000+OT6_PIPCUR
        shorta0
        ; glyph: pending boost -> arrow cluster pulsing yellow/white
        ; (the loud "you are boosting" signal); else spendable pips
        lda     $3e9d,y
        beq     @pips
        longa
        and     #$00ff
        tax
        shorta0
        lda     f:Ot6ArrowCellTbl-1,x
        sta     f:$7e0000+OT6_PIPCELL
        lda     $0e             ; frame counter: pulse every 8 frames
        and     #$08            ; palette 2 (yellow) <-> 0 (white)
        ora     #$21
        sta     f:$7e0000+OT6_PIPCELL+1
        rts
@pips:  lda     $3e9c,y         ; pip cluster for spendable bp
        sec
        sbc     $3e9d,y
        bcs     :+
        lda     #$00
:       cmp     #$06
        bcc     :+
        lda     #$05
:       longa
        and     #$00ff
        tax
        shorta0
        lda     f:Ot6PipCellTbl,x
        sta     f:$7e0000+OT6_PIPCELL
        lda     #$21
        sta     f:$7e0000+OT6_PIPCELL+1
        rts
@off:   longa
        lda     #$0000
        sta     f:$7e0000+OT6_PIPCUR
        shorta0
        rts
.endproc

; [ bp pip glyph for the party window name row ]

; menu text command $13, reached from template $01 (character names) only.
; +$4a = staging pointer w7e5b95 + row*28, so the menu row is recoverable
; without trusting any earlier command's state. empty rows draw blank.

.proc Ot6PipGlyph_ext
        .a8
        .i16
        phx
        longa
        lda     $4a             ; staging base for this row
        sec
        sbc     #$5b95
        shorta                  ; keep a: row*28 fits in 8 bits (0/28/56/84)
        ldx     #$0000
:       cmp     #$1c            ; /28 -> menu row
        bcc     :+
        sbc     #$1c
        inx
        bra     :-
:       lda     f:$7e64d6,x     ; menu row -> character slot
        cmp     #$ff
        beq     @blank
        asl                     ; slot -> entity offset
        longa
        and     #$0006
        tax
        shorta0
        lda     f:$7e3e9c,x     ; bp
        sec
        sbc     f:$7e3e9d,x     ; minus pending
        bcs     :+
        lda     #$00
:       cmp     #$06
        bcc     :+
        lda     #$05
:       longa
        and     #$00ff
        tax
        shorta0
        lda     f:Ot6PipCellTbl,x
        plx
        rtl
@blank: lda     #$ff
        plx
        rtl
.endproc

; shield-with-count glyph cells (counts 1-6)
Ot6ShieldCellTbl:
        .byte   $65,$66,$67,$69,$6a,$6b

; pip cluster cells (0-5 filled)
Ot6PipCellTbl:
        .byte   $72,$73,$75,$76,$77,$79

; boost arrow cells (pending 1-3)
Ot6ArrowCellTbl:
        .byte   $68,$6c,$6d

; bg hud glyph cells (2bpp, verified junk-free in both formations —
; probe_cells.lua rechecks candidates idle + post-action)
Ot6BgGlyphCellTbl:
        .byte   $65
        .byte   $66
        .byte   $67
        .byte   $69
        .byte   $6a
        .byte   $6b
        .byte   $71
        .byte   $72
        .byte   $73
        .byte   $75
        .byte   $76
        .byte   $77
        .byte   $79
        .byte   $68
        .byte   $6c
        .byte   $6d

Ot6BgGlyphData:
; shield-1
        .byte   $7e,$00,$91,$7e,$b1,$7e,$91,$7e
        .byte   $52,$3c,$3c,$38,$18,$00,$00,$00
; shield-2
        .byte   $7e,$00,$b1,$7e,$89,$7e,$91,$7e
        .byte   $62,$3c,$3c,$38,$18,$00,$00,$00
; shield-3
        .byte   $7e,$00,$b1,$7e,$89,$7e,$91,$7e
        .byte   $4a,$3c,$34,$38,$18,$00,$00,$00
; shield-4
        .byte   $7e,$00,$a9,$7e,$a9,$7e,$b9,$7e
        .byte   $4a,$3c,$2c,$18,$18,$00,$00,$00
; shield-5
        .byte   $7e,$00,$b9,$7e,$a1,$7e,$b1,$7e
        .byte   $4a,$3c,$3c,$38,$18,$00,$00,$00
; shield-6
        .byte   $7e,$00,$99,$7e,$a1,$7e,$b9,$7e
        .byte   $6a,$3c,$3c,$38,$18,$00,$00,$00
; shield-B
        .byte   $7e,$00,$b1,$7e,$a9,$7e,$b1,$7e
        .byte   $6a,$3c,$34,$38,$18,$00,$00,$00
; pips-0
        .byte   $00,$00,$db,$00,$db,$00,$00,$00
        .byte   $6c,$00,$6c,$00,$00,$00,$00,$00
; pips-1
        .byte   $00,$00,$db,$c0,$db,$c0,$00,$00
        .byte   $6c,$00,$6c,$00,$00,$00,$00,$00
; pips-2
        .byte   $00,$00,$db,$d8,$db,$d8,$00,$00
        .byte   $6c,$00,$6c,$00,$00,$00,$00,$00
; pips-3
        .byte   $00,$00,$db,$db,$db,$db,$00,$00
        .byte   $6c,$00,$6c,$00,$00,$00,$00,$00
; pips-4
        .byte   $00,$00,$db,$db,$db,$db,$00,$00
        .byte   $6c,$60,$6c,$60,$00,$00,$00,$00
; pips-5
        .byte   $00,$00,$db,$db,$db,$db,$00,$00
        .byte   $6c,$6c,$6c,$6c,$00,$00,$00,$00
; boost-1: one fat right arrow
        .byte   $00,$00,$20,$20,$30,$30,$38,$38
        .byte   $3c,$3c,$38,$38,$30,$30,$00,$00
; boost-2: two medium arrows
        .byte   $00,$00,$00,$00,$88,$88,$cc,$cc
        .byte   $ee,$ee,$cc,$cc,$88,$88,$00,$00
; boost-3: three narrow arrows
        .byte   $00,$00,$00,$00,$92,$92,$db,$db
        .byte   $db,$db,$92,$92,$00,$00,$00,$00
