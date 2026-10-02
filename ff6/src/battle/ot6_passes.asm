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

; [ ChooseTarget's empty mask: retarget it, and where? ]

; jsl from ChooseTarget where its mask has come out empty (@58b3), replacing
; `lda $ba / bit #$04`; a `bne` after it skips Retarget, and a `bcs` skips
; only Retarget itself.
;
; Vanilla's own passes, and the first pass of any action, keep vanilla's
; rule: retarget unless $ba bit 2 ("don't retarget") is set.
;
; A later pass of an action OT6 added passes to ($3a70 has counted down from
; the mark Ot6PassesAdded left) found its targets fallen to an earlier pass
; of the same action, or found nothing at all after such a pass landed
; nowhere (ExecAttack's @31c5 clears bit 2 for a pass that STARTS empty, and
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
        beq     vanilla         ; no passes OT6 added: vanilla's rule
        cmp     f:$7e0000+$3a70
        beq     vanilla         ; the action's first pass: vanilla's rule
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
