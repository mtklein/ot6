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
        shorta0                 ; a=0 (clr_a); formula species: no class weak
        sta     $3e9c,y         ; clear the class-weak mask. like the reveal
                                ;   masks below it must not survive a Cmd_20
                                ;   reload (no InitBattle clear) or the hud
                                ;   draws PHANTOM class-weakness cells for a
                                ;   fresh formula monster. the authored @hit
                                ;   path OVERWRITES $3e9c (store above), so it
                                ;   self-clears; the formula path never wrote
                                ;   it and must zero it here.
        lda     OT6_SCR_BIT     ; level
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
        ; per-monster battle-start state the seed must not inherit on the
        ; Cmd_20 scene-change reload (multi-phase bosses, reinforcements, the
        ; whelk head's retract cycle): it re-runs the seed via InitMonsters
        ; with NO InitBattle $3a20-$3ed3 clear. on the FRESH path InitBattle
        ; already zeroes these (write-trace confirms: its clear stores $00 here
        ; before the seed runs), so this is belt-and-suspenders there and
        ; load-bearing only on reload. monster path only (y >= $08 past @on):
        ; the character rows are never touched. with 32k sram the codex
        ; re-merge below restores genuinely-earned reveals (chips write them
        ; through), so a same-monster retract cycle keeps its reveals.
        lda     #$00
        sta     $3e88,y         ; broken timer: a stale nonzero reload-starts
                                ;   the monster BROKEN (Ot6Gate skips its turn,
                                ;   2x damage, the hud shield cell draws the
                                ;   broken glyph). the seed otherwise never
                                ;   writes it, so a reload inherits the slot's
                                ;   prior occupant.
        sta     $3e89,y         ; revealed weakness elements: stale bits, OR'd
                                ;   with the codex below, draw weaknesses as
                                ;   revealed from battle start instead of '?'
                                ;   (the hud '?'-gate reads $3e89/$3e9d)
        sta     $3e9d,y         ; revealed classes (monster half)
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
        jsr     Ot6ElemAdd      ; ot6: element adds (m6 weakness data)
        jsr     Ot6HpScale      ; ot6: difficulty transform (trash hp)
        plx
done:   rtl
.endproc

; ------------------------------------------------------------------------------

; [ element adds: widen a species' weak-element byte at monster seed time ]

; enemy identity stays vanilla in ROM; an element ADD is a runtime
; transform like Ot6HpScale, applied one hook later than the load: the
; mask is OR'd into the loaded weak byte $3be0,y (LoadRageProp stores it
; from MonsterProp+25 immediately before the seed hook), so the chip
; path, vanilla's weak x2 damage, and the hud weakness slots all read
; one truth. re-loads (retract cycles, scene changes) re-apply the OR:
; idempotent by construction.
;
; the whelk head ($134) gains fire: the boss tutorial's designed line
; -- three fire beams and a TekMissile, broken inside one head-present
; phase -- needs four chippable hits, and the head has no vanilla fire
; weak (measurement #2 called this add load-bearing m6 data). vargas
; ($103) gains holy: bosses-wob.md's vargas entry reads "poison, holy +
; bludgeoning", and vanilla gives him poison only (monster_prop.dat +25
; = $08) -- holy is the chip sabin's arrival is supposed to switch on,
; and aurabolt already carries it ($5e element byte = $20 in vanilla
; spell data), so this row is the whole remaining distance. proven at
; runtime by battle_vargas.lua.
;
; the v0.3 arc adds six more. four of them are the ARMOR LINE, and they
; exist to make one piece of dialog true: the narshe school's rung-2
; seed promises "their armored machines shrug off blade and fire alike
; ... every armor fears one right tool" (narshe-school.md:119-121), and
; the tool is edgar's bio blaster (item $a4 -> attack $7d, element $08
; poison -- battle_main.asm:6577). the seed was shipped before the
; enemies it describes could answer it. decoded fresh from
; monster_prop.dat at species*32 +$19 (weak; the offset is vanilla's own
; -- battle_main.asm:7517 loads MonsterProp+25), each row keeping every
; vanilla bit and adding poison:
;
;   $042 m-tekarmor  +$0859  vanilla $04 bolt        -> $0c
;   $09f heavyarmor  +$13f9  vanilla $84 bolt|water  -> $8c
;   $14e leader      +$29d9  vanilla $00 none        -> $08
;   $14f grunt       +$29f9  vanilla $00 none        -> $08
;
; note the two that read $00: leader and grunt had NO weakness of any
; kind, so the school's line was not merely unfulfilled for them, it was
; false -- an unbreakable gauge on the imperial camp's own foot soldiers
; (battle 13/14 -> formations 59/60/63, event_main.asm:41221 etc).
;
; and two boss rows bosses-wob.md already specified but m6 never entered:
;
;   $14a kefka       +$2959  vanilla $00 none        -> $09 poison|fire
;   $104 tunnelarmor +$2099  vanilla $84 bolt|water  -> $86 (+ice)
;
; $14a is MONSTER::KEFKA_NARSHE and nothing else -- the imperial camp
; gags load no monster record at all (Ot6ShieldTbl's block comment has
; the full decode). he is the v0.3 stop line, and vanilla left him with
; no weakness whatsoever. tunnelarmor's ice is celes's join spell buying
; a socket: vanilla's bolt and water are both dead keys for the
; locke+celes duo, so without the add the fight's only element chip is
; nothing at all (bosses-wob.md "5. TunnelArmor").
;
; ALL SIX were checked against +$17 (absorb) and +$18 (null) before
; authoring; every one reads $00/$00, so no row here puts a chip trigger
; on an absorber. that check is not ceremony -- it is the exact error
; bosses-wob.md caught twice in draft (nerapa listed fire, which it
; absorbs; the cranes' absorb pair was read as their weak pair).
;
; deliberately NOT authored, so the next author does not re-litigate:
;   - trooper ($065, +$0cb9 = $08) and rider ($03f, +$07f9 = $09) are
;     already poison-weak in VANILLA. the narshe defense waves need
;     nothing; formation 88 is trooper+heavyarmor, so with the armor row
;     above the whole wave answers to the one tool. an add here would be
;     a no-op ora that lies about who authored it.
;   - specter ($156) ABSORBS poison (+$2ad7 = $08) and is fire|holy weak
;     (+$2ad9 = $21). it is a monster-in-a-box on the phantom train (map
;     153, treasure 114 -> event battle group 34 -> formation 476) --
;     the same train whose boss also absorbs poison. the train is a
;     poison DEAD ZONE, boss and chest alike; vanilla's fire|holy are
;     live keys there (shadow's fire skean, sabin's aurabolt) so it
;     needs no add, and the one element this arc is about would heal it.
;   - siegfried ($131) has no vanilla weakness, absorb or null ($00 at
;     +$2637/+$2638/+$2639). the phantom train gag who flees (battle 109,
;     event_main.asm:65247) and bosses-wob.md gives him no block. the
;     formula's 2 shields stand: unlisted species are meant to fall
;     through, and inventing a key for a fight the player is supposed to
;     walk away from is spec no design doc asked for.
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
        .byte   $01, $00        ; whelk head: + fire (the tutorial probe)
        .word   $0103
        .byte   $20, $00        ; vargas: + holy (sabin's aurabolt)
        ; the armor line -- the narshe school's rung-2 seed made true.
        ; one tool (bio blaster, poison) opens every armored machine.
        .word   $0042
        .byte   $08, $00        ; m-tekarmor: + poison (keeps bolt)
        .word   $009f
        .byte   $08, $00        ; heavyarmor: + poison (keeps bolt|water)
        .word   $014e
        .byte   $08, $00        ; leader: + poison (vanilla had none)
        .word   $014f
        .byte   $08, $00        ; grunt: + poison (vanilla had none)
        ; the arc's stop line, and the scenario boss that had no key
        .word   $014a
        .byte   $09, $00        ; kefka (narshe defense): + poison|fire
        .word   $0104
        .byte   $02, $00        ; tunnelarmor: + ice (keeps bolt|water)
        .word   $ffff

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
;
; measurement #5 stood the multiplier DOWN to 1x. it and shielded
; resistance both lengthen fights, and stacking 2x hp with the 0.5x
; resistance overshot the snappy-fight band (baseline mines TTK ~6 real
; actions, a slog). the co-tune sweep found 1x hp x 0.5x resistance is
; the sweet spot: shielded resistance now carries the "fights are
; longer" load (it halves off-weakness damage, so the loop-IGNORER's
; fight runs ~2x longer — matching measurement #4's pace-knob regime —
; while a weakness-exploiting player stays vanilla-fast). the multiplier
; had done that job by inflating EVERY player's hp bar equally, which
; did not reward the loop; resistance does. band1 tracks band0 to 1x so
; the global danger/reward knobs stay conserved across bands (a mixed
; 1x/2x table would put mid-trash fights at ~4x length). band1 mid-trash
; stays unmeasured — parity extrapolation pending stretch fixtures.
Ot6HpMulTbl:
        .byte   $10             ; $000-$05f: 1x — swept (measurement #5:
                                ;   resistance carries the lengthening)
        .byte   $10             ; $060-$0bf: 1x — tracks band0 (parity;
                                ;   mid trash unmeasured, fixtures pending)
        .byte   $10             ; $0c0-$0ff: 1x — wor, unmeasured
        .byte   $10             ; $100+ (keep 1x: see doom gaze note)

; ------------------------------------------------------------------------------

; [ encounter-rate knob + reward conservation ]

; fights at 2x hp run ~2x longer (measurement #3: 1456f vs 744f), so the
; per-step encounter danger increment is scaled DOWN and random-battle
; rewards are scaled UP by the inverse: combat time per step and xp/gil
; per step both track vanilla. the two knobs are 16ths and their product
; is pinned at $100 (1.0) by the conservation rule — change them as a
; pair or the level/shop pacing drifts.

Ot6DangerMulW:
        .word   $0008           ; per-step danger increment x 8/16 (0.5x)
Ot6RewardMulW:
        .word   $0020           ; random-battle xp+gil x 32/16 (2x)

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
; never touches $3ecc-$3ed3 — grepped).

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
        ldx     #$0008
@bit:   asl                     ; product low <<= 1
        rol     OT6_SCR_COLS
        asl     OT6_SCR_BIT     ; next multiplier bit into carry
        bcc     @next
        clc
        adc     OT6_SCR_SLOT2
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
        beq     :+
        lda     #$ffff          ; saturate; the caller clamps the sum anyway
:       clc
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
        lda     #$00ff          ; clamp: 24-bit sums, 24-bit truth
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

; [ shielded resistance: damage attenuates while shields hold ]

; the sturdiness half of the break loop (measurement #5): while a monster
; has shields remaining and is not broken, every damaging hit it takes is
; multiplied by Ot6ShieldedMulW/16. one global knob, no per-species
; column until a sweep demands one. the emergent ordering IS the design:
;   off-weakness hit        x0.5        (feels wasted)
;   element-weak hit        ~x1         (vanilla weak x2, then x0.5 —
;                                        the chip is the real payoff)
;   broken                  x2+         (Ot6BrokenDmg, shields down)
; gates, all by construction:
;   - $3e38 nonzero = shields up and not broken. shieldless species
;     (authored 0 rows: whelk shell, tritoch, formula 0s) and broken
;     monsters both sit at 0 and pass through untouched — shields==0
;     means NO shield system, never "attenuate"
;   - the breaking hit itself is NOT attenuated: both chip procs run
;     before this tail, so its read of $3e38 already sees 0 with the
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
                                ;   measurement #5 FINALIZED 0.5x: it makes
                                ;   the damage-per-BP ladder a clean doubling
                                ;   (broken:weak:unweak = 4:2:1), so boosting
                                ;   to break and hitting the weakness both
                                ;   pay and boosting into shielded-unweak is
                                ;   visibly the worst return. 0.75x/1x flatten
                                ;   the ladder (at 1x a weakness hit ties a
                                ;   broken one — no reason to break).
                                ;   measurement #7 RE-SWEPT it under a
                                ;   playtest that read as "the loop doesn't
                                ;   matter" (1x/0.5x/0.375x/0.25x/0.1875x/
                                ;   0.125x x 4 policies x 2 pools) and kept
                                ;   0.5x: on the mt kolts pool, mashing WIPES
                                ;   3 of 6 encounters here while engaging the
                                ;   loop wins 6/6 and takes 40% less damage,
                                ;   so lowering it only deepens a hole the
                                ;   playtester already fell into. the thing
                                ;   that reads as "the loop doesn't matter"
                                ;   on EARLY trash is not this constant —
                                ;   it's that formula species carry no class
                                ;   weakness (@formula clears $3e9c), so
                                ;   fight/tools chip nothing and the break
                                ;   never fires. that is Ot6ShieldTbl
                                ;   authoring, not a damage dial.

.proc Ot6ShieldedDmg
        .a8
        .i16
        tya                     ; entity offset, width-neutral test
        cmp     #$08
        bcc     done            ; characters carry no shields
        lda     $3e38,y
        beq     done            ; 0 = broken or shieldless: no attenuation
        lda     $f2             ; resolved heal bit ONLY (chip-gate rule)
        lsr
        bcs     done
        lda     f:Ot6ShieldedMulW
        cmp     #$10
        beq     done            ; identity: vanilla arithmetic, exactly
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
        lda     #$ffff          ; clamp: a mult past $10 could overflow
@fits:  sta     $f0
        shorta0
        plx
done:   rts
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
; the upload is split into three ~128-byte slices so the nmi flush can
; re-lay the font one slice per vblank after a battle dialogue (the
; whole 384 bytes as PIO measured ~23 scanlines — more than a vblank).
; this entry point runs ALL slices back to back: it is only called in
; forced blank (battle init), where budget is unlimited.
;
; (was six slices: three more uploaded the over-character boost-mark OBJ
;  tiles, retired because they sat in vanilla's damage-numeral vram —
;  see the block comment where Ot6BoostMarksNmi_ext used to live.)

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

; element index -> tilemap palette bits (palette << 2); indices 8-11 are
; the four weapon classes (Ot6ElemGlyphFor's class fallback): menu-white,
; exactly how the same icons render as item-name leading glyphs
Ot6ElemPalTbl:
        .byte   7 << 2          ; fire: red
        .byte   3 << 2          ; ice: blue
        .byte   2 << 2          ; lightning: yellow
        .byte   6 << 2          ; poison: green
        .byte   0 << 2          ; wind: white
        .byte   2 << 2          ; holy: yellow (star shape vs bolt zigzag)
        .byte   1 << 2          ; earth: gray
        .byte   3 << 2          ; water: blue (wave shape vs ice crystal)
        .byte   0 << 2          ; slash: white
        .byte   0 << 2          ; pierce: white
        .byte   0 << 2          ; bludgeon: white
        .byte   0 << 2          ; special ¤: white

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

; [ class icon after a tool name in the battle Tools list ]

; tail of ListTextCmd_0e, the item-name drawer every battle item list
; shares. only the TOOLS window decorates ($7bc2 holds menu state $2e
; for every row it stages): item/throw/equip rows already wear a
; weapon's class as the leading name icon, and a second copy there
; would be noise — but tools keep their vanilla wrench icons ✦, so the
; class rides after the name, exactly where abilities show theirs.
; the icon replaces the name field's trailing blank (the field is
; always fully rewritten by the name loop, so the column can never go
; stale); a full 13-char name has no blank and keeps all its letters —
; autocrossbow, by the same rule that trims 10-char ability names in
; Ot6AbilityPad. classless tools ($00) and null-break rows draw
; nothing. a8/i16, db=$7e, $2c = the item id just named, y = list
; column past the name, b = tile attribute (preserved).

.proc Ot6ToolListIcon_ext
        .a8
        .i16
        xba
        pha                     ; stash the tile attr living in b
        xba
        lda     a:$7bc2         ; battle menu state under update
        cmp     #$2e            ; $2e = the tools window staging its rows
        bne     @out
        phx
        lda     $2c             ; the item id the row just named
        longa
        and     #$00ff
        tax
        shorta0
        lda     f:Ot6WeapClassTbl,x
        plx
        cmp     #$00            ; RETEST. plx sets n/z from the value it
                                ; PULLED, so the two guards below were reading
                                ; the caller's restored x — never the class
                                ; byte. x is ListTextCmd_0e's ItemName cursor
                                ; (id*13 + 13), nonzero and positive for every
                                ; item, so both guards fell through on a
                                ; CLASSLESS tool and @bit spun on a zero
                                ; OT6_SCR_BIT forever — a hard lock, measured
                                ; at $F0:057D with the battle nmi's $98
                                ; frozen. see battle_vargas.lua proof 3.
        beq     @out            ; classless tool: nothing to teach
        bmi     @out            ; null-break: teaches nothing, shows nothing
        sta     OT6_SCR_BIT
        phx
        ldx     #$0000
@bit:   lsr     OT6_SCR_BIT
        bcs     @glyph
        inx
        bra     @bit
@glyph: lda     f:Ot6ClassGlyphTbl,x
        plx
        sta     OT6_SCR_BIT     ; the class glyph
        dey
        dey                     ; back onto the name's last column
        lda     ($53),y
        cmp     #$ff
        bne     @full           ; 13-char name: no room for an icon
        pla                     ; the caller's attr ...
        xba                     ; ... into b for the 16-bit store
        lda     OT6_SCR_BIT
        longa
        sta     ($53),y         ; glyph | attr<<8 (replicates DrawListLetter)
        lda     $55
        sta     ($51),y
        shorta                  ; b holds the attr; caller reloads per char
        iny
        iny
        rtl
@full:  iny
        iny
@out:   pla
        xba                     ; restore b for the caller
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ element glyph for an ability — or its weapon-class glyph ]

; a = ability id (0-255) -> a = element icon glyph, or the ability's
; CLASS icon glyph when it has no element (Ot6SkillClassTbl: physical
; skills wear their class exactly where spells wear their element —
; TekMissile shows pierce in the magitek list, Pummel bludgeon, quadra
; slam slash), or $ff for the classless-and-elementless rest. first set
; bit wins on both axes; an element always beats the class (the design:
; "consult the class when the ability has no element"). null-break rows
; would advertise a class they never chip, so bit 7 hides the icon too.
; OT6_SCR_COLS = palette index: 0-7 element hues, 8-11 the class rows.
; preserves x/y.

.proc Ot6ElemGlyphFor
        .a8
        .i16
        phx
        pha                     ; the ability id, for the class fallback
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
        beq     @class
        ldx     #$0000
@bit:   lsr
        bcs     @hit
        inx
        bra     @bit
@hit:   txa
        sta     OT6_SCR_COLS    ; element index, for palette selection
        pla                     ; (discard the stashed id)
        lda     f:Ot6ElemGlyphTbl,x
        plx
        rts
@class: ; elementless: a physical skill's class carries the icon
        ldx     #$0000
@scan:  lda     f:Ot6SkillClassTbl,x
        cmp     #$ff
        beq     @none           ; end of table: classless ability
        cmp     $01,s
        beq     @found
        inx
        inx
        bra     @scan
@found: lda     f:Ot6SkillClassTbl+1,x
        bmi     @none           ; null-break: teaches nothing, shows nothing
        ldx     #$0000
@cbit:  lsr
        bcs     @cidx
        inx
        bra     @cbit
@cidx:  txa
        clc
        adc     #$08
        sta     OT6_SCR_COLS    ; palette index 8-11: the class rows
        pla                     ; (discard the stashed id)
        lda     f:Ot6ClassGlyphTbl,x
        plx
        rts
@none:  pla                     ; (discard the stashed id)
        lda     #$ff
        plx
        rts
.endproc

; class bit index (slash 0 .. special 3) -> small font glyph. these four
; cells ship IN the vanilla small font (they are the item icons the m3
; weapon renames lean on), so unlike the element icons they need no
; upload: every battle text system and the bg3 field map index the same
; $5800 font tiles.
Ot6ClassGlyphTbl:
        .byte   $d9             ; slash: the sword icon
        .byte   $da             ; pierce: the spear icon
        .byte   $dc             ; bludgeon: the staff icon
        .byte   $df             ; special ¤: the sparkle icon

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
        cpx     #$0054          ; 84 = the six shadow lines
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
                                ;   (C witness + random-encounter flags)
                                ;   must survive init (see the strip's
                                ;   block comment at OT6_CWITNESS)
        ; (removed: an 84-byte clear loop over OT6_HUDCOPY, a retired
        ;  feature's buffer. $57de is inside vanilla's `ram_res w7e57d5,
        ;  128`, so the loop was zeroing vanilla's name/banner scratch at
        ;  every battle init for nothing. Nothing reads OT6_HUDCOPY.)
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
;     Ot6Boost's `cmp $3e9c` would then happily let her spend.
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
        lda     $3e9c,y
        cmp     #$05
        bcs     done            ; the bank cap holds; an absorb never wraps
        inc
        sta     $3e9c,y
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

; [ boost picks the bushido tech — the charge gauge, deleted ]

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
; the ladder is kits.md's BP column: fang 0 · sky/tiger 1 · flurry/dragon
; 2 · eclipse/tempest 3. eight techs do not fit four boost levels, so a
; band holds up to three and the table names each band's TOP tech; the
; ceiling below — vanilla's own $2020, techs known - 1, the same value that
; capped the bar — then drops it to the best one cyan has actually learned.
; a band's expression therefore UPGRADES as he levels, which is the spell
; fold's grammar one rung up: fire is fire until a boost makes it fira, and
; the 1-bp band is sky until level 12 makes it tiger. the cost of that
; choice, stated plainly: the lower tech of each band is transitional (sky
; reachable L6-11, flurry L15-23, eclipse L34-43). flurry going quiet at 24
; costs the multi-hit shredder DESIGN.md names by name, until tempest
; restores that role at 44. the bands are DATA precisely so playtest can
; re-cut them without touching code.
;
; oblivion (tech 8) is deliberately NOT in the ladder. kits.md prices it at
; 3 bp "target must be Broken", and that gate cannot be read from here:
; this runs at command-latch time and swdtech is in RetargetCmdTbl
; (battle_main.asm:12818), so the target does not exist yet. shipping it
; anyway would both skip its own gate and retire eclipse and tempest, so
; the 3-bp band tops out at tempest until the divine pass (terra's trance,
; summon-once-per-battle) wires target-time gates. cyan learns oblivion off
; the phantom train, far past the rung-3 gate this work unblocks.
;
; bp is READ, never written: the spend is whatever Ot6Boost banked in
; $3e9d, so Ot6ActionEnd consumes it and skips that turn's regen exactly as
; for any other action, and the <=3 / never-past-bp caps stay Ot6Boost's
; alone. bp the ladder cannot spend (three points at level 1 still buys
; fang) is spent, not refunded — the same deal a mage takes when a third
; point on fire buys nothing past firaga.
;
; entry: from UpdateMenuState_37 — db=$7e, d=0, a8/i16, y=0 (the bar draw
; downstream indexes w7e7a73,y with it). returns a = the chosen level, as
; the vanilla block it replaces did. clobbers x.

.proc Ot6BushidoTier
        .a8
        .i16
        lda     $62ca           ; active character slot
        longa
        and     #$0003
        asl
        tax                     ; -> entity offset
        shorta0
        lda     $3e9d,x         ; pending boost
        cmp     #$04
        bcc     :+
        lda     #$03            ; (defensive: Ot6Boost already caps at 3)
:       longa
        and     #$00ff
        tax
        shorta0
        lda     f:Ot6BushidoTierTbl,x
        longa
        and     #$00ff
        pha                     ; the band's top tech, parked on the STACK.
        shorta0                 ;   the two scratch bytes in reach are both
                                ;   somebody's — $36 is btlgfx's (and only
                                ;   the display call site rewrites it right
                                ;   after us; the latch site does not), and
                                ;   OT6_SCR_BIT is the hud builder's. the
                                ;   stack owes nobody and survives an nmi.
        ldx     $2020           ; techs known - 1. a WORD (InitSkills stores
                                ;   it with stx, battle_main.asm:14495), and
                                ;   $ffff on every save before cyan joins —
                                ;   which our own test fixture is.
        cpx     #$0008
        bcc     :+
        ldx     #$0000          ; nothing learned: fang is all there is
:       txa                     ; ceiling, 0-7
        cmp     $01,s           ; ... against the band top (the pushed word's
        bcc     :+              ;   low byte). below it: the ceiling IS the
        lda     $01,s           ;   level; else the band top is
:       plx                     ; drop the parked word (x is dead here)
        pha
        asl5                    ; level * 32 — the counter value vanilla's
        sta     $7b82           ;   bar drew, so w7e7b82 still feeds the
        pla                     ;   latch, the fill, and the numerals
        rtl
.endproc

; bushido tier ladder: boost level -> that band's top tech, 0-based as the
; swdtech window numbers them (+$55 downstream makes the attack id).
Ot6BushidoTierTbl:
        .byte   $00             ; 0 bp: fang
        .byte   $02             ; 1 bp: tiger   (sky below L12)
        .byte   $04             ; 2 bp: dragon  (flurry below L24)
        .byte   $06             ; 3 bp: tempest (eclipse below L44)

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
        lda     $b5             ; current command
        beq     done            ; $00 fight: boost = extra swings
        cmp     #$06
        beq     done            ; $06 capture: same fight path
        cmp     #$07
        beq     done            ; $07 bushido: boost bought the tech tier,
                                ;   so it must not also buy a multiplier —
                                ;   the same no-double-dip the tier-family
                                ;   scan below enforces for folded spells
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

; [ retired: the over-character boost marks ]

; v0.2 RC playtest: "the boost chevrons sometimes turn into numbers", at
; no pattern the player could name.  They were not chevrons turning into
; numbers -- they were vanilla's damage numerals, drawn in tiles OT6 had
; taken.
;
; Three 16x16 arrow sprites used to live in obj tiles 200/202/204 (quads
; with 216-221), i.e. vram words $2c80-$2dd0.  ff6/notes/battle-ram.txt:
; 2206 labels that whole span: "$2C00 Damage Numeral Graphics / $2CC0
; Miss Graphics".  GfxCmd_0b picks a numeral's vram destination from two
; four-entry tables indexed by the rotating counter w7e632e
; (btlgfx_main.asm:24697 and :24781, tables at :24795):
;     bottom halves  $2d00,$2d40,$2d80,$2dc0
;     top halves     $2c00,$2c40,$2c80,$2cc0
; $80 bytes each (:1021).  Counter phase 2 covers boost-1 and boost-2;
; phase 3 covers boost-3.  Between them the four-phase rotation
; overwrites every one of the twelve tiles, so half of all damage numbers
; shown stamped digits over the chevrons -- intermittent, and keyed to a
; counter the player cannot see.  probe_objarrow.lua measured it: first
; divergence with counter=2 and dest=$2d80 exactly as predicted, and
; 2141 of 3000 sampled frames held clobbered art.
;
; The old comment here claimed these tiles were "verified blank +
; unreferenced by any oam entry ... idle and through attack effects".
; Both halves were true and neither was sufficient: battle init CLEARS
; $2c00-$3000 (btlgfx_main.asm:2244), so the tiles do read blank, and
; they are unreferenced right up until a numeral fires.  A snapshot
; cannot see a destination chosen at run time -- the exact "something was
; absent, so it was assumed free" failure CONTRIBUTING.md warns about.
;
; There is nowhere to move them.  Measured, not assumed: probe_objsentinel
; .lua fills the whole obj region with a sentinel AFTER init and plays a
; battle, so a zero-over-zero write cannot masquerade as untouched.  Only
; tiles 224-511 survive, and both blocks are spoken for --
; $2e00-$3000 is a blanket $400-byte init load (btlgfx_main.asm:2347) of
; hand-pointer/page-indicator/reflect/shield art, and probe_objtail.lua
; finds every tile in it either non-blank or oam-referenced;
; $3000-$4000 is monster graphics, which TfrMonsterGfx blankets with a
; fixed $2000-byte transfer every battle (btlgfx_main.asm:5410), so its
; apparent slack is only this formation's art being small.
;
; So the marks are gone rather than relocated.  Boost feedback keeps the
; channel that provably works: the party-window pip cell, which swaps to
; an arrow cluster pulsing yellow/white while a boost is pending (Ot6Boost
; @show) out of OT6's own 2bpp font cells -- glyph-canary verified, and
; battle_boost.lua gates it.  A future re-do wanting the floating badge
; back should draw it on the bg3 field map through the existing
; Ot6BgHud shadow/flush machinery (already OT6 territory, already veiled
; against entry/exit effects) rather than claim obj tiles again.

; ------------------------------------------------------------------------------

; [ per-frame bg hud: rebuild the shadow line buffer ]

; the hud lives on the bg3 field tilemap; this main-loop pass fills a
; shadow buffer in bank $7f, and the nmi flush copies it to vram during
; vblank. shadow at OT6_SHADOW, 6 lines x 14 bytes:
; (this line once read "$7f:fe00, 10 lines x 12 bytes" -- stale on both
;  counts, and $7ffe00 was never free: it is 1536 bytes into the LZ
;  decompression ring $7ff800-$7fffff, which battle init alone rewrites
;  when it decompresses StatusGfx.)
;   +0  vram word address of the line's first cell (0 = line disabled)
;   +2  five tilemap words (glyph | attr << 8)
; monsters: [shield-with-count][up to 4 weakness slots — elements, then
; weapon classes, revealed icon or '?' on both axes]. heroes: one
; pip-cluster cell. entities animate and drift, so each line remembers
; its previous address; the flush blanks the old cells when it moves.
; line layout: +0 cur addr (0 = disabled), +2 prev addr, +4 five cells.

; Lives at $7eecf1, past the end of vanilla's battle-graphics RAM chain.
; Four independent lines of evidence, since a bad answer here is what put
; this buffer inside live vanilla RAM the first time (see below):
;   1. btlgfx_ram.inc's chain ends at label w7eecf0 and is capped by
;      `.assert _ram_offset <= $7ef800` (btlgfx_ram.inc:1001) -- an
;      assembler-enforced invariant, so btlgfx cannot grow in without
;      failing the build. menu_ram.inc's chain tops out near $7e9849.
;   2. notes/battle-ram.txt:2183 documents "$ECF1-$F7FF -" (nothing),
;      with the hypotenuse table starting at $F800.
;   3. no literal reference, symbol, mvn/mvp target, or DMA/WRAM-port
;      loop in ff6/src or ff6/include lands in the range.
;   4. runtime write-watch over $7eecf1-$7ef7ff across a boss fight, four
;      forced command lists, a soak and a victory: zero writes -- while
;      the positive controls fired in the same run (DrawItemListText ran,
;      bank C1 wrote $5755-$576a).
;
; DO NOT extend past $7ef11f. PushMode7Vars (world/init.asm:1414) block-
; moves $7ef120-$7ef7ff via `mvn`, which no `sta` grep can find and which
; a fixture without a world-map battle never exercises. 1071 bytes are
; available; we use 84 and stop well short.
;
; WHY IT MOVED: this was $5762, annotated "trace-verified free". It was
; not -- $5762 sits 13 bytes inside vanilla's `ram_res w7e5755, 128`
; (btlgfx/btlgfx_ram.inc:71), and the battle command-list text drawers
; write $5755-$576a. The original trace ran a Fight-only fixture, where
; no command list ever opens, so it never saw them. Reproduced in
; tools/tests/probe_shadow_overlap.lua: DrawItemListText ran and bank C1
; wrote $5762-$5767, leaving the anchor at $00FF; the latch below then
; drove every NMI flush from $00FF for the rest of the battle. The
; magitek list drawer alone does NOT reproduce it (it stops at $5761),
; which is why a magitek-only fixture reads as an all-clear.
OT6_SHADOW  := $ecf1            ; lines, stride 14
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
        ; weakness slots into cells 1-4: elements first (vanilla's own
        ; data), then the class weaknesses, sharing the same four cells.
        ; a fifth weakness truncates — the deliberate cap: the row is
        ; five cells wide (the shadow strip has no room for more without
        ; moving the $57c0+ occupants), and no authored WoB species
        ; exceeds 4 total today (speck's 4 classes ride an element-free
        ; body). revealed-vs-'?' behavior is identical on both axes.
@slots: phx                     ; base on stack for the cap test
        lda     #$01
        sta     OT6_SCR_BIT
        lda     #$00
        sta     OT6_SCR_IDX     ; element index
@elem:  lda     OT6_SCR_BIT
        beq     @cls            ; elements walked: on to the classes
        and     $3be8,y
        beq     @next
        inx
        inx                     ; claim the next cell
        txa
        sec
        sbc     $01,s           ; cells used so far (byte diff, same page)
        cmp     #$09
        jcs     @edone          ; past slot cell 4 (offsets +6..+12) —
                                ;   long branch: the class loop sits between
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
@cls:   ; class-weakness slots: same claim/cap flow, from the authored
        ; class mask ($3e9c monster half, seeded at battle init) and the
        ; revealed-classes byte the chips and codex maintain. the icons
        ; are the vanilla item-class glyphs, white like the '?' (the
        ; default $21 attr from the fill is already in place — only the
        ; glyph byte is written, exactly like the '?' cell).
        lda     #$01
        sta     OT6_SCR_BIT
        lda     #$00
        sta     OT6_SCR_IDX     ; class index 0-3
@cbit:  lda     OT6_SCR_BIT
        cmp     #$10
        bcs     @edone          ; all four classes walked
        and     $3ea4,y         ; monster class weaknesses ($3e9c + 8)
        beq     @cnext
        inx
        inx                     ; claim the next cell
        txa
        sec
        sbc     $01,s           ; cells used so far (byte diff, same page)
        cmp     #$09
        bcs     @edone          ; past slot cell 4
        lda     OT6_SCR_BIT
        and     $3ea5,y         ; revealed classes ($3e9d + 8)
        beq     @cq
        phx
        lda     OT6_SCR_IDX
        longa
        and     #$00ff
        tax
        shorta0
        lda     f:Ot6ClassGlyphTbl,x
        plx
        sta     f:$7e0000+OT6_SHADOW+4,x
        bra     @cnext
@cq:    lda     #$bf            ; '?', default attr already in place
        sta     f:$7e0000+OT6_SHADOW+4,x
@cnext: asl     OT6_SCR_BIT
        inc     OT6_SCR_IDX
        bra     @cbit
@edone: plx
@done:  ; commit: latch the anchor once per battle, because recomputing every
        ; frame made the line jitter and blink on attack-animation coord
        ; transients. NOTE the justification once written here -- "monsters
        ; never move" -- is not established: vanilla recomputes both source
        ; arrays ($800f/$804b) from a tile base plus animation offsets
        ; (btlgfx_main.asm:1040), and the Whelk retract cycle and entry/exit
        ; effects visibly move things. The latch is a jitter workaround, and
        ; it is also what makes the OT6_SHADOW overlap above permanent
        ; instead of a one-frame blink. Recompute-and-compare would fix both.
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

OT6_HUDCOPY := $57de            ; (retired, and NOT ours to use: $57de is
                                ;  inside vanilla's `ram_res w7e57d5, 128`.
                                ;  kept only so the memory map records that
                                ;  this range is vanilla's, not free.)
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
                                ; writers).
; CAREFUL: the boundary is NOT "$57d5+ is vanilla's alone" (an earlier
; note here said that, and it is what made $5762 look safe). btlgfx_ram.inc
; reserves TWO buffers: w7e5755,128 AND w7e57d5,128 -- both vanilla's.
; What the probes actually establish is narrower and still holds:
; vanilla's writes into the $5755 buffer stop at $576b, so the OT6 strip
; from $57b6 up is empirically clear. Below $576b is NOT. See OT6_SHADOW.
OT6_RELAY_STAGES := 3           ; icons, glyphs x2 (~128b each). was 6:
                                ;   three arrow-tile stages retired with
                                ;   the over-character boost marks.

; the spare strip $57ba-$57bf (between OT6_FONTDIRTY and OT6_SPECIES,
; inside the m2 trace-verified free range; probe_57ba_strip write-watch:
; only bank-F0 writers). InitBP's @clr loop deliberately stops at $57b9:
; $57ba is rewritten every init by the spike probe anyway, and clearing
; $57bc would eat the random-encounter marker the field just set.
; occupants: $57ba-$57bb CWITNESS, $57bc RANDPEND, $57bd RANDBTL,
; $57be HUDVEIL (init-cleared one byte at a time in InitBP), $57bf spare.
OT6_CWITNESS := $57ba           ; word: the C toolchain spike's result
                                ;   (Ot6CSpikeProbe; battle_c.lua asserts
                                ;   it. RELOCATED from $57dc: that byte
                                ;   sits inside vanilla's $57d5-$5854
                                ;   battle name-scratch string, the same
                                ;   banner-tear collision family that
                                ;   moved OT6_FONTDIRTY.)
OT6_RANDPEND := $57bc           ; the NEXT battle is a random encounter:
                                ;   holds OT6_RANDMAGIC, set by
                                ;   Ot6MarkRandom from the two field/world
                                ;   random-battle triggers; consumed
                                ;   (compared + cleared) by InitBP.
OT6_RANDBTL  := $57bd           ; THIS battle is a random encounter
                                ;   (InitBP's normalized 0/1 copy of the
                                ;   marker; read at victory by
                                ;   Ot6RewardScale_ext). the copy-and-
                                ;   clear protocol means a marker can
                                ;   never leak past one battle: every
                                ;   InitBattle refreshes $57bd and zeroes
                                ;   $57bc, so an event battle after a
                                ;   fled or lost random encounter reads
                                ;   0. two junk defenses on top (the
                                ;   strip is init-exempt, so power-on/
                                ;   menu junk lives here until the first
                                ;   battle -- probe_57ba_strip measured
                                ;   $ff on the srm-boot line): the marker
                                ;   is a magic value, not "nonzero", and
                                ;   Ot6DangerStep word-clears both bytes
                                ;   on every danger-checked field step.
OT6_RANDMAGIC := $a5            ; the marker value (junk is $00/$ff in
                                ;   every observed boot line)
OT6_HUDVEIL  := $57be           ; nonzero = a monster entry/exit animation
                                ;   owns bg3: the flush writes vanilla's
                                ;   $01ee junk fill over each live hud
                                ;   line instead of its cells (shadow
                                ;   untouched). set/cleared by
                                ;   Ot6EntryExitVeil_ext, cleared by
                                ;   InitBP (the strip is init-exempt, so
                                ;   power-on junk here would blank the
                                ;   hud from battle one).

; [ monster entry/exit animations: veil the under-enemy hud ]

; every jsl DoMonsterEntryExit site in bank c1 is re-pointed here (same
; four bytes, no code motion). the entry/exit effect family — the whelk
; retract's FADE_DOWN/FADE_UP wipes especially — sweeps the battle-field
; bg3 region with a per-scanline scroll wave (hdma #2, fed from the
; w7e4af5 table the effect animates), and it assumes the field map holds
; nothing visible but its own mask tiles: vanilla blanks even its banner
; rows to the $01ee junk fill before scrolling. our under-enemy hud
; lines ride that same map, so the wipe smeared their glyphs across the
; screen (v0.1 whelk playtest; battle_whelkwipe is the regression gate —
; veiling exactly the hud words removed every stray pixel, measured
; against the base image frame by frame). while the veil byte is set the
; nmi flush writes the $01ee fill over each live line instead of its
; cells — the field map is word-identical to vanilla's for the whole
; animation — and the shadow itself is untouched, so the first flush
; after the effect repaints the hud exactly as built (or blanks it, if
; the monster left with the effect). a8/i16 at every call site (battle
; gfx script context); the anim returns a8/i16 on every path, sep #$20
; is belt and suspenders.

.proc Ot6EntryExitVeil_ext
        .a8
        .i16
        lda     #$01
        sta     f:$7e0000+OT6_HUDVEIL
        jsl     DoMonsterEntryExit
        sep     #$20
        lda     #$00
        sta     f:$7e0000+OT6_HUDVEIL
        rtl
.endproc

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
        beq     @s0             ; a = stage 2..0, most visible first
        cmp     #$01
        beq     @s1
        jsr     Ot6LoadElemIcons        ; 2: menu element icons
        bra     @nofont
@s1:    jsr     Ot6LoadBgGlyphsA        ; 1: hud shield glyphs
        bra     @nofont
@s0:    jsr     Ot6LoadBgGlyphsB        ; 0: hud pip/boost glyphs
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
        lda     f:$7e0000+OT6_HUDVEIL-1          ; veil rides the high byte
        and     #$ff00                           ;   (low byte = randbtl)
        bne     @veil
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
        bra     @skip
@veil:  lda     #$01ee          ; an entry/exit anim owns bg3: vanilla's
        sta     hVMDATAL        ;   junk fill, so the scroll wave sweeps
        sta     hVMDATAL        ;   a map word-identical to vanilla's
        sta     hVMDATAL
        sta     hVMDATAL
        sta     hVMDATAL
@skip:  shorta0
        longa
        txa
        clc
        adc     #$000e
        tax
        shorta0
        cpx     #$0054          ; 6 monster lines x 14
        jcc     @line           ; (veil branch grew the body past bcc)
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
; while a battle menu is open AND the actor's action is still being
; composed, R raises the active character's pending boost (cap 3, and
; never past their bp) and L lowers it. the pips by the party names show
; spendable bp (bp - pending), so feedback is immediate: the flush's
; one-cell pseudo-line repaints the active row's pip cell straight into
; the menu tilemap. window_open re-stages every row on the next open,
; cleaning up any transient state.
;
; "still being composed" is $32cc,y = $ff, the actor's pending-action
; command-list pointer (battle_main.asm:254 sets it to $ff when nothing
; is pending; CreateNormalAction:@4ecb tests it the same way). Measured
; across a real menu walk (probe_lateboost.lua): $ff through command
; select, the ability list AND target select, then a live pointer the
; instant the target is confirmed.
;
; That boundary is the fix for a v0.2 RC playtest report ("you can boost
; after selecting the ability" / "it looks cosmetic"). Two different
; things were happening either side of the confirm, and only one was a
; bug:
;   * DURING target select the spend is fully effective and stays legal
;     -- DESIGN.md prices boost "when confirming an action", and
;     Ot6QueueFold reads pending from CreateAction, which runs after
;     target select. Measured: R at the target cursor folded Fire to
;     Fire 3 ($09 at $3410), charged 2 bp (5 -> 3), and dealt tier-3
;     damage. The playtester read it as cosmetic because the spell-list
;     preview -- the thing the Narshe school teaches them to watch -- is
;     closed by then, and because the over-character chevrons they WERE
;     watching were rendering as damage numerals (the other defect).
;   * AFTER the confirm it was theft. CreateAction has already frozen
;     the tier, but Ot6ActionEnd still charges whatever pending reads at
;     action end. Measured: two more R presses post-confirm took pending
;     2 -> 3, the queued spell stayed Fire 3, damage was identical (319
;     both ways), and bp fell 5 -> 2. Three points paid, two points'
;     worth delivered.
; Refusing silently rather than buzzing: the menu lingers open for a few
; frames after every confirm, so a buzz here would fire on ordinary play
; and teach the player that a legal boost had been rejected.

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
        ; the action is committed once the actor has a command-list
        ; pointer: the tier is already frozen, so a spend here would be
        ; charged and buy nothing. display only from that point on.
        pha
        lda     $32cc,y
        inc     a               ; $ff (nothing pending) -> 0
        beq     :+
        pla
        bra     @show
:       pla
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
;   - piranha and iron fist wear their boss-block's class row (the doc
;     gives fight-level rows, not per-add rows): judgment calls.
;   - guardian/tritoch: multiple records each, WoB story order can't
;     tell them apart from here — ALL drawn shieldless for the WoB;
;     the WoR pass must re-author the real WoR fights' records.
;
; not a deviation, but it reads like a gap: kefka has one row and the
; imperial camp gags are NOT it — they need none. $14a is
; MONSTER::KEFKA_NARSHE (const.inc:1222), and it appears in exactly two
; of the 576 formation records — 489 and 505 — with `battle 57` -> group
; 57 -> 505 the narshe defense. the camp gags run `battle 56`
; (event_main.asm:40683 and :40743) -> group 56, whose two slots BOTH
; point at formation 504 — and 504 has no monster in it: present mask $00
; and all six id slots the $01ff empty sentinel (battle_monsters.dat
; +$1d88 = 00 00 ff ff ff ff ff ff 00 00 00 00 00 00 3f; the mask is
; rolled into $3aa8 at battle_main.asm:7692, and the sentinel skips
; LoadMonsterProp at :7718). nothing is loaded, so Ot6SeedShields —
; reached only from the monster/rage load — never sees them. what those
; fights run on instead is character ai: battle_prop.dat +$7e0 sets $2f49
; bit 7 with $2f4a = $04 (LoadBattleProp :7994, dispatch :7813), script
; kefka_imp_camp_1, whose slot 0 is
; CHAR_PROP::KEFKA_1|CHAR_AI_FLAG_ENEMY_CHAR (char_ai.asm:163) — the
; event has already dressed a party slot as him (char_prop VICKS,
; KEFKA_1, event_main.asm:40675; CHAR::VICKS = 15, CHAR_PROP::KEFKA_1 =
; $29) and revives that actor between rounds (clr_status VICKS, DEAD /
; max_hp VICKS, :40739) because he has character hp. gauging a character
; actor would be a per-formation feature, not a table row.
;
; this comment used to say vanilla shared ONE species between the camp
; and narshe and that the camp fights "inherited" the $14a row. they
; cannot: the camp has its own id ($16f, MONSTER::KEFKA_IMP_CAMP,
; const.inc:1259) and even that is only the actor's ai script, never a
; loaded record. see docs/design/bosses-wob.md "6-7. Imperial Camp".
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
        .byte   6, OT6_SLASH|OT6_PIERCE ; kefka: the NARSHE DEFENSE record
                                ;   only (MONSTER::KEFKA_NARSHE). the
                                ;   imperial camp gags carry no monster
                                ;   entity at all — see block comment
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
        sta     f:$7e0000+OT6_CWITNESS  ; witness word: 3*2 + 4 + 1 = 11
        pla                     ; caller pops the stacked arg
        plp
        rts
.endproc

; ------------------------------------------------------------------------------

; weapon/ability class data (m3)
        .include "ot6_class.asm"
