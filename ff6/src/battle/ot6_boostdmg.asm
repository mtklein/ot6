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

; called at the tail of the physical and magic base-damage calcs.
; damage x2/x3/x4 for pending boost 1/2/3; the per-target 9999 cap
; still applies downstream. a8/i16, x = attacker, 16-bit damage $11b0.
; fight and capture spend their boost on extra swings (Ot6FightBoost),
; tier-family spells spend it on tiers (Ot6QueueFold), and bushido
; spends it on the tech ladder (Ot6BushidoTier). The multiplier serves
; everything else.
;
; The tier test reads the action as it was queued: $3a7c/$3a7d, the command
; and attack InitPlayerAction copies out of the queue when the action starts,
; which nothing rewrites for the rest of it.  Ot6QueueFold folds at queue
; time, and only when the queued command is magic, x-magic, lore or summon
; (Ot6FoldCmdTbl) and the queued attack is a fold-table spell, so exactly
; those actions spent their boost on a tier.  Both halves are needed.  The
; command half: Throw's attack byte is an item id, and a Dirk ($00) or
; MithrilKnife ($01) reads as Fire or Ice; an engine-chosen action queues
; command/attack $0000 (RandCharAction), which the attack half alone reads
; as Fire.  The queued pair and not the executing $b5/$b6: handlers rewrite
; $b5/$b6 mid-action, and the rewritten pair can look like a folded cast
; that never folded.  A weapon's on-hit spell runs as command $02 with $b6 =
; the spell (_c237eb), a rod or shield used from Item as command $02 with the
; item's spell (Cmd_01), a sketched attack under whatever command
; GetCmdForAI names, and Umaro's Storm as command $02 with $b6 = $54.  None
; of those was folded, so each takes the multiplier.  Measured on both keys:
; probe_fight_proc_boost (a boosted Fight's Blizzard Ice, `820->820` on the
; $b6 key) and probe_throw_boost; battle_procboost guards the first.

.proc Ot6BoostDmg
        php                     ; caller width varies: pin our own
        longi
        shorta0
        .a8
        .i16
        txa                     ; width-neutral character test
        cmp     #$08
        bcs     done            ; monsters never boost
        lda     $b1             ; counterattacks never boost (the $b1.0
        lsr                     ;   flag ExecRetal raises): interceptor's
        bcs     done            ;   dog rides command $02 attack $fc/$fd
                                ;   (battle_main.asm:12606); the counter
                                ;   path never reaches Ot6ActionEnd to
                                ;   charge what it delivered
        lda     $b5             ; current command
        beq     done            ; $00 fight: boost = extra swings
        cmp     #$06
        beq     done            ; $06 capture: same fight path
        cmp     #$07
        beq     done            ; $07 bushido: boost bought the tech tier,
                                ;   so it must not also buy a multiplier
        cmp     #$10
        beq     done            ; $10 rage: boost bought the coin's
                                ;   certainty (Ot6RageCoin), never a damage
                                ;   multiplier. Cmd_10 executes the first
                                ;   possessed action in the same turn while
                                ;   the pending boost is still live, so this
                                ;   gate is required on the start turn too
        cmp     #$0f
        beq     done            ; $0f slot: boost bought the reel's
                                ;   certainty (Ot6SlotRig), never a damage
                                ;   multiplier
        cmp     #$05
        beq     done            ; $05 steal: boost buys the rare/guarantee
                                ;   downstream (Ot6StealBoostLevel /
                                ;   Ot6StealSlot), never a damage multiplier
        lda     OT6_BOOST_REVEALED,x         ; pending boost level
        beq     done
        phx
        ldx     #$0003          ; only a spell command can have bought a
@cmd:   lda     $3a7c           ;   tier: Ot6QueueFold's own four, mirrored
        cmp     f:Ot6FoldCmdTbl,x  ; in Ot6FoldCmdTbl.  A table and not a
        beq     @spell          ;   `cmp #imm / beq` chain: battle_boostprice
        dex                     ;   reads every `cmp #imm / beq` in this
        bpl     @cmd            ;   proc's first 96 bytes as a command the
        plx                     ;   multiplier EXEMPTS, and these four are
        bra     @plain          ;   the opposite of exempt
@spell: ldx     #$0000
@scan:  lda     f:Ot6FoldTbl,x  ; tier-family spell? tiers are the boost
        cmp     $3a7d           ; the queued attack (see the header)
        beq     @tier
        inx
        cpx     #$0018
        bcc     @scan
        plx
@plain: lda     OT6_BOOST_REVEALED,x         ; pending boost level (reload)
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
done:   plp
        rtl
.endproc

; the commands whose cast Ot6QueueFold may have folded to a tier -- magic,
; x-magic, lore, summon -- in the order of its own gate (ot6_boost.asm)
Ot6FoldCmdTbl:
        .byte   $02, $17, $0c, $19
