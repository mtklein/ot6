; ------------------------------------------------------------------------------
; OT6: a break cancels a boss's lit fuse (#561; docs/design/bosses-wob.md "The
; boss contract", docs/design/bosses-wor.md section 1)
;
; The contract: a boss announces its big move a turn ahead, and "breaking the
; boss during the fuse cancels the move; the charge does not resume when the
; boss recovers, and has to be started again".  Vanilla's AI gave a break no
; such effect: `wait` saves where the script resumes ($3d0c,x) and the block
; it waits in ($3240,x), a Broken monster takes no turn (Ot6BrokenTurn), so
; neither cell moves and the fuse picks up where it stopped when the break
; ends.  Measured on the four fuses vanilla wrote (build/attempts/wt/v051-fuse/
; measure/): AtmaWeapon's Flare Star, Atma's Ultima, the Gold Dragon's Bolt 3
; and Kefka's Goner all fired on the boss's first turns back.
;
; The fuse block, in vanilla's own idiom (AtmaWeapon's is the pattern; the
; worked example for authored telegraphs is the CzarDragon's script,
; AIScript::_311, which no battle deals):
;
;               <what arms it>          ; a trigger, and a roll if the move
;               if_monster_switch_clr N ;   is not to come every time
;               if_roll <chance>        ;   (if_roll, ai_script.inc)
;                       <this turn's attack>
;                       set_monster_switch N
;                       end_if
;               if_monster_switch_set N ; the fuse block: its condition holds
;                       dlg <line>      ;   from the announce to the move.
;                                       ;   The line: vanilla's, or one of
;                                       ;   the free slots $8D-$FF
;                       short_glow MONSTER_n
;                       wait            ; the fuse: the boss's next turn
;       Ot6Fuse<Boss>:                  ; <- its script resumes here while lit
;                       clr_monster_switch N    ; the trigger's clears (and
;                                       ;   any reset_monster_timer) FIRST
;                       attack <MOVE>   ; the move: one attack, no roll
;                       end_if
;
; and one row of Ot6FuseTbl below.  The clears come before the move, as the
; Gold Dragon's vanilla block has them: the fuse stops being lit once the
; firing turn's script has been read, and a turn's commands run in order, so
; a break that lands after the move and before a clear queued behind it (a
; party member's counter to a physical finisher) purges that clear with the
; rest of the turn (Ot6BrokenTurn) and no cancel runs: the trigger would
; stand, and the boss announce again with nothing earned.  battle_fuse.lua
; checks the order for every row; AtmaWeapon's and Atma's vanilla blocks had
; the clears after the move and were reordered (#561 review).  An announced move always fires unless a
; break cancels it or the boss dies (the owner, 2026-11-23: "don't announce
; anything that won't happen. however, okay to make a roll before that to
; determine whether or not to do the whole sequence"): nothing between the
; announce and the move rolls, and the fuse block's own conditions cannot
; fail in between (they are tested again on the move's turn), so a roll sits
; on the arming block, a turn earlier.  The four fuses vanilla wrote hold no
; roll after their announce (battle_fuse.lua checks every row for it).
; A boss whose trigger alone arms it (an HP line, a hit count) needs no
; arming block: the trigger is the fuse block's condition.  A fuse is LIT while its boss's main
; script waits at one of the row's resume addresses (from the announce's turn
; until the turn the move is queued), or, for a fuse a counter arms with no
; `wait` of its own (the Gold Dragon's), while its battle switch is set.
;
; A break by any route while the fuse is lit (every take that empties the last
; shield ends in Ot6HitBroke: the element chip, the class chip, OT6's Break,
; Filch, Bum Rush, Cleave's strip) cancels it, Ot6FuseSnuff:
;   * $ff into $3240,y, exactly what `end_if` and `end` store (AICmd_fe): the
;     boss's next turn starts its script from the top, so the move's `wait` is
;     forgotten and nothing resumes;
;   * the row's own clears, the trigger: monster switches or the monster
;     variable ($3dac,y), battle switches ($3eb0), battle variable 3 ($3eb3),
;     the monster's timer ($3dc0,y).  Each row leaves the script where its own
;     move's last commands would have (the state after the move fired), so
;     every state is one vanilla reaches and the trigger is earned again.
; A break while no fuse is lit changes nothing here.  The turn the boss had
; queued, and the commands of a turn in flight, are Ot6BrokenTurn's, as for
; any Broken monster.
;
; The sign (ot6_pin.asm Ot6MarkStage, ot6_hud.asm): while a fuse is lit, the
; cell before the boss's shield emblem shows a yellow "!" (OT6_MARK_FUSE), by
; turns with the trap's dagger or knife when the body is also Slowed or
; Stopped.  The HUD does not evaluate the script every frame: Ot6FusePoll
; re-reads one monster slot a frame, and only in a battle where a body with a
; row stands (OT6_FUSEPOLL), into bit 0 of OT6_FUSE; a slot whose gauge is
; held (#539) is not re-read, so the sign goes out with the hit that breaks
; the boss, not when its damage is computed.  In every other battle the cost
; is one byte test a frame (the poll's gate) and one a live line (the
; mark's): the battle loop's timing is sensitive to less (a 17-cycle test a
; line moved a suite's battle by frames, battle_hitcount on this branch).
;
; The counter half (ot6_break.asm Ot6AIStoryOp): a `dlg` that is a fuse's
; announce is no story (Ot6FuseLineTbl), so the Gold Dragon's arming block
; (`add_monster_var 1 / ... / dlg $73`) is skipped while it is Broken like any
; other counter that only counts: Fights that land on a Broken dragon wind
; nothing, as hits on a Broken Atma never have.
; ------------------------------------------------------------------------------

.segment "ot6_code"
.a8
.i16

OT6_MARK_FUSE   = 3             ; OT6_MARKCELL: a lit fuse (1, 2: ot6_pin.asm)
OT6_FUSE_ATTR   = $21 | (2 << 2)        ; text palette 2: navy, grey, yellow

OT6_FUSE_VAR3   = $01           ; a break clears battle variable 3
OT6_FUSE_TIMER  = $02           ;   and the monster's timer
OT6_FUSE_VAR2   = $08           ; a break clears battle variable 2 (Dadaluma's
                                ;   tally of spells, wt/v052-tg-wob2)
OT6_FUSE_BTIMER = $10           ; a break restarts the battle timer ($3a44, as
                                ;   reset_battle_timer leaves it: the opera
                                ;   Ultros's song, wt/v052-tg-wob2)
OT6_FUSE_SWITCH = $80           ; lit by a battle switch, not by a `wait`
OT6_FUSE_HOLD   = $04           ; every break of this body, lit or not, sets
                                ;   battle switch 0 and clears the battle
                                ;   switches the row's +6 mask clears
                                ;   (Ot6FuseHold): the Whelk's head, whose
                                ;   battle switch 0 keeps the shell from
                                ;   calling it in and whose +6 mask is that
                                ;   call, so a break sends a pending call away
                                ;   and the Broken head stays out for its
                                ;   whole window
; Flags $20-$40 are free.  The contract's other break rule (the owner,
; 2026-11-23: "a break releases whatever the broken body holds", unit B's
; Tentacles) fits here as a flag and a row that applies at every break, lit
; or not: the release itself is Discard's target effect (TargetEffect_44,
; battle_main.asm) on the member the body's $3358 names.  Not built.

; one row a fuse, 8 bytes:
;   +0 the species (word)
;   +2 the first resume address it is lit at, an offset from AIScript (word)
;   +4 how many addresses from there (byte): lit while $3d0c - (+2) < (+4);
;      a switch row's battle-switch mask ($3eb0) instead
;   +5 the monster's switch/variable byte ($3dac,y) is ANDed with this
;   +6 the battle switch byte ($3eb0) is ANDed with this
;   +7 flags (OT6_FUSE_*)
; $ffff ends the table.  A species may have several rows (Kefka's two HP
; lines).  battle_fuse.lua checks every row against the built scripts.
.macro ot6_fuse species, lit, fire, mkeep, bkeep, flags
        .word   species
        .word   lit - AIScript
        .byte   fire - lit + 1
        .byte   mkeep, bkeep, flags
.endmacro

Ot6FuseTbl:
        ; AtmaWeapon: "Vast energy focused", two glowing turns, Flare Star.
        ; Armed by its rotation's fourth turn (Mind Blast, then monster
        ; switches 0 and 1); the move's own tail clears both.
        ot6_fuse $0117, Ot6FuseAtmaWeapon, Ot6FuseAtmaWeaponFire, $fc, $ff, 0
        ; Atma: "Unknown light surrounded Atma!", two glowing turns, Ultima.
        ; Armed by its counter's tally (battle variable 3, then monster
        ; switch 0, which also stops the tally).
        ot6_fuse $017d, Ot6FuseAtma, Ot6FuseAtmaFire, $fe, $ff, OT6_FUSE_VAR3
        ; Kefka: "The end comes...beyond chaos.", his head, Goner.  Armed by
        ; his HP alone, so he says it again on his first turn back; battle
        ; switches 0 and 1 (his counters' gate, and the low line's) go as
        ; the rotation's end leaves them.
        ot6_fuse $012a, Ot6FuseGonerLow, Ot6FuseGonerLow, $ff, $fc, 0
        ot6_fuse $012a, Ot6FuseGoner, Ot6FuseGoner, $ff, $fc, 0
        ; the Gold Dragon: "Gold Dragon begins to store energy!", two of its
        ; turns counted in battle variable 3, Bolt 3 on the third.  Armed by
        ; its counter's fourth Fight (the monster variable), lit by battle
        ; switch 0.
        .word   $0150, 0
        .byte   $01, $00, $fe, OT6_FUSE_SWITCH | OT6_FUSE_VAR3
        ; the CzarDragon: the worked example of an authored fuse, armed by
        ; its timer and a roll, monster switch 0 (no battle deals it; see
        ; AIScript::_311)
        ot6_fuse $0137, Ot6FuseCzar, Ot6FuseCzar, $fe, $ff, OT6_FUSE_TIMER
        ; ---- wt/v051-tg-wob1: World of Balance bosses 1-5 (bosses-wob.md) ----
        ; Each fuse block is its script's first, lit by a monster switch an
        ; ordinary turn sets; a break clears what the move's turn clears.
        ; the Whelk's head: called in by the shell (battle switch 1), two
        ; glowing turns, then it draws into the shell.  Every break of the
        ; head, lit or not, clears the call and sets battle switch 0
        ; (OT6_FUSE_HOLD), the hold that keeps the shell from calling it in
        ; again until its first turn back
        ot6_fuse $0134, Ot6FuseWhelk, Ot6FuseWhelkFire, $ff, $fd, OT6_FUSE_HOLD
        ; the Marshal: switches 0 and 1, armed and announced (his rotation
        ; again)
        ot6_fuse $0064, Ot6FuseMarshal, Ot6FuseMarshal, $fc, $ff, 0
        ; Vargas: switch 0 (his rotation again)
        ot6_fuse $0103, Ot6FuseVargas, Ot6FuseVargas, $fe, $ff, 0
        ; the Lete River Ultros: switch 0 (his rotation again)
        ot6_fuse $012c, Ot6FuseUltros1, Ot6FuseUltros1, $fe, $ff, 0
        ; TunnelArmr: switch 0 (its rotation again)
        ot6_fuse $0104, Ot6FuseTunnelArmr, Ot6FuseTunnelArmr, $fe, $ff, 0
        ; ---- end wt/v051-tg-wob1 ----
        ; ---- wt/v051-tg-wob2: World of Balance bosses 7-10 (bosses-wob.md) ----
        ; Telstar: "It radios in!", a wave of backup on its next turn; one row
        ; a call (its clock at 25, 80, 200).  Each call's battle switch is set
        ; only by the turn that fires it, so a break clears the clock alone.
        ot6_fuse $0044, Ot6FuseTelstar1, Ot6FuseTelstar1, $ff, $ff, OT6_FUSE_TIMER
        ot6_fuse $0044, Ot6FuseTelstar2, Ot6FuseTelstar2, $ff, $ff, OT6_FUSE_TIMER
        ot6_fuse $0044, Ot6FuseTelstar3, Ot6FuseTelstar3, $ff, $ff, OT6_FUSE_TIMER
        ; the GhostTrain: "Whistle blows!", two glowing turns, Evil Toot; armed
        ; by its count of ordinary turns (battle variable 3), monster switch 0
        ot6_fuse $0106, Ot6FuseGhostTrain, Ot6FuseGhostTrainFire, $fe, $ff, OT6_FUSE_VAR3
        ; Rizopas: "Waters swell!", El Nino; armed by a roll on its turn A,
        ; monster switch 0 (switch 1, its turn B, is clear while lit)
        ot6_fuse $0155, Ot6FuseRizopas, Ot6FuseRizopas, $fc, $ff, 0
        ; Kefka at Narshe: "Frost creeps!", Ice on the squad; armed by his
        ; clock, monster switch 0
        ot6_fuse $014a, Ot6FuseKefkaNarshe, Ot6FuseKefkaNarshe, $fe, $ff, OT6_FUSE_TIMER
        ; ---- end wt/v051-tg-wob2 ----
        ; ---- wt/v052-tg-wob2: World of Balance bosses 11-16 (bosses-wob.md) ----
        ; Dadaluma: "He crouches!", Jump; armed by his knife fan once the
        ; party has used Magic on him three times (battle variable 2), monster
        ; switch 0; a break clears both
        ot6_fuse $0107, Ot6FuseDadaluma, Ot6FuseDadaluma, $fe, $ff, OT6_FUSE_VAR2
        ; the opera Ultros: "Imp! Pal! Buddy!" (vanilla's line), Imp Song; armed
        ; by the battle timer alone, which a break restarts; monster switch 0
        ; holds his slot moves while lit
        ot6_fuse $012d, Ot6FuseUltros2, Ot6FuseUltros2, $fe, $ff, OT6_FUSE_BTIMER
        ; Ifrit: "It inhales!", Fire 2 on the party; battle switch 0 (his
        ; monster variable is his tally of spells)
        ot6_fuse $0109, Ot6FuseIfrit, Ot6FuseIfrit, $ff, $fe, 0
        ; Shiva: "It inhales!" (Ifrit's line), Ice 2 on the party; battle
        ; switch 1
        ot6_fuse $0108, Ot6FuseShiva, Ot6FuseShiva, $ff, $fd, 0
        ; Number 024: "Its wall glows!", the wall's spell, one row a wall (weak to fire: Ice 2; to
        ; ice: Fire 2; to water: Bolt 2); armed by his clock's WallChange
        ; (monster switch 0), the wall held while lit (switch 1)
        ot6_fuse $010a, Ot6FuseN024Ice, Ot6FuseN024Ice, $fc, $ff, 0
        ot6_fuse $010a, Ot6FuseN024Fire, Ot6FuseN024Fire, $fc, $ff, 0
        ot6_fuse $010a, Ot6FuseN024Bolt, Ot6FuseN024Bolt, $fc, $ff, 0
        ; Number 128: "Its core heats!", Atomic Ray; armed by a blade's death
        ; (battle switch 0, which nothing else in his fight touches)
        ot6_fuse $010b, Ot6FuseN128, Ot6FuseN128, $ff, $fe, 0
        ; the Cranes: "Deck groans!", Magnitude8; each armed by its own
        ; clock (monster switch 1; switch 0 is its TekBarrier, kept), which a
        ; break restarts.  Battle variables 0-3 are their tallies: kept
        ot6_fuse $010d, Ot6FuseCraneL, Ot6FuseCraneL, $fd, $ff, OT6_FUSE_TIMER
        ot6_fuse $010e, Ot6FuseCraneR, Ot6FuseCraneR, $fd, $ff, OT6_FUSE_TIMER
        ; ---- end wt/v052-tg-wob2 ----
        ; ---- wt/v052-tg-wob3: World of Balance bosses 17-22 (bosses-wob.md) ----
        ; the bridge Ultros: "He looms over you!", Aqua Rake; armed at the edge
        ; of his advance (monster switch 0).  Switch 1 (he holds the edge) is
        ; kept: his first turn back is the sink to the start, the advance again
        ot6_fuse $012e, Ot6FuseUltros3, Ot6FuseUltros3, $fe, $ff, 0
        ; FlameEater: "It swells with flame!", Fire Ball; armed by its
        ; rotation's last turn (monster switch 2; 0 and 1 are its opening and
        ; its calls)
        ot6_fuse $0116, Ot6FuseFlameEater, Ot6FuseFlameEater, $fb, $ff, 0
        ; Chupon: "It inhales!" (Ifrit's line), Fire Ball; armed by three blows
        ; counted (battle variable 3), which a break clears
        ot6_fuse $012f, Ot6FuseChupon, Ot6FuseChupon, $ff, $ff, OT6_FUSE_VAR3
        ; the Air Force's MissileBay: "Missiles lock on!", Launcher; armed under
        ; 1,536 HP by a Missile turn (monster switch 0).  The bay's row: a break of the body
        ; leaves it lit
        ot6_fuse $0147, Ot6FuseMissileBay, Ot6FuseMissileBay, $fe, $ff, 0
        ; AtmaWeapon's last phase: "Vast energy focused" (vanilla's line), one
        ; glowing turn, Flare Star; armed by its low rotation (monster switch 2)
        ot6_fuse $0117, Ot6FuseAtmaWeaponLow, Ot6FuseAtmaWeaponLow, $fb, $ff, 0
        ; Nerapa: "The wheel turns!", Roulette; armed by six Fights counted
        ; (battle variable 3), which a break clears
        ot6_fuse $0118, Ot6FuseNerapa, Ot6FuseNerapa, $ff, $ff, OT6_FUSE_VAR3
        ; ---- end wt/v052-tg-wob3 ----
        .word   $ffff

; the announce lines a counter speaks (a `dlg` id, low byte; every id is
; under $100): not story, for Ot6AIStoryOp.  $ff ends it.
Ot6FuseLineTbl:
        .byte   $73             ; "Gold Dragon begins to store energy!"
        .byte   $ff

; [ is this dlg a fuse's announce? ]
; x = offset into AIScript of a `dlg` command.  a8/i16.  out: carry set if
; its line is in Ot6FuseLineTbl.  preserves x/y.
.proc Ot6FuseLine
        .a8
        .i16
        phy
        lda     f:AIScript+2,x
        bne     @no             ; (no line above $ff exists)
        ldy     #$0000
@scan:  phx
        tyx
        lda     f:Ot6FuseLineTbl,x
        plx
        cmp     #$ff
        beq     @no
        cmp     f:AIScript+1,x
        beq     @yes
        iny
        bra     @scan
@no:    ply
        clc
        rts
@yes:   ply
        sec
        rts
.endproc

; [ a monster's body is seeded: does its species have a fuse? ]
; jsr from Ot6SeedShields.  y = entity offset ($08-$12), OT6_SPECIES set.
; a8/i16.  Writes OT6_FUSE for the slot ($80 = it has a row, lit clear) and
; marks the battle (OT6_FUSEPOLL).  preserves x/y; clobbers a (b = 0).
.proc Ot6FuseSeed
        .a8
        .i16
        phx
        ldx     #$0000
@row:   longa
        lda     f:Ot6FuseTbl,x
        cmp     #$ffff
        beq     @none
        cmp     OT6_SPECIES-8,y
        beq     @has
        txa
        clc
        adc     #$0008
        tax
        bra     @row
@none:  shorta0
        bra     @put            ; a = 0
@has:   shorta0
        lda     #$80
        tsb     OT6_FUSEPOLL    ; the hud polls this battle
@put:   sta     OT6_FUSE-8,y
        plx
        rts
.endproc

; [ is this monster's fuse lit? ]
; y = entity offset ($08-$12).  a8/i16, db=$7e.  out: carry set = lit, and
; x = its row's offset in Ot6FuseTbl.  preserves y; clobbers a/x, and b
; (the table's words pass through it).
.proc Ot6FuseLit
        .a8
        .i16
        ldx     #$0000
@row:   longa
        lda     f:Ot6FuseTbl,x
        cmp     #$ffff
        beq     @no
        cmp     OT6_SPECIES-8,y
        shorta                  ; (plain sep: z is the compare's)
        bne     @next
        lda     f:Ot6FuseTbl+7,x
        bmi     @switch
        lda     $3240,y         ; the block its script waits in
        cmp     #$ff
        beq     @next           ; it waits nowhere
        longa
        lda     $3d0c,y         ; where it resumes
        sec
        sbc     f:Ot6FuseTbl+2,x
        cmp     #$0100
        shorta
        bcs     @next           ; before the row's first address, or far past
        cmp     f:Ot6FuseTbl+4,x
        bcc     @yes
        bra     @next
@switch:
        lda     $3eb0           ; battle switches 0-7
        and     f:Ot6FuseTbl+4,x
        bne     @yes
@next:  longa
        txa
        clc
        adc     #$0008
        tax
        bra     @row
@no:    shorta
        clc
        rts
@yes:   sec
        rts
.endproc

; [ a monster's last shield was taken: its lit fuse is cancelled ]
; jsr from Ot6HitBroke, the one leaf every break passes.  y = the target's
; entity offset (a monster).  a8, either index width, db=$7e.  preserves
; x/y; clobbers a.
.proc Ot6FuseCancel
        .a8
        lda     OT6_FUSE-8,y
        bpl     @out            ; no row for this body: one load, the common case
        phx                     ; (the caller's width)
        php
        longi
        jsr     Ot6FuseLit
        bcc     @hold
        jsr     Ot6FuseSnuff
@hold:  jsr     Ot6FuseHold     ; (after the cancel's clears: a hold wins)
@done:  plp
        plx
@out:   rts
.endproc

; [ a break holds what the body's rows say it holds ]
; Its own proc so the suites can watch it.  y = the monster.  a8/i16, db=$7e.
; For each of the body's rows with OT6_FUSE_HOLD, the battle switches its +6
; mask clears are cleared (a call not yet announced is sent away too) and
; battle switch 0 is set.
; preserves y; clobbers a/x (b passes through the table's words, as in
; Ot6FuseLit).
.proc Ot6FuseHold
        .a8
        .i16
        ldx     #$0000
@row:   longa
        lda     f:Ot6FuseTbl,x
        cmp     #$ffff
        beq     @out
        cmp     OT6_SPECIES-8,y
        shorta                  ; (plain sep: z is the compare's)
        bne     @next
        lda     f:Ot6FuseTbl+7,x
        and     #OT6_FUSE_HOLD
        beq     @next
        lda     $3eb0
        and     f:Ot6FuseTbl+6,x
        ora     #$01
        sta     $3eb0           ; battle switches 0-7: the mask's cleared, 0 set
@next:  longa
        txa
        clc
        adc     #$0008
        tax
        bra     @row
@out:   shorta
        rts
.endproc

; [ the cancel itself ]
; Its own proc so the suites can watch it fire.  y = the monster, x = its lit
; row.  a8/i16, db=$7e.  preserves x/y; clobbers a.
.proc Ot6FuseSnuff
        .a8
        .i16
        lda     #$ff
        sta     $3240,y         ; its next turn starts the script from the
                                ;   top, as after any end_if (AICmd_fe)
        lda     $3dac,y
        and     f:Ot6FuseTbl+5,x
        sta     $3dac,y         ; the monster's switches / variable
        lda     $3eb0
        and     f:Ot6FuseTbl+6,x
        sta     $3eb0           ; battle switches 0-7
        lda     f:Ot6FuseTbl+7,x
        lsr
        bcc     @timer
        stz     $3eb3           ; battle variable 3 (the tally, the count)
@timer: lsr
        bcc     @var2
        pha
        lda     #$00            ; the monster's timer, as reset_monster_timer
        sta     $3dc0,y         ;   leaves it (MiscAIEffect_00)
        sta     $3dc1,y
        pla
@var2:  lsr                     ; (OT6_FUSE_HOLD: Ot6FuseHold's, not the cancel's)
        lsr
        bcc     @btimer
        stz     $3eb2           ; battle variable 2 (Dadaluma's tally)
@btimer:
        lsr
        bcc     @out
        stz     $3a44           ; the battle timer, as reset_battle_timer
        stz     $3a45           ;   leaves it (MiscAIEffect_04)
@out:   rts
.endproc

; [ the hud's poll: one monster slot a frame ]
; jsr from Ot6BgHud_ext while OT6_FUSEPOLL is nonzero.  a8/i16, db=$7e.
; Bit 0 of the slot's OT6_FUSE follows Ot6FuseLit, except while the slot's
; gauge is held (#539): the sign changes with the hit shown.  A body that is
; gone, dead or stone is not lit.  clobbers a/x/y; b = 0 on every exit.
.proc Ot6FusePoll
        .a8
        .i16
        clr_a                   ; b = 0 for the tay
        lda     OT6_FUSEPOLL
        and     #$7f
        inc
        inc
        cmp     #$0c
        bcc     :+
        lda     #$00
:       pha
        ora     #$80
        sta     OT6_FUSEPOLL
        pla
        clc
        adc     #$08
        tay                     ; the slot's entity offset ($08-$12)
        lda     OT6_FUSE-8,y
        bpl     @out            ; no row for this body
        jsr     Ot6HitBit
        and     OT6_HOLD
        bne     @out            ; held: as of the last hit shown
        lda     $3aa0,y
        lsr
        bcc     @dark           ; not present
        lda     $3ee4,y
        bit     #$c0
        bne     @dark           ; wound / petrify
        jsr     Ot6FuseLit
        clr_a                   ; b = 0 again (Ot6FuseLit's word loads): the
                                ;   hud's callers take it so, and a dirty
                                ;   b here crashed the battle (carry kept)
        bcc     @dark
        lda     #$81
        bra     @put
@dark:  lda     #$80
@put:   sta     OT6_FUSE-8,y
@out:   rts
.endproc

; [ the mark cell of a body whose fuse is lit ]
; jsr from Ot6MarkStage.  a = the trap's mark (0 free, 1 hobbled, 2 pinned).
; out: a = the mark to draw: the fuse's, by turns with the trap's (about half
; a second each, btlgfx's frame counter $0e) when there is one.  a8, either
; index width, db=$7e.  preserves x/y.
.proc Ot6FuseMark
        .a8
        cmp     #$00
        beq     @fuse
        pha
        lda     a:$000e
        and     #$20
        beq     @trap
        pla
@fuse:  lda     #OT6_MARK_FUSE
        rts
@trap:  pla
        rts
.endproc

; ------------------------------------------------------------------------------

; [ ai conditional $0a: a roll (if_roll, ai_script.inc) ]
; In bank $c2's tail, where AICmd_fc's `jsr (AICondTbl,x)` can reach it: the
; table's entry $0a, vanilla's unused second "never", points here.  $3a2e is
; the chance in 256ths.  a8/i8, as every conditional.  out: carry set =
; continue.
.segment "battle_code"
Ot6AICondRoll:
        jsr     Rand            ; 0..255
Ot6AIRolled:                    ; (a = the roll: battle_fuse.lua reads it here)
        cmp     $3a2e
        jmp     InvertCarry     ; continue below the chance
.segment "ot6_code"
