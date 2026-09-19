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
        ; always read a stale-proof 0.
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
        sta     f:$7e0000+OT6_PIPTAIL   ; nor a stale pip-paint tail
        sta     f:$7e0000+OT6_COVERPAID ; nor a stale cover-earn latch: a
                                ;   stale bit would eat the first cover of
                                ;   the battle instead of costing a no-op
        sta     f:$7e0000+OT6_PIPPEND   ; nor a deferred pip paint: a stale
                                ;   slot would paint a spurious pip on the
                                ;   first damage numeral of the next battle
        sta     f:$7e0000+OT6_RUNICPAID ; nor a stale runic-earn latch: a
                                ;   stale bit here suppresses a real earn
                                ;   rather than costing a no-op
        sta     f:$7e0000+OT6_RUNICTURNS      ; nor a standing Runic nobody
        sta     f:$7e0000+OT6_RUNICTURNS+2    ;   raised.  four explicit
        sta     f:$7e0000+OT6_RUNICTURNS+4    ;   stores rather than a loop;
        sta     f:$7e0000+OT6_RUNICTURNS+6    ;   only the character offsets
                                ;   (0/2/4/6) are ever read, and a stale byte
                                ;   would give the next battle's Celes a
                                ;   standing magic shield she never paid for
        sta     f:$7e0000+OT6_UNCTL     ; nor a stale "the engine is driving
                                ;   this one" latch (#236): it would hand the
                                ;   first uncontrolled swing of this battle a
                                ;   dump nobody earned.  Its twin, the hurt
                                ;   line OT6_HPMARK, is cleared with the
                                ;   shadow below, where the stores are 16-bit
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
                                ;   +$18 reveal-pending (stale pending
                                ;   would commit last battle's reveals onto
                                ;   this battle's species) and +$04 wallet
                                ;   cur/prev (stale words would blank/
                                ;   paint random menu-map cells)
        bcc     @clr
                                ; the shadow now lives at $ecf1, so it is no
                                ; longer contiguous with MAPBASE/ATKCLASS/
                                ; FONTDIRTY and this second loop is required
        ldx     #$0000
@clr2:  sta     f:$7e0000+OT6_MAPBASE,x
        inx
        inx
        cpx     #$0004          ; $57b6-$57b9: map base, atkclass, fontdirty
        bcc     @clr2           ;   stops at $57ba: the $57ba-$57bf strip
                                ;   (spare word + random-encounter flags)
                                ;   must survive init (see the strip's
                                ;   block comment at OT6_RANDPEND)
        sta     f:$7e0000+OT6_HPMARK    ; #236: nobody has a hurt line yet,
        sta     f:$7e0000+OT6_HPMARK+2  ;   and 0 reads as "has not acted in
        sta     f:$7e0000+OT6_HPMARK+4  ;   this battle" in Ot6Retaliate.  A
        sta     f:$7e0000+OT6_HPMARK+6  ;   stale line from the last battle
                                        ;   would read as a grudge nobody
                                        ;   earned, so it is cleared here and
                                        ;   not left to the shadow loop above,
                                        ;   which stops at $ed61
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

; [ a character's BP bank moved; repaint the list that is drawing it ]

; An open ability list derives what it draws from the bank at the moment its
; rows are staged, and nothing re-stages them: Ot6BushidoRowGrey greys a kit
; row whose boost exceeds the caster's bank (ot6_cmdmenu.asm:385), so a bank
; that moved behind an open window left the window claiming a row was
; reachable when Ot6BushidoConfirm would refuse it, or greyed when it would
; not.  Every writer of a character's bank calls this: Ot6ActionEnd's charge
; arm and its regen arm, Ot6RunicBP, Ot6CoverBP, Ot6Filch and Ot6Bestow.
; Ot6InitBP does not, deliberately -- no menu is open at battle init.
;
; The request byte and the gate that spends it are OT6_RESTAGE and
; Ot6RestageGate_ext in ot6_hud.asm.  Detection sits here, at the writers,
; rather than as a change detector in the gate, because the gate is polled
; once per battle frame and none of these writers is per-frame code.
;
; The test is for the kit window ($30, tools shell) only, not the magic list
; ($0e): the magic list does not read the BP bank at all -- its greys are
; Ot6AbilityGrey's MP test and its prices are Ot6FoldPrices' fold of the
; caster's own PENDING boost -- so raising a request for it here would
; re-stage rows under the player's cursor for a value that window does not
; draw.  The only reader of the bank that can go stale is a kit window whose
; rows are already staged; a kit window still opening ($2e) stages from the
; live bank on its own.
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
        jsr     Ot6RevealCommit ; any reveal this action banked and no
                                ;   numeral displayed (a 0-damage or
                                ;   numeral-less script) commits no later
                                ;   than the action's own end
        txa                     ; width-neutral character test
        cmp     #$08
        bcs     done            ; monsters have no bp
        longa                   ; #236: where this actor stands as its OWN
        lda     $3bf4,x         ;   turn ends is the line a later hit is
        sta     f:$7e0000+OT6_HPMARK,x  ;   measured against.  Drawn on both
        shorta0                 ;   arms and on every character turn, so the
                                ;   grudge is always "since I last swung"
        txa                     ; the live pip cell follows this actor
        lsr                     ;   entity offset -> character slot
        sta     f:$7e0000+OT6_PIPSLOT
        lda     #32             ;   for ~half a second past this charge, so
        sta     f:$7e0000+OT6_PIPTAIL   ;   the drop lands on screen even
                                ;   when no battle menu is open at resolution
        lda     $3018,x         ; the round boundary for the True Knight
        eor     #$ff            ;   cover earn.  this actor's turn is ending,
        and     f:$7e0000+OT6_COVERPAID  ;   so his next cover pays again:
        sta     f:$7e0000+OT6_COVERPAID  ;   the same tick that decides his
                                ;   regen also re-arms his reaction (the
                                ;   boundary Runic's own machinery implies;
                                ;   see Ot6CoverBP, ot6_cover.asm)
        lda     $3018,x         ; and the same boundary for Runic's own
        eor     #$ff            ;   absorb earn: this actor's turn ending
        and     f:$7e0000+OT6_RUNICPAID  ;   re-arms his next absorb.
        sta     f:$7e0000+OT6_RUNICPAID  ;   Separate ledger from COVERPAID
                                ;   on purpose: see OT6_RUNICPAID in
                                ;   ot6_memory.inc.
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
        ; the pending is gone, so this caster's magic rows must fall back
        ; off the folded prices Ot6FoldPrices put on them.  Same request bit
        ; Ot6Boost sets when the boost goes up (ot6_hud.asm); the walk is
        ; self-restoring at 0 tier steps, so this is the whole fallback.
        ; Placed on the spend arm only: @gain never changed a price.
        lda     $3204,x
        ora     #$80            ; vanilla's "recheck enabled magic" request
        sta     $3204,x
        jsr     Ot6BankMoved    ; and the bank moved, so an open kit
                                ;   window's BP grey is stale
        bra     done
@gain:  lda     OT6_BP_CLASS,x
        cmp     #$05
        bcs     done            ; capped at 5
        inc
        sta     OT6_BP_CLASS,x
        jsr     Ot6BankMoved    ; same on the regen arm.  the two arms are
                                ;   marked separately, and not at `done`,
                                ;   because `done` is also where a monster and
                                ;   a capped-away regen leave, neither of which
                                ;   moved a bank
        ; the backstop for a deferred cover pip.  Reached by every actor,
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
;   - once per round (OT6_RUNICPAID), the same latch True Knight's cover
;     earn uses.
;
; ---- capped once per round: why ----
;
; The earn is per absorb, and RunicEffect pays every absorbing entity on
; every absorbable cast, so an uncapped earn against a multi-turn stance
; can pay more BP than the raise spent (three enemy casters against a
; three-turn stance is up to nine earns against a three-point spend).  The
; cap makes a raised stance BP-neutral over its own duration: the raise
; costs one action, and gains land only up to once per round.
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
        ; the stance outlives the absorb while its duration runs.
        ; RunicEffect cleared $3e4c.2 four instructions after it decided
        ; this entity was absorbing (:8670-8671) and before the status gate
        ; that let it through; putting the bit back here, past every gate
        ; and on the far side of the enrolment, extends the stance without
        ; re-deriving one byte of vanilla's eligibility.
        ;
        ; db-relative rather than long here because the 65816 has no `lda
        ; long,y`, only long,x.  That is safe at this site: the two
        ; instructions above are vanilla's own `lda $3e4c,y`
        ; and this proc depends on db = $7e for them.
        lda     OT6_RUNICTURNS,y
        beq     @earn           ; 0 = vanilla Runic: one absorb, then gone
        lda     $3e4c,y
        ora     #$04
        sta     $3e4c,y
@earn:  lda     $3018,y         ; this character's bit ($01/$02/$04/$08)
        and     f:$7e0000+OT6_RUNICPAID
        bne     done            ; already banked an absorb this round
        lda     OT6_BP_CLASS,y
        cmp     #$05
        bcs     done            ; the bank cap holds; an absorb never wraps
        inc
        sta     OT6_BP_CLASS,y
        lda     $3018,y         ; latch: paid this round.  set only when a pip
        ora     f:$7e0000+OT6_RUNICPAID  ;   was really banked, so a capped-away
        sta     f:$7e0000+OT6_RUNICPAID  ;   earn at 5 bp costs nothing:
                                ;   inside one round nothing but her own
                                ;   action can lower a held character's
                                ;   bank, and that action is the boundary
                                ;   that clears this latch
        jsr     Ot6BankMoved    ; an absorb is the reactive case the
                                ;   kit window could not see -- Celes's bank
                                ;   rises with her own window open and nothing
                                ;   else happening
done:   rtl
.endproc

; ------------------------------------------------------------------------------

; [ boost buys Runic a duration, the raise ]
;
; Boost N (1-3) = the stance stands for N of Celes's own turns beyond the
; one that raised it, and she acts freely on every one of them.
;
; Vanilla ends the stance in QueueAction (battle_main.asm:511) because she
; acted, so the only way she can act without dropping it is for the stance
; to outlive her action -- duration is the only lever that lets her keep
; acting under it.  So the ladder is 1/2/3 turns of shield she can act
; through.
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

; [ boost buys Runic a duration, surviving her own turn ]
;
; QueueAction clears the runic and retort bits on every action any entity
; queues (battle_main.asm:511-513, `and #$fa`), which is what makes vanilla
; Runic cost the turn it protects: raise it, and your next turn ends it.
; This hook runs immediately after that clear and puts the runic bit back
; while the duration lasts, spending one turn of it each time.
;
; It runs after vanilla's clear rather than replacing it: the retort
; bit ($3e4c.0) is cleared by the same instruction and is unrelated, so
; leaving vanilla's three instructions alone and re-setting one bit is
; both smaller (4 bytes against 8) and harder to get wrong.
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
                                ;   would be delivered but never charged
        lda     OT6_BOOST_REVEALED,x         ; pending boost level
        bne     spend           ; the player bought this one: nothing to
                                ;   decide, it just swings
        jsr     Ot6Retaliate    ; ot6 #236: nobody bought one, so this may be
                                ;   an actor the ENGINE is driving, banking
                                ;   with no way to spend.  If it is, and it
                                ;   has been hurt, this swing carries its bank
        lda     OT6_BOOST_REVEALED,x
        beq     done
        ; The `clc / adc $3a70 / sta $3a70` tail below is DERIVED by
        ; battle_healpolicy.lua and battle_retaliate.lua out of the first 32
        ; bytes of this proc, so the decision above stays short and the
        ; arithmetic stays where those scans can still find it.
spend:  asl                     ; two swings per bp
        clc
        adc     $3a70
        sta     $3a70
done:   rtl
.endproc

; ------------------------------------------------------------------------------

; [ an uncontrolled actor that got hurt dumps its bank on this swing ]

; #236.  The boost economy was inert for anyone the player was not driving:
; every writer of OT6_BOOST_REVEALED is a player-driven path (the boost
; press, the SwdTech confirm, the thief submenu, the Slot reels), so
; Ot6ActionEnd took its @gain arm on every one of their turns and the bank
; climbed to the cap of 5 and stayed there.  Measured, not assumed: a
; berserked EDGAR in battle 66 banked 1-2-3-4-5 over four engine-chosen
; Fights while Ot6FightBoost saw pending 0 every time and Ot6ActionEnd took
; the charge arm zero times (build/lab/uncontrolled/probe_bank.log,
; retained as build/attempts/<branch>/lab/uncontrolled/probe_bank.log).
;
; The owner's rule: bank normally; when you get hit, dump the whole bank on
; your next attack.  So this is the one writer of the pending byte that is
; not a player's press, and the three questions it answers are:
;
;   who   -- OT6_UNCTL, the engine's own decision (see ot6_memory.inc).  Not
;            a status test: Berserk and Muddle are status bits, Umaro is a
;            character and the Colosseum is a mode, and re-deriving that
;            list here would be four ways to disagree with vanilla.  The
;            latch is set where vanilla chooses the action FOR the actor and
;            cleared where vanilla hands the player the window.
;   when  -- OT6_HPMARK, the hp it stood on when its OWN last turn ended.
;            "Got hit" is IT STANDS LOWER THAN THAT.  A miss changes
;            nothing, a connect for 0 changes nothing, and several small
;            hits add up to one grudge -- which is what "hurt them and they
;            hit back harder" means at the screen.  The first shape of this
;            was a flag set on ApplyDmgHP's damage-taken arm;
;            battle_trueknight's frame-budget canary measured that site as
;            unaffordable at the jsl alone, so the line moved to
;            Ot6ActionEnd, which runs once a turn.  See OT6_HPMARK in
;            ot6_memory.inc for the numbers and the logs.
;   how much -- the whole bank, capped at 3 because Ot6Boost caps every spend
;            at 3 while the bank caps at 5.  Three pips is +6 swings, so 4
;            landed hits with one weapon and 8 with a Genji pair -- four or
;            eight shield-chip opportunities off one provoked swing.  It
;            costs BP and no MP: Fight is free, Ot6BoostDmg exempts command
;            $00/$06 from the damage multiplier, and Ot6AbilityCost and
;            Ot6QueueFold both ran at queue time, long before this.
;
; A player's own boost wins: a nonzero pending here was bought with an R
; press (or a Slot commit, or a SwdTech confirm) and is left exactly alone.
; An empty bank dumps nothing and leaves the grudge standing, so the actor
; hits back on the first turn it has anything to hit back with.
;
; WHAT THIS DOES NOT COVER, recorded so it is not rediscovered:
;
;   * Umaro's three special arms.  The dump hangs off Ot6FightBoost, which
;     hangs off FightAttack, and only one of UmaroAttackTbl's four slots IS
;     FightAttack -- with no relics 158 of 253 rolls (RandBitRateTbl row 0,
;     $9e/$5f) take that plain swing and carry the dump, and his Throw,
;     Storm and Charge do not.  Giving those three the swings half needs a
;     second hook at their own ExecAttack entries.  Umaro is World of Ruin
;     content, so this is designed and read off the ROM, never played.
;   * An AI-SCRIPTED character -- Biggs and Wedge in the opening, and any
;     set piece that drives a party member from a script.  QueueAction sends
;     them to ExecMonsterAction before it ever reaches the no-pending-action
;     arm, so they never touch RandCharAction and never set OT6_UNCTL: they
;     still bank with nothing to spend it on, exactly as everyone did before
;     this.  One more latch site at that branch would close it.
;
; jsr from Ot6FightBoost only, inside its character and counterattack guards
; and only once it has established that nobody bought a boost for this
; action.  a8/i16, x = the attacker's entity offset.  Clobbers A, leaves the
; caller's a8.

.proc Ot6Retaliate
        .a8
        .i16
        lda     f:$7e0000+OT6_UNCTL     ; is the engine driving ANYONE?  This
        beq     out                     ;   whole-byte test first, because on
                                        ;   every ordinary turn of every
                                        ;   ordinary battle it answers no in
                                        ;   one long load and a branch
        and     $3018,x
        beq     out                     ; ...and is this one of them?
        lda     OT6_BP_CLASS,x
        beq     out                     ; an empty bank spends nothing, and
                                        ;   must not eat the grudge: the dump
                                        ;   waits for the first pip
        longa
        lda     f:$7e0000+OT6_HPMARK,x  ; where it stood when its own last
        beq     unhurt                  ;   turn ended (0 = it has not acted
        cmp     $3bf4,x                 ;   yet, so there is no line)
        bcc     unhurt                  ; it stands ABOVE the line
        beq     unhurt                  ; ...or exactly on it: nothing hurt it
        lda     $3bf4,x                 ; hurt.  The line moves to where it
        sta     f:$7e0000+OT6_HPMARK,x  ;   stands NOW, so one hurt buys one
        shorta0                         ;   dump and the next needs a new hit
        lda     OT6_BP_CLASS,x
        cmp     #$04
        bcc     spend
        lda     #$03                    ; the spend caps at 3 (Ot6Boost's own
                                        ;   ceiling) while the bank caps at 5
spend:  sta     OT6_BOOST_REVEALED,x    ; Ot6ActionEnd charges exactly this
        rts
unhurt: shorta0
out:    rts
.endproc

; ------------------------------------------------------------------------------

; [ the engine, not the player, is choosing this character's action ]

; #236.  jsl from the head of RandCharAction (battle_main.asm), vanilla's
; own "select berserk/zombie/muddled/charmed/colosseum action".  That one
; site is reached from QueueAction's no-pending-action arm, which a player-
; driven character never takes (their queued command leaves $32cc valid),
; and which Dance, Rage and Magitek peel off before it -- so it is exactly
; the set the owner named, plus Umaro, whom CheckPlayerAction refuses a
; window by name and who therefore arrives here with every other arm
; declined.
;
; a8 at the call site; A is dead there (RandCharAction's first instruction
; is `txa`) but is preserved anyway, along with every flag.  x = the entity
; whose action is being chosen; monsters are ignored.  Index width is the
; caller's and is not touched.

.proc Ot6UnctlMark
        .a8
        php
        longa
        pha
        shorta0
        .a8
        txa                     ; width-neutral character test
        cmp     #$08
        bcs     out             ; monsters have no bank
        lda     $3018,x
        ora     f:$7e0000+OT6_UNCTL
        sta     f:$7e0000+OT6_UNCTL
out:    longa
        pla
        plp
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ ...and the player has this one back ]

; #236, the other side of the same vanilla decision: jsl from
; CheckPlayerAction at the instruction that opens the battle menu, which is
; reached only after every refusal (monster, Umaro, ai script, colosseum,
; untargetable, seized/charmed, and CheckStatus's dead/petrified/zombie/
; asleep/muddled/berserked/dancing/hidden/raging list) has declined.
;
; Clearing HERE rather than in Ot6ActionEnd is what keeps a cured status
; from leaving a dump armed: the latch says who decided the action last,
; and the window opening is the moment the answer changes back.
;
; a8 at the call site, A dead (the caller jumps straight into the menu);
; preserved anyway.  x = the character.

.proc Ot6UnctlClear
        .a8
        php
        longa
        pha
        shorta0
        .a8
        txa
        cmp     #$08
        bcs     out
        lda     $3018,x
        eor     #$ff
        and     f:$7e0000+OT6_UNCTL
        sta     f:$7e0000+OT6_UNCTL
out:    longa
        pla
        plp
        rtl
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
; ---- the folded tier is also priced as that tier ----
;
; BP buys tempo.  MP buys power.  The fold re-prices what it queued, from
; the tier's own MagicProp record and through the same relic arithmetic the
; learned path uses (Ot6SpellMP below), so a folded cast costs full MP for
; its tier rather than the base spell's MP.  This happens at queue time, on
; the same A the queue consumed, so it does not depend on any menu-side
; recheck having run first.  Ot6FoldPrices keeps the displayed price
; agreeing with it.
;
; ---- and a spell that cannot fold pays the escalation instead ----
;
; #219: every boosted ability but Fight costs escalating MP.  A spell outside
; the tier families has no tier to buy, so its boost buys Ot6BoostDmg's
; x2/x4/x8 and its price takes x2.5 per level (Ot6BoostPriceFor).  That is the
; same three commands plus summon ($19), which joins the gate here for its
; price alone: espers are in no family, so the fold arm never sees one.
; Lore ($0c) reaches this proc with the real lore id in $3a7b, the id
; MagicProp is indexed by, so one arm serves magic, x-magic, lore and summon.
;
; ---- the counterattack guard cannot use the global "counter executing" flag ----
;
; GetMPCost's character arm reads the caster's spell-list cost byte
; (battle_main.asm:13296), already moved to the folded tier's price by
; Ot6FoldPrices when the boost went up, so a stale early-out here would
; leave the folded price standing on an unfolded spell.
;
; $b1.0 ("a counterattack is executing") is global: ExecRetal sets it for
; its whole run (:12676) and an ordinary action can be queued while it is
; set.  The guard instead compares the queue slot just written (y/2)
; against the actor's own counterattack pointer $32cd,x, written by
; CreateRetalAction (:13211) and left untouched by CreateNormalAction
; (:13228) -- only a real counterattack matches.
;
; Untaught tiers still fold: a borrowed Fire folds to Fire 3 whether or not
; the caster ever learned Fire 3.  The price must come from MagicProp
; rather than the caster's own list for that reason: an unlearned row's
; list cost is 0 (AddToSpellList_01, battle_main.asm:14553, `clr_a / sta
; ($f4),y`), so pricing the fold off the list would make every untaught
; tier free.

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
        ; header paragraph above.  y/2 is the command-list pointer this call
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
        beq     @cmdok          ; $0c lore
        cmp     #$19
        bne     @keep           ; $19 summon
@cmdok: txa                     ; width-neutral character test
        cmp     #$08
        bcs     @keep           ; monsters never boost
        jsl     Ot6FoldSteps    ; pending boost -> OT6_SCR_BIT tier steps
        beq     @keep           ; unboosted: nothing to fold and nothing to
                                ;   escalate
        lda     $3a7b
        cmp     #$99            ; Step Mine, the one spell in the game whose
        beq     @keep           ;   price is not MagicProp's: battle init
                                ;   derives it from the play clock straight
                                ;   into the list row (battle_main.asm:14670)
                                ;   and there is nothing here to re-derive it
                                ;   from, so it stays vanilla on both surfaces
        lda     $3a7a
        cmp     #$19
        beq     @summon
        lda     $3a7b           ; attack id: the real spell or lore id
        jsl     Ot6InFoldTbl    ; carry set = a tier family (A preserved)
        bcc     @escalate
        jsl     Ot6FoldTier     ; -> the tier this boost buys
        cmp     $3a7b
        beq     @keep           ; a tier the caster already owns: only heads
                                ;   fold, and Ot6BoostDmg gives a non-head no
                                ;   multiplier, so neither its id nor its price
                                ;   moves
        sta     $3a7b           ; queue the folded tier
        jsl     Ot6SpellMP      ; and price it as that tier.  x is still
        sta     $3620,y         ;   the actor, y still the queue slot, so this
        bra     @keep           ;   overwrites the base cost :13249 just banked
@summon:
        lda     $3a7b           ; Cmd_19 names the esper by index; the record
        cmp     #$1b            ;   its MP lives in is index + $36, which is
        bcs     @keep           ;   also what Ot6FoldPrices priced row 0 from.
        clc                     ;   The range check is not decoration: the +$36
        adc     #$36            ;   wraps in 8 bits, so a $ff attack byte (what
                                ;   init_buf_input leaves, and what anything
                                ;   that reaches command $19 without the esper
                                ;   row carries) would price as spell $35
@escalate:
        ; not a tier family: boost buys this cast Ot6BoostDmg's x2/x4/x8, so
        ; the price escalates with it (#219).  Re-derived here, on the same A
        ; the queue consumes, so the charge does not depend on the menu-side
        ; recheck (Ot6FoldPrices) having run first -- the same rule the fold
        ; above keeps.  Both arrive at one number because both walk
        ; MagicProp -> Ot6SpellMP -> Ot6BoostPriceFor.
        jsl     Ot6SpellMP      ; the base price, relics included
        jsl     Ot6BoostPriceFor
        sta     $3620,y
@keep:  pla
        plp
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ how many tiers does this character's pending boost buy? ]
;
; the 0/1/2 clamp, shared by the three sites that need it: queue-time fold,
; list preview, and the price walk.  the cap is two tiers because that is
; where every family's table runs out: Fire 3
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

; [ what a boost costs: the one price-scaling authority ]
;
; price = min(99, floor(base * 2.5^boost + 0.5)) for boost 0..3, i.e. x1 /
; x2.5 / x6.25 / x15.625 against the base price, every result capped at 99
; (#219).  Boost multiplies a damage verb by x2/x4/x8 (Ot6BoostDmg), so MP
; scales slightly faster than damage; the ratio matches magic's own -ra -> -ga
; step, where vanilla pays ~2.5x the MP for ~2x the power.
;
; Exact in integers, with no fixed point anywhere: 2.5^n = 5^n / 2^n, so
;     floor(base * 2.5^n + 1/2) = (base * 5^n + 2^(n-1)) >> n
; and that in turn is ((base * 5^n) >> (n-1)) incremented and halved, which is
; what the body does.  The two are equal for every byte base at n = 1, 2 and
; 3: the discarded bits can only move the rounded result when base * 5^n is
; congruent to a value mod 2^n that 5^n (odd) cannot produce.  n multiply-by-5
; steps, n-1 shifts, one round.  base * 5^3 = 125 * 255 = 31875 at worst, so
; the 16-bit product cannot overflow for any byte cost.
;
; The cap is the display's, not taste's: every OT6 price drawer renders two
; digits (ListText cmd $02, btlgfx_main.asm:15045; Ot6LoadoutDrawCost,
; ot6_loadout_page.asm:375), so 100 would print as punctuation.  The owner's
; ruling is that the scaling flattens there rather than that the drawers grow
; (#219, ruling 1): Spiraler 50 costs 99 from boost 1 up, and Bum Rush,
; already at the cap, never moves at all.  The one thing the cap may not do
; is make a boost cheaper than not boosting; see the floor at @round.
;
; All three surfaces that state a price -- the drawn number, the grey, and the
; charge -- reach this proc, so they cannot disagree about what a boost costs
; (#219, ruling 3).  There is no RAM scratch: the working product lives in a
; stack-relative slot, because this runs inside Ot6FoldPrices' walk (which
; owns OT6_SCR_BIT/IDX/SLOT2) and inside the list decorators (which share the
; icon path's OT6_SCR_COLS).
;
; in: A = the base cost (a byte), X = the caster's entity offset.
; out: A = the scaled cost, a byte.  a8/i16, db=$7e; preserves X and Y.  rtl.
.proc Ot6BoostPriceFor
        .a8
        .i16
.if ::OT6_BOOST_PRICE = 0       ; :: forces the file-scope flag from in-proc
        rtl                     ; the pre-#219 economy, for the A/B only: A
                                ;   already holds the base, and a boost is
                                ;   free at every level.  Every surface that
                                ;   states a price comes through here, so the
                                ;   drawn number, the grey and the charge move
                                ;   together, exactly as they did before #219.
.endif
        php
        rep     #$30            ; a16/i16: a 16-bit product and word pushes
        .a16
        phy                     ; the caller's Y
        and     #$00ff          ; A = the base cost, zero-extended
        pha                     ; [$01,s] the base
        sep     #$20
        .a8
        lda     OT6_BOOST_REVEALED,x    ; this caster's pending boost
        cmp     #$04
        bcc     :+
        lda     #$03            ; defensive: Ot6Boost already caps the spend at 3
:       rep     #$20
        .a16
        and     #$00ff
        bne     @scale
        pla                     ; unboosted: the base price stands, unchanged
        bra     @out
@scale: phx                     ; the caller's X, free from here: the boost is
                                ;   read, and X becomes the shift counter
        tay                     ; y = n, the multiply counter
        pha                     ; [$01,s] n, [$05,s] the base
        lda     $05,s
        pha                     ; [$01,s] the multiply temp, n at $03,s
@x5:    sta     $01,s           ; product *= 5, n times -> base * 5^n
        asl
        asl                     ;   x4 (no carry: 255*25*4 = 25500)
        clc
        adc     $01,s           ;   + itself = x5
        dey
        bne     @x5
        sta     $01,s           ; hand the product back and release the temp
        pla
        plx                     ; x = n again, for the shift (the 65816 has no
                                ;   stack-relative ldy/ldx, and pulling is what
                                ;   frees the slot anyway)
@shr:   dex                     ; >> (n-1) ...
        beq     @round
        lsr
        bra     @shr
@round: inc                     ; ... then (q + 1) >> 1, the rounding step
        lsr
        cmp     #100
        bcc     :+
        lda     #99             ; the two-digit ceiling (#219, ruling 1)
:       cmp     $03,s           ; ...but the ceiling never makes a boost
        bcs     :+              ;   CHEAPER than not boosting.  One price in
        lda     $03,s           ;   the game is already above it: Phoenix at
                                ;   110 (MagicProp +$05), which is legal
                                ;   because the summon window draws three
                                ;   digits (ListText cmd $16).  Capping a
                                ;   boosted Phoenix to 99 would pay less for
                                ;   more, so the base stands instead
:       plx                     ; the caller's X back
        ply                     ; drop the base
@out:   sep     #$20
        .a8
        ply                     ; the caller's Y
        plp
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ price a base cost for the caster whose menu is open ]
;
; Ot6BoostPriceFor's menu-side entry.  The battle list decorators hold a row
; and a price but no entity offset; the active caster is $62ca, the same slot
; DrawMagicListText and Ot6AbilityGrey index by, so the number a row draws and
; the grey beside it come from the one caster whose boost the L/R pips show.
;
; in: A = the base cost.  out: A = the scaled cost.  a8/i16, db=$7e;
; preserves X and Y.  rtl.
.proc Ot6PendPrice
        .a8
        .i16
        phx
        phy
        pha                     ; park the base under the slot arithmetic
        lda     $62ca           ; active caster slot
        longa
        and     #$0003
        asl                     ; slot -> entity offset (stride 2: chars 0/2/4/6)
        tax
        shorta0
        pla
        jsl     Ot6BoostPriceFor
        ply
        plx
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ is this spell id anywhere in a tier family?  the escalation's own gate ]
;
; Ot6BoostDmg asks the same question of $3a7d, byte for byte against the same
; table, and answers it the same way: a spell in the fold table gets no damage
; multiplier, because boost spent on it bought a tier (a family head) or
; bought nothing at all (a tier the caster already owns, which does not fold
; again -- only heads fold).  Price follows damage: exactly the ids this
; returns carry SET for are the ones #219 leaves on their vanilla MP, and
; exactly the ones it returns carry CLEAR for take the 2.5x.  One scan, so the
; two halves of the boost canon cannot come to different answers about the
; same spell.
;
; in: A = spell id.  out: carry set = in a tier family; A preserved.
; a8/i16; preserves X and Y.  rtl.
.proc Ot6InFoldTbl
        .a8
        .i16
        phx
        pha                     ; [$01,s] the id, matched against every entry
        ldx     #$0000
@scan:  lda     f:Ot6FoldTbl,x
        cmp     $01,s
        beq     @yes
        inx                     ; stride 1: heads AND tiers both count here,
        cpx     #$0018          ;   unlike Ot6FoldTier's stride-3 head scan
        bcc     @scan
        pla
        plx
        clc
        rtl
@yes:   pla
        plx
        sec
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ fold one spell id up the tier table: the one authority for the fold ]
;
; the table scan, shared by three call sites: Ot6QueueFold (the charge and
; the cast), Ot6PreviewList_ext (the name the player reads) and
; Ot6FoldPrices (the number and the grey).  Those three must agree on which
; tier a boost buys, or the list will disagree with the cast, so there is
; one scan and they all call it.
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
; Deliberately re-derived from MagicProp rather than read out of the
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
; fits a byte with room to spare; the most expensive is Life 2 at 60.
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

; [ what one spell costs this caster, boost included: magic's price authority ]
;
; The magic-side twin of Ot6BoostPriceFor's use on the kit verbs, and the one
; place the four magic surfaces (the list's number, its grey, the confirm and
; the charge) get their answer from.
;
; Two rules, and Ot6InFoldTbl decides which applies rather than a second
; opinion doing it:
;   * a tier-family spell keeps its vanilla MP.  A family head folds up a tier
;     and pays that tier's own price -- the fold IS the escalation, and a
;     steeper one than 2.5x (Fire 4 -> Fire 2 20 -> Fire 3 51).  A tier the
;     caster already owns does not fold again and Ot6BoostDmg gives it no
;     multiplier either, so nothing about its price moves.  That is #219's
;     "unchanged, already escalating by tier".
;   * everything else -- Drain, Quake, Ultima, every Lore, an equipped esper's
;     summon -- is a multiplier verb under Ot6BoostDmg, so it takes the 2.5x.
;
; in: A = the spell id (an esper is its MagicProp record, index + $36),
; X = the caster's entity offset, OT6_SCR_BIT = the tier steps his boost buys
; (Ot6FoldSteps').  out: A = the price.  a8/i16, db=$7e; preserves X and Y.
.proc Ot6MagicPrice
        .a8
        .i16
        jsl     Ot6InFoldTbl    ; carry set = tier family (A preserved)
        bcs     @tier
        jsl     Ot6SpellMP      ; the base price, relics included
        jml     Ot6BoostPriceFor        ; ...x2.5 per pending boost; its rtl
                                        ;   returns for us
@tier:  jsl     Ot6FoldTier     ; a head folds; a tier comes back unchanged
        jml     Ot6SpellMP      ; and either way it is priced as itself, vanilla
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
; The price, the grey and the confirm gate also follow the folded tier;
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

; [ the magic list shows what a boosted cast will really cost, and greys on it ]
;
; Ot6QueueFold charges the folded tier; without this the list would still
; show the base spell's number beside the folded name ("Fire 3 ... 4", and
; then 51 MP gone) and the confirm would accept a cast the universal
; insufficient-MP gate then fizzles.  Since #219 the same is true of every
; spell that does not fold: its price escalates x2.5 per pending boost, so
; the walk below covers the caster's whole list rather than the eight family
; heads, and Ot6MagicPrice decides per row which of the two rules applies.
;
; The walk is driven off the master spell list $3034 (position -> real id)
; rather than off the rows themselves, because a lore's row byte is its id
; minus $8b (battle_main.asm:14648) and would be indistinguishable from a
; magic id.  Position p is row p+1; row 0 is the equipped esper, whose row
; byte is an esper index and whose MagicProp record is that index + $36.
;
; Cost: 78 rows instead of 8 families, but an unlearned row leaves after two
; loads, and this is a burst on a recheck request (an L/R edge, or the end of
; an action), never per-frame work -- the same budget note Ot6Boost's call
; site already carries.
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
; Three of those four live in bank C1.  A hook in any of them would be three
; hooks that have to agree; moving the byte they all read costs zero C1 bytes
; and makes it structurally impossible for the four to disagree.  (C1 can now
; carry flag-gated OT6 code -- btlgfx is assembled per flag, see
; Ot6AbilityGrey's header -- so this is a design choice about single authority,
; not a build constraint any more.)
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
        ; different ways per row (master-list cursor, caster, list row), so
        ; the two invariants live in scratch and x is working state.
        stx     OT6_SCR_SLOT2   ; the caster's entity offset
        jsl     Ot6FoldSteps    ; -> OT6_SCR_BIT (0 restores the base prices)
        ; --- row 0: the equipped esper, if he has one ---
        ; The $ff test below is the whole gate, and it is sufficient:
        ; InitBattle $ff-fills $2000-$341f before its one call to InitSkills
        ; (battle_main.asm:6096), the list-fill loop never writes row 0
        ; (:14644 starts at row 1), and ValidateSpellList writes row 0 only
        ; for a character who really has magicite equipped (:14556-14566).
        ; Not $3f2e: that mask means "has already summoned this battle", the
        ; once-per-battle latch UpdateEnabledMagic uses to disable the row,
        ; and a disabled row still wants the right number beside it.
        longa
        lda     $302c,x
        tax                     ; -> the caster's first list row
        shorta0
        lda     a:$0000,x       ; the esper index ValidateSpellList stored
        cmp     #$1b            ; $ff (no magicite) or anything outside the
        bcs     @rows           ;   esper range: no summon row to price.  The
                                ;   same range check Ot6QueueFold's @summon
                                ;   makes, so the two cannot price different
                                ;   records for one row
        clc
        adc     #$36            ; -> the esper's own MagicProp record
        phx                     ; the row
        ldx     OT6_SCR_SLOT2   ; the caster (Ot6MagicPrice wants the entity)
        jsl     Ot6MagicPrice
        plx                     ; the row back
        sta     a:$0003,x
        ; --- rows 1..78: every spell and lore anybody in the party knows ---
@rows:  ldx     #$0000
        stx     OT6_SCR_IDX     ; p, the master-list position (word store: the
                                ;   high byte must stay 0 for the bumps below)
@row:   ldx     OT6_SCR_IDX
        lda     $3034,x         ; the master spell list: position -> the REAL
                                ;   id ($00-$35 magic, $8b-$a2 lore, $ff =
                                ;   nobody knows it).  The caster's own row
                                ;   byte cannot stand in for this: a lore is
                                ;   stored there as id - $8b
                                ;   (battle_main.asm:14648), which collides
                                ;   with the magic ids
        cmp     #$ff
        beq     @next           ; nobody knows it: dead in every list
        cmp     #$99
        beq     @next           ; Step Mine: its price is the play clock's,
                                ;   not MagicProp's (battle_main.asm:14670),
                                ;   so recomputing the row would overwrite the
                                ;   one price in the game this walk cannot
                                ;   reproduce.  Ot6QueueFold skips it too, so
                                ;   both surfaces stay vanilla together
        pha                     ; [$01,s] the real id
        ldx     OT6_SCR_SLOT2   ; the caster
        longa
        lda     OT6_SCR_IDX
        inc                     ; row = position + 1 (row 0 is the esper), the
        asl2                    ;   same arithmetic battle init used to fill
        clc                     ;   the lists (:14644) and GetMPCost uses to
        adc     $302c,x         ;   read one back (:13268)
        tax                     ; -> this caster's row for this spell
        shorta0
        lda     a:$0000,x       ; the row's id byte
        bmi     @drop           ; $ff: not learned.  leave the row alone; it
                                ;   is already disabled, and a price on a row
                                ;   the caster cannot pick means nothing
        phx                     ; the row
        lda     $03,s           ; the real id (parked under the row pointer)
        ldx     OT6_SCR_SLOT2   ; the caster
        jsl     Ot6MagicPrice   ; -> the fold's tier price, or the escalated
                                ;   one, by Ot6InFoldTbl's single answer
        plx                     ; the row back
        sta     a:$0003,x       ; the byte: grey, number, confirm and charge
@drop:  pla                     ; drop the parked id
@next:  longa
        lda     OT6_SCR_IDX
        inc
        sta     OT6_SCR_IDX
        cmp     #$004e          ; 78 rows: 54 spells + 24 lores, the same count
        shorta0                 ;   UpdateEnabledMagic's own loop walks four
        bcc     @row            ;   instructions later (:14797)
@out:   ply
        plx
        pla
        plp
        rtl
.endproc

; ------------------------------------------------------------------------------
.if OT6_MP_COSTS
; ------------------------------------------------------------------------------

; [ price a costed verb's action at queue time, OT6_MP_COSTS ]

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
; command alone (cmd $05 -> 2 MP) and never consults the id table. (routing
; it through the table would also have to avoid a collision: steal's own
; special-effect id $a4, set at execute time in Cmd_05, is already the tool
; key for Bio Blaster.) only the basic Fight command is free; every other
; verb costs MP as its kit comes online.
;
; the charge and the refusal are both already universal (they act on whatever
; $3620 -> $3a4c holds); the only magic-specific piece is the menu grey-out /
; cost display (CheckMagicEnabled), which is the menu-bank work this
; flag waits on. that is why a hidden charge must not ship enabled: the menu
; still shows these verbs no number.
;
; Which arms escalate is ONE test, the same test the damage half already
; makes (#219, refined by the owner 2026-09-17): a verb's price escalates
; exactly when Ot6BoostDmg multiplies it.  So the gate list over there IS the
; exemption list over here, and the two halves of the boost canon cannot come
; to different answers.
;
;   * @boosted (tools $09, blitz $0a) escalates: neither command is in
;     Ot6BoostDmg's gate, the row keeps one id no matter the boost, and the
;     boost buys it x2/x4/x8.  So does @dance (cmd $13, also ungated).  The
;     base price takes x2.5 per pending level, through Ot6BoostPriceFor,
;     capped at 99.
;   * @swdtech (cmd $07) is gated, so it is flat here: its BP was already
;     spent on the tech.  Ot6BushidoTier / Ot6QueueFold left $3a7b at the
;     tech the boost bought, whose own per-tech price is what is charged.
;     BP buys the tier, MP prices the cast.
;   * @steal (cmd $05) and @rage (cmd $10) are gated, so they are flat at
;     every boost level.  They are CHANCE verbs: the boost converts variance
;     into reliability across a spread of outcomes that are not merely
;     damage, and it is already paid for in BP, the scarce resource.  MP
;     scales with magnitude; BP alone pays for certainty.  Slot (cmd $0f) is
;     gated too and would be flat for the same reason; it has no arm here
;     because it is unpriced (base 0), not because it was overlooked.
;   * Filch and Bestow ride cmd $05's gate with Steal, and for them the
;     boost buys nothing at all (Ot6Bestow's header says the same), so
;     charging for it would be charging for nothing.  The whole @steal arm
;     is therefore flat, with no per-row split.
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
        beq     @dance          ; dance: flat, paid at dance-START only
        cmp     #$10
        beq     @rage           ; rage: the same shape as dance
        ; no cmd-$11 arm: Leap is free.  It is never rendered on any
        ; surface, and it shares the Fight row on the Veldt (Ot6VeldtRow,
        ; battle_main.asm), where the free floor has to survive it.  Falling
        ; out of this chain hands back vanilla's own cost for cmd $11, 0.
        cmp     #$07
        beq     @swdtech        ; swdtech: boost bought the tech tier, and the
                                ;   row it picked is priced at its own price
        cmp     #$09
        beq     @boosted        ; tools
        cmp     #$0a
        beq     @boosted        ; blitz
        pla                     ; some other verb: hand back vanilla's cost
        plp
        rtl
@steal: ; steal is not one ability; it is the first row of Locke's thief
        ; submenu, and the row the player picked is in $3a7b (see
        ; Ot6ThiefListOpen's header for why that byte is free under this
        ; command).  Filch and Bestow price from Ot6ThiefCostTbl, keyed on
        ; that byte; everything else (the Steal row itself, the $ff a
        ; Confused or AI-issued Steal queues, a Gogo mimic) falls through to
        ; Ot6StealCost, the single authority for Steal's price.
        pla                     ; drop the parked cost (0 for steal)
        lda     $3a7b           ; the row the submenu queued
        jsl     Ot6ThiefIsNew   ; carry set = filch/bestow (A preserved)
        bcc     @plainsteal
        jsl     Ot6ThiefCostFor
        plp
        rtl
@plainsteal:
        jsl     Ot6StealCost    ; the flat price, one authority, at every
                                ;   boost level.  Cmd $05 is in Ot6BoostDmg's
                                ;   gate, so the boost multiplies nothing: it
                                ;   buys the rare/guarantee ladder
                                ;   (Ot6StealBoostLevel), which is certainty
                                ;   across a spread of outcomes rather than
                                ;   magnitude, and the BP is what pays for it
        plp
        rtl
@dance: ; dance (cmd $13) is priced at the commit moment only: the mid-dance
        ; turns queue through the same CreateAction (RandDanceAction,
        ; battle_main.asm:617), but by then Cmd_13 has set the actor's DANCE
        ; status ($3ef8 bit 0).  one payment starts the whole-battle state,
        ; and every locked-in step is free.  a
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
:       jsl     Ot6DanceCost    ; dance-start: the base price, one authority
        jsl     Ot6BoostPriceFor        ; ...x2.5 per pending boost.  Dance is
                                        ;   the one possess-verb that DOES
                                        ;   escalate: cmd $13 is not in
                                        ;   Ot6BoostDmg's gate list, so every
                                        ;   step of the dance the start pays
                                        ;   for swings at x2/x4/x8.  One test,
                                        ;   and Dance lands on the other side
                                        ;   of it from Rage
        plp
        rtl
@rage:  ; rage is the other possess-verb: flat, charged once at Rage-start,
        ; and every possessed turn after it free.  The discriminator is the
        ; same shape dance uses: Cmd_10 sets the actor's RAGE status ($3ef9
        ; bit 0) on the start turn, and every later possessed turn re-enters
        ; command $10 with the bit already set.  X = attacker entity at this
        ; hook (the site contract above).  A refused start must not lock the
        ; trance for free either; that is Ot6RageStartGate's job in Cmd_10.
        pla                     ; drop the parked cost (0 for rage)
        lda     $3ef9,x         ; status 4
        lsr                     ; bit 0 = already raging (a mid-trance turn)
        bcc     :+
        lda     #$00            ; locked-in possessed turn: free
        plp
        rtl
:       jsl     Ot6RageCost     ; rage-start: the flat price, one authority,
                                ;   at every boost level.  Cmd $10 is in
                                ;   Ot6BoostDmg's gate, so the boost
                                ;   multiplies nothing: it buys the trance's
                                ;   coin (Ot6RageCoin), certainty across a
                                ;   spread of effects rather than magnitude,
                                ;   and the BP is what pays for it
        plp
        rtl
@swdtech:
        ; SwdTech's boost was already spent, on the tech: Ot6BushidoTier left
        ; $3a7b at the row the BP bought, and that row's own table price is
        ; what should be charged.  So no escalation here -- BP buys the tier,
        ; MP prices the cast, and the ladder is already monotonic in the tech
        ; index (#219: "unchanged, already escalating by tier").
        pla                     ; drop the parked cost (it is 0 for these)
        lda     $3a7b           ; the resolved attack id
        jsl     Ot6CostFor      ; pure table scan: id -> cost in A
        plp
        rtl
@boosted:
        ; Blitz and Tools keep one id no matter the boost, and boost buys them
        ; Ot6BoostDmg's x2/x4/x8, so the price is the row's times 2.5 per
        ; pending level (#219).  X is still the attacker entity (the site
        ; contract above), which is the caster Ot6BoostPriceFor reads the
        ; pending boost of.
        pla                     ; drop the parked cost (it is 0 for these)
        lda     $3a7b           ; the resolved id (attack id / tool item id)
        jsl     Ot6CostFor      ; pure table scan: id -> cost in A
        jsl     Ot6BoostPriceFor
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

; [ the second keyed table, for Locke's thief submenu ]
;
; Why a second table rather than rows in Ot6AbilityCostTbl.  The thief rows
; are $56-$58, which sit inside SwdTech's $55-$5c key range: they are
; AttackName pad slots, and SwdTech's ids are attack ids in the same space
; (SwdTech draws its names from BushidoName, which is why the pad was free;
; see Ot6ThiefListOpen).  Putting them in the shared table would break the
; disjointness Ot6CostFor's scan relies on and would price a boosted SwdTech
; row as a Filch.  Two tables, each reached from its own arm of
; Ot6AbilityCost's command gate, keeps the key spaces disjoint.
Ot6ThiefCostTbl:
        .byte   OT6_THIEF_FILCH,  6     ; Filch: shield -> boost point
        .byte   OT6_THIEF_BESTOW, 5     ; Bestow: hand a boost point to an ally
        .byte   $ff
        ; no Steal row: Ot6StealCost is its authority and the @steal arm
        ; routes the Steal row, and every Steal this menu did not issue, to
        ; that leaf.  A row here would make two numbers for one price.

; [ price one thief row by its id, Ot6CostFor's twin on the second table ]
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

; [ can the dancer pay the start?  Cmd_13's lock-out gate ]
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

; [ the Dance price: one authority for the charge and the menu ]
;
; Dance is flat, paid at start: one payment starts a whole-battle state and
; funds every subsequent turn's verb for the rest of the battle (each
; locked-in step is free), so it prices above the per-use signature verbs
; (Steal 4, Pummel 4) while staying payable from Mog's pool (base 16 MP +
; level gains).  Pure leaf, the Ot6CostFor shape: cost in A, preserves X and
; Y; rtl so the menu decorator (bank F0 via C1) and the charge read one
; number.
.proc Ot6DanceCost
        .a8
        lda     #$08
        rtl
.endproc

; [ the Steal price: the flat verb's one authority ]
;
; 4 MP.  Locke joins at Narshe holding 31 MP (LV6); 4 is between Fire's and
; Cure's cost as a fraction of that pool, and matches the cheapest row of
; each ladder kit (Pummel $5d, Dispatch $55, and AutoCrossbow $aa are all 4).
;
; What this price still cannot do: it cannot be displayed.  Steal is a
; top-level battle command, and command_window_data_set (btlgfx_main.asm:10099)
; writes two things per row, the command byte and a GetTextColor
; colour off the DISABLED flag (:10704, `and #$80`), through MenuText::_4
; (:45136), four fixed 8-byte records with no number command in them.  There is
; no numeric field in that window to write a price into, which is why this is a
; pure leaf in the Ot6DanceCost/Ot6CostFor shape rather than an inline
; immediate: a submenu row decorator reads this and the drawn price and the
; charged price cannot disagree.
;
; Pure leaf: cost in A, preserves X and Y, rtl.
.proc Ot6StealCost
        .a8
        lda     #$04
        rtl
.endproc

; [ the Rage price: the same rule as Dance, for the other possess-verb ]
;
; One payment starts the whole-battle possessed state, so the price is per
; battle, not per turn -- the same rule Dance uses.  A per-rage formula
; (price by the rolled special's own spell cost) is not used: the special is
; rolled rather than chosen, and it would double-charge control already
; surrendered.
;
; This leaf tail-calls Ot6DanceCost rather than repeating the literal, so
; the two prices cannot drift.  Pure leaf: cost in A, preserves X and Y, rtl.
.proc Ot6RageCost
        .a8
        jmp     Ot6DanceCost    ; tail-call: same bank, its rtl returns for us
.endproc

; [ can the hunter pay the trance?  Cmd_10's lock-out gate ]
;
; The twin of Ot6DanceStartGate, for the same reason: the universal
; insufficient-MP fizzle refuses the cast, but it runs
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
; at queue time, disjoint across the three verbs. names below are the ones
; the screen prints (the FF3-US translation); where an internal
; disassembly label differs it is marked as such and never used as the
; primary.
;
; Costs are placeholders, tuned so each kit's price roughly tracks vanilla
; magic's cost-as-fraction-of-pool at the level the ability arrives.  Bum
; Rush ($64) and Cleave ($5c), each kit's divine top tier, anchor at 99 MP,
; the series' own display ceiling: every OT6 price drawer renders two
; digits (ListText cmd $02, btlgfx_main.asm:15045-15073, and
; Ot6LoadoutDrawCost, ot6_loadout_page.asm:375), so 100 would print as
; garbage rather than as a big number.
Ot6AbilityCostTbl:
        ; -- Blitz (Sabin), cmd $0a, attack ids $5d-$64.  levels are
        ;    BlitzLevelTbl.
        .byte   $5d,  4         ; Pummel     L1
        .byte   $5e, 10         ; AuraBolt   L6
        .byte   $5f, 13         ; Suplex     L10
        .byte   $60, 17         ; Fire Dance L15
        .byte   $61, 16         ; Mantra     L23
        .byte   $62, 28         ; Air Blade  L30
        .byte   $63, 50         ; Spiraler   L42
        .byte   $64, 99         ; Bum Rush   L70, the 99 anchor
        ; -- SwdTech (Cyan), cmd $07, attack ids $55-$5c.  levels are
        ;    BushidoLevelTbl.  names are BushidoName, the table the SwdTech
        ;    window renders from.  This column stays monotonic with the tech
        ;    index: the boost window offers techs weakest->strongest and the
        ;    row is the boost level, so a dearer 2x row than 3x row would
        ;    read as a bug.
        .byte   $55,  4         ; Dispatch     BP1
        .byte   $56, 10         ; Retort       BP1
        .byte   $57, 13         ; Slash        BP2
        .byte   $58, 16         ; Quadra Slam  BP2
        .byte   $59, 18         ; Empowerer    BP3
        .byte   $5a, 28         ; Stunner      BP3
        .byte   $5b, 50         ; Quadra Slice BP3
        .byte   $5c, 99         ; Cleave       BP3+Broken, the 99 anchor
        ; -- Tools (Edgar), cmd $09, tool ITEM ids $a3-$aa.  names are
        ;    item_name_en.json's, i.e. what the Tools window prints.
        .byte   $aa,  4         ; AutoCrossbow
        .byte   $a3,  6         ; NoiseBlaster
        .byte   $a4,  8         ; Bio Blaster
        .byte   $a5,  6         ; Flash
        .byte   $a8, 16         ; Drill
        .byte   $a6, 18         ; Chain Saw
        .byte   $a7, 10         ; Debilitator
        .byte   $a9, 14         ; Air Anchor
        ; Overclock (the divine "use two tools") has no single tool item id:
        ; its price is the sum of the two tools it fires, wired when
        ; Overclock is built.  Tools does not take the 99 anchor: the sum of
        ; two tools tops out at 34 (Chain Saw 18 + Drill 16).
        .byte   $ff

; ------------------------------------------------------------------------------

; [ battle mp is universal: every character keeps their save's pool ]
;
; vanilla's battle init loads every character's MP through LoadCharProp
; (battle_main.asm:6621-6640) and then clears it again unless a magic/lore
; command init set the has-mp flag ($f8 bit 0), i.e. unless the character
; knows a spell or has an esper equipped (InitCmdList @53a5..@5408;
; InitCmd_03/04 reach InitCmd_05's `lda #$01 / tsb $f8` only when
; ValidateSpellList counted a spell into $f6 or left an esper in $f7).
; Under the live MP economy that would send every spell-less character into
; battle at 0/0 while Ot6AbilityCost prices their whole kit, so Blitz,
; Tools, SwdTech and Steal would fizzle through CalcAttackEffect's universal
; insufficient-MP gate as wasted turns with no message, and the max-0
; writeback skip (battle_main.asm:12265-12267) keeps field MP full so the
; field never shows the loss.
;
; This hook sets the has-mp flag for every character, so the vanilla clear
; never fires and the pool LoadCharProp loaded survives.  the command inits
; have already run by the hook site, so Magic/Lore command removal for
; spell-less characters is untouched and only the pool differs.  with max MP
; now real, vanilla's own end-of-battle writeback (UpdateSRAM) stores cur MP
; back to the character data, so the field pool tracks battle spend exactly.
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
; Scope: this is the visual half of magic's affordance (grey the row), and it
; is now exactly half.  The other half, magic's `lda $2093,x / bmi` at the
; A-button that refuses the confirm on a disabled spell (btlgfx
; UpdateMenuState_0e @81ae, btlgfx_main.asm:19673), lives menu-side in the
; kit/dance confirms and is gated on THIS proc's answer: Ot6KitConfirmMP at the
; tools-shell confirm (UpdateMenuState_30 @8809, serving blitz, real tools,
; SwdTech and the thief submenu) and Ot6DanceConfirmMP at the dance confirm
; (UpdateMenuState_21 @85f0).  Both call in here, so a greyed row and a refused
; row are the same row by construction.
;
; That used to be described as unaffordable, because btlgfx (bank C1) was a
; stock object linked into both the shipped and the nomp ROM, so a gate there
; would have moved the nomp baseline byte-for-byte -- the one thing this flag
; must never do.  The build changed instead of the rule: btlgfx is assembled
; once per flag (configure.py), the C1 gates sit inside `.if OT6_MP_COSTS`,
; and the nomp object assembles to the same bytes it always did.
; CalcAttackEffect's universal insufficient-MP fizzle is still there underneath
; as the execution-side backstop; the menu no longer lets the player reach it
; by hand and lose the turn and the banked BP to it.
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
        bne     @afford         ; >= 256 MP: nothing in a kit costs that much
                                ;   (the price ceiling is 99)
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

