; ------------------------------------------------------------------------------
; OT6 — Octopath Traveler mechanics module
;
; All new code and data live in expanded bank $F0 (segment "ot6_code") and
; are reached from vanilla banks via jsl. Keep vanilla-bank edits to minimal
; hook shims so bank $C2 stays under its fixed segment offsets.
;
; per-entity state (unused vanilla battle RAM, zeroed by InitBattle):
;   $3e38,X  current shield points (0 = broken or shieldless)
;   $3e39,X  max shield points
;   $3e88,X  broken timer (nonzero = broken; ticks with status counters)
;   $3e89,X  revealed weakness elements (bitmask, same bits as $3be0)
;   $3e9c,X  characters: boost points (0-5) · monsters: class weaknesses
;   $3e9d,X  characters: pending boost (0-3) · monsters: revealed classes
; entity offsets: $00-$06 characters, $08-$12 monsters. the split $3e9c
; table works because every consumer is entity-gated (cmp #$08) — bp code
; never touches monster rows, class code never touches character rows.
; ------------------------------------------------------------------------------

OT6_BREAK_TICKS := $10          ; a bit under vanilla stop duration ($12)

.segment "ot6_code"

; width discipline: callers vary (battle init calls some hooks with 8-bit
; index registers!). every entry point either (a) uses only width-agnostic
; instructions — no index immediates, no pushes — or (b) does php + longi
; and restores. entity-offset checks use tya/cmp (width-neutral), never
; cpy #imm. a-width is 8-bit at every hook site (verified per site in the
; assembler listings).
.a8
.i16

; ------------------------------------------------------------------------------

; [ seed monster shields at battle init ]

; called from LoadRageProp just after the weak-elements load
; a8/i16, x = monster prop offset, y = entity offset, preserves x/y

.proc Ot6SeedShields
        .a8
        .i16
        tya                     ; entity offset, width-neutral test
        cmp     #$08
        bcs     @on             ; rage load onto a character: no shields
        rtl
@on:    lda     f:MonsterProp+16,x
        sta     OT6_SCR_BIT     ; stash the level (x gets repurposed)
        phx
        longa
        txa
        lsr
        lsr
        lsr
        lsr
        lsr                     ; monster prop offset / 32 = species id
        sta     OT6_SPECIES-8,y
        ; authored shields first: bosses and marked trash live in the
        ; override table; everyone else uses the level formula
        ldx     #$0000
@scan:  lda     f:Ot6ShieldTbl,x
        cmp     #$ffff
        beq     @formula
        cmp     OT6_SPECIES-8,y
        beq     @hit
        inx
        inx
        inx
        inx                     ; 4-byte records: species, shields, classes
        bra     @scan
@hit:   shorta0
        lda     f:Ot6ShieldTbl+3,x
        sta     $3e9c,y         ; authored class weaknesses (monster half)
        lda     f:Ot6ShieldTbl+2,x
        bra     @seed
@formula:
        shorta0                 ; formula species carry no class weakness
        lda     OT6_SCR_BIT     ; level ($3e9c,y stays InitBattle-zeroed)
        lsr
        lsr
        lsr
        clc
        adc     #$02            ; shields = 2 + level / 8 ...
        cmp     #$07
        bcc     @seed
        lda     #$06            ; ... capped at 6
@seed:  sta     $3e38,y
        sta     $3e39,y
        ; weakness codex: pre-reveal anything learned in past battles
        longa
        lda     f:OT6_CODEX_MAGIC
        cmp     #$374f          ; 'O7' - codex layout v2 initialized?
        beq     @learned        ;   (v2 = elements + classes; the bump
        ; first use (or no sram bank): wipe both tables, then sign it.
        ; without 32k sram the magic never sticks and the codex is a
        ; harmless no-op: reads return open bus, merges are junk-free
        ; because we only merge after the magic matches.
        shorta0                 ;   re-wipes any 'O6'-era bank once)
        ldx     #$0000
@wipe:  sta     f:OT6_CODEX,x
        inx
        cpx     #$0300          ; 384 species x (elements, classes)
        bcc     @wipe
        longa
        lda     #$374f
        sta     f:OT6_CODEX_MAGIC
        cmp     f:OT6_CODEX_MAGIC
        bne     @nosram         ; write didn't stick: no codex bank
@learned:
        ldx     OT6_SPECIES-8,y ; species -> learned weakness bits
        shorta0
        lda     f:OT6_CODEX,x
        ora     $3e89,y
        sta     $3e89,y
        lda     f:OT6_CODEX_CLASS,x
        ora     $3e9d,y
        sta     $3e9d,y
@nosram:
        shorta0
        jsr     Ot6HpScale      ; ot6: difficulty transform (trash hp)
        plx
done:   rtl
.endproc

; ------------------------------------------------------------------------------

; [ difficulty transform: scale trash battle hp at monster seed time ]

; enemy IDENTITY (weaknesses, ai, sprites, the rom prop record) is
; vanilla-sacred; enemy DIFFICULTY numbers are ot6's tuning surface —
; applied here as a runtime transform, so the rom data never changes.
; both battle-ram copies of the loaded hp ($3bf4 current, $3c1c max —
; LoadMonsterProp's only hp stores; every monster load funnels through
; it) are multiplied by a per-band value in 16ths, clamped at $ffff.
;
; exemptions, by construction:
;   - authored species (any Ot6ShieldTbl row: bosses + tutorial trash)
;     — boss difficulty is bosses-wob.md's job (it plans hp CUTS), and
;     the gate's battle fixtures are authored species, so their damage
;     arithmetic stays byte-stable
;   - $3a47.7 battles (Cmd_20 scene change, monsters carry hp): the
;     cells hold prior-stage hp, transformed once already —
;     LoadMonsterProp's own hp store honors the same gate
;   - rage loads never reach here (character path exits the seed hook)
;
; stamina stays vanilla: LoadMonsterProp derives it from max hp BEFORE
; this hook runs — deliberate (a stat, not an hp copy). fraction-of-hp
; attacks (doom gaze etc.) read the transformed cells at cast time and
; scale with the monster: correct.
;
; called from the tail of Ot6SeedShields, monster path only. a8/i16,
; y = entity offset ($08+), species already stashed at OT6_SPECIES-8,y.
; preserves y (x is stack-saved by the caller); exits a8, b=0.
; clobbers the OT6_SCR battle scratch (init-time: nothing else live).

.proc Ot6HpScale
        .a8
        .i16
        lda     $3a47
        bmi     done            ; monsters kept hp: no fresh load to scale
        longa
        ldx     #$0000
@scan:  lda     f:Ot6ShieldTbl,x
        cmp     #$ffff
        beq     @band           ; end of table: non-authored, transform
        cmp     OT6_SPECIES-8,y
        beq     @exempt         ; authored species: hp is theirs to keep
        inx
        inx
        inx
        inx
        bra     @scan
@band:  lda     OT6_SPECIES-8,y ; species -> census band 0-3
        ldx     #$0000
        cmp     #$0060
        bcc     @mul
        inx
        cmp     #$00c0
        bcc     @mul
        inx
        cmp     #$0100
        bcc     @mul
        inx
@mul:   shorta0
        lda     f:Ot6HpMulTbl,x
        cmp     #$10
        beq     done            ; 1x: identity, leave the cells alone
        longa                   ; b cleared above: a = the mult byte
        sta     OT6_SCR_IDX     ; kept across both cells
        lda     $3bf4,y
        jsr     hpmul
        sta     $3bf4,y         ; current hp
        lda     $3c1c,y
        jsr     hpmul
        sta     $3c1c,y         ; max hp
@exempt:
        shorta0
done:   rts

; [ a = clamp16(a * mult / 16), mult byte in OT6_SCR_IDX ]
; a16/i16. shift-add through a 24-bit product — the /16 must come
; AFTER the multiply ((hp/16)*mult zeroes 15-hp intro trash), and the
; product genuinely needs bit 16+ (8000 hp x 2.5 = 20000 fits, but
; its product doesn't). clobbers x + scratch; preserves y.
hpmul:  .a16
        sta     OT6_SCR_SLOT2   ; multiplicand
        lda     OT6_SCR_IDX
        xba
        sta     OT6_SCR_BIT     ; mult << 8: msb-first bit walker
        clr_a
        sta     OT6_SCR_COLS    ; product bits 16-23
        ldx     #$0008
@bit:   asl                     ; product <<= 1 (24-bit)
        rol     OT6_SCR_COLS
        asl     OT6_SCR_BIT     ; next multiplier bit into carry
        bcc     @next
        clc
        adc     OT6_SCR_SLOT2   ; product += multiplicand
        bcc     @next
        inc     OT6_SCR_COLS
@next:  dex
        bne     @bit
        lsr     OT6_SCR_COLS    ; /16 (24-bit shift right x4)
        ror
        lsr     OT6_SCR_COLS
        ror
        lsr     OT6_SCR_COLS
        ror
        lsr     OT6_SCR_COLS
        ror
        ldx     OT6_SCR_COLS
        beq     @fits
        lda     #$ffff          ; clamp: 16-bit cells, 16-bit truth
@fits:  rts
.endproc

; hp multiplier per species-id band, in 16ths ($10 = 1x, $28 = 2.5x).
; bands follow the species census: $00-$5f the wob trash the demo
; fights, $60-$bf mid trash, $c0-$ff late trash, $100+ bosses/events.
; authored rows are exempt above this table ever applies; $100+ stays
; 1x so unauthored event species (doom gaze's saved-hp reload
; especially — it re-seeds current hp AFTER LoadMonsterProp's store)
; never compound across encounters.
Ot6HpMulTbl:
        .byte   $20             ; $000-$05f: 2x — swept (measurement #3)
        .byte   $20             ; $060-$0bf: 2x — wob mid trash, by census
                                ;   arithmetic; stretch fixtures pending
        .byte   $10             ; $0c0-$0ff: 1x — wor, unmeasured
        .byte   $10             ; $100+ (keep 1x: see doom gaze note)

; ------------------------------------------------------------------------------

; [ chip shields on an elemental weakness hit ]

; called from the weak-element branch of CalcTargetDmg (match confirmed).
; a8, y = target, $11a1 = attack elements, preserves x/y. INDEX WIDTH
; VARIES: the per-target damage loop runs i8 (CalcAttackEffect is .i8),
; so everything here is width-agnostic except the codex store, which
; pins i16 for its word-sized species load.

.proc Ot6Chip
        .a8
        tya                     ; entity offset, width-neutral test
        cmp     #$08
        bcc     done            ; characters have no shields
        lda     $3e88,y
        bne     done            ; already broken: no chip until recovery
        lda     $3be0,y
        and     $11a1
        pha                     ; matched weakness bits
        lda     $3e89,y
        eor     #$ff
        and     $01,s
        beq     merge           ; all matched bits already revealed
        pha                     ; newly revealed bits
        lda     #$15            ; "Weak against fire!" etc. ($15 + element)
        sta     $3401
        pla
@bit:   lsr
        bcs     merge           ; message index for the lowest new element
        inc     $3401
        bra     @bit
merge:  pla                     ; reveal all matched weaknesses
        ora     $3e89,y
        sta     $3e89,y
        ; learn it forever: codex entry = everything revealed so far
        ; (seed merged the old codex bits in, so this is monotonic).
        ; species is a word: pin i16 for the load — under the caller's
        ; i8 the ldx truncated species >= $100 onto the wrong codex
        ; slot (m1 latent bug; guard/lobo were too small to catch it).
        ; entity offsets survive the rep: 8-bit index mode forces the
        ; high bytes to zero.
        php
        longi
        phx
        pha
        ldx     OT6_SPECIES-8,y
        pla
        sta     f:OT6_CODEX,x
        plx
        plp
        lda     $3e38,y
        beq     done            ; shieldless monster
        dec     a
        sta     $3e38,y
        bne     done
        lda     #OT6_BREAK_TICKS
        sta     $3e88,y         ; shields down: BREAK
done:   rtl
.endproc

; ------------------------------------------------------------------------------

; [ every landed hit: weapon-class chip, then broken double ]

; replaces the bare broken-double jsl at the elemental join @0c1e, so it
; runs for every damaging hit against every target — including hits whose
; element was absorbed/nulled/forcefielded (the blade still lands) and
; hits with no element at all (most weapons). a8 (CalcTargetDmg pins it);
; the damage loop runs i8, so pin i16 here for the chip's species/codex
; indexing — entity offsets survive the rep, 8-bit index mode forces the
; high bytes to zero. preserves x/y.

.proc Ot6HitJoin
        .a8
        php
        longi
        jsr     Ot6ClassChip
        plp
        jmp     Ot6BrokenDmg    ; tail-call: its rtl returns to vanilla
.endproc

; ------------------------------------------------------------------------------

; [ chip shields on a weapon-class weakness hit ]

; the class twin of Ot6Chip, called from Ot6HitJoin for every landed hit:
; class chip is not gated on the attack having an element. a8/i16 (the
; join pinned i16), y = target, OT6_ATKCLASS = the attack's class byte
; (set at load time by Ot6WeaponClass/Ot6SkillClass/Ot6ItemClass).
; preserves x/y. same flow as the elements: reveal, message, codex,
; chip, break. differences, by design:
;   - no vanilla x2 on a class-weak hit — the damage bonus for classes
;     is the break window itself (elemental weak x2 is vanilla's rule
;     and stays vanilla's alone)
;   - wound/petrify and heal-flagged hits never chip (elements can't
;     reach their weak branch in those states, so this is parity, not
;     a new rule; the one asymmetry is undead drain-reversal, which
;     element chip allows — vanilla jank — and class chip doesn't)

.proc Ot6ClassChip
        .a8
        .i16
        tya                     ; entity offset, width-neutral test
        cmp     #$08
        bcc     done            ; characters have no shields
        lda     f:$7e0000+OT6_ATKCLASS
        beq     done            ; classless action: chips nothing
        bmi     done            ; null-break property: teaches nothing
        and     $3e9c,y         ; monster's class weaknesses
        beq     done            ; no match
        sta     OT6_SCR_BIT     ; the matched class bit (exactly one)
        lda     $3e88,y
        bne     done            ; already broken: no chip until recovery
        lda     $3ee4,y
        bit     #$c0
        bne     done            ; wound/petrify: the hit was theater
        lda     $f2             ; resolved spell flags3 (absorb/undead-drain
        lsr                     ;   reversals already folded in); ONLY bit 0
        bcs     done            ; means heal — $20 can't-dodge etc. ride the
                                ; same byte, and gating on the whole byte
                                ; silenced every flagged skill's chip
        lda     $3e9d,y
        eor     #$ff
        and     OT6_SCR_BIT
        beq     merge           ; matched class already revealed
        lda     #$45            ; "Weak against slashing" etc. ($45 + class)
        sta     $3401
        lda     OT6_SCR_BIT
@bit:   lsr
        bcs     merge           ; message index for the matched class
        inc     $3401
        bra     @bit
merge:  lda     OT6_SCR_BIT     ; reveal the matched class
        ora     $3e9d,y
        sta     $3e9d,y
        ; learn it forever, like the elements (join already pinned i16)
        phx
        pha
        ldx     OT6_SPECIES-8,y
        pla
        sta     f:OT6_CODEX_CLASS,x
        plx
        lda     $3e38,y
        beq     done            ; shieldless monster
        dec     a
        sta     $3e38,y
        bne     done
        lda     #OT6_BREAK_TICKS
        sta     $3e88,y         ; shields down: BREAK
done:   rts
.endproc

; ------------------------------------------------------------------------------

; [ double damage against a broken target ]

; the tail of Ot6HitJoin (the join of the elemental damage block, i.e.
; every hit). a8, y = target, $f0 = 16-bit damage, $f2 = resolved spell
; flags3 (bit 0 = this hit heals, absorb/undead-drain reversals folded
; in); width-agnostic on the index side (the damage loop runs i8).
; plain drains (bit 1, bit 0 clear) DO double — vanilla's elemental-weak
; x2 applies to drains too, and the break window follows vanilla's rule.

.proc Ot6BrokenDmg
        .a8
        tya                     ; entity offset, width-neutral test
        cmp     #$08
        bcc     done
        lda     $3e88,y
        beq     done            ; not broken
        lda     $f2             ; heal bit ONLY — the whole-byte gate let
        lsr                     ;   $20 can't-dodge block the double for
        bcs     done            ;   every beam and skill that carries it
        lda     $f1
        bmi     done            ; avoid 16-bit overflow (matches vanilla)
        asl     $f0
        rol     $f1
done:   rtl
.endproc

; ------------------------------------------------------------------------------

; [ note the executing attack's weapon class, at load time ]

; three loaders cover every damage path, and each STORES ALWAYS — zero
; for the classless — so a stale class can never leak between attacks:
;   Ot6SkillClass   LoadMagicProp: every spell-record attack (magic,
;                   skills, lores, dances, espers, enemy attacks, the
;                   $ee "battle" record that fronts fight/steal/jump,
;                   and the dot-tick pseudo-attacks)
;   Ot6WeaponClass  _magicpunch: fight/capture/jump weapon swings, per
;                   hand per swing (the weapon sets Fight's class)
;   Ot6ItemClass    CalcItemEffect: items, tools, thrown weapons
; the chip itself reads OT6_ATKCLASS per target in Ot6ClassChip.

; a = ability id (preserved). caller a8; index width varies — pin.

.proc Ot6SkillClass
        .a8
        php
        longi
        .i16
        phx
        pha                     ; the ability id, for the scan compares
        ldx     #$0000
@scan:  lda     f:Ot6SkillClassTbl,x
        cmp     #$ff
        beq     @miss           ; end of table: classless ability
        cmp     $01,s
        beq     @hit
        inx
        inx
        bra     @scan
@hit:   lda     f:Ot6SkillClassTbl+1,x
        bra     @store
@miss:  lda     #$00
@store: sta     f:$7e0000+OT6_ATKCLASS
        pla
        plx
        plp
        rtl
.endproc

; [ x = attacker entity offset (+1 for a left-hand swing), a free ]

; called right after _magicpunch banks the hand's weapon element, so
; $3ca8,x is the swinging hand's item id. monsters keep a graphics code
; there (MonsterProp+26), not an item — their swings carry no class.
; (raged gau inherits the rage monster's graphics code into both hands
; — SetRage — so his raged fights can read a junk class: a known wart
; until rage is retired for capture. plain gau punches bludgeon, $ff.)

.proc Ot6WeaponClass
        .a8
        php
        longi
        .i16
        txa                     ; entity+hand: chars $00-$07, else monster
        cmp     #$08
        bcs     @none
        lda     $3ca8,x         ; the swinging hand's item id
        phx
        longa
        and     #$00ff
        tax
        shorta0
        lda     f:Ot6WeapClassTbl,x
        plx
        bra     @store
@none:  lda     #$00
@store: sta     f:$7e0000+OT6_ATKCLASS
        plp
        rtl
.endproc

; [ a = item id (preserved, as is the entry carry: tools/throw flag) ]

.proc Ot6ItemClass
        .a8
        php
        longi
        .i16
        phx
        pha                     ; item id, restored for the caller
        longa
        and     #$00ff
        tax
        shorta0
        lda     f:Ot6WeapClassTbl,x
        sta     f:$7e0000+OT6_ATKCLASS
        pla
        plx
        plp
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ combined stop-or-broken turn gate ]

; replaces the stop status check in the pending-action gate;
; caller branches on nonzero to skip the turn
; a8/i16, x = entity

.proc Ot6Gate
        .a8
        .i16
        lda     $3ef8,x
        bit     #$10
        bne     done            ; stop status: skip turn (z clear)
        lda     $3e88,x         ; broken: skip turn (z clear if nonzero)
done:   rtl
.endproc

; ------------------------------------------------------------------------------

; [ tick the broken timer, restore shields on recovery ]

; called from DecCounters once per entity status-tick
; a8/i16, x = entity, a is free (caller reloads)

.proc Ot6Tick
        .a8
        .i16
        lda     $3e88,x
        beq     done
        dec     $3e88,x
        bne     done
        lda     $3e39,x         ; recovered: shields back to max
        sta     $3e38,x         ; (revealed weaknesses stay revealed)
done:   rtl
.endproc

; ------------------------------------------------------------------------------
; (m1's monster-window shield digit — the $3ecb row-glyph buffer, its
; builder, and the MenuTextCmd_0b glyph hook — is retired: it was
; redundant with the under-enemy hud and read as an enemy COUNT.
; $3ecb-$3ed3 stays ours; the odd bytes below still serve as scratch.)
; ------------------------------------------------------------------------------

; [ a battle dialogue clobbered our font cells; restore, then flag a re-lay ]

; called from _c143b9 (dialogue close, small-font restore) in bank C1 in
; TAIL position, with WaitTfrVRAM's parameters live in the registers
; (A = source bank, X = source, Y = vram dest, $10 = size). we pass them
; straight through to the vanilla staged restore — WaitTfrVRAM streams
; $400 bytes per frame and returns only after the LAST chunk has landed
; in vram — and only THEN raise OT6_FONTDIRTY so the battle nmi re-lays
; our icons over a fully-restored font (in vblank, where direct vram
; writes actually land). the re-lay is STAGED: OT6_FONTDIRTY counts
; stages remaining, and the nmi flush runs one ~128-byte slice per
; frame — the whole 768-byte re-lay measured ~46 scanlines of PIO,
; more than an entire vblank, so a single-shot re-lay tore the frame
; (probe_banner measured end-of-flush at scanline 292 of 262).
;
; both halves of the restore-then-flag ordering are the whelk
; garbled-menu bug fix (battle_dlgmenu is the regression gate):
;   * the first cut of this shim ran BEFORE the jmp WaitTfrVRAM and
;     clobbered A with the flag value, so the "restore" streamed $1000
;     bytes of bank-$01 open bus over the font and every battle menu
;     after a scripted dialogue rendered as noise;
;   * raising the flag BEFORE the restore let the nmi re-lay fire
;     between restore chunks, and the later chunks squashed the icons
;     right back to vanilla (the original icons-vanish symptom).

.proc Ot6FontRestoreMark_ext
        jsl     WaitTfrVRAM_far ; registers pass through untouched
        php
        sep     #$20            ; a8 (index width irrelevant)
        pha
        lda     #OT6_RELAY_STAGES
        sta     f:$7e0000+OT6_FONTDIRTY
        pla
        plp
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ upload element icon tiles into the battle small font ]

; called from LoadMenuGfx right after the small font transfer (forced
; blank). one 2bpp tile (8 words) per element, cell per Ot6ElemGlyphTbl.
;
; cell choice matters: vanilla battle tilemaps are junk-padded with codes
; that point at blank font cells ($ee alone appears 1000+ times around the
; screen borders) — filling those cells paints garbage at the edges. every
; cell below was verified unreferenced in the battle tilemap regions.
;
; the upload is split into six ~128-byte slices so the nmi flush can
; re-lay the font one slice per vblank after a battle dialogue (the
; whole 768 bytes as PIO measured ~46 scanlines — more than a vblank).
; this entry point runs ALL slices back to back: it is only called in
; forced blank (battle init), where budget is unlimited.

.proc Ot6LoadFontIcons_ext
        .a8
        .i16
        php
        phb
        clr_a
        pha
        plb                     ; db = $00 for hardware registers
        longi
        shorta
        lda     #$80
        sta     hVMAINC         ; increment on high byte, +1 word
        jsr     Ot6LoadElemIcons
        jsr     Ot6LoadBgGlyphsA
        jsr     Ot6LoadBgGlyphsB
        jsr     Ot6LoadObjArrowsA
        jsr     Ot6LoadObjArrowsB
        jsr     Ot6LoadObjArrowsC
        plb
        plp
        rtl
.endproc

; [ re-lay slice: the eight element icon tiles (128 bytes) ]

; a8/i16, db = $00, vmainc $80. exits a8. clobbers a/x/y.

.proc Ot6LoadElemIcons
        .a8
        .i16
        ldx     #$0000          ; icon index (long,y indexing doesn't exist)
@icon:  shorta
        lda     f:Ot6ElemGlyphTbl,x
        longa
        and     #$00ff
        asl
        asl
        asl
        clc
        adc     #$5800          ; vram word address of the font cell
        sta     hVMADDL
        txa
        asl
        asl
        asl
        asl
        tax                     ; x becomes data offset = icon * 16
@word:  lda     f:Ot6FontIcons,x
        sta     hVMDATAL
        inx2
        txa
        and     #$000f
        bne     @word
        txa                     ; recover icon index: offset / 16
        lsr
        lsr
        lsr
        lsr
        tax
        cpx     #$0008
        bcc     @icon
        shorta
        rts
.endproc

; element bit (fire $01 .. water $80) -> small font glyph/tile code.
; the weakness strip draws from this same table.
Ot6ElemGlyphTbl:
        .byte   $eb             ; fire
        .byte   $ec             ; ice
        .byte   $ed             ; lightning
        .byte   $64             ; poison ($ee is vanilla's border junk fill!)
        .byte   $ef             ; wind
        .byte   $fb             ; holy
        .byte   $fc             ; earth
        .byte   $fd             ; water

OT6_QMARK := $bf                ; '?' glyph (unrevealed weakness slot)

; battle-only scratch (unused vanilla ram $3ecb-$3ed3, ours since m1)
OT6_SCR_SLOT2 := $3ecc          ; targeted monster offset (slot * 2)
OT6_SCR_BIT   := $3ece          ; walking element bit
OT6_SCR_IDX   := $3ed0          ; element index 0-7
OT6_SCR_COLS  := $3ed2          ; strip columns drawn so far

; ------------------------------------------------------------------------------

; [ write one menu character ]

; replicates btlgfx's DrawMenuKana buffer writes: char + attribute pairs
; into the two row buffers. caller context: menu text drawing (dp $4a/$4c
; buffer pointers, $4e attribute, y = column position, a8/i16, db=$7e).
; a = character code; y advances by 2.

.proc Ot6DrawChar
        .a8
        .i16
        sta     ($4c),y
        lda     #$ff
        sta     ($4a),y
        iny
        lda     $4e
        sta     ($4c),y
        sta     ($4a),y
        iny
        rts
.endproc



; ------------------------------------------------------------------------------

; [ ability element icon + padding for battle ability lists ]

; replaces MenuTextCmd_11's pad logic; called right after MenuTextCmd_0f
; drew the ability name, ($48) still pointing at the ability id.
;   $ff empty slot:            three blanks (as vanilla)
;   spells (< $36, 7 wide):    [element icon or blank][blank][blank]
;   attacks (10 wide):         trailing blank replaced by the icon
; a8/i16, db=$7e, y = column, preserves x

.proc Ot6AbilityPad_ext
        .a8
        .i16
        lda     ($48)
        cmp     #$ff
        beq     @blank3
        cmp     #$36
        bcs     @attack
        jsr     Ot6ElemGlyphFor ; spell: icon (or blank) + two blanks
        jsr     Ot6DrawChar
        bra     @blank2
@attack:
        jsr     Ot6ElemGlyphFor
        cmp     #$ff
        beq     @done           ; no element: leave the name alone
        dey
        dey                     ; back up onto the name's last column
        pha
        lda     ($4c),y
        cmp     #$ff
        bne     @keep           ; 10-char name: no room for an icon
        pla
        jsr     Ot6DrawChar     ; overwrite trailing blank (y returns)
        bra     @done
@keep:  pla
        iny
        iny
@done:  rtl
@blank3:
        lda     #$ff
        jsr     Ot6DrawChar
@blank2:
        lda     #$ff
        jsr     Ot6DrawChar
        lda     #$ff
        jsr     Ot6DrawChar
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ element icon after an ability name in a battle list window ]

; called after ListTextCmd_0f's name loops (battle ability lists draw
; through the LIST text system, not the menu text system). $2c = ability
; id, y = list column, b = tile attribute (must be preserved), ($53)/($51)
; = list buffer pointers, $55 = second-plane attribute word.

; common core: a = GLOBAL ability id; draws the element icon (if any)
; at the current list column, preserving b (the tile attribute) for the
; caller but recoloring our own icon via the palette bits: the battle
; menu ships text palettes 0..7 with distinct color-3 hues (0 white,
; 1 gray, 2 yellow, 3 blue, 6 green, 7 red).
.proc Ot6ListIconCommon
        .a8
        .i16
        sta     OT6_SCR_IDX     ; ability id
        xba
        pha                     ; save the tile attribute living in b
        xba
        lda     OT6_SCR_IDX
        jsr     Ot6ElemGlyphFor ; glyph in a, element index in OT6_SCR_COLS,
        sta     OT6_SCR_BIT     ;   b cleared internally
        cmp     #$ff
        beq     @keep           ; no element: blank glyph, caller's attr
        phx
        lda     OT6_SCR_COLS    ; element index 0-7
        tax                     ; (b = 0 here, so tax is safe)
        lda     f:Ot6ElemPalTbl,x
        plx
        sta     OT6_SCR_COLS    ; palette bits for this element
        pla                     ; caller attr ...
        and     #%11100011      ; ... palette bits swapped for our color
        ora     OT6_SCR_COLS
        bra     @attr
@keep:  pla
@attr:  xba                     ; b = attr for the 16-bit store
        lda     OT6_SCR_BIT     ; glyph, or $ff = blank: ALWAYS draw, so the
        longa                   ; icon column can never go stale on reused
        sta     ($53),y         ; row buffers (replicates DrawListLetter)
        lda     $55
        sta     ($51),y
        shorta                  ; b holds our attr; caller reloads per char
        iny
        iny
        rts
.endproc

; element index -> tilemap palette bits (palette << 2)
Ot6ElemPalTbl:
        .byte   7 << 2          ; fire: red
        .byte   3 << 2          ; ice: blue
        .byte   2 << 2          ; lightning: yellow
        .byte   6 << 2          ; poison: green
        .byte   0 << 2          ; wind: white
        .byte   2 << 2          ; holy: yellow (star shape vs bolt zigzag)
        .byte   1 << 2          ; earth: gray
        .byte   3 << 2          ; water: blue (wave shape vs ice crystal)

; generic battle lists ($2c already holds a global ability id)
.proc Ot6ListIcon_ext
        .a8
        .i16
        lda     $2c
        jsr     Ot6ListIconCommon
        rtl
.endproc

; magitek list: $2c is a local index into the magitek attacks (base $83)
.proc Ot6MagitekIcon_ext
        .a8
        .i16
        lda     $2c
        clc
        adc     #$83
        jsr     Ot6ListIconCommon
        rtl
.endproc

; lore list: $2c is a local lore index (base $8b)
.proc Ot6LoreIcon_ext
        .a8
        .i16
        lda     $2c
        clc
        adc     #$8b
        jsr     Ot6ListIconCommon
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ element glyph for an ability ]

; a = ability id (0-255) -> a = element icon glyph, or $ff if the ability
; has no element. first set element bit wins. preserves x/y.

.proc Ot6ElemGlyphFor
        .a8
        .i16
        phx
        longa
        and     #$00ff
        asl                     ; id * 2
        pha
        asl
        pha                     ; id * 4
        asl                     ; id * 8
        clc
        adc     $01,s           ; + id*4
        clc
        adc     $03,s           ; + id*2  = id * 14
        tax
        pla
        pla
        shorta0
        lda     f:MagicProp+1,x ; ability element byte
        beq     @none
        ldx     #$0000
@bit:   lsr
        bcs     @hit
        inx
        bra     @bit
@hit:   txa
        sta     OT6_SCR_COLS    ; element index, for palette selection
        lda     f:Ot6ElemGlyphTbl,x
        plx
        rts
@none:  lda     #$ff
        plx
        rts
.endproc

; 8x8 2bpp element icons, element-bit order (fire $01 ... water $80)
Ot6FontIcons:
; fire ($eb)
        .byte   $10,$10,$30,$38,$38,$3c,$6c,$7c
        .byte   $6e,$7e,$ee,$fe,$7e,$7c,$3c,$00
; ice ($ec)
        .byte   $10,$10,$10,$38,$6c,$7c,$ee,$fe
        .byte   $6e,$7c,$14,$38,$18,$10,$08,$00
; lightning ($ed)
        .byte   $1e,$1e,$3c,$38,$78,$70,$fc,$fc
        .byte   $3c,$18,$38,$30,$70,$60,$60,$00
; poison ($ee)
        .byte   $00,$10,$30,$38,$78,$7c,$5c,$7c
        .byte   $de,$fe,$fe,$fe,$7e,$7c,$3c,$00
; wind ($ef)
        .byte   $00,$00,$78,$7c,$0c,$04,$fa,$fc
        .byte   $0c,$00,$7c,$78,$3c,$00,$00,$00
; holy ($fb)
        .byte   $10,$10,$10,$18,$6c,$7c,$92,$fe
        .byte   $6e,$7c,$14,$18,$18,$10,$08,$00
; earth ($fc)
        .byte   $00,$00,$10,$10,$28,$38,$6c,$7c
        .byte   $4c,$7c,$ee,$fe,$fe,$fe,$7e,$00
; water ($fd)
        .byte   $00,$00,$30,$30,$4a,$7a,$4c,$4e
        .byte   $c6,$80,$7c,$7e,$7e,$7c,$3c,$00


; ------------------------------------------------------------------------------

; [ seed boost points at battle start ]

; called from InitBattle after its ram clears. runs in longa/longi
; context (InitBattle's php/longai is still active) - widths pinned here.

.proc Ot6InitBP
        .a16
        .i16
        php
        shorta0
        jsr     Ot6CSpikeProbe  ; c toolchain spike: publish a witness
        lda     #$01
        sta     $3e9c           ; characters open with 1 bp, octopath-style
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
        cpx     #$005e          ; shadow, map base, dirty (+spare)
        bcc     @clr
        ldx     #$0000
@clr2:  sta     f:$7e0000+OT6_HUDCOPY,x
        inx
        inx
        cpx     #$0054          ; last-flushed copies
        bcc     @clr2
        sta     f:$7e0000+OT6_PIPCUR    ; live pip cell off, no stale erase
        sta     f:$7e0000+OT6_PIPPREV
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
        txa                     ; width-neutral character test
        cmp     #$08
        bcs     done            ; monsters have no bp
        lda     $3e9d,x         ; pending boost spent this action?
        beq     @gain
        sta     OT6_SCR_BIT     ; consume it: bp -= pending
        lda     $3e9c,x
        sec
        sbc     OT6_SCR_BIT
        bcs     :+
        lda     #$00            ; (defensive clamp)
:       sta     $3e9c,x
        lda     #$00
        sta     $3e9d,x         ; no regen on a boosted turn
        bra     done
@gain:  lda     $3e9c,x
        cmp     #$05
        bcs     done            ; capped at 5
        inc
        sta     $3e9c,x
done:   plp
        rtl
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
        lda     $3e9d,x         ; pending boost level
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
        lda     $3e9d,x         ; pending boost
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
        lda     $3e9d,y         ; pending boost
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

; [ boost the base damage of a boosted character action ]

; called at the tail of the physical and magic base-damage calcs.
; damage x2/x3/x4 for pending boost 1/2/3; the per-target 9999 cap
; still applies downstream. a8/i16, x = attacker, 16-bit damage $11b0.
; fight and capture spend their boost on extra swings (Ot6FightBoost),
; and tier-family spells spend it on tiers (Ot6QueueFold) — the
; multiplier serves everything else. $3a7d = the action's attack id.

.proc Ot6BoostDmg
        php                     ; caller width varies: pin our own
        longi
        shorta0
        .a8
        .i16
        txa                     ; width-neutral character test
        cmp     #$08
        bcs     done            ; monsters never boost
        lda     $b5             ; current command
        beq     done            ; $00 fight: boost = extra swings
        cmp     #$06
        beq     done            ; $06 capture: same fight path
        lda     $3e9d,x         ; pending boost level
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
        lda     $3e9d,x         ; pending boost level (reload)
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

.proc Ot6LoadBgGlyphsA
        .a8
        .i16
        ot6_glyph_slice $0000, $0008
.endproc

.proc Ot6LoadBgGlyphsB
        .a8
        .i16
        ot6_glyph_slice $0008, $0010
.endproc

; ------------------------------------------------------------------------------

; [ upload the boost-mark sprite tiles ]

; three 16x16 arrow glyphs (1/2/3 chevrons) into obj tiles 200/202/204
; (quads with 216/217 etc. below) — verified blank + unreferenced by
; any oam entry in both formations, idle and through attack effects
; (probe_objtiles.lua). obj chr base is word $2000 (obsel $61), 4bpp.
; 12 tiles x 32 bytes, as three 4-tile slices (~128 bytes each — one
; fits a vblank-tail re-lay stage).
; a8/i16, db = $00, vmainc $80. exits a8. clobbers a/x/y.

.macro ot6_arrow_slice first, last
        longa
        ldx     #first          ; data offset; table offset = x >> 4
@tile:  phx                     ; (long,y indexing doesn't exist)
        txa
        lsr
        lsr
        lsr
        lsr                     ; tile index * 2
        tax
        lda     f:Ot6ObjArrowAddrTbl,x
        sta     hVMADDL
        plx
        ldy     #$0010          ; 16 words per 4bpp tile
@word:  lda     f:Ot6ObjArrowData,x
        sta     hVMDATAL
        inx
        inx
        dey
        bne     @word
        cpx     #last
        bcc     @tile
        shorta
        rts
.endmacro

.proc Ot6LoadObjArrowsA
        .a8
        .i16
        ot6_arrow_slice $0000, $0080
.endproc

.proc Ot6LoadObjArrowsB
        .a8
        .i16
        ot6_arrow_slice $0080, $0100
.endproc

.proc Ot6LoadObjArrowsC
        .a8
        .i16
        ot6_arrow_slice $0100, $0180
.endproc

; vram word addresses of the arrow tiles: quads at 200, 202, 204
; ($2000 + tile*16), each TL, TR, BL, BR
Ot6ObjArrowAddrTbl:
        .word   $2c80,$2c90,$2d80,$2d90
        .word   $2ca0,$2cb0,$2da0,$2db0
        .word   $2cc0,$2cd0,$2dc0,$2dd0

Ot6ObjArrowData:
; boost-one: 16x16 as tiles TL, TR, BL, BR
        .byte   $00,$00,$00,$00,$00,$00,$08,$08,$0e,$0e,$0f,$0f,$0f,$0f,$0f,$0f
        .byte   $00,$00,$00,$00,$00,$00,$08,$08,$0e,$0e,$0f,$0f,$0f,$0f,$0f,$0f
        .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$80,$e0,$e0,$f8,$f8
        .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$80,$e0,$e0,$f8,$f8
        .byte   $0f,$0f,$0f,$0f,$0f,$0f,$0e,$0e,$08,$08,$00,$00,$00,$00,$00,$00
        .byte   $0f,$0f,$0f,$0f,$0f,$0f,$0e,$0e,$08,$08,$00,$00,$00,$00,$00,$00
        .byte   $f8,$f8,$e0,$e0,$80,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
        .byte   $f8,$f8,$e0,$e0,$80,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
; boost-two: 16x16 as tiles TL, TR, BL, BR
        .byte   $00,$00,$00,$00,$00,$00,$00,$00,$40,$40,$60,$60,$78,$78,$7e,$7e
        .byte   $00,$00,$00,$00,$00,$00,$00,$00,$40,$40,$60,$60,$78,$78,$7e,$7e
        .byte   $00,$00,$00,$00,$00,$00,$00,$00,$80,$80,$c0,$c0,$f0,$f0,$fc,$fc
        .byte   $00,$00,$00,$00,$00,$00,$00,$00,$80,$80,$c0,$c0,$f0,$f0,$fc,$fc
        .byte   $7e,$7e,$78,$78,$60,$60,$40,$40,$00,$00,$00,$00,$00,$00,$00,$00
        .byte   $7e,$7e,$78,$78,$60,$60,$40,$40,$00,$00,$00,$00,$00,$00,$00,$00
        .byte   $fc,$fc,$f0,$f0,$c0,$c0,$80,$80,$00,$00,$00,$00,$00,$00,$00,$00
        .byte   $fc,$fc,$f0,$f0,$c0,$c0,$80,$80,$00,$00,$00,$00,$00,$00,$00,$00
; boost-three: 16x16 as tiles TL, TR, BL, BR
        .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$84,$84,$c6,$c6,$f7,$f7
        .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$84,$84,$c6,$c6,$f7,$f7
        .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$20,$20,$30,$30,$bc,$bc
        .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$20,$20,$30,$30,$bc,$bc
        .byte   $f7,$f7,$c6,$c6,$84,$84,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
        .byte   $f7,$f7,$c6,$c6,$84,$84,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
        .byte   $bc,$bc,$30,$30,$20,$20,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
        .byte   $bc,$bc,$30,$30,$20,$20,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00

; ------------------------------------------------------------------------------

; [ boost marks: arrows above every boosting character ]

; called from the battle nmi right after ClearSpriteData parked the
; frame's sprites (and after vanilla reset its allocator) — parked
; entries stay parked unless we claim them, so cleanup is free. draws
; oam entry 96+slot (16x16, obj palette 3, priority 3) above each
; character with pending boost, tracking their animated coords live;
; marks ride from the R press until the boosted action resolves.
; also re-asserts our two pal-3 colors every frame (effects use pal 3
; as scratch) with the same yellow/white pulse as the menu cell.
; db = $00 in this hook (oam shadow + dp live in bank 0); game state
; reads go through $7e long addressing.

.proc Ot6BoostMarksNmi_ext
        php
        longi
        shorta
        .a8
        .i16
        phb
        clr_a
        pha
        plb                     ; db = $00
        phx
        phy
        ; own obj palette 3's color 15 every frame: yellow/white pulse
        longa
        lda     $98             ; nmi frame counter
        and     #$0008
        bne     :+
        lda     #$1bff          ; yellow
        bra     :++
:       lda     #$7fff          ; white
:       sta     f:$7e7f7e       ; pal 3 color 15 in the palette buffer
        shorta
        ldx     #$0000          ; slot * 2
@slot:  lda     f:$7e3e9d,x     ; pending boost
        beq     @next
        dec
        asl
        clc
        adc     #$c8            ; tile: $c8/$ca/$cc for 1/2/3
        pha
        txa
        asl                     ; slot * 4 = oam entry offset
        longa
        and     #$00ff
        clc
        adc     #$0480          ; entry 96 + slot
        tay
        lda     f:$7e8033,x     ; char x + 8
        sec
        sbc     #$0018          ; one sprite-width in front of the face
        shorta                  ; (heroes face left; vanilla draws chars
        sta     $0000,y         ; in front of same-priority higher oam
        longa                   ; entries, so overlap would hide us)
        lda     f:$7e803b,x     ; char y + 8
        sec
        sbc     #$0008          ; level with the head
        shorta
        sta     $0001,y         ; sprite y
        pla
        sta     $0002,y         ; tile
        lda     #$36            ; palette 3, priority 3
        sta     $0003,y
@next:  inx
        inx
        cpx     #$0008
        bcc     @slot
        ply
        plx
        plb
        plp
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ per-frame bg hud: rebuild the shadow line buffer ]

; the hud lives on the bg3 field tilemap; this main-loop pass fills a
; shadow buffer in bank $7f, and the nmi flush copies it to vram during
; vblank. shadow at $7f:fe00, 10 lines x 12 bytes:
;   +0  vram word address of the line's first cell (0 = line disabled)
;   +2  five tilemap words (glyph | attr << 8)
; monsters: [shield-with-count][up to 4 weakness slots]. heroes: one
; pip-cluster cell. entities animate and drift, so each line remembers
; its previous address; the flush blanks the old cells when it moves.
; line layout: +0 cur addr (0 = disabled), +2 prev addr, +4 five cells.

OT6_SHADOW  := $5762            ; lines, stride 14 (trace-verified free)
OT6_MAPBASE := $57b6            ; word scratch: field bg3 map base

.proc Ot6BgHud_ext
        .a8
        .i16
        php
        longi
        shorta0
        phx
        phy
        phb
        lda     #$7e
        pha
        plb
        ; field bg3 map base (word address) from the hdma-fed value
        longa
        lda     $897b
        and     #$00fc
        xba                     ; << 8 == (>>2) << 10
        sta     f:$7e0000+OT6_MAPBASE
        shorta0
        ldy     #$0000          ; monster slot offset
        ldx     #$0000          ; shadow byte offset
@slot:  jsr     Ot6BgHudLine
        longa
        txa
        clc
        adc     #$000e
        tax
        shorta0
        iny
        iny
        cpy     #$000c
        bcc     @slot
        jsr     Ot6Boost        ; l/r boost input + live pip cell
        plb
        ply
        plx
        plp
        rtl
.endproc

; one monster line. x = shadow line base (kept), y = monster slot offset.
.proc Ot6BgHudLine
        .a8
        .i16
        lda     $3aa8,y
        lsr
        bcs     @on
        ; monster gone: disable the line (flush blanks the old cells once)
        longa
        lda     #$0000
        sta     f:$7e0000+OT6_SHADOW,x
        shorta0
        rts
@on:    ; blank the five cell words, rebuild below. the anchor word at +0
        ; is only committed at the very end (and only once per battle):
        ; the NMI flush can fire mid-rebuild, so the enable is the commit.
        longa
        lda     #$21ff
        sta     f:$7e0000+OT6_SHADOW+4,x
        sta     f:$7e0000+OT6_SHADOW+6,x
        sta     f:$7e0000+OT6_SHADOW+8,x
        sta     f:$7e0000+OT6_SHADOW+10,x
        sta     f:$7e0000+OT6_SHADOW+12,x
        shorta0
        ; dead monsters: cells stay blank, line stays live (erases old art)
        lda     $3eec,y
        bit     #$c2
        jne     @done
        ; cell 0: shield-with-count
        lda     $3e90,y
        beq     @count
        lda     #$71            ; shield-B
        bra     @shld
@count: lda     $3e40,y
        beq     @slots          ; shieldless
        cmp     #$07
        bcc     :+
        lda     #$06
:       phx
        longa
        and     #$00ff
        tax
        shorta0
        lda     f:Ot6ShieldCellTbl-1,x
        plx
@shld:  sta     f:$7e0000+OT6_SHADOW+4,x
        ; weakness slots into cells 1-4
@slots: phx                     ; base on stack for the cap test
        lda     #$01
        sta     OT6_SCR_BIT
        lda     #$00
        sta     OT6_SCR_IDX     ; element index
@elem:  lda     OT6_SCR_BIT
        beq     @edone
        and     $3be8,y
        beq     @next
        inx
        inx                     ; claim the next cell
        txa
        sec
        sbc     $01,s           ; cells used so far (byte diff, same page)
        cmp     #$09
        bcs     @edone          ; past slot cell 4 (offsets +6..+12)
        lda     OT6_SCR_BIT
        and     $3e91,y
        beq     @q
        phx
        lda     OT6_SCR_IDX
        longa
        and     #$00ff
        tax
        shorta0
        lda     f:Ot6ElemGlyphTbl,x
        sta     $3ed3           ; scratch: glyph (strip's old slot, free)
        lda     f:Ot6ElemPalTbl,x
        ora     #$21
        plx
        sta     f:$7e0000+OT6_SHADOW+5,x
        lda     $3ed3
        sta     f:$7e0000+OT6_SHADOW+4,x
        bra     @next
@q:     lda     #$bf            ; '?', default attr already in place
        sta     f:$7e0000+OT6_SHADOW+4,x
@next:  asl     OT6_SCR_BIT
        inc     OT6_SCR_IDX
        bra     @elem
@edone: plx
@done:  ; commit: latch the anchor once per battle. monsters never move
        ; ("moving" coords are attack-animation transients that made the
        ; line jitter and blink), so compute only while still disabled.
        longa
        lda     f:$7e0000+OT6_SHADOW,x
        bne     @keep
        shorta0
        phx
        lda     $804b,y
        clc
        adc     #$07            ; first row fully past the monster's tile
        and     #$f8            ; box: monsters blink by redrawing their
                                ; own box, and an anchor rounded into its
                                ; last row flickers with every blink
        longa
        and     #$00ff
        asl
        asl                     ; row * 32
        clc
        adc     f:$7e0000+OT6_MAPBASE
        pha
        shorta0
        lda     $800f,y
        lsr
        lsr
        lsr
        dec
        longa
        and     #$00ff
        clc
        adc     $01,s
        plx                     ; (discard pushed row sum)
        plx                     ; restore shadow base
        phx
        sta     f:$7e0000+OT6_SHADOW,x  ; enable line (atomic word)
        plx
@keep:  shorta0
        rts
.endproc


; ------------------------------------------------------------------------------

; [ vblank flush: shadow lines -> bg3 field tilemap ]

; called from the battle nmi right after the oam dma.

OT6_HUDCOPY := $57de            ; (retired; kept for the memory map)
OT6_ATKCLASS := $57b8           ; the executing attack's class byte: one of
                                ;   $01/$02/$04/$08 (+$80 null-break), 0 =
                                ;   classless. set by the three load hooks,
                                ;   read per target by Ot6ClassChip. lives
                                ;   in retired OT6_HUDDIRTY's byte — inside
                                ;   the m2 trace-verified strip and the
                                ;   InitBP clear. (first pick $57d6 turned
                                ;   out to be live vanilla scratch: the
                                ;   battle_class write-watcher caught
                                ;   foreign bytes $84/$85/$ab there.)

; weakness codex: learned weaknesses persist across battles, octopath
; style. lives in the second 8k sram bank (header sram size $05), which
; vanilla save files never touch. species stash: one word per monster
; slot so the chip procs can find the codex entry at reveal time.
OT6_CODEX_MAGIC := $316000      ; word 'O7' = codex layout v2 initialized
OT6_CODEX       := $316010      ; one revealed-elements byte per species
OT6_CODEX_CLASS := $316190      ; one revealed-classes byte per species
                                ;   (contiguous after OT6_CODEX: one wipe)
OT6_SPECIES     := $57c0        ; per-slot species stash (6 words)
OT6_PIPCUR      := $57cc        ; live pip cell: menu-map word addr (0=off)
OT6_PIPPREV     := $57ce        ; last flushed addr (for erase-on-move)
OT6_PIPCELL     := $57d0        ; glyph|attr word to write
OT6_LASTLR      := $57d2        ; last frame's L/R bits (edge detect)
OT6_RESTAGE     := $57d4        ; open list wants a re-render (boost moved)
OT6_FONTDIRTY   := $57b9        ; font re-lay stages remaining (0 = clean).
                                ; RELOCATED from $57d5: vanilla reserves
                                ; $57d5..$5854 as the battle name-scratch
                                ; string (ram_res w7e57d5,128 — GfxCmd_01
                                ; attack names, GfxCmd_11 monster specials,
                                ; swdtech/esper name loaders ALL write
                                ; byte 0 nonzero), so every named-attack
                                ; banner spuriously triggered a full
                                ; ~46-scanline font re-lay in the nmi tail
                                ; and tore the frame (probe_banner: flush
                                ; end at scanline 292; battle_banner is
                                ; the regression gate). $57b9 is the spare
                                ; byte after OT6_ATKCLASS, inside the m2
                                ; trace-verified strip and the InitBP @clr
                                ; (probe_57b9 write-watch: only bank-F0
                                ; writers). $57d5+ is vanilla's alone.
OT6_RELAY_STAGES := 6           ; icons, glyphs x2, arrows x3 (~128b each)

.proc Ot6BgHudFlush_ext
        .a8
        .i16
        php
        longi
        shorta0
        phx
        phy
        phb
        clr_a
        pha
        plb                     ; db = 0 for hardware registers
        lda     #$80
        sta     hVMAINC         ; word writes for the stages and the lines
        ; a battle dialogue clobbered our font cells? re-lay them ONE
        ; ~128-byte slice per nmi (OT6_FONTDIRTY counts stages left).
        ; the full 768-byte re-lay is ~46 scanlines of PIO — more than
        ; a whole vblank — so a single-shot re-lay tore the frame it
        ; ran on (probe_banner measured flush end at scanline 292/262).
        ; staging self-heals over 6 frames and each slice is gated on
        ; the live v counter: only start one with >= 14 lines of vblank
        ; left (slice ~9 + flush ~3 + hdma/inidisp tail ~2), else retry
        ; next nmi. quiet-battle flush start measured 240-250, so the
        ; gate passes within a frame or two.
        lda     f:$7e0000+OT6_FONTDIRTY
        beq     @nofont
        lda     hSLHV           ; software-latch the h/v counters
        lda     hSTAT78         ; reset the opvct read flip-flop
        lda     hOPVCT          ; v low byte
        xba                     ; stash it in b
        lda     hOPVCT          ; v bit 8 (in bit 0)
        lsr                     ; -> carry
        xba                     ; a = v low byte (xba preserves carry)
        bcs     @nofont         ; v >= 256: 6 lines left, too late
        cmp     #$e1            ; v < 225: not vblank (defensive)
        bcc     @nofont
        cmp     #$f9            ; v > 248: too late to start a slice
        bcs     @nofont
        lda     f:$7e0000+OT6_FONTDIRTY
        dec     a
        sta     f:$7e0000+OT6_FONTDIRTY
        beq     @s0             ; a = stage 5..0, most visible first
        cmp     #$01
        beq     @s1
        cmp     #$02
        beq     @s2
        cmp     #$03
        beq     @s3
        cmp     #$04
        beq     @s4
        jsr     Ot6LoadElemIcons        ; 5: menu element icons
        bra     @nofont
@s4:    jsr     Ot6LoadBgGlyphsA        ; 4: hud shield glyphs
        bra     @nofont
@s3:    jsr     Ot6LoadBgGlyphsB        ; 3: hud pip/boost glyphs
        bra     @nofont
@s2:    jsr     Ot6LoadObjArrowsA      ; 2-0: boost-mark obj tiles
        bra     @nofont
@s1:    jsr     Ot6LoadObjArrowsB
        bra     @nofont
@s0:    jsr     Ot6LoadObjArrowsC
@nofont:
        ldx     #$0000
@line:  longa
        lda     f:$7e0000+OT6_SHADOW+2,x         ; prev
        beq     @write
        cmp     f:$7e0000+OT6_SHADOW,x           ; moved?
        beq     @write
        sta     hVMADDL                          ; blank the old cells
        lda     #$21ff
        sta     hVMDATAL
        sta     hVMDATAL
        sta     hVMDATAL
        sta     hVMDATAL
        sta     hVMDATAL
@write: lda     f:$7e0000+OT6_SHADOW,x
        sta     f:$7e0000+OT6_SHADOW+2,x         ; prev = cur
        tay
        beq     @skip
        sty     hVMADDL
        lda     f:$7e0000+OT6_SHADOW+4,x
        sta     hVMDATAL
        lda     f:$7e0000+OT6_SHADOW+6,x
        sta     hVMDATAL
        lda     f:$7e0000+OT6_SHADOW+8,x
        sta     hVMDATAL
        lda     f:$7e0000+OT6_SHADOW+10,x
        sta     hVMDATAL
        lda     f:$7e0000+OT6_SHADOW+12,x
        sta     hVMDATAL
@skip:  shorta0
        longa
        txa
        clc
        adc     #$000e
        tax
        shorta0
        cpx     #$0054          ; 6 monster lines x 14
        bcc     @line
        ; live pip pseudo-line: one cell in the menu map (active char's
        ; spendable bp during boost select). tiny, runs every nmi.
        ; the party window is double-buffered: each name row is staged at
        ; map row 1+2r AND at 9+2r (+$100 words), and the window scroll
        ; picks a band (the active character's visible copy is the yellow
        ; one). paint BOTH so the live cell shows no matter which band is
        ; on screen (writing only the low band made boost feedback
        ; invisible whenever the high band was up).
@pip:   longa
        lda     f:$7e0000+OT6_PIPPREV
        beq     @cur
        cmp     f:$7e0000+OT6_PIPCUR
        beq     @cur
        sta     hVMADDL                  ; moved/closed: blank the old cell
        lda     #$21ff
        sta     hVMDATAL
        lda     f:$7e0000+OT6_PIPPREV
        clc
        adc     #$0100                   ; ...and its band twin
        sta     hVMADDL
        lda     #$21ff
        sta     hVMDATAL
@cur:   lda     f:$7e0000+OT6_PIPCUR
        sta     f:$7e0000+OT6_PIPPREV
        beq     @pdone
        sta     hVMADDL
        lda     f:$7e0000+OT6_PIPCELL
        sta     hVMDATAL
        lda     f:$7e0000+OT6_PIPCUR
        clc
        adc     #$0100
        sta     hVMADDL
        lda     f:$7e0000+OT6_PIPCELL
        sta     hVMDATAL
@pdone: shorta0
@out:   plb
        ply
        plx
        plp
        rtl
.endproc

; [ bp pip refresh: redraw the name rows when spendable bp changes ]

; called from UpdateCharText every main-loop frame. skips while the
; battle menu text is not up yet (same gate vanilla uses for hp/mp).

; [ l/r boost input + live pip feedback ]

; runs every main-loop frame from the hud builder (db=$7e, a8/i16).
; while a battle menu is open, R raises the active character's pending
; boost (cap 3, and never past their bp) and L lowers it. the pips by
; the party names show spendable bp (bp - pending), so feedback is
; immediate: the flush's one-cell pseudo-line repaints the active row's
; pip cell straight into the menu tilemap. window_open re-stages every
; row on the next open, cleaning up any transient state.

.proc Ot6Boost
        .a8
        .i16
        lda     $7bca           ; battle menu open?
        jeq     @off
        ; edge-detect L/R from the held-buttons byte
        lda     $0a
        and     #$30            ; held L/R bits
        sta     OT6_LASTLR+1    ; scratch: held ($57d3)
        eor     OT6_LASTLR      ; changed since last frame
        and     OT6_LASTLR+1    ; & held = newly pressed
        pha
        lda     OT6_LASTLR+1
        sta     OT6_LASTLR      ; remember for next frame
        ; active character -> entity offset in y
        lda     $62ca
        longa
        and     #$0003
        asl
        tay
        shorta0
        pla
        bit     #$10            ; R: boost up
        beq     @tryl
        lda     $3e9d,y
        inc     a
        cmp     #$04            ; spend at most 3
        bcs     @deny
        cmp     $3e9c,y         ; and never more than current bp
        beq     @store
        bcs     @deny
@store: sta     $3e9d,y
        inc     $6281           ; ching (spc $2c): boost committed
        lda     #$80
        sta     OT6_RESTAGE     ; open lists re-fold their names
        bra     @show
@deny:  inc     $95             ; error buzz: at cap or out of bp
        bra     @show
@tryl:  bit     #$20            ; L: boost down
        beq     @show
        lda     $3e9d,y
        beq     @show
        dec     a
        sta     $3e9d,y
        inc     $94             ; cursor click: boost taken back
        lda     #$80
        sta     OT6_RESTAGE     ; open lists re-fold their names
@show:  ; live pip cell for the active character's menu row
        lda     $62ca
        ldx     #$0000
@row:   cmp     $64d6,x         ; find the menu row showing this slot
        beq     @found
        inx
        cpx     #$0004
        bcc     @row
        bra     @off            ; not on screen: disable the pseudo-line
@found: ; map word = $7800 + (1 + row*2)*32 + 20
        longa
        txa
        asl                     ; row*2
        inc     a               ; +1
        asl
        asl
        asl
        asl
        asl                     ; *32
        clc
        adc     #$7814          ; $7800 + 20
        sta     f:$7e0000+OT6_PIPCUR
        shorta0
        ; glyph: pending boost -> arrow cluster pulsing yellow/white
        ; (the loud "you are boosting" signal); else spendable pips
        lda     $3e9d,y
        beq     @pips
        longa
        and     #$00ff
        tax
        shorta0
        lda     f:Ot6ArrowCellTbl-1,x
        sta     f:$7e0000+OT6_PIPCELL
        lda     $0e             ; frame counter: pulse every 8 frames
        and     #$08            ; palette 2 (yellow) <-> 0 (white)
        ora     #$21
        sta     f:$7e0000+OT6_PIPCELL+1
        rts
@pips:  lda     $3e9c,y         ; pip cluster for spendable bp
        sec
        sbc     $3e9d,y
        bcs     :+
        lda     #$00
:       cmp     #$06
        bcc     :+
        lda     #$05
:       longa
        and     #$00ff
        tax
        shorta0
        lda     f:Ot6PipCellTbl,x
        sta     f:$7e0000+OT6_PIPCELL
        lda     #$21
        sta     f:$7e0000+OT6_PIPCELL+1
        rts
@off:   longa
        lda     #$0000
        sta     f:$7e0000+OT6_PIPCUR
        shorta0
        rts
.endproc

; ------------------------------------------------------------------------------

; [ re-render the open magic list when boost moved ]

; polled once per frame from the battle main loop just before the
; menu-text pump. runs menu state $0d's WORK — clear the line
; transfer buffer, stage the four visible row-pairs from the scroll
; top, arm each line's vram transfer — without its completion
; transitions (those queue window-flow steps that eventually walk
; the window shut; re-entering the state taught us that the hard
; way). the re-staged rows run through Ot6PreviewList_ext, so the
; fold preview redraws with the current pending; the window stays
; parked in browse the whole time. a8/i16, db = $7e.

; the staging routines are jsr-linkage C1 locals; call them from here
; with the rts->rtl thunk: [bank][ret16][thunk16] on the stack, jml —
; their rts lands on Ot6C1Rtl, whose rtl comes home.
.macro jsr_c1 target
        phk
        pea     :+ -1
        pea     .loword(Ot6C1Rtl)-1
        jml     f:target
:
.endmacro

; flag protocol: 0 idle, $80 fresh request (Ot6Boost), 1-3 lines left
; in an active cycle. one line per frame: the nmi's _c15d99 drains a
; single $80-byte line buffer ($5e4d) per frame, which is exactly why
; vanilla's state $0d stages one row-pair per tick.

.proc Ot6RestageGate_ext
        .a8
        .i16
        lda     f:$7e0000+OT6_RESTAGE
        beq     @no
        lda     $7bca           ; menu closed: stale flag
        beq     @drop
        lda     $7bc2           ; the per-frame menu state: $0e = magic
        cmp     #$0e            ; list up and browsing (idle machinery)
        bne     @wait
        lda     $7ba9           ; a line transfer is still queued:
        bne     @no             ; let the nmi drain it first
        lda     f:$7e0000+OT6_RESTAGE
        bmi     @fresh
        ; mid-cycle: stage the next line
        jsr     @draw
        bcs     @drop           ; fourth line: cycle complete
        lda     f:$7e0000+OT6_RESTAGE
        dec
        sta     f:$7e0000+OT6_RESTAGE
        rtl
@fresh: phx
        jsr_c1  _c15a17         ; clear the line transfer buffer
        ldx     $62ca           ; active character slot (vanilla does
        lda     $8913,x         ; this same 16-bit ldx)
        sta     $7ba6           ; draw cursor = this list's scroll top
        lda     #$80
        sta     $7ba5           ; reset the 4-line staging cycle
        plx
        jsr     @draw           ; line one, now
        lda     #$03            ; three more, one per frame
        sta     f:$7e0000+OT6_RESTAGE
        rtl
@wait:  lda     f:$7e0000+OT6_RESTAGE
        bmi     @no             ; fresh request: keep it until browsable
@drop:  lda     #$00            ; cycle complete (or abandoned mid-way)
        sta     f:$7e0000+OT6_RESTAGE
@no:    rtl
@draw:  lda     $7ba6           ; stage one row-pair and arm its
        jsr_c1  DrawMagicListText       ; transfer; carry = list done
        jsr_c1  _c15729
        rts
.endproc

; [ bp pip glyph for the party window name row ]

; menu text command $13, reached from template $01 (character names) only.
; +$4a = staging pointer w7e5b95 + row*28, so the menu row is recoverable
; without trusting any earlier command's state. empty rows draw blank.

.proc Ot6PipGlyph_ext
        .a8
        .i16
        phx
        longa
        lda     $4a             ; staging base for this row
        sec
        sbc     #$5b95
        shorta                  ; keep a: row*28 fits in 8 bits (0/28/56/84)
        ldx     #$0000
:       cmp     #$1c            ; /28 -> menu row
        bcc     :+
        sbc     #$1c
        inx
        bra     :-
:       lda     f:$7e64d6,x     ; menu row -> character slot
        cmp     #$ff
        beq     @blank
        asl                     ; slot -> entity offset
        longa
        and     #$0006
        tax
        shorta0
        lda     f:$7e3e9c,x     ; bp
        sec
        sbc     f:$7e3e9d,x     ; minus pending
        bcs     :+
        lda     #$00
:       cmp     #$06
        bcc     :+
        lda     #$05
:       longa
        and     #$00ff
        tax
        shorta0
        lda     f:Ot6PipCellTbl,x
        plx
        rtl
@blank: lda     #$ff
        plx
        rtl
.endproc

; per-species shield + class-weakness overrides: bosses get authored
; counts, marked trash gets flavor, and shields 0 means explicitly
; shieldless (no display — whelk's shell stays the wrong answer, exactly
; as vanilla intended; scripted set-pieces draw no gauge: a silent hud
; says "this one is theater"). format: .word species id (monster prop
; offset / 32), .byte shields, .byte class weaknesses; $ffff terminates.
; unlisted species use the 2 + level/8 formula and carry no class
; weakness. elemental rows are NOT here — vanilla element bits stay in
; monster data, and the element ADDS in bosses-wob.md are m6 data entry.
; shields/classes follow docs/design/bosses-wob.md v1; deviations:
;   - lobo keeps 3 (authored pre-bosses-wob; the doc proposes 2)
;   - kefka: vanilla uses ONE species ($14a) for the imperial camp gags
;     AND the narshe defense, so the narshe row (6 · slash+pierce) wins;
;     the camp fights inherit it (doc wanted 3 there). per-formation
;     overrides are an m6 question.
;   - piranha and iron fist wear their boss-block's class row (the doc
;     gives fight-level rows, not per-add rows): judgment calls.
;   - guardian/tritoch: multiple records each, WoB story order can't
;     tell them apart from here — ALL drawn shieldless for the WoB;
;     the WoR pass must re-author the real WoR fights' records.
Ot6ShieldTbl:
        ; narshe intro / escape
        .word   $0000
        .byte   2, OT6_PIERCE   ; guard: armored infantry, the tekmissile
                                ;   probe (2 = formula value, kept honest)
        .word   $0019
        .byte   3, OT6_PIERCE   ; lobo: bitier trash, and the table's
                                ;   permanent regression coverage
        .word   $0100
        .byte   0, $00          ; whelk (the shell)
        .word   $0134
        .byte   4, OT6_PIERCE   ; whelk head: the first boss break.
                                ;   $0134 'Head' is the narshe fight
                                ;   (gen_whelk measured it at $57c0);
                                ;   m1 authored $0135, the WoR
                                ;   presenter's head, so the real head
                                ;   had been seeding by formula (2).
                                ;   note: $0134 has NO vanilla fire
                                ;   weak — the tutorial's fire probe
                                ;   is an m6 element ADD, not vanilla
        .word   $0064
        .byte   4, OT6_PIERCE   ; marshal: mog's fight, mog's class
        ; mt. kolts / lete river
        .word   $0103
        .byte   5, OT6_BLUDG    ; vargas: you couldn't break him without
                                ;   the monk
        .word   $014d
        .byte   2, OT6_SLASH    ; ipooh
        .word   $012c
        .byte   5, OT6_SLASH|OT6_PIERCE ; ultros 1: the row he keeps all game
        ; the three-scenario split
        .word   $0104
        .byte   5, OT6_PIERCE   ; tunnelarmor: mug and daggers
        .word   $014a
        .byte   6, OT6_SLASH|OT6_PIERCE ; kefka (camp gags + narshe defense
                                ;   share this record — see block comment)
        .word   $0044
        .byte   4, OT6_BLUDG    ; telstar
        .word   $001a
        .byte   2, OT6_PIERCE   ; doberman
        .word   $0106
        .byte   6, OT6_BLUDG    ; ghosttrain: suplex is CORRECT now
        .word   $0155
        .byte   5, OT6_SLASH|OT6_BLUDG  ; rizopas: the coverage-rule poster child
        .word   $0154
        .byte   1, OT6_SLASH|OT6_BLUDG  ; piranha: the chum wave
        ; zozo / opera / the factory
        .word   $0107
        .byte   6, OT6_PIERCE|OT6_BLUDG ; dadaluma: break the crouch
        .word   $006c
        .byte   2, OT6_PIERCE|OT6_BLUDG ; iron fist
        .word   $012d
        .byte   6, OT6_SLASH|OT6_PIERCE ; ultros 2: same row, one more shield
        .word   $0109
        .byte   6, OT6_PIERCE   ; ifrit
        .word   $0108
        .byte   6, OT6_SLASH    ; shiva
        .word   $010a
        .byte   7, OT6_SLASH|OT6_PIERCE ; number 024: the classes are the
                                ;   handhold while wallchange spins
        .word   $010b
        .byte   7, OT6_PIERCE   ; number 128 (body)
        .word   $013f
        .byte   3, OT6_SLASH    ; right blade
        .word   $0140
        .byte   3, OT6_SLASH    ; left blade
        .word   $010d
        .byte   6, OT6_PIERCE   ; crane (element sides verified at m6 entry)
        .word   $010e
        .byte   6, OT6_PIERCE   ; crane
        ; sealed gate / thamasa / the floating continent
        .word   $012e
        .byte   7, OT6_SLASH|OT6_PIERCE ; ultros 3: the row, third verse
        .word   $0116
        .byte   7, OT6_PIERCE   ; flameeater
        .word   $00de
        .byte   1, $00          ; balloon: vanilla ice/water pops them
        .word   $0168
        .byte   7, OT6_SLASH|OT6_PIERCE ; ultros 4: one last time
        .word   $012f
        .byte   4, OT6_BLUDG    ; chupon: no bludgeon, no bragging rights
        .word   $0113
        .byte   8, OT6_PIERCE   ; airforce
        .word   $0145
        .byte   3, OT6_PIERCE   ; laser gun
        .word   $0147
        .byte   3, OT6_PIERCE   ; missilebay: the part-break cancel
        .word   $0146
        .byte   1, OT6_SLASH|OT6_PIERCE|OT6_BLUDG|OT6_SPECIAL
                                ; speck: any weapon in the game breaks it
        .word   $0117
        .byte   11, OT6_SLASH|OT6_PIERCE ; atmaweapon: the WoB final exam
                                ;   (hud shield glyphs cap at 6 — display
                                ;   saturates, the count is true)
        .word   $0118
        .byte   5, OT6_SLASH|OT6_PIERCE ; nerapa: sprint fight, low gauge
        ; scripted set-pieces: no gauge drawn
        .word   $0111
        .byte   0, $00          ; guardian
        .word   $0112
        .byte   0, $00          ; guardian
        .word   $0114
        .byte   0, $00          ; tritoch
        .word   $0115
        .byte   0, $00          ; tritoch
        .word   $0144
        .byte   0, $00          ; tritoch
        .word   $ffff

; shield-with-count glyph cells (counts 1-6)
Ot6ShieldCellTbl:
        .byte   $65,$66,$67,$69,$6a,$6b

; pip cluster cells (0-5 filled)
Ot6PipCellTbl:
        .byte   $72,$73,$75,$76,$77,$79

; boost arrow cells (pending 1-3)
Ot6ArrowCellTbl:
        .byte   $68,$6c,$6d

; bg hud glyph cells (2bpp, verified junk-free in both formations —
; probe_cells.lua rechecks candidates idle + post-action)
Ot6BgGlyphCellTbl:
        .byte   $65
        .byte   $66
        .byte   $67
        .byte   $69
        .byte   $6a
        .byte   $6b
        .byte   $71
        .byte   $72
        .byte   $73
        .byte   $75
        .byte   $76
        .byte   $77
        .byte   $79
        .byte   $68
        .byte   $6c
        .byte   $6d

Ot6BgGlyphData:
; shield-1
        .byte   $7e,$00,$91,$7e,$b1,$7e,$91,$7e
        .byte   $52,$3c,$3c,$38,$18,$00,$00,$00
; shield-2
        .byte   $7e,$00,$b1,$7e,$89,$7e,$91,$7e
        .byte   $62,$3c,$3c,$38,$18,$00,$00,$00
; shield-3
        .byte   $7e,$00,$b1,$7e,$89,$7e,$91,$7e
        .byte   $4a,$3c,$34,$38,$18,$00,$00,$00
; shield-4
        .byte   $7e,$00,$a9,$7e,$a9,$7e,$b9,$7e
        .byte   $4a,$3c,$2c,$18,$18,$00,$00,$00
; shield-5
        .byte   $7e,$00,$b9,$7e,$a1,$7e,$b1,$7e
        .byte   $4a,$3c,$3c,$38,$18,$00,$00,$00
; shield-6
        .byte   $7e,$00,$99,$7e,$a1,$7e,$b9,$7e
        .byte   $6a,$3c,$3c,$38,$18,$00,$00,$00
; shield-B
        .byte   $7e,$00,$b1,$7e,$a9,$7e,$b1,$7e
        .byte   $6a,$3c,$34,$38,$18,$00,$00,$00
; pips-0
        .byte   $00,$00,$db,$00,$db,$00,$00,$00
        .byte   $6c,$00,$6c,$00,$00,$00,$00,$00
; pips-1
        .byte   $00,$00,$db,$c0,$db,$c0,$00,$00
        .byte   $6c,$00,$6c,$00,$00,$00,$00,$00
; pips-2
        .byte   $00,$00,$db,$d8,$db,$d8,$00,$00
        .byte   $6c,$00,$6c,$00,$00,$00,$00,$00
; pips-3
        .byte   $00,$00,$db,$db,$db,$db,$00,$00
        .byte   $6c,$00,$6c,$00,$00,$00,$00,$00
; pips-4
        .byte   $00,$00,$db,$db,$db,$db,$00,$00
        .byte   $6c,$60,$6c,$60,$00,$00,$00,$00
; pips-5
        .byte   $00,$00,$db,$db,$db,$db,$00,$00
        .byte   $6c,$6c,$6c,$6c,$00,$00,$00,$00
; boost-1: one fat right arrow
        .byte   $00,$00,$20,$20,$30,$30,$38,$38
        .byte   $3c,$3c,$38,$38,$30,$30,$00,$00
; boost-2: two medium arrows
        .byte   $00,$00,$00,$00,$88,$88,$cc,$cc
        .byte   $ee,$ee,$cc,$cc,$88,$88,$00,$00
; boost-3: three narrow arrows
        .byte   $00,$00,$00,$00,$92,$92,$db,$db
        .byte   $db,$db,$92,$92,$00,$00,$00,$00

; ------------------------------------------------------------------------------

; [ calypsi-compiled C modules ]

; the c toolchain spike: ff6/src/c/*.c compiled by calypsi (cc65816
; --target snes, large code/data models), linked by ln65816 against
; ot6-rom.scm which pins section farcode at $f0f000 — the ot6_c
; segment below pins the same address on the ld65 side, so both
; linkers agree by construction. regenerate with tools/cc/build-c.sh;
; symbol offsets into the blob come from ff6/src/c/ot6c.map.
;
; calypsi 65816 abi (learned from -S output): 16-bit native modes,
; first int-sized arg in A, later args pushed as words (first at 4,s
; inside the callee), result in A, far functions end in rtl. leaf
; functions that touch no globals need no direct-page context at all.

.segment "ot6_c"

Ot6CBlob:
        .incbin "../c/ot6c.raw"
ot6_c_mix := Ot6CBlob           ; unsigned char ot6_c_mix(uchar a, uchar b)

.segment "ot6_code"

; [ c spike probe: call the compiled leaf, publish a witness ]

; runs once per battle init. the harness asserts the exact value, which
; proves compile -> link -> blob -> jsl -> abi -> return end to end.

.proc Ot6CSpikeProbe
        .a8
        .i16
        php
        longa
        pea     $0004           ; second arg, a word on the stack
        lda     #$0003          ; first arg in a
        jsl     ot6_c_mix
        sta     f:$7e57dc       ; witness: 3*2 + 4 + 1 = 11
        pla                     ; caller pops the stacked arg
        plp
        rts
.endproc

; ------------------------------------------------------------------------------

; weapon/ability class data (m3)
        .include "ot6_class.asm"
