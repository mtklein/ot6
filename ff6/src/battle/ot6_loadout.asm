; ------------------------------------------------------------------------------
; Bushido loadout configurator: the field-menu side, plus the row-price shims
;
; The bank-$F0 state logic behind the field configurator (field_menu.asm holds
; only the tilemap/DMA/cursor shell and jsl's in here for every decision), and
; the two OT6_MP_COSTS-gated row-price leaves the menus draw with. The battle
; side that reads the word this file writes is ot6_bushido.asm.
; ------------------------------------------------------------------------------
; Split out of ot6_kits.asm (v0.9, 3037 lines) with the emission order of
; every instruction preserved: ot6.asm includes these files in exactly the
; order their text sat in the old one, so the assembler receives the identical
; token stream and the linker the identical segment. ROM CRC32 0x2E9B5A7F and
; ff6-en.map are byte-identical across the split.
; ------------------------------------------------------------------------------

; ==============================================================================
; Bushido loadout configurator: OT6-owned bank-F0 logic (issue #8 Layer B)
;
; The field-menu configurator's state logic lives here in F0; the C3 menu-state
; handler (field_menu.asm) is a thin shim that jsl's these for every decision
; and only performs the tilemap/DMA/cursor framework calls that must run in the
; menu bank.  All entries are a8/i16, D = 0 (the menu's direct page, so $08/$09
; new-press joypad and $4d/$4e cursor position are reachable), rtl.  These read
; the learned set from $1cf7 (not $2020, which is battle-only) and price with
; the shared Ot6CostFor leaf, as the spec requires.
; ------------------------------------------------------------------------------

; [ menu-side ceiling: popcount($1cf7) - 1, floored at 0 (0..7) ]
; The field cannot read $2020 (object-map data there), so derive the ceiling
; from the learned bitmap the same way InitSkills does at battle start.
; out: A = ceiling.  clobbers X.  preserves Y.
.proc Ot6LoadoutCeil
        .a8
        .i16
        ldx     #$0000              ; running popcount in X low
        lda     f:$7e1cf7
@lp:    beq     @done               ; no more set bits
        pha
        and     #$01
        beq     @skip
        inx
@skip:  pla
        lsr
        bra     @lp
@done:  txa                         ; A = popcount (0..8)
        beq     @zero               ; nothing learned -> ceiling 0 (only tech 0)
        dec     a                   ; ceiling = count - 1
        rtl
@zero:  lda     #$00
        rtl
.endproc

; [ auto-window tech for a slot: base = max(0,ceil-2), tech = min(base+slot-1,ceil) ]
; The same math Ot6BushidoTech runs in AUTO mode, replicated menu-side off
; $1cf7 so the seed baseline matches what battle would pick.  #38: the slot
; index is the boost (1..3) and slot 0 is retired, so a 0 clamps to 1 the same
; way the battle leaf does; Ot6LoadoutSeedWord still walks 0..3 and relies on
; that clamp to mirror slot 1 into the unused slot 0 (see there).
; in: A = slot (0..3).  out: A = tech (0..ceiling).  clobbers X.  preserves Y.
.proc Ot6LoadoutAutoTech
        .a8
        .i16
        cmp     #$01                ; #38: 1-BP floor, clamp the retired slot 0
        bcs     :+
        lda     #$01
:       pha                         ; park slot ($01,s)
        jsl     Ot6LoadoutCeil      ; A = ceiling
        pha                         ; park ceiling ($01,s ; slot now $02,s)
        sec
        sbc     #$02                ; ceiling - 2  (#38: three tiers, not four)
        bcs     :+
        lda     #$00                ; base floors at 0
:       clc
        adc     $02,s               ; base + slot
        dec     a                   ;   ... - 1 (slot >= 1 after the clamp)
        cmp     $01,s               ; vs ceiling
        bcc     :+
        lda     $01,s               ; cap at ceiling
:       sta     $02,s               ; stash tech over the parked slot
        pla                         ; drop ceiling
        pla                         ; A = tech
        rtl
.endproc

; [ is a tech learned? test bit t of $1cf7 ]
; in: A = tech (0..7).  out: carry = learned.  A preserved.  clobbers X,Y-safe.
.proc Ot6TechLearned
        .a8
        .i16
        phy
        pha                         ; save A (the tech)
        longa
        and     #$00ff
        tay                         ; Y = t (clean shift count)
        shorta0
        lda     f:$7e1cf7
        iny                         ; shift t+1 times -> carry = bit t
:       lsr
        dey
        bne     :-
        pla                         ; restore A (PLA preserves carry)
        ply                         ; restore Y (PLY preserves carry)
        rtl
.endproc

; [ unpack a slot's 3-bit tech field from the packed loadout word ]
; slot s occupies bits s*3 .. s*3+2 of the $7e1e1d word.  Both the battle read
; hook (Ot6BushidoTech) and the menu draw route through here, so they cannot
; decode the word differently.  Uses only registers + its own stack cell, no
; direct-page scratch, so it is safe to call mid-draw (the C3 loop parks its
; slot index in $e2).
; in: A = slot (0..3).  out: A = stored tech (0..7).  clobbers X.  preserves Y.
.proc Ot6LoadoutUnpack
        .a8
        .i16
        pha                         ; park slot ($01,s)
        asl                         ; slot*2
        clc
        adc     $01,s               ; slot*3 -> shift count (0,3,6,9)
        longa
        and     #$00ff
        tax                         ; X = shift count
        lda     f:OT6_LOADOUT       ; packed word
@sh:    cpx     #$0000
        beq     @msk
        lsr
        dex
        bra     @sh
@msk:   and     #$0007              ; A = this slot's 3-bit field
        shorta                      ; plain SEP #$20, keeps A (shorta0's tdc wipes it)
        sta     $01,s               ; overwrite the parked slot with the tech
        pla                         ; A = tech (0..7)
        rtl
.endproc

; [ #49: is the SwdTech loadout AUTO?  the packed word is zero ]
; The twin of Ot6RageIsAuto below, and it decodes AUTO the same way every
; other reader of this word already does: Ot6LoadoutSlotTech branches @auto on
; a zero word (:1081-1083) and Ot6LoadoutCycleCore seeds on one (:1190-1193).
; It exists so the page can state the mode without re-deriving it: a second
; `lda OT6_LOADOUT / beq` in the C3 shim would be a second definition of AUTO,
; and the two could drift when the stored format changes.
; out: carry set = AUTO.  clobbers A.  preserves X and Y.
.proc Ot6LoadoutIsAuto
        .a8
        .i16
        longa
        lda     f:OT6_LOADOUT       ; packed word (0 = AUTO)
        shorta                      ; plain SEP #$20, keeps Z (shorta0 wipes it)
        beq     @auto
        clc
        rtl
@auto:  sec
        rtl
.endproc

; [ the tech shown/used for a slot, validated: the single source of truth ]
; Mirrors the battle read hook: MANUAL returns the stored, learned tech, else
; falls back to the auto window for that slot.  Used by the C3 draw so the
; screen never names a tech the battle would not fire.
; in: A = slot (0..3).  out: A = tech (0..7).  clobbers X.  preserves Y.
.proc Ot6LoadoutSlotTech
        .a8
        .i16
        pha                         ; park slot ($01,s)
        longa
        lda     f:OT6_LOADOUT       ; packed word (0 = AUTO)
        shorta                      ; plain SEP #$20, keeps Z (shorta0's tdc wipes it)
        beq     @auto
        lda     $01,s               ; slot
        jsl     Ot6LoadoutUnpack    ; A = stored tech (clobbers X, preserves Y)
        jsl     Ot6TechLearned      ; carry = learned (A preserved)
        bcc     @auto
        sta     $01,s               ; learned: return stored tech
        pla
        rtl
@auto:  pla                         ; A = slot
        jsl     Ot6LoadoutAutoTech  ; A = auto tech for this slot
        rtl
.endproc

; [ pack a new tech into one slot's 3-bit field of the loadout word ]
; Read-modify-write: clears slot s's field (bits s*3..s*3+2) and ORs in the new
; tech, leaving the other three slots untouched.  A nonzero result means
; MANUAL by definition.  Uses menu scratch $e0..$e4 (D=0), free during input.
; in: A = new tech (0..7), X = slot (0..3).  clobbers A,X,Y.
.proc Ot6LoadoutAssign
        .a8
        .i16
        and     #$07
        sta     $e0                 ; new tech
        txa                         ; slot
        asl                         ; slot*2
        sta     $e1                 ; temp
        txa                         ; slot
        clc
        adc     $e1                 ; slot*3 -> shift count
        longa
        and     #$00ff
        tay                         ; Y = shift count
        lda     #$0007
        sta     $e1                 ; mask, pre-shift ($e1/$e2 word)
        lda     $e0
        and     #$0007              ; field = new tech, pre-shift
@sh:    cpy     #$0000
        beq     @done
        asl     a                   ; field <<= 1
        asl     $e1                 ; mask  <<= 1  (16-bit dp shift, m=0)
        dey
        bra     @sh
@done:  sta     $e3                 ; field, shifted ($e3/$e4 word)
        lda     $e1                 ; mask, shifted
        eor     #$ffff              ; ~mask
        and     f:OT6_LOADOUT       ; clear this slot's field
        ora     $e3                 ; OR in the new field
        sta     f:OT6_LOADOUT       ; write the word back
        shorta0
        rtl
.endproc

; [ pack the whole auto window into the word (the first edit out of AUTO) ]
; So that after the first manual edit the un-touched slots keep the auto
; techs they were displaying, not zero.  Result is nonzero = MANUAL (unless the
; auto window is all tech 0, a ceiling-0 case that reads auto either way).
; #38: the loop still walks slots 0..3 even though slot 0 is retired.  That is
; deliberate, because the stored format must not move (persistent_layout
; ot6-codex-o8-v1), and Ot6LoadoutAutoTech's clamp makes slot 0 a harmless
; mirror of slot 1, which keeps the word nonzero (= MANUAL) in the same
; cases it did before.  Nothing ever reads slot 0 back.
; clobbers A,X,Y.
.proc Ot6LoadoutSeedWord
        .a8
        .i16
        ldx     #$0000
@lp:    phx
        txa                         ; slot
        jsl     Ot6LoadoutAutoTech  ; A = auto tech (clobbers X, preserves Y)
        plx                         ; X = slot
        phx
        jsl     Ot6LoadoutAssign    ; pack A into slot X (clobbers A,X,Y)
        plx                         ; X = slot
        inx
        cpx     #$0004
        bcc     @lp
        rtl
.endproc

; [ open the configurator: reset the cursor to the top slot ]
; Leaves the loadout word as-is: AUTO (word 0) stays AUTO until the first edit,
; MANUAL stays MANUAL.  The display needs no seeding: Ot6LoadoutSlotTech
; computes the auto tech per slot on the fly whenever the word is 0, so the
; player still edits the auto baseline without anything being written.
; clobbers A.
.proc Ot6LoadoutOpen
        .a8
        .i16
        stz     $4d                 ; cursor: single column
        stz     $4e                 ; ... top slot
        stz     $4f
        stz     $50
        stz     $51
        stz     $52
        rtl
.endproc

; [ cycle the cursored slot's tech to the prev/next learned tech; go MANUAL ]
; The first edit out of AUTO packs the current auto window into the word first
; (Ot6LoadoutSeedWord), so the three un-touched slots keep their auto techs;
; then the cursored slot is cycled and repacked, leaving a nonzero MANUAL word.
; in: A = step delta ($01 = next, $07 = prev, i.e. +/-1 mod 8).  clobbers A,X,Y.
.proc Ot6LoadoutCycleCore
        .a8
        .i16
        pha                         ; park delta ($01,s)
        longa
        lda     f:OT6_LOADOUT       ; still AUTO?
        shorta                      ; plain SEP #$20, keeps Z (shorta0's tdc wipes it)
        bne     :+
        jsl     Ot6LoadoutSeedWord  ; first edit: store the auto window in the word
:       lda     $4e                 ; cursored row (0..2)
        inc     a                   ; #38: row i -> word slot i+1 (slot 0 retired)
        jsl     Ot6LoadoutUnpack    ; A = the slot's current stored tech
        ldy     #$0008              ; try every residue once
@hop:   clc
        adc     $01,s               ; delta
        and     #$07                ; wrap 0..7
        jsl     Ot6TechLearned      ; carry = learned (A preserved)
        bcs     @found
        dey
        bne     @hop
@found: ldx     $4e                 ; X = cursored row ($4f = 0, set by Open)
        inx                         ; -> the same row->slot mapping
        jsl     Ot6LoadoutAssign    ; pack the new tech (A) into slot X
        pla                         ; drop delta
        rtl
.endproc

Ot6LoadoutNext:                     ; R shoulder -> next learned tech
        lda     #$01
        jmp     Ot6LoadoutCycleCore
Ot6LoadoutPrev:                     ; L shoulder -> previous learned tech
        lda     #$07
        jmp     Ot6LoadoutCycleCore

; [ per-frame input: mutate loadout state; tell C3 what to do next ]
; Reads the new-press joypad ($08 low = A/X/L/R, $09 high = B/Y/Sel/Start/dpad).
;   B      -> exit               (return A = 2)
;   Up/Dn  -> move slot cursor   (return A = 1: redraw)
;   L/R    -> cycle slot's tech  (return A = 1)
;   Select -> revert to AUTO     (return A = 1)
;   else                          (return A = 0: idle)
.proc Ot6LoadoutInput
        .a8
        .i16
        lda     $09                 ; dpad / B / Y / Select / Start
        bit     #$80                ; B -> exit
        beq     :+
        lda     #$02
        rtl
:       bit     #$08                ; Up
        beq     @dn
        lda     $4e
        bne     :+
        lda     #$03                ; wrap 0 -> 2 (pre-decrement).  #38: 3 rows
:       dec     a
        sta     $4e
        lda     #$01
        rtl
@dn:    lda     $09
        bit     #$04                ; Down
        beq     @sel
        lda     $4e
        inc     a
        cmp     #$03                ; #38: three rows (1x/2x/3x), no 0x
        bcc     :+
        lda     #$00                ; wrap 2 -> 0
:       sta     $4e
        lda     #$01
        rtl
@sel:   lda     $09
        bit     #$40                ; Y -> revert to AUTO.  (not Select: FF6's
                                    ;   default config aliases physical Select
                                    ;   onto the R bit, so it cannot be told
                                    ;   apart from the R-shoulder cycle.)
        beq     @lr
        longa
        lda     #$0000
        sta     f:OT6_LOADOUT       ; word = 0 = AUTO (the display recomputes it)
        shorta0
        lda     #$01
        rtl
@lr:    lda     $08                 ; A / X / L / R shoulders
        bit     #$20                ; L shoulder -> previous learned tech
        beq     @rsh
        jsl     Ot6LoadoutPrev
        lda     #$01
        rtl
@rsh:   lda     $08
        bit     #$10                ; R shoulder -> next learned tech
        beq     @idle
        jsl     Ot6LoadoutNext
        lda     #$01
        rtl
@idle:  lda     #$00
        rtl
.endproc

; [ price a loadout row: always defined, flag-gated body ]
; The configurator lives in the shared menu object (built once, flag-agnostic),
; but Ot6CostFor is OT6_MP_COSTS-only.  So the menu prices every row through
; this always-present shim, the same as the
; Ot6BlitzRowDecorate/Ot6ToolRowDecorate pattern.  On: tail-call Ot6CostFor
; (its rtl returns to the menu).  nomp: return 0 (no cost table referenced, so
; the shared menu object links against either battle object, and the row draws
; no number).
; in: A = attack id.  out: A = MP cost (0 under nomp).  rtl.
.proc Ot6LoadoutCost
        .a8
        .i16
.if ::OT6_MP_COSTS                  ; :: is the file-scope flag, from in-proc
        jmp     Ot6CostFor          ; tail-call: same bank, its rtl returns for us
.else
        lda     #$00
        rtl
.endif
.endproc

; [ #55: price a thief submenu row: always defined, flag-gated body ]
; Ot6LoadoutCost's twin, for the second keyed table.  Ot6ThiefListOpen is
; assembled in both builds (the C1 stub jsl's it either way), but the cost
; leaves are OT6_MP_COSTS-only, so the list prices its rows through this shim:
; on, resolve the row; nomp, return 0 so cmd $02 draws two blanks and the row
; keeps the byte-identical unpriced layout.
;
; The branch here is the same branch Ot6AbilityCost's @steal arm makes.  The
; Steal row is not in Ot6ThiefCostTbl, because Ot6StealCost is its
; one authority (#52), so a shim that only scanned the thief table would draw
; Steal at 0 while the charge took 4.  Splitting on Ot6ThiefIsNew in both places
; means the drawn price and the charged price come out of the same leaf for every
; row, which is why #52 left Steal's price as a callable leaf
; instead of an inline immediate.
; in: A = row id.  out: A = MP cost (0 under nomp).  preserves X and Y.  rtl.
.proc Ot6ThiefCost
        .a8
        .i16
.if ::OT6_MP_COSTS                  ; :: is the file-scope flag, from in-proc
        jsl     Ot6ThiefIsNew       ; carry set = filch/bestow (A preserved)
        bcc     @steal
        jmp     Ot6ThiefCostFor     ; tail-call: same bank, its rtl returns for us
@steal: jmp     Ot6StealCost        ; the Steal row: #52's one authority for the 4
.else
        lda     #$00
        rtl
.endif
.endproc
