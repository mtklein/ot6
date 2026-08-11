; ------------------------------------------------------------------------------
; OT6: multi-hit hit counts (#54)
;
; A landed hit that matches a weakness chips a shield, so the number of times
; an action strikes is the break-rate dial.  That rule is measured rather than
; assumed: one boosted Fight action swinging eight times chipped four shields
; off one target, 6 -> 5 -> 4 -> 3 -> 2 -> 1, at $3a70 = 7, 5, 3, 1
; (tools/tests/probe_multihit.lua phase 1; the odd counts are the landing hand,
; ot6_boost.asm:220-224).  docs/design/multi-hit.md is the design pass.
;
; The engine has exactly one multi-hit mechanism, $3a70 "number of attacks
; (0 = 1 attack)" (battle_main.asm:6417), consumed by one loop:
;
;       @3288:  plx
;               dec  $3a70
;               bmi  @3291
;               pea  ExecAttack-1       ; battle_main.asm:8338-8339
;
; so an extra count is a whole extra ExecAttack -> CalcTargetDmg pass and
; therefore a whole extra chip opportunity.  Adding to $3a70 is all this
; module does.
;
; Why a keyed table rather than a special effect.  $11a9 holds one byte and
; selects one effect (DoAttackerEffect, battle_main.asm:10310-10317), and five
; of the abilities in scope already spend it (Suplex $30, Retort $3c, Stunner
; $3f, Cleave $23, Empowerer $36), so hit counts cannot be data-authored
; there.  Reusing vanilla's quadra effect $32 would force exactly x4 plus
; random targeting.  A scanned (id, extra) table is the shape ot6 already uses
; for per-ability data (Ot6SkillClassTbl, Ot6AbilityCostTbl).
;
; Why the hook sits in the command handlers rather than in LoadMagicProp.
; multi-hit.md §5 named LoadMagicProp and CalcItemEffect as the candidates and
; flagged both as unchecked for re-entry, which is the dangerous property: a
; hook that runs again inside the multi-attack loop re-arms $3a70 and the
; action never ends.  ExecAttack calls InitTarget itself when $3400 is $ff
; (battle_main.asm:8223-8228), and InitTarget_00/_02 call LoadMagicProp
; (:6625), so LoadMagicProp is reachable from inside the loop and was rejected
; on that basis rather than measured.  Cmd_0a and Cmd_09 cannot be: the
; multi-attack loop re-enters ExecAttack, never the command handler, and
; ExecCmd clears $3a70 through InitGfxScript (:6417) before dispatching, so
; each handler sees a fresh 0 exactly once per action.  That is the same site
; and the same argument as Ot6FightBoost, which lives in FightAttack for the
; same reason.  Measured on the built ROM by tools/tests/battle_hitcount.lua:
; a real Pummel sets $3a70 to 1 once and lands two hits.
;
; SwdTech has no hook because no SwdTech count changes: Quadra Slam and Quadra
; Slice are already x4 through vanilla's effect $32, and Empowerer x2 through
; $36.  Adding one later means adding a jsl to Cmd_07 (battle_main.asm:3970)
; the same way, since $b6 there is likewise the ability id before it is
; rebased.
; ------------------------------------------------------------------------------

.segment "ot6_code"

; ------------------------------------------------------------------------------

; [ ability id -> extra attacks ]

; 2-byte records, $ff-terminated, scanned once per action.  Keyed by attack id
; for Blitz and by tool item id for Tools, the keying Ot6SkillClassTbl and
; Ot6AbilityCostTbl already use; the two ranges are disjoint ($5d-$64 vs
; $a3-$aa) and each caller passes only its own, so one table serves both.
; An absent id is one hit, which is vanilla.
;
; The reasons are in docs/design/multi-hit.md §4; the short form:
;   - pummel: sabin's signature, 4 MP at level 1, the earliest and cheapest
;     repeatable probe in the game.  bludgeoning, which is also his bare
;     fists' class, so it is a second axis only with claws equipped.
;   - bum rush: a capstone, so x4 rather than the x8 kits.md once proposed.
;     x8 empties every authored shield count but one in a single action,
;     which would make the ultimate the opener.  x4 empties trash and the
;     low bosses and still leaves 5-shield bosses needing a second source.
;   - drill: edgar's armour-piercing tool (it ignores defence,
;     ToolsEffect_05, battle_main.asm:7330-7333), so rate into one gauge is
;     the complement to AutoCrossbow's one-hit-per-body breadth.
; AutoCrossbow is deliberately absent: it is breadth, not rate, and x4 per
; body would be 16 chips against a four-stack.

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
