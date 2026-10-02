; ------------------------------------------------------------------------------
; OT6: a pass OT6 added goes to another body when its target has fallen
;
; OT6 buys extra passes of an action through $3a70, the engine's one
; multi-hit counter (ot6_hitcount.asm's header): a boosted Fight or Capture
; (Ot6FightBoost), Pummel/Bum Rush/Drill (Ot6HitCount), a dumped Throw
; (Ot6ThrowBoost), Setzer's Coin Toss, Hired Help and Jackpot
; (Ot6SetzerEffect) and a character's GP Rain (Ot6RainPasses).
;
; Vanilla's loop does not retarget a pass whose body died on the pass before.
; ExecAttack sets $ba bit 2 ("don't retarget") at every pass after the first
; (@31c1), and clears it only when the pass STARTS with an empty mask
; (@31c5).  A pass starts with the previous pass's mask ($3a30, restored at
; @3243 and saved by _setupoldtarget), so after a kill the next pass starts
; on the dead body: ChooseTarget masks it out, finds bit 2 set and skips
; Retarget, and the pass lands nowhere.  Its empty mask is saved, so the pass
; after that starts empty and retargets.  Passes alternate dead / retarget,
; and half of what a boost bought after a kill hits nothing while a body
; still stands (wt/hire-sprite: a 3 BP Hired Help on three bodies landed
; passes 1 and 3, passes 2 and 4 found nothing, and the third body kept its
; 2,058 HP; build/attempts/wt/hire-sprite/retarget/).
;
; Vanilla's own multi-pass actions keep their rules: an unboosted two-hand
; Fight's second hand still swings at nothing after the first hand's kill,
; Empowerer's second pass stays on its body, and actions that pick at random
; every pass (Offering, Quadra Slam/Slice, the Dragon Horn's extra jumps:
; $ba bit 6) or may hit a fallen body (a weapon's follow-up spell: $ba bit
; 3) never reach this branch with a choice to make.  Only an action OT6
; added passes to retargets, and only after its first pass.
; ------------------------------------------------------------------------------

.segment "ot6_code"

; ------------------------------------------------------------------------------

; [ mark the action's pass count as OT6's ]

; jsl right after an adder's `sta $3a70`: OT6_PASSRETARGET = $3a70 as it now
; stands, the count the first pass will run at (nothing between the adders
; and that pass's ChooseTarget writes $3a70).  0 = no passes added, which is
; also InitGfxScript's reset.  Preserves A, X, Y and every flag (Ot6HitCount
; promises its caller the carry).  a8, either index width, any data bank.
.proc Ot6PassesAdded
        .a8
        php
        pha
        lda     f:$7e0000+$3a70
        sta     f:$7e0000+OT6_PASSRETARGET
        pla
        plp
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ ChooseTarget's empty mask: retarget it, and where? ]

; jsl from ChooseTarget where its mask has come out empty (@58b3), replacing
; `lda $ba / bit #$04`; a `bne` after it skips Retarget, and a `bcs` skips
; only Retarget itself.  Vanilla retargets unless $ba bit 2 is set.  With it
; set, a pass of an action OT6 added passes to retargets all the same, once
; the first pass has run ($3a70 has counted down from the mark
; Ot6PassesAdded left): its target fell to an earlier pass of the same
; action.  It goes to the side that target was on, not to the side
; Retarget would pick (a muddled character's Retarget turns to its own
; party: measured, a muddled Genji pair with a 3 BP dump went on swinging
; at CELES once the last monster fell).  So $b8/$b9 get every slot of the
; previous pass's side ($3a30, the targets that pass chose), and ChooseTarget
; carries on from there as after Retarget: _c258fa and CheckTargetsPresent
; keep the bodies still standing, and $bb narrows them to one or keeps the
; group (a single-target hire stays single, a Coin Toss stays on the group).
; A pass that finds no one standing there still lands nowhere -- or, for a
; Fight ($ba bit 5), on the backup targets ($3a4e), as vanilla's does.
;
; a8/i8 (ChooseTarget's shortai), db=$7e, x = the attacker.  out: Z clear =
; keep the empty mask; Z set, carry clear = vanilla's Retarget; Z set, carry
; set = the side is in $b8/$b9.  A clobbered (every path reloads it); X and Y
; preserved.
.proc Ot6PassRetarget
        .a8
        lda     $ba
        and     #$04
        bne     held
        clc                     ; Z set (the and), carry clear: vanilla
        rtl
held:   lda     f:$7e0000+OT6_PASSRETARGET
        beq     keep            ; vanilla's own passes: keep its rule
        cmp     f:$7e0000+$3a70
        beq     keep            ; the action's first pass: vanilla
        lda     f:$7e0000+$3a30 ; the previous pass's characters...
        beq     :+
        lda     #$0f            ;   ... means the party's side
:       sta     $b8
        lda     f:$7e0000+$3a31 ; its monsters...
        beq     :+
        lda     #$3f            ;   ... means the monsters' side
:       sta     $b9
        lda     #$00            ; Z set
        sec                     ; carry set: this side, no Retarget
        rtl
keep:   lda     #$04            ; Z clear: no retarget
        rtl
.endproc
