; ------------------------------------------------------------------------------

; [ full HP/MP restore on level up ]
;
; A character who gains a level refills current HP and MP to the new maxima.
; Boost points are battle-scoped RAM that resets every fight, and the $1600
; record carries only HP ($1609/$160b) and MP ($160d/$160f), so the
; implementable meaning is HP + MP.
;
; Called by a jsl at the tail of vanilla DoLevelUp (battle_main.asm, right after
; it stores the raised max MP), so the max HP/MP this refills to are already the
; post-level values; refilling before the raise would undershoot by the level's
; gain. X = record pointer, Y = battle slot, A = 16-bit (DoLevelUp is mid-longa).
;
; Why the battle copies ($3bf4,y / $3c08,y) rather than the record's own current
; cells ($1609,x / $160d,x): the victory sequence runs WinBattle first, then
; UpdateSRAM
; (battle_main.asm:11982-11983). UpdateSRAM copies each character's end-of-battle
; battle HP/MP ($3bf4/$3c08) back over the record's current HP/MP
; (battle_main.asm:12136-12141). A refill written to the record here would be
; overwritten a few instructions later; the battle cell is the authority
; at this point, and UpdateSRAM carries it into save RAM.
;
; Multi-level: CheckLevelUp loops DoLevelUp once per level gained
; (battle_main.asm:15773-15780), so this runs once per level and each pass reads
; the freshly-raised max, and the last pass leaves the battle cell at the final
; max. Multi-character: WinBattle's reward loop (battle_main.asm:15443-15461)
; visits each live party slot, and Y (the slot) survives down into DoLevelUp
; because ExecBtlGfx preserves it (phy/ply, battle_main.asm:16396/16410), the
; same invariant vanilla relies on when it reads $3ed8,y one instruction
; after `jsr CheckLevelUp` (battle_main.asm:15456). A character who takes no
; level never enters DoLevelUp, so their damaged battle HP/MP flow through
; UpdateSRAM un-restored.
;
; The refill target is the effective max, decoded through the boost tier the top
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
; low-14-bit base: 00 +0%, 01 +25%, 10 +50%, 11 +12.5%. A(16)=base|tier in,
; A(16)=base+boost out, uncapped; the caller clamps. Scratch $ee is dead at
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

; [ espers-as-sub-jobs: an equipped esper grants its spells to the Magic list ]
;
; Replaces the learned-status read `lda ($f0),y` inside ValidateSpellList's
; AddToSpellList_02 (battle_main.asm), the read whose $ff result marks a spell
; known/castable (`... inc / beq add`).  Y = the spell id (0..$35), $f0 = the
; character's $1a6e learned-spell table pointer ($1a6e + char*$36, set at the
; head of ValidateSpellList).  A(8) is returned as the effective learned status:
; $ff when the spell is castable, the real (< $ff) learn% otherwise.
;
; Additive, fork-independent core.  Two ways a spell is castable:
;   1. innate: $1a6e holds $ff.  Read first and returned unchanged, so a
;      character's own known spells are never touched.  That is why
;      the read happens before the esper check: the augment/replace fork
;      differs only in whether innate spells are later suppressed, and
;      suppression is not built here.
;   2. granted: the character's equipped esper ($f7, the byte ValidateSpellList
;      already banked at its head; negative = none) lists this spell id in its
;      GenjuProp row.  UpdateEnabledMagic/CheckMagicEnabled then enable and draw
;      it with no further work.  Equip Ramuh and Bolt/Rasp become castable;
;      unequip ($f7 negative) and the bmi makes this proc return the untouched
;      vanilla status, so it has no effect.
;
; The GenjuProp row is esper*11 (GetGenjuPropPtr, battle_main.asm:16155),
; computed inline because that helper lives in the battle bank and this proc does
; not: 11e = ((e*4 + e)*2 + e).  Only the five spell-id bytes (+1,+3,+5,+7,+9)
; are scanned; the learn-rate bytes are all zero (genju_prop.asm) and
; irrelevant to the grant, which keys on the id alone.
;
; Contract: a8/i16, D=0, DBR = the caller's (jsl preserves it, so `($f0),y`
; reads the same $1a6e region ValidateSpellList does).  Preserves X (the loop's
; dispatch selector, live across every iteration) and Y, the spell id the
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
        phx                     ; X is the loop's dispatch selector; preserve it
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

; [ equipped esper grants its spells in the field Magic list too ]
;
; Field-menu `_c350ae` used to return the selected actor's raw $1a6e learn
; byte.  That contradicted the battle-side grant above: a stone's spell was
; castable in battle but absent between fights.  This is the field equivalent
; of Ot6EsperSpellKnown.  It returns $ff when the spell is either innately
; learned or present in the actor's equipped esper row, otherwise the untouched
; learn percentage.  Unequipping therefore removes only the grant.
;
; Contract: called by JSL from menu/skills.asm in a8/i16, A = actor id,
; Y = the selected character-record pointer, and the menu's $e0 = spell id.
; The actor indexes the learned table; Y indexes the equipped-esper byte.  Do
; not derive one from the other: transformed/later-game roster records need not
; have actor id == record slot.  Preserves Y exactly as vanilla `_c350ae` did;
; X is scratch there already.  Every WRAM access is long because this lives in
; bank F0 and must not inherit the menu's DBR by accident.
.proc Ot6FieldSpellKnown
        .a8
        .i16
        phy
        longa
        and     #$00ff
        tay                     ; Y = actor id, clean 16-bit
        shorta
        tya
        sta     hWRMPYA
        lda     #$36
        sta     hWRMPYB
        nop3                    ; let the hardware product settle
        lda     f:$7e00e0       ; field menu's current spell id
        longa
        and     #$00ff
        clc
        adc     hRDMPYL         ; actor * 54 + spell
        tax
        shorta
        lda     f:$7e1a6e,x     ; vanilla learned status
        inc
        beq     @known          ; $ff stays known without consulting the stone
        dec
        ply                     ; recover the selected record pointer supplied
        phy                     ; by C3, while keeping the preservation frame
        pha                     ; now preserve the real partial/zero status;
                                ; it must sit ABOVE the 16-bit saved Y
        tyx                     ; long addressing supports X, not Y
        lda     f:$7e001e,x     ; that record's equipped esper
        bmi     @vanilla        ; $ff = none
        sta     hWRMPYA
        lda     #11
        sta     hWRMPYB
        nop3
        ldx     hRDMPYL         ; X = GenjuProp row offset
        lda     f:$7e00e0
        cmp     f:GenjuProp+1,x
        beq     @granted
        cmp     f:GenjuProp+3,x
        beq     @granted
        cmp     f:GenjuProp+5,x
        beq     @granted
        cmp     f:GenjuProp+7,x
        beq     @granted
        cmp     f:GenjuProp+9,x
        beq     @granted
@vanilla:
        pla                     ; untouched learned percentage
        ply
        rtl
@granted:
        pla                     ; discard the saved vanilla status
@known: lda     #$ff
        ply
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ seed the master spell-list union with equipped espers' granted spells ]
;
; Called once from InitSpellList (battle_main.asm) right after its actor loop
; unions the party's innately-known spells into $3034, and before that union is
; compacted and sorted into the per-character lists.  The in-battle Magic list is
; compacted to the spells present in $3034, so a borrowed spell no party
; member knows has no slot for the per-character hook (Ot6EsperSpellKnown) to
; keep.  Measured: equip Ramuh with nobody knowing Bolt/Rasp and $208e never
; lists them.  This adds each equipped esper's GenjuProp spell-ids to $3034 so
; the slots exist; ValidateSpellList's per-character pruning then keeps each
; spell only for the character wearing the granting esper (the additive core).
; So the core needs two hooks: this union seed and the per-character grant.
;
; Entered from InitSpellList's a8/i8 world.  $3010 (record pointers) is already
; set, because InitParty (battle_main.asm:7749) runs before InitChars (:6123)
; which calls InitSpellList, so each slot's equipped esper is $161e indexed by
; $3010,slot, as ValidateSpellList reads it.  a/x/y and P are restored via
; php/plp.  Scratch $ee is written and reread with no call between.
.proc Ot6UnionEspers
        php
        longi                   ; 16-bit index for $3010 word reads and row math
        shorta                  ; 8-bit A
        ldx     #$0006          ; party entity offsets 6,4,2,0
@slot:  lda     $3ed8,x         ; actor id
        cmp     #$0c
        bcs     @next           ; empty/special/gogo/umaro: no esper to grant
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

; [ espers-as-sub-jobs: a while-equipped stat mod ]
;
; Vanilla applied an esper's GenjuProp bonus byte at level-up (DoLevelUp ->
; GenjuBonusTbl, battle_main.asm:15826/:15960), a permanent, accumulating write
; to the character stat record ($161a strength / $161b speed / $161c stamina /
; $161d mag.pwr).  Every GenjuProp bonus byte is now $ff, so DoLevelUp
; bmi-skips it (:15827) and the record never grows.  This uses a
; while-equipped model instead: hold the esper and get the bump; unequip and
; it is gone, never written to the persistent record.
;
; Where it applies: the battle-side stat copy, not $161a-$161d.  FF6 already has
; a while-equipped stat mechanism, namely equipment.  UpdateEquip (bank C1) folds
; a character's gear bonuses into the $1100 property buffer ($11a6 vigor, $11a4
; speed, $11a2 stamina, $11a0 mag.pwr), and UpdateEquipBattle
; (battle_main.asm:6749) copies that buffer into the battle-side effective stats
; ($3b2c vigor*2, $3b19 speed, $3b40 stamina, $3b41 mag.pwr), the values the
; damage/hit/ATB math reads.  Those copies are rebuilt from base+gear at
; every battle init and on every mid-battle re-derivation (morph/revert/revive,
; the :5639 UpdateEquipBattle call), and are never written back to the $16xx
; record.  So an esper mod added there is reversible by construction: it exists
; only for as long as the esper is worn at (re-)derivation time.  This proc is
; jsl'd at the top of UpdateEquipBattle, right after it points D at $1100 and
; before it reads the buffer, so the esper mod takes the same path as a gear
; bonus, and vanilla then does the vigor-doubling, the $ff caps, and the dual
; speed store ($3b19 + the write-only $3b2d dummy).  Covering both
; UpdateEquipBattle callers (init + re-derive) makes the esper bump survive a
; mid-battle revive the same way a relic's +Vigor does.  Adding at the
; damage-calc sites instead was rejected: vigor/magpwr/stamina/speed each feed
; several formulas, so it would be many hooks where this is one, and it would
; have to re-implement the reversibility the per-battle rebuild already provides.
;
; The data: an OT6-side table rather than the repurposed GenjuProp bonus byte.
; That byte looked usable (its GENJU_BONUS enum already spells
; +Str/+Spd/+Stam/+MagPwr), but the core set every one to $ff so DoLevelUp skips
; it, and DoLevelUp reads that byte unconditionally (:15826).  Re-authoring it to
; a positive value to mean "while-equipped mod" would re-arm the vanilla
; level-up bump that was just removed, reviving the permanent record write,
; unless DoLevelUp were also edited to force the skip.  A parallel bank-$f0
; table keyed by esper index (the shape Ot6FoldTbl / Ot6AbilityCostTbl already
; use) keeps the new mechanism in ot6.asm, leaves the GenjuProp bytes at $ff,
; and keeps the two stat lifetimes (removed level-up and new while-equipped)
; off one shared byte.
;
; Stat mods only; HP/MP percentages are deferred.  The GENJU_BONUS HP_x/MP_x are
; a percent of a max that would then shift on equip/unequip (max-HP moving
; mid-battle is the difficult case the brief flags).  This ships the four flat
; stat mods only; the encoding below has no HP/MP nibble, so the deferral is
; structural rather than a runtime skip.
;
; The encoding is vanilla's own equipment layout: ItemProp+16/+17 is two bytes
; holding four signed 4-bit stat deltas, and CalcEquipEffect
; (battle_main.asm:2521-2539) is its reference decoder:
;
;       lda     f:ItemProp+16,x         ; a16: both bytes
;       ldy     #$0006
;   @:  pha / and #$000f / bit #$0008 / beq + / eor #$fff7 / inc
;    +: clc / adc $11a0,y / sta $11a0,y / pla / lsr4 / dey2 / bpl @
;
; Worked through, `(v ^ $fff7) + 1` for a nibble with bit 3 set equals `-(v & 7)`,
; so a nibble is [sign:1][magnitude:3]: $0-$7 = +0..+7, $9-$f = -1..-7, and $8 is
; a dead code that decodes to zero.  Nibble order follows the Y walk (6,4,2,0)
; against $11a6 vigor / $11a4 speed / $11a2 stamina / $11a0 mag.pwr.
;
; So Ot6EsperStatTbl is two bytes per esper in that layout:
;       byte 0 = [speed:4][vigor:4]      byte 1 = [magpwr:4][stamina:4]
; $0000 = no mod.  The per-stat ceiling is 7 (vanilla's own ceiling; nothing
; in 256 item records exceeds it).  Use the `esper_stat` macro below; do not
; hand-pack.
;
; Two deliberate differences from CalcEquipEffect, both because these deltas can
; be negative against a base this code does not control:
;   * each stat is clamped to 0..255 per store (vanilla adds 16-bit and never
;     clamps, relying on its own data being in range).  UpdateEquipBattle reads
;     only the low byte of each buffer word (battle_main.asm:6786-6800), so an
;     unclamped -3 against a base of 2 would wrap to 255, turning a downside
;     into a large upside.  The $ff cap was already here; the 0 floor is new and
;     is what makes the sign bit safe to author.
;   * the code works a8 per stat rather than a16 across the buffer word, because
;     the DP form ($a0..$a6) is the only way to reach those cells without
;     assuming DBR (see the contract below), and there is no `adc dp,y` on the
;     65816.  Hence four unrolled applications instead of vanilla's Y loop.
;
; Contract: entered from UpdateEquipBattle with D=$1100, DBR=$7e, X = character
; battle index; caller register widths are unknown (the :5639 path enters i8), so
; the proc saves P and re-establishes its own.  Widening the index to i16 is safe:
; an i8 caller's XH is hardware-forced to $00 and X here is a small slot index, so
; the widen always yields the true index.  X is preserved for the
; UpdateEquipBattle body; A/Y are dead across this point (the body re-derives Y at
; its head).  Scratch is stack and registers only; no DP cell is touched
; (D=$1100 would alias the property buffer).

; OT6_SM_NEG (nibble bit 3 = subtract) lives in code_ext.inc, beside the
; Ot6EsperStatTbl declaration, because the menu reader needs it too.

; ot6_esper_nib: encode one signed decimal in -7..+7 into a nibble in
; _ot6_sm_nib.  A .set scratch symbol rather than an expression because ca65
; cannot branch inside one; the char_prop.asm macros use the same idiom.
_ot6_sm_nib .set 0
_ot6_sm_lo  .set 0
.mac ot6_esper_nib v
        .if v < 0
                .if (v) < -7
                        .error "esper stat magnitude below -7 (encoding limit)"
                .endif
                _ot6_sm_nib .set OT6_SM_NEG | (0 - (v))
        .else
                .if (v) > 7
                        .error "esper stat magnitude above +7 (encoding limit)"
                .endif
                _ot6_sm_nib .set (v)
        .endif
.endmac

; esper_stat vig, spd, stm, mag: one esper's row, signed decimals in -7..+7.
; Emits the two bytes in vanilla's ItemProp+16/+17 nibble order.
.mac esper_stat vig, spd, stm, mag
        ot6_esper_nib vig
        _ot6_sm_lo .set _ot6_sm_nib
        ot6_esper_nib spd
        .byte   _ot6_sm_lo | (_ot6_sm_nib << 4)
        ot6_esper_nib stm
        _ot6_sm_lo .set _ot6_sm_nib
        ot6_esper_nib mag
        .byte   _ot6_sm_lo | (_ot6_sm_nib << 4)
.endmac

; ot6_apply_nib dp: A(a16) holds the remaining packed nibbles, low 4 bits being
; the one to apply to the byte at DP offset `dp`.  Leaves A(a16) shifted down by
; one nibble, ready for the next call.  Clamped 0..255 both ways (see above).
.mac ot6_apply_nib dp
        .local pos, wr, done
        pha                             ; hold the remaining packed nibbles
        and     #$000f
        beq     done                    ; +0: this stat is not touched at all
        cmp     #$0008
        bcc     pos
        and     #$0007                  ; bit 3 set -> subtract this magnitude...
        beq     done                    ; ...and $8 alone is vanilla's dead zero
        shorta
        eor     #$ff                    ; A = ~mag; +1 comes from the SEC below,
        sec                             ;   so this is dp - mag
        adc     dp
        bcs     wr
        lda     #$00                    ; floor: a downside never wraps a small base
        bra     wr
pos:    shorta
        clc
        adc     dp
        bcc     wr
        lda     #$ff                    ; byte cap, matching vanilla's stat caps
wr:     sta     dp
        longa
done:   pla
        lsr4                            ; next nibble down into the low 4 bits
.endmac

.proc Ot6EsperStatMod
        php
        longai                  ; a16/i16 (safe widen; see contract)
        phx                     ; preserve the caller's character battle index
        lda     $3010,x         ; this character's $16xx record pointer
        tax
        shorta                  ; a8
        lda     $161e,x         ; equipped esper (bit7 set / $ff = none)
        bpl     :+              ; NB both exits take a BRL: the four unrolled
        brl     out             ;   ot6_apply_nib bodies put `out` more than 127
:       longa                   ;   bytes away, out of an 8-bit branch's reach
        and     #$00ff          ; esper index 0..26
        asl                     ; two bytes per esper
        tax
        lda     f:Ot6EsperStatTbl,x     ; a16 -> both bytes, as vanilla does
        bne     :+              ; $0000 -> this esper has no while-equipped mod
        brl     out
:
        ot6_apply_nib $a6       ; vigor   (vanilla later doubles it into $3b2c)
        ot6_apply_nib $a4       ; speed   (-> $3b19, and the write-only $3b2d)
        ot6_apply_nib $a2       ; stamina (-> $3b40)
        ot6_apply_nib $a0       ; mag.pwr (-> $3b41)
; NB a proc-scoped label, not a cheap local: ot6_apply_nib's own .local labels are
; ordinary labels, and every ordinary label resets ca65's cheap-local scope, so a
; `beq @out` above the macro expansions cannot see an `@out:` below them.
out:    longi                   ; i16 to match the phx width
        plx                     ; restore the character battle index
        plp
        rtl
.endproc

; Ot6EsperStatTbl: two bytes per esper index (GenjuProp order) in vanilla's own
; ItemProp+16/+17 nibble layout, read by Ot6EsperStatMod while that esper is
; worn.  The rest are $0000 (no mod), a data-append like their spell lists
; (genju_prop.asm).
;
; Vanilla doubles vigor into $3b2c (battle_main.asm:6786-6791), so every
; table vigor value reads twice as large in battle.
Ot6EsperStatTbl:
;                   vig  spd  stm  mag
        esper_stat    0,   0,  +4,  +2   ;  0 ramuh
        esper_stat   +6,   0,  +4,  -3   ;  1 ifrit
        esper_stat   -3,  +4,   0,  +6   ;  2 shiva
        esper_stat    0,  +4,   0,  +2   ;  3 siren
        esper_stat    0,   0,   0,   0   ;  4 terrato (no-mod control; leave at $0000)
        esper_stat   -2,  +6,  +2,   0   ;  5 shoat
        esper_stat   -3,   0,  +3,  +7   ;  6 maduin
        esper_stat   +5,  -2,  +3,   0   ;  7 bismark
        esper_stat    0,  +2,   0,  +4   ;  8 stray
        esper_stat    0,   0,   0,   0   ;  9 palidor
        esper_stat    0,   0,   0,   0   ; 10 tritoch
        esper_stat    0,   0,   0,   0   ; 11 odin
        esper_stat    0,   0,   0,   0   ; 12 raiden
        esper_stat    0,   0,   0,   0   ; 13 bahamut
        esper_stat    0,   0,   0,   0   ; 14 alexandr
        esper_stat    0,   0,   0,   0   ; 15 crusader
        esper_stat    0,   0,   0,   0   ; 16 ragnarok
        esper_stat    0,   0,  +2,  +4   ; 17 kirin
        esper_stat    0,   0,  +2,  +3   ; 18 zoneseek
        esper_stat    0,  -2,  +6,  +2   ; 19 carbunkl
        esper_stat    0,  +6,  -2,  +2   ; 20 phantom
        esper_stat    0,   0,  +4,  +2   ; 21 sraphim
        esper_stat    0,  -2,  +5,   0   ; 22 golem
        esper_stat    0,   0,  +5,  +2   ; 23 unicorn
        esper_stat    0,   0,   0,   0   ; 24 fenrir
        esper_stat    0,   0,   0,   0   ; 25 starlet
        esper_stat    0,   0,   0,   0   ; 26 phoenix
        calc_size Ot6EsperStatTbl
.assert sizeof_Ot6EsperStatTbl = 27 * 2, error, "Ot6EsperStatTbl must be 2 bytes per esper for 27 espers"
