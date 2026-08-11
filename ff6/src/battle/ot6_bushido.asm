; ------------------------------------------------------------------------------
; Cyan: the Bushido ladder, battle side
;
; boost -> tech, the ceiling it is measured against, the spent-divine top-tier
; swap, and Ot6BushidoTier, the one entry the battle calls. Reads the packed
; loadout word documented below; the field side that writes that word is
; ot6_loadout.asm, and the submenu that displays the ladder is ot6_cmdmenu.asm.
; ------------------------------------------------------------------------------
; Split out of ot6_kits.asm (v0.9, 3037 lines) with the emission order of
; every instruction preserved: ot6.asm includes these files in exactly the
; order their text sat in the old one, so the assembler receives the identical
; token stream and the linker the identical segment. ROM CRC32 0x2E9B5A7F and
; ff6-en.map are byte-identical across the split.
; ------------------------------------------------------------------------------

; ==============================================================================
; Bushido loadout (issue #8 Layer B): per-save, field-configurable slots
;
; Storage: a 16-bit little-endian word in two unused bytes inside the working-
; save block ($1600-$1fff) that save.asm's CopyGameDataToSRAM/LoadSaveSlot
; round-trip per slot and CalcSaveSlotChecksum ($1600-$1ffd) covers, so the
; loadout persists and validates with no checksum work and no migration
; (every existing save reads $1e1d..$1e1e = $0000 = AUTO):
;
;   $1e1d..$1e1e   packed word.  Cyan has exactly 8 SwdTechs (index 0..7 = 3
;                  bits), so the four boost slots fit in 12 bits:
;                    slot0 (retired, #38)           slot2 (boost 2x) = bits 6-8
;                    slot1 (boost 1x) = bits 3-5    slot3 (boost 3x) = bits 9-11
;                  (top 4 bits unused, kept 0).  Each field is the same 0..7
;                  index Ot6BushidoTech returns, so the downstream +$55 /
;                  Ot6BushidoOblivion tail stays byte-for-byte unchanged.
;
; [ issue #38: every Bushido tech costs at least 1 BP ]
; Owner ruling from the rc1 playtest: "the 0 boost ability feels a bit too much
; like better attack."  Cyan's sword-art spends banked time, so a 0-pip tech
; competed with Fight instead of with the bank.  The floor is now 1 BP: the
; submenu and the field configurator both show three rows (1x, 2x, 3x), and
; his no-pip turn is Fight.
;
; The stored format did not move.  The word is still two bytes at $1e1d with
; four 3-bit fields, because every tracked checkpoint in the batch was generated against
; persistent_layout ot6-codex-o8-v1 and a schema change invalidates all of
; them.  What changed is that slot 0 is never read: rows map i -> boost i+1 ->
; word slot i+1, and slot 0 is left as whatever Ot6LoadoutSeedWord's mirror
; wrote (see there).  Old saves keep decoding: a MANUAL word's slots 1..3 mean
; what they meant before, and word 0 is still AUTO.
;
; AUTO re-derived for three tiers: the window is the top three learned techs,
; base = max(0, ceiling-2), tech = min(base + boost-1, ceiling).  At the full
; kit (ceiling 7) that is {5,6,7} at 1x/2x/3x, the same three techs the old
; four-tier window put at boosts 1/2/3, so the tuned top of the ladder (and
; Oblivion on 3x) is unchanged; only the free tier is gone.
;
; word == 0  -> AUTO (the moving window).  This is also the sentinel: an all-zero
;   word decodes to "all four slots = tech 0", a config no player sets on
;   purpose, and every existing save already has 0 there, so AUTO needs no
;   migration (the same property the old mode-flag-0 had).  word != 0 -> MANUAL:
;   unpack the 3-bit field per slot.  Revert-to-auto writes $0000.
;
; One physical cell $7e1e1d (DBR = $7e in battle); read long (f:) so the hook
; is bank-agnostic.  With the word = 0 the battle path is identical to Layer A.
; ==============================================================================

; [ Bushido ceiling: techs-known-minus-1, read safe (issue #4) ]
; InitSkills stores $2020 with a 16-bit `stx` over CountBits's uninitialized
; high byte ($ff02 in the Doma solo fight, $ffff before Cyan joins); read as a
; word, the junk high byte made even a real 2-tech ceiling `>= 8` and collapse
; to 0, pinning Cyan to Dispatch. Read a8 the junk is ignored, and an
; unlearned $ff (low byte) still trips >= 8 into the nothing-learned path.
; a8.  out: A = ceiling (0..7).  preserves X and Y.
.proc Ot6BushidoCeil
        .a8
        lda     $2020           ; techs known - 1, low byte only (issue #4)
        cmp     #$08
        bcc     :+
        lda     #$00            ; nothing learned: only tech 0 (Dispatch) exists
:       rtl
.endproc

; [ Bushido moving window of three (issue #5, refloored by #38): boost -> tech ]
; boost 1/2/3 selects Cyan's top three learned techs, weakest -> strongest:
; base = max(0, ceiling-2), tech = min(base + boost-1, ceiling). while he knows
; three or fewer, base is 0 and every learned tech is reachable; learn a fourth
; and the window slides up one, dropping the weakest. arithmetic only, no
; table.  boost 0 no longer names a tech (#38's 1-BP floor); it is clamped
; to 1 rather than allowed to underflow the window, so any caller that reaches
; here with a cleared pending byte gets the cheapest tier instead of garbage.
; a8/i16.  in: A = boost (0..3).  out: A = tech (0..ceiling).  clobbers X.
.proc Ot6BushidoTech
        .a8
        .i16
        cmp     #$01            ; #38: the floor is 1 BP, clamp a stray 0 up
        bcs     :+              ;   (the menu never offers boost 0 any more)
        lda     #$01
:       pha                     ; park boost ($01,s). the two scratch bytes in
                                ;   reach ($36 btlgfx's, OT6_SCR_BIT the hud
                                ;   builder's) both have owners; the stack has
                                ;   no owner and survives an nmi.
        ; [ issue #8 Layer B: manual-loadout read hook, packed 2-byte word ]
        ; word 0 (all existing saves) -> @auto, the vanilla window untouched.
        ; word nonzero -> return the player's stored tech for this boost slot
        ; (slot s = the 3-bit field at bit s*3), but only if it is still learned
        ; ($1cf7 bit set); otherwise fall back to the auto window for this slot
        ; rather than offer an uncastable tech.  Unpack and learned-test are the
        ; same F0 leaves the menu draw uses (Ot6LoadoutUnpack / Ot6TechLearned),
        ; so battle and menu cannot decode the word differently.  Callers run
        ; Ot6BushidoOblivion after this proc, so a manually-placed Oblivion
        ; (tech 7) keeps its spent-divine -> Tempest swap.
        longa
        lda     f:OT6_LOADOUT   ; packed loadout word (0 = AUTO)
        shorta                  ; plain SEP #$20, keeps Z (shorta0's tdc wipes it)
        beq     @auto
        lda     $01,s           ; boost (0..3) = slot
        jsl     Ot6LoadoutUnpack    ; A = stored tech for this slot (clobbers X)
        jsl     Ot6TechLearned      ; carry = learned (A and Y preserved)
        bcc     @auto           ; stored tech not learned -> auto fallback
        sta     $01,s           ; learned: overwrite the parked boost with tech
        pla                     ; A = tech (mirrors @auto's balanced tail)
        rtl
@auto:
        jsl     Ot6BushidoCeil  ; A = ceiling (preserves nothing we need)
        pha                     ; park ceiling ($01,s ; boost now $02,s)
        sec
        sbc     #$02            ; ceiling - 2   (A still = ceiling).  #38: the
        bcs     :+              ;   window is three tiers wide, not four
        lda     #$00            ; ceiling < 2: base floors at 0 (the window is all
:       ;                       ;   of {0..ceiling}, fewer than three techs)
        clc
        adc     $02,s           ; base + boost
        dec     a               ;   ... - 1 -> the tentative tech (boost >= 1 is
                                ;   guaranteed by the clamp at entry, so this
                                ;   cannot underflow; dec leaves C alone for the
                                ;   cmp below)
        cmp     $01,s           ; vs the ceiling
        bcc     :+
        lda     $01,s           ; cap at ceiling; applies only when boost overruns
:       ;                       ;   a <4-tech window (e.g. 3 bp, 3 techs known)
        sta     $02,s           ; stash the chosen tech over the parked boost byte
        pla                     ; drop the parked ceiling
        pla                     ; a = chosen tech 0-7 (stack balanced)
        rtl
.endproc

; [ Bushido Oblivion top-tier swap ]
; the window's top tier is Oblivion (tech 7) once Cyan has learned all eight:
; ceiling 7, boost 3 -> base 4 + 3 = 7, by the same base+boost sum as any other
; tier, so the divine comes out of the window itself with no special case
; outside it. it is selected here only when learned and unspent, and gated at
; resolution by Ot6Oblivion (hooked after ChooseTarget in CalcAttackEffect,
; because the target does not exist at command-latch time, swdtech being in
; RetargetCmdTbl). read the once-per-battle latch here and drop a spent
; Oblivion back to Tempest (6) so BP3 keeps a live top tier. (a divine is spent
; only on a broken, killable target; an unbroken/boss target folds to tempest at
; resolution and leaves the latch clear, so the menu keeps offering it.)
; a8/i16.  in: A = tech (0..7).  out: A = tech (a spent tech-7 -> 6).  clobbers X.
.proc Ot6BushidoOblivion
        .a8
        .i16
        cmp     #$07
        bne     @done           ; not oblivion: the chosen tech stands
        lda     $62ca           ; re-derive the active char's entity bit
        and     #$03
        asl                     ; slot * 2 = entity offset
        longa
        and     #$00ff
        tax
        shorta0
        lda     $3018,x         ; active char's bit ($01/$02/$04/$08)
        and     OT6_DIVINE_USED ; already spent the divine this battle?
        beq     @obl            ; no: oblivion stands
        lda     #$06            ; yes: revert to tempest for the rest of it
        rtl
@obl:   lda     #$07            ; oblivion
@done:  rtl
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
        jsl     Ot6BushidoOblivion  ; spent-divine top tier -> tempest
        pha
        asl5                    ; level * 32, the counter value vanilla's
        sta     $7b82           ;   bar drew, so w7e7b82 still feeds the
        pla                     ;   latch, the fill, and battle_mpcost's level()
        rtl
.endproc
