OT6_BREAK_TICKS := $10          ; a bit under vanilla stop duration ($12)

; ------------------------------------------------------------------------------
; [ the shared 16ths multiply: a16 A *= (mult/16), clamped to $ffff ]
;
; Shared by three 16-bit scalings, each "in 16ths" ($10 = 1x, $28 = 2.5x):
; monster HP (hpmul, off Ot6ShieldTbl), the per-step danger rate
; (Ot6DangerStep, off Ot6DangerMulW), and shielded damage (Ot6ShieldedDmg,
; off Ot6ShieldedMulW).
;
; A macro rather than a proc: Ot6ShieldedDmg runs inside the per-target
; damage loop and Ot6DangerStep runs on every field step, where a jsr's
; extra cycles do not fit.
;
; in:  a16/i16.  A = the multiplicand's low word, already also stored to
;      OT6_SCR_SLOT2; OT6_SCR_BIT = mult << 8 (an msb-first bit walker);
;      OT6_SCR_COLS = 0 (product bits 16-23).  Setting all three up is the
;      caller's job: each of the three sites loads its multiplier from a
;      different place, and Ot6DangerStep folds an unrelated store into the
;      same run, so only the loop below is common.
; out: A = clamp16(product / 16).  The /16 comes after the multiply on
;      purpose: (hp/16)*mult would zero the 15-hp intro trash.  The product
;      does need bits 16+ (8000 hp x 2.5 fits in 16 bits; the product
;      does not), which is why OT6_SCR_COLS carries the top byte.
; clobbers X and the three scratch cells; preserves Y.  Exits with X = the
; overflow word (0 unless clamped); no caller reads it.
; ------------------------------------------------------------------------------
.macro ot6_mul16ths
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
        lda     #$ffff          ; clamp: the destination cells are 16-bit
@fits:
.endmacro

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
        sta     OT6_BP_CLASS,y         ; authored class weaknesses (monster half)
        lda     f:Ot6ShieldTbl+2,x
        bra     @seed
@formula:
        ; no authored class row: seed the generated break-floor class so a
        ; formula species is still breakable by some weapon class. the byte
        ; is species-indexed: OT6_FLOOR_CLASS[species]. written
        ; unconditionally at every seed: it must not survive a Cmd_20 reload
        ; (no InitBattle clear), or the hud draws a stale class-weakness
        ; cell from the slot's prior occupant. the authored @hit path
        ; overwrites OT6_BP_CLASS (store above) so its mask wins; the floor
        ; is only the fallback for un-authored ids.
        ldx     OT6_SPECIES-8,y ; species id -> index (i16: 16-bit X)
        shorta0
        lda     f:OT6_FLOOR_CLASS,x
        sta     OT6_BP_CLASS,y         ; monster class-weak mask = floor class
        lda     OT6_SCR_BIT     ; level
        lsr
        lsr
        lsr
        clc
        adc     #$02            ; shields = 2 + level / 8 ...
        cmp     #$07
        bcc     @seed
        lda     #$06            ; ... capped at 6
@seed:  sta     OT6_SHIELD_CUR,y
        sta     OT6_SHIELD_MAX,y
        ; per-monster battle-start state the seed must not inherit on the
        ; Cmd_20 scene-change reload (multi-phase bosses, reinforcements, the
        ; whelk head's retract cycle): it re-runs the seed via InitMonsters
        ; with no InitBattle $3a20-$3ed3 clear. InitBattle already zeroes
        ; these on the fresh path, so this store is redundant there and
        ; required only on reload. monster path only (y >= $08 past @on):
        ; the character rows are never touched. the codex re-merge below
        ; restores reveals that were earned (chips write them through), so a
        ; same-monster retract cycle keeps its reveals.
        lda     #$00
        sta     OT6_BROKEN_TICKS,y         ; broken timer: a stale nonzero reload-starts
                                ;   the monster broken (Ot6Gate skips its turn,
                                ;   2x damage, the hud shield cell draws the
                                ;   broken glyph)
        sta     OT6_REVEALED_ELEM,y         ; revealed weakness elements: stale bits, OR'd
                                ;   with the codex below, draw weaknesses as
                                ;   revealed from battle start instead of '?'
        sta     OT6_BOOST_REVEALED,y         ; revealed classes (monster half)
        sta     OT6_RVPEND_ELEM-8,y  ; pending reveals must not survive a
        sta     OT6_RVPEND_CLS-8,y   ;   Cmd_20 reload either
        sta     OT6_BRKTICK-8,y      ; nor a pending or live break flash.
        sta     OT6_BRKPAL-8,y       ;   these two sit past InitBP's shadow
                                     ;   clear, so this is also their only
                                     ;   power-on clear
        ; weakness codex: pre-reveal anything this save learned in past battles
        jsr     Ot6CodexActive  ; x = this save's page offset
        longa
        txa
        clc
        adc     OT6_SPECIES-8,y ; page + species
        tax
        shorta0
        lda     f:OT6_CODEX,x
        ora     OT6_REVEALED_ELEM,y
        sta     OT6_REVEALED_ELEM,y
        lda     f:OT6_CODEX_CLASS,x
        ora     OT6_BOOST_REVEALED,y
        sta     OT6_BOOST_REVEALED,y
        shorta0
        jsr     Ot6ElemAdd      ; ot6: element adds (m6 weakness data)
        jsr     Ot6HpScale      ; ot6: difficulty transform (trash hp)
        plx
done:   rtl
.endproc

; ------------------------------------------------------------------------------

; [ element adds: widen a species' weak-element byte at monster seed time ]

; A runtime transform like Ot6HpScale, applied one hook later than the
; load: the mask is OR'd into the loaded weak byte $3be0,y (LoadRageProp
; stores it from MonsterProp+25 immediately before the seed hook), so the
; chip path, vanilla's weak x2 damage, and the hud weakness slots all
; read one truth. re-loads (retract cycles, scene changes) re-apply the
; OR: idempotent by construction.
;
; every row in the table is decoded from monster_prop.dat at species*32
; +$19 (vanilla's own weak-byte offset, battle_main.asm:7517 loads
; MonsterProp+25) and checked against +$17 (absorb) and +$18 (null): no
; row here puts a chip trigger on an absorber.
;
; called from the tail of Ot6SeedShields, monster path only. a8/i16,
; y = entity offset, species stashed at OT6_SPECIES-8,y. clobbers a/x
; (the caller stack-saved x). exits a8.

.proc Ot6ElemAdd
        .a8
        .i16
        longa
        ldx     #$0000
@scan:  lda     f:Ot6ElemAddTbl,x
        cmp     #$ffff
        beq     @none
        cmp     OT6_SPECIES-8,y
        beq     @hit
        inx
        inx
        inx
        inx                     ; 4-byte records: species, elements, pad
        bra     @scan
@hit:   shorta0
        lda     f:Ot6ElemAddTbl+2,x
        ora     $3be0,y
        sta     $3be0,y
        rts
@none:  shorta0
        rts
.endproc

; per-species element adds: .word species id, .byte element mask
; (fire $01 .. water $80), .byte pad; $ffff terminates.
Ot6ElemAddTbl:
        .word   $0134
        .byte   $01, $00        ; whelk head: + fire
        .word   $0103
        .byte   $20, $00        ; vargas: + holy
        .word   $0042
        .byte   $08, $00        ; m-tekarmor: + poison (keeps bolt)
        .word   $009f
        .byte   $08, $00        ; heavyarmor: + poison (keeps bolt|water)
        .word   $0002
        .byte   $04, $00        ; templar: + bolt (keeps poison)
        .word   $014a
        .byte   $09, $00        ; kefka (narshe defense): + poison|fire
        .word   $0104
        .byte   $02, $00        ; tunnelarmor: + ice (keeps bolt|water)
        .word   $0086
        .byte   $08, $00        ; cirpius: + poison
        .word   $007a
        .byte   $08, $00        ; tusker: + poison (keeps fire)
        .word   $005c
        .byte   $08, $00        ; sand ray: + poison (keeps ice|water)
        .word   $005d
        .byte   $08, $00        ; areneid: + poison (keeps ice|water)
        .word   $0012
        .byte   $08, $00        ; rhodox: + poison
        .word   $0015
        .byte   $08, $00        ; rhinotaur: + poison
        .word   $0018
        .byte   $08, $00        ; stray cat: + poison
        .word   $001d
        .byte   $08, $00        ; baskervor: + poison
        .word   $001f
        .byte   $08, $00        ; chimera: + poison
        .word   $0078
        .byte   $08, $00        ; red fang: + poison
        .word   $007b
        .byte   $08, $00        ; ralph: + poison
        .word   $0117
        .byte   $07, $00        ; atmaweapon: + fire|ice|bolt
        .word   $010b
        .byte   $84, $00        ; number 128 body: + bolt|water
        .word   $013f
        .byte   $04, $00        ; right blade: + bolt
        .word   $0140
        .byte   $04, $00        ; left blade: + bolt
        .word   $0116
        .byte   $80, $00        ; flameeater: + water
        .word   $0168
        .byte   $04, $00        ; ultros 4: + bolt
        .word   $ffff

; ------------------------------------------------------------------------------

; [ difficulty transform: scale trash battle hp at monster seed time ]

; A runtime transform: both battle-ram copies of the loaded hp ($3bf4
; current, $3c1c max, LoadMonsterProp's only hp stores; every monster load
; goes through it) are multiplied by a per-band value in 16ths, clamped
; at $ffff.
;
; exemptions, by construction:
;   - authored species (any Ot6ShieldTbl row: bosses + tutorial trash):
;     their hp is authored directly, so this transform stays out of it
;   - $3a47.7 battles (Cmd_20 scene change, monsters carry hp): the
;     cells hold prior-stage hp, transformed once already, and
;     LoadMonsterProp's own hp store honors the same gate
;   - rage loads never reach here (character path exits the seed hook)
;
; stamina stays vanilla: LoadMonsterProp derives it from max hp before
; this hook runs, deliberately, since it is a stat rather than an hp copy.
; fraction-of-hp attacks (doom gaze etc.) read the transformed cells at
; cast time and scale with the monster, which is correct.
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
; a16/i16. the multiplicand is monster HP, so the product needs
; bit 16+ (8000 hp x 2.5 = 20000 fits, but its product does not). see
; ot6_mul16ths at the top of this file for the shift-add and for why the
; /16 comes after the multiply. clobbers x + scratch; preserves y.
hpmul:  .a16
        sta     OT6_SCR_SLOT2   ; multiplicand
        lda     OT6_SCR_IDX
        xba
        sta     OT6_SCR_BIT     ; mult << 8: msb-first bit walker
        clr_a
        sta     OT6_SCR_COLS    ; product bits 16-23
        ot6_mul16ths
        rts
.endproc

; hp multiplier per species-id band, in 16ths ($10 = 1x, $28 = 2.5x).
; bands follow the species census: $00-$5f the wob trash the demo
; fights, $60-$bf mid trash, $c0-$ff late trash, $100+ bosses/events.
; authored rows are exempt before this table applies; $100+ stays
; 1x so unauthored event species (doom gaze's saved-hp reload in
; particular, which re-seeds current hp after LoadMonsterProp's store)
; never compound across encounters. shielded resistance (Ot6ShieldedMulW)
; carries the fight-length load instead of this multiplier.
Ot6HpMulTbl:
        .byte   $10             ; $000-$05f
        .byte   $10             ; $060-$0bf
        .byte   $10             ; $0c0-$0ff
        .byte   $10             ; $100+

; ------------------------------------------------------------------------------

; [ encounter-rate knob + reward conservation ]

; the per-step encounter danger increment and random-battle rewards are
; scaled by inverse factors, so combat time per step and xp/gil per step
; both track vanilla. the two knobs are 16ths and their product is
; pinned at $100 (1.0) by the conservation rule; change them as a pair
; or the level/shop pacing drifts.

Ot6DangerMulW:
        .word   $0008           ; per-step danger increment x 8/16 (0.5x)
Ot6RewardMulW:
        .word   $0020           ; random-battle xp+gil x 32/16 (2x)

; [ suppress sub-map encounters that the vanilla field cannot start ]

; Two authored sites share one wedge: if CheckBattleSub rolls while the
; party's z-state is mid-flux, EventScript_RandBattle stops forever at
; $ca0029 waiting for the pre-battle scroll/object movement to settle;
; the battle latch never comes up and player control never returns.
;
; Map 225's north bridge shaft is a z-loop ladder: its diagonal tiles
; change the party between z 0/2/3 while a step is resolving.  The
; rectangle is the shaft's complete authored route (x 29..40, y 31..61);
; other rooms in composite map 225 lie outside it and keep their
; encounter pool.
;
; Map 132's forest corridor crosses itself at (16,8): tile prop $04
; (bridge) with z-1 and both-z neighbors ((16,9)=$01, (17,9)=$03 --
; measured by probe_forest_stall.lua, 2026-09-01), the same z-flux, and
; the same $ca0029 wedge when the fighting lineage's crossTo rolled an
; encounter there (the battle half-runs, the field redraws, the event
; and the battle table never release).  The rectangle covers the bridge
; structure and its z-transition aprons (x 14..17, y 8..9).
;
; CheckBattleSub has already proved the party is tile-aligned and
; cleared its one-step $57 request before calling.  Return carry SET to
; run the normal danger/encounter path, CLEAR to consume this step
; without adding danger or advancing the battle RNG.  a8/i16; preserves
; a/x/y and every status bit except the carry result.

.proc Ot6AllowSubBattle
        .a8
        .i16
        php
        longa
        pha
        phy
        lda     a:$0082
        cmp     #$00e1          ; field map 225, Zozo interiors
        beq     Zozo
        cmp     #$0084          ; field map 132, Phantom Forest
        beq     Forest
        bra     Allow
Zozo:   ldy     a:$0803         ; active party object's property offset
        lda     a:$086a,y       ; x in 1/16-tile units
        cmp     #$01d0          ; x < 29
        bcc     Allow
        cmp     #$0290          ; x > 40
        bcs     Allow
        lda     a:$086d,y       ; y in 1/16-tile units
        cmp     #$01f0          ; y < 31
        bcc     Allow
        cmp     #$03e0          ; y > 61
        bcs     Allow
        bra     Suppress
Forest: ldy     a:$0803         ; active party object's property offset
        lda     a:$086a,y       ; x in 1/16-tile units
        cmp     #$00e0          ; x < 14
        bcc     Allow
        cmp     #$0120          ; x > 17
        bcs     Allow
        lda     a:$086d,y       ; y in 1/16-tile units
        cmp     #$0080          ; y < 8
        bcc     Allow
        cmp     #$00a0          ; y > 9
        bcs     Allow
Suppress:
        ply
        pla
        plp
        clc                     ; suppress the unsafe roll
        rtl
Allow:  ply
        pla
        plp
        sec
        rtl
.endproc

; [ per-step danger increment, scaled ]

; replaces the vanilla `lda $1f6e / adc f:<rate table>,x` pair in the two
; per-step battle checks (CheckBattleSub in field, CheckBattleWorld on
; the world map): the caller loads its own rate table entry, this scales
; it and adds the danger counter. a16/i16 (both call sites), entry a =
; the vanilla rate; exit a = $1f6e + rate * Ot6DangerMulW / 16 with
; carry = 16-bit overflow, so the caller's bcc/#$ff00 clamp is
; unchanged. at $10 the scale is exact identity (product/16 = rate).
; preserves x/y and db; the 24-bit shift-add uses the OT6_SCR battle
; scratch (no battle is live during a field step; field/world code
; never touches $3ecc-$3ed3).

.proc Ot6DangerStep
        .a16
        .i16
        phb
        phx
        pea     $7e7e
        plb
        plb                     ; db = $7e: absolute rmw on the scratch
        sta     OT6_SCR_SLOT2   ; multiplicand (the rate)
        lda     f:Ot6DangerMulW
        and     #$00ff
        xba
        sta     OT6_SCR_BIT     ; mult << 8: msb-first bit walker
        lda     #$0000
        sta     OT6_SCR_COLS    ; product bits 16-23
        sta     a:OT6_RANDPEND  ; step hygiene: word-clears the random-
                                ;   encounter marker AND last battle's
                                ;   flag. runs before this step's roll,
                                ;   so a trigger still marks; kills any
                                ;   pre-first-battle ram junk the moment
                                ;   the player takes a danger-checked
                                ;   step (see the OT6_RANDBTL comment)
        ot6_mul16ths            ; saturates; the caller clamps the sum anyway
        clc
        adc     a:$1f6e         ; the danger counter (same cell the callers
        plx                     ;   see: db=$7e is wram, db=$00 mirrors it)
        plb
        rtl
.endproc

; [ mark the coming battle as a random encounter ]

; called from the two trigger-success paths (right after they zero the
; danger counter). InitBP consumes the marker into OT6_RANDBTL, so it
; can never outlive one battle. a8 at both sites; clobbers a.

.proc Ot6MarkRandom
        .a8
        lda     #OT6_RANDMAGIC
        sta     f:$7e0000+OT6_RANDPEND
        rtl
.endproc

; [ scale a random battle's xp and gil by the inverse of the rate knob ]

; called from WinBattle immediately after the per-monster reward sums:
; exp is 24-bit at $2f35-$2f37, gil 24-bit at $2f3e-$2f40. event and
; boss battles never carry the OT6_RANDBTL flag and pass through
; untouched; veldt battles carry it but their exp sum is zero by
; vanilla's own rule, so only their gil scales. runs BEFORE the cat-hood
; gil double and the per-character exp divide, so relics and party size
; stack on the scaled sums exactly as they stack on vanilla's.
; a16/i16 at the call site; clobbers a/x/y and the OT6_SCR scratch
; (init-time victory path: the hud builder is not concurrent).

.proc Ot6RewardScale_ext
        .a16
        .i16
        lda     a:OT6_RANDBTL-1 ; flag in the high byte (word read at -1:
        and     #$ff00          ;   $57bc pending is zeroed by init)
        beq     done
        ldx     #$2f35          ; exp sum
        jsr     scale24
        ldx     #$2f3e          ; gil sum
        jsr     scale24
done:   rtl

; [ 24-bit sum at 0,x *= Ot6RewardMulW / 16, clamped $ffffff ]
scale24:
        lda     a:$0000,x
        sta     OT6_SCR_SLOT2   ; value low word
        lda     a:$0001,x
        and     #$ff00
        xba
        sta     OT6_SCR_BIT     ; value high byte
        stz     OT6_SCR_IDX     ; product bits 0-15
        stz     OT6_SCR_COLS    ; product bits 16-31
        phx
        lda     f:Ot6RewardMulW
        and     #$00ff
        xba
        tay                     ; mult << 8: msb-first walker in y
        ldx     #$0008
@bit:   asl     OT6_SCR_IDX
        rol     OT6_SCR_COLS    ; product <<= 1 (32-bit)
        tya
        asl
        tay                     ; next multiplier bit into carry
        bcc     @next
        lda     OT6_SCR_IDX
        clc
        adc     OT6_SCR_SLOT2
        sta     OT6_SCR_IDX
        lda     OT6_SCR_COLS
        adc     OT6_SCR_BIT
        sta     OT6_SCR_COLS
@next:  dex
        bne     @bit
        ldx     #$0004
@shr:   lsr     OT6_SCR_COLS    ; /16 (32-bit shift right x4)
        ror     OT6_SCR_IDX
        dex
        bne     @shr
        plx
        lda     OT6_SCR_COLS
        cmp     #$0100
        bcc     @fit
        lda     #$00ff          ; clamp: the sums are 24-bit
        sta     OT6_SCR_COLS
        lda     #$ffff
        sta     OT6_SCR_IDX
@fit:   lda     OT6_SCR_IDX
        sta     a:$0000,x
        shorta
        lda     OT6_SCR_COLS
        sta     a:$0002,x       ; byte store: +3 is not ours to touch
        longa
        rts
.endproc

; ------------------------------------------------------------------------------

; [ chip shields on an elemental weakness hit ]

; called from the weak-element branch of CalcTargetDmg.
; a8, y = target, $11a1 = attack elements, preserves x/y. index width
; varies: the per-target damage loop runs i8 (CalcAttackEffect is .i8),
; so everything here is width-agnostic except the codex store, which
; pins i16 for its word-sized species load.

.proc Ot6Chip
        .a8
        tya                     ; entity offset, width-neutral test
        cmp     #$08
        bcc     done            ; characters have no shields
        lda     OT6_BROKEN_TICKS,y
        bne     done            ; already broken: no chip until recovery
        lda     $3be0,y
        and     $11a1
        pha                     ; matched weakness bits
        lda     OT6_REVEALED_ELEM,y
        ora     OT6_RVPEND_ELEM-8,y     ; bits already banked this action
        eor     #$ff                    ;   are not "new" either
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
merge:  pla                     ; bank the matched weaknesses as pending:
        ora     OT6_RVPEND_ELEM-8,y     ;   the on-screen reveal must land on
        sta     OT6_RVPEND_ELEM-8,y     ;   the damage frame, and this runs at
                                ;   damage calc, frames earlier.
                                ;   Ot6RevealCommit moves pending into
                                ;   OT6_REVEALED_ELEM (and every same-species
                                ;   slot) at the numeral.
        ; learn it forever: codex entry = everything known so far, pending
        ; included (seed merged the old codex bits in, so this is monotonic).
        ; species is a word: pin i16 for the load, since the caller's i8
        ; would truncate species >= $100 onto the wrong codex slot.
        ; entity offsets survive the rep: 8-bit index mode forces the
        ; high bytes to zero.
        php
        longi
        phx
        lda     OT6_RVPEND_ELEM-8,y
        ora     OT6_REVEALED_ELEM,y
        pha
        jsr     Ot6CodexActive
        longa
        txa
        clc
        adc     OT6_SPECIES-8,y
        tax
        shorta0
        pla
        sta     f:OT6_CODEX,x
        plx
        plp
        lda     OT6_SHIELD_CUR,y
        beq     done            ; shieldless monster
        dec     a
        sta     OT6_SHIELD_CUR,y
        bne     done
        lda     #OT6_BREAK_TICKS
        sta     OT6_BROKEN_TICKS,y         ; shields down: break
        lda     #$ff                       ; bank the flash as pending;
        sta     OT6_BRKTICK-8,y            ;   see Ot6BreakArm.  width-
                                           ;   agnostic (abs,y in both index
                                           ;   widths), like every other store
                                           ;   in this proc but the codex one
done:   rtl
.endproc

; ------------------------------------------------------------------------------

; [ every landed hit: weapon-class chip, then broken double ]

; replaces the bare broken-double jsl at the elemental join @0c1e, so it
; runs for every damaging hit against every target, including hits whose
; element was absorbed/nulled/forcefielded (the blade still lands) and
; hits with no element at all (most weapons). a8 (CalcTargetDmg pins it);
; the damage loop runs i8, so pin i16 here for the chip's species/codex
; indexing; entity offsets survive the rep, because 8-bit index mode forces
; the high bytes to zero. preserves x/y.

.proc Ot6HitJoin
        .a8
        php
        longi
        jsr     Ot6ClassChip
        jsr     Ot6ShieldedDmg  ; ot6: sturdiness while shields hold
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
;   - no vanilla x2 on a class-weak hit: the damage bonus for classes
;     is the break window itself (elemental weak x2 is vanilla's rule
;     and stays vanilla's alone)
;   - wound/petrify and heal-flagged hits never chip (elements cannot
;     reach their weak branch in those states, so this matches rather
;     than adds a rule; the one difference is undead drain-reversal,
;     which element chip allows, following vanilla, and class chip
;     does not)

.proc Ot6ClassChip
        .a8
        .i16
        tya                     ; entity offset, width-neutral test
        cmp     #$08
        bcc     done            ; characters have no shields
        lda     f:$7e0000+OT6_ATKCLASS
        beq     done            ; classless action: chips nothing
        bmi     done            ; null-break property: teaches nothing
        and     OT6_BP_CLASS,y         ; monster's class weaknesses
        beq     done            ; no match
        sta     OT6_SCR_BIT     ; the matched class bit (exactly one)
        lda     OT6_BROKEN_TICKS,y
        bne     done            ; already broken: no chip until recovery
        lda     $3ee4,y
        bit     #$c0
        bne     done            ; wound/petrify: the hit was theater
        lda     $f2             ; resolved spell flags3 (absorb/undead-drain
        lsr                     ;   reversals already folded in); only bit 0
        bcs     done            ; means heal.  $20 can't-dodge and others ride
                                ; the same byte, and gating on the whole byte
                                ; silenced every flagged skill's chip
        lda     OT6_BOOST_REVEALED,y
        ora     OT6_RVPEND_CLS-8,y      ; banked this action is not new
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
merge:  lda     OT6_SCR_BIT     ; bank the matched class as pending:
        ora     OT6_RVPEND_CLS-8,y      ;   committed to the revealed byte on
        sta     OT6_RVPEND_CLS-8,y      ;   the damage frame, like the elements
        ; learn it forever, like the elements (join already pinned i16)
        phx
        lda     OT6_RVPEND_CLS-8,y
        ora     OT6_BOOST_REVEALED,y
        pha
        jsr     Ot6CodexActive
        longa
        txa
        clc
        adc     OT6_SPECIES-8,y
        tax
        shorta0
        pla
        sta     f:OT6_CODEX_CLASS,x
        plx
        lda     OT6_SHIELD_CUR,y
        beq     done            ; shieldless monster
        dec     a
        sta     OT6_SHIELD_CUR,y
        bne     done
        lda     #OT6_BREAK_TICKS
        sta     OT6_BROKEN_TICKS,y         ; shields down: break
        lda     #$ff                       ; flash pending (see Ot6BreakArm)
        sta     OT6_BRKTICK-8,y
done:   rts
.endproc

; ------------------------------------------------------------------------------

; [ commit pending reveals on the damage frame: per-species, one frame ]
;
; the chips above run at damage calc, inside CalcAttackEffect's per-target
; loop; the damage the player sees lands when GfxCmd_0b allocates its
; numeral thread, hundreds of frames later.  so the chips bank into
; OT6_RVPEND_* and this walker moves pending into the revealed bytes:
;   - called from GfxCmd_0b's entry (C1 shim), the damage frame proper;
;   - and from Ot6ActionEnd, the backstop for numeral-less actions, so
;     pending never outlives the action that banked it.
; the codex is per-species, so the commit writes every same-species slot's
; revealed byte in the same pass, and all siblings' icons appear on one
; frame.
; absent slots are written too when their species matches: harmless (their
; hud lines are disabled) and cheaper than a presence test.
;
; a8/i16 assumed pinned by the caller (Ot6ActionEnd pins; the _ext wrapper
; pins for C1).  db=$7e.  preserves x/y.
.proc Ot6RevealCommit
        .a8
        .i16
        phb                     ; pin db=$7e: every cell below is absolute
        phx                     ;   (battle RAM + the shadow tail), and one
        phy                     ;   caller is the C1 script engine, whose DB
        lda     #$7e            ;   is not ours to assume.
        pha
        plb
        ldy     #$0000          ; source monster slot offset 0,2..10
@src:   lda     OT6_RVPEND_ELEM,y
        ora     OT6_RVPEND_CLS,y
        beq     @next           ; nothing pending for this slot
        ldx     #$0000          ; sibling slot offset
@sib:   longa
        lda     OT6_SPECIES,x
        cmp     OT6_SPECIES,y
        shorta                  ; plain SEP #$20; shorta0's `tdc` sets Z
                                ;   from D and would wipe the compare
        bne     @skip
        lda     OT6_RVPEND_ELEM,y
        ora     $3e91,x         ; revealed elements (OT6_REVEALED_ELEM + 8)
        sta     $3e91,x
        lda     OT6_RVPEND_CLS,y
        ora     $3ea5,x         ; revealed classes (OT6_BOOST_REVEALED + 8)
        sta     $3ea5,x
@skip:  inx
        inx
        cpx     #$000c
        bcc     @sib
        lda     #$00
        sta     OT6_RVPEND_ELEM,y
        sta     OT6_RVPEND_CLS,y
@next:  iny
        iny
        cpy     #$000c
        bcc     @src
        jsr     Ot6BreakArm     ; the break flash rides the same edge, and
                                ;   rides it from here rather than from a second
                                ;   call site so it inherits both of this proc's
                                ;   callers (Ot6RevealPoll's numeral
                                ;   frame, and Ot6ActionEnd's numeral-less
                                ;   backstop) without touching ot6_boost.asm
        ply
        plx
        plb
        rts
.endproc

; ------------------------------------------------------------------------------

; [ the break moment: fire every pending monster's break, sound it once ]
;
; The chips above empty the gauge inside CalcAttackEffect's per-target
; loop, at damage calc, well before the damage frame the player sees.
; The chips bank $ff in OT6_BRKTICK and this proc converts pending into a
; live flash on the damage frame.
;
; The cleave is not conditional on the flash.  Ot6BreakStart returns
; carry for "a break happened at this monster", which is a weaker
; condition than "the flash armed": on a break that also killed the
; monster the flash is refused (death owns the palette) but the sound
; still plays, panned to where the enemy is standing.
;
; The sound is once per pass, not once per slot: two monsters broken by
; the same action share one cleave, and a multi-hit action cannot
; double it either, because a chip only banks pending when
; OT6_BROKEN_TICKS is still zero, so hits 2..n of a combo find the
; target already broken and bank nothing.
;
; The sfx id $be is vanilla's Odin/Raiden cleave (btlgfx_main.asm:26049-
; 26055, the only site that plays it), queued by writing PlayAnimSfx's
; own four bytes (btlgfx_main.asm:3175-3182) rather than jsl-ing it,
; because PlayAnimSfx takes its pan in direct-page $10 and this proc
; does not own $10 in either of its contexts.  The pan is the broken
; monster's screen x, vanilla's own idiom for a monster-local sound (the
; death animation pans to w7e80c3 the same way, :22287-22294).
;
; a8/i16, db=$7e (Ot6RevealCommit pins it).  clobbers a/y.
.proc Ot6BreakArm
        .a8
        .i16
        lda     #$80
        pha                     ; $02,s: pan, centre until a slot really broke
        lda     #$00
        pha                     ; $01,s: did anything break this pass?
        ldy     #$0000          ; monster slot offset 0,2..10
@slot:  lda     OT6_BRKTICK,y
        cmp     #$ff
        bne     @next           ; idle, or already a live countdown
        jsr     Ot6BreakStart   ; y = slot offset; carry set = a break happened
        bcc     @next           ;   here (the flash may still have been
                                ;   refused on its own; the cleave is not
                                ;   conditional on owning the sprite)
        lda     $01,s
        bne     @next           ; the first broken slot owns the pan
        inc     a
        sta     $01,s
        lda     $80c3,y         ; w7e80c3: monster screen x (btlgfx_ram.inc:720,
        sta     $02,s           ;   used as a pan the same way at :22288)
@next:  iny
        iny
        cpy     #$000c
        bcc     @slot
        pla                     ; did anything break this pass?
        beq     @quiet
        pla                     ; pan: written only when a sound is queued,
        sta     $e9ea           ;   so a silent pass cannot overwrite a pan the
                                ;   animation engine queued this same frame
        lda     #OT6_BREAK_SFX
        sta     $e9e9           ; w7ee9e9: sound effect number
        lda     #$18
        sta     $e9e8           ; w7ee9e8: spc command $18 (play game sfx)
        lda     #$01
        sta     $e9ec           ; w7ee9ec: enable animation sound effect
        rts
@quiet: pla                     ; discard the unused pan
        rts
.endproc

; ------------------------------------------------------------------------------

; [ start one monster's break moment; y = monster slot offset ]
;
; The pending byte is consumed on every path, armed or not: a pending flash
; must never outlive the action that banked it (Ot6PipPending's rule).
;
; Two tiers.  A break is an event that happened at a place on the screen,
; and the cleave is sounded from here whatever the sprite is doing.  The
; white flash additionally has to own the sprite, and is refused on its
; own, without a message, when it cannot.
;
; Sounded, flash refused (this sprite is not ours to drive):
;   - the monster is wound/petrified ($3eec & $c2, the hud's own dead test);
;   - the breaking blow also killed it (hp is already zero by the numeral
;     frame, because damage lands at calc).  Death has its own 32-frame
;     animation which loads MonsterDeathPal into this palette slot and
;     repoints w7e80db at it for the whole fade (btlgfx_main.asm:22259-22266
;     and :22452-22458), so flashing here would paint the death fade white and
;     leave the sprite on whichever writer went last;
;   - the engine has already repointed the monster at palette 3 for an
;     animation of its own (AnimCmd_80_3b, :31329).  Same reason.
;
; Refused outright: the slot is not on the field ($3aa8 bit 0, the hud's own
; presence gate).  There is no monster and no screen position for a
; monster-local sound to come from, so nothing happens at all.
;
; a8/i16, db=$7e.  preserves y; clobbers a.
; out: carry set = a break happened here; sound it, panned to this monster.
.proc Ot6BreakStart
        .a8
        .i16
        lda     #$00
        sta     OT6_BRKTICK,y   ; pending consumed either way
        lda     $3aa8,y         ; monster present flags
        lsr
        bcc     @none           ; not on the field: no event to sound at all
        lda     $3eec,y         ; monster status 1
        bit     #$c2
        bne     @sound          ; wound/petrified
        lda     $3bfc,y         ; monster hp (lo/hi)
        ora     $3bfd,y
        beq     @sound          ; the breaking blow killed it: death owns the
                                ;   palette slot and the sprite byte
        lda     $80db,y         ; w7e80db: monster sprite data; bits 1-3 are the
        and     #$0e            ;   obj palette number, and vanilla only ever
        cmp     #$06            ;   assigns 0/1/2 to a monster (:4917-4921), so
        beq     @sound          ;   3 here means an animation owns the sprite
        sta     OT6_BRKPAL,y    ; bank the real palette bits for the hand-back
        lda     #OT6_BREAK_FLASH
        sta     OT6_BRKTICK,y
        sta     OT6_BRKLIVE     ; wake the painter (any nonzero will do; it
                                ;   recomputes the count as it walks)
        jsr     Ot6BreakPal
@sound: sec
        rts
@none:  clc
        rts
.endproc

; ------------------------------------------------------------------------------

; [ fill the engine's flash palette slot with white ]
;
; Obj palette 3 == w7e7e00::_11 == $7e7f60 (btlgfx_ram.inc:672 declares the
; array as 16 palettes of 32 bytes; the sprite drawer resolves a monster's
; palette number to w7e7e00::_8 + n*32 at btlgfx_main.asm:4294-4296).  It is
; the engine's own scratch for exactly this: flash_color_set writes it for the
; attacker flash (:23440) and MonsterDeathPal is loaded into it for the death
; fade (:22264).  Nothing else can be pointing at it, because monsters are only
; ever assigned palettes 0/1/2 (:4917-4921).
;
; The PPU update DMAs sprite palettes as one unconditional fixed $100-byte
; block from w7e7e00::_8 every frame (btlgfx_main.asm:1512-1518), so the whole
; effect (the palette and the w7e80db repoint the OAM builder reads) is WRAM
; writes that ride transfers the engine was making anyway: no extra vblank
; traffic.
;
; $7fff is white in BGR555; colour 0 stays transparent by the PPU's own rule,
; so the monster reads as a solid white cut-out.
;
; a8/i16, db=$7e.  preserves y; clobbers a.
.proc Ot6BreakPal
        .a8
        .i16
        phy
        longa
        lda     #$7fff
        ldy     #$0000
@fill:  sta     $7f60,y
        iny
        iny
        cpy     #$0020
        bcc     @fill
        shorta0
        ply
        rts
.endproc

; ------------------------------------------------------------------------------

; [ drive every live break flash, one main-loop frame ]
;
; Called from Ot6BgHud_ext: our own context in bank F0 with db=$7e, outside
; the C1 battle script engine (see Ot6RevealPoll's header for why this work
; stays out of that engine).
;
; Cadence: countdown 24..0, sprite on the flash palette while bit 2 of the
; counter is set, so 4 frames white, 4 frames normal, three times, ~0.4s.  That
; is vanilla's own flash rhythm (set_one_mon_pal waits 4 frames a phase,
; :23400-23410) with a third pulse, because a break is a bigger event than a
; monster taking its turn and has to be distinguishable from it.
;
; The hand-back is guarded: it only rewrites w7e80db if the palette bits are
; still the 3 this proc wrote.  If the engine took the sprite over mid-flash
; the proc leaves it alone rather than restoring stale bits over its work.
;
; It is not called at all when nothing is flashing; the gate lives inline at
; the call site rather than at the top of this proc, since the cycle margin
; on this path is tight (see OT6_BRKLIVE in ot6_memory.inc).  The walk
; recomputes OT6_BRKLIVE from what survives each tick, so a stale flag
; costs one walk and the byte needs no init clear.
;
; a8/i16, db=$7e (Ot6BgHud_ext's context).  clobbers a; preserves x/y.
.proc Ot6BreakFlash
        .a8
        .i16
        phy
        lda     #$00
        sta     OT6_BRKLIVE
        ldy     #$0000
@slot:  lda     OT6_BRKTICK,y
        beq     @next           ; idle
        cmp     #$ff
        beq     @next           ; pending: still waiting for the damage frame
        pha
        lda     $3aa8,y
        lsr
        bcc     @drop           ; slot emptied under us
        lda     $3eec,y
        bit     #$c2
        bne     @drop           ; died / petrified under us
        pla
        dec     a
        sta     OT6_BRKTICK,y
        beq     @off            ; the flash is over: hand the sprite back
        sta     OT6_BRKLIVE     ; still counting: keep the painter awake
                                ;   (nonzero, and it leaves n/z alone for the
                                ;   phase test below)
        and     #$04
        beq     @off
        lda     $80db,y         ; on: point the monster at the white palette
        and     #$f1
        ora     #$06
        sta     $80db,y
        bra     @next
@drop:  pla                     ; discard the counter and stop driving
        lda     #$00
        sta     OT6_BRKTICK,y
@off:   lda     $80db,y
        and     #$0e
        cmp     #$06
        bne     @next           ; not ours any more: do not touch it
        lda     $80db,y
        and     #$f1
        ora     OT6_BRKPAL,y
        sta     $80db,y
@next:  iny
        iny
        cpy     #$000c
        bcc     @slot
        ply
        rts
.endproc

; [ the damage-frame trigger: poll the numeral counter, main loop ]
;
; Why a poll and not a hook in GfxCmd_0b.  A hook at that command's own
; entry, executing inside the C1 battle-script engine, locks up the fight:
; the engine's re-entrancy and register/stack contract around its
; WaitFrame is not one this code can honor.  So the walk runs from our
; own context instead and stays out of the engine.
;
; The trigger is equivalent and observable: GfxCmd_0b's first act is to
; advance the numeral thread counter $632e, so a change in that byte since
; the last main-loop tick means a numeral was allocated, i.e. the damage frame.
; The hud builder already runs every main-loop frame in bank F0 with DB=$7e,
; which is the context the walk wants.  Cost: at most one frame later than
; a hook would have been.
;
; the shadow byte is not init-cleared (it sits past InitBP's clear); a stale
; value costs one spurious commit at battle start, which finds pending empty
; (Ot6SeedShields zeroes it per slot) and does nothing.
; a8/i16, db=$7e (Ot6BgHud_ext's own context).  preserves x/y.
; out: carry set if this tick saw a numeral.  The counter can only be
; consumed once, so the edge is reported rather than duplicated into a
; second last-seen byte, and the one caller (Ot6BgHud) fans it out.
.proc Ot6RevealPoll
        .a8
        .i16
        lda     f:$7e0000+$632e         ; damage-numeral thread counter
        cmp     f:$7e0000+OT6_NUMCTR
        beq     @done                   ; no numeral since last tick
        sta     f:$7e0000+OT6_NUMCTR
        jsr     Ot6RevealCommit
        sec                             ; the numeral frame, reported
        rts
@done:  clc
        rts
.endproc

; ------------------------------------------------------------------------------

; [ double damage against a broken target ]

; the tail of Ot6HitJoin (the join of the elemental damage block, i.e.
; every hit). a8, y = target, $f0 = 16-bit damage, $f2 = resolved spell
; flags3 (bit 0 = this hit heals, absorb/undead-drain reversals folded
; in); width-agnostic on the index side (the damage loop runs i8).
; plain drains (bit 1, bit 0 clear) do double: vanilla's elemental-weak
; x2 applies to drains too, and the break window follows vanilla's rule.

.proc Ot6BrokenDmg
        .a8
        tya                     ; entity offset, width-neutral test
        cmp     #$08
        bcc     done
        lda     OT6_BROKEN_TICKS,y
        beq     done            ; not broken
        lda     $f2             ; heal bit only; the whole-byte gate let
        lsr                     ;   $20 can't-dodge block the double for
        bcs     done            ;   every beam and skill that carries it
        lda     $f1
        bmi     done            ; avoid 16-bit overflow (matches vanilla)
        asl     $f0
        rol     $f1
done:   rtl
.endproc

; ------------------------------------------------------------------------------

; [ shielded resistance: damage attenuates while shields hold ]

; while a monster has shields remaining and is not broken, every damaging
; hit it takes is multiplied by Ot6ShieldedMulW/16. one global knob, no
; per-species column. the resulting ordering is the design:
;   off-weakness hit        x0.5        (reads as wasted)
;   element-weak hit        ~x1         (vanilla weak x2, then x0.5;
;                                        the chip is the real payoff)
;   broken                  x2+         (Ot6BrokenDmg, shields down)
; gates, all by construction:
;   - OT6_SHIELD_CUR nonzero = shields up and not broken. shieldless species
;     (authored 0 rows: whelk shell, tritoch, formula 0s) and broken
;     monsters both sit at 0 and pass through untouched; shields==0
;     means no shield system rather than "attenuate"
;   - the breaking hit itself is not attenuated: both chip procs run
;     before this tail, so its read of OT6_SHIELD_CUR already sees 0 with the
;     broken timer up, and Ot6BrokenDmg doubles it instead
;   - resolved heals pass through (the $f2 bit-0 discipline, same as
;     the chip gates and the broken double: absorbs and undead drain
;     reversals must never shrink)
; called from Ot6HitJoin between the class chip and the broken double.
; a8/i16 (the join pinned i16), y = target, $f0 = 16-bit damage,
; db = $7e. preserves x/y; the 24-bit shift-add reuses the OT6_SCR
; battle scratch (Ot6ClassChip's use of it this hit is already dead).

Ot6ShieldedMulW:
        .word   $0008           ; damage x 8/16 (0.5x) while shielded;
                                ;   $10 = identity (vanilla arithmetic).
                                ;   makes the damage-per-BP ladder a clean
                                ;   doubling (broken:weak:unweak = 4:2:1).
                                ;   a formula species with no class row
                                ;   (@formula clears OT6_BP_CLASS) chips
                                ;   nothing off fight/tools regardless of
                                ;   this constant; that is Ot6ShieldTbl
                                ;   authoring, not a damage dial.

.proc Ot6ShieldedDmg
        .a8
        .i16
        tya                     ; entity offset, width-neutral test
        cmp     #$08
        bcc     done            ; characters carry no shields
        lda     OT6_SHIELD_CUR,y
        beq     done            ; 0 = broken or shieldless: no attenuation
        lda     $f2             ; resolved heal bit only (chip-gate rule)
        lsr
        bcs     done
        lda     f:Ot6ShieldedMulW
        cmp     #$10
        beq     done            ; identity: vanilla arithmetic
        phx
        longa
        lda     $f0             ; 16-bit damage
        sta     OT6_SCR_SLOT2   ; multiplicand
        lda     f:Ot6ShieldedMulW
        and     #$00ff
        xba
        sta     OT6_SCR_BIT     ; mult << 8: msb-first bit walker
        clr_a
        sta     OT6_SCR_COLS    ; product bits 16-23
        ot6_mul16ths            ; the clamp bites here: a mult past $10 can
                                ;   carry 16-bit damage out of 16 bits
        sta     $f0
        shorta0
        plx
done:   rts
.endproc

; ------------------------------------------------------------------------------

; [ note the executing attack's weapon class, at load time ]

; three loaders cover every damage path, and each always stores, using zero
; for the classless, so a stale class cannot leak between attacks:
;   Ot6SkillClass   LoadMagicProp: every spell-record attack (magic,
;                   skills, lores, dances, espers, enemy attacks, the
;                   $ee "battle" record that fronts fight/steal/jump,
;                   and the dot-tick pseudo-attacks)
;   Ot6WeaponClass  _magicpunch: fight/capture/jump weapon swings, per
;                   hand per swing (the weapon sets Fight's class)
;   Ot6ItemClass    CalcItemEffect: items, tools, thrown weapons
; the chip itself reads OT6_ATKCLASS per target in Ot6ClassChip.

; a = ability id (preserved). caller a8; index width varies, so pin it.

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
; there (MonsterProp+26) rather than an item, so their swings carry no class.
; (raged gau inherits the rage monster's graphics code into both hands
; through SetRage, so his raged fights can read a junk class: a known
; defect until rage is retired for capture. plain gau punches bludgeon, $ff.)

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
        lda     OT6_BROKEN_TICKS,x         ; broken: skip turn (z clear if nonzero)
done:   rtl
.endproc

; ------------------------------------------------------------------------------

; [ may this entity act right now? ]

; Ot6Gate above answers at queue time, which is the only place vanilla asks,
; and that is the hole.  Nothing between a queue entry and the turn re-checks
; anything: the action queue drains straight into ExecAction
; (battle_main.asm:150-159), the counterattack queue straight into ExecRetal
; (:103-112), and only QuetzEffect (:1814-1822) ever purges an entry.  So a
; turn queued before a monster breaks can still execute or counterattack.
;
; This asks the same question at execution time, from one site: CheckRetal
; (battle_main.asm:12762), +6 bytes.  A Broken monster creates no
; counterattack, matching the ruling that a Broken enemy loses its counters
; along with its turns.
;
; One site rather than two: the $C2 action path (ExecAction's pre-dispatch
; check) has under 18 cycles of slack, not enough margin for a second hook
; there without costing a missed vblank per battle-loop iteration.
;
; What one site leaves open.  The action queue is still ungated at
; execution, so a turn queued before the break lands drains into
; ExecAction (battle_main.asm:150-159) and runs.  ExecAction also runs the
; monster's AI script before any dispatch -- the `cmp #$1f` arm calls
; ExecMonsterAction (:238) and loops back to @0100 -- so that turn's script
; side effects (e.g. kill_monsters/show_monsters tags) land regardless of
; whether a command dispatches.  Closing that needs the queue entry purged
; at break time (QuetzEffect's walk, battle_main.asm:1814-1822, spends bank
; $F0 cycles rather than $C2 ones); gating earlier inside ExecAction is not
; an option either, since @01a6's `lda $32cc,x / inc / bne @01d5` (:288-290)
; would re-enter ExecAction forever on a command list that never got
; consumed.
;
; Characters can never trip it.  Ot6Chip refuses entity < $08
; (ot6_break.asm:843-845) and InitBattle's $3a20-$3ed3 clear
; (battle_main.asm:6132-6133) zeroes the character rows of
; OT6_BROKEN_TICKS, so their byte is always $00.
;
; a8 is required: under a 16-bit accumulator `lda OT6_BROKEN_TICKS,x` would
; pull the word $3e88/$3e89, broken ticks together with the revealed-element
; mask, and any revealed weakness would read as "broken".  This proc cannot
; php/plp its way out of caring, because plp would restore the very carry
; it exists to return.  The call site (CheckRetal) opens 8-bit
; (`stz $b8 / stz $b9`, battle_main.asm:12737-12738).
;
; x = entity.  clobbers a; preserves x/y.
; out: carry set = may act (present and not broken); carry clear = skip.

.proc Ot6MayAct
        .a8
        lda     OT6_BROKEN_TICKS,x
        bne     broken
        lda     $3aa0,x
        lsr                     ; carry = $3aa0.0, the presence bit
        rtl
broken: clc
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ tick the broken timer, restore shields on recovery ]

; called from DecCounters once per entity status-tick
; a8/i16, x = entity, a is free (caller reloads)

.proc Ot6Tick
        .a8
        .i16
        lda     OT6_BROKEN_TICKS,x
        beq     done
        dec     OT6_BROKEN_TICKS,x
        bne     done
        lda     OT6_SHIELD_MAX,x         ; recovered: shields back to max
        sta     OT6_SHIELD_CUR,x         ; (revealed weaknesses stay revealed)
done:   rtl
.endproc
