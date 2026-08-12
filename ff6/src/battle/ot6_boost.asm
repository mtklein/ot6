; ------------------------------------------------------------------------------

; [ seed boost points at battle start ]

; called from InitBattle after its ram clears. runs in longa/longi
; context (InitBattle's php/longai is still active) - widths pinned here.

.proc Ot6InitBP
        .a16
        .i16
        php
        shorta0
        ; consume the random-encounter marker: the field trigger set
        ; OT6_RANDPEND (to the magic value) just before this battle
        ; started; latch a normalized 0/1 as this battle's flag and clear
        ; the marker, so event battles (which never pass the trigger)
        ; always read a stale-proof 0. the magic compare rejects pre-
        ; first-battle ram junk on playlines that never took a danger-
        ; checked step (probe_57ba_strip caught $ff riding the srm boot).
        lda     f:$7e0000+OT6_RANDPEND
        cmp     #OT6_RANDMAGIC
        beq     @mark
        lda     #$00
        bra     @latch
@mark:  lda     #$01
@latch: sta     f:$7e0000+OT6_RANDBTL
        lda     #$00
        sta     f:$7e0000+OT6_RANDPEND
        sta     f:$7e0000+OT6_HUDVEIL   ; a stale veil never survives init
        sta     f:$7e0000+OT6_SCRIPTBUSY ; nor a stuck anchor-adopt gate
        sta     f:$7e0000+OT6_PIPTAIL   ; nor a stale pip-paint tail (#33)
        sta     f:$7e0000+OT6_COVERPAID ; nor a stale cover-earn latch (#37):
                                ;   it sits past the shadow clear below, and a
                                ;   stale bit would eat the first cover of the
                                ;   battle instead of costing a no-op
        sta     f:$7e0000+OT6_PIPPEND   ; nor a deferred pip paint (#42): it
                                ;   also sits past the clear, and a stale slot
                                ;   would paint a spurious pip on the first
                                ;   damage numeral of the next battle
        sta     f:$7e0000+OT6_RUNICPAID ; nor a stale runic-earn latch (#59):
                                ;   like #37's, a stale bit here suppresses a
                                ;   real earn rather than costing a no-op
        sta     f:$7e0000+OT6_RUNICTURNS      ; #59: nor a standing Runic
        sta     f:$7e0000+OT6_RUNICTURNS+2    ;   nobody raised.  four explicit
        sta     f:$7e0000+OT6_RUNICTURNS+4    ;   stores rather than a loop;
        sta     f:$7e0000+OT6_RUNICTURNS+6    ;   only the character offsets
                                ;   (0/2/4/6) are ever read, and a stale byte
                                ;   would give the next battle's Celes a
                                ;   standing magic shield she never paid for
        lda     #$01
        sta     OT6_BP_CLASS           ; characters open with 1 bp, octopath-style
        sta     $3e9e
        sta     $3ea0
        sta     $3ea2
        ; clear the bg-hud shadow (prev addresses especially: garbage here
        ; would make the first flush erase random vram)
        longa
        clr_a
        phx
        ldx     #$0000
@clr:   sta     f:$7e0000+OT6_SHADOW,x
        inx
        inx
        cpx     #$0070          ; $54 = the six shadow lines, then the tail:
                                ;   +$18 reveal-pending (#33: stale pending
                                ;   would commit last battle's reveals onto
                                ;   this battle's species) and +$04 wallet
                                ;   cur/prev (#35: stale words would blank/
                                ;   paint random menu-map cells)
        bcc     @clr
                                ; the shadow now lives at $ecf1, so it is no
                                ; longer contiguous with MAPBASE/ATKCLASS/
                                ; FONTDIRTY and this second loop is required;
                                ; one loop over $58 used to cover both.
        ldx     #$0000
@clr2:  sta     f:$7e0000+OT6_MAPBASE,x
        inx
        inx
        cpx     #$0004          ; $57b6-$57b9: map base, atkclass, fontdirty
        bcc     @clr2           ;   stops at $57ba: the $57ba-$57bf strip
                                ;   (spare word + random-encounter flags)
                                ;   must survive init (see the strip's
                                ;   block comment at OT6_RANDPEND)
        ; (removed: an 84-byte clear loop over OT6_HUDCOPY, a retired
        ;  feature's buffer. $57de is inside vanilla's `ram_res w7e57d5,
        ;  128`, so the loop was zeroing vanilla's name/banner scratch at
        ;  every battle init for nothing. Nothing reads OT6_HUDCOPY.)
                                ; (the old single-cell pip pseudo-line's
                                ;  PIPCUR/PIPPREV clears are gone with it;
                                ;  #33 moved the live pips to OT6_PIPROWS,
                                ;  gated by OT6_PIPTAIL/$7bca, and the wallet
                                ;  cur/prev ride the @clr loop above)
        sta     f:$7e0000+OT6_LASTLR
        sta     f:$7e0000+OT6_RESTAGE   ; word store: the high byte lands on
                                        ;   vanilla's $57d5 name scratch,
                                        ;   harmless at init (vanilla always
                                        ;   writes it before reading)
        plx                             ; (OT6_ATKCLASS and OT6_FONTDIRTY sit
                                        ;   in the shadow strip: the @clr
                                        ;   loop covered them)
        plp
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ #77: a character's BP bank moved; repaint the list that is drawing it ]

; An open ability list derives what it draws from the bank at the moment its
; rows are staged, and nothing re-stages them: Ot6BushidoRowGrey greys a kit
; row whose boost exceeds the caster's bank (ot6_cmdmenu.asm:385), so a bank
; that moved behind an open window left the window claiming a row was
; reachable when Ot6BushidoConfirm would refuse it, or greyed when it would
; not.  Every writer of a character's bank calls this: Ot6ActionEnd's charge
; arm and its regen arm, Ot6RunicBP, Ot6CoverBP, Ot6Filch and Ot6Bestow.
; Ot6InitBP does not, deliberately -- no menu is open at battle init.
;
; The request byte and the gate that spends it are #64's (OT6_RESTAGE,
; Ot6RestageGate_ext in ot6_hud.asm).  Detection sits here, at the writers,
; rather than as a change detector in the gate, because the gate is polled
; once per battle frame and none of these writers is per-frame code.
;
; THE MENU-STATE TEST IS NOT AN OPTIMISATION, and neither is its narrowness.
; It was measured, and it fixes a regression the unconditional version had:
;
;   battle_levelup (six earned world encounters, same savestate)
;     pre-change ..................................... pass
;     request raised for the magic list as well ...... fail
;     request raised only for the kit window ......... pass
;
; The magic list ($0e) does not read the BP bank at all: its
; greys are Ot6AbilityGrey's MP test and its prices are Ot6FoldPrices' fold of
; the caster's own PENDING boost, which #64 already requests from Ot6Boost at
; the L/R edge.  Raising a request for it here re-staged four rows under the
; player's cursor every time anyone's bank moved, which is work with no
; content change behind it, and it moved battle_levelup off its outcome.  So
; the test is for $30 and nothing else.
;
; The narrowing costs no coverage: the only reader of the bank that can be
; stale is a kit window whose rows are already staged, which is exactly the
; state being tested for.  A kit window still opening ($2e) stages from the
; live bank on its own.
;
; It used to carry a second reason, and that reason has moved (#87).  Raising
; unconditionally also read 1798 on battle_trueknight phase 4b, the frame
; budget canary, because the gate's old @wait arm HELD a fresh request that no
; open window could consume and so ran its long path on every battle frame.
; That was the gate's defect rather than this proc's, it was reachable from
; the pad without any of these writers (press R at the command window), and it
; is fixed in the gate: the request is dropped now, and the same unconditional
; build reads 1635.  So this test survives on the battle_levelup measurement
; alone.  Do not widen it back on the strength of the frame budget being
; fixed; widening it re-staged four rows under the player's cursor for a value
; those rows do not draw.
;
; entry: jsr from bank F0, a8, index width either (no index addressing and no
; pushes, so it is callable from Ot6CoverBP and Ot6RunicBP under their .i8
; sites).  Reads long, so it does not care what db the caller runs under.
; Clobbers A, which is dead at every call site.

.proc Ot6BankMoved
        .a8
        lda     f:$7e0000+$7bca ; a battle menu open at all?
        beq     @no
        lda     f:$7e0000+$7bc2 ; ...and is it the kit window, up and
        cmp     #$30            ;   browsing?  ($30 = the tools shell: Tools,
        bne     @no             ;   Blitz, SwdTech, Steal)
        lda     #$80            ; the gate's "fresh request" value
        sta     f:$7e0000+OT6_RESTAGE
@no:    rts
.endproc

; ------------------------------------------------------------------------------

; [ bp bookkeeping at the end of an entity's action ]

; called just before EndAction once the actor has no pending actions.
; characters: consume the pending boost if one was spent, otherwise
; gain 1 bp (octopath's no-regen-after-boosting rule), capped at 5.
; a8/i16, x = actor entity offset, a free

.proc Ot6ActionEnd
        php                     ; caller width varies: pin our own
        longi
        shorta0
        .a8
        .i16
        jsr     Ot6RevealCommit ; #33: any reveal this action banked and no
                                ;   numeral displayed (a 0-damage or
                                ;   numeral-less script) commits no later
                                ;   than the action's own end
        txa                     ; width-neutral character test
        cmp     #$08
        bcs     done            ; monsters have no bp
        txa                     ; #33: the live pip cell follows this actor
        lsr                     ;   entity offset -> character slot
        sta     f:$7e0000+OT6_PIPSLOT
        lda     #32             ;   for ~half a second past this charge, so
        sta     f:$7e0000+OT6_PIPTAIL   ;   the drop lands on screen even
                                ;   when no battle menu is open at resolution
        lda     $3018,x         ; #37: the round boundary for the True Knight
        eor     #$ff            ;   cover earn.  this actor's turn is ending,
        and     f:$7e0000+OT6_COVERPAID  ;   so his next cover pays again:
        sta     f:$7e0000+OT6_COVERPAID  ;   the same tick that decides his
                                ;   regen also re-arms his reaction (the
                                ;   boundary Runic's own machinery implies;
                                ;   see Ot6CoverBP, ot6_cover.asm)
        lda     $3018,x         ; #59: and the same boundary for Runic's own
        eor     #$ff            ;   absorb earn, which needed one the moment
        and     f:$7e0000+OT6_RUNICPAID  ;   boost gave the stance a duration.
        sta     f:$7e0000+OT6_RUNICPAID  ;   Until v0.9 the cap was implicit:
                                ;   RunicEffect ate the stance on the first
                                ;   absorb, so one raise could only pay
                                ;   once.  An extended stance absorbs many
                                ;   times, and #37 (itself mirrored from
                                ;   Runic) already settled what to do.
                                ;   Separate ledger from COVERPAID on purpose:
                                ;   see OT6_RUNICPAID in ot6_memory.inc.
        lda     OT6_BOOST_REVEALED,x         ; pending boost spent this action?
        beq     @gain
        sta     OT6_SCR_BIT     ; consume it: bp -= pending
        lda     OT6_BP_CLASS,x
        sec
        sbc     OT6_SCR_BIT
        bcs     :+
        lda     #$00            ; (defensive clamp)
:       sta     OT6_BP_CLASS,x
        lda     #$00
        sta     OT6_BOOST_REVEALED,x         ; no regen on a boosted turn
        ; #64: the pending is gone, so this caster's magic rows must fall back
        ; off the folded prices Ot6FoldPrices put on them.  Same request bit
        ; Ot6Boost sets when the boost goes up (ot6_hud.asm); the walk is
        ; self-restoring at 0 tier steps, so this is the whole fallback.
        ; Placed on the spend arm only: @gain never changed a price.
        lda     $3204,x
        ora     #$80            ; vanilla's "recheck enabled magic" request
        sta     $3204,x
        jsr     Ot6BankMoved    ; #77: and the bank moved, so an open kit
                                ;   window's BP grey is stale
        bra     done
@gain:  lda     OT6_BP_CLASS,x
        cmp     #$05
        bcs     done            ; capped at 5
        inc
        sta     OT6_BP_CLASS,x
        jsr     Ot6BankMoved    ; #77: same on the regen arm.  the two arms
                                ;   are marked separately, and not at `done`,
                                ;   because `done` is also where a monster and
                                ;   a capped-away regen leave, neither of which
                                ;   moved a bank
        ; #42: the backstop for a deferred cover pip.  Reached by every actor,
        ; monsters included (they are the ones whose swings a knight covers),
        ; and placed after the charge arm above so a pending cover takes the one
        ; live cell; the actor's own bank restages at the next window open, and
        ; a cover earn has no other moment.  Normally a no-op: the numeral
        ; frame already consumed the pending value.  It fires when the action
        ; issued no numeral at all, or a $ffff "hide numerals" one, the same
        ; hole Ot6RevealCommit is called at the top of this proc to plug.
done:   jsr     Ot6PipPending
        plp
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ a runic absorb pays its rune knight a boost point ]

; called from RunicEffect's per-entity loop (battle_main.asm:8508) at the
; one instruction where the absorb is already certain. vanilla walks all
; ten entities there and drops out three ways before that point: target
; not present ($3aa0.0, :8494), no runic stance at all ($3e4c.1|.2,
; :8497), and a CheckStatus gate that discards a dead / petrified /
; asleep / stopped / frozen / hidden runic-er (:8500-8503). only a
; survivor of all three reaches the `tsb $ee` that enrolls it in the
; absorbing set (:8506), and $ee is what the routine then
; retargets its mp-restore onto (:8517-8523). so this hook re-derives no
; eligibility of its own: arriving here means the absorb has happened.
;
; Which stance ate it still has to be told apart. vanilla cleared bit 2
; (the Runic command's own bit, set by Cmd_0b at :4081-4083) four
; instructions up at :8498, but deliberately left bit 1, "enemy runic",
; seeded from MonsterProp+30 at :7421. that seed does reach a character
; entity, because the same monster-property loader runs for Gau's Rage
; (Ot6SeedShields guards the same case, in this file). bit 1 still set
; here therefore means this entity ate the spell as a raging monster
; rather than as a rune knight, and it banks nothing.
;
; three economy rulings, all deliberate:
;   - the bank cap is Ot6ActionEnd's, untouched: an absorb at 5 bp is
;     capped. it never wraps, and it never mints a sixth pip that
;     Ot6Boost's `cmp OT6_BP_CLASS` would then let her spend.
;   - the no-regen-after-boost rule does not gate this. that rule
;     (Ot6ActionEnd) is about a turn's own end-of-action tick; an absorb
;     is an out-of-turn reward paid during the caster's action, and the
;     caster's own ActionEnd leaves at its `cmp #$08` monster gate
;     (:1620) without ever reaching her row. so a Celes who boosted the
;     turn she raised Runic is still paid for what she catches: the
;     stance costs her the turn either way, and charging it twice would
;     make boosting into Runic worse than not boosting.
;   - once per round (#59), added when boost gave the stance a duration.
;     See below; it is #37's ruling applied back to Runic.
;
; ---- #59: what an extended stance does to the economy ----
;
; Until v0.9 this proc needed no cap because RunicEffect's own machinery
; was one: it clears $3e4c.2 at :8671 on the first absorbable spell, so a
; single raise could only pay once.  #37 read that as a rule and
; mirrored it into the True Knight cover as an explicit once-per-round
; latch.  Boost-as-duration removes the implicit version, so #37's
; explicit one is applied back to the verb it was copied from.
;
; Measured, per Celes turn, with the earn capped at one per round:
;
;   raise turn   -3 bp (the spend), +0 regen (no-regen-after-boost), +1
;                if anything absorbable lands before her next turn
;   each of the 3 stance turns   +1 regen, +1 absorb  = +2
;   ----------------------------------------------------------------
;   4 turns, 3 actions taken:  -3 +1 +2 +2 +2  =  +4 bp
;   4 turns of anything else, 4 actions taken:      +4 bp
;
; So a 3-BP Runic is BP-neutral by construction, and what it
; costs is one action.  That is the ruling: boost buys three turns
; of standing magic shield for a turn of tempo, not for free BP.
;
; Without the cap it is a self-funding loop.  The
; earn is per absorb, and RunicEffect pays every absorbing entity on
; every absorbable cast, so three enemy casters against a three-turn
; stance is up to nine earns against a three-point spend.  Bank cap 5
; bounds the stock but not the flow: she spends three and they come
; straight back, which makes boosting free for the rest of the fight in
; the fights the ability is for.  Measured A/B in
; battle_runic.lua's "milked" phase: four absorbable casts into one round
; of a standing 3-turn stance bank +1 with this latch and +2 on a control
; build with it nop'd out.  +2 and not +4 because that fixture has one
; caster and the count is of casts resolved rather than absorb events.
; The finding is the direction: uncapped the
; earn scales with absorbs, and capped it does not scale at all.
;
; The third option #59 lists (per absorb, unscaled, justified by
; casters being rare) is the one the measurement rules out: they are not
; rare in the fights this stance is bought for, which means the ability
; would tune itself off.
;
; a8 (vanilla's `shorta` is the instruction immediately before), index
; width either: no index immediates and no pushes, per this file's
; width discipline; RunicEffect itself runs .i8. y = the absorbing
; entity's offset, a clobbered (dead: the loop reloads at :8492).

.proc Ot6RunicBP
        .a8
        tya                     ; width-neutral character test
        cmp     #$08
        bcs     done            ; monsters bank no bp and hold no duration
        lda     $3e4c,y
        and     #$02            ; survived as enemy runic: a raging gau
        bne     done            ;   ate it, not a rune knight
        ; #59: the stance outlives the absorb while its duration runs.
        ; RunicEffect cleared $3e4c.2 four instructions after it decided
        ; this entity was absorbing (:8670-8671) and before the status gate
        ; that let it through; putting the bit back here, past every gate
        ; and on the far side of the enrolment, extends the stance without
        ; re-deriving one byte of vanilla's eligibility.
        ;
        ; db-relative rather than long here because the 65816 has no `lda
        ; long,y`, only long,x.  That is safe at this site: the two
        ; instructions above are vanilla's own `lda $3e4c,y`
        ; and this proc has always depended on db = $7e for them.
        lda     OT6_RUNICTURNS,y
        beq     @earn           ; 0 = vanilla Runic: one absorb, then gone
        lda     $3e4c,y
        ora     #$04
        sta     $3e4c,y
@earn:  lda     $3018,y         ; this character's bit ($01/$02/$04/$08)
        and     f:$7e0000+OT6_RUNICPAID
        bne     done            ; already banked an absorb this round (#59)
        lda     OT6_BP_CLASS,y
        cmp     #$05
        bcs     done            ; the bank cap holds; an absorb never wraps
        inc
        sta     OT6_BP_CLASS,y
        lda     $3018,y         ; latch: paid this round.  set only when a pip
        ora     f:$7e0000+OT6_RUNICPAID  ;   was really banked, so a capped-away
        sta     f:$7e0000+OT6_RUNICPAID  ;   earn at 5 bp costs nothing.  #37's
                                ;   own argument still holds: inside one
                                ;   round nothing but her own action can lower
                                ;   a held character's bank, and that action is
                                ;   the boundary that clears this latch
        jsr     Ot6BankMoved    ; #77: an absorb is the reactive case the
                                ;   kit window could not see -- Celes's bank
                                ;   rises with her own window open and nothing
                                ;   else happening
done:   rtl
.endproc

; ------------------------------------------------------------------------------

; [ #59: boost buys Runic a duration, the raise ]
;
; The canon rule this ships: on reactive verbs, boost buys duration.
; Damage verbs multiply and chance verbs buy certainty (DESIGN.md); Runic
; is neither, which is why it sat outside the canon from v0.3 until now.
; It is the reactive reading of one DESIGN.md already had, "Buffs/debuffs:
; duration per BP".
;
; Boost N (1-3) = the stance stands for N of Celes's own turns beyond the
; one that raised it, and she acts freely on every one of them.
;
; "She still acts" and "it lasts longer" are the same lever, which is the
; one place #59's proposal does not survive contact with the code.  The
; issue offers them as separable tiers: 1 BP buys the free turns, and 2-3
; buy duration.  They cannot be separated: vanilla ends the stance in
; QueueAction (battle_main.asm:511) because she acted, so the
; only way she can act without dropping it is for the stance to outlive
; her action, which is duration.  So the ladder is 1/2/3 turns of
; shield she can act through, and there is no tier that buys only one of
; the two.
;
; entry (jsl from Cmd_0b, immediately after its `ora #$04 / sta $3e4c,x`
; sets the stance): a8/i8 (command context), x = the actor's entity
; offset, db=$7e.  width-agnostic body: no index immediates, no pushes.
; a clobbered (dead: Cmd_0b falls into `jsr _c2298a`).
.proc Ot6RunicRaise
        .a8
        txa                     ; width-neutral character test (Cmd_0b's own
        cmp     #$08            ;   `tyx` put the actor here)
        bcs     done            ; monsters hold no duration
        lda     OT6_BOOST_REVEALED,x   ; pending boost = turns of stance
        cmp     #$04
        bcc     :+
        lda     #$03            ; (defensive: Ot6Boost already caps at 3)
:       sta     f:$7e0000+OT6_RUNICTURNS,x
done:   rtl
.endproc

; ------------------------------------------------------------------------------

; [ #59: boost buys Runic a duration, surviving her own turn ]
;
; QueueAction clears the runic and retort bits on every action any entity
; queues (battle_main.asm:511-513, `and #$fa`), which is what makes vanilla
; Runic cost the turn it protects: raise it, and your next turn ends it.
; This hook runs immediately after that clear and puts the runic bit back
; while the duration lasts, spending one turn of it each time.
;
; It runs after vanilla's clear rather than replacing it: the retort
; bit ($3e4c.0) is cleared by the same instruction and has nothing to do
; with #59, so leaving vanilla's three instructions alone and re-setting
; one bit is both smaller (4 bytes against 8) and harder to get wrong.
;
; The decrement happens here, at the moment she takes a turn, so the
; counter measures what the player is promised: turns she gets to
; act under the shield.  With N latched, her Nth post-raise turn still
; restores the stance (the store goes to 0 but the bit goes back), and her
; N+1th finds 0 and lets vanilla's clear stand.  A monster's QueueAction
; falls out at the character test, and an unboosted Runic reads 0 and is
; untouched, vanilla to the byte.
;
; entry (jsl from QueueAction, right after its `sta $3e4c,x`): x = the
; queueing entity's offset, db=$7e.  a8 and width-agnostic; a clobbered
; (QueueAction reloads at :514).
.proc Ot6RunicHold
        .a8
        txa                     ; width-neutral character test
        cmp     #$08
        bcs     done            ; monsters hold no duration
        lda     f:$7e0000+OT6_RUNICTURNS,x
        beq     done            ; no extended stance: vanilla's clear stands
        dec
        sta     f:$7e0000+OT6_RUNICTURNS,x   ; one turn of shield spent
        lda     $3e4c,x
        ora     #$04            ; ...and the stance survives her acting
        sta     $3e4c,x
done:   rtl
.endproc

; ------------------------------------------------------------------------------

; [ extra swings for a boosted fight ]

; called from FightAttack right after the vanilla swing count lands in
; $3a70 (1, or 7 with offering). swings alternate hands and empty-hand
; swings whiff, so +2 swings per pending bp = +1 real hit for a
; one-weapon character, and a genji-glove pair swings both hands
; again, doubling the bonus as it doubles everything else.
; a8/i16, x = attacker entity offset.

.proc Ot6FightBoost
        .a8
        .i16
        txa                     ; width-neutral character test
        cmp     #$08
        bcs     done            ; monsters never boost
        lda     $b1             ; counterattacks never boost: they execute
        lsr                     ;   through ExecRetal, which sets $b1.0
        bcs     done            ;   (battle_main.asm:12435) and ends at an
                                ;   unhooked EndAction, so the pending
                                ;   would be delivered but never charged.
                                ;   a black belt counter with pending 3
                                ;   measured 7 swings at no cost
                                ;   (probe_ctrboost).
        lda     OT6_BOOST_REVEALED,x         ; pending boost level
        beq     done
        asl                     ; two swings per bp
        clc
        adc     $3a70
        sta     $3a70
done:   rtl
.endproc

; ------------------------------------------------------------------------------

; [ fold a boosted spell to its higher tier, at action-queue time ]

; called from CreateAction after GetMPCost banked the BASE spell's mp
; into $3620 and just before $3a7a (command | attack << 8) is written
; into the queue. a boosted character's tiered spell is queued as its
; -ra/-ga tier: every execution path then uses the higher tier's own
; record for name, animation, and power. pending 1 = one tier up, 2-3 =
; two. x = the actor's entity offset (CreateAction's own indexing),
; y = the queue slot (already doubled). preserves a/x/y.
;
; ---- #64: the folded tier is also priced as that tier (v0.9) ----
;
; It used to be "bp stays the only price": GetMPCost runs four instructions
; before this hook (battle_main.asm:13245) and banks the cost of whatever
; $3a7b held at that point (the base spell) into $3620,y at :13249.  The fold
; then rewrote $3a7b behind it, so 2 BP bought a Fire 3 (51 MP of spell)
; for Fire's 4.  Boost was a discount on the magic list: the folded
; cast beat three separate casts on both axes, fewer turns and less MP.
;
; @vanorasc's correction (issue #64), and the line it draws:
;
;     BP buys tempo.  MP buys power.
;
; One Fire 3 instead of three Fires still saves two turns, which is what
; the boost is for; the magnitude is paid for in full.  Same correction
; #45 made to the kit ladders, where a discount had outlived its reasoning.
;
; So the fold re-prices what it queued, from the tier's own MagicProp
; record and through the same relic arithmetic the learned path uses
; (Ot6SpellMP below).  This is the authoritative charge and it cannot
; race: it happens at queue time, on the same A the queue consumed, so it
; does not depend on any menu-side recheck having run first.
; Ot6FoldPrices keeps the displayed price agreeing with it.
;
; ---- #91: "it cannot race" was not true of the counterattack guard ----
;
; The paragraph above says the charge does not depend on any menu-side
; recheck having run first.  That held for the fold arm and not for the
; guard.  GetMPCost's character arm reads the caster's spell-list cost byte
; (battle_main.asm:13296), which is the byte Ot6FoldPrices already moved to
; the folded tier's price when the boost went up, so by the time this proc
; runs $3620,y is ALREADY the folded price.  Any early-out here therefore
; leaves the folded price standing on an unfolded spell.
;
; The guard's old test was $b1.0, "a counterattack is executing".  That flag
; is global: ExecRetal sets it for its whole run (:12676), and the
; immediate-action path sets it too (:5806), while UpdateBattleTime ->
; GetPlayerAction -> CreateNormalAction (:2697, :12919) runs from the
; battle-graphics frame wait, including the waits inside those.  So an
; ordinary menu action that happened to be drained during someone else's
; counterattack took the counter's early-out: base Fire cast, Fire 2's 20 MP
; charged.  Measured
; 2026-08-11 on worldmap_narshe: at the queue write $b1 = $01 while every
; character's $32cd read $ff, so no counterattack was pending for anyone --
; the flag alone cannot tell whose action is being queued.  It is timing,
; not menu position: a boost pressed at the target cursor reproduced it
; identically once it landed in the same frame window, which is why
; battle_lateboost (whose cast is a second turn) never saw it.
;
; What the narrowed test still misses: a SECOND counterattack queued for one
; actor while the first is pending chains onto the command list without
; CreateRetalAction updating $32cd,x (:13206-13211), so its pointer will not
; match and it would fold.  Left alone deliberately.  Monsters are already
; excluded below, and a character's counterattack does not reach this proc's
; command test -- it has to be command $02/$17/$0c on a tier-family head --
; so the case has no known reachable instance.
;
; Untaught tiers still fold, and that is now a decision rather than an
; inheritance.  Folding is source-agnostic (design/magicite.md): a borrowed
; Fire folds to Fire 3 whether or not the caster ever learned Fire 3, and
; that is kept, because reaching a tier you have not learned is what
; lets every spell list stay at 8 (DESIGN.md).  What changes is that it is
; now paid for.  The arithmetic had to come from
; MagicProp rather than the caster's own list for that reason: an
; unlearned row's list cost is 0 (AddToSpellList_01, battle_main.asm:14553,
; `clr_a / sta ($f4),y`), so pricing the fold off the list would have
; made every untaught tier free, which is worse than the bug.

.proc Ot6QueueFold
        .a8
        php                     ; caller widths vary: pin our own
        longi
        .i16
        pha
        ; A counterattack must not fold: no ActionEnd ever charges what a
        ; counter queues (ai counter scripts, a raged gau's, route through
        ; CreateAction), so its fold would be free.  The test is whether THIS
        ; action is the counterattack, not whether one is running -- see the
        ; header's #91 paragraph.  y/2 is the command-list pointer this call
        ; is queueing, and CreateRetalAction has already written that pointer
        ; to the actor's counterattack slot $32cd,x (battle_main.asm:13211);
        ; CreateNormalAction writes $32cc,x instead (:13228), so the two
        ; never match for an ordinary action.
        lda     $b1             ; is a counterattack executing at all?
        lsr                     ;   ($b1.0, set by ExecRetal, :12676)
        bcc     @cmd            ; no: nothing to disambiguate
        tya                     ; the queue slot, pointer * 2
        lsr                     ;   -> the pointer just queued
        cmp     $32cd,x         ; the actor's pending counterattack pointer
        beq     @keep           ;   the same: this action IS the counter
@cmd:   lda     $3a7a           ; command
        cmp     #$02
        beq     @cmdok          ; $02 magic
        cmp     #$17
        beq     @cmdok          ; $17 x-magic
        cmp     #$0c
        bne     @keep           ; $0c lore
@cmdok: txa                     ; width-neutral character test
        cmp     #$08
        bcs     @keep           ; monsters never boost
        jsl     Ot6FoldSteps    ; pending boost -> OT6_SCR_BIT tier steps
        beq     @keep           ; unboosted: nothing to fold or re-price
        lda     $3a7b           ; attack id
        jsl     Ot6FoldTier     ; -> the tier this boost buys
        cmp     $3a7b
        beq     @keep           ; not a tier family: id came back unchanged
        sta     $3a7b           ; queue the folded tier
        jsl     Ot6SpellMP      ; #64: and price it as that tier.  x is still
        sta     $3620,y         ;   the actor, y still the queue slot, so this
                                ;   overwrites the base cost :13249 just banked
@keep:  pla
        plp
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ how many tiers does this character's pending boost buy? ]
;
; the 0/1/2 clamp, in one place instead of the three copies that used to
; carry it (queue-time fold, list preview, and now the price walk).  the cap
; is two tiers because that is where every family's table runs out: Fire 3
; is the top of the deepest line, and the shallow families (Poison, Life,
; Slow, Haste) repeat their second entry so a 3-BP spend is never dead.
;
; in: x = the character's entity offset.  out: A = OT6_SCR_BIT = tier steps
; (0-2), Z set when the character has no boost pending.  a8, db=$7e;
; preserves x/y.
.proc Ot6FoldSteps
        .a8
        lda     OT6_BOOST_REVEALED,x
        beq     @out
        cmp     #$02
        bcc     @out
        lda     #$02            ; at most two tiers up
@out:   sta     OT6_SCR_BIT     ; tier steps
        lda     OT6_SCR_BIT     ; re-load so Z reflects the value, not a leftover
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ fold one spell id up the tier table: the one authority for the fold ]
;
; the table scan, factored out of the three places that had grown their own
; copy: Ot6QueueFold (the charge and the cast), Ot6PreviewList_ext (the name
; the player reads) and Ot6FoldPrices (the number and the grey).  Those three
; must agree on which tier a boost buys, or the list will disagree with the
; cast, so there is one scan and they all call it.
;
; only a family head folds: the scan steps 3 and compares the base column
; only.  a Fire 2 the caster has learned is not a head, so casting it
; boosted does not fold again; boost reaches up from the base spell and does
; not stack on a tier the caster already owns.
;
; in: A = spell id, OT6_SCR_BIT = tier steps (Ot6FoldSteps').  out: A = the
; folded id, or the input unchanged when the id is not a family head.
; a8/i16, db=$7e; preserves x/y.
.proc Ot6FoldTier
        .a8
        .i16
        phx
        pha                     ; the base id, matched against each family head
        ldx     #$0000
@row:   lda     f:Ot6FoldTbl,x
        cmp     $01,s
        beq     @hit
        inx
        inx
        inx                     ; stride 3: [base, +1 tier, +2 tiers]
        cpx     #$0018          ; 8 families
        bcc     @row
        pla                     ; not a tier family: hand the id back unchanged
        plx
        rtl
@hit:   txa                     ; row offset (< $18, fits 8 bits)
        clc
        adc     OT6_SCR_BIT
        longa
        and     #$00ff
        tax
        shorta0
        lda     f:Ot6FoldTbl,x
        sta     $01,s
        pla
        plx
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ what one spell costs this caster: the fold's price authority ]
;
; #64.  Deliberately re-derived from MagicProp rather than read out of the
; caster's own spell list, because the fold reaches tiers the caster has not
; learned and an unlearned row's list cost is 0 (see Ot6QueueFold's header).
;
; It is nonetheless the same number the learned path produces, by
; construction: ValidateSpellList seeds each row from `MagicProp+5`
; (_c25723, battle_main.asm:14575-14584) and then applies CalcMPCost
; (:14595) to it, and the relic arithmetic below is CalcMPCost's, in
; CalcMPCost's order, with Economizer taking priority over the Gold Hairpin
; as vanilla's fall-through does.  The relic byte is read from
; $3c45,x, which is where ValidateSpellList itself gets the $f8 it feeds
; CalcMPCost (:14481).  So a caster who has learned Fire 3 and one who
; only folds into it pay the same, and neither can disagree with the
; number the list draws.
;
; (Inlining the two relic bits instead of calling CalcMPCost is not an
; optimisation: CalcMPCost takes its relic byte in the direct-page cell
; $f8, and $f8 at CreateAction time belongs to whoever is mid-action, not
; to battle init.  Six bytes of arithmetic beats clobbering that.)
;
; in: A = spell id, x = the caster's entity offset.  out: A = MP cost.
; a8/i16, db=$7e; preserves x/y.  Every folded tier in the shipped table
; fits a byte with room to spare; the most expensive is Life 2 at 60, and
; tools/tests/battle_foldcost.lua asserts the whole table against the 99
; display ceiling (#57) so a future retune cannot cross it unnoticed.
.proc Ot6SpellMP
        .a8
        .i16
        phx                     ; the caller's entity offset
        longa
        and     #$00ff          ; spell id
        pha                     ; parked at $01,s for the stride multiply
        asl3                    ; id * 8
        sec
        sbc     $01,s           ; id * 7
        asl                     ; id * 14 -- MagicProp's record stride
        tax
        pla                     ; drop the parked id
        shorta0
        lda     f:MagicProp+5,x ; the tier's own cost, straight from the table
        plx                     ; the caller's entity offset back
        pha                     ; ...and the raw cost parked
        lda     $3c45,x         ; relic effects 2, CalcMPCost's own input
        bit     #$40
        bne     @econ           ; economizer: 1, and it beats the hairpin
        bit     #$20
        beq     @out            ; no gold hairpin: the table cost stands
        pla
        inc                     ; gold hairpin: (cost + 1) / 2
        lsr
        rtl
@econ:  pla                     ; drop the raw cost
        lda     #$01
        rtl
@out:   pla
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ boost preview in ability lists ]

; replaces ListTextCmd_0f's `lda ($4f) / sta $2c` (exactly four bytes).
; while the active character has boost pending, tiered spells render
; under their folded name: browsing Fire with two boosts pending shows
; "Fire 3" before the choice is made. $2c is render-scoped (name and our
; element icon). a mid-list R/L press repaints through Ot6Boost's
; OT6_RESTAGE request (ot6_hud.asm), so the name tracks live.
;
; #64 changed what the rest of the row says. This used to note that "cost
; display and selectability stay on the base spell", which was true and
; was the mismatch #64 names: the row read "Fire 3" beside Fire's 4
; MP, and the confirm accepted it however little MP the caster had. The
; price, the grey and the confirm gate now follow the folded tier too;
; Ot6FoldPrices below moves the one byte all three of them read. This proc
; owns only the name.
;
; a8/i16, db=$7e, d=0; preserves x/y and b.

.proc Ot6PreviewList_ext
        .a8
        .i16
        lda     ($4f)           ; the row's ability id
        sta     $2c
        xba
        pha                     ; preserve b (drawlistletter's attr)
        lda     $2c
        cmp     #$36
        bcs     @done           ; spells only
        phx
        phy
        longa
        lda     $62ca           ; active character slot
        and     #$0003
        asl
        tax                     ; -> entity offset, the leaves' own indexing
        shorta0
        jsl     Ot6FoldSteps    ; pending boost -> OT6_SCR_BIT tier steps
        beq     @out
        lda     $2c
        jsl     Ot6FoldTier
        sta     $2c             ; render the folded tier's name
@out:   ply
        plx
@done:  pla
        xba                     ; b restored
        lda     $2c
        rtl
.endproc

; spell tier families: base, one boost, two boosts
Ot6FoldTbl:
        .byte   $00,$05,$09     ; fire, fire 2, fire 3
        .byte   $01,$06,$0a     ; ice line
        .byte   $02,$07,$0b     ; bolt line
        .byte   $03,$08,$08     ; poison, bio (caps)
        .byte   $2d,$2e,$2f     ; cure line
        .byte   $30,$31,$31     ; life, life 2 (caps)
        .byte   $19,$28,$28     ; slow, slow 2 (caps)
        .byte   $1f,$27,$27     ; haste, haste2 (caps)

; ------------------------------------------------------------------------------

; [ the magic list shows the folded tier's price, and greys on it (#64) ]
;
; The other half of #64.  Ot6QueueFold charges the folded tier; without this
; the list would still show the base spell's number beside the folded
; name ("Fire 3 ... 4", and then 51 MP gone) and the confirm would accept
; a cast the universal insufficient-MP gate then fizzles.  That is the
; class of display mismatch the last three releases removed, and #64 names
; it explicitly.
;
; Why one byte instead of four hooks.  Everything the player is told about a
; magic row's cost reads the same cell, entry+3 of the caster's spell list:
;
;   the grey      CheckMagicEnabled  `lda a:$0003,x / cmp $3a4c`  (:14692)
;                 -> bit 7 of entry+1 -> GetTextColor $04 -> $21|$04 grey
;                    (btlgfx_main.asm:11271-11278, :10704)
;   the number    the highlighted row's cost, $2095,x -> w7e6178 -> the NMI
;                 drawer (btlgfx_main.asm:13027, :19690, :854)
;   the confirm   `lda $2093,x / bmi` refuses a disabled row
;                 (btlgfx_main.asm:19659-19663)
;   the charge    GetMPCost's character arm, `lda a:$0003,x`  (:13296)
;
; Three of those four live in bank C1, which is linked as a stock object into
; both the shipped and the nomp ROM, so a hook in any of them would shift the
; nomp baseline, the one thing that flag must never do (see Ot6AbilityGrey's
; header for the same constraint).  Moving the byte they all read costs zero
; C1 bytes and makes it structurally impossible for the four to disagree.
;
; It is self-restoring, which is why it runs at every tier including zero.
; The write is not a mutation of the previous value; it is recomputed
; absolutely, from MagicProp through Ot6SpellMP, every pass.  At 0 tier steps
; Ot6FoldTier hands back the base id and Ot6SpellMP reproduces the
; number ValidateSpellList put there (that identity is argued in Ot6SpellMP's
; header).  So pressing L back down to 0 BP restores the base prices by the
; same code path that raised them, and there is no stale state to leak into
; the next turn.  An early-out at steps == 0 would break that.
;
; When it runs.  Vanilla's own recheck request: bit 7 of $3204,x, consumed by
; the main loop's `asl $3204,x / bcc / jsr UpdateEnabledMagic`
; (battle_main.asm:1367-1369).  Ot6Boost sets it on every L/R edge that moves
; the bank, beside the OT6_RESTAGE repaint it already requested, and
; Ot6ActionEnd sets it when it consumes a pending, so the prices track the
; boost live and fall back when it is spent.  If no recheck ever
; happens the list shows base prices, which is the correct answer for
; an unboosted caster; the charge never depends on this having run
; (Ot6QueueFold re-prices at queue time regardless).
;
; entry (jsl from UpdateEnabledMagic's head): a8/i8, a battle-loop caller.
; x = the entity offset, db=$7e.  preserves a/x/y and P.
.proc Ot6FoldPrices
        .a8
        php
        longi
        .i16
        pha
        phx
        phy
        txa                     ; width-neutral character test
        cmp     #$08
        bcs     @out            ; monsters have no boost and no spell list
        ; x is the only register the 65816 can index a long address with
        ; (`lda f:tbl,y` has no encoding), and this walk needs it three
        ; different ways per family (table cursor, spell id, list entry),
        ; so the two invariants live in scratch and x is working state.
        stx     OT6_SCR_SLOT2   ; the caster's entity offset
        jsl     Ot6FoldSteps    ; -> OT6_SCR_BIT (0 restores the base prices)
        ldx     #$0000
        stx     OT6_SCR_IDX     ; family cursor (word store: the high byte must
                                ;   stay 0 for the 8-bit bumps at @next)
@fam:   ldx     OT6_SCR_IDX
        lda     f:Ot6FoldTbl,x  ; the family's base id, the id the list holds
        longa
        and     #$00ff
        tax
        shorta0
        lda     $3084,x         ; master spell list: spell id -> entry index
        cmp     #$ff
        beq     @next           ; this spell owns no list entry at all
        ldx     OT6_SCR_SLOT2   ; the caster again
        longa
        and     #$00ff
        asl2                    ; entry index * 4 -- GetMPCost's own stride
        clc
        adc     $302c,x         ; -> this caster's entry for the base spell
        tax
        shorta0
        lda     a:$0000,x       ; the entry's id byte
        bmi     @next           ; $ff: not learned.  leave the row alone; it
                                ;   is already disabled, and a price on a row
                                ;   the caster cannot pick means nothing
        phx                     ; the entry
        ldx     OT6_SCR_IDX
        lda     f:Ot6FoldTbl,x  ; the base id again
        jsl     Ot6FoldTier     ; -> the tier this boost buys
        ldx     OT6_SCR_SLOT2   ; the caster (Ot6SpellMP wants the entity)
        jsl     Ot6SpellMP      ; -> that tier's real cost, relics included
        plx                     ; the entry back
        sta     a:$0003,x       ; the byte: grey, number, confirm and charge
@next:  lda     OT6_SCR_IDX     ; cursor + 3 (low byte only; it never reaches
        clc                     ;   $18, so the high byte stays the 0 above)
        adc     #$03
        sta     OT6_SCR_IDX
        cmp     #$18            ; 8 families
        bcc     @fam
@out:   ply
        plx
        pla
        plp
        rtl
.endproc

; ------------------------------------------------------------------------------
.if OT6_MP_COSTS
; ------------------------------------------------------------------------------

; [ price a costed verb's action at queue time (v0.4, OT6_MP_COSTS) ]

; the "one dispatch change" docs/design/mp-economy.md's M4 note predicts.
; vanilla's GetMPCost (battle_main.asm) returns a cost only for magic, lore,
; summon and x-magic; every other command (Blitz, SwdTech, Tools, the free
; floor, the free-exception verbs) falls through it returning 0, so the
; universal charge at CalcAttackEffect (the $3a4c subtract, and its
; insufficient-mp fizzle) never fires for them. this hook runs on the same A
; the queue store consumes, right after GetMPCost: for the three costed verbs
; it swaps the 0 for the kit price, keyed by the resolved id already sitting
; in $3a7b at queue time:
;   blitz  ($0a): attack id  $5d-$64   (FixPlayerAttack's +$5d)
;   swdtech($07): attack id  $55-$5c   (FixPlayerAttack's +$55)
;   tools  ($09): tool item id $a3-$aa (Cmd_09 resolves it as $b6-$a2)
; those three id ranges are disjoint, so one $ff-terminated (key,cost) table
; serves all three; the command gate keeps a stray id under any other verb
; from matching a row. an id absent from the table charges 0, so a
; missing price is free rather than a garbage charge, and every command that is
; not one of the three returns vanilla's own A untouched (magic stays priced
; on its own baseline, the free floor stays free).
;
; steal (cmd $05) is a fourth costed verb, but a single ability rather than a
; list: FixPlayerAttack omits it from CmdWithAttackTbl, so it never earns a
; per-ability id in a disjoint range (its queue-time $3a7b is the menu's raw
; attack byte, not a table key). so it takes a flat-cost path keyed on the
; command alone (cmd $05 -> 2 MP, mp-economy.md's "flat small" for the
; probe-collect verb) and never consults the id table. (routing it through
; the table would also have to avoid a collision: steal's own special-effect
; id $a4, set at execute time in Cmd_05, is already the tool key for
; Bio Blaster.) confirmed (owner, 2026-07-22): only the basic Fight
; command is free; every other verb costs MP as its kit comes online.
;
; the charge and the refusal are both already universal (they act on whatever
; $3620 -> $3a4c holds); the only magic-specific piece is the menu grey-out /
; cost display (CheckMagicEnabled), which is the menu-bank work this
; flag waits on. that is why a hidden charge must not ship enabled: the menu
; still shows these verbs no number.
;
; boost never raises the price: blitz and tools keep one id no matter the
; boost, and a boosted SwdTech has already queued the tech its BP bought
; (Ot6BushidoTier / Ot6QueueFold leaves $3a7b at that tech), whose own
; per-tech price is what should be charged: BP buys the tier, and MP
; prices the cast (mp-economy.md).
;
; entry (jsl from CreateAction, right after jsr GetMPCost): a8/i16,
; A = vanilla cost, X = attacker entity, Y = queue slot. db=$7e (the site
; Ot6QueueFold reads $3a7a/$3a7b from one instruction later). preserves X
; and Y (the store needs Y, Ot6QueueFold needs X); returns A = final cost.

.proc Ot6AbilityCost
        .a8
        .i16
        php
        longi
        pha                     ; vanilla cost, parked (restored if we defer)
        lda     $3a7a           ; command
        cmp     #$05
        beq     @steal          ; steal: one verb, one flat price, no id
        cmp     #$13
        beq     @dance          ; dance: flat, paid at dance-START only (#34)
        cmp     #$10
        beq     @rage           ; rage: the same shape as dance (#40)
        ; no cmd-$11 arm: Leap is free (owner, 2026-07-29).  It had a flat 2
        ; here from #40, reasoned from "only the basic Fight command is free",
        ; but that price was never rendered on any surface, so the only way
        ; a player met it was a Leap that refused with no reason given.  And
        ; Leap now shares the Fight row on the Veldt (Ot6VeldtRow,
        ; battle_main.asm): it is the Fight row there rather than a verb
        ; beside Fight, and the free floor has to survive that.  Falling out of this
        ; chain hands back vanilla's own cost for cmd $11, which is 0.
        cmp     #$07
        beq     @costed         ; swdtech
        cmp     #$09
        beq     @costed         ; tools
        cmp     #$0a
        beq     @costed         ; blitz
        pla                     ; some other verb: hand back vanilla's cost
        plp
        rtl
@steal: ; #55: steal is no longer one ability; it is the first row of Locke's
        ; thief submenu, and the row the player picked is in $3a7b (see
        ; Ot6ThiefListOpen's header for why that byte is free under this command
        ; and why the $11a9/$a4 collision the old note warned about does not
        ; reach here).  Filch and Bestow price from Ot6ThiefCostTbl, keyed on
        ; that byte; everything else (the Steal row itself, the $ff a Confused
        ; or AI-issued Steal queues, a Gogo mimic) falls through to
        ; Ot6StealCost, so #52's single authority for Steal's 4 still holds.
        pla                     ; drop the parked cost (0 for steal)
        lda     $3a7b           ; the row the submenu queued
        jsl     Ot6ThiefIsNew   ; carry set = filch/bestow (A preserved)
        bcc     @plainsteal
        jsl     Ot6ThiefCostFor
        plp
        rtl
@plainsteal:
        jsl     Ot6StealCost    ; the flat price, one authority (#52)
        plp
        rtl
@dance: ; dance (cmd $13) is priced at the commit moment only: the mid-dance
        ; turns queue through the same CreateAction (RandDanceAction,
        ; battle_main.asm:617), but by then Cmd_13 has set the actor's DANCE
        ; status ($3ef8 bit 0).  one payment starts the whole-battle state,
        ; and every locked-in step is free (mp-economy.md's verb survey).  a
        ; stumbled start (Cmd_13's 50% @17af arm) clears the bit, so retrying the
        ; commit pays again, because the payment moment is the commit moment.
        ; X = attacker entity at this hook (the site contract above).
        pla                     ; drop the parked cost (0 for dance)
        lda     $3ef8,x         ; status 3
        lsr                     ; bit 0 = already dancing (a mid-dance turn)
        bcc     :+
        lda     #$00            ; locked-in step: free
        plp
        rtl
:       jsl     Ot6DanceCost    ; dance-start: the flat price, one authority
        plp
        rtl
@rage:  ; #40: rage is the other possess-verb, and issue #40 orders one pricing
        ; rule for both: flat, charged once at Rage-start, and every possessed
        ; turn after it free.  The discriminator is the same shape dance uses:
        ; Cmd_10 sets the actor's RAGE status ($3ef9 bit 0) on the start turn,
        ; and every later possessed turn re-enters command $10 with the bit
        ; already set.  X = attacker entity at this hook (the site contract).
        ; A refused start must not lock the trance for free either; that is
        ; Ot6RageStartGate's job in Cmd_10, dance's #34 finding re-applied.
        pla                     ; drop the parked cost (0 for rage)
        lda     $3ef9,x         ; status 4
        lsr                     ; bit 0 = already raging (a mid-trance turn)
        bcc     :+
        lda     #$00            ; locked-in possessed turn: free
        plp
        rtl
:       jsl     Ot6RageCost     ; rage-start: the flat price, one authority
        plp
        rtl
@costed:
        pla                     ; drop the parked cost (it is 0 for these)
        lda     $3a7b           ; the resolved id (attack id / tool item id)
        jsl     Ot6CostFor      ; pure table scan: id -> cost in A
        plp
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ price one ability by its id: the reusable cost authority ]
;
; the table scan, split out of Ot6AbilityCost so the menu bank can price a row
; without running the command gate. Ot6AbilityCost reads $3a7a/$3a7b at queue
; time; a menu row already holds the id it is about to draw, so it needs only
; this leaf. Pure: id in A, cost in A ($00 if the id is unpriced), reads no
; $3a7x. keys are disjoint per verb (blitz $5d-$64, swdtech $55-$5c, tools
; $a3-$aa), so the id alone selects the row. preserves X and Y; a8/i16.
; rtl (jsl): one entry for bank F0 and any cross-bank caller.
.proc Ot6CostFor
        .a8
        .i16
        phx
        pha                     ; park the id to match against each table key
        ldx     #$0000
@scan:  lda     f:Ot6AbilityCostTbl,x
        cmp     #$ff
        beq     @free           ; ran off the table: unpriced id is free
        cmp     $01,s           ; table key vs the parked id
        beq     @hit
        inx
        inx                     ; 2-byte records: key, cost
        bra     @scan
@hit:   lda     f:Ot6AbilityCostTbl+1,x
        bra     @done
@free:  lda     #$00
@done:  sta     $01,s           ; overwrite the parked id with its cost
        pla                     ; A = cost
        plx
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ #55: the second keyed table, for Locke's thief submenu ]
;
; Why a second table rather than rows in Ot6AbilityCostTbl.  That table's header
; earns its single-scan design on one property: "those three id ranges are
; disjoint, so one $ff-terminated (key,cost) table serves all three; the command
; gate keeps a stray id under any other verb from matching a row".  The
; thief rows are $56-$58, which sit inside SwdTech's $55-$5c key range: they
; are AttackName pad slots, and SwdTech's ids are attack ids in the same space
; (SwdTech draws its names from BushidoName, which is why the pad was
; free; see Ot6ThiefListOpen).  Putting them in the shared table would break the
; disjointness the scan relies on and would price a boosted SwdTech row as a
; Filch.  Keeping them here keeps the invariant true: two tables, each
; reached from its own arm of Ot6AbilityCost's command gate, and the gate is what
; makes the key spaces disjoint.
;
; The baseline (the same one Ot6AbilityCostTbl is on: 8-20% of the real pool at the
; level the ability arrives).  Locke joins at Narshe holding 31 MP at LV6, the
; figure Ot6StealCost measured off probe_mppools.lua, and these are granted at
; join with Steal (the story-gating ruling; kits.md).  So:
;
;   Steal   4  12.9%   (Ot6StealCost, unchanged: tier one, the signature)
;   Bestow  5  16.1%   between Cure's 12.5% and Drain's 17.2%
;   Filch   6  19.4%   just under Life's 20.3%, the top of the baseline
;
; Not monotonic with the tier order, deliberately: kits.md numbers Filch tier 4
; and Bestow tier 5, so a monotonic column would want Filch cheaper.  SwdTech is
; the one kit that must stay monotonic and its table says why: "the row IS the
; boost level, so a dearer 2x row than 3x row would read as a bug".  The thief
; submenu is a free-choice menu like Blitz, which the same header exempts from
; the rule ("Blitz is a free-choice menu and needs no such rule"), and Blitz
; already ships Mantra 16 beneath Fire Dance 17 for the same reason.  Price by
; what the ability does, not by where kits.md lists it.
;
; Filch sits at the top of the baseline on purpose: it is the only shield
; remover in the game that ignores class and element, and the only way to gain
; two BP in a turn (see Ot6Filch), and at 6 a full LV6 pool buys five of them.
; Bestow costs more than Steal because it is a party-wide tempo move rather
; than a probe, and less than Filch because it moves a pip Locke already paid
; for.  Placeholders like every number in this file; battle_costtable.lua
; recomputes the fractions from the ROM.
Ot6ThiefCostTbl:
        .byte   OT6_THIEF_FILCH,  6     ; Filch: shield -> boost point
        .byte   OT6_THIEF_BESTOW, 5     ; Bestow: hand a boost point to an ally
        .byte   $ff
        ; no Steal row: Ot6StealCost is its authority (#52) and the @steal arm
        ; routes the Steal row, and every Steal this menu did not issue, to
        ; that leaf.  A row here would make two numbers for one price.

; [ #55: price one thief row by its id, Ot6CostFor's twin on the second table ]
; Pure: id in A, cost in A ($00 if the id is unpriced; an unpriced id is free
; rather than a garbage charge, the same ruling Ot6CostFor makes).  preserves
; X and Y; a8/i16.  rtl.
.proc Ot6ThiefCostFor
        .a8
        .i16
        php
        longi
        phx
        pha                     ; park the id to match against each table key
        ldx     #$0000
@scan:  lda     f:Ot6ThiefCostTbl,x
        cmp     #$ff
        beq     @free           ; ran off the table: unpriced id is free
        cmp     $01,s           ; table key vs the parked id
        beq     @hit
        inx
        inx                     ; 2-byte records: key, cost
        bra     @scan
@hit:   lda     f:Ot6ThiefCostTbl+1,x
        bra     @done
@free:  lda     #$00
@done:  sta     $01,s           ; overwrite the parked id with its cost
        pla                     ; A = cost
        plx
        plp
        rtl
.endproc

; [ #34: can the dancer pay the start?  Cmd_13's lock-out gate ]
;
; carry set = the queued cost ($3a4c, staged from the cost queue at action
; load, battle_main.asm:425) exceeds the attacker's current MP.  Cmd_13
; consults this before setting the DANCE status: the universal fizzle
; refuses only the cast, and the status set in the command body would
; otherwise start the whole-battle state unpaid.  entry: jsl from Cmd_13,
; a8/i8 (command context), y = attacker entity, db=$7e.  clobbers a.
.proc Ot6DanceStartGate
        .a8
        rep     #$20
        .a16
        lda     $3c08,y         ; current MP (16-bit; y indexes fine under i8)
        cmp     $3a4c           ; carry set = MP >= cost (affordable)
        sep     #$20
        .a8
        bcs     @ok
        sec                     ; cannot pay: the start must not lock
        rtl
@ok:    clc
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ the Dance price: one authority for the charge and the menu (#34) ]
;
; mp-economy.md's verb survey rules Dance "flat, paid at start, 4-10: one
; payment starts a whole-battle state".  8, in the top half of the range,
; because the single
; payment funds every subsequent turn's verb for the rest of the battle
; (each locked-in step is free), so it prices above the per-use signature
; verbs (Steal 4 since #52, Pummel 4) while staying payable from Mog's pool
; (base 16 MP + level gains); playtest tunes.  Pure leaf, the Ot6CostFor
; shape: cost in A, preserves X and Y; rtl so the menu decorator (bank F0
; via C1) and the charge read one number.
.proc Ot6DanceCost
        .a8
        lda     #$08
        rtl
.endproc

; [ the Steal price: the flat verb's one authority (#52) ]
;
; 4, up from the 2 that shipped in v0.5.  #52's headline was "2 MP is ~2% of
; Locke's LV14 pool", but that measures at the wrong level, and the baseline this
; column is on measures at the level an ability arrives: Locke joins at Narshe
; holding 31 MP (LV6, read off worldmap_narshe by probe_mppools.lua), where 2
; is 6.5%, under the 8-20% a vanilla spell costs at its arrival, and 4 is
; 12.9%, between Fire's 10.0% and Cure's 12.5%.  So the fix is the same
; 2x #45 gave the Blitz floor, not a bigger number chosen to look right at LV14.
; (Every signature dilutes the same way by then: Pummel is 4.3% of Sabin's LV14
; pool and Dispatch 4.3% of Cyan's.  Pricing against a late pool would mean
; per-level prices, which the baseline does not do.)
;
; 4 also matches the cheapest row of all three ladder kits:
; Pummel $5d, Dispatch $55, and AutoCrossbow $aa are all 4, and Steal
; is Locke's signature, per mp-economy.md's "signatures become the cheapest rows
; of their kits".  That match matters for #55: Steal is a tier rather than the
; ceiling (owner, 2026-07-29; Locke's 99 is Master's Mark, kits.md's Locke
; ladder tier 8), so it should read as tier one of an eight-tier ladder, not
; as its own thing.
;
; What this price still cannot do: it cannot be displayed.  Steal is a
; top-level battle command, and command_window_data_set (btlgfx_main.asm:10099)
; writes two things per row, the command byte and a GetTextColor
; colour off the DISABLED flag (:10704, `and #$80`), through MenuText::_4
; (:45136), four fixed 8-byte records with no number command in them.  There is
; no numeric field in that window to write a price into, which is why this is a
; pure leaf in the Ot6DanceCost/Ot6CostFor shape rather than an inline
; immediate: when #55 gives Locke a submenu, its row decorator reads this
; and the drawn price and the charged price cannot disagree.  See mp-economy.md
; "Steal's price is real and invisible" for the ruling and why a numeric field
; was not built into the command window for one verb.
;
; Pure leaf: cost in A, preserves X and Y, rtl.
.proc Ot6StealCost
        .a8
        lda     #$04
        rtl
.endproc

; [ the Rage price: the same rule as Dance, for the other possess-verb (#40) ]
;
; issue #40 orders "one pricing rule for both possess-verbs", and mp-economy.md:
; 96's rule is the possession's: one payment starts a whole-battle state, so the
; price is per battle, not per turn.  A per-rage formula (price by the special's
; spell cost) was considered and rejected in kit-gau.md §5 on three counts: it
; double-charges (the trance's real price is the surrendered control, already
; paid, and the special is rolled rather than chosen); it makes the
; rarest hunts carry the highest prices; and it
; needs a 255-row price surface where the flat rule needs one number.
;
; 8, deliberately Dance's own number rather than a number near it.  If the Dance
; figure ever moves inside mp-economy's 4-10 range, Rage follows it: the rule
; ("possess-verbs share one flat price") takes priority over the digit, so this
; leaf tail-calls Ot6DanceCost rather than repeating the literal, and the two
; cannot drift.  Pure leaf: cost in A, preserves X and Y, rtl.
.proc Ot6RageCost
        .a8
        jmp     Ot6DanceCost    ; tail-call: same bank, its rtl returns for us
.endproc

; [ the Leap price: retired.  Leap is free (owner, 2026-07-29) ]
;
; #40 gave Leap a flat 2 (Ot6LeapCost, deleted here), reasoned from "only the
; basic Fight command is free" (mp-economy.md, as it then read) and that doc's
; probe-collect tier, the same row Steal sits on.  Two things retired it:
;
;   1. the price was never displayed.  Leap is a top-level command row, not a
;      list entry, so nothing ever drew "2 MP" beside it; the id-keyed
;      pricing surfaces (Ot6CostFor -> ot6_loadout.asm / skills.asm) only reach
;      verbs that open a window.  The command window itself
;      (command_window_data_set, btlgfx_main.asm:10099-10125) stores only the
;      command byte and a GetTextColor colour per row, and that colour is
;      `and #$80` on the DISABLED flag (:10704-10707), not affordability.  A
;      player's only encounter with the number was a Leap that refused for
;      reasons the screen never gave.
;   2. Leap is now the Fight row on the Veldt (Ot6VeldtRow, battle_main.asm).
;      #47 exists to guarantee Gau a free action; a priced Leap sitting in the
;      Fight row would have re-opened that hole in the one place, the Veldt,
;      where Gau spends the most turns.
;
; Steal keeps its flat 2: it is a verb BESIDE Fight, not the Fight row, and
; its repricing is issue #52's business, not this change's.  Leap is otherwise
; still vanilla (kit-gau.md §6.3 recommended against the boosted-Leap rider).

; [ #40: can the hunter pay the trance?  Cmd_10's lock-out gate ]
;
; The twin of Ot6DanceStartGate, and it exists for the reason #34
; found: the universal insufficient-MP fizzle refuses the cast, but it runs
; after the command body, so a Gau who cannot pay would keep the whole-battle
; RAGE status for free and every possessed turn after it costs 0.  A fizzled Rage
; must not lock the whole-battle state for nothing.  When the queued cost
; ($3a4c, staged at action load) exceeds the pool, Cmd_10 skips the status set
; and the beast latch entirely and runs the plain exec, whose fizzle shows the
; standard refusal surface.  Mid-trance turns queue at 0 (Ot6AbilityCost's
; cmd-$10 arm), so this gate never fires on a possessed turn.
; entry: jsl from Cmd_10, a8/i8 (command context), y = attacker entity, db=$7e.
; clobbers a.  out: carry set = cannot pay.
.proc Ot6RageStartGate
        .a8
        rep     #$20
        .a16
        lda     $3c08,y         ; current MP (16-bit; y indexes fine under i8)
        cmp     $3a4c           ; carry set = MP >= cost (affordable)
        sep     #$20
        .a8
        bcs     @ok
        sec                     ; cannot pay: the trance must not lock
        rtl
@ok:    clc
        rtl
.endproc

; (key, cost) pairs, $ff terminates. keys are the id already in $3a7b
; at queue time, disjoint across the three verbs. names below are the ones the
; screen prints (the FF3-US translation, per CONTRIBUTING's vocabulary rule,
; owner 2026-07-29); where an internal disassembly label differs it is marked
; as such and never used as the primary.
;
; -------- the baseline these numbers are on (#45 rescale, 2026-07-29) --------
;
; mp-economy.md's "one price scale" says kit skills price on the vanilla spell
; baseline.  That baseline was not measured until #45; here it is: vanilla
; natural magic, cost as a fraction of the caster's real pool at the level the
; spell is learned (pool = char_prop base MP + LevelUpMP running sum, both
; read out of this ROM rather than recalled):
;
;   Antdot 3 @L6 7.5% · Warp 20 @L26 8.3% · Fire 4 @L6 10.0%
;   Fire 2 20 @L22 10.4% · Cure 5 @L6 12.5% · Drain 15 @L12 17.2%
;   Life 30 @L18 20.3%
;
; (spells learned below Terra's earliest measured level are priced at that
; level, L6, pool 40, read off kolts_entry, the same clamp the kit rows
; use, because a pool the game never presents is not a price anyone pays.)
; so a vanilla spell costs roughly 8-20% of the pool it is first cast from.
; The v0.4/v0.5 kit columns did not sit on that baseline.  Measured the same way,
; SwdTech ran 1.0-3.9% and Blitz 3.6-12.5%, three to eight times under the
; scale the doc claimed they shared.  The owner's v0.7 playtest found it from
; the other end: at LV14 Cyan holds a 96 MP pool against techs costing 1/2/3,
; and BP was not scarce either, so neither currency bound him and Fight had no
; case (mp-economy.md's stated target: "Fight must sometimes be the right move,
; without Cyan and Sabin ceasing to feel like ability characters").
;
; One principled change rather than two knobs (owner's decomposition, #45):
;
;   1. Retire SwdTech's ~1/3 discount.  It was justified by "the BP ladder is
;      the real price, so MP rides ~1/3 of a comparable Blitz/Tool", a claim
;      about the four-tier 0x/1x/2x/3x ladder.  #38 rewrote that ladder to
;      1x/2x/3x and deferred the MP column ("MP costs per tech
;      unchanged"), so the discount kept applying after the premise that earned
;      it had been rewritten.  SwdTech now prices at parity with the Blitz row
;      of the same index, which is a statement about levels rather than an
;      index coincidence: BlitzLevelTbl is 1/6/10/15/23/30/42/70 and
;      BushidoLevelTbl 1/6/12/15/24/34/44/70 (field/event.asm:1236-1240), so
;      row n of either kit lands in the same range against nearly the same pool.
;   2. A general floor lift of ~1.5-2x on the Blitz ladder, tapering toward
;      1.5x at the top, i.e. compression rather than a flat multiply.  Pools
;      grow far faster than a fixed cost, so the same ladder scaled flat would
;      price the late rows above the baseline while leaving the early ones
;      under it.
;
; What that lands (cost / real pool at the level the row is reachable; rows 1-2
; evaluated at L10, the earliest either character is in the party):
;
;   Blitz    7.1 17.9 23.2 16.3  8.4  7.9  6.7  6.1 %   (was 3.6 .. 12.5)
;   SwdTech  6.9 17.2 17.1 15.1  8.8  6.6  6.2  6.0 %   (was 1.0 ..  3.9)
;
; Every row stays payable from a full pool at the level it becomes available by
; a wide margin, and the top rows most of all, because L42/L70 pools are
; 449/760.  The owner's worry that a flat 4x would push "Bum Rush 30 -> 120 past
; WoB pools" is not borne out by measurement: Bum Rush is
; L70-gated and Sabin's L70 pool is 760.  The pressure is at the floor and in
; early WoB, where mp-economy.md already said it was.
;
; Tools are deliberately unchanged.  Measured against Edgar's real pool at the
; stage each tool is acquired they already run 7-21%, on the vanilla
; baseline above (AutoCrossbow 11.1% @L7, Drill 18.4% @L13, Chain Saw 20.7% @L13).
; The general lift was considered for them and the measurement ruled it out: a
; 1.5x on Chain Saw would put it at 31%, off the top of the scale.  gil buys the
; tool once, MP is the per-use cost, and that price was already right.
;
; Every number here is a playtest placeholder (mp-economy.md's standing
; preamble) and successive rescales are expected, not churn.  The test that
; keeps a future column on the baseline is tools/tests/battle_costtable.lua, which
; recomputes these fractions from the ROM's own tables.
;
; -------- the 99 anchor (issue #57, 2026-07-29) --------
;
; Owner: "it would be cool to scale ability MP costs so that each character's
; own ultimate ends up costing 99 MP", refined to "99 where it makes sense, not
; universal".  Two rows in this table qualify: Bum Rush ($64) and Cleave
; ($5c), each its kit's divine top tier.  Tools does not participate: its
; capstone is Overclock, which kits.md prices as the sum of the two tools it
; fires and which is not built, and Air Anchor ($a9) is "a findable
; item mid-kit gag, not the capstone" (kits.md, Edgar), so there is no top
; Tools row here to anchor.  Steal, Slot, Rage and Dance are flat verbs with no
; ladder, which is a stated answer rather than a gap.
;
; Why 99 and not 100.  Owner: "seeing things like 99, 999, and 9999 in Final
; Fantasy games feels right -- very classic feel."  It is also the number this
; game already uses: vanilla's most expensive spell is Quick at 99 MP
; (magic_prop_en.dat +$05, id $2b), so the anchor is the series' own ceiling
; rather than an imported one.  It is also a hard display limit: every OT6 price
; drawer renders two digits (ListText cmd $02, btlgfx_main.asm:15045-15073,
; divides by ten once, and Ot6LoadoutDrawCost, ot6_loadout_page.asm:375,
; has one tens loop), so 100 would print as garbage rather than as a big number.
;
; What the anchor changed, and what it did not.  Rows 6/7/8 of
; both ladders, and nothing else.  #45 lifted the floor hard (2x) and the
; ceiling less (1.5x), hedging against an owner worry that "Bum Rush 30 -> 120"
; would outrun WoB pools, a worry #45's own measurement then disproved (Bum
; Rush is L70-gated and Sabin's L70 pool is 760).  The hedge stayed in after the
; measurement removed its reason, which is why the tail still sat at 6.0-6.7% of
; pool while the middle of the ladder sat at 15-23%.  The anchor corrects
; that: the tail is re-derived upward so that %-of-pool climbs
; into the anchor rather than falling away from it, and rows 1-5 are untouched
; because they already measure inside the baseline at the level they arrive.
;
;   Blitz    7.1 17.9 23.2 16.3  8.4 10.1 11.1 13.0 %   (tail was 7.9 6.7 6.1)
;   SwdTech  6.9 17.2 17.1 15.1  8.8  8.4 10.4 13.0 %   (tail was 6.6 6.2 6.0)
;
; This is not a proportional scale of the old column (99/46 =
; 2.15x): that would leave Suplex at 28 MP, 50% of a LV10 pool, and push
; rows 2-4 off the top of the baseline.  The old column was right in the
; middle and wrong at the ends, so only the end moves.
Ot6AbilityCostTbl:
        ; -- Blitz (Sabin), cmd $0a, attack ids $5d-$64.  levels are
        ;    BlitzLevelTbl.  ladder shape kept (Mantra deliberately under Fire
        ;    Dance: a utility off-ramp, not a damage tier); level lifted.
        .byte   $5d,  4         ; Pummel     L1  signature, the cheapest row
        .byte   $5e, 10         ; AuraBolt   L6  holy chip
        .byte   $5f, 13         ; Suplex     L10 bludgeon
        .byte   $60, 17         ; Fire Dance L15 fire, all
        .byte   $61, 16         ; Mantra     L23 party heal (utility, off-ramp)
        .byte   $62, 28         ; Air Blade  L30 wind, all      (#57: was 22)
        .byte   $63, 50         ; Spiraler   L42                (#57: was 30)
        .byte   $64, 99         ; Bum Rush   L70 divine, bludgeon x8, the
                                ;   anchor (#57).  13.0% of the L70 pool of
                                ;   760, inside the baseline; 7 uses from full.
        ; -- SwdTech (Cyan), cmd $07, attack ids $55-$5c.  levels are
        ;    BushidoLevelTbl.  names are BushidoName, the table the SwdTech
        ;    window actually renders from (`Bushido` survives only as the
        ;    internal label, per the vocabulary rule above).
        ;    Parity with the Blitz row of the same index, per (1) above; the
        ;    old "~1/3 of a comparable Blitz/Tool" discount is retired here.
        ;    One deviation from parity: Empowerer takes 18 rather than Mantra's
        ;    16, because this column must stay monotonic with the tech index:
        ;    the boost window offers techs weakest->strongest and the row
        ;    is the boost level (kits.md), so a dearer 2x row than 3x row would
        ;    read as a bug.  Blitz is a free-choice menu and needs no such rule.
        ;    Cyan still pays BP on top; if parity plus the 1-BP floor leaves him
        ;    short, #38's own ruling names the lever: BP seed/regen, not
        ;    the floor, and not this column.
        .byte   $55,  4         ; Dispatch     BP1 signature
        .byte   $56, 10         ; Retort       BP1 counter stance
        .byte   $57, 13         ; Slash        BP2 slash
        .byte   $58, 16         ; Quadra Slam  BP2 slash x4
        .byte   $59, 18         ; Empowerer    BP3 drain (the parity deviation)
        .byte   $5a, 28         ; Stunner      BP3 slash, all   (#57: was 22)
        .byte   $5b, 50         ; Quadra Slice BP3 wind x4      (#57: was 30)
        .byte   $5c, 99         ; Cleave       BP3+Broken divine, the anchor
                                ;   (#57).  13.0% of Cyan's L70 pool of 762,
                                ;   the same fraction Bum Rush is of Sabin's,
                                ;   which is the point of anchoring both.
        ; -- Tools (Edgar), cmd $09, tool ITEM ids $a3-$aa.  names are
        ;    item_name_en.json's, i.e. what the Tools window prints.
        ;    unchanged by the #45 rescale; see "Tools are deliberately
        ;    unchanged" above: measured, they are already on the baseline.
        .byte   $aa,  4         ; AutoCrossbow signature, piercing x4 shredder
        .byte   $a3,  6         ; NoiseBlaster confuse
        .byte   $a4,  8         ; Bio Blaster  poison, all: the armor-break key
        .byte   $a5,  6         ; Flash        blind, all
        .byte   $a8, 16         ; Drill        armored-boss answer, pierce
        .byte   $a6, 18         ; Chain Saw    slashing + instant-death chance
        .byte   $a7, 10         ; Debilitator  adds + reveals a weakness (probe)
        .byte   $a9, 14         ; Air Anchor   mid-kit gag (harpoon / doom)
        ; Overclock (the divine "use two tools") has no single tool item id:
        ; its price is the sum of the two tools it fires, wired the day
        ; Overclock is built (kits.md: Magitek-factory story unlock).  That is
        ; also why Tools does not take the 99 anchor (#57): Edgar's ultimate is
        ; Overclock, not the mid-kit gag Air Anchor, and the sum of two tools
        ; tops out at 34 (Chain Saw 18 + Drill 16).  Whether Overclock is 99 or
        ; stays the sum is a decision for the issue that builds it: both rules
        ; cannot hold, and inventing the answer here would price an ability that
        ; has no code.
        .byte   $ff

; ------------------------------------------------------------------------------

; [ battle mp is universal: every character keeps their save's pool (#32) ]
;
; vanilla's battle init loads every character's MP through LoadCharProp
; (battle_main.asm:6621-6640) and then clears it again unless a magic/lore
; command init set the has-mp flag ($f8 bit 0), i.e. unless the character
; knows a spell or has an esper equipped (InitCmdList @53a5..@5408;
; InitCmd_03/04 reach InitCmd_05's `lda #$01 / tsb $f8` only when
; ValidateSpellList counted a spell into $f6 or left an esper in $f7).
; that was sensible when only magic spent MP; under the live economy above it
; sent every spell-less character into battle at 0/0 while Ot6AbilityCost
; priced their whole kit, so Blitz, Tools, SwdTech and Steal all fizzled through
; CalcAttackEffect's universal insufficient-MP gate as wasted turns with no
; message, and the max-0 writeback skip (battle_main.asm:12265-12267) kept
; field MP full so the field never showed the loss (issue #32's measurements).
;
; ruling (issue #32): MP is a universal resource, so its battle init is
; universal.  this hook sets the has-mp flag for every character, so the
; vanilla clear never fires and the pool LoadCharProp loaded survives.  the
; command inits have already run by the hook site, so Magic/Lore command
; removal for spell-less characters is untouched and only the pool differs.
; with max MP now real, vanilla's own end-of-battle writeback (UpdateSRAM)
; stores cur MP back to the character data, so the field pool tracks battle
; spend exactly (battle_naturalmp.lua's writeback gate).
;
; entry (jsl from InitCmdList, right before its `lsr $f8`, once per
; character): a8/i8, a battle-init 8-bit-index caller, so the body is
; width-agnostic (no index ops, no pushes; ot6.asm's width discipline).
; $f8 is the init's direct-page scratch; jsl preserves D, so the dp access
; lands on the caller's own cell.
.proc Ot6MpUniversal
        lda     #$01            ; the "character has mp" bit InitCmd_05 sets
        tsb     $f8
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ grey a menu row the active caster cannot afford: magic's grey-out ported ]
;
; vanilla magic greys an unaffordable spell: UpdateEnabledMagic compares each
; spell's MP cost to the caster's current MP, and DrawMagicListText's
; GetTextColor turns the "cannot pay" answer into $04, OR'd into the row's $21
; white font-palette byte to make $25 (grey).  Blitz and Tools draw through the
; tools-window shell, never the magic list, so they never inherited that
; machinery; this proc supplies it in the menu bank.  Given a row's MP cost in
; A it returns the same $04/$00 magic ORs in: $04 (grey the row) when the active
; caster cannot pay, $00 (leave it white) when they can, and the decorator ORs
; it into the ListText $21 white palette byte the same way GetTextColor
; feeds `ora w7e5755+3`.  The caster is $62ca (the active slot DrawMagicListText
; itself indexes by) and its live MP is $3c08,slot*2, the cell
; CalcAttackEffect's universal charge later subtracts from, so the menu greys
; what the charge would refuse.  A 0 cost (an empty pad cell, or an
; unpriced id Ot6CostFor returned 0 for) is always affordable, so a blank row
; never greys.
;
; Scope: this ports the visual half of magic's affordance (grey the row).  The
; other half, magic's `lda $2093,x / bmi` at the A-button that no-ops the
; confirm on a disabled spell (btlgfx UpdateMenuState_0e @81ae,
; btlgfx_main.asm:19675), would live in the tools/blitz confirm
; (UpdateMenuState_30 @8809, btlgfx_main.asm:20668).  That is btlgfx (bank C1),
; a stock object linked into both the shipped and the nomp ROM (only the battle
; object is rebuilt per-flag), so a confirm gate there would shift the nomp
; baseline byte-for-byte, the one thing this flag must never do.  So the block
; stays where it is and costs no bytes: CalcAttackEffect's universal
; insufficient-MP fizzle refuses the cast at execution (MP is never overspent,
; battle_mpcost.lua's refusal half), and the grey tells the player
; before they get there.  If the block ever moves menu-side, it belongs beside
; @8809 gated on this same Ot6AbilityGrey answer.  (The two states were named
; _3b/_3c here until v0.9+; those are real but unrelated four-instruction
; routines at btlgfx_main.asm:12972 and :12982.  The @-addresses were
; right; the names were wrong.)
;
; a8/i16, db=$7e (the decorators' bank; $3c08/$62ca are $7e battle RAM).  in:
; A = MP cost.  out: A = $00 (white) | $04 (grey).  preserves X and Y, because
; the blitz decorator indexes Qty,y across the call and both keep their buffer
; pointers.  rtl (jsl), the twin entry-shape of Ot6CostFor beside it.
.proc Ot6AbilityGrey
        .a8
        .i16
        phx
        pha                     ; park the 8-bit cost at $01,s
        lda     $62ca           ; active caster slot (magic's own draw index)
        longa
        and     #$0003
        asl                     ; slot -> entity offset (stride 2: chars 0/2/4/6)
        tax
        shorta                  ; back to 8-bit A (reloaded next, so no clr)
        lda     $3c09,x         ; current MP, high byte
        bne     @afford         ; >= 256 MP: nothing in a kit costs that much.
                                ;   checked since #57 rather than assumed: the
                                ;   ceiling is 99 and battle_costtable.lua
                                ;   asserts it on every row of the live table
        lda     $3c08,x         ; current MP, low byte
        cmp     $01,s           ; MP - cost: C set iff MP >= cost (affordable)
        bcs     @afford
        pla                     ; cannot pay: drop the parked cost
        plx
        lda     #$04            ; the disabled bit ($21 | $04 = $25 grey)
        rtl
@afford:
        pla
        plx
        lda     #$00            ; stays $21 white
        rtl
.endproc

; ------------------------------------------------------------------------------
.endif   ; OT6_MP_COSTS
; ------------------------------------------------------------------------------

; [ boost picks the SwdTech; the charge gauge is deleted ]

; replaces UpdateMenuState_37's clock (btlgfx_main.asm @7d5f): the gauge
; ceiling `lda $2020 / inc / sta $36`, the every-4-frames `inc w7e7b82`,
; and the wrap check that followed it. vanilla ran a free bar: the
; counter climbed one unit per 4 frames, the tech was counter >> 5 (128
; frames a level, ~15 s to walk all eight known), it wrapped past the last
; one learned, and A latched whatever level it happened to be showing into
; $2bb0,y (btlgfx_main.asm:19083). the clock is the part that does not fit
; here, so the clock is the part that goes: bp picks the level instead.
; every other piece of vanilla's window is untouched and now renders a
; static selector that tracks L/R live: the numerals, the grey-out of
; unlearned techs (_c2a860), the bar, the A-button latch, FixPlayerAttack's
; +$55 (battle_main.asm:12811), Cmd_07's dispatch (battle_main.asm:3901,
; including its retort/sky stance special case).
;
; the mapping is a moving window of four (issue #5): boost 0/1/2/3 selects
; cyan's top four learned techs, weakest -> strongest. every boost level lands
; on a distinct, useful tech (boost is never dead) and cyan always wields his
; best four. base = max(0, ceiling-3), tech = min(base + boost, ceiling), where
; ceiling is vanilla's own $2020 (techs known - 1, the same value that capped
; the bar). while he knows four or fewer techs base is 0 and every learned tech
; is reachable: 0/1/2/3 land on the ones he has. this replaces the
; old tier table, which named each of four tiers' top tech (fang / tiger /
; dragon / oblivion) and clamped it to the ceiling, so a 3-tech cyan got
; Dispatch / Slash / Slash / Slash and could never cast the Retort he had
; learned, which was issue #5's bug. learn a fifth tech and the window slides
; up one, dropping the weakest; no mid-tier tech is skipped.
;
; dropping the weakest is a real tradeoff: the low techs carry utility
; (Retort's counter stance $56, Empowerer's drain $59) and MP-cheapness that go
; quiet as cyan out-levels them. resolved for v0.5 (see docs/design/kits.md):
; ship the auto-window as-is, with no special-casing of utility and no
; cheap-floor, because his MP pool grows with him and the player-chosen loadout
; (the #5 sequel) is where the drop is answered. playtest is the filter.
;
; oblivion (tech 7, the divine) is the window's conditional top tier rather
; than a case outside it: at full kit the window is {4,5,6,7} and boost 3 lands
; on 7 = oblivion by the same base+boost sum as any other tier, so it comes out
; of the window itself. it is selected here only when learned (ceiling 7) and
; unspent, and still fires as before: gated at resolution by Ot6Oblivion (the
; proc name is internal; the screen prints the tech as Cleave) (hooked
; after ChooseTarget, because the target does not exist at this command-latch
; time, swdtech being in RetargetCmdTbl), and dropped back to tempest (6) here
; for the rest of any battle whose once-per-battle latch is already set. cyan
; learns oblivion off the phantom train, so the top tier is oblivion only at
; full kit.
;
; bp is read, never written: the spend is whatever Ot6Boost banked in
; OT6_BOOST_REVEALED, so Ot6ActionEnd consumes it and skips that turn's regen as
; for any other action, and the <=3 / never-past-bp caps stay Ot6Boost's
; alone. bp the ladder cannot spend (three points at level 1 still buys
; fang) is spent, not refunded, the same as a mage's third
; point on fire buying nothing past firaga.
;
; entry: from UpdateMenuState_37: db=$7e, d=0, a8/i16, y=0 (the bar draw
; downstream indexes w7e7a73,y with it). returns a = the chosen level, as
; the vanilla block it replaces did. clobbers x.
;
; v0.5 submenu (issue #8): SwdTech is now a tools-shell submenu, one row per
; boost level, and the row is the boost, weakest at top. The base/ceiling
; arithmetic and the Cleave top-tier swap are factored into three leaf helpers
; below so single-select (this proc, called at the submenu's confirm latch) and
; the row enumeration (Ot6BushidoWindow) cannot diverge by offering a tech the
; latch would not fire, or firing one the menu never showed. $7b82 is still
; stamped (level*32): battle_mpcost's level() reads it, and the dead numeral
; path can too.

