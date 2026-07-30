; ------------------------------------------------------------------------------
; TRUE KNIGHT -- a cover pays its blocker a boost point (#37)
;
; The third reactive BP earn, built on the Runic template in ot6_boost.asm.
; ------------------------------------------------------------------------------
; Carved out of ot6_kits.asm (v0.9, 3037 lines) with the emission order of
; every instruction preserved: ot6.asm includes these files in exactly the
; order their text sat in the old one, so the assembler sees the identical
; token stream and the linker the identical segment. Proven, not argued --
; ROM CRC32 0x2E9B5A7F and ff6-en.map are byte-identical across the split.
; ------------------------------------------------------------------------------

; ------------------------------------------------------------------------------

; [ a True Knight cover pays its blocker a boost point (#37) ]

; the playtester's idea (@TimRahaim, issue #37), built on the Runic template
; the owner named: one consistent rule for every reactive BP earn.
;
; SITE.  vanilla's cover lives in CoverEffect (battle_main.asm:2855).  It
; bails three ways before any cover exists -- the attack cannot crit ($b2.1,
; :2859), there are no targets ($b8, :2862), the target is not NEAR FATAL or
; is vanished ($3ee4,y bits $0200 / $0010, :2875-2879) -- then builds the
; candidate mask (every character except the target and the attacker,
; :2882-2889) and walks all ten entities for the True Knight relic bit
; ($3c58,x & $0040, :2891-2893), keeping the highest-hp survivor of
; CheckCoverTarget's presence/status gates in $f2/$f4 (:2931-2953).  Only
; SetCoverTarget (:2911) COMMITS: past its `bmi` (no candidate) and its
; `cpy $f8 / bne` (the original target moved out from under it), it rewrites
; $f8/$a8/$b8 so the attack now lands on the blocker (:2916-2922).  This hook
; sits on the far side of that rewrite, so -- exactly like Ot6RunicBP at
; RunicEffect's enrolment -- arriving here IS the block.  It re-derives no
; eligibility of its own.
;
; WHICH relic covered still has to be told apart.  SetCoverTarget is shared:
; CoverEffect's FIRST arm (:2870-2873) is Love Token, which covers a named
; ally through $336c and never consults $3c58.  #37 is about True Knight, so
; the relic bit is re-read here on the BLOCKER.  A Love Token bodyguard who
; is not also a True Knight banks nothing; one who is, banks -- the relic the
; issue is about is the relic that pays.
;
; three economy rulings, the first two Runic's own (ot6_boost.asm):
;   - the bank cap is Ot6ActionEnd's, untouched: a cover at 5 bp is simply
;     capped.  it never wraps and never mints a sixth pip.
;   - the no-regen-after-boost rule does NOT gate this.  that rule is about a
;     turn's own end-of-action tick; a cover is an out-of-turn reward paid
;     during the ATTACKER's action, and the attacker's ActionEnd leaves at its
;     `cmp #$08` monster gate without ever reaching the blocker's row.  so a
;     knight who boosted the turn he raised his guard is still paid for what
;     he eats.
;   - ONCE PER ROUND (the owner's ruling on #37): the first cover each round
;     banks, further covers that round protect but do not pay.  FF6 has no
;     round counter, so the boundary is the one Runic's own machinery implies:
;     Runic pays once per turn Celes SPENDS raising the stance, because
;     RunicEffect consumes $3e4c.2 on the absorb and only her next turn can
;     raise it again.  The cover analogue is the blocker's own turn -- the
;     latch is cleared in Ot6ActionEnd, the same tick that decides his regen.
;     That also makes the cap self-evidently not once-per-battle, and it is
;     the only boundary in an ATB game that is visible to the player (his
;     gauge).  The latch is set only when a pip is actually banked, so a
;     capped-away earn at 5 bp costs nothing (the two are indistinguishable
;     inside a round: nothing else can raise a held character's bank).
;
; THE PIP LANDS ON THE DAMAGE FRAME, NOT THIS ONE (#42).  #37 armed
; OT6_PIPSLOT/OT6_PIPTAIL right here, on the same instruction stream that
; writes OT6_BP_CLASS -- visual event and mechanical event identical by
; construction.  That satisfied #33 as written and not what #33 is for: this
; commit precedes the damage numeral by 83-147 frames (measured,
; battle_trueknight) while the tail is 32, so the pip flashed and faded about
; two seconds before the blow visibly landed on the knight, and what a player
; perceives as "the block" is the hit landing on the blocker.  So the earn
; BANKS here, unchanged, and only the PAINT defers: the blocker's slot goes
; into OT6_PIPPEND and Ot6PipPending (ot6_hud.asm) moves it into the live cell
; off the numeral-counter edge -- #33's own Ot6RvPend*/Ot6RevealCommit shape,
; on #33's own trigger.  A missed cover still paints, on the "Miss" frame; see
; that proc for the ruling and for the Ot6ActionEnd backstop.
;
; entry (jsl from SetCoverTarget's commit): a16 (CoverEffect's own width, its
; `php/longa/.../plp` restores the caller's), index width EITHER -- the site
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
        and     #$40            ; true knight -- a plain love token pays nothing
        beq     done
        lda     $3018,x         ; this character's bit ($01/$02/$04/$08)
        and     f:$7e0000+OT6_COVERPAID
        bne     done            ; already banked a cover this round
        lda     OT6_BP_CLASS,x
        cmp     #$05
        bcs     done            ; the bank cap holds; a cover never wraps
        inc
        sta     OT6_BP_CLASS,x
        lda     $3018,x
        ora     f:$7e0000+OT6_COVERPAID
        sta     f:$7e0000+OT6_COVERPAID  ; latch: paid this round
        txa                     ; #42: DEFER the pip.  the live cell is armed
        lsr                     ;   on the damage-numeral frame, not here --
        inc                     ;   slot + 1, 0 = nothing pending
        sta     f:$7e0000+OT6_PIPPEND
done:   plp
        rtl
.endproc
