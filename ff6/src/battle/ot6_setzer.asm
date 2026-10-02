; ------------------------------------------------------------------------------
; Setzer's kit: the Slot submenu (Setzer's table), Coin Toss, Hired Help and
; the divine Jackpot
;
; The reels themselves (the boost-tiered rig) are in ot6_slot.asm; this file
; is everything around them.  Design and rulings: docs/design/kits.md,
; "Setzer -- Gambler/Merchant".
; ------------------------------------------------------------------------------
;
; The command slot, and why this is a submenu behind Slot.
;
; Setzer's command rows are FIGHT, SLOT, MAGIC, ITEM (char_prop.asm), and the
; battle menu is four rows wide, so like Locke he has no spare slot, and his
; third row is the Magic an Esper gives him, which kits.md's row-sharing rule
; never sacrifices.  Slot is his signature and rung one of his ladder, so the
; ladder goes behind the Slot row, the shape Ot6ThiefListOpen gave Steal:
; OpenCmdMenuTbl[$0f] opens a Tools-shell list whose first row is Slot itself.
;   * Slot's row confirms into the reels (Ot6SetzerConfirm): the Tools window
;     closes the way a B press closes it and the slot window opens from the
;     command window as it always has, so the reels, their boost ladder
;     (ot6_slot.asm) and their commit are untouched.
;   * the other three rows take the thief arm: target select, with the row id
;     riding w7e7a85 into $2bb0 as the queued attack byte under command $0f.
;     FixPlayerAttack would map that byte through SlotAttackTbl as a reel
;     result; Ot6SlotKitRow keeps the row id instead, and Cmd_0f's head
;     (Ot6SetzerExec) runs the row.
;   * the Coin Toss relic's Slot -> GP Rain rewrite (RelicCmdTbl) still lands
;     on command $18, whose OpenCmdMenuTbl slot is target select: a Setzer
;     wearing it gets vanilla GP Rain and no table, as a gloved Locke gets
;     Capture and no thief list.
;   * anyone else with the Slot command (a Gogo) gets the reels straight away:
;     the table is Setzer's job, and Gogo masters none.
;
; The row ids are AttackName pad slots, as the thief rows' are: $59-$5c are
; the last four of the empty pad after Joker Doom ($55) and the thief rows
; ($56-$58).  SwdTech draws its names from BushidoName, so the pad is free for
; names, but $59-$5c are also SwdTech's attack ids, and Ot6Oblivion keys
; Cleave on $5c by the attack id alone ($3a7d).  So the Slot row, which only
; ever confirms into the reels and never queues, takes $5c, and the three
; rows that do queue take $59-$5b.  None of them is a reel result
; (SlotAttackTbl: $94 $43 $ff $80 $7f $81 $fe).
OT6_SETZER_COIN    = $59        ; Coin Toss
OT6_SETZER_HIRE    = $5a        ; Hired Help
OT6_SETZER_JACKPOT = $5b        ; Jackpot (divine)
OT6_SETZER_SLOT    = $5c        ; Slot: the reels

OT6_CHAR_SETZER    = $09

; Jackpot is learned on Setzer's return in the World of Ruin: event switch
; $00ca, which the Kohlingen inn scene sets when he joins there
; (event_main.asm `switch $00CA=1`, the scene's last line) and nothing else
; sets.  Switch n is bit (n & 7) of $1e80 + (n >> 3).
OT6_JACKPOT_SW     = $1e80 + ($ca >> 3)
OT6_JACKPOT_BIT    = 1 << ($ca & 7)

; the coins' rates: gil per level, before the boost doubles them
OT6_COIN_RATE      = 30         ; Coin Toss and GP Rain (vanilla's level x 30)
OT6_HIRE_RATE      = 50         ; Hired Help

; ------------------------------------------------------------------------------

; [ open Slot as Setzer's table, the twin of Ot6ThiefListOpen ]
;
; Rows in the left column only (cells 0/6/12/18), right column $ff, so the
; window renders one clean column of up to four.  Per row: Index = the id
; above, Qty = the MP price as of this open (Jackpot's 99; the others are 0
; and draw blank), Flags = the row's own targeting byte, which the Tools
; confirm copies into w7e7a84 in place of the command's (BattleCmdProp[$0f]
; is MENU): Coin Toss takes GP Rain's own $6a (ONE_SIDE | INIT_GROUP |
; MULTI_TARGET | ENEMY, battle_cmd_prop.asm), Hired Help and Jackpot Steal's
; $43 (MANUAL | ONE_SIDE | ENEMY).  The Slot row's flags are never read.
; Jackpot's row is there once it is learned (OT6_JACKPOT_SW).
;
; entry: jsl from the C1 stub, db=$7e, a8/i16.  out: carry set = the table is
; built (the stub opens the Tools shell), carry clear = not Setzer (the stub
; opens the reels).  clobbers a/x/y.
.proc Ot6SetzerListOpen
        .a8
        .i16
        lda     $62ca           ; the active character's slot -> entity
        and     #$03
        asl
        longa
        and     #$00ff
        tax
        shorta0
        lda     $3ed8,x         ; character id
        cmp     #OT6_CHAR_SETZER
        beq     @table
        clc                     ; not Setzer: the reels, as before
        rtl
@table: ldx     #$0000
@pad:   lda     #$ff
        sta     $4005,x         ; wItemList::Index: empty = blank + unselectable
        stz     $4006,x         ; Qty 0: draws two blanks
        inx
        inx
        inx
        cpx     #$0018          ; 8 cells * 3 bytes
        bcc     @pad
        ; --- row 0: Slot (offset 0) ---
        lda     #OT6_SETZER_SLOT
        sta     $4005
        stz     $4006
        stz     $4007
        ; --- row 1: Coin Toss (offset 6) ---
        lda     #OT6_SETZER_COIN
        sta     $400b
        jsl     Ot6SetzerCost
        sta     $400c
        lda     #$6a            ; GP Rain's targeting: the enemy side
        sta     $400d
        ; --- row 2: Hired Help (offset 12) ---
        lda     #OT6_SETZER_HIRE
        sta     $4011
        jsl     Ot6SetzerCost
        sta     $4012
        lda     #$43            ; MANUAL|ONE_SIDE|ENEMY: one enemy
        sta     $4013
        ; --- row 3: Jackpot (offset 18), once learned ---
        lda     OT6_JACKPOT_SW
        and     #OT6_JACKPOT_BIT
        beq     @shown
        lda     #OT6_SETZER_JACKPOT
        sta     $4017
        jsl     Ot6SetzerCost
        sta     $4018
        lda     #$43
        sta     $4019
@shown: ; --- Config>Cursor honored as Blitz/Bushido/Tools/thief do ---
        stz     $7ba5           ; force MakeToolsList_04 to re-init the window
        lda     #$04
        sta     $7b9e           ; the tools state machine's draw phase
        lda     #$04
        sta     $6168           ; w7e6168 = 4: setzer mode (1 blitz, 2
        sec                     ;   bushido, 3 thief)
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ the MP price of a row of Setzer's table ]
;
; Jackpot is 99, the shared ultimate ceiling (kits.md: each character with an
; ultimate pays 99).  Slot is unpriced, as it has always been, and Coin Toss
; and Hired Help are paid in gil, not MP (Ot6CoinGil).  Flat at every boost
; level: the command is in Ot6BoostDmg's gate, so nothing under it is
; multiplied and nothing under it escalates.  Every other id (a reel's
; mapped attack in $3a7b at queue time, an empty cell) is 0.
; Pure leaf: id in A, price in A; preserves X and Y.  a8, either index width.
.proc Ot6SetzerCost
        .a8
        cmp     #OT6_SETZER_JACKPOT
        bne     @free
        lda     #99
        rtl
@free:  lda     #$00
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ the rate a coin row pays per level: Hired Help 50, Coin Toss 30 ]
; in: A = row id.  out: A = gil per level.  preserves X and Y.
.proc Ot6CoinRate
        .a8
        cmp     #OT6_SETZER_HIRE
        bne     @coin
        lda     #OT6_HIRE_RATE
        rtl
@coin:  lda     #OT6_COIN_RATE
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ the coins' gil: rate x level, doubled per boost point ]
;
; GP Rain's own price is the thrower's level x 30 (AttackerEffect_51) and its
; damage is twice the gil thrown, split over the targets.  The coins are the
; damage, so the boost buys more coins: x2 / x4 / x8 for 1 / 2 / 3 points,
; and that one purchase is both the bigger price and the bigger hit (boost
; pays once).  Hired Help's fee (rate 50) is one hire's and never doubles:
; its boost buys more hires, each paying its own fee (Ot6SetzerEffect,
; Ot6CoinTotal).  A monster's GP Rain is vanilla's: level x 30, no boost.
;
; The one price authority: the row's grey (Ot6SetzerRowGrey), the confirm's
; refusal (the same grey), and the gil the action takes (Ot6CoinPrice) all
; come through here, so they cannot disagree.
;
; in: A = the rate (gil per level), X = the payer's entity offset, db=$7e, a8,
; either index width.  out: the price in the whole 16-bit accumulator (B:A),
; a8 and the caller's index width.  preserves X and Y.  At the game's
; ceilings (level 99, rate 50, 3 points) it is 39,600: no overflow.
.proc Ot6CoinGil
        .a8
        php
        longi
        .i16
        phx
        phy
        pha                     ; [1,s] the rate
        txa                     ; width-neutral: the entity offset fits a byte
        cmp     #$08
        lda     #$00
        bcs     :+              ; a monster: no boost
        lda     $01,s
        cmp     #OT6_HIRE_RATE
        lda     #$00
        bcs     :+              ; Hired Help: the boost buys hires, one fee
                                ;   each, never a dearer one (Ot6CoinTotal)
        lda     OT6_BOOST_REVEALED,x    ; the pending boost
        and     #$03
:       pha                     ; [1,s] the boost, [2,s] the rate
        lda     $3b18,x         ; the payer's level
        longa
        .a16
        and     #$00ff
        tay                     ; Y = the level, counted down
        lda     $02,s
        and     #$00ff
        pha                     ; [1,s] rate16, [3,s] boost, [4,s] rate
        lda     #$0000
@mul:   cpy     #$0000
        beq     @mulled
        clc
        adc     $01,s
        dey
        bra     @mul
@mulled:
        tay                     ; Y = level x rate
        lda     $03,s
        and     #$0003
        tax                     ; X = the boost
        tya
@dbl:   cpx     #$0000
        beq     @done
        asl                     ; one point: twice the coins
        bcc     :+
        lda     #$ffff          ; (out of reach: saturate rather than wrap)
        bra     @done
:       dex
        bra     @dbl
@done:  tay                     ; Y = the price
        pla                     ; drop rate16
        pla                     ; drop the boost and the rate
        tya                     ; C = the price
        ply
        plx
        plp
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ the gil a coin row's whole action takes, at the pending boost ]
;
; Coin Toss: one throw, Ot6CoinGil's (the boost doubles the coins).  Hired
; Help: one fee a hire and 1 + boost hires (Ot6SetzerEffect adds the boost to
; the action's attack count, and each pass pays its fee at AttackerEffect_51),
; so the purse must hold them all.  At the ceilings (L99, 4 hires) 19,800.
; in: A = the row id, X = the payer's entity offset, a8, i16.  out: the gil
; in the 16-bit accumulator (B:A), a8.  preserves X and Y.
.proc Ot6CoinTotal
        .a8
        .i16
        phy
        pha                     ; [1,s] the row
        jsl     Ot6CoinRate
        jsl     Ot6CoinGil      ; C = one throw's / one hire's gil
        tay                     ; Y = it (all 16 bits under i16)
        pla                     ; the row
        cmp     #OT6_SETZER_HIRE
        bne     @one
        lda     OT6_BOOST_REVEALED,x
        and     #$03
        beq     @one            ; one hire
        cmp     #$02
        bcc     @two            ; 1 BP: two fees
        beq     @three          ; 2 BP: three fees
        longa                   ; 3 BP: four fees
        .a16
        tya
        asl
        asl
        bra     @sum
@three: .a8
        longa
        .a16
        tya
        asl
        phy
        clc
        adc     $01,s           ; two fees + one
        ply
        bra     @sum
@two:   .a8
        longa
        .a16
        tya
        asl
@sum:   tay
        shorta
        .a8
@one:   longa
        .a16
        tya
        shorta                  ; C = the gil (B keeps the high byte)
        .a8
        ply
        rtl
.endproc

; [ does the party's purse hold this price? ]
; in: the price in the 16-bit accumulator (B:A).  out: carry set = yes.
; preserves X and Y and the accumulator; a8 on return.  db=$7e.
.proc Ot6PurseHolds
        php
        longa
        .a16
        pha                     ; [1,s] the price
        lda     $1862           ; the gil's high byte (and the byte after it)
        and     #$00ff
        bne     @yes            ; 65,536 gil or more: any price fits
        lda     $1860           ; the gil's low word
        cmp     $01,s           ; carry set iff gil >= price
        bcs     @yes
        pla
        plp
        clc
        rtl
@yes:   pla
        plp
        sec
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ the setzer arm of Ot6BushidoRowGrey: a row the purse or the battle refuses ]
;
; Ot6BushidoRowGrey's shape, its fourth mode: a second grey reason on top of
; Ot6AbilityGrey's MP one, read by the row's colour (Ot6BlitzRowDecorate) and
; by the confirm's refusal (Ot6KitConfirmMP), so a greyed row is a refused row.
;   Coin Toss, Hired Help: the purse cannot pay the row's gil at the boost
;     pending now (a boost pressed with the window up re-stages the rows, so
;     the grey follows R and L);
;   Jackpot: already spent this battle (OT6_DIVINE_USED).
; a8/i16.  in: A = the MP grey ($00/$04), Y = the row's wItemList offset.
; out: A = A | ($04 if refused).  preserves X and Y.  Reached by jml from
; Ot6BushidoRowGrey, so the rtl returns to its caller.
.proc Ot6SetzerRowGrey
        .a8
        .i16
        pha                     ; [1,s] the MP grey
        phx
        lda     $62ca           ; the caster's slot -> entity
        and     #$03
        asl
        longa
        and     #$00ff
        tax
        shorta0
        lda     $4005,y         ; the row
        cmp     #OT6_SETZER_JACKPOT
        beq     @divine
        cmp     #OT6_SETZER_HIRE
        beq     @coins
        cmp     #OT6_SETZER_COIN
        bne     @white          ; Slot, an empty cell: the MP grey only
@coins: jsl     Ot6CoinTotal    ; the whole action's gil at the pending boost
        jsl     Ot6PurseHolds
        bcs     @white
        bra     @grey
@divine:
        lda     $3018,x         ; the caster's bit
        and     OT6_DIVINE_USED
        beq     @white
@grey:  plx
        pla
        ora     #$04            ; magic's disabled bit ($21|$04 = $25)
        rtl
@white: plx
        pla
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ a confirmed row of Setzer's table: Slot spins the reels, the rest target ]
;
; Called by the Tools-shell confirm (UpdateMenuState_30) in setzer mode, after
; Ot6KitConfirmMP has passed the row.  A kit row returns carry set and C1 takes
; the thief arm.  The Slot row is chained on to the reels: the Tools window is
; closed exactly as CloseToolsWindow closes it (window animation $21, the mode
; flag dropped), but the state that follows the close animation is $06,
; OpenSlotWindow, instead of $05, the command window -- the state the command
; window itself would go to had the player picked Slot there.  The queue row
; already holds command $0f (OpenCmdMenu wrote it when the table opened), and
; w7e7ba5 is cleared so the slot window inits itself as it does when opened
; from the command window.
;
; in: X = the picked cell's wItemList offset (_c18470's), db=$7e, a8, either
; index width.  out: carry set = a kit row (target select), clear = the reels
; are on their way.  preserves X and Y.
.proc Ot6SetzerConfirm
        .a8
        lda     $4005,x         ; the picked row
        cmp     #OT6_SETZER_SLOT
        beq     @reels
        sec                     ; Coin Toss, Hired Help, Jackpot: target select
        rtl
@reels: stz     $6168           ; leave setzer mode, as CloseToolsWindow does
        stz     $7ba5           ; the slot window inits itself
        lda     #$21
        sta     $7bf0           ; window animation $21: close the Tools window
        lda     #$01
        sta     $7bc2           ; wait for the animation ...
        lda     #$06
        sta     $7bc3           ; ... then OpenSlotWindow
        stz     $7bc4
        stz     $7bc5
        clc
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ FixPlayerAttack's Slot arm: a row of Setzer's table maps to no reel ]
;
; Vanilla reads a queued Slot action's attack byte as a reel result index and
; maps it through SlotAttackTbl.  A row id from the table is not one: keep it.
; in: A = the command ($0f), B = the queued attack byte.  out: carry set = a
; kit row (FixPlayerAttack skips the reel mapping), clear = a reel result.
; preserves A and B, X and Y.
.proc Ot6SlotKitRow
        .a8
        xba
        cmp     #OT6_SETZER_COIN
        bcc     @reel
        cmp     #OT6_SETZER_JACKPOT+1
        bcs     @reel
        xba
        sec
        rtl
@reel:  xba
        clc
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ Cmd_0f's head: is this action a row of Setzer's table? ]
;
; Records the row in OT6_SETZERROW (0 for a reel spin) for the two effect
; hooks below, and for a row sets attack name type 0, so the banner prints
; AttackName[$b6 - $51], the row's own name (ExecCmd $ff-filled $3412, so a
; reel spin's own banner logic is untouched).  The answer is the command whose
; targeting the row borrows for InitTarget at execution (a target that died
; since the menu is re-chosen by these rules): Coin Toss GP Rain's ($18, the
; enemy side), Hired Help and Jackpot Steal's ($05, one enemy).
;
; entry: jsl from Cmd_0f, a8/i8, db=$7e, y = the attacker.  out: carry set = a
; kit row, A = that targeting command; carry clear = a reel spin, vanilla.
; preserves x and y.
.proc Ot6SetzerExec
        .a8
        lda     $b6             ; the queued attack byte
        cmp     #OT6_SETZER_COIN
        bcc     @reel
        cmp     #OT6_SETZER_JACKPOT+1
        bcs     @reel
        sta     f:$7e0000+OT6_SETZERROW
        stz     $3412           ; attack name type 0: the row's name
        cmp     #OT6_SETZER_COIN
        bne     @single
        lda     #$18            ; GP Rain's targeting
        sec
        rtl
@single:
        lda     #$05            ; Steal's targeting: one enemy
        sec
        rtl
@reel:  lda     #$00
        sta     f:$7e0000+OT6_SETZERROW
        clc
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ a kit row's attack: the props, and the attacker effect that pays it ]
;
; After InitTarget (_c2298d: can't-dodge set, level, hit rate and the effect
; cleared).  Power 1 so CalcTargetDmg does not skip the attack (Cmd_18's own
; `inc $11a6`), no element, damage modification off (GP Rain's and the dice'
; own `stz $3414`), and $11a2 = $60, GP Rain's ignore-defense and don't-split
; (the coins' split over the targets is the effect's own divide).  Then:
;   Coin Toss, Hired Help: GP Rain's attacker effect $51, which takes the gil
;     (Ot6CoinPrice) and deals twice it; $b5 = $18 so the animation is GP
;     Rain's thrown coins.
;   Jackpot: the dice effect $09, whose Jackpot arm (Ot6JackpotDice) throws
;     the triple and sets the dice animation ($b5 = $26) itself.
; a8/i8, db=$7e.  out: A = the attacker special effect index (x2) for $11a9.
.proc Ot6SetzerEffect
        .a8
        lda     #$01
        sta     $11a6           ; power: nonzero
        stz     $11a1           ; no element
        stz     $3414           ; damage modification off
        lda     #$60
        sta     $11a2           ; ignore defense, don't split
        lda     f:$7e0000+OT6_SETZERROW
        cmp     #OT6_SETZER_COIN
        beq     @coins
        lda     OT6_BOOST_REVEALED,x    ; Hired Help and Jackpot: the boost
        and     #$03                    ;   buys more hits -- one more pass of
        clc                             ;   the attack a point (Ot6HitCount's
        adc     $3a70                   ;   counter), each its own hire or its
        sta     $3a70                   ;   own roll, so no point is lost to
        lda     f:$7e0000+OT6_SETZERROW ;   the 9,999 cap on one hit
        cmp     #OT6_SETZER_JACKPOT
        beq     @dice
@coins: lda     #$18
        sta     $b5             ; GP Rain's animation
        lda     #$a2            ; attacker special effect $51 (GP Rain)
        rtl
@dice:  lda     #$12            ; attacker special effect $09 (dice)
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ GP Rain's gil, and the coins' break class ]
;
; Replaces AttackerEffect_51's `lda $3b18,y / xba / lda #$1e / jsr MultAB`
; (level x 30, into the 16-bit accumulator): the same product for a monster,
; and for a character Ot6CoinGil's, which doubles it per boost point -- the
; boost buys coins, and the coins are the damage.  Before this a boosted GP
; Rain (the Coin Toss relic's) bought nothing: Ot6BoostDmg's multiplier runs
; in CalcDmg, and this effect overwrites the damage after it.
;
; The class (OT6_ATKCLASS), set here because nothing on GP Rain's path loads
; one (no MagicProp, no weapon, no item) and the per-target chip runs after
; this effect:
;   Coin Toss, and any character's GP Rain: special (coins are ¤, like
;     Setzer's cards and dice), one chip on each body it hits;
;   Hired Help: the sellsword's weapon fits the target -- the first of
;     slashing, piercing, bludgeoning in the target's weakness row, or none
;     (the hit lands unkeyed);
;   a monster's GP Rain: none (it is vanilla's, and hits the party).
;
; entry: jsl from AttackerEffect_51, a8/i8, db=$7e, y = the attacker.
; out: the 16-bit price in B:A, a8.  preserves X and Y.
.proc Ot6CoinPrice
        .a8
        tya                     ; width-neutral
        cmp     #$08
        bcs     @monster
        lda     $3a7c           ; the queued command
        cmp     #$0f
        bne     @rain           ; command $18: the Coin Toss relic's GP Rain
        lda     f:$7e0000+OT6_SETZERROW
        cmp     #OT6_SETZER_HIRE
        beq     @hire
@rain:  lda     #OT6_SPECIAL
        sta     f:$7e0000+OT6_ATKCLASS
        lda     #OT6_COIN_RATE
        bra     @price
@hire:  jsr     Ot6HireClass
        lda     #OT6_HIRE_RATE
        bra     @price
@monster:
        lda     #$00
        sta     f:$7e0000+OT6_ATKCLASS
        lda     #OT6_COIN_RATE
@price: phx
        tyx                     ; X = the payer (Ot6CoinGil pins its own width)
        jsl     Ot6CoinGil      ; level x rate (x 2^boost for a character)
        plx
        rtl
.endproc

; [ Hired Help's class: the first physical class the target is weak to ]
; $b9 = the monster half of the target mask (ChooseTarget has run).  a8, any
; index width.  writes OT6_ATKCLASS; preserves X and Y.
.proc Ot6HireClass
        .a8
        phx
        php
        longi
        .i16
        ldx     #$0008
        lda     $b9             ; monster mask (slots 0-5)
        beq     @none           ; a character target: no class
@mon:   lsr
        bcs     @have
        inx
        inx
        cpx     #$0014
        bcc     @mon
@none:  lda     #$00
        bra     @sto
@have:  lda     OT6_BP_CLASS,x  ; the monster's class weaknesses
        lsr
        bcs     @slash
        lsr
        bcs     @pierce
        lsr
        bcs     @bludg
        bra     @none
@slash: lda     #OT6_SLASH
        bra     @sto
@pierce:
        lda     #OT6_PIERCE
        bra     @sto
@bludg: lda     #OT6_BLUDG
@sto:   sta     f:$7e0000+OT6_ATKCLASS
        plp
        plx
        rts
.endproc

; ------------------------------------------------------------------------------

; [ Jackpot: the Fixed Dice come up a triple ]
;
; The dice effect (AttackerEffect_09) asks first.  Not a Jackpot (the queued
; command is not $0f, or this $0f action is not the Jackpot row): carry clear,
; and the effect rolls its dice as vanilla does.  A Jackpot: three dice of one
; face, the Fixed Dice's triple payoff by vanilla's own arithmetic -- face^3 x
; level x 2, times the face again for the triple, saturating at 65,535 as the
; effect's own loop does -- and carry set, so the effect returns at once.
;
; The face is a gamble, even odds on 1-6 (one battle Rand mod 6, within
; 1/256 of even), and the boost buys more of it: Ot6SetzerEffect adds the
; boost to the action's attack count, so 1 + boost passes each roll their own
; triple and land their own hit (owner, 2026-10-02: a gamble, and every point
; must land something under the 9,999 cap on one hit; playtesting tunes it).
; Nothing else is bought: no multiplier (the command is in Ot6BoostDmg's gate,
; and this damage is set here, after CalcDmg), and the MP price is flat.
;
; Null-break (kits.md: the Fixed Dice are the outliers, large numbers and no
; chip): OT6_ATKCLASS = special | null-break, and the element is clear.  The
; once-per-battle flag (OT6_DIVINE_USED) is spent here, where the triple
; lands (can't dodge).  The dice faces go to $b6/$b7 and $b5 = $26, the
; dice-roll animation vanilla's effect queues.
;
; entry: jsl from AttackerEffect_09's head, a8/i8, db=$7e, y = the attacker,
; x = the effect index.  out: carry set = handled.  preserves y.
Ot6JackpotCubeTbl:
        .byte   1, 8, 27, 64, 125, 216

.proc Ot6JackpotDice
        .a8
        lda     $3a7c           ; the queued command
        cmp     #$0f
        bne     @vanilla
        lda     f:$7e0000+OT6_SETZERROW
        cmp     #OT6_SETZER_JACKPOT
        beq     @jackpot
@vanilla:
        clc
        rtl
@jackpot:
        php
        shortai
        .a8
        .i8
        phx
        ot6_rand                ; A = 0-255
@mod6:  cmp     #$06
        bcc     @rolled
        sbc     #$06            ; (carry is set: the cmp above)
        bra     @mod6
@rolled:                        ; A = the face index 0-5, even odds within
                                ;   1/256 (256 is not a multiple of 6)
        sta     $b6             ; the third die
        sta     $b7
        asl
        asl
        asl
        asl
        ora     $b7
        sta     $b7             ; dice 1 and 2 (low/high nybble)
        ; --- face^3 x level x 2: the three dice and the level, as the effect
        ;     multiplies them (at most 216 x 198 = 42,768: no overflow) ---
        ldx     $b6
        lda     f:Ot6JackpotCubeTbl,x
        tax                     ; X = face^3, counted down
        lda     $3b18,y         ; level
        asl                     ; x 2 (at most 198)
        sta     OT6_SCR_SLOT2
        stz     OT6_SCR_SLOT2+1
        longa
        .a16
        lda     #$0000
@cube:  cpx     #$00
        beq     @cubed
        clc
        adc     OT6_SCR_SLOT2
        dex
        bra     @cube
@cubed: sta     OT6_SCR_SLOT2   ; face^3 x level x 2
        shorta
        .a8
        ldx     $b6             ; the triple: face times that, one more add
        longa                   ;   per face above 1
        .a16
@face4: cpx     #$00
        beq     @dmg
        clc
        adc     OT6_SCR_SLOT2
        bcc     :+
        lda     #$ffff          ; saturate, as the effect's own loop does
        bra     @dmg
:       dex
        bra     @face4
@dmg:   sta     $11b0           ; the damage
        shorta
        .a8
        stz     $3414           ; damage modification off (the effect's own)
        lda     #$20
        tsb     $11a4           ; can't dodge (the effect's own)
        lda     #OT6_SPECIAL|OT6_NULLBRK
        sta     f:$7e0000+OT6_ATKCLASS  ; no chip: the Fixed Dice teach nothing
        lda     #$26
        sta     $b5             ; the dice-roll animation (last: a watcher
                                ;   on $b5 sees the whole triple set)
        lda     $3018,y         ; the attacker's bit
        tsb     OT6_DIVINE_USED ; the divine is spent this battle
        plx
        plp
        sec
        rtl
.endproc
