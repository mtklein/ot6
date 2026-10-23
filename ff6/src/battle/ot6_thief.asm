; ------------------------------------------------------------------------------
; Locke's kit: the Steal submenu and its eight rows
;
; Ot6ThiefListOpen/IsNew/Exec, Filch and Bestow, and the five rows the story
; teaches (#382): Mug, Trickshot, Dismantle, Appraise and the divine Master's
; Mark.  The boost tilts on the plain Steal roll that this submenu's first row
; fires are in ot6_steal.asm; the row price comes from Ot6ThiefCost in
; ot6_loadout.asm.  Design and rulings: docs/design/kits.md, "Locke".
; ------------------------------------------------------------------------------

inc_lang "text/bushido_name_%s.inc"     ; Ot6KitListName's SwdTech names

; ------------------------------------------------------------------------------
; Locke's kit: the thief submenu and the merchant pair
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
; write ($ff from a Confused or AI-issued Steal, or a relic Capture) falls
; through to plain Steal.  A Gogo's Mimic of Steal, Filch or Bestow never
; reaches this arm: mimicreplace puts the source's command/attack word
; ($3f20 = $56xx..$58xx) into Mimic's own queue row without CreateAction, so
; the copy keeps Mimic's 0 and the row runs free (measured #261,
; tools/tests/battle_mimicboost.lua: the copier paid 0 MP where Locke paid
; 4 / 6 / 5).  Free is the ruling (mp-economy.md, "Mimic copies the action,
; not the price"); the copy's effect is Locke's row, with the copier's
; own pips (Filch banks one for the copier, Bestow gives one of the
; copier's).
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

; The later rows (#382).  AttackName has no free slot left ($56-$5c went to
; this list and Setzer's), so these ids name nothing there: the list draws
; them from Ot6ThiefName (Ot6KitListName, thief mode) and the banner from
; Ot6ThiefBannerName (attack name type 3).  Under command $05 the queued attack
; byte is this menu's own (see above), so any id outside the three rows above
; and the $ff of a Steal nobody chose is free; $e0-$e4 are clear of both.
OT6_THIEF_MUG       = $e0       ; Capture, as a row: a swing that steals
OT6_THIEF_TRICK     = $e1       ; a thrown coin: piercing, past defense
OT6_THIEF_DISMANTLE = $e2       ; a stab that corrodes defense
OT6_THIEF_APPRAISE  = $e3       ; Scan's read, Locke's way
OT6_THIEF_MARK      = $e4       ; the divine: steal from all, read all

OT6_TRICK_POWER     = 40        ; the coin's battle power (Fight's formula)
OT6_DISMANTLE_POWER = 20        ; the stab's battle power
OT6_MARK_BOOST      = 3         ; the divine's one gate: a full boost

; ------------------------------------------------------------------------------

; [ the eight rows: id, window cell, targeting, the story beat that teaches ]
;
; In page order, which is the window read a column at a time: Steal, Filch,
; Bestow, Mug down the left, Trickshot, Dismantle, Appraise and Master's Mark
; down the right.  The cell is the wItemList offset (row*6, +3 for the right
; column).  Steal, Filch and Bestow come at join (kits.md: the grant-at-join
; ruling); the other five come by story, each an event switch its beat sets
; once and nothing clears (event_main.asm):
;   Trickshot   $001A  the Lete River ride is run (:39327)
;   Mug         $001E  Locke's South Figaro escape is done (:21017)
;   Dismantle   $0079  the Sealed Gate opens (:46318)
;   Appraise    $008D  Strago is met in Thamasa (:69857)
;   Master's    $00A0  the Air Force gauntlet, on the way to the Floating
;     Mark             Continent (:13445; the landing itself sets nothing)
; Switch n is bit (n & 7) of $1e80 + (n >> 3); the record holds the byte's
; offset from $1e80 and the bit, and a zero bit means "at join".
.define OT6_SW(n) <((n) >> 3), <(1 << ((n) & 7))
OT6_THIEF_REC  = 5
OT6_THIEF_ROWS = 8
Ot6ThiefRowTbl:
        .byte   OT6_THIEF_STEAL,     0, $43, 0, 0
        .byte   OT6_THIEF_FILCH,     6, $43, 0, 0
        .byte   OT6_THIEF_BESTOW,   12, $03, 0, 0
        .byte   OT6_THIEF_MUG,      18, $43, OT6_SW($001e)
        .byte   OT6_THIEF_TRICK,     3, $43, OT6_SW($001a)
        .byte   OT6_THIEF_DISMANTLE, 9, $43, OT6_SW($0079)
        .byte   OT6_THIEF_APPRAISE, 15, $43, OT6_SW($008d)
        .byte   OT6_THIEF_MARK,     21, $6a, OT6_SW($00a0)
        ; Master's Mark takes Coin Toss's targeting ($6a: the cursor opens
        ; on the whole enemy side); it reads and robs every body whatever
        ; the cursor names

; the list's names, one 10-letter record per row in the table's order, in
; AttackName's encoding (the field page draws them through LoadArrayItem)
Ot6ThiefName:
        .byte   $92, $ad, $9e, $9a, $a5, $ff, $ff, $ff, $ff, $ff ; Steal
        .byte   $85, $a2, $a5, $9c, $a1, $ff, $ff, $ff, $ff, $ff ; Filch
        .byte   $81, $9e, $ac, $ad, $a8, $b0, $ff, $ff, $ff, $ff ; Bestow
        .byte   $8c, $ae, $a0, $ff, $ff, $ff, $ff, $ff, $ff, $ff ; Mug
        .byte   $93, $ab, $a2, $9c, $a4, $ac, $a1, $a8, $ad, $ff ; Trickshot
        .byte   $83, $a2, $ac, $a6, $9a, $a7, $ad, $a5, $9e, $ff ; Dismantle
        .byte   $80, $a9, $a9, $ab, $9a, $a2, $ac, $9e, $ff, $ff ; Appraise
        .byte   $8c, $ac, $ad, $ab, $c5, $8c, $9a, $ab, $a4, $ff ; Mstr.Mark (nine:
                                ;   the price needs a gap)

; the battle banner's names for the five later rows ($e0-$e4), 13 letters:
; the message window takes the divine's whole name
OT6_BANNER_LEN = 13
Ot6ThiefBanner:
        .byte   $8c, $ae, $a0, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff ; Mug
        .byte   $93, $ab, $a2, $9c, $a4, $ac, $a1, $a8, $ad, $ff, $ff, $ff, $ff ; Trickshot
        .byte   $83, $a2, $ac, $a6, $9a, $a7, $ad, $a5, $9e, $ff, $ff, $ff, $ff ; Dismantle
        .byte   $80, $a9, $a9, $ab, $9a, $a2, $ac, $9e, $ff, $ff, $ff, $ff, $ff ; Appraise
        .byte   $8c, $9a, $ac, $ad, $9e, $ab, $c3, $ac, $fe, $8c, $9a, $ab, $a4 ; Master's Mark

; ------------------------------------------------------------------------------

; [ has Locke learned this row? ]
; in: X = the row's record offset in Ot6ThiefRowTbl.  out: carry set = known.
; a8/i16, db=$7e.  preserves X and Y; clobbers A.
.proc Ot6ThiefRowKnown
        .a8
        .i16
        lda     f:Ot6ThiefRowTbl+4,x
        beq     @yes            ; at join
        phx
        pha                     ; [1,s] the switch's bit
        lda     f:Ot6ThiefRowTbl+3,x
        longa
        and     #$00ff
        tax
        shorta0
        lda     $1e80,x         ; the switch's byte
        and     $01,s
        sta     $01,s
        pla                     ; the switch's bit, or 0 (Z from the pull)
        beq     @no
        plx
@yes:   sec
        rtl
@no:    plx
        clc
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ which row of the table is this id? ]
; in: A = a row id.  out: carry set and X = its record offset, or carry clear.
; a8/i16.  preserves A and Y.
.proc Ot6ThiefRowOf
        .a8
        .i16
        ldx     #$0000
@scan:  cmp     f:Ot6ThiefRowTbl,x
        beq     @hit
        inx
        inx
        inx
        inx
        inx
        cpx     #OT6_THIEF_REC*OT6_THIEF_ROWS
        bcc     @scan
        clc
        rtl
@hit:   sec
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ open Steal as a submenu, the twin of Ot6BlitzListOpen ]
; Every learned row of the table goes in its own cell, the rest stay $ff
; (blank and unselectable), so the window is two columns of up to four.  Per
; row: Index = the id, Qty = the MP cost as of this open, Flags = the row's
; own targeting byte, which the Tools confirm copies into w7e7a84 in place
; of the command's.  That is why Bestow can point at the party while the
; rest point at the enemy from the same command: Steal's $43
; (MANUAL|ONE_SIDE|ENEMY, byte-identical to BattleCmdProp[$05]'s own target
; byte, battle_cmd_prop.asm:53), Bestow's $03 (MANUAL|ONE_SIDE, no ENEMY, the
; Banon's-Health side of the field, battle_cmd_prop.asm:117).
; BattleCmdProp[$05] is not changed to MENU: an AI-issued or Confused Steal
; still needs the engine's own target flags, and the player path never
; re-derives them (the menu's chosen mask reaches $b8 and CalcCmdDelay skips
; ChooseTarget while $b8 is nonzero).
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
        ; --- every learned row into its cell ---
        ldx     #$0000
@row:   jsl     Ot6ThiefRowKnown
        bcc     @next
        lda     f:Ot6ThiefRowTbl+1,x
        longa
        and     #$00ff
        tay                     ; Y = the cell
        shorta0
        lda     f:Ot6ThiefRowTbl,x
        sta     $4005,y
        jsl     Ot6ThiefCost    ; flat here; Ot6KitRowCost redraws the live
                                ;   price per draw (Trickshot's boost)
        sta     $4006,y
        lda     f:Ot6ThiefRowTbl+2,x
        sta     $4007,y
@next:  inx
        inx
        inx
        inx
        inx
        cpx     #OT6_THIEF_REC*OT6_THIEF_ROWS
        bcc     @row
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

; [ is this pending Steal-command action one of the kit's rows past Steal? ]
;
; One discriminator for the charge, the menu and the execute dispatch, so they
; cannot disagree about which row fired.  in: A = the queued attack byte
; ($3a7b at charge time, $b6 at execute time).  out: carry set and A preserved
; when it is a row with its own price and effect (Filch, Bestow and the five
; later rows); carry clear for anything else: $ff (the byte init_buf_input
; leaves, i.e. every Steal the submenu did not issue), $00, the Steal row
; itself, or garbage.  Preserves X and Y, and reads no state.
.proc Ot6ThiefIsNew
        .a8
        cmp     #OT6_THIEF_FILCH
        beq     @yes
        cmp     #OT6_THIEF_BESTOW
        beq     @yes
        cmp     #OT6_THIEF_MUG
        bcc     @no
        cmp     #OT6_THIEF_MARK+1
        bcc     @yes
@no:    clc
        rtl
@yes:   sec
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ Cmd_05's head: is this action the Mug row? ]
;
; Mug is Capture as a row of the kit (vanilla's Thief Glove verb, which FF3-US
; prints as Capture): a Fight swing whose every landing hit also tries a
; Steal.  So it runs as Capture runs, through Cmd_06: the weapon's swing and
; its class (Locke's dagger pierces), the steal on the hit (ExecAttack's
; `$b5 = $06` arm sets special effect $52), and the boost buying swings
; (Ot6FightBoost), which is what a boosted Fight or Capture buys.  The boost
; pays once (guidelines.md): the steal on a Mug's hit rolls vanilla's odds at
; every boost (Ot6StealBoostLevel's and Ot6StealSlot's capture test).  The
; price was charged at the queue as this row's (Ot6AbilityCost's @steal arm
; keys on the queued byte), so running as Capture changes no number.
; entry: jsl from Cmd_05 after its `tyx`, any widths, db=$7e, y = attacker.
; out: carry set = Mug ($b5 = $06, the caller jumps to Cmd_06); clear = any
; other Steal action.  preserves X and Y.
.proc Ot6MugCheck
        php
        sep     #$20
        .a8
        tya                     ; width-neutral: a character's action only
        cmp     #$08
        bcs     @no
        lda     $b6
        cmp     #OT6_THIEF_MUG
        bne     @no
        lda     #$06
        sta     $b5             ; Capture: the animation and the steal-on-hit
        plp
        sec
        rtl
@no:    plp
        clc
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ run the thief row this Steal action selected ]
;
; The whole execute-side dispatch, so Cmd_05's hook is five bytes (jsl + bcs)
; and every decision stays in bank F0, keeping the row-id constants out of
; the C2 source.
;
; The banner.  ExecAction $ff-fills $3410-$341f before dispatching CmdTbl
; (battle_main.asm:3132), so $3412 is $ff at entry and ShowAttackName's `bmi`
; shows nothing, which is why a vanilla Steal has never printed a banner.
; Filch and Bestow set type 0 (ShowAttackName_00, `lda $b6`), which prints
; AttackName[$b6-$51], the pad slots this menu named.  The later rows set type
; 3, unused in vanilla and pointed at the same `lda $b6`, whose message arm
; (_c2bb11's third, Ot6ThiefBannerName) names them from Ot6ThiefBanner.  Steal
; is left alone: no banner, byte-for-byte as it ships.
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
        jsl     Ot6ThiefIsNew           ; carry set = one of the kit's rows
        bcc     @plain
        cmp     #OT6_THIEF_BESTOW
        beq     @bestow
        cmp     #OT6_THIEF_FILCH
        beq     @filch
        cmp     #OT6_THIEF_TRICK
        beq     @trick
        cmp     #OT6_THIEF_DISMANTLE
        beq     @dismantle
        cmp     #OT6_THIEF_APPRAISE
        beq     @appraise
        cmp     #OT6_THIEF_MARK
        bne     @plain                  ; (Mug left at Cmd_05's head)
        jsl     Ot6MastersMark
        bra     @later
@appraise:
        jsl     Ot6Appraise
        bra     @later
@dismantle:
        jsl     Ot6Dismantle
        bra     @later
@trick: jsl     Ot6Trickshot
@later: lda     #$03                    ; attack name type 3 -> Ot6ThiefBanner
        sta     $3412
        plp
        sec
        rtl
@filch: jsl     Ot6Filch
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
; Filch reads no boost (#463): a boost raised for it buys nothing and is
; kept (Ot6KeepBoost), so a boosted Filch ends the turn as the unboosted one
; does, the filched pip and the regen pip both.  A Mimic's copy is the same.
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
        jsl     Ot6KeepBoost    ; the boost buys nothing here
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
;     pip per turn for 5 MP (Ot6ThiefCostTbl; kits.md, mp-economy.md).
;   * there is exactly one BP charge path in the game and this uses it, so no
;     second clamp, no second cap, no way for the two to drift.
; The pip handed over is the whole charge, at every boost (#463): boosting
; into Bestow buys nothing (it is not a damage verb, and Ot6BoostDmg's cmd-$05
; gate refuses to multiply anything under this command), so a pending boost
; the player raised with L/R is set to the one pip, not added to: a Bestow at
; two or three points costs the one it gives.  A Mimic's copy is the same.
;
; Three refusals, all no-ops rather than errors, because by the time this
; runs the turn is committed and there is no menu left to signal in.  Each
; keeps the boost (Ot6KeepBoost): nothing was handed over, so nothing is
; charged and the turn earns its regen pip, boosted or not:
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
        phy                     ; the caller still needs y (i8: one byte)
        lda     OT6_BP_CLASS,x
        beq     @keep           ; nothing to give
        lda     $3018,x         ; a transfer to himself changes nothing: the
        and     $b8             ;   attacker's own character bit inside the
        bne     @keep           ;   chosen mask means he pointed at himself
        ; --- primary character target -> entity offset (bit c -> offset c*2) ---
        ldy     #$00
        lda     $b8             ; character mask (slots 0-3)
@chr:   lsr
        bcs     @have
        iny
        iny
        cpy     #$08
        bcc     @chr
        bra     @keep           ; no character target: nothing to hand it to
@have:  lda     OT6_BP_CLASS,y
        cmp     #$05
        bcs     @keep           ; the ally is capped: the point would be lost
        inc     a
        sta     OT6_BP_CLASS,y  ; the ally banks it
        jsr     Ot6BankMoved    ; the ALLY's bank moved, and the ally
                                ;   is the one who may have a kit window open,
                                ;   since Locke is mid-action
        lda     #$01            ; Locke's half: Ot6ActionEnd charges the one
        sta     OT6_BOOST_REVEALED,x    ;   pip, whatever L/R raised
        bra     @out
@keep:  jsl     Ot6KeepBoost    ; refused: nothing given, nothing charged
@out:   ply
done:   plp
        rtl
.endproc


; ------------------------------------------------------------------------------

; [ Trickshot: a thrown coin, piercing, past defense ]
;
; One hit on one enemy by Fight's own physical formula (CalcDmg: Locke's
; level and vigor) at a fixed battle power, OT6_TRICK_POWER, whatever he
; holds: the coin is the weapon, so the hit pierces (OT6_PIERCE, one chip on a
; pierce-weak body) with a sword in his hand as with a dagger.  It ignores
; defense ($11a2 bit 5), which in the damage modification also skips the
; target's row and its Defend, and it cannot be dodged (_c2298d's $11a4).
; The animation is GP Rain's coin ($b5 = $18), and $b5 is also the command
; Ot6BoostDmg reads: $18 is not in its gate, so the boost multiplies the hit
; x2/x4/x8, and the price escalates with it (Ot6AbilityCost's @steal arm and
; Ot6ThiefRowCost), the one test kits.md states.
; entry: jsl from Ot6ThiefExec, a8/i8, x = attacker.  clobbers a.
.proc Ot6Trickshot
        .a8
        .i8
        lda     #OT6_TRICK_POWER
        sta     $11a6
        lda     #$21            ; physical, ignore defense
        sta     $11a2
        bra     Ot6ThiefHit
.endproc

; [ Dismantle: a stab that corrodes the target's defense ]
;
; The corrode lands first, then a weak piercing stab at the lowered defense.
; Each step takes a quarter of the target's defense (at least one point), and
; the boost buys steps: one at 0 BP, four at 3 BP (x3/4 each, so about a third
; of it left).  It lasts the battle.  The boost buys the corrode, so the stab
; is not multiplied: $b5 stays Steal's $05, which Ot6BoostDmg gates, and the
; price is flat.
; entry: jsl from Ot6ThiefExec, a8/i8, x = attacker, $b9 = the monster mask.
; clobbers a; preserves x and y.
.proc Ot6Dismantle
        .a8
        .i8
        phy
        jsr     Ot6ThiefTarget  ; y = the primary monster target
        bcc     @hit            ; none: the stab alone
        lda     OT6_BOOST_REVEALED,x
        and     #$03
        inc     a
        pha                     ; [1,s] the steps
@step:  lda     $3bb8,y         ; the body's defense
        beq     @done
        lsr
        lsr                     ; a quarter of it...
        bne     :+
        lda     #$01            ; ...or at least one point
:       eor     #$ff
        sec
        adc     $3bb8,y         ; defense - the cut
        sta     $3bb8,y
        pla
        dec     a
        pha
        bne     @step
@done:  pla
@hit:   ply
        lda     #OT6_DISMANTLE_POWER
        sta     $11a6
        lda     #$01            ; physical, defense applies (what is left)
        sta     $11a2
        ; fall through
.endproc

; [ the rest of a thief hit's props: Fight's formula, piercing ]
; a8/i8, x = attacker.  $11a6 and $11a2 are the caller's.
.proc Ot6ThiefHit
        .a8
        .i8
        stz     $11a1           ; no element
        lda     $3b2c,x         ; vigor * 2, as _magicpunch loads it
        sta     $11ae
        lda     $3b18,x         ; level, as InitAttackerLevel loads it
        sta     $11af
        lda     #OT6_PIERCE
        sta     f:$7e0000+OT6_ATKCLASS
        lda     $b6
        cmp     #OT6_THIEF_TRICK
        bne     :+
        lda     #$18            ; the coin: GP Rain's animation, and a
        sta     $b5             ;   command the multiplier serves
:       rtl
.endproc

; [ the primary monster target -> its entity offset ]
; a8/i8.  in: $b9.  out: carry set and y = the body, or carry clear.
.proc Ot6ThiefTarget
        .a8
        .i8
        ldy     #$08
        lda     $b9             ; monster mask (slots 0-5)
@mon:   lsr
        bcs     @have
        iny
        iny
        cpy     #$14
        bcc     @mon
        clc
        rts
@have:  sec
        rts
.endproc

; ------------------------------------------------------------------------------

; [ Appraise: read one enemy's weaknesses, or every enemy's with a boost ]
;
; Strago's Scan read (Ot6AnalyzeOne): every weak element and class of the
; body goes onto the HUD and into the codex for its species, nothing chipped,
; and a body vanilla will not scan stays unread.  The boost buys breadth, as
; on Scan: a point or more reads every enemy on the field.  No damage, so the
; price is flat (the boost buys no multiplier); the reveal commits with the
; action's end (Ot6ActionEnd's Ot6RevealCommit, an action with no numeral).
; entry: jsl from Ot6ThiefExec, a8/i8, x = attacker.  preserves x and y.
.proc Ot6Appraise
        .a8
        .i8
        phy
        lda     OT6_BOOST_REVEALED,x
        bne     @all
        jsr     Ot6ThiefTarget
        bcc     @out
        php
        rep     #$10
        .i16
        jsr     Ot6AnalyzeOne
        plp
        .i8
        bra     @out
@all:   php
        rep     #$10
        .i16
        ldy     #$0008
@slot:  jsr     Ot6ThiefBody
        bcc     :+
        jsr     Ot6AnalyzeOne
:       iny
        iny
        cpy     #$0014
        bcc     @slot
        plp
        .i8
@out:   ply
        rtl
.endproc

; [ is monster slot y a body on the field? ] a8/i16.  out: carry.
.proc Ot6ThiefBody
        .a8
        .i16
        lda     $3aa0,y         ; present
        lsr
        bcc     @no
        lda     $3bf4,y         ; and standing (HP, either byte)
        ora     $3bf5,y
        beq     @no
        sec
        rts
@no:    clc
        rts
.endproc

; ------------------------------------------------------------------------------

; [ Master's Mark: steal from every enemy and read every enemy ]
;
; Locke's divine, at the full boost (kits.md "Divines": the one gate is three
; points).  Every body on the field is read as Appraise reads it and robbed
; as a 3-BP Steal robs: its rare item if it has one, else its common, taken
; outright, no roll (Ot6StealSlot's cap rule), and a body with nothing, or
; already robbed, gives nothing.  No damage.  Picked at three and taken back
; to fewer (L in target select), it does nothing and charges nothing: the
; queue priced it at 0 (Ot6ThiefCharge), and the pending boost is cleared
; here, so Ot6ActionEnd reads an unboosted turn and pays its pip (Jackpot's
; rule, Ot6JackpotDice: nothing bought is nothing charged).
; Each item goes straight to the battle's obtained-items queue (BtlGfx $05,
; the one vanilla's end-of-action grant uses), since the attacker's one
; $32f4 slot holds a single item per action.
; entry: jsl from Ot6ThiefExec, a8/i8, x = attacker.  preserves x and y.
.proc Ot6MastersMark
        .a8
        .i8
        lda     OT6_BOOST_REVEALED,x
        cmp     #OT6_MARK_BOOST
        bcs     @full
        stz     OT6_BOOST_REVEALED,x    ; under the full boost: nothing done,
        rtl                             ;   nothing charged
@full:  phy
        php
        rep     #$10
        .i16
        ldy     #$0008
@slot:  jsr     Ot6ThiefBody
        bcc     @next
        jsr     Ot6AnalyzeOne
        lda     $3308,y         ; the rare
        cmp     #$ff
        bne     @take
        lda     $3309,y         ; else the common
        cmp     #$ff
        beq     @next           ; nothing to take
@take:  pha
        lda     #$ff
        sta     $3308,y         ; robbed, as a steal leaves it
        sta     $3309,y
        pla
        jsr     Ot6GrantItem
@next:  iny
        iny
        cpy     #$0014
        bcc     @slot
        plp
        .i8
        ply
@out:   rtl
.endproc

; [ add one item to what the party obtained this battle ]
; LoadItemProp (battle_main.asm) into $2e72-$2e76, quantity 1, then battle
; graphics $05, the pair _c262c7 runs for a stolen item.  a8/i16, A = item id
; (not $ff), db=$7e.  preserves X and Y.  jsr (rts).
.proc Ot6GrantItem
        .a8
        .i16
        phx
        phy
        pha
        lda     #$80            ; make item unusable
        sta     $2e73
        lda     #$ff
        sta     $2e76           ; clear all equippability flags
        pla
        sta     $2e72           ; item number
        longa
        and     #$00ff
        asl                     ; id * 2
        pha
        asl
        asl
        asl
        asl                     ; id * 32
        sec
        sbc     $01,s           ; id * 30, ItemProp's record
        tax
        pla
        shorta0
        lda     f:ItemProp+14,x ; targetting
        sta     $2e74
        lda     f:ItemProp,x
        pha
        pha
        asl
        asl
        and     #$80            ; item useable in battle
        trb     $2e73
        pla
        asl
        and     #$20            ; item can be thrown
        tsb     $2e73
        pla
        and     #$07            ; item type
        phx
        longa
        and     #$0007
        tax
        shorta0
        lda     f:ItemTypeMaskTbl,x
        plx
        asl
        tsb     $2e73
        bcs     @grant
        longa
        clc
        stz     $ee
        lda     f:ItemProp+1,x  ; equippable characters
        ldx     #$0006
@chr:   bit     $3a20,x         ; actor mask
        bne     :+
        sec
:       rol     $ee
        dex
        dex
        bpl     @chr
        shorta0
        lda     $ee
        sta     $2e76           ; set item equippability
@grant: lda     #$01
        sta     $2e75           ; quantity 1
        lda     #$05            ; battle graphics $05: add an obtained item
        jsl     ExecBtlGfx_ext
        ply
        plx
        rts
.endproc

; ------------------------------------------------------------------------------

; [ a kit list's name from a table that is not AttackName ]
;
; ListTextCmd_0f (btlgfx) jsl's here for every id at or past $51, in place of
; its own SwdTech arm:
;   bushido mode (w7e6168 = 2): ids $55-$5c are SwdTechs, named in
;     BushidoName by tech index (AttackName's $55-$5c are other rows' names);
;   thief mode (3): every row of Ot6ThiefRowTbl, named in Ot6ThiefName.
; Each letter is DrawListLetter's EN body (the tile, attribute in B, to
; ($53),y and $55 to ($51),y, Y += 2), with B reloaded from $56, the
; attribute the caller staged.
; in: A = id, Y = the line buffer offset, a8, db=$7e.  out: carry set = drawn
; (Y past the name), carry clear = an AttackName row (A = id, Y unchanged).
OT6_THIEF_NAMELEN = 10
.proc Ot6KitListName
        .a8
        php
        rep     #$10
        .i16
        pha                     ; [1,s] the id
        lda     $6168
        cmp     #$02
        beq     @bushido
        cmp     #$03
        bne     @no
        lda     $01,s
        jsl     Ot6ThiefRowOf   ; X = the record offset (row * 5)
        bcc     @no
        longa
        txa
        asl                     ; row * 10: the name's offset
        tax
        shorta0
        lda     #OT6_THIEF_NAMELEN
        pha                     ; [1,s] letters left
@thief: lda     $56
        xba
        lda     f:Ot6ThiefName,x
        jsr     Ot6ListLetter
        inx
        lda     $01,s
        dec     a
        sta     $01,s
        bne     @thief
        bra     @drawn
@bushido:
        lda     $01,s
        sec
        sbc     #$55            ; tech index 0-7
        longa
        and     #$00ff
        pha                     ; [1,s] the index
        asl
        clc
        adc     $01,s           ; x3
        asl
        asl                     ; x12, BushidoName's record
        tax
        pla
        shorta0
        lda     #BushidoName::ITEM_SIZE
        pha                     ; [1,s] letters left
@bush:  lda     $56
        xba
        lda     f:BushidoName,x
        jsr     Ot6ListLetter
        inx
        lda     $01,s
        dec     a
        sta     $01,s
        bne     @bush
@drawn: pla
        pla
        plp
        sec
        rtl
@no:    pla
        plp
        clc
        rtl
.endproc

; DrawListLetter's EN body.  in: B:A = attribute:tile, Y = buffer offset.
.proc Ot6ListLetter
        .a8
        .i16
        longa
        sta     ($53),y         ; tile id
        lda     $55
        sta     ($51),y
        shorta
        iny
        iny
        rts
.endproc

; ------------------------------------------------------------------------------

; [ attack name type 3: a later thief row's banner ]
; _c2bb11's third arm (btlgfx_code_far) jml's here: the message string at
; w7e57d5 becomes the row's name from Ot6ThiefBanner, $00-terminated, the way
; _c2bb1c copies a SwdTech's.  The row id is the script's third byte (attack
; name type 3 is ShowAttackName_00's `lda $b6`).  a8, db=$7e.  rtl.
.proc Ot6ThiefBannerName
        .a8
        php
        rep     #$10
        .i16
        ldy     #$0002
        lda     ($76),y         ; the row id
        sec
        sbc     #OT6_THIEF_MUG
        ldy     #$0000
        cmp     #OT6_THIEF_MARK - OT6_THIEF_MUG + 1
        bcs     @end            ; not a later row: an empty string
        longa
        and     #$00ff
        tay                     ; Y = the row
        lda     #$0000
@mul:   cpy     #$0000
        beq     @have
        clc
        adc     #OT6_BANNER_LEN
        dey
        bra     @mul
@have:  tax
        shorta0
@cp:    lda     f:Ot6ThiefBanner,x
        cmp     #$ff
        beq     @end
        sta     $57d5,y
        inx
        iny
        cpy     #OT6_BANNER_LEN
        bne     @cp
@end:   lda     #$00
        sta     $57d5,y
        plp
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ the field Thief page: row n's id, or $ff when it is not learned yet ]
; in: A = the page row 0-7.  out: A = the row's id or $ff.  any widths, any
; db.  preserves X and Y.  rtl.
.proc Ot6ThiefPageRow
        php
        sep     #$20
        .a8
        rep     #$10
        .i16
        phx
        phb
        pha
        lda     #$7e
        pha
        plb                     ; db = $7e for Ot6ThiefRowKnown's switch read
        pla
        longa
        and     #$00ff
        pha
        asl
        asl
        clc
        adc     $01,s           ; row * 5
        tax
        pla
        shorta0
        jsl     Ot6ThiefRowKnown
        bcc     @no
        lda     f:Ot6ThiefRowTbl,x
        bra     @out
@no:    lda     #$ff
@out:   plb
        plx
        plp
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ a later row's charge, at the queue: Ot6AbilityCost's @steal arm ]
;
; Every row under command $05 is flat (Ot6BoostDmg gates the command, so the
; boost multiplies nothing), with two exceptions, both from kits.md's one
; test, a price escalates exactly when the boost multiplies the action:
;   Trickshot's hit is multiplied ($b5 = $18 at execution), so its base
;     takes x2.5 per pending point (Ot6BoostPriceFor);
;   Master's Mark queued under three points does nothing at execution, and
;     a divine charges nothing it did not deliver (kits.md "Divines").
; in: A = the row id, X = the attacker.  out: A = the price.  a8/i16.
; preserves X and Y.  rtl.
.proc Ot6ThiefCharge
        .a8
        .i16
        cmp     #OT6_THIEF_TRICK
        bne     @mark
        jsl     Ot6ThiefCostFor
        jml     Ot6BoostPriceFor
@mark:  cmp     #OT6_THIEF_MARK
        bne     @flat
        lda     OT6_BOOST_REVEALED,x
        cmp     #OT6_MARK_BOOST
        lda     #OT6_THIEF_MARK
        bcs     @flat
        lda     #$00
        rtl
@flat:  jml     Ot6ThiefCostFor
.endproc

; [ a row's price as the window draws it: the charge's rule for the caster
;   whose window is open (Ot6KitRowCost's thief arm, and the confirm) ]
; in: A = the row id.  out: A = the price.  a8/i16.  preserves X and Y.
.proc Ot6ThiefRowCost
        .a8
        .i16
        cmp     #OT6_THIEF_TRICK
        bne     @flat
        jsl     Ot6ThiefCost
        jml     Ot6PendPrice
@flat:  jml     Ot6ThiefCost
.endproc
