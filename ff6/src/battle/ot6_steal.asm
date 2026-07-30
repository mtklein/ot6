; ------------------------------------------------------------------------------
; LOCKE -- BOOST ON THE STEAL ROLL (a chance verb buys certainty)
;
; Two tilts: the success roll and the rare/common pick. The Steal SUBMENU and
; the Filch/Bestow rows that share the command are ot6_thief.asm.
; ------------------------------------------------------------------------------
; Carved out of ot6_kits.asm (v0.9, 3037 lines) with the emission order of
; every instruction preserved: ot6.asm includes these files in exactly the
; order their text sat in the old one, so the assembler sees the identical
; token stream and the linker the identical segment. Proven, not argued --
; ROM CRC32 0x2E9B5A7F and ff6-en.map are byte-identical across the split.
; ------------------------------------------------------------------------------

; ------------------------------------------------------------------------------

; [ boost tilts the steal SUCCESS roll — the chance verb's certainty ]

; DESIGN.md's canon rule: on damage verbs boost multiplies; on chance verbs
; boost GUARANTEES. Steal is the party's slot machine, so each BP buys odds
; and the full spend buys certainty — in steal's own vocabulary.
;
; This replaces the single `lda $3b18,x` (load attacker level) at the head of
; the vanilla success math (TargetEffect_52, battle_main.asm @39a?..@39d8):
;       level  ->  adc #$32   (net +50, the shorta_sec carry trick)
;              ->  bcs guaranteed         (overflow shortcut vanilla owns)
;              ->  sbc targetLevel        (chance = level+50-targetLevel)
;              ->  bcc nothing / bmi guaranteed (>=128 shortcut it owns)
;              ->  $ee, sneak-ring doubles it, RandA(100) < $ee = success.
; Feeding a BOOSTED level into that exact chain is the whole hook — every
; downstream branch stays vanilla and untouched:
;   0 bp: the raw level, carry SET exactly as shorta_sec left it — the roll,
;         the sneak-ring double, the two shortcuts are all byte-for-byte
;         vanilla. Boost is transparent when unspent.
;   1 bp: +40 to the level. A hard steal becomes a coin flip; a coin flip a
;         near-lock. Sneak Ring still doubles the residual $ee.
;   2 bp: +90. Level parity now clears the bmi (>=128) shortcut outright;
;         only a steep deficit still rolls (and the ring still helps it).
;   3 bp: clamp to $ff so the very next `adc #$32` OVERFLOWS and vanilla's own
;         `bcs` guarantees the steal — reached BEFORE $ee exists, so the ring
;         is moot at the cap (as designed), and NO success RNG is drawn at all
;         (the certainty is roll-independent, which the test leans on).
; The monotonic ladder (0 < +40 < +90 < certain) improves success at every
; step and can only rescue a level deficit, never worsen it.
;
; The counterattack gate ($b1.0) is this file's convention (Ot6BoostDmg,
; Ot6FightBoost, Ot6QueueFold all carry it): a countered action runs through
; ExecRetal and ends at an UNHOOKED EndAction, so Ot6ActionEnd never charges
; what it delivered. A steal can't itself counter, but reading the gate keeps
; the "boost is always paid for" invariant honest (the boost-economy audit).
;
; a8/i8 — the width DoTargetEffect's `shortai` pinned; x = attacker, y =
; target, BOTH preserved (the caller still needs them). Returns a = the level
; the vanilla math should see, carry SET for the `adc #$32` that follows.

.proc Ot6StealBoostLevel
        .a8
        .i8
        lda     $b1             ; countered? never boost — it can't be charged
        lsr
        bcs     @vanilla
        lda     OT6_BOOST_REVEALED,x         ; pending boost (0-3)
        beq     @vanilla        ; unspent: byte-for-byte vanilla
        cmp     #$03
        bcs     @cap            ; 3 bp -> certainty
        cmp     #$02
        bcc     @b1
        lda     #90             ; 2 bp: +90 to the level
        bra     @add
@b1:    lda     #40             ; 1 bp: +40 to the level
@add:   clc
        adc     $3b18,x         ; level + tier bonus
        bcc     :+
        lda     #$ff            ; clamped: a high level never wraps small
:       sec                     ; carry set: the adc #$32 wants it (net +50)
        rtl
@cap:   lda     #$ff            ; forces adc #$32 to overflow -> vanilla bcs
        sec
        rtl
@vanilla:
        lda     $3b18,x         ; vanilla: the raw attacker level...
        sec                     ; ...with carry as shorta_sec left it (lsr ate it)
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ boost tilts the steal ITEM pick toward the rare slot — same chance rule ]

; Replaces the vanilla slot roll at @39d8 in TargetEffect_52:
;       phy / Rand / cmp #$20 / (iny) / lda $3308,y / ply
; Vanilla: rand < $20 (1/8) takes slot 0 ($3308,y — the 12.5% RARE), else
; slot 1 ($3309,y — the 87.5% COMMON); the picked byte (which may be $ff when
; that slot is empty) is handed back for the caller's own `cmp #$ff / beq
; nothing` test. Tiers:
;   0 bp: the vanilla roll, byte-for-byte — one Rand, the $20 threshold, and
;         an empty picked slot still falls through to "nothing" downstream.
;   1-3 bp: FALLBACK-AWARE. A boosted steal has already been promised an item
;         (the top of TargetEffect_52 proved at least one slot non-empty on
;         the $ffff check), so it must never hand back $ff: if one slot is
;         empty it takes the other. When BOTH slots hold an item the rare
;         takes a rising share of the roll — $60 (3/8) at 1 bp, $c0 (3/4) at
;         2 bp — and at 3 bp the rare is taken OUTRIGHT with no roll: the
;         cap's "rare if present" guarantee, and (like the success cap) it
;         draws no RNG.
; The fallback is what keeps boost monotonic for a one-item enemy: at 0 bp
; rolling the empty slot wastes the steal; at >=1 bp it can't. Boost never
; conjures loot — an all-empty enemy dropped out at the top and never arrives
; here, and an already-looted enemy (both slots cleared to $ff after its one
; steal) drops out the same way.
;
; a8/i8, x = attacker, y = target base (both preserved); returns a = the
; chosen item id (or $ff at 0 bp for an empty picked slot). Rand preserves x
; (phx/plx) and never touches y.

.proc Ot6StealSlot
        .a8
        .i8
        lda     $b1             ; countered? vanilla roll (convention, as above)
        lsr
        bcs     @vanilla
        lda     OT6_BOOST_REVEALED,x         ; pending boost
        beq     @vanilla        ; 0 bp: the exact vanilla roll
        lda     $3308,y         ; slot 0 = rare
        cmp     #$ff
        beq     @common         ; no rare present -> the common is the item
        lda     $3309,y         ; slot 1 = common
        cmp     #$ff
        beq     @rare           ; no common present -> the rare is the item
        lda     OT6_BOOST_REVEALED,x         ; both present: rising rare share by tier
        cmp     #$03
        bcs     @rare           ; 3 bp: rare outright, no roll (guarantee)
        cmp     #$02
        bcc     @t1
        lda     #$c0            ; 2 bp: 3/4 of the roll is rare
        bra     @roll
@t1:    lda     #$60            ; 1 bp: 3/8 of the roll is rare
@roll:  pha                     ; park the threshold across the draw (no scratch)
        ot6_rand                ; a = rand; x saved/restored -> $01,s stays threshold
        cmp     $01,s           ; carry set iff rand >= threshold
        pla
        bcc     @rare           ; rand < threshold -> rare
@common:lda     $3309,y
        rtl
@rare:  lda     $3308,y
        rtl
@vanilla:
        phy
        ot6_rand                ; a = rand; y stays parked at $01,s across it
        cmp     #$20
        bcc     :+
        iny
:       lda     $3308,y
        ply
        rtl
.endproc
