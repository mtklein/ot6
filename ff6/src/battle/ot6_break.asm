OT6_BREAK_TICKS := $10          ; a bit under vanilla stop duration ($12)

; ------------------------------------------------------------------------------
; [ the shared 16ths multiply: a16 A *= (mult/16), clamped to $ffff ]
;
; OT6 scales three different 16-bit quantities by a byte "in 16ths" ($10 = 1x,
; $28 = 2.5x): monster HP (hpmul, off Ot6ShieldTbl), the per-step danger rate
; (Ot6DangerStep, off Ot6DangerMulW) and shielded damage (Ot6ShieldedDmg, off
; Ot6ShieldedMulW).  All three ran the same twenty-two instructions inline,
; byte-for-byte the same, with only the final branch's label spelling differing
; (@fits at two sites, :+ at the third; both target the next
; instruction, so the emitted branch is identical).  This is that code, once.
;
; A macro rather than a proc, deliberately.  Ot6ShieldedDmg runs inside the
; per-target damage loop and Ot6DangerStep runs on every field step; a jsr
; here would add ~12 cycles to both for nothing, and this codebase has
; measured that a jsr into a per-frame path is already over budget.  A macro
; expands to the identical bytes at the identical addresses, which is also
; how this refactor is verified: by a byte-identical ROM rather than by a
; passing suite.
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
        ; is species-indexed: OT6_FLOOR_CLASS[species] (gen_break_floor.py).
        ; written unconditionally at every seed: like the reveal masks below
        ; it must not survive a Cmd_20 reload (no InitBattle clear), or the
        ; hud draws a stale class-weakness cell from the slot's prior
        ; occupant. the authored @hit path overwrites OT6_BP_CLASS (store above) so
        ; its mask wins; the floor is only the fallback for un-authored ids.
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
        ; with no InitBattle $3a20-$3ed3 clear. on the fresh path InitBattle
        ; already zeroes these (write-trace confirms: its clear stores $00 here
        ; before the seed runs), so this is redundant there and
        ; required only on reload. monster path only (y >= $08 past @on):
        ; the character rows are never touched. with 32k sram the codex
        ; re-merge below restores reveals that were earned (chips write them
        ; through), so a same-monster retract cycle keeps its reveals.
        lda     #$00
        sta     OT6_BROKEN_TICKS,y         ; broken timer: a stale nonzero reload-starts
                                ;   the monster broken (Ot6Gate skips its turn,
                                ;   2x damage, the hud shield cell draws the
                                ;   broken glyph). the seed otherwise never
                                ;   writes it, so a reload inherits the slot's
                                ;   prior occupant.
        sta     OT6_REVEALED_ELEM,y         ; revealed weakness elements: stale bits, OR'd
                                ;   with the codex below, draw weaknesses as
                                ;   revealed from battle start instead of '?'
                                ;   (the hud '?'-gate reads OT6_REVEALED_ELEM/OT6_BOOST_REVEALED)
        sta     OT6_BOOST_REVEALED,y         ; revealed classes (monster half)
        sta     OT6_RVPEND_ELEM-8,y  ; #33: pending reveals must not survive a
        sta     OT6_RVPEND_CLS-8,y   ;   Cmd_20 reload either; a stale bank
                                     ;   would commit the prior occupant's
                                     ;   weakness onto the new species
        sta     OT6_BRKTICK-8,y      ; #48: nor a pending or live break flash.
        sta     OT6_BRKPAL-8,y       ;   these two sit past InitBP's shadow
                                     ;   clear, so this is also their only
                                     ;   power-on clear: junk here would flash
                                     ;   a monster white on the first frames of
                                     ;   the first battle after a cold boot,
                                     ;   and hand it back a junk palette
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

; Element additions are authored OT6 combat properties, implemented as a
; runtime transform like Ot6HpScale and applied one hook later than the load: the
; mask is OR'd into the loaded weak byte $3be0,y (LoadRageProp stores it
; from MonsterProp+25 immediately before the seed hook), so the chip
; path, vanilla's weak x2 damage, and the hud weakness slots all read
; one truth. re-loads (retract cycles, scene changes) re-apply the OR:
; idempotent by construction.
;
; the whelk head ($134) gains fire: the boss tutorial's designed line
; (three fire beams and a TekMissile, broken inside one head-present
; phase) needs four chippable hits, and the head has no vanilla fire
; weak (measurement #2 called this add required m6 data). vargas
; ($103) gains holy: bosses-wob.md's vargas entry reads "poison, holy +
; bludgeoning", and vanilla gives him poison only (monster_prop.dat +25
; = $08). holy is the chip sabin's arrival is supposed to switch on,
; and aurabolt already carries it ($5e element byte = $20 in vanilla
; spell data), so this row is the remaining distance. verified at
; runtime by battle_vargas.lua.
;
; the v0.3 arc added armor-line rows here under a doctrine the v0.6
; break-coverage pass has since retired. the doctrine was the narshe
; school's tier-2 seed: "their armored machines shrug off blade and fire
; alike ... every armor fears one right tool" (the school's superseded
; tier-2 copy; narshe-school.md now carries the replacement),
; the tool being edgar's bio blaster (item $a4 -> attack $7d, element $08
; poison, battle_main.asm:6577). that made poison the sole key to the
; imperial line, and the fixed-party audit found the hole: the forced
; parties that fight this line (Cyan solo at Doma, Sabin's whole
; scenario, Locke solo in South Figaro, two of the three Narshe squads)
; carry no Edgar and so no poison, and could not break armored trash at
; all. v0.6 moves the soldier line onto weapon-class rows in Ot6ShieldTbl
; (pierce/slash/bludg, chosen per the party that fights each; the decode
; and rationale live there and in bosses-wob.md). poison is
; now one Edgar key among several rather than the only one; the school's
; old "shrug off blade / one right tool" seed contradicted the new fiction
; ("a blade finds the gaps"), so it took a dialog revision under the
; school's own sanction (2026-07-22, narshe-school.md): $0276 now teaches
; "every plate has its seam ... bring the weapon that fits."
;
; what remains poison-keyed in this table are the two machines, where a
; party that fights them can cast it, each row keeping every
; vanilla bit (decoded from monster_prop.dat at species*32 +$19; the
; offset is vanilla's own, battle_main.asm:7517 loads MonsterProp+25):
;
;   $042 m-tekarmor  +$0859  vanilla $04 bolt        -> $0c bolt|poison
;   $09f heavyarmor  +$13f9  vanilla $84 bolt|water  -> $8c (+ slash|pierce
;                            class in Ot6ShieldTbl)
;   $002 templar     +$0059  vanilla $08 poison      -> $0c bolt|poison
;                            (+bolt: metal conducts, Shadow's Bolt Edge;
;                            + a pierce class row in Ot6ShieldTbl)
;
; leader ($14e) and grunt ($14f) had poison adds here in v0.3, because they
; had no vanilla weakness of any kind and poison was their only gauge, and
; v0.6 removed both: their forced fights (Cyan's solo duel; Cyan+Sabin's
; Doma courtyard defense) carry no poison, so the add was dead data that
; also drew an unresolvable '?' on a swordfight. both are class-keyed now
; (leader slash; grunt slash|bludg; Ot6ShieldTbl).
;
; and two boss rows bosses-wob.md already specified but m6 never entered:
;
;   $14a kefka       +$2959  vanilla $00 none        -> $09 poison|fire
;   $104 tunnelarmor +$2099  vanilla $84 bolt|water  -> $86 (+ice)
;
; $14a is MONSTER::KEFKA_NARSHE and nothing else; the imperial camp
; gags load no monster record at all (Ot6ShieldTbl's block comment has
; the full decode). he is the v0.3 stop line, and vanilla left him with
; no weakness at all. tunnelarmor's ice is celes's join spell buying
; a socket: vanilla's bolt and water are both dead keys for the
; locke+celes duo, so without the add the fight has no element chip at
; all (bosses-wob.md "5. TunnelArmor").
;
; every row here was checked against +$17 (absorb) and +$18 (null) before
; authoring; every one reads $00/$00 (templar included), so no row here
; puts a chip trigger on an absorber. that check is not a formality: it is
; the error bosses-wob.md caught twice in draft (nerapa listed fire,
; which it absorbs; the cranes' absorb pair was read as their weak pair).
;
; ---- the v0.3 trash pass: six rows that make the break happen ----
;
; everything above is a boss or a set-piece. these six are ordinary
; random encounters, and they exist because measurement #7 established
; that the break, the mechanic this hack is named for, had never once
; happened in play: `player_actions_broken` was 0.0 across 168 battles,
; because every species without an authored row takes Ot6SeedShields'
; @formula path, which clears OT6_BP_CLASS (:76-85), so formula trash carries no
; class weakness and most of it carries no reachable element either.
;
; why element rows and not Ot6ShieldTbl class rows. the party that walks
; this stretch is terra, locke and edgar, and they arrive at mt. kolts
; carrying a mithril knife, a dirk and a mithril blade (char_prop.asm:152,
; :162, :197), which ot6_class.asm:49, :48 and :59 make pierce, pierce
; and slash. so the party's three default swings already cover half the
; class ring, and the other half has no wielder at all: bludgeoning
; arrives with sabin, who joins at the top of the mountain, and special
; not until setzer. a class row on this stretch is therefore either free
; (slash/pierce: holding A chips it, which is measurement #7's
; own +pierce finding, where the mash arm started chipping by accident and
; the mash-vs-loop gap closed) or unreachable (bludg/special: nothing in the
; party can chip it, and the fight has no loop at all). the class axis is
; degenerate here. the element axis is not: terra's fire costs 4 mp and a
; magic menu, edgar's bio blaster costs a tools dive (item $a4 -> attack
; $7d, magic_prop_en.dat record $7d: element $08, targets $6a = all
; enemies, power 20, 0 mp), and neither of them is what the A button does.
;
; so the stretch gets exactly two live keys and this table splits it
; between them. fire is vanilla's and already opens eight of the fifteen
; species the stretch draws (leafer, dark wind, hornet, bleary, crawly,
; trilium, tusker, vaporite); poison opened exactly one (greasemonk,
; +$1519 = $08). six rows even that up, so the per-fight question becomes
; "which of edgar's two menus" asked against a body you can read:
;
;   $086 cirpius   +$10D9  vanilla $00 none       -> $08   134 hp
;   $07a tusker    +$0F59  vanilla $01 fire       -> $09   270 hp
;   $05c sand ray  +$0B99  vanilla $82 ice|water  -> $8A    67 hp
;   $05d areneid   +$0BB9  vanilla $82 ice|water  -> $8A    87 hp
;   $012 rhodox    +$0259  vanilla $00 none       -> $08   119 hp
;   $015 rhinotaur +$02B9  vanilla $00 none       -> $08   232 hp
;
; four of those six had no weakness the stretch party could reach:
; cirpius and rhodox had no weakness at all, and sand ray and areneid are
; ice|water with nobody carrying either (terra's natural list is cure 1,
; fire 3, antdot 6, drain 12, field/event.asm:1248-1251, so fire is her
; whole offensive element ring at this point in the story). they are the
; coverage rule's live counterexamples on the route the v0.2 demo ships,
; and cirpius is the most common of them: it is 93.75% of the draws on mt.
; kolts maps 95/96/97 and it comes three at a time, so the mountain's
; most common fight was three unchippable birds.
;
; the two that already had fire are here for a different reason, which is
; arithmetic. an element chip that empties the last shield takes
; vanilla's weak x2, then skips Ot6ShieldedDmg (shields are already 0),
; then takes Ot6BrokenDmg's x2, so 4x base on the breaking hit itself. at
; terra's ~110 base that is ~440, and nothing on this mountain except
; tusker has the hp to survive its own break through the fire channel.
; bio blaster's per-target damage is a fraction of that (power 20, split
; over the whole enemy side), so poison is the channel that can open a
; window rather than closing the fight. tusker at 270 hp is the one body
; big enough for that window to be wide, which is why it gets poison on
; top of vanilla's fire: fire stays the burst answer to a 270-hp wall,
; poison becomes the break answer, and the player picks.
;
; and the shelf-F read that falls out of it: brawler ($00b) absorbs poison
; (+$0177 = $08). map 100
; draws brawler-pair 62.5% and tusker-pair 37.5%, so on the same shelf the
; same tool breaks one formation and heals the other. brawler's answer is
; a class row in Ot6ShieldTbl instead (see there); the absorb is vanilla's
; own byte and stays untouched.
;
; every one of the six was checked at +$17/+$18 the same way the boss rows
; were. five read $00/$00; rhinotaur absorbs BOLT (+$02B7 = $04) and nulls
; nothing, so poison is clear on it too. no row here feeds an absorber.
;
; deliberately not authored, so the next author does not re-open it:
;   - trooper ($065, +$0cb9 = $08) and rider ($03f, +$07f9 = $09) are
;     already poison-weak in vanilla, so no element add is authored for
;     them. but v0.6 did give both a slash|pierce class row (Ot6ShieldTbl):
;     the Narshe defense is a player-assigned 3-way split, and the squads
;     without Edgar (e.g. Cyan+Sabin, Locke+Gau) reach neither poison nor
;     any vanilla element on these bodies, only a weapon class. vanilla
;     poison stays the Edgar-squad's key; the class row is every other
;     squad's. formation 88 (trooper+heavyarmor) now opens to whatever a
;     squad holds rather than to Edgar alone.
;   - specter ($156) absorbs poison (+$2ad7 = $08) and is fire|holy weak
;     (+$2ad9 = $21). it is a monster-in-a-box on the phantom train (map
;     153, treasure 114 -> event battle group 34 -> formation 476),
;     the same train whose boss also absorbs poison. the train has no
;     poison key at all, boss or chest; vanilla's fire|holy are
;     live keys there (shadow's fire skean, sabin's aurabolt) so it
;     needs no add, and the one element this arc is about would heal it.
;   - siegfried ($131) has no vanilla weakness, absorb or null ($00 at
;     +$2637/+$2638/+$2639). the phantom train gag who flees (battle 109,
;     event_main.asm:65247) and bosses-wob.md gives him no block. the
;     formula's 2 shields stand: unlisted species are meant to fall
;     through, and inventing a key for a fight the player is supposed to
;     walk away from is not something any design doc asked for.
;   - the stretch's already-fire-weak trash: leafer ($017 +$02F9 = $81),
;     dark wind ($028 = $01), hornet ($02e = $01), bleary ($063 = $01),
;     crawly ($062 = $01), trilium ($032 = $01), vaporite ($046 = $21).
;     the coverage rule is already satisfied for every one of them by
;     terra's fire, and a second key would make the probe a formality.
;     none of them can hold a break window either (33 to 147 hp against
;     a 4x breaking hit), and measurement #7 showed that directly on
;     leafer: a synthetic class row there produced 0.7 breaks a fight and
;     every one landed at 100% of fight length, `player_actions_broken`
;     still 0. these are texture rather than tuning material, the same
;     disposition measurement #1 gave the mines pool.
;   - brawler ($00b) is the one species on the mountain that gets a class
;     row rather than an element one, because poison is the one element it
;     must not have (it absorbs it, +$0177 = $08) and its vanilla ice
;     (+$0179 = $02) has no wielder until celes. see Ot6ShieldTbl.
;   - greasemonk ($0a8 +$1519 = $08) is already poison-weak in vanilla, so
;     the south-figaro plains had one live key before this pass and an
;     add here would be a no-op ora that misstates who authored it,
;     the same rule the trooper/rider rows above are held to.
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
        ; the armor line, v0.6 break-coverage pass (block comment above).
        ; the soldier line is class-keyed now (Ot6ShieldTbl); what stays
        ; here is poison on the two machines plus templar's conducting bolt.
        .word   $0042
        .byte   $08, $00        ; m-tekarmor: + poison (keeps bolt; Shadow's
                                ;   Bolt Edge is the live camp key)
        .word   $009f
        .byte   $08, $00        ; heavyarmor: + poison (keeps bolt|water;
                                ;   Edgar's key at the Narshe waves. also a
                                ;   slash|pierce class row, Ot6ShieldTbl)
        .word   $0002
        .byte   $04, $00        ; templar: + bolt (vanilla $08 poison ->
                                ;   $0c bolt|poison; metal conducts, Shadow's
                                ;   Bolt Edge. also a pierce class row)
        ; the arc's stop line, and the scenario boss that had no key
        .word   $014a
        .byte   $09, $00        ; kefka (narshe defense): + poison|fire
        .word   $0104
        .byte   $02, $00        ; tunnelarmor: + ice (keeps bolt|water)
        ; the v0.3 trash pass: the break made reachable in ordinary
        ; fights. poison is edgar's bio blaster, the stretch's only
        ; deliberate key the A button does not already swing.
        .word   $0086
        .byte   $08, $00        ; cirpius: + poison. had no weakness at
                                ;   all, and it is 93.75% of mt. kolts
                                ;   maps 95/96/97, three at a time; one
                                ;   group tool chips the whole flock
        .word   $007a
        .byte   $08, $00        ; tusker: + poison (keeps fire). 270 hp,
                                ;   the only body on the mountain that
                                ;   survives its own break; fire stays
                                ;   the burst, poison becomes the window
        .word   $005c
        .byte   $08, $00        ; sand ray: + poison (keeps ice|water,
                                ;   neither of which the figaro-desert
                                ;   party can cast)
        .word   $005d
        .byte   $08, $00        ; areneid: + poison (same desert, same
                                ;   dead ice|water pair)
        .word   $0012
        .byte   $08, $00        ; rhodox: + poison. had no weakness, and
                                ;   it is 275% of the south-figaro plains
                                ;   forest draw
        .word   $0015
        .byte   $08, $00        ; rhinotaur: + poison. had no weakness;
                                ;   232 hp is the plains' break-capable
                                ;   body (absorbs bolt, not poison)
        ; ---- the v0.4 search-for-terra corridor: five poison rows for the
        ; western-WoB overworld the party roams looking for terra before Zozo.
        ; the party is Locke+Celes+Edgar+Sabin and its two deliberate keys are
        ; poison (edgar's bio blaster) and ice (celes); there is no fire,
        ; because terra is the search target. these five draw across the western/
        ; southern WoB sectors and every one is a coverage hole: no vanilla
        ; weakness of any element, and a formula species carries no class
        ; weakness, so before this row the terra-less party could not chip them
        ; at all. poison is the available key (a Tools dive, not the A button)
        ; and the group target answers the packs. verified against
        ; monster_prop.dat +$19/$18/$17: weak/null/absorb all read $00 on all
        ; five, so no row here feeds an absorber (the GhostTrain case):
        ;   $018 stray cat  156 hp    $01d baskervor 750 hp
        ;   $01f chimera   2237 hp    $078 red fang  325 hp
        ;   $07b ralph      620 hp
        ; not poisoned, because they already have a reachable answer and poison
        ; would be the wrong one: iron fist $06c absorbs poison (+$0d97 = $08)
        ; and carries a class row in Ot6ShieldTbl (locke's pierce / sabin's
        ; bludg); fossilfang $023 absorbs poison too but is ice-weak, which
        ; celes casts, so ice is its key. sand ray $05c / areneid $05d are
        ; already +poison above and ice-weak. the desert half of this region is
        ; covered without a row here.
        ; UNMEASURED: no world-map fixture stands in this
        ; region (the search arc is not on any generated savestate), so these
        ; five are coverage on the same census+arithmetic footing measurement #8
        ; gave the figaro-desert rows: shields left to the formula, element
        ; table only (no HpScale exemption), and numbers to be taken once a
        ; corridor fixture is generated. the fire hole, flagged: a few
        ; western-WoB bodies are fire- or wind-weak only ($090 fire, $08c
        ; fire|wind, $02a wind) and this party casts neither, so their vanilla
        ; weakness is dead for it. they are left as-is rather than double-keyed
        ; without evidence: whether they sit on the walked route at all is what
        ; the missing fixture would settle. see measurement #9.
        .word   $0018
        .byte   $08, $00        ; stray cat: no weakness, absorbs nothing
        .word   $001d
        .byte   $08, $00        ; baskervor: 750 hp, break-capable body
        .word   $001f
        .byte   $08, $00        ; chimera: 2237 hp, the region's wall
        .word   $0078
        .byte   $08, $00        ; red fang: on the task census and the tables
        .word   $007b
        .byte   $08, $00        ; ralph: no weakness, absorbs nothing
        ; ---- the v0.6 boss-element pass (issue #23). four sets that
        ; bosses-wob.md authored in prose and nobody wrote into the
        ; data; check_boss_rows.py found them and carried them as waivers
        ; until now. every row below was re-decoded from monster_prop.dat
        ; +$17 (absorb) / +$18 (null) / +$19 (weak) at authoring time rather
        ; than recalled: the Crane pair in that same document was already
        ; wrong in the absorb direction once, and the GhostTrain rule
        ; (never put a chip trigger on an absorber, where vanilla reverses
        ; the damage sign) is what these checks enforce:
        ;
        ;   species          absorb  null                    weak   add
        ;   $117 atmaweapon  $00     $00                     $00    $07
        ;   $10b number 128  $02 ice $00                     $00    $84
        ;   $13f rightblade  $02 ice $00                     $00    $04
        ;   $140 left blade  $02 ice $00                     $00    $04
        ;   $116 flameeater  $01 fir $6c bolt|poi|holy|earth $02    $80
        ;   $168 ultros 4    $80 WAT $00                     $09    $04
        ;
        ; no add bit intersects that row's absorb or null byte. the last
        ; line matters most: $168 absorbs water, so the water half
        ; of the family row would heal him and only bolt is restorable.
        ; battle_breaktbl.lua walks this whole table and asserts the
        ; add-vs-absorb/null invariant on every row, future ones included.
        .word   $0117
        .byte   $07, $00        ; atmaweapon: + fire|ice|bolt. the capstone
                                ;   fix: 11 shields, the largest gauge in
                                ;   the arc, and vanilla gives it no element
                                ;   at all, so before this row a free-pick
                                ;   party holding neither slash nor pierce
                                ;   had no break on the WoB final exam.
                                ;   absorbs and nulls nothing: all three
                                ;   bits are free (bosses-wob.md §21)
        .word   $010b
        .byte   $84, $00        ; number 128 body: + bolt|water. the espers
                                ;   zozo just paid out (ramuh) are the key
                                ;   the fight was written around; absorbs
                                ;   ice, which is neither bit (§15)
        .word   $013f
        .byte   $04, $00        ; right blade: + bolt (the narrower row the
                                ;   doc authors for the limbs; same ice
                                ;   absorb, untouched)
        .word   $0140
        .byte   $04, $00        ; left blade: + bolt
        .word   $0116
        .byte   $80, $00        ; flameeater: + water. strago's debut fight
                                ;   and Aqua Breath is what the doc frames
                                ;   it on; water was neutral on $116
                                ;   (not weak, not nulled, not absorbed), so
                                ;   the Lore read a row it could not use.
                                ;   it absorbs fire and nulls bolt|poison|
                                ;   holy|earth; water is in neither (§18)
        .word   $0168
        .byte   $04, $00        ; ultros 4: + bolt only. $168 is a different
                                ;   species from $12c/$12d/$12e and vanilla
                                ;   gave it fire|poison, not fire|bolt, so
                                ;   the running gag's element half was never
                                ;   true. bolt restores it. water is the rest
                                ;   of the family row and is not added here:
                                ;   every Ultros record absorbs water (+$17 =
                                ;   $80), so that bit would heal him (§19)
        .word   $ffff

; ------------------------------------------------------------------------------

; [ difficulty transform: scale trash battle hp at monster seed time ]

; Enemy narrative role, visual identity, and recognizable behavior are
; useful design anchors rather than fixed constraints. OT6 may author combat
; properties when the break grammar or pacing benefits. This
; broad difficulty pass is applied as a runtime transform:
; both battle-ram copies of the loaded hp ($3bf4 current, $3c1c max,
; LoadMonsterProp's only hp stores; every monster load goes through
; it) are multiplied by a per-band value in 16ths, clamped at $ffff.
;
; exemptions, by construction:
;   - authored species (any Ot6ShieldTbl row: bosses + tutorial trash),
;     because boss difficulty is bosses-wob.md's job (it plans hp cuts) and
;     the gate's battle fixtures are authored species, so their damage
;     arithmetic stays byte-stable
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
; never compound across encounters.
;
; measurement #5 took the multiplier down to 1x. it and shielded
; resistance both lengthen fights, and stacking 2x hp with the 0.5x
; resistance put fights well past the intended length (baseline mines TTK
; ~6 real actions). the co-tune sweep found 1x hp x 0.5x resistance works
; best: shielded resistance now carries the "fights are
; longer" load (it halves off-weakness damage, so a player who ignores the
; loop has fights that run ~2x longer, matching measurement #4's pace-knob
; regime, while a weakness-exploiting player stays vanilla-fast). the
; multiplier had done that job by inflating every player's hp bar equally,
; which did not reward the loop; resistance does. band1 tracks band0 to 1x
; so the global danger/reward knobs stay conserved across bands (a mixed
; 1x/2x table would put mid-trash fights at ~4x length). band1 mid-trash
; stays unmeasured: parity extrapolation pending stretch fixtures.
Ot6HpMulTbl:
        .byte   $10             ; $000-$05f: 1x, swept (measurement #5:
                                ;   resistance carries the lengthening)
        .byte   $10             ; $060-$0bf: 1x, tracks band0 (parity;
                                ;   mid trash unmeasured, fixtures pending)
        .byte   $10             ; $0c0-$0ff: 1x, wor, unmeasured
        .byte   $10             ; $100+ (keep 1x: see doom gaze note)

; ------------------------------------------------------------------------------

; [ encounter-rate knob + reward conservation ]

; fights at 2x hp run ~2x longer (measurement #3: 1456f vs 744f), so the
; per-step encounter danger increment is scaled down and random-battle
; rewards are scaled up by the inverse: combat time per step and xp/gil
; per step both track vanilla. the two knobs are 16ths and their product
; is pinned at $100 (1.0) by the conservation rule; change them as a
; pair or the level/shop pacing drifts.

Ot6DangerMulW:
        .word   $0008           ; per-step danger increment x 8/16 (0.5x)
Ot6RewardMulW:
        .word   $0020           ; random-battle xp+gil x 32/16 (2x)

; [ suppress sub-map encounters that the vanilla field cannot start ]

; Map 225's north bridge shaft is a z-loop ladder: its diagonal tiles change
; the party between z 0/2/3 while a step is resolving.  If CheckBattleSub
; rolls on that ladder, EventScript_RandBattle stops forever at $ca0029 while
; waiting for the pre-battle scroll/object movement to settle; the battle
; latch never comes up and player control never returns.  This is observable
; in unmodified play, not a test-runner artifact.
;
; The rectangle below is the shaft's complete authored route (x 29..40,
; y 31..61); other rooms in composite map 225 lie outside it and keep their
; encounter pool.  CheckBattleSub has already proved the party is tile-aligned
; and cleared its one-step $57 request before calling.  Return carry SET to
; run the normal danger/encounter path, CLEAR to consume this step without
; adding danger or advancing the battle RNG.  a8/i16; preserves a/x/y and
; every status bit except the carry result.

.proc Ot6AllowSubBattle
        .a8
        .i16
        php
        longa
        pha
        phy
        lda     a:$0082
        cmp     #$00e1          ; field map 225, Zozo interiors
        bne     Allow
        ldy     a:$0803         ; active party object's property offset
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
; never touches $3ecc-$3ed3, checked by grep).

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

; called from the weak-element branch of CalcTargetDmg (match confirmed).
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
        ora     OT6_RVPEND_ELEM-8,y     ; #33: bits already banked this action
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
merge:  pla                     ; bank the matched weaknesses as pending (#33):
        ora     OT6_RVPEND_ELEM-8,y     ;   the on-screen reveal must land on
        sta     OT6_RVPEND_ELEM-8,y     ;   the damage frame, and this runs at
                                ;   damage calc, hundreds of frames earlier
                                ;   (measured: probe_clockwork, calc f704 vs
                                ;   first numeral f1006).  Ot6RevealCommit
                                ;   moves pending into OT6_REVEALED_ELEM (and
                                ;   every same-species slot) at the numeral.
        ; learn it forever: codex entry = everything known so far, pending
        ; included (seed merged the old codex bits in, so this is monotonic).
        ; species is a word: pin i16 for the load.  under the caller's
        ; i8 the ldx truncated species >= $100 onto the wrong codex
        ; slot (m1 latent bug; guard/lobo were too small to catch it).
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
        lda     #$ff                       ; #48: and bank the flash as pending;
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
        ora     OT6_RVPEND_CLS-8,y      ; #33: banked this action is not new
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
merge:  lda     OT6_SCR_BIT     ; bank the matched class as pending (#33):
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
        lda     #$ff                       ; #48: flash pending (see Ot6BreakArm)
        sta     OT6_BRKTICK-8,y
done:   rts
.endproc

; ------------------------------------------------------------------------------

; [ commit pending reveals on the damage frame: per-species, one frame (#33) ]
;
; the chips above run at damage calc, inside CalcAttackEffect's per-target
; loop; the damage the player sees lands when GfxCmd_0b allocates its numeral
; thread, hundreds of frames later (measured on the shipped ROM,
; probe_clockwork: hp/reveal writes f704-705, first numeral f1006, so the '?'
; flipped ~300 frames before any number appeared).  so the chips bank into
; OT6_RVPEND_* and this walker moves pending into the revealed bytes:
;   - called from GfxCmd_0b's entry (C1 shim), the damage frame proper;
;   - and from Ot6ActionEnd, the backstop for numeral-less actions, so
;     pending never outlives the action that banked it.
; the codex is per-species, so the commit writes every same-species slot's
; revealed byte in the same pass, and all siblings' icons appear on one frame
; (the display agreeing with the knowledge model, issue #33's third
; requirement).
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
        lda     #$7e            ;   is not ours to assume.  measured: without
        pha                     ;   this the walker read junk species and
        plb                     ;   wrote outside battle RAM, and the
                                ;   Vargas fight locked up the moment a monster
                                ;   hit 0 hp: deaths never completed, no
                                ;   menu ever reopened (probe_vargasstall:
                                ;   24000 frames at menu=00 vs 6737 to
                                ;   ipoohs-down on the pre-change ROM).
        ldy     #$0000          ; source monster slot offset 0,2..10
@src:   lda     OT6_RVPEND_ELEM,y
        ora     OT6_RVPEND_CLS,y
        beq     @next           ; nothing pending for this slot
        ldx     #$0000          ; sibling slot offset
@sib:   longa
        lda     OT6_SPECIES,x
        cmp     OT6_SPECIES,y
        shorta                  ; plain SEP #$20; shorta0's `tdc` sets Z from
                                ;   D and would wipe the compare.  measured, not
                                ;   reasoned: with shorta0 here every slot read
                                ;   as same-species, and a dying Ipooh's pending
                                ;   slash propagated onto Vargas (whose row is
                                ;   bludg); battle_vargas's revClass control
                                ;   caught it.
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
        jsr     Ot6BreakArm     ; #48: the break flash rides the same edge, and
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

; [ the break moment: fire every pending monster's break, sound it once (#48) ]
;
; Why it is deferred.  The chips above empty the gauge inside
; CalcAttackEffect's per-target loop, at damage calc, measured hundreds of
; frames before the player sees anything (probe_clockwork, #33: calc f704 vs
; first numeral f1006).  Flashing there would fire the effect while
; the attacker was still winding up.  So the chips bank $ff in OT6_BRKTICK and
; this proc converts pending into a live flash on the damage frame, which is
; the OT6_PIPPEND / Ot6RvPend* shape #33 and #42 already established.
;
; The cleave is not conditional on the flash (#63).  Ot6BreakStart returns
; carry for "a break happened at this monster", which is a weaker condition
; than "the flash armed": it decides on its own whether it may drive the
; sprite, and on a break that also killed the monster it may not.  This pass
; sounds and pans off the weaker condition, so the break is not silent
; merely because the death animation owns the palette.  See there.
;
; The sound is once per pass, not once per slot.  Two monsters broken by the
; same action arm on the same numeral and share one cleave; a multi-hit action
; cannot double it either, because a chip only banks pending when
; OT6_BROKEN_TICKS is still zero, so hits 2..n of a combo find the target
; already broken and bank nothing.
;
; The sfx id is borrowed deliberately.  $be is vanilla's
; Odin/Raiden cleave (btlgfx_main.asm:26049-26055, the only site that plays
; it), which makes it the heaviest single-impact sound in the battle bank that
; is not already used by something a player hears every fight: $a0 is
; every connecting swing (BlockSfxTbl, :27078), $2d is a monster dying (:22295)
; and would read as a kill, and $0d is the whiff.  Odin is not obtainable until
; the WoR Ancient Castle, so through the whole supported part of the game this
; sound has no prior meaning to overwrite.  It is one constant (OT6_BREAK_SFX)
; if the owner wants a different one after hearing it.
;
; It is queued by writing PlayAnimSfx's own four bytes (btlgfx_main.asm:3175-
; 3182) rather than by jsl-ing that routine, because PlayAnimSfx takes its pan
; in direct-page $10 and this proc does not own $10 in either of its contexts.
; The pan is the broken monster's screen x, which is vanilla's own idiom for a
; monster-local sound (the death animation pans to w7e80c3 the same way,
; :22287-22294), so the cleave comes from where the enemy is standing.
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
        bcc     @next           ;   here (#63: the flash may still have been
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

; [ start one monster's break moment; y = monster slot offset (#48, #63) ]
;
; The pending byte is consumed on every path, armed or not: a pending flash
; must never outlive the action that banked it (Ot6PipPending's rule).
;
; Two tiers, and #63 is what forced the split.  A break is an event that
; happened at a place on the screen, and the cleave is sounded from here
; whatever the sprite is doing.  The white flash additionally has to own the
; sprite, and is refused on its own, without a message, when it cannot.
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
; Why the split, measured (#63).  v0.8-rc1 shipped all four of these as one
; refusal, so a break whose blow also killed produced nothing: no flash and
; no sound.  That is the common case in play rather than a corner: the
; breaking hit collects vanilla's elemental x2 and then Ot6BrokenDmg's x2, 4x
; base, and this file's own trash-pass note already recorded that nothing on
; Mt. Kolts except tusker has the hp to survive its own break.  probe_breakplay
; drove the same entry point battle_breakflash uses with hp left unpinned
; and caught the refusal directly (hp=0000, status $80, Ot6BreakStart refused
; at the hp gate, zero cleaves queued), while the two cells that kept the
; monster alive both armed and both queued their $be.  The flash is still
; correctly refused on a kill; what was wrong is that the event went silent
; with it, which is what the owner reported as "no effect happening when i
; break enemies".
;
; Not the cause, and ruled out by the same probe rather than by argument:
;   - "the arm only runs when a reveal is pending".  Ot6RevealPoll calls
;     Ot6RevealCommit on every damage-numeral edge (:Ot6RevealPoll below,
;     ot6_hud.asm:204) and Ot6BreakArm rides its tail unconditionally,
;     measured at 5 to 9 passes per staged break, including passes with
;     nothing pending at entry.  Breaks landing on a hit that revealed
;     nothing new armed normally.
;   - palette-3 contention with vanilla's own turn flash.  A cell with
;     vanilla's per-monster turn-flash latch (w7e618b) deliberately left
;     unpinned (battle_breakflash pins it as a control) armed and
;     flashed normally.
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

; [ fill the engine's flash palette slot with white (#48) ]
;
; Obj palette 3 == w7e7e00::_11 == $7e7f60 (btlgfx_ram.inc:672 declares the
; array as 16 palettes of 32 bytes; the sprite drawer resolves a monster's
; palette number to w7e7e00::_8 + n*32 at btlgfx_main.asm:4294-4296).  It is
; the engine's own scratch for exactly this: flash_color_set writes it for the
; attacker flash (:23440) and MonsterDeathPal is loaded into it for the death
; fade (:22264).  Nothing else can be pointing at it, because monsters are only
; ever assigned palettes 0/1/2 (:4917-4921).
;
; No extra vblank traffic, which is the #33 constraint this had to clear.
; The PPU update DMAs sprite palettes as one unconditional fixed $100-byte
; block from w7e7e00::_8 every frame (btlgfx_main.asm:1512-1518), so the whole
; effect (the palette and the w7e80db repoint the OAM builder reads) is WRAM
; writes that ride transfers the engine was making anyway.  Measured, not
; assumed: see battle_breakflash's nmi budget phase.
;
; $7fff is white in BGR555; colour 0 stays transparent by the PPU's own rule,
; so the monster reads as a solid white cut-out: the critical flash's colour,
; scoped to one enemy, which is the owner's direction for #48.
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

; [ drive every live break flash, one main-loop frame (#48) ]
;
; Called from Ot6BgHud_ext, the frame ticker #33 established for this
; kind of work: our own context in bank F0 with db=$7e, outside the C1 battle
; script engine whose re-entrancy around WaitFrame locked up the fight the last
; time OT6 ran a walk inside it (see Ot6RevealPoll's header).
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
; It is not called at all when nothing is flashing, and the gate lives inline at
; the call site rather than at the top of this proc, because `jsr` plus one load
; here (20 cycles) was already over budget while 12 bare NOPs were not.  The
; margin is that small; the whole measurement is written up at OT6_BRKLIVE in
; ot6_memory.inc.  The walk recomputes OT6_BRKLIVE from what survives each
; tick, so a stale flag costs one walk and the byte needs no init
; clear.
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

; [ the damage-frame trigger: poll the numeral counter, main loop (#33) ]
;
; Why a poll and not a hook in GfxCmd_0b.  The obvious site is that command's
; own entry, since it is the numeral, and that is where this first landed.  It
; locks up the fight: measured with probe_vargasstall on the Vargas formation,
; the moment any monster reached 0 hp the battle stopped (menu=$00,
; mstate=$00, deaths never completing, 24000 frames and counting) against
; 6737 frames to ipoohs-down on the pre-change ROM.  Bisected in three builds:
; the same hook replaced by four NOPs runs clean, the hook with the walker
; body skipped runs clean, and the walker body (even with its reveal stores
; removed, leaving only the species walk and the pending clear) locks up.  So
; the defect is executing this walk inside the C1 battle-script engine, whose
; re-entrancy and register/stack contract around its WaitFrame yields this
; code does not own.  The cause below that is not established; the boundary is,
; so the work moved to our own context and stays out of the engine.
;
; The trigger is equivalent and observable: GfxCmd_0b's first act is to
; advance the numeral thread counter $632e, so a change in that byte since
; the last main-loop tick means a numeral was allocated, i.e. the damage frame.
; The hud builder already runs every main-loop frame in bank F0 with DB=$7e,
; which is the context the walk wants, and battle_clockwork pins the
; resulting timing (the commit lands on a numeral frame, and after the damage
; calc that banked it).  Cost: at most one frame later than the hook would
; have been, against a lock-up.
;
; the shadow byte is not init-cleared (it sits past InitBP's clear); a stale
; value costs one spurious commit at battle start, which finds pending empty
; (Ot6SeedShields zeroes it per slot) and does nothing.
; a8/i16, db=$7e (Ot6BgHud_ext's own context).  preserves x/y.
; out: carry set if this tick saw a numeral (#42).  The counter can only be
; consumed once, and #42 needs the same edge to commit a deferred cover pip, so
; the edge is reported rather than duplicated into a second last-seen byte, and
; the one caller (Ot6BgHud) fans it out.
.proc Ot6RevealPoll
        .a8
        .i16
        lda     f:$7e0000+$632e         ; damage-numeral thread counter
        cmp     f:$7e0000+OT6_NUMCTR
        beq     @done                   ; no numeral since last tick
        sta     f:$7e0000+OT6_NUMCTR
        jsr     Ot6RevealCommit
        sec                             ; #42: the numeral frame, reported
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

; the sturdiness half of the break loop (measurement #5): while a monster
; has shields remaining and is not broken, every damaging hit it takes is
; multiplied by Ot6ShieldedMulW/16. one global knob, no per-species
; column until a sweep calls for one. the resulting ordering is the design:
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
                                ;   measurement #5 settled on 0.5x: it makes
                                ;   the damage-per-BP ladder a clean doubling
                                ;   (broken:weak:unweak = 4:2:1), so boosting
                                ;   to break and hitting the weakness both
                                ;   pay and boosting into shielded-unweak is
                                ;   visibly the worst return. 0.75x/1x flatten
                                ;   the ladder (at 1x a weakness hit ties a
                                ;   broken one, so there is no reason to
                                ;   break).  measurement #7 re-swept it under
                                ;   a playtest that read as "the loop doesn't
                                ;   matter" (1x/0.5x/0.375x/0.25x/0.1875x/
                                ;   0.125x x 4 policies x 2 pools) and kept
                                ;   0.5x: on the mt kolts pool, mashing loses
                                ;   3 of 6 encounters here while engaging the
                                ;   loop wins 6/6 and takes 40% less damage,
                                ;   so lowering it only deepens a hole the
                                ;   playtester already fell into. what reads
                                ;   as "the loop doesn't matter"
                                ;   on early trash is not this constant;
                                ;   it is that formula species carry no class
                                ;   weakness (@formula clears OT6_BP_CLASS), so
                                ;   fight/tools chip nothing and the break
                                ;   never fires. that is Ot6ShieldTbl
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
; (:103-112), and only QuetzEffect (:1814-1822) ever purges an entry.
; Measured on battle 70 before this change, through real play in
; tools/tests/battle_brokendeath.lua: 11 commands dispatched by a Broken Ifrit
; inside one fight, 8 of them Cmd_2e and 3 of them Cmd_02 MAGIC, which is Fire
; out of his `if_hit` script (ai_script.asm:4613-4616) while he wore the broken
; shield.  21 turns began with his timer up, 19 of them counterattacks.
; Ot6Gate itself was working; the turns were leaking past it.
;
; So this asks the same question at execution time, from one site: CheckRetal
; (battle_main.asm:12762), +6 bytes.  A Broken monster creates no
; counterattack, which is the design's ruling in
; docs/design/bosses-wob.md:34-37: a Broken enemy loses its counters along with
; its turns.  Where it sits is load-bearing twice over and the call site gives
; both reasons.  tools/tests/battle_brokendeath.lua guards them.
;
; One site rather than two, and that is a frame-budget decision rather than a
; design one.  945b9ed also hooked ExecAction's pre-dispatch check (:274),
; replacing the `lsr` of the value just stored, which is the site that would
; cover the $3820 action-queue drain.  It cannot land.  The $C2 action path
; has under 18 cycles of slack, and going over costs a missed vblank per
; battle-loop iteration, which battle_trueknight phase 4b sees as its covers
; span jumping 1635 -> 1798.  Measured on this branch, five builds, same
; fixture:
;   pre-change ..................................... 1635  PASS
;   this change, CheckRetal only ................... 1635  PASS
;   + the ExecAction hook .......................... 1798  FAIL
;   CONTROL: 9 bare NOPs at the ExecAction site .... 1798  FAIL
;   CONTROL: 9 unreachable bytes before ExecAction . 1635  PASS
; The two controls settle what it is.  Both grow battle_code by the same 9
; bytes to $652c; the executed one fails and the unreachable one passes.  So
; it is cycles on the action path, not bank $C2's size and not its layout.
;
; What one site leaves open, measured rather than assumed.  The action queue
; is still ungated at execution, so a turn queued before the break lands
; drains into ExecAction (battle_main.asm:150-159) and runs.  ExecAction also
; runs the monster's AI script before any dispatch -- the `cmp #$1f` arm calls
; ExecMonsterAction (:238) and loops back to @0100 -- so that turn's script
; side effects land either way, including the kill_monsters/show_monsters pair
; that performs the Ifrit/Shiva tag.  Measured after this change on the same
; fixture and driver as the before-run: 0 commands dispatched by a Broken
; actor against 11 before, and one turn that began with the timer up, ran its
; AI script, and dispatched nothing.  The ExecAction hook would have refused
; that turn's dispatch but not its script, so it buys less than it looks like
; it does.  Closing the rest needs the queue entry purged at break time
; (QuetzEffect's walk, battle_main.asm:1814-1822), which spends bank $F0
; cycles rather than $C2 ones.  Gating earlier inside ExecAction is not the
; answer either: @01a6's `lda $32cc,x / inc / bne @01d5` (:288-290) would
; re-enter ExecAction forever on a command list that never got consumed.
;
; Characters can never trip it.  Ot6Chip refuses entity < $08
; (ot6_break.asm:843-845) and InitBattle's $3a20-$3ed3 clear
; (battle_main.asm:6132-6133) zeroes the character rows of
; OT6_BROKEN_TICKS, so their byte is always $00.
;
; Index width is irrelevant here, since abs,x is one encoding either way.
; Accumulator width is not, and this proc cannot php/plp its way out of
; caring, because plp would restore the very carry it exists to return.  a8 is
; required: under a 16-bit accumulator `lda OT6_BROKEN_TICKS,x` would pull the
; word $3e88/$3e89, broken ticks together with the revealed-element mask, and
; any revealed weakness would read as "broken".  The call site is a8 and that
; is checked rather than assumed: CheckRetal opens 8-bit (`stz $b8 / stz $b9`,
; battle_main.asm:12737-12738) with its own longa/shorta pairs around the
; target words (:12746-12754), the last closed by the `shorta` at :12754,
; two instructions ahead of the branch that leads here.
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

; ------------------------------------------------------------------------------
; (m1's monster-window shield digit, the $3ecb row-glyph buffer, its
; builder, and the MenuTextCmd_0b glyph hook, are retired: they were
; redundant with the under-enemy hud and read as an enemy count.
; $3ecb-$3ed3 stays ours; the odd bytes below still serve as scratch.)
