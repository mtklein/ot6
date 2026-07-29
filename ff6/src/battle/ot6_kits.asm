; ==============================================================================
; BUSHIDO LOADOUT (issue #8 Layer B) -- per-save, field-configurable slots
;
; Storage: a 16-bit little-endian WORD in two unused bytes inside the working-
; save block ($1600-$1fff) that save.asm's CopyGameDataToSRAM/LoadSaveSlot
; round-trip per slot and CalcSaveSlotChecksum ($1600-$1ffd) covers -- so the
; loadout PERSISTS and VALIDATES for free, no checksum work and zero migration
; (every existing save reads $1e1d..$1e1e = $0000 = AUTO):
;
;   $1e1d..$1e1e   packed word.  Cyan has exactly 8 SwdTechs (index 0..7 = 3
;                  bits), so the four boost slots fit in 12 bits:
;                    slot0 (RETIRED, #38)           slot2 (boost 2x) = bits 6-8
;                    slot1 (boost 1x) = bits 3-5    slot3 (boost 3x) = bits 9-11
;                  (top 4 bits unused, kept 0).  Each field is the same 0..7
;                  INDEX Ot6BushidoTech returns, so the downstream +$55 /
;                  Ot6BushidoOblivion tail stays byte-for-byte unchanged.
;
; [ issue #38: every Bushido tech costs at least 1 BP ]
; Owner ruling from the rc1 playtest: "the 0 boost ability feels a bit too much
; like better attack."  Cyan's sword-art is SPENDING BANKED TIME, so a 0-pip
; tech competed with Fight instead of with the bank.  The floor is now 1 BP:
; the submenu and the field configurator both show exactly THREE rows -- 1x,
; 2x, 3x -- and his no-pip turn is Fight, as it should be.
;
; The STORED FORMAT DID NOT MOVE.  The word is still two bytes at $1e1d with
; four 3-bit fields, because every tracked battery anchor was minted against
; persistent_layout ot6-codex-o8-v1 and a schema change invalidates all of
; them.  What changed is that SLOT 0 IS NEVER READ: rows map i -> boost i+1 ->
; word slot i+1, and slot 0 is left as whatever Ot6LoadoutSeedWord's mirror
; wrote (see there).  Old saves keep decoding: a MANUAL word's slots 1..3 mean
; exactly what they meant before, and word 0 is still AUTO.
;
; AUTO re-derived for three rungs: the window is the TOP THREE learned techs,
; base = max(0, ceiling-2), tech = min(base + boost-1, ceiling).  At the full
; kit (ceiling 7) that is {5,6,7} at 1x/2x/3x -- the same three techs the old
; four-rung window put at boosts 1/2/3, so the tuned top of the ladder (and
; Oblivion on 3x) is unchanged; only the free rung is gone.
;
; word == 0  -> AUTO (the moving window).  This is ALSO the sentinel: an all-zero
;   word decodes to "all four slots = tech 0", a degenerate config no player sets
;   on purpose, and every existing save already has 0 there -> auto with zero
;   migration (the same property the old mode-flag-0 had).  word != 0 -> MANUAL:
;   unpack the 3-bit field per slot.  Revert-to-auto writes $0000.
;
; One physical cell $7e1e1d (DBR = $7e in battle); read long (f:) so the hook
; is bank-agnostic.  With the word = 0 the battle path is identical to Layer A.
; ==============================================================================

; [ Bushido ceiling — techs-known-minus-1, read safe (issue #4) ]
; InitSkills stores $2020 with a 16-bit `stx` over CountBits's uninitialized
; HIGH byte ($ff02 in the Doma solo fight, $ffff before Cyan joins); read as a
; WORD the junk high byte made even a real 2-tech ceiling `>= 8` and collapse to
; 0, pinning Cyan to Dispatch. Read a8 the junk is ignored, and a genuinely-
; unlearned $ff (low byte) still trips >= 8 into the nothing-learned path.
; a8.  out: A = ceiling (0..7).  preserves X and Y.
.proc Ot6BushidoCeil
        .a8
        lda     $2020           ; techs known - 1, LOW BYTE ONLY (issue #4)
        cmp     #$08
        bcc     :+
        lda     #$00            ; nothing learned: only tech 0 (Dispatch) exists
:       rtl
.endproc

; [ Bushido moving window of three (issue #5, refloored by #38) — boost -> tech ]
; boost 1/2/3 selects Cyan's TOP THREE learned techs, weakest -> strongest:
; base = max(0, ceiling-2), tech = min(base + boost-1, ceiling). while he knows
; three or fewer, base is 0 and EVERY learned tech is reachable; learn a fourth
; and the window slides up one, retiring the weakest. no table -- pure
; arithmetic.  boost 0 no longer names a tech (#38's 1-BP floor); it is clamped
; to 1 rather than allowed to underflow the window, so any caller that reaches
; here with a cleared pending byte gets the cheapest rung instead of garbage.
; a8/i16.  in: A = boost (0..3).  out: A = tech (0..ceiling).  clobbers X.
.proc Ot6BushidoTech
        .a8
        .i16
        cmp     #$01            ; #38: the floor is 1 BP -- clamp a stray 0 up
        bcs     :+              ;   (the menu never offers boost 0 any more)
        lda     #$01
:       pha                     ; park boost ($01,s). the two scratch bytes in
                                ;   reach ($36 btlgfx's, OT6_SCR_BIT the hud
                                ;   builder's) both have owners; the stack owes
                                ;   nobody and survives an nmi.
        ; [ issue #8 Layer B: manual-loadout read hook -- packed 2-byte word ]
        ; word 0 (all existing saves) -> @auto, the vanilla window untouched.
        ; word nonzero -> return the player's stored tech for THIS boost slot
        ; (slot s = the 3-bit field at bit s*3), but only if it is still learned
        ; ($1cf7 bit set); otherwise fall back to the auto window for this slot
        ; rather than offer an uncastable tech.  Unpack and learned-test are the
        ; SAME F0 leaves the menu draw uses (Ot6LoadoutUnpack / Ot6TechLearned),
        ; so battle and menu can never decode the word differently.  Callers run
        ; Ot6BushidoOblivion AFTER us, so a manually-placed Oblivion (tech 7)
        ; keeps its spent-divine -> Tempest swap.
        longa
        lda     f:OT6_LOADOUT   ; packed loadout word (0 = AUTO)
        shorta                  ; plain SEP #$20 -- keeps Z (shorta0's tdc wipes it)
        beq     @auto
        lda     $01,s           ; boost (0..3) = slot
        jsl     Ot6LoadoutUnpack    ; A = stored tech for this slot (clobbers X)
        jsl     Ot6TechLearned      ; carry = learned (A and Y preserved)
        bcc     @auto           ; stored tech not learned -> auto fallback
        sta     $01,s           ; learned: overwrite the parked boost with tech
        pla                     ; A = tech (mirrors @auto's balanced tail)
        rtl
@auto:
        jsl     Ot6BushidoCeil  ; A = ceiling (preserves nothing we need)
        pha                     ; park ceiling ($01,s ; boost now $02,s)
        sec
        sbc     #$02            ; ceiling - 2   (A still = ceiling) -- #38: the
        bcs     :+              ;   window is three rungs wide, not four
        lda     #$00            ; ceiling < 2: base floors at 0 (the window is all
:       ;                       ;   of {0..ceiling}, fewer than three techs)
        clc
        adc     $02,s           ; base + boost
        dec     a               ;   ... - 1 -> the tentative tech (boost >= 1 is
                                ;   guaranteed by the clamp at entry, so this
                                ;   cannot underflow; dec leaves C alone for the
                                ;   cmp below)
        cmp     $01,s           ; vs the ceiling
        bcc     :+
        lda     $01,s           ; cap at ceiling -- bites only when boost overruns
:       ;                       ;   a <4-tech window (e.g. 3 bp, 3 techs known)
        sta     $02,s           ; stash the chosen tech over the parked boost byte
        pla                     ; drop the parked ceiling
        pla                     ; a = chosen tech 0-7 (stack balanced)
        rtl
.endproc

; [ Bushido Oblivion top-rung swap ]
; the window's top rung IS Oblivion (tech 7) once Cyan has learned all eight:
; ceiling 7, boost 3 -> base 4 + 3 = 7, by the same base+boost sum as any other
; rung -- the divine falls out of the window for free, no special case bolted
; outside it. it fires exactly as before: SELECTED here only when learned and
; unspent, gated at RESOLUTION by Ot6Oblivion (hooked after ChooseTarget in
; CalcAttackEffect -- the target does not exist at command-latch time, swdtech
; being in RetargetCmdTbl). read the once-per-battle latch here and drop a spent
; Oblivion back to Tempest (6) so BP3 keeps a live top rung. (a divine is spent
; only on a broken, killable target; an unbroken/boss target folds to tempest at
; RESOLUTION and leaves the latch clear, so the menu keeps offering it.)
; a8/i16.  in: A = tech (0..7).  out: A = tech (a spent tech-7 -> 6).  clobbers X.
.proc Ot6BushidoOblivion
        .a8
        .i16
        cmp     #$07
        bne     @done           ; not oblivion: the chosen tech stands
        lda     $62ca           ; re-derive the active char's entity bit
        and     #$03
        asl                     ; slot * 2 = entity offset
        longa
        and     #$00ff
        tax
        shorta0
        lda     $3018,x         ; active char's bit ($01/$02/$04/$08)
        and     OT6_DIVINE_USED ; already spent the divine this battle?
        beq     @obl            ; no: oblivion stands
        lda     #$06            ; yes: revert to tempest for the rest of it
        rtl
@obl:   lda     #$07            ; oblivion
@done:  rtl
.endproc

.proc Ot6BushidoTier
        .a8
        .i16
        lda     $62ca           ; active character slot
        longa
        and     #$0003
        asl
        tax                     ; -> entity offset
        shorta0
        lda     OT6_BOOST_REVEALED,x         ; pending boost 0-3
        cmp     #$04
        bcc     :+
        lda     #$03            ; (defensive: Ot6Boost already caps at 3)
:       jsl     Ot6BushidoTech      ; boost -> tech (shared window math)
        jsl     Ot6BushidoOblivion  ; spent-divine top rung -> tempest
        pha
        asl5                    ; level * 32 — the counter value vanilla's
        sta     $7b82           ;   bar drew, so w7e7b82 still feeds the
        pla                     ;   latch, the fill, and battle_mpcost's level()
        rtl
.endproc

; ==============================================================================
; DIVINE ABILITIES (kit slot 8) -- resolution-time gates + once-per-battle latch
;
; The kit-8 divines whose gates cannot be read at command-SELECT time land here,
; gated at RESOLUTION, where the target finally exists. Each is once-per-battle
; through OT6_DIVINE_USED (per-character bit, $3ecb): the latch is READ at select
; time (Ot6BushidoTier drops a spent Oblivion back to Tempest) and SET the
; instant the divine actually lands. Every divine rides the boost economy
; exactly as its kit does -- BP is spent through Ot6ActionEnd like any boosted
; action, and (per the counterattack audit, the $b1.0 convention this file keeps
; in Ot6BoostDmg/Ot6FightBoost/Ot6QueueFold) a countered action never reaches
; ActionEnd to charge, so the divines inherit that invariant through the
; commands they ride. This region is deliberately distinct from the HUD-flush
; and sub-jobs regions.
; ------------------------------------------------------------------------------

; [ Oblivion (Cyan, Bushido tech 8): instant death iff the target is Broken ]
;
; kits.md: "Oblivion (divine) | 3, target must be Broken". The tech is vanilla
; swdtech 8, attack id $5c, which magic_prop already builds as a pure
; instant-death strike -- power 0, Status-1 $80 (Death), the $11a2.1
; instant-death-spell flag, and $11a7.0 "auto-miss if the target is immune to
; the status". What it LACKED was the Broken gate, and the survey that shipped
; Ot6BushidoTier left it out of the ladder because that gate cannot be read at
; command-latch time: swdtech is in RetargetCmdTbl (battle_main.asm:12810), which
; CLEARS the target there; the target is then re-chosen at RESOLUTION.
;
; The gate is read at exactly the one seam where the target FINALLY exists and
; the attack's properties are still editable: immediately after ChooseTarget in
; CalcAttackEffect (battle_main.asm:8185), which fills $b8/$b9 for this attack.
; (An earlier draft hooked Cmd_07's first instruction and always read an EMPTY
; target -- the retarget had cleared it and InitCmdTarget had not yet re-picked
; it -- so every Oblivion folded; battle_divines' broken-kill drive caught it.)
; Here x is still the attacker (CalcAttackEffect indexes $3c08,x etc. right
; below), $3a7d is the resolved attack id, and the loaded MagicProp bytes
; ($11a6 power, $11aa Status-1, $11a2/$11a7 flags) are the ones the per-target
; loop about to run will consume.
;
;   Broken and killable  -> mark Death directly in the target's "status to set"
;                           ($3dd4, what SetStatus1 writes at :2254, applied by
;                           UpdateStatus :11067 for every present entity INDE-
;                           PENDENT of the hit roll) -- a GUARANTEED kill, the
;                           Break window IS the guarantee, the same ruling
;                           Assassinate takes. SET the once-per-battle latch.
;   unbroken, OR a Broken
;   but death-immune boss -> the props are SURGERIED to a Tempest-like hit in
;                           place: power 70, Status-1 cleared (no Death), the
;                           instant-death-spell and auto-miss flags cleared. The
;                           per-target loop then lands a 70-power elementless
;                           slash -- the honest "reduced" fallback (kits.md names
;                           fizzle-or-reduced). Keeping a real hit as the
;                           fallback is the whole reason Oblivion could rejoin
;                           the BP3 band without retiring Tempest, and the latch
;                           stays CLEAR (the divine was not spent), so the menu
;                           keeps offering Oblivion until it truly lands.
;
; The death-immune fold matters because a boss can be Broken too (bosses carry
; shields, DESIGN.md): without it, Oblivion vs a Broken boss would burn the
; once-per-battle latch on a target its Death can never take. Folding it to a
; Tempest hit spends the turn on damage and keeps the divine in the player's
; pocket.
;
; entry: jsl from CalcAttackEffect just after ChooseTarget. a16/i8, db=$7e;
; x = attacker entity offset, $b8/$b9 = target mask, $3a7d = attack id. preserves
; x (the caller indexes it right after) and y; may edit $11a6/$11aa/$11a2/$11a7.

.proc Ot6Oblivion
        php
        shortai
        .a8
        .i8
        lda     $3a7d
        cmp     #$5c            ; oblivion's attack id?
        bne     done            ; no: this attack is untouched
        phx                     ; save the attacker entity offset (i8, 1 byte)
        ; --- primary target -> entity offset. The mask is SPLIT: $b8 low byte
        ;     is characters (bit c -> offset c*2), $b9 high byte is monsters
        ;     (bit m -> offset 8 + m*2), NOT one flat 16-bit field. A swdtech
        ;     lands on an enemy, so try the monster half first. ---
        ldx     #$08
        lda     $b9             ; monster mask (slots 0-5)
@mon:   lsr
        bcs     @have
        inx
        inx
        cpx     #$14            ; 8 + 6*2
        bcc     @mon
        ldx     #$00
        lda     $b8             ; character mask (slots 0-3)
@chr:   lsr
        bcs     @have
        inx
        inx
        cpx     #$08
        bcc     @chr
        plx                     ; no target bit: restore attacker, bail
        bra     done
@have:  ; x = target entity offset
        lda     OT6_BROKEN_TICKS,x         ; broken timer (nonzero = Broken)
        beq     @tempest        ; not broken: reduced fallback
        lda     $3aa1,x
        bit     #$04            ; Broken but death-immune (a boss)?
        bne     @tempest        ; ... its Death can't take: fall back
        ; --- Broken and killable: GUARANTEED kill + spend the divine ---
        lda     $3dd4,x
        ora     #$80            ; Death (status to set)
        sta     $3dd4,x
        plx                     ; x = attacker entity offset
        cpx     #$08
        bcs     done            ; (defensive: only characters own a divine)
        lda     $3018,x         ; attacker's entity bit ($01/$02/$04/$08)
        tsb     OT6_DIVINE_USED ; latch: divine spent this battle
        bra     done
@tempest:
        plx                     ; discard the saved attacker (unused on this arm)
        lda     #$46            ; TEMPEST power (70): the reduced fallback
        sta     $11a6
        stz     $11aa           ; clear Status-1 to inflict -- no Death $80
        lda     $11a2
        and     #$fd            ; clear the instant-death-spell flag (bit 1)
        sta     $11a2
        lda     $11a7
        and     #$fe            ; clear auto-miss-if-status-immune (bit 0)
        sta     $11a7
done:   plp
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ Assassinate (Shadow, divine): instant-kill a Broken non-boss ]
;
; kits.md sketch: "Shadow -- Assassin (piercing, thrown): Throw signature; ...
; divine Assassinate -- instant kill a Broken non-boss." The two LOAD-BEARING
; gates the sketch names are the Broken check (OT6_BROKEN_TICKS nonzero) and the non-boss
; check ($3aa1 bit 2 -- the instant-death-protection bit a boss carries, the
; same one ScimitarEffect reads at battle_main.asm:9147). Both are read at the
; SAME seam Oblivion uses -- after ChooseTarget in CalcAttackEffect, where the
; target finally exists -- so the kill is the same guaranteed $3dd4 Death mark
; (SetStatus1's byte, applied by UpdateStatus for every present entity regardless
; of the hit roll) and the once-per-battle gate is the shared OT6_DIVINE_USED
; bit. A Broken non-boss dies; a boss (its Death can't take) or an unbroken
; target is left alone -- the ordinary attack stands, the honest no-op fallback.
;
; UNDERSPECIFIED, reported not invented: the sketch does not say HOW Shadow
; invokes it -- his Throw signature, a dedicated command, or a boost cost -- and
; his kit is not built. This milestone ships the CLEAR CORE (the two gates + the
; guaranteed kill + the once-per-battle latch) gated on the attacker being SHADOW
; (char id $03, $3ed8 keyed by the entity offset since offset = slot*2) with an
; unspent divine: any attack Shadow lands on a Broken non-boss assassinates it,
; once per battle. That is the simplest faithful reading; narrowing it to
; Throw-only ($b5 == $08) or adding an arming cost is a one-line change to the
; gate below once his kit and its invocation are designed. It is DORMANT until
; then -- no Shadow is fielded, so the char-id gate never matches.
;
; entry: jsl from CalcAttackEffect just after ChooseTarget (beside Ot6Oblivion).
; a16/i8, db=$7e; x = attacker entity offset, $b8/$b9 = target mask. preserves
; x (the caller indexes it right after) and y.

.proc Ot6Assassinate
        php
        shortai
        .a8
        .i8
        cpx     #$08
        bcs     done            ; monster attacker: never
        lda     $3ed8,x         ; attacker char id (offset = slot*2)
        cmp     #$03            ; CHAR::SHADOW
        bne     done            ; not shadow: dormant
        lda     $3018,x
        and     OT6_DIVINE_USED
        bne     done            ; divine already spent this battle
        phx                     ; save attacker (i8, 1 byte)
        ; --- primary target -> entity offset. $b8 low = characters (bit c ->
        ;     offset c*2), $b9 high = monsters (bit m -> offset 8 + m*2). We want
        ;     an enemy, so scan the monster half only. ---
        ldx     #$08
        lda     $b9             ; monster mask (slots 0-5)
@mon:   lsr
        bcs     @have
        inx
        inx
        cpx     #$14
        bcc     @mon
        plx                     ; no monster target: bail
        bra     done
@have:  cpx     #$08
        bcc     @bail           ; a character target: not an enemy
        lda     OT6_BROKEN_TICKS,x         ; Broken?
        beq     @bail           ; no: ordinary attack
        lda     $3aa1,x
        bit     #$04            ; a boss (instant-death protected)?
        bne     @bail           ; yes: no-op fallback (its Death can't take)
        ; --- Broken non-boss: assassinate (guaranteed) + spend the divine ---
        lda     $3dd4,x
        ora     #$80            ; Death (status to set)
        sta     $3dd4,x
        plx                     ; x = attacker entity offset
        lda     $3018,x
        tsb     OT6_DIVINE_USED
        bra     done
@bail:  plx                     ; restore attacker; the attack stands untouched
done:   plp
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ open the Blitz command as a menu (v0.3 -- blitz-as-menu, stage 1) ]

; vanilla Blitz had no window: _c1776b armed the 64-frame pad-edge buffer and
; UpdateMenuState_3d matched button codes. This module deletes that path and
; drives Blitz through the Tools window shell instead. _c1776b now jsl's here,
; then jmp's OpenToolsWindow: we fill wItemList ourselves with the LEARNED
; blitzes, raise the mode flag the two btlgfx shims read (w7e6168, freed when
; UpdateMenuState_3d went), and jump the tools state machine straight to its
; draw phase (w7e7b9e=4) so it skips the four inventory-scan phases it would
; run for real tools.  We deliberately do NOT reset the shared cursor: the
; Tools shell already honored the Config>Cursor (Memory/Reset) setting for it
; at command-window-open time, and re-zeroing it here would defeat that -- see
; @padded.
;
; the row id we store is the resolved attack id $5d+i (Pummel $5d .. Bum Rush
; $64): ListTextCmd_0f renders ids >=$51 from AttackName for free, and the
; confirm shim subtracts $5d back to the raw index 0-7 that cmd $0a expects --
; the SAME index UpdateMenuState_3d wrote, so FixPlayerAttack (validates i
; against $1d28, adds +$5d) and the Vargas AI (reads the resolved $5d) are
; untouched. Only LEARNED blitzes appear, so that validation never trips.
;
; entry: jsl from _c1776b (btlgfx C1), db=$7e, a8/i16. clobbers a/x/y (the
; caller's next act is jmp OpenToolsWindow, which reloads what it needs).

.proc Ot6BlitzListOpen
        .a8
        .i16
        ; --- pack the learned blitzes into wItemList ($7e4005, 3 bytes/row) ---
        ldx     #$0000          ; wItemList write offset
        ldy     #$0000          ; blitz index 0-7
        lda     $1d28           ; known-blitz bitmask (the byte FixPlayerAttack
@bit:   lsr                     ;   validates); carry = bit for blitz Y
        bcc     @next
        pha                     ; park the shifted mask on the stack -- $36 and
        tya                     ;   OT6_SCR_BIT both have owners here, the stack
        clc                     ;   owes nobody and survives an nmi
        adc     #$5d            ; attack id $5d + blitz index
        sta     $4005,x         ; wItemList::Index
.if ::OT6_MP_COSTS              ; :: -- ca65 resolves .if in the proc's local
                                ;   scope; force the file-scope flag
        jsl     Ot6CostFor      ; A(id) -> A(cost); preserves X and Y
        sta     $4006,x         ; wItemList::Qty = MP cost -- Qty is otherwise
                                ;   free here, and the row-draw shim reads it
.endif
        inx
        inx
        inx                     ; next row
        pla                     ; unpark the mask
@next:  iny
        cpy     #$0008
        bne     @bit
        ; --- $ff-terminate through the 8-cell (4x2) window ---
        lda     #$ff
@pad:   cpx     #$0018          ; 8 rows * 3 bytes
        bcs     @padded
        sta     $4005,x
.if ::OT6_MP_COSTS              ; :: -- force the file-scope flag from in-proc
        stz     $4006,x         ; Qty=0: an empty cell's cost draws as two blanks
.endif
        inx
        inx
        inx
        bra     @pad
@padded:
        ; --- LEAVE the shared cursor triple alone: honor Config>Cursor ---
        ; the Tools shell already applied the Cursor (Memory/Reset) setting to
        ; this character's triple ($895f scroll / $8963 col / $8967 row) when the
        ; command window opened -- UpdateMenuState_04 (btlgfx_main.asm:13343)
        ; reads f:$001d4e, and when bit6 is CLEAR (Reset) stz-loops the whole
        ; 92-byte cursor block $890f..$896a to zero; when SET (Memory) it skips
        ; that loop, so last turn's positions survive.  The old code here zeroed
        ; the triple UNCONDITIONALLY, overriding that decision and snapping
        ; Blitz to the top row whatever the setting -- the owner-reported bug.
        ; Blitz reuses the Tools triple under the same per-slot index ($62ca),
        ; so doing nothing makes it obey the bit exactly like Tools/Magic/Item.
        ; A remembered row indexes the packed $5d+i list directly (in-battle the
        ; learned set is fixed), so no id-to-row mapping is needed.  We still
        ; force a fresh window re-init below.
        stz     $7ba5           ; force MakeToolsList_04 to re-init the window
        ; --- jump the tools state machine to its draw phase ---
        lda     #$04
        sta     $7b9e           ; w7e7b9e (MakeToolsList phase) -> MakeToolsList_04
        ; --- raise the blitz-mode flag the row-draw / confirm shims read ---
        lda     #$01
        sta     $6168           ; w7e6168
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ draw one Blitz menu row -- the names, and (priced build) their MP cost ]
;
; DrawToolsListText (btlgfx, bank C1 -- FULL) jsl's here for a blitz-mode row,
; in place of the two inline "$0e item-name -> $0f attack-name" stores it used
; to do. Relocating that swap into bank F0 buys the priced build room to ALSO
; stamp an MP cost after each name without growing the full C1 bank: the whole
; feature costs C1 a single 4-byte jsl (net -4 bytes there), the logic all rides
; here. This is the first menu-bank module -- the visual half of the mp-cost
; feature the hidden charge has been waiting on.
;
; the line buffer w7e5755 already holds the copied Tools template plus the two
; row ids (the caller wrote Index,y -> +5 and Index+3,y -> +11 before the jsl);
; w7e6168 is the blitz flag the caller just tested. entry from a jsl: db=$7e
; (the caller draws through it), a8, Y = drawn-row * 6 -- so Qty,y is the left
; cell's cost and Qty+3,y the right cell's. clobbers A only (the caller reloads
; it in InitListTextTfr and never re-uses this derived Y).
;
; ALWAYS assembled: the stock C1 object jsl's it in BOTH the priced and the
; OT6_MP_COSTS=0 baseline build, so it must resolve in both. Only the cost
; stamping is flag-gated -- the nomp row stays the byte-identical two-name
; layout. w7e5755 = $5755 near; the numeric literals below are its +4..+15.
.proc Ot6BlitzRowDecorate
        php
        sep     #$20            ; 8-bit A for the byte stores
        .a8
        .i16
        lda     #$0f            ; left cell: render from AttackName, not ItemName
        sta     $5759           ; w7e5755+4  -- name command, column 1
.if ::OT6_MP_COSTS              ; :: -- force the file-scope flag from in-proc
        ; the name is a fixed 10-wide field; stamp a 2-digit MP cost right after
        ; it, a gap space, then column 2's name and its own cost. ListText cmd
        ; $02 draws two digits with a blank tens-place, so a 0 cost (a padded
        ; empty cell, Qty pre-zeroed) renders as two blanks -- a clean gap.
        ; The $04,$21 font at +2/+3 (rode in from the copied template) colors the
        ; column-1 name AND its trailing cost together; grey that byte when the
        ; caster can't afford the row, the twin of magic greying spell+MP as one.
        lda     $4006,y         ; wItemList::Qty,y     (column-1 cost)
        jsl     Ot6AbilityGrey  ; -> $04 grey / $00 white; preserves X and Y
        jsl     Ot6BushidoRowGrey ; bushido (w7e6168=2): ALSO grey a row whose boost
                                ;   exceeds current bp; blitz passes A through
        ora     $5758           ; +3   column-1 font palette: $21 -> $21/$25
        sta     $5758
        lda     #$02
        sta     $575b           ; +6   number command      (column-1 cost)
        lda     $4006,y         ; wItemList::Qty,y         (column-1 cost value)
        sta     $575c           ; +7
        lda     #$ff
        sta     $575d           ; +8   space between the columns
        lda     #$04
        sta     $575e           ; +9   set-font command
        lda     $4009,y         ; column-2 cost -- grey column 2's font the same
        jsl     Ot6AbilityGrey  ;   way; +9/+10 colors column-2's name AND cost
        ora     #$21            ; +10  font palette: $21 white or $25 grey
        sta     $575f
        lda     #$0f
        sta     $5760           ; +11  name command         (column 2)
        lda     $4008,y         ; wItemList::Index+3,y     (column-2 id, moved)
        sta     $5761           ; +12
        lda     #$02
        sta     $5762           ; +13  number command       (column-2 cost)
        lda     $4009,y         ; wItemList::Qty+3,y       (column-2 cost value)
        sta     $5763           ; +14
        stz     $5764           ; +15  terminator
.else
        lda     #$0f            ; nomp baseline: the old layout -- swap column 2's
        sta     $575f           ;   name only (w7e5755+10), no cost, no re-layout
.endif
        plp
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ draw one Tools menu row -- a leading 2-digit price per name, greyed if
;   the caster can't afford it ]
;
; DrawToolsListText (btlgfx, bank C1) jsl's here for a REAL tools row (the
; not-blitz arm), the twin of the Ot6BlitzRowDecorate call one branch over.
; Unlike Blitz, the vanilla tools row already draws correctly, so this shim
; only stamps each tool's MP cost and greys the pair (name + price) the caster
; cannot pay for -- Ot6AbilityGrey, the same $21->$25 magic uses.  In the nomp
; battle object the OT6_MP_COSTS block below is empty and the proc is a no-op
; that leaves the vanilla two-name layout byte for byte.  ALWAYS assembled --
; the shared C1 object calls it in both builds -- so the flag gating lives here
; in the battle object, never in btlgfx.
;
; LAYOUT / FIT FINDING (see build/states/shots/tools_cost_display.png): the
; tools window is two columns of 13-wide ITEM names (AutoCrossbow, NoiseBlaster,
; ...), and those already fill the row edge to edge -- a Blitz-style cost AFTER
; each name overflows the 32-tile screen (verified: probe_tools_2col rendered
; the bare names reaching the right border).  A true single column would fit a
; trailing cost but needs the tools window to SCROLL (it is a fixed 4x2 grid
; whose max-scroll is hardwired to zero), which means re-cutting the shared
; item/throw cursor + draw state machine -- out of proportion for a cost label.
; So the cost goes in the row's LEADING pair instead, and each column is laid
; out [font][cost][name] so its one font command colors the price and the name
; as a unit (what greying needs).  The template's "$05,$02 draw-two-spaces"
; ahead of name 1 (buffer +0/+1) and its "$ff $ff" gap ahead of name 2 (+6/+7)
; become the two font commands; the two costs move to +2/+3 and +8/+9 (the old
; font slots).  A $04 font command draws nothing, so the price still lands on
; the same two tiles immediately left of its name: same 31-tile width, all 8
; tools, no re-layout.
;
; entry from a jsl: db=$7e, a8 on return, i16 (Ot6CostFor / Ot6AbilityGrey need
; it), Y unused here (the ids sit at fixed buffer offsets).  w7e5755 = $5755;
; the literals below are its +5 (id 1) and +11 (id 2), with font/cost stamped at
; +0..+3 and +6..+9.  cmd $02 renders a 0 as two blanks, so an empty ($ff) cell
; -- Ot6CostFor returns 0 for an unpriced id -- draws the same clean gap the
; vanilla spaces did, and Ot6AbilityGrey leaves a 0-cost cell white.
.proc Ot6ToolRowDecorate
        php
        sep     #$20
        .a8
        .i16
.if ::OT6_MP_COSTS              ; :: -- force the file-scope flag from in-proc
        ; Reorder each column to [font][cost][name] so ONE font command colors a
        ; tool's price AND its name.  The just-landed price display put the cost
        ; tile BEFORE the column's font command, so greying the font (to match
        ; magic) could not reach the number; sliding the font ahead of the cost
        ; fixes it at no cost in width -- a $04 font command draws nothing, so
        ; the price still sits on the same two tiles immediately left of its
        ; name.  Column 1: font -> +0/+1 (was the $05,$02 draw-spaces), cost ->
        ; +2/+3 (was the $04,$21 font).  Column 2: font -> +6/+7 (was the $ff,$ff
        ; column gap), cost -> +8/+9 (was the second $04,$21 font).  The name
        ; commands (+4,+10) and their ids (+5,+11, DrawToolsListText's) stay put.
        lda     $575a           ; +5 = column-1 tool id (DrawToolsListText wrote it)
        jsl     Ot6CostFor      ;   id -> MP cost (0 if $ff/unpriced)
        pha                     ; park column-1 cost
        jsl     Ot6AbilityGrey  ;   cost -> $04 grey / $00 white; preserves X,Y
        ora     #$21            ; +1: font palette -- $21 white or $25 grey
        sta     $5756
        lda     #$04
        sta     $5755           ; +0: font command (colors column-1 cost + name)
        lda     #$02
        sta     $5757           ; +2: number command (column-1 cost)
        pla
        sta     $5758           ; +3: column-1 cost value
        lda     $5760           ; +11 = column-2 tool id
        jsl     Ot6CostFor
        pha                     ; park column-2 cost
        jsl     Ot6AbilityGrey
        ora     #$21            ; +7: font palette -- $21 white or $25 grey
        sta     $575c
        lda     #$04
        sta     $575b           ; +6: font command (colors column-2 cost + name)
        lda     #$02
        sta     $575d           ; +8: number command (column-2 cost)
        pla
        sta     $575e           ; +9: column-2 cost value
.endif
        plp
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ draw one Dance menu row -- a leading 2-digit price per name, greyed if
;   the caster can't afford it (#34: the #35 display pattern's second consumer) ]
;
; DrawDanceListText (btlgfx, bank C1) jsl's here after copying the template
; and storing the two row ids -- the exact shape of Ot6ToolRowDecorate, on the
; dance window.  Dance's price is FLAT (Ot6DanceCost, the same authority the
; charge reads), so both columns stamp the same number; an empty ($ff) cell
; draws a 0, which cmd $02 renders as two blanks.  Each column re-lays to
; [font][cost][name] so one font command colors price and name as a unit --
; the tools transform verbatim: column 1's "$05,$04 draw-4-spaces" (+0/+1)
; and its "$04,$21 font" (+2/+3) become [font][cost], column 2's "$05,$02
; gap" (+6/+7) and font (+8/+9) likewise; the name commands (+4,+10) and ids
; (+5,+11) stay put.  Row width 2+12+2+12 = 28 tiles, narrower than vanilla's
; 30.  In the nomp build the body is empty and the vanilla layout is
; byte-identical -- ALWAYS assembled, the flag gating lives here.
;
; entry from a jsl: db=$7e, a8 on return, i16 (Ot6AbilityGrey needs it).
; w7e5755 = $5755 near; literals below are its offsets.  clobbers A only.
.proc Ot6DanceRowDecorate
        php
        sep     #$20
        .a8
        .i16
.if ::OT6_MP_COSTS              ; :: -- force the file-scope flag from in-proc
        lda     $575a           ; +5 = column-1 dance id (caller wrote it)
        jsl     Ot6DanceRowCost ;   id -> cost (0 for an $ff empty cell)
        pha                     ; park column-1 cost
        jsl     Ot6AbilityGrey  ;   cost -> $04 grey / $00 white
        ora     #$21
        sta     $5756           ; +1: font palette (colors cost + name)
        lda     #$04
        sta     $5755           ; +0: font command
        lda     #$02
        sta     $5757           ; +2: number command
        pla
        sta     $5758           ; +3: column-1 cost value
        lda     $5760           ; +11 = column-2 dance id
        jsl     Ot6DanceRowCost
        pha                     ; park column-2 cost
        jsl     Ot6AbilityGrey
        ora     #$21
        sta     $575c           ; +7: font palette
        lda     #$04
        sta     $575b           ; +6: font command
        lda     #$02
        sta     $575d           ; +8: number command
        pla
        sta     $575e           ; +9: column-2 cost value
.endif
        plp
        rtl
.endproc

.if OT6_MP_COSTS
; [ a dance row's price: the flat Ot6DanceCost, 0 for an empty cell ]
; in: A = the row's dance id ($ff = empty).  out: A = cost.  preserves X,Y.
.proc Ot6DanceRowCost
        .a8
        cmp     #$ff
        bne     :+
        lda     #$00            ; empty cell: no price, stays white
        rtl
:       jml     Ot6DanceCost    ; the one authority (its rtl returns for us)
.endproc
.endif  ; OT6_MP_COSTS

; ------------------------------------------------------------------------------

.if OT6_MP_COSTS
; [ add the Bushido "not enough BP" grey reason to a row's font ]
;
; In bushido mode (w7e6168 = 2) the submenu row IS the boost level (Y/6 + 1
; since #38's 1-BP floor, weakest at top). A row whose boost exceeds the
; caster's current bp (OT6_BP_CLASS,entity) is unreachable --
; Ot6BushidoConfirm refuses to commit it -- so grey it like an unaffordable
; spell, a SECOND grey reason on top of Ot6AbilityGrey's MP one.  At 0 bp that
; now greys ALL THREE rows: the list still SHOWS what the bank would buy (the
; teaching surface), it just refuses every row -- the same presentation an
; unaffordable spell gets, never a list that changes length with the wallet.
; Blitz mode (w7e6168 != 2) passes the MP grey through untouched.  Only ever
; reached from Ot6BlitzRowDecorate's OT6_MP_COSTS block, so it lives behind the
; same flag.  a8/i16.  in: A = the MP grey ($00/$04), Y = drawn-row*6.
; out: A = A | ($04 if bushido and boost > bp).  preserves X and Y.
.proc Ot6BushidoRowGrey
        .a8
        .i16
        pha                     ; [S+1] park the MP grey
        lda     $6168
        cmp     #$02
        bne     @pass           ; not bushido: return the MP grey unchanged
        phx                     ; [S+2] save caller X (Ot6BlitzRowDecorate's)
        lda     $62ca           ; entity offset for the bp bank
        and     #$03
        asl
        longa
        and     #$00ff
        tax
        shorta0
        lda     OT6_BP_CLASS,x         ; current bp
        pha                     ; [S+1] park bp ($01,s)
        tya                     ; A = drawn-row*6
        ldx     #$0000          ; row i accumulator
@div:   cmp     #$06            ; i = (row*6) / 6
        bcc     @haver
        sbc     #$06
        inx
        bra     @div
@haver: txa                     ; A = i
        inc     a               ; #38: boost r = i + 1 -- with the 1-BP floor a
                                ;   0-bp Cyan greys EVERY row (see the header)
        cmp     $01,s           ; r vs bp; C set iff r >= bp
        beq     @afford         ; r == bp: exactly affordable
        bcc     @afford         ; r <  bp: affordable
        pla                     ; r > bp: unreachable -- grey it
        plx                     ; restore caller X
        pla                     ; MP grey
        ora     #$04            ; add magic's disabled bit ($21|$04 = $25)
        rtl
@afford:
        pla                     ; drop bp
        plx                     ; restore caller X
@pass:  pla                     ; MP grey (unchanged)
        rtl
.endproc
.endif  ; OT6_MP_COSTS

; ------------------------------------------------------------------------------

; [ open Cyan's SwdTech as a submenu (v0.5 bushido submenu -- issue #8) ]
;
; vanilla SwdTech ran a free numeral gauge (UpdateMenuState_35/37, now dead):
; a bar climbed one unit every 4 frames, the tech was bar>>5, and A latched
; whatever level it happened to show. This module deletes the gauge and drives
; SwdTech through the Tools window shell instead -- the twin of Ot6BlitzListOpen.
; OpenCmdMenuTbl[7] now hits a C1 stub that jsl's here then jmp's OpenToolsWindow.
;
; The rows ARE the boost window: row r (weakest at TOP) = boost r = the tech
; Ot6BushidoTier returns for that boost. Ot6BushidoWindow enumerates the <=4
; techs into wItemList's LEFT column (cells r*2, so row r reads at wItemList
; offset r*6 -- what _c18470 computes for column 0); the right column and any
; unused rows are $ff (empty), so the window renders a clean single column of 4.
; Confirm (Ot6BushidoConfirm) maps the picked cell back to r, banks OT6_BOOST_REVEALED=r, and
; latches Ot6BushidoTier's tech -- so single-select and enumeration share the
; exact same base+boost math and can never diverge.
;
; entry: jsl from the C1 stub, db=$7e, a8/i16. clobbers a/x/y (the caller's next
; act is jmp OpenToolsWindow, which reloads what it needs).
.proc Ot6BushidoListOpen
        .a8
        .i16
        jsl     Ot6BushidoWindow    ; pack the <=4 window techs (left col) + $ff pad
.if ::OT6_MP_COSTS                  ; :: -- force the file-scope flag from in-proc
        ; stamp each cell's MP cost into wItemList::Qty (a $ff empty cell gets 0,
        ; which cmd $02 renders as two blanks and Ot6AbilityGrey leaves white).
        ldx     #$0000
@cost:  lda     $4005,x             ; wItemList::Index
        cmp     #$ff
        bne     @price
        stz     $4006,x             ; empty cell: cost 0
        bra     @nextc
@price: jsl     Ot6CostFor          ; id -> MP cost (preserves X and Y)
        sta     $4006,x             ; wItemList::Qty
@nextc: inx
        inx
        inx
        cpx     #$0018              ; 8 cells * 3 bytes
        bcc     @cost
.endif
        ; --- honor Config>Cursor exactly like Blitz/Tools: leave the shared
        ; cursor triple alone (the command-window open already applied Memory/
        ; Reset), just force a fresh window re-init. A remembered row indexes the
        ; packed list directly; in-battle the learned set (hence the rows) is
        ; fixed, so no id-to-row remap is needed.
        stz     $7ba5               ; force MakeToolsList_04 to re-init the window
        lda     #$04
        sta     $7b9e               ; jump the tools state machine to its draw phase
        lda     #$02
        sta     $6168               ; w7e6168 = 2 : bushido mode (1 = blitz)
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ enumerate the moving-window techs into wItemList (issue #8) ]
;
; writes attack id ($55 + tech[i]) for ROW i = 0..min(2,ceiling) into
; wItemList::Index at cell i*2 (the LEFT column of row i), and $ff-fills every
; other cell through the 8-cell (4x2) window. #38: row i IS boost i+1 -- the
; 0x rung is retired, so the window is three rows deep and row 3 always stays
; $ff (blank, and the C1 confirm refuses it). tech[i] shares Ot6BushidoTech's
; base+boost math and Ot6BushidoOblivion's top-rung swap with single-select, so
; the menu can never offer a tech the confirm latch would not fire. When Cyan
; knows fewer than three techs (ceiling < 2) only the known rows are emitted -- a
; boost past the ceiling would just cap to a duplicate tech, so its row is left
; $ff (unselectable) rather than shown.
;
; a8/i16.  out: X = number of rows written (1..3).  clobbers A,X,Y.
.proc Ot6BushidoWindow
        .a8
        .i16
        ; --- $ff-fill all eight window cells first (empty = blank + unselectable) ---
        ldx     #$0000
        lda     #$ff
@pad:   sta     $4005,x             ; wItemList::Index
        inx
        inx
        inx
        cpx     #$0018
        bcc     @pad
        ; --- rowcount-1 = min(2, ceiling): boost past the ceiling is a dup ---
        jsl     Ot6BushidoCeil      ; A = ceiling (0..7)
        cmp     #$03
        bcc     :+
        lda     #$02                ; #38: cap the window at THREE rows (1x/2x/3x)
:       pha                         ; maxrow -> $02,s (after the offset push)
        lda     #$00
        pha                         ; left-cell write offset -> $01,s
        ldy     #$0000              ; row i
@row:   tya                         ; A = row i
        inc     a                   ; #38: row i -> boost i+1 (no 0x rung)
        jsl     Ot6BushidoTech      ; A = tech (preserves Y; clobbers X)
        jsl     Ot6BushidoOblivion  ; A = tech, top-rung swap (preserves Y)
        clc
        adc     #$55                ; A = attack id $55 + tech
        pha                         ; park id ($01,s; offset now $02,s, max $03,s)
        lda     $02,s               ; A = write offset (r*6)
        longa
        and     #$00ff
        tax                         ; X = write offset
        shorta0
        pla                         ; A = id (offset back at $01,s)
        sta     $4005,x             ; wItemList::Index at row r's left cell
        lda     $01,s               ; advance offset += 6 (one row)
        clc
        adc     #$06
        sta     $01,s
        iny                         ; next row
        tya
        cmp     $02,s               ; i vs maxrow
        bcc     @row                ; i < maxrow: another row
        beq     @row                ; i == maxrow: the last row
        pla                         ; drop the write offset
        pla                         ; A = maxrow
        inc     a                   ; rowcount = maxrow + 1 (1..3)
        longa
        and     #$00ff
        tax                         ; X = rowcount
        shorta0
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ commit a Bushido submenu row: row i = boost i+1, fire that rung's tech ]
;
; jsl from the C1 tools-confirm (@8809, bushido mode w7e6168=2). The C1 side has
; already rejected an $ff (empty) cell, so X points at a real left-column tech
; cell: X = row*6, and row = boost r. Refuse (buzz, stay open) a row the caster
; lacks the BP for -- r > current bp (OT6_BP_CLASS,entity) -- the confirm twin of the
; menu's bp-grey. Otherwise bank the boost (OT6_BOOST_REVEALED,entity = r; Ot6ActionEnd then
; charges r and skips that turn's regen, exactly as an L/R spend would have),
; latch the tech Ot6BushidoTier returns for boost r into the action queue, and
; close the menu. FixPlayerAttack's +$55 and Cmd_07's dispatch stay untouched.
;
; entry: db=$7e, a8/i16, X = selected cell byte offset (_c18470's). rtl.
.proc Ot6BushidoConfirm
        .a8
        .i16
        ; --- row i = cell offset / 6  (X in {0,6,12} -> i in {0,1,2}) ---
        txa                         ; A = cell offset (low byte, <= 12)
        ldx     #$0000              ; i accumulator
@div:   cmp     #$06
        bcc     @haver
        sbc     #$06                ; C set by the cmp, so sbc is exact
        inx
        bra     @div
@haver: txa                         ; A = i (i <= 2)
        inc     a                   ; #38: boost r = i + 1 (the 1-BP floor)
        pha                         ; park r ($01,s)
        ; --- entity offset for OT6_BP_CLASS/OT6_BOOST_REVEALED ---
        lda     $62ca
        and     #$03
        asl                         ; slot * 2 = entity offset
        longa
        and     #$00ff
        tax
        shorta0
        ; --- refuse a row the caster cannot pay the BP for ---
        lda     OT6_BP_CLASS,x             ; current bp
        cmp     $01,s               ; bp vs r; C set iff bp >= r (affordable)
        bcs     @ok
        pla                         ; drop r
        inc     $95                 ; error buzz -- stay in the menu (like magic)
        rtl
@ok:    ; --- bank the boost: OT6_BOOST_REVEALED,entity = r (the spend the row selected) ---
        lda     $01,s
        sta     OT6_BOOST_REVEALED,x             ; pending boost = r (Ot6BushidoTier reads it)
        pla                         ; drop r now (already banked) -- stack balanced
        jsl     Ot6BushidoTier      ; A = base+r tech (reads the OT6_BOOST_REVEALED we just set)
        pha                         ; park tech
        lda     $7b80               ; queue slot y = (w7e7b80 & 3) * 8
        and     #$03
        asl3
        tay
        pla                         ; A = tech
        sta     $2bb0,y             ; attack index (FixPlayerAttack adds +$55)
        lda     $62ca
        sta     $2bae,y             ; character slot
        inc     $7b80               ; commit the queued action
        inc     $7bcb               ; close the menu (state $30 -> $2f)
        rtl
.endproc

; ==============================================================================
; BUSHIDO LOADOUT CONFIGURATOR -- OT6-owned bank-F0 logic (issue #8 Layer B)
;
; The field-menu configurator's STATE logic lives here in F0; the C3 menu-state
; handler (field_menu.asm) is a thin shim that jsl's these for every decision
; and only performs the tilemap/DMA/cursor framework calls that MUST run in the
; menu bank.  All entries are a8/i16, D = 0 (the menu's direct page, so $08/$09
; new-press joypad and $4d/$4e cursor position are reachable), rtl.  These read
; the learned set from $1cf7 (NOT $2020 -- battle-only) and price with the
; shared Ot6CostFor leaf, exactly as the spec requires.
; ------------------------------------------------------------------------------

; [ menu-side ceiling: popcount($1cf7) - 1, floored at 0 (0..7) ]
; The field cannot read $2020 (object-map data there), so derive the ceiling
; from the learned bitmap the same way InitSkills does at battle start.
; out: A = ceiling.  clobbers X.  preserves Y.
.proc Ot6LoadoutCeil
        .a8
        .i16
        ldx     #$0000              ; running popcount in X low
        lda     f:$7e1cf7
@lp:    beq     @done               ; no more set bits
        pha
        and     #$01
        beq     @skip
        inx
@skip:  pla
        lsr
        bra     @lp
@done:  txa                         ; A = popcount (0..8)
        beq     @zero               ; nothing learned -> ceiling 0 (only tech 0)
        dec     a                   ; ceiling = count - 1
        rtl
@zero:  lda     #$00
        rtl
.endproc

; [ auto-window tech for a slot: base = max(0,ceil-2), tech = min(base+slot-1,ceil) ]
; The very math Ot6BushidoTech runs in AUTO mode, replicated menu-side off
; $1cf7 so the seed baseline matches what battle would pick.  #38: the slot
; index IS the boost (1..3) and slot 0 is retired, so a 0 clamps to 1 exactly
; as the battle leaf does -- Ot6LoadoutSeedWord still walks 0..3 and relies on
; that clamp to mirror slot 1 into the dead slot 0 (see there).
; in: A = slot (0..3).  out: A = tech (0..ceiling).  clobbers X.  preserves Y.
.proc Ot6LoadoutAutoTech
        .a8
        .i16
        cmp     #$01                ; #38: 1-BP floor -- clamp the retired slot 0
        bcs     :+
        lda     #$01
:       pha                         ; park slot ($01,s)
        jsl     Ot6LoadoutCeil      ; A = ceiling
        pha                         ; park ceiling ($01,s ; slot now $02,s)
        sec
        sbc     #$02                ; ceiling - 2  (#38: three rungs, not four)
        bcs     :+
        lda     #$00                ; base floors at 0
:       clc
        adc     $02,s               ; base + slot
        dec     a                   ;   ... - 1 (slot >= 1 after the clamp)
        cmp     $01,s               ; vs ceiling
        bcc     :+
        lda     $01,s               ; cap at ceiling
:       sta     $02,s               ; stash tech over the parked slot
        pla                         ; drop ceiling
        pla                         ; A = tech
        rtl
.endproc

; [ is a tech learned? test bit t of $1cf7 ]
; in: A = tech (0..7).  out: carry = learned.  A preserved.  clobbers X,Y-safe.
.proc Ot6TechLearned
        .a8
        .i16
        phy
        pha                         ; save A (the tech)
        longa
        and     #$00ff
        tay                         ; Y = t (clean shift count)
        shorta0
        lda     f:$7e1cf7
        iny                         ; shift t+1 times -> carry = bit t
:       lsr
        dey
        bne     :-
        pla                         ; restore A (PLA preserves carry)
        ply                         ; restore Y (PLY preserves carry)
        rtl
.endproc

; [ unpack a slot's 3-bit tech field from the packed loadout word ]
; slot s occupies bits s*3 .. s*3+2 of the $7e1e1d word.  Both the battle read
; hook (Ot6BushidoTech) and the menu draw route through here, so they can never
; decode the word differently.  Uses only registers + its own stack cell, no
; direct-page scratch, so it is safe to call mid-draw (the C3 loop parks its
; slot index in $e2).
; in: A = slot (0..3).  out: A = stored tech (0..7).  clobbers X.  preserves Y.
.proc Ot6LoadoutUnpack
        .a8
        .i16
        pha                         ; park slot ($01,s)
        asl                         ; slot*2
        clc
        adc     $01,s               ; slot*3 -> shift count (0,3,6,9)
        longa
        and     #$00ff
        tax                         ; X = shift count
        lda     f:OT6_LOADOUT       ; packed word
@sh:    cpx     #$0000
        beq     @msk
        lsr
        dex
        bra     @sh
@msk:   and     #$0007              ; A = this slot's 3-bit field
        shorta                      ; plain SEP #$20 -- keeps A (shorta0's tdc wipes it)
        sta     $01,s               ; overwrite the parked slot with the tech
        pla                         ; A = tech (0..7)
        rtl
.endproc

; [ the tech shown/used for a slot, validated -- the single source of truth ]
; Mirrors the battle read hook: MANUAL returns the stored, learned tech, else
; falls back to the auto window for that slot.  Used by the C3 draw so the
; screen never names a tech the battle would not fire.
; in: A = slot (0..3).  out: A = tech (0..7).  clobbers X.  preserves Y.
.proc Ot6LoadoutSlotTech
        .a8
        .i16
        pha                         ; park slot ($01,s)
        longa
        lda     f:OT6_LOADOUT       ; packed word (0 = AUTO)
        shorta                      ; plain SEP #$20 -- keeps Z (shorta0's tdc wipes it)
        beq     @auto
        lda     $01,s               ; slot
        jsl     Ot6LoadoutUnpack    ; A = stored tech (clobbers X, preserves Y)
        jsl     Ot6TechLearned      ; carry = learned (A preserved)
        bcc     @auto
        sta     $01,s               ; learned: return stored tech
        pla
        rtl
@auto:  pla                         ; A = slot
        jsl     Ot6LoadoutAutoTech  ; A = auto tech for this slot
        rtl
.endproc

; [ pack a new tech into one slot's 3-bit field of the loadout word ]
; Read-modify-write: clears slot s's field (bits s*3..s*3+2) and ORs in the new
; tech, leaving the other three slots untouched.  A nonzero result is, by
; definition, MANUAL.  Uses menu scratch $e0..$e4 (D=0), free during input.
; in: A = new tech (0..7), X = slot (0..3).  clobbers A,X,Y.
.proc Ot6LoadoutAssign
        .a8
        .i16
        and     #$07
        sta     $e0                 ; new tech
        txa                         ; slot
        asl                         ; slot*2
        sta     $e1                 ; temp
        txa                         ; slot
        clc
        adc     $e1                 ; slot*3 -> shift count
        longa
        and     #$00ff
        tay                         ; Y = shift count
        lda     #$0007
        sta     $e1                 ; mask, pre-shift ($e1/$e2 word)
        lda     $e0
        and     #$0007              ; field = new tech, pre-shift
@sh:    cpy     #$0000
        beq     @done
        asl     a                   ; field <<= 1
        asl     $e1                 ; mask  <<= 1  (16-bit dp shift, m=0)
        dey
        bra     @sh
@done:  sta     $e3                 ; field, shifted ($e3/$e4 word)
        lda     $e1                 ; mask, shifted
        eor     #$ffff              ; ~mask
        and     f:OT6_LOADOUT       ; clear this slot's field
        ora     $e3                 ; OR in the new field
        sta     f:OT6_LOADOUT       ; write the word back
        shorta0
        rtl
.endproc

; [ pack the whole auto window into the word (the first edit out of AUTO) ]
; So that after the first manual edit the un-touched slots keep the auto
; techs they were displaying, not zero.  Result is nonzero = MANUAL (unless the
; auto window is all tech 0 -- a ceiling-0 degenerate that reads auto either way).
; #38: the loop still walks slots 0..3 even though slot 0 is retired.  That is
; deliberate -- the STORED FORMAT MUST NOT MOVE (persistent_layout
; ot6-codex-o8-v1), and Ot6LoadoutAutoTech's clamp makes slot 0 a harmless
; mirror of slot 1, which keeps the word nonzero (= MANUAL) in exactly the
; cases it did before.  Nothing ever reads slot 0 back.
; clobbers A,X,Y.
.proc Ot6LoadoutSeedWord
        .a8
        .i16
        ldx     #$0000
@lp:    phx
        txa                         ; slot
        jsl     Ot6LoadoutAutoTech  ; A = auto tech (clobbers X, preserves Y)
        plx                         ; X = slot
        phx
        jsl     Ot6LoadoutAssign    ; pack A into slot X (clobbers A,X,Y)
        plx                         ; X = slot
        inx
        cpx     #$0004
        bcc     @lp
        rtl
.endproc

; [ open the configurator: reset the cursor to the top slot ]
; Leaves the loadout word as-is: AUTO (word 0) stays AUTO until the first edit,
; MANUAL stays MANUAL.  The display needs no seeding -- Ot6LoadoutSlotTech
; computes the auto tech per slot on the fly whenever the word is 0, so the
; player still edits a sensible auto baseline without anything being written.
; clobbers A.
.proc Ot6LoadoutOpen
        .a8
        .i16
        stz     $4d                 ; cursor: single column
        stz     $4e                 ; ... top slot
        stz     $4f
        stz     $50
        stz     $51
        stz     $52
        rtl
.endproc

; [ cycle the cursored slot's tech to the prev/next LEARNED tech; go MANUAL ]
; The first edit out of AUTO packs the current auto window into the word first
; (Ot6LoadoutSeedWord), so the three un-touched slots keep their auto techs;
; then the cursored slot is cycled and repacked, leaving a nonzero MANUAL word.
; in: A = step delta ($01 = next, $07 = prev, i.e. +/-1 mod 8).  clobbers A,X,Y.
.proc Ot6LoadoutCycleCore
        .a8
        .i16
        pha                         ; park delta ($01,s)
        longa
        lda     f:OT6_LOADOUT       ; still AUTO?
        shorta                      ; plain SEP #$20 -- keeps Z (shorta0's tdc wipes it)
        bne     :+
        jsl     Ot6LoadoutSeedWord  ; first edit: freeze the auto window into the word
:       lda     $4e                 ; cursored ROW (0..2)
        inc     a                   ; #38: row i -> word slot i+1 (slot 0 retired)
        jsl     Ot6LoadoutUnpack    ; A = the slot's current stored tech
        ldy     #$0008              ; try every residue once
@hop:   clc
        adc     $01,s               ; delta
        and     #$07                ; wrap 0..7
        jsl     Ot6TechLearned      ; carry = learned (A preserved)
        bcs     @found
        dey
        bne     @hop
@found: ldx     $4e                 ; X = cursored row ($4f = 0, set by Open)
        inx                         ; -> the same row->slot mapping
        jsl     Ot6LoadoutAssign    ; pack the new tech (A) into slot X
        pla                         ; drop delta
        rtl
.endproc

Ot6LoadoutNext:                     ; R shoulder -> next learned tech
        lda     #$01
        jmp     Ot6LoadoutCycleCore
Ot6LoadoutPrev:                     ; L shoulder -> previous learned tech
        lda     #$07
        jmp     Ot6LoadoutCycleCore

; [ per-frame input: mutate loadout state; tell C3 what to do next ]
; Reads the new-press joypad ($08 low = A/X/L/R, $09 high = B/Y/Sel/Start/dpad).
;   B      -> exit               (return A = 2)
;   Up/Dn  -> move slot cursor   (return A = 1: redraw)
;   L/R    -> cycle slot's tech  (return A = 1)
;   Select -> revert to AUTO     (return A = 1)
;   else                          (return A = 0: idle)
.proc Ot6LoadoutInput
        .a8
        .i16
        lda     $09                 ; dpad / B / Y / Select / Start
        bit     #$80                ; B -> exit
        beq     :+
        lda     #$02
        rtl
:       bit     #$08                ; Up
        beq     @dn
        lda     $4e
        bne     :+
        lda     #$03                ; wrap 0 -> 2 (pre-decrement) -- #38: 3 rows
:       dec     a
        sta     $4e
        lda     #$01
        rtl
@dn:    lda     $09
        bit     #$04                ; Down
        beq     @sel
        lda     $4e
        inc     a
        cmp     #$03                ; #38: three rows (1x/2x/3x), no 0x
        bcc     :+
        lda     #$00                ; wrap 2 -> 0
:       sta     $4e
        lda     #$01
        rtl
@sel:   lda     $09
        bit     #$40                ; Y -> revert to AUTO.  (NOT Select: FF6's
                                    ;   default config aliases physical Select
                                    ;   onto the R bit, so it can't be told apart
                                    ;   from the R-shoulder cycle -- Y is clean.)
        beq     @lr
        longa
        lda     #$0000
        sta     f:OT6_LOADOUT       ; word = 0 = AUTO (the display recomputes it)
        shorta0
        lda     #$01
        rtl
@lr:    lda     $08                 ; A / X / L / R shoulders
        bit     #$20                ; L shoulder -> previous learned tech
        beq     @rsh
        jsl     Ot6LoadoutPrev
        lda     #$01
        rtl
@rsh:   lda     $08
        bit     #$10                ; R shoulder -> next learned tech
        beq     @idle
        jsl     Ot6LoadoutNext
        lda     #$01
        rtl
@idle:  lda     #$00
        rtl
.endproc

; [ price a loadout row -- ALWAYS defined, flag-gated body ]
; The configurator lives in the SHARED menu object (built once, flag-agnostic),
; but Ot6CostFor is OT6_MP_COSTS-only.  So the menu prices every row through
; this always-present shim -- exactly the Ot6BlitzRowDecorate/Ot6ToolRowDecorate
; pattern.  ON: tail-call Ot6CostFor (its rtl returns to the menu).  nomp: return
; 0 (no cost table referenced, so the shared menu object links against either
; battle object, and the row simply draws no number).
; in: A = attack id.  out: A = MP cost (0 under nomp).  rtl.
.proc Ot6LoadoutCost
        .a8
        .i16
.if ::OT6_MP_COSTS                  ; :: -- the file-scope flag, from in-proc
        jmp     Ot6CostFor          ; tail-call: same bank, its rtl returns for us
.else
        lda     #$00
        rtl
.endif
.endproc

; ------------------------------------------------------------------------------

; [ boost the base damage of a boosted character action ]

; called at the tail of the physical and magic base-damage calcs.
; damage x2/x3/x4 for pending boost 1/2/3; the per-target 9999 cap
; still applies downstream. a8/i16, x = attacker, 16-bit damage $11b0.
; fight and capture spend their boost on extra swings (Ot6FightBoost),
; tier-family spells spend it on tiers (Ot6QueueFold), and bushido
; spends it on the tech ladder (Ot6BushidoTier) — the multiplier serves
; everything else. $3a7d = the action's attack id.

.proc Ot6BoostDmg
        php                     ; caller width varies: pin our own
        longi
        shorta0
        .a8
        .i16
        txa                     ; width-neutral character test
        cmp     #$08
        bcs     done            ; monsters never boost
        lda     $b1             ; counterattacks never boost (the $b1.0
        lsr                     ;   flag ExecRetal raises): interceptor's
        bcs     done            ;   dog rides command $02 attack $fc/$fd
                                ;   (battle_main.asm:12606) -- no exemption
                                ;   below would catch it, and the counter
                                ;   path never reaches Ot6ActionEnd to
                                ;   charge what it delivered
        lda     $b5             ; current command
        beq     done            ; $00 fight: boost = extra swings
        cmp     #$06
        beq     done            ; $06 capture: same fight path
        cmp     #$07
        beq     done            ; $07 bushido: boost bought the tech tier,
                                ;   so it must not also buy a multiplier —
                                ;   the same no-double-dip the tier-family
                                ;   scan below enforces for folded spells
        cmp     #$10
        beq     done            ; $10 rage: a CHANCE verb (#40) -- boost bought
                                ;   the coin's certainty (Ot6RageCoin's tier
                                ;   ladder), never a damage multiplier.  This
                                ;   gate is LOAD-BEARING on the start turn:
                                ;   Cmd_10 executes the first possessed action
                                ;   in the same turn (its _c21554 tail) while
                                ;   the pending boost is still live, so without
                                ;   it a 3-BP Rage-start would buy the
                                ;   guaranteed special AND x8 it -- exactly the
                                ;   double-dip kits.md:405-410 rules out.
        cmp     #$0f
        beq     done            ; $0f slot: a CHANCE verb -- boost bought the
                                ;   reel's certainty (the Ot6SlotRig tier
                                ;   ladder), never a damage multiplier. without
                                ;   this gate a pending boost would ALSO x2/x8
                                ;   the slot attack it just chose -- the exact
                                ;   double-dip kits.md:405-410 rules out
                                ;   ("certainty INSTEAD of multiplication"),
                                ;   and the bushido/$07 gate above rules out
                                ;   for the tier ladder.
        cmp     #$05
        beq     done            ; $05 steal: a CHANCE verb, not a damage one.
                                ;   boost buys the rare/guarantee downstream
                                ;   (Ot6StealBoostLevel / Ot6StealSlot), never
                                ;   a damage multiplier — "on chance verbs
                                ;   boost guarantees" (DESIGN.md). steal deals
                                ;   no damage today, so this is belt-and-braces
                                ;   (CalcDmg reaches here regardless of power),
                                ;   and it pre-declares the ruling for Mug's
                                ;   later damage+steal kit (kits.md).
        lda     OT6_BOOST_REVEALED,x         ; pending boost level
        beq     done
        phx
        ldx     #$0000
@scan:  lda     f:Ot6FoldTbl,x  ; tier-family spell? tiers are the boost
        cmp     $3a7d
        beq     @tier
        inx
        cpx     #$0018
        bcc     @scan
        plx
        lda     OT6_BOOST_REVEALED,x         ; pending boost level (reload)
        bra     @mul0
@tier:  plx
        bra     done
@mul0:
        sta     OT6_SCR_BIT
        longa
        lda     $11b0
@mul:   asl                     ; not a true xN, but x2/x4/x8 reads better
        bcs     @cap            ; on 16-bit overflow, saturate
        shorta                  ; 8-bit dec: a 16-bit rmw would clobber
        dec     OT6_SCR_BIT     ; the scratch byte next door
        longa                   ; (rep/sep leave z alone; a survives)
        bne     @mul
        bra     @store
@cap:   lda     #$7fff
@store: sta     $11b0
        shorta0
done:   plp
        rtl
.endproc

; ------------------------------------------------------------------------------

; battle Rand, inlined: this bank ($f0) can't `jsr Rand` (that routine lives in
; $c2 and a near jsr would land in $f0 garbage) and Rand ends `rts`, not `rtl`,
; so it can't be jsl'd either. Reproduce its three lines here -- `inc $be; ldx
; $be; lda f:RNGTbl,x` -- the same rolling index into the same table Rand walks.
; a8/i8; A = the draw (0-255); x saved/restored, y untouched.
.macro ot6_rand
        phx
        inc     $be
        ldx     $be
        lda     f:RNGTbl,x
        plx
.endmacro

; [ boost tilts the steal SUCCESS roll — the chance verb's certainty ]

; DESIGN.md's canon rule: on damage verbs boost multiplies; on chance verbs
; boost GUARANTEES. Steal is the party's slot machine, so each BP buys odds
; and the full spend buys certainty — in steal's own vocabulary.
;
; This replaces the single `lda $3b18,x` (load attacker level) at the head of
; the vanilla success math (TargetEffect_52, battle_main.asm @39a?..@39d8):
;       level  ->  adc #$32   (net +50, the shorta_sec carry trick)
;              ->  bcs guaranteed         (overflow shortcut vanilla owns)
;              ->  sbc targetLevel        (chance = level+50-targetLevel)
;              ->  bcc nothing / bmi guaranteed (>=128 shortcut it owns)
;              ->  $ee, sneak-ring doubles it, RandA(100) < $ee = success.
; Feeding a BOOSTED level into that exact chain is the whole hook — every
; downstream branch stays vanilla and untouched:
;   0 bp: the raw level, carry SET exactly as shorta_sec left it — the roll,
;         the sneak-ring double, the two shortcuts are all byte-for-byte
;         vanilla. Boost is transparent when unspent.
;   1 bp: +40 to the level. A hard steal becomes a coin flip; a coin flip a
;         near-lock. Sneak Ring still doubles the residual $ee.
;   2 bp: +90. Level parity now clears the bmi (>=128) shortcut outright;
;         only a steep deficit still rolls (and the ring still helps it).
;   3 bp: clamp to $ff so the very next `adc #$32` OVERFLOWS and vanilla's own
;         `bcs` guarantees the steal — reached BEFORE $ee exists, so the ring
;         is moot at the cap (as designed), and NO success RNG is drawn at all
;         (the certainty is roll-independent, which the test leans on).
; The monotonic ladder (0 < +40 < +90 < certain) improves success at every
; step and can only rescue a level deficit, never worsen it.
;
; The counterattack gate ($b1.0) is this file's convention (Ot6BoostDmg,
; Ot6FightBoost, Ot6QueueFold all carry it): a countered action runs through
; ExecRetal and ends at an UNHOOKED EndAction, so Ot6ActionEnd never charges
; what it delivered. A steal can't itself counter, but reading the gate keeps
; the "boost is always paid for" invariant honest (the boost-economy audit).
;
; a8/i8 — the width DoTargetEffect's `shortai` pinned; x = attacker, y =
; target, BOTH preserved (the caller still needs them). Returns a = the level
; the vanilla math should see, carry SET for the `adc #$32` that follows.

.proc Ot6StealBoostLevel
        .a8
        .i8
        lda     $b1             ; countered? never boost — it can't be charged
        lsr
        bcs     @vanilla
        lda     OT6_BOOST_REVEALED,x         ; pending boost (0-3)
        beq     @vanilla        ; unspent: byte-for-byte vanilla
        cmp     #$03
        bcs     @cap            ; 3 bp -> certainty
        cmp     #$02
        bcc     @b1
        lda     #90             ; 2 bp: +90 to the level
        bra     @add
@b1:    lda     #40             ; 1 bp: +40 to the level
@add:   clc
        adc     $3b18,x         ; level + tier bonus
        bcc     :+
        lda     #$ff            ; clamped: a high level never wraps small
:       sec                     ; carry set: the adc #$32 wants it (net +50)
        rtl
@cap:   lda     #$ff            ; forces adc #$32 to overflow -> vanilla bcs
        sec
        rtl
@vanilla:
        lda     $3b18,x         ; vanilla: the raw attacker level...
        sec                     ; ...with carry as shorta_sec left it (lsr ate it)
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ boost tilts the steal ITEM pick toward the rare slot — same chance rule ]

; Replaces the vanilla slot roll at @39d8 in TargetEffect_52:
;       phy / Rand / cmp #$20 / (iny) / lda $3308,y / ply
; Vanilla: rand < $20 (1/8) takes slot 0 ($3308,y — the 12.5% RARE), else
; slot 1 ($3309,y — the 87.5% COMMON); the picked byte (which may be $ff when
; that slot is empty) is handed back for the caller's own `cmp #$ff / beq
; nothing` test. Tiers:
;   0 bp: the vanilla roll, byte-for-byte — one Rand, the $20 threshold, and
;         an empty picked slot still falls through to "nothing" downstream.
;   1-3 bp: FALLBACK-AWARE. A boosted steal has already been promised an item
;         (the top of TargetEffect_52 proved at least one slot non-empty on
;         the $ffff check), so it must never hand back $ff: if one slot is
;         empty it takes the other. When BOTH slots hold an item the rare
;         takes a rising share of the roll — $60 (3/8) at 1 bp, $c0 (3/4) at
;         2 bp — and at 3 bp the rare is taken OUTRIGHT with no roll: the
;         cap's "rare if present" guarantee, and (like the success cap) it
;         draws no RNG.
; The fallback is what keeps boost monotonic for a one-item enemy: at 0 bp
; rolling the empty slot wastes the steal; at >=1 bp it can't. Boost never
; conjures loot — an all-empty enemy dropped out at the top and never arrives
; here, and an already-looted enemy (both slots cleared to $ff after its one
; steal) drops out the same way.
;
; a8/i8, x = attacker, y = target base (both preserved); returns a = the
; chosen item id (or $ff at 0 bp for an empty picked slot). Rand preserves x
; (phx/plx) and never touches y.

.proc Ot6StealSlot
        .a8
        .i8
        lda     $b1             ; countered? vanilla roll (convention, as above)
        lsr
        bcs     @vanilla
        lda     OT6_BOOST_REVEALED,x         ; pending boost
        beq     @vanilla        ; 0 bp: the exact vanilla roll
        lda     $3308,y         ; slot 0 = rare
        cmp     #$ff
        beq     @common         ; no rare present -> the common is the item
        lda     $3309,y         ; slot 1 = common
        cmp     #$ff
        beq     @rare           ; no common present -> the rare is the item
        lda     OT6_BOOST_REVEALED,x         ; both present: rising rare share by tier
        cmp     #$03
        bcs     @rare           ; 3 bp: rare outright, no roll (guarantee)
        cmp     #$02
        bcc     @t1
        lda     #$c0            ; 2 bp: 3/4 of the roll is rare
        bra     @roll
@t1:    lda     #$60            ; 1 bp: 3/8 of the roll is rare
@roll:  pha                     ; park the threshold across the draw (no scratch)
        ot6_rand                ; a = rand; x saved/restored -> $01,s stays threshold
        cmp     $01,s           ; carry set iff rand >= threshold
        pla
        bcc     @rare           ; rand < threshold -> rare
@common:lda     $3309,y
        rtl
@rare:  lda     $3308,y
        rtl
@vanilla:
        phy
        ot6_rand                ; a = rand; y stays parked at $01,s across it
        cmp     #$20
        bcc     :+
        iny
:       lda     $3308,y
        ply
        rtl
.endproc

; ==============================================================================
; BOOST-TIERED SLOT (Setzer) -- the chance-verb canon applied to the reels
;
; ROADMAP.md:79-82 / kits.md:405-410: on chance verbs boost buys CERTAINTY in
; the verb's own vocabulary. Slot's vocabulary is the reel rig, and vanilla's
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

; ==============================================================================
; GAU -- THE HUNTER'S STABLE (issue #40, docs/design/kit-gau.md)
;
; The Ochette model: Veldt learning stays unlimited (LearnRage and the $1d2c
; bitfield are UNTOUCHED -- the collection game IS Gau), and the battle Rage
; window is filtered to an 8-slot loadout configured in the field.
;
; Storage: OT6_RAGELOAD, eight bytes at $7e1e1f, in the same save-block scrap
; the Bushido word lives in.  byte = rage id + 1; $00 = unset; all eight zero
; = AUTO.  No persistent_layout bump -- see ot6_memory.inc for the ruling.
;
; The battle read is ONE choke point: the flat list InitSkills builds at $257e.
; Everything downstream -- the window draw (btlgfx DrawRageListText), the
; confirm (btlgfx @852a, which refuses an $ff cell), the scroll cap, even
; RandRage's confused-rager fallback -- reads that list and narrows itself for
; free.  No cursor table, window template or btlgfx edit at all.
; ------------------------------------------------------------------------------

; [ is a rage learned?  test bit (id & 7) of $1d2c + (id >> 3) ]
;
; The field/battle-shared twin of the bit walk InitSkills does over the 32-byte
; $1d2c-$1d4b bitfield (battle_main.asm:14684-14691): one bit per species,
; LSB-first inside each byte, id order.
; a8/i16.  in: A = rage id (0..254).  out: carry = learned, A preserved.
;   clobbers X.  preserves Y.
.proc Ot6RageLearned
        .a8
        .i16
        phy                     ; [$01,s..$02,s] caller Y
        pha                     ; [$01,s] the id
        lsr
        lsr
        lsr                     ; A = id >> 3 = byte index
        longa
        and     #$001f          ; 32 bytes -- ids 0..254 cannot overrun it
        tax
        shorta0
        lda     $01,s           ; the id again
        and     #$07
        longa
        and     #$00ff
        tay                     ; Y = bit index (clean shift count)
        shorta0
        lda     f:$7e1d2c,x     ; the learned-rage bitfield
        iny                     ; shift bit+1 times -> carry = bit
:       lsr
        dey
        bne     :-
        pla                     ; A = the id (PLA preserves carry)
        ply                     ; caller Y  (PLY preserves carry)
        rtl
.endproc

; [ a loadout slot's rage, validated -- the single source of truth ]
;
; Mirrors the Bushido loadout's Ot6LoadoutSlotTech: the stored byte only counts
; if the species is still in the bitfield.  It cannot normally go stale
; (learning is monotonic and nothing ever clears $1d2c), but a corrupt or
; hand-edited save must not put an id in the list that SetRage would resolve
; into monster properties the player never hunted.
; a8/i16.  in: A = slot (0..7).  out: carry set + A = rage id, or carry clear
;   (unset / no longer learned).  clobbers X.  preserves Y.
.proc Ot6RageSlot
        .a8
        .i16
        longa
        and     #$00ff
        tax
        shorta0
        lda     f:OT6_RAGELOAD,x
        beq     @none           ; $00 = unset
        dec     a               ; stored byte - 1 = rage id
        jsl     Ot6RageLearned  ; carry = learned (A preserved)
        bcc     @none
        rtl                     ; carry set, A = the id
@none:  clc
        rtl
.endproc

; [ the n-th learned rage in id order (AUTO's definition, menu side) ]
;
; AUTO is "the first eight known rages in id order" -- the head of the very
; list InitSkills builds.  Not "most recently learned" (no storage exists) and
; not "strongest" (no judgment the machinery can make).  Only the FIELD menu
; calls this: in battle an all-zero loadout hands the list build straight back
; to the vanilla walk, so AUTO costs the battle path nothing.
; a8/i16.  in: A = n (0-based).  out: carry set + A = the id, or carry clear
;   (fewer than n+1 learned).  clobbers X.  preserves Y.
.proc Ot6RageNth
        .a8
        .i16
        pha                     ; [$01,s] n (counted down)
        phy                     ; [$01,s..$02,s] caller Y (n now $03,s)
        ldy     #$0000          ; candidate id
@try:   tya
        jsl     Ot6RageLearned  ; carry = learned; preserves Y, clobbers X
        bcc     @next
        lda     $03,s
        beq     @hit
        dec     a
        sta     $03,s
@next:  iny
        cpy     #$00ff          ; ids 0..254 (InitSkills' own ceiling)
        bcc     @try
        ply
        pla
        clc                     ; fewer than n+1 learned
        rtl
@hit:   tya                     ; A = the id (a8 reads Y's low byte)
        sta     $03,s           ; overwrite the parked n with it
        ply                     ; caller Y
        pla                     ; A = the id
        sec
        rtl
.endproc

; [ THE CHOKE POINT: build the battle rage list from the loadout ]
;
; Called from InitSkills (battle_main.asm) in place of -- not beside -- the
; vanilla $1d2c walk.  All eight bytes zero (AUTO, and the state every
; pre-existing save and every tracked anchor is in) returns carry CLEAR and the
; vanilla walk runs untouched, byte for byte.  Otherwise this writes the stored,
; still-learned ids in slot order to $257e, sets the count $3a9a, and returns
; carry SET.
;
; Terminator: InitBattle $ff-fills $2000-$341f (battle_main.asm:6096-6102, a
; 16-bit double-store loop) BEFORE it calls InitSkills, so every cell past the
; ones we write is already $ff -- which is what both readers stop on (the
; btlgfx confirm at :20264-20266, RandRage's scan at :992-994).  We write the
; terminator anyway rather than depend on a fill three hundred lines away.
;
; entry: jsl from InitSkills, db=$7e (InitBattle's MVN left it there).  Sets its
; own widths and restores the caller's.  clobbers A,X,Y.  out: carry set = the
; list is built, carry clear = run the vanilla walk.
.proc Ot6RageList
        php
        shorta0
        longi
        ; --- AUTO?  all eight bytes zero -> hand it back to vanilla ---
        ldx     #$0000
@zero:  lda     f:OT6_RAGELOAD,x
        bne     @manual
        inx
        cpx     #OT6_RAGESLOTS
        bcc     @zero
        plp
        clc                     ; AUTO: the vanilla walk builds the list
        rtl
@manual:
        stz     $3a9a           ; number of known rages, rebuilt below
        ldy     #$0000          ; write cursor into $257e (Ot6RageSlot keeps Y)
        lda     #$00
        pha                     ; [$01,s] slot -- NOT X: Ot6RageSlot clobbers it
@slot:  lda     $01,s
        jsl     Ot6RageSlot     ; carry set + A = id; preserves Y, kills X
        bcc     @next
        sta     $257e,y
        iny
        inc     $3a9a
@next:  lda     $01,s
        inc     a
        sta     $01,s
        cmp     #OT6_RAGESLOTS
        bcc     @slot
        pla                     ; drop the slot counter
        lda     #$ff
        sta     $257e,y         ; terminate (belt-and-braces; see the header)
        plp
        sec                     ; handled
        rtl
.endproc

; ------------------------------------------------------------------------------
; GAU'S FIELD CONFIGURATOR -- bank-F0 state logic (the Ot6Loadout* twin)
;
; Same division of labour the Bushido configurator proved: everything that
; DECIDES lives here in F0 and the C3 handler is a thin tilemap/cursor/DMA
; shim, so the field page and the battle list can never disagree about what
; the loadout says.  All entries a8/i16, D = 0 (so the $08/$09 new-press
; joypad and the $4d/$4e cursor position are reachable), rtl.  The learned set
; is read from $1d2c through the SAME Ot6RageLearned leaf the battle build
; uses -- the invariant that kept Bushido's two readers honest.
;
; The one shape difference from Bushido: Cyan's "pool" is eight techs and can
; be drawn as a grid, Gau's is up to 255 species and cannot.  So the L/R cycle
; IS the browse -- it walks the $1d2c bitfield -- and a LEARNED count stands in
; for the grid (the collection score, which is the number the hunter cares
; about anyway).
; ------------------------------------------------------------------------------

; [ is the loadout AUTO?  all eight bytes zero ]
; out: carry set = AUTO.  clobbers A,X.  preserves Y.
.proc Ot6RageIsAuto
        .a8
        .i16
        ldx     #$0000
@lp:    lda     f:OT6_RAGELOAD,x
        bne     @manual
        inx
        cpx     #OT6_RAGESLOTS
        bcc     @lp
        sec
        rtl
@manual:
        clc
        rtl
.endproc

; [ the rage a slot SHOWS, validated -- the page's single source of truth ]
; MANUAL returns the stored, still-learned id; AUTO computes the slot's window
; entry on the fly, so merely opening the page writes nothing (the Bushido
; configurator's implicit-seed property, kept).
; in: A = slot (0..7).  out: carry set + A = rage id, carry clear = blank row.
;   clobbers X.  preserves Y.
.proc Ot6RageShow
        .a8
        .i16
        pha
        jsl     Ot6RageIsAuto       ; carry set = AUTO (clobbers A and X)
        pla                         ; A = slot (PLA preserves carry)
        bcs     @auto
        jmp     Ot6RageSlot         ; tail-call: the stored, validated id
@auto:  jmp     Ot6RageNth          ; tail-call: the auto window's slot-th id
.endproc

; [ freeze the AUTO window into the eight bytes (the first edit out of AUTO) ]
; So the un-touched slots keep the beasts they were displaying rather than
; emptying.  A slot the auto window cannot fill (fewer than eight learned)
; stays $00 = unset, which the battle build simply skips.
; clobbers A,X,Y.
.proc Ot6RageSeed
        .a8
        .i16
        ldy     #$0000
@lp:    tya
        jsl     Ot6RageNth          ; carry set + A = id; preserves Y, kills X
        bcc     @done               ; fewer than Y+1 learned: the rest stay unset
        inc     a                   ; stored byte = id + 1
        phy
        plx                         ; X = slot (the i16 transfer idiom; Y intact)
        sta     f:OT6_RAGELOAD,x
        iny
        cpy     #OT6_RAGESLOTS
        bcc     @lp
@done:  rtl
.endproc

; [ open the configurator: cursor to the top slot ]
; Leaves the eight bytes as they are -- AUTO stays AUTO until the first edit,
; because Ot6RageShow computes the window per slot on the fly.
; clobbers A.
.proc Ot6RageOpen
        .a8
        .i16
        stz     $4d                 ; cursor: single column
        stz     $4e                 ; ... top slot
        stz     $4f
        stz     $50
        stz     $51
        stz     $52
        rtl
.endproc

; [ cycle the cursored slot to the prev/next LEARNED rage; go MANUAL ]
; The first edit out of AUTO freezes the window first (Ot6RageSeed), then walks
; the $1d2c bitfield from the slot's current id to the next/previous set bit,
; wrapping over 0..254 -- vanilla's own id range (InitSkills stops at $fe).
; A slot showing nothing starts its walk at id 0.  Uses menu scratch $e0 (D=0),
; free during input, exactly as Ot6LoadoutAssign uses $e0..$e4.
; in: A = step delta ($01 = next, $ff = previous).  clobbers A,X,Y.
.proc Ot6RageCycleCore
        .a8
        .i16
        pha                         ; [$01,s] delta
        jsl     Ot6RageIsAuto
        bcc     :+
        jsl     Ot6RageSeed         ; first edit: freeze the window into bytes
:       lda     $4e                 ; cursored slot (0..7)
        jsl     Ot6RageShow         ; carry set + A = the id it is showing
        bcs     :+
        lda     #$00                ; blank row: start the walk at id 0
:       sta     $e0
        ldy     #$00ff              ; try every id once (0..254)
@hop:   lda     $e0
        clc
        adc     $01,s               ; += delta
        cmp     #$ff                ; $ff is off both ends of 0..$fe
        bcc     @have
        lda     $01,s
        bmi     @low                ; delta $ff (down): 0 - 1 wraps to $fe
        lda     #$00                ; delta $01 (up):  $fe + 1 wraps to 0
        bra     @have
@low:   lda     #$fe
@have:  sta     $e0
        jsl     Ot6RageLearned      ; carry = learned (A preserved)
        bcs     @found
        dey
        bne     @hop
        pla                         ; nothing learned at all: leave it alone
        rtl
@found: lda     $e0
        inc     a                   ; stored byte = id + 1
        ldx     $4e                 ; X = cursored slot ($4f = 0, set by Open)
        sta     f:OT6_RAGELOAD,x
        pla                         ; drop delta
        rtl
.endproc

Ot6RageNext:                        ; R shoulder -> next learned rage
        lda     #$01
        jmp     Ot6RageCycleCore
Ot6RagePrev:                        ; L shoulder -> previous learned rage
        lda     #$ff
        jmp     Ot6RageCycleCore

; [ per-frame input: mutate loadout state; tell C3 what to do next ]
; The Ot6LoadoutInput contract, at eight rows:
;   B      -> exit               (return A = 2)
;   Up/Dn  -> move slot cursor   (return A = 1: redraw)
;   L/R    -> cycle the slot     (return A = 1)
;   Y      -> revert to AUTO     (return A = 1)   (NOT Select -- FF6's default
;             config aliases physical Select onto the R bit, so it cannot be
;             told apart from the R-shoulder cycle)
;   else                          (return A = 0: idle)
.proc Ot6RageInput
        .a8
        .i16
        lda     $09                 ; dpad / B / Y / Select / Start
        bit     #$80                ; B -> exit
        beq     :+
        lda     #$02
        rtl
:       bit     #$08                ; Up
        beq     @dn
        lda     $4e
        bne     :+
        lda     #OT6_RAGESLOTS      ; wrap 0 -> 7 (pre-decrement)
:       dec     a
        sta     $4e
        lda     #$01
        rtl
@dn:    lda     $09
        bit     #$04                ; Down
        beq     @sel
        lda     $4e
        inc     a
        cmp     #OT6_RAGESLOTS
        bcc     :+
        lda     #$00                ; wrap 7 -> 0
:       sta     $4e
        lda     #$01
        rtl
@sel:   lda     $09
        bit     #$40                ; Y -> revert to AUTO (all eight bytes 0)
        beq     @lr
        ldx     #$0000
        lda     #$00
:       sta     f:OT6_RAGELOAD,x
        inx
        cpx     #OT6_RAGESLOTS
        bcc     :-
        lda     #$01
        rtl
@lr:    lda     $08                 ; A / X / L / R shoulders
        bit     #$20                ; L shoulder -> previous learned rage
        beq     @rsh
        jsl     Ot6RagePrev
        lda     #$01
        rtl
@rsh:   lda     $08
        bit     #$10                ; R shoulder -> next learned rage
        beq     @idle
        jsl     Ot6RageNext
        lda     #$01
        rtl
@idle:  lda     #$00
        rtl
.endproc

; [ how many rages are known?  the collection score ]
; Popcount of the whole $1d2c-$1d4b bitfield.  Stands in for the pool grid
; Cyan's page draws: with up to 255 candidates the grid is not expressible,
; and the count is the number the collection game is actually about.
; out: A = count (0..255).  clobbers A,X,Y and menu scratch $e0/$e1.
.proc Ot6RageCount
        .a8
        .i16
        ldx     #$0000
        ldy     #$0000              ; running count
@byte:  lda     f:$7e1d2c,x
        beq     @next
        sta     $e0
        lda     #$08
        sta     $e1
@bit:   lsr     $e0
        bcc     :+
        iny
:       dec     $e1
        bne     @bit
@next:  inx
        cpx     #$0020              ; 32 bytes
        bcc     @byte
        tya                         ; a8: the count's low byte (max 255)
        rtl
.endproc

; [ price a rage row -- ALWAYS defined, flag-gated body ]
; The Ot6LoadoutCost shim, for the shared (flag-agnostic) menu object: ON
; tail-calls the one price authority, nomp returns 0 and the row draws no
; number.  Every row shows the SAME number by design -- the price is flat, so
; the column doubles as the rule's teaching surface.
; out: A = MP cost (0 under nomp).  rtl.
.proc Ot6RageRowCost
        .a8
        .i16
.if ::OT6_MP_COSTS
        jmp     Ot6RageCost         ; tail-call: its rtl returns for us
.else
        lda     #$00
        rtl
.endif
.endproc

; ------------------------------------------------------------------------------

; [ latch the trance's boost tier (Cmd_10's entry) ]
;
; BP is spent once, at the Rage-START action, through the normal Ot6ActionEnd
; consume -- but the TIER must outlive that action by the whole battle, because
; every possessed turn after it rolls the same tilted coin.  That is Slot's
; problem at longer range: Ot6SlotRig latches the spin's tier so the charge and
; the reels can never disagree; this latches the trance's tier so the charge and
; the whole possession can never disagree.
;
; It fires ONLY on the start turn -- the turn whose RAGE status bit is still
; clear.  A mid-trance Cmd_10 (every possessed turn re-enters here) finds the
; bit set and leaves the latch alone; latching there would read the already-
; consumed pending byte and silently drop the trance to tier 0.
;
; entry: jsl from Cmd_10 (battle_main.asm), a8/i8, Y = attacker entity, db=$7e.
; clobbers A.
.proc Ot6RageTierLatch
        .a8
        lda     $3ef9,y         ; status 4
        lsr                     ; bit 0 = RAGE: already possessed?
        bcs     @done           ; mid-trance turn: the latched tier stands
        lda     OT6_BOOST_REVEALED,y     ; pending boost 0-3
        cmp     #$04
        bcc     :+
        lda     #$03            ; (defensive: Ot6Boost already caps at 3)
:       sta     f:$7e0000+OT6_RAGETIER
@done:  rtl
.endproc

; [ boost tilts Rage's coin -- the chance verb's certainty, Dance-shaped ]
;
; DESIGN.md's canon: on damage verbs boost multiplies, on chance verbs boost
; GUARANTEES, in the verb's own vocabulary.  Rage's vocabulary is one coin per
; possessed turn -- RandCarry + rol picks entry 0 (always plain Fight) or entry
; 1 (the beast's special; monster_rage.asm:3-5).  The beast was already chosen
; from the menu, so the gamble BP buys off is which half of it shows up, and it
; buys it for the whole trance:
;
;   tier 0   the caller's own carry, untouched                       1/2
;   tier 1   the special unless a fresh draw < $40                    3/4
;   tier 2   the special unless a fresh draw < $10                  15/16
;   tier 3   no roll at all -- the special, every turn, all trance    1/1
;
; Each point roughly quarters the miss odds (1/2 -> 1/4 -> 1/16 -> 0), the same
; converging ladder Steal shipped.  The tilt is toward entry 1 because entry 0
; is always plain Fight -- nobody spends BP to punch more predictably.
;
; RNG DISCIPLINE: tier 0 draws NOTHING extra, so a 0-BP trance walks exactly
; the RNGTbl indices vanilla walks -- that is the byte-identical arm the
; fixture asserts, and it is why the tier test can be a same-drive A/B.
;
; entry: jsl from RandRage (bank C2) immediately after its `jsr RandCarry`,
; a8, INDEX WIDTH UNKNOWN (the site precedes RandRage's `longai`).  So the
; caller's P is parked and the index-width bit restored by hand at the end --
; `plp` would also restore the stale carry this proc exists to replace.
; in: carry = vanilla's coin, A = the value RandRage is about to `rol`.
; out: carry = the tier's coin.  A and Y preserved; X clobbered.
.proc Ot6RageCoin
        .a8
        pha                     ; [$01,s] the caller's A (the rol operand)
        lda     #$00
        rol                     ; A = vanilla's coin (0/1); carry consumed
        pha                     ; [$01,s] coin
        php
        pla                     ; A = caller P ...
        pha                     ; [$01,s] ... parked for the width restore
        rep     #$10            ; i16, so phy has a known width.  an 8-bit Y
        .i16                    ;   widens to $00yy and sep #$10 truncates it
        phy                     ;   back -- correct from either caller width
        ;   stack from here: $01,s Ylo  $02,s Yhi  $03,s P  $04,s coin  $05,s A
        lda     f:$7e0000+OT6_RAGETIER
        beq     @done           ; tier 0: vanilla's coin stands, no extra draw
        cmp     #$03
        bcc     @tilt
        lda     #$01            ; tier 3+: the special, unconditionally
        sta     $04,s           ; overwrite the parked coin
        bra     @done
@tilt:  cmp     #$02
        beq     @t2
        lda     #$40            ; tier 1: the special unless draw < $40
        bra     @roll
@t2:    lda     #$10            ; tier 2: the special unless draw < $10
@roll:  pha                     ; [$01,s] threshold -- everything else +1
        sep     #$10            ; ot6_rand indexes $be as a BYTE
        .i8
        ot6_rand                ; A = draw 0-255 (the macro saves/restores X)
        cmp     $01,s           ; carry set iff draw >= threshold
        lda     #$00
        rol                     ; A = 1 when the special wins
        sta     $05,s           ; overwrite the parked coin
        pla                     ; drop the threshold
        rep     #$10
        .i16
@done:  ply                     ; caller Y
        pla                     ; A = caller P
        and     #$10            ; restore the index width by hand: sep/rep
        beq     @i16            ;   leave C alone, plp would not
        sep     #$10
        bra     @coin
@i16:   rep     #$10
@coin:  pla                     ; A = the coin (0/1)
        lsr                     ; -> carry
        pla                     ; A = the caller's original A (PLA keeps C)
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ upload the bg hud glyphs into free font cells ]

; 16 2bpp tiles (shield-with-count 1-6/B, pip clusters 0-5, boost cells)
; written to the battle font at vram $5800 + cell*8, as two 8-tile
; slices (~128 bytes each — one fits a vblank-tail re-lay stage).
; a8/i16, db = $00, vmainc $80. exits a8. clobbers a/x/y.

.macro ot6_glyph_slice first, last
        ldx     #first          ; glyph index
@tile:  phx
        lda     f:Ot6BgGlyphCellTbl,x
        longa
        and     #$00ff
        asl
        asl
        asl
        clc
        adc     #$5800
        sta     hVMADDL
        txa                     ; data offset = index * 16
        asl
        asl
        asl
        asl
        tax
        ldy     #$0008          ; 8 words per 2bpp tile
@word:  lda     f:Ot6BgGlyphData,x
        sta     hVMDATAL
        inx
        inx
        dey
        bne     @word
        shorta
        plx
        inx
        cpx     #last
        bcc     @tile
        rts
.endmacro
