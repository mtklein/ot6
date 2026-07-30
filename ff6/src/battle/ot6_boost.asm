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
        ; started; latch a normalized 0/1 as THIS battle's flag and clear
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
                                ;   would paint a phantom pip on the first
                                ;   damage numeral of the NEXT battle
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
                                ; FONTDIRTY and this second loop is required
                                ; -- one loop over $58 used to cover both.
        ldx     #$0000
@clr2:  sta     f:$7e0000+OT6_MAPBASE,x
        inx
        inx
        cpx     #$0004          ; $57b6-$57b9: map base, atkclass, fontdirty
        bcc     @clr2           ;   STOPS at $57ba: the $57ba-$57bf strip
                                ;   (spare word + random-encounter flags)
                                ;   must survive init (see the strip's
                                ;   block comment at OT6_RANDPEND)
        ; (removed: an 84-byte clear loop over OT6_HUDCOPY, a retired
        ;  feature's buffer. $57de is inside vanilla's `ram_res w7e57d5,
        ;  128`, so the loop was zeroing vanilla's name/banner scratch at
        ;  every battle init for nothing. Nothing reads OT6_HUDCOPY.)
                                ; (the old single-cell pip pseudo-line's
                                ;  PIPCUR/PIPPREV clears are gone with it --
                                ;  #33 moved the live pips to OT6_PIPROWS,
                                ;  gated by OT6_PIPTAIL/$7bca, and the wallet
                                ;  cur/prev ride the @clr loop above)
        sta     f:$7e0000+OT6_LASTLR
        sta     f:$7e0000+OT6_RESTAGE   ; word store: the high byte lands on
                                        ;   vanilla's $57d5 name scratch —
                                        ;   harmless at init (vanilla always
                                        ;   writes it before reading)
        plx                             ; (OT6_ATKCLASS and OT6_FONTDIRTY sit
                                        ;   in the shadow strip: the @clr
                                        ;   loop covered them)
        plp
        rtl
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
        txa                     ; #33: the live pip cell follows THIS actor
        lsr                     ;   entity offset -> character slot
        sta     f:$7e0000+OT6_PIPSLOT
        lda     #32             ;   for ~half a second past this charge, so
        sta     f:$7e0000+OT6_PIPTAIL   ;   the drop lands on screen even
                                ;   when no battle menu is open at resolution
        lda     $3018,x         ; #37: THE ROUND BOUNDARY for the True Knight
        eor     #$ff            ;   cover earn.  this actor's turn is ending,
        and     f:$7e0000+OT6_COVERPAID  ;   so his next cover pays again --
        sta     f:$7e0000+OT6_COVERPAID  ;   the same tick that decides his
                                ;   regen also re-arms his reaction (the
                                ;   boundary Runic's own machinery implies;
                                ;   see Ot6CoverBP, ot6_kits.asm)
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
        bra     done
@gain:  lda     OT6_BP_CLASS,x
        cmp     #$05
        bcs     done            ; capped at 5
        inc
        sta     OT6_BP_CLASS,x
        ; #42: the BACKSTOP for a deferred cover pip.  Reached by every actor,
        ; monsters included (they are the ones whose swings a knight covers),
        ; and placed AFTER the charge arm above so a pending cover wins the one
        ; live cell -- the actor's own bank restages at the next window open,
        ; a cover earn has no other moment.  Normally a no-op: the numeral
        ; frame already consumed the pending value.  It fires when the action
        ; issued no numeral at all, or a $ffff "hide numerals" one -- the same
        ; hole Ot6RevealCommit is called at the top of this proc to plug.
done:   jsr     Ot6PipPending
        plp
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ a runic absorb pays its rune knight a boost point ]

; called from RunicEffect's per-entity loop (battle_main.asm:8508) at the
; one instruction where the absorb is already CERTAIN. vanilla walks all
; ten entities there and drops out three ways before that point: target
; not present ($3aa0.0, :8494), no runic stance at all ($3e4c.1|.2,
; :8497), and a CheckStatus gate that discards a dead / petrified /
; asleep / stopped / frozen / hidden runic-er (:8500-8503). only a
; survivor of all three reaches the `tsb $ee` that enrolls it in the
; absorbing set (:8506), and $ee is exactly what the routine then
; retargets its mp-restore onto (:8517-8523). so this hook re-derives no
; eligibility of its own -- arriving here IS the absorb.
;
; WHICH stance ate it still has to be told apart. vanilla cleared bit 2
; -- the Runic command's own bit, set by Cmd_0b (:4081-4083) -- four
; instructions up at :8498, but deliberately left bit 1, "enemy runic",
; seeded from MonsterProp+30 at :7421. that seed does reach a CHARACTER
; entity, because the same monster-property loader runs for Gau's Rage
; (Ot6SeedShields guards the identical case, this file). bit 1 still set
; here therefore means this entity ate the spell as a raging monster
; rather than as a rune knight, and it banks nothing.
;
; two economy rulings, both deliberate:
;   - the bank cap is Ot6ActionEnd's, untouched: an absorb at 5 bp is
;     simply capped. it never wraps, and it never mints a sixth pip that
;     Ot6Boost's `cmp OT6_BP_CLASS` would then happily let her spend.
;   - the no-regen-after-boost rule does NOT gate this. that rule
;     (Ot6ActionEnd) is about a turn's own end-of-action tick; an absorb
;     is an out-of-turn reward paid during the CASTER's action, and the
;     caster's own ActionEnd leaves at its `cmp #$08` monster gate
;     (:1620) without ever reaching her row. so a Celes who boosted the
;     turn she raised Runic is still paid for what she catches -- the
;     stance costs her the turn either way, and taxing it twice would
;     make boosting into Runic strictly worse than not boosting.
;
; a8 (vanilla's `shorta` is the instruction immediately before), index
; width either -- no index immediates and no pushes, per this file's
; width discipline; RunicEffect itself runs .i8. y = the absorbing
; entity's offset, a clobbered (dead: the loop reloads at :8492).

.proc Ot6RunicBP
        .a8
        tya                     ; width-neutral character test
        cmp     #$08
        bcs     done            ; monsters bank no bp
        lda     $3e4c,y
        and     #$02            ; survived as enemy runic: a raging gau
        bne     done            ;   ate it, not a rune knight
        lda     OT6_BP_CLASS,y
        cmp     #$05
        bcs     done            ; the bank cap holds; an absorb never wraps
        inc
        sta     OT6_BP_CLASS,y
done:   rtl
.endproc

; ------------------------------------------------------------------------------

; [ extra swings for a boosted fight ]

; called from FightAttack right after the vanilla swing count lands in
; $3a70 (1, or 7 with offering). swings alternate hands and empty-hand
; swings whiff, so +2 swings per pending bp = +1 real hit for a
; one-weapon character — and a genji-glove pair swings both hands
; again, doubling the bonus, exactly like it doubles everything else.
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
                                ;   UNHOOKED EndAction -- so the pending
                                ;   would be delivered but never charged.
                                ;   a black belt counter with pending 3
                                ;   measured 7 swings, free
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
; record for name, animation, and power, while bp stays the only
; price. pending 1 = one tier up, 2-3 = two. x = the actor's entity
; offset (CreateAction's own indexing). preserves a/x/y.

.proc Ot6QueueFold
        .a8
        php                     ; caller widths vary: pin our own
        longi
        .i16
        pha
        lda     $b1             ; a counter's fold would be free the same
        lsr                     ;   way: ai counter scripts (a raged gau's)
        bcs     @keep           ;   route through CreateAction under
                                ;   ExecRetal's $b1.0, and no ActionEnd
                                ;   ever charges what they queue
        lda     $3a7a           ; command
        cmp     #$02
        beq     @cmdok          ; $02 magic
        cmp     #$17
        beq     @cmdok          ; $17 x-magic
        cmp     #$0c
        bne     @keep           ; $0c lore
@cmdok: txa                     ; width-neutral character test
        cmp     #$08
        bcs     @keep           ; monsters never boost
        lda     OT6_BOOST_REVEALED,x         ; pending boost
        beq     @keep
        cmp     #$02
        bcc     :+
        lda     #$02            ; at most two tiers up
:       sta     OT6_SCR_BIT     ; tier steps
        phx
        ldx     #$0000
@row:   lda     f:Ot6FoldTbl,x
        cmp     $3a7b           ; attack id
        beq     @hit
        inx
        inx
        inx
        cpx     #$0018          ; 8 families x [base, +1, +2]
        bcc     @row
        plx
        bra     @keep
@hit:   txa                     ; row offset (< $18, fits 8 bits)
        clc
        adc     OT6_SCR_BIT
        longa
        and     #$00ff
        tax
        shorta0
        lda     f:Ot6FoldTbl,x
        sta     $3a7b           ; queue the folded tier
        plx
@keep:  pla
        plp
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ boost preview in ability lists ]

; replaces ListTextCmd_0f's `lda ($4f) / sta $2c` (exactly four bytes).
; while the active character has boost pending, tiered spells render
; under their folded name — browsing Fire with two boosts pending shows
; "Fire 3" before the choice is made. $2c is render-scoped (name + our
; element icon); the mp column and confirm logic read the list data, so
; cost display and selectability stay on the base spell. list renders
; per open; a mid-list R/L press shows at the next open (the arrow cell
; tracks live either way). a8/i16, db=$7e, d=0; preserves x/y and b.

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
        tay
        shorta0
        lda     OT6_BOOST_REVEALED,y         ; pending boost
        beq     @out
        cmp     #$02
        bcc     :+
        lda     #$02            ; at most two tiers up
:       sta     OT6_SCR_BIT     ; tier steps
        ldx     #$0000
@row:   lda     f:Ot6FoldTbl,x
        cmp     $2c
        beq     @hit
        inx
        inx
        inx
        cpx     #$0018
        bcc     @row
        bra     @out
@hit:   txa                     ; row offset (< $18, fits 8 bits)
        clc
        adc     OT6_SCR_BIT
        longa
        and     #$00ff
        tax
        shorta0
        lda     f:Ot6FoldTbl,x
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
.if OT6_MP_COSTS
; ------------------------------------------------------------------------------

; [ price a costed verb's action at queue time (v0.4 -- OT6_MP_COSTS) ]

; the "one dispatch change" docs/design/mp-economy.md's M4 note predicts.
; vanilla's GetMPCost (battle_main.asm) returns a cost only for magic, lore,
; summon and x-magic; every other command -- Blitz, SwdTech, Tools, the free
; floor, the free-exception verbs -- falls through it returning 0, so the
; universal charge at CalcAttackEffect (the $3a4c subtract, and its
; insufficient-mp FIZZLE) never fires for them. this hook runs on the same A
; the queue store consumes, right after GetMPCost: for the three costed verbs
; it swaps the 0 for the kit price, keyed by the resolved id ALREADY sitting
; in $3a7b at queue time --
;   blitz  ($0a): attack id  $5d-$64   (FixPlayerAttack's +$5d)
;   swdtech($07): attack id  $55-$5c   (FixPlayerAttack's +$55)
;   tools  ($09): tool item id $a3-$aa (Cmd_09 resolves it as $b6-$a2)
; those three id ranges are disjoint, so ONE $ff-terminated (key,cost) table
; serves all three; the command gate keeps a stray id under any OTHER verb
; from ever matching a row. an id absent from the table charges 0 -- a
; missing price is FREE, never a garbage charge -- and every command that is
; not one of the three returns vanilla's own A untouched (magic stays priced
; on its own ruler, the free floor stays free).
;
; steal (cmd $05) is a fourth costed verb, but a SINGLE ability rather than a
; list: FixPlayerAttack omits it from CmdWithAttackTbl, so it never earns a
; per-ability id in a disjoint range (its queue-time $3a7b is the menu's raw
; attack byte, not a table key). so it takes a FLAT-COST path keyed on the
; command alone -- cmd $05 -> 2 MP, mp-economy.md's "flat small" for the
; probe-collect verb -- and never consults the id table. (routing it through
; the table would also have to dodge a coincidence: steal's own special-effect
; id $a4, set at execute time in Cmd_05, is already the tool key for
; Bio Blaster.) confirmed absolute (owner, 2026-07-22): only the basic Fight
; command is free; every other verb costs MP as its kit comes online.
;
; the charge AND the refusal are BOTH already universal (they act on whatever
; $3620 -> $3a4c holds); the ONLY magic-specific piece is the menu grey-out /
; cost display (CheckMagicEnabled), which is the menu-bank work this whole
; flag waits on. that is why a hidden charge must not ship enabled: the menu
; still shows these verbs no number.
;
; boost never raises the price: blitz and tools keep one id no matter the
; boost, and a boosted SwdTech has already queued the tech its BP bought
; (Ot6BushidoTier / Ot6QueueFold leaves $3a7b at that tech), whose own
; per-tech price is exactly what should be charged -- BP buys the tier, MP
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
        beq     @steal          ; steal: one verb, one flat price -- no id
        cmp     #$13
        beq     @dance          ; dance: flat, paid at dance-START only (#34)
        cmp     #$10
        beq     @rage           ; rage: the same shape as dance (#40)
        ; NO cmd-$11 arm: LEAP IS FREE (owner, 2026-07-29).  It had a flat 2
        ; here from #40, reasoned from "only the basic Fight command is free"
        ; -- but that price was never rendered on any surface, so the only way
        ; a player met it was a Leap that silently refused.  And Leap now
        ; SHARES the Fight row on the Veldt (Ot6VeldtRow, battle_main.asm):
        ; it is not a verb beside Fight there, it IS the Fight row, and the
        ; free floor has to survive the substitution.  Falling out of this
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
@steal: ; #55: steal is no longer ONE ability -- it is the first row of Locke's
        ; thief submenu, and the row the player picked is in $3a7b (see
        ; Ot6ThiefListOpen's header for why that byte is free under this command
        ; and why the $11a9/$a4 collision the old note warned about does not
        ; reach here).  Filch and Bestow price from Ot6ThiefCostTbl, keyed on
        ; that byte; EVERYTHING ELSE -- the Steal row itself, the $ff a Confused
        ; or AI-issued Steal queues, a Gogo mimic -- falls through to
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
@dance: ; dance (cmd $13) is priced at the COMMIT moment only: the mid-dance
        ; turns queue through the same CreateAction (RandDanceAction,
        ; battle_main.asm:617), but by then Cmd_13 has set the actor's DANCE
        ; status ($3ef8 bit 0) -- one payment starts the whole-battle state,
        ; and every locked-in step is free (mp-economy.md:96).  a stumbled
        ; start (Cmd_13's 50% @17af arm) clears the bit, so retrying the
        ; commit pays again -- the payment moment IS the commit moment.
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
@rage:  ; #40: rage is the OTHER possess-verb, and issue #40 orders one pricing
        ; rule for both -- flat, charged once at Rage-START, every possessed
        ; turn after it free.  The discriminator is the same shape dance uses:
        ; Cmd_10 sets the actor's RAGE status ($3ef9 bit 0) on the start turn,
        ; and every later possessed turn re-enters command $10 with the bit
        ; already set.  X = attacker entity at this hook (the site contract).
        ; A refused START must not lock the trance for free either -- that is
        ; Ot6RageStartGate's job in Cmd_10, dance's own #34 lesson re-applied.
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

; [ price one ability by its id -- the reusable cost authority ]
;
; the table SCAN, split out of Ot6AbilityCost so the menu bank can price a row
; without paying the command gate. Ot6AbilityCost reads $3a7a/$3a7b at queue
; time; a menu row already HOLDS the id it is about to draw, so it needs only
; this leaf. PURE: id in A, cost in A ($00 if the id is unpriced), reads no
; $3a7x. keys are disjoint per verb (blitz $5d-$64, swdtech $55-$5c, tools
; $a3-$aa), so the id alone selects the row. preserves X and Y; a8/i16.
; rtl (jsl) -- one entry for bank F0 and any cross-bank caller alike.
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

; [ #55: the SECOND keyed table -- Locke's thief submenu ]
;
; WHY A SECOND TABLE RATHER THAN ROWS IN Ot6AbilityCostTbl.  That table's header
; earns its single-scan design on one property: "those three id ranges are
; disjoint, so ONE $ff-terminated (key,cost) table serves all three; the command
; gate keeps a stray id under any OTHER verb from ever matching a row".  The
; thief rows are $56-$58, which sit INSIDE SwdTech's $55-$5c key range -- they
; are AttackName pad slots, and SwdTech's ids are attack ids in the same space
; (SwdTech draws its names from BushidoName, which is exactly why the pad was
; free; see Ot6ThiefListOpen).  Putting them in the shared table would break the
; disjointness the scan relies on and would price a boosted SwdTech row as a
; Filch.  Keeping them here keeps the invariant literally true: two tables, each
; reached from its own arm of Ot6AbilityCost's command gate, and the gate is what
; makes the key spaces disjoint.
;
; THE RULER (the same one Ot6AbilityCostTbl is on: 8-20% of the real pool at the
; level the ability arrives).  Locke joins at Narshe holding 31 MP at LV6 -- the
; figure Ot6StealCost measured off probe_mppools.lua -- and these are granted at
; join with Steal (the story-gating ruling; kits.md).  So:
;
;   Steal   4  12.9%   (Ot6StealCost, unchanged -- rung one, the signature)
;   Bestow  5  16.1%   between Cure's 12.5% and Drain's 17.2%
;   Filch   6  19.4%   just under Life's 20.3%, the top of the ruler
;
; NOT MONOTONIC WITH THE RUNG ORDER, deliberately: kits.md numbers Filch rung 4
; and Bestow rung 5, so a monotonic column would want Filch cheaper.  SwdTech is
; the one kit that must stay monotonic and its table says why -- "the row IS the
; boost level, so a dearer 2x row than 3x row would read as a bug".  The thief
; submenu is a FREE-CHOICE menu like Blitz, which the same header exempts from
; the rule ("Blitz is a free-choice menu and needs no such rule"), and Blitz
; already ships Mantra 16 beneath Fire Dance 17 for the same reason.  Price by
; what the ability does, not by where kits.md happened to list it.
;
; Filch sits at the TOP of the ruler on purpose: it is the only class-blind and
; element-blind shield remover in the game and the only way to gain two BP in a
; turn (see Ot6Filch), and at 6 a full LV6 pool buys five of them.  Bestow is
; dearer than Steal because it is a party-wide tempo move rather than a probe,
; and cheaper than Filch because it moves a pip Locke already paid for.
; Placeholders like every number in this file; battle_costtable.lua recomputes
; the fractions from the ROM.
Ot6ThiefCostTbl:
        .byte   OT6_THIEF_FILCH,  6     ; Filch  -- shield -> boost point
        .byte   OT6_THIEF_BESTOW, 5     ; Bestow -- hand a boost point to an ally
        .byte   $ff
        ; NO Steal row: Ot6StealCost is its authority (#52) and the @steal arm
        ; routes the Steal row -- and every Steal this menu did not issue -- to
        ; that leaf.  A row here would make two numbers for one price.

; [ #55: price one thief row by its id -- Ot6CostFor's twin on the second table ]
; PURE: id in A, cost in A ($00 if the id is unpriced -- an unpriced id is FREE,
; never a garbage charge, the same ruling Ot6CostFor makes).  preserves X and Y;
; a8/i16.  rtl.
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
; consults this BEFORE setting the DANCE status: the universal fizzle
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

; [ the Dance price -- one authority for the charge and the menu (#34) ]
;
; mp-economy.md:96 rules "flat, paid at start, 4-10: one payment starts a
; whole-battle state".  8 -- the top half of the band -- because the single
; payment funds every subsequent turn's verb for the rest of the battle
; (each locked-in step is free), so it prices above the per-use signature
; verbs (Steal 4 since #52, Pummel 4) while staying payable from Mog's pool
; (base 16 MP + level gains); playtest tunes.  PURE leaf, the Ot6CostFor
; shape: cost in A, preserves X and Y; rtl so the menu decorator (bank F0
; via C1) and the charge read one number.
.proc Ot6DanceCost
        .a8
        lda     #$08
        rtl
.endproc

; [ the Steal price -- the flat verb's one authority (#52) ]
;
; 4, up from the 2 that shipped in v0.5.  #52's headline was "2 MP is ~2% of
; Locke's LV14 pool", but that measures at the wrong level and the ruler this
; column is on measures at the level an ability ARRIVES: Locke joins at Narshe
; holding 31 MP (LV6, read off worldmap_narshe by probe_mppools.lua), where 2
; is 6.5% -- under the 8-20% a vanilla spell costs at ITS arrival -- and 4 is
; 12.9%, between Fire's 10.0% and Cure's 12.5%.  So the honest fix is the same
; 2x #45 gave the Blitz floor, not a bigger number chosen to look right at LV14.
; (Every signature dilutes the same way by then: Pummel is 4.3% of Sabin's LV14
; pool and Dispatch 4.3% of Cyan's.  Pricing against a late pool would mean
; per-level prices, which the ruler explicitly does not do.)
;
; 4 is also exact PARITY with the cheapest row of all three ladder kits --
; Pummel $5d, Dispatch $55, AutoCrossbow $aa, every one of them 4 -- and Steal
; is Locke's signature, mp-economy.md's "signatures become the cheapest rows of
; their kits".  That parity is load-bearing for #55: Steal is a RUNG, not the
; ceiling (owner, 2026-07-29 -- Locke's 99 is Master's Mark, kits.md:404), so
; it should read as rung one of an eight-rung ladder, not as its own thing.
;
; NOTE WHAT THIS PRICE STILL CANNOT DO: it cannot be SEEN.  Steal is a
; top-level battle command, and command_window_data_set (btlgfx_main.asm:10099)
; writes exactly two things per row -- the command byte and a GetTextColor
; colour off the DISABLED flag (:10704, `and #$80`) -- through MenuText::_4
; (:45136), four fixed 8-byte records with no number command in them.  There is
; no numeric field in that window to write a price into, which is why this is a
; PURE LEAF in the Ot6DanceCost/Ot6CostFor shape rather than an inline
; immediate: the day #55 gives Locke a submenu, its row decorator reads this
; and the drawn price and the charged price cannot disagree.  See mp-economy.md
; "Steal's price is real and invisible" for the ruling and why a numeric field
; was not built into the command window for one verb.
;
; PURE leaf: cost in A, preserves X and Y, rtl.
.proc Ot6StealCost
        .a8
        lda     #$04
        rtl
.endproc

; [ the Rage price -- the SAME rule as Dance, for the other possess-verb (#40) ]
;
; issue #40 orders "one pricing rule for both possess-verbs", and mp-economy.md:
; 96's rule is the possession's: one payment starts a whole-battle state, so the
; price is per battle, not per turn.  A per-rage formula (price by the special's
; spell cost) was weighed and rejected in kit-gau.md §5 on three counts: it
; double-charges (the trance's real price is the surrendered control, already
; paid, and the special is only ROLLED, never chosen); it inverts the
; collection's joy (the rarest hunts would carry the ugliest prices); and it
; needs a 255-row price surface where the flat rule needs one number.
;
; 8 -- deliberately Dance's own number, not a number near it.  If the Dance
; figure ever moves inside mp-economy's 4-10 band, RAGE FOLLOWS IT: the rule
; ("possess-verbs share one flat price") outranks the digit, so this leaf
; tail-calls Ot6DanceCost rather than repeating the literal, and the two can
; never drift.  PURE leaf: cost in A, preserves X and Y, rtl.
.proc Ot6RageCost
        .a8
        jmp     Ot6DanceCost    ; tail-call: same bank, its rtl returns for us
.endproc

; [ the Leap price -- RETIRED.  Leap is free (owner, 2026-07-29) ]
;
; #40 gave Leap a flat 2 (Ot6LeapCost, deleted here), reasoned from "only the
; basic Fight command is free" (mp-economy.md:30-34) and mp-economy.md:97's
; probe-collect rung, the same row Steal sits on.  Two things retired it:
;
;   1. the price was NEVER DISPLAYED.  Leap is a top-level command row, not a
;      list entry, so nothing ever drew "2 MP" beside it -- the id-keyed
;      pricing surfaces (Ot6CostFor -> ot6_kits.asm / skills.asm) only reach
;      verbs that open a window.  The command window itself
;      (command_window_data_set, btlgfx_main.asm:10099-10125) stores only the
;      command byte and a GetTextColor colour per row, and that colour is
;      `and #$80` on the DISABLED flag (:10704-10707), not affordability.  A
;      player's only encounter with the number was a Leap that refused for
;      reasons the screen never gave.
;   2. Leap now IS the Fight row on the Veldt (Ot6VeldtRow, battle_main.asm).
;      #47 exists to guarantee Gau a free action; a priced Leap sitting in the
;      Fight row would have re-opened that hole in the one place -- the Veldt
;      -- where Gau spends the most turns.
;
; Steal keeps its flat 2: it is a verb BESIDE Fight, not the Fight row, and
; its repricing is issue #52's business, not this change's.  Leap is otherwise
; still vanilla (kit-gau.md §6.3 recommended against the boosted-Leap rider).

; [ #40: can the hunter pay the trance?  Cmd_10's lock-out gate ]
;
; The exact twin of Ot6DanceStartGate, and it exists for the exact reason #34
; found: the universal insufficient-MP fizzle refuses the CAST, but it runs
; after the command body, so a broke Gau would keep the whole-battle RAGE
; status for free and every possessed turn after it costs 0.  A fizzled Rage
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

; (key, cost) pairs, $ff terminates. keys are exactly the id already in $3a7b
; at queue time, disjoint across the three verbs. names below are the ones the
; SCREEN prints (the FF3-US translation -- CONTRIBUTING's vocabulary rule,
; owner 2026-07-29); where an internal disassembly label differs it is marked
; as such, never used as the primary.
;
; -------- the ruler these numbers are on (#45 rescale, 2026-07-29) --------
;
; mp-economy.md's "one price scale" says kit skills price on the vanilla spell
; ruler.  That ruler was never MEASURED until #45, so here it is: vanilla
; natural magic, cost as a fraction of the caster's real pool at the level the
; spell is LEARNED (pool = char_prop base MP + LevelUpMP running sum, both
; read out of this ROM, not recalled) --
;
;   Antdot 3 @L6 7.5% · Warp 20 @L26 8.3% · Fire 4 @L6 10.0%
;   Fire 2 20 @L22 10.4% · Cure 5 @L6 12.5% · Drain 15 @L12 17.2%
;   Life 30 @L18 20.3%
;
; (spells learned below Terra's earliest measured level are priced at that
; level -- L6, pool 40, read off kolts_doorstep -- the same clamp the kit rows
; use, because a pool the game never presents is not a price anyone pays.)
; so a vanilla spell costs roughly 8-20% of the pool it is first cast from.
; The v0.4/v0.5 kit columns did NOT sit on that ruler.  Measured the same way,
; SwdTech ran 1.0-3.9% and Blitz 3.6-12.5% -- three to eight times under the
; scale the doc claimed they shared.  The owner's v0.7 playtest found it from
; the other end: at LV14 Cyan holds a 96 MP pool against techs costing 1/2/3,
; and BP was not scarce either, so NEITHER currency bound him and Fight had no
; case (mp-economy.md's stated target: "Fight must sometimes be the right move,
; without Cyan and Sabin ceasing to feel like ability characters").
;
; ONE principled change, not two knobs (owner's decomposition, issue #45):
;
;   1. RETIRE SwdTech's ~1/3 discount.  It was justified by "the BP ladder is
;      the real price, so MP rides ~1/3 of a comparable Blitz/Tool" -- a claim
;      about the FOUR-rung 0x/1x/2x/3x ladder.  #38 rewrote that ladder to
;      1x/2x/3x and explicitly deferred the MP column ("MP costs per tech
;      unchanged"), so the discount kept applying after the premise that earned
;      it had been rewritten.  SwdTech now prices at PARITY with the Blitz row
;      of the same index -- which is a level statement, not an index
;      coincidence: BlitzLevelTbl is 1/6/10/15/23/30/42/70 and BushidoLevelTbl
;      1/6/12/15/24/34/44/70 (field/event.asm:1236-1240), so row n of either
;      kit lands in the same band against nearly the same pool.
;   2. A GENERAL FLOOR LIFT of ~1.5-2x on the Blitz ladder, tapering toward
;      1.5x at the top -- COMPRESSION, not a flat multiply.  Pools grow far
;      faster than a fixed cost, so the same ladder scaled flat would price the
;      late rows above the ruler while leaving the early ones under it.
;
; What that lands (cost / real pool at the level the row is reachable; rows 1-2
; evaluated at L10, the earliest either character is actually IN the party):
;
;   Blitz    7.1 17.9 23.2 16.3  8.4  7.9  6.7  6.1 %   (was 3.6 .. 12.5)
;   SwdTech  6.9 17.2 17.1 15.1  8.8  6.6  6.2  6.0 %   (was 1.0 ..  3.9)
;
; Every row stays payable from a full pool at the level it becomes available by
; a wide margin -- the top rows most of all, because L42/L70 pools are 449/760.
; The owner's worry that a flat 4x would push "Bum Rush 30 -> 120 past WoB
; pools" does not survive measurement in the direction he feared: Bum Rush is
; L70-gated and Sabin's L70 pool is 760.  The squeeze is at the FLOOR and in
; early WoB, exactly where mp-economy.md already said it was.
;
; TOOLS ARE DELIBERATELY UNCHANGED.  Measured against Edgar's real pool at the
; band each tool is acquired they already run 7-21% -- dead on the vanilla
; ruler above (AutoCrossbow 11.1% @L7, Drill 18.4% @L13, Chain Saw 20.7% @L13).
; The general lift was offered to them and the measurement declined it: a 1.5x
; on Chain Saw would put it at 31%, off the top of the scale.  gil buys the tool
; once, MP is the per-use cost, and that price was already right.
;
; Every number here is a playtest placeholder (mp-economy.md's standing
; preamble) and successive rescales are expected, not churn.  The gate that
; keeps a future column on the ruler is tools/tests/battle_costtable.lua, which
; recomputes these fractions from the ROM's own tables.
;
; -------- the 99 ANCHOR (issue #57, 2026-07-29) --------
;
; Owner: "it would be cool to scale ability MP costs so that each character's
; own ultimate ends up costing 99 MP", refined to "99 where it makes sense, not
; universal".  Two rows in this table qualify -- BUM RUSH ($64) and CLEAVE
; ($5c), each its kit's divine top rung.  Tools does NOT participate: its
; capstone is Overclock, which kits.md prices as the SUM of the two tools it
; fires and which is not built, and Air Anchor ($a9) is explicitly "a findable
; item mid-kit gag, not the capstone" (kits.md:137) -- so there is no top Tools
; ROW here to anchor.  Steal, Slot, Rage and Dance are flat verbs with no
; ladder at all; that is a stated non-answer, not a gap.
;
; WHY 99 AND NOT 100.  Owner: "seeing things like 99, 999, and 9999 in Final
; Fantasy games feels right -- very classic feel."  It is also the number this
; game already uses: vanilla's dearest SPELL is Quick at exactly 99 MP
; (magic_prop_en.dat +$05, id $2b), so the anchor is the series' own ceiling
; rather than an imported one.  And it is a HARD DISPLAY limit: every OT6 price
; drawer renders TWO digits -- ListText cmd $02 (btlgfx_main.asm:15045-15073)
; divides by ten exactly once, and Ot6LoadoutDrawCost (field_menu.asm:3053)
; has one tens loop -- so 100 would print as garbage, not as a big number.
;
; WHAT THE ANCHOR CHANGED, AND WHAT IT DELIBERATELY DID NOT.  Rows 6/7/8 of
; both ladders, and nothing else.  #45 lifted the FLOOR hard (2x) and the
; ceiling less (1.5x), hedging against an owner worry that "Bum Rush 30 -> 120"
; would outrun WoB pools -- a worry #45's own measurement then disproved (Bum
; Rush is L70-gated and Sabin's L70 pool is 760).  The hedge survived the
; measurement that killed it, which is why the tail still sat at 6.0-6.7% of
; pool while the middle of the ladder sat at 15-23%.  The anchor is the
; correction to that hedge: the tail is re-derived UP so that %-of-pool climbs
; into the anchor instead of falling away from it, and rows 1-5 are untouched
; because they already measure inside the ruler at the level they arrive.
;
;   Blitz    7.1 17.9 23.2 16.3  8.4 10.1 11.1 13.0 %   (tail was 7.9 6.7 6.1)
;   SwdTech  6.9 17.2 17.1 15.1  8.8  8.4 10.4 13.0 %   (tail was 6.6 6.2 6.0)
;
; This is deliberately NOT a proportional scale of the old column (99/46 =
; 2.15x): that would leave Suplex at 28 MP -- 50% of a LV10 pool -- and push
; rows 2-4 clean off the top of the ruler.  The old column was right in the
; middle and wrong at the ends; only the end moves.
Ot6AbilityCostTbl:
        ; -- Blitz (Sabin), cmd $0a, attack ids $5d-$64.  levels are
        ;    BlitzLevelTbl.  ladder shape kept (Mantra deliberately under Fire
        ;    Dance: a utility off-ramp, not a damage rung); level lifted.
        .byte   $5d,  4         ; Pummel     L1  signature -- cheapest row
        .byte   $5e, 10         ; AuraBolt   L6  holy chip
        .byte   $5f, 13         ; Suplex     L10 bludgeon
        .byte   $60, 17         ; Fire Dance L15 fire, all
        .byte   $61, 16         ; Mantra     L23 party heal (utility, off-ramp)
        .byte   $62, 28         ; Air Blade  L30 wind, all      (#57: was 22)
        .byte   $63, 50         ; Spiraler   L42                (#57: was 30)
        .byte   $64, 99         ; Bum Rush   L70 divine, bludgeon x8 -- THE
                                ;   ANCHOR (#57).  13.0% of the L70 pool of
                                ;   760, inside the ruler; 7 uses from full.
        ; -- SwdTech (Cyan), cmd $07, attack ids $55-$5c.  levels are
        ;    BushidoLevelTbl.  names are BushidoName, the table the SwdTech
        ;    window actually renders from (`Bushido` survives only as the
        ;    internal label, per the vocabulary rule above).
        ;    PARITY with the Blitz row of the same index, per (1) above -- the
        ;    old "~1/3 of a comparable Blitz/Tool" discount is retired here.
        ;    ONE deviation from parity: Empowerer takes 18 rather than Mantra's
        ;    16, because this column must stay MONOTONIC with the tech index --
        ;    the boost window offers techs weakest->strongest and the row
        ;    IS the boost level (kits.md), so a dearer 2x row than 3x row would
        ;    read as a bug.  Blitz is a free-choice menu and needs no such rule.
        ;    Cyan still pays BP on top; if parity plus the 1-BP floor leaves him
        ;    starved, #38's own ruling names the lever -- BP seed/regen, not
        ;    the floor, and not this column.
        .byte   $55,  4         ; Dispatch     BP1 signature
        .byte   $56, 10         ; Retort       BP1 counter stance
        .byte   $57, 13         ; Slash        BP2 slash
        .byte   $58, 16         ; Quadra Slam  BP2 slash x4
        .byte   $59, 18         ; Empowerer    BP3 drain (the parity deviation)
        .byte   $5a, 28         ; Stunner      BP3 slash, all   (#57: was 22)
        .byte   $5b, 50         ; Quadra Slice BP3 wind x4      (#57: was 30)
        .byte   $5c, 99         ; Cleave       BP3+Broken divine -- THE ANCHOR
                                ;   (#57).  13.0% of Cyan's L70 pool of 762,
                                ;   the same fraction Bum Rush is of Sabin's,
                                ;   which is the point of anchoring both.
        ; -- Tools (Edgar), cmd $09, tool ITEM ids $a3-$aa.  names are
        ;    item_name_en.json's, i.e. what the Tools window prints.
        ;    UNCHANGED by the #45 rescale -- see "TOOLS ARE DELIBERATELY
        ;    UNCHANGED" above: measured, they are already on the ruler.
        .byte   $aa,  4         ; AutoCrossbow signature, piercing x4 shredder
        .byte   $a3,  6         ; NoiseBlaster confuse
        .byte   $a4,  8         ; Bio Blaster  poison, all -- the armor-break key
        .byte   $a5,  6         ; Flash        blind, all
        .byte   $a8, 16         ; Drill        armored-boss answer, pierce
        .byte   $a6, 18         ; Chain Saw    slashing + instant-death chance
        .byte   $a7, 10         ; Debilitator  adds + reveals a weakness (probe)
        .byte   $a9, 14         ; Air Anchor   mid-kit gag (harpoon / doom)
        ; Overclock (the divine "use two tools") has no single tool item id:
        ; its price is the SUM of the two tools it fires -- wired the day
        ; Overclock is built (kits.md: Magitek-factory story unlock).  That is
        ; also why TOOLS DOES NOT TAKE THE 99 ANCHOR (#57): Edgar's ultimate is
        ; Overclock, not the mid-kit gag Air Anchor, and Sigma of two tools tops
        ; out at 34 (Chain Saw 18 + Drill 16).  Whether Overclock is 99 or stays
        ; Sigma is a decision for the issue that BUILDS it -- both rules cannot
        ; hold, and inventing the answer here would price an ability that has
        ; no code.
        .byte   $ff

; ------------------------------------------------------------------------------

; [ battle mp is universal -- every character keeps their save's pool (#32) ]
;
; vanilla's battle init loads every character's MP through LoadCharProp
; (battle_main.asm:6621-6640) and then CLEARS it again unless a magic/lore
; command init set the has-mp flag ($f8 bit 0) -- i.e. unless the character
; knows a spell or has an esper equipped (InitCmdList @53a5..@5408;
; InitCmd_03/04 reach InitCmd_05's `lda #$01 / tsb $f8` only when
; ValidateSpellList counted a spell into $f6 or left an esper in $f7).
; sensible when only magic spent MP; under the live economy above it sent
; every spell-less character into battle at 0/0 while Ot6AbilityCost priced
; their whole kit -- Blitz, Tools, SwdTech and Steal all fizzled through
; CalcAttackEffect's universal insufficient-MP gate as silent wasted turns,
; and the max-0 writeback skip (battle_main.asm:12265-12267) kept field MP
; full so the field never showed the theft (issue #32's measurements).
;
; ruling (issue #32): MP is a universal resource, so its battle init is
; universal.  this hook sets the has-mp flag for every character, so the
; vanilla clear never fires and the pool LoadCharProp loaded survives.  the
; command inits have already run by the hook site: Magic/Lore command
; REMOVAL for spell-less characters is untouched -- only the pool differs.
; with max MP now real, vanilla's own end-of-battle writeback (UpdateSRAM)
; stores cur MP back to the character data, so the field pool tracks battle
; spend exactly (battle_naturalmp.lua's writeback gate).
;
; entry (jsl from InitCmdList, right before its `lsr $f8`, once per
; character): a8/i8 -- a battle-init 8-bit-index caller, so the body is
; width-agnostic (no index ops, no pushes; ot6.asm's width discipline).
; $f8 is the init's direct-page scratch; jsl preserves D, so the dp access
; lands on the caller's own cell.
.proc Ot6MpUniversal
        lda     #$01            ; the "character has mp" bit InitCmd_05 sets
        tsb     $f8
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ grey a menu row the active caster cannot afford -- magic's grey-out ported ]
;
; vanilla magic greys an unaffordable spell: UpdateEnabledMagic compares each
; spell's MP cost to the caster's current MP, and DrawMagicListText's
; GetTextColor turns the "can't pay" answer into $04, OR'd into the row's $21
; white font-palette byte to make $25 (grey).  Blitz and Tools draw through the
; tools-window shell, never the magic list, so they never inherited that
; machinery -- this is it, in the menu bank.  Given a row's MP cost in A it
; returns the SAME $04/$00 magic OR's in: $04 (grey the row) when the active
; caster cannot pay, $00 (leave it white) when they can -- the decorator OR's
; it straight into the ListText $21 white palette byte, exactly as GetTextColor
; feeds `ora w7e5755+3`.  The caster is $62ca (the active slot DrawMagicListText
; itself indexes by) and its live MP is $3c08,slot*2 -- the very cell
; CalcAttackEffect's universal charge later subtracts from, so the menu greys
; precisely what the charge would refuse.  A 0 cost (an empty pad cell, or an
; unpriced id Ot6CostFor returned 0 for) is always affordable, so a blank row
; never greys.
;
; SCOPE: this ports the VISUAL half of magic's affordance (grey the row).  The
; other half -- magic's `lda $2093,x / bmi` at the A-button that no-ops the
; confirm on a disabled spell (btlgfx UpdateMenuState_3b @81ae) -- would live in
; the tools/blitz confirm (UpdateMenuState_3c @8809).  That is btlgfx (bank C1),
; a STOCK object linked into BOTH the shipped and the nomp ROM (only the battle
; object is rebuilt per-flag), so a confirm gate there would shift the nomp
; baseline byte-for-byte -- the one thing this flag must never do.  So the block
; stays where it already is and costs no bytes: CalcAttackEffect's universal
; insufficient-MP fizzle refuses the cast at execution (MP is never overspent,
; battle_mpcost.lua's REFUSAL half), and the unmistakable grey tells the player
; before they get there.  If the block ever moves menu-side, it belongs beside
; @8809 gated on this same Ot6AbilityGrey answer.
;
; a8/i16, db=$7e (the decorators' bank; $3c08/$62ca are $7e battle RAM).  in:
; A = MP cost.  out: A = $00 (white) | $04 (grey).  preserves X and Y -- the
; blitz decorator indexes Qty,y across the call, and both keep their buffer
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
        bne     @afford         ; >= 256 MP: nothing in a kit costs that much --
                                ;   CHECKED since #57, not assumed: the ceiling
                                ;   is 99 and battle_costtable.lua asserts it on
                                ;   every row of the live table
        lda     $3c08,x         ; current MP, low byte
        cmp     $01,s           ; MP - cost: C SET iff MP >= cost (affordable)
        bcs     @afford
        pla                     ; can't pay -- drop the parked cost
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

; [ boost picks the SwdTech — the charge gauge, deleted ]

; replaces UpdateMenuState_37's clock (btlgfx_main.asm @7d5f): the gauge
; ceiling `lda $2020 / inc / sta $36`, the every-4-frames `inc w7e7b82`,
; and the wrap check that followed it. vanilla ran a free bar — the
; counter climbed one unit per 4 frames, the tech was counter >> 5 (128
; frames a level, ~15 s to walk all eight known), it wrapped past the last
; one learned, and A latched whatever level it happened to be showing into
; $2bb0,y (btlgfx_main.asm:19083). the CLOCK is the part that is foreign
; here, so the clock is the part that goes: bp picks the level instead.
; every other piece of vanilla's window is untouched and now renders a
; STATIC selector that tracks L/R live — the numerals, the grey-out of
; unlearned techs (_c2a860), the bar, the A-button latch, FixPlayerAttack's
; +$55 (battle_main.asm:12811), Cmd_07's dispatch (battle_main.asm:3901,
; including its retort/sky stance special case).
;
; the mapping is a MOVING WINDOW OF FOUR (issue #5): boost 0/1/2/3 selects
; cyan's top four LEARNED techs, weakest -> strongest. every boost level lands
; on a distinct, useful tech (boost is never dead) and cyan always wields his
; best four. base = max(0, ceiling-3), tech = min(base + boost, ceiling), where
; ceiling is vanilla's own $2020 (techs known - 1, the same value that capped
; the bar). while he knows four or fewer techs base is 0 and every learned tech
; is reachable -- 0/1/2/3 land on exactly the ones he has. this REPLACES the
; old band table, which named each of four bands' TOP tech (fang / tiger /
; dragon / oblivion) and clamped it to the ceiling, so a 3-tech cyan got
; Dispatch / Slash / Slash / Slash and could never cast the Retort he had
; learned -- issue #5's bug. learn a fifth tech and the window slides up one,
; retiring the WEAKEST; never a mid-tier tech skipped.
;
; the retire is a real tradeoff: the low techs carry utility (Retort's counter
; stance $56, Empowerer's drain $59) and MP-cheapness that go quiet as cyan
; out-levels them. resolved for v0.5 (see docs/design/kits.md): ship the auto-
; window as-is, no special-casing of utility or a cheap-floor -- his MP pool
; grows with him, and the player-chosen loadout (the #5 sequel) is where the
; retire is answered. playtest is the filter.
;
; oblivion (tech 7, the divine) is the window's CONDITIONAL TOP RUNG, not a
; case bolted outside it: at full kit the window is {4,5,6,7} and boost 3 lands
; on 7 = oblivion by the same base+boost sum as any other rung -- it falls out
; for free. it is SELECTED here only when learned (ceiling 7) and unspent, and
; still fires exactly as before: gated at RESOLUTION by Ot6Oblivion (the proc
; name is internal; the screen prints the tech as Cleave) (hooked
; after ChooseTarget -- the target does not exist at this command-latch time,
; swdtech being in RetargetCmdTbl), and dropped back to tempest (6) here for
; the rest of any battle whose once-per-battle latch is already set. cyan
; learns oblivion off the phantom train, so the top rung is oblivion only at
; full kit.
;
; bp is READ, never written: the spend is whatever Ot6Boost banked in
; OT6_BOOST_REVEALED, so Ot6ActionEnd consumes it and skips that turn's regen exactly as
; for any other action, and the <=3 / never-past-bp caps stay Ot6Boost's
; alone. bp the ladder cannot spend (three points at level 1 still buys
; fang) is spent, not refunded — the same deal a mage takes when a third
; point on fire buys nothing past firaga.
;
; entry: from UpdateMenuState_37 — db=$7e, d=0, a8/i16, y=0 (the bar draw
; downstream indexes w7e7a73,y with it). returns a = the chosen level, as
; the vanilla block it replaces did. clobbers x.
;
; v0.5 SUBMENU (issue #8): SwdTech is now a tools-shell submenu -- one row per
; boost level, the row IS the boost, weakest at top. The base/ceiling arithmetic
; and the Cleave top-rung swap are factored into three leaf helpers below so
; single-select (this proc, called at the submenu's confirm latch) and the row
; ENUMERATION (Ot6BushidoWindow) can never diverge -- offering a tech the latch
; would not fire, or firing one the menu never showed. $7b82 is still stamped
; (level*32): battle_mpcost's level() reads it, and the dead numeral path can too.

