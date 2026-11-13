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
;   2. Strago's Analyze (Scan, ot6_analyze.asm): always granted to him.
;   3. granted: the character's equipped esper ($f7, the byte ValidateSpellList
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
; A worn item grants too (Ot6ItemGrants, #431: the elemental shields grant
; their family's base spell while worn).  The record those items sit in is
; found through ValidateSpellList's battle slot, which its head pushed (`phx`,
; then `php`; it is called once per slot, from InitChars) before
; AddToSpellList_02's 16-bit `phy` and this jsl: at entry the slot's low byte is
; at 7,s whichever width X had (phx pushes the high byte first), 9,s after the
; phx below.
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
        cpy     #OT6_ANALYZE_SPELL
        bne     @stone
        rep     #$20            ; Strago always knows Analyze (#381,
        .a16                    ;   ot6_analyze.asm): his learned table is
        lda     $f0             ;   the one at $1a6e + 7 * $36
        cmp     #$1a6e + OT6_CHAR_STRAGO * $36
        sep     #$20            ; (plain SEP: keeps the compare's Z)
        .a8
        beq     @grant
@stone: phx                     ; X is the loop's dispatch selector; preserve it
        lda     $f7             ; this character's equipped esper (neg = none)
        bmi     @items          ; no esper worn -> only the worn items can grant
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
@items: lda     9,s             ; ValidateSpellList's battle slot (contract above)
        longa
        and     #$00ff
        tax
        lda     $3010,x         ; that slot's record offset
        clc
        adc     #$1600
        tax                     ; X = record address
        shorta
        tya                     ; A = spell id
        jsl     Ot6ItemGrants
        bcs     @hit
        plx                     ; not granted: restore X, fall to the vanilla read
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
; learn percentage.  Unequipping therefore removes only the grant.  Strago's
; Analyze (Scan) is known whatever he wears (#381, ot6_analyze.asm).
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
        cmp     #OT6_CHAR_STRAGO
        bne     @begin
        lda     f:$7e00e0       ; Strago always knows Analyze (#381)
        cmp     #OT6_ANALYZE_SPELL
        bne     :+
        lda     #$ff
        rtl
:       lda     #OT6_CHAR_STRAGO        ; A was his actor id
@begin: phy
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
        bmi     @items          ; $ff = none: only the worn items can grant
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
@items: tyx                     ; X = the selected record (Y, intact)
        lda     f:$7e00e0       ; the spell id
        jsl     Ot6ItemGrants   ; a worn item's grant (#431)
        bcs     @granted
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
; the slots exist, and likewise each worn item's grant (Ot6ItemGrantTbl, #431);
; ValidateSpellList's per-character pruning then keeps each spell only for the
; character wearing the granting esper or item (the additive core).
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
        cmp     #OT6_CHAR_STRAGO
        bne     :+
        lda     #OT6_ANALYZE_SPELL      ; Strago's Analyze has a slot too
        jsr     @add            ;   (#381); clobbers A and Y, keeps X
:       phx
        ldy     $3010,x         ; this slot's record pointer
        lda     $161e,y         ; equipped esper (neg = none)
        bmi     @items
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
@items: plx                     ; this slot
        phx
        longa
        lda     $3010,x         ; its record offset
        clc
        adc     #$1600
        tay                     ; Y = record address (Ot6ItemGrants takes it in X)
        shorta
        ldx     #0
@grant: lda     f:Ot6ItemGrantTbl,x   ; next (item, spell) pair
        cmp     #$ff
        beq     @done           ; the table's end
        lda     f:Ot6ItemGrantTbl+1,x ; its spell
        phx
        phy
        tyx
        jsl     Ot6ItemGrants   ; does a worn item grant it?
        bcc     @skip
        jsr     @add            ; (clobbers Y; restored below)
@skip:  ply
        plx
        inx
        inx
        bra     @grant
@done:  plx
@next:  dex
        dex
        bmi     @fin
        jmp     @slot           ; (past bpl's reach)
@fin:   plp
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

; [ a worn item grants a spell, as an equipped esper does (#431) ]
;
; Ot6ItemGrantTbl is (item, spell) pairs ended by $ff: while that item is worn
; in any of the record's six equipment slots ($1f-$24 past the record address),
; the spell is in the wearer's Magic list, in battle (Ot6UnionEspers,
; Ot6EsperSpellKnown) and in the field (Ot6FieldSpellKnown), the three hooks
; that read GenjuProp for an equipped esper.  Never learned: take the item off
; and the grant goes.  Each spell is a family's base (the head of an
; Ot6FoldTbl row), never a tier: boost folds up the tiers, as for a stone's
; spells.  docs/design/magicite.md "Items that grant" is the plan, and
; tools/check_spell_grants.py holds this table to it.
;
; in:  a8/i16, A = spell id, X = record address ($1600 + record offset).
; out: carry set if a worn item grants A.  Preserves A, X, Y and the DBR; reads
;      the record in bank $7e whatever the caller's DBR.
.proc Ot6ItemGrants
        .a8
        .i16
        phb
        phy
        phx
        pha                     ; 1,s = the spell asked about
        lda     #$7e
        pha
        plb                     ; DBR = $7e: the record's slots are WRAM
        txy                     ; Y = record address
        ldx     #0
@pair:  lda     f:Ot6ItemGrantTbl,x   ; this pair's item
        cmp     #$ff
        beq     @no             ; the table's end
        lda     f:Ot6ItemGrantTbl+1,x ; this pair's spell
        cmp     1,s
        bne     @next
        lda     f:Ot6ItemGrantTbl,x
        cmp     $001f,y         ; right hand
        beq     @yes
        cmp     $0020,y         ; left hand
        beq     @yes
        cmp     $0021,y         ; helmet
        beq     @yes
        cmp     $0022,y         ; armor
        beq     @yes
        cmp     $0023,y         ; relic 1
        beq     @yes
        cmp     $0024,y         ; relic 2
        beq     @yes
@next:  inx
        inx
        bra     @pair
@no:    clc
        bra     @out
@yes:   sec
@out:   pla                     ; (pulls leave carry alone)
        plx
        ply
        plb
        rtl
.endproc

Ot6ItemGrantTbl:
        .byte   ITEM::FLAME_SHLD, ATTACK::FIRE
        .byte   ITEM::ICE_SHLD, ATTACK::ICE
        .byte   ITEM::THUNDER_SHLD, ATTACK::BOLT
        .byte   $ff

; ------------------------------------------------------------------------------

; ot6 #328: the while-worn stat packages (Ot6EsperStatMod, Ot6EsperStatTbl)
; are retired; an esper's stats are now kept rungs of its ladder
; (ot6_esper.asm, Ot6EsperFold).
