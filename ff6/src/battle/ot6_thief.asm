; ------------------------------------------------------------------------------
; Locke's kit: the Steal submenu and the merchant pair
;
; Ot6ThiefListOpen/IsNew/Exec plus Filch and Bestow. The boost tilts on the
; plain Steal roll that this submenu's first row fires are in ot6_steal.asm;
; the row price comes from Ot6ThiefCost in ot6_loadout.asm.
; ------------------------------------------------------------------------------

; ------------------------------------------------------------------------------
; Locke's kit, first slice: the thief submenu and the merchant pair
; ------------------------------------------------------------------------------
;
; The command slot, and why this is a submenu behind Steal.
;
; Locke's command rows are FIGHT, STEAL, MAGIC, ITEM (char_prop.asm:157); the
; third row is MAGIC removed at runtime by InitCmd_03
; (battle_main.asm:14100-14108) for a character who knows no spell and holds
; no esper: $f6 (ValidateSpellList's count) and $f7 (the equipped esper) both
; zero take the `_5434: lda #$ff / sta $03,s` removal. So Locke has no spare
; command slot, and the moment he equips an esper the row he gets back is
; Magic.
;
; Locke does not need a new command. Steal is tier one of an eight-tier
; ladder, so the ladder belongs behind the Steal row, the same way SwdTech's
; eight tiers sit behind Cyan's. OpenCmdMenuTbl[$05] now opens a Tools-shell
; list whose first row is Steal itself. Three consequences:
;   * no command slot is spent, no row is shared, and Magic survives.
;   * Steal's price is visible: the drawn cost and the charged cost are the
;     same leaf (Ot6StealCost).
;   * the Thief Glove's Steal -> Capture relic rewrite (RelicCmdTbl1/2,
;     battle_main.asm:14152-14157) still lands on command $06, which has its
;     own OpenCmdMenuTbl slot and is untouched. A gloved Locke gets vanilla
;     Capture and no submenu.
;
; The id decision: cmd $05's $3a7b is a free byte, so this uses a second
; keyed table rather than widening Ot6AbilityCostTbl (whose key ranges are
; disjoint by construction): Steal's effect id $a4 collides with Bio
; Blaster's tool key in $11a9, Cmd_05's execute-time special-effect selector
; (battle_main.asm:3406), but Ot6CostFor reads $3a7b, the queued attack byte,
; which never sees $a4.
;
; $3a7b is free under command $05:
;   * FixPlayerAttack (battle_main.asm:12879-12960) has no cmd-$05 arm at
;     all, so nothing rewrites it on the way to the queue;
;   * init_buf_input leaves $2bb0,y = $ff (btlgfx_main.asm:18978), what a
;     Steal has queued in it;
;   * the Tools-shell confirm routes a chosen row's wItemList::Index through
;     w7e7a85 into $2bb0,y (set_target_data, btlgfx_main.asm:17293) and from
;     there to $3a7b (CalcCmdDelay, battle_main.asm:633-635).
; So the rows get per-ability ids at no cost. cmd $05 gets its own table,
; Ot6ThiefCostTbl, reached only from Ot6AbilityCost's @steal arm. Steal's own
; row still prices through Ot6StealCost, and any $3a7b this menu did not
; write ($ff from a Confused or AI-issued Steal, a Gogo mimic, or a relic
; Capture) falls through to plain Steal.
;
; The row ids are AttackName pad slots. ListTextCmd_0f renders any id >= $51
; from AttackName[id-$51] (btlgfx_main.asm:15308-15330), and indices $05-$0b
; (ids $56-$5c) are the empty pad after Joker Doom (SwdTech draws from
; BushidoName, not from these, which is why they are still empty). Steal
; $56, Filch $57, Bestow $58 are authored into src/text/attack_name_en.json
; so they ride the encode pipeline like every other name. Names render with
; no btlgfx change, and so does the banner during the action.
OT6_THIEF_STEAL  = $56
OT6_THIEF_FILCH  = $57
OT6_THIEF_BESTOW = $58

; ------------------------------------------------------------------------------

; [ open Steal as a submenu, the twin of Ot6BlitzListOpen ]
; Three rows in the left column only (cells 0/6/12, the Ot6BushidoWindow shape),
; right column and rows past the third $ff so the window renders one clean
; column.  Per row: Index = the id above, Qty = the MP cost the decorator draws,
; Flags = the row's own targeting byte, which the Tools confirm copies into
; w7e7a84 in place of the command's.  That last one is why Bestow can point at
; the party while Steal and Filch point at the enemy from the same command:
; Steal/Filch take $43 (MANUAL|ONE_SIDE|ENEMY, byte-identical to
; BattleCmdProp[$05]'s own target byte, battle_cmd_prop.asm:53) and Bestow takes
; $03 (MANUAL|ONE_SIDE, no ENEMY, the Banon's-Health side of the field,
; battle_cmd_prop.asm:117).  BattleCmdProp[$05] is not changed to
; MENU: an AI-issued or Confused Steal still needs the engine's own target
; flags, and the player path never re-derives them (the menu's chosen mask
; reaches $b8 and CalcCmdDelay skips ChooseTarget while $b8 is nonzero).
;
; entry: jsl from the C1 stub, db=$7e, a8/i16.  clobbers a/x/y (the caller's
; next act is jmp OpenToolsWindow, which reloads what it needs).
.proc Ot6ThiefListOpen
        .a8
        .i16
        ; --- $ff-fill all eight window cells (empty = blank + unselectable) ---
        ldx     #$0000
@pad:   lda     #$ff
        sta     $4005,x         ; wItemList::Index
        stz     $4006,x         ; Qty 0: cmd $02 draws two blanks, grey leaves white
        inx
        inx
        inx
        cpx     #$0018          ; 8 cells * 3 bytes
        bcc     @pad
        ; --- row 0: Steal (offset 0) ---
        lda     #OT6_THIEF_STEAL
        sta     $4005
        jsl     Ot6ThiefCost
        sta     $4006
        lda     #$43            ; MANUAL|ONE_SIDE|ENEMY
        sta     $4007
        ; --- row 1: Filch (offset 6) ---
        lda     #OT6_THIEF_FILCH
        sta     $400b
        jsl     Ot6ThiefCost
        sta     $400c
        lda     #$43
        sta     $400d
        ; --- row 2: Bestow (offset 12) ---
        lda     #OT6_THIEF_BESTOW
        sta     $4011
        jsl     Ot6ThiefCost
        sta     $4012
        lda     #$03            ; MANUAL|ONE_SIDE: the party side
        sta     $4013
        ; --- honor Config>Cursor the same way Blitz/Bushido/Tools do: leave the
        ; shared cursor triple alone, and force a fresh window re-init. ---
        stz     $7ba5           ; force MakeToolsList_04 to re-init the window
        lda     #$04
        sta     $7b9e           ; jump the tools state machine to its draw phase
        lda     #$03
        sta     $6168           ; w7e6168 = 3 : thief mode (1 blitz, 2 bushido)
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ is this pending Steal-command action Filch, or Bestow, or plain Steal? ]
;
; One discriminator for the charge, the menu and the execute dispatch, so they
; cannot disagree about which row fired.  in: A = the queued attack byte
; ($3a7b at charge time, $b6 at execute time).  out: carry set and A preserved
; when it is one of the two new rows; carry clear for anything else: $ff (the
; byte init_buf_input leaves, i.e. every Steal the submenu did not issue), $00,
; the Steal row itself, or garbage.  Preserves X and Y, and reads no state.
.proc Ot6ThiefIsNew
        .a8
        cmp     #OT6_THIEF_FILCH
        beq     @yes
        cmp     #OT6_THIEF_BESTOW
        beq     @yes
        clc
        rtl
@yes:   sec
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ run the thief row this Steal action selected ]
;
; The whole execute-side dispatch, so Cmd_05's hook is five bytes (jsl + bcs)
; and every decision stays in bank F0, keeping the row-id constants out of
; the C2 source.
;
; Set $3412 = 0 (attack name type "normal") for the two new rows.  ExecAction
; $ff-fills $3410-$341f before dispatching CmdTbl (battle_main.asm:3132), so
; $3412 is $ff at entry and ShowAttackName's `bmi` shows nothing, which is why
; a vanilla Steal has never printed a banner.  Type 0 is ShowAttackName_00, `lda
; $b6`, and $b6 is the row id, so Filch and Bestow print their names out of the
; AttackName pad slots this menu already named.  Steal is left alone: no banner,
; byte-for-byte as it ships.
;
; The widths are pinned here rather than assumed from the command context, per
; this file's standing discipline: a 16-bit A would make `lda $b6` a two-byte
; load and the row compare a two-byte compare, and a 16-bit `stz $3412` would
; also zero $3413, which ExecAttack reads three instructions later (`lda $3413 /
; bmi`) and expects to still be the $ff ExecAction's fill left there.  The carry
; is set after the plp so the answer survives the restore.
;
; entry: jsl from Cmd_05 after its `tyx` and `jsr _c2298a`, db=$7e (the command
; context's; $b6 is direct page and jsl preserves D).  x = y = attacker entity
; offset, $b6 = the queued row id, $b8/$b9 = the target mask the menu chose.
; out: carry SET = handled (skip the steal effect), carry CLEAR = plain Steal,
; run vanilla.  preserves x and y; clobbers a.
.proc Ot6ThiefExec
        php
        shortai
        .a8
        .i8
        lda     $b6
        jsl     Ot6ThiefIsNew           ; carry set = one of the two new rows
        bcc     @plain
        cmp     #OT6_THIEF_BESTOW
        beq     @bestow
        jsl     Ot6Filch
        bra     @named
@bestow:
        jsl     Ot6Bestow
@named: stz     $3412                   ; attack name type 0 -> AttackName[$b6-$51]
        plp
        sec                             ; handled: no steal special effect
        rtl
@plain: plp
        clc
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ Filch, chip a shield off the target and keep it as a boost point ]
;
; "Steal 1 BP from the target" is not implementable: an enemy has no BP bank
; to take from.  OT6_BP_CLASS ($3e9c) is a split table (ot6.asm's own header:
; "$3e9c,X characters: boost points (0-5) - monsters: class weaknesses"), and
; the monster half is seeded at battle init with the species' authored
; class-weakness mask (Ot6SeedShields, ot6_break.asm:36 for the authored row
; and :51 for the generated break floor).  Decrementing it would not take a
; boost point; it would corrupt the break system's record of what that
; monster is weak to.  Both shipped reactive earns already refuse the
; monster half for the same reason (Ot6RunicBP's and Ot6CoverBP's `cmp
; #$08`).
;
; A pure mint ("+1 BP to Locke, the enemy pays nothing") does not work
; either: Ot6ActionEnd pays every character +1 BP at the end of any turn
; they did not boost through (ot6_boost.asm:142-147), so an ability whose
; whole effect is +1 BP is worse than Fight, which earns the same pip and
; also swings.
;
; So Filch takes the resource the enemy does have: one shield, which Locke
; keeps as a boost point.  Ot6ClassChip only chips when the attack's class
; matches the target's weakness row, so Locke's piercing dagger does nothing
; against anything not weak to piercing.  Filch ignores class and element:
; it removes a shield whatever the row says, which makes it the party's only
; answer to an enemy whose weakness is unknown or unmatched.  It is not a
; reveal: it takes the shield without recording the row, so it complements
; Debilitator rather than replacing it.
;
; The BP is payment for the chip, not for pointing at an enemy: if no shield
; is removed, no pip is banked.  Against an already-Broken or shieldless
; target Filch is a no-op (the Ot6Assassinate fallback shape).  A landed
; Filch nets Locke +2 BP on the turn, this pip plus Ot6ActionEnd's own
; unboosted regen, the only way in the game to gain two in one turn.  The
; cap is Ot6ActionEnd's and untouched: a Filch at 5 BP still takes the
; shield and banks nothing, as Runic's absorb does.
;
; The break tail is Ot6Chip's, copied rather than called because Ot6Chip is
; tied to the elemental weak-branch contract ($11a1, the reveal, the codex
; write) and Filch reveals nothing: shields to zero sets OT6_BROKEN_TICKS and
; arms the break flash as pending ($ff), which Ot6BreakArm lands on the
; damage frame.  There is no damage numeral on a Filch, so Ot6ActionEnd's
; backstop is the frame that shows it, the same path a 0-damage chip already
; relies on.
;
; entry: jsl from Cmd_05's dispatch, db=$7e, a8/i8 (command context).  x =
; attacker entity offset, $b9 = the monster half of the target mask.  clobbers
; a; preserves x and y.
.proc Ot6Filch
        .a8
        php
        shortai
        .a8
        .i8
        cpx     #$08
        bcs     done            ; monster attacker: never
        phy                     ; the caller still needs y (i8: one byte)
        ; --- primary monster target -> entity offset (Ot6Assassinate's scan) ---
        ldy     #$08
        lda     $b9             ; monster mask (slots 0-5)
@mon:   lsr
        bcs     @have
        iny
        iny
        cpy     #$14
        bcc     @mon
        bra     @out            ; no monster target: nothing to take
@have:  lda     OT6_BROKEN_TICKS,y
        bne     @out            ; already broken: no chip until recovery
        lda     OT6_SHIELD_CUR,y
        beq     @out            ; shieldless: plain no-op
        dec     a
        sta     OT6_SHIELD_CUR,y
        bne     @bank
        lda     #OT6_BREAK_TICKS
        sta     OT6_BROKEN_TICKS,y         ; shields down: Break
        lda     #$ff
        sta     OT6_BRKTICK-8,y            ; arm the flash as pending
@bank:  ; --- the chip landed: Locke keeps it as a boost point ---
        lda     OT6_BP_CLASS,x
        cmp     #$05
        bcs     @out            ; the bank cap holds; a filch never wraps
        inc     a
        sta     OT6_BP_CLASS,x
        jsr     Ot6BankMoved    ; an open kit window's BP grey is read
                                ;   at open only
@out:   ply
done:   plp
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ Bestow, hand one boost point to an ally ]
;
; Both ends of this transfer are character rows of OT6_BP_CLASS, so unlike
; Filch it needs no substitute resource.
;
; Locke's half of the transfer is not debited here.  This proc arms
; OT6_BOOST_REVEALED (the pending-boost byte) to 1 and lets Ot6ActionEnd do the
; subtraction at the end of the action, which is the one place in the game that
; charges BP (ot6_boost.asm:130-141).  Two things follow, and both are why it
; is done this way:
;   * the debit and the "no regen on a spent turn" rule are the same arm of
;     Ot6ActionEnd, so Bestow cannot accidentally be free.  Charging it here
;     instead would leave the pending byte at 0, Ot6ActionEnd would pay Locke
;     his +1 regen, and a Bestow would cost him nothing net, which is one free
;     pip per turn for 4 MP.
;   * there is exactly one BP charge path in the game and this uses it, so no
;     second clamp, no second cap, no way for the two to drift.
; If the player has already armed a pending boost with L/R before opening the
; menu, that spend stands and this adds nothing to it (the `bne` below): Locke
; pays at least one either way and cannot be double-charged.  Boosting into
; Bestow buys nothing, because it is not a damage verb and Ot6BoostDmg's cmd-$05
; gate already refuses to multiply anything under this command, so that is
; wasted BP in the same way boosting into Runic is.
;
; Three refusals, all no-ops rather than errors, because by the time this
; runs the turn is committed and there is no menu left to signal in:
;   * Locke holds no BP (nothing to give);
;   * the chosen ally is Locke himself (a transfer to himself would change
;     nothing and spend the turn);
;   * the ally is already at the 5-BP cap (Ot6ActionEnd's cap, used here
;     rather than re-implemented, as Runic and True Knight do).
; The first of these is also greyed in the menu (Ot6BushidoRowGrey's thief arm),
; so the common case is refused before the turn is spent.
;
; entry: jsl from Cmd_05's dispatch, db=$7e, a8/i8 (command context).  x =
; attacker entity offset, $b8 = the character half of the target mask.  clobbers
; a; preserves x and y.
.proc Ot6Bestow
        .a8
        php
        shortai
        .a8
        .i8
        cpx     #$08
        bcs     done            ; monster attacker: never
        lda     OT6_BP_CLASS,x
        beq     done            ; nothing to give
        lda     $3018,x         ; a transfer to himself changes nothing: the
        and     $b8             ;   attacker's own character bit inside the
        bne     done            ;   chosen mask means he pointed at himself
        phy                     ; the caller still needs y (i8: one byte)
        ; --- primary character target -> entity offset (bit c -> offset c*2) ---
        ldy     #$00
        lda     $b8             ; character mask (slots 0-3)
@chr:   lsr
        bcs     @have
        iny
        iny
        cpy     #$08
        bcc     @chr
        bra     @out            ; no character target: nothing to hand it to
@have:  lda     OT6_BP_CLASS,y
        cmp     #$05
        bcs     @out            ; the ally is capped: the point would be lost
        inc     a
        sta     OT6_BP_CLASS,y  ; the ally banks it
        jsr     Ot6BankMoved    ; the ALLY's bank moved, and the ally
                                ;   is the one who may have a kit window open,
                                ;   since Locke is mid-action
        lda     OT6_BOOST_REVEALED,x       ; Locke's half: let Ot6ActionEnd charge it
        bne     @out            ;   a spend already armed by L/R stands as is
        lda     #$01
        sta     OT6_BOOST_REVEALED,x
@out:   ply
done:   plp
        rtl
.endproc
