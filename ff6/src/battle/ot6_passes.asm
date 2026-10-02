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
; Retarget.  A hire's or a roll's pass then lands nowhere; its empty mask is
; saved, so the pass after that starts empty and retargets: passes alternate
; dead / retarget (wt/hire-sprite: a 3 BP Hired Help on three bodies landed
; passes 1 and 3, passes 2 and 4 found nothing, and the third body kept its
; 2,058 HP; build/attempts/wt/hire-sprite/retarget/).  A Fight's emptied
; mask goes back to the backup targets ($3a4e: Fight's targeting sets $ba
; bit 5, CmdTargetTbl), so its swings after a kill beat the corpse while a
; body still stood (battle_passretarget's base tally, `B fight`), or, with no
; backup, landed nowhere (`A fight`).
;
; Vanilla's own multi-pass actions keep their rules: an unboosted Genji
; pair's second hand still swings at the body the first hand felled
; (measured, battle_passretarget), Empowerer's second pass is vanilla's,
; and actions that pick at random every pass (Offering, Quadra Slam/Slice,
; the Dragon Horn's extra jumps: $ba bit 6) or may hit a fallen body (a
; weapon's follow-up spell: $ba bit 3) never reach this branch with a
; choice to make.  Only an action OT6 added passes to retargets, and only
; after its first pass.
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

; [ a pass of the action has targeted ]

; jsl from CalcAttackEffect right after ChooseTarget (and the divine gates
; behind it): once the action has passes OT6 added (a nonzero mark), set
; the mark's bit 7, so Ot6PassRetarget applies OT6's rule from the next
; pass on.  A bit of OT6's own, set at the one point every targeting pass
; goes through, rather than a reading of vanilla's state: the backup
; targets ($3a4e) are written by _setupoldtarget only on its 16-bit
; `lda $3414 / bmi` arm (so by $3415's top bit, which commands set
; differently) and zeroed by CalcCmdDelay for an action queued without a
; target; they record targets kept for a Fight's emptied mask, not whether
; this action has targeted yet.  Preserves every register and flag.  Any
; width.
.proc Ot6PassTargeted
        php
        sep     #$20
        .a8
        pha
        lda     f:$7e0000+OT6_PASSRETARGET
        beq     :+
        ora     #$80
        sta     f:$7e0000+OT6_PASSRETARGET
:       pla
        plp
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ the action's last pass is done: its mark goes ]

; jsl from ExecAttack's tail where `dec $3a70 / bmi` finds no pass left.
; The mark is the action's, and ChooseTarget is also called between
; actions with $3a70 at 0 and $3a30 left over: CalcCmdDelay's, as a muddled,
; zombied or monster actor's action is queued with no target yet (`lda #$04
; / trb $ba` there, then ChooseTarget).  A mark left standing until the next
; ExecCmd's InitGfxScript read such a call as a later OT6 pass and gave it
; the monster side -- measured on battle_cointoss: a Defend queued after a
; 1 BP Coin Toss reached this hook with the toss's mark (`Ot6PassRetarget
; x=00 mark=1 $3a70=255 $3a30=0700`), RandBit drew a target for it, the
; battle's draws moved, and the suite went red on its second toss
; (build/attempts/wt/pass-retarget/round2/cointoss/).  Preserves every
; register and flag.  Any width.
.proc Ot6PassesDone
        php
        sep     #$20
        .a8
        pha
        lda     #$00
        sta     f:$7e0000+OT6_PASSRETARGET
        pla
        plp
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ ChooseTarget's empty mask: retarget it, and where? ]

; jsl from ChooseTarget where its mask has come out empty (@58b3), replacing
; `lda $ba / bit #$04`; a `bne` after it skips Retarget, and a `bcs` skips
; only Retarget itself.
;
; Vanilla's own passes, and an action's passes until one of them has
; targeted, keep vanilla's rule: retarget unless $ba bit 2 ("don't
; retarget") is set.  "Has targeted" is the mark's bit 7 (Ot6PassTargeted,
; after ChooseTarget), not the pass count: an empty hand's pass never
; reaches ChooseTarget (ExecAttack's `lda $11a6 / jeq @3275`), so a Fight
; with its weapon in the off hand only first targets one pass down the
; count, and a queued target that fell before the action must still get
; vanilla's first-pass retarget there (wt/pass-retarget round 3: with the
; count test that pass took `keep` and every swing landed nowhere).
;
; A later pass of an action OT6 added passes to found its targets fallen to
; an earlier pass of the same action, or found nothing at all after such a
; pass landed nowhere (ExecAttack's @31c5 clears bit 2 for a pass that STARTS empty, and
; vanilla would Retarget it).  It goes to another monster or nowhere:
;   * the previous pass's targets ($3a30) were on the monster side -- a
;     monster, or a character fighting as an enemy ($3a40) -- so $b8/$b9 get
;     that whole side (the monster slots and the $3a40 characters), and
;     ChooseTarget carries on as after Retarget: _c258fa and
;     CheckTargetsPresent keep the bodies still standing, and $bb narrows
;     them to one or keeps the group (a hire stays single, a Coin Toss stays
;     on the group).  None standing: the pass lands nowhere -- or, for a
;     Fight ($ba bit 5), on the backup targets ($3a4e), the fallen body, as
;     vanilla's does;
;   * anything else (a party member: a muddled or charmed actor's pick, or
;     the player's aim at an ally; or nothing): no retarget, so the pass
;     lands nowhere (a Fight's on the fallen member), and never spreads to
;     another ally.
; Never vanilla's Retarget, which picks the side by the attacker's status
; and turns a muddled actor on its own party.
;
; a8/i8 (ChooseTarget's shortai), db=$7e, x = the attacker.  out: Z clear =
; keep the empty mask; Z set, carry clear = vanilla's Retarget; Z set, carry
; set = the monster side is in $b8/$b9.  A clobbered (every path reloads
; it); X and Y preserved.
.proc Ot6PassRetarget
        .a8
        lda     f:$7e0000+OT6_PASSRETARGET
        bpl     vanilla         ; no passes OT6 added (0), or none of this
                                ;   action's passes has targeted yet (bit 7,
                                ;   Ot6PassTargeted): vanilla's rule
        lda     f:$7e0000+$3a31 ; the previous pass's monsters...
        bne     monsters
        lda     f:$7e0000+$3a30 ; ... or characters fighting as enemies
        and     f:$7e0000+$3a40
        beq     keep            ; a party member, or nothing: no retarget
monsters:
        lda     f:$7e0000+$3a40 ; the monster side: characters fighting as
        sta     $b8             ;   enemies (Retarget's own `lda $3a40 /
        lda     #$3f            ;   tsb $b8`) and every monster slot
        sta     $b9
        lda     #$00            ; Z set
        sec                     ; carry set: this side, no Retarget
        rtl
vanilla:
        lda     $ba
        and     #$04            ; Z set: vanilla retargets; clear: it keeps
        clc
        rtl
keep:   lda     #$04            ; Z clear: no retarget
        rtl
.endproc
