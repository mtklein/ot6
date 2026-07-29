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

; [ retired: the over-character boost marks ]

; v0.2 RC playtest: "the boost chevrons sometimes turn into numbers", at
; no pattern the player could name.  They were not chevrons turning into
; numbers -- they were vanilla's damage numerals, drawn in tiles OT6 had
; taken.
;
; Three 16x16 arrow sprites used to live in obj tiles 200/202/204 (quads
; with 216-221), i.e. vram words $2c80-$2dd0.  ff6/notes/battle-ram.txt:
; 2206 labels that whole span: "$2C00 Damage Numeral Graphics / $2CC0
; Miss Graphics".  GfxCmd_0b picks a numeral's vram destination from two
; four-entry tables indexed by the rotating counter w7e632e
; (btlgfx_main.asm:24697 and :24781, tables at :24795):
;     bottom halves  $2d00,$2d40,$2d80,$2dc0
;     top halves     $2c00,$2c40,$2c80,$2cc0
; $80 bytes each (:1021).  Counter phase 2 covers boost-1 and boost-2;
; phase 3 covers boost-3.  Between them the four-phase rotation
; overwrites every one of the twelve tiles, so half of all damage numbers
; shown stamped digits over the chevrons -- intermittent, and keyed to a
; counter the player cannot see.  probe_objarrow.lua measured it: first
; divergence with counter=2 and dest=$2d80 exactly as predicted, and
; 2141 of 3000 sampled frames held clobbered art.
;
; The old comment here claimed these tiles were "verified blank +
; unreferenced by any oam entry ... idle and through attack effects".
; Both halves were true and neither was sufficient: battle init CLEARS
; $2c00-$3000 (btlgfx_main.asm:2244), so the tiles do read blank, and
; they are unreferenced right up until a numeral fires.  A snapshot
; cannot see a destination chosen at run time -- the exact "something was
; absent, so it was assumed free" failure CONTRIBUTING.md warns about.
;
; There is nowhere to move them.  Measured, not assumed: probe_objsentinel
; .lua fills the whole obj region with a sentinel AFTER init and plays a
; battle, so a zero-over-zero write cannot masquerade as untouched.  Only
; tiles 224-511 survive, and both blocks are spoken for --
; $2e00-$3000 is a blanket $400-byte init load (btlgfx_main.asm:2347) of
; hand-pointer/page-indicator/reflect/shield art, and probe_objtail.lua
; finds every tile in it either non-blank or oam-referenced;
; $3000-$4000 is monster graphics, which TfrMonsterGfx blankets with a
; fixed $2000-byte transfer every battle (btlgfx_main.asm:5410), so its
; apparent slack is only this formation's art being small.
;
; So the marks are gone rather than relocated.  Boost feedback keeps the
; channel that provably works: the party-window pip cell, which swaps to
; an arrow cluster pulsing yellow/white while a boost is pending (Ot6Boost
; @show) out of OT6's own 2bpp font cells -- glyph-canary verified, and
; battle_boost.lua gates it.  A future re-do wanting the floating badge
; back should draw it on the bg3 field map through the existing
; Ot6BgHud shadow/flush machinery (already OT6 territory, already veiled
; against entry/exit effects) rather than claim obj tiles again.

; ------------------------------------------------------------------------------

; [ per-frame bg hud: rebuild the shadow line buffer ]

; the hud lives on the bg3 field tilemap; this main-loop pass fills a
; shadow buffer in bank $7f, and the nmi flush copies it to vram during
; vblank. shadow at OT6_SHADOW, 6 lines x 14 bytes:
; (this line once read "$7f:fe00, 10 lines x 12 bytes" -- stale on both
;  counts, and $7ffe00 was never free: it is 1536 bytes into the LZ
;  decompression ring $7ff800-$7fffff, which battle init alone rewrites
;  when it decompresses StatusGfx.)
;   +0  vram word address of the line's first cell (0 = line disabled)
;   +2  five tilemap words (glyph | attr << 8)
; monsters: [shield-with-count][up to 4 weakness slots — elements, then
; weapon classes, revealed icon or '?' on both axes]. heroes: one
; pip-cluster cell. entities animate and drift, so each line remembers
; its previous address; the flush blanks the old cells when it moves.
; line layout: +0 cur addr (0 = disabled), +2 prev addr, +4 five cells.

; Lives at $7eecf1, past the end of vanilla's battle-graphics RAM chain.
; Four independent lines of evidence, since a bad answer here is what put
; this buffer inside live vanilla RAM the first time (see below):
;   1. btlgfx_ram.inc's chain ends at label w7eecf0 and is capped by
;      `.assert _ram_offset <= $7ef800` (btlgfx_ram.inc:1001) -- an
;      assembler-enforced invariant, so btlgfx cannot grow in without
;      failing the build. menu_ram.inc's chain tops out near $7e9849.
;   2. notes/battle-ram.txt:2183 documents "$ECF1-$F7FF -" (nothing),
;      with the hypotenuse table starting at $F800.
;   3. no literal reference, symbol, mvn/mvp target, or DMA/WRAM-port
;      loop in ff6/src or ff6/include lands in the range.
;   4. runtime write-watch over $7eecf1-$7ef7ff across a boss fight, four
;      forced command lists, a soak and a victory: zero writes -- while
;      the positive controls fired in the same run (DrawItemListText ran,
;      bank C1 wrote $5755-$576a).
;
; DO NOT extend past $7ef11f. PushMode7Vars (world/init.asm:1414) block-
; moves $7ef120-$7ef7ff via `mvn`, which no `sta` grep can find and which
; a fixture without a world-map battle never exercises. 1071 bytes are
; available; we use 84 and stop well short.
;
; WHY IT MOVED: this was $5762, annotated "trace-verified free". It was
; not -- $5762 sits 13 bytes inside vanilla's `ram_res w7e5755, 128`
; (btlgfx/btlgfx_ram.inc:71), and the battle command-list text drawers
; write $5755-$576a. The original trace ran a Fight-only fixture, where
; no command list ever opens, so it never saw them. Reproduced in
; tools/tests/probe_shadow_overlap.lua: DrawItemListText ran and bank C1
; wrote $5762-$5767, leaving the anchor at $00FF; the anchor latch that
; lived at Ot6BgHudLine's @done then drove every NMI flush from $00FF
; for the rest of the battle. The magitek list drawer alone does NOT
; reproduce it (it stops at $5761), which is why a magitek-only fixture
; reads as an all-clear. (The latch has since become recompute-and-
; compare -- see @done -- so an equivalent anchor stomp today would
; self-heal on the next main-loop tick. The relocation stays load-
; bearing all the same: an overlap corrupts continuously in both
; directions, and OT6 writing vanilla's live buffer was the worse half.)
                                ; OT6_SHADOW: lines, stride 14
                                ; OT6_MAPBASE: field bg3 map-base word

; [ battle-script bracket: is an animation script executing? ]

; every coordinate transient the animation engine imposes on the monster
; position arrays -- magic_init_131long zeroing/setting the $8057
; priority shifts and displacing $80cf by -$0100 (btlgfx_main.asm:
; 39277-39297), AnimCmd_80_82's all-slot x shove (:29906), AnimCmd_e2/
; e3's per-frame y animation (:33206-33279), the PushObjPos/PopObjPos
; block-hop family (:28045/:28081) -- runs from a battle animation
; script, and every such script executes inside BtlGfx_04 "execute
; battle script" (btlgfx_main @9512): action animations, monster
; specials, entry/exit effects, battle events.  scripts restore their
; transients before they end (PopObjPos restores what PushObjPos saved,
; $80/$84 restores $80/$83's y displacement, $e3 restores from
; w7e64e8), so script-free frames see settled coords by construction --
; and a script that ended WITHOUT restoring has visibly parked the
; monster there in vanilla too, at which point following it is correct,
; not stale.  so the anchor holds while OT6_SCRIPTBUSY is up and adopts
; on script-free frames.
;
; the flag is raised/cleared by the Ot6BtlGfx04_c1 wrapper behind
; BtlGfxTbl's $04 entry (same-size .addr repoint; see the block comment
; there for the C1 layout discipline).  DESIGN HISTORY, measured not
; guessed: the first cut here keyed on tick provenance instead --
; BtlGfx_01 ("called from main battle loop") = settled, WaitFrame
; ("used during animations") = transient, via same-size repoints of
; their two `jsr UpdateCharText` sites.  probe_animtick killed it: with
; a battle menu open, ~101 of 120 idle frames tick through WaitFrame
; (the menu is MODAL inside a gfx command), so the anchor held through
; the whole interactive battle and battle_hudtrack's phase 3 stayed
; red -- the sprite moved, the "recompute" never got a frame it was
; willing to adopt on.  the script container is the discriminator the
; tick path only approximated.

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
        jsr     Ot6RevealPoll   ; #33: a numeral appeared? commit the reveals
        jsr     Ot6PipStage     ; #33: stage the four live pip-row words
        jsr     Ot6WalletStage  ; #35: stage the costed-list MP wallet
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
        ; the slot is filled -- but is the monster ON SCREEN yet?  at battle
        ; entry a monster is flagged present ($3aa8) from init, while its
        ; sprite is not drawn until its fly-in animation runs: the "monsters
        ; shown" mask $201e (notes/battle-ram.txt:422 "--654321 monsters
        ; shown"; the sprite drawers gate on it, btlgfx_main.asm:5639/:5772,
        ; and DoMonsterEntryExit SETS a monster's bit as its entry completes,
        ; :45554) holds 0 for that whole fade-in window -- measured $00
        ; across probe_caveentry f84..128, while the sprites are absent.  the
        ; hud gated only on $3aa8, so it painted each entering monster's
        ; shield/'?' cells into empty space: a scatter of white glyphs on the
        ; still-dark battlefield BEFORE the fight resolved, worst with the
        ; cave's 3-5 fly-in trash (Cirpius/Hornet/Bleary), which is where the
        ; v0.3-rc1 playtest first caught it ("a bunch of characters overdrawn
        ; in white text ... when there are a bunch of enemies").  the entry
        ; ANIMATION itself is already veiled (Ot6EntryExitVeil); this closes
        ; the gap BEFORE it by gating the hud on the same mask the sprites
        ; use.  (a dead monster also clears its $201e bit, but the $3eec
        ; dead-cell path below already blanks that line -- the two agree.)
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
        ; a static battlefield means ZERO anchor stores across all six lines
        ; -- the exact invariant battle_hudtrack's write watch asserts. (this
        ; store ran unconditionally for years; empty slots were rewriting
        ; $0000 over $0000 every frame, invisible but noisy.)
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
        ; weakness slots into cells 1-4: elements first (vanilla's own
        ; data), then the class weaknesses, sharing the same four cells.
        ; a fifth weakness truncates — the deliberate cap: the row is
        ; five cells wide (the shadow strip has no room for more without
        ; moving the $57c0+ occupants), and no authored WoB species
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
        jcs     @edone          ; past slot cell 4 (offsets +6..+12) —
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
@q:     lda     #$bf            ; '?', default attr already in place
        sta     f:$7e0000+OT6_SHADOW+4,x
@next:  asl     OT6_SCR_BIT
        inc     OT6_SCR_IDX
        bra     @elem
@cls:   ; class-weakness slots: same claim/cap flow, from the authored
        ; class mask (OT6_BP_CLASS monster half, seeded at battle init) and the
        ; revealed-classes byte the chips and codex maintain. the icons
        ; are the vanilla item-class glyphs, white like the '?' (the
        ; default $21 attr from the fill is already in place — only the
        ; glyph byte is written, exactly like the '?' cell).
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
@cq:    lda     #$bf            ; '?', default attr already in place
        sta     f:$7e0000+OT6_SHADOW+4,x
@cnext: asl     OT6_SCR_BIT
        inc     OT6_SCR_IDX
        bra     @cbit
@edone: plx
@done:  ; commit: recompute-and-compare, adopted only on quiet ticks.
        ; HISTORY. this was a once-per-battle latch ("recomputing every
        ; frame made the line jitter and blink on attack-animation coord
        ; transients"), which also made any post-arm divergence permanent:
        ; the founding $5762 overlap corruption (probe_shadow_overlap), a
        ; Cmd_20 reload swapping a slot's monster, any scripted move. the
        ; transients are now READ and NAMED (Ot6ScriptBegin_ext's block
        ; comment lists them with line numbers): every one runs inside a
        ; battle animation script, so the anchor HOLDS while one executes
        ; (OT6_SCRIPTBUSY, bracketing BtlGfx_04) and recomputes on
        ; script-free frames, where coords are settled by construction
        ; (probe_animtick MEASURED the beat: menu-idle frames are mostly
        ; WaitFrame ticks, so tick provenance was the wrong gate -- the
        ; script container is the right one). identical frames
        ; compare equal and write nothing -- the jitter fix -- while a
        ; genuine change (one that survives into a quiet frame) is
        ; adopted within a frame or two -- the staleness fix. gated by
        ; battle_hudtrack (all three directions), hud_stability,
        ; battle_whelkwipe, battle_banner, and the visual goldens.
        ;
        ; the row source is NOT the frame's raw $804b: cur_poi_set
        ; (btlgfx_main.asm:1032, run every frame at :1738) derives it as
        ; $80cf + height*8 - 8 + $8057, and $8057 is a sprite-priority
        ; bias with a PATH-DEPENDENT value -- seeded per species from
        ; MonsterOverlap at monster load (btlgfx_main.asm:4671; whelk
        ; head = 8, guards = 0), zeroed for ALL slots by every $80/$83
        ; animation init (magic_init_131long, :39277), and never re-
        ; seeded until the next monster load (the whelk retract's Cmd_20
        ; reload among them). raw $804b would therefore hop the whelk
        ; head's line one row the first time any spell lands and park it
        ; there. so: strip the LIVE $8057 back out and re-apply the
        ; LOAD-TIME species seed -- exactly the row the latch captured
        ; at arm time, now stable across the whole $8057 lifecycle. the
        ; column source $800f = $80c3 + width*4 has no such term. 8-bit
        ; low-byte reads throughout, as always: transients riding the
        ; high bytes ($80/$83's -$0100 y displacement, stashed/restored
        ; at :39292/:29884) never see us. (the slot-5 leap/seize writer
        ; at btlgfx_main.asm:1133 bypasses monster load, so its species
        ; stash is stale -- unowned territory, same as under the latch:
        ; no WoB-covered content drives it.)
        lda     f:$7e0000+OT6_SCRIPTBUSY
        bne     @keep           ; a battle script owns this frame:
                                ;   coords may be transients -- hold
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
                                        ;   is still the commit -- the
                                        ;   nmi flush can fire mid-frame,
                                        ;   and the flush's prev/cur pass
                                        ;   blanks the vacated cells)
@asis:  plx
@keep:  shorta0
        rts
.endproc

; monster slot (0-5) -> its bit in the $201e "monsters shown" mask. slot s is
; bit s: verified by measurement, probe_caveentry read $201e=$1c for the three
; Cirpius that loaded into slots 2/3/4.
Ot6ShownBitTbl:
        .byte   $01,$02,$04,$08,$10,$20


; ------------------------------------------------------------------------------

; [ vblank flush: shadow lines -> bg3 field tilemap ]

; called from the battle nmi right after the oam dma.

                                ; OT6_HUDCOPY ($57de) is retired and NOT ours:
                                ;  $57de is
                                ;  inside vanilla's `ram_res w7e57d5, 128`.
                                ;  kept only so the memory map records that
                                ;  this range is vanilla's, not free.)
                                ; OT6_ATKCLASS is the executing attack's
                                ; class byte: one of
                                ;   $01/$02/$04/$08 (+$80 null-break), 0 =
                                ;   classless. set by the three load hooks,
                                ;   read per target by Ot6ClassChip. lives
                                ;   in retired OT6_HUDDIRTY's byte — inside
                                ;   the m2 trace-verified strip and the
                                ;   InitBP clear. (first pick $57d6 turned
                                ;   out to be live vanilla scratch: the
                                ;   battle_class write-watcher caught
                                ;   foreign bytes $84/$85/$ab there.)

; weakness codex species stash: one word per monster slot so the chip procs
; can find the active save page's species entry at reveal time.
                                ; OT6_SPECIES: per-slot species stash (6 words)
                                ; OT6_PIPCUR/PIPPREV/PIPCELL: retired
                                ;   (#33 -- see ot6_memory.inc)
                                ; OT6_LASTLR: last frame's L/R bits
                                ; OT6_RESTAGE: open list wants a re-render
                                ; OT6_FONTDIRTY: font re-lay stages remaining.
                                ; RELOCATED from $57d5: vanilla reserves
                                ; $57d5..$5854 as the battle name-scratch
                                ; string (ram_res w7e57d5,128 — GfxCmd_01
                                ; attack names, GfxCmd_11 monster specials,
                                ; swdtech/esper name loaders ALL write
                                ; byte 0 nonzero), so every named-attack
                                ; banner spuriously triggered a full
                                ; ~46-scanline font re-lay in the nmi tail
                                ; and tore the frame (probe_banner: flush
                                ; end at scanline 292; battle_banner is
                                ; the regression gate). $57b9 is the spare
                                ; byte after OT6_ATKCLASS, inside the m2
                                ; trace-verified strip and the InitBP @clr
                                ; (probe_57b9 write-watch: only bank-F0
                                ; writers).
; CAREFUL: the boundary is NOT "$57d5+ is vanilla's alone" (an earlier
; note here said that, and it is what made $5762 look safe). btlgfx_ram.inc
; reserves TWO buffers: w7e5755,128 AND w7e57d5,128 -- both vanilla's.
; What the probes actually establish is narrower and still holds:
; vanilla's writes into the $5755 buffer stop at $576b, so the OT6 strip
; from $57b6 up is empirically clear. Below $576b is NOT. See OT6_SHADOW.
OT6_RELAY_STAGES := 3           ; icons, glyphs x2 (~128b each). was 6:
                                ;   three arrow-tile stages retired with
                                ;   the over-character boost marks.

; the strip $57ba-$57bf (between OT6_FONTDIRTY and OT6_SPECIES,
; inside the m2 trace-verified free range; probe_57ba_strip write-watch:
; only bank-F0 writers). InitBP's @clr loop deliberately stops at $57b9:
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
                                ; OT6_RANDBTL marks THIS battle as random
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
                                ;   battle -- probe_57ba_strip measured
                                ;   $ff on the srm-boot line): the marker
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
; four bytes, no code motion). the entry/exit effect family — the whelk
; retract's FADE_DOWN/FADE_UP wipes especially — sweeps the battle-field
; bg3 region with a per-scanline scroll wave (hdma #2, fed from the
; w7e4af5 table the effect animates), and it assumes the field map holds
; nothing visible but its own mask tiles: vanilla blanks even its banner
; rows to the $01ee junk fill before scrolling. our under-enemy hud
; lines ride that same map, so the wipe smeared their glyphs across the
; screen (v0.1 whelk playtest; battle_whelkwipe is the regression gate —
; veiling exactly the hud words removed every stray pixel, measured
; against the base image frame by frame). while the veil byte is set the
; nmi flush writes the $01ee fill over each live line instead of its
; cells — the field map is word-identical to vanilla's for the whole
; animation — and the shadow itself is untouched, so the first flush
; after the effect repaints the hud exactly as built (or blanks it, if
; the monster left with the effect). a8/i16 at every call site (battle
; gfx script context); the anim returns a8/i16 on every path, sep #$20
; is belt and suspenders.

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
        ; a battle dialogue clobbered our font cells? re-lay them ONE
        ; ~128-byte slice per nmi (OT6_FONTDIRTY counts stages left).
        ; the full 768-byte re-lay is ~46 scanlines of PIO — more than
        ; a whole vblank — so a single-shot re-lay tore the frame it
        ; ran on (probe_banner measured flush end at scanline 292/262).
        ; staging self-heals over 6 frames and each slice is gated on
        ; the live v counter: only start one with >= 14 lines of vblank
        ; left (slice ~9 + flush ~3 + hdma/inidisp tail ~2), else retry
        ; next nmi. quiet-battle flush start measured 240-250, so the
        ; gate passes within a frame or two.
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
        ; TWO WRITE DISCIPLINES BELOW, on purpose (audit 2026-07-19).
        ; steady-state cell writes (prev == cur) are NOT v-gated: a write
        ; spilled past vblank is dropped by the PPU, and the rewrite-
        ; every-nmi design heals it next frame -- rewriting every nmi is
        ; already mandatory because the animation-bg restore junk-fills
        ; the area every other frame during monster actions (see the
        ; call-site comment, btlgfx_main @0c17). one-shot transitions
        ; (prev != cur: a line moved, enabled at a new address after a
        ; move, or disabled) have NO next-frame rewrite to heal them --
        ; a dropped blank-at-prev would strand stale glyphs -- so they
        ; are admission-gated on the live v counter and DEFERRED when
        ; late: prev only advances after the blank ran inside an
        ; admitted window, so the whole transition redoes next nmi
        ; until it lands. within the window a drop is impossible by
        ; arithmetic: admission ends at v=248, the worst burst (all six
        ; lines + pip transitioning at once) is ~70 words ~ 9 scanlines
        ; at the measured PIO rate (~8 words/scanline, the font-slice
        ; numbers above), ending ~257 < 262. residual accepted risk,
        ; documented not hidden: a transition deferred into a veil
        ; window leaves old glyphs one extra frame if the nmi is ALSO
        ; late -- needs a genuine move adopted on the exact frame an
        ; entry effect starts plus consecutive late nmis; no covered
        ; content produces the first half, and defer-retry bounds it
        ; at frames, not battles.
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
        ; the blank word is vanilla's $01ee junk fill, NOT $21ff.  cells a
        ; line abandons (a move or a disable) are rewritten ONCE, here, and
        ; then belong to nobody: no next-nmi repaint heals them, so whatever
        ; word this writes sits in the field map until vanilla's next
        ; ClearBG3TileBuf.  $21ff -- priority-set char $1ff -- was invisible
        ; in 8x8 (the char is a blank cell in the $5800 font page), but under
        ; an animation's bg3-16x16 window (the $896f flips the veil below
        ; already handles for LIVE cells) a 16x16 map cell renders char n
        ; plus n+1/n+$10/n+$11: $1ff pulls tiles $200/$20f/$210 -- past the
        ; font page, into the animation-gfx region -- at TOP priority.  the
        ; measured face (probe_lete_entrance, the Lete River forced battle 8,
        ; both die rolls): the monster-entrance slide walks every hud line
        ; sideways across the map, abandoning 63-92 cells ($21ff each, map
        ; dump in the probe log) while the slide itself holds $896f=$59 --
        ; and those cells render as a full-width band of white junk over the
        ; entering monsters for the effect's last ~15 frames, until the
        ; effect's own cleanup refills the buffer.  the owner's "white flash
        ; at the START of the fight, as the enemies are appearing ... too
        ; quick to screenshot" -- reliable in exactly the fights whose
        ; entrance slides shown monsters under live hud lines.  $01ee is the
        ; word vanilla holds in every field cell it did not draw itself,
        ; priority-CLEAR, safe in BOTH tile modes (its 16x16 neighbors
        ; $1ef/$1fe/$1ff are priority-clear with it, under the battle bg) --
        ; the same word the veil below writes over live cells and the entry
        ; wipes sweep.  an abandoned cell is now word-identical to a cell we
        ; never touched.
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
        ; hud glyph TILES unreliable? veil (hide) the hud, don't draw from them.
        ; a battle dialog window (window_mess_open_init, _c142e4, btlgfx_main
        ; .asm:9264) opens by ClearDlgGfxBuf-ing the whole small font and
        ; re-uploading it to $5800 in four TfrDlgTextGfx passes -- a full
        ; $5800-$5fff blank + message glyphs, which zeroes OUR borrowed glyph
        ; cells ($64-$79, $eb-$fd: all blank in SmallFontGfx).  the vanilla
        ; staged restore (Ot6FontRestoreMark, hooking _c143b9) fires on the
        ; dialog CLOSE only, and the window keeps re-uploading as it prints, so
        ; from open until the close re-lay finishes -- and for the WHOLE fight
        ; when the script never issues a close (measured: probe_moogfont /
        ; probe_moogjunk, battle 115 Kefka flashback -- the under-enemy hud
        ; drew break/shield/icon glyphs from blanked tiles for ~5000/9000
        ; frames: junk over and around the enemies).  so while a dialog window
        ; is up (w7e64d5, the open latch: _c14312 sets it, _c143cc/BattleEvent
        ; Cmd_10 re-lay then clear it) OR a re-lay is mid-flight (OT6_FONTDIRTY,
        ; the close's staged restore), hold the veil: the hud is cleanly hidden
        ; (vanilla's $01ee fill, exactly like an entry/exit anim), never junk,
        ; and repaints once the tiles are whole again.  neither flag is set by
        ; the attack-name banner (battle_banner: FONTDIRTY stays 0, hud stays
        ; painted).  the dialog draws in $80+ letter cells, disjoint from ours.
        lda     f:$7e0000+$64d5                  ; dialog window open?
        and     #$00ff
        bne     @veil
        lda     f:$7e0000+OT6_FONTDIRTY          ; font re-lay in flight?
        and     #$00ff
        bne     @veil
        ; battlefield bg3 in 16x16 TILE MODE?  an animation owns the layer --
        ; veil.  the animation inits flip the battlefield's $2105 shadow
        ; ($896f) to 16x16 bg3 tiles for an effect's run -- InitAnimType's
        ; bg1-target and bg1-gfx paths (btlgfx_main.asm:26304/:26348,
        ; `ora #$40`/`ora #$50`) and the circle/mask init families
        ; (:47410 `ora #$48`, :48362 `and #$f7 / ora #$40`) -- because the
        ; effect uses bg3 as its own canvas/color-math mask.  vanilla clears
        ; the field map first (ClearBG3TileBuf/TfrBG3Tiles) and can assume
        ; nothing of its own shows: its $01ee fill is priority-CLEAR,
        ; underneath the opaque battle bg in every mode.  our hud cells are
        ; priority-SET ($21xx), and in 16x16 mode a map cell renders at
        ; DOUBLED size and position pulling three NEIGHBOR tiles (char n
        ; draws n, n+1, n+$10, n+$11) -- so any live line inside the
        ; effect's scroll window paints doubled break-icon blocks flanked by
        ; neighbor-tile bars: "break icons amongst other things that look
        ; like junk memory", over and around the monsters, in fights with no
        ; dialogue -- the owner's residual v0.2 sighting after the fly-in
        ; and dialogue-clobber fixes.  measured (probe_junk16, map 96's
        ; natural Cirpius x3, hud rows 5/8): a plain CURE runs 42 frames at
        ; $2105=$59 with both rows inside the (0,0) window -- 424 flagged
        ; frames, screenshots match the report; Fire's $51 phase (priority
        ; flag dropped) and plain Fights ($19: bg1-only 16x16) stay
        ; invisible, which is why the sighting was intermittent.  while the
        ; bit is up, hold the veil: $01ee is exactly the word vanilla wants
        ; in every cell it did not draw itself, in both tile modes.  (the
        ; main loop can flip $896f mid-frame between our nmi reads; the
        ; exposure is bounded at one partial frame at effect onset, below
        ; per-frame sampling -- battle_hudanim16 samples per frame and
        ; passes.)
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
        ; #35 wallet pseudo-line: current MP over the open costed list
        ; ($7c00 ability-list map, single band -- measured, probe_wallet:
        ; no +$100 twin renders).  the one-shot close/switch blank uses the
        ; same defer-when-late cure as the lines (a magic or item list
        ; opening over a stale wallet would show it); the steady-state cell
        ; writes rewrite every nmi like everything else here.
        ;
        ; the WHOLE wallet+rows pass is v-gated as a unit: it grew the nmi
        ; tail to ~13 words, and on a late-entry nmi (entry at v=225, flush
        ; start 256 -- battle_banner caught the one frame) the tail wrapped
        ; past vblank.  everything here is steady-state or defer-retry, so
        ; a skipped nmi repaints in full on the next one.
@pip:
        ; #35 wallet pseudo-line: current MP over the open costed list
        ; ($7c00 ability-list map, single band -- measured, probe_wallet).
        ; PAINTED ONLY WHEN IT CHANGES, never per frame.  The steady-state
        ; repaint every other cell here uses cost the battle cannot afford:
        ; with ~13 extra words a frame the engine's own line transfers got
        ; pushed past vblank and the window state machines that wait on them
        ; hung -- battle_runic's negative phase sat with a menu open and every
        ; ATB frozen (2/2 runs; clean with just this block disabled, bisected
        ; in five builds).  A change-only write costs zero words on a quiet
        ; frame, and the value only moves on open/close and when the charge
        ; debits MP -- which is exactly the moment #33 wants it to move.
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
        lda     #$21ff          ; $21ff: this is a MENU map (no anim flips its
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
        ; live pip pseudo-line: ONE cell in the party-window menu map --
        ; deliberately the same footprint vanilla-era OT6 always had.  #33's
        ; first cut painted all four rows every nmi and BROKE THE FIGHT: with
        ; 13 words a frame going into this map, battle_runic's negative phase
        ; hung with a menu open and every ATB frozen (2/2 runs, against 2/2
        ; passes on the pre-change ROM and a clean pass with just this block
        ; disabled -- bisected in four builds).  The map is the menu engine's
        ; own; we paint one cell in it, as before.  WHICH cell is what #33
        ; changed: Ot6PipStage points it at the active character while a menu
        ; is open, and at the character who just spent BP for a few frames
        ; after (OT6_PIPTAIL), so the drop still lands on the charge frame.
        ; the party window is double-buffered -- each name row is staged at
        ; map row 1+2r AND at 9+2r (+$100 words) and the scroll picks a band
        ; -- so paint BOTH (the M2 lesson: writing only the low band made
        ; boost feedback invisible whenever the high band was up).
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
        lda     #$21ff          ; $21ff HERE is correct, on purpose: the pip
                                ;   lives in the party-window MENU map, whose
                                ;   hdma $2105 sections ($8973/$8977) no anim
                                ;   ever flips to 16x16 -- the field-map blank
                                ;   above had to become $01ee (the entrance-
                                ;   flash fix), but $01ee is the FIELD map's
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
; clobbers a; carry SET = too late, defer.) constants mirror the font
; slice gate above: v must be in [225,248] -- past 248 the worst-case
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
        bcc     @l0             ; v < 225: not vblank (defensive) -- defer
        cmp     #$f9            ; carry = (v >= 249) = too late
        rts
@l0:    sec
@l1:    rts
.endproc

; [ l/r boost input ]

; runs every main-loop frame from the hud builder (db=$7e, a8/i16).
; while a battle menu is open AND the actor's action is still being
; composed, R raises the active character's pending boost (cap 3, and
; never past their bp) and L lowers it.  DISPLAY is no longer here: the
; live cell painter (Ot6PipStage -> the flush's one-cell pseudo-line)
; points that cell at the active character while composing and at the
; character who just charged for a few frames after, showing the FULL
; bank either way -- so the visible drop is Ot6ActionEnd's charge frame
; (#33). window_open still re-stages every row on the next open
; (Ot6PipGlyph_ext, same bp reading).
;
; "still being composed" is $32cc,y = $ff, the actor's pending-action
; command-list pointer (battle_main.asm:254 sets it to $ff when nothing
; is pending; CreateNormalAction:@4ecb tests it the same way). Measured
; across a real menu walk (probe_lateboost.lua): $ff through command
; select, the ability list AND target select, then a live pointer the
; instant the target is confirmed.
;
; That boundary is the fix for a v0.2 RC playtest report ("you can boost
; after selecting the ability" / "it looks cosmetic"). Two different
; things were happening either side of the confirm, and only one was a
; bug:
;   * DURING target select the spend is fully effective and stays legal
;     -- DESIGN.md prices boost "when confirming an action", and
;     Ot6QueueFold reads pending from CreateAction, which runs after
;     target select. Measured: R at the target cursor folded Fire to
;     Fire 3 ($09 at $3410), charged 2 bp (5 -> 3), and dealt tier-3
;     damage. The playtester read it as cosmetic because the spell-list
;     preview -- the thing the Narshe school teaches them to watch -- is
;     closed by then, and because the over-character chevrons they WERE
;     watching were rendering as damage numerals (the other defect).
;   * AFTER the confirm it was theft. CreateAction has already frozen
;     the tier, but Ot6ActionEnd still charges whatever pending reads at
;     action end. Measured: two more R presses post-confirm took pending
;     2 -> 3, the queued spell stayed Fire 3, damage was identical (319
;     both ways), and bp fell 5 -> 2. Three points paid, two points'
;     worth delivered.
; Refusing silently rather than buzzing: the menu lingers open for a few
; frames after every confirm, so a buzz here would fire on ordinary play
; and teach the player that a legal boost had been rejected.

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
        ; (the $32cc + $2bae-ring test lives in Ot6CommittedSlot now --
        ; the live pip painter needs the same answer per row, and the two
        ; readings must never diverge. history of the ring half: an L/R
        ; edge between the C1 confirm and C2's ring drain changed the
        ; CHARGE without changing the tech -- probe_bushidobusy.)
        pha
        lda     $62ca
        and     #$03
        jsr     Ot6CommittedSlot
        bcc     :+
        pla
        rts                     ; committed: display only
        ; ...and a LATCHED SLOT SPIN is committed the same way (#33): the
        ; first reel press latched the spin's tier (Ot6SlotRig ->
        ; OT6_SLOTTIER) and Ot6SlotCommit re-banks that latch at the queue
        ; write, so an L/R edge mid-spin changes NOTHING the reels or the
        ; charge will see -- yet it still chinged/clicked (the slot-tiers
        ; landing, 9229881, silenced the charge but not the acknowledgment).
        ; input goes fully inert from the first press: no bank, no sound.
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
        lda     #$80
        sta     OT6_RESTAGE     ; open lists re-fold their names
        bra     @show
@deny:  inc     $95             ; error buzz: at cap or out of bp
        bra     @show
@tryl:  bit     #$20            ; L: boost down
        beq     @show
        lda     OT6_BOOST_REVEALED,y
        beq     @show
        dec     a
        sta     OT6_BOOST_REVEALED,y
        inc     $94             ; cursor click: boost taken back
        lda     #$80
        sta     OT6_RESTAGE     ; open lists re-fold their names
@show:  rts                     ; display is Ot6PipStage's job now (#33)
@off:   rts
.endproc

; ------------------------------------------------------------------------------

; [ is a character slot's action committed? -- the one reading (#33) ]
;
; committed = the actor has a live command-list pointer ($32cc != $ff: C2
; holds the action) OR the confirmed action still sits in the user-action
; ring ($2bae + 0/8/$10/$18, char slot or $ff -- GetPlayerAction's ring,
; battle_main.asm:12643; the C1 confirm freezes the payload but $32cc only
; goes live when C2 drains the ring).  Ot6Boost gates input on this (a spend
; after commit is charged but buys nothing) and Ot6PipStage picks each row's
; glyph with it (a committed bank displays FULL until the charge lands --
; the pip drop then IS the Ot6ActionEnd frame).  a8/i16, db=$7e.
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

; [ stage the live pip cell -- the drop lands on the charge frame (#33) ]
;
; ONE cell (the flush paints it into both window bands), pointed at:
;   - the ACTIVE character while a battle menu is open -- the compose-time
;     feedback, arrow cluster while a boost is pending and uncommitted;
;   - the character who just SPENT bp for OT6_PIPTAIL frames after their
;     action resolved (Ot6ActionEnd arms both), so the drop is visible even
;     though no menu is open at resolution.
; The glyph is the FULL bank, not bank-minus-pending: a committed spend keeps
; showing its pips until Ot6ActionEnd's charge writes bp, which is exactly
; what makes the visible drop and the mechanical event the same frame.  The
; measured desync this replaces: the staged party rows painted the spent
; value at the menu restage, ~570 frames before the charge (probe_clockwork
; on the pre-change ROM: spent glyph f605, charge f1169).
; a8/i16, db=$7e (Ot6BgHud_ext's context).  clobbers a; preserves x/y.
.proc Ot6PipStage
        .a8
        .i16
        ; the CHARGE WINDOW WINS.  While OT6_PIPTAIL runs, the cell follows
        ; the character who just spent BP even if a menu is open for someone
        ; else: one cell can only show one row, and the drop landing on the
        ; resolution frame is the whole point of #33.  The other rows are
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
@pips:  lda     OT6_BP_CLASS,y  ; the FULL bank (see the block comment)
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

; [ stage the costed-list MP wallet (#35: current MP where the costs are) ]
;
; while a costed ability list is open -- the tools shell (menu state $30:
; Blitz, Bushido, and real Tools) or the Dance list (#34) -- the actor's
; CURRENT MP is painted as [M][P][d][d][d] into the list window's top row,
; right side: map words $7c16-$7c1a, i.e. row 0 cols 22-26 of the $7c00
; ability-list map (measured live, probe_wallet: the list rows stage at
; $7c00 rows 1/3/5/7 cols 2-26, row 0 is never staged and renders legibly
; on the window's top edge).  the value is read from $3c08 -- the very cell
; CalcAttackEffect's universal charge debits -- so the wallet drops on the
; exact frame the queued verb's cost is paid (#33's clockwork rule for
; free).  cells stage here in the main loop; the nmi flush paints them
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
        cmp     #$21            ; dance list browse (#34; measured live in
        beq     @on             ;   battle_dancemp: open $1f -> browse $21)
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
        lda     $3c08,x         ; current MP -- the charge's own cell
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

; [ re-render the open magic list when boost moved ]

; polled once per frame from the battle main loop just before the
; menu-text pump. runs menu state $0d's WORK — clear the line
; transfer buffer, stage the four visible row-pairs from the scroll
; top, arm each line's vram transfer — without its completion
; transitions (those queue window-flow steps that eventually walk
; the window shut; re-entering the state taught us that the hard
; way). the re-staged rows run through Ot6PreviewList_ext, so the
; fold preview redraws with the current pending; the window stays
; parked in browse the whole time. a8/i16, db = $7e.

; the staging routines are jsr-linkage C1 locals; call them from here
; with the rts->rtl thunk: [bank][ret16][thunk16] on the stack, jml —
; their rts lands on Ot6C1Rtl, whose rtl comes home.
.macro jsr_c1 target
        phk
        pea     :+ -1
        pea     .loword(Ot6C1Rtl)-1
        jml     f:target
:
.endmacro

; flag protocol: 0 idle, $80 fresh request (Ot6Boost), 1-3 lines left
; in an active cycle. one line per frame: the nmi's _c15d99 drains a
; single $80-byte line buffer ($5e4d) per frame, which is exactly why
; vanilla's state $0d stages one row-pair per tick.

.proc Ot6RestageGate_ext
        .a8
        .i16
        lda     f:$7e0000+OT6_RESTAGE
        beq     @no
        lda     $7bca           ; menu closed: stale flag
        beq     @drop
        lda     $7bc2           ; the per-frame menu state: $0e = magic
        cmp     #$0e            ; list up and browsing (idle machinery)
        bne     @wait
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
        ldx     $62ca           ; active character slot (vanilla does
        lda     $8913,x         ; this same 16-bit ldx)
        sta     $7ba6           ; draw cursor = this list's scroll top
        lda     #$80
        sta     $7ba5           ; reset the 4-line staging cycle
        plx
        jsr     @draw           ; line one, now
        lda     #$03            ; three more, one per frame
        sta     f:$7e0000+OT6_RESTAGE
        rtl
@wait:  lda     f:$7e0000+OT6_RESTAGE
        bmi     @no             ; fresh request: keep it until browsable
@drop:  lda     #$00            ; cycle complete (or abandoned mid-way)
        sta     f:$7e0000+OT6_RESTAGE
@no:    rtl
@draw:  lda     $7ba6           ; stage one row-pair and arm its
        jsr_c1  DrawMagicListText       ; transfer; carry = list done
        jsr_c1  _c15729
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
        lda     f:$7e3e9c,x     ; bp -- the FULL bank (#33): the staged cell
                                ;   agrees with the live painter, which shows
                                ;   a committed spend at full strength until
                                ;   Ot6ActionEnd's charge lands (the old
                                ;   bp-minus-pending here put the drop at
                                ;   menu restage, ~900 frames early)
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
; shieldless (no display — whelk's shell stays the wrong answer, exactly
; as vanilla intended; scripted set-pieces draw no gauge: a silent hud
; says "this one is theater"). format: .word species id (monster prop
; offset / 32), .byte shields, .byte class weaknesses; $ffff terminates.
; unlisted species use the 2 + level/8 formula and carry no class
; weakness. elemental rows are NOT here — vanilla element bits stay in
; monster data, and the element ADDS in bosses-wob.md are m6 data entry.
; shields/classes follow docs/design/bosses-wob.md v1; deviations:
;   - lobo keeps 3 (authored pre-bosses-wob; the doc proposes 2)
;   - piranha and iron fist wear their boss-block's class row (the doc
;     gives fight-level rows, not per-add rows): judgment calls.
;   - guardian/tritoch: multiple records each, WoB story order can't
;     tell them apart from here — ALL drawn shieldless for the WoB;
;     the WoR pass must re-author the real WoR fights' records.
;
; not a deviation, but it reads like a gap: kefka has one row and the
; imperial camp gags are NOT it — they need none. $14a is
; MONSTER::KEFKA_NARSHE (const.inc:1222), and it appears in exactly two
; of the 576 formation records — 489 and 505 — with `battle 57` -> group
; 57 -> 505 the narshe defense. the camp gags run `battle 56`
; (event_main.asm:40683 and :40743) -> group 56, whose two slots BOTH
; point at formation 504 — and 504 has no monster in it: present mask $00
; and all six id slots the $01ff empty sentinel (battle_monsters.dat
; +$1d88 = 00 00 ff ff ff ff ff ff 00 00 00 00 00 00 3f; the mask is
; rolled into $3aa8 at battle_main.asm:7692, and the sentinel skips
; LoadMonsterProp at :7718). nothing is loaded, so Ot6SeedShields —
; reached only from the monster/rage load — never sees them. what those
; fights run on instead is character ai: battle_prop.dat +$7e0 sets $2f49
; bit 7 with $2f4a = $04 (LoadBattleProp :7994, dispatch :7813), script
; kefka_imp_camp_1, whose slot 0 is
; CHAR_PROP::KEFKA_1|CHAR_AI_FLAG_ENEMY_CHAR (char_ai.asm:163) — the
; event has already dressed a party slot as him (char_prop VICKS,
; KEFKA_1, event_main.asm:40675; CHAR::VICKS = 15, CHAR_PROP::KEFKA_1 =
; $29) and revives that actor between rounds (clr_status VICKS, DEAD /
; max_hp VICKS, :40739) because he has character hp. gauging a character
; actor would be a per-formation feature, not a table row.
;
; this comment used to say vanilla shared ONE species between the camp
; and narshe and that the camp fights "inherited" the $14a row. they
; cannot: the camp has its own id ($16f, MONSTER::KEFKA_IMP_CAMP,
; const.inc:1259) and even that is only the actor's ai script, never a
; loaded record. see docs/design/bosses-wob.md "6-7. Imperial Camp".
Ot6ShieldTbl:
        ; narshe intro / escape
        .word   $0000
        .byte   2, OT6_PIERCE   ; guard: armored infantry, the tekmissile
                                ;   probe (2 = formula value, kept honest)
        .word   $0019
        .byte   3, OT6_PIERCE   ; lobo: bitier trash, and the table's
                                ;   permanent regression coverage
        .word   $0100
        .byte   0, $00          ; whelk (the shell)
        .word   $0134
        .byte   4, OT6_PIERCE   ; whelk head: the first boss break.
                                ;   $0134 'Head' is the narshe fight
                                ;   (gen_whelk measured it at $57c0);
                                ;   m1 authored $0135, the WoR
                                ;   presenter's head, so the real head
                                ;   had been seeding by formula (2).
                                ;   note: $0134 has NO vanilla fire
                                ;   weak — the tutorial's fire probe
                                ;   is an m6 element ADD, not vanilla
        .word   $0064
        .byte   4, OT6_PIERCE   ; marshal: mog's fight, mog's class
        ; mt. kolts / lete river
        ; ---- mt. kolts trash: the v0.3 rows that make the break happen.
        ; all three carry TWO shields, and that number is the finding, not
        ; a taste. a break only opens a WINDOW if the target still has more
        ; hp than the breaking hit; the breaking hit is 4x base through the
        ; element channel (vanilla weak x2, no Ot6ShieldedDmg because the
        ; shields are already gone, then Ot6BrokenDmg x2) and 2x through
        ; the class one. so the count is really "how late does the break
        ; land", and measurement #8 swept 1/2/3 live with bal_party's
        ; BUFF_SHIELDS against the real pools:
        ;
        ;   shields   cirpius x3        tusker x2
        ;   3 (fmla)  break at 100%     break at 100%
        ;             actions_broken 0  actions_broken 0
        ;   2         break at 78-90%   break at 51-57%
        ;             actions_broken 1  actions_broken 1-2
        ;   1         (not swept)       break at 28-53%
        ;             --                actions_broken 0
        ;
        ; the formula's 3 is one chip too many: by the time the last shield
        ; falls the party has already spent the monster, so the break lands
        ; on a corpse -- which is exactly what "breaks 6/6, uptime 1 frame"
        ; meant in measurements #5 and #6, restated with a cause. and 1 is
        ; one too few for the ELEMENT channel: with no chip to soften it
        ; first, 4x base (bio blaster measures ~87 a target on a poison-weak
        ; body, so ~350) simply exceeds a 270-hp tusker outright and the
        ; break is the kill again. 2 is the count where the loop exists.
        ;
        ; brawler takes 2 for consistency with its pool-mates, and it is
        ; the one authored species whose window does NOT open at it: 137 hp
        ; against an 84-point breaking hit has the margin in principle, but
        ; terra and locke spend it before edgar's SECOND swing lands, and
        ; with one chipper against a pair the two chips often land on
        ; different brawlers and neither breaks. measured, `boost3`: 2.0
        ; chips, 0 breaks. what would close it is a slashing carrier whose
        ; per-hit damage is small enough to chip twice cheaply -- cyan's
        ; flurry, edgar's chainsaw -- and neither exists at mt. kolts. the
        ; row still buys the reveal, the chips, and (when mashed, where
        ; edgar swings the blade every turn) a real break: 3.0 chips, 1.0
        ; breaks. it is coverage plus a lesson, not a window; said plainly
        ; rather than tuned until the number looked right.
        .word   $000b
        .byte   2, OT6_SLASH    ; brawler: the mountain's one CLASS row,
                                ;   and the only one on the stretch. it
                                ;   is here because brawler ABSORBS
                                ;   poison (monster_prop.dat +$0177 =
                                ;   $08), so the bio-blaster answer the
                                ;   rest of mt. kolts teaches would HEAL
                                ;   it, and its vanilla ice (+$0179 =
                                ;   $02) has no wielder until celes.
                                ;   slash, not pierce, because slash is
                                ;   the scarce key: terra's mithril knife
                                ;   and locke's dirk are both PIERCE
                                ;   (ot6_class.asm:49,:48) and so is
                                ;   edgar's autocrossbow, while edgar's
                                ;   mithril blade (:59) is the party's
                                ;   ONLY slashing weapon -- so the answer
                                ;   to a brawler is edgar closing the
                                ;   tools menu, which is a move nothing
                                ;   else on this mountain asks for.
                                ;   the class channel is also the only one
                                ;   on this mountain that CAN hold a
                                ;   window: Ot6ClassChip takes no vanilla
                                ;   weak x2, so the breaking hit is 2x
                                ;   base, and edgar's blade measures ~42
                                ;   base here -- ~84 against 137 hp fits,
                                ;   where fire (~110 base -> ~440) and the
                                ;   bio blaster (~87 -> ~350) do not.
        .word   $0086
        .byte   2, $00          ; cirpius: SHIELDS ONLY, no class byte --
                                ;   its weakness is the poison row in
                                ;   Ot6ElemAddTbl and this row exists
                                ;   purely to take the count off the
                                ;   formula's 3. that is a legitimate use
                                ;   of this table (the whelk shell's
                                ;   `0, $00` is the same shape) and it is
                                ;   the cheapest way to move the break
                                ;   off the corpse: 3 -> 2 takes cirpius
                                ;   from actions_broken 0 to 1.
        .word   $007a
        .byte   2, $00          ; tusker: shields only, same reason. at
                                ;   270 hp it is the widest window on the
                                ;   mountain (uptime 20.5%) and at the
                                ;   formula's 3 it had none at all.
                                ; note the coupling these three share: an
                                ; Ot6ShieldTbl row also exempts its
                                ; species from Ot6HpScale. inert today
                                ; (every band ships $10 = 1x) but real if
                                ; the hp dial ever reopens, and it is why
                                ; the four OVERWORLD species in this pass
                                ; took Ot6ElemAddTbl rows only -- an
                                ; element add carries no such exemption,
                                ; so where a species needs a weakness but
                                ; not a shield count, the element table is
                                ; the cheaper instrument. these three need
                                ; the count.
        .word   $0103
        .byte   5, OT6_BLUDG    ; vargas: you couldn't break him without
                                ;   the monk
        .word   $014d
        .byte   2, OT6_SLASH    ; ipooh
        .word   $012c
        .byte   5, OT6_SLASH|OT6_PIERCE ; ultros 1: the row he keeps all game
        ; the three-scenario split
        .word   $0104
        .byte   5, OT6_PIERCE   ; tunnelarmor: mug and daggers
        .word   $014a
        .byte   6, OT6_SLASH|OT6_PIERCE ; kefka: the NARSHE DEFENSE record
                                ;   only (MONSTER::KEFKA_NARSHE). the
                                ;   imperial camp gags carry no monster
                                ;   entity at all — see block comment
        .word   $0044
        .byte   4, OT6_BLUDG    ; telstar
        .word   $001a
        .byte   2, OT6_PIERCE   ; doberman
        .word   $0106
        .byte   6, OT6_BLUDG    ; ghosttrain: suplex is CORRECT now
        .word   $0155
        .byte   5, OT6_SLASH|OT6_BLUDG  ; rizopas: the coverage-rule poster child
        .word   $0154
        .byte   1, OT6_SLASH|OT6_BLUDG  ; piranha: the chum wave
        ; ---- the v0.6 BREAK-COVERAGE pass: class rows that close the
        ; fixed-party gaps the audit found across the three scenarios. every
        ; species below was a FORMULA monster (no class weakness) whose
        ; forced party could reach none of its vanilla/added ELEMENTS -- so
        ; it was unbreakable by the exact party the game hands you. the fix
        ; is a weapon class, chosen per that party (class chips ignore
        ; absorb/null, so the water/bolt these bodies absorb never matters).
        ; shields track the early-war trash/miniboss band (2 basic, 3
        ; elite). NOTE the trade: an Ot6ShieldTbl row exempts a species from
        ; Ot6HpScale, which the armor-line ElemAddTbl block deliberately
        ; avoided -- but a class weakness has nowhere else to live, so
        ; per-party breakability takes that trade here (HpScale ships 1x,
        ; inert today). palette: armored soldiers read PIERCE (a blade finds
        ; the gaps) + lightning where a party can conduct it; the Cyan SOLO
        ; duel is SLASH (the samurai out-cuts them); Sabin's brawls add
        ; BLUDG (a monk caves the plate). decode + rationale: bosses-wob.md.
        ;
        ; -- imperial soldier line --
        .word   $0001
        .byte   2, OT6_SLASH|OT6_PIERCE ; soldier: Cyan's duel cuts it
                                ;   (slash), Shadow's throw finds the seam
                                ;   (pierce). camp pursuit b44 + Cyan-solo b43
        .word   $0002
        .byte   3, OT6_PIERCE   ; templar: camp elite (b44); Shadow's throw
                                ;   (pierce) / Bolt Edge (+bolt in ElemAddTbl)
        .word   $014e
        .byte   3, OT6_SLASH    ; leader: Cyan SOLO Doma duel (b46). slash
                                ;   only -- the samurai out-cuts the
                                ;   commander; no other party fights him, so
                                ;   no unreachable '?' clutters the swordfight
        .word   $014f
        .byte   2, OT6_SLASH|OT6_BLUDG ; grunt: Doma courtyard defense (b13),
                                ;   held by Cyan (slash) + Sabin (bludg) --
                                ;   neither reaches pierce/bolt, so the
                                ;   palette bends to who holds the line
        .word   $0176
        .byte   3, OT6_SLASH|OT6_BLUDG ; cadet: same Doma defense (b14), same
                                ;   two heroes, a bigger body
        .word   $0175
        .byte   2, OT6_PIERCE   ; officer: Locke SOLO occupied South Figaro
                                ;   (b9). pierce -- Locke's dagger is his one
                                ;   key, so it is the one weakness shown
        .word   $0065
        .byte   2, OT6_SLASH|OT6_PIERCE ; trooper: Narshe defense waves. the
                                ;   player-assigned 3-way split needs BOTH
                                ;   classes -- slash for a Cyan/Sabin squad,
                                ;   pierce for a Locke/Gau squad. keeps
                                ;   vanilla poison (the Edgar squad's key)
        .word   $003f
        .byte   3, OT6_SLASH|OT6_PIERCE ; rider: also a Narshe wave; same
                                ;   squad coverage. keeps vanilla fire|poison,
                                ;   so Shadow's Fire Skean still breaks it on
                                ;   the Phantom Train
        .word   $009f
        .byte   3, OT6_SLASH|OT6_PIERCE ; heavyarmor: Locke SOLO S.Figaro
                                ;   guards (b11 -> pierce) AND a Narshe wave
                                ;   (formation 88 -> slash for a Cyan/Sabin
                                ;   squad). keeps vanilla bolt|water + poison
        .word   $013a
        .byte   2, OT6_PIERCE   ; merchant: Locke SOLO disguise fight (b10). a
                                ;   civilian with NO vanilla weakness at all,
                                ;   unbreakable by anyone before this row;
                                ;   pierce is Locke's dagger, kept simple
        ; -- Serpent Trench (Sabin + Cyan + Gau). the trio's ring is
        ; BLUDGEON + SLASH, and that is the whole ring -- corrected in the
        ; v0.6 pass (issue #23) after the earlier "three keys, three
        ; creatures" claim turned out to rest on a wielder that does not
        ; exist. decoded, not recalled: Gau cannot equip Hardened ($28 is a
        ; katana whose equip mask reads $8008 = Shadow + Merit Award only, at
        ; item_prop_en.dat[$28*30]+1), his ONLY legal weapon in the entire
        ; game is the Imp Halberd $24 -- which IS pierce (ot6_class.asm:86)
        ; but is stocked by ZERO of the 128 shop records and is a WoB-late
        ; treasure, so it cannot be in the bag on a scenario that runs on
        ; rails -- and bare-handed his Fight reads item $ff = empty hand =
        ; OT6_BLUDG (ot6_class.asm:163). Sabin brings fists and Pummel/
        ; Suplex/Bum Rush (bludg) plus claws (slash), Cyan brings katanas
        ; and all eight SwdTechs (slash). NOBODY here pierces.
        ;
        ; so one key each is arithmetically impossible with two keys, and
        ; the honest shape is 2 bludg + 1 slash -- which is also the party's
        ; own shape (two bludgeon wielders, one slash specialist), so every
        ; member's A button still answers a creature. all three absorb water
        ; and their vanilla element (bolt/fire) is dead or L15-gated for
        ; this party, so class is the only reliable break; the vanilla bits
        ; stay for a later party that carries the element.
        ; the failure worth remembering is the RATIONALE, not the byte: the
        ; byte was authored to a wielder claim that was recalled instead of
        ; decoded. (bosses-wob.md "Serpent Trench"; weapon-classes-six.md
        ; §4.7.)
        .word   $003a
        .byte   2, OT6_SLASH    ; anguiform: a slippery eel, cut by Cyan's
                                ;   blade (vanilla bolt is dead here)
        .word   $005e
        .byte   2, OT6_BLUDG    ; actaneon: a shelled crustacean, cracked by
                                ;   Sabin's fists (vanilla fire needs L15)
        .word   $0059
        .byte   2, OT6_BLUDG    ; aspik: a constrictor, crushed by a monk's
                                ;   fists. was PIERCE, authored to a Gau
                                ;   "fanged strike" that bludgeons -- a dead
                                ;   row for the only party that fights it
                                ;   (vanilla fire needs L15)
        ; zozo / opera / the factory
        ; ---- the v0.4 ZOZO TOWN pass: four poison-trash rows, shields only.
        ; the search-for-terra party is LOCKE+CELES+EDGAR+SABIN -- TERRA IS
        ; GONE, she is the search target -- so there is no native fire at all,
        ; and poison = edgar's bio blaster is the town's break key. every town
        ; thug is ALREADY poison-weak in vanilla (slamdancer $052, harvester
        ; $04e, gabbldegak $0df, hadesgigas $053), so unlike the kolts pass this
        ; is NOT an element add: the weakness is there and reachable, and what
        ; the formula got wrong is the shield COUNT. these are L15-16 trash, so
        ; 2 + level/8 seeds 3 (gabbldegak/slamdancer, L15) or 4 (harvester/hades-
        ; gigas, L16). swept live on zozo_arrival (map 221) with bal_party's
        ; BUFF_SHIELDS, boost3, 6 battles a cell:
        ;
        ;   shields   won   dmg taken   actions_broken   break lands at
        ;   formula   5/6     582         ~0.4             90-95% (corpse)
        ;   3         6/6     554         0.17             89-100% (corpse)
        ;   2         6/6     433         1.83             62-84% (WINDOW)
        ;
        ; the tanks are the tell: at the formula's 4, hadesgigas (1200 hp) and
        ; harvester never broke at all, and the two-tank draw WIPED even the
        ; loop -- MASH wipes 6/6 in this town (the terra-less party has no fire
        ; and no reachable class weakness here, so holding A never chips), the
        ; loop 5/6. at 2 shields they break penultimate, the wipe becomes a
        ; clean win, and the loop takes 48% less damage than mashing does. this
        ; is measurement #8's kolts finding on a bigger body: the formula's
        ; count lands the break on a corpse, 2 is where the loop exists.
        ; ABSORB/NULL re-check (+$17/+$18), the boss-row discipline: hadesgigas
        ; absorbs EARTH and the rest absorb nothing; NONE of the four absorb or
        ; null poison, so the count change never turns the town's answer sour.
        ; shields-only, no class byte (like cirpius/tusker): the answer is the
        ; TOOL, never the A button -- see measurement #9.
        .word   $0052
        .byte   2, $00          ; slamdancer (map 225 sibling of the measured
                                ;   pool, bracketed by $04e 428hp / $0df 350hp)
        .word   $004e
        .byte   2, $00          ; harvester: 428 hp, a 4-shield tank at formula
        .word   $0053
        .byte   2, $00          ; hadesgigas: 1200 hp, the town wall; 4->2 is
                                ;   what lets its break window open at all
        .word   $00df
        .byte   2, $00          ; gabbldegak: comes 4 at a time, and bio's
                                ;   group target chips the whole pack at once
        .word   $0107
        .byte   6, OT6_PIERCE|OT6_BLUDG ; dadaluma: break the crouch
        .word   $006c
        .byte   2, OT6_PIERCE|OT6_BLUDG ; iron fist
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
        ; ---- the v0.6 VECTOR / MAGITEK FACTORY band (issue #11), the first
        ; route band authored off the generated floor. survey, arithmetic and
        ; per-formation reading: docs/design/break-band-vector.md.
        ;
        ; THE PROBLEM this replaces: in the deepest third of the facility
        ; (group 106, maps 271/273) the generated floor answered 100% of
        ; encounters with SLASH -- Gobbler by outright default, Rhinox by a
        ; `rhino` keyword that fired on the wrong body -- and the dungeon
        ; hands the player four swords on the way in. Nothing was unbreakable
        ; (the floor works); the failure was that "hold A" was the whole game.
        ;
        ; THE SHAPE: vanilla already labels six of the ten random-pool bodies
        ; as machines -- exactly Garm/Commando/ProtoArmor/Pipsqueak/Trapper/
        ; Chaser carry a `Program NN` special-attack name, 6 of 384 in the
        ; game -- so "the machines do not care about your sword" is a rule
        ; the player can guess before probing. bludgeon carries the band,
        ; pierce is the second key on the imperial line, slash comes off the
        ; machines, and ¤ sits the beat out (Setzer is flying the getaway, so
        ; a ¤ row would be a composition lock on the one character the
        ; climax excludes).
        ;
        ; measured, equal-map weight over the seven encounter-bearing maps:
        ; slash key-share 67.86% -> 19.64%, pierce 45.54% -> 66.96%,
        ; bludgeon 14.29% -> 80.36%. bodies: slash 59.11% -> 10.86%.
        ; (recomputed from sub_battle_group/rand_battle_group/battle_monsters
        ; at authoring time, not copied from the survey.)
        ;
        ; REACHABILITY, and the one hard demand: 33.04% of draws become
        ; bludgeon-only on the class axis, and every one of them except the
        ; Rhinox pair keeps a reachable vanilla element (ProtoArmor/Trapper
        ; bolt = Ramuh, owned since Zozo; Flan fire and the Mag Roaders'
        ; fire/ice = Ifrit and Shiva, both awarded upstream of the ride).
        ; formation $168 -- Rhinox x2, 8.93% of all draws -- is the one that
        ; blunt instruments alone answer, because Rhinox has no vanilla
        ; weakness AND ABSORBS BOLT ($075 +$17 = $04), the element the rest
        ; of the facility teaches. that is deliberate: Sabin's fists and
        ; Blitz cost nothing to bring, Gau's fists likewise, and Locke's
        ; Full Moon / Celes' Flail are on sale in four towns before the walk.
        ;
        ; SHIELD COUNTS: all twelve at 2 against a formula value of 4 (L18/19
        ; both give 2 + level/8 = 4). UNMEASURED and said plainly -- this is
        ; precedent-following, not a sweep: Mt. Kolts (balance-metrics.md
        ; :944-972) and Zozo (:1489-1510 above, where a 1200-hp HadesGigas
        ; went 4 -> 2) both found independently that the formula's count
        ; lands the break on a corpse. Landing this wants a Vector doorstep
        ; fixture and a bal_party BAL_BUFF_SHIELDS sweep over 1/2/3, with a
        ; separate three-character arm (less damage per round means the same
        ; count breaks later). break-band-vector.md §8.2/§10.3.
        .word   $00cb
        .byte   2, OT6_PIERCE|OT6_BLUDG ; garm: a magitek quadruped
                                ;   (Program 95), not a hound -- pierce the
                                ;   joints or cave the housing. commonest
                                ;   body at the entrance, where the band
                                ;   teaches its rule, so it teaches both
                                ;   halves. keeps vanilla bolt|water
        .word   $00c7
        .byte   2, OT6_PIERCE   ; commando: imperial rank keeps the imperial
                                ;   answer -- templar $0002 and officer
                                ;   $0175 are both pierce above. consistency,
                                ;   not novelty
        .word   $0165
        .byte   2, OT6_BLUDG    ; protoarmor: a sealed suit has no seam to
                                ;   put a point in; you dent it. retires
                                ;   pierce so the armored MACHINE and the
                                ;   armored MAN stop having one answer.
                                ;   vanilla bolt stays the ranged key
        .word   $0041
        .byte   2, OT6_PIERCE   ; pipsqueak: the swarm body, up to x5 and
                                ;   22% of all bodies in the band. pierce so
                                ;   Edgar's AutoCrossbow -- whole enemy side,
                                ;   chipping per hit -- is the designed
                                ;   answer to a five-stack
        .word   $0047
        .byte   2, OT6_BLUDG    ; flan: you cannot cut an ooze (keeps the
                                ;   generator's own read). its element is
                                ;   fire, which the Flame Sabre two maps
                                ;   upstream and Ifrit's magicite both
                                ;   supply -- and this pool is the floor
                                ;   Ifrit & Shiva are fought on
        .word   $0066
        .byte   2, OT6_PIERCE|OT6_BLUDG ; general: an officer in plate.
                                ;   vanilla poison answers him IF Edgar was
                                ;   picked (Bio Blaster is his Tool); the
                                ;   class row is what makes him breakable
                                ;   when he wasn't
        .word   $002d
        .byte   2, OT6_BLUDG    ; trapper: a fixed trap mechanism (Program
                                ;   18) -- you smash a device, you do not
                                ;   stab it. comes x3, vanilla bolt|water
                                ;   backs it up
        .word   $00a0
        .byte   2, OT6_PIERCE|OT6_BLUDG ; chaser: 1202 hp, the widest break
                                ;   window in the band, on the ESCAPE map
                                ;   where no shop trip is possible mid-
                                ;   sequence. two keys so whatever three
                                ;   walked out of the tube room hold one
        .word   $0088
        .byte   2, OT6_SLASH|OT6_PIERCE ; gobbler: no vanilla weakness at
                                ;   all, so this row is its ONLY key. the
                                ;   one soft body in a dungeon of machines
                                ;   -- cut it or stick it. deliberately the
                                ;   band's slash target, placed in the
                                ;   deepest pool so the blade has work in
                                ;   the room where the machines stopped
                                ;   caring about it
        .word   $0075
        .byte   2, OT6_BLUDG    ; rhinox: THE FLAGSHIP. no weakness of any
                                ;   kind AND it absorbs bolt, so the answer
                                ;   the rest of the facility teaches would
                                ;   HEAL it. armoured bulk with no seam ->
                                ;   bludgeon, and bludgeon alone: the one
                                ;   body in the band that asks the player to
                                ;   have brought a blunt instrument, and the
                                ;   reason to bring Sabin
        .word   $0006
        .byte   2, OT6_BLUDG    ; mag roader (minecart, 5 forced fights): a
                                ;   thing on wheels -- you smash the wheel.
                                ;   its vanilla FIRE stays the reward for
                                ;   reading the fight (Ifrit, or the Flame
                                ;   Sabre) and its ICE ABSORB stays a trap
        .word   $00af
        .byte   2, OT6_BLUDG    ; mag roader (the other one): same creature,
                                ;   same class -- the ELEMENT is what
                                ;   distinguishes the pair ($006 weak fire /
                                ;   absorbs ice, $0af weak ice), and
                                ;   formation $075 puts them in one fight so
                                ;   the wrong splash heals half the screen.
                                ;   flattening that onto the class axis
                                ;   would waste the best puzzle in the band.
                                ;   NB both are named "Mag Roader", so the
                                ;   name-keyed floor generator could not
                                ;   have told them apart even if it wanted
                                ;   to -- 15 names cover 42 species
        ; sealed gate / thamasa / the floating continent
        .word   $012e
        .byte   7, OT6_SLASH|OT6_PIERCE ; ultros 3: the row, third verse
        .word   $0116
        .byte   7, OT6_PIERCE   ; flameeater
        .word   $00de
        .byte   1, $00          ; balloon: vanilla ice/water pops them
        .word   $0168
        .byte   7, OT6_SLASH|OT6_PIERCE ; ultros 4: one last time
        .word   $012f
        .byte   4, OT6_BLUDG    ; chupon: no bludgeon, no bragging rights
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
                                ;   (hud shield glyphs cap at 6 — display
                                ;   saturates, the count is true)
        .word   $0118
        .byte   5, OT6_SLASH|OT6_PIERCE ; nerapa: sprint fight, low gauge
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
; GENERATED by tools/gen_break_floor.py -- do not edit the .inc by hand.
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
