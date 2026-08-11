; ------------------------------------------------------------------------------
; SETZER -- THE BOOST-TIERED SLOT REELS (a chance verb buys certainty)
; ------------------------------------------------------------------------------
; Carved out of ot6_kits.asm (v0.9, 3037 lines) with the emission order of
; every instruction preserved: ot6.asm includes these files in exactly the
; order their text sat in the old one, so the assembler sees the identical
; token stream and the linker the identical segment. Proven, not argued --
; ROM CRC32 0x2E9B5A7F and ff6-en.map are byte-identical across the split.
; ------------------------------------------------------------------------------

; ==============================================================================
; BOOST-TIERED SLOT (Setzer) -- the chance-verb canon applied to the reels
;
; ROADMAP.md "Design canon" / kits.md "Boost-tiered Steal": on chance verbs
; boost buys CERTAINTY in the verb's own vocabulary. Slot's vocabulary is the
; reel rig, and vanilla's
; rig is ONE byte: w7e6179, a single Rand() drawn at the first A press of a
; spin (btlgfx_main.asm, UpdateMenuState_08 @7f16 -- OR'd with $3c when the
; battle disables joker doom, $2f49.2). Everything dishonest the machine does
; flows from `rig AND SlotRateTbl[icon]` ($1f,$03,$01,$01,$00,$00 for icons
; 0-5, btlgfx_main.asm SlotRateTbl @7ee1):
;   == 0 (blessed): the machine helps -- reel 2 drifts up to w7e617d = 4 extra
;        icons to MATCH reel 1's icon (@8053), and a landed pair drifts reel 3
;        the same way toward the TRIPLE (@808c);
;   != 0 (cursed): reel 2 gets no help, and -- the rigged miss proper -- a
;        landed pair marks w7e617c bit 7 so reel 3 REFUSES to stop on the
;        completing icon (@80c6): the triple is untimeable, by design.
; Reel 1 always stops honestly where the player timed it. The tiers escalate
; the machine's own drift/avoid vocabulary, one rung per rung:
;
;   0 BP  vanilla to the byte. Ot6SlotRig hands the drawn rig byte back
;         untouched; every downstream compare, drift and refusal is vanilla's.
;   1 BP  the machine stops cheating AGAINST you: the rigged miss is removed
;         (Ot6SlotMiss blesses any landed pair instead of avoid-marking it, so
;         reel 3 drifts toward the triple you earned). Reel 2's help is still
;         rig-rolled, exactly vanilla.
;   2 BP  the machine cheats FOR you: the rig byte is forced to 0, so EVERY
;         icon is blessed -- reel 2 drifts toward the pair and reel 3 toward
;         the triple, within vanilla's own 4-icon nudge physics. Still a
;         gamble (the drift budget can run out), just one tilted your way.
;   3 BP  the reel is CHOSEN: drift budget becomes $ff (the whole strip, every
;         icon appears on every reel -- SlotReelTbl @a800), so reels 2 and 3
;         spin until they MATCH. The triple of whatever icon the player
;         stopped reel 1 on is guaranteed: the selection is reel 1's honest,
;         vanilla-timed stop, so "the player's selection lands" with zero UI
;         change. (True per-reel choice needs no new UI -- choosing the
;         outcome IS choosing reel 1's icon, since the result vocabulary is
;         triples; the non-triple results, 7-7-BAR self-doom and lagomorph,
;         are the machine's punishments, and certainty is exactly their
;         removal.)
;
; The joker-doom battle gate outranks boost at every tier: where vanilla ORs
; the rig with $3c ($2f49.2 set), tier 2/3 force $3c instead of 0, and
; Ot6SlotMiss keeps the avoid mark on a 7-pair -- a battle that forbids
; joker doom cannot be bought out of it (vanilla's own prohibition, kept).
;
; THE CHARGE. The tier is LATCHED from OT6_BOOST_REVEALED at the first A
; press (the spin cannot be backed out of after that -- B exits only while
; w7e7b92/93/94 are all clear, @7fec), and Ot6SlotCommit writes the latch
; back to OT6_BOOST_REVEALED at the commit press, so Ot6ActionEnd charges
; exactly the tier the reels were spun with. Without the latch an L/R edge
; during the multi-second spin changes the charge without changing the reels
; -- battle_lateboost's delivered-vs-charged theft, reopened through the reel
; window (Ot6Boost's $32cc/$2bae commit gates only close AFTER the queue
; write). NO MP price on Slot in this change (mp-economy.md's Slots pricing
; waits on the price-display surface -- one gap at a time).
;
; The latch lives in the $57ba spare byte of the init-exempt OT6 strip
; ($57ba-$57bf, ot6_hud.asm's block comment; probe_57ba_strip's bank-F0-only
; writer invariant holds -- these procs assemble into bank $f0). Stale values
; are harmless: every read below happens inside a spin, and every spin's
; first press rewrites the latch. TODO(ABI): fold into ot6_memory.inc beside
; the other strip names when that file's owner takes it.
; OT6_SLOTTIER lives in ot6_memory.inc with the rest of the $57xx strip.

; ------------------------------------------------------------------------------

; [ latch the spin's tier + tier the rig byte (first A press of a spin) ]
;
; replaces UpdateMenuState_08's `sta w7e6179` (the rig-byte store): A arrives
; holding vanilla's freshly drawn rig byte (Rand, or Rand|$3c when the battle
; disables joker doom) and leaves stored to w7e6179, tiered. Also the latch
; write: OT6_SLOTTIER = the active character's pending boost, capped at 3.
; a8, db=$7e (the menu bank's own context); index width unknown at the site,
; so php/longi pins it. clobbers x (the caller's next act reads no register).
.proc Ot6SlotRig
        .a8
        php
        longi
        .i16
        pha                     ; park the vanilla rig byte
        lda     $62ca           ; active character slot -> entity offset
        and     #$03
        asl
        longa
        and     #$00ff
        tax
        shorta0
        lda     OT6_BOOST_REVEALED,x       ; pending boost (0-3)
        cmp     #$04
        bcc     :+
        lda     #$03            ; (defensive: Ot6Boost already caps at 3)
:       sta     f:$7e0000+OT6_SLOTTIER     ; the spin's tier, latched
        cmp     #$02
        bcs     @force          ; tier 2/3: the rig is forced, not rolled
        pla                     ; tier 0/1: vanilla's own rig byte stands
        bra     @sto
@force: pla                     ; drop the rolled byte
        lda     $2f49
        and     #$04            ; joker doom disabled this battle?
        beq     :+              ;   (vanilla's `beq` = enabled)
        lda     #$3c            ; disabled: everything blessed EXCEPT the 7s
        bra     @sto            ;   ($3c & SlotRateTbl: $1f traps, $03/$01 pass)
:       lda     #$00            ; enabled: every icon blessed
@sto:   sta     $6179           ; w7e6179 -- the rig byte the two rate checks AND
        plp                     ;   the reel-2/3 drift logic read all spin long
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ the drift budget: 4 icons (vanilla) or the whole strip (tier 3) ]
;
; replaces both `lda #$04 / sta w7e617d` blessed-arm stores (reel-2 @7f5f and
; reel-3 @7f9b). w7e617d is how many extra icons a blessed reel may spin past
; while hunting the match; vanilla's 4 makes the help a nudge. Tier 3 spends
; $ff -- longer than the 16-icon strip, and every icon appears on every strip
; (SlotReelTbl), so the hunt ALWAYS lands: that is the whole "chosen" rung.
; a8, db=$7e. clobbers a only.
.proc Ot6SlotDrift
        .a8
        lda     f:$7e0000+OT6_SLOTTIER
        cmp     #$03
        bcc     @nudge
        lda     #$ff            ; tier 3: seek until matched (guaranteed)
        bra     @sto
@nudge: lda     #$04            ; vanilla's own four-icon nudge, to the byte
@sto:   sta     $617d           ; w7e617d
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ the rigged miss, removed at 1+ BP (third press, pair landed, rig cursed) ]
;
; replaces the avoid arm's `lda $3a / ora #$80` (@7fa6): vanilla marks the
; pair's icon with bit 7 so the reel-3 spin driver (@80c6) SKIPS it -- the
; player physically cannot time the triple. Tier 0 keeps that mark to the
; byte. Tier 1+ blesses the pair instead: drift budget via Ot6SlotDrift, and
; the plain icon falls through to the caller's `sta w7e617c`, the same bytes
; the blessed arm stores -- reel 3 now seeks the triple the player earned.
; A 7-pair in a joker-doom-disabled battle keeps the vanilla mark at every
; tier (the battle gate outranks boost; see the region comment).
; a8, db=$7e, d = the menu's (its $3a scratch = the pair's icon, GetSlotReel2's
; result). returns a = the value for w7e617c. clobbers a only.
.proc Ot6SlotMiss
        .a8
        lda     f:$7e0000+OT6_SLOTTIER
        beq     @avoid          ; tier 0: the vanilla rigged miss stands
        lda     $3a             ; the landed pair's icon
        bne     @bless          ; not the 7s: the miss is bought off
        lda     $2f49
        and     #$04            ; a 7-pair under the joker-doom battle gate
        bne     @avoid          ;   stays refused at any price
@bless: jsl     Ot6SlotDrift    ; budget: 4 (tier 1/2) or the strip (tier 3)
        lda     $3a             ; bless: reel 3 seeks the completing icon
        rtl
@avoid: lda     $3a
        ora     #$80            ; vanilla: reel 3 refuses the completing icon
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ commit the spin: queue the actor + re-bank the latched tier ]
;
; replaces the commit press's `lda w7e62ca / sta $2bae,y` (@7fd9): the vanilla
; store first (y = the queue row _c16d56 just computed), then the charge fix:
; OT6_BOOST_REVEALED = the latch, so Ot6ActionEnd charges the tier the reels
; were actually spun with. An L edge mid-spin can no longer buy a chosen
; triple at a discount, and an R edge mid-spin (banked but never read by the
; already-latched spin) is handed back rather than charged for nothing --
; delivered == charged, both directions (battle_lateboost's rule).
; a8, db=$7e; y preserved (the sta uses it before any width games).
.proc Ot6SlotCommit
        .a8
        lda     $62ca
        sta     $2bae,y         ; vanilla: the actor commits the queued action
        php
        longi
        .i16
        and     #$03
        asl                     ; slot -> entity offset
        longa
        and     #$00ff
        tax
        shorta0
        lda     f:$7e0000+OT6_SLOTTIER
        sta     OT6_BOOST_REVEALED,x       ; charge what the reels delivered
        plp
        rtl
.endproc
