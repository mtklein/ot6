; ------------------------------------------------------------------------------

; [ v0.4: full HP/MP restore on level up ]
;
; Octopath's rule, ported whole (docs/design/mp-economy.md "Full HP/MP restore
; on level up"): a character who gains a level refills current HP and MP to the
; new maxima. The owner framed it "HP/SP/MP"; this project retired SP (the pool
; is MP, mp-economy.md preamble) and boost points are battle-scoped RAM that
; resets every fight -- the $1600 record carries only HP ($1609/$160b) and MP
; ($160d/$160f), so the implementable meaning is HP + MP. No third pool exists
; in the record to restore.
;
; Called by a jsl at the tail of vanilla DoLevelUp (battle_main.asm, right after
; it stores the raised max MP), so the max HP/MP this refills TO are already the
; post-level values -- refilling before the raise would undershoot by the level's
; gain. X = record pointer, Y = battle slot, A = 16-bit (DoLevelUp is mid-longa).
;
; WHY the battle copies ($3bf4,y / $3c08,y), not the record's own current cells
; ($1609,x / $160d,x): the victory sequence runs WinBattle FIRST, then UpdateSRAM
; (battle_main.asm:11982-11983). UpdateSRAM copies each character's END-OF-BATTLE
; battle HP/MP ($3bf4/$3c08) back over the record's current HP/MP
; (battle_main.asm:12136-12141). A refill written to the record here would be
; silently clobbered a few instructions later; the battle cell is the authority
; at this moment, and UpdateSRAM carries it into save RAM for us. (Refilling the
; record instead was the first, quietly-wrong version of this hook.)
;
; MULTI-LEVEL: CheckLevelUp loops DoLevelUp once per level gained
; (battle_main.asm:15773-15780), so this runs once per level and each pass reads
; the freshly-raised max -- the last pass leaves the battle cell at the final
; max. MULTI-CHARACTER: WinBattle's reward loop (battle_main.asm:15443-15461)
; visits each live party slot, and Y (the slot) survives down into DoLevelUp
; because ExecBtlGfx preserves it (phy/ply, battle_main.asm:16396/16410) -- the
; same invariant vanilla itself leans on when it reads $3ed8,y one instruction
; after `jsr CheckLevelUp` (battle_main.asm:15456). A character who takes no
; level never enters DoLevelUp, so their damaged battle HP/MP flow through
; UpdateSRAM un-restored (the negative control battle_levelup.lua asserts).
;
; The refill TARGET is the effective max, decoded through the boost tier the top
; two bits of $160b/$160f carry, mirroring CalcMaxHPMP (battle_main.asm:6673) and
; capped like LoadCharProp (:6616 HP<10000, :6622 MP<1000). Masking the base
; alone would undershoot a character wearing an HP/MP-boost relic; the stale
; battle max $3c1c/$3c30 was computed pre-level at LoadCharProp time, so it is
; not the new max either.

.proc Ot6LevelUpHeal
        php
        longa                   ; 16-bit A for the maxima; index already 16-bit
                                ; here (vanilla indexes $160b,x with record ptrs
                                ; past $ff), so it is left untouched
        lda     $160b,x         ; new max HP: base | boost tier (bits 15..14)
        jsr     Ot6EffMax
        cmp     #10000          ; LoadCharProp's HP ceiling (battle_main.asm:6616)
        bcc     :+
        lda     #9999
:       sta     $3bf4,y         ; battle current HP := new max
        lda     $160f,x         ; new max MP: base | boost tier
        jsr     Ot6EffMax
        cmp     #1000           ; LoadCharProp's MP ceiling (battle_main.asm:6622)
        bcc     :+
        lda     #999
:       sta     $3c08,y         ; battle current MP := new max
        shorta                  ; back to the file-wide 8-bit assembler state;
                                ; plp restores the caller's real width
        plp
        rtl
.endproc

; effective maximum from a $160b/$160f-encoded field, mirroring CalcMaxHPMP
; (battle_main.asm:6673): the top two bits pick a boost tier added to the
; low-14-bit base -- 00 +0%, 01 +25%, 10 +50%, 11 +12.5%. A(16)=base|tier in,
; A(16)=base+boost out (uncapped -- the caller clamps). Scratch $ee is dead at
; the call site: DoLevelUp is finished with it and LearnAbilities never reads it
; (battle_main.asm:15983). X and Y are preserved.

.proc Ot6EffMax
        .a16                    ; entered mid-longa; A is 16-bit throughout
        pha                     ; encoded max
        and     #$3fff          ; base
        sta     $ee
        pla
        and     #$c000          ; boost tier
        beq     @base           ; 00 -> +0%
        cmp     #$8000
        beq     @half           ; 10 -> +50% (base>>1)
        bcs     @eighth         ; 11 -> +12.5% (base>>3)
        lda     $ee             ; 01 -> +25% (base>>2)
        lsr
        lsr
        bra     @sum
@eighth:
        lda     $ee
        lsr
        lsr
        lsr
        bra     @sum
@half:
        lda     $ee
        lsr
@sum:   clc
        adc     $ee             ; base + boost delta
        rts
@base:
        lda     $ee
        rts
        .a8                     ; restore the file-wide assembler width
.endproc

; ------------------------------------------------------------------------------

; [ M5 espers-as-sub-jobs: an equipped esper grants its spells to the Magic list ]
;
; Replaces the learned-status read `lda ($f0),y` inside ValidateSpellList's
; AddToSpellList_02 (battle_main.asm), the read whose $ff result marks a spell
; known/castable (`... inc / beq add`).  Y = the spell id (0..$35), $f0 = the
; character's $1a6e learned-spell table pointer ($1a6e + char*$36, set at the
; head of ValidateSpellList).  A(8) is returned as the EFFECTIVE learned status:
; $ff when the spell is castable, the real (< $ff) learn% otherwise.
;
; ADDITIVE, fork-independent core.  Two ways a spell is castable:
;   1. innate -- $1a6e says $ff.  Read first and returned unchanged, so a
;      character's own known spells are never touched.  This is the whole reason
;      the read happens before the esper check: the augment/replace fork only
;      differs in whether innate spells are later SUPPRESSED, and suppression is
;      not built here.
;   2. granted -- the character's equipped esper ($f7, the byte ValidateSpellList
;      already banked at its head; negative = none) lists this spell id in its
;      GenjuProp row.  UpdateEnabledMagic/CheckMagicEnabled then enable and draw
;      it for free.  Equip Ramuh -> Bolt/Rasp cast; unequip ($f7 negative) -> the
;      bmi makes this proc return the untouched vanilla status, i.e. inert.
;
; The GenjuProp row is esper*11 (GetGenjuPropPtr, battle_main.asm:16155),
; computed inline because that helper lives in the battle bank and this proc does
; not: 11e = ((e*4 + e)*2 + e).  Only the five spell-id bytes (+1,+3,+5,+7,+9)
; are scanned; the learn-rate bytes are all zero under M5 (genju_prop.asm) and
; irrelevant to the grant, which keys on the id alone.
;
; CONTRACT: a8/i16, D=0, DBR = the caller's (jsl preserves it, so `($f0),y`
; reads the same $1a6e region ValidateSpellList does).  Preserves X -- the loop's
; dispatch selector, live across every iteration -- and Y, the spell id the
; caller's `ply` restores anyway.  Clobbers A (the return) and the dead scratch
; $ee (written and read with no call between, so it needs no reserved cell).
.proc Ot6EsperSpellKnown
        .a8
        .i16
        lda     ($f0),y         ; vanilla learned status for spell id Y
        inc
        beq     @grant          ; $ff -> innately known: keep it ($ff)
        lda     $f7             ; this character's equipped esper (neg = none)
        bmi     @vanilla        ; no esper worn -> the vanilla (non-$ff) status
        phx                     ; X is the loop's dispatch selector -- preserve
        longa                   ; 16-bit for the *11 product (max 26*11 = 286)
        and     #$00ff          ; A = esper index e (0..26)
        sta     $ee             ; local scratch: stored and reloaded within this
        asl                     ;   proc with no call between, so no ValidateSpell
        asl                     ;   frame cell is reserved for it
        clc
        adc     $ee             ; 4e + e = 5e
        asl                     ; 10e
        clc
        adc     $ee             ; 10e + e = 11e (GenjuProp row offset)
        tax
        shorta
        tya                     ; A = spell id (low byte; Y's high byte is 0)
        cmp     f:GenjuProp+1,x ; the esper's five taught-spell IDs
        beq     @hit
        cmp     f:GenjuProp+3,x
        beq     @hit
        cmp     f:GenjuProp+5,x
        beq     @hit
        cmp     f:GenjuProp+7,x
        beq     @hit
        cmp     f:GenjuProp+9,x
        beq     @hit
        plx                     ; not granted: restore X, fall to the vanilla read
@vanilla:
        lda     ($f0),y         ; the real (< $ff) learn%, Y intact
        rtl
@hit:   plx                     ; granted: restore X, then resolve as known
@grant: lda     #$ff
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ M5: seed the master spell-list union with equipped espers' granted spells ]
;
; Called once from InitSpellList (battle_main.asm) right after its actor loop
; unions the party's INNATELY-known spells into $3034, and before that union is
; compacted and sorted into the per-character lists.  The in-battle Magic list is
; COMPACTED to exactly the spells present in $3034, so a borrowed spell no party
; member knows has no slot for the per-character hook (Ot6EsperSpellKnown) to keep
; -- measured: equip Ramuh with nobody knowing Bolt/Rasp and $208e never lists
; them.  This adds each equipped esper's GenjuProp spell-ids to $3034 so the slots
; exist; ValidateSpellList's per-character pruning then keeps each spell only for
; the character actually wearing the granting esper (the additive core).  So the
; correct core is TWO hooks, not one: this union seed plus the per-character grant.
;
; Entered from InitSpellList's a8/i8 world.  $3010 (record pointers) is already
; set -- InitParty (battle_main.asm:7749) runs before InitChars (:6123) which
; calls InitSpellList -- so each slot's equipped esper is $161e indexed by
; $3010,slot, exactly as ValidateSpellList reads it.  a/x/y and P are restored via
; php/plp.  Scratch $ee is written and reread with no call between.
.proc Ot6UnionEspers
        php
        longi                   ; 16-bit index for $3010 word reads and row math
        shorta                  ; 8-bit A
        ldx     #$0006          ; party entity offsets 6,4,2,0
@slot:  lda     $3ed8,x         ; actor id
        cmp     #$0c
        bcs     @next           ; empty/special/gogo/umaro -- no esper to grant
        phx
        ldy     $3010,x         ; this slot's record pointer
        lda     $161e,y         ; equipped esper (neg = none)
        bmi     @done
        longa                   ; row = esper*11 (GetGenjuPropPtr, :16155)
        and     #$00ff
        sta     $ee
        asl
        asl
        clc
        adc     $ee             ; 5e
        asl
        clc
        adc     $ee             ; 11e
        tax                     ; X = GenjuProp row offset
        shorta
        lda     f:GenjuProp+1,x ; the esper's five taught-spell IDs
        jsr     @add
        lda     f:GenjuProp+3,x
        jsr     @add
        lda     f:GenjuProp+5,x
        jsr     @add
        lda     f:GenjuProp+7,x
        jsr     @add
        lda     f:GenjuProp+9,x
        jsr     @add
@done:  plx
@next:  dex
        dex
        bpl     @slot
        plp
        rtl
; add spell id A to the union $3034[id] := id, skipping $ff (empty slot / NONE)
@add:   cmp     #$ff
        beq     @ret
        longa
        and     #$00ff
        tay                     ; Y = spell id (clean 16-bit)
        shorta
        sta     $3034,y         ; A low byte = id -> $3034[id]
@ret:   rts
.endproc

; ------------------------------------------------------------------------------

; [ M5 espers-as-sub-jobs: a while-equipped stat mod (the owner's fork-4 pick) ]
;
; Vanilla applied an esper's GenjuProp bonus byte at LEVEL-UP (DoLevelUp ->
; GenjuBonusTbl, battle_main.asm:15826/:15960) -- a permanent, accumulating write
; to the character stat record ($161a strength / $161b speed / $161c stamina /
; $161d mag.pwr).  The M5 core DELETED that: every GenjuProp bonus byte is $ff, so
; DoLevelUp bmi-skips it (:15827) and the record never grows.  The owner's call
; (ROADMAP M5) is the WHILE-EQUIPPED model instead: hold the esper, get the bump;
; unequip, it is gone -- reversible, never written to the persistent record.
;
; WHERE IT APPLIES -- the battle-side stat copy, NOT $161a-$161d.  FF6 already has
; a while-equipped stat mechanism: EQUIPMENT.  UpdateEquip (bank C1) folds a
; character's gear bonuses into the $1100 property buffer ($11a6 vigor, $11a4
; speed, $11a2 stamina, $11a0 mag.pwr), and UpdateEquipBattle
; (battle_main.asm:6749) copies that buffer into the battle-side effective stats
; ($3b2c vigor*2, $3b19 speed, $3b40 stamina, $3b41 mag.pwr) -- the values the
; damage/hit/ATB math actually reads.  Those copies are rebuilt from base+gear at
; every battle init and on every mid-battle re-derivation (morph/revert/revive --
; the :5639 UpdateEquipBattle call), and are NEVER written back to the $16xx
; record.  So an esper mod added there is reversible BY CONSTRUCTION: it exists
; only for as long as the esper is worn at (re-)derivation time.  This proc is
; jsl'd at the TOP of UpdateEquipBattle, right after it points D at $1100 and
; before it reads the buffer, so the esper mod rides the SAME path as a gear
; bonus -- vanilla then does the vigor-doubling, the $ff caps, and the dual speed
; store ($3b19 + the write-only $3b2d dummy) for free.  Covering both
; UpdateEquipBattle callers (init + re-derive) makes the esper bump survive a
; mid-battle revive exactly as a relic's +Vigor does.  Adding at the damage-calc
; sites instead was rejected: vigor/magpwr/stamina/speed each feed several
; formulas, so it would be many hooks where this is one, and it would have to
; re-implement the reversibility the per-battle rebuild already gives.
;
; THE DATA -- an OT6-side table, NOT the repurposed GenjuProp bonus byte.  The
; byte was tempting (its GENJU_BONUS enum already spells +Str/+Spd/+Stam/+MagPwr),
; but the core set every one to $ff precisely so DoLevelUp skips it, and DoLevelUp
; reads that byte UNCONDITIONALLY (:15826).  Re-authoring it to a positive value
; to mean "while-equipped mod" would re-arm the vanilla LEVEL-UP bump we just
; deleted -- reviving the permanent record write and breaking battle_subjob's
; deletion control (scenario D) -- unless DoLevelUp were ALSO edited to force the
; skip.  That is shared-code surgery for no gain.  A parallel bank-$f0 table keyed
; by esper index (the shape Ot6FoldTbl / Ot6AbilityCostTbl already use) keeps the
; whole new mechanism in ot6.asm, leaves the GenjuProp bytes at $ff, and keeps the
; two stat lifetimes (deleted level-up vs new while-equipped) off one shared byte.
;
; +STAT ONLY for v0.4; HP/MP% DEFERRED.  The GENJU_BONUS HP_x/MP_x are a percent
; of a max that would then shift on equip/unequip (max-HP moving mid-battle is the
; fiddly case the brief flags).  v0.4 ships the four flat stat mods only; the
; table selector has no HP/MP encoding, so the deferral is structural, not a
; runtime skip.  HP/MP% is a v0.5 item.
;
; CONTRACT: entered from UpdateEquipBattle with D=$1100, DBR=$7e, X = character
; battle index; caller register widths are unknown (the :5639 path enters i8), so
; the proc saves P and re-establishes its own.  Widening the index to i16 is safe:
; an i8 caller's XH is hardware-forced to $00 and X here is a small slot index, so
; the widen always yields the true index.  X is preserved for the
; UpdateEquipBattle body; A/Y are dead across this point (the body re-derives Y at
; its head).  Scratch is stack + registers only -- no DP cell is touched (D=$1100
; would alias the property buffer).
;
; while-equipped stat selectors: high nibble of an Ot6EsperStatTbl byte (low
; nibble = magnitude in base-stat points); $00 = no mod.
OT6_SM_NONE   = $00
OT6_SM_VIGOR  = $10             ; -> $11a6 buffer (vanilla doubles it into $3b2c)
OT6_SM_SPEED  = $20             ; -> $11a4 buffer ($3b19)
OT6_SM_STAM   = $30             ; -> $11a2 buffer ($3b40)
OT6_SM_MAGPWR = $40             ; -> $11a0 buffer ($3b41)

.proc Ot6EsperStatMod
        php
        longai                  ; a16/i16 (safe widen; see contract)
        phx                     ; preserve the caller's character battle index
        lda     $3010,x         ; this character's $16xx record pointer
        tax
        shorta                  ; a8
        lda     $161e,x         ; equipped esper (bit7 set / $ff = none)
        bmi     @out
        longa                   ; a16: clean the index for the table lookup
        and     #$00ff          ; esper index 0..26
        tax
        shorta                  ; a8
        lda     f:Ot6EsperStatTbl,x   ; packed mod: [stat sel : 4][magnitude : 4]
        beq     @out            ; $00 -> this esper has no while-equipped mod
        pha                     ; hold the packed byte for the selected branch
        lsr4                    ; A = stat selector 1..4
        cmp     #1
        beq     @vigor
        cmp     #2
        beq     @speed
        cmp     #3
        beq     @stam
; selector 4 = mag.pwr -> buffer $11a0
        pla                     ; packed
        and     #$0f            ; magnitude
        clc
        adc     $a0             ; += buffer mag.pwr (D=$1100 -> $11a0)
        bcc     @wm
        lda     #$ff            ; byte cap, matching vanilla's stat caps
@wm:    sta     $a0
        bra     @out
@vigor:                         ; buffer $11a6 (vanilla later doubles it into $3b2c)
        pla
        and     #$0f
        clc
        adc     $a6
        bcc     @wv
        lda     #$ff
@wv:    sta     $a6
        bra     @out
@speed:                         ; buffer $11a4 (-> $3b19, and the $3b2d dummy)
        pla
        and     #$0f
        clc
        adc     $a4
        bcc     @wp
        lda     #$ff
@wp:    sta     $a4
        bra     @out
@stam:                          ; buffer $11a2 (-> $3b40)
        pla
        and     #$0f
        clc
        adc     $a2
        bcc     @ws
        lda     #$ff
@ws:    sta     $a2
@out:   longi                   ; i16 to match the phx width
        plx                     ; restore the character battle index
        plp
        rtl
.endproc

; Ot6EsperStatTbl -- one packed byte per esper index (GenjuProp order), read by
; Ot6EsperStatMod while that esper is worn.  Authored so far: the four Zozo
; espers (v0.4) plus Ifrit and Shiva, the two the Magitek Research Facility pays
; out (v0.6, docs/design/magicite-ifrit-shiva.md).  The rest are $00 (no mod), a
; data-append exactly like their spell lists (genju_prop.asm).  Magnitudes are
; picked to be felt but not swingy (~10-16% of an early base stat) on a two-tier
; ladder the player can read: FIELD stones found on a floor are 2-3, BOSS stones
; fought for are 4-5.  M6 owns the final numbers.
Ot6EsperStatTbl:
        .byte   OT6_SM_STAM   | 3       ;  0 ramuh    +3 stamina (canon; vanilla STAMINA_1)
        .byte   OT6_SM_VIGOR  | 5       ;  1 ifrit    +5 vigor -- the ONLY vigor
                                        ;    stone (nobody else claims the
                                        ;    selector), and the first BOSS-tier
                                        ;    magnitude: field stones picked off a
                                        ;    Zozo floor are 2-3, fought-for stones
                                        ;    are 4-5.  Base vigor is 31-47 at this
                                        ;    point and barely moves all game (M5
                                        ;    deleted the per-level esper bonuses),
                                        ;    so +5 is ~11-16%.  Vanilla doubles
                                        ;    vigor into $3b2c, so the effective
                                        ;    battle bump is +10.  It is the right
                                        ;    reward for the Magitek Research
                                        ;    Facility, where every boss is
                                        ;    class-breakable and neither of this
                                        ;    pair's elements is a key.
        .byte   OT6_SM_MAGPWR | 4       ;  2 shiva    +4 mag.pwr -- boss tier, one
                                        ;    step over Kirin/Stray's +3.  Base
                                        ;    mag.pwr is 25-39, so ~10-16%.  Two of
                                        ;    her three spells scale off it.
                                        ;    COMPROMISE (magicite-ifrit-shiva.md
                                        ;    §5.2, §12.1): the design wants a
                                        ;    TWO-SIDED mod -- Ifrit +vigor/-magpwr,
                                        ;    Shiva +magpwr/-vigor -- so the pair
                                        ;    reads as opposed specialisations.
                                        ;    This table cannot say it: one
                                        ;    selector, one UNSIGNED 4-bit
                                        ;    magnitude (see the encoding above).
                                        ;    Widening it to two bytes with a
                                        ;    signed magnitude is the fix; it is a
                                        ;    change to shipped machinery and to
                                        ;    battle_esperstats.lua, so it is not
                                        ;    made here.
        .byte   OT6_SM_SPEED  | 2       ;  3 siren    +2 speed (tempo/control caster)
        .byte   OT6_SM_NONE             ;  4 terrato
        .byte   OT6_SM_NONE             ;  5 shoat
        .byte   OT6_SM_NONE             ;  6 maduin
        .byte   OT6_SM_NONE             ;  7 bismark
        .byte   OT6_SM_MAGPWR | 3       ;  8 stray    +3 mag.pwr (vanilla MAGPWR_1)
        .byte   OT6_SM_NONE             ;  9 palidor
        .byte   OT6_SM_NONE             ; 10 tritoch
        .byte   OT6_SM_NONE             ; 11 odin
        .byte   OT6_SM_NONE             ; 12 raiden
        .byte   OT6_SM_NONE             ; 13 bahamut
        .byte   OT6_SM_NONE             ; 14 alexandr
        .byte   OT6_SM_NONE             ; 15 crusader
        .byte   OT6_SM_NONE             ; 16 ragnarok
        .byte   OT6_SM_MAGPWR | 3       ; 17 kirin    +3 mag.pwr (healer; heal potency)
        .byte   OT6_SM_NONE             ; 18 zoneseek
        .byte   OT6_SM_NONE             ; 19 carbunkl
        .byte   OT6_SM_NONE             ; 20 phantom
        .byte   OT6_SM_NONE             ; 21 sraphim
        .byte   OT6_SM_NONE             ; 22 golem
        .byte   OT6_SM_NONE             ; 23 unicorn
        .byte   OT6_SM_NONE             ; 24 fenrir
        .byte   OT6_SM_NONE             ; 25 starlet
        .byte   OT6_SM_NONE             ; 26 phoenix

