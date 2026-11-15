; ------------------------------------------------------------------------------
; OT6: the esper rework, plan A (#328, docs/design/esper-rework.md)
;
; A won battle pays its Magic Points (BattleMagicPoints, doubled for a random
; battle as experience and gil are: Ot6RewardMulW) to each living seated
; member, into that member's counter for the stone the member wears.  Every
; esper has the same five rungs (10 / 30 / 75 / 200 / 500 Magic Points); a
; rung once reached is kept for good, whatever is worn later.  The rungs hold
; stat points and relic-style effects, folded into UpdateEquip as one more
; piece of gear (Ot6EsperFold), so the menu's stats and the battle's read the
; same numbers.  This replaces vanilla's learn rates (LearnGenjuMagic), its
; level-up bonus (DoLevelUp's GenjuBonusTbl call) and OT6's while-worn stat
; packages (Ot6EsperStatMod), all retired.
;
; The counters live in expanded SRAM (ot6_memory.inc OT6_ESPER_*): a live
; page that play reads and writes, copied from the slot on a load and into
; the slot on a save.
; ------------------------------------------------------------------------------

.segment "ot6_code"

OT6_ESPER_MAGIC_WORD = $3145    ; 'E1'
OT6_ESPER_MSG        = $49      ; AttackMsg $49: "<char>'s esper reached rank <v0>"

; the rungs' cumulative costs, shared with the menu
OT6_RUNG1 = 10
OT6_RUNG2 = 30
OT6_RUNG3 = 75
OT6_RUNG4 = 200
OT6_RUNG5 = 500
OT6_ESPER_CAP = 9999            ; a counter stops here (the menu shows 4 digits)

; the two signatures labbed before they ship (#328: "lab half-cost spells and
; permanent Haste before shipping them"): Shiva's Gold Hairpin bit (ItemProp
; +11 $20) and Odin's RunningShoes bit (+8 $08).  0 holds one back.
OT6_SIG_HALFMP = $20
OT6_SIG_HASTE  = $08

OT6_REC = 14                    ; bytes per rung record (Ot6LadderTbl)

; esper index (GenjuProp order, 0..26) in A (a8) -> counter slot 0..25 in A:
; Raiden (12) shares Odin's (11) and everything past it moves down one.
.proc Ot6EsperSlot
        .a8
        cmp     #12
        bcc     @done
        beq     @odin
        dec
        rts
@odin:  lda     #11
@done:  rts
.endproc

; A (a16) = Magic Points -> A (a16) = the rungs they reach, 0..5; Z set on 0.
.proc Ot6EsperRankA
        .a16
        cmp     #OT6_RUNG5
        bcs     @r5
        cmp     #OT6_RUNG4
        bcs     @r4
        cmp     #OT6_RUNG3
        bcs     @r3
        cmp     #OT6_RUNG2
        bcs     @r2
        cmp     #OT6_RUNG1
        bcs     @r1
        lda     #$0000
        rts
@r1:    lda     #$0001
        rts
@r2:    lda     #$0002
        rts
@r3:    lda     #$0003
        rts
@r4:    lda     #$0004
        rts
@r5:    lda     #$0005
        rts
.endproc

; A (a16) = actor 0..11 -> A (a16) = actor * 52, that actor's first counter's
; offset past OT6_ESPER_CTR.  Clobbers nothing else.
.proc Ot6EsperRowOff
        .a16
        asl
        asl                     ; x4
        pha
        asl
        asl                     ; x16
        pha
        asl                     ; x32
        clc
        adc     1,s
        adc     3,s             ; x52
        sta     3,s
        pla
        pla
        rts
.endproc

; Clear the live page's counters and sign it.  a/x widths saved.
.proc Ot6EsperClearLive
        php
        longai
        phx
        ldx     #OT6_ESPER_CTR
        lda     #$0000
@clr:   sta     f:OT6_ESPER_LIVE,x
        inx
        inx
        cpx     #OT6_ESPER_SHOWN + 2
        bcc     @clr
        lda     #OT6_ESPER_MAGIC_WORD
        sta     f:OT6_ESPER_LIVE+OT6_ESPER_MAGIC
        plx
        plp
        rts
.endproc

; Make sure the live page is signed (a battery from an earlier build, or a
; savestate that never passed a load or New Game, has none): an unsigned page
; starts from zero.
.proc Ot6EsperEnsureLive
        php
        longa
        lda     f:OT6_ESPER_LIVE+OT6_ESPER_MAGIC
        cmp     #OT6_ESPER_MAGIC_WORD
        beq     @ok
        jsr     Ot6EsperClearLive
@ok:    plp
        rts
.endproc

; [ lifecycle: New Game, load, save ]
; Called from the codex's lifecycle procs (ot6_codex.asm), which vanilla's
; menu already calls at these three moments.

; New Game: no esper progress.
.proc Ot6EsperNewGame
        jsr     Ot6EsperClearLive
        rts
.endproc

; A validated load of slot A (1..3): the slot's page becomes the live page.  A
; slot page with no signature (a save made before this build) reads as no
; progress.  a/x widths saved; A preserved.
.proc Ot6EsperLoaded
        php
        longai
        pha
        phx
        and     #$0003
        dec
        xba
        asl
        asl                     ; (slot - 1) * $400
        tax
        lda     f:OT6_ESPER_ROOT+OT6_ESPER_MAGIC,x
        cmp     #OT6_ESPER_MAGIC_WORD
        beq     @copy
        jsr     Ot6EsperClearLive
        bra     @done
@copy:  lda     3,s             ; the slot (under the phx)
        jsr     Ot6EsperCopySlotToLive
        lda     #OT6_ESPER_MAGIC_WORD
        sta     f:OT6_ESPER_LIVE+OT6_ESPER_MAGIC
@done:  plx
        pla
        plp
        rts
.endproc

; The title screen's Continue (field_menu.asm MenuState_23, on the confirm):
; vanilla loads the slot there and never passes LoadSavedGame, which only the
; reload after a game over calls.  A (a8) = the slot.  rtl.
.proc Ot6EsperContinue
        php
        jsr     Ot6EsperLoaded
        plp
        rtl
.endproc

; A (a16) = slot 1..3.  Copy that slot page's counters into the live page.
; The three slots get their own loops so no scratch cell is needed.
.proc Ot6EsperCopySlotToLive
        .a16
        .i16
        and     #$0003
        cmp     #$0002
        beq     @two
        cmp     #$0003
        beq     @three
        ldx     #OT6_ESPER_CTR
@c1:    lda     f:OT6_ESPER_ROOT,x
        sta     f:OT6_ESPER_LIVE,x
        inx
        inx
        cpx     #OT6_ESPER_COPY
        bcc     @c1
        rts
@two:   ldx     #OT6_ESPER_CTR
@c2:    lda     f:OT6_ESPER_ROOT+OT6_ESPER_STRIDE,x
        sta     f:OT6_ESPER_LIVE,x
        inx
        inx
        cpx     #OT6_ESPER_COPY
        bcc     @c2
        rts
@three: ldx     #OT6_ESPER_CTR
@c3:    lda     f:OT6_ESPER_ROOT+OT6_ESPER_STRIDE*2,x
        sta     f:OT6_ESPER_LIVE,x
        inx
        inx
        cpx     #OT6_ESPER_COPY
        bcc     @c3
        rts
.endproc

; A save into slot A (1..3): the live page's counters become that slot's
; page, signed.  a/x widths saved; A preserved.
.proc Ot6EsperSaveAs
        php
        longai
        pha
        phx
        jsr     Ot6EsperEnsureLive
        lda     1+2,s           ; the slot (under the phx)
        and     #$0003
        cmp     #$0002
        beq     @two
        cmp     #$0003
        beq     @three
        ldx     #OT6_ESPER_CTR
@c1:    lda     f:OT6_ESPER_LIVE,x
        sta     f:OT6_ESPER_ROOT,x
        inx
        inx
        cpx     #OT6_ESPER_COPY
        bcc     @c1
        lda     #OT6_ESPER_MAGIC_WORD
        sta     f:OT6_ESPER_ROOT+OT6_ESPER_MAGIC
        bra     @done
@two:   ldx     #OT6_ESPER_CTR
@c2:    lda     f:OT6_ESPER_LIVE,x
        sta     f:OT6_ESPER_ROOT+OT6_ESPER_STRIDE,x
        inx
        inx
        cpx     #OT6_ESPER_COPY
        bcc     @c2
        lda     #OT6_ESPER_MAGIC_WORD
        sta     f:OT6_ESPER_ROOT+OT6_ESPER_STRIDE+OT6_ESPER_MAGIC
        bra     @done
@three: ldx     #OT6_ESPER_CTR
@c3:    lda     f:OT6_ESPER_LIVE,x
        sta     f:OT6_ESPER_ROOT+OT6_ESPER_STRIDE*2,x
        inx
        inx
        cpx     #OT6_ESPER_COPY
        bcc     @c3
        lda     #OT6_ESPER_MAGIC_WORD
        sta     f:OT6_ESPER_ROOT+OT6_ESPER_STRIDE*2+OT6_ESPER_MAGIC
@done:  plx
        pla
        plp
        rts
.endproc

; ------------------------------------------------------------------------------

; [ earn at victory ]
;
; jsl from WinBattle's per-character loop, in place of vanilla's
; `lda $161e,x / bmi / jsr LearnGenjuMagic`: the loop has already skipped a
; member who is not alive (vanilla pays only the battle's living party; the
; bench earns nothing).  in: X = the character record offset ($3010,y), $fb
; = the formation's Magic Points, and the member's battle slot * 2 on the
; stack under the return address (the loop's `phy`: LearnItemMagic, called
; just before, leaves Y clobbered).  a8, i16, db=$7e.  Preserves x/y.
OT6_EARN_SEAT = 9               ; 1,s.. after php/phx/phy: Y 1-2, X 3-4, P 5,
                                ;   the return address 6-8, the loop's Y 9-10
.proc Ot6EsperEarn
        .a8
        .i16
        php
        phx
        phy
        lda     $161e,x         ; the worn esper
        bmi     @quit           ; none
        pha
        lda     $1600,x         ; actor
        cmp     #OT6_ESPER_CHARS
        pla
        bcs     @quit           ; a guest: no counters
        jsr     Ot6EsperSlot
        sta     OT6_SCR_IDX     ; the counter slot (OT6_SCR_*: victory-time
                                ;   scratch, as Ot6RewardScale_ext uses it)
        lda     $fb
        bne     @pays
@quit:  brl     @out            ; this battle pays nothing
@pays:
        jsr     Ot6EsperEnsureLive
        ; the points: $fb, times Ot6RewardMulW/16 for a random battle
        longa
        lda     $fb
        and     #$00ff
        tax                     ; X = the points
        lda     a:OT6_RANDBTL
        and     #$00ff
        beq     @plain
        lda     f:Ot6RewardMulW
        and     #$00ff
        tay                     ; Y = the multiplier in 16ths
        lda     #$0000
@mul:   cpy     #$0000
        beq     @mdone
        stx     OT6_SCR_SLOT2   ; the points
        clc
        adc     OT6_SCR_SLOT2
        dey
        bra     @mul
@mdone: lsr
        lsr
        lsr
        lsr
        tax
@plain: stx     OT6_SCR_SLOT2   ; the points paid
        txa
        sta     f:OT6_ESPER_LIVE+OT6_ESPER_SHOWN
        ; the counter: (actor * 26 + slot) * 2
        lda     3,s             ; X on entry: the character record
        tax
        lda     $1600,x         ; actor
        and     #$00ff
        jsr     Ot6EsperRowOff
        sta     OT6_SCR_BIT     ; the actor's row offset
        lda     OT6_SCR_IDX
        and     #$00ff
        asl
        clc
        adc     OT6_SCR_BIT
        tax                     ; X = the counter's offset past CTR
        lda     f:OT6_ESPER_LIVE+OT6_ESPER_CTR,x
        pha                     ; the old count
        clc
        adc     OT6_SCR_SLOT2
        bcs     @cap
        cmp     #OT6_ESPER_CAP+1
        bcc     @store
@cap:   lda     #OT6_ESPER_CAP
@store: sta     f:OT6_ESPER_LIVE+OT6_ESPER_CTR,x
        jsr     Ot6EsperRankA
        sta     OT6_SCR_BIT     ; the new rank
        pla
        jsr     Ot6EsperRankA
        cmp     OT6_SCR_BIT
        bcs     @nonew          ; no rung crossed
        lda     OT6_EARN_SEAT,s ; the loop's Y: the battle slot * 2
        and     #$00ff
        lsr                     ; the party slot 0..3
        tax
        shorta
        lda     OT6_SCR_BIT
        sta     f:OT6_ESPER_LIVE+OT6_ESPER_PEND,x
@nonew:
@out:   ply
        plx
        plp
        rtl
.endproc

; [ the victory screen's Magic Points and rank lines ]
;
; jsl from WinBattle after the per-character loop, in place of vanilla's
; "Got <v0> Magic Point(s)" block, which showed only when a spell was being
; learned or Morph was ready.  Shows the points whenever a living member
; wore a stone in a battle that paid some, then one line per member who
; reached a new rank.  a8, i16, db=$7e.  Preserves x/y.
.proc Ot6EsperMsg
        .a8
        .i16
        php
        phx
        phy
        longa
        lda     f:OT6_ESPER_LIVE+OT6_ESPER_MAGIC
        cmp     #OT6_ESPER_MAGIC_WORD
        bne     @out            ; nobody earned (the page was never signed)
        lda     f:OT6_ESPER_LIVE+OT6_ESPER_SHOWN
        beq     @ranks
        sta     $2f35           ; variable 0
        shorta
        stz     $2f37
        lda     #$35            ; "Got <v0> Magic Point(s)"
        jsr     Ot6ShowMsg
@ranks: shorta
        ldx     #$0000
@slot:  lda     f:OT6_ESPER_LIVE+OT6_ESPER_PEND,x
        beq     @next
        sta     $2f35           ; variable 0: the rank
        stz     $2f36
        stz     $2f37
        txa
        sta     $2f38           ; variable 1: the member (by battle slot)
        lda     #OT6_ESPER_MSG
        jsr     Ot6ShowMsg
@next:  inx
        cpx     #$0004
        bcc     @slot
        longa
        lda     #$0000
        sta     f:OT6_ESPER_LIVE+OT6_ESPER_PEND
        sta     f:OT6_ESPER_LIVE+OT6_ESPER_PEND+2
        sta     f:OT6_ESPER_LIVE+OT6_ESPER_SHOWN
@out:   ply
        plx
        plp
        rtl
.endproc

; ShowMsg's body for a caller in this bank: message A (a8) through battle
; graphics command 4.  db=$7e.  Preserves x/y.
.proc Ot6ShowMsg
        .a8
        php
        phx
        phy
        shorta
        longi
        sta     $2d6f
        lda     #$02            ; battle script command $02 (show battle message)
        sta     $2d6e
        lda     #$ff
        sta     $2d72
        lda     #$04            ; battle graphics $04 (execute battle script)
        jsl     ExecBtlGfx_ext
        ply
        plx
        plp
        rts
.endproc

; ------------------------------------------------------------------------------

; [ the kept bonuses, folded into UpdateEquip ]
;
; jsl from UpdateEquip right after its equipment loop, before the HP/MP boost
; flags and the stat clamps are read, so every rung the character has reached
; on every esper adds to the $11xx buffer the way one more relic would: the
; effect bytes OR'd into the same cells CalcEquipEffect fills (ItemProp +5 to
; +13 and +25), the stat points added to the words it adds a relic's boosts
; to.  The HP and MP boosts are bits CheckHPBoost reads largest-first, so the
; largest of several applies.  An earring rung counts as one earring, never a
; second: a character who already wears one gains nothing.  Every caller of
; UpdateEquip (the menus, the field, battle init and re-derivation) sees the
; same result.
;
; in: X = UpdateEquip's record index after the equipment loop (the actor is
; $15dd,x), db=$7e, a8 i16.  Preserves a/x/y and p.
.proc Ot6EsperFold
        php
        longai
        pha
        phx
        phy
        lda     f:OT6_ESPER_LIVE+OT6_ESPER_MAGIC
        cmp     #OT6_ESPER_MAGIC_WORD
        bne     @out            ; no progress page: nothing kept
        lda     $15dd,x         ; the actor
        and     #$00ff
        cmp     #OT6_ESPER_CHARS
        bcs     @out
        jsr     Ot6EsperRowOff
        tax                     ; X = this actor's first counter
        ldy     #$0000          ; Y = this esper's first rung record
@esper: lda     f:OT6_ESPER_LIVE+OT6_ESPER_CTR,x
        jsr     Ot6EsperRankA
        beq     @next
        phx
        pha                     ; rungs left to apply
        tyx
@rung:  jsr     Ot6EsperApply
        txa
        clc
        adc     #OT6_REC
        tax
        lda     1,s
        dec
        sta     1,s
        bne     @rung
        pla
        plx
@next:  inx
        inx
        tya
        clc
        adc     #OT6_REC * 5
        tay
        cpy     #OT6_REC * 5 * OT6_ESPER_SLOTS
        bcc     @esper
@out:   ply
        plx
        pla
        plp
        rtl
.endproc

; One rung record at Ot6LadderTbl+X onto the $11xx buffer.  a16 in and out,
; db=$7e; preserves x/y.
.proc Ot6EsperApply
        .a16
        .i16
        shorta
        lda     f:Ot6LadderTbl+0,x      ; +5 field effects
        tsb     $11df
        lda     f:Ot6LadderTbl+1,x      ; +6 status 1 protection
        tsb     $11d2
        lda     f:Ot6LadderTbl+2,x      ; +7 status 2 protection
        tsb     $11d3
        lda     f:Ot6LadderTbl+3,x      ; +8 status 3 set
        tsb     $11d4
        lda     f:Ot6LadderTbl+4,x      ; +9 relic effects (HP/MP boosts, atlas)
        and     #$fd                    ;   ...but the earring bit, which
        tsb     $11d5                   ;   vanilla moves to $11d7 per piece
        lda     f:Ot6LadderTbl+4,x
        and     #$02
        tsb     $11d7                   ; one earring, never a second
        lda     f:Ot6LadderTbl+5,x      ; +10
        tsb     $11d6
        lda     f:Ot6LadderTbl+6,x      ; +11
        tsb     $11d7
        lda     f:Ot6LadderTbl+7,x      ; +12
        tsb     $11d8
        lda     f:Ot6LadderTbl+8,x      ; +13
        tsb     $11d9
        lda     f:Ot6LadderTbl+9,x      ; +25 status 2 set
        tsb     $11bc
        longa
        lda     f:Ot6LadderTbl+10,x     ; vigor
        and     #$00ff
        clc
        adc     $11a6
        sta     $11a6
        lda     f:Ot6LadderTbl+11,x     ; speed
        and     #$00ff
        clc
        adc     $11a4
        sta     $11a4
        lda     f:Ot6LadderTbl+12,x     ; stamina
        and     #$00ff
        clc
        adc     $11a2
        sta     $11a2
        lda     f:Ot6LadderTbl+13,x     ; mag.pwr
        and     #$00ff
        clc
        adc     $11a0
        sta     $11a0
        rts
.endproc

; ------------------------------------------------------------------------------

; [ Crusader's Genji bit: the menu's permission, never vanilla's cut ]
;
; jsl from UpdateEquipBattle right after `lda $cf / trb $d8`, which has
; cleared the Genji bit ($11d8 & $10) for a member holding two weapons.  What
; is left of it is read once more in battle: CalcDmg's one-weapon cut, damage
; x3/4 for a Genji Glove worn without a second weapon (#534).  Crusader's
; signature (Ot6LadderTbl row 14, rung 5) sets the bit so the Equip menu takes
; a second weapon; it is meant as a pure upgrade, so a bit that no worn piece
; of gear carries (ItemProp+12 & $10 on none of $11c6-$11cb: it came from the
; ladder alone) is cleared here, before $3c58 is written.  A real Genji Glove
; keeps vanilla's cut.  $2e6e, the in-battle Item equip's Genji permission
; (btlgfx check_equip), was copied before this and keeps the bit either way.
;
; dp=$1100, a8, X preserved.  rtl.
.proc Ot6LadderGenji
        .a8
        php
        shorta
        longi                           ; before the phx, so the plx matches it
        phx
        lda     $d8                     ; relic effects 4
        and     #$10
        beq     out                     ; no Genji bit left (none, or two weapons)
        ldx     #$0005                  ; weapon, shield, helmet, armor, relics
slot:   lda     $c6,x
        cmp     #$ff
        beq     next
        phx
        longa
        and     #$00ff
        asl                             ; id x2
        pha
        asl
        asl
        asl
        asl                             ; id x32
        sec
        sbc     1,s                     ; id x30
        tax
        pla
        shorta
        lda     f:ItemProp+12,x
        plx
        and     #$10
        bne     out                     ; a worn piece carries it: vanilla
next:   dex
        bpl     slot
        lda     #$10
        trb     $d8                     ; the ladder's alone: no cut
out:    plx
        plp
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ Golem's cover: only from a knight who can take the hit ]
;
; jsl from CoverEffect's True Knight walk (battle_main.asm), for each candidate
; whose relic effects 4 carry the cover bit ($3c58 & $40), before
; CheckCoverTarget.  Vanilla's cover has no gate on the knight's own HP, so a
; frail or nearly dead knight still steps in front of the blow and can die.
; Golem's signature (Ot6LadderTbl row 21, rung 5) grants the bit as a pure
; upgrade (#534), so a knight who does not wear the True Knight relic covers
; only at half its max HP or more and never while near fatal; one wearing the
; relic keeps vanilla's cover (ITEM::TRUE_KNIGHT is the only item that
; carries the bit).  A Rage (MonsterProp+30 bit 0, which the monster-property
; loader ors into $3c58 as the same bit for Gau, battle_main.asm "true knight
; effect (rage only ???)") is the other source of the cover bit; no Rage in
; today's data sets it, and this gate would treat one like the signature's.
;
; in: a16, x = the candidate's entity offset, index width either (CoverEffect
; runs .i8: no index immediates, no index pushes), db=$7e.  out: carry set =
; it may cover.  a clobbered; x/y kept.
.proc Ot6KnightGate
        .a16
        php
        shorta
        lda     $3cd0,x                 ; relic 1
        cmp     #ITEM::TRUE_KNIGHT
        beq     yes
        lda     $3cd1,x                 ; relic 2
        cmp     #ITEM::TRUE_KNIGHT
        beq     yes
        longa
        lda     $3ee4,x
        bit     #$0200                  ; near fatal
        bne     no
        lda     $3bf4,x                 ; current HP x2 (HP < 10000: no carry out)
        asl
        cmp     $3c1c,x                 ; max HP
        bcs     yes                     ; at half or more
no:     plp
        clc
        rtl
yes:    plp
        sec
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ the signatures that are new code ]
;
; Five rung-5 effects have no vanilla bit (docs/design/esper-rework.md, the
; table's dagger rows): Conductor (Ramuh), Facet (Carbunkl), Rebirth
; (Phoenix), Fenrir's Stop and Slow immunity, and Sraphim's full revives;
; so has one rung-3 effect, Sraphim's +25% healing (Ot6SeraphHeal).  Each
; asks Ot6EsperSig (rung 5) or Ot6EsperCount whether the character holds it.

OT6_SLOT_RAMUH    = 0
OT6_SLOT_CARBUNKL = 18
OT6_SLOT_SRAPHIM  = 20
OT6_SLOT_PHOENIX  = 25
OT6_SLOT_FENRIR   = 23

; in: A (a16) = actor | counter slot << 8, i16.  out: A (a16) = that actor's
; Magic Points on that esper (0 for a guest, or with no progress page).  X
; clobbered; Y kept.  rts.
.proc Ot6EsperCount
        .a16
        .i16
        pha
        lda     f:OT6_ESPER_LIVE+OT6_ESPER_MAGIC
        cmp     #OT6_ESPER_MAGIC_WORD
        bne     @no
        lda     1,s
        and     #$00ff
        cmp     #OT6_ESPER_CHARS
        bcs     @no
        jsr     Ot6EsperRowOff
        pha                     ; [row] [actor | slot << 8]
        lda     4,s             ; the slot byte
        and     #$00ff
        asl
        clc
        adc     1,s
        tax
        pla
        pla
        lda     f:OT6_ESPER_LIVE+OT6_ESPER_CTR,x
        rts
@no:    pla
        lda     #$0000
        rts
.endproc

; in: A (16 bits, whatever the m flag) = actor | counter slot << 8.  out: C set
; when that actor's count on that esper has reached the signature (rung 5).
; Preserves a/x/y and every flag but C.  rts.
.proc Ot6EsperSig
        php
        longai
        phx
        pha
        jsr     Ot6EsperCount
        cmp     #OT6_RUNG5      ; C = reached
        pla                     ; (pulls leave C alone)
        plx
        bcs     @yes
        plp
        clc
        rts
@yes:   plp
        sec
        rts
.endproc

; jsl from InitChars after LoadCharProp, once per seated character at battle
; start.  x = the battle slot * 2 (either index width), db = $7e.  Facet:
; the boost bank opens at two points (Ot6InitBP opened it at one).  Rebirth:
; the character enters under Life 3 (status 4 bit $04, through the status-to-
; set cell LoadCharProp fills, $3de9).  Preserves everything.
.proc Ot6EsperBattleInit
        php
        longi
        shorta
        pha
        lda     $3ed8,x         ; actor
        xba
        lda     #OT6_SLOT_CARBUNKL
        xba
        jsr     Ot6EsperSig
        bcc     @rebirth
        lda     #$02
        sta     OT6_BP_CLASS,x  ; Facet
@rebirth:
        lda     $3ed8,x
        xba
        lda     #OT6_SLOT_PHOENIX
        xba
        jsr     Ot6EsperSig
        bcc     @out
        lda     $3de9,x         ; status 4 to set at the start
        ora     #$04            ; Life 3
        sta     $3de9,x
@out:   pla
        plp
        rtl
.endproc

; Fenrir's signature: immune to Stop and Slow.  jsl from the end of
; UpdateImmuneStatus in place of its `sta $3330,x` (the status-3/4 mask a
; status must pass to land; a clear bit blocks it), so it runs at battle start
; and whenever the mask is rebuilt, and after vanilla's "block both slow and
; haste if immune to either" rule, which would otherwise block Haste too.
; in: A (a8) = the mask, x = the entity (either index width), db = $7e.
.proc Ot6EsperImmune
        .a8
        php
        pha
        txa
        cmp     #$08
        bcs     @store          ; a monster
        lda     $3ed8,x
        xba
        lda     #OT6_SLOT_FENRIR
        xba
        jsr     Ot6EsperSig
        bcc     @store
        pla
        and     #<~(STATUS3::SLOW | STATUS3::STOP)
        pha
@store: pla
        sta     $3330,x
        plp
        rtl
.endproc

; Conductor: A (a8) = the shields a monster has left after a weakness hit's
; chip; x = the attacker, y = the target.  One more goes when the attacker
; holds Ramuh's signature, the action is a spell (the command is Magic or
; X-Magic: Bolt, Bolt 2, Bolt 3; not a weapon, a thrown blade, a summon or
; a skill, as the design says "the wearer's lightning spells"), and lightning is one
; of the weaknesses the hit matched ($3be0,y & $11a1 bit $04), so a mixed
; element hit whose lightning the target does not fear takes none.  rts
; from Ot6Chip (same bank).  Preserves x/y.
.proc Ot6Conductor
        .a8
        beq     @out            ; none left to take
        pha
        lda     $3a7c           ; the queued command (Ot6Life3Cast's read)
        cmp     #$02            ; Magic (and a Mimic of it)
        beq     :+
        cmp     #$17            ; X-Magic
        bne     @keep           ; not a spell
:
        lda     $3be0,y         ; the target's weak elements
        and     $11a1           ; ...the hit carried
        and     #$04            ; lightning among them
        beq     @keep
        txa
        cmp     #$08
        bcs     @keep           ; a monster's attack
        lda     $3ed8,x
        xba
        lda     #OT6_SLOT_RAMUH
        xba
        jsr     Ot6EsperSig
        bcc     @keep
        pla
        dec     a
        rts
@keep:  pla
@out:   rts
.endproc

; ------------------------------------------------------------------------------

; [ Sraphim: healing +25%, and full revives ]
;
;  Sraphim's two rungs that are new code: rung 3, the member's healing is
; 25% stronger, and rung 5 (its signature), anyone the member revives comes
; back at full HP.
;
; jsl from CalcTargetDmg (battle_main.asm @0b9b), once per target, right after
; CalcDmgMod or CalcDmgRatio has left the amount in $f0 and before the
; element, undead and zombie handling, the 9999 cap and the heal-or-damage
; choice.  x = the attacker, y = the target (either index width), db = $7e, a8.
; Preserves a/x/y and p.
;
; A heal is an action with $11a4 bit 0 (heal) whose $11a3 bit 7 (MP) is
; clear: the Cure family, Regen's ticks, Life and Life 2, Pearl Wind and
; every other HP heal a character's command carries, a Tonic or a Potion
; or a Fenix Down from Item.  An Ether's or Osmose's MP is not HP and is left
; alone.  Only a character's action counts, and not one whose actor is
; KO'd: the only action a KO'd body takes is Life 3's own revival (Phoenix's
; Rebirth, ReraiseEffect's command $26), which nobody performs on them.
; Regen's tick runs as the Regen'd body's own action (Cmd_22), since the
; game keeps no record of who cast the Regen: so a holder's own Regen heals
; 25% more, whoever cast it, and a Regen the holder cast on someone else
; heals as it always did.
;
; Rung 3: $f0 += $f0 / 4 (the quarter rounds down), after the boost's
; multiplier (Ot6BoostDmg, on the base) and the random variance; a boosted
; Cure is already Cure 2 or Cure 3 (the boost bought the tier), and the
; quarter goes on top of that.  It goes on before the heal-or-damage choice,
; so a heal that hurts an undead body or a zombie (the same amount, turned
; into damage) is 25% stronger too.  The cap is unchanged: the amount is
; still clipped at 9999 and the target's HP at its max.
;
; Rung 5: a revive -- the target is KO'd ($3ee4 bit 7) and this action lifts
; it ($3dfc bit 7, MagicStatusEffect's status-1-to-clear, filled before this
; call) -- heals the target's max HP ($3c1c), so it rises at full.  Life 2
; and a character's Life 3 on a KO'd body already did (power 16/16 of max
; HP, Ot6Life3Revive); Life and a Fenix Down (2/16) now do too.
.proc Ot6SeraphHeal
        .a8
        php
        longai
        pha
        phx
        cpx     #$0008
        bcs     @out            ; a monster's action
        lda     $11a4
        lsr
        bcc     @out            ; not a heal
        lda     $11a3
        bit     #$0080
        bne     @out            ; MP, not HP
        lda     $3ee4,x
        bit     #$0080
        bne     @out            ; a KO'd actor: Life 3's own revival
        lda     $3ed8,x         ; actor
        and     #$00ff
        ora     #OT6_SLOT_SRAPHIM << 8
        jsr     Ot6EsperCount   ; (clobbers X, pushed above)
        cmp     #OT6_RUNG3
        bcc     @out
        tax                     ; the count
        lda     $f0
        lsr
        lsr
        clc
        adc     $f0             ; + a quarter, rounded down
        bcc     :+
        lda     #$ffff          ; (saturate; the 9999 cap is downstream)
:       sta     $f0
        cpx     #OT6_RUNG5
        bcc     @out
        lda     $3ee4,y
        and     $3dfc,y
        bit     #$0080
        beq     @out            ; not a revive
        lda     $3c1c,y         ; the target's max HP
        sta     $f0
@out:   plx
        pla
        plp
        rtl
.endproc

; ------------------------------------------------------------------------------

; [ a character's progress on one esper, for the menu ]
;
; in: A (a8) = actor, X (i16) = esper index (GenjuProp order).  out: A (a16) =
; Magic Points earned (0 for a guest or with no page).  db unknown; preserves
; x/y; the caller's widths are restored except A, which returns 16-bit wide
; in a register the caller reads as a word (the menu reads it longa).
.proc Ot6EsperProgress
        php
        longai
        phx
        phy
        and     #$00ff
        cmp     #OT6_ESPER_CHARS
        bcs     @none
        pha
        lda     f:OT6_ESPER_LIVE+OT6_ESPER_MAGIC
        cmp     #OT6_ESPER_MAGIC_WORD
        beq     :+
        pla
        bra     @none
:       pla
        jsr     Ot6EsperRowOff
        pha
        txa
        shorta
        jsr     Ot6EsperSlot
        longa
        and     #$00ff
        asl
        clc
        adc     1,s
        tax
        pla
        lda     f:OT6_ESPER_LIVE+OT6_ESPER_CTR,x
        bra     @done
@none:  lda     #$0000
@done:  ply
        plx
        plp
        rtl
.endproc

; the rungs' costs as words, for the menu
Ot6RungCostTbl:
        .word   OT6_RUNG1, OT6_RUNG2, OT6_RUNG3, OT6_RUNG4, OT6_RUNG5

; ------------------------------------------------------------------------------

; [ the esper page's help line for a rung ]
;
; The esper detail page's cursor walks the rung column too (skills.asm,
; GenjuDetailCursorProp); with it on a rung, the help window at the top shows
; what the rung does: its description (Ot6RungDescIdx -> Ot6RungDescPtrs ->
; Ot6RungDescStr, tools/esper_ladder.py's DESC).  Under a rung the character
; has not reached whose effect bytes the character already holds from other
; rungs it has reached (on any esper, this one's earlier rungs included), a
; second line says so (Ot6RungHaveStr): the effect bytes of every other
; reached rung OR'd together cover this rung's.  A stat rung, or a signature
; that is new code (no bytes), is never "held": stats add, and each new
; signature sits on one esper only.  A larger max HP or max MP boost covers a
; smaller one (only the largest applies).  Gear is not counted: the line is
; about where to tour next on the ladder.
;
; in: A (a8) = esper (GenjuProp order), X (i16) = rung 0-4, Y (i16) = actor.
; Writes the string, its optional second line ($01 first) and the $00 end
; to WMDATA (the caller has pointed WMADD at the help buffer, $7e9ec9).
; a8/i16 in; every register and p preserved but A; rtl.

; the frame, on the stack and addressed through the direct page
RD_HELD  = 0            ; 10 bytes: the effect bytes the other reached rungs hold
RD_REC   = 10           ; word: this rung's record, slot * 5 + rung
RD_ROW   = 12           ; word: the actor's first counter (Ot6EsperRowOff)
RD_S     = 14           ; word: slot loop
RD_K     = 16           ; word: rung loop
RD_RANK  = 18           ; word: the slot's rank
RD_T     = 20           ; word: scratch
RD_FRAME = 22
RD_RUNG  = RD_FRAME     ; pushed by the entry: the rung,
RD_ACTOR = RD_FRAME + 2 ;   the actor,
RD_ESPER = RD_FRAME + 4 ;   and the esper

.proc Ot6RungDescText
        php
        phd
        longai
        phx
        phy
        and     #$00ff
        pha                     ; RD_ESPER
        phy                     ; RD_ACTOR
        phx                     ; RD_RUNG
        tsc
        sec
        sbc     #RD_FRAME
        tcs
        inc
        tcd                     ; dp 0 = the frame's first byte
        lda     RD_ESPER
        shorta
        jsr     Ot6EsperSlot
        longa
        and     #$00ff
        sta     RD_S
        asl
        asl
        clc
        adc     RD_S
        clc
        adc     RD_RUNG
        sta     RD_REC
; the description
        tax
        lda     f:Ot6RungDescIdx,x
        and     #$00ff
        asl
        tax
        lda     f:Ot6RungDescPtrs,x
        tax
        shorta
@copy:  lda     f:Ot6RungDescStr,x
        beq     @copied
        sta     f:hWMDATA
        inx
        bra     @copy
@copied:
; reached, or nothing kept?  then no second line
        longa
        lda     f:OT6_ESPER_LIVE+OT6_ESPER_MAGIC
        cmp     #OT6_ESPER_MAGIC_WORD
        jne     @end
        lda     RD_ACTOR
        cmp     #OT6_ESPER_CHARS
        jcs     @end
        jsr     Ot6EsperRowOff
        sta     RD_ROW
        lda     RD_S
        asl
        clc
        adc     RD_ROW
        tax
        lda     f:OT6_ESPER_LIVE+OT6_ESPER_CTR,x
        jsr     Ot6EsperRankA
        cmp     RD_RUNG
        beq     :+                      ; rank = rung: not reached
        jcs     @end                    ; rank > rung: reached, drawn white
:       lda     RD_REC
        jsr     @recoff
        shorta
        lda     f:Ot6LadderTbl+0,x
        ora     f:Ot6LadderTbl+1,x
        ora     f:Ot6LadderTbl+2,x
        ora     f:Ot6LadderTbl+3,x
        ora     f:Ot6LadderTbl+4,x
        ora     f:Ot6LadderTbl+5,x
        ora     f:Ot6LadderTbl+6,x
        ora     f:Ot6LadderTbl+7,x
        ora     f:Ot6LadderTbl+8,x
        ora     f:Ot6LadderTbl+9,x
        jeq     @end                    ; a stat rung or a new signature
; OR every other reached rung's effect bytes into RD_HELD
        longa
        stz     RD_HELD+0
        stz     RD_HELD+2
        stz     RD_HELD+4
        stz     RD_HELD+6
        stz     RD_HELD+8
        stz     RD_S
@slot:  lda     RD_S
        asl
        clc
        adc     RD_ROW
        tax
        lda     f:OT6_ESPER_LIVE+OT6_ESPER_CTR,x
        jsr     Ot6EsperRankA
        sta     RD_RANK
        beq     @nexts
        stz     RD_K
@rung:  lda     RD_S
        asl
        asl
        clc
        adc     RD_S
        clc
        adc     RD_K
        cmp     RD_REC
        beq     @nextk
        jsr     @recoff
        shorta
        lda     f:Ot6LadderTbl+0,x
        tsb     RD_HELD+0
        lda     f:Ot6LadderTbl+1,x
        tsb     RD_HELD+1
        lda     f:Ot6LadderTbl+2,x
        tsb     RD_HELD+2
        lda     f:Ot6LadderTbl+3,x
        tsb     RD_HELD+3
        lda     f:Ot6LadderTbl+4,x
        tsb     RD_HELD+4
        lda     f:Ot6LadderTbl+5,x
        tsb     RD_HELD+5
        lda     f:Ot6LadderTbl+6,x
        tsb     RD_HELD+6
        lda     f:Ot6LadderTbl+7,x
        tsb     RD_HELD+7
        lda     f:Ot6LadderTbl+8,x
        tsb     RD_HELD+8
        lda     f:Ot6LadderTbl+9,x
        tsb     RD_HELD+9
        longa
@nextk: inc     RD_K
        lda     RD_K
        cmp     RD_RANK
        bcc     @rung
@nexts: inc     RD_S
        lda     RD_S
        cmp     #OT6_ESPER_SLOTS
        bcc     @slot
; a max HP or max MP boost: only the largest applies (CheckHPBoost reads the
; bits largest-first), so a larger one held covers the smaller ones
; (ItemProp +9: HP 1/8 $10, 1/4 $04, 1/2 $08; MP 1/8 $80, 1/4 $20, 1/2 $40)
        shorta
        lda     RD_HELD+4
        bit     #$08
        beq     :+
        ora     #$14                    ; HP 1/2 covers 1/4 and 1/8
:       bit     #$04
        beq     :+
        ora     #$10                    ; HP 1/4 covers 1/8
:       bit     #$40
        beq     :+
        ora     #$a0                    ; MP 1/2 covers 1/4 and 1/8
:       bit     #$20
        beq     :+
        ora     #$80                    ; MP 1/4 covers 1/8
:       sta     RD_HELD+4
        longa
; covered?  each of this rung's bytes, less what is held, must be empty
        lda     RD_REC
        jsr     @recoff
        shorta
        lda     RD_HELD+0
        eor     #$ff
        and     f:Ot6LadderTbl+0,x
        jne     @end                    ; a bit not held: nothing to say
        lda     RD_HELD+1
        eor     #$ff
        and     f:Ot6LadderTbl+1,x
        jne     @end                    ; a bit not held: nothing to say
        lda     RD_HELD+2
        eor     #$ff
        and     f:Ot6LadderTbl+2,x
        jne     @end                    ; a bit not held: nothing to say
        lda     RD_HELD+3
        eor     #$ff
        and     f:Ot6LadderTbl+3,x
        jne     @end                    ; a bit not held: nothing to say
        lda     RD_HELD+4
        eor     #$ff
        and     f:Ot6LadderTbl+4,x
        jne     @end                    ; a bit not held: nothing to say
        lda     RD_HELD+5
        eor     #$ff
        and     f:Ot6LadderTbl+5,x
        jne     @end                    ; a bit not held: nothing to say
        lda     RD_HELD+6
        eor     #$ff
        and     f:Ot6LadderTbl+6,x
        jne     @end                    ; a bit not held: nothing to say
        lda     RD_HELD+7
        eor     #$ff
        and     f:Ot6LadderTbl+7,x
        jne     @end                    ; a bit not held: nothing to say
        lda     RD_HELD+8
        eor     #$ff
        and     f:Ot6LadderTbl+8,x
        jne     @end                    ; a bit not held: nothing to say
        lda     RD_HELD+9
        eor     #$ff
        and     f:Ot6LadderTbl+9,x
        jne     @end                    ; a bit not held: nothing to say
        lda     #$01                    ; the second line
        sta     f:hWMDATA
        ldx     #$0000
@have:  lda     f:Ot6RungHaveStr,x
        beq     @end
        sta     f:hWMDATA
        inx
        bra     @have
@end:   shorta
        lda     #$00
        sta     f:hWMDATA
        longa
        tsc
        clc
        adc     #RD_FRAME + 6
        tcs
        ply
        plx
        pld
        plp
        rtl

; A (a16) = a rung record -> X = its offset in Ot6LadderTbl (record * 14).
; Clobbers A (left a16); uses RD_T.
@recoff:
        asl
        sta     RD_T
        asl
        asl
        asl                             ; x16
        sec
        sbc     RD_T                    ; x14
        tax
        rts
.endproc

; ------------------------------------------------------------------------------

; [ the ladder ]
;
; Ot6LadderTbl: 26 espers (counter-slot order: GenjuProp order with Odin and
; Raiden as one) x 5 rungs x OT6_REC bytes:
;   +0..+8  ItemProp +5..+13 (field, status 1/2 protection, status 3 set,
;           relic effects)
;   +9      ItemProp +25 (status 2 set)
;   +10..13 vigor, speed, stamina, mag.pwr points
; docs/design/esper-rework.md's table; tools/esper_ladder.py holds the ROM
; to it.

; one rung: the effect bytes and the stat points, in the record's order
.mac rung fld, p1, p2, s3, r9, r10, r11, r12, r13, s2, vig, spd, stm, mag
        .byte   fld, p1, p2, s3, r9, r10, r11, r12, r13, s2
        .byte   vig, spd, stm, mag
.endmac
; a stat rung: points only
.mac stat vig, spd, stm, mag
        rung    0,0,0,0,0,0,0,0,0,0, vig, spd, stm, mag
.endmac
; an effect rung: the ten effect bytes only
.mac eff fld, p1, p2, s3, r9, r10, r11, r12, r13, s2
        rung    fld, p1, p2, s3, r9, r10, r11, r12, r13, s2, 0, 0, 0, 0
.endmac
; nothing (a rung whose effect is new code, not a vanilla bit: see the
; signature hooks below)
.mac none
        rung    0,0,0,0,0,0,0,0,0,0, 0, 0, 0, 0
.endmac

; status 1 / 2 bits (const.inc STATUS1 / STATUS2)
S1_DARK   = $01
S1_ZOMBIE = $02
S1_POISON = $04
S1_IMP    = $20
S1_PETRIFY= $40
S1_DEATH  = $80
S2_DOOM   = $01
S2_MUTE   = $08
S2_BSERK  = $10
S2_MUDDLE = $20
S2_SEIZE  = $40
S2_SLEEP  = $80

Ot6LadderTbl:
;                fld  p1  p2  s3  r9  r10 r11 r12 r13 s2
; 0 Ramuh: Stm / Mag; immune to Dark; Conductor (new code)
        stat    0,0,1,0
        stat    0,0,0,1
        eff     0,S1_DARK,0,0,0,0,0,0,0,0
        stat    0,0,2,0
        none
; 1 Ifrit: Vig / Stm; max HP +12.5% (Green Beret); Fight damage up (Atlas)
        stat    1,0,0,0
        stat    0,0,1,0
        eff     0,0,0,0,$10,0,0,0,0,0
        stat    2,0,0,0
        eff     0,0,0,0,$01,0,0,0,0,0
; 2 Shiva: Mag / Spd; immune to Seizure; spells at half MP (Gold Hairpin)
        stat    0,0,0,1
        stat    0,1,0,0
        eff     0,0,S2_SEIZE,0,0,0,0,0,0,0
        stat    0,0,0,2
        eff     0,0,0,0,0,0,OT6_SIG_HALFMP,0,0,0
; 3 Siren: Spd / Mag; immune to Sleep; immune to Berserk and Muddle (Peace Ring)
        stat    0,1,0,0
        stat    0,0,0,1
        eff     0,0,S2_SLEEP,0,0,0,0,0,0,0
        stat    0,2,0,0
        eff     0,0,S2_BSERK|S2_MUDDLE,0,0,0,0,0,0,0
; 4 Terrato: Mag / Stm; counters (Black Belt); max HP +50% (Muscle Belt)
        stat    0,0,0,1
        stat    0,0,1,0
        eff     0,0,0,0,0,0,0,$02,0,0
        stat    0,0,0,2
        eff     0,0,0,0,$08,0,0,0,0,0
; 5 Shoat: Spd / Stm; immune to Petrify; immune to Death and Doom
        stat    0,1,0,0
        stat    0,0,1,0
        eff     0,S1_PETRIFY,0,0,0,0,0,0,0,0
        stat    0,2,0,0
        eff     0,S1_DEATH,S2_DOOM,0,0,0,0,0,0,0
; 6 Maduin: Mag / Stm; max MP +12.5% (Bard's Hat); spell damage up (Earrings)
        stat    0,0,0,1
        stat    0,0,1,0
        eff     0,0,0,0,$80,0,0,0,0,0
        stat    0,0,0,2
        eff     0,0,0,0,$02,0,0,0,0,0
; 7 Bismark: Vig / Stm; Safe at low HP (MithrilGlove); max HP +25% (Red Cap)
        stat    1,0,0,0
        stat    0,0,1,0
        eff     0,0,0,0,0,0,0,0,$02,0
        stat    2,0,0,0
        eff     0,0,0,0,$04,0,0,0,0,0
; 8 Stray: Mag / Spd; immune to Imp; steals more often (Sneak Ring)
        stat    0,0,0,1
        stat    0,1,0,0
        eff     0,S1_IMP,0,0,0,0,0,0,0,0
        stat    0,0,0,2
        eff     0,0,0,0,0,0,$01,0,0,0
; 9 Palidor: Spd / Vig; walks faster (Sprint Shoes); Float (Cherub Down)
        stat    0,1,0,0
        stat    1,0,0,0
        eff     $20,0,0,0,0,0,0,0,0,0
        stat    0,2,0,0
        eff     0,0,0,$01,0,0,0,0,0,0
; 10 Tritoch: Mag / Spd; +1 speed; immune to Dark and Petrify (Jewel Ring)
;    and max MP +50% (Crystal Orb)
        stat    0,0,0,1
        stat    0,1,0,0
        stat    0,1,0,0
        stat    0,0,0,2
        eff     0,S1_DARK|S1_PETRIFY,0,0,$40,0,0,0,0,0
; 11 Odin / Raiden: Vig / Spd; Fight never misses (Sniper Sight); Haste
;    (RunningShoes)
        stat    1,0,0,0
        stat    0,1,0,0
        eff     0,0,0,0,0,0,$10,0,0,0
        stat    2,0,0,0
        eff     0,0,0,OT6_SIG_HASTE,0,0,0,0,0,0
; 12 Bahamut: Mag / Vig; max HP +25% (Red Cap); Fight and spell damage up
;    (Hero Ring)
        stat    0,0,0,1
        stat    1,0,0,0
        eff     0,0,0,0,$04,0,0,0,0,0
        stat    0,0,0,2
        eff     0,0,0,0,$03,0,0,0,0,0
; 13 Alexandr: Stm / Vig; immune to Death; Safe (Guard Ring)
        stat    0,0,1,0
        stat    1,0,0,0
        eff     0,S1_DEATH,0,0,0,0,0,0,0,0
        stat    0,0,2,0
        eff     0,0,0,$40,0,0,0,0,0,0
; 14 Crusader: all four +1 at rungs 1, 2 and 4; max HP +25% (Red Cap);
;    two-handed grip and two weapons (Gauntlet, Genji Glove)
        stat    1,1,1,1
        stat    1,1,1,1
        eff     0,0,0,0,$04,0,0,0,0,0
        stat    1,1,1,1
        eff     0,0,0,0,0,0,0,$18,0,0
; 15 Ragnarok: Vig / Mag; max MP +25% (Minerva); vigor x1.5 (Hyper Wrist;
;    #534: Offering's four strikes halved every physical hit, forced random
;    targets and dropped criticals and weapon procs, so it was no pure upgrade)
        stat    1,0,0,0
        stat    0,0,0,1
        eff     0,0,0,0,$20,0,0,0,0,0
        stat    2,0,0,0
        eff     0,0,0,0,0,0,$80,0,0,0
; 16 Kirin: Mag / Stm; immune to Poison; Regen (Cure Ring)
        stat    0,0,0,1
        stat    0,0,1,0
        eff     0,S1_POISON,0,0,0,0,0,0,0,0
        stat    0,0,0,2
        eff     0,0,0,$02,0,0,0,0,0,0
; 17 ZoneSeek: Mag / Stm; immune to Mute; Shell (Force Shld)
        stat    0,0,0,1
        stat    0,0,1,0
        eff     0,0,S2_MUTE,0,0,0,0,0,0,0
        stat    0,0,0,2
        eff     0,0,0,$20,0,0,0,0,0,0
; 18 Carbunkl: Stm / Mag; Shell at low HP (Barrier Ring); Facet (new code)
        stat    0,0,1,0
        stat    0,0,0,1
        eff     0,0,0,0,0,0,0,0,$01,0
        stat    0,0,2,0
        none
; 19 Phantom: Spd / Mag; no back attacks (Back Guard); Image (Mirage Vest)
        stat    0,1,0,0
        stat    0,0,0,1
        eff     0,0,0,0,0,$02,0,0,0,0
        stat    0,2,0,0
        eff     0,0,0,0,0,0,0,0,0,$04
; 20 Sraphim: Stm / Mag; the member's healing +25% (new code); full revives
;    (new code): both Ot6SeraphHeal (owner, 2026-11-14: they replace Doom's
;    countdown, which Phoenix's rung 3 holds, and Kirin's Regen)
        stat    0,0,1,0
        stat    0,0,0,1
        none
        stat    0,0,2,0
        none
; 21 Golem: Stm / Vig; immune to Muddle; covers allies (True Knight)
        stat    0,0,1,0
        stat    1,0,0,0
        eff     0,0,S2_MUDDLE,0,0,0,0,0,0,0
        stat    0,0,2,0
        eff     0,0,0,0,0,0,0,$40,0,0
; 22 Unicorn: Stm / Mag; immune to Zombie; immune to Dark, Zombie and Poison
;    (Amulet)
        stat    0,0,1,0
        stat    0,0,0,1
        eff     0,S1_ZOMBIE,0,0,0,0,0,0,0,0
        stat    0,0,2,0
        eff     0,S1_DARK|S1_ZOMBIE|S1_POISON,0,0,0,0,0,0,0,0
; 23 Fenrir: Spd / Mag; more pre-emptive strikes (Gale Hairpin); immune to
;    Stop and Slow (new code)
        stat    0,1,0,0
        stat    0,0,0,1
        eff     0,0,0,0,0,$01,0,0,0,0
        stat    0,2,0,0
        none
; 24 Starlet: Mag / Spd; immune to Berserk; max MP +25% (Minerva)
        stat    0,0,0,1
        stat    0,1,0,0
        eff     0,0,S2_BSERK,0,0,0,0,0,0,0
        stat    0,0,0,2
        eff     0,0,0,0,$20,0,0,0,0,0
; 25 Phoenix: Stm / Spd; immune to Doom's countdown and Zombie; Rebirth
;    (new code)
        stat    0,0,1,0
        stat    0,1,0,0
        eff     0,S1_ZOMBIE,S2_DOOM,0,0,0,0,0,0,0
        stat    0,0,2,0
        none
        calc_size Ot6LadderTbl
.assert sizeof_Ot6LadderTbl = OT6_REC * 5 * OT6_ESPER_SLOTS, error, "Ot6LadderTbl must be 26 espers x 5 rungs"

; the menu labels for the rungs (tools/esper_ladder.py --labels)
        .include "ot6_esper_labels.inc"

; the esper page's help lines for the rungs (tools/esper_ladder.py --labels)
        .include "ot6_esper_desc.inc"
