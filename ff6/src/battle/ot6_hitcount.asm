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
@done:  pla                     ; the ability id, back to the caller
        plx
        plp
        rtl
.endproc
