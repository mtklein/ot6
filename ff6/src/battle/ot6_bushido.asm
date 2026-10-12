; ------------------------------------------------------------------------------
; Cyan: the Bushido ladder, battle side
;
; boost -> tech, the ceiling it is measured against, the spent-divine top-tier
; swap, and Ot6BushidoTier, the one entry the battle calls. Reads the packed
; loadout word documented below; the field side that writes that word is
; ot6_loadout.asm, and the submenu that displays the ladder is ot6_cmdmenu.asm.
; ------------------------------------------------------------------------------

; ==============================================================================
; Bushido loadout: per-save, field-configurable slots
;
; Storage: a 16-bit little-endian word in two unused bytes inside the working-
; save block ($1600-$1fff) that save.asm's CopyGameDataToSRAM/LoadSaveSlot
; round-trip per slot and CalcSaveSlotChecksum ($1600-$1ffd) covers.
;
;   $1e1d..$1e1e   packed word.  Cyan has exactly 8 SwdTechs (index 0..7 = 3
;                  bits), so the four boost slots fit in 12 bits:
;                    slot0 (unused)                  slot2 (boost 2x) = bits 6-8
;                    slot1 (boost 1x) = bits 3-5     slot3 (boost 3x) = bits 9-11
;                  (top 4 bits unused, kept 0).  Each field is the same 0..7
;                  index Ot6BushidoTech returns.
;
; Every Bushido tech costs at least 1 BP: rows map i -> boost i+1 -> word slot
; i+1, and slot 0 is never read.
;
; AUTO re-derived for three tiers: the window is the top three learned techs,
; base = max(0, ceiling-2), tech = min(base + boost-1, ceiling).
;
; word == 0 -> AUTO (the moving window); this is also the sentinel, since an
; all-zero word decodes to "all four slots = tech 0", a config no player sets
; on purpose.  word != 0 -> MANUAL: unpack the 3-bit field per slot.
; Revert-to-auto writes $0000.
;
; One physical cell $7e1e1d (DBR = $7e in battle); read long (f:) so the hook
; is bank-agnostic.  With the word = 0 the battle path is unchanged.
; ==============================================================================

OT6_CLEAVE_TECH = 7             ; Cleave, Cyan's divine: SwdTech tech 8

; [ Bushido ceiling: the highest non-divine tech known, read safe ]
; InitSkills stores $2020 with a 16-bit `stx` over CountBits's uninitialized
; high byte ($ff02 in the Doma solo fight, $ffff before Cyan joins); read as a
; word, the junk high byte made even a real 2-tech ceiling `>= 8` and collapse
; to 0, pinning Cyan to Dispatch. Read a8 the junk is ignored, and an
; unlearned $ff (low byte) still trips >= 8 into the nothing-learned path.
;
; $2020 is vanilla's count of every tech known, minus 1.  Cleave (tech 7) is
; learned by story at the Phantom Train farewell (#379), long before the
; techs between, so the count includes a tech that is not at the top of a
; contiguous run: Dispatch..Quadra Slam plus Cleave counts 5, and a ceiling
; of 4 would name Empowerer, which he does not know.  So Cleave is taken out
; of the count here, and the ceiling is that of techs 0..6, which the level
; table teaches in order; Cleave stands apart, on the 3-BP row only
; (Ot6BushidoPick).  Capped at 6 for the same reason: tech 7 is never a
; window tech by index.
; a8.  out: A = ceiling (0..6).  preserves X and Y.
.proc Ot6BushidoCeil
        .a8
        lda     $2020           ; techs known - 1, low byte only
        cmp     #$08
        bcs     @none           ; nothing learned: only tech 0 (Dispatch) exists
        pha
        lda     f:$7e1cf7
        bpl     :+              ; Cleave not known: the count is the run's
        lda     $01,s
        beq     :+              ; (Cleave alone: the run is Dispatch's 0)
        dec     a               ; Cleave out of the count
        sta     $01,s
:       pla
        cmp     #OT6_CLEAVE_TECH
        bcc     @out
        lda     #OT6_CLEAVE_TECH - 1
@out:   rtl
@none:  lda     #$00
        rtl
.endproc

; [ the window's pick: boost -> tech, given the ceiling and Cleave ]
; One leaf for the battle (Ot6BushidoTech's AUTO arm) and the field
; configurator (Ot6LoadoutAutoTech), so the two cannot pick differently.
;   Cleave not known: the moving window of three, Cyan's top three techs,
;     weakest -> strongest: base = max(0, ceiling-2), tech = min(base +
;     boost-1, ceiling).
;   Cleave known (#379): the 3-BP row is Cleave, the divine's one gate
;     (kits.md "Divines"), and the 1- and 2-BP rows are his top two of the
;     rest: base = max(0, ceiling-1), tech = min(base + boost-1, ceiling).
;     At full kit that is Stunner / Quadra Slice / Cleave, the window it
;     always was.
; boost 0 is clamped to 1 (the menu never offers it).
; a8/i16.  in: A = boost (0..3), X = ceiling (0..6) | $80 if Cleave is
; known.  out: A = tech (0..7).  clobbers X.  preserves Y.
.proc Ot6BushidoPick
        .a8
        .i16
        cmp     #$01            ; the floor is 1 BP, clamp a stray 0 up
        bcs     :+
        lda     #$01
:       pha                     ; park boost ($01,s)
        txa
        pha                     ; park ceiling|cleave ($01,s; boost $02,s)
        bpl     @three          ; Cleave not known: three wide
        lda     $02,s
        cmp     #$03
        bcc     @two            ; the 1- and 2-BP rows
        lda     #OT6_CLEAVE_TECH ; the 3-BP row: Cleave
        bra     @done
@two:   lda     $01,s
        and     #$7f
        sta     $01,s           ; the ceiling alone
        dec     a               ; ceiling - 1: the rest's window is two wide
        bpl     @base
        lda     #$00
        bra     @base
@three: sec
        sbc     #$02            ; ceiling - 2: three wide
        bcs     @base
        lda     #$00            ; base floors at 0
@base:  clc
        adc     $02,s           ; base + boost
        dec     a               ;   ... - 1 (boost >= 1 after the clamp)
        cmp     $01,s           ; vs the ceiling
        bcc     @done
        lda     $01,s           ; cap at the ceiling
@done:  sta     $02,s
        pla                     ; drop the parked ceiling
        pla                     ; A = tech
        rtl
.endproc

; [ Bushido moving window of three: boost -> tech ]
; boost 1/2/3 selects Cyan's top three learned techs, weakest -> strongest:
; base = max(0, ceiling-2), tech = min(base + boost-1, ceiling). while he knows
; three or fewer, base is 0 and every learned tech is reachable; learn a fourth
; and the window slides up one, dropping the weakest. arithmetic only, no
; table.  boost 0 does not name a tech; it is clamped to 1 rather than
; allowed to underflow the window, so any caller that reaches here with a
; cleared pending byte gets the cheapest tier instead of garbage.
; a8/i16.  in: A = boost (0..3).  out: A = tech (0..ceiling).  clobbers X.
.proc Ot6BushidoTech
        .a8
        .i16
        cmp     #$01            ; the floor is 1 BP, clamp a stray 0 up
        bcs     :+              ;   (the menu never offers boost 0)
        lda     #$01
:       pha                     ; park boost ($01,s). the two scratch bytes in
                                ;   reach ($36 btlgfx's, OT6_SCR_BIT the hud
                                ;   builder's) both have owners; the stack has
                                ;   no owner and survives an nmi.
        ; [ manual-loadout read hook, packed 2-byte word ]
        ; word 0 (all existing saves) -> @auto, the vanilla window untouched.
        ; word nonzero -> return the player's stored tech for this boost slot
        ; (slot s = the 3-bit field at bit s*3), but only if it is still learned
        ; ($1cf7 bit set); otherwise fall back to the auto window for this slot
        ; rather than offer an uncastable tech.  Unpack and learned-test are the
        ; same leaves the menu draw uses (Ot6LoadoutUnpack / Ot6TechLearned),
        ; so battle and menu cannot decode the word differently.  Cleave
        ; (tech 7) stands only in the 3-BP slot (Ot6CleaveSlot): a divine's
        ; one gate is a full boost.
        longa
        lda     f:OT6_LOADOUT   ; packed loadout word (0 = AUTO)
        shorta                  ; plain SEP #$20, keeps Z (shorta0's tdc wipes it)
        beq     @auto
        lda     $01,s           ; boost (0..3) = slot
        jsl     Ot6LoadoutUnpack    ; A = stored tech for this slot (clobbers X)
        jsl     Ot6TechLearned      ; carry = learned (A and Y preserved)
        bcc     @auto           ; stored tech not learned -> auto fallback
        pha
        lda     $02,s           ; the boost = the slot
        longa
        and     #$00ff
        tax
        shorta
        pla
        jsl     Ot6CleaveSlot   ; Cleave stands only in the 3-BP slot
        bcc     @auto
        sta     $01,s           ; learned: overwrite the parked boost with tech
        pla                     ; A = tech (mirrors @auto's balanced tail)
        rtl
@auto:
        jsl     Ot6BushidoCeil  ; A = ceiling (0..6)
        pha                     ; park it ($01,s; the boost is $02,s)
        lda     f:$7e1cf7
        and     #$80            ; Cleave known?
        ora     $01,s
        sta     $01,s
        pla                     ; A = ceiling | $80 if Cleave
        longa
        and     #$00ff
        tax
        shorta
        pla                     ; A = boost (parked at entry)
        jml     Ot6BushidoPick  ; its rtl returns for us
.endproc

.proc Ot6BushidoTier
        .a8
        .i16
        lda     $62ca           ; active character slot
        longa
        and     #$0003
        asl
        tax                     ; -> entity offset
        shorta0
        lda     OT6_BOOST_REVEALED,x         ; pending boost 0-3
        cmp     #$04
        bcc     :+
        lda     #$03            ; (defensive: Ot6Boost already caps at 3)
:       jsl     Ot6BushidoTech      ; boost -> tech (shared window math)
        pha
        asl5                    ; level * 32, the counter value vanilla's
        sta     $7b82           ;   bar drew, so w7e7b82 still feeds the
        pla                     ;   flag, the fill, and battle_mpcost's level()
        rtl
.endproc
