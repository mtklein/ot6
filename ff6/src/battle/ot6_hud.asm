; [ upload the bg hud glyphs into free font cells ]

; 16 2bpp tiles (shield-with-count 1-6/B, pip clusters 0-5, boost cells)
; written to the battle font at vram $5800 + cell*8, as two 8-tile
; slices (~128 bytes each, one of which fits a vblank-tail re-lay stage).
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
        ot6_glyph_slice $0000, $0008
.endproc

.proc Ot6LoadBgGlyphsB
        .a8
        .i16
        ot6_glyph_slice $0008, $0010
.endproc

; ------------------------------------------------------------------------------

; [ per-frame bg hud: rebuild the shadow line buffer ]

; the hud lives on the bg3 field tilemap; this main-loop pass fills a
; shadow buffer in bank $7f, and the nmi flush copies it to vram during
; vblank. shadow at OT6_SHADOW, 6 lines x 14 bytes:
;   +0  vram word address of the line's first cell (0 = line disabled)
;   +2  five tilemap words (glyph | attr << 8)
; monsters: [shield-with-count][up to 4 weakness slots: elements, then
; weapon classes, revealed icon or '?' on both axes]. heroes: one
; pip-cluster cell. entities animate and drift, so each line remembers
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
        rtl
.endproc

.proc Ot6ScriptEnd_ext
        .a8
        lda     #$00
        sta     f:$7e0000+OT6_SCRIPTBUSY
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
        shorta0
        ; dead monsters: cells stay blank, line stays live (erases old art)
        lda     $3eec,y
        bit     #$c2
        jne     @done
        ; cell 0: shield-with-count
        lda     $3e90,y
        beq     @count
        lda     #$71            ; shield-broken
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
@q:     lda     #OT6_QMARK      ; '?', default attr already in place
        sta     f:$7e0000+OT6_SHADOW+4,x
@next:  asl     OT6_SCR_BIT
        inc     OT6_SCR_IDX
        bra     @elem
@cls:   ; class-weakness slots: same claim/cap flow, from the authored
        ; class mask (OT6_BP_CLASS monster half, seeded at battle init) and the
        ; revealed-classes byte the chips and codex maintain. the icons
        ; are the vanilla item-class glyphs, white like the '?' (the
        ; default $21 attr from the fill is already in place, so only the
        ; glyph byte is written, as with the '?' cell).
        lda     #$01
        sta     OT6_SCR_BIT
        lda     #$00
        sta     OT6_SCR_IDX     ; class index 0-3
@cbit:  lda     OT6_SCR_BIT
        cmp     #$10
        bcs     @edone          ; all four classes walked
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
@cq:    lda     #OT6_QMARK      ; '?', default attr already in place
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
        ; lines + pip transitioning at once) is ~70 words ~ 9 scanlines
        ; at the measured PIO rate (~8 words/scanline, the font-slice
        ; numbers above), ending ~257 < 262. residual risk: a transition
        ; deferred into a veil window leaves old glyphs one extra frame if
        ; the nmi is also late.
        ldx     #$0000
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
@skip:  shorta0
        longa
        txa
        clc
        adc     #$000e
        tax
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
        ; live pip pseudo-line: one cell in the party-window menu map. the
        ; map is the menu engine's own, and this code paints one cell in it.
        ; Ot6PipStage points it at the active character while a menu is
        ; open, and at the character who just spent BP for a few frames
        ; after (OT6_PIPTAIL), so the drop lands on the charge frame.
        ; the party window is double-buffered: each name row is staged at
        ; map row 1+2r and at 9+2r (+$100 words) and the scroll picks a band,
        ; so both are painted: writing only the low band would leave boost
        ; feedback invisible whenever the high band is up.
        longa
        lda     f:$7e0000+OT6_PIPPREV
        beq     @cur
        cmp     f:$7e0000+OT6_PIPCUR
        beq     @cur
        shorta0
        jsr     @late
        bcs     @pdone
        longa
        lda     f:$7e0000+OT6_PIPPREV            ; reload (gate ate a)
        sta     hVMADDL                  ; moved/closed: blank the old cell
        lda     #$21ff          ; $21ff is correct here, on purpose: the pip
                                ;   lives in the party-window menu map, whose
                                ;   hdma $2105 sections ($8973/$8977) no anim
                                ;   ever flips to 16x16.  the field-map blank
                                ;   above had to become $01ee (the entrance-
                                ;   flash fix), but $01ee is the field map's
                                ;   fill, not this map's
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
; local: enough vblank left for a one-shot transition write? (a8, db=0;
; clobbers a; carry set = too late, defer.) constants mirror the font
; slice gate above: v must be in [225,248]; past 248 the worst-case
; transition burst (~9 scanlines at the measured PIO rate, see the
; @nofont comment) could run into active display, where the PPU drops
; VRAM writes and a one-shot has no next-frame rewrite to heal it.
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
; during target select the spend is fully effective and stays legal:
; Ot6QueueFold reads pending from CreateAction, which runs after target
; select.  after the confirm, CreateAction has already frozen the tier,
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
        bit     #$10            ; R: boost up
        beq     @tryl
        lda     OT6_BOOST_REVEALED,y
        inc     a
        cmp     #$04            ; spend at most 3
        bcs     @deny
        cmp     OT6_BP_CLASS,y         ; and never more than current bp
        beq     @store
        bcs     @deny
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
        ; vanilla's own UpdateEnabledMagic, which Ot6FoldPrices hangs off.
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

; [ commit a deferred pip paint onto the live cell ]
;
; Why the paint defers and the bank does not.  Ot6CoverBP banks the True
; Knight's BP at SetCoverTarget's commit: that instruction is the block
; as the engine understands it.  But the engine's decision to retarget
; precedes the damage numeral by many frames, and OT6_PIPTAIL is only 32,
; so arming the cell at the commit would make the pip flash and fade
; before the blow visibly lands on the knight; a pip is meant to move
; when the thing it represents happens, and what a player perceives as
; "the block" is the hit landing on the blocker rather than the retarget.
;
; So Ot6CoverBP banks the blocker's slot into OT6_PIPPEND and this proc moves
; it into OT6_PIPSLOT/OT6_PIPTAIL, the same bank-then-commit shape
; Ot6RvPend*/Ot6RevealCommit use for weakness reveals, driven off the
; same trigger (Ot6RevealPoll's numeral-counter change, ot6_break.asm).
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
; pending paint must never outlive the action that banked it.  It runs there
; after that proc's own charge arm, so the rarer out-of-turn cover takes the one
; live cell; the actor's own bank is restaged at the next window open anyway
; (Ot6PipGlyph_ext), while a cover earn has no other moment.
;
; a8/i16, db=$7e.  clobbers a; preserves x/y.
.proc Ot6PipPending
        .a8
        .i16
        lda     f:$7e0000+OT6_PIPPEND
        beq     @none                   ; 0 = nothing deferred
        dec     a                       ; stored as slot + 1
        sta     f:$7e0000+OT6_PIPSLOT
        lda     #32                     ; OT6_PIPTAIL: ~half a second of live
        sta     f:$7e0000+OT6_PIPTAIL   ;   painting, Ot6ActionEnd's own value
        lda     #$00
        sta     f:$7e0000+OT6_PIPPEND   ; consumed (stz has no long mode)
@none:  rts
.endproc

; ------------------------------------------------------------------------------

; [ stage the live pip cell: the drop lands on the charge frame ]
;
; One cell (the flush paints it into both window bands), pointed at:
;   - the active character while a battle menu is open, giving compose-time
;     feedback, an arrow cluster while a boost is pending and uncommitted;
;   - the character who just spent bp for OT6_PIPTAIL frames after their
;     action resolved (Ot6ActionEnd arms both), so the drop is visible even
;     though no menu is open at resolution.
; The glyph is the full bank rather than bank-minus-pending: a committed spend
; keeps showing its pips until Ot6ActionEnd's charge writes bp, which is what
; makes the visible drop and the mechanical event the same frame.
; a8/i16, db=$7e (Ot6BgHud_ext's context).  clobbers a; preserves x/y.
.proc Ot6PipStage
        .a8
        .i16
        ; the charge window takes priority.  While OT6_PIPTAIL runs, the cell
        ; follows the character who just spent BP even if a menu is open for
        ; someone else: one cell can only show one row.  The other rows are
        ; re-staged at the next window open (Ot6PipGlyph_ext), and the tail
        ; is ~half a second, so a boost being composed elsewhere gets its
        ; arrow back immediately after.
        lda     f:$7e0000+OT6_PIPTAIL
        beq     @nottail
        dec     a
        sta     f:$7e0000+OT6_PIPTAIL
        lda     f:$7e0000+OT6_PIPSLOT    ; the character who just charged
        bra     @have
@nottail:
        lda     $7bca           ; battle menu open?
        bne     @menu
        jmp     @off            ; nothing to show
@menu:  lda     $62ca
        and     #$03
@have:  and     #$03
        sta     OT6_SCR_BIT     ; the slot whose cell we paint
        phx
        phy
        ldx     #$0000
@row:   cmp     $64d6,x         ; find the menu row showing this slot
        beq     @found
        inx
        cpx     #$0004
        bcc     @row
        ply
        plx
        jmp     @off            ; not on screen: disable the pseudo-line
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
        lda     OT6_SCR_BIT
        asl                     ; slot -> entity offset
        longa
        and     #$00ff
        tay
        shorta0                 ; y = entity offset
        ; arrow iff a menu is open, this row is the ACTIVE character, a boost
        ; is pending, and the action is not committed yet
        lda     $7bca
        beq     @jpips
        lda     $62ca
        and     #$03
        cmp     OT6_SCR_BIT
        bne     @jpips
        lda     OT6_BOOST_REVEALED,y
        beq     @jpips
        lda     OT6_SCR_BIT
        jsr     Ot6CommittedSlot
        bcc     @arrow
@jpips: jmp     @pips
@arrow:
        lda     OT6_BOOST_REVEALED,y     ; pending 1-3 -> arrow cell
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
        ply
        plx
        rts
@pips:  lda     OT6_BP_CLASS,y  ; the full bank (see the block comment)
        cmp     #$06
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
        ply
        plx
        rts
@off:   longa
        lda     #$0000
        sta     f:$7e0000+OT6_PIPCUR
        shorta0
        rts
.endproc

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
        lda     f:$7e3e9c,x     ; bp: the full bank. the staged cell
                                ;   agrees with the live painter, which shows
                                ;   a committed spend at full strength until
                                ;   Ot6ActionEnd's charge lands
        cmp     #$06
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

; per-species shield + class-weakness overrides: bosses get authored
; counts, marked trash gets flavor, and shields 0 means explicitly
; shieldless (no display; whelk's shell stays the wrong answer, as
; vanilla intended, and scripted set-pieces draw no gauge, so a blank hud
; means the fight is not a break fight). format: .word species id (monster
; prop offset / 32), .byte shields, .byte class weaknesses; $ffff
; terminates.  unlisted species use the 2 + level/8 formula and carry no
; class weakness. elemental rows are not here: vanilla element bits stay in
; monster data.
;   - guardian/tritoch: multiple records each, and WoB story order cannot
;     tell them apart from here, so all are drawn shieldless for the WoB.
;
; kefka has one row; the imperial camp gags need none: MONSTER::KEFKA_NARSHE
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
        .byte   2, OT6_PIERCE   ; guard: armored infantry, the tekmissile probe
        .word   $0019
        .byte   3, OT6_PIERCE   ; lobo
        .word   $0100
        .byte   0, $00          ; whelk (the shell)
        .word   $0134
        .byte   4, OT6_PIERCE   ; whelk head: the first boss break. $0134
                                ;   'Head' is the narshe fight; $0135 is
                                ;   the WoR presenter's head. no vanilla
                                ;   fire weak; the tutorial's fire probe
                                ;   is an m6 element add, not vanilla
        .word   $0064
        .byte   4, OT6_PIERCE   ; marshal: mog's fight, mog's class
        ; mt. kolts / lete river
        ; ---- mt. kolts trash: two shields lets the break land before the
        ; monster is already spent (the breaking hit is 4x base through the
        ; element channel, 2x through the class one; the formula's 3 lands
        ; the break on a corpse, and 1 is too few against the element
        ; channel: 4x base exceeds a 270-hp tusker outright).
        .word   $000b
        .byte   2, OT6_SLASH    ; brawler: absorbs poison (monster_prop.dat
                                ;   +$0177 = $08), so the mountain's usual
                                ;   bio-blaster answer would heal it; slash
                                ;   because terra/locke/edgar's other
                                ;   weapons are all pierce (ot6_class.asm:
                                ;   48,49,59) except edgar's mithril blade
        .word   $0086
        .byte   2, $00          ; cirpius: shields only; weakness is the
                                ;   poison row in Ot6ElemAddTbl
        .word   $007a
        .byte   2, $00          ; tusker: shields only, same reason.
                                ; an Ot6ShieldTbl row also exempts its
                                ; species from Ot6HpScale (inert today,
                                ; every band ships $10 = 1x); where a
                                ; species needs a weakness but not a shield
                                ; count, Ot6ElemAddTbl is the row that
                                ; avoids that exemption.
        .word   $0103
        .byte   5, OT6_BLUDG    ; vargas: not breakable without the monk
        .word   $014d
        .byte   2, OT6_SLASH    ; ipooh
        .word   $012c
        .byte   5, OT6_SLASH|OT6_PIERCE ; ultros 1: the row he keeps all game
        .word   $0104
        .byte   5, OT6_PIERCE   ; tunnelarmor: mug and daggers
        .word   $014a
        .byte   6, OT6_SLASH|OT6_PIERCE ; kefka: the Narshe defense record
                                ;   only (MONSTER::KEFKA_NARSHE); the
                                ;   imperial camp gags carry no monster
                                ;   entity at all (see the block comment)
        .word   $0044
        .byte   4, OT6_BLUDG    ; telstar
        .word   $001a
        .byte   2, OT6_PIERCE   ; doberman
        .word   $0106
        .byte   6, OT6_BLUDG    ; ghosttrain
        .word   $0155
        .byte   4, OT6_SLASH|OT6_BLUDG  ; rizopas
        .word   $0154
        .byte   1, OT6_SLASH|OT6_BLUDG  ; piranha: the chum wave
        ; class rows below give a weapon class to species whose forced
        ; party cannot reach any vanilla/added element (class chips ignore
        ; absorb/null).  shields track the early-war trash/miniboss tier
        ; (2 basic, 3 elite).  note the trade: an Ot6ShieldTbl row exempts a
        ; species from Ot6HpScale, which the armor-line ElemAddTbl block deliberately
        ; avoided, but a class weakness has nowhere else to live, so
        ; per-party breakability takes that trade here (HpScale ships 1x,
        ; inert today). palette: armored soldiers read pierce (a blade finds
        ; the gaps) plus lightning where a party can conduct it; the Cyan solo
        ; duel is slash (the samurai out-cuts them); Sabin's brawls add
        ; bludg (a monk caves the plate).
        ;
        ; -- imperial soldier line --
        .word   $0001
        .byte   2, OT6_SLASH|OT6_PIERCE ; soldier: Cyan's duel cuts it
                                ;   (slash), Shadow's throw finds the seam
                                ;   (pierce)
        .word   $0002
        .byte   3, OT6_PIERCE   ; templar: Shadow's throw (pierce) /
                                ;   Bolt Edge (+bolt in ElemAddTbl)
        .word   $014e
        .byte   3, OT6_SLASH    ; leader: Cyan solo Doma duel, slash only;
                                ;   no other party fights him
        .word   $014f
        .byte   2, OT6_SLASH|OT6_BLUDG ; grunt: Doma courtyard defense,
                                ;   held by Cyan (slash) + Sabin (bludg)
        .word   $0176
        .byte   3, OT6_SLASH|OT6_BLUDG ; cadet: same Doma defense, same two
                                ;   heroes, a bigger body
        .word   $0175
        .byte   2, OT6_PIERCE   ; officer: Locke solo occupied South Figaro;
                                ;   pierce is Locke's one key
        .word   $0065
        .byte   2, OT6_SLASH|OT6_PIERCE ; trooper: Narshe defense waves;
                                ;   slash for a Cyan/Sabin squad, pierce
                                ;   for a Locke/Gau squad
        .word   $003f
        .byte   3, OT6_SLASH|OT6_PIERCE ; rider: also a Narshe wave, same
                                ;   squad coverage. keeps vanilla fire|poison
        .word   $009f
        .byte   3, OT6_SLASH|OT6_PIERCE ; heavyarmor: Locke solo S.Figaro
                                ;   guards (pierce) and a Narshe wave (slash
                                ;   for a Cyan/Sabin squad)
        .word   $013a
        .byte   2, OT6_PIERCE   ; merchant: Locke solo disguise fight; a
                                ;   civilian with no vanilla weakness at all
        ; -- Serpent Trench (Sabin + Cyan + Gau): bludgeon and slash is the
        ; whole ring the party can reach. Gau cannot equip a pierce weapon
        ; on this scenario (his only legal one, the Imp Halberd, is a
        ; WoB-late treasure stocked by no shop, ot6_class.asm:86) and his
        ; bare-handed Fight reads as OT6_BLUDG (ot6_class.asm:163); Sabin
        ; brings fists/Pummel/Suplex/Bum Rush (bludg) plus claws (slash),
        ; Cyan brings katanas and SwdTechs (slash). all three absorb water
        ; and their vanilla element is dead or L15-gated for this party, so
        ; class is the only reliable break.
        .word   $003a
        .byte   2, OT6_SLASH    ; anguiform: cut by Cyan's blade
        .word   $005e
        .byte   2, OT6_BLUDG    ; actaneon: cracked by Sabin's fists
        .word   $0059
        .byte   2, OT6_BLUDG    ; aspik: crushed by a monk's fists
        ; zozo / opera / the factory
        ; ---- zozo town: four poison-trash rows, shields only. the
        ; search-for-terra party (Locke+Celes+Edgar+Sabin) has no native
        ; fire; poison via Edgar's bio blaster is the town's break key.
        ; every town thug is already poison-weak in vanilla, so these are
        ; shield-count-only rows.
        .word   $0052
        .byte   2, $00          ; slamdancer
        .word   $004e
        .byte   2, $00          ; harvester
        .word   $0053
        .byte   2, $00          ; hadesgigas: the town wall, 1200 hp
        .word   $00df
        .byte   2, $00          ; gabbldegak: comes 4 at a time, bio's
                                ;   group target chips the whole pack at once
        .word   $0107
        .byte   6, OT6_PIERCE|OT6_BLUDG ; dadaluma: break the crouch
        .word   $006c
        .byte   2, OT6_PIERCE|OT6_BLUDG ; iron fist
        ; the opera's timed rafter chase forces Locke + Edgar + Sabin through
        ; packs of as many as five rats: two shields (the early-trash count
        ; used at Kolts and Zozo) keeps the break window part of the chase.
        ; both classes are carried by the forced party (dagger/autocrossbow
        ; and Pummel); no element is reachable here.
        .word   $0073
        .byte   2, OT6_PIERCE|OT6_BLUDG ; sewer rat
        .word   $00d1
        .byte   2, OT6_PIERCE|OT6_BLUDG ; vermin
        .word   $012d
        .byte   6, OT6_SLASH|OT6_PIERCE ; ultros 2: same row, one more shield
        .word   $0109
        .byte   6, OT6_PIERCE   ; ifrit
        .word   $0108
        .byte   6, OT6_SLASH    ; shiva
        .word   $010a
        .byte   7, OT6_SLASH|OT6_PIERCE ; number 024: the classes are the
                                ;   handhold while wallchange spins
        .word   $010b
        .byte   7, OT6_PIERCE   ; number 128 (body)
        .word   $013f
        .byte   3, OT6_SLASH    ; right blade
        .word   $0140
        .byte   3, OT6_SLASH    ; left blade
        .word   $010d
        .byte   6, OT6_PIERCE   ; crane (element sides verified at m6 entry)
        .word   $010e
        .byte   6, OT6_PIERCE   ; crane
        ; ---- Vector / Magitek Factory random pool: bludgeon carries most
        ; of the section (vanilla already labels six of the ten random-pool
        ; bodies as machines, a `Program NN` special-attack name), pierce is
        ; the imperial line's key, and slash comes off the section's few
        ; organic bodies.  Rhinox (formation $168) has no vanilla weakness
        ; and absorbs bolt ($075 +$17 = $04), the element the rest of the
        ; facility teaches, so it is the one body only bludgeon answers.
        ; shield counts: all twelve at 2 against a formula value of 4.
        .word   $00cb
        .byte   2, OT6_PIERCE|OT6_BLUDG ; garm: a magitek quadruped
                                ;   (Program 95) rather than a hound: pierce the
                                ;   joints or cave the housing. commonest
                                ;   body at the entrance, where the section
                                ;   teaches its rule, so it teaches both
                                ;   halves. keeps vanilla bolt|water
        .word   $00c7
        .byte   2, OT6_PIERCE   ; commando: imperial rank keeps the imperial
                                ;   answer: templar $0002 and officer
                                ;   $0175 are both pierce above, so this is
                                ;   consistent with them
        .word   $0165
        .byte   2, OT6_BLUDG    ; protoarmor: a sealed suit has no seam to
                                ;   put a point in, so it dents. vanilla
                                ;   bolt stays the ranged key
        .word   $0041
        .byte   2, OT6_PIERCE   ; pipsqueak: the swarm body (up to x5);
                                ;   pierce so Edgar's AutoCrossbow (whole
                                ;   enemy side) answers a five-stack
        .word   $0047
        .byte   2, OT6_BLUDG    ; flan: an ooze cannot be cut. its element
                                ;   is fire (Flame Sabre / Ifrit's magicite)
        .word   $0066
        .byte   2, OT6_PIERCE|OT6_BLUDG ; general: an officer in plate.
                                ;   vanilla poison answers him if Edgar was
                                ;   picked (Bio Blaster); the class row makes
                                ;   him breakable otherwise
        .word   $002d
        .byte   2, OT6_BLUDG    ; trapper: a fixed trap mechanism, smashed
                                ;   rather than stabbed. vanilla bolt|water
                                ;   backs it up
        .word   $00a0
        .byte   2, OT6_PIERCE|OT6_BLUDG ; chaser: 1202 hp, the widest break
                                ;   window in the section. two keys so
                                ;   whichever three reach it hold one
        .word   $0088
        .byte   2, OT6_SLASH|OT6_PIERCE ; gobbler: no vanilla weakness at
                                ;   all, so this row is its only key. the
                                ;   one soft body in a dungeon of machines
        .word   $0075
        .byte   2, OT6_BLUDG    ; rhinox: no weakness of any kind, and it
                                ;   absorbs bolt, so the facility's usual
                                ;   answer would heal it. armoured bulk, no
                                ;   seam, so bludgeon and bludgeon alone
        .word   $0006
        .byte   2, OT6_BLUDG    ; mag roader (minecart, 5 forced fights): a
                                ;   thing on wheels, smash the wheel. vanilla
                                ;   fire stays the reward for reading the
                                ;   fight, and its ice absorb stays a trap
        .word   $00af
        .byte   2, OT6_BLUDG    ; mag roader (the other one): same creature,
                                ;   same class; the element distinguishes the
                                ;   pair ($006 weak fire/absorbs ice, $0af
                                ;   weak ice), and one formation fights them
                                ;   together so the wrong splash heals half
                                ;   the screen
        ; sealed gate / thamasa / the floating continent
        .word   $0173
        .byte   4, OT6_SLASH    ; kefka vs leo: a solo General Leo (the
                                ;   WEDGE actor) vs Kefka, L1 HP5001. Authored
                                ;   to 4 so a solo guest at arrival level wins
                                ;   with intent but can lose careless (loss
                                ;   is a GAME OVER, event_main.asm:76471).
                                ;   SLASH is Leo's sword (the Crystal,
                                ;   char_prop.asm:336), the only tool the
                                ;   player holds here. no element add: Leo's
                                ;   whole solo kit is non-elemental (Shock
                                ;   element byte $00, Crystal element byte
                                ;   $00), so an element weakness would be
                                ;   unreachable
        .word   $012e
        .byte   7, OT6_SLASH|OT6_PIERCE ; ultros 3: the row, third verse
        .word   $0116
        .byte   7, OT6_PIERCE   ; flameeater
        .word   $00de
        .byte   1, $00          ; balloon: vanilla ice/water pops them
        ; the FC random pool: elites carry 3 shields, the rest 2; fights
        ; stay dangerous but end inside the party's HP budget.
        .word   $0020
        .byte   3, OT6_SLASH|OT6_PIERCE ; behemoth: the pool's elite
        .word   $0083
        .byte   3, OT6_SLASH|OT6_PIERCE ; dragon: the other elite
        .word   $000c
        .byte   2, OT6_SLASH|OT6_PIERCE ; apokryphos
        .word   $00a4
        .byte   2, OT6_SLASH|OT6_PIERCE ; misfit
        .word   $0003
        .byte   2, OT6_SLASH|OT6_PIERCE ; ninja
        .word   $00d8
        .byte   2, OT6_SLASH|OT6_PIERCE ; wirey drgn
        .word   $004a
        .byte   2, OT6_SLASH|OT6_PIERCE ; brainpan
        .word   $0043
        .byte   2, OT6_SLASH|OT6_PIERCE ; sky armor: IAF wave trash, repeating;
                                ;   the real gauges stay on Ultros/Chupon/
                                ;   AirForce below
        .word   $00e3
        .byte   2, OT6_SLASH|OT6_PIERCE ; spit fire: same wave
        .word   $0168
        .byte   7, OT6_SLASH|OT6_PIERCE ; ultros 4: one last time
        .word   $012f
        .byte   4, OT6_BLUDG    ; chupon: bludgeon is the only key
        .word   $0113
        .byte   8, OT6_PIERCE   ; airforce
        .word   $0145
        .byte   3, OT6_PIERCE   ; laser gun
        .word   $0147
        .byte   3, OT6_PIERCE   ; missilebay: the part-break cancel
        .word   $0146
        .byte   1, OT6_SLASH|OT6_PIERCE|OT6_BLUDG|OT6_SPECIAL
                                ; speck: any weapon in the game breaks it
        .word   $0117
        .byte   11, OT6_SLASH|OT6_PIERCE ; atmaweapon: the WoB final exam
                                ;   (hud shield glyphs cap at 6, so the
                                ;   display saturates but the count is true)
        .word   $0118
        .byte   5, OT6_SLASH|OT6_PIERCE ; nerapa: sprint fight, low gauge
        ; ---- the sealed gate cave (maps 382-386) -----------------------
        ; The fled lineage never fought here, so the area shipped on floor
        ; rows the mission party cannot answer: measured (2026-09-01, 14
        ; rounds of honest play), an L23 TERRA/LOCKE/EDGAR/SABIN dealt the
        ; $082+$048 trio ~150 of its 4191 HP in five rounds.  Vanilla's
        ; own element bits carry the area's language -- HOLY on four of
        ; five species (AuraBolt is the master key the story party holds
        ; from L6), fire on the behemoth but ABSORBED by the ninja (the
        ; area's absorb lesson) -- and stay untouched.  These rows add the
        ; class axis the coverage rule requires: every body chippable by
        ; the forced party's own hands.
        .word   $006E
        .byte   2, OT6_PIERCE|OT6_SLASH ; ninja: an assassin in cloth --
                                ;   a blade finds him.  ice|holy vanilla;
                                ;   absorbs fire (the trap stays)
        .word   $00E5
        .byte   2, OT6_SLASH|OT6_BLUDG  ; spirit: swept apart or beaten
                                ;   through.  holy vanilla
        .word   $00B3
        .byte   2, OT6_SLASH    ; the soft flier; ice vanilla
        .word   $0048
        .byte   3, OT6_PIERCE|OT6_BLUDG ; the shelled tank, in threes:
                                ;   AutoCrossbow sweeps the stack, fists
                                ;   crack the shell.  holy|water vanilla
        .word   $0082
        .byte   4, OT6_BLUDG|OT6_SLASH  ; the brute: miniboss-grade gauge;
                                ;   fire|holy vanilla is the elemental
                                ;   reward for reading past the ninja's
                                ;   absorb
        ; scripted set-pieces: no gauge drawn
        .word   $0111
        .byte   0, $00          ; guardian
        .word   $0112
        .byte   0, $00          ; guardian
        .word   $0114
        .byte   0, $00          ; tritoch
        .word   $0115
        .byte   0, $00          ; tritoch
        .word   $0144
        .byte   0, $00          ; tritoch
        .word   $ffff

; break-floor class table: one class byte per species (0..383), directly
; indexed by species id. the @formula seed reads this as f:OT6_FLOOR_CLASS,x
; so an un-authored monster is still breakable by SOME weapon class.
; generated by ff6/tools/gen_break_floor.py; do not edit the .inc by hand.
        .include "ot6_break_floor.inc"

; shield-with-count glyph cells (counts 1-6)
Ot6ShieldCellTbl:
        .byte   $65,$66,$67,$69,$6a,$6b

; pip cluster cells (0-5 filled)
Ot6PipCellTbl:
        .byte   $72,$73,$75,$76,$77,$79

; boost arrow cells (pending 1-3)
Ot6ArrowCellTbl:
        .byte   $68,$6c,$6d

; bg hud glyph cells (2bpp, verified junk-free in both formations)
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
; shield-broken: the plain grey shield, no numeral, with a big white X
; struck corner to corner across the whole cell, arms running the full
; 8x8 so they land on the background outside the shield's silhouette.
        .byte   $ff,$81,$c3,$7e,$a5,$7e,$99,$7e
        .byte   $5a,$3c,$24,$3c,$5a,$42,$81,$81
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
