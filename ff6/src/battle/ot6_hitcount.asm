; ------------------------------------------------------------------------------
; OT6: multi-hit hit counts
;
; A landed hit that matches a weakness chips a shield, so the number of times
; an action strikes is the break-rate dial.
;
; The engine has exactly one multi-hit mechanism, $3a70 "number of attacks
; (0 = 1 attack)" (battle_main.asm:6428), consumed by one loop:
;
;       @3288:  plx
;               dec  $3a70
;               bmi  @3291
;               pea  ExecAttack-1       ; battle_main.asm:8390-8392
;
; so an extra count is a whole extra ExecAttack -> CalcTargetDmg pass and
; therefore a whole extra chip opportunity.  Adding to $3a70 is all this
; module does.
;
; Why a keyed table rather than a special effect.  $11a9 holds one byte and
; selects one effect (DoAttackerEffect, battle_main.asm:10376-10383), and five
; of the abilities in scope already spend it (Suplex $30, Retort $3c, Stunner
; $3f, Cleave $23, Empowerer $36), so hit counts cannot be data-authored
; there.  Reusing vanilla's quadra effect $32 would force exactly x4 plus
; random targeting.  A scanned (id, extra) table is the shape ot6 already uses
; for per-ability data (Ot6SkillClassTbl, Ot6AbilityCostTbl).
;
; Why the hook sits in the command handlers rather than in LoadMagicProp.  A
; hook that runs again inside the multi-attack loop would re-arm $3a70 and
; the action would never end.  ExecAttack calls InitTarget itself when $3400
; is $ff (battle_main.asm:8276-8282), and InitTarget_00/_02 call LoadMagicProp
; (:6636), so LoadMagicProp is reachable from inside the loop.  Cmd_0a and
; Cmd_09 are not: the multi-attack loop re-enters ExecAttack, never the
; command handler, and ExecCmd clears $3a70 through InitGfxScript (:6417)
; before dispatching, so each handler sees a fresh 0 exactly once per action.
; That is the same site and the same argument as Ot6FightBoost, which lives
; in FightAttack for the same reason.
;
; The Cmd_09 shim's sharpest hazard is not re-entry but the carry.  `sbc #$a2`
; there reads the carry the dispatcher left set, so a hook that clobbered it
; would misindex EVERY tool, not just Drill.  This proc's php/plp restores it.
;
; SwdTech has no hook because no SwdTech count changes: Quadra Slam and Quadra
; Slice are already x4 through vanilla's effect $32, and Empowerer x2 through
; $36.
; ------------------------------------------------------------------------------

.segment "ot6_code"

; ------------------------------------------------------------------------------

; [ ability id -> extra attacks ]

; 2-byte records, $ff-terminated, scanned once per action.  Keyed by attack id
; for Blitz and by tool item id for Tools; the two ranges are disjoint
; ($5d-$64 vs $a3-$aa) and each caller passes only its own, so one table
; serves both.  An absent id is one hit, which is vanilla.

Ot6HitCountTbl:
        .byte   $5d, 1          ; pummel    x2 bludgeoning
        .byte   $64, 3          ; bum rush  x4 bludgeoning
        .byte   $a8, 1          ; drill     x2 piercing
        .byte   $ff

; ------------------------------------------------------------------------------

; [ add this ability's extra attacks to the action's swing count ]

; a = ability id (preserved).  every processor flag is preserved, including
; carry: Cmd_09 calls this between loading $b6 and an `sbc #$a2` that reads
; the carry the dispatcher left set, the same contract Ot6ItemClass documents.
; caller a8; index width varies at these sites, so pin it.
;
; $3a70 is written long rather than through the data bank.  Ot6FightBoost gets
; away with `adc $3a70` because FightAttack's db is known, and these two sites
; are in the same dispatch chain, but a long store costs one cycle in a
; per-action path and removes the assumption.

.proc Ot6HitCount
        .a8
        php
        longi
        .i16
        phx
        pha                     ; the ability id, for the scan compares
        ldx     #$0000
@scan:  lda     f:Ot6HitCountTbl,x
        cmp     #$ff
        beq     @done           ; ran off the table: one hit, vanilla
        cmp     $01,s
        beq     @hit
        inx
        inx                     ; 2-byte records: id, extra attacks
        bra     @scan
@hit:   lda     f:Ot6HitCountTbl+1,x
        clc
        adc     f:$7e0000+$3a70 ; add, so a future +1 source composes
        sta     f:$7e0000+$3a70
        jsl     Ot6PassesAdded  ; #545: strikes stay on the aim (ot6_passes.asm)
        jsr     tool
        lda     f:Ot6HitCountTbl+1,x ; #554: one animation per this many
        inc     a               ;   strikes (Ot6FoldAnim); set after every
        sta     f:$7e0000+OT6_FOLDN ; adder, since Ot6PassesAdded clears it
        lda     #$00
        sta     f:$7e0000+OT6_FOLDPASS ; the first pass animates
        bra     @out
@done:  jsr     tool
@out:   pla                     ; the ability id, back to the caller
        plx
        plp
        rtl

tool:   lda     $03,s           ; (under the return) a Tool (item ids
        cmp     #$a3            ;   $a3-$aa)?  Edgar's Overclock doubles its
        bcc     :+              ;   firings (ot6_overclock.asm); x kept
        cmp     #$ab
        bcs     :+
        jsl     Ot6OverclockPasses
:       rts
.endproc

; ------------------------------------------------------------------------------

; [ #554: one animation per move use ]

; A fixed multi-hit's strikes are whole passes (above), and each pass
; queues its own battle animation: Pummel's flurry played twice and read as
; the move used twice (owner, 2026-11-17).  So the animation plays once for
; the first strike of each group of OT6_FOLDN, and the strikes after it keep
; their pass and their numerals, which land a beat apart.
;
; jsl from CalcAttackEffect right after `jsr _c235ad` has queued the pass's
; animation command ([$06, command, attack id], at queue offset $3a71).
; While the action carries OT6's added passes (OT6_PASSRETARGET) and its
; strikes fold (OT6_FOLDN, Ot6HitCount), the pass that starts a group keeps
; its animation and the next OT6_FOLDN - 1 have it rewritten to command $04,
; Ot6GfxCmdFold (btlgfx_main.asm): no animation, a beat, the earlier
; strike's numerals retired, and the gfx data pointer stepped as $06's
; would be.  Everything else about the pass is untouched: its targeting,
; damage, chips and break (the numerals carry #539's presentation), and the
; passes stay real.  An Overclocked Drill (four passes) is two groups of two.
; A pass that never reaches the queue (spent, #545) counts nothing.
;
; a8, either index width (CalcAttackEffect: i8), db=$7e.  Preserves a/x/y/p.
.proc Ot6FoldAnim
        php
        rep     #$10
        .i16
        phx
        sep     #$20
        .a8
        pha
        lda     f:$7e0000+OT6_PASSRETARGET
        beq     @out            ; no passes OT6 added to this action
        lda     f:$7e0000+OT6_FOLDN
        beq     @out            ; not a fixed multi-hit: every pass animates
        lda     f:$7e0000+OT6_FOLDPASS
        bne     @fold
        lda     f:$7e0000+OT6_FOLDN ; the group's first strike animates;
        dec     a               ;   the next N - 1 fold
        sta     f:$7e0000+OT6_FOLDPASS
        bra     @out
@fold:  dec     a
        sta     f:$7e0000+OT6_FOLDPASS
        lda     f:$7e0000+$3a71 ; this pass's animation command
        rep     #$20
        .a16
        and     #$00ff
        tax
        sep     #$20
        .a8
        lda     f:$7e0000+$2d6e,x
        cmp     #$06            ; (always: $b4 is $06 for every action)
        bne     @out
        lda     #$04            ; Ot6GfxCmdFold
        sta     f:$7e0000+$2d6e,x
@out:   pla
        plx
        plp
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ #554: battle script command $04, a folded strike ]

; btlgfx's GfxCmdTbl entry $04 (vanilla's no-op, never queued) goes to
; Ot6GfxCmdFold (ot6_c1), which jml's here inside ExecGfxCmd's jsr; this
; ends by stepping the gfx data pointer as GfxCmd_06 would (NextGfxCmdData),
; so the pass's data block is consumed without an animation, and returns
; through a C1 rts (GfxCmd_00).  Here: a beat of OT6_FOLD_BEAT frames, the
; earlier strike's numeral having just landed (DmgNumBounceTbl reaches its
; floor at its 23rd frame), then every live numeral thread is retired, so
; this strike's numerals, the commands that follow, do not draw over the
; earlier ones on the same body.  a8/i16 (btlgfx), dp 0.  clobbers a/x.
OT6_FOLD_BEAT = 24

.proc Ot6GfxCmdFold_ext
        .a8
        .i16
        lda     #OT6_FOLD_BEAT
@wait:  pha
        jsl     WaitFrame_far
        pla
        dec     a
        bne     @wait
        ldx     #$0000          ; the four numeral threads: off
@off:   lda     #$00
        sta     f:$7e631a,x     ; w7e631a: enable / green
        sta     f:$7e6322,x     ; w7e6322: frame counter
        inx
        cpx     #$0004
        bne     @off
        jsr_c1  NextGfxCmdData  ; the pass's data block, as GfxCmd_06 steps it
        jml     f:GfxCmd_00     ; a C1 rts: back to ExecGfxCmd's caller
.endproc
