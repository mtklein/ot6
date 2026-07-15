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
        jsr     Ot6LoadObjTiles ; enemy-hud sprite tiles ride the same blank
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
; obj tile vram word addresses (16 tiles, order: 8 icons, ?, B, digits 1-6)
Ot6ObjTileAddrTbl:
        .word   $3000          ; tile $100
        .word   $3020          ; tile $102
        .word   $3040          ; tile $104
        .word   $3200          ; tile $120
        .word   $3220          ; tile $122
        .word   $3240          ; tile $124
        .word   $3400          ; tile $140
        .word   $3420          ; tile $142
        .word   $3440          ; tile $144
        .word   $3600          ; tile $160
        .word   $3620          ; tile $162
        .word   $2c00          ; tile $0c0
        .word   $2c20          ; tile $0c2
        .word   $2c40          ; tile $0c4
        .word   $2c60          ; tile $0c6
        .word   $2c80          ; tile $0c8

; oam tile numbers matching the table above (low byte + name bit)
Ot6ObjTileNumTbl:
        .byte   $00, $01
        .byte   $02, $01
        .byte   $04, $01
        .byte   $20, $01
        .byte   $22, $01
        .byte   $24, $01
        .byte   $40, $01
        .byte   $42, $01
        .byte   $44, $01
        .byte   $60, $01
        .byte   $62, $01
        .byte   $c0, $00
        .byte   $c2, $00
        .byte   $c4, $00
        .byte   $c6, $00
        .byte   $c8, $00

; 4bpp tile data, 32 bytes each
Ot6ObjTiles:
        .byte   $00,$00,$08,$08,$04,$04,$10,$10
        .byte   $10,$10,$10,$10,$02,$00,$3c,$00
        .byte   $00,$10,$00,$30,$00,$38,$00,$6c
        .byte   $00,$6e,$00,$ee,$02,$7c,$3c,$00
        .byte   $10,$00,$38,$28,$7c,$10,$fe,$10
        .byte   $7e,$10,$3c,$28,$18,$00,$08,$00
        .byte   $00,$10,$00,$10,$00,$6c,$00,$ee
        .byte   $02,$6c,$04,$10,$08,$10,$08,$00
        .byte   $00,$1e,$04,$38,$08,$70,$00,$fc
        .byte   $24,$18,$08,$30,$10,$60,$40,$00
        .byte   $00,$1e,$04,$38,$08,$70,$00,$fc
        .byte   $24,$18,$08,$30,$10,$60,$40,$00
        .byte   $10,$10,$38,$38,$7c,$7c,$7c,$7c
        .byte   $fe,$fe,$fe,$fe,$7e,$7c,$3c,$00
        .byte   $00,$00,$00,$30,$00,$78,$00,$5c
        .byte   $00,$de,$00,$fe,$02,$7c,$3c,$00
        .byte   $00,$00,$04,$04,$08,$00,$06,$04
        .byte   $04,$00,$00,$00,$18,$00,$00,$00
        .byte   $00,$00,$78,$78,$0c,$04,$fa,$f8
        .byte   $04,$00,$7c,$7c,$18,$00,$00,$00
        .byte   $10,$00,$18,$08,$7c,$10,$fe,$6c
        .byte   $7e,$10,$1c,$08,$18,$00,$08,$00
        .byte   $10,$10,$10,$10,$6c,$6c,$92,$92
        .byte   $6e,$6c,$14,$10,$18,$10,$08,$00
        .byte   $00,$00,$00,$10,$10,$38,$10,$7c
        .byte   $30,$7c,$10,$fe,$00,$fe,$7e,$00
        .byte   $00,$00,$10,$10,$28,$28,$6c,$6c
        .byte   $4c,$4c,$ee,$ee,$fe,$fe,$7e,$00
        .byte   $00,$00,$30,$30,$7a,$7a,$4e,$4e
        .byte   $c6,$80,$7e,$7e,$7e,$7c,$3c,$00
        .byte   $00,$00,$30,$30,$4a,$4a,$4c,$4c
        .byte   $c6,$80,$7c,$7c,$7e,$7c,$3c,$00
        .byte   $3e,$00,$7f,$00,$47,$00,$0e,$00
        .byte   $1c,$00,$18,$00,$1c,$00,$1c,$00
        .byte   $02,$00,$39,$00,$41,$00,$02,$00
        .byte   $04,$00,$18,$00,$04,$00,$1c,$00
        .byte   $fe,$00,$ff,$00,$e7,$00,$fe,$00
        .byte   $e7,$00,$e7,$00,$fe,$00,$fc,$00
        .byte   $02,$00,$39,$00,$21,$00,$02,$00
        .byte   $21,$00,$21,$00,$02,$00,$fc,$00
        .byte   $38,$00,$78,$00,$78,$00,$38,$00
        .byte   $38,$00,$38,$00,$7c,$00,$7c,$00
        .byte   $08,$00,$08,$00,$48,$00,$08,$00
        .byte   $08,$00,$08,$00,$04,$00,$7c,$00
        .byte   $7e,$00,$ff,$00,$c7,$00,$0e,$00
        .byte   $3c,$00,$70,$00,$ff,$00,$ff,$00
        .byte   $02,$00,$79,$00,$c1,$00,$02,$00
        .byte   $0c,$00,$10,$00,$01,$00,$ff,$00
        .byte   $ff,$00,$fe,$00,$1c,$00,$3e,$00
        .byte   $3f,$00,$87,$00,$fe,$00,$7c,$00
        .byte   $01,$00,$f2,$00,$04,$00,$02,$00
        .byte   $39,$00,$01,$00,$82,$00,$7c,$00
        .byte   $1e,$00,$3e,$00,$6e,$00,$ce,$00
        .byte   $ce,$00,$ff,$00,$ff,$00,$0c,$00
        .byte   $02,$00,$12,$00,$22,$00,$42,$00
        .byte   $42,$00,$01,$00,$f3,$00,$0c,$00
        .byte   $ff,$00,$fe,$00,$fe,$00,$ff,$00
        .byte   $07,$00,$e7,$00,$7e,$00,$7c,$00
        .byte   $01,$00,$3e,$00,$02,$00,$f9,$00
        .byte   $01,$00,$61,$00,$02,$00,$7c,$00
        .byte   $3e,$00,$7c,$00,$e0,$00,$fe,$00
        .byte   $ff,$00,$e7,$00,$7e,$00,$7c,$00
        .byte   $02,$00,$1c,$00,$20,$00,$02,$00
        .byte   $39,$00,$21,$00,$02,$00,$7c,$00

; ------------------------------------------------------------------------------

; [ upload obj tiles for the enemy hud ]

; 16 sprites' top-left 8x8 quadrants (the other three quadrants of each
; 16x16 are verified-blank vram). called from the font-icon uploader
; while the screen is force-blanked and db = $00.

.proc Ot6LoadObjTiles
        .a8
        .i16
        ldx     #$0000          ; table index * 2
@tile:  longa
        lda     f:Ot6ObjTileAddrTbl,x
        sta     hVMADDL
        txa
        asl
        asl
        asl
        asl
        phx
        tax                     ; data offset = index * 32
@word:  lda     f:Ot6ObjTiles,x
        sta     hVMDATAL
        inx
        inx
        txa
        and     #$001f
        bne     @word           ; tiles are 32 bytes: stop on alignment
        shorta
        plx
        inx
        inx
        cpx     #$0020          ; 16 tiles done?
        bcc     @tile
        rts                     ; jsr-called from the font uploader
.endproc

; ------------------------------------------------------------------------------

; [ per-frame enemy hud: shield digit + weakness slots under each monster ]

; claims oam shadow entries 96-127 ($0480-$04ff, high-table bytes
; $0518-$051f). for each living monster: [shield digit or B] then one
; slot per weak element (icon if revealed, ? if not), anchored under the
; monster sprite. called from DrawCursorSprites every battle frame.
; db = $7e. entries beyond the claimed 32 are simply not drawn.

OT6_OAM   := $0480              ; oam shadow, entry 96
OT6_OAMHI := $0518              ; high table bytes for entries 96-127

.proc Ot6EnemyHud_ext
        .a8
        .i16
        php
        longi
        shorta0                 ; b = 0: tax/tay below stay clean
        phx
        phy
        phb                     ; caller's db is NOT $7e here (bank 0):
        lda     #$7e            ; battle vars and coords need bank $7e
        pha
        plb
        ldx     #$0000          ; own obj palette 3 outright: effects repaint
        longa                   ; it, so rewrite all 16 colors every frame
@hue:   lda     f:Ot6HudPal,x
        sta     $7f60,x
        inx
        inx
        cpx     #$0020
        bcc     @hue
        shorta0                 ; back to a8 AND rescrub b for tax below
        ldx     #$0000          ; hide all 32 claimed entries
@park:  lda     #$e0
        sta     OT6_OAM+1,x
        inx
        inx
        inx
        inx
        cpx     #$0080
        bcc     @park
        ldx     #$0000          ; clear high bits (x8=0, size=16x16)
@hibit: stz     OT6_OAMHI,x
        inx
        cpx     #$0008
        bcc     @hibit
        ldx     #$0000          ; x = oam byte offset within our block
        ldy     #$0000          ; y = monster slot offset (0,2,..,$0a)
@slot:  lda     $3aa8,y
        lsr
        bcc     @next           ; not present
        lda     $3eec,y
        bit     #$c2
        bne     @next           ; dead/petrified/zombie
        ; pen anchor: under the monster, roughly centered
        lda     $800f,y         ; monster center x (low byte)
        sec
        sbc     #$0c
        sta     OT6_SCR_SLOT2   ; running pen x
        lda     $804b,y         ; monster bottom y
        clc
        adc     $38             ; battle screen shake/scroll offset
        inc
        inc
        sta     OT6_SCR_IDX     ; pen y
        ; shield digit or B
        lda     $3e90,y         ; broken timer
        beq     @digit
        lda     #$09            ; glyph 9 = 'B'
        bra     @emit0
@digit: lda     $3e40,y         ; shield current
        beq     @weak           ; shieldless: no digit, straight to slots
        cmp     #$07
        bcc     :+
        lda     #$06
:       clc
        adc     #$09            ; glyphs 10-15 = digits 1-6
@emit0: jsr     Ot6EmitSprite
@weak:  lda     #$01
        sta     OT6_SCR_BIT     ; walking element bit
        stz     OT6_SCR_COLS    ; element index
@elem:  lda     OT6_SCR_BIT
        beq     @next           ; walked past bit 7
        and     $3be8,y         ; weak to this element?
        beq     @ebump
        lda     OT6_SCR_BIT
        and     $3e91,y         ; revealed?
        beq     @q
        lda     OT6_SCR_COLS    ; glyph 0-7: the element icon
        bra     @emit
@q:     lda     #$08            ; glyph 8 = '?'
@emit:  jsr     Ot6EmitSprite
@ebump: asl     OT6_SCR_BIT
        inc     OT6_SCR_COLS
        bra     @elem
@next:  iny
        iny
        cpy     #$000c
        bcc     @slot
        ; character pass: bp digit (bp - pending) beside each hero
        ldy     #$0000          ; character entity offset 0,2,4,6
@cslot: lda     $3aa0,y
        lsr
        bcc     @cnext          ; character not present
        lda     $3018,y         ; party mask nonzero = real slot
        beq     @cnext
        lda     $8033,y         ; character center x (low byte)
        clc
        adc     #$0a            ; digit sits at the hero's right shoulder
        sta     OT6_SCR_SLOT2
        lda     $8043,y         ; character bottom y
        clc
        adc     $38
        sta     OT6_SCR_IDX
        lda     $3e9c,y         ; bp
        sec
        sbc     $3e9d,y         ; minus pending boost = spendable shown
        beq     @cnext          ; zero: draw nothing
        bcc     @cnext
        cmp     #$06
        bcc     :+
        lda     #$05
:       clc
        adc     #$09            ; glyphs 10-15 = digits 1-6
        jsr     Ot6EmitSprite
@cnext: iny
        iny
        cpy     #$0008
        bcc     @cslot
        plb
        ply
        plx
        plp
        rtl
.endproc

; emit one hud sprite: a = glyph index, x = oam byte offset in our block
; (advances by 4 when a sprite is placed), pen in OT6_SCR_SLOT2/IDX.
; b must be 0 (caller guarantees via shorta0).
.proc Ot6EmitSprite
        .a8
        .i16
        cpx     #$0080
        bcs     @full           ; claimed entries exhausted
        pha                     ; glyph index
        lda     OT6_SCR_SLOT2
        sta     OT6_OAM,x       ; sprite x
        clc
        adc     #$09
        sta     OT6_SCR_SLOT2   ; advance the pen
        lda     OT6_SCR_IDX
        sta     OT6_OAM+1,x     ; sprite y
        pla
        asl                     ; table stride 2: [tile low][name bit]
        phx
        tax
        lda     f:Ot6ObjTileNumTbl,x
        xba                     ; tile low byte parks in b
        lda     f:Ot6ObjTileNumTbl+1,x
        plx
        ora     #$26            ; priority 2, palette 3, + name bit
        sta     OT6_OAM+3,x
        xba                     ; tile low byte back
        sta     OT6_OAM+2,x
        inx
        inx
        inx
        inx
        lda     #$00            ; scrub b (callers rely on b = 0 for tax)
        xba
@full:  rts
.endproc


; hud icon hues, uploaded into obj palette 3's duplicate upper half
; (cgram $b8+): body color index = 8 + element
Ot6HudPal:
        .word   $0000
        .word   $7fff
        .word   $77bb
        .word   $6737
        .word   $56b1
        .word   $462d
        .word   $35a9
        .word   $2525
        .word   $085f
        .word   $7ecf
        .word   $137f
        .word   $1ba6
        .word   $7ffb
        .word   $3fbf
        .word   $2639
        .word   $7e29
