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
; the v0.3 arc added ARMOR-LINE rows here under a doctrine the v0.6
; break-coverage pass has since RETIRED. the doctrine was the narshe
; school's rung-2 seed: "their armored machines shrug off blade and fire
; alike ... every armor fears one right tool" (narshe-school.md history),
; the tool being edgar's bio blaster (item $a4 -> attack $7d, element $08
; poison -- battle_main.asm:6577). that made POISON the sole key to the
; imperial line, and the fixed-party audit found the hole: the forced
; parties that fight this line -- Cyan solo at Doma, Sabin's whole
; scenario, Locke solo in South Figaro, two of the three Narshe squads --
; carry no Edgar and so no poison, and could not break armored trash at
; all. v0.6 moves the SOLDIER LINE onto weapon-CLASS rows in Ot6ShieldTbl
; (pierce/slash/bludg, chosen per the party that actually fights each --
; the decode and rationale live there and in bosses-wob.md). poison is
; now one Edgar key among several, not the one; the school's old "shrug
; off blade / one right tool" seed contradicted the new fiction ("a blade
; finds the gaps"), so it took a dialog revision under the school's own
; sanction (2026-07-22, narshe-school.md) -- $0276 now teaches "every
; plate has its seam ... bring the weapon that fits."
;
; what REMAINS poison-keyed in this table are the two MACHINES, where a
; party that fights them can actually cast it, each row keeping every
; vanilla bit (decoded from monster_prop.dat at species*32 +$19; the
; offset is vanilla's own -- battle_main.asm:7517 loads MonsterProp+25):
;
;   $042 m-tekarmor  +$0859  vanilla $04 bolt        -> $0c bolt|poison
;   $09f heavyarmor  +$13f9  vanilla $84 bolt|water  -> $8c (+ slash|pierce
;                            class in Ot6ShieldTbl)
;   $002 templar     +$0059  vanilla $08 poison      -> $0c bolt|poison
;                            (+bolt: metal conducts, Shadow's Bolt Edge;
;                            + a pierce class row in Ot6ShieldTbl)
;
; leader ($14e) and grunt ($14f) had poison ADDS here in v0.3 -- they had
; no vanilla weakness of any kind, so poison was their only gauge -- and
; v0.6 REMOVED both: their forced fights (Cyan's solo duel; Cyan+Sabin's
; Doma courtyard defense) carry no poison, so the add was dead data that
; also drew an unresolvable '?' on a swordfight. both are class-keyed now
; (leader slash; grunt slash|bludg -- Ot6ShieldTbl).
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
; EVERY row here was checked against +$17 (absorb) and +$18 (null) before
; authoring; every one reads $00/$00 (templar included), so no row here
; puts a chip trigger on an absorber. that check is not ceremony -- it is
; the exact error bosses-wob.md caught twice in draft (nerapa listed fire,
; which it absorbs; the cranes' absorb pair was read as their weak pair).
;
; ---- the v0.3 TRASH pass: six rows that make the break happen ----
;
; everything above is a boss or a set-piece. these six are ordinary
; random encounters, and they exist because measurement #7 established
; that the break -- the mechanic this hack is named for -- had never once
; happened in play: `player_actions_broken` was 0.0 across 168 battles,
; because every species without an authored row takes Ot6SeedShields'
; @formula path, which CLEARS $3e9c (:76-85), so formula trash carries no
; class weakness and most of it carries no reachable element either.
;
; WHY ELEMENT ROWS AND NOT Ot6ShieldTbl CLASS ROWS. the party that walks
; this stretch is terra, locke and edgar, and they arrive at mt. kolts
; carrying a mithril knife, a dirk and a mithril blade (char_prop.asm:152,
; :162, :197) -- which ot6_class.asm:49, :48 and :59 make PIERCE, PIERCE
; and SLASH. so the party's three default swings already cover half the
; class ring, and the other half has no wielder at all: bludgeoning
; arrives with sabin, who joins at the TOP of the mountain, and special
; not until setzer. a class row on this stretch is therefore either a
; FREEBIE (slash/pierce -- holding A chips it, which is measurement #7's
; own +PIERCE finding: the mash arm started chipping by accident and the
; mash-vs-loop gap CLOSED) or a REPO MAN (bludg/special -- nothing in the
; party can chip it, and the fight has no loop at all). the class axis is
; degenerate here. the element axis is not: terra's fire costs 4 mp and a
; magic menu, edgar's bio blaster costs a tools dive (item $a4 -> attack
; $7d, magic_prop_en.dat record $7d: element $08, targets $6a = ALL
; enemies, power 20, 0 mp), and NEITHER of them is what the A button does.
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
; four of those six had NO weakness the stretch party could reach --
; cirpius and rhodox had no weakness at all, sand ray and areneid are
; ice|water and nobody carries either (terra's natural list is cure 1,
; fire 3, antdot 6, drain 12 -- field/event.asm:1248-1251, so FIRE is her
; whole offensive element ring at this point in the story). they are the
; coverage rule's live counterexamples on the route the v0.2 demo ships,
; and cirpius is the worst of them: it is 93.75% of the draws on mt.
; kolts maps 95/96/97 and it comes THREE AT A TIME, so the mountain's
; most common fight was three unchippable birds.
;
; the two that already had fire are here for a different reason, and it
; is arithmetic. an element chip that empties the last shield takes
; vanilla's weak x2, then skips Ot6ShieldedDmg (shields are already 0),
; then takes Ot6BrokenDmg's x2 -- 4x base on the breaking hit itself. at
; terra's ~110 base that is ~440, and NOTHING on this mountain except
; tusker has the hp to survive its own break through the fire channel.
; bio blaster's per-target damage is a fraction of that (power 20, split
; over the whole enemy side), so poison is the channel that can open a
; window instead of closing the fight. tusker at 270 hp is the one body
; big enough for that window to be wide, which is why it gets poison on
; TOP of vanilla's fire: fire stays the burst answer to a 270-hp wall,
; poison becomes the break answer, and the player picks.
;
; and the shelf-F read that falls out of it, which is the best accident
; in this table: brawler ($00b) ABSORBS poison (+$0177 = $08). map 100
; draws brawler-pair 62.5% and tusker-pair 37.5%, so on the same shelf the
; same tool breaks one formation and HEALS the other. brawler's answer is
; a class row in Ot6ShieldTbl instead (see there); the trap is vanilla's
; own byte and stays untouched.
;
; every one of the six was checked at +$17/+$18 the same way the boss rows
; were. five read $00/$00; rhinotaur absorbs BOLT (+$02B7 = $04) and nulls
; nothing, so poison is clear on it too. no row here feeds an absorber.
;
; deliberately NOT authored, so the next author does not re-litigate:
;   - trooper ($065, +$0cb9 = $08) and rider ($03f, +$07f9 = $09) are
;     already poison-weak in VANILLA, so no ELEMENT add is authored for
;     them. but v0.6 DID give both a slash|pierce CLASS row (Ot6ShieldTbl):
;     the Narshe defense is a player-assigned 3-way split, and the squads
;     without Edgar (e.g. Cyan+Sabin, Locke+Gau) reach neither poison nor
;     any vanilla element on these bodies -- only a weapon class. vanilla
;     poison stays the Edgar-squad's key; the class row is every other
;     squad's. formation 88 (trooper+heavyarmor) now opens to whatever a
;     squad holds, not to Edgar alone.
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
;   - the stretch's ALREADY-FIRE-WEAK trash: leafer ($017 +$02F9 = $81),
;     dark wind ($028 = $01), hornet ($02e = $01), bleary ($063 = $01),
;     crawly ($062 = $01), trilium ($032 = $01), vaporite ($046 = $21).
;     the coverage rule is already satisfied for every one of them by
;     terra's fire, and a SECOND key would only make the probe a formality.
;     none of them can hold a break window either -- 33 to 147 hp against
;     a 4x breaking hit -- and measurement #7 proved that directly on
;     leafer: a synthetic class row there produced 0.7 breaks a fight and
;     every one landed at 100% of fight length, `player_actions_broken`
;     still 0. these are texture, not tuning material, the same
;     disposition measurement #1 gave the mines pool.
;   - brawler ($00b) is the one species on the mountain that gets a CLASS
;     row rather than an element one, because poison is the one element it
;     must not have (it absorbs it, +$0177 = $08) and its vanilla ice
;     (+$0179 = $02) has no wielder until celes. see Ot6ShieldTbl.
;   - greasemonk ($0a8 +$1519 = $08) is already poison-weak in VANILLA, so
;     the south-figaro plains had one live key before this pass and an
;     add here would be a no-op ora that lies about who authored it --
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
        ; the armor line -- v0.6 break-coverage pass (block comment above).
        ; the soldier line is CLASS-keyed now (Ot6ShieldTbl); what stays
        ; here is poison on the two MACHINES plus templar's conducting bolt.
        .word   $0042
        .byte   $08, $00        ; m-tekarmor: + poison (keeps bolt; Shadow's
                                ;   Bolt Edge is the live camp key)
        .word   $009f
        .byte   $08, $00        ; heavyarmor: + poison (keeps bolt|water;
                                ;   Edgar's key at the Narshe waves. ALSO a
                                ;   slash|pierce class row -- Ot6ShieldTbl)
        .word   $0002
        .byte   $04, $00        ; templar: + bolt (vanilla $08 poison ->
                                ;   $0c bolt|poison; metal conducts, Shadow's
                                ;   Bolt Edge. ALSO a pierce class row)
        ; the arc's stop line, and the scenario boss that had no key
        .word   $014a
        .byte   $09, $00        ; kefka (narshe defense): + poison|fire
        .word   $0104
        .byte   $02, $00        ; tunnelarmor: + ice (keeps bolt|water)
        ; the v0.3 trash pass -- the break made reachable in ordinary
        ; fights. poison is edgar's bio blaster, the stretch's only
        ; deliberate key the A button does not already swing.
        .word   $0086
        .byte   $08, $00        ; cirpius: + poison. had NO weakness at
                                ;   all, and it is 93.75% of mt. kolts
                                ;   maps 95/96/97 THREE at a time -- one
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
                                ;   body (absorbs BOLT, not poison)
        ; ---- the v0.4 SEARCH-FOR-TERRA corridor: five poison rows for the
        ; western-WoB overworld the party roams looking for terra before Zozo.
        ; the party is LOCKE+CELES+EDGAR+SABIN and its two DELIBERATE keys are
        ; poison (edgar's bio blaster) and ice (celes) -- there is NO fire,
        ; terra is the search target. these five draw across the western/
        ; southern WoB sectors and every one is a coverage hole: no vanilla
        ; weakness of ANY element, and a formula species carries no class
        ; weakness, so before this row the terra-less party could not chip them
        ; at all. poison is the natural key (a Tools dive, not the A button) and
        ; the group target answers the packs. verified against monster_prop.dat
        ; +$19/$18/$17 -- weak/null/absorb all read $00 on all five, so no row
        ; here feeds an absorber (the GhostTrain trap):
        ;   $018 stray cat  156 hp    $01d baskervor 750 hp
        ;   $01f chimera   2237 hp    $078 red fang  325 hp
        ;   $07b ralph      620 hp
        ; NOT poisoned, because they already have a reachable answer and poison
        ; would be the WRONG one: iron fist $06c ABSORBS poison (+$0d97 = $08)
        ; and wears a class row in Ot6ShieldTbl (locke's pierce / sabin's
        ; bludg); fossilfang $023 ABSORBS poison too but is ICE-weak, which
        ; celes casts, so ice is its key. sand ray $05c / areneid $05d are
        ; already +poison above AND ice-weak. the desert half of this region is
        ; covered without a row here.
        ; UNMEASURED, and said plainly: no world-map fixture stands in this
        ; region (the search arc is not on any minted state), so these five are
        ; coverage on the same census+arithmetic footing measurement #8 gave the
        ; figaro-desert rows -- shields left to the formula, element table only
        ; (no HpScale exemption), numbers to be taken once a corridor fixture is
        ; minted. THE FIRE HOLE, flagged: a few western-WoB bodies are fire- or
        ; wind-weak ONLY ($090 fire, $08c fire|wind, $02a wind) and this party
        ; casts neither, so their vanilla weakness is dead for it. they are left
        ; as-is rather than blindly double-keyed: whether they even sit on the
        ; walked route is exactly what the missing fixture would settle. see
        ; measurement #9.
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
OT6_DIVINE_USED := $3ecb        ; per-character once-per-battle divine latch
                                ;   (----1234, the $3f2f "desperation used"
                                ;   precedent): bit set = that character has
                                ;   spent their kit-8 divine this battle. lives
                                ;   in the retired row-glyph buffer byte (the
                                ;   ONE byte of the $3ecb-$3ed3 scratch range
                                ;   the OT6_SCR walkers never touch -- they own
                                ;   $3ecc-$3ed3 as words). InitBattle's
                                ;   $3a20-$3ed3 clear zeroes it on every fresh
                                ;   battle, and a Cmd_20 scene-change reload
                                ;   (which skips that clear) deliberately keeps
                                ;   it -- a multi-phase boss is ONE battle, so a
                                ;   divine spent in phase 1 stays spent. NOT
                                ;   $3f2f itself: vanilla's low-HP fight trigger
                                ;   still writes that byte (battle_main.asm:3432
                                ;   tsb $3f2f), so a random desperation would
                                ;   otherwise lock a divine out.
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
        sta     f:$7e0000+OT6_SCRIPTBUSY ; nor a stuck anchor-adopt gate
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
        lda     $b1             ; counterattacks never boost: they execute
        lsr                     ;   through ExecRetal, which sets $b1.0
        bcs     done            ;   (battle_main.asm:12435) and ends at an
                                ;   UNHOOKED EndAction -- so the pending
                                ;   would be delivered but never charged.
                                ;   a black belt counter with pending 3
                                ;   measured 7 swings, free
                                ;   (probe_ctrboost).
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
.if OT6_MP_COSTS
; ------------------------------------------------------------------------------

; [ price a costed verb's action at queue time (v0.4 -- OT6_MP_COSTS) ]

; the "one dispatch change" docs/design/mp-economy.md's M4 note predicts.
; vanilla's GetMPCost (battle_main.asm) returns a cost only for magic, lore,
; summon and x-magic; every other command -- blitz, bushido, tools, the free
; floor, the free-exception verbs -- falls through it returning 0, so the
; universal charge at CalcAttackEffect (the $3a4c subtract, and its
; insufficient-mp FIZZLE) never fires for them. this hook runs on the same A
; the queue store consumes, right after GetMPCost: for the three costed verbs
; it swaps the 0 for the kit price, keyed by the resolved id ALREADY sitting
; in $3a7b at queue time --
;   blitz  ($0a): attack id  $5d-$64   (FixPlayerAttack's +$5d)
;   bushido($07): attack id  $55-$5c   (FixPlayerAttack's +$55)
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
; BioBlaster.) confirmed absolute (owner, 2026-07-22): only the basic Fight
; command is free; every other verb costs MP as its kit comes online.
;
; the charge AND the refusal are BOTH already universal (they act on whatever
; $3620 -> $3a4c holds); the ONLY magic-specific piece is the menu grey-out /
; cost display (CheckMagicEnabled), which is the menu-bank work this whole
; flag waits on. that is why a hidden charge must not ship enabled: the menu
; still shows these verbs no number.
;
; boost never raises the price: blitz and tools keep one id no matter the
; boost, and a boosted bushido has already queued the tech its BP bought
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
        cmp     #$07
        beq     @costed         ; bushido
        cmp     #$09
        beq     @costed         ; tools
        cmp     #$0a
        beq     @costed         ; blitz
        pla                     ; some other verb: hand back vanilla's cost
        plp
        rtl
@steal:
        pla                     ; drop the parked cost (0 for steal)
        lda     #$02            ; flat 2 MP -- the probe-collect verb prices
        plp                     ;   like the cheapest spell (mp-economy.md)
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
; $3a7x. keys are disjoint per verb (blitz $5d-$64, bushido $55-$5c, tools
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

; (key, cost) pairs, $ff terminates. keys are exactly the id already in $3a7b
; at queue time, disjoint across the three verbs. numbers are docs/design/
; kits.md's per-row columns priced on docs/design/mp-economy.md's rulers:
; the vanilla spell scale (Fire 4, Fire 2 20, Fire 3 51), sabin's ~3-mp base
; pool sizing the floor of every ladder, and "free-to-learn is not
; free-to-use" -- a signature is the CHEAPEST row of its kit, never costless.
Ot6AbilityCostTbl:
        ; -- Blitz (Sabin), cmd $0a, attack ids $5d-$64. mp-economy.md:
        ;    "scaled by tier 2-30: Pummel 2-3, mid-kit 6-15, Bum Rush at top".
        .byte   $5d,  2         ; Pummel     L1  signature -- cheapest row
        .byte   $5e,  5         ; AuraBolt   L6  holy chip
        .byte   $5f,  7         ; Suplex     L10 bludgeon
        .byte   $60,  9         ; Fire Dance L15 fire, all
        .byte   $61,  8         ; Mantra     L23 party heal (utility, off-ramp)
        .byte   $62, 12         ; Air Blade  L30 wind, all
        .byte   $63, 18         ; Spiraler   L42
        .byte   $64, 30         ; Bum Rush   L70 divine, bludgeon x8 -- the top
        ; -- Bushido (Cyan), cmd $07, attack ids $55-$5c. kits.md left this
        ;    column TBD; PROPOSED here from the BP-tier structure. ruling
        ;    (mp-economy.md): "BP tier + discounted MP 1-8" -- the BP ladder
        ;    is the real price, so MP rides ~1/3 of a comparable blitz/tool.
        ;    monotonic with the BP band (0->1, 1->2-3, 2->4-5, 3->6-8).
        .byte   $55,  1         ; Fang     BP0 signature -- the game's cheapest
        .byte   $56,  2         ; Sky      BP1 counter stance
        .byte   $57,  3         ; Tiger    BP1 slash
        .byte   $58,  4         ; Flurry   BP2 slash x4 (Air Blade 12 -> ~1/3)
        .byte   $59,  5         ; Dragon   BP2 drain
        .byte   $5a,  6         ; Eclipse  BP3 slash, all
        .byte   $5b,  7         ; Tempest  BP3 wind x4
        .byte   $5c,  8         ; Oblivion BP3+Broken divine -- out of the
                                ;   ladder until the divine pass; priced ready
        ; -- Tools (Edgar), cmd $09, tool ITEM ids $a3-$aa. mp-economy.md:
        ;    "scaled by tier 3-20: AutoCrossbow 3-4, Drill/Chainsaw 12-20,
        ;    Debilitator 8-12". gil buys the tool once; MP is the per-use cost.
        .byte   $aa,  4         ; AutoCrossbow signature, piercing x4 shredder
        .byte   $a3,  6         ; NoiseBlaster confuse
        .byte   $a4,  8         ; BioBlaster   poison, all -- the armor-break key
        .byte   $a5,  6         ; Flash        blind, all
        .byte   $a8, 16         ; Drill        armored-boss answer, pierce
        .byte   $a6, 18         ; Chain Saw    slashing + instant-death chance
        .byte   $a7, 10         ; Debilitator  adds + reveals a weakness (probe)
        .byte   $a9, 14         ; Air Anchor   mid-kit gag (harpoon / doom)
        ; Overclock (the divine "use two tools") has no single tool item id:
        ; its price is the SUM of the two tools it fires -- wired the day
        ; Overclock is built (kits.md: Magitek-factory story unlock).
        .byte   $ff

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
        bne     @afford         ; >= 256 MP: nothing in a kit costs that much
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
; still fires exactly as before: gated at RESOLUTION by Ot6Oblivion (hooked
; after ChooseTarget -- the target does not exist at this command-latch time,
; swdtech being in RetargetCmdTbl), and dropped back to tempest (6) here for
; the rest of any battle whose once-per-battle latch is already set. cyan
; learns oblivion off the phantom train, so the top rung is oblivion only at
; full kit.
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
        lda     $3e9d,x         ; pending boost 0-3
        cmp     #$04
        bcc     :+
        lda     #$03            ; (defensive: Ot6Boost already caps at 3)
:       pha                     ; park boost. the two scratch bytes in reach are
                                ;   both somebody's — $36 is btlgfx's (and only
                                ;   the display call site rewrites it right after
                                ;   us; the latch site does not), and OT6_SCR_BIT
                                ;   is the hud builder's. the stack owes nobody
                                ;   and survives an nmi.
        lda     $2020           ; techs known - 1 (the ceiling), LOW BYTE ONLY
                                ;   (issue #4). InitSkills stores it with a 16-bit
                                ;   `stx $2020` (battle_main.asm:14532) over
                                ;   CountBits's uninitialized HIGH byte -- $FF02 in
                                ;   the Doma solo fight, $ffff before cyan joins.
                                ;   read as a WORD (the old `ldx`) the junk high
                                ;   byte made even a real 2-tech ceiling `>= 8` and
                                ;   collapse to 0, pinning Cyan to Dispatch. read
                                ;   a8 the junk is ignored, and a genuinely-
                                ;   unlearned $ff (low byte) still trips >= 8 into
                                ;   the nothing-learned path.
        cmp     #$08
        bcc     :+
        lda     #$00            ; nothing learned: only tech 0 (Dispatch) exists
:       pha                     ; park ceiling ($01,s ; boost now $02,s)
        ; --- the moving window of four (issue #5) --------------------------------
        ; boost 0/1/2/3 selects Cyan's TOP FOUR learned techs, weakest ->
        ; strongest: base = max(0, ceiling-3), tech = min(base + boost, ceiling).
        ; while he knows four or fewer, base is 0 and EVERY learned tech is
        ; reachable (0/1/2/3 land on the four he has); learn a fifth and the
        ; window slides up one, retiring the weakest. no table -- pure arithmetic.
        sec
        sbc     #$03            ; ceiling - 3   (A still = ceiling)
        bcs     :+
        lda     #$00            ; ceiling < 3: base floors at 0 (the window is all
:       ;                       ;   of {0..ceiling}, fewer than four techs)
        clc
        adc     $02,s           ; base + boost -> the tentative tech
        cmp     $01,s           ; vs the ceiling
        bcc     :+
        lda     $01,s           ; cap at ceiling -- bites only when boost overruns
:       ;                       ;   a <4-tech window (e.g. 3 bp, 3 techs known)
        sta     $02,s           ; stash the chosen tech over the parked boost byte
        pla                     ; drop the parked ceiling
        pla                     ; a = chosen tech 0-7 (stack balanced)
        ; the window's top rung IS Oblivion (tech 7) once Cyan has learned all
        ; eight: ceiling 7, boost 3 -> base 4 + 3 = 7, by the same base+boost sum
        ; as any other rung -- the divine falls out of the window for free, no
        ; special case bolted outside it. it still fires exactly as before:
        ; SELECTED here only when learned (ceiling 7) and unspent, gated at
        ; RESOLUTION by Ot6Oblivion (hooked after ChooseTarget in CalcAttackEffect
        ; -- the target does not exist at this command-latch time, swdtech being
        ; in RetargetCmdTbl). read the once-per-battle latch here and drop a spent
        ; Oblivion back to Tempest (6) so BP3 keeps a live top rung -- eclipse/
        ; tempest are never retired, they are exactly what a spent-or-unlearned
        ; divine falls to. (a divine is spent only on a broken, killable target;
        ; an unbroken/boss target folds to tempest at RESOLUTION and leaves the
        ; latch clear, so the menu keeps offering it.)
        cmp     #$07
        bne     @level          ; not oblivion: the chosen tech stands
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
        bra     @level
@obl:   lda     #$07            ; oblivion
@level: pha
        asl5                    ; level * 32 — the counter value vanilla's
        sta     $7b82           ;   bar drew, so w7e7b82 still feeds the
        pla                     ;   latch, the fill, and the numerals
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
        lda     $3e88,x         ; broken timer (nonzero = Broken)
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
; gates the sketch names are the Broken check ($3e88 nonzero) and the non-boss
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
        lda     $3e88,x         ; Broken?
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
        lda     $3e9d,x         ; pending boost (0-3)
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
        lda     $3e9d,x         ; pending boost
        beq     @vanilla        ; 0 bp: the exact vanilla roll
        lda     $3308,y         ; slot 0 = rare
        cmp     #$ff
        beq     @common         ; no rare present -> the common is the item
        lda     $3309,y         ; slot 1 = common
        cmp     #$ff
        beq     @rare           ; no common present -> the rare is the item
        lda     $3e9d,x         ; both present: rising rare share by tier
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
; wrote $5762-$5767, leaving the anchor at $00FF; the anchor latch that
; lived at Ot6BgHudLine's @done then drove every NMI flush from $00FF
; for the rest of the battle. The magitek list drawer alone does NOT
; reproduce it (it stops at $5761), which is why a magitek-only fixture
; reads as an all-clear. (The latch has since become recompute-and-
; compare -- see @done -- so an equivalent anchor stomp today would
; self-heal on the next main-loop tick. The relocation stays load-
; bearing all the same: an overlap corrupts continuously in both
; directions, and OT6 writing vanilla's live buffer was the worse half.)
OT6_SHADOW  := $ecf1            ; lines, stride 14
OT6_MAPBASE := $57b6            ; word scratch: field bg3 map base

; [ battle-script bracket: is an animation script executing? ]

; every coordinate transient the animation engine imposes on the monster
; position arrays -- magic_init_131long zeroing/setting the $8057
; priority shifts and displacing $80cf by -$0100 (btlgfx_main.asm:
; 39277-39297), AnimCmd_80_82's all-slot x shove (:29906), AnimCmd_e2/
; e3's per-frame y animation (:33206-33279), the PushObjPos/PopObjPos
; block-hop family (:28045/:28081) -- runs from a battle animation
; script, and every such script executes inside BtlGfx_04 "execute
; battle script" (btlgfx_main @9512): action animations, monster
; specials, entry/exit effects, battle events.  scripts restore their
; transients before they end (PopObjPos restores what PushObjPos saved,
; $80/$84 restores $80/$83's y displacement, $e3 restores from
; w7e64e8), so script-free frames see settled coords by construction --
; and a script that ended WITHOUT restoring has visibly parked the
; monster there in vanilla too, at which point following it is correct,
; not stale.  so the anchor holds while OT6_SCRIPTBUSY is up and adopts
; on script-free frames.
;
; the flag is raised/cleared by the Ot6BtlGfx04_c1 wrapper behind
; BtlGfxTbl's $04 entry (same-size .addr repoint; see the block comment
; there for the C1 layout discipline).  DESIGN HISTORY, measured not
; guessed: the first cut here keyed on tick provenance instead --
; BtlGfx_01 ("called from main battle loop") = settled, WaitFrame
; ("used during animations") = transient, via same-size repoints of
; their two `jsr UpdateCharText` sites.  probe_animtick killed it: with
; a battle menu open, ~101 of 120 idle frames tick through WaitFrame
; (the menu is MODAL inside a gfx command), so the anchor held through
; the whole interactive battle and battle_hudtrack's phase 3 stayed
; red -- the sprite moved, the "recompute" never got a frame it was
; willing to adopt on.  the script container is the discriminator the
; tick path only approximated.

.proc Ot6ScriptBegin_ext
        .a8
        lda     #$01
        sta     f:$7e0000+OT6_SCRIPTBUSY
        rtl
.endproc

.proc Ot6ScriptEnd_ext
        .a8
        lda     #$00
        sta     f:$7e0000+OT6_SCRIPTBUSY
        rtl
.endproc

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
        bcc     @gone           ; slot empty
        ; the slot is filled -- but is the monster ON SCREEN yet?  at battle
        ; entry a monster is flagged present ($3aa8) from init, while its
        ; sprite is not drawn until its fly-in animation runs: the "monsters
        ; shown" mask $201e (notes/battle-ram.txt:422 "--654321 monsters
        ; shown"; the sprite drawers gate on it, btlgfx_main.asm:5639/:5772,
        ; and DoMonsterEntryExit SETS a monster's bit as its entry completes,
        ; :45554) holds 0 for that whole fade-in window -- measured $00
        ; across probe_caveentry f84..128, while the sprites are absent.  the
        ; hud gated only on $3aa8, so it painted each entering monster's
        ; shield/'?' cells into empty space: a scatter of white glyphs on the
        ; still-dark battlefield BEFORE the fight resolved, worst with the
        ; cave's 3-5 fly-in trash (Cirpius/Hornet/Bleary), which is where the
        ; v0.3-rc1 playtest first caught it ("a bunch of characters overdrawn
        ; in white text ... when there are a bunch of enemies").  the entry
        ; ANIMATION itself is already veiled (Ot6EntryExitVeil); this closes
        ; the gap BEFORE it by gating the hud on the same mask the sprites
        ; use.  (a dead monster also clears its $201e bit, but the $3eec
        ; dead-cell path below already blanks that line -- the two agree.)
        phx                     ; save the shadow line base
        longa
        tya
        lsr                     ; monster slot 0-5 (y is the 2-byte offset)
        tax
        shorta0
        lda     f:Ot6ShownBitTbl,x
        plx                     ; restore the shadow line base
        and     a:$201e
        bne     @on             ; present AND shown: draw
@gone:  ; monster gone, or present but not yet entered: disable the line
        ; (flush blanks the old cells once). compare-before-store like the
        ; anchor commit at @done: an already-disabled line writes nothing, so
        ; a static battlefield means ZERO anchor stores across all six lines
        ; -- the exact invariant battle_hudtrack's write watch asserts. (this
        ; store ran unconditionally for years; empty slots were rewriting
        ; $0000 over $0000 every frame, invisible but noisy.)
        longa
        lda     f:$7e0000+OT6_SHADOW,x
        beq     @off
        lda     #$0000
        sta     f:$7e0000+OT6_SHADOW,x
@off:   shorta0
        rts
@on:    ; blank the five cell words, rebuild below. the anchor word at +0
        ; is only committed at the very end (and only when it changes):
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
@done:  ; commit: recompute-and-compare, adopted only on quiet ticks.
        ; HISTORY. this was a once-per-battle latch ("recomputing every
        ; frame made the line jitter and blink on attack-animation coord
        ; transients"), which also made any post-arm divergence permanent:
        ; the founding $5762 overlap corruption (probe_shadow_overlap), a
        ; Cmd_20 reload swapping a slot's monster, any scripted move. the
        ; transients are now READ and NAMED (Ot6ScriptBegin_ext's block
        ; comment lists them with line numbers): every one runs inside a
        ; battle animation script, so the anchor HOLDS while one executes
        ; (OT6_SCRIPTBUSY, bracketing BtlGfx_04) and recomputes on
        ; script-free frames, where coords are settled by construction
        ; (probe_animtick MEASURED the beat: menu-idle frames are mostly
        ; WaitFrame ticks, so tick provenance was the wrong gate -- the
        ; script container is the right one). identical frames
        ; compare equal and write nothing -- the jitter fix -- while a
        ; genuine change (one that survives into a quiet frame) is
        ; adopted within a frame or two -- the staleness fix. gated by
        ; battle_hudtrack (all three directions), hud_stability,
        ; battle_whelkwipe, battle_banner, and the visual goldens.
        ;
        ; the row source is NOT the frame's raw $804b: cur_poi_set
        ; (btlgfx_main.asm:1032, run every frame at :1738) derives it as
        ; $80cf + height*8 - 8 + $8057, and $8057 is a sprite-priority
        ; bias with a PATH-DEPENDENT value -- seeded per species from
        ; MonsterOverlap at monster load (btlgfx_main.asm:4671; whelk
        ; head = 8, guards = 0), zeroed for ALL slots by every $80/$83
        ; animation init (magic_init_131long, :39277), and never re-
        ; seeded until the next monster load (the whelk retract's Cmd_20
        ; reload among them). raw $804b would therefore hop the whelk
        ; head's line one row the first time any spell lands and park it
        ; there. so: strip the LIVE $8057 back out and re-apply the
        ; LOAD-TIME species seed -- exactly the row the latch captured
        ; at arm time, now stable across the whole $8057 lifecycle. the
        ; column source $800f = $80c3 + width*4 has no such term. 8-bit
        ; low-byte reads throughout, as always: transients riding the
        ; high bytes ($80/$83's -$0100 y displacement, stashed/restored
        ; at :39292/:29884) never see us. (the slot-5 leap/seize writer
        ; at btlgfx_main.asm:1133 bypasses monster load, so its species
        ; stash is stale -- unowned territory, same as under the latch:
        ; no WoB-covered content drives it.)
        lda     f:$7e0000+OT6_SCRIPTBUSY
        bne     @keep           ; a battle script owns this frame:
                                ;   coords may be transients -- hold
        phx                     ; save shadow line base
        longa
        lda     OT6_SPECIES,y   ; slot species (== monster index)
        tax
        shorta0
        lda     f:MonsterOverlap,x
        sta     OT6_SCR_BIT     ; the load-time $8057 seed
        lda     $804b,y
        sec
        sbc     $8057,y         ; strip the live priority shift...
        clc
        adc     OT6_SCR_BIT     ; ...re-apply the load-time seed
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
        cmp     f:$7e0000+OT6_SHADOW,x
        beq     @asis           ; unchanged: write nothing at all
        sta     f:$7e0000+OT6_SHADOW,x  ; adopt (atomic word: the enable
                                        ;   is still the commit -- the
                                        ;   nmi flush can fire mid-frame,
                                        ;   and the flush's prev/cur pass
                                        ;   blanks the vacated cells)
@asis:  plx
@keep:  shorta0
        rts
.endproc

; monster slot (0-5) -> its bit in the $201e "monsters shown" mask. slot s is
; bit s: verified by measurement, probe_caveentry read $201e=$1c for the three
; Cirpius that loaded into slots 2/3/4.
Ot6ShownBitTbl:
        .byte   $01,$02,$04,$08,$10,$20


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
; $57be HUDVEIL, $57bf SCRIPTBUSY (HUDVEIL and SCRIPTBUSY init-cleared one
; byte at a time in InitBP).
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
OT6_SCRIPTBUSY := $57bf         ; nonzero = a battle animation script
                                ;   (BtlGfx_04 "execute battle script")
                                ;   is executing, so monster coords may
                                ;   be animation transients. raised/
                                ;   cleared by Ot6ScriptBegin_ext /
                                ;   Ot6ScriptEnd_ext (bank F0, keeping
                                ;   the strip's F0-only writer
                                ;   invariant) from the Ot6BtlGfx04_c1
                                ;   wrapper behind BtlGfxTbl's $04
                                ;   entry. the hud builder holds anchor
                                ;   adoption while set. cleared by
                                ;   InitBP (init-exempt strip: power-on
                                ;   junk would freeze anchor adoption)
                                ;   and self-healing besides: the first
                                ;   completed script clears it.

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
        ; TWO WRITE DISCIPLINES BELOW, on purpose (audit 2026-07-19).
        ; steady-state cell writes (prev == cur) are NOT v-gated: a write
        ; spilled past vblank is dropped by the PPU, and the rewrite-
        ; every-nmi design heals it next frame -- rewriting every nmi is
        ; already mandatory because the animation-bg restore junk-fills
        ; the area every other frame during monster actions (see the
        ; call-site comment, btlgfx_main @0c17). one-shot transitions
        ; (prev != cur: a line moved, enabled at a new address after a
        ; move, or disabled) have NO next-frame rewrite to heal them --
        ; a dropped blank-at-prev would strand stale glyphs -- so they
        ; are admission-gated on the live v counter and DEFERRED when
        ; late: prev only advances after the blank ran inside an
        ; admitted window, so the whole transition redoes next nmi
        ; until it lands. within the window a drop is impossible by
        ; arithmetic: admission ends at v=248, the worst burst (all six
        ; lines + pip transitioning at once) is ~70 words ~ 9 scanlines
        ; at the measured PIO rate (~8 words/scanline, the font-slice
        ; numbers above), ending ~257 < 262. residual accepted risk,
        ; documented not hidden: a transition deferred into a veil
        ; window leaves old glyphs one extra frame if the nmi is ALSO
        ; late -- needs a genuine move adopted on the exact frame an
        ; entry effect starts plus consecutive late nmis; no covered
        ; content produces the first half, and defer-retry bounds it
        ; at frames, not battles.
        ldx     #$0000
@line:  longa
        lda     f:$7e0000+OT6_SHADOW+2,x         ; prev
        beq     @write
        cmp     f:$7e0000+OT6_SHADOW,x           ; moved?
        beq     @write
        shorta0                                  ; one-shot: gate it
        jsr     @late
        jcs     @skip           ; too late: hold prev, redo whole
                                ;   transition next nmi (@skip opens
                                ;   with shorta0, so a8 entry is fine)
                                ;   (long branch: the 16x16-mode veil
                                ;   check grew the body past bcs reach)
        longa
        lda     f:$7e0000+OT6_SHADOW+2,x         ; reload prev (gate ate a)
        sta     hVMADDL                          ; blank the old cells
        ; the blank word is vanilla's $01ee junk fill, NOT $21ff.  cells a
        ; line abandons (a move or a disable) are rewritten ONCE, here, and
        ; then belong to nobody: no next-nmi repaint heals them, so whatever
        ; word this writes sits in the field map until vanilla's next
        ; ClearBG3TileBuf.  $21ff -- priority-set char $1ff -- was invisible
        ; in 8x8 (the char is a blank cell in the $5800 font page), but under
        ; an animation's bg3-16x16 window (the $896f flips the veil below
        ; already handles for LIVE cells) a 16x16 map cell renders char n
        ; plus n+1/n+$10/n+$11: $1ff pulls tiles $200/$20f/$210 -- past the
        ; font page, into the animation-gfx region -- at TOP priority.  the
        ; measured face (probe_lete_entrance, the Lete River forced battle 8,
        ; both die rolls): the monster-entrance slide walks every hud line
        ; sideways across the map, abandoning 63-92 cells ($21ff each, map
        ; dump in the probe log) while the slide itself holds $896f=$59 --
        ; and those cells render as a full-width band of white junk over the
        ; entering monsters for the effect's last ~15 frames, until the
        ; effect's own cleanup refills the buffer.  the owner's "white flash
        ; at the START of the fight, as the enemies are appearing ... too
        ; quick to screenshot" -- reliable in exactly the fights whose
        ; entrance slides shown monsters under live hud lines.  $01ee is the
        ; word vanilla holds in every field cell it did not draw itself,
        ; priority-CLEAR, safe in BOTH tile modes (its 16x16 neighbors
        ; $1ef/$1fe/$1ff are priority-clear with it, under the battle bg) --
        ; the same word the veil below writes over live cells and the entry
        ; wipes sweep.  an abandoned cell is now word-identical to a cell we
        ; never touched.
        lda     #$01ee
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
        ; hud glyph TILES unreliable? veil (hide) the hud, don't draw from them.
        ; a battle dialog window (window_mess_open_init, _c142e4, btlgfx_main
        ; .asm:9264) opens by ClearDlgGfxBuf-ing the whole small font and
        ; re-uploading it to $5800 in four TfrDlgTextGfx passes -- a full
        ; $5800-$5fff blank + message glyphs, which zeroes OUR borrowed glyph
        ; cells ($64-$79, $eb-$fd: all blank in SmallFontGfx).  the vanilla
        ; staged restore (Ot6FontRestoreMark, hooking _c143b9) fires on the
        ; dialog CLOSE only, and the window keeps re-uploading as it prints, so
        ; from open until the close re-lay finishes -- and for the WHOLE fight
        ; when the script never issues a close (measured: probe_moogfont /
        ; probe_moogjunk, battle 115 Kefka flashback -- the under-enemy hud
        ; drew break/shield/icon glyphs from blanked tiles for ~5000/9000
        ; frames: junk over and around the enemies).  so while a dialog window
        ; is up (w7e64d5, the open latch: _c14312 sets it, _c143cc/BattleEvent
        ; Cmd_10 re-lay then clear it) OR a re-lay is mid-flight (OT6_FONTDIRTY,
        ; the close's staged restore), hold the veil: the hud is cleanly hidden
        ; (vanilla's $01ee fill, exactly like an entry/exit anim), never junk,
        ; and repaints once the tiles are whole again.  neither flag is set by
        ; the attack-name banner (battle_banner: FONTDIRTY stays 0, hud stays
        ; painted).  the dialog draws in $80+ letter cells, disjoint from ours.
        lda     f:$7e0000+$64d5                  ; dialog window open?
        and     #$00ff
        bne     @veil
        lda     f:$7e0000+OT6_FONTDIRTY          ; font re-lay in flight?
        and     #$00ff
        bne     @veil
        ; battlefield bg3 in 16x16 TILE MODE?  an animation owns the layer --
        ; veil.  the animation inits flip the battlefield's $2105 shadow
        ; ($896f) to 16x16 bg3 tiles for an effect's run -- InitAnimType's
        ; bg1-target and bg1-gfx paths (btlgfx_main.asm:26304/:26348,
        ; `ora #$40`/`ora #$50`) and the circle/mask init families
        ; (:47410 `ora #$48`, :48362 `and #$f7 / ora #$40`) -- because the
        ; effect uses bg3 as its own canvas/color-math mask.  vanilla clears
        ; the field map first (ClearBG3TileBuf/TfrBG3Tiles) and can assume
        ; nothing of its own shows: its $01ee fill is priority-CLEAR,
        ; underneath the opaque battle bg in every mode.  our hud cells are
        ; priority-SET ($21xx), and in 16x16 mode a map cell renders at
        ; DOUBLED size and position pulling three NEIGHBOR tiles (char n
        ; draws n, n+1, n+$10, n+$11) -- so any live line inside the
        ; effect's scroll window paints doubled break-icon blocks flanked by
        ; neighbor-tile bars: "break icons amongst other things that look
        ; like junk memory", over and around the monsters, in fights with no
        ; dialogue -- the owner's residual v0.2 sighting after the fly-in
        ; and dialogue-clobber fixes.  measured (probe_junk16, map 96's
        ; natural Cirpius x3, hud rows 5/8): a plain CURE runs 42 frames at
        ; $2105=$59 with both rows inside the (0,0) window -- 424 flagged
        ; frames, screenshots match the report; Fire's $51 phase (priority
        ; flag dropped) and plain Fights ($19: bg1-only 16x16) stay
        ; invisible, which is why the sighting was intermittent.  while the
        ; bit is up, hold the veil: $01ee is exactly the word vanilla wants
        ; in every cell it did not draw itself, in both tile modes.  (the
        ; main loop can flip $896f mid-frame between our nmi reads; the
        ; exposure is bounded at one partial frame at effect onset, below
        ; per-frame sampling -- battle_hudanim16 samples per frame and
        ; passes.)
        lda     f:$7e0000+$896f                  ; battlefield $2105 shadow
        and     #$0040                           ;   bg3 tile size 16x16?
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
        ; pip moved/closed: the same one-shot blank hazard as the lines
        ; (this one predates the anchor rework -- every menu-cursor hop
        ; was an ungated one-shot), same cure: defer when late, redo
        ; next nmi (@pdone opens with shorta0, a8 entry is fine)
        shorta0
        jsr     @late
        bcs     @pdone
        longa
        lda     f:$7e0000+OT6_PIPPREV            ; reload (gate ate a)
        sta     hVMADDL                  ; moved/closed: blank the old cell
        lda     #$21ff          ; $21ff HERE is correct, on purpose: the pip
                                ;   lives in the party-window MENU map, whose
                                ;   hdma $2105 sections ($8973/$8977) no anim
                                ;   ever flips to 16x16 -- the field-map
                                ;   blank above had to become $01ee (the
                                ;   entrance-flash fix), but $01ee is the
                                ;   FIELD map's fill, not this map's
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
; local: enough vblank left for a one-shot transition write? (a8, db=0;
; clobbers a; carry SET = too late, defer.) constants mirror the font
; slice gate above: v must be in [225,248] -- past 248 the worst-case
; transition burst (~9 scanlines at the measured PIO rate, see the
; @nofont comment) could run into active display, where the PPU drops
; VRAM writes and a one-shot has no next-frame rewrite to heal it.
@late:  lda     hSLHV           ; software-latch the h/v counters
        lda     hSTAT78         ; reset the opvct read flip-flop
        lda     hOPVCT          ; v low byte
        xba
        lda     hOPVCT          ; v bit 8 (in bit 0)
        lsr                     ; -> carry
        xba                     ; a = v low byte (xba preserves carry)
        bcs     @l1             ; v >= 256: too late (carry already set)
        cmp     #$e1
        bcc     @l0             ; v < 225: not vblank (defensive) -- defer
        cmp     #$f9            ; carry = (v >= 249) = too late
        rts
@l0:    sec
@l1:    rts
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
@cmtd:  pla
        bra     @show
        ; ...and committed just the same while the CONFIRMED action still
        ; sits in the user-action queue ($2bae + 0/8/$10/$18, char slot or
        ; $ff -- GetPlayerAction's ring, battle_main.asm:12643). the C1
        ; confirm freezes the payload -- bushido's A latches the tech into
        ; $2bb0 at that instant -- but $32cc only goes live when C2 drains
        ; the ring, and C2 drains between actions: 1 frame when idle, more
        ; when something is executing. an L/R edge inside that window
        ; changed the CHARGE without changing the tech
        ; (probe_bushidobusy: tempest latched at 3, one L landed, bp fell
        ; 2 -- tempest for two). magic never showed it only because its
        ; consumer, Ot6QueueFold, reads pending at drain time too.
:       lda     $2bae
        cmp     $62ca
        beq     @cmtd
        lda     $2bb6
        cmp     $62ca
        beq     @cmtd
        lda     $2bbe
        cmp     $62ca
        beq     @cmtd
        lda     $2bc6
        cmp     $62ca
        beq     @cmtd
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
        ; ---- mt. kolts trash: the v0.3 rows that make the break happen.
        ; all three carry TWO shields, and that number is the finding, not
        ; a taste. a break only opens a WINDOW if the target still has more
        ; hp than the breaking hit; the breaking hit is 4x base through the
        ; element channel (vanilla weak x2, no Ot6ShieldedDmg because the
        ; shields are already gone, then Ot6BrokenDmg x2) and 2x through
        ; the class one. so the count is really "how late does the break
        ; land", and measurement #8 swept 1/2/3 live with bal_party's
        ; BUFF_SHIELDS against the real pools:
        ;
        ;   shields   cirpius x3        tusker x2
        ;   3 (fmla)  break at 100%     break at 100%
        ;             actions_broken 0  actions_broken 0
        ;   2         break at 78-90%   break at 51-57%
        ;             actions_broken 1  actions_broken 1-2
        ;   1         (not swept)       break at 28-53%
        ;             --                actions_broken 0
        ;
        ; the formula's 3 is one chip too many: by the time the last shield
        ; falls the party has already spent the monster, so the break lands
        ; on a corpse -- which is exactly what "breaks 6/6, uptime 1 frame"
        ; meant in measurements #5 and #6, restated with a cause. and 1 is
        ; one too few for the ELEMENT channel: with no chip to soften it
        ; first, 4x base (bio blaster measures ~87 a target on a poison-weak
        ; body, so ~350) simply exceeds a 270-hp tusker outright and the
        ; break is the kill again. 2 is the count where the loop exists.
        ;
        ; brawler takes 2 for consistency with its pool-mates, and it is
        ; the one authored species whose window does NOT open at it: 137 hp
        ; against an 84-point breaking hit has the margin in principle, but
        ; terra and locke spend it before edgar's SECOND swing lands, and
        ; with one chipper against a pair the two chips often land on
        ; different brawlers and neither breaks. measured, `boost3`: 2.0
        ; chips, 0 breaks. what would close it is a slashing carrier whose
        ; per-hit damage is small enough to chip twice cheaply -- cyan's
        ; flurry, edgar's chainsaw -- and neither exists at mt. kolts. the
        ; row still buys the reveal, the chips, and (when mashed, where
        ; edgar swings the blade every turn) a real break: 3.0 chips, 1.0
        ; breaks. it is coverage plus a lesson, not a window; said plainly
        ; rather than tuned until the number looked right.
        .word   $000b
        .byte   2, OT6_SLASH    ; brawler: the mountain's one CLASS row,
                                ;   and the only one on the stretch. it
                                ;   is here because brawler ABSORBS
                                ;   poison (monster_prop.dat +$0177 =
                                ;   $08), so the bio-blaster answer the
                                ;   rest of mt. kolts teaches would HEAL
                                ;   it, and its vanilla ice (+$0179 =
                                ;   $02) has no wielder until celes.
                                ;   slash, not pierce, because slash is
                                ;   the scarce key: terra's mithril knife
                                ;   and locke's dirk are both PIERCE
                                ;   (ot6_class.asm:49,:48) and so is
                                ;   edgar's autocrossbow, while edgar's
                                ;   mithril blade (:59) is the party's
                                ;   ONLY slashing weapon -- so the answer
                                ;   to a brawler is edgar closing the
                                ;   tools menu, which is a move nothing
                                ;   else on this mountain asks for.
                                ;   the class channel is also the only one
                                ;   on this mountain that CAN hold a
                                ;   window: Ot6ClassChip takes no vanilla
                                ;   weak x2, so the breaking hit is 2x
                                ;   base, and edgar's blade measures ~42
                                ;   base here -- ~84 against 137 hp fits,
                                ;   where fire (~110 base -> ~440) and the
                                ;   bio blaster (~87 -> ~350) do not.
        .word   $0086
        .byte   2, $00          ; cirpius: SHIELDS ONLY, no class byte --
                                ;   its weakness is the poison row in
                                ;   Ot6ElemAddTbl and this row exists
                                ;   purely to take the count off the
                                ;   formula's 3. that is a legitimate use
                                ;   of this table (the whelk shell's
                                ;   `0, $00` is the same shape) and it is
                                ;   the cheapest way to move the break
                                ;   off the corpse: 3 -> 2 takes cirpius
                                ;   from actions_broken 0 to 1.
        .word   $007a
        .byte   2, $00          ; tusker: shields only, same reason. at
                                ;   270 hp it is the widest window on the
                                ;   mountain (uptime 20.5%) and at the
                                ;   formula's 3 it had none at all.
                                ; note the coupling these three share: an
                                ; Ot6ShieldTbl row also exempts its
                                ; species from Ot6HpScale. inert today
                                ; (every band ships $10 = 1x) but real if
                                ; the hp dial ever reopens, and it is why
                                ; the four OVERWORLD species in this pass
                                ; took Ot6ElemAddTbl rows only -- an
                                ; element add carries no such exemption,
                                ; so where a species needs a weakness but
                                ; not a shield count, the element table is
                                ; the cheaper instrument. these three need
                                ; the count.
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
        ; ---- the v0.6 BREAK-COVERAGE pass: class rows that close the
        ; fixed-party gaps the audit found across the three scenarios. every
        ; species below was a FORMULA monster (no class weakness) whose
        ; forced party could reach none of its vanilla/added ELEMENTS -- so
        ; it was unbreakable by the exact party the game hands you. the fix
        ; is a weapon class, chosen per that party (class chips ignore
        ; absorb/null, so the water/bolt these bodies absorb never matters).
        ; shields track the early-war trash/miniboss band (2 basic, 3
        ; elite). NOTE the trade: an Ot6ShieldTbl row exempts a species from
        ; Ot6HpScale, which the armor-line ElemAddTbl block deliberately
        ; avoided -- but a class weakness has nowhere else to live, so
        ; per-party breakability takes that trade here (HpScale ships 1x,
        ; inert today). palette: armored soldiers read PIERCE (a blade finds
        ; the gaps) + lightning where a party can conduct it; the Cyan SOLO
        ; duel is SLASH (the samurai out-cuts them); Sabin's brawls add
        ; BLUDG (a monk caves the plate). decode + rationale: bosses-wob.md.
        ;
        ; -- imperial soldier line --
        .word   $0001
        .byte   2, OT6_SLASH|OT6_PIERCE ; soldier: Cyan's duel cuts it
                                ;   (slash), Shadow's throw finds the seam
                                ;   (pierce). camp pursuit b44 + Cyan-solo b43
        .word   $0002
        .byte   3, OT6_PIERCE   ; templar: camp elite (b44); Shadow's throw
                                ;   (pierce) / Bolt Edge (+bolt in ElemAddTbl)
        .word   $014e
        .byte   3, OT6_SLASH    ; leader: Cyan SOLO Doma duel (b46). slash
                                ;   only -- the samurai out-cuts the
                                ;   commander; no other party fights him, so
                                ;   no unreachable '?' clutters the swordfight
        .word   $014f
        .byte   2, OT6_SLASH|OT6_BLUDG ; grunt: Doma courtyard defense (b13),
                                ;   held by Cyan (slash) + Sabin (bludg) --
                                ;   neither reaches pierce/bolt, so the
                                ;   palette bends to who holds the line
        .word   $0176
        .byte   3, OT6_SLASH|OT6_BLUDG ; cadet: same Doma defense (b14), same
                                ;   two heroes, a bigger body
        .word   $0175
        .byte   2, OT6_PIERCE   ; officer: Locke SOLO occupied South Figaro
                                ;   (b9). pierce -- Locke's dagger is his one
                                ;   key, so it is the one weakness shown
        .word   $0065
        .byte   2, OT6_SLASH|OT6_PIERCE ; trooper: Narshe defense waves. the
                                ;   player-assigned 3-way split needs BOTH
                                ;   classes -- slash for a Cyan/Sabin squad,
                                ;   pierce for a Locke/Gau squad. keeps
                                ;   vanilla poison (the Edgar squad's key)
        .word   $003f
        .byte   3, OT6_SLASH|OT6_PIERCE ; rider: also a Narshe wave; same
                                ;   squad coverage. keeps vanilla fire|poison,
                                ;   so Shadow's Fire Skean still breaks it on
                                ;   the Phantom Train
        .word   $009f
        .byte   3, OT6_SLASH|OT6_PIERCE ; heavyarmor: Locke SOLO S.Figaro
                                ;   guards (b11 -> pierce) AND a Narshe wave
                                ;   (formation 88 -> slash for a Cyan/Sabin
                                ;   squad). keeps vanilla bolt|water + poison
        .word   $013a
        .byte   2, OT6_PIERCE   ; merchant: Locke SOLO disguise fight (b10). a
                                ;   civilian with NO vanilla weakness at all,
                                ;   unbreakable by anyone before this row;
                                ;   pierce is Locke's dagger, kept simple
        ; -- Serpent Trench (Sabin + Cyan + Gau: bludg + slash + pierce).
        ; each aquatic answers to a different member's kit, so the trio's
        ; three keys map one-to-one onto the three creatures. all three
        ; absorb water and their vanilla element (bolt/fire) is a dead or
        ; level-gated key for this party -- class is the reliable break.
        .word   $003a
        .byte   2, OT6_SLASH    ; anguiform: a slippery eel, cut by Cyan's
                                ;   blade (vanilla bolt is dead here)
        .word   $005e
        .byte   2, OT6_BLUDG    ; actaneon: a shelled crustacean, cracked by
                                ;   Sabin's fists (vanilla fire needs L15)
        .word   $0059
        .byte   2, OT6_PIERCE   ; aspik: a coiled asp, punctured by Gau's
                                ;   fanged strike (vanilla fire needs L15)
        ; zozo / opera / the factory
        ; ---- the v0.4 ZOZO TOWN pass: four poison-trash rows, shields only.
        ; the search-for-terra party is LOCKE+CELES+EDGAR+SABIN -- TERRA IS
        ; GONE, she is the search target -- so there is no native fire at all,
        ; and poison = edgar's bio blaster is the town's break key. every town
        ; thug is ALREADY poison-weak in vanilla (slamdancer $052, harvester
        ; $04e, gabbldegak $0df, hadesgigas $053), so unlike the kolts pass this
        ; is NOT an element add: the weakness is there and reachable, and what
        ; the formula got wrong is the shield COUNT. these are L15-16 trash, so
        ; 2 + level/8 seeds 3 (gabbldegak/slamdancer, L15) or 4 (harvester/hades-
        ; gigas, L16). swept live on zozo_arrival (map 221) with bal_party's
        ; BUFF_SHIELDS, boost3, 6 battles a cell:
        ;
        ;   shields   won   dmg taken   actions_broken   break lands at
        ;   formula   5/6     582         ~0.4             90-95% (corpse)
        ;   3         6/6     554         0.17             89-100% (corpse)
        ;   2         6/6     433         1.83             62-84% (WINDOW)
        ;
        ; the tanks are the tell: at the formula's 4, hadesgigas (1200 hp) and
        ; harvester never broke at all, and the two-tank draw WIPED even the
        ; loop -- MASH wipes 6/6 in this town (the terra-less party has no fire
        ; and no reachable class weakness here, so holding A never chips), the
        ; loop 5/6. at 2 shields they break penultimate, the wipe becomes a
        ; clean win, and the loop takes 48% less damage than mashing does. this
        ; is measurement #8's kolts finding on a bigger body: the formula's
        ; count lands the break on a corpse, 2 is where the loop exists.
        ; ABSORB/NULL re-check (+$17/+$18), the boss-row discipline: hadesgigas
        ; absorbs EARTH and the rest absorb nothing; NONE of the four absorb or
        ; null poison, so the count change never turns the town's answer sour.
        ; shields-only, no class byte (like cirpius/tusker): the answer is the
        ; TOOL, never the A button -- see measurement #9.
        .word   $0052
        .byte   2, $00          ; slamdancer (map 225 sibling of the measured
                                ;   pool, bracketed by $04e 428hp / $0df 350hp)
        .word   $004e
        .byte   2, $00          ; harvester: 428 hp, a 4-shield tank at formula
        .word   $0053
        .byte   2, $00          ; hadesgigas: 1200 hp, the town wall; 4->2 is
                                ;   what lets its break window open at all
        .word   $00df
        .byte   2, $00          ; gabbldegak: comes 4 at a time, and bio's
                                ;   group target chips the whole pack at once
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
; Ot6EsperStatMod while that esper is worn.  Only the four Zozo espers (the v0.4
; playable frontier) are authored; the rest are $00 (no mod), a data-append for
; v0.5 exactly like their spell lists (genju_prop.asm).  Magnitudes are M6
; placeholders picked to be felt but not swingy (~10% of an early base stat).
Ot6EsperStatTbl:
        .byte   OT6_SM_STAM   | 3       ;  0 ramuh    +3 stamina (canon; vanilla STAMINA_1)
        .byte   OT6_SM_NONE             ;  1 ifrit
        .byte   OT6_SM_NONE             ;  2 shiva
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

; ------------------------------------------------------------------------------

; weapon/ability class data (m3)
        .include "ot6_class.asm"
