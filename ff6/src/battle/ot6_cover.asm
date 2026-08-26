; ------------------------------------------------------------------------------
; True Knight: a cover pays its blocker a boost point
;
; The third reactive BP earn, built on the Runic template in ot6_boost.asm.
; ------------------------------------------------------------------------------

; Site.  Vanilla's cover lives in CoverEffect (battle_main.asm:2855).  It
; bails three ways before any cover exists: the attack cannot crit ($b2.1,
; :2859), there are no targets ($b8, :2862), or the target is not NEAR FATAL
; or is vanished ($3ee4,y bits $0200 / $0010, :2875-2879).  It then builds the
; candidate mask (every character except the target and the attacker,
; :2882-2889) and walks all ten entities for the True Knight relic bit
; ($3c58,x & $0040, :2891-2893), keeping the highest-hp survivor of
; CheckCoverTarget's presence/status gates in $f2/$f4 (:2931-2953).  Only
; SetCoverTarget (:2911) commits: past its `bmi` (no candidate) and its
; `cpy $f8 / bne` (the original target moved out from under it), it rewrites
; $f8/$a8/$b8 so the attack now lands on the blocker (:2916-2922).  This hook
; sits on the far side of that rewrite, so arriving here means the block has
; already happened, the same way Ot6RunicBP does at RunicEffect's enrolment.
; It re-derives no eligibility of its own.
;
; SetCoverTarget is shared: CoverEffect's first arm (:2870-2873) is Love
; Token, which covers a named ally through $336c and never consults $3c58.
; The relic bit is re-read here on the blocker, so a Love Token bodyguard who
; is not also a True Knight banks nothing; one who is also a True Knight
; banks a point.
;
; economy: the bank cap is Ot6ActionEnd's, untouched, so a cover at 5 bp is
; capped and never mints a sixth pip. The no-regen-after-boost rule does not
; gate this: that rule is a turn's own end-of-action tick, while a cover is
; an out-of-turn reward paid during the attacker's action, whose ActionEnd
; leaves at its `cmp #$08` monster gate without ever reaching the blocker's
; row. Pay is once per round: the first cover each round banks, further
; covers that round protect but do not pay; the latch is cleared in
; Ot6ActionEnd, the same tick that decides the blocker's own regen, and is
; set only when a pip is actually banked.
;
; The pip lands on the damage frame, not this one: this proc arms
; OT6_PIPSLOT/OT6_PIPTAIL right here, but painting defers via OT6_PIPPEND —
; Ot6PipPending (ot6_hud.asm) moves it into the live cell — because what a
; player perceives as "the block" is the hit landing on the blocker, not this
; earlier commit. A missed cover still paints, on the "Miss" frame; see that
; proc for the Ot6ActionEnd backstop.
;
; entry (jsl from SetCoverTarget's commit): a16 (CoverEffect's own width, its
; `php/longa/.../plp` restores the caller's), index width either.  The site
; runs .i8 (CalcAttackEffect), so the body uses no index immediates and no
; pushes, per this file's width discipline.  x = the blocker's entity offset,
; db=$7e.  a clobbered (dead: the caller falls straight into `rts`), x/y kept.
.proc Ot6CoverBP
        php
        shorta0
        .a8
        txa                     ; width-neutral character test
        cmp     #$08
        bcs     done            ; monsters bank no bp
        lda     $3c58,x         ; relic effects 4 (low byte holds bit 6)
        and     #$40            ; true knight; a plain love token pays nothing
        beq     done
        lda     $3018,x         ; this character's bit ($01/$02/$04/$08)
        and     f:$7e0000+OT6_COVERPAID
        bne     done            ; already banked a cover this round
        lda     OT6_BP_CLASS,x
        cmp     #$05
        bcs     done            ; the bank cap holds; a cover never wraps
        inc
        sta     OT6_BP_CLASS,x
        jsr     Ot6BankMoved    ; the knight's bank rose behind whatever
                                ;   window he has open
        lda     $3018,x
        ora     f:$7e0000+OT6_COVERPAID
        sta     f:$7e0000+OT6_COVERPAID  ; latch: paid this round
        txa                     ; defer the pip: the live cell is armed
        lsr                     ;   on the damage-numeral frame, not here
        inc                     ;   slot + 1, 0 = nothing pending
        sta     f:$7e0000+OT6_PIPPEND
done:   plp
        rtl
.endproc
