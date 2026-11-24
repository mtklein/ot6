; [ upload the bg hud glyphs into free font cells ]

; 16 2bpp tiles written to the battle font at vram $5800 + cell*8, as two
; 8-tile slices (~128 bytes each, one of which fits a vblank-tail re-lay
; stage): slice A is the six monster slots' shield-count tiles (#292: each
; slot's cell holds the tile for ITS live count, OT6_SHHAVE, so a slot with
; nothing uploaded yet is skipped) plus the broken shield and pips-0; slice B
; the other pip clusters and the boost cells.
; a8/i16, db = $00, vmainc $80. exits a8. clobbers a/x/y.

.macro ot6_glyph_slice first, last
        ldx     #first          ; glyph index
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
        cpx     #last
        bcc     @tile
        rts
.endmacro

.proc Ot6LoadBgGlyphsA
        .a8
        .i16
        ldy     #$0000          ; monster slot 0-5
@slot:  tyx
        lda     f:$7e0000+OT6_SHHAVE,x
        beq     @next           ; nothing uploaded for this slot yet
        jsr     Ot6UploadSlotTile
@next:  iny
        cpy     #$0006
        bcc     @slot
        ot6_glyph_slice $0000, $0002
.endproc

.proc Ot6LoadBgGlyphsB
        .a8
        .i16
        ot6_glyph_slice $0002, $000b
.endproc

; [ upload one monster slot's shield-count tile (#292) ]

; a = the count 1..99, y = the monster slot 0-5.  writes Ot6ShieldGlyphs'
; tile for the count into the slot's own font cell (Ot6ShieldSlotCellTbl).
; 8 words.  a8/i16, db = $00, vmainc $80; vblank or forced blank only.
; clobbers a/x, preserves y.

.proc Ot6UploadSlotTile
        .a8
        .i16
        dec     a               ; count 1..99 -> tile 0..98
        longa
        and     #$00ff
        asl
        asl
        asl
        asl                     ; * 16 bytes a tile
        pha
        tyx
        lda     f:Ot6ShieldSlotCellTbl,x
        and     #$00ff
        asl
        asl
        asl
        clc
        adc     #$5800          ; vram word address of the slot's cell
        sta     hVMADDL
        plx
        lda     f:Ot6ShieldGlyphs+0,x
        sta     hVMDATAL
        lda     f:Ot6ShieldGlyphs+2,x
        sta     hVMDATAL
        lda     f:Ot6ShieldGlyphs+4,x
        sta     hVMDATAL
        lda     f:Ot6ShieldGlyphs+6,x
        sta     hVMDATAL
        lda     f:Ot6ShieldGlyphs+8,x
        sta     hVMDATAL
        lda     f:Ot6ShieldGlyphs+10,x
        sta     hVMDATAL
        lda     f:Ot6ShieldGlyphs+12,x
        sta     hVMDATAL
        lda     f:Ot6ShieldGlyphs+14,x
        sta     hVMDATAL
        shorta
        rts
.endproc

; ------------------------------------------------------------------------------

; [ per-frame bg hud: rebuild the shadow line buffer ]

; the hud lives on the bg3 field tilemap; this main-loop pass fills a
; shadow buffer in bank $7f, and the nmi flush copies it to vram during
; vblank. shadow at OT6_SHADOW, 6 lines x 14 bytes:
;   +0  vram word address of the line's first cell (0 = line disabled)
;   +2  five tilemap words (glyph | attr << 8)
; monsters: [shield emblem][shield count][up to 4 weakness slots:
; elements, then weapon classes, revealed icon or '?' on both axes]
; (#397: the emblem is the line's lead cell, OT6_HUDLEAD, written at the
; anchor minus one; a broken monster shows the broken shield there and an
; empty count cell). entities animate and drift, so each line remembers
; its previous address; the flush blanks the old cells when it moves.
; line layout: +0 cur addr (0 = disabled), +2 prev addr, +4 five cells.

; Lives at $7eecf1, past the end of vanilla's battle-graphics RAM chain
; (btlgfx_ram.inc's chain ends at label w7eecf0, capped by
; `.assert _ram_offset <= $7ef800`, btlgfx_ram.inc:1001).
; DO NOT extend past $7ef11f: PushMode7Vars (world/init.asm:1414) block-
; moves $7ef120-$7ef7ff via `mvn`. 1071 bytes are available; this uses 84.
                                ; OT6_SHADOW: lines, stride 14
                                ; OT6_MAPBASE: field bg3 map-base word

; [ battle-script bracket: is an animation script executing? ]

; every coordinate transient the animation engine imposes on the monster
; position arrays (magic_init_131long zeroing/setting the $8057
; priority shifts and displacing $80cf by -$0100, btlgfx_main.asm:
; 39277-39297; AnimCmd_80_82's all-slot x shove, :29906; AnimCmd_e2/
; e3's per-frame y animation, :33206-33279; the PushObjPos/PopObjPos
; block-hop family, :28045/:28081) runs from a battle animation
; script, and every such script executes inside BtlGfx_04 "execute
; battle script" (btlgfx_main @9512): action animations, monster
; specials, entry/exit effects, battle events.  scripts restore their
; transients before they end (PopObjPos restores what PushObjPos saved,
; $80/$84 restores $80/$83's y displacement, $e3 restores from
; w7e64e8), so script-free frames see settled coords by construction,
; and a script that ended without restoring has visibly parked the
; monster there in vanilla too, at which point following it is correct
; rather than stale.  so the anchor holds while OT6_SCRIPTBUSY is up and
; adopts on script-free frames.
;
; the flag is raised/cleared by the Ot6BtlGfx04_c1 wrapper behind
; BtlGfxTbl's $04 entry (same-size .addr repoint; see the block comment
; there for the C1 layout discipline).

.proc Ot6ScriptBegin_ext
        .a8
        lda     #$01
        sta     f:$7e0000+OT6_SCRIPTBUSY
        lda     #$00            ; BtlGfx_04 zeroes the multi-target numeral
        sta     f:$7e0000+OT6_MULCTR    ;   counter as it starts (#539)
        rtl
.endproc

; the script is over: whatever its hits did is shown now (#539's flush).
; a8 from C1; pins its own widths and db, restores them.
.proc Ot6ScriptEnd_ext
        .a8
        lda     #$00
        sta     f:$7e0000+OT6_SCRIPTBUSY
        php
        phb
        sep     #$20
        rep     #$10
        .a8
        .i16
        lda     #$7e
        pha
        plb
        jsr     Ot6ShowFlush
        jsr     Ot6PipPending   ; and a deferred point shows (#540)
        plb
        plp
        rtl
.endproc

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
        jsr     Ot6Boost        ; l/r boost input
        jsr     Ot6RevealPoll   ; a numeral appeared? commit the reveals
        bcc     :+              ; carry = this tick saw the numeral, so
        jsr     Ot6PipPending   ;   a deferred cover pip paints on it too
:       jsr     Ot6PipStage     ; stage the four live pip-row words
        jsr     Ot6WalletStage  ; stage the costed-list MP wallet
        lda     OT6_FUSEPOLL    ; #561: a body with a fuse stands in this
        beq     :+              ;   battle?  then one slot's lit bit a frame
        jsr     Ot6FusePoll     ;   (ot6_fuse.asm; inline gate, as below)
:
        ; drive any live break flash.  after the poll above on purpose: a
        ; break armed by this tick's numeral gets its first white frame on
        ; that same frame rather than the next one.  The gate is inline rather
        ; than a `jsr` into a proc that early-outs: this site is inside the
        ; battle loop's per-frame call (WaitFrame calls UpdateCharText ->
        ; Ot6BgHud_ext once per battle frame, btlgfx_main.asm:432-445) and
        ; the frame budget is close enough to full that a `jsr` into an
        ; early-out proc measurably slows the battle loop.
        lda     OT6_BRKLIVE     ; db=$7e is pinned at the top of this proc
        beq     :+
        jsr     Ot6BreakFlash
:
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
        bcc     @gone           ; slot empty
        ; the slot is filled, but is the monster on screen yet?  at battle
        ; entry a monster is flagged present ($3aa8) from init, while its
        ; sprite is not drawn until its fly-in animation runs: the "monsters
        ; shown" mask $201e (notes/battle-ram.txt:422 "--654321 monsters
        ; shown"; the sprite drawers gate on it, btlgfx_main.asm:5639/:5772,
        ; and DoMonsterEntryExit SETS a monster's bit as its entry completes,
        ; :45554) holds 0 for the whole fade-in window.  gating the hud on
        ; the same mask the sprites use keeps it from painting an entering
        ; monster's shield/'?' cells before the sprite exists.  a dead
        ; monster also clears its $201e bit, but the $3eec dead-cell path
        ; below already blanks that line, so the two agree.
        phx                     ; save the shadow line base
        longa
        tya
        lsr                     ; monster slot 0-5 (y is the 2-byte offset)
        tax
        shorta0
        lda     f:Ot6ShownBitTbl,x
        plx                     ; restore the shadow line base
        and     a:$201e
        bne     @on             ; present AND shown: draw
@gone:  ; monster gone, or present but not yet entered: disable the line
        ; (flush blanks the old cells once). compare-before-store like the
        ; anchor commit at @done: an already-disabled line writes nothing, so
        ; a static battlefield produces no anchor stores across all six
        ; lines.
        longa
        lda     f:$7e0000+OT6_SHADOW,x
        beq     @off
        lda     #$0000
        sta     f:$7e0000+OT6_SHADOW,x
@off:   shorta0
        rts
@on:    ; blank the five cell words, rebuild below. the anchor word at +0
        ; is only committed at the very end (and only when it changes):
        ; the NMI flush can fire mid-rebuild, so the enable is the commit.
        longa
        lda     #$21ff
        sta     f:$7e0000+OT6_SHADOW+4,x
        sta     f:$7e0000+OT6_SHADOW+6,x
        sta     f:$7e0000+OT6_SHADOW+8,x
        sta     f:$7e0000+OT6_SHADOW+10,x
        sta     f:$7e0000+OT6_SHADOW+12,x
        sta     OT6_HUDLEAD,y   ; the lead cell too (db = $7e here)
        shorta0
        ; the shield gauge (#397): the lead cell and cell 0.  shielded: the
        ; emblem (fixed cell $71) in the lead cell and the slot's count tile
        ; in cell 0, both in text palette 0, plain white.
        ; broken: the broken shield (the slot's tile 100) in the lead cell,
        ; palette 7, and cell 0 empty.  shieldless: both empty.
        ; dead monsters: cells stay blank, line stays live (erases old art).
        ; all of it as of the last hit shown (#539, Ot6ShownGauge)
        jsr     Ot6ShownGauge
        jsr     Ot6MarkStage    ; the trap's mark before the emblem (#546)
        bit     #$40
        jne     @done           ; dead or petrified
        cmp     #$00
        bpl     @count
        lda     #100            ; the broken shield's tile
        bra     @tile
@count: and     #$3f
        jeq     @slots          ; shieldless
        cmp     #100            ; the count tiles run 1..99
        bcc     @tile
        lda     #99
@tile:  phx
        pha                     ; the tile: a count 1..99, or 100 = broken
        longa
        tya
        lsr                     ; monster slot 0-5 (y is the 2-byte offset)
        tax
        shorta
        lda     $01,s
        ; the slot's cell draws the tile only once the flush has uploaded
        ; it (#292); until then it still shows the last one, for a frame
        ; or so.  ask for the upload when the cell holds another tile.
        cmp     OT6_SHHAVE,x    ; db = $7e here
        beq     :+
        sta     OT6_SHWANT,x
        lda     f:Ot6ShieldBitTbl,x
        tsb     OT6_SHPEND
:       lda     f:Ot6ShieldSlotCellTbl,x
        xba                     ; b = the slot's cell
        pla                     ; a = the tile
        plx                     ; the shadow line base
        cmp     #100
        bne     @gauge
        lda     OT6_STILLMARK   ; #538: anything Still Life marks or holds?
        ora     OT6_STILLHELD   ;   (one test a line while nothing is)
        bne     @pbroke
        lda     #OT6_BROKEN_ATTR ; broken: the slot's cell in the lead cell,
        xba                     ;   palette 7; cell 0 stays empty.  whole-
        longa                   ;   word store: the nmi flush can fire
        sta     OT6_HUDLEAD,y   ;   between two byte stores
        shorta0
        bra     @slots
@pbroke:
        xba                     ; a = the slot's cell
        pha
        jsr     Ot6StillBrokenAttr ; palette 7, or green while Still Life
        xba                     ;   holds the break or waits on the next
        pla
        longa
        sta     OT6_HUDLEAD,y
        shorta0
        bra     @slots
@gauge: lda     OT6_UNDERPAINT  ; #538: anything painted on a shield line?
        ora     OT6_STILLMARK
        bne     @pgauge
        lda     #OT6_GAUGE_ATTR ; whole-word stores, as above
        xba
        longa                   ; a = attr << 8 | the slot's cell
        sta     f:$7e0000+OT6_SHADOW+4,x        ; cell 0: the count tile
        lda     #(OT6_GAUGE_ATTR << 8) | OT6_EMBLEM
        sta     OT6_HUDLEAD,y   ; the lead cell: the emblem
        shorta0
        bra     @slots
@pgauge:
        xba                     ; a = the slot's cell
        pha
        jsr     Ot6UnderAttr    ; the count: green while Underpainting waits
        xba
        pla
        longa                   ; a = attr << 8 | the slot's cell
        sta     f:$7e0000+OT6_SHADOW+4,x
        shorta0
        jsr     Ot6StillAttr    ; the emblem: green while Still Life waits
        xba
        lda     #OT6_EMBLEM
        longa
        sta     OT6_HUDLEAD,y
        shorta0
        ; weakness slots into cells 1-4: elements first (vanilla's own
        ; data), then the class weaknesses, sharing the same four cells.
        ; a fifth weakness is truncated, which is the deliberate cap: the
        ; row is five cells wide (the shadow strip has no room for more
        ; without moving the $57c0+ occupants), and no authored WoB species
        ; exceeds 4 total today (speck's 4 classes ride an element-free
        ; body). revealed-vs-'?' behavior is identical on both axes.
@slots: phx                     ; base on stack for the cap test
        lda     #$01
        sta     OT6_SCR_BIT
        lda     #$00
        sta     OT6_SCR_IDX     ; element index
@elem:  lda     OT6_SCR_BIT
        beq     @cls            ; elements walked: on to the classes
        and     $3be8,y
        beq     @next
        inx
        inx                     ; claim the next cell
        txa
        sec
        sbc     $01,s           ; cells used so far (byte diff, same page)
        cmp     #$09
        jcs     @edone          ; past slot cell 4 (offsets +6..+12);
                                ;   long branch: the class loop sits between
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
@q:     lda     #OT6_QMARK_ATTR ; '?' in grey: attr first, as above
        sta     f:$7e0000+OT6_SHADOW+5,x
        lda     #OT6_QMARK
        sta     f:$7e0000+OT6_SHADOW+4,x
@next:  asl     OT6_SCR_BIT
        inc     OT6_SCR_IDX
        bra     @elem
@cls:   ; class-weakness slots: same claim/cap flow, from the authored
        ; class mask (OT6_BP_CLASS monster half, seeded at battle init) and the
        ; revealed-classes byte the chips and codex maintain. the icons
        ; are the vanilla item-class glyphs, white (the default $21 attr
        ; from the fill is already in place, so only the glyph byte is
        ; written; the '?' writes its grey attr first).
        lda     #$01
        sta     OT6_SCR_BIT
        lda     #$00
        sta     OT6_SCR_IDX     ; class index 0-5
        lda     $3ea4,y         ; #566: a body every class breaks says so in
        and     #OT6_CLASSES    ;   ONE cell, the any-weapon mark (six icons
        cmp     #OT6_CLASSES    ;   would not fit the line's four cells): the
        bne     @cbit           ;   mark once any class of it is revealed
        inx
        inx                     ; claim the next cell
        txa
        sec
        sbc     $01,s
        cmp     #$09
        bcs     @edone          ; past slot cell 4
        lda     $3ea5,y
        and     #OT6_CLASSES
        beq     @anyq
        lda     #OT6_ANYWEAPON
        sta     f:$7e0000+OT6_SHADOW+4,x
        bra     @edone
@anyq:  lda     #OT6_QMARK_ATTR ; '?' in grey, attr first
        sta     f:$7e0000+OT6_SHADOW+5,x
        lda     #OT6_QMARK
        sta     f:$7e0000+OT6_SHADOW+4,x
        bra     @edone
@cbit:  lda     OT6_SCR_BIT
        cmp     #OT6_CLASSES+1
        bcs     @edone          ; all six classes walked
        and     $3ea4,y         ; monster class weaknesses (OT6_BP_CLASS + 8)
        beq     @cnext
        inx
        inx                     ; claim the next cell
        txa
        sec
        sbc     $01,s           ; cells used so far (byte diff, same page)
        cmp     #$09
        bcs     @edone          ; past slot cell 4
        lda     OT6_SCR_BIT
        and     $3ea5,y         ; revealed classes (OT6_BOOST_REVEALED + 8)
        beq     @cq
        phx
        lda     OT6_SCR_IDX
        longa
        and     #$00ff
        tax
        shorta0
        lda     f:Ot6ClassGlyphTbl,x
        plx
        sta     f:$7e0000+OT6_SHADOW+4,x
        bra     @cnext
@cq:    lda     #OT6_QMARK_ATTR ; '?' in grey, attr first
        sta     f:$7e0000+OT6_SHADOW+5,x
        lda     #OT6_QMARK
        sta     f:$7e0000+OT6_SHADOW+4,x
@cnext: asl     OT6_SCR_BIT
        inc     OT6_SCR_IDX
        bra     @cbit
@edone: plx
@done:  ; commit: recompute-and-compare, adopted only on quiet ticks.
        ; the anchor holds while OT6_SCRIPTBUSY is up (a battle script may
        ; be driving monster-position transients, listed at
        ; Ot6ScriptBegin_ext) and recomputes on script-free frames, where
        ; coords are settled by construction.  identical frames compare
        ; equal and write nothing; a change that survives into a quiet
        ; frame is adopted within a frame or two.
        ;
        ; the row source is not the frame's raw $804b: cur_poi_set
        ; (btlgfx_main.asm:1032, run every frame at :1738) derives it as
        ; $80cf + height*8 - 8 + $8057, and $8057 is a sprite-priority
        ; bias whose value is path-dependent: seeded per species from
        ; MonsterOverlap at monster load (btlgfx_main.asm:4671; whelk
        ; head = 8, guards = 0), zeroed for all slots by every $80/$83
        ; animation init (magic_init_131long, :39277), and never re-
        ; seeded until the next monster load. so: strip the live $8057
        ; back out and re-apply the load-time species seed, which is
        ; stable across the whole $8057 lifecycle. the column source
        ; $800f = $80c3 + width*4 has no such term. 8-bit low-byte reads
        ; throughout: transients riding the high bytes ($80/$83's -$0100 y
        ; displacement, stashed/restored at :39292/:29884) never reach
        ; this code.
        lda     f:$7e0000+OT6_SCRIPTBUSY
        bne     @keep           ; a battle script owns this frame:
                                ;   coords may be transients, so hold
        phx                     ; save shadow line base
        longa
        lda     OT6_SPECIES,y   ; slot species (== monster index)
        tax
        shorta0
        lda     f:MonsterOverlap,x
        sta     OT6_SCR_BIT     ; the load-time $8057 seed
        lda     $804b,y
        sec
        sbc     $8057,y         ; strip the live priority shift...
        clc
        adc     OT6_SCR_BIT     ; ...re-apply the load-time seed
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
        cmp     f:$7e0000+OT6_SHADOW,x
        beq     @asis           ; unchanged: write nothing at all
        sta     f:$7e0000+OT6_SHADOW,x  ; adopt (atomic word: the enable
                                        ;   is still the commit; the
                                        ;   nmi flush can fire mid-frame,
                                        ;   and the flush's prev/cur pass
                                        ;   blanks the vacated cells)
@asis:  plx
@keep:  shorta0
        rts
.endproc

; monster slot (0-5) -> its bit in the $201e "monsters shown" mask. slot s is
; bit s.
Ot6ShownBitTbl:
        .byte   $01,$02,$04,$08,$10,$20

; ------------------------------------------------------------------------------

; [ vblank flush: shadow lines -> bg3 field tilemap ]

; called from the battle nmi right after the oam dma.

                                ; OT6_HUDCOPY ($57de) is retired and not ours:
                                ;  $57de is inside vanilla's
                                ;  `ram_res w7e57d5, 128`. kept only so the
                                ;  memory map records that this range is
                                ;  vanilla's, not free.)
                                ; OT6_ATKCLASS is the executing attack's
                                ; class byte: one of
                                ;   $01/$02/$04/$08 (+$80 null-break), 0 =
                                ;   classless. set by the three load hooks,
                                ;   read per target by Ot6ClassChip. lives
                                ;   in retired OT6_HUDDIRTY's byte, inside
                                ;   the m2 trace-verified strip and the
                                ;   InitBP clear.

; weakness codex species stash: one word per monster slot so the chip procs
; can find the active save page's species entry at reveal time.
                                ; OT6_SPECIES: per-slot species stash (6 words)
                                ; OT6_PIPCUR/PIPPREV/PIPCELL: retired;
                                ;   see ot6_memory.inc
                                ; OT6_LASTLR: last frame's L/R bits
                                ; OT6_RESTAGE: open list wants a re-render
                                ; OT6_FONTDIRTY: font re-lay stages remaining.
                                ; RELOCATED from $57d5: vanilla reserves
                                ; $57d5..$5854 as the battle name-scratch
                                ; string (ram_res w7e57d5,128: GfxCmd_01
                                ; attack names, GfxCmd_11 monster specials,
                                ; and swdtech/esper name loaders all write
                                ; byte 0 nonzero), so every named-attack
                                ; banner would trigger a full ~46-scanline
                                ; font re-lay in the nmi tail and tear the
                                ; frame. $57b9 is the spare
                                ; byte after OT6_ATKCLASS, inside the m2
                                ; trace-verified strip and the InitBP @clr
                                ; (bank-F0 writers only).
; Note: the boundary is not "$57d5+ is vanilla's alone". btlgfx_ram.inc
; reserves two buffers, w7e5755,128 and w7e57d5,128, both vanilla's.
; vanilla's writes into the $5755 buffer stop at $576b, so the OT6 strip
; from $57b6 up is clear. Below $576b is not. See OT6_SHADOW.
OT6_RELAY_STAGES := 3           ; icons, glyphs x2 (~128b each)

; the strip $57ba-$57bf (between OT6_FONTDIRTY and OT6_SPECIES,
; inside the m2 trace-verified free range). InitBP's @clr loop deliberately
; stops at $57b9:
; clearing $57bc would eat the random-encounter marker the field just set.
; occupants: $57ba-$57bb spare, $57bc RANDPEND, $57bd RANDBTL,
; $57be HUDVEIL, $57bf SCRIPTBUSY (HUDVEIL and SCRIPTBUSY init-cleared one
; byte at a time in InitBP).
                                ; OT6_RANDPEND marks that the NEXT battle is
                                ; a random encounter:
                                ;   holds OT6_RANDMAGIC, set by
                                ;   Ot6MarkRandom from the two field/world
                                ;   random-battle triggers; consumed
                                ;   (compared + cleared) by InitBP.
                                ; OT6_RANDBTL marks this battle as random
                                ;   (InitBP's normalized 0/1 copy of the
                                ;   marker; read at victory by
                                ;   Ot6RewardScale_ext). the copy-and-
                                ;   clear protocol means a marker can
                                ;   never leak past one battle: every
                                ;   InitBattle refreshes $57bd and zeroes
                                ;   $57bc, so an event battle after a
                                ;   fled or lost random encounter reads
                                ;   0. two junk defenses on top (the
                                ;   strip is init-exempt, so power-on/
                                ;   menu junk lives here until the first
                                ;   battle): the marker
                                ;   is a magic value, not "nonzero", and
                                ;   Ot6DangerStep word-clears both bytes
                                ;   on every danger-checked field step.
OT6_RANDMAGIC := $a5            ; the marker value (junk is $00/$ff in
                                ;   every observed boot line)
                                ; OT6_HUDVEIL: monster entry/exit animation
                                ;   owns bg3: the flush writes vanilla's
                                ;   $01ee junk fill over each live hud
                                ;   line instead of its cells (shadow
                                ;   untouched). set/cleared by
                                ;   Ot6EntryExitVeil_ext, cleared by
                                ;   InitBP (the strip is init-exempt, so
                                ;   power-on junk here would blank the
                                ;   hud from battle one).
                                ; OT6_SCRIPTBUSY: battle animation script
                                ;   (BtlGfx_04 "execute battle script")
                                ;   is executing, so monster coords may
                                ;   be animation transients. raised/
                                ;   cleared by Ot6ScriptBegin_ext /
                                ;   Ot6ScriptEnd_ext (bank F0, keeping
                                ;   the strip's F0-only writer
                                ;   invariant) from the Ot6BtlGfx04_c1
                                ;   wrapper behind BtlGfxTbl's $04
                                ;   entry. the hud builder holds anchor
                                ;   adoption while set. cleared by
                                ;   InitBP (init-exempt strip: power-on
                                ;   junk would freeze anchor adoption)
                                ;   and self-healing besides: the first
                                ;   completed script clears it.

; [ monster entry/exit animations: veil the under-enemy hud ]

; every jsl DoMonsterEntryExit site in bank c1 is re-pointed here (same
; four bytes, no code motion). the entry/exit effect family, and the whelk
; retract's FADE_DOWN/FADE_UP wipes in particular, sweeps the battle-field
; bg3 region with a per-scanline scroll wave (hdma #2, fed from the
; w7e4af5 table the effect animates), and it assumes the field map holds
; nothing visible but its own mask tiles: vanilla blanks even its banner
; rows to the $01ee junk fill before scrolling. our under-enemy hud lines
; ride that same map, so without the veil the wipe would smear their
; glyphs across the screen. while the veil byte is set the nmi flush
; writes the $01ee fill over each live line instead of its cells, so the
; field map is word-identical to vanilla's for the whole animation, and
; the shadow itself is untouched, so the first flush after the effect
; repaints the hud as built (or blanks it, if the monster left with the
; effect). a8/i16 at every call site (battle gfx script context); the anim
; returns a8/i16 on every path, so the sep #$20 is redundant.

.proc Ot6EntryExitVeil_ext
        .a8
        .i16
        lda     #$01
        sta     f:$7e0000+OT6_HUDVEIL
        jsl     DoMonsterEntryExit
        sep     #$20
        lda     #$00
        sta     f:$7e0000+OT6_HUDVEIL
        rtl
.endproc

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
        sta     hVMAINC         ; word writes for the stages and the lines
        ; a battle dialogue clobbered our font cells? re-lay them one
        ; ~128-byte slice per nmi (OT6_FONTDIRTY counts stages left).
        ; the full 768-byte re-lay is ~46 scanlines of PIO, more than
        ; a whole vblank, so a single-shot re-lay would tear the frame it
        ; ran on. staging self-heals over 6 frames and each slice is gated
        ; on the live v counter: only start one with >= 14 lines of vblank
        ; left (slice ~9 + flush ~3 + hdma/inidisp tail ~2), else retry
        ; next nmi.
        lda     f:$7e0000+OT6_FONTDIRTY
        beq     @nofont
        lda     hSLHV           ; software-latch the h/v counters
        lda     hSTAT78         ; reset the opvct read flip-flop
        lda     hOPVCT          ; v low byte
        xba                     ; stash it in b
        lda     hOPVCT          ; v bit 8 (in bit 0)
        lsr                     ; -> carry
        xba                     ; a = v low byte (xba preserves carry)
        bcs     @nofont         ; v >= 256: 6 lines left, too late
        cmp     #$e1            ; v < 225: not vblank (defensive)
        bcc     @nofont
        cmp     #$f9            ; v > 248: too late to start a slice
        bcs     @nofont
        lda     f:$7e0000+OT6_FONTDIRTY
        dec     a
        sta     f:$7e0000+OT6_FONTDIRTY
        beq     @s0             ; a = stage 2..0, most visible first
        cmp     #$01
        beq     @s1
        jsr     Ot6LoadElemIcons        ; 2: menu element icons
        bra     @nofont
@s1:    jsr     Ot6LoadBgGlyphsA        ; 1: hud shield glyphs
        bra     @nofont
@s0:    jsr     Ot6LoadBgGlyphsB        ; 0: hud pip/boost glyphs
@nofont:
        ; a monster slot's shield count changed (#292): upload the tile for
        ; its new count into the slot's cell.  change-only (zero words on a
        ; quiet frame), one slot per nmi, and gated like the one-shot line
        ; transitions below, since a dropped tile write has no next-frame
        ; rewrite: OT6_SHPEND keeps the bit until an admitted nmi lands it.
        ;
        ; never while a battle dialog window is up (w7e64d5) or a font
        ; re-lay is in flight (OT6_FONTDIRTY), the same two conditions that
        ; veil the hud lines below: the dialog uses the whole $5800-$5fff
        ; font page as its text canvas, cells $65-$6b included, so a tile
        ; written then lands in the dialog box (review of #292, Whelk: a
        ; synthetic upload mid-dialog drew a shield in the empty box).  the
        ; bit stays pending, and the close's re-lay (slice A re-uploads
        ; every slot from OT6_SHHAVE) runs first, so the upload lands after.
        lda     f:$7e0000+OT6_SHPEND
        beq     @noslot
        lda     f:$7e0000+$64d5 ; dialog window open?
        bne     @noslot
        lda     f:$7e0000+OT6_FONTDIRTY ; font re-lay in flight?
        bne     @noslot
        jsr     @late
        bcs     @noslot         ; too late: the bit stays, next nmi
        lda     f:$7e0000+OT6_SHPEND
        ldy     #$0000
@find:  lsr                     ; lowest pending slot
        bcs     @got
        iny
        bra     @find
@got:   tyx
        lda     f:Ot6ShieldBitTbl,x
        eor     #$ff
        and     f:$7e0000+OT6_SHPEND    ; the main loop cannot run inside
        sta     f:$7e0000+OT6_SHPEND    ;   this read-modify-write
        lda     f:$7e0000+OT6_SHWANT,x
        beq     @noslot         ; defensive: the builder never asks for 0
        sta     f:$7e0000+OT6_SHHAVE,x
        jsr     Ot6UploadSlotTile
@noslot:
        ; two write disciplines below, on purpose.
        ; steady-state cell writes (prev == cur) are not v-gated: a write
        ; spilled past vblank is dropped by the PPU, and the rewrite-
        ; every-nmi design heals it next frame.  rewriting every nmi is
        ; already required because the animation-bg restore junk-fills
        ; the area every other frame during monster actions (see the
        ; call-site comment, btlgfx_main @0c17). one-shot transitions
        ; (prev != cur: a line moved, enabled at a new address after a
        ; move, or disabled) have no next-frame rewrite to heal them, and
        ; a dropped blank-at-prev would leave stale glyphs, so they
        ; are admission-gated on the live v counter and deferred when
        ; late: prev only advances after the blank ran inside an
        ; admitted window, so the whole transition redoes next nmi
        ; until it lands. within the window a drop is impossible by
        ; arithmetic: admission ends at v=248, the worst burst (all six
        ; lines + pip transitioning at once) is ~82 words ~ 10.3 scanlines
        ; at the measured PIO rate (~8 words/scanline, the font-slice
        ; numbers above), ending ~259 < 262 (six-cell lines since #397:
        ; ~70 words, ~257, before). residual risk: a transition
        ; deferred into a veil window leaves old glyphs one extra frame if
        ; the nmi is also late.
        ;
        ; each line is six cells (#397): the lead cell (OT6_HUDLEAD, the
        ; shield gauge's emblem) at the anchor minus one, then the shadow's
        ; five.  x walks the shadow lines, y the matching slot offsets.
        ldx     #$0000
        ldy     #$0000
@line:  longa
        lda     f:$7e0000+OT6_SHADOW+2,x         ; prev
        beq     @write
        cmp     f:$7e0000+OT6_SHADOW,x           ; moved?
        beq     @write
        shorta0                                  ; one-shot: gate it
        jsr     @late
        jcs     @skip           ; too late: hold prev, redo whole
                                ;   transition next nmi (@skip opens
                                ;   with shorta0, so a8 entry is fine)
                                ;   (long branch: the 16x16-mode veil
                                ;   check grew the body past bcs reach)
        longa
        lda     f:$7e0000+OT6_SHADOW+2,x         ; reload prev (gate ate a)
        and     #$001f          ; the mark cell (#546), two before the
        cmp     #$0002          ;   anchor, unless the old line sat in
        lda     f:$7e0000+OT6_SHADOW+2,x         ;   column 0 or 1, where
        dec     a               ;   it had none (@mark's edge rule): the
        bcc     @nomark         ;   blank must not reach the row above
        dec     a
        sta     hVMADDL
        lda     #$01ee
        sta     hVMDATAL
        bra     @blank6
@nomark:
        sta     hVMADDL                          ; blank the old cells
        ; the blank word is vanilla's $01ee junk fill rather than $21ff.
        ; cells a line abandons (a move or a disable) are rewritten once,
        ; here, and then belong to nobody: no next-nmi repaint heals them, so
        ; whatever word this writes sits in the field map until vanilla's next
        ; ClearBG3TileBuf.  $21ff (priority-set char $1ff) is invisible
        ; in 8x8 (the char is a blank cell in the $5800 font page), but under
        ; an animation's bg3-16x16 window a 16x16 map cell renders char n
        ; plus n+1/n+$10/n+$11, so $1ff pulls tiles $200/$20f/$210, past the
        ; font page and into the animation-gfx region, at top priority: a
        ; monster-entrance slide that walks hud lines sideways through that
        ; window would render a band of white junk over the entering
        ; monsters.  $01ee is the word vanilla holds in every field cell it
        ; did not draw itself, priority-clear, and safe in both tile modes
        ; (its 16x16 neighbors $1ef/$1fe/$1ff are priority-clear with it,
        ; under the battle bg).  It is the same word the veil below writes
        ; over live cells and the entry wipes sweep.  an abandoned cell is
        ; now word-identical to a cell this code never touched.
        lda     #$01ee
@blank6:
        sta     hVMDATAL
        sta     hVMDATAL
        sta     hVMDATAL
        sta     hVMDATAL
        sta     hVMDATAL
        sta     hVMDATAL
@write: lda     f:$7e0000+OT6_SHADOW,x
        sta     f:$7e0000+OT6_SHADOW+2,x         ; prev = cur
        beq     @skip           ; (n/z from the lda)
        jsr     @mark           ; the mark cell, if any (#546), and the
                                ;   address of the lead cell
        lda     f:$7e0000+OT6_HUDVEIL-1          ; veil rides the high byte
        and     #$ff00                           ;   (low byte = randbtl)
        bne     @veil
        ; hud glyph tiles unreliable? veil (hide) the hud rather than drawing
        ; from them.  a battle dialog window (window_mess_open_init, _c142e4,
        ; btlgfx_main.asm:9264) opens by ClearDlgGfxBuf-ing the whole small font
        ; and re-uploading it to $5800 in four TfrDlgTextGfx passes: a full
        ; $5800-$5fff blank plus message glyphs, which zeroes the borrowed glyph
        ; cells ($64-$79, $eb-$fd: all blank in SmallFontGfx).  the vanilla
        ; staged restore (Ot6FontRestoreMark, hooking _c143b9) fires on the
        ; dialog close only, and the window keeps re-uploading as it prints,
        ; so the tiles stay blanked from open until the close re-lay
        ; finishes, or for the whole fight if the script never issues a
        ; close.  so while a dialog window is up (w7e64d5, the open latch:
        ; _c14312 sets it, _c143cc/BattleEvent Cmd_10 re-lay then clear it)
        ; or a re-lay is mid-flight (OT6_FONTDIRTY, the close's staged
        ; restore), hold the veil: the hud is hidden (vanilla's $01ee fill,
        ; as for an entry/exit anim) rather than junk, and repaints once the
        ; tiles are whole again.  the dialog draws in $80+ letter cells,
        ; disjoint from ours.
        lda     f:$7e0000+$64d5                  ; dialog window open?
        and     #$00ff
        bne     @veil
        lda     f:$7e0000+OT6_FONTDIRTY          ; font re-lay in flight?
        and     #$00ff
        bne     @veil
        ; battlefield bg3 in 16x16 tile mode?  an animation owns the layer, so
        ; veil.  the animation inits flip the battlefield's $2105 shadow
        ; ($896f) to 16x16 bg3 tiles for an effect's run (InitAnimType's
        ; bg1-target and bg1-gfx paths, btlgfx_main.asm:26304/:26348,
        ; `ora #$40`/`ora #$50`, and the circle/mask init families
        ; :47410 `ora #$48`, :48362 `and #$f7 / ora #$40`) because the
        ; effect uses bg3 as its own canvas/color-math mask.  vanilla clears
        ; the field map first (ClearBG3TileBuf/TfrBG3Tiles) and can assume
        ; nothing of its own shows: its $01ee fill is priority-clear,
        ; underneath the opaque battle bg in every mode.  the hud cells are
        ; priority-set ($21xx), and in 16x16 mode a map cell renders at
        ; doubled size and position, pulling three neighbour tiles (char n
        ; draws n, n+1, n+$10, n+$11), so any live line inside the
        ; effect's scroll window would paint doubled break-icon blocks
        ; flanked by neighbour-tile bars over and around the monsters.
        ; while the bit is up, hold the veil: $01ee is the word vanilla wants
        ; in every cell it did not draw itself, in both tile modes.  the
        ; main loop can flip $896f mid-frame between our nmi reads; the
        ; exposure is bounded at one partial frame at effect onset.
        lda     f:$7e0000+$896f                  ; battlefield $2105 shadow
        and     #$0040                           ;   bg3 tile size 16x16?
        bne     @veil
        ; the lead cell.  a line anchored in column 0 would put it in the
        ; last column of the row above, so there it is vanilla's fill word
        lda     f:$7e0000+OT6_SHADOW,x
        and     #$001f
        beq     @edge
        phx
        tyx
        lda     f:$7e0000+OT6_HUDLEAD,x
        plx
        bra     @lead
@edge:  lda     #$01ee
@lead:  sta     hVMDATAL
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
        bra     @skip
@veil:  lda     #$01ee          ; an entry/exit anim owns bg3: vanilla's
        sta     hVMDATAL        ;   junk fill, so the scroll wave sweeps
        sta     hVMDATAL        ;   a map word-identical to vanilla's
        sta     hVMDATAL
        sta     hVMDATAL
        sta     hVMDATAL
        sta     hVMDATAL
@skip:  shorta0
        longa
        txa
        clc
        adc     #$000e
        tax
        iny
        iny
        shorta0
        cpx     #$0054          ; 6 monster lines x 14
        jcc     @line           ; (veil branch grew the body past bcc)
        ; wallet pseudo-line: current MP over the open costed list ($7c00
        ; ability-list map, single band).  the one-shot close/switch blank
        ; uses the same defer-when-late fix as the lines (a magic or item
        ; list opening over a stale wallet would show it); the steady-state
        ; cell writes rewrite every nmi like everything else here.
        ;
        ; the whole wallet+rows pass is v-gated as a unit: it grows the nmi
        ; tail to ~13 words, and on a late-entry nmi the tail can wrap past
        ; vblank.  everything here is steady-state or defer-retry, so a
        ; skipped nmi repaints in full on the next one.
@pip:
        ; wallet pseudo-line: current MP over the open costed list ($7c00
        ; ability-list map, single band).  Painted only when it changes,
        ; never per frame: a steady-state repaint every cell costs ~13 extra
        ; words a frame, enough to push the engine's own line transfers past
        ; vblank and hang the window state machines that wait on them.  A
        ; change-only write costs zero words on a quiet frame, and the value
        ; only moves on open/close and when the charge debits MP.
        longa
        lda     f:$7e0000+OT6_WALLETCUR
        cmp     f:$7e0000+OT6_WALLETPREV
        bne     @wpaint
        lda     f:$7e0000+OT6_WALLETSIG
        cmp     f:$7e0000+OT6_WALLETSIGP
        beq     @pipline                 ; unchanged: write nothing at all
@wpaint:
        shorta0
        jsr     @late
        bcs     @pipline        ; late: hold prev/sig, redo next nmi
        longa
        lda     f:$7e0000+OT6_WALLETPREV
        beq     @wcur
        cmp     f:$7e0000+OT6_WALLETCUR
        beq     @wcur
        sta     hVMADDL                  ; closed/moved: blank the old cells
        lda     #$21ff          ; $21ff: this is a menu map (no anim flips its
        sta     hVMDATAL        ;   $2105 sections to 16x16), so the field
        sta     hVMDATAL        ;   map's $01ee rule does not apply here
        sta     hVMDATAL
        sta     hVMDATAL
        sta     hVMDATAL
@wcur:  lda     f:$7e0000+OT6_WALLETSIG
        sta     f:$7e0000+OT6_WALLETSIGP
        lda     f:$7e0000+OT6_WALLETCUR
        sta     f:$7e0000+OT6_WALLETPREV
        beq     @pipline
        sta     hVMADDL
        lda     f:$7e0000+OT6_WALLETCELLS+0
        sta     hVMDATAL
        lda     f:$7e0000+OT6_WALLETCELLS+2
        sta     hVMDATAL
        lda     f:$7e0000+OT6_WALLETCELLS+4
        sta     hVMDATAL
        lda     f:$7e0000+OT6_WALLETCELLS+6
        sta     hVMDATAL
        lda     f:$7e0000+OT6_WALLETCELLS+8
        sta     hVMDATAL
@pipline:
        ; the boost cells (#540): one name row's pip cell a frame, in the
        ; party-window menu map: the lowest row Ot6PipStage marked dirty,
        ; else the next in turn, so a cell changes on the frame after its
        ; face does and a write the ppu dropped is made again within four
        ; frames (the old live cell's steady rewrite, which needed no
        ; lateness gate either).  the party window is double-buffered: each
        ; name row is staged at map row 1+2r and at 9+2r (+$100 words) and
        ; the scroll picks a band, so both are painted.  a row with no
        ; character (word 0) is left alone.
        shorta0
        lda     f:$7e0000+OT6_PIPLIVE
        beq     @pdone          ; the party window not drawn yet this battle
        ldx     #$0000
        lda     f:$7e0000+OT6_PIPDIRTY
        beq     @prr
@pbit:  lsr
        bcs     @prow
        inx
        bra     @pbit
@prr:   lda     f:$7e0000+OT6_PIPRR
        inc     a
        and     #$03
        sta     f:$7e0000+OT6_PIPRR
        tax
@prow:  lda     f:Ot6HitBitTbl,x        ; the row's bit
        eor     #$ff
        and     f:$7e0000+OT6_PIPDIRTY
        sta     f:$7e0000+OT6_PIPDIRTY
        longa
        txa
        asl
        tax                     ; the row's word index
        lda     f:$7e0000+OT6_PIPROWW,x
        beq     @pdone          ; no character on this row
        lda     f:Ot6PipRowAddr,x
        sta     f:$7e0000+OT6_PIPPREV   ; the cell painted last (H.livePipCell
        sta     hVMADDL                 ;   reads it, the old live cell's word)
        lda     f:$7e0000+OT6_PIPROWW,x
        sta     hVMDATAL
        lda     f:Ot6PipRowAddr,x
        clc
        adc     #$0100          ; ...and its band twin
        sta     hVMADDL
        lda     f:$7e0000+OT6_PIPROWW,x
        sta     hVMDATAL
        ; #563: the cell before it, the name's sixth, as the name buffer
        ; holds it: a rune's sign (Ot6RuneSignStage) or the name's own cell
        lda     f:Ot6PipRowAddr,x
        dec     a
        sta     hVMADDL
        phx
        lda     f:Ot6SignOffTbl,x
        tax
        lda     f:$7e0000+OT6_SIGN_CELL,x
        plx
        pha
        sta     hVMDATAL
        lda     f:Ot6PipRowAddr,x
        clc
        adc     #$00ff
        sta     hVMADDL
        pla
        sta     hVMDATAL
@pdone: shorta0
@out:   plb
        ply
        plx
        plp
        rtl
; local: the trap's mark cell (#546), two before the anchor.  a16 in, a =
; the line's anchor (cur), x = the shadow line base, y = the slot offset.
; A slot whose OT6_MARKCELL holds a mark has the mark's word written at
; anchor - 2 (vanilla's fill under a veil) every nmi, like the line's other
; cells, and its OT6_MARKSHOWN bit set.  A free slot writes nothing there,
; so a neighbour's line that reaches the cell keeps it, except once after a
; mark ends: that blank is a one-shot, gated like the line moves and retried
; when late.  A line anchored in column 0 or 1 has no mark cell (it would
; wrap into the row above).  Out: the vram address is the lead cell's
; (anchor - 1), a16.  Preserves x/y; clobbers a.
@mark:  .a16
        .i16
        pha                     ; [$01,s] cur
        and     #$001f
        cmp     #$0002
        bcc     @mnone          ; column 0 or 1
        shorta0
        phx                     ; [$01,s] the shadow base, [$03,s] cur
        tya
        lsr                     ; the slot (b = 0)
        tax
        lda     f:$7e0000+OT6_MARKCELL,x
        bne     @mhas
        lda     f:Ot6HitBitTbl,x
        and     f:$7e0000+OT6_MARKSHOWN
        beq     @mnone8         ; free, and nothing shown: nothing to write
        jsr     @late           ; a mark that ended: blank its cell once
        bcs     @mnone8         ; late: the bit stays, next nmi
        lda     f:Ot6HitBitTbl,x
        eor     #$ff
        and     f:$7e0000+OT6_MARKSHOWN
        sta     f:$7e0000+OT6_MARKSHOWN
        bra     @mfill
@mhas:  pha                     ; the mark
        lda     f:Ot6HitBitTbl,x
        ora     f:$7e0000+OT6_MARKSHOWN
        sta     f:$7e0000+OT6_MARKSHOWN
        pla
        asl                     ; word index (b = 0)
        tax
        lda     f:$7e0000+OT6_HUDVEIL   ; the veils the line below takes:
        ora     f:$7e0000+$64d5         ;   an entry/exit, a dialog window,
        ora     f:$7e0000+OT6_FONTDIRTY ;   a font re-lay
        bne     @mfill
        lda     f:$7e0000+$896f
        and     #$40            ;   or bg3 in 16x16 tile mode
        bne     @mfill
        longa
        lda     f:Ot6MarkWordTbl,x
        bra     @mput
@mfill: longa
        lda     #$01ee          ; vanilla's fill
@mput:  plx                     ; the shadow base
        pha                     ; [$01,s] the word, [$03,s] cur
        lda     $03,s
        dec     a
        dec     a
        sta     hVMADDL
        pla
        sta     hVMDATAL        ; the address steps on to the lead cell
        pla                     ; (cur)
        rts
@mnone8:
        plx
        longa
@mnone: pla                     ; cur
        dec     a               ; the lead cell
        sta     hVMADDL
        rts
; local: enough vblank left for a one-shot transition write? (a8, db=0;
; clobbers a; carry set = too late, defer.) constants mirror the font
; slice gate above: v must be in [225,248]; past 248 the worst-case
; transition burst (~9 scanlines at the measured PIO rate, see the
; @nofont comment) could run into active display, where the PPU drops
; VRAM writes and a one-shot has no next-frame rewrite to heal it.
        .a8                     ; (@mark above leaves the assembler a16)
@late:  lda     hSLHV           ; software-latch the h/v counters
        lda     hSTAT78         ; reset the opvct read flip-flop
        lda     hOPVCT          ; v low byte
        xba
        lda     hOPVCT          ; v bit 8 (in bit 0)
        lsr                     ; -> carry
        xba                     ; a = v low byte (xba preserves carry)
        bcs     @l1             ; v >= 256: too late (carry already set)
        cmp     #$e1
        bcc     @l0             ; v < 225: not vblank (defensive), so defer
        cmp     #$f9            ; carry = (v >= 249) = too late
        rts
@l0:    sec
@l1:    rts
.endproc

; [ l/r boost input ]

; runs every main-loop frame from the hud builder (db=$7e, a8/i16).
; while a battle menu is open and the actor's action is still being
; composed, R raises the active character's pending boost (cap 3, and
; never past their bp) and L lowers it.  Display is not here: the live
; cell painter (Ot6PipStage -> the flush's one-cell pseudo-line) points
; that cell at the active character while composing and at the character
; who just charged for a few frames after, showing the full bank either
; way, so the visible drop is Ot6ActionEnd's charge frame. window_open
; still re-stages every row on the next open (Ot6PipGlyph_ext, same bp
; reading).
;
; "still being composed" is $32cc,y = $ff, the actor's pending-action
; command-list pointer (battle_main.asm:254 sets it to $ff when nothing
; is pending; CreateNormalAction:@4ecb tests it the same way): $ff holds
; through command select, the ability list and target select, then goes
; live the instant the target is confirmed.
;
; during target select the spend is fully effective and stays legal for
; an action picked off the command window (Fight...): Ot6QueueFold reads
; pending from CreateAction, which runs after target select.  an action
; picked from a list keeps the boost the list showed there (#555, below).
; after the confirm, CreateAction has already frozen the tier,
; but Ot6ActionEnd still charges whatever pending reads at action end, so
; a spend there would be charged and buy nothing -- Ot6Boost gates input
; on Ot6CommittedSlot for exactly that reason.  Refusing silently rather
; than buzzing: the menu lingers open for a few frames after every
; confirm, so a buzz here would fire on ordinary play and teach the
; player that a legal boost had been rejected.

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
        ; the action is committed once the actor has a command-list
        ; pointer: the tier is already frozen, so a spend here would be
        ; charged and buy nothing. display only from that point on.
        ; the $32cc + $2bae-ring test lives in Ot6CommittedSlot, because
        ; the live pip painter needs the same answer per row and the two
        ; readings must not diverge.
        pha
        lda     $62ca
        and     #$03
        jsr     Ot6CommittedSlot
        bcc     :+
        pla
        rts                     ; committed: display only
        ; ...and a latched slot spin is committed the same way: the first
        ; reel press latched the spin's tier (Ot6SlotRig -> OT6_SLOTTIER)
        ; and Ot6SlotCommit re-banks that latch at the queue write, so an
        ; L/R edge mid-spin changes nothing the reels or the charge will
        ; see. input goes fully inert from the first press: no bank, no
        ; sound.
:       lda     $7bc2           ; menu state $08 = the reel spin
        cmp     #$08
        bne     :+
        lda     $7b92           ; reel-1 press latch: the spin has begun
        beq     :+
        pla
        rts                     ; latched spin: display only, silently
:       pla
        ; #555: at the target select of an action picked from a list (a
        ; spell, a lore, a summon, a kit row, a dance, an item), the boost
        ; is the one the list showed when the row was picked: its name, its
        ; price and its grey are drawn there and nowhere else, and the list
        ; stays on screen through the target select unchanged.  So L and R
        ; leave the pending boost alone here.  On a spell that can be spread
        ; over a group (MANUAL | MULTI_TARGET) they are vanilla's spread
        ; keys, and moving the boost with them cast a tier the list did not
        ; show: Fire 3 picked at 2 points, spread with L, cast Fire 2 for
        ; one (the owner, v0.47).  There they are silent; elsewhere R or L
        ; buzzes, as any refused boost does.  An action picked straight off
        ; the command window (Fight, Capture...) has no list and keeps L/R.
        pha
        lda     $7bc2
        cmp     #$38            ; target select
        bne     @free
        lda     OT6_MENU_RETURN ; the state it returns to: the picking list
        cmp     #$05            ;   ($05, the command window: no list)
        beq     @free
        pla
        and     #$30
        beq     @held           ; no L/R edge
        lda     OT6_MENU_FLAGS  ; the pick's targeting flags
        and     #$21
        cmp     #$21            ; MANUAL | MULTI_TARGET: L/R spread it
        beq     @held
        inc     $95             ; error buzz: the boost is the list's
@held:  rts
@free:  pla
        bit     #$10            ; R: boost up
        beq     @tryl
        jsl     Ot6RowNoBoost   ; #463: not on a row the boost buys nothing
        bcs     @deny           ;   on (Filch, Bestow, a status cure...)
        lda     OT6_BOOST_REVEALED,y
        inc     a
        cmp     #$04            ; spend at most 3
        bcs     @deny
        jsr     Ot6BoostRoom    ; and never past the bank, plus a Portrait
        bcc     @deny           ;   gift held (#538)
        jsl     Ot6RaiseUnpaid  ; #555: nor past what the MP pays for the
        bcs     @deny           ;   action under the cursor at that boost
@store: sta     OT6_BOOST_REVEALED,y
        inc     $6281           ; ching (spc $2c): boost committed
        bra     @refold
@deny:  inc     $95             ; error buzz: at cap or out of bp
        bra     @show
@tryl:  bit     #$20            ; L: boost down
        beq     @show
        lda     OT6_BOOST_REVEALED,y
        beq     @show
        dec     a
        sta     OT6_BOOST_REVEALED,y
        inc     $94             ; cursor click: boost taken back
@refold:
        lda     #$80
        sta     OT6_RESTAGE     ; open lists re-fold their names
        ; ...and re-price them.  The folded name was only half the
        ; row: the MP number, the grey and the A-button's refusal all read
        ; spell-list byte 3, which Ot6FoldPrices rewrites off this same
        ; pending value, and the enabled bits are then re-derived from it by
        ; vanilla's own UpdateEnabledMagic, which Ot6FoldPrices hooks into.
        ;
        ; Called directly rather than through vanilla's $3204 bit-7 request:
        ; that request is consumed in AfterAction2, "update targets after
        ; each command", so the list would re-price at the end of the next
        ; action rather than under the player's cursor.  Ot6ActionEnd still
        ; uses the request bit, because there the timing is right: an
        ; action has just ended, so AfterAction2 is next.
        ;
        ; this site is inside Ot6BgHud_ext, and the battle loop's per-frame
        ; budget is close enough to full that ~80 idle cycles cost a whole
        ; extra hardware frame.  UpdateEnabledMagic's 78-row walk is far
        ; more than 80 cycles, but it is a burst on an L/R edge rather than
        ; a per-frame cost, so the worst case is one dropped frame on the
        ; frame the player presses R.
        tya                     ; the boosting character's entity offset
        jsl     Ot6RecheckMagic
@show:  rts                     ; display is Ot6PipStage's job
@off:   rts
.endproc

; [ is there room for this pending boost? ]  in: A = the pending wanted, y =
; the character.  out: carry set = it is at most the bank plus the gift
; (Ot6BankGift).  a8/i16.  preserves A, X and Y.
.proc Ot6BoostRoom
        .a8
        .i16
        pha
        phx
        tyx
        jsl     Ot6BankGift
        plx
        cmp     $01,s           ; room - wanted: carry set iff room >= wanted
        pla
        rts
.endproc

; ------------------------------------------------------------------------------

; [ is a character slot's action committed? ]
;
; committed = the actor has a live command-list pointer ($32cc != $ff: C2
; holds the action) or the confirmed action still sits in the user-action
; ring ($2bae + 0/8/$10/$18, char slot or $ff; GetPlayerAction's ring,
; battle_main.asm:12643; the C1 confirm freezes the payload but $32cc only
; goes live when C2 drains the ring).  Ot6Boost gates input on this (a spend
; after commit is charged but buys nothing) and Ot6PipStage picks each row's
; glyph with it (a committed bank displays full until the charge lands, so
; the pip drop is the Ot6ActionEnd frame).  a8/i16, db=$7e.
; in: A = character slot (0-3).  out: carry set = committed.  preserves x/y.
.proc Ot6CommittedSlot
        .a8
        .i16
        phx
        pha                     ; slot at $01,s
        asl                     ; slot -> entity offset
        longa
        and     #$00ff
        tax
        shorta0
        lda     $32cc,x
        inc     a               ; $ff (nothing pending) -> 0
        bne     @yes
        lda     $2bae
        cmp     $01,s
        beq     @yes
        lda     $2bb6
        cmp     $01,s
        beq     @yes
        lda     $2bbe
        cmp     $01,s
        beq     @yes
        lda     $2bc6
        cmp     $01,s
        beq     @yes
        pla
        plx
        clc
        rts
@yes:   pla
        plx
        sec
        rts
.endproc

; ------------------------------------------------------------------------------

; [ deliver a deferred pip paint: the cover's point shows ]
;
; Why the paint defers and the bank does not.  Ot6CoverBP banks the True
; Knight's BP at SetCoverTarget's commit: that instruction is the block
; as the engine understands it.  But the engine's decision to retarget
; precedes the damage numeral by many frames, and a pip is meant to move
; when the thing it represents happens: what a player perceives as "the
; block" is the hit landing on the blocker rather than the retarget.
;
; So Ot6CoverBP banks the blocker's slot + 1 into OT6_PIPPEND, Ot6PipFace
; shows his row one pip short while it stands, and this proc clears it, the
; same bank-then-commit shape Ot6RvPend*/Ot6RevealCommit use for weakness
; reveals, driven off the same trigger (Ot6RevealPoll's numeral-counter
; change, ot6_break.asm).
;
; A miss paints too, and lands on the right frame without extra work.  FF6
; draws "Miss" through GfxCmd_0b, and the miss arm branches into the same tail
; that increments the numeral counter (btlgfx_main.asm:24725-24735 -> :24799),
; so the numeral frame for a missed attack is the frame the word "Miss" appears
; over the knight: the earn pays whether or not the blow connects, and this
; way it always has a display.
;
; Two callers, the second a backstop.  GfxCmd_0b returns without touching the
; counter when the numeral value is $ffff ("hide numerals", :24707-24710), and
; some scripts issue no numeral at all, so Ot6ActionEnd calls this at the end
; of every action for the reason it already calls Ot6RevealCommit: a
; pending paint must never outlive the action that banked it.
;
; a8/i16, db=$7e.  clobbers a; preserves x/y.
.proc Ot6PipPending
        .a8
        .i16
        lda     f:$7e0000+OT6_PIPPEND
        beq     @none                   ; 0 = nothing deferred
        lda     #$00                    ; the cover's point shows: Ot6PipFace
        sta     f:$7e0000+OT6_PIPPEND   ;   stops holding it back (stz has
                                        ;   no long mode)
@none:  lda     #$00                    ; and a runic absorb's point shows
        sta     f:$7e0000+OT6_BPDEFER   ;   on the same numeral (#540)
        rts
.endproc

; ------------------------------------------------------------------------------

; [ the boost display: every name row's pip cell, as the rule has it (#540) ]
;
; Each party-window name row has one cell for its character's Boost Points:
; an arrow cluster for a pending boost, else the pips of the bank.  The rule
; (owner, #540): pending points stay visible as arrows until the action that
; spends them begins, and the point a turn earns at its end is not shown
; until that character is active again.  Display only: the bank
; (OT6_BP_CLASS) and the pending boost (OT6_BOOST_REVEALED) move when the
; rules say, and every rule reads them; Ot6PipFace derives the cell:
;   - pending and the action not begun (OT6_BPMARK's low nibble): the arrows;
;   - else the pips of the bank, less the pending once the action has begun
;     (the spend is charged at its end, Ot6ActionEnd), less the regen point
;     not yet shown (OT6_BPMARK's high nibble: set by Ot6ActionEnd's gain,
;     cleared when the character's window opens or its next turn begins), less
;     a cover or absorb point whose blow has not landed yet (OT6_PIPPEND,
;     OT6_BPDEFER: cleared on the damage numeral or the script's end).
; This proc stages all four rows every main-loop frame into OT6_PIPROWW and
; marks a row dirty when its word changes; the nmi flush writes the dirty
; rows into both bands of the party window.  The menu engine's own staging
; of a row (Ot6PipGlyph_ext, at every window open) reads the same face and
; marks the row dirty, so the two never disagree for longer than a frame.
; The active character's arrows pulse while its action is still being
; composed (Ot6CommittedSlot clear), as before.
; a8/i16, db=$7e (Ot6BgHud_ext's context).  clobbers a; preserves x/y.
.proc Ot6PipStage
        .a8
        .i16
        phx                     ; preserved from the top
        phy
        jsr     Ot6BpWindowSeen ; a window open: its earned point shows
        lda     OT6_PIPLIVE
        beq     @out            ; the party window not drawn yet this battle
        ldx     #$0000          ; menu row * 2
@row:   longa
        txa
        lsr
        tay
        shorta0
        lda     $64d6,y         ; menu row -> character slot
        cmp     #$ff
        bne     :+
        longa                   ; no character on this row: the flush
        stz     OT6_PIPROWW,x   ;   leaves its cell alone
        shorta0
        bra     @next
:       pha
        tya                     ; the menu row
        jsr     Ot6RuneSignStage ; #563: the rune's sign beside the name
        pla
        pha                     ; [$02,s] the slot
        jsr     Ot6PipFace      ; a = tile, b = attribute; carry = arrows
        pha                     ; [$01,s] the tile
        bcc     @calm
        lda     $7bca           ; arrows: pulse while the active character
        beq     @calm           ;   is still composing its action
        lda     $62ca
        and     #$03
        cmp     $02,s
        bne     @calm
        lda     $02,s
        jsr     Ot6CommittedSlot
        bcs     @calm
        lda     $0e             ; frame counter: pulse every 8 frames,
        and     #$08            ;   palette 2 (yellow) <-> 0 (white)
        ora     #$21
        bra     @attr
@calm:  lda     #$21
@attr:  xba
        pla                     ; a = the tile, b = the attribute
        longa
        cmp     OT6_PIPROWW,x
        beq     @same
        sta     OT6_PIPROWW,x
        shorta0
        lda     f:Ot6CharBitTbl,x
        tsb     OT6_PIPDIRTY
@same:  shorta0
        pla
@next:  inx
        inx
        cpx     #$0008
        bcc     @row
@out:   ply
        plx
        rts
.endproc

; [ one character's boost cell ]  a = character slot (0-3) -> a = the
; cell's tile, b = its attribute ($21), carry set when it is the arrows.
; a8/i16, any db (long reads only).  preserves x/y.
; [ a window open: its character is active, so its earned point shows ]
;
; Clears the open window's character's high nibble of OT6_BPMARK (its regen
; point not yet shown).  Called once a frame by Ot6PipStage and once a row by
; Ot6PipGlyph_ext, before each reads Ot6PipFace, so the menu engine's own
; staging of a row at the window's open (Ot6PipGlyph_ext, through the text
; engine) reads the same face as Ot6PipStage: before, the text engine could
; stage the row in the frame the window opened, before Ot6PipStage's clear,
; and its copy of the party window then overwrote the flush's cell for six
; frames (battle_bpdisplay at be80 on v0.46's replay: "f4078 row 0 (slot 0):
; shows p0, the rule says p1", build/attempts/wt/v046-land/replay1/bpdbg.log).
; a8/i16, any db (long reads only).  preserves x/y; clobbers a (b = 0).
.proc Ot6BpWindowSeen
        .a8
        .i16
        lda     f:$7e7bca
        bne     Ot6BpWindowOpen
        rts
.endproc

; [ #548: a window is opening for $62ca's character ]  the same clear,
; without asking $7bca: window_open stages the names (Ot6WindowOpenNames_ext)
; before it sets $7bca, and a row staged then with the point still withheld
; was copied over the flush's for a few frames (battle_bpdisplay's
; reversions: `f2702 PipGlyph 7bca=00 62ca=03 mark=E0` stages row 3 at p1,
; then the flush's p2, then p1 again; build/attempts/wt/v050-multihit-anim/).
; a8/i16, any db.  preserves x/y; clobbers a (b = 0).
.proc Ot6BpWindowOpen
        .a8
        .i16
        phx
        lda     f:$7e62ca
        and     #$03
        asl
        longa
        and     #$0006
        tax
        shorta0
        lda     f:Ot6CharBitTbl,x
        asl
        asl
        asl
        asl
        eor     #$ff
        and     f:$7e0000+OT6_BPMARK
        sta     f:$7e0000+OT6_BPMARK
        plx
        rts
.endproc


.proc Ot6PipFace
        .a8
        .i16
        phx
        and     #$03
        asl
        longa
        and     #$0006
        tax                     ; x = entity offset
        shorta0
        lda     f:Ot6CharBitTbl,x
        pha                     ; [$01,s] the slot's begun bit
        lda     f:$7e0000+OT6_BOOST_REVEALED,x
        beq     @pips           ; nothing pending
        lda     f:$7e0000+OT6_BPMARK
        and     $01,s
        bne     @pips           ; the action has begun: the spend shows
        lda     f:$7e0000+OT6_BOOST_REVEALED,x
        cmp     #$04
        bcc     :+
        lda     #$03
:       longa
        and     #$00ff
        tax
        shorta0
        pla                     ; drop the bit
        lda     f:Ot6ArrowCellTbl-1,x
        xba
        lda     #$21
        xba
        plx
        sec
        rts
@pips:  lda     f:$7e0000+OT6_BP_CLASS,x
        pha                     ; [$01,s] the count, [$02,s] the bit
        lda     f:$7e0000+OT6_BPMARK
        and     $02,s
        beq     :+              ; not begun: no spend to show
        jsr     Ot6PaidPending  ; the points it pays: a gift's is not
        eor     #$ff            ;   a pip (#538)
        sec
        adc     $01,s           ; the count less the paid points
        sta     $01,s
:       lda     $02,s
        asl
        asl
        asl
        asl                     ; its owed bit
        and     f:$7e0000+OT6_BPMARK
        beq     :+
        lda     $01,s           ; the regen point, not shown yet
        dec     a
        sta     $01,s
:       lda     $02,s
        and     f:$7e0000+OT6_BPDEFER
        beq     :+
        lda     $01,s           ; an absorb's point, its spell not landed
        dec     a
        sta     $01,s
:       txa
        lsr
        inc     a
        cmp     f:$7e0000+OT6_PIPPEND
        bne     :+
        lda     $01,s           ; a cover's point, its blow not landed
        dec     a
        sta     $01,s
:       pla
        bpl     :+
        lda     #$00            ; (never below empty)
:       cmp     #$06
        bcc     :+
        lda     #$05
:       longa
        and     #$00ff
        tax
        shorta0
        pla                     ; drop the bit
        lda     #$21
        xba
        lda     f:Ot6PipCellTbl,x
        plx
        clc
        rts
.endproc

; character bits by entity offset (stride 2), and the pip rows' bits by
; row word index: one table for both
Ot6CharBitTbl:
        .byte   $01,$00,$02,$00,$04,$00,$08,$00

; a name row's pip cell in the party-window map: $7800 + (1 + row*2)*32 + 20
Ot6PipRowAddr:
        .word   $7834,$7874,$78b4,$78f4

; ------------------------------------------------------------------------------

; [ stage the costed-list MP wallet: current MP where the costs are ]
;
; while a costed ability list is open (the tools shell, menu state $30:
; Blitz, Bushido, and real Tools, or the Dance list) the actor's
; current MP is painted as [M][P][d][d][d] into the list window's top row,
; right side: map words $7c16-$7c1a, i.e. row 0 cols 22-26 of the $7c00
; ability-list map (the list rows stage at $7c00 rows 1/3/5/7 cols 2-26,
; row 0 is never staged and renders legibly on the window's top edge).
; the value is read from $3c08, the cell CalcAttackEffect's universal
; charge debits, so the wallet drops on the frame the queued verb's cost
; is paid.  cells stage here in the main loop; the nmi flush paints them
; every frame and one-shot-blanks on close/switch, so a follow-up Magic or
; Item list never inherits a stale wallet.
; a8/i16, db=$7e.  clobbers a; preserves x/y.
.proc Ot6WalletStage
        .a8
        .i16
        lda     $7bca           ; battle menu open?
        beq     @off
        lda     $7bc2           ; menu state
        cmp     #$30            ; tools shell browse (blitz/bushido/tools)
        beq     @on
        cmp     #$21            ; dance list browse (open $1f -> browse $21)
        beq     @on
@off:   longa
        clr_a
        sta     f:$7e0000+OT6_WALLETCUR
        shorta0
        rts
@on:    phx
        phy
        lda     $62ca           ; active character slot -> entity offset
        and     #$03
        asl
        longa
        and     #$00ff
        tax
        lda     $3c08,x         ; current MP: the charge's own cell
        cmp     #999+1
        bcc     :+
        lda     #999            ; display cap (three digits)
:       sta     OT6_SCR_IDX     ; 16-bit scratch (walkers own the even words)
        sta     f:$7e0000+OT6_WALLETSIG  ; content signature for the flush's
                                ;   change-only paint (the digits below are
                                ;   a pure function of this value)
        ; letters: 'M' 'P', white ($8c/$8f: the battle list font's M and P)
        lda     #$218c
        sta     f:$7e0000+OT6_WALLETCELLS+0
        lda     #$218f
        sta     f:$7e0000+OT6_WALLETCELLS+2
        shorta0
        lda     #$00
        sta     OT6_SCR_COLS    ; leading-zero latch (0 = still leading)
        ; hundreds
        ldy     #$0000
        longa
        lda     OT6_SCR_IDX
@h:     cmp     #100
        bcc     :+
        sbc     #100            ; (carry set by the cmp)
        iny
        bra     @h
:       sta     OT6_SCR_IDX     ; remainder < 100
        shorta                  ; plain SEP #$20 (shorta0's tdc would eat A)
        .a8
        tya                     ; hundreds digit 0-9
        jsr     @digit
        sta     f:$7e0000+OT6_WALLETCELLS+4
        lda     #$21
        sta     f:$7e0000+OT6_WALLETCELLS+5
        ; tens
        ldy     #$0000
        lda     OT6_SCR_IDX     ; remainder (< 100: the low byte is whole)
@t:     cmp     #10
        bcc     :+
        sbc     #10
        iny
        bra     @t
:       sta     OT6_SCR_IDX     ; ones
        tya                     ; tens digit 0-9
        jsr     @digit
        sta     f:$7e0000+OT6_WALLETCELLS+6
        lda     #$21
        sta     f:$7e0000+OT6_WALLETCELLS+7
        lda     OT6_SCR_IDX     ; ones digit: always drawn
        clc
        adc     #$b4            ; small-font digits $b4-$bd
        sta     f:$7e0000+OT6_WALLETCELLS+8
        lda     #$21
        sta     f:$7e0000+OT6_WALLETCELLS+9
        longa
        lda     #$7c16          ; row 0 col 22 of the $7c00 list map
        sta     f:$7e0000+OT6_WALLETCUR
        shorta0
        ply
        plx
        rts
; digit 0-9 in A -> glyph byte, blanking leading zeros; latch OT6_SCR_COLS
@digit: cmp     #$00
        bne     @dig
        lda     OT6_SCR_COLS
        beq     @blank
        lda     #$b4            ; an interior zero draws
        rts
@blank: lda     #$ff            ; a leading zero is a blank cell
        rts
@dig:   pha
        lda     #$01
        sta     OT6_SCR_COLS
        pla
        clc
        adc     #$b4
        rts
.endproc

; ------------------------------------------------------------------------------

; [ re-render an open ability list when what it draws has moved ]

; polled once per frame from the battle main loop just before the
; menu-text pump. runs menu state $0d's work (clear the line
; transfer buffer, stage the four visible row-pairs from the scroll
; top, arm each line's vram transfer) without its completion
; transitions, which queue window-flow steps that eventually walk
; the window shut; re-entering the state closed the window. the
; re-staged rows run through Ot6PreviewList_ext, so the
; fold preview redraws with the current pending; the window stays
; parked in browse the whole time. a8/i16, db = $7e.
;
; Two windows are served.  The magic list (browse state $0e) is where
; a boost moved, so the folded names and their re-derived prices have to
; follow.  The kit window (browse state $30: Tools, Blitz, SwdTech, Steal) is
; the same problem with a different input, the BP bank: Ot6BushidoRowGrey
; greys a row whose boost exceeds the caster's bank, and that grey was read
; once at window open and never again, so a bank that moved behind an open
; window (a cover, a Runic absorb, a Bestow, or the caster's own action
; charging) left the window claiming a row was reachable when the confirm
; would refuse it, or greyed when it would not.
;
; The two share this proc rather than each getting one, because the staging
; they need is the same four-line cycle over the same shared bytes -- $7ba5
; (the staging latch), $7ba6 (the draw cursor) and $7ba9 (the queued line
; transfer).  Two gates driving those independently would have to agree about
; who owns the latch.  Only two things differ per
; window: which cursor holds the scroll top ($8913 magic / $895f kit, read off
; the same 16-bit `ldx $62ca` both vanilla openers use) and which C1 row
; drawer stages a line.
;
; The kit window's own opener is MakeToolsList_04 (btlgfx_main.asm:13195) and
; it does exactly what the magic arm does: _c15a17, the scroll top into $7ba6,
; $7ba5 = $80, then DrawToolsListText / _c15729 per tick.  It carries no
; per-open setup of its own (the magic opener's `jsr _c18414` spell-list
; pointer has no counterpart), so a re-stage from here needs nothing the
; magic arm did not already need.

; the staging routines are jsr-linkage C1 locals; call them from here
; with the rts->rtl thunk: [bank][ret16][thunk16] on the stack, then jml;
; their rts lands on Ot6C1Rtl, whose rtl returns here.
.macro jsr_c1 target
        phk
        pea     :+ -1
        pea     .loword(Ot6C1Rtl)-1
        jml     f:target
:
.endmacro

; flag protocol: 0 idle, $80 fresh request (Ot6Boost, and every writer of a
; character's BP bank), 1-3 lines left in an active cycle. one line per frame:
; the nmi's _c15d99 drains a single $80-byte line buffer ($5e4d) per frame,
; which is exactly why vanilla's state $0d stages one row-pair per tick.
;
; A request nobody can consume is dropped on the spot, and that is a
; performance requirement rather than tidiness.  This proc is polled once per
; battle frame from bank C1's frame loop (btlgfx_main.asm:1749); the battle
; loop's per-iteration budget is nearly full, and going over costs a missed
; vblank on every iteration.  So the byte's resting value is what the
; budget is set by, and it has to come back to zero promptly.
;
; What is given up: a request raised on a frame when the list is not browsing
; (mid-scroll, $7bc2 = $17/$18; mid-open, $0d) is dropped instead of held for
; the browse state that follows.  That is acceptable because the behavioural
; half of a boost edge does not ride on this byte at all -- Ot6Boost calls
; Ot6RecheckMagic on the same instruction stream, so prices, greys and the
; A-button's refusal are already correct -- and because both of those states
; are staging the rows themselves, from live data, while they run.  The
; residue is that row-pairs staged before the press keep the old fold until
; the next press or the next open, which is cosmetic and self-healing.

.proc Ot6RestageGate_ext
        .a8
        .i16
        lda     f:$7e0000+OT6_RESTAGE
        beq     @no
        lda     $7bca           ; menu closed: stale flag
        beq     @drop
        lda     $7bc2           ; the per-frame menu state: $0e = magic list,
        cmp     #$0e            ;   $30 = kit window; either one up and
        beq     @browse         ;   browsing (idle machinery).  in any other
        cmp     #$30            ;   state nothing can consume a request, so
        bne     @drop           ;   drop it rather than hold it
@browse:
        lda     $7ba9           ; a line transfer is still queued:
        bne     @no             ; let the nmi drain it first
        lda     f:$7e0000+OT6_RESTAGE
        bmi     @fresh
        ; mid-cycle: stage the next line
        jsr     @draw
        bcs     @drop           ; fourth line: cycle complete
        lda     f:$7e0000+OT6_RESTAGE
        dec
        sta     f:$7e0000+OT6_RESTAGE
        rtl
@fresh: phx
        jsr_c1  _c15a17         ; clear the line transfer buffer
        ldx     $62ca           ; active character slot (both vanilla openers
                                ;   do this same 16-bit ldx)
        lda     $7bc2
        cmp     #$0e
        bne     @kittop
        lda     $8913,x         ; magic list scroll top (OpenMagicWindow's)
        bra     @havetop
@kittop:
        lda     $895f,x         ; kit window scroll top (MakeToolsList_04's)
@havetop:
        sta     $7ba6           ; draw cursor = this list's scroll top
        lda     #$80
        sta     $7ba5           ; reset the 4-line staging cycle
        plx
        jsr     @draw           ; line one, now
        lda     #$03            ; three more, one per frame
        sta     f:$7e0000+OT6_RESTAGE
        rtl
@drop:  lda     f:$7e0000+OT6_RESTAGE
        bmi     :+              ; $80 = cycle never started: $7ba5 not ours
        ; a started cycle (flag 1-3) ends here, complete or abandoned.  the
        ; staging byte $7ba5 is shared: every window-open state trusts
        ; `lda $7ba5 / bmi` to mean "my own init already ran" (OpenMagicWindow
        ; @57c4, MakeToolsList_04 @58be, ...).  an abandoned cycle leaves it
        ; at $81-$83, so the next list to open skips its init and draws only
        ; the cycle's remaining 4-n lines over n stale magic rows.  hand the
        ; byte back closed; a complete cycle already left it 0 and the stz
        ; is a no-op.
        stz     $7ba5
:       lda     #$00            ; cycle complete (or abandoned mid-way)
        sta     f:$7e0000+OT6_RESTAGE
@no:    rtl
        ; stage one row-pair and arm its transfer; carry = list done.  the
        ; browse state is re-read here rather than latched at @fresh: it
        ; cannot change under a running cycle without the gate above sending
        ; that cycle to @drop first, and a latch would need a byte of RAM to
        ; say something $7bc2 already says.
@draw:  lda     $7bc2
        cmp     #$0e
        bne     @drawkit
        lda     $7ba6
        jsr_c1  DrawMagicListText
        bra     @drawn
@drawkit:
        lda     $7ba6
        jsr_c1  DrawToolsListText
@drawn: jsr_c1  _c15729
        rts
.endproc

; [ bp pip glyph for the party window name row ]

; menu text command $13, reached from template $01 (character names) only.
; +$4a = staging pointer w7e5b95 + row*28, so the menu row is recoverable
; without trusting any earlier command's state. empty rows draw blank.
; The cell is Ot6PipFace's (#540), the one the live stage draws; the row's
; word is refreshed and marked dirty, so the flush lays the same word (its
; pulse included) over whatever the engine stages, and the live stage starts
; once a row has been drawn this battle (OT6_PIPLIVE).

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
:       txa                     ; the menu row: the engine has just staged
        jsr     Ot6RuneSignStage ;  its name, so the rune's sign goes back
                                ;   beside it (#563)
        lda     f:$7e64d6,x     ; menu row -> character slot
        cmp     #$ff
        beq     @blank
        pha                     ; [$01,s] the slot
        jsr     Ot6BpWindowSeen ; a window open: its earned point shows
        longa
        txa
        asl
        tax                     ; the row's word index
        shorta0
        pla
        jsr     Ot6PipFace      ; a = tile, b = attribute
        pha
        longa
        sta     f:$7e0000+OT6_PIPROWW,x
        shorta
        lda     f:Ot6CharBitTbl,x
        ora     f:$7e0000+OT6_PIPDIRTY
        sta     f:$7e0000+OT6_PIPDIRTY
        lda     #$01
        sta     f:$7e0000+OT6_PIPLIVE
        tdc                     ; b = 0, as the text engine's 16-bit reads of
        pla                     ;   a expect (the old body left it so); a =
        plx                     ;   the tile
        rtl
@blank: lda     #$ff
        plx
        rtl
.endproc

; per-species shield + class-weakness overrides: bosses get authored
; counts, marked trash gets flavor, and shields 0 means explicitly
; shieldless (no display; whelk's shell stays the wrong answer, as
; vanilla intended, and scripted set-pieces draw no gauge, so a blank hud
; means the fight is not a break fight). format: .word species id (monster
; prop offset / 32), .byte shields, .byte class weaknesses; $ffff
; terminates.  unlisted species use the 2 + level/8 formula and carry no
; class weakness. elemental rows are not here: vanilla element bits stay in
; monster data.
;   - guardian/tritoch: multiple records each.  guardian's $0111 (battle
;     75) is drawn shieldless; $0112 is kefka's tower's guardian (battle
;     140; battle 76, its other group, is never called) and has a real row
;     (the kefka's tower block).
;     tritoch's $0144 is the World of Ruin's (only battle 119 reaches it)
;     and has a real row (the narshe block).
;
; kefka at narshe has one row ($14a; the final battle's kefka, $12a, is
; its own record, in the end block); the imperial camp gags need none: MONSTER::KEFKA_NARSHE
; ($14a, const.inc:1222) appears in exactly two formation records (489,
; 505), and `battle 57` -> group 57 -> 505 is the narshe defense.  the
; camp gags run `battle 56` (event_main.asm:40683/:40743) -> group 56,
; whose formation (504) has no monster in it: present mask $00, all
; sentinel id slots (battle_monsters.dat +$1d88).  nothing is loaded, so
; Ot6SeedShields never sees them.  those fights run on character ai
; instead (battle_prop.dat +$7e0, script kefka_imp_camp_1): the event
; dresses a party slot as Kefka (char_prop VICKS/KEFKA_1) and revives it
; between rounds, because he has character hp.  gauging a character actor
; would be a per-formation feature, not a table row.
Ot6ShieldTbl:
        ; narshe intro / escape
        .word   $0000
        .byte   2, OT6_RANGED ; guard, the TekMissile probe (Bio Blast's poison is the element)
                                ;   (opening.md 1).  poison vanilla
        .word   $0019
        .byte   3, OT6_DAGGER|OT6_SPEAR ; lobo; the old pierce was LOCKE's dirk and the moogles'
                                ;   pikes, two classes now, and the school's practice chest
                                ;   meets it with two daggers (opening.md 1,3,4). fire vanilla
        .word   $0100
        .byte   0, $00 ; whelk (the shell)
        .word   $0134
        .byte   4, OT6_RANGED ; Whelk's head, 'three beams and a TekMissile' (bosses-wob.md 1)
                                ;   (opening.md 1).  fire an ot6 add
                                ;   $0134 'Head' is the narshe fight; $0135 is the WoR
                                ;   presenter's head
        .word   $0064
        .byte   4, OT6_DAGGER|OT6_SPEAR ; marshal; 'moogle spears chip him' and LOCKE's dirk did
                                ;   under pierce (bosses-wob.md 2): both classes, so the thief
                                ;   the player controls holds a key on the boss (opening.md 3).
                                ;   poison vanilla
        ; mt. kolts / lete river
        ; ---- mt. kolts trash: two shields lets the break land before the
        ; monster is already spent (the breaking hit is 4x base through the
        ; element channel, 2x through the class one; the formula's 3 lands
        ; the break on a corpse, and 1 is too few against the element
        ; channel: 4x base exceeds a 270-hp tusker outright).
        .word   $000b
        .byte   2, OT6_SWORD|OT6_BLUNT ; brawler: the blades (it drinks the Bio Blaster's
                                ;   poison), and SABIN's fists: the first two maps he walks deal
                                ;   it, and his MetalKnuckle, a claw through v0.50, keyed it
                                ;   (opening.md 8).  ice vanilla; absorbs poison
        ; (cirpius $0086 lived here as a shields-only row through v0.16;
        ; its row is now the keyed one in the break-dark block below --
        ; Ot6SeedShields takes the FIRST match, so a species may appear
        ; in this table once.  tools/check_shield_rows.py gates that.)
        .word   $007a
        .byte   2, $00 ; tusker: no weapon weakness, as on main; Fire or the Bio Blaster
                                ;   (opening.md 8).  fire vanilla; poison an ot6 add
                                ; an Ot6ShieldTbl row also exempts its
                                ; species from Ot6HpScale (inert today,
                                ; every band ships $10 = 1x); where a
                                ; species needs a weakness but not a shield
                                ; count, Ot6ElemAddTbl is the row that
                                ; avoids that exemption.
        .word   $0103
        .byte   5, OT6_BLUNT ; vargas: 'not breakable without the monk'; SABIN's Pummel and now
                                ;   his MetalKnuckle too (opening.md 8).  poison vanilla; holy
                                ;   an ot6 add
        .word   $014d
        .byte   2, OT6_SWORD ; ipooh: 'fire + slashing' (bosses-wob.md 3), TERRA's and EDGAR's
                                ;   swords (opening.md 8).  fire vanilla
        .word   $012c
        .byte   5, OT6_SWORD|OT6_RANGED ; ultros, 'the row he keeps all game': the Lete's party
                                ;   holds two swords and the AutoCrossbow (no pike, no dagger);
                                ;   fire and bolt take the other two cells (opening.md 9).
                                ;   fire|bolt vanilla; absorbs water
        .word   $0104
        .byte   5, OT6_DAGGER ; tunnelarmor: Trickshot and his dagger; CELES's key is Ice
                                ;   (bosses-wob.md 5) (opening.md 10b).  bolt|water vanilla; ice
                                ;   an ot6 add
        .word   $014a
        .byte   6, OT6_SWORD|OT6_DAGGER ; kefka: 'any squad you route to him can break him'
                                ;   (bosses-wob.md 10): the swords, the daggers and fangs; fire
                                ;   and poison take the other two cells, so the katana has none
                                ;   (opening.md 11).  fire|poison an ot6 add
                                ;   the Narshe defense record only (MONSTER::KEFKA_NARSHE); the
                                ;   imperial camp gags carry no monster entity at all (see the
                                ;   block comment)
        .word   $0044
        .byte   4, OT6_DAGGER|OT6_BLUNT ; telstar: 'bolt, water + bludgeoning' (bosses-wob.md 6-7)
                                ;   (opening.md 10c).  bolt|water vanilla
        .word   $001a
        .byte   2, OT6_DAGGER|OT6_BLUNT ; doberman: as the templar; a x3 pack of 465 HP with no
                                ;   key for SABIN alone was the camp's slog (opening.md 10c).
                                ;   fire vanilla
        .word   $0106
        .byte   4, OT6_BLUNT ; ghosttrain: Pummel and SABIN's knuckle; 'CYAN cannot chip his own
                                ;   scenario's boss' (bosses-wob.md 8) (opening.md 10c).
                                ;   fire|bolt|holy vanilla; absorbs poison
                                ;   4 shields (was 6), #400
        .word   $0155
        .byte   4, OT6_KATANA|OT6_BLUNT ; rizopas: 'both weapons match the row' (bosses-wob.md
                                ;   9) (opening.md 10c).  bolt vanilla; absorbs water
        .word   $0154
        .byte   1, OT6_KATANA|OT6_BLUNT ; piranha: both hands at the falls (opening.md 10c).
                                ;   bolt vanilla
        ; class rows below give a weapon class to species whose forced
        ; party cannot reach any vanilla/added element (class chips ignore
        ; absorb/null).  shields track the early-war trash/miniboss tier
        ; (2 basic, 3 elite).  note the trade: an Ot6ShieldTbl row exempts a
        ; species from Ot6HpScale, which the armor-line ElemAddTbl block deliberately
        ; avoided, but a class weakness has nowhere else to live, so
        ; per-party breakability takes that trade here (HpScale ships 1x,
        ; inert today). palette (opening.md 10b, 10c, 11): the camp's bodies
        ; all take a blow, since SABIN can walk it alone (blunt); CYAN's solo
        ; duel is katana; LOCKE's solo bodies are dagger; the Narshe raiders
        ; take sword, dagger and katana, whatever squad meets them.
        ;
        ; -- imperial soldier line --
        .word   $0001
        .byte   2, OT6_KATANA|OT6_BLUNT ; soldier: CYAN's duel (katana), SABIN at the camp
                                ;   (fists); Blunt is no child of slash|pierce, and SHADOW's
                                ;   point is optional (opening.md 10c).  poison vanilla
        .word   $0002
        .byte   3, OT6_DAGGER|OT6_BLUNT ; templar: the old pierce was only SHADOW's, an optional
                                ;   hire; his blade in hand keeps it and SABIN's fists dent the
                                ;   plate (opening.md 10c).  poison vanilla; bolt an ot6 add
        .word   $014e
        .byte   3, OT6_KATANA ; leader: CYAN's solo duel (opening.md 10c).  no element
        .word   $014f
        .byte   2, OT6_KATANA|OT6_BLUNT ; grunt: CYAN and SABIN at the camp (opening.md 10c).
                                ;   no element
        .word   $0176
        .byte   3, OT6_KATANA|OT6_BLUNT ; cadet: the same two, a bigger body (opening.md 10c).
                                ;   poison vanilla
        .word   $0175
        .byte   2, OT6_DAGGER ; officer: LOCKE alone (opening.md 10b).  poison vanilla
        .word   $0065
        .byte   2, OT6_SWORD|OT6_DAGGER|OT6_KATANA ; trooper: the player forms the three squads
                                ;   freely, so a raider takes the hands of all but two of the
                                ;   seven: swords, daggers and fangs, the katana (opening.md
                                ;   11).  poison vanilla
        .word   $003f
        .byte   3, OT6_DAGGER|OT6_KATANA ; rider: 'slash for CYAN/SABIN, pierce for LOCKE/GAU'
                                ;   (bosses-wob.md, the soldier line); TERRA's Fire, EDGAR's
                                ;   poison (opening.md 11).  fire|poison vanilla
        .word   $009f
        .byte   3, OT6_DAGGER ; heavyarmor: LOCKE alone (the seam); one class, since bolt, water
                                ;   and poison leave the HUD's four cells one (opening.md 10b,
                                ;   11). bolt|water vanilla; poison an ot6 add
        .word   $013a
        .byte   2, OT6_DAGGER ; merchant: LOCKE alone (opening.md 10b).  no element
        ; -- Serpent Trench (Sabin + Cyan + Gau): three aquatics, three keys,
        ; one a member (opening.md 10c4). Gau cannot equip a weapon on this
        ; scenario (his only legal one, the Imp Halberd, is a WoB-late
        ; treasure stocked by no shop, ot6_class.asm) and his bare-handed
        ; Fight is his fangs, a dagger; Sabin brings Pummel, Suplex and his
        ; knuckle (blunt; a Mithril Claw from Mobliz's shop is a katana);
        ; Cyan brings katanas and SwdTechs. all three absorb water and their
        ; vanilla element is dead or L15-gated for this party, so class is
        ; the only reliable break.
        .word   $003a
        .byte   2, OT6_KATANA ; anguiform (the trench): cut by CYAN's blade (opening.md 10c).
                                ;   bolt vanilla; absorbs water
        .word   $005e
        .byte   2, OT6_BLUNT ; actaneon: cracked by SABIN's fists and Blitzes (opening.md 10c).
                                ;   fire|bolt vanilla; absorbs water
        .word   $0059
        .byte   2, OT6_DAGGER ; aspik: GAU's fangs, the trench's third key for its third member
                                ;   (his bare hand was bludgeon through v0.50; Dagger is no child of
                                ;   bludgeon) (opening.md 10c).  fire vanilla; absorbs water
        ; zozo / opera / the factory
        ; ---- zozo town: the four street thugs (slamdancer $0052,
        ; harvester $004e, hadesgigas $0053, gabbldegak $00df) had four
        ; shields-only rows HERE through v0.16: the search-for-terra party
        ; (Locke+Celes+Edgar+Sabin) has no native fire; every town thug is
        ; already poison-weak in vanilla, so poison via Edgar's bio blaster
        ; was the town's break key (bio's group target chips the whole
        ; gabbldegak pack at once).  Those rows shadowed the keyed rows in
        ; the break-dark block below (first match wins, ot6_break.asm
        ; Ot6SeedShields), which is why the class keys never seeded
        ; (issue #157).  The rows now live there, once: Bio Blaster
        ; remains the key it always was; the class keys add to it.
        .word   $0107
        .byte   6, OT6_DAGGER|OT6_BLUNT ; dadaluma: 'every possible pick of four holds at least
                                ;   one of the two classes' (bosses-wob.md 11): LOCKE, GAU and
                                ;   SABIN are three of the six (opening.md 12). poison vanilla
        .word   $006c
        .byte   2, OT6_BLUNT|OT6_RANGED ; iron fist: 'AoE piercing (AutoCrossbow)' on Dadaluma's
                                ;   adds (bosses-wob.md 11), and SABIN's fists (opening.md 12).
                                ;   absorbs poison; no element
        ; the opera's timed rafter chase forces Locke + Edgar + Sabin through
        ; packs of as many as five rats: two shields (the early-trash count
        ; used at Kolts and Zozo) keeps the break window part of the chase.
        ; each row's two are carried by the forced party (autocrossbow or
        ; dagger, and Pummel); no element is reachable here.
        .word   $0073
        .byte   2, OT6_SPEAR|OT6_BLUNT ; sewer rat
        .word   $00d1
        .byte   2, OT6_SPEAR|OT6_BLUNT ; vermin
        .word   $012d
        .byte   6, OT6_SWORD|OT6_RANGED ; ultros 2: same row, one more shield
        .word   $0109
        .byte   6, OT6_DAGGER ; ifrit
        .word   $0108
        .byte   6, OT6_SWORD ; shiva
        .word   $010a
        .byte   7, OT6_SWORD|OT6_DAGGER ; number 024: the classes are the
                                ;   handhold while wallchange spins
        .word   $010b
        .byte   7, OT6_DAGGER ; number 128 (body)
        .word   $013f
        .byte   3, OT6_KATANA ; right blade
        .word   $0140
        .byte   3, OT6_KATANA ; left blade
        .word   $010d
        .byte   6, OT6_DAGGER ; crane (element sides verified at m6 entry)
        .word   $010e
        .byte   6, OT6_DAGGER ; crane
        ; ---- Vector / Magitek Factory random pool: ranged carries most
        ; of the section (vanilla already labels six of the ten random-pool
        ; bodies as machines, a `Program NN` special-attack name), dagger is
        ; the imperial line's key, and a sword or a dagger takes the
        ; section's one soft body.  Rhinox (formation $168) has no vanilla
        ; weakness and absorbs bolt ($075 +$17 = $04), the element the rest
        ; of the facility teaches, so it is the one body only Ranged answers.
        ; shield counts: all twelve at 2 against a formula value of 4.
        .word   $00cb
        .byte   2, OT6_SPEAR|OT6_RANGED ; garm: a magitek quadruped
                                ;   (Program 95) rather than a hound: spear the
                                ;   joints or cave the housing. commonest
                                ;   body at the entrance, where the section
                                ;   teaches its rule, so it teaches both
                                ;   halves. keeps vanilla bolt|water
        .word   $00c7
        .byte   2, OT6_DAGGER ; commando: imperial rank keeps the imperial
                                ;   answer: templar $0002 and officer
                                ;   $0175 are both dagger above, so this is
                                ;   consistent with them
        .word   $0165
        .byte   2, OT6_RANGED ; protoarmor: a sealed suit has no seam to
                                ;   put a point in, so it dents. vanilla
                                ;   bolt stays the ranged key
        .word   $0041
        .byte   2, OT6_DAGGER ; pipsqueak: the swarm body (up to x5);
                                ;   spear so Edgar's AutoCrossbow (whole
                                ;   enemy side) answers a five-stack
        .word   $0047
        .byte   2, OT6_RANGED ; flan: an ooze cannot be cut. its element
                                ;   is fire (Flame Sabre / Ifrit's magicite)
        .word   $0066
        .byte   2, OT6_SPEAR|OT6_RANGED ; general: an officer in plate.
                                ;   vanilla poison answers him if Edgar was
                                ;   picked (Bio Blaster); the class row makes
                                ;   him breakable otherwise
        .word   $002d
        .byte   2, OT6_RANGED ; trapper: a fixed trap mechanism, smashed
                                ;   rather than stabbed. vanilla bolt|water
                                ;   backs it up
        .word   $00a0
        .byte   2, OT6_DAGGER|OT6_BLUNT ; chaser: 1202 hp, the widest break
                                ;   window in the section. two keys so
                                ;   whichever three reach it hold one
        .word   $0088
        .byte   2, OT6_DAGGER|OT6_KATANA ; gobbler: no vanilla weakness at
                                ;   all, so this row is its only key. the
                                ;   one soft body in a dungeon of machines
        .word   $0075
        .byte   2, OT6_RANGED ; rhinox: no weakness of any kind, and it
                                ;   absorbs bolt, so the facility's usual
                                ;   answer would heal it. armoured bulk, no
                                ;   seam, so what is shot and that alone
        .word   $0006
        .byte   2, OT6_RANGED ; mag roader (minecart, 5 forced fights): a
                                ;   thing on wheels, smash the wheel. vanilla
                                ;   fire stays the reward for reading the
                                ;   fight, and its ice absorb stays a trap
        .word   $00af
        .byte   2, OT6_RANGED ; mag roader (the other one): same creature,
                                ;   same class; the element distinguishes the
                                ;   pair ($006 weak fire/absorbs ice, $0af
                                ;   weak ice), and one formation fights them
                                ;   together so the wrong splash heals half
                                ;   the screen
        ; sealed gate / thamasa / the floating continent
        .word   $0173
        .byte   4, OT6_SWORD ; kefka vs leo: a solo General Leo (the
                                ;   WEDGE actor) vs Kefka, L1 HP5001. Authored
                                ;   to 4 so a solo guest at arrival level wins
                                ;   with intent but can lose careless (loss
                                ;   is a GAME OVER, event_main.asm:76471).
                                ;   SWORD is Leo's blade (the Crystal,
                                ;   char_prop.asm:336), the only tool the
                                ;   player holds here. no element add: Leo's
                                ;   whole solo kit is non-elemental (Shock
                                ;   element byte $00, Crystal element byte
                                ;   $00), so an element weakness would be
                                ;   unreachable
        .word   $012e
        .byte   7, OT6_SWORD|OT6_RANGED ; ultros 3: the row, third verse
        .word   $0116
        .byte   7, OT6_DAGGER ; flameeater
        .word   $00de
        .byte   1, $00 ; balloon: vanilla ice/water pops them
        ; the FC random pool: elites carry 3 shields, the rest 2; fights
        ; stay dangerous but end inside the party's HP budget.
        .word   $0020
        .byte   3, OT6_SWORD|OT6_SPEAR ; behemoth: the pool's elite
        .word   $0083
        .byte   3, OT6_SPEAR|OT6_KATANA ; dragon: the other elite
        ; the three bodies of the pool that are magic rather than flesh or
        ; scale (each holy-weak, each casting) take blunt too, so Relm's
        ; brushes key them (#347; she is in the FC party); the beasts, the
        ; dragons and the ninja do not.
        .word   $000c
        .byte   2, OT6_SWORD|OT6_DAGGER|OT6_BLUNT ; apokryphos: a demon
        .word   $00a4
        .byte   2, OT6_SWORD|OT6_DAGGER|OT6_BLUNT ; misfit: a conjured
                                ;   thing
        .word   $0003
        .byte   2, OT6_SWORD|OT6_DAGGER ; ninja
        .word   $00d8
        .byte   2, OT6_SWORD|OT6_DAGGER ; wirey drgn
        .word   $004a
        .byte   2, OT6_SWORD|OT6_DAGGER|OT6_BLUNT ; brainpan: a mind
        .word   $0043
        .byte   2, OT6_SWORD|OT6_SPEAR ; sky armor: IAF wave trash, repeating;
                                ;   the real gauges stay on Ultros/Chupon/
                                ;   AirForce below
        .word   $00e3
        .byte   2, OT6_SWORD|OT6_SPEAR ; spit fire: same wave
        .word   $0168
        .byte   7, OT6_SWORD|OT6_RANGED ; ultros 4: one last time
        .word   $012f
        .byte   4, OT6_RANGED ; chupon: ranged is the only key
        .word   $0113
        .byte   8, OT6_RANGED ; airforce
        .word   $0145
        .byte   3, OT6_RANGED ; laser gun
        .word   $0147
        .byte   3, OT6_RANGED ; missilebay: the part-break cancel
        .word   $0146
        .byte   1, OT6_SWORD|OT6_DAGGER|OT6_SPEAR|OT6_KATANA|OT6_BLUNT|OT6_RANGED
                                ; speck: all six
        .word   $0117
        .byte   11, OT6_SWORD|OT6_DAGGER ; atmaweapon: the WoB final exam
                                ;   (the hud draws 11 in two numerals, #292)
        .word   $0118
        .byte   5, OT6_SWORD|OT6_DAGGER ; nerapa: sprint fight, low gauge
        ; ---- audit_break_coverage.py's two break-dark areas ------------
        ; (owner-approved 2026-09-01.)  Both were beatable on raw stats,
        ; which is how the fled run shipped them dark: the break loop
        ; did not exist there.  Vanilla bits stay -- the four Zozo
        ; bodies are all poison-weak (Bio Blaster is a live key whenever
        ; EDGAR is picked), and Cirpius carries no vanilla weakness at
        ; all (Ot6ElemAddTbl gives it poison), so its class row is its
        ; only weapon key (the Rhinox condition).  These five are the ONLY
        ; rows for their species: the shields-only rows that used to sit
        ; above them (kolts, zozo) were removed for #157, because the
        ; seeder takes the first match and never reached these.
        .word   $0086
        .byte   2, OT6_DAGGER|OT6_RANGED ; cirpius, the flier that is 94% of the first maps'
                                ;   draws: the old pierce was LOCKE's dagger and EDGAR's bolts,
                                ;   two classes now (opening.md 8).  poison an ot6 add
        .word   $0053
        .byte   2, OT6_BLUNT|OT6_RANGED ; hadesgigas: Blunt alone had one real holder (SABIN:
                                ;   GAU's hand left bludgeon), so the giant takes the bolt too
                                ;   (the holder rule) (opening.md 12).  poison vanilla; absorbs
                                ;   earth
        .word   $0052
        .byte   2, OT6_SWORD|OT6_KATANA ; slamdancer, the dangerous one: the blades, CELES's and
                                ;   CYAN's (and SABIN's claw); both are slash's (opening.md 12).
                                ;   poison vanilla
        .word   $004E
        .byte   2, OT6_SWORD|OT6_SPEAR ; harvester: a blade or a spear (opening.md 12).  poison
                                ;   vanilla
        .word   $00DF
        .byte   2, OT6_DAGGER|OT6_RANGED ; gabbldegak, the x4 swarm: 'AutoCrossbow sweeps it',
                                ;   and daggers and fangs; Dagger alone has no real holder in
                                ;   the World of Ruin's Zozo (the holder rule) (opening.md 12).
                                ;   poison vanilla
        ; ---- the sealed gate cave (maps 382-386) -----------------------
        ; The fled run never fought here, so the area shipped on floor
        ; rows the mission party cannot answer: measured (2026-09-01, 14
        ; rounds of honest play), an L23 TERRA/LOCKE/EDGAR/SABIN dealt the
        ; $082+$048 trio ~150 of its 4191 HP in five rounds.  Vanilla's
        ; own element bits carry the area's language -- HOLY on four of
        ; five species (AuraBolt is the master key the story party holds
        ; from L6), fire on the behemoth but ABSORBED by the ninja (the
        ; area's absorb lesson) -- and stay untouched.  These rows add the
        ; class axis the coverage rule requires: every body chippable by
        ; the forced party's own hands (but $00b3, katana only since #566).
        .word   $006E
        .byte   2, OT6_SWORD|OT6_DAGGER ; ninja: an assassin in cloth --
                                ;   a sword or a dagger.  ice|holy vanilla;
                                ;   absorbs fire (the trap stays)
        .word   $00E5
        .byte   2, OT6_KATANA|OT6_BLUNT|OT6_RANGED ; spirit: swept apart
                                ;   or beaten through, and a spirit:
                                ;   ranged for a Setzer brought along
                                ;   (#347).  holy vanilla
        .word   $00B3
        .byte   2, OT6_SWORD ; the soft flier (a katana's); ice vanilla
        .word   $0048
        .byte   3, OT6_DAGGER|OT6_BLUNT ; the shelled tank, in threes:
                                ;   LOCKE's daggers find the seams, fists
                                ;   crack the shell.  holy|water vanilla
        .word   $0082
        .byte   4, OT6_SWORD|OT6_RANGED ; the brute: miniboss-grade gauge;
                                ;   fire|holy vanilla is the elemental
                                ;   reward for reading past the ninja's
                                ;   absorb
        ; ---- the world of balance off the story's path (wob-side-trips.md) --
        ; What no story leg walks: the forests by Albrook (world groups 17,
        ; 18, 20), on foot from the opera's landing, where the post-opera four
        ; meet them: CELES (a sword), LOCKE (a knife: dagger), EDGAR (a
        ; pike: spear; his AutoCrossbow: ranged) and SABIN (fists and
        ; blitzes: blunt); and the airship's islands, the bomb isle (27) and
        ; Triangle Island (124, 28), first reached once Setzer hands over the
        ; wheel, by LOCKE, EDGAR (a sword now), SABIN (claws: katana; his
        ; blitzes blunt) and SETZER (cards and dice: ranged).  Vanilla elements
        ; stay.
        .word   $00e8
        .byte   2, OT6_SPEAR|OT6_KATANA ; bug: a shell on wings; a sword or
                                ;   a spear.  ice|water vanilla; alone, it
                                ;   answers a Fight with a petrifying spine
        .word   $003d
        .byte   2, OT6_KATANA|OT6_BLUNT ; chickenlip: a heavy bird, packs of
                                ;   five; a sword or a blow.  ice
                                ;   vanilla
        .word   $00aa
        .byte   3, OT6_BLUNT|OT6_RANGED ; grenade: answers a Fight with
                                ;   Exploder (its own hp) unless the blow
                                ;   breaks it, since a broken body does not
                                ;   counter: break it in one swing or use
                                ;   what it does not answer: sabin's blitzes
                                ;   (blunt), setzer's cards, edgar's
                                ;   autocrossbow (ranged).  ice|water
                                ;   vanilla; absorbs fire
        .word   $00a3
        .byte   2, OT6_SWORD|OT6_DAGGER|OT6_SPEAR|OT6_KATANA|OT6_BLUNT|OT6_RANGED ; intangir:
                                ;   absorbs every element, so every class
                                ;   breaks it, setzer's cards among them,
                                ;   but not a blade of an element it drinks.
                                ;   its meteo after a hit and its escape
                                ;   under 1280 hp run through its turns,
                                ;   and a broken body has none: break it
                                ;   to bring it down.  two, under the house
                                ;   curve's miniboss count, because its
                                ;   meteo takes the whole L18-22 four that
                                ;   first meets it: one double strike
                                ;   breaks it again as it recovers (three
                                ;   shields: 3 wipes in 16 meetings; four:
                                ;   3 in 15; two: 0 in 18; wob-side-
                                ;   trips.md section 3)
        ; ---- the world of balance: the species the route met on the
        ; floor (#254; docs/design/break-coverage-wob.md, one section per
        ; area, and one battle_breakwob_* suite per area) ----------------
        ; Vanilla element bits stay (and the plains' poison adds in
        ; Ot6ElemAddTbl).  House curve: 1 pests, 2 trash, 3 tanks, 4
        ; miniboss-grade.  Each row keys at least one hand of the party
        ; that meets the body there.
        ; -- the narshe mines, terra alone (map 50) --
        .word   $0046
        .byte   1, OT6_DAGGER|OT6_BLUNT ; vaporite; her knife or her Fire, BANON's rod later,
                                ;   SABIN's fists on Mt. Kolts (opening.md 2).  fire|holy
                                ;   vanilla; absorbs bolt
        ; -- the figaro desert and the plains to south figaro (world
        ; groups 1, 12, 3, 5; opening.md 4, 6, 7): terra's and locke's
        ; daggers, edgar's mithril blade and autocrossbow (a new player's
        ; edgar holds no pike before narshe's shop); his bio blaster is
        ; the plains' element (poison) --
        .word   $005c
        .byte   2, OT6_DAGGER ; sand ray; the desert has no fire weakness, so the knives are the
                                ;   key; one class, since its three elements leave the HUD's
                                ;   four cells one (opening.md 4).  ice|water vanilla; poison an
                                ;   ot6 add
        .word   $0023
        .byte   3, OT6_SPEAR|OT6_BLUNT ; fossilfang, the rare tank: EDGAR's new Drill (or a
                                ;   pike), or a blow on the bones (opening.md 12).
                                ;   fire|ice|holy|water vanilla; absorbs poison
        .word   $0015
        .byte   2, OT6_BLUNT|OT6_RANGED ; rhinotaur, the plains' tank: the bolt goes in (no pike
                                ;   in a new player's hands), fists stagger it (opening.md 7).
                                ;   poison an ot6 add; absorbs bolt
        .word   $0012
        .byte   2, OT6_SWORD|OT6_DAGGER ; rhodox, everybody's body: the blades and the dagger
                                ;   (opening.md 7).  poison an ot6 add
        .word   $00a8
        .byte   2, OT6_DAGGER|OT6_BLUNT ; greasemonk; LOCKE's dagger, then SABIN's fists the day
                                ;   he joins (opening.md 7).  poison vanilla
        ; -- the south figaro cave (map 72): all three fire-weak, terra's
        ; fire the cave's lesson; the eye takes the knives, the worm
        ; edgar's sword, the hornet a point or the autocrossbow --
        .word   $0063
        .byte   2, OT6_DAGGER ; bleary, an eye: the knives (TERRA, LOCKE), not EDGAR's blade
                                ;   (opening.md 6).  fire vanilla
        .word   $0062
        .byte   2, OT6_SWORD|OT6_BLUNT ; crawly, a soft worm: EDGAR's blade, not the knives
                                ;   (opening.md 6).  fire vanilla
        .word   $002e
        .byte   1, OT6_DAGGER|OT6_RANGED ; hornet, a flier and a pest: anyone's point or the
                                ;   sweep (opening.md 6).  fire vanilla
        ; -- mt. kolts (map 98) --
        .word   $0032
        .byte   2, OT6_SWORD|OT6_DAGGER ; trilium: cut the stalk or stab it (opening.md 8).
                                ;   fire vanilla; absorbs water
        ; -- locke and celes out of south figaro (maps 87, 69, 70): locke's
        ; dagger, celes's sword (or her bare hands: she joins unarmed);
        ; the soldiers and hounds take both, the shell his point or her
        ; fists, the soft body and the bear her sword --
        .word   $0011
        .byte   2, OT6_SWORD|OT6_DAGGER ; commander: the same two (opening.md 10b).  poison
                                ;   vanilla
        .word   $0071
        .byte   2, OT6_SWORD|OT6_DAGGER ; vector pup: LOCKE's dagger, CELES's blade (opening.md
                                ;   10b).  fire vanilla
        .word   $0094
        .byte   2, OT6_SWORD|OT6_BLUNT ; primordite, a soft body: CELES's blade (opening.md
                                ;   10b).  bolt vanilla
        .word   $0036
        .byte   2, OT6_DAGGER|OT6_BLUNT ; trilobiter, a shell: LOCKE's point, or CELES's bare
                                ;   hands (she joins unarmed) (opening.md 10b).  no element
        .word   $00f5
        .byte   3, OT6_SWORD|OT6_BLUNT ; gold bear, the cave's tank: 'the bear only the blade'
                                ;   (opening.md 10b).  no element
        ; -- the phantom train (maps 141, 142, 145): cyan's katana, and
        ; holy (sabin's aurabolt) for every ghost --
        .word   $0008
        .byte   2, OT6_KATANA|OT6_BLUNT ; hazer: the same (opening.md 10c).  holy vanilla
        .word   $000e
        .byte   2, OT6_KATANA|OT6_BLUNT ; whisper (the train): 'holy + slash featured'
                                ;   (opening.md 10c).  fire|holy vanilla; absorbs poison
        .word   $00ba
        .byte   2, OT6_KATANA|OT6_BLUNT ; stillgoing: 'the walking body takes SABIN's fists'
                                ;   (opening.md 10c).  fire|holy vanilla; absorbs poison
        ; -- narshe's back way with banon (map 48) --
        .word   $00ef
        .byte   2, OT6_BLUNT|OT6_RANGED ; 1st class, a guard in plate: the bolt or BANON's rod
                                ;   (opening.md 10a).  poison vanilla
        .word   $00f4
        .byte   2, OT6_SWORD|OT6_DAGGER ; wild rat: a rat's row (the were-rat's) (opening.md
                                ;   10a).  fire vanilla; absorbs poison
        ; -- the plains between narshe, kohlingen, jidoor and zozo (world
        ; groups 9, 10, 11, 13) --
        .word   $0078
        .byte   2, OT6_SPEAR|OT6_KATANA ; red fang, a wolf: CYAN's katana, EDGAR's pike or Drill
                                ;   (opening.md 12).  poison an ot6 add
        .word   $002a
        .byte   2, OT6_DAGGER|OT6_RANGED ; vulture, a flier: the fliers' rule; one class would
                                ;   have one real holder (the holder rule) (opening.md 12).
                                ;   wind vanilla
        .word   $0090
        .byte   3, OT6_KATANA|OT6_BLUNT ; over grunk, the plains' tank: the katana or a blow
                                ;   (opening.md 12).  fire vanilla
        .word   $008c
        .byte   2, OT6_SWORD|OT6_RANGED ; mind candy: the blades, and the sweep for the x4 swarm
                                ;   (SETZER's cards later) (opening.md 12).  fire|wind vanilla
        ; -- the south continent round albrook (world groups 14, 21) --
        .word   $007b
        .byte   2, OT6_SWORD|OT6_DAGGER ; ralph: a beast; poison an ot6 add
        .word   $0081
        .byte   3, OT6_SWORD|OT6_DAGGER ; wyvern: a dragon's hide.  ice
                                ;   vanilla
        .word   $008d
        .byte   2, OT6_SWORD|OT6_RANGED ; weedfeeder: fire|wind vanilla
        .word   $006b
        .byte   2, OT6_SWORD|OT6_BLUNT ; joker: a conjurer (world group
                                ;   15, three to a formation: the grind
                                ;   by the banquet); setzer's cards.
                                ;   bolt|poison vanilla
        ; -- the plains round thamasa (world groups 22, 23) --
        .word   $0096
        .byte   2, OT6_SWORD|OT6_DAGGER ; cephaler: bolt vanilla (locke's
                                ;   thunderblade)
        .word   $001f
        .byte   4, OT6_SWORD|OT6_DAGGER ; chimera: 2237 hp, miniboss-grade;
                                ;   poison an ot6 add
        .word   $001d
        .byte   2, OT6_SWORD|OT6_DAGGER ; baskervor: a hound (world group
                                ;   24, the forest by thamasa); poison an
                                ;   ot6 add
        ; -- esper mountain (maps 372, 375): strago's rod (blunt) is the key
        ; the blades lack (the shell, the ooze), as relm's brush is --
        .word   $00ee
        .byte   2, OT6_SWORD|OT6_BLUNT ; mandrake: a root.  fire vanilla;
                                ;   absorbs water
        .word   $00d0
        .byte   2, OT6_DAGGER|OT6_BLUNT ; insecare: an insect's shell.
                                ;   fire|wind vanilla
        .word   $00eb
        .byte   2, OT6_SWORD|OT6_SPEAR ; abolisher: no element
        .word   $00d6
        .byte   5, OT6_DAGGER|OT6_BLUNT ; adamanchyt: the mountain's wall,
                                ;   five shields, the floor's, kept above
                                ;   the house curve for battle_breakfour's
                                ;   measurement (a 3-bp break takes four of
                                ;   the five).  swords and knives turn.
                                ;   no element
        .word   $00b8
        .byte   2, OT6_BLUNT|OT6_RANGED ; slurm: an ooze, not cut.  fire
                                ;   vanilla
        ; -- the floating continent (map 393) --
        .word   $0169
        .byte   3, OT6_SWORD|OT6_SPEAR|OT6_RANGED ; naughty: a demon,
                                ;   the pool's elite.  fire|bolt|holy
                                ;   vanilla; absorbs ice
        ; ---- the world of balance towns and boxes (docs/design/wob-
        ; towns-boxes.md): the species only those side trips meet.  vanilla elements
        ; stay; each row keys the party that can first reach the fight.
        .word   $0102
        .byte   3, OT6_DAGGER|OT6_BLUNT ; mega armor: the imperial base's
                                ;   magitek guard beside a protoarmor
                                ;   (2, ranged).  the bigger suit has
                                ;   seams a dagger finds, and still
                                ;   dents.  bolt|water vanilla
        .word   $0156
        .byte   3, OT6_KATANA|OT6_BLUNT ; specter (the train's chest) (opening.md 10c).
                                ;   fire|holy vanilla; absorbs poison
        .word   $00ae
        .byte   5, OT6_SWORD|OT6_RANGED ; gigantos: the floating
                                ;   continent's boxed giant, 6000 hp: a
                                ;   boss-grade gauge.  cut it or shoot
                                ;   it: a sword, or what is thrown or
                                ;   shot, is the key.  poison
                                ;   vanilla
        ; ---- the world of ruin: the solitary island to tzen's collapsing
        ; house (docs/design/route-wor-sabin.md section 8) ---------------
        ; Celes is alone to Tzen and holds sword (every sword; dagger only
        ; on the 26-30-power daggers); Sabin joins in Tzen and adds blunt.
        ; Vanilla element bits stay and carry the plains' lesson: ice on
        ; three of six bodies (her own spell), fire on the mantis, bolt on
        ; the plated one.  Shields follow the house curve: 1 for the 1-hp
        ; pests, 2 trash, 3 tanks, 4 miniboss-grade.  None of the twelve
        ; is met in the WoB; they can come back on Gau's WoR Veldt.
        ; tools/tests/battle_breakwor_sabin.lua reads them back from the ROM.
        ; -- the solitary island (world groups 29, 30) --
        .word   $0072
        .byte   1, OT6_SWORD ; peepers: 1 hp, dies to any hit; one shield
                                ;   so the gauge reads right (the piranha
                                ;   chum wave).  ice|water vanilla
        .word   $00b2
        .byte   1, OT6_SWORD ; earthguard: the other 1-hp pest; the floor
                                ;   (pierce, through v0.50) was keyless for her sword.
                                ;   water vanilla
        .word   $00d5
        .byte   4, OT6_SWORD ; black drgn: 4000 hp on the beach and again
                                ;   by tzen's door; a blade finds the gaps
                                ;   in the scales.  fire|holy vanilla
                                ;   (Maduin, Fire Dance, AuraBolt)
        ; -- the plains (world groups 31, 34 on the route; 33, 35, 36 beside)
        .word   $0021
        .byte   3, OT6_SWORD|OT6_SPEAR ; mesosaur: a hide a sword or a
                                ;   spear opens.  ice vanilla
        .word   $0031
        .byte   3, OT6_SWORD|OT6_BLUNT ; gilomantis: a sword for the limbs,
                                ;   a rod on the carapace.  fire vanilla is the
                                ;   better key: its Sickle counter answers
                                ;   only Fight
        .word   $007c
        .byte   3, OT6_BLUNT ; chitonid: a plated shell, caved in, never
                                ;   cut.  a sword-only Celes cannot chip it
                                ;   by design; her key is its vanilla bolt
                                ;   (the ThunderBlade in her bag, Maduin)
        .word   $0098
        .byte   2, OT6_SWORD|OT6_SPEAR ; gigan toad: trash.  ice vanilla
        .word   $00ca
        .byte   2, OT6_SWORD|OT6_SPEAR ; lunaris: no vanilla weakness, so
                                ;   this row is its only key
        .word   $00e6
        .byte   2, OT6_SWORD|OT6_SPEAR ; osprey: a flier, a sword for a
                                ;   solo blade and a spear.  ice vanilla
                                ;   breaks it fast
        ; -- tzen's collapsing house (map 311, group 128; event group 150)
        .word   $00e1
        .byte   2, OT6_SWORD|OT6_SPEAR ; scorpion: def 5 / mdef 215 -- the
                                ;   blade, not the spell.  no vanilla
                                ;   weakness
        .word   $002c
        .byte   2, OT6_SWORD|OT6_RANGED ; hermitcrab: the blade takes the
                                ;   body outside the shell, a blow cracks
                                ;   the shell.  water vanilla
        .word   $00c0
        .byte   2, OT6_SWORD|OT6_RANGED ; pm stalker: a floating ghost,
                                ;   the blade in Celes's hand, and what
                                ;   is thrown or shot.  fire|holy
                                ;   vanilla; absorbs poison
        ; ---- the world of ruin: tzen to edgar (nikeah, south figaro, the
        ; figaro cave, the castle's engine room; docs/design/route-wor-
        ; edgar.md section 8) ------------------------------------------------
        ; Celes holds sword and Sabin blunt (fists, Pummel, Suplex; a
        ; claw is katana); Edgar joins at the Tentacles and adds spear (his
        ; pike) and ranged (the AutoCrossbow).  Vanilla element bits stay.  Shields follow the
        ; house curve (1 pests, 2 trash, 3 tanks, 4 miniboss-grade); the
        ; Tentacles are a four-body boss at 5 each.  None of these species
        ; is met in the WoB.  tools/tests/battle_breakwor_edgar.lua reads
        ; them back from the ROM.
        ; -- north of tzen to nikeah (world groups 37-39) --
        .word   $0035
        .byte   1, OT6_SWORD ; bloompire: 12 hp behind def/mdef 254; the
                                ;   first blade breaks it.  Energy Sap
                                ;   (zombie) is a turn of its script, and a
                                ;   broken monster takes no turn, not even
                                ;   one queued before the break (#291,
                                ;   battle_brokendeath); not measured on a
                                ;   bloompire.  fire vanilla
        .word   $0058
        .byte   3, OT6_BLUNT ; buffalax: the tank, a bull's hide dented
                                ;   by fists; its counter answers only
                                ;   magic.  fire|water vanilla
        .word   $003c
        .byte   3, OT6_SWORD|OT6_SPEAR ; lizard: scales a sword or a dagger
                                ;   opens.  ice vanilla
        .word   $0030
        .byte   2, OT6_SPEAR|OT6_BLUNT ; delta bug: def 220 / mdef 5, a shell
                                ;   cracked, not cut -- the spell, not
                                ;   the blade.  fire vanilla
        ; -- the south figaro continent (world groups 41-44) --
        .word   $00c3
        .byte   1, OT6_SWORD ; nohrabbit: a 75-hp pest that cures the
                                ;   party when struck; one shield so the
                                ;   gauge reads right.  water vanilla
        .word   $00b9
        .byte   3, OT6_SWORD|OT6_SPEAR ; latimeria: the forest's tank,
                                ;   filleted.  bolt vanilla
        .word   $0097
        .byte   2, OT6_SWORD|OT6_BLUNT ; maliga: a sand crab, the hermitcrab
                                ;   row.  ice|bolt|water vanilla
        .word   $005f
        .byte   2, OT6_SWORD|OT6_SPEAR ; sand horse: break it before its
                                ;   jaws close (clamp, x5, every turn
                                ;   once alone).  ice|water vanilla
        ; -- the figaro cave and the castle's basements (groups 137-140) --
        .word   $0049
        .byte   2, OT6_BLUNT ; humpty: an egg, cracked.  fire|holy
                                ;   vanilla; absorbs poison
        .word   $004b
        .byte   3, OT6_BLUNT ; cruller: dough, beaten; evade 100 makes
                                ;   its fire|holy vanilla (and its runic
                                ;   fire 2) the real handles
        .word   $00a9
        .byte   3, OT6_SWORD|OT6_SPEAR|OT6_BLUNT ; neckhunter: a
                                ;   reaper, a sword or a spear; death's
                                ;   own shape is a spirit: blunt too
                                ;   (#347).  poison vanilla (bio blaster)
        .word   $00d7
        .byte   4, OT6_SWORD|OT6_BLUNT|OT6_RANGED ; dante: the cave's
                                ;   miniboss-grade body; broken, it cannot
                                ;   counter with L.3 Muddle.  a demon that
                                ;   answers magic with magic: a blow or
                                ;   a shot too.  poison vanilla
        .word   $008b
        .byte   2, OT6_SPEAR|OT6_RANGED ; drop: a blade passes through water;
                                ;   a spear or a shot splashes it.
                                ;   bolt|water vanilla
        ; -- the engine room's tentacles (event group 84, formation 454) --
        ; each absorbs one of the party's elements, so the classes carry
        ; the fight: celes's sword keys three, sabin's fists three, edgar's
        ; pike two
        .word   $011b
        .byte   5, OT6_SWORD|OT6_SPEAR ; tentacle (7000 hp): weak ice|water,
                                ;   absorbs fire
        .word   $013c
        .byte   5, OT6_SWORD|OT6_BLUNT ; tentacle (6000): weak fire, absorbs
                                ;   ice|water
        .word   $013d
        .byte   5, OT6_SPEAR|OT6_BLUNT ; tentacle (5000): no weakness,
                                ;   absorbs bolt|water; not celes's
        .word   $013e
        .byte   5, OT6_SWORD|OT6_BLUNT ; tentacle (4000): no weakness,
                                ;   absorbs earth|water
        ; ---- the world of ruin: edgar to the falcon (the kohlingen
        ; continent, darill's tomb, dullahan, the tomb's monster chest;
        ; docs/design/route-wor-falcon.md section 8) -------------------------
        ; Celes (sword), Sabin (blunt) and Edgar (sword, spear; the
        ; AutoCrossbow's ranged); Setzer joins at Kohlingen with ranged
        ; (Cards, Trump, Dice, Darts).
        ; Special was a common key through v0.50 (guidelines, owner
        ; 2026-10-01): the spirits, the magical and the cursed bodies took
        ; it beside their other keys (six of the twelve; blunt or ranged now).
        ; Vanilla element bits stay.  House curve: 2 trash, 3 tanks, 4
        ; miniboss-grade; Dullahan by bosses-wob's curve.  None of the
        ; random species is met in the WoB; the chest pair's formation 433
        ; is also the 16/256 slot of WoB world group 13, a slot no WoB tile deals.
        ; tools/tests/battle_breakwor_falcon.lua reads them back from the ROM.
        ; -- the kohlingen continent (world groups 45-47) --
        .word   $0089
        .byte   3, OT6_SWORD|OT6_RANGED ; harpiai: a winged woman, a flier
                                ;   (shot down) and a sword.  wind vanilla:
                                ;   sabin's air blade
        .word   $00db
        .byte   2, OT6_SWORD|OT6_BLUNT ; muus: nulls five elements and
                                ;   counters magic with pep up: a fight
                                ;   body, a sword and a blow, so the
                                ;   crossbow does not sweep the muus x3
        .word   $00a7
        .byte   2, OT6_BLUNT|OT6_RANGED ; deep eye: a bolt in the eye;
                                ;   two shields so the autocrossbow cracks
                                ;   six in two sweeps.  a magic eye that
                                ;   sleeps whoever meets its gaze: a blow
                                ;   too.  fire vanilla
        .word   $00d3
        .byte   3, OT6_SWORD|OT6_BLUNT|OT6_RANGED ; bogy: a ghost behind safe with no
                                ;   vanilla weakness, so this row is its
                                ;   only key: a sword for the trio, and
                                ;   setzer's cards: a spirit
        ; -- darill's tomb (groups 149-151): fire on all five, holy on four,
        ; zombie on four, poison absorbed by four --
        .word   $0005
        .byte   3, OT6_SWORD|OT6_BLUNT|OT6_RANGED ; orog: a zombie mass a
                                ;   sword or a blow opens, and cursed
                                ;   flesh (ranged); broken, it neither
                                ;   zombies nor counters.  fire|holy vanilla
        .word   $0010
        .byte   3, OT6_BLUNT|OT6_RANGED ; osteosaur: bones are broken,
                                ;   not cut or stuck (the floor's pierce
                                ;   was wrong); risen bones are cursed
                                ;   (ranged).  fire|holy vanilla
        .word   $006f
        .byte   3, OT6_SWORD|OT6_BLUNT|OT6_RANGED ; powerdemon: the
                                ;   tomb's tank, in all three basements; a
                                ;   demon (a blow and a shot too).  fire|holy vanilla
        .word   $0061
        .byte   4, OT6_SWORD ; mad oscar: the plant is cut; four so the
                                ;   break lands before sour mouth's second
                                ;   turn.  fire vanilla
        .word   $0091
        .byte   2, OT6_SWORD|OT6_RANGED ; exoray: trash behind shell; the
                                ;   autocrossbow sweeps the exoray x3.
                                ;   fire|holy vanilla
        ; -- the grave (event group 85, formation 455) --
        .word   $011c
        .byte   10, OT6_DAGGER|OT6_BLUNT|OT6_RANGED ; dullahan: an armored
                                ;   knight, a dagger through the joints,
                                ;   a blow on the plate; a headless
                                ;   spirit in it (ranged, the third key).
                                ;   fire vanilla; absorbs ice
        ; -- the monster chest beside the save point (event group 116,
        ; formation 433): the narshe whelk's rows grown for the WoR --
        .word   $0101
        .byte   0, $00 ; presenter (the shell): no gauge; hitting
                                ;   the shell is the mistake
        .word   $0135
        .byte   6, OT6_RANGED ; whelk head (the WoR head): the narshe
                                ;   head's row grown; dagger here.  fire vanilla
        ; ---- the world of ruin: terra (mobliz, phunbaba's four records;
        ; docs/design/route-wor-terra.md section 6) ------------------------
        ; One demon, four records.  Vanilla poison stays (edgar's bio
        ; blaster); bolt stays absorbed (his bolt 2/3 are celes's runic).
        ; Fists and daggers open the hide in both of the party's fights; the
        ; last record, where terra fights morphed beside the two the second
        ; bababreath left, takes her blade too.
        .word   $016a
        .byte   0, $00 ; phunbaba 1: terra alone against an
                                ;   invincible demon (ai _362), a loss the
                                ;   story plays on from: no gauge
        .word   $016b
        .byte   4, OT6_BLUNT|OT6_RANGED ; phunbaba 2: the first visit; he
                                ;   flees once hit under 20480 hp (7520 in),
                                ;   a miniboss's budget: four (six never
                                ;   broke in 18 fights, setzer's jackpot
                                ;   ending it first)
        .word   $016c
        .byte   5, OT6_BLUNT|OT6_RANGED ; phunbaba 3: the return; two
                                ;   bababreaths and the end when hit under
                                ;   15360 hp (10640 in); eight never broke
                                ;   in 18 fights
        .word   $016d
        .byte   12, OT6_SWORD|OT6_BLUNT|OT6_RANGED ; phunbaba 4: terra
                                ;   morphed with two of the four, 26000 hp
                                ;   to the kill; sword is her blade's key
        ; ---- the world of ruin: cyan (the plains round zozo, jidoor and
        ; maranda, mt. zozo, the storm dragon; docs/design/route-wor-cyan.md
        ; section 6) -------------------------------------------------------
        ; The plains' six (world groups 48-50, met a step from the falcon)
        ; are vanilla's late-game pool; their vanilla elements stay (ice,
        ; fire, bolt, water).  Mt. zozo's five come in packs and pairs:
        ; cyan's stunner cuts every body at once.
        .word   $005b
        .byte   3, OT6_DAGGER|OT6_BLUNT ; crawler: a shelled crawler; a
                                ;   rod cracks it, a dagger finds the
                                ;   joints.  ice vanilla
        .word   $0099
        .byte   3, OT6_DAGGER|OT6_KATANA ; geckorex: lizard hide.  ice
                                ;   vanilla
        .word   $003b
        .byte   2, OT6_BLUNT ; reach frog: soft; a blow.  ice vanilla
        .word   $00d2
        .byte   3, OT6_KATANA|OT6_BLUNT|OT6_RANGED ; mantodea: cut or crush
                                ;   the scythes; three, so the party breaks
                                ;   it before its battle lands (route-wor-
                                ;   terra 8); relm's brush keys it the day
                                ;   she joins (route-wor-thamasa 4.3).
                                ;   fire vanilla
        .word   $0087
        .byte   3, OT6_SWORD|OT6_DAGGER ; sprinter: a running bird.  bolt
                                ;   vanilla
        .word   $00b0
        .byte   1, OT6_DAGGER|OT6_KATANA|OT6_BLUNT ; spek tor: 250 hp; sword,
                                ;   dagger or blunt.  water vanilla
        .word   $008e
        .byte   2, OT6_DAGGER|OT6_KATANA ; luridan: horned, in herds of three
                                ;   and six.  fire|wind vanilla (cyan's
                                ;   tempest)
        .word   $00f2
        .byte   4, OT6_KATANA|OT6_BLUNT ; borras: the brute; break it before
                                ;   the uppercut.  poison vanilla
        .word   $00dd
        .byte   3, OT6_DAGGER|OT6_KATANA ; punisher.  poison vanilla
        .word   $00c5
        .byte   2, OT6_KATANA|OT6_BLUNT ; scrapper: absorbs poison (vanilla),
                                ;   so the bio blaster heals it beside the
                                ;   punishers
        .word   $0014
        .byte   2, OT6_KATANA|OT6_BLUNT ; ursus: two, so it breaks before it
                                ;   runs.  fire vanilla
        .word   $014b
        .byte   14, OT6_SWORD|OT6_DAGGER|OT6_KATANA ; storm drgn: 42000 hp; katanas cut
                                ;   the hide (cyan's quadra slam chips four
                                ;   a turn), bolt (vanilla) finds it; wind
                                ;   it absorbs (cyan's tempest heals it)
        ; ---- the world of ruin: narshe (the town, the mines, the moogle
        ; cave, the cliffs, umaro's cave; the ice dragon, tritoch and umaro;
        ; docs/design/route-wor-narshe.md section 4) ------------------------
        ; The party holds sword (terra, celes), katana (cyan), spear (mog)
        ; and fire; blunt arrives with umaro at the end.  Vanilla elements
        ; stay: the arc is ice, and every boss absorbs it and is weak to fire.
        .word   $00f8
        .byte   2, OT6_DAGGER|OT6_KATANA ; red wolf: a wolf, as the wob lobo
        .word   $00ce
        .byte   2, OT6_KATANA|OT6_RANGED ; nastidon: a hide; fire vanilla
        .word   $009c
        .byte   3, OT6_SPEAR ; test rider: the lance-rider; mog's spear
                                ;   unseats it (the recruit's key: before
                                ;   he joins, the town's riders cannot be
                                ;   broken, only worn down).  poison vanilla
        .word   $00c4
        .byte   2, OT6_DAGGER|OT6_KATANA|OT6_RANGED ; wizard: a robed
                                ;   caster, met in the moogle cave before
                                ;   mog, so cyan's katana keys it; dagger for
                                ;   a magical body; celes's runic eats its
                                ;   whole list.  bolt|poison vanilla
        .word   $00da
        .byte   1, OT6_DAGGER|OT6_RANGED ; psychot: floats; absorbs fire
                                ;   (vanilla), the one body here fire heals;
                                ;   ice vanilla
        .word   $00e7
        .byte   2, OT6_SPEAR|OT6_RANGED ; mag roader (ice): a wheel, punctured
                                ;   or crushed
        .word   $00f3
        .byte   2, OT6_SPEAR|OT6_RANGED ; mag roader (fire): the same body
        .word   $00c9
        .byte   1, OT6_SPEAR|OT6_KATANA ; poppers: in fours.  fire vanilla
        .word   $00cd
        .byte   2, OT6_SPEAR|OT6_KATANA ; kiwok: a bird.  ice vanilla
        .word   $00c6
        .byte   3, OT6_SPEAR|OT6_RANGED ; ceritops: horned and plated, the
                                ;   cave's tank.  fire vanilla; absorbs bolt
        .word   $00b4
        .byte   2, OT6_KATANA ; anemone: a plant.  fire|bolt vanilla;
                                ;   absorbs bolt and water (its bolt
                                ;   weakness never applies)
        .word   $009e
        .byte   2, OT6_SPEAR|OT6_RANGED ; tomb thumb: a cursed body (ranged
                                ;   for cursed bodies).  bolt|water vanilla
        .word   $0054
        .byte   4, OT6_KATANA|OT6_RANGED ; pug: the rare one in umaro's cave,
                                ;   miniboss-grade.  fire|bolt vanilla
        .word   $00ff
        .byte   4, OT6_KATANA|OT6_RANGED ; pugs: the same body, the chest in
                                ;   umaro's cave (event group 152); the
                                ;   split gave it the pug's other halves
        .word   $0110
        .byte   6, OT6_SWORD|OT6_SPEAR ; umaro: 17200 hp; break him before
                                ;   his green cherry (under 10240 hp).
                                ;   fire|poison vanilla; absorbs ice
        .word   $0144
        .byte   10, OT6_SWORD|OT6_SPEAR|OT6_KATANA ; tritoch (the world of ruin's
                                ;   record: only battle 119 reaches it;
                                ;   $0114/$0115 stay shieldless below):
                                ;   30000 hp, def 254, so a katana and the
                                ;   spear chip what they barely hurt; fire
                                ;   (vanilla) burns it; absorbs ice
        .word   $0149
        .byte   6, OT6_SPEAR|OT6_RANGED ; ice dragon: 24400 hp; mog's spear
                                ;   is the class key, fire (vanilla)
                                ;   everyone's; absorbs ice.  six, not the
                                ;   plan's ten: with only the spear and
                                ;   fire keying it, ten held the break off
                                ;   long enough for absolute 0 to wear the
                                ;   party down (route-wor-narshe.md 11.4)
        ; ---- the world of ruin: jidoor and thamasa (owzer's house and
        ; chadarnook, the plains, the fanatics' tower; the holy dragon and
        ; magimaster; docs/design/route-wor-thamasa.md section 4) ---------
        ; Into owzer's the party holds sword (terra, celes), katana (cyan),
        ; fire, holy (terra's pearl), ice/bolt/poison (celes's tritoch); relm
        ; and strago add blunt.  Vanilla elements stay.
        .word   $00cc
        .byte   1, OT6_DAGGER|OT6_KATANA ; vindr: a bird that dodges blades
                                ;   (evade 90): fire (vanilla) is the key
                                ;   that lands
        .word   $00ad
        .byte   2, OT6_KATANA|OT6_BLUNT ; souldancer: a dancing spirit.
                                ;   poison vanilla
        .word   $0092
        .byte   3, OT6_DAGGER|OT6_RANGED ; crusher: the house's tank; no sword or
                                ;   katana keys it, fire (vanilla) does
        .word   $0077
        .byte   1, OT6_DAGGER|OT6_KATANA ; wild cat: in fours.  fire|water
                                ;   vanilla
        .word   $0009
        .byte   2, OT6_KATANA|OT6_BLUNT ; dahling: a painting; celes's
                                ;   runic eats its ice 2 and bolt 2.  poison
                                ;   vanilla
        .word   $0033
        .byte   2, OT6_KATANA ; nightshade: a painted flower.  fire
                                ;   vanilla; absorbs water
        .word   $0050
        .byte   4, OT6_KATANA|OT6_BLUNT ; still life: the basement's
                                ;   miniboss painting.  fire vanilla
        .word   $011e
        .byte   0, $00 ; chadarnook (the goddess): hitting her is
                                ;   the fight's mistake, so no gauge
        .word   $0148
        .byte   6, OT6_SPEAR|OT6_KATANA ; chadarnook (the demon): the
                                ;   swords, with fire and pearl (vanilla
                                ;   fire|holy); absorbs bolt
        .word   $002b
        .byte   2, OT6_DAGGER|OT6_BLUNT ; harpy: thamasa's plain; relm's
                                ;   brush
        .word   $008a
        .byte   3, OT6_DAGGER|OT6_BLUNT ; gloomshell: a shell, strago's rod.
                                ;   ice vanilla
        .word   $00d4
        .byte   3, OT6_SWORD|OT6_BLUNT ; prussian: a bear
        ; The fanatics' tower is magic-only (battle switch $38): only spells
        ; chip, on a weakness or by ot6's break.  The species meet no class
        ; on this arc; blunt, the magical body's key, stands for the few
        ; places outside the tower they appear.  L.20 and L.70 start with
        ; reflect: quake (earth, added in Ot6ElemAddTbl) reaches them.
        .word   $0132
        .byte   1, OT6_BLUNT ; l.10 magic: fire|holy vanilla
        .word   $0130
        .byte   2, OT6_BLUNT ; l.20 magic: reflect; +earth
        .word   $0125
        .byte   2, OT6_BLUNT ; l.30 magic: poison vanilla; absorbs holy
        .word   $012b
        .byte   2, OT6_BLUNT ; l.40 magic: bolt vanilla
        .word   $0133
        .byte   2, OT6_BLUNT ; l.50 magic: fire|holy vanilla
        .word   $0139
        .byte   3, OT6_BLUNT ; l.60 magic: fire vanilla; absorbs ice
        .word   $0143
        .byte   3, OT6_BLUNT ; l.70 magic: reflect; +earth; ice|water
                                ;   vanilla, absorbs fire
        .word   $0163
        .byte   3, OT6_BLUNT ; l.80 magic: poison vanilla
        .word   $0164
        .byte   0, $00 ; l.90 magic: reflect and nulls holy, earth,
                                ;   water: nothing the party casts reaches
                                ;   a weakness, so no gauge and full damage
        .word   $0055
        .byte   0, $00 ; magic urn: a gift, not a fight
        .word   $0024
        .byte   6, OT6_BLUNT ; white drgn (the holy dragon): no
                                ;   weakness and no reflect: ot6's break is
                                ;   its key
        .word   $0166
        .byte   8, OT6_BLUNT ; magimaster: his wall's one weakness
                                ;   (wallchange), or ot6's break
        ; ---- the world of ruin: the phoenix cave (locke; the red dragon;
        ; doom gaze in the sky on the way; docs/design/route-wor-locke.md
        ; section 3) ------------------------------------------------------
        ; The cave splits the party: party 1 (terra, strago, sabin, cyan)
        ; holds sword, katana, blunt, fire, holy, wind and water but no
        ; ice; party 2 (celes, relm, mog, umaro) holds the cave's vanilla
        ; key, ice, with sword, spear and blunt.  Nearly every species
        ; here is weak to ice and drinks fire, so each row gives party 1 a
        ; key of its own: holy on the casters and the phantom, a class on
        ; the beasts.  Vanilla elements stay.
        .word   $00bc
        .byte   2, OT6_BLUNT ; phase: a phantom; +holy (Ot6ElemAddTbl)
                                ;   beside its ice: the key for the half
                                ;   with no ice.  absorbs fire
        .word   $00bf
        .byte   2, OT6_DAGGER|OT6_KATANA ; parasoul: cut or puncture the
                                ;   canopy.  ice vanilla; absorbs fire
        .word   $00f1
        .byte   2, OT6_SWORD|OT6_BLUNT ; necromancr: a robed caster;
                                ;   celes's runic eats its doom and flare.
                                ;   fire|holy vanilla
        .word   $00f7
        .byte   2, OT6_SPEAR|OT6_BLUNT ; trixter: a fire imp; mog's spear
                                ;   for the half with no holy.  holy vanilla
        .word   $00ec
        .byte   3, OT6_SPEAR|OT6_KATANA ; aquila: a bird, the cave's rare
                                ;   killer (flap).  ice vanilla
        .word   $00e2
        .byte   4, OT6_SPEAR|OT6_BLUNT ; chaos drgn: a dragon with no
                                ;   armour (def 5).  ice vanilla
        .word   $00e9
        .byte   2, OT6_KATANA ; sea flower: a plant, in fives.  ice|bolt
                                ;   vanilla; absorbs fire|water
        .word   $0093
        .byte   1, OT6_BLUNT ; uroburos: 50 hp behind defence 252; one
                                ;   blow of a rod breaks it.  ice vanilla
        .word   $0153
        .byte   6, OT6_SPEAR ; red dragon: 30000 hp; mog's spear between
                                ;   the scales, celes's ice; ice|water
                                ;   vanilla, absorbs fire
        .word   $011d
        .byte   8, OT6_SPEAR|OT6_RANGED ; doom gaze: the eye in the sky,
                                ;   met on the falcon's deck on the way and
                                ;   fled (v0.34 fights it).  fire|holy
                                ;   vanilla; absorbs ice|poison
        ; ---- the world of ruin: the veldt cave (gau; the srbehemoth;
        ; docs/design/route-wor-gau.md section 3) --------------------------
        ; The four who walk it (terra, celes, relm, gau) hold sword
        ; (celes), dagger (terra's knife, gau's fangs), blunt (relm's rod)
        ; and fire; every body here but rhyos drinks or nulls one of
        ; celes's spells (ice, poison).  The rows key dagger, so gau's
        ; fangs and his beasts' physical turns break what celes's ice heals.
        .word   $008f
        .byte   3, OT6_DAGGER|OT6_BLUNT ; toe cutter: a scythed shell; crack
                                ;   or puncture it.  fire|wind vanilla;
                                ;   absorbs ice
        .word   $007e
        .byte   4, OT6_DAGGER ; rhyos: an armoured horn (def 150), the
                                ;   cave's rare body; no element
        .word   $00bb
        .byte   3, OT6_DAGGER|OT6_KATANA ; allo ver: bones in the monster
                                ;   chest; doom and condemned.  fire|holy
                                ;   vanilla; absorbs poison
        .word   $0119
        .byte   6, OT6_DAGGER|OT6_BLUNT ; srbehemoth: the dead beast at
                                ;   the dog's master; horn and bone.
                                ;   fire|poison vanilla (gau's were-rat);
                                ;   absorbs ice (celes's runic, not her
                                ;   spells)
        ; ---- the world of ruin: the veldt (gau; route-wor-gau.md section
        ; 3) -------------------------------------------------------------
        ; The Veldt deals every formation the save has fought; these fourteen
        ; World of Balance bodies rode the floor and the play met them there
        ; (the sweeps' [key] lines, met.txt).  Each kept the floor's
        ; shields and class and gained one from its body; #566 then split
        ; each of the two in two, by the parties the route met them with.
        .word   $0013
        .byte   2, OT6_SWORD|OT6_DAGGER ; were-rat; TERRA's knife alone, her sword when BANON's
                                ;   party returns (opening.md 2).  fire vanilla; absorbs poison
        .word   $0017
        .byte   2, OT6_SWORD|OT6_DAGGER ; leafer, the first body on the world map; two daggers
                                ;   meet it, so it takes one (Dagger is no child of v0.50's
                                ;   slash|bludgeon) (opening.md 4).  fire|water vanilla; absorbs
                                ;   ice
        .word   $001b
        .byte   2, OT6_SWORD|OT6_BLUNT ; vomammoth; every moogle squad holds a flail or a brush,
                                ;   two of the three a sword (opening.md 3).  fire vanilla
        .word   $0028
        .byte   2, OT6_DAGGER|OT6_RANGED ; dark wind, a flier: the point or the bolt (the
                                ;   fliers' rule) (opening.md 4).  fire vanilla
        .word   $0042
        .byte   3, OT6_DAGGER|OT6_RANGED ; m-tekarmor; the knives and the AutoCrossbow's sweep,
                                ;   his first fight (opening.md 5).  bolt vanilla; poison an ot6
                                ;   add
        .word   $004d
        .byte   2, OT6_SWORD|OT6_DAGGER ; repo man; the body her Fire does not key, so the knife
                                ;   must (opening.md 2).  poison vanilla
        .word   $005d
        .byte   2, OT6_DAGGER ; areneid; through v0.50 two daggers had no key at all on the
                                ;   x3 pack (slash|bludgeon, ice|water); Dagger is no child of those,
                                ;   and its three elements leave one cell (opening.md 4).
                                ;   ice|water vanilla; poison an ot6 add
        .word   $0018
        .byte   3, OT6_DAGGER|OT6_BLUNT ; stray cat: SABIN alone holds only Blunt (his
                                ;   MetalKnuckle slashed through v0.50), so it takes it; Blunt is
                                ;   no child of slash|pierce (opening.md 10c).  poison an ot6 add
        .word   $0029
        .byte   3, OT6_KATANA|OT6_RANGED ; beakor, a flier: the katana or a thrown star; the one
                                ;   body east of the Lete SABIN alone cannot key (opening.md
                                ;   10c).  fire vanilla
        .word   $002f
        .byte   3, OT6_DAGGER|OT6_BLUNT ; crasshoppr: fists, or SHADOW's blade (opening.md 10c).
                                ;   fire|wind vanilla
        .word   $004f
        .byte   3, OT6_KATANA|OT6_RANGED ; bomb: the katana or a star; not fists, not Fire
                                ;   (opening.md 10c).  ice|water vanilla; absorbs fire
        .word   $005a
        .byte   3, OT6_KATANA|OT6_BLUNT ; ghost (the forest): the katana, the fists, AuraBolt's
                                ;   holy (opening.md 10c).  fire|holy vanilla; absorbs poison
        .word   $0076
        .byte   3, OT6_KATANA|OT6_BLUNT ; rhobite: SABIN's fists alone, CYAN's katana later
                                ;   (opening.md 10c).  water vanilla
        .word   $00a2
        .byte   3, OT6_DAGGER|OT6_KATANA ; poplium: the katana, or SHADOW's blade (opening.md
                                ;   10c).  fire|holy vanilla; absorbs poison
        ; ---- the world of ruin: the zone eater's belly (gogo; route-wor-
        ; gogo.md section 3) -----------------------------------------------
        ; The four who walk it (terra, celes, relm, strago) hold dagger
        ; (terra's), sword (celes), blunt (the two rods), fire and
        ; holy (terra) and ice (celes), and no bolt or poison: the bodies
        ; weak only to those (ogor, tap dancer) take a class, and each row
        ; keys two of the four.  Vanilla elements stay.
        .word   $00dc
        .byte   3, OT6_KATANA|OT6_BLUNT ; karkass: a carcass; break the
                                ;   bones.  fire|holy vanilla; absorbs poison
        .word   $007d
        .byte   3, OT6_DAGGER|OT6_BLUNT ; wart puck: a warty imp.  fire
                                ;   vanilla
        .word   $0068
        .byte   3, OT6_SWORD|OT6_DAGGER ; ogor: an ogre's hide.  bolt|poison
                                ;   vanilla, which the four lack
        .word   $00f0
        .byte   2, OT6_SWORD|OT6_BLUNT ; tap dancer: a dancer; muddles.
                                ;   poison vanilla, which the four lack
        .word   $0067
        .byte   3, OT6_DAGGER|OT6_BLUNT ; covert: a ninja (evade 50);
                                ;   pinned or crushed.  holy vanilla (pearl)
        .word   $00fa
        .byte   3, OT6_SWORD ; woolly: shear the wool.  fire vanilla;
                                ;   absorbs ice, bolt, poison, wind, earth,
                                ;   water
        .word   $0171
        .byte   0, $00 ; zone eater: the island's only body, and
                                ;   the fight is to be eaten (engulf takes
                                ;   the party to gogo); striking it is the
                                ;   mistake, so no gauge
        ; ---- the world of ruin: ebot's rock (strago's hidon, gogo's first
        ; area; route-wor-gogo.md section 3) ------------------------------
        ; Strago, relm, gogo and terra walk it: blunt (the rods), dagger
        ; (terra's), fire and holy.  It is strago's quest, so every
        ; body takes his rod (blunt) beside a key of its own; gogo's
        ; mimic copies whichever key was just struck.  Vanilla elements stay.
        .word   $0069
        .byte   2, OT6_BLUNT|OT6_RANGED ; warlock: a robed caster (mdef
                                ;   225).  bolt|poison vanilla
        .word   $0074
        .byte   2, OT6_SPEAR|OT6_BLUNT ; slatter: a shelled crawler; holy
                                ;   vanilla
        .word   $009a
        .byte   2, OT6_KATANA|OT6_BLUNT ; cluck: a bird.  ice vanilla;
                                ;   absorbs poison
        .word   $00a5
        .byte   2, OT6_DAGGER|OT6_BLUNT ; eland: an antelope.  bolt vanilla
        .word   $00b5
        .byte   2, OT6_DAGGER|OT6_BLUNT ; hipocampus: a sea horse.
                                ;   fire|holy vanilla; absorbs poison
        .word   $0070
        .byte   3, OT6_BLUNT|OT6_RANGED ; displayer: an eye.  fire|holy
                                ;   vanilla; absorbs poison
        .word   $00c8
        .byte   3, OT6_KATANA|OT6_BLUNT ; opinicus: a griffin.  fire|holy
                                ;   vanilla; absorbs poison
        .word   $0123
        .byte   6, OT6_DAGGER|OT6_BLUNT ; hidon: strago's old foe;
                                ;   fire|holy|earth vanilla, absorbs poison
        .word   $0126
        .byte   2, OT6_KATANA|OT6_BLUNT ; hidonite (poison claw): earth
                                ;   vanilla; absorbs poison
        .word   $0160
        .byte   2, OT6_KATANA|OT6_BLUNT ; hidonite (confuclaw): reflect,
                                ;   and drinks every element: a weapon only
        .word   $0161
        .byte   2, OT6_DAGGER|OT6_BLUNT ; hidonite (zombi claw): fire|holy
                                ;   vanilla; absorbs poison
        .word   $0162
        .byte   2, OT6_BLUNT ; hidonite (mega claw): safe, and weak to
                                ;   every element
        ; ---- the world of ruin: the opera house (the dirt dragon;
        ; route-wor-gogo.md section 3) --------------------------------------
        .word   $014c
        .byte   6, OT6_DAGGER|OT6_BLUNT ; dirt drgn: an earth dragon; the
                                ;   floor's pierce (dagger) and a rod's blow.
                                ;   wind|water vanilla (strago's aqua rake)
        ; ---- the world of ruin: the plain west of doma castle (world group
        ; 52; route-wor-dreams.md section 3): its other bodies' rows are the
        ; cyan arc's ----------------------------------------------------------
        .word   $0034
        .byte   3, OT6_KATANA|OT6_RANGED ; tumbleweed: a dry bush; cut it or
                                ;   crush it.  fire vanilla; absorbs water
        ; ---- the world of ruin: cyan's dream (route-wor-dreams.md section
        ; 3) -------------------------------------------------------------------
        ; Terra, celes and relm walk it (cyan is the dream's): sword (the two
        ; blades), blunt (relm's rod), fire, ice, bolt and holy.  Terra
        ; walks the dreamscape alone until the stooges run, so every body
        ; there took her blade or her fire (a katana's now, on some rows).
        .word   $00be
        .byte   3, OT6_SWORD|OT6_KATANA ; barb-e: a dream's siren; a sword
                                ;   or a katana.  poison vanilla
        .word   $00ab
        .byte   2, OT6_SWORD|OT6_RANGED ; critic: a shrieking bird
        .word   $0085
        .byte   3, OT6_SPEAR|OT6_RANGED ; allosaurus: a dinosaur's hide.
                                ;   fire|holy vanilla (terra's fire)
        .word   $00b1
        .byte   2, OT6_KATANA ; parasite: a soft crawler.  fire vanilla
        .word   $00ac
        .byte   3, OT6_BLUNT|OT6_RANGED ; pan dora: a jar; break it.
                                ;   fire|holy vanilla; absorbs poison
        .word   $000a
        .byte   2, OT6_BLUNT|OT6_RANGED ; rain man: a storm spirit.
                                ;   ice|holy|water vanilla (celes's ice)
        .word   $0004
        .byte   3, OT6_SWORD|OT6_KATANA ; samurai: a swordsman of the
                                ;   dream's war; steel answers steel.
                                ;   poison vanilla
        .word   $001e
        .byte   3, OT6_KATANA|OT6_RANGED ; suriander: a ghostly beast.  holy
                                ;   vanilla
        ; the cave below the dream's train: the three ride magitek armor
        ; there (_cb93bf), whose rows are the beams (fire, bolt, ice) and
        ; terra's tek missile (ranged); every body is weak to bolt vanilla,
        ; so the bolt beam breaks them all
        .word   $009d
        .byte   3, OT6_RANGED ; plutoarmor: an armored rider; the
                                ;   missile hits it.  bolt|water vanilla
        .word   $0095
        .byte   2, OT6_SPEAR|OT6_RANGED ; sky cap: a flying cap.
                                ;   bolt|wind|water vanilla
        .word   $00fe
        .byte   4, OT6_SPEAR|OT6_RANGED ; io: a war machine.  bolt|holy|
                                ;   water vanilla; nulls poison|wind|earth
        ; the dream stooges (event battle 90): each takes another pair, and
        ; the three together hold every key but a dagger
        .word   $011f
        .byte   4, OT6_KATANA|OT6_RANGED ; curley: ice|water vanilla;
                                ;   absorbs fire
        .word   $0120
        .byte   4, OT6_SPEAR|OT6_RANGED ; larry: fire vanilla; absorbs
                                ;   ice|wind
        .word   $0121
        .byte   4, OT6_SWORD|OT6_BLUNT ; moe: no weakness; absorbs bolt
        ; wrexsoul (event battle 92): a composite of the war's spirits
        .word   $0122
        .byte   6, OT6_KATANA|OT6_BLUNT ; wrexsoul: a katana or a brush.
                                ;   ice vanilla; absorbs fire|holy
        .word   $0167
        .byte   2, OT6_BLUNT ; soulsaver: a soul; the brush, or celes's
                                ;   ice (vanilla); absorbs fire|holy
        ; ---- the world of ruin: the ancient castle (route-wor-dreams.md
        ; section 3) ---------------------------------------------------------
        ; Every body wears reflect and most have mdef 250: spells bounce
        ; and steel decides.  Cyan comes back from his dream with every
        ; swdtech, and his katana keys every body here.
        .word   $00a6
        .byte   2, OT6_KATANA|OT6_RANGED ; enuo: a slime.  holy vanilla
        .word   $006d
        .byte   3, OT6_SPEAR|OT6_KATANA ; goblin: holy vanilla
        .word   $0057
        .byte   3, OT6_KATANA|OT6_RANGED ; figaliz: a lizard.  ice vanilla
        .word   $0045
        .byte   4, OT6_KATANA|OT6_RANGED ; lethal wpn: a machine; cut its
                                ;   cables or crush it.  bolt|water vanilla
        .word   $0051
        .byte   3, OT6_KATANA|OT6_RANGED ; boxed set: an empty armor.  holy
                                ;   vanilla
        .word   $0152
        .byte   6, OT6_SPEAR|OT6_KATANA ; blue drgn: a water dragon's
                                ;   scales.  bolt vanilla; absorbs water
        ; the two monster boxes (#487; met nowhere else: event groups 113
        ; and 95)
        .word   $0138
        .byte   6, OT6_KATANA|OT6_RANGED ; master pug (the cave's box, 401
                                ;   (58,43)): the pugs' row.  no weakness
                                ;   vanilla, and wallchange moves the one
                                ;   it takes; absorbs water
        .word   $0124
        .byte   6, OT6_SPEAR|OT6_KATANA ; katanasoul (the castle's box, 406
                                ;   (10,17)): a swordsman's ghost; steel
                                ;   answers steel: katana and spear.
                                ;   poison vanilla
        ; ---- the world of ruin: the colosseum's own bodies (route-wor-
        ; colosseum.md section 3) ----------------------------------------------
        ; One fighter, sent by the player, auto-battles each; these three are
        ; met nowhere else.  The fighter's weapon is the key a player chooses
        ; by choosing who fights.  Vanilla elements stay.
        .word   $0037
        .byte   6, OT6_SPEAR|OT6_KATANA ; siegfried (the impostor): a
                                ;   swordsman; steel answers steel.  weak to
                                ;   every element vanilla
        .word   $0040
        .byte   0, $00 ; chupon (the colosseum's): the wager the
                                ;   colosseum will not take; it sneezes the
                                ;   fighter out, so no gauge
        .word   $007f
        .byte   6, OT6_SPEAR|OT6_RANGED ; srbehemoth (the colosseum's): the
                                ;   dead beast, as the veldt cave's; a dagger
                                ;   or a rod.  fire|holy vanilla; absorbs poison
        ; ---- the world of ruin: the side trips by the falcon (route-wor-side-
        ; trips.md section 2) --------------------------------------------------
        ; The Cactrot desert beside Maranda (world group 111) and the dinosaur
        ; forest north of Gau's father's house (world group 54).  The cabin
        ; seats three blades, SHADOW's blade (dagger) and his throw
        ; (ranged, his skeans fire, water and bolt); vanilla elements stay.
        ; The desert keys a katana or his throw; the forest's hide wants a
        ; dagger, his throw or the mages' ice.
        .word   $003e
        .byte   2, OT6_KATANA|OT6_RANGED ; hoover: a soft sand-eater; cut it
                                ;   or crush it.  ice|water vanilla (shadow's
                                ;   water edge); it answers every hit with
                                ;   sand storm, so few hits that chip win:
                                ;   two, so the break comes before the
                                ;   counters pile up (four: 42 deaths in
                                ;   36 fights; two: 22)
        .word   $004c
        .byte   1, OT6_RANGED ; cactrot: 3 hp under evade 250: a hit that
                                ;   lands does 1, and 0 while it shields, so
                                ;   the break is the kill.  shadow's throw
                                ;   (ranged) or ice|water (vanilla)
        .word   $0027
        .byte   3, OT6_DAGGER|OT6_RANGED ; tyranosaur: a dinosaur's hide, as
                                ;   the allosaurus's; a dagger or a shot, not
                                ;   a sword.  three, so the pair's break
                                ;   lands before its second meteor (four
                                ;   lost the pair 1 in 3).  ice vanilla
        .word   $0026
        .byte   6, OT6_DAGGER|OT6_RANGED ; brachosaur: that hide on a
                                ;   46050-hp body; a break holds its turns,
                                ;   ultima among them.  ice vanilla
        ; ---- the world of ruin: kefka's tower (route-wor-kefka-tower.md
        ; section 3) ---------------------------------------------------------
        ; Three parties, each a carrier beside the bench.  The tower is two
        ; places: the empire's factory (maps 292, 352, 409, 410, 329, 355:
        ; the machines, weak to bolt and water vanilla) and its ruins (the
        ; beasts, the dead and the court).  The machines turn swords,
        ; katanas and blows: a spear or a shot finds their joints, so the
        ; bench carries there, and the carriers' blades want Bolt.  The
        ; statues are magic made stone: each takes the cards or the throws
        ; and one other hand: a katana, a spear and a blow between them.
        ; Vanilla elements stay.
        ; map 334, 287, 303, 338, 339: the tower's first floors
        .word   $0084
        .byte   3, OT6_DAGGER|OT6_BLUNT ; brontaur: a horned beast's hide,
                                ;   as the dinosaurs'.  ice vanilla
        .word   $00b7
        .byte   3, OT6_KATANA|OT6_BLUNT ; evil oscar: a cursed flower; a katana
                                ;   or a brush.  fire vanilla; absorbs
                                ;   every other element
        .word   $0080
        .byte   2, OT6_SPEAR|OT6_KATANA ; vectaur: a soft insect body in a
                                ;   pack of four.  ice|water vanilla
        .word   $00e0
        .byte   3, OT6_DAGGER|OT6_BLUNT ; gtbehemoth: horn and bone, as the
                                ;   srbehemoth's; three, so the break can
                                ;   hold its meteor (the tyranosaur's count)
        ; map 304, 354, 331: the court and the dead
        .word   $000d
        .byte   3, OT6_BLUNT|OT6_RANGED ; dark force: a floating curse.
                                ;   holy vanilla
        .word   $00bd
        .byte   3, OT6_SWORD|OT6_DAGGER ; outsider: a knife-thrower; steel
                                ;   answers steel.  holy vanilla
        .word   $006a
        .byte   3, OT6_KATANA|OT6_RANGED ; madam: a sorceress.  poison
                                ;   vanilla
        .word   $0007
        .byte   3, OT6_KATANA|OT6_BLUNT ; retainer: a knight in plate.
                                ;   poison vanilla
        .word   $00c1
        .byte   2, OT6_KATANA|OT6_RANGED ; hemophyte: a blood plant
        .word   $00fb
        .byte   3, OT6_SWORD|OT6_DAGGER ; veteran: an old soldier
        .word   $00f9
        .byte   3, OT6_BLUNT|OT6_RANGED ; didalos: a bone demon.  fire|holy
                                ;   vanilla; absorbs poison
        .word   $0016
        .byte   4, OT6_SPEAR|OT6_RANGED ; steroidite: a brute's hide.  holy
                                ;   vanilla
        .word   $0056
        .byte   1, OT6_KATANA|OT6_RANGED ; mover: 120 hp; the break is the
                                ;   kill.  absorbs poison
        ; map 294, 295, 293: the beasts of the ruins
        .word   $0025
        .byte   4, OT6_SPEAR|OT6_BLUNT ; doom drgn: a dark dragon; a
                                ;   dagger or the brush.  no weakness vanilla
        .word   $00e4
        .byte   3, OT6_BLUNT|OT6_RANGED ; vectagoyle: a stone gargoyle;
                                ;   crush it.  no weakness vanilla
        .word   $009b
        .byte   3, OT6_DAGGER|OT6_KATANA ; land worm: a soft body.  ice
                                ;   vanilla; absorbs earth
        ; the factory: the machines (bolt|water vanilla on every one)
        .word   $00fd
        .byte   2, OT6_SPEAR|OT6_RANGED ; ironhitman
        .word   $00d9
        .byte   3, OT6_SPEAR|OT6_RANGED ; dueller
        .word   $00ea
        .byte   4, OT6_SPEAR|OT6_RANGED ; fortis: a walking tank
        .word   $00ed
        .byte   2, OT6_SPEAR|OT6_RANGED ; junk
        .word   $00f6
        .byte   3, OT6_SPEAR|OT6_RANGED ; innoc
        .word   $0105
        .byte   4, OT6_SPEAR|OT6_RANGED ; prometheus
        .word   $00fc
        .byte   2, OT6_SPEAR|OT6_RANGED ; sky base
        .word   $00a1
        .byte   4, OT6_SPEAR|OT6_RANGED ; scullion: 27000 hp
        ; the bosses
        .word   $010c
        .byte   6, OT6_SPEAR|OT6_RANGED ; inferno (event battle 114, map
                                ;   410): the factory's engine.  bolt
                                ;   vanilla; absorbs fire
        .word   $0142
        .byte   3, OT6_DAGGER|OT6_KATANA ; striker: inferno's arm.  fire
                                ;   vanilla; absorbs ice
        .word   $0141
        .byte   3, OT6_KATANA|OT6_BLUNT ; rough: inferno's other arm.  ice
                                ;   vanilla; absorbs bolt
        .word   $0112
        .byte   10, OT6_SPEAR|OT6_RANGED ; guardian (event battle 140, map
                                ;   291; met nowhere else: battle 76 is
                                ;   never called): the palace's machine,
                                ;   fought at last.  bolt|water vanilla
        .word   $0127
        .byte   10, OT6_KATANA|OT6_RANGED ; doom (event battle 98): the
                                ;   demon statue.  holy vanilla; absorbs
                                ;   ice|poison
        .word   $0128
        .byte   8, OT6_SPEAR|OT6_RANGED ; goddess (event battle 99): no
                                ;   weakness vanilla; absorbs bolt|holy
        .word   $0129
        .byte   8, OT6_BLUNT|OT6_RANGED ; poltrgeist (event battle 100): a
                                ;   ghost in stone.  poison vanilla;
                                ;   absorbs fire|wind
        .word   $017d
        .byte   10, OT6_SPEAR|OT6_KATANA ; atma (event battle 112, map 331):
                                ;   the atmaweapon's rematch; katana here.
                                ;   no weakness vanilla; absorbs five
        .word   $0150
        .byte   6, OT6_SPEAR|OT6_KATANA ; gold drgn (event battle 135, map
                                ;   335): a storm dragon's scales.  water
                                ;   vanilla; absorbs bolt
        .word   $0151
        .byte   6, OT6_BLUNT|OT6_RANGED ; skull drgn (event battle 136, map
                                ;   354): bone and a curse.  fire|holy
                                ;   vanilla; absorbs poison
        ; ---- the end: kefka's battle (route-wor-the-end.md section 2) ------
        ; Battle 101 is four formations in one fight, met by whoever the
        ; order menu puts in front: each tier between its bodies takes
        ; every one of the six classes, and so does Kefka.  Vanilla
        ; elements stay.
        ; formation 471: the arms and the face
        .word   $0157
        .byte   6, OT6_SPEAR|OT6_BLUNT ; short arm: a machine's arm; a
                                ;   dagger and a rod's blow.  water vanilla
        .word   $0158
        .byte   6, OT6_SWORD|OT6_DAGGER|OT6_KATANA ; long arm: a claw on sinew; cut
                                ;   it.  wind vanilla
        .word   $0159
        .byte   8, OT6_BLUNT|OT6_RANGED ; face: magic made stone, as the
                                ;   statues.  fire vanilla; nulls earth
        ; formation 512: the four figures
        .word   $015d
        .byte   6, OT6_SWORD|OT6_BLUNT ; hit: a warrior in plate.  poison
                                ;   vanilla
        .word   $015a
        .byte   6, OT6_DAGGER|OT6_KATANA ; tiger: a beast's hide.  ice
                                ;   vanilla; absorbs earth
        .word   $015b
        .byte   6, OT6_SPEAR|OT6_RANGED ; tools: a machine, as the
                                ;   factory's.  bolt vanilla
        .word   $015c
        .byte   8, OT6_KATANA|OT6_RANGED ; magic: a sorceress, as the
                                ;   madam.  earth vanilla
        ; formation 513: the lady and the sleeper
        .word   $015e
        .byte   3, OT6_SWORD|OT6_DAGGER|OT6_SPEAR|OT6_KATANA|OT6_RANGED ; girl: 9999 hp; absorbs every
                                ;   element, so steel is the way in, and a
                                ;   break holds the life 2 she casts on the
                                ;   sleeper when she stands alone
        .word   $015f
        .byte   8, OT6_BLUNT|OT6_RANGED ; sleep: stone asleep.  no
                                ;   weakness vanilla
        ; formation 514
        .word   $012a
        .byte   16, OT6_SWORD|OT6_DAGGER|OT6_SPEAR|OT6_KATANA|OT6_BLUNT|OT6_RANGED ; kefka:
                                ;   four of the six find him, and the most
                                ;   shields of any boss (storm drgn 14).
                                ;   no weakness vanilla; nulls poison
        ; ---- the world of balance: the event fights the design audit
        ; found on the floor (docs/design/break-coverage-wob.md sections
        ; 13-17; battle_breakwob_events checks them in the ROM).  Vanilla
        ; elements stay; the house curve as above.
        ; -- the lete river's raft (event battles 7 and 8): terra's
        ; sword, edgar's pike, banon's rod (sabin's fists key none here);
        ; each of the three keys two of the three, terra's fire all three --
        .word   $0022
        .byte   2, OT6_SWORD|OT6_RANGED ; pterodon, a flier: the blades or the bolt (opening.md
                                ;   9).  fire vanilla
        .word   $0038
        .byte   2, OT6_BLUNT|OT6_RANGED ; nautiloid: a bolt in its mouth or a blow on the shell
                                ;   (opening.md 9).  fire|bolt vanilla; absorbs water
        .word   $0039
        .byte   2, OT6_SWORD|OT6_BLUNT ; exocite: the blades, the fists, BANON's rod (opening.md
                                ;   9).  fire|bolt vanilla; absorbs water
        ; -- the narshe caves' sparkle trap (map 49, battle 38): the same
        ; three; one spirit to each hand, terra's fire to all, and the
        ; bio blaster heals them --
        .word   $0060
        .byte   2, OT6_SWORD|OT6_RANGED ; dark side (the checkpoint's trap): the blades or the
                                ;   bolt, not the rod (opening.md 10a).  fire|holy vanilla;
                                ;   absorbs poison
        .word   $00b6
        .byte   2, OT6_BLUNT|OT6_RANGED ; spectre (the trap): BANON's rod, EDGAR's bolts
                                ;   (opening.md 10a).  fire|holy vanilla; absorbs poison
        .word   $00cf
        .byte   1, OT6_BLUNT|OT6_RANGED ; rinn (the trap's x3): the sweep, or the rod
                                ;   (opening.md 10a).  fire|holy vanilla; absorbs poison
        ; -- the battle for narshe's raiders (battles 22 and 23): the
        ; player forms three squads from the seven; every raider takes
        ; the troopers' keys, sword, dagger and katana (opening.md 11) --
        .word   $0079
        .byte   2, OT6_SWORD|OT6_DAGGER|OT6_KATANA ; bounty man: 'a raider should take the
                                ;   troopers' keys' (opening.md 11).  fire vanilla
        .word   $001c
        .byte   2, OT6_SWORD|OT6_DAGGER|OT6_KATANA ; fidor: 'a raider should take the troopers'
                                ;   keys' (opening.md 11).  fire vanilla
        ; -- the banquet's sparring troopers (battle 30): terra and
        ; locke's blades --
        .word   $00c2
        .byte   3, OT6_SWORD|OT6_DAGGER ; sp forces: the imperial elite,
                                ;   a tank's three; the trooper line's
                                ;   sword, and a spear.  poison vanilla
        ; -- the phantom train: sabin, cyan, shadow --
        .word   $000f
        .byte   2, OT6_KATANA|OT6_RANGED ; over-mind: the katana or a star (opening.md 10c).
                                ;   fire|holy vanilla; absorbs poison
        .word   $0131
        .byte   1, OT6_DAGGER|OT6_KATANA|OT6_BLUNT ; siegfried: one shield any hand of the three
                                ;   breaks (opening.md 10c).  no element
        ; scripted set-pieces: no gauge drawn
        .word   $0111
        .byte   0, $00 ; guardian (the wob's: battle 75)
        .word   $0114
        .byte   0, $00 ; tritoch
        .word   $0115
        .byte   0, $00 ; tritoch
        .word   $0179
        .byte   0, $00 ; flashback soldier (battle 115, terra's
                                ;   magitek flashback): 1 hp, no action
        .word   $017a
        .byte   0, $00 ; the esper kefka fights (battle 97): a
                                ;   cutscene that casts and ends itself
        .word   $017b
        .byte   0, $00 ; the battle-event runner (battles 105,
                                ;   121, 122, 123, 127): untargetable,
                                ;   plays a cutscene and ends the battle
        ; ---- bodies no formation the game deals holds: no event script
        ; calls their event battle, no battle-enabled pool or world sector
        ; holds their formation, and no ai script or chest reaches it.
        ; Rows here close the gap on purpose; tools/check_shield_rows.py
        ; refuses one whose species a reachable formation holds, and
        ; break-coverage-wob.md lists the evidence per species.
Ot6ShieldTblUnreached:
        .word   $010f
        .byte   0, $00 ; umaro (battle 74; the fight is $0110)
        .word   $011a
        .byte   0, $00 ; kefka (battle 83, formation 562; the
                                ;   final battle's is $012a)
        .word   $0136
        .byte   0, $00 ; colossus (battle 91; pool 66 only on
                                ;   maps 157 and 167, no random battles)
        .word   $0137
        .byte   0, $00 ; czardragon (formation 561)
        .word   $013b
        .byte   0, $00 ; b.day suit (formation 42)
        .word   $016e
        .byte   0, $00 ; (terra's flashback ai; battle 51)
        .word   $0170
        .byte   0, $00 ; (cyan at the camp; battle 52)
        .word   $0172
        .byte   0, $00 ; (gau from the veldt; battle 54)
        .word   $0177
        .byte   0, $00 ; (unused; battle 60)
        .word   $0178
        .byte   0, $00 ; (unused; battle 61)
        .word   $017f
        .byte   0, $00 ; (unused; formations 490-495)
        .word   $ffff

; break-floor class table: one class byte per species (0..383), directly
; indexed by species id. the @formula seed reads this as f:OT6_FLOOR_CLASS,x
; so an un-authored monster is still breakable by SOME weapon class.
; generated by ff6/tools/gen_break_floor.py; do not edit the .inc by hand.
        .include "ot6_break_floor.inc"

; each monster slot's own shield-count cell (#292): slot s draws its count
; with the tile Ot6UploadSlotTile last put in cell s (OT6_SHHAVE).  Before
; #292 these six cells held fixed tiles for the counts 1-6 and a higher
; count drew as 6; now any count 1..99 draws true.  The cells are the six the
; fixed tiles used, so no new font cell is claimed.
Ot6ShieldSlotCellTbl:
        .byte   $65,$66,$67,$69,$6a,$6b

; the shield gauge's emblem cell (#397; Ot6BgGlyphCellTbl's first entry,
; which held the broken shield before the broken art became a per-slot tile)
; and the line's tilemap attributes: priority, char bit 8, and a text
; palette (btlgfx BattleFontPal; colours 1/2/3).  The gauge: palette 0
; (black, grey, white), plain white like the HP numerals.  It was palette 2
; (navy, grey, yellow), the lightning and holy icons' yellow, and a revealed
; bolt beside the count read as a smear of it.  The broken shield: palette 7
; (grey, grey, red).  An unrevealed weakness's '?': palette 1 (navy, grey,
; the mid grey vanilla draws unusable list entries in), apart from the
; gauge's white.  The weakness icons are in Ot6ElemPalTbl (ot6_icons.asm).
OT6_EMBLEM      = $71
OT6_KNIFE       = $74           ; the pin's knife cell (#546): blank in the
                                ;   font, between the pip cells
OT6_GAUGE_ATTR  = $21 | (0 << 2)
OT6_BROKEN_ATTR = $21 | (7 << 2)
OT6_QMARK_ATTR  = $21 | (1 << 2)

; monster slot -> its OT6_SHPEND bit
Ot6ShieldBitTbl:
        .byte   $01,$02,$04,$08,$10,$20

; the shield tiles, one per count 1..99
; generated by ff6/tools/gen_shield_glyphs.py; do not edit the .inc by hand.
        .include "ot6_shield_glyphs.inc"

; pip cluster cells (0-5 filled)
Ot6PipCellTbl:
        .byte   $72,$73,$75,$76,$77,$79

; boost arrow cells (pending 1-3)
Ot6ArrowCellTbl:
        .byte   $68,$6c,$6d

; bg hud glyph cells with fixed art (2bpp, verified junk-free in both
; formations); the six shield-count cells above are loaded per slot
Ot6BgGlyphCellTbl:
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
        .byte   OT6_KNIFE       ; the pin's knife (#546)

Ot6BgGlyphData:
; the shield gauge's emblem (#397), in text palette 0: a plain white shield
; with a black outline (gen_shield_glyphs.py draws it, beside the count
; tiles; the broken shield is each slot's tile 100, #397's grey emblem
; cracked)
        .byte   OT6_EMBLEM_TILE
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
; the pin (#546): a knife standing point-down in its shadow, text palette 0
; (gen_shield_glyphs.py draws it, beside the emblem)
        .byte   OT6_KNIFE_TILE

; the mark before the shield emblem (#546, #561), by OT6_MARKCELL: free
; (never drawn: Ot6BgHudFlush_ext writes nothing for it), hobbled (the
; battle font's own dagger, $d8, the item icon beside the class icons
; Ot6ClassGlyphTbl uses), pinned (the knife).  Text palette 0, the gauge's.
Ot6MarkWordTbl:
        .word   $01ee
        .word   (OT6_GAUGE_ATTR << 8) | $d8
        .word   (OT6_GAUGE_ATTR << 8) | OT6_KNIFE
        ; #561: a lit fuse (OT6_MARK_FUSE, ot6_fuse.asm): the font's own "!"
        ; ($be), yellow
        .word   (OT6_FUSE_ATTR << 8) | $be

; ------------------------------------------------------------------------------

; window_open's DrawCharNames, through Ot6WindowOpenNames (ot6_c1), inside
; its jsr: the opening character's point shows, then the names are staged,
; and back through a C1 rts.  a8/i16 (btlgfx).
.proc Ot6WindowOpenNames_ext
        .a8
        .i16
        jsr     Ot6BpWindowOpen
        jsr_c1  DrawCharNames
        jml     f:GfxCmd_00     ; a C1 rts: back to window_open
.endproc
