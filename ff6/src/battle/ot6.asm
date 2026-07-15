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
        jsr     Ot6BuildRowGlyphs
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ shield glyph for the monster name row being drawn ]

; called from btlgfx MenuTextCmd_0b in place of the trailing blank;
; returns the glyph in a for DrawMenuLetter. ($48) still points at the
; row slot byte of the menu text string.

.proc Ot6ShieldGlyph_ext
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
; blank). writes 5 tiles to cells $eb-$ef and 3 to $fb-$fd of the font at
; vram $5800 (8 words per 2bpp tile).

.proc Ot6LoadFontIcons_ext
        php
        phb
        clr_a
        pha
        plb                     ; db = $00 for hardware registers
        shorta
        lda     #$80
        sta     hVMAINC         ; increment on high byte, +1 word
        longa
        lda     #$5800+$eb*8
        sta     hVMADDL
        ldx     #$0000
@half1: lda     f:Ot6FontIcons,x
        sta     hVMDATAL
        inx2
        cpx     #$0050          ; 5 tiles ($eb-$ef)
        bcc     @half1
        lda     #$5800+$fb*8
        sta     hVMADDL
@half2: lda     f:Ot6FontIcons,x
        sta     hVMDATAL
        inx2
        cpx     #$0080          ; 3 more tiles ($fb-$fd)
        bcc     @half2
        plb
        plp
        rtl
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
