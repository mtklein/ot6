OT6_BREAK_TICKS := $10          ; a bit under vanilla stop duration ($12)

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
        ; no AUTHORED class row: seed the generated break-floor class so a
        ; formula species is still breakable by SOME weapon class. the byte
        ; is species-indexed: OT6_FLOOR_CLASS[species] (gen_break_floor.py).
        ; written UNCONDITIONALLY every seed -- like the reveal masks below
        ; it must not survive a Cmd_20 reload (no InitBattle clear) or the
        ; hud draws a STALE class-weakness cell from the slot's prior
        ; occupant. the authored @hit path OVERWRITES OT6_BP_CLASS (store above) so
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
        ; with NO InitBattle $3a20-$3ed3 clear. on the FRESH path InitBattle
        ; already zeroes these (write-trace confirms: its clear stores $00 here
        ; before the seed runs), so this is belt-and-suspenders there and
        ; load-bearing only on reload. monster path only (y >= $08 past @on):
        ; the character rows are never touched. with 32k sram the codex
        ; re-merge below restores genuinely-earned reveals (chips write them
        ; through), so a same-monster retract cycle keeps its reveals.
        lda     #$00
        sta     OT6_BROKEN_TICKS,y         ; broken timer: a stale nonzero reload-starts
                                ;   the monster BROKEN (Ot6Gate skips its turn,
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
        sta     OT6_RVPEND_CLS-8,y   ;   Cmd_20 reload either -- a stale bank
                                     ;   would commit the prior occupant's
                                     ;   weakness onto the new species
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
; @formula path, which CLEARS OT6_BP_CLASS (:76-85), so formula trash carries no
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
        ; ---- the v0.6 BOSS-ELEMENT pass (issue #23). four sets that
        ; bosses-wob.md authored in prose and nobody ever wrote into the
        ; data; check_boss_rows.py found them and carried them as waivers
        ; until now. every row below was re-decoded from monster_prop.dat
        ; +$17 (absorb) / +$18 (null) / +$19 (weak) at authoring time, NOT
        ; recalled -- the Crane pair in that same document was wrong in
        ; exactly the absorb direction once already, and the GhostTrain rule
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
        ; line is the one with teeth: $168 ABSORBS WATER, so the water half
        ; of the family row would HEAL him and only bolt is restorable.
        ; battle_breaktbl.lua now walks this whole table and asserts the
        ; add-vs-absorb/null invariant on EVERY row, future ones included.
        .word   $0117
        .byte   $07, $00        ; atmaweapon: + fire|ice|bolt. THE capstone
                                ;   fix -- 11 shields, the biggest gauge in
                                ;   the arc, and vanilla gives it no element
                                ;   at all, so before this row a free-pick
                                ;   party holding neither slash nor pierce
                                ;   had NO break on the WoB final exam.
                                ;   absorbs and nulls nothing: all three
                                ;   bits are free (bosses-wob.md §21)
        .word   $010b
        .byte   $84, $00        ; number 128 body: + bolt|water. the espers
                                ;   zozo just paid out (ramuh) are the key
                                ;   the fight was written around; absorbs
                                ;   ICE, which is neither bit (§15)
        .word   $013f
        .byte   $04, $00        ; right blade: + bolt (the narrower row the
                                ;   doc authors for the limbs; same ice
                                ;   absorb, untouched)
        .word   $0140
        .byte   $04, $00        ; left blade: + bolt
        .word   $0116
        .byte   $80, $00        ; flameeater: + water. strago's debut fight
                                ;   and Aqua Breath is the lesson the doc
                                ;   frames it on; water was NEUTRAL on $116
                                ;   (not weak, not nulled, not absorbed), so
                                ;   the Lore read a row it could not use.
                                ;   it absorbs FIRE and nulls bolt|poison|
                                ;   holy|earth -- water is in neither (§18)
        .word   $0168
        .byte   $04, $00        ; ultros 4: + bolt ONLY. $168 is a different
                                ;   species from $12c/$12d/$12e and vanilla
                                ;   gave it fire|POISON, not fire|bolt, so
                                ;   the running gag's element half was never
                                ;   true. bolt restores it. water is the rest
                                ;   of the family row and is NOT added here:
                                ;   every Ultros record absorbs water (+$17 =
                                ;   $80), so that bit would heal him (§19)
        .word   $ffff

; ------------------------------------------------------------------------------

; [ difficulty transform: scale trash battle hp at monster seed time ]

; Enemy narrative role, visual identity, and recognizable behavior are
; useful design anchors, not immutable constraints. OT6 may author combat
; properties when the break grammar or pacing benefits. This particular
; broad difficulty pass is applied as a runtime transform —
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
merge:  pla                     ; bank the matched weaknesses as PENDING (#33):
        ora     OT6_RVPEND_ELEM-8,y     ;   the on-screen reveal must land on
        sta     OT6_RVPEND_ELEM-8,y     ;   the DAMAGE frame, and this runs at
                                ;   damage CALC -- hundreds of frames earlier
                                ;   (measured: probe_clockwork, calc f704 vs
                                ;   first numeral f1006).  Ot6RevealCommit
                                ;   moves pending into OT6_REVEALED_ELEM (and
                                ;   every same-species slot) at the numeral.
        ; learn it forever: codex entry = everything known so far, pending
        ; included (seed merged the old codex bits in, so this is monotonic).
        ; species is a word: pin i16 for the load — under the caller's
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
        sta     OT6_BROKEN_TICKS,y         ; shields down: BREAK
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
        and     OT6_BP_CLASS,y         ; monster's class weaknesses
        beq     done            ; no match
        sta     OT6_SCR_BIT     ; the matched class bit (exactly one)
        lda     OT6_BROKEN_TICKS,y
        bne     done            ; already broken: no chip until recovery
        lda     $3ee4,y
        bit     #$c0
        bne     done            ; wound/petrify: the hit was theater
        lda     $f2             ; resolved spell flags3 (absorb/undead-drain
        lsr                     ;   reversals already folded in); ONLY bit 0
        bcs     done            ; means heal — $20 can't-dodge etc. ride the
                                ; same byte, and gating on the whole byte
                                ; silenced every flagged skill's chip
        lda     OT6_BOOST_REVEALED,y
        ora     OT6_RVPEND_CLS-8,y      ; #33: banked-this-action isn't new
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
merge:  lda     OT6_SCR_BIT     ; bank the matched class as PENDING (#33):
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
        sta     OT6_BROKEN_TICKS,y         ; shields down: BREAK
done:   rts
.endproc

; ------------------------------------------------------------------------------

; [ commit pending reveals on the damage frame -- per-species, one frame (#33) ]
;
; the chips above run at damage CALC, inside CalcAttackEffect's per-target
; loop; the damage the player SEES lands when GfxCmd_0b allocates its numeral
; thread, hundreds of frames later (measured on the shipped ROM,
; probe_clockwork: hp/reveal writes f704-705, first numeral f1006 -- the '?'
; flipped ~300 frames before any number appeared).  so the chips bank into
; OT6_RVPEND_* and THIS walker moves pending into the revealed bytes:
;   - called from GfxCmd_0b's entry (C1 shim) -- the damage frame proper;
;   - and from Ot6ActionEnd -- the backstop for numeral-less actions, so
;     pending never outlives the action that banked it.
; the codex is per-species, so the commit writes every SAME-SPECIES slot's
; revealed byte in the same pass -- all siblings' icons appear on one frame
; (the display agreeing with the knowledge model, issue #33's third demand).
; absent slots are written too when their species matches: harmless (their
; hud lines are disabled) and cheaper than a presence test.
;
; a8/i16 assumed pinned by the caller (Ot6ActionEnd pins; the _ext wrapper
; pins for C1).  db=$7e.  preserves x/y.
.proc Ot6RevealCommit
        .a8
        .i16
        phb                     ; PIN DB=$7e: every cell below is absolute
        phx                     ;   (battle RAM + the shadow tail), and one
        phy                     ;   caller is the C1 SCRIPT engine, whose DB
        lda     #$7e            ;   is not ours to assume.  measured: without
        pha                     ;   this the walker read junk species and
        plb                     ;   scribbled outside battle RAM, and the
                                ;   Vargas fight WEDGED the moment a monster
                                ;   hit 0 hp -- deaths never completed, no
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
        shorta                  ; plain SEP #$20 -- shorta0's `tdc` SETS Z from
                                ;   D and would wipe the compare.  measured, not
                                ;   reasoned: with shorta0 here every slot read
                                ;   as same-species, and a dying Ipooh's pending
                                ;   SLASH propagated onto VARGAS (his row is
                                ;   BLUDG) -- battle_vargas's revClass control
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
        ply
        plx
        plb
        rts
.endproc

; [ the damage-frame trigger: poll the numeral counter, main loop (#33) ]
;
; WHY A POLL AND NOT A HOOK IN GfxCmd_0b.  The obvious site is that command's
; own entry -- it IS the numeral -- and that is where this first landed.  It
; wedges the fight: measured with probe_vargasstall on the Vargas formation,
; the moment any monster reached 0 hp the battle stopped dead (menu=$00,
; mstate=$00, deaths never completing, 24000 frames and counting) against
; 6737 frames to ipoohs-down on the pre-change ROM.  Bisected in three builds:
; the same hook replaced by four NOPs runs clean, the hook with the walker
; body skipped runs clean, and the walker body (even with its reveal stores
; removed, leaving only the species walk and the pending clear) wedges.  So
; the defect is EXECUTING THIS WALK INSIDE THE C1 BATTLE-SCRIPT ENGINE, whose
; re-entrancy and register/stack contract around its WaitFrame yields we do
; not own.  Cause not established below that; what IS established is the
; boundary, so the work moved to our own context and stays out of the engine.
;
; The trigger is equivalent and observable: GfxCmd_0b's first act is to
; advance the numeral thread counter $632e, so a change in that byte since
; the last main-loop tick means a numeral was allocated -- the damage frame.
; The hud builder already runs every main-loop frame in bank F0 with DB=$7e,
; which is exactly the context the walk wants, and battle_clockwork pins the
; resulting timing (the commit lands on a numeral frame, and after the damage
; calc that banked it).  Cost: at most one frame later than the hook would
; have been, against a wedge -- the trade is not close.
;
; the shadow byte is not init-cleared (it sits past InitBP's clear); a stale
; value costs one spurious commit at battle start, which finds pending empty
; (Ot6SeedShields zeroes it per slot) and does nothing.
; a8/i16, db=$7e (Ot6BgHud_ext's own context).  preserves x/y.
; out: CARRY SET if this tick saw a numeral (#42).  The counter can only be
; consumed once, and #42 needs the same edge to commit a deferred cover pip, so
; the edge is REPORTED rather than duplicated into a second last-seen byte --
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
; plain drains (bit 1, bit 0 clear) DO double — vanilla's elemental-weak
; x2 applies to drains too, and the break window follows vanilla's rule.

.proc Ot6BrokenDmg
        .a8
        tya                     ; entity offset, width-neutral test
        cmp     #$08
        bcc     done
        lda     OT6_BROKEN_TICKS,y
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
;   - OT6_SHIELD_CUR nonzero = shields up and not broken. shieldless species
;     (authored 0 rows: whelk shell, tritoch, formula 0s) and broken
;     monsters both sit at 0 and pass through untouched — shields==0
;     means NO shield system, never "attenuate"
;   - the breaking hit itself is NOT attenuated: both chip procs run
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
        lda     OT6_BROKEN_TICKS,x         ; broken: skip turn (z clear if nonzero)
done:   rtl
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
; (m1's monster-window shield digit — the $3ecb row-glyph buffer, its
; builder, and the MenuTextCmd_0b glyph hook — is retired: it was
; redundant with the under-enemy hud and read as an enemy COUNT.
; $3ecb-$3ed3 stays ours; the odd bytes below still serve as scratch.)
