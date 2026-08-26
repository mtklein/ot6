; ------------------------------------------------------------------------------
; The damage-verb half of the boost canon
;
; Ot6BoostDmg: x2/x4/x8 on base damage for pending boost 1/2/3, with the gate
; list that names every command boost buys something other than damage on.
; Each exempt command's own purchase is a chance verb: fight/capture buy swings
; (ot6_boost.asm), bushido buys the tech tier (ot6_bushido.asm), steal buys
; odds (ot6_steal.asm), slot buys the rig (ot6_slot.asm), rage buys the coin
; (ot6_rage.asm).
; ------------------------------------------------------------------------------
; Split out of ot6_kits.asm (v0.9, 3037 lines) with the emission order of
; every instruction preserved: ot6.asm includes these files in exactly the
; order their text sat in the old one, so the assembler receives the identical
; token stream and the linker the identical segment. ROM CRC32 0x2E9B5A7F and
; ff6-en.map are byte-identical across the split.
; ------------------------------------------------------------------------------

; ------------------------------------------------------------------------------

; [ boost the base damage of a boosted character action ]

; called at the tail of the physical and magic base-damage calcs.
; damage x2/x3/x4 for pending boost 1/2/3; the per-target 9999 cap
; still applies downstream. a8/i16, x = attacker, 16-bit damage $11b0.
; fight and capture spend their boost on extra swings (Ot6FightBoost),
; tier-family spells spend it on tiers (Ot6QueueFold), and bushido
; spends it on the tech ladder (Ot6BushidoTier). The multiplier serves
; everything else. $3a7d = the action's attack id.

.proc Ot6BoostDmg
        php                     ; caller width varies: pin our own
        longi
        shorta0
        .a8
        .i16
        txa                     ; width-neutral character test
        cmp     #$08
        bcs     @d0            ; monsters never boost
        lda     $b1             ; counterattacks never boost (the $b1.0
        lsr                     ;   flag ExecRetal raises): interceptor's
        bcs     @d0            ;   dog rides command $02 attack $fc/$fd
                                ;   (battle_main.asm:12606).  no exemption
                                ;   below would catch it, and the counter
                                ;   path never reaches Ot6ActionEnd to
                                ;   charge what it delivered
        lda     $b5             ; current command
        beq     @d0            ; $00 fight: boost = extra swings
        cmp     #$06
        beq     @d0            ; $06 capture: same fight path
        cmp     #$07
        bne     :+
        brl     @bushido        ; $07 bushido: the ladder consumes the
                                ;   tech's own tier; SURPLUS above it is
                                ;   raw amplification (#137, "the tempered
                                ;   edge") -- see the arm below.  AUTO play
                                ;   spends exactly the tier and never has
                                ;   surplus, so the old full exemption's
                                ;   behavior is preserved wherever the old
                                ;   reasoning held
:
        cmp     #$10
        beq     @d0            ; $10 rage: a chance verb (#40).  boost bought
                                ;   the coin's certainty (Ot6RageCoin's tier
                                ;   ladder), never a damage multiplier.  This
                                ;   gate is required on the start turn:
                                ;   Cmd_10 executes the first possessed action
                                ;   in the same turn (its _c21554 tail) while
                                ;   the pending boost is still live, so without
                                ;   it a 3-BP Rage-start would buy the
                                ;   guaranteed special and also x8 it, the
                                ;   double-dip kits.md's "Boost-tiered Steal"
                                ;   rules out.
        cmp     #$0f
        beq     @d0            ; $0f slot: a chance verb.  boost bought the
                                ;   reel's certainty (the Ot6SlotRig tier
                                ;   ladder), never a damage multiplier. without
                                ;   this gate a pending boost would also x2/x8
                                ;   the slot attack it just chose, the
                                ;   double-dip kits.md's "Boost-tiered Steal"
                                ;   rules out
                                ;   (certainty instead of multiplication),
                                ;   and the bushido/$07 gate above rules out
                                ;   for the tier ladder.
        cmp     #$05
        beq     @d0            ; $05 steal: a chance verb, not a damage one.
                                ;   boost buys the rare/guarantee downstream
                                ;   (Ot6StealBoostLevel / Ot6StealSlot), never
                                ;   a damage multiplier: "on chance verbs
                                ;   boost guarantees" (DESIGN.md). steal deals
                                ;   no damage today, so this gate is redundant
                                ;   (CalcDmg reaches here regardless of power),
                                ;   and it states the ruling in advance for
                                ;   Mug's later damage+steal kit (kits.md).
        lda     OT6_BOOST_REVEALED,x         ; pending boost level
        bne     :+
@d0:    brl     done            ; near relay: the #137 arm below pushed
                                ;   `done` out of short-branch reach for
                                ;   the gate list above
:       phx

        ldx     #$0000
@scan:  lda     f:Ot6FoldTbl,x  ; tier-family spell? tiers are the boost
        cmp     $3a7d
        beq     @tier
        inx
        cpx     #$0018
        bcc     @scan
        plx
        lda     OT6_BOOST_REVEALED,x         ; pending boost level (reload)
        bra     @mul0
@tier:  plx
        bra     done
@mul0:
        sta     OT6_SCR_BIT
        longa
        lda     $11b0
@mul:   asl                     ; not a true xN, but x2/x4/x8 reads better
        bcs     @cap            ; on 16-bit overflow, saturate
        shorta                  ; 8-bit dec: a 16-bit rmw would clobber
        dec     OT6_SCR_BIT     ; the scratch byte next door
        longa                   ; (rep/sep leave z alone; a survives)
        bne     @mul
        bra     @store
@cap:   lda     #$7fff
@store: sta     $11b0
        shorta0
        bra     done
        ; ---- #137, the tempered edge: surplus boost amplifies a tech ----
        ; A tech's INTRINSIC cost is what its own AUTO-window slot
        ; charges: intrinsic(T) = clamp(T - max(0, ceiling-2) + 1, 1, 3).
        ; Pending boost beyond the intrinsic is surplus, and surplus
        ; feeds the same doubler below (1 -> x2, 2 -> x4): Dispatch
        ; placed on row 3 by the loadout configurator is Dispatch x4.
        ; AUTO play never has surplus (its window charges exactly the
        ; intrinsic), the top of the ladder keeps its exclusivity
        ; (Oblivion's intrinsic is 3), and an Oblivion that declines an
        ; unbroken target and resolves as Tempest ($5b, intrinsic 2)
        ; carries surplus 1 -- the fallback stops being a dead turn.
        ; Everything reads from the RESOLVED action at damage time, so
        ; there is no new state and no latch/resolution race.
@bushido:
        lda     $3a7d           ; resolved attack id
        sec
        sbc     #$55            ; bushido ids are $55 + tech
        cmp     #$08
        bcc     :+
        brl     done            ; not a tech id: leave it alone
:
        pha                     ; park tech (0..7)
        jsl     Ot6BushidoCeil  ; A = ceiling (preserves X and Y)
        sec
        sbc     #$02
        bcs     :+
        lda     #$00            ; base = max(0, ceiling - 2)
:       sta     OT6_SCR_BIT
        pla                     ; tech
        sec
        sbc     OT6_SCR_BIT     ; tech - base
        bmi     @floor          ; below the window: intrinsic floors at 1
        inc     a               ; + 1 -> intrinsic (1..3 by construction;
        cmp     #$04            ;   the clamp is defensive)
        bcc     @intr
        lda     #$03
        bra     @intr
@floor: lda     #$01
@intr:  sta     OT6_SCR_BIT
        lda     OT6_BOOST_REVEALED,x
        sec
        sbc     OT6_SCR_BIT     ; pending - intrinsic = surplus
        beq     @nodip          ; the ladder consumed it all: no dip
        bpl     @dip
@nodip: brl     done            ; (bmi joins: a manual top tech fired
                                ;   under-spent cannot owe damage back)
@dip:
        phx
        brl     @mul0           ; A = surplus (1..2) -> x2 / x4
done:   plp
        rtl
.endproc
